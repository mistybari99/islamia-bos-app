-- ============================================================================
-- FRESH part 21 of 21. Paste the WHOLE of this file into the Supabase SQL editor, press Run, wait for "Success", then paste the next part.
-- Phases in this part, in this order: phase547 phase548 phase549 phase550 phase551 phase552 phase553
-- Never paste: any *_test.sql, the phase84 / 84b / 84c TEST-PROJECT files, ALL_NEW2..ALL_NEW11*. Commit: see docs/PASTE_ORDER.md.
-- ============================================================================

-- ---------------------------------------------------------------- phase547.sql
-- ============================================================
-- Phase 547 - Backup coverage: AI settings tables, the staff / login manifest, extra Storage buckets, per-device list
-- Run AFTER phase46, phase98 and phase106 (and after phase539 if you use _union_audit). Paste-twice safe. Earlier phase files are not edited. Nothing is deleted.
-- Audit that led here: docs/BACKUP_COVERAGE.md. Owner steps: docs/BACKUP_AND_RESTORE_GUIDE.md.
--
--   1. public._backup_tables() is re-created from its LATEST body (phase106) with ONE change: the columns monthly_token_budget and max_output_tokens (AI token
--      numbers, not credentials) no longer count as secret-looking. Before this change ai_agents and ai_providers (the owner's AI settings) were silently
--      missing from every nightly backup. Everything else is identical: *_secret*, ops_*, login_*, backup_runs, notifications, notification_reads and every
--      table with a password / pin_hash / secret / token / salt / api_key / private_key column stay out. Pure addition of two settings tables to the dump.
--   2. Two rules, both OFF (new behaviour starts only when the owner switches it on):
--        backup_accounts_on  the nightly backup also saves the staff / login MANIFEST (see 3)
--        backup_buckets_on   the backup bot may also READ the other Storage buckets (web-refs, payproof, web-public); bucket photos is always readable (phase46)
--   3. public.backup_accounts_manifest()  backup bot only. Returns, per login: id, staff id, e-mail, name, status, language, created_at, roles, locations,
--      grants (code, location, valid_until, note), whether a second factor (2FA) is enrolled, which bot purposes it has - plus the attendance devices WITHOUT
--      token_hash and the ops_accounts marks. It NEVER reads a password, a PIN hash, a token or an MFA secret (auth.users.encrypted_password is not selected).
--      With the rule OFF it answers {"enabled": false} and nothing else.
--   4. public.backup_storage_buckets()  backup bot only: the buckets (id, public, size limit, mime types), number of objects and bytes, and whether the bot can
--      read them. Used by tools/backup_photos.py --all-buckets.
--   5. Storage policy ops_buckets_read on storage.objects (select): the backup bot, rule backup_buckets_on = true, buckets web-refs / payproof / web-public.
--   6. public._union_fn_expected: the expected md5 of _backup_tables() is moved to the new text so that _union_audit() keeps saying "merged".
-- ============================================================

do $g$
begin
  if to_regprocedure('public._backup_tables()') is null or to_regprocedure('public._is_ops(text)') is null or to_regprocedure('public.rule_on(text)') is null then
    raise exception 'phase547 needs phase 46 (backup functions) and the rules engine first';
  end if;
  if to_regclass('public.ops_accounts') is null or to_regclass('public.user_grants') is null or to_regclass('public.attendance_devices') is null then
    raise exception 'phase547 needs the tables ops_accounts, user_grants and attendance_devices (phases 46, 28, 8x) first';
  end if;
end $g$;

-- 1. identical to phase106 except monthly_token_budget (AI budget numbers of ai_agents / ai_providers) is not secret-looking
create or replace function public._backup_tables() returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(c.relname::text order by c.relname), '{}'::text[])
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relispartition
     and c.relname::text not like '%\_secret%' escape '\'
     and c.relname::text not like 'ops\_%' escape '\'
     and c.relname::text not in ('login_failures', 'login_attempts', 'login_throttle', 'backup_runs', 'notifications', 'notification_reads')
     and not exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
                      and a.attname::text !~ '^(tokens_(in|out)|token_[ab]|monthly_token_budget|max_output_tokens)$'
                      and a.attname::text ~* '(password|passwd|pin_hash|secret|token|salt|api_key|private_key)');
$$;
comment on function public._backup_tables() is 'bos547: backup / restore-drill table list (computed). token_a/token_b (perm_conflict) and monthly_token_budget, max_output_tokens (ai_agents, ai_providers) are not secrets.';

-- 2. the two switches (OFF)
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('backup_accounts_on', 'notify', 'switch', 'false'::jsonb, null, null, null, null,
  'ব্যাকআপে স্টাফ লগইনের তালিকা রাখুন', 'Backup-এ Staff login-এর তালিকা রাখুন', 'Save the staff login list in the backup',
  'বন্ধ = আগের মতোই। চালু = রাতের ব্যাকআপে প্রতিজনের staff id, নাম, role, জায়গা, grant থাকবে (পাসওয়ার্ড বা PIN কখনো নয়)। নতুন project-এ লগইন আবার বানাতে লাগে।',
  'OFF = as before. ON = the nightly backup also holds every person''s staff id, name, roles, locations and grants (never a password or PIN). Needed to re-create the logins in a new project.',
  'OFF = as before. ON = the nightly backup also holds every person''s staff id, name, roles, locations and grants (never a password or PIN). Needed to re-create the logins in a new project.', 922),
 ('backup_buckets_on', 'notify', 'switch', 'false'::jsonb, null, null, null, null,
  'ব্যাকআপ-bot অন্য ছবির bucket-ও পড়তে পারবে', 'Backup bot অন্য ছবির bucket-ও পড়তে পারবে', 'Backup bot may also read the other photo buckets',
  'বন্ধ = শুধু photos bucket। চালু = web-refs, payproof, web-public bucketও ব্যাকআপে যাবে (শুধু পড়ার অনুমতি)।',
  'OFF = only the photos bucket is read (as before). ON = the backup bot may also read web-refs, payproof and web-public (read only) so that they are in the backup.',
  'OFF = only the photos bucket is read (as before). ON = the backup bot may also read web-refs, payproof and web-public (read only) so that they are in the backup.', 923)
 on conflict (key) do nothing;

