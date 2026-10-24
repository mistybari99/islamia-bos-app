# READINESS 99: is the system ready to run the whole business?

Branch `audit/readiness`, written 23 Oct 2026 from `Main-Img` tip `8ff9d92`. Local work only: nothing pushed, no GitHub change, no live Supabase access. Test data are neutral `test_*` rows on a throwaway PostgreSQL 16.15 built from the full chain (`ORDER=all`, 0 errors, 2,894 functions, 478 tables).

Three parts: **A** the readiness matrix (section 1-2), **B** the calculation proof (section 3-5), **C** the top 15 gaps and the build order (section 6). Section 7 lists what could not be verified.

## 0. Verdict in five lines

1. The money core works: purchase with freight, goods receipt, production cost with overhead, transfer, POS in five payment shapes, return, wastage, day close, supplier payment, payroll, VAT memo and statements matched hand-computed numbers except where section 4 lists a mismatch (section 3). The journal balanced in every run (Dr = Cr, 0 unbalanced entries).
2. With the **default settings** the scenario still shows 19 mismatches of 141 checks, most because the safe default books nothing for a stock, count or cash loss, the rest are defects D1, D4, D7, D8. The advisor's "recommended values" fix part of it (16 left). Adding six switches the advisor does not know leaves **5**, which are real defects (section 4).
3. Matrix: 281 rows, **76 DONE, 64 DONE-OFF, 107 PARTIAL, 11 MISSING, 23 DESIGN-NEEDED**. The 99 percent target is not reached yet: the open items are listed in order of business risk in section 6.
4. Biggest risks are not calculations: backup and restore never run for real, no real phone, printer or offline test, server-side PIN lockout not enabled, VAT not in the ledger, repository visibility undecided.
5. Nothing in this branch changes a phase file. Defects are written up with proposed new phases (section 4). One small fix is drafted as `supabase/phase548.sql` in a separate commit (see section 4, D8).

## 1. How to read the matrix

Status words: **DONE** = built and proven by the scenario or a cited test; **DONE-OFF switch** = built, behaviour starts only when the owner switches it on (default OFF), proven or cited; **PARTIAL** = part works or works only with owner setup / device test; **MISSING** = no code found; **DESIGN-NEEDED** = needs an owner or accountant choice before any code is honest.

Evidence: `scenario <label>` = a check in `tests/sql/readiness/rd_scenario.sql` (result lists `results_def.txt`, `results_rec.txt`, `results_recx.txt`); `audit2 harness` = `tests/sql/audit2/run_all.sh` re-run on this tree (section 7); phase numbers and function names are the ones in `supabase/`. Rows marked "not exercised" exist in the code but this audit did not run them.

Sources read: `DEMAND_VERIFY.md`, `DECISIONS.md`, `PLAN_NEXT.md`, `HANDOVER*.md` (6 and 7 in full headings, the rest skimmed), `ERP_AUDIT_ROADMAP.md`, `GROUP_ERP_STAGE_A.md`, `WORK_TRACKER.md`, `REMAINING.md`, `TODO.md`, `OPERATIONAL_MANUAL_BN.md`, `BUSINESS_PROCESS_GUIDE.md`, `docs/audit2/*` (84 gaps A1-A5, re-run), `docs/guide/*`. "F-xx" items of the Islamiya audit are cited through `PLAN_NEXT.md` (the audit file itself is not in the repository).

## 2. Totals

| Process | DONE | DONE-OFF | PARTIAL | MISSING | DESIGN-NEEDED | Rows |
|---|---|---|---|---|---|---|
| Purchase to pay | 9 | 4 | 6 | 0 | 0 | 19 |
| Stock and counts | 6 | 10 | 14 | 1 | 1 | 32 |
| Production and costing | 5 | 9 | 13 | 2 | 5 | 34 |
| Transfers | 2 | 12 | 12 | 2 | 1 | 29 |
| Sales, POS and orders | 7 | 2 | 6 | 0 | 0 | 15 |
| Cash, bank, card and wallet | 7 | 10 | 16 | 0 | 0 | 33 |
| Customer and supplier dues | 4 | 1 | 3 | 0 | 0 | 8 |
| Payroll and attendance | 7 | 2 | 2 | 1 | 0 | 12 |
| Accounting and statements | 6 | 2 | 5 | 1 | 3 | 17 |
| Tax and VAT | 2 | 0 | 1 | 3 | 0 | 6 |
| Reports and dashboard | 8 | 6 | 10 | 0 | 4 | 28 |
| Permissions and security | 4 | 2 | 3 | 1 | 2 | 12 |
| Offline | 0 | 0 | 4 | 0 | 0 | 4 |
| Printing | 1 | 0 | 3 | 0 | 1 | 5 |
| Notifications | 2 | 2 | 0 | 0 | 1 | 5 |
| Backup and restore | 1 | 1 | 2 | 0 | 1 | 5 |
| New-business templates | 1 | 1 | 5 | 0 | 0 | 7 |
| Owner decisions and process rules | 4 | 0 | 2 | 0 | 4 | 10 |
| **Total** | **76** | **64** | **107** | **11** | **23** | **281** |

Rows with id `AUD-...` are the 84 audit gaps A1-A5 taken from the harness table and corrected where this audit's own scenario shows another result.

### Owner decisions still open (collected from the matrix)

The last column of every matrix row names what the owner must still decide. The distinct decisions (136) are in the matrix itself; the ones that block the 99 percent target are in section 6.

## 2b. The matrix by process

### Purchase to pay

| ID | Requirement | Source | Status | Evidence | Owner must decide |
|---|---|---|---|---|---|
| PTP-01 | Purchase bill (supplier, lines, unit cost, discount) posts stock in at average cost and the supplier payable | DEMAND_VERIFY G11; BUSINESS_PROCESS_GUIDE 1 | DONE | scenario P1 (bill 9800: qty, avg cost 40, supplier owes 9800, GL 1320/1330 and 2100 agree); save_purchase/post_purchase | none |
| PTP-02 | Freight / clearing cost added to stock cost (landed cost) and allocated by value, weight or quantity | DEMAND_VERIFY G11 (landed cost); PLAN_NEXT 45 | DONE | scenario P2 (freight 490 by value: flour 42, sugar 84, box 5.25; GL inventory +490); landed_save/landed_post, phase 523/525 | Which allocation method per charge type (value / weight / quantity) is the house rule |
| PTP-03 | Freight payable to the transporter can be seen as a supplier due and later paid | GROUP: owner decision 'bill payment'; BUSINESS_PROCESS_GUIDE 8 | PARTIAL | DEFECT D1: charge credited to 2150 with the transporter as party (acct_party_ledger shows 490) but supplier_dues() shows 0 and pay_supplier() answers 'overpaid'; bill_pay_record only knows kinds purchase and cost. Only a freight paid at posting (pay_mode cash/bank/mobile) works. scenario P2/P3 FAIL in all three runs | Pay the transporter at posting (cash/bank) or later as a due: owner picks the habit; software fix is a new phase (section E, D1) |
| PTP-04 | Goods Received Note (GRN) form posts stock; the bill must not count the same goods twice | ERP_AUDIT_ROADMAP D2/D6; TODO A1; audit A4 F2 | DONE-OFF switch | scenario G1: GRN 13-1 approved -> qty 10; bill without link refused (grn_link_required); after grn_bill_link qty stays 10, payable +30. Needs rules forms_post_to_ledger + grn_receipt_source=grn + purchase_grn_guard=link (all default off/purchase) | Receipt source: GRN form or purchase bill. Recommended guard is link; the setup advisor does not set it |
| PTP-05 | Purchase requisition -> comparative statement -> purchase order as app records linked to the bill | BUSINESS_PROCESS_GUIDE 1; OPERATIONAL_MANUAL_BN 5 | PARTIAL | Forms 28-1, 29-1, 27-1 exist as paper-copy forms in entries (jsonb). No structured PO table and no PO-line to bill-line match; report p5_po_match returns 0 rows on the scenario. Code: web/forms*.js, phase 25 report P5 | Does the owner want PO as a controlled document (approve limit, open qty) or keep the paper copy |
| PTP-06 | Three-way match PO / goods received / bill | BUSINESS_PROCESS_GUIDE 1; ERP_AUDIT_ROADMAP section 4 | PARTIAL | 3-way match listed 'verified' in ERP_AUDIT_ROADMAP but depends on the PO being typed in form 27-1; grn_pending_report, grn_bill_link exist; no tolerance setting found | Tolerance (qty/price) for a match; who clears a mismatch |
| PTP-07 | Supplier price list and price-jump warning | PLAN_NEXT 45; WORK_TRACKER | DONE | supplier_price_set / supplier_price_list; purchase_cost_jump_pct exception; phase 545 price_check_include_freight (DONE-OFF) | Jump percentage; whether freight counts in the check |
| PTP-08 | Pay a supplier in parts, from cash, bank or wallet; refuse overpayment; no double payment (client id) | BUSINESS_PROCESS_GUIDE 8; phase 10 | DONE | scenario P4: partial bank payment 5000 -> owes 4830, GL 2100 and bank agree; 4831 refused 'overpaid'; pay_supplier | Who may pay (grant supplier_pay) and above which amount the owner must approve |
| PTP-09 | Staff / supplier payment request with a named approver and date | DEMAND_VERIFY F6 | DONE | pay_request_submit/decide/pay, routes payrequest, partyrequest, payapprovals (web/ia.js:228-231), phase 120 | Approver per request type |
| PTP-10 | Automatic payment when a bill is posted (cash / bank / by supplier default) or ask | phase 99/525 | DONE-OFF switch | rule purchase_bill_creates_payment (off/ask/auto_cash/auto_bank/auto_by_supplier_default); advisor sets 'ask' | Auto mode only if the owner pays every bill on the day |
| PTP-11 | Purchase return / debit note and supplier refund | phase 10; supplier_refund | DONE | save_purchase kind='return', supplier_refund, void_supplier_refund, void_supplier_payment; report supplier_returns_report | Refund vs credit-note habit |
| PTP-12 | Void a posted bill; refuse when stock or payments depend on it | WORK_TRACKER E2 | DONE-OFF switch | void_purchase; rule purchase_void_guard (advisor sets 'refuse'), purchase_void_payments | Keep or refund payments on a void |
| PTP-13 | Backdated bill flag | audit A4 | DONE-OFF switch | exception purchase_backdated raised in rec/recx runs (bills dated 3 days back); rule purchase_backdate_flag | Days allowed before a flag |
| PTP-14 | Supplier credit days, overdue ageing, dues list, supplier ledger | BUSINESS_PROCESS_GUIDE 8 | DONE | scenario R3 (supplier_ageing = account 2100); supplier_dues, supplier_ledger, report supplier_ageing | Credit days per supplier |
| PTP-15 | Duplicate supplier bill number guard | BUSINESS_PROCESS_GUIDE 8; audit A3-G16 | PARTIAL | Duplicate guard only checks form 11-1 (A3-G16, no probe); purchase_bills has client_id idempotency only | Block or warn on a repeated bill number per supplier |
| PTP-16 | Reorder suggestion from minimum stock and usage | ERP_AUDIT_ROADMAP gap 7 | PARTIAL | reorder_report() and stock_low report exist (phase 25); minimum stock is an item field the owner must fill; no auto purchase draft | Minimum stock per item; lead time |
| PTP-17 | Supplier rating (delivery, rejection, dependency) | TODO C1 | DONE | supplier_delivery_perf, supplier_rejection_rate, supplier_dependency, report p4_supplier_score | none |
| PTP-18 | Import / foreign-currency purchase and LC | GROUP_ERP G5 | PARTIAL | phase 124 import-export register per business (impexp_on OFF); no GL posting, no LC/customs (HANDOVER_7 G6 open) | Only if an import business is switched on |
| PTP-19 | Purchase document printing | DEMAND_VERIFY G11 | DONE | web/purchaseprint.js, route purchaseprint (ia.js:273) | Template wording |

### Stock and counts

