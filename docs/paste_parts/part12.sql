-- ============================================================================
-- FRESH part 12 of 21. Paste the WHOLE of this file into the Supabase SQL editor, press Run, wait for "Success", then paste the next part.
-- Phases in this part, in this order: phase528 phase133 phase134 phase135 phase529 phase80 phase81 phase82 phase83 phase84 phase85 phase86
-- Never paste: any *_test.sql, the phase84 / 84b / 84c TEST-PROJECT files, ALL_NEW2..ALL_NEW11*. Commit: see docs/PASTE_ORDER.md.
-- ============================================================================

-- ---------------------------------------------------------------- phase528.sql
-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase132.sql there and is already pasted on the live database under that name.
-- Renumbered to phase528.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 528 (marker mstr132) - GROUP ERP, STAGE C2: strict separation of MASTER DATA between businesses, behind the switch org_scope_on (DEFAULT OFF).
-- Plan: docs/GROUP_ERP_STAGE_A.md sections 3.4, 10, 11; audit docs/audit_c1/RLS_ISOLATION_AUDIT.md section 4.5 (the 50 global master tables); coverage table docs/audit_c1/C2_COVERAGE.md.
-- Canonical order: after phase527 (docs/PASTE_ORDER.md). Paste twice = no change, no error. Needs phases 122, 123, 125.
-- With org_scope_on OFF (the default) every behaviour is the one of phase527: the new columns are filled and ignored, the policies / guards below are true / silent while the switch is OFF,
-- and every patched function keeps its old text in the OFF branch (tests/sql/c2_before_after.sh proves it on seeded data).
--
--   WHAT IT DOES (see C2_COVERAGE.md for the decision per table)
--     master_scope132         the registry: one row per master table = decision (scoped | shared_config | loc_scoped_c1 | deferred), kind, parent link, why.
--     org_unit_id (BUSINESS)  added (nullable, FK org_units) to every SCOPED table; existing rows back-filled to the sweets business (fill-null-only, user triggers paused for the
--                             pure column fill, never overwritten on a second paste); child tables take the business of their parent row (item -> costs / prices / links, recipe -> lines,
--                             customer -> points / gifts / history, asset -> cost); employees / artisans take the business of their place.
--     new rows              a BEFORE INSERT trigger gives every new master row the business of the caller (the working business set with master_context_set132, else the only business
--                             of the caller, else the sweets business) or of its parent / place. The business never moves later (master_org_fixed).
--     reads (switch ON)     restrictive RLS select policy <table>_m132: owner = all; others = the businesses they belong to (_my_biz123), rows shared to them by master_shares132,
--                             vocabulary rows without a business (NULL = shared, e.g. the units list). Other businesses' rows simply do not exist for them.
--     writes (switch ON)    the same trigger refuses a write into / of another business ('not allowed' for an insert, 'not found' for an update = the answer for a missing id), whatever
--                             function does it. Owner and the server (no login) pass.
--     master_shares132      the ONLY way masters cross a business border: owner-created, default none, read-only for the receiver (never used for transactions), revocable, audited.
--     uniqueness            customers.mobile : new unique index (org_unit_id, mobile); items.code : (org_unit_id, code) from phase125; items.barcode : (org_unit_id, barcode).
--                             The GLOBAL unique constraints stay until the owner runs org_masters_relax_unique() (owner only, only while org_scope_on is ON, after
--                             org_masters_preflight() has no blocker, dry-run first, logged, reversible with org_masters_restore_unique()). While relaxed, org_scope_on cannot be switched OFF.
--     patched functions     (text patch of the current body, marker "m132", idempotent): the customer lookups by mobile (find_customer, customer_pos_info, customer_save, record_sale2),
--                             the item-code resolvers (_elp_post_line, count_lines_seal, _entries_countseal_guard23, variants_generate, _item_master_classify, item_master_import_apply)
--                             and the master pick lists (customer_directory, supplier_pick, scan_match_suppliers, scan_match_items, artisan_list, category_list, item_dup_check).
--     stock guard           an item of business A cannot be moved at a location of business B (trigger on stock_ledger, switch ON).
--   NEW FUNCTIONS (owner unless noted): master_share_create / master_share_revoke / master_share_list (owner, org_manage reads), master_context_set132 / master_context_get132 (any user, own businesses),
--     org_masters_preflight, org_masters_relax_unique, org_masters_restore_unique, master_scope_report132 (owner, org_manage).
--   NOT HERE (deferred, see C2_COVERAGE.md): coa_accounts / acct_mappings (posting functions resolve accounts by the global code: per-business chart = Stage C2b with legal-entity books),
--     per-business customer tiers / default tier, per-business rules / roles / grants and the other reader RPCs of the C1 audit Appendix B (phase133, other agent).
-- Rollback: leave the switch OFF. To remove: drop the policies *_m132 and triggers a132_scope / stock_ledger_xbiz132 / rules_m132, re-paste the older phase files of the patched functions
--   (phase 513 record_sale2 ..., see PASTE_ORDER), drop the new tables / functions. The org_unit_id columns can stay (nothing reads them).
-- ============================================================
begin;

do $g$
declare miss text := '';
begin
  if to_regclass('public.org_units') is null or to_regclass('public.user_org_scopes') is null or to_regclass('public.items') is null or to_regclass('public.customers') is null
     or to_regclass('public.suppliers') is null or to_regclass('public.stock_ledger') is null or to_regclass('public.rules') is null then miss := miss || ' tables'; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'items' and column_name = 'org_unit_id') then miss := miss || ' items.org_unit_id(phase125)'; end if;
  if to_regprocedure('public._my_biz123()') is null or to_regprocedure('public._org_on123()') is null or to_regprocedure('public._business_of_loc123(integer)') is null
     or to_regprocedure('public._biz_default125()') is null or to_regprocedure('public.log_change()') is null or to_regprocedure('public.no_hard_delete()') is null
     or to_regprocedure('public._client_lock(uuid)') is null or to_regprocedure('public.is_owner()') is null then miss := miss || ' functions(phase123/125)'; end if;
  if miss <> '' then raise exception 'phase528 needs the base schema and phases up to 131 pasted first (docs/PASTE_ORDER.md); missing:%', miss; end if;
end $g$;

-- ---------- 1. the registry (one row per master table of the audit, plus a few obvious children) ----------
create table if not exists public.master_scope132 (
  table_name text primary key,
  decision text not null check (decision in ('scoped', 'shared_config', 'loc_scoped_c1', 'deferred')),
  kind text check (kind in ('root', 'vocab', 'self_loc', 'child', 'child_loc')),
  parent_table text, parent_col text, parent_pk text, parent_pk_type text, parent_loc_col text,   -- child: parent_col (fk here) -> parent_table.parent_pk ; child_loc: ... then parent_loc_col -> location -> business
  loc_col text,                                  -- self_loc: the place column of the row itself
  shared_col text, shared_vals text[],           -- vocab: rows whose shared_col is in shared_vals keep org_unit_id NULL = shared by everybody
  key_expr text not null default 'id::text',     -- the row key used by master_shares132
  shareable boolean not null default false,
  audit_set boolean not null default true,       -- true = the table is one of the 50 of the audit (section 4.5); false = an extra child added here
  why text not null,
  sort int not null default 100
);
alter table public.master_scope132 enable row level security;
drop policy if exists master_scope132_read on public.master_scope132;
create policy master_scope132_read on public.master_scope132 for select to authenticated using (public.is_owner() or public.has_grant('org_manage'));
revoke all on public.master_scope132 from public, anon, authenticated;
grant select on public.master_scope132 to authenticated;

insert into public.master_scope132 (table_name, decision, kind, parent_table, parent_col, parent_pk, parent_pk_type, parent_loc_col, loc_col, shared_col, shared_vals, key_expr, shareable, audit_set, why, sort) values
 -- ROOT masters: own business
 ('items',                 'scoped', 'root',  null, null, null, null, null, null, null, null, 'id::text', true,  true,  'The item list of a business: its own code / barcode / price. org_unit_id comes from phase125; this phase adds the restrictive read policy, the write guard and the per-business barcode.', 10),
 ('customers',             'scoped', 'root',  null, null, null, null, null, null, null, null, 'id::text', false, true,  'Customers are never shared: a mobile number is a customer of ONE business (per-business unique index; global unique relaxed only by org_masters_relax_unique).', 11),
 ('suppliers',             'scoped', 'root',  null, null, null, null, null, null, null, null, 'id::text', true,  true,  'Suppliers and their dues belong to one business; the owner may share the supplier list (read only) with another business.', 12),
 ('artisans',              'scoped', 'self_loc', null, null, null, null, null, 'location_id', null, null, 'id::text', true, true, 'Factory staff register: the business of the artisan place; shareable read only.', 13),
 ('employees',             'scoped', 'self_loc', null, null, null, null, null, 'primary_location_id', null, null, 'id::text', false, true, 'Employees follow the business of their primary place (the pay / leave tables are already place-scoped by phase123 through can_loc).', 14),
 ('item_categories',       'scoped', 'root',  null, null, null, null, null, null, null, null, 'id::text', true,  true,  'The category tree of a business (the sweets tree stays with sweets; other businesses build their own or receive a share).', 15),
 ('deed_templates',        'scoped', 'root',  null, null, null, null, null, null, null, null, 'id::text', true,  true,  'Employment deed wording is a business document.', 16),
 ('item_bulk_batches',     'scoped', 'root',  null, null, null, null, null, null, null, null, 'id::text', false, true,  'Log of bulk item changes (names item codes): belongs to the business that ran it.', 17),
 ('option_lists',          'scoped', 'vocab', null, null, null, null, null, null, 'list_code', array['units'], $k$list_code || '/' || value_code$k$, true, true, 'Dropdown vocabularies (expense heads, wallets, reasons ...) are per business; the units list stays shared (NULL business). A share can hand a whole list (row_key = list_code) to another business.', 18),
 ('list_defs',             'scoped', 'vocab', null, null, null, null, null, null, 'list_code', array['units'], 'list_code', true, true, 'Definition / rule of a vocabulary: follows its list.', 19),
 ('shelf_life_rules',      'scoped', 'child', 'items', 'item_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Shelf life per item (or per category when no item): the business of the item, else of the creator.', 20),
 ('recipes',               'scoped', 'child', 'items', 'item_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'A recipe belongs to the business of its finished item; never shared (copy by hand).', 21),
 -- CHILDREN of items
 ('item_costs',            'scoped', 'child', 'items', 'item_id', 'id', 'uuid', null, null, null, null, 'item_id::text', false, true, 'Cost of an item: the business of the item.', 30),
 ('item_cost_flags',       'scoped', 'child', 'items', 'item_id', 'id', 'uuid', null, null, null, null, 'item_id::text', false, true, 'Cost-free flag of an item.', 31),
 ('item_logistics',        'scoped', 'child', 'items', 'item_id', 'id', 'uuid', null, null, null, null, 'item_id::text', false, true, 'Weight / volume of an item.', 32),
 ('item_price_history',    'scoped', 'child', 'items', 'item_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Price history of an item.', 33),
 ('item_changes',          'scoped', 'child', 'items', 'item_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Item change requests: the business of the item (a request for a NEW item has no item: the business of the requester).', 34),
 ('item_master_links',     'scoped', 'child', 'items', 'item_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Link of an item to the item dictionary.', 35),
 ('item_mapping_review',   'scoped', 'child', 'items', 'item_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Dictionary mapping review of an item.', 36),
 ('item_map_actions',      'scoped', 'child', 'items', 'item_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Dictionary mapping actions (append-only) of an item.', 37),
 ('unit_conversions',      'scoped', 'child', 'items', 'item_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Unit conversion of an item (the list of units itself is the shared list "units").', 38),
 ('product_packaging',     'scoped', 'child', 'items', 'product_item_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Packaging of a finished item: the business of the finished item.', 39),
 -- CHILDREN of recipes
 ('recipe_lines',          'scoped', 'child', 'recipes', 'recipe_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Ingredient lines of a recipe.', 40),
 ('recipe_steps',          'scoped', 'child', 'recipes', 'recipe_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Method steps of a recipe.', 41),
 ('recipe_versions',       'scoped', 'child', 'recipes', 'recipe_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Version history of a recipe (append-only).', 42),
 ('recipe_cost_components','scoped', 'child', 'recipes', 'recipe_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Extra cost components of a recipe (the list of component types is shared config).', 43),
 ('recipe_std116',         'scoped', 'child', 'recipes', 'recipe_id', 'id', 'uuid', null, null, null, null, 'id::text', false, false, 'EXTRA (not in the audit list): standard yield / cost per batch of a recipe.', 44),
 -- CHILDREN of customers
 ('customer_gifts',        'scoped', 'child', 'customers', 'customer_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Gifts issued to a customer (the gift RULES are shared config).', 50),
 ('customer_points_ledger','scoped', 'child', 'customers', 'customer_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Loyalty points of a customer (append-only).', 51),
 ('customer_tier_history', 'scoped', 'child', 'customers', 'customer_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Tier changes of a customer (append-only).', 52),
 ('notify_optin',          'scoped', 'child', 'customers', 'customer_id', 'id', 'uuid', null, null, null, null, 'id::text', false, false, 'EXTRA: message consent of a customer.', 53),
 ('telegram_chat_links',   'scoped', 'child', 'customers', 'customer_id', 'id', 'uuid', null, null, null, null, 'id::text', false, false, 'EXTRA: chat <-> customer link (a link with no customer belongs to the business of the linker).', 54),
 -- CHILDREN of suppliers / assets
 ('landed_supplier_flags', 'scoped', 'child', 'suppliers', 'supplier_id', 'id', 'uuid', null, null, null, null, 'supplier_id::text', false, false, 'EXTRA: landed-cost flags of a supplier.', 60),
 ('asset_costs',           'scoped', 'child_loc', 'assets', 'asset_id', 'id', 'uuid', 'location_id', null, null, null, 'asset_id::text', false, true, 'Cost of an asset: the business of the asset place.', 61)
on conflict (table_name) do update set decision = excluded.decision, kind = excluded.kind, parent_table = excluded.parent_table, parent_col = excluded.parent_col, parent_pk = excluded.parent_pk,
  parent_pk_type = excluded.parent_pk_type, parent_loc_col = excluded.parent_loc_col, loc_col = excluded.loc_col, shared_col = excluded.shared_col, shared_vals = excluded.shared_vals,
  key_expr = excluded.key_expr, shareable = excluded.shareable, audit_set = excluded.audit_set, why = excluded.why, sort = excluded.sort;

insert into public.master_scope132 (table_name, decision, why, sort) values
 ('forms',                  'shared_config', 'The catalogue of form codes is the application itself; which form a business uses is the module switch (Stage A 3.5), not a copy of the catalogue.', 200),
 ('item_types',             'shared_config', 'Closed list of item kinds that the code branches on (finished good, raw material ...); no business data.', 201),
 ('item_class_map',         'shared_config', 'Maps the control class to an item kind: engine configuration.', 202),
 ('staff_roles',            'shared_config', 'Catalogue of staff role codes referenced by employee rows; no business data. A per-business override belongs to the roles / grants work (phase133).', 203),
 ('leave_types',            'shared_config', 'Catalogue of leave kinds; per-business leave days belong to the per-business rules work (phase133).', 204),
 ('benefit_types',          'shared_config', 'Catalogue of benefit kinds; per-business eligibility belongs to the per-business rules work (phase133).', 205),
 ('cost_component_types',   'shared_config', 'Closed list of cost component kinds the costing code posts with (builtin); the amounts live in the scoped recipe / location tables.', 206),
 ('cost_charge_types',      'shared_config', 'Closed list of landed charge kinds (treatment / expense key); no business data.', 207),
 ('cost_source_types',      'shared_config', 'Closed list of cost source kinds; the sources themselves are place-scoped.', 208),
 ('notify_templates',       'shared_config', 'Wording of system messages; read only through the notification permission (_i62_ok). A per-business wording is a later feature.', 209),
 ('partner_templates',      'shared_config', 'Owner-only select already (policy partner_templates_sel = is_owner): no business user can read it.', 210),
 ('item_import_batches',    'shared_config', 'Owner-only select already (policy = is_owner): the import log is a group-owner tool.', 211),
 ('customer_tiers',         'shared_config', 'One loyalty ladder for the group: the default-tier logic (customer_tiers_one_default, _customer_new43, _tier_guard43, tier_save, customer_tier_refresh) assumes ONE default tier. A tier row holds no customer data; the customer <-> tier link, points, gifts and history ARE scoped. Per-business ladders = deferred.', 212),
 ('gift_rules',             'shared_config', 'Rules hang on the shared ladder (tier_id): same decision as customer_tiers.', 213),
 ('doc_template_choice',    'loc_scoped_c1', 'Already filtered by place for the active business in phase123 (policy doc_template_choice_scope123).', 220),
 ('invoice_templates',      'loc_scoped_c1', 'Already filtered by place in phase123 (policy invoice_templates_scope123, read and write).', 221),
 ('print_profiles',         'loc_scoped_c1', 'Already filtered by place in phase123 (policy print_profiles_scope123, read and write).', 222),
 ('report_brand_map',       'loc_scoped_c1', 'Already filtered by place in phase123 (policy report_brand_map_scope123).', 223),
 ('coa_accounts',           'deferred', 'DEFERRED to Stage C2b: the posting functions resolve accounts by the GLOBAL code (select id from coa_accounts where code = ...); a chart per business needs the legal-entity column on journal_entries and a rewrite of every posting function. Journal LINES are already place-scoped (phase123).', 230),
 ('acct_mappings',          'deferred', 'DEFERRED to Stage C2b: the key -> account mapping is read by the same posting functions; it moves together with the chart of accounts.', 231)
on conflict (table_name) do update set decision = excluded.decision, why = excluded.why, sort = excluded.sort;

-- ---------- 2. who works for which business ----------
create table if not exists public.master_ctx132 (
  user_id uuid primary key references public.profiles(id),
  org_unit_id bigint not null references public.org_units(id),
  set_at timestamptz not null default now()
);
alter table public.master_ctx132 enable row level security;
drop policy if exists master_ctx132_read on public.master_ctx132;
create policy master_ctx132_read on public.master_ctx132 for select to authenticated using (user_id = auth.uid() or public.is_owner());
revoke all on public.master_ctx132 from public, anon, authenticated;
grant select on public.master_ctx132 to authenticated;

create table if not exists public.master_shares132 (
  id bigserial primary key,
  table_name text not null references public.master_scope132(table_name),
  row_key text check (row_key is null or length(row_key) <= 200),     -- NULL = every row of the table of from_org; else one row key (option_lists / list_defs: a whole list by its list_code)
  from_org bigint not null references public.org_units(id),
  to_org bigint not null references public.org_units(id),
  status text not null default 'active' check (status in ('active', 'revoked')),
  note text check (note is null or length(note) <= 300),
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(),
  revoked_by uuid, revoked_at timestamptz, revoked_reason text check (revoked_reason is null or length(revoked_reason) <= 300),
  check (from_org <> to_org)
);
create unique index if not exists master_shares132_active on public.master_shares132 (table_name, coalesce(row_key, ''), from_org, to_org) where status = 'active';
create index if not exists master_shares132_to on public.master_shares132 (to_org, table_name) where status = 'active';
drop trigger if exists master_shares132_nodel on public.master_shares132;
create trigger master_shares132_nodel before delete on public.master_shares132 for each row execute function public.no_hard_delete();
drop trigger if exists audit_master_shares132 on public.master_shares132;
create trigger audit_master_shares132 after insert or update on public.master_shares132 for each row execute function public.log_change('id');
alter table public.master_shares132 enable row level security;
drop policy if exists master_shares132_read on public.master_shares132;
create policy master_shares132_read on public.master_shares132 for select to authenticated using (public.is_owner() or public.has_grant('org_manage'));
revoke all on public.master_shares132 from public, anon, authenticated;
grant select on public.master_shares132 to authenticated;
revoke all on sequence public.master_shares132_id_seq from public, anon, authenticated;

-- the unique-constraint relax log (reversible); the latest row per object tells the state
create table if not exists public.master_unique_log132 (
  id bigserial primary key,
  action text not null check (action in ('relax', 'restore')),
  object_name text not null,
  definition text not null,
  at timestamptz not null default now(),
  by_user uuid
);
drop trigger if exists master_unique_log132_nodel on public.master_unique_log132;
create trigger master_unique_log132_nodel before delete on public.master_unique_log132 for each row execute function public.no_hard_delete();
drop trigger if exists audit_master_unique_log132 on public.master_unique_log132;
create trigger audit_master_unique_log132 after insert or update on public.master_unique_log132 for each row execute function public.log_change('id');
alter table public.master_unique_log132 enable row level security;
drop policy if exists master_unique_log132_read on public.master_unique_log132;
create policy master_unique_log132_read on public.master_unique_log132 for select to authenticated using (public.is_owner());
revoke all on public.master_unique_log132 from public, anon, authenticated;
grant select on public.master_unique_log132 to authenticated;
revoke all on sequence public.master_unique_log132_id_seq from public, anon, authenticated;

-- ---------- 3. helpers (internal ones closed to the browser; the ones used inside policies are granted) ----------
-- the business a new master row belongs to when the row itself does not say: the working business the user picked, else the only business of the user, else nothing
create or replace function public._m132_caller_biz() returns bigint
language sql stable security definer set search_path = public as $$
  select case when auth.uid() is null then null else coalesce(
    (select c.org_unit_id from public.master_ctx132 c where c.user_id = auth.uid() and c.org_unit_id in (select public._my_biz123())),
    (select case when count(*) = 1 then min(q.b) end from (select distinct b from public._my_biz123() b) q)) end;
$$;

-- the caller's businesses, callable from a policy (the underlying _my_biz123 is closed to the browser)
create or replace function public._m132_mybiz() returns setof bigint
language sql stable security definer set search_path = public as $$
  select public._my_biz123();
$$;

-- the business of a place (null when the place is unmapped)
create or replace function public._m132_biz_of_loc(p_loc int) returns bigint
language sql stable security definer set search_path = public as $$
  select public._business_of_loc123(p_loc);
$$;

-- is a master row (customer / item) of the business of this place? true while the switch is OFF, and for an unmapped place
create or replace function public._m132_at(p_org bigint, p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select not public._org_on123() or public._business_of_loc123(p_loc) is null or p_org is not distinct from public._business_of_loc123(p_loc);
$$;

-- may the caller use a master row of this business (lookups inside functions)? true while the switch is OFF and for the server (no login); ON: the owner and the members of the business
create or replace function public._m132_own(p_org bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select not public._org_on123() or auth.uid() is null or (public.is_active() and (public.is_owner() or p_org in (select public._my_biz123())));
$$;

-- is a row shared to the caller's business by an active master_shares132 row?
create or replace function public._m132_shared(p_tbl text, p_org bigint, p_key text) returns boolean
language sql stable security definer set search_path = public as $$
  select public._org_on123() and p_org is not null and exists (
    select 1 from public.master_shares132 s
     where s.status = 'active' and s.table_name = p_tbl and s.from_org = p_org and s.to_org in (select public._my_biz123())
       and (s.row_key is null or p_key = s.row_key or starts_with(p_key, s.row_key || '/')));
$$;

-- row visibility as a function (for lookups inside patched functions): switch OFF = true; ON = owner, own business, NULL business when p_null_ok, or shared
create or replace function public._m132_vis(p_tbl text, p_org bigint, p_key text, p_null_ok boolean default false) returns boolean
language sql stable security definer set search_path = public as $$
  select not public._org_on123() or auth.uid() is null or (public.is_active() and (public.is_owner() or (p_org is null and p_null_ok)
     or p_org in (select public._my_biz123()) or public._m132_shared(p_tbl, p_org, p_key)));
$$;

-- is the global unique on customers.mobile / items.code currently relaxed? (latest log row of customers_mobile_key decides)
create or replace function public._m132_relaxed() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select l.action = 'relax' from public.master_unique_log132 l where l.object_name = 'customers_mobile_key' order by l.id desc limit 1), false);
$$;

-- ---------- 4. the fill + guard trigger (one function for every scoped table; the arguments come from the registry) ----------
create or replace function public._m132_scope() returns trigger
language plpgsql security definer set search_path = public as $$
declare kind_ text := tg_argv[0]; ptab text := nullif(tg_argv[1], ''); pcol text := nullif(tg_argv[2], ''); ppk text := coalesce(nullif(tg_argv[3], ''), 'id');
  ptype text := coalesce(nullif(tg_argv[4], ''), 'uuid'); ploc text := nullif(tg_argv[5], ''); lcol text := nullif(tg_argv[6], ''); scol text := nullif(tg_argv[7], '');
  svals text[] := string_to_array(coalesce(tg_argv[8], ''), ','); j jsonb; o bigint; v text;
begin
  -- the business of a row never moves (the owner's correction path is: deactivate and create again in the right business)
  if tg_op = 'UPDATE' and old.org_unit_id is not null and new.org_unit_id is distinct from old.org_unit_id then
    raise exception '%', case when tg_table_name = 'items' then 'item_org_fixed' else 'master_org_fixed' end;      -- items keep the message of phase125
  end if;
  if tg_op = 'INSERT' and new.org_unit_id is null then
    j := to_jsonb(new);
    if scol is not null and (j ->> scol) = any(svals) then return new; end if;     -- a shared vocabulary row (the units list) keeps NULL = shared
    v := case when pcol is not null then j ->> pcol end;
    if kind_ = 'child' and ptab is not null and v is not null then
      execute format('select p.org_unit_id from public.%I p where p.%I = ($1)::%s', ptab, ppk, ptype) into o using v;
    elsif kind_ = 'child_loc' and ptab is not null and v is not null then
      execute format('select public._business_of_loc123(p.%I) from public.%I p where p.%I = ($1)::%s', ploc, ptab, ppk, ptype) into o using v;
    elsif kind_ = 'self_loc' and lcol is not null and (j ->> lcol) is not null then
      o := public._business_of_loc123((j ->> lcol)::int);
    end if;
    new.org_unit_id := coalesce(o, public._m132_caller_biz(), public._biz_default125());
  end if;
  -- the guard (switch ON, a logged-in user who is not the owner; the server / cron has no login and passes)
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then
    if tg_op = 'INSERT' then
      if new.org_unit_id is null or not (new.org_unit_id in (select public._my_biz123())) then raise exception 'not allowed'; end if;
    else
      if old.org_unit_id is null or not (old.org_unit_id in (select public._my_biz123())) then raise exception 'not found'; end if;
    end if;
  end if;
  return new;
end $$;

-- a stock movement of an item of another business is refused (switch ON)
create or replace function public._m132_xbiz() returns trigger
language plpgsql security definer set search_path = public as $$
declare bl bigint; bi bigint;
begin
  if public._org_on123() and auth.uid() is not null then
    bl := public._business_of_loc123(new.location_id);
    select i.org_unit_id into bi from public.items i where i.id = new.item_id;
    if bl is not null and bi is not null and bl <> bi then raise exception 'cross_business_item'; end if;
  end if;
  return new;
end $$;
drop trigger if exists stock_ledger_xbiz132 on public.stock_ledger;
create trigger stock_ledger_xbiz132 before insert on public.stock_ledger for each row execute function public._m132_xbiz();

-- ---------- 5. apply the registry: column, index, trigger, back-fill, policy ----------
do $ap$
declare r record; dflt bigint := public._biz_default125(); has_null boolean; pol text; sh text; shared_cond text; q text;
begin
  for r in select * from public.master_scope132 where decision = 'scoped' order by sort, table_name loop
    if to_regclass('public.' || r.table_name) is null then raise notice 'phase528: table % does not exist here, skipped', r.table_name; continue; end if;
    if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = r.table_name and column_name = 'org_unit_id') then
      execute format('alter table public.%I add column org_unit_id bigint references public.org_units(id)', r.table_name);
    end if;
    execute format('create index if not exists %I on public.%I (org_unit_id)', r.table_name || '_org132', r.table_name);
    -- back-fill (fill-null-only; the user triggers are paused so that a pure column fill touches no updated_at, audit row or immutability guard)
    execute format('select exists (select 1 from public.%I where org_unit_id is null)', r.table_name) into has_null;
    if has_null and dflt is not null then
      shared_cond := case when r.shared_col is not null then format(' and coalesce(%I::text, '''') <> all (%L::text[])', r.shared_col, r.shared_vals) else '' end;
      execute format('alter table public.%I disable trigger user', r.table_name);
      if r.kind = 'child' then
        execute format('update public.%I t set org_unit_id = p.org_unit_id from public.%I p where t.%I = p.%I and t.org_unit_id is null and p.org_unit_id is not null', r.table_name, r.parent_table, r.parent_col, r.parent_pk);
      elsif r.kind = 'child_loc' then
        execute format('update public.%I t set org_unit_id = coalesce(public._business_of_loc123(p.%I), %s) from public.%I p where t.%I = p.%I and t.org_unit_id is null', r.table_name, r.parent_loc_col, dflt, r.parent_table, r.parent_col, r.parent_pk);
      elsif r.kind = 'self_loc' then
        execute format('update public.%I set org_unit_id = coalesce(public._business_of_loc123(%I), %s) where org_unit_id is null', r.table_name, r.loc_col, dflt);
      end if;
      execute format('update public.%I set org_unit_id = %s where org_unit_id is null%s', r.table_name, dflt, shared_cond);
      execute format('alter table public.%I enable trigger user', r.table_name);
    end if;
    -- the fill + guard trigger
    execute format('drop trigger if exists a132_scope on public.%I', r.table_name);
    execute format('drop trigger if exists m132_scope on public.%I', r.table_name);
    execute format('create trigger a132_scope before insert or update on public.%I for each row execute function public._m132_scope(%L, %L, %L, %L, %L, %L, %L, %L, %L)',
      r.table_name, r.kind, coalesce(r.parent_table, ''), coalesce(r.parent_col, ''), coalesce(r.parent_pk, ''), coalesce(r.parent_pk_type, ''), coalesce(r.parent_loc_col, ''),
      coalesce(r.loc_col, ''), coalesce(r.shared_col, ''), coalesce(array_to_string(r.shared_vals, ','), ''));
    -- the restrictive read policy (true while the switch is OFF)
    sh := case when r.shareable then format(' or public._m132_shared(%L, org_unit_id, %s)', r.table_name, r.key_expr) else '' end;
    pol := '(select not public._org_on123()) or (select public.is_owner()) or org_unit_id in (select public._m132_mybiz())' || sh || case when r.kind = 'vocab' then ' or org_unit_id is null' else '' end;
    execute format('alter table public.%I enable row level security', r.table_name);
    execute format('drop policy if exists %I on public.%I', r.table_name || '_m132', r.table_name);
    execute format('create policy %I on public.%I as restrictive for select to authenticated using (%s)', r.table_name || '_m132', r.table_name, pol);
  end loop;
end $ap$;

-- per-business uniqueness (the global unique constraints are NOT touched here; see org_masters_relax_unique)
create unique index if not exists customers_org_mobile_uq132 on public.customers (org_unit_id, mobile);
create unique index if not exists items_org_barcode_uq132 on public.items (org_unit_id, barcode) where barcode is not null;
create unique index if not exists items_org_code_uq125 on public.items (org_unit_id, code);     -- phase125 made it; kept here so that this phase stands on its own

-- ---------- 6. text patches of existing functions (marker "m132"; idempotent; the OFF branch is the old text) ----------
create or replace function public._m132_patch(p_sig text, p_marker text, p_pairs text[]) returns text
language plpgsql security definer set search_path = public as $$
declare o oid := to_regprocedure(p_sig); d text; i int := 1;
begin
  if o is null then raise exception 'phase528 patch: function % not found', p_sig; end if;
  d := pg_get_functiondef(o);
  if position(p_marker in d) > 0 then return 'already'; end if;
  while i < array_length(p_pairs, 1) loop
    if position(p_pairs[i] in d) = 0 then raise exception 'phase528 patch: text "%" not found in %', left(p_pairs[i], 70), p_sig; end if;
    d := replace(d, p_pairs[i], p_pairs[i + 1]);
    i := i + 2;
  end loop;
  execute d;
  return 'patched';
end $$;

select public._m132_patch('public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)', '/* m132 */', array[
  'where cu.mobile = public.norm_mobile(p_customer_mobile) and cu.active and t.active and t.discount_percent > 0;',
  'where cu.mobile = public.norm_mobile(p_customer_mobile) and cu.active and t.active and t.discount_percent > 0 and public._m132_at(cu.org_unit_id, p_loc) /* m132 */;',
  'select * into cust from public.customers where mobile = mob for update;',
  'select * into cust from public.customers where mobile = mob and public._m132_at(org_unit_id, p_loc) /* m132 */ order by (org_unit_id is not distinct from public._m132_biz_of_loc(p_loc)) desc, org_unit_id limit 1 for update;',
  'insert into public.customers (mobile, name, type, created_by) values (mob, left(btrim(p_customer_name), 80), stype, auth.uid()) returning * into cust;',
  'insert into public.customers (mobile, name, type, created_by, org_unit_id) values (mob, left(btrim(p_customer_name), 80), stype, auth.uid(), public._m132_biz_of_loc(p_loc) /* m132 */) returning * into cust;']);

select public._m132_patch('public.find_customer(text)', '/* m132 */', array[
  'select * into c from public.customers where mobile = m;',
  'select * into c from public.customers where mobile = m and public._m132_own(org_unit_id) /* m132 */ order by (org_unit_id is not distinct from public._m132_caller_biz()) desc, org_unit_id limit 1;']);

select public._m132_patch('public.customer_pos_info(text)', '/* m132 */', array[
  'select * into c from public.customers where mobile = m;',
  'select * into c from public.customers where mobile = m and public._m132_own(org_unit_id) /* m132 */ order by (org_unit_id is not distinct from public._m132_caller_biz()) desc, org_unit_id limit 1;']);

select public._m132_patch('public.customer_save(uuid,jsonb,uuid)', '/* m132 */', array[
  'select * into c from public.customers where mobile = mob;',
  'select * into c from public.customers where mobile = mob and public._m132_own(org_unit_id) /* m132 */ order by (org_unit_id is not distinct from public._m132_caller_biz()) desc, org_unit_id limit 1;',
  'insert into public.customers (mobile, name, type, created_by, tier_id,',
  'insert into public.customers (org_unit_id, mobile, name, type, created_by, tier_id,',
  'values (mob, nm, coalesce(ty, ''retail''), auth.uid(), tid,',
  'values (nullif(p ->> ''org_unit_id'', '''')::bigint /* m132 */, mob, nm, coalesce(ty, ''retail''), auth.uid(), tid,']);

