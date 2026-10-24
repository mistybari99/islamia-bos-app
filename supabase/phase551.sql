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
