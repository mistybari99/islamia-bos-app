# Group ERP — Stage A: audit and architecture blueprint (READ-ONLY, no code changed)

Status: **Stage A APPROVED by the owner with the changes in section 10; Stage B1 approved (scope in section 11).** Sections 1-9 are the original audit; where section 10 differs, section 10 wins. Only B1 is being built; nothing else below is implemented. Evidence = repo paths at branch `ccr-46b26d91-81vl9s` (HEAD `dbecc25`).
Honesty note: this audit is a *sampled* read (docs, schema.sql, phase2/7/16/40 SQL, greps over `supabase/*.sql` and `web/*.js`), not a line-by-line review of all 705 files.
Items marked **[unverified]** need a deeper read or a live-database check before they are relied on.
No live Supabase was available, so nothing here is verified against real data.

## 0. Protecting running work
- Working tree clean at start (`git status` empty). No other local Claude session was reachable (ListAgents: none).
- `origin` has ~90 side branches (`fix/phase-*`, `audit/*`, `qa/*`, `integration/p72-p79`, other `ccr-*`). Another chat may be using one of them: **owner must confirm which branch/phase numbers are in use before Stage B** (latest SQL file is `phase79.sql`).
- Rule for Stage B+: only one chat edits `web/ia.js`, `web/index.html`, `supabase/phaseNN.sql` numbering at a time (same fence as `docs/briefs/00_RULES.md`).

## 1. What exists today (evidence)
| Area | Finding | Evidence | Class |
|---|---|---|---|
| Platform | Supabase Postgres + plain-JS PWA, no build; Supabase free plan, GitHub Pages; web/ goes to a separate PUBLIC repo, costs never in public repo | `docs/DECISIONS.md`, `docs/briefs/00_RULES.md` | Fact |
| Size | ~208 tables, 79 phase SQL files + `_test.sql`, ~100 web modules | `supabase/`, `web/` | Fact |
| Organization | **Flat** `locations` table (id, code, name, kind in showroom/factory/godown/hub/online/other, status planned…closed, `supplied_by`). **No parent/child, no business/legal-entity/tenant table. No `business_id`/`tenant_id`/`company_id` anywhere** | `schema.sql:31`, `phase16.sql:30-60`; grep for tenant/business ids = 0 hits | Missing |
| Location scoping | `can_loc(loc)` = owner OR role `management` OR row in `user_locations`; 102 SQL files mention `location_id` [exact count of scoped tables unverified] | `phase2.sql:64`, redefined `phase7.sql:277` (latest definition **[unverified]**) | Implemented, single-tenant |
| Roles/grants | Global roles + `grant_defs` + role×form matrix + `has_grant(code[,loc])`; staff ID+PIN login | `docs/DECISIONS.md`, `phase2/7/16` | Implemented |
| Accounting | Double-entry exists: `coa_accounts`, `journal_entries`, `journal_lines` (append-only, reversing entries), `acct_mappings`, auto-post from sales/purchases/expenses/etc. Rule `accounting_on` is **OFF by default**. One global chart; entries carry `location_id` only | `phase40.sql:35-110` | Implemented, not verified on live data, single-ledger |
| Reports | `web/reports.js`, `reports2.js`, `ownerboard.js`; REMAINING.md says 34 of 65 reports not built (as of phase 21) | `docs/REMAINING.md` | Incomplete |
| Costing | Recipes/BOM, production, overhead pools, cost attribution to locations (phase 72–79) | recent commits `c8c4f56`, `1669f37`, `f8d786c` | Implemented, recent |
| Controls | Audit log, correction log, release/emergency requests, period lock, idempotency keys, append-only history, RLS on all new tables | `docs/briefs/00_RULES.md`, `phase23.sql` | Strong, reusable |
| Known gaps | GRN vs purchase both post `purchase_in` (possible double count); sale-return not netted in some reports; no service worker; server-side PIN lockout needs Auth hook | `docs/REMAINING.md` items 10,12,15 | Open |

