-- ============================================================================
-- FRESH part 3 of 21. Paste the WHOLE of this file into the Supabase SQL editor, press Run, wait for "Success", then paste the next part.
-- Phases in this part, in this order: phase21 phase22 phase23 phase24 phase25 phase26 phase27 phase28 phase40 phase41
-- Never paste: any *_test.sql, the phase84 / 84b / 84c TEST-PROJECT files, ALL_NEW2..ALL_NEW11*. Commit: see docs/PASTE_ORDER.md.
-- ============================================================================

-- ---------------------------------------------------------------- phase21.sql
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

-- ---------------------------------------------------------------- phase22.sql
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

-- ---------------------------------------------------------------- phase23.sql
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

-- ---------------------------------------------------------------- phase24.sql
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

-- ---------------------------------------------------------------- phase25.sql
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

-- ---------------------------------------------------------------- phase26.sql
-- ============================================================
-- PHASE 26 (report engine 3, batch R3-26): 13 reports on the engine of phase24
--   P2 p2_rate_trend      purchase-rate trend per item / supplier        (cost)
--   P4 p4_supplier_score  supplier scorecard                              (cost)
--   P5 p5_po_match        PO - GRN - bill 3-way match and open POs        (cost)
--   P6 p6_purchase_budget purchase spent vs the 10-4 budget and outlook   (cost)
--   K2 k2_count_variance  stock-count variance, repeat offenders          (quantities only)
--   F1 f1_production      production runs, sheet output, dispatch         (void runs shown as a status)
--   F2 f2_yield           yield vs the approved 05-4 standard
--   F3 f3_raw_vs_recipe   raw material really issued vs the recipe
--   F4 f4_breakdowns      machine breakdowns and maintenance requests
--   M2 m2_marketing_vs_sales  marketing spend and sales side by side per day
--   Q1 q1_fridge_temp     fridge temperature log, out-of-range readings
--   Q2 q2_hygiene         hygiene / expiry / checklist compliance
--   Q3 q3_complaints      complaints and sale-return root causes
-- Needs phase24 (and phase17 paper_serial, phase19 production_runs, phase23 production_runs.status). Additive and idempotent: paste twice is safe.
-- Form field ids were checked in web/forms.js, forms_stock.js, forms_factory.js, forms_cash.js, forms_sales.js.
-- ============================================================

-- ---------- private helpers (called only from the report functions below) ----------
create or replace function public._p26_d(t text) returns date
language plpgsql immutable set search_path = public as $$
begin
  if t is null or t !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
  return t::date;
exception when others then return null;
end $$;

create or replace function public._p26_b(j jsonb) returns boolean
language sql immutable set search_path = public as $$
  select coalesce(j in ('true'::jsonb, '"true"'::jsonb, '"yes"'::jsonb, '1'::jsonb, '"1"'::jsonb), false);
$$;

create or replace function public._p26_arr(j jsonb) returns jsonb
language sql immutable set search_path = public as $$
  select case when jsonb_typeof(j) = 'array' then j else '[]'::jsonb end;
$$;

-- rate observations: posted purchase bills (lines) and submitted/approved 04-1 GRN lines. Cost data: only called from cost reports.
create or replace function public._p26_rates(d1 date, d2 date, locs int[]) returns table (item_id uuid, sk text, sname text, dt date, qty numeric, rate numeric, ord text)
language sql stable security definer set search_path = public as $$
  select pl.item_id, lower(btrim(s.name)), btrim(s.name), b.bill_date, coalesce(pl.base_qty, pl.qty), coalesce(pl.unit_cost_base, pl.unit_cost), b.id::text || ':' || pl.line_no::text
    from public.purchase_bills b join public.purchase_lines pl on pl.bill_id = b.id join public.suppliers s on s.id = b.supplier_id
   where b.status = 'posted' and b.kind = 'bill' and pl.item_id is not null and b.bill_date between d1 and d2 and b.location_id = any (locs)
     and coalesce(pl.unit_cost_base, pl.unit_cost) > 0 and coalesce(pl.base_qty, pl.qty) > 0
  union all
  select i.id, lower(btrim(coalesce(s.name, e.data ->> 'supplier'))), btrim(coalesce(s.name, e.data ->> 'supplier')), e.entry_date, public._r2_num(r -> 'counted'), public._r2_num(r -> 'rate'), e.id::text || ':' || n.ord::text
    from public.entries e
    cross join lateral jsonb_array_elements(public._p26_arr(e.data -> 'lines')) with ordinality n(r, ord)
    join public.items i on i.code = n.r ->> 'item'
    left join public.suppliers s on s.id::text = e.data ->> 'supplier_id'
   where e.form_code = '04-1' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)
     and nullif(btrim(coalesce(s.name, e.data ->> 'supplier')), '') is not null
     and public._r2_num(n.r -> 'rate') > 0 and public._r2_num(n.r -> 'counted') > 0
     -- a delivery entered as a purchase bill AND a GRN is counted once (the bill wins): no posted bill line for the same item and place within 3 days
     and not exists (select 1 from public.purchase_bills b2 join public.purchase_lines pl2 on pl2.bill_id = b2.id join public.suppliers s2 on s2.id = b2.supplier_id
                      where b2.status = 'posted' and b2.kind = 'bill' and pl2.item_id = i.id and b2.location_id = e.location_id and abs(b2.bill_date - e.entry_date) <= 3
                        and lower(btrim(s2.name)) = lower(btrim(coalesce(s.name, e.data ->> 'supplier'))));
$$;

-- one row per purchase order (06-3, not cancelled) with what was received (04-1 on that PO number) and what was billed (06-4)
create or replace function public._p26_po(d1 date, d2 date, locs int[])
returns table (entry_id uuid, location_id int, entry_date date, po_no text, sk text, supplier text, delivery_date date, po_lines int, po_total numeric, lines_open int,
               grn_n int, first_grn date, last_grn date, grn_value numeric, bill_n int, bill_amount numeric)
language sql stable security definer set search_path = public as $$
  with po as (
    select e.id, e.location_id, e.entry_date, e.data,
           coalesce(nullif(btrim(e.paper_serial), ''), nullif(btrim(e.data ->> 'paper_no'), ''), e.serial::text) as po_no,
           array_remove(array[public.norm_paper_serial(e.paper_serial), public.norm_paper_serial(e.data ->> 'paper_no'), e.serial::text], null) as keys,
           btrim(coalesce(s.name, e.data ->> 'supplier')) as sname
      from public.entries e left join public.suppliers s on s.id::text = e.data ->> 'supplier_id'
     where e.form_code = '06-3' and e.status in ('submitted', 'approved') and not public._p26_b(e.data -> 'cancel')
       and e.entry_date between d1 and d2 and e.location_id = any (locs)),
  grn as (
    select g.id, g.entry_date, g.data, public.norm_paper_serial(g.data ->> 'po_no') as pk
      from public.entries g
     where g.form_code = '04-1' and g.status in ('submitted', 'approved') and g.data ->> 'paper' = 'po' and g.location_id = any (locs)
       and public.norm_paper_serial(g.data ->> 'po_no') is not null),
  bil as (
    select b.id, public.norm_paper_serial(b.data -> 'tri' -> 0 ->> 'po') as pk, public._r2_num(b.data -> 'bill_amount') as amt
      from public.entries b
     where b.form_code = '06-4' and b.status in ('submitted', 'approved') and b.location_id = any (locs)
       and public.norm_paper_serial(b.data -> 'tri' -> 0 ->> 'po') is not null)
  select po.id, po.location_id, po.entry_date, po.po_no, lower(po.sname), po.sname, public._p26_d(po.data ->> 'delivery_date'),
    (select count(*)::int from jsonb_array_elements(public._p26_arr(po.data -> 'lines')) r where public._r2_num(r -> 'qty') > 0),
    (select sum(public._r2_num(r -> 'qty') * public._r2_num(r -> 'rate')) from jsonb_array_elements(public._p26_arr(po.data -> 'lines')) r where public._r2_num(r -> 'qty') > 0),
    (select count(*)::int from (select r ->> 'item' as it, sum(public._r2_num(r -> 'qty')) as oq from jsonb_array_elements(public._p26_arr(po.data -> 'lines')) r where public._r2_num(r -> 'qty') > 0 group by 1) o
      where o.oq > coalesce((select sum(public._r2_num(gl -> 'counted')) from grn g, jsonb_array_elements(public._p26_arr(g.data -> 'lines')) gl where g.pk = any (po.keys) and gl ->> 'item' = o.it), 0)),
    (select count(*)::int from grn g where g.pk = any (po.keys)),
    (select min(g.entry_date) from grn g where g.pk = any (po.keys)),
    (select max(g.entry_date) from grn g where g.pk = any (po.keys)),
    (select sum(public._r2_num(gl -> 'counted') * public._r2_num(gl -> 'rate')) from grn g, jsonb_array_elements(public._p26_arr(g.data -> 'lines')) gl where g.pk = any (po.keys)),
    (select count(*)::int from bil b where b.pk = any (po.keys)),
    (select sum(b.amt) from bil b where b.pk = any (po.keys))
  from po;
$$;

