# NEW PROJECT SETUP: a clean Supabase project for the single repository

Written 23 Oct 2026. Status: **a plan, nothing has been run on any Supabase project.** An agent never writes to a live Supabase project (`CLAUDE.md`); the owner pastes every SQL part himself, after reading it. This plan was proven only on a throwaway local PostgreSQL 16 (section 2).

**বাংলা সারাংশ (সংক্ষেপে):**
- একটা নতুন, পরিষ্কার Supabase project বানাবেন। পুরনো project (`Islamiya-Bos`) আগে কিছুই বদলাবে না; নতুনটা ঠিক হলে তবেই স্টাফ সরবে।
- SQL বসাবেন `docs/paste_parts/part01.sql` থেকে `part21.sql` পর্যন্ত, ক্রমে, একটা একটা করে। প্রতিটির পরে নিচের শুধু-পড়ার CHECK চালিয়ে সংখ্যা মেলাবেন। error এলে থামুন, পরেরটা বসাবেন না।
- নতুন project-এ আইটেম (1369), লোকেশন (7), ও আপনার সেট-করা 56টি নিয়ম নিজে থেকে আসে না। 7টি লোকেশন ও 57টি পুরনো আইটেম SQL থেকেই বসে; বাকি 1312 আইটেম অ্যাপ থেকে "Item master import" দিয়ে আনবেন। 56টি নিয়ম (সুইচ) নিচের তালিকা দেখে নিজে চালু করবেন। সব সুইচ ডিফল্টে বন্ধ।
- লগইন (Auth users) ব্যাকআপে থাকে না। নতুন project-এ প্রথম রেজিস্টার করা ব্যক্তিই মালিক হবে; স্টাফদের আবার তৈরি/অনুমোদন করতে হবে।
- `web/config.js`-এ নতুন project-এর URL ও publishable key বসবে; GitHub Secrets নতুন করে দিতে হবে; তারপর ধাপে ধাপে স্টাফ সরানো (সেকশন 8)।

## 1. Before you start: export what exists only in the old live project

The old project (`Islamiya-Bos`, ref `rpqrcmesbhwtyrikabhy`, Postgres 17, created 11 Oct 2026) held on 23 Oct 2026 (read-only extract, counts only, no business rows read): items 1369, locations 7, customers 1, sales 11, sale payments 14, entries 1, forms 46, org units 4, business profiles 1, audit log lines 3045, rules 623 (56 of them set by the owner), journal entries 0, stock ledger 0, stock transfers 0, employees 0. Because the live project is almost empty, nearly all of the value is in the **settings and the item list**, not in transactions.

What exists ONLY in the old project (not in the repository, not recreated by SQL):

| What | Where it lives | How to keep it |
|---|---|---|
| The 56 owner-set rules (section 6) | table `rules`, column `value` | This document lists them. Also take a backup (below). |
| Items 1369 (57 old seed items + 1312 dictionary items imported from the repository file `data/item_dictionary.csv`) and any edits the owner made after import | tables `items`, `item_costs`, ... | Backup + the repository files. |
| 7 locations | table `locations` | The same 7 are created by SQL (section 2). Names the owner edited are in the backup. |
| The 11 sales, 14 payments, 1 entry, 1 customer, audit log | many tables | Backup (they are test-sized; the owner decides whether they matter). |
| Logins (staff accounts, PINs) | Supabase Auth, not schema `public` | NOT in any backup. Staff must be created again (section 7). Passwords and PINs cannot be exported. |
| Photos | Supabase Storage bucket `photos` | `tools/backup_photos.py` copies them; they are not in the table dump. |
| Anything skipped by design by `_backup_tables()`: attendance devices, bot marks, login-attempt tables, notification tables | `public` | Re-created by use; devices must be enrolled again. |

Export steps, all read-only on the old project:

1. In the app (owner login) take a backup: **Home > Backup > download JSON**, keep it in the owner's Google Drive. (This file holds business data. No agent opens it.)
2. If the nightly backup workflow ran (only possible while the repository is private), the newest dump is on the `backups` branch of the repository: `latest/` has `manifest.json` and one `<table>.ndjson.gz` per table (`docs/OPS_SETUP.md`).
3. Save a copy of section 6 below (the rules to re-apply) and the old `web/config.js`.

