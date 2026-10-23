# RECOVERY AUDIT: what was lost when the public site was replaced (20 Oct 2026)

> **Superseded (23 Oct 2026).** The union merge of the advanced line and our line is done: it is the phase chain in `docs/PASTE_ORDER.md` (phases 529 to 539 and later) and the branch that became `Main-Img`; the line `ccr-9c1f9be7-3s9qnz` is an ancestor of it. The public site now serves builds of `My-tools` commits (for example `ed3bac3`), not the build this audit calls `pub-new`. The statements below about what was lost, the branch tips and the live database describe 20 Oct 2026. The single repository is `islamia-bos-app`, branch `Main-Img` (owner decision 23 Oct 2026; see `docs/SINGLE_REPO.md`). The earlier text below is kept as history and was not rewritten.


Status: READ-ONLY analysis. Nothing was written to the live Supabase project, the public repository `mistybari99/islamia-bos-app`, or any branch except this one. The owner reads Bengali; the one-page summary is `docs/RECOVERY_SUMMARY_BN.md`. The plan is `docs/RECOVERY_ROADMAP.md`. The rehearsal tool is `tools/recovery_merge.py` (result: `docs/RECOVERY_MERGE_DRYRUN.md`).

How to read the evidence: `adv` = branch `origin/ccr-9c1f9be7-3s9qnz` (tip `0bc142b`); `ours` = `claude/supabase-readonly-audit-xo3qkp` (tip `551eb71`); `pub-old` = public commit `4ec5e56` (the build that was live); `pub-new` = public commit `b67ea29` (our upload). `file:line` means the line in that ref.

---

## 1. Cause of the loss

### 1.1 One sentence
The live site was built from a different line of work (adv) than the branch whose `web/` folder was uploaded over it (ours). The upload copied our files over the same-named files and left everything else orphaned, so every screen and shell feature that exists only on adv stopped loading.

### 1.2 Evidence chain
1. **Two lines grew from one base.** Merge base `dbecc255` (14 Oct 2026, phases 72-79). adv then added 235 commits (phases 80-135, group/business layer, glass, lazy bundle, CSP). ours added 202 commits (phases 80-99 money wave, 120/130-132 pay requests/announce/todo/shifts, 140-143, 300-329 CRM, 400-476 reports, 479-505 automation/website/AI/camera/orders). Counts: `git rev-list --count HEAD..origin/ccr-9c1f9be7-3s9qnz` = 235, reverse = 202. The two lines were built by different chat sessions that did not see each other.
2. **The public site was always built from adv.** Public history (full clone, 62 commits, read-only) shows eight `web bundle` commits made by `tools/build_web.sh`, each naming its source: `785d2fe` (INT3), `24e53bb` (1ee329c49d), `d1b3a83` (d92f6e1bd3, from `55fd150`), `0d0b14c` (1a9e6c6b70, from `int/audit-fixes` `44311c8`, includes perf/webload `ea5793e`), `5258b87` (b7f8b844b1, from `local-int2` `2907bbc`), `7bb4bc4` (6983e2b5e0, from `local-prof` `7d0e5ba`), `4ec5e56` (610e0641de, "built by tools/build_web.sh from work-loc local-loc @ **0bc142b**"). `0bc142b` is exactly the tip of adv (`git branch -r --contains 0bc142b` = only `origin/ccr-9c1f9be7-3s9qnz`). The live site files were therefore a minified, bundled, lazy-loaded build of adv.
3. **Our guide told the owner to copy `web/`.** `docs/GO_LIVE.md:26`: "Copy the `web/` folder (except `setup-sql.html`) to the public Pages repository used by the app, commit and push it there." Nothing in ours said that the Pages repo was a build of another line. (`docs/PLAN_NEXT.md` section 1.2 learned this only on 19 Oct, after the upload.)
4. **The upload (`b67ea29`, 18 Oct) is web-only: 159 files, +51,217 / -91.** It overwrote 76 same-named files with our unbundled sources and added 83 new files. It deleted nothing. Result: 50 scripts listed in the old bundle manifest are still on the server but no longer referenced by any page (list in 2.2), plus the old `core.js`, `app.css`, `lazy.js`, `theme_glass.css`, `theme_glass.js`, `bundle-manifest.json`.
5. **The new `index.html` is a different shell.** Compare `pub-old:index.html` with `pub-new:index.html`: no CSP meta (old line 5), no `?v=` cache stamps, no preload, no non-blocking font swap, theme list reduced from 5 to 3 values, three separate stylesheets instead of `app.css`, 143 `<script>` tags instead of 4 (`theme_glass.js`, `vendor/supabase.js`, `config.js`, `core.js`). Bytes fetched at start: 4,757,050 in 143 requests now, versus 1,868,752 in 4 requests before.
6. **Our own safety nets did not cover the public site.** The UI no-loss inventory (`tools/check_ui_inventory.py`, baseline 8,823 items) only compares ours with ours. It cannot see a screen that exists on adv. The numbering and demo guards do not look at the public repo either.
7. **Our SQL paste was applied over a database already built from adv.** Public pages `setup-run-1..25` (phases 72-135 of adv) were pasted first (Oct 14-15). Then our 13 `sqlparts` (our phases 8-498) were pasted (Oct 18). Two repair commits show the collision: `33be97d`/`3185918` force `lock_check` back to the phase 6 + phase 87 text, and `ec817cc` restores `biz_items` "from the repository" after saving the old body to `public._fix_fn_backup`. See section 5 (DB risks).

