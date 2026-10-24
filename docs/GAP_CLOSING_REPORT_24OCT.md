# GAP CLOSING REPORT, 24 Oct 2026 (branch Main-Img-v3)

`Main-Img-v3` = `Main-Img-v2` (76e5d77, untouched) + six commits that close the top defects of `docs/READINESS_99.md`. Local only: nothing pushed, no PR, no GitHub or Supabase change. Every defect was first reproduced on a fresh local PostgreSQL 16.15 (own data dir under /var/tmp, own port) and then shown passing with the same scenario. One phase per defect, each with its own test, registered in `tests/sql/ORDER.txt`, `tests/sql/paste_order.env`, `docs/PASTE_ORDER.md` and the generated paste parts, with BUILD-LOG entries and (i) texts for the new rules. Old phase files were not edited; every patch of an existing function is a patch at an anchor (the text is read from the database, a missing anchor stops the phase with a message, a second paste does nothing).

## Per defect: before and after

| Defect | Phase | Before (reproduced) | After | New behaviour switch |
|---|---|---|---|---|
| D1 freight / transporter payable | 549 | P2: `supplier_dues` had no row for the transporter owed 490 (account 2150); P3: `pay_supplier` raised `overpaid` | P2, P3, P3b (2150 = 0), F2 pass; journal Dr 2150 / Cr cash; trial balance equal, unbalanced entries 0; `phase549_test` 10/10 | none: identical results when no landed charge is payable (new column `supplier_payments.landed_part` stays 0) |
| D4 sales_summary gross profit | 550 | place 1 gp 3,363.22 beside net_after_returns 3,850 | gp 3,198.55 = 3,850 - 651.45 (G3); all 120 catalogue reports still run (R21); `phase550_test` 5/5 | follows the existing rule `reports_net_of_returns` (default ON; OFF = unchanged) |
| D7 staff-cost report T3 | 551 | `t3_payroll` net_pay 0 after two paid runs (9,613) | 9,613 under `report_salary_source` = app_first or `payroll_accrual_on` (R18c); default (legacy) unchanged; `phase551_test` 8/8 | existing switch |
| D5 count-first | 552 | maker saw `expected` and `diff` after counting (D1 check) | blind by default (D1 passes); `phase552_test` 10/10 | **default ON by recorded owner decision** (DECISIONS.md 11 Oct 2026 "Mandatory by default", BUILD-RULES 9); header says so; an owner-set value is untouched |
| D9 drawer expected cash | 552 | expected cash only from typed figures | new rule `drawer_expected_source` typed / pos_compare / pos; POS cash 2,350 = typed; exception `drawer_typed_vs_pos`; 5 added checks pass | default `typed` (unchanged) |
| D2 / D3 / D6 advisor | 553 | advisor omitted transit loss, transfer mode, blind count, salary source, rpt131, negative-stock block, recipe required, payroll accrual, PIN signature | `rec` run 148 pass / 0 fail (books equal stock, count blind, salary reports from the app); `phase553_test` 11/11 | advisor data only; PIN row gated by the new owner switch `pin_all_set_confirmed` (default OFF); payroll accrual row has no value (accountant and owner decide); transfer mode location_tagged vs company_wide stays the owner's decision |
| D10 stale fixtures | tests | e2e default 195 pass / 10 fail / 7 error; audit2 13 unmapped FAIL; "switches ON" A1 79 pass / 104 fail | e2e 206 / 0 / 0 (rec 205 / 0 / 0); audit2 defaults 512 / 190, unmapped FAIL 2; "switches ON" A1 163 / 24, unmapped 76 -> 27 | tests only |

D2/D3 are closed by the advisor row (owner taps apply); the defaults of `acct_transit_loss` and `acct_transfer_mode` were not changed.

## Readiness scenario (pass / fail)

| Mode | Before (as audited, Main-Img-v2) | After D1 | After D4 | After D7 | After D5/D9 | After D6 (final) |
|---|---|---|---|---|---|---|
| default | 122 / 19 | 126 / 17 | 127 / 16 | 127 / 16 | 133 / 15 | 133 / 15 |
| rec (advisor) | 126 / 15 | 130 / 13 | 131 / 12 | 131 / 12 | 137 / 11 | **148 / 0** |
| recx (advisor + extras) | 137 / 4 | 141 / 2 | 142 / 1 | 143 / 0 | 148 / 0 | 148 / 0 |