| ID | Requirement | Source | Status | Evidence | Owner must decide |
|---|---|---|---|---|---|
| STK-01 | Every movement in one append-only stock ledger with cost; quantity by place | BUILD-RULES 3,7 | DONE | stock_ledger/stock_balance; scenario M2, T2, X2 (all quantities equal hand numbers) | none |
| STK-02 | Average cost; FIFO / lot costing option | ERP_AUDIT_ROADMAP; WORK_TRACKER cost structure | DESIGN-NEEDED | Only moving average is built (scenario P2 average). Batches exist for expiry (stock_batches) but cost is not lot-based | Average cost or FIFO for sweets (shelf-life) - the owner and accountant choose |
| STK-03 | Blind stock count (count first, expected shown after) for the stock count sheet and GRN | DECISIONS 11 Oct 'count-first mandatory by default'; BUILD-RULES 9 | DONE-OFF switch | rule blind_count_on default FALSE (phase 18/23); stock_blind_active covers 13-1 and 36-1; scenario D1: maker saw expected and diff in default and in the advisor run; hidden only in recx. DEFECT D5 (default contradicts the owner decision; advisor omits it) | Switch on (recommended) - the decision text says mandatory by default |
| STK-04 | Count adjustment posts a stock gain/loss to the books | audit A4 F1 / TODO D1 | DONE-OFF switch | stock_count_adjust; scenario K1/K2: qty right in all runs; 5110 stays 0 in default, 42 in rec/recx (rule acct_count_adjust, set by the advisor) | none beyond the switch |
| STK-05 | Wastage with reason, costed, in the books | BUSINESS_PROCESS_GUIDE 2 | DONE | scenario A1 (5100 = 0.4 kg x 70.65), R9/R10 wastage report = GL; stock_wastage | Reason list; approval over a value |
| STK-06 | Expiry / batch tracking and expired-stock sale guard | phase 23; ERP_AUDIT_ROADMAP B9 | DONE-OFF switch | stock_batches, report expiry_soon, rule expiry_sale_guard (advisor 'warn'); GRN has no batch/expiry per line (REMAINING 10) | Guard: warn or refuse |
| STK-07 | Negative stock policy (allow / warn / block) | PLAN_NEXT 8-10; D-07 | DONE-OFF switch | stock_negative_mode default warn; advisor does NOT set block; late-sale exemption D-02 decided | Set block after the opening count (PLAN_NEXT D-07) |
| STK-08 | Opening stock with cost and journal | audit A4; WORK_TRACKER D2 | DONE | stock_opening, opening_stock_check96/apply96 (phase 96-103); e2e covers; not re-run in this audit | none |
| STK-09 | Unit conversion required at sale; return uses the sale's factor | PLAN_NEXT 6-7; audit A2-G4/G5 | DONE-OFF switch | rule unit_conv_required (advisor 'refuse'), return_sale_factor_on, return_uses_sale_rows (advisor on); audit2 harness FAIL/FAIL on A2-G4/G5 is stale-probe suspect | none |
| STK-10 | Period stock reconciliation: opening + movements = closing, per item and place | audit A2-G1; PLAN_NEXT 52 | PARTIAL | stock_recon_period identity holds in the default run (scenario R17 passes) but fails in the advisor run: reason transit_loss is not classified when transit_short_mode=loss (unclassified -0.5) - DEFECT D8 (also fails in recx). Daily sales-vs-stock check (PLAN_NEXT 52) still not built | Which check is the daily close rule |
| STK-11 | Stock valuation by place and category; ledger value = GL | audit A4 F1 | PARTIAL | scenario A2: company total equals GL only after the short is booked; per place equals GL only with acct_transfer_mode=location_tagged (D2, D3); valuation reports equal the ledger (scenario R4) | Location-tagged or company-wide balance sheet for transfers (WORK_TRACKER D1 open question) |
| STK-12 | Item master: 1,312 items, units, categories, images, prices, bulk edit | REMAINING P1; DEMAND_VERIFY G11 | PARTIAL | bulkitems, itemmap, categories, itemimg routes exist; the owner still types prices, minimums, Bangla category names (TODO E1) | Item data entry is the owner's work, not software |
| STK-13 | Stock tracking map by item type (which items are tracked) | PLAN_NEXT 47-51 | DONE-OFF switch | phase 505 stock_tracking_plan/apply (tracking_map_apply_on OFF); docs/STOCK_TRACKING_POLICY.md | Review each type, then apply |
| STK-14 | Combo / kit (BOM on sale) | audit A2-G7; PLAN_NEXT 12 | MISSING | audit2 A2-G7 FAIL/FAIL: no combo path (sale/void/return) | Do gift boxes need component consumption |
| STK-15 | Item merge and lifecycle (deactivate with stock) | audit A2-G9 | DONE-OFF switch | item_lifecycle_needs_zero, item_unit_change_needs_zero (advisor on); item merge function not built | none |
| STK-16 | Stock in other locations and godown, per place minimum and visibility | DECISIONS | DONE | locations table 7 seeded places; stock_levels; scenario T2 per-place quantities | none |
| STK-17 | Store ledger report (04-4 / 37-1) and stock movement ledger | OPERATIONAL_MANUAL_BN 2 | DONE | report k3_store_ledger (20 rows in scenario smoke), stock_movement_ledger, stock_ledger_rows | none |
| AUD-A2-G1 | No stock movement statement (opening + moves = closing, per item/location/period) | audit A2 (A2-G1) | DONE | scenario R17 (default run): stock_recon_period identity holds; audit2 harness re-run on this tree: defaults PASS, switches ON PASS | see the audit file docs/audit2/A2_*.md |
| AUD-A2-G2 | No sales-vs-stock reconciliation | audit A2 (A2-G2) | PARTIAL | audit2 harness re-run on this tree: defaults PASS, switches ON FAIL | see the audit file docs/audit2/A2_*.md |
| AUD-A2-G3 | stock_negative_mode=block bypassed by client-controlled sold_at | audit A2 (A2-G3) | DONE-OFF switch | audit2 harness re-run on this tree: defaults FAIL, switches ON PASS | see the audit file docs/audit2/A2_*.md |
| AUD-A2-G4 | Unit-unknown sale accepted and stock not reduced by default | audit A2 (A2-G4) | PARTIAL | audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL (open, or a stale probe: see section F) | see the audit file docs/audit2/A2_*.md |
| AUD-A2-G5 | Return after unit-factor edit restores wrong qty; base_unit editable with stock | audit A2 (A2-G5) | PARTIAL | audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL (open, or a stale probe: see section F) | see the audit file docs/audit2/A2_*.md |
| AUD-A2-G6 | Transfer above sender stock accepted in default mode | audit A2 (A2-G6) | PARTIAL | audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL (open, or a stale probe: see section F) | see the audit file docs/audit2/A2_*.md |
| AUD-A2-G7 | No combo/kit (BOM-on-sale) | audit A2 (A2-G7) | PARTIAL | audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL (open, or a stale probe: see section F) | see the audit file docs/audit2/A2_*.md |
| AUD-A2-G8 | Batch table not reconciled with balance (gain/refill/opening create no batch) | audit A2 (A2-G8) | DONE-OFF switch | audit2 harness re-run on this tree: defaults FAIL, switches ON PASS | see the audit file docs/audit2/A2_*.md |
| AUD-A2-G9 | Item lifecycle breaks stock silently (untrack, deactivate closed by 114; an item merge function is not built) | audit A2 (A2-G9) | DONE-OFF switch | audit2 harness re-run on this tree: defaults FAIL, switches ON PASS | see the audit file docs/audit2/A2_*.md |
| AUD-A2-G10 | Offline sale older than 72 h re-dated to now, unflagged | audit A2 (A2-G10) | PARTIAL | audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL (open, or a stale probe: see section F) | see the audit file docs/audit2/A2_*.md |
| AUD-A2-G11 | Transit shortage drops out of every view after receive | audit A2 (A2-G11) | PARTIAL | transit_short exception raised, the shortage listed in transfers_gap (scenario T2/R11); harness pin FAIL; audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL (open, or a stale probe: see section F) | see the audit file docs/audit2/A2_*.md |
| AUD-A2-G12 | Monitoring rules off by default | audit A2 (A2-G12) | PARTIAL | audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL (open, or a stale probe: see section F) | see the audit file docs/audit2/A2_*.md |
| AUD-A2-G13 | Server trusts the phone unit conversion | audit A2 (A2-G13) | PARTIAL | documented gap, no machine probe (code read only) | see the audit file docs/audit2/A2_*.md |
| AUD-A2-G14 | Online order link does not compare lines | audit A2 (A2-G14) | PARTIAL | documented gap, no machine probe (code read only) | see the audit file docs/audit2/A2_*.md |
| AUD-A2-G15 | Form 05-x/04-3 shadow paths only checked for skipped lines | audit A2 (A2-G15) | PARTIAL | documented gap, no machine probe (code read only) | see the audit file docs/audit2/A2_*.md |

### Production and costing