### 1.3 Public history (full list of bundles; none of the older bundles has anything the newest lacks)
| public commit | date | build id | source | notable content |
|---|---|---|---|---|
| `785d2fe` | 14 Oct | 31e160ad85 | integration INT3 | first cache-safe bundle (`?v=`, SW stamp) |
| `f78ef23` | 14 Oct | a70e358993 | + Kbd | keyboard-safe sheets |
| `24e53bb` | 14 Oct | 1ee329c49d | integration | Cat, Img, Opt, PBill, Q4, Pol, Sec; SW precache |
| `d1b3a83` | 14 Oct | d92f6e1bd3 | `55fd150` | dashboard, Liquid Glass, cold start, error log, a11y, whatsnew (CSP left out) |
| `0d0b14c` | 14 Oct | 1a9e6c6b70 | `44311c8` | lazy screens, cost116, transfer challan, recon118 |
| `5258b87` | 15 Oct | b7f8b844b1 | `2907bbc` | org122, bizctx, impexp124, variants125, dealer127-129, reports131 |
| `7bb4bc4` | 15 Oct | 6983e2b5e0 | `7d0e5ba` | phase 134 business profile |
| `4ec5e56` | 15 Oct | 610e0641de | `0bc142b` | phase 135 places under a business, new-business flow; **CSP present** |
| `b67ea29` | 18 Oct | (none) | ours `248c604`-era | our unbundled `web/`, nav history, XB/XC screens, header fix, `bos-sw-v5` |

File-set check: every file in every older bundle also exists in `4ec5e56` (`comm -23` empty for all six older commits), so recovering `4ec5e56` recovers everything the owner ever saw.

Minified versus source: `pub-old` JS is minified single-line output (for example `nav.js` 65,160 bytes in one logical block, `core.js` 1,649,680 bytes). `pub-new` has readable source for the 76 replaced files. That difference is harmless by itself; the loss is caused by the missing bundle/lazy/CSP/stamp logic, not by minification.

---

## 2. Complete inventory of what is missing or regressed

### 2.1 Shell-level capabilities lost (index.html / sw.js / nav.js)
| # | Capability in `pub-old` (= adv source) | State now | Proof |
|---|---|---|---|
| S1 | **Liquid Glass Light / Dark themes** (owner-reported) | not offered, not loaded; a saved `glass-*` choice is ignored and the phone silently falls back to the default theme | adv `web/index.html:18-27` (allowed values, theme list, `theme_glass.css` + `theme_glass.js`), adv `web/nav.js:316` (two select options); ours `web/index.html` theme script allows `dark/light/classic` only; commit `77c4cc3` (Step Glass, bos109), report `docs/briefs_p2p3/step_Glass_REPORT.md` |
| S2 | **Collapsible left menu (drawer) footer** (owner-reported "side bar collapsible, location up/down"): chevron bar; location, language, theme, online dot and log out sit in a collapsed block, default collapsed, remembered in `bos_navfoot`; menu list height 373 px expanded, 560 px collapsed | footer is always open and takes the list space | adv `web/nav.js:337-347`, `web/styles.css` (bos101 block), report `step_Navfold_REPORT.md`, test `tests/web/navfold_test.js`; ours `web/nav.js:329` has the old always-open `.dr-foot` |
| S3 | **Business switcher in the drawer + business brand (name, logo, colour) from the business profile** | gone; the old fixed brand is used | adv `web/nav.js:334` (`B.biz.switcherHTML()`), `web/bizctx.js` (150 lines), ours has no `bizctx.js` |
| S4 | **Content Security Policy** (bos111 M5) pinned by SHA-256 of the theme script | no CSP at all | adv `web/index.html:5`; ours `web/index.html` has no CSP meta; audit finding F-02 |
| S5 | **Cache-safe loading**: every asset URL stamped `?v=<content hash>`; `sw.js` VERSION = `bos-sw-<build>`; install-time precache (bos110, bos114) | static `bos-sw-v5`, no stamps, precache list holds only the camera helpers | `pub-old:sw.js` line 1; adv `web/sw.js:5-10`; ours `web/sw.js` |
| S6 | **Bundle + lazy screens** (bos114 WebLoad): 4 requests / 1.87 MB at start; 59 screens fetched on first use; POS speed with 1,369 items | 143 requests / 4.76 MB at start, all screens eager | `pub-old:bundle-manifest.json` (`core` 59 files, `lazy` 59 files, 75 routes mapped); adv `tools/build_web.sh`, `tools/web_build.js`, `tools/web_lazy.json`, `web/lazy.js`; report `step_WebLoad_REPORT.md` |
| S7 | Non-blocking font CSS (media swap + noscript), `preload` of core, viewport `interactive-widget=resizes-content` (keyboard does not cover buttons) | normal blocking font CSS, old viewport | adv `web/index.html:6,13-14` versus ours `web/index.html:5,12` |
| S8 | **Offline cold start** from the saved sign-in context (banner, POS + queue, 14-day cap) | missing | adv `web/coldstart.js` (135 lines, bos112); hooks in adv `app.js`, `pos.js` |
| S9 | **Error log for a phone-only owner** ("Report a problem" + Problems page, phase 107) | missing | adv `web/errlog.js` (415 lines); routes `reportproblem`, `problems` |
| S10 | Central accessibility helper, keyboard-safe sheets, attention badge strip | missing | adv `a11yfix.js`, `kbdfix.js`, `badges107.js` |
| S11 | "What's new" page with Open buttons | missing | adv `web/whatsnew.js`, route `whatsnew` |
| S12 | One merged stylesheet `app.css` (styles + theme + controls + glass, 103,052 bytes) | three CSS files, no glass | `pub-old:app.css` |

