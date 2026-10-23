# NO-LOSS REPORT, 23 Oct 2026

Question: after joining the branches into `Main-Img`, did any finished function, owner decision, switch default or web file change by accident? Answer: **no, except the one intended change (`stock_transfer`, phase 546)**. Everything below was measured locally on 23 Oct 2026 (throwaway PostgreSQL 16.15, Node 22; no network, no Supabase, nothing pushed).

Compared: BASE = `origin/claude/supabase-readonly-audit-xo3qkp` (tip `d91861b`), the source of truth. NEW = `Main-Img` (BASE + merge of `claude/unified-docs-merge` `fe134fa` + merge of `claude/fix-stock-transfer-546` `02276ad` + the files added by this work). Both merges were clean: **no conflicts occurred** (list of conflicts: none). The tip hash is in the final report of the task.

## (a) git diff --stat BASE..Main-Img: only the intended additions

37 files, 1480 insertions, 563 deletions. Grouped:

- From `unified-docs-merge` (docs only): new `BUSINESS_PROCESS_GUIDE.md`, `GROUP_ERP_STAGE_A.md`, `OPEN_OWNER_QUESTIONS_FROM_DAILY_GUIDE.md`, `OPERATIONAL_MANUAL_BN.md`, `SWEET_SHOP_GUIDE.md`, `WORK_TRACKER.md`; rewritten owner guides `docs/guide/OWNER_GUIDE.md`, `PHONE_ONLY_STEPS.md`, `RECOMMENDED_SETTINGS.md`, `ROLLOUT_PLAN.md`, `UAT_CHECKLIST.md` (these five carry all the 563 deleted lines; the previous versions stay in the history of BASE).
- From `fix-stock-transfer-546`: `supabase/phase546.sql`, `supabase/phase546_test.sql`, `tests/sql/ORDER.txt` and `tests/sql/paste_order.env` (one name added), `docs/PASTE_ORDER.md`, `docs/paste_parts/manifest.json`, `part20.sql`, `setup-all.html` (regenerated), `docs/BUILD-LOG.md`, `docs/LIVE_DELTA.md`.
- Added by this work: `.github/workflows/pages.yml`, `tools/check_pages_dist.py`, `docs/SINGLE_REPO.md`, `docs/NEW_PROJECT_SETUP.md`, `docs/START_HERE.md`, `docs/NO_LOSS_REPORT_23OCT.md` (this file, added in the last commit, so not in the numbers above), dated "Superseded" notes (3 lines each) in `RECOVERY_AUDIT`, `RECOVERY_ROADMAP`, `MERGE_CHECKLIST`, `PLAN_NEXT`, `SECURITY_BACKLOG`, `FORM_SEQUENCE`, `DESIGN_ROADMAP`, `DEMAND_VERIFY`, a 2-line comment in `tests/sql/tag_loss_check.sh`, the "Update 23 Oct 2026" section in `docs/DECISIONS.md`, one line in `docs/README.md`.
- **Not touched:** everything under `web/`, `tests/web/`, `android/`, `site/`, `data/`, every old SQL phase file, every other tool, every other workflow.

## (b) Tag-loss check

1. Function-text tags (`bosNN`, `orgNN`, ...) of the two final builds (section c): **0 tags lost**; tags added: `bos114` and `bos115` on `stock_transfer` (phase 546 puts back the stock check and the receiver notice that phase 544 dropped).
2. The repository's own script `bash tests/sql/tag_loss_check.sh` was run on BASE and on NEW. It exits 1 on both with the same line "NET LOST TAGS: 8": the script is stale (it builds a phase 103 baseline in a pre-merge order, so phases 104 and later stop on their own "needs phases 72..103 first" guards; its header says so now). The two reports are identical except the new step `phase546: 1 function changed, lost=-, added bos114 bos115`. So phase 546 loses no tag, and nothing else differs. This script is not a valid proof of the merged chain; the comparison in (c) is.

## (c) Function list: BASE build against NEW build

Both built with `bash tests/sql/final_build.sh` (canonical order in `tests/sql/paste_order.env`) on separate fresh databases: **0 errors** each. Every phase file pasted twice in a row (518 pastes): 0 errors, same function hashes. The 20 generated paste parts run one after another: 0 errors, same function hashes.