| ID | Requirement | Source | Status | Evidence | Owner must decide |
|---|---|---|---|---|---|
| PRD-01 | Recipe / BOM with yield, waste, versions and approval by a second person | WORK_TRACKER C-0; DECISIONS 14 Oct | DONE | scenario M1 (recipe_cost = hand 70.65/kg); recipe_save, recipe_approve by a different login; rule recipe_approval_required default off, advisor 'warn' | Who approves recipes |
| PRD-02 | Production run consumes ingredients and packaging and creates finished stock at recipe cost plus conversion cost | BUSINESS_PROCESS_GUIDE 3 | DONE | scenario M2: yields 30 and 10 kg, raw left 79/44/192, unit costs 70.65 and 75.85 = hand numbers | none |
| PRD-03 | Overhead (labour, gas, rent, electricity...) absorbed into product cost per batch, shown in the books | WORK_TRACKER layer 2 | DONE | scenario M2/M3: conversion 150 and 80 per batch, 5950 credit 610 = hand; loc_cost_cfg_set mode recipe/pool/off; phase 74 | Costing method per place (off / recipe rate / monthly pool) |
| PRD-04 | Monthly cost pool as the overhead driver | WORK_TRACKER C-2 | DONE-OFF switch | factory_cost_pools, pool_drivers116, pool_gl_post117 (OFF); not exercised in the scenario | Pool or recipe rate |
| PRD-05 | Under / over absorbed overhead true-up journal at month end | PLAN_NEXT 42 (D-11); audit A1-G3 | DESIGN-NEEDED | Report only; audit2 A1-G3 FAIL/FAIL; the actual factory costs are booked as ordinary expenses (scenario F1: salaries 9613 in 5200 while 610 is absorbed) and nothing compares them | Month-end rule for the difference (to COGS or to a variance account) |
| PRD-06 | Actual yield and yield-loss value; standard vs actual cost | audit A1-G8 | DONE-OFF switch | production_post(p_actual_yield), std_cost_true116, std_snapshot_auto116 (OFF); harness FAIL/FAIL (stale probes likely) | Yield tolerance per product |
| PRD-07 | Production without recipe refused / reason required | WORK_TRACKER production_requires_recipe | DONE-OFF switch | production_requires_recipe default false; production_manual_needs_reason (advisor on); advisor does not require recipe | Recommended: require a recipe for sweets |
| PRD-08 | Cost missing: refuse or warn; cost 0 treated as unknown unless item flagged free | WORK_TRACKER lead defaults | DONE-OFF switch | production_requires_cost default warn, advisor 'refuse'; item_cost_free_set | none |
| PRD-09 | Production void / undo | TODO A5 | DONE | production_void (phase 23/24) | none |
| PRD-10 | Production orders (plan) and capacity | WORK_TRACKER; ia.js:70-73 | PARTIAL | prod_order_add/close, routes prodplan, capacity, targets; not exercised here | Daily plan habit |
| PRD-11 | Semi-finished goods as ingredients, loop guarded | PLAN_NEXT 38; audit A1-G1 | DONE-OFF switch | phase 504 recipe_intermediate_on, semi_finished_ingredient116 (OFF); harness FAIL/FAIL stale-suspect | Which intermediates exist (syrup, khoa, dough) |
| PRD-12 | By-product / co-product output | audit A1-G9 | MISSING | audit2 A1-G9 pin: no by-product line in a recipe | Does any sweet make a sellable by-product |
| PRD-13 | Labour tied to production (hours, workers, payroll) | audit A1-G12 | DESIGN-NEEDED | NOT SUPPORTED (audit2); labour enters only as a typed rate per batch (scenario M1) | Rate per batch vs payroll-driven labour |
| PRD-14 | Packaging consumed on actual not planned yield | audit A1-G10 | DONE-OFF switch | packaging_on_actual_yield116 (OFF); harness FAIL/FAIL | none |
| PRD-15 | Product profit includes shared showroom and admin cost by owner rule | WORK_TRACKER decisions 6-7 | DONE-OFF switch | cost_attrib_in_pl (advisor says not_ready), location_cost_cfg, route costattrib | Which shared costs belong to which showroom |
| PRD-16 | Recipe / cost reports (F1 production, F2 yield, F3 raw vs recipe) | TODO C2 | DONE | reports f1_production(5 rows), f2_yield, f3_raw_vs_recipe (6 rows) run clean on scenario data | none |
| PRD-17 | Quality: yield test sheet, hygiene, fridge temperature | ERP_AUDIT_ROADMAP; forms 41-1 etc. | PARTIAL | Forms exist; reports q1/q2/q3 run; no QC module (optional, ERP_AUDIT_ROADMAP D) | none |
| PRD-18 | Cost of customer-supplied material / partner material | audit A1-G14 | DESIGN-NEEDED | NOT SUPPORTED | Needed only if the shop makes for others |
| AUD-A1-G1 | Semi-finished goods cannot be an ingredient | audit A1 (A1-G1) | PARTIAL | audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL (open, or a stale probe: see section F) | see the audit file docs/audit2/A1_*.md |
| AUD-A1-G2 | Pool/cost bills are memos: no matching expense posting | audit A1 (A1-G2) | DONE-OFF switch | audit2 harness re-run on this tree: defaults FAIL, switches ON PASS | see the audit file docs/audit2/A1_*.md |
| AUD-A1-G3 | Unabsorbed overhead not booked / not repriced | audit A1 (A1-G3) | PARTIAL | audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL (open, or a stale probe: see section F) | see the audit file docs/audit2/A1_*.md |
| AUD-A1-G4 | Runs before the month pool exists book conversion 0 | audit A1 (A1-G4) | PARTIAL | audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL (open, or a stale probe: see section F) | see the audit file docs/audit2/A1_*.md |
| AUD-A1-G5 | Overhead driver is output kg only | audit A1 (A1-G5) | PARTIAL | documented gap, no machine probe (code read only) | see the audit file docs/audit2/A1_*.md |
| AUD-A1-G6 | Pool mode ignores non-kg products | audit A1 (A1-G6) | PARTIAL | audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL (open, or a stale probe: see section F) | see the audit file docs/audit2/A1_*.md |
| AUD-A1-G7 | Unknown-cost ingredient: supplied cost does not reach item/runs | audit A1 (A1-G7) | PARTIAL | audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL (open, or a stale probe: see section F) | see the audit file docs/audit2/A1_*.md |
| AUD-A1-G8 | No standard-vs-actual cost report (money value of yield loss, stored standard) | audit A1 (A1-G8) | PARTIAL | audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL (open, or a stale probe: see section F) | see the audit file docs/audit2/A1_*.md |
| AUD-A1-G9 | No by-product / co-product output | audit A1 (A1-G9) | MISSING | no by-product line in recipes (pin PASS = gap still open); audit2 harness re-run on this tree: defaults PASS, switches ON PASS | see the audit file docs/audit2/A1_*.md |
| AUD-A1-G10 | Packaging consumed on planned yield | audit A1 (A1-G10) | PARTIAL | audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL (open, or a stale probe: see section F) | see the audit file docs/audit2/A1_*.md |
| AUD-A1-G11 | packaging_consume_on is global, not per product | audit A1 (A1-G11) | PARTIAL | documented gap, no machine probe (code read only) | see the audit file docs/audit2/A1_*.md |
| AUD-A1-G12 | Labour not tied to production (hours/workers/payroll) | audit A1 (A1-G12) | DESIGN-NEEDED | audit2 harness re-run on this tree: defaults NOT SUPPORTED, switches ON NOT SUPPORTED | see the audit file docs/audit2/A1_*.md |
| AUD-A1-G13 | Today-price view excludes freight | audit A1 (A1-G13) | PARTIAL | audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL (open, or a stale probe: see section F) | see the audit file docs/audit2/A1_*.md |
| AUD-A1-G14 | Partner/customer-supplied material not modelled | audit A1 (A1-G14) | DESIGN-NEEDED | audit2 harness re-run on this tree: defaults NOT SUPPORTED, switches ON NOT SUPPORTED | see the audit file docs/audit2/A1_*.md |
| AUD-A1-G15 | Yield-variance alert / waste-required rules OFF by default | audit A1 (A1-G15) | DONE-OFF switch | audit2 harness re-run on this tree: defaults FAIL, switches ON PASS | see the audit file docs/audit2/A1_*.md |
| AUD-A1-G16 | report_cost_source=item_costs can split reports from books | audit A1 (A1-G16) | PARTIAL | audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL (open, or a stale probe: see section F) | see the audit file docs/audit2/A1_*.md |

### Transfers

| ID | Requirement | Source | Status | Evidence | Owner must decide |
|---|---|---|---|---|---|
| TRF-01 | Send goods factory/godown -> showroom with a record; receiver confirms the quantity | OPERATIONAL_MANUAL_BN 3 | DONE | scenario T1/T2: send moves stock out at once; in transit 28 kg; receipts 20, 8, 7.5; unit cost carried 70.65 | none |
| TRF-02 | Short receipt creates an exception and an owner decision | OPERATIONAL_MANUAL_BN 3.4 | PARTIAL | transit_short exception raised in all runs (scenario T2). Stock: default leaves the 0.5 kg gone with no ledger loss row; advisor mode 'loss' writes a costed loss row. Books: nothing posted until acct_transit_loss is on (DEFECT D2) | Who bears the loss (shop / carrier / ask) - transit_short_bearer |
| TRF-03 | Transfers are journaled so each place's inventory in the books equals its stock | audit A5-GAP-4/10; WORK_TRACKER D1 proposal | DONE-OFF switch | scenario A2: default per place GL wrong (factory 10930 vs ledger 8345; showroom 1 -679.71); fixed only by acct_transfer_mode=location_tagged in recx. DEFECT D3: advisor does not set it | Location-tagged or company-wide (open question since 14 Oct) |
| TRF-04 | Refuse a send above stock; refuse send to a paused place | PLAN_NEXT 15-16 | DONE-OFF switch | phase 499 transfer_overdraw_block, transfer_paused_block (OFF) | Switch on after the opening count |
| TRF-05 | Partial receipt in steps; close the remainder short | PLAN_NEXT 17-18 | DONE-OFF switch | phase 499 transfer_partial_on, stock_close_transfer_short (OFF); clashes with transit_short_mode=loss (HANDOVER_6 P2) | One receipt habit |
| TRF-06 | Replay of a client id by another user refused | PLAN_NEXT 20 | DONE-OFF switch | phase 544 transfer_client_reuse_block (OFF) | Switch on after a test |
| TRF-07 | Receiver notification on send | PLAN_NEXT 21; audit A5-GAP-6 | DONE-OFF switch | transfer_notify_receiver (advisor on) | none |
| TRF-08 | Factory-to-branch statement (sent / received / short / in transit / sold / returned / wasted) | PLAN_NEXT 21; audit A5-GAP-1 | PARTIAL | branchstmt route and factory_branch_statement exist (HANDOVER_6); harness FAIL/FAIL (stale-suspect); transfers_gap and transfers_register reports run (scenario R11 = 0.5 kg) | Statement period and who gets it |
| TRF-09 | Return to factory as its own document with reason and original transfer | PLAN_NEXT 22; audit A5-GAP-3 | DONE-OFF switch | stock_return_transfer, transfer_return_marker (advisor on) | none |
| TRF-10 | Transfer price / mark-up for branch profit | audit A5-GAP-9 | DESIGN-NEEDED | transfer_valuation_basis none/cost/price_pct is for reports only; audit2 pin FAIL | Do showrooms buy at cost or at a transfer price |
| TRF-11 | One challan with many items | audit A5-GAP-7 | MISSING | One item per transfer (no header); challan print exists (web challan print, HANDOVER_6 item 8) | Is a multi-line challan needed |
| TRF-12 | Offline outbox for send/receive | audit A5-GAP-12 | MISSING | POS and forms have outbox; transfer RPCs have none (no probe) | Is the godown always online |
| TRF-13 | Damaged quantity with reason on receipt | phase 499; stock_receive_transfer(..., damaged_qty, reason) | DONE | signature present; transfer_damage_report | none |
| AUD-A5-GAP-1 | No factory-to-branch statement report | audit A5 (A5-GAP-1) | PARTIAL | factory_branch_statement and route branchstmt exist; harness probe suspect stale; scenario transfers_gap/transfers_register run; audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL (open, or a stale probe: see section F) | see the audit file docs/audit2/A5_*.md |
| AUD-A5-GAP-2 | Second/partial receive ignored | audit A5 (A5-GAP-2) | DONE-OFF switch | phase 499 transfer_partial_on (OFF); harness FAIL at defaults is expected; audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL | see the audit file docs/audit2/A5_*.md |
| AUD-A5-GAP-3 | Return to factory is an unmarked reverse transfer | audit A5 (A5-GAP-3) | DONE-OFF switch | audit2 harness re-run on this tree: defaults FAIL, switches ON PASS | see the audit file docs/audit2/A5_*.md |
| AUD-A5-GAP-4 | Mode loss and transit_short_resolve break the GL (location-tagged) | audit A5 (A5-GAP-4) | DONE-OFF switch | scenario A2/R12: with acct_transfer_mode=location_tagged and acct_transit_loss the GL equals the ledger by place (recx); default and advisor do not (D2, D3); audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL | see the audit file docs/audit2/A5_*.md |
| AUD-A5-GAP-5 | Send to a PAUSED location accepted | audit A5 (A5-GAP-5) | DONE-OFF switch | phase 499 transfer_paused_block (OFF); audit2 harness re-run on this tree: defaults FAIL, switches ON no probe | see the audit file docs/audit2/A5_*.md |
| AUD-A5-GAP-6 | No notification to the receiving branch on send | audit A5 (A5-GAP-6) | DONE-OFF switch | audit2 harness re-run on this tree: defaults FAIL, switches ON PASS | see the audit file docs/audit2/A5_*.md |
| AUD-A5-GAP-7 | One item per transfer, no challan header | audit A5 (A5-GAP-7) | PARTIAL | documented gap, no machine probe (code read only) | see the audit file docs/audit2/A5_*.md |
| AUD-A5-GAP-8 | Negative stock allowed on send / sale of in-transit goods | audit A5 (A5-GAP-8) | PARTIAL | audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL (open, or a stale probe: see section F) | see the audit file docs/audit2/A5_*.md |
| AUD-A5-GAP-9 | No transfer price / mark-up | audit A5 (A5-GAP-9) | PARTIAL | audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL (open, or a stale probe: see section F) | see the audit file docs/audit2/A5_*.md |
| AUD-A5-GAP-10 | Inter-branch balance (1230 by place) not shown anywhere | audit A5 (A5-GAP-10) | PARTIAL | documented gap, no machine probe (code read only) | see the audit file docs/audit2/A5_*.md |
| AUD-A5-GAP-11 | Form 03-1 path differs from screen (no transit_short flag) | audit A5 (A5-GAP-11) | PARTIAL | audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL (open, or a stale probe: see section F) | see the audit file docs/audit2/A5_*.md |
| AUD-A5-GAP-12 | No offline outbox for send/receive | audit A5 (A5-GAP-12) | PARTIAL | documented gap, no machine probe (code read only) | see the audit file docs/audit2/A5_*.md |
| AUD-A5-GAP-13 | Short receipt has only a free note | audit A5 (A5-GAP-13) | PARTIAL | documented gap, no machine probe (code read only) | see the audit file docs/audit2/A5_*.md |
| AUD-A5-GAP-14 | Replayed client id by another user returns first transfer id | audit A5 (A5-GAP-14) | DONE-OFF switch | phase 544 transfer_client_reuse_block (OFF); audit2 harness re-run on this tree: defaults FAIL, switches ON no probe | see the audit file docs/audit2/A5_*.md |
| AUD-A5-GAP-15 | Receive quantity in base unit only | audit A5 (A5-GAP-15) | PARTIAL | documented gap, no machine probe (code read only) | see the audit file docs/audit2/A5_*.md |
| AUD-A5-GAP-16 | Accounting switches all OFF by default | audit A5 (A5-GAP-16) | PARTIAL | documented gap, no machine probe (code read only) | see the audit file docs/audit2/A5_*.md |

