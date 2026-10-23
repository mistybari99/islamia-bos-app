# DEMAND_VERIFY: is everything the owner asked for present now? (21 Oct 2026)

> **Superseded in part (23 Oct 2026).** Written 21 Oct 2026. Since then the union merge was finished, the sorted form-code sequence was chosen and applied (21 Oct, phase 543), the public site serves builds of `My-tools` commits (for example `ed3bac3`), and the single repository is `islamia-bos-app` on `Main-Img`. The PRESENT / PARTIAL verdicts below were not re-checked on 23 Oct; verify an item before relying on its verdict. The single repository is `islamia-bos-app`, branch `Main-Img` (owner decision 23 Oct 2026; see `docs/SINGLE_REPO.md`). The earlier text below is kept as history and was not rewritten.


## বাংলা সারাংশ (ছোট)

মালিকের প্রশ্ন: "যা যা চেয়েছিলাম, সব কি ঠিক আছে?" উত্তর: **বেশিরভাগ আছে, কিন্তু কয়েকটা অসম্পূর্ণ।** সব দাবি মার্জ করা কোডের সঙ্গে মিলিয়ে দেখা হয়েছে (শুধু পড়া ও চালানো, কোনো live Supabase ছোঁয়া হয়নি)।

- **আছে (PRESENT):** গ্লাস থিম (`web/theme_glass.css/js`, `index.html`, বিল্ড করা dist-এ আছে); বাম মেনুর ভাঁজ-করা footer (লোকেশন, ভাষা, থিম; 21/21 টেস্ট পাস); Back = ঠিক আগের পাতা + ২/৩ ধাপ + "মূল পাতা" বোতাম (14/14 টেস্ট); ছাপা ফর্ম কোড বদলায়নি (18 Oct-এর আগের বেসলাইন `6bf2f6f`-এর সঙ্গে হুবহু এক, ফেজ 8-478 বাইট-সমান); demo-leak গার্ড OK; ব্যাকআপ private-repo গার্ড ও এনক্রিপ্টেড।
- **অসম্পূর্ণ (PARTIAL):** (১) ঘোষণা / করণীয় তালিকা / শিফট পাতা ডিফল্টে **মেনুতে দেখা যায় না** (সুইচ OFF হলে পুরো পাতাই লুকায়), অথচ আপনি বলেছেন মূল ফিচার জায়গামতো দেখাবে, শুধু ভেতরের সেটিং OFF থাকবে। (২) আপনার শব্দ-তালিকা (সেভ / ডেট / অ্যাপ্রুভ) পুরোনো ফাইলের ৯৪টি লেখায় এখনো আগের শব্দ। (৩) অন্য ব্যবসার পাতা (Variants, Cheque/PDC, Schemes, Tinting, Import-Export) মালিকের মেনুতে দেখা যায়, আর phase 122-এ ৫টি অন্য-ব্যবসার টেমপ্লেটের নাম বসানো। (৪) পুরোনো টেস্ট ফাইলে ২৩৭টি roster-ধরনের নাম (বেসলাইনে বাঁধা)। (৫) "লোকেশন অপশন মার্ক ডাউন/আপ" ঠিক কী বোঝাতে চেয়েছেন নিশ্চিত নই: footer ভাঁজ আছে, তবে লোকেশন ব্লক উপর-নিচ সরানোর আলাদা বোতাম নেই। (৬) notify workflow-তে private-repo গার্ড নেই (backup-এ আছে)।
- **মালিকের সিদ্ধান্তে পরে (DEFERRED):** ফর্ম নম্বর সাজানো, দুই-স্টেট লেআউট ডিজাইন, X3 সোশ্যাল, X5 ক্যামেরা (আসল ফোনে টেস্ট), ব্যবসার পুরো ফিচার show/hide।
- **যাচাই করা যায়নি:** live Supabase / live সাইটে কী আছে, আসল ফোনে চেহারা, Drive ব্যাকআপ, progress board (চ্যাটের artifact)।

---

## 0. How this was checked

Everything below is a read-only check of the merged tree (branch `claude/supabase-readonly-audit-xo3qkp`, tip `5e8981d` plus one docs commit). Nothing was written to the live Supabase project; nothing was pushed to the public repository. Disk: 45 percent used (`df -h /`).

Sources of demands:

1. The owner decision ledger, `docs/RECOVERY_AUDIT.md` section 4 (R1-R12, F1-F14, G1-G12).
2. The owner's own typed messages of the session transcript `109c3315-...jsonl` (both copies; about 130 Bengali messages of 16 to 18 Oct) and the messages after the context compaction (19 to 21 Oct, about 45 messages). Extracted with a small Python script (user role, text only); the table in section 3 quotes the few words that matter.
3. The recent owner statements listed in the task (N1-N20 below).

Commands run (all read-only, results quoted in the tables):

| command | result |
|---|---|
| `python3 tools/check_no_demo_leak.py` | OK |
| `python3 tools/check_numbering.py` | PASS (0 failures); `check_paste_order.py` OK (255 phases, no duplicates, none missing) |
| `python3 tools/check_ui_inventory.py` | OK: nothing lost, nothing renamed silently (11,081 baseline items, 222 through aliases) |
| `python3 tools/check_info_coverage.py` | OK: every rule added in phase 80 or later has an info entry |
| `python3 tools/build_report_registry.py --check`, `build_paste_parts.py --check`, `test_testonly_files.py`, `check_backup_guard.py` | all OK / PASS |
| `node tools/web_build.js --out <scratch>/dist` | builds (222 files); `dist/index.html` references `theme_glass.js?v=...`; `dist/theme_glass.css` and `dist/theme_glass.js` exist; `dist/app.css` contains the `glass-dark` rules; `dist/core.js` contains `BOS_NAVSTACK` |
| `python3 tests/web/run_all.py navfold_test navstack_test ...` | see section 4 |
| form-code diff against `6bf2f6f` | identical (section 2, N5) |

