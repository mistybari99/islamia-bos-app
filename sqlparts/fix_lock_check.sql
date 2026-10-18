create or replace function public.lock_check(p_date date) returns void
language plpgsql security definer set search_path = public as $$
declare v text; d date;
begin
  if p_date is null or public.is_owner() then return; end if;
  v := public.rule_txt('period_closed_until');
  if v is null or v !~ '^\d{4}-\d{2}-\d{2}$' then return; end if;
  begin d := v::date; exception when others then return; end;      -- an impossible date (2026-02-30) locks nobody out
  if p_date > d then return; end if;
  if public.rule_ok('closed_period_edit', null, null, p_date, 'entry') then return; end if;
  raise exception 'period_closed';
end $$;
select public._m_patch('public.lock_check(date)'::regprocedure, array[
  $a$if public.rule_ok('closed_period_edit', null, null, p_date, 'entry') then return; end if;$a$,
  $a$if public.rule_ok('closed_period_edit', null, null, p_date, 'entry') then return; end if;
  if public._m_lock_exc(p_date) then return; end if;   -- bos87: an owner granted one-off exception (reason on record, shown in the Exceptions list)$a$]);

