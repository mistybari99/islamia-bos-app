# Security and permission backlog (reviewed list, nothing applied)

Owner task 5 of the audit of 19 Oct 2026. This file lists, for review, the browser-callable (anon) database functions and the tables that have row security on but no policy. It does not change any grant, policy or function. Narrowing a grant or adding a policy is a separate, tested change, decided by the owner.

## 0. Where the numbers come from, and a warning

> **Superseded (23 Oct 2026).** The comparison below was made before the union merge, on a local build of phases 8 to 505. The chain is now phases up to 546 on `Main-Img` and the live project is being replaced by a new clean project (`docs/NEW_PROJECT_SETUP.md`), so the counts in this section are stale; regenerate the lists from a fresh build before acting on them. Kept as history.


- The lists below were produced from a **local throwaway build** of the repository's own paste chain (phases 8 to 505, `tests/sql/ORDER.txt`), not from the live project. The live project was read by the owner's audit only.
- The counts do not match the live audit:

| Measure | Live (audit) | Local build of this branch |
|---|---:|---:|
| Definer functions with anon EXECUTE | 21 (4 are trigger functions) | 33 (11 trigger functions, 22 RPCs) |
| RLS tables with no policy | 69 | 44 (including 2 new tables of phase 500 and 505) |
| Public functions | 2,888 | 2,372 |

- **27 of the 69 no-policy tables in the live audit do not exist in this branch** (for example `landed_cost_*`, `ie_*`, `business_profile_ops134`, `telegram_secrets`). The live project was therefore built from **a different code line** (the advanced branch `origin/ccr-9c1f9be7-3s9qnz`, which has phases 120 to 135 with other contents). This must be settled before any grant is changed (see docs/PLAN_NEXT.md item 1.1).
- The local harness grants EXECUTE on new functions to anon by default (`alter default privileges ... grant all on functions to anon`), like the hosted default. Phases that revoke anon (for example phase 478) are included. The difference from live (33 against 21) is most likely revokes that live has and this branch does not, or the reverse. **Owner action (read-only, SELECT only):** run the query in section 4 on the live project and compare.

## 1. Anon-executable RPCs (22 local)

"Keep" means the browser or device needs it before login or for the public storefront. "Review" means it is not needed anonymously, but the repository does not prove it (the function is a helper or a legacy path). Nothing is revoked in this task.

| Function | Intended caller (evidence in repo) | Proposal |
|---|---|---|
| `login_failed(text)` | web/app.js, web/pinsign.js: wrong-PIN attempt before login | Keep. Test the rate limit and the lock response. |
| `login_precheck(text)` | web/app.js, web/pinsign.js: lock status before login | Keep. It says whether a staff id is locked: review what an outsider learns. |
| `attendance_punch_push(text, jsonb)` | tools/fingerprint_bridge.py: device token | Keep (device by design). Review token length, rotation and revocation. |
| `set_my_lang(text)` | web/app.js | Review: keep only if the language choice is made on the login screen. |
| `my_context()` | web/app.js (after login) | Review: returns nothing for anon; revoke anon if no pre-login use is found. |
| `staff_directory()` | web/entry.js (signed-in staff) | Review: revoke anon if the login screen does not use it. |
| `record_sale(...)` (legacy 10-argument overload) | web/pos.js: fallback only when record_sale2 is missing (signed-in POS) | Review: revoke anon. No anonymous sale is needed. |
| `request_release(uuid, text, text)` | web/entry.js (signed-in staff) | Review: revoke anon. |
| `resolve_exception(bigint, text)` | web/entry.js (signed-in approver) | Review: revoke anon. The function checks the approver role itself. |
| `can_do(text, text)`, `can_loc(integer)`, `is_active()`, `is_owner()` | helpers for the permission checks; web code calls them when signed in | Review: revoke anon only after a test shows that no policy or view is evaluated for anon. |
| `_m_mgr()`, `_m_view()` | helpers (name begins with underscore: internal) | Review: revoke anon. |
| `web_catalog_v2(text)`, `web_site_config()`, `web_quote(jsonb, integer, text)`, `web_order_track(text, text)`, `web_order_cancel_request(text, text, text, text)`, `web_checkout_submit(...)`, `web_custom_request(...)` | site/assets/site.js and tools/build_site.py: the public storefront | Keep by design. Each needs its own abuse test: rate limit, key hash, mobile match, no price from the browser. |