### Sales, POS and orders

| ID | Requirement | Source | Status | Evidence | Owner must decide |
|---|---|---|---|---|---|
| SAL-01 | POS sale: cash, card, mobile wallet, mixed, credit with due; stock out at cost; journal | BUSINESS_PROCESS_GUIDE 5 | DONE | scenario X1/X2/A1: totals 800/500/600/1200/950/1600, stock, cash, card 1140, wallet 1130, receivable 1210, COGS 934.05 all equal hand | none |
| SAL-02 | Discount within a written limit; above it needs approval | DECISIONS; BUILD-RULES 15 | DONE | scenario X0: a salesperson with no limit written is refused 'discount_needs_approval'; owner's 50 discount posts to 4120 | Write the discount limit per role (blank limit blocks, rule 15) |
| SAL-03 | Sale return with refund (cash/mobile/card), stock back, margin reversed | DEMAND_VERIFY; PLAN_NEXT 7 | DONE | scenario X2/A1: 0.5 kg back, 4110 = 200, COGS reduced 35.325; sale_return | Whether returned sweets go back on the shelf or to wastage (packaging_return_mode) |
| SAL-04 | Void a sale | BUSINESS_PROCESS_GUIDE 5 | DONE | scenario K3: stock back, cash back, TB balanced; void_sale | Who may void and until when |
| SAL-05 | Customer credit limit and credit sale due | BUSINESS_PROCESS_GUIDE 7 | PARTIAL | due 700 recorded (scenario X1); customer credit_limit column null in scenario, enforcement not exercised | Credit limit per customer type |
| SAL-06 | Retail / wholesale (party) price lists and channels | phase 43; price_lists | PARTIAL | price_lists, price_list_items, sale_type retail/wholesale in record_sale2; party invoice forms 24-1, 25-1; wholesale not exercised | Party price rules |
| SAL-07 | Customer orders with advance, promise date, cake spec, delivery, refund, profit | phase C2 orders; ia.js:223 cakejobs | DONE | c2_order_* functions (register, advance post/apply/void, deliver, cancel, refund pay, order profit); not exercised in the scenario | Advance % and cancellation rule |
| SAL-08 | Online orders (web form, inbox) with duplicate check and stock check | WORK_TRACKER Part 3 | DONE-OFF switch | online_orders_on/inbox_on/web_form_on: advisor says not_ready; Meta/WhatsApp connection is phone-impossible (WORK_TRACKER) | Which channels to start (recommended web form + phone + walk-in) |
| SAL-09 | Delivery riders, COD cash handover, delivery charge revenue/cost | ia.js:224; audit A3-G15 | PARTIAL | xb_cod_deposit, riders route exist; delivery has no revenue/cost model (audit2 A3-G15 NOT SUPPORTED) | Delivery charge policy |
| SAL-10 | Loyalty, tiers, coupons, CRM | DEMAND_VERIFY F3 | PARTIAL | routes crmleads..crmcoupons, tiers; parts D/E/I only as reports (accepted in DEMAND_VERIFY 7b) | Which CRM screen is still wanted |
| SAL-11 | Sales channels and brand reports (item, category, hour, trend) | TODO C1 | DONE | catalogue reports item_sales, category_sales, hour_weekday, sales_trend run clean (scenario R21) | none |
| SAL-12 | Offline sale replayed later: late / old sale policy | PLAN_NEXT 8, 9, 11 | PARTIAL | late_sale_policy default redate; 100-hour-old sale re-dated with no exception (PLAN_NEXT 11); clock-skew item 9 not built | redate, redate_flag or park (owner) |
| SAL-13 | Sales figures net of returns in every report | TODO A2; audit A3-G9 | PARTIAL | DEFECT D4: report sales_summary gp = 3363.22 for place 1 while the ledger, biz_daily, l1_pnl and l2_margin say 3198.55 (gp ignores the return although net_after_returns is shown). Fails in all three runs; rule reports_net_of_returns is already true | none (bug) |
| SAL-14 | Cash drawer opening float, payout, refund events | phase drawer; drawer_event_log | DONE | drawer_event_log, drawer_report, drawer_settings; not exercised | Float per showroom |
| SAL-15 | Packaging used per sale and restored on return | phase 20/23; packaging_set | DONE-OFF switch | packaging_consume_on, packaging_return_mode (advisor 'wastage'); not in scenario | Return mode |

### Cash, bank, card and wallet

| ID | Requirement | Source | Status | Evidence | Owner must decide |
|---|---|---|---|---|---|
| CSH-01 | Daily cash close per showroom with a blind count; short/over stored even when zero | BUILD-RULES 9; DECISIONS count-first | PARTIAL | scenario D2: expected 2350, counted 2340, diff -10 stored, red exception raised, same as the POS day-close report (2350). But the maker sees expected/diff unless blind_count_on (D5), and the expected figure is typed from the sheet, not pulled from POS (A4-G02/G19) | Prefill expected from POS (recommended) and switch blind on |
| CSH-02 | Cash short/over reaches the books | audit A4-G01 | DONE-OFF switch | scenario D3: 5800 = 0 in default; 10 in rec and recx (drawer_short_post on); harness A4-G01 stale FAIL/FAIL | none |
| CSH-03 | Day book equals the journal | audit A4-G05 | PARTIAL | scenario D4: daybook_vs_journal difference 0 for the day; harness A4-G05 FAIL/FAIL (suspect stale) | none |
| CSH-04 | Card sales settle to the bank with fee; card receivable shows what is unsettled | audit A4-G06; PLAN_NEXT 33 | DONE | card_settle/card_settle_void/card_settlement_list (phase 85/109); scenario A1: 1140 = 500; settlement not exercised here (e2e C1 covers: Dr bank 588, fee 12) | Over-settlement: warn (D-09) or refuse |
| CSH-05 | Mobile wallets (bKash-style) as accounts with statements, fees, reconciliation | R4; phase 87 | DONE | scenario A1: wallet 1130 = 600; money_accounts, d_wallet_*; wallet_recon report = 600 (scenario R13) | Which wallets and numbers |
| CSH-06 | Bank accounts, bank statement import, match, post charges/interest | ERP_AUDIT_ROADMAP gap 1; audit A4-G08 | DONE-OFF switch | bank_stmt_import, bank_recon_*, bank_stmt_post113; rule bank_stmt_post_on (advisor on); statement import needs the owner's CSV; not exercised | Bank statement format |
| CSH-07 | Cash handover to hub / deposit to bank | form 03-1; cash_move_add | DONE | cash_move_add, bankreceipt route, rpt131_cash_close; not exercised | Hub/handover rule |
| CSH-08 | Cheques / PDC | G7 | DONE-OFF switch | phase 127 cheques (dealer_cheque_on OFF) | Only if the sweets business takes cheques |
| CSH-09 | Money movement approvals, self-approval blocked | BUILD-RULES 8; DECISIONS | DONE | moneycontrols route; owner_approval_mode (phase 80) | Delegates |
| CSH-10 | Expense voucher (11-1) and quick expense with one shadow copy | ERP_AUDIT_ROADMAP section 11 | DONE | quick_expense_add, shadow_links, shadow_count_once_check; e2e H1/H2 | none |
| CSH-11 | Owner top-up / draw and partner capital | ERP_AUDIT_ROADMAP D4 | PARTIAL | partner_capital primary with shadow; GL posting of partner profit share not probed (audit A4-G10) | Partner agreements |
| CSH-12 | Opening balances for cash and bank, accounting start date | ERP_AUDIT_ROADMAP 10-6 | DONE | scenario S0: acct_opening (cash 20000, bank 100000, capital 120000) posted; acct_set_start | Real opening balances at go-live |
| CSH-13 | Rounding differences in COGS at 3+ decimal cost | audit A4-G16 | DONE-OFF switch | rounding rule 5880 exists; scenario cost 70.65 and 75.85 are exact so not stressed | none |
| AUD-A4-G01 | Drawer shortage/overage never reaches the books | audit A4 (A4-G01) | DONE-OFF switch | scenario D3: books show 5800 = 10 in rec/recx (drawer_short_post on), 0 in default; harness FAIL is a stale probe; audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL | see the audit file docs/audit2/A4_*.md |
| AUD-A4-G02 | No automatic day-end cash close (expected cash typed) | audit A4 (A4-G02) | PARTIAL | expected drawer cash is typed on sheet 06-1 (scenario D2); POS day close gives the same figure but is not pulled in (D9); audit2 harness re-run on this tree: defaults PASS, switches ON PASS | see the audit file docs/audit2/A4_*.md |
| AUD-A4-G03 | customer_dues ignores advances used (double clearing) | audit A4 (A4-G03) | DONE-OFF switch | audit2 harness re-run on this tree: defaults FAIL, switches ON PASS | see the audit file docs/audit2/A4_*.md |
| AUD-A4-G04 | Period lock bypassed by owner; scheduler skips locked docs silently | audit A4 (A4-G04) | DONE-OFF switch | audit2 harness re-run on this tree: defaults FAIL, switches ON PASS | see the audit file docs/audit2/A4_*.md |
| AUD-A4-G05 | Day book and journal disagree | audit A4 (A4-G05) | DONE | scenario D4: daybook_vs_journal difference 0 for the day; audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL | see the audit file docs/audit2/A4_*.md |
| AUD-A4-G06 | Card settlement not matched to card sales; over-settlement accepted | audit A4 (A4-G06) | DONE-OFF switch | card_settle exists; scenario A1 shows 1140 = 500 unsettled; over-settlement mode is a switch (default warn); audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL | see the audit file docs/audit2/A4_*.md |
| AUD-A4-G07 | Void/reversal booked on the void date | audit A4 (A4-G07) | PARTIAL | audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL (open, or a stale probe: see section F) | see the audit file docs/audit2/A4_*.md |
| AUD-A4-G08 | No bank charge/interest posting from a statement line | audit A4 (A4-G08) | PARTIAL | audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL (open, or a stale probe: see section F) | see the audit file docs/audit2/A4_*.md |
| AUD-A4-G09 | Manual journal guard default off | audit A4 (A4-G09) | PARTIAL | documented gap, no machine probe (code read only) | see the audit file docs/audit2/A4_*.md |
| AUD-A4-G10 | Partner profit-share payments not in GL / day book | audit A4 (A4-G10) | PARTIAL | documented gap, no machine probe (code read only) | see the audit file docs/audit2/A4_*.md |
| AUD-A4-G11 | No tax in the ledger (VAT memo only) | audit A4 (A4-G11) | PARTIAL | documented gap, no machine probe (code read only) | see the audit file docs/audit2/A4_*.md |
| AUD-A4-G12 | Mobile wallet fee / bank transfer at POS | audit A4 (A4-G12) | DONE-OFF switch | audit2 harness re-run on this tree: defaults FAIL, switches ON PASS | see the audit file docs/audit2/A4_*.md |
| AUD-A4-G13 | Advance not usable at POS | audit A4 (A4-G13) | PARTIAL | documented gap, no machine probe (code read only) | see the audit file docs/audit2/A4_*.md |
| AUD-A4-G14 | Journal has no cashier / shift dimension | audit A4 (A4-G14) | PARTIAL | audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL (open, or a stale probe: see section F) | see the audit file docs/audit2/A4_*.md |
| AUD-A4-G15 | Payments cannot be back-dated | audit A4 (A4-G15) | PARTIAL | documented gap, no machine probe (code read only) | see the audit file docs/audit2/A4_*.md |
| AUD-A4-G16 | Rounding drift in COGS at 3+ decimal cost | audit A4 (A4-G16) | DONE-OFF switch | audit2 harness re-run on this tree: defaults FAIL, switches ON PASS | see the audit file docs/audit2/A4_*.md |
| AUD-A4-G17 | GL may be stale while reconciliation reads only posted entries | audit A4 (A4-G17) | PARTIAL | audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL (open, or a stale probe: see section F) | see the audit file docs/audit2/A4_*.md |
| AUD-A4-G18 | vat_report bucket uses created_at::date (session zone) | audit A4 (A4-G18) | PARTIAL | documented gap, no machine probe (code read only) | see the audit file docs/audit2/A4_*.md |
| AUD-A4-G19 | No single close-the-day reconciliation screen | audit A4 (A4-G19) | PARTIAL | documented gap, no machine probe (code read only) | see the audit file docs/audit2/A4_*.md |
| AUD-A4-G20 | Expenses are cash-basis only (no accrual) | audit A4 (A4-G20) | PARTIAL | documented gap, no machine probe (code read only) | see the audit file docs/audit2/A4_*.md |