Not lost (checked): the favourites reorder (Move up / Move down / top / bottom) exists in both lines (ours `web/nav.js:43,514,722`). The owner's "mark down / up" for the location option is therefore the S2 chevron, not the favourites reorder. **Interpretation to confirm with a screenshot from the owner** (section 7).

### 2.2 Screens and scripts that exist only on adv (51 files, 0 loaded today)
All 51 merged without a textual conflict in the rehearsal, but none is wired: `index.html`, `ia.js` and `sw.js` conflict.

| Area | Files | Routes (adv `ia.js`) | SQL phase (adv) | Switch / default |
|---|---|---|---|---|
| **Business layer** | `org122.js`, `places135.js`, `profile134.js`, `bizctx.js` | `organization`, `profile` | 122, 123, 132-135 | `org_scope_on` OFF |
| Import-export | `impexp124.js` | `impexp` | 124 | `impexp_on` |
| Variants / large catalogue | `variants125.js` | `variants` | 125, 126 | `variants_on` |
| Dealer (paint + hardware) | `cheques127.js`, `schemes128.js`, `tinting129.js` | `cheques`, `schemes`, `tinting` | 127, 128, 129 | `dealer_*_on` OFF |
| Verified reports stage 1 | `reports131.js` | `reports131` | 131 | `rpt131_on` OFF |
| Reconciliation + manufacturing cost | `recon118.js`, `cost116.js`, `costboard.js` | `stockrecon`, `branchstmt`, `netprofit`, `cost116var/queue/gl/drv/stage`, `costunknown` | 112-118 | switches OFF |
| Look and feel | `theme_glass.css`, `theme_glass.js` | (theme) | none | per user |
| Owner dashboard + charts | `dashx.js`, `dashx_metrics.js`, `charts.js` | `dashx` | 104 | per user layout |
| Print and message templates | `tpl_registry.js`, `tpl_docs.js`, `tpl_labels.js`, `tpl_msgs.js`, `tpl_samples.js`, `tplpicker.js`, `invoiceview.js` | `templates`, `invoiceview` | 92, 93 | owner choice |
| Purchase side | `purchaseprint.js`, `landed.js`, `landed_q4.js`, `optionsx.js` (bill payment, inbox masking) | `purchaseprint`, `landed`, `billpay`, `inboxpii` | 97, 99 | OFF |
| Item master | `catpick.js` (category / sub-category), `itemimg.js` (photos on POS) | `categories`, `catreport`, `itemimg` | 100, 102 | photos OFF |
| Cash and books | `cashdrawer.js`, `books85.js`, `books96.js`, `posfail.js` | `cashdrawer`, `books85`, `books96`, `posfailed` | 83, 85, 95, 96 | OFF |
| Setup and switches | `setupadvisor.js`, `setupundo.js`, `s1setup.js`, `optviews.js`, `guards.js`, `formscreens.js`, `stepw_common.js`, `chanedit.js`, `packflags.js` | `setupadvisor`, `s1setup`, `optviews`, `guards`, `unmatched`, `formguard`, `expenselink`, `transitshort`, `saleschannels`, `packflags` | 80-91 | advisory |
| Shell | `lazy.js`, `errlog.js`, `coldstart.js`, `a11yfix.js`, `kbdfix.js`, `badges107.js`, `whatsnew.js` | `reportproblem`, `problems`, `whatsnew` | 107 | on |

adv has 46 routes ours does not have: `billpay books85 books96 branchstmt cashdrawer categories catreport cheques cost116drv cost116gl cost116queue cost116stage cost116var costunknown dashx expenselink formguard guards impexp inboxpii invoiceview itemimg landed netprofit optionsx optviews organization packflags posfailed problems profile purchaseprint reportproblem reports131 s1setup saleschannels schemes scan setupadvisor stockrecon templates tinting transitshort unmatched variants whatsnew`. Note `scan`: **same route name, different feature** (adv: phase 90 "photo of a bill, list or expense"; ours: X5 item recognition `scan.js`). It is an add/add conflict and needs a rename (roadmap P1).

The database side of every row above is already live (the owner pasted adv phases 72-135 through `setup-run-1..25`), so the owner has working tables and functions with no screen. Audit F-01 saw this: "live DB has phase-135 functions, UI not wired".

