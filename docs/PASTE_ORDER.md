# PASTE ORDER: the Supabase SQL files, in order (merged version: the advanced line and our line in ONE chain)

This is the owner's list of every phase file that builds the database, in the order to paste them. One line per file. **Two lines of work were joined**: the "advanced line" (phases 72 to 135, with the owner word list, Liquid Glass, places, organization ...) and "our line" (phases 80 to 505: money controls, reports, CRM, X-packages, sweets fixes). Where both used the same number for different work, the advanced line's file was renamed to 506 to 528 (table below); its text is unchanged.

**Read first.** Nothing in this list was pasted by an agent. The owner pastes the SQL himself, after review, into the project (CLAUDE.md, Database safety). Everything new starts OFF or blank: pasting a file adds tables, functions and settings, but no feature changes behaviour until the owner switches it on or its effective-from date arrives.

**Two cases, two lists.**
- **A NEW (empty) project:** paste section A, then section B top to bottom. The same list is `tests/sql/ORDER.txt`; the ready-made parts (at most 500 KB each) are `docs/paste_parts/part01.sql ...` (made by `tools/build_paste_parts.py`, copy page `docs/paste_parts/setup-all.html`).
- **The owner's CURRENT live project** (the advanced phases 72 to 135 and the earlier 13 parts of our line are already in): do NOT paste this list. Use `docs/LIVE_DELTA.md` (a read-only probe first, then only phases 499, 501 to 505 and 529 to 539, parts `docs/paste_parts/delta01.sql ...`).

## The chain in one picture

