-- ===================== phase489.sql =====================
-- Phase 489 (X6) - GROWTH INTELLIGENCE FROM OWN DATA (works today, no provider). Read-only functions. Paste AFTER phase488. Paste-twice safe.
-- Every answer carries its ASSUMPTIONS and its DATA COVERAGE (trading days of each window). A day with no bill is not counted as zero sales.
-- Money and quantities come from sales_fact (status 'done' only, net of returns as the sales screens show them), filtered by can_loc, so a person sees only their places.
-- Correlation is not causation: every result says so in its "warning" text.
-- Access: the market_view / market_manage rights OR the sales report right (rpt_access('sales')). Module switch mi_on is NOT needed to read own-data growth.

do $g$ begin
  if to_regclass('public.sales_fact') is null or to_regprocedure('public._mi_can_view()') is null then raise exception 'phase489 needs phases 488 and 459 first'; end if;
end $g$;

create or replace function public._mi_growth_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public._mi_can_view() or public.rpt_access('sales') $$;

create or replace function public._mi_growth_warning() returns text language sql immutable as $$
  select 'These are past sales patterns. They show what changed, not why. Season, festivals, price, stock, staff and weather can explain them too.' $$;

-- item growth and decline between two windows. growth_pct is blank when the base window had no sales (never a fake percentage).
create or replace function public.mi_growth_items(p_d1 date, p_d2 date, p_c1 date, p_c2 date, p_loc int default null, p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows_ jsonb; cur_days int; base_days int; cal_cur int := p_d2 - p_d1 + 1; cal_base int := p_c2 - p_c1 + 1;
begin
  if not public._mi_growth_ok() then raise exception 'not allowed'; end if;
  if p_d2 < p_d1 or p_c2 < p_c1 then raise exception 'bad_window'; end if;
  select count(distinct day) into cur_days from public.sales_fact where status = 'done' and day between p_d1 and p_d2 and (p_loc is null or location_id = p_loc) and public.can_loc(location_id);
  select count(distinct day) into base_days from public.sales_fact where status = 'done' and day between p_c1 and p_c2 and (p_loc is null or location_id = p_loc) and public.can_loc(location_id);
  select coalesce(jsonb_agg(to_jsonb(z) order by abs(coalesce(z.change_value, 0)) desc, z.item_name), '[]'::jsonb) into rows_ from (
    select coalesce(x.item_id::text, 'quick') as item_id, coalesce(max(x.item_name), 'Quick sale') as item_name, coalesce(max(x.category), '') as category,
           round(sum(case when x.in_cur then x.net else 0 end), 2) as cur_net, round(sum(case when x.in_base then x.net else 0 end), 2) as base_net,
           round(sum(case when x.in_cur then x.net else 0 end) - sum(case when x.in_base then x.net else 0 end), 2) as change_value,
           case when sum(case when x.in_base then x.net else 0 end) > 0
                then round(100 * (sum(case when x.in_cur then x.net else 0 end) - sum(case when x.in_base then x.net else 0 end)) / sum(case when x.in_base then x.net else 0 end), 1) end as growth_pct,
           round(sum(case when x.in_cur then x.qty else 0 end), 2) as cur_qty, round(sum(case when x.in_base then x.qty else 0 end), 2) as base_qty
      from (select f.item_id, f.item_name, f.category, f.net, f.qty, f.day between p_d1 and p_d2 as in_cur, f.day between p_c1 and p_c2 as in_base
              from public.sales_fact f
             where f.status = 'done' and ((f.day between p_d1 and p_d2) or (f.day between p_c1 and p_c2))
               and (p_loc is null or f.location_id = p_loc) and public.can_loc(f.location_id)) x
     group by coalesce(x.item_id::text, 'quick')
     order by abs(sum(case when x.in_cur then x.net else 0 end) - sum(case when x.in_base then x.net else 0 end)) desc
     limit least(greatest(coalesce(p_limit, 50), 1), 200)
  ) z;
  return jsonb_build_object('rows', rows_, 'coverage', jsonb_build_object('current_trading_days', cur_days, 'current_calendar_days', cal_cur,
           'base_trading_days', base_days, 'base_calendar_days', cal_base),
         'assumptions', jsonb_build_array('Net sales of done bills, per window.', 'A blank growth_pct means the base window had no sales of the item.', 'Items with no sales in either window are not listed.'),
         'warning', public._mi_growth_warning());
end $$;

-- outlet comparison: sales per trading day (not per calendar day), so a shop with more closed days is not made to look worse
create or replace function public.mi_outlet_compare(p_d1 date, p_d2 date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows_ jsonb;
begin
  if not public._mi_growth_ok() then raise exception 'not allowed'; end if;
  if p_d2 < p_d1 then raise exception 'bad_window'; end if;
  select coalesce(jsonb_agg(to_jsonb(z) order by z.net_total desc), '[]'::jsonb) into rows_ from (
    select f.location_id, max(f.location_en) as outlet, count(distinct f.day) as trading_days, count(distinct f.sale_id) as bills,
           round(sum(f.net), 2) as net_total, round(sum(f.net) / nullif(count(distinct f.day), 0), 2) as net_per_trading_day
      from public.sales_fact f
     where f.status = 'done' and f.day between p_d1 and p_d2 and public.can_loc(f.location_id)
     group by f.location_id) z;
  return jsonb_build_object('rows', rows_, 'calendar_days', p_d2 - p_d1 + 1,
    'assumptions', jsonb_build_array('Per trading day = net sales divided by the days that had at least one bill.', 'Outlets with different sizes or products are not like for like.'),
    'warning', public._mi_growth_warning());
end $$;

-- basket analysis: pairs of items that appear on the same bill. support = bills with both / all bills in the window
create or replace function public.mi_basket_pairs(p_d1 date, p_d2 date, p_loc int default null, p_limit int default 20) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows_ jsonb; bills int;
begin
  if not public._mi_growth_ok() then raise exception 'not allowed'; end if;
  select count(distinct f.sale_id) into bills from public.sales_fact f where f.status = 'done' and f.day between p_d1 and p_d2 and (p_loc is null or f.location_id = p_loc) and public.can_loc(f.location_id);
  select coalesce(jsonb_agg(to_jsonb(z) order by z.bills_together desc, z.item_a), '[]'::jsonb) into rows_ from (
    select a.item_name as item_a, b.item_name as item_b, count(*) as bills_together,
           round(100.0 * count(*) / nullif(bills, 0), 1) as share_of_bills_pct
      from (select distinct f.sale_id, f.item_id, f.item_name from public.sales_fact f where f.status = 'done' and f.item_id is not null and f.day between p_d1 and p_d2
             and (p_loc is null or f.location_id = p_loc) and public.can_loc(f.location_id)) a
      join (select distinct f.sale_id, f.item_id, f.item_name from public.sales_fact f where f.status = 'done' and f.item_id is not null and f.day between p_d1 and p_d2
             and (p_loc is null or f.location_id = p_loc) and public.can_loc(f.location_id)) b on b.sale_id = a.sale_id and b.item_id > a.item_id
     group by a.item_name, b.item_name
     order by count(*) desc
     limit least(greatest(coalesce(p_limit, 20), 1), 100)) z;
  return jsonb_build_object('bills', bills, 'rows', rows_,
    'assumptions', jsonb_build_array('Items bought on the same bill. Not a recommendation by itself: check margin and stock before acting.'),
    'warning', 'Bought together is a pattern in past bills. It does not show that one item makes the customer buy the other.');
end $$;

-- price response hint: only when the owner typed the minimum days; only prices with enough trading days are compared
create or replace function public.mi_price_response(p_item uuid, p_d1 date, p_d2 date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare mind int := public.rule_num('mi_elast_min_days')::int; levels jsonb; n int; hint text; lv record; parts text[] := '{}';
begin
  if not public._mi_growth_ok() then raise exception 'not allowed'; end if;
  if mind is null then return jsonb_build_object('hint', null, 'why', 'Blank setting: no price-response hint is shown. The owner types the minimum days in settings (mi_elast_min_days).'); end if;
  select coalesce(jsonb_agg(to_jsonb(z) order by z.price), '[]'::jsonb) into levels from (
    select f.price, count(distinct f.day) as days, round(sum(f.qty) / nullif(count(distinct f.day), 0), 2) as qty_per_trading_day
      from public.sales_fact f where f.status = 'done' and f.item_id = p_item and f.day between p_d1 and p_d2 and public.can_loc(f.location_id)
     group by f.price) z;
  select count(*) into n from jsonb_array_elements(levels) x where (x->>'days')::int >= mind;
  if n < 2 then
    return jsonb_build_object('hint', null, 'levels', levels, 'min_days', mind, 'why', 'Fewer than two prices with at least ' || mind || ' trading days in the window: no hint.');
  end if;
  for lv in select * from jsonb_to_recordset(levels) as x(price numeric, days int, qty_per_trading_day numeric) where days >= mind order by price loop
    parts := parts || (lv.price::text || ': ' || lv.qty_per_trading_day || ' units per trading day over ' || lv.days || ' days');
  end loop;
  hint := 'In this window: ' || array_to_string(parts, ' | ') || '. A past pattern only; a price change is never the only thing that changed.';
  return jsonb_build_object('hint', hint, 'levels', levels, 'min_days', mind,
    'assumptions', jsonb_build_array('Units per trading day at each price actually charged.', 'No cost, competitor or weather effect is modelled.'),
    'warning', public._mi_growth_warning());
end $$;

-- festival uplift review: the owner's festival window against the same number of days just before it (per trading day)
create or replace function public.mi_festival_uplift(p_festival bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare fc public.festival_calendar; len int; bf date; bt date; fa numeric; fd int; ba numeric; bd int;
begin
  if not public._mi_growth_ok() then raise exception 'not allowed'; end if;
  select * into fc from public.festival_calendar where id = p_festival;
  if not found then raise exception 'not_found'; end if;
  len := fc.end_date - fc.start_date + 1; bt := fc.start_date - 1; bf := bt - len + 1;
  select coalesce(sum(f.net), 0), count(distinct f.day) into fa, fd from public.sales_fact f
    where f.status = 'done' and f.day between fc.start_date and fc.end_date and (fc.location_id is null or f.location_id = fc.location_id) and public.can_loc(f.location_id);
  select coalesce(sum(f.net), 0), count(distinct f.day) into ba, bd from public.sales_fact f
    where f.status = 'done' and f.day between bf and bt and (fc.location_id is null or f.location_id = fc.location_id) and public.can_loc(f.location_id);
  return jsonb_build_object('festival', fc.name_en, 'festival_bn', fc.name_bn, 'festival_from', fc.start_date, 'festival_to', fc.end_date,
    'comparison_from', bf, 'comparison_to', bt,
    'festival_net_per_trading_day', round(fa / nullif(fd, 0), 2), 'comparison_net_per_trading_day', round(ba / nullif(bd, 0), 2),
    'observed_uplift_pct', case when ba > 0 and bd > 0 and fd > 0 then round(100 * ((fa / fd) - (ba / bd)) / (ba / bd), 1) end,
    'owner_entered_uplift_pct', fc.uplift_pct,
    'coverage', jsonb_build_object('festival_trading_days', fd, 'festival_calendar_days', len, 'comparison_trading_days', bd),
    'assumptions', jsonb_build_array('The comparison is the same number of days just before the festival.', 'The owner uplift % is shown as typed; nothing is guessed.'),
    'warning', public._mi_growth_warning());
end $$;

revoke all on function public._mi_growth_ok(), public._mi_growth_warning(), public.mi_growth_items(date, date, date, date, int, int), public.mi_outlet_compare(date, date),
  public.mi_basket_pairs(date, date, int, int), public.mi_price_response(uuid, date, date), public.mi_festival_uplift(bigint) from public, anon;
grant execute on function public.mi_growth_items(date, date, date, date, int, int), public.mi_outlet_compare(date, date), public.mi_basket_pairs(date, date, int, int),
  public.mi_price_response(uuid, date, date), public.mi_festival_uplift(bigint) to authenticated;

notify pgrst, 'reload schema';

-- ===================== phase490.sql =====================
-- Phase 490 (X6) - THE SCHEDULED RESEARCH HOOK (OFF), the AI summariser slot (proposal only), competitor price alerts and the weekly owner digest. Paste AFTER phase489. Paste-twice safe.
-- Nothing here fetches anything. The job runner (X1 job_runs, phases 479-489) is NOT in this build: it will call mi_research_gate() before every run and mi_job_mark_run() after it. Until X1 is pasted and the owner switches the job on, no job runs.
-- The research GATE (every condition must hold; the reasons are returned in words):
--   mi_on and mi_research_job_on and mi_scrape_on are ON; the source is active; the owner has set terms_allow_scraping ON with a terms check date;
--   robots_ok is true and checked; a rate limit (requests per hour) is typed; the adapter is allowed to use the network (set by the owner, mi_adapter_set).
--   The mock adapter never uses the network and is the only adapter a test can run.
-- Never bypassed: logins, paywalls, bulk copying (findings keep the owner's own summary; quotes only within mi_quote_max_chars).

do $g$ begin
  if to_regprocedure('public.mi_finding_add(jsonb, uuid)') is null or to_regclass('public.notifications') is null then raise exception 'phase490 needs phase488 and the notifications base first'; end if;
end $g$;

create or replace function public.mi_research_gate(p_source uuid, p_adapter text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s public.mi_sources; a public.mi_adapters; why text[] := '{}'; ad text;
begin
  if not public._mi_on() then why := array_append(why, 'the market workspace is off'); end if;
  if not public.rule_on('mi_research_job_on') then why := array_append(why, 'scheduled research is off (mi_research_job_on)'); end if;
  if not public.rule_on('mi_scrape_on') then why := array_append(why, 'fetching of sources is off (mi_scrape_on)'); end if;
  select * into s from public.mi_sources where id = p_source;
  if not found or s.status <> 'active' then why := array_append(why, 'the source is not active or does not exist'); end if;
  if found and not s.terms_allow_scraping then why := array_append(why, 'the owner has not allowed scraping this source (terms flag is NO)'); end if;
  if found and s.terms_allow_scraping and s.terms_checked_on is null then why := array_append(why, 'terms check date is missing'); end if;
  if found and s.robots_ok is distinct from true then why := array_append(why, 'robots.txt check has not passed'); end if;
  if found and s.rate_limit_per_hour is null then why := array_append(why, 'no rate limit typed for this source'); end if;
  ad := coalesce(p_adapter, 'mock_offline');
  select * into a from public.mi_adapters where code = ad;
  if not found then why := array_append(why, 'unknown adapter'); elsif a.kind <> 'mock' and not a.network_allowed then why := array_append(why, 'the adapter may not use the network yet (owner has not linked it)'); end if;
  return jsonb_build_object('allowed', cardinality(why) = 0, 'reasons', to_jsonb(why), 'adapter', ad,
    'rule', 'Every condition must hold. Logins, paywalls and bulk copying are never used.');
end $$;

-- the owner links (or unlinks) an adapter to the network. Owner only; written to the change log.
create or replace function public.mi_adapter_set(p_code text, p_network_allowed boolean, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sid text; a public.mi_adapters;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if p_code = 'mock_offline' and p_network_allowed then raise exception 'mock_never_uses_network'; end if;
  update public.mi_adapters set network_allowed = coalesce(p_network_allowed, false) where code = p_code returning * into a;
  if not found then raise exception 'not_found'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'mi_adapter_set', 'mi_adapters', p_code, jsonb_build_object('network_allowed', a.network_allowed, 'reason', left(btrim(p_reason), 300)));
  return jsonb_build_object('code', p_code, 'network_allowed', a.network_allowed);
end $$;

-- a research job definition. Stored OFF. Turning it ON is refused unless the gate passes for its source.
create or replace function public.mi_job_save(p_key text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d jsonb := coalesce(p, '{}'::jsonb); j public.mi_job_defs; want boolean := coalesce((d->>'enabled')::boolean, false); g jsonb; sid uuid := nullif(d->>'source_id', '')::uuid;
begin
  if not public._mi_on() then raise exception 'module_off: the market workspace is switched off'; end if;
  if not public.is_owner() then raise exception 'not allowed: only the owner schedules research'; end if;
  if want then
    if sid is null then raise exception 'source_required'; end if;
    g := public.mi_research_gate(sid, coalesce(d->>'adapter_code', 'mock_offline'));
    if not (g->>'allowed')::boolean then raise exception 'gate_closed: %', g->>'reasons'; end if;
  end if;
  insert into public.mi_job_defs (key, label, source_id, adapter_code, schedule_cron, enabled, created_by, updated_by)
    values (p_key, btrim(d->>'label'), sid, coalesce(d->>'adapter_code', 'mock_offline'), nullif(btrim(d->>'schedule_cron'), ''), want, auth.uid(), auth.uid())
    on conflict (key) do update set label = excluded.label, source_id = excluded.source_id, adapter_code = excluded.adapter_code,
      schedule_cron = excluded.schedule_cron, enabled = excluded.enabled, updated_by = auth.uid(), updated_at = now();
  return jsonb_build_object('key', p_key, 'enabled', want);
end $$;

-- written by the job runner after a run that the gate allowed (the runner itself is X1)
create or replace function public.mi_job_mark_run(p_key text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.mi_job_defs;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  update public.mi_job_defs set last_run_at = now() where key = p_key and enabled returning * into j;
  if not found then raise exception 'not_enabled'; end if;
  return jsonb_build_object('key', p_key, 'last_run_at', j.last_run_at);
end $$;

-- ---------- AI summariser: PROPOSALS only (the agent runs under a person's login; the person who asked can not accept it) ----------
create or replace function public.mi_summary_propose(p_finding_ids uuid[], p_text text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int; pr public.mi_summary_proposals;
begin
  if not public._mi_on() or not public.rule_on('mi_ai_summary_on') then raise exception 'module_off: the AI summariser is switched off'; end if;
  if not public._mi_can_manage() then raise exception 'not allowed'; end if;
  if cardinality(p_finding_ids) = 0 then raise exception 'findings_required'; end if;
  select count(*) into n from public.mi_findings where id = any (p_finding_ids);
  if n <> cardinality(p_finding_ids) then raise exception 'findings_not_found'; end if;
  insert into public.mi_summary_proposals (finding_ids, proposed_text, created_by) values (p_finding_ids, btrim(p_text), auth.uid()) returning * into pr;
  return jsonb_build_object('id', pr.id, 'status', 'proposed', 'note', 'A proposal only. Nothing is saved as a finding until a person accepts it and writes it as a finding.');
end $$;

create or replace function public.mi_summary_decide(p_id bigint, p_decision text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pr public.mi_summary_proposals;
begin
  if not public._mi_can_manage() then raise exception 'not allowed'; end if;
  if p_decision not in ('accepted', 'rejected') then raise exception 'bad_decision'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  select * into pr from public.mi_summary_proposals where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if exists (select 1 from public.mi_summary_decisions d where d.proposal_id = p_id) then raise exception 'already_decided'; end if;
  if pr.created_by = auth.uid() then raise exception 'own_request: the person who asked can not accept it (build rule 8)'; end if;
  insert into public.mi_summary_decisions (proposal_id, decision, reason, decided_by) values (p_id, p_decision, left(btrim(p_reason), 300), auth.uid());
  return jsonb_build_object('id', p_id, 'status', p_decision);
end $$;

-- ---------- competitor price watchlist: the last two observations of each competitor item ----------
create or replace function public.mi_watch_alerts() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare th numeric := public.rule_num('mi_watch_threshold_pct'); rows_ jsonb;
begin
  if not public._mi_can_view() then raise exception 'not allowed'; end if;
  if th is null then return jsonb_build_object('threshold', null, 'alerts', '[]'::jsonb, 'note', 'Blank threshold: no competitor price alert is produced.'); end if;
  select coalesce(jsonb_agg(to_jsonb(z) order by abs(z.change_pct) desc), '[]'::jsonb) into rows_ from (
    select competitor, item_label, prev_price, price as last_price, prev_on, observed_on as last_on, round(100 * (price - prev_price) / prev_price, 1) as change_pct
      from (select o.*, lag(o.price) over (partition by lower(o.competitor), lower(o.item_label) order by o.observed_on, o.id) as prev_price,
                   lag(o.observed_on) over (partition by lower(o.competitor), lower(o.item_label) order by o.observed_on, o.id) as prev_on,
                   row_number() over (partition by lower(o.competitor), lower(o.item_label) order by o.observed_on desc, o.id desc) as rn
              from public.mi_price_obs o) q
     where rn = 1 and prev_price is not null and prev_price > 0 and abs(100 * (price - prev_price) / prev_price) > th) z;
  return jsonb_build_object('threshold', th, 'alerts', rows_, 'note', 'Each row: a competitor price that moved more than the threshold since its previous observation.');
end $$;

-- one in-app line per day for the owner when alerts exist and the switches allow it (counts only, no customer data)
create or replace function public.mi_alert_notify() returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int; day_ date := public._mi_today(); made boolean := false; a jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not (public._mi_on() and public.rule_on('mi_alerts_on')) then return jsonb_build_object('created', false, 'why', 'switched off'); end if;
  a := public.mi_watch_alerts();
  n := jsonb_array_length(a->'alerts');
  if n = 0 then return jsonb_build_object('created', false, 'why', 'no alerts'); end if;
  insert into public.notifications (user_id, audience, kind, level, title_bn, title_en, body_bn, body_en, route, key, day)
    values (null, 'owner', 'mi_price_alert', 'info', 'প্রতিযোগীর দাম বদলেছে', 'Competitor prices moved', n || ' item(s) moved beyond your threshold', n || ' item(s) moved beyond your threshold', 'market', 'mi_price_alert', day_)
    on conflict (kind, key, day) do nothing;
  made := found;
  return jsonb_build_object('created', made, 'alerts', n);
end $$;

-- weekly digest (in-app, owner): your sales growth and decline, open opportunities, price alerts. Numbers only; no customer data.
create or replace function public.mi_growth_digest(p_d1 date, p_d2 date, p_c1 date, p_c2 date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g jsonb; summ jsonb; al jsonb; made boolean := false; body text;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  g := public.mi_growth_items(p_d1, p_d2, p_c1, p_c2, null, 5);
  summ := public.mi_summary();
  al := public.mi_watch_alerts();
  body := 'Top movers in the week: ' || coalesce((select string_agg(x->>'item_name' || ' ' || coalesce(x->>'growth_pct', 'n/a') || '%', ', ') from jsonb_array_elements(g->'rows') x), 'none')
        || '. Open opportunities: ' || (summ->'opportunities')::text || '. Price alerts: ' || jsonb_array_length(al->'alerts') || '.';
  if public.rule_on('mi_digest_on') and public._mi_on() then
    insert into public.notifications (user_id, audience, kind, level, title_bn, title_en, body_bn, body_en, route, key, day)
      values (null, 'owner', 'mi_weekly_digest', 'info', 'সাপ্তাহিক বাজার ও বৃদ্ধির সারসংক্ষেপ', 'Weekly market and growth digest', body, body, 'market', 'mi_digest', public._mi_today())
      on conflict (kind, key, day) do nothing;
    made := found;
  end if;
  return jsonb_build_object('digest', body, 'created', made, 'growth', g, 'summary', summ, 'alerts', al->'alerts');
end $$;

-- ---------- privileges ----------
revoke all on function public.mi_research_gate(uuid, text), public.mi_adapter_set(text, boolean, text), public.mi_job_save(text, jsonb), public.mi_job_mark_run(text),
  public.mi_summary_propose(uuid[], text), public.mi_summary_decide(bigint, text, text), public.mi_watch_alerts(), public.mi_alert_notify(),
  public.mi_growth_digest(date, date, date, date) from public, anon;
grant execute on function public.mi_research_gate(uuid, text), public.mi_adapter_set(text, boolean, text), public.mi_job_save(text, jsonb), public.mi_job_mark_run(text),
  public.mi_summary_propose(uuid[], text), public.mi_summary_decide(bigint, text, text), public.mi_watch_alerts(), public.mi_alert_notify(),
  public.mi_growth_digest(date, date, date, date) to authenticated;

notify pgrst, 'reload schema';

-- ===================== phase491.sql =====================
-- ============================================================
-- Phase 491 - XB package part 1: bKash / Nagad / Rocket payment capture and reconciliation.
-- Run AFTER phase 478 (needs phase61 online_orders, phase83 d_wallets, phase6 sales). New file only; no old phase or function is edited.
-- Paste twice = no error, no second row.
--
--   * pay_captures          one row per mobile payment the counter writes down: provider, Trx-ID, sender number, amount, time, wallet,
--                           the order / sale / advance it is for, the amount expected, the flag (ok / overpay / underpay / no_target).
--                           A Trx-ID is unique (a duplicate is refused). Verification: pending -> verified | rejected (approver holds
--                           grant pay_verify or is the owner; never the person who captured it). Append-only (decision fields only).
--   * xb_pay_capture        write a capture (rule pay_capture_on OFF = refused). Nothing is posted to the books: a capture is evidence.
--   * xb_pay_capture_decide approve / reject; a flagged capture needs a note.
--   * xb_pay_capture_screenshot  attach a payment screenshot (private bucket 'payproof', path pay/<place>/<file>.jpg), once.
--   * pay_statement_lines   wallet statement lines imported from CSV / paste (append-only, deduplicated on wallet + Trx-ID + direction).
--   * xb_pay_statement_import   owner or a pay_verify holder (place-less grant) imports a statement; duplicates are counted, not written twice.
--   * xb_pay_tieout         daily tie-out per wallet: captured vs statement, with the lists of what does not match.
--   * Rules (OFF / blank): pay_capture_on (OFF), pay_capture_tol (blank = the amount must match exactly; no tolerance is invented).
-- No merchant API adapter is built: statement and capture records are the only inputs; no outbound call exists anywhere.
-- Paper form code for any printed version: to be given by owner (none invented).
-- ============================================================
do $guard$ begin
  if to_regclass('public.online_orders') is null or to_regclass('public.d_wallets') is null or to_regclass('public.sales') is null
     or to_regprocedure('public.c2_orders_features()') is null then
    raise exception 'phase491 needs phase61, phase83, phase6 and phase445 pasted first';
  end if;
end $guard$;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('pay_verify', 'pos', 90, 'মোবাইল পেমেন্ট যাচাই করা', 'Mobile payment verify করা', 'Verify mobile payments (bKash / Nagad / Rocket)', 'once', null)
on conflict (grant_code) do nothing;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('pay_capture_on', 'pos', 'switch', 'false', null, null, null, null, 'মোবাইল পেমেন্ট (Trx-ID) লেখা চালু', 'Mobile payment (Trx-ID) capture চালু', 'Mobile payment capture is on',
  'চালু হলে বিকাশ/নগদ/রকেটের Trx-ID, নম্বর, টাকা লেখা যাবে; একই Trx-ID দুবার ঢোকে না।', 'When on, bKash / Nagad / Rocket Trx-ID, sender, amount and time can be written; a Trx-ID is never accepted twice.', 540),
 ('pay_capture_tol', 'pos', 'number', null, 'taka', null, 0, 1000000, 'মেলানোর সহনশীলতা (টাকা)', 'Match tolerance (taka)', 'Amount match tolerance (taka)',
  'ফাঁকা = টাকা হুবহু মিলতে হবে। কোনো সংখ্যা ধরে নেওয়া হয় না।', 'Blank = the amount must match exactly. No number is assumed.', 541)
on conflict (key) do nothing;

-- ---------- tables ----------
create table if not exists public.pay_captures (
  id bigint generated always as identity primary key,
  client_id uuid unique,
  provider text not null check (provider in ('bkash', 'nagad', 'rocket', 'other')),
  wallet_code text not null references public.d_wallets(code),
  trx_id text not null check (trx_id ~ '^[A-Z0-9]{6,20}$'),
  sender_no text check (sender_no is null or char_length(sender_no) between 6 and 20),
  amount numeric not null check (amount > 0 and amount <= 1000000000000),
  paid_at timestamptz not null,
  location_id int not null references public.locations(id),
  target text not null check (target in ('order', 'sale', 'advance', 'none')),
  online_order_id uuid references public.online_orders(id),
  sale_id uuid references public.sales(id),
  expected numeric,
  diff numeric,
  flag text not null check (flag in ('ok', 'overpay', 'underpay', 'no_target')),
  status text not null default 'pending' check (status in ('pending', 'verified', 'rejected', 'void')),
  source text not null default 'manual' check (source in ('manual', 'sms_paste')),
  screenshot_path text check (screenshot_path is null or char_length(screenshot_path) <= 200),
  note text check (note is null or char_length(note) <= 300),
  captured_by uuid, captured_staff text, captured_at timestamptz not null default now(),
  decided_by uuid, decided_at timestamptz, decide_note text check (decide_note is null or char_length(decide_note) <= 300),
  check ((target = 'order') = (online_order_id is not null) or target = 'advance'), check ((target = 'sale') = (sale_id is not null))
);
create unique index if not exists pay_captures_trx_live on public.pay_captures (trx_id) where status <> 'void';
create index if not exists pay_captures_day on public.pay_captures (location_id, paid_at);

create table if not exists public.pay_statement_lines (
  id bigint generated always as identity primary key,
  wallet_code text not null references public.d_wallets(code),
  trx_id text not null check (trx_id ~ '^[A-Z0-9]{6,20}$'),
  direction text not null check (direction in ('in', 'out')),
  amount numeric not null check (amount > 0 and amount <= 1000000000000),
  stmt_at timestamptz not null,
  counterpart text check (counterpart is null or char_length(counterpart) <= 40),
  import_batch uuid not null,
  imported_by uuid, imported_at timestamptz not null default now(),
  unique (wallet_code, trx_id, direction)
);

-- captures: only the decision fields and the screenshot path move; nothing is deleted
create or replace function public._xb540_pay_ro() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: a payment capture is never deleted, void it through the decision'; end if;
  if (to_jsonb(new) - 'status' - 'decided_by' - 'decided_at' - 'decide_note' - 'screenshot_path')
     is distinct from (to_jsonb(old) - 'status' - 'decided_by' - 'decided_at' - 'decide_note' - 'screenshot_path') then
    raise exception 'append_only: a payment capture changes only its decision and its screenshot';
  end if;
  if old.screenshot_path is not null and new.screenshot_path is distinct from old.screenshot_path then raise exception 'already_attached'; end if;
  if old.status in ('verified', 'rejected', 'void') and new.status is distinct from old.status then raise exception 'decided: a decided capture cannot change'; end if;
  return new;
end $$;
drop trigger if exists pay_captures_ro on public.pay_captures;
create trigger pay_captures_ro before update or delete on public.pay_captures for each row execute function public._xb540_pay_ro();
drop trigger if exists audit_pay_captures on public.pay_captures;
create trigger audit_pay_captures after insert or update on public.pay_captures for each row execute function public.log_change('id');

create or replace function public._xb540_lines_ro() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: a statement line is never changed or deleted'; end $$;
drop trigger if exists pay_statement_lines_ro on public.pay_statement_lines;
create trigger pay_statement_lines_ro before update or delete on public.pay_statement_lines for each row execute function public._xb540_lines_ro();
drop trigger if exists audit_pay_statement_lines on public.pay_statement_lines;
create trigger audit_pay_statement_lines after insert on public.pay_statement_lines for each row execute function public.log_change('id');

-- ---------- helpers ----------
create or replace function public._xb540_verifier(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_owner() or public.has_grant('pay_verify', p_loc);
$$;
create or replace function public._xb540_verifier_any() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_owner() or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'pay_verify' and g.location_id is null);
$$;
create or replace function public._xb540_gate(p_loc int) returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('pay_capture_on') then raise exception 'module_off'; end if;
  if not public.can_do('POS', 'enter') or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
end $$;

-- ---------- capture ----------
create or replace function public.xb_pay_capture(p_client uuid, p_provider text, p_trx text, p_sender text, p_amount numeric, p_paid_at timestamptz,
  p_wallet text, p_loc int, p_target text, p_order uuid default null, p_sale uuid default null, p_source text default 'manual', p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare trx text := upper(btrim(coalesce(p_trx, ''))); o public.online_orders; s public.sales; ex numeric; df numeric; fl text; tol numeric := coalesce(public.rule_num('pay_capture_tol'), 0);
        rec public.pay_captures; wok boolean; id_ bigint; ol uuid; sl uuid; sndr text;
begin
  if p_client is not null then
    select * into rec from public.pay_captures where client_id = p_client;
    if found then return jsonb_build_object('id', rec.id, 'status', rec.status, 'flag', rec.flag, 'dup', true); end if;
  end if;
  perform public._xb540_gate(p_loc);
  if p_provider not in ('bkash', 'nagad', 'rocket', 'other') then raise exception 'bad_provider'; end if;
  if trx !~ '^[A-Z0-9]{6,20}$' then raise exception 'bad_trx_id'; end if;
  if p_amount is null or p_amount <= 0 or p_amount > 1000000000000 then raise exception 'bad_amount'; end if;
  if p_paid_at is null or p_paid_at > now() + interval '10 minutes' then raise exception 'bad_time'; end if;
  if p_source not in ('manual', 'sms_paste') then raise exception 'bad_source'; end if;
  if p_target not in ('order', 'sale', 'advance', 'none') then raise exception 'bad_target'; end if;
  select exists (select 1 from public.d_wallets w where w.code = p_wallet and w.active) into wok;
  if not wok then raise exception 'bad_wallet'; end if;
  sndr := nullif(btrim(coalesce(p_sender, '')), '');
  if sndr is not null then sndr := public.norm_mobile(sndr); if sndr is null or char_length(sndr) < 6 then raise exception 'bad_sender'; end if; end if;
  if exists (select 1 from public.pay_captures where trx_id = trx and status <> 'void') then raise exception 'duplicate_trx: this Trx-ID is already written'; end if;
  ex := null;
  if p_target = 'order' then
    select * into o from public.online_orders where id = p_order;
    if not found then raise exception 'not_found'; end if;
    if o.location_id <> p_loc then raise exception 'other_location'; end if;
    if o.status in ('delivered', 'cancelled') then raise exception 'order_closed'; end if;
    ex := o.subtotal - o.discount + o.delivery_charge - o.advance; ol := o.id;
  elsif p_target = 'sale' then
    select * into s from public.sales where id = p_sale;
    if not found then raise exception 'not_found'; end if;
    if s.location_id <> p_loc then raise exception 'other_location'; end if;
    ex := s.due_amount; sl := s.id;
  elsif p_target = 'advance' then
    select * into o from public.online_orders where id = p_order;
    if not found then raise exception 'not_found'; end if;
    if o.location_id <> p_loc then raise exception 'other_location'; end if;
    ol := o.id;
    ex := case when o.advance > 0 then o.advance end;
  end if;
  if ex is null then fl := 'no_target'; df := null;
  else
    df := round(p_amount - ex, 2);
    fl := case when abs(df) <= tol then 'ok' when df > 0 then 'overpay' else 'underpay' end;
  end if;
  insert into public.pay_captures (client_id, provider, wallet_code, trx_id, sender_no, amount, paid_at, location_id, target, online_order_id, sale_id, expected, diff, flag, source, note, captured_by, captured_staff)
    values (p_client, p_provider, p_wallet, trx, sndr, round(p_amount, 2), p_paid_at, p_loc, p_target, ol, sl, ex, df, fl, p_source, left(nullif(btrim(p_note), ''), 300), auth.uid(), (select staff_id from public.profiles where id = auth.uid()))
    returning id into id_;
  return jsonb_build_object('id', id_, 'status', 'pending', 'flag', fl, 'expected', ex, 'diff', df, 'note_needed_to_verify', fl <> 'ok');
exception when unique_violation then
  raise exception 'duplicate_trx: this Trx-ID is already written';
end $$;

-- ---------- verify (nobody approves the capture they wrote; a flagged or rejected one needs a note) ----------
create or replace function public.xb_pay_capture_decide(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rec public.pay_captures;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into rec from public.pay_captures where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public.can_loc(rec.location_id) or not public._xb540_verifier(rec.location_id) then raise exception 'not allowed'; end if;
  if p_approve is null then raise exception 'bad_input'; end if;
  if rec.status <> 'pending' then raise exception 'already_decided'; end if;
  if rec.captured_by = auth.uid() then raise exception 'own_capture: nobody approves the capture they wrote'; end if;
  if (rec.flag <> 'ok' or not p_approve) and length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.pay_captures set status = case when p_approve then 'verified' else 'rejected' end, decided_by = auth.uid(), decided_at = now(),
    decide_note = left(nullif(btrim(p_note), ''), 300) where id = rec.id;
  return jsonb_build_object('id', rec.id, 'status', case when p_approve then 'verified' else 'rejected' end, 'flag', rec.flag);
end $$;

create or replace function public.xb_pay_capture_screenshot(p_id bigint, p_path text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rec public.pay_captures;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into rec from public.pay_captures where id = p_id;
  if not found then raise exception 'not_found'; end if;
  if not public.can_loc(rec.location_id) or not public.can_do('POS', 'enter') then raise exception 'not allowed'; end if;
  if rec.screenshot_path is not null then raise exception 'already_attached'; end if;
  if p_path is null or p_path !~ ('^pay/' || rec.location_id || '/[A-Za-z0-9_.-]{1,120}\.jpe?g$') then raise exception 'bad_path'; end if;
  update public.pay_captures set screenshot_path = p_path where id = rec.id;
  return jsonb_build_object('id', rec.id, 'screenshot_path', p_path);
end $$;

create or replace function public.xb_pay_captures_list(p_loc int default null, p_status text default null, p_day date default null, p_limit int default 200) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(z) order by z.paid_at desc), '[]'::jsonb) from (
    select c.id, c.provider, c.wallet_code, c.trx_id, c.sender_no, c.amount, c.paid_at, c.location_id, c.target, c.online_order_id, c.sale_id, c.expected, c.diff, c.flag, c.status,
           c.screenshot_path is not null as has_screenshot, c.captured_staff, c.decided_at, c.decide_note
      from public.pay_captures c
     where public.is_active() and (public.is_owner() or public.can_do('POS', 'view')) and public.can_loc(c.location_id)
       and (p_loc is null or c.location_id = p_loc) and (p_status is null or c.status = p_status)
       and (p_day is null or (c.paid_at at time zone 'Asia/Dhaka')::date = p_day)
     order by c.paid_at desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) z;
$$;

-- ---------- statement import and tie-out ----------
create or replace function public.xb_pay_statement_import(p_wallet text, p_lines jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare batch uuid := gen_random_uuid(); ln jsonb; ins int := 0; dup int := 0; bad int := 0; n int;
begin
  if not public.is_active() or not public._xb540_verifier_any() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.d_wallets where code = p_wallet and active) then raise exception 'bad_wallet'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) > 2000 then raise exception 'bad_lines'; end if;
  for ln in select * from jsonb_array_elements(p_lines) loop
    if upper(btrim(coalesce(ln->>'trx_id', ''))) !~ '^[A-Z0-9]{6,20}$' or coalesce(ln->>'direction', '') not in ('in', 'out')
       or (ln->>'amount') is null or (ln->>'amount')::numeric <= 0 or (ln->>'at') is null then bad := bad + 1; continue; end if;
    insert into public.pay_statement_lines (wallet_code, trx_id, direction, amount, stmt_at, counterpart, import_batch, imported_by)
      values (p_wallet, upper(btrim(ln->>'trx_id')), ln->>'direction', round((ln->>'amount')::numeric, 2), (ln->>'at')::timestamptz,
              left(nullif(btrim(ln->>'counterpart'), ''), 40), batch, auth.uid())
      on conflict (wallet_code, trx_id, direction) do nothing;
    get diagnostics n = row_count;
    if n = 1 then ins := ins + 1; else dup := dup + 1; end if;
  end loop;
  return jsonb_build_object('wallet', p_wallet, 'batch', batch, 'inserted', ins, 'already_there', dup, 'bad_rows', bad);
end $$;

create or replace function public.xb_pay_tieout(p_date date, p_wallet text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date); out_ jsonb := '[]';
        w record; cap numeric; cap_ver numeric; stm_in numeric; stm_out numeric; l_stmt jsonb; l_erp jsonb; l_mis jsonb; nmis int; nstm int; nerp int; has_stm boolean;
begin
  if not public.is_active() or not public._xb540_verifier_any() then raise exception 'not allowed'; end if;
  for w in select code, name_en from public.d_wallets where active and (p_wallet is null or code = p_wallet) order by sort, id loop
    select coalesce(sum(amount), 0), coalesce(sum(amount) filter (where status = 'verified'), 0) into cap, cap_ver
      from public.pay_captures where wallet_code = w.code and status in ('pending', 'verified') and (paid_at at time zone 'Asia/Dhaka')::date = d;
    select coalesce(sum(amount) filter (where direction = 'in'), 0), coalesce(sum(amount) filter (where direction = 'out'), 0) into stm_in, stm_out
      from public.pay_statement_lines where wallet_code = w.code and (stmt_at at time zone 'Asia/Dhaka')::date = d;
    has_stm := exists (select 1 from public.pay_statement_lines s where s.wallet_code = w.code and (s.stmt_at at time zone 'Asia/Dhaka')::date = d);
    select coalesce(jsonb_agg(jsonb_build_object('trx_id', s.trx_id, 'amount', s.amount) order by s.trx_id), '[]'::jsonb), count(*)
      into l_stmt, nstm from public.pay_statement_lines s
     where s.wallet_code = w.code and s.direction = 'in' and (s.stmt_at at time zone 'Asia/Dhaka')::date = d
       and not exists (select 1 from public.pay_captures c where c.trx_id = s.trx_id and c.status <> 'void');
    select coalesce(jsonb_agg(jsonb_build_object('trx_id', c.trx_id, 'amount', c.amount, 'status', c.status) order by c.trx_id), '[]'::jsonb), count(*)
      into l_erp, nerp from public.pay_captures c
     where c.wallet_code = w.code and c.status = 'verified' and (c.paid_at at time zone 'Asia/Dhaka')::date = d
       and not exists (select 1 from public.pay_statement_lines s where s.wallet_code = w.code and s.trx_id = c.trx_id and s.direction = 'in');
    select coalesce(jsonb_agg(jsonb_build_object('trx_id', c.trx_id, 'captured', c.amount, 'statement', s.amount) order by c.trx_id), '[]'::jsonb), count(*)
      into l_mis, nmis from public.pay_captures c join public.pay_statement_lines s on s.wallet_code = c.wallet_code and s.trx_id = c.trx_id and s.direction = 'in'
     where c.wallet_code = w.code and c.status in ('pending', 'verified') and c.amount <> s.amount;
    out_ := out_ || jsonb_build_object('wallet', w.code, 'name_en', w.name_en, 'captured_total', cap, 'captured_verified', cap_ver,
      'statement_in', stm_in, 'statement_out', stm_out, 'statement_lines_without_capture', nstm, 'captured_not_on_statement', nerp,
      'amount_mismatch', nmis, 'statement_only', l_stmt, 'captured_only', l_erp, 'mismatch', l_mis, 'statement_imported', has_stm,
      'status', case when not has_stm then 'no_statement_imported'
                     when nstm = 0 and nerp = 0 and nmis = 0 then 'matched' else 'difference' end);
  end loop;
  return jsonb_build_object('date', d, 'wallets', out_, 'notes', jsonb_build_array('a_capture_is_evidence_not_a_posting', 'blank_tolerance_means_exact_match'));
end $$;

-- ---------- privileges and RLS ----------
alter table public.pay_captures enable row level security;
alter table public.pay_statement_lines enable row level security;
revoke all on public.pay_captures, public.pay_statement_lines from public, anon, authenticated;
grant select on public.pay_captures to authenticated;
grant select on public.pay_statement_lines to authenticated;
drop policy if exists pay_captures_sel on public.pay_captures;
create policy pay_captures_sel on public.pay_captures for select to authenticated
  using (public.is_active() and (public.is_owner() or public.can_do('POS', 'view')) and public.can_loc(location_id));
drop policy if exists pay_statement_lines_sel on public.pay_statement_lines;
create policy pay_statement_lines_sel on public.pay_statement_lines for select to authenticated using (public.is_owner() or public._xb540_verifier_any());

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('payproof', 'payproof', false, 3145728, array['image/jpeg']) on conflict (id) do nothing;
drop policy if exists xb540_payproof_ins on storage.objects;
create policy xb540_payproof_ins on storage.objects for insert to authenticated
  with check (bucket_id = 'payproof' and split_part(name, '/', 1) = 'pay' and public.is_active() and public.can_do('POS', 'enter') and public.can_loc(split_part(name, '/', 2)::int));
drop policy if exists xb540_payproof_read on storage.objects;
create policy xb540_payproof_read on storage.objects for select to authenticated
  using (bucket_id = 'payproof' and split_part(name, '/', 1) = 'pay' and public.is_active() and (public.is_owner() or public.can_do('POS', 'view')) and public.can_loc(split_part(name, '/', 2)::int));

do $x$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and (p.proname like 'xb\_pay\_%' or p.proname like '\_xb540\_%') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname like 'xb\_pay\_%' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $x$;
notify pgrst, 'reload schema';

-- ===================== phase492.sql =====================
-- ============================================================
-- Phase 492 - XB package part 2: custom-cake workflow on top of an app order.
-- Run AFTER phase 491 (and phase 445 / 448 for the order spec and cancel). New file only; no old phase or function is edited.
-- Paste twice = no error, no second row.
--
--   * cake_price_rules      owner-editable price table: base per kg, flavour extras and design extras (per kg or flat). Empty table = no quote
--                           (nothing is invented). Written only through xb_cake_price_rule_save (owner).
--   * xb_cake_quote         quote breakdown for a weight, flavour and design list (no write).
--   * cake_jobs             one cake job per app order: weight, flavour, layers, message, design notes, reference photos (paths),
--                           eggless / halal / allergen flags, due date and slot, quote lines, total, advance required, balance, state.
--   * cake_job_events       append-only trail of every state move: from, to, who (login and staff id), when, note.
--   * State chain: quoted -> confirmed (advance in the order) -> slip (production slip) -> baked -> decorated -> ready -> delivered.
--                  cancelled from any state before delivered; cancelling calls the existing c2_order_cancel (refund rules unchanged).
--                  delivered needs the app order to be delivered already (the money path stays the order's own path).
--   * Rules (OFF / blank): cake_flow_on (OFF), cake_capacity_day (blank = confirming and quoting are refused: no cap is invented),
--                  cake_lead_days (blank = refused), cake_photo_required (OFF: photo of the finished cake before delivery).
--   * xb_cake_create / xb_cake_confirm / xb_cake_move / xb_cake_photo / xb_cake_cancel: writers.
--   * xb_cake_due           production and decoration sheet for one day (printable in the web; no paper form code is invented).
--   * xb_cake_notify        customer confirmation: returns a wa.me text (the owner's phone taps send) and, when SMS is on and the customer
--                           has opted in and is not on do-not-contact, enqueues an SMS through notify_enqueue. Nothing is sent by this phase.
-- Birthday link to CRM and per-slot capacity: NOT built (see report).
-- Paper form code for a printed cake sheet: to be given by owner (none invented).
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.xb_pay_capture(uuid,text,text,text,numeric,timestamptz,text,int,text,uuid,uuid,text,text)') is null
     or to_regprocedure('public.c2_order_cancel(uuid,text,text,text)') is null or to_regprocedure('public.notify_enqueue(uuid,uuid,text,text,jsonb,text,text,text)') is null
     or to_regprocedure('public.c2_order_spec_save(uuid,jsonb,text)') is null then
    raise exception 'phase492 needs phase491, phase445-448 and phase62 pasted first';
  end if;
end $guard$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('cake_flow_on', 'pos', 'switch', 'false', null, null, null, null, 'কাস্টম কেক ওয়ার্কফ্লো চালু', 'Custom cake workflow চালু', 'Custom cake workflow is on',
  'চালু হলে কেকের কোট, অ্যাডভান্স, উৎপাদন স্লিপ, ডেকোরেশন ও ডেলিভারি ধাপ লেখা যাবে।', 'When on, cake quote, advance, production slip, decoration and delivery steps can be recorded.', 542),
 ('cake_capacity_day', 'pos', 'number', null, 'cakes', null, 1, 1000, 'একদিনে সর্বোচ্চ কেক', 'Cake per day cap', 'Maximum cakes per day',
  'ফাঁকা থাকলে নতুন কেক কোট/নিশ্চিত করা যায় না। কোনো সংখ্যা ধরে নেওয়া হয় না।', 'Blank = cakes cannot be quoted or confirmed. No number is assumed.', 543),
 ('cake_lead_days', 'pos', 'number', null, 'days', null, 0, 90, 'কেক অর্ডারের আগাম দিন', 'Cake lead time (days)', 'Cake lead time (days)',
  'ফাঁকা থাকলে কেক নেওয়া যায় না। কত দিন আগে অর্ডার দিতে হবে তা মালিক ঠিক করেন।', 'Blank = cakes cannot be taken. The owner sets how many days ahead.', 544),
 ('cake_photo_required', 'pos', 'switch', 'false', null, null, null, null, 'ডেলিভারির আগে কেকের ছবি লাগবে', 'Cake photo before delivery', 'Photo of the finished cake is required before delivery',
  'চালু থাকলে তৈরি কেকের ছবি না থাকলে ডেলিভারি হবে না।', 'On = no delivery step without a photo of the finished cake.', 545)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('cake_price_manage', 'pos', 91, 'কেকের দামের তালিকা বদল', 'Cake price list বদল', 'Change the cake price list', 'once', null)
on conflict (grant_code) do nothing;

-- ---------- price rules ----------
create table if not exists public.cake_price_rules (
  id bigint generated always as identity primary key,
  code text not null unique check (code ~ '^[a-z0-9_]{2,40}$'),
  group_kind text not null check (group_kind in ('base', 'flavour', 'design')),
  rate_kind text not null check (rate_kind in ('per_kg', 'flat')),
  label_bn text not null check (char_length(btrim(label_bn)) between 1 and 80),
  label_en text not null check (char_length(btrim(label_en)) between 1 and 80),
  amount numeric not null check (amount >= 0 and amount <= 1000000000),
  active boolean not null default true,
  updated_by uuid, updated_at timestamptz not null default now()
);
create or replace function public._xb541_no_delete() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'nothing is deleted: retire the row (active = false)'; end $$;
drop trigger if exists cake_price_rules_nodel on public.cake_price_rules;
create trigger cake_price_rules_nodel before delete on public.cake_price_rules for each row execute function public._xb541_no_delete();
drop trigger if exists audit_cake_price_rules on public.cake_price_rules;
create trigger audit_cake_price_rules after insert or update on public.cake_price_rules for each row execute function public.log_change('id');

create or replace function public.xb_cake_price_rule_save(p_code text, p_group text, p_rate text, p_label_bn text, p_label_en text, p_amount numeric, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active() or not (public.is_owner() or public.has_grant('cake_price_manage', null)) then raise exception 'not allowed'; end if;
  if p_code is null or p_code !~ '^[a-z0-9_]{2,40}$' or p_group not in ('base', 'flavour', 'design') or p_rate not in ('per_kg', 'flat')
     or p_amount is null or p_amount < 0 or p_amount > 1000000000 or p_active is null then raise exception 'bad_input'; end if;
  if p_group = 'base' and p_rate <> 'per_kg' then raise exception 'bad_input: the base price is per kg'; end if;
  insert into public.cake_price_rules (code, group_kind, rate_kind, label_bn, label_en, amount, active, updated_by)
    values (p_code, p_group, p_rate, left(btrim(coalesce(p_label_bn, '')), 80), left(btrim(coalesce(p_label_en, '')), 80), p_amount, p_active, auth.uid())
    on conflict (code) do update set group_kind = excluded.group_kind, rate_kind = excluded.rate_kind, label_bn = excluded.label_bn, label_en = excluded.label_en,
      amount = excluded.amount, active = excluded.active, updated_by = excluded.updated_by, updated_at = now();
  return jsonb_build_object('code', p_code, 'amount', p_amount, 'active', p_active);
end $$;

-- ---------- quote (no write) ----------
create or replace function public._xb541_quote(p_weight numeric, p_flavour text, p_designs text[]) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare base public.cake_price_rules; f public.cake_price_rules; d text; dr public.cake_price_rules; lines jsonb := '[]'; tot numeric := 0; amt numeric;
begin
  select * into base from public.cake_price_rules where group_kind = 'base' and active order by id limit 1;
  if not found then raise exception 'price_rules_missing: the owner has not set the cake base price'; end if;
  if p_weight is null or p_weight <= 0 or p_weight > 1000 then raise exception 'bad_weight'; end if;
  amt := round(p_weight * base.amount, 2);
  lines := lines || jsonb_build_object('code', base.code, 'group', 'base', 'label_en', base.label_en, 'label_bn', base.label_bn, 'rate', base.amount, 'basis', 'per_kg', 'qty', p_weight, 'amount', amt);
  tot := tot + amt;
  if nullif(btrim(coalesce(p_flavour, '')), '') is not null then
    select * into f from public.cake_price_rules where code = p_flavour and group_kind = 'flavour' and active;
    if not found then raise exception 'bad_flavour: no active flavour price with this code'; end if;
    amt := case when f.rate_kind = 'per_kg' then round(p_weight * f.amount, 2) else f.amount end;
    lines := lines || jsonb_build_object('code', f.code, 'group', 'flavour', 'label_en', f.label_en, 'label_bn', f.label_bn, 'rate', f.amount, 'basis', f.rate_kind, 'qty', case when f.rate_kind = 'per_kg' then p_weight else 1 end, 'amount', amt);
    tot := tot + amt;
  end if;
  foreach d in array coalesce(p_designs, '{}') loop
    select * into dr from public.cake_price_rules where code = d and group_kind = 'design' and active;
    if not found then raise exception 'bad_design: no active design extra with this code'; end if;
    amt := case when dr.rate_kind = 'per_kg' then round(p_weight * dr.amount, 2) else dr.amount end;
    lines := lines || jsonb_build_object('code', dr.code, 'group', 'design', 'label_en', dr.label_en, 'label_bn', dr.label_bn, 'rate', dr.amount, 'basis', dr.rate_kind, 'qty', case when dr.rate_kind = 'per_kg' then p_weight else 1 end, 'amount', amt);
    tot := tot + amt;
  end loop;
  return jsonb_build_object('lines', lines, 'total', round(tot, 2));
end $$;

create or replace function public.xb_cake_quote(p_weight numeric, p_flavour text default null, p_designs text[] default '{}') returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() or not public.can_do('POS', 'view') then raise exception 'not allowed'; end if;
  return public._xb541_quote(p_weight, p_flavour, p_designs);
end $$;

create or replace function public.xb_cake_price_rules_list() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.is_active() and (public.is_owner() or public.can_do('POS', 'view'))
    then coalesce((select jsonb_agg(to_jsonb(r) - 'updated_by' order by r.group_kind, r.code) from public.cake_price_rules r), '[]'::jsonb)
    else '[]'::jsonb end;
$$;

-- ---------- cake job ----------
create table if not exists public.cake_jobs (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  order_id uuid not null unique references public.online_orders(id),
  location_id int not null references public.locations(id),
  due_date date not null,
  due_slot_from time,
  weight_kg numeric not null check (weight_kg > 0 and weight_kg <= 1000),
  flavour_code text references public.cake_price_rules(code),
  layers int check (layers is null or layers between 1 and 10),
  message text check (message is null or char_length(message) <= 200),
  design_notes text check (design_notes is null or char_length(design_notes) <= 500),
  design_codes text[] not null default '{}',
  ref_photos text[] not null default '{}',
  eggless boolean not null default false,
  halal boolean not null default false,
  allergen_note text check (allergen_note is null or char_length(allergen_note) <= 200),
  quote_lines jsonb not null,
  quote_total numeric not null check (quote_total >= 0),
  advance_required numeric not null check (advance_required >= 0 and advance_required <= quote_total),
  balance numeric generated always as (quote_total - advance_required) stored,
  photo_ready_path text check (photo_ready_path is null or char_length(photo_ready_path) <= 200),
  state text not null default 'quoted' check (state in ('quoted', 'confirmed', 'slip', 'baked', 'decorated', 'ready', 'delivered', 'cancelled')),
  state_at timestamptz not null default now(),
  cancel_reason text check (cancel_reason is null or char_length(cancel_reason) <= 300),
  created_by uuid, created_staff text, created_at timestamptz not null default now()
);
create index if not exists cake_jobs_due on public.cake_jobs (location_id, due_date) where state <> 'cancelled';

create table if not exists public.cake_job_events (
  id bigint generated always as identity primary key,
  job_id uuid not null references public.cake_jobs(id),
  from_state text, to_state text not null, note text check (note is null or char_length(note) <= 300),
  by_user uuid, by_staff text, at timestamptz not null default now()
);
create index if not exists cake_job_events_job on public.cake_job_events (job_id, id);

-- trail and money-free fields: only state, photo and cancel fields move; nothing is deleted
create or replace function public._xb541_job_ro() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'nothing is deleted: a cake job is cancelled'; end if;
  if (to_jsonb(new) - 'state' - 'state_at' - 'photo_ready_path' - 'cancel_reason' - 'balance') is distinct from (to_jsonb(old) - 'state' - 'state_at' - 'photo_ready_path' - 'cancel_reason' - 'balance') then
    raise exception 'a cake job changes only its state, photo and cancel reason; the order and quote are fixed';
  end if;
  if old.state in ('delivered', 'cancelled') and new.state is distinct from old.state then raise exception 'closed: a delivered or cancelled cake job cannot change'; end if;
  return new;
end $$;
drop trigger if exists cake_jobs_ro on public.cake_jobs;
create trigger cake_jobs_ro before update or delete on public.cake_jobs for each row execute function public._xb541_job_ro();
drop trigger if exists audit_cake_jobs on public.cake_jobs;
create trigger audit_cake_jobs after insert or update on public.cake_jobs for each row execute function public.log_change('id');
drop trigger if exists cake_job_events_ro on public.cake_job_events;
create trigger cake_job_events_ro before update or delete on public.cake_job_events for each row execute function public._xb540_lines_ro();
drop trigger if exists audit_cake_job_events on public.cake_job_events;
create trigger audit_cake_job_events after insert on public.cake_job_events for each row execute function public.log_change('id');

create or replace function public._xb541_event(p_job uuid, p_from text, p_to text, p_note text) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.cake_job_events (job_id, from_state, to_state, note, by_user, by_staff)
    values (p_job, p_from, p_to, left(nullif(btrim(p_note), ''), 300), auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
end $$;

create or replace function public._xb541_gate(p_loc int) returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('cake_flow_on') then raise exception 'module_off'; end if;
  if not public.can_do('POS', 'enter') or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
end $$;

-- create the job and its quote for an open app order. Capacity and lead time are checked here; the order spec is written too.
create or replace function public.xb_cake_create(p_order uuid, p_client uuid, p_due date, p_slot time, p_weight numeric, p_flavour text, p_layers int, p_message text,
  p_design_codes text[], p_design_notes text, p_eggless boolean, p_halal boolean, p_allergen text, p_ref_photos text[], p_advance numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; q jsonb; cap numeric := public.rule_num('cake_capacity_day'); lead numeric := public.rule_num('cake_lead_days'); n int; jid uuid; rec public.cake_jobs;
        photos text[] := coalesce(p_ref_photos, '{}'); adv numeric := coalesce(p_advance, 0);
begin
  if p_client is not null then
    select * into rec from public.cake_jobs where client_id = p_client;
    if found then return jsonb_build_object('id', rec.id, 'state', rec.state, 'dup', true); end if;
  end if;
  select * into o from public.online_orders where id = p_order for update;
  if not found then raise exception 'not_found'; end if;
  perform public._xb541_gate(o.location_id);
  if o.status not in ('new', 'confirmed') then raise exception 'order_closed: a cake is quoted on a new or confirmed order'; end if;
  if exists (select 1 from public.cake_jobs where order_id = o.id) then raise exception 'already_has_cake_job'; end if;
  if p_due is null or p_due < (now() at time zone 'Asia/Dhaka')::date then raise exception 'bad_date'; end if;
  if lead is null then raise exception 'lead_time_not_set: the owner must set the cake lead time'; end if;
  if p_due < (now() at time zone 'Asia/Dhaka')::date + lead::int then raise exception 'lead_time: a cake needs % day(s) notice', lead::int; end if;
  if cap is null then raise exception 'capacity_not_set: the owner must set the cakes per day'; end if;
  select count(*) into n from public.cake_jobs where location_id = o.location_id and due_date = p_due and state <> 'cancelled';
  if n >= cap::int then raise exception 'capacity_full: % cakes already due on this day', n; end if;
  if o.delivery_date is not null and o.delivery_date <> p_due then raise exception 'due_date_differs_from_order'; end if;
  if p_message is not null and char_length(p_message) > 200 then raise exception 'too_long'; end if;
  q := public._xb541_quote(p_weight, p_flavour, p_design_codes);
  if (q->>'total')::numeric > o.subtotal - o.discount + o.delivery_charge then raise exception 'order_total_below_quote: the order lines must carry the cake at its quoted total'; end if;
  if adv < 0 or adv > (q->>'total')::numeric then raise exception 'bad_advance'; end if;
  if array_length(photos, 1) > 5 then raise exception 'too_many_photos'; end if;
  perform public.c2_order_spec_save(o.id, jsonb_build_array(jsonb_build_object('weight_kg', p_weight, 'flavour', p_flavour, 'message', p_message,
      'design', p_design_notes, 'photo_ref', photos[1])), 'cake job');
  insert into public.cake_jobs (client_id, order_id, location_id, due_date, due_slot_from, weight_kg, flavour_code, layers, message, design_notes, design_codes, ref_photos,
      eggless, halal, allergen_note, quote_lines, quote_total, advance_required, created_by, created_staff)
    values (p_client, o.id, o.location_id, p_due, p_slot, p_weight, nullif(p_flavour, ''), p_layers, nullif(btrim(p_message), ''), nullif(btrim(p_design_notes), ''),
      coalesce(p_design_codes, '{}'), photos, coalesce(p_eggless, false), coalesce(p_halal, false), nullif(btrim(p_allergen), ''), q->'lines', (q->>'total')::numeric, adv,
      auth.uid(), (select staff_id from public.profiles where id = auth.uid()))
    returning id into jid;
  perform public._xb541_event(jid, null, 'quoted', 'quote ' || (q->>'total') || ', advance ' || adv::text);
  return jsonb_build_object('id', jid, 'state', 'quoted', 'quote', q, 'advance_required', adv, 'balance', (q->>'total')::numeric - adv, 'due_count_after', n + 1);
end $$;

-- quote -> confirmed: needs the advance already in the order (the order advance field) at least the advance required
create or replace function public.xb_cake_confirm(p_job uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.cake_jobs; o public.online_orders;
begin
  select * into j from public.cake_jobs where id = p_job for update;
  if not found then raise exception 'not_found'; end if;
  perform public._xb541_gate(j.location_id);
  if j.state = 'confirmed' then return jsonb_build_object('id', j.id, 'state', 'confirmed', 'noop', true); end if;
  if j.state <> 'quoted' then raise exception 'bad_status: only a quoted cake can be confirmed (now %)', j.state; end if;
  select * into o from public.online_orders where id = j.order_id;
  if o.advance < j.advance_required then raise exception 'advance_required: the order must carry at least % before the cake is confirmed', j.advance_required; end if;
  update public.cake_jobs set state = 'confirmed', state_at = now() where id = j.id;
  perform public._xb541_event(j.id, 'quoted', 'confirmed', 'advance ' || o.advance::text);
  return jsonb_build_object('id', j.id, 'state', 'confirmed');
end $$;

-- the forward chain. delivered also needs the app order delivered and, when the switch is on, the finished-cake photo.
create or replace function public.xb_cake_move(p_job uuid, p_to text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.cake_jobs; o public.online_orders; nxt text;
begin
  select * into j from public.cake_jobs where id = p_job for update;
  if not found then raise exception 'not_found'; end if;
  perform public._xb541_gate(j.location_id);
  if p_to not in ('slip', 'baked', 'decorated', 'ready', 'delivered') then raise exception 'bad_status'; end if;
  if j.state = p_to then return jsonb_build_object('id', j.id, 'state', j.state, 'noop', true); end if;
  nxt := case j.state when 'confirmed' then 'slip' when 'slip' then 'baked' when 'baked' then 'decorated' when 'decorated' then 'ready' when 'ready' then 'delivered' else null end;
  if nxt is distinct from p_to then raise exception 'bad_status: % -> % is not allowed', j.state, p_to; end if;
  if p_to = 'delivered' then
    select * into o from public.online_orders where id = j.order_id;
    if o.status <> 'delivered' then raise exception 'order_not_delivered: deliver the app order first (its own money path)'; end if;
    if public.rule_on('cake_photo_required') and j.photo_ready_path is null then raise exception 'photo_required: a photo of the finished cake is needed first'; end if;
  end if;
  update public.cake_jobs set state = p_to, state_at = now() where id = j.id;
  perform public._xb541_event(j.id, j.state, p_to, p_note);
  return jsonb_build_object('id', j.id, 'state', p_to);
end $$;

create or replace function public.xb_cake_photo(p_job uuid, p_path text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.cake_jobs;
begin
  select * into j from public.cake_jobs where id = p_job for update;
  if not found then raise exception 'not_found'; end if;
  perform public._xb541_gate(j.location_id);
  if j.state not in ('decorated', 'ready') then raise exception 'bad_status: the photo is taken when the cake is decorated or ready'; end if;
  if p_path is null or p_path !~ ('^cake/' || j.location_id || '/[A-Za-z0-9_.-]{1,120}\.jpe?g$') then raise exception 'bad_path'; end if;
  update public.cake_jobs set photo_ready_path = p_path where id = j.id;
  perform public._xb541_event(j.id, j.state, j.state, 'photo of the finished cake');
  return jsonb_build_object('id', j.id, 'photo_ready_path', p_path);
end $$;

-- cancel before delivery: the refund and advance rules are the existing order cancel (phase 448)
create or replace function public.xb_cake_cancel(p_job uuid, p_reason text, p_advance_fate text default 'none', p_refund_mode text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.cake_jobs; r jsonb;
begin
  select * into j from public.cake_jobs where id = p_job for update;
  if not found then raise exception 'not_found'; end if;
  perform public._xb541_gate(j.location_id);
  if j.state = 'cancelled' then return jsonb_build_object('id', j.id, 'state', 'cancelled', 'noop', true); end if;
  if j.state = 'delivered' then raise exception 'order_closed: a delivered cake is not cancelled; use the sale return'; end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null then raise exception 'reason_required'; end if;
  r := public.c2_order_cancel(j.order_id, btrim(p_reason), p_advance_fate, p_refund_mode);
  update public.cake_jobs set state = 'cancelled', state_at = now(), cancel_reason = left(btrim(p_reason), 300) where id = j.id;
  perform public._xb541_event(j.id, j.state, 'cancelled', btrim(p_reason));
  return jsonb_build_object('id', j.id, 'state', 'cancelled', 'order', r);
end $$;

-- the production and decoration sheet for one day (cakes due on that day, not cancelled)
create or replace function public.xb_cake_due(p_date date, p_loc int default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.is_active() or not public.can_do('POS', 'view') then '{"rows":[]}'::jsonb else jsonb_build_object(
    'date', p_date,
    'count', (select count(*) from public.cake_jobs j where j.due_date = p_date and j.state <> 'cancelled' and (p_loc is null or j.location_id = p_loc) and public.can_loc(j.location_id)),
    'total_kg', (select coalesce(sum(j.weight_kg), 0) from public.cake_jobs j where j.due_date = p_date and j.state <> 'cancelled' and (p_loc is null or j.location_id = p_loc) and public.can_loc(j.location_id)),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('job_id', j.id, 'order_no', o.order_no, 'slot', j.due_slot_from, 'weight_kg', j.weight_kg, 'layers', j.layers,
        'flavour', j.flavour_code, 'message', j.message, 'design', j.design_notes, 'design_codes', j.design_codes, 'eggless', j.eggless, 'halal', j.halal,
        'allergen', j.allergen_note, 'state', j.state, 'delivery_mode', o.delivery_mode, 'customer', o.customer_name, 'balance', j.balance, 'ref_photos', j.ref_photos)
        order by j.due_slot_from nulls last, j.id)
      from public.cake_jobs j join public.online_orders o on o.id = j.order_id
      where j.due_date = p_date and j.state <> 'cancelled' and (p_loc is null or j.location_id = p_loc) and public.can_loc(j.location_id)), '[]'::jsonb)) end;
$$;

-- customer confirmation: a wa.me text for the owner's tap, and an SMS queued only when SMS is on, the customer opted in and is not do-not-contact
create or replace function public.xb_cake_notify(p_job uuid, p_template text default 'cake_confirmed') returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.cake_jobs; o public.online_orders; cu uuid; mob text; txt text; q jsonb; dnc boolean := false; enq jsonb := null;
begin
  select * into j from public.cake_jobs where id = p_job;
  if not found then raise exception 'not_found'; end if;
  perform public._xb541_gate(j.location_id);
  if p_template not in ('cake_confirmed', 'cake_ready') then raise exception 'bad_template'; end if;
  select * into o from public.online_orders where id = j.order_id;
  mob := public.norm_mobile(o.customer_mobile);
  txt := case when p_template = 'cake_ready' then 'Your cake (order #' || o.order_no || ') is ready for ' || j.due_date::text || '.'
              else 'Your cake order #' || o.order_no || ' is confirmed for ' || j.due_date::text || '. Advance ' || j.advance_required::text || ', balance ' || j.balance::text || ' taka.' end;
  select c.id into cu from public.customers c where c.mobile = mob;
  if cu is not null then select coalesce(p.dnc, false) into dnc from public.crm_contact_prefs p where p.customer_id = cu; end if;
  if cu is not null and not dnc and public.rule_on('notify_sms_on') then
    enq := public.notify_enqueue(gen_random_uuid(), cu, 'sms', p_template, jsonb_build_object('ref', '#' || o.order_no, 'date', j.due_date::text), 'en', 'cake_job', j.id::text);
  end if;
  return jsonb_build_object('id', j.id, 'wa_phone', case when mob like '01%' then '880' || substr(mob, 2) end, 'wa_text', txt,
    'sms', coalesce(to_jsonb(case when cu is null then 'no_customer_record' when dnc then 'do_not_contact' when not public.rule_on('notify_sms_on') then 'sms_off' end), enq));
end $$;

create or replace function public.xb_cake_job_get(p_order uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.is_active() or not public.can_do('POS', 'view') then null else (
    select to_jsonb(j) - 'client_id' || jsonb_build_object('events', coalesce((select jsonb_agg(jsonb_build_object('from', e.from_state, 'to', e.to_state, 'note', e.note, 'by', e.by_staff, 'at', e.at) order by e.id)
        from public.cake_job_events e where e.job_id = j.id), '[]'::jsonb))
    from public.cake_jobs j where j.order_id = p_order and public.can_loc(j.location_id) ) end;
$$;

-- ---------- privileges and RLS ----------
alter table public.cake_price_rules enable row level security;
alter table public.cake_jobs enable row level security;
alter table public.cake_job_events enable row level security;
revoke all on public.cake_price_rules, public.cake_jobs, public.cake_job_events from public, anon, authenticated;
grant select on public.cake_price_rules, public.cake_jobs, public.cake_job_events to authenticated;
drop policy if exists cake_price_rules_sel on public.cake_price_rules;
create policy cake_price_rules_sel on public.cake_price_rules for select to authenticated using (public.is_active() and (public.is_owner() or public.can_do('POS', 'view')));
drop policy if exists cake_jobs_sel on public.cake_jobs;
create policy cake_jobs_sel on public.cake_jobs for select to authenticated using (public.is_active() and (public.is_owner() or public.can_do('POS', 'view')) and public.can_loc(location_id));
drop policy if exists cake_job_events_sel on public.cake_job_events;
create policy cake_job_events_sel on public.cake_job_events for select to authenticated
  using (public.is_active() and exists (select 1 from public.cake_jobs j where j.id = job_id and public.can_loc(j.location_id)));

insert into public.notify_templates (code, channel, body_bn, body_en) values
 ('cake_confirmed', 'sms', 'আপনার কেক অর্ডার {ref} নিশ্চিত হয়েছে, তারিখ {date}। - {shop}', 'Your cake order {ref} is confirmed for {date}. - {shop}'),
 ('cake_ready', 'sms', 'আপনার কেক {ref} প্রস্তুত, তারিখ {date}। - {shop}', 'Your cake {ref} is ready for {date}. - {shop}')
on conflict (code) do nothing;

do $x$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and (p.proname like 'xb\_cake\_%' or p.proname like '\_xb541\_%') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname like 'xb\_cake\_%' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $x$;
notify pgrst, 'reload schema';

-- ===================== phase493.sql =====================
-- ============================================================
-- Phase 493 - XB package part 3: riders, delivery status, delivery zones, COD collected and deposited per rider per day.
-- Run AFTER phase 492. New file only; no old phase or function is edited. Paste twice = no error, no second row.
--
--   * riders                 staff or external rider master (name_bn / name_en, kind, optional employee link, phone, place, active). Owner or grant rider_manage.
--   * delivery_zones        zone fee table (owner or rider_manage). A zone with no fee cannot be assigned (nothing invented).
--   * delivery_jobs         one per app order: rider, zone, fee, attempts, live-location link (a https maps link the rider shares; no tracking is built),
--                           COD amount (= the order balance at handover). States: assigned -> out -> delivered | failed;
--                           failed -> assigned (reattempt, attempts + 1) or failed -> returned (back to the shop). Every move in delivery_events.
--   * cod_deposits          money a rider hands in (append-only, client id).
--   * xb_cod_reconcile      per rider per day: COD collected on delivered jobs, deposited, difference (short / over). Information only.
--   * cod_cases             one open case per rider per day with a difference; the owner explains it. NOTHING is posted to cash or the books:
--                           linking a short to the existing shortage cases needs an entry row and is an owner decision (not built).
--   * xb_rider_perf         deliveries, failed, returned, average minutes from handover to delivered, per rider for a date range.
--   * Rules: xb_delivery_on (OFF). When OFF every writer here is refused. Nothing is sent to riders or customers by this phase.
-- ============================================================
do $guard$ begin
  if to_regclass('public.online_orders') is null or to_regclass('public.employees') is null or to_regprocedure('public.xb_cake_create(uuid,uuid,date,time,numeric,text,int,text,text[],text,boolean,boolean,text,text[],numeric)') is null then
    raise exception 'phase493 needs phase492 (and phase61 / phase41 employees) pasted first';
  end if;
end $guard$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('xb_delivery_on', 'pos', 'switch', 'false', null, null, null, null, 'রাইডার ও ডেলিভারি ট্র্যাকিং চালু', 'Rider & delivery tracking চালু', 'Rider and delivery tracking is on',
  'চালু হলে রাইডার, ডেলিভারির অবস্থা, COD জমা ও হিসাব লেখা যাবে। কিছু পাঠানো হয় না।', 'When on, riders, delivery status and COD deposits can be recorded. Nothing is sent by this.', 546)
on conflict (key) do nothing;
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('rider_manage', 'pos', 92, 'রাইডার ও জোন ঠিক করা', 'Rider ও zone ঠিক করা', 'Manage riders and delivery zones', 'once', null)
on conflict (grant_code) do nothing;

create or replace function public._xb542_gate(p_loc int) returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('xb_delivery_on') then raise exception 'module_off'; end if;
  if not public.can_do('POS', 'enter') or (p_loc is not null and not public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
end $$;
create or replace function public._xb542_manage() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'rider_manage' and g.location_id is null));
$$;
create or replace function public._xb542_ro() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: this trail or deposit is never changed or deleted'; end $$;

-- ---------- riders and zones ----------
create table if not exists public.riders (
  id bigint generated always as identity primary key,
  name_bn text not null check (char_length(btrim(name_bn)) between 1 and 80),
  name_en text check (name_en is null or char_length(name_en) <= 80),
  kind text not null check (kind in ('staff', 'external')),
  employee_id uuid references public.employees(id),
  phone text check (phone is null or char_length(phone) between 6 and 20),
  location_id int references public.locations(id),
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now(),
  check ((kind = 'staff') = (employee_id is not null) or kind = 'external')
);
create table if not exists public.delivery_zones (
  code text primary key check (code ~ '^[a-z0-9_]{2,30}$'),
  name_bn text not null check (char_length(btrim(name_bn)) between 1 and 80),
  name_en text not null check (char_length(btrim(name_en)) between 1 and 80),
  fee numeric not null check (fee >= 0 and fee <= 1000000),
  active boolean not null default true,
  updated_by uuid, updated_at timestamptz not null default now()
);
drop trigger if exists riders_nodel on public.riders;
create trigger riders_nodel before delete on public.riders for each row execute function public._xb542_ro();
drop trigger if exists delivery_zones_nodel on public.delivery_zones;
create trigger delivery_zones_nodel before delete on public.delivery_zones for each row execute function public._xb542_ro();
drop trigger if exists audit_riders on public.riders;
create trigger audit_riders after insert or update on public.riders for each row execute function public.log_change('id');
drop trigger if exists audit_delivery_zones on public.delivery_zones;
create trigger audit_delivery_zones after insert or update on public.delivery_zones for each row execute function public.log_change('code');

create or replace function public.xb_rider_save(p_id bigint, p_name_bn text, p_name_en text, p_kind text, p_employee uuid, p_phone text, p_loc int, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare id_ bigint;
begin
  if not public._xb542_manage() then raise exception 'not allowed'; end if;
  if nullif(btrim(coalesce(p_name_bn, '')), '') is null or p_kind not in ('staff', 'external') or p_active is null then raise exception 'bad_input'; end if;
  if p_kind = 'staff' and (p_employee is null or not exists (select 1 from public.employees e where e.id = p_employee)) then raise exception 'employee_required'; end if;
  if p_kind = 'external' then p_employee := null; end if;
  if p_id is null then
    insert into public.riders (name_bn, name_en, kind, employee_id, phone, location_id, active, created_by)
      values (left(btrim(p_name_bn), 80), left(nullif(btrim(p_name_en), ''), 80), p_kind, p_employee, nullif(btrim(p_phone), ''), p_loc, p_active, auth.uid()) returning id into id_;
  else
    update public.riders set name_bn = left(btrim(p_name_bn), 80), name_en = left(nullif(btrim(p_name_en), ''), 80), kind = p_kind, employee_id = p_employee,
      phone = nullif(btrim(p_phone), ''), location_id = p_loc, active = p_active where id = p_id returning id into id_;
    if id_ is null then raise exception 'not_found'; end if;
  end if;
  return jsonb_build_object('id', id_);
end $$;

create or replace function public.xb_delivery_zone_save(p_code text, p_name_bn text, p_name_en text, p_fee numeric, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._xb542_manage() then raise exception 'not allowed'; end if;
  if p_code !~ '^[a-z0-9_]{2,30}$' or p_fee is null or p_fee < 0 or p_fee > 1000000 or p_active is null then raise exception 'bad_input'; end if;
  insert into public.delivery_zones (code, name_bn, name_en, fee, active, updated_by) values (p_code, left(btrim(p_name_bn), 80), left(btrim(p_name_en), 80), p_fee, p_active, auth.uid())
    on conflict (code) do update set name_bn = excluded.name_bn, name_en = excluded.name_en, fee = excluded.fee, active = excluded.active, updated_by = excluded.updated_by, updated_at = now();
  return jsonb_build_object('code', p_code, 'fee', p_fee);
end $$;

-- ---------- delivery jobs ----------
create table if not exists public.delivery_jobs (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.online_orders(id),
  location_id int not null references public.locations(id),
  rider_id bigint references public.riders(id),
  zone_code text references public.delivery_zones(code),
  fee numeric check (fee is null or fee >= 0),
  attempts int not null default 0 check (attempts >= 0 and attempts <= 10),
  map_link text check (map_link is null or (map_link ~ '^https://' and char_length(map_link) <= 300)),
  cod_amount numeric check (cod_amount is null or cod_amount >= 0),
  state text not null default 'unassigned' check (state in ('unassigned', 'assigned', 'out', 'delivered', 'failed', 'returned')),
  handed_at timestamptz, delivered_at timestamptz, failed_reason text check (failed_reason is null or char_length(failed_reason) <= 300),
  cod_collected numeric check (cod_collected is null or cod_collected >= 0),
  created_by uuid, created_at timestamptz not null default now(), state_at timestamptz not null default now()
);
create table if not exists public.delivery_events (
  id bigint generated always as identity primary key,
  job_id uuid not null references public.delivery_jobs(id),
  from_state text, to_state text not null, note text check (note is null or char_length(note) <= 300),
  by_user uuid, by_staff text, at timestamptz not null default now()
);
create table if not exists public.cod_deposits (
  id bigint generated always as identity primary key,
  client_id uuid unique,
  rider_id bigint not null references public.riders(id),
  location_id int not null references public.locations(id),
  deposit_day date not null,
  amount numeric not null check (amount > 0 and amount <= 1000000000),
  note text check (note is null or char_length(note) <= 300),
  deposited_by uuid, deposited_staff text, deposited_at timestamptz not null default now()
);
create table if not exists public.cod_cases (
  id bigint generated always as identity primary key,
  rider_id bigint not null references public.riders(id),
  location_id int not null references public.locations(id),
  case_day date not null,
  collected numeric not null, deposited numeric not null, difference numeric not null check (difference <> 0),
  state text not null default 'open' check (state in ('open', 'explained')),
  explain_note text check (explain_note is null or char_length(explain_note) <= 300),
  explained_by uuid, explained_at timestamptz,
  opened_at timestamptz not null default now(),
  unique (rider_id, case_day)
);
drop trigger if exists delivery_events_ro on public.delivery_events;
create trigger delivery_events_ro before update or delete on public.delivery_events for each row execute function public._xb542_ro();
drop trigger if exists cod_deposits_ro on public.cod_deposits;
create trigger cod_deposits_ro before update or delete on public.cod_deposits for each row execute function public._xb542_ro();
drop trigger if exists audit_delivery_jobs on public.delivery_jobs;
create trigger audit_delivery_jobs after insert or update on public.delivery_jobs for each row execute function public.log_change('id');
drop trigger if exists audit_cod_deposits on public.cod_deposits;
create trigger audit_cod_deposits after insert on public.cod_deposits for each row execute function public.log_change('id');

-- delivery_jobs: state, attempts, link, cod and the rider move; the order and zone fee are fixed once a job exists
create or replace function public._xb542_job_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'nothing is deleted: a delivery is returned or closed'; end if;
  if old.state in ('delivered', 'returned') and new.state is distinct from old.state then raise exception 'closed: a delivered or returned job cannot change'; end if;
  if (to_jsonb(new) - 'state' - 'state_at' - 'attempts' - 'rider_id' - 'handed_at' - 'delivered_at' - 'failed_reason' - 'map_link' - 'cod_collected' - 'updated_at')
     is distinct from (to_jsonb(old) - 'state' - 'state_at' - 'attempts' - 'rider_id' - 'handed_at' - 'delivered_at' - 'failed_reason' - 'map_link' - 'cod_collected' - 'updated_at') then
    raise exception 'the order, zone and fee of a delivery are fixed';
  end if;
  return new;
end $$;
drop trigger if exists delivery_jobs_guard on public.delivery_jobs;
create trigger delivery_jobs_guard before update or delete on public.delivery_jobs for each row execute function public._xb542_job_guard();

-- assign a rider and a zone (fee from the zone table; a zone with no fee is refused by the table itself)
create or replace function public.xb_delivery_assign(p_order uuid, p_rider bigint, p_zone text, p_map_link text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; z public.delivery_zones; r public.riders; j public.delivery_jobs; bal numeric;
begin
  select * into o from public.online_orders where id = p_order;
  if not found then raise exception 'not_found'; end if;
  perform public._xb542_gate(o.location_id);
  if o.status in ('delivered', 'cancelled') then raise exception 'order_closed'; end if;
  select * into r from public.riders where id = p_rider and active;
  if not found then raise exception 'rider_not_found_or_inactive'; end if;
  if r.location_id is not null and r.location_id <> o.location_id then raise exception 'rider_other_location'; end if;
  select * into z from public.delivery_zones where code = p_zone and active;
  if not found then raise exception 'zone_not_found_or_inactive'; end if;
  bal := o.subtotal - o.discount + o.delivery_charge - o.advance;
  select * into j from public.delivery_jobs where order_id = o.id for update;
  if not found then
    insert into public.delivery_jobs (order_id, location_id, rider_id, zone_code, fee, map_link, cod_amount, state, created_by)
      values (o.id, o.location_id, r.id, z.code, z.fee, nullif(btrim(p_map_link), ''), greatest(bal, 0), 'assigned', auth.uid()) returning * into j;
    insert into public.delivery_events (job_id, from_state, to_state, note, by_user, by_staff) values (j.id, 'unassigned', 'assigned', 'rider ' || r.name_en, auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
  else
    if j.state not in ('unassigned', 'assigned') then raise exception 'bad_status: a job on the road cannot change rider'; end if;
    update public.delivery_jobs set rider_id = r.id, state = 'assigned', state_at = now(), map_link = coalesce(nullif(btrim(p_map_link), ''), map_link) where id = j.id returning * into j;
  end if;
  return jsonb_build_object('id', j.id, 'state', j.state, 'rider_id', r.id, 'zone', z.code, 'fee', z.fee, 'cod_amount', j.cod_amount);
end $$;

-- out (handed to rider), delivered (COD collected stated), failed (reason), reattempt (failed -> assigned), returned (failed -> back to shop)
create or replace function public.xb_delivery_move(p_job uuid, p_to text, p_cod numeric default null, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.delivery_jobs; from_s text; n int;
begin
  select * into j from public.delivery_jobs where id = p_job for update;
  if not found then raise exception 'not_found'; end if;
  perform public._xb542_gate(j.location_id);
  from_s := j.state;
  if p_to not in ('out', 'delivered', 'failed', 'reattempt', 'returned') then raise exception 'bad_status'; end if;
  if p_to = 'out' and from_s = 'assigned' then
    update public.delivery_jobs set state = 'out', handed_at = now(), state_at = now() where id = j.id;
  elsif p_to = 'delivered' and from_s = 'out' then
    if p_cod is not null and (p_cod < 0 or p_cod > 1000000000) then raise exception 'bad_amount'; end if;
    update public.delivery_jobs set state = 'delivered', delivered_at = now(), state_at = now(), cod_collected = coalesce(p_cod, cod_amount) where id = j.id;
  elsif p_to = 'failed' and from_s = 'out' then
    if nullif(btrim(coalesce(p_reason, '')), '') is null then raise exception 'reason_required'; end if;
    update public.delivery_jobs set state = 'failed', failed_reason = left(btrim(p_reason), 300), state_at = now(), attempts = attempts + 1 where id = j.id;
  elsif p_to = 'reattempt' and from_s = 'failed' then
    if j.attempts >= 3 then raise exception 'too_many_attempts: return the goods to the shop'; end if;
    update public.delivery_jobs set state = 'assigned', state_at = now(), handed_at = null where id = j.id;
    p_to := 'assigned';
  elsif p_to = 'returned' and from_s = 'failed' then
    update public.delivery_jobs set state = 'returned', state_at = now() where id = j.id;
  else
    raise exception 'bad_status: % -> % is not allowed', from_s, p_to;
  end if;
  insert into public.delivery_events (job_id, from_state, to_state, note, by_user, by_staff)
    values (j.id, from_s, p_to, left(nullif(btrim(coalesce(p_reason, '')), ''), 300), auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
  return jsonb_build_object('id', j.id, 'state', p_to, 'attempts', (select attempts from public.delivery_jobs where id = j.id));
end $$;

-- COD deposit: what a rider hands in on a day (no cash move is posted here)
create or replace function public.xb_cod_deposit(p_client uuid, p_rider bigint, p_loc int, p_day date, p_amount numeric, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare id_ bigint;
begin
  if p_client is not null and exists (select 1 from public.cod_deposits where client_id = p_client) then
    return jsonb_build_object('dup', true, 'id', (select id from public.cod_deposits where client_id = p_client));
  end if;
  perform public._xb542_gate(p_loc);
  if p_amount is null or p_amount <= 0 or p_amount > 1000000000 then raise exception 'bad_amount'; end if;
  if p_day is null or p_day > (now() at time zone 'Asia/Dhaka')::date then raise exception 'bad_date'; end if;
  if not exists (select 1 from public.riders where id = p_rider and active) then raise exception 'rider_not_found_or_inactive'; end if;
  insert into public.cod_deposits (client_id, rider_id, location_id, deposit_day, amount, note, deposited_by, deposited_staff)
    values (p_client, p_rider, p_loc, p_day, round(p_amount, 2), left(nullif(btrim(p_note), ''), 300), auth.uid(), (select staff_id from public.profiles where id = auth.uid()))
    returning id into id_;
  return jsonb_build_object('id', id_, 'dup', false);
end $$;

-- per rider per day: collected (delivered jobs of that day) versus deposited. A difference opens one case (owner explains it).
create or replace function public.xb_cod_reconcile(p_day date, p_loc int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rr record; col numeric; dep numeric; rows_ jsonb := '[]';
begin
  if not public.is_active() or not (public.is_owner() or public.can_do('POS', 'view')) then raise exception 'not allowed'; end if;
  for rr in select r.id, r.name_en, r.name_bn from public.riders r where r.active and (p_loc is null or r.location_id is null or r.location_id = p_loc) order by r.id loop
    select coalesce(sum(j.cod_collected), 0) into col from public.delivery_jobs j
     where j.rider_id = rr.id and j.state = 'delivered' and (j.delivered_at at time zone 'Asia/Dhaka')::date = p_day and (p_loc is null or j.location_id = p_loc) and public.can_loc(j.location_id);
    select coalesce(sum(d.amount), 0) into dep from public.cod_deposits d where d.rider_id = rr.id and d.deposit_day = p_day and (p_loc is null or d.location_id = p_loc) and public.can_loc(d.location_id);
    rows_ := rows_ || jsonb_build_object('rider_id', rr.id, 'rider', coalesce(rr.name_en, rr.name_bn), 'collected', col, 'deposited', dep, 'difference', col - dep,
      'status', case when col - dep = 0 then 'matched' when col - dep > 0 then 'short' else 'over' end);
    if col - dep <> 0 and (p_loc is not null) then
      insert into public.cod_cases (rider_id, location_id, case_day, collected, deposited, difference)
        values (rr.id, p_loc, p_day, col, dep, col - dep) on conflict (rider_id, case_day) do nothing;
    end if;
  end loop;
  return jsonb_build_object('day', p_day, 'riders', rows_, 'notes', jsonb_build_array('information_only_no_cash_is_posted', 'a_difference_opens_a_case_for_the_owner_to_explain'));
end $$;

create or replace function public.xb_cod_case_explain(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.cod_cases;
begin
  if not public._xb542_manage() and not public.is_owner() then raise exception 'not allowed'; end if;
  select * into c from public.cod_cases where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if c.state <> 'open' then raise exception 'already_explained'; end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.cod_cases set state = 'explained', explain_note = left(btrim(p_note), 300), explained_by = auth.uid(), explained_at = now() where id = c.id;
  return jsonb_build_object('id', c.id, 'state', 'explained');
end $$;

-- performance per rider over a date range (handover date)
create or replace function public.xb_rider_perf(p_from date, p_to date, p_loc int default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.is_active() or not (public.is_owner() or public.can_do('POS', 'view')) then '[]'::jsonb else coalesce((
    select jsonb_agg(z.row_json order by z.rid) from (
      select r.id as rid, jsonb_build_object('rider_id', r.id, 'rider', coalesce(r.name_en, r.name_bn),
        'jobs', count(j.id), 'delivered', count(j.id) filter (where j.state = 'delivered'), 'failed', count(j.id) filter (where j.state in ('failed', 'returned')),
        'returned', count(j.id) filter (where j.state = 'returned'), 'open', count(j.id) filter (where j.state in ('unassigned', 'assigned', 'out')),
        'avg_minutes_to_deliver', round(avg(extract(epoch from (j.delivered_at - j.handed_at)) / 60) filter (where j.state = 'delivered' and j.handed_at is not null), 1)) as row_json
      from public.riders r left join public.delivery_jobs j on j.rider_id = r.id and (j.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to
        and (p_loc is null or j.location_id = p_loc) and public.can_loc(j.location_id)
      where r.active group by r.id) z), '[]'::jsonb) end;
$$;

-- ---------- privileges and RLS ----------
alter table public.riders enable row level security;
alter table public.delivery_zones enable row level security;
alter table public.delivery_jobs enable row level security;
alter table public.delivery_events enable row level security;
alter table public.cod_deposits enable row level security;
alter table public.cod_cases enable row level security;
revoke all on public.riders, public.delivery_zones, public.delivery_jobs, public.delivery_events, public.cod_deposits, public.cod_cases from public, anon, authenticated;
grant select on public.riders, public.delivery_zones, public.delivery_jobs, public.delivery_events, public.cod_deposits, public.cod_cases to authenticated;
drop policy if exists riders_sel on public.riders;
create policy riders_sel on public.riders for select to authenticated using (public.is_active() and (public.is_owner() or public.can_do('POS', 'view')));
drop policy if exists delivery_zones_sel on public.delivery_zones;
create policy delivery_zones_sel on public.delivery_zones for select to authenticated using (public.is_active() and (public.is_owner() or public.can_do('POS', 'view')));
drop policy if exists delivery_jobs_sel on public.delivery_jobs;
create policy delivery_jobs_sel on public.delivery_jobs for select to authenticated using (public.is_active() and (public.is_owner() or public.can_do('POS', 'view')) and public.can_loc(location_id));
drop policy if exists delivery_events_sel on public.delivery_events;
create policy delivery_events_sel on public.delivery_events for select to authenticated
  using (public.is_active() and exists (select 1 from public.delivery_jobs j where j.id = job_id and public.can_loc(j.location_id)));
drop policy if exists cod_deposits_sel on public.cod_deposits;
create policy cod_deposits_sel on public.cod_deposits for select to authenticated using (public.is_active() and (public.is_owner() or public.can_do('POS', 'view')) and public.can_loc(location_id));
drop policy if exists cod_cases_sel on public.cod_cases;
create policy cod_cases_sel on public.cod_cases for select to authenticated using (public.is_active() and (public.is_owner() or public.can_do('POS', 'view')) and public.can_loc(location_id));

do $x$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and (p.proname like 'xb\_rider\_%' or p.proname like 'xb\_delivery\_%' or p.proname like 'xb\_cod\_%' or p.proname like 'xb\_rider\_perf%'
                  or p.proname like '\_xb542\_%') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname not like '\_xb542\_%' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $x$;
notify pgrst, 'reload schema';

-- ===================== phase494.sql =====================
-- Phase 494 (XC-1) - OWNER DAILY SUMMARY, RECIPIENTS, SEND LOG, RECEIPT CONTINUITY AND SYNC REPORT.
-- Paste AFTER phase478 (end of the owner paste order). Paste-twice safe. Earlier phase files are not edited.
-- Everything new is OFF by default: switches xc_summary_on, xc_summary_email_on, xc_summary_telegram_on, xc_sync_alert_on (all false).
-- Nothing is sent from here. tools/owner_summary.py (GitHub Actions or a laptop, dry-run by default) reads xc_summary_targets(), composes with xc_summary_compose(),
-- sends by e-mail (Gmail SMTP, existing pattern) or Telegram (bot token = secret, chat id = recipient address), then writes xc_summary_record(). A send that is already logged
-- as sent for the same day and recipient is never repeated (partial unique index).
-- Blank thresholds stay blank: xc_sync_stale_hours has no default; with it blank the sync alert says "threshold not set" and sends nothing.
-- Access: owner, or the ops bot (ops purpose 'notify'). Recipient addresses are readable only by the owner and the ops bot.

do $g$ begin
  if to_regprocedure('public.daily_digest(date)') is null then raise exception 'phase494 needs phase46 (daily_digest)'; end if;
  if to_regprocedure('public._notif_add(text,text,text,text,text,text,text,text,text,integer)') is null then raise exception 'phase494 needs the notifications helper'; end if;
  if to_regprocedure('public._rb4_prod_view(integer)') is null then raise exception 'phase494 needs phase404'; end if;
end $g$;

-- ---------- settings (all OFF / blank) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'xc', v.kind, v.dv, v.unit, null, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('xc_summary_on', 'switch', 'false'::jsonb, null::text, null::numeric, null::numeric,
   'দৈনিক সারাংশ চালু / Owner daily summary: on', 'Sends the owner daily summary by the channels switched on below. OFF = nothing is sent.', 9500),
 ('xc_summary_email_on', 'switch', 'false'::jsonb, null::text, null::numeric, null::numeric,
   'ই-মেইলে সারাংশ / Daily summary by e-mail', 'Recipients with channel e-mail get the summary. Needs the Gmail secrets (docs/OPS_SETUP.md).', 9501),
 ('xc_summary_telegram_on', 'switch', 'false'::jsonb, null::text, null::numeric, null::numeric,
   'টেলিগ্রামে সারাংশ / Daily summary by Telegram', 'Recipients with channel telegram get the summary. The bot token is a GitHub secret; the chat id is on the recipient row.', 9502),
 ('xc_summary_times', 'text', '"21"'::jsonb, null::text, null::numeric, null::numeric,
   'সারাংশের সময় (ঢাকা, যেমন 08,21) / Summary hours (Dhaka, e.g. 08,21)', 'The scheduled hours the summary is due at. The script decides by the hour.', 9503),
 ('xc_sync_alert_on', 'switch', 'false'::jsonb, null::text, null::numeric, null::numeric,
   'সব দোকান সিঙ্ক? সতর্কতা / Every shop synced? alert', 'Adds an in-app warning for each outlet whose last recorded sale is older than the hours below.', 9504),
 ('xc_sync_stale_hours', 'number', null::jsonb, 'hours', 1::numeric, 720::numeric,
   'কত ঘণ্টা বিক্রি না এলে সতর্কতা (ফাঁকা = সেট নেই) / Hours without a sale before the alert (blank = not set)', 'Blank = the alert says "threshold not set" and does nothing. Nothing is assumed.', 9505)
  ) as v(key, kind, dv, unit, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

-- ---------- recipients (owner-entered; addresses are personal, owner and ops bot only) ----------
create table if not exists public.xc_summary_recipients (
  id bigint generated by default as identity primary key,
  name text not null check (length(btrim(name)) between 1 and 80),
  channel text not null check (channel in ('email', 'telegram')),
  address text not null check (length(btrim(address)) between 3 and 200),        -- e-mail address, or Telegram chat id (a number). Not a secret.
  scope text not null default 'owner' check (scope in ('owner', 'outlet')),
  location_id int references public.locations(id),
  quiet_when_empty boolean not null default false,
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz,
  check ((scope = 'outlet') = (location_id is not null)),
  check (channel <> 'telegram' or address ~ '^-?[0-9]{5,20}$')
);
alter table public.xc_summary_recipients enable row level security;
revoke all on public.xc_summary_recipients from public, anon, authenticated;
grant select on public.xc_summary_recipients to authenticated;
drop policy if exists xc_summary_recipients_owner on public.xc_summary_recipients;
create policy xc_summary_recipients_owner on public.xc_summary_recipients for select to authenticated using (public.is_owner());
drop trigger if exists audit_xc_summary_recipients on public.xc_summary_recipients;
create trigger audit_xc_summary_recipients after insert or update on public.xc_summary_recipients for each row execute function public.log_change('id');
drop trigger if exists xc_summary_recipients_nodel on public.xc_summary_recipients;
create trigger xc_summary_recipients_nodel before delete on public.xc_summary_recipients for each row execute function public.no_hard_delete();

-- ---------- send log (append-only; one successful send per day, recipient and channel) ----------
create table if not exists public.xc_summary_log (
  id bigint generated by default as identity primary key,
  run_date date not null,
  recipient_id bigint references public.xc_summary_recipients(id),
  channel text not null check (channel in ('email', 'telegram')),
  scope text not null check (scope in ('owner', 'outlet')),
  location_id int references public.locations(id),
  status text not null check (status in ('sent', 'failed', 'skipped_empty')),
  content_hash text check (content_hash is null or length(content_hash) <= 80),
  error text check (error is null or length(error) <= 300),
  created_at timestamptz not null default now()
);
create unique index if not exists xc_summary_log_sent_once on public.xc_summary_log (run_date, recipient_id, channel) where status = 'sent';
create index if not exists xc_summary_log_day on public.xc_summary_log (run_date desc);
alter table public.xc_summary_log enable row level security;
revoke all on public.xc_summary_log from public, anon, authenticated;
grant select on public.xc_summary_log to authenticated;
drop policy if exists xc_summary_log_owner on public.xc_summary_log;
create policy xc_summary_log_owner on public.xc_summary_log for select to authenticated using (public.is_owner());
drop trigger if exists xc_summary_log_nodel on public.xc_summary_log;
create trigger xc_summary_log_nodel before delete or update on public.xc_summary_log for each row execute function public.no_hard_delete();

-- who may read the summary: the owner, or the ops bot for notify
create or replace function public._xc_summary_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public._is_ops('notify'));
$$;

-- ---------- recipients: save (owner only; no delete, retire with active = false) ----------
create or replace function public.xc_recipient_save(p_id bigint, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.xc_summary_recipients; nm text; ch text; ad text; sc text; lc int; qe boolean; ac boolean; id_ bigint;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_value'; end if;
  if p_id is not null then select * into o from public.xc_summary_recipients where id = p_id; if not found then raise exception 'not_found'; end if; end if;
  nm := coalesce(nullif(btrim(p ->> 'name'), ''), o.name);
  ch := coalesce(nullif(btrim(p ->> 'channel'), ''), o.channel);
  ad := coalesce(nullif(btrim(p ->> 'address'), ''), o.address);
  sc := coalesce(nullif(btrim(p ->> 'scope'), ''), o.scope, 'owner');
  lc := case when p ? 'location_id' then nullif(p ->> 'location_id', '')::int else o.location_id end;
  qe := case when p ? 'quiet_when_empty' then coalesce((p ->> 'quiet_when_empty')::boolean, false) else coalesce(o.quiet_when_empty, false) end;
  ac := case when p ? 'active' then coalesce((p ->> 'active')::boolean, true) else coalesce(o.active, true) end;
  if nm is null then raise exception 'name_required'; end if;
  if ch not in ('email', 'telegram') then raise exception 'bad_channel'; end if;
  if sc not in ('owner', 'outlet') then raise exception 'bad_scope'; end if;
  if sc = 'outlet' and lc is null then raise exception 'location_required'; end if;
  if sc = 'owner' then lc := null; end if;
  if lc is not null and not exists (select 1 from public.locations where id = lc) then raise exception 'bad_location'; end if;
  if ch = 'email' and ad !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'bad_address'; end if;
  if ch = 'telegram' and ad !~ '^-?[0-9]{5,20}$' then raise exception 'bad_address'; end if;
  if p_id is null then
    insert into public.xc_summary_recipients (name, channel, address, scope, location_id, quiet_when_empty, active, created_by)
      values (left(nm, 80), ch, ad, sc, lc, qe, ac, auth.uid()) returning id into id_;
  else
    update public.xc_summary_recipients set name = left(nm, 80), channel = ch, address = ad, scope = sc, location_id = lc,
      quiet_when_empty = qe, active = ac, updated_by = auth.uid(), updated_at = now() where id = p_id returning id into id_;
  end if;
  return jsonb_build_object('ok', true, 'id', id_);
end $$;

-- one place, one day: bills and net sales with the same definition as daily_digest (net of returns when the setting is on)
create or replace function public._xc_outlet_day(p_day date, p_loc int) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('net',
           (select coalesce(sum(s.total), 0) from public.sales s where s.status = 'done' and s.sale_date = p_day and s.location_id = p_loc)
         - case when public.rule_on('reports_net_of_returns') then
             (select coalesce(sum(r.amount), 0) from public.sale_returns r where r.status = 'done' and r.location_id = p_loc and (r.created_at at time zone 'Asia/Dhaka')::date = p_day)
           else 0 end,
         'bills', (select count(*) from public.sales s where s.status = 'done' and s.sale_date = p_day and s.location_id = p_loc));
$$;

-- ---------- the composed summary (one JSON; the server decides every figure) ----------
create or replace function public.xc_summary_compose(p_date date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_date, public._today()); dig jsonb; sales_t jsonb; sales_y jsonb; sales_w jsonb; cash jsonb; wallets jsonb; wast jsonb;
        cakes int; cake_specs int; open_o int; failed_jobs int := 0; failed_mail int; failed_ifail int; nflag int := 0; attention int; by_loc jsonb := '[]'::jsonb;
        notes jsonb := '[]'::jsonb; coll numeric := 0; outlet_name text; ex_red int; ex_yellow int; appr int; lowc int; expc int; st jsonb; rc jsonb;
begin
  if not public._xc_summary_ok() then raise exception 'not allowed'; end if;
  if d > public._today() or d < public._today() - 400 then raise exception 'bad_date'; end if;
  if p_loc is not null then
    if not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
    select name_en into outlet_name from public.locations where id = p_loc;
  end if;
  -- sales: owner = the whole company (daily_digest, same figures as the e-mail digest); outlet = that place only, same definition (net of returns when the setting is on)
  if p_loc is null then
    dig := public.daily_digest(d);
    sales_t := dig -> 'sales' -> 'today'; sales_y := dig -> 'sales' -> 'yesterday'; sales_w := dig -> 'sales' -> 'last_week'; by_loc := dig -> 'sales' -> 'by_location';
  else
    sales_t := public._xc_outlet_day(d, p_loc); sales_y := public._xc_outlet_day(d - 1, p_loc); sales_w := public._xc_outlet_day(d - 7, p_loc);
  end if;
  select jsonb_build_object('short', coalesce(sum(-amount) filter (where amount < 0), 0), 'over', coalesce(sum(amount) filter (where amount > 0), 0), 'count', count(*))
    into cash from public.exceptions where flag_code = 'cash_short_over' and entry_date = d and (p_loc is null or location_id = p_loc);
  select jsonb_build_object('total', coalesce(sum(amount), 0), 'by_wallet', coalesce(jsonb_agg(jsonb_build_object('wallet', w.wallet, 'amount', w.amount) order by w.wallet) filter (where w.wallet is not null), '[]'::jsonb))
    into wallets from (select sp.wallet, sum(sp.amount) as amount from public.sale_payments sp
                        where sp.mode = 'mobile' and not sp.voided and (sp.paid_at at time zone 'Asia/Dhaka')::date = d and (p_loc is null or sp.location_id = p_loc) group by sp.wallet) w;
  select coalesce(sum(amount), 0) into coll from public.sale_payments where kind = 'collection' and not voided and (paid_at at time zone 'Asia/Dhaka')::date = d and (p_loc is null or location_id = p_loc);
  select jsonb_build_object('count', count(*), 'value', coalesce(round(sum(x.qty * coalesce(b.avg_cost, 0)), 2), 0)) into wast
    from public.stock_wastage x left join public.stock_balance b on b.item_id = x.item_id and b.location_id = x.location_id
   where (x.made_at at time zone 'Asia/Dhaka')::date = d and (p_loc is null or x.location_id = p_loc);
  select count(*) into open_o from public.online_orders where status in ('new', 'confirmed', 'packed') and (p_loc is null or location_id = p_loc);
  select count(*) into cakes from public.online_orders o where o.status in ('new', 'confirmed', 'packed') and o.delivery_date = d + 1 and (p_loc is null or o.location_id = p_loc);
  select count(*) into cake_specs from public.online_orders o where o.status in ('new', 'confirmed', 'packed') and o.delivery_date = d + 1 and (p_loc is null or o.location_id = p_loc)
     and exists (select 1 from public.order_cake_specs c where c.order_id = o.id and c.state = 'active');
  -- company-wide sections: only in the owner summary (an outlet recipient does not see other outlets' dues, approvals or failures)
  if p_loc is null then
    ex_red := (dig -> 'exceptions_open' ->> 'red')::int; ex_yellow := (dig -> 'exceptions_open' ->> 'yellow')::int;
    appr := (dig ->> 'approvals_pending')::int; lowc := (dig -> 'stock_alerts' ->> 'low_items')::int; expc := (dig -> 'stock_alerts' ->> 'expiring_batches')::int;
    select count(*) into failed_ifail from public.intake_failures where state = 'failed';
    select count(*) into failed_mail from public.notify_outbox where status = 'failed' and created_at > now() - interval '1 day';
    if to_regclass('public.job_runs') is not null then
      execute $q$select count(*) from public.job_runs where status = 'failed' and started_at > now() - interval '1 day'$q$ into failed_jobs;
    end if;
    st := dig -> 'backup';
  end if;
  attention := coalesce(cash ->> 'count', '0')::int + coalesce(appr, 0) + coalesce(lowc, 0) + coalesce(expc, 0) + coalesce(ex_red, 0) + coalesce(failed_ifail, 0)
             + coalesce(failed_mail, 0) + coalesce(failed_jobs, 0) + cakes + coalesce((wast ->> 'count')::int, 0);
  if p_loc is null and (st ->> 'stale')::boolean then attention := attention + 1; end if;
  -- what the summary says about itself (no ML, no probability)
  notes := jsonb_build_array(
    jsonb_build_object('code', 'figures_are_server_totals', 'text_en', 'Every figure is computed on the server for the day shown; nothing is estimated.', 'text_bn', 'সব সংখ্যা সার্ভারে ওই দিনের হিসাব; কোনো অনুমান নেই।'),
    jsonb_build_object('code', 'net_of_returns', 'text_en', case when public.rule_on('reports_net_of_returns') then 'Sales are net of returns.' else 'Sales are gross (returns not deducted; setting off).' end,
                       'text_bn', case when public.rule_on('reports_net_of_returns') then 'বিক্রি ফেরত বাদে (নিট)।' else 'বিক্রি ফেরত না বাদ দিয়ে (সেটিং বন্ধ)।' end));
  if p_loc is not null then
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'outlet_scope', 'text_en', 'Outlet view: company-wide dues, approvals, stock alerts and failures are left out.', 'text_bn', 'শাখার দৃশ্য: কোম্পানি-ব্যাপী বাকি, অনুমোদন, স্টক সতর্কতা ও ব্যর্থতা বাদ।'));
  end if;
  return jsonb_strip_nulls(jsonb_build_object('date', d, 'scope', case when p_loc is null then 'owner' else 'outlet' end, 'location_id', p_loc, 'location_name_en', outlet_name,
    'generated_at', now(),
    'sales', jsonb_build_object('today', sales_t, 'yesterday', sales_y, 'last_week', sales_w,
       'vs_yesterday_pct', case when (sales_y ->> 'net')::numeric > 0 then round(((sales_t ->> 'net')::numeric - (sales_y ->> 'net')::numeric) * 100 / (sales_y ->> 'net')::numeric, 1) end,
       'vs_last_week_pct', case when (sales_w ->> 'net')::numeric > 0 then round(((sales_t ->> 'net')::numeric - (sales_w ->> 'net')::numeric) * 100 / (sales_w ->> 'net')::numeric, 1) end,
       'by_location', by_loc),
    'cash', cash, 'wallet_receipts', wallets, 'collections', coll, 'wastage', wast,
    'orders', jsonb_build_object('open', open_o, 'cakes_due_tomorrow', cakes, 'cake_specs_due_tomorrow', cake_specs),
    'owner_only', case when p_loc is null then jsonb_build_object('dues', dig -> 'dues', 'approvals_waiting', appr, 'low_stock_items', lowc, 'batches_expiring', expc,
        'red_exceptions', ex_red, 'yellow_exceptions', ex_yellow, 'failed_intake', failed_ifail, 'failed_mail', failed_mail, 'failed_jobs', failed_jobs,
        'backup', st, 'day_close', dig -> 'day_close') end,
    'attention_items', attention, 'nothing_to_report', (attention = 0 and coalesce((sales_t ->> 'bills')::int, 0) = 0),
    'notes', notes));
end $$;

-- ---------- what the script needs: active recipients and the switches (no send from SQL) ----------
create or replace function public.xc_summary_targets() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._xc_summary_ok() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'on', public.rule_on('xc_summary_on'), 'email_on', public.rule_on('xc_summary_email_on'), 'telegram_on', public.rule_on('xc_summary_telegram_on'),
    'times', coalesce(public.rule_val('xc_summary_times') #>> '{}', '21'),
    'recipients', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'name', r.name, 'channel', r.channel, 'address', r.address, 'scope', r.scope,
                                       'location_id', r.location_id, 'quiet_when_empty', r.quiet_when_empty) order by r.id)
                              from public.xc_summary_recipients r where r.active), '[]'::jsonb));
end $$;

-- ---------- the script writes one line per send (or failed send); a second 'sent' for the same day is refused by the index ----------
create or replace function public.xc_summary_record(p_run date, p_recipient bigint, p_channel text, p_status text, p_hash text default null, p_error text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.xc_summary_recipients; id_ bigint;
begin
  if not public._xc_summary_ok() then raise exception 'not allowed'; end if;
  if p_status not in ('sent', 'failed', 'skipped_empty') then raise exception 'bad_status'; end if;
  if p_channel not in ('email', 'telegram') then raise exception 'bad_channel'; end if;
  select * into r from public.xc_summary_recipients where id = p_recipient;
  if not found then raise exception 'not_found'; end if;
  if r.channel <> p_channel then raise exception 'channel_mismatch'; end if;
  insert into public.xc_summary_log (run_date, recipient_id, channel, scope, location_id, status, content_hash, error)
    values (p_run, r.id, p_channel, r.scope, r.location_id, p_status, left(p_hash, 80), left(p_error, 300)) returning id into id_;
  return jsonb_build_object('ok', true, 'id', id_);
end $$;

create or replace function public.xc_summary_already_sent(p_run date, p_recipient bigint, p_channel text) returns boolean
language sql stable security definer set search_path = public as $$
  select public._xc_summary_ok() and exists (select 1 from public.xc_summary_log where run_date = p_run and recipient_id = p_recipient and channel = p_channel and status = 'sent');
$$;

-- owner history of what went out (no addresses; the log holds ids, status and a short error)
create or replace function public.xc_summary_history(p_limit int default 30) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.is_owner() then jsonb_build_object('rows', '[]'::jsonb, 'denied', true) else jsonb_build_object('rows', coalesce(jsonb_agg(z order by z.run_date desc, z.id desc), '[]'::jsonb)) end
    from (select l.id, l.run_date, l.channel, l.scope, l.location_id, l.status, l.error, l.created_at, r.name as recipient
            from public.xc_summary_log l left join public.xc_summary_recipients r on r.id = l.recipient_id
           order by l.run_date desc, l.id desc limit least(greatest(coalesce(p_limit, 30), 1), 200)) z;
$$;

-- ---------- receipt continuity and "every shop synced?" (server side: what the server has received) ----------
-- Receipts are numbered per place by the app. Inside a period the numbers of one place must run without a gap; a gap is a sale the server never received
-- (or a number that was used offline on another device). The check is a flag for the owner to look at, never an automatic correction.
create or replace function public.xc_sync_report(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, public._today() - 7); t date := coalesce(p_to, public._today()); stale numeric := public.rule_num('xc_sync_stale_hours'); rows_ jsonb;
begin
  if not (public.is_owner() or public.rpt_access('sales')) then raise exception 'not allowed'; end if;
  if t < f or t - f > 120 then raise exception 'bad_range'; end if;
  select coalesce(jsonb_agg(z order by z.location_id), '[]'::jsonb) into rows_ from (
    select base.location_id, base.name, base.sales, base.first_receipt, base.last_receipt, base.receipt_gaps, base.last_sale_ever,
           case when base.sales = 0 then null when base.receipt_gaps > 0 then 'gap' else 'ok' end as receipt_state,
           case when stale is null then 'threshold_not_set' when base.last_sale_ever is null then 'no_sales'
                when base.last_sale_ever < now() - make_interval(hours => stale::int) then 'stale' else 'ok' end as sync_state
      from (
        select l.id as location_id, l.name_en as name, count(s.id) as sales, min(s.receipt) as first_receipt, max(s.receipt) as last_receipt,
               coalesce((max(s.receipt) - min(s.receipt) + 1) - count(distinct s.receipt), 0) as receipt_gaps,
               (select max(x.sold_at) from public.sales x where x.location_id = l.id and x.status = 'done') as last_sale_ever
          from public.locations l left join public.sales s on s.location_id = l.id and s.sale_date between f and t
         where l.is_active and l.status = 'live' and (p_loc is null or l.id = p_loc)
         group by l.id, l.name_en) base) z;
  return jsonb_build_object('from', f, 'to', t, 'stale_hours', stale, 'rows', coalesce(rows_, '[]'::jsonb),
    'notes', jsonb_build_array(
      'receipt_state gap = numbers missing inside the period for that place: check the offline outbox on the phone and the voided bills before assuming a loss.',
      'sync_state uses the time of the last recorded sale (the server has no per-device timestamp in this build); a quiet shop is not a broken one.',
      'threshold_not_set = the owner has not typed the hours; nothing is flagged until then.'));
end $$;

-- sync alert: one in-app warning per outlet per day, only when switched on AND the hours are typed
create or replace function public.xc_sync_alert_scan(p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rep jsonb; r jsonb; n int := 0; stale numeric := public.rule_num('xc_sync_stale_hours');
begin
  if not (public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
  if not public.rule_on('xc_sync_alert_on') then return jsonb_build_object('skipped', 'switch_off'); end if;
  if stale is null then return jsonb_build_object('skipped', 'threshold_not_set'); end if;
  rep := public.xc_sync_report(null, null, null);
  for r in select * from jsonb_array_elements(rep -> 'rows') loop
    if r ->> 'sync_state' = 'stale' then
      if not p_dry then
        perform public._notif_add('sync_stale', 'warn', 'দোকান থেকে বিক্রি আসেনি: ' || (r ->> 'name'), 'No sale received from: ' || (r ->> 'name'),
          'শেষ বিক্রি ' || to_char((select max(sold_at) at time zone 'Asia/Dhaka' from public.sales where location_id = (r ->> 'location_id')::int and status = 'done'), 'DD Mon HH24:MI') || '। সীমা ' || stale || ' ঘণ্টা।',
          'Last sale ' || to_char((select max(sold_at) at time zone 'Asia/Dhaka' from public.sales where location_id = (r ->> 'location_id')::int and status = 'done'), 'DD Mon HH24:MI') || '. Limit ' || stale || ' hours.',
          '#/home', (r ->> 'location_id')::text, 'owner', (r ->> 'location_id')::int);
      end if;
      n := n + 1;
    end if;
  end loop;
  return jsonb_build_object('stale_outlets', n, 'dry', p_dry);
end $$;

-- ---------- access: closed helpers, reads by signed-in roles only ----------
do $c$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_xc_summary_ok', '_xc_outlet_day') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $c$;
revoke all on function public.xc_summary_compose(date, int) from public, anon;
revoke all on function public.xc_summary_targets() from public, anon;
revoke all on function public.xc_summary_record(date, bigint, text, text, text, text) from public, anon;
revoke all on function public.xc_summary_already_sent(date, bigint, text) from public, anon;
revoke all on function public.xc_summary_history(int) from public, anon;
revoke all on function public.xc_sync_report(date, date, int) from public, anon;
revoke all on function public.xc_sync_alert_scan(boolean) from public, anon;
revoke all on function public.xc_recipient_save(bigint, jsonb) from public, anon;
grant execute on function public.xc_summary_compose(date, int) to authenticated;
grant execute on function public.xc_summary_targets() to authenticated;
grant execute on function public.xc_summary_record(date, bigint, text, text, text, text) to authenticated;
grant execute on function public.xc_summary_already_sent(date, bigint, text) to authenticated;
grant execute on function public.xc_summary_history(int) to authenticated;
grant execute on function public.xc_sync_report(date, date, int) to authenticated;
grant execute on function public.xc_sync_alert_scan(boolean) to authenticated;
grant execute on function public.xc_recipient_save(bigint, jsonb) to authenticated;

notify pgrst, 'reload schema';

-- ===================== phase495.sql =====================
-- Phase 495 (XC-2) - DAILY PRODUCTION SUGGESTION, THE BAKER'S CONFIRMATION, AND THE ACCURACY REPORT.
-- Paste AFTER phase494. Paste-twice safe. Earlier phase files are not edited.
-- OFF by default: switch xc_prod_suggest_on (false). Window xc_prod_weeks is BLANK by default: with it blank nothing is suggested ("data needed").
-- A suggestion is arithmetic on the server, not a forecasting model. It writes NOTHING to production_plans: the baker copies or edits the lines in the production screen.
--   EXPECTED   = average sold on the same weekday over the last N weeks, using only TRADING days (a day with a bill) that are not festival days.
--   RANGE      = the lowest and the highest of those days (a range of what happened; NOT a confidence interval; no probability is claimed).
--   FESTIVAL   = an owner-entered festival covering the day shows the owner uplift % as a separate "with uplift" figure (only if the owner typed one).
--   CARRY-OVER = finished stock on hand at the place now (stock_balance); it is subtracted.
--   OPEN ORDERS = production orders for that place due that day (open status); they are added.
--   SUGGESTED  = max(0, expected + open orders - carry-over)   (or the uplifted expected, when a festival uplift applies). Rounded to 2 decimals.
-- Confirmation stores the suggestion AS IT WAS when the baker confirmed, so the accuracy report compares like with like later.
-- Costs are not used. Supplier prices are not used. No weather, no trend, no ML.

do $g$ begin
  if to_regprocedure('public._rb4_prod_view(integer)') is null or to_regprocedure('public._rb4_prod_entry(integer)') is null then raise exception 'phase495 needs phase404'; end if;
  if to_regclass('public.festival_calendar') is null then raise exception 'phase495 needs phase465 (festival calendar)'; end if;
  if to_regclass('public.production_orders') is null then raise exception 'phase495 needs phase404 (production orders)'; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'xc', v.kind, v.dv, v.unit, null, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('xc_prod_suggest_on', 'switch', 'false'::jsonb, null::text, null::numeric, null::numeric,
   'দৈনিক উৎপাদন পরামর্শ / Daily production suggestion: on', 'Shows suggested quantities on the production planning screen. OFF = no suggestion is calculated.', 9510),
 ('xc_prod_weeks', 'number', null::jsonb, 'weeks', 1::numeric, 12::numeric,
   'কত সপ্তাহের একই বারের বিক্রি দেখে পরামর্শ (ফাঁকা = সেট নেই) / Weeks of same-weekday history (blank = not set)', 'Blank = no suggestion, the screen says "data needed: xc_prod_weeks". Nothing is assumed.', 9511)
  ) as v(key, kind, dv, unit, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

-- ---------- what was suggested, confirmed, made and left (append-only per day, place and item; a re-confirm updates the planned figure and keeps the history) ----------
create table if not exists public.xc_prod_feedback (
  id bigint generated by default as identity primary key,
  plan_date date not null,
  location_id int not null references public.locations(id),
  item_id uuid not null references public.items(id),
  suggested_qty numeric check (suggested_qty is null or suggested_qty >= 0),
  range_low numeric check (range_low is null or range_low >= 0),
  range_high numeric check (range_high is null or range_high >= 0),
  days_used int check (days_used is null or days_used >= 0),
  planned_qty numeric check (planned_qty is null or planned_qty >= 0),           -- what the baker confirmed
  made_qty numeric check (made_qty is null or made_qty >= 0),                    -- what was made (entered later, base unit)
  unsold_qty numeric check (unsold_qty is null or unsold_qty >= 0),              -- left at close (entered later)
  note text check (note is null or length(note) <= 300),
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz,
  unique (plan_date, location_id, item_id)
);
alter table public.xc_prod_feedback enable row level security;
revoke all on public.xc_prod_feedback from public, anon, authenticated;
grant select on public.xc_prod_feedback to authenticated;
drop policy if exists xc_prod_feedback_read on public.xc_prod_feedback;
create policy xc_prod_feedback_read on public.xc_prod_feedback for select to authenticated using (public._rb4_prod_view(location_id));
drop trigger if exists audit_xc_prod_feedback on public.xc_prod_feedback;
create trigger audit_xc_prod_feedback after insert or update on public.xc_prod_feedback for each row execute function public.log_change('id');
drop trigger if exists xc_prod_feedback_nodel on public.xc_prod_feedback;
create trigger xc_prod_feedback_nodel before delete on public.xc_prod_feedback for each row execute function public.no_hard_delete();

-- ---------- one place, one day: item sold (quantity in the item base unit as the sale lines carry it) ----------
create or replace function public._xc_sold_day(p_loc int, p_day date) returns table (item_id uuid, qty numeric)
language sql stable security definer set search_path = public as $$
  select (x.l ->> 'item_id')::uuid, sum((x.l ->> 'qty')::numeric)
    from public.sales s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) x(l)
   where s.status = 'done' and s.location_id = p_loc and s.sale_date = p_day
     and (x.l ->> 'item_id') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' and (x.l ->> 'qty') ~ '^[0-9]+(\.[0-9]+)?$'
   group by 1;
$$;

-- ---------- the suggestion (read only; writes nothing) ----------
create or replace function public.xc_prod_suggest(p_date date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_date, public._today()); w int; ndays int; lines_ jsonb; fest jsonb; upl numeric; fest_name text; rows_ jsonb;
begin
  if p_loc is null or not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  if not public.rule_on('xc_prod_suggest_on') then return jsonb_build_object('skipped', 'switch_off'); end if;
  if d > public._today() + 14 or d < public._today() - 400 then raise exception 'bad_date'; end if;
  w := public.rule_num('xc_prod_weeks')::int;
  if w is null then return jsonb_build_object('date', d, 'location_id', p_loc, 'data_needed', jsonb_build_array('xc_prod_weeks'), 'rows', '[]'::jsonb); end if;
  -- festival covering the day (owner-entered; the largest uplift the owner typed)
  select f.name_en, f.uplift_pct into fest_name, upl from public.festival_calendar f
   where f.active and d between f.start_date and f.end_date and (f.location_id is null or f.location_id = p_loc)
   order by f.uplift_pct desc nulls last limit 1;
  -- same weekday, last w weeks; trading days only; festival days left out of the ordinary average
  with days as (select (d - 7 * k)::date as dd from generate_series(1, w) k),
  trading as (select dd from days t where exists (select 1 from public.sales s where s.status = 'done' and s.location_id = p_loc and s.sale_date = t.dd)),
  ordinary as (select t.dd from trading t where not exists (select 1 from public.festival_calendar f where f.active and t.dd between f.start_date and f.end_date and (f.location_id is null or f.location_id = p_loc))),
  sold as (select o.dd, x.item_id, x.qty from ordinary o cross join lateral public._xc_sold_day(p_loc, o.dd) x),
  items as (select distinct sold.item_id from sold),
  grid as (select i.item_id, o.dd, coalesce((select sum(sd.qty) from sold sd where sd.item_id = i.item_id and sd.dd = o.dd), 0) as q from items i cross join ordinary o),
  stat as (select g.item_id, round(avg(g.q), 3) as expected, min(g.q) as lo, max(g.q) as hi from grid g group by g.item_id),
  ord as (select po.item_id, sum(po.qty) as qty from public.production_orders po where po.status = 'open' and po.location_id = p_loc and coalesce(po.due_date, po.order_date) = d group by po.item_id),
  allitems as (select item_id from items union select item_id from ord),
  base as (
    select a.item_id, i.code, i.name_bn, i.name_en,
           coalesce(s.expected, 0) as expected, coalesce(s.lo, 0) as lo, coalesce(s.hi, 0) as hi,
           coalesce(o.qty, 0) as orders, coalesce(sb.qty, 0) as carry
      from allitems a join public.items i on i.id = a.item_id
      left join stat s on s.item_id = a.item_id left join ord o on o.item_id = a.item_id
      left join public.stock_balance sb on sb.item_id = a.item_id and sb.location_id = p_loc)
  select (select count(*) from ordinary), coalesce(jsonb_agg(jsonb_build_object(
      'item_id', b.item_id, 'code', b.code, 'name_bn', b.name_bn, 'name_en', coalesce(b.name_en, b.name_bn),
      'days_used', (select count(*) from ordinary), 'window_weeks', w,
      'expected', b.expected, 'range_low', greatest(0, round(b.lo + b.orders - b.carry, 2)), 'range_high', greatest(0, round(b.hi + b.orders - b.carry, 2)),
      'open_orders', b.orders, 'carry_over', b.carry,
      'festival', fest_name, 'uplift_pct', upl,
      'with_uplift', case when upl is not null then round(greatest(0, b.expected * (1 + upl / 100) + b.orders - b.carry), 2) end,
      'suggested', round(greatest(0, case when upl is not null then b.expected * (1 + upl / 100) else b.expected end + b.orders - b.carry), 2),
      'explanation_en', 'Average of ' || (select count(*) from ordinary) || ' same-weekday trading day(s), range ' || b.lo || ' to ' || b.hi
          || '; plus open orders ' || b.orders || '; minus carry-over ' || b.carry || '.' || case when upl is not null then ' Festival uplift ' || upl || '% shown separately.' else '' end,
      'explanation_bn', 'একই বারের ' || (select count(*) from ordinary) || 'টি বিক্রির দিনের গড়, সীমা ' || b.lo || ' থেকে ' || b.hi
          || '; যোগ: খোলা অর্ডার ' || b.orders || '; বিয়োগ: হাতে থাকা স্টক ' || b.carry || '।' || case when upl is not null then ' উৎসবের বাড়তি ' || upl || '% আলাদা দেখানো।' else '' end)
      order by b.code), '[]'::jsonb)
    into ndays, rows_ from base b;
  return jsonb_build_object('date', d, 'location_id', p_loc, 'window_weeks', w, 'trading_days_used', ndays, 'festival', fest_name, 'uplift_pct', upl,
    'rows', rows_,
    'data_needed', case when ndays = 0 then jsonb_build_array('no_same_weekday_trading_day_in_window') else '[]'::jsonb end,
    'notes', jsonb_build_array(
      'Arithmetic only: an average of past same weekdays, not a forecasting model. No probability is claimed.',
      'The range is the lowest and the highest of the past days, not a confidence interval.',
      'Days without a bill are closed, not zero sales; they are not counted.',
      'Festival days in the past are left out of the ordinary average; the owner uplift is shown separately.',
      'Carry-over is the stock on hand now; re-check it before the baker confirms.'));
end $$;

-- ---------- the baker confirms (stores the suggestion as it stands now, and the planned quantity; a line with no suggestion is stored with blanks) ----------
create or replace function public.xc_prod_confirm(p_date date, p_loc int, p_lines jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sg jsonb; ln jsonb; x jsonb; it uuid; pq numeric; n int := 0;
begin
  if not public._rb4_prod_entry(p_loc) and not public.is_owner() then raise exception 'not allowed'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) > 200 then raise exception 'bad_value'; end if;
  sg := public.xc_prod_suggest(p_date, p_loc);
  if sg ? 'skipped' then raise exception 'suggestion_off'; end if;
  for ln in select * from jsonb_array_elements(p_lines) loop
    it := nullif(ln ->> 'item_id', '')::uuid;
    pq := nullif(ln ->> 'planned_qty', '')::numeric;
    if it is null or pq is null or pq < 0 or pq > 999999999 then raise exception 'bad_value'; end if;
    select z into x from jsonb_array_elements(coalesce(sg -> 'rows', '[]'::jsonb)) z where (z ->> 'item_id')::uuid = it;
    insert into public.xc_prod_feedback (plan_date, location_id, item_id, suggested_qty, range_low, range_high, days_used, planned_qty, created_by)
      values (p_date, p_loc, it, (x ->> 'suggested')::numeric, (x ->> 'range_low')::numeric, (x ->> 'range_high')::numeric, (x ->> 'days_used')::int, pq, auth.uid())
      on conflict (plan_date, location_id, item_id) do update set planned_qty = excluded.planned_qty, suggested_qty = excluded.suggested_qty,
        range_low = excluded.range_low, range_high = excluded.range_high, days_used = excluded.days_used, updated_by = auth.uid(), updated_at = now();
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'saved', n);
end $$;

-- ---------- after the day: what was made and what was left (the person enters it; nothing is computed here) ----------
create or replace function public.xc_prod_actual_save(p_date date, p_loc int, p_item uuid, p_made numeric, p_unsold numeric, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._rb4_prod_entry(p_loc) and not public.is_owner() then raise exception 'not allowed'; end if;
  if p_made is not null and (p_made < 0 or p_made > 999999999) then raise exception 'bad_value'; end if;
  if p_unsold is not null and (p_unsold < 0 or p_unsold > 999999999) then raise exception 'bad_value'; end if;
  if not exists (select 1 from public.xc_prod_feedback where plan_date = p_date and location_id = p_loc and item_id = p_item) then raise exception 'not_confirmed'; end if;
  update public.xc_prod_feedback set made_qty = p_made, unsold_qty = p_unsold, note = left(nullif(btrim(p_note), ''), 300), updated_by = auth.uid(), updated_at = now()
   where plan_date = p_date and location_id = p_loc and item_id = p_item;
  return jsonb_build_object('ok', true);
end $$;

-- ---------- accuracy: did the suggestion's range hold the sold quantity? (days with a stored suggestion only; no verdict is written) ----------
create or replace function public.xc_prod_accuracy(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, public._today() - 30); t date := coalesce(p_to, public._today()); rows_ jsonb;
begin
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  if p_loc is null and not public.is_owner() then raise exception 'not allowed'; end if;
  if t < f or t - f > 400 then raise exception 'bad_range'; end if;
  select coalesce(jsonb_agg(z order by z.code, z.location_id), '[]'::jsonb) into rows_ from (
    select fb.location_id, i.code, coalesce(i.name_en, i.name_bn) as name, count(*) as days,
           count(*) filter (where fb.suggested_qty is not null) as with_suggestion,
           round(avg(fb.suggested_qty), 2) as avg_suggested, round(avg(fb.planned_qty), 2) as avg_planned,
           round(avg(coalesce(sd.qty, 0)), 2) as avg_sold,
           round(avg(abs(fb.suggested_qty - coalesce(sd.qty, 0))), 2) as avg_abs_error,
           round(100.0 * count(*) filter (where fb.range_low is not null and coalesce(sd.qty, 0) between fb.range_low and fb.range_high) / nullif(count(*) filter (where fb.range_low is not null), 0), 1) as sold_in_range_pct,
           round(100.0 * count(*) filter (where fb.planned_qty <> fb.suggested_qty) / nullif(count(*) filter (where fb.suggested_qty is not null), 0), 1) as edited_pct,
           round(sum(fb.unsold_qty), 2) as unsold_total, round(sum(fb.made_qty), 2) as made_total
      from public.xc_prod_feedback fb join public.items i on i.id = fb.item_id
      left join lateral (select sum(x.qty) as qty from public._xc_sold_day(fb.location_id, fb.plan_date) x where x.item_id = fb.item_id) sd on true
     where fb.plan_date between f and t and (p_loc is null or fb.location_id = p_loc)
     group by fb.location_id, i.code, i.name_en, i.name_bn) z;
  return jsonb_build_object('from', f, 'to', t, 'location_id', p_loc, 'rows', rows_,
    'notes', jsonb_build_array('Sold = the sales of that day at that place (base unit).', 'sold_in_range_pct counts days when the sold quantity fell inside the suggested range.',
      'A row with few days says little. No verdict is written by the system.'));
end $$;

do $c$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_xc_sold_day') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $c$;
revoke all on function public.xc_prod_suggest(date, int) from public, anon;
revoke all on function public.xc_prod_confirm(date, int, jsonb) from public, anon;
revoke all on function public.xc_prod_actual_save(date, int, uuid, numeric, numeric, text) from public, anon;
revoke all on function public.xc_prod_accuracy(date, date, int) from public, anon;
grant execute on function public.xc_prod_suggest(date, int) to authenticated;
grant execute on function public.xc_prod_confirm(date, int, jsonb) to authenticated;
grant execute on function public.xc_prod_actual_save(date, int, uuid, numeric, numeric, text) to authenticated;
grant execute on function public.xc_prod_accuracy(date, date, int) to authenticated;

notify pgrst, 'reload schema';

-- ===================== phase496.sql =====================
-- Phase 496 (XC-3) - SUPPLIER PRICE INTELLIGENCE: last price, 90-day trend, cheapest supplier, costliest ingredients, rise alerts and a recipe-cost preview.
-- Paste AFTER phase495. Paste-twice safe. Earlier phase files are not edited. It does NOT duplicate the purchase-rate trend report (p2_rate_trend, phase434): it links to it.
-- Prices are costs: readable only by the owner, the cost right (rpt_cost_ok) or the recipe-cost right. Browsers never read the tables directly.
-- OFF by default: switch xc_price_alert_on (false). The rise threshold xc_price_rise_pct is BLANK by default: with it blank the alert says "threshold not set" and writes nothing.
-- The alert compares the latest purchase rate of an item from a supplier with the one before it (the same supplier), inside the last 90 days. An alert is an in-app warning only.
-- The recipe preview changes ONE ingredient price on paper and shows the change per batch and per unit. It saves nothing.

do $g$ begin
  if to_regprocedure('public._p26_rates(date,date,integer[])') is null then raise exception 'phase496 needs phase434 (purchase rates)'; end if;
  if to_regprocedure('public._recipe_need(uuid,numeric,integer)') is null then raise exception 'phase496 needs phase74 (recipe need)'; end if;
  if to_regprocedure('public._notif_add(text,text,text,text,text,text,text,text,text,integer)') is null then raise exception 'phase496 needs the notifications helper'; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'xc', v.kind, v.dv, v.unit, null, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('xc_price_alert_on', 'switch', 'false'::jsonb, null::text, null::numeric, null::numeric,
   'ক্রয়মূল্য বৃদ্ধির সতর্কতা / Supplier price-rise alert: on', 'Writes an in-app warning when a purchase rate rises by more than the threshold below. OFF = nothing is checked.', 9520),
 ('xc_price_rise_pct', 'number', null::jsonb, '%', 1::numeric, 500::numeric,
   'কত % বাড়লে সতর্কতা (ফাঁকা = সেট নেই) / Rise % that triggers the alert (blank = not set)', 'Blank = "threshold not set" and nothing is written. Nothing is assumed.', 9521)
  ) as v(key, kind, dv, unit, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

-- one place of truth for "the rates of the last 90 days" (all places; the cost right decides who reads)
create or replace function public._xc_rates90() returns table (item_id uuid, supplier text, dt date, rate numeric, qty numeric, ord text)
language sql stable security definer set search_path = public as $$
  select r.item_id, r.sname, r.dt, r.rate, r.qty, r.ord from public._p26_rates(public._today() - 90, public._today(), array(select l.id from public.locations l)) r;
$$;

-- the price board (read only). Owner, or a holder of the cost right.
create or replace function public.xc_price_board(p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows_ jsonb; sup jsonb;
begin
  if not (public.is_owner() or public.rpt_cost_ok()) then raise exception 'not allowed'; end if;
  with r as (select * from public._xc_rates90()),
  per_sup as (   -- per item and supplier: last rate, the rate before it, first rate, last date, count
    select r.item_id, r.supplier,
           (array_agg(r.rate order by r.dt desc, r.ord desc))[1] as last_rate,
           (array_agg(r.rate order by r.dt desc, r.ord desc))[2] as prev_rate,
           (array_agg(r.rate order by r.dt, r.ord))[1] as first_rate,
           max(r.dt) as last_date, count(*) as n
      from r group by r.item_id, r.supplier),
  cheapest as (select distinct on (item_id) item_id, supplier as cheapest_supplier, last_rate as cheapest_rate
                 from per_sup order by item_id, last_rate asc, supplier),
  spend as (select item_id, sum(qty * rate) as spend90, sum(qty) as qty90 from r group by item_id),
  itm as (select ps.item_id, sum(ps.n) as n, max(ps.last_date) as last_date,
                 (select p.last_rate from per_sup p where p.item_id = ps.item_id order by p.last_date desc limit 1) as last_rate,
                 (select p.supplier from per_sup p where p.item_id = ps.item_id order by p.last_date desc limit 1) as last_supplier,
                 (select r2.rate from r r2 where r2.item_id = ps.item_id order by r2.dt, r2.ord limit 1) as first_rate
            from per_sup ps group by ps.item_id)
  select coalesce(jsonb_agg(jsonb_build_object('item_code', i.code, 'item_name', coalesce(i.name_en, i.name_bn), 'base_unit', i.base_unit,
      'last_rate', round(x.last_rate, 4), 'last_supplier', x.last_supplier, 'last_date', x.last_date,
      'trend_90d_pct', case when x.first_rate > 0 then round((x.last_rate - x.first_rate) / x.first_rate * 100, 2) end,
      'cheapest_supplier', c.cheapest_supplier, 'cheapest_rate', round(c.cheapest_rate, 4),
      'spend_90d', round(s.spend90, 2), 'qty_90d', round(s.qty90, 3), 'purchase_lines', x.n,
      'see', '#/report/p2_rate_trend')
      order by s.spend90 desc nulls last), '[]'::jsonb)
    into rows_
    from itm x join public.items i on i.id = x.item_id left join cheapest c on c.item_id = x.item_id left join spend s on s.item_id = x.item_id
   where x.last_rate is not null;
  return jsonb_build_object('window_days', 90,
    'items', coalesce(rows_, '[]'::jsonb), 'costliest_by_last_rate', (select coalesce(jsonb_agg(z), '[]'::jsonb) from (select e ->> 'item_name' as item_name, e ->> 'last_rate' as last_rate, e ->> 'base_unit' as base_unit
       from jsonb_array_elements(coalesce(rows_, '[]'::jsonb)) e order by (e ->> 'last_rate')::numeric desc nulls last limit greatest(least(coalesce(p_limit, 50), 200), 1)) z),
    'notes', jsonb_build_array('Costs: last purchase rate per base unit. Spend = quantity x rate over the 90 days.',
      'Trend = last rate against the first rate in the window (not a forecast).', 'Full history: the purchase-rate trend report (p2_rate_trend).'));
end $$;

-- the alert scan: latest rate against the previous rate of the SAME supplier, last 90 days; one warning per item and supplier per day
create or replace function public.xc_price_alert_scan(p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare thr numeric := public.rule_num('xc_price_rise_pct'); n int := 0; x record; k text;
begin
  if not (public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
  if not public.rule_on('xc_price_alert_on') then return jsonb_build_object('skipped', 'switch_off'); end if;
  if thr is null then return jsonb_build_object('skipped', 'threshold_not_set'); end if;
  for x in
    with r as (select * from public._xc_rates90()),
    ps as (select r.item_id, r.supplier, (array_agg(r.rate order by r.dt desc, r.ord desc))[1] as last_rate, (array_agg(r.rate order by r.dt desc, r.ord desc))[2] as prev_rate,
                  max(r.dt) as last_date from r group by r.item_id, r.supplier having count(*) >= 2)
    select ps.item_id, ps.supplier, ps.last_rate, ps.prev_rate, round((ps.last_rate - ps.prev_rate) / ps.prev_rate * 100, 2) as pct, i.code, coalesce(i.name_en, i.name_bn) as nm
      from ps join public.items i on i.id = ps.item_id
     where ps.prev_rate > 0 and (ps.last_rate - ps.prev_rate) / ps.prev_rate * 100 > thr
  loop
    k := left(x.code || '|' || x.supplier, 80);
    if not p_dry then
      perform public._notif_add('price_rise', 'warn', 'ক্রয়মূল্য বেড়েছে: ' || x.nm, 'Purchase price rose: ' || x.nm,
        x.supplier || ' থেকে ' || x.prev_rate || ' থেকে ' || x.last_rate || ' (' || x.pct || '%)।',
        'From ' || x.supplier || ': ' || x.prev_rate || ' to ' || x.last_rate || ' (' || x.pct || '%).',
        '#/report/p2_rate_trend', k, 'owner', null);
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('alerts', n, 'threshold_pct', thr, 'dry', p_dry);
end $$;

-- the recipe-cost preview: one ingredient at a new price, on paper (saves nothing)
create or replace function public.xc_recipe_price_preview(p_recipe uuid, p_item uuid, p_new_rate numeric) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare need_ numeric; yb numeric; cur numeric; batch_now jsonb; delta numeric;
begin
  if not (public._recipe_cost_ok() or public.rpt_cost_ok()) then raise exception 'not allowed'; end if;
  if p_new_rate is null or p_new_rate < 0 or p_new_rate > 1000000000 then raise exception 'bad_value'; end if;
  select n.need into need_ from public._recipe_need(p_recipe, 1, 0) n where n.item_id = p_item limit 1;
  if need_ is null then return jsonb_build_object('ingredient_in_recipe', false); end if;
  select public._base_qty(rc.item_id, rc.yield_qty, rc.yield_unit) into yb from public.recipes rc where rc.id = p_recipe;
  select (x ->> 'last_rate')::numeric into cur from jsonb_array_elements((public.xc_price_board(1000)) -> 'items') x where x ->> 'item_code' = (select code from public.items where id = p_item);
  if public._recipe_cost_ok() then select public.recipe_cost(p_recipe, null) into batch_now; end if;
  delta := need_ * (p_new_rate - coalesce(cur, 0));
  return jsonb_build_object('ingredient_in_recipe', true, 'need_base_per_batch', round(need_, 4), 'current_rate', cur, 'new_rate', p_new_rate,
    'batch_cost_now', case when batch_now is not null then batch_now -> 'batch_cost' end, 'batch_change', case when cur is not null then round(delta, 4) end,
    'unit_change', case when cur is not null and yb > 0 then round(delta / yb, 6) end, 'yield_base', yb,
    'note', 'Preview only: nothing is saved. Uses the last purchase rate as the current price.');
end $$;

do $c$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_xc_rates90') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $c$;
revoke all on function public.xc_price_board(int) from public, anon;
revoke all on function public.xc_price_alert_scan(boolean) from public, anon;
revoke all on function public.xc_recipe_price_preview(uuid, uuid, numeric) from public, anon;
grant execute on function public.xc_price_board(int) to authenticated;
grant execute on function public.xc_price_alert_scan(boolean) to authenticated;
grant execute on function public.xc_recipe_price_preview(uuid, uuid, numeric) to authenticated;

notify pgrst, 'reload schema';

-- ===================== phase497.sql =====================
-- Phase 497 (XC-4) - END-OF-DAY UNSOLD AND MARKDOWN: what cannot sell tomorrow, the outcome of each unsold unit, and wastage share per item and place.
-- Paste AFTER phase496. Paste-twice safe. Earlier phase files are not edited.
-- OFF by default: switch xc_unsold_on (false). The markdown % xc_markdown_pct is BLANK by default: with it blank no discount is suggested and a sale at a discount is refused ("markdown % not set").
-- WHAT IS AT RISK: stock batches (stock_batches) with units left whose expiry falls before the end of the next Dhaka day. A batch with NO expiry is counted and named as "no expiry captured" (not treated as safe, not treated as expiring).
-- OUTCOMES (one line per decision, append-only, void only): sold_discount (sold at the markdown price; value = quantity x sell price x (1 - %)), staff_meal, donation, waste.
--   An outcome line NEVER moves stock or money. A waste that must leave the stock is booked through the existing wastage screen (stock_wastage); this record says so on the answer.
-- A discount sale is taken at the till through the existing coupon/discount rules; this phase does not create a coupon (no new coupon table).
-- WASTAGE SHARE = wastage quantity / (quantity sold + wastage quantity), with both shown. A zero denominator gives a blank, never 0.

do $g$ begin
  if to_regclass('public.stock_batches') is null or to_regclass('public.stock_wastage') is null then raise exception 'phase497 needs the stock phases'; end if;
  if to_regprocedure('public._rb4_prod_entry(integer)') is null then raise exception 'phase497 needs phase404'; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'xc', v.kind, v.dv, v.unit, null, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('xc_unsold_on', 'switch', 'false'::jsonb, null::text, null::numeric, null::numeric,
   'বিক্রি না হওয়া মাল ও ছাড় / Unsold stock and markdown: on', 'Shows the end-of-day list and lets the outcome be recorded. OFF = the list and the records are refused.', 9530),
 ('xc_markdown_pct', 'number', null::jsonb, '%', 1::numeric, 90::numeric,
   'ছাড়ের শতাংশ (ফাঁকা = সেট নেই) / Markdown % (blank = not set)', 'Blank = no discount is suggested and a markdown sale is refused. Nothing is assumed.', 9531)
  ) as v(key, kind, dv, unit, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

create table if not exists public.xc_unsold_outcomes (
  id bigint generated by default as identity primary key,
  client_id uuid unique,
  location_id int not null references public.locations(id),
  item_id uuid not null references public.items(id),
  day date not null,
  qty numeric not null check (qty > 0 and qty <= 999999999),                    -- item base unit
  outcome text not null check (outcome in ('sold_discount', 'staff_meal', 'donation', 'waste')),
  discount_pct numeric check (discount_pct is null or (discount_pct > 0 and discount_pct <= 90)),
  unit_price numeric check (unit_price is null or unit_price >= 0),              -- the sell price at the time, less the markdown (sold_discount only)
  value numeric check (value is null or value >= 0),                             -- qty x unit_price (sold_discount only); other outcomes are blank, never 0
  note text check (note is null or length(note) <= 300),
  state text not null default 'active' check (state in ('active', 'void')),
  void_note text, void_by uuid, void_at timestamptz,
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  check ((outcome = 'sold_discount') = (discount_pct is not null and unit_price is not null and value is not null))
);
create index if not exists xc_unsold_outcomes_day on public.xc_unsold_outcomes (location_id, day);
alter table public.xc_unsold_outcomes enable row level security;
revoke all on public.xc_unsold_outcomes from public, anon, authenticated;
grant select on public.xc_unsold_outcomes to authenticated;
drop policy if exists xc_unsold_outcomes_read on public.xc_unsold_outcomes;
create policy xc_unsold_outcomes_read on public.xc_unsold_outcomes for select to authenticated using (public._rb4_prod_view(location_id));
drop trigger if exists audit_xc_unsold_outcomes on public.xc_unsold_outcomes;
create trigger audit_xc_unsold_outcomes after insert or update on public.xc_unsold_outcomes for each row execute function public.log_change('id');
drop trigger if exists xc_unsold_outcomes_nodel on public.xc_unsold_outcomes;
create trigger xc_unsold_outcomes_nodel before delete on public.xc_unsold_outcomes for each row execute function public.no_hard_delete();

-- the end-of-day list for a place: units left whose expiry falls before the end of the next Dhaka day
create or replace function public.xc_unsold_candidates(p_date date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_date, public._today()); pct numeric := public.rule_num('xc_markdown_pct'); cutoff timestamptz; rows_ jsonb; noexp jsonb;
begin
  if p_loc is null or not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  if not public.rule_on('xc_unsold_on') then return jsonb_build_object('skipped', 'switch_off'); end if;
  cutoff := (d + 2)::timestamp at time zone 'Asia/Dhaka';
  select coalesce(jsonb_agg(jsonb_build_object('item_id', z.item_id, 'code', z.code, 'name_en', coalesce(z.name_en, z.name_bn), 'qty_at_risk', z.qty,
           'earliest_expiry', z.first_exp, 'batches', z.nb, 'sell_price', z.sell_price,
           'markdown_pct', pct, 'markdown_price', case when pct is not null then round(z.sell_price * (1 - pct / 100), 2) end,
           'value_at_markdown', case when pct is not null then round(z.qty * z.sell_price * (1 - pct / 100), 2) end) order by z.first_exp), '[]'::jsonb)
    into rows_
    from (select sb.item_id, i.code, i.name_bn, i.name_en, sum(sb.qty_remaining) as qty, min(sb.expires_at) as first_exp, count(*) as nb, coalesce(i.sell_price, 0) as sell_price
            from public.stock_batches sb join public.items i on i.id = sb.item_id
           where sb.location_id = p_loc and sb.qty_remaining > 0 and sb.expires_at is not null and sb.expires_at < cutoff
           group by sb.item_id, i.code, i.name_bn, i.name_en, i.sell_price) z;
  select jsonb_build_object('batches', count(*), 'units', coalesce(sum(sb.qty_remaining), 0), 'items', count(distinct sb.item_id)) into noexp
    from public.stock_batches sb where sb.location_id = p_loc and sb.qty_remaining > 0 and sb.expires_at is null;
  return jsonb_build_object('date', d, 'location_id', p_loc, 'cutoff', cutoff, 'markdown_pct', pct,
    'data_needed', case when pct is null then jsonb_build_array('xc_markdown_pct') else '[]'::jsonb end,
    'rows', rows_, 'no_expiry_captured', noexp,
    'notes', jsonb_build_array('Units with no expiry date are counted apart and are NOT treated as safe or as expiring.',
      'The markdown price is a suggestion. It is taken at the till through the usual discount rules.'));
end $$;

-- the outcome of one unsold unit line (no stock movement here)
create or replace function public.xc_unsold_record(p_client uuid, p_loc int, p_item uuid, p_day date, p_qty numeric, p_outcome text,
                                                   p_discount_pct numeric default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.xc_unsold_outcomes; it public.items; pct numeric; up numeric; val numeric; nid bigint;
begin
  if not public._rb4_prod_entry(p_loc) and not public.is_owner() then raise exception 'not allowed'; end if;
  if not public.rule_on('xc_unsold_on') then raise exception 'switch_off'; end if;
  if p_client is not null then
    select * into o from public.xc_unsold_outcomes where client_id = p_client;
    if found then return jsonb_build_object('ok', true, 'id', o.id, 'duplicate', true); end if;
  end if;
  if p_outcome not in ('sold_discount', 'staff_meal', 'donation', 'waste') then raise exception 'bad_outcome'; end if;
  if p_qty is null or p_qty <= 0 or p_qty > 999999999 then raise exception 'bad_value'; end if;
  if p_day is null or p_day > public._today() + 1 or p_day < public._today() - 7 then raise exception 'bad_date'; end if;
  select * into it from public.items where id = p_item;
  if not found then raise exception 'item_not_found'; end if;
  if p_outcome = 'sold_discount' then
    pct := coalesce(p_discount_pct, public.rule_num('xc_markdown_pct'));
    if pct is null then raise exception 'markdown_pct_not_set'; end if;
    if pct <= 0 or pct > 90 then raise exception 'bad_discount'; end if;
    up := round(coalesce(it.sell_price, 0) * (1 - pct / 100), 2);
    val := round(p_qty * up, 2);
  end if;
  insert into public.xc_unsold_outcomes (client_id, location_id, item_id, day, qty, outcome, discount_pct, unit_price, value, note, created_by, created_staff)
    values (p_client, p_loc, p_item, p_day, p_qty, p_outcome, case when p_outcome = 'sold_discount' then pct end, up, val, left(nullif(btrim(p_note), ''), 300), auth.uid(),
            (select staff_id from public.profiles where id = auth.uid()))
    returning id into nid;
  return jsonb_build_object('ok', true, 'id', nid, 'duplicate', false, 'value', val,
    'note', case when p_outcome = 'waste' then 'Stock is not moved by this line: book the waste on the wastage screen.'
                 when p_outcome = 'sold_discount' then 'Stock is not moved by this line: the sale itself is recorded at the till.' else 'Stock is not moved by this line.' end);
end $$;

-- void (never delete): the line stays with the reason
create or replace function public.xc_unsold_void(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.xc_unsold_outcomes;
begin
  if nullif(btrim(p_note), '') is null then raise exception 'reason_required'; end if;
  select * into o from public.xc_unsold_outcomes where id = p_id;
  if not found then raise exception 'not_found'; end if;
  if not (public.is_owner() or (o.created_by = auth.uid() and (now() - o.created_at) < interval '1 hour' and public._rb4_prod_entry(o.location_id))) then raise exception 'not allowed'; end if;
  if o.state = 'void' then return jsonb_build_object('ok', true, 'duplicate', true); end if;
  update public.xc_unsold_outcomes set state = 'void', void_note = left(btrim(p_note), 300), void_by = auth.uid(), void_at = now() where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- the report: sold, unsold outcomes, wastage and wastage share per item and place, with the denominator shown, and a weekly trend
create or replace function public.xc_unsold_report(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, public._today() - 30); t date := coalesce(p_to, public._today()); rows_ jsonb; wk jsonb; cost_ok boolean := public.rpt_cost_ok();
begin
  if p_loc is null and not public.is_owner() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  if t < f or t - f > 400 then raise exception 'bad_range'; end if;
  with sold as (select s.location_id, (x.l ->> 'item_id')::uuid as item_id, sum((x.l ->> 'qty')::numeric) as q
                  from public.sales s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) x(l)
                 where s.status = 'done' and s.sale_date between f and t and (p_loc is null or s.location_id = p_loc)
                   and (x.l ->> 'item_id') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' and (x.l ->> 'qty') ~ '^[0-9]+(\.[0-9]+)?$'
                 group by 1, 2),
  waste as (select w.location_id, w.item_id, sum(w.qty) as q from public.stock_wastage w
             where (w.made_at at time zone 'Asia/Dhaka')::date between f and t and (p_loc is null or w.location_id = p_loc) group by 1, 2),
  outc as (select o.location_id, o.item_id, sum(o.qty) filter (where o.outcome = 'sold_discount') as disc_q, sum(o.value) filter (where o.outcome = 'sold_discount') as disc_v,
                  sum(o.qty) filter (where o.outcome = 'staff_meal') as staff_q, sum(o.qty) filter (where o.outcome = 'donation') as don_q,
                  sum(o.qty) filter (where o.outcome = 'waste') as outw_q
             from public.xc_unsold_outcomes o where o.state = 'active' and o.day between f and t and (p_loc is null or o.location_id = p_loc) group by 1, 2),
  keys as (select location_id, item_id from sold union select location_id, item_id from waste union select location_id, item_id from outc)
  select coalesce(jsonb_agg(jsonb_build_object('location_id', k.location_id, 'item_code', i.code, 'item_name', coalesce(i.name_en, i.name_bn),
      'sold_qty', coalesce(s.q, 0), 'wastage_qty', coalesce(w.q, 0),
      'wastage_share_pct', case when coalesce(s.q, 0) + coalesce(w.q, 0) > 0 then round(100 * coalesce(w.q, 0) / (coalesce(s.q, 0) + coalesce(w.q, 0)), 1) end,
      'share_denominator', coalesce(s.q, 0) + coalesce(w.q, 0),
      'markdown_sold_qty', o.disc_q, 'markdown_value', o.disc_v, 'staff_meal_qty', o.staff_q, 'donation_qty', o.don_q, 'outcome_waste_qty', o.outw_q,
      'wastage_value_at_current_avg_cost', case when cost_ok then round(coalesce(w.q, 0) * coalesce(sb.avg_cost, 0), 2) end)
      order by i.code, k.location_id), '[]'::jsonb) into rows_
    from keys k join public.items i on i.id = k.item_id
    left join sold s on s.location_id = k.location_id and s.item_id = k.item_id
    left join waste w on w.location_id = k.location_id and w.item_id = k.item_id
    left join outc o on o.location_id = k.location_id and o.item_id = k.item_id
    left join public.stock_balance sb on sb.location_id = k.location_id and sb.item_id = k.item_id;
  -- weekly trend of the wastage share for the whole selection (all items together, with its denominator)
  select coalesce(jsonb_agg(z order by z.week), '[]'::jsonb) into wk from (
    select date_trunc('week', x.day)::date as week,
           sum(x.sold) as sold, sum(x.wasted) as wasted,
           case when sum(x.sold) + sum(x.wasted) > 0 then round(100 * sum(x.wasted) / (sum(x.sold) + sum(x.wasted)), 1) end as share_pct
      from (select s.sale_date as day, sum((l.v ->> 'qty')::numeric) as sold, 0::numeric as wasted
              from public.sales s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) l(v)
             where s.status = 'done' and s.sale_date between f and t and (p_loc is null or s.location_id = p_loc)
               and (l.v ->> 'qty') ~ '^[0-9]+(\.[0-9]+)?$' group by s.sale_date
            union all
            select (w.made_at at time zone 'Asia/Dhaka')::date, 0, sum(w.qty) from public.stock_wastage w
             where (w.made_at at time zone 'Asia/Dhaka')::date between f and t and (p_loc is null or w.location_id = p_loc) group by 1) x
     group by 1) z;
  return jsonb_build_object('from', f, 'to', t, 'location_id', p_loc, 'rows', rows_, 'weekly_share', wk,
    'notes', jsonb_build_array('Wastage share = wasted / (sold + wasted); both are shown. Blank = no sales and no waste to compare.',
      'Waste value uses the current average cost, shown only to the cost right; it is not the cost at the time of waste.',
      'Outcome lines (markdown, staff meal, donation) are records; they are not stock movements.'));
end $$;

revoke all on function public.xc_unsold_candidates(date, int) from public, anon;
revoke all on function public.xc_unsold_record(uuid, int, uuid, date, numeric, text, numeric, text) from public, anon;
revoke all on function public.xc_unsold_void(bigint, text) from public, anon;
revoke all on function public.xc_unsold_report(date, date, int) from public, anon;
grant execute on function public.xc_unsold_candidates(date, int) to authenticated;
grant execute on function public.xc_unsold_record(uuid, int, uuid, date, numeric, text, numeric, text) to authenticated;
grant execute on function public.xc_unsold_void(bigint, text) to authenticated;
grant execute on function public.xc_unsold_report(date, date, int) to authenticated;

notify pgrst, 'reload schema';

-- ===================== phase498.sql =====================
-- Phase 498 (XC-5) - STAFF COACHING BOARD (OWNER ONLY): per person, the figures that already exist, side by side. No rankings, no scores, no public view.
-- Paste AFTER phase497. Paste-twice safe. Earlier phase files are not edited.
-- OFF by default: switch xc_coaching_on (false). Only the owner can read it, even when the switch is on.
-- The figures come from records that already exist: sales (sales, discounts, voids), cash shortage cases, production runs and their losses, attendance days (late minutes),
-- and complaints. A person with no record for a figure shows a blank, never 0. People are matched to a person's record by their staff id (profiles.staff_id) and by the employee link.
-- Shift and role awareness: not built in this phase (noted on the answer). The board does not judge; it lists what happened in the chosen period.
-- Reads personal data: nothing is shown to any other role, and the rows carry no rank field.

do $g$ begin
  if to_regclass('public.attendance_days') is null or to_regclass('public.shortage_cash_cases') is null or to_regclass('public.production_loss') is null then
    raise exception 'phase498 needs phases 404, 412 (attendance) and the shortage cases';
  end if;
  if to_regclass('public.crm_complaints') is null then raise exception 'phase498 needs the complaints table (CRM-H)'; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'xc', v.kind, v.dv, v.unit, null, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('xc_coaching_on', 'switch', 'false'::jsonb, null::text, null::numeric, null::numeric,
   'কর্মী পর্যালোচনা বোর্ড (শুধু মালিক) / Staff coaching board (owner only): on', 'Owner-only view of the figures that already exist per person. OFF = nothing is shown to anyone.', 9540)
  ) as v(key, kind, dv, unit, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

create or replace function public.xc_staff_board(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, public._today() - 30); t date := coalesce(p_to, public._today()); rows_ jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not public.rule_on('xc_coaching_on') then return jsonb_build_object('skipped', 'switch_off'); end if;
  if t < f or t - f > 400 then raise exception 'bad_range'; end if;
  with
  emp as (select p.staff_id, p.full_name, e.id as employee_id from public.profiles p left join public.employees e on e.profile_id = p.id where p.staff_id is not null),
  sales_ as (select s.created_staff as sid, count(*) filter (where s.status = 'done') as sales_n, sum(s.total) filter (where s.status = 'done') as sales_amt,
                    count(*) filter (where s.status = 'done' and s.discount > 0) as disc_n, sum(s.discount) filter (where s.status = 'done') as disc_amt
               from public.sales s where s.sale_date between f and t and (p_loc is null or s.location_id = p_loc) and s.created_staff is not null group by 1),
  voids as (select s.void_staff as sid, count(*) as void_n from public.sales s where s.status = 'void' and s.void_staff is not null
              and (s.void_at at time zone 'Asia/Dhaka')::date between f and t and (p_loc is null or s.location_id = p_loc) group by 1),
  cash as (select e.staff_id as sid, sum(c.amount) as short_amt, count(*) as short_n from public.shortage_cash_cases c join emp e on e.employee_id = c.employee_id
            where c.void_at is null and c.case_date between f and t and (p_loc is null or c.location_id = p_loc) group by 1),
  prod as (select pr.created_staff as sid, sum(pr.yield_base) as yield_n from (select r.*, p.staff_id as created_staff from public.production_runs r join public.profiles p on p.id = r.created_by) pr
            where pr.status = 'done' and (pr.made_at at time zone 'Asia/Dhaka')::date between f and t and (p_loc is null or pr.location_id = p_loc) group by 1),
  rej as (select pr.created_staff as sid, sum(l.qty) as reject_q from public.production_loss l join (select r.id, p.staff_id as created_staff, r.location_id, r.made_at from public.production_runs r join public.profiles p on p.id = r.created_by) pr on pr.id = l.run_id
           where l.status = 'active' and l.kind = 'reject' and (pr.made_at at time zone 'Asia/Dhaka')::date between f and t and (p_loc is null or pr.location_id = p_loc) group by 1),
  att as (select e.staff_id as sid, count(*) as days, count(*) filter (where a.late_minutes > 0) as late_days, sum(a.late_minutes) as late_min
            from public.attendance_days a join emp e on e.employee_id = a.employee_id where a.day between f and t and (p_loc is null or a.location_id = p_loc) group by 1),
  cmp as (select c.created_staff as sid, count(*) as complaints from public.crm_complaints c where c.created_at::date between f and t and (p_loc is null or c.location_id = p_loc) and c.created_staff is not null group by 1),
  people as (select sid from sales_ union select sid from voids union select sid from cash union select sid from prod union select sid from rej union select sid from att union select sid from cmp)
  select coalesce(jsonb_agg(jsonb_build_object('staff_id', pe.sid, 'name', coalesce(em.full_name, pe.sid),
      'sales_bills', sa.sales_n, 'sales_amount', round(sa.sales_amt, 2), 'discount_bills', sa.disc_n, 'discount_amount', round(sa.disc_amt, 2),
      'discount_share_pct', case when coalesce(sa.sales_n, 0) > 0 then round(100.0 * sa.disc_n / sa.sales_n, 1) end,
      'voids', v.void_n,
      'cash_shortage_cases', ca.short_n, 'cash_shortage_amount', round(ca.short_amt, 2),
      'production_yield', round(pd.yield_n, 3), 'production_reject', round(rj.reject_q, 3),
      'reject_share_pct', case when coalesce(pd.yield_n, 0) > 0 then round(100 * coalesce(rj.reject_q, 0) / pd.yield_n, 1) end,
      'attendance_days', at.days, 'late_days', at.late_days, 'late_minutes', at.late_min,
      'complaints', cm.complaints)
      order by coalesce(em.full_name, pe.sid)), '[]'::jsonb) into rows_
    from people pe
    left join emp em on em.staff_id = pe.sid
    left join sales_ sa on sa.sid = pe.sid left join voids v on v.sid = pe.sid left join cash ca on ca.sid = pe.sid
    left join prod pd on pd.sid = pe.sid left join rej rj on rj.sid = pe.sid left join att at on at.sid = pe.sid left join cmp cm on cm.sid = pe.sid;
  return jsonb_build_object('from', f, 'to', t, 'location_id', p_loc, 'rows', rows_, 'owner_only', true,
    'notes', jsonb_build_array('Owner only. Figures are for the period shown and are not a score. No ranking is shown.',
      'A blank means no record for that figure; it is not zero.', 'Shift and role are not taken into account in this version.'));
end $$;

revoke all on function public.xc_staff_board(date, date, int) from public, anon;
grant execute on function public.xc_staff_board(date, date, int) to authenticated;

notify pgrst, 'reload schema';