## 2. What was proven locally, and what was not

Proven on a throwaway local PostgreSQL 16.15 (own cluster, no network, not Supabase), on the branch `Main-Img`:

- The canonical paste chain (`tests/sql/paste_order.env` = `docs/PASTE_ORDER.md` section B, 261 files, now ending with `phase548`) builds with **0 errors**: `bash tests/sql/final_build.sh <db>`. Result (re-measured 24 Oct 2026 on `Main-Img-v2`): 2896 public functions, 478 tables, 486 policies, 627 rules, row level security on for every table.
- Every file pasted **twice in a row** (522 pastes, re-measured 24 Oct 2026): **0 errors**, same result (same function count and identical function-text hashes).
- The 21 generated paste parts `docs/paste_parts/part01.sql ... part21.sql`, run one after another (the way the owner will paste them), give the same 2896 functions with **identical text hashes** to the chain build, and 0 errors. The "Expected" numbers in section 4 come from that run.
- `select count(*) from public._i2_state() where not present` = 0. `_union_audit()`: 145 `merged`, 11 `other` (the file `docs/LIVE_DELTA.md` quotes 156 `merged` for the older chain; `stock_transfer` is one of the 11 `other` rows because phase 546 now owns its text on purpose; the other ten were also not `merged` before this work and were not looked at again here).
- A fresh build starts with: 7 locations, 57 items, 46 forms, 627 rules (none set by an owner), 13 roles, 0 profiles, 0 customers.

NOT proven (UNVERIFIED): a paste into a real Supabase project (the SQL editor, Auth hooks, Storage policies, extensions, the 500 KB size of each part in a phone browser), any screen of the app against the new project, and the restore of a real backup (`docs/RESTORE_DRILL.md` says the same). The local run used small stand-ins for the Supabase `auth` and `storage` schemas and for the roles `anon`, `authenticated` and `service_role`; on Supabase these already exist.

## 3. Create the project (owner)

1. Supabase > New project. Name it, pick a region near Bangladesh, set a strong database password and keep it in a password manager. Do not share it.
2. Authentication > Sign In / Providers > Email > **Confirm email OFF** > Save (`docs/SETUP.md`).
3. Open the SQL Editor. Do not paste anything yet.
4. Write down the Project URL and the **publishable** key (Project Settings > API). Never copy the `service_role` or secret key into any file or chat.

## 4. Paste the SQL parts, one at a time, with a check after each

Files: `docs/paste_parts/part01.sql` to `part21.sql` (each at most 500 KB; they are built by `tools/build_paste_parts.py` from `tests/sql/paste_order.env`; the same parts, ready to copy, are in `docs/paste_parts/setup-all.html`). If the phase list ever changes, regenerate with `python3 tools/build_paste_parts.py` and check with `python3 tools/build_paste_parts.py --check` (it passes today: "paste parts are up to date").

Rules for the owner: paste in order, one part per query, press Run, wait for "Success". If any part shows an error, STOP and send the message to the lead; do not paste the next part. A part may be pasted twice safely. Never paste `*_test.sql`, `phase84_test_project_only.sql`, or any file not in the parts. Never paste the old live-delta files (`delta01.sql`, `delta02.sql`) into the new project: those exist only to bring the OLD project up to date.

Read-only CHECK to run after every part (it only reads):

```sql
select
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace) as functions,
  (select count(*) from pg_tables where schemaname = 'public') as tables,
  (select count(*) from pg_policies where schemaname = 'public') as policies,
  (select count(*) from pg_tables where schemaname = 'public' and not rowsecurity) as rls_off,
  (select count(*) from public.rules) as rules;
```

Expected numbers measured on the local build (a real Supabase project may show a few extra functions from its own extensions; `tables`, `policies`, `rls_off` and `rules` must match exactly, and `rls_off` must always be 0):

