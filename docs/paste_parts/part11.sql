-- ============================================================================
-- FRESH part 11 of 21. Paste the WHOLE of this file into the Supabase SQL editor, press Run, wait for "Success", then paste the next part.
-- Phases in this part, in this order: phase117 phase118 phase526 phase121 phase122 phase123 phase124 phase125 phase126 phase127 phase128 phase129 phase527
-- Never paste: any *_test.sql, the phase84 / 84b / 84c TEST-PROJECT files, ALL_NEW2..ALL_NEW11*. Commit: see docs/PASTE_ORDER.md.
-- ============================================================================

-- ---------------------------------------------------------------- phase117.sql
-- ============================================================
-- Phase 117 (bos117) - BATCH 3, part 2: factory overhead reaches the books (audit: docs/audit2/A1_manufacturing_cost.md G2 G3; docs/audit2/A3_real_profit.md gap 5 / G10).
-- Run AFTER phase116 (canonical order, docs/PASTE_ORDER.md section N). Needs phases 72..111 and 116. Additive; paste twice = no change.
-- Both switches below are OFF by default = today's behaviour (a pool is a memo; factory salary also shows on the factory branch):
--   pool_gl_post117            every pool row (typed with pool_set, or coming from a cost bill with dest factory) is also posted as an expense:
--                              Dr the expense account of its cost type, Cr 2400 Other accrued expenses (pool_accrued), dated the last day of the month (today at the latest), source pool_gl117.
--                              This is the matching Dr for the Cr 5950 "overhead absorbed" of production: the unabsorbed part (actual - absorbed) is then simply an expense of the month in the P&L.
--                              A retired pool row (typed again, bill voided) is reversed. Year pools post 1/12 per month. Depreciation is NOT posted (the fixed-asset module does that).
--                              !! Turn it on ONLY if the same factory costs are NOT also entered as expenses / payroll / bills (that would count them twice).
--   factory_labour_absorbed117 the branch P&L (_p27_pl) leaves out of the factory's sheet salary the labour that was already absorbed into product cost, so it is not counted twice (A3 gap 5).
-- Read-only: pool_vs_gl117 (pool vs absorbed vs expense in the books), overhead_trueup117 (the old true-up + what reached the P&L).
-- Functions re-created (tag bos117): pool_set, _cs_push_pools, _p27_pl. Re-paste rule: if phase74/75/79 or phase72 is pasted again, paste phase117 again after it.
-- NOT done (on purpose): booking OVER-absorbed overhead back out of stock needs an actual-output re-rate at month close (risky for stock values); see docs/audit2/B3_REPORT.md.
-- ============================================================

do $g$
declare miss text := ''; m record; d text; t text; bad text := '';
begin
  for m in select * from (values ('116', 'public.production_reprice116(integer,date,boolean)'), ('74', 'public._pool_rate(integer,date,text)'), ('75', 'public._cs_alloc(bigint)'), ('72', 'public._cogs_lines72(date,date,integer[])')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regclass('public.recipe_std116') is null then miss := miss || ' 116'; end if;
  if miss <> '' then raise exception 'phase117 needs phases 72..111 and 116 pasted first (see docs/PASTE_ORDER.md); missing:%', miss; end if;
  for m in select * from (values ('public.pool_set(integer,date,text,numeric,text,boolean,text,uuid)', 'bos75 bos117'), ('public._cs_push_pools(bigint)', 'bos117'), ('public._p27_pl(date,date,integer[])', 'bos50 bos72 bos117')) v(fn, ok)
  loop
    d := pg_get_functiondef(to_regprocedure(m.fn));
    for t in select distinct x[1] from regexp_matches(d, '(bos[0-9]+)', 'g') x loop
      if position(t in m.ok) = 0 then bad := bad || ' ' || m.fn || '->' || t; end if;
    end loop;
  end loop;
  if bad <> '' then raise exception 'phase117 refuses: a function it re-creates carries a tag it does not know (merge that change into phase117 first):%', bad; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('pool_gl_post117', 'stock', 'switch', 'false', null, null, null,
  'কারখানার খরচের পুল হিসাবেও (GL) খরচ হিসেবে উঠবে', 'Factory cost pool GL-এও expense হিসেবে উঠবে', 'Factory cost pools are also posted as an expense in the books',
  'Off (default) = আজকের মতো, পুল শুধু স্মারক (memo); উৎপাদনে "ওভারহেড শোষিত" (5950) জমা হলেও তার বিপরীতে খরচ নাও থাকতে পারে। On = পুলের প্রতিটি সারি খরচ (Dr) / বাকি খরচ 2400 (Cr) হিসেবে ওঠে। সাবধান: একই খরচ আলাদা expense / বেতন / বিল হিসেবে লিখলে দুবার গোনা হবে।',
  'Off (default) = a pool is a memo; production credits "overhead absorbed" (5950) with no matching expense necessarily in the books. On = each pool row is posted Dr expense / Cr 2400 accrued. Careful: if the same cost is also entered as an expense, payroll or bill it is counted twice.', 760),
 ('factory_labour_absorbed117', 'stock', 'switch', 'false', null, null, null,
  'কারখানার বেতন থেকে পণ্যের খরচে ধরা শ্রম বাদ (দুবার গোনা বন্ধ)', 'Factory salary থেকে product cost-এ ধরা labour বাদ (double count বন্ধ)', 'Factory salary leaves out the labour already absorbed into product cost',
  'Off (default) = আজকের মতো: শ্রম পণ্যের খরচে (বিক্রির COGS) আর কারখানার শাখার বেতনে দুবার আসে। On = শাখার P&L-এ কারখানার বেতন থেকে ওই মাসে পণ্যের খরচে ধরা শ্রমের পরিমাণ বাদ যায় (বেতনের বেশি নয়)।',
  'Off (default) = as today: labour appears in product cost (COGS where sold) and again as the factory branch salary. On = the branch P&L takes from the factory salary the labour absorbed into product cost that month (never more than the salary).', 761)
on conflict (key) do nothing;

alter table public.cost_component_types add column if not exists gl_key117 text;
alter table public.cost_component_types add column if not exists gl_post117 boolean not null default true;
update public.cost_component_types set gl_key117 = case code when 'labour' then 'pool_exp_labour' when 'gas' then 'pool_exp_utilities' when 'electricity' then 'pool_exp_utilities'
    when 'factory_rent' then 'pool_exp_rent' when 'machine_repair' then 'pool_exp_repair' when 'licence_fee' then 'pool_exp_other' when 'other' then 'pool_exp_other' end
  where builtin and gl_key117 is null and code <> 'depreciation';
update public.cost_component_types set gl_post117 = false where code = 'depreciation' and gl_key117 is null;
update public.cost_component_types set gl_key117 = 'pool_exp_other' where not builtin and gl_key117 is null;

insert into public.acct_mappings (key, account_id, label_bn, label_en)
select v.k, a.id, v.bn, v.en from (values
  ('pool_exp_labour', '5200', 'কারখানার শ্রম খরচ (পুল)', 'Factory labour cost (pool)'),
  ('pool_exp_utilities', '5400', 'কারখানার গ্যাস / বিদ্যুৎ (পুল)', 'Factory gas / electricity (pool)'),
  ('pool_exp_rent', '5300', 'কারখানার ভাড়া (পুল)', 'Factory rent (pool)'),
  ('pool_exp_repair', '5600', 'কারখানার যন্ত্র মেরামত (পুল)', 'Factory machine repair (pool)'),
  ('pool_exp_other', '5900', 'কারখানার অন্যান্য খরচ (পুল)', 'Other factory cost (pool)'),
  ('pool_accrued', '2400', 'কারখানার খরচের দেনা (পুল)', 'Factory cost payable (pool)')) v(k, code, bn, en)
join public.coa_accounts a on a.code = v.code
on conflict (key) do nothing;

create table if not exists public.pool_gl_posts117 (
  id bigserial primary key,
  pool_id bigint not null references public.factory_cost_pools(id),
  month date not null check (month = date_trunc('month', month::timestamp)::date),
  amount numeric not null check (amount > 0),
  version int not null default 1,
  entry_id bigint not null references public.journal_entries(id),
  reversal_id bigint references public.journal_entries(id),
  created_by uuid, created_at timestamptz not null default now(),
  unique (pool_id, month, version)
);
drop trigger if exists pgp117_no_delete on public.pool_gl_posts117;
create trigger pgp117_no_delete before delete on public.pool_gl_posts117 for each row execute function public.no_hard_delete();
drop trigger if exists audit_pgp117 on public.pool_gl_posts117;
create trigger audit_pgp117 after insert or update on public.pool_gl_posts117 for each row execute function public.log_change('id');
alter table public.pool_gl_posts117 enable row level security;
drop policy if exists pgp117_read on public.pool_gl_posts117;      -- no browser SELECT (cost secrecy): read through pool_vs_gl117 only
revoke all on public.pool_gl_posts117 from anon, authenticated;
revoke all on sequence public.pool_gl_posts117_id_seq from anon, authenticated;
CREATE OR REPLACE FUNCTION public.pool_set(p_loc integer, p_month date, p_type text, p_amount numeric, p_period_kind text DEFAULT 'month'::text, p_one_off boolean DEFAULT false, p_note text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  if public.rule_on('pool_gl_post117') then      -- bos117: the typed pool also becomes the expense in the books (the matching Dr for the Cr 5950 absorbed)
    begin perform public._pool_gl_sync117(p_loc, m);
    exception when others then
      perform public._stock_exc(p_loc, 'pool_gl_failed', 'yellow', 'কারখানার খরচ হিসাবে (GL) ওঠেনি: ' || left(sqlerrm, 120), 'The factory cost could not be posted to the books: ' || left(sqlerrm, 120), null, m, 'STOCK');
    end;
  end if;
  return jsonb_build_object('id', nid, 'allocated_exists', alloc);
end $function$;

CREATE OR REPLACE FUNCTION public._cs_push_pools(p_bill bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b public.cost_source_bills; ct text; sh record;
begin
  select * into b from public.cost_source_bills where id = p_bill;
  update public.factory_cost_pools set active = false where source = 'allocated' and ref like 'bill:' || p_bill::text || ':%' and active;
  if b.status <> 'active' then perform public._pool_gl_after_bill117(p_bill); return; end if;      -- bos117
  select t.component_type into ct from public.cost_sources s join public.cost_source_types t on t.code = s.cost_type where s.id = b.source_id;
  for sh in select location_id, sum(amount) amt from public.cost_bill_shares where bill_id = p_bill and active and kind = 'share' and dest = 'factory' group by location_id loop
    if sh.amt > 0 then
      insert into public.factory_cost_pools (location_id, month, component_type, period_kind, actual_amount, one_off, source, ref, note, created_by)
        values (sh.location_id, b.period_month, coalesce(ct, 'other'), b.period_kind, sh.amt, b.one_off, 'allocated', 'bill:' || p_bill::text || ':' || sh.location_id::text, 'from cost bill ' || p_bill::text, auth.uid());
    end if;
  end loop;
  perform public._pool_gl_after_bill117(p_bill);      -- bos117: pool rows of this bill (new and retired) are mirrored in the books (switch pool_gl_post117)
end $function$;

CREATE OR REPLACE FUNCTION public._p27_pl(d1 date, d2 date, locs integer[])
 RETURNS TABLE(o_m date, o_loc integer, o_gross numeric, o_ret numeric, o_net numeric, o_costed numeric, o_cogs numeric, o_exp numeric, o_sal numeric, o_fixed numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  sa0 as (
    select date_trunc('month', e.entry_date)::date as m, e.location_id,
           sum(coalesce(public._r2_num(r -> 'due'), 0) + coalesce(public._r2_num(r -> 'overtime'), 0) + coalesce(public._r2_num(r -> 'other'), 0)) as amt
    from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'pay') = 'array' then e.data -> 'pay' else '[]'::jsonb end) r
    where e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs) group by 1, 2),
  sa as (  -- bos117: labour already absorbed into product cost (conversion detail 'labour' of the runs) is not charged a second time to the factory branch (switch factory_labour_absorbed117)
    select s0.m, s0.location_id, case when public.rule_on('factory_labour_absorbed117') then greatest(s0.amt - coalesce((select sum((dd ->> 'amount')::numeric) from public.production_runs pr, jsonb_array_elements(coalesce(pr.conversion_detail, '[]'::jsonb)) dd
        where pr.status = 'done' and pr.location_id = s0.location_id and date_trunc('month', (pr.made_at at time zone 'Asia/Dhaka')::date)::date = s0.m and (pr.made_at at time zone 'Asia/Dhaka')::date between d1 and d2
          and dd ->> 'type' = 'labour' and (dd ->> 'amount') is not null), 0), 0) else s0.amt end as amt
    from sa0 s0),
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

-- ---------- the mirror of the pool in the books ----------
-- internal: post / reverse the pool rows of ONE place and month. Needs the switch, accounting on and a start date; nothing is posted into a closed period (reported as skipped).
create or replace function public._pool_gl_sync117(p_loc int, p_month date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m date := public._m1(p_month); st date := public._acct_start(); today_ date := public._acct_today(); edate date; r record; ent bigint; rev bigint; ver int; amt numeric; nposted int := 0; nrev int := 0; tot numeric := 0; skipped jsonb := '[]'::jsonb;
begin
  if not public.rule_on('pool_gl_post117') or not public.rule_on('accounting_on') or st is null then return jsonb_build_object('off', true); end if;
  edate := least((m + interval '1 month')::date - 1, today_);
  -- 1. a posting whose pool row was retired (typed again, bill voided) is reversed
  for r in select p.* from public.pool_gl_posts117 p join public.factory_cost_pools f on f.id = p.pool_id
            where f.location_id = p_loc and p.month = m and p.reversal_id is null and not f.active order by p.id loop
    if public._acct_locked(today_) then skipped := skipped || jsonb_build_object('pool_id', r.pool_id, 'why', 'period_closed'); continue; end if;
    rev := public._acct_reverse(r.entry_id, today_, 'Reversal: factory cost row retired');
    update public.pool_gl_posts117 set reversal_id = rev where id = r.id;
    nrev := nrev + 1;
  end loop;
  -- 2. an active pool row that covers this month and has no live posting yet
  for r in select f.*, t.gl_key117 k, t.gl_post117 gp from public.factory_cost_pools f join public.cost_component_types t on t.code = f.component_type
            where f.active and f.location_id = p_loc
              and ((f.period_kind = 'month' and f.month = m) or (f.period_kind = 'year' and m >= f.month and m < (f.month + interval '12 months')::date))
              and not exists (select 1 from public.pool_gl_posts117 p where p.pool_id = f.id and p.month = m and p.reversal_id is null) order by f.id loop
    if not r.gp or r.k is null then skipped := skipped || jsonb_build_object('pool_id', r.id, 'why', 'type_not_posted'); continue; end if;
    amt := round(case when r.period_kind = 'month' then r.actual_amount else r.actual_amount / 12 end, 2);
    if amt < 0.005 then continue; end if;
    if edate < st then skipped := skipped || jsonb_build_object('pool_id', r.id, 'why', 'before_start'); continue; end if;
    if public._acct_locked(edate) then skipped := skipped || jsonb_build_object('pool_id', r.id, 'why', 'period_closed'); continue; end if;
    select coalesce(max(version), 0) + 1 into ver from public.pool_gl_posts117 p where p.pool_id = r.id and p.month = m;
    ent := public._acct_write(edate, p_loc, 'pool_gl117', r.id::text || ':' || to_char(m, 'YYYY-MM') || ':' || ver::text, null,
      'Factory cost ' || r.component_type || ' ' || to_char(m, 'YYYY-MM'), null,
      public._acct_resolve(jsonb_build_array(jsonb_build_object('a', r.k, 'd', amt), jsonb_build_object('a', 'pool_accrued', 'c', amt)), p_loc));
    insert into public.pool_gl_posts117 (pool_id, month, amount, version, entry_id, created_by) values (r.id, m, amt, ver, ent, auth.uid());
    nposted := nposted + 1; tot := tot + amt;
  end loop;
  return jsonb_build_object('location_id', p_loc, 'month', m, 'posted', nposted, 'reversed', nrev, 'total', round(tot, 2), 'skipped', skipped);
end $$;

-- catch-up / manual run for the people who manage the accounts (also for months where a yearly row now applies)
create or replace function public.pool_gl_sync117(p_loc int, p_month date) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not (public._acct_manage() and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  if p_month is null then raise exception 'bad_date'; end if;
  if not public.rule_on('pool_gl_post117') then raise exception 'switch_off: pool_gl_post117'; end if;
  perform pg_advisory_xact_lock(hashtextextended('acct_post', 0));
  return public._pool_gl_sync117(p_loc, p_month);
end $$;

create or replace function public._pool_gl_after_bill117(p_bill bigint) returns void
language plpgsql security definer set search_path = public as $$
declare b public.cost_source_bills; sh record;
begin
  if not public.rule_on('pool_gl_post117') then return; end if;
  select * into b from public.cost_source_bills where id = p_bill;
  if not found then return; end if;
  for sh in select distinct f.location_id from public.factory_cost_pools f where f.source = 'allocated' and f.ref like 'bill:' || p_bill::text || ':%' loop
    begin perform public._pool_gl_sync117(sh.location_id, b.period_month);
    exception when others then
      perform public._stock_exc(sh.location_id, 'pool_gl_failed', 'yellow', 'কারখানার খরচ হিসাবে (GL) ওঠেনি: ' || left(sqlerrm, 120), 'The factory cost could not be posted to the books: ' || left(sqlerrm, 120), null, b.period_month, 'STOCK');
    end;
  end loop;
end $$;

-- cost type -> expense mapping key / posted or not (owner). Keys come from the chart mappings (acct_mapping_set can point a key to another account).
create or replace function public.cost_type_gl_set117(p_code text, p_key text, p_post boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_key is not null and not exists (select 1 from public.acct_mappings where key = p_key) then raise exception 'mapping_missing:%', p_key; end if;
  update public.cost_component_types set gl_key117 = p_key, gl_post117 = coalesce(p_post, true) where code = p_code;
  if not found then raise exception 'unknown_type'; end if;
end $$;

-- A1 G2: is the pool honest against the books? One place, one month.
--   pool_total      = the month's pool (yearly rows / 12)
--   posted_total    = what pool_gl117 entries put into expense for the month (switch pool_gl_post117)
--   absorbed_gl     = what production / re-price entries credited to 5950 at this place in the month
--   expense_gl      = expense accounts (without cost of goods, wastage and 5950) debited at this place in the month, pool postings included
--   absorbed_exceeds_expense = true when more was absorbed into products than any expense in the books explains (profit overstated by that much)
create or replace function public.pool_vs_gl117(p_loc int, p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m date := public._m1(p_month); me date; ptot numeric := 0; posted numeric; absorbed numeric; exp_all numeric; exp_pool numeric; rows_ jsonb := '[]'::jsonb; t record; pm numeric; pp numeric;
begin
  if not (public._acct_view() and public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  if p_month is null then raise exception 'bad_date'; end if;
  me := (m + interval '1 month')::date - 1;
  for t in select c.code, c.label_en, c.gl_key117, c.gl_post117 from public.cost_component_types c where c.active order by c.code loop
    pm := public._pool_month_actual(p_loc, m, t.code);
    select coalesce(sum(p.amount), 0) into pp from public.pool_gl_posts117 p join public.factory_cost_pools f on f.id = p.pool_id where f.location_id = p_loc and p.month = m and p.reversal_id is null and f.component_type = t.code;
    if pm is null and pp = 0 then continue; end if;
    ptot := ptot + coalesce(pm, 0);
    rows_ := rows_ || jsonb_build_object('type', t.code, 'label_en', t.label_en, 'pool', round(pm, 2), 'posted', round(pp, 2), 'mapping_key', t.gl_key117, 'posted_to_gl_type', t.gl_post117);
  end loop;
  select coalesce(sum(p.amount), 0) into posted from public.pool_gl_posts117 p join public.factory_cost_pools f on f.id = p.pool_id where f.location_id = p_loc and p.month = m and p.reversal_id is null;
  select coalesce(sum(l.credit - l.debit), 0) into absorbed from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.coa_accounts a on a.id = l.account_id
    where a.code = '5950' and e.entry_date between m and me and coalesce(l.location_id, e.location_id) = p_loc;
  select coalesce(sum(l.debit - l.credit), 0), coalesce(sum(l.debit - l.credit) filter (where e.source_type = 'pool_gl117'), 0) into exp_all, exp_pool
    from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.coa_accounts a on a.id = l.account_id
    where a.type = 'expense' and a.code not like '50%' and a.code not like '51%' and a.code <> '5950' and e.entry_date between m and me and coalesce(l.location_id, e.location_id) = p_loc;
  return jsonb_build_object('location_id', p_loc, 'month', m, 'rows', rows_, 'pool_total', round(ptot, 2), 'posted_total', round(posted, 2), 'absorbed_gl', round(absorbed, 2),
    'expense_gl', round(exp_all, 2), 'expense_gl_from_pool', round(exp_pool, 2), 'expense_gl_other', round(exp_all - exp_pool, 2),
    'absorbed_exceeds_expense', absorbed > exp_all + 0.005,
    'unabsorbed_in_pnl', round(exp_all - absorbed, 2),
    'note', 'absorbed_exceeds_expense = true: products were charged overhead for which no expense is in the books (turn pool_gl_post117 on, or enter the cost as an expense). Expense of other kinds at this place is included in expense_gl.');
end $$;

-- the old true-up (report only) plus what really reached the books
create or replace function public.overhead_trueup117(p_loc int, p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare tu jsonb; g jsonb; over_ jsonb;
begin
  tu := public.overhead_trueup(p_loc, p_month);
  g := public.pool_vs_gl117(p_loc, p_month);
  over_ := coalesce((select jsonb_agg(jsonb_build_object('type', x->>'type', 'over_absorbed', round(-(x->>'unabsorbed')::numeric, 2)))
                       from jsonb_array_elements(tu->'rows') x where (x->>'unabsorbed') is not null and (x->>'unabsorbed')::numeric < 0), '[]'::jsonb);
  return tu || jsonb_build_object('gl', g, 'over_absorbed_types', over_,
    'note_gl', 'unabsorbed overhead is an expense of the month only when the pool is in the books (pool_gl_post117) or the cost was entered as an expense. Over-absorbed types stay in stock value until a re-price.');
end $$;

revoke all on function public._pool_gl_sync117(int, date), public._pool_gl_after_bill117(bigint) from public, anon, authenticated;
revoke all on function public.pool_gl_sync117(int, date), public.cost_type_gl_set117(text, text, boolean), public.pool_vs_gl117(int, date), public.overhead_trueup117(int, date) from public, anon;
grant execute on function public.pool_gl_sync117(int, date), public.cost_type_gl_set117(text, text, boolean), public.pool_vs_gl117(int, date), public.overhead_trueup117(int, date) to authenticated;

insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort)
select v.code, v.code, v.phase, v.module, v.rec_value, v.ready_checks, v.reason_bn, v.reason_mix, v.reason_en, v.sort from (values
 ('pool_gl_post117', '117', 'accounts', null::jsonb, '{}'::text[],
  'পুল মোডে উৎপাদন হলে খাতায় "ওভারহেড শোষিত" জমা হয়, কিন্তু পুল নিজে খাতায় খরচ হিসেবে ওঠে না। কারখানার বিদ্যুৎ / গ্যাস / ভাড়া / শ্রম যদি আলাদা expense বা বেতন হিসেবে না লিখে থাকেন, তবে এটি চালু করুন; লিখে থাকলে বন্ধ রাখুন, নইলে দুবার গোনা হবে।',
  'Pool mode-এ production হলে খাতায় overhead absorbed জমা হয়, কিন্তু pool নিজে খাতায় expense হিসেবে ওঠে না। Factory-র বিদ্যুৎ / গ্যাস / ভাড়া / শ্রম যদি আলাদা expense বা বেতন হিসেবে না লিখে থাকেন, তবে এটি চালু করুন; লিখে থাকলে off রাখুন, নইলে double গোনা হবে।',
  'In pool mode production credits overhead absorbed, but the pool itself is not an expense in the books. Switch on if you do NOT also enter the factory electricity, gas, rent and labour as expenses or payroll; keep off if you do, or they are counted twice. It depends on how you enter those costs, so no value is recommended.', 367),
 ('factory_labour_absorbed117', '117', 'accounts', null::jsonb, '{}'::text[],
  'কারখানার শ্রম পণ্যের খরচে ধরা হলে একই টাকা কারখানার শাখার বেতন হিসেবেও দেখায়। চালু করলে শাখার লাভ-ক্ষতিতে পণ্যের খরচে ধরা অংশ বেতন থেকে বাদ যায়। আপনি রেসিপি / পুলে শ্রম ধরলে তবেই চালু করুন।',
  'Factory labour product cost-এ ধরা হলে একই টাকা factory branch-এর salary হিসেবেও দেখায়। চালু করলে branch P&L-এ product cost-এ ধরা অংশ salary থেকে বাদ যায়। আপনি recipe / pool-এ labour ধরলে তবেই চালু করুন।',
  'When factory labour is charged into product cost the same money also shows as the factory branch salary. Switch on to take the absorbed part out of that salary in the branch P&L. Use it only if you charge labour in recipes or pools.', 368)
) v(code, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort)
on conflict (code) do nothing;

-- ---------------------------------------------------------------- phase118.sql
-- ============================================================
-- Phase 118 (bos118) - STEP B4: three READ-ONLY reconciliation reports (audit2 A2 G1/G2, A3 G13/C19/C20, A5 GAP-1).
--   1. stock_recon_statement   per item / location / period:  opening + production + purchases + transfers in + customer give-backs
--                              - used in production - sales - wastage - transit loss - transfers out +/- adjustments = closing, with a variance flag
--                              (ledger total against the cached stock_balance) and the sales lines that did not leave stock (stock_sales_unmatched).
--   2. factory_branch_statement per location / item / period: sent, received, short, in transit (with ageing), returned to the sender, sold, wasted,
--                              remaining, value at the transferred cost. Built from stock_transfers + stock_ledger + stock_balance (prototype a5_01b).
--   3. net_profit_report       per branch and per product: net sales, cost of goods, gross profit (costed part), wastage, card fees, variable expenses
--                              = CONTRIBUTION MARGIN; then other expenses, salary sheet, monthly fixed cost, attributed shared bills = NET PROFIT AFTER OVERHEAD.
--                              Every figure is labelled with what it includes; revenue with unknown cost is shown separately and never counted at 100 % margin.
--   Needs phases 72..103 (guard below). Additive and paste-twice safe (create or replace / if not exists / on conflict do nothing / where not exists).
--   Nothing existing is re-created or changed: no table, trigger, rule value, privilege or function of an older phase is touched. The reports only READ
--   (stable functions); the one write is the audit row of recon_export_log118 (a CSV export, same audit_log shape as log_report_export2).
--   Whole file = one transaction: if the guard refuses, nothing is created.
--   Objects:
--     grants   view_stock_recon (module stock)  - stock statement and the unmatched-sales list (quantities only)
--              view_branch_statement (module stock) - factory-to-branch statement
--              view_net_profit (module cost)    - net profit report; ALSO needs biz_cost_ok() (owner, ITEM_COST view, view_cost or view_profit): profit is cost-derived
--              Cost secrecy: in the two stock statements every cost / value key is left out unless biz_cost_ok(). Location rights: a row is shown only for a location the
--              caller can_loc() AND holds the grant for (has_grant(code, location)); the owner sees all.
--     rules    profit_variable_heads (text, default "transport")  expense heads treated as VARIABLE selling cost (inside the contribution margin);
--              branch_stmt_ageing_hours (text, default "24,72")   in-transit ageing boundaries in hours (A5: 0-24 h / 1-3 days / over 3 days)
--     RPC      stock_recon_statement(from, to, loc, item, category, limit)
--              stock_sales_unmatched(from, to, loc, item, limit)
--              factory_branch_statement(from, to, loc, item, category, limit)
--              net_profit_report(from, to, loc, category)
--              recon_export_log118(key, rows, filters)     audit row of a CSV export (owner, or grant + export_data)
--   Internal (closed to the browser): _rc118_locs, _rc118_buckets, _rc118_gap, _rc118_gap_summary.
--   Tag: bos118. No existing function is re-created.
-- ============================================================
begin;

do $g$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('72', 'public._p27_pl(date,date,integer[])'), ('78', 'public._c78_rows(date,date)'),
    ('78', 'public._c78_main_loc(date)'), ('80', 'public._cost_free80(uuid)'), ('88', 'public._rcs88()'), ('88', 'public.biz_cost_ok()'),
    ('82', 'public._base_qty(uuid,numeric,text)'), ('85', 'public._acct_from85()')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regclass('public.card_settlements85') is null then miss := miss || ' 85'; end if;
  if to_regclass('public.setup_rec_defs81') is null then miss := miss || ' 81'; end if;
  if to_regclass('public.audit_log') is null or to_regclass('public.grant_defs') is null or to_regclass('public.rules') is null
     or to_regclass('public.stock_ledger') is null or to_regclass('public.stock_transfers') is null then miss := miss || ' base'; end if;
  if miss <> '' then
    raise exception 'phase118 needs phases 72..103 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
end $g$;

-- ---------- grants ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
select 'view_stock_recon', 'stock', 96, 'স্টকের হিসাব মেলানো (শুরু + আসা − গেছে = শেষ) দেখা', 'Stock-এর হিসাব মেলানো (শুরু + আসা − গেছে = শেষ) দেখা', 'See the stock reconciliation statement (opening + in - out = closing)', 'once'
where not exists (select 1 from public.grant_defs where grant_code = 'view_stock_recon');
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
select 'view_branch_statement', 'stock', 97, 'কারখানা থেকে শাখার হিসাব (পাঠানো, পৌঁছানো, বিক্রি, বাকি) দেখা', 'Factory থেকে branch-এর হিসাব (পাঠানো, পৌঁছানো, বিক্রি, বাকি) দেখা', 'See the factory-to-branch statement (sent, received, sold, remaining)', 'once'
where not exists (select 1 from public.grant_defs where grant_code = 'view_branch_statement');
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
select 'view_net_profit', 'cost', 22, 'পণ্য ও শাখা অনুযায়ী নিট লাভ (কন্ট্রিবিউশন ও ওভারহেড সহ) দেখা', 'Product ও branch অনুযায়ী net profit (contribution ও overhead সহ) দেখা', 'See net profit per product and branch (contribution margin and after overhead)', 'once'
where not exists (select 1 from public.grant_defs where grant_code = 'view_net_profit');

-- ---------- rules ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('profit_variable_heads', 'reports', 'text', '"transport"'::jsonb, null, null, null, null,
  'নিট লাভ রিপোর্টে যে খরচের হেড বিক্রির সাথে বদলায় (ভ্যারিয়েবল)', 'Net profit report-এ যে খরচের head বিক্রির সাথে বদলায় (variable)', 'Expense heads that count as variable cost in the net profit report',
  'কমা দিয়ে হেডের কোড লিখুন (যেমন transport)। এই হেডের খরচ কন্ট্রিবিউশন মার্জিনের ভেতরে ধরা হয়; বাকি সব খরচ ওভারহেড। ফাঁকা = কোনো হেড ভ্যারিয়েবল নয়।',
  'Comma দিয়ে head-এর code লিখুন (যেমন transport)। এই head-এর খরচ contribution margin-এর ভেতরে ধরা হয়; বাকি সব খরচ overhead। ফাঁকা = কোনো head variable নয়।',
  'Comma-separated expense head codes (for example transport). Spending on these heads is counted inside the contribution margin; every other expense is overhead. Blank = no head is variable.', 995),
 ('branch_stmt_ageing_hours', 'stock', 'text', '"24,72"'::jsonb, 'hours', null, null, null,
  'পথে থাকা মালের বয়স ভাগ (ঘণ্টা, কমা দিয়ে)', 'পথে থাকা মালের age ভাগ (ঘণ্টা, comma দিয়ে)', 'In-transit ageing boundaries (hours, comma-separated)',
  'দুটি সংখ্যা, যেমন 24,72 = ২৪ ঘণ্টার কম / ১-৩ দিন / ৩ দিনের বেশি। ফাঁকা বা ভুল হলে 24,72 ধরা হয়।',
  'দুটি সংখ্যা, যেমন 24,72 = ২৪ ঘণ্টার কম / ১-৩ দিন / ৩ দিনের বেশি। ফাঁকা বা ভুল হলে 24,72 ধরা হয়।',
  'Two numbers, for example 24,72 = under 24 hours / 1-3 days / over 3 days. Blank or invalid falls back to 24,72.', 996)
on conflict (key) do nothing;

-- advisor rows: owner-typed classification and boundaries, so no value is recommended
insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort) values
 ('profit_variable_heads', 'profit_variable_heads', '118', 'reports', null, '{}'::text[],
  'কোন খরচ বিক্রির সাথে বদলায় তা আপনার ব্যবসার সিদ্ধান্ত, তাই কোনো মান ঠিক করা নেই। ডিফল্ট transport।',
  'কোন খরচ বিক্রির সাথে বদলায় তা আপনার business-এর decision, তাই কোনো মান ঠিক করা নেই। Default transport।',
  'Which costs move with sales is your business decision, so no value is recommended. The default is transport.', 995),
 ('branch_stmt_ageing_hours', 'branch_stmt_ageing_hours', '118', 'stock', null, '{}'::text[],
  'পথে থাকা মাল কত ঘণ্টায় "পুরনো" হয় তা আপনার সিদ্ধান্ত। ডিফল্ট 24,72 (অডিট A5 অনুযায়ী)।',
  'পথে থাকা মাল কত ঘণ্টায় "পুরনো" হয় তা আপনার decision। Default 24,72 (audit A5 অনুযায়ী)।',
  'How many hours make goods in transit "old" is your decision. The default is 24,72 (audit A5).', 996)
on conflict (code) do nothing;

-- ---------- internal helpers (no privilege for anyone but the definer) ----------
create or replace function public._rc118_locs(p_grant text, p_loc integer) returns integer[]
language plpgsql stable security definer set search_path = public as $$
-- bos118: the locations the caller may see for this grant (location right AND grant for that location); p_loc narrows to one; empty = refused
declare r integer[];
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select coalesce(array_agg(l.id order by l.id), '{}') into r from public.locations l
   where public.can_loc(l.id) and public.has_grant(p_grant, l.id) and (p_loc is null or l.id = p_loc);
  if coalesce(array_length(r, 1), 0) = 0 then raise exception 'not allowed'; end if;
  return r;
end $$;

create or replace function public._rc118_buckets(p_from date, p_to date, p_locs integer[], p_item uuid, p_cat text)
returns table (location_id integer, item_id uuid, opening numeric, production numeric, used numeric, purchases numeric, transfer_in numeric,
               transfer_ret numeric, transfer_oth numeric, sales numeric, cust_back numeric, wastage numeric, transit_loss numeric,
               adjustments numeric, closing numeric, ledger_total numeric, moves bigint)
language sql stable security definer set search_path = public as $$
-- bos118: the one set of ledger buckets both statements use. A reversal row is counted in the bucket of the row it reverses (so a cancelled transfer nets to 0 in
-- "transfers out"); out-going buckets are positive numbers. A transfer out is a RETURN when the receiver had earlier sent the same item to the sender.
-- Identity per row:  closing = opening + production + purchases + transfer_in + cust_back - used - sales - wastage - transit_loss - transfer_ret - transfer_oth + adjustments
  with l as (
    select sl.location_id, sl.item_id, sl.qty_delta, (sl.made_at at time zone 'Asia/Dhaka')::date as d, coalesce(o.reason, sl.reason) as eff,
           (coalesce(o.reason, sl.reason) = 'transfer_out' and sl.ref_type = 'transfer' and exists (
              select 1 from public.stock_transfers t join public.stock_transfers t2
                on t2.from_location_id = t.to_location_id and t2.to_location_id = t.from_location_id and t2.item_id = t.item_id and t2.sent_at < t.sent_at and t2.status <> 'cancelled'
              where t.id = (case when sl.ref_id ~ '^[0-9a-f-]{36}$' then sl.ref_id::uuid end))) as is_ret
      from public.stock_ledger sl
      left join public.stock_ledger o on o.id = sl.reverses_id
      join public.items i on i.id = sl.item_id
     where sl.location_id = any (p_locs) and (p_item is null or sl.item_id = p_item) and (p_cat is null or i.category = p_cat))
  select l.location_id, l.item_id,
    coalesce(sum(l.qty_delta) filter (where l.d < p_from), 0),
    coalesce(sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff = 'production_in'), 0),
    coalesce(-sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff = 'issue_out'), 0),
    coalesce(sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff in ('purchase_in', 'purchase_return')), 0),
    coalesce(sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff = 'transfer_in'), 0),
    coalesce(-sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff = 'transfer_out' and l.is_ret), 0),
    coalesce(-sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff = 'transfer_out' and not l.is_ret), 0),
    coalesce(-sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff = 'sale_out'), 0),
    coalesce(sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff in ('sale_void_in', 'sale_return')), 0),
    coalesce(-sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff = 'wastage'), 0),
    coalesce(-sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff = 'transit_loss'), 0),
    coalesce(sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff not in ('production_in', 'issue_out', 'purchase_in', 'purchase_return', 'transfer_in', 'transfer_out',
                                                                                         'sale_out', 'sale_void_in', 'sale_return', 'wastage', 'transit_loss')), 0),
    coalesce(sum(l.qty_delta) filter (where l.d <= p_to), 0),
    coalesce(sum(l.qty_delta), 0),
    count(*) filter (where l.d between p_from and p_to)
  from l group by l.location_id, l.item_id;
$$;

create or replace function public._rc118_gap(p_from date, p_to date, p_locs integer[], p_item uuid)
returns table (sale_id uuid, receipt integer, sale_date date, location_id integer, item_id uuid, sold_qty numeric, base_qty numeric, ledger_qty numeric, diff_qty numeric, kind text)
language sql stable security definer set search_path = public as $$
-- bos118: done sales (voids excluded) per sale and item: quantity in the item's BASE unit against the sale_out rows the sale posted. Lines without an item (quick sales) are skipped.
  with ln as (
    select s.id as sid, s.receipt as rc, s.sale_date as sd, s.location_id as lid,
           (case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end) as iid,
           (case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end) as q, nullif(btrim(e->>'unit'), '') as u
      from public.sales s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
     where s.status = 'done' and s.sale_date between p_from and p_to and s.location_id = any (p_locs)),
  g as (
    select ln.sid, ln.rc, ln.sd, ln.lid, ln.iid, sum(ln.q) as q, sum(public._base_qty(ln.iid, ln.q, ln.u)) as bq, bool_or(public._base_qty(ln.iid, ln.q, ln.u) is null) as unk
      from ln where ln.iid is not null and ln.q is not null and (p_item is null or ln.iid = p_item) group by 1, 2, 3, 4, 5),
  led as (
    select sl.ref_id as rid, sl.item_id as iid, sum(-sl.qty_delta) as lq from public.stock_ledger sl
     where sl.ref_type = 'sale' and sl.reason = 'sale_out' and sl.ref_id in (select sid::text from g) group by 1, 2)
  select g.sid, g.rc, g.sd, g.lid, g.iid, g.q, g.bq, coalesce(led.lq, 0), coalesce(g.bq, 0) - coalesce(led.lq, 0),
         (case when not i.tracked then 'untracked' when g.unk then 'unit_unknown' when coalesce(led.lq, 0) = 0 then 'not_posted'
               when g.bq - led.lq > 0.0005 then 'short_posted' else 'over_posted' end)
    from g join public.items i on i.id = g.iid left join led on led.rid = g.sid::text and led.iid = g.iid
   where (not i.tracked) or g.unk or abs(coalesce(g.bq, 0) - coalesce(led.lq, 0)) > 0.0005;
$$;

create or replace function public._rc118_gap_summary(p_from date, p_to date, p_locs integer[], p_item uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(q.k, q.n), '{}'::jsonb) from (select g.kind as k, count(*) as n from public._rc118_gap(p_from, p_to, p_locs, p_item) g group by g.kind) q;
$$;

-- ---------- 1. stock reconciliation statement ----------
create or replace function public.stock_recon_statement(p_from date, p_to date, p_loc integer default null, p_item uuid default null, p_category text default null, p_limit integer default 2000)
returns jsonb language plpgsql stable security definer set search_path = public as $$
-- bos118: opening + production + purchases + transfers in + give-backs - used - sales - wastage - transit loss - transfers out +/- adjustments = closing, per item and location.
-- variance_qty = ledger total (all rows) - cached stock_balance.qty; flag 'variance' when it is not 0. Cost keys only when biz_cost_ok().
declare locs integer[]; cost_ok boolean; lim integer := least(greatest(coalesce(p_limit, 2000), 1), 5000); rows_j jsonb; n_all integer; sm jsonb; gap jsonb;
begin
  if p_from is null or p_to is null or p_to < p_from then raise exception 'bad_period'; end if;
  if p_to - p_from > 370 then raise exception 'period_too_long'; end if;
  locs := public._rc118_locs('view_stock_recon', p_loc);
  cost_ok := public.biz_cost_ok();
  with b as (select * from public._rc118_buckets(p_from, p_to, locs, p_item, p_category)),
  x as (
    select b.*, i.code, i.name_bn, i.name_en, i.unit, i.tracked, lo.name_bn as loc_bn, lo.name_en as loc_en, coalesce(sb.qty, 0) as bal_qty, sb.avg_cost,
           (b.opening + b.production + b.purchases + b.transfer_in + b.cust_back - b.used - b.sales - b.wastage - b.transit_loss - b.transfer_ret - b.transfer_oth + b.adjustments) as calc_closing
      from b join public.items i on i.id = b.item_id join public.locations lo on lo.id = b.location_id
      left join public.stock_balance sb on sb.item_id = b.item_id and sb.location_id = b.location_id
     where b.moves > 0 or b.opening <> 0 or b.closing <> 0 or coalesce(sb.qty, 0) <> 0),
  y as (select x.*, (x.ledger_total - x.bal_qty) as variance, abs(x.closing - x.calc_closing) > 0.0005 as unbalanced from x)
  select count(*),
         coalesce(jsonb_agg(r.j order by r.lid, r.code) filter (where r.rn <= lim), '[]'::jsonb),
         jsonb_build_object('items', count(*), 'with_variance', count(*) filter (where r.var_flag), 'unbalanced', count(*) filter (where r.unb), 'adjusted', count(*) filter (where r.adj))
    into n_all, rows_j, sm
  from (
    select row_number() over (order by y.location_id, y.code) as rn, y.location_id as lid, y.code, (abs(y.variance) > 0.0005) as var_flag, y.unbalanced as unb, (abs(y.adjustments) > 0.0005) as adj,
      jsonb_strip_nulls(jsonb_build_object(
        'location_id', y.location_id, 'location_bn', y.loc_bn, 'location_en', coalesce(y.loc_en, y.loc_bn),
        'item_id', y.item_id, 'item_code', y.code, 'item_bn', y.name_bn, 'item_en', coalesce(y.name_en, y.name_bn), 'unit', y.unit, 'tracked', y.tracked,
        'opening_qty', round(y.opening, 4), 'production_qty', round(y.production, 4), 'purchases_qty', round(y.purchases, 4), 'transfer_in_qty', round(y.transfer_in, 4),
        'give_back_qty', round(y.cust_back, 4), 'used_qty', round(y.used, 4), 'sales_qty', round(y.sales, 4), 'wastage_qty', round(y.wastage, 4), 'transit_loss_qty', round(y.transit_loss, 4),
        'transfer_out_qty', round(y.transfer_ret + y.transfer_oth, 4), 'returned_to_sender_qty', round(y.transfer_ret, 4), 'adjustments_qty', round(y.adjustments, 4),
        'closing_qty', round(y.closing, 4), 'balance_qty', round(y.bal_qty, 4), 'variance_qty', round(y.variance, 4),
        'flags', (select coalesce(jsonb_agg(f), '[]'::jsonb) from unnest(array[case when abs(y.variance) > 0.0005 then 'variance' end, case when y.unbalanced then 'unbalanced' end,
                                                                               case when abs(y.adjustments) > 0.0005 then 'adjusted' end, case when y.closing < 0 then 'negative' end]) f where f is not null),
        'avg_cost', case when cost_ok then round(y.avg_cost, 4) end,
        'closing_value', case when cost_ok and y.avg_cost is not null then round(y.closing * y.avg_cost, 2) end)) as j
      from y) r;
  gap := public._rc118_gap_summary(p_from, p_to, locs, p_item);
  return jsonb_build_object('from', p_from, 'to', p_to, 'location_ids', to_jsonb(locs), 'cost_visible', cost_ok, 'rows', rows_j, 'row_count', n_all, 'truncated', n_all > lim,
    'summary', sm, 'sales_unmatched', gap,
    'formula', 'opening + production + purchases + transfers_in + give_backs - used - sales - wastage - transit_loss - transfers_out + adjustments = closing');
end $$;

create or replace function public.stock_sales_unmatched(p_from date, p_to date, p_loc integer default null, p_item uuid default null, p_limit integer default 500)
returns jsonb language plpgsql stable security definer set search_path = public as $$
-- bos118 (A2 G2): sales lines whose quantity did not leave stock as sold. kind: untracked (item not stock-tracked, expected), unit_unknown (no unit conversion, stock not reduced),
-- not_posted (tracked, nothing posted), short_posted / over_posted (quantity differs). Quantities only, no cost.
declare locs integer[]; lim integer := least(greatest(coalesce(p_limit, 500), 1), 2000); rows_j jsonb; cnt jsonb; tot integer;
begin
  if p_from is null or p_to is null or p_to < p_from then raise exception 'bad_period'; end if;
  if p_to - p_from > 370 then raise exception 'period_too_long'; end if;
  locs := public._rc118_locs('view_stock_recon', p_loc);
  select coalesce(jsonb_agg(q.j order by q.sale_date desc, q.receipt desc), '[]'::jsonb) into rows_j from (
    select g.sale_date, g.receipt, jsonb_build_object('sale_id', g.sale_id, 'receipt', g.receipt, 'sale_date', g.sale_date, 'location_id', g.location_id,
             'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn), 'item_id', g.item_id, 'item_code', i.code, 'item_bn', i.name_bn, 'item_en', coalesce(i.name_en, i.name_bn),
             'unit', i.unit, 'base_unit', coalesce(i.base_unit, i.unit), 'sold_qty', round(g.sold_qty, 4), 'sold_base_qty', round(g.base_qty, 4), 'ledger_qty', round(g.ledger_qty, 4),
             'diff_qty', round(g.diff_qty, 4), 'kind', g.kind) as j
      from public._rc118_gap(p_from, p_to, locs, p_item) g join public.items i on i.id = g.item_id join public.locations lo on lo.id = g.location_id
     order by g.sale_date desc, g.receipt desc limit lim) q;
  cnt := public._rc118_gap_summary(p_from, p_to, locs, p_item);
  select coalesce(sum(value::int), 0) into tot from jsonb_each_text(cnt);
  return jsonb_build_object('from', p_from, 'to', p_to, 'location_ids', to_jsonb(locs), 'rows', rows_j, 'counts', cnt, 'total', tot, 'truncated', tot > lim);
end $$;

-- ---------- 2. factory-to-branch statement ----------
create or replace function public.factory_branch_statement(p_from date, p_to date, p_loc integer default null, p_item uuid default null, p_category text default null, p_limit integer default 2000)
returns jsonb language plpgsql stable security definer set search_path = public as $$
-- bos118 (A5 GAP-1): per location and item. Supply side from stock_transfers (sent / received / short in the period, in transit at the end of the period with ageing),
-- stock side from the ledger buckets (opening, received, returned to the sender, sold, wasted, remaining). receive_mismatch = ledger transfer_in - received - resolved transit loss.
-- Value = quantity x the cost the sender's ledger row carried (cost keys only when biz_cost_ok()).
declare locs integer[]; cost_ok boolean; lim integer := least(greatest(coalesce(p_limit, 2000), 1), 5000); e_end timestamptz; asof timestamptz; rr text; b1 numeric := 24; b2 numeric := 72;
        rows_j jsonb; n_all integer; byloc jsonb;
begin
  if p_from is null or p_to is null or p_to < p_from then raise exception 'bad_period'; end if;
  if p_to - p_from > 370 then raise exception 'period_too_long'; end if;
  locs := public._rc118_locs('view_branch_statement', p_loc);
  cost_ok := public.biz_cost_ok();
  e_end := ((p_to + 1)::timestamp at time zone 'Asia/Dhaka');
  asof := least(e_end, now());
  rr := btrim(coalesce(public.rule_val('branch_stmt_ageing_hours') #>> '{}', ''));
  if rr ~ '^[0-9]+(\.[0-9]+)?\s*,\s*[0-9]+(\.[0-9]+)?$' and btrim(split_part(rr, ',', 1))::numeric < btrim(split_part(rr, ',', 2))::numeric then
    b1 := btrim(split_part(rr, ',', 1))::numeric; b2 := btrim(split_part(rr, ',', 2))::numeric;
  end if;
  with b as (select * from public._rc118_buckets(p_from, p_to, locs, p_item, p_category)),
  tr0 as (
    select t.*, (t.sent_at at time zone 'Asia/Dhaka')::date as sd, (t.received_at at time zone 'Asia/Dhaka')::date as rd,
           extract(epoch from (asof - t.sent_at)) / 3600.0 as age_h
      from public.stock_transfers t join public.items i on i.id = t.item_id
     where t.status <> 'cancelled' and t.sent_at < e_end and (t.to_location_id = any (locs) or t.from_location_id = any (locs))
       and (p_item is null or t.item_id = p_item) and (p_category is null or i.category = p_category)),
  uc as (
    select sl.ref_id as tid, sum(-sl.qty_delta * coalesce(sl.unit_cost, 0)) / nullif(sum(-sl.qty_delta), 0) as cost
      from public.stock_ledger sl where sl.ref_type = 'transfer' and sl.reason = 'transfer_out' and sl.reverses_id is null and sl.ref_id in (select id::text from tr0) group by 1),
  tr as (select tr0.*, uc.cost as ucost, (tr0.sent_at < e_end and (tr0.status = 'sent' or tr0.received_at >= e_end)) as in_tr from tr0 left join uc on uc.tid = tr0.id::text),
  toa as (
    select tr.to_location_id as lid, tr.item_id,
           coalesce(sum(tr.qty) filter (where tr.sd between p_from and p_to), 0) as sent_to,
           coalesce(sum(tr.received_qty) filter (where tr.status = 'received' and tr.rd between p_from and p_to), 0) as received_to,
           coalesce(sum(tr.qty - tr.received_qty) filter (where tr.status = 'received' and tr.rd between p_from and p_to and tr.received_qty < tr.qty), 0) as short_to,
           coalesce(sum(tr.qty) filter (where tr.in_tr), 0) as tr_qty,
           coalesce(sum(tr.qty) filter (where tr.in_tr and tr.age_h < b1), 0) as tr_q0,
           coalesce(sum(tr.qty) filter (where tr.in_tr and tr.age_h >= b1 and tr.age_h < b2), 0) as tr_q1,
           coalesce(sum(tr.qty) filter (where tr.in_tr and tr.age_h >= b2), 0) as tr_q2,
           max(tr.age_h) filter (where tr.in_tr) as oldest_h,
           sum(tr.qty * tr.ucost) filter (where tr.sd between p_from and p_to) as sent_val,
           sum(tr.received_qty * tr.ucost) filter (where tr.status = 'received' and tr.rd between p_from and p_to) as recv_val,
           sum((tr.qty - tr.received_qty) * tr.ucost) filter (where tr.status = 'received' and tr.rd between p_from and p_to and tr.received_qty < tr.qty) as short_val,
           sum(tr.qty * tr.ucost) filter (where tr.in_tr) as tr_val,
           count(*) filter (where tr.sd between p_from and p_to) as n_sent, count(*) filter (where tr.status = 'received' and tr.rd between p_from and p_to and tr.received_qty < tr.qty) as n_short,
           count(*) filter (where tr.in_tr) as n_tr
      from tr where tr.to_location_id = any (locs) group by 1, 2),
  froma as (
    select tr.from_location_id as lid, tr.item_id, coalesce(sum(tr.qty) filter (where tr.sd between p_from and p_to), 0) as sent_from
      from tr where tr.from_location_id = any (locs) group by 1, 2),
  keys as (select location_id as lid, item_id from b union select lid, item_id from toa union select lid, item_id from froma),
  z as (
    select k.lid, k.item_id, i.code, i.name_bn, i.name_en, i.unit, lo.name_bn as loc_bn, lo.name_en as loc_en, lo.kind as loc_kind,
           coalesce(b.opening, 0) as opening, coalesce(b.production, 0) as production, coalesce(b.purchases, 0) as purchases, coalesce(b.transfer_in, 0) as t_in,
           coalesce(b.transfer_ret, 0) as t_ret, coalesce(b.transfer_oth, 0) as t_oth, coalesce(b.sales, 0) as sold, coalesce(b.cust_back, 0) as back, coalesce(b.wastage, 0) as wasted,
           coalesce(b.transit_loss, 0) as t_loss, coalesce(b.used, 0) as used, coalesce(b.adjustments, 0) as adj, coalesce(b.closing, 0) as closing, coalesce(b.ledger_total, 0) as ledger_total,
           coalesce(sb.qty, 0) as bal, sb.avg_cost,
           coalesce(toa.sent_to, 0) as sent_to, coalesce(toa.received_to, 0) as received_to, coalesce(toa.short_to, 0) as short_to, coalesce(toa.tr_qty, 0) as tr_qty,
           coalesce(toa.tr_q0, 0) as tr_q0, coalesce(toa.tr_q1, 0) as tr_q1, coalesce(toa.tr_q2, 0) as tr_q2, toa.oldest_h,
           toa.sent_val, toa.recv_val, toa.short_val, toa.tr_val, coalesce(toa.n_sent, 0) as n_sent, coalesce(toa.n_short, 0) as n_short, coalesce(toa.n_tr, 0) as n_tr,
           coalesce(froma.sent_from, 0) as sent_from, coalesce(b.moves, 0) as moves
      from keys k join public.items i on i.id = k.item_id join public.locations lo on lo.id = k.lid
      left join b on b.location_id = k.lid and b.item_id = k.item_id
      left join toa on toa.lid = k.lid and toa.item_id = k.item_id left join froma on froma.lid = k.lid and froma.item_id = k.item_id
      left join public.stock_balance sb on sb.location_id = k.lid and sb.item_id = k.item_id),
  z1 as (
    select z.* from z
     where z.moves > 0 or z.opening <> 0 or z.closing <> 0 or z.n_sent > 0 or z.n_tr > 0 or z.sent_from > 0 or z.received_to > 0 or z.bal <> 0),
  z2 as (
    select z1.*, (z1.t_in - z1.received_to - z1.t_loss) as mismatch, (z1.ledger_total - z1.bal) as variance,
           (case when z1.sent_to > 0 then round(100 * z1.short_to / z1.sent_to, 2) end) as short_pct from z1)
  select count(*),
         coalesce(jsonb_agg(r.j order by r.lid, r.code) filter (where r.rn <= lim), '[]'::jsonb)
    into n_all, rows_j
  from (
    select row_number() over (order by z2.lid, z2.code) as rn, z2.lid, z2.code,
      jsonb_strip_nulls(jsonb_build_object(
        'location_id', z2.lid, 'location_bn', z2.loc_bn, 'location_en', coalesce(z2.loc_en, z2.loc_bn), 'location_kind', z2.loc_kind,
        'item_id', z2.item_id, 'item_code', z2.code, 'item_bn', z2.name_bn, 'item_en', coalesce(z2.name_en, z2.name_bn), 'unit', z2.unit,
        'opening_qty', round(z2.opening, 4), 'production_qty', round(z2.production, 4), 'purchases_qty', round(z2.purchases, 4),
        'sent_in_qty', round(z2.sent_to, 4), 'received_qty', round(z2.received_to, 4), 'short_qty', round(z2.short_to, 4), 'short_pct', z2.short_pct,
        'ledger_received_qty', round(z2.t_in, 4), 'transit_loss_qty', round(z2.t_loss, 4),
        'in_transit_qty', round(z2.tr_qty, 4), 'in_transit_age_0_qty', round(z2.tr_q0, 4), 'in_transit_age_1_qty', round(z2.tr_q1, 4), 'in_transit_age_2_qty', round(z2.tr_q2, 4),
        'oldest_transit_hours', round(z2.oldest_h::numeric, 1),
        'sent_out_qty', round(z2.sent_from, 4), 'returned_qty', round(z2.t_ret, 4), 'other_transfer_out_qty', round(z2.t_oth, 4),
        'sold_qty', round(z2.sold, 4), 'give_back_qty', round(z2.back, 4), 'wasted_qty', round(z2.wasted, 4), 'used_qty', round(z2.used, 4), 'adjustments_qty', round(z2.adj, 4),
        'remaining_qty', round(z2.closing, 4), 'balance_qty', round(z2.bal, 4), 'variance_qty', round(z2.variance, 4), 'receive_mismatch_qty', round(z2.mismatch, 4),
        'flags', (select coalesce(jsonb_agg(f), '[]'::jsonb) from unnest(array[case when z2.short_to > 0 then 'short' end, case when z2.tr_q2 > 0 then 'transit_old' end,
                                                                               case when abs(z2.mismatch) > 0.0005 then 'receive_mismatch' end, case when abs(z2.variance) > 0.0005 then 'variance' end]) f where f is not null),
        'sent_value', case when cost_ok then round(z2.sent_val, 2) end, 'received_value', case when cost_ok then round(z2.recv_val, 2) end,
        'short_value', case when cost_ok then round(z2.short_val, 2) end, 'in_transit_value', case when cost_ok then round(z2.tr_val, 2) end,
        'avg_cost', case when cost_ok then round(z2.avg_cost, 4) end, 'remaining_value', case when cost_ok and z2.avg_cost is not null then round(z2.closing * z2.avg_cost, 2) end)) as j
      from z2) r;
  -- per location totals: counts always, values only for cost holders (quantities of different units are never added)
  with tr0 as (
    select t.*, (t.sent_at at time zone 'Asia/Dhaka')::date as sd, (t.received_at at time zone 'Asia/Dhaka')::date as rd
      from public.stock_transfers t join public.items i on i.id = t.item_id
     where t.status <> 'cancelled' and t.sent_at < e_end and t.to_location_id = any (locs) and (p_item is null or t.item_id = p_item) and (p_category is null or i.category = p_category)),
  uc as (
    select sl.ref_id as tid, sum(-sl.qty_delta * coalesce(sl.unit_cost, 0)) / nullif(sum(-sl.qty_delta), 0) as cost
      from public.stock_ledger sl where sl.ref_type = 'transfer' and sl.reason = 'transfer_out' and sl.reverses_id is null and sl.ref_id in (select id::text from tr0) group by 1),
  a as (
    select t.to_location_id as lid, count(*) filter (where t.sd between p_from and p_to) as n_sent,
           count(*) filter (where t.status = 'received' and t.rd between p_from and p_to and t.received_qty < t.qty) as n_short,
           count(*) filter (where t.status = 'sent' or t.received_at >= e_end) as n_transit,
           sum(t.qty * uc.cost) filter (where t.sd between p_from and p_to) as sent_val,
           sum(t.received_qty * uc.cost) filter (where t.status = 'received' and t.rd between p_from and p_to) as recv_val,
           sum((t.qty - t.received_qty) * uc.cost) filter (where t.status = 'received' and t.rd between p_from and p_to and t.received_qty < t.qty) as short_val,
           sum(t.qty * uc.cost) filter (where t.status = 'sent' or t.received_at >= e_end) as transit_val
      from tr0 t left join uc on uc.tid = t.id::text group by 1)
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('location_id', lo.id, 'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn),
           'transfers_sent', a.n_sent, 'transfers_short', a.n_short, 'transfers_in_transit', a.n_transit,
           'sent_value', case when cost_ok then round(a.sent_val, 2) end, 'received_value', case when cost_ok then round(a.recv_val, 2) end,
           'short_value', case when cost_ok then round(a.short_val, 2) end, 'in_transit_value', case when cost_ok then round(a.transit_val, 2) end,
           'short_pct_of_value', case when cost_ok and a.sent_val > 0 then round(100 * coalesce(a.short_val, 0) / a.sent_val, 2) end)) order by lo.id), '[]'::jsonb)
    into byloc from a join public.locations lo on lo.id = a.lid;
  return jsonb_build_object('from', p_from, 'to', p_to, 'location_ids', to_jsonb(locs), 'cost_visible', cost_ok, 'ageing_hours', jsonb_build_array(b1, b2),
    'rows', rows_j, 'row_count', n_all, 'truncated', n_all > lim, 'by_location', byloc,
    'formula', 'remaining = opening + received + purchases + production + give_backs - returned - other_transfers_out - sold - wasted - transit_loss - used +/- adjustments');
end $$;

-- ---------- 3. net profit report ----------
create or replace function public.net_profit_report(p_from date, p_to date, p_loc integer default null, p_category text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
-- bos118 (A3 G13 / C19 / C20). Branch = net sales (after discount and returns) - cost of goods = gross profit (COSTED part only) - wastage and transit loss at ledger cost
-- - card fees - variable expenses = CONTRIBUTION MARGIN; - other expenses - salary sheet 02-2 - monthly fixed cost - attributed shared bills (pro-rated by days) = NET PROFIT AFTER OVERHEAD.
-- Revenue with no known cost is shown as uncosted_sales and is NOT in any profit figure. Product view: the same lines per item; fees, variable expenses and overhead of a branch
-- are shared out to its products by the product's share of that branch's net sales (an allocation, labelled as such), so product profits add up to the branch profit.
-- Needs the grant view_net_profit AND biz_cost_ok().
declare locs integer[]; vh text[]; br jsonb; pr jsonb; pb jsonb; unal numeric; total jsonb; rcs text;
begin
  if p_from is null or p_to is null or p_to < p_from then raise exception 'bad_period'; end if;
  if p_to - p_from > 370 then raise exception 'period_too_long'; end if;
  if not public.biz_cost_ok() then raise exception 'not allowed'; end if;
  locs := public._rc118_locs('view_net_profit', p_loc);
  vh := coalesce((select array_agg(btrim(x)) from unnest(string_to_array(coalesce(public.rule_val('profit_variable_heads') #>> '{}', ''), ',')) x where btrim(x) <> ''), '{}');
  rcs := public._rcs88();
  with cl as (
    select h.loc, h.item_id,
           sum((case h.src when 'sale' then 1 else -1 end) * h.qty) as qty, sum((case h.src when 'sale' then 1 else -1 end) * h.rev) as net,
           sum((case h.src when 'sale' then 1 else -1 end) * (h.rev - h.unk_rev)) as costed, sum((case h.src when 'sale' then 1 else -1 end) * (h.led_cogs + h.fb_cogs)) as cogs,
           sum((case h.src when 'sale' then 1 else -1 end) * h.unk_rev) as unk
      from public._cogs_lines72(p_from, p_to, locs) h left join public.items i on i.id = h.item_id
     where p_category is null or i.category = p_category group by 1, 2),
  wc as (
    select sl.location_id as loc, sl.item_id, sum(-sl.qty_delta * coalesce(sl.unit_cost, 0)) as cost, coalesce(sum(-sl.qty_delta) filter (where coalesce(sl.unit_cost, 0) = 0), 0) as unc_qty
      from public.stock_ledger sl join public.items i on i.id = sl.item_id
     where sl.reason in ('wastage', 'transit_loss') and sl.reverses_id is null and not exists (select 1 from public.stock_ledger r where r.reverses_id = sl.id)
       and (sl.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to and sl.location_id = any (locs) and (p_category is null or i.category = p_category) group by 1, 2),
  fee as (select c.location_id as loc, sum(c.fee) as fee from public.card_settlements85 c where c.status = 'done' and c.settle_date between p_from and p_to and c.location_id = any (locs) group by 1),
  vx as (
    select u.loc, sum(u.amt) as amt from (
      select q.location_id as loc, q.amount as amt from public.quick_expenses q where q.status = 'done' and q.exp_date between p_from and p_to and q.location_id = any (locs) and q.head = any (vh)
      union all
      select e.location_id, public._r2_num(ln -> 'amount') from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) ln
       where e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) and e.entry_date between p_from and p_to
         and e.location_id = any (locs) and (ln ->> 'head') = any (vh)) u group by 1),
  pl as (select o_loc as loc, sum(o_exp) as ex, sum(o_sal) as sal, sum(o_fixed) as fx, bool_or(o_sal is not null) as has_sal from public._p27_pl(p_from, p_to, locs) group by 1),
  sh as (
    select r.dloc as loc, sum(r.amount * ((least(p_to, (r.mth + interval '1 month')::date - 1) - greatest(p_from, r.mth) + 1)::numeric / ((r.mth + interval '1 month')::date - r.mth))) as amt
      from public._c78_rows(p_from, p_to) r where r.dkind <> 'unallocated' and r.dloc = any (locs) group by 1),
  keys as (select loc from cl union select loc from wc union select loc from fee union select loc from vx union select loc from pl union select loc from sh),
  b as (
    select k.loc, coalesce(c.net, 0) as net, coalesce(c.costed, 0) as costed, coalesce(c.unk, 0) as unk, coalesce(c.cogs, 0) as cogs, coalesce(c.qty, 0) as qty,
           coalesce(w.cost, 0) as wcost, coalesce(w.unc, 0) as wunc, coalesce(f.fee, 0) as fee, coalesce(v.amt, 0) as vexp,
           greatest(coalesce(p.ex, 0) - coalesce(v.amt, 0), 0) as oexp, coalesce(p.sal, 0) as sal, coalesce(p.fx, 0) as fx, coalesce(s.amt, 0) as shr, coalesce(p.has_sal, false) as has_sal
      from keys k
      left join (select loc, sum(net) net, sum(costed) costed, sum(unk) unk, sum(cogs) cogs, sum(qty) qty from cl group by loc) c on c.loc = k.loc
      left join (select loc, sum(cost) cost, sum(unc_qty) unc from wc group by loc) w on w.loc = k.loc
      left join fee f on f.loc = k.loc left join vx v on v.loc = k.loc left join pl p on p.loc = k.loc left join sh s on s.loc = k.loc),
  b2 as (
    select b.*, (b.costed - b.cogs) as gp, (b.costed - b.cogs - b.wcost - b.fee - b.vexp) as cm, (b.oexp + b.sal + b.fx + b.shr) as oh,
           (b.costed - b.cogs - b.wcost - b.fee - b.vexp - b.oexp - b.sal - b.fx - b.shr) as np from b),
  pb0 as (
    select k.loc, k.item_id, coalesce(c.qty, 0) as qty, coalesce(c.net, 0) as net, coalesce(c.costed, 0) as costed, coalesce(c.unk, 0) as unk, coalesce(c.cogs, 0) as cogs,
           coalesce(w.cost, 0) as wcost, coalesce(w.unc_qty, 0) as wunc
      from (select loc, item_id from cl union select loc, item_id from wc) k
      left join cl c on c.loc = k.loc and c.item_id is not distinct from k.item_id left join wc w on w.loc = k.loc and w.item_id is not distinct from k.item_id),
  pb as (
    select p.*, i.code, i.name_bn, i.name_en, i.category,
           (b2.fee + b2.vexp) * (case when b2.net > 0 then p.net / b2.net else 0 end) as var_alloc,
           b2.oh * (case when b2.net > 0 then p.net / b2.net else 0 end) as oh_alloc
      from pb0 p join b2 on b2.loc = p.loc left join public.items i on i.id = p.item_id),
  pb2 as (
    select pb.*, (pb.costed - pb.cogs - pb.wcost - pb.var_alloc) as cm, (pb.costed - pb.cogs - pb.wcost - pb.var_alloc - pb.oh_alloc) as np from pb)
  select
    (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'location_id', lo.id, 'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn),
        'net_sales', round(b2.net, 2), 'costed_sales', round(b2.costed, 2), 'uncosted_sales', round(b2.unk, 2),
        'uncosted_pct', case when b2.net > 0 then round(100 * b2.unk / b2.net, 2) end,
        'cogs', round(b2.cogs, 2), 'gross_profit', round(b2.gp, 2), 'gross_margin_pct', case when b2.costed > 0 then round(100 * b2.gp / b2.costed, 2) end,
        'wastage_cost', round(b2.wcost, 2), 'wastage_uncosted_qty', round(b2.wunc, 4), 'card_fees', round(b2.fee, 2), 'variable_expenses', round(b2.vexp, 2),
        'contribution_margin', round(b2.cm, 2), 'contribution_pct', case when b2.costed > 0 then round(100 * b2.cm / b2.costed, 2) end,
        'other_expenses', round(b2.oexp, 2), 'salary', round(b2.sal, 2), 'fixed_monthly', round(b2.fx, 2), 'shared_costs', round(b2.shr, 2),
        'overhead_total', round(b2.oh, 2), 'net_profit', round(b2.np, 2), 'net_profit_pct', case when b2.costed > 0 then round(100 * b2.np / b2.costed, 2) end,
        'complete', (b2.unk = 0 and b2.has_sal),
        'gaps', (select coalesce(jsonb_agg(g), '[]'::jsonb) from unnest(array[case when b2.unk <> 0 then 'uncosted_sales' end, case when not b2.has_sal then 'salary_not_recorded' end,
                                                                               case when b2.wunc > 0 then 'wastage_uncosted' end]) g where g is not null))) order by lo.id), '[]'::jsonb)
       from b2 join public.locations lo on lo.id = b2.loc),
    (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'item_id', q.item_id, 'item_code', coalesce(q.code, 'no_item'), 'item_bn', q.name_bn, 'item_en', coalesce(q.name_en, q.name_bn), 'category', q.category,
        'qty', round(q.qty, 4), 'net_sales', round(q.net, 2), 'costed_sales', round(q.costed, 2), 'uncosted_sales', round(q.unk, 2), 'cogs', round(q.cogs, 2),
        'gross_profit', round(q.costed - q.cogs, 2), 'gross_margin_pct', case when q.costed > 0 then round(100 * (q.costed - q.cogs) / q.costed, 2) end,
        'wastage_cost', round(q.wcost, 2), 'allocated_variable', round(q.var_alloc, 2), 'contribution_margin', round(q.cm, 2),
        'contribution_pct', case when q.costed > 0 then round(100 * q.cm / q.costed, 2) end,
        'allocated_overhead', round(q.oh_alloc, 2), 'net_profit', round(q.np, 2), 'net_profit_pct', case when q.costed > 0 then round(100 * q.np / q.costed, 2) end,
        'cost_complete', (q.unk = 0))) order by q.net desc, q.code), '[]'::jsonb)
       from (select p.item_id, p.code, p.name_bn, p.name_en, p.category, sum(p.qty) qty, sum(p.net) net, sum(p.costed) costed, sum(p.unk) unk, sum(p.cogs) cogs, sum(p.wcost) wcost,
                    sum(p.var_alloc) var_alloc, sum(p.oh_alloc) oh_alloc, sum(p.cm) cm, sum(p.np) np
               from pb2 p group by p.item_id, p.code, p.name_bn, p.name_en, p.category) q),
    (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'location_id', p.loc, 'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn), 'item_id', p.item_id, 'item_code', coalesce(p.code, 'no_item'),
        'item_bn', p.name_bn, 'item_en', coalesce(p.name_en, p.name_bn), 'category', p.category, 'qty', round(p.qty, 4), 'net_sales', round(p.net, 2), 'costed_sales', round(p.costed, 2),
        'uncosted_sales', round(p.unk, 2), 'cogs', round(p.cogs, 2), 'gross_profit', round(p.costed - p.cogs, 2), 'wastage_cost', round(p.wcost, 2),
        'allocated_variable', round(p.var_alloc, 2), 'contribution_margin', round(p.cm, 2), 'allocated_overhead', round(p.oh_alloc, 2), 'net_profit', round(p.np, 2),
        'cost_complete', (p.unk = 0))) order by p.loc, p.net desc, p.code), '[]'::jsonb)
       from pb2 p join public.locations lo on lo.id = p.loc),
    (select coalesce(sum(r.amount * ((least(p_to, (r.mth + interval '1 month')::date - 1) - greatest(p_from, r.mth) + 1)::numeric / ((r.mth + interval '1 month')::date - r.mth))), 0)
       from public._c78_rows(p_from, p_to) r where r.dkind = 'unallocated' and r.share_loc = any (locs)),
    (select jsonb_build_object('net_sales', round(coalesce(sum(net), 0), 2), 'costed_sales', round(coalesce(sum(costed), 0), 2), 'uncosted_sales', round(coalesce(sum(unk), 0), 2),
        'cogs', round(coalesce(sum(cogs), 0), 2), 'gross_profit', round(coalesce(sum(gp), 0), 2), 'contribution_margin', round(coalesce(sum(cm), 0), 2),
        'overhead_total', round(coalesce(sum(oh), 0), 2), 'net_profit', round(coalesce(sum(np), 0), 2)) from b2)
    into br, pr, pb, unal, total;
  return jsonb_build_object('from', p_from, 'to', p_to, 'location_ids', to_jsonb(locs), 'category', p_category,
    'branches', br, 'products', pr, 'product_branch', pb, 'company', coalesce(total, '{}'::jsonb) || jsonb_build_object('unallocated_shared_costs', round(coalesce(unal, 0), 2)),
    'cost_source', rcs, 'variable_heads', to_jsonb(vh),
    'included', jsonb_build_array('net_sales_after_discount_and_returns', 'cogs_from_stock_ledger_cost', 'wastage_and_transit_loss_at_ledger_cost', 'card_fees_by_settlement_date',
      'variable_expense_heads', 'other_expenses_quick_and_form_10_2', 'salary_sheet_02_2', 'monthly_fixed_cost', 'shared_bills_attributed_pro_rated_by_days'),
    'not_included', jsonb_build_array('profit_on_sales_with_unknown_cost', 'payroll_app_payments', 'shared_bills_not_attributed_to_a_place', 'online_delivery_charge',
      'depreciation_and_other_books_only_entries', 'product_conversion_cost_when_factory_costing_is_off'),
    'allocation', 'product fees, variable expenses and overhead = branch amount x product share of the branch net sales');
end $$;

-- ---------- CSV export audit ----------
create or replace function public.recon_export_log118(p_key text, p_rows integer default 0, p_filters jsonb default '{}'::jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare sid text; f jsonb := coalesce(p_filters, '{}'::jsonb); need text;
begin
  if p_key is null or p_key not in ('stock_recon', 'sales_unmatched', 'factory_branch', 'net_profit_branch', 'net_profit_product') then raise exception 'unknown_report'; end if;
  need := case when p_key in ('stock_recon', 'sales_unmatched') then 'view_stock_recon' when p_key = 'factory_branch' then 'view_branch_statement' else 'view_net_profit' end;
  if not public.is_active() or not (public.is_owner() or (public.has_grant(need) and public.rpt_grant('export_data') and (need <> 'view_net_profit' or public.biz_cost_ok()))) then raise exception 'not allowed'; end if;
  if length(f::text) > 4000 then f := jsonb_build_object('truncated', true); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'export', 'recon_report', p_key, jsonb_build_object('kind', 'csv', 'rows', least(greatest(coalesce(p_rows, 0), 0), 100000000), 'filters', f));
end $$;

-- ---------- privileges ----------
revoke all on function public._rc118_locs(text, integer), public._rc118_buckets(date, date, integer[], uuid, text), public._rc118_gap(date, date, integer[], uuid),
  public._rc118_gap_summary(date, date, integer[], uuid) from public, anon, authenticated;
revoke all on function public.stock_recon_statement(date, date, integer, uuid, text, integer), public.stock_sales_unmatched(date, date, integer, uuid, integer),
  public.factory_branch_statement(date, date, integer, uuid, text, integer), public.net_profit_report(date, date, integer, text),
  public.recon_export_log118(text, integer, jsonb) from public, anon;
grant execute on function public.stock_recon_statement(date, date, integer, uuid, text, integer), public.stock_sales_unmatched(date, date, integer, uuid, integer),
  public.factory_branch_statement(date, date, integer, uuid, text, integer), public.net_profit_report(date, date, integer, text),
  public.recon_export_log118(text, integer, jsonb) to authenticated;

commit;

-- ---------------------------------------------------------------- phase526.sql
-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase120.sql there and is already pasted on the live database under that name.
-- Renumbered to phase526.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 526 (bos120) - STEP C4: performance of the phase112..118 reports (review on a scratch copy at the owner's size, report in the C4 hand-over)
-- Run AFTER phase118 (it rewrites three functions of phase118). Additive and idempotent: paste twice = no error, same result. Whole file = one transaction: if a guard refuses, nothing changes.
--
-- Measured on 1,369 items / 229 categories / 329,000 stock_ledger rows / 50,500 sales over 2 years / 6,000 transfers / 6,000 production runs
-- (tests/sql/perf/seed.sql + seed_c4.sql), default work_mem 4 MB, 1 month = 30 days, best of 6 warm runs on a quiet box (on a loaded box the old times were 1.5x worse):
--                                    1 day            1 month          1 year          (before -> after)
--   stock_recon_statement            1.81 -> 0.46 s   2.14 -> 0.51 s   6.02 -> 2.24 s
--   factory_branch_statement         2.05 -> 0.54 s   2.28 -> 0.59 s   3.00 -> 0.74 s
--   stock_sales_unmatched            0.02 -> 0.01 s   0.31 -> 0.09 s   6.42 -> 1.55 s
-- Results are IDENTICAL: md5 of 621 outputs (periods x places x items x categories, incl. the internal buckets / gap functions) equal before and after on the 329k-row database
-- (tests/sql/perf/equality120.sh); the fixtures of supabase/phase526_test.sql give the same md5 for the phase118 bodies and these bodies on 1,116 cases and check the hand numbers.
--
-- What was slow, and the fix (each is a CREATE OR REPLACE of a phase118 function, same signature, same output, tag bos120 added next to bos118):
--   R1 _rc118_buckets  (under stock_recon_statement AND factory_branch_statement): every call read the whole ledger through 1,369 item-by-item bitmap scans, sorted 329k rows on disk and
--      ran 15 FILTER aggregates over every row. Now one pass, rows summed once per (place, item, period part, bucket) in a hash aggregate, the 15 columns read from those few sums; a reversal
--      row looks up its original only when it is a reversal; rows far from the period edges skip the time-zone conversion; the "returned to the sender" test is one hashed set of
--      transfer ids. The function carries SET work_mem = '64MB' and jit = off (the 4 MB default made the planner sort on disk; the 64 MB is used only while the call runs).
--   R2 _rc118_gap  (under stock_sales_unmatched and the summary of stock_recon_statement): _base_qty() (plpgsql, two lookups) was called twice for every sales line (186k calls for a year).
--      Now the unit factor is taken once per distinct (item, unit) pair (about 1,000) and multiplied: _base_qty(i, q, u) = q * _base_qty(i, 1, u), or NULL when the factor is unknown.
--      The item join (tracked flag) is done on those pairs too. Same SET work_mem / jit.
--   R3 stock_sales_unmatched: the list and the counts came from two separate runs of _rc118_gap; now one run (materialized) feeds both.
--
-- Indexes: NONE shipped. Tested and rejected (no measurable gain on this data; each measured on the real functions, then dropped): stock_transfers (item_id, from_location_id, to_location_id,
--   sent_at) for the "return" test; stock_ledger (ref_id) WHERE ref_type = 'transfer' AND reason = 'transfer_out' AND reverses_id IS NULL for the transfer cost lookup. The remaining time of the
--   year views of net_profit_report / profit_truth112 (5-7 s) is two runs of the phase110 function _cogs_lines72 (2.9 s each for 31,000 sales); that is an OLD function and is not touched here.
--
-- Re-paste rule: a re-paste of phase118 puts the older (slower, same result) bodies of these three functions back: paste phase526 again after it.
-- If a later phase re-creates one of the three, merge its change into the text below first: the check before the rewrites stops the paste when a body carries a tag this file does not know.
-- ============================================================
begin;

-- ============================ 0. GUARD ============================
do $g$
declare miss text := ''; m record; src text; t text; bad text := '';
begin
  for m in select * from (values
    ('118', 'public._rc118_buckets(date,date,integer[],uuid,text)'), ('118', 'public._rc118_gap(date,date,integer[],uuid)'), ('118', 'public._rc118_gap_summary(date,date,integer[],uuid)'),
    ('118', 'public._rc118_locs(text,integer)'), ('118', 'public.stock_sales_unmatched(date,date,integer,uuid,integer)'),
    ('118', 'public.stock_recon_statement(date,date,integer,uuid,text,integer)'), ('118', 'public.factory_branch_statement(date,date,integer,uuid,text,integer)'),
    ('82', 'public._base_qty(uuid,numeric,text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null and position(' ' || m.ph in miss) = 0 then miss := miss || ' ' || m.ph; end if;
  end loop;
  if miss <> '' then
    raise exception 'phase526 needs phase118 (and 72..103) pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
  -- stop when one of the three functions was changed by a phase this file does not know (merge that change into the text below first)
  for m in select * from (values
    ('public._rc118_buckets(date,date,integer[],uuid,text)', array['bos118','bos120']),
    ('public._rc118_gap(date,date,integer[],uuid)', array['bos118','bos120']),
    ('public.stock_sales_unmatched(date,date,integer,uuid,integer)', array['bos118','bos120'])) v(fn, known)
  loop
    select p.prosrc into src from pg_proc p where p.oid = to_regprocedure(m.fn);
    for t in select distinct x[1] from regexp_matches(src, '(bos[0-9]+)', 'g') x loop
      if not t = any (m.known) then bad := bad || ' ' || m.fn || ' has ' || t || ';'; end if;
    end loop;
  end loop;
  if bad <> '' then
    raise exception 'phase526 stopped: a function it re-creates was changed by a phase it does not know (merge that change into phase526 first):%', bad;
  end if;
end $g$;

-- ============================ 1. INDEXES ============================
-- none (see the header: two candidates were measured and gave nothing)

-- ============================ 2. FUNCTION REWRITES (same signature, same result) ============================

-- R1  _rc118_buckets: the one ledger scan under stock_recon_statement and factory_branch_statement.
--     before: items x (bitmap scan of the item's ledger rows) nested loop -> 329k rows sorted on disk (30 MB) -> GroupAggregate with 15 FILTER aggregates over every row.
--     now:    one pass over the ledger (a seq scan; an index probe when one item is asked for, a join to items only when a category is asked for), each row put in
--             (place, item, effective reason, period part, returned-to-sender) and summed ONCE in a hash aggregate; the 15 columns are then read from those few sums.
--     same numbers: numeric addition is exact, a reversal row still counts under the reason of the row it reverses, a transfer out is a return when the receiver sent the item
--     to the sender earlier (the old EXISTS, now one hashed set of transfer ids).
create or replace function public._rc118_buckets(p_from date, p_to date, p_locs integer[], p_item uuid, p_cat text)
returns table (location_id integer, item_id uuid, opening numeric, production numeric, used numeric, purchases numeric, transfer_in numeric,
               transfer_ret numeric, transfer_oth numeric, sales numeric, cust_back numeric, wastage numeric, transit_loss numeric,
               adjustments numeric, closing numeric, ledger_total numeric, moves bigint)
language sql stable security definer set search_path = public set work_mem = '64MB' set jit = off as $$
-- bos118: the one set of ledger buckets both statements use. A reversal row is counted in the bucket of the row it reverses (so a cancelled transfer nets to 0 in
-- "transfers out"); out-going buckets are positive numbers. A transfer out is a RETURN when the receiver had earlier sent the same item to the sender.
-- Identity per row:  closing = opening + production + purchases + transfer_in + cust_back - used - sales - wastage - transit_loss - transfer_ret - transfer_oth + adjustments
-- bos120: same result, cheaper plan (phase526.sql R1). code: 1 production 2 used 3 purchases 4 transfer in 5 return 6 other transfer out 7 sale 8 give-back 9 wastage 10 transit loss 11 adjustment.
  with ret as materialized (
    select t.id from public.stock_transfers t
     where exists (select 1 from public.stock_transfers t2
                    where t2.from_location_id = t.to_location_id and t2.to_location_id = t.from_location_id and t2.item_id = t.item_id and t2.sent_at < t.sent_at and t2.status <> 'cancelled')),
  src as (
    select sl.location_id, sl.item_id, sl.qty_delta, sl.made_at, sl.reason, sl.ref_type, sl.ref_id, sl.reverses_id
      from public.stock_ledger sl
     where p_item is not null and sl.item_id = p_item and sl.location_id = any (p_locs)
       and (p_cat is null or sl.item_id in (select i.id from public.items i where i.category = p_cat))
    union all
    select sl.location_id, sl.item_id, sl.qty_delta, sl.made_at, sl.reason, sl.ref_type, sl.ref_id, sl.reverses_id
      from public.stock_ledger sl join public.items i on i.id = sl.item_id
     where p_item is null and p_cat is not null and i.category = p_cat and sl.location_id = any (p_locs)
    union all
    select sl.location_id, sl.item_id, sl.qty_delta, sl.made_at, sl.reason, sl.ref_type, sl.ref_id, sl.reverses_id
      from public.stock_ledger sl
     where p_item is null and p_cat is null and sl.location_id = any (p_locs)),
  bnd as materialized (select ((p_from::timestamp - interval '2 days') at time zone 'Asia/Dhaka') as f0, ((p_to::timestamp + interval '3 days') at time zone 'Asia/Dhaka') as t1),
  e as (
    select s.location_id, s.item_id, s.qty_delta, s.ref_type, s.ref_id,
           (case when s.reverses_id is null then s.reason else (select o.reason from public.stock_ledger o where o.id = s.reverses_id) end) as eff,
           (case when s.made_at < b.f0 then 0 when s.made_at >= b.t1 then 2   -- far from both edges: no time-zone conversion needed
                 when (s.made_at at time zone 'Asia/Dhaka')::date < p_from then 0 when (s.made_at at time zone 'Asia/Dhaka')::date <= p_to then 1 else 2 end) as part
      from src s cross join bnd b),
  l as (
    select e.location_id, e.item_id, e.qty_delta, e.part,
           (case e.eff when 'production_in' then 1 when 'issue_out' then 2 when 'purchase_in' then 3 when 'purchase_return' then 3 when 'transfer_in' then 4
                       when 'transfer_out' then (case when e.ref_type = 'transfer' and (case when e.ref_id ~ '^[0-9a-f-]{36}$' then e.ref_id::uuid end) in (select r.id from ret r) then 5 else 6 end)
                       when 'sale_out' then 7 when 'sale_void_in' then 8 when 'sale_return' then 8 when 'wastage' then 9 when 'transit_loss' then 10 else 11 end) as code
      from e),
  a as (select l.location_id, l.item_id, l.part, l.code, sum(l.qty_delta) as q, count(*) as n from l group by 1, 2, 3, 4)
  select a.location_id, a.item_id,
    coalesce(sum(a.q) filter (where a.part = 0), 0),
    coalesce(sum(a.q) filter (where a.part = 1 and a.code = 1), 0),
    coalesce(-sum(a.q) filter (where a.part = 1 and a.code = 2), 0),
    coalesce(sum(a.q) filter (where a.part = 1 and a.code = 3), 0),
    coalesce(sum(a.q) filter (where a.part = 1 and a.code = 4), 0),
    coalesce(-sum(a.q) filter (where a.part = 1 and a.code = 5), 0),
    coalesce(-sum(a.q) filter (where a.part = 1 and a.code = 6), 0),
    coalesce(-sum(a.q) filter (where a.part = 1 and a.code = 7), 0),
    coalesce(sum(a.q) filter (where a.part = 1 and a.code = 8), 0),
    coalesce(-sum(a.q) filter (where a.part = 1 and a.code = 9), 0),
    coalesce(-sum(a.q) filter (where a.part = 1 and a.code = 10), 0),
    coalesce(sum(a.q) filter (where a.part = 1 and a.code = 11), 0),
    coalesce(sum(a.q) filter (where a.part <= 1), 0),
    coalesce(sum(a.q), 0),
    coalesce(sum(a.n) filter (where a.part = 1), 0)::bigint
  from a group by a.location_id, a.item_id;
$$;

-- R2  _rc118_gap: sales lines against the sale_out rows they posted.
--     before: _base_qty() (a plpgsql function with two lookups) was called TWICE per sales line (186k calls for a year).
--     now:    the conversion factor is taken once per distinct (item, unit) pair (about 1,000 calls) and multiplied: _base_qty(item, q, unit) is q * factor (or q, or NULL when the
--             factor is unknown), so q * _base_qty(item, 1, unit) is the same number.
create or replace function public._rc118_gap(p_from date, p_to date, p_locs integer[], p_item uuid)
returns table (sale_id uuid, receipt integer, sale_date date, location_id integer, item_id uuid, sold_qty numeric, base_qty numeric, ledger_qty numeric, diff_qty numeric, kind text)
language sql stable security definer set search_path = public set work_mem = '64MB' set jit = off as $$
-- bos118: done sales (voids excluded) per sale and item: quantity in the item's BASE unit against the sale_out rows the sale posted. Lines without an item (quick sales) are skipped.
-- bos120: unit factor once per (item, unit), not twice per line (phase526.sql R2).
  with ln as (
    select s.id as sid, s.receipt as rc, s.sale_date as sd, s.location_id as lid,
           (case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end) as iid,
           (case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end) as q, nullif(btrim(e->>'unit'), '') as u
      from public.sales s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
     where s.status = 'done' and s.sale_date between p_from and p_to and s.location_id = any (p_locs)),
  ln2 as (select ln.* from ln where ln.iid is not null and ln.q is not null and (p_item is null or ln.iid = p_item)),
  fac as materialized (select d.iid, d.u, public._base_qty(d.iid, 1::numeric, d.u) as f, i.tracked
                         from (select distinct ln2.iid, ln2.u from ln2) d join public.items i on i.id = d.iid),
  g as (
    select ln2.sid, ln2.rc, ln2.sd, ln2.lid, ln2.iid, sum(ln2.q) as q, sum(ln2.q * fac.f) as bq, bool_or(fac.f is null) as unk, bool_and(fac.tracked) as tracked
      from ln2 join fac on fac.iid = ln2.iid and coalesce(fac.u, '') = coalesce(ln2.u, '') group by 1, 2, 3, 4, 5),
  led as (
    select sl.ref_id as rid, sl.item_id as iid, sum(-sl.qty_delta) as lq from public.stock_ledger sl
     where sl.ref_type = 'sale' and sl.reason = 'sale_out' and sl.ref_id in (select sid::text from g) group by 1, 2)
  select g.sid, g.rc, g.sd, g.lid, g.iid, g.q, g.bq, coalesce(led.lq, 0), coalesce(g.bq, 0) - coalesce(led.lq, 0),
         (case when not g.tracked then 'untracked' when g.unk then 'unit_unknown' when coalesce(led.lq, 0) = 0 then 'not_posted'
               when g.bq - led.lq > 0.0005 then 'short_posted' else 'over_posted' end)
    from g left join led on led.rid = g.sid::text and led.iid = g.iid
   where (not g.tracked) or g.unk or abs(coalesce(g.bq, 0) - coalesce(led.lq, 0)) > 0.0005;
$$;

-- R3  stock_sales_unmatched: the list and the counts come from ONE run of _rc118_gap (it ran twice: once for the rows, once for _rc118_gap_summary).
create or replace function public.stock_sales_unmatched(p_from date, p_to date, p_loc integer default null, p_item uuid default null, p_limit integer default 500)
returns jsonb language plpgsql stable security definer set search_path = public as $$
-- bos118 (A2 G2): sales lines whose quantity did not leave stock as sold. kind: untracked (item not stock-tracked, expected), unit_unknown (no unit conversion, stock not reduced),
-- not_posted (tracked, nothing posted), short_posted / over_posted (quantity differs). Quantities only, no cost.
-- bos120: one gap run for rows + counts (phase526.sql R3).
declare locs integer[]; lim integer := least(greatest(coalesce(p_limit, 500), 1), 2000); rows_j jsonb; cnt jsonb; tot integer;
begin
  if p_from is null or p_to is null or p_to < p_from then raise exception 'bad_period'; end if;
  if p_to - p_from > 370 then raise exception 'period_too_long'; end if;
  locs := public._rc118_locs('view_stock_recon', p_loc);
  with gp as materialized (select * from public._rc118_gap(p_from, p_to, locs, p_item))
  select (select coalesce(jsonb_agg(q.j order by q.sale_date desc, q.receipt desc), '[]'::jsonb) from (
            select g.sale_date, g.receipt, jsonb_build_object('sale_id', g.sale_id, 'receipt', g.receipt, 'sale_date', g.sale_date, 'location_id', g.location_id,
                     'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn), 'item_id', g.item_id, 'item_code', i.code, 'item_bn', i.name_bn, 'item_en', coalesce(i.name_en, i.name_bn),
                     'unit', i.unit, 'base_unit', coalesce(i.base_unit, i.unit), 'sold_qty', round(g.sold_qty, 4), 'sold_base_qty', round(g.base_qty, 4), 'ledger_qty', round(g.ledger_qty, 4),
                     'diff_qty', round(g.diff_qty, 4), 'kind', g.kind) as j
              from gp g join public.items i on i.id = g.item_id join public.locations lo on lo.id = g.location_id
             order by g.sale_date desc, g.receipt desc limit lim) q),
         (select coalesce(jsonb_object_agg(k.kind, k.n), '{}'::jsonb) from (select g2.kind, count(*) as n from gp g2 group by g2.kind) k)
    into rows_j, cnt;
  select coalesce(sum(value::int), 0) into tot from jsonb_each_text(cnt);
  return jsonb_build_object('from', p_from, 'to', p_to, 'location_ids', to_jsonb(locs), 'rows', rows_j, 'counts', cnt, 'total', tot, 'truncated', tot > lim);
end $$;

commit;

-- ---------------------------------------------------------------- phase121.sql
-- ============================================================
-- Phase 121 (marker sec121) - SECURITY / ROBUSTNESS fixes found by the review of phases 112..118. Runs LAST (after phase118).
--   Needs phases 72..118 pasted first (guard below). Paste twice = no change. Behaviour-neutral at the defaults (every switch of 112..118 is OFF).
--   Fixes
--     1 customer_dues_net113()          revoke from public / anon, execute for authenticated only (it lists customers and their dues).
--     2 pool_set, _pool_gl_after_bill117  the GL sync (_pool_gl_sync117) is started only when pool_gl_post117 is ON AND the caller is the owner or an accountant
--                                       (is_owner() or _acct_manage()); for everybody else the existing catch-up posts it later.
--     3 cost_wait_supply96              with cost_supply_to_avg116 ON the average move (_cw_apply_avg116) needs is_owner() or _recipe_mgr() or _acct_manage();
--                                       otherwise the supplied cost is saved as before, the average is NOT moved and the answer carries needs_manager = true.
--     4 sale_return                     with return_uses_sale_rows ON the sold quantity of an item is the sum of _base_qty(item, qty, unit) over ALL its lines
--                                       (mixed units), the returned part is bq / sold_line_base, so a mixed-unit sale never restores more than it sold
--                                       (unknown unit on any line = the old factor path, as before).
--     5 bank_stmt_post113               the p_client duplicate lookup runs BEFORE line_already_matched / already_posted, so a retry returns dup:true.
--     6 stock_return_transfer           the original transfer row is locked (for update) before the returned-quantity check.
--     7 production_recost116            the rights are checked BEFORE the row lock of the run is taken.
--   Marker: sec121, deliberately NOT a bosNN tag (like perf110 / b2s115): the body guards of phases 524 / 103 / 109 / 114 / 116 / 117 refuse a body with a bosNN tag
--   they do not know, which would make the documented re-paste tail (89, 103 .. 111, 112 .. 118, 121) impossible. Re-paste rule: after any re-paste of 112..118 paste phase121 again.
--   Method: exact-text patch of the CURRENT body (helper _s121_patch dropped at the end; every older tag kept; a body that no longer holds the expected text stops the file).
-- ============================================================
begin;

do $g$
declare miss text := ''; f text;
begin
  foreach f in array array['public.customer_dues_net113()', 'public._pool_gl_sync117(integer,date)', 'public._pool_gl_after_bill117(bigint)', 'public._cw_apply_avg116(uuid,text,text)',
                           'public.bank_stmt_post113(bigint,text,integer,text,uuid,boolean)', 'public.stock_return_transfer(integer,integer,uuid,numeric,text,uuid,text,text,uuid)',
                           'public.production_recost116(uuid,boolean)', 'public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)', 'public.cost_wait_supply96(text,text,text,jsonb,text,uuid,boolean)',
                           'public.pool_set(integer,date,text,numeric,text,boolean,text,uuid)', 'public.net_profit_report(date,date,integer,text)']
  loop
    if to_regprocedure(f) is null then miss := miss || ' ' || f; end if;
  end loop;
  if miss <> '' then raise exception 'phase121 needs phases 72..118 pasted first (docs/PASTE_ORDER.md); missing:%', miss; end if;
end $g$;

create or replace function public._s121_patch(p_sig text, p_old text[], p_new text[], p_marker text) returns void
language plpgsql set search_path = public as $$
declare d text; f regprocedure := to_regprocedure(p_sig); n int; i int;
begin
  if f is null then raise exception 'phase121: function % not found', p_sig; end if;
  d := pg_get_functiondef(f);
  if position(p_marker in d) > 0 then return; end if;                               -- already patched: paste twice = no change
  for i in 1 .. array_length(p_old, 1) loop
    n := (length(d) - length(replace(d, p_old[i], ''))) / length(p_old[i]);
    if n <> 1 then raise exception 'phase121: expected text #% found % times (need exactly 1) in %; the function changed - merge by hand', i, n, p_sig; end if;
    d := replace(d, p_old[i], p_new[i]);
  end loop;
  execute d;
end $$;

-- 1 ---------------------------------------------------------------------------------------------------------------
revoke all on function public.customer_dues_net113() from public, anon;
grant execute on function public.customer_dues_net113() to authenticated;

-- 2 ---------------------------------------------------------------------------------------------------------------
select public._s121_patch('public.pool_set(integer,date,text,numeric,text,boolean,text,uuid)',
  array[$a$if public.rule_on('pool_gl_post117') then      -- bos117:$a$],
  array[$a$if public.rule_on('pool_gl_post117') and (public.is_owner() or public._acct_manage()) then      -- sec121: owner / accountant only, others rely on the catch-up; bos117:$a$], 'sec121');
select public._s121_patch('public._pool_gl_after_bill117(bigint)',
  array[$a$if not public.rule_on('pool_gl_post117') then return; end if;$a$],
  array[$a$if not (public.rule_on('pool_gl_post117') and (public.is_owner() or public._acct_manage())) then return; end if;      -- sec121: owner / accountant only, others rely on the catch-up$a$], 'sec121');

-- 3 ---------------------------------------------------------------------------------------------------------------
select public._s121_patch('public.cost_wait_supply96(text,text,text,jsonb,text,uuid,boolean)',
  array[$a$declare pl jsonb;$a$,
        $a$if public.rule_on('cost_supply_to_avg116') then perform public._cw_apply_avg116(p_client, p_kind, p_ref); end if;$a$,
        $a$'errors', pr->'errors') end);$a$],
  array[$a$declare nm121 boolean := false; pl jsonb;$a$,
        $a$if public.rule_on('cost_supply_to_avg116') then      -- sec121: the average move needs a manager
    if public.is_owner() or public._recipe_mgr() or public._acct_manage() then perform public._cw_apply_avg116(p_client, p_kind, p_ref); else nm121 := true; end if;
  end if;$a$,
        $a$'errors', pr->'errors') end) || case when nm121 then jsonb_build_object('needs_manager', true) else '{}'::jsonb end;$a$], 'sec121');

-- 4 ---------------------------------------------------------------------------------------------------------------
select public._s121_patch('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)',
  array[$a$bq := coalesce((select z.sold_base * ln.q / z.sold_line from (select$a$,
        $a$(select sum(nullif(e->>'qty', '')::numeric) from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
              where e->>'item_id' = it.id::text and (e->>'unit') is not distinct from ln.u) sold_line) z$a$],
  array[$a$bq := coalesce((select z.sold_base * bq / z.sold_line from (select$a$,
        $a$(select case when count(*) filter (where q.b is null) > 0 then null else sum(q.b) end from (select public._base_qty(it.id, nullif(e->>'qty', '')::numeric, e->>'unit') b      -- sec121: all lines of the item, in base units
              from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e where e->>'item_id' = it.id::text) q) sold_line) z$a$], 'sec121');

-- 5 ---------------------------------------------------------------------------------------------------------------
select public._s121_patch('public.bank_stmt_post113(bigint,text,integer,text,uuid,boolean)',
  array[$a$  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.journal_entries where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', r.id); end if;
  end if;
  memo :=$a$,
        $a$  if exists (select 1 from public.bank_recon_matches where line_id = p_line and active) then raise exception 'line_already_matched'; end if;$a$],
  array[$a$  memo :=$a$,
        $a$  if p_client is not null and not coalesce(p_dry, false) then      -- sec121: a retry with the same client id answers dup before line_already_matched / already_posted
    perform public._client_lock(p_client);
    select * into r from public.journal_entries where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', r.id); end if;
  end if;
  if exists (select 1 from public.bank_recon_matches where line_id = p_line and active) then raise exception 'line_already_matched'; end if;$a$], 'sec121');

-- 6 ---------------------------------------------------------------------------------------------------------------
select public._s121_patch('public.stock_return_transfer(integer,integer,uuid,numeric,text,uuid,text,text,uuid)',
  array[$a$select * into o from public.stock_transfers where id = p_ref;$a$],
  array[$a$select * into o from public.stock_transfers where id = p_ref for update;      -- sec121: two returns of one transfer are serial$a$], 'sec121');

-- 7 ---------------------------------------------------------------------------------------------------------------
select public._s121_patch('public.production_recost116(uuid,boolean)',
  array[$a$  select * into run from public.production_runs where id = p_run for update;
  if not found then raise exception 'not_found'; end if;
  if not (public._recipe_mgr() and public._cost_ok(run.location_id) and public.can_loc(run.location_id)) then raise exception 'not allowed'; end if;$a$],
  array[$a$  select * into run from public.production_runs where id = p_run;      -- sec121: rights first, the row lock only for an allowed caller
  if not found then raise exception 'not_found'; end if;
  if not (public._recipe_mgr() and public._cost_ok(run.location_id) and public.can_loc(run.location_id)) then raise exception 'not allowed'; end if;
  select * into run from public.production_runs where id = p_run for update;$a$], 'sec121');

drop function public._s121_patch(text, text[], text[], text);
commit;

-- ---------------------------------------------------------------- phase122.sql
-- ============================================================
-- Phase 122 (marker org122) - GROUP ERP, STAGE B1: the organization layer (ADDITIVE ONLY, ZERO behaviour change).
-- Plan: docs/GROUP_ERP_STAGE_A.md sections 10-11 (owner approved Stage A with changes and B1).
-- Canonical order: after phase121 (docs/PASTE_ORDER.md row 50). Needs only the base objects (no phase 72..121 function is touched or read).
-- Paste twice = no change, no error. Nothing existing is altered except ONE nullable column: locations.org_unit_id.
--   Tables (RLS on, no browser write, audit trigger, no hard delete)
--     business_templates  code, name, modules jsonb, status (available | configured | needs_setup | planned | not_implemented). Seeded; food_manufacturing = available
--                         (the sweets business), dealership / hardware_paint / technology / construction / online_store = not_implemented (a record only, no screens).
--     org_units           id, parent_id, kind (group | legal_entity | business | branch | site | department | cost_centre | project), code (unique), names, template_code,
--                         status (planned | active | inactive), effective_from / effective_to, currency, tz, attrs jsonb, audit columns. Never deleted.
--     legal_entities      org_unit_id, trade_licence_ref, tax_cfg jsonb, fiscal_start, base_currency, owner_pct (0..100, default 100). One row per legal_entity unit.
--     locations.org_unit_id  nullable. Seed: ONE group, ONE legal entity, ONE business for the existing sweets business; the existing locations are mapped to that
--                         business (fill-null-only, never overwrites, a later paste maps only locations that existed at the first paste).
--   Rule org_scope_on (switch, default OFF). NOTHING reads it yet: can_loc() and every existing function / report / policy are unchanged (that is Stage C1).
--   Functions
--     org_tree()                       read: owner or grant org_manage see every unit; anybody else only the units (and their parents) of locations they are assigned to.
--                                      Ownership %, tax config and licence number: owner only (licence also org_manage).
--     org_unit_scope(location_id)      read: location -> unit -> business -> legal entity -> group (same visibility rule).
--     org_unit_save(...)               create / update one unit (owner or grant org_manage). Create needs p_client (idempotent). Kind and code never change.
--     org_unit_deactivate(id, reason)  status inactive + effective_to; history stays; refused while active children or active locations hang under it.
--   Grant org_manage (grant_defs). Advisor row for org_scope_on (setup_rec_defs81, no value recommended).
--   No function of this file is called by any existing code.
-- Rollback: leave org_scope_on OFF (default). To remove: drop the four functions, the three tables and locations.org_unit_id (nothing else refers to them).
-- ============================================================
begin;

do $g$
declare miss text := '';
begin
  if to_regclass('public.locations') is null or to_regclass('public.audit_log') is null or to_regclass('public.grant_defs') is null or to_regclass('public.rules') is null
     or to_regclass('public.user_locations') is null or to_regclass('public.setup_rec_defs81') is null then miss := miss || ' tables'; end if;
  if to_regprocedure('public.is_owner()') is null or to_regprocedure('public.is_active()') is null or to_regprocedure('public.has_grant(text,integer)') is null
     or to_regprocedure('public.log_change()') is null or to_regprocedure('public.no_hard_delete()') is null or to_regprocedure('public._client_lock(uuid)') is null
     or to_regprocedure('public.rule_on(text)') is null then miss := miss || ' functions'; end if;
  if miss <> '' then raise exception 'phase122 needs the base schema and phases up to 121 pasted first (docs/PASTE_ORDER.md); missing:%', miss; end if;
end $g$;

-- ---------- 1. tables ----------
create table if not exists public.business_templates (
  code text primary key check (code ~ '^[a-z][a-z0-9_]{1,40}$'),
  name_bn text not null, name_en text not null,
  modules jsonb not null default '[]'::jsonb check (jsonb_typeof(modules) = 'array'),
  status text not null default 'not_implemented' check (status in ('available', 'configured', 'needs_setup', 'planned', 'not_implemented')),
  sort int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.org_units (
  id bigserial primary key,
  parent_id bigint references public.org_units(id),
  kind text not null check (kind in ('group', 'legal_entity', 'business', 'branch', 'site', 'department', 'cost_centre', 'project')),
  code text not null unique check (code ~ '^[A-Z0-9][A-Z0-9_-]{1,39}$'),
  name_bn text not null check (length(btrim(name_bn)) between 1 and 120),
  name_en text check (name_en is null or length(name_en) <= 120),
  template_code text references public.business_templates(code),
  status text not null default 'active' check (status in ('planned', 'active', 'inactive')),
  effective_from date,
  effective_to date,
  currency text not null default 'BDT' check (currency ~ '^[A-Z]{3}$'),
  tz text not null default 'Asia/Dhaka',
  attrs jsonb not null default '{}'::jsonb check (jsonb_typeof(attrs) = 'object'),
  client_id uuid unique,
  deactivated_reason text, deactivated_by uuid, deactivated_at timestamptz,
  created_by uuid, created_at timestamptz not null default now(),
  updated_by uuid, updated_at timestamptz not null default now(),
  check (effective_to is null or effective_from is null or effective_to >= effective_from),
  check ((kind = 'group') = (parent_id is null)),
  check (template_code is null or kind = 'business')
);
create index if not exists org_units_parent122 on public.org_units (parent_id);
create unique index if not exists org_units_one_group122 on public.org_units (kind) where kind = 'group';

create table if not exists public.legal_entities (
  org_unit_id bigint primary key references public.org_units(id),
  trade_licence_ref text check (trade_licence_ref is null or length(trade_licence_ref) <= 80),
  tax_cfg jsonb not null default '{}'::jsonb check (jsonb_typeof(tax_cfg) = 'object'),
  fiscal_start date,
  base_currency text not null default 'BDT' check (base_currency ~ '^[A-Z]{3}$'),
  owner_pct numeric(7,4) not null default 100 check (owner_pct >= 0 and owner_pct <= 100),
  created_by uuid, created_at timestamptz not null default now(),
  updated_by uuid, updated_at timestamptz not null default now()
);

alter table public.locations add column if not exists org_unit_id bigint references public.org_units(id);
create index if not exists locations_org_unit122 on public.locations (org_unit_id);

-- a legal_entities row may belong only to a unit of kind legal_entity
create or replace function public._le_kind_check122() returns trigger
language plpgsql set search_path = public as $$
begin
  if not exists (select 1 from public.org_units u where u.id = new.org_unit_id and u.kind = 'legal_entity') then raise exception 'not_a_legal_entity'; end if;
  return new;
end $$;
drop trigger if exists le_kind_check122 on public.legal_entities;
create trigger le_kind_check122 before insert or update on public.legal_entities for each row execute function public._le_kind_check122();

-- never hard delete, history is audited
drop trigger if exists bt122_no_delete on public.business_templates;
create trigger bt122_no_delete before delete on public.business_templates for each row execute function public.no_hard_delete();
drop trigger if exists ou122_no_delete on public.org_units;
create trigger ou122_no_delete before delete on public.org_units for each row execute function public.no_hard_delete();
drop trigger if exists le122_no_delete on public.legal_entities;
create trigger le122_no_delete before delete on public.legal_entities for each row execute function public.no_hard_delete();
drop trigger if exists audit_bt122 on public.business_templates;
create trigger audit_bt122 after insert or update on public.business_templates for each row execute function public.log_change('code');
drop trigger if exists audit_ou122 on public.org_units;
create trigger audit_ou122 after insert or update on public.org_units for each row execute function public.log_change('id');
drop trigger if exists audit_le122 on public.legal_entities;
create trigger audit_le122 after insert or update on public.legal_entities for each row execute function public.log_change('org_unit_id');

-- RLS: no browser write at all; direct read only for the owner / org_manage (templates: any active user). Everything else goes through the functions.
alter table public.business_templates enable row level security;
alter table public.org_units enable row level security;
alter table public.legal_entities enable row level security;
drop policy if exists bt122_read on public.business_templates;
create policy bt122_read on public.business_templates for select to authenticated using (public.is_active());
drop policy if exists ou122_read on public.org_units;
create policy ou122_read on public.org_units for select to authenticated using (public.is_owner() or public.has_grant('org_manage'));
drop policy if exists le122_read on public.legal_entities;
create policy le122_read on public.legal_entities for select to authenticated using (public.is_owner());
revoke all on public.business_templates, public.org_units, public.legal_entities from public, anon, authenticated;
grant select on public.business_templates, public.org_units, public.legal_entities to authenticated;
revoke all on sequence public.org_units_id_seq from public, anon, authenticated;

-- ---------- 2. grant + rule + advisor row ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
select 'org_manage', 'settings', 99, 'প্রতিষ্ঠানের কাঠামো (ব্যবসা, শাখা, সাইট) তৈরি ও বদলানো', 'Organization কাঠামো (business, branch, site) তৈরি ও বদলানো', 'Create and change the organization structure (businesses, branches, sites)', 'once'
where not exists (select 1 from public.grant_defs where grant_code = 'org_manage');

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('org_scope_on', 'settings', 'switch', 'false', null, null, null, null,
  'ব্যবসা অনুযায়ী আলাদা ডেটা-সীমা (পরের ধাপে চালু হবে)', 'Business অনুযায়ী আলাদা data-scope (পরের ধাপে কাজ করবে)', 'Per-business data scope (takes effect in a later stage)',
  'এখন কিছুই বদলায় না। বন্ধ রাখুন। পরের ধাপে (C1) এটি অ্যাক্সেস-সীমা ব্যবসা অনুযায়ী করবে।',
  'এখন কিছুই বদলায় না। off রাখুন। পরের ধাপে (C1) এটি access-scope business অনুযায়ী করবে।',
  'Does nothing yet; keep it off. In Stage C1 it will make access scope follow the business. Nothing reads this switch in phase 122.', 990)
on conflict (key) do nothing;

insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort)
select 'org_scope_on', 'org_scope_on', '122', 'settings', null::jsonb, '{}'::text[],
  'এখন চালু করার দরকার নেই: এই ধাপে এটি কোনো কাজ করে না। বন্ধ থাকুক।',
  'এখন চালু করার দরকার নেই: এই ধাপে এটি কোনো কাজ করে না। off থাকুক।',
  'Leave it off: phase 122 only adds the organization tables; the switch is read by nothing until Stage C1.', 990
where not exists (select 1 from public.setup_rec_defs81 where code = 'org_scope_on');

-- ---------- 3. seed (templates, one group, one legal entity + business for sweets, location mapping) ----------
insert into public.business_templates (code, name_bn, name_en, modules, status, sort) values
 ('food_manufacturing', 'খাদ্য উৎপাদন ও খুচরা (মিষ্টি, বেকারি)', 'Food manufacturing and retail (sweets, bakery)',
  '["pos","stock","purchase","production","costing","accounting","reports"]'::jsonb, 'available', 10),
 ('dealership', 'ডিলারশিপ (যানবাহন)', 'Dealership', '[]'::jsonb, 'not_implemented', 20),
 ('hardware_paint', 'হার্ডওয়্যার ও রং', 'Hardware and paint', '[]'::jsonb, 'not_implemented', 30),
 ('technology', 'প্রযুক্তি', 'Technology', '[]'::jsonb, 'not_implemented', 40),
 ('construction', 'নির্মাণ', 'Construction', '[]'::jsonb, 'not_implemented', 50),
 ('online_store', 'অনলাইন স্টোর', 'Online store', '[]'::jsonb, 'not_implemented', 60)
on conflict (code) do nothing;

do $seed$
declare g bigint; le bigint; bz bigint; maxloc int; seeded boolean;
begin
  select id into g from public.org_units where kind = 'group' limit 1;
  if g is null then
    insert into public.org_units (kind, code, name_bn, name_en, status) values ('group', 'GROUP', 'গ্রুপ', 'Group', 'active') returning id into g;
  end if;
  select id into bz from public.org_units where code = 'SWEETS';
  seeded := bz is not null;
  if not seeded then
    insert into public.org_units (parent_id, kind, code, name_bn, name_en, status) values (g, 'legal_entity', 'LE-SWEETS', 'মিষ্টি ব্যবসা (প্রতিষ্ঠান)', 'Sweets business (legal entity)', 'active')
      on conflict (code) do nothing;
    select id into le from public.org_units where code = 'LE-SWEETS';
    insert into public.legal_entities (org_unit_id) values (le) on conflict (org_unit_id) do nothing;
    insert into public.org_units (parent_id, kind, code, name_bn, name_en, template_code, status, attrs)
      values (le, 'business', 'SWEETS', 'মিষ্টি ব্যবসা', 'Sweets business', 'food_manufacturing', 'active', '{}'::jsonb)
      on conflict (code) do nothing;
    select id into bz from public.org_units where code = 'SWEETS';
    select coalesce(max(id), 0) into maxloc from public.locations;
    update public.org_units set attrs = attrs || jsonb_build_object('seed122', jsonb_build_object('locations_up_to_id', maxloc)) where id = bz;
  end if;
  -- fill nulls only, never overwrite; only locations that existed when the sweets business was seeded
  select coalesce((attrs->'seed122'->>'locations_up_to_id')::int, 0) into maxloc from public.org_units where id = bz;
  update public.locations set org_unit_id = bz where org_unit_id is null and id <= maxloc;
end $seed$;

-- ---------- 4. functions ----------
-- may the caller manage the structure? (owner or a GLOBAL org_manage grant)
create or replace function public._org_mgr122() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('org_manage'));
$$;

-- which parent kinds a kind may sit under
create or replace function public._org_parent_ok122(p_kind text, p_parent_kind text) returns boolean
language sql immutable set search_path = public as $$
  select case p_kind
    when 'group' then false
    when 'legal_entity' then p_parent_kind = 'group'
    when 'business' then p_parent_kind = 'legal_entity'
    when 'branch' then p_parent_kind in ('business', 'branch')
    when 'site' then p_parent_kind in ('business', 'branch', 'site')
    when 'department' then p_parent_kind in ('business', 'branch', 'site', 'department')
    when 'cost_centre' then p_parent_kind in ('business', 'branch', 'site', 'department', 'cost_centre')
    when 'project' then p_parent_kind in ('business', 'branch', 'site')
    else false end;
$$;

-- units the caller may see: managers all; others the units (and their parents) of locations they are explicitly assigned to (NOT the management-role bypass of can_loc)
create or replace function public._org_visible122() returns setof bigint
language sql stable security definer set search_path = public as $$
  select u.id from public.org_units u where public._org_mgr122()
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

-- the tree. Owner / org_manage: every unit. Others: only their own branch of the tree. Ownership %, tax config: owner only. Licence: owner or org_manage.
create or replace function public.org_tree() returns table (
  id bigint, parent_id bigint, kind text, code text, name_bn text, name_en text, template_code text, template_status text, status text,
  effective_from date, effective_to date, currency text, tz text, attrs jsonb, depth int, path text, location_ids int[],
  trade_licence_ref text, owner_pct numeric, tax_cfg jsonb, fiscal_start date, base_currency text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query
  with recursive t(id, depth, path) as (
    select u.id, 0, u.code::text from public.org_units u where u.parent_id is null
    union all
    select c.id, t.depth + 1, t.path || '/' || c.code from public.org_units c join t on c.parent_id = t.id)
  select u.id, u.parent_id, u.kind, u.code, u.name_bn, u.name_en, u.template_code, bt.status, u.status,
         u.effective_from, u.effective_to, u.currency, u.tz,
         case when public._org_mgr122() then u.attrs else '{}'::jsonb end,
         t.depth, t.path,
         coalesce((select array_agg(l.id order by l.id) from public.locations l where l.org_unit_id = u.id
                    and (public._org_mgr122() or exists (select 1 from public.user_locations ul where ul.user_id = auth.uid() and ul.location_id = l.id))), '{}'::int[]),
         case when public._org_mgr122() then le.trade_licence_ref end,
         case when public.is_owner() then le.owner_pct end,
         case when public.is_owner() then le.tax_cfg end,
         case when public._org_mgr122() then le.fiscal_start end,
         le.base_currency
    from t join public.org_units u on u.id = t.id
    left join public.legal_entities le on le.org_unit_id = u.id
    left join public.business_templates bt on bt.code = u.template_code
   where u.id in (select * from public._org_visible122())
   order by t.path;
end $$;

-- location -> unit -> business -> legal entity -> group. Managers: any location. Others: only locations they are assigned to.
create or replace function public.org_unit_scope(p_location int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare loc public.locations; u bigint; r jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_location is null then raise exception 'bad_location'; end if;
  select * into loc from public.locations where id = p_location;
  if not found then raise exception 'bad_location'; end if;
  if not (public._org_mgr122() or exists (select 1 from public.user_locations ul where ul.user_id = auth.uid() and ul.location_id = p_location)) then raise exception 'not allowed'; end if;
  u := loc.org_unit_id;
  if u is null then return jsonb_build_object('location_id', p_location, 'org_unit_id', null, 'mapped', false); end if;
  with recursive up(id, parent_id, kind, code, lvl) as (
    select o.id, o.parent_id, o.kind, o.code, 0 from public.org_units o where o.id = u
    union all
    select p.id, p.parent_id, p.kind, p.code, up.lvl + 1 from public.org_units p join up on up.parent_id = p.id)
  select jsonb_build_object('location_id', p_location, 'mapped', true, 'org_unit_id', u,
    'business_id', (select id from up where kind = 'business' order by lvl limit 1),
    'business_code', (select code from up where kind = 'business' order by lvl limit 1),
    'legal_entity_id', (select id from up where kind = 'legal_entity' order by lvl limit 1),
    'legal_entity_code', (select code from up where kind = 'legal_entity' order by lvl limit 1),
    'group_id', (select id from up where kind = 'group' order by lvl limit 1),
    'path', (select jsonb_agg(code order by lvl desc) from up))
  into r;
  return r;
end $$;

-- create / update one unit. p_id null = create (needs p_client, repeat with the same key returns the same unit). Kind and code never change.
-- p_le (kind legal_entity only): {"trade_licence_ref","tax_cfg","fiscal_start","base_currency","owner_pct"}; owner_pct and tax_cfg need the owner.
create or replace function public.org_unit_save(p_id bigint, p_parent bigint, p_kind text, p_code text, p_name_bn text, p_name_en text default null,
  p_template text default null, p_status text default null, p_from date default null, p_to date default null, p_currency text default 'BDT',
  p_tz text default 'Asia/Dhaka', p_attrs jsonb default '{}'::jsonb, p_le jsonb default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  today date := (now() at time zone 'Asia/Dhaka')::date;
  me uuid := auth.uid(); o public.org_units; par public.org_units; code_ text := upper(btrim(coalesce(p_code, '')));
  st text; cur text := upper(btrim(coalesce(p_currency, 'BDT'))); tz_ text := btrim(coalesce(p_tz, 'Asia/Dhaka'));
  attrs_ jsonb := coalesce(p_attrs, '{}'::jsonb); nid bigint; k text;
  lic text; taxc jsonb; fs date; bcur text; pct numeric;
begin
  if not public._org_mgr122() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
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

-- deactivate: status inactive + effective_to; history stays. Refused while active child units or active locations hang under it. Repeating it is a no-op.
create or replace function public.org_unit_deactivate(p_id bigint, p_reason text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.org_units; today date := (now() at time zone 'Asia/Dhaka')::date;
begin
  if not public._org_mgr122() then raise exception 'not allowed'; end if;
  if p_reason is not null and length(p_reason) > 500 then raise exception 'bad_reason'; end if;
  perform public._client_lock(p_client);
  select * into o from public.org_units where id = p_id for update;
  if not found then raise exception 'unit_not_found'; end if;
  if o.status = 'inactive' then return jsonb_build_object('dup', true, 'id', o.id); end if;
  if exists (select 1 from public.org_units c where c.parent_id = o.id and c.status <> 'inactive') then raise exception 'has_active_children'; end if;
  if exists (select 1 from public.locations l where l.org_unit_id = o.id and l.is_active) then raise exception 'has_active_locations'; end if;
  update public.org_units set status = 'inactive', effective_to = case when effective_to is null or effective_to > today then today else effective_to end,
    deactivated_reason = nullif(btrim(coalesce(p_reason, '')), ''), deactivated_by = auth.uid(), deactivated_at = now(), updated_by = auth.uid(), updated_at = now()
   where id = o.id;
  return jsonb_build_object('dup', false, 'id', o.id);
end $$;

-- ---------- 5. privileges: helpers closed, browser functions for signed-in users only ----------
revoke all on function public._org_mgr122(), public._org_parent_ok122(text, text), public._org_visible122(), public._le_kind_check122() from public, anon, authenticated;
revoke all on function public.org_tree(), public.org_unit_scope(int),
  public.org_unit_save(bigint, bigint, text, text, text, text, text, text, date, date, text, text, jsonb, jsonb, uuid),
  public.org_unit_deactivate(bigint, text, uuid) from public, anon;
grant execute on function public.org_tree(), public.org_unit_scope(int),
  public.org_unit_save(bigint, bigint, text, text, text, text, text, text, date, date, text, text, jsonb, jsonb, uuid),
  public.org_unit_deactivate(bigint, text, uuid) to authenticated;

commit;

-- ---------------------------------------------------------------- phase123.sql
-- ============================================================
-- Phase 123 (marker scope123) - GROUP ERP, STAGE C1 first slice: business isolation behind the switch org_scope_on (DEFAULT OFF).
-- Plan: docs/GROUP_ERP_STAGE_A.md sections 3.4, 10, 11; audit docs/audit_c1/RLS_ISOLATION_AUDIT.md (branch local-audit-rls). Canonical order: after phase122 (docs/PASTE_ORDER.md row 51).
-- Paste twice = no change, no error. With org_scope_on OFF (the default) EVERY function below returns exactly what it returned before this file
-- (each re-created body keeps the old expression verbatim in its OFF branch; tests/sql/c1_before_after.sh proves it on seeded data).
-- Needs phase122 (org_units, locations.org_unit_id, rule org_scope_on). Rollback: leave the rule OFF; to remove, re-paste the older phase files that own the re-created
-- functions (phase7 can_loc, phase8 has_grant, phase10 _all_locs, phase40 _acct_all, phase46 _notif_ok, phase2 staff_directory, phase12/105 customer_dues + customer_ledger,
-- phase53 fa_register / fa_schedule / year_close_list, phase514 items_with_cost / item_cost_status88, phase521 drawer_report, phase112 profit_truth112, phase7 decide_emergency), drop the
-- restrictive policies *_scope123, the trigger stock_transfers_biz123 and the new table / functions.
--
--   NEW (all closed to anon; helpers closed to the browser too)
--     table user_org_scopes (user, org_unit, role, status active|revoked; history kept; RLS: own rows / owner / org_manage; no browser write; audit + no-delete triggers)
--       One row = "this user holds this role over this unit and everything below it". A row is live only while the user still holds that role in user_roles.
--     can_scope(unit, role) / business_of_location(loc) / business_of_unit are the public helpers; _org_on123 (the switch), _org_anc123, _scopes123, _user_biz123, _my_biz123,
--       _biz_ok123, _mgmt_covers123, _loc_vis123, _item_cost_scoped123 are internal.
--     org_scope_grant / org_scope_revoke / org_scope_list / org_scope_preflight : owner (list: owner / org_manage see all, others their own rows).
--   WHEN org_scope_on = ON (stricter option chosen wherever the plan left room, see HANDOVER_7)
--     can_loc(loc)   owner = every location. Anybody else: own user_locations row, or a live 'management' scope covering the location's unit (so management = all locations of ITS
--                    business only), or an approved loc_access window for a location of one of their businesses. can_loc(null) = owner only. The global management bypass is gone.
--     _all_locs(), _acct_all()   owner only (a company-wide view is a group-owner view; an accountant sees journals place by place through can_loc).
--     has_grant(code, loc)   with a location: the location must belong to one of the caller's businesses (role grants, personal grants and windows alike), and a personal
--                    grant with NULL location means "the caller's businesses", never the database. Without a location nothing changes (the data is filtered further down).
--     _notif_ok      a notification for the 'manager' audience with no place is owner only.
--     Readers that returned data of every place without can_loc now filter by it: customer_dues, customer_ledger, fa_register, fa_schedule, year_close_list (owner only),
--                    items_with_cost + item_cost_status88 (non-owner: cost computed from the stock of the caller's own places only), drawer_report, staff_directory (people of the
--                    caller's businesses only), profit_truth112 (a place that is not yours is refused).
--     Restrictive read policies (AND-ed with the old ones, true while the switch is OFF) on the location-bearing tables that any active user could read: locations, location_settings,
--                    att_site_geo, blind_count_cfg, doc_template_choice, form_rollout, holidays, path_switch, report_brand_map, sales_channels, shifts, invoice_templates + print_profiles
--                    (read and write), the weak has_grant-only ones: location_setup_steps, paper_books, print_notes, settings_sheets, and budget_log, payment_intents,
--                    payroll_bonus_events; emergency_requests (own rows, or the business's). A row with NULL location = owner only.
--     decide_emergency: the approver must belong to the request's business (the role grant emergency_decide is global).
--     A stock transfer between two businesses is refused by a trigger (intercompany is Stage E).
--   DEFERRED (docs/HANDOVER_7.md): global masters without an owner column (items, customers, suppliers, recipes, vocabularies, rules, roles, grant_defs ...) = Stage C2; per-business
--     rules; the other ~170 unscoped reader RPCs (Appendix B of the audit); owner-only RPC families; storage bucket paths; bot identities; find_customer / customer_balance.
-- ============================================================
begin;

do $g$
declare miss text := '';
begin
  if to_regclass('public.org_units') is null or to_regclass('public.legal_entities') is null or to_regclass('public.locations') is null or to_regclass('public.user_roles') is null
     or to_regclass('public.user_locations') is null or to_regclass('public.user_grants') is null or to_regclass('public.emergency_requests') is null
     or to_regclass('public.stock_transfers') is null or to_regclass('public.fa_assets') is null or to_regclass('public.drawer_events') is null then miss := miss || ' tables'; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'locations' and column_name = 'org_unit_id') then miss := miss || ' locations.org_unit_id'; end if;
  if not exists (select 1 from public.rules where key = 'org_scope_on') then miss := miss || ' rule:org_scope_on'; end if;
  if to_regprocedure('public.can_loc(integer)') is null or to_regprocedure('public.has_grant(text,integer)') is null or to_regprocedure('public._all_locs()') is null
     or to_regprocedure('public._acct_all()') is null or to_regprocedure('public._item_cost_eff88()') is null or to_regprocedure('public._rcs88()') is null
     or to_regprocedure('public.profit_truth112(date,date,integer)') is null or to_regprocedure('public.drawer_report(date,date)') is null
     or to_regprocedure('public.items_with_cost()') is null or to_regprocedure('public.item_cost_status88()') is null or to_regprocedure('public.fa_register(date)') is null
     or to_regprocedure('public._client_lock(uuid)') is null or to_regprocedure('public.org_unit_save(bigint,bigint,text,text,text,text,text,text,date,date,text,text,jsonb,jsonb,uuid)') is null
     then miss := miss || ' functions'; end if;
  if miss <> '' then raise exception 'phase123 needs the base schema and phases up to 122 pasted first (docs/PASTE_ORDER.md); missing:%', miss; end if;
end $g$;

-- ---------- 1. who holds which role over which unit ----------
create table if not exists public.user_org_scopes (
  id bigserial primary key,
  user_id uuid not null references public.profiles(id),
  org_unit_id bigint not null references public.org_units(id),
  role_code text not null references public.roles(code),
  status text not null default 'active' check (status in ('active', 'revoked')),
  note text check (note is null or length(note) <= 300),
  client_id uuid unique,
  granted_by uuid, granted_at timestamptz not null default now(),
  revoked_by uuid, revoked_at timestamptz, revoked_reason text check (revoked_reason is null or length(revoked_reason) <= 300)
);
create unique index if not exists user_org_scopes_active123 on public.user_org_scopes (user_id, org_unit_id, role_code) where status = 'active';
create index if not exists user_org_scopes_unit123 on public.user_org_scopes (org_unit_id);

drop trigger if exists uos123_no_delete on public.user_org_scopes;
create trigger uos123_no_delete before delete on public.user_org_scopes for each row execute function public.no_hard_delete();
drop trigger if exists audit_uos123 on public.user_org_scopes;
create trigger audit_uos123 after insert or update on public.user_org_scopes for each row execute function public.log_change('id');

alter table public.user_org_scopes enable row level security;
drop policy if exists uos123_read on public.user_org_scopes;
create policy uos123_read on public.user_org_scopes for select to authenticated using (user_id = auth.uid() or public.is_owner() or public.has_grant('org_manage'));
revoke all on public.user_org_scopes from public, anon, authenticated;
grant select on public.user_org_scopes to authenticated;
revoke all on sequence public.user_org_scopes_id_seq from public, anon, authenticated;

-- ---------- 2. helpers ----------
-- the switch (rule org_scope_on). Anything unreadable counts as OFF.
create or replace function public._org_on123() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select (coalesce(r.value, r.default_value) #>> '{}')::boolean from public.rules r where r.key = 'org_scope_on'), false);   -- same value as rule_on('org_scope_on'), one lookup instead of three nested calls
$$;

-- the unit and all its parents
create or replace function public._org_anc123(p_unit bigint) returns setof bigint
language sql stable security definer set search_path = public as $$
  with recursive up(id, parent_id) as (
    select o.id, o.parent_id from public.org_units o where o.id = p_unit
    union
    select p.id, p.parent_id from public.org_units p join up on p.id = up.parent_id)
  select id from up;
$$;

-- the business a unit belongs to (the unit itself when it is one); null above the business level or for null
create or replace function public._business_of_unit123(p_unit bigint) returns bigint
language sql stable security definer set search_path = public as $$
  select o.id from public.org_units o where o.kind = 'business' and o.id in (select public._org_anc123(p_unit)) limit 1;
$$;

-- live scope rows of a user: active AND the user still holds that role
create or replace function public._scopes123(p_user uuid) returns table (org_unit_id bigint, role_code text)
language sql stable security definer set search_path = public as $$
  select s.org_unit_id, s.role_code from public.user_org_scopes s
   where s.user_id = p_user and s.status = 'active'
     and exists (select 1 from public.user_roles ur where ur.user_id = s.user_id and ur.role_code = s.role_code);
$$;

-- the businesses a user belongs to: through a scope that covers the whole business (the business or a parent of it), a scope below it, or an assigned location
create or replace function public._user_biz123(p_user uuid) returns setof bigint
language sql stable security definer set search_path = public as $$
  select b.id from public.org_units b
   where b.kind = 'business' and (
     exists (select 1 from public._scopes123(p_user) sc where sc.org_unit_id in (select public._org_anc123(b.id)))
     or exists (select 1 from public._scopes123(p_user) sc where public._business_of_unit123(sc.org_unit_id) = b.id)
     or exists (select 1 from public.user_locations ul join public.locations l on l.id = ul.location_id
                 where ul.user_id = p_user and l.org_unit_id is not null and public._business_of_unit123(l.org_unit_id) = b.id));
$$;

-- the caller's businesses (the owner: every business)
create or replace function public._my_biz123() returns setof bigint
language sql stable security definer set search_path = public as $$
  select b.id from public.org_units b where b.kind = 'business' and public.is_active() and public.is_owner()
  union
  select x from public._user_biz123(auth.uid()) x where public.is_active();
$$;

-- business of a location (internal, unguarded)
create or replace function public._business_of_loc123(p_loc int) returns bigint
language sql stable security definer set search_path = public as $$
  select public._business_of_unit123(l.org_unit_id) from public.locations l where l.id = p_loc;
$$;

-- does the location belong to one of the caller's businesses? (owner: always; unmapped location: only the owner)
create or replace function public._biz_ok123(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or (
    p_loc is not null and public._business_of_loc123(p_loc) is not null and public._business_of_loc123(p_loc) in (select public._my_biz123())));
$$;

-- does a live 'management' scope of the caller cover the location?
create or replace function public._mgmt_covers123(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public._scopes123(auth.uid()) sc join public.locations l on l.id = p_loc
                  where sc.role_code = 'management' and l.org_unit_id is not null and sc.org_unit_id in (select public._org_anc123(l.org_unit_id)));
$$;

-- row filter used by the restrictive policies: true while the switch is OFF; ON: owner, or a location of one of the caller's businesses (NULL location: owner only)
create or replace function public._loc_vis123(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select not public._org_on123() or (public.is_active() and (public.is_owner() or public._biz_ok123(p_loc)));
$$;

-- does the user share a business with the caller? (owner: everybody)
create or replace function public._shares_biz123(p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or p_user = auth.uid() or exists (select 1 from public._user_biz123(p_user) x where x in (select public._my_biz123())));
$$;

-- PUBLIC: may the caller act over this unit (and everything below it)? owner = yes; others need a live scope row on the unit or a parent of it (p_role null = any role).
-- Independent of the switch (it only says what the scope table grants).
create or replace function public.can_scope(p_unit bigint, p_role text default null) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and p_unit is not null and (public.is_owner() or exists (
    select 1 from public._scopes123(auth.uid()) sc where (p_role is null or sc.role_code = p_role) and sc.org_unit_id in (select public._org_anc123(p_unit))));
$$;

-- PUBLIC: the business of a location. Null when unmapped, or (switch ON, not owner) when the location is not one of the caller's.
create or replace function public.business_of_location(p_loc int) returns bigint
language sql stable security definer set search_path = public as $$
  select case when not public.is_active() then null
              when public._org_on123() and not public._biz_ok123(p_loc) then null
              else public._business_of_loc123(p_loc) end;
$$;

-- ---------- 3. the access primitives (OFF branch = the old text, verbatim) ----------
create or replace function public.can_loc(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (case when not coalesce((select (coalesce(r.value, r.default_value) #>> '{}')::boolean from public.rules r where r.key = 'org_scope_on'), false) then (   -- the switch read inline (can_loc runs once per row in the policies)
    -- OFF: exactly the rule of phase7
    public.is_owner()
    or exists (select 1 from public.user_roles where user_id = auth.uid() and role_code = 'management')
    or exists (select 1 from public.user_locations where user_id = auth.uid() and location_id = p_loc)
    or exists (select 1 from public.emergency_requests e where e.requested_by = auth.uid() and e.grant_code = 'loc_access' and e.status = 'approved' and e.valid_until > now()
               and e.location_id = p_loc))
  else (
    -- ON (scope123): owner = all; the rest only inside their own business(es); no location (null) = owner only
    public.is_owner()
    or (p_loc is not null and (
         exists (select 1 from public.user_locations where user_id = auth.uid() and location_id = p_loc)
         or public._mgmt_covers123(p_loc)
         or (public._biz_ok123(p_loc) and exists (select 1 from public.emergency_requests e where e.requested_by = auth.uid() and e.grant_code = 'loc_access' and e.status = 'approved'
                                                  and e.valid_until > now() and e.location_id = p_loc))))
  ) end);
$$;

create or replace function public._all_locs() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (case when not public._org_on123()
    then (public.is_owner() or exists (select 1 from public.user_roles where user_id = auth.uid() and role_code = 'management'))   -- OFF: phase10
    else public.is_owner() end);                                                                                                  -- ON (scope123): owner only
$$;

create or replace function public._acct_all() returns boolean language sql stable security definer set search_path = public as $$
  select case when not public._org_on123()
    then (public.can_loc(null) or (public.is_active() and public.has_grant('accounts_manage')))   -- OFF: phase40
    else (public.is_active() and public.is_owner()) end;                                          -- ON (scope123): owner only
$$;

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
    -- ON (scope123): with a location it must be one of the caller's businesses; a personal grant without a location = the caller's businesses, not the database
    (p_loc is null or public._biz_ok123(p_loc)) and (
      public.can_grant(p_code)
      or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = p_code
                 and (g.valid_until is null or g.valid_until > now()) and (g.location_id is null or g.location_id = p_loc))
      or exists (select 1 from public.emergency_requests e join public.grant_defs d on d.grant_code = e.grant_code and d.window_type = 'window'
                 where e.requested_by = auth.uid() and e.grant_code = p_code and e.status = 'approved' and e.valid_until > now()
                 and (p_loc is null or e.location_id is null or e.location_id = p_loc)))
  ) end));
$$;

create or replace function public._notif_ok(p_user uuid, p_aud text, p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (
    case when p_user is not null then p_user = auth.uid()
         else (p_aud = 'all'
               or public.is_owner()
               or (p_aud = 'manager' and (p_loc is not null or not public._org_on123()) and exists (select 1 from public.user_roles r where r.user_id = auth.uid()   -- scope123: no place = owner only
                     and r.role_code in ('management', 'showroom_manager', 'cash_controller', 'factory_incharge', 'purchasing', 'hr')))) end
    and (p_loc is null or p_user is not null or public.can_loc(p_loc)));
$$;

-- ---------- 4. readers that returned several places' data without can_loc ----------
create or replace function public.staff_directory() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.is_active()
    then coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'staff_id', p.staff_id, 'full_name', p.full_name) order by p.full_name)
                   from public.profiles p where p.status = 'active' and (not public._org_on123() or public._shares_biz123(p.id))), '[]'::jsonb)   -- scope123: people of my businesses
    else '[]'::jsonb end;
$$;

create or replace function public.customer_dues() returns table (id uuid, name text, mobile text, type text, credit_limit numeric, balance numeric, oldest date)
language sql stable security definer set search_path = public as $$
  with s as (
    select x.id, x.customer_id, x.sale_date, x.sold_at,
           x.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = x.id and not p.voided), 0) rem
    from public.sales x where x.status = 'done' and x.customer_id is not null and (not (select public._org_on123()) or public.can_loc(x.location_id))),
  cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) cr from s where s.rem > 0),
  c as (select z.customer_id, sum(z.a) coll from (
          select customer_id, amount a from public.sale_payments where kind = 'collection' and not voided and customer_id is not null and (not (select public._org_on123()) or public.can_loc(location_id))
          union all select customer_id, credit_amount from public.sale_returns where status = 'done' and customer_id is not null and credit_amount > 0 and (not (select public._org_on123()) or public.can_loc(location_id))) z group by 1),
  t as (select customer_id, sum(rem) rem from s group by 1)
  select cu.id, cu.name, public._cust_pii103('mobile', cu.mobile) /* bos105 */, cu.type, cu.credit_limit, t.rem - coalesce(c.coll, 0),
         (select min(k.sale_date) from cum k where k.customer_id = cu.id and k.cr > coalesce(c.coll, 0))
  from public.customers cu join t on t.customer_id = cu.id left join c on c.customer_id = cu.id
  where (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) and t.rem - coalesce(c.coll, 0) > 0
  order by 6 desc;
$$;

create or replace function public.customer_ledger(p_customer uuid) returns table (at timestamptz, kind text, ref text, location_id int, debit numeric, credit numeric, balance numeric, note text, pid bigint)
language sql stable security definer set search_path = public as $$
  with e as (
    select s.sold_at at, 'sale'::text kind, '#' || s.receipt ref, s.location_id, s.total debit, 0::numeric credit, case when s.sale_type = 'wholesale' then 'wholesale' end note, null::bigint pid
      from public.sales s where s.customer_id = p_customer and s.status = 'done' and (not (select public._org_on123()) or public.can_loc(s.location_id))
    union all
    select p.paid_at, case when p.kind = 'collection' then 'collection' else 'paid' end, coalesce(p.wallet, p.mode), p.location_id, 0, p.amount, p.note, p.id
      from public.sale_payments p where p.customer_id = p_customer and not p.voided and (not (select public._org_on123()) or public.can_loc(p.location_id))
    union all
    select r.created_at, 'sale_return', '#' || s.receipt, r.location_id, 0, r.credit_amount, r.reason_code, null::bigint
      from public.sale_returns r join public.sales s on s.id = r.sale_id where r.customer_id = p_customer and r.status = 'done' and r.credit_amount > 0 and (not (select public._org_on123()) or public.can_loc(r.location_id)))
  select e.at, e.kind, e.ref, e.location_id, e.debit, e.credit, sum(e.debit - e.credit) over (order by e.at, (e.debit > 0) desc, e.kind), e.note, e.pid
  from e where (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) order by e.at, (e.debit > 0) desc, e.kind;
$$;

create or replace function public.fa_register(p_as_of date default null) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare as_ date := coalesce(p_as_of, public._acct_today());
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  return jsonb_build_object('on', public.rule_on('fixed_assets_on'), 'as_of', as_, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name', a.name, 'category', a.category, 'location_id', a.location_id, 'acquired_on', a.acquired_on, 'cost', a.cost, 'salvage', a.salvage,
      'life_months', a.life_months, 'method', a.method, 'depr_from', a.depr_from, 'status', a.status, 'disposed_on', a.disposed_on,
      'accumulated', coalesce(p.s, 0), 'book_value', a.cost - coalesce(p.s, 0), 'months_posted', coalesce(p.n, 0), 'last_month', p.mx) order by a.code)
    from public.fa_assets a left join lateral (select sum(amount) s, count(*) n, max(month) mx from public.fa_depr_posts x where x.asset_id = a.id and x.month <= as_) p on true
    where (not public._org_on123() or public.can_loc(a.location_id))), '[]'::jsonb));   -- scope123: the caller's places (no place = owner only)
end $$;

create or replace function public.fa_schedule(p_id uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a public.fa_assets; rows_ jsonb;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  select * into a from public.fa_assets where id = p_id;
  if not found then raise exception 'not found'; end if;
  if public._org_on123() and not public.can_loc(a.location_id) then raise exception 'not found'; end if;   -- scope123: same answer as a missing id
  select coalesce(jsonb_agg(jsonb_build_object('k', k, 'month', m, 'amount', amt, 'accumulated', acc, 'book_value', a.cost - acc, 'posted', p.id is not null,
      'skipped_after_disposal', a.status = 'disposed' and m > public._a53_mon(a.disposed_on)) order by k), '[]'::jsonb) into rows_ from (
    select g k, (a.depr_from + ((g - 1) || ' months')::interval)::date m, public._a53_fa_amt(a.cost, a.salvage, a.life_months, g) amt,
      sum(public._a53_fa_amt(a.cost, a.salvage, a.life_months, g)) over (order by g) acc from generate_series(1, a.life_months) g) s
    left join public.fa_depr_posts p on p.asset_id = a.id and p.month = s.m;
  return jsonb_build_object('asset_id', a.id, 'code', a.code, 'name', a.name, 'cost', a.cost, 'salvage', a.salvage, 'life_months', a.life_months, 'method', a.method, 'status', a.status, 'rows', rows_);
end $$;

create or replace function public.year_close_list() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if public._org_on123() and not public._acct_all() then raise exception 'not allowed'; end if;   -- scope123: year closes are company-level records (owner only until the per-entity books of Stage C2)
  return jsonb_build_object('on', public.rule_on('year_close_on'), 'period_closed_until', public.rule_txt('period_closed_until'), 'owner', public.is_owner(),
    'rows', coalesce((select jsonb_agg(to_jsonb(y) - 'client_id' order by y.fiscal_to desc, y.id desc) from public.year_closes y), '[]'::jsonb));
end $$;

-- item cost seen from the caller's own places only (non-owner, switch ON). Same logic as _item_cost_eff88 with the stock filtered by can_loc;
-- only items the caller's places hold appear (items are still ONE global master until Stage C2).
create or replace function public._item_cost_scoped123() returns table (item_id uuid, cost_price numeric, src text)
language sql stable security definer set search_path = public as $$
  with m as materialized (select public._rcs88() as m),
  lg as (
    select b.item_id as iid,
           coalesce(sum(b.qty * b.avg_cost) filter (where b.qty > 0 and coalesce(b.avg_cost, 0) > 0) / nullif(sum(b.qty) filter (where b.qty > 0 and coalesce(b.avg_cost, 0) > 0), 0),
                    (select l.unit_cost from public.stock_ledger l where l.item_id = b.item_id and public.can_loc(l.location_id) and coalesce(l.unit_cost, 0) > 0 and l.qty_delta > 0 order by l.id desc limit 1)) as c
    from public.stock_balance b where public.can_loc(b.location_id) group by b.item_id),
  ic as (select x.item_id as iid, x.cost_price as c from public.item_costs x where x.cost_price is not null)
  select z.iid, z.cp, z.s from (
    select lg.iid as iid,
           case m.m when 'item_costs' then ic.c when 'ledger_avg' then lg.c else coalesce(lg.c, ic.c) end as cp,
           case m.m when 'item_costs' then 'item_costs' when 'ledger_avg' then 'ledger' else (case when lg.c is not null then 'ledger' else 'item_costs' end) end as s
    from lg left join ic on ic.iid = lg.iid cross join m) z
  where z.cp is not null;
$$;

create or replace function public.items_with_cost() returns table (item_id uuid, cost_price numeric)
language sql stable security definer set search_path = public as $$
  select c.item_id, c.cost_price from (
    select e.item_id, e.cost_price from public._item_cost_eff88() e where (select not public._org_on123() or public.is_owner())   -- bos88: the effective cost of the ONE source (report_cost_source); an item with no known cost has NO row = unknown, never 0
    union all
    select s.item_id, s.cost_price from public._item_cost_scoped123() s where (select public._org_on123() and not public.is_owner())   -- scope123: my own places only
  ) c
  -- a location-scoped personal view_cost grant counts too (the list is company wide, so any location grant is enough; role grants and the owner as before)
  where public.is_active() and (public.is_owner() or public.can_do('ITEM_COST', 'view') or public.has_grant('view_cost')
    or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'view_cost' and (g.valid_until is null or g.valid_until > now())));
$$;

create or replace function public.item_cost_status88() returns table (item_id uuid, code text, cost_price numeric, source text, cost_missing boolean)
language sql stable security definer set search_path = public as $$
  select i.id, i.code, e.cost_price, coalesce(e.src, 'none'), e.cost_price is null
  from public.items i left join (
    select x.item_id, x.cost_price, x.src from public._item_cost_eff88() x where (select not public._org_on123() or public.is_owner())
    union all
    select y.item_id, y.cost_price, y.src from public._item_cost_scoped123() y where (select public._org_on123() and not public.is_owner())) e on e.item_id = i.id
  where i.is_active and i.count_in_business and public.is_active()
    and (public.is_owner() or public.can_do('ITEM_COST', 'view') or public.has_grant('view_cost')
         or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'view_cost' and (g.valid_until is null or g.valid_until > now())))
  order by i.code;
$$;

create or replace function public.drawer_report(p_from date default null, p_to date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 29); t date := coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date); res jsonb;
begin
  if not (public.is_owner() or public.has_grant('view_reports')) then raise exception 'not allowed'; end if;
  if t < f then raise exception 'bad_range'; end if;
  if t - f > 366 then raise exception 'range_too_long'; end if;
  with e as (
    select d.*, (d.at at time zone 'Asia/Dhaka')::date as day from public.drawer_events d where (d.at at time zone 'Asia/Dhaka')::date between f and t
      and (not public._org_on123() or public.can_loc(d.location_id)))   -- scope123: the caller's places only
  select jsonb_build_object(
    'from', f, 'to', t,
    'totals', jsonb_build_object(
      'auto_open', (select count(*) from e where event = 'auto_open'), 'no_sale_open', (select count(*) from e where event = 'no_sale_open'),
      'test_open', (select count(*) from e where event = 'test_open'), 'failed', (select count(*) from e where event = 'failed')),
    'by_user', coalesce((select jsonb_agg(x order by (x ->> 'no_sale_open')::int desc, x ->> 'staff') from (
        select jsonb_build_object('user_id', by_user, 'staff', coalesce(max(by_staff), ''), 'name', coalesce(max(p.full_name), ''),
                 'no_sale_open', count(*) filter (where event = 'no_sale_open'), 'auto_open', count(*) filter (where event = 'auto_open'),
                 'failed', count(*) filter (where event = 'failed'), 'last_no_sale', max(e.at) filter (where event = 'no_sale_open')) as x
        from e left join public.profiles p on p.id = e.by_user group by by_user) q), '[]'::jsonb),
    'by_day', coalesce((select jsonb_agg(jsonb_build_object('day', day, 'no_sale_open', n) order by day) from (
        select day, count(*) as n from e where event = 'no_sale_open' group by day) q), '[]'::jsonb),
    'recent_no_sale', coalesce((select jsonb_agg(jsonb_build_object('at', at, 'staff', by_staff, 'location_id', location_id, 'reason', reason) order by at desc) from (
        select * from e where event = 'no_sale_open' order by at desc limit 50) q), '[]'::jsonb))
  into res;
  return res;
end $$;

create or replace function public.profit_truth112(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; rws jsonb; co jsonb; un numeric := 0; unc numeric := 0; wu int := 0; np numeric := 0; npf numeric := 0; prov boolean; notes jsonb := '[]'::jsonb;
begin   -- bos112
  if not (public.biz_ok() and public.biz_cost_ok() and public._acct_view()) then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  if public._org_on123() and p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;   -- scope123
  locs := array(select l.id from public.locations l where (p_loc is null or l.id = p_loc) and public.can_loc(l.id));
  select coalesce(jsonb_agg(t), '[]'::jsonb) into rws from public._pnl_truth112(p_from, p_to, locs) t;
  select coalesce(sum((t ->> 'profit')::numeric), 0), coalesce(sum((t ->> 'profit_if_uncosted_free')::numeric), 0), coalesce(sum((t ->> 'uncosted_rev')::numeric), 0),
         coalesce(sum((t ->> 'wastage_unknown_cost')::int), 0), coalesce(sum((t ->> 'unallocated')::numeric), 0)
    into np, npf, unc, wu, un from jsonb_array_elements(rws) t;
  -- the unallocated row has no profit_if_uncosted_free: it costs the same in both figures
  npf := npf + coalesce((select sum((t ->> 'profit')::numeric) from jsonb_array_elements(rws) t where t ->> 'row_type' = 'unallocated'), 0);
  prov := unc > 0.004 or un > 0.004 or wu > 0;
  if unc > 0.004 then notes := notes || jsonb_build_array('uncosted_revenue'); end if;
  if un > 0.004 then notes := notes || jsonb_build_array('unallocated_shared_costs'); end if;
  if wu > 0 then notes := notes || jsonb_build_array('wastage_cost_unknown'); end if;
  co := jsonb_build_object(
    'net_sales', coalesce((select sum((t ->> 'net_sales')::numeric) from jsonb_array_elements(rws) t), 0),
    'costed_rev', coalesce((select sum((t ->> 'costed_rev')::numeric) from jsonb_array_elements(rws) t), 0),
    'cogs', coalesce((select sum((t ->> 'cogs')::numeric) from jsonb_array_elements(rws) t), 0),
    'expenses', coalesce((select sum((t ->> 'expenses')::numeric) from jsonb_array_elements(rws) t where t ->> 'row_type' = 'truth'), 0),
    'salary', coalesce((select sum((t ->> 'salary')::numeric) from jsonb_array_elements(rws) t), 0),
    'fixed', coalesce((select sum((t ->> 'fixed')::numeric) from jsonb_array_elements(rws) t), 0),
    'wastage', coalesce((select sum((t ->> 'wastage')::numeric) from jsonb_array_elements(rws) t), 0),
    'card_fees', coalesce((select sum((t ->> 'card_fees')::numeric) from jsonb_array_elements(rws) t), 0),
    'overheads_attributed', coalesce((select sum((t ->> 'overheads_attributed')::numeric) from jsonb_array_elements(rws) t), 0),
    'unallocated', un, 'uncosted_rev', unc);
  return jsonb_build_object('from', p_from, 'to', p_to, 'location_id', p_loc, 'mode', coalesce(public.rule_txt('profit_truth_mode'), 'off'),
    'company', co || jsonb_build_object('net_profit', round(np, 2), 'net_profit_if_uncosted_free', round(npf, 2)),
    'rows', rws, 'provisional', prov, 'incomplete', notes);
end $$;

-- ---------- 5. a stock transfer between two businesses is refused while the switch is ON ----------
create or replace function public._xfer_biz123() returns trigger
language plpgsql security definer set search_path = public as $$
declare bf bigint; bt bigint;
begin
  if public._org_on123() then
    bf := public._business_of_loc123(new.from_location_id); bt := public._business_of_loc123(new.to_location_id);
    if bf is null or bt is null or bf <> bt then raise exception 'cross_business_transfer'; end if;
  end if;
  return new;
end $$;
drop trigger if exists stock_transfers_biz123 on public.stock_transfers;
create trigger stock_transfers_biz123 before insert on public.stock_transfers for each row execute function public._xfer_biz123();

-- ---------- 6. restrictive read policies (AND-ed with the old ones; true while the switch is OFF) ----------
do $pol$
declare r record;
begin
  for r in select * from (values
      ('locations', 'id', 'select'), ('location_settings', 'location_id', 'select'), ('att_site_geo', 'location_id', 'select'), ('blind_count_cfg', 'location_id', 'select'),
      ('doc_template_choice', 'location_id', 'select'), ('form_rollout', 'location_id', 'select'), ('holidays', 'location_id', 'select'), ('path_switch', 'location_id', 'select'),
      ('report_brand_map', 'location_id', 'select'), ('sales_channels', 'location_id', 'select'), ('shifts', 'location_id', 'select'),
      ('invoice_templates', 'location_id', 'all'), ('print_profiles', 'location_id', 'all'),
      ('location_setup_steps', 'location_id', 'select'), ('paper_books', 'location_id', 'select'), ('print_notes', 'location_id', 'select'), ('settings_sheets', 'location_id', 'select'),
      ('budget_log', 'location_id', 'select'), ('payment_intents', 'location_id', 'select'), ('payroll_bonus_events', 'location_id', 'select')
    ) v(t, col, cmd)
  loop
    continue when to_regclass('public.' || r.t) is null;
    execute format('drop policy if exists %I on public.%I', r.t || '_scope123', r.t);
    execute format('create policy %I on public.%I as restrictive for %s to authenticated using (public._loc_vis123(%I)) %s',
      r.t || '_scope123', r.t, r.cmd, r.col, case when r.cmd = 'all' then format('with check (public._loc_vis123(%I))', r.col) else '' end);
  end loop;
end $pol$;
-- emergency requests: own rows always; others' rows only for the owner or when the place belongs to one of the caller's businesses (a request with no place: owner only)
drop policy if exists emergency_requests_scope123 on public.emergency_requests;
create policy emergency_requests_scope123 on public.emergency_requests as restrictive for select to authenticated
  using (not public._org_on123() or requested_by = auth.uid() or public.is_owner() or (location_id is not null and public._biz_ok123(location_id)));

-- deciding an emergency request: the approver must belong to the request's business (a role grant 'emergency_decide' is global); the answer is the same as for a missing id
create or replace function public.decide_emergency(p_id bigint, p_approve boolean, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.emergency_requests; sid text; mins numeric;
begin
  if not public.can_grant('emergency_decide') then raise exception 'not allowed'; end if;
  select * into r from public.emergency_requests where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if public._org_on123() and not public.is_owner() and (r.location_id is null or not public._biz_ok123(r.location_id)) then raise exception 'not found'; end if;   -- scope123
  if r.status <> 'pending' then raise exception 'already decided'; end if;
  if r.created_at < now() - interval '1 day' then update public.emergency_requests set status = 'expired' where id = p_id; return; end if;      -- a day-old request is stale: ask again
  if r.requested_by = auth.uid() and not (public.is_owner() and public.rule_on('owner_self_approve')) then raise exception 'own_request'; end if;
  if not p_approve and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  mins := coalesce(public.rule_num('em_minutes'), 30);
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.emergency_requests set status = case when p_approve then 'approved' else 'rejected' end, decided_by = auth.uid(), decided_staff = sid, decided_at = now(),
    decision_note = left(nullif(btrim(p_note), ''), 300), valid_until = case when p_approve then now() + make_interval(mins => mins::int) end where id = p_id;
end $$;

-- ---------- 7. managing the scope rows (owner) ----------
create or replace function public.org_scope_grant(p_user uuid, p_unit bigint, p_role text default 'management', p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u public.org_units; s public.user_org_scopes; nid bigint;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is null then raise exception 'client_id_needed'; end if;
  select * into s from public.user_org_scopes where client_id = p_client;
  if found then return jsonb_build_object('dup', true, 'id', s.id); end if;
  if p_user is null or not exists (select 1 from public.profiles where id = p_user) then raise exception 'bad_user'; end if;
  select * into u from public.org_units where id = p_unit;
  if not found then raise exception 'bad_unit'; end if;
  if u.kind = 'group' then raise exception 'group_scope_is_owner_only'; end if;
  if u.status = 'inactive' then raise exception 'unit_inactive'; end if;
  if p_role is null or p_role = 'owner' or not exists (select 1 from public.roles where code = p_role and active) then raise exception 'bad_role'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'bad_note'; end if;
  select * into s from public.user_org_scopes where user_id = p_user and org_unit_id = p_unit and role_code = p_role and status = 'active';
  if found then return jsonb_build_object('dup', true, 'id', s.id); end if;
  insert into public.user_org_scopes (user_id, org_unit_id, role_code, note, client_id, granted_by) values (p_user, p_unit, p_role, p_note, p_client, auth.uid()) returning id into nid;
  return jsonb_build_object('dup', false, 'id', nid, 'live', exists (select 1 from public.user_roles ur where ur.user_id = p_user and ur.role_code = p_role));
end $$;

create or replace function public.org_scope_revoke(p_id bigint, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.user_org_scopes;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  if p_reason is not null and length(p_reason) > 300 then raise exception 'bad_reason'; end if;
  select * into s from public.user_org_scopes where id = p_id for update;
  if not found then raise exception 'scope_not_found'; end if;
  if s.status = 'revoked' then return jsonb_build_object('dup', true, 'id', s.id); end if;
  update public.user_org_scopes set status = 'revoked', revoked_by = auth.uid(), revoked_at = now(), revoked_reason = p_reason where id = p_id;
  return jsonb_build_object('dup', false, 'id', p_id);
end $$;

create or replace function public.org_scope_list(p_user uuid default null) returns table (id bigint, user_id uuid, staff_id text, full_name text, org_unit_id bigint, unit_code text, role_code text,
  status text, live boolean, note text, granted_at timestamptz, revoked_at timestamptz, revoked_reason text)
language plpgsql stable security definer set search_path = public as $$
declare mgr boolean := public.is_active() and (public.is_owner() or public.has_grant('org_manage'));
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query
    select s.id, s.user_id, pr.staff_id, pr.full_name, s.org_unit_id, u.code, s.role_code, s.status,
           s.status = 'active' and exists (select 1 from public.user_roles ur where ur.user_id = s.user_id and ur.role_code = s.role_code),
           s.note, s.granted_at, s.revoked_at, s.revoked_reason
      from public.user_org_scopes s join public.profiles pr on pr.id = s.user_id join public.org_units u on u.id = s.org_unit_id
     where (mgr or s.user_id = auth.uid()) and (p_user is null or s.user_id = p_user)
     order by s.id;
end $$;

-- before switching the rule ON: what would change for people (owner only). Read-only.
create or replace function public.org_scope_preflight() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare t text; cfg jsonb := '{}'::jsonb; n bigint;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  foreach t in array array['location_settings', 'att_site_geo', 'blind_count_cfg', 'doc_template_choice', 'form_rollout', 'holidays', 'path_switch', 'report_brand_map', 'sales_channels', 'shifts',
                           'invoice_templates', 'print_profiles', 'location_setup_steps', 'paper_books', 'print_notes', 'settings_sheets'] loop
    if to_regclass('public.' || t) is not null then
      execute format('select count(*) from public.%I where location_id is null', t) into n;
      if n > 0 then cfg := cfg || jsonb_build_object(t, n); end if;
    end if;
  end loop;
  return jsonb_build_object(
    'switch_on', public._org_on123(),
    'businesses', (select count(*) from public.org_units where kind = 'business' and status <> 'inactive'),
    'unmapped_locations', coalesce((select jsonb_agg(l.code order by l.id) from public.locations l where l.org_unit_id is null), '[]'::jsonb),
    'locations_not_under_a_business', coalesce((select jsonb_agg(l.code order by l.id) from public.locations l where l.org_unit_id is not null and public._business_of_unit123(l.org_unit_id) is null), '[]'::jsonb),
    'management_users_without_scope', coalesce((select jsonb_agg(p.staff_id order by p.staff_id) from public.user_roles ur join public.profiles p on p.id = ur.user_id and p.status = 'active'
        where ur.role_code = 'management' and not exists (select 1 from public._scopes123(ur.user_id) sc where sc.role_code = 'management')), '[]'::jsonb),
    'active_users_with_no_business', coalesce((select jsonb_agg(p.staff_id order by p.staff_id) from public.profiles p
        where p.status = 'active' and not exists (select 1 from public.user_roles ur where ur.user_id = p.id and ur.role_code = 'owner')
          and not exists (select 1 from public._user_biz123(p.id))), '[]'::jsonb),
    'personal_grants_without_location', (select count(*) from public.user_grants where location_id is null and (valid_until is null or valid_until > now())),
    'config_rows_without_location', cfg);
end $$;

-- ---------- 8. first paste only: today's management users keep working in the sweets business when the switch is turned ON ----------
do $seed$
declare bz bigint; done_ boolean;
begin
  select id, coalesce((attrs -> 'seed123' ->> 'management_backfilled')::boolean, false) into bz, done_ from public.org_units where code = 'SWEETS';
  if bz is not null and not done_ then
    insert into public.user_org_scopes (user_id, org_unit_id, role_code, note)
      select ur.user_id, bz, 'management', 'phase123 backfill: existing management user = management of the sweets business'
        from public.user_roles ur join public.profiles p on p.id = ur.user_id
       where ur.role_code = 'management'
         and not exists (select 1 from public.user_org_scopes s where s.user_id = ur.user_id and s.org_unit_id = bz and s.role_code = 'management');
    update public.org_units set attrs = attrs || jsonb_build_object('seed123', jsonb_build_object('management_backfilled', true)) where id = bz;
  end if;
end $seed$;

-- ---------- 9. privileges ----------
revoke all on function public._org_anc123(bigint), public._business_of_unit123(bigint), public._scopes123(uuid), public._user_biz123(uuid), public._my_biz123(), public._business_of_loc123(int),
  public._mgmt_covers123(int), public._shares_biz123(uuid), public._item_cost_scoped123(), public._xfer_biz123() from public, anon, authenticated;
revoke all on function public._org_on123(), public._biz_ok123(int), public._loc_vis123(int) from public, anon;
grant execute on function public._org_on123(), public._biz_ok123(int), public._loc_vis123(int) to authenticated;                       -- used inside the policies
revoke all on function public.can_scope(bigint, text), public.business_of_location(int), public.org_scope_grant(uuid, bigint, text, text, uuid), public.org_scope_revoke(bigint, text),
  public.org_scope_list(uuid), public.org_scope_preflight() from public, anon;
grant execute on function public.can_scope(bigint, text), public.business_of_location(int), public.org_scope_grant(uuid, bigint, text, text, uuid), public.org_scope_revoke(bigint, text),
  public.org_scope_list(uuid), public.org_scope_preflight() to authenticated;

-- ---------- 10. advisor row for the switch (text only; the value stays the owner's) ----------
update public.setup_rec_defs81 set phase = '123',
  reason_bn = 'এখনই চালু করবেন না: আগে org_scope_preflight() দেখুন (কোন লোক/লোকেশন বাদ পড়বে) এবং নতুন ব্যবসার লোকেদের জন্য user_org_scopes দিন। বন্ধ থাকুক।',
  reason_mix = 'এখনই on করবেন না: আগে org_scope_preflight() দেখুন (কোন লোক/location বাদ পড়বে) এবং নতুন business-এর লোকেদের জন্য user_org_scopes দিন। off থাকুক।',
  reason_en = 'Do not switch on yet: first read org_scope_preflight() (which people / places would drop out) and give the staff of each new business a user_org_scopes row. Leave it off until then.'
 where code = 'org_scope_on' and phase = '122';

update public.rules set
  label_bn = 'ব্যবসা অনুযায়ী আলাদা ডেটা-সীমা (চালু করলে এক ব্যবসার লোক অন্য ব্যবসার ডেটা দেখবে না)',
  label_mix = 'Business অনুযায়ী আলাদা data-scope (on করলে এক business-এর লোক অন্য business-এর data দেখবে না)',
  label_en = 'Separate data scope per business (when on, staff of one business cannot see another business''s data)',
  hint_en = 'Off = everything works as before. On = management is limited to its own business, role/personal grants without a place stop at the business border, the listed reports and settings tables are filtered. Read org_scope_preflight() first. Owner sees all.'
 where key = 'org_scope_on' and hint_en like '%Does nothing yet%';

commit;

-- ---------------------------------------------------------------- phase124.sql
-- ============================================================
-- Phase 124 (marker ie124) - IMPORT-EXPORT, a basic module for ONE business of the group (template import_export). ADDITIVE, idempotent.
-- Needs phase122 (org_units, org_unit_scope, org_tree). Canonical order: after phase123. Changes NO existing function, policy or rule.
-- Scope: every table carries org_unit_id (the import_export BUSINESS unit). A user reaches a business only through a location they are assigned to
--   (user_locations + can_loc + org_unit_scope(location).business_id) AND the grant impexp_view / impexp_manage on that location. The owner reaches all.
--   This does not read the rule org_scope_on: isolation by business is built in, so it already holds when that switch is turned ON later.
-- Tables (RLS on, NO browser read or write at all: everything goes through the functions below)
--   ie_currencies       per business: code (3 letters), name, decimals 0..4, active. The base currency is the legal entity's base_currency (never hard-coded).
--   ie_fx_rates         per business: currency, rate = base units per 1 foreign unit, valid_from, entered_by. APPEND-ONLY history.
--   ie_shipments        business register: direction import|export, reference, counterparty, status draft|booked|in_transit|received|closed|cancelled,
--                       currency, amount (document currency), rate used, amount_base = round(amount * rate, 2), dates, notes,
--                       landed-cost lines typed by the user in the BASE currency (freight, insurance, duty_tax, other_cost). Nothing is invented or estimated.
--   ie_shipment_events  append-only log of create / edit / status change.
-- Functions (browser): ie_businesses124, ie_currencies_list, ie_fx_rates_list, currency_save, fx_rate_set, shipment_save, shipment_set_status,
--   shipments_list, shipment_events_list, shipment_cost_summary, shipments_by_currency. Writes need rule impexp_on (default OFF) + grant impexp_manage.
-- NOT built (stated in business_templates.modules): letters of credit, customs automation, bank/payment tracking, accounting (GL) posting, stock link, multi-line shipments.
-- Rollback: leave impexp_on OFF. To remove: drop the functions and the four ie_ tables (nothing else refers to them).
-- ============================================================
begin;

do $g$ begin
  if to_regclass('public.org_units') is null or to_regprocedure('public.org_unit_scope(integer)') is null then
    raise exception 'phase124 needs phase122 (organization layer) first';
  end if;
end $g$;

-- ---------- 1. grants, rule, template row ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
select 'impexp_view', 'impexp', 90, 'আমদানি-রপ্তানি: দেখা', 'Import-Export: দেখা', 'Import-Export: view', 'once'
where not exists (select 1 from public.grant_defs where grant_code = 'impexp_view');
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
select 'impexp_manage', 'impexp', 91, 'আমদানি-রপ্তানি: শিপমেন্ট, মুদ্রা ও রেট লেখা', 'Import-Export: shipment, currency ও rate লেখা', 'Import-Export: write shipments, currencies and rates', 'once'
where not exists (select 1 from public.grant_defs where grant_code = 'impexp_manage');

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('impexp_on', 'impexp', 'switch', 'false', null, null, null, null,
  'আমদানি-রপ্তানি মডিউল চালু', 'Import-Export module চালু', 'Import-Export module on',
  'বন্ধ থাকলে শিপমেন্ট, মুদ্রা ও রেট লেখা যায় না (দেখা যায়)। হিসাবে (GL) কিছু পোস্ট হয় না।',
  'off থাকলে shipment, currency ও rate লেখা যায় না (দেখা যায়)। হিসাবে (GL) কিছু post হয় না।',
  'When off, shipments, currencies and rates cannot be written (reading works). Nothing is posted to the GL.', 991)
on conflict (key) do nothing;

-- template row: honest state. Built and tested = the register, currencies, rates, landed cost, report. Not built = the rest.
insert into public.business_templates (code, name_bn, name_en, modules, status, sort) values
 ('import_export', 'আমদানি-রপ্তানি', 'Import-Export',
  '[{"code":"shipments","state":"built"},{"code":"currencies","state":"built"},{"code":"fx_rates","state":"built"},{"code":"landed_cost","state":"built","note":"amounts typed by the user, nothing estimated"},{"code":"report_by_currency","state":"built"},{"code":"letter_of_credit","state":"not_built"},{"code":"customs_automation","state":"not_built"},{"code":"accounting_posting","state":"not_built","note":"nothing is posted to the GL yet (pending)"},{"code":"stock_link","state":"not_built"},{"code":"bank_payments","state":"not_built"}]'::jsonb,
  'needs_setup', 70)
on conflict (code) do update set modules = excluded.modules, name_bn = excluded.name_bn, name_en = excluded.name_en,
  status = case when public.business_templates.status in ('not_implemented', 'planned', 'needs_setup') then excluded.status else public.business_templates.status end
  where public.business_templates.status in ('not_implemented', 'planned', 'needs_setup');

-- ---------- 2. tables ----------
create table if not exists public.ie_currencies (
  id bigserial primary key,
  org_unit_id bigint not null references public.org_units(id),
  code text not null check (code ~ '^[A-Z]{3}$'),
  name_bn text not null check (length(btrim(name_bn)) between 1 and 80),
  name_en text check (name_en is null or length(name_en) <= 80),
  decimals int not null default 2 check (decimals between 0 and 4),
  active boolean not null default true,
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(),
  updated_by uuid, updated_at timestamptz not null default now(),
  unique (org_unit_id, code)
);
create table if not exists public.ie_fx_rates (
  id bigserial primary key,
  org_unit_id bigint not null references public.org_units(id),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  rate numeric(20,8) not null check (rate > 0 and rate <= 1000000000000),
  valid_from date not null,
  note text check (note is null or length(note) <= 300),
  client_id uuid unique,
  entered_by uuid, entered_at timestamptz not null default now()
);
create index if not exists ie_fx_rates124_look on public.ie_fx_rates (org_unit_id, currency, valid_from desc, id desc);
create table if not exists public.ie_shipments (
  id bigserial primary key,
  org_unit_id bigint not null references public.org_units(id),
  direction text not null check (direction in ('import', 'export')),
  reference text not null check (length(btrim(reference)) between 1 and 60),
  counterparty text check (counterparty is null or length(counterparty) <= 200),
  status text not null default 'draft' check (status in ('draft', 'booked', 'in_transit', 'received', 'closed', 'cancelled')),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  amount numeric(20,2) not null check (amount >= 0 and amount <= 1000000000000),
  rate numeric(20,8) not null check (rate > 0 and rate <= 1000000000000),
  amount_base numeric(20,2) not null check (amount_base >= 0 and amount_base <= 1000000000000),
  ship_date date not null,
  eta_date date,
  received_date date,
  notes text check (notes is null or length(notes) <= 1000),
  freight numeric(20,2) not null default 0 check (freight >= 0 and freight <= 1000000000000),
  insurance numeric(20,2) not null default 0 check (insurance >= 0 and insurance <= 1000000000000),
  duty_tax numeric(20,2) not null default 0 check (duty_tax >= 0 and duty_tax <= 1000000000000),
  other_cost numeric(20,2) not null default 0 check (other_cost >= 0 and other_cost <= 1000000000000),
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(),
  updated_by uuid, updated_at timestamptz not null default now(),
  unique (org_unit_id, reference)
);
create index if not exists ie_shipments124_org on public.ie_shipments (org_unit_id, status, ship_date desc);
create table if not exists public.ie_shipment_events (
  id bigserial primary key,
  shipment_id bigint not null references public.ie_shipments(id),
  org_unit_id bigint not null references public.org_units(id),
  event text not null check (event in ('create', 'edit', 'status')),
  from_status text, to_status text,
  note text check (note is null or length(note) <= 500),
  client_id uuid unique,
  by_user uuid, at timestamptz not null default now()
);
create index if not exists ie_events124_ship on public.ie_shipment_events (shipment_id, id);

create or replace function public._ie_ro124() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end $$;
drop trigger if exists ie_fx_ro124 on public.ie_fx_rates;
create trigger ie_fx_ro124 before update or delete on public.ie_fx_rates for each row execute function public._ie_ro124();
drop trigger if exists ie_ev_ro124 on public.ie_shipment_events;
create trigger ie_ev_ro124 before update or delete on public.ie_shipment_events for each row execute function public._ie_ro124();
drop trigger if exists ie_cur_nd124 on public.ie_currencies;
create trigger ie_cur_nd124 before delete on public.ie_currencies for each row execute function public.no_hard_delete();
drop trigger if exists ie_shp_nd124 on public.ie_shipments;
create trigger ie_shp_nd124 before delete on public.ie_shipments for each row execute function public.no_hard_delete();
drop trigger if exists audit_ie_cur124 on public.ie_currencies;
create trigger audit_ie_cur124 after insert or update on public.ie_currencies for each row execute function public.log_change('id');
drop trigger if exists audit_ie_fx124 on public.ie_fx_rates;
create trigger audit_ie_fx124 after insert on public.ie_fx_rates for each row execute function public.log_change('id');
drop trigger if exists audit_ie_shp124 on public.ie_shipments;
create trigger audit_ie_shp124 after insert or update on public.ie_shipments for each row execute function public.log_change('id');
drop trigger if exists audit_ie_ev124 on public.ie_shipment_events;
create trigger audit_ie_ev124 after insert on public.ie_shipment_events for each row execute function public.log_change('id');

-- RLS on, no policy = no direct browser access at all (functions only)
alter table public.ie_currencies enable row level security;
alter table public.ie_fx_rates enable row level security;
alter table public.ie_shipments enable row level security;
alter table public.ie_shipment_events enable row level security;
revoke all on public.ie_currencies, public.ie_fx_rates, public.ie_shipments, public.ie_shipment_events from public, anon, authenticated;
revoke all on sequence public.ie_currencies_id_seq, public.ie_fx_rates_id_seq, public.ie_shipments_id_seq, public.ie_shipment_events_id_seq from public, anon, authenticated;

-- ---------- 3. helpers (closed to the browser) ----------
-- may the caller act on this import_export business? p_need = 'impexp_view' (manage also counts) or 'impexp_manage'. Owner: every business.
create or replace function public._ie_access124(p_org bigint, p_need text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and p_org is not null
    and exists (select 1 from public.org_tree() t where t.id = p_org and t.kind = 'business' and t.template_code = 'import_export')
    and (public.is_owner() or exists (
      select 1 from public.user_locations ul
       where ul.user_id = auth.uid() and public.can_loc(ul.location_id)
         and (public.org_unit_scope(ul.location_id)->>'business_id')::bigint = p_org
         and (public.has_grant('impexp_manage', ul.location_id) or (p_need = 'impexp_view' and public.has_grant('impexp_view', ul.location_id)))));
$$;
-- base currency of the business = base currency of its legal entity (walk up the tree)
create or replace function public._ie_base124(p_org bigint) returns text
language sql stable security definer set search_path = public as $$
  with recursive t as materialized (select x.id, x.parent_id, x.kind, x.base_currency from public.org_tree() x),
  up as (select t.* from t where t.id = p_org union all select t.* from t join up on t.id = up.parent_id)
  select (select up.base_currency from up where up.kind = 'legal_entity' limit 1);
$$;
create or replace function public._ie_write124(p_org bigint) returns void
language plpgsql stable security definer set search_path = public as $$
declare st text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public._ie_access124(p_org, 'impexp_manage') then raise exception 'not allowed'; end if;
  if not public.rule_on('impexp_on') then raise exception 'impexp_off'; end if;
  select t.status into st from public.org_tree() t where t.id = p_org;
  if st is distinct from 'active' then raise exception 'business_not_active'; end if;
end $$;
create or replace function public._ie_num124(p_x numeric, p_nullable boolean default false) returns numeric
language plpgsql immutable set search_path = public as $$
begin
  if p_x is null then if p_nullable then return null; end if; raise exception 'bad_amount'; end if;
  if p_x <> p_x or abs(p_x) > 1000000000000 then raise exception 'bad_amount'; end if;
  return p_x;
end $$;
-- the rate in force for a currency on a date (latest valid_from <= date, then latest entry); null when none
create or replace function public._ie_rate_on124(p_org bigint, p_cur text, p_date date) returns numeric
language sql stable security definer set search_path = public as $$
  select r.rate from public.ie_fx_rates r where r.org_unit_id = p_org and r.currency = p_cur and r.valid_from <= p_date order by r.valid_from desc, r.id desc limit 1;
$$;

-- ---------- 4. functions ----------
-- the import_export businesses the caller may see (for the screen's picker)
create or replace function public.ie_businesses124() returns table (id bigint, code text, name_bn text, name_en text, status text, base_currency text, can_manage boolean, impexp_on boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query select t.id, t.code, t.name_bn, t.name_en, t.status, public._ie_base124(t.id), public._ie_access124(t.id, 'impexp_manage'), public.rule_on('impexp_on')
    from public.org_tree() t where t.kind = 'business' and t.template_code = 'import_export' and public._ie_access124(t.id, 'impexp_view') order by t.code;
end $$;

create or replace function public.ie_currencies_list(p_org bigint) returns table (id bigint, code text, name_bn text, name_en text, decimals int, active boolean, is_base boolean)
language plpgsql stable security definer set search_path = public as $$
declare b text;
begin
  if not public._ie_access124(p_org, 'impexp_view') then raise exception 'not allowed'; end if;
  b := public._ie_base124(p_org);
  return query select c.id, c.code, c.name_bn, c.name_en, c.decimals, c.active, (c.code = b) from public.ie_currencies c where c.org_unit_id = p_org order by c.code;
end $$;

create or replace function public.currency_save(p_org bigint, p_code text, p_name_bn text, p_name_en text default null, p_decimals int default 2, p_active boolean default true, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c text := upper(btrim(coalesce(p_code, ''))); o public.ie_currencies; me uuid := auth.uid(); nid bigint;
begin
  perform public._ie_write124(p_org);
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into o from public.ie_currencies where client_id = p_client;
    if found then
      if o.created_by is distinct from me then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', o.id, 'code', o.code);
    end if;
  end if;
  if c !~ '^[A-Z]{3}$' then raise exception 'bad_currency'; end if;
  if c = public._ie_base124(p_org) then raise exception 'is_base_currency'; end if;
  if p_name_bn is null or length(btrim(p_name_bn)) not between 1 and 80 then raise exception 'bad_name'; end if;
  if p_name_en is not null and length(p_name_en) > 80 then raise exception 'bad_name'; end if;
  if p_decimals is null or p_decimals not between 0 and 4 then raise exception 'bad_decimals'; end if;
  if p_active is null then raise exception 'bad_value'; end if;
  select * into o from public.ie_currencies where org_unit_id = p_org and code = c for update;
  if found then
    update public.ie_currencies set name_bn = btrim(p_name_bn), name_en = nullif(btrim(coalesce(p_name_en, '')), ''), decimals = p_decimals, active = p_active, updated_by = me, updated_at = now() where id = o.id;
    return jsonb_build_object('dup', false, 'id', o.id, 'code', c);
  end if;
  insert into public.ie_currencies (org_unit_id, code, name_bn, name_en, decimals, active, client_id, created_by, updated_by)
  values (p_org, c, btrim(p_name_bn), nullif(btrim(coalesce(p_name_en, '')), ''), p_decimals, p_active, p_client, me, me) returning id into nid;
  return jsonb_build_object('dup', false, 'id', nid, 'code', c);
end $$;

create or replace function public.fx_rate_set(p_org bigint, p_currency text, p_rate numeric, p_valid_from date default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare today date := (now() at time zone 'Asia/Dhaka')::date; c text := upper(btrim(coalesce(p_currency, ''))); vf date; o public.ie_fx_rates; nid bigint; me uuid := auth.uid();
begin
  perform public._ie_write124(p_org);
  perform public._client_lock(p_client);
  if p_client is null then raise exception 'client_id_needed'; end if;
  select * into o from public.ie_fx_rates where client_id = p_client;
  if found then
    if o.entered_by is distinct from me then raise exception 'client_id_taken'; end if;
    return jsonb_build_object('dup', true, 'id', o.id);
  end if;
  if c !~ '^[A-Z]{3}$' then raise exception 'bad_currency'; end if;
  if not exists (select 1 from public.ie_currencies where org_unit_id = p_org and code = c and active) then raise exception 'currency_not_listed'; end if;
  p_rate := public._ie_num124(p_rate);
  if p_rate <= 0 then raise exception 'bad_rate'; end if;
  if round(p_rate, 8) <> p_rate then raise exception 'bad_rate'; end if;
  vf := coalesce(p_valid_from, today);
  if vf not between date '2000-01-01' and today + 30 then raise exception 'bad_date'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'bad_note'; end if;
  perform public.lock_check(vf);
  insert into public.ie_fx_rates (org_unit_id, currency, rate, valid_from, note, client_id, entered_by) values (p_org, c, p_rate, vf, nullif(btrim(coalesce(p_note, '')), ''), p_client, me) returning id into nid;
  return jsonb_build_object('dup', false, 'id', nid);
end $$;

create or replace function public.ie_fx_rates_list(p_org bigint, p_currency text default null, p_limit int default 100) returns table (id bigint, currency text, rate numeric, valid_from date, note text, entered_by uuid, entered_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._ie_access124(p_org, 'impexp_view') then raise exception 'not allowed'; end if;
  return query select r.id, r.currency, r.rate, r.valid_from, r.note, r.entered_by, r.entered_at from public.ie_fx_rates r
    where r.org_unit_id = p_org and (p_currency is null or r.currency = upper(p_currency)) order by r.valid_from desc, r.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500);
end $$;

-- create (p_id null, needs p_client) or edit a shipment. direction and reference never change. amount / currency / rate only while draft or booked.
-- rate: given by the user, else the rate in force on ship_date; base currency = 1. No rate = refused (nothing is guessed).
create or replace function public.shipment_save(p_org bigint, p_id bigint, p_direction text, p_reference text, p_counterparty text, p_currency text, p_amount numeric, p_rate numeric,
  p_ship_date date, p_eta_date date default null, p_notes text default null, p_freight numeric default 0, p_insurance numeric default 0, p_duty_tax numeric default 0, p_other numeric default 0,
  p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  today date := (now() at time zone 'Asia/Dhaka')::date; me uuid := auth.uid(); s public.ie_shipments; cur text := upper(btrim(coalesce(p_currency, ''))); ref text := btrim(coalesce(p_reference, ''));
  base text; rt numeric; amt numeric; ab numeric; nid bigint; fr numeric; ins numeric; dty numeric; oth numeric;
begin
  perform public._ie_write124(p_org);
  perform public._client_lock(p_client);
  if p_id is null then
    if p_client is null then raise exception 'client_id_needed'; end if;
    select * into s from public.ie_shipments where client_id = p_client;
    if found then
      if s.created_by is distinct from me then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', s.id, 'amount_base', s.amount_base);
    end if;
  end if;
  base := public._ie_base124(p_org);
  if base is null then raise exception 'no_base_currency'; end if;
  if cur !~ '^[A-Z]{3}$' then raise exception 'bad_currency'; end if;
  if cur <> base and not exists (select 1 from public.ie_currencies where org_unit_id = p_org and code = cur and active) then raise exception 'currency_not_listed'; end if;
  amt := public._ie_num124(p_amount);
  if amt < 0 then raise exception 'bad_amount'; end if;
  amt := round(amt, 2);                                   -- the document amount is kept to 2 places; the base amount is round(amount * rate, 2)
  fr := round(public._ie_num124(coalesce(p_freight, 0)), 2); ins := round(public._ie_num124(coalesce(p_insurance, 0)), 2); dty := round(public._ie_num124(coalesce(p_duty_tax, 0)), 2); oth := round(public._ie_num124(coalesce(p_other, 0)), 2);
  if least(fr, ins, dty, oth) < 0 then raise exception 'bad_amount'; end if;
  if p_ship_date is null or p_ship_date not between date '2000-01-01' and today + 3660 then raise exception 'bad_date'; end if;
  if p_eta_date is not null and p_eta_date not between date '2000-01-01' and today + 3660 then raise exception 'bad_date'; end if;
  if p_notes is not null and length(p_notes) > 1000 then raise exception 'bad_notes'; end if;
  if p_counterparty is not null and length(p_counterparty) > 200 then raise exception 'bad_counterparty'; end if;
  if p_rate is not null then
    rt := public._ie_num124(p_rate);
    if rt <= 0 or round(rt, 8) <> rt then raise exception 'bad_rate'; end if;
  elsif cur = base then rt := 1;
  else rt := public._ie_rate_on124(p_org, cur, p_ship_date);
    if rt is null then raise exception 'no_rate'; end if;
  end if;
  if cur = base and rt <> 1 then raise exception 'bad_rate'; end if;
  ab := round(amt * rt, 2);
  if ab > 1000000000000 then raise exception 'bad_amount'; end if;
  perform public.lock_check(p_ship_date);

  if p_id is null then
    if p_direction is null or p_direction not in ('import', 'export') then raise exception 'bad_direction'; end if;
    if length(ref) not between 1 and 60 then raise exception 'bad_reference'; end if;
    if exists (select 1 from public.ie_shipments where org_unit_id = p_org and reference = ref) then raise exception 'reference_taken'; end if;
    insert into public.ie_shipments (org_unit_id, direction, reference, counterparty, status, currency, amount, rate, amount_base, ship_date, eta_date, notes, freight, insurance, duty_tax, other_cost, client_id, created_by, updated_by)
    values (p_org, p_direction, ref, nullif(btrim(coalesce(p_counterparty, '')), ''), 'draft', cur, amt, rt, ab, p_ship_date, p_eta_date, nullif(btrim(coalesce(p_notes, '')), ''), fr, ins, dty, oth, p_client, me, me) returning id into nid;
    insert into public.ie_shipment_events (shipment_id, org_unit_id, event, to_status, by_user) values (nid, p_org, 'create', 'draft', me);
    return jsonb_build_object('dup', false, 'id', nid, 'amount_base', ab, 'landed_base', ab + fr + ins + dty + oth);
  end if;

  select * into s from public.ie_shipments where id = p_id and org_unit_id = p_org for update;
  if not found then raise exception 'shipment_not_found'; end if;
  if s.status in ('closed', 'cancelled') then raise exception 'shipment_final'; end if;
  if p_direction is not null and p_direction <> s.direction then raise exception 'direction_fixed'; end if;
  if p_reference is not null and ref <> s.reference then raise exception 'reference_fixed'; end if;
  if s.status not in ('draft', 'booked') and (cur <> s.currency or amt <> s.amount or rt <> s.rate) then raise exception 'amount_locked'; end if;
  perform public.lock_check(s.ship_date);
  update public.ie_shipments set counterparty = nullif(btrim(coalesce(p_counterparty, '')), ''), currency = cur, amount = amt, rate = rt, amount_base = ab, ship_date = p_ship_date, eta_date = p_eta_date,
    notes = nullif(btrim(coalesce(p_notes, '')), ''), freight = fr, insurance = ins, duty_tax = dty, other_cost = oth, updated_by = me, updated_at = now() where id = s.id;
  insert into public.ie_shipment_events (shipment_id, org_unit_id, event, from_status, to_status, by_user) values (s.id, p_org, 'edit', s.status, s.status, me);
  return jsonb_build_object('dup', false, 'id', s.id, 'amount_base', ab, 'landed_base', ab + fr + ins + dty + oth);
end $$;

create or replace function public.shipment_set_status(p_org bigint, p_id bigint, p_status text, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare today date := (now() at time zone 'Asia/Dhaka')::date; me uuid := auth.uid(); s public.ie_shipments; e public.ie_shipment_events; ok boolean;
begin
  perform public._ie_write124(p_org);
  perform public._client_lock(p_client);
  if p_note is not null and length(p_note) > 500 then raise exception 'bad_note'; end if;
  if p_client is not null then
    select * into e from public.ie_shipment_events where client_id = p_client;
    if found then
      if e.by_user is distinct from me then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', e.shipment_id, 'status', e.to_status);
    end if;
  end if;
  if p_status is null or p_status not in ('draft', 'booked', 'in_transit', 'received', 'closed', 'cancelled') then raise exception 'bad_status'; end if;
  select * into s from public.ie_shipments where id = p_id and org_unit_id = p_org for update;
  if not found then raise exception 'shipment_not_found'; end if;
  if s.status = p_status then return jsonb_build_object('dup', true, 'id', s.id, 'status', s.status); end if;
  ok := (s.status = 'draft' and p_status in ('booked', 'cancelled'))
     or (s.status = 'booked' and p_status in ('in_transit', 'received', 'cancelled'))
     or (s.status = 'in_transit' and p_status in ('received', 'cancelled'))
     or (s.status = 'received' and p_status = 'closed');
  if not ok then raise exception 'bad_transition'; end if;
  perform public.lock_check(s.ship_date);
  update public.ie_shipments set status = p_status, received_date = case when p_status = 'received' and received_date is null then today else received_date end, updated_by = me, updated_at = now() where id = s.id;
  insert into public.ie_shipment_events (shipment_id, org_unit_id, event, from_status, to_status, note, client_id, by_user)
  values (s.id, p_org, 'status', s.status, p_status, nullif(btrim(coalesce(p_note, '')), ''), p_client, me);
  return jsonb_build_object('dup', false, 'id', s.id, 'status', p_status);
end $$;

create or replace function public.shipments_list(p_org bigint, p_status text default null, p_direction text default null, p_limit int default 200) returns table (
  id bigint, direction text, reference text, counterparty text, status text, currency text, amount numeric, rate numeric, amount_base numeric, ship_date date, eta_date date, received_date date,
  notes text, freight numeric, insurance numeric, duty_tax numeric, other_cost numeric, landed_base numeric, base_currency text)
language plpgsql stable security definer set search_path = public as $$
declare b text;
begin
  if not public._ie_access124(p_org, 'impexp_view') then raise exception 'not allowed'; end if;
  b := public._ie_base124(p_org);
  return query select s.id, s.direction, s.reference, s.counterparty, s.status, s.currency, s.amount, s.rate, s.amount_base, s.ship_date, s.eta_date, s.received_date, s.notes,
      s.freight, s.insurance, s.duty_tax, s.other_cost, s.amount_base + s.freight + s.insurance + s.duty_tax + s.other_cost, b
    from public.ie_shipments s where s.org_unit_id = p_org and (p_status is null or s.status = p_status) and (p_direction is null or s.direction = p_direction)
    order by s.ship_date desc, s.id desc limit least(greatest(coalesce(p_limit, 200), 1), 1000);
end $$;

create or replace function public.shipment_events_list(p_org bigint, p_id bigint) returns table (id bigint, event text, from_status text, to_status text, note text, by_user uuid, at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._ie_access124(p_org, 'impexp_view') then raise exception 'not allowed'; end if;
  return query select e.id, e.event, e.from_status, e.to_status, e.note, e.by_user, e.at from public.ie_shipment_events e where e.org_unit_id = p_org and e.shipment_id = p_id order by e.id;
end $$;

-- landed cost = goods in base currency + the lines the user entered (nothing else is added)
create or replace function public.shipment_cost_summary(p_org bigint, p_id bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s public.ie_shipments;
begin
  if not public._ie_access124(p_org, 'impexp_view') then raise exception 'not allowed'; end if;
  select * into s from public.ie_shipments where id = p_id and org_unit_id = p_org;
  if not found then raise exception 'shipment_not_found'; end if;
  return jsonb_build_object('id', s.id, 'reference', s.reference, 'base_currency', public._ie_base124(p_org), 'currency', s.currency, 'amount', s.amount, 'rate', s.rate,
    'goods_base', s.amount_base, 'freight', s.freight, 'insurance', s.insurance, 'duty_tax', s.duty_tax, 'other_cost', s.other_cost,
    'lines_total', s.freight + s.insurance + s.duty_tax + s.other_cost, 'landed_base', s.amount_base + s.freight + s.insurance + s.duty_tax + s.other_cost);
end $$;

-- per currency and direction (cancelled shipments are left out); optional ship_date range
create or replace function public.shipments_by_currency(p_org bigint, p_from date default null, p_to date default null) returns table (
  currency text, direction text, shipments bigint, amount numeric, amount_base numeric, landed_base numeric, base_currency text)
language plpgsql stable security definer set search_path = public as $$
declare b text;
begin
  if not public._ie_access124(p_org, 'impexp_view') then raise exception 'not allowed'; end if;
  b := public._ie_base124(p_org);
  return query select s.currency, s.direction, count(*), sum(s.amount), sum(s.amount_base), sum(s.amount_base + s.freight + s.insurance + s.duty_tax + s.other_cost), b
    from public.ie_shipments s where s.org_unit_id = p_org and s.status <> 'cancelled' and (p_from is null or s.ship_date >= p_from) and (p_to is null or s.ship_date <= p_to)
    group by s.currency, s.direction order by s.currency, s.direction;
end $$;

-- ---------- 5. privileges ----------
revoke all on function public._ie_ro124(), public._ie_access124(bigint, text), public._ie_base124(bigint), public._ie_write124(bigint), public._ie_num124(numeric, boolean), public._ie_rate_on124(bigint, text, date) from public, anon, authenticated;
revoke all on function public.ie_businesses124(), public.ie_currencies_list(bigint), public.currency_save(bigint, text, text, text, int, boolean, uuid),
  public.fx_rate_set(bigint, text, numeric, date, text, uuid), public.ie_fx_rates_list(bigint, text, int),
  public.shipment_save(bigint, bigint, text, text, text, text, numeric, numeric, date, date, text, numeric, numeric, numeric, numeric, uuid),
  public.shipment_set_status(bigint, bigint, text, text, uuid), public.shipments_list(bigint, text, text, int), public.shipment_events_list(bigint, bigint),
  public.shipment_cost_summary(bigint, bigint), public.shipments_by_currency(bigint, date, date) from public, anon;
grant execute on function public.ie_businesses124(), public.ie_currencies_list(bigint), public.currency_save(bigint, text, text, text, int, boolean, uuid),
  public.fx_rate_set(bigint, text, numeric, date, text, uuid), public.ie_fx_rates_list(bigint, text, int),
  public.shipment_save(bigint, bigint, text, text, text, text, numeric, numeric, date, date, text, numeric, numeric, numeric, numeric, uuid),
  public.shipment_set_status(bigint, bigint, text, text, uuid), public.shipments_list(bigint, text, text, int), public.shipment_events_list(bigint, bigint),
  public.shipment_cost_summary(bigint, bigint), public.shipments_by_currency(bigint, date, date) to authenticated;

commit;

-- ---------------------------------------------------------------- phase125.sql
-- ============================================================
-- Phase 125 (marker var125) - VARIANT ITEM MODEL, per-business items, price lists by channel (ADDITIVE ONLY, default behaviour unchanged).
-- Plan: docs/GROUP_ERP_STAGE_A.md sections 13-14 (fashion / cloth, large catalogues). Canonical order: after phase124 (docs/PASTE_ORDER.md).
-- Needs phase122 (org_units). Does NOT need phase123 / 124. Paste twice = no change, no error.
--   items (existing table): + org_unit_id (nullable, the BUSINESS that owns the item), + style_id, + variant_key, + variant_opts.
--       Existing items are filled with the sweets business (fill-null-only). A BEFORE INSERT trigger fills a new item's org_unit_id (caller's only business, else SWEETS),
--       so every old item-create flow keeps working. items.code stays GLOBALLY unique (old constraint untouched); a NEW unique index (org_unit_id, code) is added:
--       with one business it can never fire, with several businesses it is the constraint that will remain after the global one is relaxed (plan in docs/regs/variants125.md).
--   option_sets / option_values   configurable lists per business (size alpha / numeric / free / kids age band, colour, fabric ...). NOTHING hardcoded: the owner creates them.
--   item_styles / style_axes      a style (parent) and the ordered option sets (axes, max 4) that make its variants.
--   variants_generate(style, pick, dry)   style x option values -> one items row per combination (a variant IS an item, so stock_ledger / stock_balance / POS / purchase
--                                 work unchanged, stock per variant per location). Idempotent (unique style_id + variant_key), barcode per variant (internal EAN-13), dry-run first.
--   price_lists / price_list_items   channel retail | wholesale | online, scoped per business, date validity. items.sell_price / wholesale_price are NEVER overwritten.
--   price_for125(item, channel, date, qty)   read: list price when a valid list row exists, else the item's own price (no existing flow calls it).
--   Rule variants_on (switch, default OFF). OFF: every write function refuses ('variants_off'), items_read stays "any active user" exactly as before. ON: items_read also hides
--       other businesses' items (only if the policy is still the original one: a policy already changed by Stage C1 is left to C1).
--   Grant variants_manage. RLS on every new table, no browser write, audit triggers, no hard delete, anon has nothing.
-- Rollback: leave variants_on OFF. To remove: drop the functions, the new tables, the items trigger/columns/indexes (nothing else refers to them).
-- ============================================================
begin;

do $g$
declare miss text := '';
begin
  if to_regclass('public.items') is null or to_regclass('public.org_units') is null or to_regclass('public.locations') is null or to_regclass('public.user_locations') is null
     or to_regclass('public.grant_defs') is null or to_regclass('public.rules') is null or to_regclass('public.stock_balance') is null or to_regclass('public.item_types') is null then miss := miss || ' tables'; end if;
  if to_regprocedure('public.is_owner()') is null or to_regprocedure('public.is_active()') is null or to_regprocedure('public.has_grant(text,integer)') is null
     or to_regprocedure('public.log_change()') is null or to_regprocedure('public.no_hard_delete()') is null or to_regprocedure('public._client_lock(uuid)') is null
     or to_regprocedure('public.rule_on(text)') is null or to_regprocedure('public.can_loc(integer)') is null then miss := miss || ' functions'; end if;
  if miss <> '' then raise exception 'phase125 needs the base schema and phases up to 122 pasted first (docs/PASTE_ORDER.md); missing:%', miss; end if;
end $g$;

-- ---------- 1. scope helpers (business of a unit; which businesses may the caller see) ----------
-- walk up from any unit to its business ancestor (null when the unit is not under a business)
create or replace function public._biz_of125(p_unit bigint) returns bigint
language sql stable security definer set search_path = public as $$
  with recursive up(id, parent_id, kind) as (
    select o.id, o.parent_id, o.kind from public.org_units o where o.id = p_unit
    union all
    select p.id, p.parent_id, p.kind from public.org_units p join up on up.parent_id = p.id)
  select id from up where kind = 'business' limit 1;
$$;

-- the businesses the caller may work in: owner = every business; others = the businesses of the locations explicitly assigned in user_locations
-- (the 'management' role bypass of can_loc is deliberately NOT used)
create or replace function public._my_biz125() returns setof bigint
language sql stable security definer set search_path = public as $$
  select o.id from public.org_units o where o.kind = 'business' and public.is_active() and public.is_owner()
  union
  select public._biz_of125(l.org_unit_id) from public.locations l join public.user_locations ul on ul.location_id = l.id
   where public.is_active() and ul.user_id = auth.uid() and l.org_unit_id is not null and public._biz_of125(l.org_unit_id) is not null;
$$;

create or replace function public._biz_vis125(p_biz bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and p_biz is not null and (public.is_owner() or p_biz in (select public._my_biz125()));
$$;

-- may the caller change variant / price data of this business? owner, or grant variants_manage AND the business is one of theirs
create or replace function public._biz_mgr125(p_biz bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or (public.has_grant('variants_manage') and public._biz_vis125(p_biz)));
$$;

-- the sweets business = the business of the lowest-id mapped location (phase122 maps all existing locations to it); fallback: code SWEETS
create or replace function public._biz_default125() returns bigint
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select public._biz_of125(l.org_unit_id) from public.locations l where l.org_unit_id is not null order by l.id limit 1),
    (select o.id from public.org_units o where o.code = 'SWEETS' and o.kind = 'business'));
$$;

-- common write gate: switch ON, business exists and is active, caller may manage it
create or replace function public._var_gate125(p_biz bigint) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('variants_on') then raise exception 'variants_off'; end if;
  if p_biz is null or not exists (select 1 from public.org_units o where o.id = p_biz and o.kind = 'business' and o.status <> 'inactive') then raise exception 'bad_business'; end if;
  if not public._biz_mgr125(p_biz) then raise exception 'not allowed'; end if;
end $$;

-- ---------- 2. items: per-business scope + style / variant link ----------
alter table public.items add column if not exists org_unit_id bigint references public.org_units(id);
alter table public.items add column if not exists style_id bigint;
alter table public.items add column if not exists variant_key text;
alter table public.items add column if not exists variant_opts jsonb;
create index if not exists items_org_unit125 on public.items (org_unit_id);

-- ---------- 3. new tables ----------
create table if not exists public.option_sets (
  id bigserial primary key,
  org_unit_id bigint not null references public.org_units(id),
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9_]{0,23}$'),
  name_bn text not null check (length(btrim(name_bn)) between 1 and 80),
  name_en text check (name_en is null or length(name_en) <= 80),
  kind text not null default 'other' check (kind in ('size', 'colour', 'fabric', 'age', 'other')),
  product_group text check (product_group is null or length(product_group) <= 80),     -- the item category this list is meant for (informational; null = any)
  active boolean not null default true,
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now(),
  unique (org_unit_id, code)
);
create table if not exists public.option_values (
  id bigserial primary key,
  set_id bigint not null references public.option_sets(id),
  org_unit_id bigint not null references public.org_units(id),
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9._]{0,15}$'),
  label_bn text not null check (length(btrim(label_bn)) between 1 and 60),
  label_en text check (label_en is null or length(label_en) <= 60),
  sort int not null default 0 check (sort between 0 and 100000),
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now(),
  unique (set_id, code)
);
create table if not exists public.item_styles (
  id bigserial primary key,
  org_unit_id bigint not null references public.org_units(id),
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9_]{0,23}$'),
  name_bn text not null check (length(btrim(name_bn)) between 1 and 120),
  name_en text check (name_en is null or length(name_en) <= 120),
  product_group text check (product_group is null or length(product_group) <= 80),
  sub_category text check (sub_category is null or length(sub_category) <= 80),
  unit text not null default 'pc' check (length(unit) between 1 and 20),
  item_type text not null default 'resale' references public.item_types(code),
  base_price numeric(12,2) check (base_price is null or (base_price >= 0 and base_price <= 1000000000)),
  status text not null default 'active' check (status in ('active', 'inactive')),
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now(),
  unique (org_unit_id, code)
);
create table if not exists public.style_axes (
  style_id bigint not null references public.item_styles(id),
  axis_no int not null check (axis_no between 1 and 4),
  set_id bigint not null references public.option_sets(id),
  primary key (style_id, axis_no),
  unique (style_id, set_id)
);
create table if not exists public.price_lists (
  id bigserial primary key,
  org_unit_id bigint not null references public.org_units(id),
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9_-]{0,23}$'),
  name_bn text not null check (length(btrim(name_bn)) between 1 and 80),
  name_en text check (name_en is null or length(name_en) <= 80),
  channel text not null check (channel in ('retail', 'wholesale', 'online')),
  valid_from date not null default date '2000-01-01',
  valid_to date,
  active boolean not null default true,
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now(),
  unique (org_unit_id, code),
  check (valid_to is null or valid_to >= valid_from)
);
create table if not exists public.price_list_items (
  id bigserial primary key,
  price_list_id bigint not null references public.price_lists(id),
  org_unit_id bigint not null references public.org_units(id),
  item_id uuid not null references public.items(id),
  price numeric(12,2) not null check (price >= 0 and price <= 1000000000),
  min_qty numeric(12,3) not null default 1 check (min_qty > 0 and min_qty <= 1000000000),
  valid_from date not null default date '2000-01-01',
  valid_to date,
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now(),
  check (valid_to is null or valid_to >= valid_from),
  unique (price_list_id, item_id, min_qty, valid_from)
);
create index if not exists price_list_items_item125 on public.price_list_items (item_id);

do $f$ begin
  if not exists (select 1 from pg_constraint where conname = 'items_style_fk125') then
    alter table public.items add constraint items_style_fk125 foreign key (style_id) references public.item_styles(id);
  end if;
end $f$;
create index if not exists items_style125 on public.items (style_id) where style_id is not null;
create unique index if not exists items_style_variant_uq125 on public.items (style_id, variant_key) where style_id is not null;
-- per-business item code uniqueness (the global items.code unique constraint is untouched; see docs/regs/variants125.md for the plan to relax it)
create unique index if not exists items_org_code_uq125 on public.items (org_unit_id, code);

-- audit + never hard delete
do $a$
declare t text;
begin
  foreach t in array array['option_sets', 'option_values', 'item_styles', 'price_lists', 'price_list_items'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_nodel125', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel125', t);
    execute format('drop trigger if exists %I on public.%I', 'audit_' || t || '125', t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.log_change(%L)', 'audit_' || t || '125', t, 'id');
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read125', t);
    execute format('create policy %I on public.%I for select to authenticated using (public._biz_vis125(org_unit_id))', t || '_read125', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('revoke all on sequence public.%I from public, anon, authenticated', t || '_id_seq');
  end loop;
end $a$;
-- style_axes: no id column; scoped through its style. Axes of a style WITHOUT variants may be replaced (so no no-delete trigger here); once variants exist they are locked.
alter table public.style_axes enable row level security;
drop policy if exists style_axes_read125 on public.style_axes;
create policy style_axes_read125 on public.style_axes for select to authenticated using (exists (select 1 from public.item_styles s where s.id = style_id and public._biz_vis125(s.org_unit_id)));
revoke all on public.style_axes from public, anon, authenticated;
grant select on public.style_axes to authenticated;

-- ---------- 4. items trigger: the owning business of a new item; never moves later ----------
create or replace function public._items_org125() returns trigger
language plpgsql security definer set search_path = public as $$
declare n int; b bigint;
begin
  if tg_op = 'UPDATE' then
    if old.org_unit_id is not null and new.org_unit_id is distinct from old.org_unit_id then raise exception 'item_org_fixed'; end if;
  end if;
  if new.org_unit_id is null then
    select count(*), max(x) into n, b from (select distinct public._my_biz125() as x) q;
    if n = 1 then new.org_unit_id := b; else new.org_unit_id := public._biz_default125(); end if;
  elsif tg_op = 'INSERT' or new.org_unit_id is distinct from old.org_unit_id then
    if not exists (select 1 from public.org_units o where o.id = new.org_unit_id and o.kind = 'business') then raise exception 'bad_business'; end if;
  end if;
  return new;
end $$;
drop trigger if exists items_org125 on public.items;
create trigger items_org125 before insert or update on public.items for each row execute function public._items_org125();

-- backfill: every existing item belongs to the sweets business (fill-null-only). The user triggers are paused for the statement so that updated_at / audit rows / guards
-- are not touched by a pure column fill.
do $b$
declare bz bigint := public._biz_default125();
begin
  if bz is not null and exists (select 1 from public.items where org_unit_id is null) then
    alter table public.items disable trigger user;
    update public.items set org_unit_id = bz where org_unit_id is null;
    alter table public.items enable trigger user;
  end if;
end $b$;

-- ---------- 5. rule + grant + advisor row ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
select 'variants_manage', 'stock', 99, 'ভ্যারিয়েন্ট (সাইজ/রং), অপশন তালিকা ও দামের তালিকা তৈরি ও বদলানো', 'Variant (size/colour), option list ও price list তৈরি ও বদলানো', 'Create and change variants (size / colour), option lists and price lists', 'once'
where not exists (select 1 from public.grant_defs where grant_code = 'variants_manage');

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('variants_on', 'stock', 'switch', 'false', null, null, null, null,
  'ভ্যারিয়েন্ট আইটেম (সাইজ/রং) ও দামের তালিকা', 'Variant item (size/colour) ও price list', 'Variant items (size / colour) and price lists',
  'বন্ধ থাকলে মিষ্টির সব কাজ আগের মতোই। চালু করলে ভ্যারিয়েন্ট তৈরি ও দামের তালিকা কাজ করে এবং এক ব্যবসার আইটেম অন্য ব্যবসা দেখে না।',
  'off থাকলে মিষ্টির সব কাজ আগের মতোই। on করলে variant তৈরি ও price list কাজ করে এবং এক business-এর item অন্য business দেখে না।',
  'Off: sweets works exactly as before. On: variant generation and price lists work and one business can no longer read another business''s items.', 991)
on conflict (key) do nothing;

insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort)
select 'variants_on', 'variants_on', '125', 'stock', null::jsonb, '{}'::text[],
  'শুধু যখন দ্বিতীয় ব্যবসা (কাপড়/হার্ডওয়্যার) শুরু হবে তখন চালু করুন। মিষ্টির জন্য বন্ধ থাকুক।',
  'শুধু যখন দ্বিতীয় business (কাপড়/hardware) শুরু হবে তখন on করুন। মিষ্টির জন্য off থাকুক।',
  'Turn on only when a second business (cloth / hardware) starts. Keep it off for sweets.', 991
where not exists (select 1 from public.setup_rec_defs81 where code = 'variants_on');

-- ---------- 6. items_read: with the switch ON an item is visible only inside the caller's business ----------
-- Replaces the policy only while it is still the original "any active user" one; a policy already tightened by Stage C1 is left alone.
do $p$
declare q text;
begin
  select qual into q from pg_policies where schemaname = 'public' and tablename = 'items' and policyname = 'items_read';
  if q is null or q ~* 'variants_on' or regexp_replace(q, '[\s()]', '', 'g') ~ '^(public\.)?is_active$' then
    drop policy if exists items_read on public.items;
    create policy items_read on public.items for select to authenticated using (
      public.is_active() and (
        not (select public.rule_on('variants_on'))
        or org_unit_id is null
        or (select public.is_owner())
        or org_unit_id in (select public._my_biz125())));
  else
    raise notice 'phase125: items_read was changed by another phase (%); left as is', q;
  end if;
end $p$;

-- ---------- 7. option sets and values (owner editable, nothing hardcoded) ----------
create or replace function public.option_set_save(p_org bigint, p_id bigint, p_code text, p_name_bn text, p_name_en text default null, p_kind text default 'other',
  p_group text default null, p_active boolean default true, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); s public.option_sets; c text := upper(btrim(coalesce(p_code, ''))); nid bigint;
begin
  perform public._var_gate125(p_org);
  perform public._client_lock(p_client);
  if p_name_bn is null or length(btrim(p_name_bn)) not between 1 and 80 or length(coalesce(p_name_en, '')) > 80 then raise exception 'bad_name'; end if;
  if p_kind is null or p_kind not in ('size', 'colour', 'fabric', 'age', 'other') then raise exception 'bad_kind'; end if;
  if length(coalesce(p_group, '')) > 80 then raise exception 'bad_group'; end if;
  if p_id is null then
    if p_client is null then raise exception 'client_id_needed'; end if;
    select * into s from public.option_sets where client_id = p_client;
    if found then
      if s.created_by is distinct from me then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', s.id, 'code', s.code);
    end if;
    if c !~ '^[A-Z0-9][A-Z0-9_]{0,23}$' then raise exception 'bad_code'; end if;
    if exists (select 1 from public.option_sets where org_unit_id = p_org and code = c) then raise exception 'code_taken'; end if;
    insert into public.option_sets (org_unit_id, code, name_bn, name_en, kind, product_group, active, client_id, created_by, updated_by)
    values (p_org, c, btrim(p_name_bn), nullif(btrim(coalesce(p_name_en, '')), ''), p_kind, nullif(btrim(coalesce(p_group, '')), ''), coalesce(p_active, true), p_client, me, me) returning id into nid;
    return jsonb_build_object('dup', false, 'id', nid, 'code', c);
  end if;
  select * into s from public.option_sets where id = p_id and org_unit_id = p_org for update;
  if not found then raise exception 'set_not_found'; end if;
  if p_code is not null and c <> s.code then raise exception 'code_fixed'; end if;
  update public.option_sets set name_bn = btrim(p_name_bn), name_en = nullif(btrim(coalesce(p_name_en, '')), ''), kind = p_kind,
    product_group = nullif(btrim(coalesce(p_group, '')), ''), active = coalesce(p_active, active), updated_by = me, updated_at = now() where id = p_id;
  return jsonb_build_object('dup', false, 'id', p_id, 'code', s.code);
end $$;

-- upsert many values of one set: [{"code":"M","label_bn":"M","label_en":"Medium","sort":20,"active":true}, ...]. A value is never deleted: set active=false.
create or replace function public.option_values_save(p_set bigint, p_values jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.option_sets; v jsonb; n int := 0; c text; lb text; le text; so int; ac boolean; me uuid := auth.uid();
begin
  select * into s from public.option_sets where id = p_set;
  if not found then raise exception 'set_not_found'; end if;
  perform public._var_gate125(s.org_unit_id);
  if p_values is null or jsonb_typeof(p_values) <> 'array' or jsonb_array_length(p_values) not between 1 and 200 then raise exception 'bad_values'; end if;
  for v in select * from jsonb_array_elements(p_values) loop
    if jsonb_typeof(v) <> 'object' then raise exception 'bad_values'; end if;
    c := upper(btrim(coalesce(v->>'code', '')));
    if c !~ '^[A-Z0-9][A-Z0-9._]{0,15}$' then raise exception 'bad_code'; end if;
    lb := btrim(coalesce(v->>'label_bn', v->>'label_en', c)); le := nullif(btrim(coalesce(v->>'label_en', '')), '');
    if length(lb) not between 1 and 60 or length(coalesce(le, '')) > 60 then raise exception 'bad_name'; end if;
    so := coalesce(nullif(v->>'sort', '')::int, 0); if so not between 0 and 100000 then raise exception 'bad_sort'; end if;
    ac := coalesce(nullif(v->>'active', '')::boolean, true);
    insert into public.option_values (set_id, org_unit_id, code, label_bn, label_en, sort, active, created_by, updated_by)
    values (s.id, s.org_unit_id, c, lb, le, so, ac, me, me)
    on conflict (set_id, code) do update set label_bn = excluded.label_bn, label_en = excluded.label_en, sort = excluded.sort, active = excluded.active, updated_by = me, updated_at = now();
    n := n + 1;
  end loop;
  return jsonb_build_object('saved', n, 'set_id', s.id);
end $$;

-- ---------- 8. styles ----------
create or replace function public.style_save(p_org bigint, p_id bigint, p_code text, p_name_bn text, p_name_en text default null, p_group text default null,
  p_sub text default null, p_unit text default 'pc', p_item_type text default 'resale', p_price numeric default null, p_axes bigint[] default null,
  p_status text default 'active', p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); st public.item_styles; c text := upper(btrim(coalesce(p_code, ''))); nid bigint; i int; a bigint; cur bigint[]; has_var boolean;
begin
  perform public._var_gate125(p_org);
  perform public._client_lock(p_client);
  if p_name_bn is null or length(btrim(p_name_bn)) not between 1 and 120 or length(coalesce(p_name_en, '')) > 120 then raise exception 'bad_name'; end if;
  if length(coalesce(p_group, '')) > 80 or length(coalesce(p_sub, '')) > 80 then raise exception 'bad_group'; end if;
  if p_unit is null or length(btrim(p_unit)) not between 1 and 20 then raise exception 'bad_unit'; end if;
  if not exists (select 1 from public.item_types where code = p_item_type) then raise exception 'bad_item_type'; end if;
  if p_price is not null and (p_price <> p_price or p_price < 0 or p_price > 1000000000) then raise exception 'bad_price'; end if;
  if p_status not in ('active', 'inactive') then raise exception 'bad_status'; end if;
  if p_axes is not null then
    if coalesce(array_length(p_axes, 1), 0) not between 1 and 4 then raise exception 'bad_axes'; end if;
    if (select count(distinct x) from unnest(p_axes) x) <> array_length(p_axes, 1) then raise exception 'bad_axes'; end if;
    foreach a in array p_axes loop
      if not exists (select 1 from public.option_sets s where s.id = a and s.org_unit_id = p_org and s.active) then raise exception 'bad_axes'; end if;
    end loop;
  end if;
  if p_id is null then
    if p_client is null then raise exception 'client_id_needed'; end if;
    select * into st from public.item_styles where client_id = p_client;
    if found then
      if st.created_by is distinct from me then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', st.id, 'code', st.code);
    end if;
    if c !~ '^[A-Z0-9][A-Z0-9_]{0,23}$' then raise exception 'bad_code'; end if;
    if exists (select 1 from public.item_styles where org_unit_id = p_org and code = c) then raise exception 'code_taken'; end if;
    if p_axes is null then raise exception 'bad_axes'; end if;
    insert into public.item_styles (org_unit_id, code, name_bn, name_en, product_group, sub_category, unit, item_type, base_price, status, client_id, created_by, updated_by)
    values (p_org, c, btrim(p_name_bn), nullif(btrim(coalesce(p_name_en, '')), ''), nullif(btrim(coalesce(p_group, '')), ''), nullif(btrim(coalesce(p_sub, '')), ''),
            btrim(p_unit), p_item_type, round(p_price, 2), p_status, p_client, me, me) returning id into nid;
    for i in 1 .. array_length(p_axes, 1) loop insert into public.style_axes (style_id, axis_no, set_id) values (nid, i, p_axes[i]); end loop;
    return jsonb_build_object('dup', false, 'id', nid, 'code', c);
  end if;
  select * into st from public.item_styles where id = p_id and org_unit_id = p_org for update;
  if not found then raise exception 'style_not_found'; end if;
  if p_code is not null and c <> st.code then raise exception 'code_fixed'; end if;
  if p_axes is not null then
    select array_agg(set_id order by axis_no) into cur from public.style_axes where style_id = p_id;
    if cur is distinct from p_axes then
      select exists (select 1 from public.items where style_id = p_id) into has_var;
      if has_var then raise exception 'axes_locked'; end if;       -- variants already exist: the axes can no longer change
      delete from public.style_axes where style_id = p_id;
    end if;
  end if;
  update public.item_styles set name_bn = btrim(p_name_bn), name_en = nullif(btrim(coalesce(p_name_en, '')), ''), product_group = nullif(btrim(coalesce(p_group, '')), ''),
    sub_category = nullif(btrim(coalesce(p_sub, '')), ''), unit = btrim(p_unit), item_type = p_item_type, base_price = round(p_price, 2), status = p_status,
    updated_by = me, updated_at = now() where id = p_id;
  return jsonb_build_object('dup', false, 'id', p_id, 'code', st.code);
end $$;

-- ---------- 9. variant generator ----------
-- internal EAN-13 (prefix 2 = in-store use), 11 digits from the sequence + check digit
create sequence if not exists public.variant_barcode_seq125;
create or replace function public._ean13_125(p_n bigint) returns text
language sql immutable set search_path = public as $$
  with d as (select '2' || lpad(p_n::text, 11, '0') as s)
  select s || ((10 - (select sum(substr(s, k, 1)::int * case when k % 2 = 0 then 3 else 1 end) % 10 from generate_series(1, 12) k)) % 10)::text from d;
$$;

-- p_pick: optional {"<option set code>": ["S","M"]} to generate only a subset. p_dry (default true) writes nothing and returns the plan. Max 500 combinations per call.
-- Idempotent: a combination that already exists (style_id + variant_key) is left alone, so running it twice creates nothing new.
create or replace function public.variants_generate(p_style bigint, p_pick jsonb default null, p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare st public.item_styles; naxes int; total int; created int := 0; existing int := 0; r record; bc text; nid uuid; clash text; out jsonb := '[]'::jsonb; tries int;
begin
  select * into st from public.item_styles where id = p_style;
  if not found then raise exception 'style_not_found'; end if;
  perform public._var_gate125(st.org_unit_id);
  if st.status <> 'active' then raise exception 'style_inactive'; end if;
  if p_pick is not null and jsonb_typeof(p_pick) <> 'object' then raise exception 'bad_pick'; end if;
  perform 1 from public.item_styles where id = p_style for update;       -- one generator per style at a time
  select count(*) into naxes from public.style_axes where style_id = p_style;
  if naxes = 0 then raise exception 'no_axes'; end if;
  create temp table if not exists _vg125 (vkey text, vcode text, name_bn text, name_en text, opts jsonb) on commit drop;
  truncate _vg125;
  with recursive ax as (
    select a.axis_no, a.set_id, s.code scode from public.style_axes a join public.option_sets s on s.id = a.set_id where a.style_id = p_style),
  combos(n, vkey, vcode, lbn, len, opts) as (
    select 0, ''::text, ''::text, ''::text, ''::text, '{}'::jsonb
    union all
    select c.n + 1, case when c.n = 0 then v.code else c.vkey || '|' || v.code end, c.vcode || '-' || v.code, c.lbn || ' ' || v.label_bn,
           c.len || ' ' || coalesce(v.label_en, v.label_bn), c.opts || jsonb_build_object(ax.scode, v.code)
      from combos c join ax on ax.axis_no = c.n + 1
      join public.option_values v on v.set_id = ax.set_id and v.active
       and (p_pick is null or not (p_pick ? ax.scode) or (jsonb_typeof(p_pick->ax.scode) = 'array' and (p_pick->ax.scode) ? v.code)))
  insert into _vg125 select vkey, st.code || vcode, regexp_replace(btrim(st.name_bn || ' ' || lbn), '\s+', ' ', 'g'), regexp_replace(btrim(coalesce(st.name_en, st.name_bn) || ' ' || len), '\s+', ' ', 'g'), opts from combos where n = naxes;
  select count(*) into total from _vg125;
  if total = 0 then raise exception 'no_values'; end if;
  if total > 500 then raise exception 'too_many' using hint = total::text; end if;
  -- a code that already belongs to some other item (global items.code is still unique) would break the run: refuse before writing anything
  select string_agg(g.vcode, ', ') into clash from _vg125 g join public.items i on i.code = g.vcode and (i.style_id is distinct from p_style or i.variant_key is distinct from g.vkey);
  if clash is not null then raise exception 'code_taken' using hint = left(clash, 200); end if;
  select count(*) into existing from _vg125 g where exists (select 1 from public.items i where i.style_id = p_style and i.variant_key = g.vkey);
  if p_dry then
    return jsonb_build_object('dry', true, 'total', total, 'would_create', total - existing, 'existing', existing,
      'sample', (select coalesce(jsonb_agg(vcode order by vcode), '[]'::jsonb) from (select g.vcode from _vg125 g where not exists
                  (select 1 from public.items i where i.style_id = p_style and i.variant_key = g.vkey) order by g.vcode limit 20) q));
  end if;
  for r in select g.* from _vg125 g where not exists (select 1 from public.items i where i.style_id = p_style and i.variant_key = g.vkey) order by g.vcode loop
    tries := 0;
    loop
      bc := public._ean13_125(nextval('public.variant_barcode_seq125'));
      exit when not exists (select 1 from public.items where barcode = bc);
      tries := tries + 1; if tries > 50 then raise exception 'barcode_failed'; end if;
    end loop;
    insert into public.items (code, name_bn, name_en, name_mix, category, sub_category, unit, sell_price, item_type, tracked, barcode, org_unit_id, style_id, variant_key, variant_opts)
    values (r.vcode, r.name_bn, r.name_en, r.name_en, st.product_group, st.sub_category, st.unit, st.base_price, st.item_type, true, bc, st.org_unit_id, p_style, r.vkey, r.opts)
    on conflict (style_id, variant_key) where style_id is not null do nothing returning id into nid;
    if nid is not null then
      created := created + 1;
      if jsonb_array_length(out) < 50 then out := out || jsonb_build_object('id', nid, 'code', r.vcode, 'barcode', bc); end if;
    end if;
    nid := null;
  end loop;
  return jsonb_build_object('dry', false, 'total', total, 'created', created, 'existing', total - created, 'items', out);
end $$;

-- ---------- 10. reads: overview + size x colour matrix ----------
create or replace function public.my_businesses125() returns table (id bigint, code text, name_bn text, name_en text, template_code text, variants_on boolean)
language sql stable security definer set search_path = public as $$
  select o.id, o.code, o.name_bn, o.name_en, o.template_code, public.rule_on('variants_on')
    from public.org_units o where o.kind = 'business' and o.status <> 'inactive' and o.id in (select public._my_biz125()) order by o.id;
$$;

create or replace function public.variants_overview(p_org bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._biz_vis125(p_org) then raise exception 'not allowed'; end if;
  return jsonb_build_object('org', p_org, 'variants_on', public.rule_on('variants_on'), 'can_manage', public._biz_mgr125(p_org),
    'option_sets', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'code', s.code, 'name_bn', s.name_bn, 'name_en', s.name_en, 'kind', s.kind, 'product_group', s.product_group, 'active', s.active,
        'values', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'code', v.code, 'label_bn', v.label_bn, 'label_en', v.label_en, 'sort', v.sort, 'active', v.active) order by v.sort, v.code), '[]'::jsonb)
                     from public.option_values v where v.set_id = s.id)) order by s.code), '[]'::jsonb) from public.option_sets s where s.org_unit_id = p_org),
    'styles', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'code', t.code, 'name_bn', t.name_bn, 'name_en', t.name_en, 'product_group', t.product_group, 'unit', t.unit,
        'item_type', t.item_type, 'base_price', t.base_price, 'status', t.status,
        'axes', (select coalesce(jsonb_agg(a.set_id order by a.axis_no), '[]'::jsonb) from public.style_axes a where a.style_id = t.id),
        'variant_count', (select count(*) from public.items i where i.style_id = t.id)) order by t.code), '[]'::jsonb) from public.item_styles t where t.org_unit_id = p_org),
    'price_lists', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'code', p.code, 'name_bn', p.name_bn, 'name_en', p.name_en, 'channel', p.channel, 'valid_from', p.valid_from,
        'valid_to', p.valid_to, 'active', p.active, 'rows', (select count(*) from public.price_list_items x where x.price_list_id = p.id)) order by p.code), '[]'::jsonb)
        from public.price_lists p where p.org_unit_id = p_org));
end $$;

-- the matrix of one style: axes with their values and one cell per variant (stock summed over the locations the caller may see; optional single location)
create or replace function public.variant_matrix(p_style bigint, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st public.item_styles;
begin
  select * into st from public.item_styles where id = p_style;
  if not found or not public._biz_vis125(st.org_unit_id) then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  return jsonb_build_object('style', jsonb_build_object('id', st.id, 'code', st.code, 'name_bn', st.name_bn, 'name_en', st.name_en, 'base_price', st.base_price),
    'axes', (select coalesce(jsonb_agg(jsonb_build_object('axis_no', a.axis_no, 'set_id', s.id, 'code', s.code, 'name_bn', s.name_bn, 'name_en', s.name_en,
        'values', (select coalesce(jsonb_agg(jsonb_build_object('code', v.code, 'label_bn', v.label_bn, 'label_en', v.label_en, 'active', v.active) order by v.sort, v.code), '[]'::jsonb)
                     from public.option_values v where v.set_id = s.id)) order by a.axis_no), '[]'::jsonb)
               from public.style_axes a join public.option_sets s on s.id = a.set_id where a.style_id = p_style),
    'cells', (select coalesce(jsonb_agg(jsonb_build_object('item_id', i.id, 'code', i.code, 'barcode', i.barcode, 'key', i.variant_key, 'opts', i.variant_opts, 'active', i.is_active,
        'sell_price', i.sell_price,
        'stock', (select coalesce(sum(b.qty), 0) from public.stock_balance b where b.item_id = i.id and public.can_loc(b.location_id) and (p_loc is null or b.location_id = p_loc))) order by i.code), '[]'::jsonb)
              from public.items i where i.style_id = p_style));
end $$;

-- ---------- 11. price lists by channel ----------
create or replace function public.price_list_save(p_org bigint, p_id bigint, p_code text, p_name_bn text, p_name_en text default null, p_channel text default 'retail',
  p_from date default null, p_to date default null, p_active boolean default true, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); pl public.price_lists; c text := upper(btrim(coalesce(p_code, ''))); nid bigint; today date := (now() at time zone 'Asia/Dhaka')::date; f date;
begin
  perform public._var_gate125(p_org);
  perform public._client_lock(p_client);
  if p_name_bn is null or length(btrim(p_name_bn)) not between 1 and 80 or length(coalesce(p_name_en, '')) > 80 then raise exception 'bad_name'; end if;
  if p_channel is null or p_channel not in ('retail', 'wholesale', 'online') then raise exception 'bad_channel'; end if;
  f := coalesce(p_from, date '2000-01-01');
  if f < date '2000-01-01' or f > today + 3660 or (p_to is not null and (p_to < f or p_to > today + 36600)) then raise exception 'bad_date'; end if;
  if p_id is null then
    if p_client is null then raise exception 'client_id_needed'; end if;
    select * into pl from public.price_lists where client_id = p_client;
    if found then
      if pl.created_by is distinct from me then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', pl.id, 'code', pl.code);
    end if;
    if c !~ '^[A-Z0-9][A-Z0-9_-]{0,23}$' then raise exception 'bad_code'; end if;
    if exists (select 1 from public.price_lists where org_unit_id = p_org and code = c) then raise exception 'code_taken'; end if;
    insert into public.price_lists (org_unit_id, code, name_bn, name_en, channel, valid_from, valid_to, active, client_id, created_by, updated_by)
    values (p_org, c, btrim(p_name_bn), nullif(btrim(coalesce(p_name_en, '')), ''), p_channel, f, p_to, coalesce(p_active, true), p_client, me, me) returning id into nid;
    return jsonb_build_object('dup', false, 'id', nid, 'code', c);
  end if;
  select * into pl from public.price_lists where id = p_id and org_unit_id = p_org for update;
  if not found then raise exception 'list_not_found'; end if;
  if p_code is not null and c <> pl.code then raise exception 'code_fixed'; end if;
  if p_channel <> pl.channel then raise exception 'channel_fixed'; end if;
  update public.price_lists set name_bn = btrim(p_name_bn), name_en = nullif(btrim(coalesce(p_name_en, '')), ''), valid_from = f, valid_to = p_to,
    active = coalesce(p_active, active), updated_by = me, updated_at = now() where id = p_id;
  return jsonb_build_object('dup', false, 'id', p_id, 'code', pl.code);
end $$;

-- upsert rows: [{"item_id":"..","price":999,"min_qty":1,"valid_from":"2026-01-01","valid_to":null}]. The item's own price is never touched.
create or replace function public.price_list_items_set(p_list bigint, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pl public.price_lists; v jsonb; n int := 0; it uuid; pr numeric; mq numeric; vf date; vt date; me uuid := auth.uid();
begin
  select * into pl from public.price_lists where id = p_list;
  if not found then raise exception 'list_not_found'; end if;
  perform public._var_gate125(pl.org_unit_id);
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) not between 1 and 1000 then raise exception 'bad_rows'; end if;
  for v in select * from jsonb_array_elements(p_rows) loop
    if jsonb_typeof(v) <> 'object' then raise exception 'bad_rows'; end if;
    it := (v->>'item_id')::uuid; pr := (v->>'price')::numeric; mq := coalesce(nullif(v->>'min_qty', '')::numeric, 1);
    vf := coalesce(nullif(v->>'valid_from', '')::date, pl.valid_from); vt := nullif(v->>'valid_to', '')::date;
    if pr is null or pr <> pr or pr < 0 or pr > 1000000000 then raise exception 'bad_price'; end if;
    if mq is null or mq <> mq or mq <= 0 or mq > 1000000000 then raise exception 'bad_qty'; end if;
    if vf < pl.valid_from or (vt is not null and vt < vf) or (pl.valid_to is not null and (vf > pl.valid_to or vt > pl.valid_to)) then raise exception 'bad_date'; end if;
    if not exists (select 1 from public.items i where i.id = it and i.org_unit_id = pl.org_unit_id) then raise exception 'item_not_in_business'; end if;
    insert into public.price_list_items (price_list_id, org_unit_id, item_id, price, min_qty, valid_from, valid_to, created_by, updated_by)
    values (pl.id, pl.org_unit_id, it, round(pr, 2), mq, vf, vt, me, me)
    on conflict (price_list_id, item_id, min_qty, valid_from) do update set price = excluded.price, valid_to = excluded.valid_to, updated_by = me, updated_at = now();
    n := n + 1;
  end loop;
  return jsonb_build_object('saved', n, 'list_id', pl.id);
end $$;

-- which price applies? list price when an active list of that channel has a valid row (highest min_qty <= qty, then latest valid_from), else the item's own price.
-- Nothing in the existing sales / POS code calls this; it is the single place a later phase wires channel prices in.
create or replace function public.price_for125(p_item uuid, p_channel text default 'retail', p_on date default null, p_qty numeric default 1) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare i public.items; d date := coalesce(p_on, (now() at time zone 'Asia/Dhaka')::date); r record;
begin
  if p_channel is null or p_channel not in ('retail', 'wholesale', 'online') then raise exception 'bad_channel'; end if;
  if p_qty is null or p_qty <> p_qty or p_qty <= 0 then raise exception 'bad_qty'; end if;
  select * into i from public.items where id = p_item;
  if not found or not public._biz_vis125(i.org_unit_id) then raise exception 'not allowed'; end if;
  select x.price, x.price_list_id into r from public.price_list_items x join public.price_lists l on l.id = x.price_list_id
   where x.item_id = p_item and l.channel = p_channel and l.active and l.org_unit_id = i.org_unit_id
     and d between l.valid_from and coalesce(l.valid_to, date '9999-12-31') and d between x.valid_from and coalesce(x.valid_to, date '9999-12-31') and x.min_qty <= p_qty
   order by x.min_qty desc, x.valid_from desc, x.id desc limit 1;
  if found then return jsonb_build_object('price', r.price, 'source', 'list', 'list_id', r.price_list_id, 'channel', p_channel); end if;
  return jsonb_build_object('price', case when p_channel = 'wholesale' then coalesce(i.wholesale_price, i.sell_price) else i.sell_price end, 'source', 'item', 'list_id', null, 'channel', p_channel);
end $$;

-- ---------- 12. privileges ----------
revoke all on function public._biz_of125(bigint), public._my_biz125(), public._biz_vis125(bigint), public._biz_mgr125(bigint), public._biz_default125(), public._var_gate125(bigint),
  public._items_org125(), public._ean13_125(bigint) from public, anon, authenticated;
-- the RLS policies call these two as the signed-in user: they only answer about the caller's own scope
grant execute on function public._my_biz125(), public._biz_vis125(bigint) to authenticated;
revoke all on function public.option_set_save(bigint, bigint, text, text, text, text, text, boolean, uuid), public.option_values_save(bigint, jsonb),
  public.style_save(bigint, bigint, text, text, text, text, text, text, text, numeric, bigint[], text, uuid), public.variants_generate(bigint, jsonb, boolean),
  public.my_businesses125(), public.variants_overview(bigint), public.variant_matrix(bigint, int),
  public.price_list_save(bigint, bigint, text, text, text, text, date, date, boolean, uuid), public.price_list_items_set(bigint, jsonb),
  public.price_for125(uuid, text, date, numeric) from public, anon;
grant execute on function public.option_set_save(bigint, bigint, text, text, text, text, text, boolean, uuid), public.option_values_save(bigint, jsonb),
  public.style_save(bigint, bigint, text, text, text, text, text, text, text, numeric, bigint[], text, uuid), public.variants_generate(bigint, jsonb, boolean),
  public.my_businesses125(), public.variants_overview(bigint), public.variant_matrix(bigint, int),
  public.price_list_save(bigint, bigint, text, text, text, text, date, date, boolean, uuid), public.price_list_items_set(bigint, jsonb),
  public.price_for125(uuid, text, date, numeric) to authenticated;
revoke all on sequence public.variant_barcode_seq125 from public, anon, authenticated;

commit;

-- ---------------------------------------------------------------- phase126.sql
-- ============================================================
-- Phase 126 (marker var126) - LARGE CATALOGUE READINESS: server-side item search + paging (ADDITIVE ONLY; existing item screens and listings unchanged).
-- Needs phase125 (items.org_unit_id, _my_biz125). Canonical order: after phase125. Paste twice = no change, no error.
--   items.brand (nullable text)  the principal / brand of a bought-in item (paint dealer). Sweets items stay null.
--   Indexes on items: (org_unit_id, category), (lower(code) text_pattern_ops), barcode prefix, brand, and - when the extension pg_trgm is available -
--       GIN trigram indexes on name_bn / name_en / name_mix (substring search). Without pg_trgm the fallback is btree prefix indexes on lower(name_*), so a search
--       matches the START of a name (and code / barcode prefixes) instead of any part of it. items_search_info126() tells which mode is active.
--   items_search(p_org, p_q, p_filters, p_limit, p_offset)  one call = one page + summary counts, scoped to the caller's businesses (owner: all; others: the businesses of
--       their assigned locations; a business the caller may not see is refused). Never returns cost. Filters: category, sub_category, brand, style_id, barcode, item_type,
--       active (true default | false | "all"), tracked, counts (false skips the summary). q: code prefix, barcode prefix/exact, name substring (q shorter than 3 characters:
--       name prefix only, because a trigram needs 3 characters).
--   Existing flows do not call it; nothing existing is changed except the new indexes (a small extra cost on item insert / update, measured in docs/regs/variants125.md).
-- Rollback: drop items_search, items_search_info126, the new indexes and items.brand (nothing else refers to them).
-- ============================================================
begin;

do $g$
begin
  if to_regclass('public.items') is null or to_regprocedure('public._my_biz125()') is null or not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'items' and column_name = 'org_unit_id') then
    raise exception 'phase126 needs phase125 pasted first (docs/PASTE_ORDER.md)';
  end if;
end $g$;

alter table public.items add column if not exists brand text check (brand is null or length(brand) <= 80);

-- btree indexes (always)
create index if not exists items_org_cat126 on public.items (org_unit_id, category);
create index if not exists items_code_lpfx126 on public.items (lower(code) text_pattern_ops);
create index if not exists items_barcode_pfx126 on public.items (barcode text_pattern_ops) where barcode is not null;
create index if not exists items_org_brand126 on public.items (org_unit_id, brand) where brand is not null;

-- substring search: pg_trgm when it can be installed, otherwise btree prefix indexes on the lower-cased names
do $t$
declare ns text;
begin
  begin
    create schema if not exists extensions;                       -- Supabase already has it; keeps the ~30 pg_trgm helper functions out of the public API schema
    create extension if not exists pg_trgm schema extensions;
  exception when others then
    raise notice 'phase126: pg_trgm not available (%): name search falls back to btree prefix indexes', sqlerrm;
  end;
  select n.nspname into ns from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pg_trgm';
  if ns is not null then
    execute format('create index if not exists items_name_bn_trgm126 on public.items using gin (name_bn %I.gin_trgm_ops)', ns);
    execute format('create index if not exists items_name_en_trgm126 on public.items using gin (name_en %I.gin_trgm_ops)', ns);
    execute format('create index if not exists items_name_mix_trgm126 on public.items using gin (name_mix %I.gin_trgm_ops)', ns);
  else
    create index if not exists items_name_bn_pfx126 on public.items (lower(name_bn) text_pattern_ops);
    create index if not exists items_name_en_pfx126 on public.items (lower(name_en) text_pattern_ops);
    create index if not exists items_name_mix_pfx126 on public.items (lower(name_mix) text_pattern_ops);
  end if;
exception when others then
  raise notice 'phase126: name index step skipped (%)', sqlerrm;   -- an add-on: it can never block the phase
end $t$;

create or replace function public.items_search_info126() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('trigram', exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'items_name_bn_trgm126'),
    'indexes', (select coalesce(jsonb_agg(indexname order by indexname), '[]'::jsonb) from pg_indexes where schemaname = 'public' and tablename = 'items' and indexname ~ '126$'));
$$;

create or replace function public.items_search(p_org bigint default null, p_q text default null, p_filters jsonb default '{}'::jsonb, p_limit int default 50, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  q text := nullif(btrim(coalesce(p_q, '')), ''); f jsonb := coalesce(p_filters, '{}'::jsonb); lim int := coalesce(p_limit, 50); off int := coalesce(p_offset, 0);
  qe text; qlow text; act text; cat text; sub text; br text; sty bigint; bc text; ity text; trk boolean; want_counts boolean := true; res jsonb; allb boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if jsonb_typeof(f) <> 'object' then raise exception 'bad_filters'; end if;
  if p_org is not null and not public._biz_vis125(p_org) then raise exception 'not allowed'; end if;
  if lim < 1 or lim > 200 then raise exception 'bad_limit'; end if;
  if off < 0 or off > 1000000 then raise exception 'bad_offset'; end if;
  if q is not null and length(q) > 80 then raise exception 'bad_query'; end if;
  qlow := lower(coalesce(q, ''));
  qe := replace(replace(replace(qlow, '\', '\\'), '%', '\%'), '_', '\_');
  act := coalesce(f->>'active', 'true');
  if act not in ('true', 'false', 'all') then raise exception 'bad_filters'; end if;
  cat := nullif(f->>'category', ''); sub := nullif(f->>'sub_category', ''); br := nullif(f->>'brand', ''); bc := nullif(f->>'barcode', ''); ity := nullif(f->>'item_type', '');
  sty := nullif(f->>'style_id', '')::bigint; trk := nullif(f->>'tracked', '')::boolean;
  if f ? 'counts' then want_counts := coalesce((f->>'counts')::boolean, true); end if;
  allb := p_org is null and public.is_owner();

  with m as materialized (
    select i.id, i.code, i.is_active, i.style_id, i.category, i.brand,
           case when q is null then 3
                when lower(i.code) = qlow or i.barcode = q then 0
                when lower(i.code) like qe || '%' escape '\' or i.barcode like qe || '%' escape '\' then 1
                else 2 end rk
      from public.items i
     where (case when p_org is not null then i.org_unit_id = p_org when allb then true else i.org_unit_id in (select public._my_biz125()) end)
       and (act = 'all' or i.is_active = (act = 'true'))
       and (cat is null or i.category = cat) and (sub is null or i.sub_category = sub) and (br is null or i.brand = br)
       and (sty is null or i.style_id = sty) and (bc is null or i.barcode = bc) and (ity is null or i.item_type = ity) and (trk is null or i.tracked = trk)
       and (q is null
            or lower(i.code) like qe || '%' escape '\'
            or i.barcode like qe || '%' escape '\'
            or (length(q) >= 3 and (i.name_bn ilike '%' || qe || '%' escape '\' or i.name_en ilike '%' || qe || '%' escape '\' or i.name_mix ilike '%' || qe || '%' escape '\'))
            or (length(q) < 3 and (lower(i.name_bn) like qe || '%' escape '\' or lower(i.name_en) like qe || '%' escape '\' or lower(i.name_mix) like qe || '%' escape '\')))),
  pg as (select m.id, m.rk, m.code from m order by m.rk, m.code limit lim offset off)
  select jsonb_build_object('total', (select count(*) from m), 'limit', lim, 'offset', off,
    'rows', (select coalesce(jsonb_agg((to_jsonb(x) - 'rk') order by x.rk, x.code), '[]'::jsonb) from (
        select i.id, i.code, i.name_bn, i.name_en, i.name_mix, i.category, i.sub_category, i.brand, i.unit, i.sell_price, i.barcode, i.style_id, i.variant_opts, i.is_active, i.tracked, i.org_unit_id, pg.rk
          from pg join public.items i on i.id = pg.id) x),
    'counts', case when want_counts then jsonb_build_object(
        'active', (select count(*) from m where m.is_active), 'inactive', (select count(*) from m where not m.is_active), 'variants', (select count(*) from m where m.style_id is not null),
        'by_category', (select coalesce(jsonb_agg(jsonb_build_object('category', c, 'n', n) order by n desc, c), '[]'::jsonb) from (select coalesce(m.category, '') c, count(*) n from m group by 1 order by n desc, c limit 20) z),
        'by_brand', (select coalesce(jsonb_agg(jsonb_build_object('brand', b, 'n', n) order by n desc, b), '[]'::jsonb) from (select m.brand b, count(*) n from m where m.brand is not null group by 1 order by n desc, b limit 20) z)) end)
  into res;
  return res;
end $$;

revoke all on function public.items_search(bigint, text, jsonb, int, int), public.items_search_info126() from public, anon;
grant execute on function public.items_search(bigint, text, jsonb, int, int), public.items_search_info126() to authenticated;

commit;

-- ---------------------------------------------------------------- phase127.sql
-- ============================================================
-- Phase 127 (marker dl127) - DEALER / HARDWARE-PAINT BUSINESS, part 1: cheque / PDC register (ADDITIVE ONLY).
-- Canonical order: after phase126 (docs/PASTE_ORDER.md). Needs the base schema + phase122 (org_units, locations.org_unit_id) + the customer / supplier ledgers.
-- Paste twice = no change, no error. Rule dealer_cheque_on is OFF by default: while OFF every write function refuses ('feature_off'); reads still work.
--   Table  dealer_cheques         one row per cheque, RECEIVED (from a customer / other) or ISSUED (to a supplier / other). Status registered | deposited |
--                                 cleared | bounced | replaced | cancelled. Amount, bank, cheque no., cheque date, due (deposit) date, bounce reason + charge,
--                                 replacement link (replaced_by), our bank account (coa), bank statement line (reconciliation hook), ledger link.
--   Table  dealer_cheque_events   append-only history of every step (who, when, from -> to, amount). Idempotency key per step.
--   Business scope: every row carries location_id and business_id (the business unit of the location, phase122). Every read / write function checks
--     _dl_ok127(location, grant): owner, or the user is EXPLICITLY assigned to that location (user_locations; the management-role bypass of can_loc is NOT used)
--     AND holds the grant for that location. Another business's cheques are therefore invisible and untouchable. RLS on both tables uses the same check.
--   Money rule (no double counting): registering / depositing / bouncing / replacing a cheque changes NO ledger. Only CLEAR posts: a received cheque writes ONE
--     sale_payments row (kind collection, mode bank, client_id = the cheque id) so the customer's balance goes down once; an issued cheque writes ONE
--     supplier_payments row (mode bank, client_id = the cheque id). The status guard + the client id make a second clear impossible. Over-payment is refused
--     (same rule as collect_payment / pay_supplier). The bank-charge of a bounce is only RECORDED on the cheque (nothing is posted to any ledger).
--     sale_payments.mode check is widened to also allow 'bank' (existing rows and modes unchanged; _acct_paykey already maps 'bank' to the bank account).
--   Reports: cheques_due (aging buckets), cheques_bounced, post_dated_exposure (per party), cheque_ledger_check (cleared cheques whose ledger payment was voided),
--     cheque_bank_candidates + cheque_bank_link (bank reconciliation hook: cleared cheque <-> bank_statement_lines row, same account, same signed amount).
--   Rule dealer_cheque_on (switch, OFF). Grants dealer_cheque_view, dealer_cheque_manage (not given to any role by default).
-- Known limits (documented, not hidden): customers and suppliers are still ONE master list for the whole database (master-data scope is a later stage), so a party
--   can be linked from two businesses; the cheque rows themselves, and every report, are strictly per business.
-- Rollback: leave dealer_cheque_on OFF. To remove: drop the functions, the two tables (nothing else refers to them).
-- ============================================================
begin;

do $g$
declare miss text := '';
begin
  if to_regclass('public.locations') is null or to_regclass('public.org_units') is null or to_regclass('public.customers') is null or to_regclass('public.suppliers') is null
     or to_regclass('public.sale_payments') is null or to_regclass('public.supplier_payments') is null or to_regclass('public.user_locations') is null
     or to_regclass('public.bank_statement_lines') is null or to_regclass('public.coa_accounts') is null or to_regclass('public.grant_defs') is null or to_regclass('public.rules') is null
     or to_regclass('public.setup_rec_defs81') is null then miss := miss || ' tables'; end if;
  if to_regprocedure('public.is_owner()') is null or to_regprocedure('public.is_active()') is null or to_regprocedure('public.has_grant(text,integer)') is null
     or to_regprocedure('public.log_change()') is null or to_regprocedure('public.no_hard_delete()') is null or to_regprocedure('public._client_lock(uuid)') is null
     or to_regprocedure('public.rule_on(text)') is null or to_regprocedure('public.lock_check(date)') is null or to_regprocedure('public._cust_bal(uuid)') is null
     or to_regprocedure('public._sup_balance(uuid)') is null then miss := miss || ' functions'; end if;
  if miss <> '' then raise exception 'phase127 needs the base schema and phases up to 122 pasted first (docs/PASTE_ORDER.md); missing:%', miss; end if;
end $g$;

-- ---------- 0. grants, rule ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
select v.c, 'dealer', v.s, v.b, v.m, v.e, 'once' from (values
  ('dealer_cheque_view', 127, 'চেক / PDC তালিকা ও রিপোর্ট দেখা', 'Cheque / PDC list ও report দেখা', 'View the cheque / PDC register and its reports'),
  ('dealer_cheque_manage', 128, 'চেক / PDC নিবন্ধন, জমা, ক্লিয়ার, বাউন্স', 'Cheque / PDC register, deposit, clear, bounce', 'Register, deposit, clear and bounce cheques / PDCs')
) v(c, s, b, m, e) where not exists (select 1 from public.grant_defs g where g.grant_code = v.c);

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('dealer_cheque_on', 'dealer', 'switch', 'false', null, null, null, null,
  'চেক / PDC খাতা চালু', 'Cheque / PDC register চালু', 'Cheque / PDC register',
  'চালু করলে চেক নিবন্ধন, জমা, ক্লিয়ার ও বাউন্স লেখা যাবে। শুধু ক্লিয়ার হলে গ্রাহক / সাপ্লায়ারের খাতায় টাকা ওঠে।',
  'চালু করলে cheque register, deposit, clear ও bounce লেখা যাবে। শুধু clear হলে customer / supplier এর খাতায় টাকা ওঠে।',
  'When on, cheques can be registered, deposited, cleared and bounced. Only CLEAR moves money in the party ledger.', 1270)
on conflict (key) do nothing;

insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort)
select 'dealer_cheque_on', 'dealer_cheque_on', '127', 'dealer', null::jsonb, '{}'::text[],
  'ডিলার / হার্ডওয়্যার ব্যবসায় চেক ব্যবহার হলে চালু করুন; মিষ্টির ব্যবসায় দরকার নেই।',
  'Dealer / hardware business এ cheque ব্যবহার হলে চালু করুন; মিষ্টির business এ দরকার নেই।',
  'Turn on only for a business that takes or gives cheques (dealer / hardware); the sweets business does not need it.', 1270
where not exists (select 1 from public.setup_rec_defs81 where code = 'dealer_cheque_on');

-- ---------- 1. shared scope helpers (also used by phase128 / phase129) ----------
-- the business (org unit of kind business) a location belongs to; null when the location is not mapped
-- one read-only window onto the organization layer (phase122): the dealer functions read units only through it
create or replace view public.dl_unit_tree127 as select id, parent_id, kind, code from public.org_units;
revoke all on public.dl_unit_tree127 from public, anon, authenticated;

create or replace function public._dl_biz127(p_loc int) returns bigint
language sql stable security definer set search_path = public as $$
  with recursive up(id, parent_id, kind) as (
    select o.id, o.parent_id, o.kind from public.dl_unit_tree127 o join public.locations l on l.org_unit_id = o.id where l.id = p_loc
    union all select p.id, p.parent_id, p.kind from public.dl_unit_tree127 p join up on up.parent_id = p.id)
  select id from up where kind = 'business' limit 1;
$$;

-- may the caller use grant p_g1 (or p_g2) at location p_loc? Owner always; others need the grant AND an explicit assignment to that location.
create or replace function public._dl_ok127(p_loc int, p_g1 text, p_g2 text default null) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and p_loc is not null and exists (select 1 from public.locations l where l.id = p_loc) and (
    public.is_owner()
    or (exists (select 1 from public.user_locations ul where ul.user_id = auth.uid() and ul.location_id = p_loc)
        and (public.has_grant(p_g1, p_loc) or (p_g2 is not null and public.has_grant(p_g2, p_loc)))));
$$;

-- the locations the caller may use with grant p_g1 / p_g2
create or replace function public._dl_vis127(p_g1 text, p_g2 text default null) returns setof int
language sql stable security definer set search_path = public as $$
  select l.id from public.locations l where public._dl_ok127(l.id, p_g1, p_g2);
$$;

-- a business-level check: the caller holds the grant at some location of that business
create or replace function public._dl_biz_ok127(p_biz bigint, p_g1 text, p_g2 text default null) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and p_biz is not null and (public.is_owner()
    or exists (select 1 from public.locations l where public._dl_biz127(l.id) = p_biz and public._dl_ok127(l.id, p_g1, p_g2)));
$$;

create or replace function public._dl_today127() returns date
language sql stable set search_path = public as $$ select (now() at time zone 'Asia/Dhaka')::date; $$;

-- ---------- 2. tables ----------
create table if not exists public.dealer_cheques (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null unique,
  business_id bigint references public.org_units(id),
  location_id int not null references public.locations(id),
  direction text not null check (direction in ('received', 'issued')),
  party_kind text not null check (party_kind in ('customer', 'supplier', 'other')),
  customer_id uuid references public.customers(id),
  supplier_id uuid references public.suppliers(id),
  party_name text check (party_name is null or length(btrim(party_name)) between 1 and 120),
  bank_name text not null check (length(btrim(bank_name)) between 1 and 80),
  branch_name text check (branch_name is null or length(branch_name) <= 80),
  cheque_no text not null check (length(btrim(cheque_no)) between 1 and 40),
  amount numeric(16,2) not null check (amount > 0 and amount <= 1000000000000),
  cheque_date date not null check (cheque_date >= date '2000-01-01'),
  due_date date not null check (due_date >= date '2000-01-01'),
  status text not null default 'registered' check (status in ('registered', 'deposited', 'cleared', 'bounced', 'replaced', 'cancelled')),
  deposit_date date,
  bank_account_id bigint references public.coa_accounts(id),           -- our bank account (chart of accounts) the cheque goes through
  cleared_on date,
  ledger_kind text check (ledger_kind is null or ledger_kind in ('sale_payment', 'supplier_payment')),
  ledger_id bigint,                                                     -- sale_payments.id / supplier_payments.id written on CLEAR (the only money effect)
  bank_line_id bigint references public.bank_statement_lines(id),       -- bank reconciliation hook
  bounced_on date,
  bounce_reason text check (bounce_reason is null or length(bounce_reason) <= 200),
  bounce_charge numeric(16,2) not null default 0 check (bounce_charge >= 0 and bounce_charge <= 1000000000000),
  replaced_by uuid references public.dealer_cheques(id),
  replaces_id uuid references public.dealer_cheques(id),
  note text check (note is null or length(note) <= 300),
  created_by uuid, created_at timestamptz not null default now(),
  updated_by uuid, updated_at timestamptz not null default now(),
  check (due_date >= cheque_date),
  check ((party_kind = 'customer') = (customer_id is not null)),
  check ((party_kind = 'supplier') = (supplier_id is not null)),
  check (party_kind <> 'other' or party_name is not null),
  check (party_kind <> 'customer' or direction = 'received'),
  check (party_kind <> 'supplier' or direction = 'issued')
);
create unique index if not exists dealer_cheques_uq127 on public.dealer_cheques (coalesce(business_id, 0), direction, lower(btrim(bank_name)), lower(btrim(cheque_no))) where status <> 'cancelled';
create unique index if not exists dealer_cheques_bankline127 on public.dealer_cheques (bank_line_id) where bank_line_id is not null;
create index if not exists dealer_cheques_due127 on public.dealer_cheques (location_id, status, due_date);
create index if not exists dealer_cheques_cust127 on public.dealer_cheques (customer_id) where customer_id is not null;
create index if not exists dealer_cheques_sup127 on public.dealer_cheques (supplier_id) where supplier_id is not null;

create table if not exists public.dealer_cheque_events (
  id bigserial primary key,
  cheque_id uuid not null references public.dealer_cheques(id),
  location_id int not null references public.locations(id),
  action text not null check (action in ('registered', 'deposited', 'cleared', 'bounced', 'replaced', 'cancelled', 'bank_linked')),
  from_status text, to_status text,
  on_date date,
  amount numeric(16,2),
  ref text,
  note text,
  client_id uuid unique,
  actor uuid, at timestamptz not null default now()
);
create index if not exists dealer_cheque_events_ch127 on public.dealer_cheque_events (cheque_id, id);

create or replace function public._dl_append_only127() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end $$;

drop trigger if exists dealer_cheques_no_delete on public.dealer_cheques;
create trigger dealer_cheques_no_delete before delete on public.dealer_cheques for each row execute function public.no_hard_delete();
drop trigger if exists dealer_cheque_events_ro on public.dealer_cheque_events;
create trigger dealer_cheque_events_ro before update or delete on public.dealer_cheque_events for each row execute function public._dl_append_only127();
drop trigger if exists audit_dealer_cheques on public.dealer_cheques;
create trigger audit_dealer_cheques after insert or update on public.dealer_cheques for each row execute function public.log_change('id');

alter table public.dealer_cheques enable row level security;
alter table public.dealer_cheque_events enable row level security;
drop policy if exists dl_cheques_read127 on public.dealer_cheques;
create policy dl_cheques_read127 on public.dealer_cheques for select to authenticated using (public._dl_ok127(location_id, 'dealer_cheque_view', 'dealer_cheque_manage'));
drop policy if exists dl_cheque_events_read127 on public.dealer_cheque_events;
create policy dl_cheque_events_read127 on public.dealer_cheque_events for select to authenticated using (public._dl_ok127(location_id, 'dealer_cheque_view', 'dealer_cheque_manage'));
revoke all on public.dealer_cheques, public.dealer_cheque_events from public, anon, authenticated;
grant select on public.dealer_cheques, public.dealer_cheque_events to authenticated;
revoke all on sequence public.dealer_cheque_events_id_seq from public, anon, authenticated;

-- sale_payments.mode: also allow 'bank' (a cleared cheque is bank money). Existing rows / modes are unchanged; nothing existing writes 'bank' here.
do $m$ begin
  if exists (select 1 from pg_constraint where conrelid = 'public.sale_payments'::regclass and conname = 'sale_payments_mode_check' and pg_get_constraintdef(oid) !~ 'bank') then
    alter table public.sale_payments drop constraint sale_payments_mode_check;
    alter table public.sale_payments add constraint sale_payments_mode_check check (mode in ('cash', 'mobile', 'card', 'bank'));
  end if;
end $m$;

-- ---------- 3. internal helpers ----------
create or replace function public._cheque_gate127(p_loc int, p_manage boolean) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_manage then
    if not public._dl_ok127(p_loc, 'dealer_cheque_manage') then raise exception 'not allowed'; end if;
    if not public.rule_on('dealer_cheque_on') then raise exception 'feature_off'; end if;
  else
    if not public._dl_ok127(p_loc, 'dealer_cheque_view', 'dealer_cheque_manage') then raise exception 'not allowed'; end if;
  end if;
end $$;

-- insert one cheque row + its 'registered' event (used by cheque_register and cheque_replace)
create or replace function public._cheque_ins127(p_client uuid, p_loc int, p_dir text, p_kind text, p_party uuid, p_name text, p_bank text, p_branch text, p_no text,
  p_amount numeric, p_cdate date, p_due date, p_note text, p_replaces uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare amt numeric; due date; today date := public._dl_today127(); cid uuid; cu uuid; su uuid;
begin
  if p_client is null then raise exception 'client_required'; end if;
  if p_dir is null or p_dir not in ('received', 'issued') then raise exception 'bad_direction'; end if;
  if p_kind is null or p_kind not in ('customer', 'supplier', 'other') then raise exception 'bad_party_kind'; end if;
  if p_amount is null or p_amount = 'NaN'::numeric or not (abs(p_amount) <= 1000000000000) then raise exception 'bad_amount'; end if;
  amt := round(p_amount, 2);
  if amt <= 0 then raise exception 'bad_amount'; end if;
  if p_bank is null or length(btrim(p_bank)) not between 1 and 80 then raise exception 'bank_required'; end if;
  if p_no is null or length(btrim(p_no)) not between 1 and 40 then raise exception 'cheque_no_required'; end if;
  if p_branch is not null and length(p_branch) > 80 then raise exception 'branch_too_long'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'note_too_long'; end if;
  if p_cdate is null or p_cdate < today - 366 or p_cdate > today + 730 then raise exception 'bad_cheque_date'; end if;
  due := coalesce(p_due, p_cdate);
  if due < p_cdate or due > p_cdate + 366 then raise exception 'bad_due_date'; end if;
  if p_kind = 'customer' then
    if p_dir <> 'received' then raise exception 'customer_cheque_is_received'; end if;
    select id into cu from public.customers where id = p_party and active; if cu is null then raise exception 'customer_not_found'; end if;
  elsif p_kind = 'supplier' then
    if p_dir <> 'issued' then raise exception 'supplier_cheque_is_issued'; end if;
    select id into su from public.suppliers where id = p_party and active; if su is null then raise exception 'supplier_not_found'; end if;
  else
    if p_name is null or length(btrim(p_name)) not between 1 and 120 then raise exception 'party_name_required'; end if;
  end if;
  begin
    insert into public.dealer_cheques (client_id, business_id, location_id, direction, party_kind, customer_id, supplier_id, party_name, bank_name, branch_name, cheque_no,
        amount, cheque_date, due_date, replaces_id, note, created_by, updated_by)
      values (p_client, public._dl_biz127(p_loc), p_loc, p_dir, p_kind, cu, su, nullif(btrim(coalesce(p_name, '')), ''), btrim(p_bank), nullif(btrim(coalesce(p_branch, '')), ''), btrim(p_no),
        amt, p_cdate, due, p_replaces, nullif(btrim(coalesce(p_note, '')), ''), auth.uid(), auth.uid())
      returning id into cid;
  exception when unique_violation then raise exception 'duplicate_cheque';
  end;
  insert into public.dealer_cheque_events (cheque_id, location_id, action, from_status, to_status, on_date, amount, ref, note, client_id, actor)
    values (cid, p_loc, 'registered', null, 'registered', today, amt, case when p_replaces is not null then 'replaces ' || p_replaces::text end, left(p_note, 300), p_client, auth.uid());
  return cid;
end $$;

-- ---------- 4. write functions (browser) ----------
create or replace function public.cheque_register(p_client uuid, p_loc int, p_dir text, p_party_kind text, p_party uuid, p_party_name text, p_bank text, p_branch text,
  p_no text, p_amount numeric, p_cheque_date date, p_due_date date default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.dealer_cheques; cid uuid;
begin
  perform public._cheque_gate127(p_loc, true);
  if p_client is null then raise exception 'client_required'; end if;
  perform public._client_lock(p_client);
  select * into c from public.dealer_cheques where client_id = p_client;
  if found then
    if not public._dl_ok127(c.location_id, 'dealer_cheque_manage') then raise exception 'not allowed'; end if;
    return jsonb_build_object('id', c.id, 'status', c.status, 'dup', true);
  end if;
  cid := public._cheque_ins127(p_client, p_loc, p_dir, p_party_kind, p_party, p_party_name, p_bank, p_branch, p_no, p_amount, p_cheque_date, p_due_date, p_note, null);
  return jsonb_build_object('id', cid, 'status', 'registered');
end $$;

-- common: load + lock one cheque, check scope; a step key already used on ANOTHER cheque is refused
create or replace function public._cheque_load127(p_id uuid, p_client uuid) returns public.dealer_cheques
language plpgsql security definer set search_path = public as $$
declare c public.dealer_cheques;
begin
  if p_client is not null then perform public._client_lock(p_client); end if;
  select * into c from public.dealer_cheques where id = p_id;
  if not found then raise exception 'cheque_not_found'; end if;
  perform public._cheque_gate127(c.location_id, true);
  if p_client is not null and exists (select 1 from public.dealer_cheque_events e where e.client_id = p_client and e.cheque_id <> p_id) then raise exception 'client_key_used'; end if;
  select * into c from public.dealer_cheques where id = p_id for update;
  return c;
end $$;
create or replace function public._cheque_dup127(p_id uuid, p_client uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select p_client is not null and exists (select 1 from public.dealer_cheque_events e where e.client_id = p_client and e.cheque_id = p_id);
$$;

create or replace function public.cheque_deposit(p_id uuid, p_date date, p_bank_account bigint default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.dealer_cheques; today date := public._dl_today127();
begin
  c := public._cheque_load127(p_id, p_client);
  if public._cheque_dup127(p_id, p_client) then return jsonb_build_object('id', c.id, 'status', c.status, 'dup', true); end if;
  if c.status <> 'registered' then raise exception 'bad_status'; end if;
  if p_date is null or p_date < c.cheque_date or p_date > today then raise exception 'bad_date'; end if;
  if p_bank_account is not null and not exists (select 1 from public.coa_accounts a where a.id = p_bank_account) then raise exception 'bad_bank_account'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'note_too_long'; end if;
  perform public.lock_check(p_date);
  update public.dealer_cheques set status = 'deposited', deposit_date = p_date, bank_account_id = coalesce(p_bank_account, bank_account_id), updated_by = auth.uid(), updated_at = now() where id = c.id;
  insert into public.dealer_cheque_events (cheque_id, location_id, action, from_status, to_status, on_date, amount, note, client_id, actor)
    values (c.id, c.location_id, 'deposited', c.status, 'deposited', p_date, c.amount, left(p_note, 300), p_client, auth.uid());
  return jsonb_build_object('id', c.id, 'status', 'deposited');
end $$;

-- CLEAR: the only step that moves money in a party ledger. p_dry = true checks everything and returns the numbers, writes nothing.
create or replace function public.cheque_clear(p_id uuid, p_date date, p_note text default null, p_client uuid default null, p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.dealer_cheques; today date := public._dl_today127(); bal numeric; lid bigint; sid text; at_ timestamptz; kind text;
begin
  c := public._cheque_load127(p_id, p_client);
  if public._cheque_dup127(p_id, p_client) then return jsonb_build_object('id', c.id, 'status', c.status, 'dup', true); end if;
  if c.status <> 'deposited' then raise exception 'bad_status'; end if;
  if p_date is null or p_date < c.deposit_date or p_date > today then raise exception 'bad_date'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'note_too_long'; end if;
  perform public.lock_check(p_date);
  if c.party_kind = 'customer' then
    perform 1 from public.customers where id = c.customer_id for no key update;           -- one posting at a time per customer
    bal := public._cust_bal(c.customer_id); kind := 'sale_payment';
    if c.amount > bal then raise exception 'overpaid'; end if;
  elsif c.party_kind = 'supplier' then
    perform 1 from public.suppliers where id = c.supplier_id for no key update;
    bal := public._sup_balance(c.supplier_id); kind := 'supplier_payment';
    if c.amount > bal then raise exception 'overpaid'; end if;
  end if;
  if p_dry then
    return jsonb_build_object('dry', true, 'id', c.id, 'amount', c.amount, 'ledger', kind, 'balance_before', bal, 'balance_after', case when bal is not null then bal - c.amount end);
  end if;
  at_ := (p_date::timestamp + time '12:00') at time zone 'Asia/Dhaka';
  select staff_id into sid from public.profiles where id = auth.uid();
  if c.party_kind = 'customer' then
    insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, ref, amount, paid_at, note, created_by, created_staff, client_id)
      values (null, c.customer_id, c.location_id, 'collection', 'bank', left('CHQ ' || c.bank_name || ' ' || c.cheque_no, 60), c.amount, at_, left(coalesce(p_note, 'cheque cleared'), 200), auth.uid(), sid, c.id)
      returning id into lid;
  elsif c.party_kind = 'supplier' then
    insert into public.supplier_payments (supplier_id, location_id, bill_id, mode, ref, amount, paid_at, note, created_by, created_staff, client_id)
      values (c.supplier_id, c.location_id, null, 'bank', left('CHQ ' || c.bank_name || ' ' || c.cheque_no, 60), c.amount, at_, left(coalesce(p_note, 'cheque cleared'), 200), auth.uid(), sid, c.id)
      returning id into lid;
  end if;
  update public.dealer_cheques set status = 'cleared', cleared_on = p_date, ledger_kind = kind, ledger_id = lid, updated_by = auth.uid(), updated_at = now() where id = c.id;
  insert into public.dealer_cheque_events (cheque_id, location_id, action, from_status, to_status, on_date, amount, ref, note, client_id, actor)
    values (c.id, c.location_id, 'cleared', c.status, 'cleared', p_date, c.amount, case when lid is not null then kind || ':' || lid::text end, left(p_note, 300), p_client, auth.uid());
  return jsonb_build_object('id', c.id, 'status', 'cleared', 'amount', c.amount, 'ledger', kind, 'ledger_id', lid, 'balance_after', case when bal is not null then bal - c.amount end);
end $$;

-- BOUNCE: no ledger effect. The reason is required; the bank charge is only recorded.
create or replace function public.cheque_bounce(p_id uuid, p_date date, p_reason text, p_charge numeric default 0, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.dealer_cheques; today date := public._dl_today127(); chg numeric;
begin
  c := public._cheque_load127(p_id, p_client);
  if public._cheque_dup127(p_id, p_client) then return jsonb_build_object('id', c.id, 'status', c.status, 'dup', true); end if;
  if c.status <> 'deposited' then raise exception 'bad_status'; end if;
  if p_date is null or p_date < c.deposit_date or p_date > today then raise exception 'bad_date'; end if;
  if p_reason is null or length(btrim(p_reason)) not between 1 and 200 then raise exception 'reason_required'; end if;
  if p_charge is null or p_charge = 'NaN'::numeric or not (p_charge between 0 and 1000000000000) then raise exception 'bad_amount'; end if;
  chg := round(p_charge, 2);
  perform public.lock_check(p_date);
  update public.dealer_cheques set status = 'bounced', bounced_on = p_date, bounce_reason = btrim(p_reason), bounce_charge = chg, updated_by = auth.uid(), updated_at = now() where id = c.id;
  insert into public.dealer_cheque_events (cheque_id, location_id, action, from_status, to_status, on_date, amount, ref, note, client_id, actor)
    values (c.id, c.location_id, 'bounced', c.status, 'bounced', p_date, c.amount, 'charge ' || chg::text, left(btrim(p_reason) || coalesce(' / ' || p_note, ''), 300), p_client, auth.uid());
  return jsonb_build_object('id', c.id, 'status', 'bounced', 'bounce_charge', chg);
end $$;

create or replace function public.cheque_cancel(p_id uuid, p_reason text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.dealer_cheques;
begin
  c := public._cheque_load127(p_id, p_client);
  if public._cheque_dup127(p_id, p_client) then return jsonb_build_object('id', c.id, 'status', c.status, 'dup', true); end if;
  if c.status not in ('registered', 'bounced') then raise exception 'bad_status'; end if;
  if p_reason is null or length(btrim(p_reason)) not between 1 and 200 then raise exception 'reason_required'; end if;
  update public.dealer_cheques set status = 'cancelled', updated_by = auth.uid(), updated_at = now() where id = c.id;
  insert into public.dealer_cheque_events (cheque_id, location_id, action, from_status, to_status, on_date, amount, note, client_id, actor)
    values (c.id, c.location_id, 'cancelled', c.status, 'cancelled', public._dl_today127(), c.amount, btrim(p_reason), p_client, auth.uid());
  return jsonb_build_object('id', c.id, 'status', 'cancelled');
end $$;

-- REPLACE a bounced cheque by a new one (new registered cheque, same party and direction; the old one becomes 'replaced'). p_client is the key of the NEW cheque.
create or replace function public.cheque_replace(p_old uuid, p_client uuid, p_bank text, p_branch text, p_no text, p_amount numeric, p_cheque_date date, p_due_date date default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.dealer_cheques; n public.dealer_cheques; nid uuid;
begin
  if p_client is null then raise exception 'client_required'; end if;
  perform public._client_lock(p_client);
  select * into o from public.dealer_cheques where id = p_old;
  if not found then raise exception 'cheque_not_found'; end if;
  perform public._cheque_gate127(o.location_id, true);
  select * into n from public.dealer_cheques where client_id = p_client;
  if found then
    if n.replaces_id is distinct from p_old then raise exception 'client_key_used'; end if;
    return jsonb_build_object('id', n.id, 'old', p_old, 'status', n.status, 'dup', true);
  end if;
  select * into o from public.dealer_cheques where id = p_old for update;
  if o.status <> 'bounced' then raise exception 'bad_status'; end if;
  nid := public._cheque_ins127(p_client, o.location_id, o.direction, o.party_kind, coalesce(o.customer_id, o.supplier_id), o.party_name, p_bank, p_branch, p_no, p_amount, p_cheque_date, p_due_date, p_note, o.id);
  update public.dealer_cheques set status = 'replaced', replaced_by = nid, updated_by = auth.uid(), updated_at = now() where id = o.id;
  insert into public.dealer_cheque_events (cheque_id, location_id, action, from_status, to_status, on_date, amount, ref, actor)
    values (o.id, o.location_id, 'replaced', 'bounced', 'replaced', public._dl_today127(), o.amount, 'by ' || nid::text, auth.uid());
  return jsonb_build_object('id', nid, 'old', o.id, 'status', 'registered');
end $$;

-- ---------- 5. bank reconciliation hook ----------
-- candidates: cleared cheques with our bank account set and no statement line yet, vs statement lines of that account with the same signed amount (+ received, - issued) within 10 days of the clear date
create or replace function public.cheque_bank_candidates(p_business bigint default null)
returns table (cheque_id uuid, direction text, cheque_no text, amount numeric, cleared_on date, line_id bigint, line_date date, line_amount numeric, line_reference text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query
    select c.id, c.direction, c.cheque_no, c.amount, c.cleared_on, l.id, l.line_date, l.amount, l.reference
    from public.dealer_cheques c join public.bank_statement_lines l on l.account_id = c.bank_account_id
      and l.amount = case when c.direction = 'received' then c.amount else -c.amount end and abs(l.line_date - c.cleared_on) <= 10
    where c.status = 'cleared' and c.bank_line_id is null and c.bank_account_id is not null
      and c.location_id in (select public._dl_vis127('dealer_cheque_manage')) and (p_business is null or c.business_id = p_business)
      and not exists (select 1 from public.dealer_cheques x where x.bank_line_id = l.id)
    order by c.cleared_on, c.id, l.line_date, l.id;
end $$;

create or replace function public.cheque_bank_link(p_id uuid, p_line bigint, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.dealer_cheques; l public.bank_statement_lines;
begin
  c := public._cheque_load127(p_id, p_client);
  if public._cheque_dup127(p_id, p_client) then return jsonb_build_object('id', c.id, 'bank_line_id', c.bank_line_id, 'dup', true); end if;
  if c.status <> 'cleared' then raise exception 'bad_status'; end if;
  if c.bank_account_id is null then raise exception 'bank_account_missing'; end if;
  if c.bank_line_id is not null then raise exception 'already_linked'; end if;
  select * into l from public.bank_statement_lines where id = p_line;
  if not found then raise exception 'line_not_found'; end if;
  if l.account_id <> c.bank_account_id then raise exception 'wrong_bank_account'; end if;
  if l.amount <> (case when c.direction = 'received' then c.amount else -c.amount end) then raise exception 'amount_mismatch'; end if;
  begin
    update public.dealer_cheques set bank_line_id = p_line, updated_by = auth.uid(), updated_at = now() where id = c.id;
  exception when unique_violation then raise exception 'line_already_used';
  end;
  insert into public.dealer_cheque_events (cheque_id, location_id, action, from_status, to_status, on_date, amount, ref, client_id, actor)
    values (c.id, c.location_id, 'bank_linked', c.status, c.status, public._dl_today127(), c.amount, 'line ' || p_line::text, p_client, auth.uid());
  return jsonb_build_object('id', c.id, 'bank_line_id', p_line);
end $$;

-- ---------- 6. reads ----------
create or replace function public._cheque_party127(c public.dealer_cheques) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select name from public.customers where id = c.customer_id), (select name from public.suppliers where id = c.supplier_id), c.party_name);
$$;

create or replace function public.cheque_list(p_business bigint default null, p_status text default null, p_dir text default null, p_limit int default 200)
returns table (id uuid, location_id int, direction text, party_kind text, party_name text, bank_name text, cheque_no text, amount numeric, cheque_date date, due_date date,
  status text, deposit_date date, cleared_on date, bounced_on date, bounce_reason text, bounce_charge numeric, replaced_by uuid, replaces_id uuid, bank_line_id bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_status is not null and p_status not in ('registered', 'deposited', 'cleared', 'bounced', 'replaced', 'cancelled') then raise exception 'bad_status'; end if;
  if p_dir is not null and p_dir not in ('received', 'issued') then raise exception 'bad_direction'; end if;
  return query
    select c.id, c.location_id, c.direction, c.party_kind, public._cheque_party127(c), c.bank_name, c.cheque_no, c.amount, c.cheque_date, c.due_date, c.status, c.deposit_date, c.cleared_on,
           c.bounced_on, c.bounce_reason, c.bounce_charge, c.replaced_by, c.replaces_id, c.bank_line_id
    from public.dealer_cheques c
    where c.location_id in (select public._dl_vis127('dealer_cheque_view', 'dealer_cheque_manage'))
      and (p_business is null or c.business_id = p_business) and (p_status is null or c.status = p_status) and (p_dir is null or c.direction = p_dir)
    order by c.due_date desc, c.created_at desc limit greatest(1, least(coalesce(p_limit, 200), 1000));
end $$;

-- cheques still to be deposited / cleared whose due date is within p_days (overdue ones included), with an aging bucket
create or replace function public.cheques_due(p_business bigint default null, p_days int default 7, p_dir text default null, p_asof date default null)
returns table (id uuid, location_id int, direction text, party_name text, bank_name text, cheque_no text, amount numeric, cheque_date date, due_date date, status text, days_to_due int, bucket text)
language plpgsql stable security definer set search_path = public as $$
declare a date := coalesce(p_asof, public._dl_today127());
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_days is null or p_days < 0 or p_days > 3650 then raise exception 'bad_days'; end if;
  if p_dir is not null and p_dir not in ('received', 'issued') then raise exception 'bad_direction'; end if;
  return query
    select c.id, c.location_id, c.direction, public._cheque_party127(c), c.bank_name, c.cheque_no, c.amount, c.cheque_date, c.due_date, c.status, (c.due_date - a),
           case when c.due_date < a then 'overdue' when c.due_date = a then 'today' when c.due_date <= a + 7 then 'this_week' else 'later' end
    from public.dealer_cheques c
    where c.status in ('registered', 'deposited') and c.due_date <= a + p_days
      and c.location_id in (select public._dl_vis127('dealer_cheque_view', 'dealer_cheque_manage'))
      and (p_business is null or c.business_id = p_business) and (p_dir is null or c.direction = p_dir)
    order by c.due_date, c.id;
end $$;

create or replace function public.cheques_bounced(p_business bigint default null, p_from date default null, p_to date default null)
returns table (id uuid, location_id int, direction text, party_name text, bank_name text, cheque_no text, amount numeric, bounced_on date, bounce_reason text, bounce_charge numeric, status text, replaced_by uuid)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query
    select c.id, c.location_id, c.direction, public._cheque_party127(c), c.bank_name, c.cheque_no, c.amount, c.bounced_on, c.bounce_reason, c.bounce_charge, c.status, c.replaced_by
    from public.dealer_cheques c
    where c.bounced_on is not null and (p_from is null or c.bounced_on >= p_from) and (p_to is null or c.bounced_on <= p_to)
      and c.location_id in (select public._dl_vis127('dealer_cheque_view', 'dealer_cheque_manage')) and (p_business is null or c.business_id = p_business)
    order by c.bounced_on desc, c.id;
end $$;

-- post-dated exposure per party: cheques not yet cleared whose cheque date is still in the future
-- (received = money we expect and have not got; issued = money we have promised and have not paid)
create or replace function public.post_dated_exposure(p_business bigint default null, p_dir text default null, p_asof date default null)
returns table (direction text, party_kind text, party_id uuid, party_name text, cheques int, total numeric, earliest_due date, latest_due date)
language plpgsql stable security definer set search_path = public as $$
declare a date := coalesce(p_asof, public._dl_today127());
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_dir is not null and p_dir not in ('received', 'issued') then raise exception 'bad_direction'; end if;
  return query
    select c.direction, c.party_kind, coalesce(c.customer_id, c.supplier_id), max(public._cheque_party127(c)), count(*)::int, sum(c.amount), min(c.due_date), max(c.due_date)
    from public.dealer_cheques c
    where c.status in ('registered', 'deposited') and c.cheque_date > a
      and c.location_id in (select public._dl_vis127('dealer_cheque_view', 'dealer_cheque_manage')) and (p_business is null or c.business_id = p_business) and (p_dir is null or c.direction = p_dir)
    group by c.direction, c.party_kind, coalesce(c.customer_id, c.supplier_id), case when c.party_kind = 'other' then lower(btrim(c.party_name)) end
    order by 6 desc, 4;
end $$;

-- control: cleared cheques whose ledger payment was voided elsewhere (void_collection / void_supplier_payment) - the cheque would still say cleared
create or replace function public.cheque_ledger_check(p_business bigint default null)
returns table (id uuid, direction text, cheque_no text, amount numeric, cleared_on date, ledger_kind text, ledger_id bigint, problem text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query
    select z.* from (
      select c.id, c.direction, c.cheque_no, c.amount, c.cleared_on, c.ledger_kind, c.ledger_id,
        case when c.ledger_kind = 'sale_payment' and not exists (select 1 from public.sale_payments p where p.id = c.ledger_id and not p.voided and p.amount = c.amount) then 'ledger_payment_voided_or_changed'
             when c.ledger_kind = 'supplier_payment' and not exists (select 1 from public.supplier_payments p where p.id = c.ledger_id and not p.voided and p.amount = c.amount) then 'ledger_payment_voided_or_changed'
             when c.ledger_kind is null and c.party_kind <> 'other' then 'ledger_link_missing' end as problem
      from public.dealer_cheques c
      where c.status = 'cleared' and c.location_id in (select public._dl_vis127('dealer_cheque_view', 'dealer_cheque_manage')) and (p_business is null or c.business_id = p_business)) z
    where z.problem is not null order by z.cleared_on, z.id;
end $$;

-- history of one cheque
create or replace function public.cheque_events(p_id uuid)
returns table (at timestamptz, action text, from_status text, to_status text, on_date date, amount numeric, ref text, note text)
language plpgsql stable security definer set search_path = public as $$
declare c public.dealer_cheques;
begin
  select * into c from public.dealer_cheques where id = p_id;
  if not found then raise exception 'cheque_not_found'; end if;
  perform public._cheque_gate127(c.location_id, false);
  return query select e.at, e.action, e.from_status, e.to_status, e.on_date, e.amount, e.ref, e.note from public.dealer_cheque_events e where e.cheque_id = p_id order by e.id;
end $$;

-- ---------- 7. grants on functions ----------
revoke all on function public._dl_biz127(int), public._dl_ok127(int, text, text), public._dl_vis127(text, text), public._dl_biz_ok127(bigint, text, text), public._dl_today127(),
  public._dl_append_only127(), public._cheque_gate127(int, boolean), public._cheque_ins127(uuid, int, text, text, uuid, text, text, text, text, numeric, date, date, text, uuid),
  public._cheque_load127(uuid, uuid), public._cheque_dup127(uuid, uuid), public._cheque_party127(public.dealer_cheques) from public, anon, authenticated;
revoke all on function public.cheque_register(uuid, int, text, text, uuid, text, text, text, text, numeric, date, date, text), public.cheque_deposit(uuid, date, bigint, text, uuid),
  public.cheque_clear(uuid, date, text, uuid, boolean), public.cheque_bounce(uuid, date, text, numeric, text, uuid), public.cheque_cancel(uuid, text, uuid),
  public.cheque_replace(uuid, uuid, text, text, text, numeric, date, date, text), public.cheque_bank_candidates(bigint), public.cheque_bank_link(uuid, bigint, uuid),
  public.cheque_list(bigint, text, text, int), public.cheques_due(bigint, int, text, date), public.cheques_bounced(bigint, date, date),
  public.post_dated_exposure(bigint, text, date), public.cheque_ledger_check(bigint), public.cheque_events(uuid) from public, anon;
grant execute on function public.cheque_register(uuid, int, text, text, uuid, text, text, text, text, numeric, date, date, text), public.cheque_deposit(uuid, date, bigint, text, uuid),
  public.cheque_clear(uuid, date, text, uuid, boolean), public.cheque_bounce(uuid, date, text, numeric, text, uuid), public.cheque_cancel(uuid, text, uuid),
  public.cheque_replace(uuid, uuid, text, text, text, numeric, date, date, text), public.cheque_bank_candidates(bigint), public.cheque_bank_link(uuid, bigint, uuid),
  public.cheque_list(bigint, text, text, int), public.cheques_due(bigint, int, text, date), public.cheques_bounced(bigint, date, date),
  public.post_dated_exposure(bigint, text, date), public.cheque_ledger_check(bigint), public.cheque_events(uuid) to authenticated;
-- the row policies call it as the signed-in user (it only answers about the caller's own rights)
grant execute on function public._dl_ok127(int, text, text) to authenticated;

commit;

-- ---------------------------------------------------------------- phase128.sql
-- ============================================================
-- Phase 128 (marker dl128) - DEALER / HARDWARE-PAINT BUSINESS, part 2: principal SCHEME engine (ADDITIVE ONLY).
-- Canonical order: after phase127 (uses its scope helpers _dl_ok127 / _dl_biz127 / _dl_biz_ok127). Paste twice = no change, no error.
-- Rule dealer_scheme_on is OFF by default: while OFF every write function refuses ('feature_off'); previews (dry runs) and reads still work.
--   A "principal" is simply a row of suppliers (owner data - Asian / Berger / Classic or any other name; nothing is hardcoded).
--   Table dealer_schemes        one scheme of one principal for ONE business: kind slab | target | flat_pack, basis purchase | sale, measure value | qty,
--                               valid_from .. valid_to, status draft | active | closed | cancelled. Rules are editable only while draft (an active scheme is frozen).
--   Table dealer_scheme_items   optional item scope (no rows = every line of the principal's bills). A sale-based scheme MUST have an item scope
--                               (sales do not know the principal) - checked when the scheme is activated.
--   Table dealer_scheme_slabs   slab rows (from, to, rate %): used by kind slab. mode whole = the rate of the slab the total falls in applies to the WHOLE
--                               base value (retro); mode marginal = each slice of value earns its own slab rate (value measure only).
--   Table dealer_scheme_accruals  append-only: every accrual run writes delta = earned-to-date - already accrued (can be negative after a purchase return).
--   Table dealer_scheme_claims / dealer_scheme_claim_events  the claim register to the principal: submitted -> part_settled -> settled | rejected | cancelled;
--                               receipts are append-only events. A claim can never exceed the accrued-but-unclaimed amount of its scheme.
--   Base figures (nothing invented): purchase basis = lines of POSTED bills of that supplier at the locations of the business, bill date inside the scheme
--     period and up to the accrual date, returns counted negative; amount = the line amount as entered (before the bill-level discount). Sale basis = lines of
--     DONE sales at the locations of the business, in the item scope; amount = line amount as recorded. Sale returns are NOT netted (not built).
--   Earned amounts: slab (whole / marginal), target (reached when the measure >= target: pct of base value + flat amount, both entered), flat_pack
--     (amount per pack x net pack quantity). Everything is rounded to 2 places once, at the end. Never below 0.
--   scheme_accrue(.., p_dry := true) is the PREVIEW: it writes nothing and returns base, earned-to-date, already accrued and the delta.
--   Nothing is posted to the books or the supplier ledger by this phase (accruals and receipts are a register; the accountant decides the entries).
--   Reports: scheme_reconciliation (accrued vs claimed vs received, unclaimed, outstanding), claim_list, scheme_list / scheme_get.
--   Grants dealer_scheme_view, dealer_scheme_manage. Business scope exactly as phase127 (owner, or explicitly assigned location + grant, inside that business).
-- Rollback: leave dealer_scheme_on OFF. To remove: drop the functions and the six tables (nothing else refers to them).
-- ============================================================
begin;

do $g$
declare miss text := '';
begin
  if to_regclass('public.dealer_cheques') is null or to_regprocedure('public._dl_ok127(integer,text,text)') is null or to_regprocedure('public._dl_biz_ok127(bigint,text,text)') is null
     or to_regprocedure('public._dl_biz127(integer)') is null or to_regclass('public.dl_unit_tree127') is null then miss := miss || ' phase127'; end if;
  if to_regclass('public.purchase_bills') is null or to_regclass('public.purchase_lines') is null or to_regclass('public.sales') is null or to_regclass('public.suppliers') is null
     or to_regclass('public.items') is null then miss := miss || ' tables'; end if;
  if miss <> '' then raise exception 'phase128 needs the base schema and phases up to 127 pasted first (docs/PASTE_ORDER.md); missing:%', miss; end if;
end $g$;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
select v.c, 'dealer', v.s, v.b, v.m, v.e, 'once' from (values
  ('dealer_scheme_view', 129, 'প্রিন্সিপাল স্কিম, ক্লেইম ও মিলানো রিপোর্ট দেখা', 'Principal scheme, claim ও reconciliation report দেখা', 'View principal schemes, claims and the reconciliation report'),
  ('dealer_scheme_manage', 130, 'প্রিন্সিপাল স্কিম তৈরি, হিসাব তোলা, ক্লেইম', 'Principal scheme তৈরি, accrual, claim', 'Create schemes, accrue, make and settle claims')
) v(c, s, b, m, e) where not exists (select 1 from public.grant_defs g where g.grant_code = v.c);

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('dealer_scheme_on', 'dealer', 'switch', 'false', null, null, null, null,
  'প্রিন্সিপাল স্কিম চালু', 'Principal scheme চালু', 'Principal schemes',
  'চালু করলে স্কিম, হিসাব তোলা (accrual) ও ক্লেইম লেখা যাবে। শুধু আপনার দেওয়া নিয়ম থেকে অঙ্ক হয়; কিছু বাড়িয়ে ধরা হয় না।',
  'চালু করলে scheme, accrual ও claim লেখা যাবে। শুধু আপনার দেওয়া rule থেকে অঙ্ক হয়; কিছু বাড়িয়ে ধরা হয় না।',
  'When on, schemes, accruals and claims can be written. Amounts come only from the rules you enter; nothing is invented.', 1280)
on conflict (key) do nothing;

insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort)
select 'dealer_scheme_on', 'dealer_scheme_on', '128', 'dealer', null::jsonb, '{}'::text[],
  'যে ব্যবসায় প্রিন্সিপালের স্কিম/রিবেট আছে শুধু সেখানে চালু করুন।', 'যে business এ principal এর scheme/rebate আছে শুধু সেখানে চালু করুন।',
  'Turn on only for a business that earns principal schemes / rebates.', 1280
where not exists (select 1 from public.setup_rec_defs81 where code = 'dealer_scheme_on');

-- ---------- tables ----------
create table if not exists public.dealer_schemes (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null unique,
  business_id bigint not null references public.org_units(id),
  supplier_id uuid not null references public.suppliers(id),
  name text not null check (length(btrim(name)) between 1 and 120),
  kind text not null check (kind in ('slab', 'target', 'flat_pack')),
  basis text not null check (basis in ('purchase', 'sale')),
  measure text not null default 'value' check (measure in ('value', 'qty')),
  slab_mode text not null default 'whole' check (slab_mode in ('whole', 'marginal')),
  valid_from date not null check (valid_from >= date '2000-01-01'),
  valid_to date not null,
  target_amount numeric(18,4) check (target_amount is null or (target_amount > 0 and target_amount <= 1000000000000)),
  rebate_pct numeric(9,4) check (rebate_pct is null or (rebate_pct >= 0 and rebate_pct <= 100)),
  rebate_flat numeric(16,2) check (rebate_flat is null or (rebate_flat >= 0 and rebate_flat <= 1000000000000)),
  per_pack_amount numeric(16,4) check (per_pack_amount is null or (per_pack_amount > 0 and per_pack_amount <= 1000000000)),
  status text not null default 'draft' check (status in ('draft', 'active', 'closed', 'cancelled')),
  note text check (note is null or length(note) <= 300),
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now(),
  check (valid_to >= valid_from and valid_to <= valid_from + 1830),
  check (kind <> 'flat_pack' or (per_pack_amount is not null and measure = 'qty')),
  check (kind <> 'target' or (target_amount is not null and (rebate_pct is not null or rebate_flat is not null))),
  check (kind <> 'slab' or slab_mode = 'whole' or measure = 'value')
);
create index if not exists dealer_schemes_biz128 on public.dealer_schemes (business_id, status);
create index if not exists dealer_schemes_sup128 on public.dealer_schemes (supplier_id);

create table if not exists public.dealer_scheme_items (
  scheme_id uuid not null references public.dealer_schemes(id),
  item_id uuid not null references public.items(id),
  business_id bigint not null references public.org_units(id),
  primary key (scheme_id, item_id)
);
create table if not exists public.dealer_scheme_slabs (
  scheme_id uuid not null references public.dealer_schemes(id),
  seq int not null check (seq >= 1),
  from_amt numeric(18,4) not null check (from_amt >= 0),
  to_amt numeric(18,4) check (to_amt is null or to_amt > from_amt),
  rate_pct numeric(9,4) not null check (rate_pct >= 0 and rate_pct <= 100),
  business_id bigint not null references public.org_units(id),
  primary key (scheme_id, seq)
);
create table if not exists public.dealer_scheme_accruals (
  id bigserial primary key,
  scheme_id uuid not null references public.dealer_schemes(id),
  business_id bigint not null references public.org_units(id),
  upto_date date not null,
  base_value numeric(18,2) not null,
  base_qty numeric(18,4) not null,
  earned_to_date numeric(16,2) not null check (earned_to_date >= 0),
  delta numeric(16,2) not null,
  note text,
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now()
);
create index if not exists dealer_scheme_accruals_s128 on public.dealer_scheme_accruals (scheme_id, id);
create table if not exists public.dealer_scheme_claims (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null unique,
  business_id bigint not null references public.org_units(id),
  scheme_id uuid not null references public.dealer_schemes(id),
  supplier_id uuid not null references public.suppliers(id),
  claim_no text check (claim_no is null or length(claim_no) <= 40),
  claim_date date not null,
  amount numeric(16,2) not null check (amount > 0 and amount <= 1000000000000),
  status text not null default 'submitted' check (status in ('submitted', 'part_settled', 'settled', 'rejected', 'cancelled')),
  note text check (note is null or length(note) <= 300),
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now()
);
create unique index if not exists dealer_scheme_claims_no128 on public.dealer_scheme_claims (supplier_id, lower(claim_no)) where claim_no is not null and status <> 'cancelled';
create index if not exists dealer_scheme_claims_s128 on public.dealer_scheme_claims (scheme_id, status);
create table if not exists public.dealer_scheme_claim_events (
  id bigserial primary key,
  claim_id uuid not null references public.dealer_scheme_claims(id),
  business_id bigint not null references public.org_units(id),
  kind text not null check (kind in ('submitted', 'received', 'rejected', 'cancelled')),
  amount numeric(16,2),
  on_date date,
  ref text check (ref is null or length(ref) <= 80),
  note text,
  client_id uuid unique,
  actor uuid, at timestamptz not null default now()
);
create index if not exists dealer_scheme_claim_events_c128 on public.dealer_scheme_claim_events (claim_id, id);

-- append-only records
drop trigger if exists dealer_scheme_accruals_ro on public.dealer_scheme_accruals;
create trigger dealer_scheme_accruals_ro before update or delete on public.dealer_scheme_accruals for each row execute function public._dl_append_only127();
drop trigger if exists dealer_scheme_claim_events_ro on public.dealer_scheme_claim_events;
create trigger dealer_scheme_claim_events_ro before update or delete on public.dealer_scheme_claim_events for each row execute function public._dl_append_only127();
do $t$ declare t text; begin
  foreach t in array array['dealer_schemes', 'dealer_scheme_items', 'dealer_scheme_slabs', 'dealer_scheme_claims'] loop
    -- slabs / items are replaced while a scheme is a draft: a delete there is allowed only through scheme_save (it removes rows of a DRAFT scheme)
    if t in ('dealer_schemes', 'dealer_scheme_claims') then
      execute format('drop trigger if exists %I on public.%I', t || '_no_delete', t);
      execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_no_delete', t);
    end if;
  end loop;
end $t$;
drop trigger if exists audit_dealer_schemes on public.dealer_schemes;
create trigger audit_dealer_schemes after insert or update on public.dealer_schemes for each row execute function public.log_change('id');
drop trigger if exists audit_dealer_scheme_claims on public.dealer_scheme_claims;
create trigger audit_dealer_scheme_claims after insert or update on public.dealer_scheme_claims for each row execute function public.log_change('id');

-- a scheme row is frozen once it left draft (rules cannot be rewritten under existing accruals); only status / note / audit columns move
create or replace function public._scheme_frozen128() returns trigger language plpgsql set search_path = public as $$
begin
  if old.status <> 'draft' and (new.business_id, new.supplier_id, new.name, new.kind, new.basis, new.measure, new.slab_mode, new.valid_from, new.valid_to, new.target_amount, new.rebate_pct, new.rebate_flat, new.per_pack_amount)
     is distinct from (old.business_id, old.supplier_id, old.name, old.kind, old.basis, old.measure, old.slab_mode, old.valid_from, old.valid_to, old.target_amount, old.rebate_pct, old.rebate_flat, old.per_pack_amount) then
    raise exception 'scheme_frozen'; end if;
  return new;
end $$;
drop trigger if exists dealer_schemes_frozen on public.dealer_schemes;
create trigger dealer_schemes_frozen before update on public.dealer_schemes for each row execute function public._scheme_frozen128();

-- RLS
do $r$ declare t text; begin
  foreach t in array array['dealer_schemes', 'dealer_scheme_items', 'dealer_scheme_slabs', 'dealer_scheme_accruals', 'dealer_scheme_claims', 'dealer_scheme_claim_events'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read128', t);
    execute format($p$create policy %I on public.%I for select to authenticated using (public._dl_biz_ok127(business_id, 'dealer_scheme_view', 'dealer_scheme_manage'))$p$, t || '_read128', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $r$;
revoke all on sequence public.dealer_scheme_accruals_id_seq, public.dealer_scheme_claim_events_id_seq from public, anon, authenticated;
grant execute on function public._dl_biz_ok127(bigint, text, text) to authenticated;     -- used by the row policies above (answers only about the caller)

-- ---------- helpers ----------
create or replace function public._scheme_gate128(p_biz bigint, p_manage boolean) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_manage then
    if not public._dl_biz_ok127(p_biz, 'dealer_scheme_manage') then raise exception 'not allowed'; end if;
    if not public.rule_on('dealer_scheme_on') then raise exception 'feature_off'; end if;
  else
    if not public._dl_biz_ok127(p_biz, 'dealer_scheme_view', 'dealer_scheme_manage') then raise exception 'not allowed'; end if;
  end if;
end $$;

-- the calculation: base figures and earned-to-date of one scheme up to a date. Reads only; used by the preview and by the accrual.
create or replace function public._scheme_calc128(p_id uuid, p_upto date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s public.dealer_schemes; d1 date; d2 date; locs int[]; items text[]; bv numeric := 0; bq numeric := 0; x numeric; e numeric := 0; r record; lo numeric; hi numeric; hit boolean := false;
begin
  select * into s from public.dealer_schemes where id = p_id;
  if not found then raise exception 'scheme_not_found'; end if;
  d1 := s.valid_from; d2 := least(s.valid_to, p_upto);
  locs := array(select l.id from public.locations l where public._dl_biz127(l.id) = s.business_id);
  items := array(select i.item_id::text from public.dealer_scheme_items i where i.scheme_id = p_id);
  if d2 >= d1 and coalesce(array_length(locs, 1), 0) > 0 then
    if s.basis = 'purchase' then
      select coalesce(sum(case b.kind when 'bill' then pl.amount else -pl.amount end), 0), coalesce(sum(case b.kind when 'bill' then pl.qty else -pl.qty end), 0)
        into bv, bq
        from public.purchase_bills b join public.purchase_lines pl on pl.bill_id = b.id
        where b.supplier_id = s.supplier_id and b.status = 'posted' and b.location_id = any (locs) and b.bill_date between d1 and d2
          and (coalesce(array_length(items, 1), 0) = 0 or pl.item_id::text = any (items));
    else
      select coalesce(sum(coalesce((e2->>'amount')::numeric, (e2->>'qty')::numeric * (e2->>'price')::numeric)), 0), coalesce(sum((e2->>'qty')::numeric), 0)
        into bv, bq
        from public.sales sa cross join lateral jsonb_array_elements(sa.lines) e2
        where sa.status = 'done' and sa.location_id = any (locs) and sa.sale_date between d1 and d2 and (e2->>'item_id') = any (items);
    end if;
  end if;
  x := case s.measure when 'qty' then bq else bv end;
  if s.kind = 'slab' then
    if s.slab_mode = 'whole' then
      select sl.rate_pct into e from public.dealer_scheme_slabs sl where sl.scheme_id = p_id and sl.from_amt <= x and (sl.to_amt is null or x < sl.to_amt) order by sl.seq limit 1;
      e := coalesce(bv * coalesce(e, 0) / 100, 0);
    else
      e := 0;
      for r in select * from public.dealer_scheme_slabs sl where sl.scheme_id = p_id order by sl.seq loop
        lo := r.from_amt; hi := coalesce(r.to_amt, x);
        if x > lo then e := e + (least(x, hi) - lo) * r.rate_pct / 100; end if;
      end loop;
    end if;
  elsif s.kind = 'target' then
    if x >= s.target_amount then e := bv * coalesce(s.rebate_pct, 0) / 100 + coalesce(s.rebate_flat, 0); end if;
  else
    e := bq * s.per_pack_amount;
  end if;
  return jsonb_build_object('from', d1, 'to', d2, 'base_value', round(bv, 2), 'base_qty', round(bq, 4), 'measure_value', round(x, 4), 'earned', greatest(round(e, 2), 0));
end $$;

-- ---------- scheme set-up (draft only) ----------
-- p_params: {"target_amount","rebate_pct","rebate_flat","per_pack_amount","slab_mode"}; p_slabs: [{"from","to","rate"}]; p_items: item ids (empty = all lines)
create or replace function public.scheme_save(p_id uuid, p_client uuid, p_business bigint, p_supplier uuid, p_name text, p_kind text, p_basis text, p_measure text,
  p_from date, p_to date, p_params jsonb default '{}'::jsonb, p_items uuid[] default '{}', p_slabs jsonb default '[]'::jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.dealer_schemes; sid uuid; sl jsonb; n int := 0; prev_to numeric; f numeric; t numeric; rt numeric; it uuid; pr jsonb := coalesce(p_params, '{}'::jsonb); mode text;
begin
  perform public._scheme_gate128(p_business, true);
  if p_kind is null or p_kind not in ('slab', 'target', 'flat_pack') then raise exception 'bad_kind'; end if;
  if p_basis is null or p_basis not in ('purchase', 'sale') then raise exception 'bad_basis'; end if;
  if p_measure is null or p_measure not in ('value', 'qty') then raise exception 'bad_measure'; end if;
  if p_name is null or length(btrim(p_name)) not between 1 and 120 then raise exception 'name_required'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to > p_from + 1830 then raise exception 'bad_period'; end if;
  if jsonb_typeof(pr) <> 'object' then raise exception 'bad_params'; end if;
  if not exists (select 1 from public.dl_unit_tree127 u where u.id = p_business and u.kind = 'business') then raise exception 'bad_business'; end if;
  if not exists (select 1 from public.suppliers x where x.id = p_supplier and x.active) then raise exception 'supplier_not_found'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'note_too_long'; end if;
  mode := coalesce(pr->>'slab_mode', 'whole');
  if mode not in ('whole', 'marginal') then raise exception 'bad_params'; end if;
  if p_kind = 'flat_pack' and p_measure <> 'qty' then raise exception 'bad_measure'; end if;
  if p_kind = 'slab' and mode = 'marginal' and p_measure <> 'value' then raise exception 'bad_measure'; end if;
  if p_kind = 'target' and (nullif(pr->>'target_amount', '') is null or (nullif(pr->>'rebate_pct', '') is null and nullif(pr->>'rebate_flat', '') is null)) then raise exception 'target_needs_amount_and_rebate'; end if;
  if p_kind = 'flat_pack' and nullif(pr->>'per_pack_amount', '') is null then raise exception 'per_pack_amount_required'; end if;
  if p_kind = 'slab' and (p_slabs is null or jsonb_typeof(p_slabs) <> 'array' or jsonb_array_length(p_slabs) = 0) then raise exception 'slabs_required'; end if;
  if p_id is null then
    if p_client is null then raise exception 'client_required'; end if;
    perform public._client_lock(p_client);
    select * into s from public.dealer_schemes where client_id = p_client;
    if found then
      if s.business_id <> p_business then raise exception 'client_key_used'; end if;
      return jsonb_build_object('id', s.id, 'status', s.status, 'dup', true);
    end if;
    begin
      insert into public.dealer_schemes (client_id, business_id, supplier_id, name, kind, basis, measure, slab_mode, valid_from, valid_to, target_amount, rebate_pct, rebate_flat, per_pack_amount, note, created_by, updated_by)
        values (p_client, p_business, p_supplier, btrim(p_name), p_kind, p_basis, p_measure, mode, p_from, p_to, nullif(pr->>'target_amount', '')::numeric, nullif(pr->>'rebate_pct', '')::numeric,
          round(nullif(pr->>'rebate_flat', '')::numeric, 2), nullif(pr->>'per_pack_amount', '')::numeric, nullif(btrim(coalesce(p_note, '')), ''), auth.uid(), auth.uid()) returning id into sid;
    exception when check_violation or numeric_value_out_of_range then raise exception 'bad_params';
    end;
  else
    select * into s from public.dealer_schemes where id = p_id for update;
    if not found then raise exception 'scheme_not_found'; end if;
    if s.business_id <> p_business then raise exception 'not allowed'; end if;
    if s.status <> 'draft' then raise exception 'scheme_frozen'; end if;
    begin
      update public.dealer_schemes set supplier_id = p_supplier, name = btrim(p_name), kind = p_kind, basis = p_basis, measure = p_measure, slab_mode = mode, valid_from = p_from, valid_to = p_to,
        target_amount = nullif(pr->>'target_amount', '')::numeric, rebate_pct = nullif(pr->>'rebate_pct', '')::numeric, rebate_flat = round(nullif(pr->>'rebate_flat', '')::numeric, 2),
        per_pack_amount = nullif(pr->>'per_pack_amount', '')::numeric, note = nullif(btrim(coalesce(p_note, '')), ''), updated_by = auth.uid(), updated_at = now() where id = p_id;
    exception when check_violation or numeric_value_out_of_range then raise exception 'bad_params';
    end;
    sid := p_id;
    delete from public.dealer_scheme_items where scheme_id = sid;
    delete from public.dealer_scheme_slabs where scheme_id = sid;
  end if;
  -- item scope
  foreach it in array coalesce(p_items, '{}'::uuid[]) loop
    if not exists (select 1 from public.items i where i.id = it) then raise exception 'item_not_found'; end if;
    insert into public.dealer_scheme_items (scheme_id, item_id, business_id) values (sid, it, p_business) on conflict do nothing;
  end loop;
  -- slabs: ascending, no overlap
  if p_kind = 'slab' then
    for sl in select * from jsonb_array_elements(p_slabs) loop
      n := n + 1;
      begin f := (sl->>'from')::numeric; t := nullif(sl->>'to', '')::numeric; rt := (sl->>'rate')::numeric;
      exception when others then raise exception 'bad_slab'; end;
      if f is null or rt is null or f < 0 or rt < 0 or rt > 100 or (t is not null and t <= f) then raise exception 'bad_slab'; end if;
      if n = 1 and f is null then raise exception 'bad_slab'; end if;
      if n > 1 and (prev_to is null or f < prev_to) then raise exception 'slab_overlap'; end if;
      insert into public.dealer_scheme_slabs (scheme_id, seq, from_amt, to_amt, rate_pct, business_id) values (sid, n, f, t, rt, p_business);
      prev_to := t;
    end loop;
  end if;
  return jsonb_build_object('id', sid, 'status', 'draft');
end $$;

create or replace function public.scheme_activate(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.dealer_schemes;
begin
  select * into s from public.dealer_schemes where id = p_id;
  if not found then raise exception 'scheme_not_found'; end if;
  perform public._scheme_gate128(s.business_id, true);
  select * into s from public.dealer_schemes where id = p_id for update;
  if s.status = 'active' then return jsonb_build_object('id', s.id, 'status', 'active', 'dup', true); end if;
  if s.status <> 'draft' then raise exception 'bad_status'; end if;
  if s.basis = 'sale' and not exists (select 1 from public.dealer_scheme_items where scheme_id = s.id) then raise exception 'sale_scheme_needs_items'; end if;
  if s.kind = 'slab' and not exists (select 1 from public.dealer_scheme_slabs where scheme_id = s.id) then raise exception 'slabs_required'; end if;
  update public.dealer_schemes set status = 'active', updated_by = auth.uid(), updated_at = now() where id = s.id;
  return jsonb_build_object('id', s.id, 'status', 'active');
end $$;

-- ---------- accrual (preview or real) ----------
create or replace function public.scheme_accrue(p_id uuid, p_upto date default null, p_dry boolean default true, p_client uuid default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.dealer_schemes; today date := public._dl_today127(); up date; c jsonb; prev numeric; earned numeric; dl numeric; ev public.dealer_scheme_accruals;
begin
  select * into s from public.dealer_schemes where id = p_id;
  if not found then raise exception 'scheme_not_found'; end if;
  perform public._scheme_gate128(s.business_id, not coalesce(p_dry, true));
  up := coalesce(p_upto, today);
  if up > today or up < s.valid_from then raise exception 'bad_date'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'note_too_long'; end if;
  if not coalesce(p_dry, true) then
    if p_client is null then raise exception 'client_required'; end if;
    perform public._client_lock(p_client);
    select * into ev from public.dealer_scheme_accruals where client_id = p_client;
    if found then
      if ev.scheme_id <> p_id then raise exception 'client_key_used'; end if;
      return jsonb_build_object('id', ev.id, 'delta', ev.delta, 'earned_to_date', ev.earned_to_date, 'dup', true);
    end if;
    select * into s from public.dealer_schemes where id = p_id for update;      -- one accrual at a time per scheme
    if s.status <> 'active' then raise exception 'bad_status'; end if;
    perform public.lock_check(up);
  end if;
  c := public._scheme_calc128(p_id, up);
  earned := (c->>'earned')::numeric;
  select coalesce(sum(a.delta), 0) into prev from public.dealer_scheme_accruals a where a.scheme_id = p_id;
  dl := round(earned - prev, 2);
  if coalesce(p_dry, true) then
    return c || jsonb_build_object('dry', true, 'already_accrued', prev, 'delta', dl, 'status', s.status);
  end if;
  if dl = 0 then return c || jsonb_build_object('nothing_new', true, 'already_accrued', prev, 'delta', 0); end if;
  insert into public.dealer_scheme_accruals (scheme_id, business_id, upto_date, base_value, base_qty, earned_to_date, delta, note, client_id, created_by)
    values (p_id, s.business_id, up, (c->>'base_value')::numeric, (c->>'base_qty')::numeric, earned, dl, left(p_note, 300), p_client, auth.uid());
  return c || jsonb_build_object('already_accrued', prev, 'delta', dl, 'accrued_total', prev + dl);
end $$;

-- close a scheme: final accrual up to the end of its period (or today if earlier), then no more accruals
create or replace function public.scheme_close(p_id uuid, p_client uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.dealer_schemes; r jsonb;
begin
  select * into s from public.dealer_schemes where id = p_id;
  if not found then raise exception 'scheme_not_found'; end if;
  perform public._scheme_gate128(s.business_id, true);
  if p_client is null then raise exception 'client_required'; end if;
  if s.status = 'closed' then return jsonb_build_object('id', s.id, 'status', 'closed', 'dup', true); end if;
  if s.status <> 'active' then raise exception 'bad_status'; end if;
  r := public.scheme_accrue(p_id, least(s.valid_to, public._dl_today127()), false, p_client, 'final accrual at close');
  update public.dealer_schemes set status = 'closed', updated_by = auth.uid(), updated_at = now() where id = p_id;
  return jsonb_build_object('id', p_id, 'status', 'closed', 'final', r);
end $$;

create or replace function public.scheme_cancel(p_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.dealer_schemes;
begin
  select * into s from public.dealer_schemes where id = p_id;
  if not found then raise exception 'scheme_not_found'; end if;
  perform public._scheme_gate128(s.business_id, true);
  select * into s from public.dealer_schemes where id = p_id for update;
  if s.status = 'cancelled' then return jsonb_build_object('id', s.id, 'status', 'cancelled', 'dup', true); end if;
  if s.status not in ('draft', 'active') then raise exception 'bad_status'; end if;
  if p_reason is null or length(btrim(p_reason)) not between 1 and 200 then raise exception 'reason_required'; end if;
  if exists (select 1 from public.dealer_scheme_claims c where c.scheme_id = s.id and c.status in ('submitted', 'part_settled', 'settled')) then raise exception 'has_open_claims'; end if;
  update public.dealer_schemes set status = 'cancelled', note = left(coalesce(s.note || ' / ', '') || 'cancelled: ' || btrim(p_reason), 300), updated_by = auth.uid(), updated_at = now() where id = s.id;
  return jsonb_build_object('id', s.id, 'status', 'cancelled');
end $$;

-- ---------- claims to the principal ----------
create or replace function public.claim_create(p_client uuid, p_scheme uuid, p_claim_no text, p_date date, p_amount numeric, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.dealer_schemes; c public.dealer_scheme_claims; amt numeric; acc numeric; clm numeric; cid uuid;
begin
  select * into s from public.dealer_schemes where id = p_scheme;
  if not found then raise exception 'scheme_not_found'; end if;
  perform public._scheme_gate128(s.business_id, true);
  if p_client is null then raise exception 'client_required'; end if;
  perform public._client_lock(p_client);
  select * into c from public.dealer_scheme_claims where client_id = p_client;
  if found then
    if c.scheme_id <> p_scheme then raise exception 'client_key_used'; end if;
    return jsonb_build_object('id', c.id, 'status', c.status, 'dup', true);
  end if;
  if p_amount is null or p_amount = 'NaN'::numeric or not (abs(p_amount) <= 1000000000000) then raise exception 'bad_amount'; end if;
  amt := round(p_amount, 2);
  if amt <= 0 then raise exception 'bad_amount'; end if;
  if p_date is null or p_date > public._dl_today127() or p_date < s.valid_from then raise exception 'bad_date'; end if;
  if p_claim_no is not null and length(p_claim_no) > 40 then raise exception 'claim_no_too_long'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'note_too_long'; end if;
  select * into s from public.dealer_schemes where id = p_scheme for update;      -- one claim at a time per scheme
  if s.status not in ('active', 'closed') then raise exception 'bad_status'; end if;
  perform public.lock_check(p_date);
  select coalesce(sum(delta), 0) into acc from public.dealer_scheme_accruals where scheme_id = p_scheme;
  select coalesce(sum(amount), 0) into clm from public.dealer_scheme_claims where scheme_id = p_scheme and status in ('submitted', 'part_settled', 'settled');
  if amt > acc - clm then raise exception 'exceeds_accrual'; end if;
  begin
    insert into public.dealer_scheme_claims (client_id, business_id, scheme_id, supplier_id, claim_no, claim_date, amount, note, created_by, updated_by)
      values (p_client, s.business_id, s.id, s.supplier_id, nullif(btrim(coalesce(p_claim_no, '')), ''), p_date, amt, nullif(btrim(coalesce(p_note, '')), ''), auth.uid(), auth.uid()) returning id into cid;
  exception when unique_violation then raise exception 'duplicate_claim_no';
  end;
  insert into public.dealer_scheme_claim_events (claim_id, business_id, kind, amount, on_date, ref, note, client_id, actor)
    values (cid, s.business_id, 'submitted', amt, p_date, p_claim_no, left(p_note, 300), null, auth.uid());
  return jsonb_build_object('id', cid, 'status', 'submitted', 'amount', amt, 'unclaimed_after', acc - clm - amt);
end $$;

create or replace function public.claim_receive(p_claim uuid, p_client uuid, p_amount numeric, p_date date, p_ref text default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.dealer_scheme_claims; amt numeric; got numeric; st text;
begin
  select * into c from public.dealer_scheme_claims where id = p_claim;
  if not found then raise exception 'claim_not_found'; end if;
  perform public._scheme_gate128(c.business_id, true);
  if p_client is null then raise exception 'client_required'; end if;
  perform public._client_lock(p_client);
  if exists (select 1 from public.dealer_scheme_claim_events e where e.client_id = p_client) then
    if not exists (select 1 from public.dealer_scheme_claim_events e where e.client_id = p_client and e.claim_id = p_claim) then raise exception 'client_key_used'; end if;
    select * into c from public.dealer_scheme_claims where id = p_claim;
    return jsonb_build_object('id', c.id, 'status', c.status, 'dup', true);
  end if;
  select * into c from public.dealer_scheme_claims where id = p_claim for update;
  if c.status not in ('submitted', 'part_settled') then raise exception 'bad_status'; end if;
  if p_amount is null or p_amount = 'NaN'::numeric or not (abs(p_amount) <= 1000000000000) then raise exception 'bad_amount'; end if;
  amt := round(p_amount, 2);
  if amt <= 0 then raise exception 'bad_amount'; end if;
  if p_date is null or p_date > public._dl_today127() or p_date < c.claim_date then raise exception 'bad_date'; end if;
  if (p_ref is not null and length(p_ref) > 80) or (p_note is not null and length(p_note) > 300) then raise exception 'text_too_long'; end if;
  perform public.lock_check(p_date);
  select coalesce(sum(amount), 0) into got from public.dealer_scheme_claim_events where claim_id = p_claim and kind = 'received';
  if got + amt > c.amount then raise exception 'overpaid'; end if;
  st := case when got + amt = c.amount then 'settled' else 'part_settled' end;
  insert into public.dealer_scheme_claim_events (claim_id, business_id, kind, amount, on_date, ref, note, client_id, actor)
    values (p_claim, c.business_id, 'received', amt, p_date, left(p_ref, 80), left(p_note, 300), p_client, auth.uid());
  update public.dealer_scheme_claims set status = st, updated_by = auth.uid(), updated_at = now() where id = p_claim;
  return jsonb_build_object('id', p_claim, 'status', st, 'received_total', got + amt, 'outstanding', c.amount - got - amt);
end $$;

create or replace function public.claim_reject(p_claim uuid, p_client uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.dealer_scheme_claims;
begin
  select * into c from public.dealer_scheme_claims where id = p_claim;
  if not found then raise exception 'claim_not_found'; end if;
  perform public._scheme_gate128(c.business_id, true);
  if p_client is null then raise exception 'client_required'; end if;
  perform public._client_lock(p_client);
  if exists (select 1 from public.dealer_scheme_claim_events e where e.client_id = p_client) then
    if not exists (select 1 from public.dealer_scheme_claim_events e where e.client_id = p_client and e.claim_id = p_claim) then raise exception 'client_key_used'; end if;
    select * into c from public.dealer_scheme_claims where id = p_claim;
    return jsonb_build_object('id', c.id, 'status', c.status, 'dup', true);
  end if;
  select * into c from public.dealer_scheme_claims where id = p_claim for update;
  if c.status <> 'submitted' then raise exception 'bad_status'; end if;             -- nothing received yet
  if p_reason is null or length(btrim(p_reason)) not between 1 and 200 then raise exception 'reason_required'; end if;
  update public.dealer_scheme_claims set status = 'rejected', updated_by = auth.uid(), updated_at = now() where id = p_claim;
  insert into public.dealer_scheme_claim_events (claim_id, business_id, kind, amount, on_date, note, client_id, actor)
    values (p_claim, c.business_id, 'rejected', c.amount, public._dl_today127(), btrim(p_reason), p_client, auth.uid());
  return jsonb_build_object('id', p_claim, 'status', 'rejected');
end $$;

create or replace function public.claim_cancel(p_claim uuid, p_client uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.dealer_scheme_claims;
begin
  select * into c from public.dealer_scheme_claims where id = p_claim;
  if not found then raise exception 'claim_not_found'; end if;
  perform public._scheme_gate128(c.business_id, true);
  if p_client is null then raise exception 'client_required'; end if;
  perform public._client_lock(p_client);
  if exists (select 1 from public.dealer_scheme_claim_events e where e.client_id = p_client) then
    if not exists (select 1 from public.dealer_scheme_claim_events e where e.client_id = p_client and e.claim_id = p_claim) then raise exception 'client_key_used'; end if;
    select * into c from public.dealer_scheme_claims where id = p_claim;
    return jsonb_build_object('id', c.id, 'status', c.status, 'dup', true);
  end if;
  select * into c from public.dealer_scheme_claims where id = p_claim for update;
  if c.status <> 'submitted' then raise exception 'bad_status'; end if;
  if p_reason is null or length(btrim(p_reason)) not between 1 and 200 then raise exception 'reason_required'; end if;
  update public.dealer_scheme_claims set status = 'cancelled', updated_by = auth.uid(), updated_at = now() where id = p_claim;
  insert into public.dealer_scheme_claim_events (claim_id, business_id, kind, amount, on_date, note, client_id, actor)
    values (p_claim, c.business_id, 'cancelled', c.amount, public._dl_today127(), btrim(p_reason), p_client, auth.uid());
  return jsonb_build_object('id', p_claim, 'status', 'cancelled');
end $$;

-- ---------- reads ----------
create or replace function public.scheme_list(p_business bigint, p_status text default null)
returns table (id uuid, supplier_id uuid, supplier_name text, name text, kind text, basis text, measure text, valid_from date, valid_to date, status text, accrued numeric, claimed numeric, received numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._scheme_gate128(p_business, false);
  return query
    select s.id, s.supplier_id, (select x.name from public.suppliers x where x.id = s.supplier_id), s.name, s.kind, s.basis, s.measure, s.valid_from, s.valid_to, s.status,
      (select coalesce(sum(a.delta), 0) from public.dealer_scheme_accruals a where a.scheme_id = s.id),
      (select coalesce(sum(c.amount), 0) from public.dealer_scheme_claims c where c.scheme_id = s.id and c.status in ('submitted', 'part_settled', 'settled')),
      (select coalesce(sum(e.amount), 0) from public.dealer_scheme_claim_events e join public.dealer_scheme_claims c on c.id = e.claim_id where c.scheme_id = s.id and e.kind = 'received')
    from public.dealer_schemes s where s.business_id = p_business and (p_status is null or s.status = p_status) order by s.valid_from desc, s.name;
end $$;

create or replace function public.scheme_get(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s public.dealer_schemes;
begin
  select * into s from public.dealer_schemes where id = p_id;
  if not found then raise exception 'scheme_not_found'; end if;
  perform public._scheme_gate128(s.business_id, false);
  return to_jsonb(s) - 'client_id' || jsonb_build_object(
    'items', coalesce((select jsonb_agg(i.item_id order by i.item_id) from public.dealer_scheme_items i where i.scheme_id = p_id), '[]'::jsonb),
    'slabs', coalesce((select jsonb_agg(jsonb_build_object('seq', l.seq, 'from', l.from_amt, 'to', l.to_amt, 'rate', l.rate_pct) order by l.seq) from public.dealer_scheme_slabs l where l.scheme_id = p_id), '[]'::jsonb));
end $$;

create or replace function public.claim_list(p_business bigint, p_supplier uuid default null, p_status text default null)
returns table (id uuid, scheme_id uuid, scheme_name text, supplier_id uuid, supplier_name text, claim_no text, claim_date date, amount numeric, status text, received numeric, outstanding numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._scheme_gate128(p_business, false);
  return query
    select c.id, c.scheme_id, s.name, c.supplier_id, (select x.name from public.suppliers x where x.id = c.supplier_id), c.claim_no, c.claim_date, c.amount, c.status,
      r.got, case when c.status in ('submitted', 'part_settled') then c.amount - r.got else 0::numeric end
    from public.dealer_scheme_claims c join public.dealer_schemes s on s.id = c.scheme_id
      cross join lateral (select coalesce(sum(e.amount), 0) got from public.dealer_scheme_claim_events e where e.claim_id = c.id and e.kind = 'received') r
    where c.business_id = p_business and (p_supplier is null or c.supplier_id = p_supplier) and (p_status is null or c.status = p_status)
    order by c.claim_date desc, c.created_at desc;
end $$;

-- accrual vs claim vs receipt, per scheme (and per principal): what is earned, what was claimed, what came in, what is still unclaimed / outstanding
create or replace function public.scheme_reconciliation(p_business bigint, p_supplier uuid default null)
returns table (scheme_id uuid, supplier_id uuid, supplier_name text, scheme_name text, status text, accrued numeric, claimed numeric, received numeric, rejected numeric,
  unclaimed numeric, outstanding numeric, over_claimed numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._scheme_gate128(p_business, false);
  return query
    select z.id, z.supplier_id, z.sname, z.name, z.status, z.acc, z.clm, z.rec, z.rej, greatest(z.acc - z.clm, 0), z.clm - z.rec, greatest(z.clm - z.acc, 0)
    from (
      select s.id, s.supplier_id, (select x.name from public.suppliers x where x.id = s.supplier_id) sname, s.name, s.status,
        (select coalesce(sum(a.delta), 0) from public.dealer_scheme_accruals a where a.scheme_id = s.id) acc,
        (select coalesce(sum(c.amount), 0) from public.dealer_scheme_claims c where c.scheme_id = s.id and c.status in ('submitted', 'part_settled', 'settled')) clm,
        (select coalesce(sum(e.amount), 0) from public.dealer_scheme_claim_events e join public.dealer_scheme_claims c on c.id = e.claim_id where c.scheme_id = s.id and e.kind = 'received') rec,
        (select coalesce(sum(c.amount), 0) from public.dealer_scheme_claims c where c.scheme_id = s.id and c.status = 'rejected') rej
      from public.dealer_schemes s where s.business_id = p_business and s.status <> 'cancelled' and (p_supplier is null or s.supplier_id = p_supplier)) z
    order by z.sname, z.name;
end $$;

-- ---------- function grants ----------
revoke all on function public._scheme_gate128(bigint, boolean), public._scheme_calc128(uuid, date), public._scheme_frozen128() from public, anon, authenticated;
revoke all on function public.scheme_save(uuid, uuid, bigint, uuid, text, text, text, text, date, date, jsonb, uuid[], jsonb, text), public.scheme_activate(uuid),
  public.scheme_accrue(uuid, date, boolean, uuid, text), public.scheme_close(uuid, uuid), public.scheme_cancel(uuid, text),
  public.claim_create(uuid, uuid, text, date, numeric, text), public.claim_receive(uuid, uuid, numeric, date, text, text), public.claim_reject(uuid, uuid, text), public.claim_cancel(uuid, uuid, text),
  public.scheme_list(bigint, text), public.scheme_get(uuid), public.claim_list(bigint, uuid, text), public.scheme_reconciliation(bigint, uuid) from public, anon;
grant execute on function public.scheme_save(uuid, uuid, bigint, uuid, text, text, text, text, date, date, jsonb, uuid[], jsonb, text), public.scheme_activate(uuid),
  public.scheme_accrue(uuid, date, boolean, uuid, text), public.scheme_close(uuid, uuid), public.scheme_cancel(uuid, text),
  public.claim_create(uuid, uuid, text, date, numeric, text), public.claim_receive(uuid, uuid, numeric, date, text, text), public.claim_reject(uuid, uuid, text), public.claim_cancel(uuid, uuid, text),
  public.scheme_list(bigint, text), public.scheme_get(uuid), public.claim_list(bigint, uuid, text), public.scheme_reconciliation(bigint, uuid) to authenticated;

commit;

-- ---------------------------------------------------------------- phase129.sql
-- ============================================================
-- Phase 129 (marker dl129) - DEALER / HARDWARE-PAINT BUSINESS, part 3: TINTING machine (ADDITIVE ONLY).
-- Canonical order: after phase128 (uses phase127's scope helpers). Paste twice = no change, no error.
-- Rule dealer_tint_on is OFF by default: while OFF every write function refuses ('feature_off'); the dry run (preview) and reads still work.
--   Table dealer_shades           a shade code (and name) of one business. Owner data, nothing seeded.
--   Table dealer_tint_formulas    one VERSION of the formula of a shade for one BASE item (the base paint in its pack, e.g. "Emulsion white base 4L") and a pack label.
--                                 base_qty_per_pack = base units used per pack tinted. Same idea as the recipe engine (versioned, never edited: a change = a new version,
--                                 the old one is retired; status active | retired; one active version per shade + base).
--   Table dealer_tint_formula_lines  the colorants: colorant item + quantity per ONE pack (in the item's base unit, e.g. ml). Append-only.
--   Table dealer_tint_jobs        one tint job: formula, packs, customer (optional), cost, charge (entered), status done | void. Cost columns are not readable by the
--                                 browser role; they are returned only to the owner / rpt_cost_ok() users by tint_job_cost / tint_cost_report.
--   Table dealer_tint_job_lines   what the job consumed: the base + each colorant (qty, and cost for cost-visible users).
--   Stock: tint_job_run consumes base + colorants with the EXISTING stock_post (reason issue_out, ref_type tint_job, ref_id = job id) at the average cost of the moment,
--     honouring the stock_negative_mode rule (block / warn); tint_job_void reverses every row with stock_post (reason reversal, reverses_id) - the ledger is never edited.
--     Nothing is posted to the books by this phase (the existing acct_issue_out switch decides that for issue_out rows; it is OFF by default).
--   p_dry = true on tint_job_run is the PREVIEW: it writes nothing and returns the quantities, on-hand stock, shortages and (cost-visible users) the estimated cost.
--   Shade history per customer: tint_customer_shades. Business scope exactly as phase127 (owner, or explicitly assigned location + grant, inside that business).
--   Grants dealer_tint_view, dealer_tint_manage (shades, formulas), dealer_tint_run (jobs). Costs: owner or rpt_cost_ok().
-- Rollback: leave dealer_tint_on OFF. To remove: drop the functions and the five tables (nothing else refers to them).
-- ============================================================
begin;

do $g$
declare miss text := '';
begin
  if to_regclass('public.dealer_cheques') is null or to_regprocedure('public._dl_ok127(integer,text,text)') is null or to_regprocedure('public._dl_biz_ok127(bigint,text,text)') is null
     or to_regprocedure('public._dl_biz127(integer)') is null or to_regprocedure('public._dl_append_only127()') is null then miss := miss || ' phase127'; end if;
  if to_regclass('public.items') is null or to_regclass('public.stock_ledger') is null or to_regclass('public.stock_balance') is null or to_regclass('public.customers') is null then miss := miss || ' tables'; end if;
  if to_regprocedure('public.stock_post(uuid,integer,numeric,text,text,text,numeric,bigint,timestamp with time zone,text,bigint,text,uuid,uuid)') is null
     or to_regprocedure('public.rpt_cost_ok()') is null then miss := miss || ' functions'; end if;
  if miss <> '' then raise exception 'phase129 needs the base schema and phases up to 128 pasted first (docs/PASTE_ORDER.md); missing:%', miss; end if;
end $g$;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
select v.c, 'dealer', v.s, v.b, v.m, v.e, 'once' from (values
  ('dealer_tint_view', 131, 'টিন্টিং ফর্মুলা ও জব দেখা', 'Tinting formula ও job দেখা', 'View tinting formulas and jobs'),
  ('dealer_tint_manage', 132, 'শেড ও টিন্টিং ফর্মুলা তৈরি', 'Shade ও tinting formula তৈরি', 'Create shades and tinting formulas'),
  ('dealer_tint_run', 133, 'টিন্টিং জব চালানো (বেস ও কালারেন্ট স্টক থেকে কাটা)', 'Tinting job চালানো (base ও colorant stock থেকে কাটা)', 'Run tint jobs (consumes base and colorants from stock)')
) v(c, s, b, m, e) where not exists (select 1 from public.grant_defs g where g.grant_code = v.c);

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('dealer_tint_on', 'dealer', 'switch', 'false', null, null, null, null,
  'টিন্টিং মেশিন চালু', 'Tinting machine চালু', 'Tinting machine',
  'চালু করলে শেড ফর্মুলা ও টিন্ট জব লেখা যাবে; জব বেস ও কালারেন্ট স্টক থেকে কাটে।',
  'চালু করলে shade formula ও tint job লেখা যাবে; job base ও colorant stock থেকে কাটে।',
  'When on, shade formulas and tint jobs can be written; a job consumes the base and colorants from stock.', 1290)
on conflict (key) do nothing;

insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort)
select 'dealer_tint_on', 'dealer_tint_on', '129', 'dealer', null::jsonb, '{}'::text[],
  'যে দোকানে টিন্টিং মেশিন আছে শুধু সেখানে চালু করুন।', 'যে দোকানে tinting machine আছে শুধু সেখানে চালু করুন।',
  'Turn on only for a shop that has a tinting machine.', 1290
where not exists (select 1 from public.setup_rec_defs81 where code = 'dealer_tint_on');

-- ---------- tables ----------
create table if not exists public.dealer_shades (
  id uuid primary key default gen_random_uuid(),
  business_id bigint not null references public.org_units(id),
  shade_code text not null check (shade_code = upper(btrim(shade_code)) and length(shade_code) between 1 and 40),
  name text check (name is null or length(name) <= 120),
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now(),
  unique (business_id, shade_code)
);
create table if not exists public.dealer_tint_formulas (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null unique,
  business_id bigint not null references public.org_units(id),
  shade_id uuid not null references public.dealer_shades(id),
  base_item_id uuid not null references public.items(id),
  pack_label text check (pack_label is null or length(pack_label) <= 40),
  base_qty_per_pack numeric(14,4) not null default 1 check (base_qty_per_pack > 0 and base_qty_per_pack <= 1000000),
  version int not null check (version >= 1),
  status text not null default 'active' check (status in ('active', 'retired')),
  used_at timestamptz,
  note text check (note is null or length(note) <= 300),
  created_by uuid, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (shade_id, base_item_id, version)
);
create unique index if not exists dealer_tint_formulas_active129 on public.dealer_tint_formulas (shade_id, base_item_id) where status = 'active';
create table if not exists public.dealer_tint_formula_lines (
  formula_id uuid not null references public.dealer_tint_formulas(id),
  seq int not null check (seq >= 1),
  colorant_item_id uuid not null references public.items(id),
  qty_per_pack numeric(14,4) not null check (qty_per_pack > 0 and qty_per_pack <= 1000000),
  business_id bigint not null references public.org_units(id),
  primary key (formula_id, seq),
  unique (formula_id, colorant_item_id)
);
create table if not exists public.dealer_tint_jobs (
  id uuid primary key default gen_random_uuid(),
  job_no bigint generated by default as identity,
  client_id uuid not null unique,
  business_id bigint not null references public.org_units(id),
  location_id int not null references public.locations(id),
  formula_id uuid not null references public.dealer_tint_formulas(id),
  shade_id uuid not null references public.dealer_shades(id),
  shade_code text not null,
  formula_version int not null,
  base_item_id uuid not null references public.items(id),
  customer_id uuid references public.customers(id),
  customer_name text check (customer_name is null or length(customer_name) <= 120),
  packs numeric(12,3) not null check (packs > 0 and packs <= 100000),
  job_date date not null,
  charge_amount numeric(16,2) check (charge_amount is null or (charge_amount >= 0 and charge_amount <= 1000000000000)),
  cost_total numeric(16,2),                       -- SECRET (cost): not granted to the browser role
  cost_known boolean,                             -- SECRET
  status text not null default 'done' check (status in ('done', 'void')),
  note text check (note is null or length(note) <= 300),
  void_note text, void_by uuid, void_at timestamptz,
  created_by uuid, created_at timestamptz not null default now()
);
create index if not exists dealer_tint_jobs_loc129 on public.dealer_tint_jobs (location_id, job_date);
create index if not exists dealer_tint_jobs_cust129 on public.dealer_tint_jobs (customer_id, job_date) where customer_id is not null;
create table if not exists public.dealer_tint_job_lines (
  job_id uuid not null references public.dealer_tint_jobs(id),
  seq int not null,
  role text not null check (role in ('base', 'colorant')),
  item_id uuid not null references public.items(id),
  qty numeric(18,4) not null check (qty > 0),
  unit_cost numeric,                              -- SECRET
  cost numeric(16,2),                             -- SECRET
  business_id bigint not null references public.org_units(id),
  location_id int not null references public.locations(id),
  primary key (job_id, seq)
);

-- records: formulas change only status / used_at; formula lines are append-only; jobs change only status / void columns / cost columns
create or replace function public._tint_formula_guard129() returns trigger language plpgsql set search_path = public as $$
begin
  if (new.business_id, new.shade_id, new.base_item_id, new.pack_label, new.base_qty_per_pack, new.version, new.note, new.client_id)
     is distinct from (old.business_id, old.shade_id, old.base_item_id, old.pack_label, old.base_qty_per_pack, old.version, old.note, old.client_id) then
    raise exception 'formula_frozen'; end if;
  return new;
end $$;
create or replace function public._tint_job_guard129() returns trigger language plpgsql set search_path = public as $$
begin
  if old.status = 'void' then raise exception 'job_void'; end if;
  if (new.business_id, new.location_id, new.formula_id, new.shade_id, new.shade_code, new.formula_version, new.base_item_id, new.customer_id, new.customer_name, new.packs, new.job_date, new.charge_amount, new.client_id)
     is distinct from (old.business_id, old.location_id, old.formula_id, old.shade_id, old.shade_code, old.formula_version, old.base_item_id, old.customer_id, old.customer_name, old.packs, old.job_date, old.charge_amount, old.client_id) then
    raise exception 'job_frozen'; end if;
  return new;
end $$;
drop trigger if exists dealer_tint_formulas_guard on public.dealer_tint_formulas;
create trigger dealer_tint_formulas_guard before update on public.dealer_tint_formulas for each row execute function public._tint_formula_guard129();
drop trigger if exists dealer_tint_jobs_guard on public.dealer_tint_jobs;
create trigger dealer_tint_jobs_guard before update on public.dealer_tint_jobs for each row execute function public._tint_job_guard129();
drop trigger if exists dealer_tint_formula_lines_ro on public.dealer_tint_formula_lines;
create trigger dealer_tint_formula_lines_ro before update or delete on public.dealer_tint_formula_lines for each row execute function public._dl_append_only127();
drop trigger if exists dealer_tint_job_lines_ro on public.dealer_tint_job_lines;
create trigger dealer_tint_job_lines_ro before delete on public.dealer_tint_job_lines for each row execute function public._dl_append_only127();
do $t$ declare t text; begin
  foreach t in array array['dealer_shades', 'dealer_tint_formulas', 'dealer_tint_jobs'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_no_delete', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_no_delete', t);
    execute format('drop trigger if exists %I on public.%I', 'audit_' || t, t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.log_change(%L)', 'audit_' || t, t, 'id');
  end loop;
end $t$;

-- RLS: business-level for shades / formulas, location-level for jobs
alter table public.dealer_shades enable row level security;
alter table public.dealer_tint_formulas enable row level security;
alter table public.dealer_tint_formula_lines enable row level security;
alter table public.dealer_tint_jobs enable row level security;
alter table public.dealer_tint_job_lines enable row level security;
drop policy if exists dealer_shades_read129 on public.dealer_shades;
create policy dealer_shades_read129 on public.dealer_shades for select to authenticated using (public._dl_biz_ok127(business_id, 'dealer_tint_view', 'dealer_tint_manage'));
drop policy if exists dealer_tint_formulas_read129 on public.dealer_tint_formulas;
create policy dealer_tint_formulas_read129 on public.dealer_tint_formulas for select to authenticated using (public._dl_biz_ok127(business_id, 'dealer_tint_view', 'dealer_tint_manage'));
drop policy if exists dealer_tint_formula_lines_read129 on public.dealer_tint_formula_lines;
create policy dealer_tint_formula_lines_read129 on public.dealer_tint_formula_lines for select to authenticated using (public._dl_biz_ok127(business_id, 'dealer_tint_view', 'dealer_tint_manage'));
drop policy if exists dealer_tint_jobs_read129 on public.dealer_tint_jobs;
create policy dealer_tint_jobs_read129 on public.dealer_tint_jobs for select to authenticated using (public._dl_ok127(location_id, 'dealer_tint_view', 'dealer_tint_run'));
drop policy if exists dealer_tint_job_lines_read129 on public.dealer_tint_job_lines;
create policy dealer_tint_job_lines_read129 on public.dealer_tint_job_lines for select to authenticated using (public._dl_ok127(location_id, 'dealer_tint_view', 'dealer_tint_run'));
revoke all on public.dealer_shades, public.dealer_tint_formulas, public.dealer_tint_formula_lines, public.dealer_tint_jobs, public.dealer_tint_job_lines from public, anon, authenticated;
grant select on public.dealer_shades, public.dealer_tint_formulas, public.dealer_tint_formula_lines to authenticated;
grant select (id, job_no, client_id, business_id, location_id, formula_id, shade_id, shade_code, formula_version, base_item_id, customer_id, customer_name, packs, job_date, charge_amount, status, note, void_note, void_at, created_at)
  on public.dealer_tint_jobs to authenticated;                                  -- cost_total / cost_known are NOT granted
grant select (job_id, seq, role, item_id, qty, business_id, location_id) on public.dealer_tint_job_lines to authenticated;      -- unit_cost / cost are NOT granted

-- ---------- helpers ----------
create or replace function public._tint_gate129(p_biz bigint, p_loc int, p_grant text, p_write boolean) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is not null then
    if not (case when p_write then public._dl_ok127(p_loc, p_grant) else public._dl_ok127(p_loc, 'dealer_tint_view', p_grant) end) then raise exception 'not allowed'; end if;
  else
    if not (case when p_write then public._dl_biz_ok127(p_biz, p_grant) else public._dl_biz_ok127(p_biz, 'dealer_tint_view', p_grant) end) then raise exception 'not allowed'; end if;
  end if;
  if p_write and not public.rule_on('dealer_tint_on') then raise exception 'feature_off'; end if;
end $$;

-- ---------- shades and formulas ----------
-- Creates the shade if the code is new, then a NEW version of the formula for (shade, base). The previous active version of that pair becomes retired.
-- p_lines: [{"item": "<colorant item id>", "qty": <per ONE pack, item base unit>}]
create or replace function public.tint_formula_save(p_client uuid, p_business bigint, p_shade_code text, p_shade_name text, p_base_item uuid, p_pack_label text, p_base_qty numeric,
  p_lines jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f public.dealer_tint_formulas; sh public.dealer_shades; code text; v int; fid uuid; l jsonb; n int := 0; q numeric; it uuid; bq numeric;
begin
  perform public._tint_gate129(p_business, null, 'dealer_tint_manage', true);
  if p_client is null then raise exception 'client_required'; end if;
  perform public._client_lock(p_client);
  select * into f from public.dealer_tint_formulas where client_id = p_client;
  if found then
    if f.business_id <> p_business then raise exception 'client_key_used'; end if;
    return jsonb_build_object('id', f.id, 'version', f.version, 'dup', true);
  end if;
  if not exists (select 1 from public.dl_unit_tree127 u where u.id = p_business and u.kind = 'business') then raise exception 'bad_business'; end if;
  code := upper(btrim(coalesce(p_shade_code, '')));
  if length(code) not between 1 and 40 then raise exception 'shade_code_required'; end if;
  if p_shade_name is not null and length(p_shade_name) > 120 then raise exception 'name_too_long'; end if;
  if not exists (select 1 from public.items i where i.id = p_base_item) then raise exception 'item_not_found'; end if;
  if p_pack_label is not null and length(p_pack_label) > 40 then raise exception 'pack_label_too_long'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'note_too_long'; end if;
  if p_base_qty is null or p_base_qty = 'NaN'::numeric or not (p_base_qty between 0.0001 and 1000000) then raise exception 'bad_qty'; end if;
  bq := round(p_base_qty, 4);
  if bq <= 0 then raise exception 'bad_qty'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'lines_required'; end if;
  if jsonb_array_length(p_lines) > 40 then raise exception 'too_many_lines'; end if;
  -- validate every line before anything is written
  for l in select * from jsonb_array_elements(p_lines) loop
    begin it := (l->>'item')::uuid; q := (l->>'qty')::numeric; exception when others then raise exception 'bad_line'; end;
    if it is null or q is null or q = 'NaN'::numeric or not (q between 0.0001 and 1000000) or round(q, 4) <= 0 then raise exception 'bad_qty'; end if;
    if not exists (select 1 from public.items i where i.id = it) then raise exception 'item_not_found'; end if;
    if it = p_base_item then raise exception 'colorant_is_base'; end if;
  end loop;
  if (select count(distinct (x->>'item')) from jsonb_array_elements(p_lines) x) <> jsonb_array_length(p_lines) then raise exception 'duplicate_colorant'; end if;
  insert into public.dealer_shades (business_id, shade_code, name, created_by) values (p_business, code, nullif(btrim(coalesce(p_shade_name, '')), ''), auth.uid())
    on conflict (business_id, shade_code) do update set name = coalesce(nullif(btrim(coalesce(p_shade_name, '')), ''), public.dealer_shades.name)
    returning * into sh;
  if not sh.active then raise exception 'shade_inactive'; end if;
  select coalesce(max(version), 0) + 1 into v from public.dealer_tint_formulas where shade_id = sh.id and base_item_id = p_base_item;
  update public.dealer_tint_formulas set status = 'retired', updated_at = now() where shade_id = sh.id and base_item_id = p_base_item and status = 'active';
  insert into public.dealer_tint_formulas (client_id, business_id, shade_id, base_item_id, pack_label, base_qty_per_pack, version, note, created_by)
    values (p_client, p_business, sh.id, p_base_item, nullif(btrim(coalesce(p_pack_label, '')), ''), bq, v, nullif(btrim(coalesce(p_note, '')), ''), auth.uid()) returning id into fid;
  for l in select * from jsonb_array_elements(p_lines) loop
    n := n + 1;
    insert into public.dealer_tint_formula_lines (formula_id, seq, colorant_item_id, qty_per_pack, business_id) values (fid, n, (l->>'item')::uuid, round((l->>'qty')::numeric, 4), p_business);
  end loop;
  return jsonb_build_object('id', fid, 'shade_id', sh.id, 'shade_code', code, 'version', v, 'status', 'active');
end $$;

create or replace function public.tint_formula_retire(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f public.dealer_tint_formulas;
begin
  select * into f from public.dealer_tint_formulas where id = p_id;
  if not found then raise exception 'formula_not_found'; end if;
  perform public._tint_gate129(f.business_id, null, 'dealer_tint_manage', true);
  if f.status = 'retired' then return jsonb_build_object('id', f.id, 'status', 'retired', 'dup', true); end if;
  update public.dealer_tint_formulas set status = 'retired', updated_at = now() where id = p_id;
  return jsonb_build_object('id', f.id, 'status', 'retired');
end $$;

-- ---------- the job ----------
create or replace function public._tint_uuid129(p_client uuid, p_seq int) returns uuid
language sql immutable set search_path = public as $$ select md5(p_client::text || ':tint:' || p_seq::text)::uuid; $$;

create or replace function public.tint_job_run(p_client uuid, p_loc int, p_formula uuid, p_packs numeric, p_customer uuid default null, p_customer_name text default null,
  p_date date default null, p_charge numeric default null, p_note text default null, p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f public.dealer_tint_formulas; sh public.dealer_shades; j public.dealer_tint_jobs; today date := public._dl_today127(); d date; packs numeric; biz bigint; jid uuid := gen_random_uuid();
        lines jsonb := '[]'::jsonb; r record; q numeric; n int := 0; onhand numeric; avgc numeric; est numeric := 0; est_ok boolean := true; costok boolean := public.is_owner() or public.rpt_cost_ok();
        short boolean := false; tot numeric; known boolean; lid bigint; sid text; chg numeric;
begin
  select * into f from public.dealer_tint_formulas where id = p_formula;
  if not found then raise exception 'formula_not_found'; end if;
  biz := public._dl_biz127(p_loc);
  if biz is null or biz <> f.business_id then raise exception 'not allowed'; end if;
  perform public._tint_gate129(biz, p_loc, 'dealer_tint_run', not coalesce(p_dry, false));
  if f.status <> 'active' then raise exception 'formula_retired'; end if;
  if p_packs is null or p_packs = 'NaN'::numeric or not (p_packs between 0.001 and 100000) then raise exception 'bad_packs'; end if;
  packs := round(p_packs, 3);
  if packs <= 0 then raise exception 'bad_packs'; end if;
  d := coalesce(p_date, today);
  if d > today or d < today - 3 then raise exception 'bad_date'; end if;
  if p_customer_name is not null and length(p_customer_name) > 120 then raise exception 'name_too_long'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'note_too_long'; end if;
  if p_charge is not null and (p_charge = 'NaN'::numeric or not (p_charge between 0 and 1000000000000)) then raise exception 'bad_amount'; end if;
  chg := round(p_charge, 2);
  if p_customer is not null and not exists (select 1 from public.customers c where c.id = p_customer) then raise exception 'customer_not_found'; end if;
  select * into sh from public.dealer_shades where id = f.shade_id;
  -- the lines: base first, then colorants
  for r in select 'base'::text role, f.base_item_id item, round(packs * f.base_qty_per_pack, 4) qty, 0 s
           union all select 'colorant', fl.colorant_item_id, round(packs * fl.qty_per_pack, 4), fl.seq from public.dealer_tint_formula_lines fl where fl.formula_id = f.id
           order by 4 loop
    if r.qty <= 0 then raise exception 'bad_qty'; end if;
    select b.qty, b.avg_cost into onhand, avgc from public.stock_balance b where b.item_id = r.item and b.location_id = p_loc;
    onhand := coalesce(onhand, 0);
    if onhand < r.qty then short := true; end if;
    if avgc is null then est_ok := false; else est := est + r.qty * avgc; end if;
    lines := lines || jsonb_build_object('role', r.role, 'item_id', r.item, 'qty', r.qty, 'on_hand', onhand, 'short', onhand < r.qty);
  end loop;
  if p_dry then
    return jsonb_build_object('dry', true, 'shade_code', sh.shade_code, 'formula_version', f.version, 'packs', packs, 'lines', lines, 'short', short,
      'estimated_cost', case when costok and est_ok then round(est, 2) end);
  end if;
  if p_client is null then raise exception 'client_required'; end if;
  perform public._client_lock(p_client);
  select * into j from public.dealer_tint_jobs where client_id = p_client;
  if found then
    if j.location_id <> p_loc then raise exception 'client_key_used'; end if;
    return jsonb_build_object('id', j.id, 'job_no', j.job_no, 'status', j.status, 'dup', true);
  end if;
  perform public.lock_check(d);
  insert into public.dealer_tint_jobs (id, client_id, business_id, location_id, formula_id, shade_id, shade_code, formula_version, base_item_id, customer_id, customer_name, packs, job_date, charge_amount, note, created_by)
    values (jid, p_client, biz, p_loc, f.id, f.shade_id, sh.shade_code, f.version, f.base_item_id, p_customer, nullif(btrim(coalesce(p_customer_name, '')), ''), packs, d, chg, nullif(btrim(coalesce(p_note, '')), ''), auth.uid());
  -- consume from stock through the existing stock function (average cost of the moment); stock_negative_mode decides what a shortage does
  for r in select (x->>'role') role, (x->>'item_id')::uuid item, (x->>'qty')::numeric qty from jsonb_array_elements(lines) x loop
    n := n + 1;
    lid := public.stock_post(r.item, p_loc, -r.qty, 'issue_out', 'tint_job', jid::text, null, null, (d::timestamp + time '12:00') at time zone 'Asia/Dhaka', left('tint ' || sh.shade_code, 200), null, 'full', null, public._tint_uuid129(p_client, n));
    insert into public.dealer_tint_job_lines (job_id, seq, role, item_id, qty, business_id, location_id) values (jid, n, r.role, r.item, r.qty, biz, p_loc);
  end loop;
  -- cost from the ledger rows just written (one line may span several batches)
  update public.dealer_tint_job_lines jl set
    unit_cost = case when s.q > 0 then round(s.c / s.q, 6) end,
    cost = round(s.c, 2)
    from (select l.item_id, sum(-l.qty_delta) q, sum(-l.qty_delta * l.unit_cost) c from public.stock_ledger l where l.ref_type = 'tint_job' and l.ref_id = jid::text and l.reason = 'issue_out' and l.unit_cost is not null group by l.item_id) s
    where jl.job_id = jid and jl.item_id = s.item_id;
  select coalesce(sum(cost), 0), bool_and(cost is not null) into tot, known from public.dealer_tint_job_lines where job_id = jid;
  update public.dealer_tint_jobs set cost_total = tot, cost_known = coalesce(known, false) where id = jid;
  if f.used_at is null then update public.dealer_tint_formulas set used_at = now() where id = f.id; end if;
  return jsonb_build_object('id', jid, 'job_no', (select job_no from public.dealer_tint_jobs where id = jid), 'status', 'done', 'shade_code', sh.shade_code, 'packs', packs, 'lines', lines, 'short', short,
    'cost_total', case when costok then tot end, 'cost_known', case when costok then coalesce(known, false) end);
end $$;

create or replace function public.tint_job_void(p_job uuid, p_client uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.dealer_tint_jobs; r record;
begin
  select * into j from public.dealer_tint_jobs where id = p_job;
  if not found then raise exception 'job_not_found'; end if;
  perform public._tint_gate129(j.business_id, j.location_id, 'dealer_tint_run', true);
  if p_client is null then raise exception 'client_required'; end if;
  perform public._client_lock(p_client);
  select * into j from public.dealer_tint_jobs where id = p_job for update;
  if j.status = 'void' then return jsonb_build_object('id', j.id, 'status', 'void', 'dup', true); end if;
  if p_reason is null or length(btrim(p_reason)) not between 1 and 200 then raise exception 'reason_required'; end if;
  perform public.lock_check(j.job_date);
  for r in select * from public.stock_ledger o where o.ref_type = 'tint_job' and o.ref_id = j.id::text and o.reason = 'issue_out'
           and not exists (select 1 from public.stock_ledger v where v.reverses_id = o.id) order by o.item_id, o.id loop
    perform public.stock_post(r.item_id, r.location_id, -r.qty_delta, 'reversal', 'tint_job', j.id::text, r.unit_cost, r.batch_id, now(), left('void: ' || btrim(p_reason), 200), r.id, 'soft');
  end loop;
  update public.dealer_tint_jobs set status = 'void', void_note = left(btrim(p_reason), 200), void_by = auth.uid(), void_at = now() where id = j.id;
  return jsonb_build_object('id', j.id, 'status', 'void');
end $$;

-- ---------- reads ----------
create or replace function public.tint_formula_list(p_business bigint, p_shade text default null, p_status text default null)
returns table (id uuid, shade_code text, shade_name text, base_item_id uuid, pack_label text, base_qty_per_pack numeric, version int, status text, used boolean, colorants int)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._tint_gate129(p_business, null, 'dealer_tint_manage', false);
  return query
    select f.id, s.shade_code, s.name, f.base_item_id, f.pack_label, f.base_qty_per_pack, f.version, f.status, f.used_at is not null,
           (select count(*)::int from public.dealer_tint_formula_lines l where l.formula_id = f.id)
    from public.dealer_tint_formulas f join public.dealer_shades s on s.id = f.shade_id
    where f.business_id = p_business and (p_shade is null or s.shade_code = upper(btrim(p_shade))) and (p_status is null or f.status = p_status)
    order by s.shade_code, f.base_item_id, f.version desc;
end $$;

create or replace function public.tint_formula_get(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f public.dealer_tint_formulas;
begin
  select * into f from public.dealer_tint_formulas where id = p_id;
  if not found then raise exception 'formula_not_found'; end if;
  perform public._tint_gate129(f.business_id, null, 'dealer_tint_manage', false);
  return (to_jsonb(f) - 'client_id') || jsonb_build_object('shade_code', (select shade_code from public.dealer_shades where id = f.shade_id),
    'lines', coalesce((select jsonb_agg(jsonb_build_object('seq', l.seq, 'item_id', l.colorant_item_id, 'qty_per_pack', l.qty_per_pack) order by l.seq) from public.dealer_tint_formula_lines l where l.formula_id = f.id), '[]'::jsonb));
end $$;

create or replace function public.tint_job_list(p_business bigint, p_from date default null, p_to date default null, p_customer uuid default null, p_limit int default 200)
returns table (id uuid, job_no bigint, location_id int, shade_code text, formula_version int, base_item_id uuid, customer_id uuid, customer_name text, packs numeric, job_date date, charge_amount numeric, status text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query
    select j.id, j.job_no, j.location_id, j.shade_code, j.formula_version, j.base_item_id, j.customer_id, coalesce((select c.name from public.customers c where c.id = j.customer_id), j.customer_name), j.packs, j.job_date, j.charge_amount, j.status
    from public.dealer_tint_jobs j
    where j.business_id = p_business and public._dl_ok127(j.location_id, 'dealer_tint_view', 'dealer_tint_run')
      and (p_from is null or j.job_date >= p_from) and (p_to is null or j.job_date <= p_to) and (p_customer is null or j.customer_id = p_customer)
    order by j.job_date desc, j.job_no desc limit greatest(1, least(coalesce(p_limit, 200), 1000));
end $$;

-- the shade codes a customer has had mixed (history), only from jobs the caller may see
create or replace function public.tint_customer_shades(p_customer uuid, p_business bigint default null)
returns table (shade_code text, jobs int, packs numeric, last_date date, last_base_item uuid, last_formula_version int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query
    select j.shade_code, count(*)::int, sum(j.packs), max(j.job_date), (array_agg(j.base_item_id order by j.job_date desc, j.job_no desc))[1], (array_agg(j.formula_version order by j.job_date desc, j.job_no desc))[1]
    from public.dealer_tint_jobs j
    where j.customer_id = p_customer and j.status = 'done' and public._dl_ok127(j.location_id, 'dealer_tint_view', 'dealer_tint_run') and (p_business is null or j.business_id = p_business)
    group by j.shade_code order by max(j.job_date) desc, j.shade_code;
end $$;

-- COST (owner or rpt_cost_ok only): cost per job and the cost of the colorants / base, margin against the entered charge
create or replace function public.tint_job_cost(p_job uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare j public.dealer_tint_jobs;
begin
  select * into j from public.dealer_tint_jobs where id = p_job;
  if not found then raise exception 'job_not_found'; end if;
  perform public._tint_gate129(j.business_id, j.location_id, 'dealer_tint_run', false);
  if not (public.is_owner() or public.rpt_cost_ok()) then raise exception 'not allowed'; end if;
  return jsonb_build_object('id', j.id, 'job_no', j.job_no, 'shade_code', j.shade_code, 'packs', j.packs, 'status', j.status, 'cost_total', j.cost_total, 'cost_known', j.cost_known, 'charge', j.charge_amount,
    'margin', case when j.charge_amount is not null and j.cost_total is not null then round(j.charge_amount - j.cost_total, 2) end,
    'cost_per_pack', case when j.cost_total is not null then round(j.cost_total / j.packs, 4) end,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('seq', l.seq, 'role', l.role, 'item_id', l.item_id, 'qty', l.qty, 'unit_cost', l.unit_cost, 'cost', l.cost) order by l.seq) from public.dealer_tint_job_lines l where l.job_id = j.id), '[]'::jsonb));
end $$;

create or replace function public.tint_cost_report(p_business bigint, p_from date default null, p_to date default null)
returns table (shade_code text, jobs int, packs numeric, cost_total numeric, cost_per_pack numeric, charge_total numeric, unknown_cost_jobs int)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._tint_gate129(p_business, null, 'dealer_tint_run', false);
  if not (public.is_owner() or public.rpt_cost_ok()) then raise exception 'not allowed'; end if;
  return query
    select j.shade_code, count(*)::int, sum(j.packs), sum(coalesce(j.cost_total, 0)), case when sum(j.packs) > 0 then round(sum(coalesce(j.cost_total, 0)) / sum(j.packs), 4) end, sum(coalesce(j.charge_amount, 0)),
           (count(*) filter (where not coalesce(j.cost_known, false)))::int
    from public.dealer_tint_jobs j
    where j.business_id = p_business and j.status = 'done' and public._dl_ok127(j.location_id, 'dealer_tint_view', 'dealer_tint_run')
      and (p_from is null or j.job_date >= p_from) and (p_to is null or j.job_date <= p_to)
    group by j.shade_code order by 4 desc, 1;
end $$;

-- ---------- business templates: say honestly what exists (status is NOT changed: neither template is ready for use as a whole) ----------
-- filled only while the list is still empty, so a second paste (or an owner edit) is never overwritten. built = a database part with tests (phase 127-129); not_built = nothing exists yet.
update public.business_templates set modules = '[
  {"code":"cheque_pdc","state":"built","phase":127,"rule":"dealer_cheque_on"},
  {"code":"principal_schemes","state":"built","phase":128,"rule":"dealer_scheme_on"},
  {"code":"tinting","state":"built","phase":129,"rule":"dealer_tint_on"},
  {"code":"bulk_item_import","state":"not_built"},
  {"code":"item_variants","state":"not_built"},
  {"code":"dealer_pos_screens","state":"not_built"},
  {"code":"party_scope_per_business","state":"not_built"},
  {"code":"scheme_books_posting","state":"not_built"}
]'::jsonb where code = 'hardware_paint' and modules = '[]'::jsonb;
update public.business_templates set modules = '[
  {"code":"cheque_pdc","state":"built","phase":127,"rule":"dealer_cheque_on"},
  {"code":"principal_schemes","state":"built","phase":128,"rule":"dealer_scheme_on"},
  {"code":"vehicle_stock_and_sales","state":"not_built"},
  {"code":"dealer_pos_screens","state":"not_built"},
  {"code":"party_scope_per_business","state":"not_built"}
]'::jsonb where code = 'dealership' and modules = '[]'::jsonb;

-- ---------- function grants ----------
revoke all on function public._tint_gate129(bigint, int, text, boolean), public._tint_uuid129(uuid, int), public._tint_formula_guard129(), public._tint_job_guard129() from public, anon, authenticated;
revoke all on function public.tint_formula_save(uuid, bigint, text, text, uuid, text, numeric, jsonb, text), public.tint_formula_retire(uuid),
  public.tint_job_run(uuid, int, uuid, numeric, uuid, text, date, numeric, text, boolean), public.tint_job_void(uuid, uuid, text),
  public.tint_formula_list(bigint, text, text), public.tint_formula_get(uuid), public.tint_job_list(bigint, date, date, uuid, int), public.tint_customer_shades(uuid, bigint),
  public.tint_job_cost(uuid), public.tint_cost_report(bigint, date, date) from public, anon;
grant execute on function public.tint_formula_save(uuid, bigint, text, text, uuid, text, numeric, jsonb, text), public.tint_formula_retire(uuid),
  public.tint_job_run(uuid, int, uuid, numeric, uuid, text, date, numeric, text, boolean), public.tint_job_void(uuid, uuid, text),
  public.tint_formula_list(bigint, text, text), public.tint_formula_get(uuid), public.tint_job_list(bigint, date, date, uuid, int), public.tint_customer_shades(uuid, bigint),
  public.tint_job_cost(uuid), public.tint_cost_report(bigint, date, date) to authenticated;

commit;

-- ---------------------------------------------------------------- phase527.sql
-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase131.sql there and is already pasted on the live database under that name.
-- Renumbered to phase527.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 527 (marker rpt131) - REPORTS STAGE 1 (sweets business): verified sales / status / profit / stock / wastage / cash / ageing reports.
-- ADDITIVE ONLY. Canonical order: after phase129 (phase130 is a test-only file). Paste twice = no change, no error.
-- Switch: rule rpt131_on, default OFF. While OFF every rpt131_* report returns {off:true, data_needed:true} and reads nothing. Nothing existing is changed or re-created.
-- Who may run: the existing report rights only (rpt_access('<group>') = owner, grant report_<group> or view_reports). Cost columns only for owner / rpt_cost_ok().
-- Scope: every report works on the places the caller may use (can_loc, which is business-safe when org_scope_on is ON). No company-wide figure is built for non-owners;
--   a place the caller may not use in p_locs is refused ('not allowed for this location'). Customer mobile numbers are not returned.
-- Books: the status / tie-out columns read journal_entries + journal_lines (posted entries, their reversals and voided originals); the books side is shown only to users who may
--   view accounts (_acct_view); others get null + a note, never a zero.
-- Honesty rules: empty result -> data_needed:true and totals:null (never a row of zeros); a quantity is never summed across items with different units; a cost that is not known
--   is counted and shown as unknown (cost_unknown), not as 0; an unset rule (age buckets) is reported as "data needed", not defaulted.
-- Statuses: a sale is posted | unposted (done, not yet in the books) | void (never in the books) | reversed (void, books reversed) | void_not_reversed (void, books still carry it).
--   Sales have no draft state in the database (the cart exists only on the phone), so "draft" is not a sale status here. Returns: same list; "refunded" = a done return exists.
-- Functions (browser): rpt131_catalog, rpt131_sales, rpt131_sales_recon, rpt131_item_profit, rpt131_stock_recon, rpt131_wastage, rpt131_cash_close, rpt131_ageing, rpt131_log_export.
-- Rollback: leave rpt131_on OFF. To remove: drop the functions below (nothing else refers to them).
-- ============================================================
begin;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('rpt131_on', 'reports', 'switch', 'false', null, null, null, null,
  'যাচাই করা রিপোর্ট (ধাপ ১) চালু', 'Verified reports (Stage 1) চালু', 'Verified reports (Stage 1)',
  'চালু করলে বিক্রি/স্ট্যাটাস, আইটেম লাভ, স্টক মিলানো, অপচয়, ক্যাশ ক্লোজ ও বাকি/পাওনার বয়স রিপোর্ট খোলে; সব হিসাব খাতার সাথে মেলানো।',
  'চালু করলে sales/status, item profit, stock reconcile, wastage, cash close ও ageing report খোলে; সব হিসাব books-এর সাথে মেলানো।',
  'When on, the sales / status, item profit, stock reconciliation, wastage, cash close and ageing reports open; every figure is tied to the books.', 1310)
on conflict (key) do nothing;

-- ---------- helpers (not callable from the browser) ----------
create or replace function public._rpt131_note(p_code text, p_en text, p_bn text, p_what text default null) returns jsonb
language sql immutable set search_path = public as
$$ select jsonb_strip_nulls(jsonb_build_object('code', p_code, 'text_en', p_en, 'text_bn', p_bn, 'what', p_what)) $$;

create or replace function public._rpt131_gate(p_group text) returns boolean
language plpgsql stable security definer set search_path = public as
$fn$
begin   -- rpt131: false = the module switch is OFF (caller returns the "off" answer); an unauthorised caller is refused either way
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rpt_access(p_group) then raise exception 'not allowed'; end if;
  return coalesce(public.rule_on('rpt131_on'), false);
end $fn$;

create or replace function public._rpt131_off(p_report text) returns jsonb
language sql stable set search_path = public as
$$ select jsonb_build_object('report', p_report, 'off', true, 'data_needed', true, 'generated_at', now(), 'rows', '[]'::jsonb, 'totals', null, 'row_count', 0,
   'notes', jsonb_build_array(public._rpt131_note('feature_off', 'Verified reports are switched off (rule rpt131_on).', 'যাচাই করা রিপোর্ট বন্ধ (rpt131_on নিয়ম)।'))) $$;

create or replace function public._rpt131_locs(p_locs int[]) returns int[]
language plpgsql stable security definer set search_path = public as
$fn$
declare acc int[]; bad int;
begin
  select coalesce(array_agg(l.id order by l.id), '{}') into acc from public.locations l where public.can_loc(l.id);
  if p_locs is not null and cardinality(p_locs) > 0 then
    select x into bad from unnest(p_locs) x where x is null or not (x = any (acc)) limit 1;
    if found then raise exception 'not allowed for this location'; end if;
    return (select array_agg(distinct x order by x) from unnest(p_locs) x);
  end if;
  return acc;
end $fn$;

create or replace function public._rpt131_dates(p_from date, p_to date, out d1 date, out d2 date, out defaulted boolean)
language plpgsql stable set search_path = public as
$fn$
declare td date := public._today();
begin
  if p_from is null and p_to is null then d1 := date_trunc('month', td)::date; d2 := td; defaulted := true;
  else d1 := coalesce(p_from, p_to); d2 := coalesce(p_to, td); defaulted := false; end if;
  if d1 < date '2000-01-01' or d2 > date '2100-01-01' or d2 < d1 or d2 - d1 > 366 then raise exception 'bad_range'; end if;
end $fn$;

-- search (any text in the row) + totals of the matching rows + sort + page. Totals are over ALL matching rows, not only the page.
create or replace function public._rpt131_finish(p_rows jsonb, p_sum text[], p_search text, p_sort text, p_page int, p_size int, p_defsort text) returns jsonb
language plpgsql stable set search_path = public as
$fn$
declare q text := nullif(btrim(coalesce(p_search, '')), ''); spec text := coalesce(nullif(btrim(p_sort), ''), p_defsort); sk text; sd text; sz int; pg int; n int;
        allrows jsonb; pagerows jsonb; tot jsonb := '{}'::jsonb; c text; v numeric;
begin
  sz := least(greatest(coalesce(p_size, 50), 5), 200); pg := least(greatest(coalesce(p_page, 1), 1), 100000);
  sk := lower(split_part(spec, ':', 1)); sd := case lower(split_part(spec, ':', 2)) when 'asc' then 'asc' else 'desc' end;
  if sk !~ '^[a-z0-9_]{1,40}$' then sk := lower(split_part(p_defsort, ':', 1)); sd := case lower(split_part(p_defsort, ':', 2)) when 'asc' then 'asc' else 'desc' end; end if;
  if q is not null then q := '%' || lower(replace(replace(replace(left(q, 60), '\', '\\'), '%', '\%'), '_', '\_')) || '%'; end if;
  select coalesce(jsonb_agg(r), '[]'::jsonb) into allrows from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) r where q is null or lower(r::text) like q;
  n := jsonb_array_length(allrows);
  foreach c in array coalesce(p_sum, '{}'::text[]) loop
    select sum((r ->> c)::numeric) into v from jsonb_array_elements(allrows) r where (r ->> c) ~ '^-?[0-9]+(\.[0-9]+)?$';
    tot := tot || jsonb_build_object(c, case when v is null then null else round(v, 4) end);
  end loop;
  if sd = 'asc' then
    select coalesce(jsonb_agg(x.r), '[]'::jsonb) into pagerows from (select r from jsonb_array_elements(allrows) r
      order by (case when r ->> sk ~ '^-?[0-9]+(\.[0-9]+)?$' then (r ->> sk)::numeric end) asc nulls last, r ->> sk asc nulls last, r::text asc offset (pg - 1) * sz limit sz) x;
  else
    select coalesce(jsonb_agg(x.r), '[]'::jsonb) into pagerows from (select r from jsonb_array_elements(allrows) r
      order by (case when r ->> sk ~ '^-?[0-9]+(\.[0-9]+)?$' then (r ->> sk)::numeric end) desc nulls last, r ->> sk desc nulls last, r::text asc offset (pg - 1) * sz limit sz) x;
  end if;
  return jsonb_build_object('rows', pagerows, 'totals', tot, 'row_count', n, 'page', pg, 'size', sz, 'has_more', n > pg * sz, 'sort', sk || ':' || sd);
end $fn$;

create or replace function public._rpt131_env(p_report text, p_filters jsonb, p_cols jsonb, p_fin jsonb, p_notes jsonb, p_extra jsonb default null) returns jsonb
language plpgsql stable security definer set search_path = public as
$fn$
declare sid text;
begin
  select coalesce(nullif(btrim(full_name), ''), staff_id) into sid from public.profiles where id = auth.uid();
  return jsonb_build_object('report', p_report, 'off', false, 'generated_at', now(), 'generated_by', sid, 'filters', p_filters, 'columns', p_cols,
    'rows', p_fin -> 'rows', 'totals', case when (p_fin ->> 'row_count')::int = 0 then null else p_fin -> 'totals' end,
    'row_count', (p_fin ->> 'row_count')::int, 'page', (p_fin ->> 'page')::int, 'size', (p_fin ->> 'size')::int, 'has_more', (p_fin ->> 'has_more')::boolean, 'sort', p_fin ->> 'sort',
    'data_needed', (p_fin ->> 'row_count')::int = 0, 'cost_visible', public.rpt_cost_ok(), 'notes', coalesce(p_notes, '[]'::jsonb)) || coalesce(p_extra, '{}'::jsonb);
end $fn$;

-- ---------- catalogue ----------
create or replace function public.rpt131_catalog() returns jsonb
language plpgsql stable security definer set search_path = public as
$fn$
declare on_ boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  on_ := coalesce(public.rule_on('rpt131_on'), false);
  return jsonb_build_object('enabled', on_, 'reports', jsonb_build_array(
    jsonb_build_object('key', 'rpt131_sales', 'group', 'sales', 'allowed', public.rpt_access('sales'), 'name_en', 'Sales, net of voids and returns', 'name_bn', 'বিক্রি (বাতিল ও ফেরত বাদে)',
       'groups', jsonb_build_array('day', 'week', 'month', 'outlet', 'hour', 'weekday', 'staff', 'sale_type', 'pay_mode')),
    jsonb_build_object('key', 'rpt131_sales_recon', 'group', 'sales', 'allowed', public.rpt_access('sales'), 'name_en', 'Sales status and books tie-out', 'name_bn', 'বিক্রির স্ট্যাটাস ও খাতার সাথে মিল',
       'statuses', jsonb_build_array('all', 'posted', 'unposted', 'void', 'reversed', 'void_not_reversed', 'refunded', 'problems')),
    jsonb_build_object('key', 'rpt131_item_profit', 'group', 'profit', 'allowed', public.rpt_access('profit'), 'name_en', 'Item / category / outlet profit (real costs)', 'name_bn', 'আইটেম / ক্যাটাগরি / আউটলেট লাভ',
       'groups', jsonb_build_array('item', 'category', 'outlet')),
    jsonb_build_object('key', 'rpt131_stock_recon', 'group', 'stock', 'allowed', public.rpt_access('stock'), 'name_en', 'Stock reconciliation (opening + in - out = closing)', 'name_bn', 'স্টক মিলানো'),
    jsonb_build_object('key', 'rpt131_wastage', 'group', 'stock', 'allowed', public.rpt_access('stock'), 'name_en', 'Wastage by reason, item, outlet, status', 'name_bn', 'অপচয়',
       'groups', jsonb_build_array('reason', 'item', 'outlet', 'day', 'status', 'doc'), 'statuses', jsonb_build_array('all', 'posted', 'pending', 'rejected', 'cancelled', 'reversed')),
    jsonb_build_object('key', 'rpt131_cash_close', 'group', 'cash', 'allowed', public.rpt_access('cash'), 'name_en', 'Cash book and day close', 'name_bn', 'ক্যাশ বই ও দিনশেষ'),
    jsonb_build_object('key', 'rpt131_ageing', 'group', 'customers', 'allowed', public.rpt_access('customers') or public.rpt_access('purchase'), 'name_en', 'Receivable and payable ageing', 'name_bn', 'বাকি ও পাওনার বয়স',
       'kinds', jsonb_build_array('receivable', 'payable'))));
end $fn$;

-- ---------- 1. sales net of voids and returns ----------
create or replace function public.rpt131_sales(p_from date default null, p_to date default null, p_locs int[] default null, p_group text default 'day',
                                              p_search text default null, p_sort text default null, p_page int default 1, p_size int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as
$fn$
declare dd record; locs int[]; g text := lower(btrim(coalesce(p_group, 'day'))); notes jsonb := '[]'::jsonb; rws jsonb; cols jsonb; fin jsonb; dimx text; lb text; le text; jn text := ''; defsort text;
        sumcols text[];
begin
  if not public._rpt131_gate('sales') then return public._rpt131_off('rpt131_sales'); end if;
  if g not in ('day', 'week', 'month', 'outlet', 'hour', 'weekday', 'staff', 'sale_type', 'pay_mode') then raise exception 'bad_group'; end if;
  select * into dd from public._rpt131_dates(p_from, p_to);
  locs := public._rpt131_locs(p_locs);
  if dd.defaulted then notes := notes || public._rpt131_note('default_period', 'No period given: this month to date.', 'সময় দেওয়া হয়নি: এই মাসের আজ পর্যন্ত।'); end if;
  if cardinality(locs) = 0 then
    notes := notes || public._rpt131_note('no_location', 'No place is open to you.', 'কোনো লোকেশন আপনার জন্য খোলা নেই।');
    return public._rpt131_env('rpt131_sales', jsonb_build_object('from', dd.d1, 'to', dd.d2, 'locs', p_locs, 'group', g), '[]'::jsonb, public._rpt131_finish('[]'::jsonb, '{}'::text[], null, null, 1, 50, 'dim:asc'), notes);
  end if;
  notes := notes || public._rpt131_note('basis', 'Voided bills are shown apart and never counted. Returns are counted on the day they were made, at the place they were made.', 'বাতিল বিল আলাদা দেখানো, গোনা হয়নি। ফেরত ফেরতের দিনে ধরা।');
  if g = 'week' then notes := notes || public._rpt131_note('week_start', 'Weeks start on Monday.', 'সপ্তাহ সোমবার থেকে শুরু।'); end if;

  if g = 'pay_mode' then
    notes := notes || public._rpt131_note('pay_basis', 'Received = money taken with the bill; Due = sold on credit; Refunded = cash/mobile/card given back plus credit given on returns; Collections (old dues paid) are shown for information and are not sales.', 'Received = বিলের সাথে নেওয়া টাকা; Due = বাকিতে বিক্রি; Refunded = ফেরত দেওয়া টাকা ও ক্রেডিট; Collections তথ্যের জন্য, বিক্রি নয়।');
    with pay as (
        select p.mode m, sum(p.amount) v, count(distinct p.sale_id) n from public.sale_payments p join public.sales s on s.id = p.sale_id
         where p.kind = 'sale' and not p.voided and s.status = 'done' and s.sale_date between dd.d1 and dd.d2 and s.location_id = any (locs) group by p.mode),
      col as (
        select p.mode m, sum(p.amount) v from public.sale_payments p
         where p.kind = 'collection' and not p.voided and (p.paid_at at time zone 'Asia/Dhaka')::date between dd.d1 and dd.d2 and p.location_id = any (locs) group by p.mode),
      rf as (
        select r.refund_mode m, sum(r.refund_amount) v from public.sale_returns r
         where r.status = 'done' and r.refund_amount > 0 and (r.created_at at time zone 'Asia/Dhaka')::date between dd.d1 and dd.d2 and r.location_id = any (locs) group by r.refund_mode),
      due as (
        select coalesce(sum(s.due_amount), 0) v, count(*) filter (where s.due_amount > 0) n from public.sales s
         where s.status = 'done' and s.sale_date between dd.d1 and dd.d2 and s.location_id = any (locs)),
      duer as (
        select coalesce(sum(r.credit_amount), 0) v from public.sale_returns r
         where r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between dd.d1 and dd.d2 and r.location_id = any (locs)),
      modes as (select m from pay union select m from col union select m from rf),
      x as (
        select m.m dim, m.m label_en, m.m label_bn, coalesce(pay.n, 0) bills, coalesce(pay.v, 0) received, col.v collections, coalesce(rf.v, 0) refunded
          from modes m left join pay on pay.m = m.m left join col on col.m = m.m left join rf on rf.m = m.m
        union all
        select 'due', 'On credit (due)', 'বাকিতে', due.n, due.v, null, duer.v from due, duer where due.v > 0 or duer.v > 0)
    select coalesce(jsonb_agg(jsonb_build_object('dim', x.dim, 'label_en', x.label_en, 'label_bn', x.label_bn, 'bills', x.bills, 'received', round(x.received, 2), 'collections', round(x.collections, 2),
                    'refunded', round(x.refunded, 2), 'net_sales', round(x.received - x.refunded, 2)) order by x.dim), '[]'::jsonb) into rws from x;
    cols := '[{"k":"label","bn":"পেমেন্ট","en":"Payment","t":"text"},{"k":"bills","bn":"বিল","en":"Bills","t":"int"},{"k":"received","bn":"নেওয়া / বাকি","en":"Received / due","t":"money","sum":true},
              {"k":"refunded","bn":"ফেরত","en":"Refunded","t":"money","sum":true},{"k":"net_sales","bn":"নিট","en":"Net","t":"money","sum":true},{"k":"collections","bn":"আদায় (তথ্য)","en":"Collections (info)","t":"money","sum":true}]'::jsonb;
    sumcols := array['received', 'refunded', 'net_sales', 'collections'];
    fin := public._rpt131_finish(rws, sumcols, p_search, p_sort, p_page, p_size, 'net_sales:desc');
    return public._rpt131_env('rpt131_sales', jsonb_build_object('from', dd.d1, 'to', dd.d2, 'locs', p_locs, 'group', g, 'search', p_search), cols, fin, notes);
  end if;

  dimx := case g when 'day' then 'u.d::text' when 'week' then $$date_trunc('week', u.d)::date::text$$ when 'month' then $$to_char(u.d, 'YYYY-MM')$$ when 'outlet' then 'u.loc::text'
            when 'hour' then $$lpad(extract(hour from (u.t at time zone 'Asia/Dhaka'))::int::text, 2, '0')$$ when 'weekday' then $$extract(isodow from (u.t at time zone 'Asia/Dhaka'))::int::text$$
            when 'staff' then 'u.staff' else $$coalesce(u.stype, 'retail')$$ end;
  lb := case g when 'outlet' then 'coalesce(lo.name_bn, a.dim)' when 'hour' then $$a.dim || ':00'$$ when 'weekday' then $$(array['সোম','মঙ্গল','বুধ','বৃহস্পতি','শুক্র','শনি','রবি'])[a.dim::int]$$ else 'a.dim' end;
  le := case g when 'outlet' then 'coalesce(lo.name_en, lo.name_bn, a.dim)' when 'hour' then $$a.dim || ':00'$$ when 'weekday' then $$(array['Mon','Tue','Wed','Thu','Fri','Sat','Sun'])[a.dim::int]$$ else 'a.dim' end;
  if g = 'outlet' then jn := 'left join public.locations lo on lo.id = a.dim::int'; end if;
  defsort := case when g in ('outlet', 'staff', 'sale_type') then 'net_sales:desc' else 'dim:asc' end;
  execute format($q$
    with u as (
      select 'sale'::text src, s.location_id loc, s.sale_date d, s.sold_at t, coalesce(nullif(btrim(s.created_staff), ''), '-') staff, s.sale_type stype, s.subtotal gross, s.discount disc, s.total net
        from public.sales s where s.status = 'done' and s.sale_date between $1 and $2 and s.location_id = any ($3)
      union all
      select 'void', s.location_id, s.sale_date, s.sold_at, coalesce(nullif(btrim(s.created_staff), ''), '-'), s.sale_type, s.subtotal, s.discount, s.total
        from public.sales s where s.status = 'void' and s.sale_date between $1 and $2 and s.location_id = any ($3)
      union all
      select 'ret', r.location_id, (r.created_at at time zone 'Asia/Dhaka')::date, r.created_at, coalesce(nullif(btrim(r.created_staff), ''), '-'), x.sale_type, 0, 0, r.amount
        from public.sale_returns r left join public.sales x on x.id = r.sale_id
       where r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between $1 and $2 and r.location_id = any ($3)),
    a as (
      select %s as dim, count(*) filter (where src = 'sale') bills, coalesce(sum(gross) filter (where src = 'sale'), 0) gross, coalesce(sum(disc) filter (where src = 'sale'), 0) discount,
             coalesce(sum(net) filter (where src = 'sale'), 0) sales_net, count(*) filter (where src = 'void') void_bills, coalesce(sum(net) filter (where src = 'void'), 0) void_value,
             count(*) filter (where src = 'ret') return_count, coalesce(sum(net) filter (where src = 'ret'), 0) returns
        from u group by 1)
    select coalesce(jsonb_agg(jsonb_build_object('dim', a.dim, 'label_bn', %s, 'label_en', %s, 'bills', a.bills, 'gross', round(a.gross, 2), 'discount', round(a.discount, 2),
             'sales_net', round(a.sales_net, 2), 'return_count', a.return_count, 'returns', round(a.returns, 2), 'net_sales', round(a.sales_net - a.returns, 2),
             'avg_bill', case when a.bills > 0 then round(a.sales_net / a.bills, 2) end, 'return_pct', case when a.sales_net > 0 then round(100 * a.returns / a.sales_net, 2) end,
             'void_bills', a.void_bills, 'void_value', round(a.void_value, 2)) order by a.dim), '[]'::jsonb)
      from a %s$q$, dimx, lb, le, jn) into rws using dd.d1, dd.d2, locs;
  cols := jsonb_build_array(jsonb_build_object('k', 'label', 'bn', 'ভাগ', 'en', 'Group', 't', 'text'),
    '{"k":"bills","bn":"বিল","en":"Bills","t":"int","sum":true}'::jsonb, '{"k":"gross","bn":"মোট (ছাড়ের আগে)","en":"Gross","t":"money","sum":true}'::jsonb,
    '{"k":"discount","bn":"ছাড়","en":"Discount","t":"money","sum":true}'::jsonb, '{"k":"sales_net","bn":"বিক্রি","en":"Sales","t":"money","sum":true}'::jsonb,
    '{"k":"returns","bn":"ফেরত","en":"Returns","t":"money","sum":true}'::jsonb, '{"k":"net_sales","bn":"নিট বিক্রি","en":"Net sales","t":"money","sum":true}'::jsonb,
    '{"k":"avg_bill","bn":"গড় বিল","en":"Avg bill","t":"money"}'::jsonb, '{"k":"return_pct","bn":"ফেরত %","en":"Return %","t":"pct"}'::jsonb,
    '{"k":"void_bills","bn":"বাতিল বিল","en":"Void bills","t":"int","sum":true}'::jsonb, '{"k":"void_value","bn":"বাতিল টাকা","en":"Void value","t":"money","sum":true}'::jsonb);
  sumcols := array['bills', 'gross', 'discount', 'sales_net', 'return_count', 'returns', 'net_sales', 'void_bills', 'void_value'];
  fin := public._rpt131_finish(rws, sumcols, p_search, p_sort, p_page, p_size, defsort);
  return public._rpt131_env('rpt131_sales', jsonb_build_object('from', dd.d1, 'to', dd.d2, 'locs', p_locs, 'group', g, 'search', p_search), cols, fin, notes);
end $fn$;

-- ---------- 2. sales / return documents: status and tie-out to the books ----------
create or replace function public.rpt131_sales_recon(p_from date default null, p_to date default null, p_locs int[] default null, p_status text default 'all',
                                                    p_search text default null, p_sort text default null, p_page int default 1, p_size int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as
$fn$
declare dd record; locs int[]; v_st text := lower(btrim(coalesce(p_status, 'all'))); notes jsonb := '[]'::jsonb; rws jsonb; fin jsonb; cols jsonb; books boolean; a_s bigint; a_d bigint; a_r bigint;
        summ jsonb; tie jsonb; jb numeric; cap constant int := 5000; ndocs int;
begin
  if not public._rpt131_gate('sales') then return public._rpt131_off('rpt131_sales_recon'); end if;
  if v_st not in ('all', 'posted', 'unposted', 'void', 'reversed', 'void_not_reversed', 'refunded', 'problems') then raise exception 'bad_status'; end if;
  select * into dd from public._rpt131_dates(p_from, p_to);
  if dd.d2 - dd.d1 > 92 then raise exception 'bad_range'; end if;
  locs := public._rpt131_locs(p_locs);
  books := public._acct_view();
  if dd.defaulted then notes := notes || public._rpt131_note('default_period', 'No period given: this month to date.', 'সময় দেওয়া হয়নি: এই মাসের আজ পর্যন্ত।'); end if;
  if cardinality(locs) = 0 then
    notes := notes || public._rpt131_note('no_location', 'No place is open to you.', 'কোনো লোকেশন আপনার জন্য খোলা নেই।');
    return public._rpt131_env('rpt131_sales_recon', jsonb_build_object('from', dd.d1, 'to', dd.d2, 'status', v_st), '[]'::jsonb, public._rpt131_finish('[]'::jsonb, '{}'::text[], null, null, 1, 50, 'd:desc'), notes);
  end if;
  if not books then
    notes := notes || public._rpt131_note('books_hidden', 'You may not view the accounts: the books side (status, tie-out) is not shown.', 'আপনি হিসাব দেখতে পারেন না: খাতার দিক দেখানো হয়নি।');
    -- without the books the register still lists the documents, with the register status only
  end if;
  select account_id into a_s from public.acct_mappings where key = 'sales';
  select account_id into a_d from public.acct_mappings where key = 'sales_discount';
  select account_id into a_r from public.acct_mappings where key = 'sales_returns';
  notes := notes || public._rpt131_note('basis', 'Register amount = sale total (after discount) for a done sale, minus the return amount for a done return; a void document counts 0. Books amount = what the journal holds for that document (a reversed document nets to 0). Sales are posted to the books in batches, so a done sale can be "unposted" for a while. Draft does not exist for sales.', 'রেজিস্টার = বিক্রির মোট; ফেরত বিয়োগ; বাতিল = ০। খাতা = জার্নালে যা আছে। বিক্রি ব্যাচে খাতায় যায়, তাই কিছু বিল "unposted" থাকতে পারে।');

  with docs as (
      select 'sale'::text doc_type, s.id doc_id, s.receipt::text ref, s.sale_date d, s.location_id loc, s.status st, s.total amt, s.subtotal gross, s.discount disc,
             coalesce(nullif(btrim(s.customer), ''), '-') party, coalesce(nullif(btrim(s.created_staff), ''), '-') staff, null::uuid sale_id
        from public.sales s where s.sale_date between dd.d1 and dd.d2 and s.location_id = any (locs)
      union all
      select 'return', r.id, 'R-' || coalesce(x.receipt::text, '?'), (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, r.status, r.amount, 0, 0,
             coalesce(nullif(btrim(x.customer), ''), '-'), coalesce(nullif(btrim(r.created_staff), ''), '-'), r.sale_id
        from public.sale_returns r left join public.sales x on x.id = r.sale_id
       where (r.created_at at time zone 'Asia/Dhaka')::date between dd.d1 and dd.d2 and r.location_id = any (locs)),
    c as (
      select dc.*, case when books then jj.n_orig end n_orig, case when books then jj.n_rev end n_rev,
             case dc.doc_type when 'sale' then jj.bs else jj.br end books_abs,
             coalesce((select sum(r2.amount) from public.sale_returns r2 where dc.doc_type = 'sale' and r2.sale_id = dc.doc_id and r2.status = 'done'), 0) returned
        from docs dc
        left join lateral (
          select coalesce(sum(l.credit - l.debit) filter (where l.account_id in (a_s, a_d)), 0) bs, coalesce(sum(l.debit - l.credit) filter (where l.account_id = a_r), 0) br,
                 count(distinct e.id) filter (where e.reverses_id is null) n_orig, count(distinct e.id) filter (where e.reverses_id is not null) n_rev
            from public.journal_entries e join public.journal_lines l on l.entry_id = e.id
           where books and e.source_type = (case dc.doc_type when 'sale' then 'sale' else 'sale_return' end) and e.source_id = dc.doc_id::text) jj on true),
    k as (
      select c.*, (case c.doc_type when 'sale' then 1 else -1 end) sg,
             case when not books then case c.st when 'done' then 'done' else 'void' end
                  when c.st = 'done' then case when c.n_orig > 0 then 'posted' else 'unposted' end
                  else case when c.n_orig > 0 and c.n_rev > 0 then 'reversed' when c.n_orig > 0 then 'void_not_reversed' else 'void' end end dstatus,
             case when c.st = 'done' then c.amt else 0 end reg_abs
        from c),
    f as (
      select k.*, round(k.sg * k.reg_abs, 2) reg_net, case when books then round(k.sg * coalesce(k.books_abs, 0), 2) end books_net,
             case when books then round(k.sg * (k.reg_abs - coalesce(k.books_abs, 0)), 2) end diff,
             case when k.doc_type = 'sale' then case when k.returned <= 0.004 then 'none' when k.returned >= k.amt - 0.005 then 'full' else 'partial' end end refund_state
        from k)
  select count(*),
         jsonb_build_object('by_status', coalesce((select jsonb_object_agg(z.dstatus || '/' || z.doc_type, jsonb_build_object('docs', z.n, 'register_net', z.rn, 'books_net', z.bn))
                                                    from (select f.dstatus, f.doc_type, count(*) n, round(sum(f.reg_net), 2) rn, round(sum(f.books_net), 2) bn from f group by 1, 2) z), '{}'::jsonb),
                            'register_net_total', round(coalesce(sum(f.reg_net), 0), 2), 'docs_books_net_total', case when books then round(coalesce(sum(f.books_net), 0), 2) end,
                            'unposted_value', case when books then round(coalesce(sum(f.reg_net) filter (where f.dstatus = 'unposted'), 0), 2) end,
                            'amount_differs_value', case when books then round(coalesce(sum(f.diff) filter (where f.dstatus = 'posted' and abs(f.diff) > 0.005), 0), 2) end,
                            'not_reversed_docs', case when books then count(*) filter (where f.dstatus = 'void_not_reversed') end)
    into ndocs, summ from f;
  with docs as (
      select 'sale'::text doc_type, s.id doc_id, s.receipt::text ref, s.sale_date d, s.location_id loc, s.status st, s.total amt, s.subtotal gross, s.discount disc,
             coalesce(nullif(btrim(s.customer), ''), '-') party, coalesce(nullif(btrim(s.created_staff), ''), '-') staff
        from public.sales s where s.sale_date between dd.d1 and dd.d2 and s.location_id = any (locs)
      union all
      select 'return', r.id, 'R-' || coalesce(x.receipt::text, '?'), (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, r.status, r.amount, 0, 0,
             coalesce(nullif(btrim(x.customer), ''), '-'), coalesce(nullif(btrim(r.created_staff), ''), '-')
        from public.sale_returns r left join public.sales x on x.id = r.sale_id
       where (r.created_at at time zone 'Asia/Dhaka')::date between dd.d1 and dd.d2 and r.location_id = any (locs)),
    c as (
      select dc.*, case when books then jj.n_orig end n_orig, case when books then jj.n_rev end n_rev, case dc.doc_type when 'sale' then jj.bs else jj.br end books_abs,
             coalesce((select sum(r2.amount) from public.sale_returns r2 where dc.doc_type = 'sale' and r2.sale_id = dc.doc_id and r2.status = 'done'), 0) returned
        from docs dc
        left join lateral (
          select coalesce(sum(l.credit - l.debit) filter (where l.account_id in (a_s, a_d)), 0) bs, coalesce(sum(l.debit - l.credit) filter (where l.account_id = a_r), 0) br,
                 count(distinct e.id) filter (where e.reverses_id is null) n_orig, count(distinct e.id) filter (where e.reverses_id is not null) n_rev
            from public.journal_entries e join public.journal_lines l on l.entry_id = e.id
           where books and e.source_type = (case dc.doc_type when 'sale' then 'sale' else 'sale_return' end) and e.source_id = dc.doc_id::text) jj on true),
    k as (
      select c.*, (case c.doc_type when 'sale' then 1 else -1 end) sg,
             case when not books then case c.st when 'done' then 'done' else 'void' end
                  when c.st = 'done' then case when c.n_orig > 0 then 'posted' else 'unposted' end
                  else case when c.n_orig > 0 and c.n_rev > 0 then 'reversed' when c.n_orig > 0 then 'void_not_reversed' else 'void' end end dstatus,
             case when c.st = 'done' then c.amt else 0 end reg_abs
        from c),
    f as (
      select k.*, round(k.sg * k.reg_abs, 2) reg_net, case when books then round(k.sg * coalesce(k.books_abs, 0), 2) end books_net,
             case when books then round(k.sg * (k.reg_abs - coalesce(k.books_abs, 0)), 2) end diff,
             case when k.doc_type = 'sale' then case when k.returned <= 0.004 then 'none' when k.returned >= k.amt - 0.005 then 'full' else 'partial' end end refund_state,
             case when not books then null when k.dstatus = 'unposted' then 'unposted' when k.dstatus = 'void_not_reversed' then 'books_not_reversed'
                  when abs(k.sg * (k.reg_abs - coalesce(k.books_abs, 0))) > 0.005 then 'amount_differs' end flag
        from k),
    sel as (
      select f.* from f
       where case v_st when 'all' then true when 'refunded' then (f.doc_type = 'return' and f.st = 'done') or coalesce(f.refund_state, 'none') <> 'none'
                     when 'problems' then f.flag is not null else f.dstatus = v_st end
       order by f.d desc, f.ref desc limit cap)
  select coalesce(jsonb_agg(jsonb_build_object('doc_type', sel.doc_type, 'doc_id', sel.doc_id, 'ref', sel.ref, 'd', sel.d, 'loc', sel.loc,
           'outlet_en', (select coalesce(lo.name_en, lo.name_bn) from public.locations lo where lo.id = sel.loc), 'outlet_bn', (select lo.name_bn from public.locations lo where lo.id = sel.loc),
           'party', sel.party, 'staff', sel.staff, 'gross', case when sel.doc_type = 'sale' and sel.st = 'done' then sel.gross end, 'discount', case when sel.doc_type = 'sale' and sel.st = 'done' then sel.disc end,
           'register_net', sel.reg_net, 'books_net', sel.books_net, 'diff', sel.diff, 'status', sel.dstatus, 'refund_state', sel.refund_state, 'returned', case when sel.doc_type = 'sale' then round(sel.returned, 2) end,
           'flag', sel.flag, 'doc_status', sel.st)), '[]'::jsonb) into rws from sel;
  if books then
    select a_s is not null into books;   -- the three mappings must exist for the account view
    if books then
      select round(coalesce(sum(l.credit - l.debit) filter (where l.account_id in (a_s, a_d)), 0) - coalesce(sum(l.debit - l.credit) filter (where l.account_id = a_r), 0), 2) into jb
        from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
       where e.entry_date between dd.d1 and dd.d2 and l.location_id = any (locs) and l.account_id in (a_s, a_d, a_r);
    end if;
  end if;
  tie := jsonb_build_object('register_net_total', summ -> 'register_net_total', 'docs_books_net_total', summ -> 'docs_books_net_total', 'journal_by_entry_date', jb,
         'unposted_value', summ -> 'unposted_value', 'amount_differs_value', summ -> 'amount_differs_value', 'not_reversed_docs', summ -> 'not_reversed_docs',
         'explained_gap', case when summ ->> 'docs_books_net_total' is null then null else round((summ ->> 'register_net_total')::numeric - (summ ->> 'docs_books_net_total')::numeric, 2) end);
  if jb is not null and summ ->> 'docs_books_net_total' is not null and abs(jb - (summ ->> 'docs_books_net_total')::numeric) > 0.005 then
    notes := notes || public._rpt131_note('journal_date_gap', 'The journal by entry date differs from the documents of the period (a reversal or a manual entry fell in another period, or a document was posted on another date).', 'এন্ট্রির তারিখ ধরে জার্নাল আর এই সময়ের ডকুমেন্ট মেলেনি (রিভার্সাল/ম্যানুয়াল এন্ট্রি অন্য সময়ে)।');
  end if;
  if ndocs > cap then notes := notes || public._rpt131_note('truncated', 'More than 5000 documents: the list shows the newest 5000; the summary covers all. Narrow the filters.', '৫০০০-এর বেশি ডকুমেন্ট: তালিকায় নতুন ৫০০০, সারাংশে সব। ফিল্টার ছোট করুন।'); end if;
  fin := public._rpt131_finish(rws, array['gross', 'discount', 'register_net', 'books_net', 'diff'], p_search, p_sort, p_page, p_size, 'd:desc');
  cols := '[{"k":"d","bn":"তারিখ","en":"Date","t":"date"},{"k":"ref","bn":"রসিদ","en":"Receipt","t":"text"},{"k":"doc_type","bn":"ধরন","en":"Type","t":"text"},{"k":"outlet","bn":"আউটলেট","en":"Outlet","t":"text"},
            {"k":"party","bn":"গ্রাহক","en":"Customer","t":"text"},{"k":"register_net","bn":"রেজিস্টার","en":"Register","t":"money","sum":true},{"k":"books_net","bn":"খাতা","en":"Books","t":"money","sum":true},
            {"k":"diff","bn":"পার্থক্য","en":"Difference","t":"money","sum":true},{"k":"status","bn":"স্ট্যাটাস","en":"Status","t":"status"},{"k":"refund_state","bn":"ফেরত","en":"Refunded","t":"status"}]'::jsonb;
  return public._rpt131_env('rpt131_sales_recon', jsonb_build_object('from', dd.d1, 'to', dd.d2, 'locs', p_locs, 'status', v_st, 'search', p_search), cols, fin, notes,
           jsonb_build_object('summary', summ, 'tie_out', tie, 'books_visible', books is true, 'truncated', ndocs > cap));
end $fn$;

-- ---------- 3. item / category / outlet profit with real costs ----------
create or replace function public.rpt131_item_profit(p_from date default null, p_to date default null, p_locs int[] default null, p_group text default 'item',
                                                    p_category text default null, p_item uuid default null, p_search text default null, p_sort text default null,
                                                    p_page int default 1, p_size int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as
$fn$
declare dd record; locs int[]; g text := lower(btrim(coalesce(p_group, 'item'))); notes jsonb := '[]'::jsonb; rws jsonb; fin jsonb; cols jsonb; cost_ok boolean; net_on boolean;
        cat text := nullif(btrim(coalesce(p_category, '')), '');
begin
  if not public._rpt131_gate('profit') then return public._rpt131_off('rpt131_item_profit'); end if;
  if g not in ('item', 'category', 'outlet') then raise exception 'bad_group'; end if;
  select * into dd from public._rpt131_dates(p_from, p_to);
  locs := public._rpt131_locs(p_locs);
  cost_ok := public.rpt_cost_ok();
  net_on := coalesce(public.rule_on('reports_net_of_returns'), true);
  if dd.defaulted then notes := notes || public._rpt131_note('default_period', 'No period given: this month to date.', 'সময় দেওয়া হয়নি: এই মাসের আজ পর্যন্ত।'); end if;
  if cardinality(locs) = 0 then
    notes := notes || public._rpt131_note('no_location', 'No place is open to you.', 'কোনো লোকেশন আপনার জন্য খোলা নেই।');
    return public._rpt131_env('rpt131_item_profit', jsonb_build_object('from', dd.d1, 'to', dd.d2, 'group', g), '[]'::jsonb, public._rpt131_finish('[]'::jsonb, '{}'::text[], null, null, 1, 50, 'revenue:desc'), notes);
  end if;
  notes := notes || public._rpt131_note('basis', 'Revenue is after the bill discount. Real cost = the cost recorded in the stock ledger when the item was sold. Margin is worked out only on the part of the revenue that has a real cost; revenue without a known cost is shown as uncosted, never as free.', 'রেভিনিউ = বিল ছাড়ের পরে। আসল খরচ = বিক্রির সময় স্টক লেজারে লেখা খরচ। মার্জিন শুধু খরচ জানা অংশে; অজানা খরচ আলাদা দেখানো।');
  if not net_on then notes := notes || public._rpt131_note('returns_not_netted', 'Rule reports_net_of_returns is OFF: returns are NOT taken out of these figures.', 'reports_net_of_returns বন্ধ: ফেরত বাদ দেওয়া হয়নি।'); end if;
  if not cost_ok then notes := notes || public._rpt131_note('cost_hidden', 'Cost and margin columns are hidden for your role.', 'আপনার ভূমিকার জন্য খরচ ও মার্জিন লুকানো।'); end if;
  with l as (select * from public._cogs_lines72(dd.d1, dd.d2, locs)),
    x as (
      select case g when 'item' then coalesce(l.item_id::text, '-') when 'category' then coalesce(nullif(i.category, ''), '-') else l.loc::text end k,
             max(case g when 'item' then coalesce(i.name_bn, 'Unlisted') when 'category' then coalesce(nullif(i.category_bn, ''), nullif(i.category, ''), '-') else lo.name_bn end) nbn,
             max(case g when 'item' then coalesce(i.name_en, i.name_bn, 'Unlisted / quick') when 'category' then coalesce(nullif(i.category, ''), '-') else coalesce(lo.name_en, lo.name_bn) end) nen,
             max(case g when 'item' then coalesce(nullif(i.category, ''), '-') end) catx, max(i.unit) unit,
             sum(case l.src when 'sale' then 1 else -1 end * l.qty) qty, sum(case l.src when 'sale' then 1 else -1 end * l.rev) rev,
             sum(case l.src when 'sale' then 1 else -1 end * l.led_rev) led_rev, sum(case l.src when 'sale' then 1 else -1 end * l.led_cogs) led_cogs,
             sum(case l.src when 'sale' then 1 else -1 end * l.fb_rev) fb_rev, sum(case l.src when 'sale' then 1 else -1 end * l.fb_cogs) fb_cogs,
             sum(case l.src when 'sale' then 1 else -1 end * l.unk_rev) unk_rev, count(distinct l.item_id) n_items
        from l left join public.items i on i.id = l.item_id left join public.locations lo on lo.id = l.loc
       where (p_item is null or l.item_id = p_item) and (cat is null or i.category = cat)
       group by 1)
  select coalesce(jsonb_agg(jsonb_build_object('key', x.k, 'name_bn', x.nbn, 'name_en', x.nen, 'category', x.catx, 'unit', x.unit,
           'qty', case when g = 'item' then round(x.qty, 4) end, 'items', case when g <> 'item' then x.n_items end, 'revenue', round(x.rev, 2),
           'cost_real', case when cost_ok and (x.led_rev <> 0 or x.led_cogs <> 0) then round(x.led_cogs, 2) end,
           'margin', case when cost_ok and x.led_rev <> 0 then round(x.led_rev - x.led_cogs, 2) end,
           'margin_pct', case when cost_ok and x.led_rev > 0 then round(100 * (x.led_rev - x.led_cogs) / x.led_rev, 2) end,
           'costed_pct', case when x.rev > 0 then round(100 * x.led_rev / x.rev, 1) end,
           'cost_estimated', case when cost_ok then round(x.fb_cogs, 2) end, 'estimated_rev', round(x.fb_rev, 2), 'uncosted_rev', round(x.unk_rev, 2)) order by x.k), '[]'::jsonb) into rws from x;
  cols := jsonb_build_array(jsonb_build_object('k', 'label', 'bn', 'নাম', 'en', 'Name', 't', 'text'),
    '{"k":"qty","bn":"পরিমাণ","en":"Qty","t":"qty"}'::jsonb, '{"k":"revenue","bn":"রেভিনিউ","en":"Revenue","t":"money","sum":true}'::jsonb,
    '{"k":"cost_real","bn":"আসল খরচ","en":"Real cost","t":"money","sum":true,"cost":true}'::jsonb, '{"k":"margin","bn":"মার্জিন (খরচ জানা অংশে)","en":"Margin (costed part)","t":"money","sum":true,"cost":true}'::jsonb,
    '{"k":"margin_pct","bn":"মার্জিন %","en":"Margin %","t":"pct","cost":true}'::jsonb, '{"k":"costed_pct","bn":"খরচ জানা %","en":"Costed %","t":"pct"}'::jsonb,
    '{"k":"uncosted_rev","bn":"খরচ অজানা রেভিনিউ","en":"Uncosted revenue","t":"money","sum":true}'::jsonb);
  fin := public._rpt131_finish(rws, array['revenue', 'cost_real', 'margin', 'cost_estimated', 'estimated_rev', 'uncosted_rev'], p_search, p_sort, p_page, p_size, 'revenue:desc');
  return public._rpt131_env('rpt131_item_profit', jsonb_build_object('from', dd.d1, 'to', dd.d2, 'locs', p_locs, 'group', g, 'category', cat, 'item', p_item, 'search', p_search), cols, fin, notes,
           jsonb_build_object('returns_netted', net_on));
end $fn$;

-- ---------- 4. stock reconciliation (adapter over stock_recon_statement: paging, search, status, no cross-unit totals) ----------
create or replace function public.rpt131_stock_recon(p_from date default null, p_to date default null, p_locs int[] default null, p_category text default null, p_item uuid default null,
                                                    p_issues_only boolean default false, p_search text default null, p_sort text default null, p_page int default 1, p_size int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as
$fn$
declare dd record; locs int[]; notes jsonb := '[]'::jsonb; rws jsonb := '[]'::jsonb; fin jsonb; cols jsonb; s jsonb; x int; trunc boolean := false; n_unb int := 0; n_var int := 0; n_all int := 0;
        cat text := nullif(btrim(coalesce(p_category, '')), '');
begin
  if not public._rpt131_gate('stock') then return public._rpt131_off('rpt131_stock_recon'); end if;
  select * into dd from public._rpt131_dates(p_from, p_to);
  if dd.d2 - dd.d1 > 366 then raise exception 'bad_range'; end if;
  locs := public._rpt131_locs(p_locs);
  if dd.defaulted then notes := notes || public._rpt131_note('default_period', 'No period given: this month to date.', 'সময় দেওয়া হয়নি: এই মাসের আজ পর্যন্ত।'); end if;
  if cardinality(locs) = 0 then
    notes := notes || public._rpt131_note('no_location', 'No place is open to you.', 'কোনো লোকেশন আপনার জন্য খোলা নেই।');
    return public._rpt131_env('rpt131_stock_recon', jsonb_build_object('from', dd.d1, 'to', dd.d2), '[]'::jsonb, public._rpt131_finish('[]'::jsonb, '{}'::text[], null, null, 1, 50, 'item_code:asc'), notes);
  end if;
  notes := notes || public._rpt131_note('formula', 'opening + in (production, purchases, transfers in, customer give-backs) - out (used, sold, wasted, transit loss, transfers out) + adjustments = closing. "check" must be 0. "variance" = stock ledger total minus the stored balance. Quantities are never added across items.', 'শুরু + আসা - যাওয়া + সমন্বয় = শেষ। "check" ০ হতে হবে। পরিমাণ ভিন্ন আইটেমে যোগ করা হয় না।');
  for x in select unnest(case when p_locs is null or cardinality(p_locs) = 0 then array[null::int] else locs end) loop
    s := public.stock_recon_statement(dd.d1, dd.d2, x, p_item, cat, 5000);
    if (s ->> 'truncated')::boolean then trunc := true; end if;
    n_unb := n_unb + coalesce((s -> 'summary' ->> 'unbalanced')::int, 0); n_var := n_var + coalesce((s -> 'summary' ->> 'with_variance')::int, 0); n_all := n_all + coalesce((s ->> 'row_count')::int, 0);
    rws := rws || coalesce((
      select jsonb_agg(jsonb_build_object('location_id', r -> 'location_id', 'outlet_bn', r ->> 'location_bn', 'outlet_en', r ->> 'location_en', 'item_id', r -> 'item_id', 'item_code', r ->> 'item_code',
               'item_bn', r ->> 'item_bn', 'item_en', r ->> 'item_en', 'unit', r ->> 'unit',
               'opening_qty', (r ->> 'opening_qty')::numeric,
               'in_qty', round(coalesce((r ->> 'production_qty')::numeric, 0) + coalesce((r ->> 'purchases_qty')::numeric, 0) + coalesce((r ->> 'transfer_in_qty')::numeric, 0) + coalesce((r ->> 'give_back_qty')::numeric, 0), 4),
               'out_qty', round(coalesce((r ->> 'used_qty')::numeric, 0) + coalesce((r ->> 'sales_qty')::numeric, 0) + coalesce((r ->> 'wastage_qty')::numeric, 0) + coalesce((r ->> 'transit_loss_qty')::numeric, 0) + coalesce((r ->> 'transfer_out_qty')::numeric, 0), 4),
               'adjust_qty', (r ->> 'adjustments_qty')::numeric, 'closing_qty', (r ->> 'closing_qty')::numeric,
               'check_qty', round(coalesce((r ->> 'opening_qty')::numeric, 0) + coalesce((r ->> 'production_qty')::numeric, 0) + coalesce((r ->> 'purchases_qty')::numeric, 0) + coalesce((r ->> 'transfer_in_qty')::numeric, 0)
                     + coalesce((r ->> 'give_back_qty')::numeric, 0) - coalesce((r ->> 'used_qty')::numeric, 0) - coalesce((r ->> 'sales_qty')::numeric, 0) - coalesce((r ->> 'wastage_qty')::numeric, 0)
                     - coalesce((r ->> 'transit_loss_qty')::numeric, 0) - coalesce((r ->> 'transfer_out_qty')::numeric, 0) + coalesce((r ->> 'adjustments_qty')::numeric, 0) - coalesce((r ->> 'closing_qty')::numeric, 0), 4),
               'balance_qty', (r ->> 'balance_qty')::numeric, 'variance_qty', (r ->> 'variance_qty')::numeric, 'flags', r -> 'flags',
               'status', case when r -> 'flags' @> '"unbalanced"' then 'unbalanced' when r -> 'flags' @> '"variance"' then 'variance' when r -> 'flags' @> '"negative"' then 'negative' else 'ok' end,
               'closing_value', r -> 'closing_value'))
        from jsonb_array_elements(s -> 'rows') r
       where not p_issues_only or r -> 'flags' @> '"unbalanced"' or r -> 'flags' @> '"variance"' or r -> 'flags' @> '"negative"'), '[]'::jsonb);
  end loop;
  if trunc then notes := notes || public._rpt131_note('truncated', 'More than 5000 rows for one place: narrow the filters (category / item).', '৫০০০-এর বেশি সারি: ফিল্টার ছোট করুন।'); end if;
  if not public.biz_cost_ok() then notes := notes || public._rpt131_note('cost_hidden', 'Stock value is hidden for your role.', 'স্টকের দাম আপনার ভূমিকার জন্য লুকানো।'); end if;
  cols := '[{"k":"item","bn":"আইটেম","en":"Item","t":"text"},{"k":"outlet","bn":"আউটলেট","en":"Outlet","t":"text"},{"k":"opening_qty","bn":"শুরু","en":"Opening","t":"qty"},{"k":"in_qty","bn":"আসা","en":"In","t":"qty"},
            {"k":"out_qty","bn":"যাওয়া","en":"Out","t":"qty"},{"k":"adjust_qty","bn":"সমন্বয়","en":"Adjust","t":"qty"},{"k":"closing_qty","bn":"শেষ","en":"Closing","t":"qty"},
            {"k":"check_qty","bn":"চেক","en":"Check","t":"qty"},{"k":"variance_qty","bn":"ভেরিয়েন্স","en":"Variance","t":"qty"},{"k":"closing_value","bn":"শেষ দাম","en":"Closing value","t":"money","sum":true,"cost":true},
            {"k":"status","bn":"স্ট্যাটাস","en":"Status","t":"status"}]'::jsonb;
  fin := public._rpt131_finish(rws, array['closing_value'], p_search, p_sort, p_page, p_size, 'item_code:asc');
  return public._rpt131_env('rpt131_stock_recon', jsonb_build_object('from', dd.d1, 'to', dd.d2, 'locs', p_locs, 'category', cat, 'item', p_item, 'issues_only', p_issues_only, 'search', p_search), cols, fin, notes,
           jsonb_build_object('summary', jsonb_build_object('lines', n_all, 'unbalanced', n_unb, 'with_variance', n_var), 'truncated', trunc));
end $fn$;

-- ---------- 5. wastage by reason / item / outlet / day / status / document ----------
create or replace function public.rpt131_wastage(p_from date default null, p_to date default null, p_locs int[] default null, p_group text default 'reason', p_status text default 'all',
                                                p_category text default null, p_item uuid default null, p_search text default null, p_sort text default null,
                                                p_page int default 1, p_size int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as
$fn$
declare dd record; locs int[]; g text := lower(btrim(coalesce(p_group, 'reason'))); st text := lower(btrim(coalesce(p_status, 'all'))); notes jsonb := '[]'::jsonb; rws jsonb; fin jsonb; cols jsonb;
        cost_ok boolean; cat text := nullif(btrim(coalesce(p_category, '')), ''); dimx text; lb text; le text; a_w bigint; books_w numeric; reg_w numeric; defsort text;
begin
  if not public._rpt131_gate('stock') then return public._rpt131_off('rpt131_wastage'); end if;
  if g not in ('reason', 'item', 'outlet', 'day', 'status', 'doc') then raise exception 'bad_group'; end if;
  if st not in ('all', 'posted', 'pending', 'rejected', 'cancelled', 'reversed') then raise exception 'bad_status'; end if;
  select * into dd from public._rpt131_dates(p_from, p_to);
  locs := public._rpt131_locs(p_locs);
  cost_ok := public.rpt_cost_ok();
  if dd.defaulted then notes := notes || public._rpt131_note('default_period', 'No period given: this month to date.', 'সময় দেওয়া হয়নি: এই মাসের আজ পর্যন্ত।'); end if;
  if cardinality(locs) = 0 then
    notes := notes || public._rpt131_note('no_location', 'No place is open to you.', 'কোনো লোকেশন আপনার জন্য খোলা নেই।');
    return public._rpt131_env('rpt131_wastage', jsonb_build_object('from', dd.d1, 'to', dd.d2, 'group', g), '[]'::jsonb, public._rpt131_finish('[]'::jsonb, '{}'::text[], null, null, 1, 50, 'entries:desc'), notes);
  end if;
  notes := notes || public._rpt131_note('basis', 'Posted = already taken out of stock. Pending / rejected / cancelled requests did not change stock and carry no value. Value = quantity x the cost in the stock ledger at the time; a posted entry whose cost is not known is counted as "cost unknown", never as 0.', 'Posted = স্টক থেকে কাটা। Pending/rejected/cancelled স্টক বদলায়নি, দাম নেই। দাম = পরিমাণ x লেজারের খরচ; খরচ অজানা হলে "cost unknown"।');
  if g in ('reason', 'outlet', 'day', 'status') then notes := notes || public._rpt131_note('no_qty_total', 'Quantities are shown per item only; they are not added across different units.', 'পরিমাণ শুধু আইটেম ধরে; ভিন্ন একক যোগ করা হয় না।'); end if;
  if not cost_ok then notes := notes || public._rpt131_note('cost_hidden', 'Value columns are hidden for your role.', 'দামের কলাম আপনার ভূমিকার জন্য লুকানো।'); end if;
  dimx := case g when 'reason' then 'w.rc' when 'item' then 'w.item_id::text' when 'outlet' then 'w.loc::text' when 'day' then 'w.d::text' when 'status' then 'w.fstatus' else 'w.doc_id' end;
  lb := case g when 'reason' then 'coalesce(max(o.label_bn), w.rc)' when 'item' then 'max(i.name_bn)' when 'outlet' then 'max(lo.name_bn)' when 'doc' then $$max(i.name_bn)$$ else dimx end;
  le := case g when 'reason' then 'coalesce(max(o.label_en), w.rc)' when 'item' then 'coalesce(max(i.name_en), max(i.name_bn))' when 'outlet' then 'coalesce(max(lo.name_en), max(lo.name_bn))' when 'doc' then $$coalesce(max(i.name_en), max(i.name_bn))$$ else dimx end;
  defsort := case g when 'day' then 'dim:asc' when 'doc' then 'at:desc' else 'entries:desc' end;
  execute format($q$
    with w0 as (
      select 'posted'::text st, x.id::text doc_id, x.item_id, x.location_id loc, x.qty, x.reason_code rc, x.made_at at_, coalesce(nullif(btrim(x.created_staff), ''), '-') staff, x.note, l.unit_cost uc,
             exists (select 1 from public.stock_ledger rv where rv.reverses_id = x.ledger_id) rev
        from public.stock_wastage x left join public.stock_ledger l on l.id = x.ledger_id
       where (x.made_at at time zone 'Asia/Dhaka')::date between $1 and $2 and x.location_id = any ($3)
      union all
      select r.status, r.id::text, r.item_id, r.location_id, r.qty, r.reason_code, r.requested_at, coalesce(nullif(btrim(r.requested_staff), ''), '-'), r.note, null::numeric, false
        from public.wastage_requests r
       where r.status in ('pending', 'rejected', 'cancelled') and (r.requested_at at time zone 'Asia/Dhaka')::date between $1 and $2 and r.location_id = any ($3)),
    w as (
      select w0.*, (w0.at_ at time zone 'Asia/Dhaka')::date d, case when w0.rev then 'reversed' else w0.st end fstatus from w0
        join public.items i on i.id = w0.item_id where ($4::uuid is null or w0.item_id = $4) and ($5::text is null or i.category = $5)),
    a as (
      select %s as dim, %s lbn, %s len, count(*) entries, count(distinct w.item_id) items,
             case when %L = 'item' or %L = 'doc' then sum(w.qty) end qty, max(i.unit) unit,
             sum(w.qty * w.uc) filter (where w.fstatus = 'posted' and coalesce(w.uc, 0) > 0) value, count(*) filter (where w.fstatus = 'posted' and coalesce(w.uc, 0) <= 0) cost_unknown,
             max(w.at_) at_, max(w.fstatus) fstatus, max(w.staff) staff, max(w.note) note, max(w.rc) rc, max(w.loc) loc
        from w join public.items i on i.id = w.item_id left join public.locations lo on lo.id = w.loc
        left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = w.rc
       where %L = 'all' or w.fstatus = %L
       group by %s)
    select coalesce(jsonb_agg(jsonb_build_object('dim', a.dim, 'label_bn', a.lbn, 'label_en', a.len, 'entries', a.entries, 'items', a.items, 'qty', round(a.qty, 4), 'unit', a.unit,
             'value', case when %L then round(a.value, 2) end, 'cost_unknown', case when %L then a.cost_unknown end, 'at', a.at_, 'status', a.fstatus, 'staff', a.staff, 'note', a.note,
             'reason', a.rc, 'loc', a.loc) order by a.dim), '[]'::jsonb) from a$q$,
    dimx, lb, le, g, g, st, st, case g when 'doc' then 'w.doc_id, w.rc' else dimx end, cost_ok, cost_ok) into rws using dd.d1, dd.d2, locs, p_item, cat;
  if cost_ok and public._acct_view() then
    select account_id into a_w from public.acct_mappings where key = 'wastage';
    select round(coalesce(sum(l.debit - l.credit), 0), 2) into books_w from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
     where l.account_id = a_w and e.entry_date between dd.d1 and dd.d2 and l.location_id = any (locs);
    select round(coalesce(sum(x.qty * l.unit_cost) filter (where coalesce(l.unit_cost, 0) > 0 and not exists (select 1 from public.stock_ledger rv where rv.reverses_id = x.ledger_id)), 0), 2) into reg_w
      from public.stock_wastage x left join public.stock_ledger l on l.id = x.ledger_id
     where (x.made_at at time zone 'Asia/Dhaka')::date between dd.d1 and dd.d2 and x.location_id = any (locs);
  end if;
  cols := jsonb_build_array(jsonb_build_object('k', 'label', 'bn', 'ভাগ', 'en', 'Group', 't', 'text'), '{"k":"entries","bn":"এন্ট্রি","en":"Entries","t":"int","sum":true}'::jsonb,
    '{"k":"items","bn":"আইটেম","en":"Items","t":"int"}'::jsonb, '{"k":"qty","bn":"পরিমাণ","en":"Qty","t":"qty"}'::jsonb,
    '{"k":"value","bn":"দাম","en":"Value","t":"money","sum":true,"cost":true}'::jsonb, '{"k":"cost_unknown","bn":"খরচ অজানা","en":"Cost unknown","t":"int","sum":true,"cost":true}'::jsonb,
    '{"k":"status","bn":"স্ট্যাটাস","en":"Status","t":"status"}'::jsonb);
  fin := public._rpt131_finish(rws, array['entries', 'value', 'cost_unknown'], p_search, p_sort, p_page, p_size, defsort);
  return public._rpt131_env('rpt131_wastage', jsonb_build_object('from', dd.d1, 'to', dd.d2, 'locs', p_locs, 'group', g, 'status', st, 'category', cat, 'item', p_item, 'search', p_search), cols, fin, notes,
           jsonb_build_object('tie_out', case when cost_ok and public._acct_view() then jsonb_build_object('posted_value', reg_w, 'books_wastage_loss', books_w, 'gap', round(coalesce(reg_w, 0) - coalesce(books_w, 0), 2)) end));
end $fn$;

-- ---------- 6. cash book and day close ----------
create or replace function public.rpt131_cash_close(p_from date default null, p_to date default null, p_locs int[] default null, p_search text default null, p_sort text default null,
                                                   p_page int default 1, p_size int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as
$fn$
declare dd record; locs int[]; notes jsonb := '[]'::jsonb; rws jsonb; fin jsonb; cols jsonb; books boolean; a_c bigint; a_sh bigint; open_t numeric; net_t numeric; nsheets int := 0;
begin
  if not public._rpt131_gate('cash') then return public._rpt131_off('rpt131_cash_close'); end if;
  select * into dd from public._rpt131_dates(p_from, p_to);
  locs := public._rpt131_locs(p_locs);
  books := public._acct_view();
  if dd.defaulted then notes := notes || public._rpt131_note('default_period', 'No period given: this month to date.', 'সময় দেওয়া হয়নি: এই মাসের আজ পর্যন্ত।'); end if;
  if cardinality(locs) = 0 then
    notes := notes || public._rpt131_note('no_location', 'No place is open to you.', 'কোনো লোকেশন আপনার জন্য খোলা নেই।');
    return public._rpt131_env('rpt131_cash_close', jsonb_build_object('from', dd.d1, 'to', dd.d2), '[]'::jsonb, public._rpt131_finish('[]'::jsonb, '{}'::text[], null, null, 1, 50, 'd:desc'), notes);
  end if;
  select account_id into a_c from public.acct_mappings where key = 'pay_cash';
  select account_id into a_sh from public.acct_mappings where key = 'cash_short';
  if not books then notes := notes || public._rpt131_note('books_hidden', 'You may not view the accounts: the cash book columns (opening, in, out, closing, books cash) are not shown.', 'আপনি হিসাব দেখতে পারেন না: ক্যাশ বইয়ের কলাম দেখানো হয়নি।'); end if;
  notes := notes || public._rpt131_note('basis', 'Register cash = cash taken with bills + cash dues collected - cash refunds, from the sales records. Books cash = what the journal holds on the cash account for sales, collections and returns. The gap is cash not yet posted. Counted cash comes from the daily showroom sheet (14-1); a day with no sheet shows "no sheet", not 0. A sale voided after it was posted is reversed on the void date, so its gap shows on both days and nets to 0.', 'রেজিস্টার ক্যাশ = বিলের ক্যাশ + আদায় - ক্যাশ ফেরত। খাতা ক্যাশ = জার্নালে। পার্থক্য = এখনো পোস্ট হয়নি। গোনা ক্যাশ দৈনিক শিট (১৪-১) থেকে; শিট না থাকলে "no sheet"।');
  with sc as (
      select s.location_id loc, s.sale_date d, sum(p.amount) v from public.sale_payments p join public.sales s on s.id = p.sale_id
       where p.kind = 'sale' and not p.voided and s.status = 'done' and p.mode = 'cash' and s.sale_date between dd.d1 and dd.d2 and s.location_id = any (locs) group by 1, 2),
    cc as (
      select p.location_id loc, (p.paid_at at time zone 'Asia/Dhaka')::date d, sum(p.amount) v from public.sale_payments p
       where p.kind = 'collection' and not p.voided and p.mode = 'cash' and (p.paid_at at time zone 'Asia/Dhaka')::date between dd.d1 and dd.d2 and p.location_id = any (locs) group by 1, 2),
    cr as (
      select r.location_id loc, (r.created_at at time zone 'Asia/Dhaka')::date d, sum(r.refund_amount) v from public.sale_returns r
       where r.status = 'done' and r.refund_mode = 'cash' and (r.created_at at time zone 'Asia/Dhaka')::date between dd.d1 and dd.d2 and r.location_id = any (locs) group by 1, 2),
    nc as (
      select z.loc, z.d, sum(z.v) v from (
        select s.location_id loc, s.sale_date d, p.amount v from public.sale_payments p join public.sales s on s.id = p.sale_id
         where p.kind = 'sale' and not p.voided and s.status = 'done' and p.mode <> 'cash' and s.sale_date between dd.d1 and dd.d2 and s.location_id = any (locs)
        union all select p.location_id, (p.paid_at at time zone 'Asia/Dhaka')::date, p.amount from public.sale_payments p
         where p.kind = 'collection' and not p.voided and p.mode <> 'cash' and (p.paid_at at time zone 'Asia/Dhaka')::date between dd.d1 and dd.d2 and p.location_id = any (locs)
        union all select r.location_id, (r.created_at at time zone 'Asia/Dhaka')::date, -r.refund_amount from public.sale_returns r
         where r.status = 'done' and r.refund_mode <> 'cash' and (r.created_at at time zone 'Asia/Dhaka')::date between dd.d1 and dd.d2 and r.location_id = any (locs)) z group by 1, 2),
    jb as (
      select l.location_id loc, e.entry_date d, sum(l.debit) cin, sum(l.credit) cout,
             sum(l.debit - l.credit) filter (where e.source_type in ('sale', 'collection', 'sale_return')) sales_net
        from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
       where books and l.account_id = a_c and e.entry_date between dd.d1 and dd.d2 and l.location_id = any (locs) group by 1, 2),
    op as (
      select l.location_id loc, sum(l.debit - l.credit) v from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
       where books and l.account_id = a_c and e.entry_date < dd.d1 and l.location_id = any (locs) group by 1),
    sh as (
      select e.location_id loc, e.entry_date d, count(*) sheets,
             sum(coalesce((select sum(public._r2_num(f -> 'amount')) from jsonb_array_elements(case when jsonb_typeof(e.flags) = 'array' then e.flags else '[]'::jsonb end) f where f ->> 'code' = 'cash_short_over'), 0)) so
        from public.entries e where e.form_code = '14-1' and e.status in ('submitted', 'approved') and e.entry_date between dd.d1 and dd.d2 and e.location_id = any (locs) group by 1, 2),
    bs as (
      select l.location_id loc, e.entry_date d, sum(l.debit - l.credit) v from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
       where books and l.account_id = a_sh and e.entry_date between dd.d1 and dd.d2 and l.location_id = any (locs) group by 1, 2),
    keys as (select loc, d from sc union select loc, d from cc union select loc, d from cr union select loc, d from nc union select loc, d from jb union select loc, d from sh union select loc, d from bs),
    r as (
      select k.loc, k.d, coalesce(sc.v, 0) sales_cash, coalesce(cc.v, 0) coll_cash, coalesce(cr.v, 0) ref_cash, coalesce(nc.v, 0) noncash, jb.cin, jb.cout, jb.sales_net, sh.sheets, sh.so, bs.v bshort,
             coalesce(op.v, 0) + coalesce(sum(coalesce(jb.cin, 0) - coalesce(jb.cout, 0)) over (partition by k.loc order by k.d rows between unbounded preceding and 1 preceding), 0) opening
        from keys k left join sc on sc.loc = k.loc and sc.d = k.d left join cc on cc.loc = k.loc and cc.d = k.d left join cr on cr.loc = k.loc and cr.d = k.d left join nc on nc.loc = k.loc and nc.d = k.d
        left join jb on jb.loc = k.loc and jb.d = k.d left join sh on sh.loc = k.loc and sh.d = k.d left join bs on bs.loc = k.loc and bs.d = k.d left join op on op.loc = k.loc)
  select coalesce(jsonb_agg(jsonb_build_object('d', r.d, 'loc', r.loc, 'outlet_bn', lo.name_bn, 'outlet_en', coalesce(lo.name_en, lo.name_bn),
           'sales_cash', round(r.sales_cash, 2), 'collections_cash', round(r.coll_cash, 2), 'refunds_cash', round(r.ref_cash, 2),
           'expected_cash', round(r.sales_cash + r.coll_cash - r.ref_cash, 2), 'noncash_net', round(r.noncash, 2),
           'opening', case when books then round(r.opening, 2) end, 'cash_in', case when books then round(coalesce(r.cin, 0), 2) end, 'cash_out', case when books then round(coalesce(r.cout, 0), 2) end,
           'closing', case when books then round(r.opening + coalesce(r.cin, 0) - coalesce(r.cout, 0), 2) end,
           'books_sales_cash', case when books then round(coalesce(r.sales_net, 0), 2) end,
           'unposted_gap', case when books then round(r.sales_cash + r.coll_cash - r.ref_cash - coalesce(r.sales_net, 0), 2) end,
           'sheets', coalesce(r.sheets, 0), 'sheet_short_over', case when r.sheets is null then null else round(r.so, 2) end,
           'books_cash_short', case when books then round(coalesce(r.bshort, 0), 2) end,
           'flag', case when books and abs(r.sales_cash + r.coll_cash - r.ref_cash - coalesce(r.sales_net, 0)) > 0.005 then 'books_differ'
                        when r.sheets is null and (r.sales_cash + r.coll_cash) > 0 then 'no_sheet' when r.so < -0.005 then 'short' when r.so > 0.005 then 'over' end)), '[]'::jsonb),
         coalesce(sum(r.sheets), 0)
    into rws, nsheets from r join public.locations lo on lo.id = r.loc;
  if books then
    select coalesce(sum(v), 0) into open_t from (select l.location_id, sum(l.debit - l.credit) v from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
        where l.account_id = a_c and e.entry_date < dd.d1 and l.location_id = any (locs) group by 1) z;
    select coalesce(sum(l.debit - l.credit), 0) into net_t from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
     where l.account_id = a_c and e.entry_date between dd.d1 and dd.d2 and l.location_id = any (locs);
  end if;
  if nsheets = 0 then notes := notes || public._rpt131_note('no_day_close_sheet', 'No daily showroom sheet (14-1) was submitted in this period: counted cash and the short / over figure are data needed.', 'এই সময়ে কোনো দৈনিক শিট (১৪-১) জমা হয়নি: গোনা ক্যাশ ও কম/বেশি = তথ্য দরকার।'); end if;
  cols := '[{"k":"d","bn":"তারিখ","en":"Date","t":"date"},{"k":"outlet","bn":"আউটলেট","en":"Outlet","t":"text"},{"k":"opening","bn":"শুরু (খাতা)","en":"Opening (books)","t":"money"},
            {"k":"expected_cash","bn":"হওয়ার কথা (রেজিস্টার)","en":"Expected (register)","t":"money","sum":true},{"k":"books_sales_cash","bn":"খাতার বিক্রির ক্যাশ","en":"Books sales cash","t":"money","sum":true},
            {"k":"unposted_gap","bn":"পোস্ট হয়নি","en":"Not yet posted","t":"money","sum":true},{"k":"cash_in","bn":"ক্যাশ ঢুকেছে","en":"Cash in","t":"money","sum":true},{"k":"cash_out","bn":"ক্যাশ বেরিয়েছে","en":"Cash out","t":"money","sum":true},
            {"k":"closing","bn":"শেষ (খাতা)","en":"Closing (books)","t":"money"},{"k":"sheet_short_over","bn":"শিটে কম(-)/বেশি(+)","en":"Sheet short(-)/over(+)","t":"money","sum":true},
            {"k":"books_cash_short","bn":"খাতায় কম","en":"Books short","t":"money","sum":true},{"k":"flag","bn":"চিহ্ন","en":"Flag","t":"status"}]'::jsonb;
  fin := public._rpt131_finish(rws, array['sales_cash', 'collections_cash', 'refunds_cash', 'expected_cash', 'noncash_net', 'cash_in', 'cash_out', 'books_sales_cash', 'unposted_gap', 'sheet_short_over', 'books_cash_short'], p_search, p_sort, p_page, p_size, 'd:desc');
  return public._rpt131_env('rpt131_cash_close', jsonb_build_object('from', dd.d1, 'to', dd.d2, 'locs', p_locs, 'search', p_search), cols, fin, notes,
           jsonb_build_object('summary', jsonb_build_object('opening_total', case when books then round(open_t, 2) end, 'net_movement', case when books then round(net_t, 2) end,
                                                          'closing_total', case when books then round(open_t + net_t, 2) end, 'sheets', nsheets), 'books_visible', books));
end $fn$;

-- ---------- 7. receivable / payable ageing with the books tie-out ----------
create or replace function public.rpt131_ageing(p_kind text default 'receivable', p_as_of date default null, p_locs int[] default null, p_search text default null, p_sort text default null,
                                               p_page int default 1, p_size int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as
$fn$
declare kd text := lower(btrim(coalesce(p_kind, 'receivable'))); asof date := coalesce(p_as_of, public._today()); locs int[]; notes jsonb := '[]'::jsonb; rws jsonb; fin jsonb; cols jsonb;
        bk int[]; bt text; i int; lo int; hi int; bsel text := ''; bcols jsonb := '[]'::jsonb; books boolean; a_x bigint; gl numeric; reg numeric := 0; adv numeric := 0; n_unposted int; v_unposted numeric; n_ucol int := 0; v_ucol numeric := 0; v_ucred numeric := 0;
        allp boolean; sql_ text;
begin
  if kd not in ('receivable', 'payable') then raise exception 'bad_kind'; end if;
  if not public._rpt131_gate(case kd when 'receivable' then 'customers' else 'purchase' end) then return public._rpt131_off('rpt131_ageing'); end if;
  if asof > public._today() or asof < date '2000-01-01' then raise exception 'bad_range'; end if;
  locs := public._rpt131_locs(p_locs);
  books := public._acct_view();
  if cardinality(locs) = 0 then
    notes := notes || public._rpt131_note('no_location', 'No place is open to you.', 'কোনো লোকেশন আপনার জন্য খোলা নেই।');
    return public._rpt131_env('rpt131_ageing', jsonb_build_object('kind', kd, 'as_of', asof), '[]'::jsonb, public._rpt131_finish('[]'::jsonb, '{}'::text[], null, null, 1, 50, 'balance:desc'), notes);
  end if;
  -- age buckets come from the rule report_aging_buckets (days, ascending, e.g. 30,60,90): no built-in values
  bt := nullif(btrim(coalesce(public.rule_txt('report_aging_buckets'), '')), '');
  if bt is not null and bt ~ '^[0-9]+(\s*,\s*[0-9]+){0,7}$' then bk := string_to_array(regexp_replace(bt, '\s', '', 'g'), ',')::int[]; end if;
  if bk is not null then
    for i in 2..cardinality(bk) loop if bk[i] <= bk[i - 1] then bk := null; exit; end if; end loop;
  end if;
  if bk is null then notes := notes || public._rpt131_note('data_needed', 'The age buckets are not set (rule report_aging_buckets, e.g. 30,60,90): only the total and the oldest age are shown.', 'বয়সের ভাগ নিয়মে (report_aging_buckets) লেখা নেই: শুধু মোট ও সবচেয়ে পুরনো বয়স।'); end if;
  if bk is not null then
    for i in 1..cardinality(bk) + 1 loop
      lo := case when i = 1 then 0 else bk[i - 1] + 1 end; hi := case when i <= cardinality(bk) then bk[i] end;
      bsel := bsel || format(', round(coalesce(sum(%I) filter (where %s), 0), 2) as b%s', 'portion', case when hi is null then format('age >= %s', lo) else format('age between %s and %s', lo, hi) end, i);
      bcols := bcols || jsonb_build_array(jsonb_build_object('k', 'b' || i, 'bn', case when hi is null then lo || '+ দিন' else lo || '-' || hi || ' দিন' end,
                                                             'en', case when hi is null then lo || '+ days' else lo || '-' || hi || ' days' end, 't', 'money', 'sum', true));
    end loop;
  end if;

  if kd = 'receivable' then
    select account_id into a_x from public.acct_mappings where key = 'receivable';
    notes := notes || public._rpt131_note('basis', 'Open bills are cleared oldest first by the dues collected and by the credit given on returns. Money received in advance or credit beyond the bills is shown as "advances", not subtracted from other people. Customer mobile numbers are not shown.', 'খোলা বিল পুরনো থেকে আদায় ও ফেরতের ক্রেডিট দিয়ে মেটে। অগ্রিম আলাদা "advances"। মোবাইল নম্বর দেখানো হয়নি।');
    execute format($q$
      with s as (
        select s.id, s.customer_id, s.sale_date, s.sold_at, s.total - coalesce(pp.v, 0) rem
          from public.sales s left join (select sale_id, sum(amount) v from public.sale_payments where not voided and kind = 'sale' and sale_id is not null
                                           and (paid_at at time zone 'Asia/Dhaka')::date <= $1 group by 1) pp on pp.sale_id = s.id
         where s.status = 'done' and s.customer_id is not null and s.sale_date <= $1 and s.location_id = any ($2)),
      cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) cr from s where s.rem > 0.004),
      cred as (
        select z.customer_id, sum(z.v) v from (
          select p.customer_id, p.amount v from public.sale_payments p where p.kind = 'collection' and not p.voided and p.customer_id is not null
             and (p.paid_at at time zone 'Asia/Dhaka')::date <= $1 and p.location_id = any ($2)
          union all select r.customer_id, r.credit_amount from public.sale_returns r where r.status = 'done' and r.customer_id is not null and r.credit_amount > 0
             and (r.created_at at time zone 'Asia/Dhaka')::date <= $1 and r.location_id = any ($2)) z group by 1),
      tot as (select customer_id, sum(rem) allrem, count(*) bills from cum group by 1),
      pt as (select k.customer_id, $1 - k.sale_date age, greatest(0, least(k.rem, k.cr - coalesce(c.v, 0))) portion from cum k left join cred c on c.customer_id = k.customer_id),
      pc as (select pt.customer_id, round(sum(pt.portion), 2) balance, max(pt.age) filter (where pt.portion > 0) oldest %s from pt group by 1),
      cust as (select customer_id from tot union select customer_id from cred)
      select coalesce(jsonb_agg(jsonb_build_object('id', cu.id, 'name', cu.name, 'balance', round(pc.balance, 2), 'oldest_days', pc.oldest, 'bills', tot.bills %s) order by pc.balance desc) filter (where pc.balance > 0.004), '[]'::jsonb),
             coalesce(sum(pc.balance) filter (where pc.balance > 0.004), 0),
             coalesce(sum(greatest(0, coalesce(cred.v, 0) - coalesce(tot.allrem, 0))), 0)
        from cust x join public.customers cu on cu.id = x.customer_id left join tot on tot.customer_id = x.customer_id left join cred on cred.customer_id = x.customer_id left join pc on pc.customer_id = x.customer_id$q$,
      bsel, (select string_agg(format(', %L, pc.b%s', 'b' || n, n), '') from generate_series(1, case when bk is null then 0 else cardinality(bk) + 1 end) n))
      into rws, reg, adv using asof, locs;
    if books and a_x is not null then
      select round(coalesce(sum(l.debit - l.credit), 0), 2) into gl from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
       where l.account_id = a_x and e.entry_date <= asof and l.location_id = any (locs);
      select count(*), coalesce(sum(p.amount), 0) into n_ucol, v_ucol from public.sale_payments p
       where p.kind = 'collection' and not p.voided and p.customer_id is not null and (p.paid_at at time zone 'Asia/Dhaka')::date <= asof and p.location_id = any (locs)
         and not exists (select 1 from public.journal_entries e where e.source_type = 'collection' and e.source_id = p.id::text and e.reverses_id is null);
      select coalesce(sum(r.credit_amount), 0) into v_ucred from public.sale_returns r
       where r.status = 'done' and r.customer_id is not null and r.credit_amount > 0 and (r.created_at at time zone 'Asia/Dhaka')::date <= asof and r.location_id = any (locs)
         and not exists (select 1 from public.journal_entries e where e.source_type = 'sale_return' and e.source_id = r.id::text and e.reverses_id is null);
      select count(*), coalesce(sum(s.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided), 0)), 0) into n_unposted, v_unposted
        from public.sales s where s.status = 'done' and s.customer_id is not null and s.sale_date <= asof and s.location_id = any (locs) and s.total > coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided), 0)
         and not exists (select 1 from public.journal_entries e where e.source_type = 'sale' and e.source_id = s.id::text and e.reverses_id is null);
    end if;
    cols := '[{"k":"name","bn":"গ্রাহক","en":"Customer","t":"text"},{"k":"balance","bn":"মোট বাকি","en":"Total due","t":"money","sum":true},{"k":"oldest_days","bn":"সবচেয়ে পুরনো (দিন)","en":"Oldest (days)","t":"int"},{"k":"bills","bn":"বিল","en":"Bills","t":"int"}]'::jsonb || bcols;
    fin := public._rpt131_finish(rws, array['balance'] || coalesce((select array_agg('b' || n) from generate_series(1, case when bk is null then 0 else cardinality(bk) + 1 end) n), '{}'::text[]), p_search, p_sort, p_page, p_size, 'balance:desc');
    return public._rpt131_env('rpt131_ageing', jsonb_build_object('kind', kd, 'as_of', asof, 'locs', p_locs, 'search', p_search), cols, fin, notes,
      jsonb_build_object('tie_out', case when books and a_x is not null then jsonb_build_object('register_dues', round(reg, 2), 'advances', round(adv, 2), 'register_net', round(reg - adv, 2), 'books_receivable', gl,
                                                 'gap', round(reg - adv - gl, 2), 'unposted_bills', n_unposted, 'unposted_value', round(v_unposted, 2),
                                                 'unposted_collections', n_ucol, 'unposted_collections_value', round(v_ucol, 2), 'unposted_return_credit', round(v_ucred, 2),
                                                 'explained', round(v_unposted - v_ucol - v_ucred, 2), 'unexplained', round(reg - adv - gl - (v_unposted - v_ucol - v_ucred), 2)) end, 'books_visible', books and a_x is not null));
  end if;

  -- payable: the supplier open items are as of NOW (the payment allocation is not kept per date)
  if p_as_of is not null and p_as_of <> public._today() then notes := notes || public._rpt131_note('as_of_today', 'Payables are always as of today: the date you gave was ignored.', 'পাওনা সবসময় আজকের হিসাবে: দেওয়া তারিখ ধরা হয়নি।'); end if;
  asof := public._today();
  allp := public._acct_all();
  if not allp then notes := notes || public._rpt131_note('opening_hidden', 'Supplier opening balances have no place and are shown to the owner only.', 'সরবরাহকারীর শুরুর ব্যালেন্সের লোকেশন নেই, শুধু মালিক দেখেন।'); end if;
  select account_id into a_x from public.acct_mappings where key = 'payable';
  notes := notes || public._rpt131_note('basis', 'Open supplier bills after payments, returns and refunds. Age = days since the bill date. Overdue uses the supplier credit days when set.', 'পেমেন্ট, রিটার্ন, রিফান্ড বাদে খোলা বিল। বয়স = বিলের তারিখ থেকে দিন। মেয়াদ = সরবরাহকারীর ক্রেডিট দিন।');
  execute format($q$
    with o as (
      select o.supplier_id, o.bill_date, o.open_amt, s.name, s.credit_days, case when o.bill_date is null then null else $1 - o.bill_date end age
        from public._sup_open(null) o join public.suppliers s on s.id = o.supplier_id
       where o.open_amt > 0.004 and (o.location_id = any ($2) or (o.location_id is null and $3))),
    pt as (select o.*, o.open_amt portion from o),
    pc as (select pt.supplier_id, max(pt.name) name, round(sum(pt.portion), 2) balance, max(pt.age) oldest, count(*) bills,
                  round(coalesce(sum(pt.portion) filter (where pt.credit_days is not null and pt.bill_date is not null and pt.bill_date + pt.credit_days < $1), 0), 2) overdue,
                  round(coalesce(sum(pt.portion) filter (where pt.age is null), 0), 2) undated %s
             from pt group by pt.supplier_id)
    select coalesce(jsonb_agg(jsonb_build_object('id', pc.supplier_id, 'name', pc.name, 'balance', pc.balance, 'oldest_days', pc.oldest, 'bills', pc.bills, 'overdue', pc.overdue, 'undated', pc.undated %s) order by pc.balance desc), '[]'::jsonb),
           coalesce(sum(pc.balance), 0)
      from pc$q$,
    case when bk is null then '' else replace(bsel, 'portion', 'portion') end,
    (select string_agg(format(', %L, pc.b%s', 'b' || n, n), '') from generate_series(1, case when bk is null then 0 else cardinality(bk) + 1 end) n))
    into rws, reg using asof, locs, allp;
  if books and a_x is not null then
    select round(coalesce(sum(l.credit - l.debit), 0), 2) into gl from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
     where l.account_id = a_x and e.entry_date <= asof and (l.location_id = any (locs) or (l.location_id is null and allp));
  end if;
  cols := '[{"k":"name","bn":"সরবরাহকারী","en":"Supplier","t":"text"},{"k":"balance","bn":"মোট পাওনা","en":"Total owed","t":"money","sum":true},{"k":"overdue","bn":"মেয়াদ পার","en":"Overdue","t":"money","sum":true},
            {"k":"oldest_days","bn":"সবচেয়ে পুরনো (দিন)","en":"Oldest (days)","t":"int"},{"k":"bills","bn":"বিল","en":"Bills","t":"int"},{"k":"undated","bn":"তারিখহীন (শুরুর)","en":"Undated (opening)","t":"money","sum":true}]'::jsonb || bcols;
  fin := public._rpt131_finish(rws, array['balance', 'overdue', 'undated'] || coalesce((select array_agg('b' || n) from generate_series(1, case when bk is null then 0 else cardinality(bk) + 1 end) n), '{}'::text[]), p_search, p_sort, p_page, p_size, 'balance:desc');
  return public._rpt131_env('rpt131_ageing', jsonb_build_object('kind', kd, 'as_of', asof, 'locs', p_locs, 'search', p_search), cols, fin, notes,
    jsonb_build_object('tie_out', case when books and a_x is not null then jsonb_build_object('register_open', round(reg, 2), 'books_payable', gl, 'gap', round(reg - gl, 2)) end, 'books_visible', books and a_x is not null));
end $fn$;

-- ---------- 8. export log (CSV / print), same right as the other report exports ----------
create or replace function public.rpt131_log_export(p_key text, p_kind text, p_filters jsonb, p_rows integer) returns void
language plpgsql security definer set search_path = public as
$fn$
declare sid text; f jsonb := coalesce(p_filters, '{}'::jsonb);
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_grant('export_data')) then raise exception 'not allowed'; end if;
  if p_key is null or p_key not in ('rpt131_sales', 'rpt131_sales_recon', 'rpt131_item_profit', 'rpt131_stock_recon', 'rpt131_wastage', 'rpt131_cash_close', 'rpt131_ageing') then raise exception 'unknown_report'; end if;
  if p_kind is null or lower(p_kind) !~ '^[a-z0-9_]{1,20}$' then raise exception 'bad_kind'; end if;
  if length(f::text) > 4000 then f := jsonb_build_object('truncated', true); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'export', 'report', p_key, jsonb_build_object('kind', lower(p_kind), 'rows', least(greatest(coalesce(p_rows, 0), 0), 100000000), 'filters', f));
end $fn$;

-- ---------- grants ----------
revoke all on function public._rpt131_note(text, text, text, text), public._rpt131_gate(text), public._rpt131_off(text), public._rpt131_locs(int[]), public._rpt131_dates(date, date),
  public._rpt131_finish(jsonb, text[], text, text, int, int, text), public._rpt131_env(text, jsonb, jsonb, jsonb, jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.rpt131_catalog(), public.rpt131_sales(date, date, int[], text, text, text, int, int), public.rpt131_sales_recon(date, date, int[], text, text, text, int, int),
  public.rpt131_item_profit(date, date, int[], text, text, uuid, text, text, int, int), public.rpt131_stock_recon(date, date, int[], text, uuid, boolean, text, text, int, int),
  public.rpt131_wastage(date, date, int[], text, text, text, uuid, text, text, int, int), public.rpt131_cash_close(date, date, int[], text, text, int, int),
  public.rpt131_ageing(text, date, int[], text, text, int, int), public.rpt131_log_export(text, text, jsonb, integer) from public, anon;
grant execute on function public.rpt131_catalog(), public.rpt131_sales(date, date, int[], text, text, text, int, int), public.rpt131_sales_recon(date, date, int[], text, text, text, int, int),
  public.rpt131_item_profit(date, date, int[], text, text, uuid, text, text, int, int), public.rpt131_stock_recon(date, date, int[], text, uuid, boolean, text, text, int, int),
  public.rpt131_wastage(date, date, int[], text, text, text, uuid, text, text, int, int), public.rpt131_cash_close(date, date, int[], text, text, int, int),
  public.rpt131_ageing(text, date, int[], text, text, int, int), public.rpt131_log_export(text, text, jsonb, integer) to authenticated;

commit;

-- ============================================================================
-- End of FRESH part 11 of 21.
