# PLAN_NEXT: what is pending, what was decided, and why

Branch `claude/supabase-readonly-audit-xo3qkp`. Written 19 Oct 2026 after the owner's read-only audit (`ISLAMIYA_BOS_AZ_READ_ONLY_AUDIT_2026-10-19_REBUILT.md`). Owner has given all permissions and does not want to be asked decisions: where a choice was needed it was made as a business specialist and recorded in section 3.

**Status legend**
- **DONE** – change made in this branch, verified on a local throwaway database.
- **DONE-OFF** – change made; new behaviour is OFF by default (a switch in the rules table).
- **REPRO** – defect reproduced locally; fix not made yet (todo).
- **NOT REPRO** – not reproduced locally in this branch (todo: check first).
- **NOT IN BRANCH** – the feature or code the audit describes is not in this branch (see section 1).
- **TODO** – planned, not started.
- **OWNER** – needs the owner (a setting, a secret, a SQL paste, a web upload, a decision made outside the repo).
- **DECIDED** – a decision was recorded in section 3; no code change follows from it now.

## 0. What was delivered in this branch

| New file | What | Verified by |
|---|---|---|
| `supabase/phase499.sql` + `_test` | Sweets transfers: refuse over-send, refuse paused place, receive in parts, close the rest short. 3 switches OFF. | Local DB built from the full chain; test 23/23 |
| `supabase/phase501.sql` + `_test` | Sales: refuse a sale with unknown unit (switch); returns use the factor of the sale (switch). Sale factor table. | test 17/17 |
| `supabase/phase502.sql` + `_test` | Item analysis (`biz_items`) takes sale returns off (switch). | test 6/6 |
| `supabase/phase503.sql` + `_test` | Customer due takes off applied advances (switch). | test 7/7 |
| `supabase/phase504.sql` + `_test` | A made product (finished good) as an ingredient, loop refused (switch). | test 8/8 |
| `supabase/phase505.sql` + `_test` | Stock tracking map: proposals per item type, owner review, apply behind a switch. Changes no item by itself. | test 17/17 |
| `docs/STOCK_TRACKING_POLICY.md` | Tracking proposal by item type (counts from the item dictionary). | reviewed by reading the counts |
| `docs/SECURITY_BACKLOG.md` | Anon-executable functions and no-policy tables, with intended callers. No grant changed. | queries on the local build |
| `tools/check_backup_guard.py` + CI step | Static guard: backup refuses a public repo first, no data artifacts, only backup pushes. | runs OK; a negative test (guard moved after the dump) fails as it should |
| `web/data/info.json` | 9 rule entries for the new switches; 7 existing entries got `related` links. | `tools/check_info_coverage.py` OK |
| `tests/sql/ORDER.txt`, `docs/PASTE_ORDER.md`, `docs/NUMBERING.md` | Paste order 499, 501 to 505 (500 skipped on purpose). | `tools/check_numbering.py` PASS |

Not changed: any web file (except `info.json`), any live database, any grant, any policy, `org_scope_on`, repository visibility, GitHub secrets.

## 1. Facts about this branch that the audit did not have

> **Superseded (23 Oct 2026).** Section 1 describes the branch as it was on 19 Oct: diverged from the advanced line, live built from another line, `bos112` not recoverable. Today the union merge is done (the advanced line is an ancestor), `bos112` logic is in the chain, and the single repository is `islamia-bos-app` on `Main-Img` (`docs/SINGLE_REPO.md`). Kept as history.


1.1 **The branch is not the audited code.** `origin/ccr-9c1f9be7-3s9qnz` is 235 commits ahead of this branch and this branch has 192 commits the other does not have. They diverged. The same phase numbers hold different work: here phase 131 is the to-do list and phase 132 the shift schedule; on the advanced branch phase 131 is reports stage 1 and phase 132 the group ERP master-data separation, and phases 123 and 133 to 135 exist only there. **The multi-business code is not in this branch.** There are no `org_units`, `business_profiles`, `org_scope_on`, or other-business templates here (checked: no matches in `supabase/`, `web/`, `tools/`, `docs/`).

1.2 **Live is built from another line.** 27 of the 69 no-policy tables in the live audit are not created by this branch (landed costs, import/export, phase 134 business profile, Telegram secrets, and others). The live project matches the advanced branch more than this one. See docs/SECURITY_BACKLOG.md section 0.

