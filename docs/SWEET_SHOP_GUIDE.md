# Sweet Shop System: Short Guide

Source: `docs/MODULE_MAP.md` and the `web/` screens. Short by design.

## 1. Business flow (end to end)
1. **Purchase:** requisition → quote → purchase order → goods received (GRN) → bill check → supplier ledger.
2. **Stock:** received goods go to the godown or factory stock. Every move is recorded in the stock ledger.
3. **Production:** recipe card + daily sheet → production run uses ingredients and makes finished items.
4. **Transfer:** factory or godown sends goods to a showroom with a transfer challan. Receiver checks and confirms.
5. **Sale (POS):** showroom sells by item (kg / piece / pound). Stock falls at the showroom.
6. **Cash:** drawer count → day close → cash handover to hub → digital payment reconciliation.
7. **Dues:** credit sales go to customer ledger; collection reduces the due.
8. **Control:** variances create exceptions; approvals and release requests keep the books clean.
9. **Owner reports:** P&L, KPIs, dashboard shows problems first.

## 2. Roles

| Role | What they do |
|---|---|
| **Owner** | Sets rules, limits, grants; approves exceptions and big changes. |
| **Management** | Views all locations; approves most requests. |
| **Showroom manager** | Runs one showroom: sales, cash, transfers in. |
| **Salesperson / cashier** | Makes POS sales, collects payments. |
| **Storekeeper** | Receives goods, issues material, runs stock count. |
| **Factory in-charge** | Runs production, yield tests, daily sheet. |
| **Purchasing** | Requisitions, quotes, purchase orders. |
| **Cash controller** | Counts drawer, handovers, bank deposit. |
| **Party coordinator** | Customer orders, dues, invoices. |
| **HR** | Attendance, salary sheet, advances, leave. |

## 3. Key controls (short)
- **Blind count first** for cash and stock handovers.
- **Red flag** blocks day close; staff requests release, owner decides.
- **Limits** per location: discount, expense, cash tolerance, count tolerance.
- **Self-approval** blocked by default.
- **Audit log** and correction note for every change.
- **Books closed until** a date: no back-dated changes.

## 4. Rules to remember
- No hard delete: records are retired (inactive) or reversed.
- Prices change only for future entries.
- Every number comes from the owner's settings; nothing is invented.
- Multi-business is planned: each business gets its own books and data (see `docs/GROUP_ERP_STAGE_A.md`).

## 5. Owner setup checklist
1. Enter items and prices.
2. Set locations and limits.
3. Give role grants.
4. Switch on rules one by one (see `docs/guide/AUDIT_SWITCHES.md`).
5. Run the UAT checklist (`docs/guide/UAT_CHECKLIST.md`).