-- the purchase outlook of phase4 needs the caller's business-view right: where it is missing the figure is simply null
create or replace function public._p26_outlook(p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  return public.biz_outlook(p_loc, 7, 28);
exception when others then
  return null;
end $$;

-- ============================================================
-- P2 purchase-rate trend per item and supplier
-- ============================================================
create or replace function public._r3q_p2_rate_trend(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with cat as (select public.rpt_arr_text(flt -> 'categories') as c),
  x as (
    select r.item_id, r.sk, min(r.sname) as sname, count(*) as n, sum(r.qty) as qty,
           (array_agg(r.rate order by r.dt, r.ord))[1] as first_rate, (array_agg(r.rate order by r.dt desc, r.ord desc))[1] as last_rate,
           min(r.rate) as min_rate, max(r.rate) as max_rate, sum(r.qty * r.rate) / nullif(sum(r.qty), 0) as avg_rate, max(r.dt) as last_date
      from public._p26_rates(d1, d2, locs) r group by r.item_id, r.sk)
  select jsonb_build_object('item_code', i.code, 'item_bn', i.name_bn, 'supplier', x.sname, 'n', x.n, 'qty', round(x.qty, 3),
    'first_rate', round(x.first_rate, 4), 'last_rate', round(x.last_rate, 4), 'min_rate', round(x.min_rate, 4), 'max_rate', round(x.max_rate, 4), 'avg_rate', round(x.avg_rate, 4),
    'change_pct', case when x.n > 1 and x.first_rate > 0 then round((x.last_rate - x.first_rate) / x.first_rate * 100, 2) end, 'last_date', x.last_date)
    from x join public.items i on i.id = x.item_id cross join cat
   where cat.c is null or i.category = any (cat.c);
$$;

-- ============================================================
-- P4 supplier scorecard
-- ============================================================
create or replace function public._r3q_p4_supplier_score(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with sup as (
    select e.id, e.form_code, e.data, lower(btrim(coalesce(s.name, e.data ->> 'supplier'))) as sk, btrim(coalesce(s.name, e.data ->> 'supplier')) as sname
      from public.entries e left join public.suppliers s on s.id::text = e.data ->> 'supplier_id'
     where e.form_code in ('04-1', '06-4') and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)
       and nullif(btrim(coalesce(s.name, e.data ->> 'supplier')), '') is not null),
  gl as (
    select s.sk, s.sname, s.id, r ->> 'quality' as q, public._r2_num(r -> 'counted') as cnt, public._r2_num(r -> 'memo') as memo
      from sup s cross join lateral jsonb_array_elements(public._p26_arr(s.data -> 'lines')) r where s.form_code = '04-1'),
  grn as (
    select sk, min(sname) as sname, count(distinct id) as grns, count(*) as lines, count(*) filter (where memo is not null and cnt is not null and cnt < memo) as short_lines,
           count(*) filter (where q = 'return') as rejected, count(*) filter (where q = 'hold') as held, count(*) filter (where q = 'reduced') as reduced
      from gl group by sk),
  bil as (
    select sk, min(sname) as sname, count(*) as bills, count(*) filter (where data ->> 'short' = 'yes') as short_claims, count(*) filter (where data ->> 'returned' = 'yes') as return_claims
      from sup where form_code = '06-4' group by sk),
  po as (
    select p.sk, min(p.supplier) as sname, count(*) as pos, count(*) filter (where p.grn_n > 0 and p.delivery_date is not null) as pos_matched,
           count(*) filter (where p.grn_n > 0 and p.delivery_date is not null and p.first_grn > p.delivery_date) as late_pos,
           count(*) filter (where p.grn_n = 0 and p.delivery_date is not null and p.delivery_date < (now() at time zone 'Asia/Dhaka')::date) as overdue_open
      from public._p26_po(d1, d2, locs) p where p.sk is not null and p.sk <> '' group by p.sk),
  rr as (select * from public._p26_rates(d1, d2, locs)),
  rc as (
    select sk, avg(chg) as chg, count(*) as items
      from (select sk, item_id, (l - f) / f * 100 as chg
              from (select sk, item_id, (array_agg(rate order by dt, ord))[1] as f, (array_agg(rate order by dt desc, ord desc))[1] as l, count(*) as n from rr group by sk, item_id) a
             where n > 1 and f > 0) b group by sk),
  keys as (select sk, sname from grn union select sk, sname from bil union select sk, sname from po union select sk, min(sname) from rr group by sk)
  select jsonb_build_object('supplier', k.sname, 'grns', coalesce(g.grns, 0), 'lines', coalesce(g.lines, 0), 'short_lines', coalesce(g.short_lines, 0), 'rejected', coalesce(g.rejected, 0),
    'held', coalesce(g.held, 0), 'reduced', coalesce(g.reduced, 0), 'bills_checked', coalesce(b.bills, 0), 'short_claims', coalesce(b.short_claims, 0), 'return_claims', coalesce(b.return_claims, 0),
    'pos', coalesce(p.pos, 0), 'late_pos', case when coalesce(p.pos_matched, 0) > 0 then p.late_pos end, 'overdue_open', coalesce(p.overdue_open, 0),
    'rate_change_pct', case when c.chg is not null then round(c.chg, 2) end, 'rate_items', coalesce(c.items, 0))
    from (select sk, min(sname) as sname from keys where sk is not null and sk <> '' group by sk) k
    left join grn g on g.sk = k.sk left join bil b on b.sk = k.sk left join po p on p.sk = k.sk left join rc c on c.sk = k.sk;
$$;

-- ============================================================
-- P5 PO - GRN - bill match and open POs
-- ============================================================
create or replace function public._r3q_p5_po_match(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with t as (select (now() at time zone 'Asia/Dhaka')::date as today)
  select jsonb_build_object('po_no', p.po_no, 'day', p.entry_date, 'location_bn', l.name_bn, 'supplier', coalesce(p.supplier, '-'), 'delivery_date', p.delivery_date,
    'po_lines', p.po_lines, 'lines_open', p.lines_open, 'po_total', round(coalesce(p.po_total, 0), 2), 'grn_n', p.grn_n, 'grn_value', case when p.grn_n > 0 then round(coalesce(p.grn_value, 0), 2) end,
    'bill_n', p.bill_n, 'bill_amount', case when p.bill_n > 0 then round(coalesce(p.bill_amount, 0), 2) end,
    'bill_diff', case when p.bill_n > 0 and p.grn_n > 0 and p.bill_amount is not null then round(p.bill_amount - coalesce(p.grn_value, 0), 2) end,
    'days_late', case when p.delivery_date is null then null
                      when p.grn_n = 0 or p.lines_open > 0 then greatest(t.today - p.delivery_date, 0)
                      else greatest(p.last_grn - p.delivery_date, 0) end,
    'status', case when p.grn_n = 0 then 'খোলা / open'
                   when p.lines_open > 0 then 'আংশিক / partial'
                   when p.bill_n = 0 then 'প্রাপ্ত, বিল নেই / received, not billed'
                   when p.bill_amount is not null and abs(p.bill_amount - coalesce(p.grn_value, 0)) <= 0.5 then 'বিল মিলেছে / matched'
                   else 'বিল অমিল / bill differs' end)
    from public._p26_po(d1, d2, locs) p join public.locations l on l.id = p.location_id cross join t;
$$;

-- ============================================================
-- P6 purchase spent vs the 10-4 purchase budget (+ the phase4 outlook for the latest sheet of each place)
--   budget = hub cash + showroom floats + bank + mobile + receivable(7d) - payable(7d) - protected minimum cash (location setting hub_min_cash), exactly as the 10-4 sheet works it out.
--   No hub_min_cash setting = the budget was never captured = null. Spent = posted purchase bills of the 7 days from the sheet date; where there are none, the 04-1 GRN value.
-- ============================================================
create or replace function public._r3q_p6_purchase_budget(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with b as (
    select e.id, e.location_id, e.entry_date,
      coalesce(public._r2_num(e.data -> 'hub_cash'), 0) + coalesce(public._r2_num(e.data -> 'sr_float'), 0) + coalesce(public._r2_num(e.data -> 'bank'), 0) + coalesce(public._r2_num(e.data -> 'mobile'), 0) as a,
      (select coalesce(sum(public._r2_num(x -> 'amt')), 0) from jsonb_array_elements(public._p26_arr(e.data -> 'recv')) x) as bt,
      (select coalesce(sum(public._r2_num(x -> 'amt')), 0) from jsonb_array_elements(public._p26_arr(e.data -> 'pay')) x) as ct,
      (select public._r2_num(ls.value) from public.location_settings ls where ls.location_id = e.location_id and ls.key = 'hub_min_cash') as mn,
      row_number() over (partition by e.location_id order by e.entry_date desc, e.serial desc) as rn
      from public.entries e
     where e.form_code = '10-4' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)),
  c as (
    select b.*, case when b.mn is not null then b.a + b.bt - b.ct - b.mn end as budget,
      (select coalesce(sum(case when pb.kind = 'bill' then pb.total else -pb.total end), 0) from public.purchase_bills pb
        where pb.status = 'posted' and pb.location_id = b.location_id and pb.bill_date between b.entry_date and b.entry_date + 6) as bills,
      (select coalesce(sum(public._r2_num(gl -> 'counted') * public._r2_num(gl -> 'rate')), 0) from public.entries g
        cross join lateral jsonb_array_elements(public._p26_arr(g.data -> 'lines')) gl
        where g.form_code = '04-1' and g.status in ('submitted', 'approved') and g.location_id = b.location_id and g.entry_date between b.entry_date and b.entry_date + 6
          and public._r2_num(gl -> 'counted') > 0 and public._r2_num(gl -> 'rate') > 0) as grn,
      case when b.rn = 1 then public._p26_outlook(b.location_id) end as ol
      from b),
  d as (select c.*, case when c.bills > 0 then c.bills else c.grn end as spent from c)
  select jsonb_build_object('location_bn', l.name_bn, 'day', d.entry_date, 'cash_total', round(d.a, 2), 'receivable', round(d.bt, 2), 'payable', round(d.ct, 2), 'min_cash', d.mn, 'budget', round(d.budget, 2),
    'bills_7d', round(d.bills, 2), 'grn_7d', round(d.grn, 2), 'spent', round(d.spent, 2),
    'used_pct', case when d.budget > 0 then round(d.spent / d.budget * 100, 1) end, 'budget_left', case when d.budget is not null then round(d.budget - d.spent, 2) end,
    'outlook_low', case when d.ol is not null and jsonb_typeof(d.ol -> 'est_purchase_low') = 'number' then (d.ol ->> 'est_purchase_low')::numeric end,
    'outlook_high', case when d.ol is not null and jsonb_typeof(d.ol -> 'est_purchase_high') = 'number' then (d.ol ->> 'est_purchase_high')::numeric end)
    from d join public.locations l on l.id = d.location_id;
$$;

-- ============================================================
-- K2 stock-count variance per counter and item (quantities only; rows need both the counted and the book figure)
-- ============================================================
create or replace function public._r3q_k2_count_variance(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with cat as (select public.rpt_arr_text(flt -> 'categories') as c),
  ln as (
    select e.location_id, e.entry_date, e.serial, nullif(btrim(e.data ->> 'counted_by'), '') as cb, r ->> 'item' as icode,
           public._r2_num(r -> 'count') as cnt, public._r2_num(r -> 'book') as bk, nullif(btrim(r ->> 'reason'), '') as reason
      from public.entries e cross join lateral jsonb_array_elements(public._p26_arr(e.data -> 'rows')) r
     where e.form_code = '04-3' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)),
  g as (
    select ln.location_id, ln.cb, i.id as item_id, i.code, i.name_bn, count(*) as counts, count(*) filter (where ln.cnt <> ln.bk) as off_n,
           count(*) filter (where ln.cnt < ln.bk) as short_n, count(*) filter (where ln.cnt > ln.bk) as over_n,
           sum(ln.cnt - ln.bk) as net_var, sum(abs(ln.cnt - ln.bk)) as abs_var, max(ln.entry_date) as last_date,
           (array_agg(ln.reason order by ln.entry_date desc, ln.serial desc) filter (where ln.reason is not null and ln.cnt <> ln.bk))[1] as last_reason
      from ln join public.items i on i.code = ln.icode cross join cat
     where ln.cnt is not null and ln.bk is not null and (cat.c is null or i.category = any (cat.c))
     group by ln.location_id, ln.cb, i.id, i.code, i.name_bn)
  select jsonb_build_object('location_bn', l.name_bn, 'counter', coalesce(nullif(btrim(p.full_name), '') || ' · ' || g.cb, g.cb, '-'), 'item_code', g.code, 'item_bn', g.name_bn,
    'counts', g.counts, 'off_n', g.off_n, 'short_n', g.short_n, 'over_n', g.over_n, 'net_var', round(g.net_var, 3), 'abs_var', round(g.abs_var, 3),
    'off_pct', round(g.off_n * 100.0 / g.counts, 1), 'last_date', g.last_date, 'last_reason', g.last_reason)
    from g join public.locations l on l.id = g.location_id left join public.profiles p on p.staff_id = g.cb;
$$;

-- ============================================================
-- F1 production and dispatch: production_runs (void runs kept, status void), 05-1 sheets, stock transfers sent
-- ============================================================
create or replace function public._r3q_f1_production(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with u as (
    select 'রান / run'::text as source, (r.made_at at time zone 'Asia/Dhaka')::date as day, r.location_id, r.item_id, r.batches as batches, r.yield_base as qty, r.status as status, null::int as to_loc
      from public.production_runs r
     where r.location_id = any (locs) and (r.made_at at time zone 'Asia/Dhaka')::date between d1 and d2
    union all
    select 'শিট / sheet', e.entry_date, e.location_id, i.id, case when o.rn = 1 then public._r2_num(e.data -> 'batches') end, public._r2_num(o.r -> 'qty'), e.status, null
      from public.entries e
      cross join lateral (select t.r, row_number() over (order by t.ord) as rn from jsonb_array_elements(public._p26_arr(e.data -> 'output')) with ordinality t(r, ord)
                           where public._r2_num(t.r -> 'qty') > 0 and nullif(t.r ->> 'item', '') is not null) o
      left join public.items i on i.code = o.r ->> 'item'
     where e.form_code = '05-1' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)
    union all
    select 'শিট / sheet', e.entry_date, e.location_id, null::uuid, public._r2_num(e.data -> 'batches'), null::numeric, e.status, null
      from public.entries e
     where e.form_code = '05-1' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)
       and public._r2_num(e.data -> 'batches') is not null
       and not exists (select 1 from jsonb_array_elements(public._p26_arr(e.data -> 'output')) t(r) where public._r2_num(t.r -> 'qty') > 0 and nullif(t.r ->> 'item', '') is not null)
    union all
    select 'চালান / dispatch', (t.sent_at at time zone 'Asia/Dhaka')::date, t.from_location_id, t.item_id, null, t.qty, t.status, t.to_location_id
      from public.stock_transfers t
     where t.from_location_id = any (locs) and (t.sent_at at time zone 'Asia/Dhaka')::date between d1 and d2)
  select jsonb_build_object('source', u.source, 'day', u.day, 'location_bn', l.name_bn, 'product_code', i.code, 'product_bn', i.name_bn, 'unit', i.unit,
    'batches', u.batches, 'qty', u.qty, 'status', u.status, 'to_location_bn', lt.name_bn)
    from u join public.locations l on l.id = u.location_id left join public.items i on i.id = u.item_id left join public.locations lt on lt.id = u.to_loc;
$$;

-- ============================================================
-- F2 yield vs the approved 05-4 standard (per place and product), with what the production runs and the sheets made in the same period
--   standard = average good-per-input of the latest APPROVED 05-4 sheet up to the end of the period. production_runs post the recipe yield by definition, so they are shown as quantities, not as a yield test.
-- ============================================================
create or replace function public._r3q_f2_yield(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with t as (
    select e.location_id, i.id as item_id, e.entry_date, e.serial, e.status, coalesce(public._p26_d(r ->> 'date'), e.entry_date) as bdate,
           public._r2_num(r -> 'input') as inp, public._r2_num(r -> 'good') as good, public._r2_num(r -> 'second') as sec, public._r2_num(r -> 'waste') as wst
      from public.entries e join public.items i on i.code = e.data ->> 'item'
      cross join lateral jsonb_array_elements(public._p26_arr(e.data -> 'b')) r
     where e.form_code = '05-4' and e.status in ('submitted', 'approved') and e.entry_date <= d2 and e.location_id = any (locs)),
  std as (
    select distinct on (location_id, item_id) location_id, item_id, y
      from (select location_id, item_id, entry_date, serial, avg(good / inp) as y from t where status = 'approved' and inp > 0 and good is not null group by 1, 2, 3, 4) s
     order by location_id, item_id, entry_date desc, serial desc),
  p as (
    select location_id, item_id, count(*) as n, avg(good / inp) as ty,
           avg(coalesce(sec, 0) / nullif(good + coalesce(sec, 0) + coalesce(wst, 0), 0) * 100) as sec_pct, avg(coalesce(wst, 0) / nullif(good + coalesce(sec, 0) + coalesce(wst, 0), 0) * 100) as wst_pct
      from t where inp > 0 and good is not null and bdate between d1 and d2 group by 1, 2),
  runs as (
    select r.location_id, r.item_id, sum(r.batches) as b, sum(r.yield_base) as q
      from public.production_runs r
     where r.status = 'done' and r.location_id = any (locs) and (r.made_at at time zone 'Asia/Dhaka')::date between d1 and d2 group by 1, 2),
  sh as (
    select e.location_id, i.id as item_id, sum(public._base_qty(i.id, public._r2_num(o -> 'qty'), i.unit)) as q
      from public.entries e cross join lateral jsonb_array_elements(public._p26_arr(e.data -> 'output')) o join public.items i on i.code = o ->> 'item'
     where e.form_code = '05-1' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs) and public._r2_num(o -> 'qty') > 0
     group by 1, 2),
  k as (select location_id, item_id from p union select location_id, item_id from runs union select location_id, item_id from sh)
  select jsonb_build_object('location_bn', l.name_bn, 'item_code', i.code, 'item_bn', i.name_bn, 'std_yield', round(s.y, 4), 'tests_n', coalesce(p.n, 0), 'test_yield', round(p.ty, 4),
    'yield_diff_pct', case when s.y > 0 and p.ty is not null then round((p.ty - s.y) / s.y * 100, 2) end, 'second_pct', round(p.sec_pct, 2), 'waste_pct', round(p.wst_pct, 2),
    'run_batches', runs.b, 'run_qty', round(runs.q, 3), 'sheet_qty', round(sh.q, 3),
    'qty_gap', case when sh.q is not null and runs.q is not null then round(sh.q - runs.q, 3) end)
    from k join public.locations l on l.id = k.location_id join public.items i on i.id = k.item_id
    left join std s on s.location_id = k.location_id and s.item_id = k.item_id left join p on p.location_id = k.location_id and p.item_id = k.item_id
    left join runs on runs.location_id = k.location_id and runs.item_id = k.item_id left join sh on sh.location_id = k.location_id and sh.item_id = k.item_id;
$$;

-- ============================================================
-- F3 raw material really issued to production (stock_ledger issue_out, ref_type production) vs recipe lines x batches (_recipe_need). Quantities only.
-- ============================================================
create or replace function public._r3q_f3_raw_vs_recipe(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with runs as (
    select r.id, r.location_id, r.item_id as prod, r.recipe_id, r.batches
      from public.production_runs r
     where r.status = 'done' and r.location_id = any (locs) and (r.made_at at time zone 'Asia/Dhaka')::date between d1 and d2),
  need as (
    select r.id as run_id, r.location_id, r.prod, r.batches, n.item_id as ing, n.need, n.waste_missing, n.base_unit, n.code, n.name_bn
      from runs r cross join lateral public._recipe_need(r.recipe_id, r.batches, r.location_id) n where n.kind = 'ingredient'),
  act as (
    select n.run_id, n.ing, -sum(l.qty_delta) as used
      from need n join public.stock_ledger l on l.ref_type = 'production' and l.ref_id = n.run_id::text and l.reason = 'issue_out' and l.item_id = n.ing
       and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id)
     group by n.run_id, n.ing),
  g as (
    select n.location_id, n.prod, n.ing, min(n.code) as code, min(n.name_bn) as name_bn, min(n.base_unit) as base_unit, count(*) as runs, sum(n.batches) as batches,
           sum(n.need) as expected, sum(a.used) as actual, count(*) filter (where n.waste_missing) as waste_missing
      from need n left join act a on a.run_id = n.run_id and a.ing = n.ing group by n.location_id, n.prod, n.ing)
  select jsonb_build_object('location_bn', l.name_bn, 'product_code', p.code, 'product_bn', p.name_bn, 'ingredient_code', g.code, 'ingredient_bn', g.name_bn, 'base_unit', g.base_unit,
    'runs', g.runs, 'batches', g.batches, 'expected', round(g.expected, 4), 'actual', round(g.actual, 4),
    'diff', case when g.actual is not null then round(g.actual - g.expected, 4) end,
    'diff_pct', case when g.actual is not null and g.expected > 0 then round((g.actual - g.expected) / g.expected * 100, 2) end, 'waste_missing', g.waste_missing)
    from g join public.locations l on l.id = g.location_id join public.items p on p.id = g.prod;
$$;

-- ============================================================
-- F4 machine breakdown (05-1 breakdown fields) and maintenance requests (08-1); open requests are listed whatever their date
-- ============================================================
create or replace function public._r3q_f4_breakdowns(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with m as (
    select e.id, e.location_id, e.entry_date, e.data, nullif(btrim(e.data ->> 'machine'), '') as machine,
           coalesce(public._p26_d(e.data ->> 'found_date'), e.entry_date) as fd,
           public._p26_d(e.data ->> 'done_date') as dd,
           case when e.data ->> 'found_time' ~ '^\d{1,2}:\d{2}' then (e.data ->> 'found_time')::time end as ft,
           case when e.data ->> 'done_time' ~ '^\d{1,2}:\d{2}' then (e.data ->> 'done_time')::time end as dt
      from public.entries e
     where e.form_code = '08-1' and e.status in ('submitted', 'approved') and e.location_id = any (locs)),
  r8 as (
    select m.*, (m.fd + coalesce(m.ft, time '00:00')) as fts, case when m.dd is not null then m.dd + coalesce(m.dt, time '00:00') end as dts,
           (select string_agg(pr.lbl, ', ') from (values ('p_stop', 'চলছে না / not running'), ('p_cool', 'ঠান্ডা হচ্ছে না / not cooling'), ('p_noise', 'শব্দ / noise'), ('p_leak', 'লিক / leak'),
              ('p_power', 'বিদ্যুৎ / electrical'), ('p_other', 'অন্য / other')) pr(k, lbl) where public._p26_b(m.data -> pr.k)) as problem
      from m),
  a as (
    select r8.*, (select count(*) from r8 o where o.location_id = r8.location_id and lower(o.machine) = lower(r8.machine) and o.fd between r8.fd - 365 and r8.fd)::int as repeat_n
      from r8 where r8.fd <= d2 and (r8.fd >= d1 or r8.dd is null)),
  s as (
    select '08-1'::text as source, a.fd as day, a.location_id, a.machine, a.problem,
           case when a.dd is null then 'খোলা / open' else 'শেষ / closed' end as status, a.ft::text as ftime,
           case when a.dts is not null and a.dts >= a.fts then round(extract(epoch from (a.dts - a.fts))::numeric / 3600, 1) end as downtime_h,
           public._r2_num(a.data -> 'est_cost') as est_cost, public._r2_num(a.data -> 'actual_cost') as actual_cost, a.repeat_n, null::text as ref
      from a
    union all
    select '05-1', e.entry_date, e.location_id, nullif(btrim(e.data ->> 'bd_machine'), ''), null, 'শিটে লেখা / on sheet', nullif(e.data ->> 'bd_time', ''), null, null, null, null, nullif(btrim(e.data ->> 'bd_request'), '')
      from public.entries e
     where e.form_code = '05-1' and e.status in ('submitted', 'approved') and e.data ->> 'breakdown' = 'yes' and e.entry_date between d1 and d2 and e.location_id = any (locs))
  select jsonb_build_object('source', s.source, 'day', s.day, 'location_bn', l.name_bn, 'machine', coalesce(s.machine, '-'), 'problem', s.problem, 'status', s.status, 'found_time', s.ftime,
    'downtime_h', s.downtime_h, 'est_cost', s.est_cost, 'actual_cost', s.actual_cost, 'repeat_n', s.repeat_n, 'request_ref', s.ref)
    from s join public.locations l on l.id = s.location_id;
$$;

-- ============================================================
-- M2 marketing spend (18-1 lines, dated by the line date, else the sheet date) and sales (status done) side by side per day and place. No ratio, no causal claim.
-- ============================================================
create or replace function public._r3q_m2_marketing_vs_sales(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with ml as (
    select e.location_id, coalesce(public._p26_d(ln ->> 'date'), e.entry_date) as day,
           public._r2_num(ln -> 'amt') as amt, public._r2_num(ln -> 'nonpay') as nonpay,
           case when ln ->> 'head' like 'other:%' then 'other' else coalesce(nullif(btrim(ln ->> 'head'), ''), '-') end as head
      from public.entries e cross join lateral jsonb_array_elements(public._p26_arr(e.data -> 'lines')) ln
     where e.form_code = '18-1' and e.status in ('submitted', 'approved') and e.location_id = any (locs)),
  mh as (
    select ml.location_id, ml.day, ml.head, sum(coalesce(ml.amt, 0)) as amt, sum(coalesce(ml.nonpay, 0)) as nonpay, count(*) as n
      from ml where ml.day between d1 and d2 and (ml.amt is not null or ml.nonpay is not null) group by 1, 2, 3),
  mk as (
    select h.location_id, h.day, sum(h.amt) as spend, sum(h.nonpay) as nonpay, sum(h.n) as n,
           string_agg(coalesce(o.label_bn, h.head) || ' ' || to_char(h.amt, 'FM999999999990.##'), ', ' order by h.amt desc) as heads
      from mh h left join public.option_lists o on o.list_code = 'marketing_heads' and o.value_code = h.head group by 1, 2),
  sl as (
    select s.location_id, s.sale_date as day, sum(s.total) as total, count(*) as n
      from public.sales s where s.status = 'done' and s.location_id = any (locs) and s.sale_date between d1 and d2 group by 1, 2)
  select jsonb_build_object('day', coalesce(mk.day, sl.day), 'location_bn', l.name_bn, 'spend', round(coalesce(mk.spend, 0), 2), 'nonpay_value', round(coalesce(mk.nonpay, 0), 2),
    'mkt_lines', coalesce(mk.n, 0), 'heads', mk.heads, 'sales_total', round(coalesce(sl.total, 0), 2), 'sales_n', coalesce(sl.n, 0))
    from mk full join sl on sl.location_id = mk.location_id and sl.day = mk.day
    join public.locations l on l.id = coalesce(mk.location_id, sl.location_id);
$$;

-- ============================================================
-- Q1 fridge temperature log: 05-1 (fridges, fridges2 rows 1-2) and 14-1 (fridges rows 1-3, t2_1 / t2_2 second reading on busy days).
--   limits from location_settings fridgeN_min / fridgeN_max; no limit set = out_n null (never guessed).
-- ============================================================
create or replace function public._r3q_q1_fridge_temp(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with rd as (
    select e.location_id, e.entry_date as day, e.serial, e.form_code as form, f.n,
           public._r2_num(case when jsonb_typeof(e.data -> 'fridges') = 'array' then e.data -> 'fridges' -> (f.n - 1) -> 'temp' end) as r1,
           case when e.form_code = '05-1' then public._r2_num(case when jsonb_typeof(e.data -> 'fridges2') = 'array' then e.data -> 'fridges2' -> (f.n - 1) -> 'temp' end)
                when f.n = 1 then public._r2_num(e.data -> 't2_1') when f.n = 2 then public._r2_num(e.data -> 't2_2') end as r2
      from public.entries e
      cross join lateral generate_series(1, case when e.form_code = '05-1' then 2 else 3 end) f(n)
     where e.form_code in ('05-1', '14-1') and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)),
  x as (
    select rd.*, (select public._r2_num(ls.value) from public.location_settings ls where ls.location_id = rd.location_id and ls.key = 'fridge' || rd.n || '_min') as lo,
           (select public._r2_num(ls.value) from public.location_settings ls where ls.location_id = rd.location_id and ls.key = 'fridge' || rd.n || '_max') as hi,
           (select ls.value #>> '{}' from public.location_settings ls where ls.location_id = rd.location_id and ls.key = 'fridge' || rd.n || '_name') as fname
      from rd where rd.r1 is not null or rd.r2 is not null)
  select jsonb_build_object('day', x.day, 'location_bn', l.name_bn, 'form', x.form, 'fridge', x.n, 'fridge_name', x.fname, 'reading1', x.r1, 'reading2', x.r2, 'min_c', x.lo, 'max_c', x.hi,
    'out_n', case when x.lo is null or x.hi is null then null
                  else (case when x.r1 is not null and (x.r1 < x.lo or x.r1 > x.hi) then 1 else 0 end) + (case when x.r2 is not null and (x.r2 < x.lo or x.r2 > x.hi) then 1 else 0 end) end)
    from x join public.locations l on l.id = x.location_id;
$$;

-- ============================================================
-- Q2 hygiene / expiry / checklist compliance per sheet: 14-1 (16 closing steps c1..c16, expired goods shown but not removed), 05-1 (hygiene, pots, equipment, cleaning, shut-down ticks)
-- ============================================================
create or replace function public._r3q_q2_hygiene(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with e0 as (
    select e.id, e.location_id, e.entry_date, e.form_code, e.data,
           case when e.form_code = '14-1' then array['c1','c2','c3','c4','c5','c6','c7','c8','c9','c10','c11','c12','c13','c14','c15','c16']
                else array['pots_done','hygiene_done','machines_done','clean_done','machines_off','gas_off','power_off','fire_safe'] end as ks
      from public.entries e
     where e.form_code in ('14-1', '05-1') and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)),
  c as (
    select e0.*, cardinality(e0.ks) as total, (select count(*) from unnest(e0.ks) k where public._p26_b(e0.data -> k))::int as done,
           (select string_agg(k, ', ' order by ordinality) from unnest(e0.ks) with ordinality u(k, ordinality) where not public._p26_b(e0.data -> k)) as missed_list
      from e0)
  select jsonb_build_object('day', c.entry_date, 'location_bn', l.name_bn, 'form', c.form_code, 'checks', c.total, 'done', c.done, 'missed', c.total - c.done,
    'compliance_pct', round(c.done * 100.0 / c.total, 1),
    'expired_shown', case when c.form_code = '14-1' then (case when c.data ->> 'expired_shown' = 'yes' then 1 else 0 end) end,
    'expired_not_removed', case when c.form_code = '14-1' then (case when c.data ->> 'expired_shown' = 'yes' and not public._p26_b(c.data -> 'expired_removed') then 1 else 0 end) end,
    'missed_list', c.missed_list)
    from c join public.locations l on l.id = c.location_id;
$$;

-- ============================================================
-- Q3 complaints (20-3, one count per ticked cause) and sale returns (reason_code, per returned line) grouped by cause, product and place
-- ============================================================
create or replace function public._r3q_q3_complaints(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with cat as (select public.rpt_arr_text(flt -> 'categories') as c),
  lbl(k, t) as (values ('taste', 'স্বাদ / taste'), ('smell', 'গন্ধ, নষ্ট / smell, spoiled'), ('broken', 'ভাঙা / broken'), ('short', 'পরিমাণে কম / short quantity'), ('wrong', 'ভুল পণ্য / wrong goods'),
                       ('late', 'দেরি / late'), ('staff', 'কর্মীর আচরণ / staff behaviour'), ('sick', 'খেয়ে অসুস্থ / fell ill'), ('other', 'অন্য / other'), ('none', 'কারণ টিক নেই / no cause ticked')),
  c1 as (
    select e.location_id, i.id as item_id, public._r2_num(e.data -> 'qty') as qty, public._r2_num(e.data -> 'refund_amt') as refund,
           nullif(btrim(e.check_data ->> 'root_cause'), '') is null as no_root, not public._p26_b(e.check_data -> 'resolved') as unresolved, public._p26_b(e.data -> 'c_sick') as sick,
           coalesce((select array_agg(k) from unnest(array['taste','smell','broken','short','wrong','late','staff','sick','other']) k where public._p26_b(e.data -> ('c_' || k))), array['none']) as ks
      from public.entries e left join public.items i on i.code = e.data ->> 'item'
     where e.form_code = '20-3' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)),
  a as (
    select '20-3 অভিযোগ / complaint'::text as source, k as cause_code, c1.location_id, c1.item_id, count(*) as n, sum(c1.qty) as qty, sum(c1.refund) as refund,
           count(*) filter (where c1.unresolved) as unresolved, count(*) filter (where c1.sick) as sick, count(*) filter (where c1.no_root) as no_root
      from c1, unnest(c1.ks) k group by k, c1.location_id, c1.item_id),
  b as (
    select 'রিটার্ন / sale return'::text as source, sr.reason_code as cause_code, sr.location_id, nullif(x ->> 'item_id', '')::uuid as item_id, count(*) as n,
           sum(public._r2_num(x -> 'qty')) as qty, sum(public._r2_num(x -> 'amount')) as refund, null::bigint as unresolved, null::bigint as sick, null::bigint as no_root
      from public.sale_returns sr cross join lateral jsonb_array_elements(public._p26_arr(sr.lines)) x
     where sr.status = 'done' and sr.location_id = any (locs) and (sr.created_at at time zone 'Asia/Dhaka')::date between d1 and d2
       and (x ->> 'item_id') ~ '^[0-9a-f-]{36}$'
     group by sr.reason_code, sr.location_id, nullif(x ->> 'item_id', '')::uuid),
  u as (select * from a union all select * from b)
  select jsonb_build_object('source', u.source, 'cause', case when u.source like '20-3%' then coalesce(lbl.t, u.cause_code) else coalesce(o.label_bn, u.cause_code) end,
    'location_bn', l.name_bn, 'product_code', i.code, 'product_bn', coalesce(i.name_bn, '-'), 'n', u.n, 'qty', round(u.qty, 3), 'refund_amt', round(u.refund, 2),
    'unresolved', u.unresolved, 'sick', u.sick, 'no_root_cause', u.no_root)
    from u join public.locations l on l.id = u.location_id left join public.items i on i.id = u.item_id cross join cat
    left join lbl on u.source like '20-3%' and lbl.k = u.cause_code
    left join public.option_lists o on u.source not like '20-3%' and o.list_code = 'return_reasons' and o.value_code = u.cause_code
   where cat.c is null or i.category = any (cat.c);
$$;

-- ============================================================
-- the registry rows
-- ============================================================
insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('p2_rate_trend', 'P2', 'purchase', 'ক্রয়-দর ধারা (আইটেম ও সাপ্লায়ার)', 'Purchase rate trend per item and supplier', 'ক্রয়-দর ধারা (Item ও Supplier)',
  '[["item_code","কোড","Code","text"],["item_bn","আইটেম","Item","text"],["supplier","সাপ্লায়ার","Supplier","text"],["n","বার","Times","int"],["qty","পরিমাণ","Quantity","num"],["first_rate","প্রথম দর","First rate","money"],["last_rate","শেষ দর","Last rate","money"],["min_rate","সর্বনিম্ন","Lowest","money"],["max_rate","সর্বোচ্চ","Highest","money"],["avg_rate","গড় দর","Average rate","money"],["change_pct","বদল %","Change %","pct"],["last_date","শেষ তারিখ","Last date","date"]]'::jsonb,
  '{}', 'change_pct', 'desc', array['locations','categories'], false, true, false, 2601),
 ('p4_supplier_score', 'P4', 'purchase', 'সাপ্লায়ার স্কোরকার্ড', 'Supplier scorecard', 'Supplier স্কোরকার্ড',
  '[["supplier","সাপ্লায়ার","Supplier","text"],["grns","গ্রহণ রসিদ","GRNs","int"],["lines","লাইন","Lines","int"],["short_lines","কম পাওয়া লাইন","Short lines","int"],["rejected","ফেরত লাইন","Returned lines","int"],["held","আটক লাইন","Held lines","int"],["reduced","দর কমানো লাইন","Reduced-rate lines","int"],["bills_checked","যাচাই বিল","Bills checked","int"],["short_claims","ঘাটতির দাবি","Shortage claims","int"],["return_claims","ফেরতের দাবি","Return claims","int"],["pos","পারচেজ অর্ডার","POs","int"],["late_pos","দেরিতে আসা PO","Late POs","int"],["overdue_open","মেয়াদ পেরোনো খোলা PO","Overdue open POs","int"],["rate_change_pct","গড় দর বদল %","Avg rate change %","pct"],["rate_items","তুলনার আইটেম","Items compared","int"]]'::jsonb,
  array['grns','lines','short_lines','rejected','held','reduced','bills_checked','short_claims','return_claims','pos','late_pos','overdue_open'], 'rejected', 'desc', array['locations'], false, true, false, 2602),
 ('p5_po_match', 'P5', 'purchase', 'PO-GRN-বিল মিল ও খোলা PO', 'PO - GRN - bill match and open POs', 'PO-GRN-Bill মিল ও খোলা PO',
  '[["po_no","PO নং","PO no.","text"],["day","তারিখ","Date","date"],["location_bn","লোকেশন","Location","text"],["supplier","সাপ্লায়ার","Supplier","text"],["delivery_date","ডেলিভারির তারিখ","Delivery date","date"],["po_lines","PO লাইন","PO lines","int"],["lines_open","বাকি লাইন","Lines still open","int"],["po_total","PO মোট","PO total","money"],["grn_n","GRN সংখ্যা","GRNs","int"],["grn_value","GRN মূল্য","GRN value","money"],["bill_n","বিল","Bills","int"],["bill_amount","বিলের অঙ্ক","Bill amount","money"],["bill_diff","বিল − GRN","Bill − GRN","money"],["days_late","দেরি (দিন)","Days late","int"],["status","অবস্থা","Status","text"]]'::jsonb,
  '{}', 'days_late', 'desc', array['locations'], false, true, false, 2603),
 ('p6_purchase_budget', 'P6', 'purchase', 'ক্রয় বনাম বাজেট ও পূর্বাভাস', 'Purchases vs budget and outlook', 'ক্রয় বনাম Budget ও Outlook',
  '[["location_bn","লোকেশন","Location","text"],["day","শিটের তারিখ","Sheet date","date"],["cash_total","মোট হাতে","Total cash","money"],["receivable","প্রাপ্য (৭ দিন)","Receivable (7d)","money"],["payable","দেয় (৭ দিন)","Payable (7d)","money"],["min_cash","ন্যূনতম নগদ","Minimum cash","money"],["budget","পারচেজ বাজেট","Purchase budget","money"],["bills_7d","ক্রয় বিল (৭ দিন)","Purchase bills (7d)","money"],["grn_7d","GRN মূল্য (৭ দিন)","GRN value (7d)","money"],["spent","খরচ","Spent","money"],["used_pct","ব্যবহার %","Used %","pct"],["budget_left","বাজেটের বাকি","Budget left","money"],["outlook_low","পূর্বাভাস কম","Outlook low","money"],["outlook_high","পূর্বাভাস বেশি","Outlook high","money"]]'::jsonb,
  '{}', 'day', 'desc', array['locations'], false, true, false, 2604),
 ('k2_count_variance', 'K2', 'stock', 'স্টক গণনার পার্থক্য', 'Stock count variance', 'Stock গণনার পার্থক্য',
  '[["location_bn","লোকেশন","Location","text"],["counter","গণনাকারী","Counter","text"],["item_code","কোড","Code","text"],["item_bn","আইটেম","Item","text"],["counts","গণনা","Counts","int"],["off_n","পার্থক্য হয়েছে","Times off","int"],["short_n","কম","Short","int"],["over_n","বেশি","Over","int"],["net_var","নিট পার্থক্য","Net variance","num"],["abs_var","মোট পার্থক্য (চিহ্ন ছাড়া)","Absolute variance","num"],["off_pct","পার্থক্য %","Off %","pct"],["last_date","শেষ তারিখ","Last date","date"],["last_reason","শেষ কারণ","Last reason","text"]]'::jsonb,
  array['counts','off_n','short_n','over_n'], 'off_n', 'desc', array['locations','categories'], false, false, false, 2605),
 ('f1_production', 'F1', 'stock', 'দৈনিক উৎপাদন ও চালান', 'Production and dispatch', 'দৈনিক উৎপাদন ও Dispatch',
  '[["source","উৎস","Source","text"],["day","তারিখ","Date","date"],["location_bn","লোকেশন","Location","text"],["product_code","কোড","Code","text"],["product_bn","পণ্য","Product","text"],["unit","একক","Unit","text"],["batches","ব্যাচ","Batches","num"],["qty","পরিমাণ","Quantity","num"],["status","অবস্থা","Status","text"],["to_location_bn","গন্তব্য","To","text"]]'::jsonb,
  '{}', 'day', 'desc', array['locations'], false, false, false, 2606),
 ('f2_yield', 'F2', 'stock', 'ফলন বনাম স্ট্যান্ডার্ড', 'Yield vs standard', 'ফলন বনাম Standard',
  '[["location_bn","লোকেশন","Location","text"],["item_code","কোড","Code","text"],["item_bn","পণ্য","Product","text"],["std_yield","স্ট্যান্ডার্ড ফলন","Standard yield","num"],["tests_n","মাপ","Measurements","int"],["test_yield","মাপা ফলন","Measured yield","num"],["yield_diff_pct","পার্থক্য %","Difference %","pct"],["second_pct","২য় গ্রেড %","2nd grade %","pct"],["waste_pct","নষ্ট %","Waste %","pct"],["run_batches","রানের ব্যাচ","Run batches","num"],["run_qty","রানের পরিমাণ","Run quantity","num"],["sheet_qty","শিটের পরিমাণ","Sheet quantity","num"],["qty_gap","শিট − রান","Sheet − run","num"]]'::jsonb,
  '{}', 'yield_diff_pct', 'asc', array['locations'], false, false, false, 2607),
 ('f3_raw_vs_recipe', 'F3', 'stock', 'কাঁচামাল ব্যবহার বনাম রেসিপি', 'Raw material use vs recipe', 'কাঁচামাল ব্যবহার বনাম Recipe',
  '[["location_bn","লোকেশন","Location","text"],["product_code","পণ্যের কোড","Product code","text"],["product_bn","পণ্য","Product","text"],["ingredient_code","উপকরণের কোড","Ingredient code","text"],["ingredient_bn","উপকরণ","Ingredient","text"],["base_unit","একক","Unit","text"],["runs","রান","Runs","int"],["batches","ব্যাচ","Batches","num"],["expected","রেসিপি অনুযায়ী","Per recipe","num"],["actual","আসলে ইস্যু","Actually issued","num"],["diff","পার্থক্য","Difference","num"],["diff_pct","পার্থক্য %","Difference %","pct"],["waste_missing","অপচয়-% নেই","No waste % set","int"]]'::jsonb,
  '{}', 'diff_pct', 'desc', array['locations'], false, false, false, 2608),
 ('f4_breakdowns', 'F4', 'stock', 'মেশিন বন্ধ ও মেইনটেন্যান্স', 'Machine breakdowns and maintenance', 'Machine বন্ধ ও Maintenance',
  '[["source","উৎস","Source","text"],["day","তারিখ","Date","date"],["location_bn","লোকেশন","Location","text"],["machine","যন্ত্র","Machine","text"],["problem","সমস্যা","Problem","text"],["status","অবস্থা","Status","text"],["found_time","সময়","Time","text"],["downtime_h","বন্ধ (ঘণ্টা)","Down (hours)","num"],["est_cost","আনুমানিক খরচ","Estimated cost","money"],["actual_cost","প্রকৃত খরচ","Actual cost","money"],["repeat_n","এক বছরে বার","Times in a year","int"],["request_ref","অনুরোধ নং","Request no.","text"]]'::jsonb,
  array['downtime_h','est_cost','actual_cost'], 'day', 'desc', array['locations'], false, false, false, 2609),
 ('m2_marketing_vs_sales', 'M2', 'marketing', 'মার্কেটিং খরচ ও বিক্রি (একই দিন)', 'Marketing spend and sales, same days', 'Marketing খরচ ও বিক্রি (একই দিন)',
  '[["day","তারিখ","Date","date"],["location_bn","লোকেশন","Location","text"],["spend","মার্কেটিং খরচ","Marketing spend","money"],["nonpay_value","টাকা ছাড়া মূল্য","Non-cash value","money"],["mkt_lines","খরচের লাইন","Expense lines","int"],["heads","খাত","Heads","text"],["sales_total","বিক্রি","Sales","money"],["sales_n","বিক্রির সংখ্যা","Sales count","int"]]'::jsonb,
  array['spend','nonpay_value','mkt_lines','sales_total','sales_n'], 'day', 'desc', array['locations'], false, false, false, 2610),
 ('q1_fridge_temp', 'Q1', 'quality', 'ফ্রিজ তাপমাত্রা লগ', 'Fridge temperature log', 'ফ্রিজ Temperature লগ',
  '[["day","তারিখ","Date","date"],["location_bn","লোকেশন","Location","text"],["form","ফর্ম","Form","text"],["fridge","ফ্রিজ নং","Fridge no.","int"],["fridge_name","ফ্রিজের নাম","Fridge name","text"],["reading1","প্রথম পাঠ °C","Reading 1 °C","num"],["reading2","দ্বিতীয় পাঠ °C","Reading 2 °C","num"],["min_c","সর্বনিম্ন সীমা","Lower limit","num"],["max_c","সর্বোচ্চ সীমা","Upper limit","num"],["out_n","সীমার বাইরে (পাঠ)","Readings out of range","int"]]'::jsonb,
  array['out_n'], 'out_n', 'desc', array['locations'], false, false, false, 2611),
 ('q2_hygiene', 'Q2', 'quality', 'হাইজিন, মেয়াদ ও চেকলিস্ট পালন', 'Hygiene, expiry and checklist compliance', 'Hygiene, মেয়াদ ও Checklist পালন',
  '[["day","তারিখ","Date","date"],["location_bn","লোকেশন","Location","text"],["form","ফর্ম","Form","text"],["checks","ধাপ","Steps","int"],["done","সম্পন্ন","Done","int"],["missed","বাদ","Missed","int"],["compliance_pct","পালন %","Compliance %","pct"],["expired_shown","মেয়াদ-শেষ ডিসপ্লেতে","Expired shown","int"],["expired_not_removed","না সরানো","Not removed","int"],["missed_list","বাদ পড়া ধাপ","Missed steps","text"]]'::jsonb,
  array['checks','done','missed','expired_shown','expired_not_removed'], 'compliance_pct', 'asc', array['locations'], false, false, false, 2612),
 ('q3_complaints', 'Q3', 'quality', 'অভিযোগ ও রিটার্নের কারণ', 'Complaints and return causes', 'অভিযোগ ও Return-এর কারণ',
  '[["source","উৎস","Source","text"],["cause","কারণ","Cause","text"],["location_bn","লোকেশন","Location","text"],["product_code","কোড","Code","text"],["product_bn","পণ্য","Product","text"],["n","সংখ্যা","Count","int"],["qty","পরিমাণ","Quantity","num"],["refund_amt","ফেরত/মূল্য","Refund / value","money"],["unresolved","অমীমাংসিত","Unresolved","int"],["sick","অসুস্থ","Fell ill","int"],["no_root_cause","মূল কারণ নেই","No root cause","int"]]'::jsonb,
  array['n','unresolved','sick','no_root_cause'], 'n', 'desc', array['locations','categories'], false, false, false, 2613)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
  sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

revoke all on function public._p26_d(text), public._p26_b(jsonb), public._p26_arr(jsonb), public._p26_rates(date, date, int[]), public._p26_po(date, date, int[]), public._p26_outlook(int) from public, anon, authenticated;
select public._r3_lockdown();
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase27.sql
-- ============================================================
-- PHASE 27 (group profit, engine 3 reports): L1 L2 L3 L4 L5 T3 T4
--   l1_pnl            profit & loss by month and shop            (cost, owner only)
--   l2_margin         margin by item and by category             (cost)
--   l3_shop_pnl       shop P&L side by side                      (cost, owner only)
--   l4_owner_sheet    owner's 01-2 sheet vs computed system      (cost, owner only)
--   l5_breakeven      break-even and cost coverage               (cost)
--   t3_payroll        payroll & advances (02-2, 02-3)            (owner only)
--   t4_staff_cost_ratio  salary / sales % by shop                (owner only)
-- Needs phase24 (report_defs3). Additive, idempotent. Costs only for cost-right holders; salary only for the owner.
-- Sources: sales (status done) net of sale_returns (rule reports_net_of_returns, default ON) exactly like biz_daily (phase23);
--   COGS only on lines whose item has a cost (item_costs, count_in_business) - the rest is shown as "uncosted %", never guessed;
--   expenses = 10-2 lines (as expense_by_head); salary = 02-2 pay lines; fixed = location setting fixed_cost_month (prorated by days of the month inside the period).
-- ============================================================

-- shared P&L builder: one row per month x shop. Private (no grants), called only from the _r3q_ functions (definer).
create or replace function public._p27_pl(d1 date, d2 date, locs int[])
returns table (o_m date, o_loc int, o_gross numeric, o_ret numeric, o_net numeric, o_costed numeric, o_cogs numeric, o_exp numeric, o_sal numeric, o_fixed numeric)
language sql stable security definer set search_path = public as $$
  with net_on as (select coalesce(public.rule_on('reports_net_of_returns'), true) as v),
  cst as (select ic.item_id, ic.cost_price from public.item_costs ic join public.items i on i.id = ic.item_id where i.count_in_business and ic.cost_price is not null),
  s as (select x.id, date_trunc('month', x.sale_date)::date as m, x.location_id, x.total, x.subtotal, x.lines from public.sales x
        where x.status = 'done' and x.sale_date between d1 and d2 and x.location_id = any (locs)),
  tot as (select m, location_id, sum(total) as rev from s group by 1, 2),
  ln as (
    select s.m, s.location_id, (case when s.subtotal > 0 then s.total / s.subtotal else 1 end) as f,
           case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'amount')::numeric end as amt,
           case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end as qty,
           case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end as iid
    from s, jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e),
  ag as (
    select ln.m, ln.location_id, sum(ln.amt * ln.f) filter (where c.cost_price is not null) as cr, sum(ln.qty * c.cost_price) filter (where c.cost_price is not null) as cg
    from ln left join cst c on c.item_id = ln.iid group by 1, 2),
  rr as (select r.id, date_trunc('month', (r.created_at at time zone 'Asia/Dhaka')::date)::date as m, r.location_id, r.amount, r.lines
         from public.sale_returns r, net_on
         where net_on.v and r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and r.location_id = any (locs)),
  rt as (select m, location_id, sum(amount) as ra from rr group by 1, 2),
  rl as (
    select rr.m, rr.location_id, c.cost_price,
           case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'amount')::numeric end as amt,
           case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end as qty
    from rr cross join lateral jsonb_array_elements(case when jsonb_typeof(rr.lines) = 'array' then rr.lines else '[]'::jsonb end) e
    left join cst c on c.item_id = (case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end)),
  rg as (select m, location_id, sum(amt) filter (where cost_price is not null) as rcr, sum(qty * cost_price) filter (where cost_price is not null) as rcg from rl group by 1, 2),
  ex as (
    select date_trunc('month', e.entry_date)::date as m, e.location_id, sum(public._r2_num(ln -> 'amount')) as amt
    from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) ln
    where e.form_code = '10-2' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs) group by 1, 2),
  sa as (
    select date_trunc('month', e.entry_date)::date as m, e.location_id,
           sum(coalesce(public._r2_num(r -> 'due'), 0) + coalesce(public._r2_num(r -> 'overtime'), 0) + coalesce(public._r2_num(r -> 'other'), 0)) as amt
    from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'pay') = 'array' then e.data -> 'pay' else '[]'::jsonb end) r
    where e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs) group by 1, 2),
  k as (select m, location_id from tot union select m, location_id from rt union select m, location_id from ex union select m, location_id from sa)
  select k.m, k.location_id,
         coalesce(t.rev, 0), coalesce(x.ra, 0), coalesce(t.rev, 0) - coalesce(x.ra, 0),
         round(coalesce(a.cr, 0) - coalesce(g.rcr, 0), 2), round(coalesce(a.cg, 0) - coalesce(g.rcg, 0), 2),
         e.amt, s2.amt,
         case when fm.v is not null then round(fm.v * (least(d2, (k.m + interval '1 month')::date - 1) - greatest(d1, k.m) + 1)
                / extract(day from (k.m + interval '1 month' - interval '1 day')), 2) end
  from k
  left join tot t on t.m = k.m and t.location_id = k.location_id
  left join rt x on x.m = k.m and x.location_id = k.location_id
  left join ag a on a.m = k.m and a.location_id = k.location_id
  left join rg g on g.m = k.m and g.location_id = k.location_id
  left join ex e on e.m = k.m and e.location_id = k.location_id
  left join sa s2 on s2.m = k.m and s2.location_id = k.location_id
  left join lateral (select public._r2_num(ls.value) as v from public.location_settings ls where ls.location_id = k.location_id and ls.key = 'fixed_cost_month') fm on true;
$$;
revoke all on function public._p27_pl(date, date, int[]) from public, anon, authenticated;

-- ---------- L1 profit & loss by month and shop ----------
create or replace function public._r3q_l1_pnl(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'month', to_char(p.o_m, 'YYYY-MM'), 'location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en,
    'sales', round(p.o_gross, 2), 'returns', round(p.o_ret, 2), 'net_sales', round(p.o_net, 2),
    'cogs', round(p.o_cogs, 2),
    'uncosted_pct', case when p.o_net > 0 then round(100 * greatest(p.o_net - p.o_costed, 0) / p.o_net, 2) end,
    'expenses', round(p.o_exp, 2), 'salary', round(p.o_sal, 2), 'fixed', p.o_fixed,
    'profit', round(p.o_net - p.o_cogs - coalesce(p.o_exp, 0) - coalesce(p.o_sal, 0) - coalesce(p.o_fixed, 0), 2),
    'gaps', nullif(concat_ws(', ', case when p.o_exp is null then 'expenses' end, case when p.o_sal is null then 'salary' end, case when p.o_fixed is null then 'fixed' end, case when p.o_net > 0 and p.o_costed < p.o_net then 'cogs(uncosted)' end), ''))
  from public._p27_pl(d1, d2, locs) p join public.locations l on l.id = p.o_loc;
$$;

-- ---------- L3 shop P&L comparison ----------
create or replace function public._r3q_l3_shop_pnl(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with a as (select o_loc, sum(o_net) net, sum(o_costed) costed, sum(o_cogs) cogs, sum(o_exp) ex, sum(o_sal) sal, sum(o_fixed) fx from public._p27_pl(d1, d2, locs) group by o_loc)
  select jsonb_build_object(
    'location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en,
    'net_sales', round(a.net, 2), 'cogs', round(a.cogs, 2),
    'uncosted_pct', case when a.net > 0 then round(100 * greatest(a.net - a.costed, 0) / a.net, 2) end,
    'expenses', round(a.ex, 2), 'salary', round(a.sal, 2), 'fixed', a.fx,
    'profit', round(a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0), 2),
    'profit_pct', case when a.net > 0 then round(100 * (a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0)) / a.net, 2) end,
    'gaps', nullif(concat_ws(', ', case when a.ex is null then 'expenses' end, case when a.sal is null then 'salary' end, case when a.fx is null then 'fixed' end, case when a.net > 0 and a.costed < a.net then 'cogs(uncosted)' end), ''))
  from a join public.locations l on l.id = a.o_loc;
$$;

