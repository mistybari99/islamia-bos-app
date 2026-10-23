# RECOVERY ROADMAP: one plan to get every lost feature back without losing the new ones

> **Superseded (23 Oct 2026).** The union merge this roadmap plans is done (phases 529 to 539 and later are in `docs/PASTE_ORDER.md`); the canonical branch is `Main-Img`, not `recovery/union`. The public site serves builds of `My-tools` commits (for example `ed3bac3`). Treat the steps below as history; the open work is in `docs/SINGLE_REPO.md` and `docs/NEW_PROJECT_SETUP.md`. The single repository is `islamia-bos-app`, branch `Main-Img` (owner decision 23 Oct 2026; see `docs/SINGLE_REPO.md`). The earlier text below is kept as history and was not rewritten.


Written 20 Oct 2026 on branch `claude/supabase-readonly-audit-xo3qkp`. Evidence is in `docs/RECOVERY_AUDIT.md`; the rehearsal is `tools/recovery_merge.py` (result: `docs/RECOVERY_MERGE_DRYRUN.md`). Bengali one-pager: `docs/RECOVERY_SUMMARY_BN.md`.

Rules that hold for every step (from `CLAUDE.md`, `docs/BUILD-RULES.md`): no agent writes to the live Supabase project (the owner pastes SQL after review); no demo or fictional names anywhere (`python3 tools/check_no_demo_leak.py` must print OK before every commit); new SQL only in new numbered phase files, never edit an old phase, always paste-twice safe; every journal entry balances; new behaviour is OFF by default; screens are registered only through `web/ia.js`; the public repository is changed only by the owner or on his explicit go.

**Target state:** one canonical branch (`recovery/union`, cut from this branch) that contains everything of both lines; one reproducible web build (`tools/build_web.sh`) that produces what the owner's phone loads; one SQL chain whose order is written down; the public site and the live database both traceable to commit ids.

## 0. Summary table

| Phase | Goal | Calendar time | Agent effort | Owner effort | Risk |
|---|---|---|---|---|---|
| P0 | stop the bleeding: freeze, bridge, probe | 1 day | 0.5 agent-day | 30 min | low |
| P1 | recover lost web features by merging adv into ours | 4-6 days (3 agents in parallel) | 6-9 agent-days | 2 phone checks, 30 min each | medium |
| P2 | recover the database side as new numbered phases | 1-3 weeks | 10-15 agent-days (needs a PostgreSQL 16 server) | 3-6 paste sessions, or one fresh project | high |
| P3 | remaining audit items (backup, security, stock, profit, cash, cost) | rolling | 10+ agent-days | secrets, decisions, real data | medium |
| P4 | deferred design, form numbering, X3, X5, intercompany | when the owner says | 8+ agent-days | decisions | low |

## 1. P0: stop the bleeding (today)