## 2. Hardcoded single-business assumptions (blockers for "any new business")
1. **No organization layer above `locations`** — a second business would have to share one location list, one item master, one chart of accounts.
2. **Brands hardcoded in JS**: `web/app.js:14` (`BRAND` hub/bari/cakiz), `web/forms_cash.js:34,300` (showroom + brand lists), `web/forms_factory.js:259` (`BRANDS`), `web/forms_sales.js:298`, `web/forms_staff.js:317-318` (duty slots naming the four sweets showrooms). They have DB-driven first choices with **hardcoded fallbacks**; brand is mapped by `report_brand_map` (`phase9.sql:33`), not stored on sales.
3. **Location codes/kinds baked into migrations**: phase16 seeds `cake_factory`, `mishti_factory`, `godown`, `main`; `kind` CHECK list is a closed set (`locations_kind_chk`).
4. **Global master data**: items (1,312), customers, suppliers, employees have no owner-unit scope **[unverified per table]**.
5. **Single global CoA** seeded as "bakery / sweets-shop chart" (`phase40.sql` header); `journal_entries` has no legal-entity column.
6. **Roles are "business-common" sweets roles** (showroom manager, storekeeper, factory in-charge…), `management` role bypasses all location checks (`can_loc`) — would leak across businesses.
7. **Public web repo** holds the app: a multi-business UI still ships to every device; secrets/costs must stay server-side (already the rule).
8. Language/labels are Bangla/Banglish for the sweets domain (extendable, not blocking).

## 3. Target design (recommendation)
### 3.1 Key decision — one database, add an org layer (recommended) vs one Supabase project per business
| | A. One DB + org tree (recommended) | B. Project per business + aggregator |
|---|---|---|
| Cost | stays on free plan until limits | each project = free-plan limits, more owner admin |
| Isolation | RLS by org scope (must be proven by tests) | physical isolation |
| Group dashboard | simple SQL | needs cross-project sync/ETL (hard on free tier) |
| Risk to sweets | schema change on live system | none |
Recommendation: **A**, built *additively*, with a **read-only owner view** first. **Owner approved A, with strict isolation (section 10).** Revisit B only if a business needs hard physical separation (e.g. separate legal owners/partners). 
### 3.2 Org model (additive, idempotent, no table rewrites)
```
org_units(id, parent_id, kind[group|legal_entity|business|branch|site|department|cost_centre|project],
          code, name_bn/en, template_id, status, effective_from/to, currency, tz, geo jsonb, attrs jsonb)
legal_entities(org_unit_id, tax_cfg jsonb, fiscal_start, base_currency)       -- only where truly separate legally
locations.org_unit_id  -> existing locations become leaf nodes (kind showroom/factory/godown…) — NO id change
```
- Key idea: **do not add `business_id` to ~200 tables.** Scope is *derived*: every transactional row already carries `location_id` → location → org_unit → business/legal entity. Only **master data** (items, customers, suppliers, employees, CoA) gets an explicit `scope` (`group | legal_entity | business | location`) column.
- Dynamic attributes: **hybrid** — typed columns for anything queried/posted (money, stock, dates), `attrs jsonb` + `attr_defs(entity, key, type, validation)` for per-industry extras. **No pure EAV** for transactional data (slow, unsafe for accounting).
- Deactivate = `status`/`effective_to`; never delete (consistent with `no_hard_delete()`).

### 3.3 Accounting
- Add `legal_entity_id` to `coa_accounts` (nullable → default entity "sweets") and `journal_entries`; CoA templates per industry copied on entity creation. Existing entries back-filled to the sweets entity by migration (reviewed, dry-run first).
- Divisions inside one legal entity use cost-centre/location dimensions (already on `journal_lines.location_id`), not separate ledgers.
- Group consolidation = **view/function**, not stored: sum entities, translate currency if any, eliminate `intercompany` pairs. New `intercompany_links(entry_a, entry_b, kind)` + elimination accounts. **Needs professional accounting validation; tax/statutory not invented.**

