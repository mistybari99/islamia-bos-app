# INTEGRATION REPORT, 24 Oct 2026 (branch Main-Img-v2)

`Main-Img-v2` = `Main-Img` (8ff9d92, left untouched as the fallback) + three branches joined with full history (no squash) + phase 548 ordered + test fixes finished. Local only: nothing pushed, no PR, no GitHub or Supabase change. Measured on a throwaway PostgreSQL 16.15 (own data dir under /var/tmp, port 5611) and Node 22.

## What merged

| Branch (tip) | Content | Merge |
|---|---|---|
| `feat/backup-coverage` (a02e270, 7 commits) | phase 547 (AI settings tables join the dump, `backup_accounts_manifest()`, `backup_storage_buckets()`, one Storage read policy; switches `backup_accounts_on`, `backup_buckets_on` both OFF), backup/restore tools, workflow seal step, guides | clean |
| `fix/web-tests` (9e61190, 9 commits) | web test fixes; form short names got the Bng-Eng text; `info.json` fix; `tag_loss` fixes; WIP handoff note | clean |
| `audit/readiness` (4c613b2) | `docs/READINESS_99.md`, `tests/sql/readiness/`, draft stock_recon_period fix | one conflict (below) |

Phase number collision: the readiness draft `phase547.sql` was renamed to `phase548.sql` on a helper branch `audit/readiness-548` before the merge (references updated in `docs/READINESS_99.md`, the readiness BUILD-LOG entry and the SQL header). The real phase 547 is the backup coverage file.

**Conflicts (every one):** `docs/BUILD-LOG.md` only (both sides appended a new entry at the end). Resolved by keeping both entries. No other conflict.

## Phase 548: ordered into the canonical chain

It changes a report classification, so it was tested before being ordered. Proof (`supabase/phase548_test.sql`, 5 of 5; plus the whole-chain comparison):
- The only function that differs between a build with and without 548 is `stock_recon_period`; no function added or dropped, no rule or table added; grants unchanged (anon no, authenticated yes). A second paste changes nothing. No other database function calls it (only `web/stockrep.js`, which reads the rows array).
- The readiness scenario run on both: with default settings (mode `def`) the output is byte-identical (141 checks). In the advisor modes the only difference is check R17 (`opening + movements = closing`), which fails without 548 and passes with it. That is the intended fix.
- Registered in `tests/sql/ORDER.txt`, `tests/sql/paste_order.env`, `docs/PASTE_ORDER.md` (row 220), paste parts regenerated (part21 now holds 547 and 548), `docs/NEW_PROJECT_SETUP.md` updated. `tools/numbering_map.json` holds form codes only, so it needs no change. If the owner does not want 548, remove those four entries and regenerate; nothing else depends on it.

## Database results (full canonical chain, 261 phase files)

- Fresh build: 0 errors. Every file pasted twice in a row (522 pastes): 0 errors, identical function hashes. The 21 generated paste parts run one after another: 0 errors, identical hashes. Numbers: 2896 functions, 478 tables, 486 policies, 627 rules.
- Against `Main-Img` (8ff9d92) exactly the intended differences: `_backup_tables()` changed (547), new `backup_accounts_manifest()` and `backup_storage_buckets()` (547), `stock_recon_period` changed (548), new rules `backup_accounts_on` and `backup_buckets_on` (both OFF, no value set). No table differences. All other 2891 function hashes and all 625 other rule rows are identical.
- Tests: `phase546_test` 22 of 22; `phase547_test` 15 of 15; `phase548_test` 5 of 5; readiness scenario `def` 122 pass / 19 fail, `rec` 125 / 16, `recx` 136 / 5 (the failure lists equal the stored results of the audit; they are the audit's findings D1 to D10, not regressions; with 548 `rec` and `recx` each gain one pass); `tools/test_backup_coverage.py` 10 of 10 (end to end: backup, wipe, restore, 468 tables identical, 3 logins, photos in 4 buckets); `tools/test_ops.py` 34 OK (1 skipped); `tools/check_backup_guard.py` PASS; `tests/sql/tag_loss_check.sh` NET LOST TAGS 0. The test that talks to Postgres expects socket /tmp and port 5544, so a temporary socket link with that name was made and removed.

## CI checks (all pass)
check_no_demo_leak OK; check_numbering PASS; check_paste_order OK; check_info_coverage OK; check_ui_inventory OK (test_ui_inventory 16 of 16); check_backup_guard PASS; build_paste_parts --check OK; build_phase477 --check OK; build_report_registry --check OK; test_testonly_files OK; build_kb --check OK; `tools/build_web.sh` builds (build id `595647df11`, differs from Main-Img's `a8a8addc5e` because fix/web-tests changed 9 web source files (forms*.js, entry.js, locgroups.js, info.json) and so the files that carry their hashes); `tools/check_pages_dist.py` PASS on it.

## Web tests
177 files (16 superseded skipped). Parallel first pass: 171 pass, 6 fail; re-run alone: a11y, allforms, catpick_pw, lazy pass (port clash or load timeout). Two real failures fixed: `form_names_test` (regex did not accept the third Bng-Eng argument of `L()`) and `infohint_test` (new `backup_accounts_on` why text had two sentences). Final 177 of 177 pass. Tests overwrite tracked screenshots in `tests/web/`; they were restored before every commit.

## Still open
- Not run: `tests/sql/run_all_sql.sh` (the whole SQL suite family), any GitHub workflow, `pages.yml` on GitHub, the backup workflow's new seal step on GitHub, the real Supabase Storage API and bucket policies, any screen on a real phone.
- Web tests are order and port sensitive; run them one at a time for a clean result.
- Readiness defects D1 to D7, D9, D10 and the top-15 gaps in `docs/READINESS_99.md` are still open (only D8 is fixed).
- Owner questions unchanged: repository visibility, default branch rename, Pages source (`docs/SINGLE_REPO.md`). Note `backup_accounts_on` stores names and e-mails: keep the backup repository private.
- The notes in `docs/NEW_PROJECT_SETUP.md` about unverified items still apply.