-- ---------- L2 margin by item and by category ----------
create or replace function public._r3q_l2_margin(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with cats as (select public.rpt_arr_text(flt -> 'categories') as c),
  net_on as (select coalesce(public.rule_on('reports_net_of_returns'), true) as v),
  cst as (select ic.item_id, ic.cost_price from public.item_costs ic join public.items i on i.id = ic.item_id where i.count_in_business and ic.cost_price is not null),
  s as (select x.total, x.subtotal, x.lines from public.sales x where x.status = 'done' and x.sale_date between d1 and d2 and x.location_id = any (locs)),
  sl as (
    select 1 as sg, (case when s.subtotal > 0 then s.total / s.subtotal else 1 end) as f, e as le from s, jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e),
  rl as (
    select -1 as sg, 1::numeric as f, e as le from public.sale_returns r, net_on, jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) e
    where net_on.v and r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and r.location_id = any (locs)),
  u as (select sg, f, le from sl union all select sg, f, le from rl),
  p as (
    select sg * f as sf, sg,
           case when le->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (le->>'amount')::numeric end as amt,
           case when le->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (le->>'qty')::numeric end as qty,
           case when le->>'item_id' ~ '^[0-9a-f-]{36}$' then (le->>'item_id')::uuid end as iid
    from u),
  j as (
    select i.id as item_id, coalesce(i.code, '-') as icode, coalesce(i.name_bn, '(item not linked)') as nbn, coalesce(i.name_en, i.name_bn, '(item not linked)') as nen,
           coalesce(nullif(btrim(i.category), ''), '-') as cat, p.sf, p.sg, p.amt, p.qty, c.cost_price
    from p left join public.items i on i.id = p.iid left join cst c on c.item_id = p.iid),
  jf as (select j.* from j, cats where cats.c is null or j.cat = any (cats.c)),
  ia as (
    select item_id, icode, nbn, nen, cat, sum(sf * amt) as rev, sum(sg * qty) as qty,
           sum(sf * amt) filter (where cost_price is not null) as crev, sum(sg * qty * cost_price) filter (where cost_price is not null) as cg
    from jf group by item_id, icode, nbn, nen, cat),
  ca as (select cat, sum(rev) as rev, sum(crev) as crev, sum(cg) as cg from ia group by cat)
  select jsonb_build_object('level', 'item', 'category', ia.cat, 'item_code', ia.icode, 'item_name', ia.nbn, 'item_name_en', ia.nen,
    'qty', round(ia.qty, 3), 'revenue', round(ia.rev, 2), 'cogs', round(ia.cg, 2),
    'margin', case when ia.crev is not null then round(ia.crev - ia.cg, 2) end,
    'margin_pct', case when ia.crev > 0 then round(100 * (ia.crev - ia.cg) / ia.crev, 2) end,
    'uncosted_pct', case when ia.rev > 0 then round(100 * greatest(ia.rev - coalesce(ia.crev, 0), 0) / ia.rev, 2) end)
  from ia
  union all
  select jsonb_build_object('level', 'category', 'category', ca.cat, 'item_code', null, 'item_name', null, 'item_name_en', null,
    'qty', null, 'revenue', round(ca.rev, 2), 'cogs', round(ca.cg, 2),
    'margin', case when ca.crev is not null then round(ca.crev - ca.cg, 2) end,
    'margin_pct', case when ca.crev > 0 then round(100 * (ca.crev - ca.cg) / ca.crev, 2) end,
    'uncosted_pct', case when ca.rev > 0 then round(100 * greatest(ca.rev - coalesce(ca.crev, 0), 0) / ca.rev, 2) end)
  from ca;
$$;

-- ---------- L4 owner's monthly sheet (01-2) vs system ----------
create or replace function public._r3q_l4_owner_sheet(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with sh as (
    select e.id, e.location_id, e.entry_date, e.data ->> 'scope' as scope, btrim(e.data ->> 'month') as mon,
           public._r2_num(e.data -> 'sales') as s_sales,
           case when public._r2_num(e.data -> 'open_stock') is not null and public._r2_num(e.data -> 'purchases') is not null and public._r2_num(e.data -> 'close_stock') is not null
                then public._r2_num(e.data -> 'open_stock') + public._r2_num(e.data -> 'purchases') - public._r2_num(e.data -> 'close_stock') end as s_cogs,
           (select sum(public._r2_num(kv.value)) from jsonb_each(e.data) kv where kv.key like 'x\_%') as s_exp,
           public._r2_num(e.data -> 'salary') as s_sal, public._r2_num(e.data -> 'bank_charges') as s_bank
    from public.entries e
    where e.form_code = '01-2' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)),
  mm as (
    select sh.*, case when sh.mon ~ '^[0-9]{4}-([1-9]|0[1-9]|1[0-2])$' then to_date(sh.mon || '-01', 'YYYY-MM-DD') end as ms from sh),
  sy as (
    select mm.id, case when mm.ms is null or mm.scope not in ('all', 'loc') then false else true end as ok,
           (select array[sum(p.o_net), sum(p.o_costed), sum(p.o_cogs), sum(p.o_exp), sum(p.o_sal)] from public._p27_pl(mm.ms, (mm.ms + interval '1 month')::date - 1,
              case when mm.scope = 'all' then locs else array[mm.location_id] end) p) as v
    from mm)
  select jsonb_build_object('month', mm.mon, 'location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en, 'scope', mm.scope,
    'sheet_sales', mm.s_sales, 'sys_sales', case when sy.ok then round(sy.v[1], 2) end,
    'diff_sales', case when sy.ok and mm.s_sales is not null then round(mm.s_sales - sy.v[1], 2) end,
    'sheet_cogs', mm.s_cogs, 'sys_cogs', case when sy.ok then round(sy.v[3], 2) end,
    'sys_uncosted_pct', case when sy.ok and sy.v[1] > 0 then round(100 * greatest(sy.v[1] - sy.v[2], 0) / sy.v[1], 2) end,
    'sheet_expenses', mm.s_exp, 'sys_expenses', case when sy.ok then round(sy.v[4], 2) end,
    'diff_expenses', case when sy.ok and mm.s_exp is not null and sy.v[4] is not null then round(mm.s_exp - sy.v[4], 2) end,
    'sheet_salary', mm.s_sal, 'sys_salary', case when sy.ok then round(sy.v[5], 2) end,
    'diff_salary', case when sy.ok and mm.s_sal is not null and sy.v[5] is not null then round(mm.s_sal - sy.v[5], 2) end,
    'sheet_net', case when mm.s_sales is not null and mm.s_cogs is not null then round(mm.s_sales - mm.s_cogs - coalesce(mm.s_exp, 0) - coalesce(mm.s_sal, 0) - coalesce(mm.s_bank, 0), 2) end,
    'sys_net', case when sy.ok then round(sy.v[1] - sy.v[3] - coalesce(sy.v[4], 0) - coalesce(sy.v[5], 0), 2) end)
  from mm join sy on sy.id = mm.id join public.locations l on l.id = mm.location_id;
$$;

-- ---------- L5 break-even and cost coverage ----------
create or replace function public._r3q_l5_breakeven(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with a as (select o_loc, sum(o_net) net, sum(o_costed) costed, sum(o_cogs) cogs, sum(o_fixed) fx from public._p27_pl(d1, d2, locs) group by o_loc),
  b as (select a.*, case when a.costed > 0 and a.costed - a.cogs > 0 then (a.costed - a.cogs) / a.costed end as gm,
          (select public._r2_num(ls.value) from public.location_settings ls where ls.location_id = a.o_loc and ls.key = 'fixed_cost_month') as fm from a)
  select jsonb_build_object('location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en,
    'net_sales', round(b.net, 2),
    'uncosted_pct', case when b.net > 0 then round(100 * greatest(b.net - b.costed, 0) / b.net, 2) end,
    'gm_pct', case when b.gm is not null then round(100 * b.gm, 2) end,
    'fixed', b.fx,
    'be_sales', case when b.gm is not null and b.fx is not null then round(b.fx / b.gm, 2) end,
    'gap', case when b.gm is not null and b.fx is not null then round(b.net - b.fx / b.gm, 2) end,
    'coverage_pct', case when b.gm is not null and b.fx > 0 then round(100 * b.net / (b.fx / b.gm), 2) end,
    'fixed_month', b.fm,
    'be_month', case when b.gm is not null and b.fm is not null then round(b.fm / b.gm, 2) end)
  from b join public.locations l on l.id = b.o_loc;
$$;

-- ---------- T3 payroll & advances (02-2 salary sheets, 02-3 advance register) ----------
create or replace function public._r3q_t3_payroll(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with pay as (
    select e.id, e.location_id, btrim(r ->> 'name') as nm,
           coalesce(public._r2_num(r -> 'due'), 0) + coalesce(public._r2_num(r -> 'overtime'), 0) + coalesce(public._r2_num(r -> 'other'), 0) as gross,
           coalesce(public._r2_num(r -> 'adv_ded'), 0) as adv_ded, coalesce(public._r2_num(r -> 'other_ded'), 0) as oth_ded
    from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'pay') = 'array' then e.data -> 'pay' else '[]'::jsonb end) r
    where e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)
      and btrim(coalesce(r ->> 'name', '')) <> ''),
  pg as (select location_id, lower(nm) as k, min(nm) as nm, count(distinct id) as sheets, sum(gross) as gross, sum(adv_ded) as adv_ded, sum(oth_ded) as oth_ded from pay group by 1, 2),
  av as (
    select e.location_id, lower(btrim(e.data ->> 'staff')) as k, min(btrim(e.data ->> 'staff')) as nm,
           sum(public._r2_num(r -> 'amount')) as given, sum(public._r2_num(r -> 'ded_now')) as ded_now
    from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'adv') = 'array' then e.data -> 'adv' else '[]'::jsonb end) r
    where e.form_code = '02-3' and e.status in ('submitted', 'approved') and e.location_id = any (locs) and btrim(coalesce(e.data ->> 'staff', '')) <> ''
      and coalesce(case when r ->> 'date' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then (r ->> 'date')::date end, e.entry_date) between d1 and d2
    group by 1, 2),
  ob as (
    select distinct on (e.location_id, lower(btrim(e.data ->> 'staff'))) e.location_id, lower(btrim(e.data ->> 'staff')) as k, btrim(e.data ->> 'staff') as nm,
           (select sum(public._r2_num(r -> 'balance')) from jsonb_array_elements(case when jsonb_typeof(e.data -> 'adv') = 'array' then e.data -> 'adv' else '[]'::jsonb end) r) as outstanding
    from public.entries e
    where e.form_code = '02-3' and e.status in ('submitted', 'approved') and e.location_id = any (locs) and btrim(coalesce(e.data ->> 'staff', '')) <> '' and e.entry_date <= d2
    order by e.location_id, lower(btrim(e.data ->> 'staff')), e.entry_date desc, e.created_at desc),
  ks as (select location_id, k from pg union select location_id, k from av union select location_id, k from ob)
  select jsonb_build_object('location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en,
    'person', coalesce(pg.nm, av.nm, ob.nm), 'sheets', pg.sheets,
    'gross_pay', round(pg.gross, 2), 'adv_deducted', round(pg.adv_ded, 2), 'other_deducted', round(pg.oth_ded, 2),
    'net_pay', round(pg.gross - pg.adv_ded - pg.oth_ded, 2),
    'adv_given', round(av.given, 2), 'adv_register_deduction', round(av.ded_now, 2), 'adv_outstanding', round(ob.outstanding, 2))
  from ks join public.locations l on l.id = ks.location_id
  left join pg on pg.location_id = ks.location_id and pg.k = ks.k
  left join av on av.location_id = ks.location_id and av.k = ks.k
  left join ob on ob.location_id = ks.location_id and ob.k = ks.k;
$$;

-- ---------- T4 staff cost / sales % by shop ----------
create or replace function public._r3q_t4_staff_cost_ratio(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with a as (select o_loc, sum(o_net) net, sum(o_sal) sal from public._p27_pl(d1, d2, locs) group by o_loc)
  select jsonb_build_object('location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en,
    'net_sales', round(a.net, 2), 'salary', round(a.sal, 2),
    'salary_pct', case when a.net > 0 and a.sal is not null then round(100 * a.sal / a.net, 2) end)
  from a join public.locations l on l.id = a.o_loc;
$$;

-- ---------- registry ----------
insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('l1_pnl', 'L1', 'profit', 'লাভ-ক্ষতি (মাস ও দোকান অনুযায়ী)', 'Profit & loss by month and shop', 'লাভ-ক্ষতি (P&L)',
  '[["month","মাস","Month","text"],["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],
    ["sales","বিক্রি (সম্পন্ন বিক্রি)","Sales (done sales)","money"],["returns","রিটার্ন (বিক্রি-রিটার্ন)","Returns (sale returns)","money"],["net_sales","নিট বিক্রি","Net sales","money"],
    ["cogs","মালের খরচ (শুধু খরচ-ধরা লাইন; আইটেম খরচ)","COGS (costed lines only; item costs)","money"],["uncosted_pct","খরচ-ছাড়া বিক্রির %","Uncosted sales %","pct"],
    ["expenses","ব্যয় (ভাউচার ১০-২)","Expenses (voucher 10-2)","money"],["salary","বেতন (বেতন শিট ০২-২)","Salary (salary sheet 02-2)","money"],
    ["fixed","স্থির খরচ (লোকেশন সেটিং, দিন অনুপাতে)","Fixed cost (location setting, pro rata)","money"],["profit","লাভ / (ক্ষতি)","Profit / (loss)","money"],["gaps","যা পাওয়া যায়নি","Missing inputs","text"]]'::jsonb,
  array['sales','returns','net_sales','cogs','expenses','salary','fixed','profit'], 'month', 'desc', array['locations','brands'], false, true, true, 270),
 ('l2_margin', 'L2', 'profit', 'আইটেম ও ক্যাটাগরি মার্জিন', 'Margin by item and category', 'আইটেম / Category margin',
  '[["level","স্তর","Level","text"],["category","ক্যাটাগরি","Category","text"],["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],
    ["qty","পরিমাণ","Qty","num"],["revenue","বিক্রি (রিটার্ন বাদে)","Sales (net of returns)","money"],["cogs","মালের খরচ (খরচ-ধরা লাইন)","COGS (costed lines)","money"],
    ["margin","মার্জিন (খরচ-ধরা লাইনে)","Margin (costed lines)","money"],["margin_pct","মার্জিন %","Margin %","pct"],["uncosted_pct","খরচ-ছাড়া বিক্রির %","Uncosted sales %","pct"]]'::jsonb,
  '{}', 'revenue', 'desc', array['locations','brands','categories'], false, true, false, 271),
 ('l3_shop_pnl', 'L3', 'profit', 'দোকান P&L তুলনা', 'Shop P&L comparison', 'দোকান P&L তুলনা',
  '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["net_sales","নিট বিক্রি","Net sales","money"],
    ["cogs","মালের খরচ (খরচ-ধরা লাইন)","COGS (costed lines)","money"],["uncosted_pct","খরচ-ছাড়া বিক্রির %","Uncosted sales %","pct"],["expenses","ব্যয় (১০-২)","Expenses (10-2)","money"],
    ["salary","বেতন (০২-২)","Salary (02-2)","money"],["fixed","স্থির খরচ","Fixed cost","money"],["profit","লাভ / (ক্ষতি)","Profit / (loss)","money"],["profit_pct","লাভ %","Profit %","pct"],["gaps","যা পাওয়া যায়নি","Missing inputs","text"]]'::jsonb,
  array['net_sales','cogs','expenses','salary','fixed','profit'], 'profit_pct', 'asc', array['locations','brands'], false, true, true, 272),
 ('l4_owner_sheet', 'L4', 'profit', 'মালিকের মাসিক শিট বনাম সিস্টেম', 'Owner monthly sheet vs system', 'মালিকের শিট (01-2) vs system',
  '[["month","মাস","Month","text"],["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["scope","পরিধি","Scope","text"],
    ["sheet_sales","শিট: বিক্রি","Sheet: sales","money"],["sys_sales","সিস্টেম: নিট বিক্রি","System: net sales","money"],["diff_sales","পার্থক্য: বিক্রি","Diff: sales","money"],
    ["sheet_cogs","শিট: মালের খরচ (শুরু+ক্রয়−শেষ)","Sheet: COGS (open+purch−close)","money"],["sys_cogs","সিস্টেম: মালের খরচ (খরচ-ধরা লাইন)","System: COGS (costed lines)","money"],["sys_uncosted_pct","সিস্টেম: খরচ-ছাড়া বিক্রি %","System: uncosted sales %","pct"],
    ["sheet_expenses","শিট: ব্যয়","Sheet: expenses","money"],["sys_expenses","সিস্টেম: ব্যয় (১০-২)","System: expenses (10-2)","money"],["diff_expenses","পার্থক্য: ব্যয়","Diff: expenses","money"],
    ["sheet_salary","শিট: বেতন","Sheet: salary","money"],["sys_salary","সিস্টেম: বেতন (০২-২)","System: salary (02-2)","money"],["diff_salary","পার্থক্য: বেতন","Diff: salary","money"],
    ["sheet_net","শিট: নিট লাভ","Sheet: net profit","money"],["sys_net","সিস্টেম: নিট লাভ (স্থির খরচ ছাড়া)","System: net profit (before fixed cost)","money"]]'::jsonb,
  '{}', 'month', 'desc', array['locations','brands'], false, true, true, 273),
 ('l5_breakeven', 'L5', 'profit', 'ব্রেক-ইভেন ও খরচ কভারেজ', 'Break-even and cost coverage', 'Break-even ও cost coverage',
  '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["net_sales","নিট বিক্রি","Net sales","money"],
    ["uncosted_pct","খরচ-ছাড়া বিক্রির %","Uncosted sales %","pct"],["gm_pct","গ্রস মার্জিন % (খরচ-ধরা লাইনে)","Gross margin % (costed lines)","pct"],["fixed","স্থির খরচ (সময়ের জন্য)","Fixed cost (for the period)","money"],
    ["be_sales","ব্রেক-ইভেন বিক্রি (সময়ের)","Break-even sales (period)","money"],["gap","বিক্রি − ব্রেক-ইভেন","Sales − break-even","money"],["coverage_pct","কভারেজ %","Coverage %","pct"],
    ["fixed_month","মাসিক স্থির খরচ","Monthly fixed cost","money"],["be_month","মাসিক ব্রেক-ইভেন বিক্রি","Monthly break-even sales","money"]]'::jsonb,
  array['net_sales','fixed','be_sales'], 'coverage_pct', 'asc', array['locations','brands'], false, true, false, 274),
 ('t3_payroll', 'T3', 'profit', 'বেতন ও অ্যাডভান্স', 'Payroll and advances', 'বেতন ও Advance',
  '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["person","কর্মী (নাম মিলিয়ে)","Person (matched by name)","text"],["sheets","বেতন শিট","Salary sheets","int"],
    ["gross_pay","মোট পাওনা (০২-২)","Total due (02-2)","money"],["adv_deducted","অ্যাডভান্স কর্তন (০২-২)","Advance deducted (02-2)","money"],["other_deducted","অন্য কর্তন","Other deduction","money"],["net_pay","নিট বেতন","Net pay","money"],
    ["adv_given","অ্যাডভান্স দেওয়া (০২-৩)","Advance given (02-3)","money"],["adv_register_deduction","রেজিস্টারে কর্তন (০২-৩)","Deduction in register (02-3)","money"],["adv_outstanding","বকেয়া অ্যাডভান্স (০২-৩, সর্বশেষ পাতা)","Advance outstanding (02-3, latest page)","money"]]'::jsonb,
  array['gross_pay','adv_deducted','other_deducted','net_pay','adv_given','adv_register_deduction','adv_outstanding'], 'net_pay', 'desc', array['locations','brands'], false, false, true, 275),
 ('t4_staff_cost_ratio', 'T4', 'profit', 'স্টাফ খরচ ÷ বিক্রি', 'Staff cost / sales %', 'Staff খরচ ÷ বিক্রি %',
  '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["net_sales","নিট বিক্রি","Net sales","money"],["salary","বেতন (০২-২)","Salary (02-2)","money"],["salary_pct","বেতন ÷ বিক্রি %","Salary ÷ sales %","pct"]]'::jsonb,
  array['net_sales','salary'], 'salary_pct', 'desc', array['locations','brands'], false, false, true, 276)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix,
  cols = excluded.cols, tot = excluded.tot, sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate,
  cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

select public._r3_lockdown();

-- ---------------------------------------------------------------- phase28.sql
-- ============================================================
-- PHASE 28 (groups C+D): parallel-month comparison (pairs, daily rows, month-end Pass / Fail), Print & books (paper book register, print notes),
--   "Needs you" oldest-first list. Additive and idempotent (paste twice = no error). Needs phase17 (form_rollout, rollout_set) and phase8.
--   * comparison_pairs: named by the OWNER (created empty - nothing is invented). comparison_days: one row per pair x place x day, the keeper writes the paper figure,
--     another person the app figure; the same person cannot do both on a row; result match / differ / waiting is computed.
--   * parallel_month_decide(form, place, month, pass, note): owner only, after the month has ended. Pass needs at least one comparison day, none waiting, every differ with a
--     reason and a fix; it then sets the form x place to 'app' (rollout_set) and records the decision. Fail records why; the form stays parallel.
--   * paper_books: first / last serial of each printed book per form x place; paper_books_check() lists gaps and overlaps; print_notes: what to change at the next print
--     (created when a place is renamed or closed, or by hand), cleared only by recording the new print (date + who).
--   * needs_you_oldest(limit): the oldest waiting things the caller may decide, oldest first.
-- Nothing is hard-deleted. Settings switches: rules parallel_compare_on (ON) and print_notes_auto (ON).
-- ============================================================

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('parallel_compare_on', 'entries', 'switch', 'true', null, null, null, null, 'পাশাপাশি মাস: দৈনিক তুলনা ও মাস-শেষের পাস/ফেল', 'Parallel মাস: daily comparison ও month-end pass/fail', 'Parallel month: daily comparison and month-end pass / fail',
  'বন্ধ করলে মাস-শেষে পাস/ফেল ছাড়াই মালিক নিজে কাগজ→অ্যাপ বদলাতে পারবেন (আগের মতো)।', 'Off = the owner can move paper→app without the month-end pass / fail (as before).', 90),
 ('smart_defaults_on', 'entries', 'switch', 'true', null, null, null, null, 'নতুন ফর্মে "আগেরটা থেকে নিন" বোতাম', 'নতুন form-এ "আগেরটা থেকে নিন" button', 'A "Start from my last one" button on a new form',
  'আগের এন্ট্রি থেকে শুধু আইটেম, সরবরাহকারী ও পছন্দের ঘর নেয়; কোনো পরিমাণ, টাকা, তারিখ বা সই নেয় না।', 'Copies only items, suppliers and choices from your last entry - never quantities, money, dates, signatures or photos.', 92),
 ('offline_cache_on', 'ui', 'switch', 'true', null, null, null, null, 'ইন্টারনেট ছাড়া অ্যাপ খোলা (ফোনে সংরক্ষণ)', 'Internet ছাড়া app খোলা (phone-এ cache)', 'Open the app without internet (cached on the phone)',
  'বন্ধ করলে ফোন থেকে সংরক্ষিত কপি মুছে যায়; অ্যাপ আগের মতো ইন্টারনেট লাগবে।', 'Off = the saved copy is removed from the phone; the app needs internet to start, as before.', 93),
 ('print_notes_auto', 'settings', 'switch', 'true', null, null, null, null, 'জায়গার নাম বদল/বন্ধে ছাপার নোট নিজে হবে', 'জায়গার নাম বদল/বন্ধে print note নিজে হবে', 'Print note is made when a place is renamed or closed',
  'পরের ছাপায় কী বদলাতে হবে তার নোট। ছাপার তারিখ লেখা না হওয়া পর্যন্ত নোট থাকে।', 'A note of what to change at the next print; it stays until the new print is recorded.', 91)
 on conflict (key) do nothing;

-- ---------- parallel comparison ----------
create table if not exists public.comparison_pairs (
  id bigserial primary key,
  form_code text not null references public.forms(code),
  name_bn text not null, name_en text,
  how_paper text, how_app text,                     -- how each figure is read, in words (the owner defines them)
  is_active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now()
);
create table if not exists public.comparison_days (
  id bigserial primary key,
  pair_id bigint not null references public.comparison_pairs(id),
  form_code text not null references public.forms(code),
  location_id int not null references public.locations(id),
  day date not null,
  paper_value numeric check (paper_value is null or abs(paper_value) <= 1000000000000),
  app_value numeric check (app_value is null or abs(app_value) <= 1000000000000),
  result text not null default 'waiting' check (result in ('match', 'differ', 'waiting')),
  reason text, fix text,
  keeper_user uuid, enterer_user uuid,
  keeper_at timestamptz, enterer_at timestamptz,
  unique (pair_id, location_id, day),
  check (keeper_user is null or enterer_user is null or keeper_user <> enterer_user)
);
create table if not exists public.parallel_months (
  form_code text not null references public.forms(code),
  location_id int not null references public.locations(id),
  month date not null,                              -- first day of the month
  result text not null check (result in ('pass', 'fail')),
  note text, days int, differ int,
  decided_by uuid, decided_at timestamptz not null default now(),
  primary key (form_code, location_id, month)
);
do $$ declare t text; begin
  foreach t in array array['comparison_pairs', 'comparison_days', 'parallel_months'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_active()%s)', t || '_read', t, case when t = 'comparison_days' or t = 'parallel_months' then ' and public.can_loc(location_id)' else '' end);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop trigger if exists %I on public.%I', 'audit_' || t, t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.log_change(%L)', 'audit_' || t, t, case when t = 'parallel_months' then 'form_code,location_id,month' else 'id' end);
    execute format('drop trigger if exists %I on public.%I', t || '_no_delete', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_no_delete', t);
  end loop;
end $$;

create or replace function public._par_mgr() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('rollout_manage'));
$$;

