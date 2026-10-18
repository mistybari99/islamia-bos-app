-- ===================== phase407.sql =====================
-- Phase 407 (bos407) - RPT-B4 / R4b: REAL CONSUMPTION VS RECIPE (#44), STANDARD VS ACTUAL COST AND THE PRICE / USAGE / YIELD VARIANCE (#33, #43, #55).
-- Paste after phase406. Paste-twice safe. Read only: nothing here moves stock or money. No earlier phase file is edited.
--
-- BASIS (said on the screen too)
--   Standard quantity   = what the production screen booked out for the run (the recipe need). It is read from the stock ledger (ref production + run id), so it is exactly what was booked.
--   Real quantity       = the record a person made with prod_actual_issue_set. Nothing is guessed: a run or ingredient without a record is "not captured" and is left out of every total.
--   Booked price        = the average cost the ledger used when the standard quantity went out (blank or 0 = unknown).
--   Standard price      = the owner's price list (item_costs). An ingredient without a list price has no price variance.
--   Standard output     = production_runs.yield_std (the recipe yield x batches). Real output = the quantity the person typed at production (yield_actual); blank = "not captured".
--   Material variance of one fully measured run (all inputs present):
--       price  = sum (booked price - standard price) x real qty
--       usage  = sum (real qty - standard qty) x standard price
--       yield  = (standard output - real output) x (sum standard qty x standard price / standard output)
--       total  = sum real qty x booked price - real output x (sum standard qty x standard price / standard output)       and  total = price + usage + yield   exactly
--   Positive = more cost than the standard (unfavourable). Each part is also given alone when only its own inputs exist. Conversion cost (labour, overhead) has no standard in the system: it is shown as booked, not split.
--   Money is shown only with the cost right (_cost_ok at the run's place); otherwise the answer says cost_hidden and gives quantities only.

do $g$ begin
  if to_regprocedure('public.rb4_dispatch_recon(date,date,int)') is null then raise exception 'phase407 needs phase406 first'; end if;
end $g$;

create or replace function public.rb4_consumption_vs_recipe(p_from date default null, p_to date default null, p_loc int default null, p_item uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; rows_ jsonb; sm jsonb; runs_n int; runs_any int; notes jsonb := '[]'::jsonb; trunc boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  select count(*), count(*) filter (where exists (select 1 from public.production_issue_actual a where a.run_id = r.id and a.status = 'active')) into runs_n, runs_any
    from public.production_runs r where r.status = 'done' and public._rb4_day(r.made_at) between f and t and (p_loc is null or r.location_id = p_loc) and (p_item is null or r.item_id = p_item) and public._rb4_prod_view(r.location_id);
  if runs_any = 0 then notes := notes || jsonb_build_object('code', 'actual_issue_not_captured', 'field', 'real use of ingredients'); end if;

  with runs as (
    select r.* from public.production_runs r where r.status = 'done' and public._rb4_day(r.made_at) between f and t and (p_loc is null or r.location_id = p_loc) and (p_item is null or r.item_id = p_item) and public._rb4_prod_view(r.location_id)
     order by r.made_at desc limit 2001),
  lines as (
    select r.id as run_id, r.made_at, r.location_id, r.item_id as fg_id, x.item_id, x.std_qty, a.actual_qty
      from runs r
      cross join lateral (select b.item_id, b.qty as std_qty from public._rb4_run_booked(r.id) b
                          union all
                          select a2.item_id, null::numeric from public.production_issue_actual a2 where a2.run_id = r.id and a2.status = 'active' and not exists (select 1 from public._rb4_run_booked(r.id) b2 where b2.item_id = a2.item_id)) x
      left join public.production_issue_actual a on a.run_id = r.id and a.item_id = x.item_id and a.status = 'active')
  select (select count(*) > 2000 from runs),
         coalesce(jsonb_agg(jsonb_build_object('run_id', l.run_id, 'day', public._rb4_day(l.made_at), 'location_id', l.location_id, 'location', lo.name_bn, 'location_en', lo.name_en,
           'fg_code', fi.code, 'fg_name_bn', fi.name_bn, 'fg_name_en', fi.name_en, 'item_id', l.item_id, 'code', ii.code, 'name_bn', ii.name_bn, 'name_en', ii.name_en, 'base_unit', public._item_base(l.item_id),
           'std_qty', l.std_qty, 'actual_qty', l.actual_qty, 'diff', case when l.std_qty is not null and l.actual_qty is not null then round(l.actual_qty - l.std_qty, 4) end,
           'diff_pct', case when l.std_qty > 0 and l.actual_qty is not null then round((l.actual_qty - l.std_qty) / l.std_qty * 100, 2) end,
           'status', case when l.std_qty is null then 'not_in_recipe' when l.actual_qty is null then 'not_captured' else 'measured' end)
           order by l.made_at desc, ii.code), '[]'::jsonb)
    into trunc, rows_
    from lines l join public.items ii on ii.id = l.item_id join public.items fi on fi.id = l.fg_id join public.locations lo on lo.id = l.location_id;

  select coalesce(jsonb_agg(jsonb_build_object('item_id', g.item_id, 'code', ii.code, 'name_bn', ii.name_bn, 'name_en', ii.name_en, 'base_unit', public._item_base(g.item_id),
        'runs_issued', g.runs_total, 'runs_measured', g.runs_measured, 'runs_not_captured', g.runs_total - g.runs_measured,
        'std_qty_measured', case when g.runs_measured > 0 then g.std_sum end, 'actual_qty_measured', case when g.runs_measured > 0 then g.act_sum end,
        'diff', case when g.runs_measured > 0 then round(g.act_sum - g.std_sum, 4) end,
        'diff_pct', case when g.runs_measured > 0 and g.std_sum > 0 then round((g.act_sum - g.std_sum) / g.std_sum * 100, 2) end) order by ii.code), '[]'::jsonb) into sm
    from (select e ->> 'item_id' as item_id_t, (e ->> 'item_id')::uuid as item_id,
                 count(*) filter (where e ->> 'status' in ('measured', 'not_captured')) as runs_total, count(*) filter (where e ->> 'status' = 'measured') as runs_measured,
                 sum((e ->> 'std_qty')::numeric) filter (where e ->> 'status' = 'measured') as std_sum, sum((e ->> 'actual_qty')::numeric) filter (where e ->> 'status' = 'measured') as act_sum
            from jsonb_array_elements(rows_) e group by 1, 2) g
    join public.items ii on ii.id = g.item_id;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'summary', sm, 'runs', runs_n, 'runs_with_real_use', runs_any, 'truncated', coalesce(trunc, false), 'notes', notes,
    'basis', 'Standard = the recipe quantity booked out by the production screen (stock ledger). Real = what a person recorded. Runs or ingredients with no record are not captured and are left out of the totals.');
end $$;

create or replace function public.rb4_cost_variance(p_from date default null, p_to date default null, p_loc int default null, p_item uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; r record; ln record; rows_ jsonb := '[]'::jsonb; lines jsonb; money boolean; hidden boolean := false; trunc boolean := false; cnt int := 0;
        n_ing int; n_sp int; n_aq int; n_ap int; extra_n int; sq_sp numeric; aq_ap numeric; aq_sp numeric; sq_ap numeric; yb numeric; ao numeric; stdunit numeric;
        pv numeric; uv numeric; yvv numeric; tv numeric; yield_ok boolean; usage_ok boolean; price_ok boolean; total_ok boolean; miss text[]; sm jsonb; ap_ numeric; notes jsonb := '[]'::jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  for r in select pr.* from public.production_runs pr where pr.status = 'done' and public._rb4_day(pr.made_at) between f and t and (p_loc is null or pr.location_id = p_loc) and (p_item is null or pr.item_id = p_item)
              and public._rb4_prod_view(pr.location_id) order by pr.made_at desc limit 501 loop
    cnt := cnt + 1;
    if cnt > 500 then trunc := true; exit; end if;
    money := public._cost_ok(r.location_id); if not money then hidden := true; end if;
    n_ing := 0; n_sp := 0; n_aq := 0; n_ap := 0; sq_sp := 0; aq_ap := 0; aq_sp := 0; sq_ap := 0; lines := '[]'::jsonb; miss := '{}';
    for ln in select b.item_id, b.qty as sq, b.unit_cost as ap, ic.cost_price as sp, a.actual_qty as aq, i.code, i.name_bn, i.name_en
                from public._rb4_run_booked(r.id) b join public.items i on i.id = b.item_id
                left join public.item_costs ic on ic.item_id = b.item_id
                left join public.production_issue_actual a on a.run_id = r.id and a.item_id = b.item_id and a.status = 'active' order by i.code loop
      ap_ := case when ln.ap is null or ln.ap <= 0 then null else ln.ap end;       -- cost 0 or blank = unknown
      n_ing := n_ing + 1;
      if ln.sp is not null then n_sp := n_sp + 1; sq_sp := sq_sp + ln.sq * ln.sp; end if;
      if ln.aq is not null then n_aq := n_aq + 1; end if;
      if ap_ is not null then n_ap := n_ap + 1; end if;
      if ln.aq is not null and ln.sp is not null then aq_sp := aq_sp + ln.aq * ln.sp; end if;
      if ln.aq is not null and ap_ is not null then aq_ap := aq_ap + ln.aq * ap_; end if;
      lines := lines || jsonb_build_object('item_id', ln.item_id, 'code', ln.code, 'name_bn', ln.name_bn, 'name_en', ln.name_en, 'std_qty', ln.sq, 'actual_qty', ln.aq,
          'booked_price', case when money then ap_ end, 'std_price', case when money then ln.sp end,
          'price_var', case when money and ln.aq is not null and ln.sp is not null and ap_ is not null then round((ap_ - ln.sp) * ln.aq, 2) end,
          'usage_var', case when money and ln.aq is not null and ln.sp is not null then round((ln.aq - ln.sq) * ln.sp, 2) end);
    end loop;
    select count(*) into extra_n from public.production_issue_actual a where a.run_id = r.id and a.status = 'active' and not exists (select 1 from public._rb4_run_booked(r.id) b where b.item_id = a.item_id);
    yb := r.yield_std; ao := r.yield_actual;
    stdunit := case when yb > 0 and n_ing > 0 and n_sp = n_ing then sq_sp / yb end;
    yield_ok := ao is not null and stdunit is not null;
    usage_ok := n_ing > 0 and n_aq = n_ing and n_sp = n_ing and extra_n = 0;
    price_ok := usage_ok and n_ap = n_ing;
    total_ok := yield_ok and price_ok;
    pv := case when price_ok then round(aq_ap - aq_sp, 2) end;
    uv := case when usage_ok then round(aq_sp - sq_sp, 2) end;
    yvv := case when yield_ok then round((yb - ao) * stdunit, 2) end;
    tv := case when total_ok then round(aq_ap - ao * stdunit, 2) end;
    if n_ing = 0 then miss := array_append(miss, 'booked ingredients'::text); end if;
    if n_aq < n_ing or extra_n > 0 then miss := array_append(miss, 'real use of ingredients'::text); end if;
    if n_sp < n_ing then miss := array_append(miss, 'standard price (price list)'::text); end if;
    if n_ap < n_ing then miss := array_append(miss, 'booked cost'::text); end if;
    if ao is null then miss := array_append(miss, 'actual yield'::text); end if;
    rows_ := rows_ || jsonb_build_object('run_id', r.id, 'day', public._rb4_day(r.made_at), 'location_id', r.location_id, 'item_id', r.item_id,
        'yield_std', r.yield_std, 'yield_actual', r.yield_actual, 'yield_var_qty', case when ao is not null and yb is not null then round(yb - ao, 4) end,
        'booked_unit_cost', case when money then r.unit_cost end, 'std_unit_cost_booked', case when money then r.std_cost end, 'material_cost', case when money then r.material_cost end,
        'conversion_cost', case when money then r.conversion_cost end, 'conversion_complete', r.conversion_complete, 'conversion_mode', r.conversion_mode,
        'std_unit_cost_list', case when money then round(stdunit, 6) end,
        'std_cost_for_real_output', case when money and total_ok then round(ao * stdunit, 2) end, 'real_material_cost', case when money and price_ok then round(aq_ap, 2) end,
        'price_var', case when money then pv end, 'usage_var', case when money then uv end, 'yield_var', case when money then yvv end, 'total_var', case when money then tv end,
        'price_var_ok', price_ok, 'usage_var_ok', usage_ok, 'yield_var_ok', yield_ok, 'measured', total_ok,
        'status', case when total_ok then 'measured' when yield_ok or usage_ok then 'partly' else 'not_measured' end, 'missing', to_jsonb(miss), 'lines', lines);
  end loop;
  -- names for the rows (kept out of the loop to keep it short)
  select coalesce(jsonb_agg(e || jsonb_build_object('location', l.name_bn, 'location_en', l.name_en, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base((e ->> 'item_id')::uuid))
         order by e ->> 'day' desc), '[]'::jsonb) into rows_
    from jsonb_array_elements(rows_) e join public.items i on i.id = (e ->> 'item_id')::uuid join public.locations l on l.id = (e ->> 'location_id')::int;
  -- summary per finished item: only runs where the part could be measured are added; the counts say how many
  select coalesce(jsonb_agg(jsonb_build_object('item_id', g.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(g.item_id),
        'runs', g.runs, 'runs_measured', g.rm, 'runs_partly', g.rp, 'runs_not_measured', g.runs - g.rm - g.rp,
        'price_var', case when g.n_price > 0 then g.s_price end, 'price_var_runs', g.n_price, 'usage_var', case when g.n_usage > 0 then g.s_usage end, 'usage_var_runs', g.n_usage,
        'yield_var', case when g.n_yield > 0 then g.s_yield end, 'yield_var_runs', g.n_yield,
        'total_var', case when g.rm > 0 then g.s_total end, 'std_cost_for_real_output', case when g.rm > 0 then g.s_std end, 'real_material_cost', case when g.rm > 0 then g.s_real end,
        'total_var_pct', case when g.rm > 0 and g.s_std > 0 then round(g.s_total / g.s_std * 100, 2) end) order by i.code), '[]'::jsonb) into sm
    from (select (e ->> 'item_id')::uuid as item_id, count(*) as runs, count(*) filter (where e ->> 'status' = 'measured') as rm, count(*) filter (where e ->> 'status' = 'partly') as rp,
                 count(*) filter (where (e ->> 'price_var_ok')::boolean) as n_price, sum((e ->> 'price_var')::numeric) filter (where (e ->> 'price_var_ok')::boolean) as s_price,
                 count(*) filter (where (e ->> 'usage_var_ok')::boolean) as n_usage, sum((e ->> 'usage_var')::numeric) filter (where (e ->> 'usage_var_ok')::boolean) as s_usage,
                 count(*) filter (where (e ->> 'yield_var_ok')::boolean) as n_yield, sum((e ->> 'yield_var')::numeric) filter (where (e ->> 'yield_var_ok')::boolean) as s_yield,
                 sum((e ->> 'total_var')::numeric) filter (where (e ->> 'measured')::boolean) as s_total, sum((e ->> 'std_cost_for_real_output')::numeric) filter (where (e ->> 'measured')::boolean) as s_std,
                 sum((e ->> 'real_material_cost')::numeric) filter (where (e ->> 'measured')::boolean) as s_real
            from jsonb_array_elements(rows_) e group by 1) g join public.items i on i.id = g.item_id;
  if jsonb_array_length(rows_) > 0 and not exists (select 1 from jsonb_array_elements(rows_) e where e ->> 'status' = 'measured') then
    notes := notes || jsonb_build_object('code', 'no_run_fully_measured', 'field', 'real use of ingredients, standard price, actual yield');
  end if;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'summary', sm, 'cost_hidden', hidden, 'truncated', trunc, 'notes', notes,
    'basis', 'Standard price = the owner price list (item_costs). Booked price = the average cost the ledger used for the run. Positive variance = more cost than the standard. Conversion cost has no standard and is not split. A part is shown only when all of its inputs were captured.');
end $$;

do $p$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('rb4_consumption_vs_recipe', 'rb4_cost_variance') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $p$;

notify pgrst, 'reload schema';

-- ===================== phase408.sql =====================
-- Phase 408 (bos408) - RPT-B4 / R4c: RUN-LEVEL YIELD VS STANDARD (#45), REJECT / REWORK / PRODUCTION LOSS (#49), WASTAGE WITH THE BATCH AND PRODUCTION-RUN DIMENSION (#50).
-- Paste after phase407. Paste-twice safe. Read only: nothing here moves stock or money. No earlier phase file is edited.
--
--   rb4_run_yield(from, to, place, item)         one row per finished run: standard output, the output the person typed (blank = "not captured"), the difference and %, and the owner's warning limit
--                                                (rule yield_variance_warn_pct; blank limit = no flag, said in words). Another package may also list the same runs; the numbers come from production_runs only.
--   rb4_losses(from, to, place, item)            reject / rework per run (prod_loss_add): the run's state is recorded / checked-none / not captured. Percentages use only runs whose state is known.
--   rb4_wastage_dim(from, to, place, item)       the wastage records with the batch they were taken from and, when that batch was made by a production run, the run; by reason, item and batch.
--                                                Value = quantity x the ledger cost of the write-off, shown only with the cost right and only where the cost is known.

do $g$ begin
  if to_regprocedure('public.rb4_cost_variance(date,date,int,uuid)') is null then raise exception 'phase408 needs phase407 first'; end if;
end $g$;

create or replace function public.rb4_run_yield(p_from date default null, p_to date default null, p_loc int default null, p_item uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; thr numeric := public.rule_num('yield_variance_warn_pct'); rows_ jsonb; sm jsonb; trunc boolean; notes jsonb := '[]'::jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  with runs as (
    select r.* from public.production_runs r where r.status = 'done' and public._rb4_day(r.made_at) between f and t and (p_loc is null or r.location_id = p_loc) and (p_item is null or r.item_id = p_item) and public._rb4_prod_view(r.location_id)
     order by r.made_at desc limit 2001)
  select (select count(*) > 2000 from runs),
         coalesce(jsonb_agg(jsonb_build_object('run_id', r.id, 'day', public._rb4_day(r.made_at), 'location_id', r.location_id, 'location', l.name_bn, 'location_en', l.name_en,
           'item_id', r.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(r.item_id), 'batches', r.batches,
           'yield_std', r.yield_std, 'yield_actual', r.yield_actual, 'booked_output', r.yield_base,
           'var_qty', case when r.yield_actual is not null and r.yield_std is not null then round(r.yield_actual - r.yield_std, 4) end,
           'var_pct', case when r.yield_actual is not null and r.yield_std > 0 then round((r.yield_actual - r.yield_std) / r.yield_std * 100, 2) end,
           'status', case when r.yield_std is null then 'standard_not_captured' when r.yield_actual is null then 'not_captured' else 'measured' end,
           'over_limit', case when thr is not null and r.yield_actual is not null and r.yield_std > 0 then abs((r.yield_actual - r.yield_std) / r.yield_std * 100) > thr end) order by r.made_at desc), '[]'::jsonb)
    into trunc, rows_
    from (select * from runs limit 2000) r join public.items i on i.id = r.item_id join public.locations l on l.id = r.location_id;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', g.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(g.item_id),
        'runs', g.runs, 'measured', g.m, 'not_captured', g.runs - g.m, 'std_qty_measured', case when g.m > 0 then g.s_std end, 'actual_qty_measured', case when g.m > 0 then g.s_act end,
        'var_pct', case when g.m > 0 and g.s_std > 0 then round((g.s_act - g.s_std) / g.s_std * 100, 2) end, 'over_limit_runs', case when thr is not null then g.over end) order by i.code), '[]'::jsonb) into sm
    from (select (e ->> 'item_id')::uuid as item_id, count(*) as runs, count(*) filter (where e ->> 'status' = 'measured') as m,
                 sum((e ->> 'yield_std')::numeric) filter (where e ->> 'status' = 'measured') as s_std, sum((e ->> 'yield_actual')::numeric) filter (where e ->> 'status' = 'measured') as s_act,
                 count(*) filter (where (e ->> 'over_limit')::boolean) as over
            from jsonb_array_elements(rows_) e group by 1) g join public.items i on i.id = g.item_id;
  if thr is null then notes := notes || jsonb_build_object('code', 'limit_not_set', 'field', 'yield_variance_warn_pct'); end if;
  if jsonb_array_length(rows_) > 0 and not exists (select 1 from jsonb_array_elements(rows_) e where e ->> 'status' = 'measured') then notes := notes || jsonb_build_object('code', 'actual_yield_not_captured', 'field', 'actual yield'); end if;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'summary', sm, 'limit_pct', thr, 'truncated', coalesce(trunc, false), 'notes', notes);
end $$;

create or replace function public.rb4_losses(p_from date default null, p_to date default null, p_loc int default null, p_item uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; rows_ jsonb; reasons jsonb; sm jsonb; items_ jsonb; trunc boolean; notes jsonb := '[]'::jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  with runs as (
    select r.* from public.production_runs r where r.status = 'done' and public._rb4_day(r.made_at) between f and t and (p_loc is null or r.location_id = p_loc) and (p_item is null or r.item_id = p_item) and public._rb4_prod_view(r.location_id)
     order by r.made_at desc limit 2001),
  agg as (
    select r.id, coalesce(sum(x.qty) filter (where x.kind = 'reject'), 0) as rej, coalesce(sum(x.qty) filter (where x.kind = 'rework'), 0) as rew,
           count(*) filter (where x.kind in ('reject', 'rework')) as recorded_n, count(*) filter (where x.kind = 'none') as none_n,
           coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'kind', x.kind, 'qty', x.qty, 'reason_code', x.reason_code, 'reason', o.label_en, 'reason_bn', o.label_bn, 'note', x.note) order by x.created_at) filter (where x.kind in ('reject', 'rework')), '[]'::jsonb) as lines
      from runs r left join public.production_loss x on x.run_id = r.id and x.status = 'active'
      left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = x.reason_code group by r.id)
  select (select count(*) > 2000 from runs),
         coalesce(jsonb_agg(jsonb_build_object('run_id', r.id, 'day', public._rb4_day(r.made_at), 'location_id', r.location_id, 'location', l.name_bn, 'location_en', l.name_en,
           'item_id', r.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(r.item_id), 'output', r.yield_base,
           'state', case when a.recorded_n > 0 then 'recorded' when a.none_n > 0 then 'none' else 'not_captured' end,
           'reject_qty', case when a.recorded_n > 0 or a.none_n > 0 then a.rej end, 'rework_qty', case when a.recorded_n > 0 or a.none_n > 0 then a.rew end,
           'reject_pct', case when (a.recorded_n > 0 or a.none_n > 0) and r.yield_base > 0 then round(a.rej / r.yield_base * 100, 2) end,
           'rework_pct', case when (a.recorded_n > 0 or a.none_n > 0) and r.yield_base > 0 then round(a.rew / r.yield_base * 100, 2) end, 'lines', a.lines) order by r.made_at desc), '[]'::jsonb)
    into trunc, rows_
    from (select * from runs limit 2000) r join agg a on a.id = r.id join public.items i on i.id = r.item_id join public.locations l on l.id = r.location_id;

  select coalesce(jsonb_agg(jsonb_build_object('reason_code', z.rc, 'reason', o.label_en, 'reason_bn', o.label_bn, 'reject_n', z.rn, 'rework_n', z.wn) order by z.rn + z.wn desc, z.rc), '[]'::jsonb) into reasons
    from (select l ->> 'reason_code' as rc, count(*) filter (where l ->> 'kind' = 'reject') as rn, count(*) filter (where l ->> 'kind' = 'rework') as wn
            from jsonb_array_elements(rows_) e, jsonb_array_elements(e -> 'lines') l group by 1) z left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = z.rc;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', g.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(g.item_id),
        'runs', g.runs, 'runs_known', g.known, 'runs_not_captured', g.runs - g.known, 'output_known', case when g.known > 0 then g.out_k end, 'reject_qty', case when g.known > 0 then g.rej end, 'rework_qty', case when g.known > 0 then g.rew end,
        'reject_pct', case when g.known > 0 and g.out_k > 0 then round(g.rej / g.out_k * 100, 2) end, 'rework_pct', case when g.known > 0 and g.out_k > 0 then round(g.rew / g.out_k * 100, 2) end) order by i.code), '[]'::jsonb) into items_
    from (select (e ->> 'item_id')::uuid as item_id, count(*) as runs, count(*) filter (where e ->> 'state' <> 'not_captured') as known,
                 sum((e ->> 'output')::numeric) filter (where e ->> 'state' <> 'not_captured') as out_k, sum((e ->> 'reject_qty')::numeric) filter (where e ->> 'state' <> 'not_captured') as rej,
                 sum((e ->> 'rework_qty')::numeric) filter (where e ->> 'state' <> 'not_captured') as rew
            from jsonb_array_elements(rows_) e group by 1) g join public.items i on i.id = g.item_id;
  select jsonb_build_object('runs', jsonb_array_length(rows_), 'recorded', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'state' = 'recorded'),
      'none', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'state' = 'none'), 'not_captured', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'state' = 'not_captured')) into sm;
  if (sm ->> 'runs')::int > 0 and (sm ->> 'recorded')::int + (sm ->> 'none')::int = 0 then notes := notes || jsonb_build_object('code', 'loss_not_captured', 'field', 'reject and rework'); end if;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'by_reason', reasons, 'by_item', items_, 'summary', sm, 'truncated', coalesce(trunc, false), 'notes', notes,
    'basis', 'A reject or rework is a record, not a stock movement: the output of the run is as booked. Percentages use only runs whose state is known (recorded, or checked and none). Stock written off is in the wastage report.');
end $$;

create or replace function public.rb4_wastage_dim(p_from date default null, p_to date default null, p_loc int default null, p_item uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; rows_ jsonb; by_reason jsonb; by_item jsonb; by_batch jsonb; trunc boolean; hidden boolean := false; sm jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  select exists (select 1 from public.stock_wastage w where public._rb4_day(w.made_at) between f and t and (p_loc is null or w.location_id = p_loc) and public._rb4_prod_view(w.location_id) and not public._cost_ok(w.location_id)) into hidden;
  with w as (
    select w.*, b.made_at as batch_made, b.qty_made as batch_qty, r.id as run_id, public._cost_ok(w.location_id) as money,
           case when lg.unit_cost is not null and lg.unit_cost > 0 then lg.unit_cost end as ucost
      from public.stock_wastage w
      left join public.stock_batches b on b.id = w.batch_id
      left join public.production_runs r on r.batch_id = w.batch_id and r.status = 'done'
      left join public.stock_ledger lg on lg.id = w.ledger_id
     where public._rb4_day(w.made_at) between f and t and (p_loc is null or w.location_id = p_loc) and (p_item is null or w.item_id = p_item) and public._rb4_prod_view(w.location_id)
     order by w.made_at desc limit 2001)
  select (select count(*) > 2000 from w),
         coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'day', public._rb4_day(x.made_at), 'location_id', x.location_id, 'location', l.name_bn, 'location_en', l.name_en,
           'item_id', x.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(x.item_id), 'qty', x.qty,
           'reason_code', x.reason_code, 'reason', o.label_en, 'reason_bn', o.label_bn,
           'batch_id', x.batch_id, 'batch_made_at', x.batch_made, 'run_id', x.run_id, 'batch_state', case when x.batch_id is null then 'batch_not_captured' when x.run_id is null then 'not_from_a_run' else 'from_run' end,
           'value', case when x.money and x.ucost is not null then round(x.qty * x.ucost, 2) end, 'value_state', case when not x.money then 'cost_hidden' when x.ucost is null then 'cost_not_captured' else 'known' end,
           'note', x.note, 'created_staff', x.created_staff) order by x.made_at desc), '[]'::jsonb)
    into trunc, rows_
    from (select * from w limit 2000) x join public.items i on i.id = x.item_id join public.locations l on l.id = x.location_id left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = x.reason_code;

  select coalesce(jsonb_agg(jsonb_build_object('reason_code', g.rc, 'reason', o.label_en, 'reason_bn', o.label_bn, 'records', g.n, 'value', case when g.vk > 0 then g.v end, 'value_known_n', g.vk, 'value_not_known_n', g.n - g.vk) order by g.n desc, g.rc), '[]'::jsonb) into by_reason
    from (select e ->> 'reason_code' as rc, count(*) as n, count(*) filter (where e ->> 'value_state' = 'known') as vk, sum((e ->> 'value')::numeric) as v from jsonb_array_elements(rows_) e group by 1) g
    left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = g.rc;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', g.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(g.item_id), 'records', g.n, 'qty', g.q,
        'value', case when g.vk > 0 then g.v end, 'value_known_n', g.vk, 'value_not_known_n', g.n - g.vk) order by i.code), '[]'::jsonb) into by_item
    from (select (e ->> 'item_id')::uuid as item_id, count(*) as n, sum((e ->> 'qty')::numeric) as q, count(*) filter (where e ->> 'value_state' = 'known') as vk, sum((e ->> 'value')::numeric) as v from jsonb_array_elements(rows_) e group by 1) g
    join public.items i on i.id = g.item_id;
  select coalesce(jsonb_agg(jsonb_build_object('batch_id', g.bid, 'run_id', g.rid, 'batch_made_at', g.bm, 'item_id', g.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(g.item_id),
        'records', g.n, 'qty', g.q, 'value', case when g.vk > 0 then g.v end, 'value_not_known_n', g.n - g.vk) order by g.bm desc nulls last), '[]'::jsonb) into by_batch
    from (select (e ->> 'batch_id')::bigint as bid, (e ->> 'run_id')::uuid as rid, (e ->> 'batch_made_at')::timestamptz as bm, (e ->> 'item_id')::uuid as item_id, count(*) as n, sum((e ->> 'qty')::numeric) as q,
                 count(*) filter (where e ->> 'value_state' = 'known') as vk, sum((e ->> 'value')::numeric) as v
            from jsonb_array_elements(rows_) e where e ->> 'batch_id' is not null group by 1, 2, 3, 4) g join public.items i on i.id = g.item_id;
  select jsonb_build_object('records', jsonb_array_length(rows_), 'batch_not_captured', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'batch_state' = 'batch_not_captured'),
      'from_run', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'batch_state' = 'from_run'),
      'value_known_n', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'value_state' = 'known'),
      'value', (select sum((e ->> 'value')::numeric) from jsonb_array_elements(rows_) e where e ->> 'value_state' = 'known')) into sm;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'by_reason', by_reason, 'by_item', by_item, 'by_batch', by_batch, 'summary', sm, 'cost_hidden', hidden, 'truncated', coalesce(trunc, false),
    'basis', 'Quantity is never added across different items. A value is shown only where the ledger cost of the write-off is known and the reader has the cost right; the others are counted as not known, never as 0.');
end $$;

do $p$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('rb4_run_yield', 'rb4_losses', 'rb4_wastage_dim') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $p$;

notify pgrst, 'reload schema';

-- ===================== phase409.sql =====================
-- Phase 409 (bos409) - RPT-B4 / R5a: SALES TARGETS AND DAILY KPI SNAPSHOTS, TABLES, SETTINGS AND TARGET ENTRY.
-- Paste after phase404 (it uses the helpers _rb4_today / _rb4_range; phases 405-408 are not needed by this file). Paste-twice safe. No earlier phase file is edited; no shared function is re-created.
-- Requirements: docs/REPORTS_AUDIT_1.md items #9, #24 (target vs achievement) and #10 (KPI trends and exception alerts).
--
-- WHAT THIS ADDS
--   sales_targets   the owner's target per outlet and month: an amount, and optionally a gross-profit %. A change retires the old line and writes a new one (history kept). No target = "target not set".
--   kpi_snapshots   one row per day, place and measure (phase 410 fills it); only additive measures are stored, ratios are worked out when read.
--   grant sales_target_manage   who may set targets. By default NOBODY but the owner holds it (the owner can hand it to a role in the permission matrix).
--   settings (all blank = off): kpi_alert_sales_drop_pct, kpi_alert_discount_pct, kpi_alert_void_n. No limit is invented: a blank limit means no alert of that kind, and the screen says so.
-- Nothing here moves stock or money. Paper form code of the target entry screen: to be given by owner.

do $g$ begin
  if to_regclass('public.sales') is null or to_regclass('public.sale_returns') is null then raise exception 'phase409 needs the sales phases'; end if;
  if to_regprocedure('public.log_change()') is null then raise exception 'phase409 needs log_change'; end if;
  if to_regprocedure('public._rb4_today()') is null then raise exception 'phase409 needs phase404 first'; end if;
end $g$;

-- ---------- grant (nobody holds it by default except the owner, who always may) ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('sales_target_manage', 'reports', 70, 'বিক্রির লক্ষ্য ঠিক করা', 'Sales target ঠিক করা', 'Set sales targets', 'once', null)
on conflict (grant_code) do nothing;

-- ---------- settings (blank = no alert of that kind) ----------
insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('kpi_alert_sales_drop_pct', 'reports', 'number', null, null, 0, 100,
  'দিনের বিক্রি আগের ৪টি একই বারের গড়ের চেয়ে এর বেশি % কম হলে সতর্কতা', 'Day''s sales এর চেয়ে বেশি % কম হলে সতর্কতা (আগের ৪টি একই বারের গড়ের তুলনায়)',
  'Alert when a day''s sales are lower than the average of the previous 4 same weekdays by more than this %',
  'Blank = no sales-drop alert. Needs at least 2 earlier snapshot days of the same weekday; with fewer the screen says "not enough history". Display only: it changes nothing.', 7001),
 ('kpi_alert_discount_pct', 'reports', 'number', null, null, 0, 100,
  'দিনের ডিসকাউন্ট বিক্রির (ডিসকাউন্টের আগে) এর বেশি % হলে সতর্কতা', 'Day''s discount এর বেশি % হলে সতর্কতা (ডিসকাউন্টের আগের বিক্রির)',
  'Alert when a day''s discount is more than this % of the sales before discount',
  'Blank = no discount alert. Display only.', 7002),
 ('kpi_alert_void_n', 'reports', 'number', null, null, 0, 100000,
  'এক দিনে এর বেশি বাতিল বিক্রি হলে সতর্কতা', 'এক দিনে এর বেশি void sale হলে সতর্কতা',
  'Alert when a place has more than this many voided sales in one day',
  'Blank = no void alert. Display only.', 7003)
on conflict (key) do nothing;

-- ---------- tables ----------
create table if not exists public.sales_targets (
  id bigserial primary key,
  location_id int not null references public.locations(id),
  month date not null check (extract(day from month) = 1),          -- the first day of the month
  amount numeric not null check (amount >= 0 and amount <= 1000000000000),
  gp_pct numeric check (gp_pct is null or (gp_pct >= 0 and gp_pct <= 100)),
  note text check (note is null or length(note) <= 300),
  status text not null default 'active' check (status in ('active', 'retired')),
  retired_note text, retired_by uuid, retired_at timestamptz,
  created_by uuid, created_staff text, created_at timestamptz not null default now()
);
create unique index if not exists sales_targets_one_active on public.sales_targets (location_id, month) where status = 'active';
create index if not exists sales_targets_month on public.sales_targets (month, location_id);

create table if not exists public.kpi_snapshots (
  snap_date date not null,
  location_id int not null references public.locations(id),
  kpi text not null check (kpi ~ '^[a-z0-9_]{2,40}$'),
  value numeric,                                                       -- blank = could not be worked out (never 0)
  computed_at timestamptz not null default now(),
  computed_by uuid,
  primary key (snap_date, location_id, kpi)
);
create index if not exists kpi_snapshots_loc on public.kpi_snapshots (location_id, snap_date);

drop trigger if exists audit_sales_targets on public.sales_targets;
create trigger audit_sales_targets after insert or update on public.sales_targets for each row execute function public.log_change('id');
alter table public.sales_targets enable row level security;
alter table public.kpi_snapshots enable row level security;
revoke all on public.sales_targets, public.kpi_snapshots from public, anon, authenticated;
revoke all on sequence public.sales_targets_id_seq from public, anon, authenticated;

-- ---------- who may read / write ----------
-- reading targets and KPIs: the owner or the sales report right (rpt_access('sales') also covers view_reports), and the place must be theirs
create or replace function public._rb4_target_view(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and public.can_loc(p_loc) and (public.is_owner() or public.rpt_access('sales') or public.has_grant('report_pos', p_loc));
$$;
create or replace function public._rb4_target_edit() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('sales_target_manage'));
$$;
drop policy if exists sales_targets_read on public.sales_targets;
create policy sales_targets_read on public.sales_targets for select to authenticated using (public._rb4_target_view(location_id));
drop policy if exists kpi_snapshots_read on public.kpi_snapshots;
create policy kpi_snapshots_read on public.kpi_snapshots for select to authenticated using (public._rb4_target_view(location_id));
grant select on public.sales_targets, public.kpi_snapshots to authenticated;

-- ---------- target entry ----------
-- p_month = any day of the month (the first of that month is stored). A second call for the same place + month retires the old line (kept as history) and writes the new one.
create or replace function public.sales_target_set(p_loc int, p_month date, p_amount numeric, p_gp_pct numeric default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m date; sid text; id_ bigint; old public.sales_targets; n text := nullif(btrim(p_note), '');
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public._rb4_target_edit() then raise exception 'not allowed'; end if;
  if p_loc is null or not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if p_month is null then raise exception 'bad_date'; end if;
  m := date_trunc('month', p_month)::date;
  if abs(m - public._rb4_today()) > 800 then raise exception 'bad_date'; end if;
  if p_amount is null or not (p_amount >= 0 and p_amount <= 1000000000000) then raise exception 'bad_amount'; end if;
  if p_gp_pct is not null and not (p_gp_pct >= 0 and p_gp_pct <= 100) then raise exception 'bad_gp_pct'; end if;
  if n is not null and length(n) > 300 then raise exception 'bad_note'; end if;
  select * into old from public.sales_targets where location_id = p_loc and month = m and status = 'active' for update;
  if found and old.amount = p_amount and old.gp_pct is not distinct from p_gp_pct then return jsonb_build_object('dup', true, 'id', old.id); end if;
  if found then
    update public.sales_targets set status = 'retired', retired_note = 'replaced by a new target', retired_by = auth.uid(), retired_at = now() where id = old.id;
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.sales_targets (location_id, month, amount, gp_pct, note, created_by, created_staff) values (p_loc, m, p_amount, p_gp_pct, n, auth.uid(), sid) returning id into id_;
  return jsonb_build_object('id', id_, 'month', m, 'replaced', old.id);
end $$;

create or replace function public.sales_target_retire(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.sales_targets;
begin
  if not public._rb4_target_edit() then raise exception 'not allowed'; end if;
  select * into r from public.sales_targets where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(r.location_id) then raise exception 'not allowed'; end if;
  if r.status = 'retired' then return jsonb_build_object('dup', true, 'status', 'retired'); end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.sales_targets set status = 'retired', retired_note = left(btrim(p_note), 300), retired_by = auth.uid(), retired_at = now() where id = p_id;
  return jsonb_build_object('status', 'retired');
end $$;

create or replace function public.sales_target_list(p_from date default null, p_to date default null, p_loc int default null, p_with_retired boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := date_trunc('month', coalesce(p_from, public._rb4_today()))::date; t date := date_trunc('month', coalesce(p_to, public._rb4_today() + 62))::date;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public._rb4_target_view(p_loc) then raise exception 'not allowed'; end if;
  return jsonb_build_object('from', f, 'to', t, 'can_edit', public._rb4_target_edit(), 'rows', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'location_id', s.location_id, 'location', l.name_bn, 'location_en', l.name_en,
      'month', s.month, 'amount', s.amount, 'gp_pct', s.gp_pct, 'note', s.note, 'status', s.status, 'retired_note', s.retired_note, 'created_staff', s.created_staff, 'created_at', s.created_at)
      order by s.month, l.sort, s.id)
    from public.sales_targets s join public.locations l on l.id = s.location_id
   where s.month between f and t and (p_loc is null or s.location_id = p_loc) and public._rb4_target_view(s.location_id) and (coalesce(p_with_retired, false) or s.status = 'active')), '[]'::jsonb));
end $$;

-- ---------- privileges ----------
do $p$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_rb4_target_view', '_rb4_target_edit') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);      -- used by the row-level-security policies
  end loop;
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('sales_target_set', 'sales_target_retire', 'sales_target_list') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $p$;

notify pgrst, 'reload schema';

-- ===================== phase410.sql =====================
-- Phase 410 (bos410) - RPT-B4 / R5b: TARGET VS ACHIEVEMENT (#9, #24), DAILY KPI SNAPSHOTS, KPI TRENDS AND EXCEPTION ALERTS (#10).
-- Paste after phase409. Paste-twice safe. No earlier phase file is edited. Reads existing sales data; writes only kpi_snapshots (a copy of already recorded figures).
--
--   rb4_target_report(from_month, to_month, place)   per place and month: target, achieved (net of returns while the rule reports_net_of_returns is on, same basis as the dashboard),
--                                                    pace (the share of the month gone, today counted), status, and the gross-profit % against its target when the reader has the cost right.
--   kpi_snapshot_take(from, to, redo)                keeps one row per closed day, place and measure. Idempotent: an existing day is left alone unless redo (owner / target manager) asks.
--                                                    Who: the owner, the sales report right, or the scheduler account that already runs notify_scan (select kpi_snapshot_take() after it).
--   rb4_kpi_trend(from, to, place)                   the daily series from the snapshots (days without a snapshot are listed as missing, never drawn as 0), and the alerts of the three owner limits.
-- Alerts are display only. A blank limit means no alert of that kind and the answer says so. Nothing is moved or posted.

do $g$ begin
  if to_regclass('public.kpi_snapshots') is null then raise exception 'phase410 needs phase409 first'; end if;
end $g$;

-- per day and place: what was sold, discounted, voided and returned (the raw material of both the target report and the snapshots)
create or replace function public._rb4_sales_days(f date, t date, locs int[]) returns table (d date, loc int, gross numeric, subtotal numeric, discount numeric, bills bigint, void_n bigint, void_amt numeric, returns_amt numeric)
language sql stable security definer set search_path = public as $$
  with s as (
    select x.sale_date as d, x.location_id as loc, sum(x.total) filter (where x.status = 'done') as gross, sum(x.subtotal) filter (where x.status = 'done') as subtotal, sum(x.discount) filter (where x.status = 'done') as discount,
           count(*) filter (where x.status = 'done') as bills, count(*) filter (where x.status = 'void') as void_n, sum(x.total) filter (where x.status = 'void') as void_amt
      from public.sales x where x.sale_date between f and t and x.location_id = any (locs) group by 1, 2),
  r as (
    select (c.created_at at time zone 'Asia/Dhaka')::date as d, c.location_id as loc, sum(c.amount) as returns_amt
      from public.sale_returns c where c.status = 'done' and (c.created_at at time zone 'Asia/Dhaka')::date between f and t and c.location_id = any (locs) group by 1, 2)
  select coalesce(s.d, r.d), coalesce(s.loc, r.loc), coalesce(s.gross, 0), coalesce(s.subtotal, 0), coalesce(s.discount, 0), coalesce(s.bills, 0), coalesce(s.void_n, 0), coalesce(s.void_amt, 0), coalesce(r.returns_amt, 0)
    from s full join r on s.d = r.d and s.loc = r.loc;
$$;

create or replace function public.rb4_target_report(p_from_month date default null, p_to_month date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := date_trunc('month', coalesce(p_from_month, public._rb4_today()))::date; t date := date_trunc('month', coalesce(p_to_month, public._rb4_today()))::date; td date := public._rb4_today();
        net_on boolean := coalesce(public.rule_on('reports_net_of_returns'), true); locs int[]; costlocs int[]; rows_ jsonb; sm jsonb; notes jsonb := '[]'::jsonb; tend date;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public._rb4_target_view(p_loc) then raise exception 'not allowed'; end if;
  select coalesce(array_agg(l.id), '{}') into locs from public.locations l where (p_loc is null or l.id = p_loc) and public._rb4_target_view(l.id);
  select coalesce(array_agg(l.id), '{}') into costlocs from public.locations l where l.id = any (locs) and public._cost_ok(l.id);
  tend := least((t + interval '1 month')::date - 1, td);
  with sd as (select date_trunc('month', x.d)::date as m, x.loc, sum(x.gross) as gross, sum(x.returns_amt) as ret, sum(x.bills) as bills from public._rb4_sales_days(f, greatest(tend, f), locs) x group by 1, 2),
  cg as (select date_trunc('month', h.d)::date as m, h.loc, sum((case h.src when 'sale' then 1 else -1 end) * (h.led_rev + h.fb_rev)) as crev, sum((case h.src when 'sale' then 1 else -1 end) * (h.led_cogs + h.fb_cogs)) as cogs,
                sum((case h.src when 'sale' then 1 else -1 end) * h.unk_rev) as unk
           from public._cogs_lines72(f, greatest(tend, f), costlocs) h group by 1, 2),
  tg as (select s.* from public.sales_targets s where s.status = 'active' and s.month between f and t and s.location_id = any (locs)),
  keys as (select tg.month as m, tg.location_id as loc from tg union select sd.m, sd.loc from sd where sd.gross <> 0 or sd.ret <> 0),
  z as (
    select k.m, k.loc, tg.id as tid, tg.amount as target, tg.gp_pct as gp_target, coalesce(sd.gross, 0) as gross, coalesce(sd.ret, 0) as ret, coalesce(sd.bills, 0) as bills,
           coalesce(sd.gross, 0) - case when net_on then coalesce(sd.ret, 0) else 0 end as achieved,
           extract(day from (k.m + interval '1 month' - interval '1 day'))::int as dim,
           least(extract(day from (k.m + interval '1 month' - interval '1 day'))::int, greatest(0, td - k.m + 1)) as elapsed,
           cg.crev, cg.cogs, cg.unk, k.loc = any (costlocs) as money
      from keys k left join tg on tg.month = k.m and tg.location_id = k.loc left join sd on sd.m = k.m and sd.loc = k.loc left join cg on cg.m = k.m and cg.loc = k.loc)
  select coalesce(jsonb_agg(jsonb_build_object('month', z.m, 'location_id', z.loc, 'location', l.name_bn, 'location_en', l.name_en, 'target_id', z.tid,
      'target', z.target, 'achieved', round(z.achieved, 2), 'gross_sales', z.gross, 'returns', z.ret, 'bills', z.bills,
      'achievement_pct', case when z.target > 0 then round(z.achieved / z.target * 100, 1) end, 'shortfall', case when z.target is not null then round(greatest(z.target - z.achieved, 0), 2) end,
      'days_in_month', z.dim, 'days_elapsed', z.elapsed, 'pace_pct', case when z.target is not null then round(z.elapsed::numeric / z.dim * 100, 1) end,
      'pace_amount', case when z.target is not null then round(z.target * z.elapsed / z.dim, 2) end,
      'status', case when z.target is null then 'target_not_set' when z.m > td then 'not_started'
                     when (z.m + interval '1 month')::date <= td then case when z.achieved >= z.target then 'closed_met' else 'closed_missed' end
                     when z.achieved >= z.target then 'met' when z.achieved >= z.target * z.elapsed / z.dim then 'on_track' else 'behind' end,
      'gp_target_pct', z.gp_target,
      'gp_pct', case when z.money and z.crev > 0 then round((z.crev - z.cogs) / z.crev * 100, 2) end,
      'gp_gap_pp', case when z.money and z.crev > 0 and z.gp_target is not null then round((z.crev - z.cogs) / z.crev * 100 - z.gp_target, 2) end,
      'uncosted_pct', case when z.money and z.crev + coalesce(z.unk, 0) > 0 then round(coalesce(z.unk, 0) / (z.crev + coalesce(z.unk, 0)) * 100, 1) end,
      'gp_state', case when not z.money then 'cost_hidden' when z.crev is null or z.crev <= 0 then 'cost_not_captured' when z.gp_target is null then 'gp_target_not_set' else 'known' end) order by z.m desc, l.sort, z.loc), '[]'::jsonb)
    into rows_
    from z join public.locations l on l.id = z.loc;
  select jsonb_build_object('rows_with_target', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'target_id' is not null),
      'rows_without_target', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'target_id' is null),
      'target_total', (select sum((e ->> 'target')::numeric) from jsonb_array_elements(rows_) e where e ->> 'target_id' is not null),
      'achieved_total_for_targets', (select sum((e ->> 'achieved')::numeric) from jsonb_array_elements(rows_) e where e ->> 'target_id' is not null),
      'behind', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'status' in ('behind', 'closed_missed')),
      'costs_hidden', exists (select 1 from public.locations l where l.id = any (locs) and not public._cost_ok(l.id))) into sm;
  if (sm ->> 'rows_with_target')::int = 0 then notes := notes || jsonb_build_object('code', 'target_not_set', 'field', 'sales target'); end if;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'summary', sm, 'net_of_returns', net_on, 'notes', notes,
    'basis', 'Achieved = sales of the month that are done, less sale returns (while the rule reports_net_of_returns is on); the same basis as the dashboard. Pace = the share of the month that has passed (today counted) times the target. GP % is on the part of the sales whose cost is known.');
end $$;

-- one stored figure; returns 1 when a row was written
create or replace function public._rb4_kpi_put(p_d date, p_loc int, p_k text, p_v numeric, p_redo boolean) returns int
language plpgsql security definer set search_path = public as $$
declare cnt int;
begin
  if p_redo then
    insert into public.kpi_snapshots (snap_date, location_id, kpi, value, computed_by) values (p_d, p_loc, p_k, p_v, auth.uid())
      on conflict (snap_date, location_id, kpi) do update set value = excluded.value, computed_at = now(), computed_by = auth.uid();
    return 1;
  end if;
  insert into public.kpi_snapshots (snap_date, location_id, kpi, value, computed_by) values (p_d, p_loc, p_k, p_v, auth.uid()) on conflict (snap_date, location_id, kpi) do nothing;
  get diagnostics cnt = row_count;
  return cnt;
end $$;

create or replace function public.kpi_snapshot_take(p_from date default null, p_to date default null, p_redo boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare td date := public._rb4_today(); f date := coalesce(p_from, td - 1); t date := coalesce(p_to, coalesce(p_from, td - 1)); ops boolean; locs int[]; n int := 0; r record; redo boolean := coalesce(p_redo, false);
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  ops := public._is_ops('notify');
  if not (ops or public.is_owner() or public.rpt_access('sales')) then raise exception 'not allowed'; end if;
  if redo and not (public.is_owner() or public._rb4_target_edit()) then raise exception 'not allowed'; end if;
  if t < f or t - f > 100 then raise exception 'bad_range'; end if;
  if t >= td then raise exception 'day_not_closed'; end if;      -- today is not finished: a snapshot of it would mislead
  select coalesce(array_agg(l.id), '{}') into locs from public.locations l where l.is_active and (ops or public.is_owner() or public.can_loc(l.id));
  -- places that sell: every closed day gets its figures (a day with no sale is a real 0 for a place that sells at all)
  for r in
    select days.d, s.loc, coalesce(sd.gross, 0) as gross, coalesce(sd.returns_amt, 0) as ret, coalesce(sd.bills, 0) as bills, coalesce(sd.subtotal, 0) as subtotal, coalesce(sd.discount, 0) as disc,
           coalesce(sd.void_n, 0) as void_n, coalesce(sd.void_amt, 0) as void_amt
      from (select generate_series(f, t, interval '1 day')::date as d) days
      cross join (select x.location_id as loc from public.sales x where x.location_id = any (locs) group by 1 union select c.location_id from public.sale_returns c where c.location_id = any (locs) group by 1) s
      left join public._rb4_sales_days(f, t, locs) sd on sd.d = days.d and sd.loc = s.loc loop
    n := n + public._rb4_kpi_put(r.d, r.loc, 'gross_sales', r.gross, redo) + public._rb4_kpi_put(r.d, r.loc, 'returns_amt', r.ret, redo) + public._rb4_kpi_put(r.d, r.loc, 'bills_n', r.bills, redo)
           + public._rb4_kpi_put(r.d, r.loc, 'subtotal_amt', r.subtotal, redo) + public._rb4_kpi_put(r.d, r.loc, 'discount_amt', r.disc, redo)
           + public._rb4_kpi_put(r.d, r.loc, 'void_n', r.void_n, redo) + public._rb4_kpi_put(r.d, r.loc, 'void_amt', r.void_amt, redo);
  end loop;
  -- places that produce
  for r in
    select days.d, m.loc, coalesce(pr.runs_n, 0) as runs_n, pr.ys, pr.ya
      from (select generate_series(f, t, interval '1 day')::date as d) days
      cross join (select x.location_id as loc from public.production_runs x where x.location_id = any (locs) group by 1) m
      left join (select public._rb4_day(x.made_at) as d, x.location_id as loc, count(*) as runs_n, sum(x.yield_std) filter (where x.yield_actual is not null) as ys, sum(x.yield_actual) filter (where x.yield_actual is not null) as ya
                   from public.production_runs x where x.status = 'done' and public._rb4_day(x.made_at) between f and t and x.location_id = any (locs) group by 1, 2) pr on pr.d = days.d and pr.loc = m.loc loop
    n := n + public._rb4_kpi_put(r.d, r.loc, 'runs_n', r.runs_n, redo) + public._rb4_kpi_put(r.d, r.loc, 'yield_std_measured', r.ys, redo) + public._rb4_kpi_put(r.d, r.loc, 'yield_actual_measured', r.ya, redo);
  end loop;
  return jsonb_build_object('from', f, 'to', t, 'rows_written', n, 'redo', redo);
end $$;

create or replace function public.rb4_kpi_trend(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; td date := public._rb4_today(); net_on boolean := coalesce(public.rule_on('reports_net_of_returns'), true);
        l_drop numeric := public.rule_num('kpi_alert_sales_drop_pct'); l_disc numeric := public.rule_num('kpi_alert_discount_pct'); l_void numeric := public.rule_num('kpi_alert_void_n');
        days_ jsonb; places jsonb; alerts jsonb; missing jsonb; notes jsonb := '[]'::jsonb; exc jsonb; short_hist int;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_target_view(p_loc) then raise exception 'not allowed'; end if;
  with sn as (
    select s.snap_date as d, s.location_id as loc,
           max(s.value) filter (where s.kpi = 'gross_sales') as gross, max(s.value) filter (where s.kpi = 'returns_amt') as ret, max(s.value) filter (where s.kpi = 'bills_n') as bills,
           max(s.value) filter (where s.kpi = 'subtotal_amt') as subtotal, max(s.value) filter (where s.kpi = 'discount_amt') as disc, max(s.value) filter (where s.kpi = 'void_n') as void_n,
           max(s.value) filter (where s.kpi = 'void_amt') as void_amt, max(s.value) filter (where s.kpi = 'runs_n') as runs_n,
           max(s.value) filter (where s.kpi = 'yield_std_measured') as ys, max(s.value) filter (where s.kpi = 'yield_actual_measured') as ya
      from public.kpi_snapshots s where s.snap_date between f - 28 and t and (p_loc is null or s.location_id = p_loc) and public._rb4_target_view(s.location_id) group by 1, 2),
  nt as (select sn.*, case when sn.gross is not null then sn.gross - case when net_on then coalesce(sn.ret, 0) else 0 end end as net from sn),
  cur as (select * from nt where d between f and t)
  select coalesce((select jsonb_agg(jsonb_build_object('day', x.d, 'places_covered', x.pc, 'net_sales', x.net, 'gross_sales', x.gross, 'returns', x.ret, 'bills', x.bills,
              'avg_bill', case when x.bills > 0 then round(x.gross / x.bills, 2) end, 'discount_pct', case when x.subtotal > 0 then round(x.disc / x.subtotal * 100, 2) end,
              'void_n', x.void_n, 'void_amt', x.void_amt, 'runs_n', x.runs_n, 'yield_var_pct', case when x.ys > 0 then round((x.ya - x.ys) / x.ys * 100, 2) end) order by x.d)
            from (select d, count(*) as pc, sum(net) as net, sum(gross) as gross, sum(ret) as ret, sum(bills) as bills, sum(subtotal) as subtotal, sum(disc) as disc, sum(void_n) as void_n, sum(void_amt) as void_amt, sum(runs_n) as runs_n, sum(ys) as ys, sum(ya) as ya
                    from cur group by d) x), '[]'::jsonb),
         coalesce((select jsonb_agg(jsonb_build_object('location_id', g.loc, 'location', l.name_bn, 'location_en', l.name_en, 'days', g.n, 'net_sales', g.net, 'bills', g.bills,
              'avg_bill', case when g.bills > 0 then round(g.gross / g.bills, 2) end, 'discount_pct', case when g.subtotal > 0 then round(g.disc / g.subtotal * 100, 2) end, 'void_n', g.void_n) order by l.sort, g.loc)
            from (select loc, count(*) as n, sum(net) as net, sum(gross) as gross, sum(bills) as bills, sum(subtotal) as subtotal, sum(disc) as disc, sum(void_n) as void_n from cur group by loc) g join public.locations l on l.id = g.loc), '[]'::jsonb),
         coalesce((select jsonb_agg(z.j order by z.d desc, z.loc, z.k)
            from (
              select c.d, c.loc, 'sales_drop' as k, jsonb_build_object('day', c.d, 'location_id', c.loc, 'location', lo.name_bn, 'location_en', lo.name_en, 'kind', 'sales_drop', 'value', c.net, 'reference', round(r.avg_ref, 2),
                       'drop_pct', round((r.avg_ref - c.net) / r.avg_ref * 100, 1), 'limit', l_drop, 'reference_days', r.n_ref) as j
                from cur c join public.locations lo on lo.id = c.loc
                cross join lateral (select avg(p.net) as avg_ref, count(*) as n_ref from nt p where p.loc = c.loc and p.d < c.d and p.d >= c.d - 28 and extract(dow from p.d) = extract(dow from c.d) and p.net is not null) r
               where l_drop is not null and c.net is not null and r.n_ref >= 2 and r.avg_ref > 0 and c.net < r.avg_ref * (1 - l_drop / 100)
              union all
              select c.d, c.loc, 'discount_high', jsonb_build_object('day', c.d, 'location_id', c.loc, 'location', lo.name_bn, 'location_en', lo.name_en, 'kind', 'discount_high', 'value', round(c.disc / c.subtotal * 100, 2), 'limit', l_disc)
                from cur c join public.locations lo on lo.id = c.loc where l_disc is not null and c.subtotal > 0 and c.disc / c.subtotal * 100 > l_disc
              union all
              select c.d, c.loc, 'void_high', jsonb_build_object('day', c.d, 'location_id', c.loc, 'location', lo.name_bn, 'location_en', lo.name_en, 'kind', 'void_high', 'value', c.void_n, 'limit', l_void)
                from cur c join public.locations lo on lo.id = c.loc where l_void is not null and c.void_n > l_void) z), '[]'::jsonb),
         (select count(*) from cur c cross join lateral (select count(*) as n_ref from nt p where p.loc = c.loc and p.d < c.d and p.d >= c.d - 28 and extract(dow from p.d) = extract(dow from c.d) and p.net is not null) r
           where l_drop is not null and c.net is not null and r.n_ref < 2)
    into days_, places, alerts, short_hist;
  -- closed days of the period without any snapshot: said, never drawn as 0
  select coalesce(jsonb_agg(d.d order by d.d), '[]'::jsonb) into missing
    from (select generate_series(f, least(t, td - 1), interval '1 day')::date as d) d
   where not exists (select 1 from public.kpi_snapshots s where s.snap_date = d.d and (p_loc is null or s.location_id = p_loc) and public._rb4_target_view(s.location_id));
  if l_drop is null then notes := notes || jsonb_build_object('code', 'alert_limit_not_set', 'field', 'kpi_alert_sales_drop_pct'); end if;
  if l_disc is null then notes := notes || jsonb_build_object('code', 'alert_limit_not_set', 'field', 'kpi_alert_discount_pct'); end if;
  if l_void is null then notes := notes || jsonb_build_object('code', 'alert_limit_not_set', 'field', 'kpi_alert_void_n'); end if;
  if short_hist > 0 then notes := notes || jsonb_build_object('code', 'not_enough_history', 'days', short_hist); end if;
  if jsonb_array_length(days_) = 0 then notes := notes || jsonb_build_object('code', 'snapshot_not_captured', 'field', 'daily KPI snapshot'); end if;
  select jsonb_build_object('red', count(*) filter (where e.level = 'red'), 'yellow', count(*) filter (where e.level = 'yellow')) into exc
    from public.exceptions e where e.status = 'open' and (e.location_id is null or public.can_loc(e.location_id));
  return jsonb_build_object('from', f, 'to', t, 'days', days_, 'places', places, 'alerts', alerts, 'missing_days', missing, 'net_of_returns', net_on, 'open_exceptions', exc,
    'limits', jsonb_build_object('sales_drop_pct', l_drop, 'discount_pct', l_disc, 'void_n', l_void), 'notes', notes,
    'basis', 'From the daily snapshots. A day without a snapshot is listed as missing, not drawn as 0. Sales drop = a day below the average of the previous 4 same weekdays (at least 2 needed) by more than the owner limit. Alerts are display only.');
end $$;

do $p$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_rb4_sales_days', '_rb4_kpi_put') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('rb4_target_report', 'kpi_snapshot_take', 'rb4_kpi_trend') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $p$;

notify pgrst, 'reload schema';

-- ===================== phase411.sql =====================
-- Phase 411 (bos411) - RPT-B4 / R5c: OUTLET TARGET TILE FOR THE OWNER BOARD.
-- Paste after phase410. Paste-twice safe. Read only. The owner board (web/ownerboard.js, phase45) keeps its own widget list; this phase gives the one function the new widget "target_vs" calls.
--
--   rb4_target_tile(month)   this month (or the month asked): per place with a target - target, achieved, achievement %, pace % (the share of the month gone, today counted), status - and one total line over the places that
--                            have a target. Places that sold something but have no target are listed by name ("target not set"). Nothing is invented: no target = no tile line.

do $g$ begin
  if to_regprocedure('public.rb4_target_report(date,date,int)') is null then raise exception 'phase411 needs phase410 first'; end if;
end $g$;

create or replace function public.rb4_target_tile(p_month date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m date := date_trunc('month', coalesce(p_month, public._rb4_today()))::date; rep jsonb; rows_ jsonb; tt_ numeric; ta_ numeric; pace numeric; notgt jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  rep := public.rb4_target_report(m, m, null);
  select coalesce(jsonb_agg(jsonb_build_object('location_id', e ->> 'location_id', 'location', e ->> 'location', 'location_en', e ->> 'location_en', 'target', e -> 'target', 'achieved', e -> 'achieved',
         'achievement_pct', e -> 'achievement_pct', 'pace_pct', e -> 'pace_pct', 'status', e ->> 'status', 'gp_pct', e -> 'gp_pct', 'gp_target_pct', e -> 'gp_target_pct') order by (e ->> 'location_id')::int), '[]'::jsonb) into rows_
    from jsonb_array_elements(rep -> 'rows') e where e ->> 'target_id' is not null;
  select coalesce(jsonb_agg(jsonb_build_object('location_id', e ->> 'location_id', 'location', e ->> 'location', 'location_en', e ->> 'location_en', 'achieved', e -> 'achieved') order by (e ->> 'location_id')::int), '[]'::jsonb) into notgt
    from jsonb_array_elements(rep -> 'rows') e where e ->> 'target_id' is null;
  select sum((e ->> 'target')::numeric), sum((e ->> 'achieved')::numeric), max((e ->> 'pace_pct')::numeric) into tt_, ta_, pace from jsonb_array_elements(rows_) e;
  return jsonb_build_object('month', m, 'rows', rows_, 'no_target', notgt,
    'total', case when jsonb_array_length(rows_) > 0 then jsonb_build_object('target', tt_, 'achieved', ta_, 'achievement_pct', case when tt_ > 0 then round(ta_ / tt_ * 100, 1) end, 'pace_pct', pace) end,
    'behind', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'status' in ('behind', 'closed_missed')),
    'notes', case when jsonb_array_length(rows_) = 0 then jsonb_build_array(jsonb_build_object('code', 'target_not_set', 'field', 'sales target')) else '[]'::jsonb end);
end $$;

revoke all on function public.rb4_target_tile(date) from public, anon;
grant execute on function public.rb4_target_tile(date) to authenticated;

notify pgrst, 'reload schema';

-- ===================== phase412.sql =====================
-- Phase 412 (bos412) - RPT-B4 / R8a: RATED CAPACITY, PRODUCTION LINES AND LABOUR HOURS PER RUN (data capture).
-- Paste after phase405 (it extends the run link table of phase 404). Paste-twice safe. No earlier phase file is edited; no shared function is re-created.
-- Requirements: docs/REPORTS_AUDIT_1.md items #48 (output per labour hour) and #51 (capacity utilization). Attendance exists at day level only; the hours of a crew on one run were never captured.
--
--   production_lines     a named line / section of a producing place (name_bn + name_en, retired never deleted).
--   capacity_ratings     the owner's rated capacity of a place (or one of its lines): batches per day and working days per week, from a day on. A blank rating = "rated capacity not captured".
--   production_labour    who worked on a run: number of people and the hours each worked (more than one crew = more than one line). Voided, never deleted.
--   production_run_links.line_id   which line a run was made on (optional).
--   grant capacity_manage   who may set lines and ratings. By default only the owner. Labour hours are entered with the production grant stock_production, like the rest of the production capture.
-- Nothing here moves stock or money. Paper form code of these entry screens: to be given by owner.

do $g$ begin
  if to_regclass('public.production_run_links') is null then raise exception 'phase412 needs phase404 first'; end if;
  if to_regprocedure('public.prod_run_link(uuid,uuid,bigint,boolean,boolean)') is null then raise exception 'phase412 needs phase405 first'; end if;
end $g$;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('capacity_manage', 'stock', 60, 'উৎপাদন লাইন ও ক্ষমতা ঠিক করা', 'Production line ও capacity ঠিক করা', 'Set production lines and rated capacity', 'once', null)
on conflict (grant_code) do nothing;

create table if not exists public.production_lines (
  id serial primary key,
  location_id int not null references public.locations(id),
  name_bn text not null check (length(btrim(name_bn)) between 1 and 80),
  name_en text check (name_en is null or length(btrim(name_en)) between 1 and 80),
  active boolean not null default true,
  retired_note text, retired_by uuid, retired_at timestamptz,
  created_by uuid, created_at timestamptz not null default now()
);
create unique index if not exists production_lines_name on public.production_lines (location_id, lower(btrim(name_bn)));

create table if not exists public.capacity_ratings (
  id bigserial primary key,
  location_id int not null references public.locations(id),
  line_id int references public.production_lines(id),
  batches_per_day numeric not null check (batches_per_day > 0 and batches_per_day <= 100000),
  days_per_week numeric not null check (days_per_week > 0 and days_per_week <= 7),
  effective_from date not null,
  note text check (note is null or length(note) <= 300),
  status text not null default 'active' check (status in ('active', 'retired')),
  retired_note text, retired_by uuid, retired_at timestamptz,
  created_by uuid, created_staff text, created_at timestamptz not null default now()
);
create unique index if not exists capacity_ratings_one on public.capacity_ratings (location_id, coalesce(line_id, 0), effective_from) where status = 'active';

create table if not exists public.production_labour (
  id bigserial primary key,
  client_id uuid unique,
  run_id uuid not null references public.production_runs(id),
  people int not null check (people > 0 and people <= 1000),
  hours_each numeric not null check (hours_each > 0 and hours_each <= 24),
  note text check (note is null or length(note) <= 300),
  status text not null default 'active' check (status in ('active', 'void')),
  void_note text, void_by uuid, void_at timestamptz,
  created_by uuid, created_staff text, created_at timestamptz not null default now()
);
create index if not exists production_labour_run on public.production_labour (run_id);

alter table public.production_run_links add column if not exists line_id int references public.production_lines(id);

do $t$
declare t text;
begin
  foreach t in array array['production_lines', 'capacity_ratings', 'production_labour'] loop
    execute format('drop trigger if exists audit_%1$s on public.%1$s', t);
    execute format('create trigger audit_%1$s after insert or update on public.%1$s for each row execute function public.log_change(%2$L)', t, 'id');
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $t$;
revoke all on sequence public.production_lines_id_seq, public.capacity_ratings_id_seq, public.production_labour_id_seq from public, anon, authenticated;

create or replace function public._rb4_cap_edit(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and public.can_loc(p_loc) and (public.is_owner() or public.has_grant('capacity_manage', p_loc));
$$;
drop policy if exists production_lines_read on public.production_lines;
create policy production_lines_read on public.production_lines for select to authenticated using (public._rb4_prod_view(location_id));
drop policy if exists capacity_ratings_read on public.capacity_ratings;
create policy capacity_ratings_read on public.capacity_ratings for select to authenticated using (public._rb4_prod_view(location_id));
drop policy if exists production_labour_read on public.production_labour;
create policy production_labour_read on public.production_labour for select to authenticated using (exists (select 1 from public.production_runs r where r.id = run_id and public._rb4_prod_view(r.location_id)));

-- ---------- lines ----------
create or replace function public.production_line_set(p_id int, p_loc int, p_name_bn text, p_name_en text default null, p_active boolean default true, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.production_lines; nb text := nullif(btrim(p_name_bn), ''); ne text := nullif(btrim(p_name_en), ''); id_ int;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_id is not null then
    select * into l from public.production_lines where id = p_id for update;
    if not found then raise exception 'not found'; end if;
    if not public._rb4_cap_edit(l.location_id) then raise exception 'not allowed'; end if;
  else
    if p_loc is null or not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
    if not public._rb4_cap_edit(p_loc) then raise exception 'not allowed'; end if;
  end if;
  if nb is null or length(nb) > 80 or (ne is not null and length(ne) > 80) then raise exception 'bad_name'; end if;
  if p_id is null then
    insert into public.production_lines (location_id, name_bn, name_en, created_by) values (p_loc, nb, ne, auth.uid()) returning id into id_;
    return jsonb_build_object('id', id_);
  end if;
  if coalesce(p_active, true) = false and l.active then
    if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;      -- retiring a line needs a reason
    update public.production_lines set name_bn = nb, name_en = ne, active = false, retired_note = left(btrim(p_note), 300), retired_by = auth.uid(), retired_at = now() where id = p_id;
  else
    update public.production_lines set name_bn = nb, name_en = ne, active = coalesce(p_active, true), retired_note = case when coalesce(p_active, true) then null else retired_note end where id = p_id;
  end if;
  return jsonb_build_object('id', p_id);
end $$;

create or replace function public.production_line_list(p_loc int default null, p_with_retired boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'location_id', l.location_id, 'location', lo.name_bn, 'location_en', lo.name_en, 'name_bn', l.name_bn, 'name_en', l.name_en, 'active', l.active, 'retired_note', l.retired_note,
      'can_edit', public._rb4_cap_edit(l.location_id)) order by lo.sort, l.id)
    from public.production_lines l join public.locations lo on lo.id = l.location_id
   where (p_loc is null or l.location_id = p_loc) and public._rb4_prod_view(l.location_id) and (coalesce(p_with_retired, false) or l.active)), '[]'::jsonb);
end $$;

-- ---------- rated capacity ----------
create or replace function public.capacity_rating_set(p_loc int, p_line int, p_batches_per_day numeric, p_days_per_week numeric, p_from date, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old public.capacity_ratings; sid text; id_ bigint; n text := nullif(btrim(p_note), '');
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is null or not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if not public._rb4_cap_edit(p_loc) then raise exception 'not allowed'; end if;
  if p_line is not null and not exists (select 1 from public.production_lines where id = p_line and location_id = p_loc and active) then raise exception 'line_not_found'; end if;
  if p_batches_per_day is null or not (p_batches_per_day > 0 and p_batches_per_day <= 100000) then raise exception 'bad_capacity'; end if;
  if p_days_per_week is null or not (p_days_per_week > 0 and p_days_per_week <= 7) then raise exception 'bad_days'; end if;
  if p_from is null or abs(p_from - public._rb4_today()) > 800 then raise exception 'bad_date'; end if;
  if n is not null and length(n) > 300 then raise exception 'bad_note'; end if;
  select * into old from public.capacity_ratings where location_id = p_loc and line_id is not distinct from p_line and effective_from = p_from and status = 'active' for update;
  if found and old.batches_per_day = p_batches_per_day and old.days_per_week = p_days_per_week then return jsonb_build_object('dup', true, 'id', old.id); end if;
  if found then update public.capacity_ratings set status = 'retired', retired_note = 'replaced by a new rating', retired_by = auth.uid(), retired_at = now() where id = old.id; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.capacity_ratings (location_id, line_id, batches_per_day, days_per_week, effective_from, note, created_by, created_staff) values (p_loc, p_line, p_batches_per_day, p_days_per_week, p_from, n, auth.uid(), sid) returning id into id_;
  return jsonb_build_object('id', id_, 'replaced', old.id);
end $$;

create or replace function public.capacity_rating_retire(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.capacity_ratings;
begin
  select * into r from public.capacity_ratings where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public._rb4_cap_edit(r.location_id) then raise exception 'not allowed'; end if;
  if r.status = 'retired' then return jsonb_build_object('dup', true, 'status', 'retired'); end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.capacity_ratings set status = 'retired', retired_note = left(btrim(p_note), 300), retired_by = auth.uid(), retired_at = now() where id = p_id;
  return jsonb_build_object('status', 'retired');
end $$;

create or replace function public.capacity_rating_list(p_loc int default null, p_with_retired boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'location_id', c.location_id, 'location', lo.name_bn, 'location_en', lo.name_en, 'line_id', c.line_id, 'line_bn', ln.name_bn, 'line_en', ln.name_en,
      'batches_per_day', c.batches_per_day, 'days_per_week', c.days_per_week, 'effective_from', c.effective_from, 'note', c.note, 'status', c.status, 'retired_note', c.retired_note, 'created_staff', c.created_staff,
      'can_edit', public._rb4_cap_edit(c.location_id)) order by lo.sort, c.location_id, c.line_id nulls first, c.effective_from desc, c.id)
    from public.capacity_ratings c join public.locations lo on lo.id = c.location_id left join public.production_lines ln on ln.id = c.line_id
   where (p_loc is null or c.location_id = p_loc) and public._rb4_prod_view(c.location_id) and (coalesce(p_with_retired, false) or c.status = 'active')), '[]'::jsonb);
end $$;

-- ---------- labour hours of a run ----------
create or replace function public.prod_labour_add(p_run uuid, p_people int, p_hours numeric, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare prev public.production_labour; r public.production_runs; sid text; id_ bigint; n text := nullif(btrim(p_note), '');
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into prev from public.production_labour where client_id = p_client;
    if found then
      if prev.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', prev.id);
    end if;
  end if;
  select * into r from public.production_runs where id = p_run;
  if not found then raise exception 'not found'; end if;
  if not public._rb4_prod_entry(r.location_id) then raise exception 'not allowed'; end if;
  if r.status <> 'done' then raise exception 'run_void'; end if;
  if p_people is null or not (p_people between 1 and 1000) then raise exception 'bad_people'; end if;
  if p_hours is null or not (p_hours > 0 and p_hours <= 24) then raise exception 'bad_hours'; end if;
  if n is not null and length(n) > 300 then raise exception 'bad_note'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.production_labour (client_id, run_id, people, hours_each, note, created_by, created_staff) values (p_client, p_run, p_people, p_hours, n, auth.uid(), sid) returning id into id_;
  return jsonb_build_object('id', id_, 'labour_hours', p_people * p_hours);
end $$;

create or replace function public.prod_labour_void(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.production_labour; r public.production_runs;
begin
  select * into l from public.production_labour where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  select * into r from public.production_runs where id = l.run_id;
  if not public._rb4_prod_entry(r.location_id) then raise exception 'not allowed'; end if;
  if l.status = 'void' then return jsonb_build_object('dup', true, 'status', 'void'); end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.production_labour set status = 'void', void_note = left(btrim(p_note), 300), void_by = auth.uid(), void_at = now() where id = p_id;
  return jsonb_build_object('status', 'void');
end $$;

-- which line a run was made on (blank = not recorded); a finished run only
create or replace function public.prod_run_line(p_run uuid, p_line int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.production_runs;
begin
  select * into r from public.production_runs where id = p_run;
  if not found then raise exception 'not found'; end if;
  if not public._rb4_prod_entry(r.location_id) then raise exception 'not allowed'; end if;
  if r.status <> 'done' then raise exception 'run_void'; end if;
  if p_line is not null and not exists (select 1 from public.production_lines where id = p_line and location_id = r.location_id and active) then raise exception 'line_not_found'; end if;
  insert into public.production_run_links (run_id, line_id, linked_by) values (p_run, p_line, auth.uid())
    on conflict (run_id) do update set line_id = excluded.line_id, linked_by = excluded.linked_by, linked_at = now();
  return jsonb_build_object('run_id', p_run, 'line_id', p_line);
end $$;

-- labour and line of the runs of a period (the entry screen shows them next to prod_runs_recent)
create or replace function public.prod_labour_list(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('run_id', r.id, 'line_id', k.line_id, 'line_bn', ln.name_bn, 'line_en', ln.name_en,
        'labour_hours', (select sum(x.people * x.hours_each) from public.production_labour x where x.run_id = r.id and x.status = 'active'),
        'entries', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'people', x.people, 'hours_each', x.hours_each, 'note', x.note, 'created_staff', x.created_staff) order by x.id) from public.production_labour x where x.run_id = r.id and x.status = 'active'), '[]'::jsonb))
      order by r.made_at desc)
    from public.production_runs r left join public.production_run_links k on k.run_id = r.id left join public.production_lines ln on ln.id = k.line_id
   where r.status = 'done' and public._rb4_day(r.made_at) between f and t and (p_loc is null or r.location_id = p_loc) and public._rb4_prod_view(r.location_id)), '[]'::jsonb);
end $$;

do $p$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = '_rb4_cap_edit' loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace
           and p.proname in ('production_line_set', 'production_line_list', 'capacity_rating_set', 'capacity_rating_retire', 'capacity_rating_list', 'prod_labour_add', 'prod_labour_void', 'prod_run_line', 'prod_labour_list') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $p$;

notify pgrst, 'reload schema';

-- ===================== phase413.sql =====================
-- Phase 413 (bos413) - RPT-B4 / R8b: OUTPUT PER LABOUR HOUR (#48) AND CAPACITY UTILIZATION (#51).
-- Paste after phase412. Paste-twice safe. Read only: nothing here moves stock or money. No earlier phase file is edited.
--
--   rb4_labour_productivity(from, to, place, item)   per finished run: the output, the labour hours recorded for it (people x hours each, summed over the crews) and the output per labour hour.
--                                                    A run with no labour record is "labour not captured": it is not counted in any total and its figure is empty (never 0). Units are never mixed: totals are per item.
--   rb4_capacity_utilization(from, to, place)        per place (and per line that has a rating): the batches made against the rated capacity. Capacity of a day = batches per day x working days per week / 7,
--                                                    taken from the rating in force on that day. Days with no rating are not judged (the batches made on them are shown apart); no rating at all = "rated capacity not captured".
--                                                    A place-level rating is compared with ALL runs of the place; a line rating with the runs recorded on that line.

do $g$ begin
  if to_regprocedure('public.prod_labour_list(date,date,int)') is null then raise exception 'phase413 needs phase412 first'; end if;
end $g$;

create or replace function public.rb4_labour_productivity(p_from date default null, p_to date default null, p_loc int default null, p_item uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; rows_ jsonb; by_item jsonb; by_place jsonb; trunc boolean; notes jsonb := '[]'::jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  with runs as (
    select r.* from public.production_runs r where r.status = 'done' and public._rb4_day(r.made_at) between f and t and (p_loc is null or r.location_id = p_loc) and (p_item is null or r.item_id = p_item) and public._rb4_prod_view(r.location_id)
     order by r.made_at desc limit 2001),
  lab as (select x.run_id, sum(x.people * x.hours_each) as hrs, sum(x.people) as ppl, count(*) as crews from public.production_labour x where x.status = 'active' and x.run_id in (select id from runs) group by 1)
  select (select count(*) > 2000 from runs),
         coalesce(jsonb_agg(jsonb_build_object('run_id', r.id, 'day', public._rb4_day(r.made_at), 'location_id', r.location_id, 'location', l.name_bn, 'location_en', l.name_en,
           'item_id', r.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(r.item_id), 'batches', r.batches, 'output', r.yield_base,
           'line_id', k.line_id, 'line_bn', ln.name_bn, 'line_en', ln.name_en, 'labour_hours', lab.hrs, 'people', lab.ppl, 'crews', lab.crews,
           'output_per_hour', case when lab.hrs > 0 then round(r.yield_base / lab.hrs, 4) end, 'hours_per_unit', case when lab.hrs > 0 and r.yield_base > 0 then round(lab.hrs / r.yield_base, 4) end,
           'status', case when lab.hrs is null then 'labour_not_captured' else 'measured' end) order by r.made_at desc), '[]'::jsonb)
    into trunc, rows_
    from (select * from runs limit 2000) r join public.items i on i.id = r.item_id join public.locations l on l.id = r.location_id
    left join lab on lab.run_id = r.id left join public.production_run_links k on k.run_id = r.id left join public.production_lines ln on ln.id = k.line_id;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', g.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(g.item_id),
        'runs', g.runs, 'measured', g.m, 'labour_not_captured', g.runs - g.m, 'output_measured', case when g.m > 0 then g.out_m end, 'labour_hours', case when g.m > 0 then g.hrs end,
        'output_per_hour', case when g.m > 0 and g.hrs > 0 then round(g.out_m / g.hrs, 4) end) order by i.code), '[]'::jsonb) into by_item
    from (select (e ->> 'item_id')::uuid as item_id, count(*) as runs, count(*) filter (where e ->> 'status' = 'measured') as m, sum((e ->> 'output')::numeric) filter (where e ->> 'status' = 'measured') as out_m,
                 sum((e ->> 'labour_hours')::numeric) filter (where e ->> 'status' = 'measured') as hrs from jsonb_array_elements(rows_) e group by 1) g join public.items i on i.id = g.item_id;
  select coalesce(jsonb_agg(jsonb_build_object('location_id', g.loc, 'location', l.name_bn, 'location_en', l.name_en, 'runs', g.runs, 'measured', g.m, 'labour_not_captured', g.runs - g.m,
        'labour_hours', case when g.m > 0 then g.hrs end, 'batches_measured', case when g.m > 0 then g.b end, 'batches_per_hour', case when g.m > 0 and g.hrs > 0 then round(g.b / g.hrs, 4) end) order by l.sort, g.loc), '[]'::jsonb) into by_place
    from (select (e ->> 'location_id')::int as loc, count(*) as runs, count(*) filter (where e ->> 'status' = 'measured') as m, sum((e ->> 'labour_hours')::numeric) filter (where e ->> 'status' = 'measured') as hrs,
                 sum((e ->> 'batches')::numeric) filter (where e ->> 'status' = 'measured') as b from jsonb_array_elements(rows_) e group by 1) g join public.locations l on l.id = g.loc;
  if jsonb_array_length(rows_) > 0 and not exists (select 1 from jsonb_array_elements(rows_) e where e ->> 'status' = 'measured') then notes := notes || jsonb_build_object('code', 'labour_not_captured', 'field', 'labour hours per run'); end if;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'by_item', by_item, 'by_place', by_place, 'truncated', coalesce(trunc, false), 'notes', notes,
    'basis', 'Labour hours = people x hours each, summed over the crews recorded for the run. Output of different items is never added; totals are per item. Runs with no labour record are left out of every total.');
end $$;

create or replace function public.rb4_capacity_utilization(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; rows_ jsonb; notes jsonb := '[]'::jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  with days as (select generate_series(f, t, interval '1 day')::date as d),
  pairs as (
    select c.location_id as loc, c.line_id from public.capacity_ratings c where c.status = 'active' and (p_loc is null or c.location_id = p_loc) and public._rb4_prod_view(c.location_id)
    union
    select r.location_id, null::int from public.production_runs r where r.status = 'done' and public._rb4_day(r.made_at) between f and t and (p_loc is null or r.location_id = p_loc) and public._rb4_prod_view(r.location_id)),
  pd as (
    select p.loc, p.line_id, days.d, rt.batches_per_day, rt.days_per_week,
           (select coalesce(sum(r.batches), 0) from public.production_runs r left join public.production_run_links k on k.run_id = r.id
             where r.status = 'done' and r.location_id = p.loc and public._rb4_day(r.made_at) = days.d and (p.line_id is null or k.line_id = p.line_id)) as act
      from pairs p cross join days
      left join lateral (select c.batches_per_day, c.days_per_week from public.capacity_ratings c where c.status = 'active' and c.location_id = p.loc and c.line_id is not distinct from p.line_id and c.effective_from <= days.d
                          order by c.effective_from desc limit 1) rt on true),
  ag as (
    select loc, line_id, count(*) as days_n, count(*) filter (where batches_per_day is not null) as days_rated,
           sum(batches_per_day * days_per_week / 7) as cap, sum(act) filter (where batches_per_day is not null) as act_rated, sum(act) filter (where batches_per_day is null) as act_unrated, sum(act) as act_all,
           (array_agg(batches_per_day order by d desc) filter (where batches_per_day is not null))[1] as bpd_last, (array_agg(days_per_week order by d desc) filter (where batches_per_day is not null))[1] as dpw_last
      from pd group by loc, line_id)
  select coalesce(jsonb_agg(jsonb_build_object('location_id', a.loc, 'location', l.name_bn, 'location_en', l.name_en, 'line_id', a.line_id, 'line_bn', ln.name_bn, 'line_en', ln.name_en,
      'days', a.days_n, 'days_rated', a.days_rated, 'days_not_rated', a.days_n - a.days_rated, 'capacity_batches', case when a.days_rated > 0 then round(a.cap, 2) end,
      'batches_made_on_rated_days', case when a.days_rated > 0 then a.act_rated end, 'batches_made_on_days_not_rated', case when a.days_n > a.days_rated then a.act_unrated end, 'batches_made', a.act_all,
      'utilization_pct', case when a.days_rated > 0 and a.cap > 0 then round(a.act_rated / a.cap * 100, 1) end,
      'rated_batches_per_day', a.bpd_last, 'rated_days_per_week', a.dpw_last,
      'status', case when a.days_rated = 0 then 'rated_capacity_not_captured' when a.days_rated < a.days_n then 'partly_rated' else 'rated' end) order by l.sort, a.loc, a.line_id nulls first), '[]'::jsonb) into rows_
    from ag a join public.locations l on l.id = a.loc left join public.production_lines ln on ln.id = a.line_id;
  if jsonb_array_length(rows_) > 0 and not exists (select 1 from jsonb_array_elements(rows_) e where e ->> 'status' <> 'rated_capacity_not_captured') then notes := notes || jsonb_build_object('code', 'capacity_not_captured', 'field', 'rated capacity'); end if;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'notes', notes,
    'basis', 'Capacity of a day = rated batches per day x working days per week / 7, from the rating in force that day. Batches made are the finished runs (batches field). Days without a rating are not judged. A place rating counts all runs of the place; a line rating counts the runs recorded on the line.');
end $$;

do $p$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('rb4_labour_productivity', 'rb4_capacity_utilization') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $p$;

notify pgrst, 'reload schema';

-- ===================== phase415.sql =====================
-- Phase 415 (bos415) - RPT-B4 / R9a: OWNER SETTING FOR THE VALUE OF GOODS MOVED BETWEEN UNITS (factory -> shops).
-- Paste after phase404 (it uses the helper _rb4_today; phases 405-413 are not needed). Paste-twice safe. No earlier phase file is edited.
-- Requirement: docs/REPORTS_AUDIT_1.md item #7 (factory vs retail): stock_transfers carry no value, so a factory result cannot be told from a retail result. The owner decides the basis:
--
--   transfer_valuation_basis   none (DEFAULT, as today)  the report says "not valued" and shows quantities and the ledger cost only
--                              cost                       goods moved at what they cost the factory (the ledger cost of the transfer-out line): the factory shows no margin on transfers
--                              price_pct                  goods moved at a percentage of the item's selling price (setting transfer_price_pct); a blank percentage or a blank selling price = "not valued", never a guess
--   transfer_price_pct         the percentage for price_pct. BLANK by default (a blank number blocks the basis that needs it, BUILD-RULES 15).
-- The setting changes only the report (phase 416). No stock, no journal and no price changes.

do $g$ begin
  if to_regprocedure('public._rb4_today()') is null then raise exception 'phase415 needs phase404 first'; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('transfer_valuation_basis', 'reports', 'choice', '"none"'::jsonb, '["none", "cost", "price_pct"]'::jsonb, null, null,
  'কারখানা থেকে শোরুমে পাঠানো মালের দাম কীভাবে ধরা হবে (শুধু রিপোর্টে)', 'Factory থেকে showroom-এ পাঠানো মালের দাম কীভাবে ধরা হবে (শুধু report-এ)',
  'How goods moved between units are valued (reports only)',
  'none = not valued (default, as today). cost = the factory cost from the stock ledger. price_pct = a percentage of the selling price (set transfer_price_pct). Changes only the factory-vs-retail report; no stock or money moves.', 7010),
 ('transfer_price_pct', 'reports', 'number', null, null, 0, 1000,
  'পাঠানো মালের দাম = বিক্রয়মূল্যের এত শতাংশ (শুধু "price_pct" হলে)', 'পাঠানো মালের দাম = selling price-এর এত % (শুধু "price_pct" হলে)',
  'Moved goods are valued at this % of the selling price (only when the basis is price_pct)',
  'Blank = no value is worked out for that basis; the report says "percentage not set".', 7011)
on conflict (key) do nothing;

-- the value of one transfer line under the owner's basis; the state says why a value is missing
create or replace function public._rb4_transfer_value(p_item uuid, p_qty numeric, p_unit_cost numeric, p_basis text default null, p_pct numeric default null, out value numeric, out state text)
language plpgsql stable security definer set search_path = public as $$
declare b text := coalesce(p_basis, public.rule_txt('transfer_valuation_basis'), 'none'); pct numeric := coalesce(p_pct, public.rule_num('transfer_price_pct')); sp numeric;
begin
  if b = 'cost' then
    if p_unit_cost is null or p_unit_cost <= 0 then value := null; state := 'cost_not_captured'; else value := round(p_qty * p_unit_cost, 2); state := 'at_cost'; end if;
  elsif b = 'price_pct' then
    select sell_price into sp from public.items where id = p_item;
    if pct is null then value := null; state := 'pct_not_set';
    elsif sp is null or sp <= 0 then value := null; state := 'price_not_captured';
    else value := round(p_qty * sp * pct / 100, 2); state := 'pct_of_price'; end if;
  else
    value := null; state := 'not_valued';
  end if;
end $$;

revoke all on function public._rb4_transfer_value(uuid, numeric, numeric, text, numeric) from public, anon, authenticated;

notify pgrst, 'reload schema';

-- ===================== phase416.sql =====================
-- Phase 416 (bos416) - RPT-B4 / R9b: FACTORY VS RETAIL (#7) AND THE AUDIT LINE FOR THE CSV OF EVERY NEW REPORT OF THIS PACKAGE.
-- Paste after phase415 (and after 406-413 for the export keys to be useful; the report itself needs 404, 409, 410 and 415; the guard below says so). Paste-twice safe. Read only. No earlier phase file is edited.
--
--   rb4_factory_vs_retail(from, to)   three blocks side by side, per place the reader may see:
--     factory   what each factory place produced (runs, output per item, the cost booked on the runs) and what it sent to the shops;
--     transfers factory -> shop per item: quantity sent / received, the ledger cost of the goods, and their value under the owner's basis (setting transfer_valuation_basis, default none = "not valued");
--     retail    each shop: sales net of returns, the cost of goods sold from the ledger, gross profit on the part whose cost is known.
--   Shop gross profit is at ledger cost (what the system books). It is NOT reduced by a transfer value: the report puts the factory margin on transfers next to it and never nets the two.
--   Cost and value columns appear only for readers with the cost right at that place; a missing cost is "cost not captured", never 0.
--   rb4_log_export(key, kind, filters, rows)   the audit line written BEFORE a CSV of one of these reports is built (same rule as log_page_export: the owner or the export right, plus the right to read the report).

do $g$ begin
  if to_regprocedure('public._rb4_transfer_value(uuid,numeric,numeric,text,numeric)') is null then raise exception 'phase416 needs phase415 first'; end if;
  if to_regprocedure('public._rb4_target_view(int)') is null then raise exception 'phase416 needs phase409 (reader checks)'; end if;
  if to_regprocedure('public._rb4_sales_days(date,date,int[])') is null then raise exception 'phase416 needs phase410 (daily sales helper)'; end if;
end $g$;

create or replace function public.rb4_factory_vs_retail(p_from date default null, p_to date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; basis text := coalesce(public.rule_txt('transfer_valuation_basis'), 'none'); pct numeric := public.rule_num('transfer_price_pct'); net_on boolean := coalesce(public.rule_on('reports_net_of_returns'), true);
        facs int[]; rets int[]; costfac int[]; costret int[]; fac_rows jsonb; tr_rows jsonb; ret_rows jsonb; fac_tot jsonb; tr_tot jsonb; ret_tot jsonb; notes jsonb := '[]'::jsonb; hidden boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  select coalesce(array_agg(l.id), '{}') into facs from public.locations l where l.kind = 'factory' and (public._rb4_prod_view(l.id) or public._rb4_target_view(l.id));
  select coalesce(array_agg(l.id), '{}') into rets from public.locations l where l.kind = 'showroom' and (public._rb4_target_view(l.id) or public._rb4_prod_view(l.id));
  select coalesce(array_agg(x), '{}') into costfac from unnest(facs) x where public._cost_ok(x);
  select coalesce(array_agg(x), '{}') into costret from unnest(rets) x where public._cost_ok(x);
  hidden := cardinality(costfac) < cardinality(facs) or cardinality(costret) < cardinality(rets);

  -- factory side: production per place and item
  select coalesce(jsonb_agg(jsonb_build_object('location_id', z.loc, 'location', l.name_bn, 'location_en', l.name_en, 'item_id', z.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(z.item_id),
        'runs', z.runs, 'output', z.qty, 'costed_runs', case when z.loc = any (costfac) then z.costed end,
        'production_cost', case when z.loc = any (costfac) and z.costed = z.runs then round(z.cost, 2) end,
        'cost_state', case when not (z.loc = any (costfac)) then 'cost_hidden' when z.costed < z.runs then 'cost_not_captured' else 'known' end) order by l.sort, i.code), '[]'::jsonb) into fac_rows
    from (select r.location_id as loc, r.item_id, count(*) as runs, sum(r.yield_base) as qty, count(*) filter (where r.cost_complete and r.material_cost is not null and coalesce(r.conversion_complete, true)) as costed,
                 sum(coalesce(r.material_cost, 0) + coalesce(r.conversion_cost, 0)) as cost
            from public.production_runs r where r.status = 'done' and public._rb4_day(r.made_at) between f and t and r.location_id = any (facs) group by 1, 2) z
    join public.items i on i.id = z.item_id join public.locations l on l.id = z.loc;

  -- transfers factory -> shop, one value per transfer then grouped
  with tr as (
    select s.id, s.from_location_id as fl, s.to_location_id as tl, s.item_id, s.qty, s.status, s.received_qty,
           (select sum(-l.qty_delta * coalesce(l.unit_cost, 0)) from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = s.id::text and l.reason = 'transfer_out') as cost_val,
           (select bool_and(coalesce(l.unit_cost, 0) > 0) from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = s.id::text and l.reason = 'transfer_out') as cost_known
      from public.stock_transfers s
     where s.status in ('sent', 'received') and public._rb4_day(s.sent_at) between f and t and s.from_location_id = any (facs)
       and exists (select 1 from public.locations d where d.id = s.to_location_id and d.kind = 'showroom')),
  v as (
    select tr.*, (public._rb4_transfer_value(tr.item_id, tr.qty, case when tr.cost_known and tr.qty > 0 then tr.cost_val / tr.qty end, basis, pct)).value as tv,
                 (public._rb4_transfer_value(tr.item_id, tr.qty, case when tr.cost_known and tr.qty > 0 then tr.cost_val / tr.qty end, basis, pct)).state as tstate
      from tr)
  select coalesce(jsonb_agg(jsonb_build_object('from_location_id', g.fl, 'from_location', fo.name_bn, 'from_location_en', fo.name_en, 'to_location_id', g.tl, 'to_location', tlo.name_bn, 'to_location_en', tlo.name_en,
        'item_id', g.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(g.item_id), 'transfers', g.n, 'sent', g.qty, 'received', coalesce(g.rec, 0), 'in_transit', coalesce(g.transit, 0),
        'cost_value', case when g.fl = any (costfac) and g.cost_unknown = 0 then round(g.cost_val, 2) end,
        'cost_state', case when not (g.fl = any (costfac)) then 'cost_hidden' when g.cost_unknown > 0 then 'cost_not_captured' else 'known' end,
        'transfer_value', case when g.fl = any (costfac) and g.val_unknown = 0 then round(g.tv, 2) end,
        'value_state', case when not (g.fl = any (costfac)) then 'cost_hidden' when basis = 'none' then 'not_valued' when g.val_unknown > 0 then (select min(v2.tstate) from v v2 where v2.fl = g.fl and v2.tl = g.tl and v2.item_id = g.item_id and v2.tv is null) else basis end,
        'margin', case when g.fl = any (costfac) and g.cost_unknown = 0 and g.val_unknown = 0 and basis <> 'none' then round(g.tv - g.cost_val, 2) end) order by fo.sort, tlo.sort, i.code), '[]'::jsonb) into tr_rows
    from (select v.fl, v.tl, v.item_id, count(*) as n, sum(v.qty) as qty, sum(coalesce(v.received_qty, 0)) filter (where v.status = 'received') as rec, sum(v.qty) filter (where v.status = 'sent') as transit,
                 sum(v.cost_val) as cost_val, count(*) filter (where not coalesce(v.cost_known, false)) as cost_unknown, sum(v.tv) as tv, count(*) filter (where v.tv is null) as val_unknown
            from v group by 1, 2, 3) g
    join public.items i on i.id = g.item_id join public.locations fo on fo.id = g.fl join public.locations tlo on tlo.id = g.tl;

  -- retail side: each shop
  select coalesce(jsonb_agg(jsonb_build_object('location_id', z.loc, 'location', l.name_bn, 'location_en', l.name_en, 'gross_sales', z.gross, 'returns', z.ret, 'net_sales', z.gross - case when net_on then z.ret else 0 end, 'bills', z.bills,
        'cogs', case when z.loc = any (costret) and z.crev is not null then round(z.cogs, 2) end, 'costed_sales', case when z.loc = any (costret) and z.crev is not null then round(z.crev, 2) end,
        'gross_profit', case when z.loc = any (costret) and z.crev > 0 then round(z.crev - z.cogs, 2) end, 'gp_pct', case when z.loc = any (costret) and z.crev > 0 then round((z.crev - z.cogs) / z.crev * 100, 2) end,
        'uncosted_pct', case when z.loc = any (costret) and z.crev + coalesce(z.unk, 0) > 0 then round(coalesce(z.unk, 0) / (z.crev + coalesce(z.unk, 0)) * 100, 1) end,
        'cost_state', case when not (z.loc = any (costret)) then 'cost_hidden' when z.crev is null or z.crev <= 0 then 'cost_not_captured' else 'known' end) order by l.sort, z.loc), '[]'::jsonb) into ret_rows
    from (select s.loc, sum(s.gross) as gross, sum(s.returns_amt) as ret, sum(s.bills) as bills, c.crev, c.cogs, c.unk
            from public._rb4_sales_days(f, t, rets) s
            left join (select h.loc, sum((case h.src when 'sale' then 1 else -1 end) * (h.led_rev + h.fb_rev)) as crev, sum((case h.src when 'sale' then 1 else -1 end) * (h.led_cogs + h.fb_cogs)) as cogs,
                              sum((case h.src when 'sale' then 1 else -1 end) * h.unk_rev) as unk from public._cogs_lines72(f, t, costret) h group by 1) c on c.loc = s.loc
           group by s.loc, c.crev, c.cogs, c.unk) z join public.locations l on l.id = z.loc;

  select jsonb_build_object('runs', coalesce((select sum((e ->> 'runs')::int) from jsonb_array_elements(fac_rows) e), 0),
      'production_cost', (select sum((e ->> 'production_cost')::numeric) from jsonb_array_elements(fac_rows) e where e ->> 'cost_state' = 'known'),
      'items_not_costed', (select count(*) from jsonb_array_elements(fac_rows) e where e ->> 'cost_state' <> 'known')) into fac_tot;
  select jsonb_build_object('rows', jsonb_array_length(tr_rows), 'cost_value', (select sum((e ->> 'cost_value')::numeric) from jsonb_array_elements(tr_rows) e where e ->> 'cost_state' = 'known'),
      'transfer_value', (select sum((e ->> 'transfer_value')::numeric) from jsonb_array_elements(tr_rows) e where e -> 'transfer_value' <> 'null'::jsonb),
      'factory_margin', (select sum((e ->> 'margin')::numeric) from jsonb_array_elements(tr_rows) e where e -> 'margin' <> 'null'::jsonb),
      'rows_not_valued', (select count(*) from jsonb_array_elements(tr_rows) e where e -> 'transfer_value' = 'null'::jsonb)) into tr_tot;
  select jsonb_build_object('net_sales', (select sum((e ->> 'net_sales')::numeric) from jsonb_array_elements(ret_rows) e), 'gross_profit', (select sum((e ->> 'gross_profit')::numeric) from jsonb_array_elements(ret_rows) e where e -> 'gross_profit' <> 'null'::jsonb),
      'shops_without_cost', (select count(*) from jsonb_array_elements(ret_rows) e where e ->> 'cost_state' <> 'known')) into ret_tot;
  if basis = 'none' then notes := notes || jsonb_build_object('code', 'transfers_not_valued', 'field', 'transfer_valuation_basis'); end if;
  if basis = 'price_pct' and pct is null then notes := notes || jsonb_build_object('code', 'pct_not_set', 'field', 'transfer_price_pct'); end if;
  if cardinality(facs) = 0 then notes := notes || jsonb_build_object('code', 'no_factory_place', 'field', 'factory place'); end if;
  return jsonb_build_object('from', f, 'to', t, 'basis', basis, 'price_pct', pct, 'net_of_returns', net_on, 'cost_hidden', hidden, 'factory', jsonb_build_object('rows', fac_rows, 'totals', fac_tot),
    'transfers', jsonb_build_object('rows', tr_rows, 'totals', tr_tot), 'retail', jsonb_build_object('rows', ret_rows, 'totals', ret_tot), 'notes', notes,
    'statement', 'Shop gross profit is at ledger cost, the figure the system books. It is not reduced by a transfer value. The factory margin on transfers is shown next to it and the two are never netted here.');
end $$;

-- ---------- audit line for the CSV ----------
create or replace function public.rb4_log_export(p_key text, p_kind text, p_filters jsonb, p_rows int) returns void
language plpgsql security definer set search_path = public as $$
declare sid text; f jsonb := coalesce(p_filters, '{}'::jsonb); ok boolean; any_prod boolean; any_tgt boolean;
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_grant('export_data')) then raise exception 'not allowed'; end if;
  if p_key is null or p_key not in ('plan_vs_actual', 'order_status', 'dispatch_recon', 'consumption', 'cost_variance', 'run_yield', 'losses', 'wastage_dim', 'labour_productivity', 'capacity',
                                    'target_report', 'kpi_trend', 'factory_vs_retail', 'production_runs', 'capacity_ratings', 'sales_targets') then
    raise exception 'unknown_report';
  end if;
  select exists (select 1 from public.locations l where public._rb4_prod_view(l.id)) into any_prod;
  select exists (select 1 from public.locations l where public._rb4_target_view(l.id)) into any_tgt;
  ok := case
    when p_key in ('target_report', 'kpi_trend', 'sales_targets') then any_tgt
    when p_key = 'factory_vs_retail' then any_prod or any_tgt
    else any_prod end;
  if not coalesce(ok, false) then raise exception 'not allowed'; end if;
  if p_kind is null or lower(p_kind) !~ '^[a-z0-9_]{1,20}$' then raise exception 'bad_kind'; end if;
  if length(f::text) > 4000 then f := jsonb_build_object('truncated', true); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'export', 'report', p_key, jsonb_build_object('kind', lower(p_kind), 'rows', least(greatest(coalesce(p_rows, 0), 0), 100000000), 'filters', f));
end $$;

do $p$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('rb4_factory_vs_retail', 'rb4_log_export') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $p$;

notify pgrst, 'reload schema';

-- ===================== phase420.sql =====================
-- ============================================================
-- BOS tool · Phase 420 (RPT-B2 R1): HONESTY FIXES in the existing stock and purchase reports (audit docs/REPORTS_AUDIT_2.md, items #57 #69 #94 #98 and findings 6, 7, 10).
-- Paste after phase99. Additive and safe to paste twice. No old phase file is edited. Nothing here writes business data; every report stays OPEN to the roles that already hold
-- report_stock / report_purchase (no new grant, no setting is switched, nothing sits behind an OFF setting).
--
-- Rules kept (owner): a missing figure is shown as "not captured" naming the field or form, never as 0 and never as an estimate; no limit, default or price is invented
-- (a threshold that is not set is told in a notice); existing figures are not changed, columns and notices are added. The only value changes are the three the owner asked for:
-- a negative balance reads 'negative' (was 'low'), the expiry list uses ONE threshold, the supplier overdue is empty (not 0) where credit days are not set.
--
-- What this phase adds
--   1. Plumbing, so a report of engine 2 or 3 can be extended in place without copying its query:
--        * report_catalog2(): an engine-3 row (report_defs3) with the same key REPLACES the engine-2 entry (no duplicate in the list).
--        * report_run2(): after the normal answer, a private decorator  _r4d_<key>(filters, answer)  (if one exists) may add notes, sub-totals, hide cost columns.
--          Later phases (421 to 425) add decorators by creating a function; they never re-create report_run2 again.
--   2. #57 / #60-62  stock_balance (engine 3, same key and route): item-type filter, state 'negative', per-line "no cost recorded" flag, notice with the uncosted count,
--        sub-totals per place, per place kind and per item type (answer field "subtotals"), drill to the item ledger.
--   3. #69 expiry_soon (engine 3, same key): ONE threshold = rule report_expiry_soon_days if set, else the existing rule expiry_warn_days; batches with stock but no expiry date
--        are listed in a "no expiry captured" row per item and place (never "nothing expiring"); notices say which rule gave the threshold.
--   4. #94 p4_supplier_score: reads posted purchase bills, purchase returns (with reason) and quality checks; a leg that was never captured (GRN 04-1, bill check 06-4, PO 06-3)
--        is empty with the form code named (not 0).
--   5. #98 supplier_ageing: overdue is empty where the supplier has no credit days (it showed 0.00), with a notice. The age buckets stay on rule report_aging_buckets, no hidden default.
--   6. wastage_by_reason2(): the reason report without adding quantities of different units (one quantity per unit).
--   7. stock_reconcile(p_fix): unchanged for the owner, but the rewrite of the cache now leaves an audit line; stock_reconcile_fix(p_confirm) is the confirmed path the stock screen uses.
--   8. log_report_export4(): audit line for the CSV of the new report pages (same right as every export: owner or grant export_data).
-- ============================================================

-- ---------- 1. plumbing ----------
create or replace function public._r4_note(p_code text, p_en text, p_bn text, p_what text default null) returns jsonb
language sql immutable set search_path = public as $$
  select jsonb_strip_nulls(jsonb_build_object('code', p_code, 'what', p_what, 'text_en', p_en, 'text_bn', p_bn));
$$;
create or replace function public._r4_addnote(p_res jsonb, p_note jsonb) returns jsonb
language sql immutable set search_path = public as $$
  select jsonb_set(p_res, '{notes}', coalesce(p_res -> 'notes', '[]'::jsonb) || jsonb_build_array(p_note));
$$;
-- item types chosen in the filter (only codes that exist); null = no filter
create or replace function public._r4_types(p_flt jsonb) returns text[]
language sql stable security definer set search_path = public as $$
  select case when v is null then null else coalesce((select array_agg(t.code) from public.item_types t where t.code = any (v)), '{}') end
    from (select public.rpt_arr_text(p_flt -> 'item_types') as v) x;
$$;

create or replace function public.report_catalog2() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  return coalesce((select jsonb_agg(e) from jsonb_array_elements(public.report_catalog2_core()) e
                    where not exists (select 1 from public.report_defs3 d where d.key = e ->> 'key' and d.is_active)), '[]'::jsonb) || public.report_catalog3();
end $$;

create or replace function public.report_run2(p_key text, p_filters jsonb default '{}'::jsonb, p_group text default null, p_sort text default null, p_page int default 1) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb; flt jsonb := case when p_filters is not null and jsonb_typeof(p_filters) = 'object' then p_filters else '{}'::jsonb end;
begin
  if exists (select 1 from public.report_defs3 where key = p_key and is_active) then r := public.report_run3(p_key, p_filters, p_group, p_sort, p_page);
  else r := public.report_run2_core(p_key, p_filters, p_group, p_sort, p_page); end if;
  if p_key ~ '^[a-z0-9_]{2,40}$' and to_regprocedure('public._r4d_' || p_key || '(jsonb,jsonb)') is not null then      -- bos420: the in-place extension of this report
    execute format('select public.%I($1, $2)', '_r4d_' || p_key) into r using flt, r;
  end if;
  return r;
end $$;
revoke all on function public.report_catalog2(), public.report_run2(text, jsonb, text, text, int), public._r4_note(text, text, text, text), public._r4_addnote(jsonb, jsonb), public._r4_types(jsonb) from public, anon;
grant execute on function public.report_catalog2(), public.report_run2(text, jsonb, text, text, int) to authenticated;
revoke all on function public._r4_note(text, text, text, text), public._r4_addnote(jsonb, jsonb), public._r4_types(jsonb) from authenticated;

-- every decorator is private (run as definer, no access check of its own: report_run2 already checked the right)
create or replace function public._r4_lockdown() returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in select p.oid::regprocedure::text as sig from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname like '\_r4d\_%' or p.proname like '\_r4q\_%') loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig); n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public._r4_lockdown() from public, anon, authenticated;

-- ---------- 2. #57 / #60-62 stock_balance, in place (engine 3 row with the same key) ----------
create or replace function public._r3q_stock_balance(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with p as (select public.rpt_arr_text(flt -> 'categories') as cat, public._r4_types(flt) as ty, public.rpt_cost_ok() as cost)
  select jsonb_build_object('item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn),
      'item_type', coalesce(t.label_bn, it.item_type), 'item_type_en', coalesce(t.label_en, t.label_bn, it.item_type),
      'category', coalesce(it.category, '(none)'), 'location_bn', l.name_bn, 'location_en', coalesce(l.name_en, l.name_bn), 'qty', b.qty, 'unit', it.unit, 'min_stock', it.min_stock,
      'state', case when b.qty < 0 then 'negative' when it.min_stock is null then 'no_min' when b.qty <= it.min_stock then 'low' else 'ok' end,
      'avg_cost', case when p.cost then b.avg_cost end,
      'value', case when p.cost and b.avg_cost is not null then round(b.qty * b.avg_cost, 2) end,
      'cost_note', case when p.cost and b.qty <> 0 and b.avg_cost is null then 'no cost recorded' end,
      '_nc', case when p.cost and b.qty <> 0 and b.avg_cost is null then '["avg_cost","value"]'::jsonb end,
      'drill', format('#/stockrep/ledger?item=%s&loc=%s', it.id, b.location_id))
    from public.stock_balance b join public.items it on it.id = b.item_id join public.locations l on l.id = b.location_id
      left join public.item_types t on t.code = it.item_type cross join p
   where b.location_id = any (locs) and it.is_active and (p.cat is null or it.category = any (p.cat)) and (p.ty is null or it.item_type = any (p.ty));
$$;

-- sub-totals for the same filters: one helper used by the decorator and by the tests
create or replace function public._r4_levels_agg(p_locs int[], p_cat text[], p_ty text[], p_cost boolean) returns jsonb
language sql stable security definer set search_path = public as $$
  with x as (
    select b.item_id, b.location_id, b.qty, b.avg_cost, it.min_stock, coalesce(l.name_bn, '') as lbn, coalesce(l.name_en, l.name_bn, '') as len, coalesce(l.kind, '(not set)') as kind,
           coalesce(t.label_bn, it.item_type) as tbn, coalesce(t.label_en, t.label_bn, it.item_type) as ten, it.item_type
      from public.stock_balance b join public.items it on it.id = b.item_id join public.locations l on l.id = b.location_id left join public.item_types t on t.code = it.item_type
     where b.location_id = any (p_locs) and it.is_active and (p_cat is null or it.category = any (p_cat)) and (p_ty is null or it.item_type = any (p_ty))),
  a as (select 'place' as g, x.location_id::text as k, x.lbn as bn, x.len as en, count(*) as lines, count(*) filter (where x.qty <> 0) as stocked_lines,
          count(*) filter (where x.qty < 0) as negative_lines, count(*) filter (where x.qty <> 0 and x.avg_cost is null) as uncosted_lines,
          sum(round(x.qty * x.avg_cost, 2)) filter (where x.avg_cost is not null) as value from x group by x.location_id, x.lbn, x.len
        union all
        select 'kind', x.kind, x.kind, x.kind, count(*), count(*) filter (where x.qty <> 0), count(*) filter (where x.qty < 0), count(*) filter (where x.qty <> 0 and x.avg_cost is null),
          sum(round(x.qty * x.avg_cost, 2)) filter (where x.avg_cost is not null) from x group by x.kind
        union all
        select 'type', x.item_type, x.tbn, x.ten, count(*), count(*) filter (where x.qty <> 0), count(*) filter (where x.qty < 0), count(*) filter (where x.qty <> 0 and x.avg_cost is null),
          sum(round(x.qty * x.avg_cost, 2)) filter (where x.avg_cost is not null) from x group by x.item_type, x.tbn, x.ten)
  select jsonb_build_object(
    'place', coalesce((select jsonb_agg(jsonb_build_object('name', a.bn, 'name_en', a.en, 'lines', a.lines, 'negative_lines', a.negative_lines, 'uncosted_lines', case when p_cost then a.uncosted_lines end,
        'value', case when p_cost then coalesce(a.value, 0) end) order by a.bn) from a where a.g = 'place'), '[]'::jsonb),
    'kind', coalesce((select jsonb_agg(jsonb_build_object('name', a.bn, 'name_en', a.en, 'lines', a.lines, 'negative_lines', a.negative_lines, 'uncosted_lines', case when p_cost then a.uncosted_lines end,
        'value', case when p_cost then coalesce(a.value, 0) end) order by a.bn) from a where a.g = 'kind'), '[]'::jsonb),
    'type', coalesce((select jsonb_agg(jsonb_build_object('name', a.bn, 'name_en', a.en, 'lines', a.lines, 'negative_lines', a.negative_lines, 'uncosted_lines', case when p_cost then a.uncosted_lines end,
        'value', case when p_cost then coalesce(a.value, 0) end) order by a.bn) from a where a.g = 'type'), '[]'::jsonb),
    'lines', (select count(*) from x), 'negative_lines', (select count(*) from x where qty < 0), 'uncosted_lines', (select count(*) from x where qty <> 0 and avg_cost is null),
    'low_lines', (select count(*) from x where qty >= 0 and min_stock is not null and qty <= min_stock), 'no_min_lines', (select count(*) from x where qty >= 0 and min_stock is null),
    'value', case when p_cost then (select coalesce(sum(round(qty * avg_cost, 2)) filter (where avg_cost is not null), 0) from x) end);
$$;
revoke all on function public._r4_levels_agg(int[], text[], text[], boolean) from public, anon, authenticated;

create or replace function public._r4d_stock_balance(p_flt jsonb, p_res jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare agg jsonb; cost_ok boolean := public.rpt_cost_ok(); res jsonb := p_res; col jsonb; cols jsonb := '[]'::jsonb; sec jsonb := '[]'::jsonb; mcols jsonb;
begin
  agg := public._r4_levels_agg(public._r2_locs(p_flt), public.rpt_arr_text(p_flt -> 'categories'), public._r4_types(p_flt), cost_ok);
  res := jsonb_set(res, '{totals}', coalesce(res -> 'totals', '{}'::jsonb) || jsonb_build_object('lines', agg -> 'lines', 'low_lines', agg -> 'low_lines', 'no_min_lines', agg -> 'no_min_lines', 'negative_lines', agg -> 'negative_lines'));
  if not cost_ok then
    for col in select * from jsonb_array_elements(res -> 'columns') loop
      if col ->> 'key' not in ('avg_cost', 'value', 'cost_note') then cols := cols || jsonb_build_array(col); end if;
    end loop;
    res := jsonb_set(res, '{columns}', cols);
    res := jsonb_set(res, '{totals}', coalesce(res -> 'totals', '{}'::jsonb) - 'value');
    res := jsonb_set(res, '{rows}', coalesce((select jsonb_agg(r - 'avg_cost' - 'value' - 'cost_note' - '_nc') from jsonb_array_elements(res -> 'rows') r), '[]'::jsonb));
    res := public._r4_addnote(res, jsonb_build_object('code', 'cost_hidden'));
  else
    res := jsonb_set(res, '{totals}', coalesce(res -> 'totals', '{}'::jsonb) || jsonb_build_object('value', agg -> 'value'));
    if (agg ->> 'uncosted_lines')::int > 0 then
      res := public._r4_addnote(res, public._r4_note('data_needed',
        (agg ->> 'uncosted_lines') || ' stock line(s) with a quantity have no cost recorded. The value total leaves them out; their value is not captured (it is not zero). A cost is recorded by a purchase bill line with a unit cost, an opening entered with a cost, or a production post with a cost.',
        (agg ->> 'uncosted_lines') || 'টি স্টক লাইনে পরিমাণ আছে কিন্তু খরচ লেখা নেই। মোট মূল্যে এগুলো ধরা হয়নি; এদের মূল্য অজানা (শূন্য নয়)। খরচ লেখা হয় ক্রয় বিলের লাইনে দর দিলে, খরচসহ ওপেনিং দিলে বা খরচসহ উৎপাদন পোস্ট করলে।', 'unit cost'));
    end if;
  end if;
  if (agg ->> 'negative_lines')::int > 0 then
    res := public._r4_addnote(res, public._r4_note('data_needed',
      (agg ->> 'negative_lines') || ' line(s) are NEGATIVE: more went out than the book had (a sale beyond stock). State shows "negative", not "low". Open the negative and integrity list to see them with their source.',
      (agg ->> 'negative_lines') || 'টি লাইন ঋণাত্মক: বইয়ে যা ছিল তার চেয়ে বেশি বের হয়েছে (স্টকের বাইরে বিক্রি)। অবস্থা "ঋণাত্মক" দেখানো হয়, "কম" নয়।', 'negative stock'));
  end if;
  sec := jsonb_build_array(
    jsonb_build_object('id', 'by_place', 'title_bn', 'লোকেশন অনুযায়ী মোট', 'title_en', 'Totals by place', 'rows', agg -> 'place'),
    jsonb_build_object('id', 'by_kind', 'title_bn', 'লোকেশনের ধরন অনুযায়ী মোট', 'title_en', 'Totals by kind of place', 'rows', agg -> 'kind'),
    jsonb_build_object('id', 'by_type', 'title_bn', 'আইটেমের ধরন অনুযায়ী মোট', 'title_en', 'Totals by item type', 'rows', agg -> 'type'));
  mcols := '[{"key":"name","label_bn":"নাম","label_en":"Name","type":"text"},{"key":"lines","label_bn":"লাইন","label_en":"Lines","type":"int"},{"key":"negative_lines","label_bn":"ঋণাত্মক","label_en":"Negative","type":"int"}]'::jsonb
          || case when cost_ok then '[{"key":"uncosted_lines","label_bn":"খরচ লেখা নেই","label_en":"No cost recorded","type":"int"},{"key":"value","label_bn":"মূল্য (খরচ জানা অংশে)","label_en":"Value (costed part)","type":"money"}]'::jsonb else '[]'::jsonb end;
  sec := (select jsonb_agg(s || jsonb_build_object('columns', mcols)) from jsonb_array_elements(sec) s);
  return jsonb_set(res, '{subtotals}', sec);
end $$;

insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('stock_balance', 'S2', 'stock', 'স্টক ব্যালান্স', 'Stock balance', 'Stock balance',
  '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["item_type","ধরন","Type","text"],["item_type_en","Type (EN)","Type (EN)","text"],["category","ক্যাটাগরি","Category","text"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["qty","আছে","On hand","num"],["unit","একক","Unit","text"],["min_stock","ন্যূনতম","Minimum","num"],["state","অবস্থা","State","text"],["avg_cost","গড় খরচ","Avg cost","money"],["value","মূল্য","Value","money"],["cost_note","খরচ","Cost","text"]]'::jsonb,
  array['value'], 'item_name', 'asc', array['locations','brands','categories','item_types'], true, false, false, 4201)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
  sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

-- ---------- 3. #69 expiry_soon, in place: one threshold, and the batches that have no expiry ----------
create or replace function public._r3q_expiry_soon(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with t as (select (now() at time zone 'Asia/Dhaka')::date as today, coalesce(public.rule_num('report_expiry_soon_days'), public.rule_num('expiry_warn_days')) as thr,
                    public.rpt_arr_text(flt -> 'categories') as cat, public.rpt_cost_ok() as cost),
  dated as (
    select it.id as item_id, it.code, it.name_bn, coalesce(it.name_en, it.name_bn) as name_en, l.id as loc_id, l.name_bn as lbn, coalesce(l.name_en, l.name_bn) as len,
           (b.made_at at time zone 'Asia/Dhaka')::date as made_on, (b.expires_at at time zone 'Asia/Dhaka')::date as exp_on, b.qty_remaining as qty, it.unit, sb.avg_cost, t.today, t.cost
      from public.stock_batches b join public.items it on it.id = b.item_id join public.locations l on l.id = b.location_id
        left join public.stock_balance sb on sb.item_id = b.item_id and sb.location_id = b.location_id cross join t
     where b.qty_remaining > 0 and b.expires_at is not null and b.location_id = any (locs) and (t.cat is null or it.category = any (t.cat))
       and (b.expires_at at time zone 'Asia/Dhaka')::date <= t.today + coalesce(t.thr::int, -1)),
  noexp as (
    select it.id as item_id, it.code, it.name_bn, coalesce(it.name_en, it.name_bn) as name_en, l.id as loc_id, l.name_bn as lbn, coalesce(l.name_en, l.name_bn) as len,
           min((b.made_at at time zone 'Asia/Dhaka')::date) as made_on, sum(b.qty_remaining) as qty, count(*) as batches, it.unit, sb.avg_cost, t.cost
      from public.stock_batches b join public.items it on it.id = b.item_id join public.locations l on l.id = b.location_id
        left join public.stock_balance sb on sb.item_id = b.item_id and sb.location_id = b.location_id cross join t
     where b.qty_remaining > 0 and b.expires_at is null and b.location_id = any (locs) and (t.cat is null or it.category = any (t.cat))
     group by it.id, it.code, it.name_bn, it.name_en, l.id, l.name_bn, l.name_en, it.unit, sb.avg_cost, t.cost)
  select jsonb_build_object('item_code', d.code, 'item_name', d.name_bn, 'item_name_en', d.name_en, 'location_id', d.loc_id, 'location_bn', d.lbn, 'location_en', d.len, 'made_on', d.made_on, 'expires_on', d.exp_on,
      'n_dated', 1, 'n_expired', case when d.exp_on < d.today then 1 else 0 end,
      'days_left', d.exp_on - d.today, 'qty', d.qty, 'unit', d.unit, 'batches', 1, 'state', case when d.exp_on < d.today then 'expired' else 'soon' end,
      'value', case when d.cost and d.avg_cost is not null then round(d.qty * d.avg_cost, 2) end, 'drill', format('#/batchrep/batches?item=%s&loc=%s', d.item_id, d.loc_id))
    from dated d
  union all
  select jsonb_build_object('item_code', n.code, 'item_name', n.name_bn, 'item_name_en', n.name_en, 'location_id', n.loc_id, 'location_bn', n.lbn, 'location_en', n.len, 'made_on', n.made_on, 'expires_on', null,
      'n_dated', 0, 'n_expired', 0,
      'days_left', null, 'qty', n.qty, 'unit', n.unit, 'batches', n.batches, 'state', 'no_expiry',
      'value', case when n.cost and n.avg_cost is not null then round(n.qty * n.avg_cost, 2) end, '_nc', '["expires_on","days_left"]'::jsonb,
      'drill', format('#/batchrep/batches?item=%s&loc=%s', n.item_id, n.loc_id))
    from noexp n;
$$;

create or replace function public._r4d_expiry_soon(p_flt jsonb, p_res jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb := p_res; thr numeric; src text; cost_ok boolean := public.rpt_cost_ok(); nb bigint; ni bigint; locs int[] := public._r2_locs(p_flt); cat text[] := public.rpt_arr_text(p_flt -> 'categories');
        col jsonb; cols jsonb := '[]'::jsonb;
begin
  thr := public.rule_num('report_expiry_soon_days');
  if thr is not null then src := 'report_expiry_soon_days';
  else thr := public.rule_num('expiry_warn_days'); src := case when thr is not null then 'expiry_warn_days' end; end if;
  if thr is null then
    res := public._r4_addnote(res, public._r4_note('data_needed', 'No "days ahead" rule is set (report_expiry_soon_days or expiry_warn_days), so only batches already past their expiry are listed.',
      'কত দিন আগে সতর্ক করা হবে তার নিয়ম বসানো নেই (report_expiry_soon_days বা expiry_warn_days); তাই শুধু মেয়াদ-শেষ ব্যাচ দেখাচ্ছে।', 'expiry_warn_days'));
  else
    res := public._r4_addnote(res, public._r4_note('info', 'Batches that expire within ' || thr::int || ' day(s) are listed (threshold from the rule ' || src || '); the same threshold is used on the stock reports page.',
      'আগামী ' || thr::int || ' দিনের মধ্যে মেয়াদ শেষ হবে এমন ব্যাচ দেখানো হচ্ছে (সীমা নিয়ম ' || src || ' থেকে); স্টক রিপোর্ট পাতাতেও একই সীমা।'));
  end if;
  select count(*), count(distinct b.item_id) into nb, ni from public.stock_batches b join public.items it on it.id = b.item_id
   where b.qty_remaining > 0 and b.expires_at is null and b.location_id = any (locs) and (cat is null or it.category = any (cat));
  if nb > 0 then
    res := public._r4_addnote(res, public._r4_note('data_needed', nb || ' batch(es) of ' || ni || ' item(s) hold stock with NO expiry date captured. They are listed as "no expiry" rows; they are not "safe". Expiry is captured only when the item has a shelf-life rule (Settings > shelf life) or the batch is entered with an expiry.',
      nb || 'টি ব্যাচে (' || ni || 'টি আইটেম) স্টক আছে কিন্তু মেয়াদ লেখা নেই। এগুলো "মেয়াদ নেই" সারিতে দেখানো হয়েছে; এগুলো নিরাপদ নয়। আইটেমের শেলফ-লাইফ নিয়ম থাকলে বা ব্যাচে মেয়াদ দিলে তবেই মেয়াদ লেখা হয়।', 'shelf_life_rules / expires_at'));
  end if;
  res := jsonb_set(res, '{totals}', (coalesce(res -> 'totals', '{}'::jsonb) - 'n_dated' - 'n_expired') || jsonb_build_object('batches', coalesce((res #>> '{totals,n_dated}')::numeric::int, 0), 'expired_batches', coalesce((res #>> '{totals,n_expired}')::numeric::int, 0)));
  if not cost_ok then
    for col in select * from jsonb_array_elements(res -> 'columns') loop if col ->> 'key' <> 'value' then cols := cols || jsonb_build_array(col); end if; end loop;
    res := jsonb_set(res, '{columns}', cols);
    res := jsonb_set(res, '{totals}', coalesce(res -> 'totals', '{}'::jsonb) - 'value');
    res := jsonb_set(res, '{rows}', coalesce((select jsonb_agg(r - 'value') from jsonb_array_elements(res -> 'rows') r), '[]'::jsonb));
    res := public._r4_addnote(res, jsonb_build_object('code', 'cost_hidden'));
  end if;
  return res;
end $$;

insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('expiry_soon', 'S3', 'stock', 'মেয়াদ শেষ / শিগগির শেষ', 'Expired and expiring soon', 'Expiry শেষ / শিগগির শেষ',
  '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["made_on","তৈরি","Made","date"],["expires_on","মেয়াদ শেষ","Expires","date"],["days_left","বাকি দিন","Days left","int"],["qty","পরিমাণ (বাকি)","Qty left","num"],["unit","একক","Unit","text"],["batches","ব্যাচ","Batches","int"],["state","অবস্থা","State","text"],["value","আনুমানিক মূল্য","Approx. value","money"]]'::jsonb,
  array['n_dated','n_expired','value'], 'days_left', 'asc', array['locations','brands','categories'], true, false, false, 4202)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
  sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

-- ---------- 4. #94 supplier scorecard: bills, returns and quality checks are read; a leg never captured is empty with its form code, not 0 ----------
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
  pb as (                                                                    -- bos420: posted purchase bills and purchase returns of the period
    select lower(btrim(s.name)) as sk, min(btrim(s.name)) as sname, count(*) filter (where b.kind = 'bill') as bills_n, coalesce(sum(b.total) filter (where b.kind = 'bill'), 0) as bills_total,
           count(*) filter (where b.kind = 'return') as returns_n, coalesce(sum(b.total) filter (where b.kind = 'return'), 0) as returns_total
      from public.purchase_bills b join public.suppliers s on s.id = b.supplier_id
     where b.status = 'posted' and b.bill_date between d1 and d2 and b.location_id = any (locs) group by lower(btrim(s.name))),
  qc as (                                                                    -- bos420: quality checks of goods received (bill or GRN sheet), the latest status of each source
    select z.sk, min(z.sname) as sname, count(*) as qc_n, count(*) filter (where z.st in ('hold', 'reject')) as qc_bad
      from (select coalesce(lower(btrim(sb.name)), lower(btrim(coalesce(s2.name, e.data ->> 'supplier')))) as sk, coalesce(btrim(sb.name), btrim(coalesce(s2.name, e.data ->> 'supplier'))) as sname,
                   (select q.status from public.qc_records q where q.source_type = c.source_type and q.source_id = c.source_id order by q.created_at desc, q.id desc limit 1) as st
              from (select distinct source_type, source_id from public.qc_records
                     where source_type = 'grn' and (created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and location_id = any (locs)) c
              left join public.purchase_bills bb on bb.id = c.source_id left join public.suppliers sb on sb.id = bb.supplier_id
              left join public.entries e on e.id = c.source_id and e.form_code = '04-1' left join public.suppliers s2 on s2.id::text = e.data ->> 'supplier_id') z
     where z.sk is not null and z.sk <> '' group by z.sk),
  keys as (select sk, sname from grn union select sk, sname from bil union select sk, sname from po union select sk, min(sname) from rr group by sk
           union select sk, sname from pb union select sk, sname from qc)
  select jsonb_build_object('supplier', k.sname,
    'grns', g.grns, 'lines', g.lines, 'short_lines', g.short_lines, 'rejected', g.rejected, 'held', g.held, 'reduced', g.reduced,
    'bills_checked', b.bills, 'short_claims', b.short_claims, 'return_claims', b.return_claims,
    'pos', p.pos, 'late_pos', case when coalesce(p.pos_matched, 0) > 0 then p.late_pos end, 'overdue_open', p.overdue_open,
    'rate_change_pct', case when c.chg is not null then round(c.chg, 2) end, 'rate_items', coalesce(c.items, 0),
    'bills_n', coalesce(x.bills_n, 0), 'bills_total', coalesce(x.bills_total, 0), 'returns_n', coalesce(x.returns_n, 0), 'returns_total', coalesce(x.returns_total, 0),
    'return_pct', case when coalesce(x.bills_total, 0) > 0 then round(x.returns_total * 100.0 / x.bills_total, 1) end,
    'qc_n', q.qc_n, 'qc_bad', q.qc_bad, 'qc_bad_pct', case when q.qc_n > 0 then round(q.qc_bad * 100.0 / q.qc_n, 1) end,
    'not_captured', nullif(concat_ws(', ', case when g.sk is null then '04-1' end, case when b.sk is null then '06-4' end, case when p.sk is null then '06-3' end, case when q.sk is null then 'QC' end), ''),
    '_nc', (select coalesce(jsonb_agg(z), '[]'::jsonb) from unnest(array[
      case when g.sk is null then 'grns' end, case when g.sk is null then 'lines' end, case when g.sk is null then 'short_lines' end, case when g.sk is null then 'rejected' end,
      case when g.sk is null then 'held' end, case when g.sk is null then 'reduced' end,
      case when b.sk is null then 'bills_checked' end, case when b.sk is null then 'short_claims' end, case when b.sk is null then 'return_claims' end,
      case when p.sk is null then 'pos' end, case when p.sk is null then 'late_pos' end, case when p.sk is null then 'overdue_open' end,
      case when q.sk is null then 'qc_n' end, case when q.sk is null then 'qc_bad' end, case when q.sk is null then 'qc_bad_pct' end]) z where z is not null))
    from (select sk, min(sname) as sname from keys where sk is not null and sk <> '' group by sk) k
    left join grn g on g.sk = k.sk left join bil b on b.sk = k.sk left join po p on p.sk = k.sk left join rc c on c.sk = k.sk left join pb x on x.sk = k.sk left join qc q on q.sk = k.sk;
$$;

create or replace function public._r4d_p4_supplier_score(p_flt jsonb, p_res jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb := p_res; d1 date := (p_res #>> '{meta,from}')::date; d2 date := (p_res #>> '{meta,to}')::date; locs int[] := public._r2_locs(p_flt); n_grn bigint; n_bil bigint; n_po bigint; tot jsonb;
begin
  if d1 is null or d2 is null then return res; end if;
  select count(*) into n_grn from public.entries e where e.form_code = '04-1' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs);
  select count(*) into n_bil from public.entries e where e.form_code = '06-4' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs);
  select count(*) into n_po from public._p26_po(d1, d2, locs);
  tot := coalesce(res -> 'totals', '{}'::jsonb);
  if n_grn = 0 then tot := tot - 'grns' - 'lines' - 'short_lines' - 'rejected' - 'held' - 'reduced';
    res := public._r4_addnote(res, public._r4_note('data_needed', 'No goods-received sheet (04-1) was captured in this period: the GRN columns are empty (not captured), not 0. Purchase bills below come from posted bills.',
      'এই সময়ে কোনো মাল-গ্রহণ শিট (০৪-১) লেখা হয়নি: GRN-এর কলাম ফাঁকা (লেখা হয়নি), ০ নয়। ক্রয় বিলের কলাম পোস্ট করা বিল থেকে এসেছে।', '04-1')); end if;
  if n_bil = 0 then tot := tot - 'bills_checked' - 'short_claims' - 'return_claims';
    res := public._r4_addnote(res, public._r4_note('data_needed', 'No supplier bill check (06-4) was captured in this period: bills checked and claims are empty (not captured), not 0.',
      'এই সময়ে সরবরাহকারীর বিল যাচাই (০৬-৪) লেখা হয়নি: যাচাই করা বিল ও দাবির কলাম ফাঁকা (লেখা হয়নি), ০ নয়।', '06-4')); end if;
  if n_po = 0 then tot := tot - 'pos' - 'late_pos' - 'overdue_open';
    res := public._r4_addnote(res, public._r4_note('data_needed', 'No purchase order (06-3) was captured in this period: the PO columns are empty (not captured), not 0.',
      'এই সময়ে কোনো ক্রয় অর্ডার (০৬-৩) লেখা হয়নি: PO-এর কলাম ফাঁকা (লেখা হয়নি), ০ নয়।', '06-3')); end if;
  res := public._r4_addnote(res, public._r4_note('info', 'Purchase returns come from posted purchase returns (reason on the return). Quality checks are counted for goods-received checks whose source is a posted bill or a GRN sheet; a check on a source that has no supplier is not counted.',
    'ক্রয় ফেরত পোস্ট করা ফেরত থেকে। কোয়ালিটি চেক গোনা হয় যেগুলোর উৎস পোস্ট করা বিল বা GRN শিট; যে উৎসে সরবরাহকারী নেই তা গোনা হয়নি।'));
  return jsonb_set(res, '{totals}', tot);
end $$;

insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('p4_supplier_score', 'P4', 'purchase', 'সাপ্লায়ার স্কোরকার্ড', 'Supplier scorecard', 'Supplier স্কোরকার্ড',
  '[["supplier","সাপ্লায়ার","Supplier","text"],["bills_n","ক্রয় বিল (পোস্টেড)","Purchase bills","int"],["bills_total","ক্রয় বিলের টাকা","Bills amount","money"],["returns_n","ক্রয় ফেরত","Purchase returns","int"],["returns_total","ফেরতের টাকা","Returns amount","money"],["return_pct","ফেরত % (টাকার)","Return % (amount)","pct"],["qc_n","কোয়ালিটি চেক","Quality checks","int"],["qc_bad","আটক/বাতিল","Held or rejected","int"],["qc_bad_pct","আটক/বাতিল %","Held or rejected %","pct"],["grns","গ্রহণ রসিদ","GRNs","int"],["lines","লাইন","Lines","int"],["short_lines","কম পাওয়া লাইন","Short lines","int"],["rejected","ফেরত লাইন","Returned lines","int"],["held","আটক লাইন","Held lines","int"],["reduced","দর কমানো লাইন","Reduced-rate lines","int"],["bills_checked","যাচাই বিল","Bills checked","int"],["short_claims","ঘাটতির দাবি","Shortage claims","int"],["return_claims","ফেরতের দাবি","Return claims","int"],["pos","পারচেজ অর্ডার","POs","int"],["late_pos","দেরিতে আসা PO","Late POs","int"],["overdue_open","মেয়াদ পেরোনো খোলা PO","Overdue open POs","int"],["rate_change_pct","গড় দর বদল %","Avg rate change %","pct"],["rate_items","তুলনার আইটেম","Items compared","int"],["not_captured","লেখা হয়নি (ফর্ম)","Not captured (form)","text"]]'::jsonb,
  array['bills_n','bills_total','returns_n','returns_total','qc_n','qc_bad','grns','lines','short_lines','rejected','held','reduced','bills_checked','short_claims','return_claims','pos','late_pos','overdue_open'], 'rejected', 'desc', array['locations'], false, true, false, 2602)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
  sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

-- ---------- 5. #98 supplier_ageing: overdue is empty (not 0.00) where the supplier has no credit days ----------
create or replace function public._r4d_supplier_ageing(p_flt jsonb, p_res jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb := p_res; rw jsonb; rows_ jsonb := '[]'::jsonb; n_all bigint; n_page int := 0; names text;
begin
  for rw in select * from jsonb_array_elements(coalesce(res -> 'rows', '[]'::jsonb)) loop
    if rw -> 'credit_days' is null or jsonb_typeof(rw -> 'credit_days') = 'null' then
      rw := (rw - 'overdue') || jsonb_build_object('overdue', null, '_nc', jsonb_build_array('overdue', 'credit_days')); n_page := n_page + 1;
    end if;
    rows_ := rows_ || jsonb_build_array(rw);
  end loop;
  res := jsonb_set(res, '{rows}', rows_);
  select count(*), string_agg(s.name, ', ' order by s.name) into n_all, names from public.suppliers s
   where s.credit_days is null and exists (select 1 from public._sup_open(s.id) o where o.open_amt > 0);
  if n_all > 0 then
    res := public._r4_addnote(res, public._r4_note('data_needed', n_all || ' supplier(s) with open payables have NO credit days set (' || left(names, 160) || '). Their overdue amount cannot be worked out: it is shown as "not captured", not as 0.00. Set the credit days on the supplier (Settings > Suppliers).',
      'খোলা দেনা আছে এমন ' || n_all || ' জন সরবরাহকারীর বাকির মেয়াদ (দিন) বসানো নেই (' || left(names, 160) || ')। তাদের মেয়াদ-পার অঙ্ক হিসাব করা যায় না: ০.০০ নয়, "লেখা হয়নি" দেখানো হয়। সরবরাহকারীর তথ্যে বাকির মেয়াদ বসান।', 'credit_days'));
  end if;
  return res;
end $$;

-- the same flag for the payables screen (supplier_dues / payables_summary show 0 overdue where credit days are empty): the suppliers that cannot be judged
create or replace function public.supplier_credit_gaps() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_access('purchase') or public._pur_ok(null)) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('supplier_id', s.id, 'name', s.name) order by s.name) from public.suppliers s
                    where s.credit_days is null and exists (select 1 from public._sup_open(s.id) o where o.open_amt > 0)), '[]'::jsonb);
end $$;
revoke all on function public.supplier_credit_gaps() from public, anon;
grant execute on function public.supplier_credit_gaps() to authenticated;

-- ---------- 6. wastage by reason without adding different units ----------
create or replace function public.wastage_by_reason2(p_loc int default null, p_from date default null, p_to date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 30); t date := coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date);
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('reason_code', r.reason_code, 'label_bn', r.lbn, 'label_mix', r.lmix, 'label_en', r.len, 'entries', r.entries, 'items', r.items,
        'qty', case when jsonb_array_length(r.units) = 1 then (r.units -> 0 ->> 'qty')::numeric end, 'unit', case when jsonb_array_length(r.units) = 1 then r.units -> 0 ->> 'unit' end,
        'mixed_units', jsonb_array_length(r.units) > 1, 'units', r.units) order by r.entries desc, r.reason_code)
    from (select g.reason_code, g.lbn, g.lmix, g.len, sum(g.entries) as entries, sum(g.items) as items,
                 jsonb_agg(jsonb_build_object('unit', g.unit, 'qty', g.qty, 'entries', g.entries) order by g.unit) as units
            from (select w.reason_code, coalesce(o.label_bn, w.reason_code) as lbn, coalesce(o.label_mix, o.label_bn, w.reason_code) as lmix, coalesce(o.label_en, w.reason_code) as len,
                         coalesce(public._item_base(w.item_id), '?') as unit, round(sum(w.qty), 4) as qty, count(*) as entries, count(distinct w.item_id) as items
                    from public.stock_wastage w left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = w.reason_code
                   where public.can_loc(w.location_id) and (p_loc is null or w.location_id = p_loc) and (w.made_at at time zone 'Asia/Dhaka')::date between f and t
                   group by w.reason_code, o.label_bn, o.label_mix, o.label_en, coalesce(public._item_base(w.item_id), '?')) g
           group by g.reason_code, g.lbn, g.lmix, g.len) r), '[]'::jsonb);
end $$;
revoke all on function public.wastage_by_reason2(int, date, date) from public, anon;
grant execute on function public.wastage_by_reason2(int, date, date) to authenticated;

-- ---------- 7. stock_reconcile: the rewrite of the cache leaves an audit line; the stock screen uses the confirmed path ----------
-- stock_reconcile(false) is unchanged (a read). stock_reconcile(true) is owner only as before and now writes one audit line (action stock_reconcile_fix) when it changed a row.
create or replace function public.stock_reconcile(p_fix boolean default false)
returns table (item_id uuid, location_id int, ledger_qty numeric, cached_qty numeric, qty_diff numeric, cached_avg numeric, replay_avg numeric)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare r record; l record; q numeric; a numeric; bq numeric; bavg numeric; n int := 0; sid text; log_ jsonb := '[]'::jsonb;
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
        n := n + 1; if n <= 50 then log_ := log_ || jsonb_build_array(jsonb_build_object('item_id', r.iid, 'location_id', r.lid, 'old_qty', bq, 'new_qty', q, 'old_avg', bavg, 'new_avg', a)); end if;   -- bos420
      end if;
      return next;
    end if;
  end loop;
  if p_fix and n > 0 then                                                                                                   -- bos420: the cache was rewritten, say who and what
    select p.staff_id into sid from public.profiles p where p.id = auth.uid();
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
      values (auth.uid(), sid, 'stock_reconcile_fix', 'stock_balance', null, jsonb_build_object('rows_fixed', n, 'confirmed', coalesce(current_setting('bos.reconcile_confirm', true), '') = 'yes', 'first_rows', log_));
  end if;
end $$;

-- the confirmed path: owner only, the owner types the word FIX, one audit line (the stock screen calls this, not stock_reconcile(true))
create or replace function public.stock_reconcile_fix(p_confirm text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int; sid text;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_confirm is distinct from 'FIX' then raise exception 'confirm_required'; end if;
  perform set_config('bos.reconcile_confirm', 'yes', true);
  select count(*) into n from public.stock_reconcile(true);
  select p.staff_id into sid from public.profiles p where p.id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'stock_reconcile_confirm', 'stock_balance', null, jsonb_build_object('rows_fixed', n, 'typed', 'FIX'));
  return jsonb_build_object('fixed', n);
end $$;
revoke all on function public.stock_reconcile_fix(text) from public, anon;
grant execute on function public.stock_reconcile_fix(text) to authenticated;

-- ---------- 8. export audit line for the new report pages ----------
create or replace function public._r4_export_keys() returns text[]
language sql immutable set search_path = public as $$
  select array['stock_ledger','stock_recon','batch_stock','fg_ageing','unsold_by_batch','fg_distribution','expired_damaged_unsold','batch_trace','stockx_reorder','stockx_expiry','stockx_wastage'];
$$;
create or replace function public.log_report_export4(p_key text, p_kind text, p_filters jsonb, p_rows int) returns void
language plpgsql security definer set search_path = public as $$
declare sid text; f jsonb := coalesce(p_filters, '{}'::jsonb);
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_grant('export_data')) then raise exception 'not allowed'; end if;
  if p_key is null or not (p_key = any (public._r4_export_keys())) then raise exception 'unknown_report'; end if;
  if p_kind is null or lower(p_kind) !~ '^[a-z0-9_]{1,20}$' then raise exception 'bad_kind'; end if;
  if length(f::text) > 4000 then f := jsonb_build_object('truncated', true); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'export', 'report', p_key, jsonb_build_object('kind', lower(p_kind), 'rows', least(greatest(coalesce(p_rows, 0), 0), 100000000), 'filters', f));
end $$;
revoke all on function public._r4_export_keys() from public, anon, authenticated;
revoke all on function public.log_report_export4(text, text, jsonb, int) from public, anon;
grant execute on function public.log_report_export4(text, text, jsonb, int) to authenticated;

select public._r3_lockdown();
select public._r4_lockdown();
notify pgrst, 'reload schema';

-- ===================== phase421.sql =====================
-- ============================================================
-- BOS tool · Phase 421 (RPT-B2 R2a): stock movement reports, in place or new, all on the existing report engine 3 (viewer #/report/<key>, CSV and print there).
-- Needs phase420 (the decorator hook). Paste after phase420. Safe to paste twice. Read-only reports; they stay OPEN to report_stock holders; nothing is behind a setting.
--   #64 transfers_register     every transfer (sent, received, short, in transit, cancelled) with the shortage claim state; transfers_gap stays the exceptions-only view
--   #66 k2_count_variance      EXTENDED in place: the paper count sheets (04-3) AND the counts typed in the app (count adjust), with the value of the difference
--   #71 stock_adjustments      the stock adjustment history: who, why, how much, what it is worth
--   #77 wastage_rate           wastage as a share of stock handled, with the denominator shown (opening + received); value share of sales shown beside it
-- A value without a cost is empty with the basis named; a share without a denominator is empty (data not captured), never 0.
-- ============================================================

-- ---------- #64 all transfers ----------
create or replace function public._r3q_transfers_register(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with t as (select (now() at time zone 'Asia/Dhaka')::date as today, public.rpt_cost_ok() as cost)
  select jsonb_build_object('sent_day', (x.sent_at at time zone 'Asia/Dhaka')::date, 'from_bn', lf.name_bn, 'from_en', coalesce(lf.name_en, lf.name_bn), 'to_bn', lt.name_bn, 'to_en', coalesce(lt.name_en, lt.name_bn),
      'item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn), 'unit', public._item_base(it.id),
      'sent_qty', x.qty, 'received_qty', x.received_qty,
      'short_qty', case when x.status = 'received' then round(x.qty - coalesce(x.received_qty, x.qty), 4) end,
      'in_transit_qty', case when x.status = 'sent' then x.qty end,
      'flag', case when x.status = 'sent' then 'in_transit' when x.status = 'cancelled' then 'cancelled' when x.qty - coalesce(x.received_qty, x.qty) > 0 then 'short' else 'ok' end,
      'days_in_transit', case when x.status = 'sent' then t.today - (x.sent_at at time zone 'Asia/Dhaka')::date end,
      'received_day', (x.received_at at time zone 'Asia/Dhaka')::date, 'sent_staff', x.sent_staff, 'received_staff', x.received_staff,
      'note', coalesce(x.receive_note, x.note), 'claim', st.status,
      'value', case when t.cost then (select case when bool_and(l.unit_cost is not null) then round(sum(-l.qty_delta * l.unit_cost), 2) end from public.stock_ledger l
                                       where l.ref_type = 'transfer' and l.ref_id = x.id::text and l.reason = 'transfer_out') end,
      'short_value', case when t.cost and st.id is not null then st.value end,
      '_nc', (select coalesce(jsonb_agg(z), '[]'::jsonb) from unnest(array[
                case when t.cost and not exists (select 1 from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = x.id::text and l.reason = 'transfer_out' and l.unit_cost is null) then null
                     when t.cost then 'value' end,
                case when t.cost and st.id is not null and st.value is null then 'short_value' end]) z where z is not null),
      'drill', format('#/stockrep/ledger?item=%s&loc=%s', it.id, x.from_location_id))
    from public.stock_transfers x join public.items it on it.id = x.item_id join public.locations lf on lf.id = x.from_location_id join public.locations lt on lt.id = x.to_location_id
      left join public.shortage_transit st on st.transfer_id = x.id cross join t
   where (x.sent_at at time zone 'Asia/Dhaka')::date between d1 and d2 and (x.from_location_id = any (locs) or x.to_location_id = any (locs));
$$;

create or replace function public._r4d_transfers_register(p_flt jsonb, p_res jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb := p_res; cost_ok boolean := public.rpt_cost_ok(); col jsonb; cols jsonb := '[]'::jsonb; n_all bigint; n_sh bigint; n_tr bigint; n_nc bigint; d1 date := (p_res #>> '{meta,from}')::date; d2 date := (p_res #>> '{meta,to}')::date;
        locs int[] := public._r2_locs(p_flt);
begin
  if d1 is null then return res; end if;
  select count(*), count(*) filter (where x.status = 'received' and x.qty - coalesce(x.received_qty, x.qty) > 0), count(*) filter (where x.status = 'sent') into n_all, n_sh, n_tr
    from public.stock_transfers x where (x.sent_at at time zone 'Asia/Dhaka')::date between d1 and d2 and (x.from_location_id = any (locs) or x.to_location_id = any (locs));
  res := public._r4_addnote(res, public._r4_note('info', n_all || ' transfer(s) in the period: ' || n_tr || ' still in transit, ' || n_sh || ' received short. This list shows ALL transfers; "Transfers not received or short" shows only the exceptions. Quantities are in each item''s own base unit, so they are not added up.',
    'এই সময়ে ' || n_all || 'টি ট্রান্সফার: ' || n_tr || 'টি পথে, ' || n_sh || 'টি কম পৌঁছেছে। এই তালিকায় সব ট্রান্সফার; "পৌঁছায়নি / কম পৌঁছেছে" রিপোর্টে শুধু ব্যতিক্রম। পরিমাণ প্রতিটি আইটেমের নিজের এককে, তাই যোগ করা হয়নি।'));
  if cost_ok then
    select count(*) into n_nc from public.shortage_transit st join public.stock_transfers x on x.id = st.transfer_id
     where st.value is null and (x.sent_at at time zone 'Asia/Dhaka')::date between d1 and d2 and (x.from_location_id = any (locs) or x.to_location_id = any (locs));
    if n_nc > 0 then res := public._r4_addnote(res, public._r4_note('data_needed', n_nc || ' short transfer(s) have no cost at send, so their value is not captured (it is not zero). The owner enters the cost on the shortage record.',
      n_nc || 'টি কম-পৌঁছানো ট্রান্সফারে পাঠানোর সময়ের খরচ নেই, তাই মূল্য লেখা হয়নি (শূন্য নয়)। মালিক ঘাটতির রেকর্ডে খরচ বসান।', 'shortage_transit.value')); end if;
  else
    for col in select * from jsonb_array_elements(res -> 'columns') loop if col ->> 'key' not in ('value', 'short_value') then cols := cols || jsonb_build_array(col); end if; end loop;
    res := jsonb_set(res, '{columns}', cols); res := public._r4_addnote(res, jsonb_build_object('code', 'cost_hidden'));
  end if;
  return res;
end $$;

insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('transfers_register', 'S4', 'stock', 'সব ট্রান্সফার (পাঠানো, পৌঁছানো, কম, পথে)', 'All transfers (sent, received, short, in transit)', 'সব Transfer (sent, received, short, পথে)',
  '[["sent_day","পাঠানো","Sent","date"],["from_bn","কোথা থেকে","From","text"],["from_en","From (EN)","From (EN)","text"],["to_bn","কোথায়","To","text"],["to_en","To (EN)","To (EN)","text"],["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["unit","একক","Unit","text"],["sent_qty","পাঠানো","Sent qty","num"],["received_qty","পৌঁছেছে","Received qty","num"],["short_qty","কম","Short","num"],["in_transit_qty","পথে","In transit","num"],["flag","অবস্থা","State","text"],["days_in_transit","পথে দিন","Days in transit","int"],["received_day","গ্রহণ","Received","date"],["sent_staff","পাঠিয়েছে","Sent by","text"],["received_staff","গ্রহণ করেছে","Received by","text"],["claim","দাবির অবস্থা","Claim state","text"],["value","মূল্য (খরচে)","Value (at cost)","money"],["short_value","কমের মূল্য","Short value","money"],["note","নোট","Note","text"]]'::jsonb,
  '{}', 'sent_day', 'desc', array['locations','brands'], false, false, false, 4203)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
  sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

-- ---------- #66 count variance (paper sheet 04-3 + counts typed in the app), with the value of the difference ----------
create or replace function public._r3q_k2_count_variance(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with cat as (select public.rpt_arr_text(flt -> 'categories') as c, public.rpt_cost_ok() as cost),
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
     group by ln.location_id, ln.cb, i.id, i.code, i.name_bn),
  rp as (                                                       -- bos421: counts typed in the app (stock_count_adjust); a count with no difference writes nothing, so only differences are here
    select l.location_id, l.created_by, i.id as item_id, i.code, i.name_bn, count(*) as off_n, count(*) filter (where l.qty_delta < 0) as short_n, count(*) filter (where l.qty_delta > 0) as over_n,
           sum(l.qty_delta) as net_var, sum(abs(l.qty_delta)) as abs_var, max((l.made_at at time zone 'Asia/Dhaka')::date) as last_date,
           (array_agg(l.note order by l.id desc))[1] as last_reason
      from public.stock_ledger l join public.items i on i.id = l.item_id cross join cat
     where l.reason = 'count_adjust' and (l.made_at at time zone 'Asia/Dhaka')::date between d1 and d2 and l.location_id = any (locs) and (cat.c is null or i.category = any (cat.c))
     group by l.location_id, l.created_by, i.id, i.code, i.name_bn)
  select jsonb_build_object('location_bn', l.name_bn, 'counter', coalesce(nullif(btrim(p.full_name), '') || ' · ' || g.cb, g.cb, '-'), 'item_code', g.code, 'item_bn', g.name_bn, 'source', 'sheet 04-3',
    'counts', g.counts, 'off_n', g.off_n, 'short_n', g.short_n, 'over_n', g.over_n, 'net_var', round(g.net_var, 3), 'abs_var', round(g.abs_var, 3),
    'off_pct', round(g.off_n * 100.0 / g.counts, 1),
    'net_value', case when cat.cost and sb.avg_cost is not null then round(g.net_var * sb.avg_cost, 2) end, 'abs_value', case when cat.cost and sb.avg_cost is not null then round(g.abs_var * sb.avg_cost, 2) end,
    '_nc', case when cat.cost and sb.avg_cost is null then '["net_value","abs_value"]'::jsonb end,
    'last_date', g.last_date, 'last_reason', g.last_reason, 'drill', format('#/stockrep/ledger?item=%s&loc=%s', g.item_id, g.location_id))
    from g join public.locations l on l.id = g.location_id left join public.profiles p on p.staff_id = g.cb cross join cat
      left join public.stock_balance sb on sb.item_id = g.item_id and sb.location_id = g.location_id
  union all
  select jsonb_build_object('location_bn', l.name_bn, 'counter', coalesce(nullif(btrim(p.full_name), '') || ' · ' || p.staff_id, p.staff_id, '-'), 'item_code', r.code, 'item_bn', r.name_bn, 'source', 'count in app',
    'counts', null, 'off_n', r.off_n, 'short_n', r.short_n, 'over_n', r.over_n, 'net_var', round(r.net_var, 3), 'abs_var', round(r.abs_var, 3), 'off_pct', null,
    'net_value', case when cat.cost and sb.avg_cost is not null then round(r.net_var * sb.avg_cost, 2) end, 'abs_value', case when cat.cost and sb.avg_cost is not null then round(r.abs_var * sb.avg_cost, 2) end,
    '_nc', case when cat.cost and sb.avg_cost is null then '["counts","off_pct","net_value","abs_value"]'::jsonb else '["counts","off_pct"]'::jsonb end,
    'last_date', r.last_date, 'last_reason', r.last_reason, 'drill', format('#/stockrep/ledger?item=%s&loc=%s', r.item_id, r.location_id))
    from rp r join public.locations l on l.id = r.location_id left join public.profiles p on p.id = r.created_by cross join cat
      left join public.stock_balance sb on sb.item_id = r.item_id and sb.location_id = r.location_id;
$$;

create or replace function public._r4d_k2_count_variance(p_flt jsonb, p_res jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb := p_res; cost_ok boolean := public.rpt_cost_ok(); col jsonb; cols jsonb := '[]'::jsonb; tot jsonb := coalesce(p_res -> 'totals', '{}'::jsonb);
begin
  res := public._r4_addnote(res, public._r4_note('info', 'Two sources: "sheet 04-3" (paper count sheets, every counted line) and "count in app" (a count typed in the app). The app writes a line ONLY when the count differs from the book, so for those rows the number of counts and the off % are not captured. The value is the difference at the item''s average cost now; where no cost is recorded it is empty.',
    'দুটি উৎস: "sheet 04-3" (কাগজের গণনা শিট, প্রতিটি গোনা লাইন) এবং "count in app" (অ্যাপে লেখা গণনা)। অ্যাপ শুধু বইয়ের সাথে পার্থক্য হলেই লাইন লেখে, তাই ওই সারিতে গণনার সংখ্যা ও পার্থক্য % লেখা হয়নি। মূল্য = পার্থক্য × আইটেমের এখনকার গড় খরচ; খরচ না থাকলে ফাঁকা।'));
  if not cost_ok then
    for col in select * from jsonb_array_elements(res -> 'columns') loop if col ->> 'key' not in ('net_value', 'abs_value') then cols := cols || jsonb_build_array(col); end if; end loop;
    res := jsonb_set(res, '{columns}', cols); tot := tot - 'net_value' - 'abs_value'; res := public._r4_addnote(res, jsonb_build_object('code', 'cost_hidden'));
  end if;
  return jsonb_set(res, '{totals}', tot);
end $$;

insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('k2_count_variance', 'K2', 'stock', 'স্টক গণনার পার্থক্য', 'Stock count variance', 'Stock গণনার পার্থক্য',
  '[["location_bn","লোকেশন","Location","text"],["counter","গণনাকারী","Counter","text"],["item_code","কোড","Code","text"],["item_bn","আইটেম","Item","text"],["source","উৎস","Source","text"],["counts","গণনা","Counts","int"],["off_n","পার্থক্য হয়েছে","Times off","int"],["short_n","কম","Short","int"],["over_n","বেশি","Over","int"],["net_var","নিট পার্থক্য","Net variance","num"],["abs_var","মোট পার্থক্য (চিহ্ন ছাড়া)","Absolute variance","num"],["net_value","নিট মূল্য (গড় খরচে)","Net value (avg cost)","money"],["abs_value","মোট মূল্য (গড় খরচে)","Absolute value (avg cost)","money"],["off_pct","পার্থক্য %","Off %","pct"],["last_date","শেষ তারিখ","Last date","date"],["last_reason","শেষ কারণ","Last reason","text"]]'::jsonb,
  array['counts','off_n','short_n','over_n','net_value','abs_value'], 'off_n', 'desc', array['locations','categories'], false, false, false, 2605)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
  sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

-- ---------- #71 stock adjustment history ----------
create or replace function public._r3q_stock_adjustments(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with cat as (select public.rpt_arr_text(flt -> 'categories') as c, public._r4_types(flt) as ty, public.rpt_cost_ok() as cost)
  select jsonb_build_object('day', (l.made_at at time zone 'Asia/Dhaka')::date, 'at', to_char(l.made_at at time zone 'Asia/Dhaka', 'HH24:MI'), 'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn),
      'item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn), 'unit', public._item_base(it.id),
      'direction', case when l.qty_delta < 0 then 'decrease' else 'increase' end, 'book_qty', b.before_qty, 'counted_qty', b.before_qty + l.qty_delta, 'qty_delta', l.qty_delta,
      'value', case when cat.cost and coalesce(l.unit_cost, sb.avg_cost) is not null then round(l.qty_delta * coalesce(l.unit_cost, sb.avg_cost), 2) end,
      'basis', case when not cat.cost then null when l.unit_cost is not null then 'booked cost' when sb.avg_cost is not null then 'average cost now' else 'no cost recorded' end,
      '_nc', case when cat.cost and coalesce(l.unit_cost, sb.avg_cost) is null then '["value"]'::jsonb end,
      'who', coalesce(nullif(btrim(p.full_name), '') || ' · ' || p.staff_id, p.staff_id, '-'), 'why', l.note, 'ledger_id', l.id,
      'drill', format('#/stockrep/ledger?item=%s&loc=%s', it.id, l.location_id))
    from public.stock_ledger l join public.items it on it.id = l.item_id join public.locations lo on lo.id = l.location_id cross join cat
      left join public.profiles p on p.id = l.created_by left join public.stock_balance sb on sb.item_id = l.item_id and sb.location_id = l.location_id
      cross join lateral (select coalesce(sum(z.qty_delta), 0) as before_qty from public.stock_ledger z where z.item_id = l.item_id and z.location_id = l.location_id and z.id < l.id) b
   where l.reason = 'count_adjust' and (l.made_at at time zone 'Asia/Dhaka')::date between d1 and d2 and l.location_id = any (locs)
     and (cat.c is null or it.category = any (cat.c)) and (cat.ty is null or it.item_type = any (cat.ty));
$$;

create or replace function public._r4d_stock_adjustments(p_flt jsonb, p_res jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb := p_res; cost_ok boolean := public.rpt_cost_ok(); col jsonb; cols jsonb := '[]'::jsonb; tot jsonb := coalesce(p_res -> 'totals', '{}'::jsonb);
begin
  res := public._r4_addnote(res, public._r4_note('info', 'Adjustments made by a stock count in the app (book quantity, counted quantity, difference, who, why). Wastage, transfers and corrections of a bill are not adjustments; they have their own lists. Value uses the booked cost; where a gain has none, the average cost now (the basis column says which).',
    'অ্যাপে স্টক গণনা দিয়ে করা সমন্বয় (বই, গোনা, পার্থক্য, কে, কেন)। নষ্ট, ট্রান্সফার ও বিল সংশোধন সমন্বয় নয়; সেগুলোর আলাদা তালিকা আছে। মূল্য লেখা খরচে; ঘাটতির খরচ না থাকলে এখনকার গড় খরচে (basis কলামে লেখা)।'));
  if not cost_ok then
    for col in select * from jsonb_array_elements(res -> 'columns') loop if col ->> 'key' not in ('value', 'basis') then cols := cols || jsonb_build_array(col); end if; end loop;
    res := jsonb_set(res, '{columns}', cols); tot := tot - 'value'; res := public._r4_addnote(res, jsonb_build_object('code', 'cost_hidden'));
  end if;
  return jsonb_set(res, '{totals}', tot);
end $$;

insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('stock_adjustments', 'S5', 'stock', 'স্টক সমন্বয়ের ইতিহাস (কে, কেন, মূল্য)', 'Stock adjustment history (who, why, value)', 'Stock সমন্বয়ের ইতিহাস (কে, কেন, মূল্য)',
  '[["day","তারিখ","Date","date"],["at","সময়","Time","text"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["unit","একক","Unit","text"],["direction","দিক","Direction","text"],["book_qty","বইয়ে ছিল","Book qty","num"],["counted_qty","গুনে পাওয়া","Counted qty","num"],["qty_delta","পার্থক্য","Difference","num"],["value","মূল্য","Value","money"],["basis","মূল্যের ভিত্তি","Value basis","text"],["who","কে","Who","text"],["why","কেন","Why","text"]]'::jsonb,
  array['value'], 'day', 'desc', array['locations','brands','categories','item_types'], false, false, false, 4204)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
  sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

-- ---------- #77 wastage as a share of stock handled ----------
-- per item and place: wastage qty / (stock at the start of the period + goods received in the period). The two parts of the denominator are columns. Value share of sales is shown beside it.
create or replace function public._r3q_wastage_rate(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with cat as (select public.rpt_arr_text(flt -> 'categories') as c, public._r4_types(flt) as ty, public.rpt_cost_ok() as cost),
  w as (
    select w.item_id, w.location_id, sum(w.qty) as wq, count(*) as n, sum(w.qty * sl.unit_cost) filter (where sl.unit_cost is not null) as wv, count(*) filter (where sl.unit_cost is null) as w_uncosted
      from public.stock_wastage w left join public.stock_ledger sl on sl.id = w.ledger_id
     where (w.made_at at time zone 'Asia/Dhaka')::date between d1 and d2 and w.location_id = any (locs) group by w.item_id, w.location_id),
  h as (
    select w.item_id, w.location_id,
           coalesce((select sum(l.qty_delta) from public.stock_ledger l where l.item_id = w.item_id and l.location_id = w.location_id and (l.made_at at time zone 'Asia/Dhaka')::date < d1), 0) as opening_qty,
           coalesce((select sum(l.qty_delta) from public.stock_ledger l where l.item_id = w.item_id and l.location_id = w.location_id and (l.made_at at time zone 'Asia/Dhaka')::date between d1 and d2
                      and l.reason in ('opening', 'purchase_in', 'production_in', 'transfer_in')), 0) as received_qty
      from w),
  s as (select f.item_id, f.location_id, sum(f.net) as net from public.sales_fact f where f.status = 'done' and f.day between d1 and d2 and f.location_id = any (locs) and f.item_id is not null group by 1, 2)
  select jsonb_build_object('item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn), 'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn),
      'unit', public._item_base(it.id), 'entries', w.n, 'wastage_qty', round(w.wq, 4), 'opening_qty', round(h.opening_qty, 4), 'received_qty', round(h.received_qty, 4), 'handled_qty', round(h.opening_qty + h.received_qty, 4),
      'wastage_pct', case when h.opening_qty + h.received_qty > 0 then round(w.wq * 100.0 / (h.opening_qty + h.received_qty), 2) end,
      'wastage_value', case when cat.cost then round(w.wv, 2) end, 'uncosted_entries', case when cat.cost then w.w_uncosted end,
      'sales_value', round(s.net, 2), 'value_pct_of_sales', case when cat.cost and s.net > 0 and w.wv is not null then round(w.wv * 100.0 / s.net, 2) end,
      '_nc', (select coalesce(jsonb_agg(z), '[]'::jsonb) from unnest(array[case when h.opening_qty + h.received_qty <= 0 then 'wastage_pct' end, case when cat.cost and w.wv is null then 'wastage_value' end,
                case when s.net is null or s.net <= 0 then 'value_pct_of_sales' end]) z where z is not null),
      'drill', format('#/stockrep/ledger?item=%s&loc=%s', it.id, w.location_id))
    from w join h on h.item_id = w.item_id and h.location_id = w.location_id join public.items it on it.id = w.item_id join public.locations lo on lo.id = w.location_id cross join cat
      left join s on s.item_id = w.item_id and s.location_id = w.location_id
   where (cat.c is null or it.category = any (cat.c)) and (cat.ty is null or it.item_type = any (cat.ty));
$$;

create or replace function public._r4d_wastage_rate(p_flt jsonb, p_res jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb := p_res; cost_ok boolean := public.rpt_cost_ok(); col jsonb; cols jsonb := '[]'::jsonb; tot jsonb := coalesce(p_res -> 'totals', '{}'::jsonb);
begin
  res := public._r4_addnote(res, public._r4_note('info', 'Wastage % = wastage quantity / (stock at the start of the period + goods received in the period: opening entries, purchases, production, transfers in). Both parts are shown. Where nothing was held or received the % is empty (no denominator), it is not 0. Value % of sales = wastage value (costed entries only) / sales value of the same item and place.',
    'নষ্ট % = নষ্টের পরিমাণ / (সময়ের শুরুর স্টক + সময়ে পাওয়া মাল: ওপেনিং, ক্রয়, উৎপাদন, ট্রান্সফার ইন)। দুটি অংশই দেখানো হয়েছে। কিছু না থাকলে/না এলে % ফাঁকা (ভাগ করার সংখ্যা নেই), ০ নয়। বিক্রির % = নষ্টের মূল্য (শুধু খরচ জানা এন্ট্রি) / একই আইটেম ও জায়গার বিক্রির মূল্য।'));
  res := public._r4_addnote(res, public._r4_note('info', 'Quantities are per item in its own base unit; different units are never added. Use the existing Wastage report for totals by reason, item, place or day.',
    'পরিমাণ প্রতিটি আইটেমের নিজের এককে; ভিন্ন একক যোগ করা হয়নি। কারণ, আইটেম, জায়গা বা দিন অনুযায়ী মোটের জন্য আগের "অপচয়" রিপোর্ট দেখুন।'));
  if not cost_ok then
    for col in select * from jsonb_array_elements(res -> 'columns') loop if col ->> 'key' not in ('wastage_value', 'uncosted_entries', 'sales_value', 'value_pct_of_sales') then cols := cols || jsonb_build_array(col); end if; end loop;
    res := jsonb_set(res, '{columns}', cols); tot := tot - 'wastage_value' - 'uncosted_entries'; res := public._r4_addnote(res, jsonb_build_object('code', 'cost_hidden'));
  end if;
  return jsonb_set(res, '{totals}', tot);
end $$;

insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('wastage_rate', 'S6', 'stock', 'অপচয় % (কত মালের মধ্যে কত নষ্ট)', 'Wastage % of stock handled', 'অপচয় % (stock handled-এর মধ্যে)',
  '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["unit","একক","Unit","text"],["entries","বার","Entries","int"],["wastage_qty","নষ্ট পরিমাণ","Wastage qty","num"],["opening_qty","শুরুর স্টক","Opening qty","num"],["received_qty","পাওয়া মাল","Received qty","num"],["handled_qty","মোট ছিল (ভাগ করার সংখ্যা)","Handled (denominator)","num"],["wastage_pct","নষ্ট %","Wastage %","pct"],["wastage_value","নষ্টের মূল্য (খরচ জানা অংশ)","Wastage value (costed part)","money"],["uncosted_entries","খরচ অজানা এন্ট্রি","Entries with no cost","int"],["sales_value","বিক্রির মূল্য","Sales value","money"],["value_pct_of_sales","বিক্রির %","Value % of sales","pct"]]'::jsonb,
  array['entries','wastage_value','uncosted_entries'], 'wastage_pct', 'desc', array['locations','brands','categories','item_types'], false, false, false, 4205)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
  sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

select public._r3_lockdown();
select public._r4_lockdown();
notify pgrst, 'reload schema';

-- ===================== phase422.sql =====================
-- ============================================================
-- BOS tool · Phase 422 (RPT-B2 R2b): the stock MOVEMENT LEDGER of one item at one place (#63): opening, every movement with its running balance, closing, a check against the
-- cached balance, and for every row the source document (sale, refund, bill, transfer, production, wastage, count). Read-only. Paste after phase421. Safe to paste twice.
-- Opens to report_stock holders (rpt_access('stock')) at their own places; the cost of a row is shown only to who may see cost. Used by web/stockrep.js (#/stockrep/ledger),
-- which every "drill" link of the stock reports points to.
-- ============================================================

-- the source document of one ledger row: kind, a short label, and a few plain facts (no money unless the caller may see cost)
create or replace function public._r4_doc(p_reason text, p_ref_type text, p_ref_id text, p_cost boolean) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare j jsonb;
begin
  if p_ref_type is null then return jsonb_build_object('kind', coalesce(p_reason, 'other'), 'label', coalesce(p_reason, '')); end if;
  if p_ref_type = 'sale' then
    select jsonb_build_object('kind', 'sale', 'label', 'Sale #' || s.receipt, 'detail', jsonb_build_object('receipt', s.receipt, 'sale_date', s.sale_date, 'status', s.status, 'pay_mode', s.pay_mode, 'location_id', s.location_id)) into j
      from public.sales s where s.id::text = p_ref_id;
  elsif p_ref_type = 'sale_return' then
    select jsonb_build_object('kind', 'refund', 'label', 'Refund of sale #' || s.receipt, 'detail', jsonb_build_object('receipt', s.receipt, 'reason_code', r.reason_code, 'status', r.status, 'refund_mode', r.refund_mode, 'created_at', r.created_at)) into j
      from public.sale_returns r join public.sales s on s.id = r.sale_id where r.id::text = p_ref_id;
  elsif p_ref_type = 'purchase' then
    select jsonb_build_object('kind', case b.kind when 'return' then 'purchase_return' else 'purchase' end, 'label', case b.kind when 'return' then 'Purchase return ' else 'Bill ' end || coalesce(b.bill_no, '-') || ' · ' || su.name,
      'detail', jsonb_build_object('bill_no', b.bill_no, 'supplier', su.name, 'bill_date', b.bill_date, 'status', b.status, 'reason_code', b.reason_code) || case when p_cost then jsonb_build_object('total', b.total) else '{}'::jsonb end) into j
      from public.purchase_bills b join public.suppliers su on su.id = b.supplier_id where b.id::text = p_ref_id;
  elsif p_ref_type = 'transfer' then
    select jsonb_build_object('kind', 'transfer', 'label', 'Transfer ' || coalesce(lf.name_en, lf.name_bn) || ' > ' || coalesce(lt.name_en, lt.name_bn),
      'detail', jsonb_build_object('status', x.status, 'sent_qty', x.qty, 'received_qty', x.received_qty, 'sent_at', x.sent_at, 'received_at', x.received_at, 'sent_staff', x.sent_staff, 'received_staff', x.received_staff, 'note', coalesce(x.receive_note, x.note))) into j
      from public.stock_transfers x join public.locations lf on lf.id = x.from_location_id join public.locations lt on lt.id = x.to_location_id where x.id::text = p_ref_id;
  elsif p_ref_type = 'wastage' then
    select jsonb_build_object('kind', 'wastage', 'label', 'Wastage · ' || coalesce(o.label_en, w.reason_code), 'detail', jsonb_build_object('reason_code', w.reason_code, 'note', w.note, 'made_at', w.made_at, 'staff', w.created_staff)) into j
      from public.stock_wastage w left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = w.reason_code where w.id::text = p_ref_id;
  elsif p_ref_type = 'production' then
    select jsonb_build_object('kind', 'production', 'label', 'Production run ' || to_char(pr.made_at at time zone 'Asia/Dhaka', 'YYYY-MM-DD'),
      'detail', jsonb_build_object('run_id', pr.id, 'made_at', pr.made_at, 'batches', pr.batches, 'yield_base', pr.yield_base, 'batch_id', pr.batch_id)) into j
      from public.production_runs pr where pr.id::text = p_ref_id;
    if j is null and p_ref_id ~ '^[0-9]{1,18}$' then          -- a direct production entry: the reference is the batch
      select jsonb_build_object('kind', 'production', 'label', 'Production batch #' || b.id, 'detail', jsonb_build_object('batch_id', b.id, 'made_at', b.made_at, 'expires_at', b.expires_at, 'qty_made', b.qty_made, 'note', b.note)) into j
        from public.stock_batches b where b.id::text = p_ref_id;
    end if;
  end if;
  return coalesce(j, jsonb_build_object('kind', coalesce(p_ref_type, p_reason), 'label', case p_ref_type when 'count' then 'Count adjust' when 'opening' then 'Opening stock' when 'issue' then 'Issue to production' else coalesce(p_ref_type, '') end));
end $$;
revoke all on function public._r4_doc(text, text, text, boolean) from public, anon, authenticated;

create or replace function public.stock_movement_ledger(p_item uuid, p_loc int, p_from date default null, p_to date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare today date := (now() at time zone 'Asia/Dhaka')::date; f date; t date; it public.items; lo public.locations; opening numeric; total_all numeric; cached numeric; avgc numeric;
        rows_ jsonb; sumry jsonb; n bigint; cost_ok boolean; closing numeric; first_run numeric; later bigint; cap constant int := 1000;
begin
  if not public.is_active() or not public.rpt_access('stock') then raise exception 'not allowed'; end if;
  if p_loc is null or not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  f := coalesce(p_from, today - 30); t := coalesce(p_to, today);
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
  select * into it from public.items where id = p_item; if not found then raise exception 'item_not_found'; end if;
  select * into lo from public.locations where id = p_loc;
  cost_ok := public.rpt_cost_ok();
  select coalesce(sum(qty_delta), 0) into opening from public.stock_ledger l where l.item_id = p_item and l.location_id = p_loc and (l.made_at at time zone 'Asia/Dhaka')::date < f;
  select coalesce(sum(qty_delta), 0) into total_all from public.stock_ledger l where l.item_id = p_item and l.location_id = p_loc;
  select b.qty, b.avg_cost into cached, avgc from public.stock_balance b where b.item_id = p_item and b.location_id = p_loc;
  select count(*) into n from public.stock_ledger l where l.item_id = p_item and l.location_id = p_loc and (l.made_at at time zone 'Asia/Dhaka')::date between f and t;
  select count(*) into later from public.stock_ledger l where l.item_id = p_item and l.location_id = p_loc and (l.made_at at time zone 'Asia/Dhaka')::date > t;
  select coalesce(jsonb_agg(jsonb_build_object('id', z.id, 'at', z.made_at, 'day', z.d, 'time', z.tm, 'reason', z.reason, 'ref_type', z.ref_type, 'ref_id', z.ref_id, 'qty_delta', z.qty_delta, 'running', z.running,
      'unit_cost', case when cost_ok then z.unit_cost end, 'value', case when cost_ok and z.unit_cost is not null then round(z.qty_delta * z.unit_cost, 2) end,
      '_nc', case when cost_ok and z.unit_cost is null and z.reason in ('purchase_in', 'production_in', 'opening', 'count_adjust') then '["unit_cost","value"]'::jsonb end,
      'batch_id', z.batch_id, 'batch_no', z.batch_no, 'note', z.note, 'who', z.who, 'reverses_id', z.reverses_id, 'doc', public._r4_doc(z.reason, z.ref_type, z.ref_id, cost_ok)) order by z.made_at, z.id), '[]'::jsonb)
    into rows_
    from (select q.*, row_number() over (order by q.made_at, q.id) as rn, count(*) over () as cnt from (
            select l.id, l.made_at, (l.made_at at time zone 'Asia/Dhaka')::date as d, to_char(l.made_at at time zone 'Asia/Dhaka', 'HH24:MI') as tm, l.reason, l.ref_type, l.ref_id, l.qty_delta, l.unit_cost, l.batch_id, sb.batch_no, l.note,
                   coalesce(nullif(btrim(p.full_name), '') || ' · ' || p.staff_id, p.staff_id) as who, l.reverses_id,
                   opening + sum(l.qty_delta) over (order by l.made_at, l.id) as running
              from public.stock_ledger l left join public.stock_batches sb on sb.id = l.batch_id left join public.profiles p on p.id = l.created_by
             where l.item_id = p_item and l.location_id = p_loc and (l.made_at at time zone 'Asia/Dhaka')::date between f and t) q) z
   where z.rn > z.cnt - cap;
  closing := opening + coalesce((select sum(l.qty_delta) from public.stock_ledger l where l.item_id = p_item and l.location_id = p_loc and (l.made_at at time zone 'Asia/Dhaka')::date between f and t), 0);
  first_run := case when n > cap then closing - coalesce((select sum(x.qty_delta) from (select l.qty_delta from public.stock_ledger l where l.item_id = p_item and l.location_id = p_loc
                       and (l.made_at at time zone 'Asia/Dhaka')::date between f and t order by l.made_at desc, l.id desc limit cap) x), 0) end;
  select coalesce(jsonb_agg(jsonb_build_object('reason', s.reason, 'rows', s.c, 'in_qty', s.i, 'out_qty', s.o, 'net', s.i - s.o) order by s.reason), '[]'::jsonb) into sumry
    from (select l.reason, count(*) as c, coalesce(sum(l.qty_delta) filter (where l.qty_delta > 0), 0) as i, coalesce(-sum(l.qty_delta) filter (where l.qty_delta < 0), 0) as o
            from public.stock_ledger l where l.item_id = p_item and l.location_id = p_loc and (l.made_at at time zone 'Asia/Dhaka')::date between f and t group by l.reason) s;
  return jsonb_build_object('item', jsonb_build_object('id', it.id, 'code', it.code, 'name_bn', it.name_bn, 'name_en', coalesce(it.name_en, it.name_bn), 'unit', public._item_base(it.id), 'item_type', it.item_type),
    'location', jsonb_build_object('id', lo.id, 'name_bn', lo.name_bn, 'name_en', coalesce(lo.name_en, lo.name_bn)), 'from', f, 'to', t,
    'opening', opening, 'closing', closing, 'rows', rows_, 'row_count', n, 'truncated', n > cap, 'shown_from_running', first_run, 'summary', sumry,
    'check', jsonb_build_object('ledger_total_all', total_all, 'cached', coalesce(cached, 0), 'ok', total_all = coalesce(cached, 0), 'later_rows', later, 'closing_is_latest', later = 0),
    'avg_cost', case when cost_ok then avgc end, 'cost_shown', cost_ok,
    'notes', case when n > cap then jsonb_build_array(public._r4_note('truncated', 'Only the last ' || cap || ' of ' || n || ' rows are shown; narrow the dates for the rest. The opening and closing are for the whole period.',
        'শেষ ' || cap || 'টি সারি (মোট ' || n || ') দেখানো হয়েছে; বাকিটা দেখতে তারিখ ছোট করুন। শুরু ও শেষের ব্যালান্স পুরো সময়ের।')) else '[]'::jsonb end);
end $$;
revoke all on function public.stock_movement_ledger(uuid, int, date, date) from public, anon;
grant execute on function public.stock_movement_ledger(uuid, int, date, date) to authenticated;

select public._r4_lockdown();
notify pgrst, 'reload schema';

-- ===================== phase423.sql =====================
-- ============================================================
-- BOS tool · Phase 423 (RPT-B2 R3): RECONCILIATION and integrity of stock. Read-only. Paste after phase422. Safe to paste twice. Open to report_stock holders at their own places.
--   #72 stock_integrity      (engine 3, viewer #/report/stock_integrity)  negative balances, a cached balance that differs from the ledger, batches that hold more than the balance
--   #75 stock_recon_period(from, to, loc)                                   opening (ledger replay) + in - out = closing per item and place, in-transit and short transfer lines,
--                                                                           and a check of the ledger against the cached balance (web/stockrep.js #/stockrep/recon)
--   #82 daily_closing        (engine 3)  the closing stock of each day against the NEXT day's sales and loss (empty, not 0, while the next day has not happened)
--   #73 item_turnover        (engine 3)  consumption / average stock, and days on hand; empty where there is no consumption or no stock (no division by zero, no estimate)
-- Quantities are per item in its own base unit and are never added across items. The stock identity is: opening + received - issued = closing, on the ledger (made_at in Asia/Dhaka days).
-- ============================================================

-- daily closing stock per item and place from the ledger (also gives the day's net sales and loss); day d1 .. d2 + 1 (the extra day is the "next day" of d2)
create or replace function public._r4_closing_daily(d1 date, d2 date, locs int[], ty text[], cat text[])
returns table (day date, item_id uuid, location_id int, closing numeric, sales_net numeric, loss numeric, received numeric)
language sql stable security definer set search_path = public as $$
  with p as (
    select l.item_id, l.location_id from public.stock_ledger l join public.items it on it.id = l.item_id
     where l.location_id = any (locs) and (l.made_at at time zone 'Asia/Dhaka')::date <= d2 + 1 and it.is_active and (ty is null or it.item_type = any (ty)) and (cat is null or it.category = any (cat))
     group by l.item_id, l.location_id),
  dn as (
    select l.item_id, l.location_id, (l.made_at at time zone 'Asia/Dhaka')::date as d, sum(l.qty_delta) as net,
           -sum(l.qty_delta) filter (where l.reason in ('sale_out', 'sale_void_in', 'sale_return')) as sales_net,
           -sum(l.qty_delta) filter (where l.reason = 'wastage') as loss,
           sum(l.qty_delta) filter (where l.reason in ('purchase_in', 'production_in', 'transfer_in')) as received
      from public.stock_ledger l join p on p.item_id = l.item_id and p.location_id = l.location_id
     where (l.made_at at time zone 'Asia/Dhaka')::date <= d2 + 1 group by 1, 2, 3),
  op as (select dn.item_id, dn.location_id, sum(dn.net) as o from dn where dn.d < d1 group by 1, 2),
  g as (select p.item_id, p.location_id, s::date as dd from p cross join generate_series(d1, d2 + 1, interval '1 day') s)
  select g.dd, g.item_id, g.location_id, coalesce(op.o, 0) + sum(coalesce(dn.net, 0)) over (partition by g.item_id, g.location_id order by g.dd),
         coalesce(dn.sales_net, 0), coalesce(dn.loss, 0), coalesce(dn.received, 0)
    from g left join dn on dn.item_id = g.item_id and dn.location_id = g.location_id and dn.d = g.dd
           left join op on op.item_id = g.item_id and op.location_id = g.location_id;
$$;
revoke all on function public._r4_closing_daily(date, date, int[], text[], text[]) from public, anon, authenticated;

-- ---------- #72 negative balances and integrity ----------
create or replace function public._r3q_stock_integrity(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with cat as (select public.rpt_arr_text(flt -> 'categories') as c, public._r4_types(flt) as ty),
  lg as (select l.item_id, l.location_id, sum(l.qty_delta) as q from public.stock_ledger l where l.location_id = any (locs) group by 1, 2),
  bt as (select b.item_id, b.location_id, sum(b.qty_remaining) as q from public.stock_batches b where b.location_id = any (locs) and b.qty_remaining > 0 group by 1, 2),
  base as (
    select sb.item_id, sb.location_id, sb.qty as cached, coalesce(lg.q, 0) as ledger, coalesce(bt.q, 0) as batched
      from public.stock_balance sb left join lg on lg.item_id = sb.item_id and lg.location_id = sb.location_id left join bt on bt.item_id = sb.item_id and bt.location_id = sb.location_id
     where sb.location_id = any (locs)),
  neg as (
    select b.item_id, b.location_id, b.cached, b.ledger,
           (select min(r.d) from (select (l.made_at at time zone 'Asia/Dhaka')::date as d, sum(l.qty_delta) over (order by l.made_at, l.id) as run from public.stock_ledger l
                                   where l.item_id = b.item_id and l.location_id = b.location_id) r where r.run < 0) as since,
           (select coalesce(sum(-l.qty_delta), 0) from public.stock_ledger l where l.item_id = b.item_id and l.location_id = b.location_id and l.qty_delta < 0 and l.batch_id is null
               and l.reason in ('sale_out', 'issue_out', 'transfer_out', 'wastage')) as unbatched_out
      from base b where b.cached < 0)
  select jsonb_build_object('issue', 'negative', 'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn), 'item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn),
      'unit', public._item_base(it.id), 'cached_qty', n.cached, 'ledger_qty', n.ledger, 'diff', round(n.cached - n.ledger, 4), 'short_qty', -n.cached, 'since', n.since, 'unbatched_out_qty', n.unbatched_out,
      'detail', 'More went out than the book had. The oversold part is posted with no batch, so it cannot be traced to a production or receipt.',
      'drill', format('#/stockrep/ledger?item=%s&loc=%s', it.id, n.location_id))
    from neg n join public.items it on it.id = n.item_id join public.locations lo on lo.id = n.location_id cross join cat where (cat.c is null or it.category = any (cat.c)) and (cat.ty is null or it.item_type = any (cat.ty))
  union all
  select jsonb_build_object('issue', 'cache_differs', 'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn), 'item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn),
      'unit', public._item_base(it.id), 'cached_qty', b.cached, 'ledger_qty', b.ledger, 'diff', round(b.cached - b.ledger, 4), 'short_qty', null, 'since', null, 'unbatched_out_qty', null,
      'detail', 'The cached balance differs from the sum of the ledger. The ledger is the truth; the owner can repair the cache on the stock screen (typed confirmation).',
      'drill', format('#/stockrep/ledger?item=%s&loc=%s', it.id, b.location_id))
    from base b join public.items it on it.id = b.item_id join public.locations lo on lo.id = b.location_id cross join cat
   where abs(b.cached - b.ledger) > 0.00005 and (cat.c is null or it.category = any (cat.c)) and (cat.ty is null or it.item_type = any (cat.ty))
  union all
  select jsonb_build_object('issue', 'batches_exceed_balance', 'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn), 'item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn),
      'unit', public._item_base(it.id), 'cached_qty', b.cached, 'ledger_qty', b.ledger, 'diff', round(b.batched - b.cached, 4), 'short_qty', null, 'since', null, 'unbatched_out_qty', null,
      'detail', 'Open batches hold more (' || round(b.batched, 4) || ') than the balance (' || b.cached || '). A batch can never hold more than the item''s balance.',
      'drill', format('#/batchrep/batches?item=%s&loc=%s', it.id, b.location_id))
    from base b join public.items it on it.id = b.item_id join public.locations lo on lo.id = b.location_id cross join cat
   where b.batched > greatest(b.cached, 0) + 0.0005 and (cat.c is null or it.category = any (cat.c)) and (cat.ty is null or it.item_type = any (cat.ty));
$$;

create or replace function public._r4d_stock_integrity(p_flt jsonb, p_res jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb := p_res; n_all int := coalesce((p_res #>> '{page,groups}')::int, 0);
begin
  if n_all = 0 then
    return public._r4_addnote(res, public._r4_note('info', 'Nothing to report: no negative balance, no cached balance that differs from the ledger, no batch that holds more than the balance (for the places and filters chosen).',
      'কিছু নেই: কোনো ঋণাত্মক ব্যালান্স নেই, ক্যাশ ব্যালান্স খাতার সাথে মেলে, কোনো ব্যাচ ব্যালান্সের চেয়ে বেশি ধরে না (বাছা লোকেশন ও ফিল্টারে)।'));
  end if;
  return public._r4_addnote(res, public._r4_note('info', 'Three checks: a NEGATIVE balance (more went out than the book had), a cached balance that DIFFERS from the ledger, and batches that hold MORE than the balance. Each row opens the ledger of that item and place.',
    'তিনটি যাচাই: ঋণাত্মক ব্যালান্স (বইয়ে যা ছিল তার চেয়ে বেশি বের হয়েছে), ক্যাশ ব্যালান্স খাতার সাথে অমিল, এবং ব্যালান্সের চেয়ে বেশি ধরা ব্যাচ। প্রতিটি সারি সেই আইটেম ও জায়গার খাতা খোলে।'));
end $$;

insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('stock_integrity', 'S7', 'stock', 'ঋণাত্মক স্টক ও হিসাবের গরমিল', 'Negative stock and integrity', 'ঋণাত্মক Stock ও হিসাবের গরমিল',
  '[["issue","সমস্যা","Issue","text"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["unit","একক","Unit","text"],["cached_qty","ক্যাশ ব্যালান্স","Cached balance","num"],["ledger_qty","খাতার যোগফল","Ledger total","num"],["diff","পার্থক্য","Difference","num"],["short_qty","ঘাটতি (বেশি বেরিয়েছে)","Oversold by","num"],["since","কবে থেকে","Since","date"],["unbatched_out_qty","ব্যাচ ছাড়া বেরিয়েছে","Out with no batch","num"],["detail","বিবরণ","Detail","text"]]'::jsonb,
  '{}', 'issue', 'asc', array['locations','brands','categories','item_types'], true, false, false, 4207)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
  sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

-- ---------- #75 period reconciliation ----------
create or replace function public.stock_recon_period(p_from date, p_to date, p_loc int default null, p_types text[] default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare today date := (now() at time zone 'Asia/Dhaka')::date; locs int[]; rows_ jsonb; transit jsonb; short_ jsonb; sm jsonb; cost_ok boolean; ty text[]; n bigint; cap constant int := 1500;
begin
  if not public.is_active() or not public.rpt_access('stock') then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  locs := coalesce(array(select l.id from public.locations l where public.can_loc(l.id) and (p_loc is null or l.id = p_loc)), '{}');
  ty := case when p_types is null or cardinality(p_types) = 0 then null else coalesce(array(select t.code from public.item_types t where t.code = any (p_types)), '{}') end;
  cost_ok := public.rpt_cost_ok();
  with a as (
    select l.item_id, l.location_id,
           sum(l.qty_delta) filter (where (l.made_at at time zone 'Asia/Dhaka')::date < p_from) as opening,
           sum(l.qty_delta) filter (where (l.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to) as period,
           sum(l.qty_delta) filter (where (l.made_at at time zone 'Asia/Dhaka')::date <= p_to) as closing_replay,
           sum(l.qty_delta) as total_all,
           sum(l.qty_delta) filter (where l.reason = 'opening' and (l.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to) as opening_entry,
           sum(l.qty_delta) filter (where l.reason = 'purchase_in' and (l.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to) as purchase_in,
           sum(l.qty_delta) filter (where l.reason = 'production_in' and (l.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to) as production_in,
           sum(l.qty_delta) filter (where l.reason = 'transfer_in' and (l.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to) as transfer_in,
           sum(l.qty_delta) filter (where l.reason in ('sale_void_in', 'sale_return') and (l.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to) as sales_back,
           sum(l.qty_delta) filter (where l.reason = 'sale_out' and (l.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to) as sale_out,
           sum(l.qty_delta) filter (where l.reason = 'issue_out' and (l.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to) as issue_out,
           sum(l.qty_delta) filter (where l.reason = 'wastage' and (l.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to) as wastage,
           sum(l.qty_delta) filter (where l.reason = 'transfer_out' and (l.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to) as transfer_out,
           sum(l.qty_delta) filter (where l.reason = 'purchase_return' and (l.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to) as purchase_return,
           sum(l.qty_delta) filter (where l.reason = 'count_adjust' and (l.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to) as count_adjust,
           sum(l.qty_delta) filter (where l.reason = 'reversal' and (l.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to) as reversal
      from public.stock_ledger l join public.items it on it.id = l.item_id
     where l.location_id = any (locs) and (ty is null or it.item_type = any (ty)) group by l.item_id, l.location_id),
  c as (
    select a.*, coalesce(a.opening, 0) as o, coalesce(a.period, 0) as pd,
           coalesce(a.opening_entry, 0) + coalesce(a.purchase_in, 0) + coalesce(a.production_in, 0) + coalesce(a.transfer_in, 0) + coalesce(a.sales_back, 0) + coalesce(a.sale_out, 0) + coalesce(a.issue_out, 0)
             + coalesce(a.wastage, 0) + coalesce(a.transfer_out, 0) + coalesce(a.purchase_return, 0) + coalesce(a.count_adjust, 0) + coalesce(a.reversal, 0) as listed
      from a where coalesce(a.opening, 0) <> 0 or coalesce(a.period, 0) <> 0 or coalesce(a.closing_replay, 0) <> 0),
  t as (                                                -- still on the road at the end of p_to: sent by then, not received by then
    select x.from_location_id as lid, x.item_id, sum(x.qty) as q from public.stock_transfers x
     where (x.sent_at at time zone 'Asia/Dhaka')::date <= p_to and x.from_location_id = any (locs)
       and (x.status = 'sent' or (x.status = 'received' and (x.received_at at time zone 'Asia/Dhaka')::date > p_to) or (x.status = 'cancelled' and (x.cancelled_at at time zone 'Asia/Dhaka')::date > p_to))
     group by 1, 2),
  r as (
    select c.*, it.code, it.name_bn, coalesce(it.name_en, it.name_bn) as name_en, public._item_base(it.id) as unit, it.item_type, lo.name_bn as lbn, coalesce(lo.name_en, lo.name_bn) as len,
           c.o + c.pd as closing, sb.qty as cached, coalesce(t.q, 0) as in_transit_out, row_number() over (order by lo.id, it.code) as rn, count(*) over () as cnt
      from c join public.items it on it.id = c.item_id join public.locations lo on lo.id = c.location_id
        left join public.stock_balance sb on sb.item_id = c.item_id and sb.location_id = c.location_id left join t on t.lid = c.location_id and t.item_id = c.item_id)
  select coalesce(jsonb_agg(jsonb_build_object('item_id', r.item_id, 'location_id', r.location_id, 'location_bn', r.lbn, 'location_en', r.len, 'item_code', r.code, 'item_name', r.name_bn, 'item_name_en', r.name_en,
      'unit', r.unit, 'item_type', r.item_type, 'opening', r.o, 'opening_entry', coalesce(r.opening_entry, 0), 'purchase_in', coalesce(r.purchase_in, 0), 'production_in', coalesce(r.production_in, 0),
      'transfer_in', coalesce(r.transfer_in, 0), 'sales_back', coalesce(r.sales_back, 0), 'sale_out', coalesce(r.sale_out, 0), 'issue_out', coalesce(r.issue_out, 0), 'wastage', coalesce(r.wastage, 0),
      'transfer_out', coalesce(r.transfer_out, 0), 'purchase_return', coalesce(r.purchase_return, 0), 'count_adjust', coalesce(r.count_adjust, 0), 'reversal', coalesce(r.reversal, 0),
      'unclassified', round(r.pd - r.listed, 4), 'closing', r.closing, 'identity_diff', round(r.closing - coalesce(r.closing_replay, 0), 4),
      'later_qty', round(coalesce(r.total_all, 0) - coalesce(r.closing_replay, 0), 4), 'ledger_total', coalesce(r.total_all, 0), 'cached', coalesce(r.cached, 0),
      'cache_diff', round(coalesce(r.cached, 0) - coalesce(r.total_all, 0), 4), 'in_transit_out', r.in_transit_out,
      'state', case when abs(r.pd - r.listed) > 0.00005 or abs(r.closing - coalesce(r.closing_replay, 0)) > 0.00005 then 'unclassified'
                    when abs(coalesce(r.cached, 0) - coalesce(r.total_all, 0)) > 0.00005 then 'cache_differs' else 'ok' end) order by r.rn) filter (where r.rn <= cap), '[]'::jsonb), max(r.cnt)
    into rows_, n from r;
  select coalesce(jsonb_agg(jsonb_build_object('transfer_id', x.id, 'sent_day', (x.sent_at at time zone 'Asia/Dhaka')::date, 'from_location_id', x.from_location_id, 'to_location_id', x.to_location_id,
      'from_name', coalesce(lf.name_en, lf.name_bn), 'to_name', coalesce(lt.name_en, lt.name_bn), 'item_code', it.code, 'item_name', coalesce(it.name_en, it.name_bn), 'unit', public._item_base(it.id), 'qty', x.qty,
      'days', p_to - (x.sent_at at time zone 'Asia/Dhaka')::date) order by x.sent_at), '[]'::jsonb) into transit
    from public.stock_transfers x join public.items it on it.id = x.item_id join public.locations lf on lf.id = x.from_location_id join public.locations lt on lt.id = x.to_location_id
   where (x.sent_at at time zone 'Asia/Dhaka')::date <= p_to and (x.from_location_id = any (locs) or x.to_location_id = any (locs)) and (ty is null or it.item_type = any (ty))
     and (x.status = 'sent' or (x.status = 'received' and (x.received_at at time zone 'Asia/Dhaka')::date > p_to) or (x.status = 'cancelled' and (x.cancelled_at at time zone 'Asia/Dhaka')::date > p_to));
  select coalesce(jsonb_agg(jsonb_build_object('transfer_id', x.id, 'sent_day', (x.sent_at at time zone 'Asia/Dhaka')::date, 'received_day', (x.received_at at time zone 'Asia/Dhaka')::date,
      'from_name', coalesce(lf.name_en, lf.name_bn), 'to_name', coalesce(lt.name_en, lt.name_bn), 'item_code', it.code, 'item_name', coalesce(it.name_en, it.name_bn), 'unit', public._item_base(it.id),
      'sent_qty', x.qty, 'received_qty', x.received_qty, 'short_qty', round(x.qty - x.received_qty, 4), 'claim', st.status,
      'short_value', case when cost_ok then st.value end, 'value_missing', cost_ok and st.id is not null and st.value is null) order by x.received_at), '[]'::jsonb) into short_
    from public.stock_transfers x join public.items it on it.id = x.item_id join public.locations lf on lf.id = x.from_location_id join public.locations lt on lt.id = x.to_location_id
      left join public.shortage_transit st on st.transfer_id = x.id
   where x.status = 'received' and x.received_qty < x.qty and (x.received_at at time zone 'Asia/Dhaka')::date between p_from and p_to and (x.from_location_id = any (locs) or x.to_location_id = any (locs))
     and (ty is null or it.item_type = any (ty));
  sm := jsonb_build_object('pairs', n,
    'ok', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'state' = 'ok'), 'cache_differs', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'state' = 'cache_differs'),
    'unclassified', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'state' = 'unclassified'),
    'later_rows', (select count(*) from jsonb_array_elements(rows_) e where (e ->> 'later_qty')::numeric <> 0),
    'in_transit_lines', jsonb_array_length(transit), 'short_lines', jsonb_array_length(short_),
    'identity_holds', not exists (select 1 from jsonb_array_elements(rows_) e where e ->> 'state' = 'unclassified'),
    'cache_checked', p_to >= today);
  return jsonb_build_object('from', p_from, 'to', p_to, 'location_id', p_loc, 'rows', rows_, 'transit', transit, 'short', short_, 'summary', sm, 'truncated', coalesce(n, 0) > cap, 'cost_shown', cost_ok,
    'notes', jsonb_build_array(
      public._r4_note('info', 'Opening = the ledger replayed to the day before ' || p_from || '. Closing = opening + the movements of the period. Each item is in its own base unit, so rows are never added together. "In transit" is stock that left the sender and has not been received by ' || p_to || ': it is already out of the sender and not yet in the receiver.',
        'শুরু = ' || p_from || ' এর আগের দিন পর্যন্ত খাতার যোগফল। শেষ = শুরু + সময়ের নড়াচড়া। প্রতিটি আইটেম নিজের এককে, তাই সারি যোগ করা হয়নি। "পথে" = প্রেরক থেকে বেরিয়েছে কিন্তু ' || p_to || ' পর্যন্ত গ্রহণ হয়নি।'),
      case when p_to < today then public._r4_note('info', 'The check against the cached balance compares the cached balance now with the ledger total now; the period ends before today, so later movements are shown in "later" and are not an error.',
        'ক্যাশ ব্যালান্সের সাথে যাচাই এখনকার ক্যাশ ও এখনকার খাতার যোগফলের; সময় আজকের আগে শেষ, তাই পরের নড়াচড়া "পরে" ঘরে দেখানো, ভুল নয়।') end));
end $$;
revoke all on function public.stock_recon_period(date, date, int, text[]) from public, anon;
grant execute on function public.stock_recon_period(date, date, int, text[]) to authenticated;

-- ---------- #82 closing stock of each day against the next day's sales and loss ----------
create or replace function public._r3q_daily_closing(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with p as (select (now() at time zone 'Asia/Dhaka')::date as today, public.rpt_cost_ok() as cost),
  cd as (select * from public._r4_closing_daily(d1, d2, locs, public._r4_types(flt), public.rpt_arr_text(flt -> 'categories')))
  select jsonb_build_object('day', c.day, 'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn), 'item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn),
      'unit', public._item_base(it.id), 'closing_qty', round(c.closing, 4), 'received_qty', round(c.received, 4),
      'next_sales_qty', case when c.day + 1 <= p.today then round(n.sales_net, 4) end, 'next_loss_qty', case when c.day + 1 <= p.today then round(n.loss, 4) end,
      'sales_pct', case when c.day + 1 <= p.today and c.closing > 0 then round(n.sales_net * 100.0 / c.closing, 1) end,
      'loss_pct', case when c.day + 1 <= p.today and c.closing > 0 then round(n.loss * 100.0 / c.closing, 1) end,
      'closing_value', case when p.cost and sb.avg_cost is not null then round(c.closing * sb.avg_cost, 2) end,
      '_nc', (select coalesce(jsonb_agg(z), '[]'::jsonb) from unnest(array[case when c.day + 1 > p.today then 'next_sales_qty' end, case when c.day + 1 > p.today then 'next_loss_qty' end,
               case when c.day + 1 > p.today or c.closing <= 0 then 'sales_pct' end, case when c.day + 1 > p.today or c.closing <= 0 then 'loss_pct' end,
               case when p.cost and sb.avg_cost is null then 'closing_value' end]) z where z is not null),
      'drill', format('#/stockrep/ledger?item=%s&loc=%s&from=%s&to=%s', it.id, c.location_id, c.day, c.day + 1))
    from cd c left join cd n on n.item_id = c.item_id and n.location_id = c.location_id and n.day = c.day + 1
      join public.items it on it.id = c.item_id join public.locations lo on lo.id = c.location_id left join public.stock_balance sb on sb.item_id = c.item_id and sb.location_id = c.location_id cross join p
   where c.day between d1 and d2 and (c.closing <> 0 or coalesce(n.sales_net, 0) <> 0 or coalesce(n.loss, 0) <> 0);
$$;

create or replace function public._r4d_daily_closing(p_flt jsonb, p_res jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb := p_res; cost_ok boolean := public.rpt_cost_ok(); col jsonb; cols jsonb := '[]'::jsonb;
begin
  res := public._r4_addnote(res, public._r4_note('info', 'Closing stock at the end of each day (the ledger replayed by business day), beside what was sold and what was lost (wastage) on the NEXT day. For today the next day has not happened, so those cells are empty (not captured yet), not 0. % = next day quantity / closing. Value uses the average cost now.',
    'প্রতিটি দিনের শেষের স্টক (খাতা দিন ধরে), পাশে পরের দিন কত বিক্রি ও কত নষ্ট হয়েছে। আজকের পরের দিন এখনও আসেনি, তাই সেই ঘর ফাঁকা (এখনও নেই), ০ নয়। % = পরের দিনের পরিমাণ / শেষের স্টক। মূল্য এখনকার গড় খরচে।'));
  if not cost_ok then
    for col in select * from jsonb_array_elements(res -> 'columns') loop if col ->> 'key' <> 'closing_value' then cols := cols || jsonb_build_array(col); end if; end loop;
    res := jsonb_set(res, '{columns}', cols); res := public._r4_addnote(res, jsonb_build_object('code', 'cost_hidden'));
  end if;
  return res;
end $$;

insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('daily_closing', 'S8', 'stock', 'দিনের শেষের স্টক বনাম পরের দিনের বিক্রি ও ক্ষতি', 'Closing stock vs next-day sales and loss', 'দিনের শেষের Stock বনাম পরের দিনের বিক্রি ও ক্ষতি',
  '[["day","দিন","Day","date"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["unit","একক","Unit","text"],["closing_qty","দিনের শেষে স্টক","Closing stock","num"],["received_qty","সেদিন পাওয়া","Received that day","num"],["next_sales_qty","পরের দিন বিক্রি","Next-day sales","num"],["next_loss_qty","পরের দিন নষ্ট","Next-day loss","num"],["sales_pct","বিক্রি % (শেষের স্টকের)","Sales % of closing","pct"],["loss_pct","নষ্ট % (শেষের স্টকের)","Loss % of closing","pct"],["closing_value","শেষের স্টকের মূল্য","Closing value","money"]]'::jsonb,
  '{}', 'day', 'desc', array['locations','brands','categories','item_types'], false, false, false, 4208)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
  sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

-- ---------- #73 turnover and days on hand ----------
create or replace function public._r3q_item_turnover(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with p as (select (d2 - d1 + 1) as days, public.rpt_cost_ok() as cost, public.rpt_arr_text(flt -> 'categories') as cat, public._r4_types(flt) as ty),
  cd as (select * from public._r4_closing_daily(d1, d2, locs, (select ty from p), (select cat from p))),
  perday as (select item_id, day, sum(closing) as q from cd where day between d1 and d2 group by 1, 2),
  av as (select item_id, avg(q) as avg_q from perday group by 1),
  used as (select cd.item_id, sum(cd.sales_net) filter (where cd.day between d1 and d2) as sold from cd group by 1),
  iss as (select l.item_id, coalesce(-sum(l.qty_delta), 0) as q from public.stock_ledger l where l.reason = 'issue_out' and l.location_id = any (locs) and (l.made_at at time zone 'Asia/Dhaka')::date between d1 and d2 group by 1),
  now_ as (select b.item_id, sum(b.qty) as q, sum(b.qty * b.avg_cost) filter (where b.avg_cost is not null) as v, count(*) filter (where b.qty <> 0 and b.avg_cost is null) as unc from public.stock_balance b where b.location_id = any (locs) group by 1)
  select jsonb_build_object('item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn), 'unit', public._item_base(it.id), 'item_type', coalesce(t.label_bn, it.item_type),
      'sold_qty', round(coalesce(u.sold, 0), 4), 'issued_qty', round(coalesce(i.q, 0), 4), 'used_qty', round(coalesce(u.sold, 0) + coalesce(i.q, 0), 4), 'avg_stock_qty', round(a.avg_q, 4), 'on_hand_qty', round(coalesce(n.q, 0), 4),
      'turnover', case when a.avg_q > 0 and coalesce(u.sold, 0) + coalesce(i.q, 0) > 0 then round((coalesce(u.sold, 0) + coalesce(i.q, 0)) / a.avg_q, 3) end,
      'days_on_hand', case when a.avg_q > 0 and coalesce(u.sold, 0) + coalesce(i.q, 0) > 0 then round(a.avg_q * p.days / (coalesce(u.sold, 0) + coalesce(i.q, 0)), 1) end,
      'cover_days_now', case when coalesce(n.q, 0) > 0 and coalesce(u.sold, 0) + coalesce(i.q, 0) > 0 then round(n.q * p.days / (coalesce(u.sold, 0) + coalesce(i.q, 0)), 1) end,
      'value_on_hand', case when p.cost then round(n.v, 2) end, 'uncosted_places', case when p.cost then coalesce(n.unc, 0) end,
      '_nc', (select coalesce(jsonb_agg(z), '[]'::jsonb) from unnest(array[case when a.avg_q <= 0 or coalesce(u.sold, 0) + coalesce(i.q, 0) <= 0 then 'turnover' end, case when a.avg_q <= 0 or coalesce(u.sold, 0) + coalesce(i.q, 0) <= 0 then 'days_on_hand' end,
               case when coalesce(n.q, 0) <= 0 or coalesce(u.sold, 0) + coalesce(i.q, 0) <= 0 then 'cover_days_now' end]) z where z is not null),
      'drill', format('#/stockrep/recon?from=%s&to=%s', d1, d2))
    from av a join public.items it on it.id = a.item_id cross join p left join public.item_types t on t.code = it.item_type left join used u on u.item_id = a.item_id left join iss i on i.item_id = a.item_id left join now_ n on n.item_id = a.item_id
   where a.avg_q <> 0 or coalesce(u.sold, 0) + coalesce(i.q, 0) <> 0;
$$;

create or replace function public._r4d_item_turnover(p_flt jsonb, p_res jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb := p_res; cost_ok boolean := public.rpt_cost_ok(); col jsonb; cols jsonb := '[]'::jsonb;
begin
  res := public._r4_addnote(res, public._r4_note('info', 'Used = sold (net of voids and refunds) + issued to production, in the item''s base unit. Average stock = the mean of the book closing stock of every day of the period (all chosen places together). Turnover = used / average stock. Days on hand = average stock x days of the period / used. Where nothing was used, or the average stock is not above 0, these are empty (they cannot be worked out), never 0 and never an estimate. Wastage and transfers are not "used".',
    'ব্যবহার = বিক্রি (বাতিল ও ফেরত বাদে) + উৎপাদনে ইস্যু, আইটেমের নিজের এককে। গড় স্টক = সময়ের প্রতিদিনের বইয়ের শেষ স্টকের গড় (বাছা সব জায়গা মিলিয়ে)। টার্নওভার = ব্যবহার / গড় স্টক। দিন হাতে = গড় স্টক × সময়ের দিন / ব্যবহার। কিছু ব্যবহার না হলে বা গড় স্টক ০-র বেশি না হলে ঘর ফাঁকা (হিসাব করা যায় না), ০ বা আন্দাজ নয়। নষ্ট ও ট্রান্সফার "ব্যবহার" নয়।'));
  if not cost_ok then
    for col in select * from jsonb_array_elements(res -> 'columns') loop if col ->> 'key' not in ('value_on_hand', 'uncosted_places') then cols := cols || jsonb_build_array(col); end if; end loop;
    res := jsonb_set(res, '{columns}', cols); res := public._r4_addnote(res, jsonb_build_object('code', 'cost_hidden'));
  end if;
  return res;
end $$;

insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('item_turnover', 'S9', 'stock', 'স্টক টার্নওভার ও কত দিনের মাল হাতে', 'Stock turnover and days on hand', 'Stock turnover ও কত দিনের মাল হাতে',
  '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["item_type","ধরন","Type","text"],["unit","একক","Unit","text"],["sold_qty","বিক্রি (নিট)","Sold (net)","num"],["issued_qty","উৎপাদনে ইস্যু","Issued to production","num"],["used_qty","ব্যবহার","Used","num"],["avg_stock_qty","গড় স্টক","Average stock","num"],["turnover","টার্নওভার","Turnover","num"],["days_on_hand","কত দিনের মাল","Days on hand","num"],["on_hand_qty","এখন হাতে","On hand now","num"],["cover_days_now","এখনকার মাল কত দিনের","Days of cover now","num"],["value_on_hand","এখনকার মূল্য (খরচ জানা অংশ)","Value now (costed part)","money"],["uncosted_places","খরচ অজানা লাইন","Lines with no cost","int"]]'::jsonb,
  '{}', 'turnover', 'desc', array['locations','brands','categories','item_types'], false, false, false, 4209)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
  sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

select public._r3_lockdown();
select public._r4_lockdown();
notify pgrst, 'reload schema';

-- ===================== phase424.sql =====================
-- ============================================================
-- BOS tool · Phase 424 (RPT-B2 R4a): batches and freshness. Read-only. Paste after phase423. Safe to paste twice. Open to report_stock holders at their own places.
--   #67 item_slow            EXTENDED in place (engine 3, same key): sales net of refunds, stock on hand, its value, the last movement, and a state (not moving / no net sales / sold)
--   #70 batch_stock_rows     stock batch by batch with expiry and FEFO order, and one "unbatched" line per item and place so that batches + unbatched = the balance
--   #68 fg_ageing_rows       the age of finished-goods stock by batch (days since made), by item (oldest and weighted average); age bands only if the owner set report_aging_buckets
-- Raw material received without a lot cannot be aged (nothing records when it arrived): it shows as unbatched. Capturing the supplier lot on receipt is the R5 package, not this one.
-- The answer of the RPCs has the shape of the report viewer {columns, rows, totals, notes, sections} so web/batchrep.js can draw and export it.
-- ============================================================

-- answer builder: columns come as [[key, bn, en, type], ...]
create or replace function public._r4_ans(p_cols jsonb, p_rows jsonb, p_totals jsonb, p_notes jsonb, p_extra jsonb default '{}'::jsonb) returns jsonb
language sql immutable set search_path = public as $$
  select jsonb_build_object('columns', (select coalesce(jsonb_agg(jsonb_build_object('key', c ->> 0, 'label_bn', c ->> 1, 'label_en', c ->> 2, 'type', c ->> 3,
            'role', case when c ->> 3 in ('money', 'int', 'num', 'pct') then 'measure' else 'dim' end)), '[]'::jsonb) from jsonb_array_elements(p_cols) c),
    'rows', coalesce(p_rows, '[]'::jsonb), 'totals', p_totals, 'notes', coalesce(p_notes, '[]'::jsonb)) || coalesce(p_extra, '{}'::jsonb);
$$;
revoke all on function public._r4_ans(jsonb, jsonb, jsonb, jsonb, jsonb) from public, anon, authenticated;

-- age band label for an age in days, from the owner's list of band ends (rule report_aging_buckets, e.g. 1,3,7: 0-1, 2-3, 4-7, 8+); null when no bands
create or replace function public._r4_band(p_age int, p_bands int[]) returns text
language plpgsql immutable set search_path = public as $$
declare i int; lo int := 0;
begin
  if p_bands is null or cardinality(p_bands) = 0 or p_age is null then return null; end if;
  for i in 1..cardinality(p_bands) loop
    if p_age <= p_bands[i] then return lo || '-' || p_bands[i]; end if;
    lo := p_bands[i] + 1;
  end loop;
  return lo || '+';
end $$;
revoke all on function public._r4_band(int, int[]) from public, anon, authenticated;

-- the owner's band ends from the existing rule; null when empty or not a rising list (no default is invented)
create or replace function public._r4_bands() returns int[]
language plpgsql stable security definer set search_path = public as $$
declare bk text := public.rule_txt('report_aging_buckets'); b int[]; i int;
begin
  if bk is null or bk !~ '^[0-9]{1,4}(,[0-9]{1,4}){0,5}$' then return null; end if;
  b := string_to_array(bk, ',')::int[];
  for i in 2..cardinality(b) loop if b[i] <= b[i - 1] then return null; end if; end loop;
  return b;
end $$;
revoke all on function public._r4_bands() from public, anon, authenticated;

-- the family of a production batch: the batch itself and every batch that came from it by transfer (a transfer in carries the batch to the receiver as a new batch row)
create or replace function public._r4_lineage() returns table (root bigint, batch bigint)
language sql stable security definer set search_path = public as $$
  with recursive o as (select l.id, l.ref_id, l.batch_id, row_number() over (partition by l.ref_id order by l.id) as rn from public.stock_ledger l where l.reason = 'transfer_out' and l.ref_type = 'transfer' and l.batch_id is not null),
  i as (select l.id, l.ref_id, l.batch_id, row_number() over (partition by l.ref_id order by l.id) as rn from public.stock_ledger l where l.reason = 'transfer_in' and l.ref_type = 'transfer' and l.batch_id is not null),
  pairs as (select o.batch_id as parent, i.batch_id as child from o join i on i.ref_id = o.ref_id and i.rn = o.rn),
  roots as (select distinct l.batch_id as r from public.stock_ledger l where l.reason = 'production_in' and l.batch_id is not null),
  tree(root, batch) as (select r, r from roots union all select t.root, p.child from tree t join pairs p on p.parent = t.batch)
  select root, batch from tree;
$$;
revoke all on function public._r4_lineage() from public, anon, authenticated;

-- ---------- #67 slow and non-moving items, in place ----------
create or replace function public._r3q_item_slow(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with p as (select public.rpt_arr_text(flt -> 'categories') as cat, public._r4_types(flt) as ty, public.rpt_cost_ok() as cost, (now() at time zone 'Asia/Dhaka')::date as today),
  s as (select f.item_id, sum(f.qty) as qty, sum(f.net) as net, count(distinct f.sale_id) as bills, max(f.day) as last_sold
          from public.sales_fact f where f.status = 'done' and f.item_id is not null and f.day between d1 and d2 and f.location_id = any (locs) group by 1),
  r as (select (e ->> 'item_id')::uuid as item_id, sum((e ->> 'qty')::numeric) as rqty, sum((e ->> 'amount')::numeric) as ramt
          from public.sale_returns x cross join lateral jsonb_array_elements(case when jsonb_typeof(x.lines) = 'array' then x.lines else '[]'::jsonb end) e
         where x.status = 'done' and (x.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and x.location_id = any (locs) and nullif(e ->> 'item_id', '') is not null group by 1),
  oh as (select b.item_id, sum(b.qty) as q, sum(round(b.qty * b.avg_cost, 2)) filter (where b.avg_cost is not null) as v, count(*) filter (where b.qty <> 0 and b.avg_cost is null) as unc
           from public.stock_balance b where b.location_id = any (locs) group by 1),
  mv as (select l.item_id, max((l.made_at at time zone 'Asia/Dhaka')::date) as d from public.stock_ledger l where l.location_id = any (locs) and l.reason not in ('opening', 'count_adjust') group by 1)
  select jsonb_build_object('item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn), 'category', coalesce(it.category, '(none)'), 'item_type', coalesce(t.label_bn, it.item_type),
      'qty', coalesce(round(s.qty, 3), 0), 'net', coalesce(round(s.net, 2), 0), 'bills', coalesce(s.bills, 0), 'last_sold', s.last_sold,
      'refund_qty', coalesce(round(r.rqty, 3), 0), 'net_qty', coalesce(round(s.qty, 3), 0) - coalesce(round(r.rqty, 3), 0), 'net_after_refunds', coalesce(round(s.net, 2), 0) - coalesce(round(r.ramt, 2), 0),
      'on_hand', case when it.tracked then round(coalesce(oh.q, 0), 3) end, 'unit', public._item_base(it.id),
      'value', case when p.cost and it.tracked and coalesce(oh.q, 0) <> 0 and oh.v is not null then round(oh.v, 2) end, 'uncosted_lines', case when p.cost and it.tracked then coalesce(oh.unc, 0) end,
      'last_movement', mv.d, 'days_since_movement', p.today - mv.d,
      'state', case when it.tracked and coalesce(oh.q, 0) > 0 and (mv.d is null or mv.d < d1) then 'not_moving'
                    when coalesce(s.qty, 0) - coalesce(r.rqty, 0) <= 0 then 'no_net_sales' else 'sold' end,
      '_nc', (select coalesce(jsonb_agg(z), '[]'::jsonb) from unnest(array[case when not it.tracked then 'on_hand' end, case when it.tracked and mv.d is null then 'last_movement' end,
                case when p.cost and it.tracked and coalesce(oh.q, 0) <> 0 and oh.v is null then 'value' end]) z where z is not null),
      'drill', format('#/stockrep/recon?from=%s&to=%s', d1, d2))
    from public.items it cross join p left join public.item_types t on t.code = it.item_type left join s on s.item_id = it.id left join r on r.item_id = it.id left join oh on oh.item_id = it.id left join mv on mv.item_id = it.id
   where it.is_active and it.sellable and it.retired_at is null and (p.cat is null or it.category = any (p.cat)) and (p.ty is null or it.item_type = any (p.ty));
$$;

create or replace function public._r4d_item_slow(p_flt jsonb, p_res jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb := p_res; cost_ok boolean := public.rpt_cost_ok(); col jsonb; cols jsonb := '[]'::jsonb; tot jsonb := coalesce(p_res -> 'totals', '{}'::jsonb);
begin
  res := public._r4_addnote(res, public._r4_note('info', 'Sales are the sales of the period; refunds of the same period are taken off ("net qty", "net after refunds"; the old columns qty and net are unchanged). Stock on hand is the book balance now at the chosen places. Last movement is the last ledger movement that is not an opening entry or a count correction. State: not moving = stock on hand and no movement in the period; no net sales = nothing left after refunds; sold. No limit is used to call an item "slow": sort by net qty.',
    'বিক্রি = সময়ের বিক্রি; একই সময়ের ফেরত বাদ ("নিট পরিমাণ", "ফেরতের পর নিট"; আগের qty ও net কলাম অপরিবর্তিত)। হাতে স্টক = বাছা জায়গার এখনকার বইয়ের ব্যালান্স। শেষ নড়াচড়া = ওপেনিং ও গণনা-সংশোধন ছাড়া শেষ খাতা-নড়াচড়া। অবস্থা: নড়ছে না = স্টক আছে কিন্তু সময়ে কোনো নড়াচড়া নেই; নিট বিক্রি নেই = ফেরতের পর কিছু নেই; বিক্রি হয়েছে। "ধীর" বলার কোনো সীমা বসানো হয়নি: নিট পরিমাণ অনুযায়ী সাজান।'));
  if not cost_ok then
    for col in select * from jsonb_array_elements(res -> 'columns') loop if col ->> 'key' not in ('value', 'uncosted_lines') then cols := cols || jsonb_build_array(col); end if; end loop;
    res := jsonb_set(res, '{columns}', cols); tot := tot - 'value'; res := public._r4_addnote(res, jsonb_build_object('code', 'cost_hidden'));
  end if;
  return jsonb_set(res, '{totals}', tot);
end $$;

insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('item_slow', 'S10', 'sales', 'ধীর ও অবিক্রীত আইটেম', 'Slow and unsold items', 'ধীর ও unsold Item',
  '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["category","ক্যাটাগরি","Category","text"],["item_type","ধরন","Type","text"],["qty","বিক্রি পরিমাণ","Qty sold","num"],["refund_qty","ফেরত","Refunded qty","num"],["net_qty","নিট পরিমাণ","Net qty","num"],["net","বিক্রি","Sales","money"],["net_after_refunds","ফেরতের পর নিট","Net after refunds","money"],["bills","বিল","Bills","int"],["last_sold","শেষ বিক্রি","Last sold","date"],["on_hand","হাতে স্টক","On hand","num"],["unit","একক","Unit","text"],["value","স্টকের মূল্য","Stock value","money"],["uncosted_lines","খরচ অজানা লাইন","Lines with no cost","int"],["last_movement","শেষ নড়াচড়া","Last movement","date"],["days_since_movement","কত দিন নড়েনি","Days since movement","int"],["state","অবস্থা","State","text"]]'::jsonb,
  array['net','net_after_refunds','value'], 'net_qty', 'asc', array['locations','brands','categories','item_types'], false, false, false, 4210)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
  sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

-- ---------- #70 / #68 batch rows: every open batch, plus the unbatched part of the balance ----------
create or replace function public._r4_batch_rows(p_locs int[], p_item uuid, p_types text[], p_cost boolean) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with t as (select (now() at time zone 'Asia/Dhaka')::date as today, coalesce(public.rule_num('report_expiry_soon_days'), public.rule_num('expiry_warn_days')) as thr, public._r4_bands() as bands),
  b as (
    select sb.id as bid, sb.batch_no, sb.item_id, sb.location_id, sb.made_at, sb.expires_at, sb.qty_made, sb.qty_remaining
      from public.stock_batches sb join public.items it on it.id = sb.item_id
     where sb.qty_remaining > 0 and sb.location_id = any (p_locs) and (p_item is null or sb.item_id = p_item) and (p_types is null or it.item_type = any (p_types)) and it.is_active),
  rk as (select b.bid, row_number() over (partition by b.item_id, b.location_id order by (b.expires_at is not null and b.expires_at <= now()), b.expires_at nulls last, b.made_at, b.bid) as r from b),
  rt as (select l.batch as bid, min(l.root) as root from public._r4_lineage() l group by 1),
  bs as (select b.item_id, b.location_id, sum(b.qty_remaining) as q from b group by 1, 2),
  bal as (
    select sbl.item_id, sbl.location_id, sbl.qty, sbl.avg_cost from public.stock_balance sbl join public.items it on it.id = sbl.item_id
     where sbl.location_id = any (p_locs) and (p_item is null or sbl.item_id = p_item) and (p_types is null or it.item_type = any (p_types)) and it.is_active and it.tracked)
  select jsonb_build_object('item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn), 'item_type', coalesce(ty.label_bn, it.item_type), 'item_type_en', coalesce(ty.label_en, ty.label_bn, it.item_type),
      'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn), 'row_kind', 'batch', 'batch_no', coalesce(b.batch_no, '#' || b.bid), 'batch_id', b.bid, 'root_batch', rt.root,
      'origin', (select l.reason from public.stock_ledger l where l.batch_id = b.bid and l.qty_delta > 0 order by l.id limit 1),
      'made_on', (b.made_at at time zone 'Asia/Dhaka')::date, 'age_days', t.today - (b.made_at at time zone 'Asia/Dhaka')::date, 'age_band', public._r4_band(t.today - (b.made_at at time zone 'Asia/Dhaka')::date, t.bands),
      'expires_on', (b.expires_at at time zone 'Asia/Dhaka')::date, 'days_left', (b.expires_at at time zone 'Asia/Dhaka')::date - t.today,
      'state', case when b.expires_at is null then 'no_expiry' when (b.expires_at at time zone 'Asia/Dhaka')::date < t.today then 'expired' when (b.expires_at at time zone 'Asia/Dhaka')::date <= t.today + coalesce(t.thr::int, -1) then 'soon' else 'ok' end,
      'qty', b.qty_remaining, 'unit', public._item_base(it.id), 'qty_made', b.qty_made, 'remaining_pct', round(b.qty_remaining * 100.0 / nullif(b.qty_made, 0), 1), 'item_balance', coalesce(bl.qty, 0), 'fefo_rank', rk.r,
      'value', case when p_cost and bl.avg_cost is not null then round(b.qty_remaining * bl.avg_cost, 2) end, 'qc_blocked', public._qc_batch_blocked60(b.bid),
      '_nc', (select coalesce(jsonb_agg(z), '[]'::jsonb) from unnest(array[case when b.expires_at is null then 'expires_on' end, case when b.expires_at is null then 'days_left' end,
               case when p_cost and bl.avg_cost is null then 'value' end]) z where z is not null),
      'drill', format('#/batchrep/trace?batch=%s', coalesce(rt.root, b.bid)))
    from b join public.items it on it.id = b.item_id join public.locations lo on lo.id = b.location_id join rk on rk.bid = b.bid left join rt on rt.bid = b.bid left join bal bl on bl.item_id = b.item_id and bl.location_id = b.location_id
      left join public.item_types ty on ty.code = it.item_type cross join t
  union all
  select jsonb_build_object('item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn), 'item_type', coalesce(ty.label_bn, it.item_type), 'item_type_en', coalesce(ty.label_en, ty.label_bn, it.item_type),
      'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn), 'row_kind', 'unbatched', 'batch_no', null, 'batch_id', null, 'root_batch', null, 'origin', null,
      'made_on', null, 'age_days', null, 'age_band', null, 'expires_on', null, 'days_left', null, 'state', 'unbatched', 'qty', round(bl.qty - coalesce(bs.q, 0), 4), 'unit', public._item_base(it.id), 'qty_made', null, 'remaining_pct', null,
      'item_balance', bl.qty, 'fefo_rank', null, 'value', case when p_cost and bl.avg_cost is not null then round((bl.qty - coalesce(bs.q, 0)) * bl.avg_cost, 2) end, 'qc_blocked', false,
      '_nc', (select coalesce(jsonb_agg(z), '[]'::jsonb) from unnest(array['made_on', 'age_days', 'expires_on', 'days_left', case when p_cost and bl.avg_cost is null then 'value' end]) z where z is not null),
      'drill', format('#/stockrep/ledger?item=%s&loc=%s', it.id, bl.location_id))
    from bal bl join public.items it on it.id = bl.item_id join public.locations lo on lo.id = bl.location_id left join bs on bs.item_id = bl.item_id and bs.location_id = bl.location_id left join public.item_types ty on ty.code = it.item_type
   where abs(bl.qty - coalesce(bs.q, 0)) > 0.0005;
$$;
revoke all on function public._r4_batch_rows(int[], uuid, text[], boolean) from public, anon, authenticated;

create or replace function public.batch_stock_rows(p_loc int default null, p_item uuid default null, p_types text[] default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; ty text[]; cost_ok boolean; rows_ jsonb; n int; nb int; nu numeric; thr numeric; src text; notes jsonb := '[]'::jsonb; cap constant int := 1500; cols jsonb; nne int;
begin
  if not public.is_active() or not public.rpt_access('stock') then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  locs := coalesce(array(select l.id from public.locations l where public.can_loc(l.id) and (p_loc is null or l.id = p_loc)), '{}');
  ty := case when p_types is null or cardinality(p_types) = 0 then null else coalesce(array(select t.code from public.item_types t where t.code = any (p_types)), '{}') end;
  cost_ok := public.rpt_cost_ok();
  select coalesce(jsonb_agg(r order by r ->> 'item_code', r ->> 'location_en', (r ->> 'fefo_rank')::int nulls last), '[]'::jsonb), count(*) into rows_, n from (select * from public._r4_batch_rows(locs, p_item, ty, cost_ok) r limit cap + 1) z(r);
  if n > cap then rows_ := rows_ - cap; notes := notes || jsonb_build_array(public._r4_note('truncated', 'More than ' || cap || ' rows: narrow by place, item or type.', cap || 'টির বেশি সারি: জায়গা, আইটেম বা ধরন দিয়ে ছোট করুন।')); end if;
  select count(*) filter (where e ->> 'row_kind' = 'batch'), coalesce(sum((e ->> 'qty')::numeric) filter (where e ->> 'row_kind' = 'unbatched' and (e ->> 'qty')::numeric > 0), 0), count(*) filter (where e ->> 'state' = 'no_expiry')
    into nb, nu, nne from jsonb_array_elements(rows_) e;
  thr := coalesce(public.rule_num('report_expiry_soon_days'), public.rule_num('expiry_warn_days'));
  src := case when public.rule_num('report_expiry_soon_days') is not null then 'report_expiry_soon_days' when public.rule_num('expiry_warn_days') is not null then 'expiry_warn_days' end;
  notes := notes || jsonb_build_array(public._r4_note('info', 'Every open batch of the chosen items and places, in the order the system takes them (FEFO: not expired first, earliest expiry first, expired last), and one "unbatched" line per item and place for the part of the balance that is in no batch (negative = sold beyond stock). Batches + unbatched = the balance of the item at that place. '
      || case when thr is not null then 'Soon = expires within ' || thr::int || ' day(s) (rule ' || src || ').' else 'No "days ahead" rule is set, so only expired batches are marked.' end,
    'প্রতিটি খোলা ব্যাচ, সিস্টেম যে ক্রমে নেয় (FEFO) সেই ক্রমে, আর প্রতিটি আইটেম-জায়গায় ব্যাচ-বহির্ভূত অংশের জন্য একটি "unbatched" লাইন (ঋণাত্মক = স্টকের বাইরে বিক্রি)। ব্যাচ + unbatched = সেই জায়গায় আইটেমের ব্যালান্স।'));
  if nne > 0 then notes := notes || jsonb_build_array(public._r4_note('data_needed', nne || ' batch(es) have no expiry date captured (shown as "no expiry", not safe). Expiry is captured when the item has a shelf-life rule or the batch is entered with an expiry.',
      nne || 'টি ব্যাচে মেয়াদ লেখা নেই ("no expiry", নিরাপদ নয়)। আইটেমের শেলফ-লাইফ নিয়ম থাকলে বা ব্যাচে মেয়াদ দিলে মেয়াদ লেখা হয়।', 'shelf_life_rules / expires_at')); end if;
  if nu > 0 then notes := notes || jsonb_build_array(public._r4_note('data_needed', 'Stock of ' || nu::numeric(14,3) || ' (summed over items of different units, so only a pointer) sits in no batch: its receipt date and expiry are not captured, so it cannot be aged or traced.',
      'ব্যাচ ছাড়া স্টক আছে (' || nu::numeric(14,3) || ', ভিন্ন এককের যোগ, তাই শুধু ইঙ্গিত): এর গ্রহণের তারিখ ও মেয়াদ লেখা নেই, তাই বয়স বা ট্রেস করা যায় না।', 'lot / batch on receipt')); end if;
  if not cost_ok then notes := notes || jsonb_build_array(jsonb_build_object('code', 'cost_hidden')); end if;
  cols := '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["item_type","ধরন","Type","text"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["row_kind","ধরন (ব্যাচ/ব্যাচ-ছাড়া)","Row","text"],["batch_no","ব্যাচ","Batch","text"],["origin","উৎস","Origin","text"],["made_on","তৈরি/গ্রহণ","Made / received","date"],["expires_on","মেয়াদ শেষ","Expires","date"],["days_left","বাকি দিন","Days left","int"],["state","অবস্থা","State","text"],["qty","পরিমাণ","Qty","num"],["unit","একক","Unit","text"],["remaining_pct","বাকি %","Remaining %","pct"],["item_balance","আইটেমের ব্যালান্স","Item balance","num"],["fefo_rank","FEFO ক্রম","FEFO order","int"]]'::jsonb
         || case when cost_ok then '[["value","মূল্য","Value","money"]]'::jsonb else '[]'::jsonb end;
  return public._r4_ans(cols, rows_, null, notes, jsonb_build_object('cost_shown', cost_ok, 'batches', nb, 'truncated', n > cap));
end $$;
revoke all on function public.batch_stock_rows(int, uuid, text[]) from public, anon;
grant execute on function public.batch_stock_rows(int, uuid, text[]) to authenticated;

-- #68 ageing of finished goods: batch rows with the age, and a per-item summary (oldest and the quantity-weighted average age)
create or replace function public.fg_ageing_rows(p_loc int default null, p_types text[] default array['finished_good']) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; ty text[]; cost_ok boolean; rows_ jsonb; n int; bands int[]; notes jsonb := '[]'::jsonb; cap constant int := 1500; cols jsonb; sec jsonb; nu int;
begin
  if not public.is_active() or not public.rpt_access('stock') then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  locs := coalesce(array(select l.id from public.locations l where public.can_loc(l.id) and (p_loc is null or l.id = p_loc)), '{}');
  ty := case when p_types is null or cardinality(p_types) = 0 then null else coalesce(array(select t.code from public.item_types t where t.code = any (p_types)), '{}') end;
  cost_ok := public.rpt_cost_ok(); bands := public._r4_bands();
  select coalesce(jsonb_agg(r order by (r ->> 'age_days')::int desc nulls last, r ->> 'item_code'), '[]'::jsonb), count(*) into rows_, n from (select * from public._r4_batch_rows(locs, null, ty, cost_ok) r limit cap + 1) z(r);
  if n > cap then rows_ := rows_ - cap; notes := notes || jsonb_build_array(public._r4_note('truncated', 'More than ' || cap || ' rows: narrow by place or type.', cap || 'টির বেশি সারি: জায়গা বা ধরন দিয়ে ছোট করুন।')); end if;
  select count(*) into nu from jsonb_array_elements(rows_) e where e ->> 'row_kind' = 'unbatched' and (e ->> 'qty')::numeric > 0;
  sec := jsonb_build_array(jsonb_build_object('id', 'by_item', 'title_bn', 'আইটেম অনুযায়ী বয়স', 'title_en', 'Age by item',
    'columns', '[{"key":"item_name","label_bn":"আইটেম","label_en":"Item","type":"text"},{"key":"location","label_bn":"লোকেশন","label_en":"Location","type":"text"},{"key":"batches","label_bn":"ব্যাচ","label_en":"Batches","type":"int"},{"key":"qty","label_bn":"পরিমাণ","label_en":"Qty","type":"num"},{"key":"oldest_days","label_bn":"সবচেয়ে পুরনো (দিন)","label_en":"Oldest (days)","type":"int"},{"key":"avg_days","label_bn":"গড় বয়স (পরিমাণ ধরে, দিন)","label_en":"Average age (qty weighted, days)","type":"num"}]'::jsonb,
    'rows', coalesce((select jsonb_agg(jsonb_build_object('item_name', g.nm, 'location', g.loc, 'batches', g.c, 'qty', g.q, 'oldest_days', g.o, 'avg_days', g.a) order by g.o desc, g.nm)
                        from (select e ->> 'item_name' as nm, e ->> 'location_en' as loc, count(*) as c, sum((e ->> 'qty')::numeric) as q, max((e ->> 'age_days')::int) as o,
                                     round(sum((e ->> 'qty')::numeric * (e ->> 'age_days')::int) / nullif(sum((e ->> 'qty')::numeric), 0), 1) as a
                                from jsonb_array_elements(rows_) e where e ->> 'row_kind' = 'batch' group by 1, 2) g), '[]'::jsonb)));
  if bands is null then
    notes := notes || jsonb_build_array(public._r4_note('data_needed', 'No age bands are set (rule report_aging_buckets, e.g. 1,3,7). The age is shown in days for every batch; no band is invented.',
      'বয়সের ভাগ বসানো নেই (নিয়ম report_aging_buckets, যেমন 1,3,7)। প্রতিটি ব্যাচের বয়স দিনে দেখানো; কোনো ভাগ নিজে বানানো হয়নি।', 'report_aging_buckets'));
  else notes := notes || jsonb_build_array(public._r4_note('info', 'Age bands (days) come from the rule report_aging_buckets.', 'বয়সের ভাগ (দিন) নিয়ম report_aging_buckets থেকে।')); end if;
  notes := notes || jsonb_build_array(public._r4_note('info', 'Age = days since the batch was made. Finished goods are made in the app, so the made date is known; a transferred batch keeps the made date of its production. Stock that sits in no batch has no made date and is listed as "unbatched".',
    'বয়স = ব্যাচ তৈরির পর কত দিন। তৈরি পণ্য অ্যাপেই তৈরি হয়, তাই তৈরির তারিখ জানা; ট্রান্সফার হলেও ব্যাচ উৎপাদনের তারিখ রাখে। যে স্টক কোনো ব্যাচে নেই তার তৈরির তারিখ নেই, "unbatched" দেখানো হয়।'));
  if nu > 0 then notes := notes || jsonb_build_array(public._r4_note('data_needed', nu || ' item/place line(s) hold stock in no batch (age not captured).', nu || 'টি আইটেম-জায়গায় ব্যাচ ছাড়া স্টক আছে (বয়স লেখা নেই)।', 'batch')); end if;
  if not cost_ok then notes := notes || jsonb_build_array(jsonb_build_object('code', 'cost_hidden')); end if;
  cols := '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["row_kind","ধরন","Row","text"],["batch_no","ব্যাচ","Batch","text"],["made_on","তৈরি","Made","date"],["age_days","বয়স (দিন)","Age (days)","int"],["age_band","বয়সের ভাগ","Age band","text"],["expires_on","মেয়াদ শেষ","Expires","date"],["days_left","বাকি দিন","Days left","int"],["state","অবস্থা","State","text"],["qty","বাকি পরিমাণ","Qty left","num"],["unit","একক","Unit","text"],["qty_made","তৈরি হয়েছিল","Qty made","num"],["remaining_pct","বাকি %","Remaining %","pct"]]'::jsonb
         || case when cost_ok then '[["value","মূল্য","Value","money"]]'::jsonb else '[]'::jsonb end;
  return public._r4_ans(cols, rows_, null, notes, jsonb_build_object('cost_shown', cost_ok, 'sections', sec, 'truncated', n > cap, 'bands', to_jsonb(bands)));
end $$;
revoke all on function public.fg_ageing_rows(int, text[]) from public, anon;
grant execute on function public.fg_ageing_rows(int, text[]) to authenticated;

select public._r3_lockdown();
select public._r4_lockdown();
notify pgrst, 'reload schema';

-- ===================== phase425.sql =====================
-- ============================================================
-- BOS tool · Phase 425 (RPT-B2 R4b): where did each production batch go. Read-only. Paste after phase424. Safe to paste twice. Open to report_stock holders at their own places.
--   #80 unsold_by_batch       for every production batch: made, sold (net of voids and refunds), wasted, other (count / issue), short in transit, still on the road, still in stock, and the check that they add up
--   #84 fg_distribution       the same by outlet: what each outlet received from each batch, sold, wasted, holds, is still waiting for; sales that carry no batch are a line of their own
--   #79 expired_damaged_unsold  wastage entries grouped as expired / damaged / unsold, and customer returns marked damaged (whether they went back into sellable stock)
--   fg_batch_rows(batch)      the source rows of one production batch family (drill of the three reports above)
-- Wastage reason "unsold" is added to the existing list wastage_reasons (a list value, BUILD-RULES 4); nothing else in the list is touched.
-- A batch family is the production batch plus the batch rows its transfers created at the receivers (the batch travels with the goods). Sales made beyond stock carry no batch and cannot be traced.
-- ============================================================

insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort) values
 ('wastage_reasons', 'unsold', 'বিক্রি হয়নি (অবিক্রীত)', 'বিক্রি হয়নি / Unsold', 'Unsold', 7)
on conflict (list_code, value_code) do nothing;

-- per production batch: where the quantity is (one row per root)
create or replace function public._r4_fg_batch_agg() returns table (root bigint, made_qty numeric, sold_net numeric, wasted numeric, other_qty numeric, in_transit numeric, short_qty numeric, remaining numeric, unaccounted numeric)
language sql stable security definer set search_path = public as $$
  with lin as (select * from public._r4_lineage()),
  lr as (select ln.root, l.* from lin ln join public.stock_ledger l on l.batch_id = ln.batch),
  tr as (
    select lr.root, lr.ref_id, -sum(lr.qty_delta) filter (where lr.reason = 'transfer_out') as out_q, sum(lr.qty_delta) filter (where lr.reason = 'transfer_in') as in_q, sum(lr.qty_delta) filter (where lr.reason = 'reversal') as rev_q
      from lr where lr.ref_type = 'transfer' group by 1, 2),
  trc as (
    select tr.root, sum(case when t.status = 'sent' then coalesce(tr.out_q, 0) - coalesce(tr.in_q, 0) - coalesce(tr.rev_q, 0) else 0 end) as in_transit,
           sum(case when t.status = 'received' then coalesce(tr.out_q, 0) - coalesce(tr.in_q, 0) else 0 end) as short_q
      from tr join public.stock_transfers t on t.id::text = tr.ref_id group by 1),
  rem as (select ln.root, sum(b.qty_remaining) as q from lin ln join public.stock_batches b on b.id = ln.batch group by 1),
  agg as (
    select lr.root,
           coalesce(-sum(lr.qty_delta) filter (where lr.reason in ('sale_out', 'sale_void_in', 'sale_return')), 0) as sold_net,
           coalesce(-sum(lr.qty_delta) filter (where lr.reason = 'wastage'), 0) as wasted,
           coalesce(-sum(lr.qty_delta) filter (where lr.reason in ('count_adjust', 'issue_out', 'purchase_return') or (lr.reason = 'reversal' and coalesce(lr.ref_type, '') <> 'transfer')), 0) as other_q
      from lr group by lr.root)
  select b.id, b.qty_made, coalesce(a.sold_net, 0), coalesce(a.wasted, 0), coalesce(a.other_q, 0), coalesce(c.in_transit, 0), coalesce(c.short_q, 0), coalesce(r.q, 0),
         round(b.qty_made - (coalesce(a.sold_net, 0) + coalesce(a.wasted, 0) + coalesce(a.other_q, 0) + coalesce(c.in_transit, 0) + coalesce(c.short_q, 0) + coalesce(r.q, 0)), 4)
    from (select distinct root from lin) x join public.stock_batches b on b.id = x.root left join agg a on a.root = x.root left join trc c on c.root = x.root left join rem r on r.root = x.root;
$$;
revoke all on function public._r4_fg_batch_agg() from public, anon, authenticated;

-- #80 unsold finished goods by production batch
create or replace function public.unsold_by_batch(p_from date default null, p_to date default null, p_loc int default null, p_types text[] default null, p_open_only boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare today date := (now() at time zone 'Asia/Dhaka')::date; f date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 30); t date := coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date);
        locs int[]; ty text[]; cost_ok boolean := public.rpt_cost_ok(); rows_ jsonb; n int; notes jsonb := '[]'::jsonb; cols jsonb; bad int; thr numeric; cap constant int := 800; noexp int;
begin
  if not public.is_active() or not public.rpt_access('stock') then raise exception 'not allowed'; end if;
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  locs := coalesce(array(select l.id from public.locations l where public.can_loc(l.id) and (p_loc is null or l.id = p_loc)), '{}');
  ty := case when p_types is null or cardinality(p_types) = 0 then null else coalesce(array(select x.code from public.item_types x where x.code = any (p_types)), '{}') end;
  thr := coalesce(public.rule_num('report_expiry_soon_days'), public.rule_num('expiry_warn_days'));
  select coalesce(jsonb_agg(z.j order by (z.j ->> 'made_on') desc, z.j ->> 'item_code'), '[]'::jsonb), count(*) into rows_, n from (
    select jsonb_build_object('item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn), 'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn),
        'batch_id', b.id, 'made_on', (b.made_at at time zone 'Asia/Dhaka')::date, 'age_days', today - (b.made_at at time zone 'Asia/Dhaka')::date, 'expires_on', (b.expires_at at time zone 'Asia/Dhaka')::date,
        'days_left', (b.expires_at at time zone 'Asia/Dhaka')::date - today,
        'state', case when a.remaining + a.in_transit <= 0 then 'finished' when b.expires_at is null then 'no_expiry' when (b.expires_at at time zone 'Asia/Dhaka')::date < today then 'expired'
                      when (b.expires_at at time zone 'Asia/Dhaka')::date <= today + coalesce(thr::int, -1) then 'soon' else 'ok' end,
        'unit', public._item_base(it.id), 'made_qty', a.made_qty, 'sold_qty', a.sold_net, 'wasted_qty', a.wasted, 'other_qty', a.other_qty, 'short_qty', a.short_qty, 'in_transit_qty', a.in_transit,
        'remaining_qty', a.remaining, 'unsold_qty', a.remaining + a.in_transit, 'unsold_pct', case when a.made_qty > 0 then round((a.remaining + a.in_transit) * 100.0 / a.made_qty, 1) end, 'unaccounted_qty', a.unaccounted,
        'unit_cost', case when cost_ok then pc.unit_cost end, 'unsold_value', case when cost_ok and pc.unit_cost is not null then round((a.remaining + a.in_transit) * pc.unit_cost, 2) end,
        '_nc', (select coalesce(jsonb_agg(zz), '[]'::jsonb) from unnest(array[case when b.expires_at is null then 'expires_on' end, case when b.expires_at is null then 'days_left' end,
                 case when cost_ok and pc.unit_cost is null then 'unit_cost' end, case when cost_ok and pc.unit_cost is null then 'unsold_value' end]) zz where zz is not null),
        'drill', format('#/batchrep/trace?batch=%s', b.id)) as j
      from public._r4_fg_batch_agg() a join public.stock_batches b on b.id = a.root join public.items it on it.id = b.item_id join public.locations lo on lo.id = b.location_id
        left join lateral (select l.unit_cost from public.stock_ledger l where l.batch_id = b.id and l.reason = 'production_in' order by l.id limit 1) pc on true
     where (b.made_at at time zone 'Asia/Dhaka')::date between f and t and b.location_id = any (locs) and (ty is null or it.item_type = any (ty))
       and (not p_open_only or a.remaining + a.in_transit > 0)
     order by b.made_at desc limit cap + 1) z;
  if n > cap then rows_ := rows_ - cap; notes := notes || jsonb_build_array(public._r4_note('truncated', 'More than ' || cap || ' batches: narrow the dates.', cap || 'টির বেশি ব্যাচ: তারিখ ছোট করুন।')); end if;
  select count(*) into bad from jsonb_array_elements(rows_) e where abs((e ->> 'unaccounted_qty')::numeric) > 0.0005;
  select count(*) into noexp from jsonb_array_elements(rows_) e where e ->> 'state' = 'no_expiry';
  notes := notes || jsonb_build_array(public._r4_note('info', 'Per production batch: made = sold (net of voids and refunds) + wasted + other (count corrections, issues) + short in transit + on the road + in stock. "Unsold" = in stock + on the road. The family of a batch includes the batch rows its transfers created at the outlets. Sales made beyond stock carry no batch and are not in any row (see the distribution report). Value = unsold quantity x the cost recorded at production; where none was recorded it is empty (not captured).',
    'প্রতিটি উৎপাদন ব্যাচ: তৈরি = বিক্রি (বাতিল ও ফেরত বাদে) + নষ্ট + অন্যান্য (গণনা সংশোধন, ইস্যু) + পথে কম + পথে আছে + স্টকে আছে। "অবিক্রীত" = স্টকে + পথে। ব্যাচের পরিবারে ট্রান্সফারে আউটলেটে তৈরি ব্যাচ-সারিও ধরা। স্টকের বাইরে বিক্রির কোনো ব্যাচ নেই, তাই কোনো সারিতে নেই (বিতরণ রিপোর্ট দেখুন)। মূল্য = অবিক্রীত পরিমাণ × উৎপাদনে লেখা খরচ; না থাকলে ফাঁকা।'));
  if bad > 0 then notes := notes || jsonb_build_array(public._r4_note('data_needed', bad || ' batch(es) do not add up (made does not equal the parts). The column "not accounted" shows the difference; open the batch to see its rows.',
      bad || 'টি ব্যাচের হিসাব মিলছে না। "হিসাবহীন" কলামে পার্থক্য; ব্যাচ খুলে সারি দেখুন।', 'stock_batches.qty_remaining')); end if;
  if noexp > 0 then notes := notes || jsonb_build_array(public._r4_note('data_needed', noexp || ' batch(es) have no expiry date captured (no shelf-life rule for the item).', noexp || 'টি ব্যাচে মেয়াদ লেখা নেই (আইটেমের শেলফ-লাইফ নিয়ম নেই)।', 'shelf_life_rules')); end if;
  if not cost_ok then notes := notes || jsonb_build_array(jsonb_build_object('code', 'cost_hidden')); end if;
  cols := '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["location_bn","কোথায় তৈরি","Made at","text"],["location_en","Made at (EN)","Made at (EN)","text"],["batch_id","ব্যাচ নং","Batch","int"],["made_on","তৈরি","Made","date"],["age_days","বয়স (দিন)","Age (days)","int"],["expires_on","মেয়াদ শেষ","Expires","date"],["days_left","বাকি দিন","Days left","int"],["state","অবস্থা","State","text"],["unit","একক","Unit","text"],["made_qty","তৈরি","Made","num"],["sold_qty","বিক্রি (নিট)","Sold (net)","num"],["wasted_qty","নষ্ট","Wasted","num"],["other_qty","অন্যান্য","Other","num"],["short_qty","পথে কম","Short in transit","num"],["in_transit_qty","পথে আছে","On the road","num"],["remaining_qty","স্টকে আছে","In stock","num"],["unsold_qty","অবিক্রীত","Unsold","num"],["unsold_pct","অবিক্রীত %","Unsold %","pct"],["unaccounted_qty","হিসাবহীন","Not accounted","num"]]'::jsonb
         || case when cost_ok then '[["unit_cost","উৎপাদন খরচ (প্রতি একক)","Cost per unit","money"],["unsold_value","অবিক্রীতের মূল্য","Unsold value","money"]]'::jsonb else '[]'::jsonb end;
  return public._r4_ans(cols, rows_, null, notes, jsonb_build_object('from', f, 'to', t, 'cost_shown', cost_ok, 'truncated', n > cap));
end $$;
revoke all on function public.unsold_by_batch(date, date, int, text[], boolean) from public, anon;
grant execute on function public.unsold_by_batch(date, date, int, text[], boolean) to authenticated;

-- #84 distribution of finished goods by outlet and batch
create or replace function public.fg_distribution(p_from date default null, p_to date default null, p_loc int default null, p_types text[] default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 30); t date := coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date); locs int[]; ty text[]; cost_ok boolean := public.rpt_cost_ok();
        rows_ jsonb; n int; notes jsonb := '[]'::jsonb; cols jsonb; nobatch numeric; cap constant int := 1500;
begin
  if not public.is_active() or not public.rpt_access('stock') then raise exception 'not allowed'; end if;
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  locs := coalesce(array(select l.id from public.locations l where public.can_loc(l.id) and (p_loc is null or l.id = p_loc)), '{}');
  ty := case when p_types is null or cardinality(p_types) = 0 then null else coalesce(array(select x.code from public.item_types x where x.code = any (p_types)), '{}') end;
  with roots as (
    select b.id as root, b.item_id, b.location_id as made_loc, b.made_at, b.expires_at from public.stock_batches b join public.items it on it.id = b.item_id
     where b.id in (select distinct l.root from public._r4_lineage() l) and (b.made_at at time zone 'Asia/Dhaka')::date between f and t and (ty is null or it.item_type = any (ty))),
  lr as (select ln.root, l.* from public._r4_lineage() ln join roots r on r.root = ln.root join public.stock_ledger l on l.batch_id = ln.batch),
  perloc as (
    select lr.root, lr.location_id,
           coalesce(sum(lr.qty_delta) filter (where lr.reason in ('production_in', 'transfer_in')), 0) as in_qty,
           coalesce(-sum(lr.qty_delta) filter (where lr.reason in ('sale_out', 'sale_void_in', 'sale_return')), 0) as sold_net,
           coalesce(-sum(lr.qty_delta) filter (where lr.reason = 'wastage'), 0) as wasted,
           coalesce(-sum(lr.qty_delta) filter (where lr.reason in ('count_adjust', 'issue_out', 'purchase_return')), 0) as other_q,
           coalesce(-sum(lr.qty_delta) filter (where lr.reason = 'transfer_out'), 0) as sent_on
      from lr group by lr.root, lr.location_id),
  rem as (select ln.root, b.location_id, sum(b.qty_remaining) as q from public._r4_lineage() ln join roots r on r.root = ln.root join public.stock_batches b on b.id = ln.batch group by 1, 2),
  tr as (
    select lr.root, lr.ref_id, -sum(lr.qty_delta) filter (where lr.reason = 'transfer_out') as out_q, sum(lr.qty_delta) filter (where lr.reason = 'transfer_in') as in_q, sum(lr.qty_delta) filter (where lr.reason = 'reversal') as rev_q
      from lr where lr.ref_type = 'transfer' group by 1, 2),
  dest as (
    select tr.root, x.to_location_id as location_id,
           sum(case when x.status = 'sent' then coalesce(tr.out_q, 0) - coalesce(tr.in_q, 0) - coalesce(tr.rev_q, 0) else 0 end) as on_road,
           sum(case when x.status = 'received' then coalesce(tr.out_q, 0) - coalesce(tr.in_q, 0) else 0 end) as short_q
      from tr join public.stock_transfers x on x.id::text = tr.ref_id group by 1, 2),
  keys as (select root, location_id from perloc union select root, location_id from rem union select root, location_id from dest),
  rr as (
    select r.root, r.item_id, k.location_id, r.made_at, r.expires_at, r.made_loc, coalesce(p.in_qty, 0) as in_qty, coalesce(p.sold_net, 0) as sold_net, coalesce(p.wasted, 0) as wasted, coalesce(p.other_q, 0) as other_q,
           coalesce(p.sent_on, 0) as sent_on, coalesce(m.q, 0) as remaining, coalesce(d.on_road, 0) as on_road, coalesce(d.short_q, 0) as short_q
      from keys k join roots r on r.root = k.root left join perloc p on p.root = k.root and p.location_id = k.location_id left join rem m on m.root = k.root and m.location_id = k.location_id
        left join dest d on d.root = k.root and d.location_id = k.location_id where k.location_id = any (locs)),
  js as (
    select jsonb_build_object('item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn), 'batch_id', rr.root, 'made_on', (rr.made_at at time zone 'Asia/Dhaka')::date,
        'expires_on', (rr.expires_at at time zone 'Asia/Dhaka')::date, 'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn), 'role', case when rr.location_id = rr.made_loc then 'made_here' else 'outlet' end,
        'unit', public._item_base(it.id), 'received_qty', rr.in_qty, 'sold_qty', rr.sold_net, 'wasted_qty', rr.wasted, 'other_qty', rr.other_q, 'sent_on_qty', rr.sent_on, 'short_qty', rr.short_q,
        'on_road_qty', rr.on_road, 'remaining_qty', rr.remaining,
        'sold_pct', case when rr.in_qty > 0 then round(rr.sold_net * 100.0 / rr.in_qty, 1) end,
        '_nc', case when rr.expires_at is null then '["expires_on"]'::jsonb end,
        'drill', format('#/batchrep/trace?batch=%s', rr.root)) as j, rr.made_at as mk, it.code as ic
      from rr join public.items it on it.id = rr.item_id join public.locations lo on lo.id = rr.location_id
    union all
    select jsonb_build_object('item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn), 'batch_id', null, 'made_on', null, 'expires_on', null, 'location_bn', lo.name_bn,
        'location_en', coalesce(lo.name_en, lo.name_bn), 'role', 'no_batch', 'unit', public._item_base(it.id), 'received_qty', null, 'sold_qty', -sum(l.qty_delta), 'wasted_qty', null, 'other_qty', null, 'sent_on_qty', null, 'short_qty', null,
        'on_road_qty', null, 'remaining_qty', null, 'sold_pct', null, '_nc', '["batch_id","made_on","expires_on","received_qty"]'::jsonb, 'drill', format('#/stockrep/ledger?item=%s&loc=%s', it.id, l.location_id)), now() - interval '100 years', it.code
      from public.stock_ledger l join public.items it on it.id = l.item_id join public.locations lo on lo.id = l.location_id
     where l.batch_id is null and l.reason in ('sale_out', 'sale_void_in', 'sale_return') and (l.made_at at time zone 'Asia/Dhaka')::date between f and t and l.location_id = any (locs) and (ty is null or it.item_type = any (ty))
       and it.id in (select item_id from roots)
     group by it.id, it.code, it.name_bn, it.name_en, lo.id, lo.name_bn, lo.name_en, l.location_id having sum(l.qty_delta) <> 0)
  select coalesce(jsonb_agg(js.j order by js.mk desc, js.ic), '[]'::jsonb), count(*) into rows_, n from js;
  select coalesce(sum((e ->> 'sold_qty')::numeric), 0) into nobatch from jsonb_array_elements(rows_) e where e ->> 'role' = 'no_batch';
  if n > cap then rows_ := rows_ - cap; notes := notes || jsonb_build_array(public._r4_note('truncated', 'More than ' || cap || ' rows: narrow the dates or the place.', cap || 'টির বেশি সারি: তারিখ বা জায়গা ছোট করুন।')); end if;
  notes := notes || jsonb_build_array(public._r4_note('info', 'One row per production batch and place: what the place received from the batch (made here counts as received at the production place), what it sold (net of voids and refunds), wasted, corrected by a count, passed on to another place, holds now, and what is still on the road to it. "Short" is what was lost between sending and receiving. The line "no batch" is the sales of the same items that carry no batch (sold beyond stock): they cannot be linked to a production batch.',
    'প্রতিটি উৎপাদন ব্যাচ ও জায়গার জন্য একটি সারি: জায়গা ব্যাচ থেকে কত পেয়েছে (তৈরির জায়গায় তৈরি = পাওয়া), কত বিক্রি (বাতিল ও ফেরত বাদে), নষ্ট, গণনায় সংশোধন, অন্য জায়গায় পাঠানো, এখন কত আছে, আর কত এখনও পথে। "কম" = পাঠানো ও পাওয়ার মাঝে হারানো। "no batch" সারি = একই আইটেমের যে বিক্রির ব্যাচ নেই (স্টকের বাইরে বিক্রি); এগুলো উৎপাদন ব্যাচের সাথে মেলানো যায় না।'));
  if nobatch > 0 then notes := notes || jsonb_build_array(public._r4_note('data_needed', 'Sales with no batch exist for these items (sold beyond stock): their batch, made date and expiry are not captured.',
      'এই আইটেমগুলোর ব্যাচ-ছাড়া বিক্রি আছে (স্টকের বাইরে বিক্রি): এদের ব্যাচ, তৈরির তারিখ ও মেয়াদ লেখা নেই।', 'stock_ledger.batch_id')); end if;
  cols := '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["batch_id","ব্যাচ নং","Batch","int"],["made_on","তৈরি","Made","date"],["expires_on","মেয়াদ শেষ","Expires","date"],["location_bn","জায়গা","Place","text"],["location_en","Place (EN)","Place (EN)","text"],["role","ভূমিকা","Role","text"],["unit","একক","Unit","text"],["received_qty","পেয়েছে","Received","num"],["sold_qty","বিক্রি (নিট)","Sold (net)","num"],["wasted_qty","নষ্ট","Wasted","num"],["other_qty","অন্যান্য","Other","num"],["sent_on_qty","আরেক জায়গায় পাঠিয়েছে","Sent on","num"],["short_qty","পথে কম","Short in transit","num"],["on_road_qty","পথে আছে","On the road","num"],["remaining_qty","এখন আছে","Holds now","num"],["sold_pct","বিক্রি % (পাওয়ার)","Sold % of received","pct"]]'::jsonb;
  return public._r4_ans(cols, rows_, null, notes, jsonb_build_object('from', f, 'to', t, 'cost_shown', cost_ok, 'truncated', n > cap));
end $$;
revoke all on function public.fg_distribution(date, date, int, text[]) from public, anon;
grant execute on function public.fg_distribution(date, date, int, text[]) to authenticated;

-- #79 expired, damaged and unsold: wastage entries by class, and customer returns marked damaged
create or replace function public.expired_damaged_unsold(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 30); t date := coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date); locs int[]; cost_ok boolean := public.rpt_cost_ok(); rows_ jsonb; n int;
        notes jsonb := '[]'::jsonb; cols jsonb; sec jsonb; cap constant int := 1500; n_unsold int; n_other int; nrules int; n_ret int; n_ret_back int;
begin
  if not public.is_active() or not public.rpt_access('stock') then raise exception 'not allowed'; end if;
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  locs := coalesce(array(select l.id from public.locations l where public.can_loc(l.id) and (p_loc is null or l.id = p_loc)), '{}');
  select coalesce(jsonb_agg(z.j order by z.j ->> 'day' desc, z.j ->> 'item_code'), '[]'::jsonb), count(*) into rows_, n from (
    select jsonb_build_object('day', (w.made_at at time zone 'Asia/Dhaka')::date, 'class', case w.reason_code when 'expired' then 'expired' when 'unsold' then 'unsold' else 'damaged' end, 'source', 'wastage',
        'reason', coalesce(o.label_en, w.reason_code), 'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn), 'item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn),
        'qty', w.qty, 'unit', public._item_base(it.id), 'batch_id', sb.id, 'batch_made_on', (sb.made_at at time zone 'Asia/Dhaka')::date, 'batch_age_days', case when sb.id is not null then (w.made_at at time zone 'Asia/Dhaka')::date - (sb.made_at at time zone 'Asia/Dhaka')::date end,
        'value', case when cost_ok and sl.unit_cost is not null then round(w.qty * sl.unit_cost, 2) end, 'back_in_stock', null, 'note', w.note, 'who', w.created_staff,
        '_nc', (select coalesce(jsonb_agg(zz), '[]'::jsonb) from unnest(array[case when cost_ok and sl.unit_cost is null then 'value' end, case when sb.id is null then 'batch_id' end]) zz where zz is not null),
        'drill', case when sb.id is not null then format('#/batchrep/trace?batch=%s', coalesce((select min(l2.root) from public._r4_lineage() l2 where l2.batch = sb.id), sb.id)) else format('#/stockrep/ledger?item=%s&loc=%s', it.id, w.location_id) end) as j
      from public.stock_wastage w join public.items it on it.id = w.item_id join public.locations lo on lo.id = w.location_id left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = w.reason_code
        left join public.stock_ledger sl on sl.id = w.ledger_id left join public.stock_batches sb on sb.id = coalesce(w.batch_id, sl.batch_id)
     where w.reason_code in ('expired', 'unsold', 'broken', 'burnt', 'spoiled') and (w.made_at at time zone 'Asia/Dhaka')::date between f and t and w.location_id = any (locs)
    union all
    select jsonb_build_object('day', (r.created_at at time zone 'Asia/Dhaka')::date, 'class', 'damaged', 'source', 'customer return', 'reason', 'Damaged (customer return)', 'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn),
        'item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn), 'qty', (e ->> 'qty')::numeric, 'unit', e ->> 'unit', 'batch_id', null, 'batch_made_on', null, 'batch_age_days', null,
        'value', null, 'back_in_stock', coalesce((select sum(l.qty_delta) from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.item_id = it.id), 0) > 0,
        'note', r.note, 'who', r.created_staff, '_nc', '["batch_id","value"]'::jsonb, 'drill', format('#/stockrep/ledger?item=%s&loc=%s', it.id, r.location_id))
      from public.sale_returns r cross join lateral jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) e
        join public.items it on it.id::text = e ->> 'item_id' join public.locations lo on lo.id = r.location_id
     where r.status = 'done' and r.reason_code = 'damaged' and (r.created_at at time zone 'Asia/Dhaka')::date between f and t and r.location_id = any (locs)) z;
  if n > cap then rows_ := rows_ - cap; notes := notes || jsonb_build_array(public._r4_note('truncated', 'More than ' || cap || ' rows: narrow the dates.', cap || 'টির বেশি সারি: তারিখ ছোট করুন।')); end if;
  select count(*) into n_unsold from public.stock_wastage w where w.reason_code = 'unsold' and (w.made_at at time zone 'Asia/Dhaka')::date between f and t and w.location_id = any (locs);
  select count(*) into n_other from public.stock_wastage w where w.reason_code not in ('expired', 'unsold', 'broken', 'burnt', 'spoiled') and (w.made_at at time zone 'Asia/Dhaka')::date between f and t and w.location_id = any (locs);
  select count(*), count(*) filter (where (e ->> 'back_in_stock')::boolean) into n_ret, n_ret_back from jsonb_array_elements(rows_) e where e ->> 'source' = 'customer return';
  select count(*) into nrules from public.w1c_return_class_rules;
  sec := jsonb_build_array(jsonb_build_object('id', 'by_class', 'title_bn', 'ধরন অনুযায়ী', 'title_en', 'By class',
    'columns', '[{"key":"class","label_bn":"ধরন","label_en":"Class","type":"text"},{"key":"entries","label_bn":"এন্ট্রি","label_en":"Entries","type":"int"}]'::jsonb || case when cost_ok then '[{"key":"value","label_bn":"মূল্য (খরচ জানা অংশ)","label_en":"Value (costed part)","type":"money"},{"key":"uncosted","label_bn":"খরচ অজানা","label_en":"No cost","type":"int"}]'::jsonb else '[]'::jsonb end,
    'rows', coalesce((select jsonb_agg(jsonb_build_object('class', g.c, 'entries', g.n, 'value', case when cost_ok then g.v end, 'uncosted', case when cost_ok then g.u end) order by g.c)
                        from (select e ->> 'class' as c, count(*) as n, coalesce(sum((e ->> 'value')::numeric), 0) as v, count(*) filter (where e ->> 'source' = 'wastage' and e -> 'value' = 'null'::jsonb) as u from jsonb_array_elements(rows_) e group by 1) g), '[]'::jsonb)));
  notes := notes || jsonb_build_array(public._r4_note('info', 'Classes: expired = wastage reason Expired; unsold = reason Unsold (unsold stock written off at the end of the day); damaged = reasons Broken, Burnt, Spoiled, and customer returns marked Damaged. Other reasons (sample, staff meal, unknown: ' || n_other || ' entries in the period) are not in this list; see the Wastage report.',
    'ধরন: expired = কারণ "মেয়াদ শেষ"; unsold = কারণ "অবিক্রীত" (দিনশেষে অবিক্রীত মাল বাদ); damaged = কারণ ভেঙে/পুড়ে/নষ্ট এবং গ্রাহকের "ক্ষতিগ্রস্ত" ফেরত। অন্য কারণ (নমুনা, স্টাফ খাবার, অজানা: ' || n_other || 'টি) এই তালিকায় নেই; "অপচয়" রিপোর্ট দেখুন।'));
  if n_unsold = 0 then notes := notes || jsonb_build_array(public._r4_note('info', 'No entry with the reason Unsold in this period. Staff write unsold stock off with the reason Unsold (the reason was added to the wastage reasons list).',
      'এই সময়ে "অবিক্রীত" কারণে কোনো এন্ট্রি নেই। অবিক্রীত মাল বাদ দিতে কারণ "অবিক্রীত" দিন (কারণটি অপচয়ের কারণ তালিকায় যোগ হয়েছে)।')); end if;
  if n_ret > 0 and nrules = 0 then notes := notes || jsonb_build_array(public._r4_note('data_needed', n_ret_back || ' of ' || n_ret || ' damaged customer return(s) went BACK into sellable stock: no return class rules are set (damaged items are restocked unless the owner sets a rule).',
      n_ret || 'টি ক্ষতিগ্রস্ত ফেরতের মধ্যে ' || n_ret_back || 'টি বিক্রির স্টকে ফিরে গেছে: ফেরতের শ্রেণি-নিয়ম বসানো নেই (মালিক নিয়ম না দিলে ক্ষতিগ্রস্ত মালও স্টকে ফেরে)।', 'w1c_return_class_rules')); end if;
  if not cost_ok then notes := notes || jsonb_build_array(jsonb_build_object('code', 'cost_hidden')); end if;
  cols := '[["day","তারিখ","Date","date"],["class","ধরন","Class","text"],["source","উৎস","Source","text"],["reason","কারণ","Reason","text"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["qty","পরিমাণ","Qty","num"],["unit","একক","Unit","text"],["batch_id","ব্যাচ","Batch","int"],["batch_made_on","ব্যাচ তৈরি","Batch made","date"],["batch_age_days","ক্ষতির সময়ে বয়স (দিন)","Age when lost (days)","int"],["back_in_stock","স্টকে ফিরেছে","Back in stock","text"],["note","নোট","Note","text"],["who","কে","Who","text"]]'::jsonb
         || case when cost_ok then '[["value","মূল্য","Value","money"]]'::jsonb else '[]'::jsonb end;
  return public._r4_ans(cols, rows_, null, notes, jsonb_build_object('from', f, 'to', t, 'cost_shown', cost_ok, 'sections', sec, 'truncated', n > cap));
end $$;
revoke all on function public.expired_damaged_unsold(date, date, int) from public, anon;
grant execute on function public.expired_damaged_unsold(date, date, int) to authenticated;

-- the source rows of one production batch family (drill target of the three reports and of the batch stock list)
create or replace function public.fg_batch_rows(p_batch bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare cost_ok boolean := public.rpt_cost_ok(); b public.stock_batches; it public.items; rt_id bigint; agg record; fam jsonb; rows_ jsonb; n int; cap constant int := 1000;
begin
  if not public.is_active() or not public.rpt_access('stock') then raise exception 'not allowed'; end if;
  select min(l.root) into rt_id from public._r4_lineage() l where l.batch = p_batch;
  if rt_id is null then rt_id := p_batch; end if;
  select * into b from public.stock_batches where id = rt_id;
  if not found then raise exception 'batch_not_found'; end if;
  if not public.can_loc(b.location_id) and not exists (select 1 from public._r4_lineage() l join public.stock_batches x on x.id = l.batch where l.root = rt_id and public.can_loc(x.location_id)) then raise exception 'not allowed for this location'; end if;
  select * into it from public.items where id = b.item_id;
  select * into agg from public._r4_fg_batch_agg() a where a.root = b.id;
  select coalesce(jsonb_agg(jsonb_build_object('batch_id', x.id, 'location_id', x.location_id, 'location', coalesce(lo.name_en, lo.name_bn), 'made_on', (x.made_at at time zone 'Asia/Dhaka')::date,
      'expires_on', (x.expires_at at time zone 'Asia/Dhaka')::date, 'qty_made', x.qty_made, 'qty_remaining', x.qty_remaining, 'is_root', x.id = rt_id) order by x.id), '[]'::jsonb) into fam
    from public._r4_lineage() l join public.stock_batches x on x.id = l.batch join public.locations lo on lo.id = x.location_id where l.root = rt_id and public.can_loc(x.location_id);
  select coalesce(jsonb_agg(z.j order by z.mk, z.id), '[]'::jsonb), count(*) into rows_, n from (
    select jsonb_build_object('id', l.id, 'at', l.made_at, 'day', (l.made_at at time zone 'Asia/Dhaka')::date, 'time', to_char(l.made_at at time zone 'Asia/Dhaka', 'HH24:MI'), 'location', coalesce(lo.name_en, lo.name_bn), 'batch_id', l.batch_id,
        'reason', l.reason, 'qty_delta', l.qty_delta, 'unit_cost', case when cost_ok then l.unit_cost end, 'note', l.note, 'doc', public._r4_doc(l.reason, l.ref_type, l.ref_id, cost_ok)) as j, l.made_at as mk, l.id
      from public._r4_lineage() ln join public.stock_ledger l on l.batch_id = ln.batch join public.locations lo on lo.id = l.location_id where ln.root = rt_id and public.can_loc(l.location_id) order by l.made_at, l.id limit cap + 1) z;
  if n > cap then rows_ := rows_ - cap; end if;
  return jsonb_build_object('batch_id', rt_id, 'item', jsonb_build_object('code', it.code, 'name_bn', it.name_bn, 'name_en', coalesce(it.name_en, it.name_bn), 'unit', public._item_base(it.id)),
    'made_on', (b.made_at at time zone 'Asia/Dhaka')::date, 'expires_on', (b.expires_at at time zone 'Asia/Dhaka')::date, 'location_id', b.location_id,
    'summary', jsonb_build_object('made_qty', agg.made_qty, 'sold_qty', agg.sold_net, 'wasted_qty', agg.wasted, 'other_qty', agg.other_qty, 'short_qty', agg.short_qty, 'in_transit_qty', agg.in_transit, 'remaining_qty', agg.remaining, 'unaccounted_qty', agg.unaccounted),
    'family', fam, 'rows', rows_, 'truncated', n > cap, 'cost_shown', cost_ok);
end $$;
revoke all on function public.fg_batch_rows(bigint) from public, anon;
grant execute on function public.fg_batch_rows(bigint) to authenticated;

select public._r4_lockdown();
notify pgrst, 'reload schema';

-- ===================== phase430.sql =====================
-- Phase 430 (bos430) - RPT-B3 / R5a: SUPPLIER LOT AND EXPIRY CAPTURED AT THE RAW RECEIPT (audit item #83, data-capture gap 1).
-- Paste after phase99 (needs phase10 purchases and batches, phase60 grn_batch_links). Paste-twice safe. Earlier phase files are not edited and no shared function is re-created here:
-- the two places where a shared function must call this package are HOOKS (docs/integration/RPT-B3.md, tests/sql/rb3_hooks430.sql). Until the integrator pastes the hook, the screen
-- (web/purchase.js) calls receipt_lots_apply itself right after posting, so the feature works without it; only the server side "lot required" refusal needs the hook.
--
-- WHAT THIS ADDS
--   1. Table receipt_lots: the supplier's lot / batch number and expiry date typed on a purchase line (optional by default). Staged while the bill is a draft, applied (one stock batch
--      per lot, with batch_no and expiry) when the bill is posted. A line may have several lots (then each lot gives its own quantity). Stock that gets no lot stays "unbatched"
--      and is counted and printed by stock_unbatched (the lot reports never show a figure for it).
--   2. receipt_lots_stage(bill, lots), receipt_lots_get(bill), receipt_lots_apply(bill), receipt_lot_check(bill), stock_unbatched(loc, item).
--   3. Settings (rules): receipt_lot_required (OFF) and receipt_expiry_required (OFF). OFF = today's behaviour, nothing is refused. ON = a bill with tracked stock lines cannot be
--      posted until each such line has a lot number (and an expiry date when the second switch is ON). The check is _rb3_lot_gate, called by the hook in post_purchase.
--   4. Grants: none new. Writing needs purchase_entry at the bill's place (or the owner); reading needs the purchase, stock or quality report right or the same writing right.
-- The paper form code of this capture is NOT invented here: paper form code: to be given by owner. Until then the digital entry on the purchase line is the record.

do $g$ begin
  if to_regclass('public.grn_batch_links') is null or to_regclass('public.purchase_lines') is null then raise exception 'phase430 needs phase10 and phase60 first'; end if;
end $g$;

-- ---------- generic helper: exact-text patch of a LIVE function (marker = no-op on a second paste; a missing site stops everything) ----------
create or replace function public._rb3_patch(p_fn regprocedure, p_pairs text[], p_marker text) returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int;
begin
  if p_marker is null or length(p_marker) < 4 then raise exception 'marker_required'; end if;
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    if position(p_pairs[i] in def) = 0 then raise exception 'patch site not found in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception 'patch of % carries no marker %', p_fn::text, p_marker; end if;
  execute def;
  return true;
end $$;

-- ---------- settings ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('receipt_lot_required', 'purchase', 'switch', 'false', null, null, null, null, 'ক্রয় বিলে স্টক লাইনে সাপ্লায়ারের লট নম্বর লাগবে', 'Purchase bill এর stock line এ supplier lot no লাগবে', 'A purchase bill needs the supplier lot number on every stock line before it can be posted', 'OFF by default: the lot is optional. Needs the hook in post_purchase to be refused on the server (the screen asks either way).', 130),
 ('receipt_expiry_required', 'purchase', 'switch', 'false', null, null, null, null, 'লটের সাথে মেয়াদের তারিখও লাগবে', 'Lot এর সাথে expiry date ও লাগবে', 'The lot also needs an expiry date (works together with the lot switch)', 'OFF by default', 131)
on conflict (key) do nothing;

-- ---------- table ----------
create table if not exists public.receipt_lots (
  id bigserial primary key,
  bill_id uuid not null references public.purchase_bills(id),
  line_no int not null,
  item_id uuid not null references public.items(id),
  supplier_id uuid not null references public.suppliers(id),
  location_id int not null references public.locations(id),
  lot_no text check (lot_no is null or length(btrim(lot_no)) between 1 and 40),
  expiry_date date,
  qty numeric check (qty is null or (qty > 0 and qty <= 1000000000000)),           -- in the unit written on the line; null = the whole line
  status text not null default 'staged' check (status in ('staged', 'applied', 'no_stock')),
  batch_id bigint,                                                                 -- the stock batch made when the bill was posted (no FK on purpose, like grn_batch_links)
  qty_base numeric,
  created_by uuid, created_at timestamptz not null default now(), applied_at timestamptz,
  check (lot_no is not null or expiry_date is not null)
);
create index if not exists receipt_lots_bill on public.receipt_lots (bill_id, line_no);
create index if not exists receipt_lots_batch on public.receipt_lots (batch_id) where batch_id is not null;
create index if not exists receipt_lots_item on public.receipt_lots (item_id, supplier_id);
drop trigger if exists audit_receipt_lots on public.receipt_lots;
create trigger audit_receipt_lots after insert or update or delete on public.receipt_lots for each row execute function public.log_change('id');
alter table public.receipt_lots enable row level security;
drop policy if exists receipt_lots_read on public.receipt_lots;
create policy receipt_lots_read on public.receipt_lots for select to authenticated using (public.can_loc(location_id));
revoke all on public.receipt_lots from public, anon, authenticated;
grant select on public.receipt_lots to authenticated;
revoke all on sequence public.receipt_lots_id_seq from public, anon, authenticated;

-- ---------- who may read / write ----------
create or replace function public._rb3_view_ok(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and public.can_loc(p_loc) and (public.is_owner() or public.rpt_access('stock') or public.rpt_access('quality') or public.rpt_access('purchase')
    or public.has_grant('purchase_entry', p_loc) or public.has_grant('grn_batch', p_loc));
$$;

-- the lines of a bill that take stock (tracked, not an asset, not a free-text line)
create or replace function public._rb3_stock_lines(p_bill uuid) returns table (line_no int, item_id uuid, code text, name_bn text, name_en text, qty numeric, unit text, base_qty numeric)
language sql stable security definer set search_path = public as $$
  select l.line_no, l.item_id, i.code, i.name_bn, i.name_en, l.qty, l.unit, l.base_qty
    from public.purchase_lines l join public.items i on i.id = l.item_id
   where l.bill_id = p_bill and i.tracked and coalesce(i.item_type, '') <> 'asset' order by l.line_no;
$$;

-- ---------- stage the lots of a DRAFT bill (replaces the staged rows of that bill; applied rows are never touched) ----------
-- p_lots: [{"line_no":1,"lot_no":"L-1","expiry":"2026-12-31","qty":50}]   (qty optional = the whole line)
create or replace function public.receipt_lots_stage(p_bill uuid, p_lots jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pb public.purchase_bills; x jsonb; ln record; lot text; ex date; q numeric; n int := 0; today date := (now() at time zone 'Asia/Dhaka')::date; seen jsonb := '{}'::jsonb; sumq numeric;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into pb from public.purchase_bills where id = p_bill for update;
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(pb.location_id) then raise exception 'not allowed for this location'; end if;
  if not (public.is_owner() or public.has_grant('purchase_entry', pb.location_id)) then raise exception 'not allowed'; end if;
  if pb.kind <> 'bill' then raise exception 'lots_only_on_bills'; end if;
  if pb.status <> 'draft' then raise exception 'not_draft'; end if;
  if p_lots is null or jsonb_typeof(p_lots) <> 'array' or jsonb_array_length(p_lots) > 200 then raise exception 'bad_lots'; end if;
  delete from public.receipt_lots where bill_id = p_bill and status = 'staged';
  for x in select * from jsonb_array_elements(p_lots) loop
    if jsonb_typeof(x) <> 'object' then raise exception 'bad_lots'; end if;
    lot := nullif(btrim(x ->> 'lot_no'), ''); ex := nullif(x ->> 'expiry', '')::date;
    q := nullif(x ->> 'qty', '')::numeric;
    if lot is null and ex is null and q is null then continue; end if;
    if lot is null and ex is null then raise exception 'lot_or_expiry_needed'; end if;
    if lot is not null and length(lot) > 40 then raise exception 'bad_lot_no'; end if;
    if ex is not null and (ex < pb.bill_date or ex > today + 3650) then raise exception 'bad_expiry'; end if;
    if q is not null and not (q between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
    select * into ln from public._rb3_stock_lines(p_bill) l where l.line_no = (x ->> 'line_no')::int;
    if not found then raise exception 'line_not_stock'; end if;
    insert into public.receipt_lots (bill_id, line_no, item_id, supplier_id, location_id, lot_no, expiry_date, qty, created_by)
      values (p_bill, ln.line_no, ln.item_id, pb.supplier_id, pb.location_id, lot, ex, q, auth.uid());
    n := n + 1;
  end loop;
  -- several lots on one line: each needs its own quantity and together they cannot exceed the line
  for ln in select l.line_no, count(*) as c, count(*) filter (where r.qty is null) as nq, sum(r.qty) as sq from public.receipt_lots r join public.purchase_lines l on l.bill_id = r.bill_id and l.line_no = r.line_no
             where r.bill_id = p_bill and r.status = 'staged' group by l.line_no loop
    if ln.c > 1 and ln.nq > 0 then raise exception 'qty_needed_for_each_lot'; end if;
    select qty into sumq from public.purchase_lines where bill_id = p_bill and line_no = ln.line_no;
    if ln.sq is not null and ln.sq > sumq + 0.00005 then raise exception 'lots_exceed_line'; end if;
  end loop;
  return jsonb_build_object('staged', n);
end $$;

-- ---------- read the lots of a bill (staged and applied) ----------
create or replace function public.receipt_lots_get(p_bill uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pb public.purchase_bills;
begin
  select * into pb from public.purchase_bills where id = p_bill;
  if not found then raise exception 'not found'; end if;
  if not public._rb3_view_ok(pb.location_id) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'line_no', r.line_no, 'item_id', r.item_id, 'lot_no', r.lot_no, 'expiry', r.expiry_date, 'qty', r.qty, 'status', r.status,
    'batch_id', r.batch_id, 'qty_base', r.qty_base) order by r.line_no, r.id) from public.receipt_lots r where r.bill_id = p_bill), '[]'::jsonb);
end $$;

-- ---------- what is missing for the "required" switches (also used by the server gate) ----------
create or replace function public.receipt_lot_check(p_bill uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pb public.purchase_bills; ln record; miss jsonb := '[]'::jsonb; needlot boolean := public.rule_on('receipt_lot_required'); needexp boolean := public.rule_on('receipt_expiry_required');
begin
  select * into pb from public.purchase_bills where id = p_bill;
  if not found then raise exception 'not found'; end if;
  if not public._rb3_view_ok(pb.location_id) then raise exception 'not allowed'; end if;
  if pb.kind = 'bill' then
    for ln in select * from public._rb3_stock_lines(p_bill) loop
      if (needlot and not exists (select 1 from public.receipt_lots r where r.bill_id = p_bill and r.line_no = ln.line_no and r.lot_no is not null))
         or (needexp and not exists (select 1 from public.receipt_lots r where r.bill_id = p_bill and r.line_no = ln.line_no and r.expiry_date is not null)) then
        miss := miss || jsonb_build_object('line_no', ln.line_no, 'code', ln.code, 'name_bn', ln.name_bn, 'name_en', ln.name_en,
          'lot_missing', needlot and not exists (select 1 from public.receipt_lots r where r.bill_id = p_bill and r.line_no = ln.line_no and r.lot_no is not null),
          'expiry_missing', needexp and not exists (select 1 from public.receipt_lots r where r.bill_id = p_bill and r.line_no = ln.line_no and r.expiry_date is not null));
      end if;
    end loop;
  end if;
  return jsonb_build_object('lot_required', needlot, 'expiry_required', needexp, 'missing', miss);
end $$;

-- the refusal itself (called by the hook at the start of post_purchase; harmless when both switches are OFF)
create or replace function public._rb3_lot_gate(p_bill uuid) returns void
language plpgsql security definer set search_path = public as $$
declare pb public.purchase_bills; ln record; needlot boolean := public.rule_on('receipt_lot_required'); needexp boolean := public.rule_on('receipt_expiry_required');
begin
  if not (needlot or needexp) then return; end if;
  select * into pb from public.purchase_bills where id = p_bill;
  if not found or pb.kind <> 'bill' or pb.status <> 'draft' then return; end if;
  for ln in select * from public._rb3_stock_lines(p_bill) loop
    if needlot and not exists (select 1 from public.receipt_lots r where r.bill_id = p_bill and r.line_no = ln.line_no and r.lot_no is not null) then
      raise exception 'lot_required' using detail = ln.code, hint = 'line ' || ln.line_no::text;
    end if;
    if needexp and not exists (select 1 from public.receipt_lots r where r.bill_id = p_bill and r.line_no = ln.line_no and r.expiry_date is not null) then
      raise exception 'expiry_required' using detail = ln.code, hint = 'line ' || ln.line_no::text;
    end if;
  end loop;
end $$;

-- ---------- apply the staged lots of a POSTED bill: one stock batch per lot (internal core, no permission check: the callers did it) ----------
create or replace function public._rb3_lot_apply(p_bill uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pb public.purchase_bills; r public.receipt_lots; ln public.purchase_lines; f numeric; bq numeric; free numeric; done_line numeric; viaGrn numeric; bid bigint;
        applied int := 0; nostock int := 0; ids bigint[] := '{}';
begin
  select * into pb from public.purchase_bills where id = p_bill;
  if not found or pb.kind <> 'bill' or pb.status <> 'posted' then return jsonb_build_object('applied', 0, 'no_stock', 0, 'batches', '[]'::jsonb, 'not_posted', true); end if;
  for r in select * from public.receipt_lots where bill_id = p_bill and status = 'staged' order by line_no, id for update loop
    select * into ln from public.purchase_lines where bill_id = p_bill and line_no = r.line_no;
    if not found or ln.base_qty is null then continue; end if;
    f := public._unit_factor_base(ln.item_id, ln.unit);
    bq := case when r.qty is null then ln.base_qty else r.qty * coalesce(ln.base_qty / nullif(ln.qty, 0), f) end;
    select coalesce(sum(x.qty_base), 0) into done_line from public.receipt_lots x where x.bill_id = p_bill and x.line_no = r.line_no and x.status = 'applied';
    select coalesce(sum(g.qty_base), 0) into viaGrn from public.grn_batch_links g where g.source_type = 'purchase' and g.source_id = p_bill and g.item_id = ln.item_id;
    bq := round(least(bq, ln.base_qty - done_line - viaGrn), 4);
    insert into public.stock_balance (item_id, location_id) values (r.item_id, r.location_id) on conflict do nothing;
    select b.qty - coalesce((select sum(sb.qty_remaining) from public.stock_batches sb where sb.item_id = r.item_id and sb.location_id = r.location_id and sb.qty_remaining > 0), 0) into free
      from public.stock_balance b where b.item_id = r.item_id and b.location_id = r.location_id for update;
    bq := round(least(bq, free), 4);
    if bq < 0.0001 then
      update public.receipt_lots set status = 'no_stock', applied_at = now() where id = r.id;
      nostock := nostock + 1; continue;
    end if;
    insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by, batch_no)
      values (r.item_id, r.location_id, pb.bill_date::timestamp at time zone 'Asia/Dhaka', bq, bq,
              case when r.expiry_date is null then null else (r.expiry_date::timestamp + interval '23 hours 59 minutes') at time zone 'Asia/Dhaka' end,
              jsonb_build_object('source', 'receipt_lot', 'bill_id', p_bill, 'supplier_id', pb.supplier_id), left('Receipt lot ' || coalesce(r.lot_no, ''), 200), auth.uid(), r.lot_no)
      returning id into bid;
    update public.receipt_lots set status = 'applied', batch_id = bid, qty_base = bq, applied_at = now() where id = r.id;
    if r.lot_no is not null and r.expiry_date is not null then       -- the same link the paper-GRN batch uses, so a quality hold on this receipt reaches the batch
      insert into public.grn_batch_links (batch_id, source_type, source_id, item_id, location_id, batch_no, expiry_date, qty_base, created_by)
        values (bid, 'purchase', p_bill, r.item_id, r.location_id, r.lot_no, r.expiry_date, bq, auth.uid()) on conflict do nothing;
    end if;
    applied := applied + 1; ids := ids || bid;
  end loop;
  return jsonb_build_object('applied', applied, 'no_stock', nostock, 'batches', to_jsonb(ids));
end $$;

-- the public call (the screen calls it right after posting; idempotent, a second call applies nothing)
create or replace function public.receipt_lots_apply(p_bill uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pb public.purchase_bills;
begin
  select * into pb from public.purchase_bills where id = p_bill;
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(pb.location_id) then raise exception 'not allowed for this location'; end if;
  if not (public.is_owner() or public.has_grant('purchase_entry', pb.location_id) or public.has_grant('grn_batch', pb.location_id)) then raise exception 'not allowed'; end if;
  if pb.status <> 'posted' then raise exception 'not_posted'; end if;
  return public._rb3_lot_apply(p_bill);
end $$;

-- ---------- unbatched stock: on hand minus what sits in open batches (quantities only, never a cost) ----------
create or replace function public.stock_unbatched(p_loc int default null, p_item uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', x.item_id, 'code', x.code, 'name_bn', x.name_bn, 'name_en', x.name_en, 'location_id', x.location_id, 'base_unit', x.base_unit,
      'on_hand', x.qty, 'in_batches', x.inb, 'unbatched', case when x.qty - x.inb > 0.0005 then round(x.qty - x.inb, 4) else 0 end, 'negative', x.qty < 0) order by x.code, x.location_id), '[]'::jsonb) into out_
    from (select b.item_id, i.code, i.name_bn, i.name_en, b.location_id, public._item_base(b.item_id) as base_unit, b.qty,
                 coalesce((select sum(sb.qty_remaining) from public.stock_batches sb where sb.item_id = b.item_id and sb.location_id = b.location_id and sb.qty_remaining > 0), 0) as inb
            from public.stock_balance b join public.items i on i.id = b.item_id
           where i.tracked and public.can_loc(b.location_id) and (p_loc is null or b.location_id = p_loc) and (p_item is null or b.item_id = p_item) and b.qty <> 0) x;
  return out_;
end $$;

-- ---------- privileges ----------
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace
           and p.proname in ('_rb3_patch', '_rb3_view_ok', '_rb3_stock_lines', '_rb3_lot_gate', '_rb3_lot_apply') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace
           and p.proname in ('receipt_lots_stage', 'receipt_lots_get', 'receipt_lot_check', 'receipt_lots_apply', 'stock_unbatched') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';

-- ===================== phase431.sql =====================
-- Phase 431 (bos431) - RPT-B3 / R5b: TRACEABILITY AND RECALL (audit items #83 and #85).
-- Paste after phase430. Paste-twice safe. Earlier phase files are not edited; no shared function is re-created.
--
-- WHAT THIS ADDS
--   1. trace_batch(batch, dir)        raw material lot -> finished batch -> transfers -> outlets / customers (sales), and back from a finished batch to the raw lots it was made from.
--                                     Built only from records that already exist (stock_ledger batch_id, production_runs, stock_transfers, sales, receipt_lots, grn_batch_links).
--   2. trace_batch_find(...)          find a batch by lot number, item, place.
--   3. recall_cases, recall_batches   a recall case (digital entry, paper form code: to be given by owner) with the batches under recall and what was done with each.
--      recall_open / recall_add_batch / recall_batch_mark / recall_close / recall_list
--   4. recall_affected(case)          the affected-stock report: every batch reached from the recalled ones, what is still in stock where, what was sold at which outlet, to which
--                                     named customers, what is in transit, and the UNBATCHED quantity of the same items (stock that cannot be shown to be free of the lot), and
--                                     receipts of the same item and supplier that have no lot recorded.
-- Nothing here moves stock or money. Holding, removing or writing off recalled stock is done with the existing wastage / return screens; the case only records what was done.
-- Reading: the owner or a holder of the stock or quality report right (rpt_access). Writing a case: the owner or the new grant recall_manage. A person sees only the places they may see
-- (management and the owner see all); anything hidden is counted in the answer (hidden_places), never silently dropped. Customer mobile numbers are never returned.
-- Missing data is said, never shown as 0: a batch with no recorded origin says "origin not captured"; unlotted receipts and unbatched quantities are listed as such.

do $g$ begin
  if to_regprocedure('public._rb3_view_ok(int)') is null then raise exception 'phase431 needs phase430 first'; end if;
end $g$;

-- ---------- grant ----------
with ins as (
  insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
   ('recall_manage', 'stock', 49, 'রিকল কেস খোলা ও চালানো', 'Recall case খোলা ও চালানো', 'Open and run a recall case', 'once', null)
  on conflict (grant_code) do nothing returning grant_code)
insert into public.rule_grants (grant_code, role_code)
  select s.g, s.r from (values ('recall_manage', 'management'), ('recall_manage', 'factory_incharge'), ('recall_manage', 'storekeeper')) s(g, r)
  join ins on ins.grant_code = s.g
  where exists (select 1 from public.roles ro where ro.code = s.r)
  on conflict do nothing;

-- ---------- tables ----------
create sequence if not exists public.recall_case_no_seq;
create table if not exists public.recall_cases (
  id uuid primary key default gen_random_uuid(),
  case_no bigint not null default nextval('public.recall_case_no_seq') unique,
  client_id uuid unique,
  title text not null check (length(btrim(title)) between 3 and 120),
  reason text not null check (length(btrim(reason)) between 3 and 500),
  hazard text check (hazard is null or length(hazard) <= 300),
  status text not null default 'open' check (status in ('open', 'closed')),
  opened_by uuid, opened_staff text, opened_at timestamptz not null default now(),
  closed_by uuid, closed_staff text, closed_at timestamptz, close_note text check (close_note is null or length(close_note) <= 500)
);
create table if not exists public.recall_batches (
  id bigserial primary key,
  case_id uuid not null references public.recall_cases(id),
  batch_id bigint not null,                                    -- (no FK on purpose, like grn_batch_links: a truncate of the stock tables must still hit the ledger trigger first)
  added_by uuid, added_at timestamptz not null default now(), note text check (note is null or length(note) <= 300),
  action_status text not null default 'to_do' check (action_status in ('to_do', 'removed_from_shelf', 'returned_to_supplier', 'written_off', 'not_found', 'nothing_left')),
  action_by uuid, action_at timestamptz, action_note text check (action_note is null or length(action_note) <= 300),
  unique (case_id, batch_id)
);
create index if not exists recall_batches_batch on public.recall_batches (batch_id);
drop trigger if exists audit_recall_cases on public.recall_cases;
create trigger audit_recall_cases after insert or update on public.recall_cases for each row execute function public.log_change('id');
drop trigger if exists audit_recall_batches on public.recall_batches;
create trigger audit_recall_batches after insert or update on public.recall_batches for each row execute function public.log_change('id');
alter table public.recall_cases enable row level security;
alter table public.recall_batches enable row level security;
-- no direct browser access: the tables are read only through the functions below (they check rpt_access / recall_manage themselves)
revoke all on public.recall_cases, public.recall_batches from public, anon, authenticated;
revoke all on sequence public.recall_case_no_seq, public.recall_batches_id_seq from public, anon, authenticated;

-- ---------- access ----------
create or replace function public._rb3_trace_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.rpt_access('stock') or public.rpt_access('quality') or public.has_grant('recall_manage'));
$$;
create or replace function public._rb3_loc_vis(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public._all_locs() or public.can_loc(p_loc);
$$;

-- ---------- where a batch came from ----------
create or replace function public._rb3_origin(p_batch bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare b public.stock_batches; r record; run record; g record; tin record; tout record;
begin
  select * into b from public.stock_batches where id = p_batch;
  if not found then return null; end if;
  select rl.lot_no, rl.expiry_date, rl.bill_id, pb.bill_no, pb.bill_date, pb.supplier_id, s.name as supplier into r
    from public.receipt_lots rl join public.purchase_bills pb on pb.id = rl.bill_id join public.suppliers s on s.id = pb.supplier_id where rl.batch_id = p_batch limit 1;
  if found then
    return jsonb_build_object('type', 'receipt', 'supplier_id', r.supplier_id, 'supplier', r.supplier, 'bill_id', r.bill_id, 'bill_no', r.bill_no, 'bill_date', r.bill_date, 'lot_no', r.lot_no, 'expiry', r.expiry_date);
  end if;
  select l.source_type, l.source_id, l.batch_no, l.expiry_date into g from public.grn_batch_links l where l.batch_id = p_batch;
  if found then
    if g.source_type = 'purchase' then
      select pb.bill_no, pb.bill_date, pb.supplier_id, s.name as supplier into r from public.purchase_bills pb join public.suppliers s on s.id = pb.supplier_id where pb.id = g.source_id;
      return jsonb_build_object('type', 'receipt', 'supplier_id', r.supplier_id, 'supplier', r.supplier, 'bill_id', g.source_id, 'bill_no', r.bill_no, 'bill_date', r.bill_date, 'lot_no', g.batch_no, 'expiry', g.expiry_date);
    end if;
    return jsonb_build_object('type', 'grn_form', 'entry_id', g.source_id, 'lot_no', g.batch_no, 'expiry', g.expiry_date,
      'supplier', (select btrim(coalesce(s.name, e.data ->> 'supplier')) from public.entries e left join public.suppliers s on s.id::text = e.data ->> 'supplier_id' where e.id = g.source_id));
  end if;
  select pr.id, pr.made_at, pr.item_id into run from public.production_runs pr where pr.batch_id = p_batch;
  if found then return jsonb_build_object('type', 'production', 'run_id', run.id, 'made_at', run.made_at); end if;
  select l.ref_id into tin from public.stock_ledger l where l.batch_id = p_batch and l.reason = 'transfer_in' and l.ref_type = 'transfer' order by l.id limit 1;
  if found then
    select l.batch_id, l.location_id into tout from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = tin.ref_id and l.reason = 'transfer_out' and l.batch_id is not null order by l.id limit 1;
    return jsonb_build_object('type', 'transfer', 'transfer_id', tin.ref_id, 'source_batch_id', tout.batch_id, 'from_location_id', tout.location_id);
  end if;
  return jsonb_build_object('type', 'unknown', 'lot_no', b.batch_no);
end $$;

-- follow transfers back to the batch that really was made or received (max 10 hops)
create or replace function public._rb3_root(p_batch bigint) returns bigint
language plpgsql stable security definer set search_path = public as $$
declare cur bigint := p_batch; o jsonb; n int := 0;
begin
  loop
    o := public._rb3_origin(cur);
    exit when o is null or o ->> 'type' <> 'transfer' or (o ->> 'source_batch_id') is null or n >= 10;
    cur := (o ->> 'source_batch_id')::bigint; n := n + 1;
  end loop;
  return cur;
end $$;

-- a one-line description of a batch
create or replace function public._rb3_batch_row(p_batch bigint) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('batch_id', b.id, 'item_id', b.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'location_id', b.location_id, 'location', l.name_bn, 'location_en', l.name_en,
    'made_at', b.made_at, 'expires_at', b.expires_at, 'qty_made', b.qty_made, 'qty_remaining', b.qty_remaining, 'lot_no', b.batch_no, 'base_unit', public._item_base(b.item_id), 'origin', public._rb3_origin(b.id))
    from public.stock_batches b join public.items i on i.id = b.item_id join public.locations l on l.id = b.location_id where b.id = p_batch;
$$;

-- ---------- forward trace of one or more start batches (the shared core of trace_batch and recall_affected) ----------
create or replace function public._rb3_forward(p_start bigint[]) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  queue bigint[] := p_start; seen bigint[] := '{}'; x bigint; xb public.stock_batches; s record; t record; w record; rel jsonb := '{}'::jsonb; reached jsonb := '[]'::jsonb;
  sales_ jsonb := '[]'::jsonb; tr jsonb := '[]'::jsonb; made jsonb := '[]'::jsonb; waste jsonb := '[]'::jsonb; manual jsonb := '[]'::jsonb; hidden int := 0; sales_total int := 0; sale_cap constant int := 500;
  nb bigint; rid text; run_batch bigint; row_ jsonb; tt public.stock_transfers; sent numeric;
begin
  select coalesce(array_agg(distinct u), '{}') into queue from unnest(p_start) u;
  for x in select unnest(queue) loop rel := rel || jsonb_build_object(x::text, 'start'); end loop;
  while coalesce(array_length(queue, 1), 0) > 0 and coalesce(array_length(seen, 1), 0) < 300 loop
    x := queue[1]; queue := queue[2:array_length(queue, 1)];
    if x = any (seen) then continue; end if;
    seen := seen || x;
    select * into xb from public.stock_batches where id = x;
    if not found then continue; end if;
    if not public._rb3_loc_vis(xb.location_id) then hidden := hidden + 1; continue; end if;
    row_ := public._rb3_batch_row(x) || jsonb_build_object('relation', coalesce(rel ->> x::text, 'reached'));
    reached := reached || row_;
    -- sales (net of voids and returns)
    for s in
      select q.sref, sum(q.q) as net, sum(q.q) filter (where q.kind = 'out') as gross
        from (select sl.ref_id as sref, -sl.qty_delta as q, 'out' as kind from public.stock_ledger sl where sl.batch_id = x and sl.reason = 'sale_out' and sl.ref_type = 'sale'
              union all select sl.ref_id, sl.qty_delta * -1, 'void' from public.stock_ledger sl where sl.batch_id = x and sl.reason = 'sale_void_in' and sl.ref_type = 'sale'
              union all select sr.sale_id::text, sl.qty_delta * -1, 'ret' from public.stock_ledger sl join public.sale_returns sr on sr.id::text = sl.ref_id
                         where sl.batch_id = x and sl.ref_type = 'sale_return' and sl.reason in ('sale_return', 'reversal')) q
       group by q.sref loop
      if s.net is null or s.net < 0.0005 then continue; end if;
      select sa.id, sa.receipt, sa.sale_date, sa.location_id, sa.customer, sa.customer_id, sa.status, l.name_bn as place into t
        from public.sales sa join public.locations l on l.id = sa.location_id where sa.id::text = s.sref;
      if not found then continue; end if;
      if not public._rb3_loc_vis(t.location_id) then hidden := hidden + 1; continue; end if;
      sales_total := sales_total + 1;
      if jsonb_array_length(sales_) < sale_cap then
        sales_ := sales_ || jsonb_build_object('sale_id', t.id, 'receipt', t.receipt, 'sale_date', t.sale_date, 'location_id', t.location_id, 'location', t.place, 'customer', nullif(btrim(t.customer), ''),
          'customer_id', t.customer_id, 'qty', round(s.net, 4), 'batch_id', x, 'item_id', xb.item_id, 'code', row_ ->> 'code');
      end if;
    end loop;
    -- used in production: the run's finished batch is reached
    for s in select l.ref_id as run_id, sum(-l.qty_delta) as qty from public.stock_ledger l where l.batch_id = x and l.reason = 'issue_out' and l.ref_type = 'production' group by l.ref_id loop
      select pr.batch_id into run_batch from public.production_runs pr where pr.id::text = s.run_id and pr.status = 'done';
      made := made || jsonb_build_object('run_id', s.run_id, 'from_batch_id', x, 'qty', round(s.qty, 4), 'to_batch_id', run_batch);
      if run_batch is not null and not (run_batch = any (seen)) and not (run_batch = any (queue)) then
        queue := queue || run_batch; rel := rel || jsonb_build_object(run_batch::text, 'made_from');
      end if;
    end loop;
    -- issued by hand (no production run): the destination is not recorded
    select coalesce(sum(-l.qty_delta), 0) into sent from public.stock_ledger l where l.batch_id = x and l.reason = 'issue_out' and coalesce(l.ref_type, '') <> 'production';
    if sent > 0 then manual := manual || jsonb_build_object('batch_id', x, 'qty', round(sent, 4)); end if;
    -- transfers
    for s in select l.ref_id as tid, sum(case when l.reason = 'transfer_out' then -l.qty_delta else l.qty_delta end) as qty from public.stock_ledger l
              where l.batch_id = x and l.ref_type = 'transfer' and l.reason in ('transfer_out', 'reversal') group by l.ref_id loop
      if s.qty < 0.0005 then continue; end if;
      select * into tt from public.stock_transfers where id::text = s.tid;
      tr := tr || jsonb_build_object('transfer_id', s.tid, 'from_batch_id', x, 'qty_sent', round(s.qty, 4), 'from_location_id', xb.location_id, 'to_location_id', tt.to_location_id,
        'status', tt.status, 'received_qty', tt.received_qty, 'sent_at', tt.sent_at, 'received_at', tt.received_at);
      for w in select l.batch_id as nb2 from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = s.tid and l.reason = 'transfer_in' and l.batch_id is not null loop
        nb := w.nb2;
        if not (nb = any (seen)) and not (nb = any (queue)) then queue := queue || nb; rel := rel || jsonb_build_object(nb::text, 'transferred'); end if;
      end loop;
    end loop;
    -- written off / taken out in other ways
    for w in select l.reason, sum(-l.qty_delta) as qty from public.stock_ledger l where l.batch_id = x and l.reason in ('wastage', 'purchase_return', 'count_adjust') and l.qty_delta < 0 group by l.reason loop
      waste := waste || jsonb_build_object('batch_id', x, 'reason', w.reason, 'qty', round(w.qty, 4));
    end loop;
  end loop;
  return jsonb_build_object('batches', reached, 'sales', sales_, 'sales_total', sales_total, 'sales_truncated', sales_total > sale_cap, 'made_into', made, 'transfers', tr,
    'taken_out', waste, 'issued_without_run', manual, 'hidden_places', hidden, 'batches_truncated', coalesce(array_length(queue, 1), 0) > 0);
end $$;

-- ---------- summaries shared by trace and recall: by place, unbatched quantity ----------
create or replace function public._rb3_summary(p_fwd jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare by_loc jsonb; unb jsonb := '[]'::jsonb; u jsonb; it record; named int; walk int;
begin
  select coalesce(jsonb_agg(jsonb_build_object('location_id', z.loc, 'location', l.name_bn, 'location_en', l.name_en, 'on_hand', z.on_hand, 'sold', z.sold, 'sales_n', z.sales_n,
      'in_transit', z.transit) order by l.name_bn), '[]'::jsonb) into by_loc
    from (select loc, sum(on_hand) as on_hand, sum(sold) as sold, sum(sales_n) as sales_n, sum(transit) as transit from (
            select (b ->> 'location_id')::int as loc, (b ->> 'qty_remaining')::numeric as on_hand, 0::numeric as sold, 0 as sales_n, 0::numeric as transit from jsonb_array_elements(p_fwd -> 'batches') b
            union all select (s ->> 'location_id')::int, 0, (s ->> 'qty')::numeric, 1, 0 from jsonb_array_elements(p_fwd -> 'sales') s
            union all select (t ->> 'to_location_id')::int, 0, 0, 0, (t ->> 'qty_sent')::numeric from jsonb_array_elements(p_fwd -> 'transfers') t where t ->> 'status' = 'sent') u2
          where loc is not null group by loc) z join public.locations l on l.id = z.loc;
  for it in select distinct (b ->> 'item_id')::uuid as item_id, (b ->> 'location_id')::int as loc from jsonb_array_elements(p_fwd -> 'batches') b loop
    for u in select * from jsonb_array_elements(public.stock_unbatched(it.loc, it.item_id)) loop
      if (u ->> 'unbatched')::numeric > 0 or (u ->> 'negative')::boolean then unb := unb || u; end if;
    end loop;
  end loop;
  select count(distinct s ->> 'customer'), count(*) filter (where s ->> 'customer' is null) into named, walk from jsonb_array_elements(p_fwd -> 'sales') s;
  return jsonb_build_object('by_place', by_loc, 'unbatched', unb, 'named_customers', named, 'sales_without_customer', walk);
end $$;

-- ---------- the trace of one batch ----------
-- dir: 'fwd' (where it went), 'back' (what it was made from), 'both'
create or replace function public.trace_batch(p_batch bigint, p_dir text default 'both') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare b public.stock_batches; dir text := coalesce(p_dir, 'both'); fwd jsonb; back jsonb := null; run record; inputs jsonb := '[]'::jsonb; unb jsonb := '[]'::jsonb; ib record;
        root bigint; warn jsonb := '[]'::jsonb;
begin
  if not public._rb3_trace_ok() then raise exception 'not allowed'; end if;
  if dir not in ('fwd', 'back', 'both') then raise exception 'bad_dir'; end if;
  select * into b from public.stock_batches where id = p_batch;
  if not found then raise exception 'batch_not_found'; end if;
  if not public._rb3_loc_vis(b.location_id) then raise exception 'not allowed for this location'; end if;
  if dir in ('back', 'both') then
    root := public._rb3_root(p_batch);
    select pr.id, pr.made_at, pr.item_id into run from public.production_runs pr where pr.batch_id = root;
    if found then
      for ib in select l.batch_id, l.item_id, sum(-l.qty_delta) as qty from public.stock_ledger l where l.ref_type = 'production' and l.ref_id = run.id::text and l.reason = 'issue_out' group by l.batch_id, l.item_id loop
        if ib.batch_id is null then
          unb := unb || jsonb_build_object('item_id', ib.item_id, 'code', (select code from public.items where id = ib.item_id), 'name_bn', (select name_bn from public.items where id = ib.item_id),
            'qty', round(ib.qty, 4), 'note', 'unbatched');
        else
          inputs := inputs || (public._rb3_batch_row(ib.batch_id) || jsonb_build_object('qty_used', round(ib.qty, 4), 'root_origin', public._rb3_origin(public._rb3_root(ib.batch_id))));
        end if;
      end loop;
    end if;
    back := jsonb_build_object('root_batch_id', root, 'run_id', run.id, 'inputs', inputs, 'unbatched_inputs', unb);
  end if;
  if dir in ('fwd', 'both') then
    fwd := public._rb3_forward(array[p_batch]);
    fwd := fwd || jsonb_build_object('summary', public._rb3_summary(fwd));
  end if;
  if (public._rb3_origin(p_batch) ->> 'type') = 'unknown' then warn := warn || '"origin_not_captured"'::jsonb; end if;
  return jsonb_build_object('batch', public._rb3_batch_row(p_batch), 'back', back, 'forward', fwd, 'warnings', warn);
end $$;

-- find a batch: by lot number text, item, place; only batches with stock left unless p_all
create or replace function public.trace_batch_find(p_q text default null, p_item uuid default null, p_loc int default null, p_all boolean default false, p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare q text := nullif(btrim(p_q), ''); lim int := least(greatest(coalesce(p_limit, 100), 1), 300);
begin
  if not public._rb3_trace_ok() then raise exception 'not allowed'; end if;
  if q is not null and length(q) > 60 then raise exception 'bad_query'; end if;
  return coalesce((select jsonb_agg(public._rb3_batch_row(x.id) order by x.made_at desc, x.id desc) from (
      select b.id, b.made_at from public.stock_batches b join public.items i on i.id = b.item_id
       where public._rb3_loc_vis(b.location_id) and (p_loc is null or b.location_id = p_loc) and (p_item is null or b.item_id = p_item)
         and (coalesce(p_all, false) or b.qty_remaining > 0)
         and (q is null or b.batch_no ilike '%' || replace(replace(q, '%', ''), '_', '') || '%' or i.code ilike '%' || replace(replace(q, '%', ''), '_', '') || '%'
              or i.name_bn ilike '%' || replace(replace(q, '%', ''), '_', '') || '%' or coalesce(i.name_en, '') ilike '%' || replace(replace(q, '%', ''), '_', '') || '%' or b.id::text = q)
       order by b.made_at desc, b.id desc limit lim) x), '[]'::jsonb);
end $$;

-- ---------- recall cases ----------
create or replace function public._rb3_recall_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('recall_manage'));
$$;

create or replace function public.recall_open(p_title text, p_reason text, p_hazard text default null, p_batches bigint[] default '{}', p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare cid uuid; prev public.recall_cases; sid text; bid bigint; loc int; n int := 0; tt text := btrim(coalesce(p_title, '')); rr text := btrim(coalesce(p_reason, ''));
begin
  if not public._rb3_recall_ok() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into prev from public.recall_cases where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', prev.id, 'case_no', prev.case_no); end if;
  end if;
  if length(tt) < 3 or length(tt) > 120 then raise exception 'bad_title'; end if;
  if length(rr) < 3 or length(rr) > 500 then raise exception 'reason_required'; end if;
  if length(coalesce(p_hazard, '')) > 300 then raise exception 'bad_hazard'; end if;
  if coalesce(array_length(p_batches, 1), 0) > 100 then raise exception 'too_many_batches'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.recall_cases (client_id, title, reason, hazard, opened_by, opened_staff) values (p_client, tt, rr, nullif(btrim(p_hazard), ''), auth.uid(), sid) returning id into cid;
  foreach bid in array coalesce(p_batches, '{}') loop
    select location_id into loc from public.stock_batches where id = bid;
    if loc is null then raise exception 'batch_not_found'; end if;
    insert into public.recall_batches (case_id, batch_id, added_by) values (cid, bid, auth.uid()) on conflict do nothing;
    n := n + 1;
  end loop;
  select b.location_id into loc from public.recall_batches rb join public.stock_batches b on b.id = rb.batch_id where rb.case_id = cid order by rb.id limit 1;
  if loc is not null then
    perform public._stock_exc(loc, 'recall_opened', 'red', 'রিকল কেস খোলা হয়েছে: ' || left(tt, 80), 'A recall case was opened: ' || left(tt, 80));
  end if;
  return jsonb_build_object('id', cid, 'case_no', (select case_no from public.recall_cases where id = cid), 'batches', n);
end $$;

create or replace function public.recall_add_batch(p_case uuid, p_batch bigint, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.recall_cases;
begin
  if not public._rb3_recall_ok() then raise exception 'not allowed'; end if;
  select * into c from public.recall_cases where id = p_case for update;
  if not found then raise exception 'not found'; end if;
  if c.status <> 'open' then raise exception 'case_closed'; end if;
  if not exists (select 1 from public.stock_batches where id = p_batch) then raise exception 'batch_not_found'; end if;
  if length(coalesce(p_note, '')) > 300 then raise exception 'bad_note'; end if;
  insert into public.recall_batches (case_id, batch_id, added_by, note) values (p_case, p_batch, auth.uid(), nullif(btrim(p_note), '')) on conflict do nothing;
  return jsonb_build_object('case_id', p_case, 'batch_id', p_batch);
end $$;

-- what was done with a batch under recall (the history is in the audit log; a closed case cannot change)
create or replace function public.recall_batch_mark(p_case uuid, p_batch bigint, p_status text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.recall_cases; n text := nullif(btrim(p_note), '');
begin
  if not public._rb3_recall_ok() then raise exception 'not allowed'; end if;
  select * into c from public.recall_cases where id = p_case for update;
  if not found then raise exception 'not found'; end if;
  if c.status <> 'open' then raise exception 'case_closed'; end if;
  if p_status is null or p_status not in ('to_do', 'removed_from_shelf', 'returned_to_supplier', 'written_off', 'not_found', 'nothing_left') then raise exception 'bad_status'; end if;
  if p_status in ('written_off', 'not_found') and (n is null or length(n) < 3) then raise exception 'note_required'; end if;
  if n is not null and length(n) > 300 then raise exception 'bad_note'; end if;
  update public.recall_batches set action_status = p_status, action_by = auth.uid(), action_at = now(), action_note = n where case_id = p_case and batch_id = p_batch;
  if not found then raise exception 'batch_not_in_case'; end if;
  return jsonb_build_object('case_id', p_case, 'batch_id', p_batch, 'status', p_status);
end $$;

create or replace function public.recall_close(p_case uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.recall_cases; n text := btrim(coalesce(p_note, '')); sid text; open_n int; loc int;
begin
  if not public._rb3_recall_ok() then raise exception 'not allowed'; end if;
  select * into c from public.recall_cases where id = p_case for update;
  if not found then raise exception 'not found'; end if;
  if c.status = 'closed' then return jsonb_build_object('dup', true, 'status', 'closed'); end if;
  if length(n) < 3 or length(n) > 500 then raise exception 'note_required'; end if;
  select count(*) into open_n from public.recall_batches where case_id = p_case and action_status = 'to_do';
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.recall_cases set status = 'closed', closed_by = auth.uid(), closed_staff = sid, closed_at = now(), close_note = n where id = p_case;
  if open_n > 0 then
    select b.location_id into loc from public.recall_batches rb join public.stock_batches b on b.id = rb.batch_id where rb.case_id = p_case order by rb.id limit 1;
    perform public._stock_exc(loc, 'recall_closed_open', 'yellow', 'রিকল কেস বন্ধ, কিন্তু ' || open_n::text || ' ব্যাচের কাজ বাকি', 'A recall case was closed with ' || open_n::text || ' batch(es) still to do');
  end if;
  return jsonb_build_object('status', 'closed', 'still_to_do', open_n);
end $$;

create or replace function public.recall_list(p_status text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._rb3_trace_ok() then raise exception 'not allowed'; end if;
  if p_status is not null and p_status not in ('open', 'closed') then raise exception 'bad_status'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'case_no', c.case_no, 'title', c.title, 'reason', c.reason, 'hazard', c.hazard, 'status', c.status, 'opened_at', c.opened_at,
      'opened_staff', c.opened_staff, 'closed_at', c.closed_at, 'close_note', c.close_note,
      'batches_n', (select count(*) from public.recall_batches rb where rb.case_id = c.id),
      'to_do_n', (select count(*) from public.recall_batches rb where rb.case_id = c.id and rb.action_status = 'to_do')) order by c.case_no desc)
    from public.recall_cases c where p_status is null or c.status = p_status), '[]'::jsonb);
end $$;

-- ---------- the affected-stock report of a case ----------
create or replace function public.recall_affected(p_case uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c public.recall_cases; starts bigint[]; fwd jsonb; summ jsonb; entered jsonb; unlot jsonb := '[]'::jsonb; r record; o jsonb;
begin
  if not public._rb3_trace_ok() then raise exception 'not allowed'; end if;
  select * into c from public.recall_cases where id = p_case;
  if not found then raise exception 'not found'; end if;
  select coalesce(array_agg(rb.batch_id order by rb.id), '{}') into starts from public.recall_batches rb where rb.case_id = p_case;
  select coalesce(jsonb_agg(public._rb3_batch_row(rb.batch_id) || jsonb_build_object('action_status', rb.action_status, 'action_note', rb.action_note, 'action_at', rb.action_at, 'note', rb.note) order by rb.id), '[]'::jsonb)
    into entered from public.recall_batches rb where rb.case_id = p_case;
  fwd := public._rb3_forward(starts);
  summ := public._rb3_summary(fwd);
  -- receipts of the same item from the same supplier that carry no lot: the recalled lot cannot be ruled out for them
  for r in select distinct (public._rb3_origin(public._rb3_root(u.bid)) ->> 'supplier_id')::uuid as sup, b.item_id from unnest(starts) as u(bid) join public.stock_batches b on b.id = u.bid loop
    if r.sup is null then continue; end if;
    unlot := unlot || coalesce((select jsonb_agg(jsonb_build_object('bill_id', pb.id, 'bill_no', pb.bill_no, 'bill_date', pb.bill_date, 'supplier_id', pb.supplier_id, 'supplier', sp.name, 'item_id', l.item_id,
          'code', i.code, 'qty', coalesce(l.base_qty, l.qty), 'location_id', pb.location_id) order by pb.bill_date desc)
        from public.purchase_bills pb join public.purchase_lines l on l.bill_id = pb.id join public.items i on i.id = l.item_id join public.suppliers sp on sp.id = pb.supplier_id
       where pb.status = 'posted' and pb.kind = 'bill' and pb.supplier_id = r.sup and l.item_id = r.item_id and public._rb3_loc_vis(pb.location_id)
         and not exists (select 1 from public.receipt_lots rl where rl.bill_id = pb.id and rl.line_no = l.line_no and rl.status = 'applied')
         and not exists (select 1 from public.grn_batch_links g where g.source_type = 'purchase' and g.source_id = pb.id and g.item_id = l.item_id)), '[]'::jsonb);
  end loop;
  return jsonb_build_object('case', to_jsonb(c) - 'client_id', 'entered', entered, 'forward', fwd, 'summary', summ, 'unlotted_receipts', unlot,
    'data_notes', to_jsonb(array_remove(array[case when jsonb_array_length(summ -> 'unbatched') > 0 then 'unbatched_stock_present' end,
                                                case when jsonb_array_length(unlot) > 0 then 'receipts_without_lot' end], null)));
end $$;

-- ---------- privileges ----------
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace
           and p.proname in ('_rb3_trace_ok', '_rb3_loc_vis', '_rb3_origin', '_rb3_root', '_rb3_batch_row', '_rb3_forward', '_rb3_summary', '_rb3_recall_ok') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace
           and p.proname in ('trace_batch', 'trace_batch_find', 'recall_open', 'recall_add_batch', 'recall_batch_mark', 'recall_close', 'recall_list', 'recall_affected') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';

-- ===================== phase432.sql =====================
-- Phase 432 (bos432) - RPT-B3 / R6a: QUALITY CHECK WITH ITEM, QUANTITY AND SUPPLIER (#89) and DAMAGED QUANTITY ON TRANSFER RECEIVE (#65).
-- Paste after phase431 (needs phase60 qc_records and phase10 stock_transfers). Paste-twice safe. Earlier phase files are not edited. No shared function is changed in behaviour:
--   * qc_record keeps its 7-argument signature (now a thin wrapper that passes nulls); the new 11-argument function carries the same rules plus the new fields.
--   * stock_receive_transfer keeps its 3-argument function untouched; the new 5-argument function validates the damage fields, calls the 3-argument one (every rule of today) and then records them.
--   * qc_list is re-created with two more optional filters and more columns (an old call with 4 arguments still works).
--
-- WHAT THIS ADDS
--   1. qc_records gains item_id, qty (base unit; the quantity this check is about: rejected / held for hold and reject, checked for pass) and supplier_id. All optional. Old rows keep null
--      and the screens say "not captured"; nothing is guessed back. The supplier and item are read from the source (purchase bill, paper GRN 04-1, production run) when not typed.
--   2. qc_list(loc, from, to, status, item, supplier): the latest check per source with the new columns and filters.
--   3. stock_transfers gains received_damaged_qty and damaged_reason (list transfer_damage_reasons: editable, Add new and Other like every list). Blank = not captured, never 0.
--      stock_receive_transfer(id, received, note, damaged, reason), transfer_damage_report(from, to, loc).
-- The damaged quantity is a RECORD. The goods stay in the receiving stock until they are written off with the wastage screen (reason Broken); nothing is written to stock or money here.
-- Paper form code of these two captures: to be given by owner (digital entry screens only for now).

do $g$ begin
  if to_regclass('public.qc_records') is null or to_regclass('public.stock_transfers') is null then raise exception 'phase432 needs phase10 and phase60 first'; end if;
  if to_regprocedure('public._rb3_view_ok(int)') is null then raise exception 'phase432 needs phase430 first'; end if;
end $g$;

-- ---------- columns ----------
alter table public.qc_records add column if not exists item_id uuid references public.items(id);
alter table public.qc_records add column if not exists qty numeric;
alter table public.qc_records add column if not exists supplier_id uuid references public.suppliers(id);
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'qc_records_qty_range' and conrelid = 'public.qc_records'::regclass) then
    alter table public.qc_records add constraint qc_records_qty_range check (qty is null or (qty > 0 and qty <= 1000000000000));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'qc_records_qty_needs_item' and conrelid = 'public.qc_records'::regclass) then
    alter table public.qc_records add constraint qc_records_qty_needs_item check (qty is null or item_id is not null);
  end if;
end $$;
create index if not exists qc_records_supplier on public.qc_records (supplier_id, created_at) where supplier_id is not null;
create index if not exists qc_records_item on public.qc_records (item_id, created_at) where item_id is not null;

alter table public.stock_transfers add column if not exists received_damaged_qty numeric;
alter table public.stock_transfers add column if not exists damaged_reason text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'stock_transfers_damaged_range' and conrelid = 'public.stock_transfers'::regclass) then
    alter table public.stock_transfers add constraint stock_transfers_damaged_range check (received_damaged_qty is null or (received_damaged_qty between 0 and 1000000000000));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'stock_transfers_damaged_le_received' and conrelid = 'public.stock_transfers'::regclass) then
    alter table public.stock_transfers add constraint stock_transfers_damaged_le_received check (received_damaged_qty is null or received_qty is null or received_damaged_qty <= received_qty);
  end if;
end $$;

insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort) values
 ('transfer_damage_reasons', 'broken', 'ভেঙে গেছে', 'ভেঙে গেছে (broken)', 'Broken', 1),
 ('transfer_damage_reasons', 'leaked', 'চুইয়ে / ছিটকে গেছে', 'Leaked / spilled', 'Leaked / spilled', 2),
 ('transfer_damage_reasons', 'crushed', 'চাপা পড়ে নষ্ট', 'Crushed', 'Crushed', 3),
 ('transfer_damage_reasons', 'spoiled', 'পথে নষ্ট / পচে গেছে', 'পথে spoiled', 'Spoiled on the way', 4),
 ('transfer_damage_reasons', 'packaging', 'প্যাকেট ছেঁড়া / খোলা', 'Packaging torn / open', 'Packaging torn / open', 5),
 ('transfer_damage_reasons', 'other', 'অন্যান্য', 'Other', 'Other', 9)
on conflict (list_code, value_code) do nothing;

-- ---------- where a quality-check source sits and who supplied it ----------
create or replace function public._rb3_qc_source(p_type text, p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare loc int; sup uuid; itm uuid; it_codes text[];
begin
  if p_type = 'production' then
    select location_id, item_id into loc, itm from public.production_runs where id = p_id;
    return case when loc is null then null else jsonb_build_object('location_id', loc, 'supplier_id', null, 'item_id', itm, 'item_ids', jsonb_build_array(itm)) end;
  end if;
  select location_id, supplier_id into loc, sup from public.purchase_bills where id = p_id and kind = 'bill' and status = 'posted';
  if found then
    return jsonb_build_object('location_id', loc, 'supplier_id', sup, 'item_ids', coalesce((select jsonb_agg(distinct l.item_id) from public.purchase_lines l where l.bill_id = p_id and l.item_id is not null), '[]'::jsonb));
  end if;
  select e.location_id,
         case when (e.data ->> 'supplier_id') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then (e.data ->> 'supplier_id')::uuid end,
         coalesce((select array_agg(distinct x ->> 'item') from jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) x), '{}')
    into loc, sup, it_codes from public.entries e where e.id = p_id and e.form_code = '04-1';
  if loc is null then return null; end if;
  if sup is not null and not exists (select 1 from public.suppliers where id = sup) then sup := null; end if;
  return jsonb_build_object('location_id', loc, 'supplier_id', sup, 'item_ids', coalesce((select jsonb_agg(i.id) from public.items i where i.code = any (it_codes)), '[]'::jsonb));
end $$;

-- ---------- qc_record: the full function (same rules as phase60 plus item, quantity, supplier) ----------
create or replace function public.qc_record(p_source_type text, p_source_id uuid, p_status text, p_checks jsonb, p_note text, p_photo text, p_client uuid,
  p_item uuid, p_qty numeric, p_unit text, p_supplier uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare loc int; sid text; prev public.qc_records; rid uuid; c jsonb; codes text[] := '{}'; code text; bad int := 0; n text := nullif(btrim(p_note), '');
        src jsonb; sup uuid := p_supplier; bq numeric; itm uuid := p_item;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into prev from public.qc_records where client_id = p_client;
    if found then
      if prev.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', prev.id, 'status', prev.status);
    end if;
  end if;
  if p_source_type is null or p_source_type not in ('production', 'grn') then raise exception 'bad_source'; end if;
  if p_source_id is null then raise exception 'bad_source'; end if;
  if p_status is null or p_status not in ('pass', 'hold', 'reject') then raise exception 'bad_status'; end if;
  src := public._rb3_qc_source(p_source_type, p_source_id);
  if src is null then raise exception 'source_not_found'; end if;
  loc := (src ->> 'location_id')::int;
  if not public.can_loc(loc) then raise exception 'not allowed for this location'; end if;
  if not (public.is_owner() or public.has_grant('qc_record', loc)) then raise exception 'not allowed'; end if;
  if p_checks is null or jsonb_typeof(p_checks) <> 'array' or jsonb_array_length(p_checks) > 30 then raise exception 'bad_checks'; end if;
  for c in select * from jsonb_array_elements(p_checks) loop
    if jsonb_typeof(c) <> 'object' or jsonb_typeof(c->'ok') <> 'boolean' or jsonb_typeof(c->'code') <> 'string' then raise exception 'bad_checks'; end if;
    code := c->>'code';
    if code = any (codes) then raise exception 'bad_checks'; end if;
    if not exists (select 1 from public.option_lists where list_code = 'qc_checks' and value_code = code and active) then raise exception 'bad_check_code'; end if;
    codes := codes || code;
    if not (c->>'ok')::boolean then bad := bad + 1; end if;
  end loop;
  if p_status = 'pass' and bad > 0 then raise exception 'pass_has_failed_check'; end if;
  if p_status <> 'pass' and (n is null or length(n) < 3) then raise exception 'note_required'; end if;
  if n is not null and length(n) > 300 then raise exception 'bad_note'; end if;
  if length(coalesce(p_photo, '')) > 300 then raise exception 'bad_photo'; end if;
  -- the new optional fields
  if itm is null and p_source_type = 'production' then itm := (src ->> 'item_id')::uuid; end if;
  if itm is not null then
    if not exists (select 1 from public.items where id = itm) then raise exception 'item_not_found'; end if;
    if p_item is not null and not (src -> 'item_ids') ? itm::text then raise exception 'item_not_in_source'; end if;
  end if;
  if sup is not null and not exists (select 1 from public.suppliers where id = sup) then raise exception 'supplier_not_found'; end if;
  if (src ->> 'supplier_id') is not null then
    if sup is not null and sup <> (src ->> 'supplier_id')::uuid then raise exception 'supplier_mismatch'; end if;
    sup := (src ->> 'supplier_id')::uuid;
  end if;
  if p_qty is not null then
    if itm is null then raise exception 'item_required_for_qty'; end if;
    bq := public._base_qty(itm, p_qty, p_unit);
    if bq is null then raise exception 'unit_unknown'; end if;
    if not (bq between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  end if;
  select * into prev from public.qc_records where source_type = p_source_type and source_id = p_source_id order by created_at desc, id desc limit 1;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.qc_records (client_id, source_type, source_id, location_id, status, checks, note, photo, supersedes_id, created_by, created_staff, item_id, qty, supplier_id)
    values (p_client, p_source_type, p_source_id, loc, p_status, p_checks, n, nullif(btrim(p_photo), ''), prev.id, auth.uid(), sid, itm, bq, sup) returning id into rid;
  if p_status in ('hold', 'reject') then
    perform public._stock_exc(loc, 'qc_' || p_status, case when public.rule_on('quality_block_on') then 'red' else 'yellow' end,
      'কোয়ালিটি চেকে ' || case p_status when 'hold' then 'আটক' else 'বাতিল' end || ' (' || p_source_type || ')',
      'Quality check: ' || p_status || ' (' || p_source_type || ')', null, null, 'QC');
  end if;
  return jsonb_build_object('id', rid, 'status', p_status, 'failed', bad, 'blocked', public.rule_on('quality_block_on') and p_status in ('hold', 'reject'), 'item_id', itm, 'qty', bq, 'supplier_id', sup);
end $$;

-- the old 7-argument signature stays (screens, tests and the offline outbox call it): a thin wrapper, no default on the new arguments so no call is ambiguous
create or replace function public.qc_record(p_source_type text, p_source_id uuid, p_status text, p_checks jsonb default '[]'::jsonb,
  p_note text default null, p_photo text default null, p_client uuid default null) returns jsonb
language sql security definer set search_path = public as $$
  select public.qc_record(p_source_type, p_source_id, p_status, p_checks, p_note, p_photo, p_client, null::uuid, null::numeric, null::text, null::uuid);
$$;

-- ---------- qc_list with the new columns and filters ----------
drop function if exists public.qc_list(int, date, date, text);
create or replace function public.qc_list(p_loc int default null, p_from date default null, p_to date default null, p_status text default null, p_item uuid default null, p_supplier uuid default null)
returns table (id uuid, source_type text, source_id uuid, location_id int, status text, checks jsonb, note text, created_at timestamptz, created_staff text, history_n bigint,
               item_id uuid, item_code text, item_name_bn text, item_name_en text, base_unit text, qty numeric, supplier_id uuid, supplier_name text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_status is not null and p_status not in ('pass', 'hold', 'reject') then raise exception 'bad_status'; end if;
  if p_from is not null and p_to is not null and p_to < p_from then raise exception 'bad_range'; end if;
  return query
    select q.id, q.source_type, q.source_id, q.location_id, q.status, q.checks, q.note, q.created_at, q.created_staff,
           (select count(*) from public.qc_records h where h.source_type = q.source_type and h.source_id = q.source_id),
           q.item_id, i.code, i.name_bn, i.name_en, case when i.id is null then null else public._item_base(i.id) end, q.qty, q.supplier_id, s.name
    from public.qc_records q left join public.items i on i.id = q.item_id left join public.suppliers s on s.id = q.supplier_id
    where q.id = (select x.id from public.qc_records x where x.source_type = q.source_type and x.source_id = q.source_id order by x.created_at desc, x.id desc limit 1)
      and public.can_loc(q.location_id) and (p_loc is null or q.location_id = p_loc)
      and (p_status is null or q.status = p_status) and (p_item is null or q.item_id = p_item) and (p_supplier is null or q.supplier_id = p_supplier)
      and (p_from is null or (q.created_at at time zone 'Asia/Dhaka')::date >= p_from)
      and (p_to is null or (q.created_at at time zone 'Asia/Dhaka')::date <= p_to)
    order by q.created_at desc limit 200;
end $$;

-- ---------- damaged quantity on transfer receive ----------
create or replace function public.stock_receive_transfer(p_id uuid, p_received_qty numeric, p_note text, p_damaged_qty numeric, p_damaged_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.stock_transfers; rq numeric; res jsonb; dq numeric := p_damaged_qty; rs text := nullif(btrim(p_damaged_reason), ''); it public.items;
begin
  select * into t from public.stock_transfers where id = p_id;
  if not found then raise exception 'not found'; end if;
  rq := coalesce(p_received_qty, t.qty);
  if dq is not null then
    if not (dq between 0 and 999999999) then raise exception 'bad_qty'; end if;
    if dq > rq then raise exception 'damaged_over_received'; end if;
    if dq > 0 and (rs is null or not exists (select 1 from public.option_lists where list_code = 'transfer_damage_reasons' and value_code = rs and active)) then raise exception 'damage_reason_required'; end if;
    if dq = 0 then rs := null; end if;
  end if;
  res := public.stock_receive_transfer(p_id, p_received_qty, p_note);          -- the 3-argument function: every rule of today (grant, short quantity, batches, exception)
  if coalesce((res ->> 'dup')::boolean, false) then return res; end if;
  if dq is not null then
    update public.stock_transfers set received_damaged_qty = dq, damaged_reason = rs where id = p_id;
    if dq > 0 then
      select * into it from public.items where id = t.item_id;
      perform public._stock_exc(t.to_location_id, 'transit_damaged', 'yellow', it.name_bn || ': গ্রহণ ' || rq::text || ', তার মধ্যে ' || dq::text || ' ক্ষতিগ্রস্ত',
        coalesce(it.name_en, it.name_bn) || ': received ' || rq::text || ', of which ' || dq::text || ' damaged');
    end if;
  end if;
  return res || jsonb_build_object('damaged', dq);
end $$;

-- the damaged-on-receipt report (read only). Blank damaged = "not captured"; it is never added up as 0.
create or replace function public.transfer_damage_report(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 30); t date := coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date); rows_ jsonb; n int; cap int; ncap int; qd numeric; qs numeric;
begin
  if not (public.is_active() and (public.is_owner() or public.rpt_access('stock'))) then raise exception 'not allowed'; end if;
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('transfer_id', x.id, 'received_at', x.received_at, 'day', (x.received_at at time zone 'Asia/Dhaka')::date, 'from_location_id', x.from_location_id,
        'from_name', lf.name_bn, 'to_location_id', x.to_location_id, 'to_name', lt.name_bn, 'item_id', x.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(x.item_id),
        'qty_sent', x.qty, 'received_qty', x.received_qty, 'short', x.qty - x.received_qty, 'damaged', x.received_damaged_qty, 'reason', x.damaged_reason,
        'reason_label', (select coalesce(o.label_en, o.value_code) from public.option_lists o where o.list_code = 'transfer_damage_reasons' and o.value_code = x.damaged_reason),
        'reason_label_bn', (select o.label_bn from public.option_lists o where o.list_code = 'transfer_damage_reasons' and o.value_code = x.damaged_reason),
        'batch_id', (select l.batch_id from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = x.id::text and l.reason = 'transfer_in' and l.batch_id is not null order by l.id limit 1))
        order by x.received_at desc, x.id), '[]'::jsonb),
    count(*), count(*) filter (where x.received_damaged_qty is null), sum(x.received_damaged_qty), sum(x.qty - x.received_qty)
    into rows_, n, ncap, qd, qs
    from public.stock_transfers x join public.items i on i.id = x.item_id join public.locations lf on lf.id = x.from_location_id join public.locations lt on lt.id = x.to_location_id
   where x.status = 'received' and (x.received_at at time zone 'Asia/Dhaka')::date between f and t
     and (public.can_loc(x.to_location_id) or public.can_loc(x.from_location_id)) and (p_loc is null or x.to_location_id = p_loc or x.from_location_id = p_loc);
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'received_n', n, 'damaged_not_captured_n', ncap, 'damaged_total_captured', qd, 'short_total', qs);
end $$;

-- ---------- privileges ----------
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_rb3_qc_source') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qc_record', 'qc_list', 'transfer_damage_report')
           or (p.proname = 'stock_receive_transfer' and p.pronargs = 5) loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';

-- ===================== phase433.sql =====================
-- Phase 433 (bos433) - RPT-B3 / R6b: STOCKOUT LOG (#74), "SHELF LIFE NOT SET" NOTICE (#81), ACTUAL YIELD REPORT (#78).
-- Paste after phase432. Paste-twice safe. Earlier phase files are not edited; no shared function is re-created.
--
-- WHAT THIS ADDS
--   1. stockout_log: a simple digital entry at the shop (date, place, item, note, estimated missed quantity - optional). stockout_add / stockout_void / stockout_list / stockout_summary.
--      Every number is what a person wrote. A blank estimate is "not captured", never 0, and is never added into a total.
--      New grant stockout_log (owner, management, showroom_manager, storekeeper, salesperson get it the first time it is created; the owner can change that). Paper form code: to be given by owner.
--   2. shelf_life_missing(loc): the products that are made in the factory (an active recipe or a production run) and have NO shelf-life rule that applies today. Their batches get no expiry,
--      so every expiry list is silent about them. The screens show this as a notice and link to Settings > Shelf life (the maintenance screen already exists; this package only adds the notice).
--   3. yield_report(from, to, loc): production runs with the standard yield, the actual yield the person typed at production (blank = "not captured") and the difference.
-- Nothing here moves stock or money.

do $g$ begin
  if to_regprocedure('public._rb3_view_ok(int)') is null then raise exception 'phase433 needs phase430 first'; end if;
  if not exists (select 1 from information_schema.columns where table_name = 'production_runs' and column_name = 'yield_actual') then raise exception 'phase433 needs phase74 (production_runs.yield_actual)'; end if;
end $g$;

-- ---------- grant ----------
with ins as (
  insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
   ('stockout_log', 'stock', 50, 'স্টক শেষ (চাহিদা পূরণ হয়নি) লেখা', 'Stockout (চাহিদা পূরণ হয়নি) লেখা', 'Log a stockout (unmet demand)', 'once', null)
  on conflict (grant_code) do nothing returning grant_code)
insert into public.rule_grants (grant_code, role_code)
  select s.g, s.r from (values ('stockout_log', 'management'), ('stockout_log', 'showroom_manager'), ('stockout_log', 'storekeeper'), ('stockout_log', 'salesperson')) s(g, r)
  join ins on ins.grant_code = s.g
  where exists (select 1 from public.roles ro where ro.code = s.r)
  on conflict do nothing;

-- ---------- table ----------
create table if not exists public.stockout_log (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  log_date date not null,
  location_id int not null references public.locations(id),
  item_id uuid not null references public.items(id),
  note text check (note is null or length(note) <= 300),
  est_missed_qty numeric check (est_missed_qty is null or (est_missed_qty > 0 and est_missed_qty <= 1000000000000)),       -- item base unit; a person's estimate, optional
  status text not null default 'open' check (status in ('open', 'void')),
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  void_by uuid, void_at timestamptz, void_note text
);
create index if not exists stockout_log_loc on public.stockout_log (location_id, log_date);
create index if not exists stockout_log_item on public.stockout_log (item_id, log_date);
drop trigger if exists audit_stockout_log on public.stockout_log;
create trigger audit_stockout_log after insert or update on public.stockout_log for each row execute function public.log_change('id');
alter table public.stockout_log enable row level security;
drop policy if exists stockout_log_read on public.stockout_log;
create policy stockout_log_read on public.stockout_log for select to authenticated using (public.can_loc(location_id));
revoke all on public.stockout_log from public, anon, authenticated;
grant select on public.stockout_log to authenticated;

create or replace function public._rb3_stockout_ok(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and public.can_loc(p_loc) and (public.is_owner() or public.has_grant('stockout_log', p_loc));
$$;
create or replace function public._rb3_stockout_view(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and public.can_loc(p_loc) and (public.is_owner() or public.rpt_access('stock') or public.has_grant('stockout_log', p_loc));
$$;

create or replace function public.stockout_add(p_date date, p_loc int, p_item uuid, p_note text default null, p_est_qty numeric default null, p_unit text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare prev public.stockout_log; it public.items; sid text; bq numeric; id_ uuid; today date := (now() at time zone 'Asia/Dhaka')::date; n text := nullif(btrim(p_note), '');
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into prev from public.stockout_log where client_id = p_client;
    if found then
      if prev.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', prev.id);
    end if;
  end if;
  if p_loc is null or not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if not public._rb3_stockout_ok(p_loc) then raise exception 'not allowed'; end if;
  if p_date is null or p_date > today then raise exception 'bad_date'; end if;
  select * into it from public.items where id = p_item;
  if not found or not it.is_active then raise exception 'item_not_found'; end if;
  if n is not null and length(n) > 300 then raise exception 'bad_note'; end if;
  if p_est_qty is not null then
    bq := public._base_qty(p_item, p_est_qty, p_unit);
    if bq is null then raise exception 'unit_unknown'; end if;
    if not (bq between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.stockout_log (client_id, log_date, location_id, item_id, note, est_missed_qty, created_by, created_staff) values (p_client, p_date, p_loc, p_item, n, bq, auth.uid(), sid) returning id into id_;
  return jsonb_build_object('id', id_, 'est_missed_qty', bq);
end $$;

create or replace function public.stockout_void(p_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.stockout_log;
begin
  select * into r from public.stockout_log where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not (public._rb3_stockout_ok(r.location_id) and (r.created_by = auth.uid() or public.is_owner() or public.has_grant('stockout_log', r.location_id))) then raise exception 'not allowed'; end if;
  if r.status = 'void' then return jsonb_build_object('dup', true, 'status', 'void'); end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.stockout_log set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = p_id;
  return jsonb_build_object('status', 'void');
end $$;

create or replace function public.stockout_list(p_from date default null, p_to date default null, p_loc int default null, p_item uuid default null, p_with_void boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 30); t date := coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date);
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public._rb3_stockout_view(p_loc) then raise exception 'not allowed'; end if;
  return jsonb_build_object('from', f, 'to', t, 'rows', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'log_date', s.log_date, 'location_id', s.location_id, 'location', l.name_bn, 'location_en', l.name_en,
      'item_id', s.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(s.item_id), 'note', s.note, 'est_missed_qty', s.est_missed_qty,
      'status', s.status, 'created_staff', s.created_staff, 'created_at', s.created_at, 'void_note', s.void_note) order by s.log_date desc, s.created_at desc)
    from public.stockout_log s join public.items i on i.id = s.item_id join public.locations l on l.id = s.location_id
   where s.log_date between f and t and public._rb3_stockout_view(s.location_id) and (p_loc is null or s.location_id = p_loc) and (p_item is null or s.item_id = p_item)
     and (coalesce(p_with_void, false) or s.status = 'open')), '[]'::jsonb));
end $$;

create or replace function public.stockout_summary(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 30); t date := coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date);
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public._rb3_stockout_view(p_loc) then raise exception 'not allowed'; end if;
  return jsonb_build_object('from', f, 'to', t, 'rows', coalesce((select jsonb_agg(jsonb_build_object('location_id', z.location_id, 'location', l.name_bn, 'location_en', l.name_en, 'item_id', z.item_id, 'code', i.code,
      'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(z.item_id), 'events', z.ev, 'days', z.dy, 'last_date', z.last_d, 'est_missed_total', z.est, 'est_captured_n', z.estn,
      'est_not_captured_n', z.ev - z.estn, 'on_hand_now', (select b.qty from public.stock_balance b where b.item_id = z.item_id and b.location_id = z.location_id), 'tracked', i.tracked)
      order by z.ev desc, i.code)
    from (select s.location_id, s.item_id, count(*) as ev, count(distinct s.log_date) as dy, max(s.log_date) as last_d, sum(s.est_missed_qty) as est, count(s.est_missed_qty) as estn
            from public.stockout_log s where s.status = 'open' and s.log_date between f and t and public._rb3_stockout_view(s.location_id) and (p_loc is null or s.location_id = p_loc)
           group by s.location_id, s.item_id) z join public.items i on i.id = z.item_id join public.locations l on l.id = z.location_id), '[]'::jsonb));
end $$;

-- ---------- shelf life not set ----------
create or replace function public.shelf_life_missing(p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', x.id, 'code', x.code, 'name_bn', x.name_bn, 'name_en', x.name_en, 'why', x.why, 'last_run', x.last_run) order by x.code), '[]'::jsonb) into out_
    from (select i.id, i.code, i.name_bn, i.name_en,
                 case when exists (select 1 from public.recipes r where r.item_id = i.id and r.active) then 'recipe' else 'production_runs' end as why,
                 (select max(pr.made_at) from public.production_runs pr where pr.item_id = i.id and pr.status = 'done' and (p_loc is null or pr.location_id = p_loc)) as last_run
            from public.items i
           where i.is_active and i.tracked and public.shelf_life_for(i.id) is null
             and (exists (select 1 from public.recipes r where r.item_id = i.id and r.active)
                  or exists (select 1 from public.production_runs pr where pr.item_id = i.id and pr.status = 'done' and (p_loc is null or pr.location_id = p_loc) and public.can_loc(pr.location_id)))) x;
  return jsonb_build_object('count', jsonb_array_length(out_), 'items', out_);
end $$;

-- ---------- actual yield ----------
create or replace function public.yield_report(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 30); t date := coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date); rows_ jsonb; sm jsonb;
begin
  if not (public.is_active() and (public.is_owner() or public.rpt_access('stock') or public.rpt_access('quality') or public._recipe_read())) then raise exception 'not allowed'; end if;
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('run_id', r.id, 'day', (r.made_at at time zone 'Asia/Dhaka')::date, 'made_at', r.made_at, 'location_id', r.location_id, 'location', l.name_bn, 'item_id', r.item_id,
      'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(r.item_id), 'batches', r.batches, 'batch_id', r.batch_id, 'yield_std', r.yield_std, 'yield_actual', r.yield_actual,
      'booked', r.yield_base, 'var_pct', case when r.yield_actual is not null and r.yield_std > 0 then round((r.yield_actual - r.yield_std) / r.yield_std * 100, 2) end, 'note', r.note) order by r.made_at desc, r.id), '[]'::jsonb)
    into rows_
    from public.production_runs r join public.items i on i.id = r.item_id join public.locations l on l.id = r.location_id
   where r.status = 'done' and (r.made_at at time zone 'Asia/Dhaka')::date between f and t and public.can_loc(r.location_id) and (p_loc is null or r.location_id = p_loc);
  select coalesce(jsonb_agg(jsonb_build_object('item_id', z.item_id, 'code', z.code, 'name_bn', z.name_bn, 'name_en', z.name_en, 'runs', z.n, 'actual_captured', z.na, 'actual_not_captured', z.n - z.na,
      'std_of_captured', z.sstd, 'actual_total', z.sact, 'var_pct', case when z.sstd > 0 then round((z.sact - z.sstd) / z.sstd * 100, 2) end) order by z.code), '[]'::jsonb) into sm
    from (select r.item_id, i.code, i.name_bn, i.name_en, count(*) as n, count(r.yield_actual) filter (where r.yield_std is not null) as na,
                 sum(r.yield_std) filter (where r.yield_actual is not null) as sstd, sum(r.yield_actual) filter (where r.yield_std is not null) as sact
            from public.production_runs r join public.items i on i.id = r.item_id
           where r.status = 'done' and (r.made_at at time zone 'Asia/Dhaka')::date between f and t and public.can_loc(r.location_id) and (p_loc is null or r.location_id = p_loc)
           group by r.item_id, i.code, i.name_bn, i.name_en) z;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'summary', sm);
end $$;

-- ---------- privileges ----------
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_rb3_stockout_ok', '_rb3_stockout_view') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('stockout_add', 'stockout_void', 'stockout_list', 'stockout_summary', 'shelf_life_missing', 'yield_report') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';

-- ===================== phase434.sql =====================
-- Phase 434 (bos434) - RPT-B3 / R7a: PRICE TREND WITH VALUE (#92), AGREED PRICE PER ITEM AND SUPPLIER (#101), PREFERRED / ALTERNATIVE SUPPLIERS PER ITEM (#104, the capture part).
-- Paste after phase433. Paste-twice safe. Earlier phase files are not edited. The only existing thing changed in place is the purchase-rate-trend report (engine 3, key p2_rate_trend): it gains
-- ONE column (value = quantity x rate, summed) and a total; every existing column, filter and the cost-right rule are unchanged.
--
-- WHAT THIS ADDS
--   1. supplier_item_prices: the standard / agreed price of an item from a supplier (per the unit the owner types; stored per base unit), with a from-date. A new price closes the previous
--      one the day before. Nothing is deleted: a price is retired with a note. supplier_price_set / supplier_price_retire / supplier_price_list.
--   2. item_suppliers: which suppliers may supply an item, "preferred" or "alternative". item_supplier_set / item_supplier_retire / item_supplier_list.
--   3. Grant supplier_terms_manage (purchasing and management get it the first time it is created). The owner always may.
-- COST IS SECRET: agreed prices are costs. They are returned only to the owner, a holder of the cost right (rpt_cost_ok) or a holder of supplier_terms_manage. The tables are not readable by browsers.
-- No price, limit or tolerance is invented: a blank is a blank. Paper form code of these two captures: to be given by owner (digital entry screens only for now).

do $g$ begin
  if to_regprocedure('public._rb3_view_ok(int)') is null then raise exception 'phase434 needs phase430 first'; end if;
  if to_regclass('public.report_defs3') is null then raise exception 'phase434 needs phase24 and phase26 (report engine 3)'; end if;
end $g$;

-- ---------- #92 purchase-rate trend: a value column ----------
create or replace function public._r3q_p2_rate_trend(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with cat as (select public.rpt_arr_text(flt -> 'categories') as c),
  x as (
    select r.item_id, r.sk, min(r.sname) as sname, count(*) as n, sum(r.qty) as qty,
           (array_agg(r.rate order by r.dt, r.ord))[1] as first_rate, (array_agg(r.rate order by r.dt desc, r.ord desc))[1] as last_rate,
           min(r.rate) as min_rate, max(r.rate) as max_rate, sum(r.qty * r.rate) / nullif(sum(r.qty), 0) as avg_rate, sum(r.qty * r.rate) as value, max(r.dt) as last_date
      from public._p26_rates(d1, d2, locs) r group by r.item_id, r.sk)
  select jsonb_build_object('item_code', i.code, 'item_bn', i.name_bn, 'supplier', x.sname, 'n', x.n, 'qty', round(x.qty, 3),
    'first_rate', round(x.first_rate, 4), 'last_rate', round(x.last_rate, 4), 'min_rate', round(x.min_rate, 4), 'max_rate', round(x.max_rate, 4), 'avg_rate', round(x.avg_rate, 4),
    'value', round(x.value, 2),
    'change_pct', case when x.n > 1 and x.first_rate > 0 then round((x.last_rate - x.first_rate) / x.first_rate * 100, 2) end, 'last_date', x.last_date)
    from x join public.items i on i.id = x.item_id cross join cat
   where cat.c is null or i.category = any (cat.c);
$$;
update public.report_defs3 set
  cols = '[["item_code","কোড","Code","text"],["item_bn","আইটেম","Item","text"],["supplier","সাপ্লায়ার","Supplier","text"],["n","বার","Times","int"],["qty","পরিমাণ","Quantity","num"],["first_rate","প্রথম দর","First rate","money"],["last_rate","শেষ দর","Last rate","money"],["min_rate","সর্বনিম্ন","Lowest","money"],["max_rate","সর্বোচ্চ","Highest","money"],["avg_rate","গড় দর","Average rate","money"],["value","মূল্য (পরিমাণ × দর)","Value (quantity x rate)","money"],["change_pct","বদল %","Change %","pct"],["last_date","শেষ তারিখ","Last date","date"]]'::jsonb,
  tot = array['value']
 where key = 'p2_rate_trend';
revoke all on function public._r3q_p2_rate_trend(date, date, int[], jsonb) from public, anon, authenticated;

-- ---------- grant ----------
with ins as (
  insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
   ('supplier_terms_manage', 'purchase', 54, 'সাপ্লায়ারের নির্ধারিত দাম ও পছন্দের সাপ্লায়ার ঠিক করা', 'Supplier এর agreed price ও preferred supplier ঠিক করা', 'Set agreed supplier prices and preferred / alternative suppliers', 'once', null)
  on conflict (grant_code) do nothing returning grant_code)
insert into public.rule_grants (grant_code, role_code)
  select s.g, s.r from (values ('supplier_terms_manage', 'purchasing'), ('supplier_terms_manage', 'management')) s(g, r)
  join ins on ins.grant_code = s.g
  where exists (select 1 from public.roles ro where ro.code = s.r)
  on conflict do nothing;

create or replace function public._rb3_terms_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('supplier_terms_manage'));
$$;
-- may the caller see agreed prices (costs)?
create or replace function public._rb3_terms_cost_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.rpt_cost_ok() or public.has_grant('supplier_terms_manage'));
$$;

-- ---------- tables ----------
create table if not exists public.supplier_item_prices (
  id bigserial primary key,
  item_id uuid not null references public.items(id),
  supplier_id uuid not null references public.suppliers(id),
  price numeric not null check (price > 0 and price <= 1000000000),                 -- as typed, per unit
  unit text,                                                                         -- the unit the price is per (null = the item's base unit)
  price_base numeric not null check (price_base > 0 and price_base <= 1000000000),  -- per base unit (what the bill lines are compared with)
  effective_from date not null,
  effective_to date,
  active boolean not null default true,
  note text check (note is null or length(note) <= 300),
  created_by uuid, created_at timestamptz not null default now(),
  retired_by uuid, retired_at timestamptz, retired_note text,
  check (effective_to is null or effective_to >= effective_from)
);
create index if not exists supplier_item_prices_pair on public.supplier_item_prices (item_id, supplier_id, effective_from);
drop trigger if exists audit_supplier_item_prices on public.supplier_item_prices;
create trigger audit_supplier_item_prices after insert or update on public.supplier_item_prices for each row execute function public.log_change('id');
alter table public.supplier_item_prices enable row level security;
revoke all on public.supplier_item_prices from public, anon, authenticated;
revoke all on sequence public.supplier_item_prices_id_seq from public, anon, authenticated;

create table if not exists public.item_suppliers (
  id bigserial primary key,
  item_id uuid not null references public.items(id),
  supplier_id uuid not null references public.suppliers(id),
  rank text not null check (rank in ('preferred', 'alternative')),
  active boolean not null default true,
  note text check (note is null or length(note) <= 300),
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz,
  retired_note text,
  unique (item_id, supplier_id)
);
create index if not exists item_suppliers_item on public.item_suppliers (item_id) where active;
drop trigger if exists audit_item_suppliers on public.item_suppliers;
create trigger audit_item_suppliers after insert or update on public.item_suppliers for each row execute function public.log_change('id');
alter table public.item_suppliers enable row level security;
drop policy if exists item_suppliers_read on public.item_suppliers;
create policy item_suppliers_read on public.item_suppliers for select to authenticated using (public.is_active());
revoke all on public.item_suppliers from public, anon, authenticated;
grant select on public.item_suppliers to authenticated;
revoke all on sequence public.item_suppliers_id_seq from public, anon, authenticated;

-- ---------- agreed prices ----------
create or replace function public.supplier_price_set(p_item uuid, p_supplier uuid, p_price numeric, p_unit text default null, p_from date default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare today date := (now() at time zone 'Asia/Dhaka')::date; fr date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date); f numeric; prev public.supplier_item_prices; nid bigint; un text := nullif(btrim(p_unit), '');
begin
  if not public._rb3_terms_ok() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.items where id = p_item and is_active) then raise exception 'item_not_found'; end if;
  if not exists (select 1 from public.suppliers where id = p_supplier and active) then raise exception 'supplier_not_found'; end if;
  if p_price is null or not (p_price > 0 and p_price <= 1000000000) then raise exception 'bad_price'; end if;
  if fr > today + 366 or fr < date '2000-01-01' then raise exception 'bad_date'; end if;
  if length(coalesce(p_note, '')) > 300 then raise exception 'bad_note'; end if;
  f := public._unit_factor_base(p_item, un);
  if f is null or not (f > 0) then raise exception 'unit_unknown'; end if;
  select * into prev from public.supplier_item_prices where item_id = p_item and supplier_id = p_supplier and active and effective_to is null order by effective_from desc limit 1 for update;
  if found then
    if prev.effective_from >= fr then raise exception 'overlaps_existing'; end if;
    update public.supplier_item_prices set effective_to = fr - 1 where id = prev.id;
  end if;
  insert into public.supplier_item_prices (item_id, supplier_id, price, unit, price_base, effective_from, note, created_by)
    values (p_item, p_supplier, round(p_price, 4), un, round(p_price / f, 6), fr, nullif(btrim(p_note), ''), auth.uid()) returning id into nid;
  return jsonb_build_object('id', nid, 'price_base', round(p_price / f, 6), 'closed_previous', prev.id);
end $$;

create or replace function public.supplier_price_retire(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.supplier_item_prices;
begin
  if not public._rb3_terms_ok() then raise exception 'not allowed'; end if;
  select * into r from public.supplier_item_prices where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not r.active then return jsonb_build_object('dup', true); end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.supplier_item_prices set active = false, retired_by = auth.uid(), retired_at = now(), retired_note = left(btrim(p_note), 300),
    effective_to = coalesce(effective_to, greatest(effective_from, (now() at time zone 'Asia/Dhaka')::date)) where id = p_id;
  return jsonb_build_object('id', p_id, 'active', false);
end $$;

create or replace function public.supplier_price_list(p_item uuid default null, p_supplier uuid default null, p_all boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._rb3_terms_cost_ok() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'item_id', p.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'supplier_id', p.supplier_id, 'supplier', s.name,
      'price', p.price, 'unit', p.unit, 'base_unit', public._item_base(p.item_id), 'price_base', p.price_base, 'effective_from', p.effective_from, 'effective_to', p.effective_to, 'active', p.active,
      'current', p.active and p.effective_from <= (now() at time zone 'Asia/Dhaka')::date and (p.effective_to is null or p.effective_to >= (now() at time zone 'Asia/Dhaka')::date),
      'note', p.note, 'retired_note', p.retired_note, 'can_edit', public._rb3_terms_ok()) order by i.code, s.name, p.effective_from desc)
    from public.supplier_item_prices p join public.items i on i.id = p.item_id join public.suppliers s on s.id = p.supplier_id
   where (p_item is null or p.item_id = p_item) and (p_supplier is null or p.supplier_id = p_supplier) and (coalesce(p_all, false) or p.active)), '[]'::jsonb);
end $$;

-- ---------- preferred / alternative suppliers ----------
create or replace function public.item_supplier_set(p_item uuid, p_supplier uuid, p_rank text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.item_suppliers; nid bigint;
begin
  if not public._rb3_terms_ok() then raise exception 'not allowed'; end if;
  if p_rank is null or p_rank not in ('preferred', 'alternative') then raise exception 'bad_rank'; end if;
  if not exists (select 1 from public.items where id = p_item and is_active) then raise exception 'item_not_found'; end if;
  if not exists (select 1 from public.suppliers where id = p_supplier and active) then raise exception 'supplier_not_found'; end if;
  if length(coalesce(p_note, '')) > 300 then raise exception 'bad_note'; end if;
  select * into r from public.item_suppliers where item_id = p_item and supplier_id = p_supplier for update;
  if found then
    update public.item_suppliers set rank = p_rank, active = true, note = coalesce(nullif(btrim(p_note), ''), note), updated_by = auth.uid(), updated_at = now(), retired_note = null where id = r.id;
    return jsonb_build_object('id', r.id, 'updated', true);
  end if;
  insert into public.item_suppliers (item_id, supplier_id, rank, note, created_by) values (p_item, p_supplier, p_rank, nullif(btrim(p_note), ''), auth.uid()) returning id into nid;
  return jsonb_build_object('id', nid, 'updated', false);
end $$;

create or replace function public.item_supplier_retire(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.item_suppliers;
begin
  if not public._rb3_terms_ok() then raise exception 'not allowed'; end if;
  select * into r from public.item_suppliers where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not r.active then return jsonb_build_object('dup', true); end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.item_suppliers set active = false, updated_by = auth.uid(), updated_at = now(), retired_note = left(btrim(p_note), 300) where id = p_id;
  return jsonb_build_object('id', p_id, 'active', false);
end $$;

create or replace function public.item_supplier_list(p_item uuid default null, p_supplier uuid default null, p_all boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_active() and (public.is_owner() or public.rpt_access('purchase') or public.rpt_access('stock') or public.has_grant('supplier_terms_manage'))) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'item_id', x.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'supplier_id', x.supplier_id, 'supplier', s.name,
      'rank', x.rank, 'active', x.active, 'note', x.note, 'retired_note', x.retired_note, 'can_edit', public._rb3_terms_ok()) order by i.code, x.rank, s.name)
    from public.item_suppliers x join public.items i on i.id = x.item_id join public.suppliers s on s.id = x.supplier_id
   where (p_item is null or x.item_id = p_item) and (p_supplier is null or x.supplier_id = p_supplier) and (coalesce(p_all, false) or x.active)), '[]'::jsonb);
end $$;

-- ---------- privileges ----------
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_rb3_terms_ok', '_rb3_terms_cost_ok') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace
           and p.proname in ('supplier_price_set', 'supplier_price_retire', 'supplier_price_list', 'item_supplier_set', 'item_supplier_retire', 'item_supplier_list') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
select public._r3_lockdown();

notify pgrst, 'reload schema';

-- ===================== phase435.sql =====================
-- Phase 435 (bos435) - RPT-B3 / R7b: PURCHASING REPORTS - supplier returns and purchase adjustments (#100), agreed-price variance (#101), supplier rejection rate (#103),
-- supplier dependency and risk (#104), supplier delivery performance (#102).
-- Paste after phase434. Paste-twice safe. Earlier phase files are not edited; no shared function is re-created. All reports are READ ONLY.
--
-- Open to the roles that already hold the purchase report right (report_purchase, or view_reports) and the owner; money columns are shown only to who may see costs (rpt_cost_ok);
-- without that right the money keys are null and the answer says cost_hidden. A place a person may not see is never included.
-- Missing data is said, never turned into 0: a check with no quantity, a PO with no promised date, an item with no declared supplier, a bill line with no agreed price are all COUNTED and
-- named as "not captured" in the answer.
-- Drill-down: every row carries the id of its source (bill, quality check, purchase-order entry) so the screen can open it.
--   #100 supplier_returns_report(from, to, loc, supplier)       returns, bill discounts, voided bills, supplier refunds, per-supplier summary
--   #101 purch_price_variance(from, to, loc, supplier, item)    posted bill lines against the agreed price valid on the bill date
--   #103 supplier_rejection_rate(from, to, loc, supplier)       latest quality check per receipt: pass / hold / reject, by check and by quantity where typed
--   #104 supplier_dependency(from, to, loc)                     per item: suppliers really used, share of the biggest, declared preferred / alternative, risk flags
--   #102 supplier_delivery_perf(from, to, loc, supplier)        paper PO (06-3) promised date against the GRN (04-1) dates

do $g$ begin
  if to_regprocedure('public.item_supplier_list(uuid,uuid,boolean)') is null then raise exception 'phase435 needs phase434 first'; end if;
  if to_regprocedure('public._p26_po(date,date,int[])') is null then raise exception 'phase435 needs phase26 first'; end if;
end $g$;

-- the places the caller may see (and p_loc when given); a given place that is not allowed stops the call
create or replace function public._rb3_locs(p_loc int) returns int[] language plpgsql stable security definer set search_path = public as $$
begin
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  return coalesce((select array_agg(l.id) from public.locations l where public.can_loc(l.id) and (p_loc is null or l.id = p_loc)), '{}');
end $$;
create or replace function public._rb3_range(p_from date, p_to date, out f date, out t date) language plpgsql stable as $$
begin
  f := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 30); t := coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date);
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
end $$;
create or replace function public._rb3_purch_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.rpt_access('purchase'));
$$;

-- ---------- #100 returns and adjustments ----------
create or replace function public.supplier_returns_report(p_from date default null, p_to date default null, p_loc int default null, p_supplier uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r record; locs int[]; cost boolean := public.rpt_cost_ok(); returns_ jsonb; disc jsonb; voids jsonb; refunds jsonb; summ jsonb; cap constant int := 300;
begin
  if not public._rb3_purch_ok() then raise exception 'not allowed'; end if;
  select * into r from public._rb3_range(p_from, p_to);
  locs := public._rb3_locs(p_loc);
  select coalesce(jsonb_agg(x.j order by x.d desc), '[]'::jsonb) into returns_ from (
    select b.bill_date as d, jsonb_build_object('bill_id', b.id, 'bill_no', b.bill_no, 'bill_date', b.bill_date, 'supplier_id', b.supplier_id, 'supplier', s.name, 'location_id', b.location_id, 'location', l.name_bn,
      'ref_bill_id', b.ref_bill_id, 'ref_bill_no', rb.bill_no, 'reason_code', b.reason_code,
      'reason_label', (select coalesce(o.label_en, o.value_code) from public.option_lists o where o.list_code = 'return_reasons' and o.value_code = b.reason_code),
      'reason_label_bn', (select o.label_bn from public.option_lists o where o.list_code = 'return_reasons' and o.value_code = b.reason_code),
      'total', case when cost then b.total end, 'variance', case when cost then b.variance end,
      'items', (select coalesce(jsonb_agg(jsonb_build_object('code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'qty', pl.qty, 'unit', pl.unit) order by pl.line_no), '[]'::jsonb)
                  from public.purchase_lines pl left join public.items i on i.id = pl.item_id where pl.bill_id = b.id)) as j
      from public.purchase_bills b join public.suppliers s on s.id = b.supplier_id join public.locations l on l.id = b.location_id left join public.purchase_bills rb on rb.id = b.ref_bill_id
     where b.kind = 'return' and b.status = 'posted' and b.bill_date between r.f and r.t and b.location_id = any (locs) and (p_supplier is null or b.supplier_id = p_supplier)
     order by b.bill_date desc limit cap) x;
  select coalesce(jsonb_agg(x.j order by x.d desc), '[]'::jsonb) into disc from (
    select b.bill_date as d, jsonb_build_object('bill_id', b.id, 'bill_no', b.bill_no, 'bill_date', b.bill_date, 'supplier_id', b.supplier_id, 'supplier', s.name, 'location', l.name_bn,
      'subtotal', case when cost then b.subtotal end, 'discount', case when cost then b.discount end, 'total', case when cost then b.total end) as j
      from public.purchase_bills b join public.suppliers s on s.id = b.supplier_id join public.locations l on l.id = b.location_id
     where b.kind = 'bill' and b.status = 'posted' and b.discount > 0 and b.bill_date between r.f and r.t and b.location_id = any (locs) and (p_supplier is null or b.supplier_id = p_supplier)
     order by b.bill_date desc limit cap) x;
  select coalesce(jsonb_agg(x.j order by x.d desc), '[]'::jsonb) into voids from (
    select b.bill_date as d, jsonb_build_object('bill_id', b.id, 'bill_no', b.bill_no, 'bill_date', b.bill_date, 'kind', b.kind, 'supplier_id', b.supplier_id, 'supplier', s.name, 'location', l.name_bn,
      'total', case when cost then b.total end, 'void_note', b.void_note, 'void_at', b.void_at) as j
      from public.purchase_bills b join public.suppliers s on s.id = b.supplier_id join public.locations l on l.id = b.location_id
     where b.status = 'void' and b.bill_date between r.f and r.t and b.location_id = any (locs) and (p_supplier is null or b.supplier_id = p_supplier)
     order by b.bill_date desc limit cap) x;
  select coalesce(jsonb_agg(x.j order by x.d desc), '[]'::jsonb) into refunds from (
    select (f.refunded_at at time zone 'Asia/Dhaka')::date as d, jsonb_build_object('refund_id', f.id, 'day', (f.refunded_at at time zone 'Asia/Dhaka')::date, 'supplier_id', f.supplier_id, 'supplier', s.name, 'location', l.name_bn,
      'amount', case when cost then f.amount end, 'mode', f.mode, 'reason_code', f.reason_code, 'note', f.note) as j
      from public.supplier_refunds f join public.suppliers s on s.id = f.supplier_id join public.locations l on l.id = f.location_id
     where not f.voided and (f.refunded_at at time zone 'Asia/Dhaka')::date between r.f and r.t and f.location_id = any (locs) and (p_supplier is null or f.supplier_id = p_supplier)
     order by f.refunded_at desc limit cap) x;
  select coalesce(jsonb_agg(jsonb_build_object('supplier_id', z.sid, 'supplier', z.sname, 'purchases_n', z.pn, 'purchases_total', case when cost then z.pt end, 'returns_n', z.rn, 'returns_total', case when cost then z.rt end,
      'return_pct', case when cost and z.pt > 0 then round(z.rt / z.pt * 100, 2) end, 'discounts_total', case when cost then z.dt end, 'voided_n', z.vn, 'voided_total', case when cost then z.vt end,
      'refunds_n', z.fn, 'refunds_total', case when cost then z.ft end) order by z.sname), '[]'::jsonb) into summ from (
    select s.id as sid, s.name as sname,
      count(*) filter (where b.kind = 'bill' and b.status = 'posted') as pn, coalesce(sum(b.total) filter (where b.kind = 'bill' and b.status = 'posted'), 0) as pt,
      count(*) filter (where b.kind = 'return' and b.status = 'posted') as rn, coalesce(sum(b.total) filter (where b.kind = 'return' and b.status = 'posted'), 0) as rt,
      coalesce(sum(b.discount) filter (where b.kind = 'bill' and b.status = 'posted'), 0) as dt,
      count(*) filter (where b.status = 'void') as vn, coalesce(sum(b.total) filter (where b.status = 'void'), 0) as vt,
      (select count(*) from public.supplier_refunds f where f.supplier_id = s.id and not f.voided and (f.refunded_at at time zone 'Asia/Dhaka')::date between r.f and r.t and f.location_id = any (locs)) as fn,
      coalesce((select sum(f.amount) from public.supplier_refunds f where f.supplier_id = s.id and not f.voided and (f.refunded_at at time zone 'Asia/Dhaka')::date between r.f and r.t and f.location_id = any (locs)), 0) as ft
      from public.suppliers s left join public.purchase_bills b on b.supplier_id = s.id and b.bill_date between r.f and r.t and b.location_id = any (locs)
     where (p_supplier is null or s.id = p_supplier)
     group by s.id, s.name) z where z.pn + z.rn + z.vn + z.fn > 0;
  return jsonb_build_object('from', r.f, 'to', r.t, 'cost_hidden', not cost, 'returns', returns_, 'discounts', disc, 'voided', voids, 'refunds', refunds, 'summary', summ,
    'truncated', jsonb_array_length(returns_) >= cap or jsonb_array_length(disc) >= cap or jsonb_array_length(voids) >= cap or jsonb_array_length(refunds) >= cap);
end $$;

-- ---------- #101 agreed price variance ----------
create or replace function public.purch_price_variance(p_from date default null, p_to date default null, p_loc int default null, p_supplier uuid default null, p_item uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r record; locs int[]; rows_ jsonb; s jsonb; tot_lines int; with_p int; extra_tot numeric; cap constant int := 500;
begin
  if not (public._rb3_purch_ok() and public.rpt_cost_ok()) then raise exception 'not allowed'; end if;
  select * into r from public._rb3_range(p_from, p_to);
  locs := public._rb3_locs(p_loc);
  with b as (
    select b.id as bill_id, pl.line_no, b.bill_date, b.supplier_id, sp.name as sname, b.bill_no, l.name_bn as place, pl.item_id, i.code, i.name_bn, i.name_en,
           coalesce(pl.base_qty, pl.qty) as qty, coalesce(pl.unit_cost_base, pl.unit_cost) as actual, ap.price_base as agreed, ap.id as agreed_id, ap.effective_from as agreed_from,
           case when ap.id is not null then (coalesce(pl.unit_cost_base, pl.unit_cost) - ap.price_base) * coalesce(pl.base_qty, pl.qty) end as extra
      from public.purchase_bills b join public.purchase_lines pl on pl.bill_id = b.id join public.items i on i.id = pl.item_id join public.suppliers sp on sp.id = b.supplier_id join public.locations l on l.id = b.location_id
      left join lateral (select p.* from public.supplier_item_prices p where p.item_id = pl.item_id and p.supplier_id = b.supplier_id and p.effective_from <= b.bill_date
                          and (p.effective_to is null or p.effective_to >= b.bill_date) and (p.active or (p.retired_at at time zone 'Asia/Dhaka')::date > b.bill_date)
                          order by p.effective_from desc, p.id desc limit 1) ap on true
     where b.kind = 'bill' and b.status = 'posted' and b.bill_date between r.f and r.t and b.location_id = any (locs) and (p_supplier is null or b.supplier_id = p_supplier)
       and (p_item is null or pl.item_id = p_item) and pl.item_id is not null),
  lim as (select * from b order by bill_date desc, line_no limit cap)
  select (select coalesce(jsonb_agg(jsonb_build_object('bill_id', x.bill_id, 'bill_no', x.bill_no, 'bill_date', x.bill_date, 'supplier_id', x.supplier_id, 'supplier', x.sname, 'location', x.place,
              'item_id', x.item_id, 'code', x.code, 'name_bn', x.name_bn, 'name_en', x.name_en, 'base_unit', public._item_base(x.item_id), 'qty', x.qty, 'actual_price', round(x.actual, 4),
              'agreed_price', x.agreed, 'agreed_id', x.agreed_id, 'agreed_from', x.agreed_from,
              'diff', case when x.agreed_id is not null then round(x.actual - x.agreed, 4) end,
              'diff_pct', case when x.agreed_id is not null then round((x.actual - x.agreed) / x.agreed * 100, 2) end,
              'extra_cost', case when x.agreed_id is not null then round(x.extra, 2) end) order by x.bill_date desc, x.line_no), '[]'::jsonb) from lim x),
         (select coalesce(jsonb_agg(jsonb_build_object('supplier_id', z.supplier_id, 'supplier', z.sname, 'lines', z.n, 'lines_with_agreed', z.np, 'lines_without_agreed', z.n - z.np,
              'extra_cost', round(z.ex, 2), 'lines_above', z.up, 'lines_below', z.dn) order by z.sname), '[]'::jsonb)
            from (select supplier_id, sname, count(*) as n, count(agreed_id) as np, sum(extra) as ex, count(*) filter (where extra > 0.005) as up, count(*) filter (where extra < -0.005) as dn from b group by supplier_id, sname) z),
         (select count(*) from b), (select count(agreed_id) from b), (select round(sum(extra), 2) from b)
    into rows_, s, tot_lines, with_p, extra_tot;
  return jsonb_build_object('from', r.f, 'to', r.t, 'rows', rows_, 'summary', s, 'lines', tot_lines, 'lines_with_agreed', with_p, 'lines_without_agreed', tot_lines - with_p, 'extra_cost_total', extra_tot,
    'truncated', tot_lines > cap, 'basis', 'bill line price per base unit, before the bill discount, against the agreed price valid on the bill date');
end $$;

-- ---------- #103 supplier rejection rate ----------
create or replace function public.supplier_rejection_rate(p_from date default null, p_to date default null, p_loc int default null, p_supplier uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r record; locs int[]; rows_ jsonb; checks_ jsonb; cap constant int := 500;
begin
  if not (public.is_active() and (public.is_owner() or public.rpt_access('purchase') or public.rpt_access('quality'))) then raise exception 'not allowed'; end if;
  select * into r from public._rb3_range(p_from, p_to);
  locs := public._rb3_locs(p_loc);
  with last_ as (
    select distinct on (q.source_type, q.source_id) q.* from public.qc_records q
     where q.source_type = 'grn' order by q.source_type, q.source_id, q.created_at desc, q.id desc),
  c as (
    select l.* from last_ l where l.location_id = any (locs) and (l.created_at at time zone 'Asia/Dhaka')::date between r.f and r.t and (p_supplier is null or l.supplier_id = p_supplier))
  select coalesce(jsonb_agg(jsonb_build_object('supplier_id', z.sid, 'supplier', z.sname, 'checks', z.n, 'pass', z.np, 'hold', z.nh, 'reject', z.nr,
      'reject_rate_pct', case when z.n > 0 then round(z.nr::numeric / z.n * 100, 2) end,
      'qty_captured_n', z.nq, 'qty_not_captured_n', z.n - z.nq, 'qty_checked', z.qc, 'qty_rejected', z.qr,
      'reject_rate_qty_pct', case when z.qc > 0 then round(z.qr / z.qc * 100, 2) end,
      'receipts_n', z.rec, 'receipts_checked_n', z.n, 'share_checked_pct', case when z.rec > 0 then round(least(z.n, z.rec)::numeric / z.rec * 100, 1) end,
      'supplier_not_captured', z.sid is null) order by z.sname nulls last), '[]'::jsonb) into rows_ from (
    select c.supplier_id as sid, s.name as sname, count(*) as n, count(*) filter (where c.status = 'pass') as np, count(*) filter (where c.status = 'hold') as nh, count(*) filter (where c.status = 'reject') as nr,
           count(c.qty) as nq, sum(c.qty) as qc, coalesce(sum(c.qty) filter (where c.status = 'reject'), 0) as qr,
           case when c.supplier_id is null then null else (select count(*) from public.purchase_bills b where b.supplier_id = c.supplier_id and b.kind = 'bill' and b.status = 'posted'
                  and b.bill_date between r.f and r.t and b.location_id = any (locs)) end as rec
      from c left join public.suppliers s on s.id = c.supplier_id group by c.supplier_id, s.name) z;
  select coalesce(jsonb_agg(jsonb_build_object('check_id', c.id, 'source_id', c.source_id, 'day', (c.created_at at time zone 'Asia/Dhaka')::date, 'status', c.status, 'supplier_id', c.supplier_id, 'supplier', s.name,
      'item_id', c.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'qty', c.qty, 'base_unit', case when i.id is null then null else public._item_base(i.id) end, 'note', c.note, 'location_id', c.location_id,
      'is_bill', exists (select 1 from public.purchase_bills b where b.id = c.source_id)) order by c.created_at desc), '[]'::jsonb) into checks_ from (
    select distinct on (q.source_id) q.* from public.qc_records q where q.source_type = 'grn' order by q.source_id, q.created_at desc, q.id desc) c
    left join public.suppliers s on s.id = c.supplier_id left join public.items i on i.id = c.item_id
   where c.location_id = any (locs) and (c.created_at at time zone 'Asia/Dhaka')::date between r.f and r.t and (p_supplier is null or c.supplier_id = p_supplier);
  return jsonb_build_object('from', r.f, 'to', r.t, 'rows', rows_, 'checks', checks_,
    'basis', 'latest quality check of each received lot (purchase bill or paper GRN 04-1); the paper GRN rejected lines of the supplier scorecard are a separate count');
end $$;

-- ---------- #104 dependency and risk ----------
create or replace function public.supplier_dependency(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r record; locs int[]; cost boolean := public.rpt_cost_ok(); rows_ jsonb; summ jsonb;
begin
  if not _rb3_purch_ok() then raise exception 'not allowed'; end if;
  select * into r from public._rb3_range(p_from, p_to);
  locs := public._rb3_locs(p_loc);
  with u as (
    select pl.item_id, b.supplier_id, sum(coalesce(pl.base_qty, pl.qty)) as qty, sum(pl.amount) as val, count(distinct b.id) as bills
      from public.purchase_bills b join public.purchase_lines pl on pl.bill_id = b.id
     where b.kind = 'bill' and b.status = 'posted' and b.bill_date between r.f and r.t and b.location_id = any (locs) and pl.item_id is not null
     group by pl.item_id, b.supplier_id),
  t as (select item_id, sum(qty) as tq, count(*) as ns from u group by item_id),
  top as (select distinct on (u.item_id) u.item_id, u.supplier_id, u.qty from u order by u.item_id, u.qty desc, u.supplier_id),
  d as (select x.item_id,
               coalesce(jsonb_agg(jsonb_build_object('supplier_id', x.supplier_id, 'supplier', s.name)) filter (where x.rank = 'preferred'), '[]'::jsonb) as pref,
               coalesce(jsonb_agg(jsonb_build_object('supplier_id', x.supplier_id, 'supplier', s.name)) filter (where x.rank = 'alternative'), '[]'::jsonb) as alt,
               array_agg(x.supplier_id) as declared
          from public.item_suppliers x join public.suppliers s on s.id = x.supplier_id where x.active group by x.item_id),
  rowsq as (
    select i.id as item_id, i.code, i.name_bn, i.name_en, t.ns, t.tq, ts.name as top_name, ts.id as top_id, round(top.qty / nullif(t.tq, 0) * 100, 1) as top_share,
           (select sum(u2.val) from u u2 where u2.item_id = i.id) as val_total, d.pref, d.alt, d.declared,
           coalesce((select jsonb_agg(jsonb_build_object('supplier_id', u3.supplier_id, 'supplier', s3.name, 'qty', round(u3.qty, 4), 'share_pct', round(u3.qty / nullif(t.tq, 0) * 100, 1),
                     'value', case when cost then round(u3.val, 2) end, 'declared', u3.supplier_id = any (coalesce(d.declared, '{}'))) order by u3.qty desc)
                     from u u3 join public.suppliers s3 on s3.id = u3.supplier_id where u3.item_id = i.id), '[]'::jsonb) as used
      from t join public.items i on i.id = t.item_id join top on top.item_id = t.item_id join public.suppliers ts on ts.id = top.supplier_id left join d on d.item_id = t.item_id)
  select coalesce(jsonb_agg(jsonb_build_object('item_id', q.item_id, 'code', q.code, 'name_bn', q.name_bn, 'name_en', q.name_en, 'base_unit', public._item_base(q.item_id),
      'suppliers_used', q.ns, 'qty_total', round(q.tq, 4), 'top_supplier_id', q.top_id, 'top_supplier', q.top_name, 'top_share_pct', q.top_share,
      'value_total', case when cost then round(q.val_total, 2) end,
      'preferred', coalesce(q.pref, '[]'::jsonb), 'alternatives', coalesce(q.alt, '[]'::jsonb), 'used', q.used,
      'flags', to_jsonb(array_remove(array[
        case when q.ns = 1 then 'single_supplier_used' end,
        case when q.declared is null then 'declared_suppliers_not_captured' end,
        case when q.declared is not null and jsonb_array_length(coalesce(q.alt, '[]'::jsonb)) = 0 then 'no_alternative_declared' end,
        case when q.declared is not null and jsonb_array_length(coalesce(q.pref, '[]'::jsonb)) > 0 and not exists (select 1 from jsonb_array_elements(q.pref) pp where (pp ->> 'supplier_id')::uuid = q.top_id) then 'preferred_not_the_main_supplier' end,
        case when q.declared is not null and exists (select 1 from jsonb_array_elements(q.used) uu where (uu ->> 'declared')::boolean is not true) then 'used_supplier_not_declared' end], null))
      ) order by q.top_share desc, q.code), '[]'::jsonb) into rows_ from rowsq q;
  select jsonb_build_object('items', jsonb_array_length(rows_),
      'single_supplier', (select count(*) from jsonb_array_elements(rows_) x where x -> 'flags' ? 'single_supplier_used'),
      'declared_not_captured', (select count(*) from jsonb_array_elements(rows_) x where x -> 'flags' ? 'declared_suppliers_not_captured'),
      'no_alternative', (select count(*) from jsonb_array_elements(rows_) x where x -> 'flags' ? 'no_alternative_declared'),
      'preferred_not_main', (select count(*) from jsonb_array_elements(rows_) x where x -> 'flags' ? 'preferred_not_the_main_supplier'),
      'used_not_declared', (select count(*) from jsonb_array_elements(rows_) x where x -> 'flags' ? 'used_supplier_not_declared')) into summ;
  return jsonb_build_object('from', r.f, 'to', r.t, 'cost_hidden', not cost, 'rows', rows_, 'summary', summ,
    'basis', 'posted purchase bills of the period; shares by quantity in the base unit; declared suppliers from the item_suppliers list');
end $$;

-- ---------- #102 delivery performance ----------
create or replace function public.supplier_delivery_perf(p_from date default null, p_to date default null, p_loc int default null, p_supplier uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r record; locs int[]; sname text; rows_ jsonb; summ jsonb; npo int; today date := (now() at time zone 'Asia/Dhaka')::date; cap constant int := 500;
begin
  if not (public.is_active() and (public.is_owner() or public.rpt_access('purchase'))) then raise exception 'not allowed'; end if;
  select * into r from public._rb3_range(p_from, p_to);
  locs := public._rb3_locs(p_loc);
  if p_supplier is not null then select lower(btrim(name)) into sname from public.suppliers where id = p_supplier; if sname is null then raise exception 'supplier_not_found'; end if; end if;
  with d as (
    select p.*, l.name_bn as place, x.st, x.late, x.lead
      from public._p26_po(r.f, r.t, locs) p join public.locations l on l.id = p.location_id
      cross join lateral (select
          case when p.grn_n > 0 and p.lines_open = 0 then
                 case when p.delivery_date is null then 'received_no_promised_date' when p.last_grn <= p.delivery_date then 'on_time' else 'late' end
               when p.grn_n > 0 then
                 case when p.delivery_date is null then 'partial_no_promised_date' when today > p.delivery_date then 'partial_overdue' else 'partial' end
               else
                 case when p.delivery_date is null then 'open_no_promised_date' when today > p.delivery_date then 'overdue_open' else 'open' end end as st,
          case when p.delivery_date is null then null
               when p.grn_n > 0 and p.lines_open = 0 then greatest(p.last_grn - p.delivery_date, 0)
               when today > p.delivery_date then today - p.delivery_date else 0 end as late,
          case when p.grn_n > 0 then p.first_grn - p.entry_date end as lead) x
     where p_supplier is null or p.sk = sname),
  lim as (select * from d order by entry_date desc, po_no limit cap)
  select (select coalesce(jsonb_agg(jsonb_build_object('entry_id', q.entry_id, 'po_no', q.po_no, 'po_date', q.entry_date, 'location_id', q.location_id, 'location', q.place, 'supplier', q.supplier,
              'promised_date', q.delivery_date, 'first_grn', q.first_grn, 'last_grn', q.last_grn, 'grn_n', q.grn_n, 'lines_open', q.lines_open, 'po_lines', q.po_lines,
              'status', q.st, 'days_late', q.late, 'lead_days', q.lead) order by q.entry_date desc, q.po_no), '[]'::jsonb) from lim q),
         (select coalesce(jsonb_agg(jsonb_build_object('supplier', z.nm, 'pos', z.n, 'received_complete', z.rc, 'on_time', z.ot, 'late', z.lt,
              'on_time_pct', case when z.ot + z.lt > 0 then round(z.ot::numeric / (z.ot + z.lt) * 100, 1) end,
              'avg_days_late', z.avgl, 'avg_lead_days', z.avgd, 'overdue_open', z.ov, 'partial', z.pa, 'promised_date_not_captured', z.nd) order by z.nm), '[]'::jsonb)
            from (select coalesce(supplier, '-') as nm, count(*) as n, count(*) filter (where st in ('on_time', 'late', 'received_no_promised_date')) as rc,
                         count(*) filter (where st = 'on_time') as ot, count(*) filter (where st = 'late') as lt,
                         round(avg(late) filter (where st = 'late'), 1) as avgl, round(avg(lead) filter (where lead is not null), 1) as avgd,
                         count(*) filter (where st in ('overdue_open', 'partial_overdue')) as ov, count(*) filter (where st like 'partial%') as pa,
                         count(*) filter (where st like '%no_promised_date') as nd
                    from d group by coalesce(supplier, '-')) z),
         (select count(*) from d)
    into rows_, summ, npo;
  return jsonb_build_object('from', r.f, 'to', r.t, 'rows', rows_, 'summary', summ, 'truncated', npo > cap,
    'basis', 'paper purchase orders (06-3) against goods received notes (04-1) carrying the same PO number; purchase bills carry no PO link, so they are not part of this report');
end $$;

-- ---------- privileges ----------
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_rb3_locs', '_rb3_range', '_rb3_purch_ok') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace
           and p.proname in ('supplier_returns_report', 'purch_price_variance', 'supplier_rejection_rate', 'supplier_dependency', 'supplier_delivery_perf') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';

-- ===================== phase436.sql =====================
-- Phase 436 (bos436) - RPT-B3: AUDIT LINE FOR THE CSV EXPORT OF THE NEW REPORTS.
-- Paste after phase435. Paste-twice safe. Earlier phase files are not edited. log_page_export (phase13) accepts only the day book and the salary report, so the new reports get their own
-- function with the SAME rule: the owner or a holder of the export right (export_data), plus the right to read the report itself. The screen calls it BEFORE it builds the file; a refusal
-- means no file. One audit_log line per export: who, what, how many rows, which filters.
--   keys: trace, recall, quality_checks, transfer_damage, stockout, yield, shelf_life            (stock / quality report right, recall_manage, stockout_log)
--         supplier_returns, rejection, dependency, delivery, item_suppliers        (purchase report right; rejection also the quality right)
--         price_variance, agreed_prices                                            (purchase report right AND the cost right: they show prices)

do $g$ begin
  if to_regprocedure('public._rb3_purch_ok()') is null then raise exception 'phase436 needs phase435 first'; end if;
end $g$;

create or replace function public.rb3_log_export(p_key text, p_kind text, p_filters jsonb, p_rows int) returns void
language plpgsql security definer set search_path = public as $$
declare sid text; f jsonb := coalesce(p_filters, '{}'::jsonb); ok boolean;
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_grant('export_data')) then raise exception 'not allowed'; end if;
  if p_key is null or p_key not in ('trace', 'recall', 'quality_checks', 'transfer_damage', 'stockout', 'yield', 'shelf_life', 'supplier_returns', 'rejection', 'dependency', 'delivery', 'item_suppliers', 'price_variance', 'agreed_prices') then
    raise exception 'unknown_report';
  end if;
  ok := case
    when p_key in ('trace', 'recall', 'quality_checks', 'transfer_damage', 'yield', 'shelf_life') then public.is_owner() or public.rpt_access('stock') or public.rpt_access('quality') or public.has_grant('recall_manage')
    when p_key = 'stockout' then public.is_owner() or public.rpt_access('stock') or exists (select 1 from public.locations l where public.can_loc(l.id) and public.has_grant('stockout_log', l.id))
    when p_key = 'rejection' then public.is_owner() or public.rpt_access('purchase') or public.rpt_access('quality')
    when p_key in ('supplier_returns', 'dependency', 'delivery', 'item_suppliers') then public.is_owner() or public.rpt_access('purchase')
    else public.is_owner() or (public.rpt_access('purchase') and public.rpt_cost_ok()) or public.has_grant('supplier_terms_manage')
  end;
  if not coalesce(ok, false) then raise exception 'not allowed'; end if;
  if p_kind is null or lower(p_kind) !~ '^[a-z0-9_]{1,20}$' then raise exception 'bad_kind'; end if;
  if length(f::text) > 4000 then f := jsonb_build_object('truncated', true); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'export', 'report', p_key, jsonb_build_object('kind', lower(p_kind), 'rows', least(greatest(coalesce(p_rows, 0), 0), 100000000), 'filters', f));
end $$;

revoke all on function public.rb3_log_export(text, text, jsonb, int) from public, anon;
grant execute on function public.rb3_log_export(text, text, jsonb, int) to authenticated;

notify pgrst, 'reload schema';

-- ===================== phase440.sql =====================
-- Phase 440 (bos440) - REPORT HONESTY, part 1 (package RPT-C1, block R1). Paste AFTER phase99 (the last Wave 1 phase). Paste-twice safe. Earlier phase files are not edited.
-- WHY (docs/REPORTS_AUDIT_3.md F1, F2, F4): the hub report engine turns "not captured" into 0 in its totals, shows a profit number even when expenses, salary or fixed cost were never
--      captured, calls the management profit a plain "Profit & loss" without saying it is not the books' profit, and the sales reports do not say that they are before returns.
-- WHAT THIS FILE DOES (nothing here changes a stored record or a journal; with every setting at its default the ONLY change to an existing figure is that a total of "nothing captured" is
--      empty instead of 0 - proved by tests/sql/c1_before_after.sh)
--   1. report_run3 (engine 3 totals): a total over a column in which NO row has a value is now null ("not captured"), no longer 0. A column with some values still adds them up. (text patch, marker bos440)
--   2. L1 / L3 (profit and loss by month and shop / shop comparison): new key profit_complete on every row; new setting report_profit_blank_on (default OFF = today's profit number):
--      when ON, a profit whose expenses, salary, fixed cost or cost of goods were not captured is null ("not captured") instead of a number that leaves the missing part out.
--      The two reports are renamed "... (management view)". (text patch, marker bos440)
--   3. report_notes(key, filters, columns): ONE read-only function that returns the notices (basis lines) for a hub report: management view with a link to Profit check and the salary / expense /
--      returns basis, what is missing, the returns line for the sales reports, the expense basis. The list of notices per report is the table report_notice_topics; a topic is a function
--      _c1_n_<topic>(key, from, to, places, filters, columns). Phase 441 adds its topics the same way. Nothing in the report engines is called for this: web/reportnotes.js asks for it.
-- NOT DONE here (phase 441): attendance, compliance, RFM, lapsed, cash short. Not touched at all: engine-1 sales functions (another package adds returns columns there).
-- !! Re-pasting phase 24 or 27 or 72 or 78 or 79 removes the bos440 patches: paste this file again.

do $g$ begin
  if to_regprocedure('public._i1_apply_hooks()') is null then raise exception 'phase440 needs phase99 (and 8 to 98) first'; end if;
  if to_regprocedure('public.report_run3(text,jsonb,text,text,integer)') is null or to_regclass('public.report_defs3') is null
     or to_regprocedure('public._p27_pl(date,date,integer[])') is null or to_regprocedure('public._w1d_view()') is null then
    raise exception 'phase440 needs the report engine and the profit functions of phases 24, 27 and 92';
  end if;
end $g$;

create or replace function public._c1_p440_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- generic exact-text patch (the phase92 _w1d_patch idea with this package's markers bos440 .. bos449 (a letter after the number tells two patches of one function apart)). A missing or doubled site STOPS the paste; the marker makes the second paste a no-op ----------
create or replace function public._c1_patch(p_fn regprocedure, p_marker text, p_pairs text[]) returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int; n int;
begin
  if p_marker is null or p_marker !~ '^bos44[0-9][a-z]?$' then raise exception 'bad_marker'; end if;
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    n := (length(def) - length(replace(def, p_pairs[i], ''))) / length(p_pairs[i]);
    if n = 0 then raise exception '% patch site not found in %: %', p_marker, p_fn::text, left(p_pairs[i], 90); end if;
    if n > 1 then raise exception '% patch site is not unique in %: %', p_marker, p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception '% patch of % carries no marker', p_marker, p_fn::text; end if;
  execute def;
  return true;
end $$;
-- the same, for a longer piece: replaces the text from p_start up to (not including) p_end by p_new. Both anchors must exist once, in this order.
create or replace function public._c1_patch_span(p_fn regprocedure, p_marker text, p_start text, p_end text, p_new text) returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); a int; b int;
begin
  if p_marker is null or p_marker !~ '^bos44[0-9][a-z]?$' then raise exception 'bad_marker'; end if;
  if position(p_marker in def) > 0 then return false; end if;
  a := position(p_start in def);
  if a = 0 then raise exception '% patch start not found in %: %', p_marker, p_fn::text, left(p_start, 90); end if;
  if position(p_start in substr(def, a + 1)) > 0 then raise exception '% patch start is not unique in %: %', p_marker, p_fn::text, left(p_start, 90); end if;
  b := position(p_end in substr(def, a + length(p_start)));
  if b = 0 then raise exception '% patch end not found in %: %', p_marker, p_fn::text, left(p_end, 90); end if;
  b := a + length(p_start) + b - 1;
  def := substr(def, 1, a - 1) || p_new || substr(def, b);
  if position(p_marker in def) = 0 then raise exception '% patch of % carries no marker', p_marker, p_fn::text; end if;
  execute def;
  return true;
end $$;
revoke all on function public._c1_patch(regprocedure, text, text[]), public._c1_patch_span(regprocedure, text, text, text, text) from public, anon, authenticated;

-- ---------- setting (rules, module reports). Default OFF = today's profit number. ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('report_profit_blank_on', 'reports', 'switch', 'false', null, null, null, null,
  'লাভ-ক্ষতি রিপোর্টে তথ্য না থাকলে "সংগ্রহ হয়নি" দেখাও', 'Profit report-এ তথ্য না থাকলে "not captured" দেখাও', 'Profit shows "not captured" when a part of it is missing',
  'বন্ধ থাকলে লাভের সংখ্যা আগের মতোই থাকে (যে অংশের তথ্য নেই সেটি বাদ দিয়ে)। চালু করলে খরচ, বেতন, স্থির খরচ বা মালের খরচের তথ্য না থাকা সারিতে লাভের ঘরে "সংগ্রহ হয়নি" দেখায়।',
  'Off রাখলে profit-এর সংখ্যা আগের মতোই থাকে (যে অংশের data নেই সেটি বাদ দিয়ে)। On করলে খরচ, বেতন, স্থির খরচ বা মালের খরচের data না থাকা row-এ profit ঘরে "not captured" দেখায়।',
  'Off keeps the profit number exactly as it is today (it leaves the missing part out). On shows "not captured" instead of a profit on every row where expenses, salary, fixed cost or cost of goods were not captured.', 810)
on conflict (key) do nothing;

-- ---------- 1. engine 3 totals: nothing captured is null, never 0 ----------
select public._c1_patch('public.report_run3(text,jsonb,text,text,integer)'::regprocedure, 'bos440', array[
  $o$targs := targs || format('%L, round(coalesce(sum((r ->> %L)::numeric), 0), 4), ', k, k);$o$,
  $n$targs := targs || format('%L, case when count(r ->> %L) = 0 then null else round(sum((r ->> %L)::numeric), 4) end, ', k, k, k);   /* bos440: a column with no value at all is "not captured" (null), not 0 */$n$]);

-- ---------- 2. L1 / L3: profit_complete on every row, profit blank when asked and a part is missing ----------
select public._c1_patch('public._r3q_l1_pnl(date,date,integer[],jsonb)'::regprocedure, 'bos440', array[
  $o$'profit', round(p.o_net - p.o_cogs - coalesce(p.o_exp, 0) - coalesce(p.o_sal, 0) - coalesce(p.o_fixed, 0), 2),$o$,
  $n$'profit', case when public.rule_on('report_profit_blank_on') /* bos440 */ and (p.o_exp is null or p.o_sal is null or p.o_fixed is null or (p.o_net > 0 and p.o_costed < p.o_net)) then null
                    else round(p.o_net - p.o_cogs - coalesce(p.o_exp, 0) - coalesce(p.o_sal, 0) - coalesce(p.o_fixed, 0), 2) end,
    'profit_complete', not (p.o_exp is null or p.o_sal is null or p.o_fixed is null or (p.o_net > 0 and p.o_costed < p.o_net)),$n$]);
select public._c1_patch('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)'::regprocedure, 'bos440', array[
  $o$'profit', round(a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0), 2),$o$,
  $n$'profit', case when public.rule_on('report_profit_blank_on') /* bos440 */ and (a.ex is null or a.sal is null or a.fx is null or (a.net > 0 and a.costed < a.net)) then null
                    else round(a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0), 2) end,
    'profit_complete', not (a.ex is null or a.sal is null or a.fx is null or (a.net > 0 and a.costed < a.net)),$n$,
  $o$'profit_pct', case when a.net > 0 then round(100 * (a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0)) / a.net, 2) end,$o$,
  $n$'profit_pct', case when a.net > 0 and not (public.rule_on('report_profit_blank_on') and (a.ex is null or a.sal is null or a.fx is null or a.costed < a.net)) then round(100 * (a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0)) / a.net, 2) end,$n$]);

-- the two P&L reports say what they are
update public.report_defs3
   set name_en = name_en || ' (management view)', name_bn = name_bn || ' (ম্যানেজমেন্ট ভিউ)', name_mix = coalesce(name_mix, name_bn) || ' (management view)'
 where key in ('l1_pnl', 'l3_shop_pnl') and name_en not like '%(management view)%';

-- ---------- 3. notices (basis lines) for hub reports ----------
create table if not exists public.report_notice_topics (
  report_key text not null,
  topic text not null check (topic ~ '^[a-z0-9_]{1,40}$'),
  sort int not null default 100,
  primary key (report_key, topic)
);
alter table public.report_notice_topics enable row level security;
revoke all on public.report_notice_topics from public, anon, authenticated;

create or replace function public._c1_money(p numeric) returns text language sql immutable set search_path = public as $$
  select case when p is null then '-' else to_char(round(p, 2), 'FM999,999,999,990.00') end $$;

-- the period of a hub report, worked out as the report engines do (preset, or from / to, or this month so far). d1 is null when the preset is unknown.
create or replace function public._c1_period(p_flt jsonb, out d1 date, out d2 date) language plpgsql stable security definer set search_path = public as $$
declare flt jsonb := case when p_flt is not null and jsonb_typeof(p_flt) = 'object' then p_flt else '{}'::jsonb end; today date := (now() at time zone 'Asia/Dhaka')::date; pr jsonb; preset text;
begin
  preset := flt ->> 'preset';
  if preset is not null then
    pr := public.report_presets() -> preset;
    if pr is null or jsonb_typeof(pr) = 'null' then return; end if;
    d1 := (pr ->> 'from')::date; d2 := (pr ->> 'to')::date; return;
  end if;
  d1 := public.rpt_date(flt ->> 'from'); d2 := public.rpt_date(flt ->> 'to');
  if d1 is null and d2 is null then d1 := date_trunc('month', today)::date; d2 := today;
  elsif d1 is null then d1 := d2; elsif d2 is null then d2 := today; end if;
end $$;

-- may this person open this report? true / false; null = no such report (the three report engines are asked in turn)
create or replace function public._c1_report_ok(p_key text) returns boolean language plpgsql stable security definer set search_path = public as $$
declare d public.report_defs3; g jsonb;
begin
  if not public.is_active() then return false; end if;
  g := public.rpt_def(p_key);
  if g is not null then return public.rpt_access(g ->> 'group'); end if;
  if public._r2_def(p_key) is not null then return public._r2_ok(p_key); end if;
  select * into d from public.report_defs3 where key = p_key and is_active;
  if found then return public._r3_ok(d); end if;
  return null;
end $$;

-- topic: management_view. The P&L reports are the management view (daily records), not the books.
create or replace function public._c1_n_mgmt_view(p_key text, d1 date, d2 date, eff int[], flt jsonb, cols text[]) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare src text := coalesce(public.rule_txt('report_salary_source'), 'legacy'); acc boolean := public.rule_on('payroll_accrual_on'); net boolean := coalesce(public.rule_on('reports_net_of_returns'), true);
  one boolean := public.rule_on('profit_one_number_on'); cnt text := coalesce(public.rule_txt('expense_count_on'), 'as_today'); wf text := coalesce(public.rule_txt('d_wallet_fee_treatment'), 'separate_expense');
  b jsonb := '[]'::jsonb; ve text; vb text;
begin
  -- salary
  if src = 'app_first' then
    b := b || jsonb_build_object('code', 'salary', 'text_en', 'Salary: from the payroll runs that are counted; the salary sheet (02-2) is used only for months and places that have no counted run.',
      'text_bn', 'বেতন: গণনায় ধরা পে-রোল রান থেকে; যে মাস বা জায়গায় রান নেই সেখানে শুধু বেতন শিট (০২-২)।');
  elsif acc then
    b := b || jsonb_build_object('code', 'salary', 'text_en', 'Salary: salary sheets (02-2) that are not copies of an app payroll run, plus approved or paid payroll runs (payroll accrual is on).',
      'text_bn', 'বেতন: অ্যাপের পে-রোল রানের কপি নয় এমন বেতন শিট (০২-২) এবং অনুমোদিত বা পরিশোধিত পে-রোল রান (পে-রোল অ্যাক্রুয়াল চালু)।');
  else
    b := b || jsonb_build_object('code', 'salary', 'text_en', 'Salary: taken from the salary sheets (02-2). A payroll run paid in the app is not used here, so this can differ from the money actually paid.',
      'text_bn', 'বেতন: বেতন শিট (০২-২) থেকে। অ্যাপে পরিশোধ করা পে-রোল রান এখানে ধরা হয় না, তাই আসলে দেওয়া টাকার সাথে ভিন্ন হতে পারে।');
  end if;
  -- expenses
  ve := case cnt when 'approved' then 'approved' when 'submitted' then 'submitted or approved' else 'submitted or approved' end;
  vb := case cnt when 'approved' then 'অনুমোদিত' else 'জমা দেওয়া বা অনুমোদিত' end;
  b := b || jsonb_build_object('code', 'expenses',
    'text_en', 'Expenses: expense vouchers (10-2) that are ' || ve || ', plus quick expenses' || case when wf = 'separate_expense' then ' and wallet fees' else '' end || '. '
               || case when one then 'Wasted stock, stock count shortage, goods lost in transit, cash short and running costs paid by supplier bill are counted as the Profit check settings say.'
                       else 'Wasted stock, stock count shortage, goods lost in transit, cash short and running costs paid by supplier bill are NOT in this profit (they are in the journal).' end,
    'text_bn', 'খরচ: ' || vb || ' ব্যয় ভাউচার (১০-২), সাথে দ্রুত খরচ' || case when wf = 'separate_expense' then ' ও ওয়ালেট ফি' else '' end || '। '
               || case when one then 'নষ্ট মাল, গণনায় কম, পথে হারানো মাল, ক্যাশ কম ও সাপ্লায়ার বিলে দেওয়া চলতি খরচ Profit check-এর সেটিং অনুযায়ী ধরা হয়।'
                       else 'নষ্ট মাল, গণনায় কম, পথে হারানো মাল, ক্যাশ কম ও সাপ্লায়ার বিলে দেওয়া চলতি খরচ এই লাভে নেই (এগুলো খাতায় আছে)।' end);
  -- returns
  b := b || jsonb_build_object('code', 'returns', 'text_en', case when net then 'Sales are net of sale returns.' else 'Sale returns are NOT taken off the sales (the returns setting is off).' end,
    'text_bn', case when net then 'বিক্রি থেকে বিক্রি-ফেরত বাদ দেওয়া হয়েছে।' else 'বিক্রি থেকে বিক্রি-ফেরত বাদ দেওয়া হয়নি (ফেরতের সেটিং বন্ধ)।' end);
  return jsonb_build_array(jsonb_build_object('code', 'management_view', 'level', 'info',
    'text_en', 'Management view, not the books. Profit here = net sales - cost of goods - expenses - salary - fixed cost, worked out from the daily records. The journal profit can differ. Profit check shows the difference line by line.',
    'text_bn', 'ম্যানেজমেন্ট ভিউ, হিসাবের খাতা নয়। এখানে লাভ = নিট বিক্রি - মালের খরচ - খরচ - বেতন - স্থির খরচ, দৈনিক রেকর্ড থেকে। খাতার (জার্নাল) লাভ ভিন্ন হতে পারে। Profit check পার্থক্য লাইন ধরে দেখায়।',
    'link', jsonb_build_object('route', 'profitcheck', 'label_en', 'Open Profit check', 'label_bn', 'Profit check খুলুন'), 'basis', b));
end $$;

-- topic: profit_gaps. Which parts were not captured (per month and place for L1, per place for the others).
create or replace function public._c1_n_profit_gaps(p_key text, d1 date, d2 date, eff int[], flt jsonb, cols text[]) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare n int; ne int; ns int; nf int; nc int; nany int; blank boolean := public.rule_on('report_profit_blank_on'); parts_en text[] := '{}'; parts_bn text[] := '{}'; en text; bn text; lv text := 'warn';
begin
  if p_key = 'l1_pnl' then
    select count(*), count(*) filter (where o_exp is null), count(*) filter (where o_sal is null), count(*) filter (where o_fixed is null), count(*) filter (where o_net > 0 and o_costed < o_net),
           count(*) filter (where o_exp is null or o_sal is null or o_fixed is null or (o_net > 0 and o_costed < o_net))
      into n, ne, ns, nf, nc, nany from public._p27_pl(d1, d2, eff);
  else
    select count(*), count(*) filter (where ex is null), count(*) filter (where sal is null), count(*) filter (where fx is null), count(*) filter (where net > 0 and costed < net),
           count(*) filter (where ex is null or sal is null or fx is null or (net > 0 and costed < net))
      into n, ne, ns, nf, nc, nany
      from (select o_loc, sum(o_net) net, sum(o_costed) costed, sum(o_exp) ex, sum(o_sal) sal, sum(o_fixed) fx from public._p27_pl(d1, d2, eff) group by o_loc) z;
  end if;
  if n = 0 then return '[]'::jsonb; end if;
  if p_key = 'l5_breakeven' then
    if nf = 0 then return '[]'::jsonb; end if;
    return jsonb_build_array(jsonb_build_object('code', 'fixed_cost_missing', 'level', 'warn', 'data', jsonb_build_object('places', nf, 'of', n),
      'text_en', 'Fixed cost per month is not set for ' || nf || ' of ' || n || ' place(s): break-even is not calculated for them and shows "not captured". The totals leave them out.',
      'text_bn', n || 'টির মধ্যে ' || nf || 'টি জায়গার মাসিক স্থির খরচ দেওয়া নেই: সেগুলোর ব্রেক-ইভেন হিসাব হয়নি, "সংগ্রহ হয়নি" দেখাচ্ছে। মোটে এগুলো নেই।'));
  elsif p_key = 't4_staff_cost_ratio' then
    if ns = 0 then return '[]'::jsonb; end if;
    return jsonb_build_array(jsonb_build_object('code', 'salary_missing', 'level', 'warn', 'data', jsonb_build_object('places', ns, 'of', n),
      'text_en', 'Salary is not captured for ' || ns || ' of ' || n || ' place(s): their ratio shows "not captured". The totals leave them out.',
      'text_bn', n || 'টির মধ্যে ' || ns || 'টি জায়গার বেতনের তথ্য নেই: সেগুলোর অনুপাত "সংগ্রহ হয়নি" দেখাচ্ছে। মোটে এগুলো নেই।'));
  end if;
  if nany = 0 then return '[]'::jsonb; end if;
  if ne > 0 then parts_en := parts_en || (ne || ' without expenses'); parts_bn := parts_bn || (ne || 'টিতে খরচ নেই'); end if;
  if ns > 0 then parts_en := parts_en || (ns || ' without salary'); parts_bn := parts_bn || (ns || 'টিতে বেতন নেই'); end if;
  if nf > 0 then parts_en := parts_en || (nf || ' without fixed cost'); parts_bn := parts_bn || (nf || 'টিতে স্থির খরচ নেই'); end if;
  if nc > 0 then parts_en := parts_en || (nc || ' with sales that have no known cost'); parts_bn := parts_bn || (nc || 'টিতে খরচ অজানা বিক্রি আছে'); end if;
  en := nany || ' of ' || n || ' row(s) are incomplete: ' || array_to_string(parts_en, ', ') || '. '
        || case when blank then 'The setting "Profit shows not captured..." is ON, so their profit shows "not captured".' else 'Their profit leaves the missing part out. Switch on "Profit shows not captured..." in the settings to show "not captured" there instead.' end;
  bn := n || 'টি সারির মধ্যে ' || nany || 'টি অসম্পূর্ণ: ' || array_to_string(parts_bn, ', ') || '। '
        || case when blank then 'সেটিং "তথ্য না থাকলে সংগ্রহ হয়নি দেখাও" চালু, তাই এগুলোর লাভে "সংগ্রহ হয়নি" দেখাচ্ছে।' else 'এগুলোর লাভে না থাকা অংশ বাদ গেছে। সেখানে "সংগ্রহ হয়নি" দেখাতে সেটিং "তথ্য না থাকলে সংগ্রহ হয়নি দেখাও" চালু করুন।' end;
  return jsonb_build_array(jsonb_build_object('code', 'profit_incomplete', 'level', lv, 'data', jsonb_build_object('rows', n, 'incomplete', nany, 'no_expenses', ne, 'no_salary', ns, 'no_fixed', nf, 'uncosted', nc, 'blank_on', blank),
    'text_en', en, 'text_bn', bn));
end $$;

-- topic: returns_line. The hub sales reports count sales before sale returns: say so and show the returns of the same period and places.
create or replace function public._c1_n_returns_line(p_key text, d1 date, d2 date, eff int[], flt jsonb, cols text[]) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare n int; amt numeric; shown boolean := coalesce(cols && array['returns', 'return_amount', 'returns_amount', 'returns_total', 'net_after_returns'], false); narrow boolean; en text; bn text;
begin
  select count(*), coalesce(sum(r.amount), 0) into n, amt from public.sale_returns r
   where r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and r.location_id = any (eff);
  narrow := flt ?| array['items', 'categories', 'customer', 'staff', 'modes', 'sale_type'];
  if n = 0 then
    en := 'No sale return was recorded in this period and these places.'; bn := 'এই সময়ে ও এই জায়গাগুলোতে কোনো বিক্রি-ফেরত নেই।';
  else
    en := 'Sale returns in this period: ' || n || ' return(s), ' || public._c1_money(amt) || '. '
          || case when shown then 'They are also in the returns column of this report.' else 'The figures in this report are before returns: take the returns off to get sales after returns.' end;
    bn := 'এই সময়ের বিক্রি-ফেরত: ' || n || 'টি, ৳ ' || public._c1_money(amt) || '। '
          || case when shown then 'রিপোর্টের ফেরতের কলামেও আছে।' else 'এই রিপোর্টের সংখ্যা ফেরতের আগের: ফেরত বাদ দিলে ফেরতের পরের বিক্রি পাবেন।' end;
  end if;
  if narrow then
    en := en || ' The returns line is not narrowed by the item, customer, staff or payment filters.';
    bn := bn || ' আইটেম, গ্রাহক, স্টাফ বা পেমেন্টের ফিল্টারে ফেরতের লাইন ছোট হয় না।';
  end if;
  return jsonb_build_array(jsonb_build_object('code', 'returns_line', 'level', 'info', 'data', jsonb_build_object('count', n, 'amount', amt, 'in_report', shown),
    'text_en', en, 'text_bn', bn, 'link', jsonb_build_object('route', 'salereturn', 'label_en', 'Sale returns', 'label_bn', 'বিক্রি ফেরত')));
end $$;

-- topic: expense_basis. Three expense totals exist for the same period; say which one this report is and where the whole list is.
create or replace function public._c1_n_expense_basis(p_key text, d1 date, d2 date, eff int[], flt jsonb, cols text[]) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare par boolean := public.rule_on('report_expense_parity_on'); cnt text := coalesce(public.rule_txt('expense_count_on'), 'as_today'); en text; bn text;
begin
  if p_key = 'expense_by_head' then
    en := 'This report counts expense vouchers (10-2) that are ' || case cnt when 'approved' then 'approved' else 'submitted or approved' end || '. Quick expenses are '
          || case when par then 'counted (setting on)' else 'NOT counted (setting off)' end || '. Bank charges, wallet fees and marketing (18-1) are not counted.';
    bn := 'এই রিপোর্টে ' || case cnt when 'approved' then 'অনুমোদিত' else 'জমা দেওয়া বা অনুমোদিত' end || ' ব্যয় ভাউচার (১০-২) ধরা হয়। দ্রুত খরচ '
          || case when par then 'ধরা হয় (সেটিং চালু)' else 'ধরা হয় না (সেটিং বন্ধ)' end || '। ব্যাংক চার্জ, ওয়ালেট ফি ও মার্কেটিং (১৮-১) ধরা হয় না।';
  elsif p_key = 'e3_weak_control' then
    en := 'This control report checks expense vouchers (10-2)' || case when par then ' and quick expenses (setting on).' else '; quick expenses are not in it (setting off).' end;
    bn := 'এই কন্ট্রোল রিপোর্ট ব্যয় ভাউচার (১০-২) দেখে' || case when par then ' ও দ্রুত খরচ (সেটিং চালু)।' else '; দ্রুত খরচ এতে নেই (সেটিং বন্ধ)।' end;
  else
    en := 'This trend counts expense vouchers (10-2) and quick expenses, the same as the profit report. The expense report and the journal can show other totals.';
    bn := 'এই ধারায় ব্যয় ভাউচার (১০-২) ও দ্রুত খরচ ধরা হয়, লাভের রিপোর্টের মতোই। খরচ রিপোর্ট ও জার্নালের মোট ভিন্ন হতে পারে।';
  end if;
  return jsonb_build_array(jsonb_build_object('code', 'expense_basis', 'level', 'info', 'text_en', en || ' The Expense register lists every voucher and shows why the totals differ.',
    'text_bn', bn || ' খরচ রেজিস্টার প্রতিটি ভাউচার দেখায় এবং মোট কেন ভিন্ন তা বলে।',
    'link', jsonb_build_object('route', 'expenseregister', 'label_en', 'Open the Expense register', 'label_bn', 'খরচ রেজিস্টার খুলুন')));
end $$;

insert into public.report_notice_topics (report_key, topic, sort) values
 ('l1_pnl', 'mgmt_view', 10), ('l3_shop_pnl', 'mgmt_view', 10), ('l4_owner_sheet', 'mgmt_view', 10), ('l5_breakeven', 'mgmt_view', 10), ('t4_staff_cost_ratio', 'mgmt_view', 10),
 ('l1_pnl', 'profit_gaps', 20), ('l3_shop_pnl', 'profit_gaps', 20), ('l5_breakeven', 'profit_gaps', 20), ('t4_staff_cost_ratio', 'profit_gaps', 20),
 ('sales_summary', 'returns_line', 10), ('sales_trend', 'returns_line', 10), ('sales_combined', 'returns_line', 10), ('item_sales', 'returns_line', 10), ('category_sales', 'returns_line', 10),
 ('hour_weekday', 'returns_line', 10), ('retail_wholesale', 'returns_line', 10), ('receipt_register', 'returns_line', 10),
 ('expense_by_head', 'expense_basis', 10), ('e2_expense_trend', 'expense_basis', 10), ('e3_weak_control', 'expense_basis', 10)
on conflict do nothing;

-- the one function the browser calls. Read only. Same right as the report itself. Reports without a topic answer [].
create or replace function public.report_notes(p_key text, p_filters jsonb default '{}'::jsonb, p_cols text[] default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare ok boolean; t record; p record; eff int[]; flt jsonb; out_ jsonb := '[]'::jsonb; r jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  ok := public._c1_report_ok(p_key);
  if ok is null then raise exception 'unknown_report'; end if;
  if not ok then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.report_notice_topics where report_key = p_key) then return out_; end if;
  flt := case when p_filters is not null and jsonb_typeof(p_filters) = 'object' then p_filters else '{}'::jsonb end;
  select * into p from public._c1_period(flt);
  if p.d1 is null then return out_; end if;
  eff := public._r2_locs(flt);
  for t in select topic from public.report_notice_topics where report_key = p_key order by sort, topic loop
    if to_regprocedure('public._c1_n_' || t.topic || '(text,date,date,integer[],jsonb,text[])') is null then continue; end if;
    execute format('select public._c1_n_%s($1, $2, $3, $4, $5, $6)', t.topic) into r using p_key, p.d1, p.d2, eff, flt, p_cols;
    if r is not null and jsonb_typeof(r) = 'array' then out_ := out_ || r; end if;
  end loop;
  return out_;
end $$;

-- closed to browsers: everything with an underscore; open: report_notes (signed in, same right as the report)
revoke all on function public._c1_money(numeric), public._c1_period(jsonb), public._c1_report_ok(text),
  public._c1_n_mgmt_view(text, date, date, integer[], jsonb, text[]), public._c1_n_profit_gaps(text, date, date, integer[], jsonb, text[]),
  public._c1_n_returns_line(text, date, date, integer[], jsonb, text[]), public._c1_n_expense_basis(text, date, date, integer[], jsonb, text[]) from public, anon, authenticated;
revoke all on function public.report_notes(text, jsonb, text[]) from public, anon;
grant execute on function public.report_notes(text, jsonb, text[]) to authenticated;
notify pgrst, 'reload schema';