### 3.4 Access control
- Replace `can_loc(loc)` internals with `can_scope(org_unit)`: owner → all; user grants `(user, org_unit, role)` inherited downward. `management` role stops being global; becomes "all locations of *its* business".
- Every SECURITY DEFINER function keeps `p_client` idempotency + `set search_path`; add negative tests: user of business A cannot read/write B via id swap, RPC param, or direct table select (RLS select policies today are mostly `is_active()` — **must be tightened per table; scope of work unverified, likely largest cost**).

### 3.5 Templates / module activation
`business_templates(code, modules[], default_coa, role_presets, workflows jsonb, status)` and `org_modules(org_unit_id, module, state[active|configured|needs_setup|planned|not_implemented])`. The existing `rules` + `grant_defs` mechanism (per-feature ON/OFF) is reused as the activation switch. Sweets = template `food_manufacturing` mapped to current phases 1–79. Dealership/tech/construction/digital templates ship as **records with `not_implemented`**, no screens.

### 3.6 Owner Group dashboard
Reuse `ownerboard.js`/accounting reports with an org filter; show per-unit `data_status` (ok / partial / not_implemented) — never a fake zero (matches existing "empty = data needed" rule in `DECISIONS.md`). Drill-down group → business → location → journal entry using existing reports.

## 4. Reuse-versus-build matrix
| Capability | Decision |
|---|---|
| Auth, PIN, roles, grants, rules, audit/correction log, release requests | **Reuse**; extend scope check |
| Locations | **Reuse as leaf**; add `org_unit_id` |
| Org tree, legal entity, templates, module activation, attr_defs | **Build** (new tables, additive) |
| Journal/CoA | **Reuse**; add `legal_entity_id`, per-entity CoA, intercompany |
| Items/customers/suppliers | **Reuse**; add `scope` |
| Stock ledger, production, costing | **Reuse** unchanged for sweets |
| Reports/ownerboard | **Reuse**; add org filter + data_status |
| Hardcoded brand/location lists in web | **Replace with DB-driven** (small, safe change) |
| Dealership/tech/construction/digital workflows | **Do not build now** |

## 5. API / permission boundary
Keep "all writes through SECURITY DEFINER RPCs" (no REST table writes). New RPCs: `org_unit_save/deactivate`, `template_apply` (dry-run first), `module_set`, `scope_grant`, `group_dashboard(from,to,unit)`. No arbitrary SQL, no service key in the browser.

