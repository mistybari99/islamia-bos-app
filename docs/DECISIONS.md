# BOS Tool: Owner Decisions (log)

Source: owner answers in chat, 11 Oct 2026. Scope: all 42 forms of BOS Build Kit v1.39, mobile-first, zero cost.

## Platform
- Supabase (free plan, Singapore region) + GitHub Pages. No paid plan, no domain, no SMS.
- Backup: owner button "download all data" (saved to Google Drive by the owner). No auto-backup on the free plan.
- Photos: expense voucher, goods receipt (GRN), maintenance request.

## Login and roles
- Staff ID + PIN (no SMS OTP, it is not free). Staff stays logged in on their phone.
- Roles are business-common (owner, management, cash controller, showroom manager, salesperson, storekeeper, factory in-charge, purchasing, party coordinator, carrier, HR).
- Owner has a role x form matrix to switch view / enter / approve on or off, per role. Multiple roles per person allowed.

## Entry rules
- Any change to a draft needs a note first; the maker writes the note, makes the change, then submits. Every change goes to a separate Correction Log (who, when, what, why, note), visible to the owner in one place.
- Self-approval (maker = checker) is blocked by default. Owner can switch it per role in the matrix; every switch is logged.

## Control rules
- Count-first: handovers (cash, goods) require the counted figure before the system figure is shown. Mandatory by default; owner can configure per form.
- Red control: day-close is blocked. Staff applies for release with a note/reason. Owner accepts (day can proceed) or rejects (stays blocked). All requests and decisions are logged. Owner can configure block vs warn per control.
- Variance auto-creates an item in the owner's exceptions list (who, where, how much). Auto-creation has an on/off switch. A legal / illegal reason can be recorded as a note.
- Dashboard: problems first, plus a short summary of numbers (sales, expenses, profit, per location).

## Data and language
- Item list seeded from data/items_seed.csv (57 items), editable at any time. Price change affects only future entries.
- Languages, per-user switch, three modes: (1) Bangla, (2) Banglish = Bangla text with simple everyday English words mixed in (NOT Bangla transliterated into Latin letters), (3) full English. All form labels exist in all three.
- Form notes shown as info buttons, coloured warning boxes and step-by-step questions.
- No invented numbers, limits or recipes: everything from settings; empty means "data needed".

## Build order
- Phase by phase, owner reviews each phase. Phase 1: login, roles, settings, items, audit log. Then core forms, dashboard, rest of the 42 forms.

## Update 12 Oct 2026
- Hosting: web/ goes to a separate PUBLIC repo (free GitHub Pages). This private repo keeps schema, data, docs. Costs/prices never go in the public repo.
- Cost price is a separate permission (ITEM_COST view / enter). Owner switches it per role in the matrix. Hidden roles cannot read it even through the API.
- Item and price changes by anyone except the owner are requests: they wait for the owner or a role with ITEMS "approve". The requester cannot approve own request unless the owner allows it for that role. Owner's own changes apply at once. All changes are logged.

## Update 23 Oct 2026
- One repository only: `islamia-bos-app` (GitHub Pages site). Everything from `My-tools` is brought into it, with full history, on a branch named exactly `Main-Img`, which becomes the repository's default branch. Plan and checklist: `docs/SINGLE_REPO.md`.
- The database will be a NEW, clean Supabase project. The old live project (`Islamiya-Bos`) is almost empty and stays untouched until the owner says otherwise. Plan: `docs/NEW_PROJECT_SETUP.md`.
- Nothing is uploaded, pushed, deleted, renamed or switched on GitHub or Supabase without the owner's explicit yes. Until then everything is prepared locally only.
- Repository visibility (public or private) is STILL OPEN. The 12 Oct decision (costs and prices never in a public repo) and the backup guard (backups refuse to run in a public repo) both bear on it. It is documented, not decided.
- Unchanged: new SQL only in new phase files, every new behaviour OFF by default, no demo or fictional material in the repository.
