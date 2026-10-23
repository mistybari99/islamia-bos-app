# LIVE DELTA: from the owner's current live database to the merged version (no old phase pasted again)

Written 20 Oct 2026 for the owner. **An agent never writes to the live project.** Everything below is pasted by the owner, after he has read it. Nothing here drops `bos112` or `bos113` logic; both are put back and kept.

## 1. What this is

The live database is, by the audit (`docs/RECOVERY_AUDIT.md` section 3 and D1/D2/D12):

1. built from the advanced line's pages `setup-run-1..25` (phases 72 to 135), pasted on 14-15 Oct;
2. then our line's 13 `sqlparts` (our phases 8 to 498) pasted on 18 Oct. **These parts start with phase 8, so the early phases (8 to 79) were pasted a second time and put their older function text back over the advanced line's changes.** The audit saw this in two places (`lock_check` lost bos113, `biz_items` lost bos112). A local simulation shows it is wider: **128 shared functions** that only the advanced line had changed went back to the phase 8-79 text, 10 more keep our text without the advanced logic, 1 differs in another way, and 17 have both lines' changes in different places;
3. plus hand-added blocks of the public `sqlparts` (`fix_lock_check.sql`, the `biz_items` fix with `_fix_fn_backup`, a pre-flight in part 12).

Our line's newest phases 499 and 501 to 505 (sweets fixes) are not in the sqlparts.

The merged version (fresh build = `tests/sql/ORDER.txt`, parts `docs/paste_parts/part01.sql ...`) keeps every logic of both lines. **This document brings the live database to exactly the same function texts and structure as a fresh build**, using only new, additive, paste-twice-safe phase files:

| file | what it does on the live database |
|---|---|
| `phase499.sql`, `phase501.sql` to `phase505.sql` | our newest phases (sweets fixes). All new switches OFF. Skip any that the probe says is already there (they are safe to paste twice anyway). |
| `phase529.sql` | the safety shim: creates `public._union_fn_backup` (where every replaced text is saved first); removes the parameter defaults of the 8-argument `acct_journal_post` (so a call with up to 7 arguments can never be "not unique"); re-creates the 7-argument one if it is missing. On a database whose `lock_check` already has our hooks it does nothing to it. |
| `phase530.sql` to `phase534.sql` | the 17 functions both lines changed: `lock_check` (bos113 owner mode + our bos87/bos89), `biz_items` and `rpt_agg_sql` (bos112 returns netting, bos110, bos88 cost source + our bos402 and phase 502), `_cust_bal`, `customer_dues`, `_acct_docs`, `_daybook_lines`, `_p27_pl`, `_r3q_l3_shop_pnl`, `_sale_stock_out`, `sale_return`, `stock_receive_transfer`, `stock_reconcile`, `stock_transfer`, `_recipe_lines_ok`, `acct_journal_post` (7 and 8 arguments). |
| `phase535.sql` to `phase538.sql` | puts the advanced line's logic back in 139 shared functions (128 reset to the phase 8-79 text, 10 with our text only, 1 other) so that they have the merged text. |
| `phase539.sql` | drops the two stale overloads `inbound_message_receive` (9 arguments) and `web_order_submit` (13 arguments) when the new ones exist; adds `public._union_audit()`. |

**Never pasted on the live project again:** phases 8 to 498 (already there), the advanced files 100 to 135 and 506 to 528 (already there under their original numbers 72 to 135; 506 to 528 are only the new NAMES of advanced phases 80 to 99, 120, 131, 132), any `*_test.sql`, anything with `test_project_only` in its name.

## 2. How each union file protects the database

Every file from 529 to 539 first looks at **every function it handles** and puts it in one of four states:

- **DONE**: the function already has exactly the merged text. Nothing happens.
- **KNOWN**: the function has a known older text (the base text of phases 8-79, the advanced text, our text, or the text the simulation of the live paste produced; recognised by md5). It is replaced by the merged text, and the old text is first saved in `public._union_fn_backup` (columns `id, fn, saved_at, why, def`).
- **PATCH** (only for the 17 functions both lines changed): the text is not a known one, but every patch site of the fallback is found: the patch is applied.
- **UNKNOWN**: nothing fits (a hand fix, or a text the simulation did not produce). **Nothing is changed in that file.** The error message lists ALL such functions in one message (this is the pattern of the pre-flight in `sqlparts/part12.sql`, for every function at once): `phaseNNN: these functions have an unknown text, nothing was changed. Send this message to the agent: public.xxx(...) (the text in this database is not one of the known texts and the patch sites are not all there; md5 ...)`.

