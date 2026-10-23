# WORK TRACKER - audit fixes, costing, recipes, online orders (single source of memory)
Updated: 2026-10-14. Read this first in any new session. Basis: AUDIT_REPORT_FULL.md findings (a1..a4). Owner: phone only, Bangla, short honest replies, never give him scripts/terminal/computer work; he pastes SQL via the copy-button pages and sends screenshots.

## Owner rules (apply to every step)
1 one step = one branch (fix/phase-X); after a step STOP and report; no merge / deploy / next step without the owner's "merge" or "next step"
2 only NEW migrations (phase72+); old phase files untouched; all changes additive, paste-twice safe
3 nothing runs on the live Supabase except step A (SELECT only); tests on scratch DBs
4 new rules default = today's behaviour (warn/off); no limit, rate or amount in code (location settings only)
5 never invent numbers/rates/recipes/data; every cost field starts BLANK, blank is flagged "অসম্পূর্ণ/অনুমান"
6 keep cost-secrecy (view_cost), RLS, grants, client_id idempotency, immutable ledger, audit log; every new write path has client_id + audit
7 each step: SQL tests on a fresh DB (phase50_test style) + re-run older suites, show pass/fail numbers; no "pollution" excuses
8 report = 3 separate parts: যাচাই হয়েছে (run) / পড়ে বোঝা (code read) / যাচাই হয়নি, with file refs
9 match printed forms (05-3, 05-4, 10-2, web/forms_factory.js:169-215): one place holds detail, the other only a number; mismatches go to the report, never auto-changed
10 phone-impossible setups (external accounts, approvals, secrets, deploy) listed separately; secrets never in code/repo/chat
11 partial work or missing external connection is stated plainly; a design is never called "running"
12 NO real person names in code, seeds, tests, docs: roles and ids only (artisan names only in the artisan register)
13 LANGUAGE RULE (software-wide, common; in Bangla mode too, common words stay ENGLISH words; NEVER rewrite/reword existing texts - only new strings follow the rule): English mode = 100% English words, NO Bangla characters; Bng/Eng (mix) = natural Bangla with common technical English words (stock, cost, bill, order, switch, report, batch...) mixed in; Bangla mode = Bangla; via B.L(bn,en,mix), never one language hard-coded; every new test asserts English-mode strings contain no Bangla characters. Details: UI labels: language follows the software language setting (বাংলা selected => Bangla, English selected => English, mix mode => Bng-Eng) via B.L(bn,en,mix); NEVER hard-code one language; every new screen/message/error must have all three; check English mode shows English

## Cost structure (code must follow)
layer 1 raw material = average cost (+ separate "আজকের কেনা দাম"); layer 2 factory conversion cost (labour, gas/fuel, electricity, factory rent, licence & fees, machine repair, depreciation, other) goes INTO product cost; layer 3 showroom + admin cost NOT in product cost (branch P&L). Product cost = material cost + conversion rate x quantity.

## Live state (owner pasted): phases 48-71 in Supabase (check box: all 8 parts OK). Live DB is nearly empty: 0 tracked items, 0 recipes, 0 online orders, accounting_on=false (start date 2026-10-14), 2 sales not in journal; report COGS (item_costs) 1072.21 vs journal 0 for Oct. Public page https://mistybari99.github.io/islamia-bos-app/ (setup-sql.html phases 48-71, audit-a.html).