-- 3. the staff / login manifest (no password, no PIN hash, no token, no MFA secret)
create or replace function public.backup_accounts_manifest() returns jsonb
language plpgsql security definer set search_path = public as $$
declare accts jsonb; devs jsonb; ops jsonb; mfa_ids uuid[] := '{}'::uuid[]; has_mfa boolean := false; cols text;
begin
  if not public._is_ops('backup') then raise exception 'not allowed'; end if;
  if not public.rule_on('backup_accounts_on') then
    return jsonb_build_object('enabled', false, 'note', 'rule backup_accounts_on is OFF');
  end if;
  if to_regclass('auth.mfa_factors') is not null then
    has_mfa := true;
    execute 'select coalesce(array_agg(distinct user_id), ''{}''::uuid[]) from auth.mfa_factors' into mfa_ids;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id, 'staff_id', p.staff_id, 'email', lower(u.email), 'full_name', p.full_name, 'status', p.status, 'lang', p.lang, 'created_at', p.created_at,
      'roles', coalesce((select jsonb_agg(r.role_code order by r.role_code) from public.user_roles r where r.user_id = p.id), '[]'::jsonb),
      'locations', coalesce((select jsonb_agg(l.location_id order by l.location_id) from public.user_locations l where l.user_id = p.id), '[]'::jsonb),
      'grants', coalesce((select jsonb_agg(jsonb_build_object('grant_code', g.grant_code, 'location_id', g.location_id, 'valid_until', g.valid_until, 'note', g.note) order by g.grant_code, g.location_id, g.id)
                            from public.user_grants g where g.user_id = p.id), '[]'::jsonb),
      'bot_purposes', coalesce((select jsonb_agg(o.purpose order by o.purpose) from public.ops_accounts o where o.user_id = p.id and o.active), '[]'::jsonb),
      'has_2fa', p.id = any (mfa_ids)) order by p.staff_id, p.id), '[]'::jsonb)
    into accts
    from public.profiles p left join auth.users u on u.id = p.id;
  -- attendance devices WITHOUT token_hash: the device has to be enrolled again after a restore (a new token is made then)
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name, 'location_id', d.location_id, 'vendor', d.vendor, 'serial', d.serial, 'active', d.active, 'created_at', d.created_at) order by d.id), '[]'::jsonb)
    into devs from public.attendance_devices d;
  select coalesce(jsonb_agg(jsonb_build_object('user_id', o.user_id, 'purpose', o.purpose, 'active', o.active) order by o.user_id, o.purpose), '[]'::jsonb) into ops from public.ops_accounts o;
  return jsonb_build_object('enabled', true, 'version', 1, 'generated_at', now(), 'mfa_table_present', has_mfa,
    'logins', jsonb_array_length(accts), 'accounts', accts, 'attendance_devices', devs, 'ops_accounts', ops,
    'never_included', jsonb_build_array('passwords', 'PIN hashes', 'device token hashes', 'MFA secrets', 'sessions'));
end $$;

-- 4. buckets
create or replace function public.backup_storage_buckets() returns jsonb
language plpgsql security definer set search_path = public as $$
declare arr jsonb := '[]'::jsonb; b record; n bigint; sz bigint; on_ boolean; readable boolean;
begin
  if not public._is_ops('backup') then raise exception 'not allowed'; end if;
  if to_regclass('storage.buckets') is null or to_regclass('storage.objects') is null then
    return jsonb_build_object('buckets', '[]'::jsonb, 'note', 'no storage schema here');
  end if;
  on_ := public.rule_on('backup_buckets_on');
  for b in execute 'select id::text id, coalesce(public, false) pub, file_size_limit, allowed_mime_types from storage.buckets order by id' loop
    execute 'select count(*), coalesce(sum(coalesce((to_jsonb(o) -> ''metadata'' ->> ''size'')::bigint, 0)), 0) from storage.objects o where o.bucket_id = $1' into n, sz using b.id;
    readable := b.id = 'photos' or (on_ and b.id in ('web-refs', 'payproof', 'web-public'));
    arr := arr || jsonb_build_object('id', b.id, 'public', b.pub, 'file_size_limit', b.file_size_limit, 'allowed_mime_types', to_jsonb(b.allowed_mime_types),
                                     'objects', n, 'bytes', sz, 'bot_can_read', readable);
  end loop;
  return jsonb_build_object('buckets', arr, 'buckets_rule_on', on_);
end $$;

-- 5. the read policy for the other buckets (rule backup_buckets_on, default OFF)
do $$ begin
  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists ops_buckets_read on storage.objects';
    execute 'create policy ops_buckets_read on storage.objects for select to authenticated using (bucket_id in (''web-refs'', ''payproof'', ''web-public'') and public._is_ops(''backup'') and public.rule_on(''backup_buckets_on''))';
  end if;
end $$;

-- grants: only a signed-in user may call; the function itself refuses everybody but the backup bot
revoke all on function public.backup_accounts_manifest() from public, anon, authenticated;
revoke all on function public.backup_storage_buckets() from public, anon, authenticated;
grant execute on function public.backup_accounts_manifest() to authenticated;
grant execute on function public.backup_storage_buckets() to authenticated;

-- 6. keep _union_audit() honest about the new text of _backup_tables()
do $u$ begin
  if to_regclass('public._union_fn_expected') is not null then
    update public._union_fn_expected set md5_text = md5(rtrim(pg_get_functiondef(to_regprocedure('public._backup_tables()')), E'\n')) where fn = 'public._backup_tables()';
  end if;
end $u$;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase548.sql
-- Phase 548 (READINESS D8) - stock_recon_period: the movement reason transit_loss is a listed movement.
-- Paste AFTER phase547 (last file of the canonical order). Paste-twice safe (a second paste finds the text already patched and does nothing). Earlier phase files are not edited.
-- From the readiness audit of 23 Oct 2026 (docs/READINESS_99.md, defect D8; first drafted as phase 547, renamed 548 on 24 Oct). Tested on a LOCAL throwaway PostgreSQL 16 only (supabase/phase548_test.sql, readiness scenario R17); the owner pastes it himself after review.
-- Ordered into the canonical chain on 24 Oct 2026 because the test proves: only stock_recon_period changes, no other function, no rule, no table, and with default settings the scenario output is identical except R17 (the fix).
-- Problem (reproduced): with transit_short_mode = loss (the setup advisor sets it), a short receipt writes a ledger row with reason transit_loss
--   (phase 499 / 114). stock_recon_period (phase 423) does not know that reason, so the period statement shows "unclassified -0.5" and state
--   "unclassified" for the receiving place although opening + movements = closing holds. Nothing is lost; the statement is just not able to say so.
-- Fix: the function text is read from the database (so later patches to it are kept), three anchors are replaced, and the function is created again:
--   (1) one more column in the movement sums: transit_loss, (2) it is part of the listed movements, (3) it is returned as the key transit_loss in every row.
-- No new switch: with no transit_loss row in a period the result is identical to today (the new key is 0).
-- Business reason (decided, not asked): a statement that calls a known, costed movement "unclassified" teaches people to ignore the word.

