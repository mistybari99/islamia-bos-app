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