create or replace function public.comparison_pair_save(p_form text, p_name_bn text, p_name_en text default null, p_how_paper text default null, p_how_app text default null,
  p_id bigint default null, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare nid bigint;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_name_bn is null or length(btrim(p_name_bn)) < 2 then raise exception 'name_required'; end if;
  if not exists (select 1 from public.forms where code = p_form) then raise exception 'form_not_found'; end if;
  if p_id is null then
    insert into public.comparison_pairs (form_code, name_bn, name_en, how_paper, how_app, is_active, created_by)
      values (p_form, left(btrim(p_name_bn), 120), left(nullif(btrim(p_name_en), ''), 120), left(nullif(btrim(p_how_paper), ''), 300), left(nullif(btrim(p_how_app), ''), 300), coalesce(p_active, true), auth.uid()) returning id into nid;
  else
    update public.comparison_pairs set name_bn = left(btrim(p_name_bn), 120), name_en = left(nullif(btrim(p_name_en), ''), 120), how_paper = left(nullif(btrim(p_how_paper), ''), 300),
      how_app = left(nullif(btrim(p_how_app), ''), 300), is_active = coalesce(p_active, true) where id = p_id and form_code = p_form returning id into nid;
    if nid is null then raise exception 'not_found'; end if;
  end if;
  return jsonb_build_object('id', nid);
end $$;

-- the keeper writes the paper figure, someone else the app figure; role = 'paper' | 'app'
create or replace function public.comparison_record(p_pair bigint, p_loc int, p_day date, p_role text, p_value numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pr public.comparison_pairs; r public.comparison_days; today date := (now() at time zone 'Asia/Dhaka')::date;
begin
  if not public.is_active() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if p_role not in ('paper', 'app') then raise exception 'bad_role'; end if;
  if p_value is null or abs(p_value) > 1000000000000 then raise exception 'bad_amount'; end if;
  if p_day is null or p_day > today or p_day < today - 62 then raise exception 'bad_date'; end if;
  select * into pr from public.comparison_pairs where id = p_pair and is_active;
  if not found then raise exception 'pair_not_found'; end if;
  if public.rollout_mode(pr.form_code, p_loc) is distinct from 'parallel' then raise exception 'not_parallel'; end if;
  if exists (select 1 from public.parallel_months m where m.form_code = pr.form_code and m.location_id = p_loc and m.month = date_trunc('month', p_day)::date) then raise exception 'month_decided'; end if;
  if not (public.is_owner() or public.can_do(pr.form_code, 'enter') or public.can_do(pr.form_code, 'approve') or public.has_grant('rollout_manage', p_loc)) then raise exception 'not allowed'; end if;
  insert into public.comparison_days (pair_id, form_code, location_id, day) values (p_pair, pr.form_code, p_loc, p_day) on conflict (pair_id, location_id, day) do nothing;
  select * into r from public.comparison_days where pair_id = p_pair and location_id = p_loc and day = p_day for update;
  if p_role = 'paper' then
    if r.enterer_user = auth.uid() then raise exception 'keeper_is_enterer'; end if;
    if r.paper_value is not null and r.keeper_user is distinct from auth.uid() then raise exception 'already_recorded'; end if;
    update public.comparison_days set paper_value = round(p_value, 4), keeper_user = auth.uid(), keeper_at = now() where id = r.id;
  else
    if r.keeper_user = auth.uid() then raise exception 'keeper_is_enterer'; end if;
    if r.app_value is not null and r.enterer_user is distinct from auth.uid() then raise exception 'already_recorded'; end if;
    update public.comparison_days set app_value = round(p_value, 4), enterer_user = auth.uid(), enterer_at = now() where id = r.id;
  end if;
  update public.comparison_days set result = case when paper_value is null or app_value is null then 'waiting' when abs(paper_value - app_value) < 0.005 then 'match' else 'differ' end
    where id = r.id returning * into r;
  return jsonb_build_object('id', r.id, 'result', r.result);
end $$;

create or replace function public.comparison_explain(p_id bigint, p_reason text, p_fix text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.comparison_days;
begin
  select * into r from public.comparison_days where id = p_id for update;
  if not found or not public.can_loc(r.location_id) then raise exception 'not allowed'; end if;
  if not (public.is_owner() or public.has_grant('rollout_manage', r.location_id) or r.keeper_user = auth.uid() or r.enterer_user = auth.uid()) then raise exception 'not allowed'; end if;
  if r.result <> 'differ' then raise exception 'not_differ'; end if;
  if exists (select 1 from public.parallel_months m where m.form_code = r.form_code and m.location_id = r.location_id and m.month = date_trunc('month', r.day)::date) then raise exception 'month_decided'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 or p_fix is null or length(btrim(p_fix)) < 3 then raise exception 'reason_and_fix_required'; end if;
  update public.comparison_days set reason = left(btrim(p_reason), 300), fix = left(btrim(p_fix), 300) where id = r.id;
  return jsonb_build_object('id', r.id);
end $$;

create or replace function public.parallel_month_status(p_form text, p_loc int, p_month date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m date := date_trunc('month', coalesce(p_month, (now() at time zone 'Asia/Dhaka')::date))::date; today date := (now() at time zone 'Asia/Dhaka')::date;
        n int; mt int; df int; dfx int; wt int; pairs int; dec public.parallel_months; ended boolean;
begin
  if not public.is_active() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  select count(*) into pairs from public.comparison_pairs where form_code = p_form and is_active;
  select count(*), count(*) filter (where result = 'match'), count(*) filter (where result = 'differ'), count(*) filter (where result = 'differ' and nullif(btrim(coalesce(reason, '')), '') is not null and nullif(btrim(coalesce(fix, '')), '') is not null),
         count(*) filter (where result = 'waiting')
    into n, mt, df, dfx, wt from public.comparison_days where form_code = p_form and location_id = p_loc and day >= m and day < (m + interval '1 month')::date;
  select * into dec from public.parallel_months where form_code = p_form and location_id = p_loc and month = m;
  ended := (m + interval '1 month')::date <= today;
  return jsonb_build_object('form', p_form, 'location_id', p_loc, 'month', m, 'mode', public.rollout_mode(p_form, p_loc), 'pairs', pairs, 'days', n, 'match', mt, 'differ', df, 'differ_explained', dfx, 'waiting', wt,
    'month_ended', ended, 'decision', case when dec.form_code is null then null else jsonb_build_object('result', dec.result, 'note', dec.note, 'at', dec.decided_at) end,
    'pass_ready', ended and pairs > 0 and n > 0 and wt = 0 and df = dfx and dec.form_code is null);
end $$;

create or replace function public.parallel_month_decide(p_form text, p_loc int, p_month date, p_pass boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m date := date_trunc('month', p_month)::date; st jsonb; today date := (now() at time zone 'Asia/Dhaka')::date;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_pass is null then raise exception 'bad_value'; end if;
  if public.rollout_mode(p_form, p_loc) is distinct from 'parallel' then raise exception 'not_parallel'; end if;
  if (m + interval '1 month')::date > today then raise exception 'month_not_ended'; end if;
  if exists (select 1 from public.parallel_months where form_code = p_form and location_id = p_loc and month = m) then raise exception 'already_decided'; end if;
  if not p_pass and (p_note is null or length(btrim(p_note)) < 3) then raise exception 'note_required'; end if;
  st := public.parallel_month_status(p_form, p_loc, m);
  if p_pass and public.rule_on('parallel_compare_on') then
    if (st ->> 'pairs')::int = 0 then raise exception 'no_pair_named'; end if;
    if (st ->> 'days')::int = 0 then raise exception 'no_comparison_days'; end if;
    if (st ->> 'waiting')::int > 0 then raise exception 'days_waiting'; end if;
    if (st ->> 'differ')::int <> (st ->> 'differ_explained')::int then raise exception 'differ_without_reason'; end if;
  end if;
  insert into public.parallel_months (form_code, location_id, month, result, note, days, differ, decided_by)
    values (p_form, p_loc, m, case when p_pass then 'pass' else 'fail' end, left(nullif(btrim(p_note), ''), 300), (st ->> 'days')::int, (st ->> 'differ')::int, auth.uid());
  if p_pass then perform public.rollout_set(p_form, p_loc, 'app', 'parallel month ' || to_char(m, 'YYYY-MM') || ' passed'); end if;
  return jsonb_build_object('result', case when p_pass then 'pass' else 'fail' end, 'month', m);
end $$;

-- forms x places that are in parallel and whose last full month still has no decision (the owner's waiting list)
create or replace function public.parallel_waiting() returns table (form_code text, location_id int, month date)
language sql stable security definer set search_path = public as $$
  select r.form_code, r.location_id, (date_trunc('month', (now() at time zone 'Asia/Dhaka')::date) - interval '1 month')::date
    from public.form_rollout r
   where r.mode = 'parallel' and public.is_owner() and public.rule_on('parallel_compare_on')
     and exists (select 1 from public.comparison_days d where d.form_code = r.form_code and d.location_id = r.location_id
                   and d.day >= (date_trunc('month', (now() at time zone 'Asia/Dhaka')::date) - interval '1 month')::date and d.day < date_trunc('month', (now() at time zone 'Asia/Dhaka')::date)::date)
     and not exists (select 1 from public.parallel_months p where p.form_code = r.form_code and p.location_id = r.location_id
                   and p.month = (date_trunc('month', (now() at time zone 'Asia/Dhaka')::date) - interval '1 month')::date);
$$;

-- ---------- print & books ----------
create table if not exists public.paper_books (
  id bigserial primary key,
  form_code text not null references public.forms(code),
  location_id int not null references public.locations(id),
  prefix text, first_no bigint not null check (first_no >= 0), last_no bigint not null,
  issued_on date, holder text, note text,
  status text not null default 'active' check (status in ('active', 'used', 'void')),
  created_by uuid, created_at timestamptz not null default now(),
  check (last_no >= first_no)
);
create index if not exists paper_books_fl on public.paper_books (form_code, location_id, first_no);
create table if not exists public.print_notes (
  id bigserial primary key,
  form_code text references public.forms(code),   -- null = every printed form that carries a place line
  location_id int not null references public.locations(id),
  reason text not null, change_to text,
  created_by uuid, created_at timestamptz not null default now(),
  cleared_on date, cleared_by uuid, cleared_at timestamptz
);
do $$ declare t text; begin
  foreach t in array array['paper_books', 'print_notes'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_owner() or public.has_grant(%L) or public.has_grant(%L, location_id))', t || '_read', t, 'head_management', 'print_books');
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop trigger if exists %I on public.%I', 'audit_' || t, t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.log_change(%L)', 'audit_' || t, t, 'id');
    execute format('drop trigger if exists %I on public.%I', t || '_no_delete', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_no_delete', t);
  end loop;
end $$;
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'print_books', 'master', 64, 'ছাপা ও বই: সিরিয়াল ও ছাপার নোট লেখা', 'Print ও books: serial ও print note লেখা', 'Print & books: record serials and print notes', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'print_books');

create or replace function public._books_mgr(p_loc int default null) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('head_management') or public.has_grant('print_books', p_loc));
$$;

create or replace function public.paper_book_add(p_form text, p_loc int, p_first bigint, p_last bigint, p_prefix text default null, p_issued date default null, p_holder text default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare nid bigint; ov record;
begin
  if not public._books_mgr(p_loc) or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.forms where code = p_form) or not exists (select 1 from public.locations where id = p_loc) then raise exception 'not_found'; end if;
  if p_first is null or p_last is null or p_first < 0 or p_last < p_first or p_last > 999999999999 then raise exception 'bad_range'; end if;
  select * into ov from public.paper_books b where b.form_code = p_form and b.location_id = p_loc and b.status <> 'void' and coalesce(b.prefix, '') = coalesce(nullif(btrim(p_prefix), ''), '') and p_first <= b.last_no and p_last >= b.first_no limit 1;
  if found then raise exception 'books_overlap' using detail = ov.first_no::text || '-' || ov.last_no::text; end if;
  insert into public.paper_books (form_code, location_id, prefix, first_no, last_no, issued_on, holder, note, created_by)
    values (p_form, p_loc, nullif(btrim(p_prefix), ''), p_first, p_last, p_issued, left(nullif(btrim(p_holder), ''), 80), left(nullif(btrim(p_note), ''), 300), auth.uid()) returning id into nid;
  return jsonb_build_object('id', nid);
end $$;

create or replace function public.paper_book_set_status(p_id bigint, p_status text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b public.paper_books;
begin
  select * into b from public.paper_books where id = p_id for update;
  if not found or not public._books_mgr(b.location_id) or not public.can_loc(b.location_id) then raise exception 'not allowed'; end if;
  if p_status not in ('active', 'used', 'void') then raise exception 'bad_value'; end if;
  if p_status = 'void' and (p_note is null or length(btrim(p_note)) < 3) then raise exception 'note_required'; end if;
  if p_status <> 'void' and b.status = 'void' and exists (select 1 from public.paper_books o where o.id <> b.id and o.form_code = b.form_code and o.location_id = b.location_id and o.status <> 'void' and coalesce(o.prefix, '') = coalesce(b.prefix, '') and b.first_no <= o.last_no and b.last_no >= o.first_no) then raise exception 'books_overlap'; end if;
  update public.paper_books set status = p_status, note = coalesce(left(nullif(btrim(p_note), ''), 300), note) where id = p_id;
  return jsonb_build_object('id', p_id, 'status', p_status);
end $$;

-- gaps and overlaps between the books of one form x place, and the first serial the app may use next
create or replace function public.paper_books_check(p_form text, p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare prev public.paper_books; b public.paper_books; issues jsonb := '[]'::jsonb; mx bigint;
begin
  if not public._books_mgr(p_loc) or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  for b in select * from public.paper_books where form_code = p_form and location_id = p_loc and status <> 'void' order by coalesce(prefix, ''), first_no loop
    if prev.id is not null and coalesce(prev.prefix, '') = coalesce(b.prefix, '') then
      if b.first_no <= prev.last_no then issues := issues || jsonb_build_array(jsonb_build_object('type', 'overlap', 'from', prev.last_no, 'to', b.first_no));
      elsif b.first_no > prev.last_no + 1 then issues := issues || jsonb_build_array(jsonb_build_object('type', 'gap', 'from', prev.last_no + 1, 'to', b.first_no - 1)); end if;
    end if;
    prev := b;
  end loop;
  select max(last_no) into mx from public.paper_books where form_code = p_form and location_id = p_loc and status <> 'void';
  return jsonb_build_object('issues', issues, 'last_paper_no', mx, 'app_continues_from', case when mx is null then null else mx + 1 end);
end $$;

create or replace function public.print_note_add(p_loc int, p_form text, p_reason text, p_change text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare nid bigint;
begin
  if not public._books_mgr(p_loc) or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if p_form is not null and not exists (select 1 from public.forms where code = p_form) then raise exception 'form_not_found'; end if;
  insert into public.print_notes (form_code, location_id, reason, change_to, created_by) values (p_form, p_loc, left(btrim(p_reason), 300), left(nullif(btrim(p_change), ''), 300), auth.uid()) returning id into nid;
  return jsonb_build_object('id', nid);
end $$;

create or replace function public.print_note_clear(p_id bigint, p_printed_on date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n public.print_notes;
begin
  select * into n from public.print_notes where id = p_id for update;
  if not found or not public._books_mgr(n.location_id) or not public.can_loc(n.location_id) then raise exception 'not allowed'; end if;
  if n.cleared_at is not null then return jsonb_build_object('id', n.id, 'dup', true); end if;
  if p_printed_on is null or p_printed_on > (now() at time zone 'Asia/Dhaka')::date + 1 or p_printed_on < date '2000-01-01' then raise exception 'bad_date'; end if;
  update public.print_notes set cleared_on = p_printed_on, cleared_by = auth.uid(), cleared_at = now() where id = n.id;
  return jsonb_build_object('id', n.id);
end $$;

-- a place renamed or closed -> one note (null form = every printed form with a place line)
create or replace function public._loc_print_note() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.rule_on('print_notes_auto') then return new; end if;
  if new.name_bn is distinct from old.name_bn or new.name_en is distinct from old.name_en or new.name_mix is distinct from old.name_mix then
    insert into public.print_notes (form_code, location_id, reason, change_to, created_by)
      values (null, new.id, 'place renamed: ' || coalesce(old.name_bn, '') || ' -> ' || coalesce(new.name_bn, ''), 'Change the place line at the next print', auth.uid());
  end if;
  if new.status is distinct from old.status and new.status = 'closed' then
    insert into public.print_notes (form_code, location_id, reason, change_to, created_by) values (null, new.id, 'place closed: ' || coalesce(new.name_bn, ''), 'Remove the place from the next print', auth.uid());
  end if;
  return new;
end $$;
drop trigger if exists locations_print_note on public.locations;
create trigger locations_print_note after update on public.locations for each row execute function public._loc_print_note();

-- ---------- Needs you: the oldest waiting things the caller may decide ----------
create or replace function public.needs_you_oldest(p_limit int default 8) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb; lim int := least(greatest(coalesce(p_limit, 8), 1), 30);
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.since), '[]'::jsonb) into out_ from (
    select * from (
      select 'entry'::text kind, e.id::text id, e.form_code || ' #' || coalesce(e.serial::text, '') as label, e.location_id, coalesce(e.submitted_at, e.created_at) as since, ('entry/' || e.id)::text as route
        from public.entries e where e.status = 'submitted' and public.can_loc(e.location_id) and (public.is_owner() or public.can_do(e.form_code, 'approve')) and e.created_by is distinct from auth.uid()
      union all
      select 'release', r.id::text, r.flag_code, (select en.location_id from public.entries en where en.id = r.entry_id), r.requested_at, 'releases'
        from public.release_requests r where r.status = 'pending' and public._release_can_see(r.entry_id)
      union all
      select 'emergency', q.id::text, q.grant_code, q.location_id, q.created_at, 'emergency' from public.emergency_requests q where q.status = 'pending' and public.is_owner()
      union all
      select 'item_change', c.id::text, 'item change', null::int, c.requested_at, 'itemreq' from public.item_changes c where c.status = 'pending' and (public.is_owner() or public.has_grant('item_create') or public.can_do('ITEMS', 'approve'))
      union all
      select 'staff', p.id::text, coalesce(p.full_name, p.staff_id), null::int, p.created_at, 'staff' from public.profiles p where p.status = 'pending' and public.is_owner()
      union all
      select 'wastage', w.id::text, 'wastage', w.location_id, w.requested_at, 'stock' from public.wastage_requests w where w.status = 'pending' and public.can_loc(w.location_id) and public.has_grant('wastage_approve', w.location_id) and w.requested_by is distinct from auth.uid()
      union all
      select 'parallel', pw.form_code || ':' || pw.location_id, pw.form_code || ' ' || to_char(pw.month, 'YYYY-MM'), pw.location_id, (pw.month + interval '1 month')::timestamptz, 'parallel' from public.parallel_waiting() pw
    ) u where u.since is not null order by u.since limit lim
  ) x;
  return out_;
end $$;


-- ---------- guided flows: a skipped step is recorded with a note (never silently ticked) ----------
create table if not exists public.flow_skips (
  id bigserial primary key,
  flow text not null check (flow ~ '^[a-z_]{2,30}$'), step text not null check (step ~ '^[a-z0-9_]{1,40}$'),
  location_id int references public.locations(id), day date not null,
  note text not null check (length(btrim(note)) >= 3),
  created_by uuid not null, created_staff text, created_at timestamptz not null default now(),
  unique (flow, step, location_id, day, created_by)
);
alter table public.flow_skips enable row level security;
drop policy if exists flow_skips_read on public.flow_skips;
create policy flow_skips_read on public.flow_skips for select to authenticated using (created_by = auth.uid() or public.is_owner());
revoke all on public.flow_skips from public, anon, authenticated; grant select on public.flow_skips to authenticated;
drop trigger if exists audit_flow_skips on public.flow_skips;
create trigger audit_flow_skips after insert on public.flow_skips for each row execute function public.log_change('id');
drop trigger if exists flow_skips_no_change on public.flow_skips;
create trigger flow_skips_no_change before update or delete on public.flow_skips for each row execute function public.no_hard_delete();
create or replace function public.flow_skip(p_flow text, p_step text, p_loc int, p_day date, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sid text;
begin
  if not public.is_active() or (p_loc is not null and not public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  if p_day is null or p_day > (now() at time zone 'Asia/Dhaka')::date or p_day < (now() at time zone 'Asia/Dhaka')::date - 31 then raise exception 'bad_date'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.flow_skips (flow, step, location_id, day, note, created_by, created_staff) values (p_flow, p_step, p_loc, p_day, left(btrim(p_note), 300), auth.uid(), sid)
    on conflict (flow, step, location_id, day, created_by) do nothing;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.flow_skip(text, text, int, date, text) from public, anon; grant execute on function public.flow_skip(text, text, int, date, text) to authenticated;

revoke all on function public._par_mgr(), public._books_mgr(int), public._loc_print_note(), public.comparison_pair_save(text, text, text, text, text, bigint, boolean), public.comparison_record(bigint, int, date, text, numeric),
  public.comparison_explain(bigint, text, text), public.parallel_month_status(text, int, date), public.parallel_month_decide(text, int, date, boolean, text), public.parallel_waiting(),
  public.paper_book_add(text, int, bigint, bigint, text, date, text, text), public.paper_book_set_status(bigint, text, text), public.paper_books_check(text, int),
  public.print_note_add(int, text, text, text), public.print_note_clear(bigint, date), public.needs_you_oldest(int) from public, anon;
revoke all on function public._par_mgr(), public._books_mgr(int), public._loc_print_note() from authenticated;
grant execute on function public.comparison_pair_save(text, text, text, text, text, bigint, boolean), public.comparison_record(bigint, int, date, text, numeric),
  public.comparison_explain(bigint, text, text), public.parallel_month_status(text, int, date), public.parallel_month_decide(text, int, date, boolean, text), public.parallel_waiting(),
  public.paper_book_add(text, int, bigint, bigint, text, date, text, text), public.paper_book_set_status(bigint, text, text), public.paper_books_check(text, int),
  public.print_note_add(int, text, text, text), public.print_note_clear(bigint, date), public.needs_you_oldest(int) to authenticated;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase40.sql
-- ============================================================
-- PHASE 40 (Module A: Accounting). Additive and idempotent (paste twice = no error). Needs phase8..phase28.
--   * coa_accounts: chart of accounts (code immutable, never deleted, retire with active = false). Seeded with a bakery / sweets-shop chart.
--   * journal_entries + journal_lines: double-entry journal. Append-only (a correction is a reversing entry). debit = credit, > 0, each line debit XOR credit.
--   * acct_mappings: payment mode / event -> account (the owner can re-point them).
--   * acct_post_pending(dry): reads the business tables (sales, returns, collections, purchases, supplier payments / refunds, 10-2 expense vouchers,
--     cash moves, wastage, production runs) and posts what has no journal entry yet. It never touches the hot paths. Idempotent by (source_type, source_id).
--     A voided source gets a reversing entry. COGS only where a real unit cost exists in the stock ledger - nothing is guessed (flag cogs_missing).
--   * Reports (jsonb): acct_trial_balance, acct_ledger, acct_journal_book, acct_income_statement, acct_balance_sheet, acct_cash_flow, acct_party_ledger, acct_reconcile.
--   * Manual journal acct_journal_post / acct_journal_reverse, opening balances acct_opening, acct_set_start.
--   * Rules: accounting_on (OFF), accounting_autopost (ON), accounting_start_date (empty = "Data needed"). Grants: accounts_view, accounts_manage.
-- Nothing is deleted. Staff-advance / salary postings are not connected (those tables do not exist yet): use the manual journal until they do.
-- ============================================================

-- ---------- rules and grants ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('accounting_on', 'books', 'switch', 'false', null, null, null, null, 'হিসাবরক্ষণ (খতিয়ান) চালু', 'Accounting (ledger) চালু', 'Accounting (double-entry books) on',
  'চালু করার আগে হিসাব শুরুর তারিখ ও শুরুর জের দিন। বন্ধ থাকলে কিছু পোস্ট হয় না।', 'Set the start date and opening balances first. While off nothing is posted to the books.', 90),
 ('accounting_autopost', 'books', 'switch', 'true', null, null, null, null, 'হিসাব পাতা খুললে নিজে পোস্ট', 'Accounts পাতা খুললে নিজে post', 'Post new business events when the accounts page opens',
  'চালু = হিসাব পাতা খুললে নতুন বিক্রি/কেনা/খরচ নিজে খতিয়ানে উঠে যায়। বন্ধ = "এখন পোস্ট করুন" বোতাম চাপতে হবে।', 'On = opening the accounts page posts new sales, purchases and expenses by itself. Off = press "Post now".', 91)
 on conflict (key) do nothing;
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('accounting_start_date', 'books', 'text', null, 'YYYY-MM-DD', null, null, null, 'হিসাব শুরুর তারিখ', 'হিসাব শুরুর date', 'Accounting start date',
  'এই তারিখের আগের কিছু খতিয়ানে ওঠে না। ফাঁকা = "ডেটা লাগবে"। যেমন 2026-11-01।', 'Nothing dated before this goes into the books. Empty = "Data needed". e.g. 2026-11-01.', 92)
 on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'accounts_view', 'cash', 70, 'হিসাব দেখা (খতিয়ান, ব্যালান্স শিট)', 'Accounts দেখা (ledger, balance sheet)', 'View the accounts (ledger, trial balance, balance sheet, P&L)', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'accounts_view');
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'accounts_manage', 'cash', 71, 'হিসাব পরিচালনা (পোস্ট, জার্নাল, হিসাবের তালিকা)', 'Accounts manage (post, journal, chart)', 'Manage the accounts (post, manual journal, opening balances, chart of accounts)', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'accounts_manage');

-- ---------- tables ----------
create table if not exists public.coa_accounts (
  id bigserial primary key,
  code text not null unique check (code ~ '^[0-9A-Za-z.\-]{1,12}$'),
  name_bn text not null check (length(btrim(name_bn)) between 1 and 120),
  name_en text not null check (length(btrim(name_en)) between 1 and 120),
  type text not null check (type in ('asset', 'liability', 'equity', 'income', 'expense')),
  parent_id bigint references public.coa_accounts(id),
  normal_side text not null check (normal_side in ('debit', 'credit')),
  is_group boolean not null default false,            -- a header: it adds up its children, nothing is posted to it
  is_system boolean not null default false,
  active boolean not null default true,
  sort int not null default 0,
  created_at timestamptz not null default now(),
  created_by uuid
);
create index if not exists coa_parent on public.coa_accounts (parent_id);

create table if not exists public.acct_mappings (
  key text primary key check (key ~ '^[a-z0-9_]{2,48}$'),
  account_id bigint not null references public.coa_accounts(id),
  label_bn text, label_en text,
  updated_by uuid, updated_at timestamptz not null default now()
);

create table if not exists public.journal_entries (
  id bigint generated always as identity primary key,
  entry_date date not null,
  location_id int references public.locations(id),
  source_type text not null check (length(source_type) between 1 and 40),
  source_id text not null check (length(source_id) between 1 and 80),
  subtype text,
  memo text not null check (length(memo) <= 300),
  status text not null default 'posted' check (status in ('posted', 'void')),
  reverses_id bigint references public.journal_entries(id),
  flags text,                                          -- e.g. cogs_missing, unreadable_lines
  photo text,
  created_by uuid, created_staff text,
  created_at timestamptz not null default now(),
  client_id uuid unique
);
create unique index if not exists je_source_uq on public.journal_entries (source_type, source_id) where reverses_id is null;
create unique index if not exists je_reverses_uq on public.journal_entries (reverses_id) where reverses_id is not null;
create index if not exists je_date on public.journal_entries (entry_date);

create table if not exists public.journal_lines (
  entry_id bigint not null references public.journal_entries(id),
  line_no int not null,
  account_id bigint not null references public.coa_accounts(id),
  debit numeric not null default 0 check (debit >= 0 and debit <= 1000000000000),
  credit numeric not null default 0 check (credit >= 0 and credit <= 1000000000000),
  location_id int references public.locations(id),
  party_type text check (party_type is null or party_type in ('customer', 'supplier', 'staff', 'partner')),
  party_id text,
  memo text,
  primary key (entry_id, line_no),
  check ((debit > 0) <> (credit > 0))
);
create index if not exists jl_account on public.journal_lines (account_id);
create index if not exists jl_party on public.journal_lines (party_type, party_id) where party_type is not null;

-- ---------- immutability ----------
create or replace function public._acct_ro() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_table_name = 'journal_entries' and tg_op = 'UPDATE' then
    -- the only change ever allowed: an entry becomes 'void' once its reversing entry exists
    if old.status = 'posted' and new.status = 'void' and (to_jsonb(new) - 'status') = (to_jsonb(old) - 'status')
       and exists (select 1 from public.journal_entries r where r.reverses_id = old.id) then return new; end if;
  end if;
  raise exception 'append_only: % is a record, it cannot be changed or deleted (post a reversing entry)', tg_table_name;
end $$;
drop trigger if exists je_ro on public.journal_entries;
create trigger je_ro before update or delete on public.journal_entries for each row execute function public._acct_ro();
drop trigger if exists je_ro_t on public.journal_entries;
create trigger je_ro_t before truncate on public.journal_entries for each statement execute function public._acct_ro();
drop trigger if exists jl_ro on public.journal_lines;
create trigger jl_ro before update or delete on public.journal_lines for each row execute function public._acct_ro();
drop trigger if exists jl_ro_t on public.journal_lines;
create trigger jl_ro_t before truncate on public.journal_lines for each statement execute function public._acct_ro();

create or replace function public._acct_balance_chk() returns trigger language plpgsql security definer set search_path = public as $$
declare d numeric; c numeric;
begin
  select coalesce(sum(debit), 0), coalesce(sum(credit), 0) into d, c from public.journal_lines where entry_id = new.entry_id;
  if d <> c or d <= 0 then raise exception 'unbalanced: debit % credit % (entry %)', d, c, new.entry_id; end if;
  return null;
end $$;
drop trigger if exists jl_balance on public.journal_lines;
create constraint trigger jl_balance after insert on public.journal_lines deferrable initially deferred for each row execute function public._acct_balance_chk();

-- the chart: code, type and side never change; nothing is deleted
create or replace function public._acct_coa_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'nothing is deleted – retire instead'; end if;
  if new.code <> old.code or new.type <> old.type or new.normal_side <> old.normal_side or new.is_group <> old.is_group then raise exception 'account_fixed: code, type and side cannot change'; end if;
  return new;
end $$;
drop trigger if exists coa_guard on public.coa_accounts;
create trigger coa_guard before update or delete on public.coa_accounts for each row execute function public._acct_coa_guard();
drop trigger if exists audit_coa_accounts on public.coa_accounts;
create trigger audit_coa_accounts after insert or update on public.coa_accounts for each row execute function public.log_change('id');
drop trigger if exists audit_acct_mappings on public.acct_mappings;
create trigger audit_acct_mappings after insert or update on public.acct_mappings for each row execute function public.log_change('key');
drop trigger if exists acct_mappings_no_delete on public.acct_mappings;
create trigger acct_mappings_no_delete before delete on public.acct_mappings for each row execute function public.no_hard_delete();

-- ---------- access helpers ----------
create or replace function public._acct_view() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('accounts_view') or public.has_grant('accounts_manage')
    or exists (select 1 from public.locations l where public.has_grant('accounts_view', l.id) or public.has_grant('accounts_manage', l.id)));
$$;
create or replace function public._acct_manage() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('accounts_manage')
    or exists (select 1 from public.locations l where public.has_grant('accounts_manage', l.id)));
$$;
-- every place (and the company-level lines with no place): owner, head management, or an accountant whose grant is not tied to one place
create or replace function public._acct_all() returns boolean language sql stable security definer set search_path = public as $$ select public.can_loc(null) or (public.is_active() and public.has_grant('accounts_manage')); $$;
create or replace function public._acct_locs() returns int[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(l.id), '{}') from public.locations l where public.can_loc(l.id);
$$;
create or replace function public._acct_start() returns date language plpgsql stable security definer set search_path = public as $$
declare v text := public.rule_txt('accounting_start_date');
begin
  if v is null or v !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
  begin return v::date; exception when others then return null; end;
end $$;
create or replace function public._acct_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date; $$;
create or replace function public._acct_locked(p_date date) returns boolean language plpgsql security definer set search_path = public as $$
begin perform public.lock_check(p_date); return false; exception when others then return true; end $$;

-- ---------- RLS ----------
alter table public.coa_accounts enable row level security;
alter table public.acct_mappings enable row level security;
alter table public.journal_entries enable row level security;
alter table public.journal_lines enable row level security;
drop policy if exists coa_read on public.coa_accounts;
create policy coa_read on public.coa_accounts for select to authenticated using (public._acct_view());
drop policy if exists acct_map_read on public.acct_mappings;
create policy acct_map_read on public.acct_mappings for select to authenticated using (public._acct_view());
drop policy if exists je_read on public.journal_entries;
create policy je_read on public.journal_entries for select to authenticated using (public._acct_view() and (public._acct_all() or (location_id is not null and public.can_loc(location_id))));
drop policy if exists jl_read on public.journal_lines;
create policy jl_read on public.journal_lines for select to authenticated using (public._acct_view() and (public._acct_all() or (location_id is not null and public.can_loc(location_id))));
revoke all on public.coa_accounts, public.acct_mappings, public.journal_entries, public.journal_lines from public, anon, authenticated;
grant select on public.coa_accounts, public.acct_mappings, public.journal_entries, public.journal_lines to authenticated;

-- ---------- seed: chart of accounts ----------
do $seed$
declare r record;
begin
  for r in select * from (values
    ('1000', 'সম্পদ', 'Assets', 'asset', 'debit', true, null, 10),
    ('1100', 'নগদ ও ব্যাংক', 'Cash and bank', 'asset', 'debit', true, '1000', 11),
    ('1110', 'হাতে নগদ', 'Cash in hand', 'asset', 'debit', false, '1100', 12),
    ('1120', 'ব্যাংক', 'Bank', 'asset', 'debit', false, '1100', 13),
    ('1130', 'মোবাইল ওয়ালেট (বিকাশ/নগদ)', 'Mobile wallets (bKash / Nagad)', 'asset', 'debit', false, '1100', 14),
    ('1140', 'কার্ডের পাওনা', 'Card receivable', 'asset', 'debit', false, '1100', 15),
    ('1200', 'পাওনা ও অগ্রিম', 'Receivables and advances', 'asset', 'debit', true, '1000', 20),
    ('1210', 'গ্রাহকের বাকি', 'Customer receivables', 'asset', 'debit', false, '1200', 21),
    ('1220', 'স্টাফকে অগ্রিম', 'Advances to staff', 'asset', 'debit', false, '1200', 22),
    ('1230', 'লোকেশনের মধ্যে লেনদেন (ক্লিয়ারিং)', 'Inter-location clearing', 'asset', 'debit', false, '1200', 23),
    ('1300', 'মজুত মাল', 'Inventory', 'asset', 'debit', true, '1000', 30),
    ('1310', 'মজুত: তৈরি পণ্য', 'Inventory: finished goods', 'asset', 'debit', false, '1300', 31),
    ('1320', 'মজুত: কাঁচামাল', 'Inventory: raw materials', 'asset', 'debit', false, '1300', 32),
    ('1330', 'মজুত: প্যাকেজিং', 'Inventory: packaging', 'asset', 'debit', false, '1300', 33),
    ('1400', 'অগ্রিম দেওয়া খরচ', 'Prepaid expenses', 'asset', 'debit', false, '1000', 40),
    ('1500', 'স্থায়ী সম্পদ', 'Fixed assets', 'asset', 'debit', true, '1000', 50),
    ('1510', 'স্থায়ী সম্পদ (কেনা দামে)', 'Fixed assets at cost', 'asset', 'debit', false, '1500', 51),
    ('1590', 'সঞ্চিত অবচয় (বিয়োগ)', 'Accumulated depreciation (contra)', 'asset', 'credit', false, '1500', 52),
    ('2000', 'দায়', 'Liabilities', 'liability', 'credit', true, null, 100),
    ('2100', 'সরবরাহকারীর পাওনা', 'Supplier payables', 'liability', 'credit', false, '2000', 101),
    ('2200', 'বকেয়া বেতন', 'Accrued salaries', 'liability', 'credit', false, '2000', 102),
    ('2300', 'গ্রাহকের অগ্রিম (আমাদের দায়)', 'Customer advances (liability)', 'liability', 'credit', false, '2000', 103),
    ('2400', 'অন্যান্য বকেয়া খরচ', 'Other accrued expenses', 'liability', 'credit', false, '2000', 104),
    ('3000', 'মালিকানা', 'Equity', 'equity', 'credit', true, null, 200),
    ('3100', 'মালিকের মূলধন', 'Owner capital', 'equity', 'credit', false, '3000', 201),
    ('3200', 'অংশীদার / বিনিয়োগকারীর মূলধন', 'Partner / investor capital', 'equity', 'credit', false, '3000', 202),
    ('3300', 'মালিকের উত্তোলন (বিয়োগ)', 'Owner drawings (contra)', 'equity', 'debit', false, '3000', 203),
    ('3900', 'জমা মুনাফা (শুরুর)', 'Retained earnings (opening)', 'equity', 'credit', false, '3000', 209),
    ('4000', 'আয়', 'Income', 'income', 'credit', true, null, 300),
    ('4100', 'বিক্রয়', 'Sales', 'income', 'credit', false, '4000', 301),
    ('4110', 'বিক্রি ফেরত (বিয়োগ)', 'Sales returns (contra)', 'income', 'debit', false, '4000', 302),
    ('4120', 'বিক্রয় ছাড় / ডিসকাউন্ট (বিয়োগ)', 'Sales discounts (contra)', 'income', 'debit', false, '4000', 303),
    ('4900', 'অন্যান্য আয়', 'Other income', 'income', 'credit', false, '4000', 309),
    ('5000', 'বিক্রীত পণ্যের খরচ (COGS)', 'Cost of goods sold', 'expense', 'debit', false, null, 400),
    ('5100', 'নষ্ট মালের ক্ষতি', 'Wastage loss', 'expense', 'debit', false, null, 401),
    ('5200', 'বেতন ও মজুরি', 'Salaries and wages', 'expense', 'debit', false, null, 402),
    ('5300', 'ভাড়া', 'Rent', 'expense', 'debit', false, null, 403),
    ('5400', 'বিদ্যুৎ, পানি, গ্যাস', 'Utilities', 'expense', 'debit', false, null, 404),
    ('5500', 'মার্কেটিং', 'Marketing', 'expense', 'debit', false, null, 405),
    ('5600', 'মেরামত ও রক্ষণাবেক্ষণ', 'Repairs and maintenance', 'expense', 'debit', false, null, 406),
    ('5700', 'যাতায়াত ও পরিবহন', 'Transport', 'expense', 'debit', false, null, 407),
    ('5800', 'ক্যাশ ঘাটতি / উদ্বৃত্ত', 'Cash short / over', 'expense', 'debit', false, null, 408),
    ('5810', 'ব্যাংক চার্জ', 'Bank charges', 'expense', 'debit', false, null, 409),
    ('5820', 'অবচয়', 'Depreciation', 'expense', 'debit', false, null, 410),
    ('5830', 'স্টাফের খাবার ও নাস্তা', 'Staff meals and welfare', 'expense', 'debit', false, null, 411),
    ('5840', 'আপ্যায়ন', 'Hospitality', 'expense', 'debit', false, null, 412),
    ('5850', 'বাইরে থেকে কেনা মাল', 'Outside-sourced goods', 'expense', 'debit', false, null, 413),
    ('5860', 'ভোগ্য সামগ্রী', 'Consumables', 'expense', 'debit', false, null, 414),
    ('5870', 'অশ্রেণীবদ্ধ ক্রয়', 'Purchases not classified', 'expense', 'debit', false, null, 415),
    ('5900', 'অন্যান্য খরচ', 'Other expenses', 'expense', 'debit', false, null, 499)
  ) as v(code, nb, ne, ty, sd, grp, par, srt) loop
    insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, is_group, is_system, sort)
      values (r.code, r.nb, r.ne, r.ty, r.sd, r.grp, true, r.srt) on conflict (code) do nothing;
    if r.par is not null then
      update public.coa_accounts c set parent_id = (select p.id from public.coa_accounts p where p.code = r.par) where c.code = r.code and c.parent_id is null and c.is_system;
    end if;
  end loop;
end $seed$;

insert into public.acct_mappings (key, account_id, label_bn, label_en)
select v.k, a.id, v.lb, v.le from (values
  ('pay_cash', '1110', 'নগদ টাকা', 'Cash payments'),
  ('pay_bank', '1120', 'ব্যাংক / কার্ডে সরবরাহকারীকে', 'Bank payments'),
  ('pay_mobile', '1130', 'মোবাইল ওয়ালেট', 'Mobile wallet payments'),
  ('pay_card', '1140', 'কার্ডে বিক্রি (পাওনা)', 'Card sales (receivable)'),
  ('sales', '4100', 'বিক্রয় আয়', 'Sales revenue'),
  ('sales_returns', '4110', 'বিক্রি ফেরত', 'Sales returns'),
  ('sales_discount', '4120', 'বিক্রয়ে ছাড়', 'Sales discounts'),
  ('receivable', '1210', 'গ্রাহকের বাকি', 'Customer receivable'),
  ('payable', '2100', 'সরবরাহকারীর পাওনা', 'Supplier payable'),
  ('cust_advance', '2300', 'গ্রাহকের অগ্রিম', 'Customer advance'),
  ('inv_finished', '1310', 'তৈরি পণ্যের মজুত', 'Finished goods inventory'),
  ('inv_raw', '1320', 'কাঁচামালের মজুত', 'Raw materials inventory'),
  ('inv_pack', '1330', 'প্যাকেজিংয়ের মজুত', 'Packaging inventory'),
  ('cogs', '5000', 'বিক্রীত পণ্যের খরচ', 'Cost of goods sold'),
  ('wastage', '5100', 'নষ্ট মালের ক্ষতি', 'Wastage loss'),
  ('owner_capital', '3100', 'মালিকের টাকা ঢোকানো', 'Owner top-up'),
  ('owner_drawings', '3300', 'মালিকের উত্তোলন', 'Owner draw'),
  ('hub_clearing', '1230', 'হাব থেকে প্রাপ্ত নগদ', 'Hub receipts clearing'),
  ('fixed_assets', '1510', 'স্থায়ী সম্পদ কেনা', 'Fixed asset purchases'),
  ('purch_consumable', '5860', 'ভোগ্য সামগ্রী কেনা', 'Consumable purchases'),
  ('purch_unclassified', '5870', 'আইটেম ছাড়া ক্রয়', 'Purchases without an item'),
  ('retained', '3900', 'শুরুর জমা মুনাফা (ব্যালান্স মেলাতে)', 'Opening retained earnings (balancing)'),
  ('exp_staff_meal', '5830', '10-2: স্টাফের খাবার', '10-2 staff meals'),
  ('exp_transport', '5700', '10-2: যাতায়াত', '10-2 transport'),
  ('exp_hospitality', '5840', '10-2: আপ্যায়ন', '10-2 hospitality'),
  ('exp_repair', '5600', '10-2: মেরামত / ইউটিলিটি', '10-2 repairs / utilities'),
  ('exp_labour', '5200', '10-2: অস্থায়ী শ্রমিক', '10-2 temporary labour'),
  ('exp_sourcing', '5850', '10-2: বাইরের মাল', '10-2 outside-sourced goods'),
  ('exp_other', '5900', '10-2: অন্যান্য খরচ (যে খাতের আলাদা হিসাব নেই)', '10-2 other expenses (any head without its own mapping)')
) as v(k, c, lb, le) join public.coa_accounts a on a.code = v.c
on conflict (key) do nothing;

-- ---------- internal helpers ----------
create or replace function public._acct_num(t text) returns numeric language sql immutable set search_path = public as $$
  select case when translate(btrim(t), '০১২৩৪৫৬৭৮৯,', '0123456789') ~ '^[0-9]{1,12}(\.[0-9]{1,4})?$' then translate(btrim(t), '০১২৩৪৫৬৭৮৯,', '0123456789')::numeric end;
$$;
create or replace function public._acct_inv_key(t text) returns text language sql immutable as $$
  select case coalesce(t, '') when 'raw_material' then 'inv_raw' when 'packaging' then 'inv_pack' else 'inv_finished' end;
$$;
create or replace function public._acct_buy_key(t text) returns text language sql immutable as $$
  select case coalesce(t, '-') when '-' then 'purch_unclassified' when 'finished_good' then 'inv_finished' when 'resale' then 'inv_finished'
    when 'raw_material' then 'inv_raw' when 'packaging' then 'inv_pack' when 'asset' then 'fixed_assets'
    when 'consumable' then 'purch_consumable' when 'infrastructure' then 'purch_consumable' when 'controlled' then 'purch_consumable' else 'inv_raw' end;
$$;
create or replace function public._acct_paykey(p_mode text, p_card_to_bank boolean default false) returns text language sql immutable as $$
  select case p_mode when 'cash' then 'pay_cash' when 'mobile' then 'pay_mobile' when 'bank' then 'pay_bank' when 'card' then case when p_card_to_bank then 'pay_bank' else 'pay_card' end end;
$$;

-- does this source still need an action? (live and not posted yet) or (gone and posted and not reversed yet)
create or replace function public._acct_need(p_type text, p_id text, p_live boolean) returns boolean language sql stable set search_path = public as $$
  select case when p_live then not exists (select 1 from public.journal_entries e where e.source_type = p_type and e.source_id = p_id and e.reverses_id is null)
    else exists (select 1 from public.journal_entries e where e.source_type = p_type and e.source_id = p_id and e.reverses_id is null)
         and not exists (select 1 from public.journal_entries r join public.journal_entries o on o.id = r.reverses_id where o.source_type = p_type and o.source_id = p_id and o.reverses_id is null) end;
$$;

-- bill amount split by what was bought (discount spread over the lines, the last cent goes to the biggest part)
create or replace function public._acct_purchase_alloc(p_bill uuid) returns table(k text, amt numeric) language plpgsql stable set search_path = public as $$
declare b public.purchase_bills; f numeric; ks text[] := '{}'; vs numeric[] := '{}'; r record; sm numeric := 0; big int := 1; i int;
begin
  select * into b from public.purchase_bills where id = p_bill;
  if not found then return; end if;
  f := case when b.subtotal > 0 then (b.subtotal - b.discount) / b.subtotal else 1 end;
  for r in select public._acct_buy_key(it.item_type) key, sum(coalesce(l.amount, l.qty * l.unit_cost, 0)) a
           from public.purchase_lines l left join public.items it on it.id = l.item_id where l.bill_id = p_bill group by 1 order by 1 loop
    ks := ks || r.key; vs := vs || round(r.a * f, 2);
  end loop;
  if coalesce(array_length(ks, 1), 0) = 0 then ks := array['purch_unclassified']; vs := array[b.total]; end if;
  for i in 1 .. array_length(vs, 1) loop sm := sm + vs[i]; if vs[i] > vs[big] then big := i; end if; end loop;
  vs[big] := vs[big] + (b.total - sm);
  for i in 1 .. array_length(ks, 1) loop
    if vs[i] > 0 then k := ks[i]; amt := vs[i]; return next; end if;
  end loop;
end $$;

-- ---------- the scanner: every business document that needs posting or reversing ----------
-- lines are {a: mapping key, d|c: amount, pt, pid, m}. Nothing is posted here.
create or replace function public._acct_docs(p_start date) returns table(
  source_type text, source_id text, entry_date date, location_id int, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
language plpgsql stable security definer set search_path = public as $fn$
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
  where e.form_code = '10-2' and e.status = 'approved' and e.entry_date >= p_start and public._acct_need('expense_voucher', e.id::text || ':' || coalesce(e.rev_no, 0)::text, v.total > 0);
  return query
  select 'expense_voucher'::text, je.source_id, je.entry_date, je.location_id, 'Expense voucher no longer approved'::text, null::text, false, public._acct_today(), null::text, null::text, null::jsonb
  from public.journal_entries je
  where je.source_type = 'expense_voucher' and je.reverses_id is null
    and not exists (select 1 from public.entries e where e.form_code = '10-2' and e.status = 'approved' and e.id::text || ':' || coalesce(e.rev_no, 0)::text = je.source_id)
    and not exists (select 1 from public.journal_entries r where r.reverses_id = je.id);

  -- cash moves (bank deposit / withdraw, owner top-up / draw, customer advances, hub receipt)
  return query
  select 'cash_move'::text, m.id::text, m.move_date, m.location_id, ('Cash move: ' || m.kind)::text, m.kind, m.status = 'done', (m.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when m.status = 'done' then case m.kind
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
  where m.move_date >= p_start and public._acct_need('cash_move', m.id::text, m.status = 'done');

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
        select 1 o, jsonb_build_object('a', 'inv_finished', 'd', c.amt) j
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from (select it.item_type t, round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id
                where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out' and l.unit_cost is not null group by it.item_type) z where z.amt > 0
      ) y) end
  from public.production_runs r cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where l.unit_cost is null) nulls
    from public.stock_ledger l where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out') c
  where (r.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('production', r.id::text, r.status = 'done');
end $fn$;

-- keys -> account ids; accepts {a}, {account_id} or {code}; returns [{account_id, debit, credit, party_type, party_id, memo, location_id}]
create or replace function public._acct_resolve(p_lines jsonb, p_loc int) returns jsonb language plpgsql stable set search_path = public as $$
declare e jsonb; out jsonb := '[]'; aid bigint; k text; d numeric; c numeric; ds text; cs text; lc int; pid text;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' then raise exception 'no_lines'; end if;
  for e in select * from jsonb_array_elements(p_lines) loop
    if jsonb_typeof(e) <> 'object' then raise exception 'bad_line'; end if;
    aid := null;
    if nullif(e->>'account_id', '') is not null then
      if (e->>'account_id') !~ '^[0-9]{1,15}$' then raise exception 'unknown_account'; end if;
      aid := (e->>'account_id')::bigint;
      if not exists (select 1 from public.coa_accounts where id = aid) then raise exception 'unknown_account'; end if;
    elsif nullif(e->>'code', '') is not null then
      select id into aid from public.coa_accounts where code = e->>'code';
      if aid is null then raise exception 'unknown_account'; end if;
    elsif nullif(e->>'a', '') is not null then
      k := e->>'a';
      select account_id into aid from public.acct_mappings where key = k;
      if aid is null and k like 'exp\_%' then select account_id into aid from public.acct_mappings where key = 'exp_other'; end if;
      if aid is null then raise exception 'mapping_missing:%', k; end if;
    else raise exception 'unknown_account'; end if;
    ds := coalesce(e->>'debit', e->>'d', '0'); cs := coalesce(e->>'credit', e->>'c', '0');
    if ds = '' then ds := '0'; end if; if cs = '' then cs := '0'; end if;
    if ds !~ '^[0-9]{1,13}(\.[0-9]{1,6})?$' or cs !~ '^[0-9]{1,13}(\.[0-9]{1,6})?$' then raise exception 'bad_amount'; end if;
    d := round(ds::numeric, 2); c := round(cs::numeric, 2);
    lc := coalesce(nullif(e->>'location_id', '')::int, p_loc);
    pid := nullif(btrim(coalesce(e->>'party_id', e->>'pid')), '');
    out := out || jsonb_build_object('account_id', aid, 'debit', d, 'credit', c, 'party_type', nullif(coalesce(e->>'party_type', e->>'pt'), ''), 'party_id', left(pid, 60),
      'memo', left(nullif(btrim(coalesce(e->>'memo', e->>'m')), ''), 200), 'location_id', lc);
  end loop;
  return out;
end $$;

-- the system lines are merged (same account / party twice = one line, debit and credit netted)
create or replace function public._acct_merge(p_lines jsonb) returns jsonb language sql immutable as $$
  select coalesce(jsonb_agg(jsonb_build_object('a', a, 'd', case when net > 0 then net end, 'c', case when net < 0 then -net end, 'pt', pt, 'pid', pid) order by a, pid), '[]'::jsonb)
  from (select e->>'a' a, nullif(e->>'pt', '') pt, nullif(e->>'pid', '') pid, sum(coalesce((e->>'d')::numeric, 0) - coalesce((e->>'c')::numeric, 0)) net
        from jsonb_array_elements(p_lines) e group by 1, 2, 3) z where net <> 0;
$$;

-- the one place that writes a journal entry
create or replace function public._acct_write(p_date date, p_loc int, p_type text, p_sid text, p_subtype text, p_memo text, p_flags text, p_lines jsonb,
  p_reverses bigint default null, p_client uuid default null, p_photo text default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare st date := public._acct_start(); id_ bigint; e jsonb; n int := 0; td numeric := 0; tc numeric := 0; d numeric; c numeric; a public.coa_accounts; sid text; pt text; lc int;
begin
  if st is null then raise exception 'data_needed'; end if;
  if p_date is null or p_date < st then raise exception 'before_start'; end if;
  if p_date > public._acct_today() + 1 then raise exception 'bad_date'; end if;
  if p_loc is not null and not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) < 2 then raise exception 'need_two_lines'; end if;
  if jsonb_array_length(p_lines) > 200 then raise exception 'too_many_lines'; end if;
  if p_photo is not null and (length(p_photo) > 300 or p_photo like '%..%') then raise exception 'bad_photo'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.journal_entries (entry_date, location_id, source_type, source_id, subtype, memo, flags, photo, reverses_id, created_by, created_staff, client_id)
    values (p_date, p_loc, p_type, p_sid, p_subtype, left(coalesce(nullif(btrim(p_memo), ''), p_type), 300), p_flags, nullif(btrim(p_photo), ''), p_reverses, auth.uid(), sid, p_client) returning id into id_;
  for e in select * from jsonb_array_elements(p_lines) loop
    n := n + 1;
    d := (e->>'debit')::numeric; c := (e->>'credit')::numeric; pt := e->>'party_type'; lc := nullif(e->>'location_id', '')::int;
    if d < 0 or c < 0 or (d > 0) = (c > 0) then raise exception 'line_debit_xor_credit'; end if;
    if d > 1000000000000 or c > 1000000000000 then raise exception 'bad_amount'; end if;
    select * into a from public.coa_accounts where id = (e->>'account_id')::bigint;
    if not found then raise exception 'unknown_account'; end if;
    if a.is_group then raise exception 'account_is_group: %', a.code; end if;
    if not a.active and p_reverses is null then raise exception 'account_retired: %', a.code; end if;
    if pt is not null and pt not in ('customer', 'supplier', 'staff', 'partner') then raise exception 'bad_party'; end if;
    if pt is not null and nullif(e->>'party_id', '') is null then raise exception 'party_id_required'; end if;
    if lc is not null and not exists (select 1 from public.locations where id = lc) then raise exception 'bad_location'; end if;
    insert into public.journal_lines (entry_id, line_no, account_id, debit, credit, location_id, party_type, party_id, memo)
      values (id_, n, a.id, d, c, lc, pt, case when pt is not null then left(e->>'party_id', 60) end, left(nullif(e->>'memo', ''), 200));
    td := td + d; tc := tc + c;
  end loop;
  if td <> tc or td <= 0 then raise exception 'unbalanced' using detail = 'debit ' || td::text || ' credit ' || tc::text; end if;
  return id_;
end $$;

create or replace function public._acct_reverse(p_orig bigint, p_date date, p_memo text, p_client uuid default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare o public.journal_entries; id_ bigint; lines jsonb;
begin
  select * into o from public.journal_entries where id = p_orig for update;
  if not found then raise exception 'not found'; end if;
  if o.reverses_id is not null then raise exception 'cannot_reverse_a_reversal'; end if;
  if exists (select 1 from public.journal_entries where reverses_id = p_orig) then raise exception 'already_reversed'; end if;
  select jsonb_agg(jsonb_build_object('account_id', account_id, 'debit', credit, 'credit', debit, 'party_type', party_type, 'party_id', party_id, 'memo', memo, 'location_id', location_id) order by line_no)
    into lines from public.journal_lines where entry_id = p_orig;
  id_ := public._acct_write(greatest(p_date, o.entry_date), o.location_id, o.source_type, o.source_id, o.subtype, 'Reversal: ' || o.memo, o.flags, lines, p_orig, p_client, null);
  update public.journal_entries set status = 'void' where id = p_orig;
  return id_;
end $$;

-- ---------- status / settings ----------
create or replace function public.acct_status() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  return jsonb_build_object('on', public.rule_on('accounting_on'), 'autopost', public.rule_on('accounting_autopost'), 'start', public._acct_start(),
    'can_manage', public._acct_manage(), 'owner', public.is_owner(),
    'opening', exists (select 1 from public.journal_entries o where o.source_type = 'opening' and o.reverses_id is null and not exists (select 1 from public.journal_entries r where r.reverses_id = o.id)),
    'entries', (select count(*) from public.journal_entries), 'accounts', (select count(*) from public.coa_accounts where active),
    'last_post', (select max(created_at) from public.journal_entries where created_by is not null and source_type not in ('manual', 'opening')));
end $$;

create or replace function public.acct_set_start(p_date date) returns jsonb language plpgsql security definer set search_path = public as $$
declare mn date;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_date is null or p_date < date '2000-01-01' or p_date > public._acct_today() + 366 then raise exception 'bad_date'; end if;
  select min(entry_date) into mn from public.journal_entries;
  if mn is not null and p_date > mn then raise exception 'entries_before_start' using detail = mn::text; end if;
  perform public.set_rule('accounting_start_date', to_jsonb(p_date::text));
  return jsonb_build_object('start', p_date);
end $$;

-- ---------- chart of accounts ----------
create or replace function public.acct_account_save(p_id bigint, p_code text, p_name_bn text, p_name_en text, p_type text, p_parent bigint default null,
  p_active boolean default true, p_sort int default null, p_contra boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.coa_accounts; side text; par public.coa_accounts;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if p_name_bn is null or length(btrim(p_name_bn)) = 0 or length(p_name_bn) > 120 or p_name_en is null or length(btrim(p_name_en)) = 0 or length(p_name_en) > 120 then raise exception 'name_required'; end if;
  if p_parent is not null then
    select * into par from public.coa_accounts where id = p_parent;
    if not found or not par.is_group then raise exception 'bad_parent'; end if;
  end if;
  if p_id is null then
    if p_code is null or p_code !~ '^[0-9A-Za-z.\-]{1,12}$' then raise exception 'bad_code'; end if;
    if p_type is null or p_type not in ('asset', 'liability', 'equity', 'income', 'expense') then raise exception 'bad_type'; end if;
    if par.id is not null and par.type <> p_type then raise exception 'bad_parent'; end if;
    if exists (select 1 from public.coa_accounts where code = p_code) then raise exception 'code_taken'; end if;
    side := case when (p_type in ('asset', 'expense')) <> coalesce(p_contra, false) then 'debit' else 'credit' end;
    insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, parent_id, sort, created_by)
      values (p_code, btrim(p_name_bn), btrim(p_name_en), p_type, side, p_parent, coalesce(p_sort, 500), auth.uid()) returning * into a;
    return jsonb_build_object('id', a.id, 'code', a.code);
  end if;
  select * into a from public.coa_accounts where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if par.id is not null and (par.type <> a.type or par.id = a.id) then raise exception 'bad_parent'; end if;
  if not coalesce(p_active, true) then
    if a.is_system and exists (select 1 from public.acct_mappings where account_id = a.id) then raise exception 'account_in_use_by_mapping'; end if;
    if exists (select 1 from public.coa_accounts where parent_id = a.id and active) then raise exception 'has_active_children'; end if;
  end if;
  update public.coa_accounts set name_bn = btrim(p_name_bn), name_en = btrim(p_name_en), parent_id = coalesce(p_parent, parent_id), active = coalesce(p_active, active), sort = coalesce(p_sort, sort) where id = a.id;
  return jsonb_build_object('id', a.id, 'code', a.code);
end $$;

create or replace function public.acct_mapping_set(p_key text, p_account bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare a public.coa_accounts;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if p_key is null or p_key !~ '^[a-z0-9_]{2,48}$' then raise exception 'bad_key'; end if;
  select * into a from public.coa_accounts where id = p_account;
  if not found or a.is_group or not a.active then raise exception 'bad_account'; end if;
  if not exists (select 1 from public.acct_mappings where key = p_key) and p_key not like 'exp\_%' then raise exception 'bad_key'; end if;
  insert into public.acct_mappings (key, account_id, updated_by) values (p_key, p_account, auth.uid())
    on conflict (key) do update set account_id = excluded.account_id, updated_by = auth.uid(), updated_at = now();
  return jsonb_build_object('key', p_key, 'account_id', p_account);
end $$;

-- ---------- posting from the business events ----------
create or replace function public.acct_post_pending(p_dry boolean default false, p_limit int default 1500) returns jsonb
language plpgsql security definer set search_path = public as $$
declare st date := public._acct_start(); d record; n int := 0; posted int := 0; rev int := 0; locked int := 0; more boolean := false; ln jsonb; res jsonb; orig public.journal_entries; rdate date;
        by_type jsonb := '{}'; waiting jsonb := '{}'; errors jsonb := '[]'; prev jsonb := '[]'; flagged int := 0; eid bigint; tot_d numeric := 0; tot_c numeric := 0; lim int := least(greatest(coalesce(p_limit, 1500), 1), 5000);
        trial jsonb; skipped jsonb := '[]'; acc jsonb := '[]';
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true, 'dry', p_dry); end if;
  if not p_dry and not public.rule_on('accounting_on') then raise exception 'accounting_off'; end if;
  if not p_dry then perform pg_advisory_xact_lock(hashtextextended('acct_post', 0)); end if;
  for d in select * from public._acct_docs(st) order by 3, 1, 2 loop
    if d.waiting is not null then waiting := jsonb_set(waiting, array[d.waiting], to_jsonb(coalesce((waiting->>d.waiting)::int, 0) + 1)); continue; end if;
    if n >= lim then more := true; exit; end if;
    begin
      if d.live then
        if public._acct_locked(d.entry_date) then locked := locked + 1; continue; end if;
        ln := public._acct_resolve(public._acct_merge(d.lines), d.location_id);
        if p_dry then
          acc := acc || (select coalesce(jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', (x->>'debit')::numeric, 'credit', (x->>'credit')::numeric)), '[]'::jsonb)
                         from jsonb_array_elements(ln) x join public.coa_accounts a on a.id = (x->>'account_id')::bigint);
          if jsonb_array_length(prev) < 60 then
            prev := prev || jsonb_build_object('date', d.entry_date, 'source_type', d.source_type, 'source_id', d.source_id, 'memo', d.memo, 'flags', d.flags, 'location_id', d.location_id,
              'lines', (select jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', (x->>'debit')::numeric, 'credit', (x->>'credit')::numeric, 'party_type', x->>'party_type', 'party_id', x->>'party_id'))
                        from jsonb_array_elements(ln) x join public.coa_accounts a on a.id = (x->>'account_id')::bigint));
          end if;
        else
          eid := public._acct_write(d.entry_date, d.location_id, d.source_type, d.source_id, d.subtype, d.memo, d.flags, ln);
        end if;
        posted := posted + 1;
        if d.flags like '%cogs_missing%' then flagged := flagged + 1; end if;
        by_type := jsonb_set(by_type, array[d.source_type], to_jsonb(coalesce((by_type->>d.source_type)::int, 0) + 1));
      else
        select * into orig from public.journal_entries o where o.source_type = d.source_type and o.source_id = d.source_id and o.reverses_id is null;
        rdate := greatest(coalesce(d.void_date, public._acct_today()), orig.entry_date);
        if public._acct_locked(rdate) then locked := locked + 1; continue; end if;
        if p_dry then
          acc := acc || (select coalesce(jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', l.credit, 'credit', l.debit)), '[]'::jsonb)
                         from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where l.entry_id = orig.id);
          if jsonb_array_length(prev) < 60 then
            prev := prev || jsonb_build_object('date', rdate, 'source_type', d.source_type, 'source_id', d.source_id, 'memo', 'Reversal: ' || orig.memo, 'reversal', true, 'location_id', orig.location_id,
              'lines', (select jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', l.credit, 'credit', l.debit, 'party_type', l.party_type, 'party_id', l.party_id) order by l.line_no)
                        from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where l.entry_id = orig.id));
          end if;
        else
          eid := public._acct_reverse(orig.id, rdate, 'Reversal: ' || orig.memo);
        end if;
        rev := rev + 1;
        by_type := jsonb_set(by_type, array[d.source_type || '_reversed'], to_jsonb(coalesce((by_type->>(d.source_type || '_reversed'))::int, 0) + 1));
      end if;
      n := n + 1;
    exception when others then
      errors := errors || jsonb_build_object('source_type', d.source_type, 'source_id', d.source_id, 'error', sqlerrm);
      n := n + 1;
    end;
  end loop;
  if p_dry then
    select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name_bn', name_bn, 'name_en', name_en, 'debit', dr, 'credit', cr) order by code), '[]'::jsonb), coalesce(sum(dr), 0), coalesce(sum(cr), 0)
      into trial, tot_d, tot_c from (select x->>'code' code, x->>'name_bn' name_bn, x->>'name_en' name_en, sum((x->>'debit')::numeric) dr, sum((x->>'credit')::numeric) cr from jsonb_array_elements(acc) x group by 1, 2, 3) z;
  end if;
  if to_regclass('public.staff_advances') is null then skipped := skipped || to_jsonb('staff_advances'::text); end if;
  if to_regclass('public.salary_payments') is null then skipped := skipped || to_jsonb('salary_payments'::text); end if;
  res := jsonb_build_object('dry', p_dry, 'start', st, 'posted', posted, 'reversed', rev, 'by_type', by_type, 'locked', locked, 'waiting', waiting, 'cogs_missing', flagged,
    'errors', errors, 'more', more, 'skipped_sources', skipped);
  if p_dry then res := res || jsonb_build_object('preview', prev, 'trial', trial, 'total_debit', tot_d, 'total_credit', tot_c); end if;
  return res;
end $$;

-- ---------- manual journal, opening balances ----------
create or replace function public.acct_journal_post(p_date date, p_loc int, p_memo text, p_lines jsonb, p_client uuid default null, p_photo text default null, p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
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
end $$;

create or replace function public.acct_journal_reverse(p_id bigint, p_note text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.journal_entries; r public.journal_entries; id_ bigint; dt date;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.journal_entries where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', r.id); end if;
  end if;
  select * into o from public.journal_entries where id = p_id;
  if not found then raise exception 'not found'; end if;
  if o.source_type not in ('manual', 'opening') then raise exception 'use_source: reverse the business document instead'; end if;
  if o.location_id is not null and not public.can_loc(o.location_id) then raise exception 'not allowed for this location'; end if;
  dt := greatest(public._acct_today(), o.entry_date);
  perform public.lock_check(dt);
  id_ := public._acct_reverse(p_id, dt, 'Reversal (' || left(btrim(p_note), 150) || '): ' || o.memo, p_client);
  return jsonb_build_object('id', id_);
end $$;

create or replace function public.acct_opening(p_lines jsonb, p_plug boolean default false, p_memo text default null, p_client uuid default null, p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare st date := public._acct_start(); ln jsonb; x jsonb; td numeric := 0; tc numeric := 0; diff numeric; plug bigint; r public.journal_entries; id_ bigint; ty text;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if st is null then raise exception 'data_needed'; end if;
  if exists (select 1 from public.journal_entries o where o.source_type = 'opening' and o.reverses_id is null and not exists (select 1 from public.journal_entries r2 where r2.reverses_id = o.id)) then raise exception 'opening_exists'; end if;
  if exists (select 1 from public.journal_entries where entry_date < st and source_type <> 'opening') then raise exception 'postings_before_opening'; end if;
  ln := public._acct_resolve(p_lines, null);
  for x in select * from jsonb_array_elements(ln) loop
    select type into ty from public.coa_accounts where id = (x->>'account_id')::bigint;
    if ty in ('income', 'expense') then raise exception 'opening_balance_sheet_only'; end if;
    td := td + (x->>'debit')::numeric; tc := tc + (x->>'credit')::numeric;
  end loop;
  diff := round(td - tc, 2);
  if diff <> 0 then
    if not coalesce(p_plug, false) then raise exception 'unbalanced' using detail = 'debit ' || td::text || ' credit ' || tc::text; end if;
    select account_id into plug from public.acct_mappings where key = 'retained';
    if plug is null then raise exception 'mapping_missing:retained'; end if;
    ln := ln || jsonb_build_object('account_id', plug, 'debit', case when diff < 0 then -diff else 0 end, 'credit', case when diff > 0 then diff else 0 end, 'party_type', null, 'party_id', null, 'memo', 'balancing figure', 'location_id', null);
    if diff > 0 then tc := tc + diff; else td := td - diff; end if;
  end if;
  if td <= 0 then raise exception 'no_lines'; end if;
  if p_dry then return jsonb_build_object('dry', true, 'date', st, 'total_debit', td, 'total_credit', tc, 'plug', diff, 'lines', jsonb_array_length(ln)); end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.journal_entries where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', r.id); end if;
  end if;
  id_ := public._acct_write(st, null, 'opening', 'opening:' || coalesce(p_client::text, gen_random_uuid()::text), null, coalesce(nullif(btrim(p_memo), ''), 'Opening balances'), null, ln, null, p_client, null);
  return jsonb_build_object('id', id_, 'date', st, 'plug', diff);
end $$;

-- ---------- reports ----------
-- balances per account (visible places only): opening net (before p_from), debits and credits inside [p_from, p_to], rolled up through the groups
create or replace function public._acct_bal(p_from date, p_to date, p_loc int) returns table(account_id bigint, open_net numeric, dr numeric, cr numeric)
language plpgsql stable security definer set search_path = public as $$
declare v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs(); f date := coalesce(p_from, date '1900-01-01');
begin
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  return query
  with recursive b as (
    select l.account_id aid,
      coalesce(sum(l.debit - l.credit) filter (where e.entry_date < f), 0) o,
      coalesce(sum(l.debit) filter (where e.entry_date >= f), 0) d, coalesce(sum(l.credit) filter (where e.entry_date >= f), 0) c
    from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
    where e.entry_date <= coalesce(p_to, date '2999-12-31')
      and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)
    group by l.account_id),
  anc(acc, anc_id) as (select a.id, a.id from public.coa_accounts a union all select n.acc, p.parent_id from anc n join public.coa_accounts p on p.id = n.anc_id where p.parent_id is not null)
  select anc.anc_id, sum(b.o), sum(b.d), sum(b.c) from anc join b on b.aid = anc.acc group by anc.anc_id;
end $$;

create or replace function public.acct_trial_balance(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); rows_ jsonb; td numeric; tc numeric; to_ date := coalesce(p_to, public._acct_today()); fr date;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  fr := coalesce(p_from, st);
  if fr > to_ then raise exception 'bad_range'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'type', a.type, 'parent_id', a.parent_id, 'is_group', a.is_group,
      'open_dr', greatest(b.open_net, 0), 'open_cr', greatest(-b.open_net, 0), 'dr', b.dr, 'cr', b.cr,
      'close_dr', greatest(b.open_net + b.dr - b.cr, 0), 'close_cr', greatest(-(b.open_net + b.dr - b.cr), 0)) order by a.code), '[]'::jsonb),
    coalesce(sum(greatest(b.open_net + b.dr - b.cr, 0)) filter (where not a.is_group), 0), coalesce(sum(greatest(-(b.open_net + b.dr - b.cr), 0)) filter (where not a.is_group), 0)
    into rows_, td, tc
    from public._acct_bal(fr, to_, p_loc) b join public.coa_accounts a on a.id = b.account_id
    where b.open_net <> 0 or b.dr <> 0 or b.cr <> 0;
  return jsonb_build_object('from', fr, 'to', to_, 'location_id', p_loc, 'rows', rows_, 'total_debit', td, 'total_credit', tc, 'balanced', td = tc, 'diff', td - tc);
end $$;

create or replace function public.acct_income_statement(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); inc jsonb; exp_ jsonb; ti numeric; te numeric; cg numeric := 0; cid bigint; to_ date := coalesce(p_to, public._acct_today()); fr date; cm bigint;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  fr := coalesce(p_from, st);
  if fr > to_ then raise exception 'bad_range'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'parent_id', a.parent_id, 'is_group', a.is_group, 'amount', (b.cr - b.dr)) order by a.code), '[]'::jsonb),
         coalesce(sum(b.cr - b.dr) filter (where not a.is_group), 0)
    into inc, ti from public._acct_bal(fr, to_, p_loc) b join public.coa_accounts a on a.id = b.account_id where a.type = 'income' and (b.dr <> 0 or b.cr <> 0);
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'parent_id', a.parent_id, 'is_group', a.is_group, 'amount', (b.dr - b.cr)) order by a.code), '[]'::jsonb),
         coalesce(sum(b.dr - b.cr) filter (where not a.is_group), 0)
    into exp_, te from public._acct_bal(fr, to_, p_loc) b join public.coa_accounts a on a.id = b.account_id where a.type = 'expense' and (b.dr <> 0 or b.cr <> 0);
  select account_id into cid from public.acct_mappings where key = 'cogs';
  select coalesce(sum(b.dr - b.cr), 0) into cg from public._acct_bal(fr, to_, p_loc) b where b.account_id = cid;
  select count(*) into cm from public.journal_entries e where e.entry_date between fr and to_ and e.flags like '%cogs_missing%' and e.reverses_id is null
    and (public._acct_all() or (e.location_id is not null and public.can_loc(e.location_id))) and (p_loc is null or e.location_id = p_loc);
  return jsonb_build_object('from', fr, 'to', to_, 'location_id', p_loc, 'income', inc, 'expense', exp_, 'total_income', ti, 'total_expense', te, 'cogs', cg,
    'gross_profit', ti - cg, 'net_profit', ti - te, 'cogs_missing', cm);