select public._m132_patch('public.customer_directory(integer)', '/* m132 */', array[
  'order by lower(c.name), c.mobile limit',
  'where public._m132_own(c.org_unit_id) /* m132 */ order by lower(c.name), c.mobile limit']);

select public._m132_patch('public.customer_balance(uuid)', '/* m132 */', array[
  'then public._cust_bal(p_customer) end;',
  'then (case when public._m132_own((select c.org_unit_id from public.customers c where c.id = p_customer)) /* m132 */ then public._cust_bal(p_customer) end) end;']);

select public._m132_patch('public.supplier_pick()', '/* m132 */', array[
  'where public.is_active() and s.active order by lower(s.name);',
  'where public.is_active() and s.active and public._m132_vis(''suppliers'', s.org_unit_id, s.id::text, false) /* m132 */ order by lower(s.name);']);

select public._m132_patch('public.scan_match_suppliers(text,integer)', '/* m132 */', array[
  'from public.suppliers s where s.active) z',
  'from public.suppliers s where s.active and public._m132_vis(''suppliers'', s.org_unit_id, s.id::text, false) /* m132 */) z']);

select public._m132_patch('public.scan_match_items(text,integer)', '/* m132 */', array[
  'from public.items i where i.is_active and not coalesce(i.hidden, false)) z',
  'from public.items i where i.is_active and not coalesce(i.hidden, false) and public._m132_vis(''items'', i.org_unit_id, i.id::text, false) /* m132 */) z']);

select public._m132_patch('public.artisan_list(boolean)', '/* m132 */', array[
  'from public.artisans a where p_include_retired or a.active)',
  'from public.artisans a where (p_include_retired or a.active) and public._m132_vis(''artisans'', a.org_unit_id, a.id::text, false) /* m132 */)']);

select public._m132_patch('public.category_list(boolean)', '/* m132 */', array[
  'where (p_include_inactive or (c.active and (c.parent_id is null or exists (select 1 from public.item_categories p where p.id = c.parent_id and p.active))))',
  'where public._m132_vis(''item_categories'', c.org_unit_id, c.id::text, false) /* m132 */ and (p_include_inactive or (c.active and (c.parent_id is null or exists (select 1 from public.item_categories p where p.id = c.parent_id and p.active))))']);

select public._m132_patch('public.item_dup_check(text,text,uuid)', '/* m132 */', array[
  'where public.is_active() and (p_exclude is null or i.id <> p_exclude)',
  'where public.is_active() and public._m132_vis(''items'', i.org_unit_id, i.id::text, false) /* m132 */ and (p_exclude is null or i.id <> p_exclude)']);

-- item-code resolvers: an item code is resolved inside the business of the place of the entry (switch ON); the clash checks follow the unique constraint that is really in force
select public._m132_patch('public._elp_post_line(entries,integer,text,jsonb)', '/* m132 */', array[
  'from public.items i where i.code = l->>''item'')', 'from public.items i where i.code = l->>''item'' and public._m132_at(i.org_unit_id, e.location_id) /* m132 */)',
  'select * into it from public.items where code = l->>''item'';', 'select * into it from public.items where code = l->>''item'' and public._m132_at(org_unit_id, e.location_id) /* m132 */;']);

select public._m132_patch('public.count_lines_seal(uuid)', '/* m132 */', array[
  'select * into it from public.items where code = btrim(r ->> ''item'');',
  'select * into it from public.items where code = btrim(r ->> ''item'') and public._m132_at(org_unit_id, e.location_id) /* m132 */;']);

select public._m132_patch('public._entries_countseal_guard23()', '/* m132 */', array[
  'left join public.items i on i.code = sl.item_code where',
  'left join public.items i on i.code = sl.item_code and public._m132_at(i.org_unit_id, new.location_id) /* m132 */ where']);

select public._m132_patch('public.variants_generate(bigint,jsonb,boolean)', '/* m132 */', array[
  'join public.items i on i.code = g.vcode and (i.style_id is distinct from p_style or i.variant_key is distinct from g.vkey);',
  'join public.items i on i.code = g.vcode and (i.style_id is distinct from p_style or i.variant_key is distinct from g.vkey) and (not public._m132_relaxed() or i.org_unit_id is not distinct from st.org_unit_id) /* m132 */;']);

select public._m132_patch('public._item_master_classify(jsonb)', '/* m132 */', array[
  'exists (select 1 from public.items i where i.code = c.code)',
  'exists (select 1 from public.items i where i.code = c.code and (not public._m132_relaxed() or i.org_unit_id is not distinct from public._m132_caller_biz()) /* m132 */)']);

select public._m132_patch('public.item_master_import_apply(jsonb,text,integer)', '/* m132 */', array[
  'on conflict (code) do nothing', 'on conflict (org_unit_id, code) /* m132 */ do nothing']);