| Part | Phases | Size | functions | tables | policies | rules |
|---|---|---|---|---|---|---|
| part01.sql | schema to phase11 | 459 KB | 173 | 49 | 67 | 51 |
| part02.sql | phase12 to phase20 | 470 KB | 367 | 82 | 100 | 90 |
| part03.sql | phase21 to phase41 | 496 KB | 546 | 109 | 127 | 108 |
| part04.sql | phase42 to phase49 | 456 KB | 742 | 149 | 167 | 168 |
| part05.sql | phase50 to phase72 | 456 KB | 892 | 178 | 195 | 193 |
| part06.sql | phase73 to phase506 | 443 KB | 1016 | 207 | 221 | 218 |
| part07.sql | phase507 to phase517 | 474 KB | 1135 | 227 | 237 | 247 |
| part08.sql | phase515 to phase522 | 358 KB | 1175 | 233 | 238 | 259 |
| part09.sql | phase523 to phase104 | 497 KB | 1265 | 249 | 246 | 279 |
| part10.sql | phase105 to phase116 | 470 KB | 1303 | 255 | 247 | 311 |
| part11.sql | phase117 to phase527 | 493 KB | 1453 | 283 | 291 | 322 |
| part12.sql | phase528 to phase86 | 457 KB | 1622 | 307 | 351 | 339 |
| part13.sql | phase87 to phase97 | 497 KB | 1883 | 330 | 370 | 395 |
| part14.sql | phase98 to phase308 | 490 KB | 2119 | 358 | 383 | 450 |
| part15.sql | phase316 to phase408 | 491 KB | 2324 | 383 | 398 | 499 |
| part16.sql | phase409 to phase441 | 478 KB | 2475 | 395 | 406 | 514 |
| part17.sql | phase442 to phase470 | 457 KB | 2645 | 409 | 423 | 528 |
| part18.sql | phase471 to phase490 | 495 KB | 2822 | 459 | 471 | 594 |
| part19.sql | phase491 to phase534 | 398 KB | 2890 | 476 | 486 | 623 |
| part20.sql | phase535 to phase546 | 493 KB | 2894 | 478 | 486 | 625 |
| part21.sql | phase547 to phase548 (backup coverage; stock_recon_period lists transit_loss) | 15 KB | 2896 | 478 | 486 | 627 |

Final checks after part21 (both read-only; all counts in this table were measured part by part on 24 Oct 2026):

```sql
select * from public._i2_state() where not present;          -- must return no rows
select state, count(*) from public._union_audit() group by state;  -- expected: merged 145, other 11
select count(*) from pg_tables where schemaname = 'public' and not rowsecurity;  -- must be 0
select count(*) from public.locations;   -- 7
select count(*) from public.items;       -- 57 (the seed items)
select count(*) from public.forms;       -- 46
select count(*) from public.rules where value is not null;  -- 0 (no owner setting yet)
```

Then list the switches that are ON by factory default: `select key from public.rules where kind = 'switch' and (coalesce(value, default_value)) = 'true'::jsonb order by 1;`. On the local build this returns 68 switches that phases defined as ON (for example `notify_on`, `payroll_on`, `smart_defaults_on`, `offline_cache_on`). Read the (i) text of any of them before changing it.

## 5. Seed items, locations and rules from the owner's own backup

What is seeded by SQL itself: 7 locations (main showroom and sweet factory, 2nd branch, cake factory, godown, AL-CAKIZ, MISTY BARI, Mujgunni sweet factory), 57 old seed items, 46 forms, roles, the chart of accounts, option lists and the 627 rules with safe defaults.

What you bring from your own files:

1. **The other 1312 items** come from the repository file `data/item_dictionary.csv` (also `web/data/item_dictionary.json`). In the app (owner login): Products > menu > **Item master import** > load the file > **Preview** (writes nothing) > **Apply** (200 rows per request, resumes if the network drops). Details and a rehearsal result are in `docs/DRYRUN_item_master.md`. Expected result: 1369 items in total.
2. **Costs and prices** are not in the dictionary. Enter them from the paper records (never guess; `docs/BUILD-RULES.md` rule 15). `data/items_seed.csv` holds the 57 old seed prices.
3. **Locations**: check the 7 created by SQL against the old project's list; rename in the app, do not delete (rule 3).
4. **Everything else** (customers, sales, etc., if the owner wants them): restore from the owner's backup with the existing tools:
   - `tools/restore_backup.py <backup_folder> --out restore.sql [--dry-run] [--tables a,b] [--split-mb 4]` turns a backup folder (made by `tools/backup_dump.py`) into SQL files that the owner pastes. It verifies every file against `manifest.json` first, `--dry-run` writes nothing, default mode only adds missing rows, `--truncate` empties the restored tables first (destructive; only for a new empty copy). It needs no database access. It restores table data only: **not** logins, **not** photos, **not** the tables the dump skips by design.
   - `tools/restore_drill.py <backup_folder> --dsn "postgresql://postgres@/bos_scratch?host=/tmp&port=5544"` proves a backup can be restored: it refuses any database that is not local and not named with `scratch`, then checks file hashes, table list, key functions, row level security, row counts, journal balance and stock ledger against stock balance. Use it on a **scratch local database only** (steps in `docs/RESTORE_DRILL.md`). It was NOT run on any real data for this plan.
   - Logins are not in the backup. `profiles.id` points to `auth.users.id`, so restoring profile rows into a new project needs the same user ids created first; the simpler path is to create the staff again (section 7).