end $$;

create or replace function public.acct_balance_sheet(p_as_of date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); as_ date := coalesce(p_as_of, public._acct_today()); ass jsonb; lia jsonb; eq jsonb; ta numeric; tl numeric; te numeric; earn numeric; diff numeric; cm bigint;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'parent_id', a.parent_id, 'is_group', a.is_group, 'amount', (b.open_net + b.dr - b.cr)) order by a.code), '[]'::jsonb),
         coalesce(sum(b.open_net + b.dr - b.cr) filter (where not a.is_group), 0)
    into ass, ta from public._acct_bal(null, as_, p_loc) b join public.coa_accounts a on a.id = b.account_id where a.type = 'asset' and (b.dr <> 0 or b.cr <> 0 or b.open_net <> 0);
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'parent_id', a.parent_id, 'is_group', a.is_group, 'amount', -(b.open_net + b.dr - b.cr)) order by a.code), '[]'::jsonb),
         coalesce(sum(-(b.open_net + b.dr - b.cr)) filter (where not a.is_group), 0)
    into lia, tl from public._acct_bal(null, as_, p_loc) b join public.coa_accounts a on a.id = b.account_id where a.type = 'liability' and (b.dr <> 0 or b.cr <> 0 or b.open_net <> 0);
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'parent_id', a.parent_id, 'is_group', a.is_group, 'amount', -(b.open_net + b.dr - b.cr)) order by a.code), '[]'::jsonb),
         coalesce(sum(-(b.open_net + b.dr - b.cr)) filter (where not a.is_group), 0)
    into eq, te from public._acct_bal(null, as_, p_loc) b join public.coa_accounts a on a.id = b.account_id where a.type = 'equity' and (b.dr <> 0 or b.cr <> 0 or b.open_net <> 0);
  select coalesce(sum(-(b.open_net + b.dr - b.cr)) filter (where a.type = 'income' and not a.is_group), 0) - coalesce(sum(b.open_net + b.dr - b.cr) filter (where a.type = 'expense' and not a.is_group), 0)
    into earn from public._acct_bal(null, as_, p_loc) b join public.coa_accounts a on a.id = b.account_id;
  diff := round(ta - (tl + te + earn), 2);
  select count(*) into cm from public.journal_entries e where e.entry_date <= as_ and e.flags like '%cogs_missing%' and e.reverses_id is null
    and (public._acct_all() or (e.location_id is not null and public.can_loc(e.location_id))) and (p_loc is null or e.location_id = p_loc);
  return jsonb_build_object('as_of', as_, 'location_id', p_loc, 'assets', ass, 'liabilities', lia, 'equity', eq, 'total_assets', ta, 'total_liabilities', tl, 'total_equity', te,
    'retained_earnings', earn, 'total_equity_and_earnings', te + earn, 'total_liabilities_and_equity', tl + te + earn, 'unbalanced', diff <> 0, 'difference', diff, 'cogs_missing', cm);
