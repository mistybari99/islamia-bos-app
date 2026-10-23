# START HERE: which document is for what (newest first)

Last updated 23 Oct 2026. The repository is `islamia-bos-app`, branch `Main-Img` (see `docs/SINGLE_REPO.md`). Rules for everyone: `CLAUDE.md` (repository root) and `docs/BUILD-RULES.md`.

## Read first (23 Oct 2026)
- `docs/SINGLE_REPO.md`: one repository, what is published and what is not, branch rules, rollback, the checklist of GitHub settings only the owner can change.
- `docs/NEW_PROJECT_SETUP.md`: how to build the new clean Supabase project step by step, with checks after each SQL part, what to re-apply, how to switch the staff over.
- `docs/NO_LOSS_REPORT_23OCT.md`: proof that nothing was lost when the branches were joined (diff, functions, rules, web build).
- `docs/DECISIONS.md` (last section, "Update 23 Oct 2026"): the owner decisions of this session.
- `docs/OPEN_OWNER_QUESTIONS_FROM_DAILY_GUIDE.md`: questions still open for the owner.

## Using the system (owner and staff)
- `docs/guide/OWNER_GUIDE.md`: owner guide (Bangla), then `docs/guide/PHONE_ONLY_STEPS.md`, `docs/guide/RECOMMENDED_SETTINGS.md`, `docs/guide/ROLLOUT_PLAN.md` (switch on one thing at a time), `docs/guide/UAT_CHECKLIST.md` (acceptance test).
- `docs/OPERATIONAL_MANUAL_BN.md`, `docs/BUSINESS_PROCESS_GUIDE.md`, `docs/SWEET_SHOP_GUIDE.md`: daily operation and business process.
- `docs/GROUP_ERP_STAGE_A.md`, `docs/WORK_TRACKER.md`: group ERP stage A and the work tracker.

## Database
- `docs/PASTE_ORDER.md`: the one canonical SQL order (`tests/sql/paste_order.env` is the source). Ready-made parts: `docs/paste_parts/`.
- `docs/LIVE_DELTA.md`: only for bringing the OLD live project up to date; not used for the new project.
- `docs/RESTORE_DRILL.md`, `docs/OPS_SETUP.md`: backup, restore and secrets.
- `docs/BUILD-LOG.md`: what changed in every task and what could not be confirmed (newest entries at the end).

## History (kept, partly superseded; each has a dated note at the top)
- `docs/RECOVERY_AUDIT.md`, `docs/RECOVERY_ROADMAP.md`, `docs/MERGE_CHECKLIST.md`, `docs/DEMAND_VERIFY.md`, `docs/PLAN_NEXT.md`, `docs/SECURITY_BACKLOG.md`, `docs/DESIGN_ROADMAP.md`, `docs/FORM_SEQUENCE.md` (rule still valid).
- Everything else in `docs/` is indexed by folder in `docs/README.md`.
