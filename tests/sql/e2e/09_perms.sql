\echo == 09 permissions: cost secrecy, bot, conflicts, show/hide/locked
select tt.as(:'o');
drop table if exists tt.ctx; create table tt.ctx (k text primary key, v text); grant select on tt.ctx to authenticated;
insert into tt.ctx select 'rcp', id::text from recipes limit 1;
insert into tt.ctx select 'pbid', id::text from purchase_bills order by created_at limit 1;
insert into tt.ctx select 'sale', id::text from sales order by receipt limit 1;
insert into tt.ctx select 'run', id::text from production_runs limit 1;
insert into tt.ctx select 'lc', id::text from landed_costs limit 1;
insert into tt.ctx select 'oo', id::text from online_orders limit 1;
insert into tt.ctx select 'sup', id::text from suppliers order by created_at limit 1;
insert into tt.ctx select 'cake', id::text from items where code='FG-CAKE';
drop table if exists tt.sweep; create table tt.sweep (who text, fn text, args text, leaked text, ok boolean, err text);
grant all on tt.sweep to authenticated;
create or replace function tt.cx(p text) returns text language sql stable as $$ select v from tt.ctx where k = p $$;
grant execute on function tt.cx(text) to authenticated;
create or replace function tt.sweep_run(p_who uuid, p_label text) returns void language plpgsql as $f$
declare r record; a text; res text; fp text := '42\.73|57\.73|41\.33|477\.34|954\.68|1084\.9|282\.04|942\.08|11922\.6|3\.150000|4\.7733'; i int; arglist text[]; nm text; ty text; v text; okk boolean; er text; lk text;
begin
  perform set_config('request.jwt.claim.sub', p_who::text, false);
  for r in select p.oid, p.proname, p.pronargs, p.proargnames, p.proargtypes from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname='public' and p.proname !~ '^_' and p.prokind='f' and has_function_privilege('authenticated', p.oid, 'execute')
              and p.proname not in ('report_fact_rebuild','backup_stock_ledger','backup_stock_balance') order by p.proname, p.oid loop
    arglist := '{}';
    for i in 1..r.pronargs loop
      nm := coalesce(r.proargnames[i], ''); ty := (select typname from pg_type where oid = r.proargtypes[i-1]);
      v := 'null';
      if ty = 'uuid' then
        v := case when nm ~ 'item' then format('%L', tt.cx('cake')) when nm ~ 'recipe' then format('%L', tt.cx('rcp')) when nm ~ 'sale' then format('%L', tt.cx('sale')) when nm ~ 'supplier' then format('%L', tt.cx('sup'))
                  when nm ~ 'bill' then format('%L', tt.cx('pbid')) when nm ~ 'run' then format('%L', tt.cx('run')) when nm ~ 'order' then format('%L', tt.cx('oo')) when nm ~ '(user|emp)' then format('%L', p_who::text) when nm ~ 'p_id|p_entry|p_cost' then format('%L', tt.cx('lc')) else 'null' end;
      elsif ty = 'int4' then v := case when nm ~ 'loc' then '1' when nm ~ 'limit' then '50' when nm ~ 'days' then '30' when nm ~ 'page' then '1' else 'null' end;
      elsif ty = 'int8' then v := case when nm ~ 'limit' then '50' else 'null' end;
      elsif ty = 'date' then v := case when nm ~ 'from' then format('%L', tt.today()-10) else format('%L', tt.today()) end;
      elsif ty = 'text' then v := case when nm ~ 'key' then '''item_sales''' when nm ~ 'kind' then '''purchase''' when nm ~ 'p_ref' then format('%L', tt.cx('pbid')) else 'null' end;
      elsif ty = 'jsonb' then v := case when nm ~ 'filters' then '''{}''::jsonb' else 'null' end;
      end if;
      arglist := arglist || (v || '::' || format_type(r.proargtypes[i-1], null));
    end loop;
    a := array_to_string(arglist, ',');
    okk := false; er := null; lk := null; res := null;
    begin
      execute format('select coalesce(string_agg(to_jsonb(x)::text, '' ''), '''') from public.%I(%s) x', r.proname, a) into res;
      okk := true; lk := (regexp_match(res, '(.{0,30}(' || fp || ').{0,20})'))[1];
      raise exception 'e2e_rollback';
    exception when others then
      if sqlerrm <> 'e2e_rollback' then okk := false; er := left(sqlerrm, 80); end if;
    end;
    insert into tt.sweep values (p_label, r.proname || '(' || r.pronargs || ')', left(a,200), lk, okk, er);
  end loop;
end $f$;
grant execute on function tt.sweep_run(uuid, text) to authenticated;

