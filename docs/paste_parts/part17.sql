-- ============================================================================
-- FRESH part 17 of 21. Paste the WHOLE of this file into the Supabase SQL editor, press Run, wait for "Success", then paste the next part.
-- Phases in this part, in this order: phase442 phase443 phase444 phase445 phase446 phase447 phase448 phase449 phase450 phase451 phase452 phase453 phase454 phase455 phase456 phase457 phase458 phase459 phase460 phase461 phase462 phase463 phase464 phase465 phase466 phase467 phase468 phase470
-- Never paste: any *_test.sql, the phase84 / 84b / 84c TEST-PROJECT files, ALL_NEW2..ALL_NEW11*. Commit: see docs/PASTE_ORDER.md.
-- ============================================================================

-- ---------------------------------------------------------------- phase442.sql
-- Phase 442 (bos442) - EXPENSE REGISTER (package RPT-C1, block R2). Paste AFTER phase441. Paste-twice safe. New functions only: nothing that exists is edited.
-- WHY (docs/REPORTS_AUDIT_3.md F3, F8, reports 114 and 115): the same period shows three different expense totals (expense report 790, P&L and day book 1,210, journal 920 in the dry run) and no screen
--      lists the vouchers behind them; the marketing register (18-1) is read by two reports and reaches no total at all.
-- WHAT THIS FILE DOES (read only: no record and no journal line is written; no new setting; the existing settings expense_count_on, report_expense_parity_on and d_wallet_fee_treatment decide the flags)
--   expense_register(from, to, place, basis, kinds, status, limit, offset): ONE list, one line per voucher:
--      expense vouchers 10-2 (every status), quick expenses, bank charges, mobile wallet fees, and the marketing register 18-1 lines marked "not in the books".
--      Every line says whether it is counted by the expense report, by the P&L and day book, and by the journal (and whether the journal line is posted yet).
--      basis = all | report | pl | journal: the list shows only the lines that basis counts (all = every line).
--      The answer also carries the reconciliation: the three totals, and for every kind of line how much of it each total counts and why they differ.
-- Access: owner, or the report grant of the expense group (report_expense / view_reports), or the accounts view right. Places: the ones the person may see. Nothing depends on a capture switch.

do $g$ begin
  if to_regprocedure('public._c1_p441_present()') is null then raise exception 'phase442 needs phase441 first'; end if;
  if to_regclass('public.quick_expenses') is null or to_regclass('public.money_charges') is null or to_regclass('public.d_wallet_fees') is null
     or to_regprocedure('public._w1d_exp_status_ok(text,text)') is null or to_regprocedure('public._w1d_parity_on()') is null then
    raise exception 'phase442 needs the tables and functions of phases 50, 83, 87 and 93';
  end if;
end $g$;

create or replace function public._c1_p442_present() returns boolean language sql immutable as $$ select true $$;

create or replace function public._c1_exp_view() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.rpt_access('expense') or public._acct_view()) $$;

-- is there a live (not reversed) journal entry for this document?
create or replace function public._c1_je_live(p_type text, p_id text) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.journal_entries je where je.source_type = p_type and je.source_id = p_id and je.reverses_id is null
                   and not exists (select 1 from public.journal_entries r where r.reverses_id = je.id)) $$;

-- every expense line of the period and places, with the three flags. Internal: the caller checks the right and the places.
create or replace function public._c1_exp_rows(p_from date, p_to date, p_locs int[])
returns table (key text, kind text, class text, source_id text, entry_date date, location_id int, ref text, head text, heads jsonb, paid_to text, mode text, amount numeric, status text,
               no_receipt_amount numeric, unreadable int, in_report boolean, in_pl boolean, in_journal boolean, posted boolean, flags text[], staff text)
language sql stable security definer set search_path = public as $$
  with par as (select public._w1d_parity_on() as par_on, coalesce(public.rule_txt('d_wallet_fee_treatment'), 'separate_expense') as wf),
  v as (
    select e.id, e.serial, e.entry_date, e.location_id, e.status, e.created_staff, e.rev_no, public.is_shadow('entries', e.id::text) as shadow, z.*
      from public.entries e
      cross join lateral (
        select coalesce(sum(public._r2_num(ln -> 'amount')), 0) as amt,
               coalesce(sum(public._r2_num(ln -> 'amount')) filter (where ln ->> 'receipt' = 'no'), 0) as norc,
               count(*) filter (where coalesce(btrim(ln ->> 'amount'), '') <> '' and public._r2_num(ln -> 'amount') is null) as bad,
               count(distinct coalesce(nullif(btrim(ln ->> 'head'), ''), '-')) as nh,
               min(coalesce(nullif(btrim(ln ->> 'head'), ''), '-')) as h1,
               min(nullif(btrim(ln ->> 'to'), '')) as to1,
               coalesce(jsonb_agg(jsonb_build_object('head', coalesce(nullif(btrim(ln ->> 'head'), ''), '-'), 'to', nullif(btrim(ln ->> 'to'), ''), 'receipt', ln ->> 'receipt', 'amount', public._r2_num(ln -> 'amount')) order by ord), '[]'::jsonb) as lines
          from jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) with ordinality as t(ln, ord)) z
     where e.form_code = '10-2' and e.entry_date between p_from and p_to and e.location_id = any (p_locs))
  select 'voucher:' || v.id::text, 'voucher'::text,
         (case when v.shadow then 'voucher_shadow' when v.status = 'approved' then 'voucher_approved' when v.status = 'submitted' then 'voucher_submitted' else 'voucher_not_counted' end)::text,
         v.id::text, v.entry_date, v.location_id, v.serial::text, (case when v.nh = 1 then v.h1 end)::text, v.lines, v.to1::text, null::text, v.amt, v.status::text, v.norc, v.bad::int,
         (public._w1d_exp_status_ok(v.status, 'pl') and (not (select par_on from par) or not v.shadow)),
         (public._w1d_exp_status_ok(v.status, 'pl') and not v.shadow),
         (public._w1d_exp_status_ok(v.status, 'journal') and not v.shadow),
         public._c1_je_live('expense_voucher', v.id::text || ':' || coalesce(v.rev_no, 0)::text),
         array_remove(array[case when v.shadow then 'shadow' end, case when v.bad > 0 then 'unreadable_lines' end, case when v.norc > 0 then 'no_receipt' end], null)::text[],
         v.created_staff::text
    from v
  union all
  select 'quick:' || q.id::text, 'quick', 'quick', q.id::text, q.exp_date, q.location_id, null::text, q.head::text, null::jsonb, nullif(btrim(q.paid_to), '')::text, q.mode::text, q.amount, q.status::text,
         (case when not q.receipt then q.amount else 0 end)::numeric, 0,
         (q.status = 'done' and (select par_on from par)), (q.status = 'done'), (q.status = 'done'), public._c1_je_live('quick_expense', q.id::text),
         array_remove(array[case when not q.receipt then 'no_receipt' end], null)::text[], q.created_staff::text
    from public.quick_expenses q where q.exp_date between p_from and p_to and q.location_id = any (p_locs)
  union all
  select 'bank_charge:' || c.id::text, 'bank_charge', 'bank_charge', c.id::text, c.charge_date, c.location_id, c.ref::text, null::text, null::jsonb, coalesce(nullif(btrim(ma.name_en), ''), ma.name_bn)::text, ma.kind::text, c.amount, c.status::text,
         0::numeric, 0, false, false, (c.status = 'done'), public._c1_je_live('money_charge', c.id::text), '{}'::text[], c.created_staff::text
    from public.money_charges c join public.money_accounts ma on ma.id = c.account_id
   where c.kind = 'charge' and c.charge_date between p_from and p_to and (c.location_id = any (p_locs) or (c.location_id is null and public._acct_all()))
  union all
  select 'wallet_fee:' || f.id::text, 'wallet_fee', 'wallet_fee', f.id::text, f.fee_date, f.location_id, f.ref::text, f.kind::text, null::jsonb, w.name_en::text, 'mobile'::text, f.amount, (case when f.voided then 'void' else 'done' end)::text,
         0::numeric, 0, false, (not f.voided and (select wf from par) = 'separate_expense'), (not f.voided and (select wf from par) = 'separate_expense'), public._c1_je_live('d_wallet_fee', f.id::text),
         '{}'::text[], f.created_staff::text
    from public.d_wallet_fees f join public.d_wallets w on w.id = f.wallet_id
   where f.fee_date between p_from and p_to and (f.location_id = any (p_locs) or (f.location_id is null and public._acct_all()))
  union all
  select ('marketing:' || e.id::text || ':' || t.ord::text), 'marketing', 'marketing', e.id::text, coalesce(public._db_date(ln ->> 'date'), e.entry_date), e.location_id, e.serial::text,
         coalesce(nullif(btrim(ln ->> 'head'), ''), '-')::text, null::jsonb, nullif(btrim(ln ->> 'campaign'), '')::text, nullif(btrim(ln ->> 'source'), '')::text, public._r2_num(ln -> 'amt'), e.status::text,
         0::numeric, 0, false, false, false, null::boolean,
         array_remove(array['not_in_books', case when ln ->> 'source' = 'imprest' then 'maybe_in_voucher' end], null)::text[], e.created_staff::text
    from public.entries e
    cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) with ordinality as t(ln, ord)
   where e.form_code = '18-1' and e.status in ('submitted', 'approved') and e.location_id = any (p_locs)
     and coalesce(public._db_date(ln ->> 'date'), e.entry_date) between p_from and p_to and coalesce(public._r2_num(ln -> 'amt'), 0) > 0
$$;

create or replace function public.expense_register(p_from date, p_to date, p_loc int default null, p_basis text default 'all', p_kinds text[] default null, p_status text default null,
                                                   p_limit int default 100, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; basis text := lower(coalesce(nullif(btrim(p_basis), ''), 'all')); lim int := least(greatest(coalesce(p_limit, 100), 1), 500); off int := greatest(coalesce(p_offset, 0), 0);
  cnt bigint; shown numeric; rows_ jsonb; lines_ jsonb; tot jsonb; unp jsonb; labels jsonb; sm_en text; sm_bn text; par boolean := public._w1d_parity_on(); cnt_rule text := coalesce(public.rule_txt('expense_count_on'), 'as_today');
  wf text := coalesce(public.rule_txt('d_wallet_fee_treatment'), 'separate_expense');
begin
  if not public._c1_exp_view() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'bad_range'; end if;
  if basis not in ('all', 'report', 'pl', 'journal') then raise exception 'bad_basis'; end if;
  locs := public._r2_locs(case when p_loc is null then '{}'::jsonb else jsonb_build_object('locations', jsonb_build_array(p_loc)) end);
  if cardinality(locs) = 0 then raise exception 'not allowed'; end if;

  with r as (select * from public._c1_exp_rows(p_from, p_to, locs)),
  f as (select * from r where (basis = 'all' or (basis = 'report' and in_report) or (basis = 'pl' and in_pl) or (basis = 'journal' and in_journal))
                         and (p_kinds is null or kind = any (p_kinds)) and (p_status is null or status = p_status)),
  pg as (select * from f order by entry_date desc, kind, ref nulls last, key limit lim offset off)
  select (select count(*) from f), (select coalesce(sum(amount), 0) from f),
         (select coalesce(jsonb_agg(to_jsonb(pg) order by pg.entry_date desc, pg.kind, pg.ref nulls last, pg.key), '[]'::jsonb) from pg)
    into cnt, shown, rows_;

  with r as (select * from public._c1_exp_rows(p_from, p_to, locs))
  select jsonb_build_object('report', coalesce(sum(amount) filter (where in_report), 0), 'pl', coalesce(sum(amount) filter (where in_pl), 0), 'journal', coalesce(sum(amount) filter (where in_journal), 0),
           'daybook', coalesce(sum(amount) filter (where in_pl and kind <> 'wallet_fee'), 0), 'journal_posted', coalesce(sum(amount) filter (where in_journal and posted), 0), 'not_in_books', coalesce(sum(amount) filter (where kind = 'marketing'), 0),
           'lines', count(*)),
         jsonb_build_object('n', count(*) filter (where in_journal and not posted), 'amount', coalesce(sum(amount) filter (where in_journal and not posted), 0))
    into tot, unp from r;

  with r as (select * from public._c1_exp_rows(p_from, p_to, locs)),
  g as (select class, count(*) n, coalesce(sum(amount), 0) amt, coalesce(sum(amount) filter (where in_report), 0) rep, coalesce(sum(amount) filter (where in_pl), 0) pl,
               coalesce(sum(amount) filter (where in_journal), 0) jr, bool_and(in_report) a_rep, bool_and(in_pl) a_pl, bool_and(in_journal) a_jr from r group by class)
  select coalesce(jsonb_agg(jsonb_build_object('class', g.class, 'n', g.n, 'amount', g.amt, 'report', g.rep, 'pl', g.pl, 'journal', g.jr, 'd_pl_report', g.pl - g.rep, 'd_journal_pl', g.jr - g.pl,
    'label_en', case g.class when 'voucher_approved' then 'Expense vouchers, approved' when 'voucher_submitted' then 'Expense vouchers, submitted and waiting for approval'
        when 'voucher_not_counted' then 'Expense vouchers, draft or rejected' when 'voucher_shadow' then 'Expense vouchers that are a copy (shadow) of another record' when 'quick' then 'Quick expenses'
        when 'bank_charge' then 'Bank charges' when 'wallet_fee' then 'Mobile wallet fees' else 'Marketing register 18-1' end,
    'label_bn', case g.class when 'voucher_approved' then 'ব্যয় ভাউচার, অনুমোদিত' when 'voucher_submitted' then 'ব্যয় ভাউচার, জমা দেওয়া, অনুমোদনের অপেক্ষায়'
        when 'voucher_not_counted' then 'ব্যয় ভাউচার, খসড়া বা বাতিল' when 'voucher_shadow' then 'অন্য রেকর্ডের কপি (শ্যাডো) ভাউচার' when 'quick' then 'দ্রুত খরচ'
        when 'bank_charge' then 'ব্যাংক চার্জ' when 'wallet_fee' then 'মোবাইল ওয়ালেট ফি' else 'মার্কেটিং রেজিস্টার ১৮-১' end,
    'why_en', case g.class
        when 'voucher_approved' then null
        when 'voucher_submitted' then case when g.a_pl then 'Submitted but not yet approved. The expense report, the P&L and the day book count it' else 'Submitted but not yet approved. Nothing counts it yet (the setting counts only approved vouchers)' end
                                      || case when g.a_jr then ', and so does the journal.' else '; the journal waits for the approval.' end
        when 'voucher_not_counted' then 'Draft or rejected: no total counts it.'
        when 'voucher_shadow' then 'A copy of a record that is entered through another path: the main record is counted, this copy is not.'
        when 'quick' then 'Counted in the P&L, the day book and the journal' || case when g.a_rep then ' and in the expense report.' else '; the expense report leaves it out (the setting "Expense report counts quick expenses" is off).' end
        when 'bank_charge' then 'Only the journal has bank charges: the expense report, the P&L and the day book do not count them.'
        when 'wallet_fee' then case when g.a_pl then 'The P&L and the journal count wallet fees; the expense report and the day book do not.' else 'Not counted: wallet fees are not treated as a separate expense (setting).' end
        else 'Not in the books. No report and no journal counts the marketing register. If the same spend was also typed as an expense voucher it is in the books once, through the voucher.' end,
    'why_bn', case g.class
        when 'voucher_approved' then null
        when 'voucher_submitted' then case when g.a_pl then 'জমা দেওয়া কিন্তু অনুমোদন হয়নি। খরচ রিপোর্ট, P&L ও দিনের খাতা ধরে' else 'জমা দেওয়া কিন্তু অনুমোদন হয়নি। এখনও কোনো মোটে ধরা হয় না (সেটিং শুধু অনুমোদিত ভাউচার ধরে)' end
                                      || case when g.a_jr then ', জার্নালও ধরে।' else '; জার্নাল অনুমোদনের অপেক্ষায়।' end
        when 'voucher_not_counted' then 'খসড়া বা বাতিল: কোনো মোটে ধরা হয় না।'
        when 'voucher_shadow' then 'অন্য পথে এন্ট্রি হওয়া রেকর্ডের কপি: মূল রেকর্ড ধরা হয়, এই কপি নয়।'
        when 'quick' then 'P&L, দিনের খাতা ও জার্নালে ধরা হয়' || case when g.a_rep then ' এবং খরচ রিপোর্টেও।' else '; খরচ রিপোর্ট বাদ দেয় (সেটিং "খরচ রিপোর্টে দ্রুত খরচ ধরো" বন্ধ)।' end
        when 'bank_charge' then 'শুধু জার্নালে ব্যাংক চার্জ আছে: খরচ রিপোর্ট, P&L ও দিনের খাতা ধরে না।'
        when 'wallet_fee' then case when g.a_pl then 'P&L ও জার্নাল ওয়ালেট ফি ধরে; খরচ রিপোর্ট ও দিনের খাতা ধরে না।' else 'ধরা হয় না: ওয়ালেট ফি আলাদা খরচ হিসেবে ধরার সেটিং নেই।' end
        else 'খাতায় নেই। কোনো রিপোর্ট বা জার্নাল মার্কেটিং রেজিস্টার ধরে না। একই খরচ ব্যয় ভাউচারেও লেখা হলে ভাউচার দিয়ে একবার খাতায় আছে।' end)
    order by case g.class when 'voucher_approved' then 1 when 'voucher_submitted' then 2 when 'voucher_not_counted' then 3 when 'voucher_shadow' then 4 when 'quick' then 5 when 'bank_charge' then 6 when 'wallet_fee' then 7 else 8 end), '[]'::jsonb)
    into lines_ from g;

  select coalesce(jsonb_object_agg(l.list_code, l.m), '{}'::jsonb) into labels from (
    select o.list_code, jsonb_object_agg(o.value_code, jsonb_build_object('bn', o.label_bn, 'en', coalesce(o.label_en, o.label_bn))) m
      from public.option_lists o where o.list_code in ('expense_heads', 'marketing_heads') group by o.list_code) l;

  sm_en := 'Expense report ' || public._c1_money((tot ->> 'report')::numeric) || '; P&L ' || public._c1_money((tot ->> 'pl')::numeric)
      || case when (tot ->> 'daybook')::numeric <> (tot ->> 'pl')::numeric then ' (the day book shows ' || public._c1_money((tot ->> 'daybook')::numeric) || ': it leaves out wallet fees)' else ' (the day book shows the same)' end
      || '; journal ' || public._c1_money((tot ->> 'journal')::numeric) || '.'
    || coalesce((select ' ' || string_agg(x ->> 'label_en' || ' ' || public._c1_money((x ->> 'amount')::numeric) || ': ' || (x ->> 'why_en'), ' ' order by ord) from jsonb_array_elements(lines_) with ordinality t(x, ord)
                  where x ->> 'why_en' is not null), '');
  sm_bn := 'খরচ রিপোর্ট ' || public._c1_money((tot ->> 'report')::numeric) || '; P&L ' || public._c1_money((tot ->> 'pl')::numeric)
      || case when (tot ->> 'daybook')::numeric <> (tot ->> 'pl')::numeric then ' (দিনের খাতায় ' || public._c1_money((tot ->> 'daybook')::numeric) || ': ওয়ালেট ফি বাদ)' else ' (দিনের খাতায় একই)' end
      || '; জার্নাল ' || public._c1_money((tot ->> 'journal')::numeric) || '।'
    || coalesce((select ' ' || string_agg(x ->> 'label_bn' || ' ' || public._c1_money((x ->> 'amount')::numeric) || ': ' || (x ->> 'why_bn'), ' ' order by ord) from jsonb_array_elements(lines_) with ordinality t(x, ord)
                  where x ->> 'why_bn' is not null), '');

  return jsonb_build_object('from', p_from, 'to', p_to, 'location_id', p_loc, 'basis', basis, 'rows', rows_, 'count', cnt, 'shown_amount', shown, 'limit', lim, 'offset', off, 'has_more', (off + lim) < cnt,
    'totals', tot, 'recon', jsonb_build_object('lines', lines_, 'unposted', unp, 'summary_en', sm_en, 'summary_bn', sm_bn,
        'agree', (tot ->> 'report') = (tot ->> 'pl') and (tot ->> 'pl') = (tot ->> 'journal')),
    'labels', labels, 'settings', jsonb_build_object('expense_count_on', cnt_rule, 'report_expense_parity_on', par, 'd_wallet_fee_treatment', wf));
end $$;

revoke all on function public._c1_exp_view(), public._c1_je_live(text, text), public._c1_exp_rows(date, date, int[]) from public, anon, authenticated;
revoke all on function public.expense_register(date, date, int, text, text[], text, int, int) from public, anon;
grant execute on function public.expense_register(date, date, int, text, text[], text, int, int) to authenticated;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase443.sql
-- Phase 443 (bos443) - STATEMENTS, part 1 (package RPT-C1, block R3): account classes and the P&L by month and outlet. Paste AFTER phase442. Paste-twice safe. New objects only.
-- WHY (docs/REPORTS_AUDIT_3.md reports 121, 124, 126): the books can show ONE P&L for ONE period and ONE place at a time; the cash-flow tab is a list of cash-account movements without
--      operating / investing / financing, and there is no working-capital figure. The owner decides which class each chart account belongs to; nothing is guessed.
-- WHAT THIS FILE DOES (read only for the books: no journal line is written)
--   1. Table coa_report_class: per chart account, an optional cash-flow class (operating / investing / financing) and an optional balance class (current / non_current). BLANK = "unclassified".
--      Nothing is deleted (clearing a class blanks it; every change is written to audit_log by the table trigger). Set by the owner or an accounts manager: coa_class_set, coa_class_apply_suggested.
--      coa_class_list shows every account with its classes AND a suggestion (usual accounting practice by account code); a suggestion is never applied by itself - only coa_class_apply_suggested
--      (owner / accounts manager, fills blanks only, never overwrites) applies it.
--   2. stmt_pl_matrix(from, to, place): the P&L from the JOURNAL by month (columns) and outlet (rows): income, cost of goods, other expenses, gross and net. Year-end closing journals are left out.
--      Journal lines without an outlet are shown on their own row ("not assigned to an outlet"). stmt_pl_drill(month, place, kind): the accounts and the biggest journal entries behind one cell.
-- Access: owner, accounts view / manage right, or the report grant of the profit group. Places: the ones the person may see (same rule as the books). Needs the accounting start date; without it
--      the answer says so ("accounting module not switched on - no data captured") and carries no number.

do $g$ begin
  if to_regprocedure('public._c1_p442_present()') is null then raise exception 'phase443 needs phase442 first'; end if;
  if to_regclass('public.coa_accounts') is null or to_regprocedure('public._acct_bal(date,date,integer)') is null or to_regprocedure('public._w1d_mgr()') is null then
    raise exception 'phase443 needs the accounting of phases 40 and 92';
  end if;
end $g$;

create or replace function public._c1_p443_present() returns boolean language sql immutable as $$ select true $$;

create or replace function public._stmt_view() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public._acct_view() or public.rpt_access('profit')) $$;

-- ---------- 1. classes per account ----------
create table if not exists public.coa_report_class (
  account_id bigint primary key references public.coa_accounts(id),
  cf_class text check (cf_class in ('operating', 'investing', 'financing')),
  bs_class text check (bs_class in ('current', 'non_current')),
  reason text check (reason is null or length(reason) <= 300),
  set_by uuid default auth.uid(), set_at timestamptz not null default now()
);
drop trigger if exists coa_report_class_nodel on public.coa_report_class;
create trigger coa_report_class_nodel before delete on public.coa_report_class for each row execute function public.no_hard_delete();
drop trigger if exists audit_coa_report_class on public.coa_report_class;
create trigger audit_coa_report_class after insert or update on public.coa_report_class for each row execute function public.log_change('account_id');
alter table public.coa_report_class enable row level security;
revoke all on public.coa_report_class from public, anon, authenticated;
drop policy if exists coa_report_class_read on public.coa_report_class;
create policy coa_report_class_read on public.coa_report_class for select to authenticated using (public._stmt_view());
grant select on public.coa_report_class to authenticated;

-- the cash accounts: the SAME set the Cash flow tab (acct_cash_flow) uses, so the two agree
create or replace function public._c1_cash_ids() returns bigint[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(distinct x), '{}') from (
    select account_id x from public.acct_mappings where key in ('pay_cash', 'pay_bank', 'pay_mobile')
    union select coa_account_id from public.money_accounts
    union select account_id from public.acct_mappings where key like 'd\_wallet\_%') z where x is not null $$;

-- usual practice by account code (a suggestion only). cf: income / expense and the working accounts are operating, fixed assets investing, partner loans and capital financing.
-- bs: assets are current except the fixed-asset group 15xx; liabilities are current except partner loans 25xx (left blank: the owner decides).
create or replace function public._c1_class_suggest(p_code text, p_type text) returns table (cf text, bs text) language sql immutable set search_path = public as $$
  select case
           when p_type in ('income', 'expense') then 'operating'
           when p_type = 'asset' and p_code ~ '^1[234]' then 'operating'
           when p_type = 'asset' and p_code ~ '^15' then 'investing'
           when p_type = 'liability' and p_code ~ '^25' then 'financing'
           when p_type = 'liability' then 'operating'
           when p_type = 'equity' and p_code ~ '^3[1-4]' then 'financing'
           else null end,
         case
           when p_type = 'asset' and p_code ~ '^15' then 'non_current'
           when p_type = 'asset' then 'current'
           when p_type = 'liability' and p_code ~ '^25' then null
           when p_type = 'liability' then 'current'
           else null end $$;

create or replace function public.coa_class_list() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare ids bigint[] := public._c1_cash_ids();
begin
  if not public._stmt_view() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'type', a.type, 'active', a.active, 'is_cash', a.id = any (ids),
      'cf_class', c.cf_class, 'bs_class', c.bs_class, 'suggest_cf', s.cf, 'suggest_bs', s.bs, 'set_at', c.set_at, 'reason', c.reason) order by a.code)
    from public.coa_accounts a left join public.coa_report_class c on c.account_id = a.id
    cross join lateral public._c1_class_suggest(a.code, a.type) s
    where not a.is_group), '[]'::jsonb);
end $$;

create or replace function public.coa_class_set(p_account bigint, p_cf text, p_bs text, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.coa_accounts; cf text := nullif(btrim(coalesce(p_cf, '')), ''); bs text := nullif(btrim(coalesce(p_bs, '')), ''); why text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not public._w1d_mgr() then raise exception 'not allowed'; end if;
  select * into a from public.coa_accounts where id = p_account;
  if not found then raise exception 'account_not_found'; end if;
  if a.is_group then raise exception 'account_is_group'; end if;
  if cf is not null and cf not in ('operating', 'investing', 'financing') then raise exception 'bad_value'; end if;
  if bs is not null and bs not in ('current', 'non_current') then raise exception 'bad_value'; end if;
  if cf is not null and p_account = any (public._c1_cash_ids()) then raise exception 'cash_account_has_no_flow_class'; end if;
  if bs is not null and a.type not in ('asset', 'liability') then raise exception 'balance_class_is_for_assets_and_liabilities'; end if;
  if why is not null and length(why) > 300 then raise exception 'too_long'; end if;
  insert into public.coa_report_class (account_id, cf_class, bs_class, reason, set_by, set_at) values (p_account, cf, bs, why, auth.uid(), now())
    on conflict (account_id) do update set cf_class = excluded.cf_class, bs_class = excluded.bs_class, reason = excluded.reason, set_by = auth.uid(), set_at = now();
  return jsonb_build_object('account_id', p_account, 'cf_class', cf, 'bs_class', bs);
end $$;

-- fills the blanks with the suggestion. Never overwrites a class that is set. Dry run (p_dry true, the default) writes nothing and says what it would do.
create or replace function public.coa_class_apply_suggested(p_reason text default null, p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int := 0; x record; ids bigint[] := public._c1_cash_ids(); why text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not public._w1d_mgr() then raise exception 'not allowed'; end if;
  if not coalesce(p_dry, true) and (why is null or length(why) < 5) then raise exception 'reason_required'; end if;
  for x in select a.id, a.code, c.cf_class cur_cf, c.bs_class cur_bs, s.cf, s.bs, (a.id = any (ids)) is_cash
             from public.coa_accounts a left join public.coa_report_class c on c.account_id = a.id cross join lateral public._c1_class_suggest(a.code, a.type) s
            where not a.is_group and ((c.cf_class is null and s.cf is not null and not (a.id = any (ids))) or (c.bs_class is null and s.bs is not null)) loop
    n := n + 1;
    if not coalesce(p_dry, true) then
      insert into public.coa_report_class (account_id, cf_class, bs_class, reason, set_by, set_at)
        values (x.id, case when x.is_cash then null else x.cur_cf end, x.cur_bs, null, auth.uid(), now()) on conflict (account_id) do nothing;
      update public.coa_report_class c set cf_class = coalesce(c.cf_class, case when x.is_cash then null else x.cf end), bs_class = coalesce(c.bs_class, x.bs),
             reason = coalesce(why, c.reason), set_by = auth.uid(), set_at = now() where c.account_id = x.id;
    end if;
  end loop;
  return jsonb_build_object('dry', coalesce(p_dry, true), 'accounts', n);
end $$;

-- ---------- 2. P&L by month and outlet, from the journal ----------
create or replace function public.stmt_pl_matrix(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); to_ date := coalesce(p_to, public._acct_today()); fr date; v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs();
  cid bigint; cells jsonb; outs jsonb; by_m jsonb; by_o jsonb; grand jsonb; months jsonb; ncl bigint; nun bigint; cm bigint;
begin
  if not public._stmt_view() then raise exception 'not allowed'; end if;
  if st is null then
    return jsonb_build_object('data_needed', true, 'reason', 'accounting_not_started', 'text_en', 'The accounting module is not switched on (no start date) - no data captured.',
      'text_bn', 'হিসাব মডিউল চালু নেই (শুরুর তারিখ নেই) - কোনো তথ্য সংগ্রহ হয়নি।');
  end if;
  fr := coalesce(p_from, st);
  if fr > to_ or to_ - fr > 1100 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  select account_id into cid from public.acct_mappings where key = 'cogs';
  select coalesce(jsonb_agg(to_char(m, 'YYYY-MM') order by m), '[]'::jsonb) into months from generate_series(date_trunc('month', fr), date_trunc('month', to_), interval '1 month') m;

  with p as (
    select to_char(date_trunc('month', e.entry_date), 'YYYY-MM') as mon, l.location_id as loc,
           coalesce(sum(l.credit - l.debit) filter (where a.type = 'income'), 0) as income,
           coalesce(sum(l.debit - l.credit) filter (where a.id = cid), 0) as cogs,
           coalesce(sum(l.debit - l.credit) filter (where a.type = 'expense' and a.id is distinct from cid), 0) as expenses
      from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.coa_accounts a on a.id = l.account_id
     where a.type in ('income', 'expense') and not a.is_group and e.entry_date between fr and to_
       and e.source_type <> 'year_close' and coalesce(e.flags, '') not like '%year_close%'
       and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)
     group by 1, 2),
  c as (select coalesce(jsonb_agg(jsonb_build_object('month', p.mon, 'location_id', p.loc, 'income', p.income, 'cogs', p.cogs, 'gross', p.income - p.cogs, 'expenses', p.expenses, 'net', p.income - p.cogs - p.expenses,
          'cogs_missing', (select count(*) from public.journal_entries e where to_char(date_trunc('month', e.entry_date), 'YYYY-MM') = p.mon and e.flags like '%cogs_missing%' and e.reverses_id is null
                            and e.location_id is not distinct from p.loc)) order by p.mon, p.loc nulls last), '[]'::jsonb) j from p),
  o as (select coalesce(jsonb_agg(jsonb_build_object('location_id', z.loc, 'name_bn', coalesce(lc.name_bn, 'কোনো আউটলেটে দেওয়া নেই'), 'name_en', coalesce(lc.name_en, lc.name_bn, 'Not assigned to an outlet'),
          'assigned', z.loc is not null) order by z.loc nulls last), '[]'::jsonb) j from (select distinct loc from p) z left join public.locations lc on lc.id = z.loc),
  bm as (select coalesce(jsonb_agg(jsonb_build_object('month', q.mon, 'income', q.i, 'cogs', q.c, 'gross', q.i - q.c, 'expenses', q.x, 'net', q.i - q.c - q.x) order by q.mon), '[]'::jsonb) j
           from (select mon, sum(income) i, sum(cogs) c, sum(expenses) x from p group by mon) q),
  bo as (select coalesce(jsonb_agg(jsonb_build_object('location_id', q.loc, 'income', q.i, 'cogs', q.c, 'gross', q.i - q.c, 'expenses', q.x, 'net', q.i - q.c - q.x) order by q.loc nulls last), '[]'::jsonb) j
           from (select loc, sum(income) i, sum(cogs) c, sum(expenses) x from p group by loc) q),
  gr as (select jsonb_build_object('income', coalesce(sum(income), 0), 'cogs', coalesce(sum(cogs), 0), 'gross', coalesce(sum(income - cogs), 0), 'expenses', coalesce(sum(expenses), 0),
          'net', coalesce(sum(income - cogs - expenses), 0)) j, count(*) filter (where loc is null) as nun from p)
  select c.j, o.j, bm.j, bo.j, gr.j, gr.nun into cells, outs, by_m, by_o, grand, nun from c, o, bm, bo, gr;

  select count(*) into ncl from public.journal_entries e where e.entry_date between fr and to_ and (e.source_type = 'year_close' or coalesce(e.flags, '') like '%year_close%');
  select count(*) into cm from public.journal_entries e where e.entry_date between fr and to_ and e.flags like '%cogs_missing%' and e.reverses_id is null
     and (v_all or (e.location_id is not null and public.can_loc(e.location_id))) and (p_loc is null or e.location_id = p_loc);
  return jsonb_build_object('from', fr, 'to', to_, 'location_id', p_loc, 'months', months, 'outlets', outs, 'cells', cells, 'by_month', by_m, 'by_outlet', by_o, 'grand', grand,
    'provisional', cm > 0, 'cogs_missing_entries', cm,
    'notes', (case when ncl > 0 then jsonb_build_array(jsonb_build_object('code', 'year_close_left_out', 'level', 'info', 'n', ncl,
                 'text_en', 'Year-end closing journals (' || ncl || ') are left out so that the closed year still shows its income and expenses.', 'text_bn', 'বছর শেষের ক্লোজিং জার্নাল (' || ncl || 'টি) বাদ দেওয়া হয়েছে, যাতে ক্লোজ করা বছরেও আয় ও খরচ দেখা যায়।')) else '[]'::jsonb end)
      || (case when nun > 0 then jsonb_build_array(jsonb_build_object('code', 'unassigned_outlet', 'level', 'info', 'text_en', 'Some journal lines have no outlet; they are on their own row.', 'text_bn', 'কিছু জার্নাল লাইনে আউটলেট নেই; সেগুলো আলাদা সারিতে।')) else '[]'::jsonb end)
      || (case when cm > 0 then jsonb_build_array(jsonb_build_object('code', 'cogs_missing', 'level', 'warn', 'n', cm, 'text_en', cm || ' sale(s) have no known cost in the books: the gross profit is provisional.', 'text_bn', cm || 'টি বিক্রির খাতায় খরচ জানা নেই: মোট লাভ সাময়িক।')) else '[]'::jsonb end),
    'basis', jsonb_build_object('text_en', 'From the journal (the books). Income is net of sales returns and discounts; cost of goods is the cost-of-goods account; other expenses are all other expense accounts. It is not the management view of the hub reports.',
      'text_bn', 'জার্নাল (হিসাবের খাতা) থেকে। আয় বিক্রি-ফেরত ও ছাড় বাদে; মালের খরচ মালের খরচের অ্যাকাউন্ট; অন্য খরচ বাকি সব খরচের অ্যাকাউন্ট। এটি হাবের রিপোর্টের ম্যানেজমেন্ট ভিউ নয়।'));
end $$;

create or replace function public.stmt_pl_drill(p_month date, p_loc int, p_kind text, p_unassigned boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); m0 date; m1 date; v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs(); cid bigint; accs jsonb; ents jsonb;
  kind text := lower(coalesce(nullif(btrim(p_kind), ''), 'all'));
begin
  if not public._stmt_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  if p_month is null or kind not in ('income', 'cogs', 'expenses', 'all') then raise exception 'bad_value'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  m0 := date_trunc('month', p_month)::date; m1 := (m0 + interval '1 month')::date - 1;
  select account_id into cid from public.acct_mappings where key = 'cogs';
  with d as (
    select a.id as aid, e.id as eid, case when a.type = 'income' then l.credit - l.debit else l.debit - l.credit end as amt,
           case when a.type = 'income' then 'income' when a.id = cid then 'cogs' else 'expenses' end as typ
      from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.coa_accounts a on a.id = l.account_id
     where a.type in ('income', 'expense') and not a.is_group and e.entry_date between greatest(m0, st) and m1 and e.source_type <> 'year_close' and coalesce(e.flags, '') not like '%year_close%'
       and (v_all or l.location_id = any (v_locs))
       and ((coalesce(p_unassigned, false) and l.location_id is null) or (not coalesce(p_unassigned, false) and (p_loc is null or l.location_id = p_loc)))),
  fa as (select aid, typ, sum(amt) amt, count(*) n from d where kind = 'all' or typ = kind group by aid, typ),
  fe as (select eid, typ, sum(amt) amt from d where kind = 'all' or typ = kind group by eid, typ order by abs(sum(amt)) desc limit 100)
  select (select coalesce(jsonb_agg(jsonb_build_object('account_id', a.id, 'code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'kind', fa.typ, 'amount', fa.amt, 'lines', fa.n) order by fa.typ, a.code), '[]'::jsonb)
            from fa join public.coa_accounts a on a.id = fa.aid),
         (select coalesce(jsonb_agg(jsonb_build_object('entry_id', je.id, 'entry_date', je.entry_date, 'source_type', je.source_type, 'memo', je.memo, 'kind', fe.typ, 'amount', fe.amt) order by abs(fe.amt) desc, je.id), '[]'::jsonb)
            from fe join public.journal_entries je on je.id = fe.eid)
    into accs, ents;
  return jsonb_build_object('month', to_char(m0, 'YYYY-MM'), 'location_id', p_loc, 'unassigned', coalesce(p_unassigned, false), 'kind', kind, 'accounts', accs, 'entries', ents);
end $$;

revoke all on function public._stmt_view(), public._c1_cash_ids(), public._c1_class_suggest(text, text) from public, anon, authenticated;
grant execute on function public._stmt_view() to authenticated;       -- used by the table policy
revoke all on function public.coa_class_list(), public.coa_class_set(bigint, text, text, text), public.coa_class_apply_suggested(text, boolean),
  public.stmt_pl_matrix(date, date, int), public.stmt_pl_drill(date, int, text, boolean) from public, anon;
grant execute on function public.coa_class_list(), public.coa_class_set(bigint, text, text, text), public.coa_class_apply_suggested(text, boolean),
  public.stmt_pl_matrix(date, date, int), public.stmt_pl_drill(date, int, text, boolean) to authenticated;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase444.sql
-- Phase 444 (bos444) - STATEMENTS, part 2 (package RPT-C1, block R3): the cash-flow statement and the working capital. Paste AFTER phase443. Paste-twice safe. New objects only.
-- WHY (docs/REPORTS_AUDIT_3.md F12, reports 124 and 126): the Cash flow tab lists movements of the cash accounts by source; an opening journal inside the period shows as a 900,000 inflow, a bank deposit
--      shows as 2,000 in AND 2,000 out, and nothing says operating / investing / financing. There is no working-capital figure.
-- WHAT THIS FILE DOES (read only for the books: no journal line is written)
--   1. Setting report_cf_opening_through (text date, blank): journals dated on or before it are opening balances, not flows. Opening journals (source opening) are ALWAYS opening.
--   2. stmt_cash_flow(from, to, place): cash-flow statement from the journal, DIRECT method. Cash = the same accounts as the Cash flow tab. For every journal entry the cash it moved is shared over the
--      other lines of the entry, and each line goes to the cash-flow class of its chart account (phase 443: operating / investing / financing; blank = "unclassified" - nothing is guessed).
--      Opening journals are left out of the flows (shown on their own line); a move between two cash accounts (deposit, withdrawal, wallet top-up) is netted: it is not a flow.
--      opening + operating + investing + financing + unclassified + opening journals in the period = closing, and the closing is the same figure as the Cash flow tab (the test proves it).
--      stmt_cf_drill(from, to, place, class, account): the journal entries behind one class or account.
--   4. c1_export_log(key, kind, filters, rows): the export gate + audit line for the CSV of the expense register (442) and of these statements (owner or export_data, plus the right to read the screen).
--   3. stmt_working_capital(as_of, place): (a) by the current / non-current class of each asset and liability account (phase 443): current assets - current liabilities, accounts without a class listed apart;
--      (b) the plain formula cash + customer receivables + inventory - supplier payables from the mapped accounts. Without any class (a) says "not captured", it never shows 0.
-- Access: as phase 443 (owner, accounts view / manage, or the report grant of the profit group). Without the accounting start date: "accounting module not switched on - no data captured".

do $g$ begin
  if to_regprocedure('public._c1_p443_present()') is null then raise exception 'phase444 needs phase443 first'; end if;
end $g$;

create or replace function public._c1_p444_present() returns boolean language sql immutable as $$ select true $$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('report_cf_opening_through', 'reports', 'text', null, null, null, null, null,
  'ক্যাশ-ফ্লো স্টেটমেন্ট: এই তারিখ পর্যন্ত জার্নাল শুরুর ব্যালেন্স', 'Cash-flow statement: এই তারিখ পর্যন্ত journal শুরুর balance', 'Cash-flow statement: journals up to this date are opening balances',
  'YYYY-MM-DD লিখুন। শুরুর ব্যালেন্স হাতে জার্নালে (manual) দিলে তার তারিখ এখানে দিন, তাহলে সেটি ক্যাশ-ফ্লো-এর আয় হিসেবে আসবে না। ফাঁকা থাকলে শুধু "শুরুর ব্যালেন্স" ধরনের জার্নাল বাদ যায়।',
  'YYYY-MM-DD লিখুন। শুরুর balance হাতে journal-এ (manual) দিলে তার তারিখ এখানে দিন, তাহলে সেটি cash-flow-এর আয় হিসেবে আসবে না। ফাঁকা থাকলে শুধু "শুরুর ব্যালেন্স" ধরনের journal বাদ যায়।',
  'Type a date as YYYY-MM-DD. If you entered the opening balances as an ordinary manual journal, give its date here so that it is not counted as a cash inflow. Blank: only journals of the kind "opening balances" are left out.', 818)
on conflict (key) do nothing;

create or replace function public._c1_open_through() returns date language plpgsql stable security definer set search_path = public as $$
declare v text := public.rule_txt('report_cf_opening_through');
begin
  if v is null or btrim(v) !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
  begin return btrim(v)::date; exception when others then return null; end;
end $$;

-- ---------- 2. cash-flow statement ----------
create or replace function public.stmt_cash_flow(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); to_ date := coalesce(p_to, public._acct_today()); fr date; v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs(); ids bigint[] := public._c1_cash_ids();
  thr date := public._c1_open_through(); open_ numeric; classes jsonb; srcs jsonb; flows numeric; opening_in numeric; transfers numeric; unalloc numeric; n_transfer bigint; n_manual_open bigint;
  unc_amt numeric; notes_ jsonb := '[]'::jsonb;
begin
  if not public._stmt_view() then raise exception 'not allowed'; end if;
  if st is null then
    return jsonb_build_object('data_needed', true, 'reason', 'accounting_not_started', 'text_en', 'The accounting module is not switched on (no start date) - no data captured.',
      'text_bn', 'হিসাব মডিউল চালু নেই (শুরুর তারিখ নেই) - কোনো তথ্য সংগ্রহ হয়নি।');
  end if;
  fr := coalesce(p_from, st);
  if fr > to_ or to_ - fr > 1100 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  select coalesce(sum(l.debit - l.credit), 0) into open_ from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
   where l.account_id = any (ids) and e.entry_date < fr and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc);

  with en as (
    select e.id, e.entry_date, e.source_type, coalesce(e.subtype, e.source_type) as cat,
           (e.source_type = 'opening' or exists (select 1 from public.journal_entries o where o.id = e.reverses_id and o.source_type = 'opening') or (thr is not null and e.entry_date <= thr)) as is_open,
           coalesce(sum(l.debit) filter (where l.account_id = any (ids)), 0) as cdr, coalesce(sum(l.credit) filter (where l.account_id = any (ids)), 0) as ccr,
           coalesce(sum(l.debit - l.credit) filter (where l.account_id = any (ids)), 0) as cash_net,
           coalesce(sum(l.credit - l.debit) filter (where not (l.account_id = any (ids))), 0) as ab,
           count(*) filter (where not (l.account_id = any (ids))) as n_counter
      from public.journal_entries e join public.journal_lines l on l.entry_id = e.id
     where e.entry_date between fr and to_ and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)
     group by e.id having bool_or(l.account_id = any (ids))),
  ct as (
    select en.id, l.account_id, coalesce(c.cf_class, 'unclassified') as cls, en.cash_net * (l.credit - l.debit) / en.ab as contrib
      from en join public.journal_lines l on l.entry_id = en.id and not (l.account_id = any (ids)) and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)
      left join public.coa_report_class c on c.account_id = l.account_id
     where not en.is_open and en.ab <> 0),
  pa as (select account_id, cls, coalesce(sum(greatest(contrib, 0)), 0) as i, coalesce(sum(greatest(-contrib, 0)), 0) as o from ct group by account_id, cls),
  pc as (select cls, sum(i) i, sum(o) o,
                jsonb_agg(jsonb_build_object('account_id', a.id, 'code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'in', pa.i, 'out', pa.o, 'net', pa.i - pa.o) order by a.code) accounts
           from pa join public.coa_accounts a on a.id = pa.account_id group by cls),
  cl as (select coalesce(jsonb_agg(jsonb_build_object('class', k.cls, 'in', coalesce(pc.i, 0), 'out', coalesce(pc.o, 0), 'net', coalesce(pc.i, 0) - coalesce(pc.o, 0), 'accounts', coalesce(pc.accounts, '[]'::jsonb)) order by k.ord), '[]'::jsonb) j
           from (values ('operating', 1), ('investing', 2), ('financing', 3), ('unclassified', 4)) k(cls, ord) left join pc on pc.cls = k.cls),
  sr as (select coalesce(jsonb_agg(jsonb_build_object('category', cat, 'in', i, 'out', o, 'net', i - o) order by cat), '[]'::jsonb) j
           from (select cat, coalesce(sum(greatest(cash_net, 0)), 0) i, coalesce(sum(greatest(-cash_net, 0)), 0) o from en where not is_open and (cash_net <> 0) group by cat) z),
  tt as (select coalesce(sum(cash_net) filter (where not is_open), 0) as flows, coalesce(sum(cash_net) filter (where is_open), 0) as opening_in, coalesce(sum(least(cdr, ccr)) filter (where not is_open), 0) as transfers,
                coalesce(sum(cash_net) filter (where not is_open and ab = 0 and cash_net <> 0), 0) as unalloc, count(*) filter (where not is_open and least(cdr, ccr) > 0) as n_transfer,
                count(*) filter (where e2.source_type = 'manual' and e2.entry_date = st and not e2.is_open and thr is null) as n_manual_open
           from en e2)
  select cl.j, sr.j, tt.flows, tt.opening_in, tt.transfers, tt.unalloc, tt.n_transfer, tt.n_manual_open into classes, srcs, flows, opening_in, transfers, unalloc, n_transfer, n_manual_open from cl, sr, tt;

  select ((x ->> 'in')::numeric + (x ->> 'out')::numeric) into unc_amt from jsonb_array_elements(classes) x where x ->> 'class' = 'unclassified';
  if coalesce(unc_amt, 0) > 0 then
    notes_ := notes_ || jsonb_build_array(jsonb_build_object('code', 'unclassified', 'level', 'warn',
      'text_en', 'Some cash movements belong to accounts that have no cash-flow class yet. They are shown as "unclassified" - nothing is guessed. Give the accounts a class in the Classes tab.',
      'text_bn', 'কিছু নগদ লেনদেন এমন অ্যাকাউন্টের যার ক্যাশ-ফ্লো ক্লাস এখনও দেওয়া হয়নি। সেগুলো "অশ্রেণিবদ্ধ" দেখাচ্ছে - কিছু আন্দাজ করা হয়নি। Classes ট্যাবে অ্যাকাউন্টে ক্লাস দিন।'));
  end if;
  if coalesce(unalloc, 0) <> 0 then
    notes_ := notes_ || jsonb_build_array(jsonb_build_object('code', 'unallocated', 'level', 'warn', 'amount', unalloc,
      'text_en', 'Part of the cash movement could not be shared over the other lines of its journal entry (the other lines are in places you cannot see): ' || public._c1_money(unalloc) || '.',
      'text_bn', 'নগদ লেনদেনের একটি অংশ তার জার্নাল এন্ট্রির অন্য লাইনে ভাগ করা যায়নি (অন্য লাইন আপনার দেখার বাইরের জায়গায়): ' || public._c1_money(unalloc) || '।'));
  end if;
  if coalesce(n_manual_open, 0) > 0 then
    notes_ := notes_ || jsonb_build_array(jsonb_build_object('code', 'maybe_opening', 'level', 'warn', 'n', n_manual_open,
      'text_en', n_manual_open || ' manual journal(s) are dated on the accounting start date and move cash. If they are the opening balances, give their date in the setting "journals up to this date are opening balances" - until then they count as cash inflows.',
      'text_bn', n_manual_open || 'টি হাতে-করা জার্নাল হিসাব শুরুর তারিখে এবং নগদ নাড়াচ্ছে। এগুলো শুরুর ব্যালেন্স হলে সেটিং "এই তারিখ পর্যন্ত জার্নাল শুরুর ব্যালেন্স"-এ তারিখ দিন - নইলে এগুলো নগদ আয় হিসেবে ধরা হবে।'));
  end if;
  if coalesce(opening_in, 0) <> 0 then
    notes_ := notes_ || jsonb_build_array(jsonb_build_object('code', 'opening_in_period', 'level', 'info', 'amount', opening_in,
      'text_en', 'Opening balances posted inside this period (' || public._c1_money(opening_in) || ') are not a flow: they are shown on their own line.',
      'text_bn', 'এই সময়ের মধ্যে পোস্ট করা শুরুর ব্যালেন্স (' || public._c1_money(opening_in) || ') কোনো লেনদেন নয়: আলাদা লাইনে দেখানো হয়েছে।'));
  end if;
  return jsonb_build_object('from', fr, 'to', to_, 'location_id', p_loc, 'opening', open_, 'classes', classes, 'by_source', srcs,
    'flows', flows, 'opening_in_period', opening_in, 'transfers_netted', transfers, 'transfer_entries', n_transfer, 'unallocated', unalloc,
    'closing', open_ + flows + opening_in,
    'opening_through', thr,
    'notes', notes_,
    'basis', jsonb_build_object('text_en', 'Direct method from the journal. Cash = the cash, bank and mobile wallet accounts (the same as the Cash flow tab of Accounts). Each cash movement is placed in the class of the other account of its journal entry. A move between two cash accounts is netted.',
      'text_bn', 'জার্নাল থেকে সরাসরি পদ্ধতি। নগদ = ক্যাশ, ব্যাংক ও মোবাইল ওয়ালেট অ্যাকাউন্ট (হিসাবের Cash flow ট্যাবের মতোই)। প্রতিটি নগদ লেনদেন তার জার্নাল এন্ট্রির অন্য অ্যাকাউন্টের ক্লাসে যায়। দুই নগদ অ্যাকাউন্টের মধ্যে স্থানান্তর নেট করা হয়।'));
end $$;

create or replace function public.stmt_cf_drill(p_from date, p_to date, p_loc int, p_class text, p_account bigint default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs(); ids bigint[] := public._c1_cash_ids(); thr date := public._c1_open_through();
  cls text := lower(coalesce(nullif(btrim(p_class), ''), 'all')); rows_ jsonb;
begin
  if not public._stmt_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 1100 then raise exception 'bad_range'; end if;
  if cls not in ('operating', 'investing', 'financing', 'unclassified', 'opening', 'transfer', 'all') then raise exception 'bad_value'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  with en as (
    select e.id, e.entry_date, e.source_type, e.memo,
           (e.source_type = 'opening' or exists (select 1 from public.journal_entries o where o.id = e.reverses_id and o.source_type = 'opening') or (thr is not null and e.entry_date <= thr)) as is_open,
           coalesce(sum(l.debit) filter (where l.account_id = any (ids)), 0) as cdr, coalesce(sum(l.credit) filter (where l.account_id = any (ids)), 0) as ccr,
           coalesce(sum(l.debit - l.credit) filter (where l.account_id = any (ids)), 0) as cash_net,
           coalesce(sum(l.credit - l.debit) filter (where not (l.account_id = any (ids))), 0) as ab
      from public.journal_entries e join public.journal_lines l on l.entry_id = e.id
     where e.entry_date between p_from and p_to and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)
     group by e.id having bool_or(l.account_id = any (ids))),
  ct as (
    select en.id, en.entry_date, en.source_type, en.memo, l.account_id, coalesce(c.cf_class, 'unclassified') as k, en.cash_net * (l.credit - l.debit) / en.ab as amt
      from en join public.journal_lines l on l.entry_id = en.id and not (l.account_id = any (ids)) and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)
      left join public.coa_report_class c on c.account_id = l.account_id
     where not en.is_open and en.ab <> 0),
  un as (
    select id, entry_date, source_type, memo, null::bigint as account_id, (case when is_open then 'opening' else 'transfer' end) as k, (case when is_open then cash_net else least(cdr, ccr) end) as amt
      from en where is_open or (least(cdr, ccr) > 0)),
  allr as (select * from ct union all select * from un)
  select coalesce(jsonb_agg(jsonb_build_object('entry_id', z.id, 'entry_date', z.entry_date, 'source_type', z.source_type, 'memo', z.memo, 'class', z.k, 'account_id', z.account_id,
           'account_code', a.code, 'amount', z.amt) order by z.entry_date desc, abs(z.amt) desc, z.id), '[]'::jsonb) into rows_
    from (select * from allr where (cls = 'all' or k = cls) and (p_account is null or account_id = p_account) order by entry_date desc, abs(amt) desc limit 300) z left join public.coa_accounts a on a.id = z.account_id;
  return jsonb_build_object('from', p_from, 'to', p_to, 'class', cls, 'account_id', p_account, 'rows', rows_);
end $$;

-- ---------- 3. working capital ----------
create or replace function public.stmt_working_capital(p_as_of date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); as_ date := coalesce(p_as_of, public._acct_today()); ids bigint[] := public._c1_cash_ids(); cash_ numeric; recv numeric; inv numeric; pay numeric;
  ca jsonb; cl jsonb; nca jsonb; ncl jsonb; ua jsonb; ul jsonb; sums jsonb; classed int; notes_ jsonb := '[]'::jsonb; wc numeric; n_un int;
begin
  if not public._stmt_view() then raise exception 'not allowed'; end if;
  if st is null then
    return jsonb_build_object('data_needed', true, 'reason', 'accounting_not_started', 'text_en', 'The accounting module is not switched on (no start date) - no data captured.',
      'text_bn', 'হিসাব মডিউল চালু নেই (শুরুর তারিখ নেই) - কোনো তথ্য সংগ্রহ হয়নি।');
  end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  with b as (
    select a.id, a.code, a.name_bn, a.name_en, a.type, c.bs_class, case when a.type = 'asset' then x.open_net + x.dr - x.cr else -(x.open_net + x.dr - x.cr) end as amt
      from public._acct_bal(null, as_, p_loc) x join public.coa_accounts a on a.id = x.account_id left join public.coa_report_class c on c.account_id = a.id
     where not a.is_group and a.type in ('asset', 'liability') and (x.open_net <> 0 or x.dr <> 0 or x.cr <> 0)),
  j as (select type, bs_class, jsonb_agg(jsonb_build_object('account_id', id, 'code', code, 'name_bn', name_bn, 'name_en', name_en, 'amount', amt) order by code) accs, sum(amt) tot, count(*) n from b group by type, bs_class)
  select coalesce((select accs from j where type = 'asset' and bs_class = 'current'), '[]'::jsonb), coalesce((select accs from j where type = 'liability' and bs_class = 'current'), '[]'::jsonb),
         coalesce((select accs from j where type = 'asset' and bs_class = 'non_current'), '[]'::jsonb), coalesce((select accs from j where type = 'liability' and bs_class = 'non_current'), '[]'::jsonb),
         coalesce((select accs from j where type = 'asset' and bs_class is null), '[]'::jsonb), coalesce((select accs from j where type = 'liability' and bs_class is null), '[]'::jsonb),
         jsonb_build_object('current_assets', coalesce((select tot from j where type = 'asset' and bs_class = 'current'), 0), 'current_liabilities', coalesce((select tot from j where type = 'liability' and bs_class = 'current'), 0),
           'non_current_assets', coalesce((select tot from j where type = 'asset' and bs_class = 'non_current'), 0), 'non_current_liabilities', coalesce((select tot from j where type = 'liability' and bs_class = 'non_current'), 0),
           'unclassified_assets', coalesce((select tot from j where type = 'asset' and bs_class is null), 0), 'unclassified_liabilities', coalesce((select tot from j where type = 'liability' and bs_class is null), 0)),
         (select count(*) from b where bs_class = 'current'), (select count(*) from b where bs_class is null)
    into ca, cl, nca, ncl, ua, ul, sums, classed, n_un;
  -- the plain formula
  select coalesce(sum(x.open_net + x.dr - x.cr) filter (where a.id = any (ids)), 0),
         coalesce(sum(x.open_net + x.dr - x.cr) filter (where a.id in (select account_id from public.acct_mappings where key = 'receivable')), 0),
         coalesce(sum(x.open_net + x.dr - x.cr) filter (where a.id in (select account_id from public.acct_mappings where key in ('inv_finished', 'inv_raw', 'inv_pack'))), 0),
         coalesce(-sum(x.open_net + x.dr - x.cr) filter (where a.id in (select account_id from public.acct_mappings where key = 'payable')), 0)
    into cash_, recv, inv, pay from public._acct_bal(null, as_, p_loc) x join public.coa_accounts a on a.id = x.account_id where not a.is_group;
  if classed = 0 then
    wc := null;
    notes_ := notes_ || jsonb_build_array(jsonb_build_object('code', 'no_current_class', 'level', 'warn',
      'text_en', 'No account is classed "current" yet, so working capital by class is not calculated (not captured). Give the accounts a class in the Classes tab. The formula below does not need classes.',
      'text_bn', 'এখনও কোনো অ্যাকাউন্ট "চলতি" ক্লাসে নেই, তাই ক্লাস অনুযায়ী ওয়ার্কিং ক্যাপিটাল হিসাব হয়নি (সংগ্রহ হয়নি)। Classes ট্যাবে অ্যাকাউন্টে ক্লাস দিন। নিচের সূত্রে ক্লাস লাগে না।'));
  else
    wc := (sums ->> 'current_assets')::numeric - (sums ->> 'current_liabilities')::numeric;
    if n_un > 0 then
      notes_ := notes_ || jsonb_build_array(jsonb_build_object('code', 'unclassified_balances', 'level', 'warn', 'n', n_un,
        'text_en', n_un || ' asset or liability account(s) with a balance have no current / non-current class: they are listed apart and are NOT in the working capital above.',
        'text_bn', 'ব্যালেন্স আছে এমন ' || n_un || 'টি সম্পদ বা দায়ের অ্যাকাউন্টে চলতি / অ-চলতি ক্লাস নেই: সেগুলো আলাদা তালিকায়, ওপরের ওয়ার্কিং ক্যাপিটালে ধরা হয়নি।'));
    end if;
  end if;
  return jsonb_build_object('as_of', as_, 'location_id', p_loc,
    'by_class', jsonb_build_object('current_assets', ca, 'current_liabilities', cl, 'non_current_assets', nca, 'non_current_liabilities', ncl, 'unclassified_assets', ua, 'unclassified_liabilities', ul,
        'totals', sums, 'working_capital', wc, 'classed_accounts', classed, 'unclassified_accounts', n_un),
    'formula', jsonb_build_object('cash', cash_, 'receivables', recv, 'inventory', inv, 'payables', pay, 'working_capital', cash_ + recv + inv - pay),
    'notes', notes_,
    'basis', jsonb_build_object('text_en', 'From the journal up to the date. By class: current assets minus current liabilities, as you classed the accounts. Formula: cash, bank and wallets + customer receivables + inventory - supplier payables, from the fixed accounts.',
      'text_bn', 'তারিখ পর্যন্ত জার্নাল থেকে। ক্লাস অনুযায়ী: আপনার দেওয়া ক্লাসে চলতি সম্পদ বিয়োগ চলতি দায়। সূত্র: ক্যাশ, ব্যাংক ও ওয়ালেট + গ্রাহকের পাওনা + মজুত - সরবরাহকারীর দেনা, নির্দিষ্ট অ্যাকাউন্ট থেকে।'));
end $$;

-- ---------- 4. export log for the CSV of the expense register and the statements (same gate as the other exports: the owner or the export_data right, plus the right to read that screen) ----------
create or replace function public.c1_export_log(p_key text, p_kind text, p_filters jsonb default '{}'::jsonb, p_rows int default 0) returns void
language plpgsql security definer set search_path = public as $$
declare sid text; f jsonb := coalesce(p_filters, '{}'::jsonb);
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_grant('export_data')) then raise exception 'not allowed'; end if;
  if p_key is null or p_key not in ('expense_register', 'stmt_pl_matrix', 'stmt_cash_flow', 'stmt_working_capital', 'coa_classes', 'recipe_cost_gaps') then raise exception 'unknown_report'; end if;
  if p_key = 'expense_register' and not public._c1_exp_view() then raise exception 'not allowed'; end if;
  if p_key in ('stmt_pl_matrix', 'stmt_cash_flow', 'stmt_working_capital', 'coa_classes') and not public._stmt_view() then raise exception 'not allowed'; end if;
  if p_key = 'recipe_cost_gaps' and not (public.is_owner() or public.rpt_grant('view_cost')) then raise exception 'not allowed'; end if;
  if p_kind is null or lower(p_kind) !~ '^[a-z0-9_]{1,20}$' then raise exception 'bad_kind'; end if;
  if length(f::text) > 4000 then f := jsonb_build_object('truncated', true); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'export', 'report', p_key, jsonb_build_object('kind', lower(p_kind), 'rows', least(greatest(coalesce(p_rows, 0), 0), 100000000), 'filters', f));
end $$;
revoke all on function public.c1_export_log(text, text, jsonb, int) from public, anon;
grant execute on function public.c1_export_log(text, text, jsonb, int) to authenticated;

revoke all on function public._c1_open_through() from public, anon, authenticated;
revoke all on function public.stmt_cash_flow(date, date, int), public.stmt_cf_drill(date, date, int, text, bigint), public.stmt_working_capital(date, int) from public, anon;
grant execute on function public.stmt_cash_flow(date, date, int), public.stmt_cf_drill(date, date, int, text, bigint), public.stmt_working_capital(date, int) to authenticated;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase445.sql
-- ============================================================
-- Phase 445 - RPT-C2 / R4 part 1 (reports #153-163): what the app order must capture - cake specification and the promised time slot.
-- Run AFTER phase 99 (needs phase61 online_orders). New file only: no old phase or function is edited. Paste twice = no error, no second row.
--
--   * order_cake_specs   one row per cake on an app order: weight (kg), flavour, message on the cake, design, photo reference. Replace = the old rows are voided, new rows added (history stays).
--   * order_promises     the promised time slot of an app order (from / to, Dhaka time). The promised DATE stays online_orders.delivery_date. Every change is a new row with a reason (append-only).
--   * c2_order_spec_save, c2_order_promise_set       write (POS enter, module online_orders_on, the order's place). Nothing here posts to the books.
--   * rule order_promise_required (OFF)             when ON an order cannot be confirmed before a promised slot exists. OFF = today.
--   * rule order_late_grace_minutes (blank)         blank = on time means delivered at or before the END of the promised slot (no grace invented).
--   * c2_orders_features()                           what the server has (the web asks once; older servers answer "no" and the screens fall back).
-- Paper form code for any printed version of the cake sheet: to be given by owner (the app sheet is a digital entry only; no new paper code is invented).
-- Helpers named _c2_* are closed to browsers; c2_can_read_orders() and c2_order_visible() are open because the row policies call them.
-- ============================================================
do $guard$ begin
  if to_regclass('public.online_orders') is null or to_regprocedure('public._i1_apply_hooks()') is null then
    raise exception 'phase445 needs phase61 (online orders) and phase99 pasted first';
  end if;
end $guard$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('order_promise_required', 'pos', 'switch', 'false', null, null, null, null, 'অর্ডার নিশ্চিত করার আগে ডেলিভারির সময়-স্লট লাগবে', 'Order confirm করার আগে promised time slot লাগবে', 'A promised time slot is needed before an order is confirmed',
  'বন্ধ থাকলে আগের মতোই; চালু করলে স্লট ছাড়া অর্ডার নিশ্চিত হবে না।', 'Off = as today. On = an app order cannot be confirmed until a promised time slot is written.', 640),
 ('order_late_grace_minutes', 'reports', 'number', null, 'min', null, 0, 1440, 'দেরি ধরার আগে কত মিনিট ছাড়', 'Late ধরার আগে কত minute ছাড়', 'Minutes of grace before a delivery counts as late',
  'ফাঁকা থাকলে স্লটের শেষ সময়ের পর দেরি ধরা হয়; কোনো ছাড় ধরা হয় না।', 'Blank = late means after the END of the promised slot; no grace is assumed.', 641)
 on conflict (key) do nothing;

-- ---------- helpers ----------
create or replace function public.c2_can_read_orders() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.rpt_grant('report_orders') or public.rpt_grant('view_reports') or public.can_do('POS', 'view'));
$$;
create or replace function public.c2_order_visible(p_order uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.online_orders o where o.id = p_order and public.can_loc(o.location_id));
$$;
create or replace function public._c2_staff() returns text language sql stable security definer set search_path = public as $$
  select staff_id from public.profiles where id = auth.uid();
$$;
-- a trail table row may only be voided (state active -> void with the void_* fields); nothing else changes, nothing is deleted
create or replace function public._c2_trail_ro() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and old.state = 'active' and new.state = 'void'
     and (to_jsonb(new) - 'state' - 'void_by' - 'void_at' - 'void_note') = (to_jsonb(old) - 'state' - 'void_by' - 'void_at' - 'void_note') then return new; end if;
  raise exception 'append_only: % is a trail, void the row instead', tg_table_name;
end $$;

-- ---------- cake specification ----------
create table if not exists public.order_cake_specs (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.online_orders(id),
  item_id uuid references public.items(id),
  weight_kg numeric check (weight_kg is null or (weight_kg > 0 and weight_kg <= 1000)),
  flavour text check (flavour is null or char_length(flavour) <= 80),
  message text check (message is null or char_length(message) <= 200),
  design text check (design is null or char_length(design) <= 300),
  photo_ref text check (photo_ref is null or char_length(photo_ref) <= 300),
  note text check (note is null or char_length(note) <= 300),
  state text not null default 'active' check (state in ('active', 'void')),
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  void_by uuid, void_at timestamptz, void_note text,
  check (weight_kg is not null or nullif(btrim(flavour), '') is not null or nullif(btrim(message), '') is not null or nullif(btrim(design), '') is not null or nullif(btrim(photo_ref), '') is not null or nullif(btrim(note), '') is not null)
);
create index if not exists order_cake_specs_order on public.order_cake_specs (order_id) where state = 'active';
drop trigger if exists order_cake_specs_ro on public.order_cake_specs;
create trigger order_cake_specs_ro before update or delete on public.order_cake_specs for each row execute function public._c2_trail_ro();
drop trigger if exists audit_order_cake_specs on public.order_cake_specs;
create trigger audit_order_cake_specs after insert or update on public.order_cake_specs for each row execute function public.log_change('id');

-- ---------- promised time slot ----------
create table if not exists public.order_promises (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.online_orders(id),
  slot_from time not null,
  slot_to time,
  reason text check (reason is null or char_length(reason) <= 300),
  state text not null default 'active' check (state in ('active', 'void')),
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  void_by uuid, void_at timestamptz, void_note text,
  check (slot_to is null or slot_to > slot_from)
);
create index if not exists order_promises_order on public.order_promises (order_id, id desc);
drop trigger if exists order_promises_ro on public.order_promises;
create trigger order_promises_ro before update or delete on public.order_promises for each row execute function public._c2_trail_ro();
drop trigger if exists audit_order_promises on public.order_promises;
create trigger audit_order_promises after insert or update on public.order_promises for each row execute function public.log_change('id');

-- the newest active promise of an order
create or replace function public._c2_promise_of(p_order uuid) returns public.order_promises language sql stable security definer set search_path = public as $$
  select * from public.order_promises where order_id = p_order and state = 'active' order by id desc limit 1;
$$;

-- optional gate: confirm needs a promised slot while the rule is ON (OFF = today)
create or replace function public._c2_promise_gate() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'confirmed' and old.status is distinct from 'confirmed' and public.rule_on('order_promise_required')
     and not exists (select 1 from public.order_promises where order_id = new.id and state = 'active') then
    raise exception 'promise_required: write the promised time slot before confirming this order';
  end if;
  return new;
end $$;
drop trigger if exists online_orders_c2_promise_gate on public.online_orders;
create trigger online_orders_c2_promise_gate before update on public.online_orders for each row when (new.status is distinct from old.status) execute function public._c2_promise_gate();

-- ---------- writers ----------
-- replace the cake specs of an open order. p_specs = [{item_id?, weight_kg?, flavour?, message?, design?, photo_ref?, note?}]; an empty array clears them.
create or replace function public.c2_order_spec_save(p_order uuid, p_specs jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; sp jsonb; n int := 0; w numeric; iid uuid; cur jsonb; nw jsonb := '[]'; fl text; ms text; dz text; ph text; nt text;
begin
  select * into o from public.online_orders where id = p_order for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  if o.status in ('delivered', 'cancelled') then raise exception 'order_closed: a delivered or cancelled order cannot change'; end if;
  if p_specs is null or jsonb_typeof(p_specs) <> 'array' or jsonb_array_length(p_specs) > 20 then raise exception 'bad_specs'; end if;
  for sp in select * from jsonb_array_elements(p_specs) loop
    w := nullif(btrim(sp ->> 'weight_kg'), '')::numeric;
    if w is not null and (w = 'NaN'::numeric or w <= 0 or w > 1000) then raise exception 'bad_weight'; end if;
    iid := nullif(btrim(sp ->> 'item_id'), '')::uuid;
    if iid is not null and not exists (select 1 from jsonb_array_elements(o.lines) l where l ->> 'item_id' = iid::text) then raise exception 'item_not_on_order'; end if;
    fl := left(nullif(btrim(sp ->> 'flavour'), ''), 80); ms := left(nullif(btrim(sp ->> 'message'), ''), 200); dz := left(nullif(btrim(sp ->> 'design'), ''), 300);
    ph := left(nullif(btrim(sp ->> 'photo_ref'), ''), 300); nt := left(nullif(btrim(sp ->> 'note'), ''), 300);
    if w is null and fl is null and ms is null and dz is null and ph is null and nt is null then raise exception 'empty_spec'; end if;
    nw := nw || jsonb_build_object('item_id', iid, 'weight_kg', w, 'flavour', fl, 'message', ms, 'design', dz, 'photo_ref', ph, 'note', nt);
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', item_id, 'weight_kg', weight_kg, 'flavour', flavour, 'message', message, 'design', design, 'photo_ref', photo_ref, 'note', note) order by id), '[]'::jsonb)
    into cur from public.order_cake_specs where order_id = o.id and state = 'active';
  if cur = nw then return jsonb_build_object('order_id', o.id, 'specs', jsonb_array_length(nw), 'noop', true); end if;
  update public.order_cake_specs set state = 'void', void_by = auth.uid(), void_at = now(), void_note = left(coalesce(nullif(btrim(p_note), ''), 'replaced'), 300) where order_id = o.id and state = 'active';
  for sp in select * from jsonb_array_elements(nw) loop
    insert into public.order_cake_specs (order_id, item_id, weight_kg, flavour, message, design, photo_ref, note, created_by, created_staff)
      values (o.id, nullif(sp ->> 'item_id', '')::uuid, nullif(sp ->> 'weight_kg', '')::numeric, sp ->> 'flavour', sp ->> 'message', sp ->> 'design', sp ->> 'photo_ref', sp ->> 'note', auth.uid(), public._c2_staff());
    n := n + 1;
  end loop;
  perform public._oo_event61(o.id, o.status, o.status, 'cake specification ' || case when n = 0 then 'cleared' else 'saved (' || n || ')' end);
  return jsonb_build_object('order_id', o.id, 'specs', n);
end $$;

-- write or change the promised time slot of an open order (a change needs a reason). Times are Dhaka clock times.
create or replace function public.c2_order_promise_set(p_order uuid, p_from time, p_to time default null, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; cur public.order_promises; id_ bigint;
begin
  select * into o from public.online_orders where id = p_order for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  if o.status in ('delivered', 'cancelled') then raise exception 'order_closed: a delivered or cancelled order cannot change'; end if;
  if p_from is null then raise exception 'slot_required'; end if;
  if p_to is not null and p_to <= p_from then raise exception 'bad_slot: the end must be after the start'; end if;
  if o.delivery_date is null then raise exception 'delivery_date_required: the promised date comes from the order delivery date'; end if;
  cur := public._c2_promise_of(o.id);
  if cur.id is not null then
    if cur.slot_from = p_from and cur.slot_to is not distinct from p_to then return jsonb_build_object('order_id', o.id, 'noop', true); end if;
    if nullif(btrim(p_reason), '') is null then raise exception 'reason_required'; end if;
  end if;
  insert into public.order_promises (order_id, slot_from, slot_to, reason, created_by, created_staff)
    values (o.id, p_from, p_to, left(nullif(btrim(p_reason), ''), 300), auth.uid(), public._c2_staff()) returning id into id_;
  perform public._oo_event61(o.id, o.status, o.status, 'promised slot ' || p_from::text || coalesce(' - ' || p_to::text, '') || coalesce(' | ' || nullif(btrim(p_reason), ''), ''));
  return jsonb_build_object('order_id', o.id, 'id', id_, 'slot_from', p_from, 'slot_to', p_to, 'date', o.delivery_date);
end $$;

-- what this server can do (the web asks once; a missing function = an older server = the old screens)
create or replace function public.c2_orders_features() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object('v', 445,
    'spec', to_regprocedure('public.c2_order_spec_save(uuid,jsonb,text)') is not null,
    'promise', to_regprocedure('public.c2_order_promise_set(uuid,time without time zone,time without time zone,text)') is not null,
    'cost', to_regprocedure('public.c2_order_cost_add(uuid,text,numeric,text,text,uuid)') is not null,
    'cancel', to_regprocedure('public.c2_order_cancel(uuid,text,text,text)') is not null,
    'advance', to_regprocedure('public.c2_order_advance_post(uuid)') is not null,
    'detail', to_regprocedure('public.c2_order_detail(uuid)') is not null,
    'online_orders_on', public.rule_on('online_orders_on'), 'promise_required', public.rule_on('order_promise_required'),
    'refund_record_on', coalesce(public.rule_on('order_refund_record_on'), false), 'advance_post_on', coalesce(public.rule_on('order_advance_post_on'), false));
end $$;

-- ---------- RLS and privileges ----------
do $$ declare t text; begin
  foreach t in array array['order_cake_specs', 'order_promises'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_sel', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.c2_can_read_orders() and public.c2_order_visible(order_id))', t || '_sel', t);
  end loop;
end $$;
do $c2$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^_?c2_' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname !~ '^_' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $c2$;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase446.sql
-- ============================================================
-- Phase 446 - RPT-C2 / R4 part 2 (reports #162, #161): the ACTUAL delivery cost of an app order.
-- Run AFTER phase 445. New file only. Paste twice = no error, no second row.
--
--   * list order_delivery_cost_kinds (rider pay, fuel, platform / courier fee, Other): chosen from the list (BUILD-RULES 4), "Other" needs a written note. The owner adds kinds through Lists.
--   * order_delivery_costs   one row per cost of one order: kind, amount, who was paid (free name), the Dhaka date, note. Append-only: a wrong row is VOIDED with a reason, never edited.
--   * c2_order_cost_add / c2_order_cost_void   write (POS enter, module online_orders_on, the order's place). Idempotent on the client id.
--   The cost is INFORMATION for order costing (delivery cost report, order profit). It does NOT post to the books: the payment is entered as an expense as today, so nothing is counted twice.
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.c2_order_spec_save(uuid,jsonb,text)') is null then raise exception 'phase446 needs phase445 pasted first'; end if;
end $guard$;

insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort, active, extra) values
 ('order_delivery_cost_kinds', 'rider_pay', 'রাইডারকে দেওয়া টাকা', 'Rider pay', 'Rider pay', 10, true, '{}'),
 ('order_delivery_cost_kinds', 'fuel', 'জ্বালানি', 'Fuel', 'Fuel', 20, true, '{}'),
 ('order_delivery_cost_kinds', 'platform_fee', 'প্ল্যাটফর্ম / কুরিয়ার ফি', 'Platform / courier fee', 'Platform / courier fee', 30, true, '{}'),
 ('order_delivery_cost_kinds', 'other', 'অন্য (লিখুন)', 'Other (write it)', 'Other (write it)', 90, true, '{}')
on conflict (list_code, value_code) do nothing;
update public.list_defs set title_bn = coalesce(title_bn, 'ডেলিভারির খরচের ধরন'), title_en = coalesce(title_en, 'Delivery cost kinds') where list_code = 'order_delivery_cost_kinds';

create table if not exists public.order_delivery_costs (
  id bigint generated always as identity primary key,
  client_id uuid,
  order_id uuid not null references public.online_orders(id),
  kind text not null,
  amount numeric not null check (amount > 0 and amount <= 1000000000),
  paid_to text check (paid_to is null or char_length(paid_to) <= 60),
  cost_date date not null,
  note text check (note is null or char_length(note) <= 300),
  state text not null default 'active' check (state in ('active', 'void')),
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  void_by uuid, void_at timestamptz, void_note text
);
create unique index if not exists order_delivery_costs_client on public.order_delivery_costs (created_by, client_id) where client_id is not null;
create index if not exists order_delivery_costs_order on public.order_delivery_costs (order_id) where state = 'active';
drop trigger if exists order_delivery_costs_ro on public.order_delivery_costs;
create trigger order_delivery_costs_ro before update or delete on public.order_delivery_costs for each row execute function public._c2_trail_ro();
drop trigger if exists audit_order_delivery_costs on public.order_delivery_costs;
create trigger audit_order_delivery_costs after insert or update on public.order_delivery_costs for each row execute function public.log_change('id');

create or replace function public.c2_order_cost_add(p_order uuid, p_kind text, p_amount numeric, p_paid_to text default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; r public.order_delivery_costs; id_ bigint; amt numeric := round(coalesce(p_amount, 0), 2);
begin
  select * into o from public.online_orders where id = p_order for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.order_delivery_costs where created_by = auth.uid() and client_id = p_client;
    if found then return jsonb_build_object('id', r.id, 'order_id', o.id, 'dup', true); end if;
  end if;
  if o.status = 'new' then raise exception 'bad_status: a delivery cost is written once the order is confirmed'; end if;
  if amt = 'NaN'::numeric or amt <= 0 or amt > 1000000000 then raise exception 'bad_amount'; end if;
  if p_kind is null or not exists (select 1 from public.option_lists where list_code = 'order_delivery_cost_kinds' and value_code = p_kind and active) then raise exception 'bad_kind'; end if;
  if p_kind = 'other' and nullif(btrim(p_note), '') is null then raise exception 'note_required: write what the other cost was'; end if;
  if char_length(coalesce(p_paid_to, '')) > 60 or char_length(coalesce(p_note, '')) > 300 then raise exception 'too_long'; end if;
  insert into public.order_delivery_costs (client_id, order_id, kind, amount, paid_to, cost_date, note, created_by, created_staff)
    values (p_client, o.id, p_kind, amt, nullif(btrim(p_paid_to), ''), public._dhaka_today(), nullif(btrim(p_note), ''), auth.uid(), public._c2_staff()) returning id into id_;
  perform public._oo_event61(o.id, o.status, o.status, 'delivery cost ' || amt::text || ' (' || p_kind || ')');
  return jsonb_build_object('id', id_, 'order_id', o.id, 'amount', amt, 'kind', p_kind);
end $$;

create or replace function public.c2_order_cost_void(p_cost bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.order_delivery_costs; o public.online_orders;
begin
  select * into c from public.order_delivery_costs where id = p_cost for update;
  if not found then raise exception 'not_found'; end if;
  select * into o from public.online_orders where id = c.order_id;
  perform public._oo_gate61(o.location_id);
  if c.state = 'void' then return jsonb_build_object('id', c.id, 'noop', true); end if;
  if nullif(btrim(p_note), '') is null or char_length(p_note) > 300 then raise exception 'reason_required'; end if;
  update public.order_delivery_costs set state = 'void', void_by = auth.uid(), void_at = now(), void_note = btrim(p_note) where id = c.id;
  perform public._oo_event61(o.id, o.status, o.status, 'delivery cost voided: ' || btrim(p_note));
  return jsonb_build_object('id', c.id, 'state', 'void');
end $$;

alter table public.order_delivery_costs enable row level security;
revoke all on public.order_delivery_costs from public, anon, authenticated;
grant select on public.order_delivery_costs to authenticated;
drop policy if exists order_delivery_costs_sel on public.order_delivery_costs;
create policy order_delivery_costs_sel on public.order_delivery_costs for select to authenticated using (public.c2_can_read_orders() and public.c2_order_visible(order_id));

do $c2$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^_?c2_' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname !~ '^_' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $c2$;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase447.sql
-- ============================================================
-- Phase 447 - RPT-C2 / R4 part 3 (report #156): an advance taken on an app order becomes a real CUSTOMER ADVANCE (account 2300) - a setting, OFF.
-- Run AFTER phase 446. New file only. Paste twice = no error, no second row.
--
--   Today (OFF, unchanged): the advance written on an app order reaches the books only when the order is delivered (it is passed to record_sale2 as the first payment); a cancelled order never reaches them.
--   ON: c2_order_advance_post(order) records the advance with the EXISTING cash_move_add('cust_advance') - cash/bank/mobile in, account 2300 customer advance, on the customer's advance list - so
--       day book, journal and the advance list show it from the day it was taken. At delivery c2_order_deliver passes only what is collected NOW to record_sale2 and then applies the advance to
--       the sale with the EXISTING cash_move_add('cust_advance_used') (Dr 2300, Cr receivable). No money is counted twice.
--   Who: the existing cash_move right (owner or grant cash_move at that place) is needed to post, void or apply - the same right the Cash and bank screen needs. Without it nothing is posted, the order
--       stays as it was, and the order shows "advance not recorded in the books yet". Delivery still works (legacy way) when the advance was never posted.
--   * rules  order_advance_post_on (OFF)  and  order_advance_post_from (blank = every order): only orders created on or after that day are posted. Blank + ON = every open order.
--   * order_advance_posts  one row per posted advance (state posted -> applied | refunded | void). The cash move itself is the money record.
--   * c2_order_advance_post / _void / _apply, c2_order_deliver, trigger online_orders_c2_advance_guard (a posted advance cannot be edited on the order; void it first).
--   Known and left alone: the customer dues lists (customer_dues, customer_ledger) count sales and sale payments only, as for every 'cust_advance_used' today; an applied advance is shown beside the
--   due in the order register and in the credit reports, never hidden. The sale made at delivery shows the advance part as DUE until the advance is applied.
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.c2_order_cost_add(uuid,text,numeric,text,text,uuid)') is null then raise exception 'phase447 needs phase446 pasted first'; end if;
end $guard$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('order_advance_post_on', 'pos', 'switch', 'false', null, null, null, null, 'অর্ডারের অ্যাডভান্স গ্রাহকের অগ্রিম হিসেবে খাতায়', 'Order-এর advance গ্রাহকের অগ্রিম হিসেবে খাতায়', 'Post an order advance as a customer advance',
  'বন্ধ থাকলে আগের মতোই: অ্যাডভান্স খাতায় ওঠে ডেলিভারির সময়। চালু করলে অ্যাডভান্স নেওয়ার দিনই ক্যাশ/ব্যাংকে আসে ও অগ্রিম (২৩০০) হিসেবে দেখা যায়।', 'Off = as today: the advance reaches the books at delivery. On = it is recorded the day it is taken (cash/bank/mobile in, account 2300).', 650),
 ('order_advance_post_from', 'pos', 'text', null, null, null, null, null, 'এই তারিখ বা তার পরের অর্ডারের অ্যাডভান্স খাতায় তুলুন', 'এই date বা পরের order-এর advance খাতায় তুলুন', 'Post advances only for orders created on or after',
  'তারিখ লিখুন YYYY-MM-DD। ফাঁকা থাকলে চালু অবস্থায় সব খোলা অর্ডার।', 'A day, YYYY-MM-DD. Blank (with the switch ON) = every open order.', 651)
 on conflict (key) do nothing;

-- the customer behind an order: found by the normalised mobile, created the same way record_sale2 creates one
create or replace function public._c2_customer_for(p_mobile text, p_name text) returns uuid language plpgsql security definer set search_path = public as $$
declare mob text := public.norm_mobile(p_mobile); c public.customers;
begin
  if mob is null or char_length(mob) < 6 then raise exception 'bad_mobile'; end if;
  select * into c from public.customers where mobile = mob for update;
  if not found then
    if nullif(btrim(p_name), '') is null then raise exception 'customer_name_required'; end if;
    insert into public.customers (mobile, name, type, created_by) values (mob, left(btrim(p_name), 80), 'retail', auth.uid()) returning * into c;
  elsif not c.active then raise exception 'customer_inactive';
  end if;
  return c.id;
end $$;

create table if not exists public.order_advance_posts (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.online_orders(id),
  customer_id uuid not null references public.customers(id),
  amount numeric not null check (amount > 0),
  mode text not null check (mode in ('cash', 'bank', 'mobile')),
  state text not null default 'posted' check (state in ('posted', 'applied', 'refunded', 'void')),
  move_id uuid not null references public.cash_moves(id),             -- the cash_moves row 'cust_advance' (the money record)
  applied_move_id uuid references public.cash_moves(id),              -- 'cust_advance_used'
  applied_sale_id uuid references public.sales(id),
  applied_amount numeric,
  refund_move_id uuid references public.cash_moves(id),               -- 'cust_advance_refund' (phase 448)
  note text check (note is null or char_length(note) <= 300),
  created_by uuid, created_staff text, created_at timestamptz not null default now(), closed_at timestamptz, closed_note text
);
create unique index if not exists order_advance_posts_live on public.order_advance_posts (order_id) where state in ('posted', 'applied');
create index if not exists order_advance_posts_order on public.order_advance_posts (order_id);
drop trigger if exists audit_order_advance_posts on public.order_advance_posts;
create trigger audit_order_advance_posts after insert or update on public.order_advance_posts for each row execute function public.log_change('id');
-- only the state and the closing fields move; nothing is deleted, no money field is edited
create or replace function public._c2_advance_post_ro() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: an advance post is never deleted'; end if;
  if old.state in ('refunded', 'void') then raise exception 'append_only: a closed advance post cannot change'; end if;
  if (to_jsonb(new) - 'state' - 'applied_move_id' - 'applied_sale_id' - 'applied_amount' - 'refund_move_id' - 'closed_at' - 'closed_note')
     is distinct from (to_jsonb(old) - 'state' - 'applied_move_id' - 'applied_sale_id' - 'applied_amount' - 'refund_move_id' - 'closed_at' - 'closed_note') then
    raise exception 'append_only: an advance post only changes state';
  end if;
  return new;
end $$;
drop trigger if exists order_advance_posts_ro on public.order_advance_posts;
create trigger order_advance_posts_ro before update or delete on public.order_advance_posts for each row execute function public._c2_advance_post_ro();

-- a posted advance is the money record: the order's advance figure cannot be edited under it
create or replace function public._c2_advance_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (new.advance is distinct from old.advance or new.advance_mode is distinct from old.advance_mode)
     and exists (select 1 from public.order_advance_posts where order_id = old.id and state in ('posted', 'applied')) then
    raise exception 'advance_posted: the advance of this order is already recorded in the books; void it first';
  end if;
  return new;
end $$;
drop trigger if exists online_orders_c2_advance_guard on public.online_orders;
create trigger online_orders_c2_advance_guard before update on public.online_orders for each row execute function public._c2_advance_guard();

create or replace function public._c2_advance_started(o public.online_orders) returns boolean language plpgsql stable security definer set search_path = public as $$
declare f text := public.rule_txt('order_advance_post_from');
begin
  if not public.rule_on('order_advance_post_on') then return false; end if;
  if f is null then return true; end if;
  if f !~ '^\d{4}-\d{2}-\d{2}$' then return false; end if;
  return (o.created_at at time zone 'Asia/Dhaka')::date >= f::date;
end $$;

create or replace function public._c2_money_mode(p_mode text) returns text language sql immutable as $$
  select case p_mode when 'cash' then 'cash' when 'mobile' then 'mobile' when 'card' then 'bank' else null end;
$$;

create or replace function public.c2_order_advance_post(p_order uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; cust uuid; mv jsonb; pid bigint; mid uuid; md text; cnt int;
begin
  select * into o from public.online_orders where id = p_order for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  if not public._c2_advance_started(o) then raise exception 'advance_post_off: the order advance posting switch is off (or starts later)'; end if;
  if o.status not in ('new', 'confirmed', 'packed') then raise exception 'order_closed: only an open order can have its advance posted'; end if;
  if o.advance <= 0 then raise exception 'no_advance'; end if;
  if exists (select 1 from public.order_advance_posts where order_id = o.id and state in ('posted', 'applied')) then
    return jsonb_build_object('order_id', o.id, 'noop', true);
  end if;
  md := public._c2_money_mode(o.advance_mode);
  if md is null then raise exception 'bad_mode'; end if;
  cust := public._c2_customer_for(o.customer_mobile, o.customer_name);
  select count(*) into cnt from public.order_advance_posts where order_id = o.id;
  mv := public.cash_move_add(o.location_id, 'cust_advance', o.advance, public._dhaka_today(), md, cust, left('online order #' || o.order_no || ' advance', 80), 'advance taken on an app order',
          md5('c2adv:' || o.id::text || ':' || cnt::text)::uuid);
  mid := (mv ->> 'id')::uuid;
  if mid is null then raise exception 'advance_not_recorded'; end if;
  insert into public.order_advance_posts (order_id, customer_id, amount, mode, move_id, created_by, created_staff)
    values (o.id, cust, o.advance, md, mid, auth.uid(), public._c2_staff()) returning id into pid;
  perform public._oo_event61(o.id, o.status, o.status, 'advance ' || o.advance::text || ' recorded as a customer advance');
  return jsonb_build_object('order_id', o.id, 'post_id', pid, 'move_id', mid, 'amount', o.advance, 'mode', md);
end $$;

-- take the posted advance back out of the books (before delivery). Voids the cash move (needs the cash_move right); the order advance figure can then be edited again.
create or replace function public.c2_order_advance_void(p_order uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; a public.order_advance_posts;
begin
  select * into o from public.online_orders where id = p_order for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  select * into a from public.order_advance_posts where order_id = o.id and state = 'posted' for update;
  if not found then raise exception 'no_posted_advance'; end if;
  if nullif(btrim(p_note), '') is null or char_length(p_note) > 300 then raise exception 'reason_required'; end if;
  perform public.cash_move_void(a.move_id, 'order advance voided: ' || btrim(p_note));
  update public.order_advance_posts set state = 'void', closed_at = now(), closed_note = btrim(p_note) where id = a.id;
  perform public._oo_event61(o.id, o.status, o.status, 'posted advance voided: ' || btrim(p_note));
  return jsonb_build_object('order_id', o.id, 'state', 'void');
end $$;

-- apply a posted advance to the sale of a delivered order (cust_advance_used: Dr 2300, Cr receivable; no money moves)
create or replace function public.c2_order_advance_apply(p_order uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; a public.order_advance_posts; s public.sales; paid numeric; due numeric; amt numeric; mv jsonb;
begin
  select * into o from public.online_orders where id = p_order for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  select * into a from public.order_advance_posts where order_id = o.id and state = 'posted' for update;
  if not found then
    if exists (select 1 from public.order_advance_posts where order_id = o.id and state = 'applied') then return jsonb_build_object('order_id', o.id, 'noop', true); end if;
    raise exception 'no_posted_advance';
  end if;
  if o.status <> 'delivered' or o.sale_id is null then raise exception 'bad_status: the advance is applied to the sale of a delivered order'; end if;
  select * into s from public.sales where id = o.sale_id;
  select coalesce(sum(amount), 0) into paid from public.sale_payments where sale_id = s.id and not voided;
  due := greatest(s.total - paid, 0);
  amt := least(a.amount, due);
  if amt <= 0 then raise exception 'nothing_to_apply: the sale has no amount left to cover'; end if;
  mv := public.cash_move_add(o.location_id, 'cust_advance_used', amt, public._dhaka_today(), null, a.customer_id, left('online order #' || o.order_no || ' applied to receipt ' || s.receipt, 80),
          'advance applied to the delivered order sale', md5('c2use:' || a.id::text)::uuid);
  update public.order_advance_posts set state = 'applied', applied_move_id = (mv ->> 'id')::uuid, applied_sale_id = s.id, applied_amount = amt, closed_at = now() where id = a.id;
  perform public._oo_event61(o.id, o.status, o.status, 'advance ' || amt::text || ' applied to receipt ' || s.receipt);
  return jsonb_build_object('order_id', o.id, 'sale_id', s.id, 'applied', amt, 'left_on_advance', a.amount - amt);
end $$;

-- deliver: the existing online_order_deliver while the advance was never posted (identical result); with a posted advance the sale is made WITHOUT the advance payment and the advance is applied after.
create or replace function public.c2_order_deliver(p_id uuid, p_payments jsonb default '[]') returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; a public.order_advance_posts; sl jsonb := '[]'; ln jsonb; res jsonb; sid uuid; ap jsonb; can_apply boolean;
begin
  select * into o from public.online_orders where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  select * into a from public.order_advance_posts where order_id = o.id and state = 'posted';
  if not found or o.sale_id is not null then
    return public.online_order_deliver(p_id, p_payments) || jsonb_build_object('advance_posted', false);
  end if;
  if o.status <> 'packed' then raise exception 'bad_status: only a packed order can be delivered (now %)', o.status; end if;
  if p_payments is not null and jsonb_typeof(p_payments) <> 'array' then raise exception 'bad_payments'; end if;
  for ln in select * from jsonb_array_elements(o.lines) loop
    sl := sl || jsonb_build_object('item_id', ln ->> 'item_id', 'qty', (ln ->> 'qty')::numeric, 'price', (ln ->> 'price')::numeric);
  end loop;
  if o.delivery_charge > 0 then sl := sl || jsonb_build_object('name', 'Delivery charge', 'amount', o.delivery_charge); end if;
  res := public.record_sale2(o.sale_client, o.location_id, sl, o.discount, coalesce(p_payments, '[]'::jsonb), o.customer_mobile, o.customer_name, 'retail', 'Online order #' || o.order_no, false, null);
  sid := (res ->> 'id')::uuid;
  if exists (select 1 from public.online_orders x where x.sale_id = sid and x.id <> o.id) then raise exception 'sale_already_linked'; end if;
  update public.online_orders set status = 'delivered', sale_id = sid, delivered_by = auth.uid(), delivered_at = now(), updated_at = now() where id = o.id;
  perform public._oo_event61(o.id, 'packed', 'delivered', 'sale receipt ' || (res ->> 'receipt') || ' (advance ' || a.amount::text || ' posted earlier)');
  can_apply := public.is_owner() or public.has_grant('cash_move', o.location_id);
  if can_apply then ap := public.c2_order_advance_apply(o.id); end if;
  return jsonb_build_object('id', o.id, 'status', 'delivered', 'sale_id', sid, 'receipt', res -> 'receipt', 'total', res -> 'total', 'paid', res -> 'paid', 'due', res -> 'due',
    'advance_posted', true, 'advance_applied', can_apply, 'advance_apply', ap);
end $$;

alter table public.order_advance_posts enable row level security;
revoke all on public.order_advance_posts from public, anon, authenticated;
grant select on public.order_advance_posts to authenticated;
drop policy if exists order_advance_posts_sel on public.order_advance_posts;
create policy order_advance_posts_sel on public.order_advance_posts for select to authenticated using (public.c2_can_read_orders() and public.c2_order_visible(order_id));

do $c2$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^_?c2_' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname !~ '^_' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $c2$;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase448.sql
-- ============================================================
-- Phase 448 - RPT-C2 / R4 part 4 (report #157): cancelling an app order with advance_fate = refund makes a REAL money record.
-- Run AFTER phase 447. New file only. Paste twice = no error, no second row.
--
--   Today (switch OFF, unchanged): online_order_cancel stores advance_fate and posts nothing - no cash move, no journal line, no day-book line.
--   ON (rule order_refund_record_on): every cancelled order with advance_fate = refund and an advance gets ONE refund row (state due) the moment it is cancelled - whichever screen cancelled it
--       (trigger online_orders_c2_refund_due). c2_order_cancel then pays it at once when the person may move money (owner or grant cash_move at that place); otherwise the refund waits as "due" in the
--       refund list for a person who may. Paying uses ONLY the existing cash_move_add:
--         * advance already posted (phase 447): one 'cust_advance_refund' (account 2300 debit, cash/bank/mobile out);
--         * advance never posted: two moves dated today and labelled so - 'cust_advance' (the money that came in with the order, not recorded before) then 'cust_advance_refund' (it goes out): net zero on the
--           books, but the cash-in and cash-out are both visible in the day book on the day it was found.
--   advance_fate adjust = the advance stays a customer advance when it was posted (nothing to do); income with a posted advance is refused (the accountant makes that journal by hand: 2300 -> income).
--   * rule order_refund_record_on (OFF)    * order_refunds  one row per refund (due -> paid | void), the money records are linked by id
--   * c2_order_cancel(order, reason, fate, refund_mode)   * c2_order_refund_pay(order, mode)   * c2_order_refund_void(order, note)   * c2_order_refunds_list(from, to, loc, state)
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.c2_order_advance_post(uuid)') is null then raise exception 'phase448 needs phase447 pasted first'; end if;
end $guard$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('order_refund_record_on', 'pos', 'switch', 'false', null, null, null, null, 'বাতিল অর্ডারের অ্যাডভান্স ফেরত টাকার রেকর্ড হিসেবে লিখুন', 'Cancel order-এর advance ফেরত real money record হিসেবে লিখুন', 'Record the refund of a cancelled order advance as real money',
  'বন্ধ থাকলে আগের মতোই: ফেরত বেছে নিলে কোনো টাকার রেকর্ড হয় না। চালু করলে ফেরত রেকর্ড তৈরি হয়, ক্যাশ-অধিকার থাকা কেউ টাকা দিলে ক্যাশ/ব্যাংক খাতায় ওঠে।', 'Off = as today: choosing refund writes no money record. On = a refund record is made; a person with the cash right pays it and it reaches the day book and the journal.', 660)
 on conflict (key) do nothing;

create table if not exists public.order_refunds (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.online_orders(id),
  customer_id uuid references public.customers(id),
  amount numeric not null check (amount > 0),
  refund_mode text not null check (refund_mode in ('cash', 'bank', 'mobile')),
  state text not null default 'due' check (state in ('due', 'paid', 'void')),
  advance_post_id bigint references public.order_advance_posts(id),
  in_move_id uuid references public.cash_moves(id),       -- 'cust_advance' written now when the advance had never been posted
  out_move_id uuid references public.cash_moves(id),      -- 'cust_advance_refund'
  note text check (note is null or char_length(note) <= 300),
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  paid_by uuid, paid_staff text, paid_at timestamptz, void_by uuid, void_at timestamptz, void_note text
);
create unique index if not exists order_refunds_live on public.order_refunds (order_id) where state in ('due', 'paid');
create index if not exists order_refunds_state on public.order_refunds (state);
drop trigger if exists audit_order_refunds on public.order_refunds;
create trigger audit_order_refunds after insert or update on public.order_refunds for each row execute function public.log_change('id');
create or replace function public._c2_refund_ro() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: a refund record is never deleted'; end if;
  if old.state <> 'due' then raise exception 'append_only: a paid or void refund cannot change'; end if;
  if (to_jsonb(new) - 'state' - 'refund_mode' - 'customer_id' - 'advance_post_id' - 'in_move_id' - 'out_move_id' - 'paid_by' - 'paid_staff' - 'paid_at' - 'void_by' - 'void_at' - 'void_note' - 'note')
     is distinct from (to_jsonb(old) - 'state' - 'refund_mode' - 'customer_id' - 'advance_post_id' - 'in_move_id' - 'out_move_id' - 'paid_by' - 'paid_staff' - 'paid_at' - 'void_by' - 'void_at' - 'void_note' - 'note') then
    raise exception 'append_only: the amount and the order of a refund cannot change';
  end if;
  return new;
end $$;
drop trigger if exists order_refunds_ro on public.order_refunds;
create trigger order_refunds_ro before update or delete on public.order_refunds for each row execute function public._c2_refund_ro();

-- every cancelled order with fate refund gets its refund row while the switch is ON, whichever screen cancelled it
create or replace function public._c2_refund_due() returns trigger language plpgsql security definer set search_path = public as $$
declare md text;
begin
  if new.status = 'cancelled' and old.status is distinct from 'cancelled' and new.advance_fate = 'refund' and new.advance > 0 and public.rule_on('order_refund_record_on')
     and not exists (select 1 from public.order_refunds where order_id = new.id and state in ('due', 'paid')) then
    md := coalesce(public._c2_money_mode(new.advance_mode), 'cash');
    insert into public.order_refunds (order_id, amount, refund_mode, created_by, created_staff, advance_post_id)
      values (new.id, new.advance, md, auth.uid(), public._c2_staff(), (select id from public.order_advance_posts where order_id = new.id and state = 'posted'));
  end if;
  return null;
end $$;
drop trigger if exists online_orders_c2_refund_due on public.online_orders;
create trigger online_orders_c2_refund_due after update on public.online_orders for each row when (new.status is distinct from old.status) execute function public._c2_refund_due();

-- pay a due refund through the existing cash_move_add (its own right check applies: owner or grant cash_move at the place)
create or replace function public._c2_refund_pay(p_refund bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.order_refunds; o public.online_orders; a public.order_advance_posts; cust uuid; mv jsonb; inmv jsonb; outid uuid; inid uuid; inmode text;
begin
  select * into r from public.order_refunds where id = p_refund for update;
  if not found then raise exception 'not_found'; end if;
  if r.state <> 'due' then return jsonb_build_object('id', r.id, 'state', r.state, 'noop', true); end if;
  select * into o from public.online_orders where id = r.order_id;
  select * into a from public.order_advance_posts where order_id = o.id and state = 'posted' for update;
  cust := coalesce(a.customer_id, public._c2_customer_for(o.customer_mobile, o.customer_name));
  if a.id is null then
    inmode := coalesce(public._c2_money_mode(o.advance_mode), r.refund_mode);
    inmv := public.cash_move_add(o.location_id, 'cust_advance', r.amount, public._dhaka_today(), inmode, cust, left('online order #' || o.order_no || ' advance (found at refund)', 80),
              'advance of a cancelled order, recorded now because it was not recorded when it was taken', md5('c2refin:' || r.id::text)::uuid);
    inid := (inmv ->> 'id')::uuid;
  end if;
  mv := public.cash_move_add(o.location_id, 'cust_advance_refund', r.amount, public._dhaka_today(), r.refund_mode, cust, left('online order #' || o.order_no || ' refund', 80),
          'advance refunded after the order was cancelled', md5('c2refout:' || r.id::text)::uuid);
  outid := (mv ->> 'id')::uuid;
  update public.order_refunds set state = 'paid', customer_id = cust, in_move_id = inid, out_move_id = outid, advance_post_id = a.id, paid_by = auth.uid(), paid_staff = public._c2_staff(), paid_at = now() where id = r.id;
  if a.id is not null then update public.order_advance_posts set state = 'refunded', refund_move_id = outid, closed_at = now(), closed_note = 'refunded after the order was cancelled' where id = a.id; end if;
  perform public._oo_event61(o.id, o.status, o.status, 'advance ' || r.amount::text || ' refunded (' || r.refund_mode || ')');
  return jsonb_build_object('id', r.id, 'state', 'paid', 'amount', r.amount, 'mode', r.refund_mode, 'out_move_id', outid, 'in_move_id', inid);
end $$;

create or replace function public._c2_can_move_money(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and public.can_loc(p_loc) and (public.is_owner() or public.has_grant('cash_move', p_loc));
$$;

create or replace function public.c2_order_cancel(p_id uuid, p_reason text, p_advance_fate text default 'none', p_refund_mode text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; v jsonb; r public.order_refunds; paid jsonb; fate text := coalesce(p_advance_fate, 'none');
begin
  select * into o from public.online_orders where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  if p_refund_mode is not null and p_refund_mode not in ('cash', 'bank', 'mobile') then raise exception 'bad_mode'; end if;
  if fate = 'income' and exists (select 1 from public.order_advance_posts where order_id = o.id and state = 'posted') then
    raise exception 'advance_posted_income: the advance is in the books as a customer advance; choose refund or adjust, or ask the accountant to move it to income';
  end if;
  v := public.online_order_cancel(p_id, p_reason, p_advance_fate);
  select * into r from public.order_refunds where order_id = o.id and state = 'due';
  if not found then
    return v || jsonb_build_object('refund', case when fate = 'refund' and o.advance > 0 and not public.rule_on('order_refund_record_on') then 'not_recorded'
                                                  when fate = 'adjust' and exists (select 1 from public.order_advance_posts where order_id = o.id and state = 'posted') then 'held_as_customer_advance' else null end);
  end if;
  if p_refund_mode is not null and p_refund_mode <> r.refund_mode then update public.order_refunds set refund_mode = p_refund_mode where id = r.id; end if;
  if public._c2_can_move_money(o.location_id) then
    paid := public._c2_refund_pay(r.id);
    return v || jsonb_build_object('refund', 'paid', 'refund_id', r.id, 'refund_detail', paid);
  end if;
  return v || jsonb_build_object('refund', 'due', 'refund_id', r.id);
end $$;

-- pay a refund that is waiting (a person with the cash right); the mode may be changed at that moment
create or replace function public.c2_order_refund_pay(p_order uuid, p_mode text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; r public.order_refunds;
begin
  select * into o from public.online_orders where id = p_order;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  if p_mode is not null and p_mode not in ('cash', 'bank', 'mobile') then raise exception 'bad_mode'; end if;
  select * into r from public.order_refunds where order_id = o.id and state in ('due', 'paid');
  if not found then raise exception 'no_refund_due'; end if;
  if r.state = 'paid' then return jsonb_build_object('id', r.id, 'state', 'paid', 'noop', true); end if;
  if not public._c2_can_move_money(o.location_id) then raise exception 'not allowed'; end if;
  if p_mode is not null and p_mode <> r.refund_mode then update public.order_refunds set refund_mode = p_mode where id = r.id; end if;
  return public._c2_refund_pay(r.id);
end $$;

-- the customer waived the refund / it was settled another way: close the due row with a reason (owner or the cash right). The advance is then still to be settled by hand - the report shows it.
create or replace function public.c2_order_refund_void(p_order uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; r public.order_refunds;
begin
  select * into o from public.online_orders where id = p_order;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  if not public._c2_can_move_money(o.location_id) then raise exception 'not allowed'; end if;
  if nullif(btrim(p_note), '') is null or char_length(p_note) > 300 then raise exception 'reason_required'; end if;
  select * into r from public.order_refunds where order_id = o.id and state = 'due' for update;
  if not found then raise exception 'no_refund_due'; end if;
  update public.order_refunds set state = 'void', void_by = auth.uid(), void_at = now(), void_note = btrim(p_note) where id = r.id;
  perform public._oo_event61(o.id, o.status, o.status, 'refund closed without payment: ' || btrim(p_note));
  return jsonb_build_object('id', r.id, 'state', 'void');
end $$;

-- the refund list (read): who is owed what, paid or waiting. Needs the order report access; rows only for places the person may see.
create or replace function public.c2_order_refunds_list(p_from date default null, p_to date default null, p_loc int default null, p_state text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.c2_can_read_orders() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  return jsonb_build_object('module_on', public.rule_on('online_orders_on'), 'record_on', public.rule_on('order_refund_record_on'), 'rows', coalesce((
    select jsonb_agg(to_jsonb(z) order by z.created_at desc) from (
      select r.id, r.order_id, o.order_no, o.location_id, o.customer_name, r.amount, r.refund_mode, r.state, r.created_at, r.paid_at, r.in_move_id is not null as found_at_refund, r.void_note
        from public.order_refunds r join public.online_orders o on o.id = r.order_id
       where public.can_loc(o.location_id) and (p_loc is null or o.location_id = p_loc) and (p_state is null or r.state = p_state)
         and (p_from is null or (r.created_at at time zone 'Asia/Dhaka')::date >= p_from) and (p_to is null or (r.created_at at time zone 'Asia/Dhaka')::date <= p_to)
       order by r.created_at desc limit 500) z), '[]'::jsonb));
end $$;

alter table public.order_refunds enable row level security;
revoke all on public.order_refunds from public, anon, authenticated;
grant select on public.order_refunds to authenticated;
drop policy if exists order_refunds_sel on public.order_refunds;
create policy order_refunds_sel on public.order_refunds for select to authenticated using (public.c2_can_read_orders() and public.c2_order_visible(order_id));

do $c2$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^_?c2_' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname !~ '^_' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $c2$;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase449.sql
-- ============================================================
-- Phase 449 - RPT-C2 / R4 part 5 (reports #153 order register, #155 cake order register, #156 advance and outstanding order balances). READ ONLY.
-- Run AFTER phase 448. New file only. Paste twice = no error.
--
--   _c2_orders_base(from, to, loc, by)   the ONE normalised row list the order reports read: app orders (online_orders), paper form 20-1 (one row per order sheet) and paper form 20-6 (one row per ledger line).
--                                        The three sources are never merged: every row carries `source`. A sheet written on paper AND typed in the app shows twice, once per source (stated on screen).
--   c2_order_register(...)   #153    c2_cake_register(...)   #155    c2_order_balances(...)   #156    c2_order_detail(order)   drill-down of one app order
--   Balance rules (the old list `online_orders_list` is left as it is): open order = total - advance; delivered = what is still due on its sale after payments and after a posted advance that was applied
--   (a delivered order no longer shows as owed); cancelled = 0 owed, the advance is shown by state (refunded, refund due, refund not recorded, kept for adjustment, taken as income).
--   Every report is open to the existing order-report access (owner, report_orders, view_reports, or POS view) and only shows the places the person may see. When the online order module is not
--   switched on the answer says so (notes: module_off) and still returns the paper rows - nothing is hidden. Cost columns need the cost right (rpt_cost_ok).
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.c2_order_cancel(uuid,text,text,text)') is null then raise exception 'phase449 needs phase448 pasted first'; end if;
end $guard$;

create or replace function public._c2_date(p text) returns date language plpgsql immutable as $$
begin if p ~ '^\d{4}-\d{2}-\d{2}$' then return p::date; end if; return null; exception when others then return null; end $$;
create or replace function public._c2_time(p text) returns time language plpgsql immutable as $$
begin if p ~ '^\d{1,2}:\d{2}' then return substring(p from '^\d{1,2}:\d{2}')::time; end if; return null; exception when others then return null; end $$;
create or replace function public._c2_num(p jsonb) returns numeric language sql immutable as $$
  select case when jsonb_typeof(p) = 'number' then (p #>> '{}')::numeric when jsonb_typeof(p) = 'string' and (p #>> '{}') ~ '^-?[0-9]+(\.[0-9]+)?$' then (p #>> '{}')::numeric end;
$$;
-- one date range check for every order / customer / staff report
create or replace function public._c2_range(p_from date, p_to date) returns void language plpgsql immutable as $$
begin
  if p_from is null or p_to is null or p_to < p_from then raise exception 'bad_date: from and to are required and to is not before from'; end if;
  if p_to - p_from > 1100 then raise exception 'bad_date: at most 1100 days in one report'; end if;
end $$;

create or replace function public._c2_orders_base(p_from date, p_to date, p_loc int default null, p_by text default 'order') returns table (
  source text, ref text, order_id uuid, entry_id uuid, line_no int, loc int, order_date date, created_at timestamptz,
  customer_name text, customer_mobile text, channel text, order_type text, status text, delivery_mode text, delivery_by text,
  promised_date date, promised_from time, promised_to time, delivered_at timestamptz, delivered_date date,
  total numeric, discount numeric, delivery_charge numeric, advance numeric, balance numeric, balance_basis text, advance_state text,
  sale_id uuid, receipt int, has_spec boolean, cancel_reason text, advance_fate text, delivery_cost numeric)
language plpgsql stable security definer set search_path = public as $$
declare mob boolean := public.can_do('POS', 'view') or public.rpt_mobile_ok();
begin
  return query
  select 'app'::text, '#' || o.order_no::text, o.id, null::uuid, null::int, o.location_id, (o.created_at at time zone 'Asia/Dhaka')::date, o.created_at,
         o.customer_name, case when mob then o.customer_mobile end, o.channel,
         case when exists (select 1 from public.order_cake_specs c where c.order_id = o.id and c.state = 'active') then 'cake' else 'normal' end,
         o.status, o.delivery_mode, o.delivery_by, o.delivery_date, pr.slot_from, pr.slot_to, o.delivered_at, (o.delivered_at at time zone 'Asia/Dhaka')::date,
         o.subtotal - o.discount + o.delivery_charge, o.discount, o.delivery_charge, o.advance,
         case o.status when 'delivered' then case when s.id is null then null when s.status = 'void' then 0
                                                  else greatest(s.total - sp.paid - coalesce(case when ap.state = 'applied' then ap.applied_amount end, 0), 0) end
                       when 'cancelled' then 0 else o.subtotal - o.discount + o.delivery_charge - o.advance end,
         case o.status when 'delivered' then case when s.id is null then 'sale_missing' when s.status = 'void' then 'sale_voided' when ap.state = 'applied' then 'sale_due_after_payments_and_applied_advance' else 'sale_due_after_payments' end
                       when 'cancelled' then 'cancelled' else 'total_minus_advance' end,
         case when o.advance = 0 then 'none'
              when o.status in ('new', 'confirmed', 'packed') then case when ap.state = 'posted' then 'held_in_books' else 'held_not_in_books' end
              when o.status = 'delivered' then case when ap.state = 'applied' then 'applied_to_sale' when ap.state = 'posted' then 'held_not_applied' else 'paid_into_sale' end
              else case rf.state when 'paid' then 'refunded' when 'due' then 'refund_due' when 'void' then 'refund_closed'
                                 else case o.advance_fate when 'refund' then 'refund_not_recorded' when 'adjust' then case when ap.state = 'posted' then 'kept_as_customer_advance' else 'kept_for_adjustment' end
                                                          when 'income' then 'taken_as_income' else 'unknown' end end end,
         o.sale_id, s.receipt, exists (select 1 from public.order_cake_specs c where c.order_id = o.id and c.state = 'active'), o.cancel_reason, o.advance_fate,
         (select sum(c.amount) from public.order_delivery_costs c where c.order_id = o.id and c.state = 'active')
    from public.online_orders o
    left join public.sales s on s.id = o.sale_id
    left join lateral (select coalesce(sum(p.amount), 0) as paid from public.sale_payments p where p.sale_id = s.id and not p.voided) sp on true
    left join public.order_advance_posts ap on ap.order_id = o.id and ap.state in ('posted', 'applied')
    left join lateral (select r.state from public.order_refunds r where r.order_id = o.id order by r.id desc limit 1) rf on true
    left join lateral (select x.slot_from, x.slot_to from public.order_promises x where x.order_id = o.id and x.state = 'active' order by x.id desc limit 1) pr on true
   where public.can_loc(o.location_id) and (p_loc is null or o.location_id = p_loc)
     and case when p_by = 'promised' then o.delivery_date between p_from and p_to else (o.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to end;

  return query
  select 'paper_20_1'::text, '20-1/' || e.serial::text, null::uuid, e.id, null::int, e.location_id, e.entry_date, e.created_at,
         nullif(btrim(e.data ->> 'cust_name'), ''), case when mob then nullif(btrim(e.data ->> 'cust_phone'), '') end, nullif(btrim(e.data ->> 'channel'), ''),
         case when e.data ->> 'order_type' = 'custom' then 'cake' else coalesce(nullif(e.data ->> 'order_type', ''), 'normal') end,
         case when (e.data ->> 'not_collected') = 'true' then 'not_collected' when (e.data ->> 'cust_signed') = 'true' then 'handed' else 'open' end,
         nullif(e.data ->> 'deliv_mode', ''), nullif(e.data ->> 'deliv_by', ''),
         public._c2_date(e.data ->> 'deliv_date'), public._c2_time(e.data ->> 'deliv_time'), null::time, null::timestamptz, null::date,
         t.total, t.disc, null::numeric, t.adv,
         case when (e.data ->> 'not_collected') = 'true' then 0
              when (e.data ->> 'cust_signed') = 'true' then case when t.total is null then null when public._c2_num(e.data -> 'due_paid') is null then null else greatest(t.total - t.disc - t.adv - public._c2_num(e.data -> 'due_paid'), 0) end
              else case when t.total is null then null else t.total - t.disc - t.adv end end,
         case when (e.data ->> 'not_collected') = 'true' then 'cancelled_on_sheet' when (e.data ->> 'cust_signed') = 'true' then case when public._c2_num(e.data -> 'due_paid') is null then 'due_payment_not_written' else 'total_minus_advance_minus_due_paid' end else 'total_minus_advance' end,
         case when t.adv = 0 then 'none' when (e.data ->> 'not_collected') = 'true' then coalesce(e.data ->> 'adv_fate', 'unknown') else 'on_sheet' end,
         null::uuid, null::int, null::boolean, nullif(e.data ->> 'fate_reason', ''), nullif(e.data ->> 'adv_fate', ''), null::numeric
    from public.entries e
    cross join lateral (select public._c2_num(e.data -> 'total') as total, coalesce(public._c2_num(e.data -> 'discount'), 0) as disc, coalesce(public._c2_num(e.data -> 'advance'), 0) as adv) t
   where e.form_code = '20-1' and e.status in ('submitted', 'approved') and public.can_loc(e.location_id) and (p_loc is null or e.location_id = p_loc)
     and case when p_by = 'promised' then public._c2_date(e.data ->> 'deliv_date') between p_from and p_to else e.entry_date between p_from and p_to end;

  return query
  select 'paper_20_6'::text, '20-6/' || e.serial::text || '/' || l.ord::text, null::uuid, e.id, l.ord::int, e.location_id, e.entry_date, e.created_at,
         null::text, null::text, nullif(lower(btrim(l.v ->> 'platform')), ''), 'normal'::text, coalesce(nullif(l.v ->> 'outcome', ''), 'not_written'),
         null::text, nullif(btrim(l.v ->> 'delivery'), ''), null::date, null::time, null::time, null::timestamptz, null::date,
         public._c2_num(l.v -> 'amt'), null::numeric, public._c2_num(l.v -> 'dcharge'), null::numeric, null::numeric, 'ledger_line'::text, 'none'::text,
         null::uuid, null::int, null::boolean, null::text, null::text, null::numeric
    from public.entries e
    cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) with ordinality as l(v, ord)
   where e.form_code = '20-6' and e.status in ('submitted', 'approved') and public.can_loc(e.location_id) and (p_loc is null or e.location_id = p_loc)
     and p_by <> 'promised' and e.entry_date between p_from and p_to;
end $$;

-- notes every order report carries (codes the web turns into words)
create or replace function public._c2_order_notes(p_paper boolean default true) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare n jsonb := '[]'::jsonb;
begin
  if not public.rule_on('online_orders_on') then n := n || '"module_off"'::jsonb; end if;
  if p_paper then n := n || '"sources_not_merged"'::jsonb; end if;
  if not public.rpt_cost_ok() then n := n || '"cost_hidden"'::jsonb; end if;
  if not (public.can_do('POS', 'view') or public.rpt_mobile_ok()) then n := n || '"mobile_hidden"'::jsonb; end if;
  return n;
end $$;

-- #153 the unified order register
create or replace function public.c2_order_register(p_from date, p_to date, p_loc int default null, p_source text default null, p_status text default null, p_by text default 'order', p_limit int default 500) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lim int := least(greatest(coalesce(p_limit, 500), 1), 2000); rows jsonb; tot jsonb; n int; cost boolean := public.rpt_cost_ok();
begin
  if not public.c2_can_read_orders() then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_source is not null and p_source not in ('app', 'paper_20_1', 'paper_20_6') then raise exception 'bad_filter'; end if;
  if p_by not in ('order', 'promised') then raise exception 'bad_filter'; end if;
  with b as (select x.* from public._c2_orders_base(p_from, p_to, p_loc, p_by) x where (p_source is null or x.source = p_source) and (p_status is null or x.status = p_status)),
       t as (select * from b order by order_date desc, source, ref limit lim)
  select (select coalesce(jsonb_agg(case when cost then to_jsonb(r) else to_jsonb(r) - 'delivery_cost' end order by r.order_date desc, r.source, r.ref), '[]'::jsonb) from t r),
         (select count(*) from b),
         (select coalesce(jsonb_object_agg(q.source, q.v), '{}'::jsonb) from (
            select g.source, jsonb_build_object('rows', count(*), 'total', sum(g.total), 'advance', sum(g.advance), 'balance', sum(g.balance),
                   'rows_without_total', count(*) filter (where g.total is null), 'rows_without_balance', count(*) filter (where g.balance is null)) as v from b g group by g.source) q)
    into rows, n, tot;
  return jsonb_build_object('from', p_from, 'to', p_to, 'by', p_by, 'module_on', public.rule_on('online_orders_on'), 'notes', public._c2_order_notes(true),
    'truncated', n > lim, 'row_count', n, 'totals_by_source', tot, 'rows', rows);
end $$;

-- #155 the cake / custom order register: app cake specs next to paper 20-1 sheets of type custom
create or replace function public.c2_cake_register(p_from date, p_to date, p_loc int default null, p_source text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows jsonb; noscap int;
begin
  if not public.c2_can_read_orders() then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_source is not null and p_source not in ('app', 'paper_20_1') then raise exception 'bad_filter'; end if;
  select coalesce(jsonb_agg(to_jsonb(z) order by z.order_date desc, z.ref, z.line), '[]'::jsonb) into rows from (
    select 'app'::text as source, b.ref, b.order_id, null::uuid as entry_id, c.id::int as line, b.order_date, b.loc, b.customer_name, b.status, b.promised_date, b.promised_from, b.promised_to, b.delivery_mode,
           (select l ->> 'name' from public.online_orders o2, jsonb_array_elements(o2.lines) l where o2.id = b.order_id and l ->> 'item_id' = c.item_id::text limit 1) as item_name,
           c.weight_kg, c.flavour, c.message, c.design, c.photo_ref, c.note, null::text as description
      from public._c2_orders_base(p_from, p_to, p_loc, 'order') b join public.order_cake_specs c on c.order_id = b.order_id and c.state = 'active'
     where b.source = 'app' and (p_source is null or p_source = 'app')
    union all
    select 'paper_20_1', b.ref, null::uuid, b.entry_id, i.ord::int, b.order_date, b.loc, b.customer_name, b.status, b.promised_date, b.promised_from, null::time, b.delivery_mode,
           nullif(btrim(i.v ->> 'item'), ''), null::numeric, null::text, nullif(btrim(i.v ->> 'msg'), ''), nullif(btrim(i.v ->> 'design'), ''), null::text, nullif(btrim(i.v ->> 'special'), ''), nullif(btrim(i.v ->> 'desc'), '')
      from public._c2_orders_base(p_from, p_to, p_loc, 'order') b join public.entries e on e.id = b.entry_id
      cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'items') = 'array' then e.data -> 'items' else '[]'::jsonb end) with ordinality as i(v, ord)
     where b.source = 'paper_20_1' and b.order_type = 'cake' and (p_source is null or p_source = 'paper_20_1')
     order by 6 desc, 2, 5 limit 2000) z;
  select count(*) into noscap from public._c2_orders_base(p_from, p_to, p_loc, 'order') b where b.source = 'app' and not b.has_spec and b.status <> 'cancelled';
  return jsonb_build_object('from', p_from, 'to', p_to, 'module_on', public.rule_on('online_orders_on'), 'notes', public._c2_order_notes(true), 'rows', rows,
    'app_orders_without_spec', noscap);
end $$;

-- #156 advance payments and outstanding order balances
create or replace function public.c2_order_balances(p_from date, p_to date, p_loc int default null, p_open_only boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows jsonb; sm jsonb;
begin
  if not public.c2_can_read_orders() then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  select coalesce(jsonb_agg(to_jsonb(z) order by z.order_date desc, z.source, z.ref), '[]'::jsonb) into rows from (
    select b.source, b.ref, b.order_id, b.entry_id, b.loc, b.order_date, b.customer_name, b.customer_mobile, b.status, b.total, b.discount, b.advance, b.balance, b.balance_basis, b.advance_state, b.sale_id, b.receipt,
           (b.balance is not null and b.balance > 0 and b.status in ('delivered', 'handed')) as owed_after_delivery
      from public._c2_orders_base(p_from, p_to, p_loc, 'order') b
     where b.source in ('app', 'paper_20_1') and (b.advance > 0 or coalesce(b.balance, 0) > 0)
       and (not p_open_only or b.status in ('new', 'confirmed', 'packed', 'open'))
     order by b.order_date desc limit 1000) z;
  select jsonb_build_object(
    'app', jsonb_build_object(
      'advance_held_open_orders', coalesce(sum(b.advance) filter (where b.source = 'app' and b.status in ('new', 'confirmed', 'packed')), 0),
      'balance_to_collect_open_orders', coalesce(sum(b.balance) filter (where b.source = 'app' and b.status in ('new', 'confirmed', 'packed')), 0),
      'still_owed_after_delivery', coalesce(sum(b.balance) filter (where b.source = 'app' and b.status = 'delivered'), 0),
      'advance_to_return_cancelled', coalesce(sum(b.advance) filter (where b.source = 'app' and b.advance_state in ('refund_due', 'refund_not_recorded')), 0),
      'advance_not_in_books_open', coalesce(sum(b.advance) filter (where b.source = 'app' and b.advance_state = 'held_not_in_books'), 0),
      'advance_posted_not_applied', coalesce(sum(b.advance) filter (where b.source = 'app' and b.advance_state = 'held_not_applied'), 0)),
    'paper_20_1', jsonb_build_object(
      'advance_open_sheets', coalesce(sum(b.advance) filter (where b.source = 'paper_20_1' and b.status = 'open'), 0),
      'balance_open_sheets', coalesce(sum(b.balance) filter (where b.source = 'paper_20_1' and b.status = 'open'), 0),
      'open_sheets_without_total', count(*) filter (where b.source = 'paper_20_1' and b.status = 'open' and b.total is null),
      'handed_without_due_payment_written', count(*) filter (where b.source = 'paper_20_1' and b.status = 'handed' and b.balance is null))) into sm
    from public._c2_orders_base(p_from, p_to, p_loc, 'order') b where b.source in ('app', 'paper_20_1');
  return jsonb_build_object('from', p_from, 'to', p_to, 'module_on', public.rule_on('online_orders_on'), 'notes', public._c2_order_notes(true) || '"old_list_balance_differs"'::jsonb, 'summary', sm, 'rows', rows);
end $$;

-- drill-down: one app order with its trail, cake specs, promise, costs, advance, refund and sale
create or replace function public.c2_order_detail(p_order uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare o public.online_orders; s public.sales; paid numeric; cost boolean := public.rpt_cost_ok();
begin
  select * into o from public.online_orders where id = p_order;
  if not found or not public.c2_can_read_orders() or not public.can_loc(o.location_id) then raise exception 'not allowed'; end if;
  if o.sale_id is not null then select * into s from public.sales where id = o.sale_id; select coalesce(sum(amount), 0) into paid from public.sale_payments where sale_id = s.id and not voided; end if;
  return jsonb_build_object(
    'order', to_jsonb(o) - 'sale_client',
    'events', coalesce((select jsonb_agg(jsonb_build_object('from', e.from_status, 'to', e.to_status, 'note', e.note, 'by', e.by_staff, 'at', e.at) order by e.id) from public.online_order_events e where e.order_id = o.id), '[]'::jsonb),
    'specs', coalesce((select jsonb_agg(to_jsonb(c) - 'created_by' - 'void_by' order by c.id) from public.order_cake_specs c where c.order_id = o.id and c.state = 'active'), '[]'::jsonb),
    'spec_history', (select count(*) from public.order_cake_specs c where c.order_id = o.id and c.state = 'void'),
    'promise', (select to_jsonb(x) - 'created_by' - 'void_by' from (select * from public.order_promises where order_id = o.id and state = 'active' order by id desc limit 1) x),
    'promise_history', coalesce((select jsonb_agg(jsonb_build_object('slot_from', x.slot_from, 'slot_to', x.slot_to, 'reason', x.reason, 'at', x.created_at, 'by', x.created_staff) order by x.id) from public.order_promises x where x.order_id = o.id and x.state = 'active'), '[]'::jsonb),
    'costs', case when cost then coalesce((select jsonb_agg(to_jsonb(c) - 'created_by' - 'void_by' order by c.id) from public.order_delivery_costs c where c.order_id = o.id), '[]'::jsonb) else null end,
    'cost_hidden', not cost,
    'advance_post', (select to_jsonb(a) - 'created_by' from public.order_advance_posts a where a.order_id = o.id order by a.id desc limit 1),
    'refund', (select to_jsonb(r) - 'created_by' - 'paid_by' - 'void_by' from public.order_refunds r where r.order_id = o.id order by r.id desc limit 1),
    'sale', case when s.id is null then null else jsonb_build_object('id', s.id, 'receipt', s.receipt, 'status', s.status, 'total', s.total, 'paid', paid, 'due', greatest(s.total - paid, 0)) end,
    'register_row', (select to_jsonb(b) from public._c2_orders_base((o.created_at at time zone 'Asia/Dhaka')::date, (o.created_at at time zone 'Asia/Dhaka')::date, o.location_id, 'order') b where b.order_id = o.id),
    'can_move_money', public._c2_can_move_money(o.location_id), 'module_on', public.rule_on('online_orders_on'));
end $$;

do $c2$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^_?c2_' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname !~ '^_' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $c2$;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase450.sql
-- ============================================================
-- Phase 450 - RPT-C2 / R4 part 6 (reports #159 delayed and undelivered orders, #158 on-time delivery performance, #163 order fulfilment rate). READ ONLY.
-- Run AFTER phase 449. New file only. Paste twice = no error.
--
--   The promised moment of an app order = its delivery date + the END of the promised time slot (phase 445); a point time uses that time; no slot = the end of the promised day (basis "date_only", said on screen).
--   Grace: rule order_late_grace_minutes - blank = none. Orders with NO delivery date cannot be judged: they are COUNTED apart ("not judged"), never treated as on time or as late.
--   Paper form 20-1 sheets: promised date and time are on the sheet (deliv_date, deliv_time); the sheet has no delivery timestamp, so paper rows appear in the delayed list (still open after the promise)
--   and in the fulfilment counts, but are never part of the on-time percentage (note paper_delivery_time_not_captured).
--   Open to the existing order-report access; only the places the person may see.
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.c2_order_register(date,date,int,text,text,text,int)') is null then raise exception 'phase450 needs phase449 pasted first'; end if;
end $guard$;

-- the promised end moment (Dhaka time) of a row of _c2_orders_base; null when there is no promised date
create or replace function public._c2_promised_end(p_date date, p_from time, p_to time) returns timestamptz language sql immutable as $$
  select case when p_date is null then null else ((p_date::timestamp + coalesce(p_to, p_from, time '23:59:59')) at time zone 'Asia/Dhaka') end;
$$;
create or replace function public._c2_grace() returns interval language sql stable security definer set search_path = public as $$
  select make_interval(mins => coalesce(public.rule_num('order_late_grace_minutes'), 0)::int);
$$;

-- #159 delayed and undelivered orders (open orders whose promised moment has passed)
create or replace function public.c2_orders_delayed(p_loc int default null, p_as_of timestamptz default null, p_from date default null, p_to date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare nowts timestamptz := coalesce(p_as_of, now()); d1 date := coalesce(p_from, (nowts at time zone 'Asia/Dhaka')::date - 365); d2 date := coalesce(p_to, (nowts at time zone 'Asia/Dhaka')::date + 365); rows jsonb; sm jsonb; g interval := public._c2_grace();
begin
  if not public.c2_can_read_orders() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  perform public._c2_range(d1, d2);
  with b as (select x.*, public._c2_promised_end(x.promised_date, x.promised_from, x.promised_to) as pend
               from public._c2_orders_base(d1, d2, p_loc, 'promised') x where x.source in ('app', 'paper_20_1') and x.status in ('new', 'confirmed', 'packed', 'open')),
       o as (select b.*, nowts - b.pend as over, (b.promised_from is not null) as slot_known from b where b.pend is not null and nowts > b.pend + g)
  select (select coalesce(jsonb_agg(jsonb_build_object('source', source, 'ref', ref, 'order_id', order_id, 'entry_id', entry_id, 'loc', loc, 'customer_name', customer_name, 'customer_mobile', customer_mobile, 'status', status,
            'channel', channel, 'order_type', order_type, 'delivery_mode', delivery_mode, 'promised_date', promised_date, 'promised_from', promised_from, 'promised_to', promised_to, 'basis', case when slot_known then 'slot' else 'date_only' end,
            'overdue_hours', case when slot_known then round(extract(epoch from over) / 3600, 1) end, 'overdue_days', (nowts at time zone 'Asia/Dhaka')::date - promised_date, 'advance', advance, 'balance', balance, 'total', total)
            order by over desc), '[]'::jsonb) from o),
         jsonb_build_object('delayed', (select count(*) from o), 'delayed_app', (select count(*) from o where source = 'app'), 'delayed_paper_20_1', (select count(*) from o where source = 'paper_20_1'),
           'oldest_days', (select max((nowts at time zone 'Asia/Dhaka')::date - promised_date) from o),
           'judged_by_slot', (select count(*) from o where slot_known), 'judged_by_date_only', (select count(*) from o where not slot_known),
           'open_without_promised_date', (select count(*) from public._c2_orders_base((nowts at time zone 'Asia/Dhaka')::date - 365, (nowts at time zone 'Asia/Dhaka')::date + 1, p_loc, 'order') y
                                           where y.source in ('app', 'paper_20_1') and y.status in ('new', 'confirmed', 'packed', 'open') and y.promised_date is null),
           'open_not_yet_due', (select count(*) from b where b.pend is not null and nowts <= b.pend + g), 'grace_minutes', public.rule_num('order_late_grace_minutes'))
    into rows, sm;
  return jsonb_build_object('as_of', nowts at time zone 'Asia/Dhaka', 'module_on', public.rule_on('online_orders_on'), 'notes', public._c2_order_notes(true) || '"open_without_date_not_judged"'::jsonb, 'summary', sm, 'rows', rows);
end $$;

-- #158 on-time delivery performance (app orders delivered; the promised date is inside the range)
create or replace function public.c2_orders_ontime(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows jsonb; sm jsonb; byx jsonb; g interval := public._c2_grace(); nj int;
begin
  if not public.c2_can_read_orders() then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  with b as (select x.*, public._c2_promised_end(x.promised_date, x.promised_from, x.promised_to) as pend
               from public._c2_orders_base(p_from, p_to, p_loc, 'promised') x where x.source = 'app' and x.status = 'delivered' and x.delivered_at is not null),
       j as (select b.*, (b.delivered_at <= b.pend + g) as on_time, (b.promised_from is not null) as slot_known,
                    round(extract(epoch from (b.delivered_at - b.pend)) / 60) as late_minutes from b where b.pend is not null)
  select (select coalesce(jsonb_agg(jsonb_build_object('ref', ref, 'order_id', order_id, 'loc', loc, 'customer_name', customer_name, 'channel', channel, 'delivery_mode', delivery_mode, 'delivery_by', delivery_by,
            'promised_date', promised_date, 'promised_from', promised_from, 'promised_to', promised_to, 'delivered_at', delivered_at at time zone 'Asia/Dhaka', 'basis', case when slot_known then 'slot' else 'date_only' end,
            'on_time', on_time, 'late_minutes', case when on_time then null else late_minutes end) order by delivered_at desc), '[]'::jsonb) from j),
         jsonb_build_object('judged', (select count(*) from j), 'on_time', (select count(*) from j where on_time), 'late', (select count(*) from j where not on_time),
           'on_time_pct', (select case when count(*) = 0 then null else round(100.0 * count(*) filter (where on_time) / count(*), 1) end from j),
           'judged_by_slot', (select count(*) from j where slot_known), 'judged_by_date_only', (select count(*) from j where not slot_known),
           'on_time_by_slot_pct', (select case when count(*) filter (where slot_known) = 0 then null else round(100.0 * count(*) filter (where slot_known and on_time) / count(*) filter (where slot_known), 1) end from j),
           'avg_late_minutes', (select round(avg(late_minutes)) from j where not on_time), 'grace_minutes', public.rule_num('order_late_grace_minutes')),
         (select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) from (select 'by_mode:' || coalesce(delivery_mode, '-') as k, jsonb_build_object('judged', count(*), 'on_time', count(*) filter (where on_time)) as v from j group by delivery_mode
              union all select 'by_channel:' || coalesce(channel, '-'), jsonb_build_object('judged', count(*), 'on_time', count(*) filter (where on_time)) from j group by channel) q)
    into rows, sm, byx;
  select count(*) into nj from public._c2_orders_base(p_from, p_to, p_loc, 'order') y where y.source = 'app' and y.status = 'delivered' and y.promised_date is null;
  return jsonb_build_object('from', p_from, 'to', p_to, 'module_on', public.rule_on('online_orders_on'),
    'notes', public._c2_order_notes(true) || '"paper_delivery_time_not_captured"'::jsonb, 'summary', sm || jsonb_build_object('delivered_without_promised_date_not_judged', nj), 'breakdown', byx,
    'still_open_overdue', (public.c2_orders_delayed(p_loc, null, p_from, p_to) -> 'summary' ->> 'delayed_app')::int, 'rows', rows);
end $$;

-- #163 order fulfilment rate (by the day the order was taken)
create or replace function public.c2_order_fulfilment(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare sm jsonb; byx jsonb;
begin
  if not public.c2_can_read_orders() then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  with b as (select * from public._c2_orders_base(p_from, p_to, p_loc, 'order') x where x.source in ('app', 'paper_20_1')),
       a as (select source,
              count(*) as orders,
              count(*) filter (where status in ('delivered', 'handed')) as delivered,
              count(*) filter (where status in ('cancelled', 'not_collected')) as cancelled,
              count(*) filter (where status in ('new', 'confirmed', 'packed', 'open')) as still_open
             from b group by source)
  select coalesce(jsonb_object_agg(source, jsonb_build_object('orders', orders, 'delivered', delivered, 'cancelled', cancelled, 'still_open', still_open,
            'rate_of_closed_pct', case when delivered + cancelled = 0 then null else round(100.0 * delivered / (delivered + cancelled), 1) end,
            'rate_of_all_pct', case when orders = 0 then null else round(100.0 * delivered / orders, 1) end)), '{}'::jsonb) into sm from a;
  select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) into byx from (
    select 'app:channel:' || coalesce(channel, '-') as k, jsonb_build_object('orders', count(*), 'delivered', count(*) filter (where status = 'delivered'), 'cancelled', count(*) filter (where status = 'cancelled')) as v
      from public._c2_orders_base(p_from, p_to, p_loc, 'order') x where x.source = 'app' group by channel
    union all select 'app:mode:' || coalesce(delivery_mode, '-'), jsonb_build_object('orders', count(*), 'delivered', count(*) filter (where status = 'delivered'), 'cancelled', count(*) filter (where status = 'cancelled'))
      from public._c2_orders_base(p_from, p_to, p_loc, 'order') x where x.source = 'app' group by delivery_mode) q;
  return jsonb_build_object('from', p_from, 'to', p_to, 'module_on', public.rule_on('online_orders_on'), 'notes', public._c2_order_notes(true) || '"rate_formulas"'::jsonb, 'summary', sm, 'breakdown', byx);
end $$;

do $c2$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^_?c2_' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname !~ '^_' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $c2$;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase451.sql
-- ============================================================
-- Phase 451 - RPT-C2 / R4 part 7 (reports #157 order cancellation and refunds, #162 delivery cost and performance). READ ONLY.
-- Run AFTER phase 450. New file only. Paste twice = no error.
--
--   c2_order_cancellations(from, to, place)   app orders cancelled in the range (the day the cancel was written in the order trail) with reason, advance, what was decided for it and where the refund stands
--       (paid / due / closed without payment / NOT RECORDED because the refund switch is off / kept as customer advance / taken as income), plus the paper 20-1 sheets marked "not collected".
--   c2_delivery_cost_report(from, to, place)  home and courier orders taken in the range: what the customer paid for delivery, the actual cost written at delivery (phase 446), the margin ONLY where a cost
--       was written. Orders with no cost written are COUNTED apart ("cost not captured"), never treated as cost 0. Paper 20-6 ledger lines show their delivery charge; the paper sheet has no cost side.
--   Delivery cost needs the cost right (rpt_cost_ok); without it the cost columns are empty and the note cost_hidden says why. Open to the existing order-report access; only places the person may see.
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.c2_orders_ontime(date,date,int)') is null then raise exception 'phase451 needs phase450 pasted first'; end if;
end $guard$;

create or replace function public.c2_order_cancellations(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows jsonb; sm jsonb; paper jsonb; reasons jsonb; created_n int; created_c int;
begin
  if not public.c2_can_read_orders() then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  with c as (
    select o.id, o.order_no, o.location_id, o.customer_name, o.channel, o.cancel_reason, o.advance, o.advance_fate, o.advance_mode,
           o.subtotal - o.discount + o.delivery_charge as total,
           (select e.at from public.online_order_events e where e.order_id = o.id and e.to_status = 'cancelled' order by e.id desc limit 1) as cancelled_at,
           (select r.state from public.order_refunds r where r.order_id = o.id order by r.id desc limit 1) as rstate,
           (select r.paid_at from public.order_refunds r where r.order_id = o.id and r.state = 'paid' limit 1) as paid_at,
           (select r.refund_mode from public.order_refunds r where r.order_id = o.id order by r.id desc limit 1) as rmode,
           exists (select 1 from public.order_advance_posts a where a.order_id = o.id and a.state = 'posted') as held_posted
      from public.online_orders o where o.status = 'cancelled' and public.can_loc(o.location_id) and (p_loc is null or o.location_id = p_loc)),
       d as (select c.*, case when c.advance = 0 then 'none' when c.rstate = 'paid' then 'refunded' when c.rstate = 'due' then 'refund_due' when c.rstate = 'void' then 'refund_closed'
                              else case c.advance_fate when 'refund' then 'refund_not_recorded' when 'adjust' then case when c.held_posted then 'kept_as_customer_advance' else 'kept_for_adjustment' end
                                                       when 'income' then 'taken_as_income' else 'unknown' end end as advance_state
               from c where (c.cancelled_at at time zone 'Asia/Dhaka')::date between p_from and p_to)
  select (select coalesce(jsonb_agg(jsonb_build_object('ref', '#' || order_no, 'order_id', id, 'loc', location_id, 'customer_name', customer_name, 'channel', channel, 'cancelled_at', cancelled_at at time zone 'Asia/Dhaka',
            'reason', cancel_reason, 'total', total, 'advance', advance, 'advance_fate', advance_fate, 'advance_state', advance_state, 'refund_mode', rmode, 'refund_paid_at', paid_at at time zone 'Asia/Dhaka') order by cancelled_at desc), '[]'::jsonb) from d),
         jsonb_build_object('cancelled', (select count(*) from d), 'cancelled_value', (select coalesce(sum(total), 0) from d), 'advance_total', (select coalesce(sum(advance), 0) from d),
           'refunded', (select coalesce(sum(advance), 0) from d where advance_state = 'refunded'), 'refund_due', (select coalesce(sum(advance), 0) from d where advance_state = 'refund_due'),
           'refund_not_recorded', (select coalesce(sum(advance), 0) from d where advance_state = 'refund_not_recorded'), 'refund_closed_unpaid', (select coalesce(sum(advance), 0) from d where advance_state = 'refund_closed'),
           'kept_as_customer_advance', (select coalesce(sum(advance), 0) from d where advance_state in ('kept_as_customer_advance', 'kept_for_adjustment')), 'taken_as_income', (select coalesce(sum(advance), 0) from d where advance_state = 'taken_as_income'),
           'fate_unknown', (select count(*) from d where advance_state = 'unknown')),
         (select coalesce(jsonb_agg(jsonb_build_object('reason', reason, 'orders', n, 'advance', adv) order by n desc), '[]'::jsonb) from (select coalesce(nullif(lower(btrim(cancel_reason)), ''), '(no reason written)') as reason, count(*) as n, sum(advance) as adv from d group by 1) z)
    into rows, sm, reasons;
  select count(*), count(*) filter (where status = 'cancelled') into created_n, created_c
    from public._c2_orders_base(p_from, p_to, p_loc, 'order') x where x.source = 'app';
  select jsonb_build_object('sheets_not_collected', count(*), 'advance', coalesce(sum(adv), 0), 'by_fate', coalesce(jsonb_object_agg(f, n) filter (where f is not null), '{}'::jsonb)) into paper from (
    select coalesce(nullif(x.advance_fate, ''), 'not_written') as f, count(*) as n, sum(x.advance) as adv from public._c2_orders_base(p_from, p_to, p_loc, 'order') x where x.source = 'paper_20_1' and x.status = 'not_collected' group by 1) q;
  return jsonb_build_object('from', p_from, 'to', p_to, 'module_on', public.rule_on('online_orders_on'), 'record_on', public.rule_on('order_refund_record_on'),
    'notes', public._c2_order_notes(true) || case when public.rule_on('order_refund_record_on') then '[]'::jsonb else '["refund_switch_off"]'::jsonb end,
    'summary', sm || jsonb_build_object('orders_taken_in_range', created_n, 'of_those_cancelled', created_c, 'cancel_rate_pct', case when created_n = 0 then null else round(100.0 * created_c / created_n, 1) end),
    'by_reason', reasons, 'paper_20_1', paper, 'rows', rows);
end $$;

create or replace function public.c2_delivery_cost_report(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare cost boolean := public.rpt_cost_ok(); rows jsonb; sm jsonb; bykind jsonb; byby jsonb; paper jsonb;
begin
  if not public.c2_can_read_orders() then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  with b as (select x.* from public._c2_orders_base(p_from, p_to, p_loc, 'order') x where x.source = 'app' and x.delivery_mode in ('home', 'courier')),
       r as (select b.*, case when cost then b.delivery_cost end as cost_x from b)
  select (select coalesce(jsonb_agg(jsonb_build_object('ref', ref, 'order_id', order_id, 'loc', loc, 'order_date', order_date, 'customer_name', customer_name, 'delivery_mode', delivery_mode, 'delivery_by', delivery_by, 'status', status,
            'charge', delivery_charge, 'cost', cost_x, 'margin', case when cost and delivery_cost is not null then delivery_charge - delivery_cost end, 'cost_captured', delivery_cost is not null) order by order_date desc, ref), '[]'::jsonb) from r),
         jsonb_build_object('orders', (select count(*) from b), 'orders_not_cancelled', (select count(*) from b where status <> 'cancelled'), 'delivered', (select count(*) from b where status = 'delivered'),
           'charge_total', (select coalesce(sum(delivery_charge), 0) from b where status <> 'cancelled'),
           'with_cost_captured', case when cost then (select count(*) from b where delivery_cost is not null) end,
           'cost_not_captured', case when cost then (select count(*) from b where delivery_cost is null and status in ('delivered', 'cancelled')) end,
           'cost_total_captured', case when cost then (select sum(delivery_cost) from b) end,
           'charge_where_cost_captured', case when cost then (select sum(delivery_charge) from b where delivery_cost is not null) end,
           'margin_where_cost_captured', case when cost then (select sum(delivery_charge - delivery_cost) from b where delivery_cost is not null) end,
           'avg_cost_per_order_captured', case when cost then (select round(avg(delivery_cost), 2) from b where delivery_cost is not null) end)
    into rows, sm;
  select case when cost then coalesce(jsonb_object_agg(kind, jsonb_build_object('amount', amt, 'rows', n)), '{}'::jsonb) end into bykind from (
    select c.kind, sum(c.amount) as amt, count(*) as n from public.order_delivery_costs c join public._c2_orders_base(p_from, p_to, p_loc, 'order') x on x.order_id = c.order_id and x.source = 'app' and x.delivery_mode in ('home', 'courier')
     where c.state = 'active' group by c.kind) q;
  select case when cost then coalesce(jsonb_agg(jsonb_build_object('delivery_by', coalesce(delivery_by, '(not written)'), 'orders', orders, 'orders_with_cost', wc, 'cost', ct, 'charge', ch) order by orders desc), '[]'::jsonb) end into byby from (
    select x.delivery_by, count(*) as orders, count(*) filter (where x.delivery_cost is not null) as wc, sum(x.delivery_cost) as ct, sum(x.delivery_charge) as ch
      from public._c2_orders_base(p_from, p_to, p_loc, 'order') x where x.source = 'app' and x.delivery_mode in ('home', 'courier') and x.status <> 'cancelled' group by x.delivery_by) q;
  select jsonb_build_object('lines', count(*), 'delivery_charge', sum(delivery_charge), 'lines_without_charge_written', count(*) filter (where delivery_charge is null),
           'by_delivery', coalesce((select jsonb_agg(jsonb_build_object('delivery_by', coalesce(delivery_by, '(not written)'), 'lines', n, 'charge', ch) order by n desc) from (
              select y.delivery_by, count(*) as n, sum(y.delivery_charge) as ch from public._c2_orders_base(p_from, p_to, p_loc, 'order') y where y.source = 'paper_20_6' group by y.delivery_by) g), '[]'::jsonb))
    into paper from public._c2_orders_base(p_from, p_to, p_loc, 'order') z where z.source = 'paper_20_6';
  return jsonb_build_object('from', p_from, 'to', p_to, 'module_on', public.rule_on('online_orders_on'),
    'notes', public._c2_order_notes(true) || '"cost_is_information_not_posted"'::jsonb || '"paper_20_6_no_cost_side"'::jsonb, 'summary', sm, 'by_kind', bykind, 'by_delivery_by', byby, 'paper_20_6', paper, 'rows', rows);
end $$;

do $c2$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^_?c2_' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname !~ '^_' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $c2$;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase452.sql
-- ============================================================
-- Phase 452 - RPT-C2 / R4 part 8 (reports #160 order-wise production and material cost, #161 order profitability). READ for the reports; one small capture: the ORDER on a production run.
-- Run AFTER phase 451. New file only. Paste twice = no error.
--
--   production_run_orders   links a production run to an app order (a run can serve several orders; an order can use several runs). qty = how much of the run's output is for that order (blank is
--                           allowed only when the run has this one link: then the whole run belongs to the order). Append-only: a wrong link is VOIDED with a reason.
--   c2_production_link_order / c2_production_link_void   write. Allowed: owner, the stock_production right at the run's place, or a POS-enter person at the order's place. Module online_orders_on needed.
--   c2_orders_for_production(place)   the open app orders a factory person may pick from (order number, customer name, delivery day, cake summary - no mobile number, no money).
--   c2_order_production_cost(from, to, place, order)   #160   cost of each linked run share: material and conversion cost split by quantity. Costs that the run could not know (cost_complete false) are
--                           shown as "cost not complete", never as 0. Needs the cost right.
--   c2_order_profit(from, to, place)   #161   delivered app orders: sale value - cost of the goods sold (stock ledger at the time of the sale) - the delivery cost written. A profit is shown ONLY when every
--                           part is known; otherwise the row lists what is missing. Pickup orders need no delivery cost. A sale with returns is not judged (the goods cost of returned items is not reversed here).
--                           Needs the cost right. The linked production cost is shown beside it for comparison and is NOT subtracted again (the goods cost is already in the sale cost).
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.c2_delivery_cost_report(date,date,int)') is null then raise exception 'phase452 needs phase451 pasted first'; end if;
end $guard$;

create table if not exists public.production_run_orders (
  id bigint generated always as identity primary key,
  run_id uuid not null references public.production_runs(id),
  order_id uuid not null references public.online_orders(id),
  qty numeric check (qty is null or (qty > 0 and qty <= 1000000000)),
  note text check (note is null or char_length(note) <= 300),
  state text not null default 'active' check (state in ('active', 'void')),
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  void_by uuid, void_at timestamptz, void_note text
);
create unique index if not exists production_run_orders_live on public.production_run_orders (run_id, order_id) where state = 'active';
create index if not exists production_run_orders_order on public.production_run_orders (order_id) where state = 'active';
drop trigger if exists production_run_orders_ro on public.production_run_orders;
create trigger production_run_orders_ro before update or delete on public.production_run_orders for each row execute function public._c2_trail_ro();
drop trigger if exists audit_production_run_orders on public.production_run_orders;
create trigger audit_production_run_orders after insert or update on public.production_run_orders for each row execute function public.log_change('id');

create or replace function public.c2_production_link_order(p_run uuid, p_order uuid, p_qty numeric default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.production_runs; o public.online_orders; id_ bigint; q numeric := case when p_qty is null then null else round(p_qty, 4) end;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into r from public.production_runs where id = p_run;
  if not found then raise exception 'not_found'; end if;
  select * into o from public.online_orders where id = p_order for update;
  if not found then raise exception 'not_found'; end if;
  if not public.rule_on('online_orders_on') then raise exception 'module_off'; end if;
  if not (public.is_owner() or public.has_grant('stock_production', r.location_id) or (public.can_do('POS', 'enter') and public.can_loc(o.location_id))) then raise exception 'not allowed'; end if;
  if r.status <> 'done' then raise exception 'run_void: a voided production run cannot be linked'; end if;
  if q is not null and (q = 'NaN'::numeric or q <= 0) then raise exception 'bad_qty'; end if;
  if char_length(coalesce(p_note, '')) > 300 then raise exception 'too_long'; end if;
  if exists (select 1 from public.production_run_orders where run_id = r.id and order_id = o.id and state = 'active') then return jsonb_build_object('run_id', r.id, 'order_id', o.id, 'noop', true); end if;
  if q is not null and q + coalesce((select sum(x.qty) from public.production_run_orders x where x.run_id = r.id and x.state = 'active'), 0) > r.yield_base then
    raise exception 'qty_over_output: the quantities linked to this run would be more than the run made (%)', r.yield_base;
  end if;
  insert into public.production_run_orders (run_id, order_id, qty, note, created_by, created_staff) values (r.id, o.id, q, left(nullif(btrim(p_note), ''), 300), auth.uid(), public._c2_staff()) returning id into id_;
  perform public._oo_event61(o.id, o.status, o.status, 'production run linked' || coalesce(' (' || q::text || ')', ''));
  return jsonb_build_object('id', id_, 'run_id', r.id, 'order_id', o.id, 'qty', q);
end $$;

create or replace function public.c2_production_link_void(p_link bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.production_run_orders; r public.production_runs; o public.online_orders;
begin
  select * into l from public.production_run_orders where id = p_link for update;
  if not found then raise exception 'not_found'; end if;
  select * into r from public.production_runs where id = l.run_id; select * into o from public.online_orders where id = l.order_id;
  if not public.rule_on('online_orders_on') then raise exception 'module_off'; end if;
  if not (public.is_owner() or public.has_grant('stock_production', r.location_id) or (public.can_do('POS', 'enter') and public.can_loc(o.location_id))) then raise exception 'not allowed'; end if;
  if l.state = 'void' then return jsonb_build_object('id', l.id, 'noop', true); end if;
  if nullif(btrim(p_note), '') is null or char_length(p_note) > 300 then raise exception 'reason_required'; end if;
  update public.production_run_orders set state = 'void', void_by = auth.uid(), void_at = now(), void_note = btrim(p_note) where id = l.id;
  perform public._oo_event61(o.id, o.status, o.status, 'production run link voided: ' || btrim(p_note));
  return jsonb_build_object('id', l.id, 'state', 'void');
end $$;

-- the open orders a factory person can pick from (no mobile number, no money)
create or replace function public.c2_orders_for_production(p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() or not (public.is_owner() or public.has_grant('stock_production') or public.can_do('POS', 'view') or public.can_do('POS', 'enter')) then raise exception 'not allowed'; end if;
  return jsonb_build_object('module_on', public.rule_on('online_orders_on'), 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('order_id', o.id, 'order_no', o.order_no, 'loc', o.location_id, 'customer_name', o.customer_name, 'status', o.status, 'delivery_date', o.delivery_date,
             'slot_from', pr.slot_from, 'slot_to', pr.slot_to, 'cake', exists (select 1 from public.order_cake_specs c where c.order_id = o.id and c.state = 'active')) order by o.delivery_date nulls last, o.order_no)
      from public.online_orders o left join lateral (select x.slot_from, x.slot_to from public.order_promises x where x.order_id = o.id and x.state = 'active' order by x.id desc limit 1) pr on true
     where o.status in ('new', 'confirmed', 'packed') and (p_loc is null or o.location_id = p_loc)), '[]'::jsonb));
end $$;

-- #160 cost of the production linked to orders
create or replace function public.c2_order_production_cost(p_from date, p_to date, p_loc int default null, p_order uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare cost boolean := public.rpt_cost_ok(); rows jsonb; per jsonb; nolink int;
begin
  if not public.c2_can_read_orders() then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  with b as (select x.order_id, x.ref, x.order_date, x.customer_name, x.status, x.loc, x.promised_date from public._c2_orders_base(p_from, p_to, p_loc, 'order') x where x.source = 'app' and (p_order is null or x.order_id = p_order)),
       l as (select b.*, k.id as link_id, k.qty as link_qty, r.id as run_id, r.status as run_status, (r.made_at at time zone 'Asia/Dhaka')::date as made_on, r.location_id as run_loc, r.item_id, it.code, it.name_bn, it.name_en,
                    r.yield_base, r.material_cost, r.conversion_cost, r.unit_cost, r.cost_complete, r.conversion_complete,
                    (select count(*) from public.production_run_orders k2 where k2.run_id = r.id and k2.state = 'active') as links_on_run
               from b join public.production_run_orders k on k.order_id = b.order_id and k.state = 'active' join public.production_runs r on r.id = k.run_id join public.items it on it.id = r.item_id),
       a as (select l.*, case when l.link_qty is not null then l.link_qty when l.links_on_run = 1 then l.yield_base end as qty_used from l)
  select coalesce(jsonb_agg(jsonb_build_object('order_ref', ref, 'order_id', order_id, 'customer_name', customer_name, 'order_status', status, 'link_id', link_id, 'run_id', run_id, 'made_on', made_on, 'run_loc', run_loc,
            'item_code', code, 'item_name_bn', name_bn, 'item_name_en', name_en, 'run_output', yield_base, 'qty_for_order', qty_used,
            'share_pct', case when qty_used is not null and yield_base > 0 then round(100.0 * qty_used / yield_base, 1) end,
            'allocation_known', qty_used is not null, 'run_void', run_status = 'void',
            'material_cost', case when cost and run_status = 'done' and qty_used is not null and yield_base > 0 and material_cost is not null then round(material_cost * qty_used / yield_base, 2) end,
            'conversion_cost', case when cost and run_status = 'done' and qty_used is not null and yield_base > 0 and conversion_cost is not null then round(conversion_cost * qty_used / yield_base, 2) end,
            'cost_complete', coalesce(cost_complete, false) and coalesce(conversion_complete, true)) order by order_date desc, ref, made_on), '[]'::jsonb) into rows from a;
  select coalesce(jsonb_agg(y.x order by y.rf), '[]'::jsonb) into per from (
    with b as (select x.order_id, x.ref from public._c2_orders_base(p_from, p_to, p_loc, 'order') x where x.source = 'app' and (p_order is null or x.order_id = p_order)),
         z as (select b.order_id, b.ref, r.status as run_status, r.yield_base, r.material_cost, r.conversion_cost, r.cost_complete,
                      case when k.qty is not null then k.qty when (select count(*) from public.production_run_orders k2 where k2.run_id = r.id and k2.state = 'active') = 1 then r.yield_base end as qty_used
                 from b join public.production_run_orders k on k.order_id = b.order_id and k.state = 'active' join public.production_runs r on r.id = k.run_id)
    select min(z.ref) as rf, jsonb_build_object('order_id', z.order_id, 'order_ref', min(z.ref), 'runs', count(*),
             'material_cost', case when cost and bool_and(z.material_cost is not null and z.qty_used is not null and z.run_status = 'done') then round(sum(z.material_cost * z.qty_used / nullif(z.yield_base, 0)), 2) end,
             'conversion_cost', case when cost and bool_and(z.conversion_cost is not null and z.qty_used is not null and z.run_status = 'done') then round(sum(z.conversion_cost * z.qty_used / nullif(z.yield_base, 0)), 2) end,
             'complete', bool_and(coalesce(z.cost_complete, false) and z.qty_used is not null and z.run_status = 'done')) as x
      from z group by z.order_id) y;
  select count(*) into nolink from public._c2_orders_base(p_from, p_to, p_loc, 'order') x
   where x.source = 'app' and x.has_spec and x.status <> 'cancelled' and not exists (select 1 from public.production_run_orders k where k.order_id = x.order_id and k.state = 'active');
  return jsonb_build_object('from', p_from, 'to', p_to, 'module_on', public.rule_on('online_orders_on'), 'notes', public._c2_order_notes(false) || '"run_cost_split_by_quantity"'::jsonb,
    'cake_orders_without_a_linked_run', nolink, 'per_order', per, 'rows', rows);
end $$;

-- #161 order profitability (delivered app orders, by the day of delivery)
create or replace function public.c2_order_profit(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare cost boolean := public.rpt_cost_ok(); rows jsonb; sm jsonb;
begin
  if not public.c2_can_read_orders() then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  with o as (
    select o.id, o.order_no, o.location_id, o.customer_name, o.delivery_mode, o.delivery_charge, s.id as sale_id, s.receipt, s.status as sale_status, s.total as revenue, (o.delivered_at at time zone 'Asia/Dhaka')::date as delivered_on,
           (select count(*) from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text) as ledger_rows,
           (select count(*) from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text and coalesce(l.unit_cost, 0) <= 0) as ledger_no_cost,
           (select sum(-l.qty_delta * l.unit_cost) from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text) as goods_cost,
           (select sum(c.amount) from public.order_delivery_costs c where c.order_id = o.id and c.state = 'active') as delivery_cost,
           (select coalesce(sum(r.amount), 0) from public.sale_returns r where r.sale_id = s.id and r.status = 'done') as returns,
           (select case when count(*) = 0 or count(*) filter (where public._c2_run_alloc(k.id) is null) > 0 then null else sum(public._c2_run_alloc(k.id)) end from public.production_run_orders k where k.order_id = o.id and k.state = 'active') as linked_production_cost
      from public.online_orders o join public.sales s on s.id = o.sale_id
     where o.status = 'delivered' and public.can_loc(o.location_id) and (p_loc is null or o.location_id = p_loc) and (o.delivered_at at time zone 'Asia/Dhaka')::date between p_from and p_to),
       p as (select o.*, array_remove(array[case when o.ledger_rows = 0 or o.ledger_no_cost > 0 then 'goods_cost' end,
                                            case when o.delivery_mode in ('home', 'courier') and o.delivery_cost is null then 'delivery_cost' end,
                                            case when o.sale_status = 'void' then 'sale_voided' end,
                                            case when o.returns > 0 then 'sale_has_returns' end], null) as missing from o)
  select coalesce(jsonb_agg(jsonb_build_object('ref', '#' || order_no, 'order_id', id, 'loc', location_id, 'customer_name', customer_name, 'delivery_mode', delivery_mode, 'delivered_on', delivered_on, 'receipt', receipt, 'revenue', revenue,
            'goods_cost', case when cost then goods_cost end, 'delivery_cost', case when cost then case when delivery_mode = 'pickup' then coalesce(delivery_cost, 0) else delivery_cost end end,
            'linked_production_cost', case when cost then linked_production_cost end,
            'profit', case when cost and cardinality(missing) = 0 then revenue - goods_cost - coalesce(delivery_cost, 0) end,
            'missing', case when cost then to_jsonb(missing) else '["cost_hidden"]'::jsonb end) order by delivered_on desc, order_no), '[]'::jsonb),
         jsonb_build_object('delivered_orders', count(*), 'revenue_all', coalesce(sum(revenue), 0),
           'orders_with_every_cost_known', case when cost then count(*) filter (where cardinality(missing) = 0) end,
           'orders_with_something_missing', case when cost then count(*) filter (where cardinality(missing) > 0) end,
           'revenue_of_full_cost_orders', case when cost then sum(revenue) filter (where cardinality(missing) = 0) end,
           'profit_of_full_cost_orders', case when cost then sum(revenue - goods_cost - coalesce(delivery_cost, 0)) filter (where cardinality(missing) = 0) end,
           'margin_pct_of_full_cost_orders', case when cost and sum(revenue) filter (where cardinality(missing) = 0) > 0 then round(100.0 * sum(revenue - goods_cost - coalesce(delivery_cost, 0)) filter (where cardinality(missing) = 0) / sum(revenue) filter (where cardinality(missing) = 0), 1) end)
    into rows, sm from p;
  return jsonb_build_object('from', p_from, 'to', p_to, 'module_on', public.rule_on('online_orders_on'), 'notes', public._c2_order_notes(false) || '"profit_only_when_every_cost_known"'::jsonb || '"linked_production_not_subtracted"'::jsonb,
    'summary', sm, 'rows', rows);
end $$;

-- the allocated total cost (material + conversion) of one production link; null when it cannot be known
create or replace function public._c2_run_alloc(p_link bigint) returns numeric language sql stable security definer set search_path = public as $$
  select case when r.status <> 'done' or r.material_cost is null or r.yield_base <= 0 then null
              else round((r.material_cost + coalesce(r.conversion_cost, 0)) * coalesce(k.qty, case when (select count(*) from public.production_run_orders k2 where k2.run_id = r.id and k2.state = 'active') = 1 then r.yield_base end) / r.yield_base, 2) end
    from public.production_run_orders k join public.production_runs r on r.id = k.run_id where k.id = p_link;
$$;

alter table public.production_run_orders enable row level security;
revoke all on public.production_run_orders from public, anon, authenticated;
grant select on public.production_run_orders to authenticated;
drop policy if exists production_run_orders_sel on public.production_run_orders;
create policy production_run_orders_sel on public.production_run_orders for select to authenticated using (public.c2_can_read_orders() and public.c2_order_visible(order_id));

do $c2$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^_?c2_' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname !~ '^_' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $c2$;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase453.sql
-- ============================================================
-- Phase 453 - RPT-C2 / R5 part 1 (report #138 customer credit risk and overdue; the "dues not linked to a customer" notice). READ ONLY apart from the credit-days field.
-- Run AFTER phase 452. New file only. Does not touch the CRM tables (phases 300-340). Paste twice = no error.
--
--   customers.credit_days   (new, blank for everyone) the days a customer may take to pay; set with c2_customer_credit_days_set (owner or grant customer_manage = the right that sets the credit limit).
--   rules  credit_default_days (blank)         terms used for a customer with no credit_days of their own. Blank = such a customer has NO terms: their dues are listed but not called overdue.
--          credit_risk_watch_days (blank)      a customer whose oldest overdue amount is this many days past due or more is "watch".
--          credit_risk_high_days (blank)       ... "high". While either is blank the risk column says "rule not set" - ages and amounts are still shown. Nothing here blocks a sale.
--   c2_credit_risk(as_of, only_overdue, search)   one row per customer who owes: balance (the same figure as the dues list), open items aged oldest-first by the SAME rule customer_dues uses
--          (collections and return credits settle the oldest first, opening dues first), due date = item date + terms, overdue amount, days past due, limit used, advance held, advance already applied.
--   c2_credit_terms_list()                      customers that have terms set (for the editing screen).
--   c2_dues_not_linked_notice()                 amounts the customer dues list cannot show: opening dues entered while open_parties_link is OFF, due on sales that have no customer,
--          and (accounting people only) receivable in the journal with no customer. Each with its count and where to fix it.
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.c2_order_profit(date,date,int)') is null then raise exception 'phase453 needs phase452 pasted first'; end if;
end $guard$;

alter table public.customers add column if not exists credit_days int;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'customers_credit_days_c2_chk') then
    alter table public.customers add constraint customers_credit_days_c2_chk check (credit_days is null or (credit_days >= 0 and credit_days <= 3650));
  end if;
end $$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('credit_default_days', 'customers', 'number', null, 'days', null, 0, 3650, 'যে গ্রাহকের নিজের বাকির দিন নেই তার জন্য ডিফল্ট দিন', 'যে customer-এর নিজের credit day নেই তার default দিন', 'Default credit days for a customer with none of their own',
  'ফাঁকা থাকলে নিজের দিন না থাকা গ্রাহকের বাকিকে মেয়াদোত্তীর্ণ বলা হয় না।', 'Blank = a customer with no days of their own has no terms; their dues are listed but not called overdue.', 520),
 ('credit_risk_watch_days', 'customers', 'number', null, 'days', null, 0, 3650, 'এত দিন মেয়াদ পেরোলে গ্রাহক "নজরে"', 'এত দিন মেয়াদ পেরোলে customer "নজরে"', 'Overdue this many days or more = watch',
  'ফাঁকা থাকলে ঝুঁকির কলামে "নিয়ম বসানো নেই" দেখায়; বাকির বয়স ও টাকা তবুও দেখায়।', 'Blank = the risk column says "rule not set"; ages and amounts are still shown.', 521),
 ('credit_risk_high_days', 'customers', 'number', null, 'days', null, 0, 3650, 'এত দিন মেয়াদ পেরোলে গ্রাহক "উচ্চ ঝুঁকি"', 'এত দিন মেয়াদ পেরোলে customer "high risk"', 'Overdue this many days or more = high risk',
  'ফাঁকা থাকলে ঝুঁকির কলামে "নিয়ম বসানো নেই" দেখায়।', 'Blank = the risk column says "rule not set".', 522)
 on conflict (key) do nothing;

create or replace function public.c2_can_read_customers() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.rpt_grant('report_customers') or public.rpt_grant('view_reports') or public.can_do('POS', 'view'));
$$;

create or replace function public._c2_audit(p_action text, p_table text, p_id text, p_detail jsonb) returns void language sql security definer set search_path = public as $$
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail) values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), p_action, p_table, p_id, p_detail);
$$;

-- owner or the credit-limit right sets the days; every change is an audit line (the customers audit trigger) plus the reason
create or replace function public.c2_customer_credit_days_set(p_customer uuid, p_days int, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.customers;
begin
  if not public.is_active() or not (public.is_owner() or public.has_grant('customer_manage')) then raise exception 'not allowed'; end if;
  select * into c from public.customers where id = p_customer for update;
  if not found then raise exception 'customer_not_found'; end if;
  if p_days is not null and (p_days < 0 or p_days > 3650) then raise exception 'bad_days'; end if;
  if c.credit_days is not distinct from p_days then return jsonb_build_object('id', c.id, 'credit_days', c.credit_days, 'noop', true); end if;
  if c.credit_days is not null and nullif(btrim(p_reason), '') is null then raise exception 'reason_required'; end if;
  update public.customers set credit_days = p_days where id = c.id;
  perform public._c2_audit('credit_days_set', 'customers', c.id::text, jsonb_build_object('from', c.credit_days, 'to', p_days, 'reason', left(btrim(p_reason), 300)));
  return jsonb_build_object('id', c.id, 'credit_days', p_days);
end $$;

-- #138
create or replace function public.c2_credit_risk(p_as_of date default null, p_only_overdue boolean default false, p_search text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare asof date := coalesce(p_as_of, public._dhaka_today()); def int := public.rule_num('credit_default_days')::int; watch int := public.rule_num('credit_risk_watch_days')::int; hi int := public.rule_num('credit_risk_high_days')::int;
        mob boolean := public.can_do('POS', 'view') or public.rpt_mobile_ok(); rows jsonb; sm jsonb; q text := nullif(lower(btrim(p_search)), '');
begin
  if not public.c2_can_read_customers() then raise exception 'not allowed'; end if;
  if asof > public._dhaka_today() then raise exception 'bad_date'; end if;
  with s as (select x.id, x.customer_id, x.sale_date, x.sold_at, x.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = x.id and not p.voided), 0) as rem
               from public.sales x where x.status = 'done' and x.customer_id is not null and x.sale_date <= asof),
       items as (select cu.id as cid, 0 as ord, public._w1a_cust_open_date(cu.id) as d, public._w1a_cust_open_date(cu.id)::timestamptz as at, public._w1a_cust_open(cu.id) as amt from public.customers cu where public._w1a_cust_open(cu.id) > 0
                 union all select customer_id, 1, sale_date, sold_at, rem from s where rem > 0),
       coll as (select z.customer_id as cid, sum(z.a) as c from (
                  select customer_id, amount as a from public.sale_payments where kind = 'collection' and not voided and customer_id is not null and (paid_at at time zone 'Asia/Dhaka')::date <= asof
                  union all select customer_id, credit_amount from public.sale_returns where status = 'done' and customer_id is not null and credit_amount > 0 and (created_at at time zone 'Asia/Dhaka')::date <= asof) z group by 1),
       cum as (select i.*, sum(i.amt) over (partition by i.cid order by i.ord, i.at) as cr from items i),
       op as (select m.cid, m.d, least(m.amt, greatest(m.cr - coalesce(cl.c, 0), 0)) as open_amt from cum m left join coll cl on cl.cid = m.cid),
       cust as (select cu.id, cu.name, cu.mobile, cu.credit_limit, cu.credit_days, coalesce(cu.credit_days, def) as terms, case when cu.credit_days is not null then 'customer' when def is not null then 'default' else 'none' end as terms_source
                  from public.customers cu where q is null or lower(cu.name) like '%' || q || '%' or cu.mobile like '%' || q || '%'),
       agg as (select c.*, coalesce(sum(o.open_amt), 0) as balance, min(o.d) filter (where o.open_amt > 0) as oldest,
                      coalesce(sum(o.open_amt) filter (where c.terms is not null and o.d is not null and o.d + c.terms < asof), 0) as overdue,
                      coalesce(sum(o.open_amt) filter (where c.terms is not null and o.d is not null and o.d + c.terms >= asof), 0) as not_due,
                      coalesce(sum(o.open_amt) filter (where o.d is null), 0) as undated,
                      max(asof - (o.d + c.terms)) filter (where c.terms is not null and o.d is not null and o.d + c.terms < asof and o.open_amt > 0) as days_past_due
                 from cust c join op o on o.cid = c.id group by c.id, c.name, c.mobile, c.credit_limit, c.credit_days, c.terms, c.terms_source having coalesce(sum(o.open_amt), 0) > 0),
       adv as (select m.customer_id as cid, sum(case when m.kind = 'cust_advance' then m.amount else 0 end) as held_in, sum(case when m.kind = 'cust_advance_used' then m.amount else 0 end) as used,
                      sum(case when m.kind = 'cust_advance' then m.amount else -m.amount end) as net
                 from public.cash_moves m where m.status = 'done' and m.kind like 'cust_advance%' and m.move_date <= asof group by 1),
       r as (select a.*, ad.net as advance_held, ad.used as advance_applied,
                    case when a.credit_limit is not null and a.credit_limit > 0 then round(100.0 * a.balance / a.credit_limit, 1) end as limit_used_pct,
                    case when a.credit_limit is not null and a.balance > a.credit_limit then true else false end as over_limit,
                    case when a.terms is null then 'no_terms' when a.overdue <= 0 then 'ok' when watch is null or hi is null then 'rule_not_set'
                         when a.days_past_due >= hi then 'high' when a.days_past_due >= watch then 'watch' else 'ok' end as risk
               from agg a left join adv ad on ad.cid = a.id where not p_only_overdue or a.overdue > 0)
  select (select coalesce(jsonb_agg(jsonb_build_object('customer_id', id, 'name', name, 'mobile', case when mob then mobile end, 'balance', balance, 'oldest_open', oldest, 'credit_days', credit_days, 'terms_days', terms, 'terms_source', terms_source,
            'overdue', case when terms is null then null else overdue end, 'not_yet_due', case when terms is null then null else not_due end, 'days_past_due', days_past_due, 'undated', undated,
            'credit_limit', credit_limit, 'limit_used_pct', limit_used_pct, 'over_limit', over_limit, 'advance_held', coalesce(advance_held, 0), 'advance_applied', coalesce(advance_applied, 0), 'risk', risk)
            order by overdue desc, balance desc), '[]'::jsonb) from r),
         (select jsonb_build_object('customers_owing', count(*), 'balance_total', coalesce(sum(balance), 0), 'overdue_total', coalesce(sum(overdue) filter (where terms is not null), 0), 'customers_overdue', count(*) filter (where overdue > 0 and terms is not null),
            'owing_without_terms', count(*) filter (where terms is null), 'balance_without_terms', coalesce(sum(balance) filter (where terms is null), 0), 'over_limit', count(*) filter (where over_limit),
            'watch', count(*) filter (where risk = 'watch'), 'high', count(*) filter (where risk = 'high'), 'rule_not_set', count(*) filter (where risk = 'rule_not_set'),
            'default_days', def, 'watch_days', watch, 'high_days', hi) from r)
    into rows, sm;
  return jsonb_build_object('as_of', asof, 'notes', (case when watch is null or hi is null then '["risk_rule_not_set"]'::jsonb else '[]'::jsonb end) || (case when def is null then '["no_default_terms"]'::jsonb else '[]'::jsonb end)
                                                   || '["same_oldest_first_rule_as_dues_list"]'::jsonb || (case when mob then '[]'::jsonb else '["mobile_hidden"]'::jsonb end), 'summary', sm, 'rows', rows);
end $$;

create or replace function public.c2_credit_terms_list() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.c2_can_read_customers() then raise exception 'not allowed'; end if;
  return jsonb_build_object('can_edit', public.is_owner() or public.has_grant('customer_manage'), 'default_days', public.rule_num('credit_default_days'), 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('customer_id', c.id, 'name', c.name, 'credit_days', c.credit_days, 'credit_limit', c.credit_limit) order by c.name) from public.customers c where c.credit_days is not null), '[]'::jsonb));
end $$;

-- amounts that no customer line carries
create or replace function public.c2_dues_not_linked_notice() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare items jsonb := '[]'::jsonb; a numeric; n int; ar bigint; acct boolean := public._acct_view() and public._acct_all(); st date;
begin
  if not public.c2_can_read_customers() then raise exception 'not allowed'; end if;
  if not public.rule_on('open_parties_link') then
    select coalesce(sum(opening_balance), 0), count(*) into a, n from public.customers where coalesce(opening_balance, 0) > 0;
    if n > 0 then items := items || jsonb_build_object('code', 'opening_not_counted', 'amount', a, 'count', n, 'fix_route', 'openparties'); end if;
  end if;
  select coalesce(sum(due_amount), 0), count(*) into a, n from public.sales where status = 'done' and customer_id is null and due_amount > 0;
  if n > 0 then items := items || jsonb_build_object('code', 'sales_due_no_customer', 'amount', a, 'count', n, 'fix_route', 'dues'); end if;
  st := public._acct_start();
  if acct and st is not null then
    select account_id into ar from public.acct_mappings where key = 'receivable';
    if ar is not null then
      select coalesce(sum(debit - credit), 0), count(*) into a, n from public.journal_lines where account_id = ar and party_id is null;
      if n > 0 and abs(a) > 0.004 then items := items || jsonb_build_object('code', 'journal_receivable_no_customer', 'amount', a, 'count', n, 'fix_route', 'accounts'); end if;
    end if;
  end if;
  return jsonb_build_object('items', items, 'journal_checked', acct and st is not null, 'open_parties_link_on', public.rule_on('open_parties_link'));
end $$;

do $c2$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^_?c2_' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname !~ '^_' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $c2$;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase454.sql
-- ============================================================
-- Phase 454 - RPT-C2 / R5 part 2 (reports #139 customer lifetime value, #140 complaints and returns per customer, #141 special-order (cake) history per customer, and the customer card). READ ONLY.
-- Run AFTER phase 453. New file only. Does not touch the CRM tables (phases 300-340). Paste twice = no error.
--
--   c2_customer_ltv(from, to, search, limit, customer)   all-time by default - NO 365-day cap (the hub report refuses ranges over 365 days). Orders, revenue, returns, net revenue, first and last sale, days
--        as a customer. Gross margin only with the cost right and only over the sales whose cost is fully known, with the coverage shown (sales with a known cost / all sales) - never an estimate.
--        Sales with no customer are counted apart so the reader sees how much of the revenue the table covers.
--   c2_customer_returns(from, to, search, customer)   sale returns (sale_returns) per customer + complaints written on the paper register 20-3, matched by the phone number written on the sheet.
--        A sheet with no phone, or a phone that is not a customer, cannot be linked: they are COUNTED apart (the paper form has the phone as an optional box).
--   c2_customer_special_orders(from, to, search, customer)   cake / custom orders per customer: app orders with a cake specification (phase 445) and paper 20-1 custom sheets, matched by mobile number;
--        flavours and weights as written, last special order, birthday and anniversary as entered (blank = not entered, never a guess).
--   c2_customer_card(customer)   one customer: terms and dues (phase 453), lifetime value, returns and complaints, the last special orders.
--   Open to the existing customer-report access (owner, report_customers, view_reports, or POS view). Mobile numbers are shown to POS viewers and people with the mobile right only.
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.c2_credit_risk(date,boolean,text)') is null then raise exception 'phase454 needs phase453 pasted first'; end if;
end $guard$;

create or replace function public._c2_mob(p text) returns text language plpgsql immutable as $$
begin return public.norm_mobile(p); exception when others then return null; end $$;

-- #139
create or replace function public.c2_customer_ltv(p_from date default null, p_to date default null, p_search text default null, p_limit int default 200, p_customer uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lim int := least(greatest(coalesce(p_limit, 200), 1), 2000); mob boolean := public.can_do('POS', 'view') or public.rpt_mobile_ok(); cost boolean := public.rpt_cost_ok();
        q text := nullif(lower(btrim(p_search)), ''); d1 date := coalesce(p_from, date '2000-01-01'); d2 date := coalesce(p_to, public._dhaka_today()); rows jsonb; sm jsonb; today date := public._dhaka_today();
begin
  if not public.c2_can_read_customers() then raise exception 'not allowed'; end if;
  if (p_from is null) <> (p_to is null) then raise exception 'bad_date: give both dates or none (none = all time)'; end if;
  if p_from is not null and p_to < p_from then raise exception 'bad_date'; end if;
  with s as (select x.id, x.customer_id, x.sale_date, x.total,
                    (select count(*) from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = x.id::text) as lrows,
                    (select count(*) from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = x.id::text and coalesce(l.unit_cost, 0) <= 0) as lnocost,
                    (select sum(-l.qty_delta * l.unit_cost) from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = x.id::text) as gcost
               from public.sales x where x.status = 'done' and x.sale_date between d1 and d2),
       a as (select s.customer_id, count(*) as orders, sum(s.total) as revenue, min(s.sale_date) as first_sale, max(s.sale_date) as last_sale,
                    count(*) filter (where s.lrows > 0 and s.lnocost = 0) as costed, sum(s.total - s.gcost) filter (where s.lrows > 0 and s.lnocost = 0) as margin
               from s where s.customer_id is not null group by s.customer_id),
       rt as (select r.customer_id, count(*) as n, sum(r.amount) as amt from public.sale_returns r where r.status = 'done' and r.customer_id is not null and (r.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 group by 1),
       j as (select cu.id, cu.name, cu.mobile, cu.type, cu.active, a.orders, a.revenue, coalesce(rt.amt, 0) as returns, coalesce(rt.n, 0) as return_count, a.revenue - coalesce(rt.amt, 0) as net_revenue, a.first_sale, a.last_sale,
                    a.last_sale - a.first_sale as days_as_customer, today - a.last_sale as days_since_last, round(a.revenue / a.orders, 2) as avg_order, a.costed, a.margin
               from a join public.customers cu on cu.id = a.customer_id left join rt on rt.customer_id = a.customer_id
              where (p_customer is null or cu.id = p_customer) and (q is null or lower(cu.name) like '%' || q || '%' or cu.mobile like '%' || q || '%')),
       t as (select * from j order by net_revenue desc, orders desc limit lim)
  select (select coalesce(jsonb_agg(jsonb_build_object('customer_id', id, 'name', name, 'mobile', case when mob then mobile end, 'type', type, 'active', active, 'orders', orders, 'revenue', revenue, 'returns', returns, 'return_count', return_count,
            'net_revenue', net_revenue, 'avg_order', avg_order, 'first_sale', first_sale, 'last_sale', last_sale, 'days_as_customer', days_as_customer, 'days_since_last', days_since_last,
            'gross_margin', case when cost then margin end, 'sales_with_known_cost', case when cost then costed end) order by net_revenue desc, orders desc), '[]'::jsonb) from t),
         (select jsonb_build_object('customers', count(*), 'orders', coalesce(sum(orders), 0), 'revenue', coalesce(sum(revenue), 0), 'returns', coalesce(sum(returns), 0), 'net_revenue', coalesce(sum(net_revenue), 0),
            'shown', least(count(*), lim), 'window_from', p_from, 'window_to', p_to,
            'sales_without_customer', (select count(*) from s where s.customer_id is null), 'revenue_without_customer', (select coalesce(sum(total), 0) from s where s.customer_id is null)) from j)
    into rows, sm;
  return jsonb_build_object('all_time', p_from is null, 'notes', (case when cost then '[]'::jsonb else '["cost_hidden"]'::jsonb end) || '["margin_only_where_cost_known"]'::jsonb || (case when mob then '[]'::jsonb else '["mobile_hidden"]'::jsonb end),
    'summary', sm, 'rows', rows);
end $$;

-- #140
create or replace function public.c2_customer_returns(p_from date, p_to date, p_search text default null, p_customer uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare mob boolean := public.can_do('POS', 'view') or public.rpt_mobile_ok(); q text := nullif(lower(btrim(p_search)), ''); rows jsonb; sm jsonb;
begin
  if not public.c2_can_read_customers() then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  with r as (select x.customer_id, count(*) as returns, sum(x.amount) as ret_amt, max((x.created_at at time zone 'Asia/Dhaka')::date) as last_return,
                    (select y.reason_code from public.sale_returns y where y.customer_id = x.customer_id and y.status = 'done' and (y.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to group by y.reason_code order by count(*) desc, y.reason_code limit 1) as top_reason
               from public.sale_returns x where x.status = 'done' and x.customer_id is not null and (x.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to and public.can_loc(x.location_id) group by x.customer_id),
       e as (select public._c2_mob(en.data ->> 'cust_phone') as mobile, en.id, en.entry_date,
                    (en.data ->> 'c_sick') = 'true' as sick, coalesce(public._c2_num(en.data -> 'refund_amt'), 0) as refund_amt,
                    array_remove(array[case when (en.data ->> 'c_taste') = 'true' then 'taste' end, case when (en.data ->> 'c_smell') = 'true' then 'smell' end, case when (en.data ->> 'c_broken') = 'true' then 'broken' end,
                                       case when (en.data ->> 'c_short') = 'true' then 'short' end, case when (en.data ->> 'c_wrong') = 'true' then 'wrong' end, case when (en.data ->> 'c_late') = 'true' then 'late' end,
                                       case when (en.data ->> 'c_staff') = 'true' then 'staff' end, case when (en.data ->> 'c_sick') = 'true' then 'sick' end, case when (en.data ->> 'c_other') = 'true' then 'other' end], null) as causes
               from public.entries en where en.form_code = '20-3' and en.status in ('submitted', 'approved') and en.entry_date between p_from and p_to and public.can_loc(en.location_id)),
       ec as (select cu.id as customer_id, count(*) as complaints, count(*) filter (where e.sick) as sick_cases, sum(e.refund_amt) as refund_amt, max(e.entry_date) as last_complaint,
                     (select coalesce(jsonb_object_agg(c, n), '{}'::jsonb) from (select u.c, count(*) as n from e e2 cross join lateral unnest(e2.causes) as u(c) where e2.mobile = cu.mobile group by u.c) z) as causes
                from e join public.customers cu on cu.mobile = e.mobile group by cu.id, cu.mobile),
       j as (select cu.id, cu.name, cu.mobile, coalesce(r.returns, 0) as returns, coalesce(r.ret_amt, 0) as return_amount, r.last_return, r.top_reason, coalesce(ec.complaints, 0) as complaints, coalesce(ec.sick_cases, 0) as sick_cases,
                    coalesce(ec.refund_amt, 0) as complaint_refunds, ec.last_complaint, coalesce(ec.causes, '{}'::jsonb) as causes
               from public.customers cu left join r on r.customer_id = cu.id left join ec on ec.customer_id = cu.id
              where (r.customer_id is not null or ec.customer_id is not null) and (p_customer is null or cu.id = p_customer) and (q is null or lower(cu.name) like '%' || q || '%' or cu.mobile like '%' || q || '%'))
  select (select coalesce(jsonb_agg(jsonb_build_object('customer_id', id, 'name', name, 'mobile', case when mob then mobile end, 'returns', returns, 'return_amount', return_amount, 'last_return', last_return, 'top_reason', top_reason,
            'complaints', complaints, 'sick_cases', sick_cases, 'complaint_refunds', complaint_refunds, 'last_complaint', last_complaint, 'causes', causes) order by returns + complaints desc, return_amount desc), '[]'::jsonb) from j),
         jsonb_build_object('customers', (select count(*) from j), 'returns', (select coalesce(sum(returns), 0) from j), 'return_amount', (select coalesce(sum(return_amount), 0) from j), 'complaints_linked', (select coalesce(sum(complaints), 0) from j),
           'complaint_sheets_total', (select count(*) from e), 'complaint_sheets_without_phone', (select count(*) from e where e.mobile is null),
           'complaint_sheets_phone_not_a_customer', (select count(*) from e where e.mobile is not null and not exists (select 1 from public.customers c2 where c2.mobile = e.mobile)),
           'returns_without_customer', (select count(*) from public.sale_returns x where x.status = 'done' and x.customer_id is null and (x.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to and public.can_loc(x.location_id)))
    into rows, sm;
  return jsonb_build_object('from', p_from, 'to', p_to, 'notes', '["complaints_matched_by_phone","paper_20_3_phone_optional"]'::jsonb || (case when mob then '[]'::jsonb else '["mobile_hidden"]'::jsonb end), 'summary', sm, 'rows', rows);
end $$;

-- the next yearly date (birthday, anniversary) on or after today; 29 February falls on 1 March in a year that has none
create or replace function public._c2_next_annual(p_date date, p_today date) returns date language plpgsql immutable as $$
declare y int := extract(year from p_today)::int; d date;
begin
  if p_date is null then return null; end if;
  for i in 0..1 loop
    begin d := make_date(y + i, extract(month from p_date)::int, extract(day from p_date)::int);
    exception when others then d := make_date(y + i, 3, 1); end;
    if d >= p_today then return d; end if;
  end loop;
  return null;
end $$;

-- #141
create or replace function public.c2_customer_special_orders(p_from date, p_to date, p_search text default null, p_customer uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare mob boolean := public.can_do('POS', 'view') or public.rpt_mobile_ok(); q text := nullif(lower(btrim(p_search)), ''); rows jsonb; per jsonb; cnt int; unmatched int; today date := public._dhaka_today();
begin
  if not public.c2_can_read_customers() then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  with base as (select * from public._c2_orders_base(p_from, p_to, null, 'order')),
       t as (
         select 'app'::text as source, b.ref, b.order_id, null::uuid as entry_id, public._c2_mob(o.customer_mobile) as mobile, b.customer_name, b.order_date, b.promised_date as delivery_date, b.status, b.total,
                c.flavour, c.weight_kg, c.message, c.design
           from base b join public.online_orders o on o.id = b.order_id join public.order_cake_specs c on c.order_id = b.order_id and c.state = 'active' where b.source = 'app'
         union all
         select 'paper_20_1', b.ref, null::uuid, b.entry_id, public._c2_mob(e.data ->> 'cust_phone'), b.customer_name, b.order_date, b.promised_date, b.status, b.total,
                nullif(btrim(i.v ->> 'desc'), ''), null::numeric, nullif(btrim(i.v ->> 'msg'), ''), nullif(btrim(i.v ->> 'design'), '')
           from base b join public.entries e on e.id = b.entry_id
           cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'items') = 'array' and jsonb_array_length(e.data -> 'items') > 0 then e.data -> 'items' else '[{}]'::jsonb end) as i(v)
          where b.source = 'paper_20_1' and b.order_type = 'cake'),
       m as (select t.*, cu.id as customer_id, cu.name as cname, cu.mobile as cmobile, cu.birthday, cu.anniversary from t left join public.customers cu on cu.mobile = t.mobile
              where (p_customer is null or cu.id = p_customer) and (q is null or lower(coalesce(cu.name, t.customer_name, '')) like '%' || q || '%' or coalesce(t.mobile, '') like '%' || q || '%'))
  select (select coalesce(jsonb_agg(jsonb_build_object('customer_id', customer_id, 'name', coalesce(cname, customer_name), 'mobile', case when mob then mobile end, 'source', source, 'ref', ref, 'order_id', order_id, 'entry_id', entry_id,
            'order_date', order_date, 'delivery_date', delivery_date, 'status', status, 'total', total, 'flavour', flavour, 'weight_kg', weight_kg, 'message', message, 'design', design) order by order_date desc, ref), '[]'::jsonb) from m),
         (select coalesce(jsonb_agg(jsonb_build_object('customer_id', z.customer_id, 'name', z.cname, 'mobile', case when mob then z.cmobile end, 'special_orders', z.n, 'first', z.first_d, 'last', z.last_d, 'flavours', z.flavours,
            'birthday', z.birthday, 'anniversary', z.anniversary, 'next_birthday_in_days', case when z.birthday is null then null else public._c2_next_annual(z.birthday, today) - today end,
            'next_anniversary_in_days', case when z.anniversary is null then null else public._c2_next_annual(z.anniversary, today) - today end) order by z.n desc, z.last_d desc), '[]'::jsonb) from (
            select customer_id, cname, cmobile, birthday, anniversary, count(*) as n, min(order_date) as first_d, max(order_date) as last_d,
                   (select coalesce(jsonb_agg(f), '[]'::jsonb) from (select distinct lower(m2.flavour) as f from m m2 where m2.customer_id = m.customer_id and m2.flavour is not null limit 5) fl) as flavours
              from m where customer_id is not null group by customer_id, cname, cmobile, birthday, anniversary) z),
         (select count(*) from m), (select count(*) from m where customer_id is null), (select count(distinct customer_id) from m where customer_id is not null)
    into rows, per, cnt, unmatched;
  return jsonb_build_object('from', p_from, 'to', p_to, 'module_on', public.rule_on('online_orders_on'), 'notes', '["matched_by_mobile","sources_not_merged"]'::jsonb || (case when public.rule_on('online_orders_on') then '[]'::jsonb else '["module_off"]'::jsonb end) || (case when mob then '[]'::jsonb else '["mobile_hidden"]'::jsonb end),
    'summary', jsonb_build_object('special_order_rows', cnt, 'rows_without_a_customer_match', unmatched, 'customers', (select count(*) from jsonb_array_elements(per))), 'customers', per, 'rows', rows);
end $$;

-- the customer card (drill-down from any customer report)
create or replace function public.c2_customer_card(p_customer uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c public.customers; mob boolean := public.can_do('POS', 'view') or public.rpt_mobile_ok(); risk jsonb; ltv jsonb; ret jsonb; so jsonb; d1 date := public._dhaka_today() - 365; d2 date := public._dhaka_today();
begin
  if not public.c2_can_read_customers() then raise exception 'not allowed'; end if;
  select * into c from public.customers where id = p_customer;
  if not found then raise exception 'customer_not_found'; end if;
  risk := public.c2_credit_risk(null, false, c.mobile);
  ltv := public.c2_customer_ltv(null, null, null, 1, c.id);
  ret := public.c2_customer_returns(d1, d2, null, c.id);
  so := public.c2_customer_special_orders(d1, d2, null, c.id);
  return jsonb_build_object('customer', jsonb_build_object('id', c.id, 'name', c.name, 'mobile', case when mob then c.mobile end, 'type', c.type, 'active', c.active, 'credit_limit', c.credit_limit, 'credit_days', c.credit_days,
            'default_credit_days', public.rule_num('credit_default_days'), 'birthday', c.birthday, 'anniversary', c.anniversary, 'customer_since', c.customer_since),
    'credit', (select r from jsonb_array_elements(risk -> 'rows') r where r ->> 'customer_id' = c.id::text limit 1), 'credit_notes', risk -> 'notes',
    'ltv', (select r from jsonb_array_elements(ltv -> 'rows') r limit 1), 'returns_last_365_days', (select r from jsonb_array_elements(ret -> 'rows') r limit 1), 'returns_summary', ret -> 'summary',
    'special_orders_last_365_days', so -> 'rows', 'can_edit_terms', public.is_owner() or public.has_grant('customer_manage'));
end $$;

do $c2$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^_?c2_' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname !~ '^_' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $c2$;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase455.sql
-- ============================================================
-- Phase 455 - RPT-C2 / R6 part 1 (reports #142 attendance summary for a period, #147 overtime and late variance, and the salary-basis notice for the T3 / T4 staff-cost reports). READ ONLY.
-- Run AFTER phase 454. New file only. Paste twice = no error.
--
--   Source: the app's day records (attendance_days: punches, late, early, worked and overtime minutes). The hub report attendance_summary reads the paper sheet 02-1 only and shows nothing while the app
--   holds the days; this report reads the app days and says how many paper 02-1 sheets exist beside them (their data is NOT added).
--   c2_att_period_summary(from, to, place, employee)   per person: days by status, late days / minutes, early-leave minutes, worked minutes, overtime (approved / waiting), single-punch days, manual days,
--        scheduled minutes and variance (worked - scheduled) ONLY over days that have a shift - days without a shift are counted apart; calendar days with no record at all are counted apart.
--   c2_att_person_days(employee, from, to)             the day rows behind one person (drill-down).
--   c2_salary_basis(from, to, place)                   the salary figure the staff-cost and profit reports (T3, T4, L1) use, beside the 02-2 paper sheets and the counted / paid payroll runs, the two
--        settings that decide which one is used, and the difference. Needs the salary right (salary_view) or the owner. Does not change any report.
--   Who: the owner, a holder of report_staff / view_reports for the person's place, or anyone who may already see that person's attendance (own record, attendance_manage, employee_view, employee_manage).
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.c2_customer_card(uuid)') is null then raise exception 'phase455 needs phase454 pasted first'; end if;
end $guard$;

create or replace function public.c2_can_read_staff() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active();
$$;
-- one employee row is visible when the existing attendance rule allows it, or the person holds a staff report right for that place
create or replace function public._c2_emp_visible(p_emp uuid) returns boolean language sql stable security definer set search_path = public as $$
  select public._att_view(p_emp) or (public.rpt_access('staff') and exists (select 1 from public.employees e where e.id = p_emp and e.primary_location_id is not null and public.can_loc(e.primary_location_id)));
$$;
create or replace function public._c2_shift_minutes(p_start time, p_end time, p_cross boolean, p_break int) returns int language sql immutable as $$
  select ((extract(epoch from p_end) - extract(epoch from p_start)) / 60)::int + case when p_cross or p_end <= p_start then 1440 else 0 end - coalesce(p_break, 0);
$$;

create or replace function public.c2_att_period_summary(p_from date, p_to date, p_loc int default null, p_employee uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare today date := public._dhaka_today(); rows jsonb; sm jsonb; paper int; last_d date := least(p_to, today);
begin
  if not public.c2_can_read_staff() then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  with emp as (select e.id, e.employee_no, e.full_name_bn, e.full_name_en, e.primary_location_id as loc, e.joining_date, e.status
                 from public.employees e
                where e.status in ('active', 'on_leave', 'resigned', 'terminated', 'retired') and public._c2_emp_visible(e.id) and (p_loc is null or e.primary_location_id = p_loc) and (p_employee is null or e.id = p_employee)
                  and (e.status in ('active', 'on_leave') or exists (select 1 from public.attendance_days a where a.employee_id = e.id and a.day between p_from and p_to))),
       d as (select a.*, s.id as sid, case when s.id is not null then public._c2_shift_minutes(s.start_time, s.end_time, s.crosses_midnight, s.break_min) end as sched
               from public.attendance_days a join emp on emp.id = a.employee_id left join public.shifts s on s.id = a.shift_id where a.day between p_from and p_to),
       agg as (select d.employee_id,
                      count(*) as days_with_record,
                      count(*) filter (where d.status = 'present') as present, count(*) filter (where d.status = 'late') as late_status, count(*) filter (where d.status = 'absent') as absent,
                      count(*) filter (where d.status = 'half_day') as half_day, count(*) filter (where d.status = 'leave') as leave, count(*) filter (where d.status = 'unpaid') as unpaid,
                      count(*) filter (where d.status = 'off') as off, count(*) filter (where d.status = 'holiday') as holiday,
                      count(*) filter (where d.late_minutes > 0) as late_days, coalesce(sum(d.late_minutes), 0) as late_minutes, coalesce(sum(d.early_leave_minutes), 0) as early_leave_minutes,
                      coalesce(sum(d.worked_minutes), 0) as worked_minutes, coalesce(sum(d.ot_minutes), 0) as ot_minutes, coalesce(sum(d.ot_minutes) filter (where d.ot_approved), 0) as ot_approved_minutes,
                      coalesce(sum(d.ot_minutes) filter (where not d.ot_approved), 0) as ot_waiting_minutes,
                      count(*) filter (where d.single_punch) as single_punch_days, count(*) filter (where d.source = 'manual') as manual_days,
                      count(*) filter (where d.status in ('present', 'late', 'half_day') and d.sched is not null) as days_with_shift, count(*) filter (where d.status in ('present', 'late', 'half_day') and d.sched is null) as days_without_shift,
                      sum(d.sched) filter (where d.status in ('present', 'late', 'half_day') and d.sched is not null) as scheduled_minutes,
                      sum(d.worked_minutes - d.sched) filter (where d.status in ('present', 'late', 'half_day') and d.sched is not null) as variance_minutes
                 from d group by d.employee_id),
       r as (select emp.*, greatest(last_d - greatest(p_from, coalesce(emp.joining_date, p_from)) + 1, 0) as expected_days, agg.*
               from emp left join agg on agg.employee_id = emp.id)
  select (select coalesce(jsonb_agg(jsonb_build_object('employee_id', id, 'employee_no', employee_no, 'name_bn', full_name_bn, 'name_en', full_name_en, 'loc', loc, 'status', status,
            'calendar_days', expected_days, 'days_with_record', coalesce(days_with_record, 0), 'days_without_record', greatest(expected_days - coalesce(days_with_record, 0), 0),
            'present', coalesce(present, 0), 'late_status', coalesce(late_status, 0), 'absent', coalesce(absent, 0), 'half_day', coalesce(half_day, 0), 'leave', coalesce(leave, 0), 'unpaid', coalesce(unpaid, 0), 'off', coalesce(off, 0), 'holiday', coalesce(holiday, 0),
            'late_days', coalesce(late_days, 0), 'late_minutes', coalesce(late_minutes, 0), 'early_leave_minutes', coalesce(early_leave_minutes, 0), 'worked_minutes', coalesce(worked_minutes, 0),
            'ot_minutes', coalesce(ot_minutes, 0), 'ot_approved_minutes', coalesce(ot_approved_minutes, 0), 'ot_waiting_minutes', coalesce(ot_waiting_minutes, 0),
            'single_punch_days', coalesce(single_punch_days, 0), 'manual_days', coalesce(manual_days, 0), 'days_with_shift', coalesce(days_with_shift, 0), 'days_without_shift', coalesce(days_without_shift, 0),
            'scheduled_minutes', scheduled_minutes, 'variance_minutes', variance_minutes) order by coalesce(full_name_en, full_name_bn), id), '[]'::jsonb) from r),
         (select jsonb_build_object('people', count(*), 'people_with_no_record_at_all', count(*) filter (where coalesce(days_with_record, 0) = 0), 'days_with_record', coalesce(sum(days_with_record), 0),
            'days_without_record', coalesce(sum(greatest(expected_days - coalesce(days_with_record, 0), 0)), 0), 'late_days', coalesce(sum(late_days), 0), 'late_minutes', coalesce(sum(late_minutes), 0), 'absent', coalesce(sum(absent), 0),
            'worked_minutes', coalesce(sum(worked_minutes), 0), 'ot_minutes', coalesce(sum(ot_minutes), 0), 'ot_waiting_minutes', coalesce(sum(ot_waiting_minutes), 0),
            'scheduled_minutes', sum(scheduled_minutes), 'variance_minutes', sum(variance_minutes), 'days_without_shift', coalesce(sum(days_without_shift), 0)) from r)
    into rows, sm;
  select count(*) into paper from public.entries en where en.form_code = '02-1' and en.status in ('submitted', 'approved') and en.entry_date between p_from and p_to and public.can_loc(en.location_id) and (p_loc is null or en.location_id = p_loc);
  return jsonb_build_object('from', p_from, 'to', p_to, 'notes', '["app_days_only","calendar_days_without_record_counted_apart","variance_only_days_with_a_shift"]'::jsonb || (case when paper > 0 then '["paper_02_1_not_included"]'::jsonb else '[]'::jsonb end),
    'paper_02_1_sheets_in_range', paper, 'summary', sm, 'rows', rows);
end $$;

create or replace function public.c2_att_person_days(p_employee uuid, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.c2_can_read_staff() or not public._c2_emp_visible(p_employee) then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  return jsonb_build_object('employee_id', p_employee, 'from', p_from, 'to', p_to, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('day', a.day, 'status', a.status, 'day_kind', a.day_kind, 'first_in', a.first_in at time zone 'Asia/Dhaka', 'last_out', a.last_out at time zone 'Asia/Dhaka', 'worked_minutes', a.worked_minutes,
             'late_minutes', a.late_minutes, 'early_leave_minutes', a.early_leave_minutes, 'ot_minutes', a.ot_minutes, 'ot_approved', a.ot_approved, 'punch_count', a.punch_count, 'single_punch', a.single_punch, 'source', a.source,
             'shift_id', a.shift_id, 'scheduled_minutes', case when s.id is not null then public._c2_shift_minutes(s.start_time, s.end_time, s.crosses_midnight, s.break_min) end,
             'variance_minutes', case when s.id is not null and a.status in ('present', 'late', 'half_day') then a.worked_minutes - public._c2_shift_minutes(s.start_time, s.end_time, s.crosses_midnight, s.break_min) end, 'note', a.note) order by a.day)
      from public.attendance_days a left join public.shifts s on s.id = a.shift_id where a.employee_id = p_employee and a.day between p_from and p_to), '[]'::jsonb));
end $$;

-- the salary basis notice
create or replace function public.c2_salary_basis(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; rows jsonb; sm jsonb; src text := coalesce(public.rule_txt('report_salary_source'), 'legacy'); acc boolean := public.rule_on('payroll_accrual_on');
begin
  if not public.is_active() or not (public.is_owner() or public.has_grant('salary_view')) then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  select coalesce(array_agg(l.id), '{}') into locs from public.locations l where public.can_loc(l.id) and (p_loc is null or l.id = p_loc);
  with u as (select o_m as m, sum(o_sal) as reports_use from public._p27_pl(p_from, p_to, locs) group by o_m),
       sh as (select date_trunc('month', e.entry_date)::date as m,
                     sum(coalesce(public._r2_num(r -> 'due'), 0) + coalesce(public._r2_num(r -> 'overtime'), 0) + coalesce(public._r2_num(r -> 'other'), 0)) as sheets, count(distinct e.id) as sheet_count
                from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'pay') = 'array' then e.data -> 'pay' else '[]'::jsonb end) r
               where e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.entry_date between p_from and p_to and e.location_id = any (locs) group by 1),
       cn as (select c.m, sum(c.amt) as runs_counted from public.c_salary_by_month(p_from, p_to, locs) c group by c.m),
       pd as (select r.month as m, sum(l.net + l.advance_recovery) as runs_paid, count(distinct r.id) as paid_runs
                from public.payroll_runs r join public.payroll_lines l on l.run_id = r.id and l.active
               where r.status = 'paid' and r.month between date_trunc('month', p_from)::date and p_to and coalesce(l.location_id, r.location_id) = any (locs) group by 1),
       mm as (select m from u union select m from sh union select m from cn union select m from pd),
       j as (select mm.m, u.reports_use, sh.sheets, sh.sheet_count, cn.runs_counted, pd.runs_paid, pd.paid_runs from mm left join u using (m) left join sh using (m) left join cn using (m) left join pd using (m))
  select (select coalesce(jsonb_agg(jsonb_build_object('month', m, 'reports_use', reports_use, 'sheets_02_2', sheets, 'sheet_count', coalesce(sheet_count, 0), 'runs_counted', runs_counted, 'runs_paid', runs_paid, 'paid_runs', coalesce(paid_runs, 0),
            'difference_runs_minus_reports', case when runs_counted is not null and reports_use is not null then runs_counted - reports_use end,
            'basis', case when runs_counted is null and sheets is not null then 'sheets_only' when runs_counted is not null and (acc or src = 'app_first') then 'runs_first' when runs_counted is not null then 'sheets_while_runs_exist' else 'none' end,
            'mismatch', runs_counted is not null and reports_use is not null and abs(runs_counted - reports_use) > 0.005) order by m), '[]'::jsonb) from j),
         (select jsonb_build_object('reports_use', sum(reports_use), 'sheets_02_2', sum(sheets), 'runs_counted', sum(runs_counted), 'runs_paid', sum(runs_paid), 'months_with_a_mismatch', count(*) filter (where runs_counted is not null and reports_use is not null and abs(runs_counted - reports_use) > 0.005)) from j)
    into rows, sm;
  return jsonb_build_object('from', p_from, 'to', p_to, 'settings', jsonb_build_object('report_salary_source', src, 'payroll_accrual_on', acc),
    'notes', '["reports_t3_t4_l1_use_this_figure","nothing_here_changes_a_report","switch_in_profit_check"]'::jsonb, 'summary', sm, 'rows', rows);
end $$;

do $c2$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^_?c2_' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname !~ '^_' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $c2$;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase456.sql
-- ============================================================
-- Phase 456 - RPT-C2 / R6 part 2 (reports #148 sales per labour hour with punch coverage, #150 cashier-wise cash variance with shift). READ ONLY.
-- Run AFTER phase 455. New file only. Paste twice = no error.
--
--   #150  The daily showroom sheet 14-1 gets a "Cashier" box (web/forms_cash.js, additive; the shift box already exists on the sheet). Data is kept in the sheet's own data (key cashier), so no table changes.
--         c2_cashier_variance(from, to, place)  short / over of each sheet (the flag the phone wrote when the sheet was saved, the same figure as the hub report) grouped by cashier and shift;
--         sheets with no cashier written are listed apart ("cashier not written", with the sheet writer shown) - never given to a guessed person. The status of the shortage case (open / approved /
--         rejected / void) is shown beside the sheet, which the hub report ignores.
--   #148  c2_sales_per_labour_hour(from, to, place)  per place: sales (done sales, returns shown apart), labour hours = worked minutes of present / late / half-day records, and the punch coverage =
--         records with punches / records. Sales per hour is shown ONLY when the hours exist; the coverage is always beside it. Labour hours come from the app's day records, not from paper 02-1.
--   Open to the owner and to holders of the existing report rights (report_cash / report_pos for #150; report_staff / report_sales for #148, view_reports for both).
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.c2_att_period_summary(date,date,int,uuid)') is null then raise exception 'phase456 needs phase455 pasted first'; end if;
end $guard$;

create or replace function public.c2_cashier_variance(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows jsonb; sm jsonb; sheets jsonb;
begin
  if not public.is_active() or not (public.rpt_access('cash') or public.rpt_access('pos') or public.can_do('14-1', 'view')) then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  with x as (
    select e.id, e.location_id, e.entry_date, coalesce(nullif(btrim(e.data ->> 'shift'), ''), 'not_written') as shift, nullif(btrim(e.data ->> 'cashier'), '') as cashier,
           coalesce(nullif(btrim(e.created_staff), ''), '-') as writer,
           coalesce((select sum(public._c2_num(f -> 'amount')) from jsonb_array_elements(case when jsonb_typeof(e.flags) = 'array' then e.flags else '[]'::jsonb end) f where f ->> 'code' = 'cash_short_over'), 0) as so,
           (select c.status from public.shortage_cash_cases c where c.entry_id = e.id) as case_status
      from public.entries e where e.form_code = '14-1' and e.status in ('submitted', 'approved') and e.entry_date between p_from and p_to and public.can_loc(e.location_id) and (p_loc is null or e.location_id = p_loc)),
       n as (select x.*, (select coalesce(emp.full_name_en, emp.full_name_bn) from public.profiles pr join public.employees emp on emp.profile_id = pr.id where pr.staff_id = x.cashier limit 1) as cashier_name from x),
       g as (select cashier, max(cashier_name) as cashier_name, shift, count(*) as sheets, count(*) filter (where so < 0) as short_sheets, count(*) filter (where so > 0) as over_sheets,
                    coalesce(-sum(so) filter (where so < 0), 0) as short_amount, coalesce(sum(so) filter (where so > 0), 0) as over_amount, coalesce(sum(so), 0) as net, coalesce(max(abs(so)), 0) as worst,
                    count(*) filter (where case_status = 'open') as cases_open, count(*) filter (where case_status = 'approved') as cases_approved, count(*) filter (where case_status = 'rejected') as cases_rejected, count(*) filter (where case_status = 'void') as cases_void
               from n group by cashier, shift)
  select (select coalesce(jsonb_agg(to_jsonb(g) - 'cashier' || jsonb_build_object('cashier', coalesce(cashier, ''), 'cashier_written', cashier is not null) order by cashier is null, net, cashier), '[]'::jsonb) from g),
         (select jsonb_build_object('sheets', count(*), 'sheets_without_cashier', count(*) filter (where cashier is null), 'sheets_without_shift', count(*) filter (where shift = 'not_written'), 'short_amount', coalesce(-sum(so) filter (where so < 0), 0),
            'over_amount', coalesce(sum(so) filter (where so > 0), 0), 'net', coalesce(sum(so), 0)) from n),
         (select coalesce(jsonb_agg(jsonb_build_object('entry_id', id, 'loc', location_id, 'day', entry_date, 'shift', shift, 'cashier', cashier, 'writer', writer, 'variance', so, 'case_status', case_status) order by entry_date desc, id) filter (where cashier is null and so <> 0), '[]'::jsonb) from n)
    into rows, sm, sheets;
  return jsonb_build_object('from', p_from, 'to', p_to, 'notes', '["same_flag_as_hub_cash_short_over","case_status_shown","cashier_box_new_on_14_1"]'::jsonb || (case when (sm ->> 'sheets_without_cashier')::int > 0 then '["cashier_not_written_on_some_sheets"]'::jsonb else '[]'::jsonb end),
    'summary', sm, 'rows', rows, 'uncredited_sheets_with_a_variance', sheets);
end $$;

create or replace function public.c2_sales_per_labour_hour(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows jsonb; sm jsonb;
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_access('staff') or public.rpt_access('sales')) then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  with l as (select l.id, l.name_bn, l.name_en from public.locations l where public.can_loc(l.id) and (p_loc is null or l.id = p_loc)),
       s as (select x.location_id, sum(x.total) as sales, count(*) as bills from public.sales x where x.status = 'done' and x.sale_date between p_from and p_to group by 1),
       r as (select y.location_id, sum(y.amount) as returns from public.sale_returns y where y.status = 'done' and (y.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to group by 1),
       a as (select d.location_id, count(*) as staff_days, count(*) filter (where d.punch_count > 0) as days_with_punches, sum(d.worked_minutes) as worked, count(*) filter (where d.single_punch) as single_punch_days
               from public.attendance_days d where d.day between p_from and p_to and d.status in ('present', 'late', 'half_day') and d.location_id is not null group by 1),
       j as (select l.id, l.name_bn, l.name_en, coalesce(s.sales, 0) as sales, coalesce(s.bills, 0) as bills, coalesce(r.returns, 0) as returns, a.staff_days, a.days_with_punches, a.worked, a.single_punch_days
               from l left join s on s.location_id = l.id left join r on r.location_id = l.id left join a on a.location_id = l.id where s.location_id is not null or a.location_id is not null)
  select coalesce(jsonb_agg(jsonb_build_object('loc', id, 'name_bn', name_bn, 'name_en', name_en, 'sales', sales, 'bills', bills, 'returns', returns, 'net_sales', sales - returns,
            'staff_days', coalesce(staff_days, 0), 'labour_hours', case when coalesce(worked, 0) > 0 then round(worked / 60.0, 1) end,
            'punch_coverage_pct', case when coalesce(staff_days, 0) > 0 then round(100.0 * days_with_punches / staff_days, 1) end, 'single_punch_days', coalesce(single_punch_days, 0),
            'sales_per_hour', case when coalesce(worked, 0) > 0 then round((sales - returns) / (worked / 60.0), 2) end,
            'status', case when coalesce(staff_days, 0) = 0 then 'no_attendance_records' when coalesce(worked, 0) = 0 then 'no_hours' when days_with_punches < staff_days then 'partial_punches' else 'ok' end) order by id), '[]'::jsonb),
         jsonb_build_object('places', count(*), 'sales', coalesce(sum(sales), 0), 'returns', coalesce(sum(returns), 0), 'labour_hours', case when coalesce(sum(worked), 0) > 0 then round(sum(worked) / 60.0, 1) end,
            'punch_coverage_pct', case when coalesce(sum(staff_days), 0) > 0 then round(100.0 * sum(days_with_punches) / sum(staff_days), 1) end,
            'sales_per_hour', case when coalesce(sum(worked), 0) > 0 and bool_and(coalesce(worked, 0) > 0) then round((sum(sales) - sum(returns)) / (sum(worked) / 60.0), 2) end,
            'places_without_hours', count(*) filter (where coalesce(worked, 0) = 0))
    into rows, sm from j;
  return jsonb_build_object('from', p_from, 'to', p_to, 'notes', '["hours_from_app_day_records","returns_shown_apart","per_hour_only_where_hours_exist"]'::jsonb, 'summary', sm, 'rows', rows);
end $$;

do $c2$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^_?c2_' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname !~ '^_' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $c2$;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase457.sql
-- ============================================================
-- Phase 457 - RPT-C2 / R6 part 3 (report #149 production output per worker / labour hour): the CREW and HOURS of a production run.
-- Run AFTER phase 456. New file only. Paste twice = no error.
--
--   production_crew   one row per worker on a production run: the employee and the minutes worked on that run. Append-only: changing the crew voids the old rows and writes new ones.
--   c2_production_crew_set(run, crew)   crew = [{employee_id, hours | minutes}]. Allowed: owner or the stock_production right at the run's place. Entered inside the software on the production sheet
--       (paper form code for a printed crew sheet: to be given by owner - none is invented here).
--   c2_crew_pick(place)                 active employees of a place (id and name only - no pay) for the picker.
--   c2_output_per_labour_hour(from, to, place)   per finished product and in total: output, crew minutes, output per labour hour, ONLY over the runs that have a crew; the share of runs with a crew
--       (coverage) is always shown beside it. A run with no crew is counted apart, never given hours.
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.c2_sales_per_labour_hour(date,date,int)') is null then raise exception 'phase457 needs phase456 pasted first'; end if;
end $guard$;

create table if not exists public.production_crew (
  id bigint generated always as identity primary key,
  run_id uuid not null references public.production_runs(id),
  employee_id uuid not null references public.employees(id),
  minutes int not null check (minutes > 0 and minutes <= 1440),
  state text not null default 'active' check (state in ('active', 'void')),
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  void_by uuid, void_at timestamptz, void_note text
);
create unique index if not exists production_crew_live on public.production_crew (run_id, employee_id) where state = 'active';
create index if not exists production_crew_run on public.production_crew (run_id) where state = 'active';
drop trigger if exists production_crew_ro on public.production_crew;
create trigger production_crew_ro before update or delete on public.production_crew for each row execute function public._c2_trail_ro();
drop trigger if exists audit_production_crew on public.production_crew;
create trigger audit_production_crew after insert or update on public.production_crew for each row execute function public.log_change('id');

create or replace function public._c2_can_crew(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('stock_production', p_loc));
$$;

create or replace function public.c2_production_crew_set(p_run uuid, p_crew jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.production_runs; w jsonb; emp public.employees; mins int; nw jsonb := '[]'::jsonb; cur jsonb; seen uuid[] := '{}'; n int := 0;
begin
  select * into r from public.production_runs where id = p_run;
  if not found then raise exception 'not_found'; end if;
  if not public._c2_can_crew(r.location_id) then raise exception 'not allowed'; end if;
  if r.status <> 'done' then raise exception 'run_void'; end if;
  if p_crew is null or jsonb_typeof(p_crew) <> 'array' or jsonb_array_length(p_crew) > 50 then raise exception 'bad_crew'; end if;
  for w in select * from jsonb_array_elements(p_crew) loop
    select * into emp from public.employees where id = nullif(w ->> 'employee_id', '')::uuid;
    if not found or emp.status not in ('active', 'on_leave') then raise exception 'employee_not_active'; end if;
    if emp.id = any (seen) then raise exception 'duplicate_worker'; end if;
    seen := seen || emp.id;
    mins := case when nullif(w ->> 'minutes', '') is not null then (w ->> 'minutes')::numeric::int when nullif(w ->> 'hours', '') is not null then round((w ->> 'hours')::numeric * 60)::int end;
    if mins is null or mins <= 0 or mins > 1440 then raise exception 'bad_minutes: 1 to 1440 minutes (24 hours) for one worker on one run'; end if;
    nw := nw || jsonb_build_object('employee_id', emp.id, 'minutes', mins);
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('employee_id', employee_id, 'minutes', minutes) order by employee_id), '[]'::jsonb) into cur from public.production_crew where run_id = r.id and state = 'active';
  if cur = (select coalesce(jsonb_agg(x order by x ->> 'employee_id'), '[]'::jsonb) from jsonb_array_elements(nw) x) then return jsonb_build_object('run_id', r.id, 'workers', jsonb_array_length(nw), 'noop', true); end if;
  update public.production_crew set state = 'void', void_by = auth.uid(), void_at = now(), void_note = left(coalesce(nullif(btrim(p_note), ''), 'replaced'), 300) where run_id = r.id and state = 'active';
  for w in select * from jsonb_array_elements(nw) loop
    insert into public.production_crew (run_id, employee_id, minutes, created_by, created_staff) values (r.id, (w ->> 'employee_id')::uuid, (w ->> 'minutes')::int, auth.uid(), public._c2_staff());
    n := n + 1;
  end loop;
  return jsonb_build_object('run_id', r.id, 'workers', n, 'minutes', (select coalesce(sum(minutes), 0) from public.production_crew where run_id = r.id and state = 'active'));
end $$;

create or replace function public.c2_production_crew_get(p_run uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r public.production_runs;
begin
  select * into r from public.production_runs where id = p_run;
  if not found or not public.is_active() or not (public._c2_can_crew(r.location_id) or public.rpt_access('staff') or public.rpt_access('stock')) or not public.can_loc(r.location_id) then raise exception 'not allowed'; end if;
  return jsonb_build_object('run_id', r.id, 'rows', coalesce((select jsonb_agg(jsonb_build_object('employee_id', c.employee_id, 'name', coalesce(e.full_name_en, e.full_name_bn), 'minutes', c.minutes) order by e.full_name_bn)
                                                          from public.production_crew c join public.employees e on e.id = c.employee_id where c.run_id = r.id and c.state = 'active'), '[]'::jsonb));
end $$;

create or replace function public.c2_crew_pick(p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._c2_can_crew(p_loc) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('employee_id', e.id, 'employee_no', e.employee_no, 'name_bn', e.full_name_bn, 'name_en', e.full_name_en) order by e.full_name_bn)
                     from public.employees e where e.status in ('active', 'on_leave') and e.primary_location_id = p_loc), '[]'::jsonb);
end $$;

create or replace function public.c2_output_per_labour_hour(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows jsonb; sm jsonb; runlist jsonb;
begin
  if not public.is_active() or not (public.is_owner() or public.has_grant('stock_production') or public.rpt_access('staff') or public.rpt_access('stock')) then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  with r as (select pr.id, pr.location_id, pr.item_id, (pr.made_at at time zone 'Asia/Dhaka')::date as day, pr.yield_base as output,
                    (select count(*) from public.production_crew c where c.run_id = pr.id and c.state = 'active') as workers, (select sum(c.minutes) from public.production_crew c where c.run_id = pr.id and c.state = 'active') as minutes
               from public.production_runs pr where pr.status = 'done' and (pr.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to and public.can_loc(pr.location_id) and (p_loc is null or pr.location_id = p_loc)),
       it as (select r.item_id, i.code, i.name_bn, i.name_en, count(*) as runs, count(*) filter (where r.workers > 0) as runs_with_crew, sum(r.output) as output, sum(r.output) filter (where r.workers > 0) as output_with_crew,
                     sum(r.minutes) as crew_minutes from r join public.items i on i.id = r.item_id group by r.item_id, i.code, i.name_bn, i.name_en)
  select (select coalesce(jsonb_agg(jsonb_build_object('item_id', item_id, 'code', code, 'name_bn', name_bn, 'name_en', name_en, 'runs', runs, 'runs_with_crew', runs_with_crew, 'output', output, 'output_with_crew', output_with_crew,
            'crew_hours', case when crew_minutes > 0 then round(crew_minutes / 60.0, 2) end, 'output_per_labour_hour', case when crew_minutes > 0 then round(output_with_crew / (crew_minutes / 60.0), 2) end,
            'coverage_pct', round(100.0 * runs_with_crew / runs, 1)) order by code), '[]'::jsonb) from it),
         (select jsonb_build_object('runs', coalesce(sum(runs), 0), 'runs_with_crew', coalesce(sum(runs_with_crew), 0), 'runs_without_crew', coalesce(sum(runs - runs_with_crew), 0),
            'coverage_pct', case when sum(runs) > 0 then round(100.0 * sum(runs_with_crew) / sum(runs), 1) end, 'crew_hours', case when sum(crew_minutes) > 0 then round(sum(crew_minutes) / 60.0, 2) end) from it),
         (select coalesce(jsonb_agg(jsonb_build_object('run_id', id, 'loc', location_id, 'day', day, 'item_id', item_id, 'output', output, 'workers', workers, 'crew_hours', case when minutes > 0 then round(minutes / 60.0, 2) end,
            'output_per_labour_hour', case when minutes > 0 then round(output / (minutes / 60.0), 2) end) order by day desc, id), '[]'::jsonb) from r)
    into rows, sm, runlist;
  return jsonb_build_object('from', p_from, 'to', p_to, 'notes', '["per_hour_only_runs_with_a_crew","units_are_the_run_output_units","runs_without_crew_counted_apart"]'::jsonb, 'summary', sm, 'rows', rows, 'runs', runlist);
end $$;

alter table public.production_crew enable row level security;
revoke all on public.production_crew from public, anon, authenticated;
grant select on public.production_crew to authenticated;
drop policy if exists production_crew_sel on public.production_crew;
create policy production_crew_sel on public.production_crew for select to authenticated
  using (exists (select 1 from public.production_runs r where r.id = run_id and public.can_loc(r.location_id) and (public._c2_can_crew(r.location_id) or public.rpt_access('staff') or public.rpt_access('stock'))));

do $c2$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^_?c2_' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname !~ '^_' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $c2$;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase458.sql
-- Phase 458 (RPT-C3, package R7 part 1) - SHARED HELPERS, CAMPAIGN MASTER LIST, CAMPAIGN / OFFER CODE ON A SALE OR ORDER, AUDITED EXPORT.
-- Paste AFTER the build through phase 99 (any other phase may come before or after). Paste-twice safe. No earlier phase file is edited; no shared function is replaced.
--
-- What this adds (everything is additive and OPTIONAL: a sale with no campaign behaves exactly as today):
--   * list 'marketing_campaigns' (the campaign master list). It is an ordinary option list, so Add new / Other / add rule (open | approval | owner) / retire / history
--     all come from the existing list framework (phase15). Details (start, end, budget, channel, note) live in option_lists.extra. NOTHING is seeded: the owner enters campaigns.
--   * mkt_sale_tags / mkt_order_tags: the campaign and the offer / coupon code typed at the till (or on an online order), one row per sale / order.
--     The code is a LABEL on the sale. It does not give a discount and is not a second coupon system: validated coupons are the CRM-F tables (crmf_coupons / crmf_coupon_uses)
--     when they are installed - this package only READS them (see phase460) and, when a typed code matches a CRM-F coupon, stores that coupon's id next to the code.
--   * mkt_campaign_save, mkt_active_campaigns, mkt_tag_sale, mkt_tag_sale_client, mkt_tag_order
--   * rptc3_export_log: the audited-export check for every RPT-C3 report page (needs the owner or the export_data grant AND the report's own group).
--   * _c3_* helpers used by phases 459-468.
-- Reports stay OPEN: every report function of this package asks rpt_access(<group>) = owner, report_<group> grant or view_reports (phase 9). Cost columns also need rpt_cost_ok().
-- Test data only (test_*).

do $g$ begin
  if to_regprocedure('public.option_add(text,text,text,text,jsonb,boolean,uuid)') is null or to_regprocedure('public._r2_num(jsonb)') is null
     or to_regprocedure('public._p26_d(text)') is null or to_regprocedure('public.rpt_access(text)') is null or to_regclass('public.online_orders') is null then
    raise exception 'phase458 needs the build through phase 99 (phases 15, 21, 26, 40, 61 and 9)';
  end if;
end $g$;

create or replace function public._p458_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- shared helpers ----------
create or replace function public._c3_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function public._c3_locs(p_loc int) returns int[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(l.id order by l.id), '{}'::int[]) from public.locations l where public.can_loc(l.id) and (p_loc is null or l.id = p_loc)
$$;
create or replace function public._c3_need(p_group text) returns void language plpgsql stable security definer set search_path = public as $$
begin if not public.is_active() or not public.rpt_access(p_group) then raise exception 'not allowed'; end if; end $$;
create or replace function public._c3_range(p_from date, p_to date) returns void language plpgsql immutable as $$
begin if p_from is null or p_to is null or p_from > p_to or p_to - p_from > 1100 then raise exception 'bad_range'; end if; end $$;
create or replace function public._c3_staff(p_user uuid) returns text language sql stable security definer set search_path = public as $$
  select coalesce(nullif(p.staff_id, ''), nullif(p.full_name, '')) from public.profiles p where p.id = p_user
$$;
create or replace function public._c3_norm(t text) returns text language sql immutable as $$ select lower(regexp_replace(btrim(coalesce(t, '')), '\s+', ' ', 'g')) $$;
-- a number inside option_lists.extra (text or number); anything else is "not captured" (null), never 0
create or replace function public._c3_xnum(x jsonb, k text) returns numeric language sql immutable as $$
  select case when x ->> k ~ '^[0-9]{1,12}(\.[0-9]{1,4})?$' then (x ->> k)::numeric end
$$;
create or replace function public._c3_xdate(x jsonb, k text) returns date language plpgsql immutable as $$
begin
  if x ->> k ~ '^\d{4}-\d{2}-\d{2}$' then return (x ->> k)::date; end if;
  return null;
exception when others then return null;
end $$;
-- the CRM-F coupon tables are READ when they exist (no second coupon system)
create or replace function public._c3_crmf_present() returns boolean language sql stable as $$
  select to_regclass('public.crmf_coupons') is not null and to_regclass('public.crmf_coupon_uses') is not null
$$;

-- ---------- the campaign master list (an ordinary option list; nothing is seeded) ----------
insert into public.list_defs (list_code, add_rule, allow_other, title_bn, title_en, note)
  values ('marketing_campaigns', 'owner', true, 'মার্কেটিং ক্যাম্পেইন', 'Marketing campaigns',
          'The campaign master list: 18-1 lines, sales and online orders point to a campaign here. Start / end / budget / channel are kept with each campaign.')
  on conflict (list_code) do nothing;

-- owner / list manager: add or edit a campaign with its details (names via the list framework, details validated here)
create or replace function public.mkt_campaign_save(p_value text, p_patch jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ex jsonb := '{}'; v text; st date; en date; bud numeric; res jsonb; vc text := p_value; o public.option_lists; bn text; enm text;
begin
  if not public._list_mgr('marketing_campaigns') then raise exception 'not allowed'; end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then raise exception 'bad_value'; end if;
  if p_patch ? 'start' then
    if nullif(btrim(p_patch ->> 'start'), '') is not null then
      if (p_patch ->> 'start') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'bad_date'; end if;
      begin st := (p_patch ->> 'start')::date; exception when others then raise exception 'bad_date'; end;
      ex := ex || jsonb_build_object('start', st);
    end if;
  end if;
  if p_patch ? 'end' then
    if nullif(btrim(p_patch ->> 'end'), '') is not null then
      if (p_patch ->> 'end') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'bad_date'; end if;
      begin en := (p_patch ->> 'end')::date; exception when others then raise exception 'bad_date'; end;
      ex := ex || jsonb_build_object('end', en);
    end if;
  end if;
  if p_patch ? 'budget' and nullif(btrim(p_patch ->> 'budget'), '') is not null then
    if (p_patch ->> 'budget') !~ '^[0-9]{1,12}(\.[0-9]{1,2})?$' then raise exception 'bad_amount'; end if;
    bud := (p_patch ->> 'budget')::numeric; ex := ex || jsonb_build_object('budget', bud);
  end if;
  if p_patch ? 'channel' and nullif(btrim(p_patch ->> 'channel'), '') is not null then ex := ex || jsonb_build_object('channel', left(btrim(p_patch ->> 'channel'), 40)); end if;
  if p_patch ? 'note' and nullif(btrim(p_patch ->> 'note'), '') is not null then ex := ex || jsonb_build_object('note', left(btrim(p_patch ->> 'note'), 300)); end if;
  bn := nullif(btrim(p_patch ->> 'name_bn'), ''); enm := nullif(btrim(p_patch ->> 'name_en'), '');
  if vc is null then
    if bn is null then raise exception 'name_required'; end if;
    res := public.option_add('marketing_campaigns', bn, enm, null, ex, coalesce((p_patch ->> 'force')::boolean, false));
    if (res ->> 'status') <> 'added' then return res; end if;
    vc := res ->> 'value_code';
  else
    select * into o from public.option_lists where list_code = 'marketing_campaigns' and value_code = vc;
    if not found then raise exception 'bad_option'; end if;
    -- end before start is refused whichever of the two was sent
    st := coalesce(st, public._c3_xdate(o.extra, 'start')); en := coalesce(en, public._c3_xdate(o.extra, 'end'));
    if st is not null and en is not null and en < st then raise exception 'end_before_start'; end if;
    update public.option_lists set label_bn = coalesce(bn, label_bn), label_en = coalesce(enm, label_en),
        extra = jsonb_strip_nulls(coalesce(extra, '{}'::jsonb) || ex)
      where list_code = 'marketing_campaigns' and value_code = vc;
    res := jsonb_build_object('status', 'saved', 'value_code', vc);
  end if;
  if vc is not null and (select (public._c3_xdate(extra, 'start') is not null and public._c3_xdate(extra, 'end') is not null
                                 and public._c3_xdate(extra, 'end') < public._c3_xdate(extra, 'start')) from public.option_lists where list_code = 'marketing_campaigns' and value_code = vc) then
    raise exception 'end_before_start';
  end if;
  return res || jsonb_build_object('value_code', vc);
end $$;

-- campaigns a till may pick today (active, inside its dates when dates are given)
create or replace function public.mkt_active_campaigns() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare td date := public._c3_today();
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('code', o.value_code, 'name_bn', o.label_bn, 'name_en', o.label_en,
            'start', public._c3_xdate(o.extra, 'start'), 'end', public._c3_xdate(o.extra, 'end')) order by o.sort, o.value_code)
      from public.option_lists o
     where o.list_code = 'marketing_campaigns' and o.active
       and (public._c3_xdate(o.extra, 'start') is null or public._c3_xdate(o.extra, 'start') <= td)
       and (public._c3_xdate(o.extra, 'end') is null or public._c3_xdate(o.extra, 'end') >= td)), '[]'::jsonb);
end $$;

-- ---------- tags: campaign and offer / coupon code on a sale or an online order ----------
create table if not exists public.mkt_sale_tags (
  sale_id uuid primary key references public.sales(id),
  campaign_code text check (campaign_code is null or length(campaign_code) between 1 and 40),
  offer_code text check (offer_code is null or offer_code ~ '^[A-Z0-9][A-Z0-9_-]{1,29}$'),
  coupon_id uuid,                                   -- only when the CRM-F coupon table exists and knows the typed code (no foreign key on purpose)
  location_id int,
  tagged_by uuid, tagged_staff text, tagged_at timestamptz not null default now(),
  check (campaign_code is not null or offer_code is not null)
);
create table if not exists public.mkt_order_tags (
  order_id uuid primary key references public.online_orders(id),
  campaign_code text check (campaign_code is null or length(campaign_code) between 1 and 40),
  offer_code text check (offer_code is null or offer_code ~ '^[A-Z0-9][A-Z0-9_-]{1,29}$'),
  coupon_id uuid,
  location_id int,
  tagged_by uuid, tagged_staff text, tagged_at timestamptz not null default now(),
  check (campaign_code is not null or offer_code is not null)
);
create index if not exists mkt_sale_tags_campaign on public.mkt_sale_tags (campaign_code);
create index if not exists mkt_sale_tags_offer on public.mkt_sale_tags (offer_code) where offer_code is not null;
create index if not exists mkt_order_tags_campaign on public.mkt_order_tags (campaign_code);
drop trigger if exists audit_mkt_sale_tags on public.mkt_sale_tags;
create trigger audit_mkt_sale_tags after insert or update on public.mkt_sale_tags for each row execute function public.log_change('sale_id');
drop trigger if exists mkt_sale_tags_no_delete on public.mkt_sale_tags;
create trigger mkt_sale_tags_no_delete before delete on public.mkt_sale_tags for each row execute function public.no_hard_delete();
drop trigger if exists audit_mkt_order_tags on public.mkt_order_tags;
create trigger audit_mkt_order_tags after insert or update on public.mkt_order_tags for each row execute function public.log_change('order_id');
drop trigger if exists mkt_order_tags_no_delete on public.mkt_order_tags;
create trigger mkt_order_tags_no_delete before delete on public.mkt_order_tags for each row execute function public.no_hard_delete();
alter table public.mkt_sale_tags enable row level security;
alter table public.mkt_order_tags enable row level security;
revoke all on public.mkt_sale_tags, public.mkt_order_tags from public, anon, authenticated;
grant select on public.mkt_sale_tags, public.mkt_order_tags to authenticated;
drop policy if exists mkt_sale_tags_read on public.mkt_sale_tags;
create policy mkt_sale_tags_read on public.mkt_sale_tags for select to authenticated
  using (public.is_active() and public.can_loc(location_id) and (public.can_do('POS', 'view') or public.rpt_access('marketing')));
drop policy if exists mkt_order_tags_read on public.mkt_order_tags;
create policy mkt_order_tags_read on public.mkt_order_tags for select to authenticated
  using (public.is_active() and public.can_loc(location_id) and (public.can_do('POS', 'view') or public.rpt_access('marketing')));

-- the CRM-F coupon id for a typed code (null when CRM-F is not installed or the code is unknown)
create or replace function public._c3_coupon_id(p_code text) returns uuid language plpgsql stable security definer set search_path = public as $$
declare r uuid;
begin
  if p_code is null or not public._c3_crmf_present() then return null; end if;
  execute 'select id from public.crmf_coupons where code = $1' into r using p_code;
  return r;
end $$;

create or replace function public._c3_tag_clean(p_campaign text, p_offer text, out camp text, out offer text) language plpgsql stable security definer set search_path = public as $$
begin
  camp := nullif(btrim(coalesce(p_campaign, '')), '');
  offer := nullif(upper(btrim(coalesce(p_offer, ''))), '');
  if camp is not null and not exists (select 1 from public.option_lists o where o.list_code = 'marketing_campaigns' and o.value_code = camp and o.active) then raise exception 'unknown_campaign'; end if;
  if offer is not null and offer !~ '^[A-Z0-9][A-Z0-9_-]{1,29}$' then raise exception 'bad_offer_code'; end if;
  if camp is null and offer is null then raise exception 'nothing_to_tag'; end if;
end $$;

-- tag a finished sale. The first tag: anyone who may enter POS sales at that location. Changing an existing tag: the owner or a POS approver. Every change is in audit_log.
create or replace function public.mkt_tag_sale(p_sale uuid, p_campaign text, p_offer text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.sales; c record; t public.mkt_sale_tags; cid uuid; sid text; st date; en date; outside boolean := false;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into s from public.sales where id = p_sale;
  if not found then raise exception 'sale_not_found'; end if;
  if not (public.can_do('POS', 'enter') and public.can_loc(s.location_id)) then raise exception 'not allowed'; end if;
  if s.status <> 'done' then raise exception 'sale_not_done'; end if;
  select * into c from public._c3_tag_clean(p_campaign, p_offer);
  cid := public._c3_coupon_id(c.offer);
  select * into t from public.mkt_sale_tags where sale_id = p_sale;
  if found then
    if t.campaign_code is not distinct from c.camp and t.offer_code is not distinct from c.offer then return jsonb_build_object('ok', true, 'unchanged', true); end if;
    if not (public.is_owner() or public.can_do('POS', 'approve')) then raise exception 'tag_change_needs_approver'; end if;
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.mkt_sale_tags (sale_id, campaign_code, offer_code, coupon_id, location_id, tagged_by, tagged_staff)
    values (p_sale, c.camp, c.offer, cid, s.location_id, auth.uid(), sid)
    on conflict (sale_id) do update set campaign_code = excluded.campaign_code, offer_code = excluded.offer_code, coupon_id = excluded.coupon_id,
      tagged_by = excluded.tagged_by, tagged_staff = excluded.tagged_staff, tagged_at = now();
  if c.camp is not null then
    select public._c3_xdate(o.extra, 'start'), public._c3_xdate(o.extra, 'end') into st, en from public.option_lists o where o.list_code = 'marketing_campaigns' and o.value_code = c.camp;
    outside := (st is not null and s.sale_date < st) or (en is not null and s.sale_date > en);
  end if;
  return jsonb_build_object('ok', true, 'campaign', c.camp, 'offer_code', c.offer, 'coupon_id', cid, 'crmf_installed', public._c3_crmf_present(),
    'coupon_known', cid is not null, 'outside_campaign_dates', outside);
end $$;

-- same, found by the till's own sale id (client id): used to tag a sale that was queued offline and has just been sent
create or replace function public.mkt_tag_sale_client(p_client uuid, p_campaign text, p_offer text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sid uuid;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select id into sid from public.sales where client_id = p_client and created_by = auth.uid();
  if sid is null then raise exception 'sale_not_found'; end if;
  return public.mkt_tag_sale(sid, p_campaign, p_offer);
end $$;

create or replace function public.mkt_tag_order(p_order uuid, p_campaign text, p_offer text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; c record; t public.mkt_order_tags; cid uuid; sid text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into o from public.online_orders where id = p_order;
  if not found then raise exception 'order_not_found'; end if;
  if not (public.can_do('POS', 'enter') and public.can_loc(o.location_id)) then raise exception 'not allowed'; end if;
  select * into c from public._c3_tag_clean(p_campaign, p_offer);
  cid := public._c3_coupon_id(c.offer);
  select * into t from public.mkt_order_tags where order_id = p_order;
  if found then
    if t.campaign_code is not distinct from c.camp and t.offer_code is not distinct from c.offer then return jsonb_build_object('ok', true, 'unchanged', true); end if;
    if not (public.is_owner() or public.can_do('POS', 'approve')) then raise exception 'tag_change_needs_approver'; end if;
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.mkt_order_tags (order_id, campaign_code, offer_code, coupon_id, location_id, tagged_by, tagged_staff)
    values (p_order, c.camp, c.offer, cid, o.location_id, auth.uid(), sid)
    on conflict (order_id) do update set campaign_code = excluded.campaign_code, offer_code = excluded.offer_code, coupon_id = excluded.coupon_id,
      tagged_by = excluded.tagged_by, tagged_staff = excluded.tagged_staff, tagged_at = now();
  return jsonb_build_object('ok', true, 'campaign', c.camp, 'offer_code', c.offer, 'coupon_id', cid, 'crmf_installed', public._c3_crmf_present(), 'coupon_known', cid is not null);
end $$;

-- ---------- the campaign each sale belongs to: its own tag first, else the tag of the online order it came from ----------
create or replace function public._c3_sale_campaign(d1 date, d2 date, locs int[]) returns table (sale_id uuid, campaign_code text, offer_code text, coupon_id uuid, via text)
language sql stable security definer set search_path = public as $$
  select s.id, coalesce(t.campaign_code, ot.campaign_code), coalesce(t.offer_code, ot.offer_code), coalesce(t.coupon_id, ot.coupon_id),
         case when t.sale_id is not null then 'sale' when ot.order_id is not null then 'order' end
    from public.sales s
    left join public.mkt_sale_tags t on t.sale_id = s.id
    left join public.online_orders oo on oo.sale_id = s.id
    left join public.mkt_order_tags ot on ot.order_id = oo.id
   where s.sale_date between d1 and d2 and s.location_id = any (locs) and (t.sale_id is not null or ot.order_id is not null)
$$;

-- ---------- audited export for every RPT-C3 report page ----------
create or replace function public._c3_export_group(p_key text) returns text language sql immutable as $$
  select case
    when p_key in ('mkt_spend', 'mkt_vs_sales', 'mkt_campaign_perf', 'mkt_discount', 'mkt_coupons', 'mkt_cac', 'mkt_repeat', 'mkt_roi', 'mkt_post') then 'marketing'
    when p_key in ('aud_voids', 'aud_approvals', 'aud_gaps', 'aud_stockadj', 'aud_overrides', 'aud_unusual', 'aud_users') then 'control'
    when p_key = 'aud_log' then '*owner'
    when p_key in ('fc_sales', 'fc_items', 'fc_festivals', 'fc_seasonal') then 'sales'
    when p_key in ('fc_production', 'fc_raw', 'fc_expiry') then 'stock'
    when p_key in ('fc_cash', 'fc_suppliers') then 'cash'
    when p_key = 'fc_scenario' then 'profit'
  end
$$;
create or replace function public.rptc3_export_log(p_key text, p_kind text, p_filters jsonb, p_rows int) returns void
language plpgsql security definer set search_path = public as $$
declare g text := public._c3_export_group(p_key); sid text; f jsonb := coalesce(p_filters, '{}'::jsonb);
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_grant('export_data')) then raise exception 'not allowed'; end if;
  if g is null then raise exception 'unknown_report'; end if;
  if g = '*owner' then
    if not public.is_owner() then raise exception 'not allowed'; end if;
  elsif not public.rpt_access(g) then raise exception 'not allowed'; end if;
  if p_kind is null or lower(p_kind) !~ '^[a-z0-9_]{1,20}$' then raise exception 'bad_kind'; end if;
  if length(f::text) > 4000 then f := jsonb_build_object('truncated', true); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'export', 'report', p_key, jsonb_build_object('kind', lower(p_kind), 'rows', least(greatest(coalesce(p_rows, 0), 0), 100000000), 'filters', f));
end $$;

-- ---------- privileges ----------
revoke all on function public._c3_today(), public._c3_locs(int), public._c3_need(text), public._c3_range(date, date), public._c3_staff(uuid), public._c3_norm(text),
  public._c3_xnum(jsonb, text), public._c3_xdate(jsonb, text), public._c3_crmf_present(), public._c3_coupon_id(text), public._c3_tag_clean(text, text),
  public._c3_sale_campaign(date, date, int[]), public._c3_export_group(text), public._p458_present() from public, anon, authenticated;
revoke all on function public.mkt_campaign_save(text, jsonb), public.mkt_active_campaigns(), public.mkt_tag_sale(uuid, text, text), public.mkt_tag_sale_client(uuid, text, text),
  public.mkt_tag_order(uuid, text, text), public.rptc3_export_log(text, text, jsonb, int) from public, anon;
grant execute on function public.mkt_campaign_save(text, jsonb), public.mkt_active_campaigns(), public.mkt_tag_sale(uuid, text, text), public.mkt_tag_sale_client(uuid, text, text),
  public.mkt_tag_order(uuid, text, text), public.rptc3_export_log(text, text, jsonb, int) to authenticated;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase459.sql
-- Phase 459 (RPT-C3, package R7 part 2) - MARKETING REPORTS #164 #165 #166 #167: spend by campaign, spend vs sales, campaign revenue and contribution, discount campaign performance.
-- Paste AFTER phase458. Paste-twice safe. Read-only functions (no table is written). No earlier phase file is edited.
--
-- Rules every figure here follows:
--   * a number that was not captured is NULL ("data not captured" on screen), never 0 and never an estimate;
--   * spend = the paid amount of 18-1 lines (submitted + approved sheets, like the hub report E4 / M2). "Value without payment" (samples) is shown apart and never added;
--   * a line belongs to a campaign when it names one from the master list (campaign_id), else when its free-text campaign equals exactly ONE campaign name; otherwise it is "unassigned";
--   * revenue / contribution are for sales that CARRY a campaign tag (phase458). Untagged sales are not guessed into a campaign, so the share of sales with a tag is always shown;
--   * contribution is on the COSTED part of the sales only (items with a cost price), with the costed share shown. Cost needs rpt_cost_ok(); without it the cost columns are NULL;
--   * access: rpt_access('marketing') (owner, report_marketing or view_reports) and the caller's locations (can_loc). Nothing here says one thing caused another.
-- Test data only (test_*).

do $g$ begin
  if to_regprocedure('public._p458_present()') is null then raise exception 'phase459 needs phase458 first'; end if;
end $g$;

-- ---------- the 18-1 lines with their campaign resolved ----------
create or replace function public._c3_mkt_lines(d1 date, d2 date, locs int[], p_status text[] default array['submitted', 'approved'])
returns table (entry_id uuid, serial int, status text, rev_no int, location_id int, line_no int, day date, head text, campaign_txt text, campaign_code text, via text,
               amt numeric, nonpay numeric, source text, receipt text, approved_by text)
language sql stable security definer set search_path = public as $$
  with camps as (select o.value_code, o.label_bn, o.label_en, o.label_mix from public.option_lists o where o.list_code = 'marketing_campaigns'),
  ln as (
    select e.id as eid, e.serial as ser, e.status as st, e.rev_no as rv, e.location_id as loc, x.ord::int as lno,
           coalesce(public._p26_d(x.l ->> 'date'), e.entry_date) as dy,
           case when x.l ->> 'head' like 'other:%' then 'other' else coalesce(nullif(btrim(x.l ->> 'head'), ''), '-') end as hd,
           nullif(btrim(x.l ->> 'campaign'), '') as ctxt, nullif(btrim(x.l ->> 'campaign_id'), '') as cid,
           public._r2_num(x.l -> 'amt') as am, public._r2_num(x.l -> 'nonpay') as np, nullif(btrim(x.l ->> 'source'), '') as src,
           nullif(btrim(x.l ->> 'receipt'), '') as rc, nullif(btrim(x.l ->> 'approved_by'), '') as ap
      from public.entries e
      cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) with ordinality as x(l, ord)
     where e.form_code = '18-1' and e.status = any (p_status) and e.location_id = any (locs))
  select ln.eid, ln.ser, ln.st, ln.rv, ln.loc, ln.lno, ln.dy, ln.hd, ln.ctxt, coalesce(c1.value_code, c2.value_code),
         case when c1.value_code is not null then 'list' when c2.value_code is not null then 'text' end,
         ln.am, ln.np, ln.src, ln.rc, ln.ap
    from ln
    left join camps c1 on c1.value_code = ln.cid
    left join lateral (select max(c.value_code) as value_code from camps c
                        where ln.ctxt is not null and (public._c3_norm(c.label_bn) = public._c3_norm(ln.ctxt) or public._c3_norm(c.label_en) = public._c3_norm(ln.ctxt)
                              or public._c3_norm(c.label_mix) = public._c3_norm(ln.ctxt)) having count(*) = 1) c2 on c1.value_code is null
   where ln.dy between d1 and d2 and (coalesce(ln.am, 0) > 0 or coalesce(ln.np, 0) > 0)
$$;

-- ---------- per-sale money with returns and the costed part (same method as the management P&L, phase27) ----------
create or replace function public._c3_sale_facts(d1 date, d2 date, locs int[])
returns table (sale_id uuid, sale_date date, location_id int, customer_id uuid, subtotal numeric, discount numeric, total numeric, ret numeric, net numeric, costed_net numeric, cogs numeric)
language sql stable security definer set search_path = public as $$
  with net_on as (select coalesce(public.rule_on('reports_net_of_returns'), true) as v),
  cst as (select ic.item_id, ic.cost_price from public.item_costs ic join public.items i on i.id = ic.item_id where i.count_in_business and ic.cost_price is not null),
  s as (select x.id, x.sale_date as sd, x.location_id as loc, x.customer_id as cu, x.subtotal as sub, x.discount as dis, x.total as tot, x.lines
          from public.sales x where x.status = 'done' and x.sale_date between d1 and d2 and x.location_id = any (locs)),
  ln as (
    select s.id as sid, (case when s.sub > 0 then s.tot / s.sub else 1 end) as f,
           case when e ->> 'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e ->> 'amount')::numeric end as amt,
           case when e ->> 'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e ->> 'qty')::numeric end as qty,
           case when e ->> 'item_id' ~ '^[0-9a-f-]{36}$' then (e ->> 'item_id')::uuid end as iid
      from s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e),
  ag as (select ln.sid, sum(ln.amt * ln.f) filter (where c.cost_price is not null) as cr, sum(ln.qty * c.cost_price) filter (where c.cost_price is not null) as cg
           from ln left join cst c on c.item_id = ln.iid group by 1),
  rr as (select r.sale_id as sid, r.amount, r.lines from public.sale_returns r join s on s.id = r.sale_id, net_on where net_on.v and r.status = 'done'),
  rt as (select sid, sum(amount) as ra from rr group by 1),
  rl as (
    select rr.sid, c.cost_price,
           case when e ->> 'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e ->> 'amount')::numeric end as amt,
           case when e ->> 'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e ->> 'qty')::numeric end as qty
      from rr cross join lateral jsonb_array_elements(case when jsonb_typeof(rr.lines) = 'array' then rr.lines else '[]'::jsonb end) e
      left join cst c on c.item_id = (case when e ->> 'item_id' ~ '^[0-9a-f-]{36}$' then (e ->> 'item_id')::uuid end)),
  rg as (select sid, sum(amt) filter (where cost_price is not null) as rcr, sum(qty * cost_price) filter (where cost_price is not null) as rcg from rl group by 1)
  select s.id, s.sd, s.loc, s.cu, s.sub, s.dis, s.tot, coalesce(t.ra, 0), s.tot - coalesce(t.ra, 0),
         case when a.cr is null then null else round(a.cr - coalesce(g.rcr, 0), 2) end, case when a.cg is null then null else round(a.cg - coalesce(g.rcg, 0), 2) end
    from s left join rt t on t.sid = s.id left join ag a on a.sid = s.id left join rg g on g.sid = s.id
$$;

-- ---------- #164 marketing spend by campaign and period ----------
create or replace function public.mkt_spend_by_campaign(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; rows_ jsonb; bym jsonb; tot jsonb; cov jsonb;
begin
  perform public._c3_need('marketing'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  if p_loc is not null and cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  with l as (select * from public._c3_mkt_lines(p_from, p_to, locs)),
  g as (select l.campaign_code,
               sum(l.amt) filter (where l.amt > 0) as spend, sum(l.amt) filter (where l.amt > 0 and l.status = 'approved') as spend_approved,
               count(*) filter (where l.amt > 0) as n_lines, sum(l.nonpay) filter (where l.nonpay > 0) as nonpay,
               min(l.day) as first_day, max(l.day) as last_day, count(*) filter (where l.amt > 0 and l.via = 'text') as n_text_match
          from l group by 1),
  hd as (select campaign_code, jsonb_object_agg(head, a) as heads from (select l.campaign_code, l.head, round(sum(l.amt), 2) as a from l where l.amt > 0 group by 1, 2) z group by 1)
  select coalesce(jsonb_agg(jsonb_build_object('campaign_code', g.campaign_code, 'name_bn', o.label_bn, 'name_en', o.label_en,
           'spend', round(g.spend, 2), 'spend_approved', round(g.spend_approved, 2), 'lines', g.n_lines, 'nonpay_value', round(g.nonpay, 2),
           'budget', public._c3_xnum(o.extra, 'budget'),
           'budget_used_pct', case when public._c3_xnum(o.extra, 'budget') > 0 and g.spend is not null then round(100 * g.spend / public._c3_xnum(o.extra, 'budget'), 1) end,
           'start', public._c3_xdate(o.extra, 'start'), 'end', public._c3_xdate(o.extra, 'end'), 'first_day', g.first_day, 'last_day', g.last_day,
           'matched_by_text', g.n_text_match, 'heads', hd.heads) order by (g.campaign_code is null), g.spend desc nulls last), '[]'::jsonb)
    into rows_
    from g left join public.option_lists o on o.list_code = 'marketing_campaigns' and o.value_code = g.campaign_code left join hd on hd.campaign_code is not distinct from g.campaign_code;
  select coalesce(jsonb_agg(jsonb_build_object('month', z.m, 'campaign_code', z.campaign_code, 'spend', z.a) order by z.m, z.campaign_code nulls last), '[]'::jsonb) into bym
    from (select date_trunc('month', l.day)::date as m, l.campaign_code, round(sum(l.amt), 2) as a from public._c3_mkt_lines(p_from, p_to, locs) l where l.amt > 0 group by 1, 2) z;
  select jsonb_build_object('spend', round(sum(l.amt) filter (where l.amt > 0), 2), 'lines', count(*) filter (where l.amt > 0), 'nonpay_value', round(sum(l.nonpay) filter (where l.nonpay > 0), 2)),
         jsonb_build_object('lines', count(*) filter (where l.amt > 0), 'with_campaign', count(*) filter (where l.amt > 0 and l.campaign_code is not null),
           'pct', case when count(*) filter (where l.amt > 0) > 0 then round(100.0 * count(*) filter (where l.amt > 0 and l.campaign_code is not null) / count(*) filter (where l.amt > 0), 1) end,
           'spend_with_campaign_pct', case when sum(l.amt) filter (where l.amt > 0) > 0 then round(100 * coalesce(sum(l.amt) filter (where l.amt > 0 and l.campaign_code is not null), 0) / sum(l.amt) filter (where l.amt > 0), 1) end)
    into tot, cov from public._c3_mkt_lines(p_from, p_to, locs) l;
  return jsonb_build_object('key', 'mkt_spend', 'from', p_from, 'to', p_to, 'loc', p_loc, 'rows', rows_, 'by_month', bym, 'totals', tot, 'coverage', cov,
    'notes', jsonb_build_array('spend_paid_only', 'nonpay_apart', 'sheets_submitted_and_approved', 'unassigned_is_not_guessed', 'not_in_books_unless_posted'),
    'basis', '18-1 lines, paid amount, sheets submitted or approved, dated by the line date');
end $$;

-- drill-down: the 18-1 lines behind a campaign row (p_campaign '' or '__none' = lines with no campaign)
create or replace function public.mkt_spend_lines(p_from date, p_to date, p_loc int default null, p_campaign text default null, p_limit int default 500) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[];
begin
  perform public._c3_need('marketing'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  return jsonb_build_object('key', 'mkt_spend_lines', 'rows', coalesce((select jsonb_agg(to_jsonb(z) order by z.day desc, z.serial desc, z.line_no) from (
      select l.entry_id, l.serial, l.status, l.location_id, l.line_no, l.day, l.head, l.campaign_txt, l.campaign_code, l.via, l.amt, l.nonpay, l.source, l.receipt, l.approved_by,
             (select o.label_en from public.option_lists o where o.list_code = 'marketing_heads' and o.value_code = l.head) as head_name,
             coalesce((select true from public.journal_entries je where je.source_type = 'mkt_spend' and je.source_id like l.entry_id::text || ':%:' || l.line_no and je.reverses_id is null
                         and not exists (select 1 from public.journal_entries r where r.reverses_id = je.id) limit 1), false) as in_books
        from public._c3_mkt_lines(p_from, p_to, locs) l
       where (p_campaign is null or (p_campaign in ('', '__none') and l.campaign_code is null) or l.campaign_code = p_campaign)
       order by l.day desc, l.serial desc, l.line_no limit least(greatest(coalesce(p_limit, 500), 1), 2000)) z), '[]'::jsonb));
end $$;

-- ---------- #165 marketing spend vs sales, same day (extends the hub report M2; no causal claim) ----------
create or replace function public.mkt_spend_vs_sales(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; rows_ jsonb; sp numeric; sl numeric; tg numeric;
begin
  perform public._c3_need('marketing'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  select coalesce(jsonb_agg(x order by x ->> 'day', x ->> 'location_bn'), '[]'::jsonb) into rows_ from public._r3q_m2_marketing_vs_sales(p_from, p_to, locs, '{}'::jsonb) x;
  select sum((x ->> 'spend')::numeric), sum((x ->> 'sales_total')::numeric) into sp, sl from jsonb_array_elements(rows_) x;
  select sum(f.net) into tg from public._c3_sale_facts(p_from, p_to, locs) f join public._c3_sale_campaign(p_from, p_to, locs) c on c.sale_id = f.sale_id where c.campaign_code is not null;
  return jsonb_build_object('key', 'mkt_vs_sales', 'from', p_from, 'to', p_to, 'loc', p_loc, 'rows', rows_,
    'totals', jsonb_build_object('spend', round(sp, 2), 'sales_total', round(sl, 2), 'campaign_tagged_net', round(tg, 2)),
    'notes', jsonb_build_array('no_causal_claim', 'same_day_only', 'sales_gross_of_returns', 'spend_paid_only'),
    'basis', 'Spend of 18-1 lines and bill totals on the same day and place, side by side. It shows what happened together, not what caused what.');
end $$;

-- ---------- #166 campaign revenue and contribution (tagged sales only) ----------
create or replace function public.mkt_campaign_performance(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; cost_ok boolean; rows_ jsonb; tot jsonb; cov jsonb; all_net numeric; tag_net numeric; tag_bills bigint; all_bills bigint;
begin
  perform public._c3_need('marketing'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  cost_ok := public.rpt_cost_ok();
  with f as (select * from public._c3_sale_facts(p_from, p_to, locs)),
  t as (select c.campaign_code, count(*) as bills, sum(f.net) as net, sum(f.discount) as disc, sum(f.costed_net) as cnet, sum(f.cogs) as cogs, count(distinct f.customer_id) as custs
          from f join public._c3_sale_campaign(p_from, p_to, locs) c on c.sale_id = f.sale_id where c.campaign_code is not null group by 1),
  sp as (select l.campaign_code, sum(l.amt) filter (where l.amt > 0) as spend, count(*) filter (where l.amt > 0) as n from public._c3_mkt_lines(p_from, p_to, locs) l where l.campaign_code is not null group by 1),
  k as (select campaign_code from t union select campaign_code from sp)
  select coalesce(jsonb_agg(jsonb_build_object('campaign_code', k.campaign_code, 'name_bn', o.label_bn, 'name_en', o.label_en,
        'tagged_bills', coalesce(t.bills, 0), 'no_tagged_sales', t.bills is null,
        'revenue_net', round(t.net, 2), 'discount_given', round(t.disc, 2), 'identified_customers', t.custs,
        'costed_net', case when cost_ok then round(t.cnet, 2) end, 'cogs', case when cost_ok then round(t.cogs, 2) end,
        'contribution_costed', case when cost_ok and t.cnet is not null then round(t.cnet - t.cogs, 2) end,
        'cost_coverage_pct', case when cost_ok and t.net > 0 then round(100 * coalesce(t.cnet, 0) / t.net, 1) end,
        'spend', round(sp.spend, 2), 'spend_lines', sp.n,
        'after_spend_costed', case when cost_ok and t.cnet is not null and sp.spend is not null then round(t.cnet - t.cogs - sp.spend, 2) end,
        'start', public._c3_xdate(o.extra, 'start'), 'end', public._c3_xdate(o.extra, 'end')) order by t.net desc nulls last, k.campaign_code), '[]'::jsonb)
    into rows_
    from k left join t on t.campaign_code = k.campaign_code left join sp on sp.campaign_code = k.campaign_code
         left join public.option_lists o on o.list_code = 'marketing_campaigns' and o.value_code = k.campaign_code;
  select sum(f.net), count(*) into all_net, all_bills from public._c3_sale_facts(p_from, p_to, locs) f;
  select sum(f.net), count(*) into tag_net, tag_bills from public._c3_sale_facts(p_from, p_to, locs) f join public._c3_sale_campaign(p_from, p_to, locs) c on c.sale_id = f.sale_id where c.campaign_code is not null;
  cov := jsonb_build_object('bills', all_bills, 'tagged_bills', tag_bills, 'tagged_pct', case when all_bills > 0 then round(100.0 * tag_bills / all_bills, 1) end,
                            'revenue_net', round(all_net, 2), 'tagged_revenue_net', round(tag_net, 2),
                            'tagged_revenue_pct', case when all_net > 0 then round(100 * coalesce(tag_net, 0) / all_net, 1) end);
  tot := jsonb_build_object('revenue_net', round(tag_net, 2), 'cost_hidden', not cost_ok);
  return jsonb_build_object('key', 'mkt_campaign_perf', 'from', p_from, 'to', p_to, 'loc', p_loc, 'rows', rows_, 'totals', tot, 'coverage', cov,
    'notes', jsonb_build_array('tagged_sales_only', 'contribution_on_costed_part', 'no_causal_claim', 'spend_in_same_period') || case when cost_ok then '[]'::jsonb else jsonb_build_array('cost_hidden') end,
    'basis', 'Net sales (after returns) of bills that carry the campaign. Contribution = sales of items with a cost price minus their cost. Spend = 18-1 lines of the campaign in the same dates.');
end $$;

-- drill-down: the sales behind a campaign row
create or replace function public.mkt_campaign_sales(p_from date, p_to date, p_loc int default null, p_campaign text default null, p_limit int default 500) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; cost_ok boolean;
begin
  perform public._c3_need('marketing'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc); cost_ok := public.rpt_cost_ok();
  return jsonb_build_object('key', 'mkt_campaign_sales', 'rows', coalesce((select jsonb_agg(to_jsonb(z) order by z.sale_date desc, z.receipt desc) from (
      select f.sale_id, f.sale_date, s.receipt, f.location_id, c.campaign_code, c.offer_code, c.via, f.discount, f.total, f.ret, f.net,
             case when cost_ok then f.costed_net end as costed_net, case when cost_ok then f.cogs end as cogs, cu.name as customer
        from public._c3_sale_facts(p_from, p_to, locs) f
        join public._c3_sale_campaign(p_from, p_to, locs) c on c.sale_id = f.sale_id
        join public.sales s on s.id = f.sale_id left join public.customers cu on cu.id = f.customer_id
       where p_campaign is null or c.campaign_code = p_campaign
       order by f.sale_date desc, s.receipt desc limit least(greatest(coalesce(p_limit, 500), 1), 2000)) z), '[]'::jsonb));
end $$;

-- ---------- #167 discount campaign performance ----------
create or replace function public.mkt_discount_campaigns(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; rows_ jsonb; base jsonb;
begin
  perform public._c3_need('marketing'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  with f as (select * from public._c3_sale_facts(p_from, p_to, locs)),
  c as (select * from public._c3_sale_campaign(p_from, p_to, locs)),
  j as (select f.*, c.campaign_code, c.offer_code from f left join c on c.sale_id = f.sale_id),
  g as (select coalesce(j.campaign_code, '') as camp, count(*) filter (where j.discount > 0) as disc_bills, sum(j.discount) filter (where j.discount > 0) as disc,
               sum(j.subtotal) filter (where j.discount > 0) as gross, sum(j.net) filter (where j.discount > 0) as net,
               count(*) filter (where j.offer_code is not null and j.discount = 0) as code_without_discount
          from j group by 1 having count(*) filter (where j.discount > 0) > 0 or count(*) filter (where j.offer_code is not null) > 0)
  select coalesce(jsonb_agg(jsonb_build_object('campaign_code', nullif(g.camp, ''), 'name_bn', o.label_bn, 'name_en', o.label_en, 'discount_bills', g.disc_bills,
        'discount_total', round(g.disc, 2), 'gross_of_those_bills', round(g.gross, 2), 'net_of_those_bills', round(g.net, 2),
        'discount_pct_of_gross', case when g.gross > 0 then round(100 * g.disc / g.gross, 1) end,
        'avg_bill_net', case when g.disc_bills > 0 then round(g.net / g.disc_bills, 2) end, 'offer_code_without_discount', g.code_without_discount)
        order by (g.camp = ''), g.disc desc nulls last), '[]'::jsonb)
    into rows_ from g left join public.option_lists o on o.list_code = 'marketing_campaigns' and o.value_code = g.camp;
  select jsonb_build_object('bills', count(*) filter (where discount = 0), 'avg_bill_net', case when count(*) filter (where discount = 0) > 0 then round(sum(net) filter (where discount = 0) / count(*) filter (where discount = 0), 2) end)
    into base from public._c3_sale_facts(p_from, p_to, locs);
  return jsonb_build_object('key', 'mkt_discount', 'from', p_from, 'to', p_to, 'loc', p_loc, 'rows', rows_, 'baseline_no_discount', base,
    'notes', jsonb_build_array('no_causal_claim', 'compare_with_baseline_is_not_proof', 'untagged_discounts_in_blank_row'),
    'basis', 'Bills with a discount grouped by the campaign they carry (blank = no campaign). Baseline = bills in the same dates with no discount. Staff / approver detail: the Discounts report.');
end $$;

revoke all on function public._c3_mkt_lines(date, date, int[], text[]), public._c3_sale_facts(date, date, int[]) from public, anon, authenticated;
revoke all on function public.mkt_spend_by_campaign(date, date, int), public.mkt_spend_lines(date, date, int, text, int), public.mkt_spend_vs_sales(date, date, int),
  public.mkt_campaign_performance(date, date, int), public.mkt_campaign_sales(date, date, int, text, int), public.mkt_discount_campaigns(date, date, int) from public, anon;
grant execute on function public.mkt_spend_by_campaign(date, date, int), public.mkt_spend_lines(date, date, int, text, int), public.mkt_spend_vs_sales(date, date, int),
  public.mkt_campaign_performance(date, date, int), public.mkt_campaign_sales(date, date, int, text, int), public.mkt_discount_campaigns(date, date, int) to authenticated;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase460.sql
-- Phase 460 (RPT-C3, package R7 part 3) - MARKETING REPORTS #168 #169 #170 #171: coupon / offer usage, customer acquisition cost, repeat purchase after a promotion, marketing ROI.
-- Paste AFTER phase459. Paste-twice safe. Read-only functions. No earlier phase file is edited.
--
--   #168 coupon usage    validated coupons come from the CRM-F tables (crmf_coupons / crmf_coupon_uses) WHEN THEY EXIST - this file creates NO coupon table. Codes typed at the till
--                        without CRM-F (phase458 tags) are shown in a second block labelled "typed, not validated". A sale in both is counted once (as validated).
--   #169 CAC             spend / new customers, ALWAYS with the share of new customers whose source is filled. By-source spend only where the source equals a campaign.
--   #170 repeat          customers who bought on a promotion and bought again within N days after it. N is typed by the person or comes from the setting mkt_repeat_days
--                        (blank = "data needed"; no default is invented). A window that is not over yet is marked incomplete.
--   #171 ROI             ONLY attributable data: tagged sales and campaign-assigned spend. Unassigned spend is shown apart and is NOT in any ROI. Contribution is on the costed part,
--                        with the costed share shown. No ratio is shown when its inputs are missing. Nothing here says a campaign caused a sale.
-- Test data only (test_*).

do $g$ begin
  if to_regprocedure('public.mkt_campaign_performance(date,date,integer)') is null then raise exception 'phase460 needs phase459 first'; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'reports', v.kind, v.dv, v.unit, v.ch, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('mkt_repeat_days', 'number', null::jsonb, 'days', null::jsonb, 1::numeric, 365::numeric,
   'Repeat purchase window after a promotion (days)',
   'The marketing report "repeat purchase after a promotion" counts a customer as a repeat buyer if he buys again within this many days after the promotion ended. Blank = the report asks the person to type the days; nothing is assumed.', 910)
  ) as v(key, kind, dv, unit, ch, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

-- ---------- #168 coupon / offer usage ----------
create or replace function public.mkt_coupon_usage(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; crmf boolean := public._c3_crmf_present(); val jsonb := '[]'; typed jsonb; tot jsonb;
begin
  perform public._c3_need('marketing'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  if crmf then
    execute $q$
      select coalesce(jsonb_agg(jsonb_build_object('code', z.code, 'name', z.name, 'kind', z.kind, 'value', z.value, 'campaign_ref', z.campaign_ref, 'uses', z.uses,
               'customers', z.customers, 'discount_given', z.disc, 'bill_total', z.bt, 'mismatches', z.mism, 'first_use', z.f, 'last_use', z.l) order by z.uses desc, z.code), '[]'::jsonb)
        from (select c.code, c.name, c.kind, c.value, c.campaign_ref, count(*) as uses, count(distinct u.customer_id) as customers, round(sum(u.discount_given), 2) as disc,
                     round(sum(u.bill_total), 2) as bt, count(*) filter (where u.mismatch) as mism, min(s.sale_date) as f, max(s.sale_date) as l
                from public.crmf_coupon_uses u join public.crmf_coupons c on c.id = u.coupon_id join public.sales s on s.id = u.sale_id
               where s.status = 'done' and s.sale_date between $1 and $2 and s.location_id = any ($3) group by 1, 2, 3, 4, 5) z $q$
      into val using p_from, p_to, locs;
    execute $q$
      select coalesce(jsonb_agg(jsonb_build_object('offer_code', z.offer_code, 'bills', z.bills, 'discount_given', z.disc, 'net', z.net, 'campaign_code', z.camp) order by z.bills desc, z.offer_code), '[]'::jsonb)
        from (select t.offer_code, count(*) as bills, round(sum(s.discount), 2) as disc, round(sum(s.total), 2) as net, max(t.campaign_code) as camp
                from public.mkt_sale_tags t join public.sales s on s.id = t.sale_id
               where t.offer_code is not null and s.status = 'done' and s.sale_date between $1 and $2 and s.location_id = any ($3)
                 and not exists (select 1 from public.crmf_coupon_uses u where u.sale_id = t.sale_id) group by 1) z $q$
      into typed using p_from, p_to, locs;
  else
    select coalesce(jsonb_agg(jsonb_build_object('offer_code', z.offer_code, 'bills', z.bills, 'discount_given', z.disc, 'net', z.net, 'campaign_code', z.camp) order by z.bills desc, z.offer_code), '[]'::jsonb)
      into typed
      from (select t.offer_code, count(*) as bills, round(sum(s.discount), 2) as disc, round(sum(s.total), 2) as net, max(t.campaign_code) as camp
              from public.mkt_sale_tags t join public.sales s on s.id = t.sale_id
             where t.offer_code is not null and s.status = 'done' and s.sale_date between p_from and p_to and s.location_id = any (locs) group by 1) z;
  end if;
  tot := jsonb_build_object('validated_uses', coalesce((select sum((x ->> 'uses')::int) from jsonb_array_elements(val) x), 0),
                            'typed_bills', coalesce((select sum((x ->> 'bills')::int) from jsonb_array_elements(typed) x), 0));
  return jsonb_build_object('key', 'mkt_coupons', 'from', p_from, 'to', p_to, 'loc', p_loc, 'crmf_installed', crmf, 'validated', val, 'typed', typed, 'totals', tot,
    'notes', case when crmf then jsonb_build_array('validated_from_crmf', 'typed_codes_not_validated', 'tier_offers_in_customer_tier_report')
                  else jsonb_build_array('crmf_not_installed', 'typed_codes_not_validated', 'tier_offers_in_customer_tier_report') end,
    'basis', case when crmf then 'Validated = coupon uses recorded by the coupon module (CRM-F). Typed = a code written on the bill that matches no recorded coupon use.'
                  else 'The coupon module (CRM-F) is not installed, so no coupon is validated. The codes below were typed on the bill and are not checked against any list.' end);
end $$;

-- ---------- #169 customer acquisition cost ----------
create or replace function public.mkt_cac(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; spend numeric; n_new bigint; n_src bigint; by_src jsonb; attrib_spend numeric; attrib_new bigint; first_loc boolean := p_loc is not null;
begin
  perform public._c3_need('marketing'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  select sum(l.amt) filter (where l.amt > 0) into spend from public._c3_mkt_lines(p_from, p_to, locs) l;
  with fs as (select s.customer_id, (array_agg(s.location_id order by s.sale_date, s.sold_at))[1] as loc1 from public.sales s where s.status = 'done' and s.customer_id is not null group by 1),
  nc as (select c.id, nullif(btrim(c.source), '') as src from public.customers c left join fs on fs.customer_id = c.id
          where coalesce(c.customer_since, (c.created_at at time zone 'Asia/Dhaka')::date) between p_from and p_to
            and (not first_loc or fs.loc1 = any (locs)))
  select count(*), count(*) filter (where src is not null) into n_new, n_src from nc;
  with fs as (select s.customer_id, (array_agg(s.location_id order by s.sale_date, s.sold_at))[1] as loc1 from public.sales s where s.status = 'done' and s.customer_id is not null group by 1),
  nc as (select c.id, nullif(btrim(c.source), '') as src from public.customers c left join fs on fs.customer_id = c.id
          where coalesce(c.customer_since, (c.created_at at time zone 'Asia/Dhaka')::date) between p_from and p_to
            and (not first_loc or fs.loc1 = any (locs))),
  sp as (select l.campaign_code, sum(l.amt) filter (where l.amt > 0) as spend from public._c3_mkt_lines(p_from, p_to, locs) l where l.campaign_code is not null group by 1),
  cm as (select o.value_code, public._c3_norm(o.label_bn) as nb, public._c3_norm(o.label_en) as ne, public._c3_norm(o.value_code) as nc from public.option_lists o where o.list_code = 'marketing_campaigns'),
  g as (select coalesce(nc.src, '') as src, count(*) as n from nc group by 1),
  j as (select g.src, g.n, (select max(cm.value_code) from cm where g.src <> '' and public._c3_norm(g.src) in (cm.nb, cm.ne, cm.nc)) as camp from g)
  select coalesce(jsonb_agg(jsonb_build_object('source', nullif(j.src, ''), 'new_customers', j.n, 'campaign_code', j.camp, 'campaign_spend', round(sp.spend, 2),
           'cac', case when sp.spend > 0 and j.n > 0 then round(sp.spend / j.n, 2) end) order by (j.src = ''), j.n desc), '[]'::jsonb),
         sum(sp.spend), sum(j.n) filter (where sp.spend is not null)
    into by_src, attrib_spend, attrib_new
    from j left join sp on sp.campaign_code = j.camp;
  return jsonb_build_object('key', 'mkt_cac', 'from', p_from, 'to', p_to, 'loc', p_loc, 'rows', by_src,
    'totals', jsonb_build_object('marketing_spend', round(spend, 2), 'new_customers', n_new, 'new_with_source', n_src,
       'cac_all', case when spend > 0 and n_new > 0 then round(spend / n_new, 2) end,
       'attributable_spend', round(attrib_spend, 2), 'attributable_new_customers', attrib_new,
       'cac_attributable', case when attrib_spend > 0 and attrib_new > 0 then round(attrib_spend / attrib_new, 2) end),
    'coverage', jsonb_build_object('new_customers', n_new, 'with_source', n_src, 'source_pct', case when n_new > 0 then round(100.0 * n_src / n_new, 1) end),
    'notes', jsonb_build_array('source_coverage_shown', 'cac_all_is_a_blend', 'new_customer_is_date_of_first_record', 'no_causal_claim') ||
             case when first_loc then jsonb_build_array('place_filter_uses_first_sale_place') else '[]'::jsonb end,
    'basis', 'Spend = paid 18-1 lines. New customer = a customer record dated in the period (customer since, else created). CAC (all) = all marketing spend / all new customers. CAC (attributable) = spend of campaigns whose name is a customer source / new customers with those sources.');
end $$;

-- ---------- #170 repeat purchase after a promotion ----------
create or replace function public.mkt_repeat_after_promo(p_campaign text default null, p_days int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d int := coalesce(p_days, public.rule_num('mkt_repeat_days')::int); locs int[]; rows_ jsonb; td date := public._c3_today();
begin
  perform public._c3_need('marketing'); locs := public._c3_locs(null);
  if d is null then return jsonb_build_object('key', 'mkt_repeat', 'data_needed', jsonb_build_array('mkt_repeat_days'), 'rows', '[]'::jsonb,
      'notes', jsonb_build_array('window_days_not_set'), 'basis', 'Type the number of days, or the owner sets "Repeat purchase window after a promotion". No value is assumed.'); end if;
  if d < 1 or d > 365 then raise exception 'bad_days'; end if;
  with camp as (select o.value_code as code, o.label_bn, o.label_en, public._c3_xdate(o.extra, 'start') as st, public._c3_xdate(o.extra, 'end') as en
                  from public.option_lists o where o.list_code = 'marketing_campaigns' and (p_campaign is null or o.value_code = p_campaign)),
  tg as (select c.code, s.id as sale_id, s.customer_id, s.sale_date from camp c
           join public.mkt_sale_tags t on t.campaign_code = c.code join public.sales s on s.id = t.sale_id and s.status = 'done' and s.location_id = any (locs)
         union select c.code, s.id, s.customer_id, s.sale_date from camp c
           join public.mkt_order_tags ot on ot.campaign_code = c.code join public.online_orders oo on oo.id = ot.order_id join public.sales s on s.id = oo.sale_id and s.status = 'done' and s.location_id = any (locs)),
  win as (select c.code, c.label_bn, c.label_en, coalesce(c.en, max(tg.sale_date)) as promo_end, c.st, count(tg.sale_id) as bills,
                 count(tg.sale_id) filter (where tg.customer_id is not null) as bills_known, count(distinct tg.customer_id) as custs
            from camp c left join tg on tg.code = c.code group by c.code, c.label_bn, c.label_en, c.en, c.st having count(tg.sale_id) > 0),
  rep as (select w.code, count(distinct s2.customer_id) as repeaters, min(s2.sale_date - w.promo_end) as first_gap
            from win w join tg on tg.code = w.code and tg.customer_id is not null
            join public.sales s2 on s2.customer_id = tg.customer_id and s2.status = 'done' and s2.location_id = any (locs)
                 and s2.sale_date > w.promo_end and s2.sale_date <= w.promo_end + d
                 and not exists (select 1 from tg x where x.sale_id = s2.id and x.code = w.code)
           group by w.code)
  select coalesce(jsonb_agg(jsonb_build_object('campaign_code', w.code, 'name_bn', w.label_bn, 'name_en', w.label_en, 'promo_end', w.promo_end, 'window_from', w.promo_end + 1, 'window_to', w.promo_end + d,
        'window_complete', w.promo_end + d <= td - 1, 'tagged_bills', w.bills, 'tagged_bills_with_customer', w.bills_known,
        'identified_pct', round(100.0 * w.bills_known / w.bills, 1), 'promo_customers', w.custs, 'repeat_customers', coalesce(r.repeaters, 0),
        'repeat_pct', case when w.custs > 0 and w.promo_end + d <= td - 1 then round(100.0 * coalesce(r.repeaters, 0) / w.custs, 1) end,
        'repeat_pct_so_far', case when w.custs > 0 then round(100.0 * coalesce(r.repeaters, 0) / w.custs, 1) end,
        'end_is_last_tagged_sale', (select c.en is null from camp c where c.code = w.code)) order by w.promo_end desc), '[]'::jsonb)
    into rows_ from win w left join rep r on r.code = w.code;
  return jsonb_build_object('key', 'mkt_repeat', 'window_days', d, 'rows', rows_,
    'notes', jsonb_build_array('only_identified_customers', 'incomplete_window_marked', 'no_causal_claim', 'repeat_means_a_later_bill_not_tagged_to_the_same_campaign'),
    'basis', 'Customers (with a name or mobile on the bill) who bought on a bill tagged to the campaign, and who bought again within ' || d || ' days after the campaign ended (a campaign with no end date uses its last tagged sale).');
end $$;

-- ---------- #171 marketing ROI (attributable data only) ----------
create or replace function public.mkt_roi(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare perf jsonb; locs int[]; unassigned numeric; rows_ jsonb; cost_ok boolean := public.rpt_cost_ok();
begin
  perform public._c3_need('marketing'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  perf := public.mkt_campaign_performance(p_from, p_to, p_loc);
  select sum(l.amt) filter (where l.amt > 0) into unassigned from public._c3_mkt_lines(p_from, p_to, locs) l where l.campaign_code is null;
  select coalesce(jsonb_agg(r || jsonb_build_object(
        'revenue_per_taka', case when (r ->> 'spend')::numeric > 0 and r ->> 'revenue_net' is not null then round((r ->> 'revenue_net')::numeric / (r ->> 'spend')::numeric, 2) end,
        'roi_pct_costed_part', case when cost_ok and (r ->> 'spend')::numeric > 0 and r ->> 'contribution_costed' is not null
              then round(100 * ((r ->> 'contribution_costed')::numeric - (r ->> 'spend')::numeric) / (r ->> 'spend')::numeric, 1) end,
        'why_no_roi', case when r ->> 'spend' is null then 'no_spend_recorded' when (r ->> 'spend')::numeric <= 0 then 'no_spend_recorded'
                           when r ->> 'revenue_net' is null then 'no_tagged_sales' when not cost_ok then 'cost_hidden' when r ->> 'contribution_costed' is null then 'no_costed_sales' end)
        order by (r ->> 'revenue_net')::numeric desc nulls last), '[]'::jsonb)
    into rows_ from jsonb_array_elements(perf -> 'rows') r;
  return jsonb_build_object('key', 'mkt_roi', 'from', p_from, 'to', p_to, 'loc', p_loc, 'rows', rows_, 'coverage', perf -> 'coverage',
    'unassigned_spend_not_in_roi', round(unassigned, 2),
    'notes', jsonb_build_array('attributable_data_only', 'contribution_on_costed_part', 'unassigned_spend_not_in_roi', 'untagged_sales_not_counted_roi_may_be_understated', 'no_causal_claim') ||
             case when cost_ok then '[]'::jsonb else jsonb_build_array('cost_hidden') end,
    'basis', 'ROI % = (contribution on the costed part - campaign spend) / campaign spend. Revenue per taka = tagged net sales / campaign spend. Only bills that carry the campaign and 18-1 lines assigned to the campaign are used.');
end $$;

revoke all on function public.mkt_coupon_usage(date, date, int), public.mkt_cac(date, date, int), public.mkt_repeat_after_promo(text, int), public.mkt_roi(date, date, int) from public, anon;
grant execute on function public.mkt_coupon_usage(date, date, int), public.mkt_cac(date, date, int), public.mkt_repeat_after_promo(text, int), public.mkt_roi(date, date, int) to authenticated;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase461.sql
-- Phase 461 (RPT-C3, package R7 part 4) - POST THE MARKETING SPEND OF FORM 18-1 TO THE JOURNAL (setting marketing_post_on, OFF) WITHOUT DOUBLE COUNTING FORM 10-2.
-- Paste AFTER phase460 (needs phase 40 accounting and phase 458). Paste-twice safe. No earlier phase file is edited; acct_post_pending and every shared function stay as they are.
--
-- Why: form 18-1 spend never reaches the journal or the profit figures (audit finding F8). If the same spend is ALSO typed in form 10-2 (expense head "marketing") or as a quick expense,
-- posting both would count it twice. Posting is therefore an owner decision, OFF by default, and every line is classified before anything is written:
--   posted               already in the journal (key = sheet : revision : line number)
--   to_post              an APPROVED 18-1 line, paid from bank / mobile / card, dated on or after the start dates, no 10-2 look-alike, period open
--   skip_imprest         paid from the imprest box: the imprest money is recorded by its 10-2 voucher, so posting it here would count it twice. NEVER posted by this file.
--   needs_source         the line has no "source of money": the credit side is unknown, so nothing is posted
--   owner_money          paid from the owner's own money: which account is credited is an accounting choice nobody made yet, so nothing is posted
--   possible_duplicate   an approved / submitted 10-2 voucher line (head marketing) or a quick expense of the SAME amount, SAME place and SAME date exists. It waits for a person's
--                        decision (mkt_post_decide: post | skip, reason required, kept for ever). Never posted by itself.
--   decided_skip         a person chose to skip it
--   before_start / not_set_up   dated before the start dates / the start dates are not set yet
--   period_locked        the period is closed
-- Entry written (two lines, Dr = Cr): Dr 'exp_marketing' mapping / Cr 'pay_bank' | 'pay_mobile' (card follows the supplier-payment rule: bank). Source type 'mkt_spend', dated the line date.
-- Settings (module books): marketing_post_on (switch, OFF), marketing_post_from (date, blank = cannot switch on). The switch can go ON only with a valid date, accounting ON with a start date
-- and the three mappings present. A re-opened sheet (new revision) has its old entry reversed and the new one posted on the next run; nothing is deleted.
-- NOTE for the owner and the accountant: the management profit view (L1 / T4) reads 10-2 vouchers, not 18-1; the journal profit includes these entries once posted.
-- Test data only (test_*).

do $g$ begin
  if to_regprocedure('public.mkt_spend_by_campaign(date,date,integer)') is null or to_regprocedure('public._acct_write(date,integer,text,text,text,text,text,jsonb,bigint,uuid,text)') is null
     or to_regprocedure('public._append_only43()') is null then
    raise exception 'phase461 needs phases 459, 40 and 43 first';
  end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'books', v.kind, v.dv, v.unit, v.ch, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('marketing_post_on', 'switch', 'false'::jsonb, null::text, null::jsonb, null::numeric, null::numeric,
   'Post the marketing spend of form 18-1 to the books',
   'OFF = form 18-1 spend stays out of the journal (today). ON = approved 18-1 lines paid from bank / mobile / card are posted (Dr marketing expense, Cr bank / mobile), except lines that look like the same spend already typed in form 10-2 or as a quick expense: those wait for a decision. Imprest-paid lines are never posted here. Needs the date below, accounting ON with a start date, and the marketing / bank / mobile account mappings.', 960),
 ('marketing_post_from', 'text', null::jsonb, 'YYYY-MM-DD', null::jsonb, null::numeric, null::numeric,
   'Marketing spend is posted to the books from this date',
   'Only 18-1 lines dated on or after this date are posted. Blank = the switch above cannot be turned on. Lines before this date are never posted.', 961)
  ) as v(key, kind, dv, unit, ch, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

create or replace function public._c3_rules_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare v text; f text; d date;
begin
  if new.key = 'marketing_post_from' then
    v := nullif(new.value #>> '{}', '');
    if v is not null then
      if v !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'bad_date'; end if;
      begin d := v::date; exception when others then raise exception 'bad_date'; end;
    end if;
  elsif new.key = 'marketing_post_on' and coalesce((new.value #>> '{}')::boolean, false) then
    select nullif(coalesce(r.value, r.default_value) #>> '{}', '') into f from public.rules r where r.key = 'marketing_post_from';
    if f is null or public._acct_start() is null or not public.rule_on('accounting_on') then raise exception 'marketing_post_needs_setup'; end if;
    if (select count(*) from public.acct_mappings where key in ('exp_marketing', 'pay_bank', 'pay_mobile')) < 3 then raise exception 'marketing_post_needs_mappings'; end if;
  end if;
  return new;
end $$;
drop trigger if exists c3_rules_guard on public.rules;
create trigger c3_rules_guard before insert or update on public.rules for each row
  when (new.key in ('marketing_post_on', 'marketing_post_from')) execute function public._c3_rules_guard();

-- ---------- decisions on look-alike lines (append-only) ----------
create table if not exists public.mkt_post_decisions (
  id bigint generated by default as identity primary key,
  entry_id uuid not null references public.entries(id),
  rev_no int not null,
  line_no int not null,
  decision text not null check (decision in ('post', 'skip')),
  reason text not null check (length(btrim(reason)) >= 3 and length(reason) <= 300),
  decided_by uuid, decided_staff text, decided_at timestamptz not null default now()
);
create index if not exists mkt_post_decisions_key on public.mkt_post_decisions (entry_id, rev_no, line_no, id desc);
drop trigger if exists mkt_post_decisions_ro on public.mkt_post_decisions;
create trigger mkt_post_decisions_ro before update or delete on public.mkt_post_decisions for each row execute function public._append_only43();
drop trigger if exists mkt_post_decisions_ro_t on public.mkt_post_decisions;
create trigger mkt_post_decisions_ro_t before truncate on public.mkt_post_decisions for each statement execute function public._append_only43();
alter table public.mkt_post_decisions enable row level security;
revoke all on public.mkt_post_decisions from public, anon, authenticated;
grant select on public.mkt_post_decisions to authenticated;
drop policy if exists mkt_post_decisions_read on public.mkt_post_decisions;
create policy mkt_post_decisions_read on public.mkt_post_decisions for select to authenticated using (public._acct_view() or public._acct_manage());

-- ---------- classification of every approved 18-1 line ----------
create or replace function public._c3_post_lines(d1 date, d2 date, locs int[])
returns table (entry_id uuid, serial int, rev_no int, location_id int, line_no int, day date, head text, campaign_code text, amt numeric, source text, receipt text,
               skey text, cls text, why text, decision text)
language sql stable security definer set search_path = public as $$
  with st as (select public._acct_start() as a, nullif(public.rule_txt('marketing_post_from'), '') as f),
  l as (select * from public._c3_mkt_lines(d1, d2, locs, array['approved']) m where m.amt > 0),
  j as (
    select l.*, l.entry_id::text || ':' || l.rev_no || ':' || l.line_no as k,
           (select dd.decision from public.mkt_post_decisions dd where dd.entry_id = l.entry_id and dd.rev_no = l.rev_no and dd.line_no = l.line_no order by dd.id desc limit 1) as dec,
           exists (select 1 from public.journal_entries je where je.source_type = 'mkt_spend' and je.source_id = l.entry_id::text || ':' || l.rev_no || ':' || l.line_no and je.reverses_id is null
                    and not exists (select 1 from public.journal_entries r where r.reverses_id = je.id)) as posted,
           exists (select 1 from public.entries e2, lateral jsonb_array_elements(case when jsonb_typeof(e2.data -> 'lines') = 'array' then e2.data -> 'lines' else '[]'::jsonb end) x
                    where e2.form_code = '10-2' and e2.status in ('submitted', 'approved') and e2.location_id = l.location_id and e2.entry_date = l.day
                      and x ->> 'head' = 'marketing' and public._r2_num(x -> 'amount') = l.amt)
           or exists (select 1 from public.quick_expenses q where q.status <> 'void' and q.location_id = l.location_id and q.exp_date = l.day and q.head = 'marketing' and q.amount = l.amt) as lookalike
      from l)
  select j.entry_id, j.serial, j.rev_no, j.location_id, j.line_no, j.day, j.head, j.campaign_code, j.amt, j.source, j.receipt, j.k,
    case when j.posted then 'posted'
         when j.dec = 'skip' then 'decided_skip'
         when j.source = 'imprest' then 'skip_imprest'
         when j.source is null then 'needs_source'
         when j.source = 'owner' then 'owner_money'
         when j.source not in ('bank', 'mobile', 'card') then 'needs_source'
         when j.dec is distinct from 'post' and j.lookalike then 'possible_duplicate'
         when (select a from st) is null or (select f from st) is null then 'not_set_up'
         when j.day < (select a from st) or j.day < (select f::date from st) then 'before_start'
         when public._acct_locked(j.day) then 'period_locked'
         else 'to_post' end,
    case when j.source = 'imprest' then 'the imprest money is recorded by its 10-2 voucher'
         when j.lookalike and j.dec is distinct from 'post' then 'a 10-2 voucher or quick expense with the same head, amount, place and date exists' end,
    j.dec
  from j
$$;

-- ---------- preview (no write) ----------
create or replace function public.mkt_post_preview(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; rows_ jsonb; cnt jsonb; st date := public._acct_start(); f text := nullif(public.rule_txt('marketing_post_from'), '');
begin
  if not public.is_active() or not (public.rpt_access('marketing') or public._acct_view() or public._acct_manage()) then raise exception 'not allowed'; end if;
  perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  select coalesce(jsonb_agg(to_jsonb(z) order by z.day, z.serial, z.line_no), '[]'::jsonb) into rows_ from (
    select entry_id, serial, rev_no, location_id, line_no, day, head, campaign_code, amt, source, receipt, cls, why, decision from public._c3_post_lines(p_from, p_to, locs)) z;
  select coalesce(jsonb_object_agg(cls, jsonb_build_object('lines', n, 'amount', a)), '{}'::jsonb) into cnt
    from (select cls, count(*) as n, round(sum(amt), 2) as a from public._c3_post_lines(p_from, p_to, locs) group by 1) c;
  return jsonb_build_object('key', 'mkt_post', 'from', p_from, 'to', p_to, 'loc', p_loc, 'rows', rows_, 'counts', cnt,
    'setting', jsonb_build_object('on', public.rule_on('marketing_post_on'), 'from', f, 'accounting_start', st, 'accounting_on', public.rule_on('accounting_on'),
       'mappings_ok', (select count(*) from public.acct_mappings where key in ('exp_marketing', 'pay_bank', 'pay_mobile')) = 3),
    'notes', jsonb_build_array('approved_sheets_only', 'imprest_never_posted_here', 'look_alikes_wait_for_a_decision', 'owner_money_not_posted', 'management_profit_view_unchanged'),
    'basis', 'Approved 18-1 lines with a paid amount, classified before anything is written. Only "to_post" lines are posted, and only while the setting is ON.');
end $$;

-- a person decides a look-alike (or any) line: post it anyway or skip it for good
create or replace function public.mkt_post_decide(p_entry uuid, p_line int, p_decision text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text; n int;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if p_decision not in ('post', 'skip') then raise exception 'bad_decision'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  select * into e from public.entries where id = p_entry and form_code = '18-1';
  if not found or e.status <> 'approved' then raise exception 'sheet_not_approved'; end if;
  if not public.can_loc(e.location_id) then raise exception 'not allowed for this location'; end if;
  select jsonb_array_length(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) into n;
  if p_line is null or p_line < 1 or p_line > n then raise exception 'bad_line'; end if;
  if coalesce(public._r2_num(e.data -> 'lines' -> (p_line - 1) -> 'amt'), 0) <= 0 then raise exception 'bad_line'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.mkt_post_decisions (entry_id, rev_no, line_no, decision, reason, decided_by, decided_staff) values (p_entry, e.rev_no, p_line, p_decision, left(btrim(p_reason), 300), auth.uid(), sid);
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'mkt_post_decide', 'entries', p_entry::text, jsonb_build_object('line', p_line, 'rev', e.rev_no, 'decision', p_decision, 'reason', left(btrim(p_reason), 300)));
  return jsonb_build_object('ok', true, 'decision', p_decision);
end $$;

-- ---------- the posting run (dry by default). Posts "to_post" lines; reverses entries whose sheet / revision / line is gone ----------
create or replace function public.mkt_post_run(p_dry boolean default true, p_limit int default 200) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record; je record; lim int := least(greatest(coalesce(p_limit, 200), 1), 1000); n int := 0; rv int := 0; locked int := 0; errs jsonb := '[]'; more boolean := false; locs int[];
        lines_ jsonb; credit text; eid bigint; memo text; td date := public._acct_today(); st date := public._acct_start(); f date;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if not public.rule_on('marketing_post_on') then raise exception 'marketing_post_off'; end if;
  f := nullif(public.rule_txt('marketing_post_from'), '')::date;
  if st is null or f is null then raise exception 'marketing_post_needs_setup'; end if;
  select array_agg(l.id) into locs from public.locations l where public.can_loc(l.id);
  -- 1. reverse entries whose approved line no longer exists in that revision
  for je in select j.* from public.journal_entries j where j.source_type = 'mkt_spend' and j.reverses_id is null
              and not exists (select 1 from public.journal_entries r2 where r2.reverses_id = j.id)
              and not exists (select 1 from public.entries e, lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) with ordinality x(l, ord)
                               where e.form_code = '18-1' and e.status = 'approved' and e.id::text || ':' || e.rev_no || ':' || x.ord = j.source_id and public._r2_num(x.l -> 'amt') > 0)
              order by j.id loop
    if public._acct_locked(greatest(td, je.entry_date)) then locked := locked + 1; continue; end if;
    if not p_dry then perform public._acct_reverse(je.id, td, 'Marketing 18-1 line no longer approved'); end if;
    rv := rv + 1;
  end loop;
  -- 2. post what is classified to_post
  for r in select * from public._c3_post_lines(f, td + 1, coalesce(locs, '{}'::int[])) l where l.cls = 'to_post' order by l.day, l.serial, l.line_no loop
    if n >= lim then more := true; exit; end if;
    credit := case r.source when 'bank' then 'pay_bank' when 'card' then public._acct_paykey('card', true) when 'mobile' then 'pay_mobile' end;
    memo := left('Marketing 18-1 #' || r.serial || ' line ' || r.line_no || ': ' || coalesce(r.head, '') || coalesce(' / ' || r.campaign_code, ''), 300);
    begin
      if not p_dry then
        lines_ := public._acct_resolve(public._acct_merge(jsonb_build_array(jsonb_build_object('a', 'exp_marketing', 'd', r.amt), jsonb_build_object('a', credit, 'c', r.amt))), r.location_id);
        eid := public._acct_write(r.day, r.location_id, 'mkt_spend', r.skey, null, memo, null, lines_);
      end if;
      n := n + 1;
    exception when others then errs := errs || jsonb_build_object('key', r.skey, 'error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('dry', p_dry, 'posted', n, 'reversed', rv, 'period_locked', locked, 'more', more, 'errors', errs);
end $$;

-- the owner can move everything this file posted back to zero (use before switching the setting off for good); reason required
create or replace function public.mkt_post_wind_down(p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare je record; n int := 0; locked int := 0; td date := public._acct_today(); sid text;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  for je in select j.* from public.journal_entries j where j.source_type = 'mkt_spend' and j.reverses_id is null and not exists (select 1 from public.journal_entries r2 where r2.reverses_id = j.id) order by j.id loop
    if public._acct_locked(greatest(td, je.entry_date)) then locked := locked + 1; continue; end if;
    perform public._acct_reverse(je.id, td, 'Marketing posting wound down: ' || left(btrim(p_reason), 150)); n := n + 1;
  end loop;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail) values (auth.uid(), sid, 'mkt_post_wind_down', 'journal_entries', 'mkt_spend', jsonb_build_object('reversed', n, 'locked', locked, 'reason', left(btrim(p_reason), 300)));
  return jsonb_build_object('reversed', n, 'period_locked', locked);
end $$;

revoke all on function public._c3_rules_guard(), public._c3_post_lines(date, date, int[]) from public, anon, authenticated;
revoke all on function public.mkt_post_preview(date, date, int), public.mkt_post_decide(uuid, int, text, text), public.mkt_post_run(boolean, int), public.mkt_post_wind_down(text) from public, anon;
grant execute on function public.mkt_post_preview(date, date, int), public.mkt_post_decide(uuid, int, text, text), public.mkt_post_run(boolean, int), public.mkt_post_wind_down(text) to authenticated;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase462.sql
-- Phase 462 (RPT-C3, package R8 part 1) - AUDIT AND CONTROL: the audit log pager (#173) and the one register of voided, reversed and corrected records across every module (#182).
-- Paste AFTER phase458. Paste-twice safe. Read-only functions plus two indexes on audit_log (the table stays append-only; an index changes no row). No earlier phase file is edited.
--
--   aud_log_page      the append-only audit_log, newest first, filtered by dates / table / action / staff / text, paged (limit + offset) with the exact total. OWNER ONLY, like the
--                     audit_log table itself (its row-level policy is owner-only; this function does not widen it). CSV is built by the screen page by page; each export is logged.
--   aud_void_register every void, reversal and correction in one list: module, what, record date, WHEN it was voided (null where the module never stored the time - said so, not guessed),
--                     amount, who, reason, place. Nothing is hard-deleted anywhere, so this lists what the modules keep. Salary-related modules (payroll runs / payments, staff advances)
--                     appear only for the owner and holders of salary_view.
-- Access for the register: rpt_access('control') (owner, report_control or view_reports) and the caller's places. Test data only (test_*).

do $g$ begin
  if to_regprocedure('public._p458_present()') is null then raise exception 'phase462 needs phase458 first'; end if;
end $g$;

create index if not exists audit_log_at on public.audit_log (at desc);
create index if not exists audit_log_table_at on public.audit_log (table_name, at desc);

-- ---------- #173 audit log pager (owner only) ----------
create or replace function public.aud_log_page(p_from date default null, p_to date default null, p_table text default null, p_action text default null, p_staff text default null,
                                               p_search text default null, p_limit int default 50, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lim int := least(greatest(coalesce(p_limit, 50), 1), 500); off_ int := greatest(coalesce(p_offset, 0), 0); tot bigint; rows_ jsonb; q text := nullif(btrim(coalesce(p_search, '')), '');
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_from is not null and p_to is not null and p_from > p_to then raise exception 'bad_range'; end if;
  if q is not null and length(q) > 80 then raise exception 'bad_search'; end if;
  select count(*) into tot from public.audit_log a
   where (p_from is null or (a.at at time zone 'Asia/Dhaka')::date >= p_from) and (p_to is null or (a.at at time zone 'Asia/Dhaka')::date <= p_to)
     and (p_table is null or a.table_name = p_table) and (p_action is null or a.action = p_action) and (p_staff is null or a.staff_id = p_staff)
     and (q is null or a.record_id ilike '%' || q || '%' or a.detail::text ilike '%' || q || '%');
  select coalesce(jsonb_agg(to_jsonb(z) order by z.at desc, z.id desc), '[]'::jsonb) into rows_ from (
    select a.id, a.at, a.staff_id, a.user_id, a.action, a.table_name, a.record_id, a.detail from public.audit_log a
     where (p_from is null or (a.at at time zone 'Asia/Dhaka')::date >= p_from) and (p_to is null or (a.at at time zone 'Asia/Dhaka')::date <= p_to)
       and (p_table is null or a.table_name = p_table) and (p_action is null or a.action = p_action) and (p_staff is null or a.staff_id = p_staff)
       and (q is null or a.record_id ilike '%' || q || '%' or a.detail::text ilike '%' || q || '%')
     order by a.at desc, a.id desc limit lim offset off_) z;
  return jsonb_build_object('key', 'aud_log', 'rows', rows_, 'total', tot, 'limit', lim, 'offset', off_,
    'tables', (select coalesce(jsonb_agg(t order by t), '[]'::jsonb) from (select distinct table_name t from public.audit_log) x),
    'actions', (select coalesce(jsonb_agg(t order by t), '[]'::jsonb) from (select distinct action t from public.audit_log) x),
    'notes', jsonb_build_array('owner_only', 'append_only', 'times_are_asia_dhaka_dates'),
    'basis', 'Every add, change, export and approval the system wrote, newest first. Rows are never edited or deleted.');
end $$;

-- ---------- #182 voided / reversed / corrected records, all modules ----------
create or replace function public._c3_voids(d1 date, d2 date, locs int[], p_salary boolean)
returns table (module text, kind text, rec_id text, ref text, rec_date date, event_at timestamptz, amount numeric, who text, reason text, location_id int, route text)
language sql stable security definer set search_path = public as $$
  with x as (
    select 'sale'::text m, 'void'::text k, s.id::text rid, 'Receipt ' || s.receipt as ref, s.sale_date as rd, s.void_at as ev, s.total as am, coalesce(s.void_staff, public._c3_staff(s.void_by)) as wh, s.void_note as rs, s.location_id as loc, 'sale'::text as rt
      from public.sales s where s.status = 'void'
    union all select 'sale_payment', 'void', p.id::text, 'Payment ' || p.id, (p.paid_at at time zone 'Asia/Dhaka')::date, null, p.amount, null, p.void_note, p.location_id, 'sale_payment'
      from public.sale_payments p where p.voided
    union all select 'sale_return', 'void', r.id::text, 'Return ' || left(r.id::text, 8), (r.created_at at time zone 'Asia/Dhaka')::date, r.void_at, r.amount, public._c3_staff(r.void_by), r.void_note, r.location_id, 'sale_return'
      from public.sale_returns r where r.status = 'void' or r.void_at is not null
    union all select 'supplier_payment', 'void', p.id::text, 'Supplier payment ' || p.id, (p.paid_at at time zone 'Asia/Dhaka')::date, null, p.amount, public._c3_staff(p.void_by), p.void_note, p.location_id, 'supplier_payment'
      from public.supplier_payments p where p.voided
    union all select 'supplier_refund', 'void', f.id::text, 'Supplier refund ' || f.id, (f.refunded_at at time zone 'Asia/Dhaka')::date, null, f.amount, public._c3_staff(f.void_by), f.void_note, f.location_id, 'supplier_refund'
      from public.supplier_refunds f where f.voided
    union all select 'purchase_bill', 'void', b.id::text, 'Bill ' || coalesce(b.bill_no, left(b.id::text, 8)), b.bill_date, b.void_at, b.total, public._c3_staff(b.void_by), b.void_note, b.location_id, 'purchase'
      from public.purchase_bills b where b.status = 'void'
    union all select 'cash_move', 'void', c.id::text, 'Cash move ' || c.kind, c.move_date, c.void_at, c.amount, public._c3_staff(c.void_by), c.void_note, c.location_id, 'cash_move'
      from public.cash_moves c where c.status = 'void' or c.void_at is not null
    union all select 'quick_expense', 'void', q.id::text, 'Quick expense ' || q.head, q.exp_date, q.void_at, q.amount, public._c3_staff(q.void_by), q.void_note, q.location_id, 'quick_expense'
      from public.quick_expenses q where q.status = 'void' or q.void_at is not null
    union all select 'other_income', 'void', o.id::text, 'Other income ' || o.head, o.income_date, o.void_at, o.amount, public._c3_staff(o.void_by), o.void_note, o.location_id, 'other_income'
      from public.other_income o where o.status = 'void' or o.void_at is not null
    union all select 'money_charge', 'void', c.id::text, 'Bank / wallet charge ' || c.kind, c.charge_date, c.void_at, c.amount, public._c3_staff(c.void_by), c.void_note, c.location_id, 'money_charge'
      from public.money_charges c where c.status = 'void' or c.void_at is not null
    union all select 'money_transfer', 'void', t.id::text, 'Transfer ' || t.id, t.xfer_date, t.void_at, t.amount, public._c3_staff(t.void_by), t.void_note, t.location_id, 'money_transfer'
      from public.money_transfers t where t.status = 'void' or t.void_at is not null
    union all select 'production_run', 'void', r.id::text, 'Production run ' || left(r.id::text, 8), (r.made_at at time zone 'Asia/Dhaka')::date, r.void_at, null, public._c3_staff(r.void_by), r.void_note, r.location_id, 'production_run'
      from public.production_runs r where r.status = 'void' or r.void_at is not null
    union all select 'wallet_fee', 'void', w.id::text, 'Wallet fee ' || w.id, w.fee_date, w.void_at, w.amount, public._c3_staff(w.void_by), w.void_note, w.location_id, 'wallet_fee'
      from public.d_wallet_fees w where w.voided
    union all select 'wallet_move', 'void', w.id::text, 'Wallet move ' || w.id, w.move_date, w.void_at, w.amount, public._c3_staff(w.void_by), w.void_note, w.location_id, 'wallet_move'
      from public.d_wallet_moves w where w.voided
    union all select 'cost_bill', 'void', c.id::text, 'Cost bill ' || coalesce(c.bill_no, c.id::text), c.bill_date, c.void_at, c.amount, public._c3_staff(c.void_by), c.void_note, null::int, 'cost_bill'
      from public.cost_source_bills c where c.status = 'void' or c.void_at is not null
    union all select 'journal', 'reversal', j.id::text, j.source_type || ' ' || j.source_id, j.entry_date, j.created_at, (select sum(l.debit) from public.journal_lines l where l.entry_id = j.id), coalesce(j.created_staff, public._c3_staff(j.created_by)), j.memo, j.location_id, 'journal'
      from public.journal_entries j where j.reverses_id is not null
    union all select 'form_correction', 'correction', c.id::text, 'Form ' || c.form_code || ' ' || coalesce(c.entry_id, ''), (c.at at time zone 'Asia/Dhaka')::date, c.at, null, c.staff_id, c.note,
                    (select e.location_id from public.entries e where e.id::text = c.entry_id), 'entry'
      from public.corrections c
    union all select 'form_change_request', 'correction', r.id::text, 'Form change request ' || r.id, (r.decided_at at time zone 'Asia/Dhaka')::date, r.decided_at, null, r.decided_staff, r.reason,
                    (select e.location_id from public.entries e where e.id = r.entry_id), 'entry'
      from public.entry_change_requests r where r.status = 'approved'
    union all select 'payroll_run', 'void', r.id::text, 'Payroll run ' || to_char(r.month, 'YYYY-MM'), r.month, r.void_at, null, public._c3_staff(r.void_by), r.void_reason, r.location_id, 'payroll'
      from public.payroll_runs r where p_salary and (r.status = 'void' or r.void_at is not null)
    union all select 'payroll_payment', 'void', p.id::text, 'Payroll payment ' || p.id, p.pay_date, p.void_at, p.amount, public._c3_staff(p.void_by), p.void_reason, p.location_id, 'payroll'
      from public.payroll_payments p where p_salary and (p.status = 'void' or p.void_at is not null)
    union all select 'staff_advance', 'void', a.id::text, 'Staff advance ' || a.id, a.adv_date, a.void_at, a.amount, public._c3_staff(a.void_by), a.void_reason, a.location_id, 'payroll'
      from public.employee_advances a where p_salary and (a.status = 'void' or a.void_at is not null))
  select x.m, x.k, x.rid, x.ref, x.rd, x.ev, x.am, x.wh, x.rs, x.loc, x.rt from x
   where coalesce((x.ev at time zone 'Asia/Dhaka')::date, x.rd) between d1 and d2 and (x.loc is null or x.loc = any (locs))
$$;

create or replace function public.aud_void_register(p_from date, p_to date, p_loc int default null, p_module text default null, p_limit int default 500) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; sal boolean; lim int := least(greatest(coalesce(p_limit, 500), 1), 2000); rows_ jsonb; tot bigint;
begin
  perform public._c3_need('control'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  if p_loc is not null and cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  sal := public.is_owner() or public.rpt_grant('salary_view');
  select count(*) into tot from public._c3_voids(p_from, p_to, locs, sal) v where p_loc is null or v.location_id = p_loc;
  select coalesce(jsonb_agg(to_jsonb(z) order by z.sort_at desc nulls last, z.module), '[]'::jsonb) into rows_ from (
    select v.module, v.kind, v.rec_id, v.ref, v.rec_date, v.event_at, coalesce(v.event_at, v.rec_date::timestamptz) as sort_at, (v.event_at is null) as time_not_captured,
           v.amount, v.who, v.reason, v.location_id, v.route
      from public._c3_voids(p_from, p_to, locs, sal) v
     where (p_loc is null or v.location_id = p_loc) and (p_module is null or v.module = p_module)
     order by coalesce(v.event_at, v.rec_date::timestamptz) desc nulls last limit lim) z;
  return jsonb_build_object('key', 'aud_voids', 'from', p_from, 'to', p_to, 'loc', p_loc, 'rows', rows_, 'total', tot,
    'by_module', (select coalesce(jsonb_object_agg(v.module, jsonb_build_object('kind', v.kind, 'n', v.n, 'amount', v.amt)), '{}'::jsonb)
                    from (select m.module, min(m.kind) as kind, count(*) as n, round(sum(m.amount), 2) as amt from public._c3_voids(p_from, p_to, locs, sal) m where p_loc is null or m.location_id = p_loc group by m.module) v),
    'salary_hidden', not sal,
    'notes', jsonb_build_array('nothing_is_hard_deleted', 'time_not_captured_where_the_module_stores_none', 'dates_are_the_void_date_else_the_record_date') || case when sal then '[]'::jsonb else jsonb_build_array('salary_modules_hidden') end,
    'basis', 'Every voided record, journal reversal and recorded correction, from the table each module keeps. A blank "when" means that module never stored the time of the void.');
end $$;

revoke all on function public._c3_voids(date, date, int[], boolean) from public, anon, authenticated;
revoke all on function public.aud_log_page(date, date, text, text, text, text, int, int), public.aud_void_register(date, date, int, text, int) from public, anon;
grant execute on function public.aud_log_page(date, date, text, text, text, text, int, int), public.aud_void_register(date, date, int, text, int) to authenticated;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase463.sql
-- Phase 463 (RPT-C3, package R8 part 2) - AUDIT AND CONTROL: approval delays (#180), stock adjustment approval history (#174), missing cost / recipe / batch / expiry data (#183).
-- Paste AFTER phase462. Paste-twice safe. Read-only functions. No earlier phase file is edited.
--
--   aud_approval_delays      for every kind of request that waits for a person (form sheets, change requests, wastage, releases, emergency approvals, new list options, cash short cases,
--                            money requests): how many were asked, decided and are still waiting; clock hours from asked to decided (average, median, longest) by kind and by approver;
--                            and the oldest requests still waiting. Hours are clock hours (nights and holidays included). Nothing is called "late": no limit is invented.
--   aud_stock_adjustments    who asked for and who approved each stock adjustment: wastage requests, wastage recorded directly (no request, so no approver), count adjustments (through the
--                            counted sheet's approver, or direct) and transit-loss decisions. Unit value shown only to people who may see costs.
--   aud_cost_gaps            data that is missing and would make a profit or stock figure wrong: items with no cost price, finished goods with no active recipe, recipe lines with no waste
--                            percentage, ingredient / packaging with no cost under the chosen method (wraps d_recipe_cost_gaps), stock batches with no expiry date.
-- Access: rpt_access('control') (gaps: control OR stock) and the caller's places. Test data only (test_*).

do $g$ begin
  if to_regprocedure('public.aud_void_register(date,date,integer,text,integer)') is null then raise exception 'phase463 needs phase462 first'; end if;
end $g$;

create or replace function public._c3_hours(a timestamptz, b timestamptz) returns numeric language sql immutable as $$
  select case when a is null or b is null then null else round(extract(epoch from (b - a)) / 3600.0, 1) end
$$;

-- ---------- #180 approval delays ----------
create or replace function public._c3_requests(d1 date, d2 date, locs int[])
returns table (kind text, sub text, ref text, asked_by text, asked_at timestamptz, status text, decided_by text, decided_at timestamptz, location_id int)
language sql stable security definer set search_path = public as $$
  with x as (
    select 'form'::text k, e.form_code s, e.form_code || ' #' || e.serial as r, coalesce(e.created_staff, public._c3_staff(e.created_by)) as ab, e.submitted_at as aa,
           case e.status when 'submitted' then 'pending' else e.status end as st, e.checked_staff as db, e.checked_at as da, e.location_id as loc
      from public.entries e where e.submitted_at is not null and e.status in ('submitted', 'approved', 'rejected')
    union all select 'change_request', null, 'Change request ' || c.id, c.requested_staff, c.created_at, c.status, c.decided_staff, c.decided_at, (select e.location_id from public.entries e where e.id = c.entry_id)
      from public.entry_change_requests c
    union all select 'wastage', w.reason_code, 'Wastage request ' || left(w.id::text, 8), w.requested_staff, w.requested_at, w.status, w.decided_staff, w.decided_at, w.location_id
      from public.wastage_requests w
    union all select 'release', r.flag_code, 'Release request ' || r.id, r.requested_staff, r.requested_at, r.status, r.decided_staff, r.decided_at, (select e.location_id from public.entries e where e.id = r.entry_id)
      from public.release_requests r
    union all select 'emergency', g.grant_code, 'Emergency ' || g.id, g.requested_staff, g.created_at, g.status, g.decided_staff, g.decided_at, g.location_id
      from public.emergency_requests g
    union all select 'list_option', o.list_code, 'New option ' || coalesce(o.label_en, o.label_bn), public._c3_staff(o.requested_by), o.requested_at, o.status, public._c3_staff(o.decided_by), o.decided_at, null::int
      from public.option_requests o
    union all select 'cash_short', null, 'Cash short case ' || left(c.id::text, 8), null, c.created_at, case c.status when 'open' then 'pending' else c.status end, public._c3_staff(c.decided_by), c.decided_at, c.location_id
      from public.shortage_cash_cases c where c.status in ('open', 'approved', 'rejected')
    union all select 'money_request', q.kind, 'Money request ' || q.id, q.requested_staff, q.requested_at, q.status, q.decided_staff, q.decided_at, q.location_id
      from public.w1e_requests q)
  select x.k, x.s, x.r, x.ab, x.aa, x.st, x.db, x.da, x.loc from x
   where (x.aa at time zone 'Asia/Dhaka')::date between d1 and d2 and (x.loc is null or x.loc = any (locs))
$$;

create or replace function public.aud_approval_delays(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; bykind jsonb; byappr jsonb; pend jsonb; npend bigint; nodec bigint;
begin
  perform public._c3_need('control'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  if p_loc is not null and cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('kind', z.kind, 'asked', z.asked, 'decided', z.decided, 'approved', z.approved, 'rejected', z.rejected, 'pending', z.pending, 'cancelled_or_other', z.other,
          'avg_hours', z.avg_h, 'median_hours', z.med_h, 'max_hours', z.max_h) order by z.kind), '[]'::jsonb) into bykind
    from (select r.kind, count(*) as asked, count(*) filter (where r.decided_at is not null) as decided, count(*) filter (where r.status = 'approved') as approved,
                 count(*) filter (where r.status = 'rejected') as rejected, count(*) filter (where r.status = 'pending') as pending,
                 count(*) filter (where r.status not in ('pending', 'approved', 'rejected')) as other,
                 round(avg(public._c3_hours(r.asked_at, r.decided_at)), 1) as avg_h,
                 round((percentile_cont(0.5) within group (order by public._c3_hours(r.asked_at, r.decided_at)))::numeric, 1) as med_h,
                 max(public._c3_hours(r.asked_at, r.decided_at)) as max_h
            from public._c3_requests(p_from, p_to, locs) r where p_loc is null or r.location_id = p_loc group by r.kind) z;
  select coalesce(jsonb_agg(jsonb_build_object('approver', z.dby, 'decided', z.n, 'avg_hours', z.avg_h, 'max_hours', z.max_h) order by z.n desc, z.dby), '[]'::jsonb) into byappr
    from (select coalesce(r.decided_by, '(not recorded)') as dby, count(*) as n, round(avg(public._c3_hours(r.asked_at, r.decided_at)), 1) as avg_h, max(public._c3_hours(r.asked_at, r.decided_at)) as max_h
            from public._c3_requests(p_from, p_to, locs) r where r.decided_at is not null and (p_loc is null or r.location_id = p_loc) group by 1) z;
  select count(*), count(*) filter (where r.decided_at is not null and r.decided_by is null) into npend, nodec from public._c3_requests(p_from, p_to, locs) r where r.status = 'pending' and (p_loc is null or r.location_id = p_loc);
  select coalesce(jsonb_agg(to_jsonb(z) order by z.age_hours desc), '[]'::jsonb) into pend from (
    select r.kind, r.sub, r.ref, r.asked_by, r.asked_at, public._c3_hours(r.asked_at, now()) as age_hours, r.location_id
      from public._c3_requests(p_from, p_to, locs) r where r.status = 'pending' and (p_loc is null or r.location_id = p_loc) order by r.asked_at limit 200) z;
  select count(*) into nodec from public._c3_requests(p_from, p_to, locs) r where r.decided_at is not null and r.decided_by is null and (p_loc is null or r.location_id = p_loc);
  return jsonb_build_object('key', 'aud_approvals', 'from', p_from, 'to', p_to, 'loc', p_loc, 'by_kind', bykind, 'by_approver', byappr, 'pending', pend,
    'totals', jsonb_build_object('pending', npend, 'decided_without_approver_name', nodec),
    'notes', jsonb_build_array('clock_hours_not_working_hours', 'no_late_limit_invented', 'dated_by_the_day_it_was_asked'),
    'basis', 'Hours from "asked" to "decided" on the clock. The list shows the oldest requests still waiting, with their age now.');
end $$;

-- ---------- #174 stock adjustment approval history ----------
create or replace function public._c3_stockadj(d1 date, d2 date, locs int[])
returns table (kind text, rec_id text, on_date date, item_id uuid, qty numeric, unit_cost numeric, reason text, asked_by text, asked_at timestamptz, approver text, decided_at timestamptz,
               status text, note text, location_id int, route text)
language sql stable security definer set search_path = public as $$
  select 'wastage_request'::text, w.id::text, (w.requested_at at time zone 'Asia/Dhaka')::date, w.item_id, -w.qty, null::numeric, w.reason_code, w.requested_staff, w.requested_at, w.decided_staff, w.decided_at, w.status, w.decision_note, w.location_id, 'wastage'::text
    from public.wastage_requests w where (w.requested_at at time zone 'Asia/Dhaka')::date between d1 and d2 and w.location_id = any (locs)
  union all
  select 'wastage_direct', s.id::text, (s.made_at at time zone 'Asia/Dhaka')::date, s.item_id, -s.qty, (select l.unit_cost from public.stock_ledger l where l.id = s.ledger_id), s.reason_code, s.created_staff, s.created_at, null, null, 'recorded', s.note, s.location_id, 'wastage'
    from public.stock_wastage s where (s.made_at at time zone 'Asia/Dhaka')::date between d1 and d2 and s.location_id = any (locs) and not exists (select 1 from public.wastage_requests w where w.wastage_id = s.id)
  union all
  select case when l.ref_type = 'entry' then 'count_sheet' else 'count_direct' end, l.id::text, (l.made_at at time zone 'Asia/Dhaka')::date, l.item_id, l.qty_delta, l.unit_cost, 'count_adjust',
         public._c3_staff(l.created_by), l.created_at, e.checked_staff, e.checked_at, case when l.ref_type = 'entry' then e.status else 'recorded' end, l.note, l.location_id, 'entry'
    from public.stock_ledger l left join public.entries e on l.ref_type = 'entry' and e.id::text = l.ref_id
   where l.reason = 'count_adjust' and (l.made_at at time zone 'Asia/Dhaka')::date between d1 and d2 and l.location_id = any (locs)
  union all
  select 'transit_loss', t.id::text, coalesce(t.received_on, (t.created_at at time zone 'Asia/Dhaka')::date), t.item_id, -t.qty_short, null, t.status, null, t.created_at, public._c3_staff(t.decided_by), t.decided_at, t.status, t.note, t.to_location_id, 'shortages'
    from public.shortage_transit t where coalesce(t.received_on, (t.created_at at time zone 'Asia/Dhaka')::date) between d1 and d2 and t.to_location_id = any (locs)
$$;

create or replace function public.aud_stock_adjustments(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; cost_ok boolean := public.rpt_cost_ok(); rows_ jsonb; bykind jsonb; noappr bigint;
begin
  perform public._c3_need('control'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  if p_loc is not null and cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(to_jsonb(z) order by z.on_date desc, z.kind), '[]'::jsonb) into rows_ from (
    select a.kind, a.rec_id, a.on_date, i.code as item_code, i.name_en as item_name, a.qty, case when cost_ok then a.unit_cost end as unit_cost,
           case when cost_ok and a.unit_cost is not null then round(a.qty * a.unit_cost, 2) end as value, a.reason, a.asked_by, a.asked_at, a.approver, a.decided_at,
           public._c3_hours(a.asked_at, a.decided_at) as hours_to_decide, a.status, a.note, a.location_id, a.route,
           (a.approver is null and a.status in ('approved', 'written_off', 'claimed', 'recovered')) as approver_missing
      from public._c3_stockadj(p_from, p_to, locs) a left join public.items i on i.id = a.item_id where p_loc is null or a.location_id = p_loc order by a.on_date desc, a.kind limit 2000) z;
  select coalesce(jsonb_agg(jsonb_build_object('kind', k.kind, 'n', k.n, 'with_approver', k.wa, 'without_approver', k.n - k.wa) order by k.kind), '[]'::jsonb) into bykind
    from (select a.kind, count(*) as n, count(*) filter (where a.approver is not null) as wa from public._c3_stockadj(p_from, p_to, locs) a where p_loc is null or a.location_id = p_loc group by a.kind) k;
  select count(*) into noappr from public._c3_stockadj(p_from, p_to, locs) a where a.approver is null and a.status in ('approved', 'written_off', 'claimed', 'recovered') and (p_loc is null or a.location_id = p_loc);
  return jsonb_build_object('key', 'aud_stockadj', 'from', p_from, 'to', p_to, 'loc', p_loc, 'rows', rows_, 'by_kind', bykind, 'totals', jsonb_build_object('rows', jsonb_array_length(rows_), 'approver_missing', noappr),
    'notes', jsonb_build_array('direct_wastage_has_no_request', 'qty_negative_is_stock_out') || case when cost_ok then '[]'::jsonb else jsonb_build_array('cost_hidden') end,
    'basis', 'Each adjustment of stock with who asked, who decided and how long it took. "Direct" entries had no request, so there is no approver to show.');
end $$;

-- ---------- #183 missing cost, recipe, batch or expiry data ----------
create or replace function public.aud_cost_gaps(p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; s1 jsonb; s2 jsonb; s3 jsonb; s4 jsonb := '[]'; s5 jsonb; n1 bigint; n2 bigint; n3 bigint; n5 bigint; lc record; cost_hidden boolean := false; part jsonb; seen text[] := '{}'; rj jsonb;
begin
  if not public.is_active() or not (public.rpt_access('control') or public.rpt_access('stock')) then raise exception 'not allowed'; end if;
  locs := public._c3_locs(p_loc);
  if p_loc is not null and cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  select count(*) into n1 from public.items i where i.is_active and i.count_in_business and coalesce(i.sellable, true) and not exists (select 1 from public.item_costs c where c.item_id = i.id and c.cost_price is not null);
  select coalesce(jsonb_agg(to_jsonb(z) order by z.code), '[]'::jsonb) into s1 from (
    select i.id as item_id, i.code, i.name_bn, i.name_en, i.item_type from public.items i
     where i.is_active and i.count_in_business and coalesce(i.sellable, true) and not exists (select 1 from public.item_costs c where c.item_id = i.id and c.cost_price is not null) order by i.code limit 300) z;
  select count(*) into n2 from public.items i where i.is_active and i.item_type = 'finished_good' and not exists (select 1 from public.recipes r where r.item_id = i.id and r.active);
  select coalesce(jsonb_agg(to_jsonb(z) order by z.code), '[]'::jsonb) into s2 from (
    select i.id as item_id, i.code, i.name_bn, i.name_en from public.items i
     where i.is_active and i.item_type = 'finished_good' and not exists (select 1 from public.recipes r where r.item_id = i.id and r.active) order by i.code limit 300) z;
  select count(*) into n3 from public.recipe_lines l join public.recipes r on r.id = l.recipe_id where l.active and r.active and l.waste_pct is null;
  select coalesce(jsonb_agg(to_jsonb(z) order by z.recipe_item, z.ingredient), '[]'::jsonb) into s3 from (
    select r.id as recipe_id, fi.code as recipe_item, ii.code as ingredient, ii.name_en as ingredient_name, l.qty, l.unit from public.recipe_lines l join public.recipes r on r.id = l.recipe_id
      join public.items fi on fi.id = r.item_id join public.items ii on ii.id = l.ingredient_item_id where l.active and r.active and l.waste_pct is null limit 300) z;
  for lc in select x.id from public.locations x where x.id = any (locs) order by x.id loop
    begin
      part := public.d_recipe_cost_gaps(lc.id);
      for rj in select * from jsonb_array_elements(part) loop
        if not ((rj ->> 'item_id') = any (seen)) then seen := seen || (rj ->> 'item_id'); s4 := s4 || jsonb_build_array(rj || jsonb_build_object('location_id', lc.id)); end if;
      end loop;
    exception when others then cost_hidden := true;
    end;
  end loop;
  select count(*) into n5 from public.stock_batches b where b.qty_remaining > 0 and b.expires_at is null and b.location_id = any (locs) and (p_loc is null or b.location_id = p_loc);
  select coalesce(jsonb_agg(to_jsonb(z) order by z.made_at), '[]'::jsonb) into s5 from (
    select b.id as batch_id, b.batch_no, i.code, i.name_en, b.location_id, b.made_at, b.qty_remaining from public.stock_batches b join public.items i on i.id = b.item_id
     where b.qty_remaining > 0 and b.expires_at is null and b.location_id = any (locs) and (p_loc is null or b.location_id = p_loc) order by b.made_at limit 300) z;
  return jsonb_build_object('key', 'aud_gaps', 'loc', p_loc,
    'sections', jsonb_build_object(
      'item_no_cost', jsonb_build_object('total', n1, 'rows', s1), 'fg_no_recipe', jsonb_build_object('total', n2, 'rows', s2),
      'recipe_waste_missing', jsonb_build_object('total', n3, 'rows', s3), 'ingredient_no_cost', jsonb_build_object('total', jsonb_array_length(s4), 'rows', s4, 'cost_hidden', cost_hidden),
      'batch_no_expiry', jsonb_build_object('total', n5, 'rows', s5)),
    'notes', jsonb_build_array('lists_show_up_to_300_rows_each_total_is_exact', 'no_cost_means_profit_is_only_on_the_costed_part') || case when cost_hidden then jsonb_build_array('ingredient_costs_need_the_cost_right') else '[]'::jsonb end,
    'basis', 'Records the books depend on that are not filled in. A missing cost price is not shown as 0 anywhere; these lists show where that happens.');
end $$;

revoke all on function public._c3_hours(timestamptz, timestamptz), public._c3_requests(date, date, int[]), public._c3_stockadj(date, date, int[]) from public, anon, authenticated;
revoke all on function public.aud_approval_delays(date, date, int), public.aud_stock_adjustments(date, date, int), public.aud_cost_gaps(int) from public, anon;
grant execute on function public.aud_approval_delays(date, date, int), public.aud_stock_adjustments(date, date, int), public.aud_cost_gaps(int) to authenticated;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase464.sql
-- Phase 464 (RPT-C3, package R8 part 3) - AUDIT AND CONTROL: price-override approver captured (#175), voids / refunds / unusual transactions in one list (#176), per-user activity (#177).
-- Paste AFTER phase463. Paste-twice safe. No earlier phase file is edited; record_sale2 and every shared function stay as they are.
--
--   NEW CAPTURE (additive, never blocks a sale): trigger sales_c3_override_capture on sales (AFTER INSERT). When a bill has lines whose price was changed, it stores who approved:
--       approval 'grant'         the seller holds the price_override right and the owner switched pos_override_manager ON (the same rule record_sale2 uses);
--       approval 'emergency'     a one-off emergency approval was used (the decider is stored);
--       approval 'not_required'  the setting pos_override_manager is OFF, so no approver is asked for (today's behaviour);
--       approval 'unknown'       the bill came in by a path that does not carry the approval (stored as unknown, never guessed).
--     Bills made BEFORE this phase have no row: the report says "not captured", never an approver it does not know. Any error in the capture is swallowed - the sale always succeeds.
--   aud_overrides   discount approvals (already stored on the bill) and price-override approvals side by side, per bill, with counts by approver and the capture coverage.
--   aud_unusual     sale voids, voided payments, returns (and the refund paid), voided returns and the exceptions raised on bills: events of known kinds, NO invented threshold.
--   aud_user_activity  per person: logins (ok / failed), what he did (audit log actions, exports), bills made / voided / discounted, returns, forms created and decided.
--                   Login and audit-log columns come from owner-only tables, so only the owner sees them; everyone else with the control report sees the business-record columns.
-- Access: rpt_access('control') and the caller's places. Test data only (test_*).

do $g$ begin
  if to_regprocedure('public.aud_cost_gaps(integer)') is null or to_regprocedure('public._append_only43()') is null then raise exception 'phase464 needs phases 463 and 43 first'; end if;
end $g$;

create table if not exists public.sale_price_overrides (
  sale_id uuid primary key references public.sales(id),
  override_lines int not null check (override_lines >= 1),
  approval text not null check (approval in ('grant', 'emergency', 'not_required', 'unknown')),
  approver_by uuid, approver_staff text,
  captured_at timestamptz not null default now()
);
drop trigger if exists sale_price_overrides_ro on public.sale_price_overrides;
create trigger sale_price_overrides_ro before update or delete on public.sale_price_overrides for each row execute function public._append_only43();
drop trigger if exists sale_price_overrides_ro_t on public.sale_price_overrides;
create trigger sale_price_overrides_ro_t before truncate on public.sale_price_overrides for each statement execute function public._append_only43();
alter table public.sale_price_overrides enable row level security;
revoke all on public.sale_price_overrides from public, anon, authenticated;
grant select on public.sale_price_overrides to authenticated;
drop policy if exists sale_price_overrides_read on public.sale_price_overrides;
create policy sale_price_overrides_read on public.sale_price_overrides for select to authenticated
  using (public.is_active() and exists (select 1 from public.sales s where s.id = sale_id));

create or replace function public._c3_sale_override_capture() returns trigger language plpgsql security definer set search_path = public as $$
declare n int; em text; rid bigint; r public.emergency_requests; ap text := 'unknown'; who uuid; sid text;
begin
  begin
    select count(*) into n from jsonb_array_elements(case when jsonb_typeof(new.lines) = 'array' then new.lines else '[]'::jsonb end) e where e ->> 'override' = 'true';
    if coalesce(n, 0) = 0 then return new; end if;
    em := current_setting('bos.em_used', true);
    if em is not null and em ~ ':price_override' then
      select (x.m)[1]::bigint into rid from regexp_matches(em, '([0-9]+):price_override', 'g') as x(m) order by (x.m)[1]::bigint desc limit 1;
      select * into r from public.emergency_requests where id = rid;
      if found and r.decided_by is not null then ap := 'emergency'; who := r.decided_by; sid := r.decided_staff; end if;
    elsif not public.rule_on('pos_override_manager') then
      ap := 'not_required';
    elsif public.can_grant('price_override') then
      ap := 'grant'; who := new.created_by; select staff_id into sid from public.profiles where id = new.created_by;
    end if;
    insert into public.sale_price_overrides (sale_id, override_lines, approval, approver_by, approver_staff) values (new.id, n, ap, who, sid) on conflict (sale_id) do nothing;
  exception when others then null;     -- the capture must never stop a sale
  end;
  return new;
end $$;
drop trigger if exists sales_c3_override_capture on public.sales;
create trigger sales_c3_override_capture after insert on public.sales for each row execute function public._c3_sale_override_capture();

-- ---------- #175 discount and price-override approvals ----------
create or replace function public.aud_overrides(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; rows_ jsonb; byappr jsonb; cov jsonb; first_cap timestamptz;
begin
  perform public._c3_need('control'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  if p_loc is not null and cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  select min(captured_at) into first_cap from public.sale_price_overrides;
  with b as (
    select s.id, s.receipt, s.sale_date, s.location_id, s.created_staff, s.total, s.discount, s.discount_kind, s.discount_input, s.discount_approved_staff, s.discount_approval,
           (select count(*) from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e where e ->> 'override' = 'true') as ov_lines, o.approval as ov_approval, o.approver_staff as ov_staff
      from public.sales s left join public.sale_price_overrides o on o.sale_id = s.id
     where s.status = 'done' and s.sale_date between p_from and p_to and s.location_id = any (locs) and (p_loc is null or s.location_id = p_loc))
  select coalesce(jsonb_agg(jsonb_build_object('sale_id', b.id, 'receipt', b.receipt, 'sale_date', b.sale_date, 'location_id', b.location_id, 'seller', b.created_staff, 'total', b.total,
        'discount', nullif(b.discount, 0), 'discount_kind', b.discount_kind, 'discount_input', b.discount_input, 'discount_approver', b.discount_approved_staff, 'discount_approval', b.discount_approval,
        'override_lines', nullif(b.ov_lines, 0), 'override_approval', case when b.ov_lines = 0 then null else coalesce(b.ov_approval, 'not_captured') end, 'override_approver', b.ov_staff)
        order by b.sale_date desc, b.receipt desc), '[]'::jsonb) into rows_ from b where b.discount > 0 or b.ov_lines > 0;
  with b as (
    select s.discount, s.discount_approved_staff, s.discount_approval, (select count(*) from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e where e ->> 'override' = 'true') as ov_lines,
           o.approval as ov_approval, o.approver_staff as ov_staff
      from public.sales s left join public.sale_price_overrides o on o.sale_id = s.id
     where s.status = 'done' and s.sale_date between p_from and p_to and s.location_id = any (locs) and (p_loc is null or s.location_id = p_loc))
  select coalesce(jsonb_agg(jsonb_build_object('approver', z.ap, 'kind', z.k, 'bills', z.n) order by z.k, z.n desc), '[]'::jsonb) into byappr from (
      select coalesce(b.discount_approved_staff, '(none recorded)') as ap, 'discount'::text as k, count(*) as n from b where b.discount > 0 group by 1
      union all select coalesce(b.ov_staff, case when b.ov_approval = 'not_required' then '(not required: switch off)' else '(none recorded)' end), 'price_override', count(*) from b where b.ov_lines > 0 group by 1) z;
  select jsonb_build_object('discount_bills', count(*) filter (where discount > 0), 'discount_with_approver', count(*) filter (where discount > 0 and discount_approved_staff is not null),
         'override_bills', count(*) filter (where ov_lines > 0), 'override_captured', count(*) filter (where ov_lines > 0 and ov_approval is not null),
         'override_captured_pct', case when count(*) filter (where ov_lines > 0) > 0 then round(100.0 * count(*) filter (where ov_lines > 0 and ov_approval is not null) / count(*) filter (where ov_lines > 0), 1) end)
    into cov from (
      select s.discount, s.discount_approved_staff, o.approval as ov_approval,
             (select count(*) from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e where e ->> 'override' = 'true') as ov_lines
        from public.sales s left join public.sale_price_overrides o on o.sale_id = s.id
       where s.status = 'done' and s.sale_date between p_from and p_to and s.location_id = any (locs) and (p_loc is null or s.location_id = p_loc)) q;
  return jsonb_build_object('key', 'aud_overrides', 'from', p_from, 'to', p_to, 'loc', p_loc, 'rows', rows_, 'by_approver', byappr, 'coverage', cov,
    'capture_started', (first_cap at time zone 'Asia/Dhaka')::date,
    'settings', jsonb_build_object('pos_override_manager', public.rule_on('pos_override_manager'), 'pos_discount_manager', public.rule_on('pos_discount_manager')),
    'notes', jsonb_build_array('override_approver_captured_from_phase464', 'older_bills_say_not_captured', 'no_approver_is_asked_for_while_the_switch_is_off', 'a_discount_inside_the_limit_needs_no_approver'),
    'basis', 'Per bill: the approver stored with the discount, and the approver of a price change (stored by this phase onward). "Not captured" = the bill is older than the capture.');
end $$;

-- ---------- #176 voids, refunds and unusual transactions ----------
create or replace function public._c3_unusual(d1 date, d2 date, locs int[])
returns table (type text, on_date date, event_at timestamptz, ref text, amount numeric, who text, reason text, status text, flag text, location_id int, sale_id uuid)
language sql stable security definer set search_path = public as $$
  select 'sale_void'::text, coalesce((s.void_at at time zone 'Asia/Dhaka')::date, s.sale_date), s.void_at, 'Receipt ' || s.receipt, s.total, coalesce(s.void_staff, public._c3_staff(s.void_by)), s.void_note, 'void'::text, null::text, s.location_id, s.id
    from public.sales s where s.status = 'void' and coalesce((s.void_at at time zone 'Asia/Dhaka')::date, s.sale_date) between d1 and d2 and s.location_id = any (locs)
  union all
  select 'payment_void', (p.paid_at at time zone 'Asia/Dhaka')::date, null, 'Payment ' || p.id, p.amount, null, p.void_note, 'void', p.kind, p.location_id, p.sale_id
    from public.sale_payments p where p.voided and (p.paid_at at time zone 'Asia/Dhaka')::date between d1 and d2 and p.location_id = any (locs)
  union all
  select 'return', (r.created_at at time zone 'Asia/Dhaka')::date, r.created_at, 'Return ' || left(r.id::text, 8), r.amount, r.created_staff, r.note, r.status, r.reason_code, r.location_id, r.sale_id
    from public.sale_returns r where r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and r.location_id = any (locs)
  union all
  select 'refund_paid', (r.created_at at time zone 'Asia/Dhaka')::date, r.created_at, 'Return ' || left(r.id::text, 8), r.refund_amount, r.created_staff, r.note, r.status, r.refund_mode, r.location_id, r.sale_id
    from public.sale_returns r where r.status = 'done' and coalesce(r.refund_amount, 0) > 0 and (r.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and r.location_id = any (locs)
  union all
  select 'return_void', coalesce((r.void_at at time zone 'Asia/Dhaka')::date, (r.created_at at time zone 'Asia/Dhaka')::date), r.void_at, 'Return ' || left(r.id::text, 8), r.amount, public._c3_staff(r.void_by), r.void_note, r.status, r.reason_code, r.location_id, r.sale_id
    from public.sale_returns r where (r.status = 'void' or r.void_at is not null) and coalesce((r.void_at at time zone 'Asia/Dhaka')::date, (r.created_at at time zone 'Asia/Dhaka')::date) between d1 and d2 and r.location_id = any (locs)
  union all
  select 'exception', e.entry_date, e.created_at, 'Receipt ' || (select s.receipt from public.sales s where s.id = e.sale_id), e.amount, e.resolved_staff, e.resolved_note, e.status, e.flag_code, e.location_id, e.sale_id
    from public.exceptions e where e.sale_id is not null and e.entry_date between d1 and d2 and e.location_id = any (locs)
$$;

create or replace function public.aud_unusual(p_from date, p_to date, p_loc int default null, p_type text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; rows_ jsonb; bytype jsonb;
begin
  perform public._c3_need('control'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  if p_loc is not null and cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(to_jsonb(z) order by z.on_date desc, z.type), '[]'::jsonb) into rows_ from (
    select u.type, u.on_date, u.event_at, u.ref, u.amount, u.who, u.reason, u.status, u.flag, u.location_id, u.sale_id
      from public._c3_unusual(p_from, p_to, locs) u where (p_loc is null or u.location_id = p_loc) and (p_type is null or u.type = p_type) order by u.on_date desc, u.type limit 2000) z;
  select coalesce(jsonb_agg(jsonb_build_object('type', z.type, 'n', z.n, 'amount', z.a) order by z.type), '[]'::jsonb) into bytype
    from (select u.type, count(*) as n, round(sum(u.amount), 2) as a from public._c3_unusual(p_from, p_to, locs) u where p_loc is null or u.location_id = p_loc group by u.type) z;
  return jsonb_build_object('key', 'aud_unusual', 'from', p_from, 'to', p_to, 'loc', p_loc, 'rows', rows_, 'by_type', bytype,
    'notes', jsonb_build_array('events_of_known_kinds_not_a_threshold', 'a_refund_is_also_inside_its_return', 'payment_void_time_not_stored'),
    'basis', 'Bill voids, voided payments, returns and the refund paid, voided returns, and the exceptions raised on bills. Nothing here is flagged by an amount limit.');
end $$;

-- ---------- #177 per-user activity ----------
create or replace function public.aud_user_activity(p_from date, p_to date, p_staff text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; own boolean := public.is_owner(); rows_ jsonb; tl jsonb := null; lg jsonb := null;
begin
  perform public._c3_need('control'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(null);
  with ppl as (select p.staff_id, p.full_name, p.status from public.profiles p where p.staff_id is not null and (p_staff is null or p.staff_id = p_staff)),
  sl as (select s.created_staff as st, count(*) as bills, count(*) filter (where s.discount > 0) as disc
           from public.sales s where s.sale_date between p_from and p_to and s.location_id = any (locs) group by 1),
  vd as (select s.void_staff as st, count(*) as voided from public.sales s where s.status = 'void' and (s.void_at at time zone 'Asia/Dhaka')::date between p_from and p_to and s.location_id = any (locs) group by 1),
  rt as (select r.created_staff as st, count(*) as returns from public.sale_returns r where r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to and r.location_id = any (locs) group by 1),
  ec as (select e.created_staff as st, count(*) as made from public.entries e where (e.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to and e.location_id = any (locs) group by 1),
  ed as (select e.checked_staff as st, count(*) as decided from public.entries e where (e.checked_at at time zone 'Asia/Dhaka')::date between p_from and p_to and e.location_id = any (locs) group by 1),
  lo as (select a.staff_id as st, count(*) filter (where a.ok) as ok_, count(*) filter (where not a.ok) as bad_, max(a.at) filter (where a.ok) as last_ok from public.login_attempts a
          where own and (a.at at time zone 'Asia/Dhaka')::date between p_from and p_to group by 1),
  au as (select a.staff_id as st, count(*) as acts, count(*) filter (where a.action = 'export') as exports from public.audit_log a
          where own and (a.at at time zone 'Asia/Dhaka')::date between p_from and p_to group by 1)
  select coalesce(jsonb_agg(jsonb_build_object('staff_id', ppl.staff_id, 'name', ppl.full_name, 'status', ppl.status,
        'bills_made', coalesce(sl.bills, 0), 'bills_with_discount', coalesce(sl.disc, 0), 'bills_voided_by_him', coalesce(vd.voided, 0), 'returns_made', coalesce(rt.returns, 0),
        'forms_created', coalesce(ec.made, 0), 'forms_decided', coalesce(ed.decided, 0),
        'logins_ok', case when own then coalesce(lo.ok_, 0) end, 'logins_failed', case when own then coalesce(lo.bad_, 0) end, 'last_login', lo.last_ok,
        'audit_actions', case when own then coalesce(au.acts, 0) end, 'exports', case when own then coalesce(au.exports, 0) end)
        order by coalesce(sl.bills, 0) desc, ppl.staff_id), '[]'::jsonb) into rows_
    from ppl left join sl on sl.st = ppl.staff_id left join vd on vd.st = ppl.staff_id left join rt on rt.st = ppl.staff_id left join ec on ec.st = ppl.staff_id left join ed on ed.st = ppl.staff_id
         left join lo on lo.st = ppl.staff_id left join au on au.st = ppl.staff_id
   where coalesce(sl.bills, 0) + coalesce(vd.voided, 0) + coalesce(rt.returns, 0) + coalesce(ec.made, 0) + coalesce(ed.decided, 0) + coalesce(lo.ok_, 0) + coalesce(lo.bad_, 0) + coalesce(au.acts, 0) > 0;
  if own and p_staff is not null then
    select coalesce(jsonb_agg(jsonb_build_object('at', a.at, 'action', a.action, 'table', a.table_name, 'record', a.record_id) order by a.at desc), '[]'::jsonb) into tl
      from (select * from public.audit_log x where x.staff_id = p_staff and (x.at at time zone 'Asia/Dhaka')::date between p_from and p_to order by x.at desc limit 100) a;
    select coalesce(jsonb_agg(jsonb_build_object('at', a.at, 'ok', a.ok) order by a.at desc), '[]'::jsonb) into lg
      from (select * from public.login_attempts x where x.staff_id = p_staff and (x.at at time zone 'Asia/Dhaka')::date between p_from and p_to order by x.at desc limit 50) a;
  end if;
  return jsonb_build_object('key', 'aud_users', 'from', p_from, 'to', p_to, 'staff', p_staff, 'rows', rows_, 'timeline', tl, 'logins', lg,
    'notes', jsonb_build_array('business_record_columns', 'places_you_can_see_only') || case when own then '[]'::jsonb else jsonb_build_array('login_and_audit_columns_owner_only') end,
    'basis', 'Counts per person from the business records (bills, voids, returns, forms) and, for the owner, from the login and audit logs. Counts are not a judgement of the person.');
end $$;

revoke all on function public._c3_sale_override_capture(), public._c3_unusual(date, date, int[]) from public, anon, authenticated;
revoke all on function public.aud_overrides(date, date, int), public.aud_unusual(date, date, int, text), public.aud_user_activity(date, date, text) from public, anon;
grant execute on function public.aud_overrides(date, date, int), public.aud_unusual(date, date, int, text), public.aud_user_activity(date, date, text) to authenticated;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase465.sql
-- Phase 465 (RPT-C3, package R9 part 1) - PLANNING: the festival calendar (owner enters), the sales forecast (#184) and the item demand forecast (#185), each with its assumptions panel.
-- Paste AFTER phase464. Paste-twice safe. Read-only forecasts; the only table is the festival calendar. No earlier phase file is edited; biz_outlook and reorder_report stay as they are.
--
-- HOW THE FORECAST WORKS (said on the screen, in plain words, next to every number):
--   * It looks back over a WINDOW of completed days (the person types the days, or the owner sets "Forecast window"; no default is assumed).
--   * A TRADING DAY is a day with at least one bill in the chosen place(s). A day with no bill is treated as closed / no data - it is NOT counted as zero sales.
--   * For each future day it takes the SAME WEEKDAY's past trading days: expected = their average; LOW and HIGH = the smallest and the largest of them (a range of what happened,
--     NOT a statistical confidence interval; no probability is claimed). It also shows how many past days it used (n). With no past same-weekday day there is no figure (blank).
--   * Past days that fall inside an owner-entered FESTIVAL are left out of the ordinary average. A future festival day shows the owner-set uplift % separately ("with uplift") -
--     only when the owner typed one; nothing is guessed. No trend, weather or price change is modelled.
--   * Data coverage = trading days / calendar days of the window (shorter history than the window is said so). Sales are net of returns when the setting reports_net_of_returns is on.
--   * Item demand uses the stock ledger's units sold (base unit) and the same method; days an item was out of stock count as zero, so a stocked-out item may be under-estimated.
-- Access: rpt_access('sales') (item demand: sales or stock) (owner, report_sales or view_reports) and the caller's places. Festival entry: owner only. Test data only (test_*).

do $g$ begin
  if to_regprocedure('public._c3_sale_facts(date,date,integer[])') is null then raise exception 'phase465 needs phase459 first'; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'reports', v.kind, v.dv, v.unit, v.ch, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('fc_window_days', 'number', null::jsonb, 'days', null::jsonb, 7::numeric, 365::numeric,
   'Forecast window (days of history)',
   'How many completed days the sales and item forecasts look back over. Blank = the forecast pages ask the person to type the days; nothing is assumed. A longer window uses more history but reacts slower to change.', 920),
 ('fc_payroll_day', 'number', null::jsonb, 'day of month', null::jsonb, 1::numeric, 31::numeric,
   'Day of the month salaries are usually paid',
   'Used only by the expected cash calendar to place the next salary payment on a date. Blank = salary shows as "date not set". The amount is the last payroll run, repeated (said on the page).', 921)
  ) as v(key, kind, dv, unit, ch, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

-- ---------- festival calendar (the owner enters it; nothing is seeded; nothing is deleted) ----------
create table if not exists public.festival_calendar (
  id bigint generated by default as identity primary key,
  name_bn text not null check (length(btrim(name_bn)) between 1 and 120),
  name_en text check (name_en is null or length(name_en) <= 120),
  start_date date not null,
  end_date date not null,
  uplift_pct numeric(8, 2) check (uplift_pct is null or uplift_pct > -100),
  location_id int references public.locations(id),
  note text check (note is null or length(note) <= 300),
  active boolean not null default true,
  retired_reason text, retired_at timestamptz, retired_by uuid,
  created_by uuid, created_at timestamptz not null default now(),
  check (end_date >= start_date)
);
create index if not exists festival_calendar_dates on public.festival_calendar (start_date, end_date);
drop trigger if exists audit_festival_calendar on public.festival_calendar;
create trigger audit_festival_calendar after insert or update on public.festival_calendar for each row execute function public.log_change('id');
drop trigger if exists festival_calendar_no_delete on public.festival_calendar;
create trigger festival_calendar_no_delete before delete on public.festival_calendar for each row execute function public.no_hard_delete();
alter table public.festival_calendar enable row level security;
revoke all on public.festival_calendar from public, anon, authenticated;
grant select on public.festival_calendar to authenticated;
drop policy if exists festival_calendar_read on public.festival_calendar;
create policy festival_calendar_read on public.festival_calendar for select to authenticated using (public.is_active());

create or replace function public.festival_save(p_id bigint, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare bn text := nullif(btrim(p ->> 'name_bn'), ''); en text := nullif(btrim(p ->> 'name_en'), ''); sd date; ed date; up numeric; loc int; nt text := nullif(btrim(p ->> 'note'), ''); id_ bigint := p_id; o public.festival_calendar;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_value'; end if;
  if p_id is not null then select * into o from public.festival_calendar where id = p_id; if not found then raise exception 'not_found'; end if; end if;
  bn := coalesce(bn, o.name_bn); if bn is null then raise exception 'name_required'; end if;
  begin sd := coalesce(nullif(p ->> 'start_date', '')::date, o.start_date); ed := coalesce(nullif(p ->> 'end_date', '')::date, o.end_date, sd);
  exception when others then raise exception 'bad_date'; end;
  if sd is null then raise exception 'bad_date'; end if;
  if ed < sd then raise exception 'end_before_start'; end if;
  if p ? 'uplift_pct' then
    if nullif(btrim(p ->> 'uplift_pct'), '') is null then up := null;
    else
      if (p ->> 'uplift_pct') !~ '^-?[0-9]{1,5}(\.[0-9]{1,2})?$' then raise exception 'bad_uplift'; end if;
      up := (p ->> 'uplift_pct')::numeric; if up <= -100 then raise exception 'bad_uplift'; end if;
    end if;
  else up := o.uplift_pct; end if;
  if p ? 'location_id' then loc := nullif(p ->> 'location_id', '')::int; else loc := o.location_id; end if;
  if loc is not null and not exists (select 1 from public.locations where id = loc) then raise exception 'bad_location'; end if;
  if p_id is null then
    insert into public.festival_calendar (name_bn, name_en, start_date, end_date, uplift_pct, location_id, note, created_by) values (bn, en, sd, ed, up, loc, nt, auth.uid()) returning id into id_;
  else
    update public.festival_calendar set name_bn = bn, name_en = coalesce(en, name_en), start_date = sd, end_date = ed, uplift_pct = up, location_id = loc, note = coalesce(nt, note) where id = p_id;
  end if;
  return jsonb_build_object('ok', true, 'id', id_);
end $$;

create or replace function public.festival_retire(p_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  update public.festival_calendar set active = false, retired_reason = left(btrim(p_reason), 200), retired_at = now(), retired_by = auth.uid() where id = p_id and active;
  if not found then raise exception 'not_found'; end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.festival_reactivate(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  update public.festival_calendar set active = true, retired_reason = null, retired_at = null, retired_by = null where id = p_id and not active;
  if not found then raise exception 'not_found'; end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.festival_list(p_all boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._c3_need('sales');
  return jsonb_build_object('key', 'fc_festivals', 'rows', coalesce((select jsonb_agg(to_jsonb(f) order by f.start_date desc, f.id desc) from public.festival_calendar f where p_all or f.active), '[]'::jsonb),
    'notes', jsonb_build_array('owner_enters_every_festival', 'uplift_is_owner_set_never_guessed', 'nothing_is_deleted_only_retired'));
end $$;

-- ---------- trading days of a window (the base of every forecast) ----------
create or replace function public._c3_festival_of(p_day date, locs int[]) returns table (names text, uplift numeric, n int)
language sql stable security definer set search_path = public as $$
  select string_agg(coalesce(f.name_en, f.name_bn), ' / ' order by f.id), max(f.uplift_pct), count(*)::int
    from public.festival_calendar f where f.active and p_day between f.start_date and f.end_date and (f.location_id is null or f.location_id = any (locs))
$$;

create or replace function public._c3_fc_days(d1 date, d2 date, locs int[]) returns table (day date, dow int, net numeric, bills bigint, is_fest boolean)
language sql stable security definer set search_path = public as $$
  select f.sale_date, extract(dow from f.sale_date)::int, sum(f.net), count(*), (select (public._c3_festival_of(f.sale_date, locs)).n > 0)
    from public._c3_sale_facts(d1, d2, locs) f group by f.sale_date
$$;

-- ---------- #184 sales forecast ----------
create or replace function public.fc_sales_forecast(p_loc int, p_ahead int, p_window int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; w int := coalesce(p_window, public.rule_num('fc_window_days')::int); td date := public._c3_today(); d1 date; first_sale date; eff int; rows_ jsonb; assum jsonb;
        n_trade int; n_ord int; n_fest int; wobs jsonb; tot_e numeric; tot_lo numeric; tot_hi numeric; tot_up numeric; n_none int; any_up boolean;
begin
  perform public._c3_need('sales'); locs := public._c3_locs(p_loc);
  if p_loc is not null and cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  if w is null then return jsonb_build_object('key', 'fc_sales', 'data_needed', jsonb_build_array('fc_window_days'), 'rows', '[]'::jsonb, 'notes', jsonb_build_array('window_days_not_set'),
      'basis', 'Type the number of days to look back, or the owner sets "Forecast window". No value is assumed.'); end if;
  if w < 7 or w > 365 or p_ahead is null or p_ahead < 1 or p_ahead > 90 then raise exception 'bad_range'; end if;
  d1 := td - w;
  select min(s.sale_date) into first_sale from public.sales s where s.status = 'done' and s.location_id = any (locs);
  eff := td - greatest(d1, coalesce(first_sale, td));
  select count(*), count(*) filter (where not is_fest), count(*) filter (where is_fest) into n_trade, n_ord, n_fest from public._c3_fc_days(d1, td - 1, locs);
  select coalesce(jsonb_object_agg(dow::text, n), '{}'::jsonb) into wobs from (select dow, count(*) as n from public._c3_fc_days(d1, td - 1, locs) where not is_fest group by dow) z;
  with base as (select * from public._c3_fc_days(d1, td - 1, locs) where not is_fest),
  g as (select dow, count(*) as n, avg(net) as a, min(net) as lo, max(net) as hi from base group by dow),
  fut as (select (td + i)::date as d, extract(dow from td + i)::int as dw, i from generate_series(0, p_ahead - 1) i)
  select coalesce(jsonb_agg(jsonb_build_object('date', fut.d, 'weekday', fut.dw, 'is_today', fut.i = 0, 'n_obs', coalesce(g.n, 0),
        'expected', round(g.a, 2), 'low', round(g.lo, 2), 'high', round(g.hi, 2),
        'festival', fe.names, 'festival_uplift_pct', fe.uplift, 'expected_with_uplift', case when fe.uplift is not null and g.a is not null then round(g.a * (1 + fe.uplift / 100), 2) end) order by fut.d), '[]'::jsonb),
         sum(g.a), sum(g.lo), sum(g.hi), sum(case when fe.uplift is not null and g.a is not null then g.a * (1 + fe.uplift / 100) else g.a end), count(*) filter (where g.a is null), bool_or(fe.uplift is not null)
    into rows_, tot_e, tot_lo, tot_hi, tot_up, n_none, any_up
    from fut left join g on g.dow = fut.dw left join lateral public._c3_festival_of(fut.d, locs) fe on fe.n > 0;
  assum := jsonb_build_object('window_days', w, 'window_from', d1, 'window_to', td - 1, 'first_sale_date', first_sale, 'effective_window_days', eff,
      'trading_days', n_trade, 'ordinary_trading_days', n_ord, 'festival_days_left_out', n_fest, 'calendar_days', eff,
      'data_coverage_pct', case when eff > 0 then round(100.0 * n_trade / eff, 1) end, 'same_weekday_days_used', wobs,
      'revenue_basis', case when coalesce(public.rule_on('reports_net_of_returns'), true) then 'net of returns' else 'bill totals, returns not netted' end,
      'uplift_entered_by_owner', coalesce(any_up, false), 'festival_rows', (select count(*) from public.festival_calendar where active));
  return jsonb_build_object('key', 'fc_sales', 'loc', p_loc, 'ahead', p_ahead, 'rows', rows_, 'assumptions', assum,
    'totals', jsonb_build_object('expected', round(tot_e, 2), 'low', round(tot_lo, 2), 'high', round(tot_hi, 2), 'expected_with_uplift', case when any_up then round(tot_up, 2) end, 'days_without_estimate', n_none),
    'notes', jsonb_build_array('range_is_lowest_and_highest_past_same_weekday_not_a_confidence_interval', 'no_probability_claimed', 'days_without_a_bill_are_closed_not_zero', 'festival_days_left_out_of_the_average',
                               'uplift_only_when_the_owner_typed_one', 'no_trend_weather_or_price_change') ||
             case when eff < w then jsonb_build_array('history_shorter_than_the_window') else '[]'::jsonb end,
    'basis', 'Average of the same weekday over the last ' || w || ' days; low and high are the smallest and largest of those days.');
end $$;

-- ---------- #185 item demand forecast ----------
create or replace function public.fc_item_demand(p_loc int, p_ahead int, p_window int default null, p_apply_uplift boolean default false, p_limit int default 500) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; w int := coalesce(p_window, public.rule_num('fc_window_days')::int); td date := public._c3_today(); d1 date; n_ord int; rows_ jsonb; tot bigint; unt bigint; lim int := least(greatest(coalesce(p_limit, 500), 1), 2000);
begin
  if not public.is_active() or not (public.rpt_access('sales') or public.rpt_access('stock')) then raise exception 'not allowed'; end if;
  locs := public._c3_locs(p_loc);
  if p_loc is not null and cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  if w is null then return jsonb_build_object('key', 'fc_items', 'data_needed', jsonb_build_array('fc_window_days'), 'rows', '[]'::jsonb, 'notes', jsonb_build_array('window_days_not_set')); end if;
  if w < 7 or w > 365 or p_ahead is null or p_ahead < 1 or p_ahead > 90 then raise exception 'bad_range'; end if;
  d1 := td - w;
  select count(*) into n_ord from public._c3_fc_days(d1, td - 1, locs) where not is_fest;
  select count(distinct (e ->> 'item_id')) into unt from public.sales s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
    join public.items i on i.id = (case when e ->> 'item_id' ~ '^[0-9a-f-]{36}$' then (e ->> 'item_id')::uuid end)
   where s.status = 'done' and s.sale_date between d1 and td - 1 and s.location_id = any (locs) and not i.tracked;
  with td_ as (select day, dow from public._c3_fc_days(d1, td - 1, locs) where not is_fest),
  u as (select l.item_id, (l.made_at at time zone 'Asia/Dhaka')::date as day, sum(-l.qty_delta) as q from public.stock_ledger l
         where l.reason in ('sale_out', 'sale_void_in', 'sale_return') and l.location_id = any (locs) and (l.made_at at time zone 'Asia/Dhaka')::date between d1 and td - 1 group by 1, 2),
  sold as (select item_id from u group by 1 having sum(q) > 0),
  g as (select s.item_id, t.dow, count(*) as n, avg(coalesce(u.q, 0)) as a, min(coalesce(u.q, 0)) as lo, max(coalesce(u.q, 0)) as hi
          from sold s cross join td_ t left join u on u.item_id = s.item_id and u.day = t.day group by 1, 2),
  tot_ as (select s.item_id, sum(coalesce(u.q, 0)) as units, count(*) filter (where coalesce(u.q, 0) > 0) as days_with from sold s cross join td_ t left join u on u.item_id = s.item_id and u.day = t.day group by 1),
  fut as (select (td + i)::date as d, extract(dow from td + i)::int as dw, 1 + case when p_apply_uplift then coalesce((select (public._c3_festival_of(td + i, locs)).uplift), 0) / 100 else 0 end as mult from generate_series(0, p_ahead - 1) i),
  f as (select g.item_id, sum(g.a) as e, sum(g.lo) as lo, sum(g.hi) as hi, sum(g.a * fut.mult) as eu, count(*) as dd
          from g join fut on fut.dw = g.dow group by 1),
  oh as (select b.item_id, sum(b.qty) as q from public.stock_balance b where b.location_id = any (locs) group by 1)
  select count(*), coalesce(jsonb_agg(jsonb_build_object('item_id', i.id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(i.id),
        'units_in_window', round(t.units, 3), 'trading_days_with_sale', t.days_with, 'avg_per_trading_day', case when n_ord > 0 then round(t.units / n_ord, 4) end,
        'expected', round(f.e, 3), 'low', round(f.lo, 3), 'high', round(f.hi, 3), 'expected_with_uplift', case when p_apply_uplift then round(f.eu, 3) end,
        'on_hand', round(oh.q, 3), 'days_cover', case when t.units > 0 and n_ord > 0 and oh.q is not null then round(oh.q / (t.units / n_ord), 1) end,
        'days_with_an_estimate', f.dd) order by f.e desc nulls last, i.code) filter (where true), '[]'::jsonb)
    into tot, rows_
    from tot_ t join public.items i on i.id = t.item_id left join f on f.item_id = t.item_id left join oh on oh.item_id = t.item_id;
  -- keep the answer small: the first lim rows (the sort above puts the biggest first)
  if jsonb_array_length(rows_) > lim then rows_ := (select jsonb_agg(x) from (select x from jsonb_array_elements(rows_) x limit lim) z); end if;
  return jsonb_build_object('key', 'fc_items', 'loc', p_loc, 'ahead', p_ahead, 'window_days', w, 'rows', rows_, 'items_total', tot,
    'assumptions', jsonb_build_object('window_from', d1, 'window_to', td - 1, 'ordinary_trading_days', n_ord, 'unit', 'base unit of each item (stock ledger)',
        'untracked_items_sold_not_covered', unt, 'uplift_applied', coalesce(p_apply_uplift, false)),
    'notes', jsonb_build_array('range_is_lowest_and_highest_past_same_weekday_not_a_confidence_interval', 'no_probability_claimed', 'days_out_of_stock_count_as_zero', 'untracked_items_not_covered') ||
             case when coalesce(p_apply_uplift, false) then jsonb_build_array('the_same_uplift_is_applied_to_every_item') else '[]'::jsonb end,
    'basis', 'Units sold per trading day from the stock ledger, same-weekday average over the last ' || w || ' days, summed over the next ' || p_ahead || ' days.');
end $$;

revoke all on function public._c3_festival_of(date, int[]), public._c3_fc_days(date, date, int[]) from public, anon, authenticated;
revoke all on function public.festival_save(bigint, jsonb), public.festival_retire(bigint, text), public.festival_reactivate(bigint), public.festival_list(boolean),
  public.fc_sales_forecast(int, int, int), public.fc_item_demand(int, int, int, boolean, int) from public, anon;
grant execute on function public.festival_save(bigint, jsonb), public.festival_retire(bigint, text), public.festival_reactivate(bigint), public.festival_list(boolean),
  public.fc_sales_forecast(int, int, int), public.fc_item_demand(int, int, int, boolean, int) to authenticated;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase466.sql
-- Phase 466 (RPT-C3, package R9 part 2) - PLANNING: production requirement (#186) and recipe-exploded raw material purchase forecast (#187).
-- Paste AFTER phase465. Paste-twice safe. Read-only functions. No earlier phase file is edited.
--
--   fc_production_requirement  for ONE place: finished goods that have an active recipe. Expected demand over the horizon (phase465 item forecast: same-weekday average, low/high range)
--                              + open online orders due inside the horizon - stock on hand = what to make. Shown as units and as recipe batches. Two columns, because the average
--                              already contains past order sales: "without orders" and "with open orders on top" (the person chooses; the page says the second may count some demand twice).
--   fc_raw_purchase            the same quantities pushed through the recipes (waste % included, like production preview): ingredient need, stock on hand, shortfall, lead days
--                              (setting reorder_lead_days) and, only for people who may see costs, the cost at the chosen costing method. Ingredients with no cost are counted, not priced.
-- Assumptions are returned with every answer. Nothing is posted or ordered. Access: rpt_access('stock'); item demand also needs a sales or stock report right. Test data only (test_*).

do $g$ begin
  if to_regprocedure('public.fc_item_demand(integer,integer,integer,boolean,integer)') is null then raise exception 'phase466 needs phase465 first'; end if;
end $g$;

create or replace function public.fc_production_requirement(p_loc int, p_ahead int, p_window int default null, p_basis text default 'expected') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare dem jsonb; td date := public._c3_today(); rows_ jsonb; norec jsonb; n_undated bigint; basis text := coalesce(p_basis, 'expected');
begin
  perform public._c3_need('stock');
  if p_loc is null or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if basis not in ('expected', 'high') then raise exception 'bad_basis'; end if;
  dem := public.fc_item_demand(p_loc, p_ahead, p_window, false, 2000);
  if dem ? 'data_needed' then return dem || jsonb_build_object('key', 'fc_production'); end if;
  with d as (select (x ->> 'item_id')::uuid as item_id, (x ->> 'expected')::numeric as e, (x ->> 'low')::numeric as lo, (x ->> 'high')::numeric as hi, (x ->> 'on_hand')::numeric as oh
               from jsonb_array_elements(dem -> 'rows') x),
  o as (select (l ->> 'item_id')::uuid as item_id, sum(public._base_qty((l ->> 'item_id')::uuid, (l ->> 'qty')::numeric, i.unit)) as q, count(*) filter (where public._base_qty((l ->> 'item_id')::uuid, (l ->> 'qty')::numeric, i.unit) is null) as bad
          from public.online_orders oo cross join lateral jsonb_array_elements(oo.lines) l join public.items i on i.id = (l ->> 'item_id')::uuid
         where oo.location_id = p_loc and oo.status in ('new', 'confirmed', 'packed') and oo.delivery_date between td and td + p_ahead - 1 group by 1),
  rc as (select distinct on (r.item_id) r.item_id, r.id as recipe_id, r.version, public._base_qty(r.item_id, r.yield_qty, r.yield_unit) as yb from public.recipes r where r.active order by r.item_id, r.version desc),
  j as (select coalesce(d.item_id, o.item_id) as item_id, d.e, d.lo, d.hi, coalesce(o.q, 0) as oq, o.bad, coalesce(d.oh, (select sum(b.qty) from public.stock_balance b where b.item_id = coalesce(d.item_id, o.item_id) and b.location_id = p_loc), 0) as oh
          from d full join o on o.item_id = d.item_id)
  select coalesce(jsonb_agg(jsonb_build_object('item_id', i.id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(i.id), 'recipe_id', rc.recipe_id, 'recipe_version', rc.version,
           'yield_per_batch', rc.yb, 'demand_expected', round(j.e, 3), 'demand_low', round(j.lo, 3), 'demand_high', round(j.hi, 3), 'open_orders', round(j.oq, 3), 'orders_unit_problem', coalesce(j.bad, 0),
           'on_hand', round(j.oh, 3),
           'to_make', case when j.e is null and j.oq = 0 then null else round(greatest((case when basis = 'high' then j.hi else j.e end) - j.oh, 0), 3) end,
           'to_make_with_orders', case when j.e is null and j.oq = 0 then null else round(greatest(coalesce(case when basis = 'high' then j.hi else j.e end, 0) + j.oq - j.oh, 0), 3) end,
           'batches', case when rc.yb > 0 and j.e is not null then round(greatest((case when basis = 'high' then j.hi else j.e end) - j.oh, 0) / rc.yb, 3) end,
           'batches_with_orders', case when rc.yb > 0 then round(greatest(coalesce(case when basis = 'high' then j.hi else j.e end, 0) + j.oq - j.oh, 0) / rc.yb, 3) end,
           'batches_whole_with_orders', case when rc.yb > 0 then ceil(greatest(coalesce(case when basis = 'high' then j.hi else j.e end, 0) + j.oq - j.oh, 0) / rc.yb) end,
           'no_demand_history', j.e is null) order by i.code), '[]'::jsonb)
    into rows_ from j join rc on rc.item_id = j.item_id join public.items i on i.id = j.item_id;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', i.id, 'code', i.code, 'name_en', i.name_en)), '[]'::jsonb) into norec
    from jsonb_array_elements(dem -> 'rows') x join public.items i on i.id = (x ->> 'item_id')::uuid
   where not exists (select 1 from public.recipes r where r.item_id = i.id and r.active);
  select count(*) into n_undated from public.online_orders oo where oo.location_id = p_loc and oo.status in ('new', 'confirmed', 'packed') and oo.delivery_date is null;
  return jsonb_build_object('key', 'fc_production', 'loc', p_loc, 'ahead', p_ahead, 'basis', basis, 'rows', rows_, 'sold_without_recipe', norec, 'assumptions', dem -> 'assumptions' ||
      jsonb_build_object('orders_counted', 'online orders new / confirmed / packed with a delivery date inside the horizon', 'orders_without_a_date_not_counted', n_undated, 'recipe', 'the active recipe with the highest version'),
    'notes', dem -> 'notes' || jsonb_build_array('orders_on_top_may_count_some_demand_twice', 'stock_on_hand_is_this_place_only', 'items_without_a_recipe_listed_apart', 'nothing_is_ordered_or_produced_by_this_report'),
    'basis_text', 'What to make = ' || case when basis = 'high' then 'the HIGH past same-weekday demand' else 'the expected (average) demand' end || ' over the horizon, minus stock on hand; the second column adds open orders due in the horizon.');
end $$;

create or replace function public.fc_raw_purchase(p_loc int, p_ahead int, p_window int default null, p_basis text default 'expected', p_with_orders boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare prod jsonb; cost_ok boolean := public.rpt_cost_ok(); lead numeric := public.rule_num('reorder_lead_days'); rows_ jsonb; tot numeric; uncosted int; bad_units int;
begin
  perform public._c3_need('stock');
  prod := public.fc_production_requirement(p_loc, p_ahead, p_window, p_basis);
  if prod ? 'data_needed' then return prod || jsonb_build_object('key', 'fc_raw'); end if;
  with pr as (select (x ->> 'recipe_id')::uuid as recipe_id, x ->> 'code' as fg_code,
                     coalesce(case when p_with_orders then (x ->> 'batches_with_orders')::numeric else (x ->> 'batches')::numeric end, 0) as b
                from jsonb_array_elements(prod -> 'rows') x),
  n as (select pr.fg_code, pr.b, rn.* from pr cross join lateral public._recipe_need(pr.recipe_id, pr.b, p_loc) rn where pr.b > 0),
  a as (select n.item_id, n.code, n.name_bn, n.name_en, n.base_unit, n.kind, sum(n.need) as need, max(n.on_hand) as oh, bool_and(n.unit_ok) as unit_ok, bool_or(n.waste_missing) as wm, bool_and(n.tracked) as tracked,
               jsonb_agg(jsonb_build_object('product', n.fg_code, 'batches', round(n.b, 3), 'need', n.need) order by n.fg_code) as used_by
          from n group by n.item_id, n.code, n.name_bn, n.name_en, n.base_unit, n.kind),
  c as (select a.*, case when cost_ok then public._d_material_cost(a.item_id, p_loc) end as uc from a)
  select coalesce(jsonb_agg(jsonb_build_object('item_id', c.item_id, 'code', c.code, 'name_bn', c.name_bn, 'name_en', c.name_en, 'kind', c.kind, 'base_unit', c.base_unit, 'need', round(c.need, 3), 'on_hand', round(c.oh, 3),
           'shortfall', round(greatest(c.need - c.oh, 0), 3), 'lead_days', lead, 'unit_cost', round(c.uc, 4), 'est_cost', case when c.uc is not null then round(greatest(c.need - c.oh, 0) * c.uc, 2) end,
           'unit_problem', not c.unit_ok, 'waste_percent_missing', c.wm, 'stock_not_tracked', not c.tracked, 'used_by', c.used_by) order by (greatest(c.need - c.oh, 0) = 0), c.code), '[]'::jsonb),
         round(sum(greatest(c.need - c.oh, 0) * c.uc), 2), count(*) filter (where cost_ok and c.uc is null and greatest(c.need - c.oh, 0) > 0), count(*) filter (where not c.unit_ok)
    into rows_, tot, uncosted, bad_units from c;
  return jsonb_build_object('key', 'fc_raw', 'loc', p_loc, 'ahead', p_ahead, 'basis', p_basis, 'with_orders', coalesce(p_with_orders, false), 'rows', rows_,
    'totals', jsonb_build_object('estimated_cost_of_shortfall', case when cost_ok then tot end, 'shortfall_items_without_a_cost', case when cost_ok then uncosted end, 'items_with_unit_problem', bad_units),
    'assumptions', prod -> 'assumptions' || jsonb_build_object('lead_days_setting', lead, 'cost_method', coalesce(public.rule_txt('d_material_cost_method'), 'average_purchase')),
    'notes', prod -> 'notes' || jsonb_build_array('need_includes_recipe_waste_percent', 'waste_percent_missing_means_zero_waste_was_used_and_is_flagged', 'stock_on_hand_counted_once_per_ingredient', 'no_supplier_order_is_placed') ||
             case when lead is null then jsonb_build_array('lead_days_not_set') else '[]'::jsonb end || case when cost_ok then '[]'::jsonb else jsonb_build_array('cost_hidden') end,
    'basis_text', 'Finished-goods quantities from the production requirement, exploded through each active recipe, summed per ingredient, less stock on hand.');
end $$;

revoke all on function public.fc_production_requirement(int, int, int, text), public.fc_raw_purchase(int, int, int, text, boolean) from public, anon;
grant execute on function public.fc_production_requirement(int, int, int, text), public.fc_raw_purchase(int, int, int, text, boolean) to authenticated;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase467.sql
-- Phase 467 (RPT-C3, package R9 part 3) - PLANNING: expected cash in / out calendar (#188), upcoming supplier payments (#189), expected wastage and expiry risk (#190).
-- Paste AFTER phase466. Paste-twice safe. Read-only functions. No earlier phase file is edited.
--
--   fc_supplier_payments  open supplier bills with a DUE DATE = bill date + the supplier's credit days. Overdue, due inside the horizon, and "date unknown" (no credit days or no bill date,
--                         e.g. an opening balance) are kept apart. An unknown date is never placed on the calendar.
--   fc_cash_calendar      known future money only, by day:
--                         IN   open online orders: the balance (subtotal - discount + delivery charge - advance) on the delivery date;
--                              customer dues: on oldest bill date + the customer's credit days WHEN the customers table has credit_days (otherwise "date unknown");
--                         OUT  supplier bills as above; salary: bills of an approved payroll run not yet paid, else (only if the owner set the pay day, fc_payroll_day) the LAST payroll run
--                              repeated on the next pay day - marked as an assumption; bank charges of recurring transfers.
--                         Recurring transfers between own accounts are listed apart and are not in the net. No opening balance, no forecast sales and no tax are included.
--   fc_expiry_risk        stock batches with an expiry date inside N days (the person types N, or the existing setting report_expiry_soon_days): units expected to be sold before expiry
--                         (first-expiring-first-out, the window's average sales per calendar day continuing) and the rest = at risk; already-expired stock apart; value at cost for people who may see cost.
-- Access: cash calendar / supplier payments rpt_access('cash') (supplier payments also 'purchase'); expiry rpt_access('stock'). Salary lines only for the owner and salary_view holders.
-- Test data only (test_*).

do $g$ begin
  if to_regprocedure('public.fc_raw_purchase(integer,integer,integer,text,boolean)') is null then raise exception 'phase467 needs phase466 first'; end if;
end $g$;

-- ---------- supplier bills with due dates ----------
create or replace function public._c3_sup_due(locs int[], p_all_places boolean)
returns table (supplier_id uuid, supplier text, bill_id uuid, bill_no text, bill_date date, credit_days int, open_amt numeric, due_date date, location_id int)
language sql stable security definer set search_path = public as $$
  select o.supplier_id, s.name, o.bill_id, o.bill_no, o.bill_date, s.credit_days, o.open_amt,
         case when o.bill_date is not null and s.credit_days is not null then o.bill_date + s.credit_days end, o.location_id
    from public._sup_open(null) o join public.suppliers s on s.id = o.supplier_id
   where o.open_amt > 0 and ((o.location_id is null and p_all_places) or o.location_id = any (locs))
$$;

create or replace function public.fc_supplier_payments(p_days int, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; td date := public._c3_today(); rows_ jsonb; tot jsonb; cov jsonb;
begin
  if not public.is_active() or not (public.rpt_access('cash') or public.rpt_access('purchase')) then raise exception 'not allowed'; end if;
  if p_days is null or p_days < 1 or p_days > 365 then raise exception 'bad_range'; end if;
  locs := public._c3_locs(p_loc);
  if p_loc is not null and cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('supplier_id', d.supplier_id, 'supplier', d.supplier, 'bill_id', d.bill_id, 'bill_no', d.bill_no, 'bill_date', d.bill_date, 'credit_days', d.credit_days,
        'open_amount', d.open_amt, 'due_date', d.due_date, 'days_overdue', case when d.due_date < td then td - d.due_date end, 'location_id', d.location_id,
        'status', case when d.due_date is null then 'date_unknown' when d.due_date < td then 'overdue' when d.due_date < td + p_days then 'due' else 'later' end)
        order by d.due_date nulls last, d.supplier), '[]'::jsonb) into rows_ from public._c3_sup_due(locs, p_loc is null) d;
  select jsonb_build_object('overdue', round(coalesce(sum(d.open_amt) filter (where d.due_date < td), 0), 2), 'due_in_horizon', round(coalesce(sum(d.open_amt) filter (where d.due_date >= td and d.due_date < td + p_days), 0), 2),
         'later', round(coalesce(sum(d.open_amt) filter (where d.due_date >= td + p_days), 0), 2), 'date_unknown', round(coalesce(sum(d.open_amt) filter (where d.due_date is null), 0), 2),
         'all_open', round(coalesce(sum(d.open_amt), 0), 2)),
         jsonb_build_object('bills', count(*), 'bills_with_a_date', count(*) filter (where d.due_date is not null), 'dated_pct', case when count(*) > 0 then round(100.0 * count(*) filter (where d.due_date is not null) / count(*), 1) end,
           'suppliers', count(distinct d.supplier_id), 'suppliers_without_credit_days', count(distinct d.supplier_id) filter (where d.credit_days is null))
    into tot, cov from public._c3_sup_due(locs, p_loc is null) d;
  return jsonb_build_object('key', 'fc_suppliers', 'from', td, 'days', p_days, 'loc', p_loc, 'rows', rows_, 'totals', tot, 'coverage', cov,
    'notes', jsonb_build_array('due_date_is_bill_date_plus_credit_days', 'unknown_date_is_not_placed_on_the_calendar', 'payments_already_made_are_taken_off_oldest_bill_first', 'no_discount_or_penalty_modelled'),
    'basis', 'Open supplier bills with the date they fall due. A supplier with no credit days has no due date; set it on the supplier to see it here.');
end $$;

-- ---------- #188 expected cash in / out ----------
create or replace function public.fc_cash_calendar(p_days int, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; td date := public._c3_today(); sal boolean; pay_day int := public.rule_num('fc_payroll_day')::int; has_cd boolean; ev jsonb := '[]'; cust_cd jsonb := '{}'; r record; days_ jsonb; buckets jsonb; tot jsonb;
        last_run record; outstanding numeric; outstanding_n int; nxt date; ass jsonb := '[]'; hid boolean := false;
begin
  if not public.is_active() or not public.rpt_access('cash') then raise exception 'not allowed'; end if;
  if p_days is null or p_days < 1 or p_days > 365 then raise exception 'bad_range'; end if;
  locs := public._c3_locs(p_loc);
  if p_loc is not null and cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  sal := public.is_owner() or public.rpt_grant('salary_view');
  -- build the event list in a temp-free way: one jsonb array of {d, kind, dir, amt, ref, assumed}
  -- orders
  for r in select oo.id, oo.order_no, oo.delivery_date as d, oo.subtotal - oo.discount + oo.delivery_charge - oo.advance as bal from public.online_orders oo
            where oo.status in ('new', 'confirmed', 'packed') and oo.delivery_date is not null and oo.location_id = any (locs) and (oo.subtotal - oo.discount + oo.delivery_charge - oo.advance) > 0 loop
    ev := ev || jsonb_build_object('d', r.d, 'kind', 'order_balance', 'dir', 'in', 'amt', r.bal, 'ref', 'Order #' || r.order_no);
  end loop;
  -- customers (credit days only if that column exists)
  has_cd := exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'customers' and column_name = 'credit_days');
  if has_cd then execute 'select coalesce(jsonb_object_agg(id::text, credit_days), ''{}''::jsonb) from public.customers where credit_days is not null' into cust_cd; end if;
  for r in select c.id, c.name, c.balance, c.oldest from public.customer_dues() c loop
    if has_cd and r.oldest is not null and cust_cd ? r.id::text then
      ev := ev || jsonb_build_object('d', r.oldest + (cust_cd ->> r.id::text)::int, 'kind', 'customer_due', 'dir', 'in', 'amt', r.balance, 'ref', r.name);
    else
      ev := ev || jsonb_build_object('d', null, 'kind', 'customer_due', 'dir', 'in', 'amt', r.balance, 'ref', r.name);
    end if;
  end loop;
  -- suppliers
  for r in select * from public._c3_sup_due(locs, p_loc is null) loop
    ev := ev || jsonb_build_object('d', r.due_date, 'kind', 'supplier_bill', 'dir', 'out', 'amt', r.open_amt, 'ref', r.supplier || coalesce(' / ' || r.bill_no, ''));
  end loop;
  -- salary
  if not sal then hid := true;
  else
    select coalesce(sum(l.net - coalesce(l.paid_amount, 0)), 0), count(*) into outstanding, outstanding_n from public.payroll_lines l join public.payroll_runs pr on pr.id = l.run_id
     where pr.status = 'approved' and l.active and l.payment_status in ('unpaid', 'partly') and l.location_id = any (locs);
    if outstanding > 0 then
      nxt := case when pay_day is null then null else (case when make_date(extract(year from td)::int, extract(month from td)::int, least(pay_day, 28)) >= td
            then make_date(extract(year from td)::int, extract(month from td)::int, least(pay_day, 28)) else (make_date(extract(year from td)::int, extract(month from td)::int, 1) + interval '1 month')::date + least(pay_day, 28) - 1 end) end;
      ev := ev || jsonb_build_object('d', nxt, 'kind', 'salary_owed', 'dir', 'out', 'amt', outstanding, 'ref', 'Approved payroll not yet paid (' || outstanding_n || ' lines)');
    elsif pay_day is not null then
      select pr.month, sum(l.net) as net into last_run from public.payroll_runs pr join public.payroll_lines l on l.run_id = pr.id and l.active
       where pr.status in ('approved', 'paid') and pr.location_id = any (locs) group by pr.month order by pr.month desc limit 1;
      if last_run.net is not null then
        nxt := case when make_date(extract(year from td)::int, extract(month from td)::int, least(pay_day, 28)) >= td then make_date(extract(year from td)::int, extract(month from td)::int, least(pay_day, 28))
                    else (make_date(extract(year from td)::int, extract(month from td)::int, 1) + interval '1 month')::date + least(pay_day, 28) - 1 end;
        ev := ev || jsonb_build_object('d', nxt, 'kind', 'salary_assumed', 'dir', 'out', 'amt', last_run.net, 'ref', 'Same as the payroll of ' || to_char(last_run.month, 'YYYY-MM'), 'assumed', true);
        ass := ass || to_jsonb('salary repeats the last payroll run on day ' || pay_day || ' of the month (the owner set the day)');
      end if;
    end if;
  end if;
  -- recurring transfers: fees are real money out, the transfer itself moves between own accounts
  for r in select m.id, m.name, m.amount, m.fee, m.day_of_month, m.start_date, m.end_date,
                  (date_trunc('month', td) + (g * interval '1 month'))::date as mon from public.money_recurring m cross join generate_series(0, (p_days / 28) + 1) g
            where m.active and (m.location_id is null or m.location_id = any (locs)) loop
    declare od date := r.mon + (least(r.day_of_month, extract(day from (r.mon + interval '1 month' - interval '1 day'))::int) - 1);
    begin
      if od >= td and od < td + p_days and od >= r.start_date and (r.end_date is null or od <= r.end_date) then
        ev := ev || jsonb_build_object('d', od, 'kind', 'recurring_transfer', 'dir', 'transfer', 'amt', r.amount, 'ref', r.name);
        if coalesce(r.fee, 0) > 0 then ev := ev || jsonb_build_object('d', od, 'kind', 'transfer_fee', 'dir', 'out', 'amt', r.fee, 'ref', r.name); end if;
      end if;
    end;
  end loop;
  with e as (select (x ->> 'd')::date as d, x ->> 'kind' as kind, x ->> 'dir' as dir, (x ->> 'amt')::numeric as amt, x ->> 'ref' as ref, coalesce((x ->> 'assumed')::boolean, false) as assumed from jsonb_array_elements(ev) x)
  select coalesce(jsonb_agg(jsonb_build_object('date', z.d, 'in', z.i, 'out', z.o, 'transfers', z.t, 'net_known', z.i - z.o, 'items', z.items) order by z.d), '[]'::jsonb) into days_
    from (select e.d, round(sum(e.amt) filter (where e.dir = 'in'), 2) as i0, coalesce(round(sum(e.amt) filter (where e.dir = 'in'), 2), 0) as i, coalesce(round(sum(e.amt) filter (where e.dir = 'out'), 2), 0) as o,
                 coalesce(round(sum(e.amt) filter (where e.dir = 'transfer'), 2), 0) as t, jsonb_agg(jsonb_build_object('kind', e.kind, 'dir', e.dir, 'amount', e.amt, 'ref', e.ref, 'assumed', e.assumed) order by e.kind, e.ref) as items
            from e where e.d >= td and e.d < td + p_days group by e.d) z;
  with e as (select (x ->> 'd')::date as d, x ->> 'kind' as kind, x ->> 'dir' as dir, (x ->> 'amt')::numeric as amt from jsonb_array_elements(ev) x)
  select jsonb_build_object('overdue_in', round(coalesce(sum(amt) filter (where dir = 'in' and d < td), 0), 2), 'overdue_out', round(coalesce(sum(amt) filter (where dir = 'out' and d < td), 0), 2),
         'date_unknown_in', round(coalesce(sum(amt) filter (where dir = 'in' and d is null), 0), 2), 'date_unknown_out', round(coalesce(sum(amt) filter (where dir = 'out' and d is null), 0), 2)),
         jsonb_build_object('in', round(coalesce(sum(amt) filter (where dir = 'in' and d >= td and d < td + p_days), 0), 2), 'out', round(coalesce(sum(amt) filter (where dir = 'out' and d >= td and d < td + p_days), 0), 2),
           'in_dated_later', round(coalesce(sum(amt) filter (where dir = 'in' and d >= td + p_days), 0), 2), 'out_dated_later', round(coalesce(sum(amt) filter (where dir = 'out' and d >= td + p_days), 0), 2))
    into buckets, tot from e;
  return jsonb_build_object('key', 'fc_cash', 'from', td, 'days', p_days, 'loc', p_loc, 'rows', days_, 'buckets', buckets, 'totals', tot,
    'assumptions', ass, 'coverage', jsonb_build_object('customer_credit_days_column', has_cd, 'salary_pay_day_set', pay_day is not null),
    'notes', jsonb_build_array('only_known_future_money', 'no_opening_balance_no_forecast_sales_no_tax', 'unknown_dates_are_not_placed_on_the_calendar', 'transfers_between_own_accounts_are_not_in_the_net') ||
             case when has_cd then '[]'::jsonb else jsonb_build_array('customers_have_no_credit_days_so_dues_are_undated') end ||
             case when hid then jsonb_build_array('salary_hidden') else '[]'::jsonb end,
    'basis', 'Money that is already owed or promised, on the day it is expected. It is not a prediction of sales or of the cash balance.');
end $$;

-- ---------- #190 expected wastage and expiry risk ----------
create or replace function public.fc_expiry_risk(p_loc int, p_days int default null, p_window int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; n int := coalesce(p_days, public.rule_num('report_expiry_soon_days')::int); w int := coalesce(p_window, public.rule_num('fc_window_days')::int); td date := public._c3_today(); d1 date; first_sale date; eff int;
        cost_ok boolean := public.rpt_cost_ok(); rows_ jsonb; expired jsonb; noexp bigint; tot jsonb;
begin
  perform public._c3_need('stock'); locs := public._c3_locs(p_loc);
  if p_loc is not null and cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  if n is null or w is null then
    return jsonb_build_object('key', 'fc_expiry', 'data_needed', (case when n is null then jsonb_build_array('report_expiry_soon_days') else '[]'::jsonb end) || (case when w is null then jsonb_build_array('fc_window_days') else '[]'::jsonb end),
      'rows', '[]'::jsonb, 'notes', jsonb_build_array('days_not_set'), 'basis', 'Type the days (or let the owner set the settings). Nothing is assumed.');
  end if;
  if n < 1 or n > 365 or w < 7 or w > 365 then raise exception 'bad_range'; end if;
  d1 := td - w;
  select min(s.sale_date) into first_sale from public.sales s where s.status = 'done' and s.location_id = any (locs);
  eff := greatest(td - greatest(d1, coalesce(first_sale, td)), 1);
  with u as (select l.item_id, l.location_id, sum(-l.qty_delta) as units from public.stock_ledger l
              where l.reason in ('sale_out', 'sale_void_in', 'sale_return') and l.location_id = any (locs) and (l.made_at at time zone 'Asia/Dhaka')::date between d1 and td - 1 group by 1, 2),
  wa as (select s.item_id, s.location_id, sum(s.qty) as q from public.stock_wastage s where s.location_id = any (locs) and (s.made_at at time zone 'Asia/Dhaka')::date between d1 and td - 1 group by 1, 2),
  b as (select b.id, b.item_id, b.location_id, b.batch_no, b.qty_remaining, b.expires_at, b.made_at, (b.expires_at at time zone 'Asia/Dhaka')::date as exp_d,
               greatest(extract(epoch from (b.expires_at - now())) / 86400.0, 0) as dte,
               coalesce(sum(b.qty_remaining) over (partition by b.item_id, b.location_id order by b.expires_at, b.id rows between unbounded preceding and 1 preceding), 0) as before_
          from public.stock_batches b where b.qty_remaining > 0 and b.expires_at is not null and b.expires_at > now() and b.location_id = any (locs) and (p_loc is null or b.location_id = p_loc)),
  c as (select b.*, greatest(coalesce(u.units, 0), 0) / eff as per_day, wa.q as wasted,
               coalesce(ic.cost_price, (select sb.avg_cost from public.stock_balance sb where sb.item_id = b.item_id and sb.location_id = b.location_id)) as uc
          from b left join u on u.item_id = b.item_id and u.location_id = b.location_id left join wa on wa.item_id = b.item_id and wa.location_id = b.location_id left join public.item_costs ic on ic.item_id = b.item_id),
  r as (select c.*, least(c.qty_remaining, greatest(c.per_day * c.dte - c.before_, 0)) as sold_before from c)
  select coalesce(jsonb_agg(jsonb_build_object('batch_id', r.id, 'batch_no', r.batch_no, 'item_id', i.id, 'code', i.code, 'name_en', i.name_en, 'name_bn', i.name_bn, 'location_id', r.location_id, 'qty_remaining', r.qty_remaining,
           'expires_on', r.exp_d, 'days_to_expiry', round(r.dte, 1), 'avg_sold_per_day', round(r.per_day, 4), 'expected_sold_before_expiry', round(r.sold_before, 3), 'at_risk_qty', round(r.qty_remaining - r.sold_before, 3),
           'at_risk_value', case when cost_ok and r.uc is not null then round((r.qty_remaining - r.sold_before) * r.uc, 2) end, 'wasted_in_window', r.wasted,
           'no_sales_history', coalesce(r.per_day, 0) = 0) order by r.exp_d, i.code), '[]'::jsonb)
    into rows_ from r join public.items i on i.id = r.item_id where r.exp_d <= td + n and r.expires_at > now();
  select coalesce(jsonb_agg(jsonb_build_object('batch_id', b.id, 'batch_no', b.batch_no, 'code', i.code, 'name_en', i.name_en, 'location_id', b.location_id, 'qty_remaining', b.qty_remaining, 'expired_on', (b.expires_at at time zone 'Asia/Dhaka')::date) order by b.expires_at), '[]'::jsonb)
    into expired from public.stock_batches b join public.items i on i.id = b.item_id where b.qty_remaining > 0 and b.expires_at <= now() and b.location_id = any (locs) and (p_loc is null or b.location_id = p_loc);
  select count(*) into noexp from public.stock_batches b where b.qty_remaining > 0 and b.expires_at is null and b.location_id = any (locs) and (p_loc is null or b.location_id = p_loc);
  select jsonb_build_object('batches', jsonb_array_length(rows_), 'at_risk_value', case when cost_ok then (select round(sum((x ->> 'at_risk_value')::numeric), 2) from jsonb_array_elements(rows_) x) end,
         'at_risk_value_missing_cost', case when cost_ok then (select count(*) from jsonb_array_elements(rows_) x where x ->> 'at_risk_value' is null and (x ->> 'at_risk_qty')::numeric > 0) end) into tot;
  return jsonb_build_object('key', 'fc_expiry', 'loc', p_loc, 'days', n, 'window_days', w, 'rows', rows_, 'already_expired', expired, 'totals', tot,
    'assumptions', jsonb_build_object('sales_per_day', 'units sold in the window / calendar days of the window (' || eff || '), continuing unchanged', 'order_of_use', 'first expiring batch first', 'no_new_stock_assumed', true,
        'batches_without_expiry_not_covered', noexp),
    'notes', jsonb_build_array('at_risk_is_stock_left_after_expected_sales_not_a_prediction_of_waste', 'no_restock_or_price_cut_modelled', 'batches_without_expiry_are_not_covered') || case when cost_ok then '[]'::jsonb else jsonb_build_array('cost_hidden') end,
    'basis', 'For each batch expiring within ' || n || ' days: units the shop is expected to sell before it expires (the average of the last ' || w || ' days, oldest batch first) and the units that would be left.');
end $$;

revoke all on function public._c3_sup_due(int[], boolean) from public, anon, authenticated;
revoke all on function public.fc_supplier_payments(int, int), public.fc_cash_calendar(int, int), public.fc_expiry_risk(int, int, int) from public, anon;
grant execute on function public.fc_supplier_payments(int, int), public.fc_cash_calendar(int, int), public.fc_expiry_risk(int, int, int) to authenticated;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase468.sql
-- Phase 468 (RPT-C3, package R9 part 4) - PLANNING: sales and profit what-if scenarios (#192) and seasonal / festival demand analysis (#193).
-- Paste AFTER phase467. Paste-twice safe. Read-only functions. No earlier phase file is edited.
--
--   fc_scenario   starts from what really happened in a chosen period (the management profit view's own building blocks: net sales, the costed part and its cost, vouchers, salary, fixed cost) and
--                 applies the percent changes the PERSON types: volume, price, unit cost, expenses, salary, fixed cost. No percent is suggested or assumed (all blank = the baseline unchanged).
--                 Costs of goods move with volume and unit cost only. The "result after costs" appears ONLY when every part is captured (costed share 100%, vouchers, salary and fixed cost all
--                 present); otherwise it is blank and the missing parts are named. A scenario is arithmetic on the owner's numbers, not a forecast.
--   fc_seasonal   for each past festival the owner entered: sales per trading day during it against the sales per trading day of the ordinary trading days in the N days before it (N is typed),
--                 the observed difference in %, and the uplift the owner entered for comparison; the same festival in several years is grouped. Plus sales by month with trading days, so the
--                 yearly pattern is visible. Observed differences are history, not promises; the number of days behind each figure is always shown.
-- Access: scenario rpt_access('profit') (costs also need rpt_cost_ok); seasonal rpt_access('sales'). Test data only (test_*).

do $g$ begin
  if to_regprocedure('public.fc_expiry_risk(integer,integer,integer)') is null then raise exception 'phase468 needs phase467 first'; end if;
end $g$;

create or replace function public.fc_scenario(p_loc int, p_from date, p_to date, p_inputs jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; cost_ok boolean := public.rpt_cost_ok(); k text; v text; inp jsonb := coalesce(p_inputs, '{}'::jsonb); vol numeric := 0; prc numeric := 0; cst numeric := 0; exp_ numeric := 0; sal numeric := 0; fix numeric := 0;
        b record; lines_ jsonb := '[]'; miss jsonb := '[]'; n2 numeric; c2 numeric; g2 numeric; e2 numeric; s2 numeric; f2 numeric; res0 numeric; res1 numeric; full_cost boolean;
begin
  perform public._c3_need('profit'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  if p_loc is not null and cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  if jsonb_typeof(inp) <> 'object' then raise exception 'bad_input'; end if;
  for k, v in select key, value #>> '{}' from jsonb_each(inp) loop
    if k not in ('volume_pct', 'price_pct', 'cost_pct', 'expense_pct', 'salary_pct', 'fixed_pct') then raise exception 'bad_input'; end if;
    if nullif(btrim(v), '') is null then continue; end if;
    if v !~ '^-?[0-9]{1,5}(\.[0-9]{1,2})?$' or v::numeric <= -100 then raise exception 'bad_input'; end if;
    case k when 'volume_pct' then vol := v::numeric; when 'price_pct' then prc := v::numeric; when 'cost_pct' then cst := v::numeric;
           when 'expense_pct' then exp_ := v::numeric; when 'salary_pct' then sal := v::numeric; else fix := v::numeric; end case;
  end loop;
  select sum(o_net) as net, sum(o_costed) as costed, sum(o_cogs) as cogs, sum(o_exp) as exp_, sum(o_sal) as sal, sum(o_fixed) as fixed, count(*) as n into b from public._p27_pl(p_from, p_to, locs);
  if coalesce(b.n, 0) = 0 or b.net is null then
    return jsonb_build_object('key', 'fc_scenario', 'from', p_from, 'to', p_to, 'loc', p_loc, 'data_needed', jsonb_build_array('sales_in_period'), 'lines', '[]'::jsonb, 'notes', jsonb_build_array('no_sales_in_the_period'));
  end if;
  n2 := b.net * (1 + vol / 100) * (1 + prc / 100);
  c2 := b.costed * (1 + vol / 100) * (1 + prc / 100);
  g2 := b.cogs * (1 + vol / 100) * (1 + cst / 100);
  e2 := b.exp_ * (1 + exp_ / 100); s2 := b.sal * (1 + sal / 100); f2 := b.fixed * (1 + fix / 100);
  full_cost := cost_ok and b.costed is not null and b.cogs is not null and b.net > 0 and abs(b.costed - b.net) < 0.005;
  if not cost_ok then miss := miss || to_jsonb('cost_hidden'::text); elsif b.costed is null or b.cogs is null or not full_cost then miss := miss || to_jsonb('cost_coverage_not_full'::text); end if;
  if b.exp_ is null then miss := miss || to_jsonb('expense_vouchers_not_captured'::text); end if;
  if b.sal is null then miss := miss || to_jsonb('salary_not_captured'::text); end if;
  if b.fixed is null then miss := miss || to_jsonb('fixed_cost_not_set'::text); end if;
  if jsonb_array_length(miss) = 0 then res0 := b.net - b.cogs - b.exp_ - b.sal - b.fixed; res1 := n2 - g2 - e2 - s2 - f2; end if;
  lines_ := jsonb_build_array(
    jsonb_build_object('key', 'net_sales', 'baseline', round(b.net, 2), 'scenario', round(n2, 2)),
    jsonb_build_object('key', 'costed_sales', 'baseline', case when cost_ok then round(b.costed, 2) end, 'scenario', case when cost_ok and b.costed is not null then round(c2, 2) end),
    jsonb_build_object('key', 'cost_of_goods_costed_part', 'baseline', case when cost_ok then round(b.cogs, 2) end, 'scenario', case when cost_ok and b.cogs is not null then round(g2, 2) end),
    jsonb_build_object('key', 'contribution_costed_part', 'baseline', case when cost_ok and b.costed is not null then round(b.costed - b.cogs, 2) end, 'scenario', case when cost_ok and b.costed is not null then round(c2 - g2, 2) end),
    jsonb_build_object('key', 'expense_vouchers', 'baseline', round(b.exp_, 2), 'scenario', round(e2, 2)),
    jsonb_build_object('key', 'salary', 'baseline', round(b.sal, 2), 'scenario', round(s2, 2)),
    jsonb_build_object('key', 'fixed_cost', 'baseline', round(b.fixed, 2), 'scenario', round(f2, 2)),
    jsonb_build_object('key', 'result_after_costs', 'baseline', round(res0, 2), 'scenario', round(res1, 2)));
  select jsonb_agg(l || jsonb_build_object('delta', case when l ->> 'baseline' is not null and l ->> 'scenario' is not null then round((l ->> 'scenario')::numeric - (l ->> 'baseline')::numeric, 2) end,
           'delta_pct', case when l ->> 'baseline' is not null and l ->> 'scenario' is not null and (l ->> 'baseline')::numeric <> 0 then round(100 * ((l ->> 'scenario')::numeric - (l ->> 'baseline')::numeric) / abs((l ->> 'baseline')::numeric), 1) end))
    into lines_ from jsonb_array_elements(lines_) l;
  return jsonb_build_object('key', 'fc_scenario', 'from', p_from, 'to', p_to, 'loc', p_loc, 'inputs', jsonb_build_object('volume_pct', vol, 'price_pct', prc, 'cost_pct', cst, 'expense_pct', exp_, 'salary_pct', sal, 'fixed_pct', fix),
    'lines', lines_, 'result_missing', miss,
    'notes', jsonb_build_array('arithmetic_on_typed_percents_not_a_forecast', 'goods_cost_moves_with_volume_and_unit_cost_only', 'no_percent_is_suggested', 'result_shown_only_when_every_part_is_captured', 'baseline_is_the_management_view_not_the_journal'),
    'basis', 'Baseline = what happened in the period (net sales after returns, the costed part and its cost, expense vouchers, salary sheets, fixed cost). Scenario = the same figures with the percent changes you typed.');
end $$;

create or replace function public.fc_seasonal(p_loc int, p_baseline_days int, p_months int default 24) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; td date := public._c3_today(); fest jsonb; mon jsonb; grp jsonb; up jsonb;
begin
  perform public._c3_need('sales'); locs := public._c3_locs(p_loc);
  if p_loc is not null and cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  if p_baseline_days is null or p_baseline_days < 7 or p_baseline_days > 90 or p_months is null or p_months < 1 or p_months > 60 then raise exception 'bad_range'; end if;
  with f as (select * from public.festival_calendar where active and end_date < td and (location_id is null or location_id = any (locs))),
  r as (
    select f.id, f.name_bn, f.name_en, f.start_date, f.end_date, f.uplift_pct,
           (select count(*) from public._c3_fc_days(f.start_date, f.end_date, locs)) as fdays,
           (select sum(net) from public._c3_fc_days(f.start_date, f.end_date, locs)) as fnet,
           (select count(*) from public._c3_fc_days(f.start_date - p_baseline_days, f.start_date - 1, locs) b where not b.is_fest) as bdays,
           (select sum(net) from public._c3_fc_days(f.start_date - p_baseline_days, f.start_date - 1, locs) b where not b.is_fest) as bnet
      from f)
  select coalesce(jsonb_agg(jsonb_build_object('festival_id', r.id, 'name_bn', r.name_bn, 'name_en', r.name_en, 'start', r.start_date, 'end', r.end_date, 'calendar_days', r.end_date - r.start_date + 1,
          'trading_days', r.fdays, 'net_sales', round(r.fnet, 2), 'avg_per_trading_day', case when r.fdays > 0 then round(r.fnet / r.fdays, 2) end,
          'baseline_trading_days', r.bdays, 'baseline_avg_per_trading_day', case when r.bdays > 0 then round(r.bnet / r.bdays, 2) end,
          'observed_difference_pct', case when r.fdays > 0 and r.bdays > 0 and r.bnet > 0 then round(100 * ((r.fnet / r.fdays) / (r.bnet / r.bdays) - 1), 1) end,
          'owner_uplift_pct', r.uplift_pct) order by r.start_date desc), '[]'::jsonb) into fest from r;
  select coalesce(jsonb_agg(jsonb_build_object('name', g.nm, 'occurrences', g.n, 'with_data', g.nd, 'average_observed_difference_pct', g.av) order by g.nm), '[]'::jsonb) into grp
    from (select lower(coalesce(x ->> 'name_en', x ->> 'name_bn')) as nm, count(*) as n, count(*) filter (where x ->> 'observed_difference_pct' is not null) as nd,
                 round(avg((x ->> 'observed_difference_pct')::numeric), 1) as av from jsonb_array_elements(fest) x group by 1) g;
  select coalesce(jsonb_agg(jsonb_build_object('name_bn', f.name_bn, 'name_en', f.name_en, 'start', f.start_date, 'end', f.end_date, 'owner_uplift_pct', f.uplift_pct) order by f.start_date), '[]'::jsonb) into up
    from public.festival_calendar f where f.active and f.end_date >= td and (f.location_id is null or f.location_id = any (locs));
  select coalesce(jsonb_agg(jsonb_build_object('month', m.mo, 'net_sales', round(m.net, 2), 'bills', m.bills, 'trading_days', m.td, 'avg_per_trading_day', case when m.td > 0 then round(m.net / m.td, 2) end,
          'festival_trading_days', m.ftd) order by m.mo), '[]'::jsonb) into mon
    from (select date_trunc('month', d.day)::date as mo, sum(d.net) as net, sum(d.bills) as bills, count(*) as td, count(*) filter (where d.is_fest) as ftd
            from public._c3_fc_days((date_trunc('month', td) - (p_months - 1) * interval '1 month')::date, td, locs) d group by 1) m;
  return jsonb_build_object('key', 'fc_seasonal', 'loc', p_loc, 'baseline_days', p_baseline_days, 'months', p_months, 'festivals', fest, 'grouped', grp, 'upcoming', up, 'by_month', mon,
    'notes', jsonb_build_array('observed_differences_are_history_not_promises', 'days_behind_each_figure_are_shown', 'baseline_is_ordinary_trading_days_before_the_festival', 'days_without_a_bill_are_closed_not_zero', 'owner_uplift_shown_for_comparison_only'),
    'basis', 'Per festival: sales per trading day during it against sales per trading day on ordinary trading days in the ' || p_baseline_days || ' days before it.');
end $$;

revoke all on function public.fc_scenario(int, date, date, jsonb), public.fc_seasonal(int, int, int) from public, anon;
grant execute on function public.fc_scenario(int, date, date, jsonb), public.fc_seasonal(int, int, int) to authenticated;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase470.sql
-- Phase 470 (RPT-HUB, part 1): Business Memory reports hub. Per-user saved items, date indexes, permission helpers.
-- READ ONLY over the business tables: nothing here changes a figure, a setting or a permission. No OFF switch: the hub is open to every
-- signed-in person, and each answer is cut down to the report rights that person already holds (see _rh_area_ok).
-- New: table rpthub_user_items (favourites, recently opened, saved views, home pins; one person sees only their own rows),
--      helpers _rh_area_ok / _rh_locs / _rh_staff / _rh_ts, rpt_hub_perms(), date indexes for the lookups of phases 471-476.
-- Safe to paste twice. Requires the report engine (phase9 / phase21). English text only for server messages; screen text is in the web files.
do $$ begin
  if to_regclass('public.sales') is null or to_regprocedure('public.rpt_access(text)') is null or to_regclass('public.stock_ledger') is null then
    raise exception 'rpthub_needs_earlier_phases: paste phases 8 to 21 first';
  end if;
end $$;

-- ---------- per-person saved items ----------
create table if not exists public.rpthub_user_items (
  id bigint generated by default as identity primary key,
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('fav', 'recent', 'view', 'pin')),
  item_key text not null check (length(item_key) between 1 and 80),           -- a report id from web/data/report_registry.json, or tool:<name> for a hub tool
  name text check (name is null or length(name) <= 80),                       -- saved views carry a name
  params jsonb not null default '{}'::jsonb check (pg_column_size(params) <= 4000),
  open_count int not null default 0,
  last_opened_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create unique index if not exists rpthub_user_items_uq on public.rpthub_user_items (user_id, kind, item_key, coalesce(name, ''));
create index if not exists rpthub_user_items_user on public.rpthub_user_items (user_id, kind, last_opened_at desc);
alter table public.rpthub_user_items enable row level security;
drop policy if exists rpthub_ui_read on public.rpthub_user_items;
drop policy if exists rpthub_ui_ins on public.rpthub_user_items;
drop policy if exists rpthub_ui_upd on public.rpthub_user_items;
drop policy if exists rpthub_ui_del on public.rpthub_user_items;
create policy rpthub_ui_read on public.rpthub_user_items for select to authenticated using (user_id = auth.uid());
create policy rpthub_ui_ins on public.rpthub_user_items for insert to authenticated with check (user_id = auth.uid() and public.is_active());
create policy rpthub_ui_upd on public.rpthub_user_items for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy rpthub_ui_del on public.rpthub_user_items for delete to authenticated using (user_id = auth.uid());
revoke all on public.rpthub_user_items from anon, authenticated;
grant select, insert, update, delete on public.rpthub_user_items to authenticated;

-- ---------- date indexes for the "what happened" lookups (only where the table has none on its time column) ----------
do $$
declare r record;
begin
  for r in select * from (values
    ('rpthub_sale_returns_at', 'sale_returns', 'created_at'), ('rpthub_transfers_sent', 'stock_transfers', 'sent_at'), ('rpthub_transfers_recv', 'stock_transfers', 'received_at'),
    ('rpthub_wastage_at', 'stock_wastage', 'made_at'), ('rpthub_prod_at', 'production_runs', 'made_at'), ('rpthub_ledger_at', 'stock_ledger', 'made_at'),
    ('rpthub_ledger_item', 'stock_ledger', 'item_id, made_at'), ('rpthub_ledger_batch', 'stock_ledger', 'batch_id'),
    ('rpthub_audit_at', 'audit_log', 'at'), ('rpthub_audit_rec', 'audit_log', 'table_name, record_id'), ('rpthub_exc_at', 'exceptions', 'created_at'),
    ('rpthub_sup_refund_at', 'supplier_refunds', 'refunded_at'), ('rpthub_bill_date', 'purchase_bills', 'bill_date'),
    ('rpthub_release_at', 'release_requests', 'requested_at'), ('rpthub_chg_at', 'entry_change_requests', 'created_at'), ('rpthub_emerg_at', 'emergency_requests', 'created_at'),
    ('rpthub_cashshort_date', 'shortage_cash_cases', 'case_date'), ('rpthub_transit_at', 'shortage_transit', 'created_at'),
    ('rpthub_empstat_at', 'employee_status_log', 'at'), ('rpthub_paypay_date', 'payroll_payments', 'pay_date'), ('rpthub_adv_date', 'employee_advances', 'adv_date'),
    ('rpthub_jrn_date', 'journal_entries', 'entry_date'), ('rpthub_cashmove_date', 'cash_moves', 'move_date'), ('rpthub_othinc_date', 'other_income', 'income_date'),
    ('rpthub_moneyx_date', 'money_transfers', 'xfer_date'), ('rpthub_wreq_at', 'wastage_requests', 'requested_at'), ('rpthub_pricehist_item', 'item_price_history', 'item_id, changed_at'),
    ('rpthub_entries_date', 'entries', 'entry_date, form_code')) v(ix, tbl, cols)
  loop
    if to_regclass('public.' || r.tbl) is not null then execute format('create index if not exists %I on public.%I (%s)', r.ix, r.tbl, r.cols); end if;
  end loop;
  if to_regclass('public.sales') is not null then create index if not exists rpthub_sales_void_at on public.sales (void_at) where status = 'void'; end if;
end $$;

-- ---------- helpers (closed to browsers; the public entry points call them) ----------
create or replace function public._rh_staff(u uuid) returns text language sql stable security definer set search_path = public as $$
  select coalesce(nullif(p.full_name, ''), p.staff_id) from public.profiles p where p.id = u;
$$;
-- the business day (Asia/Dhaka) a timestamp falls in
create or replace function public._rh_day(t timestamptz) returns date language sql immutable as $$ select (t at time zone 'Asia/Dhaka')::date $$;
-- time shown for a record that carries only a date: its creation time when that was the same day, else the end of that day
create or replace function public._rh_ts(d date, c timestamptz) returns timestamptz language sql immutable as $$
  select case when c is not null and (c at time zone 'Asia/Dhaka')::date = d then c else (d::timestamp + interval '23 hours 59 minutes') at time zone 'Asia/Dhaka' end;
$$;
create or replace function public._rh_locs() returns int[] language sql stable security definer set search_path = public as $$
  select coalesce(array(select l.id from public.locations l where public.can_loc(l.id)), '{}'::int[]);
$$;
-- may the caller see this kind of record? Reuses the report rights that already exist (report_<group>, view_reports, view_cost, salary_view ...).
create or replace function public._rh_area_ok(p_area text) returns boolean language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then return false; end if;
  if public.is_owner() then return true; end if;
  return case p_area
    when 'sales' then public.rpt_access('sales') or public.rpt_access('pos')
    when 'pos' then public.rpt_access('pos') or public.rpt_access('sales')
    when 'customers' then public.rpt_access('customers') or public.rpt_access('sales') or public.rpt_access('pos')
    when 'cash' then public.rpt_access('cash') or public.rpt_access('pos') or public.rpt_grant('accounts_view') or public.rpt_grant('view_daybook')
    when 'stock' then public.rpt_access('stock')
    when 'purchase' then public.rpt_access('purchase')
    when 'expense' then public.rpt_access('expense')
    when 'payroll' then public.rpt_grant('salary_view') or public.rpt_grant('payroll_manage')
    when 'hr' then public.rpt_grant('report_staff') or public.rpt_grant('employee_view') or public.rpt_grant('employee_manage')
    when 'control' then public.rpt_grant('report_control')
    when 'accounts' then public.rpt_grant('accounts_view') or public.rpt_grant('accounts_manage') or public.rpt_grant('view_daybook')
    when 'cost' then public.rpt_cost_ok()
    when 'export' then public.rpt_grant('export_data')
    else false end;
end $$;

create or replace function public.rpt_hub_perms() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a text; o jsonb := '{}'::jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  foreach a in array array['sales', 'pos', 'customers', 'cash', 'stock', 'purchase', 'expense', 'payroll', 'hr', 'control', 'accounts', 'cost', 'export'] loop
    o := o || jsonb_build_object(a, public._rh_area_ok(a));
  end loop;
  return jsonb_build_object('owner', public.is_owner(), 'areas', o, 'locations', to_jsonb(public._rh_locs()), 'generated_at', now());
end $$;

revoke all on function public._rh_staff(uuid), public._rh_day(timestamptz), public._rh_ts(date, timestamptz), public._rh_locs(), public._rh_area_ok(text) from public, anon, authenticated;
revoke all on function public.rpt_hub_perms() from public, anon;
grant execute on function public.rpt_hub_perms() to authenticated;

-- ============================================================================
-- End of FRESH part 17 of 21.