5. Photos: `tools/backup_photos.py` copies them to the backup; uploading them to the new project's Storage is a separate owner step. UNVERIFIED: there is no ready tool in the repository that uploads them back.

## 6. Settings to re-apply (the 56 owner-set rules of the old project)

Read from the owner's live rules extract of 23 Oct 2026 (phone numbers redacted; enter the two numbers yourself). All 56 keys exist in the fresh build, so each can be set in the app: **Switchboard** (`#/switchboard`) or by `select public.set_rule('<key>', '<json value>'::jsonb);` in the SQL editor, owner session only. Apply them **gradually**, not all at once: follow `docs/guide/ROLLOUT_PLAN.md` (one switch at a time, check, then the next) and `docs/guide/RECOMMENDED_SETTINGS.md`. A sensible order: first the display and input switches, then stock and orders, last the accounting group.

| Group | Key = value to set (factory default in brackets) |
|---|---|
| Accounting (the books) | `accounting_on` = true (false), `accounting_start_date` = "2026-10-14" (not set; **decide the start date again for the new project: the books start on the day you start posting**), `acct_count_adjust` = true, `acct_issue_out` = true, `acct_transit_loss` = true, `acct_purchase_variance` = true, `acct_manual_prod_in103` = true, `manual_journal_guard` = "on" ("off"), `journal_loc_check` = true, `mapping_type_guard` = true, `journal_stale_warn_hours` = 2 |
| Cash | `cash_short_post_on` = true, `cash_short_treatment` = "staff_receivable" ("expense"), `other_income_on` = true, `bank_slip_required` = true |
| Orders and online | `online_orders_on` = true, `online_keep_order_price` = true, `online_pack_warn_on` = true, `order_promise_required` = true, `order_refund_record_on` = true, `web_form_on` = true, `web_form_captcha_on` = true, `website_custom_cake_on` = true, `website_pay_manual_on` = true, `website_pay_mobile_number` = (owner's number, redacted here), `website_whatsapp` = (owner's number, redacted here), `meta_intake_on` = true, `cake_flow_on` = true, `cake_photo_required` = true |
| Delivery and X-packages | `xb_delivery_on` = true, `xc_coaching_on` = true, `xc_price_alert_on` = true, `xc_prod_suggest_on` = true, `xc_prod_weeks` = 2, `xc_summary_on` = true, `xc_sync_alert_on` = true, `xc_sync_stale_hours` = 1 |
| Inbox and requests | `inbox_on` = true, `inbox_silence_hours` = 12 (24), `pay_requests_on` = true, `pay_request_exception_mode` = "never" ("reason"), `pay_requests_required_kinds` = "salary" ("both"), `party_request_approver_mode` = "owner" ("same"), `announce_on` = true, `todo_on` = true, `shift_on` = true, `crm_hooks_on` = true, `em_settings_invoice` = true |
| POS and screens | `pos_offline_hours` = 2 (72), `pos_customer_on_discount` = true, `pos_show_invoice_after_sale` = "always" ("never"), `item_images_mode` = "pos_only" ("off"), `barcode_camera_on` = true, `barcode_device_on` = true, `list_search_min` = 8 (8, same as default), `ui_noperm_mode` = "lock" ("lock", same as default) |

That is 56 keys (two of them equal their factory default). In words, the switches that were ON in the old project: accounting_on from 2026-10-14, acct_count_adjust, acct_issue_out, acct_transit_loss, acct_purchase_variance, manual_journal_guard = on, journal_loc_check, mapping_type_guard, online_orders_on, web_form_on, inbox_on, pay_requests_on, order_promise_required, cash_short_post_on, the xc_* switches and xb_delivery_on, with pos_offline_hours = 2, item_images_mode = pos_only and party_request_approver_mode = owner.