So the worst case is a red message and an unchanged database, never a silent loss.

## 3. Step 0: read-only probe (change nothing)

Paste each block in the Supabase SQL editor and send the result text back if anything looks odd. SELECT only.

The six blocks A1 to A6 of `docs/RECOVERY_ROADMAP.md` Appendix A (which line's objects exist, which tags `lock_check` and `biz_items` carry, what `_fix_fn_backup` holds, `_i2_state`). Then these two:

```sql
-- A7. which of our newest phases are already in? (true = present)
select exists (select 1 from public.rules where key = 'transfer_partial_on')            as p499,
       exists (select 1 from public.rules where key = 'stock_unit_unknown_block')       as p501,
       exists (select 1 from public.rules where key = 'biz_items_net_returns')          as p502,
       exists (select 1 from public.rules where key = 'dues_net_advance_on')            as p503,
       exists (select 1 from public.rules where key = 'recipe_intermediate_on')         as p504,
       to_regclass('public.stock_tracking_map') is not null                             as p505,
       to_regclass('public._union_fn_backup') is not null                               as union_shim_there;

-- A8. fingerprint of the 156 functions the union files handle (md5 of the text now), and the two stale overloads
select v.fn, to_regprocedure(v.fn) is not null as present,
       case when to_regprocedure(v.fn) is null then null else md5(rtrim(pg_get_functiondef(to_regprocedure(v.fn)), E'\n')) end as md5_now
from (values
  ('public._acct_all()'),
  ('public._acct_docs(date)'),
  ('public._acct_inv_split72(text[],text,text[],integer)'),
  ('public._all_locs()'),
  ('public._backup_tables()'),
  ('public._c78_rows(date,date)'),
  ('public._cogs_lines72(date,date,integer[])'),
  ('public._conv_cost(uuid,integer,numeric,numeric,date,text)'),
  ('public._cs_push_pools(bigint)'),
  ('public._cust_bal(uuid)'),
  ('public._daybook_lines(integer[],integer[],date,date)'),
  ('public._elp_post_line(entries,integer,text,jsonb)'),
  ('public._entries_countseal_guard23()'),
  ('public._inb_insert_message(jsonb)'),
  ('public._inb_pii_cols76()'),
  ('public._intake_fail(text,integer,text,text,jsonb,text)'),
  ('public._item_base(uuid)'),
  ('public._item_flags_apply(uuid,jsonb)'),
  ('public._item_link(uuid,text,text,boolean)'),
  ('public._item_master_classify(jsonb)'),
  ('public._ledger_item_guard()'),
  ('public._notif_ok(uuid,text,integer)'),
  ('public._oo_short77(uuid)'),
  ('public._p27_pl(date,date,integer[])'),
  ('public._post_purchase_p13(uuid,jsonb)'),
  ('public._qc_latest60(text,uuid)'),
  ('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)'),
  ('public._recipe_approved_guard()'),
  ('public._recipe_frozen()'),
  ('public._recipe_gate73(uuid)'),
  ('public._recipe_lines_ok(uuid,jsonb)'),
  ('public._recipe_need(uuid,numeric,integer)'),
  ('public._recipe_set_artisan(uuid,integer,text)'),
  ('public._rv_log(uuid,text,jsonb,text,uuid)'),
  ('public._sale_stock_out()'),
  ('public._stock_guard(uuid,integer,text,date)'),
  ('public._sup_balance(uuid)'),
  ('public._void_purchase_p13(uuid,text)'),
  ('public._wastage_post(uuid,integer,numeric,text,text,text,bigint,uuid,uuid,text)'),
  ('public.acct_account_save(bigint,text,text,text,text,bigint,boolean,integer,boolean)'),
  ('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)'),
  ('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)'),
  ('public.acct_mapping_set(text,bigint)'),
  ('public.acct_opening(jsonb,boolean,text,uuid,boolean)'),
  ('public.acct_post_pending(boolean,integer)'),
  ('public.acct_status()'),
  ('public.artisan_list(boolean)'),
  ('public.assistant_health()'),
  ('public.bank_recon_candidates(bigint,integer)'),
  ('public.bank_recon_lines(bigint,text,integer)'),
  ('public.bank_recon_match(bigint,bigint,integer,text)'),
  ('public.bank_recon_match_many(jsonb,boolean)'),
  ('public.bank_recon_report(bigint,date,date)'),
  ('public.bank_recon_suggest(bigint,date,date,integer)'),
  ('public.bank_recon_unmatch(bigint,text)'),
  ('public.bank_stmt_import(bigint,jsonb,uuid,boolean)'),
  ('public.biz_items(date,date,integer)'),
  ('public.blind_active(text,integer)'),
  ('public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)'),
  ('public.control_counts()'),
  ('public.cost_attrib_main_set(integer,date,text,uuid)'),
  ('public.cost_rule_approve(bigint,text)'),
  ('public.cost_source_set_active(bigint,boolean,text)'),
  ('public.count_lines_seal(uuid)'),
  ('public.count_unsubmitted_scan()'),
  ('public.customer_advances()'),
  ('public.customer_balance(uuid)'),
  ('public.customer_directory(integer)'),
  ('public.customer_dues()'),
  ('public.customer_ledger(uuid)'),
  ('public.customer_points_adjust(uuid,integer,text,uuid)'),
  ('public.customer_points_redeem(uuid,integer,text,uuid,boolean)'),
  ('public.customer_pos_info(text)'),
  ('public.customer_profile(uuid)'),
  ('public.customer_save(uuid,jsonb,uuid)'),
  ('public.customer_set_tier(uuid,bigint,text,boolean)'),
  ('public.decide_emergency(bigint,boolean,text)'),
  ('public.dup_suspects(date,date)'),
  ('public.fa_register(date)'),
  ('public.fa_schedule(uuid)'),
  ('public.gift_claim(uuid,uuid,bigint,text,uuid)'),
  ('public.gift_issue(uuid,text,text,numeric,date,text,uuid)'),
  ('public.gifts_due(uuid)'),
  ('public.has_grant(text,integer)'),
  ('public.inbox_board(integer)'),
  ('public.inbox_get(bigint)'),
  ('public.inbox_list(integer,text,integer)'),
  ('public.intake_failures_list(text,integer)'),
  ('public.inventory_vs_gl(date,integer)'),
  ('public.item_apply(uuid,jsonb,text)'),
  ('public.item_dup_check(text,text,uuid)'),
  ('public.item_map_accept_confident(boolean)'),
  ('public.item_map_decide2(uuid,text,text,text,boolean)'),
  ('public.item_mapping_decide(uuid,text,text,text,boolean)'),
  ('public.item_master_import_apply(jsonb,text,integer)'),
  ('public.item_new(jsonb,text)'),
  ('public.items_with_cost()'),
  ('public.location_save(integer,jsonb)'),
  ('public.lock_check(date)'),
  ('public.login_failed(text)'),
  ('public.loyalty_award(uuid)'),
  ('public.notify_cancel(bigint)'),
  ('public.notify_enqueue(uuid,uuid,text,text,jsonb,text,text,text)'),
  ('public.notify_optin_set(uuid,text,boolean,text,text)'),
  ('public.notify_outbox_summary()'),
  ('public.online_order_get(uuid)'),
  ('public.online_order_save(uuid,uuid,integer,text,text,text,text,jsonb,text,text,date,numeric,numeric,numeric,text,text,text)'),
  ('public.online_orders_list(integer,text,date,date,integer)'),
  ('public.packaging_set(uuid,uuid,numeric,text,boolean,text)'),
  ('public.partner_calculate(bigint,date,date,jsonb)'),
  ('public.partner_settlement_save(bigint,date,date,jsonb,text,uuid)'),
  ('public.path_cfg(text,integer)'),
  ('public.pay_supplier(uuid,integer,jsonb,uuid,text)'),
  ('public.payment_intent_link(bigint,bigint)'),
  ('public.pool_set(integer,date,text,numeric,text,boolean,text,uuid)'),
  ('public.production_can_make(integer)'),
  ('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)'),
  ('public.production_preview(integer,uuid,numeric)'),
  ('public.production_run_costs(integer,date,date)'),
  ('public.production_void(uuid,text)'),
  ('public.profit_source_check(date,date,integer)'),
  ('public.purchase_get(uuid)'),
  ('public.recipe_approve(uuid,text)'),
  ('public.recipe_book(integer,boolean,integer)'),
  ('public.recipe_copy(uuid,uuid,boolean,uuid)'),
  ('public.recipe_cost(uuid,integer)'),
  ('public.recipe_cost_component_set(uuid,text,text,numeric,numeric,text,text,uuid)'),
  ('public.recipe_save(uuid,uuid,numeric,text,text,jsonb,uuid,boolean)'),
  ('public.recipe_steps_save(uuid,jsonb,uuid)'),
  ('public.recipe_yield_suggestion(uuid)'),
  ('public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)'),
  ('public.rollout_mode(text,integer)'),
  ('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)'),
  ('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)'),
  ('public.sales_channel_save(integer,text,text,text,text,integer,text,text,boolean)'),
  ('public.save_purchase(uuid,uuid,uuid,integer,text,date,jsonb,numeric,text,text,text,uuid,text)'),
  ('public.save_supplier(uuid,jsonb)'),
  ('public.sheet_sync_all()'),
  ('public.shelf_life_for(uuid,date)'),
  ('public.stock_blind_active(text,integer)'),
  ('public.stock_count_adjust(uuid,integer,numeric,text,text,uuid)'),
  ('public.stock_opening(uuid,integer,numeric,numeric,text,text,uuid)'),
  ('public.stock_post(uuid,integer,numeric,text,text,text,numeric,bigint,timestamp with time zone,text,bigint,text,uuid,uuid)'),
  ('public.stock_receive_transfer(uuid,numeric,text)'),
  ('public.stock_receive_transfer(uuid,numeric,text,numeric,text)'),
  ('public.stock_reconcile(boolean)'),
  ('public.stock_transfer(integer,integer,uuid,numeric,text,text,uuid)'),
  ('public.supplier_pick()'),
  ('public.supplier_refund(uuid,integer,numeric,text,text,text,text,text,uuid)'),
  ('public.template_for(text,integer)'),
  ('public.unit_factor(uuid,text,text)'),
  ('public.urgent_alerts(timestamp with time zone)'),
  ('public.void_supplier_payment(bigint,text)'),
  ('public.void_supplier_refund(bigint,text)'),
  ('public.wastage_decide(uuid,boolean,text)'),
  ('public.year_close_list()')
) v(fn)
union all
select 'STALE ' || p.oid::regprocedure::text, true, null from pg_proc p
 where p.pronamespace = 'public'::regnamespace and p.proname in ('inbound_message_receive', 'web_order_submit', 'acct_journal_post')
order by 1;
```

(`md5_now` of the merged text is what `phase539.sql` records; if you want to know in advance, send the A8 result and the agent compares it with the known texts.)

## 4. Step 1 to 3: backup, paste, check

1. Backup: Home > Backup, keep the file outside the phone. Restore it once into a spare project if you can (`docs/GO_LIVE.md` section 1).
2. Open `setup-all.html` (made by `tools/build_paste_parts.py`) section B, or paste the files by hand, in this order, one at a time, waiting for Success:
   `delta01.sql` (phases 499, 501-505, 529-533 as they fit) then `delta02.sql`. The first lines of each part name the phases it holds. Order inside: `phase499, 501, 502, 503, 504, 505, 529, 530, 531, 532, 533, 534, 535, 536, 537, 538, 539`.
   If the probe A7 says a phase of 499-505 is already in, you may skip it, or paste it again (safe).
3. After the last part:
   ```sql
   select * from public._i2_state() where not present;                 -- must return no rows
   select state, count(*) from public._union_audit() group by 1;       -- must show only: merged | 156
   select id, fn, saved_at, why from public._union_fn_backup order by id;   -- what was replaced, and when
   ```
   A union file prints a notice `phaseNNN: N function(s) changed`. A second run prints 0.

## 5. If a file stops with "unknown text"

Copy the whole message and send it. Do not paste the next file. Nothing was changed by that file, but the earlier files of the list stay applied (each is complete on its own). The agent will add the md5 of your text as a new known state (a new phase file, never an edit of an old one) or write a patch for it.

## 6. Rollback

Every replaced text is in `public._union_fn_backup` (`def` = the full `create or replace function` text). To put one back (example, id 7), as the owner in the SQL editor: `do $$ begin execute (select def from public._union_fn_backup where id = 7); end $$;` Then paste the union files again only after the agent has looked at why.

## 7. Evidence from the simulation (all on local throwaway PostgreSQL 16, nothing live)

- The chain "advanced block, then our whole line from phase 8 (the live order), then the two hand fixes" was built locally. It ends with 156 functions that differ from a fresh merged build and with the two stale overloads (the same ambiguity as the audit's `acct_journal_post`).
- Pasting the delta list (499, 501-505, 529-539) on that database gives **0 differences in 2,891 function texts** compared with the fresh merged build, `_i2_state` empty, `_union_audit` = 156 merged, and a second paste changes nothing (no new backup row).
- Structure (tables, columns, constraints, indexes, triggers, policies, views, rules): the only differences between the simulated live database and the fresh build were the objects of phases 499 and 501-505, which the delta pastes.
- Limit: the real live database may hold hand fixes the simulation does not know (the audit names `fix_lock_check.sql`, the `biz_items` fix and `_fix_fn_backup`). The simulation reproduced both of them. Any other hand fix shows up as UNKNOWN (section 5), never as a silent overwrite.

## 8. Decisions recorded (the owner asked the agent to decide)

- **One chain, advanced block first.** It is the order the live database received; the other order fails by design (advanced phases refuse bodies with tags they do not know).
- **Same feature twice: the advanced one is canonical, ours is kept OFF.** Customer due net of advance: advanced `dues_net_advance` / `customer_dues_net113`; ours `dues_net_advance_on` (503) is kept in `customer_dues`, OFF. Returns in the item analysis: advanced `items_net_of_returns` (bos112); ours `biz_items_net_returns` (502) does nothing while the advanced one is on (no double take-off). Unknown unit on a sale: advanced `unit_conv_required` (bos82) plus ours `stock_unit_unknown_block` (501) checked first, both OFF. Return at the sale's factor: both `return_uses_sale_rows` (bos114) and `return_sale_factor_on` (501). Intermediate product as ingredient: either `semi_finished_ingredient116` or `recipe_intermediate_on` (504) allows it; both loop checks run. Transfer short: advanced `transit_short_mode = loss` (bos83) is counted on what is still missing after our partial receipts (499). Cost basis: advanced ONE report cost source (bos88/bos110) by default; our `reports_cost_basis = ledger_first` (bos402) keeps our join. Never turn on two switches that do the same job.
- **Period lock for the owner:** our `owner_closed_period_mode` (off | log | reason, bos89) and the advanced `period_lock_owner_mode` (off | warn, bos113) both exist; ours decides first; the advanced warn line is written after our check allowed the date. Both default off.
- **Account codes:** the advanced line uses 1240 and maps `transit_loss` to 5130; our carrier receivable is created as 1245 when 1240 is taken, and our `transit_loss` mapping keeps the advanced account. Journal entries still balance (Dr = Cr).
- **`acct_journal_post`:** two real functions (7 and 8 arguments, no parameter default on the 8-argument one), same guard (`manual_journal_guard`, OFF) and same journal gate in both.
- **Tag collision:** both lines used the markers `bos80` to `bos99`, `bos120`, `bos131`, `bos132` for different work. No file was edited for this; the union files compare function texts by md5, not by tag.

## 9. Phase 543: printed form codes (owner decision, 21 Oct 2026, final)

**An agent never writes to the live project. The owner pastes this file himself.**

- **File:** `supabase/phase543.sql`, paste **once, after phase 539** (the last file of section 1 above). It is also safe to paste twice: a second paste finds `public.form_code_migration_543` and changes nothing. Test file: `supabase/phase543_test.sql` (local throwaway database only; never paste it into the live project).
- **What changes:** the 41 printed forms get the codes `NN-1` (sorted A-Z by the English short name; mapping in `docs/FORM_SEQUENCE.md` section 4). `0-1` (Location Settings) keeps its code. Stored data: `forms.code` and `forms.sort`, `form_code` in 20 tables (for example `entries`, `serials`, `role_form_perms`, `form_rollout`), label text in `rules`, `path_domains`, `report_defs3`, `list_defs`, `money_event_settings`, `acct_mappings`, `setup_rec_defs81`. Stored code: the 132 function texts that name a code, 4 trigger conditions, one check constraint, one row policy (the function text keeps its name and signature).
- **Not changed:** `audit_log` and `_union_fn_backup` (history); the non-printed codes `POS`, `ITEMS`, `ITEM_COST`, `ONLINE_INTAKE`; free text typed by people. The phase prints a notice for every column that still names an old code, with the row count, so the owner can decide.
- **Refusal before any change:** a row with a printed code the map does not know, or a map that does not match the database, stops the phase with a message that lists them. Nothing is written in that case (one transaction).
- **Order with the web app:** the web build in this repository uses the NEW codes. Paste phase 543 **before** the new web build is put on the live site, and do not put the new build on the site before the paste. Until then the old site and the old codes belong together.
- **Retired numbers:** phases 540 to 542 are old numbers (renamed to 491 to 493); phase 543 is the next free number. Do not paste any old phase file after phase 543: an old file carries the old codes (`docs/FORM_SEQUENCE.md` section 3).
- **Steps:** 1. backup (Home > Backup). 2. paste `supabase/phase543.sql` in one run (the file has its own `begin` and `commit`). 3. run `select * from public._i2_state() where not present;` (must return no rows). 4. run `select * from public.form_code_migration_543;` (one row, tag `FORM-CODE-CLEAN-SEQUENCE-543`). 5. check a printed form in the app (for example the expense voucher is now `11-1`).
- **Rollback:** the phase is one transaction; a failure undoes all of it. After a successful paste, a rollback means restoring the backup from step 1.

## Phase 545 (21 Oct 2026): freight in the purchase price check (switch OFF)

- **What it adds:** one rule row (`price_check_include_freight`, switch, default OFF), one check function (`purchase_price_check_freight545`), one helper, and one trigger on `landed_costs` (after status becomes posted). No existing function is redefined.
- **Effect today:** none. With the switch OFF the trigger returns at once; the local fingerprint of the scenario is the same with and without phase 545.
- **Steps (owner):** 1. backup (Home > Backup). 2. paste `supabase/phase545.sql` once in the SQL editor (it is paste-twice safe). 3. run `select * from public._i2_state() where not present;` (must return no rows). 4. leave the switch OFF, or switch it on in Rules after your own test.
- **Rollback:** `drop trigger landed_costs_price_freight545 on public.landed_costs;` and `delete from public.rules where key = 'price_check_include_freight';` (no data is changed by the phase itself).

## Phase 546: `stock_transfer` carries all four switch behaviours again (switches stay OFF)

- **Why:** phase 544 re-created `stock_transfer` from the phase 499 text and so dropped the "a transfer needs stock" check (rule `transfer_needs_stock`, bos114) and the "tell the receiving place" notice (rule `transfer_notify_receiver`, bos115) that phases 114, 115 and 533 had put in. A normal paste order (544 after 533) ended with the weaker function. Both rules are OFF, so staff saw no change; the owner could not switch them on and get the behaviour.
- **What it does:** re-creates only `stock_transfer(integer,integer,uuid,numeric,text,text,uuid)`: the phase 544 text plus the two missing blocks, exactly as phase 533 has them. No new rule, table, column, privilege or data. With every switch OFF the function behaves as before (same answers, same stock, no notice).
- **Steps (owner):** 1. backup (Home > Backup). 2. paste `supabase/phase546.sql` once in the SQL editor, after phase 545 (it is paste-twice safe). 3. run `select * from public._i2_state() where not present;` (must return no rows). 4. leave the switches OFF, or switch them on in Rules after your own test.
- **Rollback:** paste `supabase/phase544.sql` again (it re-creates the previous function text). No data is changed by phase 546 itself.