## Plan in 3 parts
### Part 1 - correct accounts & safety
| step | scope | status | branch / migration |
|---|---|---|---|
| A | live read-only SELECT checks | DONE (results reported) | fix/phase-A, supabase/audit_phaseA_readonly.sql |
| B | B1 rounding + autopost errors visible; B2 one COGS source (ledger; item_costs fallback flagged) in biz_daily/_p27_pl/l2_margin/brand_pnl/partner profit/phase50:543; B3 return margin with discount share; B4 unknown-cost "সাময়িক" + production_requires_cost (warn|refuse); B5 inventory_vs_gl read-only + reconcile tab; B6 posting status strip | DONE, pushed, NOT merged, NOT in live DB (waiting owner merge) | fix/phase-B, phase72 (71 tests, no regressions) |
| D | D1 missing stock moves to GL (count_adjust, stock_opening, issue_out, transit_loss, purchase-return variance; keys stock_adjust, purchase_variance; transfers: PROPOSE location-tagged pairs vs company-wide BS, owner decides); D2 inventory opening helper + warning; D3 uncosted wastage/production waiting; D4 manual-journal guard (reason code, party mandatory on payable/receivable); D5 autopost scheduler + >1 day pending alert, locked docs list; D6 card settlement to bank, expense voucher payment mode | TODO | fix/phase-D |
| E | E1 GRN vs purchase exclusivity; E2 block void of posted bill after use (refund/credit not auto-void payment); E3 unit-conversion required at sale; E4 negative-stock (sell_below_zero use logged, production negatives, never-opened list); E5 form vs screen (05-1 consumes ingredients or refuses; NULL-cost flag; pending shadow links; unmatched-form list); E6 expense double-count (dup_suspects expense branch); E7 transit shortage; E8 offline POS failed cards (manager override resend, JSON export, board); E9 online order gaps -> done in Part 3 | TODO | fix/phase-E |
| F | audit trail: log_change + no-delete on stock_balance/stock_batches/purchase_lines/stock_transfers/stock_wastage; production_runs void audit; stock_reconcile(true) audit rows; service_role path = "যাচাই হয়নি" | TODO | fix/phase-F |
### Part 2 - costing & recipes (agent running in worktree)
| step | scope | status | branch / migration |
|---|---|---|---|
| C-0 | artisans register (roles + owner-typed names only there), recipe artisan pick (+ "অন্য"), recipe_versions + approval (changer != approver), recipe_steps (ordered, minutes x people = SUGGESTED labour hours only), artisan recipe book (no cost by default), grant recipe_view | DONE pushed, NOT merged/live (98 SQL, web 49) | fix/phase-C0, phase73 |
| C | recipe_cost_components, factory_cost_pools + normal_monthly_output (pool rate), production_post adds conversion cost, production_runs cost columns (cost-right only), recipe_cost = same _recipe_need (packaging separate rows), today's purchase price row, GL overhead_absorbed + true-up "অনাবশোষিত ওভারহেড", p_actual_yield + variance, manual production path reason; C9 (recost, landed cost) = owner decision only | DONE pushed, NOT merged/live (96 SQL, web 39); MUST re-merge with phase72 production_post/recipe_cost (7-arg core + 6-arg wrapper) | fix/phase-C, phase74 |
| C-2ক | cost_sources + cost_source_bills (separate/shared bills), allocation rules (meter/percent/area/headcount/output/one site/other), destinations factory/showroom/admin, sum=100 else refuse, "অভাগিত" row, effective-date rule changes (no history rewrite), factory share -> pools, "বিল বাকি", no averaging guesses, 10-2 duplicate flag, entry person != rule approver | DONE pushed, NOT merged/live (76 SQL, web 34); location_cost_cfg table instead of location_settings (owner may revert) | fix/phase-C2a, phase75 |
### Part 3 - online orders & messages (agent running in worktree)
| step | scope | status | branch / migration |
|---|---|---|---|
| H | sales_channels, inbound_messages (inbox), web/landing form endpoint (server-side price, idempotent), Facebook/Instagram/WhatsApp webhook receiver + signature check (verify Meta docs; unverified stays "যাচাই হয়নি"), staff confirms orders, optional auto-draft default OFF, duplicate flag, phone/address visibility + audit, failed-webhook retry, "শেষ বার্তা কখন" alert | DONE, pushed, NOT merged, NOT live (phase76: 108 tests, web 29; edge fns source only) | fix/phase-H, phase76 |
| E9 | pack-time stock warn, keep order price option, void-sale flag on order, packaging-return PROPOSAL | DONE, pushed, NOT merged, NOT live (phase77: 26 tests) | fix/phase-E9, phase77 |
### Final
| G | regression tests of the audit scenarios (a1-F1 hand calc 661/10=66.10, a3 main scenario, a4 mixed scenario), negative-stock sweep function, whole suite before/after numbers | TODO | fix/phase-G |

## Finding -> step map (nothing may be dropped)
a1: F1 method note->C; F2 no overhead->C/C-2ক; F3 NULL cost never back-filled->B4/C9; F4 actual yield->C7; F5 recipe_cost packaging->C4; F6 two cost sources->B2; F7 manual production->C8; F9 landed cost->C9 (decision); F10 negative->E4; F11 cost columns->C3.
a2: F1 unit conversion->E3; F2 negative policy->E4; F3 offline failed->E8; F4 return margin->B3; F5 COGS source->B2; F6 online order->E9; F7 packaging return->E9 proposal.
a3: F1 two profit numbers->B2; F2 costed_rev gross returns->B3; F3 unknown cost->B4; F4 uncosted waiting->D3; F5 rounding->B1; F6 inventory GL->B5 (report) + D1 (posting); F7 opening->D2; F8 autopost delay->B6 + D5; F9 locked docs->D5; F10 manual journal->D4; F12 overhead->C; F13 card settlement/expense mode->D6.
a4: F1 GL vs ledger->B5/D1; F2 GRN->E1; F3 bill void->E2; F4 form vs screen->E5; F5 expense double->E6; F6 transit shortage->E7; F7 manual journal payable->D4; F8 autopost->D5; F9 audit triggers->F; F10 shadow pairing->E5.

## OWNER DECISIONS RECEIVED (14 Oct) - Part 2
1 recipe approval: owner can approve himself OR grant permission to others; when granting, system shows a SUGGESTION to give approval to someone else (non-blocking; owner can always do everything)
2 recipe_approval_required: both warn and required stay as owner-selectable switch
3 costing method per place: all options (off / recipe rate / monthly pool) stay selectable from the app
4 production_requires_recipe: option exists; owner decides in the field who does what
5 bill entry / rule approval permissions: granted later by owner, with the same separation suggestion
6 profit/cost attribution: per showroom AND main centre, app option whether showroom/admin cost shares are charged to a showroom or kept at main centre; backend fully built-in even when unused
7 keep location_cost_cfg; ADD built-in 'which cost belongs to which showroom' + ability to CHANGE it (reason + audit + history)
-> built as step C-2b (branch fix/phase-C2b, phase78) - agent running in worktree /home/user/wt-c2b