### Customer and supplier dues

| ID | Requirement | Source | Status | Evidence | Owner must decide |
|---|---|---|---|---|---|
| DUE-01 | Customer due after partial payment and later collection | BUSINESS_PROCESS_GUIDE 7 | DONE | scenario X1/X2/R2: due 700, collection 300, balance 400 = customer_dues report = GL 1210 = acct_party_ledger | none |
| DUE-02 | Customer due net of advances already applied | PLAN_NEXT 31-32; audit A4-G03 | DONE-OFF switch | dues_net_advance (advisor on, phase 503/customer_dues_net113); customer_ledger not yet netted (PLAN_NEXT 32) | none |
| DUE-03 | Receivable ageing and reminders | BUSINESS_PROCESS_GUIDE 7 | PARTIAL | report receivable_aging, rpt131_ageing (rpt131_on OFF); no automatic reminder sending (notify outbox needs a connection) | Reminder days and channel |
| DUE-04 | Supplier due / ageing / ledger | BUSINESS_PROCESS_GUIDE 8 | DONE | scenario P4/R3 | none |
| DUE-05 | Party (wholesale) credit and ledger | forms 24-1, 25-1, 30-1 | PARTIAL | paper-copy forms; customer ledger common | Party credit terms |
| DUE-06 | Freight / transporter dues | see PTP-03 | PARTIAL | DEFECT D1 | see PTP-03 |
| DUE-07 | Staff advance and recovery | phase 41/42; payroll | DONE | employee advances, advance_recovery in payroll_lines; staff_advances | Recovery rule |
| DUE-08 | Open parties opening balances | ia.js:206 openparties | DONE | route openparties; not exercised | Opening dues at go-live |

### Payroll and attendance

| ID | Requirement | Source | Status | Evidence | Owner must decide |
|---|---|---|---|---|---|
| PAY-01 | Employee master with pay structure, documents, deeds, shifts | phase 41 | DONE | employee_save, employee_pay_set, routes employees, deeds, shifts | Pay structure per person |
| PAY-02 | Attendance: device import, app punch, leave, holidays, shifts, overtime | ERP_AUDIT_ROADMAP section 6 | PARTIAL | phase 42; bridge tested against a fake device only; app punch spoofable; geofence/selfie not built (Phase C of ERP_AUDIT_ROADMAP) | Fingerprint device primary? app punch allowed? |
| PAY-03 | Monthly payroll sheet from attendance: absent deduction, late, overtime, bonus, advance recovery; approve; pay | BUSINESS_PROCESS_GUIDE 10 | DONE | scenario W1: worker A net round(6000-2*6000/31)=5613, staff B 4000; payroll_create/approve/pay; calc_detail trail shown | Day-rate basis (calendar days used, working days possible) |
| PAY-04 | Salary expense and payment in the books, per place and by mode | phase 87 | DONE | scenario W2: 5200 = 9613, bank -5613, cash showroom -4000 | Accrual or pay-basis (payroll_accrual_on default off) |
| PAY-05 | Salary accrual (expense in the month earned) | phase 87 payroll_accrual_on | DONE-OFF switch | rule payroll_accrual_on default false; advisor does not set it; month close warns no_payroll_run | Accrual from which month |
| PAY-06 | Staff cost reports include app payroll | audit A3-G2; reports T3/T4/L1 | PARTIAL | DEFECT D7: t3_payroll shows 0 for the paid runs in all three runs (it reads paper sheets); l1_pnl includes salary only with report_salary_source=app_first (recx); c2_salary_basis reconciles runs (scenario R18b passes) | Switch the staff-cost reports to app payroll (recommended once payroll runs) |
| PAY-07 | Paper salary sheet 21-1 and app payroll not counted twice | ERP_AUDIT_ROADMAP D1 | DONE-OFF switch | phase 93 report salary source; HANDOVER_6 P2 warns sheet without month keys is counted next to payments | Month the app payroll becomes the only record |
| PAY-08 | Final settlement of a leaving employee | phase 42 | DONE | payroll_settlement_preview, exit clearance form 10-1 | Gratuity/notice rule |
| PAY-09 | Provident fund, gratuity, income-tax deduction at source | Bangladesh payroll practice | MISSING | No function or table found (grep: no provident/gratuity/withholding in public functions) | Which statutory deductions apply (accountant) |
| PAY-10 | Salary and advance request in the app with approver | DEMAND_VERIFY F6 | DONE | pay_request_*; phase 120 | Approver |
| PAY-11 | Bonus events (Eid) by months of basic | phase 42 | DONE | payroll_bonus_events; not exercised | Eid bonus rule |
| PAY-12 | Payroll lock after payment; void with reason | phase 42 | DONE | payroll_void, payroll_payment_void | none |

### Accounting and statements

| ID | Requirement | Source | Status | Evidence | Owner must decide |
|---|---|---|---|---|---|
| ACC-01 | Double-entry journal, every entry balanced, append-only with reversals | CLAUDE.md; BUILD-RULES 7 | DONE | scenario Z1/Z2 in all runs: unbalanced entries 0, sum(debit-credit)=0; TB report balanced; period close | none |
| ACC-02 | Auto-posting from sales, purchases, cash, returns, wastage, production, payroll, landed cost | R5; FORM_LEDGER_LINKAGE_AUDIT | DONE | scenario A1/M3/P4/W2: GL equals hand numbers for the posted types; acct_post_pending | Switch accounting_on after reviewing opening balances (default off) |
| ACC-03 | Trial balance, P&L, balance sheet, cash flow | ERP_AUDIT_ROADMAP section 4 | PARTIAL | scenario A1/F1/F2: TB balanced; P&L revenue, COGS equal hand; balance sheet balances (difference 0) in all runs. Net profit and total assets equal the all-costs-booked hand figure only in recx (default off by 45.325, advisor run off by 35.325) | none beyond the switches |
| ACC-04 | Profit equal across branch P&L, product margin, day report and journal | audit A3-G1; PLAN_NEXT 25 (D-08) | PARTIAL | scenario G2/R5-R8: biz_daily, l1_pnl, l2_margin (both products, place 1 and both places), l3_shop_pnl agree with hand and journal; sales_summary gp does not (D4); l1 shows profit_complete=false (wastage, expenses not in it, flagged honestly) | Which figure is 'the profit' (D-08) |
| ACC-05 | Month-end close checklist (blockers, warnings, snapshot) | phase 82 | PARTIAL | c_month_close_preview ran: blocker month_not_finished and warning no_payroll_run were correct for 24 Oct; the close itself could not be run inside this month (date) | Close day rule |
| ACC-06 | Period lock; owner bypass and late-posting warnings | audit A4-G04 | DONE-OFF switch | period_lock_set, period_lock_owner_mode (advisor warn), period_lock_late_warn (advisor on) | none |
| ACC-07 | Year-end close and retained earnings roll | ERP_AUDIT_ROADMAP gap 2 | DONE | year_close_run/year_close_reverse (phase 9x); balance sheet shows retained earnings = P&L (scenario F2); year close not run | First fiscal year dates |
| ACC-08 | Fixed assets register and depreciation | ERP_AUDIT_ROADMAP gap 4 | DONE | fa_asset_save, fa_depr_post, fa_register, fa_schedule, fa_asset_dispose; not exercised | Depreciation rates (accountant) |
| ACC-09 | Budgets and budget vs actual | ERP_AUDIT_ROADMAP gap 5 | DONE | budget_set, budget_list, budget_vs_actual; not exercised | Budget lines |
| ACC-10 | Manual journal guard (reason, party on receivable/payable) | WORK_TRACKER D4 | DONE-OFF switch | manual_journal_guard (advisor on) | none |
| ACC-11 | Accrual accounting for expenses (not cash basis only) | audit A4-G20 | DESIGN-NEEDED | no probe; expenses post when paid (cost_bill_creates_payment ask); no accrual option found | Cash or accrual expense policy (accountant) |
| ACC-12 | Void/reversal dated on the original day | audit A4-G07 | DESIGN-NEEDED | pin FAIL: reversals post on the void date | Reverse in the original or the current period |
| ACC-13 | Journal carries cashier / shift dimension | audit A4-G14 | MISSING | FAIL/FAIL in harness | Needed for cashier reports? |
| ACC-14 | Inventory GL equals stock ledger (company and per place) | audit A4 F1 | PARTIAL | scenario A2; see STK-11 and TRF-03 | see TRF-03 |
| ACC-15 | Group consolidation and intercompany | GROUP_ERP Stage E | DESIGN-NEEDED | DEFERRED-BY-OWNER (DEMAND_VERIFY G4) | Later, per pair |
| ACC-16 | Statements exported (CSV) for the accountant | ia.js:124 biexport | DONE | acct_export_csv, route biexport; not exercised | Which statements the accountant wants |
| ACC-17 | Multi-currency | ERP_AUDIT_ROADMAP section 4 'unnecessary' | PARTIAL | Only the import-export module has currencies and rates (phase 124, off) | Not needed for sweets |

### Tax and VAT

| ID | Requirement | Source | Status | Evidence | Owner must decide |
|---|---|---|---|---|---|
| TAX-01 | VAT memo report (output, input, returns, net payable) with a settable rate and inclusive/exclusive prices | TODO E4; PLAN_NEXT 37 | DONE | scenario V1: output 259.53, input 468.10, net -208.57 = hand (rate 5 is a TEST number; default rate is blank = 'data needed'); vat_report | Real rate and method from the VAT adviser |
| TAX-02 | VAT posted to the ledger (output VAT payable, input VAT recoverable) | audit A4-G11; PLAN_NEXT 37 | MISSING | scenario V2: accounts 2800 and 1240 stay 0 (accounts exist as 'not in use yet'); vat_input mapping key exists for landed charges only | VAT method (invoice or cash basis), who files |
| TAX-03 | Mushak 6.3 / VAT invoice printing and return form data | REMAINING 17; TODO E4 | MISSING | Not found; stays OFF until the adviser gives the rate (owner decision) | Adviser rate and whether sweets are VAT-registered |
| TAX-04 | VAT date bucket uses the shop time zone | audit A4-G18 | PARTIAL | vat_report uses created_at::date for returns (session zone) - harmless in Dhaka session, wrong at UTC midnight (no probe) | none (small fix) |
| TAX-05 | Withholding tax, advance income tax, corporate tax computation | Bangladesh practice | MISSING | accounts 2810 'not in use yet'; no function | Accountant decides the tax pack |
| TAX-06 | Item VAT status per item (applicable / exempt / undecided) | phase 53 | DONE | items.vat_applicable (true/false/null); undecided items shown as undecided_amount | Set per item category |

### Reports and dashboard