### 2.3 Behaviour inside shared files that `pub-new` overwrote with older code (adv-only edits, 28 files, +/- counts vs base)
| File(s) | What adv added | Tag |
|---|---|---|
| `nav.js` (+36/-17) | glass options, collapsible footer, business switcher, `duesFn` (net-of-advance dues list), optviews hook | bos109, bos101, bos113, bos91 |
| `app.js` (+76/-11), `pos.js` (+95/-29) | cold-start hooks, late-sale / replay handling, category pickers, business brand on receipt | bos112, bos114, bos100 |
| `stock2.js` (+123/-22) | transfer challan, marked return sheet, incoming count, batch check, categories | bos114, bos115, bos100 |
| `inbox.js` (+71/-18) | PII masking with audited unmask | bos99 / bos105 |
| `recipes.js`, `bulkitems.js`, `itemmaster.js`, `items2.js` | category / sub-category, upload fix, recon tab | bos100, bos103, bos107 |
| `dues.js`, `dash.js`, `finance2.js`, `ownerboard.js`, `payroll.js`, `accounts.js` | net-of-advance dues, card settlement, wording | bos113, bos108 |
| `index.html` | CSP, bundle tags, glass, preload | bos109, bos111, bos113, bos114 |
| `sw.js` | build-stamped cache, precache | bos110, bos114 |
| `styles.css`, `theme.css` | drawer fold, glass tokens, contrast fixes | bos101, bos102, bos108, bos112, bos114 |
| ~20 more (`attendance.js`, `employees.js`, `lists.js`, `locations.js`, `rollout.js`, `recipebook.js`, `costattrib.js`, ...) | wording only (+N/-N) | bos108 |

### 2.4 Wording regression (language rule of the owner)
adv applied the Bangla review (`docs/i18n/BANGLA_REVIEW.md`, phase 108): common words stay English in Bangla mode (Save/সেভ, Date/ডেট, Approve/অ্যাপ্রুভ, Cancel/ক্যান্সেল, Customer/কাস্টমার, Supplier/সাপ্লায়ার). The review found 574 unique strings where Bangla replaced a common word. ours has the older text. The rehearsal counts **142 renamed labels and 22 missing controls** in the no-loss inventory when adv files merge over ours (`docs/RECOVERY_MERGE_DRYRUN.md`, ui inventory). This follows the owner's instruction at turn L361 (16 Oct 01:40: keep common English words, "ইংলিশ word এ কমন রাখতে").

### 2.5 Infrastructure present only on adv (needed to rebuild the bundle)
`tools/build_web.sh`, `tools/web_build.js`, `tools/web_deps.js`, `tools/web_lazy.json` (not present in ours: `ls tools/` shows none), tests `lazy_test.js`, `order_lazy_test.js`, `swupdate_test.js`, `sec2_csp_test.js`, `navfold_test.js`, `glass_test.js`, `glass_b2_test.js`, `coldstart_test.js`. Needs `terser` + `esbuild` (installed by npm on first run).

### 2.6 What exists only on ours (must not be lost by the recovery)
80 web files absent on adv: navigation stack `navstack.js` (exact Back, Back 2/3, Main), the 360 px header-wrap fix, `connect.js`, `website.js`, `market.js`, `ai_core.js`, `photo.js`, `scan_core.js`, `scan_native.js`, `order_parser.js`, `xb_paysms.js`, `xb_paycapture.js`, `xb_cakejobs.js`, `xb_riders.js`, `xc_unsold.js`, `xc_summary.js`, CRM (`crm_*.js` x11), report hub (`reporthub*.js`, `rptkit.js`, `campaigns.js`, `couponuse.js`, `auditreports.js`, `forecast.js`, `c2rpt.js`, `orderreports.js`, `custinsight.js`, `staffreports.js`, `reportsmap.js`), money wave (`moneysrc.js`, `moneyaccounts.js`, `openparties.js`, `periodlock.js`, `moneycontrols.js`, `returnrules.js`, `profitcheck.js`, `reportnotes.js`, `expenseregister.js`, `statements.js`, `otherincome.js`, `freshness.js`, `balancecheck.js`, `wallets.js`, `monthclose.js`, `shortages.js`), `announce.js`, `todo.js`, `shifts.js`, `payrequests.js`, production/ops (`prodplan.js`, `prodreports.js`, `capacity.js`, `targets.js`, `trace.js`, `stockout.js`, `purchrep.js`, `stockrep.js`, `batchrep.js`, `rb4common.js`), `infohint.js` + `data/info.json` (552 entries), `data/report_registry.json`, vendored ZXing and Tesseract. 82 routes exist only on ours. SQL: 183 tables and 1,372 functions created only by our phases >= 80; adv-only: 88 tables, 589 functions.

---

## 3. Branch map (facts)