1.3 **The `bos112` returns-netting block is not recoverable here.** The audit says the live `biz_items` contains a `bos112` block that is not in the repository. It is not in the repository (no match for `bos112`, `_fix_fn_backup`). The scratch folder the owner named (`scratchpad/w/`) does not exist in this session (the scratch folder is empty; the uploads folder has only the audit and images). So the exact text cannot be restored. Decision D-06: recreate the netting from the return rows, behind a switch, and say so. **[Corrected 20 Oct 2026, union merge: this was wrong. The `bos112` text IS in the repository once the advanced line is merged: `supabase/phase112.sql` (advanced phase 112, same number) and `phase531.sql` keeps it inside `biz_items` together with our phase 502 netting. See docs/RECOVERY_AUDIT.md and docs/LIVE_DELTA.md.]**

1.4 **The card-settlement code is not in this branch.** There is no `card_settle_over_mode`, no card receivable settlement, no settled-card void. The audit's card items (settled-card void, over-settlement, card fee) cannot be reproduced here. **[Corrected 20 Oct 2026, union merge: this was wrong. Card settlement is in the advanced phases 85 and 109 (`phase511.sql` and `phase109.sql` in this repository: `card_settle`, `card_settlements85`, over-settlement mode, settled-card void). It is part of the merged version.]**

1.5 **Live data is unknown to this session.** All live counts in this file come from the audit (19 Oct 2026, 04:28 to 04:34 UTC). Nothing was read from live.

## 2. Pending items (numbered)

### 2.1 Other business templates and multi-business (audit F-08, F-09; scope 1)

1. **NOT IN BRANCH** – Port the org/business scope work (advanced branch phases 123, 124 to 129, 131 to 135, the C1 to C3 commits) into a new phase series. Needs a renumbering plan (the numbers collide), a review of the advanced branch's 235 commits, and an owner decision on the branch of record (see 2.1 item 2 below and D-01). **TODO, large.**
2. **OWNER** – Decide the canonical branch and record its commit SHA; verify which SQL phases are live (audit F-01, release gate A). Until then, do not paste any phase from the advanced branch.
3. **TODO (after item 1)** – Two-business negative test: business A's staff cannot read or write business B's customers, items, recipes, stock, prices, reports, finance, locations or files, through RPCs and table reads. Must run on a local database with the switch on in the test only. Not possible on this branch today.
4. **DONE** – `org_scope_on` was NOT switched on and no default changed (the switch does not exist in this branch; nothing to change).
5. **OWNER / NOT IN BRANCH** – Other templates (`construction`, `dealership`, `hardware_paint`, `online_store`, `technology`, `import_export`): no template code or data exists in this branch, so nothing was added and nothing is active. The live status values (`not_implemented`, `needs_setup`, `available`) are in the live database only; the owner should confirm them with a read-only query.

### 2.2 Sweets: negative stock and sales (audit A2, F-12, F-13; scope 2a)