end $$;

create or replace function public.acct_ledger(p_account bigint, p_from date, p_to date, p_loc int default null, p_limit int default 1000) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); a public.coa_accounts; v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs(); to_ date := coalesce(p_to, public._acct_today()); fr date; open_ numeric; rows_ jsonb;
        lim int := least(greatest(coalesce(p_limit, 1000), 1), 5000); sgn int; ids bigint[];
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  select * into a from public.coa_accounts where id = p_account;
  if not found then raise exception 'unknown_account'; end if;
  fr := coalesce(p_from, st);
  sgn := case a.normal_side when 'debit' then 1 else -1 end;
  select array(with recursive t(id) as (select p_account union all select c.id from public.coa_accounts c join t on c.parent_id = t.id) select id from t) into ids;
  select coalesce(sum(l.debit - l.credit), 0) * sgn into open_ from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
    where l.account_id = any (ids) and e.entry_date < fr and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc);
  select coalesce(jsonb_agg(jsonb_build_object('date', w.entry_date, 'entry_id', w.entry_id, 'line_no', w.line_no, 'memo', w.memo, 'line_memo', w.lmemo, 'source_type', w.source_type, 'source_id', w.source_id,
      'account_code', w.code, 'party_type', w.party_type, 'party_id', w.party_id, 'location_id', w.location_id, 'debit', w.debit, 'credit', w.credit, 'balance', w.bal, 'reversal', w.reverses_id is not null)
      order by w.entry_date, w.entry_id, w.line_no), '[]'::jsonb)
    into rows_ from (
      select z.*, open_ + sum((z.debit - z.credit) * sgn) over (order by z.entry_date, z.entry_id, z.line_no) bal from (
        select e.entry_date, e.id entry_id, l.line_no, e.memo, l.memo lmemo, e.source_type, e.source_id, e.reverses_id, ac.code, l.party_type, l.party_id, l.location_id, l.debit, l.credit
        from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.coa_accounts ac on ac.id = l.account_id
        where l.account_id = any (ids) and e.entry_date between fr and to_ and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)
        order by e.entry_date, e.id, l.line_no limit lim) z) w;
  return jsonb_build_object('account', jsonb_build_object('id', a.id, 'code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'type', a.type, 'normal_side', a.normal_side, 'is_group', a.is_group),
    'from', fr, 'to', to_, 'opening', open_, 'rows', rows_,
    'closing', case when jsonb_array_length(rows_) = 0 then open_ else (rows_ -> (jsonb_array_length(rows_) - 1) ->> 'balance')::numeric end, 'truncated', jsonb_array_length(rows_) >= lim);
end $$;

create or replace function public.acct_journal_book(p_from date, p_to date, p_loc int default null, p_limit int default 200, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); v_all boolean := public._acct_all(); rows_ jsonb; lim int := least(greatest(coalesce(p_limit, 200), 1), 1000); to_ date := coalesce(p_to, public._acct_today()); fr date; tot bigint;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  fr := coalesce(p_from, st);
  select count(*) into tot from public.journal_entries e where e.entry_date between fr and to_ and (v_all or (e.location_id is not null and public.can_loc(e.location_id))) and (p_loc is null or e.location_id = p_loc);
  select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'date', e.entry_date, 'location_id', e.location_id, 'source_type', e.source_type, 'source_id', e.source_id, 'subtype', e.subtype, 'memo', e.memo,
      'status', e.status, 'reverses_id', e.reverses_id, 'flags', e.flags, 'photo', e.photo, 'created_at', e.created_at, 'created_staff', e.created_staff,
      'lines', (select jsonb_agg(jsonb_build_object('line_no', l.line_no, 'code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', l.debit, 'credit', l.credit, 'party_type', l.party_type, 'party_id', l.party_id, 'memo', l.memo) order by l.line_no)
                from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where l.entry_id = e.id)) order by e.entry_date desc, e.id desc), '[]'::jsonb)
    into rows_ from (select * from public.journal_entries e where e.entry_date between fr and to_ and (v_all or (e.location_id is not null and public.can_loc(e.location_id))) and (p_loc is null or e.location_id = p_loc)
      order by e.entry_date desc, e.id desc limit lim offset greatest(coalesce(p_offset, 0), 0)) e;
  return jsonb_build_object('from', fr, 'to', to_, 'total', tot, 'rows', rows_);
end $$;

-- simple cash flow: the cash-like accounts (cash, bank, mobile wallets) and what moved them
create or replace function public.acct_cash_flow(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs(); ids bigint[]; to_ date := coalesce(p_to, public._acct_today()); fr date; open_ numeric; rows_ jsonb; ti numeric; tout numeric;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  fr := coalesce(p_from, st);
  select array_agg(account_id) into ids from public.acct_mappings where key in ('pay_cash', 'pay_bank', 'pay_mobile');
  select coalesce(sum(l.debit - l.credit), 0) into open_ from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
    where l.account_id = any (ids) and e.entry_date < fr and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc);
  select coalesce(jsonb_agg(jsonb_build_object('category', cat, 'in', i, 'out', o, 'net', i - o) order by cat), '[]'::jsonb), coalesce(sum(i), 0), coalesce(sum(o), 0) into rows_, ti, tout from (
    select coalesce(e.subtype, e.source_type) cat, sum(l.debit) i, sum(l.credit) o
    from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
    where l.account_id = any (ids) and e.entry_date between fr and to_ and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)
    group by 1) z;
  return jsonb_build_object('from', fr, 'to', to_, 'opening', open_, 'rows', rows_, 'total_in', ti, 'total_out', tout, 'closing', open_ + ti - tout);
end $$;

-- customer / supplier sub-ledger (the party tag on the lines)
create or replace function public.acct_party_ledger(p_type text, p_id text, p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs(); sgn int; open_ numeric; rows_ jsonb; to_ date := coalesce(p_to, public._acct_today()); fr date;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  if p_type is null or p_type not in ('customer', 'supplier', 'staff', 'partner') or p_id is null then raise exception 'bad_party'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  fr := coalesce(p_from, st);
  sgn := case p_type when 'customer' then 1 when 'staff' then 1 else -1 end;      -- a customer owes us (debit); we owe a supplier (credit)
  select coalesce(sum(l.debit - l.credit), 0) * sgn into open_ from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
    where l.party_type = p_type and l.party_id = p_id and e.entry_date < fr and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc);
  select coalesce(jsonb_agg(jsonb_build_object('date', w.entry_date, 'entry_id', w.entry_id, 'memo', w.memo, 'source_type', w.source_type, 'source_id', w.source_id, 'account_code', w.code,
      'debit', w.debit, 'credit', w.credit, 'balance', w.bal) order by w.entry_date, w.entry_id, w.line_no), '[]'::jsonb) into rows_ from (
    select z.*, open_ + sum((z.debit - z.credit) * sgn) over (order by z.entry_date, z.entry_id, z.line_no) bal from (
      select e.entry_date, e.id entry_id, l.line_no, e.memo, e.source_type, e.source_id, a.code, l.debit, l.credit
      from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.coa_accounts a on a.id = l.account_id
      where l.party_type = p_type and l.party_id = p_id and e.entry_date between fr and to_ and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)
      order by e.entry_date, e.id, l.line_no limit 2000) z) w;
  return jsonb_build_object('party_type', p_type, 'party_id', p_id, 'from', fr, 'to', to_, 'opening', open_, 'rows', rows_,
    'closing', case when jsonb_array_length(rows_) = 0 then open_ else (rows_ -> (jsonb_array_length(rows_) - 1) ->> 'balance')::numeric end);
end $$;

-- the sub-ledgers against the existing customer / supplier balances (differences only)
create or replace function public.acct_reconcile(p_kind text default 'all') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); cust jsonb := '[]'; sup jsonb := '[]'; unattr numeric := 0; nc int := 0; ns int := 0; ar bigint; ap bigint; adv bigint;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if not public._acct_all() then raise exception 'not allowed'; end if;           -- a reconciliation covers every place: owner / management only
  if st is null then return jsonb_build_object('data_needed', true); end if;
  select account_id into ar from public.acct_mappings where key = 'receivable';
  select account_id into ap from public.acct_mappings where key = 'payable';
  select account_id into adv from public.acct_mappings where key = 'cust_advance';
  if p_kind in ('all', 'customer') then
    select coalesce(jsonb_agg(jsonb_build_object('party_id', x.pid, 'name', x.nm, 'journal', x.j, 'existing', x.l, 'advance_applied', x.av, 'difference', x.j - x.l, 'unexplained', x.j - x.l + x.av) order by abs(x.j - x.l + x.av) desc), '[]'::jsonb), count(*)
      into cust, nc from (
      select c.id::text pid, c.name nm, coalesce(j.bal, 0) j, coalesce(public._cust_bal(c.id), 0) l,
             coalesce((select sum(m.amount) from public.cash_moves m where m.customer_id = c.id and m.kind = 'cust_advance_used' and m.status = 'done' and m.move_date >= st), 0) av
      from public.customers c left join (select party_id, sum(debit - credit) bal from public.journal_lines where account_id = ar and party_type = 'customer' group by party_id) j on j.party_id = c.id::text
      where coalesce(j.bal, 0) <> 0 or coalesce(public._cust_bal(c.id), 0) <> 0) x
      where abs(x.j - x.l + x.av) > 0.005;
    select coalesce(sum(debit - credit), 0) into unattr from public.journal_lines where account_id = ar and party_id is null;
  end if;
  if p_kind in ('all', 'supplier') then
    select coalesce(jsonb_agg(jsonb_build_object('party_id', x.pid, 'name', x.nm, 'journal', x.j, 'existing', x.l, 'difference', x.j - x.l, 'unexplained', x.j - x.l) order by abs(x.j - x.l) desc), '[]'::jsonb), count(*)
      into sup, ns from (
      select s.id::text pid, s.name nm, coalesce(j.bal, 0) j, coalesce(public._sup_balance(s.id), 0) l
      from public.suppliers s left join (select party_id, sum(credit - debit) bal from public.journal_lines where account_id = ap and party_type = 'supplier' group by party_id) j on j.party_id = s.id::text
      where coalesce(j.bal, 0) <> 0 or coalesce(public._sup_balance(s.id), 0) <> 0) x
      where abs(x.j - x.l) > 0.005;
  end if;
  return jsonb_build_object('start', st, 'customers', cust, 'customers_off', nc, 'suppliers', sup, 'suppliers_off', ns, 'unattributed_receivable', unattr,
    'note', 'A difference equal to a balance that existed before the start date means that party has no opening balance in the books yet.');
end $$;

-- one call for the overview page
create or replace function public.acct_overview(p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); t date := public._acct_today(); bs jsonb; isx jsonb; pend jsonb;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true, 'on', public.rule_on('accounting_on')); end if;
  bs := public.acct_balance_sheet(t, p_loc);
  isx := public.acct_income_statement(greatest(date_trunc('month', t)::date, st), t, p_loc);
  return jsonb_build_object('start', st, 'on', public.rule_on('accounting_on'), 'balance_sheet', jsonb_build_object('total_assets', bs->'total_assets', 'total_liabilities', bs->'total_liabilities',
      'total_equity', bs->'total_equity_and_earnings', 'unbalanced', bs->'unbalanced', 'difference', bs->'difference', 'cogs_missing', bs->'cogs_missing'),
    'income_month', jsonb_build_object('total_income', isx->'total_income', 'total_expense', isx->'total_expense', 'net_profit', isx->'net_profit', 'cogs', isx->'cogs', 'gross_profit', isx->'gross_profit', 'from', isx->'from'),
    'status', public.acct_status());
end $$;

-- ---------- grants ----------
revoke all on function public._acct_ro(), public._acct_balance_chk(), public._acct_coa_guard() from public, anon, authenticated;
revoke all on function public._acct_view(), public._acct_manage(), public._acct_all(), public._acct_locs(), public._acct_start(), public._acct_today(), public._acct_locked(date) from public, anon, authenticated;
revoke all on function public._acct_num(text), public._acct_inv_key(text), public._acct_buy_key(text), public._acct_paykey(text, boolean), public._acct_need(text, text, boolean), public._acct_purchase_alloc(uuid) from public, anon, authenticated;
revoke all on function public._acct_docs(date), public._acct_resolve(jsonb, int), public._acct_merge(jsonb), public._acct_bal(date, date, int) from public, anon, authenticated;
revoke all on function public._acct_write(date, int, text, text, text, text, text, jsonb, bigint, uuid, text), public._acct_reverse(bigint, date, text, uuid) from public, anon, authenticated;
revoke all on function public.acct_status(), public.acct_set_start(date), public.acct_account_save(bigint, text, text, text, text, bigint, boolean, int, boolean), public.acct_mapping_set(text, bigint),
  public.acct_post_pending(boolean, int), public.acct_journal_post(date, int, text, jsonb, uuid, text, boolean), public.acct_journal_reverse(bigint, text, uuid),
  public.acct_opening(jsonb, boolean, text, uuid, boolean), public.acct_trial_balance(date, date, int), public.acct_income_statement(date, date, int), public.acct_balance_sheet(date, int),
  public.acct_ledger(bigint, date, date, int, int), public.acct_journal_book(date, date, int, int, int), public.acct_cash_flow(date, date, int),
  public.acct_party_ledger(text, text, date, date, int), public.acct_reconcile(text), public.acct_overview(int) from public, anon;
grant execute on function public.acct_status(), public.acct_set_start(date), public.acct_account_save(bigint, text, text, text, text, bigint, boolean, int, boolean), public.acct_mapping_set(text, bigint),
  public.acct_post_pending(boolean, int), public.acct_journal_post(date, int, text, jsonb, uuid, text, boolean), public.acct_journal_reverse(bigint, text, uuid),
  public.acct_opening(jsonb, boolean, text, uuid, boolean), public.acct_trial_balance(date, date, int), public.acct_income_statement(date, date, int), public.acct_balance_sheet(date, int),
  public.acct_ledger(bigint, date, date, int, int), public.acct_journal_book(date, date, int, int, int), public.acct_cash_flow(date, date, int),
  public.acct_party_ledger(text, text, date, date, int), public.acct_reconcile(text), public.acct_overview(int) to authenticated;

-- the read policies call this one as the caller (it only answers yes / no about the caller)
grant execute on function public._acct_view(), public._acct_all() to authenticated;