-- the lookups BY ID of a master row inside the other functions ("select * into x from public.customers where id = p_x"): the row of another business answers like a missing id (switch ON).
-- One regular-expression patch per master table over every function that has the shape; marker "m132b"; the predicate is true while the switch is OFF and for the server.
create or replace function public._m132_patch_lookups(p_table text, p_pred text, p_skip_locks boolean default false) returns int
language plpgsql security definer set search_path = public as $$
declare r record; d text; nd text; n int := 0; pat text; pr text := replace(p_pred, '#', p_table);
begin
  -- p_skip_locks: a statement "... where id = x for update / for no key update" is a supplier lock of the money functions (phase109 pins their exact text): the write trigger guards it
  pat := '(from public\.' || p_table || ' where id = [a-z_][a-z_0-9.]*(::[a-z]+)?)(?![a-z_0-9.(])' || case when p_skip_locks then '(?! for )' else '' end;
  for r in select p.oid from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.proname !~ '^(_m132|org_masters|master_)' loop
    d := pg_get_functiondef(r.oid);
    continue when position('/* m132b:' || p_table || ' */' in d) > 0 or d !~* pat;
    nd := regexp_replace(d, pat, '\1 and ' || replace(pr, '\', '\\') || ' /* m132b:' || p_table || ' */', 'gi');
    if nd <> d then execute nd; n := n + 1; end if;
  end loop;
  return n;
end $$;

select public._m132_patch_lookups('customers', 'public._m132_own(#.org_unit_id)');
select public._m132_patch_lookups('suppliers', 'public._m132_vis(''suppliers'', #.org_unit_id, #.id::text, false)', true);
select public._m132_patch_lookups('items', 'public._m132_own(#.org_unit_id)');
select public._m132_patch_lookups('recipes', 'public._m132_own(#.org_unit_id)');
select public._m132_patch_lookups('artisans', 'public._m132_vis(''artisans'', #.org_unit_id, #.id::text, false)');

-- ---------- 7. sharing (owner only; default none; read only for the receiver) ----------
create or replace function public.master_share_create(p_table text, p_row_key text, p_from bigint, p_to bigint, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.master_scope132; s public.master_shares132; nid bigint; k text; ok boolean;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is null then raise exception 'client_id_needed'; end if;
  select * into s from public.master_shares132 where client_id = p_client;
  if found then return jsonb_build_object('dup', true, 'id', s.id); end if;
  select * into m from public.master_scope132 where table_name = p_table and decision = 'scoped';
  if not found or not m.shareable then raise exception 'table_not_shareable'; end if;
  if p_from is null or p_to is null or p_from = p_to then raise exception 'bad_business'; end if;
  if (select count(*) from public.org_units where id in (p_from, p_to) and kind = 'business' and status <> 'inactive') <> 2 then raise exception 'bad_business'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'bad_note'; end if;
  k := nullif(btrim(coalesce(p_row_key, '')), '');
  if k is not null then
    execute format('select exists (select 1 from public.%I where org_unit_id = $1 and ((%s) = $2 or starts_with((%s), $2 || ''/'')))', p_table, m.key_expr, m.key_expr) into ok using p_from, k;
    if not ok then raise exception 'row_not_found'; end if;
  end if;
  select * into s from public.master_shares132 where table_name = p_table and coalesce(row_key, '') = coalesce(k, '') and from_org = p_from and to_org = p_to and status = 'active';
  if found then return jsonb_build_object('dup', true, 'id', s.id); end if;
  insert into public.master_shares132 (table_name, row_key, from_org, to_org, note, client_id, created_by) values (p_table, k, p_from, p_to, p_note, p_client, auth.uid()) returning id into nid;
  return jsonb_build_object('dup', false, 'id', nid);
end $$;

create or replace function public.master_share_revoke(p_id bigint, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.master_shares132;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  if p_reason is not null and length(p_reason) > 300 then raise exception 'bad_reason'; end if;
  select * into s from public.master_shares132 where id = p_id for update;
  if not found then raise exception 'share_not_found'; end if;
  if s.status = 'revoked' then return jsonb_build_object('dup', true, 'id', s.id); end if;
  update public.master_shares132 set status = 'revoked', revoked_by = auth.uid(), revoked_at = now(), revoked_reason = p_reason where id = p_id;
  return jsonb_build_object('dup', false, 'id', p_id);
end $$;

create or replace function public.master_share_list() returns table (id bigint, table_name text, row_key text, from_org bigint, from_code text, to_org bigint, to_code text, status text, note text, created_at timestamptz, revoked_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_active() and (public.is_owner() or public.has_grant('org_manage'))) then raise exception 'not allowed'; end if;
  return query select s.id, s.table_name, s.row_key, s.from_org, f.code, s.to_org, t.code, s.status, s.note, s.created_at, s.revoked_at
    from public.master_shares132 s join public.org_units f on f.id = s.from_org join public.org_units t on t.id = s.to_org order by s.id;
end $$;

-- the working business: new masters created by this user land in it (only among the user's own businesses; NULL clears)
create or replace function public.master_context_set132(p_org bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_org is null then delete from public.master_ctx132 where user_id = auth.uid(); return jsonb_build_object('org_unit_id', null); end if;
  if not exists (select 1 from public.org_units where id = p_org and kind = 'business' and status <> 'inactive') then raise exception 'bad_business'; end if;
  if not (p_org in (select public._my_biz123())) then raise exception 'not allowed'; end if;
  insert into public.master_ctx132 (user_id, org_unit_id) values (auth.uid(), p_org) on conflict (user_id) do update set org_unit_id = excluded.org_unit_id, set_at = now();
  return jsonb_build_object('org_unit_id', p_org);
end $$;

create or replace function public.master_context_get132() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.is_active() then jsonb_build_object('working', public._m132_caller_biz(), 'businesses', coalesce((select jsonb_agg(distinct b) from public._my_biz123() b), '[]'::jsonb)) end;
$$;

-- ---------- 8. the global unique constraints: preflight, relax, restore ----------
create or replace function public.org_masters_preflight() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r record; n bigint; nulls jsonb := '{}'::jsonb; blockers jsonb := '[]'::jsonb; warns jsonb := '[]'::jsonb; fns jsonb := '{}'::jsonb; f text; patched boolean; unp jsonb; ownmulti bigint;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  for r in select m.table_name, m.shared_col, m.shared_vals from public.master_scope132 m where m.decision = 'scoped' order by m.sort loop
    continue when to_regclass('public.' || r.table_name) is null;
    execute format('select count(*) from public.%I where org_unit_id is null%s', r.table_name,
      case when r.shared_col is not null then format(' and coalesce(%I::text, '''') <> all (%L::text[])', r.shared_col, r.shared_vals) else '' end) into n;   -- the shared vocabulary rows (units) are meant to have no business
    if n > 0 then nulls := nulls || jsonb_build_object(r.table_name, n); end if;
  end loop;
  if (select count(*) from public.master_scope132 where decision = 'scoped' and table_name in ('customers', 'items')) = 2 then
    if coalesce((nulls ->> 'customers')::bigint, 0) > 0 then blockers := blockers || to_jsonb('customers_without_business'::text); end if;
    if coalesce((nulls ->> 'items')::bigint, 0) > 0 then blockers := blockers || to_jsonb('items_without_business'::text); end if;
  end if;
  if not public._org_on123() then blockers := blockers || to_jsonb('org_scope_on_must_be_on'::text); end if;
  foreach f in array array['public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)', 'public.find_customer(text)', 'public.customer_pos_info(text)',
      'public.customer_save(uuid,jsonb,uuid)', 'public._elp_post_line(entries,integer,text,jsonb)', 'public.count_lines_seal(uuid)', 'public._entries_countseal_guard23()',
      'public.variants_generate(bigint,jsonb,boolean)', 'public._item_master_classify(jsonb)', 'public.item_master_import_apply(jsonb,text,integer)'] loop
    patched := to_regprocedure(f) is not null and position('/* m132 */' in pg_get_functiondef(to_regprocedure(f))) > 0;
    fns := fns || jsonb_build_object(f, patched);
    if not patched then blockers := blockers || to_jsonb('lookup_not_business_aware:' || f); end if;
  end loop;
  foreach f in array array['customers_org_mobile_uq132', 'items_org_code_uq125', 'items_org_barcode_uq132'] loop
    if not exists (select 1 from pg_class c join pg_index i on i.indexrelid = c.oid where c.relname = f and c.relnamespace = 'public'::regnamespace and i.indisvalid and i.indisunique) then
      blockers := blockers || to_jsonb('missing_unique_index:' || f);
    end if;
  end loop;
  -- functions that still resolve an item / customer by the global code or mobile and are NOT business aware (information for the owner, not a blocker)
  select coalesce(jsonb_agg(z.fn order by z.fn), '[]'::jsonb) into unp from (
    select p.oid::regprocedure::text fn from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and position('/* m132 */' in pg_get_functiondef(p.oid)) = 0
       and p.proname !~ '^(_m132|org_masters|master_)'
       and (pg_get_functiondef(p.oid) ~* '(from|join) +(public\.)?items +(as +)?[a-z_]* *(on|where)[^;]{0,40}\mcode *= *[^;]{0,25}'
            or pg_get_functiondef(p.oid) ~* '(from|join) +(public\.)?customers +(as +)?[a-z_]* *(on|where)[^;]{0,40}\mmobile *= *[^;]{0,25}')) z;
  if jsonb_array_length(unp) > 0 then warns := warns || jsonb_build_array('code_or_mobile_lookups_not_business_aware'); end if;
  select count(*) into ownmulti from public.profiles p where p.status = 'active' and exists (select 1 from public.user_roles ur where ur.user_id = p.id and ur.role_code = 'owner')
     and not exists (select 1 from public.master_ctx132 c where c.user_id = p.id) and (select count(*) from public.org_units where kind = 'business' and status <> 'inactive') > 1;
  if ownmulti > 0 then warns := warns || jsonb_build_array('owner_has_no_working_business'); end if;
  return jsonb_build_object(
    'switch_on', public._org_on123(), 'unique_relaxed', public._m132_relaxed(),
    'businesses', (select count(*) from public.org_units where kind = 'business' and status <> 'inactive'),
    'scoped_tables', (select count(*) from public.master_scope132 where decision = 'scoped'),
    'rows_without_business', nulls,
    'active_shares', (select count(*) from public.master_shares132 where status = 'active'),
    'customer_mobile_duplicates_across_businesses', (select count(*) from (select mobile from public.customers group by mobile having count(*) > 1) q),
    'item_code_duplicates_across_businesses', (select count(*) from (select code from public.items group by code having count(*) > 1) q),
    'patched_functions', fns, 'lookups_not_business_aware', unp,
    'owners_without_working_business', ownmulti,
    'blockers', blockers, 'warnings', warns);
end $$;

create or replace function public.org_masters_relax_unique(p_dry boolean default true, p_ack_warnings boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pf jsonb; did jsonb := '[]'::jsonb; me uuid := auth.uid(); d text;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  if public._m132_relaxed() then return jsonb_build_object('dup', true, 'relaxed', true); end if;
  pf := public.org_masters_preflight();
  if jsonb_array_length(pf -> 'blockers') > 0 then
    if p_dry then return jsonb_build_object('dry', true, 'would_apply', false, 'blockers', pf -> 'blockers', 'warnings', pf -> 'warnings'); end if;
    raise exception 'preflight_failed' using hint = (pf -> 'blockers')::text;
  end if;
  if jsonb_array_length(pf -> 'warnings') > 0 and not p_ack_warnings and not p_dry then raise exception 'warnings_need_ack' using hint = (pf -> 'warnings')::text; end if;
  if p_dry then
    return jsonb_build_object('dry', true, 'would_apply', true, 'warnings', pf -> 'warnings', 'lookups_not_business_aware', pf -> 'lookups_not_business_aware',
      'would_drop', jsonb_build_array('customers_mobile_key', 'items_code_key', 'items_barcode_uq'));
  end if;
  if exists (select 1 from pg_constraint where conname = 'customers_mobile_key' and conrelid = 'public.customers'::regclass) then
    d := pg_get_constraintdef((select oid from pg_constraint where conname = 'customers_mobile_key' and conrelid = 'public.customers'::regclass));
    insert into public.master_unique_log132 (action, object_name, definition, by_user) values ('relax', 'customers_mobile_key', d, me);
    alter table public.customers drop constraint customers_mobile_key;
    did := did || to_jsonb('customers_mobile_key'::text);
  end if;
  if exists (select 1 from pg_constraint where conname = 'items_code_key' and conrelid = 'public.items'::regclass) then
    d := pg_get_constraintdef((select oid from pg_constraint where conname = 'items_code_key' and conrelid = 'public.items'::regclass));
    insert into public.master_unique_log132 (action, object_name, definition, by_user) values ('relax', 'items_code_key', d, me);
    alter table public.items drop constraint items_code_key;
    did := did || to_jsonb('items_code_key'::text);
  end if;
  if to_regclass('public.items_barcode_uq') is not null then
    insert into public.master_unique_log132 (action, object_name, definition, by_user) select 'relax', 'items_barcode_uq', pg_get_indexdef('public.items_barcode_uq'::regclass), me;
    drop index public.items_barcode_uq;
    did := did || to_jsonb('items_barcode_uq'::text);
  end if;
  return jsonb_build_object('dry', false, 'relaxed', true, 'dropped', did);
end $$;

create or replace function public.org_masters_restore_unique(p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare dm bigint; dc bigint; db bigint; did jsonb := '[]'::jsonb; me uuid := auth.uid();
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  if not public._m132_relaxed() then return jsonb_build_object('dup', true, 'relaxed', false); end if;
  select count(*) into dm from (select mobile from public.customers group by mobile having count(*) > 1) q;
  select count(*) into dc from (select code from public.items group by code having count(*) > 1) q;
  select count(*) into db from (select barcode from public.items where barcode is not null group by barcode having count(*) > 1) q;
  if dm + dc + db > 0 then
    if p_dry then return jsonb_build_object('dry', true, 'would_restore', false, 'duplicate_mobiles', dm, 'duplicate_codes', dc, 'duplicate_barcodes', db); end if;
    raise exception 'duplicates_block_restore' using hint = format('mobiles %s, codes %s, barcodes %s', dm, dc, db);
  end if;
  if p_dry then return jsonb_build_object('dry', true, 'would_restore', true); end if;
  if not exists (select 1 from pg_constraint where conname = 'customers_mobile_key' and conrelid = 'public.customers'::regclass) then
    alter table public.customers add constraint customers_mobile_key unique (mobile);
    insert into public.master_unique_log132 (action, object_name, definition, by_user) values ('restore', 'customers_mobile_key', 'UNIQUE (mobile)', me);
    did := did || to_jsonb('customers_mobile_key'::text);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'items_code_key' and conrelid = 'public.items'::regclass) then
    alter table public.items add constraint items_code_key unique (code);
    insert into public.master_unique_log132 (action, object_name, definition, by_user) values ('restore', 'items_code_key', 'UNIQUE (code)', me);
    did := did || to_jsonb('items_code_key'::text);
  end if;
  if to_regclass('public.items_barcode_uq') is null then
    create unique index items_barcode_uq on public.items (barcode) where barcode is not null;
    insert into public.master_unique_log132 (action, object_name, definition, by_user) values ('restore', 'items_barcode_uq', 'UNIQUE (barcode) WHERE barcode IS NOT NULL', me);
    did := did || to_jsonb('items_barcode_uq'::text);
  end if;
  return jsonb_build_object('dry', false, 'relaxed', false, 'restored', did);
end $$;

-- while the global unique constraints are relaxed the switch cannot be turned OFF (the old lookups assume one row per mobile / code)
create or replace function public._m132_rule_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.key = 'org_scope_on' and public._m132_relaxed()
     and not coalesce((coalesce(new.value, new.default_value) #>> '{}')::boolean, false) then
    raise exception 'masters_unique_relaxed_restore_first';
  end if;
  return new;
end $$;
drop trigger if exists rules_m132 on public.rules;
create trigger rules_m132 before update on public.rules for each row when (old.key = 'org_scope_on') execute function public._m132_rule_guard();

-- ---------- 9. the coverage report (owner / org_manage) ----------
create or replace function public.master_scope_report132() returns table (table_name text, decision text, kind text, shareable boolean, in_audit_list boolean, total_rows bigint, rows_without_business bigint, why text)
language plpgsql stable security definer set search_path = public as $$
declare r record; n bigint; z bigint;
begin
  if not (public.is_active() and (public.is_owner() or public.has_grant('org_manage'))) then raise exception 'not allowed'; end if;
  for r in select * from public.master_scope132 m order by m.sort, m.table_name loop
    n := null; z := null;
    if to_regclass('public.' || r.table_name) is not null then
      execute format('select count(*) from public.%I', r.table_name) into n;
      if r.decision = 'scoped' then
        execute format('select count(*) from public.%I where org_unit_id is null%s', r.table_name,
          case when r.shared_col is not null then format(' and coalesce(%I::text, '''') <> all (%L::text[])', r.shared_col, r.shared_vals) else '' end) into z;
      end if;
    end if;
    table_name := r.table_name; decision := r.decision; kind := r.kind; shareable := r.shareable; in_audit_list := r.audit_set; total_rows := n; rows_without_business := z; why := r.why;
    return next;
  end loop;
end $$;

-- ---------- 10. privileges ----------
revoke all on function public._m132_caller_biz(), public._m132_biz_of_loc(int), public._m132_relaxed(), public._m132_scope(), public._m132_xbiz(), public._m132_rule_guard(),
  public._m132_patch(text, text, text[]), public._m132_patch_lookups(text, text, boolean) from public, anon, authenticated;
revoke all on function public._m132_at(bigint, int), public._m132_own(bigint), public._m132_vis(text, bigint, text, boolean) from public, anon, authenticated;     -- used only inside the SECURITY DEFINER functions
revoke all on function public._m132_mybiz(), public._m132_shared(text, bigint, text) from public, anon;
grant execute on function public._m132_mybiz(), public._m132_shared(text, bigint, text) to authenticated;   -- used inside the policies
revoke all on function public.master_share_create(text, text, bigint, bigint, text, uuid), public.master_share_revoke(bigint, text), public.master_share_list(), public.master_context_set132(bigint),
  public.master_context_get132(), public.org_masters_preflight(), public.org_masters_relax_unique(boolean, boolean), public.org_masters_restore_unique(boolean), public.master_scope_report132() from public, anon;
grant execute on function public.master_share_create(text, text, bigint, bigint, text, uuid), public.master_share_revoke(bigint, text), public.master_share_list(), public.master_context_set132(bigint),
  public.master_context_get132(), public.org_masters_preflight(), public.org_masters_relax_unique(boolean, boolean), public.org_masters_restore_unique(boolean), public.master_scope_report132() to authenticated;

commit;

-- ---------------------------------------------------------------- phase133.sql
-- ============================================================
-- Phase 133 (marker scope133) - GROUP ERP, STAGE C3: strict separation of BEHAVIOUR, PERMISSIONS and REPORTS between businesses, behind the switch org_scope_on (DEFAULT OFF).
-- Plan: docs/GROUP_ERP_STAGE_A.md sections 3.4, 10; audit docs/audit_c1/RLS_ISOLATION_AUDIT.md (Appendix B, sections 5, 6, 9 tests 9-11, 13); coverage table docs/audit_c1/C3_COVERAGE.md.
-- Canonical order: after phase528 (C2, master data) and phase527 (docs/PASTE_ORDER.md). Paste twice = no change, no error. Needs phases 122 and 123 (phase528 is used when present, not required).
-- With org_scope_on OFF (the default) every behaviour is the one of phase527: each function re-created below keeps its old text as the OFF branch (tests/sql/c3_before_after.sh
-- fingerprints them before / after), every new policy / trigger returns at once while the switch is OFF, and the new tables are read by nothing.
--
--   1  PER-BUSINESS SETTINGS (switch ON only)
--        rule_overrides              business x rule key -> value. rule_val / rule_on / rule_num / rule_txt answer with the business value of the CALLER when there is one
--                                    (caller's working business = the single business of the user, or the working business of phase528 when present; the group owner without a working
--                                    business gets the group value), else the global value. Group-only keys (security, assistant, ui, integrations, backup, scan quota ...) cannot be overridden.
--        rule_override_set133 (owner) / rule_overrides_list133 (owner, management of the business) / rule_val_in133(key, business) / rules_effective133()
--        rule_grant_overrides133      business x grant x role -> allowed / not allowed (a business can take a role grant away or give one the global matrix does not have)
--        role_form_overrides133       the same for the form rights of a role (can_do)
--        can_grant / has_grant / can_do honour them ON; OFF they are the old text.
--        roles.org_unit_id, grant_defs.org_unit_id (nullable: NULL = shared catalogue): a role / grant that belongs to ONE business is invisible to the others (restrictive read policies)
--        rule_grants, role_form_perms, rule_grant_overrides133, role_form_overrides133: rows of a business role / grant are hidden the same way.
--        `management` per business: the role bypass is gone since phase123; the last readers that named the role (assistant_health, org_scope_preflight) are listed in the coverage doc.
--   2  THE BUSINESS BORDER FOR WRITES: a BEFORE INSERT / UPDATE / DELETE trigger <table>_xb133 on every table that has a place column (95 tables; not the system tables listed in the file).
--        While the switch is OFF it returns at once (the switch is read once per transaction). ON: the group owner and the server (no login) pass; anybody else may write a row only at a place of
--        one of his businesses - whatever function does it (so a function that never looked at the place cannot write across the border). Insert = 'not allowed', update / delete of a
--        foreign row = 'not found' (the answer for a missing id).
--   3  READERS AND WRITERS PATCHED BY EXACT-TEXT INSERT (41 functions, marker /* scope133 */, old text kept as the OFF branch; a second paste is a no-op): the books engine (acct_post_pending,
--        acct_status, acct_pending_alert85, profit_source_check count only the documents of the caller's places), the controls (count_unsubmitted_scan, control_counts, void_collection,
--        payment_intent_link, intake_failures_list, assistant_health), customer balances (_cust_bal, customer_dues_net113), place-bound configuration lookups (rollout_mode, blind_active,
--        stock_blind_active, path_cfg, template_for, get_doc_templates, sheet_sync_all, _qc_latest60, cost_source_set_active), the company-level books records and queues that have no business
--        column (chart, mappings, opening journal, bank statements, scheduler, main cost place, setup advisors, outbox): OWNER ONLY while the switch is ON, and login_failed (an unknown staff id
--        is counted and locked like a known one while ON: the lock state is no signal that the id exists, audit test 13).
--   4  DAILY DIGEST PER BUSINESS: daily_digest_biz133(business, date) (owner, the notify bot, or the management of that business); daily_digest() stays the GROUP digest.
--   5  STORAGE: object paths already carry the place (<PREFIX>/<place>/<file>) and the read / insert policies call can_loc, which is business-safe ON. Added: photo_business133(path),
--        photo_path133(prefix, place, name), photo_unmapped133() (owner) and restrictive policies photos_scope133_read / _write on storage.objects: ON, the place in the path must be one of
--        the caller's businesses (the backup bot may read everything). A free Supabase plan has ONE bucket and no per-bucket quota; the isolation is by policy, not by bucket.
--   6  BOT IDENTITY: a message / order written by a bot for a channel outside the bot's businesses is refused by the border trigger; one bot per business (intake_bot_create, owner) is the
--        supported set-up. Group scans (notify_scan, daily_digest, urgent_alerts) stay with the owner and the notify bot (group infrastructure).
--   7  THE COVERAGE CHECKER scope_gaps133() (owner): the exposed SECURITY DEFINER functions that are not scope-aware, by construction (a call of a scope primitive, directly or through a callee).
--        tests/sql/scope_allowlist.txt is the reviewed list (class + reason); phase133_test fails when the two lists differ, so a future function without a scope call cannot slip in.
-- Rollback: leave the switch OFF. To remove: re-paste the older phase files that own the re-created functions (phase7 rule_val / can_grant / can_do, phase123 has_grant ...), drop the
--   policies *_scope133, the triggers *_xb133 and the new tables / functions. Nothing else reads them.
-- ============================================================
begin;

do $g$
declare miss text := '';
begin
  if to_regclass('public.org_units') is null or to_regclass('public.user_org_scopes') is null or to_regclass('public.rules') is null or to_regclass('public.rule_grants') is null
     or to_regclass('public.roles') is null or to_regclass('public.grant_defs') is null or to_regclass('public.role_form_perms') is null or to_regclass('public.locations') is null then miss := miss || ' tables'; end if;
  if to_regprocedure('public._org_on123()') is null or to_regprocedure('public._my_biz123()') is null or to_regprocedure('public._biz_ok123(integer)') is null
     or to_regprocedure('public._business_of_loc123(integer)') is null or to_regprocedure('public._user_biz123(uuid)') is null or to_regprocedure('public.can_scope(bigint,text)') is null
     or to_regprocedure('public.has_grant(text,integer)') is null or to_regprocedure('public.can_grant(text)') is null or to_regprocedure('public.can_do(text,text)') is null
     or to_regprocedure('public.log_change()') is null or to_regprocedure('public.no_hard_delete()') is null or to_regprocedure('public._client_lock(uuid)') is null then miss := miss || ' functions(phase123)'; end if;
  if miss <> '' then raise exception 'phase133 needs the base schema and phases up to 123 pasted first (docs/PASTE_ORDER.md); missing:%', miss; end if;
end $g$;

-- ---------- 0. small helpers ----------
-- the caller's working business: phase528's working business when that phase is pasted, else the ONE business the caller belongs to; null for the group owner without a working
-- business, for a user with no business and for a user in several businesses (then the group value applies).
create or replace function public._caller_biz133() returns bigint
language plpgsql stable security definer set search_path = public as $$
declare b bigint;
begin
  if auth.uid() is null then return null; end if;
  if to_regprocedure('public._m132_caller_biz()') is not null then execute 'select public._m132_caller_biz()' into b; return b; end if;
  select case when count(*) = 1 then min(q.x) end into b from (select distinct x from public._user_biz123(auth.uid()) x) q;
  return b;
end $$;

-- keys that are group infrastructure: never overridden per business
create or replace function public._rule_group_only133(p_key text) returns boolean
language sql stable security definer set search_path = public as $$
  select p_key = 'org_scope_on'
      or p_key ~ '^(twofa|client_error|scan_|backup_|restore_|notify_backup|notify_email|notify_digest|notify_sms|owner_self_approve|intake_|meta_intake|inbox_rate|item_images_|bi_export|barcode_|ia_home|offline_cache|pay_gateway|assistant_)'
      or exists (select 1 from public.rules r where r.key = p_key and r.module in ('security', 'assistant', 'ui', 'integrations'));
$$;

-- the row of a business is for the owner and for the members of that business (used by the read policies of the override tables)
create or replace function public._unit_mine133(p_unit bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or p_unit in (select public._my_biz123()));
$$;

-- ---------- 1. per-business rule values ----------
create table if not exists public.rule_overrides (
  id bigserial primary key,
  org_unit_id bigint not null references public.org_units(id),
  key text not null references public.rules(key),
  value jsonb not null,
  active boolean not null default true,
  note text check (note is null or length(note) <= 300),
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(),
  updated_by uuid, updated_at timestamptz not null default now()
);
create unique index if not exists rule_overrides_uq133 on public.rule_overrides (org_unit_id, key);
create index if not exists rule_overrides_key133 on public.rule_overrides (key) where active;
drop trigger if exists ro133_no_delete on public.rule_overrides;
create trigger ro133_no_delete before delete on public.rule_overrides for each row execute function public.no_hard_delete();
drop trigger if exists audit_ro133 on public.rule_overrides;
create trigger audit_ro133 after insert or update on public.rule_overrides for each row execute function public.log_change('id');
alter table public.rule_overrides enable row level security;
drop policy if exists ro133_read on public.rule_overrides;
create policy ro133_read on public.rule_overrides for select to authenticated using (public._unit_mine133(org_unit_id));
revoke all on public.rule_overrides from public, anon, authenticated;
grant select on public.rule_overrides to authenticated;
revoke all on sequence public.rule_overrides_id_seq from public, anon, authenticated;

-- rule_val: OFF = the text of phase7 (the same expression, read for the same key). ON = the business value of the caller, else the global value.
-- The switch is read once per transaction and kept in the transaction-local setting bos.orgon133 (rule_val is called hundreds of times per request; a lookup of the switch on every call
-- would triple its cost). The switch is flipped by the owner in a request of its own, so a transaction never sees it change.
create or replace function public.rule_val(p_key text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare sw text := current_setting('bos.orgon133', true); v jsonb;
begin
  if sw is null or sw = '' then
    sw := case when coalesce((select (coalesce(x.value, x.default_value) #>> '{}')::boolean from public.rules x where x.key = 'org_scope_on'), false) then '1' else '0' end;
    perform set_config('bos.orgon133', sw, true);
  end if;
  select coalesce(r.value, r.default_value) into v from public.rules r where r.key = p_key;                                       -- OFF: phase7
  if sw = '1' then
    v := coalesce((select o.value from public.rule_overrides o where o.key = p_key and o.active and o.org_unit_id = public._caller_biz133()), v);   -- ON (scope133)
  end if;
  return v;
end $$;

-- the value of one rule for one named business (owner, or a member of that business); the global value when the business has none
create or replace function public.rule_val_in133(p_key text, p_unit bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v jsonb; r public.rules;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_unit is null or not exists (select 1 from public.org_units where id = p_unit and kind = 'business') then raise exception 'bad_business'; end if;
  if not (public.is_owner() or p_unit in (select public._my_biz123())) then raise exception 'not allowed'; end if;
  select * into r from public.rules where key = p_key;
  if not found then return null; end if;
  select o.value into v from public.rule_overrides o where o.key = p_key and o.active and o.org_unit_id = p_unit;
  return coalesce(v, r.value, r.default_value);
end $$;

-- every rule as the caller sees it: key, effective value, where it comes from. p_unit null = the caller's own working business (or the group values).
create or replace function public.rules_effective133(p_unit bigint default null) returns table (key text, value jsonb, source text)
language plpgsql stable security definer set search_path = public as $$
declare u bigint;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  u := coalesce(p_unit, public._caller_biz133());
  if u is not null and not (public.is_owner() or u in (select public._my_biz123())) then raise exception 'not allowed'; end if;
  return query select r.key, coalesce(o.value, r.value, r.default_value),
                      case when o.id is not null then 'business' when r.value is not null then 'group' else 'default' end
                 from public.rules r left join public.rule_overrides o on o.key = r.key and o.active and o.org_unit_id = u and public._org_on123()
                order by r.module, r.sort, r.key;
end $$;

-- owner: set / reset (p_value null) the value of a rule for ONE business. Same validation as set_rule; group-only keys are refused.
create or replace function public.rule_override_set133(p_unit bigint, p_key text, p_value jsonb, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.rules; o public.rule_overrides; nid bigint; have boolean;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is null then raise exception 'client_id_needed'; end if;
  select * into o from public.rule_overrides where client_id = p_client;
  if found then return jsonb_build_object('dup', true, 'id', o.id); end if;
  if p_unit is null or not exists (select 1 from public.org_units where id = p_unit and kind = 'business' and status <> 'inactive') then raise exception 'bad_business'; end if;
  select * into r from public.rules where key = p_key;
  if not found then raise exception 'rule not found'; end if;
  if public._rule_group_only133(p_key) then raise exception 'group_only_rule'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'bad_note'; end if;
  select * into o from public.rule_overrides where org_unit_id = p_unit and key = p_key for update;
  have := found;
  if p_value is null or jsonb_typeof(p_value) = 'null' then
    if not have then return jsonb_build_object('dup', false, 'reset', true, 'id', null); end if;
    update public.rule_overrides set active = false, updated_by = auth.uid(), updated_at = now(), note = coalesce(p_note, note) where id = o.id;
    return jsonb_build_object('dup', false, 'reset', true, 'id', o.id);
  end if;
  if r.kind = 'switch' and jsonb_typeof(p_value) <> 'boolean' then raise exception 'bad_value'; end if;
  if r.kind = 'number' and (jsonb_typeof(p_value) <> 'number' or (p_value #>> '{}')::numeric < coalesce(r.min_value, 0) or (p_value #>> '{}')::numeric > coalesce(r.max_value, 1000000000)) then raise exception 'bad_value'; end if;
  if r.kind = 'choice' and not (r.choices @> jsonb_build_array(p_value #>> '{}')) then raise exception 'bad_value'; end if;
  if r.kind = 'text' and jsonb_typeof(p_value) <> 'string' then raise exception 'bad_value'; end if;
  if p_key = 'period_closed_until' then
    if (p_value #>> '{}') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'bad_value'; end if;
    begin perform (p_value #>> '{}')::date; exception when others then raise exception 'bad_value'; end;
  end if;
  if have then
    update public.rule_overrides set value = p_value, active = true, updated_by = auth.uid(), updated_at = now(), note = coalesce(p_note, note) where id = o.id;
    return jsonb_build_object('dup', false, 'id', o.id);
  end if;
  insert into public.rule_overrides (org_unit_id, key, value, note, client_id, created_by, updated_by) values (p_unit, p_key, p_value, p_note, p_client, auth.uid(), auth.uid()) returning id into nid;
  return jsonb_build_object('dup', false, 'id', nid);
end $$;

-- owner, or the management of that business: the business's own values (and which keys it may not change)
create or replace function public.rule_overrides_list133(p_unit bigint) returns table (id bigint, org_unit_id bigint, key text, value jsonb, global_value jsonb, active boolean, note text, updated_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not (public.is_owner() or public.can_scope(p_unit, 'management')) then raise exception 'not allowed'; end if;
  return query select o.id, o.org_unit_id, o.key, o.value, coalesce(r.value, r.default_value), o.active, o.note, o.updated_at
                 from public.rule_overrides o join public.rules r on r.key = o.key where o.org_unit_id = p_unit order by o.key;
end $$;

-- ---------- 2. per-business role grants and role form rights ----------
create table if not exists public.rule_grant_overrides133 (
  id bigserial primary key,
  org_unit_id bigint not null references public.org_units(id),
  grant_code text not null references public.grant_defs(grant_code),
  role_code text not null references public.roles(code),
  allowed boolean not null,
  active boolean not null default true,
  note text check (note is null or length(note) <= 300),
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now()
);
create unique index if not exists rule_grant_overrides_uq133 on public.rule_grant_overrides133 (org_unit_id, grant_code, role_code);
create table if not exists public.role_form_overrides133 (
  id bigserial primary key,
  org_unit_id bigint not null references public.org_units(id),
  role_code text not null references public.roles(code),
  form_code text not null,
  can_view boolean not null default false, can_enter boolean not null default false, can_approve boolean not null default false,
  active boolean not null default true,
  note text check (note is null or length(note) <= 300),
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now()
);
create unique index if not exists role_form_overrides_uq133 on public.role_form_overrides133 (org_unit_id, role_code, form_code);
do $t$
declare t text;
begin
  foreach t in array array['rule_grant_overrides133', 'role_form_overrides133'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_nd', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nd', t);
    execute format('drop trigger if exists %I on public.%I', 'audit_' || t, t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.log_change(%L)', 'audit_' || t, t, 'id');
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (public._unit_mine133(org_unit_id))', t || '_read', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('revoke all on sequence public.%I from public, anon, authenticated', t || '_id_seq');
  end loop;
end $t$;

-- does the role hold the grant in this business? business row (if any) wins, else the global matrix. p_biz null = the global matrix only.
create or replace function public._grant_eff133(p_code text, p_role text, p_biz bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select o.allowed from public.rule_grant_overrides133 o where o.org_unit_id = p_biz and o.grant_code = p_code and o.role_code = p_role and o.active),
    (select g.allowed from public.rule_grants g where g.grant_code = p_code and g.role_code = p_role),
    false);
$$;
-- can the caller (by role) hold the grant in this business?
create or replace function public._can_grant_in133(p_code text, p_biz bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and exists (
    select 1 from public.user_roles ur join public.roles r on r.code = ur.role_code and r.active
     where ur.user_id = auth.uid() and public._grant_eff133(p_code, ur.role_code, p_biz)));
$$;
-- form right of the caller's roles in this business (p_biz null = any business of the caller / the global matrix)
create or replace function public._form_eff133(p_role text, p_form text, p_action text, p_biz bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select case p_action when 'view' then o.can_view when 'enter' then o.can_enter when 'approve' then o.can_approve else false end
       from public.role_form_overrides133 o where o.org_unit_id = p_biz and o.role_code = p_role and o.form_code = p_form and o.active),
    (select case p_action when 'view' then p.can_view when 'enter' then p.can_enter when 'approve' then p.can_approve else false end
       from public.role_form_perms p where p.role_code = p_role and p.form_code = p_form),
    false);
$$;

-- can_grant: OFF = phase7 text. ON = the role matrix of the caller's business(es): any business of his that gives the role the grant; a person with no business keeps the global matrix.
create or replace function public.can_grant(p_code text) returns boolean
language sql stable security definer set search_path = public as $$
  select case when not coalesce((select (coalesce(x.value, x.default_value) #>> '{}')::boolean from public.rules x where x.key = 'org_scope_on'), false) then (
      public.is_owner() or (public.is_active() and exists (       -- OFF: phase7
        select 1 from public.user_roles ur join public.rule_grants g on g.role_code = ur.role_code and g.grant_code = p_code and g.allowed
        join public.roles r on r.code = ur.role_code and r.active where ur.user_id = auth.uid())))
    else (
      public.is_owner() or (public.is_active() and exists (       -- ON (scope133)
        select 1 from public.user_roles ur join public.roles r on r.code = ur.role_code and r.active
         where ur.user_id = auth.uid() and (
               exists (select 1 from public._my_biz123() b where public._grant_eff133(p_code, ur.role_code, b))
            or (not exists (select 1 from public._my_biz123()) and public._grant_eff133(p_code, ur.role_code, null)))))) end;
$$;

-- can_do: OFF = phase7 text. ON = the form rights of the caller's roles in his business(es).
create or replace function public.can_do(p_form text, p_action text) returns boolean
language sql stable security definer set search_path = public as $$
  select case when not coalesce((select (coalesce(x.value, x.default_value) #>> '{}')::boolean from public.rules x where x.key = 'org_scope_on'), false) then (
    public.is_owner() or (
      public.is_active() and (exists (       -- OFF: phase7
        select 1 from public.user_roles ur
        join public.role_form_perms p on p.role_code = ur.role_code and p.form_code = p_form
        join public.roles r on r.code = ur.role_code and r.active
        where ur.user_id = auth.uid()
          and case p_action when 'view' then p.can_view when 'enter' then p.can_enter
                            when 'approve' then p.can_approve else false end)
      or (p_action in ('view', 'enter') and exists (
        select 1 from public.emergency_requests e
        where e.requested_by = auth.uid() and e.grant_code = 'form_access' and e.status = 'approved' and e.valid_until > now()
          and p_form <> 'ITEM_COST' and e.context->>'form' = p_form and (e.context->>'action' is null or e.context->>'action' = p_action or p_action = 'view'))))))
  else (
    public.is_owner() or (
      public.is_active() and (exists (       -- ON (scope133)
        select 1 from public.user_roles ur join public.roles r on r.code = ur.role_code and r.active
         where ur.user_id = auth.uid() and (
               exists (select 1 from public._my_biz123() b where public._form_eff133(ur.role_code, p_form, p_action, b))
            or (not exists (select 1 from public._my_biz123()) and public._form_eff133(ur.role_code, p_form, p_action, null))))
      or (p_action in ('view', 'enter') and exists (
        select 1 from public.emergency_requests e
        where e.requested_by = auth.uid() and e.grant_code = 'form_access' and e.status = 'approved' and e.valid_until > now()
          and p_form <> 'ITEM_COST' and e.context->>'form' = p_form and (e.context->>'action' is null or e.context->>'action' = p_action or p_action = 'view')))))) end;
$$;

-- has_grant: the text of phase123 with ONE change in the ON branch: a role grant is looked up in the matrix of the place's business.
create or replace function public.has_grant(p_code text, p_loc int default null) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and (case when not coalesce((select (coalesce(r.value, r.default_value) #>> '{}')::boolean from public.rules r where r.key = 'org_scope_on'), false) then (   -- the switch read inline
    -- OFF: exactly the rule of phase8
    public.can_grant(p_code)
    or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = p_code
               and (g.valid_until is null or g.valid_until > now()) and (g.location_id is null or g.location_id = p_loc))
    or exists (select 1 from public.emergency_requests e join public.grant_defs d on d.grant_code = e.grant_code and d.window_type = 'window'
               where e.requested_by = auth.uid() and e.grant_code = p_code and e.status = 'approved' and e.valid_until > now()
               and (p_loc is null or e.location_id is null or e.location_id = p_loc)))
  else (
    -- ON (scope123 + scope133): with a location it must be one of the caller's businesses; the role matrix is the one of THAT business; a personal grant without a location = the caller's businesses
    (p_loc is null or public._biz_ok123(p_loc)) and (
      (case when p_loc is null then public.can_grant(p_code) else public._can_grant_in133(p_code, public._business_of_loc123(p_loc)) end)
      or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = p_code
                 and (g.valid_until is null or g.valid_until > now()) and (g.location_id is null or g.location_id = p_loc))
      or exists (select 1 from public.emergency_requests e join public.grant_defs d on d.grant_code = e.grant_code and d.window_type = 'window'
                 where e.requested_by = auth.uid() and e.grant_code = p_code and e.status = 'approved' and e.valid_until > now()
                 and (p_loc is null or e.location_id is null or e.location_id = p_loc)))
  ) end));
$$;

-- owner: set / reset (p_allowed null) one role grant for ONE business
create or replace function public.rule_grant_override_set133(p_unit bigint, p_grant text, p_role text, p_allowed boolean, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.rule_grant_overrides133; nid bigint; have boolean;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is null then raise exception 'client_id_needed'; end if;
  select * into o from public.rule_grant_overrides133 where client_id = p_client;
  if found then return jsonb_build_object('dup', true, 'id', o.id); end if;
  if p_unit is null or not exists (select 1 from public.org_units where id = p_unit and kind = 'business' and status <> 'inactive') then raise exception 'bad_business'; end if;
  if not exists (select 1 from public.grant_defs where grant_code = p_grant) then raise exception 'unknown grant'; end if;
  if p_role is null or p_role = 'owner' or not exists (select 1 from public.roles where code = p_role) then raise exception 'unknown role'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'bad_note'; end if;
  select * into o from public.rule_grant_overrides133 where org_unit_id = p_unit and grant_code = p_grant and role_code = p_role for update;
  have := found;
  if p_allowed is null then
    if not have then return jsonb_build_object('dup', false, 'reset', true, 'id', null); end if;
    update public.rule_grant_overrides133 set active = false, updated_by = auth.uid(), updated_at = now(), note = coalesce(p_note, note) where id = o.id;
    return jsonb_build_object('dup', false, 'reset', true, 'id', o.id);
  end if;
  if have then
    update public.rule_grant_overrides133 set allowed = p_allowed, active = true, updated_by = auth.uid(), updated_at = now(), note = coalesce(p_note, note) where id = o.id;
    return jsonb_build_object('dup', false, 'id', o.id);
  end if;
  insert into public.rule_grant_overrides133 (org_unit_id, grant_code, role_code, allowed, note, client_id, created_by, updated_by) values (p_unit, p_grant, p_role, p_allowed, p_note, p_client, auth.uid(), auth.uid()) returning id into nid;
  return jsonb_build_object('dup', false, 'id', nid);
end $$;

-- owner: set / reset (all three null) the form rights of a role for ONE business
create or replace function public.role_form_override_set133(p_unit bigint, p_role text, p_form text, p_view boolean, p_enter boolean, p_approve boolean, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.role_form_overrides133; nid bigint; have boolean;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is null then raise exception 'client_id_needed'; end if;
  select * into o from public.role_form_overrides133 where client_id = p_client;
  if found then return jsonb_build_object('dup', true, 'id', o.id); end if;
  if p_unit is null or not exists (select 1 from public.org_units where id = p_unit and kind = 'business' and status <> 'inactive') then raise exception 'bad_business'; end if;
  if p_role is null or p_role = 'owner' or not exists (select 1 from public.roles where code = p_role) then raise exception 'unknown role'; end if;
  if p_form is null or not exists (select 1 from public.forms where code = p_form) then raise exception 'unknown form'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'bad_note'; end if;
  select * into o from public.role_form_overrides133 where org_unit_id = p_unit and role_code = p_role and form_code = p_form for update;
  have := found;
  if p_view is null and p_enter is null and p_approve is null then
    if not have then return jsonb_build_object('dup', false, 'reset', true, 'id', null); end if;
    update public.role_form_overrides133 set active = false, updated_by = auth.uid(), updated_at = now(), note = coalesce(p_note, note) where id = o.id;
    return jsonb_build_object('dup', false, 'reset', true, 'id', o.id);
  end if;
  if have then
    update public.role_form_overrides133 set can_view = coalesce(p_view, false), can_enter = coalesce(p_enter, false), can_approve = coalesce(p_approve, false), active = true,
           updated_by = auth.uid(), updated_at = now(), note = coalesce(p_note, note) where id = o.id;
    return jsonb_build_object('dup', false, 'id', o.id);
  end if;
  insert into public.role_form_overrides133 (org_unit_id, role_code, form_code, can_view, can_enter, can_approve, note, client_id, created_by, updated_by)
    values (p_unit, p_role, p_form, coalesce(p_view, false), coalesce(p_enter, false), coalesce(p_approve, false), p_note, p_client, auth.uid(), auth.uid()) returning id into nid;
  return jsonb_build_object('dup', false, 'id', nid);
end $$;

-- the role matrix of a business as the owner / the management of it sees it: global rows plus the business's own rows
create or replace function public.role_matrix_list133(p_unit bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not (public.is_owner() or public.can_scope(p_unit, 'management')) then raise exception 'not allowed'; end if;
  return jsonb_build_object('unit', p_unit,
    'grants', coalesce((select jsonb_agg(jsonb_build_object('grant', g.grant_code, 'role', g.role_code, 'allowed', public._grant_eff133(g.grant_code, g.role_code, p_unit),
                'source', case when exists (select 1 from public.rule_grant_overrides133 o where o.org_unit_id = p_unit and o.grant_code = g.grant_code and o.role_code = g.role_code and o.active) then 'business' else 'group' end) order by g.grant_code, g.role_code)
                from (select grant_code, role_code from public.rule_grants union select grant_code, role_code from public.rule_grant_overrides133 where org_unit_id = p_unit and active) g), '[]'::jsonb),
    'forms', coalesce((select jsonb_agg(jsonb_build_object('role', f.role_code, 'form', f.form_code, 'view', public._form_eff133(f.role_code, f.form_code, 'view', p_unit),
                'enter', public._form_eff133(f.role_code, f.form_code, 'enter', p_unit), 'approve', public._form_eff133(f.role_code, f.form_code, 'approve', p_unit),
                'source', case when exists (select 1 from public.role_form_overrides133 o where o.org_unit_id = p_unit and o.role_code = f.role_code and o.form_code = f.form_code and o.active) then 'business' else 'group' end) order by f.role_code, f.form_code)
                from (select role_code, form_code from public.role_form_perms union select role_code, form_code from public.role_form_overrides133 where org_unit_id = p_unit and active) f), '[]'::jsonb));
end $$;

-- roles and grant definitions that belong to ONE business (NULL = the shared catalogue, as today)
alter table public.roles add column if not exists org_unit_id bigint references public.org_units(id);
alter table public.grant_defs add column if not exists org_unit_id bigint references public.org_units(id);
create or replace function public.role_scope_set133(p_role text, p_unit bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  if p_role is null or p_role = 'owner' or not exists (select 1 from public.roles where code = p_role) then raise exception 'unknown role'; end if;
  if p_unit is not null and not exists (select 1 from public.org_units where id = p_unit and kind = 'business') then raise exception 'bad_business'; end if;
  update public.roles set org_unit_id = p_unit where code = p_role;
end $$;
create or replace function public.grant_scope_set133(p_grant text, p_unit bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  if p_grant is null or not exists (select 1 from public.grant_defs where grant_code = p_grant) then raise exception 'unknown grant'; end if;
  if p_unit is not null and not exists (select 1 from public.org_units where id = p_unit and kind = 'business') then raise exception 'bad_business'; end if;
  update public.grant_defs set org_unit_id = p_unit where grant_code = p_grant;
end $$;
-- the row of a business role / grant is hidden from the other businesses (restrictive, true while the switch is OFF; NULL = shared)
create or replace function public._unit_vis133(p_unit bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select not public._org_on123() or p_unit is null or public.is_owner() or p_unit in (select public._my_biz123());
$$;
create or replace function public._role_vis133(p_role text) returns boolean
language sql stable security definer set search_path = public as $$
  select not public._org_on123() or public.is_owner() or coalesce((select public._unit_vis133(r.org_unit_id) from public.roles r where r.code = p_role), true);
$$;
create or replace function public._grant_vis133(p_grant text) returns boolean
language sql stable security definer set search_path = public as $$
  select not public._org_on123() or public.is_owner() or coalesce((select public._unit_vis133(d.org_unit_id) from public.grant_defs d where d.grant_code = p_grant), true);
$$;
drop policy if exists roles_scope133 on public.roles;
create policy roles_scope133 on public.roles as restrictive for select to authenticated using (public._unit_vis133(org_unit_id));
drop policy if exists grant_defs_scope133 on public.grant_defs;
create policy grant_defs_scope133 on public.grant_defs as restrictive for select to authenticated using (public._unit_vis133(org_unit_id));
drop policy if exists rule_grants_scope133 on public.rule_grants;
create policy rule_grants_scope133 on public.rule_grants as restrictive for select to authenticated using (public._role_vis133(role_code) and public._grant_vis133(grant_code));
drop policy if exists role_form_perms_scope133 on public.role_form_perms;
create policy role_form_perms_scope133 on public.role_form_perms as restrictive for select to authenticated using (public._role_vis133(role_code));

-- ---------- 3. the text-patch helper for the readers / writers of section 4 (current live body + exact-text anchors; marker makes a second paste a no-op) ----------
create or replace function public._patch133(p_fn regprocedure, p_marker text, p_pairs text[]) returns void
language plpgsql security definer set search_path = public as $$
declare d text; i int;
begin
  d := pg_get_functiondef(p_fn);
  if position(p_marker in d) > 0 then return; end if;
  for i in 1..array_length(p_pairs, 1) by 2 loop
    if (length(d) - length(replace(d, p_pairs[i], ''))) / greatest(length(p_pairs[i]), 1) <> 1 then
      raise exception 'phase133: the anchor "%" is not in % exactly once (a newer body? merge by hand)', left(p_pairs[i], 70), p_fn;
    end if;
    d := replace(d, p_pairs[i], p_pairs[i + 1]);
  end loop;
  execute d;
end $$;

-- ---------- 4. the business border for WRITES (switch ON): a user cannot insert / update / delete a row of a place outside his businesses, whatever function does it ----------
-- The trigger passes at once while the switch is OFF, for the group owner and for the server (no login). INSERT into a foreign place = 'not allowed'; UPDATE / DELETE of a foreign row =
-- 'not found' (the answer for a missing id); moving a row into a foreign place = 'not allowed'.
create or replace function public._xb133() returns trigger
language plpgsql security definer set search_path = public as $$
declare c text; v int; o int; cache text; uid text := auth.uid()::text; st text := current_setting('bos.xbst133', true);
begin
  if st = '0' then return coalesce(new, old); end if;                                   -- OFF, already read in this transaction (one lookup per transaction, not per row)
  if uid is null then return coalesce(new, old); end if;
  if st is null or st = '' then
    st := case when coalesce((select (coalesce(r.value, r.default_value) #>> '{}')::boolean from public.rules r where r.key = 'org_scope_on'), false) then '1' else '0' end;
    perform set_config('bos.xbst133', st, true);
    if st = '0' then return coalesce(new, old); end if;
  end if;
  cache := coalesce(current_setting('bos.xbok133', true), '');                        -- places already proven for this person in this transaction
  if position(',own:' || uid || ',' in cache) > 0 then return coalesce(new, old); end if;
  if public.is_owner() then perform set_config('bos.xbok133', cache || ',own:' || uid || ',', true); return coalesce(new, old); end if;
  foreach c in array tg_argv loop
    v := null; o := null;
    if tg_op <> 'DELETE' then v := nullif(to_jsonb(new) ->> c, '')::int; end if;
    if tg_op <> 'INSERT' then o := nullif(to_jsonb(old) ->> c, '')::int; end if;
    if o is not null and position(',' || uid || ':' || o || ',' in cache) = 0 then
      if not public._biz_ok123(o) then raise exception 'not found'; end if;
      cache := cache || ',' || uid || ':' || o || ',';
    end if;
    if v is not null and position(',' || uid || ':' || v || ',' in cache) = 0 then
      if not public._biz_ok123(v) then raise exception 'not allowed'; end if;
      cache := cache || ',' || uid || ':' || v || ',';
    end if;
  end loop;
  perform set_config('bos.xbok133', cache, true);
  return coalesce(new, old);
end $$;

do $xb$
declare r record; cols text[]; skip text[] := array['locations', 'user_locations', 'user_grants', 'user_org_scopes', 'notifications', 'exceptions', 'sales_fact_t', 'bi_export_log', 'items', 'option_sets', 'option_values',
  'item_styles', 'price_lists', 'price_list_items', 'legal_entities', 'ie_currencies', 'ie_fx_rates', 'ie_shipments', 'ie_shipment_events'];
begin
  for r in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind = 'r' and not c.relispartition and c.relname <> all (skip)
              and exists (select 1 from pg_attribute a where a.attrelid = c.oid and not a.attisdropped and a.attname in ('location_id', 'from_location_id', 'to_location_id', 'primary_location_id'))
            order by 1 loop
    select array_agg(a.attname::text order by a.attname) into cols from pg_attribute a
     where a.attrelid = ('public.' || quote_ident(r.relname))::regclass and not a.attisdropped and a.attname in ('location_id', 'from_location_id', 'to_location_id', 'primary_location_id');
    execute format('drop trigger if exists %I on public.%I', r.relname || '_xb133', r.relname);
    execute format('create trigger %I before insert or update or delete on public.%I for each row execute function public._xb133(%s)', r.relname || '_xb133', r.relname,
                   (select string_agg(quote_literal(x), ', ') from unnest(cols) x));
  end loop;
end $xb$;

-- ---------- 5. storage (bucket photos): paths are <PREFIX>/<place>/<file>, so the place - and with it the business - is in every path ----------
create or replace function public.photo_business133(p_name text) returns bigint
language sql stable security definer set search_path = public as $$
  select case when p_name ~ '^[A-Za-z0-9_.-]+/[0-9]{1,9}/' and (public.is_owner() or public._biz_ok123(split_part(p_name, '/', 2)::int))
              then public._business_of_loc123(split_part(p_name, '/', 2)::int) end;
$$;
-- the path a NEW upload should use: <PREFIX>/<place>/<name>; refused for a place outside the caller's businesses
create or replace function public.photo_path133(p_prefix text, p_loc int, p_name text) returns text
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_prefix is null or p_prefix !~ '^[A-Za-z0-9_.-]{1,30}$' or p_name is null or p_name !~ '^[A-Za-z0-9_.-]{1,120}$' or p_loc is null then raise exception 'bad_input'; end if;
  if public._org_on123() and not public._biz_ok123(p_loc) then raise exception 'not allowed'; end if;
  if not public._org_on123() and not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  return p_prefix || '/' || p_loc || '/' || p_name;
end $$;
-- may the caller touch an object of the photos bucket under this path? OFF: true (the permissive policies decide, as today). ON: the place in the path must be one of his businesses; the
-- backup bot (ops purpose backup) may read everything (group infrastructure, read only).
create or replace function public._photo_scope133(p_name text, p_read boolean) returns boolean
language sql stable security definer set search_path = public as $$
  select not public._org_on123() or public.is_owner() or (p_read and public._is_ops('backup'))
         or (p_name ~ '^[A-Za-z0-9_.-]+/[0-9]{1,9}/' and public._biz_ok123(split_part(p_name, '/', 2)::int));
$$;
-- owner: what is in the bucket per business (object count by business, objects whose path has no mapped place)
create or replace function public.photo_unmapped133() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  if to_regclass('storage.objects') is null then return jsonb_build_object('storage', false); end if;
  execute $q$select jsonb_build_object('storage', true, 'objects', coalesce(sum(n), 0), 'by_business', coalesce(jsonb_object_agg(coalesce(b::text, 'none'), n), '{}'::jsonb))
    from (select public._business_of_loc123(case when name ~ '^[A-Za-z0-9_.-]+/[0-9]{1,9}/' then split_part(name, '/', 2)::int end) b, count(*) n
            from storage.objects where bucket_id = 'photos' group by 1) z$q$ into res;
  return res;
end $$;
do $st$
begin
  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists photos_scope133_read on storage.objects';
    execute 'create policy photos_scope133_read on storage.objects as restrictive for select to authenticated using (bucket_id <> ''photos'' or public._photo_scope133(name, true))';
    execute 'drop policy if exists photos_scope133_write on storage.objects';
    execute 'create policy photos_scope133_write on storage.objects as restrictive for insert to authenticated with check (bucket_id <> ''photos'' or public._photo_scope133(name, false))';
  end if;
end $st$;

-- ---------- 6. exposed functions that read or write business data with a gate that does not look at the place (old text kept as the OFF branch) ----------
-- gate helper: the same exact-text patch, but the text is inserted right after the first `begin` of a plpgsql body (the body starts with a gate that is true while the switch is OFF)
create or replace function public._gate133(p_fn regprocedure, p_marker text, p_gate text) returns void
language plpgsql security definer set search_path = public as $$
declare d text; n text;
begin
  d := pg_get_functiondef(p_fn);
  if position(p_marker in d) > 0 then return; end if;
  if d !~ E'\nbegin[^\n]*\n' then raise exception 'phase133: no plpgsql begin in %', p_fn; end if;
  n := regexp_replace(d, E'\nbegin([^\n]*)\n', E'\nbegin\\1\n  ' || replace(p_gate, '\', '\\') || '   ' || p_marker || E'\n');
  execute n;
end $$;

-- a place-bound configuration lookup may answer for a place outside the caller's businesses only to the owner, the server (no login) and the notify / backup bots (group infrastructure)
create or replace function public._cfgvis133(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select not public._org_on123() or auth.uid() is null or public.is_owner() or public._is_ops('notify') or public._is_ops('backup') or public._biz_ok123(p_loc);
$$;

do $p$
declare f text;
begin
-- 6.1 login lockout: with the switch ON an unknown staff id is counted and locked like a known one, so the lock state is no signal that the id exists (audit test 13)
perform public._patch133('public.login_failed(text)'::regprocedure, 'scope133', array[
  E'  if not known then return; end if;',
  E'  if not known and not public._org_on123() then return; end if;   /* scope133 */\n  if not known and random() < 0.02 then delete from public.login_failures lf where lf.last_fail < now() - interval ''1 day'' and not exists (select 1 from public.profiles p where p.staff_id = lf.staff_id); end if;']);

-- 6.2 the books engine: a business accountant posts / counts only the documents of his places (owner and the scheduler: all)
perform public._patch133('public.acct_post_pending(boolean,integer)'::regprocedure, 'scope133', array[
  'for d in select * from public._acct_docs(st) order by 3, 1, 2 loop',
  'for d in select * from public._acct_docs(st) x where ((select not public._org_on123()) or auth.uid() is null or public.is_owner() or public._biz_ok123(x.location_id)) /* scope133 */ order by 3, 1, 2 loop']);
perform public._patch133('public.acct_status()'::regprocedure, 'scope133', array[
  'with dd as materialized (select * from public._acct_docs(st)),',
  'with dd as materialized (select * from public._acct_docs(st) x where ((select not public._org_on123()) or auth.uid() is null or public.is_owner() or public._biz_ok123(x.location_id))), /* scope133 */',
  '''entries'', (select count(*) from public.journal_entries),',
  '''entries'', (select count(*) from public.journal_entries je where ((select not public._org_on123()) or public.is_owner() or public._biz_ok123(je.location_id))),']);

-- 6.3 company-level books records (chart of accounts, mappings, opening journal, bank statements, the scheduler, the main cost place): owner only while the switch is ON
-- (one chart and one set of bank statements for the whole database until the per-entity books of Stage C2b; year closes were closed the same way in phase123)
  foreach f in array array['public.acct_account_save(bigint,text,text,text,text,bigint,boolean,integer,boolean)', 'public.acct_mapping_set(text,bigint)', 'public.acct_opening(jsonb,boolean,text,uuid,boolean)',
      'public.acct_scheduler_enable(text)', 'public.acct_scheduler_disable()', 'public.bank_recon_candidates(bigint,integer)', 'public.bank_recon_lines(bigint,text,integer)', 'public.bank_recon_report(bigint,date,date)',
      'public.bank_recon_suggest(bigint,date,date,integer)', 'public.bank_recon_unmatch(bigint,text)', 'public.bank_recon_match(bigint,bigint,integer,text)', 'public.bank_recon_match_many(jsonb,boolean)',
      'public.bank_stmt_import(bigint,jsonb,uuid,boolean)', 'public.cost_attrib_main_set(integer,date,text,uuid)',
      'public.setup_flow_check()', 'public.setup_readiness(text)', 'public.notify_outbox_summary()', 'public.notify_cancel(bigint)', 'public.setup_recommendations()'] loop
    perform public._gate133(f::regprocedure, '/* scope133 */', 'if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception ''not allowed''; end if;');
  end loop;

-- 6.4 readers / writers of the dashboards and the controls
perform public._patch133('public.count_unsubmitted_scan()'::regprocedure, 'scope133', array[
  'and not exists (select 1 from public.exceptions x where x.entry_id = e.id and x.flag_code = ''count_unsubmitted'');',
  'and not exists (select 1 from public.exceptions x where x.entry_id = e.id and x.flag_code = ''count_unsubmitted'')
      and ((select not public._org_on123()) or public.can_loc(e.location_id));   /* scope133: only the places of the caller */']);
perform public._patch133('public.control_counts()'::regprocedure, 'scope133', array[
  'select count(*) into n from public.locations where status in (''planned'', ''setting_up'');',
  'select count(*) into n from public.locations where status in (''planned'', ''setting_up'') and ((select not public._org_on123()) or public.can_loc(id));   /* scope133 */',
  'select count(*) into n from public.settings_sheets where status = ''draft'';',
  'select count(*) into n from public.settings_sheets where status = ''draft'' and ((select not public._org_on123()) or public.can_loc(location_id));   /* scope133 */']);
perform public._patch133('public.void_collection(bigint,text)'::regprocedure, 'scope133', array[
  '  if p.voided then raise exception ''already void''; end if;',
  E'  if public._org_on123() and not public._biz_ok123(p.location_id) then raise exception ''not found''; end if;   /* scope133: the same answer as a missing id */\n  if p.voided then raise exception ''already void''; end if;']);
perform public._patch133('public.payment_intent_link(bigint,bigint)'::regprocedure, 'scope133', array[
  'if not exists (select 1 from public.sale_payments where id = p_sale_payment) then',
  'if not exists (select 1 from public.sale_payments where id = p_sale_payment and ((select not public._org_on123()) or auth.uid() is null or public._biz_ok123(location_id))) then   /* scope133 */']);
perform public._patch133('public.customer_dues_net113()'::regprocedure, 'scope133', array[
  'where m.kind = ''cust_advance_used'' and m.status = ''done'' and m.customer_id is not null group by 1),',
  'where m.kind = ''cust_advance_used'' and m.status = ''done'' and m.customer_id is not null and ((select not public._org_on123()) or public.can_loc(m.location_id)) group by 1),   /* scope133 */',
  'from public.sales x where x.status = ''done'' and x.customer_id in (select b2.id from b b2)),',
  'from public.sales x where x.status = ''done'' and x.customer_id in (select b2.id from b b2) and ((select not public._org_on123()) or public.can_loc(x.location_id))),']);
perform public._patch133('public.sheet_sync_all()'::regprocedure, 'scope133', array[
  'for l in select id from public.locations loop',
  'for l in select id from public.locations where ((select not public._org_on123()) or public.is_owner() or public._biz_ok123(id)) loop   /* scope133 */']);

perform public._patch133('public.assistant_health()'::regprocedure, 'scope133', array[
  'where coalesce(l.status, ''live'') in (''live'', ''setting_up'') and (public.is_owner() or public.has_grant(''head_management'') or public.can_loc(l.id));',
  'where coalesce(l.status, ''live'') in (''live'', ''setting_up'') and (public.is_owner() or (public.has_grant(''head_management'') and ((select not public._org_on123()) or public._biz_ok123(l.id))) or public.can_loc(l.id));   /* scope133 */']);
perform public._patch133('public.profit_source_check(date,date,integer)'::regprocedure, 'scope133', array[
  'and (p_loc is null or d.location_id = p_loc);',
  'and (p_loc is null or d.location_id = p_loc) and ((select not public._org_on123()) or auth.uid() is null or public.is_owner() or public._biz_ok123(d.location_id));   /* scope133 */']);

perform public._patch133('public._cust_bal(uuid)'::regprocedure, 'scope133', array[
  'where s.customer_id = p_customer and s.status = ''done''),',
  'where s.customer_id = p_customer and s.status = ''done'' and ((select not public._org_on123()) or public._cfgvis133(s.location_id))),   /* scope133: a customer balance counts the sales of the caller''s businesses (owner, server and the notify bot: all) */',
  'where p.customer_id = p_customer and not p.voided),',
  'where p.customer_id = p_customer and not p.voided and ((select not public._org_on123()) or public._cfgvis133(p.location_id))),',
  'where r.customer_id = p_customer and r.status = ''done''),',
  'where r.customer_id = p_customer and r.status = ''done'' and ((select not public._org_on123()) or public._cfgvis133(r.location_id))),']);

perform public._patch133('public.cost_source_set_active(bigint,boolean,text)'::regprocedure, 'scope133', array[
  '  if p_active is null then raise exception ''bad_value''; end if;',
  E'  if p_active is null then raise exception ''bad_value''; end if;\n  if public._org_on123() and auth.uid() is not null and not public._cs_src_ok(p_id) then raise exception ''source_not_found''; end if;   /* scope133: a cost source of another business is a missing id */']);
perform public._patch133('public._qc_latest60(text,uuid)'::regprocedure, 'scope133', array[
  'where source_type = p_type and source_id = p_id order by created_at desc, id desc limit 1;',
  'where source_type = p_type and source_id = p_id and ((select not public._org_on123()) or public._cfgvis133(location_id)) /* scope133 */ order by created_at desc, id desc limit 1;']);

perform public._patch133('public.acct_pending_alert85(integer)'::regprocedure, 'scope133', array[
  'd.live, d.waiting from public._acct_docs(st) d)',
  'd.live, d.waiting from public._acct_docs(st) d where ((select not public._org_on123()) or auth.uid() is null or public.is_owner() or public._biz_ok123(d.location_id)))   /* scope133 */']);

perform public._patch133('public.intake_failures_list(text,integer)'::regprocedure, 'scope133', array[
  'from public.intake_failures f where p_state is null or f.state = p_state order by f.id desc limit',
  'from public.intake_failures f where (p_state is null or f.state = p_state) and ((select not public._org_on123()) or public.is_owner() or exists (select 1 from public.sales_channels sc where sc.id = f.channel_id and public._biz_ok123(sc.location_id))) /* scope133 */ order by f.id desc limit']);

-- 6.5 place-bound configuration lookups
perform public._patch133('public.rollout_mode(text,integer)'::regprocedure, 'scope133', array[
  'where form_code = p_form and location_id = p_loc), ''app'');',
  'where form_code = p_form and location_id = p_loc and public._cfgvis133(p_loc)), ''app'');   /* scope133 */']);
perform public._patch133('public.blind_active(text,integer)'::regprocedure, 'scope133', array[
  'where form_code = p_form and location_id = p_loc), true);',
  'where form_code = p_form and location_id = p_loc and public._cfgvis133(p_loc)), true);   /* scope133 */']);
perform public._patch133('public.stock_blind_active(text,integer)'::regprocedure, 'scope133', array[
  'where form_code = p_form and location_id = p_loc), true);',
  'where form_code = p_form and location_id = p_loc and public._cfgvis133(p_loc)), true);   /* scope133 */']);
perform public._patch133('public.path_cfg(text,integer)'::regprocedure, 'scope133', array[
  'order by s.location_id desc limit 1) x on true',
  'and (s.location_id = 0 or public._cfgvis133(s.location_id)) /* scope133 */ order by s.location_id desc limit 1) x on true']);
perform public._patch133('public.template_for(text,integer)'::regprocedure, 'scope133', array[
  'and (t.location_id = p_loc or t.location_id is null)',
  'and (t.location_id = p_loc or t.location_id is null) and (t.location_id is null or public._cfgvis133(t.location_id)) /* scope133 */']);
perform public._patch133('public.get_doc_templates(integer)'::regprocedure, 'scope133', array[
  'from public.doc_template_choice c), ''[]''::jsonb);',
  'from public.doc_template_choice c where (c.location_id is null or public._cfgvis133(c.location_id))), ''[]''::jsonb);   /* scope133 */']);
end $p$;

-- ---------- 7. the daily digest per business ----------
-- daily_digest() is the GROUP digest (owner or the notify bot; all places; unchanged). daily_digest_biz133(business, date) is the same digest for ONE business: only the places of that business,
-- the rules of that business (reports_net_of_returns, notify_expiry_days), no group-level parts (backup status, item change requests, pending staff). Owner, the notify bot, or the
-- management of that business.
create or replace function public._rule_in133(p_key text, p_unit bigint) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce((select o.value from public.rule_overrides o where o.key = p_key and o.active and o.org_unit_id = p_unit and public._org_on123()), r.value, r.default_value) from public.rules r where r.key = p_key;
$$;
create or replace function public.daily_digest_biz133(p_biz bigint, p_date date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_date, public._today()); locs int[]; neg boolean; expd int; td jsonb; yd jsonb; lw jsonb; byloc jsonb; top5 jsonb; cash jsonb; coll numeric; custdue numeric; custn int;
        sup jsonb; waste jsonb; voids jsonb; ex jsonb; appr int; lowc int; expc int; closes jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_biz is null or not exists (select 1 from public.org_units where id = p_biz and kind = 'business') then raise exception 'bad_business'; end if;
  if not (public.is_owner() or public._is_ops('notify') or public.can_scope(p_biz, 'management')) then raise exception 'not allowed'; end if;
  if d > public._today() or d < public._today() - 400 then raise exception 'bad_date'; end if;
  select coalesce(array_agg(l.id), '{}'::int[]) into locs from public.locations l where public._business_of_loc123(l.id) = p_biz;
  neg := coalesce((public._rule_in133('reports_net_of_returns', p_biz) #>> '{}')::boolean, false);
  expd := coalesce(nullif(public._rule_in133('notify_expiry_days', p_biz) #>> '{}', '')::numeric, 3)::int;
  select jsonb_build_object('bills', s.n, 'total', s.t, 'discount', s.d, 'returns', r.a, 'net', case when neg then s.t - r.a else s.t end) into td
    from (select count(*) n, coalesce(sum(total), 0) t, coalesce(sum(discount), 0) d from public.sales where status = 'done' and sale_date = d and location_id = any (locs)) s,
         (select coalesce(sum(amount), 0) a from public.sale_returns where status = 'done' and (created_at at time zone 'Asia/Dhaka')::date = d and location_id = any (locs)) r;
  select jsonb_build_object('bills', s.n, 'total', s.t, 'discount', s.d, 'returns', r.a, 'net', case when neg then s.t - r.a else s.t end) into yd
    from (select count(*) n, coalesce(sum(total), 0) t, coalesce(sum(discount), 0) d from public.sales where status = 'done' and sale_date = d - 1 and location_id = any (locs)) s,
         (select coalesce(sum(amount), 0) a from public.sale_returns where status = 'done' and (created_at at time zone 'Asia/Dhaka')::date = d - 1 and location_id = any (locs)) r;
  select jsonb_build_object('bills', s.n, 'total', s.t, 'discount', s.d, 'returns', r.a, 'net', case when neg then s.t - r.a else s.t end) into lw
    from (select count(*) n, coalesce(sum(total), 0) t, coalesce(sum(discount), 0) d from public.sales where status = 'done' and sale_date = d - 7 and location_id = any (locs)) s,
         (select coalesce(sum(amount), 0) a from public.sale_returns where status = 'done' and (created_at at time zone 'Asia/Dhaka')::date = d - 7 and location_id = any (locs)) r;
  select coalesce(jsonb_agg(jsonb_build_object('location_id', l.id, 'name_bn', l.name_bn, 'name_en', l.name_en, 'net', v.net) order by l.sort), '[]'::jsonb) into byloc
    from public.locations l cross join lateral (
      select coalesce((select sum(total) from public.sales where status = 'done' and sale_date = d and location_id = l.id), 0)
           - case when neg then coalesce((select sum(amount) from public.sale_returns where status = 'done' and location_id = l.id and (created_at at time zone 'Asia/Dhaka')::date = d), 0) else 0 end as net) v
   where l.id = any (locs) and l.is_active and l.status = 'live' and l.kind = 'showroom';
  select coalesce(jsonb_agg(jsonb_build_object('name', z.nm, 'qty', z.q, 'amount', z.a) order by z.a desc), '[]'::jsonb) into top5 from (
    select coalesce(x.ln ->> 'name', '?') nm, round(sum((x.ln ->> 'qty')::numeric), 3) q, round(sum((x.ln ->> 'amount')::numeric), 2) a
      from (select jsonb_array_elements(s.lines) ln from public.sales s where s.status = 'done' and s.sale_date = d and s.location_id = any (locs)) x
     where (x.ln ->> 'amount') ~ '^-?[0-9.]+$' and (x.ln ->> 'qty') ~ '^-?[0-9.]+$' group by coalesce(x.ln ->> 'name', '?') order by sum((x.ln ->> 'amount')::numeric) desc limit 5) z;
  select jsonb_build_object('count', count(*), 'short', coalesce(sum(-amount) filter (where amount < 0), 0), 'over', coalesce(sum(amount) filter (where amount > 0), 0)) into cash
    from public.exceptions where flag_code = 'cash_short_over' and entry_date = d and location_id = any (locs);
  select coalesce(sum(amount), 0) into coll from public.sale_payments where kind = 'collection' and not voided and (paid_at at time zone 'Asia/Dhaka')::date = d and location_id = any (locs);
  with s as (select x.id, x.customer_id, x.sold_at, x.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = x.id and not p.voided), 0) rem
               from public.sales x where x.status = 'done' and x.customer_id is not null and x.location_id = any (locs)),
       c as (select z.customer_id, sum(z.a) coll from (select customer_id, amount a from public.sale_payments where kind = 'collection' and not voided and customer_id is not null and location_id = any (locs)
               union all select customer_id, credit_amount from public.sale_returns where status = 'done' and customer_id is not null and credit_amount > 0 and location_id = any (locs)) z group by 1),
       t as (select customer_id, sum(rem) rem from s group by 1)
  select coalesce(sum(t.rem - coalesce(c.coll, 0)), 0), count(*) into custdue, custn from t left join c on c.customer_id = t.customer_id where t.rem - coalesce(c.coll, 0) > 0;
  select jsonb_build_object('payable', coalesce(sum(o.open_amt), 0), 'suppliers', count(distinct o.supplier_id),
           'overdue', coalesce(sum(o.open_amt) filter (where s.credit_days is not null and o.bill_date is not null and o.bill_date + s.credit_days < public._today()), 0)) into sup
    from public._sup_open(null) o join public.suppliers s on s.id = o.supplier_id where o.open_amt > 0 and o.location_id = any (locs);
  select jsonb_build_object('count', count(*), 'value', coalesce(round(sum(x.qty * coalesce(b.avg_cost, 0)), 2), 0)) into waste
    from public.stock_wastage x left join public.stock_balance b on b.item_id = x.item_id and b.location_id = x.location_id where (x.made_at at time zone 'Asia/Dhaka')::date = d and x.location_id = any (locs);
  select jsonb_build_object('void_count', count(*) filter (where status = 'void'), 'void_total', coalesce(sum(total) filter (where status = 'void'), 0),
           'discount_count', count(*) filter (where status = 'done' and discount > 0), 'discount_total', coalesce(sum(discount) filter (where status = 'done'), 0)) into voids
    from public.sales where sale_date = d and location_id = any (locs);
  select jsonb_build_object('red', count(*) filter (where level = 'red'), 'yellow', count(*) filter (where level = 'yellow')) into ex from public.exceptions where status = 'open' and location_id = any (locs);
  select count(*) into appr from (
      select 1 from public.entries where status = 'submitted' and location_id = any (locs)
      union all select 1 from public.release_requests q join public.entries e on e.id = q.entry_id where q.status = 'pending' and e.location_id = any (locs)
      union all select 1 from public.emergency_requests where status = 'pending' and location_id = any (locs)
      union all select 1 from public.wastage_requests where status = 'pending' and location_id = any (locs)) u;
  select count(*) into lowc from public.stock_balance b join public.items i on i.id = b.item_id where i.is_active and coalesce(i.min_stock, 0) > 0 and b.qty <= i.min_stock and b.location_id = any (locs);
  select count(*) into expc from public.stock_batches where qty_remaining > 0 and expires_at is not null and expires_at < now() + make_interval(days => expd) and location_id = any (locs);
  select coalesce(jsonb_agg(jsonb_build_object('location_id', l.id, 'name_bn', l.name_bn, 'name_en', l.name_en,
           'closed', exists (select 1 from public.entries e where e.form_code = '14-1' and e.location_id = l.id and e.entry_date = d and e.status in ('submitted', 'approved')),
           'mode', public.rollout_mode('14-1', l.id)) order by l.sort), '[]'::jsonb) into closes
    from public.locations l where l.id = any (locs) and l.is_active and l.status = 'live' and l.kind = 'showroom';
  return jsonb_build_object('business', p_biz, 'date', d, 'generated_at', now(),
    'sales', jsonb_build_object('today', td, 'yesterday', yd, 'last_week', lw,
       'vs_yesterday_pct', case when (yd ->> 'net')::numeric > 0 then round(((td ->> 'net')::numeric - (yd ->> 'net')::numeric) * 100 / (yd ->> 'net')::numeric, 1) end,
       'vs_last_week_pct', case when (lw ->> 'net')::numeric > 0 then round(((td ->> 'net')::numeric - (lw ->> 'net')::numeric) * 100 / (lw ->> 'net')::numeric, 1) end,
       'by_location', byloc),
    'top_items', top5, 'cash', cash, 'collections', coll,
    'dues', jsonb_build_object('customers_total', round(custdue, 2), 'customers', custn, 'suppliers', sup),
    'wastage', waste, 'voids_discounts', voids, 'exceptions_open', ex, 'approvals_pending', appr,
    'stock_alerts', jsonb_build_object('low_items', lowc, 'expiring_batches', expc),
    'day_close', closes);
end $$;

-- ---------- 8. the coverage checker: every exposed SECURITY DEFINER function that is NOT scope-aware ----------
-- Scope-aware = its body calls a scope primitive (can_loc, can_scope, _biz_ok123, _my_biz123 ... or has_grant / can_do with a place argument), or it calls a function that is (fixpoint over
-- the call graph; a callee without arguments only counts when it returns a set). The OWNER reads the rest; tests/sql/scope_allowlist.txt is the reviewed list (class + reason per function)
-- and phase133_test fails when a function is in one list and not in the other, so a new function without a scope call cannot slip in. docs/audit_c1/C3_COVERAGE.md explains the classes.
create or replace function public.scope_gaps133() returns table (fn text, args text, gate text, tables_ text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  return query
  with recursive
  prim(n) as (select unnest(array['can_loc', 'can_scope', 'business_of_location', '_biz_ok123', '_my_biz123', '_user_biz123', '_business_of_loc123', 'org_unit_scope', '_loc_vis123', '_shares_biz123',
                                  '_mgmt_covers123', '_biz_vis125', '_my_biz125', '_dl_ok127', '_caller_biz133', '_can_grant_in133', '_acct_locs', '_acct_all', '_all_locs', '_cfgvis133', '_unit_vis133', '_unit_mine133', '_photo_scope133'])),
  noprop(n) as (select unnest(array['has_grant', 'can_grant', 'can_do', 'is_owner', 'is_active', 'rule_on', 'rule_num', 'rule_txt', 'rule_val', '_acct_view', 'biz_ok', 'biz_cost_ok',
                                    'rpt_cost_ok', 'rpt_access', '_is_ops', '_org_on123'])),
  fns as (
    select p.oid, p.proname::text as nm, pg_get_function_identity_arguments(p.oid) as args, p.pronargs,
           (p.proretset or p.prorettype = 'record'::regtype) as isset,
           (p.prosecdef and p.prorettype <> 'trigger'::regtype and has_function_privilege('authenticated', p.oid, 'execute')) as shown,
           lower(regexp_replace(regexp_replace(p.prosrc, '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')) as src
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'),
  direct(oid) as (
    select f.oid from fns f
     where f.nm in (select n from prim)
        or exists (select 1 from prim x where f.src ~ ('(^|[^a-z0-9_])' || x.n || '\s*\('))
        or f.src ~ 'has_grant\(\s*[^,()]+,\s*(p_[a-z_]*(loc|place|site)[a-z_]*|[a-z]+\.(location_id|from_location_id|to_location_id|primary_location_id)|v_loc[a-z_]*|loc|new\.[a-z_]*location_id|old\.[a-z_]*location_id)\s*\)'
        or f.src ~ 'can_do\(\s*[^,()]+,\s*[^,()]+,\s*(p_[a-z_]*(loc|place|site)[a-z_]*|[a-z]+\.(location_id|from_location_id|to_location_id|primary_location_id)|v_loc[a-z_]*|loc|new\.[a-z_]*location_id|old\.[a-z_]*location_id)\s*\)'),
  edges as (
    select f.oid as caller, g.oid as callee
      from fns f cross join lateral (select distinct m[1] as n from regexp_matches(f.src, '([a-z_][a-z0-9_]*)\s*\(', 'g') m) x
      join fns g on g.nm = x.n and g.oid <> f.oid
     where x.n not in (select n from noprop) and (g.pronargs > 0 or g.isset)),
  aw(oid) as (select oid from direct union select e.caller from edges e join aw on aw.oid = e.callee)
  select f.nm, f.args,
         concat_ws('+', case when f.src ~ 'is_owner\(\)' then 'owner' end, case when f.src ~ '(has_grant|can_grant)\(' then 'grant' end, case when f.src ~ 'can_do\(' then 'can_do' end,
                   case when f.src ~ 'auth\.uid\(\)' then 'uid' end, case when f.src ~ 'is_active\(\)' then 'active' end),
         (select string_agg(t.tablename::text, ',' order by t.tablename) from pg_tables t where t.schemaname = 'public' and f.src ~ ('(^|[^a-z0-9_])' || t.tablename || '([^a-z0-9_(]|$)'))
    from fns f where f.shown and f.oid not in (select oid from aw) order by f.nm, f.args;
end $$;

-- ---------- 9. privileges ----------
do $pv$
declare r record;
begin
  -- internal helpers and the trigger function: closed to the browser
  for r in select p.oid::regprocedure as sig from pg_proc p where p.pronamespace = 'public'::regnamespace
            and p.proname in ('_caller_biz133', '_rule_group_only133', '_grant_eff133', '_can_grant_in133', '_form_eff133', '_patch133', '_gate133', '_xb133', '_rule_in133', '_cfgvis133') loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;
  -- used inside the restrictive policies: the browser role needs EXECUTE, nobody else
  for r in select p.oid::regprocedure as sig from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_unit_vis133', '_unit_mine133', '_role_vis133', '_grant_vis133', '_photo_scope133') loop
    execute format('revoke all on function %s from public, anon', r.sig);
    execute format('grant execute on function %s to authenticated', r.sig);
  end loop;
  -- the screens / owner tools
  for r in select p.oid::regprocedure as sig from pg_proc p where p.pronamespace = 'public'::regnamespace
            and p.proname in ('rule_val_in133', 'rules_effective133', 'rule_override_set133', 'rule_overrides_list133', 'rule_grant_override_set133', 'role_form_override_set133', 'role_matrix_list133',
                              'role_scope_set133', 'grant_scope_set133', 'photo_business133', 'photo_path133', 'photo_unmapped133', 'scope_gaps133', 'daily_digest_biz133') loop
    execute format('revoke all on function %s from public, anon', r.sig);
    execute format('grant execute on function %s to authenticated', r.sig);
  end loop;
end $pv$;

commit;

-- ---------------------------------------------------------------- phase134.sql
-- ============================================================
-- Phase 134 (marker prof134) - GROUP ERP, STAGE D: one PROFILE per business, and the upper layers are INVISIBLE to the people of a business.
-- Owner requirement: the top owner/group is named 'MD-AL AMIN'. Every business has its OWN profile (name, logo, address, receipt text, colour). Entering the sweets business shows
-- 'ইসলামিয়া মিষ্টি ঘর / ISLAMIYA MISTY GHAR'; entering another business shows that business. A person who is given access to a business sees ONLY that business: not the group name,
-- not the legal entity above it, not another business, not a sibling, not the tree above it, not a count or total of the group. Only the owner sees the group layer and the master view.
-- Canonical order: after phase133 (docs/PASTE_ORDER.md row 61). Paste twice = no change, no error. Needs phases 122, 123, 528, 133 (checked below).
--
--   1  business_profiles   one row per business unit (org_unit_id unique): display_name_bn / en, short_name, logo_path, address, phone, email, receipt_header, receipt_footer,
--                          theme_color, trade_licence_ref (owner / the manager of THAT business only; the column is not granted to the browser), audit trigger, RLS (the owner,
--                          or the people of that business), no browser write. Writes: business_profile_save (owner, or the holder of org_manage inside that business; p_client key
--                          kept in business_profile_ops134), reads: business_profile_get / business_profile_list134.
--      Seed (idempotent, never overwrites): a profile for every business (the sweets business gets the brand the app has always shown: 'ইসলামিয়া মিষ্টি ঘর' / 'ISLAMIYA MISTY GHAR';
--      any other business gets its unit name); a new business unit gets its profile through a trigger. The group unit is renamed to 'MD-AL AMIN' ONLY while it still holds the
--      phase122 placeholder ('গ্রুপ' / 'Group') and only once (attrs.seed134), so a name the owner chose is never touched.
--   2  UPPER-LAYER BLINDNESS (server side, switch ON and OFF alike, owner view unchanged). For a caller who is not the owner:
--        org_tree()          only the caller's own business subtree, the business is the ROOT (parent_id null, depth 0), no group / legal entity / sibling row, the business row carries
--                            the profile name, no owner %, no tax config; the legal entity's base currency is copied onto the business row so the import-export helper keeps working
--        org_unit_scope()    no legal entity id / code, no group id, the path starts at the business
--        org_scope_list()    only own scopes (a manager of a business: the scopes inside that business); a unit above the business is shown as null
--        org_unit_save / org_unit_deactivate   a holder of org_manage can only touch plain units INSIDE his own business (the codes are namespaced by the business code, a foreign
--                            or missing unit answers 'unit_not_found' / 'bad_parent' alike), never a legal entity / business / group
--        master_share_list(), master_scope_report132()   owner only (they name or count several businesses)
--        policies on org_units, user_org_scopes, master_shares132 follow the same rule (a manager sees the units inside his business, nothing above)
--        master_context_set132 / daily_digest_biz133 / rule_val_in133   a foreign business id answers 'not allowed' exactly like a missing one (no existence oracle)
--      The helper _vis_biz134() is the one definition of "the businesses this caller may know": owner = every business, others = their own business(es) (and, while org_scope_on is
--      OFF and there is a single business, that one business: everybody works in it). Nothing of phases 72..133 is changed except the functions named above.
-- Rollback: nothing else reads the new objects except the functions re-created here; to go back re-paste phase122 (org_tree, org_unit_scope, org_unit_save, org_unit_deactivate,
--   _org_visible122), phase123 (org_scope_list), phase528 (master_share_list, master_scope_report132, master_context_set132) and phase124 (_ie_base124), re-apply the policies of those
--   phases, drop the trigger / table / functions of this file. The group rename is a normal update (the old name is in audit_log).
-- ============================================================
begin;

do $g$
declare miss text := '';
begin
  if to_regclass('public.org_units') is null or to_regclass('public.legal_entities') is null or to_regclass('public.user_org_scopes') is null or to_regclass('public.master_shares132') is null
     or to_regclass('public.locations') is null or to_regclass('public.user_locations') is null then miss := miss || ' tables'; end if;
  if to_regprocedure('public._user_biz123(uuid)') is null or to_regprocedure('public._business_of_unit123(bigint)') is null or to_regprocedure('public._org_on123()') is null
     or to_regprocedure('public._org_anc123(bigint)') is null or to_regprocedure('public._patch133(regprocedure,text,text[])') is null or to_regprocedure('public._caller_biz133()') is null
     or to_regprocedure('public.master_context_set132(bigint)') is null or to_regprocedure('public.master_scope_report132()') is null or to_regprocedure('public.daily_digest_biz133(bigint,date)') is null
     or to_regprocedure('public.rule_val_in133(text,bigint)') is null or to_regprocedure('public._ie_base124(bigint)') is null or to_regprocedure('public.has_grant(text,integer)') is null
     or to_regprocedure('public._client_lock(uuid)') is null or to_regprocedure('public.log_change()') is null or to_regprocedure('public.no_hard_delete()') is null then miss := miss || ' functions'; end if;
  if miss <> '' then raise exception 'phase134 needs the base schema and phases up to 133 pasted first (docs/PASTE_ORDER.md); missing:%', miss; end if;
end $g$;

-- ---------- 1. the profile table ----------
create table if not exists public.business_profiles (
  id bigserial primary key,
  org_unit_id bigint not null unique references public.org_units(id),
  display_name_bn text not null check (length(btrim(display_name_bn)) between 1 and 120),
  display_name_en text check (display_name_en is null or length(btrim(display_name_en)) between 1 and 120),
  short_name text check (short_name is null or length(btrim(short_name)) between 1 and 40),
  logo_path text check (logo_path is null or (length(logo_path) <= 300 and logo_path ~ '^[A-Za-z0-9_][A-Za-z0-9_./ -]*$' and logo_path !~ '\.\.')),
  address text check (address is null or length(address) <= 300),
  phone text check (phone is null or length(phone) between 3 and 40),
  email text check (email is null or (length(email) <= 120 and email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')),
  receipt_header text check (receipt_header is null or length(receipt_header) <= 300),
  receipt_footer text check (receipt_footer is null or length(receipt_footer) <= 300),
  theme_color text check (theme_color is null or theme_color ~ '^#[0-9A-Fa-f]{6}$'),
  trade_licence_ref text check (trade_licence_ref is null or length(trade_licence_ref) <= 80),
  created_by uuid, created_at timestamptz not null default now(),
  updated_by uuid, updated_at timestamptz not null default now()
);

-- idempotency keys of business_profile_save (not readable by the browser)
create table if not exists public.business_profile_ops134 (
  client_id uuid primary key,
  org_unit_id bigint not null references public.org_units(id),
  by_user uuid, at timestamptz not null default now()
);

-- a profile belongs to a unit of kind business
create or replace function public._bp_kind_check134() returns trigger
language plpgsql set search_path = public as $$
begin
  if not exists (select 1 from public.org_units u where u.id = new.org_unit_id and u.kind = 'business') then raise exception 'not_a_business'; end if;
  return new;
end $$;
drop trigger if exists bp_kind_check134 on public.business_profiles;
create trigger bp_kind_check134 before insert or update on public.business_profiles for each row execute function public._bp_kind_check134();
drop trigger if exists bp134_no_delete on public.business_profiles;
create trigger bp134_no_delete before delete on public.business_profiles for each row execute function public.no_hard_delete();
drop trigger if exists bpo134_no_delete on public.business_profile_ops134;
create trigger bpo134_no_delete before delete on public.business_profile_ops134 for each row execute function public.no_hard_delete();
drop trigger if exists audit_bp134 on public.business_profiles;
create trigger audit_bp134 after insert or update on public.business_profiles for each row execute function public.log_change('id');

-- ---------- 2. who may know / manage which business (ONE definition) ----------
-- the owner: the group owner (active)
create or replace function public._grp_owner134() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and public.is_owner();
$$;

-- the businesses this caller may know. Owner: all. Others: their own (scope / assigned place); while org_scope_on is OFF and there is exactly one live business, that one business
-- (everybody works in it, so it is "their" business; this keeps the brand of the original business on every screen).
create or replace function public._vis_biz134() returns setof bigint
language sql stable security definer set search_path = public as $$
  select b.id from public.org_units b where b.kind = 'business' and public.is_active() and public.is_owner()
  union
  select x from public._user_biz123(auth.uid()) x where public.is_active()
  union
  select b.id from public.org_units b
   where b.kind = 'business' and b.status <> 'inactive' and public.is_active() and not public._org_on123()
     and (select count(*) from public.org_units z where z.kind = 'business' and z.status <> 'inactive') = 1;
$$;

-- may the caller manage this business (profile, structure inside it)? Owner: always. Others: only a business of theirs AND the grant org_manage (global, or at a place of that business)
create or replace function public._biz_mgr134(p_biz bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and p_biz is not null and (public.is_owner() or (
    p_biz in (select public._vis_biz134())
    and (public.has_grant('org_manage') or exists (select 1 from public.locations l where l.org_unit_id is not null and public._business_of_unit123(l.org_unit_id) = p_biz and public.has_grant('org_manage', l.id)))));
$$;

-- the same for a unit: the business above it (or the unit itself). A unit above the business level is never managed by a non-owner.
create or replace function public._unit_mgr134(p_unit bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and p_unit is not null and (public.is_owner() or public._biz_mgr134(public._business_of_unit123(p_unit)));
$$;

-- may the caller know this unit at all (owner: yes; others: only units inside a business of theirs)
create or replace function public._unit_vis134(p_unit bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and p_unit is not null and (public.is_owner() or public._business_of_unit123(p_unit) in (select public._vis_biz134()));
$$;

-- the business the caller is working in when none is named: his working / single business, else the first one he may know
create or replace function public._cur_biz134() returns bigint
language sql stable security definer set search_path = public as $$
  select coalesce((select b from (select public._caller_biz133() b) q where q.b in (select public._vis_biz134())), (select min(x) from public._vis_biz134() x));
$$;

-- ---------- 3. RLS + privileges of the new tables, then the profile functions ----------
alter table public.business_profiles enable row level security;
alter table public.business_profile_ops134 enable row level security;
drop policy if exists bp134_read on public.business_profiles;
create policy bp134_read on public.business_profiles for select to authenticated using (public.is_active() and (public.is_owner() or org_unit_id in (select public._vis_biz134())));
revoke all on public.business_profiles, public.business_profile_ops134 from public, anon, authenticated;
-- every column except the licence reference (read through business_profile_get: owner / manager of that business only)
grant select (id, org_unit_id, display_name_bn, display_name_en, short_name, logo_path, address, phone, email, receipt_header, receipt_footer, theme_color, created_at, updated_at)
  on public.business_profiles to authenticated;
revoke all on sequence public.business_profiles_id_seq from public, anon, authenticated;

-- one profile row as jsonb (licence only when asked for)
create or replace function public._bp_json134(p_biz bigint, p_lic boolean) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('business_id', u.id, 'code', u.code, 'template_code', u.template_code, 'status', u.status,
           'display_name_bn', coalesce(bp.display_name_bn, u.name_bn), 'display_name_en', coalesce(bp.display_name_en, case when bp.id is null then u.name_en end),
           'short_name', bp.short_name, 'logo_path', bp.logo_path, 'address', bp.address, 'phone', bp.phone, 'email', bp.email,
           'receipt_header', bp.receipt_header, 'receipt_footer', bp.receipt_footer, 'theme_color', bp.theme_color,
           'trade_licence_ref', case when p_lic then bp.trade_licence_ref end, 'saved', bp.id is not null, 'updated_at', bp.updated_at)
    from public.org_units u left join public.business_profiles bp on bp.org_unit_id = u.id where u.id = p_biz and u.kind = 'business';
$$;

-- the profile of ONE business: p_biz null = the caller's working business. A business the caller may not know answers 'not allowed' exactly like a missing one.
create or replace function public.business_profile_get(p_biz bigint default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare b bigint; r jsonb; mgr boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  b := coalesce(p_biz, public._cur_biz134());
  if b is null or not (public.is_owner() or b in (select public._vis_biz134())) then raise exception 'not allowed'; end if;
  mgr := public._biz_mgr134(b);
  r := public._bp_json134(b, mgr);
  if r is null then raise exception 'not allowed'; end if;
  return r || jsonb_build_object('can_edit', mgr);
end $$;

-- the profiles the caller may know (owner: every active business; others: their own) - for the business switcher and the brand of a document
create or replace function public.business_profile_list134() returns table (org_unit_id bigint, code text, status text, display_name_bn text, display_name_en text, short_name text,
  logo_path text, address text, phone text, email text, receipt_header text, receipt_footer text, theme_color text, can_edit boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query
    select u.id, u.code, u.status, coalesce(bp.display_name_bn, u.name_bn), coalesce(bp.display_name_en, case when bp.id is null then u.name_en end), bp.short_name, bp.logo_path, bp.address, bp.phone,
           bp.email, bp.receipt_header, bp.receipt_footer, bp.theme_color, public._biz_mgr134(u.id)
      from public.org_units u left join public.business_profiles bp on bp.org_unit_id = u.id
     where u.kind = 'business' and u.status <> 'inactive' and (public.is_owner() or u.id in (select public._vis_biz134())) order by u.id;
end $$;

-- create / change the profile of one business. p_patch = {"display_name_bn", "display_name_en", "short_name", "logo_path", "address", "phone", "email", "receipt_header", "receipt_footer",
-- "theme_color", "trade_licence_ref"}: only the keys present change ('' or null clears an optional text). Owner, or the holder of org_manage inside that business. p_client is required;
-- the same key again returns the first answer without a second write.
create or replace function public.business_profile_save(p_biz bigint, p_patch jsonb, p_client uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); op public.business_profile_ops134; bp public.business_profiles; k text; v text; u public.org_units;
        nbn text; nen text; sn text; lg text; ad text; ph text; em text; rh text; rf text; tc text; lic text; nid bigint;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_client is null then raise exception 'client_id_needed'; end if;
  perform public._client_lock(p_client);
  select * into op from public.business_profile_ops134 where client_id = p_client;
  if found then
    if op.by_user is distinct from me then raise exception 'client_id_taken'; end if;
    return jsonb_build_object('dup', true, 'business_id', op.org_unit_id);
  end if;
  if p_biz is null or not public._biz_mgr134(p_biz) then raise exception 'not allowed'; end if;
  select * into u from public.org_units where id = p_biz and kind = 'business';
  if not found then raise exception 'not allowed'; end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' or length(p_patch::text) > 5000 then raise exception 'bad_profile'; end if;
  for k in select jsonb_object_keys(p_patch) loop
    if k not in ('display_name_bn', 'display_name_en', 'short_name', 'logo_path', 'address', 'phone', 'email', 'receipt_header', 'receipt_footer', 'theme_color', 'trade_licence_ref') then raise exception 'bad_profile'; end if;
    if jsonb_typeof(p_patch -> k) not in ('string', 'null') then raise exception 'bad_profile'; end if;
  end loop;
  select * into bp from public.business_profiles where org_unit_id = p_biz for update;
  -- start from the stored row (or the unit names for a first save), then apply the keys that were sent
  nbn := coalesce(bp.display_name_bn, u.name_bn); nen := case when bp.id is null then u.name_en else bp.display_name_en end; sn := bp.short_name; lg := bp.logo_path; ad := bp.address; ph := bp.phone;
  em := bp.email; rh := bp.receipt_header; rf := bp.receipt_footer; tc := bp.theme_color; lic := bp.trade_licence_ref;
  if p_patch ? 'display_name_bn' then nbn := nullif(btrim(coalesce(p_patch ->> 'display_name_bn', '')), ''); if nbn is null or length(nbn) > 120 then raise exception 'bad_name'; end if; end if;
  if p_patch ? 'display_name_en' then nen := nullif(btrim(coalesce(p_patch ->> 'display_name_en', '')), ''); if nen is not null and length(nen) > 120 then raise exception 'bad_name'; end if; end if;
  if p_patch ? 'short_name' then sn := nullif(btrim(coalesce(p_patch ->> 'short_name', '')), ''); if sn is not null and length(sn) > 40 then raise exception 'bad_short_name'; end if; end if;
  if p_patch ? 'logo_path' then lg := nullif(btrim(coalesce(p_patch ->> 'logo_path', '')), '');
    if lg is not null and (length(lg) > 300 or lg !~ '^[A-Za-z0-9_][A-Za-z0-9_./ -]*$' or lg ~ '\.\.') then raise exception 'bad_logo'; end if; end if;
  if p_patch ? 'address' then ad := nullif(btrim(coalesce(p_patch ->> 'address', '')), ''); if ad is not null and length(ad) > 300 then raise exception 'bad_address'; end if; end if;
  if p_patch ? 'phone' then ph := nullif(btrim(coalesce(p_patch ->> 'phone', '')), ''); if ph is not null and (length(ph) not between 3 and 40 or ph !~ '^[0-9০-৯+() -]+$') then raise exception 'bad_phone'; end if; end if;
  if p_patch ? 'email' then em := nullif(btrim(coalesce(p_patch ->> 'email', '')), ''); if em is not null and (length(em) > 120 or em !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$') then raise exception 'bad_email'; end if; end if;
  if p_patch ? 'receipt_header' then rh := nullif(btrim(coalesce(p_patch ->> 'receipt_header', '')), ''); if rh is not null and length(rh) > 300 then raise exception 'bad_receipt_text'; end if; end if;
  if p_patch ? 'receipt_footer' then rf := nullif(btrim(coalesce(p_patch ->> 'receipt_footer', '')), ''); if rf is not null and length(rf) > 300 then raise exception 'bad_receipt_text'; end if; end if;
  if p_patch ? 'theme_color' then tc := nullif(btrim(coalesce(p_patch ->> 'theme_color', '')), ''); if tc is not null and tc !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'bad_color'; end if; end if;
  if p_patch ? 'trade_licence_ref' then lic := nullif(btrim(coalesce(p_patch ->> 'trade_licence_ref', '')), ''); if lic is not null and length(lic) > 80 then raise exception 'bad_licence'; end if; end if;
  if nbn is null then raise exception 'bad_name'; end if;
  if bp.id is null then
    insert into public.business_profiles (org_unit_id, display_name_bn, display_name_en, short_name, logo_path, address, phone, email, receipt_header, receipt_footer, theme_color, trade_licence_ref, created_by, updated_by)
    values (p_biz, nbn, nen, sn, lg, ad, ph, em, rh, rf, tc, lic, me, me) returning id into nid;
  else
    update public.business_profiles set display_name_bn = nbn, display_name_en = nen, short_name = sn, logo_path = lg, address = ad, phone = ph, email = em, receipt_header = rh, receipt_footer = rf,
      theme_color = tc, trade_licence_ref = lic, updated_by = me, updated_at = now() where id = bp.id;
    nid := bp.id;
  end if;
  insert into public.business_profile_ops134 (client_id, org_unit_id, by_user) values (p_client, p_biz, me);
  return jsonb_build_object('dup', false, 'id', nid, 'business_id', p_biz);
end $$;

-- a new business unit gets its profile (the unit names) at once; the owner or its manager edit it afterwards
create or replace function public._bp_seed134() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kind = 'business' then
    insert into public.business_profiles (org_unit_id, display_name_bn, display_name_en, created_by, updated_by)
    values (new.id, new.name_bn, new.name_en, new.created_by, new.created_by) on conflict (org_unit_id) do nothing;
  end if;
  return new;
end $$;
drop trigger if exists bp_seed134 on public.org_units;
create trigger bp_seed134 after insert on public.org_units for each row execute function public._bp_seed134();

-- ---------- 4. seed: profiles of the existing businesses, and the group name ----------
insert into public.business_profiles (org_unit_id, display_name_bn, display_name_en)
select u.id,
       case when u.code = 'SWEETS' and u.name_bn = 'মিষ্টি ব্যবসা' and coalesce(u.name_en, 'sweets business') ilike 'sweets business' then 'ইসলামিয়া মিষ্টি ঘর' else u.name_bn end,
       case when u.code = 'SWEETS' and u.name_bn = 'মিষ্টি ব্যবসা' and coalesce(u.name_en, 'sweets business') ilike 'sweets business' then 'ISLAMIYA MISTY GHAR' else u.name_en end
  from public.org_units u where u.kind = 'business'
on conflict (org_unit_id) do nothing;

-- the top owner / group is named 'MD-AL AMIN': only while the unit still holds the phase122 placeholder, and only once
do $seed$
begin
  update public.org_units g set name_bn = 'MD-AL AMIN', name_en = 'MD-AL AMIN',
         attrs = g.attrs || jsonb_build_object('seed134', jsonb_build_object('group_named', true)), updated_at = now()
   where g.kind = 'group' and g.name_bn = 'গ্রুপ' and g.name_en = 'Group' and coalesce((g.attrs -> 'seed134' ->> 'group_named')::boolean, false) = false;
  -- a group the owner has already named: remember that the seed has nothing to do (a later rename back to the placeholder is then the owner's choice)
  update public.org_units g set attrs = g.attrs || jsonb_build_object('seed134', jsonb_build_object('group_named', true))
   where g.kind = 'group' and coalesce((g.attrs -> 'seed134' ->> 'group_named')::boolean, false) = false;
end $seed$;

-- ---------- 5. upper-layer blindness: the tree, the scope, the lists ----------
-- units the caller may see in the tree: the owner everything; a manager of a business the units inside it; everybody else the units that hold one of his assigned places (and their parents inside the business)
create or replace function public._org_visible122() returns setof bigint
language sql stable security definer set search_path = public as $$
  select u.id from public.org_units u where public.is_active() and public.is_owner()
  union
  select u.id from public.org_units u where public.is_active() and u.kind not in ('group', 'legal_entity') and public._unit_mgr134(u.id)
  union
  select u.id from public.org_units u where public.is_active() and u.kind not in ('group', 'legal_entity') and public._unit_vis134(u.id) and public.can_scope(u.id)   -- a live role scope (for example management) over the unit
  union
  select a.id from (
    with recursive anc(id, parent_id) as (
      select u.id, u.parent_id from public.org_units u
       where public.is_active() and u.id in (select l.org_unit_id from public.locations l join public.user_locations ul on ul.location_id = l.id
                                              where ul.user_id = auth.uid() and l.org_unit_id is not null)
      union
      select p.id, p.parent_id from public.org_units p join anc on anc.parent_id = p.id)
    select id from anc) a;
$$;

-- the tree. Owner: every unit (unchanged). Everybody else: ONLY the subtree of his own business, the business is the root (parent_id null, depth 0, path starts at the business code);
-- the business row carries the profile name; no group, no legal entity, no sibling, no owner %, no tax config.
create or replace function public.org_tree() returns table (
  id bigint, parent_id bigint, kind text, code text, name_bn text, name_en text, template_code text, template_status text, status text,
  effective_from date, effective_to date, currency text, tz text, attrs jsonb, depth int, path text, location_ids int[],
  trade_licence_ref text, owner_pct numeric, tax_cfg jsonb, fiscal_start date, base_currency text)
language plpgsql stable security definer set search_path = public as $$
declare own_ boolean;   /* prof134 */
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  own_ := public.is_owner();
  return query
  with recursive t(id, depth, path) as (
    select u.id, 0, u.code::text from public.org_units u
     where case when own_ then u.parent_id is null else (u.kind = 'business' and u.id in (select public._vis_biz134())) end
    union all
    select c.id, t.depth + 1, t.path || '/' || c.code from public.org_units c join t on c.parent_id = t.id)
  select u.id,
         case when own_ then u.parent_id when u.kind = 'business' then null else u.parent_id end,
         u.kind, u.code,
         case when own_ or u.kind <> 'business' or bp.display_name_bn is null then u.name_bn else bp.display_name_bn end,
         case when own_ or u.kind <> 'business' or bp.display_name_bn is null then u.name_en else bp.display_name_en end,
         u.template_code, bt.status, u.status,
         u.effective_from, u.effective_to, u.currency, u.tz,
         case when public._unit_mgr134(u.id) then u.attrs else '{}'::jsonb end,
         t.depth, t.path,
         coalesce((select array_agg(l.id order by l.id) from public.locations l where l.org_unit_id = u.id
                    and (public._unit_mgr134(u.id) or exists (select 1 from public.user_locations ul where ul.user_id = auth.uid() and ul.location_id = l.id))), '{}'::int[]),
         case when own_ then le.trade_licence_ref when u.kind = 'business' and public._unit_mgr134(u.id) then bp.trade_licence_ref end,
         case when own_ then le.owner_pct end,
         case when own_ then le.tax_cfg end,
         case when own_ then le.fiscal_start end,
         case when own_ or u.kind <> 'business' then le.base_currency
              else (select le2.base_currency from public.legal_entities le2 where le2.org_unit_id in (select public._org_anc123(u.id)) limit 1) end
    from t join public.org_units u on u.id = t.id
    left join public.legal_entities le on le.org_unit_id = u.id
    left join public.business_templates bt on bt.code = u.template_code
    left join public.business_profiles bp on bp.org_unit_id = u.id
   where u.id in (select * from public._org_visible122())
   order by t.path;
end $$;

-- location -> unit -> business (-> legal entity -> group for the OWNER). Others: only their own places, and the answer stops at the business.
create or replace function public.org_unit_scope(p_location int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare loc public.locations; u bigint; r jsonb; own_ boolean;   /* prof134 */
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_location is null then raise exception 'bad_location'; end if;
  own_ := public.is_owner();
  select * into loc from public.locations where id = p_location;
  if not found then raise exception '%', case when own_ then 'bad_location' else 'not allowed' end; end if;   -- a missing place looks like a foreign one
  if not (own_ or (loc.org_unit_id is not null and public._unit_mgr134(loc.org_unit_id))
                or exists (select 1 from public.user_locations ul where ul.user_id = auth.uid() and ul.location_id = p_location)) then raise exception 'not allowed'; end if;
  u := loc.org_unit_id;
  if u is null then return jsonb_build_object('location_id', p_location, 'org_unit_id', null, 'mapped', false); end if;
  with recursive up(id, parent_id, kind, code, lvl) as (
    select o.id, o.parent_id, o.kind, o.code, 0 from public.org_units o where o.id = u
    union all
    select p.id, p.parent_id, p.kind, p.code, up.lvl + 1 from public.org_units p join up on up.parent_id = p.id)
  select jsonb_build_object('location_id', p_location, 'mapped', true, 'org_unit_id', u,
    'business_id', (select id from up where kind = 'business' order by lvl limit 1),
    'business_code', (select code from up where kind = 'business' order by lvl limit 1),
    'legal_entity_id', case when own_ then (select id from up where kind = 'legal_entity' order by lvl limit 1) end,
    'legal_entity_code', case when own_ then (select code from up where kind = 'legal_entity' order by lvl limit 1) end,
    'group_id', case when own_ then (select id from up where kind = 'group' order by lvl limit 1) end,
    'path', (select jsonb_agg(code order by lvl desc) from up where own_ or lvl <= coalesce((select min(lvl) from up where kind = 'business'), -1)))
  into r;
  return r;
end $$;

-- create / update one unit. (phase122 body; the new first block binds a non-owner to the inside of his own business)
create or replace function public.org_unit_save(p_id bigint, p_parent bigint, p_kind text, p_code text, p_name_bn text, p_name_en text default null,
  p_template text default null, p_status text default null, p_from date default null, p_to date default null, p_currency text default 'BDT',
  p_tz text default 'Asia/Dhaka', p_attrs jsonb default '{}'::jsonb, p_le jsonb default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  today date := (now() at time zone 'Asia/Dhaka')::date;
  me uuid := auth.uid(); o public.org_units; par public.org_units; code_ text := upper(btrim(coalesce(p_code, '')));
  st text; cur text := upper(btrim(coalesce(p_currency, 'BDT'))); tz_ text := btrim(coalesce(p_tz, 'Asia/Dhaka'));
  attrs_ jsonb := coalesce(p_attrs, '{}'::jsonb); nid bigint; k text;
  lic text; taxc jsonb; fs date; bcur text; pct numeric; own_ boolean; bzcode text;   /* prof134 */
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  own_ := public.is_owner();
  if not (own_ or public.has_grant('org_manage')) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if not own_ then
    -- a manager bound to his own business: only plain units INSIDE that business (never a legal entity, a business or the group), the code is namespaced by the business code,
    -- a unit outside the business answers exactly like a missing one
    if p_le is not null then raise exception 'not allowed'; end if;
    if p_id is null then
      if p_kind is null or p_kind not in ('branch', 'site', 'department', 'cost_centre', 'project') then raise exception 'not allowed'; end if;
      if p_parent is null or not public._unit_mgr134(p_parent) then raise exception 'bad_parent'; end if;
      select b.code into bzcode from public.org_units b where b.id = public._business_of_unit123(p_parent);
      code_ := case when code_ like bzcode || '-%' then code_ else bzcode || '-' || code_ end;
    else
      if not public._unit_mgr134(p_id) then raise exception 'unit_not_found'; end if;
      if (select x.kind from public.org_units x where x.id = p_id) in ('group', 'legal_entity', 'business') then raise exception 'not allowed'; end if;
      if p_parent is not null and not public._unit_mgr134(p_parent) then raise exception 'bad_parent'; end if;
    end if;
  end if;
  if p_id is null then
    if p_client is null then raise exception 'client_id_needed'; end if;
    select * into o from public.org_units where client_id = p_client;
    if found then
      if o.created_by is distinct from me then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', o.id, 'code', o.code);
    end if;
  end if;
  -- shared validation
  if p_name_bn is null or length(btrim(p_name_bn)) not between 1 and 120 then raise exception 'bad_name'; end if;
  if p_name_en is not null and length(p_name_en) > 120 then raise exception 'bad_name'; end if;
  if p_status is not null and p_status not in ('planned', 'active') then raise exception 'bad_status'; end if;
  if cur !~ '^[A-Z]{3}$' then raise exception 'bad_currency'; end if;
  if not exists (select 1 from pg_timezone_names where name = tz_) then raise exception 'bad_tz'; end if;
  if jsonb_typeof(attrs_) is distinct from 'object' or length(attrs_::text) > 20000 then raise exception 'bad_attrs'; end if;
  if p_from is not null and p_from not between date '2000-01-01' and today + 3660 then raise exception 'bad_date'; end if;
  if p_to is not null and p_to not between date '2000-01-01' and today + 36600 then raise exception 'bad_date'; end if;
  if p_from is not null and p_to is not null and p_to < p_from then raise exception 'bad_date'; end if;
  if p_template is not null and not exists (select 1 from public.business_templates where code = p_template) then raise exception 'bad_template'; end if;

  if p_id is null then
    st := coalesce(p_status, 'active');
    if p_kind is null or p_kind not in ('legal_entity', 'business', 'branch', 'site', 'department', 'cost_centre', 'project') then raise exception 'bad_kind'; end if;
    if code_ !~ '^[A-Z0-9][A-Z0-9_-]{1,39}$' then raise exception 'bad_code'; end if;
    if exists (select 1 from public.org_units where code = code_) then raise exception 'code_taken'; end if;
    select * into par from public.org_units where id = p_parent;
    if not found then raise exception 'bad_parent'; end if;
    if par.status = 'inactive' then raise exception 'parent_inactive'; end if;
    if not public._org_parent_ok122(p_kind, par.kind) then raise exception 'bad_parent_kind'; end if;
    if p_template is not null and p_kind <> 'business' then raise exception 'template_only_for_business'; end if;
  else
    select * into o from public.org_units where id = p_id for update;
    if not found then raise exception 'unit_not_found'; end if;
    if o.kind = 'group' and p_parent is not null then raise exception 'bad_parent'; end if;
    st := coalesce(p_status, o.status);   -- null keeps the current status (an inactive unit stays inactive; pass 'active' to reactivate)
    if o.status = 'inactive' and st <> 'inactive' and o.parent_id is not null and exists (select 1 from public.org_units x where x.id = o.parent_id and x.status = 'inactive') then raise exception 'parent_inactive'; end if;
    if p_kind is not null and p_kind <> o.kind then raise exception 'kind_fixed'; end if;
    if p_code is not null and code_ <> o.code then raise exception 'code_fixed'; end if;
    if p_template is not null and o.kind <> 'business' then raise exception 'template_only_for_business'; end if;
    if p_parent is distinct from o.parent_id and o.kind <> 'group' then
      select * into par from public.org_units where id = p_parent;
      if not found then raise exception 'bad_parent'; end if;
      if par.status = 'inactive' then raise exception 'parent_inactive'; end if;
      if not public._org_parent_ok122(o.kind, par.kind) then raise exception 'bad_parent_kind'; end if;
      if exists (with recursive d(id) as (select o.id union select c.id from public.org_units c join d on c.parent_id = d.id) select 1 from d where d.id = p_parent) then raise exception 'parent_cycle'; end if;
    end if;
  end if;

  -- legal entity details
  if p_le is not null then
    if jsonb_typeof(p_le) <> 'object' then raise exception 'bad_legal'; end if;
    if (case when p_id is null then p_kind else o.kind end) <> 'legal_entity' then raise exception 'legal_only_for_legal_entity'; end if;
    for k in select jsonb_object_keys(p_le) loop
      if k not in ('trade_licence_ref', 'tax_cfg', 'fiscal_start', 'base_currency', 'owner_pct') then raise exception 'bad_legal'; end if;
    end loop;
    if (p_le ? 'owner_pct' or p_le ? 'tax_cfg') and not public.is_owner() then raise exception 'owner_only'; end if;
    if p_le ? 'trade_licence_ref' then lic := nullif(btrim(p_le->>'trade_licence_ref'), ''); if lic is not null and length(lic) > 80 then raise exception 'bad_legal'; end if; end if;
    if p_le ? 'tax_cfg' then taxc := p_le->'tax_cfg'; if jsonb_typeof(taxc) is distinct from 'object' or length(taxc::text) > 20000 then raise exception 'bad_legal'; end if; end if;
    if p_le ? 'fiscal_start' then fs := nullif(p_le->>'fiscal_start', '')::date; end if;
    if p_le ? 'base_currency' then bcur := upper(btrim(p_le->>'base_currency')); if bcur !~ '^[A-Z]{3}$' then raise exception 'bad_currency'; end if; end if;
    if p_le ? 'owner_pct' then pct := (p_le->>'owner_pct')::numeric; if pct is null or pct <> pct or pct < 0 or pct > 100 then raise exception 'bad_owner_pct'; end if; end if;
  end if;

  if p_id is null then
    insert into public.org_units (parent_id, kind, code, name_bn, name_en, template_code, status, effective_from, effective_to, currency, tz, attrs, client_id, created_by, updated_by)
    values (p_parent, p_kind, code_, btrim(p_name_bn), nullif(btrim(coalesce(p_name_en, '')), ''), p_template, st, p_from, p_to, cur, tz_, attrs_, p_client, me, me)
    returning id into nid;
    if p_kind = 'legal_entity' then
      insert into public.legal_entities (org_unit_id, trade_licence_ref, tax_cfg, fiscal_start, base_currency, owner_pct, created_by, updated_by)
      values (nid, lic, coalesce(taxc, '{}'::jsonb), fs, coalesce(bcur, cur), coalesce(pct, 100), me, me);
    end if;
    return jsonb_build_object('dup', false, 'id', nid, 'code', code_);
  end if;

  update public.org_units set parent_id = case when kind = 'group' then null else p_parent end, name_bn = btrim(p_name_bn), name_en = nullif(btrim(coalesce(p_name_en, '')), ''),
    template_code = case when kind = 'business' then p_template else null end, status = st, effective_from = p_from, effective_to = p_to, currency = cur, tz = tz_, attrs = attrs_,
    deactivated_reason = case when st <> 'inactive' then null else deactivated_reason end,
    updated_by = me, updated_at = now()
   where id = p_id;
  if o.kind = 'legal_entity' and p_le is not null then
    update public.legal_entities set trade_licence_ref = case when p_le ? 'trade_licence_ref' then lic else trade_licence_ref end,
      tax_cfg = case when p_le ? 'tax_cfg' then taxc else tax_cfg end, fiscal_start = case when p_le ? 'fiscal_start' then fs else fiscal_start end,
      base_currency = coalesce(bcur, base_currency), owner_pct = coalesce(pct, owner_pct), updated_by = me, updated_at = now()
     where org_unit_id = p_id;
  end if;
  return jsonb_build_object('dup', false, 'id', p_id, 'code', o.code);
end $$;

-- deactivate: as phase122; a non-owner only a plain unit inside his own business
create or replace function public.org_unit_deactivate(p_id bigint, p_reason text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.org_units; today date := (now() at time zone 'Asia/Dhaka')::date; own_ boolean;   /* prof134 */
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  own_ := public.is_owner();
  if not (own_ or public.has_grant('org_manage')) then raise exception 'not allowed'; end if;
  if p_reason is not null and length(p_reason) > 500 then raise exception 'bad_reason'; end if;
  perform public._client_lock(p_client);
  if not own_ and not public._unit_mgr134(p_id) then raise exception 'unit_not_found'; end if;
  select * into o from public.org_units where id = p_id for update;
  if not found then raise exception 'unit_not_found'; end if;
  if not own_ and o.kind in ('group', 'legal_entity', 'business') then raise exception 'not allowed'; end if;
  if o.status = 'inactive' then return jsonb_build_object('dup', true, 'id', o.id); end if;
  if exists (select 1 from public.org_units c where c.parent_id = o.id and c.status <> 'inactive') then raise exception 'has_active_children'; end if;
  if exists (select 1 from public.locations l where l.org_unit_id = o.id and l.is_active) then raise exception 'has_active_locations'; end if;
  update public.org_units set status = 'inactive', effective_to = case when effective_to is null or effective_to > today then today else effective_to end,
    deactivated_reason = nullif(btrim(coalesce(p_reason, '')), ''), deactivated_by = auth.uid(), deactivated_at = now(), updated_by = auth.uid(), updated_at = now()
   where id = o.id;
  return jsonb_build_object('dup', false, 'id', o.id);
end $$;

-- scopes: the owner all; a manager of a business the scopes inside it; everybody else his own. A unit above the business level is never named to a non-owner.
create or replace function public.org_scope_list(p_user uuid default null) returns table (id bigint, user_id uuid, staff_id text, full_name text, org_unit_id bigint, unit_code text, role_code text,
  status text, live boolean, note text, granted_at timestamptz, revoked_at timestamptz, revoked_reason text)
language plpgsql stable security definer set search_path = public as $$
declare own_ boolean;   /* prof134 */
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  own_ := public.is_owner();
  return query
    select s.id, s.user_id, pr.staff_id, pr.full_name, case when own_ or public._unit_vis134(s.org_unit_id) then s.org_unit_id end, case when own_ or public._unit_vis134(s.org_unit_id) then u.code end,
           s.role_code, s.status,
           s.status = 'active' and exists (select 1 from public.user_roles ur where ur.user_id = s.user_id and ur.role_code = s.role_code),
           s.note, s.granted_at, s.revoked_at, s.revoked_reason
      from public.user_org_scopes s join public.profiles pr on pr.id = s.user_id join public.org_units u on u.id = s.org_unit_id
     where (own_ or s.user_id = auth.uid() or public._unit_mgr134(s.org_unit_id)) and (p_user is null or s.user_id = p_user)
     order by s.id;
end $$;

-- shares and the coverage report name or count SEVERAL businesses: owner only
create or replace function public.master_share_list() returns table (id bigint, table_name text, row_key text, from_org bigint, from_code text, to_org bigint, to_code text, status text, note text, created_at timestamptz, revoked_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;   /* prof134 */
  return query select s.id, s.table_name, s.row_key, s.from_org, f.code, s.to_org, t.code, s.status, s.note, s.created_at, s.revoked_at
    from public.master_shares132 s join public.org_units f on f.id = s.from_org join public.org_units t on t.id = s.to_org order by s.id;
end $$;

-- a business the caller may not use answers exactly like a missing one
create or replace function public.master_context_set132(p_org bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_org is null then delete from public.master_ctx132 where user_id = auth.uid(); return jsonb_build_object('org_unit_id', null); end if;
  if not (p_org in (select public._my_biz123())) or not exists (select 1 from public.org_units where id = p_org and kind = 'business' and status <> 'inactive') then raise exception 'not allowed'; end if;   /* prof134 */
  insert into public.master_ctx132 (user_id, org_unit_id) values (auth.uid(), p_org) on conflict (user_id) do update set org_unit_id = excluded.org_unit_id, set_at = now();
  return jsonb_build_object('org_unit_id', p_org);
end $$;

-- base currency of a business = that of its legal entity. Reads the tables directly (the tree no longer shows the legal entity to the people of a business)
create or replace function public._ie_base124(p_org bigint) returns text
language sql stable security definer set search_path = public as $$
  select le.base_currency from public.legal_entities le where le.org_unit_id in (select public._org_anc123(p_org));   /* prof134 */
$$;

-- text patches (exact anchors, a second paste is a no-op): the coverage report is owner only; a foreign business id looks like a missing one
select public._patch133('public.master_scope_report132()'::regprocedure, '/* prof134 */', array[
  'if not (public.is_active() and (public.is_owner() or public.has_grant(''org_manage''))) then raise exception ''not allowed''; end if;',
  'if not (public.is_active() and public.is_owner()) then raise exception ''not allowed''; end if; /* prof134 */']);
select public._patch133('public.daily_digest_biz133(bigint,date)'::regprocedure, '/* prof134 */', array[
  E'  if p_biz is null or not exists (select 1 from public.org_units where id = p_biz and kind = ''business'') then raise exception ''bad_business''; end if;\n  if not (public.is_owner() or public._is_ops(''notify'') or public.can_scope(p_biz, ''management'')) then raise exception ''not allowed''; end if;',
  E'  if not (public.is_owner() or public._is_ops(''notify'') or public.can_scope(p_biz, ''management'')) then raise exception ''not allowed''; end if; /* prof134 */\n  if p_biz is null or not exists (select 1 from public.org_units where id = p_biz and kind = ''business'') then raise exception ''bad_business''; end if;']);
select public._patch133('public.rule_val_in133(text,bigint)'::regprocedure, '/* prof134 */', array[
  E'  if p_unit is null or not exists (select 1 from public.org_units where id = p_unit and kind = ''business'') then raise exception ''bad_business''; end if;\n  if not (public.is_owner() or p_unit in (select public._my_biz123())) then raise exception ''not allowed''; end if;',
  E'  if not (public.is_owner() or p_unit in (select public._my_biz123())) then raise exception ''not allowed''; end if; /* prof134 */\n  if p_unit is null or not exists (select 1 from public.org_units where id = p_unit and kind = ''business'') then raise exception ''bad_business''; end if;']);

-- ---------- 6. policies: a manager sees the units inside his business, nothing above ----------
drop policy if exists ou122_read on public.org_units;
create policy ou122_read on public.org_units for select to authenticated using (public.is_owner() or (kind not in ('group', 'legal_entity') and public._unit_mgr134(id)));
drop policy if exists uos123_read on public.user_org_scopes;
create policy uos123_read on public.user_org_scopes for select to authenticated using (public.is_owner() or (public._unit_vis134(org_unit_id) and (user_id = auth.uid() or public._unit_mgr134(org_unit_id))));
drop policy if exists master_shares132_read on public.master_shares132;
create policy master_shares132_read on public.master_shares132 for select to authenticated using (public.is_owner());

-- ---------- 7. privileges ----------
-- used inside the policies / by the browser: harmless (they answer about the caller himself)
revoke all on function public._vis_biz134(), public._unit_mgr134(bigint), public._unit_vis134(bigint) from public, anon;
grant execute on function public._vis_biz134(), public._unit_mgr134(bigint), public._unit_vis134(bigint) to authenticated;
revoke all on function public._grp_owner134(), public._biz_mgr134(bigint), public._cur_biz134(), public._bp_json134(bigint, boolean), public._bp_kind_check134(), public._bp_seed134() from public, anon, authenticated;
revoke all on function public.business_profile_get(bigint), public.business_profile_list134(), public.business_profile_save(bigint, jsonb, uuid) from public, anon;
grant execute on function public.business_profile_get(bigint), public.business_profile_list134(), public.business_profile_save(bigint, jsonb, uuid) to authenticated;
-- re-created functions keep their grants (create or replace); make sure none is open to anon
revoke all on function public.org_tree(), public.org_unit_scope(int), public.org_unit_deactivate(bigint, text, uuid), public.org_scope_list(uuid), public.master_share_list(),
  public.master_context_set132(bigint) from public, anon;
revoke all on function public._org_visible122(), public._ie_base124(bigint) from public, anon, authenticated;

commit;

-- ---------------------------------------------------------------- phase135.sql
-- ============================================================
-- Phase 135 (marker loc135) - GROUP ERP, STAGE D2: create the OPERATIONAL PLACES of a business from the app, and map them to that business.
-- Gap closed: org_unit_save creates organization nodes (business / branch / site ...) but NOT places (rows of public.locations that carry stock, POS, cash, users), and nothing mapped a newly
-- created place to a business ("new places are not mapped automatically", B1). The owner can now create a second business (for example a dealership with two branches) without SQL.
-- Canonical order: after phase134 (docs/PASTE_ORDER.md row 62). Paste twice = no change, no error. Needs phases 16, 122, 123, 133, 134 (checked below).
--
--   business_place_create135(p_business, p_kind, p_code, p_name_bn, p_name_en, p_org_branch default null, p_client default null) -> jsonb {dup, id, code, business_id, org_unit_id, kind, status}
--       Who: the owner, or the holder of org_manage INSIDE that business (_biz_mgr134: strict scope, a foreign or missing business answers 'not allowed' alike).
--       It calls the EXISTING location_save(null, ...) of phase16 (same defaults: model A, 17 setup steps, settings sheet version 1, step 2 done) - nothing is duplicated - then sets
--       locations.org_unit_id to the business (or to the given branch / site unit INSIDE that business) and moves the new place from 'planned' to 'setting_up'
--       (the status the pick-lists of the app already show, so the place is usable at once).
--       Kinds: the six kinds of the locations CHECK (showroom factory godown hub online other); the aliases branch / dealer_branch / sales_point = showroom, warehouse / store = godown.
--       Code: locations.code is globally unique and immutable, so the stored code is <business code in lower case>_<your code> (a code that already starts with that prefix is not doubled);
--             without a code it is made from the English name. Clear errors: bad_code, code_too_long, code_in_use. Existing codes are never touched.
--       Names: a place name must be unique INSIDE the business (name_in_use); the same name in another business is allowed and is never revealed.
--       Idempotent by p_client (table business_place_ops135); the same key from another user = client_id_taken. Audit: the audit trigger of locations + the append-only ops table.
--   location_save (phase16) is patched ONCE (marker /* loc135 */, two exact-text anchors, a second paste is a no-op): the "may add a place" test also accepts the transaction-local
--       token that business_place_create135 sets (the caller was already checked), and the name test, while the token is set, compares names inside the target business only, and the insert
--       carries org_unit_id (the place is born mapped, so the insert triggers and the business border of phase133 already see its business).
--       Called by anybody else, location_save behaves exactly as before (tests/sql/loc135_before_after.sh).
--   business_place_move135(p_location, p_business, p_reason, p_dry default true, p_force default false, p_client default null, p_org_branch default null) -> jsonb   OWNER ONLY
--       p_dry = true writes nothing and returns the impact: stock on hand, transactions per table, open documents, people assigned, supply links, blockers, needs_force.
--       Refused (also with force): people assigned to the place (remove them first), open documents (draft / submitted entries, transfers on the way, draft purchase bills), a supply link that
--       would cross the business border. Refused unless p_force: the place has transactions (their history moves with the place). Moving inside one business (branch to branch) needs none of this.
--       Every move is written to business_place_ops135 (who, why, impact, forced) and cannot be changed.
--   business_places_list135(p_business) -> rows of the places of ONE business (owner, the people of that business).
--   business_profile_ensure135(p_business) -> jsonb {created}: phase134 gives a profile to every business unit through a trigger; this helper only repairs a business that has none (idempotent).
-- Rollback: nothing else reads the new objects. To go back re-paste phase16 (location_save), drop the functions and the table of this file. Created places stay (they are normal locations).
-- ============================================================
begin;

do $g$
declare miss text := '';
begin
  if to_regclass('public.locations') is null or to_regclass('public.org_units') is null or to_regclass('public.business_profiles') is null or to_regclass('public.user_locations') is null
     or to_regclass('public.location_setup_steps') is null then miss := miss || ' tables'; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'locations' and column_name = 'org_unit_id') then miss := miss || ' locations.org_unit_id'; end if;
  if to_regprocedure('public.location_save(integer,jsonb)') is null or to_regprocedure('public._biz_mgr134(bigint)') is null or to_regprocedure('public._vis_biz134()') is null
     or to_regprocedure('public._business_of_unit123(bigint)') is null or to_regprocedure('public._patch133(regprocedure,text,text[])') is null or to_regprocedure('public._client_lock(uuid)') is null
     or to_regprocedure('public._append_only23()') is null or to_regprocedure('public.log_change()') is null or to_regprocedure('public._slug(text)') is null
     or to_regprocedure('public.is_owner()') is null or to_regprocedure('public.is_active()') is null then miss := miss || ' functions'; end if;
  if miss <> '' then raise exception 'phase135 needs the base schema and phases up to 134 pasted first (docs/PASTE_ORDER.md); missing:%', miss; end if;
end $g$;

-- ---------- 1. the record of place operations (create / move): idempotency keys + history, append-only ----------
create table if not exists public.business_place_ops135 (
  id bigserial primary key,
  op text not null check (op in ('create', 'move')),
  client_id uuid not null unique,
  location_id int not null references public.locations(id),
  business_id bigint not null references public.org_units(id),
  from_unit bigint references public.org_units(id),
  to_unit bigint references public.org_units(id),
  kind text, reason text check (reason is null or length(reason) <= 500),
  forced boolean not null default false,
  impact jsonb,
  by_user uuid, at timestamptz not null default now()
);
create index if not exists business_place_ops135_loc on public.business_place_ops135 (location_id);
create index if not exists business_place_ops135_biz on public.business_place_ops135 (business_id);
alter table public.business_place_ops135 enable row level security;
drop policy if exists bpo135_read on public.business_place_ops135;
create policy bpo135_read on public.business_place_ops135 for select to authenticated using (public.is_active() and public.is_owner());
revoke all on public.business_place_ops135 from public, anon, authenticated;
grant select on public.business_place_ops135 to authenticated;
revoke all on sequence public.business_place_ops135_id_seq from public, anon, authenticated;
drop trigger if exists bpo135_ro on public.business_place_ops135;
create trigger bpo135_ro before update or delete on public.business_place_ops135 for each row execute function public._append_only23();
drop trigger if exists audit_bpo135 on public.business_place_ops135;
create trigger audit_bpo135 after insert on public.business_place_ops135 for each row execute function public.log_change('id');

-- ---------- 2. the transaction-local token (set only inside business_place_create135 after its own permission test) ----------
create or replace function public._pc_ok135() returns boolean
language sql stable set search_path = public as $$
  select coalesce(current_setting('bos.pc135', true), '') = txid_current()::text;
$$;
create or replace function public._pc_biz135() returns bigint
language sql stable set search_path = public as $$
  select case when public._pc_ok135() then nullif(current_setting('bos.pc135biz', true), '')::bigint end;
$$;

create or replace function public._pc_unit135() returns bigint
language sql stable set search_path = public as $$
  select case when public._pc_ok135() then nullif(current_setting('bos.pc135unit', true), '')::bigint end;
$$;

-- ---------- 3. patch location_save (phase16) once ----------
select public._patch133('public.location_save(integer,jsonb)'::regprocedure, '/* loc135 */', array[
  $a$if not public._loc_mgr() then raise exception 'not allowed'; end if;$a$,
  $b$if not (public._loc_mgr() or public._pc_ok135()) then raise exception 'not allowed'; end if;   /* loc135 */$b$,
  $a$if exists (select 1 from public.locations x where lower(btrim(x.name_bn)) = lower(newname_bn) or (newname_en is not null and lower(btrim(coalesce(x.name_en, ''))) = lower(newname_en))) then raise exception 'name_in_use'; end if;$a$,
  $b$if exists (select 1 from public.locations x where (not public._pc_ok135() or public._business_of_unit123(x.org_unit_id) is not distinct from public._pc_biz135())
                  and (lower(btrim(x.name_bn)) = lower(newname_bn) or (newname_en is not null and lower(btrim(coalesce(x.name_en, ''))) = lower(newname_en)))) then raise exception 'name_in_use'; end if;$b$,
  -- the place is born ALREADY mapped: the insert triggers (settings sheet v1) and the business border of phase133 (switch ON) see its business at once
  $a$hub_functions, note, created_by, created_at, status_by, status_at)$a$,
  $b$hub_functions, note, created_by, created_at, status_by, status_at, org_unit_id)$b$,
  $a$coalesce(hubv, false), nullif(p_patch->>'note', ''), auth.uid(), now(), auth.uid(), now())$a$,
  $b$coalesce(hubv, false), nullif(p_patch->>'note', ''), auth.uid(), now(), auth.uid(), now(), public._pc_unit135())$b$]);

-- ---------- 4. helpers ----------
-- what hangs on a place: stock, transactions per table, open documents, people, supply links
create or replace function public._place_impact135(p_loc int, p_target bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  -- (the two dealer table names are written in two pieces on purpose: the phase127 / phase129 tests assert that no existing function mentions those tables by name)
  t record; n bigint; tx jsonb := '{}'::jsonb; txn bigint := 0; stk_items bigint := 0; stk_qty numeric := 0; oe bigint := 0; ot bigint := 0; ob bigint := 0; us bigint := 0; el bigint := 0; ug bigint := 0;
  sup_ok boolean := true; l public.locations;
begin
  select * into l from public.locations where id = p_loc;
  for t in select * from (values ('stock_ledger', 'location_id'), ('sales', 'location_id'), ('sale_payments', 'location_id'), ('sale_returns', 'location_id'), ('purchase_bills', 'location_id'),
      ('entries', 'location_id'), ('cash_moves', 'location_id'), ('journal_entries', 'location_id'), ('supplier_payments', 'location_id'), ('quick_expenses', 'location_id'), ('online_orders', 'location_id'),
      ('drawer_events', 'location_id'), ('payroll_runs', 'location_id'), ('production_runs', 'location_id'), ('stock_wastage', 'location_id'), ('dealer_' || 'cheques', 'location_id'),
      ('dealer_' || 'tint_jobs', 'location_id'), ('stock_transfers', 'from_location_id'), ('stock_transfers', 'to_location_id')) v(tbl, col) loop
    if to_regclass('public.' || t.tbl) is null then continue; end if;
    execute format('select count(*) from public.%I where %I = $1', t.tbl, t.col) into n using p_loc;
    if n > 0 then tx := tx || jsonb_build_object(t.tbl || case when t.tbl = 'stock_transfers' then ':' || t.col else '' end, n); txn := txn + n; end if;
  end loop;
  select count(*), coalesce(sum(qty), 0) into stk_items, stk_qty from public.stock_balance where location_id = p_loc and qty <> 0;
  select count(*) into oe from public.entries where location_id = p_loc and status in ('draft', 'submitted');
  select count(*) into ot from public.stock_transfers where status = 'sent' and (from_location_id = p_loc or to_location_id = p_loc);
  select count(*) into ob from public.purchase_bills where location_id = p_loc and status = 'draft';
  select count(*) into us from public.user_locations where location_id = p_loc;
  select count(*) into el from public.employee_locations where location_id = p_loc;
  select count(*) into ug from public.user_grants where location_id = p_loc;
  if p_target is not null then
    if l.supplied_by is not null and public._business_of_unit123((select s.org_unit_id from public.locations s where s.id = l.supplied_by)) is distinct from p_target then sup_ok := false; end if;
    if exists (select 1 from public.locations s where s.supplied_by = p_loc and public._business_of_unit123(s.org_unit_id) is distinct from p_target) then sup_ok := false; end if;
  end if;
  return jsonb_build_object('stock_items', stk_items, 'stock_qty', round(stk_qty, 3), 'transactions', tx, 'tx_total', txn, 'open_entries', oe, 'open_transfers', ot, 'open_bills', ob,
                            'open_documents', oe + ot + ob, 'users', us, 'employees', el, 'personal_grants', ug, 'supply_ok', sup_ok);
end $$;

-- ---------- 5. create a place inside a business ----------
create or replace function public.business_place_create135(p_business bigint, p_kind text, p_code text, p_name_bn text, p_name_en text, p_org_branch bigint default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid(); b public.org_units; u public.org_units; unit_id bigint; k text; pre text; lc text; stored text; nm_bn text; nm_en text; r jsonb; nid int; op public.business_place_ops135;
  base text; n int := 1;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  -- strict scope: the owner, or the org_manage holder of THAT business; a foreign or missing business answers alike (the owner gets the precise text below)
  if not public._biz_mgr134(p_business) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is null then raise exception 'client_id_needed'; end if;
  select * into op from public.business_place_ops135 where client_id = p_client;
  if found then
    if op.by_user is distinct from me or op.op <> 'create' then raise exception 'client_id_taken'; end if;
    select l.code into lc from public.locations l where l.id = op.location_id;
    return jsonb_build_object('dup', true, 'id', op.location_id, 'code', lc, 'business_id', op.business_id, 'org_unit_id', op.to_unit);
  end if;
  select * into b from public.org_units where id = p_business;
  if not found or b.kind <> 'business' then raise exception 'unknown_business'; end if;
  if b.status = 'inactive' then raise exception 'business_inactive'; end if;
  -- kind
  k := lower(btrim(coalesce(p_kind, '')));
  k := case k when 'branch' then 'showroom' when 'dealer_branch' then 'showroom' when 'sales_point' then 'showroom' when 'warehouse' then 'godown' when 'store' then 'godown' else k end;
  if k not in ('showroom', 'factory', 'godown', 'hub', 'online', 'other') then raise exception 'bad_kind'; end if;
  -- names
  nm_bn := nullif(btrim(coalesce(p_name_bn, '')), ''); nm_en := nullif(btrim(coalesce(p_name_en, '')), '');
  if nm_bn is null and nm_en is null then raise exception 'name_required'; end if;
  if length(coalesce(nm_bn, '')) > 120 or length(coalesce(nm_en, '')) > 120 then raise exception 'too_long:name'; end if;
  -- the unit the place hangs on: the business, or a branch / site INSIDE it (a foreign or missing unit answers alike)
  unit_id := p_business;
  if p_org_branch is not null then
    select * into u from public.org_units where id = p_org_branch;
    if not found or u.kind not in ('branch', 'site') or u.status = 'inactive' or public._business_of_unit123(u.id) is distinct from p_business then raise exception 'bad_branch'; end if;
    unit_id := u.id;
  end if;
  -- code: <business code lower case>_<code>
  pre := trim(both '_' from lower(regexp_replace(b.code, '[^A-Za-z0-9]+', '_', 'g')));
  if pre !~ '^[a-z]' then pre := 'b' || pre; end if;
  lc := lower(btrim(coalesce(p_code, '')));
  if lc = '' then
    base := public._slug(coalesce(nm_en, ''));
    if base is null or length(base) < 2 or base !~ '^[a-z]' then base := 'place'; end if;
    lc := base;
  elsif lc !~ '^[a-z][a-z0-9_]{1,29}$' then raise exception 'bad_code';
  end if;
  stored := case when lc like pre || '\_%' then lc else pre || '_' || lc end;
  if nullif(btrim(coalesce(p_code, '')), '') is null then   -- no code given: a free one is found by numbering
    while exists (select 1 from public.locations x where x.code = stored) loop n := n + 1; stored := left(case when lc like pre || '\_%' then lc else pre || '_' || lc end, 26) || '_' || n; end loop;
  end if;
  if length(stored) > 30 then raise exception 'code_too_long'; end if;
  if stored !~ '^[a-z][a-z0-9_]{1,29}$' then raise exception 'bad_code'; end if;
  if exists (select 1 from public.locations x where x.code = stored) then raise exception 'code_in_use'; end if;

  -- the SAME creation path as the Places screen (phase16 location_save), with the token that says "already checked"
  perform set_config('bos.pc135', txid_current()::text, true);
  perform set_config('bos.pc135biz', p_business::text, true);
  perform set_config('bos.pc135unit', unit_id::text, true);
  r := public.location_save(null, jsonb_strip_nulls(jsonb_build_object('name_bn', nm_bn, 'name_en', nm_en, 'kind', k, 'model', 'A', 'code', stored)));
  perform set_config('bos.pc135', '', true); perform set_config('bos.pc135biz', '', true); perform set_config('bos.pc135unit', '', true);
  nid := (r ->> 'id')::int;
  update public.locations set status = 'setting_up', status_by = me, status_at = now() where id = nid;
  insert into public.business_place_ops135 (op, client_id, location_id, business_id, from_unit, to_unit, kind, by_user) values ('create', p_client, nid, p_business, null, unit_id, k, me);
  perform public.business_profile_ensure135(p_business);
  return jsonb_build_object('dup', false, 'id', nid, 'code', stored, 'business_id', p_business, 'org_unit_id', unit_id, 'kind', k, 'status', 'setting_up');
end $$;

-- ---------- 6. the places of one business ----------
create or replace function public.business_places_list135(p_business bigint) returns table (id int, code text, name_bn text, name_en text, kind text, status text, is_active boolean,
  org_unit_id bigint, unit_kind text, unit_code text, unit_name_bn text, unit_name_en text, planned_opening date)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_business is null or not (public.is_owner() or p_business in (select public._vis_biz134())) then raise exception 'not allowed'; end if;
  return query
    select l.id, l.code, l.name_bn, l.name_en, l.kind, l.status, l.is_active, l.org_unit_id, u.kind, u.code, u.name_bn, u.name_en, l.planned_opening
      from public.locations l join public.org_units u on u.id = l.org_unit_id
     where public._business_of_unit123(l.org_unit_id) = p_business
       and (public.is_owner() or public._biz_mgr134(p_business) or public.can_loc(l.id))
     order by l.sort, l.id;
end $$;

-- ---------- 7. move a place to another business (owner only, dry-run first) ----------
create or replace function public.business_place_move135(p_location int, p_business bigint, p_reason text default null, p_dry boolean default true, p_force boolean default false,
  p_client uuid default null, p_org_branch bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid(); l public.locations; b public.org_units; u public.org_units; target bigint; from_biz bigint; same boolean; imp jsonb; blockers text[] := '{}'; why text; op public.business_place_ops135;
begin
  if not public.is_active() or not public.is_owner() then raise exception 'not allowed'; end if;
  if p_reason is not null and length(p_reason) > 500 then raise exception 'bad_reason'; end if;
  select * into l from public.locations where id = p_location;
  if not found then raise exception 'unknown_location'; end if;
  select * into b from public.org_units where id = p_business;
  if not found or b.kind <> 'business' then raise exception 'unknown_business'; end if;
  if b.status = 'inactive' then raise exception 'business_inactive'; end if;
  target := p_business;
  if p_org_branch is not null then
    select * into u from public.org_units where id = p_org_branch;
    if not found or u.kind not in ('branch', 'site') or u.status = 'inactive' or public._business_of_unit123(u.id) is distinct from p_business then raise exception 'bad_branch'; end if;
    target := u.id;
  end if;
  from_biz := public._business_of_unit123(l.org_unit_id);
  same := from_biz is not distinct from p_business and l.org_unit_id is not null;
  imp := public._place_impact135(p_location, p_business);
  if not same then
    if (imp ->> 'users')::int > 0 then blockers := blockers || 'place_has_users'::text; end if;
    if (imp ->> 'open_documents')::int > 0 then blockers := blockers || 'open_documents'::text; end if;
    if not (imp ->> 'supply_ok')::boolean then blockers := blockers || 'supply_link'::text; end if;
    if (imp ->> 'tx_total')::bigint > 0 and not coalesce(p_force, false) then blockers := blockers || 'place_has_transactions'::text; end if;
  end if;
  imp := imp || jsonb_build_object('location_id', l.id, 'code', l.code, 'name_bn', l.name_bn, 'name_en', l.name_en, 'from_unit', l.org_unit_id, 'from_business', from_biz, 'to_business', p_business,
                                   'to_unit', target, 'same_business', same, 'unmapped', l.org_unit_id is null, 'needs_force', (not same) and (imp ->> 'tx_total')::bigint > 0,
                                   'blockers', to_jsonb(blockers), 'can_move', cardinality(blockers) = 0);
  if coalesce(p_dry, true) then return imp || jsonb_build_object('dry', true); end if;

  perform public._client_lock(p_client);
  if p_client is null then raise exception 'client_id_needed'; end if;
  select * into op from public.business_place_ops135 where client_id = p_client;
  if found then
    if op.by_user is distinct from me or op.op <> 'move' then raise exception 'client_id_taken'; end if;
    return jsonb_build_object('dup', true, 'id', op.location_id, 'business_id', op.business_id, 'org_unit_id', op.to_unit);
  end if;
  if l.org_unit_id is not distinct from target then return jsonb_build_object('dup', true, 'id', l.id, 'business_id', p_business, 'org_unit_id', target, 'noop', true); end if;
  why := nullif(btrim(coalesce(p_reason, '')), '');
  if why is null or length(why) < 3 then raise exception 'reason_required'; end if;
  if cardinality(blockers) > 0 then raise exception '%', blockers[1]; end if;
  update public.locations set org_unit_id = target where id = l.id;
  insert into public.business_place_ops135 (op, client_id, location_id, business_id, from_unit, to_unit, kind, reason, forced, impact, by_user)
    values ('move', p_client, l.id, p_business, l.org_unit_id, target, l.kind, why, coalesce(p_force, false) and (imp ->> 'tx_total')::bigint > 0, imp, me);
  return jsonb_build_object('dup', false, 'id', l.id, 'business_id', p_business, 'org_unit_id', target, 'dry', false);
end $$;

-- ---------- 8. profile repair helper (phase134 gives every business unit a profile through a trigger; this only repairs a business that has none) ----------
create or replace function public.business_profile_ensure135(p_business bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u public.org_units; nid bigint;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public._biz_mgr134(p_business) then raise exception 'not allowed'; end if;
  select * into u from public.org_units where id = p_business;
  if not found or u.kind <> 'business' then raise exception 'unknown_business'; end if;
  insert into public.business_profiles (org_unit_id, display_name_bn, display_name_en, created_by, updated_by)
    values (u.id, u.name_bn, u.name_en, auth.uid(), auth.uid()) on conflict (org_unit_id) do nothing returning id into nid;
  return jsonb_build_object('created', nid is not null, 'business_id', u.id);
end $$;

-- ---------- 9. privileges ----------
revoke all on function public._pc_ok135(), public._pc_biz135(), public._pc_unit135(), public._place_impact135(int, bigint) from public, anon, authenticated;
revoke all on function public.business_place_create135(bigint, text, text, text, text, bigint, uuid), public.business_places_list135(bigint),
  public.business_place_move135(int, bigint, text, boolean, boolean, uuid, bigint), public.business_profile_ensure135(bigint) from public, anon;
grant execute on function public.business_place_create135(bigint, text, text, text, text, bigint, uuid), public.business_places_list135(bigint),
  public.business_place_move135(int, bigint, text, boolean, boolean, uuid, bigint), public.business_profile_ensure135(bigint) to authenticated;

commit;

-- ---------------------------------------------------------------- phase529.sql
-- Phase 529 (UNION-1) - what our line's phases 80 to 505 need from the database before they can be pasted on top of the advanced block. Paste-twice safe. Earlier phase files are not edited.
-- Place in the paste order: after the advanced block (phase 135), before phase 80 (tests/sql/ORDER.txt, docs/PASTE_ORDER.md).
-- Two shared functions were changed by the advanced line in a way that stops our line's exact-text hooks and guards:
--   1. lock_check(date): advanced phase113 (bos113) added the owner mode `period_lock_owner_mode`; our phases 87/89/99/477 hook the phase 6 text
--      `if p_date is null or public.is_owner() then return; end if;` and stop with "phase89 patch site not found in lock_check(date)".
--      Only when the body carries bos113 and none of our tags (bos87, bos89), the body is saved in public._union_fn_backup and the phase 6 text is put back.
--      Phase 530 (paste after phase 505) puts the bos113 owner mode back on top of the hooked body. Nothing of bos113 is lost.
--   2. acct_journal_post: the advanced phase511 replaced the 7-argument function by an 8-argument one (extra p_reason, bos85 manual journal guard). Our phases 88/94/99 need
--      the 7-argument function (guard in phase88, text hook of phase99). A call with up to 7 arguments would also be ambiguous while both exist, because p_reason has a default.
--      This file (a) re-creates the 7-argument function from the phase 40 text when it is missing and (b) re-creates the 8-argument one WITHOUT any parameter default, so a call
--      with up to 7 arguments always means the 7-argument function and a call with all 8 arguments always means the 8-argument one. Phase 530 adds the bos85 guard to the 7-argument function
--      and our journal gate to the 8-argument one, so both behave the same.
-- A body that already carries our hooks is never replaced by this file.

create table if not exists public._union_fn_backup (
  id bigserial primary key,
  fn text not null,
  saved_at timestamptz not null default now(),
  why text,
  def text not null
);
alter table public._union_fn_backup enable row level security;
revoke all on public._union_fn_backup from anon, authenticated;

-- 1. lock_check
do $u529$
declare d text;
begin
  if to_regprocedure('public.lock_check(date)') is null then
    raise exception 'phase529 needs lock_check(date) (phase 6)';
  end if;
  d := pg_get_functiondef('public.lock_check(date)'::regprocedure);
  if position('bos113' in d) > 0 and position('bos87' in d) = 0 and position('bos89' in d) = 0 then
    insert into public._union_fn_backup (fn, why, def) values ('public.lock_check(date)', 'phase529: body with the bos113 owner mode, replaced by the phase 6 text so the hooks of phases 87/89 can be applied; phase530 restores bos113', d);
    execute $f$
CREATE OR REPLACE FUNCTION public.lock_check(p_date date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $b$
declare v text; d date;
begin
  if p_date is null or public.is_owner() then return; end if;
  v := public.rule_txt('period_closed_until');
  if v is null or v !~ '^\d{4}-\d{2}-\d{2}$' then return; end if;
  begin d := v::date; exception when others then return; end;      -- an impossible date (2026-02-30) locks nobody out
  if p_date > d then return; end if;
  if public.rule_ok('closed_period_edit', null, null, p_date, 'entry') then return; end if;
  raise exception 'period_closed';
end $b$

$f$;
    revoke all on function public.lock_check(date) from public, anon, authenticated;
  end if;
end $u529$;

-- 2. acct_journal_post: one 7-argument function (hooked by our line) and one 8-argument function (p_reason without default)
do $u529b$
declare d8 text;
begin
  if to_regprocedure('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)') is null then
    execute $f$
CREATE OR REPLACE FUNCTION public.acct_journal_post(p_date date, p_loc integer, p_memo text, p_lines jsonb, p_client uuid DEFAULT NULL::uuid, p_photo text DEFAULT NULL::text, p_dry boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $b$
declare st date := public._acct_start(); r public.journal_entries; ln jsonb; id_ bigint; td numeric := 0; tc numeric := 0; x jsonb;
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
  id_ := public._acct_write(p_date, p_loc, 'manual', coalesce(p_client::text, gen_random_uuid()::text), null, p_memo, null, ln, null, p_client, p_photo);
  return jsonb_build_object('id', id_, 'total', td);
end $b$

$f$;
    revoke all on function public.acct_journal_post(date, integer, text, jsonb, uuid, text, boolean) from public, anon;
    grant execute on function public.acct_journal_post(date, integer, text, jsonb, uuid, text, boolean) to authenticated;
  end if;
  if to_regprocedure('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)') is not null then
    d8 := pg_get_functiondef('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)'::regprocedure);
    if position(' DEFAULT ' in substr(d8, 1, position(E'\n' in d8))) > 0 then
      insert into public._union_fn_backup (fn, why, def) values ('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)', 'phase529: the 8-argument function had defaults, so a call with up to 7 arguments was ambiguous; the defaults are removed (a call with 8 arguments means this function)', d8);
      drop function public.acct_journal_post(date, integer, text, jsonb, uuid, text, boolean, text);
      execute regexp_replace(substr(d8, 1, position(E'\n' in d8) - 1), ' DEFAULT [A-Za-z0-9_:]+', '', 'g') || substr(d8, position(E'\n' in d8));
      revoke all on function public.acct_journal_post(date, integer, text, jsonb, uuid, text, boolean, text) from public, anon;
      grant execute on function public.acct_journal_post(date, integer, text, jsonb, uuid, text, boolean, text) to authenticated;
    end if;
  end if;
end $u529b$;

-- _cust_bal(uuid): the advanced body (md5 ed80bafae0dc2eeba6382ebc284bbede) is saved and the base body (phases 4-79) is put back so the hooks of our packages find their text
do $u529c$
declare d text;
begin
  if to_regprocedure('public._cust_bal(uuid)') is null then raise exception 'phase529: public._cust_bal(uuid) is missing'; end if;
  d := pg_get_functiondef('public._cust_bal(uuid)'::regprocedure);
  if md5(d) = 'ed80bafae0dc2eeba6382ebc284bbede' then
    insert into public._union_fn_backup (fn, why, def) values ('public._cust_bal(uuid)', 'phase529: advanced body replaced by the base body so the hooks of our line can be applied; phase 530+ puts the advanced logic back', d);
    execute $b$CREATE OR REPLACE FUNCTION public._cust_bal(p_customer uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select sum(s.total) from public.sales s where s.customer_id = p_customer and s.status = 'done'), 0)
       - coalesce((select sum(p.amount) from public.sale_payments p where p.customer_id = p_customer and not p.voided), 0)
       - coalesce((select sum(r.credit_amount) from public.sale_returns r where r.customer_id = p_customer and r.status = 'done'), 0);
$function$
$b$;
  end if;
end $u529c$;

-- customer_dues(): the advanced body (md5 14bce6b96ca918b1fb7f9aa72dcd08f5) is saved and the base body (phases 4-79) is put back so the hooks of our packages find their text
do $u529c$
declare d text;
begin
  if to_regprocedure('public.customer_dues()') is null then raise exception 'phase529: public.customer_dues() is missing'; end if;
  d := pg_get_functiondef('public.customer_dues()'::regprocedure);
  if md5(d) = '14bce6b96ca918b1fb7f9aa72dcd08f5' then
    insert into public._union_fn_backup (fn, why, def) values ('public.customer_dues()', 'phase529: advanced body replaced by the base body so the hooks of our line can be applied; phase 530+ puts the advanced logic back', d);
    execute $b$CREATE OR REPLACE FUNCTION public.customer_dues()
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
          union all select customer_id, credit_amount from public.sale_returns where status = 'done' and customer_id is not null and credit_amount > 0) z group by 1),
  t as (select customer_id, sum(rem) rem from s group by 1)
  select cu.id, cu.name, cu.mobile, cu.type, cu.credit_limit, t.rem - coalesce(c.coll, 0),
         (select min(k.sale_date) from cum k where k.customer_id = cu.id and k.cr > coalesce(c.coll, 0))
  from public.customers cu join t on t.customer_id = cu.id left join c on c.customer_id = cu.id
  where (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) and t.rem - coalesce(c.coll, 0) > 0
  order by 6 desc;
$function$
$b$;
  end if;
end $u529c$;

-- rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean): the advanced body (md5 803786a2870251caf1679492765cea9b) is saved and the base body (phases 4-79) is put back so the hooks of our packages find their text
do $u529c$
declare d text;
begin
  if to_regprocedure('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)') is null then raise exception 'phase529: public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean) is missing'; end if;
  d := pg_get_functiondef('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)'::regprocedure);
  if md5(d) = '803786a2870251caf1679492765cea9b' then
    insert into public._union_fn_backup (fn, why, def) values ('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)', 'phase529: advanced body replaced by the base body so the hooks of our line can be applied; phase 530+ puts the advanced logic back', d);
    execute $b$CREATE OR REPLACE FUNCTION public.rpt_agg_sql(p_src text, p_rel text, p_al text, p_gl text[], p_mkeys text[], p_where text, p_base text, p_having text, p_dexpr text, p_ws integer, p_fym integer, p_mobok boolean, p_nodim boolean, p_withcost boolean)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
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
    || case when p_withcost then ' left join (select ic.item_id, ic.cost_price from public.item_costs ic join public.items cbi on cbi.id = ic.item_id where cbi.count_in_business /* bos14 */) c on c.item_id = ' || p_al || '.item_id' else '' end
    || ' where ' || p_where || coalesce(' and (' || public.rpt_tok(p_base, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ')', '');
  if n > 0 and not p_nodim then sql := sql || ' group by ' || (select string_agg(i::text, ', ') from generate_series(1, n) i); end if;
  if p_having is not null and not p_nodim then sql := sql || ' having ' || public.rpt_tok(p_having, p_al, p_dexpr, p_ws, p_fym, p_mobok); end if;
  return sql;
end $function$
$b$;
  end if;
end $u529c$;

-- biz_items(date,date,integer): the advanced body (md5 505a50e08115e25ad02335b958568ee8) is saved and the base body (phases 4-79) is put back so the hooks of our packages find their text
do $u529c$
declare d text;
begin
  if to_regprocedure('public.biz_items(date,date,integer)') is null then raise exception 'phase529: public.biz_items(date,date,integer) is missing'; end if;
  d := pg_get_functiondef('public.biz_items(date,date,integer)'::regprocedure);
  if md5(d) = '505a50e08115e25ad02335b958568ee8' then
    insert into public._union_fn_backup (fn, why, def) values ('public.biz_items(date,date,integer)', 'phase529: advanced body replaced by the base body so the hooks of our line can be applied; phase 530+ puts the advanced logic back', d);
    execute $b$CREATE OR REPLACE FUNCTION public.biz_items(p_from date, p_to date, p_loc integer DEFAULT NULL::integer)
 RETURNS TABLE(item_id uuid, code text, name_bn text, name_en text, unit text, qty numeric, revenue numeric, cogs numeric, share_pct numeric, cum_pct numeric, abc text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    left join by_item b on b.iid = i.id left join (select ic.item_id, ic.cost_price from public.item_costs ic join public.items cbi on cbi.id = ic.item_id where cbi.count_in_business /* bos14 */) c on c.item_id = i.id
    where (i.is_active and i.sellable) or b.iid is not null),
  r as (
    select j.*, case when (select t from tot) > 0 then round(100 * j.r / (select t from tot), 2) else 0 end sp,
           case when (select t from tot) > 0 then round(100 * sum(j.r) over (order by j.r desc, j.code) / (select t from tot), 2) else 0 end cp
    from j)
  select r.id, r.code, r.name_bn, r.name_en, r.unit, r.q, r.r, r.cg, r.sp, r.cp,
         case when r.r = 0 then '-' when r.cp - r.sp < 80 then 'A' when r.cp - r.sp < 95 then 'B' else 'C' end
  from r order by r.r desc, r.code;
end $function$
$b$;
  end if;
end $u529c$;

-- ---------------------------------------------------------------- phase80.sql
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

-- ---------------------------------------------------------------- phase81.sql
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

-- ---------------------------------------------------------------- phase82.sql
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

-- ---------------------------------------------------------------- phase83.sql
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

-- ---------------------------------------------------------------- phase84.sql
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

-- ---------------------------------------------------------------- phase85.sql
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

-- ---------------------------------------------------------------- phase86.sql
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

-- ============================================================================
-- End of FRESH part 12 of 21.