6. **DONE-OFF (phase 501)** – Unknown unit: a sale with a tracked item whose unit has no conversion can be refused (`stock_unit_unknown_block`). Default keeps the old behaviour (sale kept, stock not reduced, yellow warning). Reproduced in the test with the switch OFF (T1). Note: `record_sale2` stores the item's own unit on each line, so the case needs an item whose unit is not its base unit and has no conversion; a first attempt with a requested unit did not reproduce for that reason.
7. **DONE-OFF (phase 501)** – Return uses today's conversion factor. Fixed for sales made after phase 501 (`return_sale_factor_on`, factor saved per sale in `sale_base_factor`). Sales made before the new table keep the old behaviour (no saved factor). Reproduced in the test with the switch OFF (T5): 2 box sold at 12 (24 pieces out), factor edited to 10, return puts back 20 (4 lost).
8. **DECIDED (D-02)** – Late sales (sold more than 2 minutes before the server receives them) under `stock_negative_mode = block` are NOT refused. They are kept, the stock can go negative, and a yellow `stock_negative` exception is written. Reproduced: 9 kg sold at 10 minutes old on 5 kg: accepted, stock -4, exception written. A fresh sale of the same quantity is refused.
9. **TODO (needs client change)** – Phone clock skew: a phone whose clock is behind looks like a late sale and skips the block. The fix is a replay marker from the phone's offline queue (the POS sends `p_sold_at` and drops its queue time `_t` in `clean()`), plus a server rule that treats only marked replays as late. Not done: it changes the POS and the RPC signature.
10. **REPRO, DECIDED (D-07)** – A sale at the receiving place while the goods are still in transit: reproduced (20 kg in transit, 5 kg sold at the receiving place: stock -5, `sale_out` posted) under the default `stock_negative_mode = warn`. Decision: no code change; the owner sets `block` (Settings, stock rules). Under `block` the same sale is refused.
11. **REPRO, OWNER decision** – A very old offline sale is re-dated to now. Checked on the local build (21 Oct): with the default `late_sale_policy` = `redate`, `_w1b_late_sale` accepts a sale made 100 hours before it reached the server (limit `pos_offline_hours` = 72) and returns NULL: the sale is re-dated to now, with no exception. Only `park` applies the 72-hour rule (held for the owner) and `redate_flag` writes a yellow exception. Which policy is right is the owner's choice (phase 89 default). Not changed.
12. **TODO** – Combo / kit consumption, opening stock without batch sold last, count gain without batch, silent variance alert when tolerance is unset: NOT REPRO yet.
13. **OWNER** – The live sale with no item id (audit F-10: 1 of 14 sale lines). Read-only check first (which receipt, which item name), then the owner decides whether to correct the record.
14. **OWNER** – The 10 live sales (4,461 taka, no stock or journal trail). The audit asks whether they are real or test records. The owner answers; nothing is changed by the agent (audit F-10, F-11).

### 2.3 Sweets: transfers (audit A5, F-14, F-15; scope 2b)

15. **DONE-OFF (phase 499)** – Over-send: `transfer_overdraw_block` refuses a send bigger than the sender's stock. Reproduced: 120 kg sent from 100 kg on hand under `warn` (sender -20).
16. **DONE-OFF (phase 499)** – Paused destination: `transfer_paused_block` refuses a send to a place whose status is not live. Reproduced: a send to a paused place was accepted.
17. **DONE-OFF (phase 499)** – Partial receipt in steps: `transfer_partial_on` lets the receipt come in parts. The transfer stays `sent` until all of it arrives or the owner runs `stock_close_transfer_short`. Reproduced: 20 sent, 8 received, second receipt returned `dup`, 12 kg stuck in transit for ever.
18. **DONE-OFF (phase 499)** – Close the rest short: `stock_close_transfer_short` writes one `transit_short` exception and closes the transfer. Works only with item 17 on.
19. **NOT REPRO (in this branch)** – `transit_short` GL mismatch (location-tagged accounting, "loss" mode): in this branch `transit_short` writes a stock exception only and posts no journal. The audit's GL mismatch belongs to the advanced branch's accounting. Check on the advanced branch before any fix.
20. **DONE-OFF (phase 544)** – Different-user replay of a reused client id. Reproduced on the local build: user A sends 5 kg with client id X; user B sends 7 kg with the same X and is answered `dup` with A's transfer id, B's 7 kg is not moved. Switch `transfer_client_reuse_block` (OFF): ON = refused with `client_id_reused`. The same user replaying its own id still gets `dup`. Tests: `phase544_test` 12/12 on a fresh local build, paste-twice clean; `phase499_test` 23/23. Owner: switch on after a test.
21. **TODO** – Receiver notification when goods are sent; factory-to-branch statement (sent / received / short / in transit / sold / returned / wasted by branch and period). The statement is a report: design first.
22. **TODO** – Return-to-factory as a dedicated document with reason and original transfer (today: a reverse transfer).

### 2.4 Sweets: profit (audit A3, F-16; scope 2c)

