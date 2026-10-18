-- ===================== phase15.sql =====================
-- ============================================================
-- Phase 15 (W3): LIST ADD-RULES + OTHER QUEUE + SHARED LIST CONTROL (additive, safe to run twice, paste whole into the Supabase SQL editor)
--   Needs phase8..phase14 applied first (phase11 for no_hard_delete / code_immutable is expected; created here only if missing).
--   * option_lists (existing table, no second lists table): + created_by/at, retired_by/at/reason (retire = active=false, never delete)
--   * list_defs: one row per list: add_rule open | approval | owner, allow_other, active, locked, hidden, note
--   * option_add(): the ONLY way a non-owner joins a list; the rule is enforced here (open: at once; approval: option_requests row; owner: owner / list manager only)
--     similar-name check (case / spaces / Bangla digits, contains, one-letter slip) returns the similar options so the screen can say "already exists"
--   * option_requests (+ option_request_decide), list_other_entries (+ option_other_log / option_other_resolve: add as new / merge / reject; rows are never deleted)
--   * maker <> approver; the owner is exempt only while the rule owner_self_approve is ON (default ON)
--   * grant list_manage (owner delegates: decide requests / add to owner-rule lists, all lists) and list_managers (the same, one list only)
--   * retire / reactivate / edit through option_retire / option_reactivate / option_update (reason required for retire)
--   * rules owner_self_approve (on), list_search_min (8)
--   Nothing is deleted. Direct insert / update on option_lists stays owner only (policy option_lists_owner); locked lists refuse every change by trigger.
-- ============================================================

-- ---------- (0) helpers from phase11 (same text; created only so this file also works if phase11 was skipped) ----------
create or replace function public.no_hard_delete() returns trigger
language plpgsql set search_path = public as $$
begin raise exception 'nothing is deleted – retire instead'; end $$;

-- ---------- (1) option_lists: who/when created, who/when/why retired ----------
alter table public.option_lists add column if not exists created_by uuid;
alter table public.option_lists add column if not exists created_at timestamptz;
alter table public.option_lists add column if not exists retired_by uuid;
alter table public.option_lists add column if not exists retired_at timestamptz;
alter table public.option_lists add column if not exists retired_reason text;

-- ---------- (2) list_defs ----------
create table if not exists public.list_defs (
  list_code text primary key,
  add_rule text not null default 'approval' check (add_rule in ('open', 'approval', 'owner')),
  allow_other boolean not null default true,
  active boolean not null default true,
  locked boolean not null default false,
  hidden boolean not null default false,
  note text, title_bn text, title_en text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), updated_by uuid
);
insert into public.list_defs (list_code) select distinct list_code from public.option_lists on conflict (list_code) do nothing;
alter table public.list_defs enable row level security;
drop policy if exists list_defs_read on public.list_defs;
create policy list_defs_read on public.list_defs for select to authenticated using (public.is_active());
revoke all on public.list_defs from anon, authenticated;
grant select on public.list_defs to authenticated;
drop trigger if exists audit_list_defs on public.list_defs;
create trigger audit_list_defs after insert or update on public.list_defs for each row execute function public.log_change('list_code');
drop trigger if exists list_defs_no_delete on public.list_defs;
create trigger list_defs_no_delete before delete on public.list_defs for each row execute function public.no_hard_delete();
drop trigger if exists list_defs_code_immutable on public.list_defs;
create trigger list_defs_code_immutable before update on public.list_defs for each row execute function public.code_immutable('list_code');

-- ---------- (3) rules and grants ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('owner_self_approve', 'lists', 'switch', 'true', null, null, null, null, 'মালিক নিজের অনুরোধ নিজে অনুমোদন করতে পারবেন', 'Owner নিজের request নিজে approve করতে পারবে', 'The owner may approve his / her own request',
   'বন্ধ করলে মালিকের অনুরোধও অন্য অনুমতিপ্রাপ্ত কেউ অনুমোদন করবেন', 'Off করলে owner এর request ও অন্য অনুমতিপ্রাপ্ত কেউ approve করবে', 'Off = even the owner''s own request must be decided by another person who holds list_manage', 210),
 ('list_search_min', 'lists', 'number', '8', null, null, 1, 200, 'তালিকায় এর বেশি অপশন থাকলে সার্চ বক্স দেখাবে', 'List এ এর বেশি option থাকলে search box দেখাবে', 'Show a search box when a list has more options than this', null, null, 'Used by the shared list control in forms', 211)
on conflict (key) do nothing;
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('other_pending_cap', 'lists', 'number', '50', null, null, 1, 10000, 'একজনের সর্বোচ্চ অপেক্ষমাণ "অন্যান্য" লেখা', 'একজনের maximum pending "Other" লেখা', 'Most pending "Other" write-ins one person may have', null, null, 'More are refused until the owner decides some', 212)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('list_manage', 'master', 62, 'তালিকা পরিচালনা: নতুন অপশনের অনুরোধ ও "অন্যান্য" তালিকা সিদ্ধান্ত, মালিক-নিয়মের তালিকায় যোগ', 'List পরিচালনা: নতুন option এর request ও "Other" queue সিদ্ধান্ত, owner-rule list এ যোগ', 'Manage lists: decide new-option requests and the Other queue, add to owner-rule lists', 'once', null)
on conflict (grant_code) do nothing;

-- one list only (the owner delegates a single list to a person)
create table if not exists public.list_managers (
  list_code text not null, user_id uuid not null references public.profiles(id),
  active boolean not null default true, granted_by uuid, granted_at timestamptz not null default now(),
  primary key (list_code, user_id)
);
alter table public.list_managers enable row level security;
drop policy if exists list_managers_read on public.list_managers;
create policy list_managers_read on public.list_managers for select to authenticated using (user_id = auth.uid() or public.is_owner());
revoke all on public.list_managers from anon, authenticated;
grant select on public.list_managers to authenticated;
drop trigger if exists audit_list_managers on public.list_managers;
create trigger audit_list_managers after insert or update on public.list_managers for each row execute function public.log_change('list_code,user_id');
drop trigger if exists list_managers_no_delete on public.list_managers;
create trigger list_managers_no_delete before delete on public.list_managers for each row execute function public.no_hard_delete();

-- may the caller manage this list (decide requests / Other queue, add to an owner-rule list)?
create or replace function public._list_mgr(p_list text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and (public.has_grant('list_manage')
    or exists (select 1 from public.list_managers m where m.list_code = p_list and m.user_id = auth.uid() and m.active)));
$$;

create or replace function public.list_manager_set(p_list text, p_user uuid, p_on boolean default true) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.list_defs where list_code = p_list) then raise exception 'unknown_list'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then raise exception 'unknown user'; end if;
  insert into public.list_managers (list_code, user_id, active, granted_by) values (p_list, p_user, coalesce(p_on, true), auth.uid())
    on conflict (list_code, user_id) do update set active = coalesce(p_on, true), granted_by = auth.uid(), granted_at = now();
end $$;

-- ---------- (4) name helpers (similar-name check) ----------
create or replace function public._opt_norm(p text) returns text
language sql immutable set search_path = public as $$
  -- NFC, zero-width joiners and the danda removed, precomposed য় ড় ঢ় written as base + nukta, Bangla digits as ASCII digits
  select regexp_replace(translate(replace(replace(replace(replace(replace(replace(normalize(lower(coalesce(p, '')), NFC),
      U&'\200C', ''), U&'\200D', ''), U&'\09DF', U&'\09AF\09BC'), U&'\09DC', U&'\09A1\09BC'), U&'\09DD', U&'\09A2\09BC'), U&'\0964', ''),
      '০১২৩৪৫৬৭৮৯', '0123456789'), '[[:space:].,;:!?(){}/_&+-]+', '', 'g');
$$;
-- true when the two (already normalised) names differ by one inserted / removed / changed character (both at least 4 long)
create or replace function public._opt_lev1(a text, b text) returns boolean
language plpgsql immutable set search_path = public as $$
declare la int := length(coalesce(a, '')); lb int := length(coalesce(b, '')); i int := 1;
begin
  if abs(la - lb) > 1 or least(la, lb) < 4 then return false; end if;
  if a = b then return true; end if;
  while i <= least(la, lb) and substr(a, i, 1) = substr(b, i, 1) loop i := i + 1; end loop;
  if la = lb then return substr(a, i + 1) = substr(b, i + 1);
  elsif la > lb then return substr(a, i + 1) = substr(b, i);
  else return substr(a, i) = substr(b, i + 1); end if;
end $$;

-- similar existing options (active AND retired ones, so a retired value is not re-added by accident)
create or replace function public.option_similar(p_list text, p_bn text default null, p_en text default null, p_mix text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare names text[]; r record; rn text[]; k text; res jsonb := '[]'; hit text; a text; b text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if length(coalesce(p_bn, '')) > 120 or length(coalesce(p_en, '')) > 120 or length(coalesce(p_mix, '')) > 120 then raise exception 'name_too_long'; end if;
  names := array(select x from unnest(array[public._opt_norm(p_bn), public._opt_norm(p_en), public._opt_norm(p_mix)]) x where x <> '');
  if coalesce(array_length(names, 1), 0) = 0 then return res; end if;
  for r in select * from public.option_lists where list_code = p_list order by sort loop
    rn := array(select x from unnest(array[public._opt_norm(r.label_bn), public._opt_norm(r.label_en), public._opt_norm(r.label_mix), public._opt_norm(r.value_code)]) x where x <> '');
    hit := null;
    foreach a in array names loop
      foreach b in array rn loop
        if a = b then hit := 'same';
        elsif hit is distinct from 'same' and least(length(a), length(b)) >= 3 and (position(a in b) > 0 or position(b in a) > 0) then hit := coalesce(hit, 'contains');
        elsif hit is null and public._opt_lev1(a, b) then hit := 'close'; end if;
      end loop;
    end loop;
    if hit is not null then
      res := res || jsonb_build_array(jsonb_build_object('value_code', r.value_code, 'label_bn', r.label_bn, 'label_en', r.label_en, 'label_mix', r.label_mix, 'active', r.active, 'kind', hit));
    end if;
  end loop;
  -- same first, then contains, then close; at most 8
  return coalesce((select jsonb_agg(e) from (select e from jsonb_array_elements(res) e
      order by case e->>'kind' when 'same' then 0 when 'contains' then 1 else 2 end limit 8) q), '[]'::jsonb);
end $$;

-- ---------- (5) option_lists guard: audit fields, retire stamps, locked lists ----------
create or replace function public.option_lists_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare lk boolean;
begin
  if tg_op = 'INSERT' then
    insert into public.list_defs (list_code) values (new.list_code) on conflict (list_code) do nothing;
  end if;
  select locked into lk from public.list_defs where list_code = new.list_code;
  if tg_op = 'INSERT' then
    if coalesce(lk, false) then raise exception 'list_locked'; end if;
    new.created_by := coalesce(new.created_by, auth.uid()); new.created_at := coalesce(new.created_at, now());
    if not new.active then new.retired_at := coalesce(new.retired_at, now()); new.retired_by := coalesce(new.retired_by, auth.uid()); end if;
    return new;
  end if;
  if coalesce(lk, false) and (new.label_bn is distinct from old.label_bn or new.label_en is distinct from old.label_en or new.label_mix is distinct from old.label_mix
     or new.active is distinct from old.active or new.sort is distinct from old.sort or (new.extra - 'cat_no') is distinct from (old.extra - 'cat_no')) then
    raise exception 'list_locked';
  end if;
  if old.active and not new.active then
    new.retired_at := now(); new.retired_by := auth.uid();
  elsif not old.active and new.active then
    new.retired_at := null; new.retired_by := null; new.retired_reason := null;          -- the audit log keeps the history
  end if;
  return new;
end $$;
drop trigger if exists option_lists_guard on public.option_lists;
create trigger option_lists_guard before insert or update on public.option_lists for each row execute function public.option_lists_guard();

-- ---------- (6) requests and the Other queue ----------
create table if not exists public.option_requests (
  id uuid primary key default gen_random_uuid(),
  list_code text not null, label_bn text not null, label_en text, label_mix text, extra jsonb not null default '{}',
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  requested_by uuid not null default auth.uid(), requested_at timestamptz not null default now(),
  client_id uuid, similar_opts jsonb,
  decided_by uuid, decided_at timestamptz, decision_note text, resulting_value text
);
create unique index if not exists option_requests_client_uq on public.option_requests (requested_by, client_id) where client_id is not null;
create index if not exists option_requests_list_idx on public.option_requests (list_code, status);
create table if not exists public.list_other_entries (
  id uuid primary key default gen_random_uuid(),
  list_code text not null, text text not null check (length(text) between 1 and 200),
  entered_by uuid not null default auth.uid(), entered_at timestamptz not null default now(),
  form_code text, entry_id uuid, client_id uuid, ctx jsonb not null default '{}',
  status text not null default 'pending' check (status in ('pending', 'merged', 'added', 'rejected')),
  resolved_option text, resolved_by uuid, resolved_at timestamptz, resolved_note text
);
create unique index if not exists list_other_client_uq on public.list_other_entries (entered_by, client_id) where client_id is not null;
create index if not exists list_other_list_idx on public.list_other_entries (list_code, status);
alter table public.option_requests enable row level security;
alter table public.list_other_entries enable row level security;
drop policy if exists option_requests_read on public.option_requests;
create policy option_requests_read on public.option_requests for select to authenticated using (requested_by = auth.uid() or public._list_mgr(list_code));
drop policy if exists list_other_read on public.list_other_entries;
create policy list_other_read on public.list_other_entries for select to authenticated using (entered_by = auth.uid() or public._list_mgr(list_code));
revoke all on public.option_requests, public.list_other_entries from anon, authenticated;
grant select on public.option_requests, public.list_other_entries to authenticated;
drop trigger if exists audit_option_requests on public.option_requests;
create trigger audit_option_requests after insert or update on public.option_requests for each row execute function public.log_change('id');
drop trigger if exists audit_list_other on public.list_other_entries;
create trigger audit_list_other after insert or update on public.list_other_entries for each row execute function public.log_change('id');
drop trigger if exists option_requests_no_delete on public.option_requests;
create trigger option_requests_no_delete before delete on public.option_requests for each row execute function public.no_hard_delete();
drop trigger if exists list_other_no_delete on public.list_other_entries;
create trigger list_other_no_delete before delete on public.list_other_entries for each row execute function public.no_hard_delete();

-- ---------- (7) insert one option (internal): unique, immutable value_code ----------
create or replace function public._opt_insert(p_list text, p_bn text, p_en text, p_mix text, p_extra jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare base text; vc text; n int := 1; mx int;
begin
  perform pg_advisory_xact_lock(hashtext('optlist:' || p_list));
  base := left(trim(both '_' from lower(regexp_replace(coalesce(nullif(btrim(p_en), ''), ''), '[^a-zA-Z0-9]+', '_', 'g'))), 24);
  if base is null or base = '' then base := 'o'; end if;
  vc := base;
  while vc = 'other' or exists (select 1 from public.option_lists where list_code = p_list and value_code = vc) loop n := n + 1; vc := base || '_' || n; end loop;   -- retired codes stay reserved
  select coalesce(max(sort), 0) + 1 into mx from public.option_lists where list_code = p_list;
  insert into public.option_lists (list_code, value_code, label_bn, label_en, label_mix, sort, active, extra, created_by, created_at)
    values (p_list, vc, btrim(p_bn), nullif(btrim(p_en), ''), nullif(btrim(p_mix), ''), mx, true, coalesce(p_extra, '{}'), auth.uid(), now());
  return vc;
end $$;

-- ---------- (8) option_add: THE add path; the list's rule is enforced here ----------
create or replace function public.option_add(p_list text, p_bn text, p_en text default null, p_mix text default null, p_extra jsonb default '{}',
                                             p_force boolean default false, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.list_defs; sim jsonb; same jsonb; bn text := nullif(btrim(p_bn), ''); mgr boolean; direct boolean; rq public.option_requests; vc text; rid uuid;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if bn is null or public._opt_norm(bn) = '' then raise exception 'name_required'; end if;
  if length(bn) > 120 or length(coalesce(p_en, '')) > 120 or length(coalesce(p_mix, '')) > 120 then raise exception 'name_too_long'; end if;
  if p_extra is not null and jsonb_typeof(p_extra) <> 'object' then raise exception 'bad_value'; end if;
  if not exists (select 1 from public.list_defs where list_code = p_list) and not exists (select 1 from public.option_lists where list_code = p_list) then raise exception 'unknown_list'; end if;
  insert into public.list_defs (list_code) values (p_list) on conflict (list_code) do nothing;
  select * into d from public.list_defs where list_code = p_list;
  if not d.active then raise exception 'list_inactive'; end if;
  if d.locked then raise exception 'list_locked'; end if;
  if p_client is not null then
    select * into rq from public.option_requests where requested_by = auth.uid() and client_id = p_client;
    if found then return jsonb_build_object('status', case rq.status when 'approved' then 'added' else 'requested' end, 'request_id', rq.id, 'value_code', rq.resulting_value, 'repeat', true); end if;
  end if;
  sim := public.option_similar(p_list, bn, p_en, p_mix);
  select e into same from jsonb_array_elements(sim) e where e->>'kind' = 'same' limit 1;
  if same is not null then return jsonb_build_object('status', 'exists', 'value_code', same->>'value_code', 'similar', sim); end if;
  if jsonb_array_length(sim) > 0 and not coalesce(p_force, false) then return jsonb_build_object('status', 'similar', 'similar', sim); end if;
  mgr := public._list_mgr(p_list);
  -- limits, cat_no and the like are business data: only the owner / a list manager may send them along (everybody else's extra is dropped)
  p_extra := case when mgr then coalesce(p_extra, '{}') - 'cat_no' else '{}'::jsonb end;
  direct := d.add_rule = 'open' or (d.add_rule = 'owner' and mgr) or (d.add_rule = 'approval' and public.is_owner() and public.rule_on('owner_self_approve'));
  if direct then
    vc := public._opt_insert(p_list, bn, p_en, p_mix, p_extra);
    return jsonb_build_object('status', 'added', 'value_code', vc);
  end if;
  if d.add_rule = 'owner' then raise exception 'owner_only'; end if;
  -- approval: a pending request (the same name already waiting is not filed twice)
  select * into rq from public.option_requests where list_code = p_list and status = 'pending' and public._opt_norm(label_bn) = public._opt_norm(bn) limit 1;
  if found then return jsonb_build_object('status', 'requested', 'request_id', rq.id, 'duplicate', true); end if;
  insert into public.option_requests (list_code, label_bn, label_en, label_mix, extra, client_id, similar_opts)
    values (p_list, bn, nullif(btrim(p_en), ''), nullif(btrim(p_mix), ''), coalesce(p_extra, '{}'), p_client, case when jsonb_array_length(sim) > 0 then sim end) returning id into rid;
  return jsonb_build_object('status', 'requested', 'request_id', rid);
end $$;

-- ---------- (9) decide a request: owner or list manager; maker <> approver (owner exempt only while owner_self_approve is on) ----------
create or replace function public.option_request_decide(p_id uuid, p_approve boolean, p_note text default null, p_bn text default null, p_en text default null, p_mix text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.option_requests; d public.list_defs; vc text; bn text; same text;
begin
  select * into r from public.option_requests where id = p_id;
  if not found then raise exception 'request_not_found'; end if;
  perform pg_advisory_xact_lock(hashtext('optlist:' || r.list_code));
  select * into r from public.option_requests where id = p_id for update;
  if not public._list_mgr(r.list_code) then raise exception 'not allowed'; end if;
  if r.status <> 'pending' then return jsonb_build_object('status', r.status, 'value_code', r.resulting_value, 'repeat', true); end if;
  if r.requested_by = auth.uid() and not (public.is_owner() and public.rule_on('owner_self_approve')) then raise exception 'self_approval'; end if;
  if coalesce(p_approve, false) then
    select * into d from public.list_defs where list_code = r.list_code;
    if d.locked then raise exception 'list_locked'; end if;
    if not d.active then raise exception 'list_inactive'; end if;
    bn := coalesce(nullif(btrim(p_bn), ''), r.label_bn);
    select e->>'value_code' into same from jsonb_array_elements(public.option_similar(r.list_code, bn, coalesce(p_en, r.label_en), coalesce(p_mix, r.label_mix))) e where e->>'kind' = 'same' and (e->>'active')::boolean limit 1;
    vc := coalesce(same, public._opt_insert(r.list_code, bn, coalesce(nullif(btrim(p_en), ''), r.label_en), coalesce(nullif(btrim(p_mix), ''), r.label_mix), r.extra));
    update public.option_requests set status = 'approved', decided_by = auth.uid(), decided_at = now(), decision_note = left(p_note, 300), resulting_value = vc where id = p_id;
    return jsonb_build_object('status', 'approved', 'value_code', vc);
  end if;
  update public.option_requests set status = 'rejected', decided_by = auth.uid(), decided_at = now(), decision_note = left(p_note, 300) where id = p_id;
  return jsonb_build_object('status', 'rejected');
end $$;

-- ---------- (10) Other queue ----------
create or replace function public.option_other_log(p_list text, p_text text, p_ctx jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.list_defs; tx text := nullif(btrim(p_text), ''); ex record; rid uuid; cl uuid; ent uuid; cap int; c2 jsonb := '{}'; k text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if tx is null or public._opt_norm(tx) = '' then raise exception 'name_required'; end if;
  if length(tx) > 200 then raise exception 'name_too_long'; end if;
  select * into d from public.list_defs where list_code = p_list;
  if not found then raise exception 'unknown_list'; end if;
  if not d.allow_other or not d.active then raise exception 'other_not_allowed'; end if;
  p_ctx := case when jsonb_typeof(coalesce(p_ctx, '{}')) = 'object' then coalesce(p_ctx, '{}') else '{}'::jsonb end;
  if length(p_ctx::text) > 2048 then raise exception 'ctx_too_large'; end if;
  begin cl := nullif(p_ctx->>'client_id', '')::uuid; exception when others then cl := null; end;
  begin ent := nullif(p_ctx->>'entry_id', '')::uuid; exception when others then ent := null; end;
  foreach k in array array['form_code', 'item_id', 'field', 'supplier_id'] loop       -- only these keys are kept, each a short string
    if p_ctx ? k and jsonb_typeof(p_ctx->k) = 'string' then c2 := c2 || jsonb_build_object(k, left(p_ctx->>k, 60)); end if;
  end loop;
  if cl is not null then
    select id, status into ex from public.list_other_entries where entered_by = auth.uid() and client_id = cl;
    if found then return jsonb_build_object('status', ex.status, 'id', ex.id, 'repeat', true); end if;
  end if;
  -- a text that is already a listed option is not queued: the screen uses the option
  select o.value_code into ex from public.option_lists o where o.list_code = p_list and o.active
    and public._opt_norm(tx) in (public._opt_norm(o.label_bn), public._opt_norm(o.label_en), public._opt_norm(o.label_mix)) limit 1;
  if found then return jsonb_build_object('status', 'exists', 'value_code', ex.value_code); end if;
  cap := coalesce(public.rule_num('other_pending_cap'), 50)::int;
  if (select count(*) from public.list_other_entries where entered_by = auth.uid() and status = 'pending') >= cap then raise exception 'other_queue_full'; end if;
  insert into public.list_other_entries (list_code, text, form_code, entry_id, client_id, ctx)
    values (p_list, tx, left(p_ctx->>'form_code', 20), ent, cl, c2) returning id into rid;
  return jsonb_build_object('status', 'pending', 'id', rid);
end $$;

-- p_action: 'add' (becomes a new option), 'merge' (joins p_value, an existing option), 'reject'. Equal texts waiting in the same list are decided together.
drop function if exists public.option_other_resolve(uuid, text, text, text, text, text, text);
create or replace function public.option_other_resolve(p_id uuid, p_action text, p_value text default null, p_bn text default null, p_en text default null, p_mix text default null, p_note text default null, p_force boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.list_other_entries; d public.list_defs; vc text; bn text; ownok boolean; st text; n int; o public.option_lists; sim jsonb; same jsonb;
begin
  select * into r from public.list_other_entries where id = p_id;
  if not found then raise exception 'other_not_found'; end if;
  perform pg_advisory_xact_lock(hashtext('optlist:' || r.list_code));          -- one lock per list, always taken first: no deadlock between two deciders
  select * into r from public.list_other_entries where id = p_id for update;
  if not public._list_mgr(r.list_code) then raise exception 'not allowed'; end if;
  if r.status <> 'pending' then return jsonb_build_object('status', r.status, 'value_code', r.resolved_option, 'repeat', true); end if;
  ownok := public.is_owner() and public.rule_on('owner_self_approve');
  if r.entered_by = auth.uid() and not ownok then raise exception 'self_approval'; end if;
  if p_action = 'reject' then
    st := 'rejected'; vc := null;
  elsif p_action = 'merge' then
    select * into o from public.option_lists where list_code = r.list_code and value_code = p_value;
    if not found then raise exception 'bad_option'; end if;
    if not o.active then raise exception 'option_inactive'; end if;
    st := 'merged'; vc := p_value;
  elsif p_action = 'add' then
    select * into d from public.list_defs where list_code = r.list_code;
    if d.locked then raise exception 'list_locked'; end if;
    if not d.active then raise exception 'list_inactive'; end if;
    bn := coalesce(nullif(btrim(p_bn), ''), r.text);
    if length(bn) > 120 or length(coalesce(p_en, '')) > 120 or length(coalesce(p_mix, '')) > 120 then raise exception 'name_too_long'; end if;
    sim := public.option_similar(r.list_code, bn, p_en, p_mix);
    select e into same from jsonb_array_elements(sim) e where e->>'kind' = 'same' limit 1;
    if same is not null then return jsonb_build_object('status', 'exists', 'value_code', same->>'value_code', 'similar', sim); end if;
    if jsonb_array_length(sim) > 0 and not coalesce(p_force, false) then return jsonb_build_object('status', 'similar', 'similar', sim); end if;
    vc := public._opt_insert(r.list_code, bn, nullif(btrim(p_en), ''), nullif(btrim(p_mix), ''), '{}');
    st := 'added';
  else raise exception 'bad_value'; end if;
  update public.list_other_entries set status = st, resolved_option = vc, resolved_by = auth.uid(), resolved_at = now(), resolved_note = left(p_note, 300)
    where id in (select id from public.list_other_entries where list_code = r.list_code and status = 'pending' and public._opt_norm(text) = public._opt_norm(r.text)
                   and (entered_by <> auth.uid() or ownok or id = p_id) order by id for update);
  get diagnostics n = row_count;
  return jsonb_build_object('status', st, 'value_code', vc, 'resolved', n);
end $$;

-- ---------- (11) edit / retire / reactivate (owner or list manager); retire needs a reason; nothing is deleted ----------
create or replace function public.option_retire(p_list text, p_value text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.option_lists;
begin
  if not public._list_mgr(p_list) then raise exception 'not allowed'; end if;
  if nullif(btrim(p_reason), '') is null then raise exception 'reason_required'; end if;
  select * into o from public.option_lists where list_code = p_list and value_code = p_value for update;
  if not found then raise exception 'bad_option'; end if;
  if not o.active then return jsonb_build_object('status', 'retired', 'repeat', true); end if;
  update public.option_lists set active = false, retired_reason = left(btrim(p_reason), 200) where list_code = p_list and value_code = p_value;
  return jsonb_build_object('status', 'retired');
end $$;
create or replace function public.option_reactivate(p_list text, p_value text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._list_mgr(p_list) then raise exception 'not allowed'; end if;
  update public.option_lists set active = true where list_code = p_list and value_code = p_value;
  if not found then raise exception 'bad_option'; end if;
  return jsonb_build_object('status', 'active');
end $$;
drop function if exists public.option_update(text, text, text, text, text);
create or replace function public.option_update(p_list text, p_value text, p_bn text, p_en text default null, p_mix text default null, p_extra jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._list_mgr(p_list) then raise exception 'not allowed'; end if;
  if nullif(btrim(p_bn), '') is null then raise exception 'name_required'; end if;
  if length(p_bn) > 120 or length(coalesce(p_en, '')) > 120 or length(coalesce(p_mix, '')) > 120 then raise exception 'name_too_long'; end if;
  if p_extra is not null and (jsonb_typeof(p_extra) <> 'object' or not public.is_owner()) then raise exception 'not allowed'; end if;   -- limits and the like: owner only
  update public.option_lists set label_bn = btrim(p_bn), label_en = nullif(btrim(p_en), ''), label_mix = nullif(btrim(p_mix), ''),
      extra = case when p_extra is null then extra else jsonb_strip_nulls((extra - 'limit_month') || (p_extra - 'cat_no')) end
    where list_code = p_list and value_code = p_value;
  if not found then raise exception 'bad_option'; end if;
  return jsonb_build_object('status', 'saved');
end $$;
create or replace function public.option_reorder(p_list text, p_codes text[]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare i int := 0; c text;
begin
  if not public._list_mgr(p_list) then raise exception 'not allowed'; end if;
  foreach c in array coalesce(p_codes, '{}') loop
    i := i + 1;
    update public.option_lists set sort = i where list_code = p_list and value_code = c;
  end loop;
  return jsonb_build_object('status', 'saved', 'n', i);
end $$;

-- owner edits the list's own settings (rule, Other on/off, active, locked, hidden, note, titles)
create or replace function public.list_def_set(p_list text, p_patch jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k text; v jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then raise exception 'bad_value'; end if;
  if not exists (select 1 from public.option_lists where list_code = p_list) and not exists (select 1 from public.list_defs where list_code = p_list) then raise exception 'unknown_list'; end if;
  insert into public.list_defs (list_code) values (p_list) on conflict (list_code) do nothing;
  for k, v in select * from jsonb_each(p_patch) loop
    if k = 'add_rule' then
      if jsonb_typeof(v) <> 'string' or (v #>> '{}') not in ('open', 'approval', 'owner') then raise exception 'bad_value'; end if;
      update public.list_defs set add_rule = v #>> '{}' where list_code = p_list;
    elsif k in ('allow_other', 'active', 'locked', 'hidden') then
      if jsonb_typeof(v) <> 'boolean' then raise exception 'bad_value'; end if;
      execute format('update public.list_defs set %I = $1 where list_code = $2', k) using (v #>> '{}')::boolean, p_list;
    elsif k in ('note', 'title_bn', 'title_en') then
      if jsonb_typeof(v) not in ('string', 'null') then raise exception 'bad_value'; end if;
      execute format('update public.list_defs set %I = left(nullif(btrim($1), ''''), 200) where list_code = $2', k) using v #>> '{}', p_list;
    else raise exception 'bad_value'; end if;
  end loop;
  update public.list_defs set updated_at = now(), updated_by = auth.uid() where list_code = p_list;
  return (select to_jsonb(x) from public.list_defs x where list_code = p_list);
end $$;

-- ---------- (12) counts for the Needs-you badge (only for people who may decide) ----------
create or replace function public.list_queue_counts() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb := '{"requests":0,"other":0,"lists":{}}'; r record; rq int := 0; ot int := 0;
begin
  if not public.is_active() then return res; end if;
  for r in select d.list_code,
      (select count(*) from public.option_requests q where q.list_code = d.list_code and q.status = 'pending') as rq,
      (select count(*) from public.list_other_entries o where o.list_code = d.list_code and o.status = 'pending') as ot
    from public.list_defs d loop
    if (r.rq > 0 or r.ot > 0) and public._list_mgr(r.list_code) then
      rq := rq + r.rq; ot := ot + r.ot;
      res := jsonb_set(res, array['lists', r.list_code], jsonb_build_object('requests', r.rq, 'other', r.ot));
    end if;
  end loop;
  return jsonb_set(jsonb_set(res, '{requests}', to_jsonb(rq)), '{other}', to_jsonb(ot));
end $$;

-- ---------- (13) privileges: authenticated only; internal helpers not callable from outside ----------
revoke all on function public._opt_insert(text, text, text, text, jsonb), public.option_lists_guard() from public, anon, authenticated;
revoke all on function public.option_add(text, text, text, text, jsonb, boolean, uuid), public.option_request_decide(uuid, boolean, text, text, text, text),
  public.option_other_log(text, text, jsonb), public.option_other_resolve(uuid, text, text, text, text, text, text, boolean), public.option_retire(text, text, text),
  public.option_reactivate(text, text), public.option_update(text, text, text, text, text, jsonb), public.option_reorder(text, text[]), public.list_def_set(text, jsonb),
  public.list_manager_set(text, uuid, boolean), public.list_queue_counts(), public.option_similar(text, text, text, text), public._list_mgr(text),
  public._opt_norm(text), public._opt_lev1(text, text) from public, anon;
grant execute on function public.option_add(text, text, text, text, jsonb, boolean, uuid), public.option_request_decide(uuid, boolean, text, text, text, text),
  public.option_other_log(text, text, jsonb), public.option_other_resolve(uuid, text, text, text, text, text, text, boolean), public.option_retire(text, text, text),
  public.option_reactivate(text, text), public.option_update(text, text, text, text, text, jsonb), public.option_reorder(text, text[]), public.list_def_set(text, jsonb),
  public.list_manager_set(text, uuid, boolean), public.list_queue_counts(), public.option_similar(text, text, text, text), public._list_mgr(text),
  public._opt_norm(text), public._opt_lev1(text, text) to authenticated;

-- ===================== phase16.sql =====================
-- ============================================================
-- Phase 16 (W4): LOCATIONS (kind / model / status / hub / setup steps / pause / close) + CONTROL CENTER counts
--                + SETTINGS SHEET 0-1 VERSIONS (get_limit)   (additive, safe to run twice, paste whole into the Supabase SQL editor)
--   Needs phase8..phase14 applied first. Does NOT need phase15 (list_defs / list_queue_counts are used only when they exist).
--   * locations (existing table): + kind, model, status (planned | setting_up | live | paused | closed), supplied_by, planned_opening, hub_functions,
--     note, paused_reason/by/at, closed_reason/by/at, status_by/at, created_by/at.  Existing 7 rows: kind/model/status filled ONCE
--     (all live, except the stopped Mujgunni factory `mishti_factory` = paused).  Codes stay immutable (phase11); nothing is deleted.
--   * option list 'location_models' (A own place, B franchise, C funded; B and C start retired = hidden, the owner switches them on in Lists)
--   * location_setup_steps: 17 steps per new place (read from Build command 5), gate: steps 1-15 (optional ones aside) before 16 (start)
--   * RPC location_save (edit / add a new place; code = slug of the name, unique), location_set_status (pause / resume / close with checklist
--     warnings; the owner may override), location_set_active, location_step_set, location_steps_init, location_close_check
--   * grants location_manage, head_management, settings_approve (owner delegates; has_grant()); rules location_block_when_paused (ON),
--     location_start_first_of_month (OFF), block_on_missing_limit (OFF), owner_self_approve (ON, same key as phase15)
--   * a paused / closed place refuses NEW entries and sales on the server (triggers on entries and sales); reading stays open
--   * settings_sheets + settings_values: versions of the Location Settings Sheet 0-1, seeded as approved version 1 from location_settings;
--     draft -> approve (maker <> approver, the owner exempt while owner_self_approve is ON); get_limit(loc, key, date) returns the value in force
--     on that date or NULL (= Data needed).  location_settings stays readable and is written through, so every old screen keeps working;
--     an edit through the old screen makes a new (auto) version.
--   * control_counts(): the merged "Needs you" counts for the Control Center / Home (only what the caller may decide)
-- ============================================================

-- ---------- (0) helpers (same text as phase11 / phase15; created only so this file also works alone) ----------
create or replace function public.no_hard_delete() returns trigger
language plpgsql set search_path = public as $$
begin raise exception 'nothing is deleted – retire instead'; end $$;

-- ---------- (1) locations: new columns ----------
alter table public.locations add column if not exists kind text;
alter table public.locations add column if not exists model text;
alter table public.locations add column if not exists status text not null default 'live';
alter table public.locations add column if not exists supplied_by int references public.locations(id);
alter table public.locations add column if not exists planned_opening date;
alter table public.locations add column if not exists hub_functions boolean not null default false;
alter table public.locations add column if not exists note text;
alter table public.locations add column if not exists paused_reason text;
alter table public.locations add column if not exists paused_by uuid;
alter table public.locations add column if not exists paused_at timestamptz;
alter table public.locations add column if not exists closed_reason text;
alter table public.locations add column if not exists closed_by uuid;
alter table public.locations add column if not exists closed_at timestamptz;
alter table public.locations add column if not exists status_by uuid;
alter table public.locations add column if not exists status_at timestamptz;
alter table public.locations add column if not exists created_by uuid;
alter table public.locations add column if not exists created_at timestamptz default now();
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'locations_kind_chk') then
    alter table public.locations add constraint locations_kind_chk check (kind is null or kind in ('showroom', 'factory', 'godown', 'hub', 'online', 'other'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'locations_status_chk') then
    alter table public.locations add constraint locations_status_chk check (status in ('planned', 'setting_up', 'live', 'paused', 'closed'));
  end if;
end $$;

-- the seven existing places: filled ONCE (kind is null only before the first run), never overwritten afterwards
update public.locations set
  kind = case code when 'cake_factory' then 'factory' when 'mishti_factory' then 'factory' when 'godown' then 'godown' else 'showroom' end,
  model = 'A',
  hub_functions = (code = 'main'),
  status = case when code = 'mishti_factory' or not is_active then 'paused' else 'live' end,
  paused_reason = case when code = 'mishti_factory' then 'বন্ধ মুজগুন্নি কারখানা (যন্ত্র রাখা) / stopped Mujgunni factory'
                       when not is_active then 'inactive before phase16' end,
  paused_at = case when code = 'mishti_factory' or not is_active then now() end,
  status_at = now()
where kind is null and code in ('main', 'branch2', 'mishti_bari', 'al_cakes', 'cake_factory', 'mishti_factory', 'godown');
-- any other pre-existing row (added by SQL by hand): showroom, own place, live unless inactive
update public.locations set kind = 'showroom', model = 'A', status = case when is_active then 'live' else 'paused' end, status_at = now()
where kind is null;

-- ---------- (2) rules and grants ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('location_block_when_paused', 'locations', 'switch', 'true', null, null, null, null, 'বিরতি/বন্ধ লোকেশনে নতুন এন্ট্রি ও বিক্রি আটকানো', 'Paused/closed location-এ নতুন entry ও sale আটকানো', 'Block new entries and sales at a paused or closed place',
   'চালু থাকলে সার্ভারই নতুন এন্ট্রি/বিক্রি নেবে না; দেখা (রিপোর্ট) চলবে', 'On থাকলে server নতুন entry/sale নেবে না; দেখা চলবে', 'When on the server refuses new entries and sales; reading and reports stay open', 80),
 ('location_start_first_of_month', 'locations', 'switch', 'false', null, null, null, null, 'নতুন লোকেশন শুধু মাসের ১ তারিখে চালু (ধাপ ১৬)', 'নতুন location শুধু মাসের ১ তারিখে চালু (step 16)', 'A new place may start only on the 1st of a month (step 16)',
   'বন্ধ রাখলে যেকোনো দিনে চালু করা যাবে', 'Off থাকলে যেকোনো দিনে start', 'Off = any day', 81),
 ('block_on_missing_limit', 'locations', 'switch', 'false', null, null, null, null, 'সীমা ফাঁকা থাকলে ফর্ম জমা আটকানো', 'Limit ফাঁকা থাকলে Form জমা আটকানো', 'Block a form submit while a limit it needs is blank (Data needed)',
   'ডিফল্ট বন্ধ: ফাঁকা থাকলে শুধু ‘তথ্য লাগবে’ দেখাবে', 'Default Off: শুধু ‘Data needed’ দেখাবে', 'Default off: only shows Data needed', 82),
 ('owner_self_approve', 'lists', 'switch', 'true', null, null, null, null, 'মালিক নিজের অনুরোধ নিজে অনুমোদন করতে পারবেন', 'Owner নিজের request নিজে approve করতে পারবেন', 'Owner may approve their own request',
   'বন্ধ করলে মালিকের অনুরোধও অন্য অনুমতিপ্রাপ্ত কেউ অনুমোদন করবেন', 'Off করলে owner-এর request অন্য কেউ approve করবেন', 'When off, the owner''s own requests need another approver', 50)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('location_manage', 'master', 63, 'লোকেশন পরিচালনা: সম্পাদনা, নতুন শোরুম, বিরতি/বন্ধ, সেটআপ ধাপ', 'Location পরিচালনা: edit, নতুন showroom, pause/close, setup step', 'Manage locations: edit, add a showroom, pause / close, setup steps', 'window', null),
 ('head_management', 'master', 64, 'হেড ম্যানেজমেন্ট: কন্ট্রোল সেন্টারের অংশ (লোকেশন, সীমা, তালিকা) — খরচ/বেতন ছাড়া', 'Head management: Control Center-এর অংশ (location, limit, list) — cost/salary ছাড়া', 'Head management: part of the Control Center (places, limits, lists), no costs or salaries', 'window', null),
 ('settings_approve', 'settings', 65, 'সেটিংস শিট (০-১) এর নতুন সংস্করণ অনুমোদন', 'Settings sheet (0-1) এর নতুন version approve', 'Approve a new version of the settings sheet (0-1)', 'window', null)
on conflict (grant_code) do nothing;

-- who may do what (server side)
create or replace function public._loc_mgr() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and (public.has_grant('location_manage') or public.has_grant('head_management')));
$$;
create or replace function public._sheet_viewer() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and (public.has_grant('location_manage') or public.has_grant('head_management') or public.has_grant('settings_approve')));
$$;

-- location-scoped versions: a grant given for ONE place (user_grants.location_id) counts for that place only
create or replace function public._loc_mgr_at(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and (public.has_grant('location_manage', p_loc) or public.has_grant('head_management', p_loc)));
$$;
create or replace function public._sheet_viewer_at(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and (public.has_grant('location_manage', p_loc) or public.has_grant('head_management', p_loc) or public.has_grant('settings_approve', p_loc)));
$$;

-- ---------- (3) option list 'location_models' (editable in #/lists) ----------
insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort, active)
select 'location_models', v.c, v.bn, v.mx, v.en, v.s, v.a from (values
  ('A', 'ক — নিজস্ব স্থান', 'A — Own place', 'A — Own place', 1, true),
  ('B', 'খ — ফ্র্যাঞ্চাইজ (এখনও সিদ্ধান্ত হয়নি)', 'B — Franchise (not decided yet)', 'B — Franchise (not decided yet)', 2, false),
  ('C', 'গ — অংশীদারি/ফান্ডেড (এখনও সিদ্ধান্ত হয়নি)', 'C — Funded (not decided yet)', 'C — Funded partner (not decided yet)', 3, false)) as v(c, bn, mx, en, s, a)
where not exists (select 1 from public.option_lists o where o.list_code = 'location_models' and o.value_code = v.c);
do $$ begin
  if to_regclass('public.list_defs') is not null then
    insert into public.list_defs (list_code, add_rule) values ('location_models', 'owner') on conflict (list_code) do nothing;
  end if;
end $$;

-- ---------- (4) setup steps ----------
create table if not exists public.location_setup_steps (
  location_id int not null references public.locations(id),
  step_no int not null check (step_no between 1 and 17),
  title_bn text not null, title text not null,
  owner_role text, owner_yes boolean not null default false, optional boolean not null default false,
  done boolean not null default false, done_by uuid, done_at timestamptz, note text,
  primary key (location_id, step_no)
);
alter table public.location_setup_steps enable row level security;
drop policy if exists loc_steps_read on public.location_setup_steps;
create policy loc_steps_read on public.location_setup_steps for select to authenticated using (public._loc_mgr_at(location_id));
revoke all on public.location_setup_steps from public, anon, authenticated;
grant select on public.location_setup_steps to authenticated;
drop trigger if exists audit_loc_steps on public.location_setup_steps;
create trigger audit_loc_steps after insert or update on public.location_setup_steps for each row execute function public.log_change('location_id,step_no');
drop trigger if exists loc_steps_no_delete on public.location_setup_steps;
create trigger loc_steps_no_delete before delete on public.location_setup_steps for each row execute function public.no_hard_delete();

-- the 17 steps of Build command 5 (owner_yes = the step marked * : needs the owner's yes)
create or replace function public._loc_steps_def() returns table (n int, bn text, en text, who text, yes boolean, opt boolean)
language sql immutable set search_path = public as $$
  select * from (values
   (1,  'সিদ্ধান্ত: জায়গা, ভাড়া, বাজেট, প্রত্যাশিত বিক্রি, কোন কারখানা সরবরাহ করবে', 'Decide: place, rent, budget, expected sales, which factory supplies it', 'Owner', true, false),
   (2,  'লোকেশন কোড ও লোকেশন তালিকায় একটি সারি', 'Location code and a row in the location list', 'Daily-accounts reconciliation staff', false, false),
   (3,  'পরের ছাপা পর্যন্ত প্রতিটি ফর্মের লোকেশন বক্সে "অন্যান্য"-এ নাম লেখা', 'Name the place under Other on every form''s location box until the next print', 'Head management', false, false),
   (4,  'এই জায়গার আইটেম তালিকা ও বর্তমান মূল্য তালিকা', 'Item list and current price list for this place', 'Head management', false, false),
   (5,  'ডিউটি স্লট: ম্যানেজার, ব্যাকআপ, রাতের দ্বিতীয় গণনাকারী; একই ব্যক্তি দুই স্লটে নয় (ফর্ম ০২-৭)', 'Duty slots: manager, backup, night second counter; the same person is never in two slots (form 02-7)', 'Owner names, head management enters', true, false),
   (6,  'নতুন ডিউটি-ধারকের দক্ষতা যাচাই (ফর্ম ০২-৮)', 'Skill check of the new duty holder (form 02-8)', 'A checker from the list', false, false),
   (7,  'নিয়োগ ও নিবন্ধন (ফর্ম ০২-৪)', 'Hiring and registration (form 02-4)', 'Head management', false, false),
   (8,  'একজন-মানুষের ফাঁক পূরণ: রাতের দ্বিতীয় গণনা, সাক্ষী, শিফট হস্তান্তর (ফর্ম ০২-৭, ১১-১)', 'Cover the one-person gap: night second count, witness, shift handover (forms 02-7, 11-1)', 'Owner', true, false),
   (9,  'ক্যাশ বক্স: ড্রয়ার ফ্লোট ও ইমপ্রেস আলাদা; ব্যবসার মোবাইল-মানি নম্বর (০-১ সারি ১, ২)', 'Cash boxes: drawer float and imprest kept apart; the business mobile-money number (0-1 rows 1 and 2)', 'Head management', false, false),
   (10, 'এই জায়গার নিজস্ব মাপে লোকেশন সেটিংস শিট ০-১ (হেড ম্যানেজমেন্ট পূরণ, মালিক অনুমোদন)', 'Location Settings Sheet 0-1 at this place''s own measures (head management fills, owner approves)', 'Head management fills, owner approves', true, false),
   (11, 'যন্ত্রপাতি ও জায়গা: ফ্রিজ থার্মোমিটার, ওজন পরীক্ষার বাটখারা, হস্তান্তরের জায়গা, চাবির দায়িত্ব (০-১ সারি ১১, ১৩, ৩০)', 'Equipment and places: fridge thermometer, scale test weight, handover place, key duty (0-1 rows 11, 13, 30)', 'Head management', false, false),
   (12, 'কাগজের সেট ছাপা, সিরিয়াল সহ; প্রতিটি বইয়ের প্রথম নম্বর লেখা', 'Print the paper set with serial numbers; write the first number of each book', 'Head management', false, false),
   (13, 'সরবরাহ মানচিত্র: কোন কারখানা, কত ট্রিপ, হস্তান্তর বিন্দু (সরবরাহ মানচিত্র নিশ্চিত না হওয়া পর্যন্ত ঐচ্ছিক)', 'Supply map: which factory, how many trips, the handover point (optional until the supply map is confirmed)', 'Head management', false, true),
   (14, 'প্রশিক্ষণ, এক কাগজ এক করে (ফর্ম ০২-৮)', 'Training, one paper at a time (form 02-8)', 'Head management', false, false),
   (15, 'আগের রাতে উদ্বোধনী গণনা (ফর্ম ০৪-৩, ০৪-৪)', 'Opening count the night before (forms 04-3, 04-4)', 'Two counters', false, false),
   (16, 'মাসের ১ তারিখে চালু: প্রথম সপ্তাহ, এক মাসের পাস/ফেল, তারপর ৭, ৩০, ৯০ দিনের পর্যালোচনা', 'Start on the 1st: first week, then one month pass or fail, then 7, 30 and 90 day reviews', 'Everyone at the place', false, false),
   (17, 'অন্য জায়গার সাথে একই সংখ্যায় সাপ্তাহিক তুলনা (ফর্ম ০১-১, নতুন কলাম)', 'Weekly comparison with the other places on the same figures (form 01-1, a new column)', 'Head management', false, false)
  ) as v(n, bn, en, who, yes, opt);
$$;

create or replace function public._loc_steps_seed(p_loc int) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.location_setup_steps (location_id, step_no, title_bn, title, owner_role, owner_yes, optional)
  select p_loc, d.n, d.bn, d.en, d.who, d.yes, d.opt from public._loc_steps_def() d
  on conflict (location_id, step_no) do nothing;
end $$;

-- ---------- (5) location RPCs ----------
create or replace function public._slug(p text) returns text
language sql immutable set search_path = public as $$
  select left(trim(both '_' from regexp_replace(lower(coalesce(p, '')), '[^a-z0-9]+', '_', 'g')), 30);
$$;

-- status moves are enforced by the DATABASE (any writer, also plain SQL): closed is final
create or replace function public._loc_status_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.status is distinct from old.status then
    if old.status = 'closed' then raise exception 'closed_is_final'; end if;
    if not ((old.status, new.status) in (('planned', 'setting_up'), ('planned', 'live'), ('planned', 'closed'), ('setting_up', 'planned'), ('setting_up', 'live'), ('setting_up', 'paused'), ('setting_up', 'closed'),
                                         ('live', 'paused'), ('live', 'closed'), ('paused', 'live'), ('paused', 'closed'))) then
      raise exception 'bad_transition:%->%', old.status, new.status;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists locations_status_guard on public.locations;
create trigger locations_status_guard before update on public.locations for each row execute function public._loc_status_guard();

-- edit (p_id given) or add (p_id null) a place.  p_patch keys: name_bn name_mix name_en kind model supplied_by planned_opening hub_functions note sort code (add only)
create or replace function public.location_save(p_id int, p_patch jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r public.locations; v_code text; base text; n int := 1; v text; k text; sb int; hops int := 0; nid int; po date; sortv int; hubv boolean;
  newname_bn text; newname_en text;
begin
  if p_id is null then
    if not public._loc_mgr() then raise exception 'not allowed'; end if;
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
    if exists (select 1 from public.locations x where lower(btrim(x.name_bn)) = lower(newname_bn) or (newname_en is not null and lower(btrim(coalesce(x.name_en, ''))) = lower(newname_en))) then raise exception 'name_in_use'; end if;
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
    insert into public.locations (code, name_bn, name_mix, name_en, sort, is_active, kind, model, status, supplied_by, planned_opening, hub_functions, note, created_by, created_at, status_by, status_at)
    values (v_code, newname_bn, nullif(btrim(coalesce(p_patch->>'name_mix', '')), ''), newname_en,
            coalesce(sortv, (select coalesce(max(x.sort), 0) + 1 from public.locations x)), true,
            coalesce(nullif(p_patch->>'kind', ''), 'showroom'), coalesce(nullif(p_patch->>'model', ''), 'A'), 'planned', sb, po,
            coalesce(hubv, false), nullif(p_patch->>'note', ''), auth.uid(), now(), auth.uid(), now())
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
end $$;

-- things that should be settled before a place stops: open credit, stock on hand, open entries, transfers on the way
create or replace function public.location_close_check(p_id int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare dues numeric := 0; stk numeric := 0; stki int := 0; oe int := 0; tr int := 0; w jsonb := '[]';
begin
  if not public._loc_mgr_at(p_id) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.locations where id = p_id) then raise exception 'unknown_location'; end if;
  select coalesce(sum(due_amount), 0) into dues from public.sales where location_id = p_id and status = 'done' and due_amount > 0;
  select coalesce(sum(qty), 0), count(*) into stk, stki from public.stock_balance where location_id = p_id and qty > 0;
  select count(*) into oe from public.entries where location_id = p_id and status in ('draft', 'submitted');
  select count(*) into tr from public.stock_transfers where status = 'sent' and (from_location_id = p_id or to_location_id = p_id);
  if dues > 0 then w := w || jsonb_build_object('code', 'open_dues', 'amount', dues); end if;
  if stki > 0 then w := w || jsonb_build_object('code', 'stock_on_hand', 'items', stki, 'qty', stk); end if;
  if oe > 0 then w := w || jsonb_build_object('code', 'open_entries', 'count', oe); end if;
  if tr > 0 then w := w || jsonb_build_object('code', 'transfers_in_transit', 'count', tr); end if;
  return jsonb_build_object('warnings', w, 'ok', jsonb_array_length(w) = 0);
end $$;

-- steps that block the start (1..15 except optional ones)
create or replace function public._loc_open_steps(p_id int) returns int[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(step_no order by step_no), '{}') from public.location_setup_steps
  where location_id = p_id and step_no <= 15 and not done and not optional;
$$;

-- pause / resume / start / close.  Returns {ok:false, warnings:[...]} when a checklist is open and p_override is not set; only the owner may override.
create or replace function public.location_set_status(p_id int, p_status text, p_reason text default null, p_override boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.locations; w jsonb := '[]'; open_steps int[]; cc jsonb; okmove boolean := false; reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not public._loc_mgr_at(p_id) then raise exception 'not allowed'; end if;
  if p_status not in ('planned', 'setting_up', 'live', 'paused', 'closed') then raise exception 'bad_status'; end if;
  if reason is not null and length(reason) > 500 then raise exception 'too_long:reason'; end if;
  select * into r from public.locations where id = p_id for update;
  if not found then raise exception 'unknown_location'; end if;
  if r.status = p_status then return jsonb_build_object('ok', true, 'status', r.status, 'unchanged', true); end if;
  if r.status = 'closed' then raise exception 'closed_is_final'; end if;
  okmove := (r.status, p_status) in (('planned', 'setting_up'), ('planned', 'live'), ('planned', 'closed'), ('setting_up', 'planned'), ('setting_up', 'live'), ('setting_up', 'paused'), ('setting_up', 'closed'),
                                     ('live', 'paused'), ('live', 'closed'), ('paused', 'live'), ('paused', 'closed'));
  if not okmove then raise exception 'bad_transition:%->%', r.status, p_status; end if;
  if p_status in ('paused', 'closed') and reason is null then raise exception 'reason_required'; end if;

  if p_status = 'live' and r.status in ('planned', 'setting_up') then
    open_steps := public._loc_open_steps(p_id);
    if coalesce(array_length(open_steps, 1), 0) > 0 then w := w || jsonb_build_object('code', 'setup_steps_open', 'steps', to_jsonb(open_steps)); end if;
    if public.rule_on('location_start_first_of_month') and extract(day from (now() at time zone 'Asia/Dhaka')::date) <> 1 then w := w || jsonb_build_object('code', 'not_first_of_month'); end if;
  elsif p_status = 'closed' then
    cc := public.location_close_check(p_id); w := cc->'warnings';
  end if;
  if jsonb_array_length(w) > 0 then
    if not coalesce(p_override, false) then return jsonb_build_object('ok', false, 'warnings', w, 'status', r.status); end if;
    if not public.is_owner() then raise exception 'owner_override_only'; end if;
    if reason is null then raise exception 'reason_required'; end if;
  end if;

  update public.locations set status = p_status, status_by = auth.uid(), status_at = now(),
    paused_reason = case when p_status = 'paused' then reason else paused_reason end,
    paused_by = case when p_status = 'paused' then auth.uid() else paused_by end,
    paused_at = case when p_status = 'paused' then now() else paused_at end,
    closed_reason = case when p_status = 'closed' then reason else closed_reason end,
    closed_by = case when p_status = 'closed' then auth.uid() else closed_by end,
    closed_at = case when p_status = 'closed' then now() else closed_at end,
    is_active = case when p_status = 'closed' then false else is_active end
  where id = p_id;
  return jsonb_build_object('ok', true, 'status', p_status, 'overridden', jsonb_array_length(w) > 0, 'warnings', w);
end $$;

-- switch a place active / inactive (a lighter switch than pause).  Closed places stay inactive.
create or replace function public.location_set_active(p_id int, p_active boolean) returns void
language plpgsql security definer set search_path = public as $$
declare st text;
begin
  if not public._loc_mgr_at(p_id) then raise exception 'not allowed'; end if;
  select status into st from public.locations where id = p_id;
  if not found then raise exception 'unknown_location'; end if;
  if st = 'closed' and coalesce(p_active, true) then raise exception 'closed_is_final'; end if;
  update public.locations set is_active = coalesce(p_active, true) where id = p_id;
end $$;

-- make sure a place has its 17 steps (for an older place the owner wants to run the checklist on)
create or replace function public.location_steps_init(p_id int) returns int
language plpgsql security definer set search_path = public as $$
begin
  if not public._loc_mgr_at(p_id) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.locations where id = p_id) then raise exception 'unknown_location'; end if;
  perform public._loc_steps_seed(p_id);
  return (select count(*) from public.location_setup_steps where location_id = p_id);
end $$;

-- tick / untick one step.  Steps marked * (owner_yes) are the owner's only; step 16 needs 1-15; ticking 16 starts a place that is in setup
-- (a PAUSED place is never resumed silently: resume it on purpose).
create or replace function public.location_step_set(p_loc int, p_step int, p_done boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.location_setup_steps; st jsonb; open_steps int[]; cur text;
begin
  if not public._loc_mgr_at(p_loc) then raise exception 'not allowed'; end if;
  if p_note is not null and length(p_note) > 500 then raise exception 'too_long:note'; end if;
  select * into s from public.location_setup_steps where location_id = p_loc and step_no = p_step for update;
  if not found then raise exception 'unknown_step'; end if;
  select status into cur from public.locations where id = p_loc;
  if cur = 'closed' then raise exception 'closed_is_final'; end if;
  if s.owner_yes and not public.is_owner() then raise exception 'owner_only_step'; end if;
  if coalesce(p_done, true) and p_step = 16 then
    if cur = 'paused' then raise exception 'place_paused'; end if;
    open_steps := public._loc_open_steps(p_loc);
    if coalesce(array_length(open_steps, 1), 0) > 0 then raise exception 'steps_open:%', array_to_string(open_steps, ','); end if;
  end if;
  update public.location_setup_steps set done = coalesce(p_done, true),
    done_by = case when coalesce(p_done, true) then auth.uid() end, done_at = case when coalesce(p_done, true) then now() end,
    note = coalesce(nullif(btrim(p_note), ''), note)
  where location_id = p_loc and step_no = p_step;
  if coalesce(p_done, true) and p_step = 16 and cur in ('planned', 'setting_up') then
    st := public.location_set_status(p_loc, 'live', 'step 16: started', false);
    if (st->>'ok')::boolean is not true then
      update public.location_setup_steps set done = false, done_by = null, done_at = null where location_id = p_loc and step_no = 16;
      return jsonb_build_object('ok', false, 'warnings', st->'warnings');
    end if;
  elsif coalesce(p_done, true) and cur = 'planned' then
    update public.locations set status = 'setting_up', status_by = auth.uid(), status_at = now() where id = p_loc and status = 'planned';
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- ---------- (6) paused / closed places refuse NEW entries and sales ----------
-- Real work that happened BEFORE the status change but reaches the server late (back-dated entry, offline sale synced later) is still accepted:
-- only rows dated on / after the status change are refused.  The owner can open a short window for late work (location_block_override, logged).
create table if not exists public.location_block_overrides (
  id bigserial primary key,
  location_id int not null references public.locations(id),
  reason text not null, created_by uuid, created_at timestamptz not null default now(), expires_at timestamptz not null
);
alter table public.location_block_overrides enable row level security;
drop policy if exists loc_block_ov_read on public.location_block_overrides;
create policy loc_block_ov_read on public.location_block_overrides for select to authenticated using (public.is_owner());
revoke all on public.location_block_overrides from public, anon, authenticated;
grant select on public.location_block_overrides to authenticated;
drop trigger if exists audit_loc_block_ov on public.location_block_overrides;
create trigger audit_loc_block_ov after insert or update on public.location_block_overrides for each row execute function public.log_change('id');
drop trigger if exists loc_block_ov_no_delete on public.location_block_overrides;
create trigger loc_block_ov_no_delete before delete on public.location_block_overrides for each row execute function public.no_hard_delete();

create or replace function public.location_block_override(p_loc int, p_reason text, p_minutes int default 30) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare e timestamptz;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null then raise exception 'reason_required'; end if;
  if not (coalesce(p_minutes, 0) between 1 and 240) then raise exception 'bad_number'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'unknown_location'; end if;
  e := now() + make_interval(mins => p_minutes);
  insert into public.location_block_overrides (location_id, reason, created_by, expires_at) values (p_loc, left(btrim(p_reason), 300), auth.uid(), e);
  return e;
end $$;

create or replace function public._loc_block_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare st text; sat timestamptz;
begin
  select status, status_at into st, sat from public.locations where id = new.location_id;
  if st in ('paused', 'closed') and public.rule_on('location_block_when_paused') then
    if sat is not null then
      if tg_table_name = 'entries' and (to_jsonb(new) ->> 'entry_date')::date < (sat at time zone 'Asia/Dhaka')::date then return new; end if;
      if tg_table_name = 'sales' and (to_jsonb(new) ->> 'sold_at')::timestamptz < sat then return new; end if;
    end if;
    if exists (select 1 from public.location_block_overrides o where o.location_id = new.location_id and o.expires_at > now()) then return new; end if;
    raise exception 'location_paused:%', st;
  end if;
  return new;
end $$;
drop trigger if exists entries_loc_guard on public.entries;
create trigger entries_loc_guard before insert on public.entries for each row execute function public._loc_block_guard();
drop trigger if exists sales_loc_guard on public.sales;
create trigger sales_loc_guard before insert on public.sales for each row execute function public._loc_block_guard();

-- stock transfers INTO, purchase bills / wastage requests AT a CLOSED place are refused (a paused place only warns: the screens show its status).
create or replace function public._loc_closed_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare lid int := nullif(to_jsonb(new) ->> tg_argv[0], '')::int; st text;
begin
  select status into st from public.locations where id = lid;
  if st = 'closed' and public.rule_on('location_block_when_paused')
     and not exists (select 1 from public.location_block_overrides o where o.location_id = lid and o.expires_at > now()) then raise exception 'location_paused:closed'; end if;
  return new;
end $$;
do $$ declare t record; begin
  for t in select * from (values ('stock_transfers', 'to_location_id'), ('purchase_bills', 'location_id'), ('wastage_requests', 'location_id'), ('stock_wastage', 'location_id')) v(tb, col) loop
    if to_regclass('public.' || t.tb) is not null and exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = t.tb and c.column_name = t.col) then
      execute format('drop trigger if exists %I on public.%I', t.tb || '_closed_guard', t.tb);
      execute format('create trigger %I before insert on public.%I for each row execute function public._loc_closed_guard(%L)', t.tb || '_closed_guard', t.tb, t.col);
    end if;
  end loop;
end $$;

-- ---------- (7) settings sheet 0-1 versions ----------
-- the keys a sheet may hold (the 64 keys of the limits screen) with their shape; the owner can add keys with SQL.  Unknown key = refused.
create table if not exists public.settings_keys (
  key text primary key, kind text not null check (kind in ('number', 'text', 'time', 'bool')),
  min_value numeric not null default -1000, max_value numeric not null default 1000000000000, active boolean not null default true
);
alter table public.settings_keys enable row level security;
drop policy if exists settings_keys_read on public.settings_keys;
create policy settings_keys_read on public.settings_keys for select to authenticated using (public.is_active());
revoke all on public.settings_keys from public, anon, authenticated;
grant select on public.settings_keys to authenticated;
drop trigger if exists settings_keys_no_delete on public.settings_keys;
create trigger settings_keys_no_delete before delete on public.settings_keys for each row execute function public.no_hard_delete();
insert into public.settings_keys (key, kind) values
  ('drawer_float', 'number'),
  ('imprest', 'number'),
  ('expense_max', 'number'),
  ('cash_tol', 'number'),
  ('goods_money_tol_pct', 'number'),
  ('goods_money_tol_max', 'number'),
  ('big_sale', 'number'),
  ('avg_daily_sales', 'number'),
  ('discount_limit', 'number'),
  ('refund_limit', 'number'),
  ('hub_cash_max', 'number'),
  ('hub_min_cash', 'number'),
  ('order_hold_days', 'number'),
  ('unclaimed_days', 'number'),
  ('open_time', 'time'),
  ('close_time', 'time'),
  ('busy_day_def', 'text'),
  ('handover_point', 'text'),
  ('crates', 'number'),
  ('trays', 'number'),
  ('fridge1_name', 'text'),
  ('fridge1_min', 'number'),
  ('fridge1_max', 'number'),
  ('fridge2_name', 'text'),
  ('fridge2_min', 'number'),
  ('fridge2_max', 'number'),
  ('fridge3_name', 'text'),
  ('fridge3_min', 'number'),
  ('fridge3_max', 'number'),
  ('shelf_sweet', 'number'),
  ('shelf_cake', 'number'),
  ('shelf_doi', 'number'),
  ('shelf_bakery', 'number'),
  ('daytag_0', 'text'),
  ('daytag_1', 'text'),
  ('daytag_2', 'text'),
  ('daytag_3', 'text'),
  ('daytag_4', 'text'),
  ('daytag_5', 'text'),
  ('daytag_6', 'text'),
  ('waste_classes', 'text'),
  ('count_tol_pct', 'number'),
  ('count_tol_max', 'number'),
  ('quote_over', 'number'),
  ('jalebi_base_pct', 'number'),
  ('jalebi_per_kg_flour', 'number'),
  ('jalebi_tol_pct', 'number'),
  ('jalebi_tol_kg', 'number'),
  ('oil_change_rule', 'text'),
  ('mkt_limit_1', 'number'),
  ('mkt_limit_2', 'number'),
  ('mkt_limit_3', 'number'),
  ('mkt_limit_4', 'number'),
  ('mkt_limit_5', 'number'),
  ('mkt_limit_6', 'number'),
  ('mkt_limit_7', 'number'),
  ('mkt_limit_8', 'number'),
  ('mkt_limit_9', 'number'),
  ('mkt_limit_10', 'number'),
  ('online_order_limit', 'number'),
  ('scale_test', 'text'),
  ('newprod_review_days', 'number'),
  ('fixed_cost_month', 'number'),
  ('anomaly_ratio', 'number')
on conflict (key) do nothing;

create table if not exists public.settings_sheets (
  id bigserial primary key,
  location_id int not null references public.locations(id),
  version int not null,
  status text not null default 'draft' check (status in ('draft', 'approved', 'discarded')),
  effective_from date,
  source text not null default 'sheet' check (source in ('seed', 'sheet', 'legacy')),
  note text,
  created_by uuid, created_at timestamptz not null default now(),
  approved_by uuid, approved_at timestamptz,
  unique (location_id, version)
);
alter table public.settings_sheets add column if not exists base_version int;          -- the version the draft was copied from
alter table public.settings_sheets add column if not exists last_edited_by uuid;
alter table public.settings_sheets add column if not exists applied_at timestamptz;    -- when the version was written through to location_settings
update public.settings_sheets set applied_at = coalesce(approved_at, now()) where applied_at is null and source in ('seed', 'legacy');
create unique index if not exists settings_sheets_one_draft on public.settings_sheets (location_id) where status = 'draft';
create table if not exists public.settings_values (
  sheet_id bigint not null references public.settings_sheets(id),
  key text not null,
  value jsonb,                       -- null = blank = Data needed
  primary key (sheet_id, key)
);
alter table public.settings_sheets enable row level security;
alter table public.settings_values enable row level security;
drop policy if exists settings_sheets_read on public.settings_sheets;
create policy settings_sheets_read on public.settings_sheets for select to authenticated using (public._sheet_viewer_at(location_id));
drop policy if exists settings_values_read on public.settings_values;
create policy settings_values_read on public.settings_values for select to authenticated using (exists (select 1 from public.settings_sheets s where s.id = sheet_id and public._sheet_viewer_at(s.location_id)));
revoke all on public.settings_sheets, public.settings_values from public, anon, authenticated;
grant select on public.settings_sheets, public.settings_values to authenticated;
drop trigger if exists audit_settings_sheets on public.settings_sheets;
create trigger audit_settings_sheets after insert or update on public.settings_sheets for each row execute function public.log_change('id');
drop trigger if exists audit_settings_values on public.settings_values;
create trigger audit_settings_values after insert or update on public.settings_values for each row execute function public.log_change('sheet_id,key');
drop trigger if exists settings_sheets_no_delete on public.settings_sheets;
create trigger settings_sheets_no_delete before delete on public.settings_sheets for each row execute function public.no_hard_delete();
drop trigger if exists settings_values_no_delete on public.settings_values;
create trigger settings_values_no_delete before delete on public.settings_values for each row execute function public.no_hard_delete();
-- an approved version never changes its values (a change is the next version)
create or replace function public._sheet_values_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare st text;
begin
  select status into st from public.settings_sheets where id = new.sheet_id;
  if st is distinct from 'draft' and coalesce(current_setting('bos.sheet_seed', true), '') <> '1' then raise exception 'sheet_not_draft'; end if;
  return new;
end $$;
drop trigger if exists settings_values_guard on public.settings_values;
create trigger settings_values_guard before insert or update on public.settings_values for each row execute function public._sheet_values_guard();

-- version 1 for every place: approved, copied from location_settings (blank = Data needed).  Only places that have no sheet yet.
do $$
declare l record; sid bigint;
begin
  perform set_config('bos.sheet_seed', '1', true);
  for l in select id from public.locations loc where not exists (select 1 from public.settings_sheets s where s.location_id = loc.id) loop
    insert into public.settings_sheets (location_id, version, status, effective_from, source, note, approved_at, applied_at)
      values (l.id, 1, 'approved', date '2000-01-01', 'seed', 'copied from location_settings', now(), now()) returning id into sid;
    insert into public.settings_values (sheet_id, key, value) select sid, ls.key, ls.value from public.location_settings ls where ls.location_id = l.id
      on conflict do nothing;
  end loop;
  perform set_config('bos.sheet_seed', '', true);
end $$;

-- the version in force on a date (latest approved with effective_from <= date; before the first one: the first)
create or replace function public._sheet_in_force(p_loc int, p_date date) returns bigint
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select id from public.settings_sheets where location_id = p_loc and status = 'approved' and effective_from <= p_date order by effective_from desc, version desc limit 1),
    (select id from public.settings_sheets where location_id = p_loc and status = 'approved' order by effective_from, version limit 1));
$$;

-- THE reader: the value in force on that date; NULL = blank = Data needed
create or replace function public.get_limit(p_loc int, p_key text, p_date date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare sid bigint; v jsonb;
begin
  if not (public.is_active() and (public.can_loc(p_loc) or public._sheet_viewer_at(p_loc))) then raise exception 'not allowed'; end if;
  sid := public._sheet_in_force(p_loc, coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date));
  if sid is null then
    select value into v from public.location_settings where location_id = p_loc and key = p_key;
  else
    select value into v from public.settings_values where sheet_id = sid and key = p_key;
  end if;
  if v is null or v = 'null'::jsonb or (jsonb_typeof(v) = 'string' and btrim(v #>> '{}') = '') then return null; end if;
  return v;
end $$;

-- which of these keys are blank at the place on that date
create or replace function public.limit_missing(p_loc int, p_keys text[], p_date date default null) returns text[]
language plpgsql stable security definer set search_path = public as $$
declare k text; res text[] := '{}';
begin
  if not (public.is_active() and (public.can_loc(p_loc) or public._sheet_viewer_at(p_loc))) then raise exception 'not allowed'; end if;
  foreach k in array coalesce(p_keys, '{}') loop
    if public.get_limit(p_loc, k, p_date) is null then res := res || k; end if;
  end loop;
  return res;
end $$;

create or replace function public.sheet_list(p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._sheet_viewer_at(p_loc) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'version', s.version, 'status', s.status, 'effective_from', s.effective_from, 'source', s.source, 'note', s.note,
      'created_by', s.created_by, 'created_at', s.created_at, 'approved_by', s.approved_by, 'approved_at', s.approved_at, 'base_version', s.base_version,
      'filled', (select count(*) from public.settings_values v where v.sheet_id = s.id and v.value is not null and v.value <> 'null'::jsonb and btrim(v.value #>> '{}') <> ''),
      'blank', (select count(*) from public.settings_values v where v.sheet_id = s.id and (v.value is null or v.value = 'null'::jsonb or btrim(v.value #>> '{}') = '')),
      'in_force', s.id = public._sheet_in_force(p_loc, (now() at time zone 'Asia/Dhaka')::date)) order by s.version desc)
    from public.settings_sheets s where s.location_id = p_loc), '[]');
end $$;

-- the one draft of a place (created from the version in force, remembering which version that was)
create or replace function public._sheet_draft_for(p_loc int, p_uid uuid) returns bigint
language plpgsql security definer set search_path = public as $$
declare d bigint; cur bigint; nv int; bv int;
begin
  perform 1 from public.locations where id = p_loc for update;
  if not found then raise exception 'unknown_location'; end if;
  select id into d from public.settings_sheets where location_id = p_loc and status = 'draft';
  if d is not null then return d; end if;
  select coalesce(max(version), 0) + 1 into nv from public.settings_sheets where location_id = p_loc;
  cur := public._sheet_in_force(p_loc, (now() at time zone 'Asia/Dhaka')::date);
  select version into bv from public.settings_sheets where id = cur;
  insert into public.settings_sheets (location_id, version, status, source, created_by, last_edited_by, base_version) values (p_loc, nv, 'draft', 'sheet', p_uid, p_uid, bv) returning id into d;
  if cur is not null then insert into public.settings_values (sheet_id, key, value) select d, key, value from public.settings_values where sheet_id = cur; end if;
  return d;
end $$;
create or replace function public.sheet_draft(p_loc int) returns bigint
language plpgsql security definer set search_path = public as $$
begin
  if not public._sheet_viewer_at(p_loc) then raise exception 'not allowed'; end if;
  return public._sheet_draft_for(p_loc, auth.uid());
end $$;

-- a value must fit the key: numbers must be real jsonb numbers inside the range (a string such as 'Infinity', 'NaN' or 'abc' is refused for a number key)
create or replace function public._limit_value_ok(p_key text, p_val jsonb) returns jsonb
language plpgsql stable set search_path = public as $$
declare k public.settings_keys; n numeric; t text;
begin
  if p_key is null or p_key !~ '^[a-z0-9_]{1,60}$' then raise exception 'bad_key'; end if;
  select * into k from public.settings_keys where key = p_key and active;
  if not found and not exists (select 1 from public.location_settings where key = p_key) then raise exception 'unknown_key'; end if;
  if p_val is null or p_val = 'null'::jsonb then return null; end if;
  if k.key is null then   -- only known from old location_settings rows: any sane scalar
    if jsonb_typeof(p_val) = 'number' then
      if not ((p_val #>> '{}')::numeric between -1000000000000 and 1000000000000) then raise exception 'bad_number'; end if; return p_val;
    elsif jsonb_typeof(p_val) = 'string' then
      t := btrim(p_val #>> '{}'); if length(t) > 200 or lower(t) in ('infinity', '-infinity', 'nan') then raise exception 'bad_value'; end if; return case when t = '' then null else to_jsonb(t) end;
    elsif jsonb_typeof(p_val) = 'boolean' then return p_val; end if;
    raise exception 'bad_value';
  end if;
  if k.kind = 'number' then
    if jsonb_typeof(p_val) <> 'number' then raise exception 'bad_value'; end if;
    n := (p_val #>> '{}')::numeric;
    if not (n between k.min_value and k.max_value) then raise exception 'bad_number'; end if;
    return p_val;
  elsif k.kind = 'time' then
    if jsonb_typeof(p_val) <> 'string' then raise exception 'bad_value'; end if;
    t := btrim(p_val #>> '{}'); if t = '' then return null; end if;
    if t !~ '^([01]?[0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'bad_value'; end if;
    return to_jsonb(t);
  elsif k.kind = 'bool' then
    if jsonb_typeof(p_val) <> 'boolean' then raise exception 'bad_value'; end if; return p_val;
  end if;
  if jsonb_typeof(p_val) <> 'string' then raise exception 'bad_value'; end if;
  t := btrim(p_val #>> '{}'); if length(t) > 200 then raise exception 'too_long:value'; end if;
  return case when t = '' then null else to_jsonb(t) end;
end $$;

create or replace function public.sheet_set(p_sheet bigint, p_values jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare s public.settings_sheets; k text; n int := 0;
begin
  if p_values is null or jsonb_typeof(p_values) <> 'object' then raise exception 'bad_patch'; end if;
  select * into s from public.settings_sheets where id = p_sheet for update;
  if not found then raise exception 'unknown_sheet'; end if;
  if not public._sheet_viewer_at(s.location_id) then raise exception 'not allowed'; end if;
  if s.status <> 'draft' then raise exception 'sheet_not_draft'; end if;
  for k in select jsonb_object_keys(p_values) loop
    insert into public.settings_values (sheet_id, key, value) values (p_sheet, k, public._limit_value_ok(k, p_values->k))
      on conflict (sheet_id, key) do update set value = excluded.value;
    n := n + 1;
  end loop;
  update public.settings_sheets set last_edited_by = auth.uid() where id = p_sheet;
  return n;
end $$;

create or replace function public.sheet_discard(p_sheet bigint) returns void
language plpgsql security definer set search_path = public as $$
declare s public.settings_sheets;
begin
  select * into s from public.settings_sheets where id = p_sheet for update;
  if not found then raise exception 'unknown_sheet'; end if;
  if not public._sheet_viewer_at(s.location_id) then raise exception 'not allowed'; end if;
  if s.status <> 'draft' then raise exception 'sheet_not_draft'; end if;
  if s.created_by is distinct from auth.uid() and not public.is_owner() then raise exception 'not allowed'; end if;
  update public.settings_sheets set status = 'discarded' where id = p_sheet;
end $$;

-- write the version in force today through to location_settings (old screens and server functions keep reading location_settings)
create or replace function public._sheet_writethrough(p_loc int) returns void
language plpgsql security definer set search_path = public as $$
declare sid bigint; today date := (now() at time zone 'Asia/Dhaka')::date;
begin
  sid := public._sheet_in_force(p_loc, today);
  if sid is null then return; end if;
  perform set_config('bos.sheet_sync', '1', true);
  insert into public.location_settings (location_id, key, value, updated_by)
    select p_loc, v.key, v.value, auth.uid() from public.settings_values v where v.sheet_id = sid
  on conflict (location_id, key) do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
  perform set_config('bos.sheet_sync', '', true);
  update public.settings_sheets set applied_at = now() where location_id = p_loc and status = 'approved' and effective_from <= today and applied_at is null;
end $$;

-- there is no scheduler: a future-dated version is written through lazily, by this cheap check (does nothing when nothing is due).
-- It runs from control_counts() (every Home load of an owner / delegate), location_save, sheet_approve and sheet_sync_all().
-- get_limit() itself is always right by date; only code that reads location_settings DIRECTLY (record_sale2 ...) sees the new value after one of these ran.
create or replace function public._sheet_sync_due() returns int
language plpgsql security definer set search_path = public as $$
declare l record; n int := 0;
begin
  for l in select distinct location_id from public.settings_sheets where status = 'approved' and applied_at is null and effective_from <= (now() at time zone 'Asia/Dhaka')::date loop
    perform public._sheet_writethrough(l.location_id); n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.sheet_approve(p_sheet bigint, p_effective date default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.settings_sheets; eff date; lastd date; firstd date; today date := (now() at time zone 'Asia/Dhaka')::date; exempt boolean;
begin
  select * into s from public.settings_sheets where id = p_sheet for update;
  if not found then raise exception 'unknown_sheet'; end if;
  if not (public.is_owner() or (public.is_active() and public.has_grant('settings_approve', s.location_id))) then raise exception 'not allowed'; end if;
  if s.status <> 'draft' then raise exception 'sheet_not_draft'; end if;
  exempt := public.is_owner() and public.rule_on('owner_self_approve');
  -- the approver is neither the person who started the draft nor the last person who edited it
  if not exempt and (s.created_by is not distinct from auth.uid() or s.last_edited_by is not distinct from auth.uid()) then raise exception 'maker_cannot_approve'; end if;
  -- a newer version was approved since this draft was copied: refuse (start a new draft from the current version)
  if exists (select 1 from public.settings_sheets x where x.location_id = s.location_id and x.status = 'approved' and x.version > coalesce(s.base_version, 0)) then raise exception 'newer_version_exists'; end if;
  eff := coalesce(p_effective, today);
  select coalesce((select l.created_at::date from public.locations l where l.id = s.location_id and l.created_by is not null), date '2000-01-01') into firstd;
  if eff < firstd then raise exception 'effective_too_early'; end if;
  if eff > today + 365 then raise exception 'effective_too_far'; end if;
  select max(effective_from) into lastd from public.settings_sheets where location_id = s.location_id and status = 'approved' and source <> 'seed';
  if lastd is not null and eff < lastd then raise exception 'effective_before_previous'; end if;
  update public.settings_sheets set status = 'approved', effective_from = eff, approved_by = auth.uid(), approved_at = now(), note = coalesce(nullif(btrim(p_note), ''), note) where id = p_sheet;
  perform public._sheet_writethrough(s.location_id);
  return jsonb_build_object('ok', true, 'version', s.version, 'effective_from', eff);
end $$;

create or replace function public.sheet_sync_all() returns int
language plpgsql security definer set search_path = public as $$
declare l record; n int := 0;
begin
  if not public._sheet_viewer() then raise exception 'not allowed'; end if;
  for l in select id from public.locations loop perform public._sheet_writethrough(l.id); n := n + 1; end loop;
  return n;
end $$;

-- the OLD screen (#/locset) writes location_settings directly (owner only, RLS).  Keep it working AND versioned:
--  * owner_self_approve ON : a direct change makes a new approved version (source 'legacy', effective today, copied from the version in force TODAY);
--    the same person changing again the same day edits that version.
--  * owner_self_approve OFF: the direct change is NOT applied; it goes into the draft (someone else approves it) and location_settings keeps the old value.
create or replace function public._ls_legacy() returns trigger
language plpgsql security definer set search_path = public as $$
declare cur public.settings_sheets; nv int; sid bigint; did bigint; today date := (now() at time zone 'Asia/Dhaka')::date; me uuid := auth.uid();
begin
  if coalesce(current_setting('bos.sheet_sync', true), '') = '1' then return new; end if;
  if tg_op = 'UPDATE' and old.value is not distinct from new.value then return new; end if;
  if me is not null and public.is_owner() and not public.rule_on('owner_self_approve') then
    did := public._sheet_draft_for(new.location_id, me);
    insert into public.settings_values (sheet_id, key, value) values (did, new.key, new.value) on conflict (sheet_id, key) do update set value = excluded.value;
    update public.settings_sheets set last_edited_by = me where id = did;
    perform set_config('bos.sheet_sync', '1', true);
    if tg_op = 'UPDATE' then update public.location_settings set value = old.value where location_id = new.location_id and key = new.key;
    else update public.location_settings set value = null where location_id = new.location_id and key = new.key; end if;
    perform set_config('bos.sheet_sync', '', true);
    return new;
  end if;
  perform set_config('bos.sheet_seed', '1', true);
  select * into cur from public.settings_sheets where id = public._sheet_in_force(new.location_id, today);
  if not found then
    insert into public.settings_sheets (location_id, version, status, effective_from, source, note, approved_at, applied_at) values (new.location_id, 1, 'approved', date '2000-01-01', 'seed', 'created by a direct settings change', now(), now()) returning id into sid;
  elsif cur.source = 'legacy' and cur.effective_from = today and cur.approved_by is not distinct from me and cur.version = (select max(version) from public.settings_sheets where location_id = new.location_id and status = 'approved') then
    sid := cur.id;
  else
    select coalesce(max(version), 0) + 1 into nv from public.settings_sheets where location_id = new.location_id;
    insert into public.settings_sheets (location_id, version, status, effective_from, source, note, created_by, approved_by, approved_at, applied_at, base_version)
      values (new.location_id, nv, 'approved', today, 'legacy', 'changed on the old limits screen', me, me, now(), now(), cur.version) returning id into sid;
    insert into public.settings_values (sheet_id, key, value) select sid, key, value from public.settings_values where sheet_id = cur.id on conflict do nothing;
  end if;
  insert into public.settings_values (sheet_id, key, value) values (sid, new.key, new.value)
    on conflict (sheet_id, key) do update set value = excluded.value;
  perform set_config('bos.sheet_seed', '', true);
  return new;
end $$;
drop trigger if exists location_settings_legacy on public.location_settings;
create trigger location_settings_legacy after insert or update on public.location_settings for each row execute function public._ls_legacy();

-- a new place gets its (blank) version 1 too
create or replace function public._loc_sheet_v1() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.settings_sheets (location_id, version, status, effective_from, source, note, approved_at, applied_at)
    values (new.id, 1, 'approved', date '2000-01-01', 'seed', 'blank: every value needs data', now(), now()) on conflict (location_id, version) do nothing;
  return new;
end $$;
drop trigger if exists locations_sheet_v1 on public.locations;
create trigger locations_sheet_v1 after insert on public.locations for each row execute function public._loc_sheet_v1();

-- ---------- (8) Control Center: what waits for the caller ----------
create or replace function public.control_counts() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
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
    select count(*) into n from public.locations where status in ('planned', 'setting_up'); res := res || jsonb_build_object('location_setup', n);
  end if;
  if own or hd or sa then
    select count(*) into n from public.settings_sheets where status = 'draft'; res := res || jsonb_build_object('settings_drafts', n);
  end if;
  -- the list queue is for people who may DECIDE it (the list_manage grant); head_management alone does not (the server would refuse the Lists screen)
  if (own or lg) and to_regprocedure('public.list_queue_counts()') is not null then
    execute 'select public.list_queue_counts()' into q;
    res := res || jsonb_build_object('lists', coalesce((q->>'requests')::int, 0) + coalesce((q->>'other')::int, 0));
  end if;
  return res;
end $$;

-- ---------- (9) privileges ----------
revoke all on function public._loc_mgr(), public._sheet_viewer(), public._loc_mgr_at(int), public._sheet_viewer_at(int), public._loc_steps_def(), public._loc_steps_seed(int), public._slug(text), public._loc_open_steps(int),
  public._loc_block_guard(), public._loc_closed_guard(), public._loc_status_guard(), public._sheet_values_guard(), public._sheet_in_force(int, date), public._limit_value_ok(text, jsonb), public._sheet_writethrough(int),
  public._sheet_sync_due(), public._sheet_draft_for(int, uuid), public._ls_legacy(), public._loc_sheet_v1(),
  public.location_save(int, jsonb), public.location_close_check(int), public.location_set_status(int, text, text, boolean), public.location_set_active(int, boolean),
  public.location_steps_init(int), public.location_step_set(int, int, boolean, text), public.location_block_override(int, text, int),
  public.get_limit(int, text, date), public.limit_missing(int, text[], date), public.sheet_list(int), public.sheet_draft(int), public.sheet_set(bigint, jsonb),
  public.sheet_discard(bigint), public.sheet_approve(bigint, date, text), public.sheet_sync_all(), public.control_counts() from public, anon, authenticated;
grant execute on function public.location_save(int, jsonb), public.location_close_check(int), public.location_set_status(int, text, text, boolean), public.location_set_active(int, boolean),
  public.location_steps_init(int), public.location_step_set(int, int, boolean, text), public.location_block_override(int, text, int),
  public.get_limit(int, text, date), public.limit_missing(int, text[], date), public.sheet_list(int), public.sheet_draft(int), public.sheet_set(bigint, jsonb),
  public.sheet_discard(bigint), public.sheet_approve(bigint, date, text), public.sheet_sync_all(), public.control_counts(), public._loc_mgr(), public._sheet_viewer(), public._loc_mgr_at(int), public._sheet_viewer_at(int) to authenticated;

-- ===================== phase17.sql =====================
-- ============================================================
-- Phase 17 (W5a): ROLLOUT (paper / parallel / app per form x place), PAPER + APP TOGETHER (entered later + paper serial),
--                 LOCK / REVISIONS / CHANGE REQUESTS, OWNER SELF-APPROVAL SWITCH, idempotent client_id for the form offline queue.
--   Additive and safe to run twice; paste the whole file into the Supabase SQL editor.  Needs phase8..phase14.  Does NOT need phase15 / 16
--   (the rule owner_self_approve is the same key phase15 / 16 use: inserted here only when it is missing).
--   * form_rollout(form_code, location_id, mode paper | parallel | app, note, changed_by, changed_at): every existing form x place starts 'app'
--     (live forms stay in the app).  A missing row means 'app'.  RPC rollout_set / rollout_set_many: owner or the delegable grant rollout_manage; audit-logged.
--     Enforcement on the server: a BEFORE INSERT trigger on entries (like the pause trigger of phase16) refuses a NEW app entry where the mode is
--     'paper', unless it is flagged "entered later from paper" with a paper serial and the original time.  'parallel' and 'app' are allowed.
--     Switch rollout_enforce (default ON, acts only on mode 'paper' so nothing existing changes).
--   * entries: + entered_later, paper_serial, paper_at (original time), source ('app' | 'paper_entry'), rev_no, client_id, rollout_mode.
--     The paper serial is the number printed in the paper book: unique per (form, place) (index + the existing data.paper_no index of phase5, the
--     value is mirrored to data.paper_no so the gap audit sees it), the app serial (entries.serial) is software generated: the two never clash.
--     Switch entered_later_on (default ON).  number_audit_both(form, place) reports both series.
--   * save_entry gets an optional 8th argument p_meta jsonb ({client_id, entered_later, paper_serial, paper_at}); the old 7-argument calls keep working.
--     A create with a client_id that already exists returns the existing entry (idempotent re-send from the phone's offline queue).
--   * entry_change_requests + entry_revisions (append-only): after approval an entry is locked; a person who may enter the form asks for a change
--     (entry_change_request), the owner or a holder of the delegable grant change_approve decides (maker <> approver); an approval keeps the old
--     version as revision n and makes revision n+1 current.  entry_revisions_list shows the history.  reopen_entry (owner) also keeps the approved
--     version as a revision.
--   * owner_self_approve (default ON = owner exempt): decide_entry, decide_release, decide_emergency, submit_item_change / decide_item_change honour it.
--     When OFF the owner's own submission needs another approver (another owner, or a delegate: approve right on the form, release_decide,
--     emergency_decide, ITEMS approve / item_create).
-- ============================================================

-- ---------- (0) helpers (same text as phase11 / 16; here so the file stands alone) ----------
create or replace function public.no_hard_delete() returns trigger
language plpgsql set search_path = public as $$
begin raise exception 'nothing is deleted – retire instead'; end $$;

-- ---------- (1) rules and grants ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('rollout_enforce', 'entries', 'switch', 'true', null, null, null, null, 'কাগজ অবস্থায় অ্যাপে নতুন এন্ট্রি আটকানো', 'Paper অবস্থায় app-এ নতুন entry আটকানো', 'Refuse new app entries where the form is on Paper',
   'চালু থাকলে যে ফর্ম × লোকেশন ‘কাগজ’-এ আছে সেখানে সার্ভার নতুন এন্ট্রি নেবে না (কাগজ থেকে ‘পরে তোলা’ ছাড়া)। ‘পাশাপাশি’ ও ‘অ্যাপ’-এ কিছু বদলায় না', 'On থাকলে ‘Paper’ ফর্ম×লোকেশনে server নতুন entry নেবে না (কাগজ থেকে ‘পরে তোলা’ ছাড়া)', 'When on, the server refuses a new entry at a form x place set to Paper (except one entered later from paper). Parallel and App are never blocked', 90),
 ('entered_later_on', 'entries', 'switch', 'true', null, null, null, null, 'কাগজ থেকে ‘পরে তোলা’ এন্ট্রি চালু', 'কাগজ থেকে ‘পরে তোলা’ entry চালু', 'Allow "entered later from paper" entries',
   'বাইরে কাজ করা কেউ আগে কাগজে লিখে পরে অ্যাপে তুলতে পারবেন: কাগজের নম্বর ও আসল সময় লাগে; অনুমোদনে যায়', 'বাইরে কাজ করা কেউ আগে paper-এ লিখে পরে app-এ তুলতে পারবেন: paper number ও আসল সময় লাগে', 'Someone working outside fills the paper and keys it in later: needs the paper serial and the original time; goes to approval like any entry', 91),
 ('change_requests_on', 'entries', 'switch', 'true', null, null, null, null, 'অনুমোদিত এন্ট্রি বদলের অনুরোধ চালু', 'Approved entry বদলের request চালু', 'Allow change requests on approved entries',
   'বন্ধ করলে অনুমোদিত এন্ট্রি বদলের অনুরোধ নেওয়া হবে না (মালিক আগের মতো ‘আবার খুলুন’ ব্যবহার করবেন)', 'Off করলে approved entry বদলের request নেওয়া হবে না', 'When off, change requests are refused (the owner still has Reopen)', 92),
 ('entered_later_max_days', 'entries', 'number', null, 'days', null, 0, 3650, 'পরে তোলা এন্ট্রি: কাগজের আসল তারিখ সর্বোচ্চ কত দিন আগের (ফাঁকা = সীমা নেই)', 'পরে তোলা entry: paper-এর আসল date সর্বোচ্চ কত দিন আগের (ফাঁকা = Data needed)', 'Entered later: oldest allowed paper date, in days (blank = Data needed / no limit)',
   'ফাঁকা থাকলে কোনো সীমা নেই। দিলে: তার চেয়ে পুরনো কাগজ শুধু মালিক তুলতে পারবেন (লাল এক্সেপশনসহ)', 'ফাঁকা = no limit। দিলে: তার চেয়ে পুরনো paper শুধু owner তুলতে পারবেন (red exception সহ)', 'Blank = no limit. When set, older paper can be entered by the owner only (with a red exception)', 93),
 ('owner_self_approve', 'lists', 'switch', 'true', null, null, null, null, 'মালিক নিজের অনুরোধ নিজে অনুমোদন করতে পারবেন', 'Owner নিজের request নিজে approve করতে পারবেন', 'Owner may approve their own request',
   'বন্ধ করলে মালিকের অনুরোধও অন্য অনুমতিপ্রাপ্ত কেউ অনুমোদন করবেন', 'Off করলে owner-এর request অন্য কেউ approve করবেন', 'When off, the owner''s own requests need another approver', 50)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('rollout_manage', 'master', 66, 'ফর্ম × লোকেশন: কাগজ / পাশাপাশি / অ্যাপ বদলানো', 'Form × location: Paper / Parallel / App বদলানো', 'Change a form x place between Paper / Parallel / App', 'window', null),
 ('change_approve', 'master', 67, 'অনুমোদিত এন্ট্রি বদলের অনুরোধ অনুমোদন', 'Approved entry বদলের request approve', 'Approve change requests on approved entries', 'window', null),
 ('release_decide', 'master', 68, 'লাল নিয়ন্ত্রণ ছাড়ের অনুরোধ অনুমোদন', 'Red control release request approve', 'Decide red-control release requests', 'window', null)
on conflict (grant_code) do nothing;

-- ---------- (2) rollout state ----------
create table if not exists public.form_rollout (
  form_code text not null references public.forms(code),
  location_id int not null references public.locations(id),
  mode text not null default 'app' check (mode in ('paper', 'parallel', 'app')),
  note text,
  changed_by uuid, changed_at timestamptz not null default now(),
  primary key (form_code, location_id)
);
alter table public.form_rollout enable row level security;
drop policy if exists form_rollout_read on public.form_rollout;
create policy form_rollout_read on public.form_rollout for select to authenticated using (public.is_active());
revoke all on public.form_rollout from public, anon, authenticated;
grant select on public.form_rollout to authenticated;
drop trigger if exists audit_form_rollout on public.form_rollout;
create trigger audit_form_rollout after insert or update on public.form_rollout for each row execute function public.log_change('form_code,location_id');
drop trigger if exists form_rollout_no_delete on public.form_rollout;
create trigger form_rollout_no_delete before delete on public.form_rollout for each row execute function public.no_hard_delete();

-- every existing form x place starts on the app (live forms stay live); a missing row also means app
insert into public.form_rollout (form_code, location_id, mode, note)
select f.code, l.id, 'app', 'start: live forms stay on the app'
from public.forms f cross join public.locations l
on conflict (form_code, location_id) do nothing;

create or replace function public.rollout_mode(p_form text, p_loc int) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select mode from public.form_rollout where form_code = p_form and location_id = p_loc), 'app');
$$;

create or replace function public._rollout_mgr() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and public.has_grant('rollout_manage'));
$$;

create or replace function public.rollout_set(p_form text, p_loc int, p_mode text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old text;
begin
  if not public._rollout_mgr() then raise exception 'not allowed'; end if;
  if p_mode is null or p_mode not in ('paper', 'parallel', 'app') then raise exception 'bad_mode'; end if;
  if not exists (select 1 from public.forms where code = p_form) then raise exception 'form_not_found'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'location_not_found'; end if;
  old := public.rollout_mode(p_form, p_loc);
  insert into public.form_rollout (form_code, location_id, mode, note, changed_by, changed_at)
    values (p_form, p_loc, p_mode, nullif(left(btrim(coalesce(p_note, '')), 300), ''), auth.uid(), now())
    on conflict (form_code, location_id) do update set mode = excluded.mode, note = excluded.note, changed_by = excluded.changed_by, changed_at = excluded.changed_at;
  return jsonb_build_object('form', p_form, 'location_id', p_loc, 'from', old, 'to', p_mode);
end $$;

-- bulk: null array = all forms / all places
create or replace function public.rollout_set_many(p_forms text[], p_locs int[], p_mode text, p_note text default null) returns int
language plpgsql security definer set search_path = public as $$
declare n int := 0; f text; l int;
begin
  if not public._rollout_mgr() then raise exception 'not allowed'; end if;
  if p_mode is null or p_mode not in ('paper', 'parallel', 'app') then raise exception 'bad_mode'; end if;
  for f in select code from public.forms where p_forms is null or code = any(p_forms) order by code loop
    for l in select id from public.locations where p_locs is null or id = any(p_locs) order by id loop
      perform public.rollout_set(f, l, p_mode, p_note); n := n + 1;
    end loop;
  end loop;
  return n;
end $$;

-- ---------- (3) entries: paper + app together, revision number, client id ----------
alter table public.entries add column if not exists entered_later boolean not null default false;
alter table public.entries add column if not exists paper_serial text;
alter table public.entries add column if not exists paper_at timestamptz;
alter table public.entries add column if not exists source text not null default 'app';
alter table public.entries add column if not exists rev_no int not null default 1;
alter table public.entries add column if not exists client_id uuid;
alter table public.entries add column if not exists rollout_mode text;
alter table public.entries add column if not exists reopen_snap jsonb;      -- the approved version kept at an owner reopen; becomes a revision only if the re-approved entry really differs
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'entries_source_chk') then
    alter table public.entries add constraint entries_source_chk check (source in ('app', 'paper_entry'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'entries_later_chk') then
    alter table public.entries add constraint entries_later_chk check (not entered_later or (nullif(btrim(paper_serial), '') is not null and paper_at is not null));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'entries_rollout_mode_chk') then
    alter table public.entries add constraint entries_rollout_mode_chk check (rollout_mode is null or rollout_mode in ('paper', 'parallel', 'app'));
  end if;
end $$;
create unique index if not exists entries_client_uq on public.entries (client_id) where client_id is not null;
-- the printed number, normalised: upper case, trimmed, leading zeros of each number dropped (A-0101 = a-101 = A-101); once per form and place, apart from the app serial
create or replace function public.norm_paper_serial(p text) returns text
language sql immutable as $$ select nullif(regexp_replace(upper(btrim(coalesce(p, ''))), '(^|[^0-9])0+([0-9])', '\1\2', 'g'), '') $$;
create or replace function public.paper_serial_collisions() returns table (form_code text, location_id int, norm text, entries bigint)
language sql stable security definer set search_path = public as $$
  select e.form_code, e.location_id, public.norm_paper_serial(e.paper_serial), count(*) from public.entries e
  where public.is_owner() and public.norm_paper_serial(e.paper_serial) is not null group by 1, 2, 3 having count(*) > 1;
$$;
do $$ begin
  if exists (select 1 from public.entries where public.norm_paper_serial(paper_serial) is not null group by form_code, location_id, public.norm_paper_serial(paper_serial) having count(*) > 1) then
    raise warning 'phase17: paper serials collide after normalisation - the unique index was NOT changed; run select * from paper_serial_collisions() as the owner and fix them, then run this file again';
  else
    create unique index if not exists entries_paper_serial_nuq on public.entries (form_code, location_id, (public.norm_paper_serial(paper_serial))) where public.norm_paper_serial(paper_serial) is not null;
    drop index if exists public.entries_paper_serial_uq;
  end if;
end $$;

create or replace function public._entries_rollout_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare m text;
begin
  m := public.rollout_mode(new.form_code, new.location_id);
  new.rollout_mode := m;
  new.source := case when new.entered_later then 'paper_entry' else 'app' end;
  if m = 'paper' and public.rule_on('rollout_enforce') and not new.entered_later then raise exception 'rollout_paper:%', new.form_code; end if;
  return new;
end $$;
drop trigger if exists entries_rollout_guard on public.entries;
create trigger entries_rollout_guard before insert on public.entries for each row execute function public._entries_rollout_guard();

-- ---------- (4) save_entry with the optional meta (client id, entered later) ----------
drop function if exists public.save_entry(uuid, text, int, date, jsonb, jsonb, text);
create or replace function public.save_entry(p_id uuid, p_form text, p_loc int, p_date date, p_data jsonb, p_flags jsonb, p_note text default null, p_meta jsonb default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text; n int; ow boolean; cid uuid; later boolean; ps text; pat timestamptz; pt text; d date := p_date; dat jsonb := coalesce(p_data, '{}'::jsonb); has_later boolean; oldd jsonb; mx numeric; fls jsonb := coalesce(p_flags, '[]'::jsonb);
begin
  if not public.can_do(p_form, 'enter') then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if not exists (select 1 from public.forms where code = p_form and enabled) then raise exception 'form is switched off'; end if;
  if p_meta is not null and jsonb_typeof(p_meta) <> 'object' then raise exception 'bad_meta'; end if;
  begin cid := nullif(p_meta->>'client_id', '')::uuid; exception when others then raise exception 'bad_client_id'; end;
  has_later := p_meta is not null and p_meta ? 'entered_later';
  select staff_id into sid from public.profiles where id = auth.uid();

  if p_id is null then
    if cid is not null then
      select * into e from public.entries where client_id = cid;
      if found then
        if e.created_by <> auth.uid() then raise exception 'client_id_in_use'; end if;
        if e.form_code <> p_form or e.location_id <> p_loc then raise exception 'client_id_mismatch'; end if;
        return jsonb_build_object('id', e.id, 'serial', e.serial, 'duplicate', true);
      end if;
    end if;
  else
    select * into e from public.entries where id = p_id for update;
    if not found then raise exception 'entry not found'; end if;
    if e.status <> 'draft' then raise exception 'entry is locked'; end if;
    if e.created_by <> auth.uid() and not public.is_owner() then raise exception 'only the maker can edit'; end if;
  end if;

  -- entered later from paper: effective values (a draft keeps its own when the meta does not mention them)
  begin later := case when has_later then coalesce((p_meta->>'entered_later')::boolean, false) else coalesce(e.entered_later, false) end;
  exception when others then raise exception 'bad_meta'; end;
  if later then
    if has_later then
      ps := nullif(btrim(coalesce(p_meta->>'paper_serial', '')), '');
      begin
        pt := nullif(btrim(coalesce(p_meta->>'paper_at', '')), '');
        if pt is null then pat := null;
        elsif pt ~ '[T ][0-9:.]+(Z|[+-][0-9]{2}(:?[0-9]{2})?)$' then pat := pt::timestamptz;      -- has an offset
        else pat := pt::timestamp at time zone 'Asia/Dhaka';                                        -- naive = Dhaka local time
        end if;
      exception when others then raise exception 'paper_time_required'; end;
    else ps := e.paper_serial; pat := e.paper_at; end if;
    if not public.rule_on('entered_later_on') and not coalesce(e.entered_later, false) then raise exception 'entered_later_off'; end if;
    if ps is null then raise exception 'paper_serial_required'; end if;
    if length(ps) > 40 then raise exception 'paper_serial_too_long'; end if;
    if pat is null then raise exception 'paper_time_required'; end if;
    if pat > now() + interval '5 minutes' then raise exception 'paper_time_future'; end if;
    d := (pat at time zone 'Asia/Dhaka')::date;                       -- the business date is the original date
    dat := jsonb_set(dat, '{paper_no}', to_jsonb(ps));                -- mirrored: the gap audit and the old unique index see it
    mx := public.rule_num('entered_later_max_days');
    if mx is not null and pat < now() - make_interval(days => mx::int) then
      if not public.is_owner() then raise exception 'entered_later_too_old'; end if;
      if not exists (select 1 from jsonb_array_elements(fls) x where x->>'code' = 'entered_later_old') then
        fls := fls || jsonb_build_array(jsonb_build_object('code', 'entered_later_old', 'level', 'red', 'src', 'system',
          'text', jsonb_build_object('bn', 'কাগজের তারিখ সীমার চেয়ে পুরনো — পরে তোলা', 'en', 'Entered later: paper date older than the limit')));
      end if;
    end if;
    if exists (select 1 from public.entries x where x.form_code = p_form and x.location_id = p_loc and (p_id is null or x.id <> p_id)
               and (public.norm_paper_serial(x.paper_serial) = public.norm_paper_serial(ps) or public.norm_paper_serial(x.data->>'paper_no') = public.norm_paper_serial(ps))) then raise exception 'paper_serial_in_use'; end if;
  else ps := null; pat := null; end if;

  if p_id is null then
    begin
      insert into public.serials (form_code, location_id, last) values (p_form, p_loc, 1)
        on conflict (form_code, location_id) do update set last = public.serials.last + 1 returning last into n;
      insert into public.entries (form_code, location_id, serial, entry_date, data, flags, created_by, created_staff, entered_later, paper_serial, paper_at, client_id)
        values (p_form, p_loc, n, d, dat, fls, auth.uid(), sid, later, ps, pat, cid) returning * into e;
    exception when unique_violation then
      -- two sends of the same client id at once: the loser (its serial bump is rolled back with this block) gets the winner's entry
      if cid is null then raise; end if;
      select * into e from public.entries where client_id = cid and created_by = auth.uid();
      if not found then raise; end if;
      if e.form_code <> p_form or e.location_id <> p_loc then raise exception 'client_id_mismatch'; end if;
      return jsonb_build_object('id', e.id, 'serial', e.serial, 'duplicate', true);
    end;
    return jsonb_build_object('id', e.id, 'serial', e.serial);
  end if;

  oldd := e.data;
  if e.entered_later and not later and not (dat ? 'paper_no') then oldd := e.data - 'paper_no'; end if;     -- switching “entered later” off drops only the mirrored serial: no note needed
  ow := public.jsonb_overwrites(oldd, dat);
  if ow and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  if ow then
    insert into public.corrections (user_id, staff_id, form_code, entry_id, note, before, after)
      values (auth.uid(), sid, e.form_code, e.id::text, btrim(p_note), e.data, dat);
  end if;
  update public.entries set data = dat, flags = fls, entry_date = d, updated_at = now(),
    entered_later = later, paper_serial = ps, paper_at = pat, source = case when later then 'paper_entry' else 'app' end where id = p_id;
  return jsonb_build_object('id', e.id, 'serial', e.serial, 'overwrote', ow);
end $$;
revoke all on function public.save_entry(uuid, text, int, date, jsonb, jsonb, text, jsonb) from public, anon;
grant execute on function public.save_entry(uuid, text, int, date, jsonb, jsonb, text, jsonb) to authenticated;

create or replace function public.submit_entry(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; f public.forms; fl jsonb; blocked text[] := '{}'; auto boolean;
begin
  select * into e from public.entries where id = p_id for update;
  if not found then raise exception 'entry not found'; end if;
  if e.status <> 'draft' then raise exception 'entry is locked'; end if;
  if e.created_by <> auth.uid() and not public.is_owner() then raise exception 'only the maker can submit'; end if;
  if not public.can_do(e.form_code, 'enter') or not public.can_loc(e.location_id) then raise exception 'not allowed'; end if;
  if public.rollout_mode(e.form_code, e.location_id) = 'paper' and public.rule_on('rollout_enforce') and not e.entered_later then
    raise exception 'rollout_paper:%', e.form_code;
  end if;
  select * into f from public.forms where code = e.form_code;
  if f.red_block then
    for fl in select * from jsonb_array_elements(e.flags) loop
      if fl->>'level' = 'red' and fl->>'code' <> 'entered_later_old' and not exists (select 1 from public.release_requests r
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
revoke all on function public.submit_entry(uuid) from public, anon;
grant execute on function public.submit_entry(uuid) to authenticated;

-- ---------- (5) owner self-approval switch: entries ----------
create or replace function public.decide_entry(p_id uuid, p_approve boolean, p_note text default null, p_check jsonb default null, p_flags jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text; self_ok boolean; auto boolean; newflags jsonb;
begin
  select * into e from public.entries where id = p_id for update;
  if not found or e.status <> 'submitted' then raise exception 'entry is not waiting for a decision'; end if;
  if not (public.can_do(e.form_code, 'approve') and public.can_loc(e.location_id)) then raise exception 'not allowed'; end if;
  if public.is_owner() then self_ok := public.rule_on('owner_self_approve');
  else self_ok := exists (select 1 from public.user_roles ur join public.roles r on r.code = ur.role_code where ur.user_id = auth.uid() and r.allow_self_approve);
  end if;
  if e.created_by = auth.uid() and not self_ok then raise exception 'you cannot approve your own entry'; end if;
  if not p_approve and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  -- flags found while checking (receiver's count, etc.) are added to the maker's flags
  newflags := coalesce(p_flags, '[]'::jsonb);
  if p_approve and e.reopen_snap is not null then
    -- an owner reopen: the old approved version becomes a revision only when the re-approved entry really differs (no empty revisions)
    if (e.reopen_snap->'data') is distinct from e.data or (e.reopen_snap->'check_data') is distinct from coalesce(p_check, e.check_data) then
      insert into public.entry_revisions (entry_id, rev_no, data, check_data, flags, changed_by, changed_staff, approved_by, approved_staff, reason)
        values (e.id, e.rev_no, e.reopen_snap->'data', e.reopen_snap->'check_data', e.reopen_snap->'flags', (e.reopen_snap->>'by')::uuid, e.reopen_snap->>'staff', auth.uid(), sid, e.reopen_snap->>'reason');
      update public.entries set rev_no = e.rev_no + 1 where id = p_id;
    end if;
    update public.entries set reopen_snap = null where id = p_id;
  end if;
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
revoke all on function public.decide_entry(uuid, boolean, text, jsonb, jsonb) from public, anon;
grant execute on function public.decide_entry(uuid, boolean, text, jsonb, jsonb) to authenticated;

-- red-control release: the owner as before, plus a delegate holding release_decide; maker <> approver (the owner exempt only while owner_self_approve is ON)
create or replace function public.decide_release(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sid text; r public.release_requests;
begin
  select * into r from public.release_requests where id = p_id for update;
  if not found then raise exception 'request is not pending'; end if;
  if not (public.is_owner() or (public.is_active() and public.has_grant('release_decide', (select location_id from public.entries where id = r.entry_id)))) then raise exception 'owner only'; end if;
  if r.status <> 'pending' then raise exception 'request is not pending'; end if;
  if r.requested_by = auth.uid() and not (public.is_owner() and public.rule_on('owner_self_approve')) then raise exception 'self_approval'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.release_requests set status = case when p_approve then 'approved' else 'rejected' end,
    decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = p_note where id = p_id;
  return jsonb_build_object('status', case when p_approve then 'approved' else 'rejected' end);
end $$;
revoke all on function public.decide_release(bigint, boolean, text) from public, anon;
grant execute on function public.decide_release(bigint, boolean, text) to authenticated;
create or replace function public._release_can_see(p_entry uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('release_decide', (select location_id from public.entries where id = p_entry)));
$$;
revoke all on function public._release_can_see(uuid) from public, anon; grant execute on function public._release_can_see(uuid) to authenticated;
drop policy if exists release_read on public.release_requests;
create policy release_read on public.release_requests for select to authenticated
  using (requested_by = auth.uid() or public.is_owner() or public._release_can_see(entry_id));

-- emergency requests: someone else decides; the owner is exempt only while owner_self_approve is ON
create or replace function public.decide_emergency(p_id bigint, p_approve boolean, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.emergency_requests; sid text; mins numeric;
begin
  if not public.can_grant('emergency_decide') then raise exception 'not allowed'; end if;
  select * into r from public.emergency_requests where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if r.status <> 'pending' then raise exception 'already decided'; end if;
  if r.created_at < now() - interval '1 day' then update public.emergency_requests set status = 'expired' where id = p_id; return; end if;      -- a day-old request is stale: ask again
  if r.requested_by = auth.uid() and not (public.is_owner() and public.rule_on('owner_self_approve')) then raise exception 'own_request'; end if;
  if not p_approve and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  mins := coalesce(public.rule_num('em_minutes'), 30);
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.emergency_requests set status = case when p_approve then 'approved' else 'rejected' end, decided_by = auth.uid(), decided_staff = sid, decided_at = now(),
    decision_note = left(nullif(btrim(p_note), ''), 300), valid_until = case when p_approve then now() + make_interval(mins => mins::int) end where id = p_id;
end $$;
revoke all on function public.decide_emergency(bigint, boolean, text) from public, anon;
grant execute on function public.decide_emergency(bigint, boolean, text) to authenticated;

-- item changes: the owner's own change is applied at once only while owner_self_approve is ON; otherwise it is a request for another approver
create or replace function public.submit_item_change(p_item uuid, p_patch jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sid text; cid bigint;
begin
  if not public.can_do('ITEMS', 'enter') then raise exception 'not allowed'; end if;
  if p_patch ? 'cost_price' and not public.can_do('ITEM_COST', 'enter') then raise exception 'not allowed to change cost'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if public.is_owner() and public.rule_on('owner_self_approve') then
    return jsonb_build_object('status', 'applied', 'item_id', public.apply_item_patch(p_item, p_patch));
  end if;
  insert into public.item_changes (item_id, patch, note, requested_by, requested_staff)
    values (p_item, p_patch, p_note, auth.uid(), sid) returning id into cid;
  return jsonb_build_object('status', 'pending', 'id', cid);
end $$;
revoke all on function public.submit_item_change(uuid, jsonb, text) from public, anon;
grant execute on function public.submit_item_change(uuid, jsonb, text) to authenticated;

create or replace function public.decide_item_change(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.item_changes; sid text; self_ok boolean;
begin
  if not (public.is_owner() or public.can_do('ITEMS', 'approve') or (public.is_active() and public.has_grant('item_create'))) then raise exception 'not allowed'; end if;
  select * into c from public.item_changes where id = p_id for update;
  if not found or c.status <> 'pending' then raise exception 'request is not pending'; end if;
  if public.is_owner() then self_ok := public.rule_on('owner_self_approve');
  else self_ok := exists (select 1 from public.user_roles ur join public.roles r on r.code = ur.role_code where ur.user_id = auth.uid() and r.allow_self_approve);
  end if;
  if c.requested_by = auth.uid() and not self_ok then raise exception 'you cannot approve your own request'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_approve then perform set_config('bos.item_apply', '1', true); perform public.apply_item_patch(c.item_id, c.patch); perform set_config('bos.item_apply', '', true); end if;
  update public.item_changes set status = case when p_approve then 'approved' else 'rejected' end,
    decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = p_note where id = p_id;
  return jsonb_build_object('status', case when p_approve then 'approved' else 'rejected' end);
end $$;
revoke all on function public.decide_item_change(bigint, boolean, text) from public, anon;
grant execute on function public.decide_item_change(bigint, boolean, text) to authenticated;

-- ---------- (6) revisions (append-only) and change requests ----------
create table if not exists public.entry_revisions (
  entry_id uuid not null references public.entries(id),
  rev_no int not null,
  data jsonb not null, check_data jsonb not null default '{}', flags jsonb not null default '[]',
  changed_by uuid, changed_staff text,                 -- who asked for the change
  approved_by uuid, approved_staff text,               -- who decided it
  request_id bigint, reason text,
  at timestamptz not null default now(),
  primary key (entry_id, rev_no)
);
create or replace function public.entry_revisions_append_only() returns trigger
language plpgsql set search_path = public as $$
begin raise exception 'entry_revisions is append-only'; end $$;
drop trigger if exists entry_revisions_no_change on public.entry_revisions;
create trigger entry_revisions_no_change before update or delete on public.entry_revisions for each row execute function public.entry_revisions_append_only();
drop trigger if exists entry_revisions_no_truncate on public.entry_revisions;
create trigger entry_revisions_no_truncate before truncate on public.entry_revisions for each statement execute function public.entry_revisions_append_only();
alter table public.entry_revisions enable always trigger entry_revisions_no_truncate;
alter table public.entry_revisions enable row level security;
drop policy if exists entry_revisions_read on public.entry_revisions;
create policy entry_revisions_read on public.entry_revisions for select to authenticated
  using (exists (select 1 from public.entries e where e.id = entry_id));      -- exactly the entries the caller may read (entries RLS)
revoke all on public.entry_revisions from public, anon, authenticated;
grant select on public.entry_revisions to authenticated;

create table if not exists public.entry_change_requests (
  id bigserial primary key,
  entry_id uuid not null references public.entries(id),
  base_rev int not null,
  requested_by uuid not null, requested_staff text,
  reason text not null check (length(btrim(reason)) > 0),
  patch jsonb not null,                                -- {data?, check_data?, flags?}: the whole new value of each part named
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  created_at timestamptz not null default now(),
  decided_by uuid, decided_staff text, decided_at timestamptz, decision_note text, new_rev int
);
create unique index if not exists entry_change_one_pending on public.entry_change_requests (entry_id) where status = 'pending';
create index if not exists entry_change_status on public.entry_change_requests (status, created_at desc);
-- a delegate sees (and decides) requests only for entries of a place where the grant holds AND of a form he may view / approve there
create or replace function public._ecr_scope(p_entry uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or exists (select 1 from public.entries e where e.id = p_entry
    and public.has_grant('change_approve', e.location_id) and public.can_loc(e.location_id)
    and (public.can_do(e.form_code, 'approve') or public.can_do(e.form_code, 'view'))));
$$;
create or replace function public._ecr_can_see(p_requester uuid, p_entry uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (p_requester = auth.uid() or public._ecr_scope(p_entry));
$$;
alter table public.entry_change_requests enable row level security;
drop policy if exists entry_change_read on public.entry_change_requests;
create policy entry_change_read on public.entry_change_requests for select to authenticated using (public._ecr_can_see(requested_by, entry_id));
revoke all on public.entry_change_requests from public, anon, authenticated;
grant select on public.entry_change_requests to authenticated;
drop trigger if exists audit_entry_change on public.entry_change_requests;
create trigger audit_entry_change after insert or update on public.entry_change_requests for each row execute function public.log_change('id');
drop trigger if exists entry_change_no_delete on public.entry_change_requests;
create trigger entry_change_no_delete before delete on public.entry_change_requests for each row execute function public.no_hard_delete();

create or replace function public.entry_change_request(p_entry uuid, p_reason text, p_patch jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text; rid bigint;
begin
  if not public.rule_on('change_requests_on') then raise exception 'change_requests_off'; end if;
  if p_reason is null or length(btrim(p_reason)) = 0 then raise exception 'note_required'; end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' or not (p_patch ?| array['data', 'check_data', 'flags']) then raise exception 'bad_patch'; end if;
  if p_patch ? 'data' and jsonb_typeof(p_patch->'data') <> 'object' then raise exception 'bad_patch'; end if;
  if p_patch ? 'check_data' and jsonb_typeof(p_patch->'check_data') <> 'object' then raise exception 'bad_patch'; end if;
  if p_patch ? 'flags' and jsonb_typeof(p_patch->'flags') <> 'array' then raise exception 'bad_patch'; end if;
  if length(p_patch::text) > 400000 then raise exception 'bad_patch'; end if;
  select * into e from public.entries where id = p_entry;
  if not found then raise exception 'entry not found'; end if;
  if not (public.can_do(e.form_code, 'enter') and public.can_loc(e.location_id)) then raise exception 'not allowed'; end if;
  if e.status <> 'approved' then raise exception 'not_locked'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  begin
    insert into public.entry_change_requests (entry_id, base_rev, requested_by, requested_staff, reason, patch)
      values (e.id, e.rev_no, auth.uid(), sid, left(btrim(p_reason), 500), p_patch) returning id into rid;
  exception when unique_violation then raise exception 'change_pending'; end;
  return jsonb_build_object('id', rid, 'status', 'pending');
end $$;

create or replace function public.entry_change_cancel(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.entry_change_requests set status = 'cancelled', decided_by = auth.uid(), decided_at = now()
   where id = p_id and requested_by = auth.uid() and status = 'pending';
  if not found then raise exception 'request is not pending'; end if;
end $$;

create or replace function public.entry_change_decide(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.entry_change_requests; e public.entries; sid text; nd jsonb; nc jsonb; nf jsonb; auto boolean; nr int; self_ok boolean;
begin
  select * into r from public.entry_change_requests where id = p_id for update;
  if not found or r.status <> 'pending' then raise exception 'request is not pending'; end if;
  select * into e from public.entries where id = r.entry_id for update;
  if not public._ecr_scope(e.id) then raise exception 'not allowed'; end if;
  if public.is_owner() then self_ok := public.rule_on('owner_self_approve');
  else self_ok := exists (select 1 from public.user_roles ur join public.roles ro on ro.code = ur.role_code where ur.user_id = auth.uid() and ro.allow_self_approve);
  end if;
  if r.requested_by = auth.uid() and not self_ok then raise exception 'self_approval'; end if;
  if not p_approve and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if not p_approve then
    update public.entry_change_requests set status = 'rejected', decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = left(btrim(p_note), 500) where id = p_id;
    return jsonb_build_object('status', 'rejected');
  end if;
  if e.status <> 'approved' or e.rev_no <> r.base_rev then raise exception 'stale_request'; end if;
  nd := coalesce(r.patch->'data', e.data); nc := coalesce(r.patch->'check_data', e.check_data); nf := coalesce(r.patch->'flags', e.flags);
  if e.entered_later then nd := jsonb_set(nd, '{paper_no}', to_jsonb(e.paper_serial)); end if;     -- the paper serial never changes through a revision
  nr := e.rev_no + 1;
  insert into public.entry_revisions (entry_id, rev_no, data, check_data, flags, changed_by, changed_staff, approved_by, approved_staff, request_id, reason)
    values (e.id, e.rev_no, e.data, e.check_data, e.flags, r.requested_by, r.requested_staff, auth.uid(), sid, r.id, r.reason);
  update public.entries set data = nd, check_data = nc, flags = nf, rev_no = nr, updated_at = now() where id = e.id;
  if r.patch ? 'flags' then
    select coalesce((select (value #>> '{}')::boolean from public.settings where key = 'auto_exceptions'), true) into auto;
    delete from public.exceptions where entry_id = e.id and status = 'open';
    if auto then
      insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
        select e.id, e.form_code, e.location_id, e.entry_date, x->>'code', x->>'level', nullif(x->>'amount','')::numeric, x->'text'
        from jsonb_array_elements(nf) x;
    end if;
  end if;
  update public.entry_change_requests set status = 'approved', decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = left(btrim(p_note), 500), new_rev = nr where id = p_id;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'revision', 'entries', e.id::text, jsonb_build_object('form', e.form_code, 'serial', e.serial, 'from_rev', e.rev_no, 'to_rev', nr, 'request', r.id, 'reason', r.reason));
  return jsonb_build_object('status', 'approved', 'rev_no', nr);
end $$;

-- the history of an entry: every older version (immutable) and the current one
create or replace function public.entry_revisions_list(p_entry uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.entries;
begin
  select * into e from public.entries where id = p_entry;
  if not found then raise exception 'entry not found'; end if;
  if not (public.is_owner() or (public.can_do(e.form_code, 'view') and public.can_loc(e.location_id))) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(x order by (x->>'rev_no')::int desc) from (
      select jsonb_build_object('rev_no', v.rev_no, 'current', false, 'data', v.data, 'check_data', v.check_data, 'flags', v.flags,
             'changed_staff', v.changed_staff, 'approved_staff', v.approved_staff, 'at', v.at, 'reason', v.reason) x
      from public.entry_revisions v where v.entry_id = e.id
      union all
      select jsonb_build_object('rev_no', e.rev_no, 'current', true, 'data', e.data, 'check_data', e.check_data, 'flags', e.flags,
             'changed_staff', null, 'approved_staff', e.checked_staff, 'at', e.updated_at, 'reason', null)) q), '[]'::jsonb);
end $$;

-- how many change requests the caller may decide (for Needs-you / badge)
create or replace function public.entry_change_counts() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('pending', (select count(*) from public.entry_change_requests q where q.status = 'pending' and public._ecr_scope(q.entry_id)
    and (q.requested_by <> auth.uid() or (public.is_owner() and public.rule_on('owner_self_approve')))));
$$;

-- reopen (owner): pending change requests of the entry are cancelled; the approved version is kept and becomes a revision only if the re-approved entry differs
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
  if e.status = 'approved' then
    update public.entries set reopen_snap = jsonb_build_object('data', e.data, 'check_data', e.check_data, 'flags', e.flags, 'by', auth.uid(), 'staff', sid, 'reason', 'reopened: ' || left(btrim(p_note), 400)) where id = p_id;
  end if;
  update public.entry_change_requests set status = 'cancelled', decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = 'entry reopened by the owner'
    where entry_id = p_id and status = 'pending';
  update public.entries set status = 'draft', submitted_at = null, checked_by = null, checked_staff = null, checked_at = null, check_note = null, check_data = '{}', updated_at = now() where id = p_id;
  return jsonb_build_object('status', 'draft');
end $$;
revoke all on function public.reopen_entry(uuid, text) from public, anon;
grant execute on function public.reopen_entry(uuid, text) to authenticated;

-- ---------- (7) gap audit over both series ----------
create or replace function public.number_audit_both(p_form text, p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lo bigint; hi bigint; cnt bigint; miss_n bigint; miss bigint[]; later bigint; pa jsonb; ap jsonb;
begin
  if not (public.is_owner() or (public.can_do(p_form, 'approve') and public.can_loc(p_loc))) then raise exception 'not allowed'; end if;
  begin pa := public.number_audit(p_form, p_loc);
  exception when others then
    if sqlerrm like '%range too wide%' then pa := jsonb_build_object('range_too_wide', true); else raise; end if;
  end;
  select min(serial), max(serial), count(*) into lo, hi, cnt from public.entries where form_code = p_form and location_id = p_loc;
  select count(*) into later from public.entries where form_code = p_form and location_id = p_loc and entered_later;
  if cnt = 0 then ap := jsonb_build_object('entered', 0, 'missing_count', 0, 'missing', '[]'::jsonb);
  elsif hi - lo > 100000 then ap := jsonb_build_object('entered', cnt, 'first', lo, 'last', hi, 'range_too_wide', true);
  else
    select coalesce(array_agg(g order by g), '{}') into miss from (select g from generate_series(lo, hi) g where not exists (select 1 from public.entries e where e.form_code = p_form and e.location_id = p_loc and e.serial = g) limit 200) m;
    select count(*) into miss_n from generate_series(lo, hi) g where not exists (select 1 from public.entries e where e.form_code = p_form and e.location_id = p_loc and e.serial = g);
    ap := jsonb_build_object('entered', cnt, 'first', lo, 'last', hi, 'missing_count', miss_n, 'missing', to_jsonb(miss));
  end if;
  return jsonb_build_object('paper', pa, 'app', ap, 'entered_later', later);
end $$;

-- ---------- (7b) the owner self-approval switch may only go OFF while another person can approve ----------
create or replace function public._other_approver_exists() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p where p.status = 'active' and p.id <> auth.uid() and (
      exists (select 1 from public.user_roles ur where ur.user_id = p.id and ur.role_code = 'owner')
      or exists (select 1 from public.user_roles ur join public.role_form_perms f on f.role_code = ur.role_code join public.roles ro on ro.code = ur.role_code and ro.active
                 where ur.user_id = p.id and f.can_approve)
      or exists (select 1 from public.user_grants g where g.user_id = p.id and g.grant_code in ('change_approve', 'release_decide', 'item_create') and (g.valid_until is null or g.valid_until > now()))));
$$;
create or replace function public.owner_self_approve_set(p_on boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_on is null then raise exception 'bad_value'; end if;
  if not p_on and not public._other_approver_exists() then raise exception 'no_other_approver'; end if;
  perform public.set_rule('owner_self_approve', to_jsonb(p_on));
  return jsonb_build_object('owner_self_approve', p_on);
end $$;
create or replace function public._rules_self_approve_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- only for the API roles (set_rule through the app): a direct SQL update by the database owner is not blocked
  if current_setting('role', true) = 'authenticated' and new.key = 'owner_self_approve'
     and coalesce(new.value, new.default_value) = 'false'::jsonb and not public._other_approver_exists() then raise exception 'no_other_approver'; end if;
  return new;
end $$;
drop trigger if exists rules_self_approve_guard on public.rules;
create trigger rules_self_approve_guard before update on public.rules for each row execute function public._rules_self_approve_guard();
revoke all on function public._other_approver_exists(), public.owner_self_approve_set(boolean), public._rules_self_approve_guard(), public._ecr_scope(uuid), public.norm_paper_serial(text), public.paper_serial_collisions() from public, anon;
grant execute on function public.owner_self_approve_set(boolean), public.paper_serial_collisions(), public._ecr_scope(uuid), public.norm_paper_serial(text) to authenticated;

-- ---------- (8) privileges ----------
revoke all on function public.rollout_mode(text, int), public._rollout_mgr(), public.rollout_set(text, int, text, text), public.rollout_set_many(text[], int[], text, text),
  public._entries_rollout_guard(), public.entry_revisions_append_only(), public.entry_change_request(uuid, text, jsonb),
  public.entry_change_cancel(bigint), public.entry_change_decide(bigint, boolean, text), public.entry_revisions_list(uuid), public.entry_change_counts(),
  public.number_audit_both(text, int), public._ecr_can_see(uuid, uuid) from public, anon;
grant execute on function public.rollout_mode(text, int), public.rollout_set(text, int, text, text), public.rollout_set_many(text[], int[], text, text),
  public.entry_change_request(uuid, text, jsonb), public.entry_change_cancel(bigint), public.entry_change_decide(bigint, boolean, text),
  public.entry_revisions_list(uuid), public.entry_change_counts(), public.number_audit_both(text, int) to authenticated;
grant execute on function public._ecr_can_see(uuid, uuid) to authenticated;   -- used by the RLS policy
revoke execute on function public._rollout_mgr(), public._entries_rollout_guard(), public.entry_revisions_append_only() from authenticated;

-- ===================== phase18.sql =====================
-- PHASE 18 (W5): server-side BLIND COUNT for forms 14-1 (drawer) and 10-1 (hub), and PIN SIGNATURES (second signature = another login).
-- Additive, idempotent, safe to paste whole in the Supabase SQL editor.  ORDER: phase8..phase17 first (needs phase16 get_limit and phase17 for nothing else).
-- Everything is OFF by default: rules blind_count_on, pin_signature_on = false.  Nothing changes for any form until the owner switches them on.
--
-- BLIND COUNT (rule 9)
--   count_save(entry, section, counted): the counted figure is stored FIRST (immutable), the expected figure is computed on the server from the
--   entry's other saved data and returned only after the save.  Short/over is stored always (also 0) in entry_counts and mirrored to
--   entries.check_data.blind.  `expected` is never stored in entries.data and never returned by any function before the count is saved,
--   except to the owner / holders of the delegable grant see_expected (count_peek, logged; rule owner_sees_expected_first can take it from the owner too).
--   sections: 'drawer' = 14-1 (the maker counts the cash drawer), 'hub' = 10-1 (the hub person counts the handover).
-- PIN SIGNATURES (rule 10)
--   A second signature is a different login with its own PIN.  The browser signs the second person in on a throw-away client (no session kept)
--   and that client calls sign_entry: auth.uid() is the signer.  The server refuses signer = maker, one login twice, a role signed twice,
--   a signer without access to the place, a locked login.  entry_signatures is append-only.  Wrong PINs go through login_failed (phase11).
--   NOTE: SQL cannot check another user's password, so the PIN itself is checked by Supabase Auth, not by this file.

-- ---------- (1) rules + grant ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('blind_count_on', 'entries', 'switch', 'false', null, null, null, null, 'অন্ধ গণনা: আগে গণনা সেভ, তারপর প্রত্যাশিত অঙ্ক', 'Blind count: আগে count save, তারপর expected', 'Blind count: save the count first, then see the expected figure',
   'চালু করলে ১৪-১ (ড্রয়ার) ও ১০-১ (হাব)-এ প্রত্যাশিত অঙ্ক গণনা সেভের আগে দেখা যাবে না। ফর্ম × লোকেশন আলাদা করে বন্ধ করা যায়', 'চালু করলে 14-1 (drawer) ও 10-1 (hub)-এ expected figure count save-এর আগে দেখা যাবে না। form × location আলাদা বন্ধ করা যায়', 'When on, forms 14-1 (drawer) and 10-1 (hub) do not show the expected figure before the count is saved. Can be switched off per form x place', 94),
 ('owner_sees_expected_first', 'entries', 'switch', 'true', null, null, null, null, 'মালিক গণনার আগেও প্রত্যাশিত অঙ্ক দেখতে পারবেন', 'Owner count-এর আগেও expected দেখতে পারবেন', 'Owner may see the expected figure before the count is saved',
   'বন্ধ করলে মালিকও আগে দেখতে পারবেন না (see_expected অনুমতিপ্রাপ্ত অন্য কেউ পারবেন)। প্রতিবার দেখা লগে থাকে', 'বন্ধ করলে owner-ও আগে দেখতে পারবেন না (see_expected grant-ওয়ালা অন্য কেউ পারবেন)। প্রতিবার log-এ থাকে', 'When off the owner is blind too (a person holding see_expected still may). Every early look is logged', 95),
 ('pin_signature_owner_override', 'entries', 'switch', 'false', null, null, null, null, 'পিন স্বাক্ষর ছাড়া জমা: মালিকের ছাড় (হলুদ এক্সেপশনসহ)', 'PIN signature ছাড়া submit: owner override (yellow exception সহ)', 'Owner may submit without the PIN signatures (yellow exception)',
   'চালু থাকলে শুধু মালিক স্বাক্ষর ছাড়া জমা দিতে পারবেন; হলুদ এক্সেপশন তৈরি হয়', 'চালু থাকলে শুধু owner signature ছাড়া submit করতে পারবেন; yellow exception হয়', 'When on only the owner may submit without signatures; a yellow exception is raised', 97),
 ('pin_signature_on', 'entries', 'switch', 'false', null, null, null, null, 'পিন স্বাক্ষর: দ্বিতীয় স্বাক্ষর অন্য লগইন + নিজের পিন', 'PIN signature: দ্বিতীয় signature অন্য login + নিজের PIN', 'PIN signature: the second signature is another login with its own PIN',
   'বন্ধ থাকলে আগের মতো নাম বেছে সাক্ষী। চালু করলে ফর্ম অনুযায়ী (তালিকা) সাক্ষী নিজের পিন দিয়ে স্বাক্ষর করবেন; লেখক নিজে স্বাক্ষর করতে পারবেন না', 'বন্ধ থাকলে আগের মতো name বেছে witness। চালু করলে form অনুযায়ী witness নিজের PIN দিয়ে sign করবেন', 'When off the old name-picker witness stays. When on (per form list) the witness signs with their own PIN; the maker can never be the signer', 96)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('see_expected', 'master', 69, 'গণনা সেভের আগে প্রত্যাশিত অঙ্ক দেখা', 'Count save-এর আগে expected দেখা', 'See the expected figure before the count is saved', 'window', null)
on conflict (grant_code) do nothing;

-- ---------- (2) per form x place / per form switch lists ----------
create table if not exists public.blind_count_cfg (
  form_code text not null references public.forms(code),
  location_id int not null references public.locations(id),
  enabled boolean not null default true,
  changed_by uuid, changed_at timestamptz not null default now(),
  primary key (form_code, location_id)
);
create table if not exists public.pin_sig_cfg (
  form_code text primary key references public.forms(code),
  enabled boolean not null default true,
  changed_by uuid, changed_at timestamptz not null default now()
);
alter table public.blind_count_cfg enable row level security;
alter table public.pin_sig_cfg enable row level security;
drop policy if exists blind_count_cfg_read on public.blind_count_cfg;
create policy blind_count_cfg_read on public.blind_count_cfg for select to authenticated using (public.is_active());
drop policy if exists pin_sig_cfg_read on public.pin_sig_cfg;
create policy pin_sig_cfg_read on public.pin_sig_cfg for select to authenticated using (public.is_active());
revoke all on public.blind_count_cfg, public.pin_sig_cfg from public, anon, authenticated;
grant select on public.blind_count_cfg, public.pin_sig_cfg to authenticated;
drop trigger if exists audit_blind_count_cfg on public.blind_count_cfg;
create trigger audit_blind_count_cfg after insert or update on public.blind_count_cfg for each row execute function public.log_change('form_code,location_id');
drop trigger if exists audit_pin_sig_cfg on public.pin_sig_cfg;
create trigger audit_pin_sig_cfg after insert or update on public.pin_sig_cfg for each row execute function public.log_change('form_code');
drop trigger if exists blind_count_cfg_no_delete on public.blind_count_cfg;
create trigger blind_count_cfg_no_delete before delete on public.blind_count_cfg for each row execute function public.no_hard_delete();
drop trigger if exists pin_sig_cfg_no_delete on public.pin_sig_cfg;
create trigger pin_sig_cfg_no_delete before delete on public.pin_sig_cfg for each row execute function public.no_hard_delete();

create or replace function public.blind_active(p_form text, p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select p_form in ('14-1', '10-1') and public.rule_on('blind_count_on')
     and coalesce((select enabled from public.blind_count_cfg where form_code = p_form and location_id = p_loc), true);
$$;
create or replace function public.pin_sig_active(p_form text) returns boolean
language sql stable security definer set search_path = public as $$
  select p_form in ('14-1', '10-1') and public.rule_on('pin_signature_on')
     and coalesce((select enabled from public.pin_sig_cfg where form_code = p_form), true);
$$;
create or replace function public.blind_cfg_set(p_form text, p_loc int, p_enabled boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_form not in ('14-1', '10-1') then raise exception 'form_not_supported'; end if;
  if p_enabled is null then raise exception 'bad_value'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'location_not_found'; end if;
  insert into public.blind_count_cfg (form_code, location_id, enabled, changed_by, changed_at) values (p_form, p_loc, p_enabled, auth.uid(), now())
    on conflict (form_code, location_id) do update set enabled = excluded.enabled, changed_by = excluded.changed_by, changed_at = excluded.changed_at;
  return jsonb_build_object('form', p_form, 'location_id', p_loc, 'enabled', p_enabled);
end $$;
create or replace function public.pin_sig_cfg_set(p_form text, p_enabled boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_form not in ('14-1', '10-1') then raise exception 'form_not_supported'; end if;
  if p_enabled is null then raise exception 'bad_value'; end if;
  insert into public.pin_sig_cfg (form_code, enabled, changed_by, changed_at) values (p_form, p_enabled, auth.uid(), now())
    on conflict (form_code) do update set enabled = excluded.enabled, changed_by = excluded.changed_by, changed_at = excluded.changed_at;
  return jsonb_build_object('form', p_form, 'enabled', p_enabled);
end $$;

-- ---------- (3) counts ----------
-- the maker of a draft must not learn expected / diff from the server while blind is on (only an approver, or a see_expected holder, does)
create or replace function public._count_hide18(e public.entries) returns boolean
language sql stable security definer set search_path = public as $$
  select public.blind_active(e.form_code, e.location_id) and e.status = 'draft' and e.created_by = auth.uid() and not public.has_grant('see_expected', e.location_id);
$$;
create table if not exists public.entry_counts (
  entry_id uuid not null references public.entries(id),
  section text not null check (section in ('drawer', 'hub')),
  counted_detail jsonb not null,                 -- what the person typed (notes by denomination, or one number)
  counted numeric not null check (counted between 0 and 1000000000),
  expected numeric not null,                     -- computed on the server at save time (kept here, never in entries.data)
  diff numeric not null,                         -- counted - expected, ALWAYS stored, also 0
  inputs_hash text,                              -- hash of the figures the expected value was made from
  counted_by uuid not null, counted_staff text, counted_at timestamptz not null default now(),
  expected_seen_by uuid, expected_seen_at timestamptz,
  seen_before_count boolean not null default false,
  primary key (entry_id, section)
);
create table if not exists public.entry_count_peeks (
  id bigserial primary key,
  entry_id uuid not null references public.entries(id),
  section text not null,
  seen_by uuid not null, seen_staff text, seen_at timestamptz not null default now()
);
create or replace function public._append_only18() returns trigger
language plpgsql set search_path = public as $$
begin raise exception '% is append-only', tg_table_name; end $$;
drop trigger if exists entry_counts_no_change on public.entry_counts;
create trigger entry_counts_no_change before update or delete on public.entry_counts for each row execute function public._append_only18();
drop trigger if exists entry_counts_no_truncate on public.entry_counts;
create trigger entry_counts_no_truncate before truncate on public.entry_counts for each statement execute function public._append_only18();
alter table public.entry_counts enable always trigger entry_counts_no_truncate;
drop trigger if exists entry_count_peeks_no_change on public.entry_count_peeks;
create trigger entry_count_peeks_no_change before update or delete on public.entry_count_peeks for each row execute function public._append_only18();
drop trigger if exists entry_count_peeks_no_truncate on public.entry_count_peeks;
create trigger entry_count_peeks_no_truncate before truncate on public.entry_count_peeks for each statement execute function public._append_only18();
alter table public.entry_count_peeks enable always trigger entry_count_peeks_no_truncate;
alter table public.entry_counts enable row level security;
alter table public.entry_count_peeks enable row level security;
drop policy if exists entry_counts_read on public.entry_counts;
create policy entry_counts_read on public.entry_counts for select to authenticated
  using (exists (select 1 from public.entries e where e.id = entry_id and not public._count_hide18(e)));      -- rows exist only AFTER the count; the maker of a blind draft does not read expected / diff
drop policy if exists entry_count_peeks_read on public.entry_count_peeks;
create policy entry_count_peeks_read on public.entry_count_peeks for select to authenticated using (public.is_owner());
revoke all on public.entry_counts, public.entry_count_peeks from public, anon, authenticated;
grant select on public.entry_counts, public.entry_count_peeks to authenticated;
revoke all on sequence public.entry_count_peeks_id_seq from public, anon, authenticated;

-- lenient number of a json field (blank / junk / Infinity = 0), same as the browser's num()
create or replace function public._n18(j jsonb, k text) returns numeric
language plpgsql immutable set search_path = public as $$
declare v numeric;
begin
  v := nullif(btrim(coalesce(j ->> k, '')), '')::numeric;
  if v is null or not (v between -1000000000000 and 1000000000000) then return 0; end if;
  return v;
exception when others then return 0;
end $$;

-- total of a count: a plain number, or notes by denomination {n1000..n1, coin}.  strict = refuse bad input
create or replace function public._den_total18(j jsonb, strict boolean) returns numeric
language plpgsql immutable set search_path = public as $$
declare t numeric := 0; d int; v numeric; k text;
begin
  if j is null or jsonb_typeof(j) = 'null' then return 0; end if;
  if jsonb_typeof(j) = 'number' then
    v := (j #>> '{}')::numeric;
    if not (v between 0 and 1000000000) then if strict then raise exception 'bad_count'; end if; return 0; end if;
    return v;
  end if;
  if jsonb_typeof(j) <> 'object' then if strict then raise exception 'bad_count'; end if; return 0; end if;
  foreach d in array array[1000, 500, 200, 100, 50, 20, 10, 5, 2, 1] loop
    k := 'n' || d;
    if j ? k then
      begin v := nullif(btrim(j ->> k), '')::numeric; exception when others then v := null; if strict then raise exception 'bad_count'; end if; end;
      if v is not null then
        if not (v between 0 and 1000000) or (strict and v <> trunc(v)) then if strict then raise exception 'bad_count'; end if; v := 0; end if;
        t := t + d * v;
      end if;
    end if;
  end loop;
  if j ? 'coin' then
    begin v := nullif(btrim(j ->> 'coin'), '')::numeric; exception when others then v := null; if strict then raise exception 'bad_count'; end if; end;
    if v is not null then
      if not (v between 0 and 1000000000) then if strict then raise exception 'bad_count'; end if; v := 0; end if;
      t := t + v;
    end if;
  end if;
  if not (t between 0 and 1000000000) then if strict then raise exception 'bad_count'; end if; return 0; end if;
  return t;
end $$;

-- the figures the expected value is made of (also hashed, to show later changes)
create or replace function public._count_inputs18(e public.entries, p_section text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare fl numeric; fj jsonb; d jsonb := e.data;
begin
  if p_section = 'drawer' then
    begin fj := public.get_limit(e.location_id, 'drawer_float', e.entry_date); exception when others then fj := null; end;
    fl := case when fj is null or jsonb_typeof(fj) <> 'number' then null else (fj #>> '{}')::numeric end;
    return jsonb_build_object('float', fl, 'open_counted', nullif(btrim(coalesce(d ->> 'open_counted', '')), ''),
      'total', public._n18(d, 'total_entered'), 'digital', public._n18(d, 'd_bkash') + public._n18(d, 'd_nagad') + public._n18(d, 'd_card') + public._n18(d, 'd_bank') + public._n18(d, 'd_other'),
      'dues', public._n18(d, 'dues'), 'new_adv', public._n18(d, 'new_adv'), 'prior_adv', public._n18(d, 'prior_adv'), 'refund', public._n18(d, 'refund'),
      'credit', public._n18(d, 'credit_sales'), 'midday', public._n18(d, 'midday_hub'), 'rounding', public._n18(d, 'rounding'));
  end if;
  return jsonb_build_object('sent', public._den_total18(d -> 'count', false), 'leave', public._n18(d, 'leave_float'));
end $$;
-- same arithmetic as forms.js (14-1: guidebook G.6 equation 1; 10-1: handover = counted - float left)
create or replace function public._count_expected18(p_in jsonb, p_section text) returns numeric
language plpgsql immutable set search_path = public as $$
declare openf numeric;
begin
  if p_section = 'drawer' then
    openf := case when p_in ->> 'open_counted' is not null then (p_in ->> 'open_counted')::numeric when p_in ->> 'float' is not null then (p_in ->> 'float')::numeric else 0 end;
    return openf + (p_in ->> 'total')::numeric - (p_in ->> 'digital')::numeric + (p_in ->> 'dues')::numeric + (p_in ->> 'new_adv')::numeric - (p_in ->> 'prior_adv')::numeric
      - (p_in ->> 'refund')::numeric - (p_in ->> 'credit')::numeric - (p_in ->> 'midday')::numeric + (p_in ->> 'rounding')::numeric;
  end if;
  return (p_in ->> 'sent')::numeric - (p_in ->> 'leave')::numeric;
end $$;

create or replace function public._count_sec18(p_section text) returns text
language sql immutable as $$ select case p_section when 'drawer' then '14-1' when 'hub' then '10-1' end; $$;

-- may the caller count / peek at this entry?
create or replace function public._count_can18(e public.entries, p_section text, p_for_save boolean) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare self_ok boolean;
begin
  if not public.is_active() or not public.can_loc(e.location_id) then return false; end if;
  if public.is_owner() then return true; end if;
  if p_section = 'drawer' then
    return e.created_by = auth.uid() or (not p_for_save and public.can_do(e.form_code, 'approve'));
  end if;
  if not public.can_do(e.form_code, 'approve') then return false; end if;
  select exists (select 1 from public.user_roles ur join public.roles r on r.code = ur.role_code where ur.user_id = auth.uid() and r.allow_self_approve) into self_ok;
  return e.created_by <> auth.uid() or self_ok;
end $$;


-- counted but never submitted (throw-away drafts): an owner exception once the business day is over (no invented time limit)
create or replace function public.count_unsubmitted_scan() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
    select e.id, e.form_code, e.location_id, e.entry_date, 'count_unsubmitted', 'red', null,
           jsonb_build_object('bn', 'গণনা সেভ হয়েছে কিন্তু শিট জমা হয়নি', 'en', 'Count saved but the sheet was never submitted')
    from public.entry_counts c join public.entries e on e.id = c.entry_id
    where c.section = 'drawer' and e.status = 'draft' and e.entry_date < (now() at time zone 'Asia/Dhaka')::date
      and not exists (select 1 from public.exceptions x where x.entry_id = e.id and x.flag_code = 'count_unsubmitted');
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.count_save(p_entry uuid, p_section text, p_counted jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; tot numeric; inp jsonb; ex numeric; df numeric; sid text; c public.entry_counts; peek public.entry_count_peeks; hide boolean;
begin
  if p_section not in ('drawer', 'hub') then raise exception 'bad_section'; end if;
  perform public.count_unsubmitted_scan();
  select * into e from public.entries where id = p_entry for update;
  if not found then raise exception 'entry not found'; end if;
  if e.form_code <> public._count_sec18(p_section) then raise exception 'bad_section'; end if;
  if not public._count_can18(e, p_section, true) then raise exception 'not allowed'; end if;
  if (p_section = 'drawer' and e.status <> 'draft') or (p_section = 'hub' and e.status <> 'submitted') then raise exception 'count_not_open'; end if;
  tot := public._den_total18(p_counted, true);
  select * into c from public.entry_counts where entry_id = p_entry and section = p_section;
  if found then
    -- a retry of the same count (lost answer) gets the saved result; a different figure is refused: the count never changes
    if c.counted = tot and c.counted_by = auth.uid() then
      if public._count_hide18(e) then return jsonb_build_object('section', p_section, 'saved', true, 'counted', c.counted, 'hidden', true, 'already', true); end if;
      return jsonb_build_object('section', p_section, 'counted', c.counted, 'expected', c.expected, 'diff', c.diff, 'match', c.diff = 0, 'already', true);
    end if;
    raise exception 'count_already_saved';
  end if;
  if p_section = 'drawer' then
    if not (e.data ? 'cash_count') then raise exception 'count_missing'; end if;
    if public._den_total18(e.data -> 'cash_count', false) <> tot then raise exception 'count_mismatch'; end if;
    -- one counted open draft per person, place and day: no throw-away drafts to read the expected figure
    if exists (select 1 from public.entries x join public.entry_counts k on k.entry_id = x.id and k.section = 'drawer'
               where x.form_code = e.form_code and x.location_id = e.location_id and x.entry_date = e.entry_date and x.created_by = e.created_by and x.status = 'draft' and x.id <> e.id) then
      raise exception 'count_draft_limit';
    end if;
  end if;
  if p_section = 'hub' and (e.check_data ? 'rcount') and public._den_total18(e.check_data -> 'rcount', false) <> tot then raise exception 'count_mismatch'; end if;
  inp := public._count_inputs18(e, p_section);
  ex := public._count_expected18(inp, p_section);
  df := tot - ex;
  select staff_id into sid from public.profiles where id = auth.uid();
  select * into peek from public.entry_count_peeks where entry_id = p_entry and section = p_section and seen_by = auth.uid() order by id limit 1;
  insert into public.entry_counts (entry_id, section, counted_detail, counted, expected, diff, inputs_hash, counted_by, counted_staff, counted_at, expected_seen_by, expected_seen_at, seen_before_count)
    values (p_entry, p_section, coalesce(p_counted, 'null'::jsonb), tot, ex, df, md5(inp::text), auth.uid(), sid, now(),
            coalesce(peek.seen_by, auth.uid()), coalesce(peek.seen_at, now()),
            exists (select 1 from public.entry_count_peeks where entry_id = p_entry and section = p_section));
  update public.entries set check_data = check_data where id = p_entry;          -- the guard trigger mirrors the result into check_data.blind (not while a draft)
  if public._count_hide18(e) then return jsonb_build_object('section', p_section, 'saved', true, 'counted', tot, 'hidden', true); end if;
  return jsonb_build_object('section', p_section, 'counted', tot, 'expected', ex, 'diff', df, 'match', df = 0);
end $$;

-- the expected figure BEFORE the count: only the owner (rule owner_sees_expected_first) or a holder of see_expected; every look is logged
create or replace function public.count_peek(p_entry uuid, p_section text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; c public.entry_counts; inp jsonb; sid text;
begin
  if p_section not in ('drawer', 'hub') then raise exception 'bad_section'; end if;
  select * into e from public.entries where id = p_entry;
  if not found then raise exception 'entry not found'; end if;
  if e.form_code <> public._count_sec18(p_section) then raise exception 'bad_section'; end if;
  if not public._count_can18(e, p_section, false) then raise exception 'not allowed'; end if;
  select * into c from public.entry_counts where entry_id = p_entry and section = p_section;
  if found then
    if public._count_hide18(e) then return jsonb_build_object('saved', true, 'counted', c.counted, 'hidden', true); end if;
    return jsonb_build_object('saved', true, 'counted', c.counted, 'expected', c.expected, 'diff', c.diff);
  end if;
  if public.blind_active(e.form_code, e.location_id) then
    if public.is_owner() and not public.rule_on('owner_sees_expected_first') and not exists (
         select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'see_expected' and (g.valid_until is null or g.valid_until > now()) and (g.location_id is null or g.location_id = e.location_id)) then
      raise exception 'not allowed';
    end if;
    if not public.has_grant('see_expected', e.location_id) then raise exception 'not allowed'; end if;
    select staff_id into sid from public.profiles where id = auth.uid();
    insert into public.entry_count_peeks (entry_id, section, seen_by, seen_staff) values (p_entry, p_section, auth.uid(), sid);
  end if;
  inp := public._count_inputs18(e, p_section);
  return jsonb_build_object('saved', false, 'expected', public._count_expected18(inp, p_section));
end $$;

-- the saved count of an entry (no expected figure unless it is saved)
create or replace function public.count_get(p_entry uuid, p_section text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.entries; c public.entry_counts;
begin
  select * into e from public.entries where id = p_entry;
  if not found or not public.is_active() or not public.can_loc(e.location_id) then raise exception 'not allowed'; end if;
  select * into c from public.entry_counts where entry_id = p_entry and section = p_section;
  if not found then return jsonb_build_object('saved', false, 'blind', public.blind_active(e.form_code, e.location_id)); end if;
  if public._count_hide18(e) then return jsonb_build_object('saved', true, 'counted', c.counted, 'hidden', true, 'counted_at', c.counted_at); end if;
  return jsonb_build_object('saved', true, 'counted', c.counted, 'expected', c.expected, 'diff', c.diff, 'match', c.diff = 0, 'counted_at', c.counted_at, 'counted_staff', c.counted_staff,
    'seen_before_count', c.seen_before_count, 'inputs_changed', md5(public._count_inputs18(e, p_section)::text) is distinct from c.inputs_hash);
end $$;

-- guard on entries: a saved count cannot be changed through the entry, the result is mirrored into check_data.blind once the sheet is submitted,
-- and the server adds the cash short/over flag at submit (the maker never sees expected / diff before that)
create or replace function public._entries_blind_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare r public.entry_counts; tol numeric; tj jsonb; lvl text;
begin
  for r in select * from public.entry_counts where entry_id = new.id loop
    if r.section = 'drawer' then
      if new.data is distinct from old.data and (new.data ? 'cash_count') and public._den_total18(new.data -> 'cash_count', false) <> r.counted then raise exception 'count_locked'; end if;
      if old.status = 'draft' and new.status = 'submitted' then
        if not (new.data ? 'cash_count') or public._den_total18(new.data -> 'cash_count', false) <> r.counted then raise exception 'count_locked'; end if;
        if r.diff <> 0 and not exists (select 1 from jsonb_array_elements(new.flags) f where f ->> 'code' = 'cash_short_over') then
          begin tj := public.get_limit(new.location_id, 'cash_tol', new.entry_date); exception when others then tj := null; end;
          tol := case when tj is not null and jsonb_typeof(tj) = 'number' then (tj #>> '{}')::numeric end;
          lvl := case when tol is not null and abs(r.diff) <= tol then 'yellow' else 'red' end;
          new.flags := new.flags || jsonb_build_array(jsonb_build_object('code', 'cash_short_over', 'level', lvl, 'amount', r.diff, 'src', 'system',
            'text', case when r.diff < 0 then jsonb_build_object('bn', 'ক্যাশ কম', 'en', 'Cash short') else jsonb_build_object('bn', 'ক্যাশ বেশি', 'en', 'Cash over') end));
        end if;
      end if;
    elsif new.check_data ? 'rcount' and public._den_total18(new.check_data -> 'rcount', false) <> r.counted then raise exception 'count_locked';
    end if;
  end loop;
  if new.status = 'draft' then
    new.check_data := coalesce(new.check_data, '{}'::jsonb) - 'blind';
  elsif exists (select 1 from public.entry_counts where entry_id = new.id) then
    new.check_data := coalesce(new.check_data, '{}'::jsonb) || jsonb_build_object('blind', (
      select jsonb_object_agg(section, jsonb_build_object('counted', counted, 'expected', expected, 'diff', diff, 'match', diff = 0, 'counted_at', counted_at))
      from public.entry_counts where entry_id = new.id));
  end if;
  return new;
end $$;
drop trigger if exists entries_blind_guard on public.entries;
create trigger entries_blind_guard before update on public.entries for each row execute function public._entries_blind_guard();

-- ---------- (4) PIN signatures ----------
create table if not exists public.entry_signatures (
  id bigserial primary key,
  entry_id uuid not null references public.entries(id),
  role text not null check (role in ('witness', 'second_sig', 'hub_pair')),
  signer_id uuid not null, signer_staff text,
  signed_at timestamptz not null default now(),
  data_hash text not null,                         -- md5 of the sheet (without the signer names) when it was signed: a later change makes the signature stale
  unique (entry_id, role, data_hash),
  unique (entry_id, signer_id, data_hash)
);
drop trigger if exists entry_signatures_no_change on public.entry_signatures;
create trigger entry_signatures_no_change before update or delete on public.entry_signatures for each row execute function public._append_only18();
drop trigger if exists entry_signatures_no_truncate on public.entry_signatures;
create trigger entry_signatures_no_truncate before truncate on public.entry_signatures for each statement execute function public._append_only18();
alter table public.entry_signatures enable always trigger entry_signatures_no_truncate;
alter table public.entry_signatures enable row level security;
drop policy if exists entry_signatures_read on public.entry_signatures;
create policy entry_signatures_read on public.entry_signatures for select to authenticated using (exists (select 1 from public.entries e where e.id = entry_id));
revoke all on public.entry_signatures from public, anon, authenticated;
grant select on public.entry_signatures to authenticated;
drop trigger if exists audit_entry_signatures on public.entry_signatures;
create trigger audit_entry_signatures after insert on public.entry_signatures for each row execute function public.log_change('entry_id,role');

create or replace function public._sig_hash18(d jsonb) returns text
language sql immutable as $$ select md5(((coalesce(d, '{}'::jsonb)) - 'witness' - 'second_sig' - 'pair_by')::text); $$;
create or replace function public._addflag18(fl jsonb, p_code text, p_level text, p_bn text, p_en text) returns jsonb
language sql immutable as $$ select coalesce(fl, '[]'::jsonb) || jsonb_build_array(jsonb_build_object('code', p_code, 'level', p_level, 'src', 'system', 'text', jsonb_build_object('bn', p_bn, 'en', p_en))); $$;

-- called by the SECOND person's own session (their PIN was checked by Supabase Auth in the browser): auth.uid() is the signer
create or replace function public.sign_entry(p_entry uuid, p_role text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text; iat numeric; h text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into e from public.entries where id = p_entry for update;
  -- place first, one text for every refusal of access (no hint whether the entry exists)
  if not found or not public.can_loc(e.location_id) or not (public.can_do(e.form_code, 'enter') or public.can_do(e.form_code, 'approve')) then raise exception 'not allowed'; end if;
  if p_role not in ('witness', 'second_sig', 'hub_pair') then raise exception 'bad_role'; end if;
  if (p_role in ('witness', 'second_sig') and e.form_code <> '14-1') or (p_role = 'hub_pair' and e.form_code <> '10-1') then raise exception 'bad_role'; end if;
  if not public.pin_sig_active(e.form_code) then raise exception 'pin_signature_off'; end if;
  if e.status not in ('draft', 'submitted') then raise exception 'entry is locked'; end if;
  if e.created_by = auth.uid() then raise exception 'signer_is_maker'; end if;
  -- a fresh sign-in just now (the browser signs the signer in on a second client): an old token cannot sign
  begin iat := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'iat', nullif(current_setting('request.jwt.claim.iat', true), ''))::numeric; exception when others then iat := null; end;
  if iat is null or iat < extract(epoch from now()) - 120 then raise exception 'login_not_fresh'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if exists (select 1 from public.login_failures f where f.staff_id = sid and f.locked and (f.locked_until is null or f.locked_until > now())) then raise exception 'signer_locked'; end if;
  h := public._sig_hash18(e.data);
  if exists (select 1 from public.entry_signatures where entry_id = p_entry and signer_id = auth.uid() and data_hash = h) then raise exception 'signer_already_signed'; end if;
  if exists (select 1 from public.entry_signatures where entry_id = p_entry and role = p_role and data_hash = h) then raise exception 'role_already_signed'; end if;
  insert into public.entry_signatures (entry_id, role, signer_id, signer_staff, data_hash) values (p_entry, p_role, auth.uid(), sid, h);
  return jsonb_build_object('entry', p_entry, 'role', p_role, 'signer_staff', sid);
end $$;

-- a draft cannot be submitted without valid (not stale) PIN signatures once they are switched on for the form
create or replace function public._entries_sig_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare roles text[]; r text; s text; h text; missing text[] := '{}';
begin
  if not (old.status = 'draft' and new.status = 'submitted') then return new; end if;
  if not public.pin_sig_active(new.form_code) then return new; end if;
  roles := case new.form_code when '14-1' then array['witness', 'second_sig'] else array['hub_pair'] end;
  h := public._sig_hash18(new.data);
  foreach r in array roles loop
    select signer_staff into s from public.entry_signatures where entry_id = new.id and role = r and data_hash = h order by id desc limit 1;
    if s is null then
      missing := missing || r;
      continue;
    end if;
    if r = 'witness' and coalesce(new.data ->> 'witness', '') <> s then raise exception 'signature_mismatch:witness'; end if;
    if r = 'second_sig' and coalesce(new.data ->> 'second_sig', '') <> s then raise exception 'signature_mismatch:second_sig'; end if;
  end loop;
  if array_length(missing, 1) > 0 then
    if new.entered_later then
      new.flags := public._addflag18(new.flags, 'unsigned_entered_later', 'yellow', 'কাগজ থেকে পরে তোলা — পিন স্বাক্ষর নেই', 'Entered later from paper - no PIN signature');
    elsif public.is_owner() and public.rule_on('pin_signature_owner_override') then
      new.flags := public._addflag18(new.flags, 'unsigned_owner_override', 'yellow', 'মালিকের ছাড়ে পিন স্বাক্ষর ছাড়া জমা', 'Submitted without PIN signatures by the owner override');
    else
      r := missing[1];
      if exists (select 1 from public.entry_signatures where entry_id = new.id and role = r) then raise exception 'pin_signature_stale:%', r; end if;
      raise exception 'pin_signature_required:%', r;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists entries_sig_guard on public.entries;
create trigger entries_sig_guard before update on public.entries for each row execute function public._entries_sig_guard();


-- submit_entry (phase17 body) with ONE change: the exceptions are made from the flags AFTER the update, so flags the server adds at submit
-- (cash_short_over from the saved blind count, unsigned_entered_later, unsigned_owner_override) become exceptions too
create or replace function public.submit_entry(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; f public.forms; fl jsonb; blocked text[] := '{}'; auto boolean;
begin
  select * into e from public.entries where id = p_id for update;
  if not found then raise exception 'entry not found'; end if;
  if e.status <> 'draft' then raise exception 'entry is locked'; end if;
  if e.created_by <> auth.uid() and not public.is_owner() then raise exception 'only the maker can submit'; end if;
  if not public.can_do(e.form_code, 'enter') or not public.can_loc(e.location_id) then raise exception 'not allowed'; end if;
  if public.rollout_mode(e.form_code, e.location_id) = 'paper' and public.rule_on('rollout_enforce') and not e.entered_later then
    raise exception 'rollout_paper:%', e.form_code;
  end if;
  select * into f from public.forms where code = e.form_code;
  if f.red_block then
    for fl in select * from jsonb_array_elements(e.flags) loop
      if fl->>'level' = 'red' and fl->>'code' <> 'entered_later_old' and not exists (select 1 from public.release_requests r
           where r.entry_id = e.id and r.flag_code = fl->>'code' and r.status = 'approved'
             and r.flag_amount is not distinct from nullif(fl->>'amount','')::numeric) then
        blocked := blocked || (fl->>'code');
      end if;
    end loop;
    if array_length(blocked, 1) > 0 then raise exception 'red_blocked:%', array_to_string(blocked, ','); end if;
  end if;
  update public.entries set status = 'submitted', submitted_at = now(), updated_at = now() where id = p_id;
  select * into e from public.entries where id = p_id;
  select coalesce((select (value #>> '{}')::boolean from public.settings where key = 'auto_exceptions'), true) into auto;
  delete from public.exceptions where entry_id = e.id and status = 'open' and flag_code <> 'count_unsubmitted';
  if auto then
    insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      select e.id, e.form_code, e.location_id, e.entry_date, x->>'code', x->>'level', nullif(x->>'amount','')::numeric, x->'text'
      from jsonb_array_elements(e.flags) x;
  end if;
  return jsonb_build_object('status', 'submitted');
end $$;
revoke all on function public.submit_entry(uuid) from public, anon;
grant execute on function public.submit_entry(uuid) to authenticated;

-- ---------- (5) rights ----------
revoke execute on function public.blind_active(text, int), public.pin_sig_active(text), public.blind_cfg_set(text, int, boolean), public.pin_sig_cfg_set(text, boolean),
  public.count_save(uuid, text, jsonb), public.count_peek(uuid, text), public.count_get(uuid, text), public.sign_entry(uuid, text), public.count_unsubmitted_scan(), public._count_hide18(public.entries), public._sig_hash18(jsonb), public._addflag18(jsonb, text, text, text, text),
  public._n18(jsonb, text), public._den_total18(jsonb, boolean), public._count_inputs18(public.entries, text), public._count_expected18(jsonb, text),
  public._count_sec18(text), public._count_can18(public.entries, text, boolean), public._entries_blind_guard(), public._entries_sig_guard(), public._append_only18() from public, anon;
grant execute on function public.blind_active(text, int), public.pin_sig_active(text), public.blind_cfg_set(text, int, boolean), public.pin_sig_cfg_set(text, boolean),
  public.count_save(uuid, text, jsonb), public.count_peek(uuid, text), public.count_get(uuid, text), public.sign_entry(uuid, text), public.count_unsubmitted_scan(), public._count_hide18(public.entries) to authenticated;   -- _count_hide18 is used by the entry_counts read policy
-- the helpers stay internal (they are called inside security definer functions); authenticated needs no direct access
revoke execute on function public._n18(jsonb, text), public._den_total18(jsonb, boolean), public._count_inputs18(public.entries, text), public._count_expected18(jsonb, text),
  public._count_sec18(text), public._count_can18(public.entries, text, boolean), public._entries_blind_guard(), public._entries_sig_guard(), public._append_only18() from authenticated;

-- ===================== phase19.sql =====================
-- Phase 19 (W6): recipes / BOM, packaging rule, production that consumes raw material.
--   Additive and idempotent (paste whole in the Supabase SQL editor; run twice is fine). Needs phase8..phase14 (stock ledger, items, item types). phase15..18 are not required.
--   * recipes (a version per finished good) + recipe_lines (ingredients: raw_material / packaging / resale items, qty, unit, waste % - empty waste = "Data needed")
--     A version that has been used by a production run is immutable (a change is a NEW version). Nothing is deleted: active flag. No cost columns anywhere.
--   * recipe_cost(recipe, loc): cost of one batch from the stock average cost - only for the owner / ITEM_COST / view_cost people.
--   * product_packaging (packaging per product, applies to sale or production) + setting packaging_consume_on (off | sale | production, default off).
--       sale       -> an AFTER INSERT trigger on sales (separate from the stock trigger, record_sale2 is NOT changed) takes the packaging out of the ledger
--                     with the SOFT mode (a sale is never blocked); if one packaging line cannot be posted the sale still goes through and the owner gets a yellow
--                     line `packaging_not_consumed`. A void gives the packaging back.
--       production -> production_post takes the packaging out in the same transaction as the ingredients.
--   * production_post(loc, recipe, batches, client, made_at, note): ONE transaction: ledger OUT per ingredient (qty x batches x (1 + waste%)) at the weighted average
--     cost, ledger IN of the finished good (yield x batches) with batch + expiry from shelf_life_for(), idempotent by client id, period lock, can_loc, grant
--     stock_production (+ its emergency rule em_stock_production), shortage refused (setting production_short_mode) with the full list of what is short.
--   * production_preview / production_can_make for the production sheet and the "what can I make now" view (no costs).
--   * settings: packaging_consume_on, production_requires_recipe (default OFF: the old stock_production_in works as before), production_short_mode,
--     recipe_waste_required (default OFF: an empty waste % is treated as 0 and the owner gets a yellow line). Grant recipe_manage (delegable).
--   The old stock_production_in is re-created with the same body plus one switch check (production_requires_recipe).

-- ---------- settings and grant ----------
insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('packaging_consume_on', 'stock', 'choice', '"off"', '["off","sale","production"]', null, null,
  'প্যাকেজিং কখন স্টক থেকে কমবে: বন্ধ / বিক্রিতে / উৎপাদনে', 'Packaging কখন stock থেকে কমবে: off / sale / production', 'When packaging leaves the stock: off, with a sale, or with production',
  'Off = packaging is not taken out automatically. Uses the per-product packaging list. A sale is never blocked by packaging.', 190),
 ('production_requires_recipe', 'stock', 'switch', 'false', null, null, null,
  'উৎপাদন শুধু রেসিপি দিয়েই (পুরনো সরাসরি "উৎপাদিত মাল তোলা" বন্ধ)', 'Production শুধু recipe দিয়েই (পুরনো সরাসরি "Production in" বন্ধ)', 'Production only through a recipe (the old direct "Production in" is refused)',
  'Off = the direct production-in works as before. On = every production must use a recipe so the raw material is taken out.', 191),
 ('production_short_mode', 'stock', 'choice', '"refuse"', '["refuse","follow_stock_rule"]', null, null,
  'কাঁচামাল কম থাকলে: আটকানো / স্টকের সাধারণ নিয়ম', 'Raw material কম থাকলে: refuse / stock এর সাধারণ rule', 'When raw material is short: refuse, or follow the general stock rule',
  'refuse = the production is refused (unless stock_negative_mode is allow, or the person may sell below zero). follow_stock_rule = same as selling (warn / block / allow).', 192),
 ('recipe_waste_required', 'stock', 'switch', 'false', null, null, null,
  'রেসিপিতে অপচয় % না থাকলে উৎপাদন আটকানো', 'Recipe এ waste % না থাকলে production আটকানো', 'Refuse production when a recipe line has no waste %',
  'Off = an empty waste % counts as 0 and the owner gets a yellow line. The owner sets the real waste %; nothing is guessed.', 193)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('recipe_manage', 'master', 69, 'রেসিপি ও প্যাকেজিং নিয়ম তৈরি / বদল', 'Recipe ও packaging rule তৈরি / বদল', 'Create and change recipes and packaging rules', 'window', null)
on conflict (grant_code) do nothing;

-- ---------- tables ----------
create table if not exists public.recipes (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id),
  version int not null check (version >= 1),
  yield_qty numeric not null check (yield_qty > 0 and yield_qty < 1000000000),
  yield_unit text,                                           -- null = the item base unit
  active boolean not null default true,
  note text,
  used_at timestamptz,                                       -- first production run: from then on the version is frozen
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(),
  unique (item_id, version)
);
create index if not exists recipes_item on public.recipes (item_id, active);
create table if not exists public.recipe_lines (
  id bigserial primary key,
  recipe_id uuid not null references public.recipes(id),
  ingredient_item_id uuid not null references public.items(id),
  qty numeric not null check (qty > 0 and qty < 1000000000),
  unit text,                                                 -- null = the ingredient base unit
  waste_pct numeric check (waste_pct is null or (waste_pct >= 0 and waste_pct <= 100)),     -- null = Data needed
  note text,
  sort int not null default 0,
  unique (recipe_id, ingredient_item_id)
);
alter table public.recipe_lines add column if not exists active boolean not null default true;
alter table public.recipe_lines drop constraint if exists recipe_lines_recipe_id_ingredient_item_id_key;
create unique index if not exists recipe_lines_one_active on public.recipe_lines (recipe_id, ingredient_item_id) where active;
create table if not exists public.product_packaging (
  id bigserial primary key,
  product_item_id uuid not null references public.items(id),
  packaging_item_id uuid not null references public.items(id),
  qty_per_unit numeric not null check (qty_per_unit > 0 and qty_per_unit < 1000000),     -- packaging base units per ONE base unit of the product
  applies_to text not null default 'sale' check (applies_to in ('sale', 'production')),
  active boolean not null default true,
  note text,
  updated_by uuid, updated_at timestamptz not null default now(),
  unique (product_item_id, packaging_item_id, applies_to)
);
create table if not exists public.production_runs (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  location_id int not null references public.locations(id),
  recipe_id uuid not null references public.recipes(id),
  item_id uuid not null references public.items(id),
  batches numeric not null check (batches > 0),
  made_at timestamptz not null,
  yield_base numeric not null,
  ledger_in_id bigint, batch_id bigint,
  waste_missing int not null default 0,
  cost_complete boolean,
  note text,
  created_by uuid, created_at timestamptz not null default now()
);
create index if not exists production_runs_loc on public.production_runs (location_id, made_at);

-- ---------- helpers ----------
create or replace function public._recipe_mgr() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('recipe_manage'));
$$;
create or replace function public._recipe_read() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('recipe_manage') or public.has_grant('stock_production') or public.has_grant('stock_issue')
    or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code in ('recipe_manage', 'stock_production', 'stock_issue') and (g.valid_until is null or g.valid_until > now())));
$$;
create or replace function public._recipe_cost_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.can_do('ITEM_COST', 'view') or public.has_grant('view_cost')
    or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'view_cost' and (g.valid_until is null or g.valid_until > now())));
$$;

-- immutability: lines and the yield of a used version never change; a used version is never removed
create or replace function public._recipe_frozen() returns trigger language plpgsql security definer set search_path = public as $$
declare rid uuid; used timestamptz;
begin
  if tg_table_name = 'recipes' then
    if tg_op = 'DELETE' then
      if old.used_at is not null then raise exception 'recipe_used'; end if;
      raise exception 'no_delete';
    end if;
    if tg_op = 'UPDATE' and old.used_at is not null and (new.item_id is distinct from old.item_id or new.version is distinct from old.version
        or new.yield_qty is distinct from old.yield_qty or new.yield_unit is distinct from old.yield_unit) then raise exception 'recipe_used'; end if;
    return new;
  end if;
  rid := case when tg_op = 'DELETE' then old.recipe_id else new.recipe_id end;
  select used_at into used from public.recipes where id = rid;
  if used is not null then raise exception 'recipe_used'; end if;
  if tg_op = 'DELETE' then raise exception 'no_delete'; end if;
  if tg_op = 'UPDATE' and new.recipe_id is distinct from old.recipe_id then raise exception 'recipe_used'; end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
drop trigger if exists recipes_frozen on public.recipes;
create trigger recipes_frozen before update or delete on public.recipes for each row execute function public._recipe_frozen();
drop trigger if exists recipe_lines_frozen on public.recipe_lines;
create trigger recipe_lines_frozen before insert or update or delete on public.recipe_lines for each row execute function public._recipe_frozen();

drop trigger if exists audit_recipes on public.recipes;
create trigger audit_recipes after insert or update on public.recipes for each row execute function public.log_change('id');
drop trigger if exists audit_recipe_lines on public.recipe_lines;
create trigger audit_recipe_lines after insert or update or delete on public.recipe_lines for each row execute function public.log_change('id');
drop trigger if exists audit_product_packaging on public.product_packaging;
create trigger audit_product_packaging after insert or update on public.product_packaging for each row execute function public.log_change('id');
drop trigger if exists audit_production_runs on public.production_runs;
create trigger audit_production_runs after insert on public.production_runs for each row execute function public.log_change('id');

-- ---------- RLS ----------
alter table public.recipes enable row level security;
alter table public.recipe_lines enable row level security;
alter table public.product_packaging enable row level security;
alter table public.production_runs enable row level security;
drop policy if exists recipes_read on public.recipes;
create policy recipes_read on public.recipes for select to authenticated using (public._recipe_read());
drop policy if exists recipe_lines_read on public.recipe_lines;
create policy recipe_lines_read on public.recipe_lines for select to authenticated using (public._recipe_read());
drop policy if exists product_packaging_read on public.product_packaging;
create policy product_packaging_read on public.product_packaging for select to authenticated using (public._recipe_read());
drop policy if exists production_runs_read on public.production_runs;
create policy production_runs_read on public.production_runs for select to authenticated using (public._recipe_read() and public.can_loc(location_id));
revoke all on public.recipes, public.recipe_lines, public.product_packaging, public.production_runs from anon, authenticated;
grant select on public.recipes, public.recipe_lines, public.product_packaging, public.production_runs to authenticated;
revoke all on sequence public.recipe_lines_id_seq, public.product_packaging_id_seq from anon, authenticated;

-- ---------- recipe writes ----------
create or replace function public._recipe_lines_ok(p_item uuid, p_lines jsonb) returns void language plpgsql security definer set search_path = public as $$
declare ln jsonb; ing public.items; q numeric; w numeric; seen uuid[] := '{}'; iid uuid;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  if jsonb_array_length(p_lines) > 100 then raise exception 'too_many_lines'; end if;
  for ln in select x from jsonb_array_elements(p_lines) x loop
    iid := nullif(ln->>'ingredient_item_id', '')::uuid;
    select * into ing from public.items where id = iid;
    if not found then raise exception 'item_not_found'; end if;
    if iid = p_item then raise exception 'ingredient_is_product'; end if;
    if ing.item_type not in ('raw_material', 'packaging', 'resale') then raise exception 'bad_ingredient_type' using detail = ing.code; end if;
    if iid = any(seen) then raise exception 'dup_ingredient'; end if;
    seen := seen || iid;
    q := nullif(ln->>'qty', '')::numeric;
    if q is null or not (q > 0 and q < 1000000000) then raise exception 'bad_qty'; end if;
    w := nullif(ln->>'waste_pct', '')::numeric;
    if w is not null and not (w between 0 and 100) then raise exception 'bad_waste'; end if;
    if public._base_qty(iid, q, nullif(btrim(ln->>'unit'), '')) is null then raise exception 'unit_unknown' using detail = ing.code; end if;
  end loop;
end $$;

create or replace function public._recipe_put_lines(p_recipe uuid, p_lines jsonb) returns void language plpgsql security definer set search_path = public as $$
declare ln jsonb; n int := 0;
begin
  for ln in select x from jsonb_array_elements(p_lines) x loop
    n := n + 1;
    insert into public.recipe_lines (recipe_id, ingredient_item_id, qty, unit, waste_pct, note, sort)
      values (p_recipe, (ln->>'ingredient_item_id')::uuid, (ln->>'qty')::numeric, nullif(btrim(ln->>'unit'), ''), nullif(ln->>'waste_pct', '')::numeric, left(nullif(btrim(ln->>'note'), ''), 200), n);
  end loop;
end $$;

-- create a new version (p_id null) or edit a version that has never been used. p_lines = [{ingredient_item_id, qty, unit, waste_pct, note}]
create or replace function public.recipe_save(p_id uuid, p_item uuid, p_yield_qty numeric, p_yield_unit text, p_note text, p_lines jsonb, p_client uuid default null, p_retire_old boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; r public.recipes; v int; rid uuid; yu text := nullif(btrim(p_yield_unit), '');
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_yield_qty is null or not (p_yield_qty > 0 and p_yield_qty < 1000000000) then raise exception 'bad_qty'; end if;
  if p_id is not null then
    select * into r from public.recipes where id = p_id for update;
    if not found then raise exception 'recipe_not_found'; end if;
    if r.used_at is not null then raise exception 'recipe_used'; end if;
    it := (select i from public.items i where i.id = r.item_id);
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
    insert into public.recipes (item_id, version, yield_qty, yield_unit, active, note, client_id, created_by)
      values (it.id, v, p_yield_qty, yu, true, left(p_note, 300), p_client, auth.uid()) returning id into rid;
    if p_retire_old then update public.recipes set active = false where item_id = it.id and id <> rid and active; end if;
  else
    rid := p_id; v := r.version;
    update public.recipes set yield_qty = p_yield_qty, yield_unit = yu, note = left(p_note, 300) where id = rid;
    update public.recipe_lines set active = false where recipe_id = rid and active;      -- a draft only (never used): old lines are retired, never deleted; the trigger refuses this for a used version
  end if;
  perform public._recipe_put_lines(rid, p_lines);
  return jsonb_build_object('id', rid, 'version', v);
end $$;

-- copy a version: same item = next version (optionally retiring the source); another item = version 1 of that item
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
  insert into public.recipes (item_id, version, yield_qty, yield_unit, active, note, client_id, created_by)
    values (tgt.id, v, s.yield_qty, case when tgt.id = s.item_id then s.yield_unit else null end, true, s.note, p_client, auth.uid()) returning id into rid;
  insert into public.recipe_lines (recipe_id, ingredient_item_id, qty, unit, waste_pct, note, sort)
    select rid, ingredient_item_id, qty, unit, waste_pct, note, sort from public.recipe_lines where recipe_id = p_from and active;
  if tgt.id <> s.item_id and public._base_qty(tgt.id, s.yield_qty, null) is null then raise exception 'unit_unknown'; end if;
  if p_retire_old and tgt.id = s.item_id then update public.recipes set active = false where id = p_from; end if;
  return jsonb_build_object('id', rid, 'version', v);
end $$;

create or replace function public.recipe_set_active(p_id uuid, p_active boolean) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  if p_active is null then raise exception 'bad_value'; end if;
  update public.recipes set active = p_active where id = p_id;
  if not found then raise exception 'recipe_not_found'; end if;
end $$;

-- packaging per product (one row per product x packaging x sale|production); inactive instead of delete
create or replace function public.packaging_set(p_product uuid, p_packaging uuid, p_qty numeric, p_applies text default 'sale', p_active boolean default true, p_note text default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare pr public.items; pk public.items; rid bigint;
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  if p_applies not in ('sale', 'production') then raise exception 'bad_value'; end if;
  if p_qty is null or not (p_qty > 0 and p_qty < 1000000) then raise exception 'bad_qty'; end if;
  select * into pr from public.items where id = p_product;
  select * into pk from public.items where id = p_packaging;
  if pr.id is null or pk.id is null then raise exception 'item_not_found'; end if;
  if pk.item_type is distinct from 'packaging' then raise exception 'bad_ingredient_type' using detail = pk.code; end if;
  if pr.item_type not in ('finished_good', 'resale') then raise exception 'bad_product_type'; end if;
  insert into public.product_packaging (product_item_id, packaging_item_id, qty_per_unit, applies_to, active, note, updated_by, updated_at)
    values (p_product, p_packaging, p_qty, p_applies, coalesce(p_active, true), left(p_note, 200), auth.uid(), now())
    on conflict (product_item_id, packaging_item_id, applies_to) do update
      set qty_per_unit = excluded.qty_per_unit, active = excluded.active, note = excluded.note, updated_by = auth.uid(), updated_at = now()
    returning id into rid;
  return rid;
end $$;

-- ---------- the consumption maths (internal; used by preview, can-make and post) ----------
-- one row per thing that leaves the stock for p_batches batches: the ingredients, plus the production-time packaging when the setting says so
create or replace function public._recipe_need(p_recipe uuid, p_batches numeric, p_loc int)
returns table (item_id uuid, kind text, need numeric, on_hand numeric, tracked boolean, unit_ok boolean, waste_missing boolean, code text, name_bn text, name_en text, base_unit text)
language plpgsql stable security definer set search_path = public as $$
declare r public.recipes; yb numeric;
begin
  select * into r from public.recipes where id = p_recipe;
  if not found then return; end if;
  yb := coalesce(public._base_qty(r.item_id, r.yield_qty, r.yield_unit), 0) * p_batches;
  return query
    select z.item_id, min(z.kind), sum(z.need), max(z.on_hand), bool_and(z.tracked), bool_and(z.unit_ok), bool_or(z.waste_missing), z.code, z.name_bn, z.name_en, z.base_unit
    from (
      select i.id as item_id, 'ingredient'::text as kind,
             round(public._base_qty(i.id, l.qty, l.unit) * p_batches * (1 + coalesce(l.waste_pct, 0) / 100), 4) as need,
             coalesce(b.qty, 0) as on_hand, i.tracked, public._base_qty(i.id, l.qty, l.unit) is not null as unit_ok, l.waste_pct is null as waste_missing,
             i.code, i.name_bn, i.name_en, public._item_base(i.id) as base_unit
        from public.recipe_lines l join public.items i on i.id = l.ingredient_item_id
        left join public.stock_balance b on b.item_id = i.id and b.location_id = p_loc
       where l.recipe_id = p_recipe and l.active
      union all
      select i.id, 'packaging'::text, round(pp.qty_per_unit * yb, 4), coalesce(b.qty, 0), i.tracked, true, false, i.code, i.name_bn, i.name_en, public._item_base(i.id)
        from public.product_packaging pp join public.items i on i.id = pp.packaging_item_id
        left join public.stock_balance b on b.item_id = i.id and b.location_id = p_loc
       where coalesce(public.rule_txt('packaging_consume_on'), 'off') = 'production' and pp.product_item_id = r.item_id and pp.active and pp.applies_to = 'production') z
    group by z.item_id, z.code, z.name_bn, z.name_en, z.base_unit;
end $$;

-- preview for the production sheet: what will be used, what is on hand, what is short. No costs.
create or replace function public.production_preview(p_loc int, p_recipe uuid, p_batches numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; it public.items; yb numeric; ls jsonb; sh jsonb; wm int;
begin
  if not public._recipe_read() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if p_batches is null or not (p_batches between 0.0001 and 100000) then raise exception 'bad_qty'; end if;
  select * into r from public.recipes where id = p_recipe;
  if not found then raise exception 'recipe_not_found'; end if;
  select * into it from public.items where id = r.item_id;
  yb := round(public._base_qty(r.item_id, r.yield_qty, r.yield_unit) * p_batches, 4);
  select coalesce(jsonb_agg(jsonb_build_object('item_id', n.item_id, 'kind', n.kind, 'code', n.code, 'name_bn', n.name_bn, 'name_en', n.name_en, 'need', n.need, 'on_hand', n.on_hand,
           'short', greatest(n.need - n.on_hand, 0), 'unit', n.base_unit, 'tracked', n.tracked, 'unit_ok', n.unit_ok, 'waste_missing', n.waste_missing) order by n.kind, n.code), '[]'::jsonb),
         coalesce(jsonb_agg(n.item_id) filter (where n.need > n.on_hand), '[]'::jsonb), count(*) filter (where n.waste_missing)
    into ls, sh, wm from public._recipe_need(p_recipe, p_batches, p_loc) n;
  return jsonb_build_object('recipe_id', r.id, 'item_id', r.item_id, 'version', r.version, 'active', r.active, 'batches', p_batches, 'yield_base', yb, 'yield_unit', public._item_base(r.item_id),
    'lines', ls, 'short_items', sh, 'waste_missing', wm,
    'can_make', (jsonb_array_length(sh) = 0 and not exists (select 1 from jsonb_array_elements(ls) x where (x->>'tracked')::boolean is not true or (x->>'unit_ok')::boolean is not true)),
    'tracked', it.tracked);
end $$;

-- "what can I make now" at one location: for every active recipe (newest active version per product) how many batches the stock allows
create or replace function public.production_can_make(p_loc int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; out jsonb := '[]'::jsonb; mx numeric; lim uuid; unk boolean; n record; per numeric; it public.items;
begin
  if not public._recipe_read() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  for r in select distinct on (item_id) * from public.recipes where active order by item_id, version desc loop
    select * into it from public.items where id = r.item_id;
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
end $$;

-- cost of one batch from the average cost in stock (owner / ITEM_COST / view_cost only; unknown cost = null = Data needed)
create or replace function public.recipe_cost(p_recipe uuid, p_loc int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; ls jsonb := '[]'::jsonb; total numeric := 0; complete boolean := true; l record; need numeric; av numeric; yb numeric;
begin
  if p_loc is not null then
    if not (public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;      -- same rule as the stock cost columns
  elsif not public._recipe_cost_ok() then raise exception 'not allowed'; end if;
  select * into r from public.recipes where id = p_recipe;
  if not found then raise exception 'recipe_not_found'; end if;
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
    'unit_cost', case when complete and yb > 0 then round(total / yb, 6) end, 'yield_base', yb);
end $$;

-- ---------- production ----------
create or replace function public.production_post(p_loc int, p_recipe uuid, p_batches numeric, p_client uuid default null, p_made_at timestamptz default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; it public.items; at_ timestamptz := coalesce(p_made_at, now()); run public.production_runs; n record; rid uuid := gen_random_uuid();
        mode text; neg text; yb numeric; f numeric; sl jsonb; exp timestamptz; bid bigint; lin bigint; lid bigint; tot numeric := 0; cost_ok boolean := true; av numeric; wm int := 0;
        shorts text := ''; used jsonb := '[]'::jsonb; ucb numeric; derived uuid;
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
  return jsonb_build_object('run_id', rid, 'ledger_id', lid, 'batch_id', bid, 'qty', yb, 'expires_at', exp, 'consumed', used, 'waste_missing', wm) || case when public._cost_ok(p_loc) then jsonb_build_object('cost_complete', cost_ok) else '{}'::jsonb end;
end $$;

-- the old direct "production in": identical to phase10 except the new switch (production_requires_recipe)
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
  sl := public.shelf_life_for(p_item, (at_ at time zone 'Asia/Dhaka')::date);
  exp := case when sl is null then null else at_ + ((sl->>'hours')::float8 * interval '1 hour') end;
  insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
    values (p_item, p_loc, at_, bq, bq, exp, sl, left(p_note, 200), auth.uid()) returning id into bid;
  lid := public.stock_post(p_item, p_loc, bq, 'production_in', 'production', bid::text, case when p_unit_cost is null then null else p_unit_cost / f end, bid, at_, left(p_note, 200), null, 'none', null, p_client);
  return jsonb_build_object('ledger_id', lid, 'batch_id', bid, 'qty', bq, 'expires_at', exp);
end $$;

-- ---------- packaging with a sale (separate trigger; the stock trigger and record_sale2 are untouched) ----------
create or replace function public._sale_packaging_out() returns trigger language plpgsql security definer set search_path = public as $$
declare pk record; bad boolean := false;
begin
  if new.status <> 'done' or new.lines is null or jsonb_typeof(new.lines) <> 'array' then return new; end if;
  if coalesce(public.rule_txt('packaging_consume_on'), 'off') <> 'sale' then return new; end if;
  begin
    for pk in
      select pp.packaging_item_id as item_id, sum(public._base_qty(li.iid, li.q, li.u) * pp.qty_per_unit) as qty, count(*) filter (where public._base_qty(li.iid, li.q, li.u) is null) as unk,
             i.code, i.name_bn, i.name_en
        from (select (x->>'item_id')::uuid as iid, nullif(x->>'qty', '')::numeric as q, x->>'unit' as u from jsonb_array_elements(new.lines) x where nullif(x->>'item_id', '') is not null) li
        join public.product_packaging pp on pp.product_item_id = li.iid and pp.active and pp.applies_to = 'sale'
        join public.items i on i.id = pp.packaging_item_id
       where li.q > 0 and li.q <= 999999999
       group by pp.packaging_item_id, i.code, i.name_bn, i.name_en order by pp.packaging_item_id loop
      if pk.unk > 0 then bad := true; end if;
      begin
        if pk.qty is null or round(pk.qty, 4) < 0.0001 then continue; end if;
        perform public.stock_post(pk.item_id, new.location_id, -round(pk.qty, 4), 'issue_out', 'sale_pack', new.id::text, null, null, new.sold_at, null, null, 'soft', new.id);
      exception when others then
        bad := true;
        perform public._stock_exc(new.location_id, 'packaging_not_consumed', 'yellow', 'রসিদ ' || new.receipt || ': ' || coalesce(pk.name_bn, '') || ' — প্যাকেজিং স্টক থেকে কমানো যায়নি',
          'Receipt ' || new.receipt || ': ' || coalesce(pk.name_en, pk.name_bn, '') || ' — the packaging could not be taken out of the stock', new.id, new.sale_date, 'POS');
      end;
    end loop;
  exception when others then
    bad := true;
  end;
  if bad then
    perform public._stock_exc(new.location_id, 'packaging_not_consumed', 'yellow', 'রসিদ ' || new.receipt || ': প্যাকেজিং পুরোটা কমানো যায়নি', 'Receipt ' || new.receipt || ': the packaging could not be fully taken out of the stock', new.id, new.sale_date, 'POS');
  end if;
  return new;
end $$;
drop trigger if exists sales_packaging_out on public.sales;
create trigger sales_packaging_out after insert on public.sales for each row execute function public._sale_packaging_out();

create or replace function public._sale_packaging_void() returns trigger language plpgsql security definer set search_path = public as $$
declare r public.stock_ledger;
begin
  for r in select * from public.stock_ledger o where o.ref_type = 'sale_pack' and o.ref_id = new.id::text and o.reason = 'issue_out'
           and not exists (select 1 from public.stock_ledger v where v.reverses_id = o.id) order by o.item_id, o.id loop
    perform public.stock_post(r.item_id, r.location_id, -r.qty_delta, 'sale_void_in', 'sale_pack', new.id::text, r.unit_cost, r.batch_id, now(), null, r.id, 'none', new.id);
  end loop;
  return new;
end $$;
drop trigger if exists sales_packaging_void on public.sales;
create trigger sales_packaging_void after update of status on public.sales for each row
  when (old.status is distinct from 'void' and new.status = 'void') execute function public._sale_packaging_void();

-- ---------- privileges ----------
revoke all on function public._recipe_mgr(), public._recipe_read(), public._recipe_cost_ok(), public._recipe_frozen(), public._recipe_lines_ok(uuid, jsonb), public._recipe_put_lines(uuid, jsonb),
  public._recipe_need(uuid, numeric, int), public._sale_packaging_out(), public._sale_packaging_void() from public, anon, authenticated;
revoke all on function public.recipe_save(uuid, uuid, numeric, text, text, jsonb, uuid, boolean), public.recipe_copy(uuid, uuid, boolean, uuid), public.recipe_set_active(uuid, boolean),
  public.packaging_set(uuid, uuid, numeric, text, boolean, text), public.production_preview(int, uuid, numeric), public.production_can_make(int), public.recipe_cost(uuid, int),
  public.production_post(int, uuid, numeric, uuid, timestamptz, text) from public, anon;
grant execute on function public.recipe_save(uuid, uuid, numeric, text, text, jsonb, uuid, boolean), public.recipe_copy(uuid, uuid, boolean, uuid), public.recipe_set_active(uuid, boolean),
  public.packaging_set(uuid, uuid, numeric, text, boolean, text), public.production_preview(int, uuid, numeric), public.production_can_make(int), public.recipe_cost(uuid, int),
  public.production_post(int, uuid, numeric, uuid, timestamptz, text) to authenticated;
revoke all on function public.stock_production_in(uuid, int, numeric, timestamptz, text, text, uuid, numeric) from public, anon;
grant execute on function public.stock_production_in(uuid, int, numeric, timestamptz, text, text, uuid, numeric) to authenticated;
-- the read policies call this helper as the signed-in person
grant execute on function public._recipe_read() to authenticated;
-- cost_complete is a cost fact: not readable by people who may not see costs
revoke select on public.production_runs from authenticated;
grant select (id, client_id, location_id, recipe_id, item_id, batches, made_at, yield_base, ledger_in_id, batch_id, waste_missing, note, created_by, created_at) on public.production_runs to authenticated;

-- ===================== phase20.sql =====================
-- ============================================================
-- Phase 20: FORMS <-> STOCK LEDGER LINKS, discount approver on sales, brand-level P&L.
--   Additive and safe to run twice; paste the whole file into the Supabase SQL editor.  Needs phase8..phase17 (phase18 / 19 are not required).
--   (1) rule forms_post_to_ledger (default OFF) + per-form switches forms_ledger_cfg(form_code, is_on).
--       When an entry of 04-1 GRN / 04-2 issue / 04-3 count / 03-1 transfer / 05-1 factory sheet is APPROVED, an AFTER UPDATE trigger on entries
--       calls entry_post_ledger(entry), which posts into the existing stock ledger through stock_post.  decide_entry is NOT edited.
--       - one log row per form line in entry_ledger_posts (entry, generation, line): the same approval twice posts nothing twice;
--       - reopen + re-approve (or an approved change request) with different content: reverse the earlier generation (reversal rows) and post the new one;
--       - lines whose item is not tracked / not counted in the business, held / returned GRN lines, lines without a quantity: skipped, yellow exception ledger_skip;
--       - any failure (unknown item, not enough stock, unknown unit ...): yellow exception ledger_post_failed with the reason, approval is never blocked;
--         entry_post_ledger_retry(entry) posts the failed lines again (and also posts an entry approved while the switch was off).
--   (2) the 04-4 store ledger and 06-5 supplier ledger need no new data: they become read views over stock_ledger_rows / supplier_ledger (web).
--   (3) sales.discount_approved_by / _staff / discount_approval: filled by a BEFORE INSERT trigger from the approval that record_sale2 used
--       (a granted role = the seller, an emergency approval = the person who approved the request).  record_sale2 is NOT edited.  RPC discounts_report.
--   (4) brand_pnl(from, to): the existing gross-profit figures (biz_daily) grouped by brand through report_brand_map. Costs only for cost-grant holders.
-- ============================================================

-- ---------- (1) switches ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('forms_post_to_ledger', 'stock', 'switch', 'false', null, null, null, null,
  'ফর্ম অনুমোদন হলে স্টক লেজারে নিজে থেকে পোস্ট', 'Form approve হলে stock ledger এ নিজে পোস্ট', 'Approved forms post to the stock ledger',
  'চালু করলে GRN, ইস্যু স্লিপ, কাউন্ট শিট, ট্রান্সফার চালান ও কারখানা শিট অনুমোদনের সময় স্টক লেজারে লাইন যোগ করে। বন্ধ থাকলে কিছুই বদলায় না।',
  null,
  'When on, an approved GRN, issue slip, count sheet, transfer challan or factory sheet adds its lines to the stock ledger. Off = nothing changes (default). Each form also has its own switch.', 71)
on conflict (key) do nothing;

create table if not exists public.forms_ledger_cfg (
  form_code text primary key references public.forms(code),
  is_on boolean not null default true,                     -- the master rule forms_post_to_ledger must be on as well
  changed_by uuid, changed_at timestamptz not null default now()
);
alter table public.forms_ledger_cfg enable row level security;
revoke all on public.forms_ledger_cfg from public, anon, authenticated;
grant select on public.forms_ledger_cfg to authenticated;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'forms_ledger_cfg' and policyname = 'forms_ledger_cfg_read') then
    create policy forms_ledger_cfg_read on public.forms_ledger_cfg for select to authenticated using (public.is_active());
  end if;
end $$;
insert into public.forms_ledger_cfg (form_code) select code from public.forms where code in ('04-1', '04-2', '04-3', '03-1', '05-1') on conflict do nothing;

create table if not exists public.entry_ledger_posts (
  id bigserial primary key,
  entry_id uuid not null references public.entries(id),
  gen int not null check (gen >= 1),                        -- a new generation when the approved content changed (the old one is reversed)
  line_no int not null,                                     -- 1-based line of the form table; 0 = the form as a whole
  form_code text not null,
  location_id int not null references public.locations(id), -- the entry's place
  to_location_id int references public.locations(id),
  kind text not null check (kind in ('in', 'out', 'count', 'transfer', 'prod', 'none')),
  item_id uuid references public.items(id),
  item_code text,
  qty_base numeric,                                         -- base unit; for a count the counted quantity
  sig text not null,                                        -- fingerprint of all lines of this generation
  status text not null check (status in ('posted', 'skipped', 'failed', 'reversed', 'void')),
  reason text,                                              -- why skipped / failed / the short note of a post
  ref text,                                                 -- entry:gen:line, written to stock_ledger.ref_id (ref_type 'entry')
  transfer_id uuid,
  posted_by uuid, posted_at timestamptz not null default now(), reversed_at timestamptz,
  unique (entry_id, gen, line_no)
);
create index if not exists entry_ledger_posts_entry on public.entry_ledger_posts (entry_id, gen);
create index if not exists entry_ledger_posts_bad on public.entry_ledger_posts (status) where status in ('failed', 'skipped');
alter table public.entry_ledger_posts enable row level security;
revoke all on public.entry_ledger_posts from public, anon, authenticated;
grant select on public.entry_ledger_posts to authenticated;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'entry_ledger_posts' and policyname = 'entry_ledger_posts_read') then
    create policy entry_ledger_posts_read on public.entry_ledger_posts for select to authenticated using (public.is_active() and (public.is_owner() or public.can_loc(location_id)));
  end if;
end $$;

-- ---------- small helpers ----------
create or replace function public._elp_num(p text) returns numeric
language sql immutable as $$ select case when btrim(p) ~ '^-?[0-9]+(\.[0-9]+)?$' then btrim(p)::numeric end $$;
create or replace function public._elp_flag(p text) returns boolean
language sql immutable as $$ select coalesce(lower(btrim(p)) in ('true', 't', '1', 'yes', 'on'), false) $$;
create or replace function public._elp_loc(p text) returns int
language sql stable security definer set search_path = public as $$
  select l.id from public.locations l where btrim(p) ~ '^[0-9]{1,9}$' and l.id = btrim(p)::int;
$$;
create or replace function public._elp_enabled(p_form text) returns boolean
language sql stable security definer set search_path = public as $$
  select p_form in ('04-1', '04-2', '04-3', '03-1', '05-1') and public.rule_on('forms_post_to_ledger')
         and coalesce((select c.is_on from public.forms_ledger_cfg c where c.form_code = p_form), true);
$$;

-- ---------- the form -> ledger lines map (what each form means for the ledger; nothing is guessed) ----------
-- one jsonb object per non-empty row: {n, kind, item, qty, cost, from, to, recv, skip, note}.  qty / cost are in the item's own unit as written on the form.
create or replace function public._elp_lines(e public.entries) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out jsonb := '[]'::jsonb; r jsonb; n int; tab text; arr jsonb; q text; cr jsonb; kept boolean; note text; nrate numeric;
begin
  note := left(e.form_code || '-' || e.serial::text || coalesce(' ' || nullif(btrim(e.data->>'supplier'), ''), ''), 120);
  if e.form_code = '04-1' then
    nrate := public._elp_num(e.data->>'new_rate');
    for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) with ordinality x(v, o) loop
      continue when coalesce(nullif(btrim(r->>'item'), ''), nullif(btrim(r->>'counted'), '')) is null;
      q := coalesce(r->>'quality', 'accept');
      out := out || jsonb_build_object('n', n, 'kind', 'in', 'item', nullif(btrim(r->>'item'), ''), 'qty', public._elp_num(r->>'counted'),
        'cost', case when q = 'reduced' and nrate is not null then nrate else public._elp_num(r->>'rate') end,
        'skip', case when q = 'hold' then 'quality_hold' when q = 'return' then 'quality_return' end, 'note', note);
    end loop;
  elsif e.form_code = '04-2' then
    kept := not public._elp_flag(e.data->>'not_overnight');       -- the form's own rule: kept overnight = the whole quantity counts as used
    for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) with ordinality x(v, o) loop
      continue when coalesce(nullif(btrim(r->>'item'), ''), nullif(btrim(r->>'issued'), '')) is null;
      out := out || jsonb_build_object('n', n, 'kind', 'out', 'item', nullif(btrim(r->>'item'), ''),
        'qty', public._elp_num(r->>'issued') - case when kept then 0 else coalesce(public._elp_num(r->>'ret'), 0) end, 'note', note || ' ' || coalesce(e.data->>'purpose', ''));
    end loop;
  elsif e.form_code = '04-3' then
    for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(e.data->'rows') = 'array' then e.data->'rows' else '[]'::jsonb end) with ordinality x(v, o) loop
      continue when coalesce(nullif(btrim(r->>'item'), ''), nullif(btrim(r->>'count'), '')) is null;
      out := out || jsonb_build_object('n', n, 'kind', 'count', 'item', nullif(btrim(r->>'item'), ''), 'qty', public._elp_num(r->>'count'), 'book', public._elp_num(r->>'book'),
        'skip', case when public._elp_num(r->>'book') is null then 'no_count_basis' end,
        'note', left(note || ' ' || coalesce(nullif(btrim(r->>'reason'), ''), 'stock count'), 190));
    end loop;
  elsif e.form_code = '03-1' then
    cr := case when jsonb_typeof(e.check_data->'items') = 'array' then e.check_data->'items' else '[]'::jsonb end;
    for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(e.data->'items') = 'array' then e.data->'items' else '[]'::jsonb end) with ordinality x(v, o) loop
      continue when coalesce(nullif(btrim(r->>'item'), ''), nullif(btrim(r->>'sent'), '')) is null;
      out := out || jsonb_build_object('n', n, 'kind', 'transfer', 'item', nullif(btrim(r->>'item'), ''), 'qty', public._elp_num(r->>'sent'),
        'from', public._elp_loc(e.data->>'from_loc'), 'to', public._elp_loc(e.data->>'to_loc'),
        'recv', public._elp_num(cr->(n - 1)->>'received'), 'note', note);
    end loop;
  elsif e.form_code = '05-1' then
    for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(e.data->'output') = 'array' then e.data->'output' else '[]'::jsonb end) with ordinality x(v, o) loop
      continue when coalesce(nullif(btrim(r->>'item'), ''), nullif(btrim(r->>'qty'), '')) is null;
      out := out || jsonb_build_object('n', n, 'kind', 'prod', 'item', nullif(btrim(r->>'item'), ''), 'qty', public._elp_num(r->>'qty'), 'note', note);
    end loop;
  end if;
  if jsonb_array_length(out) = 0 then
    out := jsonb_build_array(jsonb_build_object('n', 0, 'kind', 'none', 'skip', 'no_item_lines', 'note', note));
  end if;
  return out;
end $$;

-- ---------- post ONE line (runs inside a sub-transaction of entry_post_ledger: an error here undoes only this line) ----------
create or replace function public._elp_post_line(e public.entries, g int, sg text, l jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare it public.items; n int := (l->>'n')::int; kind text := l->>'kind'; qty numeric := nullif(l->>'qty', '')::numeric; bq numeric; f numeric; ucb numeric;
        ref text := e.id::text || ':g' || g::text || ':' || n::text; lid bigint; olid bigint; bal public.stock_balance; d numeric; tid uuid; fl int := nullif(l->>'from', '')::int;
        tl int := nullif(l->>'to', '')::int; rq numeric; rbq numeric; note text := nullif(l->>'note', ''); at_ timestamptz := now(); sl jsonb; exp timestamptz; bid bigint; sid text;
        stt text := 'posted'; why text; ucost numeric;
begin
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
end $$;

-- ---------- undo one generation (reversal rows; nothing is deleted) ----------
create or replace function public._elp_reverse(e public.entries, g int) returns void
language plpgsql security definer set search_path = public as $$
declare p public.entry_ledger_posts; o public.stock_ledger;
begin
  for p in select * from public.entry_ledger_posts where entry_id = e.id and gen = g and status = 'posted' order by line_no desc loop
    for o in select x.* from public.stock_ledger x where x.reason <> 'reversal'
             and ((p.transfer_id is not null and x.ref_type = 'transfer' and x.ref_id = p.transfer_id::text) or (p.transfer_id is null and x.ref_type = 'entry' and x.ref_id = p.ref))
             and not exists (select 1 from public.stock_ledger y where y.reverses_id = x.id) order by x.id desc loop
      perform public.stock_post(o.item_id, o.location_id, -o.qty_delta, 'reversal', o.ref_type, o.ref_id, o.unit_cost, o.batch_id, now(), 'entry revised: earlier posting undone', o.id, 'none');
    end loop;
    if p.transfer_id is not null then update public.stock_transfers set status = 'cancelled', cancelled_by = auth.uid(), cancelled_at = now() where id = p.transfer_id; end if;
    update public.entry_ledger_posts set status = 'reversed', reversed_at = now() where id = p.id;
  end loop;
  update public.entry_ledger_posts set status = 'void' where entry_id = e.id and gen = g and status in ('failed', 'skipped');
end $$;

create or replace function public._elp_exceptions(e public.entries, g int) returns void
language plpgsql security definer set search_path = public as $$
declare sk text; fl text; nsk int; nfl int;
begin
  delete from public.exceptions where entry_id = e.id and status = 'open' and flag_code in ('ledger_skip', 'ledger_post_failed');
  select count(*), string_agg('#' || line_no::text || ' ' || coalesce(item_code, '-') || ' ' || coalesce(reason, ''), '; ' order by line_no) into nsk, sk
    from public.entry_ledger_posts where entry_id = e.id and gen = g and status = 'skipped';
  select count(*), string_agg('#' || line_no::text || ' ' || coalesce(item_code, '-') || ': ' || coalesce(reason, ''), '; ' order by line_no) into nfl, fl
    from public.entry_ledger_posts where entry_id = e.id and gen = g and status = 'failed';
  if nsk > 0 then
    insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (e.id, e.form_code, e.location_id, e.entry_date, 'ledger_skip', 'yellow', nsk,
        jsonb_build_object('bn', e.form_code || '-' || e.serial || ': ' || nsk || ' লাইন স্টক লেজারে যায়নি — ' || left(sk, 300),
                           'en', e.form_code || '-' || e.serial || ': ' || nsk || ' line(s) were not posted to the stock ledger — ' || left(sk, 300)));
  end if;
  if nfl > 0 then
    insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (e.id, e.form_code, e.location_id, e.entry_date, 'ledger_post_failed', 'yellow', nfl,
        jsonb_build_object('bn', e.form_code || '-' || e.serial || ': ' || nfl || ' লাইন স্টক লেজারে পোস্ট হয়নি (আবার চেষ্টা করা যাবে) — ' || left(fl, 300),
                           'en', e.form_code || '-' || e.serial || ': ' || nfl || ' line(s) could not be posted to the stock ledger (retry is possible) — ' || left(fl, 300)));
  end if;
end $$;

-- ---------- the poster: idempotent. Same content = nothing new; changed content = reverse the old generation and post the new one ----------
create or replace function public.entry_post_ledger(p_entry uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
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
  select count(*) filter (where status = 'posted'), count(*) filter (where status = 'failed'), count(*) filter (where status = 'skipped') into nposted, nfail, nskip
    from public.entry_ledger_posts where entry_id = e.id and gen = g;
  perform public._elp_exceptions(e, g);
  return jsonb_build_object('ok', true, 'enabled', true, 'gen', g, 'posted', nposted, 'failed', nfail, 'skipped', nskip);
end $$;
revoke all on function public.entry_post_ledger(uuid), public._elp_post_line(public.entries, int, text, jsonb), public._elp_reverse(public.entries, int),
  public._elp_exceptions(public.entries, int), public._elp_lines(public.entries) from public, anon, authenticated;

-- the trigger: never blocks the approval (a failure of the whole poster becomes one exception)
create or replace function public._entries_post_ledger() returns trigger
language plpgsql security definer set search_path = public as $$
declare msg text;
begin
  if not public._elp_enabled(new.form_code) then return null; end if;
  begin
    perform public.entry_post_ledger(new.id);
  exception when others then
    msg := sqlerrm;
    begin
      insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
        values (new.id, new.form_code, new.location_id, new.entry_date, 'ledger_post_failed', 'yellow', null,
          jsonb_build_object('bn', new.form_code || '-' || new.serial || ': স্টক লেজারে পোস্ট হয়নি — ' || left(msg, 200),
                             'en', new.form_code || '-' || new.serial || ': could not post to the stock ledger — ' || left(msg, 200)));
    exception when others then null;
    end;
  end;
  return null;
end $$;
revoke all on function public._entries_post_ledger() from public, anon, authenticated;
drop trigger if exists entries_post_ledger on public.entries;
create trigger entries_post_ledger after update on public.entries for each row
  when (new.status = 'approved' and (old.status is distinct from 'approved' or old.data is distinct from new.data or old.check_data is distinct from new.check_data))
  execute function public._entries_post_ledger();

-- ---------- public RPCs ----------
create or replace function public._elp_may(p_entry uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and exists (select 1 from public.entries e where e.id = p_entry
    and (public.is_owner() or (public.can_loc(e.location_id) and public.can_do(e.form_code, 'approve'))));
$$;
revoke all on function public._elp_may(uuid) from public, anon, authenticated;

create or replace function public.entry_post_ledger_retry(p_entry uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._elp_may(p_entry) then raise exception 'not allowed'; end if;
  return public.entry_post_ledger(p_entry);
end $$;

-- lines of one entry (what went to the ledger); no costs
create or replace function public.entry_ledger_lines(p_entry uuid)
returns table (gen int, line_no int, kind text, item_code text, qty_base numeric, status text, reason text, posted_at timestamptz, reversed_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_active() and exists (select 1 from public.entries e where e.id = p_entry and (public.is_owner() or public.can_loc(e.location_id)))) then raise exception 'not allowed'; end if;
  return query select x.gen, x.line_no, x.kind, x.item_code, x.qty_base, x.status, x.reason, x.posted_at, x.reversed_at from public.entry_ledger_posts x where x.entry_id = p_entry order by x.gen, x.line_no;
end $$;

-- approved entries whose latest generation has failed lines (the retry list)
create or replace function public.ledger_post_problems(p_loc int default null)
returns table (entry_id uuid, form_code text, serial int, location_id int, entry_date date, failed int, skipped int, first_reason text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query
    with cur as (select x.entry_id, max(x.gen) g from public.entry_ledger_posts x group by 1)
    select e.id, e.form_code, e.serial, e.location_id, e.entry_date,
           (count(*) filter (where x.status = 'failed'))::int, (count(*) filter (where x.status = 'skipped'))::int,
           min(x.reason) filter (where x.status = 'failed')
    from cur join public.entry_ledger_posts x on x.entry_id = cur.entry_id and x.gen = cur.g
    join public.entries e on e.id = x.entry_id
    where (p_loc is null or e.location_id = p_loc) and (public.is_owner() or (public.can_loc(e.location_id) and public.can_do(e.form_code, 'approve')))
    group by e.id, e.form_code, e.serial, e.location_id, e.entry_date
    having count(*) filter (where x.status in ('failed', 'skipped')) > 0
    order by e.entry_date desc, e.serial desc limit 200;
end $$;

-- owner: per-form switch
create or replace function public.forms_ledger_cfg_set(p_form text, p_on boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_form not in ('04-1', '04-2', '04-3', '03-1', '05-1') or p_on is null then raise exception 'bad_form'; end if;
  insert into public.forms_ledger_cfg (form_code, is_on, changed_by, changed_at) values (p_form, p_on, auth.uid(), now())
    on conflict (form_code) do update set is_on = excluded.is_on, changed_by = auth.uid(), changed_at = now();
  return jsonb_build_object('form_code', p_form, 'is_on', p_on);
end $$;

-- ---------- (3) discount approver on sales ----------
alter table public.sales add column if not exists discount_approved_by uuid;
alter table public.sales add column if not exists discount_approved_staff text;
alter table public.sales add column if not exists discount_approval text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'sales_discount_approval_chk') then
    alter table public.sales add constraint sales_discount_approval_chk check (discount_approval is null or discount_approval in ('grant', 'emergency'));
  end if;
end $$;

-- record_sale2 asks rule_ok('discount_over_limit', ...) BEFORE the insert: a granted role passes can_grant (= the seller holds the right), otherwise the one-use / window
-- emergency approval is consumed and use_emergency leaves 'id:grant' in the transaction setting bos.em_used.  The trigger reads exactly that.
create or replace function public._sales_discount_approver() returns trigger
language plpgsql security definer set search_path = public as $$
declare em text; rid bigint; r public.emergency_requests; lim jsonb;
begin
  if coalesce(new.discount, 0) <= 0 or new.discount_approved_by is not null then return new; end if;
  em := current_setting('bos.em_used', true);
  if em is not null and em ~ ':discount_over_limit' then
    select (x.m)[1]::bigint into rid from regexp_matches(em, '([0-9]+):discount_over_limit', 'g') as x(m) order by (x.m)[1]::bigint desc limit 1;
    select * into r from public.emergency_requests where id = rid;
    if found and r.decided_by is not null then
      new.discount_approved_by := r.decided_by; new.discount_approved_staff := r.decided_staff; new.discount_approval := 'emergency'; return new;
    end if;
  end if;
  select value into lim from public.location_settings where location_id = new.location_id and key = 'discount_limit';
  if public.rule_on('pos_discount_manager') and (lim is null or jsonb_typeof(lim) = 'null' or new.discount > (lim #>> '{}')::numeric) and public.can_grant('discount_over_limit') then
    new.discount_approved_by := new.created_by;
    select staff_id into new.discount_approved_staff from public.profiles where id = new.created_by;
    new.discount_approval := 'grant';
  end if;
  return new;
end $$;
revoke all on function public._sales_discount_approver() from public, anon, authenticated;
drop trigger if exists sales_discount_approver on public.sales;
create trigger sales_discount_approver before insert on public.sales for each row execute function public._sales_discount_approver();

create or replace function public.discounts_report(p_from date, p_to date, p_loc int default null, p_only_approved boolean default false)
returns table (sale_id uuid, location_id int, receipt int, sale_date date, status text, subtotal numeric, discount numeric, discount_kind text, discount_input numeric, total numeric,
               seller_staff text, approver_staff text, approval text, over_limit boolean, customer text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  return query
    select s.id, s.location_id, s.receipt, s.sale_date, s.status, s.subtotal, s.discount, s.discount_kind, s.discount_input, s.total, s.created_staff,
           s.discount_approved_staff, s.discount_approval,
           (s.discount_approval is not null), s.customer
    from public.sales s
    where s.sale_date between p_from and p_to and s.discount > 0 and (p_loc is null or s.location_id = p_loc) and public.can_loc(s.location_id)
      and (not coalesce(p_only_approved, false) or s.discount_approval is not null)
    order by s.sale_date desc, s.location_id, s.receipt desc limit 2000;
end $$;

-- ---------- (4) brand-level P&L ----------
-- The existing gross-profit figures (biz_daily: revenue, discount, voids, costed revenue, cost of goods) grouped by brand.  A location that is not in report_brand_map is
-- shown as 'unmapped' (nothing is guessed).  Cost / gross profit are NULL for callers without a cost right (biz_daily already blanks them).  Combined = the sum of the rows (web).
create or replace function public.brand_pnl(p_from date, p_to date, p_brand text default null)
returns table (brand_code text, brand_bn text, brand_en text, locations int, n bigint, revenue numeric, discount numeric, void_n bigint, void_amt numeric,
               costed_rev numeric, cogs numeric, gross_profit numeric, gp_pct numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  return query
    with d as (select x.* from public.biz_daily(p_from, p_to, null) x),
    m as (select d.*, coalesce(b.brand_code, 'unmapped') bc, b.brand_bn bbn, b.brand_en ben from d left join public.report_brand_map b on b.location_id = d.location_id)
    select m.bc, coalesce(max(m.bbn), 'ব্র্যান্ড ঠিক করা নেই'), coalesce(max(m.ben), 'Not mapped to a brand'), (count(distinct m.location_id))::int,
           sum(m.n)::bigint, sum(m.revenue), sum(m.discount), sum(m.void_n)::bigint, sum(m.void_amt),
           sum(m.costed_rev), sum(m.cogs),
           case when public.biz_cost_ok() then sum(m.costed_rev) - sum(m.cogs) end,
           case when public.biz_cost_ok() and sum(m.costed_rev) > 0 then round((sum(m.costed_rev) - sum(m.cogs)) / sum(m.costed_rev) * 100, 2) end
    from m where p_brand is null or m.bc = p_brand
    group by m.bc order by sum(m.revenue) desc nulls last;
end $$;

-- ---------- grants ----------
revoke all on function public.entry_post_ledger_retry(uuid), public.entry_ledger_lines(uuid), public.ledger_post_problems(int), public.forms_ledger_cfg_set(text, boolean),
  public.discounts_report(date, date, int, boolean), public.brand_pnl(date, date, text) from public, anon;
grant execute on function public.entry_post_ledger_retry(uuid), public.entry_ledger_lines(uuid), public.ledger_post_problems(int), public.forms_ledger_cfg_set(text, boolean),
  public.discounts_report(date, date, int, boolean), public.brand_pnl(date, date, text) to authenticated;
revoke all on function public._elp_num(text), public._elp_flag(text), public._elp_loc(text), public._elp_enabled(text), public._sales_discount_approver() from public, anon, authenticated;

-- ===================== phase21.sql =====================
-- ============================================================
-- BOS tool · Phase 21: MORE REPORTS (12) for the Reports hub, beside the phase9 engine.
-- Run AFTER phase9 (needs report_presets, rpt_* helpers, report_brand_map) and phase10 (stock tables) and the purchase tables.
-- Additive and idempotent: safe to run again. NOTHING from phase9 is replaced or edited.
--
-- Why a second function: phase9's report_run reads its whitelist from rpt_def / rpt_keys (immutable SQL functions inside an already
-- applied file). Replacing them would silently lose the new reports the day phase9 is pasted again. So the new reports have their OWN
-- whitelist and their own three functions with the SAME answer shape as report_run (columns, rows, totals, page, has_more, notes, meta):
--   report_catalog2()                              list for the hub (same fields as report_catalog)
--   report_run2(key, filters, group, sort, page)   the data; user input never becomes SQL (keys in a fixed list, values quoted with %L)
--   log_report_export2(key, kind, filters, rows)   audit row after a CSV / print (owner or grant export_data)
-- The app (web/reports.js + web/reports2.js) merges the two catalogues and sends a key to the function that owns it.
--
-- Security (same rules as phase9)
--   * every call needs the grant report_<group> or view_reports (owner always); rows limited to can_loc() locations
--   * cost columns exist only for owner / ITEM_COST view / grant view_cost or view_profit (not computed otherwise);
--     the two supplier-money reports are cost-only: without that right they are locked, not shown empty
--   * numbers read from the jsonb of forms are parsed safely (text that is not a plain number is skipped and counted, never guessed)
--   * thresholds are RULES with no built-in value: aging buckets reuse report_aging_buckets; "expiring soon" needs report_expiry_soon_days
-- ============================================================

-- ---------- grants (seeded only when missing; nobody gets them by default except the owner: the owner gives them in Who may do what) ----------
do $$
declare r record;
begin
  for r in select * from (values
    ('report_stock',    64, 'রিপোর্ট: স্টক ও অপচয়', 'Report: Stock & wastage', 'Reports: Stock and wastage'),
    ('report_purchase', 65, 'রিপোর্ট: ক্রয় ও সরবরাহকারী', 'Report: Purchases & suppliers', 'Reports: Purchases and suppliers'),
    ('report_expense',  66, 'রিপোর্ট: খরচ', 'Report: Expenses', 'Reports: Expenses'),
    ('report_staff',    67, 'রিপোর্ট: কর্মীর হাজিরা', 'Report: Staff attendance', 'Reports: Staff attendance'),
    ('report_control',  68, 'রিপোর্ট: ব্যতিক্রম (গরমিল)', 'Report: Exceptions', 'Reports: Exceptions')) v(code, sort, bn, mix, en)
  loop
    if not exists (select 1 from public.grant_defs where grant_code = r.code) then
      insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
        values (r.code, 'reports', r.sort, r.bn, r.mix, r.en, 'once', null);
    end if;
  end loop;
end $$;

insert into public.rules (key, module, kind, default_value, unit, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('report_expiry_soon_days', 'reports', 'number', null, 'দিন', 0, 3650, 'মেয়াদ কত দিনের মধ্যে শেষ হলে "শিগগির শেষ" ধরা হবে', 'Expiry কত দিনের মধ্যে হলে "শিগগির শেষ"', 'Days ahead that count as "expiring soon"', 'ফাঁকা থাকলে শুধু মেয়াদ-শেষ ব্যাচ দেখাবে', 'Empty = only batches already past expiry are listed', 65)
 on conflict (key) do nothing;
-- the staff home lists "today's sheets to fill": empty = every sheet the person may enter; the owner can narrow it to the daily sheets (codes separated by commas)
insert into public.rules (key, module, kind, default_value, unit, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('home_daily_forms', 'settings', 'text', null, null, null, null, 'হোমে "আজকের শিট"-এ কোন ফর্মগুলো দেখাবে (কোড, কমা দিয়ে)', 'Home-এ "আজকের Sheet"-এ কোন Form (code, comma দিয়ে)', 'Daily sheets shown on the staff home (form codes, comma separated)', 'ফাঁকা = কর্মী যে ফর্মে লিখতে পারে সবগুলো', 'Empty = every form the person may enter', 66)
 on conflict (key) do nothing;

-- ---------- small helpers ----------
create or replace function public._r2_num(j jsonb) returns numeric
language sql immutable set search_path = public as $$
  select case when j is null then null
    when jsonb_typeof(j) = 'number' then case when (j #>> '{}')::numeric between -1000000000000 and 1000000000000 then (j #>> '{}')::numeric end
    when jsonb_typeof(j) = 'string' and btrim(j #>> '{}') ~ '^-?[0-9]{1,12}(\.[0-9]{1,4})?$' then btrim(j #>> '{}')::numeric end;
$$;

-- locations the caller may use, narrowed by the filters locations / brands
create or replace function public._r2_locs(p_flt jsonb) returns int[]
language plpgsql stable security definer set search_path = public as $$
declare al int[]; lo int[]; br text[];
begin
  al := coalesce((select array_agg(l.id) from public.locations l where public.can_loc(l.id)), '{}');
  lo := public.rpt_arr_int(p_flt -> 'locations');
  if lo is not null then al := coalesce(array(select unnest(al) intersect select unnest(lo)), '{}'); end if;
  br := public.rpt_arr_text(p_flt -> 'brands');
  if br is not null then al := coalesce(array(select x from unnest(al) x where exists (select 1 from public.report_brand_map m where m.location_id = x and m.brand_code = any (br))), '{}'); end if;
  return al;
end $$;

-- the whitelist: group, names, which filters, sort, groups (dims) and fixed columns [key, bn, en, type]
create or replace function public._r2_def(p_key text) returns jsonb
language sql immutable set search_path = public as $j$
  select ($c${
   "item_slow":{"group":"sales","bn":"ধীর ও অবিক্রীত আইটেম","en":"Slow and unsold items","mix":"ধীর ও unsold Item","allow":["locations","brands","categories"],"sort":"qty:asc"},
   "stock_low":{"group":"stock","bn":"স্টক কম (ন্যূনতমের নিচে)","en":"Stock at or below minimum","mix":"Stock কম (minimum-এর নিচে)","allow":["locations","brands","categories"],"nodate":1,"sort":"short_by:desc"},
   "stock_balance":{"group":"stock","bn":"স্টক ব্যালান্স","en":"Stock balance","mix":"Stock balance","allow":["locations","brands","categories"],"nodate":1,"sort":"item_name:asc"},
   "wastage":{"group":"stock","bn":"অপচয় (কারণ / আইটেম অনুযায়ী)","en":"Wastage by reason / item","mix":"অপচয় (reason / item অনুযায়ী)","allow":["locations","brands"],"gdef":"reason","dims":["reason","item","location","day"],"sort":"@dim"},
   "expiry_soon":{"group":"stock","bn":"মেয়াদ শেষ / শিগগির শেষ","en":"Expired and expiring soon","mix":"Expiry শেষ / শিগগির শেষ","allow":["locations","brands","categories"],"nodate":1,"sort":"days_left:asc"},
   "transfers_gap":{"group":"stock","bn":"ট্রান্সফার: পৌঁছায়নি / কম পৌঁছেছে","en":"Transfers not received or short","mix":"Transfer: পৌঁছায়নি / কম","allow":["locations","brands"],"sort":"sent_day:desc"},
   "supplier_ageing":{"group":"purchase","bn":"সরবরাহকারীকে দেনার বয়স","en":"Supplier payables ageing","mix":"Supplier-কে দেনার বয়স","allow":["locations","brands"],"nodate":1,"cost":1,"sort":"balance:desc"},
   "purchases_by_supplier":{"group":"purchase","bn":"ক্রয় (সরবরাহকারী অনুযায়ী)","en":"Purchases by supplier","mix":"Purchase (supplier অনুযায়ী)","allow":["locations","brands"],"cost":1,"gdef":"supplier","dims":["supplier","location","day"],"sort":"total:desc"},
   "expense_by_head":{"group":"expense","bn":"খরচ (খাত অনুযায়ী)","en":"Expenses by head","mix":"খরচ (head অনুযায়ী)","allow":["locations","brands"],"gdef":"head","dims":["head","location","day"],"sort":"amount:desc"},
   "cash_short_over":{"group":"cash","bn":"ক্যাশ কম / বেশি","en":"Cash short / over","mix":"Cash কম / বেশি","allow":["locations","brands"],"gdef":"location","dims":["location","day","staff"],"sort":"net:asc"},
   "attendance_summary":{"group":"staff","bn":"হাজিরার সারসংক্ষেপ","en":"Attendance summary","mix":"হাজিরার summary","allow":["locations","brands"],"gdef":"person","dims":["person","location"],"sort":"absent:desc"},
   "exceptions_summary":{"group":"control","bn":"ব্যতিক্রম (গরমিল) সারসংক্ষেপ","en":"Exceptions summary","mix":"Exception summary","allow":["locations","brands"],"gdef":"form","dims":["form","location","flag","level","day"],"sort":"total:desc"}
  }$c$::jsonb) -> p_key;
$j$;

create or replace function public._r2_keys() returns text[]
language sql immutable set search_path = public as $$
  select array['item_slow','stock_low','stock_balance','wastage','expiry_soon','transfers_gap','supplier_ageing','purchases_by_supplier','expense_by_head','cash_short_over','attendance_summary','exceptions_summary'];
$$;

-- group (dimension) labels for the hub / group picker
create or replace function public._r2_dimlab(p_dim text) returns jsonb
language sql immutable set search_path = public as $$
  select ($c${"reason":["কারণ","Reason"],"item":["আইটেম","Item"],"location":["লোকেশন","Location"],"day":["দিন","Day"],"supplier":["সরবরাহকারী","Supplier"],
    "head":["খরচের খাত","Expense head"],"staff":["কর্মী","Staff"],"person":["কর্মী","Person"],"form":["ফর্ম","Form"],"flag":["ব্যতিক্রমের ধরন","Exception type"],"level":["মাত্রা","Level"]}$c$::jsonb) -> p_dim;
$$;

-- access: group grant (or view_reports), cost-only reports also need the cost right
create or replace function public._r2_ok(p_key text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare d jsonb := public._r2_def(p_key);
begin
  if d is null then return false; end if;
  return public.rpt_access(d ->> 'group') and (coalesce((d ->> 'cost')::int, 0) = 0 or public.rpt_cost_ok());
end $$;

-- ---------- catalogue ----------
create or replace function public.report_catalog2() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare k text; d jsonb; out_ jsonb := '[]'::jsonb; dl jsonb; g text; ok boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  foreach k in array public._r2_keys() loop
    d := public._r2_def(k); ok := public._r2_ok(k); dl := '[]'::jsonb;
    if d ? 'dims' then
      for g in select jsonb_array_elements_text(d -> 'dims') loop
        dl := dl || jsonb_build_array(jsonb_build_object('key', g, 'time', g = 'day', 'label_bn', public._r2_dimlab(g) ->> 0, 'label_en', public._r2_dimlab(g) ->> 1, 'needs_rule', null));
      end loop;
    end if;
    out_ := out_ || jsonb_build_array(jsonb_build_object('key', k, 'group', d ->> 'group', 'grant', 'report_' || (d ->> 'group'), 'allowed', ok, 'kind', 'raw', 'engine', 2,
      'name_bn', d ->> 'bn', 'name_en', d ->> 'en', 'name_mix', d ->> 'mix',
      'filters', to_jsonb(case when coalesce((d ->> 'nodate')::int, 0) = 0 then array['date'] else '{}'::text[] end || coalesce((select array_agg(x) from jsonb_array_elements_text(d -> 'allow') x), '{}')),
      'dims', dl, 'default_group', nullif(d ->> 'gdef', ''), 'columns', '[]'::jsonb, 'compare', false, 'needs_date', coalesce((d ->> 'nodate')::int, 0) = 0, 'cost_only', coalesce((d ->> 'cost')::int, 0) = 1));
  end loop;
  return out_;
end $$;

-- ---------- the data ----------
create or replace function public.report_run2(p_key text, p_filters jsonb default '{}'::jsonb, p_group text default null, p_sort text default null, p_page int default 1) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  def jsonb; flt jsonb; notes jsonb := '[]'::jsonb; today date := (now() at time zone 'Asia/Dhaka')::date; cost_ok boolean; eff int[]; nloc int;
  d1 date; d2 date; pr jsonb; preset text; pgsize int; pg int := least(greatest(coalesce(p_page, 1), 1), 1000); off int; lim int; cap constant int := 500;
  g text; t text; tot text; cols jsonb := '[]'::jsonb; outc jsonb := '[]'::jsonb; allowkeys text[] := '{}'; c jsonb; sk text; sd text; sraw text; sparts text[]; ordr text; dsort text;
  rows_ jsonb; totals_ jsonb; ngroups bigint := 0; hm boolean; dn boolean := false; cat text[]; cf text := ''; days_ numeric; bk text; buckets int[]; i int; lo int; hi int; bsel text := '';
  de text; dcols jsonb; dgrp text; n_unset bigint; n_bad bigint; cs text := ''; ct text := ''; allow_all boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  def := public._r2_def(p_key);
  if def is null then raise exception 'unknown_report'; end if;
  if not public._r2_ok(p_key) then raise exception 'not allowed'; end if;
  flt := case when p_filters is not null and jsonb_typeof(p_filters) = 'object' then p_filters else '{}'::jsonb end;
  cost_ok := public.rpt_cost_ok();
  eff := public._r2_locs(flt);
  select count(*) into nloc from public.locations;
  if cardinality(public._r2_locs('{}'::jsonb)) < nloc then notes := notes || jsonb_build_array(jsonb_build_object('code', 'location_scope')); end if;
  if cardinality(eff) = 0 then notes := notes || jsonb_build_array(jsonb_build_object('code', 'no_location', 'text_en', 'No location is open to you', 'text_bn', 'কোনো লোকেশন আপনার জন্য খোলা নেই')); end if;
  pgsize := least(greatest(coalesce(public.rule_num('report_page_size'), 50), 10), 200)::int;
  off := (pg - 1) * pgsize; lim := greatest(least(pgsize, cap - off), 0);
  -- unknown filter keys are reported, never used
  for g in select jsonb_object_keys(flt) loop
    if g in ('from', 'to', 'preset', 'compare_mode') or jsonb_typeof(flt -> g) = 'null' then continue; end if;
    if not (def -> 'allow' @> to_jsonb(g)) then notes := notes || jsonb_build_array(jsonb_build_object('code', 'filter_ignored', 'what', left(g, 40))); end if;
  end loop;
  cat := case when def -> 'allow' @> '"categories"' then public.rpt_arr_text(flt -> 'categories') end;

  if coalesce((def ->> 'nodate')::int, 0) = 0 then
    preset := flt ->> 'preset';
    if preset is not null then
      pr := public.report_presets() -> preset;
      if pr is null or jsonb_typeof(pr) = 'null' then
        return jsonb_build_object('report', p_key, 'columns', '[]'::jsonb, 'rows', '[]'::jsonb, 'totals', null, 'compare', null, 'has_more', false, 'data_needed', true,
          'page', jsonb_build_object('n', pg, 'size', pgsize, 'groups', 0, 'cap', cap),
          'notes', jsonb_build_array(jsonb_build_object('code', 'data_needed', 'what', left(preset, 30), 'text_en', 'Unknown date preset', 'text_bn', 'তারিখের প্রিসেটের নাম ভুল')));
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

  -- group (one dimension)
  if def ? 'dims' then
    dgrp := lower(btrim(coalesce(p_group, '')));
    if dgrp = '' then dgrp := def ->> 'gdef';
    elsif dgrp like '%,%' then
      notes := notes || jsonb_build_array(jsonb_build_object('code', 'group_ignored', 'what', left(split_part(dgrp, ',', 2), 30))); dgrp := split_part(dgrp, ',', 1);
    end if;
    if dgrp in ('none', 'total', '-') then dgrp := null;
    elsif dgrp is not null and not (def -> 'dims' @> to_jsonb(dgrp)) then
      notes := notes || jsonb_build_array(jsonb_build_object('code', 'group_ignored', 'what', left(dgrp, 30))); dgrp := def ->> 'gdef';
    end if;
  elsif p_group is not null and btrim(p_group) <> '' then
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'group_ignored', 'what', left(p_group, 30)));
  end if;

  -- ============ the queries ============
  if p_key = 'item_slow' then
    if cat is not null then cf := format(' and it.category = any (%L::text[])', cat); end if;
    t := format($f$with s as (select f.item_id, sum(f.qty) as qty, sum(f.net) as net, count(distinct f.sale_id) as bills, max(f.day) as last_sold
        from public.sales_fact f where f.status = 'done' and f.item_id is not null and f.day between %L and %L and f.location_id = any (%L::int[]) group by 1)
      select it.code as item_code, it.name_bn as item_name, it.name_en as item_name_en, coalesce(it.category, '(none)') as category,
        coalesce(round(s.qty, 3), 0) as qty, coalesce(round(s.net, 2), 0) as net, coalesce(s.bills, 0) as bills, s.last_sold
      from public.items it left join s on s.item_id = it.id
      where it.is_active and it.sellable and it.retired_at is null%s$f$, d1, d2, eff, cf);
    tot := 'count(*) as items, count(*) filter (where qty = 0) as unsold_items, coalesce(sum(net), 0) as net';
    cols := '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["category","ক্যাটাগরি","Category","text"],["qty","বিক্রি পরিমাণ","Qty sold","num"],["net","বিক্রি","Sales","money"],["bills","বিল","Bills","int"],["last_sold","শেষ বিক্রি","Last sold","date"]]';
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'info', 'text_en', 'Active sellable items with no sale in the period show 0. Smallest quantity first.', 'text_bn', 'এই সময়ে বিক্রি না হওয়া চালু আইটেম ০ দেখাবে। কম বিক্রি আগে।'));

  elsif p_key = 'stock_low' or p_key = 'stock_balance' then
    if cat is not null then cf := format(' and it.category = any (%L::text[])', cat); end if;
    if p_key = 'stock_low' then
      cs := case when cost_ok then ', round(greatest(it.min_stock - b.qty, 0) * b.avg_cost, 2) as reorder_value' else '' end;
      t := format($f$select it.code as item_code, it.name_bn as item_name, it.name_en as item_name_en, coalesce(it.category, '(none)') as category, l.id as location_id,
          l.name_bn as location_bn, l.name_en as location_en, b.qty, it.min_stock, round(it.min_stock - b.qty, 3) as short_by, it.unit%s
        from public.stock_balance b join public.items it on it.id = b.item_id join public.locations l on l.id = b.location_id
        where b.location_id = any (%L::int[]) and it.is_active and it.min_stock is not null and b.qty <= it.min_stock%s$f$, cs, eff, cf);
      tot := 'count(*) as lines, count(*) filter (where qty <= 0) as at_zero' || case when cost_ok then ', sum(reorder_value) as reorder_value' else '' end;
      cols := '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["category","ক্যাটাগরি","Category","text"],["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["qty","আছে","On hand","num"],["min_stock","ন্যূনতম","Minimum","num"],["short_by","ঘাটতি","Short by","num"],["unit","একক","Unit","text"]]';
      select count(*) into n_unset from public.items it where it.is_active and it.tracked and it.min_stock is null;
      if n_unset > 0 then notes := notes || jsonb_build_array(jsonb_build_object('code', 'data_needed', 'what', 'min_stock', 'text_en', n_unset || ' tracked items have no minimum set, so they cannot be checked', 'text_bn', n_unset || 'টি ট্র্যাক করা আইটেমে ন্যূনতম স্টক বসানো নেই, তাই যাচাই হয়নি')); end if;
    else
      cs := case when cost_ok then ', b.avg_cost, round(b.qty * b.avg_cost, 2) as value' else '' end;
      t := format($f$select it.code as item_code, it.name_bn as item_name, it.name_en as item_name_en, coalesce(it.category, '(none)') as category, l.id as location_id,
          l.name_bn as location_bn, l.name_en as location_en, b.qty, it.unit, it.min_stock,
          case when it.min_stock is null then 'no_min' when b.qty <= it.min_stock then 'low' else 'ok' end as state%s
        from public.stock_balance b join public.items it on it.id = b.item_id join public.locations l on l.id = b.location_id
        where b.location_id = any (%L::int[]) and it.is_active%s$f$, cs, eff, cf);
      tot := 'count(*) as lines, count(*) filter (where state = ''low'') as low_lines, count(*) filter (where state = ''no_min'') as no_min_lines' || case when cost_ok then ', sum(value) as value' else '' end;
      cols := '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["category","ক্যাটাগরি","Category","text"],["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["qty","আছে","On hand","num"],["unit","একক","Unit","text"],["min_stock","ন্যূনতম","Minimum","num"],["state","অবস্থা","State","text"]]';
    end if;
    if cost_ok then
      cols := cols || case when p_key = 'stock_low' then '[["reorder_value","পূরণের আনুমানিক খরচ","Approx. cost to refill","money"]]'::jsonb
                           else '[["avg_cost","গড় খরচ","Avg cost","money"],["value","মূল্য","Value","money"]]'::jsonb end;
    else notes := notes || jsonb_build_array(jsonb_build_object('code', 'cost_hidden')); end if;

  elsif p_key = 'wastage' then
    dcols := case dgrp when 'item' then '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["unit","একক","Unit","text"]]'
                       when 'location' then '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"]]'
                       when 'day' then '[["day","দিন","Day","date"]]'
                       when 'reason' then '[["reason","","","id"],["reason_bn","কারণ","Reason","text"],["reason_en","Reason (EN)","Reason (EN)","text"]]'
                       else '[]' end::jsonb;
    cs := case when cost_ok then ', round(sum(w.qty * sl.unit_cost) filter (where sl.unit_cost is not null), 2) as value, count(*) filter (where sl.unit_cost is null) as uncosted_entries' else '' end;
    t := format($f$select %s count(*) as entries%s%s
      from public.stock_wastage w join public.items it on it.id = w.item_id join public.locations l on l.id = w.location_id
        left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = w.reason_code
        left join public.stock_ledger sl on sl.id = w.ledger_id
      where (w.made_at at time zone 'Asia/Dhaka')::date between %L and %L and w.location_id = any (%L::int[])%s$f$,
      case dgrp when 'item' then 'it.code as item_code, it.name_bn as item_name, it.name_en as item_name_en, it.unit as unit,'
                when 'location' then 'l.id as location_id, l.name_bn as location_bn, l.name_en as location_en,'
                when 'day' then '(w.made_at at time zone ''Asia/Dhaka'')::date as day,'
                when 'reason' then 'w.reason_code as reason, coalesce(o.label_bn, w.reason_code) as reason_bn, coalesce(o.label_en, w.reason_code) as reason_en,'
                else '' end,
      case when dgrp = 'item' then ', round(sum(w.qty), 3) as qty' else '' end, cs, d1, d2, eff,
      case dgrp when 'item' then ' group by it.id, it.code, it.name_bn, it.name_en, it.unit'
                when 'location' then ' group by l.id, l.name_bn, l.name_en'
                when 'day' then ' group by 1'
                when 'reason' then ' group by w.reason_code, o.label_bn, o.label_en'
                else '' end);
    tot := 'sum(entries) as entries' || case when cost_ok then ', sum(value) as value, sum(uncosted_entries) as uncosted_entries' else '' end;
    cols := dcols || '[["entries","বার","Entries","int"]]'::jsonb || case when dgrp = 'item' then '[["qty","পরিমাণ","Qty","num"]]'::jsonb else '[]'::jsonb end;
    if cost_ok then cols := cols || '[["value","মূল্য (খরচ জানা অংশে)","Value (costed part)","money"],["uncosted_entries","খরচ অজানা সারি","Entries with no cost","int"]]'::jsonb;
    else notes := notes || jsonb_build_array(jsonb_build_object('code', 'cost_hidden')); end if;
    if dgrp is distinct from 'item' then notes := notes || jsonb_build_array(jsonb_build_object('code', 'info', 'text_en', 'Quantity is shown only per item (units differ between items).', 'text_bn', 'পরিমাণ শুধু আইটেম অনুযায়ী দেখানো হয় (আইটেমের একক আলাদা)।')); end if;

  elsif p_key = 'expiry_soon' then
    days_ := public.rule_num('report_expiry_soon_days');
    if cat is not null then cf := format(' and it.category = any (%L::text[])', cat); end if;
    cs := case when cost_ok then ', round(b.qty_remaining * sb.avg_cost, 2) as value' else '' end;
    t := format($f$select it.code as item_code, it.name_bn as item_name, it.name_en as item_name_en, l.id as location_id, l.name_bn as location_bn, l.name_en as location_en,
        (b.made_at at time zone 'Asia/Dhaka')::date as made_on, (b.expires_at at time zone 'Asia/Dhaka')::date as expires_on,
        (b.expires_at at time zone 'Asia/Dhaka')::date - %L::date as days_left, b.qty_remaining as qty, it.unit,
        case when (b.expires_at at time zone 'Asia/Dhaka')::date < %L::date then 'expired' else 'soon' end as state%s
      from public.stock_batches b join public.items it on it.id = b.item_id join public.locations l on l.id = b.location_id
        left join public.stock_balance sb on sb.item_id = b.item_id and sb.location_id = b.location_id
      where b.qty_remaining > 0 and b.expires_at is not null and b.location_id = any (%L::int[])
        and (b.expires_at at time zone 'Asia/Dhaka')::date <= %L::date + %s%s$f$,
      today, today, cs, eff, today, case when days_ is null then '-1' else (days_::int)::text end, cf);
    tot := 'count(*) as batches, count(*) filter (where state = ''expired'') as expired_batches' || case when cost_ok then ', sum(value) as value' else '' end;
    cols := '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["made_on","তৈরি","Made","date"],["expires_on","মেয়াদ শেষ","Expires","date"],["days_left","বাকি দিন","Days left","int"],["qty","পরিমাণ (বাকি)","Qty left","num"],["unit","একক","Unit","text"],["state","অবস্থা","State","text"]]';
    if cost_ok then cols := cols || '[["value","আনুমানিক মূল্য","Approx. value","money"]]'::jsonb; else notes := notes || jsonb_build_array(jsonb_build_object('code', 'cost_hidden')); end if;
    if days_ is null then notes := notes || jsonb_build_array(jsonb_build_object('code', 'data_needed', 'what', 'report_expiry_soon_days', 'text_en', 'Set "days ahead" in Rules to also see batches that expire soon. Only batches already expired are listed.', 'text_bn', 'শিগগির শেষ হবে এমন ব্যাচ দেখতে নিয়মে দিনের সংখ্যা বসান। এখন শুধু মেয়াদ-শেষ ব্যাচ দেখাচ্ছে।')); end if;

  elsif p_key = 'transfers_gap' then
    t := format($f$select (x.sent_at at time zone 'Asia/Dhaka')::date as sent_day, lf.name_bn as from_bn, lf.name_en as from_en, lt.name_bn as to_bn, lt.name_en as to_en,
        it.code as item_code, it.name_bn as item_name, it.name_en as item_name_en, x.qty as sent_qty, x.received_qty,
        case when x.status = 'received' then round(x.qty - coalesce(x.received_qty, x.qty), 3) end as diff_qty, x.status, x.sent_staff, x.received_staff
      from public.stock_transfers x join public.items it on it.id = x.item_id join public.locations lf on lf.id = x.from_location_id join public.locations lt on lt.id = x.to_location_id
      where (x.sent_at at time zone 'Asia/Dhaka')::date between %L and %L and (x.from_location_id = any (%L::int[]) or x.to_location_id = any (%L::int[]))
        and x.status <> 'cancelled' and (x.status = 'sent' or coalesce(x.received_qty, x.qty) <> x.qty)$f$, d1, d2, eff, eff);
    tot := 'count(*) as transfers, count(*) filter (where status = ''sent'') as not_received, count(*) filter (where diff_qty <> 0) as short_received';
    cols := '[["sent_day","পাঠানো","Sent","date"],["from_bn","কোথা থেকে","From","text"],["from_en","From (EN)","From (EN)","text"],["to_bn","কোথায়","To","text"],["to_en","To (EN)","To (EN)","text"],["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["sent_qty","পাঠানো পরিমাণ","Sent qty","num"],["received_qty","পৌঁছেছে","Received qty","num"],["diff_qty","পার্থক্য","Difference","num"],["status","অবস্থা","Status","text"],["sent_staff","পাঠিয়েছে","Sent by","text"],["received_staff","গ্রহণ করেছে","Received by","text"]]';

  elsif p_key = 'supplier_ageing' then
    allow_all := public._all_locs() and public.rpt_arr_int(flt -> 'locations') is null and public.rpt_arr_text(flt -> 'brands') is null;
    bk := public.rule_txt('report_aging_buckets');
    if bk is not null and bk ~ '^[0-9]{1,4}(,[0-9]{1,4}){0,5}$' then
      buckets := string_to_array(bk, ',')::int[];
      for i in 2..cardinality(buckets) loop if buckets[i] <= buckets[i - 1] then buckets := null; exit; end if; end loop;
    end if;
    cols := '[["supplier_id","","","id"],["supplier","সরবরাহকারী","Supplier","text"],["balance","মোট দেনা","Total payable","money"],["opening_part","শুরুর বাকি (তারিখ ছাড়া)","Opening balance part","money"]]';
    if buckets is not null and cardinality(buckets) > 0 then
      for i in 1..cardinality(buckets) + 1 loop
        lo := case when i = 1 then 0 else buckets[i - 1] + 1 end; hi := case when i <= cardinality(buckets) then buckets[i] end;
        bsel := bsel || format(', round(coalesce(sum(o.open_amt) filter (where o.bill_date is not null and (%L::date - o.bill_date) %s), 0), 2) as bucket_%s', today,
          case when hi is null then '>= ' || lo else 'between ' || lo || ' and ' || hi end, i);
        cols := cols || jsonb_build_array(jsonb_build_array('bucket_' || i, case when hi is null then lo || '+ দিন' else lo || '–' || hi || ' দিন' end, case when hi is null then lo || '+ days' else lo || '–' || hi || ' days' end, 'money'));
      end loop;
    else notes := notes || jsonb_build_array(jsonb_build_object('code', 'data_needed', 'what', 'report_aging_buckets', 'text_en', 'Set the ageing buckets (days) in Rules to split by age', 'text_bn', 'বয়স ভাগ করতে নিয়মে দিনের ভাগ বসান')); end if;
    cols := cols || '[["oldest_days","সবচেয়ে পুরনো (দিন)","Oldest (days)","int"],["credit_days","বাকির মেয়াদ (দিন)","Credit days","int"],["overdue","মেয়াদ পার","Past credit days","money"]]'::jsonb;
    t := format($f$with o as (select * from public._sup_open(null) where open_amt > 0)
      select s.id as supplier_id, s.name as supplier, round(sum(o.open_amt), 2) as balance, round(coalesce(sum(o.open_amt) filter (where o.bill_date is null), 0), 2) as opening_part%s,
        max(%L::date - o.bill_date) as oldest_days, s.credit_days,
        round(coalesce(sum(o.open_amt) filter (where s.credit_days is not null and o.bill_date is not null and o.bill_date + s.credit_days < %L::date), 0), 2) as overdue
      from o join public.suppliers s on s.id = o.supplier_id
      where o.location_id = any (%L::int[]) or (o.location_id is null and %L::boolean)
      group by s.id, s.name, s.credit_days$f$, bsel, today, today, eff, allow_all);
    tot := 'count(*) as suppliers, sum(balance) as balance, sum(overdue) as overdue' || (select coalesce(string_agg(format(', sum(bucket_%s) as bucket_%s', n, n), ''), '') from generate_series(1, coalesce(cardinality(buckets), -1) + 1) n where buckets is not null);
    if not allow_all then notes := notes || jsonb_build_array(jsonb_build_object('code', 'info', 'text_en', 'Opening balances (no shop) are included only when all locations are selected', 'text_bn', 'শুরুর বাকি (দোকান ছাড়া) শুধু সব লোকেশন বাছা থাকলে ধরা হয়')); end if;

  elsif p_key = 'purchases_by_supplier' then
    de := case dgrp when 'supplier' then 's.id as supplier_id, s.name as supplier,' when 'location' then 'l.id as location_id, l.name_bn as location_bn, l.name_en as location_en,'
                    when 'day' then 'b.bill_date as day,' else '' end;
    t := format($f$select %s count(*) filter (where b.kind = 'bill') as bills, coalesce(sum(b.subtotal) filter (where b.kind = 'bill'), 0) as subtotal,
        coalesce(sum(b.discount) filter (where b.kind = 'bill'), 0) as discount, coalesce(sum(b.total) filter (where b.kind = 'bill'), 0) as total,
        coalesce(sum(b.paid) filter (where b.kind = 'bill'), 0) as paid, coalesce(sum(b.total - b.paid) filter (where b.kind = 'bill'), 0) as due,
        count(*) filter (where b.kind = 'return') as returns, coalesce(sum(b.total) filter (where b.kind = 'return'), 0) as returns_total
      from public.purchase_bills b join public.suppliers s on s.id = b.supplier_id join public.locations l on l.id = b.location_id
      where b.status = 'posted' and b.bill_date between %L and %L and b.location_id = any (%L::int[])%s$f$, de, d1, d2, eff,
      case dgrp when 'supplier' then ' group by s.id, s.name' when 'location' then ' group by l.id, l.name_bn, l.name_en' when 'day' then ' group by b.bill_date' else '' end);
    tot := 'sum(bills) as bills, sum(subtotal) as subtotal, sum(discount) as discount, sum(total) as total, sum(paid) as paid, sum(due) as due, sum(returns) as returns, sum(returns_total) as returns_total';
    cols := (case dgrp when 'supplier' then '[["supplier_id","","","id"],["supplier","সরবরাহকারী","Supplier","text"]]' when 'location' then '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"]]'
                       when 'day' then '[["day","দিন","Day","date"]]' else '[]' end)::jsonb
      || '[["bills","বিল","Bills","int"],["subtotal","সাবটোটাল","Subtotal","money"],["discount","ছাড়","Discount","money"],["total","মোট","Total","money"],["paid","পরিশোধ","Paid","money"],["due","বাকি","Due","money"],["returns","রিটার্ন","Returns","int"],["returns_total","রিটার্নের টাকা","Returns amount","money"]]'::jsonb;

  elsif p_key = 'expense_by_head' then
    t := format($f$select %s count(*) filter (where x.amt is not null) as lines, coalesce(sum(x.amt), 0) as amount,
        count(*) filter (where x.amt is not null and x.rcpt = 'no') as no_receipt_lines, coalesce(sum(x.amt) filter (where x.rcpt = 'no'), 0) as no_receipt_amount,
        round(100 * coalesce(sum(x.amt), 0) / nullif(sum(sum(x.amt)) over (), 0), 2) as share_pct, count(*) filter (where x.amt is null) as skipped_lines
      from (select e.id, e.location_id, e.entry_date, public._r2_num(ln -> 'amount') as amt, ln ->> 'receipt' as rcpt, coalesce(nullif(btrim(ln ->> 'head'), ''), '-') as head
            from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) ln
            where e.form_code = '10-2' and e.status in ('submitted', 'approved') and e.entry_date between %L and %L and e.location_id = any (%L::int[])) x
        join public.locations l on l.id = x.location_id left join public.option_lists o on o.list_code = 'expense_heads' and o.value_code = x.head
      %s$f$,
      case dgrp when 'head' then 'x.head as head, coalesce(o.label_bn, x.head) as head_bn, coalesce(o.label_en, x.head) as head_en,'
                when 'location' then 'l.id as location_id, l.name_bn as location_bn, l.name_en as location_en,'
                when 'day' then 'x.entry_date as day,' else '' end, d1, d2, eff,
      case dgrp when 'head' then 'group by x.head, o.label_bn, o.label_en' when 'location' then 'group by l.id, l.name_bn, l.name_en' when 'day' then 'group by x.entry_date' else '' end);
    tot := 'sum(lines) as lines, sum(amount) as amount, sum(no_receipt_lines) as no_receipt_lines, sum(no_receipt_amount) as no_receipt_amount, sum(skipped_lines) as skipped_lines';
    cols := (case dgrp when 'head' then '[["head","","","id"],["head_bn","খাত","Head","text"],["head_en","Head (EN)","Head (EN)","text"]]' when 'location' then '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"]]'
                       when 'day' then '[["day","দিন","Day","date"]]' else '[]' end)::jsonb
      || '[["lines","লাইন","Lines","int"],["amount","টাকা","Amount","money"],["share_pct","অংশ %","Share %","pct"],["no_receipt_lines","রসিদ ছাড়া লাইন","Lines without receipt","int"],["no_receipt_amount","রসিদ ছাড়া টাকা","Amount without receipt","money"],["skipped_lines","পড়া যায়নি এমন লাইন","Unreadable lines","int"]]'::jsonb;
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'info', 'text_en', 'From submitted and approved expense vouchers (10-2). Drafts are not counted. A line whose amount is not a plain number is skipped and counted.', 'text_bn', 'জমা ও অনুমোদিত ব্যয় ভাউচার (১০-২) থেকে। খসড়া ধরা হয়নি। অঙ্ক পড়া না গেলে লাইন বাদ ও গণনা।'));

  elsif p_key = 'cash_short_over' then
    t := format($f$select %s count(*) as sheets, count(*) filter (where x.so < 0) as short_sheets, count(*) filter (where x.so > 0) as over_sheets,
        coalesce(-sum(x.so) filter (where x.so < 0), 0) as short_amount, coalesce(sum(x.so) filter (where x.so > 0), 0) as over_amount, coalesce(sum(x.so), 0) as net,
        coalesce(max(abs(x.so)), 0) as worst
      from (select e.id, e.location_id, e.entry_date, coalesce(nullif(btrim(e.created_staff), ''), '-') as staff,
              coalesce((select sum(public._r2_num(f -> 'amount')) from jsonb_array_elements(case when jsonb_typeof(e.flags) = 'array' then e.flags else '[]'::jsonb end) f where f ->> 'code' = 'cash_short_over'), 0) as so
            from public.entries e where e.form_code = '14-1' and e.status in ('submitted', 'approved') and e.entry_date between %L and %L and e.location_id = any (%L::int[])) x
        join public.locations l on l.id = x.location_id
      %s$f$,
      case dgrp when 'location' then 'l.id as location_id, l.name_bn as location_bn, l.name_en as location_en,' when 'day' then 'x.entry_date as day,' when 'staff' then 'x.staff as staff,' else '' end, d1, d2, eff,
      case dgrp when 'location' then 'group by l.id, l.name_bn, l.name_en' when 'day' then 'group by x.entry_date' when 'staff' then 'group by x.staff' else '' end);
    tot := 'sum(sheets) as sheets, sum(short_sheets) as short_sheets, sum(over_sheets) as over_sheets, sum(short_amount) as short_amount, sum(over_amount) as over_amount, sum(net) as net, max(worst) as worst';
    cols := (case dgrp when 'location' then '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"]]' when 'day' then '[["day","দিন","Day","date"]]'
                       when 'staff' then '[["staff","কর্মী (শিট লেখক)","Staff (sheet writer)","text"]]' else '[]' end)::jsonb
      || '[["sheets","শিট","Sheets","int"],["short_sheets","কম হওয়া শিট","Sheets short","int"],["over_sheets","বেশি হওয়া শিট","Sheets over","int"],["short_amount","কম (মোট)","Short (total)","money"],["over_amount","বেশি (মোট)","Over (total)","money"],["net","নিট (বেশি − কম)","Net (over − short)","money"],["worst","সবচেয়ে বড় পার্থক্য","Largest gap","money"]]'::jsonb;
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'info', 'text_en', 'Taken from the short/over flag of each daily showroom sheet (14-1), worked out on the phone when the sheet was saved. A sheet with an exact match carries no flag and counts as 0.', 'text_bn', 'প্রতিটি দৈনিক শোরুম শিটের (১৪-১) কম/বেশি চিহ্ন থেকে, যা ফোনে শিট সেভের সময় হিসাব হয়েছিল। ঠিকঠাক মিললে চিহ্ন থাকে না, ০ ধরা হয়।'));

  elsif p_key = 'attendance_summary' then
    t := format($f$select %s count(distinct x.id) as sheets, coalesce(sum(x.present), 0) as present, coalesce(sum(x.late), 0) as late, coalesce(sum(x.absent), 0) as absent,
        coalesce(sum(x.leave_unpaid), 0) as leave_unpaid, coalesce(sum(x.leave_paid), 0) as leave_paid, coalesce(sum(x.ot_hours), 0) as ot_hours
      from (select e.id, e.location_id, btrim(r ->> 'name') as person, public._r2_num(r -> 'present') as present, public._r2_num(r -> 'late') as late, public._r2_num(r -> 'absent') as absent,
              public._r2_num(r -> 'leave_unpaid') as leave_unpaid, public._r2_num(r -> 'leave_paid') as leave_paid, public._r2_num(r -> 'ot_hours') as ot_hours
            from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'staff') = 'array' then e.data -> 'staff' else '[]'::jsonb end) r
            where e.form_code = '02-1' and e.status in ('submitted', 'approved') and e.entry_date between %L and %L and e.location_id = any (%L::int[])
              and btrim(coalesce(r ->> 'name', '')) <> '') x
        join public.locations l on l.id = x.location_id
      %s$f$,
      case dgrp when 'person' then 'x.person as person,' when 'location' then 'l.id as location_id, l.name_bn as location_bn, l.name_en as location_en,' else '' end, d1, d2, eff,
      case dgrp when 'person' then 'group by x.person' when 'location' then 'group by l.id, l.name_bn, l.name_en' else '' end);
    tot := 'sum(present) as present, sum(late) as late, sum(absent) as absent, sum(leave_unpaid) as leave_unpaid, sum(leave_paid) as leave_paid, sum(ot_hours) as ot_hours';
    cols := (case dgrp when 'person' then '[["person","কর্মী","Person","text"]]' when 'location' then '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"]]' else '[]' end)::jsonb
      || '[["sheets","শিট","Sheets","int"],["present","উপস্থিত","Present","num"],["late","দেরি","Late","num"],["absent","অনুপস্থিত","Absent","num"],["leave_unpaid","বিনা বেতনের ছুটি","Unpaid leave","num"],["leave_paid","সবেতন ছুটি","Paid leave","num"],["ot_hours","ওভারটাইম ঘণ্টা","Overtime hours","num"]]'::jsonb;
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'info', 'text_en', 'From monthly attendance registers (02-1) dated inside the period. Same person on two sheets is added up by name.', 'text_bn', 'সময়ের মধ্যে তারিখের মাসিক হাজিরা রেজিস্টার (০২-১) থেকে। একই নাম দুই শিটে থাকলে যোগ হয়।'));

  elsif p_key = 'exceptions_summary' then
    t := format($f$select %s count(*) as total, count(*) filter (where x.status = 'open') as open, count(*) filter (where x.status = 'resolved') as resolved,
        count(*) filter (where x.level = 'red') as red, count(*) filter (where x.level = 'yellow') as yellow,
        round(avg(extract(epoch from (x.resolved_at - x.created_at)) / 3600.0) filter (where x.status = 'resolved' and x.resolved_at is not null), 1) as avg_hours_to_resolve
      from public.exceptions x join public.locations l on l.id = x.location_id
      where x.entry_date between %L and %L and x.location_id = any (%L::int[])
      %s$f$,
      case dgrp when 'form' then 'x.form_code as form,' when 'location' then 'l.id as location_id, l.name_bn as location_bn, l.name_en as location_en,' when 'flag' then 'x.flag_code as flag,'
                when 'level' then 'x.level as level,' when 'day' then 'x.entry_date as day,' else '' end, d1, d2, eff,
      case dgrp when 'form' then 'group by x.form_code' when 'location' then 'group by l.id, l.name_bn, l.name_en' when 'flag' then 'group by x.flag_code' when 'level' then 'group by x.level' when 'day' then 'group by x.entry_date' else '' end);
    tot := 'sum(total) as total, sum(open) as open, sum(resolved) as resolved, sum(red) as red, sum(yellow) as yellow';
    cols := (case dgrp when 'form' then '[["form","ফর্ম","Form","text"]]' when 'location' then '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"]]'
                       when 'flag' then '[["flag","ধরন","Type","text"]]' when 'level' then '[["level","মাত্রা","Level","text"]]' when 'day' then '[["day","দিন (শিটের)","Day (of sheet)","date"]]' else '[]' end)::jsonb
      || '[["total","মোট","Total","int"],["open","খোলা","Open","int"],["resolved","সমাধান","Resolved","int"],["red","লাল","Red","int"],["yellow","হলুদ","Yellow","int"],["avg_hours_to_resolve","গড় সমাধানের ঘণ্টা","Avg hours to resolve","num"]]'::jsonb;
  end if;

  -- columns -> response shape, sort whitelist
  for c in select * from jsonb_array_elements(cols) loop
    outc := outc || jsonb_build_array(jsonb_build_object('key', c ->> 0, 'label_bn', c ->> 1, 'label_en', c ->> 2, 'type', c ->> 3,
      'role', case when c ->> 3 in ('money', 'int', 'num', 'pct') then 'measure' else 'dim' end, 'cost', (c ->> 0) in ('value', 'avg_cost', 'reorder_value', 'uncosted_entries')));
    allowkeys := allowkeys || (c ->> 0);
  end loop;
  sraw := lower(btrim(coalesce(p_sort, '')));
  if sraw <> '' then
    if left(sraw, 1) = '-' then sd := 'desc'; sraw := substr(sraw, 2); end if;
    sparts := regexp_split_to_array(sraw, '[: ]+');
    if sparts[1] = any (allowkeys) then sk := sparts[1]; sd := coalesce(sd, case when sparts[2] = 'desc' then 'desc' else 'asc' end);
    else notes := notes || jsonb_build_array(jsonb_build_object('code', 'sort_ignored', 'what', left(sparts[1], 30))); end if;
  end if;
  if sk is null then
    dsort := def ->> 'sort';
    if dsort = '@dim' or split_part(dsort, ':', 1) <> all (allowkeys) then
      sk := coalesce((select c2 ->> 0 from jsonb_array_elements(cols) c2 where c2 ->> 3 <> 'id' limit 1), allowkeys[1]); sd := 'asc';
    else sk := split_part(dsort, ':', 1); sd := split_part(dsort, ':', 2); end if;
  end if;
  ordr := quote_ident(sk) || ' ' || case when sd = 'desc' then 'desc' else 'asc' end || ' nulls last, 1';

  execute format('select coalesce(jsonb_agg(to_jsonb(x) - ''_n'' - ''_rn'' order by x._rn), ''[]''::jsonb), coalesce(max(x._n), 0) from (select q.*, count(*) over () as _n, row_number() over (order by %s) as _rn from (%s) q order by %s limit %s offset %s) x',
    ordr, t, ordr, lim, off) into rows_, ngroups;
  execute format('select to_jsonb(x) from (select %s from (%s) q) x', tot, t) into totals_;
  hm := (off + pgsize) < least(ngroups, cap);
  if ngroups > cap then notes := notes || jsonb_build_array(jsonb_build_object('code', 'truncated', 'cap', cap, 'groups', ngroups)); end if;
  if jsonb_array_length(rows_) = 0 or ngroups = 0 then
    dn := true;
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'no_data', 'text_en', 'Data needed: nothing matches this period / filters', 'text_bn', 'তথ্য দরকার: এই সময়/ফিল্টারে কিছু নেই'));
  end if;
  return jsonb_build_object('report', p_key, 'columns', outc, 'rows', rows_, 'totals', totals_, 'compare', null,
    'page', jsonb_build_object('n', pg, 'size', pgsize, 'groups', ngroups, 'cap', cap), 'has_more', coalesce(hm, false), 'notes', notes, 'data_needed', dn,
    'meta', jsonb_build_object('from', d1, 'to', d2, 'group', case when dgrp is null then '[]'::jsonb else jsonb_build_array(dgrp) end, 'sort', sk, 'dir', sd, 'cost_shown', cost_ok, 'today', today));
end $$;

-- ---------- export log ----------
create or replace function public.log_report_export2(p_key text, p_kind text, p_filters jsonb, p_rows int) returns void
language plpgsql security definer set search_path = public as $$
declare sid text; f jsonb := coalesce(p_filters, '{}'::jsonb);
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_grant('export_data')) then raise exception 'not allowed'; end if;
  if p_key is null or not (p_key = any (public._r2_keys())) then raise exception 'unknown_report'; end if;
  if p_kind is null or lower(p_kind) !~ '^[a-z0-9_]{1,20}$' then raise exception 'bad_kind'; end if;
  if length(f::text) > 4000 then f := jsonb_build_object('truncated', true); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'export', 'report', p_key, jsonb_build_object('kind', lower(p_kind), 'rows', least(greatest(coalesce(p_rows, 0), 0), 100000000), 'filters', f));
end $$;

-- ---------- privileges ----------
revoke all on function public._r2_num(jsonb), public._r2_locs(jsonb), public._r2_def(text), public._r2_keys(), public._r2_dimlab(text), public._r2_ok(text),
  public.report_catalog2(), public.report_run2(text, jsonb, text, text, int), public.log_report_export2(text, text, jsonb, int) from public, anon, authenticated;
grant execute on function public.report_catalog2(), public.report_run2(text, jsonb, text, text, int), public.log_report_export2(text, text, jsonb, int) to authenticated;

notify pgrst, 'reload schema';

-- ===================== phase22.sql =====================
-- ============================================================
-- PHASE 22 (item master P1): bulk item editor + old-item decision tools. Additive and idempotent (paste twice = no error).
-- Needs phase14 (item master). Run after phase8..phase21.
--   1  grant item_bulk, rules items_hide_unpriced_in_pos (ON) and item_map_accept_min_conf (empty)
--   2  item_bulk_batches: one append-only audit row per applied batch
--   3  items_bulk_apply(changes, dry, batch, note): validates every row, dry-run writes nothing, owner / item_bulk / item_create apply at once,
--      others create item_changes requests; idempotent by client batch id; max 200 rows; cost only when the owner sends it
--   4  mapping decisions of the 57 old items: item_map_decide2 (link / keep / later / use_dict / undo), item_map_accept_confident
-- Nothing is deleted. Cost prices are never read or written here unless the owner sends cost_price in a row.
-- ============================================================

-- ---------- 1. grant and rules ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'item_bulk', 'master', 61, 'অনেক আইটেমের দাম / একক / স্টক একসাথে বদল (অনুমোদন ছাড়া)', 'অনেক item-এর দাম / unit / stock একসাথে বদল (approval ছাড়া)',
       'Change prices / units / stock settings of many items at once (no approval)', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'item_bulk');

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('items_hide_unpriced_in_pos', 'settings', 'switch', 'true', null, null, null, null, 'দাম ছাড়া আইটেম পিকারে দেখাবে না', 'দাম ছাড়া item picker-এ দেখাবে না', 'Hide items without a price from the pickers',
  'POS-এ দাম ছাড়া আইটেম কখনোই বিক্রি হয় না; এটি তালিকা ও পিকারে "দাম বাকি" আইটেম লুকাতে সাহায্য করে', 'POS never sells an item without a price; this keeps "Data needed" items out of the pickers', 70),
 ('item_map_accept_min_conf', 'settings', 'number', null, null, null, 0, 1, 'পুরনো আইটেম: "সব নিশ্চিত মিল মানুন"-এর সর্বনিম্ন মিল (০-১)', 'পুরনো item: "সব confident মিল মানুন"-এর minimum match (0-1)', 'Old items: minimum match (0-1) for "accept all high-confidence"',
  'ফাঁকা = শুধু যেগুলোকে আমদানির সময় নিশ্চিত (auto) ধরা হয়েছে', 'Empty = only the ones marked auto (high confidence) at import', 71)
 on conflict (key) do nothing;

-- ---------- 2. audit table ----------
create table if not exists public.item_bulk_batches (
  id bigserial primary key,
  client_batch text not null,
  created_by uuid not null, created_staff text,
  mode text not null check (mode in ('direct', 'requests')),
  note text,
  rows_n int not null, ok_n int not null default 0, requested_n int not null default 0, skipped_n int not null default 0, error_n int not null default 0,
  results jsonb not null default '[]',
  created_at timestamptz not null default now()
);
create unique index if not exists item_bulk_batches_client_uq on public.item_bulk_batches (created_by, client_batch);
alter table public.item_bulk_batches enable row level security;
drop policy if exists item_bulk_batches_read on public.item_bulk_batches;
create policy item_bulk_batches_read on public.item_bulk_batches for select to authenticated
  using (created_by = auth.uid() or public.is_owner() or public.has_grant('item_bulk'));
revoke all on public.item_bulk_batches from public, anon, authenticated;
grant select on public.item_bulk_batches to authenticated;

create or replace function public._append_only22() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end $$;
drop trigger if exists item_bulk_batches_ro on public.item_bulk_batches;
create trigger item_bulk_batches_ro before update or delete on public.item_bulk_batches for each row execute function public._append_only22();
drop trigger if exists item_bulk_batches_ro_t on public.item_bulk_batches;
create trigger item_bulk_batches_ro_t before truncate on public.item_bulk_batches for each statement execute function public._append_only22();

-- ---------- 3. bulk apply ----------
create or replace function public._bulk_bool(p jsonb) returns boolean language plpgsql immutable set search_path = public as $$
declare s text;
begin
  if p is null or p = 'null'::jsonb then return null; end if;
  if jsonb_typeof(p) = 'boolean' then return (p #>> '{}')::boolean; end if;
  s := lower(btrim(p #>> '{}'));
  if s in ('true', 'yes', 'y', '1', 'on', 'হ্যাঁ') then return true; end if;
  if s in ('false', 'no', 'n', '0', 'off', 'না') then return false; end if;
  raise exception 'bad_flag';
end $$;

create or replace function public._bulk_num(p jsonb, p_what text) returns numeric language plpgsql immutable set search_path = public as $$
declare s text := nullif(btrim(coalesce(p #>> '{}', '')), '');
begin
  if s is null then return null; end if;
  -- plain digits only: no sign, no exponent, no NaN / Infinity (a numeric can hold them)
  if s !~ '^[0-9]{1,10}(\.[0-9]{1,6})?$' or s::numeric > 1000000000 or not (s::numeric between 0 and 1000000000) then raise exception 'bad_price:%', p_what; end if;
  return s::numeric;
end $$;

create or replace function public.items_bulk_apply(p_changes jsonb, p_dry boolean default false, p_batch text default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); direct boolean; mode text; e jsonb; i int := 0; it public.items; patch jsonb; chg jsonb; res jsonb := '[]'::jsonb;
  st text; why text; n_ok int := 0; n_req int := 0; n_skip int := 0; n_err int := 0; seen uuid[] := '{}'; k text; num numeric; u text; b boolean; cur_cost numeric;
  sid text; ex public.item_bulk_batches; bid bigint; eff_count boolean; cname text;
begin
  if uid is null or not public.is_active() then raise exception 'not allowed'; end if;
  direct := public.is_owner() or public.has_grant('item_bulk') or public.has_grant('item_create');
  if not (direct or public.can_do('ITEMS', 'enter')) then raise exception 'not allowed'; end if;
  mode := case when direct then 'direct' else 'requests' end;
  if p_changes is null or jsonb_typeof(p_changes) <> 'array' or jsonb_array_length(p_changes) = 0 then raise exception 'bad_request'; end if;
  if jsonb_array_length(p_changes) > 200 then raise exception 'too_many_rows'; end if;
  if not coalesce(p_dry, false) then
    if nullif(btrim(coalesce(p_batch, '')), '') is null or length(p_batch) > 80 then raise exception 'batch_required'; end if;
    perform pg_advisory_xact_lock(hashtext('items_bulk:' || uid::text || ':' || p_batch));
    select * into ex from public.item_bulk_batches where created_by = uid and client_batch = p_batch;
    if found then
      return jsonb_build_object('dry', false, 'already', true, 'mode', ex.mode, 'batch', ex.client_batch, 'batch_id', ex.id, 'rows', ex.rows_n, 'ok', ex.ok_n, 'requested', ex.requested_n,
        'skipped', ex.skipped_n, 'error', ex.error_n, 'results', ex.results);
    end if;
  end if;
  select staff_id into sid from public.profiles where id = uid;

  for e in select x from jsonb_array_elements(p_changes) x loop
    i := i + 1; st := 'ok'; why := null; chg := '{}'::jsonb; patch := '{}'::jsonb; it := null;
    begin
      if jsonb_typeof(e) <> 'object' then raise exception 'bad_row'; end if;
      if nullif(btrim(coalesce(e->>'item_id', '')), '') is not null then
        if (e->>'item_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise exception 'item_not_found'; end if;
        select * into it from public.items where id = (e->>'item_id')::uuid;
      elsif nullif(btrim(coalesce(e->>'code', '')), '') is not null then
        select * into it from public.items where code = btrim(e->>'code');
      end if;
      if it.id is null then raise exception 'item_not_found'; end if;
      if it.id = any(seen) then raise exception 'duplicate_row'; end if;
      seen := seen || it.id;
      for k in select jsonb_object_keys(e) loop
        if k not in ('item_id', 'code', 'sell_price', 'wholesale_price', 'unit', 'tracked', 'min_stock', 'count_in_business', 'sellable', 'hidden', 'is_active', 'reason', 'name_bn', 'name_en', 'cost_price') then
          raise exception 'bad_field:%', k;
        end if;
      end loop;
      if it.locked then raise exception 'skip:locked'; end if;
      if exists (select 1 from public.item_map_actions a where a.action = 'use_dict' and (a.item_id = it.id or a.dict_code = it.code)
                 and not exists (select 1 from public.item_map_actions u where u.action = 'undo_use_dict' and u.ref_id = a.id)) then raise exception 'skip:replaced'; end if;
      eff_count := it.count_in_business;

      if e ? 'cost_price' and nullif(btrim(coalesce(e->>'cost_price', '')), '') is not null then      -- costs: owner only, explicit column
        if not public.is_owner() then raise exception 'cost_owner_only'; end if;
        num := public._bulk_num(e->'cost_price', 'cost');
        select cost_price into cur_cost from public.item_costs where item_id = it.id;
        if cur_cost is distinct from num then patch := patch || jsonb_build_object('cost_price', num::text); chg := chg || jsonb_build_object('cost_price', jsonb_build_array('(hidden)', '(hidden)')); end if;
      end if;
      if e ? 'sell_price' then num := public._bulk_num(e->'sell_price', 'sell');
        if num = 0 then raise exception 'bad_price:sell'; end if;                    -- a selling price of 0 is never set in bulk
        if num is not null and it.sell_price is distinct from num then patch := patch || jsonb_build_object('sell_price', num::text); chg := chg || jsonb_build_object('sell_price', jsonb_build_array(it.sell_price, num)); end if; end if;
      if e ? 'wholesale_price' then num := public._bulk_num(e->'wholesale_price', 'wholesale');
        if num is not null and it.wholesale_price is distinct from num then patch := patch || jsonb_build_object('wholesale_price', num::text); chg := chg || jsonb_build_object('wholesale_price', jsonb_build_array(it.wholesale_price, num)); end if; end if;
      if e ? 'min_stock' then num := public._bulk_num(e->'min_stock', 'min_stock');
        if num is not null and it.min_stock is distinct from num then patch := patch || jsonb_build_object('min_stock', num::text); chg := chg || jsonb_build_object('min_stock', jsonb_build_array(it.min_stock, num)); end if; end if;
      if e ? 'unit' and nullif(btrim(coalesce(e->>'unit', '')), '') is not null then
        u := coalesce(public._item_unit_code(btrim(e->>'unit')), btrim(e->>'unit'));
        if u not in ('kg', 'pc', 'lb') and not exists (select 1 from public.option_lists where list_code = 'units' and value_code = u and active) then raise exception 'bad_unit'; end if;
        if it.unit is distinct from u then patch := patch || jsonb_build_object('unit', u); chg := chg || jsonb_build_object('unit', jsonb_build_array(it.unit, u)); end if;
      end if;
      if e ? 'name_bn' and nullif(btrim(coalesce(e->>'name_bn', '')), '') is not null then
        if length(e->>'name_bn') > 200 then raise exception 'name_too_long'; end if;
        if it.name_bn is distinct from btrim(e->>'name_bn') then patch := patch || jsonb_build_object('name_bn', btrim(e->>'name_bn')); chg := chg || jsonb_build_object('name_bn', jsonb_build_array(it.name_bn, btrim(e->>'name_bn'))); end if;
      end if;
      if e ? 'name_en' and e->>'name_en' is not null then
        if length(e->>'name_en') > 200 then raise exception 'name_too_long'; end if;
        if it.name_en is distinct from nullif(btrim(e->>'name_en'), '') then patch := patch || jsonb_build_object('name_en', btrim(e->>'name_en')); chg := chg || jsonb_build_object('name_en', jsonb_build_array(it.name_en, nullif(btrim(e->>'name_en'), ''))); end if;
      end if;
      if e ? 'count_in_business' then b := public._bulk_bool(e->'count_in_business');
        if b is not null and b is distinct from it.count_in_business then
          if b and it.item_type = 'asset' then raise exception 'type_not_counted'; end if;
          if not b and exists (select 1 from public.stock_balance where item_id = it.id and qty <> 0) then raise exception 'item_has_stock'; end if;
          patch := patch || jsonb_build_object('count_in_business', b); chg := chg || jsonb_build_object('count_in_business', jsonb_build_array(it.count_in_business, b)); eff_count := b; end if; end if;
      if e ? 'tracked' then b := public._bulk_bool(e->'tracked');
        if b is not null and b is distinct from it.tracked then
          if b and not eff_count then raise exception 'tracked_needs_count'; end if;
          patch := patch || jsonb_build_object('tracked', b); chg := chg || jsonb_build_object('tracked', jsonb_build_array(it.tracked, b)); end if; end if;
      if e ? 'sellable' then b := public._bulk_bool(e->'sellable');
        if b is not null and b is distinct from it.sellable then
          if b and it.item_type in ('asset', 'raw_material') then raise exception 'type_not_sellable'; end if;
          patch := patch || jsonb_build_object('sellable', b); chg := chg || jsonb_build_object('sellable', jsonb_build_array(it.sellable, b)); end if; end if;
      if e ? 'hidden' then b := public._bulk_bool(e->'hidden');
        if b is not null and b is distinct from it.hidden then patch := patch || jsonb_build_object('hidden', b); chg := chg || jsonb_build_object('hidden', jsonb_build_array(it.hidden, b)); end if; end if;
      if e ? 'is_active' then b := public._bulk_bool(e->'is_active');
        if b is not null and b is distinct from it.is_active then
          if not b then
            if exists (select 1 from public.stock_balance where item_id = it.id and qty <> 0) then raise exception 'item_has_stock'; end if;
            if exists (select 1 from public.item_master_links l where l.active and (l.item_id = it.id or l.dict_code = it.code)) then raise exception 'item_linked'; end if;
          end if;
          patch := patch || jsonb_build_object('is_active', b); chg := chg || jsonb_build_object('is_active', jsonb_build_array(it.is_active, b));
          if not b then patch := patch || jsonb_build_object('retired_reason', left(coalesce(nullif(btrim(e->>'reason'), ''), nullif(btrim(p_note), ''), 'bulk'), 200)); end if;
        end if; end if;

      if patch = '{}'::jsonb then
        st := 'skipped'; why := 'nochange';
      elsif not coalesce(p_dry, false) then
        perform set_config('bos.item_apply', '1', true);
        if direct then
          perform public.apply_item_patch(it.id, patch);
          st := 'ok';
        else
          if patch ? 'cost_price' then raise exception 'cost_owner_only'; end if;
          perform public._item_patch_check(patch);
          insert into public.item_changes (item_id, patch, note, requested_by, requested_staff) values (it.id, patch, left(coalesce(p_note, 'bulk'), 300), uid, sid);
          st := 'requested';
        end if;
        perform set_config('bos.item_apply', '', true);
      else
        st := case when direct then 'ok' else 'requested' end;
      end if;
    exception when others then
      perform set_config('bos.item_apply', '', true);
      if sqlerrm like 'skip:%' then st := 'skipped'; why := substr(sqlerrm, 6);
      else st := 'error'; why := left(sqlerrm, 120); end if;
      chg := '{}'::jsonb;
    end;
    if st = 'ok' then n_ok := n_ok + 1; elsif st = 'requested' then n_req := n_req + 1; elsif st = 'skipped' then n_skip := n_skip + 1; else n_err := n_err + 1; end if;
    res := res || jsonb_build_array(jsonb_build_object('i', i, 'item_id', it.id, 'code', coalesce(it.code, e->>'code'), 'status', st, 'reason', why, 'changes', chg));
  end loop;

  if coalesce(p_dry, false) then
    return jsonb_build_object('dry', true, 'mode', mode, 'rows', i, 'ok', n_ok, 'requested', n_req, 'skipped', n_skip, 'error', n_err, 'results', res);
  end if;
  insert into public.item_bulk_batches (client_batch, created_by, created_staff, mode, note, rows_n, ok_n, requested_n, skipped_n, error_n, results)
    values (p_batch, uid, sid, mode, left(p_note, 300), i, n_ok, n_req, n_skip, n_err, res) returning id into bid;
  return jsonb_build_object('dry', false, 'already', false, 'mode', mode, 'batch', p_batch, 'batch_id', bid, 'rows', i, 'ok', n_ok, 'requested', n_req, 'skipped', n_skip, 'error', n_err, 'results', res);
end $$;
revoke all on function public.items_bulk_apply(jsonb, boolean, text, text), public._bulk_bool(jsonb), public._bulk_num(jsonb, text) from public, anon, authenticated;
grant execute on function public.items_bulk_apply(jsonb, boolean, text, text) to authenticated;

-- ---------- 4. old item decisions ----------
do $$ declare c text; begin
  select conname into c from pg_constraint where conrelid = 'public.item_mapping_review'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%status%';
  if c is not null and exists (select 1 from pg_constraint where conname = c and pg_get_constraintdef(oid) not like '%replaced%') then
    execute format('alter table public.item_mapping_review drop constraint %I', c);
    alter table public.item_mapping_review add constraint item_mapping_review_status_chk check (status in ('pending', 'linked', 'rejected', 'later', 'replaced'));
  end if;
end $$;

create table if not exists public.item_map_actions (
  id bigserial primary key,
  item_id uuid not null references public.items(id),             -- the old item
  dict_code text,
  action text not null check (action in ('link', 'keep', 'later', 'use_dict', 'undo_use_dict', 'undo', 'accept_all')),
  before jsonb not null default '{}', ref_id bigint, note text,
  created_by uuid, created_at timestamptz not null default now()
);
alter table public.item_map_actions enable row level security;
drop policy if exists item_map_actions_read on public.item_map_actions;
create policy item_map_actions_read on public.item_map_actions for select to authenticated using (public.is_owner() or public.has_grant('item_create'));
revoke all on public.item_map_actions from public, anon, authenticated;
grant select on public.item_map_actions to authenticated;
drop trigger if exists item_map_actions_ro on public.item_map_actions;
create trigger item_map_actions_ro before update or delete on public.item_map_actions for each row execute function public._append_only22();
drop trigger if exists item_map_actions_ro_t on public.item_map_actions;
create trigger item_map_actions_ro_t before truncate on public.item_map_actions for each statement execute function public._append_only22();

-- link / keep / later / use_dict / undo of ONE old item. 'use_dict' (copy price + unit to the dictionary item, retire the old item) is the owner's only.
create or replace function public.item_map_decide2(p_item uuid, p_action text, p_dict text default null, p_note text default null, p_force boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare lg public.items; dc public.items; rv public.item_mapping_review; act public.item_map_actions; aid bigint; f record; cur_status text; dstock boolean; bc_moved boolean := false;
begin
  if not (public.is_owner() or public.has_grant('item_create')) then raise exception 'not allowed'; end if;
  if p_action not in ('link', 'keep', 'later', 'use_dict', 'undo') then raise exception 'bad_request'; end if;
  select * into lg from public.items where id = p_item and import_batch is null;
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
end $$;

-- accept every suggestion that is high confidence: marked auto at import, or match >= rule item_map_accept_min_conf. p_dry = only count.
create or replace function public.item_map_accept_confident(p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
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
      n := n + 1; codes := codes || (select code from public.items where id = r.item_id);
    exception when others then skipped := skipped + 1;
    end;
  end loop;
  return jsonb_build_object('dry', coalesce(p_dry, true), 'accepted', n, 'skipped', skipped, 'codes', to_jsonb(codes));
end $$;
revoke all on function public.item_map_decide2(uuid, text, text, text, boolean), public.item_map_accept_confident(boolean), public._append_only22() from public, anon, authenticated;
grant execute on function public.item_map_decide2(uuid, text, text, text, boolean), public.item_map_accept_confident(boolean) to authenticated;

-- ---------- 5. a late offline sale of an item retired in the meantime ----------
-- record_sale2 refuses an inactive item. A sale made OFFLINE before the item was retired (sold_at older than 2 minutes, item changed after the sale) is accepted and flagged red
-- ('offline_sale_item_changed', the same exception phase14 raises for flag / price changes). Online sales of an inactive item stay refused. Text patch of the current definition
-- (not a rewrite), marker bos22-late; a second trigger sets the flag so phase14's own guard function is not replaced.
do $$
declare o oid; d text;
begin
  select p.oid into o from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'record_sale2' and p.prokind = 'f' limit 1;
  if o is not null then
    d := pg_get_functiondef(o);
    if position('bos22-late' in d) = 0 and position('if not found or not it.is_active then raise exception ''item_not_found''; end if;' in d) > 0 then
      d := replace(d, 'if not found or not it.is_active then raise exception ''item_not_found''; end if;',
        'if not found then raise exception ''item_not_found''; end if; /* bos22-late */ if not it.is_active and not (at_ < now() - interval ''2 minutes'' and it.updated_at > at_) then raise exception ''item_not_found''; end if;');
      execute d;
    end if;
  end if;
end $$;
create or replace function public._sale_item_guard22() returns trigger language plpgsql security definer set search_path = public as $$
declare ln jsonb; it public.items;
begin
  if new.lines is null or jsonb_typeof(new.lines) <> 'array' or new.sold_at >= now() - interval '2 minutes' then return new; end if;
  for ln in select x from jsonb_array_elements(new.lines) x where nullif(x->>'item_id', '') is not null loop
    select * into it from public.items where id = (ln->>'item_id')::uuid;
    if found and not it.is_active and it.updated_at > new.sold_at then perform set_config('bos.offline_item_changed', new.id::text, true); end if;
  end loop;
  return new;
end $$;
drop trigger if exists sales_item_guard22 on public.sales;
create trigger sales_item_guard22 before insert on public.sales for each row execute function public._sale_item_guard22();
revoke all on function public._sale_item_guard22() from public, anon, authenticated;

-- ===================== phase23.sql =====================
-- ============================================================
-- PHASE 23 (group A: wrong-number fixes). Additive and idempotent (paste twice = no error). Needs phase8..phase22.
--   A1  GRN (04-1) vs purchase page: only ONE of them adds bought goods to stock. Rule grn_receipt_source (purchase | grn, default purchase).
--       Cross-check function receipt_duplicates().
--   A2  Sales figures net of sale returns: biz_daily revenue minus returns (rule reports_net_of_returns, ON); sale_returns_summary(from).
--   A4  Day-book gaps: table cash_moves (bank deposit / withdraw, owner top-up / draw, customer advance in / refund / used, hub receipt)
--       with cash_move_add / cash_move_void / customer_advances(); the day book reads them (day_book re-created, one added union).
--   A5  Production void: production_void(run, note) reverses the ingredient-out and finished-good-in ledger rows.
-- Nothing is deleted. No cost price is exposed. Dry-run first: cash_move_add(..., p_dry := true) validates and writes nothing.
-- ============================================================

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('grn_receipt_source', 'stock', 'choice', '"purchase"', null, '["purchase","grn"]'::jsonb, null, null,
  'কেনা মাল স্টকে কোথা থেকে ওঠে: ক্রয় পেজ না GRN', 'কেনা মাল stock-এ কোথা থেকে ওঠে: Purchase page না GRN', 'Bought goods enter stock from: purchase page or GRN',
  'দুটোর একটাই স্টক বাড়ায়, যাতে দুবার না গোনা হয়। ডিফল্ট = ক্রয় পেজ; GRN ফর্মের "ইন" লাইন তখন বাদ পড়ে (কারণ: covered_by_purchase_page)।',
  'Only one of the two adds stock, so nothing is counted twice. Default = purchase page; GRN in-lines are then skipped (reason covered_by_purchase_page). Choose grn if you stop using the purchase page for stock.', 72),
 ('reports_net_of_returns', 'reports', 'switch', 'true', null, null, null, null,
  'বিক্রির হিসাব থেকে বিক্রি-ফেরত বাদ', 'বিক্রির হিসাব থেকে sale return বাদ', 'Sales figures are net of sale returns',
  'চালু = দৈনিক বিক্রি/মুনাফার রিপোর্টে ফেরত দেওয়া পণ্যের দাম ফেরতের দিনে বাদ যায়।',
  'On = daily sales/profit figures subtract the value of goods taken back, on the day of the return.', 73)
 on conflict (key) do nothing;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('ia_home_v2', 'ui', 'switch', 'true', null, null, null, null, 'নতুন হোম পেজ ও নিচের বার', 'নতুন Home page ও নিচের bar', 'New home page and bottom bar',
  'বন্ধ করলে সবাই আগের হোম পেজ ও মেনু দেখবে। চালু = নতুন বিন্যাস (ডিফল্ট)।', 'Off = everyone sees the old home page and menu. On = the new layout (default). A phone can also turn it off for itself.', 80),
 ('ui_collapsed_controls', 'ui', 'switch', 'true', null, null, null, null, 'ছোট করা অপশন (ড্রপডাউন / ⋮ মেনু)', 'ছোট করা option (dropdown / ⋮ menu)', 'Collapsed options (dropdowns / ⋮ menus)',
  'বন্ধ করলে সব অপশন আগের মতো খোলা বোতাম হয়ে দেখাবে।', 'Off = every option shows as open buttons again, as before.', 81)
 on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'cash_move', 'cash', 62, 'ব্যাংক জমা / মালিকের টাকা / অগ্রিম এন্ট্রি', 'Bank জমা / owner-এর টাকা / advance entry', 'Record bank deposits, owner top-ups and customer advances', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'cash_move');
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'production_void', 'stock', 63, 'উৎপাদন বাতিল', 'Production বাতিল', 'Void a production run', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'production_void');

-- ---------- A1 ----------
create or replace function public._elp_post_line(e public.entries, g int, sg text, l jsonb) returns void
language plpgsql security definer set search_path = public as $$
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
end $$;
-- biz_daily (A2)
create or replace function public.biz_daily(p_from date, p_to date, p_loc int default null)
returns table (sale_date date, location_id int, n bigint, revenue numeric, discount numeric,
               void_n bigint, void_amt numeric, costed_rev numeric, cogs numeric)
language plpgsql stable security definer set search_path = public as $$
declare cost_ok boolean := public.biz_cost_ok(); net_on boolean := coalesce(public.rule_on('reports_net_of_returns'), true);
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
  lc as (select l.*, c.cost_price from ln l left join (select ic.item_id, ic.cost_price from public.item_costs ic join public.items cbi on cbi.id = ic.item_id where cbi.count_in_business /* bos14 */) c on c.item_id = l.iid),
  ag as (
    select lc.sale_date, lc.location_id,
           sum(lc.amt * lc.f) filter (where lc.cost_price is not null) cr,
           sum(lc.qty * lc.cost_price) filter (where lc.cost_price is not null) cg
    from lc group by 1, 2),
  tot as (select ok.sale_date, ok.location_id, count(*) n, sum(ok.total) rev, sum(ok.discount) disc from ok group by 1, 2),
  vd as (select s.sale_date, s.location_id, count(*) vn, sum(s.total) va from s where s.status = 'void' group by 1, 2),
  rr as (select r.id, (r.created_at at time zone 'Asia/Dhaka')::date sale_date, r.location_id, r.amount from public.sale_returns r
         where net_on and r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to
           and (p_loc is null or r.location_id = p_loc) and r.location_id in (select l.id from public.locations l where public.can_loc(l.id))),
  rl as (select rr.id, rr.sale_date, rr.location_id, c.cost_price,
           case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'amount')::numeric end amt, case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end qty
         from rr join public.sale_returns r on r.id = rr.id, jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) e
         left join (select ic.item_id, ic.cost_price from public.item_costs ic join public.items cbi on cbi.id = ic.item_id where cbi.count_in_business /* bos14 */) c
           on c.item_id = (case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end)),
  rt as (select rr.sale_date, rr.location_id, sum(rr.amount) ra,
           (select sum(x.amt) filter (where x.cost_price is not null) from rl x where x.sale_date = rr.sale_date and x.location_id = rr.location_id) rcr,
           (select sum(x.qty * x.cost_price) filter (where x.cost_price is not null) from rl x where x.sale_date = rr.sale_date and x.location_id = rr.location_id) rcg
         from rr group by 1, 2),
  k as (select t.sale_date, t.location_id from tot t union select v.sale_date, v.location_id from vd v union select x.sale_date, x.location_id from rt x)
  select k.sale_date, k.location_id,
         coalesce(t.n, 0), coalesce(t.rev, 0) - coalesce(x.ra, 0), coalesce(t.disc, 0), coalesce(v.vn, 0), coalesce(v.va, 0),
         case when cost_ok then round(coalesce(a.cr, 0) - coalesce(x.rcr, 0), 2) end, case when cost_ok then round(coalesce(a.cg, 0) - coalesce(x.rcg, 0), 2) end
  from k
  left join tot t on t.sale_date = k.sale_date and t.location_id = k.location_id
  left join vd v on v.sale_date = k.sale_date and v.location_id = k.location_id
  left join rt x on x.sale_date = k.sale_date and x.location_id = k.location_id
  left join ag a on a.sale_date = k.sale_date and a.location_id = k.location_id
  order by 1, 2;
end $$;
create or replace function public.receipt_duplicates(p_days int default 3) returns table (item_id uuid, location_id int, purchase_ledger bigint, entry_ledger bigint, qty numeric, purchase_at timestamptz, entry_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  p_days := least(greatest(coalesce(p_days, 3), 0), 30);
  return query
    select a.item_id, a.location_id, a.id, b.id, a.qty_delta, a.created_at, b.created_at
      from public.stock_ledger a join public.stock_ledger b on b.item_id = a.item_id and b.location_id = a.location_id
       and b.reason = 'purchase_in' and b.ref_type = 'entry' and abs(b.qty_delta - a.qty_delta) <= a.qty_delta * 0.01
       and abs(extract(epoch from (b.created_at - a.created_at))) <= p_days * 86400
     where a.reason = 'purchase_in' and a.ref_type = 'purchase' and a.qty_delta > 0
       and not exists (select 1 from public.stock_ledger v where v.reverses_id = a.id) and not exists (select 1 from public.stock_ledger v where v.reverses_id = b.id)
     order by a.created_at desc limit 500;
end $$;
revoke all on function public.receipt_duplicates(int) from public, anon;
grant execute on function public.receipt_duplicates(int) to authenticated;

-- ---------- A2 ----------
create or replace function public.sale_returns_summary(p_from date) returns table (return_date date, location_id int, n bigint, amount numeric, refund numeric, credit numeric)
language sql stable security definer set search_path = public as $$
  select (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, count(*), sum(r.amount), sum(r.refund_amount), sum(r.credit_amount)
    from public.sale_returns r
   where r.status = 'done' and public.is_active() and public.can_loc(r.location_id) and (r.created_at at time zone 'Asia/Dhaka')::date >= p_from
     and (public.can_do('POS', 'view') or public.can_do('POS', 'enter') or public.has_grant('sale_return', r.location_id) or public.is_owner())
   group by 1, 2;
$$;
revoke all on function public.sale_returns_summary(date) from public, anon;
grant execute on function public.sale_returns_summary(date) to authenticated;


-- sales_summary: same columns; when reports_net_of_returns is ON, each day's sale returns come as an extra 'done' row (pay_mode 'return', n 0, negative total)
-- so every screen that adds the totals is automatically net.
create or replace function public.sales_summary(p_from date) returns table (sale_date date, location_id int, pay_mode text, status text, n bigint, total numeric, discount numeric, due numeric)
language sql stable set search_path = public as $$
  select s.sale_date, s.location_id, s.pay_mode, s.status, count(*), sum(s.total), sum(s.discount), sum(s.due_amount)
    from public.sales s where s.sale_date >= p_from group by 1, 2, 3, 4
  union all
  select (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, 'return'::text, 'done'::text, 0::bigint, -sum(r.amount), 0::numeric, 0::numeric
    from public.sale_returns r
   where public.rule_on('reports_net_of_returns') and r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date >= p_from
   group by 1, 2;
$$;
grant execute on function public.sales_summary(date) to authenticated;

-- ---------- A4 ----------
create table if not exists public.cash_moves (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  location_id int not null references public.locations(id),
  kind text not null check (kind in ('bank_deposit', 'bank_withdraw', 'owner_topup', 'owner_draw', 'cust_advance', 'cust_advance_refund', 'cust_advance_used', 'hub_receipt')),
  mode text check (mode is null or mode in ('cash', 'bank', 'mobile')),
  amount numeric not null check (amount >= 0.01 and amount <= 1000000000000),
  move_date date not null,
  customer_id uuid references public.customers(id),
  ref text, note text,
  status text not null default 'done' check (status in ('done', 'void')),
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  void_by uuid, void_at timestamptz, void_note text,
  check ((kind in ('bank_deposit', 'bank_withdraw', 'cust_advance_used') and mode is null) or (kind not in ('bank_deposit', 'bank_withdraw', 'cust_advance_used') and mode is not null)),
  check (kind not like 'cust_advance%' or customer_id is not null)
);
create index if not exists cash_moves_loc_date on public.cash_moves (location_id, move_date);
create index if not exists cash_moves_cust on public.cash_moves (customer_id) where status = 'done' and customer_id is not null;
drop trigger if exists audit_cash_moves on public.cash_moves;
create trigger audit_cash_moves after insert or update on public.cash_moves for each row execute function public.log_change('id');
alter table public.cash_moves enable row level security;
drop policy if exists cash_moves_read on public.cash_moves;
create policy cash_moves_read on public.cash_moves for select to authenticated
  using (public.can_loc(location_id) and (public.is_owner() or public.has_grant('cash_move', location_id) or public.has_grant('view_daybook', location_id)));
revoke all on public.cash_moves from public, anon, authenticated;
grant select on public.cash_moves to authenticated;

create or replace function public.cash_move_add(p_loc int, p_kind text, p_amount numeric, p_date date default null, p_mode text default null, p_customer uuid default null,
  p_ref text default null, p_note text default null, p_client uuid default null, p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
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
    if p_customer is null or not exists (select 1 from public.customers where id = p_customer) then raise exception 'customer_required'; end if;
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
  if p_dry then
    return jsonb_build_object('dry', true, 'kind', p_kind, 'mode', p_mode, 'amount', round(p_amount, 2), 'date', d, 'location_id', p_loc, 'customer_id', p_customer,
      'daybook', case p_kind when 'bank_deposit' then 'cash out, bank in' when 'bank_withdraw' then 'bank out, cash in' when 'owner_topup' then p_mode || ' in' when 'owner_draw' then p_mode || ' out'
                             when 'cust_advance' then p_mode || ' in' when 'cust_advance_refund' then p_mode || ' out' when 'hub_receipt' then 'cash in (internal)' else 'no money moves (advance used)' end);
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.cash_moves (id, client_id, location_id, kind, mode, amount, move_date, customer_id, ref, note, created_by, created_staff)
    values (id_, p_client, p_loc, p_kind, p_mode, round(p_amount, 2), d, p_customer, left(btrim(p_ref), 80), left(btrim(p_note), 300), auth.uid(), sid);
  return jsonb_build_object('id', id_, 'kind', p_kind, 'amount', round(p_amount, 2));
end $$;

create or replace function public.cash_move_void(p_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.cash_moves; bal numeric;
begin
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into r from public.cash_moves where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public.can_loc(r.location_id) or not (public.is_owner() or public.has_grant('cash_move', r.location_id)) then raise exception 'not allowed'; end if;
  if r.status = 'void' then return jsonb_build_object('id', r.id, 'status', 'void', 'dup', true); end if;
  perform public.lock_check(r.move_date);
  if r.customer_id is not null then perform pg_advisory_xact_lock(hashtext('adv:' || r.customer_id::text)); end if;
  if r.kind = 'cust_advance' then   -- cannot void an advance that was already refunded or used
    select coalesce(sum(case when kind = 'cust_advance' then amount else -amount end), 0) - r.amount into bal from public.cash_moves where customer_id = r.customer_id and status = 'done' and kind like 'cust_advance%';
    if bal < 0 then raise exception 'advance_already_used'; end if;
  end if;
  update public.cash_moves set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = r.id;
  return jsonb_build_object('id', r.id, 'status', 'void');
end $$;

create or replace function public.customer_advances() returns table (customer_id uuid, name text, mobile text, balance numeric, last_at date)
language sql stable security definer set search_path = public as $$
  select c.id, c.name, c.mobile, sum(case when m.kind = 'cust_advance' then m.amount else -m.amount end), max(m.move_date)
    from public.cash_moves m join public.customers c on c.id = m.customer_id
   where m.status = 'done' and m.kind like 'cust_advance%' and public.is_active() and public.can_loc(m.location_id) and (public.is_owner() or public.has_grant('cash_move', m.location_id) or public.has_grant('view_daybook', m.location_id))
   group by c.id, c.name, c.mobile having sum(case when m.kind = 'cust_advance' then m.amount else -m.amount end) <> 0;
$$;

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
   where m.status = 'done' and m.location_id = any (p_locs) and m.move_date between p_from and p_to;
$$;

-- ---------- A5 ----------
alter table public.production_runs add column if not exists status text not null default 'done';
alter table public.production_runs add column if not exists void_by uuid;
alter table public.production_runs add column if not exists void_at timestamptz;
alter table public.production_runs add column if not exists void_note text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'production_runs_status_chk') then
    alter table public.production_runs add constraint production_runs_status_chk check (status in ('done', 'void'));
  end if;
end $$;

create or replace function public.production_void(p_run uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare run public.production_runs; r record; b public.stock_batches; n int := 0;
begin
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into run from public.production_runs where id = p_run for update;
  if not found then raise exception 'not_found'; end if;
  if not public.can_loc(run.location_id) or not (public.is_owner() or public.has_grant('production_void', run.location_id)) then raise exception 'not allowed'; end if;
  if run.status = 'void' then return jsonb_build_object('id', run.id, 'status', 'void', 'dup', true); end if;
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
end $$;

revoke all on function public.cash_move_add(int, text, numeric, date, text, uuid, text, text, uuid, boolean), public.cash_move_void(uuid, text), public.customer_advances(),
  public._daybook_lines23(int[], date, date), public.production_void(uuid, text), public._elp_post_line(public.entries, int, text, jsonb) from public, anon;
revoke all on function public._daybook_lines23(int[], date, date), public._elp_post_line(public.entries, int, text, jsonb) from authenticated;
grant execute on function public.cash_move_add(int, text, numeric, date, text, uuid, text, text, uuid, boolean), public.cash_move_void(uuid, text), public.customer_advances(),
  public.production_void(uuid, text) to authenticated;

-- day_book re-created with the new union (A4)
create or replace function public.day_book(p_loc int, p_from date, p_to date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_locs int[]; v_sal int[]; v_start date; v_all boolean := (p_loc is null); v_to date; v_today date := (now() at time zone 'Asia/Dhaka')::date;
  v_days jsonb; v_tot jsonb; v_hidden boolean; v_mask boolean; v_known boolean; v_skipped int; v_allseen boolean;
  v_ob numeric[] := array[null, null, null]::numeric[]; v_base numeric[] := array[0, 0, 0]::numeric[]; v_bal boolean;
  v_netopen jsonb; v_netclose jsonb; v_open jsonb; v_close jsonb; v_i1 numeric; v_i2 numeric; v_i3 numeric; v_o1 numeric; v_o2 numeric; v_o3 numeric; v_n1 numeric; v_n2 numeric; v_n3 numeric; v_tr numeric;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_from in (date 'infinity', date '-infinity') or p_to in (date 'infinity', date '-infinity')
     or not (p_from between date '2000-01-01' and date '2100-01-01') or not (p_to between date '2000-01-01' and date '2100-01-01')
     or p_to < p_from or p_to - p_from + 1 > 366 then raise exception 'bad_range'; end if;
  if not public.is_owner() and not public.rule_on('daybook_enabled') then raise exception 'daybook_off'; end if;
  select array_agg(l.id) into v_locs from public.locations l
   where (p_loc is null or l.id = p_loc) and public.can_loc(l.id) and public.has_grant('view_daybook', l.id);
  if v_locs is null or (p_loc is not null and not (p_loc = any (v_locs))) then raise exception 'not allowed'; end if;
  select coalesce(array_agg(l), '{}') into v_sal from unnest(v_locs) l where public.has_grant('salary_view', l);
  v_hidden := cardinality(v_sal) < cardinality(v_locs);
  v_mask := (not public.is_owner()) and public.rule_on('daybook_mask_names');
  v_start := public._db_start();
  v_to := least(p_to, v_today);
  v_allseen := v_all and (select count(*) from public.locations) = cardinality(v_locs);
  v_ob := array[public.rule_num('daybook_open_cash'), public.rule_num('daybook_open_bank'), public.rule_num('daybook_open_mobile')];
  v_bal := v_allseen and v_ob[1] is not null and v_ob[2] is not null and v_ob[3] is not null;
  v_known := v_start is not null and v_to >= v_start;

  -- opening net: ONE aggregate over [start, p_from - 1] (only rows dated on/after the start date)
  if v_start is not null and v_start < p_from then
    select array[coalesce(sum(s) filter (where mode = 'cash'), 0), coalesce(sum(s) filter (where mode = 'bank'), 0), coalesce(sum(s) filter (where mode = 'mobile'), 0)] into v_base
      from (select u.mode, case when u.dir = 'in' then u.amount else -u.amount end as s
              from (select * from public._daybook_lines(v_locs, v_sal, v_start, p_from - 1) union all select * from public._daybook_lines12(v_locs, v_start, p_from - 1) union all select * from public._daybook_lines23(v_locs, v_start, p_from - 1)) u
             where not (u.internal and v_all)) z;
  end if;

  with rl as (select * from public._daybook_lines(v_locs, v_sal, p_from, v_to) union all select * from public._daybook_lines12(v_locs, p_from, v_to) union all select * from public._daybook_lines23(v_locs, p_from, v_to)),
  c as (select d, mode, case when dir = 'in' then amount else -amount end as s from rl where not (internal and v_all) and v_start is not null and d >= v_start),
  perday as (select d, sum(s) filter (where mode = 'cash') cash, sum(s) filter (where mode = 'bank') bank, sum(s) filter (where mode = 'mobile') mobile from c group by d),
  cum as (select d, coalesce(cash, 0) cash, coalesce(bank, 0) bank, coalesce(mobile, 0) mobile,
                 coalesce(sum(cash) over (order by d rows between unbounded preceding and 1 preceding), 0) + v_base[1] pc,
                 coalesce(sum(bank) over (order by d rows between unbounded preceding and 1 preceding), 0) + v_base[2] pb,
                 coalesce(sum(mobile) over (order by d rows between unbounded preceding and 1 preceding), 0) + v_base[3] pm from perday),
  x as (select t.d,
          coalesce(sum(t.amount) filter (where t.dir = 'in' and t.mode = 'cash' and not (t.internal and v_all)), 0) i_cash,
          coalesce(sum(t.amount) filter (where t.dir = 'in' and t.mode = 'bank' and not (t.internal and v_all)), 0) i_bank,
          coalesce(sum(t.amount) filter (where t.dir = 'in' and t.mode = 'mobile' and not (t.internal and v_all)), 0) i_mobile,
          coalesce(sum(t.amount) filter (where t.dir = 'out' and t.mode = 'cash' and not (t.internal and v_all)), 0) o_cash,
          coalesce(sum(t.amount) filter (where t.dir = 'out' and t.mode = 'bank' and not (t.internal and v_all)), 0) o_bank,
          coalesce(sum(t.amount) filter (where t.dir = 'out' and t.mode = 'mobile' and not (t.internal and v_all)), 0) o_mobile,
          coalesce(sum(t.amount) filter (where t.internal), 0) tr,
          jsonb_agg(jsonb_build_object('loc', t.loc, 'dir', t.dir, 'mode', t.mode, 'type', t.typ, 'amount', t.amount,
                    'ref', case when v_mask then null else t.ref end, 'text', case when v_mask then null else t.txt end, 'who', t.who,
                    'at', t.at, 'src', t.src, 'src_id', t.src_id, 'internal', t.internal, 'sensitive', t.sensitive) order by t.at, t.typ) lines
          from rl t group by t.d)
  select coalesce(jsonb_agg(jsonb_build_object(
      'date', x.d,
      'net_open', case when v_start is not null and x.d >= v_start then jsonb_build_object('cash', cm.pc, 'bank', cm.pb, 'mobile', cm.pm, 'total', cm.pc + cm.pb + cm.pm) end,
      'net_close', case when v_start is not null and x.d >= v_start then jsonb_build_object('cash', cm.pc + cm.cash, 'bank', cm.pb + cm.bank, 'mobile', cm.pm + cm.mobile, 'total', cm.pc + cm.pb + cm.pm + cm.cash + cm.bank + cm.mobile) end,
      'open', case when v_bal and x.d >= v_start then jsonb_build_object('cash', v_ob[1] + cm.pc, 'bank', v_ob[2] + cm.pb, 'mobile', v_ob[3] + cm.pm, 'total', v_ob[1] + v_ob[2] + v_ob[3] + cm.pc + cm.pb + cm.pm) end,
      'close', case when v_bal and x.d >= v_start then jsonb_build_object('cash', v_ob[1] + cm.pc + cm.cash, 'bank', v_ob[2] + cm.pb + cm.bank, 'mobile', v_ob[3] + cm.pm + cm.mobile,
                    'total', v_ob[1] + v_ob[2] + v_ob[3] + cm.pc + cm.pb + cm.pm + cm.cash + cm.bank + cm.mobile) end,
      'in', jsonb_build_object('cash', x.i_cash, 'bank', x.i_bank, 'mobile', x.i_mobile, 'total', x.i_cash + x.i_bank + x.i_mobile),
      'out', jsonb_build_object('cash', x.o_cash, 'bank', x.o_bank, 'mobile', x.o_mobile, 'total', x.o_cash + x.o_bank + x.o_mobile),
      'transfers', x.tr, 'lines', x.lines) order by x.d), '[]'::jsonb),
    coalesce(sum(x.i_cash), 0), coalesce(sum(x.i_bank), 0), coalesce(sum(x.i_mobile), 0), coalesce(sum(x.o_cash), 0), coalesce(sum(x.o_bank), 0), coalesce(sum(x.o_mobile), 0), coalesce(sum(x.tr), 0),
    coalesce(sum(x.i_cash - x.o_cash) filter (where v_start is not null and x.d >= v_start), 0), coalesce(sum(x.i_bank - x.o_bank) filter (where v_start is not null and x.d >= v_start), 0), coalesce(sum(x.i_mobile - x.o_mobile) filter (where v_start is not null and x.d >= v_start), 0)
    into v_days, v_i1, v_i2, v_i3, v_o1, v_o2, v_o3, v_tr, v_n1, v_n2, v_n3
    from x left join cum cm on cm.d = x.d;

  v_tot := jsonb_build_object(
    'in', jsonb_build_object('cash', v_i1, 'bank', v_i2, 'mobile', v_i3, 'total', v_i1 + v_i2 + v_i3),
    'out', jsonb_build_object('cash', v_o1, 'bank', v_o2, 'mobile', v_o3, 'total', v_o1 + v_o2 + v_o3), 'transfers', v_tr);
  if v_known then
    -- start of the range = running net before p_from (rows on/after the start date only); end = that + what happened in the range on/after the start date
    select jsonb_build_object('cash', v_base[1], 'bank', v_base[2], 'mobile', v_base[3], 'total', v_base[1] + v_base[2] + v_base[3]) into v_netopen;
    v_netclose := jsonb_build_object('cash', v_base[1] + v_n1, 'bank', v_base[2] + v_n2, 'mobile', v_base[3] + v_n3, 'total', v_base[1] + v_base[2] + v_base[3] + v_n1 + v_n2 + v_n3);
    v_tot := v_tot || jsonb_build_object('net_open', v_netopen, 'net_close', v_netclose);
    if v_bal then
      v_tot := v_tot || jsonb_build_object('open', jsonb_build_object('cash', v_ob[1] + v_base[1], 'bank', v_ob[2] + v_base[2], 'mobile', v_ob[3] + v_base[3], 'total', v_ob[1] + v_ob[2] + v_ob[3] + v_base[1] + v_base[2] + v_base[3]),
        'close', jsonb_build_object('cash', v_ob[1] + (v_netclose ->> 'cash')::numeric, 'bank', v_ob[2] + (v_netclose ->> 'bank')::numeric, 'mobile', v_ob[3] + (v_netclose ->> 'mobile')::numeric,
                                    'total', v_ob[1] + v_ob[2] + v_ob[3] + (v_netclose ->> 'total')::numeric));
    end if;
  end if;
  v_skipped := public._daybook_skipped(v_locs, v_sal, p_from, v_to);

  return jsonb_build_object('from', p_from, 'to', v_to, 'capped', p_to > v_today, 'loc', p_loc, 'start', v_start, 'opening_known', v_known, 'balances', v_bal,
    'enabled', public.rule_on('daybook_enabled'), 'salary_hidden', v_hidden, 'names_masked', v_mask, 'skipped_rows', v_skipped, 'days', v_days,
    'totals', v_tot || jsonb_build_object('net_open', coalesce(v_tot -> 'net_open', 'null'::jsonb), 'net_close', coalesce(v_tot -> 'net_close', 'null'::jsonb), 'open', coalesce(v_tot -> 'open', 'null'::jsonb), 'close', coalesce(v_tot -> 'close', 'null'::jsonb)),
    'notes', jsonb_build_array('card_as_bank', 'imprest_in_cash') || (case when exists (select 1 from public.cash_moves cm where cm.status = 'done' and cm.kind = 'hub_receipt' and cm.location_id = any (v_locs) and cm.move_date between p_from and v_to)
      then '[]'::jsonb else jsonb_build_array('hub_receipt_not_recorded') end) || jsonb_build_array('bank_deposit_not_dated') || jsonb_build_array('drafts_excluded', 'refunds_included', 'future_dates_capped'));
end $$;
revoke all on function public.day_book(int, date, date) from public, anon; grant execute on function public.day_book(int, date, date) to authenticated;

grant select (status, void_by, void_at, void_note) on public.production_runs to authenticated;

-- ============================================================
-- B2: blind count for the stock count sheet (04-3) and the goods received note (04-1). Needs phase18 (blind_count_on, blind_count_cfg).
--   04-3: the counter never sees (and the browser never sends) the book balance. count_lines_seal() takes the SERVER's balance of every counted item at that moment
--         and locks the counted figures; the book figure is written into the sheet only when it is submitted. Posting then uses that sealed book figure.
--   04-1: the counted figures are sealed first; only then does the screen show the memo figure. A sealed count cannot be changed through the entry.
--   Off by default (rule blind_count_on, per-form/location switch blind_count_cfg - same switches as phase18). Nothing changes while it is off.
-- ============================================================
create or replace function public.stock_blind_active(p_form text, p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select p_form in ('04-1', '04-3') and public.rule_on('blind_count_on')
     and coalesce((select enabled from public.blind_count_cfg where form_code = p_form and location_id = p_loc), true);
$$;

create table if not exists public.entry_count_seals (
  entry_id uuid not null references public.entries(id),
  line_no int not null check (line_no >= 1),
  form_code text not null,
  item_code text not null,
  counted numeric not null check (counted >= 0),
  book_base numeric,                       -- 04-3 only: the server balance (base unit) at the moment of sealing
  sealed_by uuid, sealed_at timestamptz not null default now(),
  primary key (entry_id, line_no)
);
alter table public.entry_count_seals enable row level security;
drop policy if exists entry_count_seals_read on public.entry_count_seals;
create policy entry_count_seals_read on public.entry_count_seals for select to authenticated
  using (exists (select 1 from public.entries e where e.id = entry_id and public.can_loc(e.location_id)
        and (public.is_owner() or e.status <> 'draft' or e.created_by is distinct from auth.uid() or public.has_grant('see_expected', e.location_id))));
revoke all on public.entry_count_seals from public, anon, authenticated;
grant select on public.entry_count_seals to authenticated;
create or replace function public._append_only23() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end $$;
drop trigger if exists entry_count_seals_ro on public.entry_count_seals;
create trigger entry_count_seals_ro before update or delete on public.entry_count_seals for each row execute function public._append_only23();
drop trigger if exists entry_count_seals_ro_t on public.entry_count_seals;
create trigger entry_count_seals_ro_t before truncate on public.entry_count_seals for each statement execute function public._append_only23();

create or replace function public.blind_cfg_set(p_form text, p_loc int, p_enabled boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_form not in ('14-1', '10-1', '04-3', '04-1') then raise exception 'form_not_supported'; end if;
  if p_enabled is null then raise exception 'bad_value'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'location_not_found'; end if;
  insert into public.blind_count_cfg (form_code, location_id, enabled, changed_by, changed_at) values (p_form, p_loc, p_enabled, auth.uid(), now())
    on conflict (form_code, location_id) do update set enabled = excluded.enabled, changed_by = excluded.changed_by, changed_at = excluded.changed_at;
  return jsonb_build_object('form', p_form, 'location_id', p_loc, 'enabled', p_enabled);
end $$;

create or replace function public.count_lines_state(p_entry uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.entries; k text; n int; s int;
begin
  select * into e from public.entries where id = p_entry;
  if not found or not public.can_loc(e.location_id) then raise exception 'not allowed'; end if;
  if not public.stock_blind_active(e.form_code, e.location_id) then return jsonb_build_object('blind', false); end if;
  k := case e.form_code when '04-3' then 'rows' else 'lines' end;
  select count(*) into n from jsonb_array_elements(case when jsonb_typeof(e.data -> k) = 'array' then e.data -> k else '[]'::jsonb end) r where nullif(btrim(r ->> 'item'), '') is not null;
  select count(*) into s from public.entry_count_seals where entry_id = e.id;
  return jsonb_build_object('blind', true, 'rows', n, 'sealed', s, 'all_sealed', n > 0 and s >= n);
end $$;

create or replace function public.count_lines_seal(p_entry uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
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
      select * into it from public.items where code = btrim(r ->> 'item');
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
end $$;

create or replace function public._entries_countseal_guard23() returns trigger
language plpgsql security definer set search_path = public as $$
declare k text; cf text; s record; r jsonb; n int; arr jsonb := '[]'::jsonb; it public.items; iid uuid; f numeric; bk numeric;
begin
  if new.form_code not in ('04-1', '04-3') or not public.stock_blind_active(new.form_code, new.location_id) then return new; end if;
  k := case new.form_code when '04-3' then 'rows' else 'lines' end; cf := case new.form_code when '04-3' then 'count' else 'counted' end;
  if tg_op = 'UPDATE' then
    for s in select * from public.entry_count_seals where entry_id = new.id loop
      r := case when jsonb_typeof(new.data -> k) = 'array' then new.data -> k -> (s.line_no - 1) end;
      if r is null or btrim(coalesce(r ->> 'item', '')) <> s.item_code or public._n18(r, cf) <> s.counted then raise exception 'count_locked'; end if;
    end loop;
    if old.status = 'draft' and new.status <> 'draft' then
      for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(new.data -> k) = 'array' then new.data -> k else '[]'::jsonb end) with ordinality x(v, o) loop
        if nullif(btrim(r ->> 'item'), '') is not null and not exists (select 1 from public.entry_count_seals where entry_id = new.id and line_no = n) then raise exception 'count_not_sealed'; end if;
      end loop;
    end if;
  end if;
  if new.form_code = '04-3' and jsonb_typeof(new.data -> k) = 'array' then
    for r, n in select x.v, x.o::int from jsonb_array_elements(new.data -> k) with ordinality x(v, o) loop
      r := case when jsonb_typeof(r) = 'object' then r - 'book' else r end;
      if tg_op = 'UPDATE' and new.status <> 'draft' and jsonb_typeof(r) = 'object' then
        select sl.book_base, i.id into bk, iid from public.entry_count_seals sl left join public.items i on i.code = sl.item_code where sl.entry_id = new.id and sl.line_no = n;
        if found and bk is not null then
          select * into it from public.items where id = iid;
          f := public._unit_factor_base(it.id, it.unit);
          if f is not null and f > 0 then r := r || jsonb_build_object('book', round(bk / f, 4)::text); end if;
        end if;
      end if;
      arr := arr || jsonb_build_array(r);
    end loop;
    new.data := jsonb_set(new.data, array[k], arr);
  end if;
  return new;
end $$;
drop trigger if exists entries_countseal_guard23 on public.entries;
drop trigger if exists entries_zcountseal_guard23 on public.entries;   -- named to sort AFTER entries_sig_guard: the PIN hash is taken before the server book figure is added
create trigger entries_zcountseal_guard23 before insert or update on public.entries for each row execute function public._entries_countseal_guard23();

revoke all on function public.stock_blind_active(text, int), public.count_lines_state(uuid), public.count_lines_seal(uuid), public._entries_countseal_guard23(), public._append_only23() from public, anon;
revoke all on function public._entries_countseal_guard23(), public._append_only23() from authenticated;
grant execute on function public.stock_blind_active(text, int), public.count_lines_state(uuid), public.count_lines_seal(uuid) to authenticated;

-- ============================================================
-- B3: PIN signature (witness) also on the stock count sheet 04-3. Same switch (pin_signature_on) and per-form switch (pin_sig_cfg).
-- ============================================================
create or replace function public.pin_sig_active(p_form text) returns boolean
language sql stable security definer set search_path = public as $$
  select p_form in ('14-1', '10-1', '04-3') and public.rule_on('pin_signature_on')
     and coalesce((select enabled from public.pin_sig_cfg where form_code = p_form), true);
$$;
create or replace function public.pin_sig_cfg_set(p_form text, p_enabled boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_form not in ('14-1', '10-1', '04-3') then raise exception 'form_not_supported'; end if;
  if p_enabled is null then raise exception 'bad_value'; end if;
  insert into public.pin_sig_cfg (form_code, enabled, changed_by, changed_at) values (p_form, p_enabled, auth.uid(), now())
    on conflict (form_code) do update set enabled = excluded.enabled, changed_by = excluded.changed_by, changed_at = excluded.changed_at;
  return jsonb_build_object('form', p_form, 'enabled', p_enabled);
end $$;
create or replace function public.sign_entry(p_entry uuid, p_role text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text; iat numeric; h text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into e from public.entries where id = p_entry for update;
  -- place first, one text for every refusal of access (no hint whether the entry exists)
  if not found or not public.can_loc(e.location_id) or not (public.can_do(e.form_code, 'enter') or public.can_do(e.form_code, 'approve')) then raise exception 'not allowed'; end if;
  if p_role not in ('witness', 'second_sig', 'hub_pair') then raise exception 'bad_role'; end if;
  if (p_role = 'witness' and e.form_code not in ('14-1', '04-3')) or (p_role = 'second_sig' and e.form_code <> '14-1') or (p_role = 'hub_pair' and e.form_code <> '10-1') then raise exception 'bad_role'; end if;   -- phase 23: the stock count sheet (04-3) has a witness too
  if not public.pin_sig_active(e.form_code) then raise exception 'pin_signature_off'; end if;
  if e.status not in ('draft', 'submitted') then raise exception 'entry is locked'; end if;
  if e.created_by = auth.uid() then raise exception 'signer_is_maker'; end if;
  -- a fresh sign-in just now (the browser signs the signer in on a second client): an old token cannot sign
  begin iat := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'iat', nullif(current_setting('request.jwt.claim.iat', true), ''))::numeric; exception when others then iat := null; end;
  if iat is null or iat < extract(epoch from now()) - 120 then raise exception 'login_not_fresh'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if exists (select 1 from public.login_failures f where f.staff_id = sid and f.locked and (f.locked_until is null or f.locked_until > now())) then raise exception 'signer_locked'; end if;
  h := public._sig_hash18(e.data);
  if exists (select 1 from public.entry_signatures where entry_id = p_entry and signer_id = auth.uid() and data_hash = h) then raise exception 'signer_already_signed'; end if;
  if exists (select 1 from public.entry_signatures where entry_id = p_entry and role = p_role and data_hash = h) then raise exception 'role_already_signed'; end if;
  insert into public.entry_signatures (entry_id, role, signer_id, signer_staff, data_hash) values (p_entry, p_role, auth.uid(), sid, h);
  return jsonb_build_object('entry', p_entry, 'role', p_role, 'signer_staff', sid);
end $$;
create or replace function public._entries_sig_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare roles text[]; r text; s text; h text; missing text[] := '{}';
begin
  if not (old.status = 'draft' and new.status = 'submitted') then return new; end if;
  if not public.pin_sig_active(new.form_code) then return new; end if;
  roles := case new.form_code when '14-1' then array['witness', 'second_sig'] when '04-3' then array['witness'] else array['hub_pair'] end;
  h := public._sig_hash18(new.data);
  foreach r in array roles loop
    select signer_staff into s from public.entry_signatures where entry_id = new.id and role = r and data_hash = h order by id desc limit 1;
    if s is null then
      missing := missing || r;
      continue;
    end if;
    if r = 'witness' and coalesce(new.data ->> 'witness', '') <> s then raise exception 'signature_mismatch:witness'; end if;
    if r = 'second_sig' and coalesce(new.data ->> 'second_sig', '') <> s then raise exception 'signature_mismatch:second_sig'; end if;
  end loop;
  if array_length(missing, 1) > 0 then
    if new.entered_later then
      new.flags := public._addflag18(new.flags, 'unsigned_entered_later', 'yellow', 'কাগজ থেকে পরে তোলা — পিন স্বাক্ষর নেই', 'Entered later from paper - no PIN signature');
    elsif public.is_owner() and public.rule_on('pin_signature_owner_override') then
      new.flags := public._addflag18(new.flags, 'unsigned_owner_override', 'yellow', 'মালিকের ছাড়ে পিন স্বাক্ষর ছাড়া জমা', 'Submitted without PIN signatures by the owner override');
    else
      r := missing[1];
      if exists (select 1 from public.entry_signatures where entry_id = new.id and role = r) then raise exception 'pin_signature_stale:%', r; end if;
      raise exception 'pin_signature_required:%', r;
    end if;
  end if;
  return new;
end $$;

-- ===================== phase24.sql =====================
-- ============================================================
-- PHASE 24 (group C): report engine 3 = a registry of reports (table report_defs3) + one function per report
--   _r3q_<key>(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb   (one jsonb object per row, keys = the column keys; private: nobody may call it directly)
--   report_run3(key, filters, group, sort, page) does access, locations, dates, sort, paging, totals - same answer shape as report_run2, so the reports hub shows them with no new screen.
--   report_catalog2 / report_run2 / log_report_export2 are wrapped: a key that is in report_defs3 goes to engine 3, every other key to the old code (renamed *_core).
-- Needs phase21. Run in order after it (do not paste phase21 again afterwards). Additive and idempotent. Costs only for cost-right holders; owner-only reports stay owner-only.
-- ============================================================
create table if not exists public.report_defs3 (
  key text primary key check (key ~ '^[a-z0-9_]{2,40}$'),
  code text,                                   -- number in docs/plan_v2/REPORTS.md (S10, P2 ...)
  grp text not null,                           -- access group: report_<grp> grant (or view_reports)
  name_bn text not null, name_en text not null, name_mix text,
  cols jsonb not null,                         -- [[key, label_bn, label_en, type]]  type: text | id | date | int | num | money | pct
  tot text[] not null default '{}',            -- column keys summed into the totals
  sort_key text, sort_dir text not null default 'desc',
  allow text[] not null default array['locations'],
  nodate boolean not null default false, cost boolean not null default false, owner_only boolean not null default false,
  sort int not null default 0, is_active boolean not null default true
);
alter table public.report_defs3 enable row level security;
drop policy if exists report_defs3_read on public.report_defs3;
create policy report_defs3_read on public.report_defs3 for select to authenticated using (public.is_active());
revoke all on public.report_defs3 from public, anon, authenticated;
grant select on public.report_defs3 to authenticated;

do $$
declare r record;
begin
  for r in select * from (values
    ('report_profit',    69, 'রিপোর্ট: লাভ-ক্ষতি', 'Report: Profit & loss', 'Reports: Profit and loss'),
    ('report_quality',   70, 'রিপোর্ট: মান ও পরিচ্ছন্নতা', 'Report: Quality & hygiene', 'Reports: Quality and hygiene'),
    ('report_marketing', 71, 'রিপোর্ট: মার্কেটিং', 'Report: Marketing', 'Reports: Marketing'),
    ('report_orders',    72, 'রিপোর্ট: অর্ডার ও ডেলিভারি', 'Report: Orders & delivery', 'Reports: Orders and delivery')) v(code, sort, bn, mix, en)
  loop
    if not exists (select 1 from public.grant_defs where grant_code = r.code) then
      insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values (r.code, 'reports', r.sort, r.bn, r.mix, r.en, 'once', null);
    end if;
  end loop;
end $$;

create or replace function public._r3_ok(d public.report_defs3) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return d.is_active and public.rpt_access(d.grp) and (not d.cost or public.rpt_cost_ok()) and (not d.owner_only or public.is_owner());
end $$;

create or replace function public.report_catalog3() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d public.report_defs3; out_ jsonb := '[]'::jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  for d in select * from public.report_defs3 where is_active order by sort, key loop
    out_ := out_ || jsonb_build_array(jsonb_build_object('key', d.key, 'code', d.code, 'group', d.grp, 'grant', 'report_' || d.grp, 'allowed', public._r3_ok(d), 'kind', 'raw', 'engine', 2,
      'name_bn', d.name_bn, 'name_en', d.name_en, 'name_mix', coalesce(d.name_mix, d.name_bn),
      'filters', to_jsonb(case when d.nodate then '{}'::text[] else array['date'] end || d.allow),
      'dims', '[]'::jsonb, 'default_group', null, 'columns', '[]'::jsonb, 'compare', false, 'needs_date', not d.nodate, 'cost_only', d.cost));
  end loop;
  return out_;
end $$;

create or replace function public.report_run3(p_key text, p_filters jsonb default '{}'::jsonb, p_group text default null, p_sort text default null, p_page int default 1) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  d public.report_defs3; flt jsonb; notes jsonb := '[]'::jsonb; today date := (now() at time zone 'Asia/Dhaka')::date; eff int[]; d1 date; d2 date; pr jsonb; preset text;
  pgsize int; pg int := least(greatest(coalesce(p_page, 1), 1), 1000); off int; lim int; cap constant int := 500; c jsonb; outc jsonb := '[]'::jsonb; keys text[] := '{}'; types jsonb := '{}'::jsonb;
  sk text; sd text; sraw text; sparts text[]; ordr text; rows_ jsonb; totals_ jsonb; ng bigint := 0; hm boolean; dn boolean := false; fn text; k text; targs text := ''; g text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into d from public.report_defs3 where key = p_key and is_active;
  if not found then raise exception 'unknown_report'; end if;
  if not public._r3_ok(d) then raise exception 'not allowed'; end if;
  fn := '_r3q_' || d.key;
  flt := case when p_filters is not null and jsonb_typeof(p_filters) = 'object' then p_filters else '{}'::jsonb end;
  for c in select jsonb_array_elements(d.cols) loop
    outc := outc || jsonb_build_array(jsonb_build_object('key', c ->> 0, 'label_bn', c ->> 1, 'label_en', c ->> 2, 'type', c ->> 3,
      'role', case when c ->> 3 in ('money', 'int', 'num', 'pct') then 'measure' else 'dim' end, 'cost', d.cost));
    keys := keys || (c ->> 0); types := types || jsonb_build_object(c ->> 0, c ->> 3);
  end loop;
  if to_regprocedure('public.' || fn || '(date,date,int[],jsonb)') is null then
    return jsonb_build_object('report', p_key, 'columns', outc, 'rows', '[]'::jsonb, 'totals', null, 'compare', null, 'has_more', false, 'data_needed', true,
      'page', jsonb_build_object('n', pg, 'size', 0, 'groups', 0, 'cap', cap), 'notes', jsonb_build_array(jsonb_build_object('code', 'data_needed', 'text_en', 'This report is not installed yet', 'text_bn', 'এই রিপোর্ট এখনও বসানো হয়নি')));
  end if;
  eff := public._r2_locs(flt);
  if cardinality(eff) = 0 then notes := notes || jsonb_build_array(jsonb_build_object('code', 'no_location', 'text_en', 'No location is open to you', 'text_bn', 'কোনো লোকেশন আপনার জন্য খোলা নেই')); end if;
  pgsize := least(greatest(coalesce(public.rule_num('report_page_size'), 50), 10), 200)::int;
  off := (pg - 1) * pgsize; lim := greatest(least(pgsize, cap - off), 0);
  for g in select jsonb_object_keys(flt) loop
    if g in ('from', 'to', 'preset', 'compare_mode') or jsonb_typeof(flt -> g) = 'null' then continue; end if;
    if not (g = any (d.allow)) then notes := notes || jsonb_build_array(jsonb_build_object('code', 'filter_ignored', 'what', left(g, 40))); end if;
  end loop;
  if not d.nodate then
    preset := flt ->> 'preset';
    if preset is not null then
      pr := public.report_presets() -> preset;
      if pr is null or jsonb_typeof(pr) = 'null' then
        return jsonb_build_object('report', p_key, 'columns', outc, 'rows', '[]'::jsonb, 'totals', null, 'compare', null, 'has_more', false, 'data_needed', true,
          'page', jsonb_build_object('n', pg, 'size', pgsize, 'groups', 0, 'cap', cap), 'notes', jsonb_build_array(jsonb_build_object('code', 'data_needed', 'what', left(preset, 30), 'text_en', 'Unknown date preset', 'text_bn', 'তারিখের প্রিসেটের নাম ভুল')));
      end if;
      d1 := (pr ->> 'from')::date; d2 := (pr ->> 'to')::date;
    else
      d1 := public.rpt_date(flt ->> 'from'); d2 := public.rpt_date(flt ->> 'to');
      if d1 is null and d2 is null then d1 := date_trunc('month', today)::date; d2 := today;
        notes := notes || jsonb_build_array(jsonb_build_object('code', 'default_period', 'text_en', 'No period given: this month to date', 'text_bn', 'সময় দেওয়া হয়নি: এই মাসের শুরু থেকে আজ পর্যন্ত'));
      elsif d1 is null then d1 := d2; elsif d2 is null then d2 := today; end if;
    end if;
    if d2 < d1 or d2 - d1 > 365 then raise exception 'bad_range'; end if;
  else d1 := today; d2 := today;
  end if;
  sraw := lower(btrim(coalesce(p_sort, '')));
  if sraw <> '' then
    if left(sraw, 1) = '-' then sd := 'desc'; sraw := substr(sraw, 2); end if;
    sparts := regexp_split_to_array(sraw, '[: ]+');
    if sparts[1] = any (keys) then sk := sparts[1]; sd := coalesce(sd, case when sparts[2] = 'desc' then 'desc' else 'asc' end);
    else notes := notes || jsonb_build_array(jsonb_build_object('code', 'sort_ignored', 'what', left(sparts[1], 30))); end if;
  end if;
  if sk is null then
    if d.sort_key is not null and d.sort_key = any (keys) then sk := d.sort_key; sd := d.sort_dir;
    else sk := coalesce((select c2 ->> 0 from jsonb_array_elements(d.cols) c2 where c2 ->> 3 <> 'id' limit 1), keys[1]); sd := 'asc'; end if;
  end if;
  ordr := case when types ->> sk in ('money', 'int', 'num', 'pct') then format('(r ->> %L)::numeric', sk) else format('r ->> %L', sk) end || ' ' || case when sd = 'desc' then 'desc' else 'asc' end || ' nulls last';
  execute format('select coalesce(jsonb_agg(x.r order by x.rn), ''[]''::jsonb), coalesce(max(x.n), 0) from (select r, count(*) over () as n, row_number() over (order by %s) as rn from public.%I($1, $2, $3, $4) r order by %s limit %s offset %s) x',
    ordr, fn, ordr, lim, off) into rows_, ng using d1, d2, eff, flt;
  if cardinality(d.tot) > 0 then
    foreach k in array d.tot loop targs := targs || format('%L, round(coalesce(sum((r ->> %L)::numeric), 0), 4), ', k, k); end loop;
    execute format('select jsonb_build_object(%s) from public.%I($1, $2, $3, $4) r', left(targs, length(targs) - 2), fn) into totals_ using d1, d2, eff, flt;
  end if;
  hm := (off + pgsize) < least(ng, cap);
  if ng > cap then notes := notes || jsonb_build_array(jsonb_build_object('code', 'truncated', 'cap', cap, 'groups', ng)); end if;
  if jsonb_array_length(rows_) = 0 or ng = 0 then
    dn := true; notes := notes || jsonb_build_array(jsonb_build_object('code', 'no_data', 'text_en', 'Data needed: nothing matches this period / filters', 'text_bn', 'তথ্য দরকার: এই সময়/ফিল্টারে কিছু নেই'));
  end if;
  return jsonb_build_object('report', p_key, 'columns', outc, 'rows', rows_, 'totals', totals_, 'compare', null,
    'page', jsonb_build_object('n', pg, 'size', pgsize, 'groups', ng, 'cap', cap), 'has_more', coalesce(hm, false), 'notes', notes, 'data_needed', dn,
    'meta', jsonb_build_object('from', d1, 'to', d2, 'group', '[]'::jsonb, 'sort', sk, 'dir', sd, 'cost_shown', public.rpt_cost_ok(), 'today', today));
end $$;

-- ---------- wrap the engine-2 entry points (renamed once; a re-run keeps the wrappers) ----------
do $$ begin
  if to_regprocedure('public.report_run2_core(text,jsonb,text,text,int)') is null then alter function public.report_run2(text, jsonb, text, text, int) rename to report_run2_core; end if;
  if to_regprocedure('public.report_catalog2_core()') is null then alter function public.report_catalog2() rename to report_catalog2_core; end if;
end $$;
revoke all on function public.report_run2_core(text, jsonb, text, text, int), public.report_catalog2_core() from public, anon, authenticated;

create or replace function public.report_run2(p_key text, p_filters jsonb default '{}'::jsonb, p_group text default null, p_sort text default null, p_page int default 1) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if exists (select 1 from public.report_defs3 where key = p_key and is_active) then return public.report_run3(p_key, p_filters, p_group, p_sort, p_page); end if;
  return public.report_run2_core(p_key, p_filters, p_group, p_sort, p_page);
end $$;
create or replace function public.report_catalog2() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  return public.report_catalog2_core() || public.report_catalog3();
end $$;

create or replace function public.log_report_export2(p_key text, p_kind text, p_filters jsonb, p_rows int) returns void
language plpgsql security definer set search_path = public as $$
declare sid text; f jsonb := coalesce(p_filters, '{}'::jsonb);
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_grant('export_data')) then raise exception 'not allowed'; end if;
  if p_key is null or not (p_key = any (public._r2_keys()) or exists (select 1 from public.report_defs3 d where d.key = p_key and d.is_active)) then raise exception 'unknown_report'; end if;
  if p_kind is null or lower(p_kind) !~ '^[a-z0-9_]{1,20}$' then raise exception 'bad_kind'; end if;
  if length(f::text) > 4000 then f := jsonb_build_object('truncated', true); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'export', 'report', p_key, jsonb_build_object('kind', lower(p_kind), 'rows', least(greatest(coalesce(p_rows, 0), 0), 100000000), 'filters', f));
end $$;

-- every _r3q_* report function is private (they run as definer and do no access checks of their own): report files end with  select public._r3_lockdown();
create or replace function public._r3_lockdown() returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in select p.oid::regprocedure::text as sig from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like '\_r3q\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig); n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public._r3_lockdown() from public, anon, authenticated;

revoke all on function public.report_run3(text, jsonb, text, text, int), public.report_catalog3(), public._r3_ok(public.report_defs3), public.report_run2(text, jsonb, text, text, int), public.report_catalog2(), public.log_report_export2(text, text, jsonb, int) from public, anon;
grant execute on function public.report_run3(text, jsonb, text, text, int), public.report_catalog3(), public.report_run2(text, jsonb, text, text, int), public.report_catalog2(), public.log_report_export2(text, text, jsonb, int) to authenticated;
revoke all on function public._r3_ok(public.report_defs3) from authenticated;
notify pgrst, 'reload schema';

-- ===================== phase25.sql =====================
-- ============================================================
-- PHASE 25 (report builder 25): reports on engine 3 (needs phase24; read-only, additive, paste-twice safe)
--   s10_orders  S10  orders / online / delivery            (20-1, 20-6)
--   d5_lapsed   D5   lapsed customers, new vs repeat       (sales)
--   m1_rfm      M1   RFM customer segments                 (sales)
--   x2_bypass   X2   releases / emergency / grant use      (release_requests, emergency_requests)
--   x3_audit_log X3  audit & correction log (owner only)   (audit_log)
--   x4_compliance X4 form submission compliance            (entries 14-1, 10-1)
--   x5_staff_trend X5 staff indicators, monthly            (sales, same logic as biz_staff)
--   g2_paper_numbers G2 duplicate / out-of-order paper no. (entries.data.paper_no)
--   k3_store_ledger K3 store ledger per item and kind      (stock_ledger; quantities only)
--   e2_expense_trend E2 expense trend vs previous period   (10-2)
--   e3_weak_control E3 no-receipt / over-limit / imprest   (10-2, 14-1)
--   e4_marketing_limit E4 marketing spend vs head limit    (18-1, option_lists, location_settings)
--   w1_cash_flow W1  daily cash flow per location          (_daybook_lines*)
--   w2_handover_vs_hub W2 handover (10-1) vs hub count     (10-1, entry_counts, check_data)
-- ============================================================

-- ---------- S10 orders, online & delivery ----------
create or replace function public._r3q_s10_orders(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('source', '20-1', 'channel', x.channel, 'online', x.online, 'delivery', x.delivery, 'orders', count(*),
      'amount', coalesce(sum(x.total), 0), 'advance', coalesce(sum(x.adv), 0), 'balance', coalesce(sum(x.total - x.disc - x.adv), 0),
      'handed', count(*) filter (where x.signed), 'not_collected', count(*) filter (where x.nc), 'returned', null, 'delivery_charge', null)
    from (select coalesce(nullif(btrim(e.data ->> 'channel'), ''), '-') as channel, coalesce(nullif(btrim(e.data ->> 'online'), ''), '-') as online,
                 coalesce(nullif(btrim(e.data ->> 'deliv_by'), ''), '-') as delivery,
                 coalesce(public._r2_num(e.data -> 'total'), 0) as total, coalesce(public._r2_num(e.data -> 'discount'), 0) as disc, coalesce(public._r2_num(e.data -> 'advance'), 0) as adv,
                 (e.data ->> 'cust_signed') = 'true' as signed, (e.data ->> 'not_collected') = 'true' as nc
            from public.entries e
           where e.form_code = '20-1' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)) x
   group by x.channel, x.online, x.delivery
  union all
  select jsonb_build_object('source', '20-6', 'channel', 'ledger', 'online', y.platform, 'delivery', y.delivery, 'orders', count(*),
      'amount', coalesce(sum(y.amt), 0), 'advance', null, 'balance', null,
      'handed', count(*) filter (where y.outcome = 'handed'), 'not_collected', null, 'returned', count(*) filter (where y.outcome = 'returned'),
      'delivery_charge', coalesce(sum(y.dch), 0))
    from (select coalesce(nullif(lower(btrim(l ->> 'platform')), ''), '-') as platform, coalesce(nullif(btrim(l ->> 'delivery'), ''), '-') as delivery,
                 public._r2_num(l -> 'amt') as amt, public._r2_num(l -> 'dcharge') as dch, l ->> 'outcome' as outcome
            from public.entries e
            cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) l
           where e.form_code = '20-6' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)) y
   group by y.platform, y.delivery;
$$;

-- ---------- D5 lapsed & new vs repeat customers ----------
create or replace function public._r3q_d5_lapsed(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with s as (select x.customer_id, x.sale_date, x.total from public.sales x
              where x.status = 'done' and x.customer_id is not null and x.location_id = any (locs) and x.sale_date <= d2),
  c as (select customer_id, min(sale_date) as first_d, max(sale_date) as last_d, count(*) as n_all,
               count(*) filter (where sale_date >= d1) as n_p, coalesce(sum(total) filter (where sale_date >= d1), 0) as amt_p
          from s group by customer_id)
  select jsonb_build_object('customer_id', cu.id, 'name', cu.name, 'mobile', cu.mobile,
      'kind', case when c.first_d >= d1 then 'new' when c.n_p > 0 then 'repeat' else 'lapsed' end,
      'first_date', c.first_d, 'last_date', c.last_d, 'days_silent', d2 - c.last_d, 'orders_period', c.n_p, 'amount_period', c.amt_p, 'orders_total', c.n_all)
    from c join public.customers cu on cu.id = c.customer_id
   where c.n_p > 0 or c.last_d >= d1 - 180;
$$;

-- ---------- M1 RFM segments (window = the chosen period) ----------
create or replace function public._r3q_m1_rfm(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with c as (select x.customer_id, max(x.sale_date) as last_d, count(*) as n, coalesce(sum(x.total), 0) as amt
               from public.sales x where x.status = 'done' and x.customer_id is not null and x.location_id = any (locs) and x.sale_date between d1 and d2
              group by x.customer_id)
  select jsonb_build_object('customer_id', cu.id, 'name', cu.name, 'mobile', cu.mobile,
      'segment', case when c.n >= 3 and d2 - c.last_d <= 30 then 'Champion' when c.n >= 2 and d2 - c.last_d > 60 then 'At-risk' when c.n = 1 then 'One-time' else 'Regular' end,
      'recency_days', d2 - c.last_d, 'frequency', c.n, 'monetary', c.amt, 'last_date', c.last_d)
    from c join public.customers cu on cu.id = c.customer_id;
$$;

-- ---------- X2 releases / emergency / grant use ----------
create or replace function public._r3q_x2_bypass(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('staff_id', u.staff, 'staff_name', max(pr.full_name), 'kind', u.kind, 'code', u.code, 'requests', count(*),
      'approved', count(*) filter (where u.st in ('approved', 'used')), 'rejected', count(*) filter (where u.st = 'rejected'),
      'pending', count(*) filter (where u.st = 'pending'), 'other', count(*) filter (where u.st in ('expired', 'cancelled')), 'amount', coalesce(sum(u.amt), 0))
    from (select coalesce(r.requested_staff, '-') as staff, 'release'::text as kind, r.flag_code as code, r.status as st, r.flag_amount as amt
            from public.release_requests r join public.entries e on e.id = r.entry_id
           where (r.requested_at at time zone 'Asia/Dhaka')::date between d1 and d2 and e.location_id = any (locs)
          union all
          select coalesce(q.requested_staff, '-'), 'emergency', q.grant_code, q.status, q.amount
            from public.emergency_requests q
           where (q.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and q.location_id = any (locs)) u
    left join public.profiles pr on pr.staff_id = u.staff
   group by u.staff, u.kind, u.code;
$$;

-- ---------- X3 audit log (owner only) ----------
create or replace function public._r3q_x3_audit_log(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('table_name', a.table_name, 'action', a.action, 'staff_id', coalesce(a.staff_id, '-'), 'events', count(*),
      'first_day', min((a.at at time zone 'Asia/Dhaka')::date), 'last_day', max((a.at at time zone 'Asia/Dhaka')::date))
    from public.audit_log a
   where cardinality(locs) > 0 and (a.at at time zone 'Asia/Dhaka')::date between d1 and d2
   group by a.table_name, a.action, coalesce(a.staff_id, '-');
$$;

-- ---------- X4 form submission compliance (14-1 and 10-1 per shop) ----------
create or replace function public._r3q_x4_compliance(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with today as (select (now() at time zone 'Asia/Dhaka')::date as t),
  hi as (select least(d2, (select t from today)) as h),
  n as (select greatest((select h from hi) - d1 + 1, 0) as days)
  select jsonb_build_object('location_id', l.id, 'location', l.name_bn, 'form', f.code, 'days', (select days from n), 'submitted_days', coalesce(s.sd, 0),
      'missing_days', greatest((select days from n) - coalesce(s.sd, 0), 0),
      'compliance_pct', case when (select days from n) > 0 then round(100.0 * coalesce(s.sd, 0) / (select days from n), 2) end,
      'stale_drafts', coalesce(s.stale, 0), 'late_submits', coalesce(s.late, 0))
    from public.locations l
    cross join (values ('14-1'), ('10-1')) f(code)
    left join lateral (
      select count(distinct e.entry_date) filter (where e.status in ('submitted', 'approved')) as sd,
             count(*) filter (where e.status = 'draft' and e.entry_date < (select t from today) - 1) as stale,
             count(*) filter (where e.status in ('submitted', 'approved') and not e.entered_later and e.submitted_at is not null
                                and (e.submitted_at at time zone 'Asia/Dhaka')::date > e.entry_date) as late
        from public.entries e where e.form_code = f.code and e.location_id = l.id and e.entry_date between d1 and d2) s on true
   where l.id = any (locs) and l.kind = 'showroom' and l.is_active and l.status = 'live';
$$;

-- ---------- X5 staff indicators, monthly (same logic as biz_staff, month by month) ----------
create or replace function public._r3q_x5_staff_trend(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with s as (select x.*, date_trunc('month', x.sale_date)::date as mon from public.sales x where x.sale_date between d1 and d2 and x.location_id = any (locs)),
  ovr as (select s.id, bool_or(e ->> 'override' = 'true') as o from s, jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e group by s.id),
  per as (select s.created_staff as st, s.mon, count(*) filter (where s.status = 'done') as n, coalesce(sum(s.total) filter (where s.status = 'done'), 0) as rev,
                 coalesce(sum(s.discount) filter (where s.status = 'done'), 0) as disc, count(*) filter (where s.status = 'void') as vn,
                 count(*) filter (where s.status = 'done' and o.o) as onum, count(*) filter (where s.status = 'done' and s.quick) as qn,
                 coalesce(sum(s.due_amount) filter (where s.status = 'done'), 0) as duea
            from s left join ovr o on o.id = s.id group by s.created_staff, s.mon)
  select jsonb_build_object('staff_id', coalesce(p.st, '-'), 'staff_name', pr.full_name, 'month', p.mon, 'orders', p.n, 'revenue', p.rev,
      'discount_pct', case when p.rev + p.disc > 0 then round(100 * p.disc / (p.rev + p.disc), 2) end,
      'void_pct', case when p.n + p.vn > 0 then round(100 * p.vn::numeric / (p.n + p.vn), 2) end,
      'override_pct', case when p.n > 0 then round(100 * p.onum::numeric / p.n, 2) end,
      'quick_pct', case when p.n > 0 then round(100 * p.qn::numeric / p.n, 2) end,
      'due_pct', case when p.rev > 0 then round(100 * p.duea / p.rev, 2) end)
    from per p left join public.profiles pr on pr.staff_id = p.st;
$$;

-- ---------- G2 duplicate / out-of-order paper numbers and book usage ----------
create or replace function public._r3q_g2_paper_numbers(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with p as (select e.location_id, e.form_code, e.entry_date, e.serial,
                    public.norm_paper_serial(coalesce(nullif(btrim(e.data ->> 'paper_no'), ''), nullif(btrim(e.paper_serial), ''))) as pn
               from public.entries e where e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)),
  q as (select p.*, case when p.pn ~ '^[0-9]{1,9}$' then p.pn::int end as num from p),
  dup as (select location_id, form_code, pn, count(*) as c from q where pn is not null group by location_id, form_code, pn having count(*) > 1),
  dsum as (select location_id, form_code, count(*) as dup_numbers from dup group by location_id, form_code),
  ord as (select location_id, form_code, count(*) filter (where entry_date < prev_d) as ooo
            from (select q.*, lag(entry_date) over (partition by location_id, form_code order by num, entry_date, serial) as prev_d from q where num is not null) z
           group by location_id, form_code),
  agg as (select location_id, form_code, count(*) as entries, count(*) filter (where pn is null) as no_pn, count(distinct pn) as dist,
                 min(num) as mn, max(num) as mx, count(distinct num) as dnum from q group by location_id, form_code)
  select jsonb_build_object('location_id', l.id, 'location', l.name_bn, 'form', a.form_code, 'entries', a.entries, 'no_paper_no', a.no_pn,
      'distinct_numbers', a.dist, 'duplicate_numbers', coalesce(ds.dup_numbers, 0), 'out_of_order', coalesce(o.ooo, 0),
      'first_no', a.mn, 'last_no', a.mx, 'missing_numbers', case when a.mn is not null then (a.mx - a.mn + 1) - a.dnum end)
    from agg a join public.locations l on l.id = a.location_id
    left join dsum ds on ds.location_id = a.location_id and ds.form_code = a.form_code
    left join ord o on o.location_id = a.location_id and o.form_code = a.form_code;
$$;

-- ---------- K3 store ledger per item and kind (quantities only, no cost) ----------
create or replace function public._r3q_k3_store_ledger(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('item_code', it.code, 'item_name', it.name_bn, 'unit', it.unit, 'kind', sl.reason, 'movements', count(*),
      'in_qty', coalesce(sum(sl.qty_delta) filter (where sl.qty_delta > 0), 0), 'out_qty', coalesce(-sum(sl.qty_delta) filter (where sl.qty_delta < 0), 0),
      'net_qty', sum(sl.qty_delta))
    from public.stock_ledger sl join public.items it on it.id = sl.item_id
   where sl.location_id = any (locs) and (sl.made_at at time zone 'Asia/Dhaka')::date between d1 and d2
     and sl.reverses_id is null and not exists (select 1 from public.stock_ledger r where r.reverses_id = sl.id)
     and (public.rpt_arr_text(flt -> 'categories') is null or it.category = any (public.rpt_arr_text(flt -> 'categories')))
   group by it.id, it.code, it.name_bn, it.unit, sl.reason;
$$;

-- ---------- E2 expense trend with the previous period ----------
create or replace function public._r3q_e2_expense_trend(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with ln as (select e.entry_date as d, coalesce(nullif(btrim(l ->> 'head'), ''), '-') as head, public._r2_num(l -> 'amount') as amt
                from public.entries e
                cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) l
               where e.form_code = '10-2' and e.status in ('submitted', 'approved') and e.location_id = any (locs)
                 and e.entry_date between d1 - (d2 - d1 + 1) and d2),
  g as (select head, coalesce(sum(amt) filter (where d >= d1), 0) as cur, coalesce(sum(amt) filter (where d < d1), 0) as prev from ln group by head)
  select jsonb_build_object('head', coalesce(o.label_bn, g.head), 'current', g.cur, 'previous', g.prev, 'change', g.cur - g.prev,
      'change_pct', case when g.prev > 0 then round(100 * (g.cur - g.prev) / g.prev, 2) end)
    from g left join public.option_lists o on o.list_code = 'expense_heads' and o.value_code = g.head;
$$;

-- ---------- E3 no-receipt / over-limit / imprest ----------
create or replace function public._r3q_e3_weak_control(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('location_id', l.id, 'location', l.name_bn, 'source', '10-2', 'approver', v.appr, 'vouchers', count(*),
      'no_receipt_lines', coalesce(sum(v.nr_lines), 0), 'no_receipt_amount', coalesce(sum(v.nr_amt), 0),
      'over_limit_vouchers', count(*) filter (where v.over), 'over_limit_amount', coalesce(sum(v.over_amt), 0),
      'approval_missing', count(*) filter (where v.appr_miss), 'reason_missing', count(*) filter (where v.reason_miss),
      'imprest_diff_sheets', count(*) filter (where v.imp_diff), 'imprest_diff_amount', coalesce(sum(v.imp_amt), 0))
    from (select e.location_id, coalesce(nullif(btrim(e.data ->> 'approved_by'), ''), '-') as appr, x.nr_lines, x.nr_amt,
                 exists (select 1 from jsonb_array_elements(fl.fa) fe where fe ->> 'code' = 'over_limit') as over,
                 (select coalesce(sum(public._r2_num(fe -> 'amount')), 0) from jsonb_array_elements(fl.fa) fe where fe ->> 'code' = 'over_limit') as over_amt,
                 exists (select 1 from jsonb_array_elements(fl.fa) fe where fe ->> 'code' = 'approval_missing') as appr_miss,
                 exists (select 1 from jsonb_array_elements(fl.fa) fe where fe ->> 'code' = 'receipt_reason_missing') as reason_miss,
                 exists (select 1 from jsonb_array_elements(fl.fa) fe where fe ->> 'code' = 'imprest_mismatch') as imp_diff,
                 (select coalesce(sum(abs(public._r2_num(fe -> 'amount'))), 0) from jsonb_array_elements(fl.fa) fe where fe ->> 'code' = 'imprest_mismatch') as imp_amt
            from public.entries e
            cross join lateral (select case when jsonb_typeof(e.flags) = 'array' then e.flags else '[]'::jsonb end as fa) fl
            cross join lateral (select count(*) filter (where ln ->> 'receipt' = 'no' and public._r2_num(ln -> 'amount') > 0) as nr_lines,
                                       sum(public._r2_num(ln -> 'amount')) filter (where ln ->> 'receipt' = 'no') as nr_amt
                                  from jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) ln) x
           where e.form_code = '10-2' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)) v
    join public.locations l on l.id = v.location_id
   group by l.id, l.name_bn, v.appr
  union all
  select jsonb_build_object('location_id', l.id, 'location', l.name_bn, 'source', '14-1', 'approver', '-', 'vouchers', count(*),
      'no_receipt_lines', null, 'no_receipt_amount', null, 'over_limit_vouchers', null, 'over_limit_amount', null, 'approval_missing', null, 'reason_missing', null,
      'imprest_diff_sheets', count(*) filter (where v.imp_diff), 'imprest_diff_amount', coalesce(sum(v.imp_amt), 0))
    from (select e.location_id,
                 exists (select 1 from jsonb_array_elements(fl.fa) fe where fe ->> 'code' = 'open_imprest_diff') as imp_diff,
                 (select coalesce(sum(abs(public._r2_num(fe -> 'amount'))), 0) from jsonb_array_elements(fl.fa) fe where fe ->> 'code' = 'open_imprest_diff') as imp_amt
            from public.entries e
            cross join lateral (select case when jsonb_typeof(e.flags) = 'array' then e.flags else '[]'::jsonb end as fa) fl
           where e.form_code = '14-1' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)) v
    join public.locations l on l.id = v.location_id
   group by l.id, l.name_bn;
$$;

-- ---------- E4 marketing spend vs the monthly head limit ----------
create or replace function public._r3q_e4_marketing_limit(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with ln as (select e.location_id, date_trunc('month', coalesce(public._db_date(l ->> 'date'), e.entry_date))::date as mon,
                     case when l ->> 'head' like 'other:%' then 'other' else coalesce(nullif(btrim(l ->> 'head'), ''), '-') end as head,
                     public._r2_num(l -> 'amt') as amt
                from public.entries e
                cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) l
               where e.form_code = '18-1' and e.status in ('submitted', 'approved') and e.location_id = any (locs)
                 and coalesce(public._db_date(l ->> 'date'), e.entry_date) between d1 and d2),
  g as (select location_id, mon, head, sum(amt) filter (where amt > 0) as spend from ln group by location_id, mon, head having sum(amt) filter (where amt > 0) is not null),
  w as (select g.*, o.label_bn,
               coalesce(case when o.extra ->> 'limit_month' ~ '^[0-9]{1,12}(\.[0-9]{1,4})?$' then (o.extra ->> 'limit_month')::numeric end,
                        (select public._r2_num(ls.value) from public.location_settings ls where ls.location_id = g.location_id and ls.key = 'mkt_limit_' || g.head)) as lim
          from g left join public.option_lists o on o.list_code = 'marketing_heads' and o.value_code = g.head)
  select jsonb_build_object('location_id', l.id, 'location', l.name_bn, 'month', w.mon, 'head', coalesce(w.label_bn, w.head), 'spend', w.spend, 'limit', w.lim,
      'used_pct', case when w.lim > 0 then round(100 * w.spend / w.lim, 2) end, 'over_amount', case when w.lim is not null then greatest(w.spend - w.lim, 0) end)
    from w join public.locations l on l.id = w.location_id;
$$;

-- ---------- W1 daily cash flow per location (cash-flow only: no salary lines, no internal lines) ----------
create or replace function public._r3q_w1_cash_flow(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('location_id', l.id, 'location', l.name_bn, 'day', u.d,
      'cash_in', coalesce(sum(u.amount) filter (where u.dir = 'in' and u.mode = 'cash'), 0), 'cash_out', coalesce(sum(u.amount) filter (where u.dir = 'out' and u.mode = 'cash'), 0),
      'net_cash', coalesce(sum(u.amount) filter (where u.dir = 'in' and u.mode = 'cash'), 0) - coalesce(sum(u.amount) filter (where u.dir = 'out' and u.mode = 'cash'), 0),
      'other_in', coalesce(sum(u.amount) filter (where u.dir = 'in' and u.mode <> 'cash'), 0), 'other_out', coalesce(sum(u.amount) filter (where u.dir = 'out' and u.mode <> 'cash'), 0))
    from (select * from public._daybook_lines(locs, '{}'::int[], d1, d2) union all select * from public._daybook_lines12(locs, d1, d2) union all select * from public._daybook_lines23(locs, d1, d2)) u
    join public.locations l on l.id = u.loc
   where not u.internal and not u.sensitive
   group by l.id, l.name_bn, u.d;
$$;

-- ---------- W2 handover (10-1) vs hub count ----------
create or replace function public._r3q_w2_handover_vs_hub(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('location_id', l.id, 'location', l.name_bn, 'carrier', v.carrier, 'slips', count(*), 'handover', coalesce(sum(v.handover), 0),
      'hub_counted_slips', count(*) filter (where v.hub is not null), 'hub_received', sum(v.hub),
      'diff', sum(v.hub - v.handover) filter (where v.hub is not null),
      'short_slips', count(*) filter (where v.hub is not null and v.hub < v.handover), 'over_slips', count(*) filter (where v.hub is not null and v.hub > v.handover),
      'not_counted', count(*) filter (where v.hub is null))
    from (select e.location_id, coalesce(nullif(btrim(e.data ->> 'carrier'), ''), '-') as carrier, h.amt as handover,
                 case when ec.counted is not null then ec.counted
                      when e.check_data ? 'rcount' and public._den_total18(e.check_data -> 'rcount', false) > 0 then public._den_total18(e.check_data -> 'rcount', false) end as hub
            from public.entries e
            left join public.entry_counts ec on ec.entry_id = e.id and ec.section = 'hub'
            cross join lateral (select coalesce(public._db_num(e.data #> '{count,n1000}'), 0) * 1000 + coalesce(public._db_num(e.data #> '{count,n500}'), 0) * 500
                + coalesce(public._db_num(e.data #> '{count,n200}'), 0) * 200 + coalesce(public._db_num(e.data #> '{count,n100}'), 0) * 100
                + coalesce(public._db_num(e.data #> '{count,n50}'), 0) * 50 + coalesce(public._db_num(e.data #> '{count,n20}'), 0) * 20
                + coalesce(public._db_num(e.data #> '{count,n10}'), 0) * 10 + coalesce(public._db_num(e.data #> '{count,n5}'), 0) * 5
                + coalesce(public._db_num(e.data #> '{count,n2}'), 0) * 2 + coalesce(public._db_num(e.data #> '{count,n1}'), 0)
                + coalesce(public._db_num(e.data #> '{count,coin}'), 0) - coalesce(public._db_num(e.data -> 'leave_float'), 0) as amt) h
           where e.form_code = '10-1' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)) v
    join public.locations l on l.id = v.location_id
   group by l.id, l.name_bn, v.carrier;
$$;

-- ---------- registry ----------
insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('s10_orders', 'S10', 'orders', 'অর্ডার, অনলাইন ও ডেলিভারি', 'Orders, online & delivery', 'Order, online ও delivery',
  '[["source","উৎস ফর্ম","Source form","text"],["channel","মাধ্যম","Channel","text"],["online","অনলাইন/প্ল্যাটফর্ম","Online / platform","text"],["delivery","ডেলিভারি","Delivery","text"],["orders","অর্ডার","Orders","int"],["amount","অঙ্ক","Amount","money"],["advance","অ্যাডভান্স","Advance","money"],["balance","বাকি","Balance","money"],["handed","হাতে দেওয়া","Handed over","int"],["not_collected","নেওয়া হয়নি","Not collected","int"],["returned","ফেরত","Returned","int"],["delivery_charge","ডেলিভারি চার্জ","Delivery charge","money"]]'::jsonb,
  array['orders','amount','advance','balance','handed','not_collected','returned','delivery_charge'], 'amount', 'desc', array['locations'], false, false, false, 2500),
 ('d5_lapsed', 'D5', 'sales', 'নিষ্ক্রিয় ও নতুন-পুরনো গ্রাহক', 'Lapsed, new vs repeat customers', 'Lapsed ও নতুন-পুরনো গ্রাহক',
  '[["customer_id","","","id"],["name","নাম","Name","text"],["mobile","মোবাইল","Mobile","text"],["kind","ধরন (new/repeat/lapsed)","Kind (new/repeat/lapsed)","text"],["first_date","প্রথম কেনা","First purchase","date"],["last_date","শেষ কেনা","Last purchase","date"],["days_silent","নীরব দিন","Days silent","int"],["orders_period","এই সময়ের অর্ডার","Orders in period","int"],["amount_period","এই সময়ের টাকা","Amount in period","money"],["orders_total","মোট অর্ডার","Orders to date","int"]]'::jsonb,
  array['orders_period','amount_period'], 'amount_period', 'desc', array['locations'], false, false, false, 2510),
 ('m1_rfm', 'M1', 'sales', 'গ্রাহক সেগমেন্ট (RFM)', 'Customer segments (RFM)', 'Customer segment (RFM)',
  '[["customer_id","","","id"],["name","নাম","Name","text"],["mobile","মোবাইল","Mobile","text"],["segment","সেগমেন্ট","Segment","text"],["recency_days","শেষ কেনার পর দিন","Days since last purchase","int"],["frequency","বার","Orders","int"],["monetary","টাকা","Spend","money"],["last_date","শেষ কেনা","Last purchase","date"]]'::jsonb,
  array['frequency','monetary'], 'monetary', 'desc', array['locations'], false, false, false, 2520),
 ('x2_bypass', 'X2', 'control', 'ছাড়, জরুরি অনুমোদন ও গ্রান্ট ব্যবহার', 'Releases, emergency & grant use', 'Release, emergency ও grant ব্যবহার',
  '[["staff_id","স্টাফ আইডি","Staff ID","text"],["staff_name","নাম","Name","text"],["kind","ধরন","Kind","text"],["code","কোড","Code","text"],["requests","অনুরোধ","Requests","int"],["approved","অনুমোদিত","Approved","int"],["rejected","বাতিল","Rejected","int"],["pending","অপেক্ষায়","Pending","int"],["other","মেয়াদ শেষ/বাতিল","Expired/cancelled","int"],["amount","অঙ্ক","Amount","money"]]'::jsonb,
  array['requests','approved','rejected','pending','other','amount'], 'requests', 'desc', array['locations'], false, false, false, 2530),
 ('x3_audit_log', 'X3', 'control', 'অডিট ও সংশোধন লগ', 'Audit & correction log', 'Audit ও correction log',
  '[["table_name","টেবিল","Table","text"],["action","কাজ","Action","text"],["staff_id","স্টাফ","Staff","text"],["events","ঘটনা","Events","int"],["first_day","প্রথম দিন","First day","date"],["last_day","শেষ দিন","Last day","date"]]'::jsonb,
  array['events'], 'events', 'desc', '{}'::text[], false, false, true, 2540),
 ('x4_compliance', 'X4', 'control', 'ফর্ম জমার নিয়ম-পালন', 'Form submission compliance', 'Form জমার compliance',
  '[["location_id","","","id"],["location","শোরুম","Shop","text"],["form","ফর্ম","Form","text"],["days","দিন","Days","int"],["submitted_days","জমা-দেওয়া দিন","Days submitted","int"],["missing_days","বাদ-পড়া দিন","Days missing","int"],["compliance_pct","পালন %","Compliance %","pct"],["stale_drafts","পুরনো খসড়া","Stale drafts","int"],["late_submits","দেরিতে জমা","Late submits","int"]]'::jsonb,
  array['days','submitted_days','missing_days','stale_drafts','late_submits'], 'missing_days', 'desc', array['locations'], false, false, false, 2550),
 ('x5_staff_trend', 'X5', 'staff', 'স্টাফ সূচক ধারা (মাসওয়ারি)', 'Staff indicators by month', 'Staff সূচক ধারা (monthly)',
  '[["staff_id","স্টাফ আইডি","Staff ID","text"],["staff_name","নাম","Name","text"],["month","মাস","Month","date"],["orders","বিক্রি","Sales","int"],["revenue","বিক্রয়","Revenue","money"],["discount_pct","ছাড় %","Discount %","pct"],["void_pct","বাতিল %","Void %","pct"],["override_pct","দাম বদল %","Override %","pct"],["quick_pct","কুইক %","Quick %","pct"],["due_pct","বাকি %","Due %","pct"]]'::jsonb,
  array['orders','revenue'], 'month', 'desc', array['locations'], false, false, false, 2560),
 ('g2_paper_numbers', 'G2', 'control', 'ডুপ্লিকেট/উল্টো ক্রম ও বই-ব্যবহার', 'Duplicate / out-of-order paper numbers', 'Duplicate/উল্টো ক্রম ও বই-ব্যবহার',
  '[["location_id","","","id"],["location","লোকেশন","Location","text"],["form","ফর্ম","Form","text"],["entries","এন্ট্রি","Entries","int"],["no_paper_no","নম্বর ছাড়া","Without number","int"],["distinct_numbers","আলাদা নম্বর","Distinct numbers","int"],["duplicate_numbers","ডুপ্লিকেট নম্বর","Duplicate numbers","int"],["out_of_order","উল্টো ক্রম","Out of order","int"],["first_no","প্রথম নম্বর","First no.","int"],["last_no","শেষ নম্বর","Last no.","int"],["missing_numbers","বাদ-পড়া নম্বর","Missing numbers","int"]]'::jsonb,
  array['entries','no_paper_no','duplicate_numbers','out_of_order','missing_numbers'], 'duplicate_numbers', 'desc', array['locations'], false, false, false, 2570),
 ('k3_store_ledger', 'K3', 'stock', 'স্টক মুভমেন্ট (আইটেম ও ধরন)', 'Store ledger movement', 'Stock movement (item ও kind)',
  '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["unit","একক","Unit","text"],["kind","ধরন","Kind","text"],["movements","মুভমেন্ট","Movements","int"],["in_qty","ঢুকেছে","In","num"],["out_qty","বেরিয়েছে","Out","num"],["net_qty","নিট","Net","num"]]'::jsonb,
  array['movements'], 'movements', 'desc', array['locations','brands','categories'], false, false, false, 2580),
 ('e2_expense_trend', 'E2', 'expense', 'খরচের ধারা ও আগের সময়ের তুলনা', 'Expense trend vs previous period', 'খরচের ধারা (আগের সময়ের সাথে)',
  '[["head","খাত","Head","text"],["current","এই সময়","Current","money"],["previous","আগের সময়","Previous","money"],["change","পরিবর্তন","Change","money"],["change_pct","পরিবর্তন %","Change %","pct"]]'::jsonb,
  array['current','previous','change'], 'change', 'desc', array['locations'], false, false, false, 2590),
 ('e3_weak_control', 'E3', 'expense', 'রসিদহীন, সীমা-ছাড়া ও ইমপ্রেস্ট', 'No-receipt, over-limit & imprest', 'রসিদহীন/সীমা-ছাড়া/imprest',
  '[["location_id","","","id"],["location","লোকেশন","Location","text"],["source","ফর্ম","Form","text"],["approver","অনুমোদনকারী","Approver","text"],["vouchers","ভাউচার/শিট","Vouchers / sheets","int"],["no_receipt_lines","রসিদ ছাড়া লাইন","No-receipt lines","int"],["no_receipt_amount","রসিদ ছাড়া টাকা","No-receipt amount","money"],["over_limit_vouchers","সীমার উপরে ভাউচার","Over-limit vouchers","int"],["over_limit_amount","সীমার উপরের লাইন (বড়)","Over-limit line (largest)","money"],["approval_missing","অনুমোদনকারী নেই","Approver missing","int"],["reason_missing","কারণ নেই","Reason missing","int"],["imprest_diff_sheets","ইমপ্রেস্ট অমিল","Imprest mismatch","int"],["imprest_diff_amount","ইমপ্রেস্ট অমিলের টাকা","Imprest mismatch amount","money"]]'::jsonb,
  array['vouchers','no_receipt_lines','no_receipt_amount','over_limit_vouchers','over_limit_amount','approval_missing','reason_missing','imprest_diff_sheets','imprest_diff_amount'], 'no_receipt_amount', 'desc', array['locations'], false, false, false, 2600),
 ('e4_marketing_limit', 'E4', 'marketing', 'মার্কেটিং খরচ বনাম মাসিক সীমা', 'Marketing spend vs monthly head limit', 'মার্কেটিং খরচ vs monthly limit',
  '[["location_id","","","id"],["location","লোকেশন","Location","text"],["month","মাস","Month","date"],["head","খাত","Head","text"],["spend","খরচ","Spend","money"],["limit","মাসিক সীমা","Monthly limit","money"],["used_pct","ব্যবহার %","Used %","pct"],["over_amount","সীমার বেশি","Over limit","money"]]'::jsonb,
  array['spend','over_amount'], 'spend', 'desc', array['locations'], false, false, false, 2610),
 ('w1_cash_flow', 'W1', 'cash', 'দৈনিক ক্যাশ প্রবাহ', 'Daily cash flow', 'Daily cash flow',
  '[["location_id","","","id"],["location","লোকেশন","Location","text"],["day","দিন","Day","date"],["cash_in","নগদ ঢুকেছে","Cash in","money"],["cash_out","নগদ বেরিয়েছে","Cash out","money"],["net_cash","নিট নগদ","Net cash","money"],["other_in","ব্যাংক/মোবাইল ঢুকেছে","Bank/mobile in","money"],["other_out","ব্যাংক/মোবাইল বেরিয়েছে","Bank/mobile out","money"]]'::jsonb,
  array['cash_in','cash_out','net_cash','other_in','other_out'], 'day', 'desc', array['locations'], false, false, false, 2620),
 ('w2_handover_vs_hub', 'W2', 'cash', 'হ্যান্ডওভার বনাম হাব গণনা', 'Handover vs hub count', 'Handover vs hub গণনা',
  '[["location_id","","","id"],["location","লোকেশন","Location","text"],["carrier","বহনকারী","Carrier","text"],["slips","স্লিপ","Slips","int"],["handover","হ্যান্ডওভার","Handover","money"],["hub_counted_slips","হাবে গোনা স্লিপ","Slips counted at hub","int"],["hub_received","হাবে প্রাপ্ত","Hub received","money"],["diff","পার্থক্য (হাব − হ্যান্ডওভার)","Difference (hub − handover)","money"],["short_slips","কম স্লিপ","Short slips","int"],["over_slips","বেশি স্লিপ","Over slips","int"],["not_counted","হাবে গোনা হয়নি","Not counted at hub","int"]]'::jsonb,
  array['slips','handover','hub_counted_slips','hub_received','diff','short_slips','over_slips','not_counted'], 'diff', 'asc', array['locations'], false, false, false, 2630)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols,
  tot = excluded.tot, sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort;

select public._r3_lockdown();