The 11 trigger functions (`entries_lock`, `entries_paper_required`, `guard_last_owner`, `handle_new_user`, `item_costs_history`, `item_costs_history_after`, `items_before`, `items_price_history`, `log_change`, `log_entry_status`, `sales_lock`) cannot be called as RPCs; their anon EXECUTE is harmless and is not on the review list. The audit's "4 trigger functions" count is the live project's.

## 2. Tables with row security on and no policy (44 local)

Intended access for every one of them: **none from the browser**. Each is read and written only by security-definer functions, which the table of section 3 names. Adding a permissive policy to any of them would open it, so none is proposed. The audit's advice holds: no policy only to clear an advisor warning.

The 27 live-only tables (section 0) are not listed here: they are not in this branch, so their callers cannot be checked in this repository.

## 3. Table to intended caller (definer functions that read or write it)

| Table | Used by (definer functions) |
|---|---|
| acct_post_errors72 | acct_post_pending, acct_status, _w1g_post_scheduled, _w1g_freshness, _w1g_acct_readiness |
| crm_complaints, crm_complaint_events, crm_complaint_returns | the CRM complaint RPCs (`_crmh_*`) |
| crm_feedback | `_crmh_feedback_*`, `_crmh_report` |
| crm_leads, crm_lead_events, crm_lead_lists, crm_lead_quotes | the CRM lead RPCs (`_crmg_*`) |
| crm_metrics, crm_metrics_runs, crmc_export_log | `crmc_*` (metrics, export, scheduled run) |
| crm_notes, customer_addresses, customer_dates, customer_phones, customer_tags | `crma_*` (customer 360, phones, dates, tags, notes) |
| crm_segments, crm_segment_members | `crmc_segment_*`, `_crmc_ids_of` |
| crm_tasks, crm_task_events | `_crmg_*` task functions |
| intake_bots, intake_failures, intake_hits | `intake_bot_set`, `_inb_is_bot`, `intake_failures_list`, `web_order_submit` |
| item_new_clients | item_new2 |
| login_throttle | `_login_throttle`, `_backup_tables` |
| other_income | `_w1f_other_income_*`, `rpt_hub_day`, `rpt_hub_trail`, `_c3_voids` (the web reads it only through RPCs) |
| r2_roster_days | `_r2_plan`, `r2_roster_*` |
| recall_batches, recall_cases | `recall_*` |
| report_notice_topics | report_notes |
| sales_fact_t | `rpt_fact_load`, `rpt_fact_trg`, `report_fact_rebuild`, `report_run` (reports) |
| serials | record_sale, record_sale2, save_entry, online_order_save, web_checkout_submit (number counters) |
| supplier_item_prices | `supplier_price_*`, `purch_price_variance` |
| w1e_mapping_types, w1e_requests | `w1e_*`, `_w1e_*`, `_c3_requests` |
| w1f_seed_state | `_w1f_seed_*` |
| w1g_post_runs, w1g_post_watermark, w1g_sched_state, w1g_switch_acks | `_w1g_*` (scheduled posting, freshness, switch acknowledgement) |
| web_rate_hits | `_web_rate91` (storefront rate limit) |
| sale_base_factor (new, phase 501) | `_sale_stock_out`, `sale_return`. Owner-facing: none. |
| stock_tracking_map (new, phase 505) | `stock_tracking_plan`, `stock_tracking_review`, `stock_tracking_apply` (owner only) |

## 4. Owner's read-only checks on the live project (SELECT only; paste into the SQL editor, nothing is written)

```sql
-- anon-executable definer functions, live
select p.proname, pg_get_function_identity_arguments(p.oid)
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prosecdef and has_function_privilege('anon', p.oid, 'EXECUTE')
order by 1;

-- RLS tables with no policy, live
select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind in ('r', 'p') and c.relrowsecurity
  and not exists (select 1 from pg_policy q where q.polrelid = c.oid)
order by 1;
```

Send the two result lists back. They replace the local lists above, and the review in section 1 is then repeated for the live names.

## 5. What was not changed, and why

- No grant was revoked, no policy added, no function re-granted by this task.
- Revoking anon from the "Review" rows is the proposal. It must be done only after the owner has the live list (section 4), and each revoke is tested with an anonymous persona (the web login screen, the storefront and the device path must still work).