23. **DONE-OFF (phase 502)** – Item analysis (`biz_items`) takes sale returns off (`biz_items_net_returns`). Returns are dated by the day they were made, counted in that period and place, as the returns line of other reports does. Reproduced: 3 kg sold, 1 kg returned: 3 kg and 300 shown before; 2 kg and 200 after. Decision D-06.
24. **REPRO / DECIDED (D-06)** – The audit's `bos112` netting block: not in the repository, not recoverable here. Its netting is replaced by item 23. If the owner has the live text (the function body from the live database), it can be compared with phase 502 in one review. **[Corrected 20 Oct 2026, union merge: superseded: the bos112 netting is `phase112.sql`; the merged `biz_items` (phase531) uses it when `items_net_of_returns` is on and our phase 502 netting only when it is off.]**
25. **TODO (decision needed, D-08)** – One profit source of truth. This branch has `profit_recon` and `profit_source_check` (checks), but no single profit figure that every report uses. Decide the truth (recommended: sales after returns, COGS from the stock ledger, unknown cost shown as unknown, never as 100% margin), then make each report use it.
26. **NOT REPRO** – Shop P&L counts uncosted revenue as 100% margin (the audit's shop view). Check the shop P&L function before any fix.
27. **NOT REPRO** – Wastage / expiry loss and card fees not in shop or product profit.
28. **NOT REPRO** – Payroll double count (conversion cost plus branch salary loss).
29. **NOT REPRO** – Shared-cost allocation: one-day report shows the whole month's share; reassignment changes history (needs a month-end profit snapshot).
30. **TODO** – No contribution-margin metric per product or branch. Design first.

### 2.5 Cash, card and customer money (audit A4, F-17; scope 2d)

31. **DONE-OFF (phase 503)** – Customer due takes off applied advances (`dues_net_advance_on`). Reproduced: 500 credit sale, 300 advance applied: due still 500 (advance balance correctly 0).
32. **TODO** – `customer_ledger` also does not net applied advances (phase 447 header says so). Same fix shape as item 31; a separate change after the owner confirms the due-list switch.
33. **NOT IN BRANCH** – Settled-card void leaves the card receivable negative; over-settlement accepted by default; card fee. No card settlement exists here. If this code is brought in (item 2.1.1), the decision for over-settlement is: keep the warn default and document it, unless the owner says refuse (it is not owner-neutral: a fee rounding case would be refused). Recorded as D-09 pending item 2.1.1. **[Corrected 20 Oct 2026, union merge: superseded: card settlement exists (advanced phases 85/109 = `phase511.sql`, `phase109.sql`).]**
34. **NOT REPRO** – Day book shows a bank-paid voucher as cash; the journal shows it as bank. Check the daybook function against the journal for the same receipt.
35. **NOT REPRO** – Drawer shortage / overage is a flag only (no journal to the short-and-over account); opening float not linked to the last close.
36. **NOT REPRO** – Mobile wallet and multiple bank accounts not fully represented in the payment mapping.
37. **TODO** – VAT report is a memo calculation (no output VAT account in the tested path). Owner decision on the VAT method first.

### 2.6 Sweets: manufacturing cost (audit A1, F-18; scope 2e)

38. **DONE-OFF (phase 504)** – A made product as an ingredient (`recipe_intermediate_on`), loop refused. Reproduced: `bad_ingredient_type`. This branch has no separate semi-finished type; a made intermediate is a finished good (decision D-10). Production consumes its stock (tested: 10 kg less 2 kg per batch).
39. **NOT REPRO** – Piece-based product in pool mode gets conversion cost 0 with only a yellow warning.
40. **NOT REPRO** – Late cost pool is not repriced for a production run that was booked before the pool was entered.
41. **NOT REPRO** – Cost pool bills do not book the matching expense (high risk: credit to overhead without a debit expense). Check first; this is the audit's most serious manufacturing item.
42. **TODO (decision D-11)** – Overhead over- or under-absorption true-up is a report only. Decide the month-end journal rule before any code.
43. **TODO** – Actual-yield loss is not a separate monetary variance; `std_cost` uses actual spend over theoretical output.
44. **TODO** – Packaging allocation uses planned yield in one path (not actual yield).
45. **DONE-OFF (phase 545, step 1 of 21 Oct 2026)** – Owner decision: freight is an OPTION in today's purchase price check. Switch `price_check_include_freight` (default OFF, Rules screen, module purchase, info entry `rule:price_check_include_freight`). ON: when a landed cost is posted, each item it touches is compared with its last posted purchase, both at invoice price plus the freight allocated to the line (`landed_cost_alloc`, parts stock + cogs; voided rows count negative). A jump above `purchase_cost_jump_pct` writes a yellow `purchase_price_jump` exception whose text says "with freight". OFF: no change. The same scenario with and without phase 545 gives the same fingerprint (`FP545 24abfd73b7374c0b119d91db15c94826` in both). Tests: `supabase/phase545_test.sql`, 19 of 19 PASS on a fresh local build of the full chain; phase 545 pasted twice with no error; `_i2_state()` not present = 0 rows. Limit: the freight of a bill is known only when its landed cost is posted, so the freight check runs then; the invoice check at bill posting is unchanged (it runs before the freight exists). Owner: paste phase 545 (`docs/PASTE_ORDER.md` row 217, `docs/LIVE_DELTA.md`), then switch it on after a test.
46. **OWNER** – `recipe_approval_required` is `off` and `production_requires_cost` is `warn` in the live audit. These are owner settings; not changed.

### 2.7 Stock tracking (audit F-10; scope 3)

47. **DONE** – Tracking proposal by item type: `docs/STOCK_TRACKING_POLICY.md` (754 proposed tracked, 320 not tracked, 238 controlled by their own rule; counts from the dictionary, 1,312 items).
48. **DONE-OFF (phase 505)** – Mapping tool: plan, review, apply by type, behind `tracking_map_apply_on` (OFF). Nothing is flipped by the file.
49. **OWNER** – Classify items with no type (plan shows "(not classified)").
50. **OWNER** – Count opening stock per place for each tracked type (never guessed).
51. **OWNER** – Review each type with `stock_tracking_review`, then apply.
52. **TODO** – Sales-versus-stock daily check (audit Gate C: opening + in - out = closing, and sales quantity against ledger movement). Not built.

### 2.8 Backup, notifications and the public repository (audit F-03, F-04, F-19; scope 4)

53. **DONE (already present)** – The backup workflow refuses to run unless the repository is private (step "Refuse to run in a public repository"; fails closed).
54. **DONE** – Static guard `tools/check_backup_guard.py` (guard first, no data artifact, only backup pushes) in CI (`integration-checks.yml`). Tested with a broken copy.
55. **OWNER** – The repository is public (audit metadata, 19 Oct). Under the guard, the backup will refuse until the repo is private or the backups go to a separate private repository. **Decision D-12: no visibility change by the agent (owner rule).** The owner chooses: make this repo private, or a separate private backup repo.
56. **OWNER** – Secrets for backup and notify (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `BOT_EMAIL`, `BOT_PASSWORD`, `BACKUP_PASSPHRASE`, `BACKUP_KDF_SALT`, Gmail fields). The audit's jobs failed for missing `SUPABASE_URL`. Steps in docs/OPS_SETUP.md. Never in source.
57. **OWNER** – Prove one successful scheduled backup and one isolated restore (`tools/restore_drill.py` on a disposable database). Then prove one notify run.
58. **TODO** – Node 20 deprecation of `actions/checkout@v4` in the workflows (maintenance).
59. **OWNER** – Secret scan of the full git history and all branches (audit F-19). Rotate any real secret found.

### 2.9 Security and performance backlog (audit F-06, F-07; scope 5)

60. **DONE (document)** – `docs/SECURITY_BACKLOG.md`: the anon-executable functions with intended caller and a proposal for each; the no-policy tables with the definer functions that use them.
61. **OWNER** – Run the two read-only queries in SECURITY_BACKLOG section 4 on live and send the lists back. Then the review is repeated for the live names.
62. **OWNER decision, TODO** – Revoke anon from the "Review" rows of SECURITY_BACKLOG section 1 (after the live check, with an anonymous test of login, storefront and device path). No policy is added to any table.
63. **TODO** – The 337 unindexed foreign keys, 256 unused indexes, 45 RLS init-plan warnings, 15 multiple-permissive-policy cases, 4 duplicate index pairs: each needs a query plan on staging. No blind change.
64. **OWNER** – Edge functions: the live listing is empty. Decide which integrations are needed; deploy through review or mark them off.
65. **TODO** – CSP and the newer UI protections exist on the advanced branch only. Port with the branch decision (2.1.2).

### 2.10 Earlier design work carried over (from docs/HANDOFF.md section 4)

66. **OWNER / TODO** – Two-state layout (Default / all optional parts on / revert): design debated by two architects; the owner has not chosen. Not started.
67. **OWNER** – Form-code sequencing: `tools/numbering_map.json` has `form_groups_approved: false`. No form code is changed. The owner must approve the map before any form code moves (BUILD-RULES rule 2).
68. **OWNER** – Phase numbers in SQL text: the phase 487 seed description says "phase 490" (a line the renumber tool will not change). The owner edits it.
69. **TODO** – Info entries: `related` fields for `cake_spec` and `cake_price_manage` (these two have no entry yet). The other seven were done (section 0).
70. **OWNER** – X3 social screen: needs the Meta / WhatsApp account and the public media URL decisions. Not started.
71. **OWNER** – X5 camera: test on a real phone (not done here).
72. **OWNER** – Phone check at 360 px for the new switches and screens (no screen was added in this branch).
73. **OWNER** – Bengali text review of the new rule labels (written bilingually; the owner should read them).

### 2.11 Deployment and paste (owner)

74. **OWNER** – Paste the SQL in this order, in the Supabase SQL editor, after the earlier phases already live: phase 499, then phase 501, 502, 503, 504, 505. Each file is paste-twice safe. Each is OFF by default, so pasting changes no behaviour. Full order in `docs/PASTE_ORDER.md`, rows 185 to 190.
75. **OWNER** – If any old phase file (3 to 98, or any 300 to 477 file) is pasted again: paste 477 and 478 after it, then paste 499 and 501 to 505 again (they re-define some old functions).
76. **OWNER** – Web upload: `web/data/info.json` changed (9 new entries, 7 `related` links). Upload it with the next web release (`docs/GO_LIVE.md` §3). No other web file changed in this branch.
77. **OWNER** – Switch on each new behaviour only after a test in the owner's own use (each switch is in the rules table and in Settings, with its (i) text).

### 2.12 Owner-visible items added on 21 Oct 2026

78. **DONE (owner-visible) – Backup reliability.** Home > Backup (JSON download): one run at a time, progress shown, four tables read at once, the file kept for "save the file again" (a new tap), a Bengali message with a retry button when the run fails, and a notice naming any table that could not be read (the file is still saved without it). Cause and evidence: commit `36254db`, `web/app.js` (backup section), test `tests/web/backup_button_test.js` (5 taps, double tap, failure, partial, save again; 360 px). The browser's own download blocking was not reproduced headless; the owner should test on a phone (tap Backup five times; each run ends in a saved file or a message).
79. **DEFERRED-BY-OWNER – Show or hide whole main features.** The owner has not decided. Recorded as deferred in `docs/DEMAND_VERIFY.md` (N4) and `docs/DESIGN_ROADMAP.md` section 2. The switch `ia_show_off_features` does NOT exist (no rule row, no read in `web/`); it is created only after the owner decides. Nothing implemented.

80. **N11 pass (21 Oct 2026)** – Sweets TODO list: closed in code this pass: item 20 (phase 544). Checked and left as owner decisions: item 11 (item 45 was done in phase 545, see there). Left open, with reasons: 9 (needs a POS replay marker: a client and RPC change, not done here), 12 (combo and kit: several cases, each needs its own reproduction), 21 and 22 (design first), 25 (D-08, changes every report), 30 (design first), 32 (waits for the owner's due-list switch), 37 (VAT method: owner), 42 (D-11 month-end rule: owner), 43 and 44 (monetary variance and packaging basis: design, needs reproduction), 52 (daily sales-versus-stock check: not built).

## 3. Decisions made (and why)

- **D-01 Branch of record.** Do not merge or port the advanced branch in this task. Reason: 235 commits and conflicting phase numbers; a port needs its own plan and review. Recorded as item 2.1.1 and 2.1.2 (owner to confirm the canonical branch).
- **D-02 Late sales are not refused.** Reason: goods that left the shop cannot be un-sold, and refusing a queued offline sale loses the sale and blocks the phone queue. The yellow exception is the control. Clock skew (item 9) is open and needs the replay marker.
- **D-03 Every new behaviour is OFF by default.** Reason: the owner's rule (BUILD-RULES, CLAUDE.md). Each switch has an (i) text in `info.json`. Turning a switch on is the owner's decision.
- **D-04 Blocks are switches, not defaults.** Reason: changing a default changes live behaviour (for example refusing over-sends would stop today's sends). The owner can switch each block on after a test.
- **D-05 Partial receipt keeps the transfer open, and the owner closes the rest.** Reason: a split delivery is normal; the close action is the owner's act, so a short quantity is never closed by accident.
- **D-06 Item analysis netting uses the return's own date.** Reason: the same rule as the returns line in the other reports, and as the cash and the books (when the goods come back). The bos112 text is not recoverable, so the netting is written again from the return rows; the difference from the live version is unknown until the owner compares. **[Corrected 20 Oct 2026, union merge: decision superseded by the merge (see item 24 note): the advanced bos112 netting is canonical, ours (502) stays as the fallback and never takes a return off twice.]**
- **D-07 Stock negative mode stays `warn`; the owner sets `block`.** Reason: `block` refuses sales on today's data, which the owner has not reconciled. Recommended setting: `block` once stock is counted (item 50).
- **D-08 One profit truth is a design task, not a code change now.** Reason: choosing the truth changes every report.
- **D-09 Over-settlement stays a warning when the card code is brought in.** Reason: a fee rounding case would be refused otherwise; the owner decides. (Only applies when item 33 code exists.)
- **D-10 A made intermediate is a finished good.** Reason: this branch has no semi-finished type, and adding a type would change the item model. The loop guard makes it safe.
- **D-11 Overhead true-up stays a report until the owner sets the month-end rule.** Reason: a journal entry for it changes the books.
- **D-12 No visibility change, no secret change, by the agent.** Reason: owner rule; the backup guard already protects the data.
- **D-13 Revokes are proposals, not changes.** Reason: a wrong revoke can stop a login, a storefront or a device. Each needs the live list and a test.
- **D-14 Phase 500 is skipped.** Reason: the numbering guard lists 500 as a retired number. Skipping avoids a reference to the old file being read as the new one.
- **D-15 The bos112 and card-settlement gaps are recorded, not invented.** Reason: no text exists here to copy; inventing a settlement would be worse than a documented gap. **[Corrected 20 Oct 2026, union merge: superseded: both gaps are closed by the advanced line (phases 112 and 85/109).]**
- **D-16 The 27 live-only tables are not in this branch.** Reason: their code is not here, so no policy or caller can be checked here.

## 4. What was reproduced, and how

Every reproduction was run on a local throwaway PostgreSQL 16 cluster (port 5544, a `postgres` user, created for this session and removed at the end), built from the owner paste chain (`tests/sql/build_fresh_db.sh`, `ORDER=all`). The Supabase roles `anon`, `authenticated` and `service_role` were created on that cluster only. No live project was touched. The test users are `test_*` accounts with neutral names; the test items are `test_*` codes.

## 5. Checks run before the commit

- `python3 tools/check_no_demo_leak.py` – OK
- `python3 tools/check_numbering.py` – PASS
- `python3 tools/build_phase477.py --check` – OK
- `python3 tools/test_testonly_files.py` – PASS
- `python3 tools/check_info_coverage.py` – OK
- `python3 tools/check_ui_inventory.py` – OK
- `python3 tools/check_backup_guard.py` – PASS (new)
- Full chain build with `ORDER=all` – no errors; each new file pasted twice without error.
- Each new `_test` on the full chain – all PASS (see section 0).
- The repository SQL regression script `tests/sql/run_all_sql.sh` – see section 6.
- `tests/web/infohint_test.js` – 0 failures.

## 6. Regression run (repository SQL suites)

Run: `PORT=5544 PFX=w5 bash tests/sql/run_all_sql.sh` on a local throwaway cluster (chain phase 8 to 505, every suite, every phase pasted twice).

- Paste-twice errors from phase 88 on: none.
- Every new suite (phase 88 to 99 and 499, 501 to 505): all PASS.
- Old suites: three differ from the base run (through 87). Each was checked against a fresh build of the chain through phase 498 (the branch before this work), and each gives the same result there:
  - `phase21_test`: two failing checks (T1, T5) on both builds: pre-existing.
  - `phase26_test`: one failing check (K2, "shows no money column") on both builds: pre-existing.
  - `phase84_test` (with the test-project files): the same 80-table refusal list and the same RESULT (36 pass, 3 fail) on both builds: pre-existing. One of my own changes (a foreign key from `sale_base_factor` to `sales`) added an entry to that list; it was removed, and the list now matches the pre-branch one.
- Web: `tests/web/infohint_test.js` (info entries, 360 px, the 552 entries): 0 failures. Its seed-SQL check needed the new rule keys written in tuple form (done). Screenshots were written to the test folder and not committed.
- Not run: the full web suite (`tests/web/run_all.py`, 109 suites). Disk was at 44%, so it is allowed; it was not run in this session because the changes are SQL, `info.json` and a CI check.
