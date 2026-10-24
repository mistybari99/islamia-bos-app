# BACKUP_COVERAGE - what is backed up, what is not, and why

Audit date 23 Oct 2026. Branch `feat/backup-coverage` (from `Main-Img` 8ff9d92). Read with `docs/BACKUP_AND_RESTORE_GUIDE.md` (the owner's steps) and `docs/OPS_SETUP.md` (setup of the bot and the secrets).
The older audit of phases 72..103 is `docs/backend/BACKUP_COVERAGE.md`; this file replaces it as the current picture.

How this was made: the whole schema was built on a throwaway local PostgreSQL 16 (`tests/sql/final_build.sh`, every phase through 547). The table matrix below is **computed** from that database by
`tools/backup_coverage_matrix.py` (it can be re-run and checked with `--check docs/BACKUP_COVERAGE.md`), so it cannot drift from the schema. Nothing here was read from the live Supabase project.

## 1. The existing backup path (what was audited)

| Piece | What it does | Finding |
|---|---|---|
| `.github/workflows/backup.yml` | 02:30 Dhaka every night + manual run. First step refuses to run unless the repository is private (fails closed). Dumps through the "ops bot" (anon key + the bot's login, never `service_role`), copies photos, commits to the `backups` branch (`latest/` + `YYYY/MM/DD/`), optionally copies to Google Drive. Only this workflow pushes (`tools/check_backup_guard.py`). | Good. Guard first, only backup pushes: unchanged. |
| `tools/backup_dump.py` + SQL `backup_manifest / backup_dump / _backup_tables` (phase 46, 70, 106) | Every table of schema `public` except a fixed exclusion list, page by page, deterministic gzip, row count and sha256 per file, count checked at start and end of the run. Optional encryption (rule `backup_encrypt_on`, passphrase secret `BACKUP_PASSPHRASE`, `tools/backup_crypto.py`). | Good, but the name filter hid two settings tables (G1) and no row-content checksum existed (G6). |
| `tools/backup_photos.py` | Copies bucket `photos` only. | Other buckets missing (G3); skipped files carried no checksum (G6). |
| `tools/restore_backup.py` | Verifies sha256 and row count of every file, then writes restore SQL (`--truncate` for a new copy). | Checks the files, not the restored database (G7). |
| `tools/restore_drill.py` | Restores into a local scratch database and checks counts, journal balance and stock. | Counts only, no content comparison (G7). |
| App button "Download all data (JSON)" (`web/app.js`, `BACKUP_TABLES`) | Owner's phone, fixed list of 77 table names. | Only **77 of 478** tables. A convenience copy, **not** a backup (G8). |
| Failure alert | `backup_log('failed')` + `backup_status()`: the app bell shows red and `notify.yml` sends an urgent mail when the last good backup is older than `backup_max_age_hours` (36) or the last run failed. A red workflow run also e-mails by GitHub's normal rules. | Exists. Reused, nothing new built. The seal / photo failures now turn the run red too. |

## 2. Gaps found, and what was done

| # | Gap | Fix (this branch) | Status |
|---|---|---|---|
| G1 | `ai_agents` and `ai_providers` (the AI settings) were silently missing from every dump: the column names `monthly_token_budget` / `max_output_tokens` matched the "token" secret filter. They hold no secret (`key_location` is only the word `supabase_secret`). | `supabase/phase547.sql` re-creates `_backup_tables()` with those two column names allowed. Same pattern as phase 70 and 106. | Done, tested |
| G2 | **Staff logins** (Supabase Auth) were not in any backup. The `profiles`, `user_roles`, `user_locations`, `user_grants` tables were, but `profiles.id` points to `auth.users.id`, and the login e-mail only exists in Auth. A new project could not re-create the accounts. | `backup_accounts_manifest()` (phase547, backup bot only, switch `backup_accounts_on`, OFF) writes `accounts.json`: id, staff id, e-mail, name, status, language, roles, locations, grants, 2FA yes/no, bot marks, attendance devices **without** token hash. Never a password, PIN hash, token or MFA secret. `tools/restore_accounts.py` re-creates the logins with the same ids. | Done, tested locally. Switch is OFF until the owner turns it on |
| G3 | Other Storage buckets (`web-refs`, `payproof`, `web-public`) were not copied; the bot could not read them. | Phase547 policy `ops_buckets_read` (switch `backup_buckets_on`, OFF) + `backup_storage_buckets()`; `backup_photos.py --all-buckets` copies them to `buckets/<bucket>/`. A bucket that holds files but is not readable is reported as a warning in `storage_buckets.json`, never silently skipped. | Done, tested with a fake Storage API only |
| G4 | Edge function secrets: nothing recorded. | The anon-key bot cannot read real secrets (and must not). `manifest.json` now lists the NAMES the edge functions read (`edge_function_secret_names_expected`, from the source code). Values are never stored. | Names only, by design |
| G5 | Per-device settings and the offline queue live in each phone's browser. | Cannot be backed up from the server. Documented (section 6). Attendance machines are in `accounts.json` (without token). | Documented |
| G6 | No versioned manifest with a checksum per file for everything, and no row-content checksum. | `manifest.json` format 2: `manifest_version`, `rows_sha256` per table (order independent), `extras` (accounts), `storage` block (per bucket, sha256 of its manifest; every photo has its own sha256), `code.commit`, `code.paste_order_sha256`, edge secret names. `tools/backup_seal.py` checks the photo files on disk. | Done, tested |
| G7 | Restore did not verify the restored database. | `restore_backup.py` ends its last SQL file with a row-count check that rolls the file back on a mismatch. `tools/verify_restore.py` compares counts **and** row checksums of every table with the backup and checks the logins. `tools/restore_storage.py` checks sha256 before upload and the object count after. | Done, tested |
| G8 | App button covers 77 of 478 tables. | Left as it is (it is the owner's quick personal copy and changing the screen is outside this task). The guide says plainly: do not rely on it. | Documented, not changed |
| G9 | Photos stay unencrypted in the private repo even when `backup_encrypt_on` is ON (only table files and `accounts.json` are encrypted). | Not changed: photos are added once and never rewritten, which suits git; encrypting them would break that. Written in the guide as a limit. | Documented |
| G10 | `ops_accounts` (which login is the backup bot) is excluded from the dump, so a restored project had no bot. | The bot marks are in `accounts.json`; `restore_accounts.py create --follow-up` writes the SQL to mark them again. The bot's password is set again by hand and goes into the GitHub secret. | Done |

## 3. Tables of schema `public`

Sensitivity is a **heuristic** from table and column names (`tools/backup_coverage_matrix.py`, function `classify`). `high` = staff pay and identity, `personal` = customers, suppliers, contacts,
`financial` = sales, stock, books, `settings`, `log / history`, `operational`, `secret` = left out because it holds a hash or secret. Read the `high` and `personal` rows once and tell the lead if a class is wrong.
A table in the backup is stored in the dump **as it is**: when the owner turns encryption ON the files are unreadable without `BACKUP_PASSPHRASE`; when it is OFF they are plain text in a private repository.

<!-- matrix:begin -->
Tables in schema public: **478**. In the nightly backup: **468**. Left out on purpose: **10**. Also in the app button "download all data": **77** (of 77 names in its fixed list).

| Table | Columns | Nightly backup | App button | Why left out | Sensitivity (heuristic) |
|---|---:|---|---|---|---|
| `_union_fn_backup` | 5 | yes | no |  | operational |
| `_union_fn_expected` | 2 | yes | no |  | operational |
| `acct_autopost_runs85` | 9 | yes | no |  | financial |
| `acct_mappings` | 6 | yes | no |  | financial |
| `acct_post_errors72` | 6 | yes | no |  | financial |
| `action_proposals` | 17 | yes | no |  | operational |
| `action_targets` | 7 | yes | no |  | operational |
| `agent_accounts` | 6 | yes | no |  | settings |
| `agreement_parties` | 7 | yes | no |  | operational |
| `ai_agent_grants` | 4 | yes | no |  | settings |
| `ai_agents` | 16 | yes | no |  | settings |
| `ai_calls` | 13 | yes | no |  | operational |
| `ai_eval_cases` | 6 | yes | no |  | operational |
| `ai_eval_runs` | 9 | yes | no |  | log / history |
| `ai_kb_entries` | 17 | yes | no |  | operational |
| `ai_providers` | 16 | yes | no |  | settings |
| `ai_redaction_rules` | 8 | yes | no |  | settings |
| `ai_suggestions` | 20 | yes | no |  | operational |
| `artisans` | 18 | yes | no |  | operational |
| `asset_costs` | 5 | yes | yes |  | financial |
| `assets` | 21 | yes | yes |  | financial |
| `assistant_notes` | 12 | yes | no |  | operational |
| `assistant_usage` | 10 | yes | no |  | operational |
| `att_evidence_reg` | 11 | yes | no |  | operational |
| `att_mark_log54` | 18 | yes | no |  | log / history |
| `att_self_lock` | 6 | yes | no |  | operational |
| `att_site_geo` | 5 | yes | no |  | operational |
| `attendance_days` | 27 | yes | no |  | high (staff pay / identity) |
| `attendance_devices` | 13 | **NO** | no | has secret-looking column(s): token_hash (the safe columns are in the staff manifest) | secret |
| `attendance_import_batches` | 18 | yes | no |  | high (staff pay / identity) |
| `attendance_punches` | 19 | yes | no |  | high (staff pay / identity) |
| `audit_log` | 11 | yes | yes |  | log / history |
| `backup_runs` | 10 | **NO** | no | run-time table of the backup / notification module, re-created by the app | log / history |
| `bank_recon_matches` | 12 | yes | no |  | high (staff pay / identity) |
| `bank_recon_trail` | 9 | yes | no |  | high (staff pay / identity) |
| `bank_statement_lines` | 11 | yes | no |  | high (staff pay / identity) |
| `benefit_types` | 10 | yes | no |  | high (staff pay / identity) |
| `bi_export_log` | 13 | yes | no |  | log / history |
| `bill_pay_defaults99` | 8 | yes | no |  | financial |
| `bill_payments99` | 18 | yes | no |  | financial |
| `blind_count_cfg` | 5 | yes | yes |  | settings |
| `bos_salt105` | 2 | yes | no |  | operational |
| `budget_log` | 9 | yes | no |  | financial |
| `budgets` | 7 | yes | no |  | financial |
| `business_place_ops135` | 13 | yes | no |  | operational |
| `business_profile_ops134` | 4 | yes | no |  | operational |
| `business_profiles` | 17 | yes | no |  | personal (customers, suppliers, people) |
| `business_templates` | 7 | yes | no |  | settings |
| `c_month_close_log` | 8 | yes | no |  | log / history |
| `cake_job_events` | 8 | yes | no |  | log / history |
| `cake_jobs` | 27 | yes | no |  | operational |
| `cake_price_rules` | 10 | yes | no |  | financial |
| `capacity_ratings` | 14 | yes | no |  | operational |
| `card_settlements85` | 15 | yes | no |  | operational |
| `cash_moves` | 18 | yes | no |  | financial |
| `client_error_hits107` | 3 | yes | no |  | log / history |
| `client_error_seen107` | 3 | yes | no |  | log / history |
| `client_errors` | 19 | yes | no |  | log / history |
| `coa_accounts` | 13 | yes | no |  | financial |
| `coa_report_class` | 6 | yes | no |  | financial |
| `cod_cases` | 12 | yes | no |  | operational |
| `cod_deposits` | 10 | yes | no |  | operational |
| `comparison_days` | 14 | yes | no |  | operational |
| `comparison_pairs` | 9 | yes | no |  | operational |
| `corrections` | 9 | yes | yes |  | log / history |
| `cost_attrib_main` | 11 | yes | no |  | financial |
| `cost_bill_inputs` | 4 | yes | no |  | financial |
| `cost_bill_shares` | 12 | yes | no |  | financial |
| `cost_charge_types` | 15 | yes | no |  | financial |
| `cost_component_types` | 12 | yes | no |  | financial |
| `cost_share_reassign` | 16 | yes | no |  | financial |
| `cost_source_bills` | 21 | yes | no |  | financial |
| `cost_source_locs` | 2 | yes | no |  | financial |
| `cost_source_rule_shares` | 5 | yes | no |  | financial |
| `cost_source_rules` | 12 | yes | no |  | financial |
| `cost_source_types` | 8 | yes | no |  | financial |
| `cost_sources` | 15 | yes | no |  | financial |
| `crm_complaint_events` | 9 | yes | no |  | personal (customers, suppliers, people) |
| `crm_complaint_returns` | 5 | yes | no |  | personal (customers, suppliers, people) |
| `crm_complaints` | 32 | yes | no |  | personal (customers, suppliers, people) |
| `crm_consent_events` | 14 | yes | no |  | personal (customers, suppliers, people) |
| `crm_contact_prefs` | 5 | yes | no |  | personal (customers, suppliers, people) |
| `crm_customer_links` | 12 | yes | no |  | personal (customers, suppliers, people) |
| `crm_dup_reviews` | 10 | yes | no |  | personal (customers, suppliers, people) |
| `crm_export_log` | 11 | yes | no |  | personal (customers, suppliers, people) |
| `crm_feedback` | 17 | yes | no |  | personal (customers, suppliers, people) |
| `crm_lead_events` | 10 | yes | no |  | personal (customers, suppliers, people) |
| `crm_lead_lists` | 7 | yes | no |  | personal (customers, suppliers, people) |
| `crm_lead_quotes` | 17 | yes | no |  | personal (customers, suppliers, people) |
| `crm_leads` | 32 | yes | no |  | personal (customers, suppliers, people) |
| `crm_metrics` | 17 | yes | no |  | personal (customers, suppliers, people) |
| `crm_metrics_runs` | 8 | yes | no |  | personal (customers, suppliers, people) |
| `crm_notes` | 11 | yes | no |  | personal (customers, suppliers, people) |
| `crm_segment_members` | 3 | yes | no |  | personal (customers, suppliers, people) |
| `crm_segments` | 17 | yes | no |  | personal (customers, suppliers, people) |
| `crm_tags` | 6 | yes | no |  | personal (customers, suppliers, people) |
| `crm_task_events` | 8 | yes | no |  | personal (customers, suppliers, people) |
| `crm_tasks` | 21 | yes | no |  | personal (customers, suppliers, people) |
| `crm_view_log` | 9 | yes | no |  | personal (customers, suppliers, people) |
| `crmc_export_log` | 11 | yes | no |  | personal (customers, suppliers, people) |
| `crmf_coupon_scope` | 3 | yes | no |  | personal (customers, suppliers, people) |
| `crmf_coupon_uses` | 14 | yes | no |  | personal (customers, suppliers, people) |
| `crmf_coupons` | 21 | yes | no |  | personal (customers, suppliers, people) |
| `crmf_expiry_lines` | 4 | yes | no |  | personal (customers, suppliers, people) |
| `crmf_expiry_runs` | 10 | yes | no |  | personal (customers, suppliers, people) |
| `crmf_hook_grants` | 8 | yes | no |  | personal (customers, suppliers, people) |
| `crmf_hooks` | 12 | yes | no |  | personal (customers, suppliers, people) |
| `crmf_liab_postings` | 7 | yes | no |  | personal (customers, suppliers, people) |
| `crmf_referral_codes` | 5 | yes | no |  | personal (customers, suppliers, people) |
| `crmf_referrals` | 15 | yes | no |  | personal (customers, suppliers, people) |
| `customer_addresses` | 14 | yes | no |  | personal (customers, suppliers, people) |
| `customer_dates` | 13 | yes | no |  | personal (customers, suppliers, people) |
| `customer_gifts` | 16 | yes | no |  | personal (customers, suppliers, people) |
| `customer_phones` | 12 | yes | no |  | personal (customers, suppliers, people) |
| `customer_points_ledger` | 11 | yes | no |  | personal (customers, suppliers, people) |
| `customer_tags` | 7 | yes | no |  | personal (customers, suppliers, people) |
| `customer_tier_history` | 10 | yes | no |  | personal (customers, suppliers, people) |
| `customer_tiers` | 22 | yes | no |  | personal (customers, suppliers, people) |
| `customers` | 25 | yes | yes |  | personal (customers, suppliers, people) |
| `d_item_roles` | 5 | yes | no |  | settings |
| `d_material_fixed_price` | 7 | yes | no |  | financial |
| `d_material_roles` | 6 | yes | no |  | settings |
| `d_product_role_req` | 5 | yes | no |  | settings |
| `d_wallet_checks` | 16 | yes | no |  | personal (customers, suppliers, people) |
| `d_wallet_fees` | 16 | yes | no |  | operational |
| `d_wallet_moves` | 18 | yes | no |  | operational |
| `d_wallets` | 12 | yes | no |  | operational |
| `dash_layouts` | 4 | yes | no |  | settings |
| `dealer_cheque_events` | 13 | yes | no |  | log / history |
| `dealer_cheques` | 32 | yes | no |  | high (staff pay / identity) |
| `dealer_scheme_accruals` | 12 | yes | no |  | operational |
| `dealer_scheme_claim_events` | 11 | yes | no |  | log / history |
| `dealer_scheme_claims` | 14 | yes | no |  | operational |
| `dealer_scheme_items` | 3 | yes | no |  | operational |
| `dealer_scheme_slabs` | 6 | yes | no |  | operational |
| `dealer_schemes` | 21 | yes | no |  | operational |
| `dealer_shades` | 7 | yes | no |  | operational |
| `dealer_tint_formula_lines` | 5 | yes | no |  | settings |
| `dealer_tint_formulas` | 14 | yes | no |  | settings |
| `dealer_tint_job_lines` | 9 | yes | no |  | operational |
| `dealer_tint_jobs` | 24 | yes | no |  | personal (customers, suppliers, people) |
| `deed_templates` | 12 | yes | no |  | settings |
| `delivery_events` | 8 | yes | no |  | log / history |
| `delivery_jobs` | 17 | yes | no |  | operational |
| `delivery_zones` | 7 | yes | no |  | operational |
| `doc_template_choice` | 6 | yes | no |  | settings |
| `drawer_events` | 11 | yes | no |  | log / history |
| `emergency_requests` | 18 | yes | yes |  | operational |
| `employee_advance_recoveries` | 7 | yes | no |  | high (staff pay / identity) |
| `employee_advances` | 17 | yes | no |  | high (staff pay / identity) |
| `employee_benefit_grants` | 15 | yes | no |  | high (staff pay / identity) |
| `employee_benefits` | 13 | yes | no |  | high (staff pay / identity) |
| `employee_deeds` | 27 | yes | no |  | high (staff pay / identity) |
| `employee_documents` | 12 | yes | no |  | high (staff pay / identity) |
| `employee_leave_entitlements` | 6 | yes | no |  | high (staff pay / identity) |
| `employee_locations` | 5 | yes | no |  | high (staff pay / identity) |
| `employee_pay` | 13 | yes | no |  | high (staff pay / identity) |
| `employee_pay_components` | 8 | yes | no |  | high (staff pay / identity) |
| `employee_shift_assignments` | 11 | yes | no |  | high (staff pay / identity) |
| `employee_status_log` | 8 | yes | no |  | high (staff pay / identity) |
| `employees` | 40 | yes | no |  | high (staff pay / identity) |
| `entries` | 26 | yes | yes |  | operational |
| `entry_approvers` | 6 | yes | no |  | operational |
| `entry_change_requests` | 14 | yes | yes |  | log / history |
| `entry_count_peeks` | 6 | yes | yes |  | log / history |
| `entry_count_seals` | 8 | yes | no |  | operational |
| `entry_counts` | 13 | yes | yes |  | operational |
| `entry_ledger_posts` | 19 | yes | yes |  | financial |
| `entry_revisions` | 12 | yes | yes |  | log / history |
| `entry_signatures` | 7 | yes | yes |  | operational |
| `exceptions` | 16 | yes | yes |  | operational |
| `fa_assets` | 18 | yes | no |  | financial |
| `fa_depr_posts` | 8 | yes | no |  | operational |
| `factory_cost_pools` | 14 | yes | no |  | financial |
| `festival_calendar` | 14 | yes | no |  | operational |
| `flow_skips` | 9 | yes | no |  | operational |
| `form_code_migration_543` | 9 | yes | no |  | settings |
| `form_rollout` | 6 | yes | yes |  | settings |
| `forms` | 10 | yes | yes |  | settings |
| `forms_ledger_cfg` | 4 | yes | yes |  | financial |
| `gift_rules` | 11 | yes | no |  | settings |
| `grant_defs` | 9 | yes | yes |  | settings |
| `grant_separation_pairs` | 5 | yes | no |  | settings |
| `grn_batch_links` | 12 | yes | no |  | financial |
| `holidays` | 9 | yes | no |  | operational |
| `ie_currencies` | 12 | yes | no |  | operational |
| `ie_fx_rates` | 9 | yes | no |  | operational |
| `ie_shipment_events` | 10 | yes | no |  | log / history |
| `ie_shipments` | 23 | yes | no |  | operational |
| `inbound_message_events` | 7 | yes | no |  | personal (customers, suppliers, people) |
| `inbound_messages` | 16 | yes | no |  | personal (customers, suppliers, people) |
| `inbox_unmask_log99` | 10 | yes | no |  | personal (customers, suppliers, people) |
| `intake_bots` | 5 | yes | no |  | operational |
| `intake_failures` | 13 | yes | no |  | operational |
| `intake_hits` | 4 | yes | no |  | operational |
| `intake_proofs94` | 4 | **NO** | no | has secret-looking column(s): secret_hash | secret |
| `integration_config_versions` | 7 | yes | no |  | settings |
| `integration_registry` | 21 | yes | no |  | operational |
| `invoice_shares` | 7 | yes | no |  | financial |
| `invoice_templates` | 16 | yes | yes |  | financial |
| `item_aliases` | 8 | yes | no |  | operational |
| `item_bulk_batches` | 14 | yes | yes |  | financial |
| `item_categories` | 15 | yes | no |  | settings |
| `item_changes` | 13 | yes | yes |  | log / history |
| `item_class_map` | 5 | yes | yes |  | settings |
| `item_cost_flags` | 7 | yes | no |  | financial |
| `item_costs` | 5 | yes | yes |  | financial |
| `item_import_batches` | 12 | yes | yes |  | financial |
| `item_logistics` | 7 | yes | no |  | log / history |
| `item_map_actions` | 10 | yes | yes |  | settings |
| `item_mapping_review` | 11 | yes | yes |  | settings |
| `item_master_links` | 9 | yes | yes |  | operational |
| `item_new_clients` | 6 | yes | no |  | operational |
| `item_price_history` | 7 | yes | yes |  | financial |
| `item_recognition_reviews` | 8 | yes | no |  | settings |
| `item_styles` | 16 | yes | no |  | operational |
| `item_suppliers` | 11 | yes | no |  | personal (customers, suppliers, people) |
| `item_types` | 11 | yes | yes |  | settings |
| `items` | 41 | yes | yes |  | operational |
| `job_heartbeat` | 3 | yes | no |  | operational |
| `job_runs` | 9 | yes | no |  | log / history |
| `journal_entries` | 15 | yes | no |  | financial |
| `journal_lines` | 9 | yes | no |  | financial |
| `kpi_snapshots` | 6 | yes | no |  | operational |
| `landed_cost_alloc` | 13 | yes | no |  | financial |
| `landed_cost_basis` | 5 | yes | no |  | financial |
| `landed_cost_docs` | 4 | yes | no |  | financial |
| `landed_cost_lines` | 13 | yes | no |  | financial |
| `landed_cost_stock` | 16 | yes | no |  | financial |
| `landed_costs` | 24 | yes | no |  | financial |
| `landed_skips` | 5 | yes | no |  | financial |
| `landed_supplier_flags` | 7 | yes | no |  | personal (customers, suppliers, people) |
| `late_sales_held` | 15 | yes | no |  | financial |
| `leave_requests` | 14 | yes | no |  | operational |
| `leave_types` | 7 | yes | no |  | settings |
| `ledger_cost_supply96` | 12 | yes | no |  | financial |
| `legal_entities` | 10 | yes | no |  | operational |
| `list_defs` | 13 | yes | yes |  | settings |
| `list_managers` | 5 | yes | yes |  | settings |
| `list_other_entries` | 14 | yes | yes |  | settings |
| `location_block_overrides` | 6 | yes | no |  | operational |
| `location_cost_attribution` | 17 | yes | no |  | financial |
| `location_cost_cfg` | 9 | yes | no |  | financial |
| `location_settings` | 5 | yes | yes |  | settings |
| `location_setup_steps` | 11 | yes | yes |  | operational |
| `locations` | 25 | yes | yes |  | operational |
| `login_attempts` | 5 | **NO** | yes | login throttle data, re-created by use | log / history |
| `login_failures` | 6 | **NO** | yes | login throttle data, re-created by use | log / history |
| `login_throttle` | 3 | **NO** | no | login throttle data, re-created by use | log / history |
| `manual_reason_codes85` | 8 | yes | no |  | operational |
| `master_ctx132` | 3 | yes | no |  | operational |
| `master_scope132` | 16 | yes | no |  | operational |
| `master_shares132` | 13 | yes | no |  | operational |
| `master_unique_log132` | 6 | yes | no |  | log / history |
| `mi_adapters` | 6 | yes | no |  | operational |
| `mi_finding_files` | 7 | yes | no |  | operational |
| `mi_findings` | 20 | yes | no |  | operational |
| `mi_job_defs` | 11 | yes | no |  | settings |
| `mi_offer_log` | 9 | yes | no |  | log / history |
| `mi_opp_decisions` | 8 | yes | no |  | operational |
| `mi_opp_links` | 5 | yes | no |  | operational |
| `mi_opp_outcomes` | 16 | yes | no |  | operational |
| `mi_opportunities` | 31 | yes | no |  | settings |
| `mi_price_obs` | 12 | yes | no |  | financial |
| `mi_product_gaps` | 9 | yes | no |  | operational |
| `mi_sources` | 20 | yes | no |  | operational |
| `mi_summary_decisions` | 6 | yes | no |  | operational |
| `mi_summary_proposals` | 6 | yes | no |  | operational |
| `mi_topics` | 16 | yes | no |  | operational |
| `mkt_order_tags` | 8 | yes | no |  | financial |
| `mkt_post_decisions` | 9 | yes | no |  | operational |
| `mkt_sale_tags` | 8 | yes | no |  | financial |
| `money_accounts` | 22 | yes | no |  | high (staff pay / identity) |
| `money_charges` | 16 | yes | no |  | operational |
| `money_checks` | 14 | yes | no |  | operational |
| `money_event_settings` | 9 | yes | no |  | log / history |
| `money_exception_grants` | 15 | yes | no |  | settings |
| `money_exceptions` | 14 | yes | no |  | operational |
| `money_recurring` | 15 | yes | no |  | operational |
| `money_transfers` | 19 | yes | no |  | financial |
| `notification_reads` | 3 | **NO** | no | run-time table of the backup / notification module, re-created by the app | log / history |
| `notifications` | 17 | **NO** | no | run-time table of the backup / notification module, re-created by the app | personal (customers, suppliers, people) |
| `notify_optin` | 9 | yes | no |  | log / history |
| `notify_optin_log` | 8 | yes | no |  | log / history |
| `notify_outbox` | 19 | yes | no |  | personal (customers, suppliers, people) |
| `notify_templates` | 7 | yes | no |  | log / history |
| `online_order_events` | 8 | yes | no |  | financial |
| `online_order_flags` | 11 | yes | no |  | financial |
| `online_orders` | 42 | yes | no |  | personal (customers, suppliers, people) |
| `open_party_adjustments` | 17 | yes | no |  | personal (customers, suppliers, people) |
| `opening_batches` | 7 | yes | no |  | financial |
| `opening_stock_actions96` | 12 | yes | no |  | financial |
| `opening_stock_followups103` | 13 | yes | no |  | financial |
| `ops_accounts` | 6 | **NO** | no | bot-account marks (re-made after a restore; the staff manifest lists them) | operational |
| `option_lists` | 14 | yes | yes |  | settings |
| `option_requests` | 15 | yes | yes |  | settings |
| `option_sets` | 13 | yes | no |  | settings |
| `option_values` | 12 | yes | no |  | settings |
| `option_view_ops` | 5 | yes | no |  | settings |
| `order_advance_posts` | 17 | yes | no |  | high (staff pay / identity) |
| `order_cake_specs` | 16 | yes | no |  | financial |
| `order_delivery_costs` | 15 | yes | no |  | financial |
| `order_dup_flags` | 11 | yes | no |  | financial |
| `order_promises` | 12 | yes | no |  | financial |
| `order_refunds` | 19 | yes | no |  | financial |
| `org_units` | 21 | yes | no |  | settings |
| `other_income` | 19 | yes | no |  | operational |
| `owner_board_items` | 7 | yes | no |  | operational |
| `paper_books` | 12 | yes | no |  | operational |
| `parallel_months` | 9 | yes | no |  | operational |
| `partner_agreements` | 19 | yes | no |  | operational |
| `partner_capital` | 17 | yes | no |  | operational |
| `partner_parties` | 13 | yes | no |  | high (staff pay / identity) |
| `partner_rules` | 8 | yes | no |  | settings |
| `partner_settlement_lines` | 9 | yes | no |  | operational |
| `partner_settlement_payments` | 10 | yes | no |  | financial |
| `partner_settlements` | 18 | yes | no |  | operational |
| `partner_templates` | 11 | yes | no |  | settings |
| `partner_ventures` | 13 | yes | no |  | operational |
| `path_domains` | 11 | yes | no |  | settings |
| `path_switch` | 8 | yes | no |  | settings |
| `pay_captures` | 25 | yes | no |  | operational |
| `pay_request_events` | 10 | yes | no |  | high (staff pay / identity) |
| `pay_request_exceptions` | 12 | yes | no |  | high (staff pay / identity) |
| `pay_requests` | 29 | yes | no |  | high (staff pay / identity) |
| `pay_statement_lines` | 10 | yes | no |  | operational |
| `payment_intents` | 15 | yes | no |  | financial |
| `payment_webhook_log` | 12 | yes | no |  | financial |
| `payroll_bonus_events` | 7 | yes | no |  | high (staff pay / identity) |
| `payroll_lines` | 48 | yes | no |  | high (staff pay / identity) |
| `payroll_payments` | 18 | yes | no |  | high (staff pay / identity) |
| `payroll_runs` | 14 | yes | no |  | high (staff pay / identity) |
| `period_overrides` | 15 | yes | no |  | financial |
| `perm_conflict` | 6 | yes | no |  | operational |
| `perm_reco_ignore` | 4 | yes | no |  | settings |
| `perm_reco_role` | 5 | yes | no |  | settings |
| `pin_sig_cfg` | 4 | yes | yes |  | settings |
| `pool_gl_posts117` | 9 | yes | no |  | operational |
| `pos_failed_cards` | 13 | yes | no |  | operational |
| `pos_replay_log` | 10 | yes | no |  | log / history |
| `price_list_items` | 12 | yes | no |  | financial |
| `price_lists` | 14 | yes | no |  | financial |
| `print_notes` | 10 | yes | no |  | settings |
| `print_profiles` | 11 | yes | yes |  | settings |
| `product_packaging` | 10 | yes | yes |  | operational |
| `production_crew` | 11 | yes | no |  | financial |
| `production_issue_actual` | 11 | yes | no |  | financial |
| `production_labour` | 13 | yes | no |  | financial |
| `production_lines` | 10 | yes | no |  | financial |
| `production_loss` | 14 | yes | no |  | financial |
| `production_orders` | 16 | yes | no |  | financial |
| `production_plans` | 16 | yes | no |  | financial |
| `production_reprice116` | 10 | yes | no |  | financial |
| `production_run_links` | 6 | yes | no |  | financial |
| `production_run_orders` | 12 | yes | no |  | financial |
| `production_runs` | 33 | yes | yes |  | financial |
| `profiles` | 6 | yes | yes |  | personal (customers, suppliers, people) |
| `profit_row_exclusions` | 13 | yes | no |  | operational |
| `purchase_bills` | 26 | yes | yes |  | financial |
| `purchase_lines` | 11 | yes | yes |  | financial |
| `qc_records` | 16 | yes | no |  | settings |
| `quick_expenses` | 18 | yes | no |  | financial |
| `r2_announce_seen` | 3 | yes | no |  | operational |
| `r2_announcements` | 17 | yes | no |  | operational |
| `r2_roster_days` | 10 | yes | no |  | operational |
| `r2_todos` | 18 | yes | no |  | operational |
| `recall_batches` | 10 | yes | no |  | financial |
| `recall_cases` | 14 | yes | no |  | operational |
| `receipt_lots` | 15 | yes | no |  | operational |
| `recipe_cost_components` | 13 | yes | no |  | financial |
| `recipe_lines` | 10 | yes | yes |  | financial |
| `recipe_std116` | 15 | yes | no |  | financial |
| `recipe_steps` | 18 | yes | no |  | financial |
| `recipe_versions` | 12 | yes | no |  | financial |
| `recipes` | 19 | yes | yes |  | financial |
| `release_requests` | 13 | yes | yes |  | operational |
| `report_brand_map` | 4 | yes | yes |  | settings |
| `report_brand_map_hist` | 11 | yes | no |  | settings |
| `report_defs3` | 16 | yes | no |  | settings |
| `report_notice_topics` | 3 | yes | no |  | operational |
| `report_views` | 8 | yes | no |  | operational |
| `restore_drills` | 9 | yes | no |  | log / history |
| `riders` | 10 | yes | no |  | personal (customers, suppliers, people) |
| `role_favourites` | 4 | yes | yes |  | settings |
| `role_form_overrides133` | 14 | yes | no |  | settings |
| `role_form_perms` | 5 | yes | yes |  | settings |
| `role_option_view` | 5 | yes | no |  | settings |
| `roles` | 8 | yes | yes |  | settings |
| `rpthub_user_items` | 9 | yes | no |  | operational |
| `rule_grant_overrides133` | 12 | yes | no |  | settings |
| `rule_grants` | 3 | yes | yes |  | settings |
| `rule_overrides` | 11 | yes | no |  | settings |
| `rules` | 18 | yes | yes |  | settings |
| `sale_base_factor` | 5 | yes | no |  | financial |
| `sale_form_links` | 14 | yes | no |  | financial |
| `sale_payments` | 20 | yes | yes |  | financial |
| `sale_price_overrides` | 6 | yes | no |  | financial |
| `sale_return_packaging80` | 9 | yes | no |  | financial |
| `sale_returns` | 22 | yes | yes |  | financial |
| `sale_tier_use` | 6 | yes | no |  | financial |
| `sales` | 31 | yes | yes |  | financial |
| `sales_channels` | 12 | yes | no |  | financial |
| `sales_fact_t` | 24 | yes | no |  | financial |
| `sales_targets` | 13 | yes | no |  | financial |
| `scan_events` | 9 | yes | no |  | log / history |
| `scan_jobs` | 30 | yes | no |  | operational |
| `serials` | 3 | yes | no |  | operational |
| `settings` | 7 | yes | yes |  | settings |
| `settings_keys` | 5 | yes | no |  | settings |
| `settings_sheets` | 14 | yes | yes |  | settings |
| `settings_values` | 3 | yes | yes |  | settings |
| `setup_apply_batches81` | 6 | yes | no |  | financial |
| `setup_apply_lines81` | 8 | yes | no |  | operational |
| `setup_check_defs81` | 14 | yes | no |  | settings |
| `setup_rec_defs81` | 11 | yes | no |  | settings |
| `setup_topic_defs81` | 6 | yes | no |  | settings |
| `shadow_links` | 14 | yes | no |  | operational |
| `shelf_life_rules` | 15 | yes | yes |  | settings |
| `shifts` | 16 | yes | no |  | operational |
| `shortage_cash_cases` | 17 | yes | no |  | financial |
| `shortage_transit` | 17 | yes | no |  | operational |
| `shortage_transit_events` | 11 | yes | no |  | log / history |
| `site_config` | 13 | yes | no |  | personal (customers, suppliers, people) |
| `social_deliveries` | 17 | yes | no |  | operational |
| `social_item_events` | 10 | yes | no |  | log / history |
| `social_items` | 27 | yes | no |  | operational |
| `social_metrics` | 7 | yes | no |  | operational |
| `staff_roles` | 7 | yes | no |  | settings |
| `stock_balance` | 5 | yes | yes |  | financial |
| `stock_batches` | 12 | yes | yes |  | financial |
| `stock_ledger` | 15 | yes | yes |  | financial |
| `stock_tracking_map` | 7 | yes | no |  | financial |
| `stock_transfers` | 23 | yes | yes |  | financial |
| `stock_wastage` | 13 | yes | yes |  | financial |
| `stockout_log` | 14 | yes | no |  | financial |
| `style_axes` | 3 | yes | no |  | operational |
| `supplier_item_prices` | 15 | yes | no |  | personal (customers, suppliers, people) |
| `supplier_payments` | 18 | yes | yes |  | personal (customers, suppliers, people) |
| `supplier_refunds` | 17 | yes | yes |  | personal (customers, suppliers, people) |
| `suppliers` | 16 | yes | yes |  | high (staff pay / identity) |
| `telegram_chat_links` | 12 | yes | no |  | personal (customers, suppliers, people) |
| `telegram_secrets` | 4 | **NO** | no | name contains _secret (stores a secret hash) | secret |
| `unit_conversions` | 10 | yes | yes |  | settings |
| `user_favourites` | 9 | yes | no |  | settings |
| `user_grants` | 8 | yes | yes |  | settings |
| `user_locations` | 2 | yes | yes |  | operational |
| `user_option_view` | 5 | yes | no |  | settings |
| `user_org_scopes` | 12 | yes | no |  | operational |
| `user_roles` | 2 | yes | yes |  | settings |
| `w1c_exit_keep` | 8 | yes | no |  | operational |
| `w1c_exit_log` | 12 | yes | no |  | log / history |
| `w1c_return_class_rules` | 9 | yes | no |  | financial |
| `w1c_return_lines` | 14 | yes | no |  | financial |
| `w1c_returns` | 10 | yes | no |  | financial |
| `w1e_mapping_types` | 6 | yes | no |  | settings |
| `w1e_requests` | 22 | yes | no |  | operational |
| `w1f_seed_state` | 14 | yes | no |  | operational |
| `w1g_post_runs` | 12 | yes | no |  | log / history |
| `w1g_post_watermark` | 13 | yes | no |  | operational |
| `w1g_sched_state` | 5 | yes | no |  | operational |
| `w1g_switch_acks` | 7 | yes | no |  | settings |
| `wastage_requests` | 18 | yes | yes |  | financial |
| `web_cancel_requests` | 8 | yes | no |  | operational |
| `web_closures` | 6 | yes | no |  | operational |
| `web_custom_requests` | 16 | yes | no |  | personal (customers, suppliers, people) |
| `web_item_images` | 11 | yes | no |  | operational |
| `web_item_pub` | 18 | yes | no |  | operational |
| `web_pickup_points` | 7 | yes | no |  | personal (customers, suppliers, people) |
| `web_rate_hits` | 3 | yes | no |  | operational |
| `web_stock_holds` | 11 | yes | no |  | financial |
| `web_zones` | 10 | yes | no |  | operational |
| `webhook_rotations` | 6 | yes | no |  | operational |
| `x1_gate_log` | 9 | yes | no |  | log / history |
| `xc_prod_feedback` | 16 | yes | no |  | operational |
| `xc_summary_log` | 10 | yes | no |  | log / history |
| `xc_summary_recipients` | 12 | yes | no |  | personal (customers, suppliers, people) |
| `xc_unsold_outcomes` | 18 | yes | no |  | operational |
| `year_closes` | 16 | yes | no |  | operational |

Names in the app button list that are not a table of the schema (no data, the button records an error for them): none.
<!-- matrix:end -->

Why the ten tables are left out, in one line each: `attendance_devices` (device token hash; the other columns are in `accounts.json`), `intake_proofs94` and `telegram_secrets` (secret hashes, set again after a restore),
`login_attempts / login_failures / login_throttle` (re-created by use), `backup_runs / notifications / notification_reads` (run-time tables of the backup and bell module),
`ops_accounts` (bot marks, in `accounts.json`). Everything else is in.

## 4. Auth (Supabase Authentication, schema `auth`)

| Item | In the backup? | Why / how it comes back | Sensitivity |
|---|---|---|---|
| Login id (`auth.users.id`) and e-mail (`<staff id>@<emailDomain>`) | **Yes** in `accounts.json`, when rule `backup_accounts_on` is ON (default OFF) | `restore_accounts.py create` makes the user again with the same id | personal |
| Staff id, name, status, language (`profiles`) | Yes (table, and in `accounts.json`) | table restore | personal |
| Roles, locations, grants (`user_roles`, `user_locations`, `user_grants`) | Yes (tables, and in `accounts.json`) | table restore, keyed by the same ids | access control |
| Which login is a backup / notify bot (`ops_accounts`) | Yes in `accounts.json` only | follow-up SQL written by `restore_accounts.py` | access control |
| Password (the app uses `<PIN>-bos`) and PIN hash | **No, never** | Supabase keeps only a hash and it cannot be exported. Every person gets a **new PIN**: `restore_accounts.py reset-pin` | secret |
| 2FA (TOTP) enrolment | **No** (only "has 2FA yes/no" is listed) | the person enrols again | secret |
| Active sessions, refresh tokens | No | people sign in again | secret |
| Attendance machine tokens | No (hash excluded) | enrol the machine again in the app | secret |
| Supabase dashboard settings (auth providers, e-mail templates, password rules, site URL) | No | outside the database; note them once by hand (guide, checklist) | config |

## 5. Storage (buckets)

| Bucket | Content | Public? | Backed up? | Restore | Sensitivity |
|---|---|---|---|---|---|
| `photos` | item pictures, expense vouchers, GRN, maintenance, scan photos | private | **Yes**, always (phase 46 policy `ops_photos_read`) into `photos/` | `restore_storage.py` | financial documents, may show people |
| `web-refs` | customer reference pictures for web orders (cake spec) | private | **Yes, once `backup_buckets_on` is ON** (default OFF) into `buckets/web-refs/` | same | personal |
| `payproof` | payment screenshots | private | same switch, `buckets/payproof/` | same | financial, personal |
| `web-public` | approved item photos shown on the website | public | same switch, `buckets/web-public/` | same | public |
| any bucket made later | | | **No** until phase547's policy and `backup_storage_buckets()` list it; it is listed in `storage_buckets.json` as not copied, with its object count | | |

Limits: files bigger than 80 MB in total (all of one bucket) are not put in git; with Google Drive set up they go to Drive only, otherwise the seal step reports a problem and the run turns red.
Photos are added to `latest/photos/` and never removed, so a photo deleted in the app stays in the backup. Photos are **not encrypted** (see G9).

## 6. Everything else

| Item | Backed up? | Note |
|---|---|---|
| The schema (tables, functions, policies) | In the repo (`supabase/*.sql`, paste order in `tests/sql/paste_order.env`) | `manifest.json` records `code.commit` (when run by GitHub) and the sha256 of the paste order file. A restore builds the schema from the repo first. |
| Settings and rules (`rules`, `settings`, `settings_values`, `location_settings` ...) | Yes (tables) | |
| Assistant notes and AI settings (`ai_*`, assistant tables) | Yes (after phase547 for `ai_agents`, `ai_providers`) | the AI **key** is an edge function secret, not in the database |
| Audit log (`audit_log`, `*_log`, `entry_revisions`) | Yes | append-only history is restored as it was |
| Edge function secrets | **Names only** in `manifest.json`: `ANTHROPIC_API_KEY`, `INTAKE_BOT_PASSWORD`, `SCAN_AI_MODEL`, `TELEGRAM_SECRET_TOKEN` (`SUPABASE_ANON_KEY` is set by Supabase itself) | The owner must keep the **values** in his password manager. Set them again with `supabase secrets set NAME=value` or the dashboard. The functions themselves are in the repo (`supabase/functions/`); deploying them is a separate owner step. |
| GitHub Actions secrets (`BOT_PASSWORD`, `BACKUP_PASSPHRASE`, `BACKUP_KDF_SALT`, ...) | No (GitHub never shows them) | keep a copy of `BACKUP_PASSPHRASE` and `BACKUP_KDF_SALT` **outside** GitHub. Without them an encrypted backup cannot be opened. |
| Per-device settings (this phone's language, POS place, nav pins, `bos_device_key`, printer choice) | **No** | browser `localStorage`, per phone. Language and pins are mirrored in the database (`profiles.lang`, `user_favourites`) and come back with the data; the rest is set again in a minute. |
| Records saved on a phone but **not sent yet** (offline queue, IndexedDB `bos_rpcq`, `bos_scan`) | **No** | they exist only on that phone until they are sent. A lost phone loses them. |
| Google Drive copy | Optional | same files as the branch, photos included |
| Anything entered after the last backup | No | up to about 24 hours. |

## 7. Honest limits of this audit

* Built and tested only on a local PostgreSQL 16 with a fake Auth admin API and a fake Storage API. **Nobody has run the new steps in GitHub Actions or against a real Supabase project.**
* `restore_accounts.py` uses the documented Auth admin endpoint with a caller-chosen `id`; this is UNVERIFIED on the real service (the first real restore is the test: see the first-restore checklist).
* The sensitivity column is a name-based guess.