| ID | Requirement | Source | Status | Evidence | Owner must decide |
|---|---|---|---|---|---|
| RPT-01 | Report hub with 193 listed reports, question-driven | DEMAND_VERIFY F8 | PARTIAL | web/data/report_registry.json: 170 implemented, 20 incomplete, 2 unverified, 1 unavailable; hub route reports/hub | Which incomplete reports the owner still needs |
| RPT-02 | Every catalogue report runs without error on real-shaped data | TODO C | DONE | scenario R21: all 120 reports of report_catalog/2/3 (19 + 55 + 46) ran with 0 errors on the scenario data | none |
| RPT-03 | Reports agree with the ledger | audit A3/A4 | PARTIAL | scenario R1-R20: payment_modes, customer_dues, supplier_ageing, stock_balance, l1/l2/l3, wastage, transfers_gap, wallet_recon, cash flow, profit_source_check agree; exceptions D4 (sales_summary gp) and D7 (T3) | none |
| RPT-04 | Verified reports stage 1 (rpt131_*) tie to books | phase 131 | DONE-OFF switch | rule rpt131_on default false; advisor does not set it; with it off every rpt131 call returns 'feature_off' | Switch on |
| RPT-05 | Owner dashboard: problems first, then sales/expenses/profit per place | DECISIONS | DONE | owner_board_get, dashx route, owner_board_on default true | none |
| RPT-06 | Net profit report (one company profit) | PLAN_NEXT 25 | DONE-OFF switch | profit_truth_mode (advisor on), netprofit route | none |
| RPT-07 | Daily check: sales quantity vs ledger movement; unmatched sales | PLAN_NEXT 52 | PARTIAL | stock_sales_unmatched exists; daily check screen not built | none |
| RPT-08 | Contribution margin per product or branch | PLAN_NEXT 30; audit A3-G13 | DESIGN-NEEDED | NOT SUPPORTED | Fixed vs variable cost split rule |
| RPT-09 | Exports / BI | ERP_AUDIT_ROADMAP gap 14 | DONE | biexport route, rpt_hub_log_export | none |
| RPT-10 | Scheduled owner summary by e-mail | N17b | DONE-OFF switch | tools/owner_summary.py, notify digest; needs secrets and a private repo | Secrets and recipient |
| RPT-11 | Report speed on 1,300 items and a year of sales | phase 120; HANDOVER_6 | PARTIAL | throttled-laptop numbers only; no load test on this audit | none |
| AUD-A3-G1 | No single true-profit statement (branch P&L vs books) | audit A3 (A3-G1) | PARTIAL | audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL (open, or a stale probe: see section F) | see the audit file docs/audit2/A3_*.md |
| AUD-A3-G2 | Salary in two stores (sheet 02-2 vs payroll app) | audit A3 (A3-G2) | DONE | audit2 harness re-run on this tree: defaults PASS, switches ON PASS | see the audit file docs/audit2/A3_*.md |
| AUD-A3-G3 | Wastage/expiry/count loss not in branch P&L | audit A3 (A3-G3) | DONE-OFF switch | audit2 harness re-run on this tree: defaults FAIL, switches ON PASS | see the audit file docs/audit2/A3_*.md |
| AUD-A3-G4 | Card/wallet fees not in branch/product profit | audit A3 (A3-G4) | DONE-OFF switch | audit2 harness re-run on this tree: defaults FAIL, switches ON PASS | see the audit file docs/audit2/A3_*.md |
| AUD-A3-G5 | Revenue with unknown cost counted at 0 cost in profit | audit A3 (A3-G5) | DONE | audit2 harness re-run on this tree: defaults PASS, switches ON PASS | see the audit file docs/audit2/A3_*.md |
| AUD-A3-G6 | cost_attrib_in_pl default OFF; shares not in branch profit | audit A3 (A3-G6) | DONE-OFF switch | audit2 harness re-run on this tree: defaults FAIL, switches ON PASS | see the audit file docs/audit2/A3_*.md |
| AUD-A3-G7 | Unallocated shared costs vanish from every P&L | audit A3 (A3-G7) | PARTIAL | documented gap, no machine probe (code read only) | see the audit file docs/audit2/A3_*.md |
| AUD-A3-G8 | Shared-cost shares not pro-rated by period | audit A3 (A3-G8) | DONE | audit2 harness re-run on this tree: defaults PASS, switches ON PASS | see the audit file docs/audit2/A3_*.md |
| AUD-A3-G9 | Returns not netted in product sales reports | audit A3 (A3-G9) | PARTIAL | l2_margin/l1_pnl net returns (scenario R7) but sales_summary gp does not (D4); audit2 harness re-run on this tree: defaults FAIL, switches ON FAIL (open, or a stale probe: see section F) | see the audit file docs/audit2/A3_*.md |
| AUD-A3-G10 | Factory conversion default off/silent; labour not linked to payroll | audit A3 (A3-G10) | DONE | audit2 harness re-run on this tree: defaults PASS, switches ON PASS | see the audit file docs/audit2/A3_*.md |
| AUD-A3-G11 | No sales-share allocation method | audit A3 (A3-G11) | DESIGN-NEEDED | audit2 harness re-run on this tree: defaults NOT SUPPORTED, switches ON NOT SUPPORTED | see the audit file docs/audit2/A3_*.md |
| AUD-A3-G12 | Reassign applies to closed months (no snapshot) | audit A3 (A3-G12) | PARTIAL | documented gap, no machine probe (code read only) | see the audit file docs/audit2/A3_*.md |
| AUD-A3-G13 | No contribution margin (fixed/variable) | audit A3 (A3-G13) | DESIGN-NEEDED | audit2 harness re-run on this tree: defaults NOT SUPPORTED, switches ON NOT SUPPORTED | see the audit file docs/audit2/A3_*.md |
| AUD-A3-G14 | Expense heads rent/utilities have no account mapping | audit A3 (A3-G14) | DONE | audit2 harness re-run on this tree: defaults PASS, switches ON PASS | see the audit file docs/audit2/A3_*.md |
| AUD-A3-G15 | Delivery has no revenue or cost model | audit A3 (A3-G15) | DESIGN-NEEDED | audit2 harness re-run on this tree: defaults NOT SUPPORTED, switches ON NOT SUPPORTED | see the audit file docs/audit2/A3_*.md |
| AUD-A3-G16 | Bill duplicate guard only checks form 10-2 | audit A3 (A3-G16) | PARTIAL | documented gap, no machine probe (code read only) | see the audit file docs/audit2/A3_*.md |
| AUD-A3-G17 | Margin screens share one switch but labels say Gross profit | audit A3 (A3-G17) | PARTIAL | documented gap, no machine probe (code read only) | see the audit file docs/audit2/A3_*.md |

### Permissions and security