| Line | Tip | Commits | Ahead / behind ours | SQL phases | Web | Only here |
|---|---|---|---|---|---|---|
| `origin/ccr-78d03e25-k7ksyo` (GitHub default) | `dbecc25` 14 Oct | 56 | 0 / 202 | 2-79 | 85 files | stale base; nothing unique |
| `origin/ccr-9c1f9be7-3s9qnz` (adv) | `0bc142b` 15 Oct | 291 | 235 / 202 | 2-79, 80-118, 120-129, 131-135 (130 is a test) | 137 files | glass, collapsible drawer, business layer, CSP, bundle/lazy, cold start, error log, templates, dashx, dealer, variants, import-export, profile, places, reports131, audit-fix phases 112-118 |
| `claude/supabase-readonly-audit-xo3qkp` (ours) | `551eb71` 19 Oct | 258 | 0 / 235 | 2-79, 80-99, 120, 130-132, 140-143, 300-308, 316-319, 323-329, 400-478, 479-498, 499, 501-505 | 167 files | navstack, X1-XC, CRM, report hub, money wave, announce/todo/shifts/pay requests, info signs, 360 px fixes |
| `origin/ccr-46b26d91-81vl9s` | `2535ec6` 15 Oct | 71 | 15 / 202 | 2-79 | 85 files (unchanged base) | docs only: Group ERP Stage A blueprint and owner answers (`3180466`, `48000c9`, `918d649`...), demo guides, read-only MCP config |
| `origin/ccr-2f54f832-rkdi5z`, `origin/ccr-9ef9353a-q2wsec` | 13 / 14 Oct | 18 / 43 | 0 / 240, 0 / 215 | older | 72 / 80 files | nothing unique |

Where the public build came from: `0bc142b` (see 1.2 item 2), found by the commit trailer in `4ec5e56` and confirmed by `git branch -r --contains 0bc142b`.

Phase collisions (same number, different content): **23 numbers**: 80-99, 120, 131, 132 (46 conflicted SQL files with their `_test` pairs). Free adv-only numbers: 31 (100-118, 121-129, 133-135). Both lines re-create 10 functions whole (`_acct_docs`, `_daybook_lines`, `_p27_pl`, `_recipe_lines_ok`, `_sale_stock_out`, `biz_items`, `customer_dues`, `sale_return`, `stock_receive_transfer`, `stock_reconcile`) and both patch 113 pre-existing functions (list in the roadmap, P2). No rule key was found in both lines (pattern scan; partial).

---

## 4. Owner decision and demand ledger

Source: user messages of the transcript `109c3315-...jsonl` (turn id `L<line>`, UTC time shown in the file) and its compaction summaries; plus the decision documents of the adv line (`docs/DECISIONS.md`, `docs/GROUP_ERP_STAGE_A.md` sections 10-11 at commit `3180466`, `docs/HANDOVER_7.md`). Status words: **done**, **partial**, **lost** (shipped before, not reachable now), **todo**, **deferred** (owner said later), **conflict**.

### 4.1 Rules and process
| ID | Turn / date | Owner words (short) | Meaning | Status | Where |
|---|---|---|---|---|---|
| R1 | L519 / L572, 16 Oct | "আর ডেমো মুছতে হবে না, বাট এই গুলা যেন আবার সফটওয়্যার এ না ঢুকে যায়" | demo / fictional staff never in repo, DB, docs | done | `CLAUDE.md`, `tools/check_no_demo_leak.py`, `.github/workflows/no-demo-leak.yml`. Caveat: **8 adv test files fail this guard** (5.2, W5) |
| R2 | L1101, L1113, L1181, L1192 | "ডেমো পুশ করতে মানা করছিলাম না", "বিকল্পটাই করো, কিন্তু পরে ইতিহাস মুছতে চাই তখন যেন পারি" | no demo push; history cleanup possible later | done / deferred | guards above; `docs/HISTORY_CLEANUP_RUNBOOK.md`, `tools/make_clean_branch.sh`; history rewrite not done |
| R3 | L636, 16 Oct 15:28 | "ওউনার এর এটা অপশন বিল্ড করা থাকবে ... নিজেই এপ্রুভ ... এন্ট্রি লগ এ শো ... অফ" | owner approval modes (self / other / show in log / off) | done on ours; conflict with adv phase 87 ("owner can always approve") | ours phases 80, 86, 87 |
| R4 | L1057, L1074 | "বেতন কোন হিসাব থেকে দিবো এইটা ফিক্স না ... সব সেটিংস ... End to end" | payment source never fixed; settings end to end; exceptions allowed | done on ours; partial across lines | ours phase 87 (money accounts, payment source on 14 event types); adv phase 85 (card settlement, stock to GL) |
| R5 | L683 | "ফর্ম এর প্রত্তেক টা এন্ট্রি লেজার এ কানেক্ট হচ্ছে কিনা ... রিপোরট এ হিসাব লিংক" | every form linked to ledger and reports | partial | `docs/FORM_LEDGER_LINKAGE_AUDIT.md`, Wave 1 phases 80-99; live `accounting_on` OFF, so unproven live |
| R6 | L1735 | "যা সিদধান্ত চাচ্ছো, তার সব অপশন ইনপুট দেওয়ার সিস্টেম থাকবে" | every decision is a setting | done | `CLAUDE.md` rule; `rules` + `set_rule` |
| R7 | L5634, 18 Oct 08:31 | "আমাকে এখন আর কোন ডিসিশন এ জিগাসা করবা না" | agent decides as a business specialist | done as process | `docs/HANDOFF.md` section 1. Side effect: decisions D-01 to D-16 in `PLAN_NEXT.md`; **D-06 and D-15 rest on a false premise** (bos112 text exists, section 5) |
| R8 | L7682 | "মেইন হেড ফিচার ... যেখানে শো করা উচিত সেখান এ শো করা লাগবে ... শো/হাইড পরে" | main features visible, only inner settings OFF | partial | `HANDOFF.md`; not verified screen by screen |
| R9 | L5650, L5672, L5700, L5775 | "আগের স্টাইল ফেজ নাম্বার ... ক্রম সেট ... কোন কনফ্লিক্ট না হলেই হচ্ছে" | sequential phase numbers, no conflict | partial | ours 480-554 -> 479-498 done (`tools/renumber.py`); **collision with adv 80-99, 120, 131, 132 open** |
| R10 | L7848, L7881, L7946, L7977, L8009 | "ম্যানুয়াল ফর্ম এর নাম্বার যেন চেঞ্জ না হয় ... ছাপা নাম্বার" then "সুন্দর করে সিরিয়াল ... shortcut Name ... md ফাইল" | printed form codes frozen; propose sequence + short names + project guide | deferred | `docs/NUMBERING.md`, `tools/numbering_map.json` (`form_groups_approved: false`); scratch `NUMBERING_PLAN.md`, `PROJECT_FILE_ORGANISER_GUIDE.md` |
| R11 | adv `DECISIONS.md` | words list "common words stay English in Bangla mode" | UI language rule | done on adv (bos108), **lost** on public, regressed on ours | 2.4 |
| R12 | adv `DECISIONS.md` (11-12 Oct) | free plan, Staff ID + PIN, role matrix, count-first, red control, three language modes, web in a separate public repo | base platform | done (both lines, base <= 79) | base phases |

