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
