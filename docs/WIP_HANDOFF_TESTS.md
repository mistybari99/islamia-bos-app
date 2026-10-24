> **Finished 24 Oct 2026** on branch `Main-Img-v2`: the full `tests/web` suite was run (177 files, 16 superseded skipped), the two remaining failures were fixed (`form_names_test` regex, `info.json` backup_accounts_on why), the BUILD-LOG entry was added. Result 177 of 177 pass. The notes below are the earlier state.

# WIP handoff: web test fixes (branch fix/web-tests, from Main-Img 8ff9d92). Nothing pushed.

Rerun one test: `node tests/web/<name>_test.js` (from the repo root; no argument needed). Tests overwrite tracked PNGs in tests/web: run `git checkout -- '*.png'; git clean -fq -- 'tests/web/*.png'` afterwards.

| Test | Root cause (class) | Status | Rerun | Next step |
|---|---|---|---|---|
| infohint | info.json `rule:price_check_include_freight` why had 2 sentences (1: data bug) | fixed, passes (checked alone; port 8493 is fixed, do not run in parallel) | `node tests/web/infohint_test.js` | none |
| lang_all | S2/S3 rewrote 46 two-argument L() titles, baseline keys no longer matched; also taka sign in an en slot (1: BUILD-RULES 13) | fixed (mix text added, locgroups mix), passes | `node tests/web/lang_all_test.js` | optional: rebuild baseline to drop 45 fixed entries (`LANG_BASELINE_WRITE=1`) |
| listctl, engine, blindstock | smoke.js built the forms table from schema.sql with OLD form codes; phase 543 renumbered, so new codes never loaded (2: fixture). blindstock also had a real bug: entry.js hint keys sb_hint04_3/04_1 not renumbered (1) | fixed, all three pass | `node tests/web/listctl_test.js` etc. | none |
| a11y | same fixture cause; passed 60/60 after the fix (earlier geometry failure not reproduced) | fixed, passes once | `node tests/web/a11y_test.js` | rerun a few times to rule out flakiness |
| items2_b | served ../My-tools/web on fixed port 8197 (3: infra) | fixed, passes | `node tests/web/items2_b_test.js` | none |
| glass_b2 | baseline 35f8f7d predates intended header/form-code changes (2) | fixed: BASE_REF default 36254db, passes | `node tests/web/glass_b2_test.js` | owner may prefer another baseline policy |
| swupdate | test used old make_bundle.sh; real deploy is build_web.sh with per-file ?v=; CSP blocks localhost photo host; make_bundle.sh node --check bug (2, 3) | fixed, 55 pass / 0 fail | `node tests/web/swupdate_test.js` (needs clone with history and /home/user/islamia-bos-app) | note: config.js stamp is not the hash of the protected public copy (exempted in test) |
| catpick_pw_test (superseded) | fixture | passes, removed from superseded.txt | `node tests/web/catpick_pw_test.js` | none |
| glass_test (superseded) | old baseline | stays superseded by glass_b2, documented in tests/web/README_TESTS.md | | none |
| items2_test (superseded) | upload assertion changed in step Img | stays superseded by items2_b, documented | | none |
| tests/sql/tag_loss_check.sh | split by phase number broke the canonical order; scratch cluster was also SQL_ASCII. No real lost tag: qc_list 4-arg replaced by 6-arg in phase432 (2/3) | fixed, NET LOST TAGS 0, exit 0 | start scratch Postgres (below), `bash tests/sql/tag_loss_check.sh` | none |

## Not finished
- Full tests/web run was interrupted: about 78 of ~190 done, all exit 0 except `scan_web_test` (needs env `BOS_REPO_DIR=$PWD`, it does not use _paths.js: rerun with it, or add `_paths` to it). Logs: /tmp/claude-0/runall, /tmp/claude-0/runall2.
- Not done: the remaining tests, BUILD-LOG entry (BUILD-RULES 16), build to /home/user/work-tests-out was run once OK (build 8ad6b76d50); check_ui_inventory, check_info_coverage, check_numbering, check_no_demo_leak all OK at last run.

## Processes
All stopped. Scratch Postgres 16: data dir /var/tmp/pg_scratch_5544, socket /tmp port 5544, UTF8, roles anon/authenticated/service_role/authenticator. Start: `runuser -u postgres -- /usr/lib/postgresql/16/bin/pg_ctl -D /var/tmp/pg_scratch_5544 -o "-p 5544 -k /tmp -c listen_addresses=''" -w start`; stop: same with `-m fast stop`; remove: delete the directory.