-- table-level: any readable column with cost values?
create or replace function tt.table_sweep(p_who uuid, p_label text) returns void language plpgsql as $f$
declare t record; res text; fp text := '42\.73|57\.73|41\.33|477\.34|954\.68|282\.04|942\.08|11922\.6|3\.150000|4\.7733'; lk text; nrows bigint;
begin
  perform set_config('request.jwt.claim.sub', p_who::text, false);
  for t in select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','v','m') order by 1 loop
    begin
      execute format('select count(*), coalesce(string_agg(to_jsonb(x)::text, '' ''), '''') from public.%I x', t.relname) into nrows, res;
      lk := (regexp_match(res, '(.{0,30}(' || fp || ').{0,20})'))[1];
      insert into tt.sweep values (p_label, 'TABLE ' || t.relname, nrows::text, lk, true, null);
    exception when others then null;
    end;
  end loop;
end $f$;
grant execute on function tt.table_sweep(uuid, text) to authenticated;

set role authenticated;
select tt.sweep_run(:'sp'::uuid, 'sp');
select tt.sweep_run(:'sk'::uuid, 'sk');
select tt.sweep_run(:'bu'::uuid, 'bu');
select tt.sweep_run(:'ap'::uuid, 'ap');
select tt.sweep_run(:'bt'::uuid, 'bt');
select tt.sweep_run(:'fm'::uuid, 'fm_has_view_cost');
select tt.table_sweep(:'sp'::uuid, 'sp');
select tt.table_sweep(:'sk'::uuid, 'sk');
select tt.table_sweep(:'bu'::uuid, 'bu');
select tt.table_sweep(:'fm'::uuid, 'fm_has_view_cost');
reset role;
select tt.eq('V0 sweep: functions executed OK (sp)', (select count(*) from tt.sweep where who='sp' and ok and fn not like 'TABLE%'), (select count(*) from tt.sweep where who='sp' and ok and fn not like 'TABLE%'));
select who, count(*) filter (where ok and fn not like 'TABLE%') as fn_ok, count(*) filter (where not ok and fn not like 'TABLE%') as fn_err, count(*) filter (where fn like 'TABLE%') as tbl_read from tt.sweep group by who order by who;
select tt.eq('V1 no-cost users: RPC outputs containing cost fingerprints', 0, (select count(*) from tt.sweep where who in ('sp','sk','ap','bt') and leaked is not null and fn not like 'TABLE%'));
select tt.eq('V1 no-cost users: readable TABLE rows containing cost fingerprints', 0, (select count(*) from tt.sweep where who in ('sp','sk','bu','ap','bt') and leaked is not null and fn like 'TABLE%'));
select 'LEAK ' || who || ' ' || fn || ' :: ' || leaked from tt.sweep where who in ('sp','sk','ap','bt') and leaked is not null order by 1;
select 'NOTE purchasing role (ITEM_COST view by role seed) sees cost in ' || count(*) || ' functions' from tt.sweep where who='bu' and leaked is not null;
select 'CONTROL(view_cost holder sees cost in) ' || count(*) from tt.sweep where who='fm_has_view_cost' and leaked is not null;

\echo -- scan photo path (purchase bill photo) as a no-cost uploader
select tt.as(:'o');
select set_rule('scan_enabled','true') is null as sen \gset
select tt.as(:'sk');
select scan_create(gen_random_uuid(),'purchase_bill',1,'SCAN/1/e2e1.jpg','aabbccddeeff00112233') ->> 'id' as j1 \gset
select tt.as(:'o');
select scan_set_extracted(:'j1'::uuid, jsonb_build_object('supplier', jsonb_build_object('name','Alpha Traders'),'bill_no','B-100','total',2562.00,'lines', jsonb_build_array(jsonb_build_object('desc','Flour','qty',200,'unit','kg','unit_cost',42.7333,'item_id',tt.iid('RM-F'))))) is not null as sx \gset
select tt.as(:'sk');
select scan_get(:'j1'::uuid) as sg \gset
select tt.t('Z1 NOTE uploader (no cost right) sees the machine-read prices of the bill he photographed (design: own uploads)', (:'sg'::jsonb->>'cost_hidden')='false', 'visible to uploader', (:'sg'::jsonb->>'cost_hidden'));
insert into auth.users (id,email,raw_user_meta_data) values ('00000000-0000-0000-0000-00000000000a','keeper2@e2e.app','{"full_name":"Keeper Two"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values ('00000000-0000-0000-0000-00000000000a','storekeeper') on conflict do nothing;
insert into user_locations values ('00000000-0000-0000-0000-00000000000a',1) on conflict do nothing;
select tt.as('00000000-0000-0000-0000-00000000000a');
select tt.err('Z1 another storekeeper (no cost, not the uploader, no confirm right) cannot even open the scan', format($$select scan_get('%s'::uuid)$$, :'j1'), 'not found');
select tt.as(:'o'); select set_user_grant('00000000-0000-0000-0000-00000000000a'::uuid,'scan_confirm') is null as gsc \gset
select tt.as('00000000-0000-0000-0000-00000000000a');
select scan_get(:'j1'::uuid)::text as sg2 \gset
select tt.t('Z1 confirmer without the cost right: prices, photo path and draft hidden (cost_hidden)', (:'sg2'::jsonb->>'cost_hidden')='true' and :'sg2' !~ '42\.73|2562|SCAN/1' , 'cost_hidden', left(:'sg2',70));
select tt.err('Z1 same confirmer cannot save a review on it', format($$select scan_review_save('%s'::uuid, '{"lines":[]}'::jsonb, false)$$, :'j1'), 'not allowed');
select tt.as(:'sk');
select tt.t('Z1 scan_list has no unit_cost', not (scan_list()::text ~ 'unit_cost|42\.73'));
select scan_review_save(:'j1'::uuid, jsonb_build_object('bill_no','B-100','lines', jsonb_build_array(jsonb_build_object('desc','Flour','qty',200,'unit','kg','unit_cost',42.7333,'item_id',tt.iid('RM-F'),'decision','map'))), false) as rvs \gset
select tt.t('Z1 scan_review_save by a no-cost reviewer: result shows no cost numbers', not (:'rvs'::text ~ '42\.73'), 'no cost', left(:'rvs',120));
select tt.as(:'o');

\echo -- conflicting grants flagged
select permission_recommendations(:'bu'::uuid) as pr \gset
select tt.t('Y1 permission_recommendations flags purchase_entry + supplier_pay for the buyer', (select count(*) from jsonb_array_elements(:'pr'::jsonb->'not_recommended_combo') c where c->>'a'='purchase_entry' and c->>'b'='supplier_pay')=1, '1 combo', (select count(*)::text from jsonb_array_elements(:'pr'::jsonb->'not_recommended_combo')));
select set_user_grant(:'fm'::uuid,'price_override') is null as g_po \gset
select permission_recommendations(:'fm'::uuid) as pr2 \gset
select tt.t('Y1 view_cost + price_override flagged for the maker', (select count(*) from jsonb_array_elements(:'pr2'::jsonb->'not_recommended_combo') c where c->>'a'='view_cost' and c->>'b'='price_override')=1, '1 combo', (select count(*)::text from jsonb_array_elements(:'pr2'::jsonb->'not_recommended_combo')));
select tt.as(:'sp');
select tt.err('Y1 a non-owner cannot read another user''s recommendations', format($$select permission_recommendations('%s'::uuid)$$, :'bu'), 'not allowed');
select tt.as(:'o');

\echo -- show / hide / locked does not change grants
select md5((select coalesce(string_agg(t::text,',' order by t::text),'') from user_grants t)||(select string_agg(t::text,',' order by t::text) from role_form_perms t)||(select string_agg(t::text,',' order by t::text) from rule_grants t)||(select string_agg(t::text,',' order by t::text) from user_roles t)) as snap0 \gset
select set_option_view(:'sp'::uuid,'f:06-1','hide',gen_random_uuid()) is not null as h1 \gset
select set_option_view(:'sp'::uuid,'f:05-1','locked',gen_random_uuid()) is not null as h2 \gset
select option_views_for_user(:'sp'::uuid) as ov \gset
select md5((select coalesce(string_agg(t::text,',' order by t::text),'') from user_grants t)||(select string_agg(t::text,',' order by t::text) from role_form_perms t)||(select string_agg(t::text,',' order by t::text) from rule_grants t)||(select string_agg(t::text,',' order by t::text) from user_roles t)) as snap1 \gset
select tt.is('Y3 grants / form perms / role grants identical after hide + locked', :'snap0', :'snap1');
select tt.t('Y3 hidden/locked recorded as views only', (:'ov'::jsonb->'overrides')::text like '%06-1%', 'recorded', left((:'ov'::jsonb->'overrides')::text,100));
select tt.t('Y3 effective permission POS enter unchanged for sp', (:'ov'::jsonb->'perms'->'POS'->>'enter')='true', 'true', (:'ov'::jsonb->'perms'->'POS'->>'enter'));
select tt.as(:'sp');
select tt.t('Y3 the seller can still sell with a hidden/locked form (permission untouched)', record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":300}]',tt.iid('FG-CAKE'))::jsonb,0,'[{"mode":"cash","amount":300}]',null,null,'retail',null,false) is not null);
select tt.as(:'o');