### 4.2 Features requested on ours
| ID | Turn / date | Owner words (short) | Status | Where |
|---|---|---|---|---|
| F1 | L1224, L1250 | two specialist agents debate the audit; one agent for compact page design | done (docs) / build todo | `docs/ARCHITECTURE_DESIGN.md`, scratch audit docs |
| F2 | L1267, L1334 | "কোন এজেন্ট কত পারসেন্ট ... সব সময় ভিজিবল" | done | progress board artifact |
| F3 | L2093 | "CRM এর গ্যাপ চেক করাও, না থাকলে ফুল CRM" | partial | phases 300-308, 316-319, 323-329; `crm_*.js`; D/E/I parts only via RPT-C3 (458-468) |
| F4 | L2120, L2136, L4851 | architecture: many options in short space, no form name or option dropped; later "backup defaults -> all-on layout -> revert" | deferred | `ARCHITECTURE_DESIGN.md`; owner said "ডিজাইন পরে" (L8083); not built |
| F5 | L2381 | "ক্রিটিক্যাল সিস্টেম ... i সাইন দিয়ে ... ইনফরমেশন" | done on ours; **absent on adv** | `web/infohint.js`, `web/data/info.json` (552), `tools/check_info_coverage.py` |
| F6 | L2524 | staff ask for salary/advance in the app, approver named, date; same for parties and suppliers | done | R1 pack: phase 120 (ours), `payrequests.js` |
| F7 | L2611 | news-ticker announcement bar, TO-DO list, shift schedule | done | phases 130-132 (ours), `announce.js`, `todo.js`, `shifts.js` |
| F8 | L2858-L3204 | 193-report master list, grouped, matched by purpose, question-driven ("এক বছরে একজন স্টাফের খাওয়ার খরচ", "ব্রাঞ্চের ইলেক্ট্রিসিটি বিল ৮ মাস") | done / partial | `reporthub*.js`, phases 400-476, `data/report_registry.json`; overlaps adv `reports131` |
| F9 | L4294 | website, Facebook autopost, AI agents, camera/OCR/ML Kit all built, link later via Connect Center | done-OFF; X3 screens deferred; X5 not phone-tested | phases 479-498; `connect.js`, `website.js`, `ai_core.js`, `scan_*.js` |
| F10 | L4872, L4888 | exact Back to the page you came from, 2-3 steps, "Main" point | done on ours; at risk in the merge | `web/navstack.js`, `app.js goback` |
| F11 | L5584, L5618, L8083 | "ডিজাইন বাদ দিয়ে যত কাজ হয়েছে তা আগে লাইভ ... ওয়েব এ লাইভ" | **lost** (the live step overwrote the older live site) | this audit |
| F12 | L8560, L8636, L8767 | SQL copy-paste links, fewest parts, one-click copy page | done | 13 parts, `setup-all.html`; side effects section 5 |
| F13 | L8209-L8433 | backups on phone and Drive; disk clean-up | done | backup zip, Drive folder "Islamia BOS backup 2026-10-18" |
| F14 | L5564 / L5592 | phase numbers 480/490/500 looked wrong | done | see R9 |