-- ---------------------------------------------------------------- phase41.sql
-- ============================================================
-- PHASE 41 (module B1): EMPLOYEES - registration, pay structure, facilities, documents, roles and DEEDS.
-- Additive and idempotent (paste twice = no error). Needs phase8..phase28 (uses phase11/15 no_hard_delete, norm_mobile, log_change,
-- is_active / is_owner / can_loc / has_grant, rules, grant_defs, rule_grants, option_lists / list_defs). Depends on no other new phase.
-- Nothing is deleted: people, pay versions, deeds, documents are retired by a status / void flag; records are append-only or guarded by triggers.
-- Rule switches: employees_module_on (ON), employee_mobile_unique (ON), deed_expiry_warn_days (30).
--
-- ---------------------------------------------------------------------------------------------------------------------------
-- SCHEMA CHEAT SHEET FOR THE NEXT MODULE (B2 attendance / payroll).  Today in all code = (now() at time zone 'Asia/Dhaka')::date.
-- ---------------------------------------------------------------------------------------------------------------------------
-- WHO IS AN EMPLOYEE:  public.employees  where status in ('active','on_leave')   ('draft' = wizard not finished, 'discarded' = abandoned draft;
--   neither is a person yet). resigned / terminated / retired are kept for history.
--   employees(id uuid pk, client_id uuid unique, employee_no text unique  -- 'E-0001'.. assigned when the draft is submitted, immutable, never reused
--     , full_name_bn, full_name_en, nickname, photo_path (Storage path EMP/<loc>/<id>.jpg in the private bucket 'photos'), gender male|female|other,
--     date_of_birth, blood_group, nid_no (digits only, unique), mobile (01XXXXXXXXX via norm_mobile), email, present_address, permanent_address,
--     emergency_name, emergency_relation, emergency_mobile, marital_status single|married|divorced|widowed, education, joining_date, probation_end,
--     designation text (code of option_lists 'emp_designation' or free text), department text (option_lists 'emp_department'),
--     primary_location_id int -> locations, primary_role_code -> staff_roles(code),
--     employment_type permanent|contract|daily|part_time|trainee,
--     status draft|active|on_leave|resigned|terminated|retired|discarded, status_date, status_reason,
--     profile_id uuid unique -> profiles (login account, optional), device_user_id text unique (fingerprint device id),
--     bank_account, mobile_wallet   -- PAY ACCOUNT: column NOT selectable by the browser; read with employee_pay_account_get() (salary_view)
--     , notes, created_by, created_at, updated_by, updated_at)
--   employee_locations(employee_id, location_id, active, added_by, added_at)  -- other places the person may work (primary one is on employees)
--   employee_status_log(id, employee_id, from_status, to_status, status_date, reason, by, at)   -- append-only history of status changes
--   employee_documents(id, employee_id, kind nid|contract|cv|certificate|guarantor|photo|other, file_path (EMPDOC/<loc>/.. or EMP/<loc>/..), note, uploaded_by, uploaded_at, void, void_by/at/reason)
-- PAY (salary-sensitive: rows are visible ONLY to the owner or a holder of grant salary_view at the person's location; writes owner / salary_manage):
--   employee_pay(id, employee_id, effective_from, pay_basis monthly|daily|hourly, basic, ot_rule none|rate_per_hour|multiple_of_hourly, ot_value
--     (amount per hour, or the multiple e.g. 1.5 / 2.0), ot_hours_basis (hours in a normal day, 8), bonus_rules jsonb
--     [{name, months_of_basic, min_service_months}], note, client_id, created_by, created_at)      -- APPEND-ONLY. CURRENT = latest effective_from <= today, ties -> highest id
--   employee_pay_components(id, pay_id -> employee_pay, kind allowance|deduction, name, amount | percent_of_basic (exactly one), taxable, active)
--     -- amount of a percent line = round(basic * percent / 100, 2). gross = basic + allowances; net = gross - deductions.
--   Helper for server code (not callable from the browser): public._emp_pay_on(employee uuid, date) returns the employee_pay row in force on that date;
--     public._emp_pay_json(pay_id) returns it with computed lines. Browser: employee_pay_current(emp [, on date]), employee_pay_history(emp).
--   employee_benefits(id, employee_id, kind meal|uniform|accommodation|transport|phone|insurance|other, description, value_per_month (column hidden
--     from the browser; employee_benefits_list() shows it to salary_view only), from_date, to_date, active)
--   leave_types(code, name_bn, name_en, paid, default_days, active, sort) seeded annual / sick / casual / unpaid / maternity / paternity
--   employee_leave_entitlements(id, employee_id, leave_type -> leave_types, days_per_year)   unique(employee_id, leave_type)
-- ROLES AND DEEDS:
--   staff_roles(code, name_bn, name_en, major, description, active, sort)   -- job roles (NOT the login roles of table roles)
--   deed_templates(id, family_id, version, role_code, title_bn, title_en, clauses jsonb, active, created_by, created_at)  -- content immutable, a change = new version
--     clauses = [{no, text_bn, text_en, kind rule|amount|duration|text, value, unit}]
--   employee_deeds(id, client_id, employee_id, template_id, role_code, title, clauses, start_date, end_date, probation_days, notice_days, security_deposit,
--     guarantor_name, guarantor_mobile, guarantor_nid, status draft|active|expired|terminated|superseded, signed_at, signed_doc_path,
--     revision_no, supersedes_id, created_by/at, activated_by/at, ended_by/at, end_reason)
--     -- immutable once active; a change = deed_revise() (new draft, revision_no + 1, supersedes_id) then deed_activate() which marks the old one superseded.
--     -- one ACTIVE deed per (employee, role) (partial unique index).
-- GRANTS (grant_defs): employee_view (see staff of own places, no pay; given by default to roles management / showroom_manager / factory_incharge),
--   employee_manage (register / edit / documents / draft deeds), salary_view (existing), salary_manage (write pay, accounts, benefit values), deed_manage (templates, activate / end deeds).
--   The owner passes all. Access is always scoped by the person's location (can_loc + has_grant(code, location)).
-- BROWSER FUNCTIONS: employee_save, employee_submit, employee_discard, employee_status_set, employee_locations_set, employee_link_profile, employee_set_photo,
--   employee_dup_check, employee_doc_add / employee_doc_void, employee_pay_set (p_dry = preview), employee_pay_current / _history, employee_pay_account_set / _get,
--   leave_entitlement_set, employee_benefit_save / _end / employee_benefits_list, staff_role_save, deed_template_save / _retire, deed_save, deed_revise,
--   deed_activate, deed_end, deed_attach_signed, deed_expire_due, deeds_expiring(days).
-- ============================================================

-- ---------- rules and grants ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('employees_module_on', 'people', 'switch', 'true', null, null, null, null, 'কর্মচারী নিবন্ধন (নতুন যোগ / বদল) চালু', 'Employee নিবন্ধন (নতুন যোগ / বদল) চালু', 'Employee registration (add / change) is on',
  'বন্ধ করলে কেউ নতুন কর্মচারী যোগ বা তথ্য বদলাতে পারবে না; দেখা চলবে।', 'Off = nobody can add or change employees; viewing still works.', 160),
 ('employee_mobile_unique', 'people', 'switch', 'true', null, null, null, null, 'একই মোবাইল দুই কর্মচারীতে নয়', 'একই mobile দুই employee-তে নয়', 'One mobile number per employee',
  'চালু = আগে থেকে থাকা নম্বরে নতুন কর্মচারী সংরক্ষণ হবে না। বন্ধ = শুধু সতর্কবার্তা।', 'On = a number already used by another employee is refused. Off = only a warning.', 161),
 ('deed_expiry_warn_days', 'people', 'number', '30', 'days', null, 1, 365, 'চুক্তি (ডিড) শেষ হওয়ার কত দিন আগে সতর্ক করবে', 'Deed শেষ হওয়ার কত দিন আগে সতর্ক করবে', 'Warn this many days before a deed ends',
  null, null, 162)
 on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select v.c, 'people', v.s, v.bn, v.mx, v.en, 'window', null
from (values
 ('employee_view', 70, 'কর্মচারীর তথ্য দেখা (বেতন ছাড়া)', 'Employee-র তথ্য দেখা (salary ছাড়া)', 'See employee records (no pay)'),
 ('employee_manage', 71, 'কর্মচারী নিবন্ধন ও তথ্য বদল', 'Employee নিবন্ধন ও তথ্য বদল', 'Register and edit employees'),
 ('salary_manage', 72, 'বেতন কাঠামো বদলানো', 'Salary কাঠামো বদলানো', 'Set pay structures'),
 ('deed_manage', 73, 'ডিড টেমপ্লেট ও ডিড চালু/শেষ করা', 'Deed template ও deed চালু/শেষ করা', 'Manage deed templates, activate / end deeds')
) as v(c, s, bn, mx, en)
where not exists (select 1 from public.grant_defs g where g.grant_code = v.c);

insert into public.rule_grants (grant_code, role_code)
select 'employee_view', r.code from public.roles r where r.code in ('management', 'showroom_manager', 'factory_incharge')
on conflict do nothing;

-- ---------- lists (designation / department) ----------
insert into public.list_defs (list_code, add_rule) values ('emp_designation', 'owner'), ('emp_department', 'owner') on conflict (list_code) do nothing;
insert into public.option_lists (list_code, value_code, label_bn, label_en, sort) values
 ('emp_designation', 'manager', 'ম্যানেজার', 'Manager', 1), ('emp_designation', 'cashier', 'ক্যাশিয়ার', 'Cashier', 2), ('emp_designation', 'salesperson', 'সেলসম্যান', 'Salesperson', 3),
 ('emp_designation', 'storekeeper', 'স্টোরকিপার', 'Storekeeper', 4), ('emp_designation', 'factory_incharge', 'কারখানা ইনচার্জ', 'Factory in-charge', 5),
 ('emp_designation', 'head_artisan', 'প্রধান কারিগর', 'Head artisan (Karigor)', 6), ('emp_designation', 'artisan', 'কারিগর', 'Artisan', 7),
 ('emp_designation', 'helper', 'হেল্পার', 'Helper', 8), ('emp_designation', 'delivery', 'ডেলিভারি', 'Delivery', 9), ('emp_designation', 'accountant', 'হিসাবরক্ষক', 'Accountant', 10),
 ('emp_designation', 'guard', 'গার্ড', 'Guard', 11), ('emp_designation', 'cleaner', 'ক্লিনার', 'Cleaner', 12),
 ('emp_department', 'showroom', 'শোরুম', 'Showroom', 1), ('emp_department', 'factory', 'কারখানা', 'Factory', 2), ('emp_department', 'store', 'স্টোর', 'Store', 3),
 ('emp_department', 'accounts', 'হিসাব', 'Accounts', 4), ('emp_department', 'delivery', 'ডেলিভারি', 'Delivery', 5), ('emp_department', 'admin', 'প্রশাসন', 'Admin', 6)
 on conflict (list_code, value_code) do nothing;

-- ---------- core: roles, leave types ----------
create table if not exists public.staff_roles (
  code text primary key check (code ~ '^[a-z][a-z0-9_]{1,40}$'),
  name_bn text not null, name_en text not null, major boolean not null default false, description text,
  active boolean not null default true, sort int not null default 0
);
insert into public.staff_roles (code, name_bn, name_en, major, description, sort) values
 ('manager', 'ম্যানেজার (মালিকের প্রতিনিধি)', 'Manager (owner''s representative)', true, 'Runs a place on behalf of the owner', 1),
 ('cashier', 'ক্যাশিয়ার', 'Cashier', true, 'Handles cash', 2),
 ('salesperson', 'বিক্রয়কর্মী', 'Salesperson', false, 'Sells to customers', 3),
 ('storekeeper', 'স্টোরকিপার', 'Storekeeper', true, 'Responsible for stock', 4),
 ('factory_incharge', 'কারখানা ইনচার্জ', 'Factory in-charge', true, 'Runs production', 5),
 ('head_artisan', 'প্রধান কারিগর', 'Head artisan / Karigor', true, 'Leads the artisans', 6),
 ('helper', 'হেল্পার', 'Helper', false, null, 7),
 ('delivery', 'ডেলিভারি', 'Delivery', false, null, 8),
 ('accountant', 'হিসাবরক্ষক', 'Accountant', true, 'Keeps the books', 9),
 ('guard', 'গার্ড', 'Guard', false, null, 10),
 ('cleaner', 'ক্লিনার', 'Cleaner', false, null, 11)
 on conflict (code) do nothing;

create table if not exists public.leave_types (
  code text primary key, name_bn text not null, name_en text not null, paid boolean not null, default_days numeric not null default 0 check (default_days between 0 and 366),
  active boolean not null default true, sort int not null default 0
);
-- default_days are SUGGESTIONS only (the wizard pre-fills them, the owner edits); verify against the Bangladesh Labour Act before relying on them
insert into public.leave_types (code, name_bn, name_en, paid, default_days, sort) values
 ('annual', 'বার্ষিক ছুটি (বেতনসহ)', 'Annual leave (paid)', true, 0, 1), ('sick', 'অসুস্থতার ছুটি (বেতনসহ)', 'Sick leave (paid)', true, 14, 2),
 ('casual', 'নৈমিত্তিক ছুটি (বেতনসহ)', 'Casual leave (paid)', true, 10, 3), ('unpaid', 'বিনা বেতনের ছুটি', 'Unpaid leave', false, 0, 4),
 ('maternity', 'মাতৃত্বকালীন ছুটি', 'Maternity leave', true, 112, 5), ('paternity', 'পিতৃত্বকালীন ছুটি', 'Paternity leave', true, 0, 6)
 on conflict (code) do nothing;

-- ---------- employees ----------
create sequence if not exists public.employee_no_seq;
revoke all on sequence public.employee_no_seq from public, anon, authenticated;

create table if not exists public.employees (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  employee_no text unique,
  full_name_bn text not null check (char_length(btrim(full_name_bn)) between 1 and 120),
  full_name_en text, nickname text,
  photo_path text check (photo_path is null or photo_path ~ '^EMP/[0-9]+/[A-Za-z0-9_.-]{1,120}$'),
  gender text check (gender in ('male', 'female', 'other')),
  date_of_birth date, blood_group text check (blood_group in ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-')),
  nid_no text check (nid_no is null or nid_no ~ '^([0-9]{10}|[0-9]{13}|[0-9]{17})$'),
  mobile text, email text, present_address text, permanent_address text,
  emergency_name text, emergency_relation text, emergency_mobile text,
  marital_status text check (marital_status in ('single', 'married', 'divorced', 'widowed')), education text,
  joining_date date, probation_end date, designation text, department text,
  primary_location_id int references public.locations(id), primary_role_code text references public.staff_roles(code),
  employment_type text not null default 'permanent' check (employment_type in ('permanent', 'contract', 'daily', 'part_time', 'trainee')),
  status text not null default 'draft' check (status in ('draft', 'active', 'on_leave', 'resigned', 'terminated', 'retired', 'discarded')),
  status_date date, status_reason text,
  profile_id uuid unique references public.profiles(id),
  device_user_id text, bank_account text, mobile_wallet text, notes text,
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now()
);
create unique index if not exists employees_nid_uq on public.employees (nid_no) where nid_no is not null;
create unique index if not exists employees_device_uq on public.employees (device_user_id) where device_user_id is not null;
create index if not exists employees_loc on public.employees (primary_location_id, status);
create index if not exists employees_mobile on public.employees (mobile) where mobile is not null;

create table if not exists public.employee_locations (
  employee_id uuid not null references public.employees(id), location_id int not null references public.locations(id),
  active boolean not null default true, added_by uuid, added_at timestamptz not null default now(), primary key (employee_id, location_id)
);
create table if not exists public.employee_status_log (
  id bigserial primary key, employee_id uuid not null references public.employees(id), from_status text, to_status text not null,
  status_date date, reason text, by uuid, at timestamptz not null default now()
);
create index if not exists employee_status_log_emp on public.employee_status_log (employee_id, id);
create table if not exists public.employee_documents (
  id bigserial primary key, client_id uuid unique, employee_id uuid not null references public.employees(id),
  kind text not null check (kind in ('nid', 'contract', 'cv', 'certificate', 'guarantor', 'photo', 'other')),
  file_path text not null check (file_path ~ '^(EMP|EMPDOC)/[0-9]+/[A-Za-z0-9_.-]{1,120}$'), note text,
  uploaded_by uuid, uploaded_at timestamptz not null default now(), void boolean not null default false, void_by uuid, void_at timestamptz, void_reason text
);
create index if not exists employee_documents_emp on public.employee_documents (employee_id);

-- ---------- pay ----------
create table if not exists public.employee_pay (
  id bigserial primary key, client_id uuid unique, employee_id uuid not null references public.employees(id), effective_from date not null,
  pay_basis text not null check (pay_basis in ('monthly', 'daily', 'hourly')), basic numeric not null check (basic > 0 and basic <= 1000000000000),
  ot_rule text not null default 'none' check (ot_rule in ('none', 'rate_per_hour', 'multiple_of_hourly')),
  ot_value numeric check (ot_value is null or (ot_value > 0 and ot_value <= 1000000)),
  ot_hours_basis numeric not null default 8 check (ot_hours_basis between 1 and 24),
  bonus_rules jsonb not null default '[]', note text, created_by uuid, created_at timestamptz not null default now(),
  check ((ot_rule = 'none') = (ot_value is null))
);
create index if not exists employee_pay_emp on public.employee_pay (employee_id, effective_from desc, id desc);
create table if not exists public.employee_pay_components (
  id bigserial primary key, pay_id bigint not null references public.employee_pay(id), kind text not null check (kind in ('allowance', 'deduction')),
  name text not null check (char_length(btrim(name)) between 1 and 60), amount numeric check (amount is null or (amount >= 0 and amount <= 1000000000000)),
  percent_of_basic numeric check (percent_of_basic is null or (percent_of_basic >= 0 and percent_of_basic <= 100)),
  taxable boolean not null default false, active boolean not null default true,
  check ((amount is null) <> (percent_of_basic is null))
);
create index if not exists employee_pay_components_pay on public.employee_pay_components (pay_id);

create table if not exists public.employee_benefits (
  id bigserial primary key, client_id uuid unique, employee_id uuid not null references public.employees(id),
  kind text not null check (kind in ('meal', 'uniform', 'accommodation', 'transport', 'phone', 'insurance', 'other')), description text,
  value_per_month numeric check (value_per_month is null or (value_per_month >= 0 and value_per_month <= 1000000000000)),
  from_date date not null, to_date date, active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now(),
  check (to_date is null or to_date >= from_date)
);
create index if not exists employee_benefits_emp on public.employee_benefits (employee_id);
create table if not exists public.employee_leave_entitlements (
  id bigserial primary key, employee_id uuid not null references public.employees(id), leave_type text not null references public.leave_types(code),
  days_per_year numeric not null check (days_per_year between 0 and 366), updated_by uuid, updated_at timestamptz not null default now(), unique (employee_id, leave_type)
);

-- ---------- deeds ----------
create table if not exists public.deed_templates (
  id bigserial primary key, client_id uuid unique, family_id bigint not null, version int not null check (version >= 1), role_code text not null references public.staff_roles(code),
  title_bn text not null, title_en text, clauses jsonb not null default '[]', active boolean not null default true, created_by uuid, created_at timestamptz not null default now(),
  unique (family_id, version)
);
create table if not exists public.employee_deeds (
  id bigserial primary key, client_id uuid unique, employee_id uuid not null references public.employees(id), template_id bigint references public.deed_templates(id),
  role_code text not null references public.staff_roles(code), title text not null, clauses jsonb not null default '[]',
  start_date date, end_date date, probation_days int check (probation_days between 0 and 365), notice_days int check (notice_days between 0 and 365),
  security_deposit numeric check (security_deposit is null or (security_deposit >= 0 and security_deposit <= 1000000000000)),
  guarantor_name text, guarantor_mobile text, guarantor_nid text,
  status text not null default 'draft' check (status in ('draft', 'active', 'expired', 'terminated', 'superseded')),
  signed_at date, signed_doc_path text check (signed_doc_path is null or signed_doc_path ~ '^EMPDOC/[0-9]+/[A-Za-z0-9_.-]{1,120}$'),
  revision_no int not null default 1, supersedes_id bigint references public.employee_deeds(id),
  created_by uuid, created_at timestamptz not null default now(), activated_by uuid, activated_at timestamptz, ended_by uuid, ended_at timestamptz, end_reason text,
  check (end_date is null or start_date is null or end_date >= start_date)
);
create unique index if not exists employee_deeds_one_active on public.employee_deeds (employee_id, role_code) where status = 'active';
create unique index if not exists employee_deeds_one_revision on public.employee_deeds (supersedes_id) where supersedes_id is not null and status in ('draft', 'active');
create index if not exists employee_deeds_emp on public.employee_deeds (employee_id);

-- ---------- triggers: number, immutability, no delete, audit ----------
create or replace function public._emp_no_set() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and old.employee_no is not null and new.employee_no is distinct from old.employee_no then raise exception 'employee_no_immutable'; end if;
  if new.employee_no is null and new.status not in ('draft', 'discarded') then new.employee_no := 'E-' || lpad(nextval('public.employee_no_seq')::text, 4, '0'); end if;
  if tg_op = 'INSERT' and new.employee_no is not null and new.status in ('draft', 'discarded') then new.employee_no := null; end if;
  return new;
end $$;
drop trigger if exists employees_no on public.employees;
create trigger employees_no before insert or update on public.employees for each row execute function public._emp_no_set();

create or replace function public._append_only41() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end $$;
drop trigger if exists employee_pay_ro on public.employee_pay;
create trigger employee_pay_ro before update or delete on public.employee_pay for each row execute function public._append_only41();
drop trigger if exists employee_status_log_ro on public.employee_status_log;
create trigger employee_status_log_ro before update or delete on public.employee_status_log for each row execute function public._append_only41();

-- pay components: only the active flag may change
create or replace function public._pay_comp_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end if;
  if (to_jsonb(new) - 'active') is distinct from (to_jsonb(old) - 'active') then raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end if;
  return new;
end $$;
drop trigger if exists employee_pay_components_ro on public.employee_pay_components;
create trigger employee_pay_components_ro before update or delete on public.employee_pay_components for each row execute function public._pay_comp_guard();

-- deed templates: only the active flag may change (a new version is a new row)
create or replace function public._deed_tpl_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end if;
  if (to_jsonb(new) - 'active') is distinct from (to_jsonb(old) - 'active') then raise exception 'template_immutable: make a new version'; end if;
  return new;
end $$;
drop trigger if exists deed_templates_ro on public.deed_templates;
create trigger deed_templates_ro before update or delete on public.deed_templates for each row execute function public._deed_tpl_guard();

-- deeds: a draft is free; once active only the end of life may be written (status, ended_*, end_reason) and a signed scan may be attached once
create or replace function public._deed_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end if;
  if old.status = 'draft' then
    if new.status not in ('draft', 'active', 'terminated') then raise exception 'deed_bad_status'; end if;
    return new;
  end if;
  if old.status <> 'active' then raise exception 'deed_immutable: this deed is %', old.status; end if;
  if new.status not in ('active', 'expired', 'terminated', 'superseded') then raise exception 'deed_bad_status'; end if;
  if (to_jsonb(new) - array['status', 'ended_by', 'ended_at', 'end_reason', 'signed_doc_path']) is distinct from (to_jsonb(old) - array['status', 'ended_by', 'ended_at', 'end_reason', 'signed_doc_path'])
     or (old.signed_doc_path is not null and new.signed_doc_path is distinct from old.signed_doc_path) then
    raise exception 'deed_immutable: an active deed cannot be changed - make a revision';
  end if;
  return new;
end $$;
drop trigger if exists employee_deeds_guard on public.employee_deeds;
create trigger employee_deeds_guard before update or delete on public.employee_deeds for each row execute function public._deed_guard();

do $$
declare t text;
begin
  foreach t in array array['employees', 'employee_locations', 'employee_documents', 'employee_benefits', 'employee_leave_entitlements', 'staff_roles', 'leave_types', 'employee_deeds', 'deed_templates'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
  end loop;
end $$;
drop trigger if exists audit_employees on public.employees;
create trigger audit_employees after insert or update on public.employees for each row execute function public.log_change('id');
drop trigger if exists audit_employee_locations on public.employee_locations;
create trigger audit_employee_locations after insert or update on public.employee_locations for each row execute function public.log_change('employee_id,location_id');
drop trigger if exists audit_employee_documents on public.employee_documents;
create trigger audit_employee_documents after insert or update on public.employee_documents for each row execute function public.log_change('id');
drop trigger if exists audit_employee_pay on public.employee_pay;
create trigger audit_employee_pay after insert on public.employee_pay for each row execute function public.log_change('id');
drop trigger if exists audit_employee_pay_components on public.employee_pay_components;
create trigger audit_employee_pay_components after insert or update on public.employee_pay_components for each row execute function public.log_change('id');
drop trigger if exists audit_employee_benefits on public.employee_benefits;
create trigger audit_employee_benefits after insert or update on public.employee_benefits for each row execute function public.log_change('id');
drop trigger if exists audit_employee_leave on public.employee_leave_entitlements;
create trigger audit_employee_leave after insert or update on public.employee_leave_entitlements for each row execute function public.log_change('id');
drop trigger if exists audit_staff_roles on public.staff_roles;
create trigger audit_staff_roles after insert or update on public.staff_roles for each row execute function public.log_change('code');
drop trigger if exists audit_deed_templates on public.deed_templates;
create trigger audit_deed_templates after insert or update on public.deed_templates for each row execute function public.log_change('id');
drop trigger if exists audit_employee_deeds on public.employee_deeds;
create trigger audit_employee_deeds after insert or update on public.employee_deeds for each row execute function public.log_change('id');

-- ---------- access helpers (also used by the policies, so authenticated may execute them; they only answer about the caller) ----------
-- may the caller act on this employee with any of these grants? Scoped by the person's primary location (and, for viewing, the other places they work).
create or replace function public._emp_ok(p_emp uuid, p_codes text[], p_secondary boolean default false) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or exists (
    select 1 from public.employees e
    cross join lateral (select e.primary_location_id as l
                        union select el.location_id from public.employee_locations el where p_secondary and el.employee_id = e.id and el.active) x
    cross join unnest(p_codes) c
    where e.id = p_emp and x.l is not null and public.can_loc(x.l) and public.has_grant(c, x.l)));
$$;
-- may the caller use this grant at some place (for things without a location: templates, lists)?
create or replace function public._emp_any(p_codes text[]) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or exists (
    select 1 from public.locations l cross join unnest(p_codes) c where public.can_loc(l.id) and public.has_grant(c, l.id)));
$$;
create or replace function public._loc_ok(p_loc int, p_code text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and p_loc is not null and (public.is_owner() or (public.can_loc(p_loc) and public.has_grant(p_code, p_loc)));
$$;

-- ---------- RLS: reads only; every write goes through the functions below ----------
do $$
declare t text;
begin
  foreach t in array array['employees', 'employee_locations', 'employee_status_log', 'employee_documents', 'employee_pay', 'employee_pay_components', 'employee_benefits',
                           'employee_leave_entitlements', 'staff_roles', 'leave_types', 'deed_templates', 'employee_deeds'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;

drop policy if exists employees_read on public.employees;
create policy employees_read on public.employees for select to authenticated using (
  public.is_active() and (public.is_owner() or profile_id = auth.uid() or (status = 'draft' and created_by = auth.uid())
    or public._emp_ok(id, array['employee_view', 'employee_manage'], true)));
-- the pay account columns are NOT selectable: employee_pay_account_get() (salary_view) is the only way
do $$
declare cols text;
begin
  select string_agg(quote_ident(column_name), ', ' order by ordinal_position) into cols from information_schema.columns
   where table_schema = 'public' and table_name = 'employees' and column_name not in ('bank_account', 'mobile_wallet');
  execute 'revoke all on public.employees from authenticated';
  execute 'grant select (' || cols || ') on public.employees to authenticated';
end $$;

drop policy if exists employee_locations_read on public.employee_locations;
create policy employee_locations_read on public.employee_locations for select to authenticated using (public._emp_ok(employee_id, array['employee_view', 'employee_manage'], true));
drop policy if exists employee_status_log_read on public.employee_status_log;
create policy employee_status_log_read on public.employee_status_log for select to authenticated using (public._emp_ok(employee_id, array['employee_view', 'employee_manage'], true));
drop policy if exists employee_documents_read on public.employee_documents;
create policy employee_documents_read on public.employee_documents for select to authenticated using (public._emp_ok(employee_id, array['employee_manage']));
drop policy if exists employee_pay_read on public.employee_pay;
create policy employee_pay_read on public.employee_pay for select to authenticated using (public._emp_ok(employee_id, array['salary_view']));
drop policy if exists employee_pay_components_read on public.employee_pay_components;
create policy employee_pay_components_read on public.employee_pay_components for select to authenticated
  using (exists (select 1 from public.employee_pay p where p.id = pay_id and public._emp_ok(p.employee_id, array['salary_view'])));
drop policy if exists employee_benefits_read on public.employee_benefits;
create policy employee_benefits_read on public.employee_benefits for select to authenticated using (public._emp_ok(employee_id, array['employee_view', 'employee_manage'], true));
drop policy if exists employee_leave_read on public.employee_leave_entitlements;
create policy employee_leave_read on public.employee_leave_entitlements for select to authenticated using (public._emp_ok(employee_id, array['employee_view', 'employee_manage'], true));
drop policy if exists staff_roles_read on public.staff_roles;
create policy staff_roles_read on public.staff_roles for select to authenticated using (public.is_active());
drop policy if exists leave_types_read on public.leave_types;
create policy leave_types_read on public.leave_types for select to authenticated using (public.is_active());
drop policy if exists deed_templates_read on public.deed_templates;
create policy deed_templates_read on public.deed_templates for select to authenticated using (public._emp_any(array['deed_manage', 'employee_manage']));
drop policy if exists employee_deeds_read on public.employee_deeds;
create policy employee_deeds_read on public.employee_deeds for select to authenticated using (public._emp_ok(employee_id, array['employee_manage', 'deed_manage']));

grant select on public.employee_locations, public.employee_status_log, public.employee_documents, public.employee_pay, public.employee_pay_components,
  public.employee_leave_entitlements, public.staff_roles, public.leave_types, public.deed_templates, public.employee_deeds to authenticated;
-- the monthly value of a facility is pay information
grant select (id, client_id, employee_id, kind, description, from_date, to_date, active, created_by, created_at, updated_by, updated_at) on public.employee_benefits to authenticated;

-- ---------- storage: private bucket 'photos', prefixes EMP/<loc>/ (portrait) and EMPDOC/<loc>/ (documents). The old photos_* policies stay; policies are OR-ed. ----------
create or replace function public._emp_photo_ok(p_name text, p_action text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and split_part(p_name, '/', 2) ~ '^[0-9]+$' and case split_part(p_name, '/', 1)
    when 'EMP' then public._loc_ok(split_part(p_name, '/', 2)::int, 'employee_manage')
                    or (p_action = 'view' and public.can_loc(split_part(p_name, '/', 2)::int) and public.has_grant('employee_view', split_part(p_name, '/', 2)::int))
    when 'EMPDOC' then public._loc_ok(split_part(p_name, '/', 2)::int, 'employee_manage')
    else false end;
$$;
do $$
begin
  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists emp_photos_insert on storage.objects';
    execute 'create policy emp_photos_insert on storage.objects for insert to authenticated with check (bucket_id = ''photos'' and public._emp_photo_ok(name, ''enter''))';
    execute 'drop policy if exists emp_photos_read on storage.objects';
    execute 'create policy emp_photos_read on storage.objects for select to authenticated using (bucket_id = ''photos'' and public._emp_photo_ok(name, ''view''))';
  end if;
end $$;

-- ---------- small pure helpers ----------
create or replace function public._e_txt(d jsonb, k text, n int default 200) returns text language plpgsql immutable as $$
declare v text := nullif(btrim(d ->> k), '');
begin if v is not null and char_length(v) > n then raise exception 'too_long: %', k; end if; return v; end $$;
create or replace function public._e_date(d jsonb, k text) returns date language plpgsql immutable as $$
begin return nullif(btrim(d ->> k), '')::date; exception when others then raise exception 'bad_date: %', k; end $$;
create or replace function public._e_num(d jsonb, k text, lo numeric, hi numeric) returns numeric language plpgsql immutable as $$
declare v numeric;
begin
  begin v := nullif(btrim(d ->> k), '')::numeric; exception when others then raise exception 'bad_number: %', k; end;
  if v is not null and not (v between lo and hi) then raise exception 'bad_number: %', k; end if;
  return v;
end $$;
create or replace function public._e_nid(p text) returns text language plpgsql immutable as $$
declare v text;
begin
  if nullif(btrim(p), '') is null then return null; end if;
  v := regexp_replace(translate(p, '০১২৩৪৫৬৭৮৯', '0123456789'), '[^0-9]', '', 'g');
  if v !~ '^([0-9]{10}|[0-9]{13}|[0-9]{17})$' then raise exception 'bad_nid'; end if;
  return v;
end $$;
create or replace function public._emp_gate() returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('employees_module_on') then raise exception 'module_off'; end if;
end $$;
create or replace function public._dhaka_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;

-- ---------- employee_save: create a draft / change fields (partial: only the keys present in p_data change) ----------
create or replace function public.employee_save(p_id uuid, p_client uuid, p_data jsonb, p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d jsonb := coalesce(p_data, '{}'); e public.employees; v_old_loc int; v_today date := public._dhaka_today(); v_warn jsonb := '{}'; v_dup jsonb; v_no text; v_new boolean := (p_id is null);
begin
  perform public._emp_gate();
  if jsonb_typeof(d) <> 'object' then raise exception 'bad_data'; end if;
  if v_new then
    perform public._client_lock(p_client);
    if p_client is not null then
      select * into e from public.employees where client_id = p_client;
      if found then
        if not public._emp_ok(e.id, array['employee_manage']) and not (e.created_by = auth.uid()) then raise exception 'not allowed'; end if;
        return jsonb_build_object('id', e.id, 'employee_no', e.employee_no, 'status', e.status, 'repeat', true);
      end if;
    end if;
    e.id := gen_random_uuid(); e.client_id := p_client; e.status := 'draft'; e.employment_type := 'permanent'; e.status_date := v_today; e.created_by := auth.uid(); e.created_at := now();
  else
    select * into e from public.employees where id = p_id for update;
    if not found then raise exception 'not_found'; end if;
    if not public._emp_ok(e.id, array['employee_manage']) then raise exception 'not allowed'; end if;
    if e.status in ('discarded') then raise exception 'employee_discarded'; end if;
    v_old_loc := e.primary_location_id;
  end if;
  if d ? 'full_name_bn' then e.full_name_bn := public._e_txt(d, 'full_name_bn', 120); end if;
  if d ? 'full_name_en' then e.full_name_en := public._e_txt(d, 'full_name_en', 120); end if;
  if d ? 'nickname' then e.nickname := public._e_txt(d, 'nickname', 60); end if;
  if d ? 'gender' then e.gender := public._e_txt(d, 'gender', 10); end if;
  if d ? 'date_of_birth' then e.date_of_birth := public._e_date(d, 'date_of_birth'); end if;
  if d ? 'blood_group' then e.blood_group := public._e_txt(d, 'blood_group', 3); end if;
  if d ? 'nid_no' then e.nid_no := public._e_nid(d ->> 'nid_no'); end if;
  if d ? 'mobile' then e.mobile := case when public._e_txt(d, 'mobile', 30) is null then null else public.norm_mobile(d ->> 'mobile') end; end if;
  if d ? 'email' then e.email := lower(public._e_txt(d, 'email', 120)); end if;
  if d ? 'present_address' then e.present_address := public._e_txt(d, 'present_address', 400); end if;
  if d ? 'permanent_address' then e.permanent_address := public._e_txt(d, 'permanent_address', 400); end if;
  if d ? 'emergency_name' then e.emergency_name := public._e_txt(d, 'emergency_name', 120); end if;
  if d ? 'emergency_relation' then e.emergency_relation := public._e_txt(d, 'emergency_relation', 60); end if;
  if d ? 'emergency_mobile' then e.emergency_mobile := case when public._e_txt(d, 'emergency_mobile', 30) is null then null else public.norm_mobile(d ->> 'emergency_mobile') end; end if;
  if d ? 'marital_status' then e.marital_status := public._e_txt(d, 'marital_status', 10); end if;
  if d ? 'education' then e.education := public._e_txt(d, 'education', 300); end if;
  if d ? 'joining_date' then e.joining_date := public._e_date(d, 'joining_date'); end if;
  if d ? 'probation_end' then e.probation_end := public._e_date(d, 'probation_end'); end if;
  if d ? 'designation' then e.designation := public._e_txt(d, 'designation', 80); end if;
  if d ? 'department' then e.department := public._e_txt(d, 'department', 80); end if;
  if d ? 'primary_location_id' then e.primary_location_id := public._e_num(d, 'primary_location_id', 1, 100000)::int; end if;
  if d ? 'primary_role_code' then e.primary_role_code := public._e_txt(d, 'primary_role_code', 41); end if;
  if d ? 'employment_type' then e.employment_type := coalesce(public._e_txt(d, 'employment_type', 12), 'permanent'); end if;
  if d ? 'device_user_id' then e.device_user_id := public._e_txt(d, 'device_user_id', 40); end if;
  if d ? 'notes' then e.notes := public._e_txt(d, 'notes', 1000); end if;
  -- checks
  if e.full_name_bn is null then raise exception 'name_required'; end if;
  if e.primary_location_id is null then raise exception 'location_required'; end if;
  if not exists (select 1 from public.locations l where l.id = e.primary_location_id) then raise exception 'bad_location'; end if;
  if e.gender is not null and e.gender not in ('male', 'female', 'other') then raise exception 'bad_gender'; end if;
  if e.blood_group is not null and e.blood_group not in ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-') then raise exception 'bad_blood_group'; end if;
  if e.marital_status is not null and e.marital_status not in ('single', 'married', 'divorced', 'widowed') then raise exception 'bad_marital_status'; end if;
  if e.employment_type not in ('permanent', 'contract', 'daily', 'part_time', 'trainee') then raise exception 'bad_employment_type'; end if;
  if e.email is not null and e.email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'bad_email'; end if;
  if e.date_of_birth is not null and not (e.date_of_birth between date '1930-01-01' and v_today - 10 * 365) then raise exception 'bad_date: date_of_birth'; end if;
  if e.joining_date is not null and not (e.joining_date between date '1990-01-01' and v_today + 90) then raise exception 'bad_date: joining_date'; end if;
  if e.probation_end is not null and (e.joining_date is null or e.probation_end < e.joining_date or e.probation_end > e.joining_date + 1100) then raise exception 'bad_date: probation_end'; end if;
  if e.primary_role_code is not null and not exists (select 1 from public.staff_roles r where r.code = e.primary_role_code and r.active) then raise exception 'bad_role'; end if;
  if (v_new or e.primary_location_id is distinct from v_old_loc) and not public._loc_ok(e.primary_location_id, 'employee_manage') then raise exception 'not allowed'; end if;
  -- duplicates: NID is always refused (one person, one NID); mobile follows the rule employee_mobile_unique
  if e.nid_no is not null and exists (select 1 from public.employees x where x.nid_no = e.nid_no and x.id <> e.id) then raise exception 'duplicate_nid'; end if;
  if e.device_user_id is not null and exists (select 1 from public.employees x where x.device_user_id = e.device_user_id and x.id <> e.id) then raise exception 'duplicate_device_id'; end if;
  if e.mobile is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'employee_no', x.employee_no, 'name', x.full_name_bn)), '[]') into v_dup
      from public.employees x where x.mobile = e.mobile and x.id <> e.id and x.status <> 'discarded';
    if jsonb_array_length(v_dup) > 0 then
      if public.rule_on('employee_mobile_unique') then raise exception 'duplicate_mobile'; end if;
      v_warn := v_warn || jsonb_build_object('mobile', v_dup);
    end if;
  end if;
  if p_dry then return jsonb_build_object('dry', true, 'ok', true, 'warnings', v_warn); end if;
  if v_new then
    insert into public.employees (id, client_id, full_name_bn, full_name_en, nickname, gender, date_of_birth, blood_group, nid_no, mobile, email, present_address, permanent_address,
        emergency_name, emergency_relation, emergency_mobile, marital_status, education, joining_date, probation_end, designation, department, primary_location_id, primary_role_code,
        employment_type, status, status_date, device_user_id, notes, created_by, created_at, updated_by, updated_at)
      values (e.id, e.client_id, e.full_name_bn, e.full_name_en, e.nickname, e.gender, e.date_of_birth, e.blood_group, e.nid_no, e.mobile, e.email, e.present_address, e.permanent_address,
        e.emergency_name, e.emergency_relation, e.emergency_mobile, e.marital_status, e.education, e.joining_date, e.probation_end, e.designation, e.department, e.primary_location_id, e.primary_role_code,
        e.employment_type, 'draft', v_today, e.device_user_id, e.notes, auth.uid(), now(), auth.uid(), now());
  else
    update public.employees set full_name_bn = e.full_name_bn, full_name_en = e.full_name_en, nickname = e.nickname, gender = e.gender, date_of_birth = e.date_of_birth, blood_group = e.blood_group,
        nid_no = e.nid_no, mobile = e.mobile, email = e.email, present_address = e.present_address, permanent_address = e.permanent_address, emergency_name = e.emergency_name,
        emergency_relation = e.emergency_relation, emergency_mobile = e.emergency_mobile, marital_status = e.marital_status, education = e.education, joining_date = e.joining_date,
        probation_end = e.probation_end, designation = e.designation, department = e.department, primary_location_id = e.primary_location_id, primary_role_code = e.primary_role_code,
        employment_type = e.employment_type, device_user_id = e.device_user_id, notes = e.notes, updated_by = auth.uid(), updated_at = now()
      where id = e.id;
  end if;
  select employee_no into v_no from public.employees where id = e.id;
  return jsonb_build_object('id', e.id, 'employee_no', v_no, 'status', (select status from public.employees where id = e.id), 'warnings', v_warn);
end $$;

-- finish the wizard: draft -> active (gets the number E-0001..)
create or replace function public.employee_submit(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; v_today date := public._dhaka_today();
begin
  perform public._emp_gate();
  select * into e from public.employees where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(e.id, array['employee_manage']) then raise exception 'not allowed'; end if;
  if e.status <> 'draft' then return jsonb_build_object('id', e.id, 'employee_no', e.employee_no, 'status', e.status, 'repeat', true); end if;
  if e.joining_date is null then raise exception 'joining_date_required'; end if;
  if nullif(btrim(coalesce(e.designation, '')), '') is null then raise exception 'designation_required'; end if;
  update public.employees set status = 'active', status_date = v_today, updated_by = auth.uid(), updated_at = now() where id = e.id returning * into e;
  insert into public.employee_status_log (employee_id, from_status, to_status, status_date, reason, by) values (e.id, 'draft', 'active', v_today, 'registered', auth.uid());
  return jsonb_build_object('id', e.id, 'employee_no', e.employee_no, 'status', e.status);
end $$;

create or replace function public.employee_discard(p_id uuid, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees;
begin
  perform public._emp_gate();
  select * into e from public.employees where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not (public._emp_ok(e.id, array['employee_manage']) or e.created_by = auth.uid()) then raise exception 'not allowed'; end if;
  if e.status <> 'draft' then raise exception 'not_a_draft'; end if;
  update public.employees set status = 'discarded', status_date = public._dhaka_today(), status_reason = left(btrim(coalesce(p_reason, '')), 300), updated_by = auth.uid(), updated_at = now() where id = e.id;
  insert into public.employee_status_log (employee_id, from_status, to_status, status_date, reason, by) values (e.id, 'draft', 'discarded', public._dhaka_today(), left(btrim(coalesce(p_reason, '')), 300), auth.uid());
  return jsonb_build_object('id', e.id, 'status', 'discarded');
end $$;

-- who else looks the same? (wizard warnings while typing); needs employee_manage somewhere
create or replace function public.employee_dup_check(p_nid text, p_mobile text, p_exclude uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_nid text; v_mob text; r_nid jsonb := '[]'; r_mob jsonb := '[]';
begin
  if not public._emp_any(array['employee_manage']) then raise exception 'not allowed'; end if;
  begin v_nid := public._e_nid(p_nid); exception when others then v_nid := null; end;
  begin v_mob := case when nullif(btrim(p_mobile), '') is null then null else public.norm_mobile(p_mobile) end; exception when others then v_mob := null; end;
  if v_nid is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'employee_no', x.employee_no, 'name', x.full_name_bn, 'status', x.status)), '[]') into r_nid
      from public.employees x where x.nid_no = v_nid and x.id is distinct from p_exclude and x.status <> 'discarded';
  end if;
  if v_mob is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'employee_no', x.employee_no, 'name', x.full_name_bn, 'status', x.status)), '[]') into r_mob
      from public.employees x where x.mobile = v_mob and x.id is distinct from p_exclude and x.status <> 'discarded';
  end if;
  return jsonb_build_object('nid', r_nid, 'mobile', r_mob, 'mobile_blocks', public.rule_on('employee_mobile_unique'));
end $$;