1. Base: `schema.sql`, `phase2/3/4.sql`, `ALL_NEW.sql`, then phases 8 to 71 (section A), then 72 to 79 (shared by both lines, identical text).
2. The advanced block: phases 506 to 525 (in the advanced line's own order: 506 507 508 509 510 511 512 513 514 516 517 515 518 519 521 520 522 523 524 525), 100 to 118, 526, 121 to 129, 527, 528, 133 to 135.
3. **phase529** (shim): puts the phase 6 text of `lock_check` and the 7-argument `acct_journal_post` back, so our exact-text hooks can be applied on top of the advanced block.
4. Our line: 80 to 99, 120, 130 to 132, 140 to 143, 300 to 329, 400 to 476, **477** (re-patches every package hook), **478** (helper functions closed to anon), 479 to 505.
5. **phase530 to 539**: the two lines' logic put back together in 17 functions, the advanced logic put back in 139 shared functions where an early repaste resets it, the two stale overloads dropped, and `public._union_audit()`.

This order is what the live database received (advanced block on Oct 14-15, our line on Oct 18) plus the shim and the union phases. Any other order is untested. The order "our line first, then the advanced block" fails by design: the advanced phases refuse a function body that carries a tag they do not know.

## Renumbering of the advanced line (same text, new file names)

The live database holds these advanced files under their ORIGINAL numbers. They are listed here only for a new project; **never paste 100 to 135 or 506 to 528 into the live project**.

| advanced original | file in this repository | content (short) |
|---|---|---|
| phase80 | phase506 | free-cost flag, intake bot |
| phase81 | phase507 | setup recommendations |
| phase82 | phase508 | stock guards |
| phase83 | phase509 | form vs screen, transit, offline POS |
| phase84 | phase510 | audit trail |
| phase85 | phase511 | stock moves to the GL, card settlement |
| phase86 | phase512 | Telegram channel |
| phase87 | phase513 | QA fixes, owner can approve |
| phase88 | phase514 | one report cost source |
| phase89 | phase515 | final bodies of re-created functions |
| phase90 | phase516 | scan a bill |
| phase91 | phase517 | who sees what |
| phase92 | phase518 | invoice on screen, share |
| phase93 | phase519 | print and message templates |
| phase94 | phase520 | security review fixes |
| phase95 | phase521 | cash drawer |
| phase96 | phase522 | opening stock, cost waiting |
| phase97 | phase523 | landed cost |
| phase98 | phase524 | `_acct_docs` merge |
| phase99 | phase525 | bill payment options, inbox masking |
| phase120 | phase526 | report speed |
| phase131 | phase527 | verified reports stage 1 |
| phase132 | phase528 | master data separation |

Their test files follow (`phaseN_test.sql` and the `b`/`c`/... variants); `phase130_integration_test.sql` is a test only. Phases 100 to 118, 121 to 129 and 133 to 135 kept their numbers.

## Numbering of phases 479 to 498: read this

Phases 479 to 498 (the X-packages X1 to XC, the XB package and the RPT, CRM and XC work in that range) were numbered by **several builders working in parallel**. The numbers were picked to avoid clashes, not to show the build or the dependency order. So a higher number does not mean "built later", and two neighbouring numbers may not depend on each other at all.

The positions below follow the numbers, which is the order `tests/sql/ORDER.txt` uses. Each file's header lists what it needs. If a file's header says it needs another phase, paste that phase first, even if its number is higher.

## Renumbered earlier: the parallel-builder phases -> 479-498 (our line, before the merge)

The parallel-builder files were renumbered in paste order so the sequence continues after phase 478. No SQL body changed; only file names, references in text files and the header comments that named their own file. Old name -> new name, with `_test` files following their main file:

| Old number | New number |
|---|---|
| 480 | 479 |
| 481 | 480 |
| 490 | 481 |
| 491 | 482 |
| 500 | 483 |
| 510 | 484 |
| 511 | 485 |
| 520 | 486 |
| 530 | 487 |
| 531 | 488 |
| 532 | 489 |
| 533 | 490 |
| 540 | 491 |
| 541 | 492 |
| 542 | 493 |
| 550 | 494 |
| 551 | 495 |
| 552 | 496 |
| 553 | 497 |
| 554 | 498 |

## Phases 491 to 493 (XB): now in `tests/sql/ORDER.txt`

Phases 491, 492 and 493 say "Run AFTER phase 478" in their headers. They are now listed in `tests/sql/ORDER.txt`, after 490 and before 494, so the build scripts build them. They sit at their numeric position (after 490, before 494). Build the local database once before the owner pastes them.

## phase481.sql has no `_test` file

There is no test for 481 of its own: `supabase/phase481_test.sql` does not exist on purpose. The X2 checks for phase481 are in `supabase/phase482_test.sql`, which is run on a fresh copy with 481 and 482 pasted twice.

## Never paste these

- `supabase/phase84_test_project_only.sql`, `supabase/phase84b_*` and `supabase/phase84c_*`: they are for TEST projects only and some of them wipe data. Never paste them into the live project.
- Any `*_test.sql` file: tests, not schema.
- `ALL_NEW*.sql` (except `ALL_NEW.sql` in section A): full bundles for a brand-new empty project only (see `docs/SETUP.md`). Do not mix them with this list.
- `phase14_import*` and `phase30_controls*`: data and UI helper files, not schema phases.

## Paste steps (short)

1. Take a backup (Home > Backup) and restore it once into a test project (see `docs/GO_LIVE.md`).
2. Paste the files in the order of section B, one at a time, into the Supabase SQL editor (or the ready-made parts). Each file is safe to paste twice (the headers say so).
3. If a file stops with a red error, stop, copy the message and do not paste the next file. The union files 529 to 539 list ALL problems in ONE message and change nothing in that case.
4. After the last file run: `select * from public._i2_state() where not present;` It must return no rows. Then `select state, count(*) from public._union_audit() group by 1;` It must show only `merged` (156).

## A. Foundation

`schema.sql`, `phase2.sql`, `phase3.sql`, `phase4.sql`, `ALL_NEW.sql`, then
`phase8 phase9 phase10 phase11 phase12 phase13 phase14 phase15 phase16 phase17 phase18 phase19 phase20 phase21 phase22 phase23 phase24 phase25 phase26 phase27 phase28 phase40 phase41 phase42 phase43 phase44 phase45 phase46 phase47 phase48 phase49 phase50 phase51 phase52 phase53 phase54 phase60 phase61 phase62 phase70 phase71`
(exactly `FOUNDATION` in `tests/sql/paste_order.env`; `tests/sql/build_fresh_db.sh` builds the same).

## B. The list (strictly in this order, each once)

Columns: # = paste position (1 = the first file after the foundation), file, line (`shared` = identical in both lines, `adv` = advanced line, `ours` = our line, `union` = the merge phases), package or origin, what it does or needs. Package names of our line: `base` = the product before the packages; W1-A to W1-G, I-1 = Wave 1 (phases 88 to 99); R1 = pay requests; R2-A to R2-C = announcements, to-do, shifts; W1-FIX = Wave 1 fixes (140 to 143); CRM-A to CRM-H = customer work; RPT-B1 to RPT-C3 and RPT-HUB = reports; integrator = the re-patch and the anon lock (477, 478); X1 to X6, XB and XC = the later packages (all OFF by default); SW = sweets fixes after phase 498 (499 and 501 to 505, all OFF; 500 is not used).

| # | file | line | package / origin | what it does |
|---|---|---|---|---|
| 1 | `phase72.sql` | ours | base | One COGS source for reports, balanced inventory lines, unknown-cost warnings |
| 2 | `phase73.sql` | ours | base | Recipe master: artisans, recipe versions with approval, steps, recipe book |
| 3 | `phase74.sql` | ours | base | Costing and overhead (conversion cost into product cost) |
| 4 | `phase75.sql` | ours | base | Cost sources and allocation (separate or shared bills) |
| 5 | `phase76.sql` | ours | base | Sales channels, message inbox, web order intake, Meta message intake (pull-in only) |
| 6 | `phase77.sql` | ours | base | Existing online-order gap fixes (audit a2-F6) |
| 7 | `phase78.sql` | ours | base | Showroom and admin cost attribution, approval separation hint |
| 8 | `phase79.sql` | ours | base | Integration: merged definitions of functions re-created by phases 72 to 78 |
| 9 | `phase506.sql` | adv | imported from advanced phase80 | needs: 72..79. guard inside |
| 10 | `phase507.sql` | adv | imported from advanced phase81 | needs: 72..79. guard inside (does not need 80) |
| 11 | `phase508.sql` | adv | imported from advanced phase82 | needs: 78. |
| 12 | `phase509.sql` | adv | imported from advanced phase83 | needs: foundation. |
| 13 | `phase510.sql` | adv | imported from advanced phase84 | needs: 78. |
| 14 | `phase511.sql` | adv | imported from advanced phase85 | needs: 72..79. guard inside |
| 15 | `phase512.sql` | adv | imported from advanced phase86 | needs: 76 (and 77..79). |
| 16 | `phase513.sql` | adv | imported from advanced phase87 | needs: 72..79, 82, 84. guard inside |
| 17 | `phase514.sql` | adv | imported from advanced phase88 | needs: 72..79, 82, 83, 84. guard inside |
| 18 | `phase516.sql` | adv | imported from advanced phase90 | needs: foundation .. 84. guard inside (lists the missing phases) |
| 19 | `phase517.sql` | adv | imported from advanced phase91 | needs: 86. guard inside (checks its tables) |
| 20 | `phase515.sql` | adv | imported from advanced phase89 | needs: 72..88, 90, 91. guard raises `phase89 needs phases 72..88, 90, 91 pasted first ... missing: <numbers>` if any is absent |
| 21 | `phase518.sql` | adv | imported from advanced phase92 | needs: 72..88. guard inside (invoice on screen) |
| 22 | `phase519.sql` | adv | imported from advanced phase93 | needs: base schema. guard inside (print templates) |
| 23 | `phase521.sql` | adv | imported from advanced phase95 | needs: base + 8. guard inside (cash drawer option) |
| 24 | `phase520.sql` | adv | imported from advanced phase94 | needs: 76, 80, 81, 85, 86, 89, 90, 92, 93. guard raises `phase94 needs phases 76, 80, 81, 85, 86, 89, 90, 92, 93 pasted first ...`. Security step (docs/briefs_p2p3/step_Sec_REPORT.md): re-creates 9 functions with the tag bos94 (none of them is in phase89's list) and gives `inbound_message_receive` / `web_order_submit` one extra defaulted argument. Do NOT paste phase76 again afterwards (it would bring back the old signatures next to the new ones). |
| 25 | `phase522.sql` | adv | imported from advanced phase96 | needs: 80, 85, 89. guard inside (needs `bos85` and `bos89` in `_acct_docs`; refuses a body with a tag it does not know). Opening-stock helper + cost waiting. Re-creates `_acct_docs`, `_acct_inv_split72`, `_acct_stock_moves85`, `_pvar85`, `inventory_vs_gl` |
| 26 | `phase523.sql` | adv | imported from advanced phase97 | needs: 72..88, 90, 91, 89. guard inside. Landed cost. Re-creates `_acct_docs` from the phase89 body + bos97 blocks, so on its own it ERASES every bos96 line |
| 27 | `phase524.sql` | adv | imported from advanced phase98 | needs: 72..97. guard inside (24 marker objects + `bos89`; raises `phase98 needs phases 72..97 pasted first ... missing: <numbers>`). Re-creates 5 functions only: `_acct_docs` = phase89 body + all bos96 lines + both bos97 blocks (tag bos98 on one comment line), and the 4 other phase96 functions byte-identical. Creates run only if both guards passed. No table, rule, data, privilege or trigger |
| 28 | `phase525.sql` | adv | imported from advanced phase99 | needs: 72..98. guard inside (one marker object per phase 72..97 + `bos89` + `bos98` in `_acct_docs`; raises `phase99 needs phases 72..98 pasted first ... missing: <numbers>`). Step Opt: two OPTIONS (bill payment, inbox masking), all default OFF. Re-creates 5 functions only (`inbox_list`, `inbox_get`, `online_orders_list`, `online_order_get`, `telegram_chat_info`, tag bos99) - none of them is touched by phase98, and phase99 does not touch `_acct_docs`. If a later phase re-creates one of the five, merge into the phase99 text. See docs/briefs_p2p3/step_Opt_REPORT.md |
| 29 | `phase100.sql` | adv | advanced line | needs: 72..97. guard inside (Step Cat: one category / sub-category master, rule `category_required_on_item`). Re-creates no existing function. See docs/briefs_p2p3/step_Cat_REPORT.md |
| 30 | `phase101.sql` | adv | advanced line | needs: 72..98. guard inside (Step Rec: setup advisor rows for every rule of phases 82..98; only `setup_rec_defs81` rows, ON CONFLICT DO NOTHING). See docs/briefs_p2p3/step_Rec_REPORT.md |
| 31 | `phase102.sql` | adv | advanced line | needs: item images; re-creates no accounting function. goes between 101 and 103; phase103 does not need it |
| 32 | `phase103.sql` | adv | advanced line | needs: 72..101. guard inside (one marker object per phase 72..99 + `bos98` in `_acct_docs` + `item_categories` (100) + the phase101 advisor row; raises `phase103 needs phases 72..101 pasted first ... missing: <numbers>`). Step E2E: defects D-1..D-8 of the independent end-to-end run. Re-creates 20 functions from their LATEST bodies (`_acct_docs`, `_acct_stock_moves85`, `inventory_vs_gl`, `_cw_docs96`, `_cw_rows96`, `_cw_posted96`, `_ob_rows96`, `_ob_plan96`, `opening_stock_apply96`, `recipe_cost`, `_setup_chk81`, `setup_recommendations`, `setup_recommend_apply`, `_inb_pii_f99`, `_inb_pii_json99`, `inbox_list`, `customer_directory`, `find_customer`, and `online_order_get` / `online_orders_list` byte-identical so one paste repairs a re-paste of phase89; every older bosNN tag kept, new tag bos103), adds 3 internal helpers, 1 switch `acct_manual_prod_in103` (default OFF), 1 flow check row, 1 grant def, 1 append-only table `opening_stock_followups103` + view `opening_covered103`. A body with a tag it does not know stops the paste. See docs/briefs_p2p3/step_E2E_REPORT.md |
| 33 | `phase104.sql` | adv | advanced line | needs: 72..103. guard inside (Step Dash). Owner dashboard layouts: table `dash_layouts` (RLS, a user sees only their own row), `dash_layout_get()`, `dash_layout_save()`, one audit trigger. Re-creates no existing function (tag bos104). |
| 34 | `phase105.sql` | adv | advanced line | needs: 72..103. guard inside (one marker object per phase 72..99, `item_categories` (100) and the phase103 advisor row `flw_grn_double103`, plus the phase99 / phase103 functions it re-creates; raises `phase105 needs phases 72..103 pasted first ... missing: <numbers>`; a body guard refuses to overwrite a body that carries a bosNN tag it does not know). Step Sec2: H1 customer phone / address bypass paths, M1 unmask race, M2 auto-payment limits, M3 keep_credit void, M6 phone regex, L3-L6. Re-creates 13 functions from their LATEST bodies (`_bp_uuid99`, `_bp_auto99`, `_bp_pay99`, `_bp_sp_void99`, `inbox_unmask`, `_inb_mask_phones103`, `_cust_pii103`, `customer_dues`, `customer_advances`, `customer_profile`, `customer_directory`, `customer_save`, `_inb_pii_cols76`; older bosNN tags kept, new tag bos105), adds `_bp_auto_ok105`, closed table `bos_salt105`, switch `customers_pii_guard_on` (default OFF). See docs/briefs_p2p3/step_Sec2_REPORT.md |
| 35 | `phase106.sql` | adv | advanced line | needs: 72..103. guard inside; backup / restore-drill coverage (section I). Re-creates only `_backup_tables()` and adds `backup_coverage106()`. |
| 36 | `phase107.sql` | adv | advanced line | needs: 72..103. guard inside; client error log (Step Errlog): 3 tables, 3 rules, 1 grant, 10 functions, all new. See docs/briefs_p2p3/step_Errlog_REPORT.md |
| 37 | `phase108.sql` | adv | advanced line | needs: 72..103. guard inside; Bangla label updates, UPDATE statements only (each fires only while the column still holds the old seed text); no table, column, function or privilege is changed. docs/i18n/BANGLA_REVIEW.md |
| 38 | `phase109.sql` | adv | advanced line | needs: 72..103. guard inside (marker objects 72..99 + `_rec_value103`; body guard refuses to overwrite a function that carries a bosNN tag it does not know). Step Conc: F1 `production_post` row-locks balances, F2 supplier lock `FOR NO KEY UPDATE` in 7 functions, F4 sorted bulk option views, F5 `setup_recommend_apply` one at a time, F6 rule `card_settle_over_mode` + advisor row. Re-creates 12 functions (tag bos109); since INT4 it leaves `_bp_pay99` alone when phase105 is already on it (phase111 merges it). See docs/briefs_p2p3/step_Conc_REPORT.md |
| 39 | `phase110.sql` | adv | advanced line | needs: 72..103. guard inside; performance: 8 indexes first (RUN AT A QUIET TIME), then 6 function patches (`_cogs_lines72`, `_item_cost_eff88`, `_rcs88`, `rpt_agg_sql`, `inbox_list`, `_acct_stock_moves85`; marker perf110). Results identical. See section M and docs/briefs_p2p3/step_Perf_REPORT.md |
| 40 | `phase111.sql` | adv | advanced line | needs: 72..109 (110 optional). guard inside (marker objects of 72..107 and 109; raises `phase111 needs phases 72..110 pasted first ... missing: <numbers>`; body guard refuses an unknown tag). Step INT4: 3-way merge of `_bp_pay99` (phase103 body + bos105 L4 line + bos109 supplier lock), tags bos105 + bos109 + bos111. Nothing else. See docs/briefs_p2p3/step_INT4_REPORT.md |
| 41 | `phase112.sql` | adv | advanced line | needs: 72..111. guard inside (marker objects + `card_settle_over_mode`; body guard refuses an unknown tag on `_c78_rows`, `_r3q_l3_shop_pnl`, `biz_items`). BATCH 1a "profit truth" (audit A3 G1..G9): one net profit for the shop P&L and the dashboard tile (`profit_truth112`), sheet / payroll-app salary without double count, wastage, card fees, shared bills pro rata by days, unallocated row, returns netted in `biz_items`. Rules `profit_truth_mode`, `cost_share_prorate_mode`, `items_net_of_returns` (all default off) + 3 advisor rows. Tag bos112. Test: `supabase/phase112_test.sql` |
| 42 | `phase113.sql` | adv | advanced line | needs: 72..111. guard inside (body guard on `_acct_docs`, `acct_post_pending`, `_daybook_lines`, `customer_dues`, `collect_payment`, `lock_check`). BATCH 1b "books truth" (audit A4 G01 G03 G04 G05 G08): drawer shortage posts to 5800, dues net of the advance used, closed-period owner / scheduler warnings, day book = journal for voucher mode and card fee, `bank_stmt_post113`. Rules `drawer_short_post`, `dues_net_advance`, `period_lock_owner_mode`, `period_lock_late_warn`, `daybook_align_mode`, `bank_stmt_post_on` (all default off) + 6 advisor rows + mapping `cash_short`. Tag bos113. Test: `supabase/phase113_test.sql` |
| 43 | `phase114.sql` | adv | advanced line | needs: 72..103. guard inside. BATCH 2 stock safety part 1 (audit2 A2): 7 switches, all default OFF (`late_sale_follows_block`, `transfer_needs_stock`, `return_uses_sale_rows`, `item_unit_change_needs_zero`, `item_lifecycle_needs_zero`, `batch_for_adjustments`, `batch_refill_cap`) + advisor rows (phase 114), `stock_batch_reconcile(p_fix)`, 2 triggers. Patches by exact-text insert (helper dropped at the end; older tags kept, stops with a message if the expected line is gone): `_sale_stock_out`, `stock_transfer`, `sale_return`, `stock_count_adjust`, `stock_opening` (tag bos114). Test: `supabase/phase114_test.sql`. |
| 44 | `phase115.sql` | adv | advanced line | needs: 72..103. guard inside. BATCH 2 part 2 (audit2 A5): 4 switches, default OFF (`transfer_late_receive`, `transfer_return_marker`, `transfer_notify_receiver`, `transit_loss_gl_fix`) + advisor rows (phase 115), columns `stock_transfers.kind/reason/ref_transfer_id`, `stock_receive_more`, `stock_return_transfer`. Patches: `stock_transfer` (notify, tag bos115), `_acct_stock_moves85` and `_acct_docs` (the synthetic +short transfer_in of `_transit_loss83` gets no leg; marker `b2s115`, deliberately NOT a bosNN tag, like perf110 / sec2-L6, so the body guards of phase98 / 103 / 110 do not refuse a re-paste). Independent of phase114. Test: `supabase/phase115_test.sql`. |
| 45 | `phase116.sql` | adv | advanced line | needs: 72..111. guard inside (marker objects 72..97, `opening_covered103`, `bos109` in `production_post`; body guard refuses a function that carries a tag it does not know). BATCH 3 (manufacturing cost engine): 7 switches all OFF, semi-finished goods as ingredients, packaging on actual yield, standard-vs-actual (`recipe_std116`, `production_variance116`), pool drivers, provisional conversion + `production_reprice116`, supplied cost reaches the average + `production_recost116`. Re-creates `_recipe_lines_ok`, `_recipe_need`, `production_post` (7 args), `_conv_cost`, `cost_wait_supply96`, `production_run_costs`, `production_void` (tag bos116). Test: `supabase/phase116_test.sql`. |
| 46 | `phase117.sql` | adv | advanced line | needs: 72..111, 116. guard inside. BATCH 3 (factory overhead in the books): `pool_gl_post117` (pool rows posted Dr expense / Cr 2400, reversed when retired) and `factory_labour_absorbed117` (branch P&L), both OFF; `pool_vs_gl117`, `overhead_trueup117`. Re-creates `pool_set`, `_cs_push_pools`, `_p27_pl` (tag bos117). Test: `supabase/phase117_test.sql`. |
| 47 | `phase118.sql` | adv | advanced line | needs: 72..103. guard inside (functions of 72 / 78 / 80 / 82 / 85 / 88 and the tables stock_ledger, stock_transfers, card_settlements85). Step B4: three READ-ONLY reconciliation reports (`stock_recon_statement`, `stock_sales_unmatched`, `factory_branch_statement`, `net_profit_report`) + `recon_export_log118`; grants `view_stock_recon`, `view_branch_statement`, `view_net_profit`; rules `profit_variable_heads`, `branch_stmt_ageing_hours` (+ 2 advisor rows). Tag bos118; no existing function is re-created. See section N |
| 48 | `phase526.sql` | adv | imported from advanced phase120 | needs: 118 (and 72..103). guard inside (the phase118 functions and `_base_qty`; a body guard refuses an unknown bosNN tag on the three functions it rewrites). Step C4 (performance of the phase112..118 reports): `CREATE OR REPLACE` of `_rc118_buckets`, `_rc118_gap`, `stock_sales_unmatched` only (same signature, same output, tag bos120 next to bos118); no index (two candidates measured, no gain). stock_recon_statement 2.1 s -> 0.5 s and factory_branch_statement 2.3 s -> 0.6 s for a month on the owner-size scratch DB. Re-paste rule: after a re-paste of phase118 paste phase120 again. Tests: `supabase/phase120_test.sql`, `tests/sql/perf/equality120.sh`. Placed after phase118 and before phase121 (integration C4: phase121 does not touch the three functions; verified with phase121_test on the merged chain). Re-paste of phase118 puts the older bodies back: paste phase120 again. |
| 49 | `phase121.sql` | adv | advanced line | needs: 72..118. guard inside. Security review fixes of 112..118 (marker `sec121`, deliberately not a bosNN tag): `customer_dues_net113` revoked from public / anon; `pool_set` and `_pool_gl_after_bill117` start the GL sync only for owner / accountant; `cost_wait_supply96` moves the item average only for owner / recipe manager / accountant (else `needs_manager`); `sale_return` sold quantity over all lines in base units; `bank_stmt_post113` duplicate lookup first; `stock_return_transfer` locks the original; `production_recost116` checks rights before the row lock. Exact-text patches of the live bodies, paste twice = no change, nothing changes at the defaults. Test: `supabase/phase121_test.sql` |
| 50 | `phase122.sql` | adv | advanced line | needs: base schema (no phase 72..121 function is touched). guard inside. GROUP ERP STAGE B1 (marker `org122`, not a bosNN tag; changes NO existing function): tables `org_units`, `legal_entities`, `business_templates` (RLS, audit, no hard delete, no browser write), nullable `locations.org_unit_id`, seed of one group + one legal entity + one business for the sweets business with the existing locations mapped (fill-null only), rule `org_scope_on` (default OFF, read by nothing), grant `org_manage`, functions `org_tree`, `org_unit_scope`, `org_unit_save`, `org_unit_deactivate`. Test: `phase122_test`; proof of no behaviour change: `tests/sql/b1_before_after.sh`. Plan: `docs/GROUP_ERP_STAGE_A.md` sections 10-11. |
| 51 | `phase123.sql` | adv | advanced line | needs: 122 (and the base schema; re-creates functions of phases 2, 7, 8, 10, 12, 40, 46, 53, 88, 95, 112). guard inside. GROUP ERP STAGE C1 first slice (marker `scope123`, not a bosNN tag; every bosNN tag of the re-created bodies is kept): business isolation behind the switch `org_scope_on` (default OFF = every function returns what it returned before, proved by `tests/sql/c1_before_after.sh`). New table `user_org_scopes` (user, unit, role; RLS, audit, no hard delete, no browser write), helpers `can_scope`, `business_of_location` (+ internal `_org_on123`, `_biz_ok123`, `_loc_vis123` ...), owner functions `org_scope_grant`, `org_scope_revoke`, `org_scope_list`, `org_scope_preflight`. Re-created with an OFF branch that is the old text verbatim: `can_loc`, `_all_locs`, `_acct_all`, `has_grant`, `_notif_ok`, `decide_emergency`, `staff_directory`, `customer_dues`, `customer_ledger`, `fa_register`, `fa_schedule`, `year_close_list`, `items_with_cost`, `item_cost_status88`, `drawer_report`, `profit_truth112`; restrictive read policies `*_scope123` on the location-bearing any-active tables (true while OFF); trigger `stock_transfers_biz123` (cross-business transfer). First paste only: today's `management` users get a management scope on the sweets business (marker in the SWEETS attrs, a revoked row is never revived). Test: `phase123_test`; plan and deferred list: `docs/HANDOVER_7.md`. |
| 52 | `phase124.sql` | adv | advanced line | needs: 122 (org_unit_scope, org_tree, org_units); not 123. guard inside. IMPORT-EXPORT basic module (marker `ie124`, changes NO existing function): tables `ie_currencies`, `ie_fx_rates` (append-only), `ie_shipments`, `ie_shipment_events` (append-only) - RLS on, no direct browser access, audit, no hard delete; each carries `org_unit_id` of an import_export business and every function checks it (owner = all, others = their locations' business + grant). Grants `impexp_view`, `impexp_manage`; rule `impexp_on` (default OFF, refuses writes); `business_templates` row `import_export` (needs_setup, modules list says built / not built; no GL posting). Functions `ie_businesses124`, `ie_currencies_list`, `currency_save`, `fx_rate_set`, `ie_fx_rates_list`, `shipment_save`, `shipment_set_status`, `shipments_list`, `shipment_events_list`, `shipment_cost_summary`, `shipments_by_currency`. Test: `phase124_test`. Registration lines: `docs/regs/impexp124.md`. |
| 53 | `phase125.sql` | adv | advanced line | needs: 122 (items, org_units; not 123/124). guard inside. VARIANT ITEM MODEL (marker `var125`, changes NO existing function): nullable `items.org_unit_id` (filled with the sweets business, fill-null only; a BEFORE INSERT trigger fills new items) + `style_id`, `variant_key`, `variant_opts`; NEW unique index `(org_unit_id, code)` while the global `items.code` unique constraint stays; tables `option_sets`, `option_values`, `item_styles`, `style_axes`, `price_lists`, `price_list_items` (RLS scoped to the caller's business, audit, no hard delete, no browser write); functions `option_set_save`, `option_values_save`, `style_save`, `variants_generate` (idempotent, EAN-13 per variant), `variants_overview`, `variant_matrix`, `my_businesses125`, `price_list_save`, `price_list_items_set`, `price_for125`; rule `variants_on` (switch, default OFF), grant `variants_manage`. `items_read` is replaced only while it is still the original any-active-user policy and only hides other businesses' items while the switch is ON. |
| 54 | `phase126.sql` | adv | advanced line | needs: 125. guard inside. LARGE CATALOGUE READINESS (marker `var126`, changes NO existing function): `items.brand`, btree prefix indexes and (when pg_trgm exists) trigram GIN indexes on the item names, `items_search(org, q, filters, limit, offset)` (server-side search + paging + summary counts, scoped by the caller's businesses, never returns cost), `items_search_info126()`. |
| 55 | `phase127.sql` | adv | advanced line | needs: phase122 (+ base schema and the customer / supplier ledgers). guard inside. DEALER BUSINESS part 1 (marker `dl127`, changes no existing function): cheque / PDC register `dealer_cheques` + append-only `dealer_cheque_events`, rule `dealer_cheque_on` (OFF), grants `dealer_cheque_view` / `dealer_cheque_manage`, shared scope helpers `_dl_*127` (business of a location, explicit-assignment check), functions `cheque_register / deposit / clear (p_dry preview) / bounce / cancel / replace / bank_candidates / bank_link / list / cheques_due / cheques_bounced / post_dated_exposure / cheque_ledger_check / cheque_events`. Only CLEAR writes the party ledger (one `sale_payments` row mode bank, or one `supplier_payments` row); `sale_payments.mode` check is widened to also allow `bank`. Test: `phase127_test`. Numbers after other agents' rows 123..126 land: this row moves, the order inside the NEW list stays ...126, 127, 128, 129. |
| 56 | `phase128.sql` | adv | advanced line | needs: 127 (+ purchase bills, sales). guard inside. DEALER BUSINESS part 2 (marker `dl128`): principal scheme engine: `dealer_schemes` (slab whole / marginal, target rebate, flat per pack; purchase or sale basis; period), `dealer_scheme_items`, `dealer_scheme_slabs`, append-only `dealer_scheme_accruals`, claim register `dealer_scheme_claims` + append-only `dealer_scheme_claim_events`, rule `dealer_scheme_on` (OFF), grants `dealer_scheme_view` / `dealer_scheme_manage`, functions `scheme_save / activate / accrue (p_dry preview) / close / cancel`, `claim_create / receive / reject / cancel`, `scheme_list / scheme_get / claim_list / scheme_reconciliation`. Nothing is posted to the books. Test: `phase128_test`. |
| 57 | `phase129.sql` | adv | advanced line | needs: 127 (+ stock_post, items). guard inside. DEALER BUSINESS part 3 (marker `dl129`): tinting: `dealer_shades`, versioned `dealer_tint_formulas` + append-only `dealer_tint_formula_lines`, `dealer_tint_jobs` + `dealer_tint_job_lines` (cost columns not readable by the browser role), rule `dealer_tint_on` (OFF), grants `dealer_tint_view / manage / run`, functions `tint_formula_save / retire / list / get`, `tint_job_run (p_dry preview) / void / list`, `tint_customer_shades`, `tint_job_cost`, `tint_cost_report`; consumes through the existing `stock_post` (issue_out, reversal on void). Also fills `business_templates.modules` of hardware_paint and dealership (built vs not built; status unchanged). Test: `phase129_test`. |
| 58 | `phase527.sql` | adv | imported from advanced phase131 | needs: 72 (journal, sales, stock_ledger), 118 (stock_recon_statement) and the report rights of phase9. guard inside. REPORTS STAGE 1, sweets business (marker `rpt131`, changes NO existing function): rule `rpt131_on` (default OFF) and the read-only reports `rpt131_sales` (net of voids and returns by day / week / month / outlet / hour / weekday / staff / sale type / payment method), `rpt131_sales_recon` (document register: posted / unposted / void / reversed / refunded and the tie-out to the journal), `rpt131_item_profit` (item / category / outlet profit with real ledger costs), `rpt131_stock_recon` (paged stock reconciliation), `rpt131_wastage` (by reason / item / outlet / day / status / document), `rpt131_cash_close` (cash book and day close), `rpt131_ageing` (receivable and payable ageing with the books tie-out), `rpt131_catalog`, `rpt131_log_export`. Existing report rights only; cost columns only for owner / rpt_cost_ok. Paste twice = no change. phase130 is a test-only file (no row). |
| 59 | `phase528.sql` | adv | imported from advanced phase132 | needs: 122, 123, 125 (+ the base schema; re-creates 93 existing functions by text patch, see N11). guard inside. GROUP ERP STAGE C2: MASTER DATA kept apart between businesses (marker `mstr132`, text-patch markers `/* m132 */` and `/* m132b:<table> */`, not bosNN tags; every bosNN tag of the patched bodies is kept). Registry `master_scope132` (54 rows = the 50 master tables of the C1 audit + 4 children: 34 scoped, 14 shared config, 4 place-scoped by phase123, 2 deferred), nullable `org_unit_id` on the 34 scoped tables (back-filled to the sweets business, fill-null-only), trigger `a132_scope` (fills a new row's business, refuses a write into / of another business while `org_scope_on` is ON), restrictive read policy `<table>_m132`, stock guard on `stock_ledger`, `master_shares132` (+ `master_share_create / revoke / list`, owner only, default none), `master_context_set132 / get132`, per-business unique indexes (`customers (org_unit_id, mobile)`, `items (org_unit_id, barcode)`), `org_masters_preflight`, `org_masters_relax_unique` / `org_masters_restore_unique` (owner only, reversible, logged in `master_unique_log132`), `master_scope_report132`. No rule is added; behaviour is unchanged while `org_scope_on` is OFF (tests/sql/c2_before_after.sh). Coverage: docs/audit_c1/C2_COVERAGE.md. Test: `supabase/phase132_test.sql` |
| 60 | `phase133.sql` | adv | advanced line | needs: 122, 123 (re-creates `rule_val`, `can_grant`, `can_do`, `has_grant` and patches 41 more functions by exact-text insert, see N12; phase132 is used when pasted, not required). guard inside. GROUP ERP STAGE C3: behaviour, permissions and reports kept apart between businesses behind `org_scope_on` (marker `scope133`, text-patch marker `/* scope133 */`; not a bosNN tag, every bosNN tag of the patched bodies is kept). New tables `rule_overrides` (business x rule key), `rule_grant_overrides133`, `role_form_overrides133`; nullable `roles.org_unit_id`, `grant_defs.org_unit_id`; `rule_val` / `rule_on` / `rule_num` / `rule_txt` answer with the business value of the caller's working business, `can_grant` / `has_grant` / `can_do` read the business role matrix; owner tools `rule_override_set133`, `rule_grant_override_set133`, `role_form_override_set133`, `role_scope_set133`, `grant_scope_set133`; readers `rule_val_in133`, `rules_effective133`, `rule_overrides_list133`, `role_matrix_list133`; border triggers `<table>_xb133` on every table with a place column (a user cannot write a row of a foreign business by any function); patched readers / writers of the books engine, the controls, the place-bound config lookups and `_cust_bal`; owner-only-while-ON gate on the company-level books records; storage helpers `photo_business133`, `photo_path133`, `photo_unmapped133` + restrictive storage policies; `daily_digest_biz133`; the coverage checker `scope_gaps133()` (reviewed list: `tests/sql/scope_allowlist.txt`, explained in `docs/audit_c1/C3_COVERAGE.md`). No rule is added; with the switch OFF nothing changes (`tests/sql/c3_before_after.sh`). Test: `supabase/phase133_test.sql` |
| 61 | `phase134.sql` | adv | advanced line | needs: 122, 123, 132, 133 (re-creates `org_tree`, `org_unit_scope`, `org_unit_save`, `org_unit_deactivate`, `org_scope_list`, `master_share_list`, `master_context_set132`, `_org_visible122`, `_ie_base124` and patches 3 more, see N13). guard inside. GROUP ERP STAGE D (marker `prof134`, text-patch marker `/* prof134 */`): ONE PROFILE PER BUSINESS and UPPER-LAYER BLINDNESS. Tables `business_profiles` (name bn/en, short name, logo path, address, phone, email, receipt header / footer, theme colour, trade licence reference not readable by the browser role), `business_profile_ops134` (idempotency keys); functions `business_profile_get / list134 / save`; helpers `_vis_biz134`, `_biz_mgr134`, `_unit_mgr134`, `_unit_vis134`, `_cur_biz134`, `_grp_owner134`; seed: a profile per business (sweets = 'ইসলামিয়া মিষ্টি ঘর' / 'ISLAMIYA MISTY GHAR'), the group unit renamed to 'MD-AL AMIN' only while it still holds the placeholder and only once; a non-owner sees only his own business subtree (the business is the root; no group, legal entity, sibling, count). No new rule, no new grant. Paste twice safe. |
| 62 | `phase135.sql` | adv | advanced line | needs: 16, 122, 123, 133, 134 (re-creates NOTHING; text-patches `location_save` once, see N14). guard inside. GROUP ERP STAGE D2 (marker `loc135`, text-patch marker `/* loc135 */`): the OPERATIONAL PLACES of a business created from the app and mapped to it. Table `business_place_ops135` (idempotency keys + append-only history of creates and moves); functions `business_place_create135` (owner, or the org_manage holder INSIDE that business: calls the existing `location_save`, maps the place to the business or to a branch inside it, starts it in `setting_up`, code = business prefix + code, name unique per business), `business_place_move135` (owner only, dry-run first, force for transactions, refuses people / open documents / supply links), `business_places_list135`, `business_profile_ensure135`; helpers `_pc_ok135`, `_pc_biz135`, `_pc_unit135`, `_place_impact135`. No new rule, no new grant. Paste twice safe. |
| 63 | `phase529.sql` | union | UNION-1 | Shim before our packages: puts the phase 6 text of lock_check and the 7-argument acct_journal_post back (and removes the parameter defaults of the 8-argument one) so our exact-text hooks can be applied. Saves what it replaces in `_union_fn_backup`. Does nothing on a database that has our hooks already. |
| 64 | `phase80.sql` | ours | base | One-step opening balance (stock, cash per place, wallets, dues, payables, capital) |
| 65 | `phase81.sql` | ours | base | Shortages: hub count cash short, customer advance check, transit short |
| 66 | `phase82.sql` | ours | base | Salary accrual, Monthly Close, partner profit-share posting |
| 67 | `phase83.sql` | ours | base | Separate wallets (bKash, Nagad, Rocket, others) and production materials |
| 68 | `phase84.sql` | ours | base | Balance check, read-only (safe for the live project) |
| 69 | `phase85.sql` | ours | base | Integration of phases 81, 82, 83 into the shared functions |
| 70 | `phase86.sql` | ours | base | Fixes after the independent check of phases 80 to 85 |
| 71 | `phase87.sql` | ours | base | Money accounts |
| 72 | `phase88.sql` | ours | W1-A | Opening dues and payables linked to customer and supplier sub-ledgers (W1-A) |
| 73 | `phase89.sql` | ours | W1-B | Period lock, back-date window, late offline sales held for the owner (W1-B) |
| 74 | `phase90.sql` | ours | W1-C | Staff exit revokes access (W1-C) |
| 75 | `phase91.sql` | ours | W1-C | Sale return control: window, class rule, expired-batch rule (W1-C) |
| 76 | `phase92.sql` | ours | W1-D | One profit number (W1-D) |
| 77 | `phase93.sql` | ours | W1-D | Report parity and dated brand map (W1-D) |
| 78 | `phase94.sql` | ours | W1-E | Cash and payment controls: supplier payment limit, duplicate guard (W1-E) |
| 79 | `phase95.sql` | ours | W1-E | Journal, chart and mapping controls, journal requests (W1-E) |
| 80 | `phase96.sql` | ours | W1-F | Chart and mapping completeness, expense heads, other income (W1-F) |
| 81 | `phase97.sql` | ours | W1-F | Customer receipt channels: bank, cheque, payment source on collections (W1-F) |
| 82 | `phase98.sql` | ours | W1-G | Journal freshness, switch-coupling warning, data-protection settings (W1-G) |
| 83 | `phase99.sql` | ours | I-1 (Wave 1 integration) | Wave 1 integration: applies the Wave 1 hooks in one call (I-1) |
| 84 | `phase120.sql` | ours | R1 | Pay requests: staff salary and advance, supplier payment, one approver (R1) |
| 85 | `phase130.sql` | ours | R2-A | Announcements from the owner (R2-A) |
| 86 | `phase131.sql` | ours | R2-B | To-do list with repeats (R2-B) |
| 87 | `phase132.sql` | ours | R2-C | Shift templates and weekly roster, record only (R2-C) |
| 88 | `phase140.sql` | ours | W1-FIX | A sale void follows the return rules (W1-FIX) |
| 89 | `phase141.sql` | ours | W1-FIX | Supplier payment limit counted over several days (W1-FIX) |
| 90 | `phase142.sql` | ours | W1-FIX | A staff exit cannot be undone by linking a login (W1-FIX) |
| 91 | `phase143.sql` | ours | W1-FIX | One re-patch call for the hooks of phases 140 to 142 (W1-FIX) |
| 92 | `phase300.sql` | ours | CRM-A | Customer profile plus: schema, settings, grants, helpers (CRM-A) |
| 93 | `phase301.sql` | ours | CRM-A | Customer profile plus: write functions (CRM-A) |
| 94 | `phase302.sql` | ours | CRM-A | Customer 360: read functions, timeline, upcoming dates, masked directory (CRM-A) |
| 95 | `phase303.sql` | ours | CRM-B | Consent per channel with evidence, do-not-contact list (CRM-B) |
| 96 | `phase304.sql` | ours | CRM-B | Privacy by role: phone numbers and lists, export control, log (CRM-B) |
| 97 | `phase305.sql` | ours | CRM-B | Possible duplicate customers, soft "same person" link (CRM-B) |
| 98 | `phase306.sql` | ours | CRM-C | Customer scores and RFM labels with the owner's cut-offs (CRM-C) |
| 99 | `phase307.sql` | ours | CRM-C | Customer lists (segments): rule builder, saved lists (CRM-C) |
| 100 | `phase308.sql` | ours | CRM-C | Customer value: repeat rate, lifetime value, lapsed and at-risk lists (CRM-C) |
| 101 | `phase316.sql` | ours | CRM-F | Loyalty extras part 1: points expiry, burn rules, manual adjustment alert (CRM-F) |
| 102 | `phase317.sql` | ours | CRM-F | Loyalty extras part 2: referral codes and rewards (CRM-F) |
| 103 | `phase318.sql` | ours | CRM-F | Loyalty extras part 3: coupons and vouchers (CRM-F) |
| 104 | `phase319.sql` | ours | CRM-F | Loyalty extras part 4: birthday and festival hooks, points statement (CRM-F) |
| 105 | `phase323.sql` | ours | CRM-G | Enquiry and lead pipeline, tasks: settings, rights, tables, guards (CRM-G, 1 of 5) |
| 106 | `phase324.sql` | ours | CRM-G | Leads: save, notes, assign, stage moves, lost and reopen with reason, quotes (CRM-G, 2 of 5) |
| 107 | `phase325.sql` | ours | CRM-G | Convert a won lead to an order or party form; pipeline board (CRM-G, 3 of 5) |
| 108 | `phase326.sql` | ours | CRM-G | Tasks: add, done, snooze, skip, reassign, my tasks (CRM-G, 4 of 5) |
| 109 | `phase327.sql` | ours | CRM-G | Status for the screens, settings overview, go-live checklist (CRM-G, 5 of 5) |
| 110 | `phase328.sql` | ours | CRM-H | Customer complaints with an SLA clock (CRM-H, 1 of 2) |
| 111 | `phase329.sql` | ours | CRM-H | Ratings, repeat-complaint list, complaints and ratings report (CRM-H, 2 of 2) |
| 112 | `phase400.sql` | ours | RPT-B1 | Returns and refund consistency in sales reports (RPT-B1) |
| 113 | `phase401.sql` | ours | RPT-B1 | "Data not captured" notices (RPT-B1) |
| 114 | `phase402.sql` | ours | RPT-B1 | One cost basis for item sales and business analysis (RPT-B1) |
| 115 | `phase403.sql` | ours | RPT-B1 | Three reports a sweets and bakery business needs (RPT-B1) |
| 116 | `phase404.sql` | ours | RPT-B4 | Production capture: tables and helpers (RPT-B4) |
| 117 | `phase405.sql` | ours | RPT-B4 | Production capture: entry functions (RPT-B4) |
| 118 | `phase406.sql` | ours | RPT-B4 | Plan vs actual, order status, production-to-dispatch reconciliation (RPT-B4) |
| 119 | `phase407.sql` | ours | RPT-B4 | Real consumption vs recipe, standard vs actual cost, price, usage and yield variance (RPT-B4) |
| 120 | `phase408.sql` | ours | RPT-B4 | Run-level yield vs standard, reject and loss, wastage with batch (RPT-B4) |
| 121 | `phase409.sql` | ours | RPT-B4 | Sales targets and daily KPI snapshots: tables, settings, target entry (RPT-B4) |
| 122 | `phase410.sql` | ours | RPT-B4 | Target vs achievement, KPI trends, exception alerts (RPT-B4) |
| 123 | `phase411.sql` | ours | RPT-B4 | Outlet target tile for the owner board (RPT-B4) |
| 124 | `phase412.sql` | ours | RPT-B4 | Rated capacity, production lines and labour hours per run (RPT-B4) |
| 125 | `phase413.sql` | ours | RPT-B4 | Output per labour hour and capacity utilization (RPT-B4) |
| 126 | `phase415.sql` | ours | RPT-B4 | Owner setting for the value of goods moved between units (RPT-B4) |
| 127 | `phase416.sql` | ours | RPT-B4 | Factory vs retail report and audit line for the CSV of new reports (RPT-B4) |
| 128 | `phase420.sql` | ours | RPT-B2 | Honesty fixes in the existing stock and purchase reports (RPT-B2) |
| 129 | `phase421.sql` | ours | RPT-B2 | Stock movement reports on engine 3 (RPT-B2) |
| 130 | `phase422.sql` | ours | RPT-B2 | Stock movement ledger of one item at one place (RPT-B2) |
| 131 | `phase423.sql` | ours | RPT-B2 | Stock reconciliation and integrity, read-only (RPT-B2) |
| 132 | `phase424.sql` | ours | RPT-B2 | Batches and freshness, read-only (RPT-B2) |
| 133 | `phase425.sql` | ours | RPT-B2 | Where each production batch went, read-only (RPT-B2) |
| 134 | `phase430.sql` | ours | RPT-B3 | Supplier lot and expiry captured at raw receipt (RPT-B3) |
| 135 | `phase431.sql` | ours | RPT-B3 | Traceability and recall (RPT-B3) |
| 136 | `phase432.sql` | ours | RPT-B3 | Quality check by item, quantity and supplier; damaged quantity on transfer (RPT-B3) |
| 137 | `phase433.sql` | ours | RPT-B3 | Stockout log, shelf-life-not-set notice, actual yield report (RPT-B3) |
| 138 | `phase434.sql` | ours | RPT-B3 | Price trend with value, agreed price per item and supplier (RPT-B3) |
| 139 | `phase435.sql` | ours | RPT-B3 | Purchasing reports: supplier returns, adjustments, agreed-price variance (RPT-B3) |
| 140 | `phase436.sql` | ours | RPT-B3 | Audit line for the CSV export of the new reports (RPT-B3) |
| 141 | `phase440.sql` | ours | RPT-C1 | Report honesty part 1: null-safe totals, profit completeness (RPT-C1) |
| 142 | `phase441.sql` | ours | RPT-C1 | Report honesty part 2 (RPT-C1) |
| 143 | `phase442.sql` | ours | RPT-C1 | Expense register (RPT-C1) |
| 144 | `phase443.sql` | ours | RPT-C1 | Statements part 1: account classes, P&L by month and outlet (RPT-C1) |
| 145 | `phase444.sql` | ours | RPT-C1 | Statements part 2: cash-flow statement, working capital (RPT-C1) |
| 146 | `phase445.sql` | ours | RPT-C2 | Order capture part 1: cake specification and promised time slot (RPT-C2) |
| 147 | `phase446.sql` | ours | RPT-C2 | Order capture part 2: actual delivery cost of an app order (RPT-C2) |
| 148 | `phase447.sql` | ours | RPT-C2 | Advance on an app order becomes a customer advance (setting OFF) (RPT-C2) |
| 149 | `phase448.sql` | ours | RPT-C2 | Cancelling an app order with a refund makes a money record (RPT-C2) |
| 150 | `phase449.sql` | ours | RPT-C2 | Order registers and advance or outstanding balances, read-only (RPT-C2) |
| 151 | `phase450.sql` | ours | RPT-C2 | Delayed and undelivered orders, on-time delivery, fulfilment rate, read-only (RPT-C2) |
| 152 | `phase451.sql` | ours | RPT-C2 | Order cancellation and refunds, delivery cost and performance, read-only (RPT-C2) |
| 153 | `phase452.sql` | ours | RPT-C2 | Order-wise production and material cost, order profitability (RPT-C2) |
| 154 | `phase453.sql` | ours | RPT-C2 | Customer credit risk and overdue; dues not linked to a customer notice (RPT-C2) |
| 155 | `phase454.sql` | ours | RPT-C2 | Customer lifetime value, complaints and returns per customer, cake history (RPT-C2) |
| 156 | `phase455.sql` | ours | RPT-C2 | Attendance summary, overtime and late variance (RPT-C2) |
| 157 | `phase456.sql` | ours | RPT-C2 | Sales per labour hour; cashier cash variance with shift (RPT-C2) |
| 158 | `phase457.sql` | ours | RPT-C2 | Production crew and hours per run; output per worker (RPT-C2) |
| 159 | `phase458.sql` | ours | RPT-C3 | Campaign master list, campaign or offer code on a sale, audited export (RPT-C3) |
| 160 | `phase459.sql` | ours | RPT-C3 | Marketing reports: spend by campaign, spend vs sales, campaign revenue (RPT-C3) |
| 161 | `phase460.sql` | ours | RPT-C3 | Marketing reports: coupon usage, acquisition cost, repeat purchase (RPT-C3) |
| 162 | `phase461.sql` | ours | RPT-C3 | Post marketing spend of form 17-1 to the journal, setting OFF, no double count (RPT-C3) |
| 163 | `phase462.sql` | ours | RPT-C3 | Audit and control: audit log pager, register of voided and reversed records (RPT-C3) |
| 164 | `phase463.sql` | ours | RPT-C3 | Audit and control: approval delays, stock adjustment approval history (RPT-C3) |
| 165 | `phase464.sql` | ours | RPT-C3 | Audit and control: price-override approver, unusual transactions list (RPT-C3) |
| 166 | `phase465.sql` | ours | RPT-C3 | Planning: festival calendar, sales forecast, item demand forecast (RPT-C3) |
| 167 | `phase466.sql` | ours | RPT-C3 | Planning: production requirement, recipe-based raw material purchase forecast (RPT-C3) |
| 168 | `phase467.sql` | ours | RPT-C3 | Planning: expected cash in and out calendar, supplier payments, expected wastage (RPT-C3) |
| 169 | `phase468.sql` | ours | RPT-C3 | Planning: sales and profit what-if scenarios, seasonal demand (RPT-C3) |
| 170 | `phase470.sql` | ours | RPT-HUB | Business Memory hub: saved items, date indexes, permission helpers (RPT-HUB, read-only) |
| 171 | `phase471.sql` | ours | RPT-HUB | "What happened?" day replay (RPT-HUB) |
| 172 | `phase472.sql` | ours | RPT-HUB | Entity timelines with running balance (RPT-HUB) |
| 173 | `phase473.sql` | ours | RPT-HUB | "What changed" and "why did this number change" (RPT-HUB) |
| 174 | `phase474.sql` | ours | RPT-HUB | Audit trail overlay for one record (RPT-HUB) |
| 175 | `phase475.sql` | ours | RPT-HUB | Favourites, recent reports, saved views, Home pins, export log (RPT-HUB) |
| 176 | `phase476.sql` | ours | RPT-HUB | Spend explorer: how much was spent on what, for whom, where (RPT-HUB) |
| 177 | `phase477.sql` | ours | integrator | Re-patch of every package hook plus integration glue; paste after 476 (integrator) |
| 178 | `phase478.sql` | ours | integrator | Closes the small helper functions to the signed-out role; paste after 477 (integrator) |
| 179 | `phase479.sql` | ours | X1 | X1 foundation part 1: connection registry, job runs, one gate for outside and AI calls, agent identities (X1) |
| 180 | `phase480.sql` | ours | X1 | X1 foundation part 2: approval queue for agent proposals, health view (X1) |
| 181 | `phase481.sql` | ours | X2 | X2 website part 1: settings (OFF), catalogue publishing, public read functions (X2) |
| 182 | `phase482.sql` | ours | X2 | X2 website part 2: checkout, stock holds, tracking, custom cake requests, owner admin (X2) |
| 183 | `phase483.sql` | ours | X3 | X3 social and marketing workspace: content, approval, publishing queue, metrics (X3, OFF) |
| 184 | `phase484.sql` | ours | X4 | X4 AI foundation: provider registry, monthly budgets, redaction, agent catalogue, call log (X4, OFF) |
| 185 | `phase485.sql` | ours | X4 | X4 AI knowledge, suggestions, feedback, evaluation (X4, OFF) |
| 186 | `phase486.sql` | ours | X5 | X5 item recognition foundation: duplicate check, review record, aliases, asset details (X5) |
| 187 | `phase487.sql` | ours | X6 | X6 market intelligence foundation: settings (OFF), rights, tables (X6) |
| 188 | `phase488.sql` | ours | X6 | X6 workspace: topics, sources, findings, competitor prices, opportunities (X6) |
| 189 | `phase489.sql` | ours | X6 | X6 growth intelligence from own data, read-only (X6) |
| 190 | `phase490.sql` | ours | X6 | X6 scheduled research hook (OFF), AI summariser slot, competitor price alerts, weekly digest (X6) |
| 191 | `phase491.sql` | ours | XB | XB part 1: bKash, Nagad, Rocket payment capture and reconciliation (XB) |
| 192 | `phase492.sql` | ours | XB | XB part 2: custom-cake workflow on top of an app order (XB) |
| 193 | `phase493.sql` | ours | XB | XB part 3: riders, delivery status, zones, cash on delivery per rider per day (XB) |
| 194 | `phase494.sql` | ours | XC | XC-1 owner daily summary, recipients, send log, receipt continuity (XC, OFF) |
| 195 | `phase495.sql` | ours | XC | XC-2 daily production suggestion, baker's confirmation, accuracy report (XC, OFF) |
| 196 | `phase496.sql` | ours | XC | XC-3 supplier price board, rise alert (threshold blank), recipe-cost preview (XC, OFF) |
| 197 | `phase497.sql` | ours | XC | XC-4 unsold stock and markdown list, wastage share (XC, OFF, markdown % blank) |
| 198 | `phase498.sql` | ours | XC | XC-5 owner-only staff coaching board, no rankings (XC, OFF) |
| 199 | `phase499.sql` | ours | SW | SW-1 sweets transfers: over-send, paused place, receipt in steps, close short (3 switches, OFF) |
| 200 | `phase501.sql` | ours | SW | SW-2 sweets sale stock: unknown unit refused on request, return at the sale's factor (2 switches, OFF) |
| 201 | `phase502.sql` | ours | SW | SW-3 item analysis takes sale returns off (switch, OFF) |
| 202 | `phase503.sql` | ours | SW | SW-4 customer due takes off applied advances (switch, OFF) |
| 203 | `phase504.sql` | ours | SW | SW-5 a made product as an ingredient, loop refused (switch, OFF) |
| 204 | `phase505.sql` | ours | SW | SW-6 stock tracking map and owner review; nothing applied (switch, OFF) |
| 205 | `phase530.sql` | union | UNION-2 | lock_check carries bos113 (owner mode) + bos87 + bos89 |
| 206 | `phase531.sql` | union | UNION-3 | biz_items and rpt_agg_sql: bos112 / bos110 / bos88 + bos402 + phase 502 |
| 207 | `phase532.sql` | union | UNION-4 | _cust_bal, customer_dues, _acct_docs, _daybook_lines, _p27_pl, _r3q_l3_shop_pnl carry both lines |
| 208 | `phase533.sql` | union | UNION-5 | _sale_stock_out, sale_return, stock_receive_transfer, stock_reconcile, stock_transfer, _recipe_lines_ok carry both lines |
| 209 | `phase534.sql` | union | UNION-6 | acct_journal_post, 7- and 8-argument, same guard and gate |
| 210 | `phase535.sql` | union | UNION-7 | advanced logic put back in shared functions (a to ...) where an early repaste reset it; does nothing on a fresh build |
| 211 | `phase536.sql` | union | UNION-8 | same, second group |
| 212 | `phase537.sql` | union | UNION-9 | same, third group |
| 213 | `phase538.sql` | union | UNION-10 | same, last group |
| 214 | `phase539.sql` | union | UNION-11 | drops the two stale overloads; adds `_union_audit()` (read-only report: merged / other / missing) |
| 215 | `phase543.sql` | form | FORM-543 | printed form codes: the clean sequence (NN-1, A-Z by English short name, owner 21 Oct 2026). Migrates forms.code, form_code in 20 tables, code literals in functions, triggers, one policy, one check and the label text. Tag FORM-CODE-CLEAN-SEQUENCE-543. Paste ONCE (a second paste is a no-op). Test: `phase543_test.sql` (local only). |
| 216 | `phase544.sql` | ours | SW | SW-7 sweets transfers: a client id reused by another user refused (switch transfer_client_reuse_block, OFF) |
| 217 | `phase545.sql` | ours | STEP1 | Purchase price check: freight counted when a landed cost is posted (switch price_check_include_freight, OFF; test phase545_test.sql) |
| 218 | `phase546.sql` | ours | FIX | `stock_transfer` carries all four switch behaviours again: phase 544 text + bos114 `transfer_needs_stock` check + bos115 `transfer_notify_receiver` notice (no new rule, all OFF; test phase546_test.sql) |
| 219 | `phase547.sql` | ours | BACKUP | Backup coverage: ai_agents / ai_providers join the dump; staff / login manifest `backup_accounts_manifest()` (switch backup_accounts_on, OFF); other Storage buckets readable by the backup bot (switch backup_buckets_on, OFF); test phase547_test.sql |
| 220 | `phase548.sql` | ours | READINESS-D8 | `stock_recon_period` lists the movement reason `transit_loss` (the period statement no longer calls a costed transit loss "unclassified"). Changes only that one function; no new rule or table; test `phase548_test.sql` and readiness scenario R17. If an old phase that rewrites `stock_recon_period` (423) is ever pasted again, paste 548 again (paste-twice safe). |
| 221 | `phase549.sql` | ours | FREIGHT-D1 | Freight / transporter payable (account 2150) is visible in `supplier_dues`, `supplier_open_bills`, `supplier_ledger`, ageing and payable through `pay_supplier` (new column `supplier_payments.landed_part`, split trigger, patches at anchors in `_sup_open`, `_sup_balance`, `_acct_docs`, `acct_reconcile`, `supplier_ledger`). No new rule: identical results when no landed charge is payable to a supplier. Test `phase549_test.sql` and readiness P2, P3. If an old phase that rewrites one of these functions is pasted again, paste 549 again (paste-twice safe). |
| 222 | `phase550.sql` | ours | REPORT-D4 | Report gross profit (`gp`, `gp_pct`, `cogs` of the cost-join reports such as `sales_summary`) is net of sale returns, following the existing rule `reports_net_of_returns` (default ON, so net_after_returns and gp now agree; OFF = unchanged). Patch at anchor in `_rptb1_agg_wrap`; returned costed revenue and COGS come from `_cogs_lines72` (same source as `biz_daily`). No new rule. Test `phase550_test.sql` and readiness G3, R21. |
| 223 | `phase551.sql` | ours | STAFFCOST-D7 | Staff-cost report `t3_payroll` reads the paid app payroll runs (from `payroll_lines`) for months that have a run, and leaves out the paper sheets of those months, when `report_salary_source` = app_first or `payroll_accrual_on` is on (the same switch as L1/C2). Default (legacy) unchanged. Patch at anchor in `_r3q_t3_payroll`, helper `_p551_app_salary()`. No new rule. Test `phase551_test.sql` and readiness R18c. |
| 224 | `phase552.sql` | ours | COUNT-D5D9 | Count-first by default: `blind_count_on` default becomes ON, following the recorded owner decision of 11 Oct 2026 (DECISIONS.md, BUILD-RULES 9); a value the owner already set stays. New rule `drawer_expected_source` (typed | pos_compare | pos, default typed): the drawer expected cash can come from the POS, or be compared with it (exception `drawer_typed_vs_pos`). Patches at anchors in `count_save`, `count_peek`, `_entries_blind_guard`; four helper functions `_p552_*`. Test `phase552_test.sql` and readiness D1, D9. |
| 225 | `phase553.sql` | ours | ADVISOR-D2D3D6 | Setup advisor data: recommended values for `acct_transit_loss` (true), `acct_transfer_mode` (location_tagged), `stock_negative_mode` (block), `production_requires_recipe` (true) and new rows for `blind_count_on`, `report_salary_source` (app_first), `rpt131_on`, `pin_signature_on` (gated by the new check `sec_pin` and the owner confirmation switch `pin_all_set_confirmed`, default OFF), `payroll_accrual_on` (row, no value). No rule default and no function behaviour changes; the owner still taps apply. Test `phase553_test.sql`; readiness rec mode. |

## Old phase files: if you ever paste one again

Old phase files (3 to 79 and the early phases of our line) re-create functions, and that removes the hooks other phases added to them. If you paste any old file again: paste phase 477 afterwards (it puts every hook back and calls `public._i2_apply_all()`), then phase 478 (it closes the helper functions to anon), then 499 and 501 to 505, then **529 to 539 again, in order** (they are safe to paste twice and put the merged text of the 156 functions back; an unknown text is listed, never overwritten). Do not paste phase 40 or `ALL_NEW10.sql` after the advanced phase 511: they bring back the 7-argument `acct_journal_post` next to the 8-argument one; phase 529 removes the ambiguity again. Then run the checks of step 4.