---

## 1. Owner decision ledger (RECOVERY_AUDIT section 4) checked against the merged code

Status words: PRESENT, PARTIAL, MISSING, DEFERRED-BY-OWNER, CANNOT-VERIFY.

### 1.1 Rules and process

| ID | Demand | Status | Proof | Fix plan |
|---|---|---|---|---|
| R1 | Demo / fictional staff never in the repo, DB, docs | PRESENT (tests: see N6) | `CLAUDE.md:3-9`; `python3 tools/check_no_demo_leak.py` prints OK; `.github/workflows/no-demo-leak.yml`; `git ls-files | grep -i -E "demo|imagined|real_life|story"` shows only the guard files and `docs/HISTORY_CLEANUP_RUNBOOK.md`; `web/data/kb.json` has no roster name | none (test caveat in N6) |
| R2 | No demo push; history can be cleaned later | PRESENT (tooling) | `docs/HISTORY_CLEANUP_RUNBOOK.md`, `tools/make_clean_branch.sh`; the history rewrite itself is not done and was not asked for yet | owner says when |
| R3 | Owner approval modes (self / named / logged / off) | PRESENT | `supabase/phase80.sql:8-9` (`owner_approval_mode`, `owner_approver_role`); `phase80.sql:112` | none |
| R4 | Salary and other payments from any account, settings end to end | PRESENT | `supabase/phase87.sql:10-17` (money_accounts, payment source on the event types); routes `moneyaccounts`, `moneycontrols` in `web/ia.js` | none |
| R5 | Every form entry reaches the ledger and the reports | PARTIAL | `docs/FORM_LEDGER_LINKAGE_AUDIT.md`; the wiring exists in phases 80-99 but `accounting_on` is OFF and the live database is not readable from here | after the owner pastes the SQL and switches `accounting_on` on, run the "check all" page and the day-book / journal reconciliation (`balancecheck`, `ledgerlinks` screens) on real entries |
| R6 | Every decision is a setting with a safe default | PRESENT | `rules` table + `set_rule`; `python3 tools/check_info_coverage.py` OK (every rule since phase 80 has an entry) | none |
| R7 | No more decision questions | PRESENT (process) | `docs/HANDOFF.md:21`; this audit asked none | none. `PLAN_NEXT.md` D-06 / D-15 / item 65 rest on stale facts (see RECOVERY_AUDIT 4.4) and should be corrected |
| R8 | Main features visible at their proper place, only inner settings OFF | **PARTIAL** | `web/ia.js:35` (`ruleOn`) and the records `announce`, `todo`, `shifts` use `ok: (c) => ruleOn('announce_on' / 'todo_on' / 'shift_on')`: while the switch is OFF (default, `phase130/131/132.sql`) the whole screen is not offered in the menu, Home or search. Every other route is gated by role only. | Make the three entries visible to the owner and management when the switch is OFF and open an "off - turn it on in Switchboard" state (the screens already refuse server-side). Change `ok` to `(c) => c.own || ruleOn(...)` plus an off notice in `announce.js`, `todo.js`, `shifts.js`; then run `announce_test`, `todo_test`, `shifts_test`, `ia_test`. Not done here: the tests assert the hidden state |
| R9 | Phase numbers in the old style, in order, no conflict | PRESENT | `check_numbering.py` PASS; `tests/sql/ORDER.txt` 255 phases, duplicates none; highest file `phase539.sql`; our 480-554 became 479-498; adv collisions became 506-528; union phases 529-539. The owner's guess (about 150-200) was answered and accepted (L5701-L5776: "যা করা লাগবে করো, কনফ্লিক্ট না হলেই হচ্ছে") | none |
| R10a | Printed form codes (e.g. 02-1) must not change | PRESENT | see N5 | none |
| R10b | Pretty sequence + short names + project guide md | DEFERRED-BY-OWNER | `docs/NUMBERING.md`, `tools/numbering_map.json:38` `"form_groups_approved": false`; `tools/renumber.py` refuses to change form codes without approval | owner approves the map, then `renumber.py --apply` |
| R11 | Owner word list: common words stay English in Bangla mode; Save = সেভ, Date = ডেট, Approve = অ্যাপ্রুভ | **PARTIAL** | `tools/apply_owner_words.py --dry-run web/*.js` reports **94 strings still to change** (older and advanced-line texts); `MERGE_CHECKLIST.md` decision 6 says only our strings were converted on purpose | Run `python3 tools/apply_owner_words.py web/*.js` (idempotent), then `check_ui_inventory.py` (add aliases), `lang_all_test`, `catpick_test`, `c1_test`, `scan_test`; one commit. Not done here because the string tests of the advanced line compare exact words |
| R12 | Base platform (free plan, Staff ID + PIN, role matrix, count-first, red control, 3 language modes) | PRESENT | phases 8-478 are byte-identical to `6bf2f6f` (loop over `git ls-tree 6bf2f6f supabase/`: no CHANGED, no GONE) | none |

### 1.2 Features requested on our line