do $p548$
declare d text; o text; sig regprocedure := 'public.stock_recon_period(date, date, integer, text[])'::regprocedure;
  a2 constant text := 'coalesce(a.reversal, 0) as listed';
  a3 constant text := '''reversal'', coalesce(r.reversal, 0),';
begin
  select pg_get_functiondef(sig) into d;
  if d is null then raise exception 'phase548: stock_recon_period not found'; end if;
  if position('transit_loss' in d) > 0 then return; end if;                       -- already patched: paste twice does nothing
  o := d;
  if position(a2 in d) = 0 or position(a3 in d) = 0 or position('as reversal' in d) = 0 then
    raise exception 'phase548: an anchor of stock_recon_period was not found (the function text changed); nothing was changed';
  end if;
  d := replace(d, 'as reversal', 'as reversal, sum(l.qty_delta) filter (where l.reason = ''transit_loss'' and (l.made_at at time zone ''Asia/Dhaka'')::date between p_from and p_to) as transit_loss');
  d := replace(d, a2, 'coalesce(a.reversal, 0) + coalesce(a.transit_loss, 0) as listed');
  d := replace(d, a3, '''reversal'', coalesce(r.reversal, 0), ''transit_loss'', coalesce(r.transit_loss, 0),');
  if d = o then raise exception 'phase548: nothing replaced'; end if;
  execute d;
end $p548$;

-- ---------------------------------------------------------------- phase549.sql
-- Phase 549 (READINESS D1) - freight / transporter payable (account 2150) is visible in the supplier lists and payable through the normal supplier payment.
-- Paste AFTER phase548. Paste-twice safe (every patch looks for its own marker first). Earlier phase files are not edited.
-- Problem (reproduced by tests/sql/readiness, scenario P2/P3): a landed cost with a charge line pay_mode = payable and supplier_id = transporter credits account 2150
--   with the transporter as party (phase 97). supplier_dues / supplier_open_bills / supplier_ledger / _sup_balance only know purchase bills, so the transporter
--   is owed 490 in the books but appears in no list, and pay_supplier raises 'overpaid'.
-- Fix (additive): (1) column supplier_payments.landed_part (the part of a payment that settles landed charges; default 0); (2) a BEFORE INSERT trigger sets it:
--   ordinary bills are settled first, the rest (up to what is owed for landed charges) settles the landed charges; every payment path (pay_supplier, the approved
--   pay request, cheque clear) goes through it; (3) _lc_open() = landed charges still owed per supplier and place; (4) patches at anchors: _sup_open (landed rows appear
--   as the pseudo-bill "Landed charges", payments only reduce ordinary bills by amount - landed_part), _sup_balance (+ landed charges), supplier_ledger (a "landed" row per cost),
--   _acct_docs (a supplier payment debits 2150 for its landed part and 2100 for the rest), acct_reconcile (compares 2100 with the ordinary balance only).
-- No new rule: with no landed charge payable to a supplier every result is identical to before (landed_part stays 0). The behaviour starts when such a charge exists.
-- Every journal entry still balances: the two debit lines add up to the payment amount, the credit line is unchanged.
-- Test: supabase/phase549_test.sql and the readiness scenario (P2, P3).

alter table public.supplier_payments add column if not exists landed_part numeric not null default 0;
do $c$ begin
  if not exists (select 1 from pg_constraint where conname = 'supplier_payments_landed_part_chk549') then
    alter table public.supplier_payments add constraint supplier_payments_landed_part_chk549 check (landed_part >= 0 and landed_part <= amount);
  end if;
end $c$;

-- landed charges still owed, per supplier and place (payable lines of posted landed costs, minus the landed parts paid; payments are applied oldest place first)
create or replace function public._lc_open(p_supplier uuid default null)
returns table(supplier_id uuid, location_id integer, oldest date, open_amt numeric) language sql stable security definer set search_path = public as $$
  with ch as (
    select l.supplier_id, c.location_id, min(c.cost_date) oldest, sum(a.amount) charged
    from public.landed_cost_alloc a join public.landed_cost_lines l on l.id = a.charge_line_id join public.landed_costs c on c.id = a.cost_id
    where a.kind = 'post' and c.status = 'posted' and l.pay_mode = 'payable' and l.supplier_id is not null and (p_supplier is null or l.supplier_id = p_supplier)
    group by l.supplier_id, c.location_id),
  paid as (select p.supplier_id, sum(p.landed_part) paid from public.supplier_payments p where not p.voided and p.landed_part > 0 and (p_supplier is null or p.supplier_id = p_supplier) group by 1),
  cum as (select ch.*, sum(ch.charged) over (partition by ch.supplier_id order by ch.oldest, ch.location_id) cs from ch)
  select cum.supplier_id, cum.location_id, cum.oldest,
         cum.charged - least(cum.charged, greatest(0, coalesce(paid.paid, 0) - (cum.cs - cum.charged)))
  from cum left join paid on paid.supplier_id = cum.supplier_id $$;

create or replace function public._lc_charged(p_supplier uuid) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(a.amount), 0)
  from public.landed_cost_alloc a join public.landed_cost_lines l on l.id = a.charge_line_id join public.landed_costs c on c.id = a.cost_id
  where a.kind = 'post' and c.status = 'posted' and l.pay_mode = 'payable' and l.supplier_id = p_supplier $$;

create or replace function public._lc_open_total(p_supplier uuid) returns numeric language sql stable security definer set search_path = public as $$
  select public._lc_charged(p_supplier) - coalesce((select sum(p.landed_part) from public.supplier_payments p where p.supplier_id = p_supplier and not p.voided), 0) $$;

-- the debit lines of a supplier payment journal entry (2100 for the ordinary part, 2150 for the landed part; no zero line)
create or replace function public._p549_pay_debits(p_amount numeric, p_landed numeric, p_supplier uuid) returns jsonb language sql immutable set search_path = public as $$
  select coalesce(jsonb_agg(x), '[]'::jsonb) from (
    select jsonb_build_object('a', 'payable', 'd', p_amount - coalesce(p_landed, 0), 'pt', 'supplier', 'pid', p_supplier::text) x where p_amount - coalesce(p_landed, 0) > 0
    union all
    select jsonb_build_object('a', 'landed_payable', 'd', p_landed, 'pt', 'supplier', 'pid', p_supplier::text) where coalesce(p_landed, 0) > 0) z $$;