The check count grows because the scenario got the checks P3 (two) and P3b and five D9 checks; P3 now expects success and F2 expects the books after the 490 cash payment. The 15 failures left in the default run are the safe defaults the owner has not switched on (transit short and cash short unbooked, transfer accounting off, staff-cost report on the paper source, count loss unbooked); they pass once the advisor is applied. The numbers on the original v2 tip with the original scenario were 122/19, 126/15, 137/4 (the first column).

## Proof that only the intended objects changed (full chain, 266 phase files)

- Build from scratch: 0 errors. Every file pasted twice in a row (532 pastes): 0 errors, identical function hashes. The 21 generated paste parts run in sequence: 0 errors, identical function hashes, 2907 functions, 478 tables, 486 policies, 629 rules; no table without row level security.
- Against Main-Img-v2: 11 functions added (`_lc_charged`, `_lc_open`, `_lc_open_total`, `_p549_pay_debits`, `_p549_split_bi`, `_p551_app_salary`, `_p552_expected`, `_p552_flags`, `_p552_pos_cash`, `_p552_pos_expected`, `_sup_balance_ord`), all closed to anon and authenticated; 11 functions changed by anchor patches (`_acct_docs`, `_entries_blind_guard`, `_r3q_t3_payroll`, `_rptb1_agg_wrap`, `_setup_chk81`, `_sup_balance`, `_sup_open`, `acct_reconcile`, `count_peek`, `count_save`, `supplier_ledger`); every other function hash is identical. Rules: `blind_count_on` default false -> true, new `drawer_expected_source` (default typed) and `pin_all_set_confirmed` (default false); no other rule row differs; no rule has an owner value. One column added: `supplier_payments.landed_part`. No table added, no policy changed. One trigger added: `zz549_landed_split_bi`.
- Journal safety: unbalanced entries 0 in all three scenario runs; the supplier payment journal debits add up to the credit by construction (`_p549_pay_debits`).
- Old suites compared before and after phase 552 on the same database: `phase23_test` 49, `phase47_test` 3, `phase133_test` 0, `phase535_test` 4, `phase536_test` 4 failure lines, identical; `phase18_test` gained its one expected failure (T0 asserts the old default OFF; `tests/sql/baseline_fails.txt` updated).
- Phase tests on the final chain: 546 22/22, 547 15/15, 548 5/5, 549 10/10, 550 5/5, 551 8/8, 552 10/10, 553 11/11. Backup end-to-end `tools/test_backup_coverage.py` 10/10 (with the new column), `tools/test_ops.py` 34 OK, `tools/check_backup_guard.py` PASS.

## CI checks (all pass)
check_no_demo_leak OK; check_numbering PASS; check_paste_order OK; check_info_coverage OK; check_ui_inventory OK (test_ui_inventory 16/16); check_backup_guard PASS; build_paste_parts --check OK; build_phase477 --check OK; build_report_registry --check OK; build_kb --check OK; test_testonly_files OK; `tools/build_web.sh` build id `08fc226e5e` (only `info.json` and `kb.json` changed on the web side: two new rule entries plus two clarified ones) and `tools/check_pages_dist.py` PASS. Web tests run: infohint (after fixing the new entries), blind, blindstock, assistant, setupadvisor_b2, reports, reports131, reporthub_parse all pass; the full 177-file web suite was not re-run (no web code changed).

## Still open
- Owner decisions: `acct_transfer_mode` location_tagged vs company_wide (open since 14 Oct); whether to switch `drawer_expected_source` to pos_compare or pos; payroll accrual (accountant); repository visibility, default branch, Pages source (unchanged).
- Not done: the 06-1 screen does not yet prefill the POS figures (server side is ready, `_p552_pos_expected`); `gap_map.tsv` has 27 unmapped probes; `docs/audit2/VERIFY_STATUS.md` was not regenerated.
- Not confirmed: any of this on a real Supabase project, the approved pay-request and cheque-clear paths for freight payments (they use the same trigger but were not run end to end), a payroll month that mixes runs and sheets for one person, and the full SQL suite family `tests/sql/run_all_sql.sh` (not run).
- Behaviour to know before pasting: the count-first default makes goods receipts (13-1) need their sealed count on a fresh project; switch `blind_count_on` OFF in the Switchboard to go back.
