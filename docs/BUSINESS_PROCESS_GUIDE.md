# Business Process Guide: Real Business to Software

Each topic: what it is in real business, the process, and how the software supports it. Short by design.

## 1. Purchasing (Procure to Pay)
- **Real business:** Buy only what is needed, from the best quote, with approval above a limit.
- **Process:** Requisition → quotation comparison → purchase order → goods received → bill check → payment.
- **In software:** Purchasing screens (06-1 to 06-5) with 3-way match and supplier ledger; limit above which the owner approves.

## 2. Inventory and Stock Control
- **Real business:** Know exactly how much stock is on hand, where it is, and what it is worth.
- **Process:** Receive → store → issue or sell → count → adjust with a reason.
- **In software:** Stock ledger records every movement; blind stock count shows variance; negative stock is blocked by setting.

## 3. Production and Costing
- **Real business:** Produce to a recipe, track yield and waste, and know the true cost per item.
- **Process:** Recipe card → daily production sheet → yield check → finished goods to stock → cost per batch.
- **In software:** Recipe/BOM and production runs consume ingredients and create finished items; costing uses real ledger cost, not estimates.

## 4. Transfers Between Locations
- **Real business:** Move goods from factory or godown to showrooms with a paper trail.
- **Process:** Dispatch challan → transit → receiver checks quantity → accept or report short/damaged.
- **In software:** Transfer register with receiver confirmation; short goods are written off or flagged, never silently lost.

## 5. Sales (Point of Sale)
- **Real business:** Sell quickly, take the right payment, and keep discounts under control.
- **Process:** Scan or pick item → quantity → discount (within limit) → payment (cash, mobile, card, partial) → receipt.
- **In software:** POS with quick keys, offline queue, discount limit and approval, receipt numbering per location.

## 6. Cash and Bank Control
- **Real business:** Cash in the drawer must match the sales record; surplus and shortage are explained.
- **Process:** Blind count → compare with system → day close → handover to hub → bank deposit.
- **In software:** Blind count first; difference above tolerance blocks day close until owner releases.

## 7. Receivables (Customer Dues)
- **Real business:** Give credit only within a limit and collect on time.
- **Process:** Credit sale → customer ledger → aging → collection → reminder for overdue.
- **In software:** Customer ledger with credit limit, dues list with age, partial collection by cash or mobile.

## 8. Payables (Supplier Dues)
- **Real business:** Pay suppliers on time, with the right bill and no duplicate payment.
- **Process:** Bill received → matched to order and goods → approved → paid → supplier ledger updated.
- **In software:** Supplier ledger and payment history; duplicate bill numbers are flagged.

## 9. Accounting and Financial Statements
- **Real business:** Books must reconcile; P&L and balance sheet must match the real money and stock.
- **Process:** Sales, purchases, expenses and cash post to the books → trial balance → P&L → balance sheet.
- **In software:** Double-entry journal posted from business events; reports reconcile to ledger; accounting switch is turned on after review.

## 10. Staff, Attendance and Payroll
- **Real business:** Pay correctly for hours worked, with advances and deductions recorded.
- **Process:** Attendance → overtime → advances → salary sheet → payment → record.
- **In software:** Attendance, salary sheet, advances; salary visible only to owner or the right grant.

## 11. Internal Control and Audit
- **Real business:** No one approves their own work; every change leaves a trail.
- **Process:** Maker enters → checker approves → exception raised if variance → owner decides → audit log.
- **In software:** Self-approval blocked by default; release requests; correction log; audit log for every change.

## 12. Reporting and Owner Decisions
- **Real business:** Owner sees problems first and decides from real numbers.
- **Process:** Daily numbers → exceptions → weekly review → monthly P&L and KPIs → decision.
- **In software:** Owner dashboard shows problems first, then sales, margin and cash per location.

## 13. Multi-Business (Group) Management
- **Real business:** Each business has its own licence, books and staff; the owner sees the whole group.
- **Process:** Create business → add places → assign staff with scope → keep books separate → group view.
- **In software:** Organization tree, business profiles, strict data scope per business, owner-only group view (planned rollout, switches off by default).

## 14. Change Management (Rollout)
- **Real business:** Change one thing at a time, measure, then keep or roll back.
- **Process:** Plan → switch on one rule → watch one day → confirm → next rule.
- **In software:** Every new rule defaults to OFF; switch order documented in the audit switches guide.