| Step | Who | What | Acceptance | Rollback |
|---|---|---|---|---|
| P0.1 | owner | **Freeze.** No more upload of `web/` to the public repo. No more SQL paste from either line until P0.3 is read. | nothing changes on the site or database for 24 hours | n/a |
| P0.2 | owner decides, agent prepares, owner pushes | **Bridge: put the previous site back.** In the public clone make a branch `restore-4ec5e56` and run `git revert b67ea29` (the upload is web-only: 159 files, +51,217/-91, so one revert undoes it and leaves the SQL pages `sqlparts/` and `setup-all.html` alone). Check `git diff 4ec5e56 HEAD -- . ':!sqlparts' ':!setup-all.html'` is empty. The owner merges/pushes it. Keep the new build reachable: tag `b67ea29` as `web-ours-v5` before reverting. | glass themes selectable, left menu chevron works, `#/organization`, `#/profile`, new-business flow open on the phone; the old service worker `bos-sw-610e0641de` takes over | `git revert` the revert (tag `web-ours-v5`). Cost of the bridge: the new screens of ours (navigation history, XB/XC, CRM, report hub, 360 px header fix) are not visible until P1 ships |
| P0.2b | owner | Alternative if the owner prefers to keep the new site: skip P0.2. Then the lost list in the audit (section 2) stays lost until P1. | n/a | n/a |
| P0.3 | owner pastes, agent reads results | **Read-only database probe** (Appendix A: SELECT statements only). Paste the result text back. | answers: is `lock_check` still the bos113 version, did the `biz_items` fix replace the body, what is in `_fix_fn_backup`, which adv and ours objects exist | read-only, nothing to roll back |
| P0.4 | owner + agent | **Name the branch of record.** Recommended: create `recovery/union` from this branch (Step P1.1), set it as the GitHub default branch when P1 passes. The current default `ccr-78d03e25-k7ksyo` is the oldest line (`dbecc25`). | one line in `docs/HANDOFF.md` and `docs/GO_LIVE.md`: "the web build is made by `tools/build_web.sh` from branch X at commit Y" | n/a |
| P0.5 | agent (after owner OK) | **Preserve.** Tag the adv tip (`backup/adv-0bc142b`), the live-old public commit (`backup/pub-4ec5e56`) and ours (`backup/ours-551eb71`) in the repositories that own them. Tags are pushed only with the owner's yes. | `git tag -l 'backup/*'` shows three tags | delete tag |
| P0.6 | agent | **Stop the wrong advice.** Fix `docs/GO_LIVE.md` step 3 (no more "copy `web/`"; point to the build tool and this roadmap) and correct `docs/PLAN_NEXT.md` 1.3, 1.4, D-06, D-15 (bos112 and card settlement are in adv phases 112 and 109). Docs only. | review by reading | git revert |

Effort P0: 0.5 agent-day, 30 minutes of the owner.

## 2. P1: recover the lost web features (merge adv into ours, keep every new screen)

Principle: adv is the base for the **shell** (index.html, nav drawer, sw.js, theme, bundle tool); ours is the base for **new screens and logic** (navstack, X1-XC, CRM, reports, money wave). Every route and every control of both lines must still exist after the merge. The merge is done on a new branch; this branch stays untouched until the owner approves.

### 2.1 Steps
| Step | What | Command / file | Acceptance |
|---|---|---|---|
| P1.1 | Rehearse and create the branch | `git fetch origin && python3 tools/recovery_merge.py --keep` (prints the scratch worktree and temp branch), or by hand: `git switch -c recovery/union` then `git merge --no-commit origin/ccr-9c1f9be7-3s9qnz` | 78 conflicted files listed (same as `docs/RECOVERY_MERGE_DRYRUN.md`) |
| P1.2 | Non-web conflicts | `.gitignore`: union of both. `docs/BUILD-LOG.md`: keep both sections. `docs/PASTE_ORDER.md`: keep ours and append an "Imported from the advanced line" section (P2.1). Tests: take adv version for adv-only tests, ours for ours; **never commit the 7 conflicted `.png` screenshots** (`git checkout -- tests/web/*.png`) | no conflict markers (`grep -rn '^<<<<<<<' .`) |
| P1.3 | SQL files | for the 23 colliding numbers keep ours in place; bring adv's under new names (P2.1 map); the 31 non-colliding adv phases keep their number | `python3 tools/check_numbering.py` PASS |
| P1.4 | Demo guard | rewrite roster-style names in the 8 adv test files with `test_*` names (list in the audit, W5); review `web/tpl_samples.js` | `python3 tools/check_no_demo_leak.py` prints OK |
| P1.5 | The 16 web conflicts, one by one (table 2.2) | see table | each file: `node --check`, its own test, `tests/web/run_all.py` suite subset |
| P1.6 | Wire the 51 adv scripts and 82+46 routes | `web/ia.js` union of `rec(...)`; `web/index.html`; `tools/web_lazy.json` (classify our 80 new scripts: eager only if the first screen needs them, otherwise lazy; keep POS, forms, Back (`navstack.js`) eager) | `python3 tools/check_ui_inventory.py` OK, `tests/web/ia_test.js`, `order_test.js`, `lazy_test.js`, `order_lazy_test.js` |
| P1.7 | Wording | adopt adv wording (owner word list) everywhere; add alias entries for the 142 renamed labels and the 22 moved controls with the reason "owner word list, phase 108" (script it from the checker output) | ui inventory OK with aliases |
| P1.8 | Info signs | write (i) entries for the 47 adv rules without one (`org_scope_on`, `profit_truth_mode`, `dealer_*`, ...) in `web/data/info.json` | `python3 tools/check_info_coverage.py` OK |
| P1.9 | Build | `tools/build_web.sh --out <scratch>/dist` (needs `terser`, `esbuild`; installs with npm once). Recompute the CSP hash for the inline theme script; confirm every external host used by ours (Tesseract data, jsDelivr) is in `connect-src` / `script-src`; bump nothing by hand (the build stamps `bos-sw-<id>` itself; `tools/bump_sw.py` is retired for the public build) | `tests/web/sec2_csp_test.js`, `swupdate_test.js`, `lazy_test.js`, `glass_test.js`, `navfold_test.js`, `coldstart_test.js`, `errlog_test.js` pass |
| P1.10 | Full web suite | `python3 tests/web/run_all.py --copy <scratch> --out <scratch>` (109 suites of ours + adv suites), then `git checkout -- tests/web/*.png` | 0 failures, no hidden assertion failures (count assertion lines, exit code alone hid failures once) |
| P1.11 | 360 px visual pass | headless Chromium at 360x740 for: Home, POS, drawer open/collapsed (each theme incl. glass), `#/organization`, `#/profile`, `#/switchboard`, `#/xcunsold`, `#/cakejobs`, `#/announce`, a long form | no horizontal overflow, no console error |
| P1.12 | Preview, not cut-over | publish the dist to a **separate preview location** (a Pages branch or a sub-folder `next/` of the public repo), not to the root | owner opens the preview on his phone and ticks Appendix C |
| P1.13 | Cut-over | owner approves; push the dist to the root; update `PUBLISH_NOTES.md`/`DEPLOY_CHECKLIST.md` (build id, source commit, SQL phase list) | site shows the new build id; old phones update after one reopen |

### 2.2 The 16 conflicted web files and how to resolve each
| File | Ours changed | adv changed | Rule |
|---|---|---|---|
| `web/index.html` | +6/-1 (nav history script, scripts) | +13/-7 (CSP, glass, preload, bundle tags) | start from adv's head (CSP, `interactive-widget`, theme script with 5 values, fonts swap), then the union of scripts; the built `dist/index.html` is what ships; recompute the CSP sha256 |
| `web/ia.js` | +107/-5 | +55/-7 | union of routes; on a name clash keep both and rename ours (see `scan`); run `bos-organise` rules (`docs/IA_RULES.md`) |
| `web/nav.js` | +10/-3 (pay-request counts) | +36/-17 (glass, fold, business switcher, optviews, dues) | take adv, re-apply ours' `prq` counter; keep the favourites reorder |
| `web/sw.js` | +13/-1 (camera precache) | +25/-2 (stamped cache, precache) | take adv's design; put ours' camera files into the build's precache list (`web_lazy.json`), not a hand list |
| `web/app.js` | +9/-3 (Back via `navstack`) | +76/-11 (cold start, late sale, bizctx) | union; both hooks live in different functions |
| `web/pos.js` | +13/-5 | +95/-29 | union; run `pos*_test.js` and the 1,369-item speed test |
| `web/scan.js` | add (X5 item recognition) | add (phase 90 scan a bill) | **two different features, one filename**: keep adv `scan.js` (route `scan`), rename ours to `scan_items.js` and its routes to `scanitems`; update `scan_core.js`, `scan_native.js`, `photo.js`, `sw.js` precache |
| `web/stockx.js` | +127/-19 (tracking map UI) | +13/-13 (wording) | take ours, re-apply adv wording |
| `web/costing.js`, `daybook.js`, `filters.js`, `itemmaster.js`, `recipes.js`, `salereturn.js`, `switchboard.js`, `i18n.js` | small to medium | wording and bos100/bos107 hooks | take adv text, re-apply ours' additions (i18n: keep ours' 223 added keys) |
| `web/styles.css` | +6/-1 (header wrap fix) | +26 (drawer fold, contrast) | union; keep `header.top { flex-wrap: wrap }` |

### 2.3 Acceptance for P1 as a whole
- `tools/check_*.py` and `tools/build_phase477.py --check`, `tools/test_testonly_files.py`, `tools/build_report_registry.py --check`: all eight green.
- Route diff: every route in `bundle-manifest.json` of `4ec5e56` (75 mapped routes + 52 core pages) **and** every route in ours' `ia.js` opens without error (script: compare `rec(` names and open each in headless Chromium).
- Owner checklist (Appendix C) passes on the preview.
- Rollback: tag `web-ours-v5` and `backup/pub-4ec5e56`; the cut-over is one commit, reverted with `git revert`.

Effort: 6-9 agent-days; split in three parallel agents (shell + tests; ia/nav/routes + wording + info; build + CSP + visual pass), one checker agent. Owner: two phone checks.

## 3. P2: recover the database side as new numbered phases (no edits to old phases)

### 3.0 Gate (decision before any SQL work)
Run P0.3. Then choose, with the owner (agent recommends **B**):
- **A. Patch live.** Write union phases, test them, owner pastes. Keeps the live project; keeps unknown live-only state (for example `_fix_fn_backup`, whichever body `lock_check`/`biz_items` really have).
- **B. Fresh project from one tested chain.** Live holds 10 test-like sales, 1 customer, 0 journal rows, 0 stock rows (audit 3.3). Build the union chain on a throwaway PostgreSQL 16, test it, create a new Supabase project, paste once, re-import the item dictionary (`web/data/item_dictionary.json`, `tools/gen_item_import.py`), recreate users. Result is reproducible and has no unknown objects. The old project stays untouched as the fallback. Cost: one day of owner re-setup.
- The owner decides; nothing here is written to live by an agent.

### 3.1 Renumbering map (rules of `tools/renumber.py`: ours <= 478 is never changed; 500 is skipped; adv phases keep their text, only file names and the first comment line change)
The 23 numbers that exist on both lines with different content. Left: adv original (what the live database already has). Right: the name the file gets in `supabase/` of the union branch.

| adv original | imported as | adv content (short) | | adv original | imported as | adv content (short) |
|---|---|---|---|---|---|---|
| phase80 | phase506 | free-cost flag, intake bot | | phase92 | phase518 | invoice on screen, share |
| phase81 | phase507 | setup recommendations | | phase93 | phase519 | print/message templates |
| phase82 | phase508 | stock guards (E1-E4) | | phase94 | phase520 | security review fixes |
| phase83 | phase509 | form vs screen, transit, offline POS | | phase95 | phase521 | cash drawer |
| phase84 | phase510 | audit trail | | phase96 | phase522 | opening stock, cost waiting |
| phase85 | phase511 | stock moves to the GL, card settlement | | phase97 | phase523 | landed cost |
| phase86 | phase512 | Telegram channel | | phase98 | phase524 | `_acct_docs` merge |
| phase87 | phase513 | QA fixes, owner can approve | | phase99 | phase525 | bill payment options, inbox masking |
| phase88 | phase514 | one report cost source | | phase120 | phase526 | report speed |
| phase89 | phase515 | final bodies of re-created functions | | phase131 | phase527 | verified reports stage 1 |
| phase90 | phase516 | scan a bill | | phase132 | phase528 | master data separation |
| phase91 | phase517 | who sees what | | | | |

The 31 adv-only numbers keep their number (100-118, 121-129, 133-135). Test pairs follow (`phaseN_test.sql` -> new name). A test-only `phase130_test.sql` on adv does not collide with our real phase 130; rename to `phase_adv130_test.sql`. Internal text such as `raise exception 'phase87 ...'` is a non-comment line: the tool reports it BLOCKED; leave it, the text is a label only (state it in each file's first comment line: "imported from adv phase 87 as phase 513").

**Canonical order of the imported block** (adv's own, from `tests/sql/paste_order.env`): 72-79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 90, 91, 89, 92, 93, 95, 94, 96, 97, 98, 99, 100-118, 120-129, 131-135. After renaming: 506, 507, 508, 509, 510, 511, 512, 513, 514, 516, 517, 515, 518, 519, 521, 520, 522, 523, 524, 525, 100-118, 526, 121-129, 527, 528, 133-135.

**Chain for a fresh build (union):** base 8-79, then the imported adv block in the order above, then ours (80-99, 120, 130-132, 140-143, 300-329, 400-478, 479-505), then the reconciliation phases of 3.2. This is the order the live database actually received them (adv Oct 14-15, ours Oct 18), so it is the order known to run.

### 3.2 Union reconciliation phases (new numbers from 529; each is paste-twice safe, OFF by default)
| New phase | Content | Source of truth |
|---|---|---|
| 529 | `lock_check` union: ours bos87 `_m_lock_exc` **and** adv bos113 `period_lock_owner_mode` / `closed_period_owner` | adv `phase113.sql`, ours `phase87.sql` |
| 530 | `biz_items` union: keep bos402 hook + bos112 returns netting + bos14 cost join | adv `phase112.sql`, public `part12.sql` reference body |
| 531 | the other 9 functions created whole by both: `_acct_docs`, `_daybook_lines`, `_p27_pl`, `_recipe_lines_ok`, `_sale_stock_out`, `customer_dues`, `sale_return`, `stock_receive_transfer`, `stock_reconcile` (one phase per two functions to keep diffs reviewable: 531-535) | build both orders on PostgreSQL, diff bodies, merge by hand |
| 536 | the 113 shared patched functions: a **body-tag audit** (`select` listing which tags each live body carries) and re-patches only where a tag is missing | Appendix B list |
| 537 | exception-kind constraint union (kinds written by adv: `closed_period_owner`, `late_docs_locked`, `stock_negative`, `transit_short`...) | adv 113/114/115 vs ours 89/94/120 |
| 538 | `_fix_fn_backup`: add a primary key (or drop it after the owner has read it) | audit advisor |
| later | feature de-duplication (3.3) | |

Because exact-text patches and body guards fail in different ways (ours patch by text; adv refuses unknown tags), every union phase starts from the **tag audit** of 3.2/536 and states which tags it keeps. Tests: both orders (adv then ours; ours then adv) on a throwaway PostgreSQL 16, paste-twice, `tests/sql/run_all_sql.sh` against the existing baseline, and a before/after snapshot with every switch OFF (default-state parity), as `PLAN_NEXT` section 6 did.

### 3.3 Remove the double work (decide per feature; keep files, do not edit them)
| Feature | Ours | adv | Recommendation |
|---|---|---|---|
| dues net of applied advance | 503 `dues_net_advance_on` | 113 `dues_net_advance`, `customer_dues_net113` | adv canonical (already live); mark 503 "superseded", keep OFF |
| transfers: over-send, paused place, partial receipt | 499 | 114, 115 (`transfer_needs_stock`, `transfer_late_receive`, ...) | adv canonical; compare partial-receipt behaviour on a test database before choosing |
| unknown unit, return factor | 501 | 114 | same |
| `biz_items` returns netting | 502 | 112 | adv canonical (union function from 530) |
| intermediate as ingredient | 504 | 116 `semi_finished_ingredient116` | adv canonical |
| stock tracking map | 505 | none | keep (ours only) |
| Settings advisor | none | 81, 101 | keep adv, register switches of ours (task for P3) |
| Reports | 400-476 hub | 131 verified reports | keep both; route names are distinct |
| Owner approval | 80, 86, 87 modes | 87 "owner can always approve" | **owner decision**: R3 says the owner chooses the mode; ours implements it; verify adv 87 does not undo it after the order adv -> ours |

### 3.4 Live-only objects to account for
`lock_check` bos113 owner-mode (recreate in 529), `biz_items` bos112 netting (530; also readable in live `_fix_fn_backup`), `_fix_fn_backup` (538), the 27 no-policy tables not created by ours (all are adv phases; document in `SECURITY_BACKLOG.md`), and the three hand-added blocks of the public `sqlparts` (D12): turn each into a numbered idempotent phase **or** retire it once 529-531 exist.

### 3.5 Acceptance for P2
- `python3 tools/check_numbering.py` PASS with the imported files; `docs/PASTE_ORDER.md` has the union order and a "renumbered from" table; `tests/sql/ORDER.txt` lists it.
- Union chain builds on a throwaway PostgreSQL 16 without error in both orders; every new file pastes twice; `_i2_state()` shows no missing hook; adv suites (112-118, 121-135) and ours (80-99, 120, 130-132, 499-505) pass at baseline.
- Default parity: with every switch OFF, report totals before/after each union phase are identical.
- Owner receives one numbered paste list (not 13 giant parts): small files, each with a one-line check.
- Rollback: before pasting, owner downloads the backup (`docs/OPS_SETUP.md`); each union phase is one function body, restorable from `_fix_fn_backup`-style saved text (the phases save the old body first).

Effort: 10-15 agent-days; requires a session with a PostgreSQL 16 server (this session has only the `psql` client). Owner: 3-6 paste sessions (A) or one project switch (B).

## 4. P3: remaining audit items (from `docs/PLAN_NEXT.md` section 2, re-ordered)
| Item | Owner action | Agent action | Effort |
|---|---|---|---|
| F-03 backup: private destination, secrets, one successful run + one isolated restore | create secrets, decide repo visibility | `tools/check_backup_guard.py` exists; add restore evidence page | 2 d |
| F-04 notifications failed (missing `SUPABASE_URL`) | secrets | dry-run test | 1 d |
| F-10/F-11 live sales are test-like; items untracked; accounting OFF | say which records are real; count opening stock | tracking map review UI (505) after P1 | 3 d |
| Gate E two-business negative test | none | run the adv C1-C3 suites + a persona test with `org_scope_on` ON in a test database | 4 d |
| F-07 anon-executable functions, 69 no-policy tables | run the two queries in `SECURITY_BACKLOG.md` §4 | review, propose revokes (never apply) | 3 d |
| F-06 index / policy advisor findings | none | staging query plans | 3 d |
| Profit truth, cash/card, manufacturing cost items still open on ours (PLAN_NEXT 2.4-2.6) | decisions D-08, D-11 | **first check adv 112-118 already solve them**, then implement only the rest | 5 d |
| Security backlog: Node 20 deprecation, secret scan of history | rotate any found secret | scan | 1 d |

## 5. P4: deferred by the owner
| Item | Status | Trigger |
|---|---|---|
| Two-state layout (defaults saved -> all-on layout -> revert) and compact page design | not started; `docs/ARCHITECTURE_DESIGN.md` | owner says "start design" after P1 is live |
| Printed form-code sequencing and short names (`tools/numbering_map.json`, `form_groups_approved: false`) | plan only | owner approves the map |
| X3 social screens | needs Meta/WhatsApp account and public media URL | owner supplies |
| X5 camera on a real phone | not tested | owner device test |
| Intercompany (Stage E), partnerships view | not built | owner |
| Group ERP C3 questions 1-4 (`HANDOVER_7`) | unanswered | owner |
| Other business templates (construction, online store, technology) | `not_implemented` records only | owner |
| Info `related` fields for 9 ours entries | todo | agent, low priority |

## 6. Conflict-handling rules (apply in every phase)
1. **Never choose a side silently.** Every conflicted file gets a line in the merge log: file, ours change, adv change, rule used.
2. **Shell from adv, new screens from ours** (index.html, nav.js, sw.js, styles, theme from adv; navstack, X1-XC, CRM, reports, money wave from ours). Never drop a route from either side: run the route diff before and after.
3. **Wording: adv's owner word list wins** for common words; add aliases with a reason, do not rename back.
4. **Phase numbers:** ours <= 478 never changes; adv colliding numbers go to 506-528; 500 is skipped; new reconciliation phases start at 529; files are never renamed after they were pasted live; an imported file's first comment line states "imported from adv phase N". A number is never reused for new content.
5. **SQL is additive:** union phases re-create a function from its latest body and keep every older tag; a body guard refuses to overwrite an unknown tag; the old body is saved first.
6. **Order known to run:** adv block first, then ours (the order the live database received). Test the other order too and write down the difference.
7. **Defaults:** every new switch OFF; default parity snapshot must stay identical.
8. **Same feature twice:** keep the one already live (adv), mark the other superseded, never turn both ON.
9. **Public repo:** only the owner pushes; the build tool never deletes files that exist only on the other line (check `tools/build_web.sh` "gone from web/" output before any `--to` run).
10. **Tests and screenshots:** `git checkout -- tests/web/*.png` after every web run; no roster names in tests; count assertion lines, not only exit codes.
11. **Evidence over memory:** a claim "not in the repository" requires a search of all remote branches (`git grep <name> $(git branch -r)`); the bos112 mistake came from skipping that.
12. **Disk:** stop above 90% (the tool checks); remove scratch worktrees and `/tmp/pg*` after each run.

## 7. Rehearsal result (tools/recovery_merge.py, dry run, 20 Oct 2026)
- Source `origin/ccr-9c1f9be7-3s9qnz` (0bc142b), ours `551eb71`, merge base `dbecc255`. 235 ahead, 202 behind.
- **78 conflicted files**: SQL 46 (23 phase numbers x main + test), web 16, tests 13 (3 js, 3 sh, 7 png), docs 2 (`BUILD-LOG.md`, `PASTE_ORDER.md`), other 1 (`.gitignore`).
- Merged cleanly: 1,304 added files (51 web, 89 SQL), 302 modified.
- Checks (conflicts resolved "ours" only to run them): numbering PASS, phase477 OK, report registry OK, backup guard OK; **demo leak FAIL (8 test files), test-only FAIL (same), info coverage FAIL (47 rules), ui inventory FAIL (164 problems)**. Baseline of this branch: 8 of 8 OK.
- The tool created and removed its own scratch worktree and temp branch; this branch and the remotes were not touched. Re-run any time: `git fetch origin && python3 tools/recovery_merge.py`.

---

## Appendix A: read-only probe for the owner (Supabase SQL editor; SELECT only, changes nothing)
Paste each block, copy the result text back. If any statement errors, send the error.

```sql
-- A1. which version tags do the key functions carry? (true/false per tag)
select p.oid::regprocedure::text as fn,
       position('bos112' in d) > 0 as bos112, position('bos113' in d) > 0 as bos113,
       position('bos87'  in d) > 0 as bos87,  position('bos402' in d) > 0 as bos402,
       position('bos98'  in d) > 0 as bos98,  position('bos103' in d) > 0 as bos103,
       position('bos105' in d) > 0 as bos105, position('bos109' in d) > 0 as bos109,
       length(d) as bytes
from pg_proc p, lateral (select pg_get_functiondef(p.oid) as d) x
where p.pronamespace = 'public'::regnamespace
  and p.proname in ('lock_check','biz_items','_acct_docs','_daybook_lines','_p27_pl','_recipe_lines_ok',
                    '_sale_stock_out','customer_dues','sale_return','stock_receive_transfer','stock_reconcile')
order by 1;

-- A2. what did the biz_items fix save?
select fn, saved_at, length(def) as bytes, position('bos112' in def) > 0 as had_bos112
from public._fix_fn_backup order by saved_at;

-- A3. which line's objects exist? (true = present)
select to_regclass('public.org_units') is not null              as adv122_org,
       to_regclass('public.business_profiles') is not null       as adv134_profile,
       exists (select 1 from pg_proc where proname = 'business_place_create135') as adv135_places,
       exists (select 1 from pg_proc where proname = 'profit_truth112')          as adv112_profit,
       exists (select 1 from pg_proc where proname = 'customer_dues_net113')     as adv113_dues,
       exists (select 1 from pg_proc where proname = '_i2_state')                as ours_i2,
       to_regclass('public.pay_requests') is not null            as ours120_payreq,
       to_regclass('public.crm_leads') is not null               as ours_crm;

-- A4. hooks of ours that did not apply (must be empty)
select * from public._i2_state() where not present;

-- A5. switches that are set (not default)
select * from public.rules where value is not null order by 1 limit 200;

-- A6. size of the schema
select (select count(*) from pg_tables where schemaname='public') as tables,
       (select count(*) from pg_proc where pronamespace='public'::regnamespace) as functions;
```

## Appendix B: the 113 pre-existing functions patched or re-created by both lines (P2 body-tag audit list)
```
_acct_all _acct_docs _acct_inv_key _acct_inv_split72 _acct_locked _acct_manage _acct_merge _acct_need _acct_num _acct_paykey
_acct_purchase_alloc _acct_resolve _acct_reverse _acct_sid52 _acct_start _acct_today _acct_view _acct_write _all_locs _avg_next
_base_qty _client_lock _cogs_lines72 _cost_ok _cust_bal _cust_mgr43 _cust_pos43 _cust_stats43 _d43 _daybook_lines _db_date _db_num
_dhaka_today _is_ops _item_base _may _n43 _notif_add _oo_event61 _oo_gate61 _p27_pl _pur_ok _r2_num _r3q_l1_pnl _r3q_l3_shop_pnl
_recipe_cost_ok _recipe_lines_ok _recipe_mgr _recipe_need _sale_stock_out _shadowed52 _stock_exc _stock_guard _sup_balance _sup_open
_today _today43 _unit_factor_base _use_em acct_journal_post acct_mapping_set acct_opening acct_post_pending acct_status biz_cost_ok
biz_items biz_ok can_do can_grant can_loc collect_payment customer_balance customer_directory customer_dues customer_ledger
customer_profile has_grant inventory_vs_gl is_shadow item_new lock_check no_hard_delete norm_mobile partner_calculate pay_supplier
post_purchase production_post production_run_costs quick_expense_add recipe_cost record_sale2 rpt_access rpt_agg_sql rpt_cost_ok
rpt_dims rpt_grant rpt_meas rpt_mobile_ok rpt_tok rule_num rule_ok rule_on rule_txt rule_val sale_return save_purchase set_rule
shelf_life_for stock_opening stock_post stock_receive_transfer stock_reconcile stock_transfer
```
(Method: names referenced as `public.NAME(` in phases >= 80 of both lines, restricted to functions that already exist in phases < 80. 10 of them are created whole by both: `_acct_docs _daybook_lines _p27_pl _recipe_lines_ok _sale_stock_out biz_items customer_dues sale_return stock_receive_transfer stock_reconcile`.)

## Appendix C: owner phone checklist for the preview (30 minutes)
1. Open the preview address on the phone; sign in; Home loads in a few seconds (4 files at start, not 143).
2. Menu (left drawer): chevron at the bottom folds and unfolds the location, language, theme, online and log out block; the choice is remembered after reopening.
3. Theme: Premium Dark, Premium Light, Classic, **Liquid Glass Light, Liquid Glass Dark** can be chosen; each survives a reload.
4. Business: the drawer shows the business switcher (when more than one business exists); `Organization` opens; **Add place**, **New business** guided flow open; `Business profile` opens.
5. Back button: open three screens in a row; Back returns step by step; "Main" returns to the first deep entry (navigation history of ours).
6. New screens of ours still open: Unsold stock, Owner summary, Payment capture, Cake jobs, Riders, Announcements, To-do, Shifts, Pay requests, Report hub.
7. Old screens come back: Dashboard (`dashx`), Templates, Invoice after a sale, Categories, Landed cost, What's new, Report a problem.
8. Switch the phone to aeroplane mode and reopen the app: Home and POS open from the saved sign-in (cold start).
9. Bangla wording: Save is "সেভ", Date is "ডেট", Approve is "অ্যাপ্রুভ" on every screen (owner word list).
10. Tell the agent anything that looks different from before; that goes into `docs/RECOVERY_AUDIT.md` section 2.