### 4.3 Requirements recorded on the adv line (owner answered in the other session)
| ID | Source | Requirement | Status |
|---|---|---|---|
| G1 | owner report | Liquid Glass themes | **lost** on public; adv only |
| G2 | owner report | collapsible left menu, location block movable | **lost** on public; adv only (S2) |
| G3 | `GROUP_ERP_STAGE_A.md` 10a | every business a separate legal entity; strict data isolation proven by tests; no cross-business transactions now; master dashboard owner-only; partnerships later; about 70% generic foundation; no industry workflows yet | adv DB done (phases 122, 123, 132, 133; switch OFF); UI **lost**; not in ours |
| G4 | 10b | intercompany later, per-pair, OFF | todo (Stage E) |
| G5 | `HANDOVER_7` import-export answers | import and export, few configurable currencies, no intercompany | adv done (124); UI **lost** |
| G6 | docs commit `918d649` | fashion/cloth: variants, large catalogue | adv done (125, 126); UI **lost** |
| G7 | docs commits `c57699e`, `4d063e6` | dealership: cheque/PDC, principal schemes, tinting | adv done (127-129, OFF); UI **lost** |
| G8 | phase 134 header | one profile per business; people of a business never see group or other businesses | adv DB done; UI **lost** |
| G9 | phase 135 | create places of a business from the app; guided new business | adv DB done; UI **lost** (this was the newest live feature) |
| G10 | `HANDOVER_7` C3 MCQs 1-4 | per-business rule changes, bots per business, books per business, accountants | **unanswered** |
| G11 | adv phases 91, 92, 93, 97, 99, 100, 102 | who-sees-what, invoice after sale, print/message templates, landed cost, bill payment, categories, item photos | DB done; UI **lost** |
| G12 | adv phases 112-118, 121 (audit2 fixes) | profit truth, books truth, stock safety, transfers, manufacturing cost, reconciliation reports | DB done (switches OFF); UI **lost**; **duplicated** by our 499-505 |

### 4.4 Statements that are wrong in current docs (fix in roadmap P2)
- `docs/PLAN_NEXT.md` 1.3 / D-06 / D-15: "`bos112` is not recoverable". It is in `origin/ccr-9c1f9be7-3s9qnz:supabase/phase112.sql` (functions `_c78_rows112`, `_pnl_truth112`, `profit_truth112`, `biz_items` tag bos112). `period_lock_owner_mode` / `bos113` `lock_check` is in `phase113.sql`; `card_settle_over_mode` in `phase109.sql`.
- `docs/PLAN_NEXT.md` 1.4 "card-settlement code is not in this branch": true for ours; the code is in adv phases 85 and 109.
- `docs/PLAN_NEXT.md` items 15-18, 23, 31, 38 (phases 499, 501-504) re-implement what adv phases 112-118 already deliver and what the live database already contains.

---

## 5. Risk list

### 5.1 Database side (live project; nothing read or written by this audit; derived from the repos and the 19 Oct audit)
| ID | Risk | Evidence | Likelihood | Check (read-only, owner) |
|---|---|---|---|---|
| D1 | `lock_check` in live was forced back to the phase 6 + phase 87 text, **dropping the adv bos113 owner-mode logic** (`period_lock_owner_mode`, exception `closed_period_owner`) | public `sqlparts/part08.sql` (commit `3185918`) and `sqlparts/fix_lock_check.sql`; adv `phase113.sql` header | high | probe Q1 (does the body contain `bos113`) |
| D2 | `biz_items` in live: either only the cost join was rewritten (keeps bos112 returns netting) or the body was **replaced by the phase 4 + 14 text** and the old body saved in `public._fix_fn_backup` | public `sqlparts/part12.sql` (commit `ec817cc`), 19 Oct audit lists `_fix_fn_backup` among 69 no-policy tables (it exists, so the fix step ran) and also says live `biz_items` has a bos112 block | unknown | probe Q1 + Q2; if the replace branch ran, the live bos112 text sits in `_fix_fn_backup.def` and is also in adv `phase112.sql` |
| D3 | 10 functions created whole by both lines: last paste wins. Our parts were pasted last, so adv fixes inside them (bos98-bos113) may be gone | list in section 3; adv guards refuse to overwrite unknown tags, ours patch by exact text | high | probe Q1 for tags per function |
| D4 | 113 pre-existing functions patched by both lines (full list in roadmap P2.3); exact-text hooks of ours may have fallen back or skipped | `_i1_apply_hooks`, phase 477 pre-flight added by `ec817cc` | medium | `select * from public._i2_state() where not present;` must be empty |
| D5 | 27 of the 69 no-policy live tables are not created by ours (landed costs, import-export, business profile, Telegram secrets...) | `docs/PLAN_NEXT.md` 1.2, `docs/SECURITY_BACKLOG.md` | certain | all are in adv phases; no action except knowing the source |
| D6 | Two copies of the same feature with different switch names (dues net of advance: ours `dues_net_advance_on`, adv `dues_net_advance`; transfers, unit-unknown, biz_items netting, intermediate ingredient) | rule lists in `phase499-504` versus adv `112-116` | certain | decide which is canonical before switching either on |
| D7 | `public._fix_fn_backup` has no primary key and holds an old function body (advisor warning) | audit 2.2 | certain | read, save, then decide |
| D8 | Exception-kind check constraint `money_exceptions_kind_check` is rebuilt by our phases 89/94/120; adv phases write other kinds (`closed_period_owner`, `late_docs_locked`, `stock_negative`...) into `exceptions` | `phase89.sql:99-108`, adv `phase113.sql` | to verify | insert tests on a throwaway database |
| D9 | Both lines own the same phase numbers 80-99, 120, 131, 132. A future "re-paste from phase N" instruction means different files on each line | `PASTE_ORDER.md` | certain | resolved by the renumbering map (roadmap P2.1) |
| D10 | Switches all OFF in live (`accounting_on`, `org_scope_on`, `rpt131_on`, `stock_negative_mode=warn`, items untracked): recovered UI will show empty or "off" screens until the owner sets them | audit F-08, F-10, F-11 | certain | expected; not a loss |
| D12 | **The SQL that was pasted live is not reproducible from this repository.** The public `sqlparts` contain three hand-added blocks that are not phases: `fix_lock_check.sql` (and the same text inserted before the hooks in part 8), and in part 12 the `fix_biz_items` block plus a pre-flight dry run. They changed live function bodies and created `_fix_fn_backup` | public commits `33be97d`, `3185918`, `ec817cc`; `tools/` and `supabase/` of ours do not contain them | certain | roadmap P2.4 turns them into numbered, idempotent phases or replaces them by union phases |
| D11 | Live data is a handful of test-like records (10 sales, 1 customer, 0 journals): a **fresh rebuild is feasible** and removes all unknown live-only state | audit 3.3 | n/a | owner decision (roadmap P2.0) |