Four rules exist in the fresh build but not in the old project: `price_check_include_freight`, `transfer_client_reuse_block`, `backup_accounts_on` and `backup_buckets_on` (the last two come from phase 547 and are OFF; see `docs/BACKUP_AND_RESTORE_GUIDE.md`) (from phases after the old project's last paste). Both are OFF in the fresh build (checked); read their (i) text before changing them. Phase 546 (the stock-transfer fix that puts back the stock check and receiver notice) adds no switch that is ON.

Do not switch `accounting_on` on before the opening balances, the chart of accounts and the item costs of the new project are entered and the readiness check in `#/setupadvisor` shows no red row.

## 7. App and GitHub configuration for the new project

1. **`web/config.js`**: change only `url` (the new Project URL) and `key` (the new **publishable** key, starts with `sb_publishable_`). Keep `emailDomain` as it is unless the owner decides otherwise (a changed domain breaks every staff login e-mail). Commit that change on `Main-Img`; `tools/check_pages_dist.py` refuses a build whose key is not a publishable key. Never put a `service_role` or secret key in this file.
2. **GitHub secrets** for the new project (Settings > Secrets and variables > Actions; full list and steps in `docs/OPS_SETUP.md` and `docs/SINGLE_REPO.md`): `SUPABASE_URL`, `SUPABASE_ANON_KEY` (publishable key), `BOT_EMAIL`, `BOT_PASSWORD` (a least-privilege backup bot made in Authentication > Users with Auto Confirm User), `BACKUP_PASSPHRASE`, `BACKUP_KDF_SALT`; optional `NOTIFY_BOT_EMAIL`, `NOTIFY_BOT_PASSWORD`, `GMAIL_APP_PASSWORD`, SMS and Google Drive secrets. Old secrets that point to the old project must be removed or replaced the same day.
3. **First login**: open the app (a private browser window) and register first. The first account becomes the active owner automatically (`docs/SETUP.md`). Do this yourself before any staff member opens the link.
4. **Staff**: register each person, approve them in Staff and approval, set roles and locations, have each choose a PIN. Staff IDs must keep the same form as before.

## 8. Order to switch the staff over without losing data

1. Old project stays untouched and in use. Export everything in section 1 and note the date and time.
2. Create the new project and paste parts 01 to 21 with the checks (sections 3 and 4). Stop at the first error.
3. Register the owner in the new project; import the 1312 items; enter or restore the data the owner wants (section 5).
4. Apply the settings from section 6 in the order of `docs/guide/ROLLOUT_PLAN.md`; keep `accounting_on` for last.
5. Run the user acceptance list `docs/guide/UAT_CHECKLIST.md` on the new project with the owner login only. Optionally rehearse a restore with `tools/restore_drill.py` on a scratch local database (steps in `docs/RESTORE_DRILL.md`).
6. Point `web/config.js` at the new project on a branch and check the built site on a phone (the Pages workflow builds it only when merged into `Main-Img`; before that, test a build locally with `bash tools/build_web.sh`).
7. Choose a quiet time. In the old app, finish the day: close shifts, post or record every sale, take the final backup again (new data since step 1), and tell staff to stop entering.
8. Move any records made since step 1 into the new project (restore the new backup, or re-enter the few sales by hand), then merge the `config.js` change into `Main-Img`. The Pages workflow publishes it.
9. Staff open the app (close and reopen once), log in with their new PIN, and do one test sale each. Keep the old project read-only and paused (not deleted) for at least the first month; deleting anything needs the owner's explicit yes.
10. Switch the GitHub secrets to the new project, run the backup workflow once (needs a private repository) and check it is green.

## 9. If something goes wrong

- A part shows an error: stop. Do not paste the next part. Copy the error text; nothing was written by the failing statement's transaction only if the part is one transaction (UNVERIFIED for each part); re-pasting the same part is safe.
- Counts do not match section 4: stop and compare; do not switch anything on.
- After going live: roll the website back (`docs/SINGLE_REPO.md` section 5) or point `config.js` back at the old project (which was left intact).