| ID | Requirement | Source | Status | Evidence | Owner must decide |
|---|---|---|---|---|---|
| SEC-01 | Staff ID + PIN login; roles; role x form matrix; per-grant control | DECISIONS 11 Oct | DONE | phase 2/7/16; scenario S0 (6 test users, 6 roles, discount refusal X0, discount limit needs a written limit) | none |
| SEC-02 | Cost price hidden from roles without ITEM_COST, also through the API | DECISIONS 12 Oct | DONE | view_cost grant; rpt cost_only columns; e2e perms 09_perms.sql (not re-run here) | Which roles may see cost |
| SEC-03 | Two signatures = two logins; PIN signature on two-person forms | BUILD-RULES 10; TODO B3 | DONE-OFF switch | pin_signature_on default off; pin_sig_cfg per form | Switch on |
| SEC-04 | Wrong PIN lockout enforced on the server (Auth hook) | ERP_AUDIT_ROADMAP 7.1; BUILD-RULES 14 | PARTIAL | App-side counter only until the owner enables hook_password_verification_attempt in Supabase (owner action); PIN hardening postponed by owner (#16) | Enable the hook and a longer PIN scheme |
| SEC-05 | Two-factor (TOTP) for owner/accountant | phase 70/71 | PARTIAL | twofa routes and functions built; real enrolment not verified (WORK_TRACKER) | Who must use 2FA |
| SEC-06 | Server-side permission for every action (hidden button = refused request) | BUILD-RULES 14 | PARTIAL | Scenario refusals proven only for discount (X0), blind count (D1) and GRN link; SECURITY_BACKLOG lists anon-executable definer functions and no-policy tables, no revoke done (PLAN_NEXT 62) | Revoke list after a live check |
| SEC-07 | Append-only audit log and change log | BUILD-RULES 7 | DONE | audit_log, no_hard_delete triggers (phase 8-23) | none |
| SEC-08 | Self-approval blocked by default, owner can allow per role, logged | DECISIONS | DONE | owner_approval_mode (phase 80); scenario D2 sheet approved by a different login | none |
| SEC-09 | Business isolation between several businesses (org_scope_on) | G3; PLAN_NEXT 3 | DONE-OFF switch | phase 123/132/133 behind org_scope_on (OFF); two-business negative test exists as phase123_test (171/0) but was not re-run here | Switch on only when a second business exists |
| SEC-10 | Public repository exposure of SQL/prices | DECISIONS 23 Oct; PLAN_NEXT 55 | DESIGN-NEEDED | Repository visibility is OPEN (documented, not decided); backup/notify workflows refuse to run in a public repo | Make the repo private or use a private backup repo |
| SEC-11 | Secret scan of the full git history | PLAN_NEXT 59 | MISSING | owner/agent task not done in this audit (no live access, no GitHub) | Rotate any real secret found |
| SEC-12 | Edge functions deployed or marked off | PLAN_NEXT 64 | DESIGN-NEEDED | live listing empty (audit F-xx); none needed for core sweets flows | Which integrations are needed |

### Offline

| ID | Requirement | Source | Status | Evidence | Owner must decide |
|---|---|---|---|---|---|
| OFF-01 | POS works offline: sales queue on the phone, replay with client id, 'Not sent yet' state | BUILD-RULES 12 | PARTIAL | record_sale_offline; routes outbox (ia.js:145), posfailed (ia.js:262), web/posfail.js; replay idempotency proven by e2e X4 (not re-run); real-phone offline cold start NOT verified (MERGE_CHECKLIST 'Not done') | none |
| OFF-02 | Service worker: first load works offline | TODO D4 | PARTIAL | web/sw.js exists; needs https and a real phone test (REMAINING 15) | Phone test by the owner |
| OFF-03 | Forms outbox with client ids | ERP_AUDIT_ROADMAP D11 | PARTIAL | entry.js draft/outbox; transfers have none (TRF-12) | none |
| OFF-04 | Late/old offline sale rule | PLAN_NEXT 9, 11 | PARTIAL | see SAL-12 | redate / flag / park |

### Printing

| ID | Requirement | Source | Status | Evidence | Owner must decide |
|---|---|---|---|---|---|
| PRN-01 | Receipt / invoice template per showroom, print after sale | DEMAND_VERIFY G11 | PARTIAL | web/tpl_docs.js, tpl_registry.js, invoiceview route, pos_show_invoice_after_sale; real thermal printer and cash drawer NOT tested (DEVICE_CHECKLIST, HANDOVER_6 P7) | Printer model, paper width, receipt wording |
| PRN-02 | Challan, label and message templates | DEMAND_VERIFY G11 | PARTIAL | tpl_labels.js, tpl_msgs.js; not exercised | Label sizes |
| PRN-03 | Printed form codes unchanged (NN-1 sorted sequence) | N5; FORM_SEQUENCE | DONE | phase 543 applied on the local build ('forms 41, form_code rows 394'); note: tests/sql/e2e and tests/sql/audit2 still use OLD codes (finding D10) | none |
| PRN-04 | Form kit text matching the paper field by field | ERP_AUDIT_ROADMAP 0-1; TODO E2 | DESIGN-NEEDED | Original paper Form Kit text is not in the repository (blocking, owner to supply) | Provide the paper kit |
| PRN-05 | Books printing (printbooks) | ia.js:198 | PARTIAL | route printbooks; placeholder tile in Control Center (REMAINING 14) | none |

### Notifications

| ID | Requirement | Source | Status | Evidence | Owner must decide |
|---|---|---|---|---|---|
| NTF-01 | In-app bell and notification list | DEMAND_VERIFY | DONE | notifications table, route notifications, notifications_unread_count | none |
| NTF-02 | Daily e-mail digest to the owner | N17b | DONE-OFF switch | tools/notify_digest.py, rule notify_email_on (default true); needs GitHub secrets and a private repo (workflow guard added 21 Oct) | Gmail secrets; private repo |
| NTF-03 | SMS / WhatsApp / Telegram messages to customers or staff | ERP_AUDIT_ROADMAP gap 21 | DESIGN-NEEDED | notify_outbox, notify_optin exist; no provider connected (phone-impossible setup); SMS costs money (DECISIONS 11 Oct: no SMS) | Provider and budget |
| NTF-04 | Exceptions list with auto-created items (who, where, how much) | DECISIONS | DONE | exceptions table; scenario shows transit_short, cash_short_over, discount_no_limit, sale_return, landed_unapproved, purchase_backdated rows | none |
| NTF-05 | Receiver notified on transfer; announcements, to-do, shifts | F7; PLAN_NEXT 21 | DONE-OFF switch | announce_on, todo_on, shift_on default off; screens visible to owner (21 Oct fix) | Switch on per need |

### Backup and restore

| ID | Requirement | Source | Status | Evidence | Owner must decide |
|---|---|---|---|---|---|
| BKP-01 | Encrypted scheduled backup to a private place | N17a; PLAN_NEXT 53-54 | DONE-OFF switch | backup.yml refuses a public repo, tools/backup_crypto.py scrypt+HMAC, check_backup_guard.py; never run on the real project (no secrets) | Make repo private or private backup repo; set secrets |
| BKP-02 | Restore drill into a disposable database | PLAN_NEXT 57 | PARTIAL | tools/restore_drill.py and docs/RESTORE_DRILL.md; test_restore_drill.py; real drill not done | Run one drill |
| BKP-03 | Owner button 'download all data' (JSON) | DECISIONS 11 Oct; PLAN_NEXT 78 | DONE | Home > Backup; commit 36254db; phone test pending | Test on phone |
| BKP-04 | Auth users in the backup; attendance device tokens | ERP_AUDIT_ROADMAP 7.2 | PARTIAL | auth users not in dump; token_hash tables excluded | Re-create users from staff list on restore |
| BKP-05 | Drive copy of the backup | F13 | DESIGN-NEEDED | Drive folder is outside the repo - cannot verify | Keep the folder current |

### New-business templates

| ID | Requirement | Source | Status | Evidence | Owner must decide |
|---|---|---|---|---|---|
| NBT-01 | Organization layer: group, businesses, places, per-business scope | G3, G9; phase 122-135 | DONE-OFF switch | org_scope_on OFF; routes organization, profile; places135 test passed in DEMAND_VERIFY | Create the second business when needed |
| NBT-02 | Template for food manufacturing (sweets) is the complete one | N11 | PARTIAL | sweets path complete in code; this readiness audit lists the remaining gaps (sections C/E) | none |
| NBT-03 | Templates for dealership, hardware/paint, technology, construction, online store | N10; phase 122 stubs | PARTIAL | stubs 'not_implemented'; dealer screens cheques/schemes/tinting built (127-129, OFF); import-export (124) and variants (125) built OFF; hidden from the sweets owner by bizgate (21 Oct) | Build order of other businesses (not before sweets is 99 percent) |
| NBT-04 | One-click 'recommended settings' for a new business | setup advisor; docs/guide/RECOMMENDED_SETTINGS.md | PARTIAL | setup_recommend_apply applied 51 rules on the scenario; skipped accounting_on, cost_attrib_in_pl, online_orders_on, inbox_on, web_form_on (not_ready). It leaves out blind_count_on, acct_transfer_mode, acct_transit_loss, report_salary_source, rpt131_on, stock_negative_mode, production_requires_recipe (section D) | Accept the extra recommendations in section D |
| NBT-05 | Setup flow check (readiness before switching modules on) | phase 81 | DONE | setup_readiness, setup_flow_check, setup_apply_history | none |
| NBT-06 | Chart of accounts template per industry and per-entity chart | GROUP_ERP 3.3 | PARTIAL | global chart seeded for a sweets shop; per-entity chart not separated (INTEGRATION_REPORT_8) | Chart for the next business |
| NBT-07 | Bilingual names (bn/en) and three language modes everywhere | BUILD-RULES 13 | PARTIAL | owner word list applied 21 Oct; Bangla review of new labels pending (PLAN_NEXT 73) | Read the Bangla labels |

### Owner decisions and process rules

| ID | Requirement | Source | Status | Evidence | Owner must decide |
|---|---|---|---|---|---|
| DEC-01 | Every decision is a setting with a safe default; new behaviour OFF | CLAUDE.md; BUILD-RULES | PARTIAL | 625 rules; scenario default run has 9 rules set, advisor 60; but safe default conflicts with owner decisions in two places: blind_count_on OFF (decision says mandatory) and discount limit blank blocks sales (rule 15) | Decide: safe-default = old behaviour, or owner decision text wins |
| DEC-02 | No demo or fictional data in the repository | CLAUDE.md; DEMAND_VERIFY R1 | DONE | check_no_demo_leak.py OK before each commit of this audit; scenario uses test_* only | none |
| DEC-03 | Paste order: new SQL only in new phases, safe to paste twice | BUILD-RULES; N19 | DONE | full chain ORDER=all built with 0 errors on PostgreSQL 16.15 in 30 s (2,894 functions, 478 tables); phase 543-546 included | none |
| DEC-04 | Location, staff id and time filled by the system | BUILD-RULES 6 | DONE | scenario: sale/entry rows carry created_by and location from the login; owner and managers did not type them | none |
| DEC-05 | Lists with Add new / Other and per-list add rule | BUILD-RULES 4-5 | DONE | listctl, option_reactivate; 50 selects wired (TODO D1) | none |
| DEC-06 | One profit truth; unknown cost shown as unknown, never 100 percent margin | PLAN_NEXT D-08 | PARTIAL | profit_truth_mode (advisor on); reports show uncosted_pct; sales_summary inconsistency D4 | Confirm the truth (sales after returns, ledger COGS) |
| DEC-07 | Show/hide of whole main features is a later owner decision | N4/PLAN_NEXT 79 | DESIGN-NEEDED | DEFERRED-BY-OWNER; optviews route exists | Decide later |
| DEC-08 | Design: compact two-state layout, form codes sequence | N15; PLAN_NEXT 66 | DESIGN-NEEDED | DEFERRED-BY-OWNER | Decide later |
| DEC-09 | Live database facts (which phases pasted, real data) | F11; N7b | DESIGN-NEEDED | CANNOT-VERIFY from here (no live access by rule); new Supabase project plan docs/NEW_PROJECT_SETUP.md | Owner pastes the chain on the new project |
| DEC-10 | Sweets live records: 10 live sales (4,461 taka) and the sale without item id | PLAN_NEXT 13-14 | DESIGN-NEEDED | OWNER question; the live project is to be replaced by a new clean project (DECISIONS 23 Oct) | Real or test records |

## 3. Part B: the calculation proof

Script: `tests/sql/readiness/rd_scenario.sql`, run by `tests/sql/readiness/run.sh <mode> <db>` on a clone of a fully built database. One scenario, three settings sets: **def** (defaults), **rec** (the setup advisor `setup_recommend_apply`, run twice: 51 rules applied) and **recx** (rec plus six switches this audit found missing from the advisor: `acct_transfer_mode=location_tagged`, `acct_transit_loss`, `blind_count_on`, `report_salary_source=app_first`, `rpt131_on`, `cash_short_post_on`). In all three runs `accounting_on` and autopost are on, the VAT rate is a TEST number (5 percent, prices include VAT; the product leaves it blank).

### 3.1 Inputs and hand-computed expectations

| Step | Inputs (place 6 = cake factory, 1 and 3 = showrooms) | Hand-computed expectation (derived in the script by arithmetic, not from a system function) |
|---|---|---|
| Opening | cash 20,000 (place 1), bank 100,000, capital 120,000 | trial balance balanced |
| Purchase | flour 100 kg @ 40, sugar 60 kg @ 80, box 200 pc @ 5 = 9,800 from supplier one; freight 490 (5 percent by value) to a transporter | landed unit cost flour 42, sugar 84, box 5.25; inventory GL 10,290; supplier owes 9,800 |
| Goods receipt | tape 10 pc @ 3 by GRN form 13-1, then the bill with the link guard | counted once: qty 10, payable +30 |
| Production | recipe A 10 kg = flour 5 + sugar 4 + box 2, conversion 150 per batch, 3 batches; recipe B 5 kg = flour 3 + sugar 2 + box 1, conversion 80, 2 batches | A 70.65 per kg x 30 kg, B 75.85 per kg x 10 kg; overhead absorbed 610; raw left 79 / 44 / 192 |
| Transfer | factory to showroom 1: A 20, B 8; to showroom 3: A 8, received 7.5 | unit cost carried; 0.5 kg short = 35.325 |
| POS | S1 A 2 kg cash 800; S2 B 1 kg card 500; S3 A 1.5 kg bKash-style wallet 600; S4 A 3 kg = 1,200 with 500 cash and 700 due; S5 B 2 kg less discount 50 = 950 cash; S6 (showroom 3) A 4 kg cash 1,600; collection 300; return 0.5 kg A (refund 200); wastage 0.4 kg A | revenue after returns 5,450; COGS 934.05; gross margin place 1 A 1,976.10 / B 1,222.45, place 3 A 1,317.40; due 400 |
| Day close | showroom 1 sheet 06-1: total 4,050, digital 1,100, dues 300, refund 200, credit 700, counted 2 x 1000 + 3 x 100 + 2 x 20 | expected drawer 2,350, counted 2,340, short 10 |
| Supplier payment | 5,000 from bank | supplier owes 4,830; bank 95,000 |
| Payroll | worker A 6,000 with 2 absent days, staff B 4,000; October (31 days) | A net round(6000 - 2 x 6000/31) = 5,613; B 4,000; salaries 9,613 |
| VAT memo | rate 5, inclusive: sales 5,650, returns 200, purchases 9,830 | output 259.53, input 468.10, net payable -208.57 |
| Month end | statements for the month; close preview | net profit and total assets from the hand numbers; the close itself is blocked until 31 Oct (blocker `month_not_finished`, correct) |
| Extra | count flour 78 against book 79; void sale S6 | 5110 = 42; stock and cash back |

### 3.2 Results by section (checks passed / failed)

| Section | def pass/fail | rec pass/fail | recx pass/fail |
|---|---|---|---|
| S setup | 1 / 0 | 1 / 0 | 1 / 0 |
| P purchase, freight, supplier payment | 15 / 2 | 15 / 2 | 15 / 2 |
| G GRN guard and margins | 11 / 1 | 11 / 1 | 11 / 1 |
| M production | 11 / 0 | 11 / 0 | 11 / 0 |
| T transfers | 9 / 2 | 9 / 2 | 11 / 0 |
| X POS sales, return, wastage | 11 / 0 | 11 / 0 | 11 / 0 |
| A books after sales | 12 / 4 | 12 / 4 | 16 / 0 |
| D day close and cash count | 8 / 3 | 10 / 1 | 11 / 0 |
| W payroll | 5 / 1 | 6 / 0 | 6 / 0 |
| V VAT memo | 4 / 0 | 4 / 0 | 4 / 0 |
| F statements | 6 / 3 | 6 / 3 | 9 / 0 |
| R reports against the ledger | 23 / 2 | 22 / 3 | 23 / 2 |
| K count and void | 4 / 1 | 5 / 0 | 5 / 0 |
| Z totals | 2 / 0 | 2 / 0 | 2 / 0 |
| **Total** | **122 / 19** | **125 / 16** | **136 / 5** |

Every failing check is listed with expected and actual numbers in the result files. Checks were written with the **correct business expectation** (books equal stock, cash short is in the books), so a failure at default settings means "the default leaves this unbooked", not a calculation error.

### 3.3 What changes between the three runs

Final state after the whole scenario (including the count and the void):

| Measure | def | rec | recx |
|---|---|---|---|
| Rules with a value set | 9 | 60 | 66 |
| Checks passed / failed | 122 / 19 | 125 / 16 | 136 / 5 |
| Inventory in the books vs stock ledger (10,172.97) | 10,250.29 (books 77.33 too high: short 35.33 + count 42) | 10,208.29 (35.33 too high: short unbooked) | 10,172.97 (equal) |
| 5110 count loss in the books | 0 | 42.00 | 42.00 |
| 5800 cash short/over | 0 | 10.00 | 10.00 |
| 5130 stock short in transit | 0 | 0 | 35.32 |
| Per-place inventory in the books equals the stock ledger | no (place 1 shows -679.71) | no | yes |
| Journal entries | 19 | 21 | 28 |
| Exceptions raised | 6 | 8 | 8 |
| Maker sees expected cash after counting | yes | yes | no (blind) |
| Net profit shown by the P&L (all days) | -5,832.71 | -5,884.71 | -5,920.03 (the figure with every cost booked) |

The advisor skipped five rules as `not_ready` (`accounting_on`, `cost_attrib_in_pl`, `online_orders_on`, `inbox_on`, `web_form_on`): they need data or an external connection first.

## 4. Confirmed mismatches and defects, with a proposed fix

No phase file was edited. Each fix below is a **new phase** (numbers 548 onward are free (547 is the backup coverage phase): `tests/sql/ORDER.txt` ends at 546 on the branch this audit was made on). "Runs" = the runs in which the check fails.

| ID | Function and inputs | Expected (hand) | Actual | Runs | Proposed new phase / fix | Effort |
|---|---|---|---|---|---|---|
| D1 | `landed_save` + `landed_post` with a freight charge `pay_mode=payable`, `supplier_id` = transporter, amount 490; then `supplier_dues(6)`, `pay_supplier(<transporter>, 6, [{"mode":"cash","amount":490}])` | transporter owed 490 and payable | `acct_party_ledger` shows 490 (account 2150), `supplier_dues` shows no row, `pay_supplier` raises `overpaid`; `bill_pay_record` knows only kinds `purchase` and `cost` (scenario P2, P3) | def, rec, recx | phase 548: `supplier_dues`, `supplier_ledger`, `supplier_open_bills` include party-tagged 2150 lines; `pay_supplier` pays them (Dr 2150, Cr cash/bank/wallet). Old text stays; change by patch-at-anchor with tag check | M |
| D2 | `stock_receive_transfer(<transfer of 8 kg>, 7.5)` | 0.5 kg x 70.65 = 35.325 loss visible in stock and books | default: no ledger loss row, no journal; rec: costed ledger row `transit_loss`, but no journal (rule `acct_transit_loss` OFF): inventory in the books 35.325 above the stock ledger (scenario T3, A2, F1, R12) | def, rec | advisor change (D6) to set `acct_transit_loss`; owner decides whether the bearer is shop or carrier (`transit_short_bearer`) | S |
| D3 | `stock_transfer` x3 then `stock_receive_transfer`; compare inventory GL by place with `stock_balance` value by place | place 6: 8,345.00; place 1: 1,340.09; place 3: 247.275 | def/rec: place 6 10,930.00; place 1 -679.71; place 3 -282.60 (company total equals only after D2). With `acct_transfer_mode=location_tagged` all places equal (recx) (scenario A2) | def, rec | advisor change (D6) to set `acct_transfer_mode`; owner chooses location-tagged or company-wide (open question since 14 Oct) | S + owner |
| D4 | `report_run('sales_summary', {from,to}, 'location')`, place 1 | gp = net after returns 3,850 - COGS after return 651.45 = 3,198.55 (ledger, `biz_daily`, `l1_pnl`, `l2_margin` all say so) | gp 3,363.22 (= 4,050 - 686.78: returns left out although `net_after_returns` 3,850 is in the same row; `reports_net_of_returns` already true) (scenario G3) | def, rec, recx | phase 549: in the `sales_summary` branch of `report_run` compute `gp`, `gp_pct` from `net_after_returns` and return-netted COGS | S |
| D5 | `count_save(<06-1 entry>, 'drawer', {...})` called by the showroom manager | maker gets only `saved` and `counted` (BUILD-RULES 9, owner decision 11 Oct "mandatory by default") | returns `expected` 2,350 and `diff` -10 while `blind_count_on` = false (default and advisor); hidden only in recx (scenario D1) | def, rec | advisor change (D6) and an owner decision on the default; no code bug | S |
| D6 | `setup_recommend_apply` (twice) | the advisor's set should make the books equal the stock and the count blind | applies 51 rules, omits `acct_transit_loss`, `acct_transfer_mode`, `blind_count_on`, `report_salary_source`, `rpt131_on`, `stock_negative_mode=block`, `production_requires_recipe`, `payroll_accrual_on`, `pin_signature_on` | def, rec | phase 550: add these as recommendations (each with its readiness check and reason text); the owner still taps apply | S |
| D7 | `report_run2('t3_payroll', {month})` after two paid payroll runs | net pay 9,613 | totals net_pay null / 0 (reads paper sheets 02-2/02-3 only); `l1_pnl` carries salary only when `report_salary_source=app_first`; `c2_salary_basis` does show runs_paid 9,613 (scenario R18b passes, R18c fails) | def, rec, recx | phase 551: T3/T4 read `payroll_lines` when runs exist for the month (same switch as L1) | M |
| D8 | `stock_recon_period(from,to,3)` after `transit_short_mode=loss` | unclassified 0 | row test_sweet_a place 3: `unclassified` -0.5, state `unclassified` because reason `transit_loss` is not in the list of movement reasons (scenario R17) | rec, recx | draft written and tested: `supabase/phase548.sql` (separate commit, NOT yet in `tests/sql/ORDER.txt` or `docs/PASTE_ORDER.md`): reads the function text, adds `transit_loss` as a listed movement; on a clone of the recx database the unclassified row went from 0.5 to 0, paste twice clean, grants unchanged (anon no, authenticated yes) | S |
| D9 | Sheet 06-1 drawer count | expected cash filled from the POS day close (2,350) | expected is computed from typed sheet figures (`_count_expected18`); POS day-close report gives the same 2,350 (scenario D2) but nothing compares or fills it | all | phase 552 or a screen change: prefill and compare, exception when typed totals differ from POS | M |
| D10 | `tests/sql/e2e` and `tests/sql/audit2` | pass on the current tree | use pre-renumber form codes (04-1 = old GRN, now Cash Position and Budget; 10-2 = old expense voucher): `entries_form_code_fkey` violations, 'form is switched off'; audit2 'switches ON' pass switches on all 165 switches including mutually conflicting ones (`lot_required`); 84 unmapped FAILs in that pass | n/a | update fixtures to the NN-1 codes through the mapping in `docs/FORM_SEQUENCE.md`; separate pass for conflicting switches | M |

Items that look like defects but are **safe defaults** (documented, owner chooses): cash short/over and count loss unbooked by default (`drawer_short_post`, `acct_count_adjust`), salary expense at payment (`payroll_accrual_on`), blind count off, stock negative mode warn, GRN as source off, `rpt131_on` off.

The scenario also confirmed these controls working as designed: GRN link guard (no double count), discount refused without a written limit, overpayment of a supplier refused, expired-stock rules not triggered, journal always balanced, replay by client id (earlier e2e).

## 5. Reports against the ledger

All 120 entries of the three report catalogues (`report_catalog`, `report_catalog2`, `report_catalog3`: 19 + 55 + 46) ran on the scenario data with 0 errors (check R21). Agreement with the ledger (checks R1-R20): payment modes, customer dues, supplier ageing, stock balance (value 9,932.365 before the extra count), `l1_pnl`, `l2_margin` (both products, place 1 alone, both places), `l3_shop_pnl`, wastage (report = GL), `transfers_gap` (0.5 kg), wallet reconciliation, `w1_cash_flow`, `profit_source_check`, `acct_party_ledger`, `stock_reconcile` all agree with hand numbers in every run. Exceptions: `sales_summary` gp (D4), `t3_payroll` (D7), `stock_recon_period` in rec/recx (D8), and the books-versus-stock checks that depend on D2/D3. The verified-report family `rpt131_*` answers `feature_off` until `rpt131_on` is switched on. `report_parity` covers salary and expenses only (not sales).

Registry status of the 193 listed reports (`web/data/report_registry.json`): 170 implemented, 20 incomplete, 2 unverified, 1 unavailable.

## 6. Part C: top 15 gaps to close for 99 percent, by business risk

Effort: S = under a day, M = a few days, L = a week or more (agent work; owner or accountant time is named separately).

| # | Gap | Why it ranks here | Effort | Who |
|---|---|---|---|---|
| 1 | Backup and restore proven on the real (new) project; repository visibility decided; secrets set | Losing the books loses the business. Backups never ran for real; the workflow refuses a public repo; no restore drill (BKP-01/02, SEC-10) | S | Owner |
| 2 | Real phone, thermal printer, cash drawer and offline cold-start test (UAT checks 65-94) | Day-one failure at the counter; nothing verified on a device (OFF-01/02, PRN-01) | M | Owner + agent |
| 3 | Server-side PIN lockout (Auth hook) and a stronger PIN scheme | Weakest login control, postponed by owner (SEC-04) | S + M | Owner, then agent |
| 4 | Books equal stock after every loss and move: advisor adds `acct_transfer_mode`, `acct_transit_loss`, count and cash short switches (D2, D3, D6) | Without them inventory and profit are overstated and branch balance sheets are wrong | S | Agent + owner (location-tagged vs company-wide) |
| 5 | Count-first by default and the cash expected figure filled from POS (D5, D9) | The owner's control rule 9 is off by default; typed expected cash can hide a short | S + M | Agent + owner |
| 6 | Freight / transporter payable visible in supplier dues and payable (D1) | Money owed that no list shows; payment impossible | M | Agent |
| 7 | VAT in the ledger and Mushak 6.3 / return data, after the adviser gives rate and method (TAX-02/03) | Statutory exposure; today only a memo; rate blank | L | Accountant, then agent |
| 8 | One profit truth: fix `sales_summary` gp (D4) and staff-cost reports T3/T4 (D7), D-08 decision | Two reports give different profit; owner decisions rest on them | S + M | Agent + owner |
| 9 | Payroll: accrual option, statutory deductions (PF, tax at source, gratuity) | Salary is the largest cost; expense by month and legal deductions are missing (PAY-05, PAY-09) | M-L | Accountant, then agent |
| 10 | Month-end overhead true-up (under/over absorbed) and month close run | Product cost and monthly profit drift without it (PRD-05, ACC-05) | M | Owner rule, then agent |
| 11 | Security review: revoke anon-executable definer functions after a live check; permission tests for every write RPC | Hidden button must be a refused request (SEC-06); list exists, no revoke done | M | Owner (live check) + agent |
| 12 | Refresh stale test suites to the NN-1 form codes and run them in CI (D10) | Regressions are invisible; two big suites no longer run clean | M | Agent |
| 13 | Purchase order as a controlled document with open quantity and 3-way match tolerance (PTP-05/06) | Purchasing is paper-copy today; over-buying and price drift are caught only by reports | L | Owner decides need, then agent |
| 14 | Transfers: multi-line challan, transfer price option, offline outbox, receipts for partial deliveries as default (TRF-10/11/12) | Daily factory-to-showroom flow works but is one item at a time | M | Owner + agent |
| 15 | Contribution margin, combos / gift boxes, by-products, costing method FIFO (PRD-12, STK-14, STK-02, RPT-08) | Needed for decisions and special products, not for daily operation | L | Owner decisions first |

### Recommended build order

1. **Owner actions that need no code** (rows 1, 3 part one, 2 planning): private repository or private backup repo, secrets, one restore drill, enable the Auth hook, start the phone/printer UAT.
2. **Small settings phase** (rows 4, 5 part one, D6): phase 550 adds the missing recommendations; decide location-tagged vs company-wide first. Re-run the scenario: expect recx-like result with the advisor alone.
3. **Small fixes** (D4, D8): phase 549 and 548 (drafted; first drafted as 547, renamed because 547 is the backup coverage phase). Re-run the scenario.
4. **Freight payable** (row 6) and **staff-cost reports** (row 8, D7): phases 548 and 551.
5. **Cash close**: prefill from POS (D9), then switch blind count on in the live routine.
6. **Test refresh** (row 12) so every later phase is checked automatically.
7. **Accountant block** (rows 7, 9, 10): VAT posting, payroll accrual and deductions, overhead true-up. Start when the accountant has given rates and rules.
8. **Owner-driven extensions** (rows 13-15) only after the sweets business has run a month on the above.

## 7. What could not be verified, and an incident

- No live Supabase and no real phone, printer, drawer, fingerprint device or bank: all device rows are code-read only.
- The Islamiya read-only audit (F-01...F-19) is not in the repository; F items are taken from `PLAN_NEXT.md` as quoted there.
- The month close itself could not run: today is 24 Oct and the checklist blocks an unfinished month (`month_not_finished`). Preview numbers matched the P&L.
- Not exercised in the scenario (present in code, covered only by older suites): card settlement, bank statement import, fixed assets, budgets, orders with advance, online orders, year close, cheque, partner settlement, 2FA, backup run, notifications sending.
- Payroll used inserted attendance rows (fixtures) and a day-rate of salary / calendar days; the real policy (working days, Friday) is an owner decision and was not tested.
- The audit2 harness (84 gaps) was re-run on this tree: defaults 494 probes pass / 205 fail (gaps: 9 PASS, 47 FAIL, 5 NOT SUPPORTED, 23 NO PROBE); "switches ON" pass 457 / 230 (22 PASS, 32 FAIL, 5, 25). Many FAILs are stale probes (old form codes, conflicting auto-switches, D10); its status column was corrected only where this audit's scenario proves another result.
- Unit tests of the web (`tests/web`) were not run; only SQL.
- **Incident:** another session's PostgreSQL cluster was listening on port 5544 (`/var/tmp/pgdata_bk`). My first start of `tests/sql/audit2/run_all.sh` used that port before I noticed; it created and dropped databases named `b5run`/`b5run_on` there for about a minute before I stopped it. If that session was using a database with that name, it may have been dropped and rebuilt; I touched nothing else and did not use that cluster again. All results above come from my own cluster (port 5777, data in `/tmp/pgw`).