-- the split: ordinary bills first, the rest settles landed charges
create or replace function public._p549_split_bi() returns trigger language plpgsql security definer set search_path = public as $$
declare lc numeric; tot numeric; ord numeric;
begin
  lc := public._lc_open_total(new.supplier_id);
  if lc is null or lc <= 0 then new.landed_part := 0; return new; end if;
  tot := public._sup_balance(new.supplier_id);                 -- includes the landed charges (patched below)
  ord := greatest(tot - lc, 0);
  new.landed_part := least(lc, greatest(0, new.amount - ord));
  return new;
end $$;
drop trigger if exists zz549_landed_split_bi on public.supplier_payments;
create trigger zz549_landed_split_bi before insert on public.supplier_payments for each row execute function public._p549_split_bi();

create or replace function public._sup_balance_ord(p_supplier uuid) returns numeric language sql stable security definer set search_path = public as $$
  select public._sup_balance(p_supplier) - greatest(public._lc_open_total(p_supplier), 0) $$;

revoke all on function public._lc_open(uuid), public._lc_charged(uuid), public._lc_open_total(uuid), public._p549_pay_debits(numeric, numeric, uuid), public._p549_split_bi(), public._sup_balance_ord(uuid) from public, anon, authenticated;

-- patch helper (dropped at the end): the function text is read from the database, so later patches to it are kept
create or replace function public._p549_patch(p_sig text, p_marker text, p_from text[], p_to text[]) returns void language plpgsql as $$
declare d text; i int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into d;
  if d is null then raise exception 'phase549: % not found', p_sig; end if;
  if position(p_marker in d) > 0 then return; end if;               -- already patched: paste twice does nothing
  for i in 1 .. array_length(p_from, 1) loop
    if position(p_from[i] in d) = 0 then raise exception 'phase549: an anchor of % was not found (the function text changed); nothing was changed: %', p_sig, left(p_from[i], 80); end if;
    d := replace(d, p_from[i], p_to[i]);
  end loop;
  execute d;
end $$;

select public._p549_patch('public._sup_open(uuid)', '/* p549 */',
  array['p.amount x from public.supplier_payments p', 'from c2 left join pool on pool.supplier_id = c2.supplier_id;'],
  array['p.amount - p.landed_part x /* p549 */ from public.supplier_payments p',
        E'from c2 left join pool on pool.supplier_id = c2.supplier_id\n  union all select o.supplier_id, null::uuid, ''Landed charges''::text, o.oldest, o.location_id, o.open_amt, o.open_amt from public._lc_open(p_supplier) o where o.open_amt > 0;']);