-- status changes (history kept). Leaving (resigned / terminated / retired) needs a reason and ends the person's active deeds. Coming back is owner only.
create or replace function public.employee_status_set(p_id uuid, p_status text, p_date date, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; v_today date := public._dhaka_today(); v_reason text := nullif(left(btrim(coalesce(p_reason, '')), 300), '');
begin
  perform public._emp_gate();
  if p_status not in ('active', 'on_leave', 'resigned', 'terminated', 'retired') then raise exception 'bad_status'; end if;
  select * into e from public.employees where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(e.id, array['employee_manage']) then raise exception 'not allowed'; end if;
  if e.status in ('draft', 'discarded') then raise exception 'not_registered_yet'; end if;
  if e.status = p_status then raise exception 'same_status'; end if;
  if p_date is null or not (p_date between v_today - 400 and v_today + 60) then raise exception 'bad_date'; end if;
  if p_status in ('resigned', 'terminated', 'retired', 'on_leave') and v_reason is null then raise exception 'reason_required'; end if;
  if e.status in ('resigned', 'terminated', 'retired') then
    if not public.is_owner() then raise exception 'owner_only'; end if;
    if v_reason is null then raise exception 'reason_required'; end if;
  end if;
  update public.employees set status = p_status, status_date = p_date, status_reason = v_reason, updated_by = auth.uid(), updated_at = now() where id = e.id;
  insert into public.employee_status_log (employee_id, from_status, to_status, status_date, reason, by) values (e.id, e.status, p_status, p_date, v_reason, auth.uid());
  if p_status in ('resigned', 'terminated', 'retired') then
    update public.employee_deeds set status = 'terminated', ended_by = auth.uid(), ended_at = now(), end_reason = 'employee_' || p_status where employee_id = e.id and status = 'active';
    update public.employee_deeds set status = 'terminated', ended_by = auth.uid(), ended_at = now(), end_reason = 'employee_' || p_status where employee_id = e.id and status = 'draft';
  end if;
  return jsonb_build_object('id', e.id, 'status', p_status);
end $$;

create or replace function public.employee_locations_set(p_id uuid, p_locs int[]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l int;
begin
  perform public._emp_gate();
  if not public._emp_ok(p_id, array['employee_manage']) then raise exception 'not allowed'; end if;
  if coalesce(array_length(p_locs, 1), 0) > 30 then raise exception 'too_many'; end if;
  foreach l in array coalesce(p_locs, '{}') loop
    if not exists (select 1 from public.locations x where x.id = l) then raise exception 'bad_location'; end if;
    insert into public.employee_locations (employee_id, location_id, active, added_by) values (p_id, l, true, auth.uid())
      on conflict (employee_id, location_id) do update set active = true;
  end loop;
  update public.employee_locations set active = false where employee_id = p_id and active and not (location_id = any (coalesce(p_locs, '{}')));
  return jsonb_build_object('id', p_id, 'locations', coalesce(p_locs, '{}'));
end $$;

create or replace function public.employee_link_profile(p_id uuid, p_profile uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees;
begin
  perform public._emp_gate();
  select * into e from public.employees where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(e.id, array['employee_manage']) then raise exception 'not allowed'; end if;
  if p_profile is not null then
    if not exists (select 1 from public.profiles pr where pr.id = p_profile) then raise exception 'profile_not_found'; end if;
    if exists (select 1 from public.employees x where x.profile_id = p_profile and x.id <> e.id) then raise exception 'profile_already_linked'; end if;
  end if;
  update public.employees set profile_id = p_profile, updated_by = auth.uid(), updated_at = now() where id = e.id;
  return jsonb_build_object('id', e.id, 'profile_id', p_profile);
end $$;

create or replace function public.employee_set_photo(p_id uuid, p_path text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees;
begin
  perform public._emp_gate();
  select * into e from public.employees where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(e.id, array['employee_manage']) then raise exception 'not allowed'; end if;
  if p_path is not null and (p_path !~ '^EMP/[0-9]+/[A-Za-z0-9_.-]{1,120}$' or split_part(p_path, '/', 2)::int is distinct from e.primary_location_id) then raise exception 'bad_path'; end if;
  update public.employees set photo_path = p_path, updated_by = auth.uid(), updated_at = now() where id = e.id;
  return jsonb_build_object('id', e.id, 'photo_path', p_path);
end $$;

-- ---------- documents ----------
create or replace function public.employee_doc_add(p_id uuid, p_kind text, p_path text, p_note text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; r public.employee_documents;
begin
  perform public._emp_gate();
  perform public._client_lock(p_client);
  select * into e from public.employees where id = p_id;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(e.id, array['employee_manage']) then raise exception 'not allowed'; end if;
  if p_client is not null then select * into r from public.employee_documents where client_id = p_client; if found then return jsonb_build_object('id', r.id, 'repeat', true); end if; end if;
  if p_kind not in ('nid', 'contract', 'cv', 'certificate', 'guarantor', 'photo', 'other') then raise exception 'bad_kind'; end if;
  if p_path is null or p_path !~ '^(EMP|EMPDOC)/[0-9]+/[A-Za-z0-9_.-]{1,120}$' then raise exception 'bad_path'; end if;
  if (p_kind = 'photo') <> (split_part(p_path, '/', 1) = 'EMP') then raise exception 'bad_path'; end if;
  if split_part(p_path, '/', 2)::int is distinct from e.primary_location_id then raise exception 'bad_path'; end if;
  if char_length(coalesce(p_note, '')) > 300 then raise exception 'too_long: note'; end if;
  insert into public.employee_documents (client_id, employee_id, kind, file_path, note, uploaded_by) values (p_client, e.id, p_kind, p_path, nullif(btrim(p_note), ''), auth.uid()) returning * into r;
  return jsonb_build_object('id', r.id);
end $$;
create or replace function public.employee_doc_void(p_doc bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.employee_documents;
begin
  perform public._emp_gate();
  select * into r from public.employee_documents where id = p_doc for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(r.employee_id, array['employee_manage']) then raise exception 'not allowed'; end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'reason_required'; end if;
  update public.employee_documents set void = true, void_by = auth.uid(), void_at = now(), void_reason = left(btrim(p_reason), 300) where id = r.id and not void;
  return jsonb_build_object('id', r.id, 'void', true);
end $$;

-- ---------- pay structure ----------
-- validated component list (array of {kind,name,amount|percent_of_basic,taxable}); duplicate names inside a kind are refused
create or replace function public._pay_clean(p_comps jsonb) returns jsonb language plpgsql immutable as $$
declare c jsonb; out_ jsonb := '[]'; k text; n text; a numeric; pc numeric; seen text[] := '{}';
begin
  if p_comps is null or jsonb_typeof(p_comps) = 'null' then return '[]'; end if;
  if jsonb_typeof(p_comps) <> 'array' or jsonb_array_length(p_comps) > 30 then raise exception 'bad_components'; end if;
  for c in select * from jsonb_array_elements(p_comps) loop
    if jsonb_typeof(c) <> 'object' then raise exception 'bad_components'; end if;
    k := c ->> 'kind'; n := nullif(btrim(c ->> 'name'), '');
    if k not in ('allowance', 'deduction') then raise exception 'bad_component_kind'; end if;
    if n is null or char_length(n) > 60 then raise exception 'bad_component_name'; end if;
    a := public._e_num(c, 'amount', 0, 1000000000000); pc := public._e_num(c, 'percent_of_basic', 0, 100);
    if (a is null) = (pc is null) then raise exception 'component_amount_or_percent: %', n; end if;
    if (k || ':' || lower(n)) = any (seen) then raise exception 'duplicate_component: %', n; end if;
    seen := seen || (k || ':' || lower(n));
    out_ := out_ || jsonb_build_array(jsonb_build_object('kind', k, 'name', n, 'amount', a, 'percent_of_basic', pc, 'taxable', coalesce((c ->> 'taxable')::boolean, false)));
  end loop;
  return out_;
end $$;
-- computed lines and totals from a basic + cleaned components
create or replace function public._pay_calc(p_basic numeric, p_comps jsonb) returns jsonb language plpgsql immutable as $$
declare c jsonb; lines jsonb := '[]'; v numeric; al numeric := 0; de numeric := 0;
begin
  for c in select * from jsonb_array_elements(coalesce(p_comps, '[]')) loop
    if coalesce((c ->> 'active')::boolean, true) is false then continue; end if;
    v := coalesce((c ->> 'amount')::numeric, round(p_basic * (c ->> 'percent_of_basic')::numeric / 100, 2));
    if c ->> 'kind' = 'allowance' then al := al + v; else de := de + v; end if;
    lines := lines || jsonb_build_array(c || jsonb_build_object('calc', v));
  end loop;
  return jsonb_build_object('components', lines, 'allowances', al, 'deductions', de, 'gross', round(p_basic + al, 2), 'net', round(p_basic + al - de, 2));
end $$;
create or replace function public._emp_pay_json(p_pay bigint) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare p public.employee_pay; comps jsonb;
begin
  select * into p from public.employee_pay where id = p_pay;
  if not found then return null; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'kind', c.kind, 'name', c.name, 'amount', c.amount, 'percent_of_basic', c.percent_of_basic, 'taxable', c.taxable, 'active', c.active) order by c.id), '[]')
    into comps from public.employee_pay_components c where c.pay_id = p.id;
  return jsonb_build_object('pay_id', p.id, 'employee_id', p.employee_id, 'effective_from', p.effective_from, 'pay_basis', p.pay_basis, 'basic', p.basic, 'ot_rule', p.ot_rule, 'ot_value', p.ot_value,
    'ot_hours_basis', p.ot_hours_basis, 'bonus_rules', p.bonus_rules, 'note', p.note, 'created_at', p.created_at) || public._pay_calc(p.basic, comps);
end $$;
-- for server code (payroll): the pay version in force for a person on a date
create or replace function public._emp_pay_on(p_emp uuid, p_on date) returns public.employee_pay language sql stable security definer set search_path = public as $$
  select * from public.employee_pay where employee_id = p_emp and effective_from <= coalesce(p_on, public._dhaka_today()) order by effective_from desc, id desc limit 1;
$$;

create or replace function public.employee_pay_set(p_emp uuid, p_effective date, p_basis text, p_basic numeric, p_ot_rule text, p_ot_value numeric, p_bonus jsonb, p_components jsonb,
  p_note text, p_client uuid default null, p_dry boolean default false, p_ot_hours numeric default 8) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_today date := public._dhaka_today(); v_comps jsonb; v_calc jsonb; r public.employee_pay; b jsonb; v_bonus jsonb := '[]'; c jsonb; v_id bigint; v_stat text;
begin
  perform public._emp_gate();
  if not public._emp_ok(p_emp, array['salary_manage']) then raise exception 'not allowed'; end if;
  select status into v_stat from public.employees where id = p_emp;
  if v_stat is null or v_stat = 'discarded' then raise exception 'not_found'; end if;
  if not p_dry then
    perform public._client_lock(p_client);
    if p_client is not null then select * into r from public.employee_pay where client_id = p_client; if found then return public._emp_pay_json(r.id) || jsonb_build_object('repeat', true); end if; end if;
  end if;
  if p_effective is null or not (p_effective between v_today - 1830 and v_today + 366) then raise exception 'bad_date'; end if;
  if p_basis not in ('monthly', 'daily', 'hourly') then raise exception 'bad_basis'; end if;
  if p_basic is null or not (p_basic > 0 and p_basic <= 1000000000000) then raise exception 'bad_amount'; end if;
  if p_ot_rule not in ('none', 'rate_per_hour', 'multiple_of_hourly') then raise exception 'bad_ot_rule'; end if;
  if p_ot_rule = 'none' then if p_ot_value is not null then raise exception 'bad_ot_value'; end if;
  elsif p_ot_value is null or not (p_ot_value > 0 and p_ot_value <= 1000000) or (p_ot_rule = 'multiple_of_hourly' and not (p_ot_value between 1 and 5)) then raise exception 'bad_ot_value'; end if;
  if p_ot_hours is null or not (p_ot_hours between 1 and 24) then raise exception 'bad_ot_hours'; end if;
  if char_length(coalesce(p_note, '')) > 500 then raise exception 'too_long: note'; end if;
  if p_bonus is not null and jsonb_typeof(p_bonus) <> 'null' then
    if jsonb_typeof(p_bonus) <> 'array' or jsonb_array_length(p_bonus) > 10 then raise exception 'bad_bonus'; end if;
    for b in select * from jsonb_array_elements(p_bonus) loop
      if jsonb_typeof(b) <> 'object' or nullif(btrim(b ->> 'name'), '') is null or char_length(b ->> 'name') > 60 then raise exception 'bad_bonus'; end if;
      v_bonus := v_bonus || jsonb_build_array(jsonb_build_object('name', btrim(b ->> 'name'), 'months_of_basic', public._e_num(b, 'months_of_basic', 0, 24), 'min_service_months', coalesce(public._e_num(b, 'min_service_months', 0, 600), 0)));
      if (v_bonus -> (jsonb_array_length(v_bonus) - 1) ->> 'months_of_basic') is null then raise exception 'bad_bonus'; end if;
    end loop;
  end if;
  v_comps := public._pay_clean(p_components);
  v_calc := public._pay_calc(p_basic, v_comps);
  if (v_calc ->> 'net')::numeric < 0 then raise exception 'deductions_exceed_gross'; end if;
  if p_dry then
    return jsonb_build_object('dry', true, 'effective_from', p_effective, 'pay_basis', p_basis, 'basic', p_basic, 'ot_rule', p_ot_rule, 'ot_value', p_ot_value, 'ot_hours_basis', p_ot_hours, 'bonus_rules', v_bonus) || v_calc;
  end if;
  insert into public.employee_pay (client_id, employee_id, effective_from, pay_basis, basic, ot_rule, ot_value, ot_hours_basis, bonus_rules, note, created_by)
    values (p_client, p_emp, p_effective, p_basis, round(p_basic, 2), p_ot_rule, p_ot_value, p_ot_hours, v_bonus, nullif(btrim(p_note), ''), auth.uid()) returning id into v_id;
  for c in select * from jsonb_array_elements(v_comps) loop
    insert into public.employee_pay_components (pay_id, kind, name, amount, percent_of_basic, taxable)
      values (v_id, c ->> 'kind', c ->> 'name', (c ->> 'amount')::numeric, (c ->> 'percent_of_basic')::numeric, (c ->> 'taxable')::boolean);
  end loop;
  return public._emp_pay_json(v_id);
end $$;

create or replace function public.employee_pay_current(p_emp uuid, p_on date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r public.employee_pay;
begin
  if not public._emp_ok(p_emp, array['salary_view']) then raise exception 'not allowed'; end if;
  select * into r from public._emp_pay_on(p_emp, p_on);
  if r.id is null then return null; end if;
  return public._emp_pay_json(r.id);
end $$;
create or replace function public.employee_pay_history(p_emp uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._emp_ok(p_emp, array['salary_view']) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(public._emp_pay_json(p.id) order by p.effective_from desc, p.id desc) from public.employee_pay p where p.employee_id = p_emp), '[]');
end $$;

create or replace function public.employee_pay_account_set(p_emp uuid, p_bank text, p_wallet text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_w text := nullif(btrim(coalesce(p_wallet, '')), '');
begin
  perform public._emp_gate();
  if not public._emp_ok(p_emp, array['salary_manage']) then raise exception 'not allowed'; end if;
  if char_length(coalesce(p_bank, '')) > 120 then raise exception 'too_long: bank_account'; end if;
  if v_w is not null then v_w := public.norm_mobile(v_w); end if;
  update public.employees set bank_account = nullif(btrim(coalesce(p_bank, '')), ''), mobile_wallet = v_w, updated_by = auth.uid(), updated_at = now() where id = p_emp;
  if not found then raise exception 'not_found'; end if;
  return jsonb_build_object('id', p_emp);
end $$;
create or replace function public.employee_pay_account_get(p_emp uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._emp_ok(p_emp, array['salary_view']) then raise exception 'not allowed'; end if;
  return (select jsonb_build_object('bank_account', e.bank_account, 'mobile_wallet', e.mobile_wallet) from public.employees e where e.id = p_emp);
end $$;

-- ---------- leave entitlements, benefits ----------
create or replace function public.leave_entitlement_set(p_emp uuid, p_type text, p_days numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public._emp_gate();
  if not public._emp_ok(p_emp, array['employee_manage']) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.leave_types t where t.code = p_type and t.active) then raise exception 'bad_leave_type'; end if;
  if p_days is null or not (p_days between 0 and 366) then raise exception 'bad_days'; end if;
  insert into public.employee_leave_entitlements (employee_id, leave_type, days_per_year, updated_by) values (p_emp, p_type, p_days, auth.uid())
    on conflict (employee_id, leave_type) do update set days_per_year = excluded.days_per_year, updated_by = auth.uid(), updated_at = now();
  return jsonb_build_object('employee_id', p_emp, 'leave_type', p_type, 'days_per_year', p_days);
end $$;

create or replace function public.employee_benefit_save(p_id bigint, p_client uuid, p_emp uuid, p_kind text, p_desc text, p_value numeric, p_from date, p_to date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.employee_benefits; v_today date := public._dhaka_today();
begin
  perform public._emp_gate();
  perform public._client_lock(p_client);
  if p_id is not null then select * into r from public.employee_benefits where id = p_id for update; if not found then raise exception 'not_found'; end if; end if;
  if not public._emp_ok(coalesce(r.employee_id, p_emp), array['employee_manage', 'salary_manage']) then raise exception 'not allowed'; end if;
  if p_value is not null and not public._emp_ok(coalesce(r.employee_id, p_emp), array['salary_manage']) then raise exception 'not allowed'; end if;
  if p_kind not in ('meal', 'uniform', 'accommodation', 'transport', 'phone', 'insurance', 'other') then raise exception 'bad_kind'; end if;
  if p_value is not null and not (p_value between 0 and 1000000000000) then raise exception 'bad_amount'; end if;
  if p_from is null or not (p_from between v_today - 1830 and v_today + 366) then raise exception 'bad_date'; end if;
  if p_to is not null and p_to < p_from then raise exception 'bad_date'; end if;
  if char_length(coalesce(p_desc, '')) > 300 then raise exception 'too_long: description'; end if;
  if p_id is null then
    if p_client is not null then select * into r from public.employee_benefits where client_id = p_client; if found then return jsonb_build_object('id', r.id, 'repeat', true); end if; end if;
    if not exists (select 1 from public.employees where id = p_emp) then raise exception 'not_found'; end if;
    insert into public.employee_benefits (client_id, employee_id, kind, description, value_per_month, from_date, to_date, created_by, updated_by)
      values (p_client, p_emp, p_kind, nullif(btrim(p_desc), ''), p_value, p_from, p_to, auth.uid(), auth.uid()) returning * into r;
  else
    update public.employee_benefits set kind = p_kind, description = nullif(btrim(p_desc), ''), value_per_month = case when p_value is not null then p_value else value_per_month end,
      from_date = p_from, to_date = p_to, updated_by = auth.uid(), updated_at = now() where id = r.id returning * into r;
  end if;
  return jsonb_build_object('id', r.id);
end $$;
create or replace function public.employee_benefit_end(p_id bigint, p_to date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.employee_benefits;
begin
  perform public._emp_gate();
  select * into r from public.employee_benefits where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(r.employee_id, array['employee_manage']) then raise exception 'not allowed'; end if;
  if p_to is null or p_to < r.from_date or p_to > public._dhaka_today() + 366 then raise exception 'bad_date'; end if;
  update public.employee_benefits set to_date = p_to, active = false, updated_by = auth.uid(), updated_at = now() where id = r.id;
  return jsonb_build_object('id', r.id, 'to_date', p_to);
end $$;
create or replace function public.employee_benefits_list(p_emp uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_sal boolean;
begin
  if not public._emp_ok(p_emp, array['employee_view', 'employee_manage', 'salary_view'], true) then raise exception 'not allowed'; end if;
  v_sal := public._emp_ok(p_emp, array['salary_view']);
  return coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'kind', b.kind, 'description', b.description, 'from_date', b.from_date, 'to_date', b.to_date, 'active', b.active,
           'value_per_month', case when v_sal then b.value_per_month end) order by b.from_date desc, b.id desc) from public.employee_benefits b where b.employee_id = p_emp), '[]');
end $$;

-- ---------- roles ----------
create or replace function public.staff_role_save(p_code text, p_name_bn text, p_name_en text, p_major boolean, p_description text, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_code is null or p_code !~ '^[a-z][a-z0-9_]{1,40}$' then raise exception 'bad_code'; end if;
  if nullif(btrim(coalesce(p_name_bn, '')), '') is null or char_length(p_name_bn) > 100 or char_length(coalesce(p_name_en, '')) > 100 or char_length(coalesce(p_description, '')) > 300 then raise exception 'bad_name'; end if;
  insert into public.staff_roles (code, name_bn, name_en, major, description, active, sort)
    values (p_code, btrim(p_name_bn), coalesce(nullif(btrim(p_name_en), ''), btrim(p_name_bn)), coalesce(p_major, false), nullif(btrim(p_description), ''), coalesce(p_active, true), 100)
    on conflict (code) do update set name_bn = excluded.name_bn, name_en = excluded.name_en, major = excluded.major, description = excluded.description, active = excluded.active;
  return jsonb_build_object('code', p_code);
end $$;

-- ---------- deeds ----------
create or replace function public._clauses_clean(p_cl jsonb) returns jsonb language plpgsql immutable as $$
declare c jsonb; out_ jsonb := '[]'; i int := 0; k text; bn text; en text; v text; u text;
begin
  if p_cl is null or jsonb_typeof(p_cl) = 'null' then return '[]'; end if;
  if jsonb_typeof(p_cl) <> 'array' or jsonb_array_length(p_cl) > 60 then raise exception 'bad_clauses'; end if;
  for c in select * from jsonb_array_elements(p_cl) loop
    if jsonb_typeof(c) <> 'object' then raise exception 'bad_clauses'; end if;
    i := i + 1; k := coalesce(nullif(c ->> 'kind', ''), 'text'); bn := nullif(btrim(c ->> 'text_bn'), ''); en := nullif(btrim(c ->> 'text_en'), '');
    v := nullif(btrim(c ->> 'value'), ''); u := nullif(btrim(c ->> 'unit'), '');
    if k not in ('rule', 'amount', 'duration', 'text') then raise exception 'bad_clause_kind'; end if;
    if bn is null and en is null then raise exception 'clause_text_required'; end if;
    if char_length(coalesce(bn, '')) > 2000 or char_length(coalesce(en, '')) > 2000 or char_length(coalesce(v, '')) > 200 or char_length(coalesce(u, '')) > 30 then raise exception 'too_long: clause'; end if;
    if k in ('amount', 'duration') and v is not null and v !~ '^[0-9]+(\.[0-9]+)?$' then raise exception 'bad_clause_value'; end if;
    out_ := out_ || jsonb_build_array(jsonb_build_object('no', i, 'text_bn', bn, 'text_en', en, 'kind', k, 'value', v, 'unit', u));
  end loop;
  return out_;
end $$;

create or replace function public.deed_template_save(p_family bigint, p_role text, p_title_bn text, p_title_en text, p_clauses jsonb, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_cl jsonb; last_ public.deed_templates; r public.deed_templates; v_ver int := 1; v_fam bigint := p_family;
begin
  perform public._emp_gate();
  if not public._emp_any(array['deed_manage']) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into r from public.deed_templates where client_id = p_client; if found then return jsonb_build_object('id', r.id, 'family_id', r.family_id, 'version', r.version, 'repeat', true); end if; end if;
  if not exists (select 1 from public.staff_roles s where s.code = p_role and s.active) then raise exception 'bad_role'; end if;
  if nullif(btrim(coalesce(p_title_bn, '')), '') is null or char_length(p_title_bn) > 200 or char_length(coalesce(p_title_en, '')) > 200 then raise exception 'bad_title'; end if;
  v_cl := public._clauses_clean(p_clauses);
  if p_family is not null then
    perform pg_advisory_xact_lock(hashtextextended('bos41:tpl:' || p_family::text, 0));
    select * into last_ from public.deed_templates where family_id = p_family order by version desc limit 1;
    if not found then raise exception 'not_found'; end if;
    if last_.role_code = p_role and last_.title_bn = btrim(p_title_bn) and coalesce(last_.title_en, '') = coalesce(nullif(btrim(p_title_en), ''), '') and last_.clauses = v_cl and last_.active then
      return jsonb_build_object('id', last_.id, 'family_id', last_.family_id, 'version', last_.version, 'unchanged', true);
    end if;
    v_ver := last_.version + 1;
    update public.deed_templates set active = false where family_id = p_family and active;
  end if;
  if v_fam is null then v_fam := nextval(pg_get_serial_sequence('public.deed_templates', 'id')); end if;     -- a new template is the first member of its own family
  insert into public.deed_templates (id, client_id, family_id, version, role_code, title_bn, title_en, clauses, created_by)
    values (case when p_family is null then v_fam else nextval(pg_get_serial_sequence('public.deed_templates', 'id')) end, p_client, v_fam, v_ver, p_role, btrim(p_title_bn), nullif(btrim(p_title_en), ''), v_cl, auth.uid())
    returning * into r;
  return jsonb_build_object('id', r.id, 'family_id', r.family_id, 'version', r.version);
end $$;

-- retire / bring back the newest version of a template family (older versions stay as they were)
create or replace function public.deed_template_retire(p_family bigint, p_active boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare last_ public.deed_templates;
begin
  perform public._emp_gate();
  if not public._emp_any(array['deed_manage']) then raise exception 'not allowed'; end if;
  select * into last_ from public.deed_templates where family_id = p_family order by version desc limit 1;
  if not found then raise exception 'not_found'; end if;
  update public.deed_templates set active = coalesce(p_active, false) where id = last_.id;
  return jsonb_build_object('family_id', p_family, 'active', coalesce(p_active, false));
end $$;

-- create / change a DRAFT deed (copies the clauses of a template when none are given). Several fields are optional.
create or replace function public.deed_save(p_id bigint, p_client uuid, p_emp uuid, p_template bigint, p_role text, p_title text, p_clauses jsonb, p_start date, p_end date,
  p_probation int, p_notice int, p_deposit numeric, p_gname text, p_gmobile text, p_gnid text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.employee_deeds; t public.deed_templates; v_cl jsonb; v_emp uuid := p_emp; v_st text; v_title text := nullif(btrim(coalesce(p_title, '')), ''); v_today date := public._dhaka_today();
begin
  perform public._emp_gate();
  perform public._client_lock(p_client);
  if p_id is not null then
    select * into r from public.employee_deeds where id = p_id for update;
    if not found then raise exception 'not_found'; end if;
    if r.status <> 'draft' then raise exception 'deed_not_draft'; end if;
    v_emp := r.employee_id;
  elsif p_client is not null then
    select * into r from public.employee_deeds where client_id = p_client;
    if found then
      if not public._emp_ok(r.employee_id, array['employee_manage', 'deed_manage']) then raise exception 'not allowed'; end if;
      return jsonb_build_object('id', r.id, 'repeat', true);
    end if;
  end if;
  if not public._emp_ok(v_emp, array['employee_manage', 'deed_manage']) then raise exception 'not allowed'; end if;
  select status into v_st from public.employees where id = v_emp;
  if v_st is null then raise exception 'not_found'; end if;
  if v_st in ('resigned', 'terminated', 'retired', 'discarded') then raise exception 'employee_not_working'; end if;
  if not exists (select 1 from public.staff_roles s where s.code = p_role and s.active) then raise exception 'bad_role'; end if;
  if p_template is not null then
    select * into t from public.deed_templates where id = p_template;
    if not found then raise exception 'template_not_found'; end if;
    if t.role_code <> p_role then raise exception 'template_role_mismatch'; end if;
  end if;
  v_cl := case when p_clauses is not null and jsonb_typeof(p_clauses) <> 'null' then public._clauses_clean(p_clauses) when t.id is not null then public._clauses_clean(t.clauses) else '[]' end;
  v_title := coalesce(v_title, t.title_bn);
  if v_title is null or char_length(v_title) > 200 then raise exception 'bad_title'; end if;
  if p_start is not null and not (p_start between date '1990-01-01' and v_today + 366) then raise exception 'bad_date'; end if;
  if p_end is not null and (p_start is null or p_end < p_start or p_end > p_start + 3660) then raise exception 'bad_date'; end if;
  if p_probation is not null and not (p_probation between 0 and 365) then raise exception 'bad_days'; end if;
  if p_notice is not null and not (p_notice between 0 and 365) then raise exception 'bad_days'; end if;
  if p_deposit is not null and not (p_deposit between 0 and 1000000000000) then raise exception 'bad_amount'; end if;
  if char_length(coalesce(p_gname, '')) > 120 then raise exception 'too_long: guarantor'; end if;
  if p_id is null then
    insert into public.employee_deeds (client_id, employee_id, template_id, role_code, title, clauses, start_date, end_date, probation_days, notice_days, security_deposit,
        guarantor_name, guarantor_mobile, guarantor_nid, created_by)
      values (p_client, v_emp, p_template, p_role, v_title, v_cl, p_start, p_end, p_probation, p_notice, p_deposit, nullif(btrim(p_gname), ''),
        case when nullif(btrim(coalesce(p_gmobile, '')), '') is null then null else public.norm_mobile(p_gmobile) end, public._e_nid(p_gnid), auth.uid()) returning * into r;
  else
    update public.employee_deeds set template_id = p_template, role_code = p_role, title = v_title, clauses = v_cl, start_date = p_start, end_date = p_end, probation_days = p_probation,
        notice_days = p_notice, security_deposit = p_deposit, guarantor_name = nullif(btrim(p_gname), ''),
        guarantor_mobile = case when nullif(btrim(coalesce(p_gmobile, '')), '') is null then null else public.norm_mobile(p_gmobile) end, guarantor_nid = public._e_nid(p_gnid)
      where id = r.id returning * into r;
  end if;
  return jsonb_build_object('id', r.id, 'status', r.status, 'revision_no', r.revision_no);
end $$;

-- change an ACTIVE deed = copy it into a new draft revision (revision_no + 1). Activating the revision supersedes the old deed.
create or replace function public.deed_revise(p_id bigint, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.employee_deeds; r public.employee_deeds;
begin
  perform public._emp_gate();
  perform public._client_lock(p_client);
  select * into o from public.employee_deeds where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(o.employee_id, array['employee_manage', 'deed_manage']) then raise exception 'not allowed'; end if;
  if p_client is not null then select * into r from public.employee_deeds where client_id = p_client; if found then return jsonb_build_object('id', r.id, 'repeat', true); end if; end if;
  if o.status <> 'active' then raise exception 'deed_not_active'; end if;
  if exists (select 1 from public.employee_deeds x where x.supersedes_id = o.id and x.status = 'draft') then raise exception 'revision_already_open'; end if;
  insert into public.employee_deeds (client_id, employee_id, template_id, role_code, title, clauses, start_date, end_date, probation_days, notice_days, security_deposit,
      guarantor_name, guarantor_mobile, guarantor_nid, revision_no, supersedes_id, created_by)
    values (p_client, o.employee_id, o.template_id, o.role_code, o.title, o.clauses, o.start_date, o.end_date, o.probation_days, o.notice_days, o.security_deposit,
      o.guarantor_name, o.guarantor_mobile, o.guarantor_nid, o.revision_no + 1, o.id, auth.uid()) returning * into r;
  return jsonb_build_object('id', r.id, 'revision_no', r.revision_no, 'supersedes_id', o.id);
end $$;

create or replace function public.deed_activate(p_id bigint, p_signed_at date default null, p_signed_doc text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.employee_deeds; v_today date := public._dhaka_today(); v_emp_st text;
begin
  perform public._emp_gate();
  select * into r from public.employee_deeds where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(r.employee_id, array['deed_manage']) then raise exception 'not allowed'; end if;
  if r.status = 'active' then return jsonb_build_object('id', r.id, 'status', 'active', 'repeat', true); end if;
  if r.status <> 'draft' then raise exception 'deed_not_draft'; end if;
  select status into v_emp_st from public.employees where id = r.employee_id;
  if v_emp_st in ('resigned', 'terminated', 'retired', 'discarded') then raise exception 'employee_not_working'; end if;
  if r.start_date is null then raise exception 'start_date_required'; end if;
  if jsonb_array_length(r.clauses) = 0 then raise exception 'clauses_required'; end if;
  if p_signed_at is not null and not (p_signed_at between date '1990-01-01' and v_today + 1) then raise exception 'bad_date'; end if;
  if p_signed_doc is not null and p_signed_doc !~ '^EMPDOC/[0-9]+/[A-Za-z0-9_.-]{1,120}$' then raise exception 'bad_path'; end if;
  if exists (select 1 from public.employee_deeds x where x.employee_id = r.employee_id and x.role_code = r.role_code and x.status = 'active' and x.id is distinct from r.supersedes_id) then raise exception 'active_deed_exists'; end if;
  if r.supersedes_id is not null then
    update public.employee_deeds set status = 'superseded', ended_by = auth.uid(), ended_at = now(), end_reason = 'revised' where id = r.supersedes_id and status = 'active';
  end if;
  update public.employee_deeds set status = 'active', signed_at = p_signed_at, signed_doc_path = p_signed_doc, activated_by = auth.uid(), activated_at = now() where id = r.id returning * into r;
  return jsonb_build_object('id', r.id, 'status', r.status, 'revision_no', r.revision_no);
end $$;

create or replace function public.deed_attach_signed(p_id bigint, p_path text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.employee_deeds;
begin
  perform public._emp_gate();
  select * into r from public.employee_deeds where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(r.employee_id, array['employee_manage', 'deed_manage']) then raise exception 'not allowed'; end if;
  if r.signed_doc_path is not null then raise exception 'already_attached'; end if;
  if p_path is null or p_path !~ '^EMPDOC/[0-9]+/[A-Za-z0-9_.-]{1,120}$' then raise exception 'bad_path'; end if;
  update public.employee_deeds set signed_doc_path = p_path where id = r.id;
  return jsonb_build_object('id', r.id);
end $$;

create or replace function public.deed_end(p_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.employee_deeds;
begin
  perform public._emp_gate();
  select * into r from public.employee_deeds where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(r.employee_id, array['deed_manage']) then raise exception 'not allowed'; end if;
  if r.status not in ('active', 'draft') then raise exception 'deed_not_active'; end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 or char_length(p_reason) > 300 then raise exception 'reason_required'; end if;
  update public.employee_deeds set status = 'terminated', ended_by = auth.uid(), ended_at = now(), end_reason = btrim(p_reason) where id = r.id;
  return jsonb_build_object('id', r.id, 'status', 'terminated');
end $$;

-- mark active deeds whose end date has passed as expired (any employee_manage / deed_manage holder may run it; it only applies the calendar)
create or replace function public.deed_expire_due() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public._emp_any(array['employee_manage', 'deed_manage']) then raise exception 'not allowed'; end if;
  update public.employee_deeds set status = 'expired', ended_by = auth.uid(), ended_at = now(), end_reason = 'end_date_passed' where status = 'active' and end_date < public._dhaka_today();
  get diagnostics n = row_count;
  return n;
end $$;

-- active deeds that end within p_days (null = the rule deed_expiry_warn_days) or already ended but not yet marked expired
create or replace function public.deeds_expiring(p_days int default null) returns table (deed_id bigint, employee_id uuid, employee_no text, full_name_bn text, role_code text, title text, end_date date, days_left int)
language plpgsql stable security definer set search_path = public as $$
declare v_days int := coalesce(p_days, public.rule_num('deed_expiry_warn_days')::int, 30); v_today date := public._dhaka_today();
begin
  if v_days < 0 or v_days > 3660 then raise exception 'bad_days'; end if;
  return query
    select d.id, d.employee_id, e.employee_no, e.full_name_bn, d.role_code, d.title, d.end_date, (d.end_date - v_today)::int
      from public.employee_deeds d join public.employees e on e.id = d.employee_id
     where d.status = 'active' and d.end_date is not null and d.end_date <= v_today + v_days and public._emp_ok(d.employee_id, array['employee_manage', 'deed_manage'])
     order by d.end_date, d.id;
end $$;

-- ---------- function grants: the browser calls the listed ones; helpers are closed to everybody but the definer ----------
do $$
declare p record;
begin
  for p in select oid::regprocedure as sig, proname from pg_proc where pronamespace = 'public'::regnamespace
           and (proname like 'employee\_%' escape '\' or proname like 'deed\_%' escape '\' or proname like 'deeds\_%' escape '\' or proname in ('staff_role_save', 'leave_entitlement_set', '_emp_ok', '_emp_any', '_loc_ok', '_emp_photo_ok')
                or proname in ('_e_txt', '_e_date', '_e_num', '_e_nid', '_emp_gate', '_dhaka_today', '_pay_clean', '_pay_calc', '_emp_pay_json', '_emp_pay_on', '_clauses_clean', '_emp_no_set',
                               '_append_only41', '_pay_comp_guard', '_deed_tpl_guard', '_deed_guard')) loop
    execute format('revoke all on function %s from public, anon', p.sig);
    if p.proname in ('_e_txt', '_e_date', '_e_num', '_e_nid', '_emp_gate', '_dhaka_today', '_pay_clean', '_pay_calc', '_emp_pay_json', '_emp_pay_on', '_clauses_clean', '_emp_no_set',
                     '_append_only41', '_pay_comp_guard', '_deed_tpl_guard', '_deed_guard') then
      execute format('revoke all on function %s from authenticated', p.sig);
    else
      execute format('grant execute on function %s to authenticated', p.sig);
    end if;
  end loop;
end $$;

-- ============================================================================
-- End of FRESH part 3 of 21.