| ID | Demand | Status | Proof | Fix plan |
|---|---|---|---|---|
| F1 | Two specialists debate the audit; one agent designs compact pages | PRESENT (docs) | `docs/ARCHITECTURE_DESIGN.md`, `docs/IA_CONCEPT.md` | build is deferred (F4) |
| F2 | Live progress board visible all the time | CANNOT-VERIFY | it was an artifact of the chat, not a file of the repo | recreate on request |
| F3 | Full CRM | PARTIAL | screens `crmleads crmtasks crm360 crmconsent crmdupes crmlists crmvalue crmfeedback crmloyalty crmcoupons tiers` in `web/ia.js`; ledger notes that parts D/E/I live only as reports (RPT-C3, phases 458-468) | confirm in the ledger which of D/E/I need their own screen; otherwise accept |
| F4 | Compact page design, many options in short space, no form name dropped | DEFERRED-BY-OWNER | `docs/ARCHITECTURE_DESIGN.md`; owner: "ডিজাইন পরে" (L8083) | start when the owner says |
| F5 | "i" sign with an explanation on critical settings | PRESENT | `web/infohint.js`, `web/data/info.json` (701 entries), `check_info_coverage.py` OK | none |
| F6 | Staff ask for salary / advance in the app, approver named, date; same for parties and suppliers | PRESENT | routes `payrequest partyrequest payapprovals payreqsettings` (`web/ia.js`); `web/payrequests.js`; phase 120 | none |
| F7 | News-ticker announcements, TO-DO list, shift schedule | PARTIAL | code present: `web/announce.js`, `todo.js`, `shifts.js`, phases 130-132; but the three screens are hidden while their switches are OFF (R8) | same fix as R8 |
| F8 | 193-report master list, grouped, question-driven | PRESENT | `web/data/report_registry.json` (`total: 193`), `web/reporthub.js` (route `#/reports/hub`), `reporthub_ask.js`, `build_report_registry.py --check` OK | none |
| F9 | Website, Facebook autopost, AI agents, camera / OCR built, linked later through the Connect Center | PRESENT (OFF) | `web/website.js`, `connect.js`, `ai_core.js`, `scan_items.js`, `scan_native.js`; `tools/social_publish.py`; `.github/workflows/social.yml`; route `connect` (owner only) | X3 screens and X5 phone test: see N16 |
| F10 | Exact Back, 2-3 steps, Main point | PRESENT | see N9 | none |
| F11 | Everything done so far live on the web | CANNOT-VERIFY | the live site and the live database are not readable from here; the web bundle builds and the SQL chain is documented in `docs/LIVE_DELTA.md` | owner uploads the built `web/` and pastes the parts in `docs/paste_parts/` (`setup-all.html`) |
| F12 | SQL copy-paste links, fewest parts, one-click copy page | PRESENT | `docs/paste_parts/setup-all.html`; `python3 tools/build_paste_parts.py --check` OK | none |
| F13 | Backups on phone and Drive | PARTIAL | repo side PRESENT (`.github/workflows/backup.yml`, `tools/backup_crypto.py`); the Drive folder "Islamia BOS backup 2026-10-18" is outside the repo | CANNOT-VERIFY the Drive copy; owner opens the folder |
| F14 | Phase numbers 480 / 490 / 500 looked wrong | PRESENT | = R9 | none |

### 1.3 Requirements recorded on the advanced line

| ID | Demand | Status | Proof | Fix plan |
|---|---|---|---|---|
| G1 | Liquid Glass themes | PRESENT | N1 | none |
| G2 | Collapsible left menu, location block | PRESENT (see N2 for the "up/down" wording) | `web/nav.js:343-351`, `web/styles.css:325-340`, `navfold_test` 21 pass / 0 fail | see N2 |
| G3 | Every business separate; strict isolation; no cross-business transactions; master dashboard owner-only | PRESENT (switch OFF) | `supabase/phase122.sql` (org_units), phases 123, 132, 133; `web/bizctx.js`, `web/org122.js`, route `organization`; scope switch default OFF | the isolation test between two businesses is PLAN_NEXT item 3 (TODO): run `phase123_test.sql` after the owner decides to switch scope on |
| G4 | Intercompany later, per pair, OFF | DEFERRED-BY-OWNER | ledger Stage E | later |
| G5 | Import-export, few currencies | PRESENT (UI visible, see N10) | route `impexp`, `web/impexp124.js`, phase 124 | see N10 |
| G6 | Fashion: variants | PRESENT (UI visible, see N10) | route `variants`, `web/variants125.js`, phase 125 (`variants_on` default OFF) | see N10 |
| G7 | Dealership: cheque / PDC, principal schemes, tinting | PRESENT (UI visible, see N10) | routes `cheques`, `schemes`, `tinting` (`web/ia.js:192-194`), phases 127-129 | see N10 |
| G8 | One profile per business; people of a business never see the group | PRESENT | route `profile`, `web/profile134.js`, phase 134 | none |
| G9 | Create places of a business from the app, guided new business | PRESENT | `web/places135.js` (273 lines), route `organization`, phase 135 | none |
| G10 | Per-business rule changes, bots, books, accountants (MCQs 1-4 unanswered) | CANNOT-VERIFY | no code evidence either way; owner said on 19 Oct "I cannot give anything now, you decide" (L718) | decide as the specialist: rules and books stay global until the owner switches scope on; record in `docs/DECISIONS.md` |
| G11 | Who-sees-what, invoice after sale, print / message templates, landed cost, bill payment, categories, item photos | PRESENT | routes `invoiceview billpay landed categories itemimg purchaseprint` and `web/tpl_*.js`, `tplpicker.js` | none |
| G12 | Audit-2 fixes (profit truth, books truth, stock safety, transfers, manufacturing cost) | PRESENT (duplicated, switches OFF) | routes `cost116var cost116queue cost116gl cost116drv cost116stage`; our 499-505 kept under their own OFF switches (`docs/LIVE_DELTA.md` section 8) | do not switch both on |

---

## 2. Recent owner statements (task list) checked one by one