select public._p549_patch('public._sup_balance(uuid)', '/* p549 */',
  array['and not voided), 0);'],
  array['and not voided), 0)
       + coalesce(public._lc_charged(p_supplier), 0) /* p549 */;']);

select public._p549_patch('public.supplier_ledger(uuid,integer)', '/* p549 */',
  array['select f.refunded_at, ''refund'''],
  array['select (c.cost_date::timestamp at time zone ''Asia/Dhaka''), ''landed''::text, coalesce(nullif(c.shipment_ref, ''''), left(c.id::text, 8)), c.location_id, sum(a.amount), 0::numeric, null::text, null::bigint, null::uuid, 1 /* p549 */
        from public.landed_cost_alloc a join public.landed_cost_lines l on l.id = a.charge_line_id join public.landed_costs c on c.id = a.cost_id
        where a.kind = ''post'' and c.status = ''posted'' and l.pay_mode = ''payable'' and l.supplier_id = p_supplier and (p_loc is null or c.location_id = p_loc)
        group by c.id, c.cost_date, c.shipment_ref, c.location_id
      union all
      select f.refunded_at, ''refund''']);

select public._p549_patch('public._acct_docs(date)', '_p549_pay_debits',
  array['case when not p.voided then jsonb_build_array(jsonb_build_object(''a'', ''payable'', ''d'', p.amount, ''pt'', ''supplier'', ''pid'', p.supplier_id::text),'],
  array['case when not p.voided then public._p549_pay_debits(p.amount, p.landed_part, p.supplier_id) || jsonb_build_array(']);

select public._p549_patch('public.acct_reconcile(text)', '_sup_balance_ord',
  array['coalesce(public._sup_balance(s.id), 0) l', 'coalesce(public._sup_balance(s.id), 0) <> 0'],
  array['coalesce(public._sup_balance_ord(s.id), 0) l', 'coalesce(public._sup_balance_ord(s.id), 0) <> 0']);

drop function public._p549_patch(text, text, text[], text[]);

-- ---------------------------------------------------------------- phase550.sql
-- Phase 550 (READINESS D4) - report gross profit (gp, gp_pct, cogs of the cost-join reports, e.g. sales_summary) is net of sale returns, as net_after_returns already is.
-- Paste AFTER phase549. Paste-twice safe (the patch looks for its own marker first). Earlier phase files are not edited.
-- Problem (reproduced, readiness scenario G3): report_run('sales_summary', ..., 'location') shows net_after_returns 3,850 for the place but gp 3,363.22 (= 4,050 - 686.78):
--   the cost columns come from the sales lines only, the returns are left out. biz_daily, the ledger, l1_pnl and l2_margin say 3,198.55 (= 3,850 - 651.45).
-- Fix: in _rptb1_agg_wrap, when the owner's rule reports_net_of_returns is ON (its default is ON since phase 23: the recorded decision "sales reports are net of returns"),
--   the costed revenue and the COGS of the returned lines (the same source as biz_daily: _cogs_lines72, rows of the return documents) are subtracted per group:
--   cogs = cogs - returned cogs; gp = gp - returned costed revenue + returned cogs; gp_pct = gp / (costed revenue - returned costed revenue).
--   uncosted_pct is left as it was. With the rule OFF the reports are unchanged. No new rule; it follows the existing switch.
-- Only reports that have a returns column AND the cost columns (cost_join = 1, src bill: sales_summary and the reports built on it) are touched; with no returns in the period every number is identical.
-- Test: supabase/phase550_test.sql and the readiness scenario (G3).

create or replace function public._p550_patch(p_sig text, p_marker text, p_from text[], p_to text[]) returns void language plpgsql as $$
declare d text; i int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into d;
  if d is null then raise exception 'phase550: % not found', p_sig; end if;
  if position(p_marker in d) > 0 then return; end if;
  for i in 1 .. array_length(p_from, 1) loop
    if position(p_from[i] in d) = 0 then raise exception 'phase550: an anchor of % was not found (the function text changed); nothing was changed: %', p_sig, left(p_from[i], 80); end if;
    d := replace(d, p_from[i], p_to[i]);
  end loop;
  execute d;
end $$;

select public._p550_patch('public._rptb1_agg_wrap(jsonb,text[],text[],jsonb,integer[],date,date,text,integer,integer,boolean,boolean,text,text)', '/* p550 */',
  array[
    'rqt := format(''select %s from %s %s where %s'', amts, rel, al, w);',
    E'if cost_extra then\n    foreach k in array extra loop rows_sel := rows_sel || format(''bq.%I as %I'', k, k); tot_sel := tot_sel || format(''bq.%I as %I'', k, k); end loop;\n  end if;'],
  array[
    E'if cost_extra and net_on then   /* p550 */\n    amts := amts || '', coalesce(sum(b.rc_cr), 0) as r_cr, coalesce(sum(b.rc_cg), 0) as r_cg'';\n    rel := ''(select b0.*, rc.cr as rc_cr, rc.cg as rc_cg from public.rpt_ret_b b0 left join (select h.doc_id as did, sum(h.led_rev + h.fb_rev) as cr, sum(h.led_cogs + h.fb_cogs) as cg from public._cogs_lines72(''\n      || quote_literal(p_from::text) || ''::date, '' || quote_literal(p_to::text) || ''::date, public._cogs_locs72(null)) h where h.src = ''''return'''' group by 1) rc on rc.did = b0.return_id)'';\n  end if;\n  rqt := format(''select %s from %s %s where %s'', amts, rel, al, w);',
    E'if cost_extra then\n    foreach k in array extra loop\n      if net_on and k = ''cogs'' then ex := ''round(bq.cogs - coalesce(rq.r_cg, 0), 2) as cogs''; rows_sel := rows_sel || ex; tot_sel := tot_sel || ex;\n      elsif net_on and k = ''gp'' then ex := ''round(bq.gp - coalesce(rq.r_cr, 0) + coalesce(rq.r_cg, 0), 2) as gp''; rows_sel := rows_sel || ex; tot_sel := tot_sel || ex;\n      elsif net_on and k = ''gp_pct'' then ex := ''round(100 * (bq.gp - coalesce(rq.r_cr, 0) + coalesce(rq.r_cg, 0)) / nullif(bq.gp + bq.cogs - coalesce(rq.r_cr, 0), 0), 2) as gp_pct''; rows_sel := rows_sel || ex; tot_sel := tot_sel || ex;\n      else rows_sel := rows_sel || format(''bq.%I as %I'', k, k); tot_sel := tot_sel || format(''bq.%I as %I'', k, k); end if;\n    end loop;\n  end if;']);

drop function public._p550_patch(text, text, text[], text[]);

-- ---------------------------------------------------------------- phase551.sql
-- Phase 551 (READINESS D7) - the staff-cost report t3_payroll reads the app payroll runs when the owner's salary source says so.
-- Paste AFTER phase550. Paste-twice safe (marker). Earlier phase files are not edited.
-- Problem (reproduced, readiness scenario R18c): after two paid payroll runs (net pay 9,613) report_run2('t3_payroll') showed net_pay 0: it reads only the paper sheets 21-1 and 35-1.
--   L1 (l1_pnl, _p27_pl, t4) and c2_salary_basis already use the runs when the rule report_salary_source = app_first (or payroll_accrual_on is on).
-- Fix: _r3q_t3_payroll follows the SAME switch: when it is on, a month that has a paid payroll run in the range is taken from the run lines (gross = net + deductions, advance recovery,
--   other deductions, net = the line's net) and the paper sheets of that month are left out (no double count); months without a run still use the sheets.
--   The default of report_salary_source is legacy, so with defaults the report is identical to before. Advisor row: phase 553.
-- Test: supabase/phase551_test.sql and the readiness scenario (R18c, run with report_salary_source = app_first in the advisor-plus mode).

create or replace function public._p551_app_salary() returns boolean language sql stable security definer set search_path = public as $$
  select public._w1d_salary_app_first() or coalesce(public.rule_on('payroll_accrual_on'), false) $$;
revoke all on function public._p551_app_salary() from public, anon, authenticated;

create or replace function public._p551_patch(p_sig text, p_marker text, p_from text[], p_to text[]) returns void language plpgsql as $$
declare d text; i int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into d;
  if d is null then raise exception 'phase551: % not found', p_sig; end if;
  if position(p_marker in d) > 0 then return; end if;
  for i in 1 .. array_length(p_from, 1) loop
    if position(p_from[i] in d) = 0 then raise exception 'phase551: an anchor of % was not found (the function text changed); nothing was changed: %', p_sig, left(p_from[i], 80); end if;
    d := replace(d, p_from[i], p_to[i]);
  end loop;
  execute d;
end $$;

select public._p551_patch('public._r3q_t3_payroll(date,date,integer[],jsonb)', '/* p551 */',
  array['and btrim(coalesce(r ->> ''name'', '''')) <> ''''),'],
  array[E'and btrim(coalesce(r ->> ''name'', '''')) <> ''''
      and not (public._p551_app_salary() and date_trunc(''month'', e.entry_date)::date in (select r2.month from public.payroll_runs r2 where r2.status = ''paid'' and r2.month between date_trunc(''month'', d1)::date and d2))   /* p551 */
    union all
    select md5(''p551run'' || r3.id::text || l.id::text)::uuid, coalesce(l.location_id, r3.location_id), btrim(coalesce(l.name, l.employee_no, ''-'')),
           l.net + l.advance_recovery + greatest(l.deductions - l.advance_recovery, 0), l.advance_recovery, greatest(l.deductions - l.advance_recovery, 0)
    from public.payroll_runs r3 join public.payroll_lines l on l.run_id = r3.id and l.active
    where public._p551_app_salary() and r3.status = ''paid'' and r3.month between date_trunc(''month'', d1)::date and d2 and coalesce(l.location_id, r3.location_id) = any (locs)),']);

drop function public._p551_patch(text, text, text[], text[]);

-- ---------------------------------------------------------------- phase552.sql
-- Phase 552 (READINESS D5 + D9) - count-first by default, and the drawer's expected cash can come from the POS.
-- Paste AFTER phase551. Paste-twice safe. Earlier phase files are not edited.
--
-- D5. OWNER DECISION ALREADY RECORDED (docs/DECISIONS.md, 11 Oct 2026): "Count-first: handovers (cash, goods) require the counted figure before the system figure is shown.
--   Mandatory by default; owner can configure per form." BUILD-RULES 9 says the same. The switch blind_count_on (phase 18) was created with the default false, so a fresh
--   project showed the expected figure to the maker (readiness scenario D1). THIS PHASE sets the DEFAULT of blind_count_on to true, following the recorded decision.
--   Only the default changes: a value the owner has already set stays (rules.value is not touched); per form and place the owner can still switch it off (blind_count_cfg).
--   Effect when the default applies: forms 06-1 and 03-1 (cash) and 13-1 and 36-1 (goods) hide the expected figure and the difference from the person who counts.
--   To go back to the old behaviour: set blind_count_on = OFF in the Switchboard.
--
-- D9. New rule drawer_expected_source (choice typed | pos_compare | pos), default typed = nothing changes.
--   typed:       the drawer's expected cash is computed from the figures typed on the sheet (as before).
--   pos_compare: as typed, and when the sheet is submitted, an exception drawer_typed_vs_pos (yellow) is raised if the typed expectation differs from the POS expectation.
--   pos:         the expected cash is taken from the POS: open float + POS cash received (sales and collections, cash) - cash refunds + new advances - prior advances - midday hand-in + rounding.
--                If the place has no POS activity that day, the typed figure is used.
--   The POS part is the same figure as the POS day-close report (expected_cash_after_refunds).
-- Test: supabase/phase552_test.sql and the readiness scenario (D1, D2, D9).

update public.rules set default_value = 'true'::jsonb where key = 'blind_count_on' and default_value is distinct from 'true'::jsonb;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('drawer_expected_source', 'entries', 'choice', '"typed"'::jsonb, null, '["typed","pos_compare","pos"]'::jsonb, null, null,
  'ড্রয়ারের প্রত্যাশিত ক্যাশ কোথা থেকে', 'Drawer-এর expected cash কোথা থেকে', 'Where the drawer''s expected cash comes from',
  'typed = শিটে লেখা অঙ্ক থেকে (আগের মতো)। pos_compare = তাই, কিন্তু শিটের অঙ্ক POS-এর সঙ্গে না মিললে ব্যতিক্রম। pos = POS থেকে নেওয়া অঙ্ক।',
  'typed = sheet-এ লেখা অঙ্ক (আগের মতো)। pos_compare = তাই, কিন্তু POS-এর সঙ্গে না মিললে exception। pos = POS থেকে।',
  'typed = from the figures typed on the sheet (as before). pos_compare = the same, and an exception when it differs from the POS. pos = taken from the POS day close.', 923)
on conflict (key) do nothing;

-- POS cash of one place and day: cash received (sales and collections) minus cash refunds; null when the place had no POS activity that day
create or replace function public._p552_pos_cash(p_loc integer, p_day date) returns numeric language sql stable security definer set search_path = public as $$
  select case when not exists (select 1 from public.rpt_pay p where p.location_id = p_loc and p.day = p_day and not p.voided)
               and not exists (select 1 from public.rpt_ret_p r where r.location_id = p_loc and r.day = p_day) then null
    else coalesce((select sum(p.amount) from public.rpt_pay p where p.location_id = p_loc and p.day = p_day and not p.voided and p.mode = 'cash' and p.kind in ('sale', 'collection')), 0)
       - coalesce((select sum(r.amount) from public.rpt_ret_p r where r.location_id = p_loc and r.day = p_day and r.mode = 'cash'), 0) end $$;

-- the drawer expectation built from the POS cash and the sheet's own non-POS figures; null when the POS has nothing for that day
create or replace function public._p552_pos_expected(p_e public.entries, p_inp jsonb) returns numeric language plpgsql stable security definer set search_path = public as $$
declare pc numeric; openf numeric;
begin
  pc := public._p552_pos_cash(p_e.location_id, p_e.entry_date);
  if pc is null then return null; end if;
  openf := case when p_inp ->> 'open_counted' is not null then (p_inp ->> 'open_counted')::numeric when p_inp ->> 'float' is not null then (p_inp ->> 'float')::numeric else 0 end;
  return openf + pc + coalesce((p_inp ->> 'new_adv')::numeric, 0) - coalesce((p_inp ->> 'prior_adv')::numeric, 0) - coalesce((p_inp ->> 'midday')::numeric, 0) + coalesce((p_inp ->> 'rounding')::numeric, 0);
end $$;

create or replace function public._p552_expected(p_e public.entries, p_section text, p_inp jsonb, p_typed numeric) returns numeric language plpgsql stable security definer set search_path = public as $$
declare px numeric;
begin
  if p_section <> 'drawer' or coalesce(public.rule_txt('drawer_expected_source'), 'typed') <> 'pos' then return p_typed; end if;
  px := public._p552_pos_expected(p_e, p_inp);
  return coalesce(px, p_typed);
end $$;

-- at submit: pos_compare raises the exception when the typed expectation (what the count was compared with) differs from the POS expectation
create or replace function public._p552_flags(p_e public.entries, p_counted_expected numeric, p_flags jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare px numeric; d numeric;
begin
  if coalesce(public.rule_txt('drawer_expected_source'), 'typed') <> 'pos_compare' then return p_flags; end if;
  if exists (select 1 from jsonb_array_elements(p_flags) f where f ->> 'code' = 'drawer_typed_vs_pos') then return p_flags; end if;
  px := public._p552_pos_expected(p_e, public._count_inputs18(p_e, 'drawer'));
  if px is null then return p_flags; end if;
  d := p_counted_expected - px;
  if abs(d) <= 0.005 then return p_flags; end if;
  return p_flags || jsonb_build_array(jsonb_build_object('code', 'drawer_typed_vs_pos', 'level', 'yellow', 'amount', d, 'src', 'system',
    'text', jsonb_build_object('bn', 'শিটের অঙ্ক POS-এর সঙ্গে মেলেনি', 'en', 'Sheet figures differ from the POS')));
end $$;

revoke all on function public._p552_pos_cash(integer, date), public._p552_pos_expected(public.entries, jsonb), public._p552_expected(public.entries, text, jsonb, numeric),
  public._p552_flags(public.entries, numeric, jsonb) from public, anon, authenticated;

create or replace function public._p552_patch(p_sig text, p_marker text, p_from text[], p_to text[]) returns void language plpgsql as $$
declare d text; i int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into d;
  if d is null then raise exception 'phase552: % not found', p_sig; end if;
  if position(p_marker in d) > 0 then return; end if;
  for i in 1 .. array_length(p_from, 1) loop
    if position(p_from[i] in d) = 0 then raise exception 'phase552: an anchor of % was not found (the function text changed); nothing was changed: %', p_sig, left(p_from[i], 80); end if;
    d := replace(d, p_from[i], p_to[i]);
  end loop;
  execute d;
end $$;

select public._p552_patch('public.count_save(uuid,text,jsonb)', '_p552_expected',
  array['ex := public._count_expected18(inp, p_section);'],
  array['ex := public._p552_expected(e, p_section, inp, public._count_expected18(inp, p_section));   /* p552 */']);
select public._p552_patch('public.count_peek(uuid,text)', '_p552_expected',
  array['''expected'', public._count_expected18(inp, p_section));'],
  array['''expected'', public._p552_expected(e, p_section, inp, public._count_expected18(inp, p_section)));   /* p552 */']);
select public._p552_patch('public._entries_blind_guard()', '_p552_flags',
  array['if not (new.data ? ''cash_count'') or public._den_total18(new.data -> ''cash_count'', false) <> r.counted then raise exception ''count_locked''; end if;'],
  array['if not (new.data ? ''cash_count'') or public._den_total18(new.data -> ''cash_count'', false) <> r.counted then raise exception ''count_locked''; end if;
        new.flags := public._p552_flags(new, r.expected, new.flags);   /* p552 */']);

drop function public._p552_patch(text, text, text[], text[]);

-- ---------------------------------------------------------------- phase553.sql
-- Phase 553 (READINESS D2 + D3 + D6) - the setup advisor gets recommended values for the switches the readiness audit found missing.
-- Paste AFTER phase552. Paste-twice safe (the rows that already have a value are not touched). Earlier phase files are not edited.
-- What this is: ADVISOR DATA ONLY. The advisor (setup_recommend_apply) still needs the owner's tap; no rule, no default and no function changes; a switch the owner has already set is never overwritten
--   (reason owner_chosen). Each row carries the readiness checks that stop it while the data is not ready (reason not_ready), and an honest reason text.
-- Rows that existed without a value (the audit's D2/D3/D6): acct_transit_loss -> true, acct_transfer_mode -> location_tagged, stock_negative_mode -> block, production_requires_recipe -> true.
--   Note acct_transfer_mode: location_tagged vs company_wide is the owner's open question since 14 Oct 2026; the advisor row proposes location_tagged (the choice that makes the books equal the stock per place); the owner may choose company_wide instead.
-- New rows: blind_count_on -> true (the recorded default, for a project where it was switched off), report_salary_source -> app_first, rpt131_on -> true, payroll_accrual_on -> true, pin_signature_on -> true.
-- Test: supabase/phase553_test.sql and the readiness scenario in rec mode (books equal stock; count blind; salary reports from the app).

update public.setup_rec_defs81 set rec_value = 'true'::jsonb, ready_checks = array['acc_start','acc_coa','acc_map'], phase = '553',
  reason_bn = 'হিসাব চালু ও জায়গাভিত্তিক স্থানান্তর হিসাব চালু থাকলে পথে হারানো মালের খরচ "পথে ক্ষতি" অ্যাকাউন্টে যায়; না হলে খাতার ইনভেন্টরি স্টকের চেয়ে বেশি থাকে। ঝুঁকি: চালু করলে পুরনো জমা আসল তারিখে পোস্ট হয়।',
  reason_mix = 'Accounting ও transfer accounting চালু থাকলে পথে হারানো মালের cost "transit loss" account-এ যায়; না হলে খাতার inventory stock-এর চেয়ে বেশি থাকে। Warning: backlog আসল তারিখে post হয়।',
  reason_en = 'With accounting and transfer accounting on, the cost of goods short on arrival goes to the transit loss account; without it the books carry inventory above the stock. Warning: turning it on posts the backlog at the original dates.'
 where rule_key = 'acct_transit_loss' and rec_value is null;
update public.setup_rec_defs81 set rec_value = '"location_tagged"'::jsonb, ready_checks = array['acc_start','acc_coa','acc_map'], phase = '553',
  reason_bn = 'একাধিক জায়গা (দোকান, গুদাম, কারখানা) থাকলে location_tagged দিলে পাঠানো ও গ্রহণের দুটি এন্ট্রি হয় এবং প্রতি জায়গায় খাতা ও স্টক মেলে। একটাই জায়গা হলে off থাকুক। company_wide বেছে নেওয়া মালিকের সিদ্ধান্ত (১৪ অক্টোবর থেকে খোলা)।',
  reason_mix = 'একাধিক জায়গা থাকলে location_tagged: send ও receive দুটি entry, প্রতি জায়গায় books ও stock মেলে। এক জায়গা হলে off। company_wide মালিকের সিদ্ধান্ত (14 Oct থেকে open)।',
  reason_en = 'With more than one place, location_tagged posts a send and a receive entry so the books equal the stock place by place. With one place keep off. Choosing company_wide instead is the owner''s decision (open since 14 Oct 2026). Warning: the backlog posts at the original dates.'
 where rule_key = 'acct_transfer_mode' and rec_value is null;
update public.setup_rec_defs81 set rec_value = '"block"'::jsonb, ready_checks = array['stk_neg','stk_opening'], phase = '553',
  reason_bn = 'শুরুর স্টক বা প্রথম গণনার পর block দিলে স্টকের চেয়ে বেশি বিক্রি আটকায়। ঋণাত্মক স্টক থাকলে বা শুরুর স্টক না দিলে আগে ঠিক করুন, নইলে সত্যিকারের বিক্রিও আটকে যেতে পারে।',
  reason_mix = 'Opening stock বা প্রথম count-এর পর block: stock-এর বেশি sale আটকায়। Negative stock বা opening stock না থাকলে আগে ঠিক করুন।',
  reason_en = 'After the opening stock or the first count, block stops a sale above stock. Fix negative balances and enter the opening stock first, or genuine sales may be stopped.'
 where rule_key = 'stock_negative_mode' and rec_value is null;
update public.setup_rec_defs81 set rec_value = 'true'::jsonb, ready_checks = array['prd_recipes'], phase = '553',
  reason_bn = 'চালু থাকলে অনুমোদিত রেসিপি ছাড়া উৎপাদন পোস্ট হয় না, তাই খরচ ও স্টক নিয়ম মেনে চলে। আগে রেসিপি বানিয়ে অনুমোদন করুন।',
  reason_mix = 'চালু থাকলে approved recipe ছাড়া production post হয় না। আগে recipe বানিয়ে approve করুন।',
  reason_en = 'When on, production cannot be posted without an approved recipe, so cost and stock follow the recipe. Make and approve the recipes first.'
 where rule_key = 'production_requires_recipe' and rec_value is null;

insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort, active) values
 ('blind_count_on', 'blind_count_on', '553', 'entries', 'true'::jsonb, '{}',
  'আগে গণনা, তারপর প্রত্যাশিত অঙ্ক: মালিকের ১১ অক্টোবরের সিদ্ধান্ত। এটি এখন ডিফল্টে চালু; কেউ বন্ধ করে থাকলে এই সারি আবার চালু করে।',
  'আগে count, তারপর expected: মালিকের 11 Oct সিদ্ধান্ত। এখন default চালু; কেউ বন্ধ করলে এই row আবার চালু করে।',
  'Count first, then the expected figure: the owner''s decision of 11 Oct 2026. It is now ON by default; this row switches it on again if it was turned off.', 1301, true),
 ('report_salary_source', 'report_salary_source', '553', 'books', '"app_first"'::jsonb, '{}',
  'অ্যাপের বেতন রান থেকে বেতনের রিপোর্ট ও লাভ-ক্ষতি হিসাব হয়; কাগজের শিট শুধু রান না থাকা মাসে। না হলে রিপোর্ট ০ দেখাতে পারে।',
  'App-এর payroll run থেকে বেতনের report ও P&L; কাগজের sheet শুধু run না থাকা মাসে।',
  'Salary reports and the profit-and-loss take the app''s payroll runs; paper sheets are used only for months without a run. Otherwise the staff-cost report can show zero after payroll was paid in the app.', 1302, true),
 ('rpt131_on', 'rpt131_on', '553', 'general', 'true'::jsonb, '{}',
  'যাচাই-করা রিপোর্ট পরিবার (rpt131) চালু করে; বন্ধ থাকলে সেগুলো "feature_off" বলে।',
  'Verified report family (rpt131) চালু; বন্ধ থাকলে "feature_off" বলে।',
  'Turns on the verified report family (rpt131); while off these reports answer feature_off.', 1303, true),
 ('payroll_accrual_on', 'payroll_accrual_on', '553', 'books', null, '{}',
  'বেতন মাসের খরচ হিসেবে মাস শেষে ধরা হয় (পরিশোধের দিনে নয়), দেনা আলাদা থাকে। এটি হিসাবরক্ষক ও মালিকের সিদ্ধান্ত, তাই কোনো মান সুপারিশ করা হয় না।',
  'Salary মাসের expense হিসেবে মাস শেষে ধরা হয় (payment-এর দিনে নয়)। এটি accountant ও মালিকের সিদ্ধান্ত, তাই কোনো মান recommend করা হয় না।',
  'Salary is booked as the month''s expense at month end (not on the payment day) with the liability kept apart. This is the accountant''s and the owner''s decision, so the advisor shows the row but recommends no value.', 1304, true),
 ('pin_signature_on', 'pin_signature_on', '553', 'entries', 'true'::jsonb, array['sec_pin'],
  'দ্বিতীয় সাইনের সময় আলাদা লগইনের PIN লাগে, তাই একজন দুই সই করতে পারে না (BUILD-RULES 10)। আগে মালিক নিশ্চিত করুন যে সবার PIN সেট আছে (সুইচ pin_all_set_confirmed); তার আগে এই সারি "প্রস্তুত নয়" থাকে।',
  'দ্বিতীয় sign-এ আলাদা login-এর PIN লাগে (BUILD-RULES 10)। আগে মালিক নিশ্চিত করুন যে সবার PIN সেট আছে (সুইচ pin_all_set_confirmed); তার আগে এই সারি "প্রস্তুত নয়" থাকে।',
  'The second signature needs the other login''s PIN, so one person cannot sign twice (BUILD-RULES 10). First the owner confirms that everyone has a PIN (switch pin_all_set_confirmed); until then this row stays not ready.', 1305, true)
on conflict (code) do nothing;

-- the readiness check behind the pin row: the server cannot see whether every login has a PIN, so the OWNER confirms it with a switch (default OFF = the row is not ready)
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('pin_all_set_confirmed', 'entries', 'switch', 'false'::jsonb, null, null, null, null,
  'মালিক নিশ্চিত করছেন: সবার PIN সেট আছে', 'Owner confirm করছেন: সবার PIN set আছে', 'Owner confirms: every login has a PIN',
  'বন্ধ = setup advisor pin_signature_on চালু করবে না। চালু = advisor চালু করতে পারবে। এই সুইচ নিজে কোনো আচরণ বদলায় না।',
  'বন্ধ = advisor pin_signature_on চালু করবে না। চালু = পারবে। এই switch নিজে কোনো behaviour বদলায় না।',
  'OFF = the setup advisor will not switch pin_signature_on on. ON = it may. This switch changes no behaviour by itself.', 924)
on conflict (key) do nothing;
insert into public.setup_check_defs81 (code, topic, kind, gate_rule, level, label_bn, label_mix, label_en, fix_bn, fix_mix, fix_en, nav, sort, active)
 select 'sec_pin', 'security', 'ready', null, 'warn', 'সবার PIN সেট আছে কিনা মালিক নিশ্চিত করেননি', 'সবার PIN set আছে কিনা owner confirm করেননি', 'The owner has not confirmed that every login has a PIN',
        'সবাইকে PIN দিয়ে সুইচ pin_all_set_confirmed চালু করুন', 'সবাইকে PIN দিয়ে pin_all_set_confirmed চালু করুন', 'Give everyone a PIN, then switch pin_all_set_confirmed on', 'switchboard', 1301, true
 where not exists (select 1 from public.setup_check_defs81 where code = 'sec_pin');

create or replace function public._p553_patch(p_sig text, p_marker text, p_from text[], p_to text[]) returns void language plpgsql as $$
declare d text; i int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into d;
  if d is null then raise exception 'phase553: % not found', p_sig; end if;
  if position(p_marker in d) > 0 then return; end if;
  for i in 1 .. array_length(p_from, 1) loop
    if position(p_from[i] in d) = 0 then raise exception 'phase553: an anchor of % was not found (the function text changed); nothing was changed: %', p_sig, left(p_from[i], 80); end if;
    d := replace(d, p_from[i], p_to[i]);
  end loop;
  execute d;
end $$;
select public._p553_patch('public._setup_chk81(text)', '/* p553 */',
  array['  when ''acc_start'' then'],
  array['  when ''sec_pin'' then   /* p553 */
    n := case when coalesce(public.rule_on(''pin_all_set_confirmed''), false) then 0 else 1 end; tot := 1;
  when ''acc_start'' then']);
drop function public._p553_patch(text, text, text[], text[]);

-- ============================================================================
-- End of FRESH part 21 of 21.
-- Now run this check (it only reads):
-- select * from public._i2_state() where not present;   -- must return no rows