## OWNER DELEGATED ALL REMAINING DECISIONS TO THE LEAD (14 Oct) - rule: build EVERYTHING in, keep every option switchable; at real use the app shows a RECOMMENDED choice with a Bangla reason ('কোনটা ভালো/যুক্তিসঙ্গত'), the owner may choose anything; once a system is switched on, data must flow the correct way automatically.
Lead's chosen defaults / recommendations (UI shows them as 'প্রস্তাবিত'; never force; stored defaults stay OFF/today's behaviour until the owner taps 'প্রস্তাবিত প্রয়োগ'):
- cost 0: treated as UNKNOWN unless the item is marked 'খরচ সত্যিই শূন্য' (new per-item flag) - recommended
- production_requires_cost: default warn; RECOMMENDED refuse once ingredient costs are entered; add Bangla label for cost_missing
- reports item_costs fallback: keep as fallback, always labelled 'অনুমান'; recommend entering ledger cost
- partner profit-share base with fallback numbers: switch warn|refuse; default warn, recommend refuse for settlements
- D bookings (recommended): count_adjust -> stock gain/loss account (stock_adjust); opening -> owner capital via opening entry; transfers -> location-tagged pair with inter-location clearing (switch to company-wide alternative); purchase-return variance -> purchase_variance
- channels: all built; recommended to start: web form + phone + walk-in; Messenger/Instagram/WhatsApp stay off until connection exists (phone-impossible setup)
- phone/address guard: recommend ON; contact-view grant to POS-enter roles of that branch + owner
- drafts: built, recommend OFF at start
- intake bot: DEDICATED minimal role that can call only intake functions (NOT POS enter) - redesign in follow-up
- E9: recommend pack_warn ON, keep_order_price ON (price_override approver = manager role), sale-return flag ON
- packaging on sale return: option B (packaging_return_mode none|restore|wastage), default none, recommend 'wastage' first
- web form rate limit / captcha / silence hours: values live in settings; UI shows suggested ranges, owner taps to apply
NEW STEPS:
- S1 (phase80) decision follow-ups: per-item free-cost flag, cost_missing label, partner-base switch, packaging_return_mode, intake-bot role redesign
- S2 (phase81) RECOMMENDATIONS + ACTIVATION GUIDE ('চালু করার গাইড'): function setup_recommendations() evaluates live DB state and returns recommended switches/settings with Bangla reason + status; one-tap apply with audit; readiness checks before switching a module on (e.g. accounting needs opening balances + mappings; stock tracking needs conversions + costs; production needs recipes approved); post-activation flow checks ('সব ঠিকঠাক বইছে?'); never blocks the owner
- INT (phase79 = integration fix): integration branch merging B + C chain + C2b + H + E9, re-create production_post/recipe_cost once with ALL changes (phase72 + phase74 + phase73 approval gate), full regression

## Open owner decisions (collect from agent reports)
- start stock tracking + accounting_on: before or after Part 1? (live DB empty; risk rises once enabled)
- D1 transfers: location-tagged vs company-wide balance sheet
- negative stock block mode where; C9 recost + landed cost; packaging return on sale return; Meta app/business verification path

## Phone-impossible setups (never given to the owner as his task)
Meta app + business verification + webhook subscription; edge-function deployment and secret-store entries; scheduler (pg_cron / edge schedule) activation; any server access.

## Process memory
- agents write only inside their own worktree/branch; lead merges; live deploy only on explicit "merge"/"deploy" from the owner
- public repo islamia-bos-app publishes web files + setup pages; pushing it = production deploy
- 2FA TOTP + restore drill (#17/#18) built, phases 70/71 pasted; real Supabase drill/enrol UNVERIFIED
- #16 PIN hardening postponed by owner

## Update (latest)
- integration/p72-p79 now holds: 72-79, 82 (Ea), 83 (Eb), 84 (F); QA report in docs/briefs_p2p3/QA_COVERAGE.md. Default branch ccr-78d03e25-k7ksyo fast-forwarded to dbecc25 (72-79) on owner "Merge". Nothing in live DB / public pages yet.
- Running: S1(80) S2(81) D(85) Tg(86 telegram) X(87 QA fixups: owner-always-approve, unassigned findings, wiring).
- TODO INT2 (phase89): phase83 re-creates _sale_stock_out WITHOUT bos82 lines -> re-apply bos82+bos83 together; re-check every function overwritten by 80-87 (pg_get_functiondef diff); fix phase21/22 fixture (phase84 forbids stock_balance delete); wiring posfail.js (index.html after pos.js, ia.js posfailed rec).
- Production answer: recipe path auto-deducts raw/pack, no-recipe path does not; recommend production_requires_recipe ON; double-issue risk -> X guard.