| # | Demand (owner words, short) | Status | Proof | Fix plan |
|---|---|---|---|---|
| N1 | Glass theme must exist ("আমার গ্লাস থিম") | **PRESENT** | `web/theme_glass.css` (226 lines), `web/theme_glass.js`; `web/index.html:18` (theme list `glass-light`, `glass-dark`), `:24` (`BOS_THEME.list`), `:27` (`<link rel=stylesheet href=theme_glass.css><script src=theme_glass.js>`); picker in `web/nav.js:16` and `:319`; `tools/web_build.js:9,36,116` (CSS merged into `app.css`, JS loaded in head, precached). Built dist: `dist/index.html` contains `theme_glass.js?v=5972f54a02`, `dist/app.css` contains `glass-dark`. `node tests/web/glass_test.js` (run in the git checkout): **282 passed, 9 failed**; the 9 failures are all "non-glass theme identical to the pre-glass base 35f8f7d" (dark / light / classic home, pos, form) and mean later shell changes, not a missing glass theme; contrast checks (103 token pairs, worst 4.74:1) pass | optional: refresh the 9 base comparisons in `glass_test.js` to the current non-glass look; real-phone look is not verified |
| N2 | Left side bar fully visible; location option can go "mark down / up" | **PARTIAL** (bar PRESENT; wording CANNOT-VERIFY) | Drawer with a collapsible footer (chevron; location switch, language, theme, online dot, log out): `web/nav.js:335-350` (`#nav_foot`, `foot_tog`, `bos_navfoot` remembered per device), `web/styles.css:325-340`, location box `nav.js:235-257` (`drawLocBox`, `curLoc`, `setCurLoc`). `navfold_test`: **21 pass, 0 fail** at 360x740 (default collapsed, toggle, persists after reload, no horizontal overflow). Reorder controls exist for favourites only: `nav.js:46,503,534` (Move up / down / top / bottom). A literal "move the location block up / down" control does not exist (grep of `nav.js`, `locations.js`, `places135.js` for up / down / reorder finds nothing for the location block). `RECOVERY_AUDIT.md` 4.3 G2 and section 7 item 3 already flag this wording as unconfirmed | Default today is collapsed, so on first open the location choice is hidden behind the chevron. Proposed (small, in `nav.js` + `styles.css`): (a) open by default when the person has 2 or more places; (b) add Up / Down buttons on the footer blocks (location, language, theme) saving the order in `localStorage` `bos_navfoot_order`; test in `navfold_test.js`. Needs one screenshot from the owner only if the intended meaning is different |
| N3 | Main features visible at their proper place; only inner settings OFF by default | **PARTIAL** | = R8: `announce`, `todo`, `shifts` are not offered while their switch is OFF; all other 214 routes are offered by role. `web/ia.js:35`. | R8 fix plan |
| N4 | Show / hide of whole main features is a later owner decision | DEFERRED-BY-OWNER | An owner "Hide" choice already exists (`web/ia.js:390` `B.optviews.hidden`, route `optviews`, `web/optviews.js`), so the later decision has a place to go | none |
| N5 | Printed form codes (e.g. 02-1) must NOT change | **PRESENT** | The 43 form codes found in the form files `web/forms*.js`, `formscreens.js` are identical at `6bf2f6f` and at HEAD (`diff /tmp/c_old.txt /tmp/c_new.txt`: IDENTICAL; sample `01-1 01-2 02-1 04-4 06-5`). Every `supabase/phaseN.sql` and `_test.sql` of 6bf2f6f with N <= 478 is unchanged at HEAD (no CHANGED, no GONE). `tools/numbering_map.json:38` `form_groups_approved: false` and `renumber.py` refuses form changes. The only text changes in the form files since 6bf2f6f are labels and the brand list (word list, pay_mode field) | none |
| N6 | No demo / fictional data anywhere | **PARTIAL** | `check_no_demo_leak.py` OK for app code, SQL, kb.json, tools, workflows; no `DEMO_*`, `IMAGINED_*`, `REAL_LIFE_*` file is tracked; invented template samples are neutral ("Sample item A", `web/tpl_samples.js:1`); org seeds are generic (`phase122.sql:156-175`: group, sweets business, no person). Not clean: 54 old test files still carry **237 roster-style name hits**, frozen by `tools/demo_leak_test_baseline.json` (may go down, never up). `docs/IA_CONCEPT.md:283` had one such name in a sketch: **fixed in this task** (commit `84ff5d8`) | Rewrite the 54 test files with `test_*` identifiers file by file (`python3 tools/check_no_demo_leak.py --write-baseline` after each batch), top of the list: `sign_test.js` (16), `attendance_test.js` (11), `supabase/phase27_test.sql` (20), `phase13_test.sql` (10), `phase25_test.sql` (10). Separate task, test-only |
| N7a | Agents never write the live Supabase | PRESENT (repo side) | `CLAUDE.md:12`; `supabase/phase84_test_project_only.sql:1-8` (guarded, default OFF, "never paste into live"); `tools/test_testonly_files.py` OK; no tool in `tools/` writes with a service key except the GitHub Actions the owner configures (`backup.yml`, `notify.yml`, `x1_job.py`: bots with their own least-privilege accounts, run by GitHub, not by an agent) | none |
| N7b | ... and nothing was written live by earlier agents | CANNOT-VERIFY | there is no read access to the live project in this task | `docs/MERGE_CHECKLIST.md` "Not done" lists it as not done; the owner's own query results (RECOVERY audit, 20 Oct) matched the local build (0 differences in 2,891 function texts, `docs/LIVE_DELTA.md`) |
| N8 | No more decision questions to the owner | PRESENT | `docs/HANDOFF.md:21`; this audit and `MERGE_CHECKLIST.md` "Decisions" record choices instead of asking | none |
| N9 | Back returns to the exact previous screen; also 2-3 steps back; Main button | **PRESENT** | `web/navstack.js` (stack in sessionStorage, 30 entries, `back(n)`, `main()`); `web/app.js:59-61` (Main button and Back-2 / Back-3 shown when the chain is deep enough), `app.js:617-618` (`goback`, `navmain`); label `web/i18n.js:43` `mainscr` = Main; loaded `web/index.html:38`; present in `dist/core.js`. `node tests/web/navstack_test.js`: **OK navstack 14 checks** | none |
| N10 | Other businesses stay separate; no other-business templates / details; sweets first and complete | **PARTIAL** | Separation is built (G3, switch OFF by default). But other-business detail IS in the product: (a) five screens for other trades are in the owner's menu with no business gating: `variants` (fashion), `cheques`, `schemes` ("asian, berger" in the keywords), `tinting` (paint), `impexp` (`web/ia.js:190-194`; `ok` is `c.own || ...`); their rules are OFF (`variants_on` etc.), so they do nothing, but they are visible; (b) `supabase/phase122.sql:146-153` seeds five template stubs by name (`dealership`, `hardware_paint`, `technology`, `construction`, `online_store`, status `not_implemented`, empty module list). Nothing else (no workflow, no data) | Smallest fix: in `web/ia.js` give the five records `ok` that also requires a small new helper (for example `B.biz.hasTemplate('fashion')`, to be added in `web/bizctx.js`) so they show only when the chosen business has that template and the rule is ON; keep all code. For (b) leave the stubs (they are inert names and removing them changes a pasted phase file, which the build rules forbid) or add a new phase file that marks them hidden. Then run `ia_test`, `check_ui_inventory.py` (add aliases) |
| N11 | Sweets business first and fully complete | PARTIAL | the sweets path is complete in code and tests (POS, production, costing, transfers, accounting); `docs/PLAN_NEXT.md` still lists 16 TODO, 10 NOT REPRO, 23 OWNER items (profit source of truth D-08, VAT method, overhead true-up D-11, contribution margin, daily sales-vs-stock check, return-to-factory document ...) | work the PLAN_NEXT TODO list after the owner pastes the SQL; the NOT REPRO items first need a local reproduction |
| N12 | Owner word list (সেভ, ডেট, অ্যাপ্রুভ) | **PARTIAL** | = R11 (94 old strings left; our strings converted: `rg` shows 154 uses of সেভ, 204 of ডেট, 122 of অ্যাপ্রুভ) | R11 fix plan |
| N13 | 360 px mobile layout | PRESENT, see section 4 for the run | tests run at 360x740 (`navfold_test`, `rptb4_test` ...), 109 test files measure `scrollWidth`; `MERGE_CHECKLIST.md` records the 20 px overflow fix in `web/catpick.js` | real phone not verified |
| N14 | Numbering / form-code sequencing deferred | DEFERRED-BY-OWNER | = R10b | none |
| N15 | Two-state layout design deferred | DEFERRED-BY-OWNER | `docs/PLAN_NEXT.md:141` item 66 "not started". Note: `web/switchboard.js:19-26` already has a switch-level "Layout: Default / All on / Revert to defaults snapshot" (the shell-level version of it, covering only optional "people" sections); the compact page design is not built. `PLAN_NEXT.md` item 66 and `HANDOFF.md:27` disagree about this | correct the sentence in `PLAN_NEXT.md` item 66 |
| N16a | X3 social deferred | DEFERRED-BY-OWNER | `docs/PLAN_NEXT.md:145` item 70 (needs Meta / WhatsApp account and public media URL); `HANDOFF.md:54` | owner supplies the account |
| N16b | X5 camera deferred (phone test) | DEFERRED-BY-OWNER | `PLAN_NEXT.md:146` item 71; code present (`scan_items.js`, `scan_native.js`) | owner device test |
| N17a | Backup private and safe | **PRESENT** | `.github/workflows/backup.yml:36-41` refuses to run unless the repository is private; `tools/backup_crypto.py` encrypts every table file (scrypt + HMAC, passphrase only in the owner's secret); `tools/check_backup_guard.py` PASS ("guard first, fails closed, no data artifact upload"); dump goes through the least-privilege ops bot, "no service_role key" (`backup.yml:5`) | note in `backup_crypto.py`: the home-made container has had no independent review; `age` or `gpg` is the stronger option |
| N17b | Notifications private and safe | PARTIAL | `tools/notify_digest.py` sends only through the owner's own Gmail secrets to the owner, supports `--dry-run`, and respects the rule `notify_email_on` (`supabase/phase46.sql:122`, default `true`, an older owner-approved default); but `.github/workflows/notify.yml` has no "repository must be private" check like `backup.yml` | copy the 6-line private check from `backup.yml:36-41` into `notify.yml` and `automation.yml`; trivial but touches workflows, so not done here |
| N18 | Agent rules in `CLAUDE.md` (check before every commit) | PRESENT | `CLAUDE.md`; `.github/workflows/no-demo-leak.yml`; the check printed OK before the commit of this task | none |
| N19 | "Build discipline": new SQL in a new phase file, safe to paste twice, journals balance | PRESENT | `docs/MERGE_CHECKLIST.md` Verification: 255 phases, 0 errors on the first and the second paste; `ORDER.txt` check PASS | none |
| N20 | Owner asked: where did the lost items (glass, side bar ...) go | PRESENT (explained and restored) | `docs/RECOVERY_AUDIT.md` section 1; both are back in the merged shell (N1, N2) | none |

---

## 4. Web test runs (headless Chromium, 360x740, mocked RPCs; copy of the tree)

Command: `python3 tests/web/run_all.py <suite names>`; logs in the scratch folder. Result of the demand-related suites:

| suite | what it proves | result |
|---|---|---|
| `navfold_test` | collapsible side bar footer, location / language / theme, 360 px | exit 0, **21 pass / 0 fail** |
| `navstack_test` | exact Back, Back 2/3, Main | exit 0, **14 checks OK** |
| `glass_test` (run in the git checkout, it needs history) | Liquid Glass tokens, contrast | 282 pass / 9 fail (the 9 = "non-glass themes identical to the pre-glass base", see N1) |
| `rptb4_test` | no horizontal scroll at 360 px on the report tabs | exit 0, 0 of 135 failed |
| `reporthub_test` | report hub (F8) | 101 of 101 |
| `announce_test`, `todo_test`, `shifts_test` | F7 screens (when switched on) | all 0 failures (82, 67, 74 assertions) |
| `payrequests_test` | F6 | 0 failures |
| `org122_test`, `places135_test`, `profile134_test`, `locations_test` | G3, G8, G9, places | ALL OK / 0 failures |
| `variants125_test`, `impexp124_test` | other-business screens (N10) | 0 failures (they work; the issue is visibility) |
| `ia_test`, `nav2_test`, `optviews_test` | menu registry, drawer, owner Hide | 0 failures / 58 pass |
| `infohint_test`, `notifications_test`, `site_pages_test`, `dashx_test` | F5, bell, public pages 360 px, dashboard | 0 failures (site pages: "English page still fits 360px" PASS) |
| `theme_test` | themes | exit 0 with **1 assertion failure**: "owner: Sell is the first/largest element of Home" (layout wording of the advanced line, not a missing theme) |
| `errlog_test` | error log | exit 2: test crashes (`TypeError ... reading 'message'`), same family as the non-zero list in `MERGE_CHECKLIST.md` |

Not re-run here: the other ~160 suites. `MERGE_CHECKLIST.md` (Verification) records the full 186-suite run of 20 Oct: every suite ends like the advanced line alone or better, with these non-zero as before: a11y (axe-core missing), catpick, controls, errlog, glass, glass_b2, swupdate (need git history), landed_pw, nav, rollout, scan, sec2_itemimg, stockx. (A first attempt to repeat the whole run was stopped after about 30 minutes: it needs more than one hour on this machine. An old log folder from the 20 Oct run was found in the scratch area and was NOT used as evidence.)


## 5. Totals

Rows counted by status (62 rows in sections 1 and 2; several rows are the same defect seen from two demands):

| status | rows |
|---|---|
| PRESENT | 37 |
| PARTIAL | 13 |
| MISSING | 0 |
| DEFERRED-BY-OWNER | 8 |
| CANNOT-VERIFY | 4 (F2, F11, G10, N7b) |

The 13 PARTIAL rows are 9 distinct open items:

1. R8 / F7 / N3: announce, todo and shifts are hidden while their switch is OFF (fix: show them, with an off notice).
2. R11 / N12: 94 strings still use the old words (fix: run `apply_owner_words.py`, adjust tests).
3. N10: five other-trade screens and five template names are visible (fix: gate by business template).
4. N6: 237 roster-style name hits in 54 old test files (fix: rewrite with `test_*` names).
5. N2: no literal up / down for the location block; footer collapsed by default (fix: open by default with 2+ places, add up / down).
6. N17b: `notify.yml` and `automation.yml` lack the private-repository check (fix: copy it from `backup.yml`).
7. R5: ledger linkage unproven live (owner pastes, then switch `accounting_on`).
8. F3: CRM parts D / E / I only as reports.
9. F13 / N11: Drive copy not checkable; sweets "complete" still has the PLAN_NEXT TODO list.

No row is MISSING: nothing the owner asked for is absent from the merged tree. Trivial and safe fix made in this task: one roster-style name removed from `docs/IA_CONCEPT.md:283` (commit `84ff5d8`). All other fixes are listed but not made, because they change screens that tests assert or touch workflows.


## 6. What could not be verified

- The live Supabase project and the live web site: no access by rule. What is deployed there, and whether the owner has pasted the 13 parts, is unknown (F11, N7b).
- Real-phone look and touch behaviour: Liquid Glass look, 360 px on a device, camera / OCR under the new CSP, offline cold start (`MERGE_CHECKLIST.md` "Not done").
- The Google Drive backup folder (F13) and the chat-only progress board (F2).
- The exact meaning of "location option mark down / up" (N2): two readings are covered (collapsible footer, favourites reorder); the literal third reading (reordering the location block) is not built.
- Per-business rule scope (G10): never answered by the owner.
- The 94 old strings (R11) and the 237 test-name hits (N6) are counted, not yet changed.


---

## 7. Fix log (21 Oct 2026, same branch)

The owner said: fix ALL partial items, no more questions. Every decision below was taken by the specialist and is recorded here. No SQL phase was added (no new phase file, no `delta03.sql`, `docs/paste_parts` and `docs/LIVE_DELTA.md` are unchanged): all fixes are web code, tests, workflows and docs. Nothing was written to the live Supabase project and nothing was pushed to the public repository.

| Item | Rows closed | What changed | Decision |
|---|---|---|---|
| 1. Main features visible | R8, F7, N3 | `web/ia.js`: `announce`, `todo`, `shifts` now use `c.own \|\| <grant> \|\| ruleOn(switch)` (grants `announce_post`, `todo_assign`, `shift_manage`). While the inner switch is OFF the owner and any grant holder see the entry in the drawer, Home, search and category page; the screen (already server-driven) shows the notice, now worded "Off: ... Turn on in Settings (announce_on / todo_on / shift_on)". The Home bar, the Home to-do card and every request stay OFF (unchanged). Tests `announce_test`, `todo_test`, `shifts_test` assert: OFF + owner = visible, OFF + grant holder = visible, OFF + other staff = not offered. | Other staff are not offered an entry that has nothing for them until the switch is ON. Checked every other `ia.js` record: no other entry is hidden by a switch (the only `ruleOn` uses were these three); the Home "owner board" uses `owner_board_on`, which is ON by default and is not a menu entry. No explicit owner decision to hide anything else exists (N4 stays: the owner's own Hide choice, route `optviews`). |
| 2. Owner word list | R11, N12 | `python3 tools/apply_owner_words.py web/*.js` run (diff reviewed: bn and mix slots only, `en` and code untouched): 94 strings in 46 files, for example `save: সংরক্ষণ` -> `সেভ`, `তারিখ` -> `ডেট`, `অনুমোদন` -> `অ্যাপ্রুভ` (related words such as অনুমোদনকারী and অনুমোদিত stay, as the tool defines). 79 UI-inventory label aliases (each with a reason) in `tests/ui_inventory/aliases.json`; `tools/test_ui_inventory.py` and the daybook string assertion adjusted. | `web/data/info.json` already had none of the old words (checked: 0 hits), so the (i) entries are consistent; `check_info_coverage.py` OK. `web/data/kb.json` and docs keep ordinary prose (the words there are explanations, not button or label text) and were not changed. |
| 3. Other-business screens | N10, G5-G7 visibility | `web/bizctx.js`: new `B.biz.otherTrade()`, `B.biz.hasTemplate(...codes)`, `B.biz.template()`; a business without a template is the original sweets business; the drawer signature includes the template so the menu redraws. `web/ia.js`: `variants`, `cheques`, `schemes`, `tinting`, `impexp` get `ok: otherTrade() && (old access rule)`. Result: the sweets owner (template `food_manufacturing`, or no organization data) does not see them in the drawer, Home, search or category page; the routes stay registered and live and still open by link; a business with another template (or the owner "all businesses" view that contains one) shows them. New `tests/web/bizgate_test.js` (sweets hidden, organization data missing hidden, two-business switch, "all" view, second business without template hidden, route still opens, 360 px). `ia_test` updated. `check_ui_inventory.py` OK without aliases for these (routes unchanged). | The five template-name stubs of `phase122.sql` stay: they are inert names with status `not_implemented`, shown disabled and labelled "Not built yet" only inside the owner-only Organization screen and the new-business guide; they appear in no sweets menu or report. Old phases are not edited and no new phase was added, because marking them again as `not_implemented` would change nothing. No other-business data or detail was added. |
| 4. Side bar | N2, G2 | `web/nav.js`, `web/styles.css`: the location block has explicit "move higher" / "move lower" buttons (44 px, with words for screen readers). Position `0` = top of the drawer under the search box (always visible), `1` / `2` / `3` = first / second / last block inside the collapsible footer (`1` = as before). Kept per person on the device under `bos_locpos_<id>`. There is no generic per-user preference table in the system (favourites have their own RPCs), so localStorage under the person's own key is the mechanism. The footer opens expanded by default when the person has 2 or more places; the person's own toggle (`bos_navfoot` 1 / 0) always wins. `navfold_test` stays green: single place = collapsed by default (as before); new 2+ places section: open by default, buttons, order persists after reload, top position, no overflow at 360 px. | The wording "mark down / up" is read as "move higher / lower"; if the owner meant something else a screenshot will settle it, nothing else is blocked. |
| 5. Roster-style names in old tests | N6, R1 | 234 hits in 54 test files (web suites, `phaseN_test.sql`, `tests/sql/test*.sql`, `tools/test_fingerprint_bridge.py`, `assistant_intents.json`) rewritten to `testa` ... / `TestA` ... (alphabetical order of the old names kept; letters and digits only, because a staff id must be 3-20 letters or digits). Expected values untouched. Two app texts had roster-like examples: `web/i18n.js` staff id hint (`rahim01` -> `staff01`) and the invoice preview sample (`karim02` / a customer name -> `cashier01` / `Sample customer`). The frozen baselines were updated with this note: `tests/ui_inventory/baseline.json` (the 3 hint texts, same change) and `tools/demo_leak_test_baseline.json` (now `{}`: no test file carries a roster name any more). | `check_no_demo_leak.py` prints OK with an empty baseline. No old non-test phase SQL was touched; the `_test.sql` files are tests. |
| 6. Workflows | N17b | `notify.yml`, `automation.yml` and `owner_summary.yml` (it also mails private figures) carry the same "Refuse to run in a public repository" step as the FIRST step of the job, failing closed. `tools/check_backup_guard.py` now checks all four workflows (guard first, fails closed). | `social.yml` publishes public posts and handles no private figures: not guarded on purpose. |
| 7a. R5 form to ledger | R5 | Cannot be closed from code: `accounting_on` is OFF and the live database is not readable from here. The needed live probe is below (read-only). | Owner runs it after pasting the SQL and switching `accounting_on` on. |
| 7b. F3 CRM parts D / E / I | F3 | Accepted as reports (RPT-C3, phases 458-468): the repository does not define what a dedicated D / E / I screen would contain, and building new CRM screens means new phases, screens and an owner delta (too large for this fix pass, and it would invent scope). The CRM screens A, B, C, F, G, H stay as they are. | If the owner names one missing screen it is added as its own package. |
| 7c. F13 Drive copy, N11 sweets "complete" | F13, N11 | Not fixable in code: the Drive folder is outside the repository; the `PLAN_NEXT.md` TODO list (16 TODO, 10 NOT REPRO, 23 OWNER items) is a separate work list that needs the live paste first. | Unchanged. |
| 7d. G10 per-business rule scope | G10 | Decided (the owner said "you decide" on 19 Oct): rules, books and bots stay GLOBAL until the owner switches `org_scope_on` on; then per-business scope is a separate stage. | Recorded here. |
| 7e. N15 | N15 | `PLAN_NEXT.md` item 66 and `HANDOFF.md:27` disagree about the two-state layout (the switch-level Layout presets exist, the compact page design is not built). Left as is: the design is deferred by the owner. | none |

### Live probe for R5 (read-only, the owner runs it after the paste)

1. After switching `accounting_on` on and setting `accounting_start_date`: `select public.rule_on('accounting_on');` must return `true`.
2. Open the app screens `#/balancecheck` ("check all") and `#/ledgerlinks`; every form and screen should show a posting path or a stated reason.
3. For one real day: day book total (screen `daybook`) against the journal for the same day (screen `accounts`, report of journal entries); `select (select count(*) from journal_entries) as entries, (select count(*) from journal_lines) as lines;` before and after a "Post now" shows the lines grow in pairs. Any difference is a gap to report, not to fix by hand.

### Evidence of the fix pass

| Check | Result |
|---|---|
| `check_no_demo_leak.py`, `check_info_coverage.py`, `check_ui_inventory.py` (11,084 items, 301 aliases, 0 lost), `check_numbering.py`, `build_phase477.py --check`, `build_paste_parts.py --check`, `build_report_registry.py --check`, `check_paste_order.py`, `check_backup_guard.py`, `test_ui_inventory.py` (16 checks), `test_testonly_files.py`, python tool tests | all OK / PASS |
| `bash tools/build_web.sh --out <scratch>/dist` | builds (222 files); nothing uploaded |
| SQL: the 16 changed `phaseN_test.sql` files, old text against new text, each on a fresh LOCAL throwaway Postgres 16 built from `tests/sql/ORDER.txt` up to that phase | identical pass / fail counts in every file (for example phase8: 106 / 1 both, phase21: 74 / 2 both, all others 0 fail); the local cluster and `/tmp/pg*` were deleted afterwards. `tests/sql/test4/6/8.sql` (ad hoc scripts, one name each) were not run: only data tokens changed |
| Web: full `tests/web/run_all.py`, 187 suites, exit codes and assertion lines counted | 9 suites with a non-zero exit: `catpick_pw`, `catpick`, `controls`, `errlog`, `glass_b2`, `glass`, `scan`, `sec2_itemimg`, `swupdate`. Compared with the merged baseline `8a25d49` run in a separate worktree: `catpick_pw`, `catpick`, `controls`, `scan`, `sec2_itemimg` fail the same way there; `glass`, `glass_b2`, `swupdate` need git history (sandbox copy, listed in MERGE_CHECKLIST); `errlog` failed 2 timing assertions only under load and passes alone (88 / 0, before and after). Assertion failures with exit 0 (`items2`, `theme`, `rollout`) are identical in the baseline. One new failure found by the full run (`customers_test` searched the old name fragment) was fixed in the test and passes. No new failures. |
| Navigation and new behaviour | `navfold_test` 36 pass / 0 fail (360 px); `bizgate_test`, `ia_test`, `announce_test` (82), `todo_test` (67), `shifts_test` (74), `b2_test`, `nav2_test`, `optviews_test` (58), `org122_test`, `places135_test`, `variants125_test`, `impexp124_test`, `dealer127_test`: 0 failures |

Owner steps: none for SQL (no new phase, no delta). Web: build with `bash tools/build_web.sh --out <folder>` (or use the checked build) and upload when ready; then on a real phone check the drawer (location block buttons, footer open with 2+ places) and, if wanted, switch on `announce_on`, `todo_on`, `shift_on` in Settings.

## Fix log: five suites

The five web suites that failed on the baseline were run alone, the failing assertion lines were read, and each was classified. Counts are assertion failure lines, not only exit codes.

| Suite | Root cause | Class | Fix |
|---|---|---|---|
| `catpick_test` (3 fails) | Owner word list (`fcc7a4a`): in Bangla mode Category / Sub-category / Item are written in Bangla letters (ক্যাটাগরি, সাব-ক্যাটাগরি, আইটেম); only mix mode keeps Latin. The test still demanded Latin in Bangla mode. | stale test (c) | Assertions rewritten to the new rule, same intent: bn must NOT use the Latin words, mix must NOT use the Bangla-letter forms, en and mix identical, bn title has ক্যাটাগরি and mix title has Category. |
| `catpick_test` (found by the rewrite) | `catpick.js` `r_required` Bangla text still had the Latin words "Item Category". | real defect (a), text | Now "জরুরি — নতুন আইটেম ক্যাটাগরি ছাড়া সেভ হবে না". |
| `catpick_pw_test` (1 fail) | Same rule. Browser run showed two screen labels still Latin in Bangla mode: the breadcrumb of `#/categories` and the title of `#/catreport`, both from the registry `web/ia.js`. | stale test (c) + real defect (a), text | `ia.js`: bn slot of `categories` and `catreport` now ক্যাটাগরি. Two `label` aliases with reason added to `tests/ui_inventory/aliases.json`. Test assertion now checks bn = Bangla letters and no Latin Category, mix = Latin and no ক্যাটাগরি. |
| `scan_test` (2 fails) | (1) `qty` Bangla text is `Qty`, which is the owner-list exception (Qty stays Latin in every mode). (2) `itemimg.js` mentions `scan_itempick` as the CSS selector `[data-act="scan_itempick"]` and in a comment, so the "no other file uses this handler name" check hit a second file. | stale test (c) | (1) only the key `qty` with value `Qty` is exempt from the "Bangla letters" check, every other string still must have Bangla letters. (2) comments and `[data-act=...]` selector mentions are removed before the clash check; a second handler or data-act attribute elsewhere is still caught. |
| `sec2_itemimg_test` (5 fails) | The test used signed URLs on `https://mock.local/`, but the page CSP `connect-src` (correctly) only allows `https://*.supabase.co`, so `itemimg.js` could not fetch any picture. Real signed URLs are on `*.supabase.co`. After that, one assertion expected exactly 1 sign-in callback, but `app.js` (bos112) now registers its own sign-out listener. | test environment (b) + stale count (c) | Mock host is now `https://mock.supabase.co/` (routed in the test; the CSP is not touched). The callback check is `>= 1`; itemimg's own listener stays proven by the SIGNED_OUT / user switch / token refresh assertions that fire every registered callback. |
| `controls_test` (3 fails then a 30 s click timeout) | Real defect (a). `controls.js` `rebuild()` called `classList.add('ctl-grp')` / `add('ctl-hid')` on every pass even when the class was already there; that still queues an attribute mutation, which the group's own observer read as an outside change, cleared the signature and rebuilt the trigger every 30 ms (about 50 rebuilds in 1.5 s, trigger detached while being clicked, "element is not stable"). | real app defect (a) | `rebuild()` adds a class only if it is missing. Same-value writes removed in `a11yfix.js` too (`tog()` aria-pressed and the skip-link text), which also fed observers. After the fix the trigger is stable (0 mutations in 1.5 s). Side benefit: `a11y_test` 59/1 -> 60/0 and `itemimg_test` now pass. |

No assertion was deleted or skipped. No SQL changed.