## 6. Migration, rollback, regression plan
1. Create new tables empty (additive). 2. Insert group + sweets legal entity + business + map the 7 existing locations (`locations.org_unit_id`), **dry-run report first, owner approves**. 3. Back-fill `legal_entity_id` on CoA/journal with a reconciliation query (trial balance before = after, row counts equal). 4. Switch `can_loc` to scope-based behind a rule flag `org_scope_on` (default OFF → identical behaviour). 5. Turn flag ON in a test DB, run full SQL+Playwright suites (`tests/sql/build_fresh_db.sh`, `tests/web`). 6. Rollback = flag OFF; new columns are nullable so old code keeps working; no data deleted/renamed. Backup before each step (owner's "download all data" + `tools/backup_dump.py`; restore drill `docs/RESTORE_DRILL.md`).

## 7. Roadmap (estimates are rough; unverified)
| Stage | Content | Depends on | Effort | Main risk |
|---|---|---|---|---|
| B1 | org_units + legal_entities + map existing locations (no behaviour change) | owner approval, branch/phase numbering | S–M | none (additive) |
| B2 | UI "Organization" admin + DB-driven brands/locations (remove fallbacks) | B1 | M | web fence conflicts |
| C1 | Scope-based access (`can_scope`) + RLS tightening + isolation tests | B1 | **L** | leaks if any table missed |
| C2 | Master data `scope`, per-entity CoA, back-fill | B1 | M | accounting reconciliation |
| D | Templates + module activation (records only) | B1 | S | mislabelling "ready" |
| E | Intercompany + consolidation functions | C2 | M | needs accountant review |
| F | Owner group dashboard | C1, E | M | partial data honesty |
| Final | Migration rehearsal, backup/restore, regression | all | M | live-DB not available to me |

## 8. Acceptance criteria (from the directive, made testable)
- New business + branches created from UI with zero code change; second business has independent branches.
- User of business A gets 0 rows / error on B via direct select, RPC param swap, id guess (SQL tests per table list).
- Sweets regression: trial balance, stock balances, sales totals identical before/after migration (checksum queries).
- Dashboard includes new unit automatically; unimplemented modules show "not implemented", never 0.
- Deactivating a unit keeps all history; all new tables RLS + audit trigger + idempotent re-run.

## 9. Open questions for the owner (ANSWERED in section 10; kept for history)
1. Legal reality: are the future businesses separate legal entities (separate trade licence/tax/partners) or one proprietorship?
2. Approve option A (one DB) vs B (project per business)?
3. Which branch/phase numbers is the other chat using? Reserve phase80+ for this work? (ANSWERED: phase122+, see section 10d.)
4. Is the existing sweets accounting (`accounting_on`) actually switched on and in use on the live DB? (changes migration risk)
5. Free-plan limits (DB size, connections) acceptable for group growth, or is a paid plan authorised later?
6. Should `management` role stay group-wide, or become per-business?

## 10. Owner decisions (recorded after Stage A review)
### 10a. Business model
- Every business is a **separate legal entity** (own trade licence, own books), all owned by the one owner. Partnerships may come later (see below).
- **Strict data isolation** between businesses. Option A (one database with an org layer) is approved, but isolation must be strict and proven by tests (a user of business A gets nothing from B by direct select, RPC parameter swap or id guess).
- **No cross-business transactions today.** Each business keeps its own books.
- **Master (group) dashboard is visible to the owner only.**
- **Partnerships later:** ownership percentage per business (`legal_entities.owner_pct`, default 100) plus a "my share" view. Not built beyond the column in B1.
- **Build about 70% generic foundation now** (org tree, scope, templates, accounting dimensions). **Industry workflows (dealership, hardware+paint, technology, construction, online store) are NOT built now**; they exist only as `not_implemented` template records.

### 10b. INTERCOMPANY (kept as planned; default OFF; not in B1; built in Stage E)
- Paired entries, one in each business's books, bound together by one **link id**.
- **Per-pair enable by the owner**; the whole feature stays OFF until the owner enables a pair.
- **Owner or an explicit grant only, with approval** before posting.
- **Elimination** of the pair in group totals.
- **Due-from / due-to accounts must match**; a mismatch raises an alert.
- **Only amount and date cross the boundary** between the two businesses; no other data is visible to the other side.
- Needs accountant review before use (as in 3.3).

### 10c. New risks from docs/HANDOVER_6.md (MULTI-BUSINESS section, branch origin/ccr-9c1f9be7-3s9qnz)
1. **Global `rules` and grants**: all ~31 audit switches, `grant_defs` and `profit_variable_heads` / `branch_stmt_ageing_hours` are global, not per business.
2. **`management` role bypasses `can_loc`** (leak across businesses once a second business exists).
3. **Single chart of accounts**: new GL accounts (5800 cash short, 5810 bank fee, 4900 bank interest, 2400 overhead pool, transit loss 5110-5140) go into one global chart; `journal_entries` has no legal-entity column.
4. **`profit_truth112` is company-wide**: one net profit across all locations; must become per business (also the dashboard tile).
5. **Global item master** (items, customers, suppliers, recipes, pools, cost types, `location_cost_cfg`); phase116 semi-finished / ingredient rules assume one item master.
6. **Hardcoded brand lists** remain in `web/app.js`, `forms_cash.js`, `forms_factory.js`, `forms_sales.js`; location `kind` is a closed set; new screens (recon118, cost116) have no business switcher.
7. Paste chain is one chain for one database; the public web repo ships one bundle for all businesses.
New read functions (stock_recon_statement, factory_branch_statement, net_profit_report) already scope by `can_loc` + `has_grant(code, loc)`; that is the base to extend.

### 10d. Phase numbering
**phase122 and above** for this work. phase121 is the last used; phase119 is a test file only; phase120 is installed (merged, report speed). Keep one chat on `supabase/phaseNN.sql` numbering at a time.

## 11. Stage B1 (approved): scope, non-scope, rollback, acceptance
**Scope (additive only, zero behaviour change), `supabase/phase122.sql` + `phase122_test.sql`:**
- New tables `org_units`, `legal_entities` (with `trade_licence_ref`, `owner_pct`), `business_templates`; nullable `locations.org_unit_id`.
- Seed one group, one legal entity + business for the existing sweets business; map existing locations by code (idempotent, fills nulls only). Seed templates: `food_manufacturing` = available (sweets), the five other industries = not_implemented.
- Rule `org_scope_on`, default OFF. Read functions `org_tree()`, `org_unit_scope(location_id)`; write functions `org_unit_save`, `org_unit_deactivate` (owner or grant `org_manage`; SECURITY DEFINER, idempotent `p_client`, audit, no hard delete).
- RLS on all new tables, no direct writes, anon has no access.

**Non-scope (not touched in B1):** `can_loc`, any existing function or report, RLS of existing tables, accounting (`legal_entity_id`), master-data scope, UI, intercompany, group dashboard, industry workflows.

**Rollback:** rule stays OFF and nothing reads the new objects, so old behaviour is unchanged. To remove: drop the new functions and tables and the nullable `locations.org_unit_id` column; no existing data is changed. Backup before pasting (as in section 6).

**Acceptance tests (phase122_test):** (1) second business plus branches created through the functions with no code change; (2) deactivation keeps history; (3) non-owner without `org_manage` is refused; (4) anon cannot execute; (5) second paste = no error; (6) every existing sweets location is mapped; (7) sweets report totals unchanged before/after; (8) idempotency key returns the same result without a second row. Full SQL suite and both e2e modes must stay at baseline.

## 12. Added by owner: Import-Export business (template `import_export`)
- Separate business, own legal entity and books like all others. Registered as a **business template record, status `not_implemented`**; no workflows are built in B1/B2/C1. Seeded by a small later phase (after phase123) so it does not collide with the work in flight.
- Foundation needs it will use (planned, not built): multi-currency (document currency + base currency, FX rate per document, realised/unrealised FX gain-loss accounts), shipment/consignment as a project-like cost centre, landed cost (reuse existing phase97 landed-cost design), customs duty/VAT/tax lines as configurable (never invented), letter-of-credit / advance-payment tracking, bank guarantee and payment-terms schedules, HS code and country-of-origin attributes via `attrs`/`attr_defs`, document set (invoice, packing list, bill of lading) as attachments, supplier/buyer parties scoped to this business only, inventory in transit.
- Open owner questions before building: import, export or both; which currencies; customs agent/CNF workflow; whether goods ever flow to another of the owner's businesses (would require the Stage E intercompany feature).

### 12.1 Owner answers (Import-Export)
- Both import and export.
- Currencies: a small configurable list of common currencies (base currency plus a few; the owner edits the list, none hardcoded).
- Goods flowing into another of the owner's businesses: not needed now. Keep it simple; the Stage E intercompany feature stays planned, default OFF, not built.

## 13. Added by owner: Fashion / Cloth business (template `fashion_apparel`)
- Separate business, own legal entity and books. Template record, status `not_implemented`; seeded with `import_export` in the later template-seed phase. Nothing built now.
- Foundation requirement (must not be blocked by today's design): the item master must support **variants** (one style -> size x colour x fabric SKUs, barcode per variant, stock per variant per location). Today `items` is flat and `items.code` is globally unique (see audit_c1/RLS_ISOLATION_AUDIT.md), so B-stage work must allow per-business item codes and a style/variant parent-child link via `attrs`/`attr_defs` or a `parent_item_id`, without changing sweets items.
- Planned later (not built): season/collection, size-colour matrix entry (purchase, stock, POS), exchange/return rules, consignment/wholesale price lists, tailoring/custom orders, fabric/raw material and cut-make-trim costing (reuse the existing recipe/BOM + costing engine as a manufacturing template if the owner produces garments), aged-stock/markdown reports.
- Open owner questions before building: retail only or also wholesale/manufacturing/tailoring; online sales needed; sizes/colour scheme per product group.

### 13.1 Owner answers (Fashion / Cloth) - all options wanted
- Retail AND wholesale AND manufacturing AND tailoring/custom orders (all four, as modules the owner can switch on per business).
- Online sales needed (needs the later online-store template/channel stock sync; stock per variant is the shared source of truth).
- Size/colour scheme: configurable per product group, owner edits the lists; support every common scheme (alpha S/M/L, numeric, free-size, kids age bands, colour + fabric attributes).
- Consequence for foundation: variant (style -> SKU) model, per-business item codes, price lists by channel (retail / wholesale / online), and recipe/BOM-based costing are required ahead of the fashion template going beyond `not_implemented`. Build order stays: foundation (B/C stages) -> variant item model -> fashion retail slice -> wholesale/online -> manufacturing/tailoring.

## 14. Owner detail: Dealership business (paint dealer + hardware, templates `dealership` and `hardware_paint`)
- Mainly a **colour/paint dealer** for several principal companies (owner named Asian, Berger, Classic and more; the list is owner data, never hardcoded), plus paint accessories, **hardware, sanitary, home items, electrical and hardware tools**. Two branches today; unlimited later (branches = org_units).
- Foundation needs (planned, not built now): principal/company ledger per supplier (purchases, schemes, rebates, targets, claims, returns, reconciliation); item categories per owner list (paint, hardware, sanitary, home, electrical, tools); pack sizes and unit conversion (litre/kg/pack/carton, retail vs bulk); batch/lot and shade/colour code with expiry where relevant; tinting/shade-mixing as a service with consumption of base + colorant (BOM-like, reuse recipe engine); B2B party credit ledgers with credit limit and ageing for contractors/painters/retailers; multi-warehouse and inter-branch transfer inside the same business; price lists per customer type; dealer scheme/discount tracking; cheque/PDC tracking [owner to confirm]; delivery/challan.
- Reuse: existing credit ledger, supplier reconciliation, stock transfer (receiver check), landed cost and costing engine from the sweets system; none of it changes for sweets.
- Open owner questions before building: tinting machine used? cheque/PDC and bank-guarantee handling needed? principal schemes (slab, target rebate) in scope for v1? item count per branch.

### 14.1 Owner answers (Dealership)
- Tinting machine: yes. Cheque / post-dated cheque handling: yes. Principal schemes (slab, target rebate): yes, wanted. Item count: large (thousands per branch likely).
- Consequences for foundation: (a) item master and every item list/search/POS/report must be built for large catalogues (server-side paging and search, indexes, bulk import/edit like the existing bulkitems.js, barcode/scan), validated against the sweets 1,369-item baseline and a synthetic 20k-item load test before the dealership template leaves `not_implemented`; (b) cheque/PDC register (received/issued, due date, banked, bounced, replaced) tied to party ledgers and bank reconciliation; (c) scheme engine (slab, target rebate, claim to principal, accrual vs claim reconciliation); (d) tinting as BOM-style consumption with shade formulas per base and pack; (e) all scoped per business, never shared with sweets item codes.