### 5.2 Web / delivery side
| ID | Risk | Detail |
|---|---|---|
| W1 | Orphan files on the public site | 50 old scripts, `core.js`, `app.css`, `lazy.js`, `bundle-manifest.json`, glass files stay on the server; `PUBLISH_NOTES.md` and `DEPLOY_CHECKLIST.md` describe a build that is not live; `tools/build_web.sh --to` would delete files that vanished from `web/` (it removes "gone from web/" files), so the next adv-style build run from ours would erase the adv screens for good |
| W2 | Phones with the old service worker | old SW `bos-sw-610e0641de` precaches `core.js?v=b668c85845`; new SW is `bos-sw-v5`, network first; a phone that stays offline keeps the old shell until it reconnects |
| W3 | Two pages claim `scan` | add/add conflict (2.2) |
| W4 | CSP needs the new inline hash and any new host | adv CSP allows `cdn.jsdelivr.net` and `tessdata.projectnaptha.com`; after merge every inline script and every new external host of ours must be re-checked (`tests/web/sec2_csp_test.js`) |
| W5 | Demo-guard failures on adv tests | `supabase/phase127_test.sql`, `phase129_test.sql`, `phase21b_test.sql`, `tests/web/dashx_test.js`, `dealer127_test.js`, `items2_b_test.js`, `pos2b_test.js`, `reports131_test.js`: roster-style names; must be rewritten with `test_*` names before import. `web/tpl_samples.js` says "Invented items and amounts only": review against `CLAUDE.md` |
| W6 | `info.json` coverage | 47 adv rules (for example `org_scope_on`, `dealer_cheque_on`, `profit_truth_mode`) have no (i) entry; `check_info_coverage.py` fails until they are written |
| W7 | UI no-loss inventory | 164 problems on the rehearsed tree (22 missing controls, 142 renamed labels) |
| W8 | Disk / process | each full web test needs space and a local database; HANDOFF section 7 rules apply |
| W9 | No staging | a candidate build must be tried on a phone before it replaces the root; today there is no preview site |

### 5.3 Process risks
- Two chat sessions worked on the same repository with different branches and no shared "branch of record". The GitHub default branch is the oldest (`dbecc25`).
- Agents decided "not recoverable / not in branch" without searching other branches (D-06, D-15).
- No release identity: the live web commit, the live SQL phase list and the canonical branch were never written down (audit Gate A).

---

## 6. Rehearsal numbers (from `tools/recovery_merge.py`, dry run of 20 Oct)
- Merge of adv into a scratch branch of ours: **78 conflicted files** (46 SQL = 23 phase numbers with `_test` pairs, 16 web, 13 tests including 7 screenshots, 2 docs, `.gitignore`). 1,304 files merge cleanly (51 web, 89 SQL).
- Checks with conflicts resolved "ours": numbering PASS, phase477 build OK, report registry OK, backup guard OK; **demo leak FAIL (8 files), test-only FAIL (same cause), info coverage FAIL (47 rules), ui inventory FAIL (164 problems)**. Baseline of ours: all eight OK.
- Full report: `docs/RECOVERY_MERGE_DRYRUN.md`.

## 7. What could not be determined
1. The exact current state of the live database functions (this audit is read-only and did not query it): probes are in the roadmap, appendix A.
2. Which of the 13 SQL parts the owner actually pasted, and in what order, beyond "parts 1-13".
3. The owner's own words for the sidebar request ("mark down / up"): the transcript available here ends at 18 Oct 15:04; the report arrived later. Interpretation S2 matches the adv feature that moves the location block (collapsible footer). A screenshot would settle it.
4. The "several more, unknown" items: section 2 lists everything that differs. Anything the owner remembers that is not in section 2 must be compared with the public history (`git log` of `islamia-bos-app`).
5. Whether the preferred Bangla wording is adv's (owner word list) for every screen; recommended yes (R11).
6. A local un-pushed revert commit in `/home/user/islamia-bos-app`: none found (HEAD = origin/main = `b67ea29`, clean tree).
7. Whether any adv-only feature was ever used with real data (live has 10 sales, 1 customer).
