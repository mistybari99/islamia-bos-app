# FORM_SEQUENCE: how printed form codes are ordered (rule file for Claude and contributors)

> **Superseded (23 Oct 2026).** The status line below is out of date. The owner approved Option B (sorted by English short name, `NN-1`) on 21 Oct 2026, final; `tools/numbering_map.json` has `form_groups_approved: true` and phase 543 applied the codes. The printed codes are the new ones. The rule in section 1 stands.

Status: the owner chose **Option B** (sorted by short name). The mapping below is the proposal the owner must approve line by line before anything is applied. Until then the printed codes in the app and the database are the OLD codes, and `tools/numbering_map.json` keeps `form_groups_approved: false`.

## 1. The rule

1. A printed form code is `NN-1`, where `NN` is the form's position (01 to 41) when the forms are sorted A-Z by their **English short name** (case-insensitive, plain string order).
2. The form `0-1` (Location Settings) is a fixed exception. The app checks the literal `'0-1'` in several places (`web/nav.js`, `web/app.js`, `web/entry.js`), so it keeps its code.
3. The short name is the only name the sort uses. The Bangla short name is shown next to it and never decides the order.
4. Position numbers are never reused. A form that is retired keeps its code and is marked closed (BUILD-RULES rule 2).
5. Codes change only after the owner approves the mapping table in section 4 in writing, and only through a numbered phase (see section 5).

## 2. How to add a form

1. Choose the English short name and the Bangla short name (from the form kit title; do not invent business data).
2. Insert it into the sorted list. Every form after it moves one position. This is why a new form is not added to the middle of a live sequence: first agree the new mapping with the owner, then apply it in one step.
3. Until the owner approves a new mapping, a new form uses a temporary code outside the sequence and is listed in section 6 as pending. Do not take a code that is already retired.
4. Update the mapping table, `tests/web/form_names_test.js` (the test checks the order and the bijection), and the form kit entry.

## 3. Old codes are retired

- After apply, the old code of every moved form is **retired**. It must not be reused for another form. Old codes stay in history (docs, phase files, the BUILD-LOG) unchanged.
- Old-code references in live code are changed in the same apply step; old-code references in history are left as they are, with the note "old code, see docs/FORM_SEQUENCE.md".
- Some new codes are the same string as an old code of a different form (see section 4, column "collision"). Reading an old document with a new mind is therefore unsafe; always check the form name next to the code.

## 4. Mapping table (proposal, sorted by English short name)