| | BASE | NEW |
|---|---|---|
| public functions (name + arguments) | 2894 | 2894, same list (md5 of the sorted names+arguments `a352d3515a99` on both) |
| md5 of `pg_get_functiondef` per function | | 2893 identical, **1 different** |

The one difference: `stock_transfer(integer,integer,uuid,numeric,text,text,uuid)`, md5 `452aa6c8f16809e0ae473bbfd8f0137b` in BASE, `85fbf75e9ce1f871fdbcaa8847e80506` in NEW. Nothing else.

## (d) Rule keys and defaults

`select key, kind, value, default_value from rules order by key`: 625 rows in both builds, **byte-identical** (md5 `b747b0209869`). No owner value is set in either (fresh build). Against the owner's live extract of 23 Oct 2026 (623 rules): all 623 keys exist and **all 623 defaults and kinds are equal**; the two extra keys of the fresh build are `price_check_include_freight` and `transfer_client_reuse_block` (both OFF). All 56 owner-set keys of the live project exist (see `docs/NEW_PROJECT_SETUP.md` section 6).

## (e) Web build

`bash tools/build_web.sh --out <dir>` on BASE and on NEW: build id **`a8a8addc5e` on both**, 224 files each (212 published entries), `diff -r` of the two output folders: **no file differs**. The `web/` folder is identical in both branches (the diff in (a) has no `web/` line). The guard `python3 tools/check_pages_dist.py <dist>` passes on the build (203 JavaScript files checked), and was shown to fail on a copy that had a `.sql` file, a `.csv` in `data/` and a secret-looking value added (5 problems found).

## CI checks run locally on Main-Img (all pass)

| Check | Result |
|---|---|
| `tools/check_no_demo_leak.py` | OK |
| `tools/check_numbering.py` | PASS (0 failures, 0 warnings) |
| `tools/check_paste_order.py` | OK |
| `tools/check_info_coverage.py` | OK |
| `tools/check_ui_inventory.py`, `tools/test_ui_inventory.py` | OK; 16 checks, 0 failed |
| `tools/check_backup_guard.py` | PASS |
| `tools/build_paste_parts.py --check` | up to date |
| `tools/build_phase477.py --check` | up to date |
| `tools/build_report_registry.py --check` | OK |
| `tools/test_testonly_files.py` | OK |
| `tools/build_web.sh` | build `a8a8addc5e` |
| `tools/check_doc_links.py` (not in CI) | 316 findings, 313 before this work; the 3 new ones are the intentional mention of old public-repo files in `docs/SINGLE_REPO.md` |

Not run: `ai-kb` workflow (off by default, needs a repository variable), the integration, backup, notify, automation, social and owner-summary workflows (they need GitHub and secrets), `.github/workflows/pages.yml` itself (never ran on GitHub; checked as YAML only), the SQL test suites `tests/sql/run_all_sql.sh` (not run in this task; `phase546_test.sql` was reported 22 of 22 by the branch author, not re-run here).

## Web test suites (`tests/web`, Playwright with the local Chromium)

193 test files were run (the `superseded.txt` skip list was not applied, so 3 superseded tests ran too). First pass in parallel (3 at a time, 150 s limit, which caused port clashes and timeouts): 169 exit 0, 24 non-zero. The 21 non-superseded failures were re-run one at a time (400 s limit; the six that needed the environment variable `BOS_REPO_DIR` were re-run with it). Final: **181 pass, 9 fail, 3 superseded fail** (`catpick_pw_test`, `glass_test`, `items2_test`, which `run_all.sh` skips by design).

The 9 failing tests: `a11y_test` (1 geometry check of 60), `blindstock_test` (timeout, field not found), `engine_test` (30 s timeout), `glass_b2_test` (dark theme compared with an old base commit), `infohint_test` (rule `price_check_include_freight`: its "why" text has 2 sentences, the test wants 1), `items2_b_test` (supplier picker), `lang_all_test` (46 lines: forms missing a Bangla-English mix text), `listctl_test` (30 s timeout), `swupdate_test` (`make_bundle.sh` fixture failed). These were NOT compared against BASE by running them there, but `web/` and `tests/web/` are byte-identical in BASE and NEW, so the same failures exist in BASE. They are open items, not caused by this work. `infohint_test` points at a small real text fix in `web/data/info.json` (not made here: web files were deliberately not changed).

Running the web tests overwrote tracked screenshot files in `tests/web/`; they were restored with `git checkout` and the new ones deleted before committing.