| Sort no. | Short name (EN) | Short name (BN) | Old code | New code |
|---|---|---|---|---|
| 1 | Appointment Letter | নিয়োগপত্র | 02-4 | 01-1 |
| 2 | Bill Check and Payment | বিল যাচাই ও পেমেন্ট | 06-4 | 02-1 |
| 3 | Cash Handover | ক্যাশ হ্যান্ডওভার | 10-1 | 03-1 |
| 4 | Cash Position and Budget | ক্যাশ পজিশন ও বাজেট | 10-4 | 04-1 |
| 5 | Customer Order | কাস্টমার অর্ডার | 20-1 | 05-1 |
| 6 | Daily Showroom Sheet | দৈনিক শোরুম শিট | 14-1 | 06-1 |
| 7 | Digital Payment Reconciliation | ডিজিটাল পেমেন্ট রিকনসিলিয়েশন | 10-3 | 07-1 |
| 8 | Discount Approval | ডিসকাউন্ট অনুমোদন | 20-2 | 08-1 |
| 9 | Duty and Backup Card | ডিউটি ও ব্যাকআপ কার্ড | 02-7 | 09-1 |
| 10 | Exit Clearance | এক্সিট ক্লিয়ারেন্স | 02-6 | 10-1 |
| 11 | Expense Voucher | ব্যয় ভাউচার | 10-2 | 11-1 |
| 12 | Factory Daily | কারখানা দৈনিক | 05-1 | 12-1 |
| 13 | Goods Received (GRN) | মালামাল গ্রহণ (GRN) | 04-1 | 13-1 |
| 14 | Jalebi Counter Daily | জিলাপি কাউন্টার দৈনিক | 14-2 | 14-1 |
| 15 | Leave Application | ছুটির আবেদন | 02-5 | 15-1 |
| 16 | Maintenance Request | মেইনটেন্যান্স অনুরোধ | 08-1 | 16-1 |
| 17 | Marketing Expense | মার্কেটিং ব্যয় | 18-1 | 17-1 |
| 18 | Material Issue | মালামাল ইস্যু | 04-2 | 18-1 |
| 19 | Monthly Attendance | মাসিক হাজিরা | 02-1 | 19-1 |
| 20 | Monthly P&L and KPI | মাসিক P&L ও KPI | 01-2 | 20-1 |
| 21 | Monthly Salary | মাসিক বেতন | 02-2 | 21-1 |
| 22 | New Product Decision | নতুন প্রোডাক্ট সিদ্ধান্ত | 05-5 | 22-1 |
| 23 | Online and Delivery Ledger | অনলাইন ও ডেলিভারি লেজার | 20-6 | 23-1 |
| 24 | Party and Wholesale Invoice | পার্টি ও পাইকারি ইনভয়েস | 20-4 | 24-1 |
| 25 | Party and Wholesale Ledger | পার্টি ও পাইকারি লেজার | 20-5 | 25-1 |
| 26 | Product Spec Card | প্রোডাক্ট স্পেক কার্ড | 05-2 | 26-1 |
| 27 | Purchase Order | পারচেজ অর্ডার | 06-3 | 27-1 |
| 28 | Purchase Requisition | পারচেজ রিকুইজিশন | 06-1 | 28-1 |
| 29 | Quotation Comparison | কোটেশন তুলনা | 06-2 | 29-1 |
| 30 | Receivable and Advance | প্রাপ্য ও অ্যাডভান্স | 10-5 | 30-1 |
| 31 | Recipe Card | রেসিপি কার্ড | 05-3 | 31-1 |
| 32 | Return and Complaint | রিটার্ন ও অভিযোগ | 20-3 | 32-1 |
| 33 | Shift Handover | শিফট হ্যান্ডওভার | 11-1 | 33-1 |
| 34 | Skill Checklist | স্কিল চেকলিস্ট | 02-8 | 34-1 |
| 35 | Staff Advance | স্টাফ অ্যাডভান্স | 02-3 | 35-1 |
| 36 | Stock Count | স্টক কাউন্ট | 04-3 | 36-1 |
| 37 | Store Ledger | স্টোর লেজার | 04-4 | 37-1 |
| 38 | Supplier Ledger | সাপ্লায়ার লেজার | 06-5 | 38-1 |
| 39 | Transfer Challan | ট্রান্সফার চালান | 03-1 | 39-1 |
| 40 | Weekly Review | সাপ্তাহিক রিভিউ | 01-1 | 40-1 |
| 41 | Yield Test | ফলন টেস্ট | 05-4 | 41-1 |
| fixed | Location Settings | লোকেশন সেটিংস | 0-1 | 0-1 |

Every one of the 41 sorted forms changes its code. The suffix `-1` is the same for all forms under this rule; if the owner prefers a bare two-digit code, that is a separate decision (section 7 of the proposal).

## 5. Where the apply step must act (not done yet)

- Live database: `forms.code` is immutable (trigger `forms_code_immutable`) and referenced by foreign keys from `entries` and about twenty other tables that store `form_code`. The change needs a new numbered phase file, written for review and pasted by the owner. No agent writes to the live project.
- Repository: docs, SQL comments and tests that name a code (see the proposal, section 5), and the app code that matches on the literal codes.
- `tools/renumber.py` currently works on the old group-level map. It must be extended to this per-code table and given an "applied" guard before `--apply` is used; otherwise a second run would shift the codes again.

## 6. Pending

- The owner's follow-up on location grouping (Main Showroom, Branch, Production House, Warehouse) does not touch location codes. Do not change location codes under this rule.
- Retired or closed forms: none recorded.
