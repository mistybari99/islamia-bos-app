# BACKUP AND RESTORE GUIDE (for the owner)

Written 23 Oct 2026. Simple English first, a Bangla summary at the end (section 11). The full list of what is and is not saved is `docs/BACKUP_COVERAGE.md`.
Setup of the backup bot and GitHub secrets is `docs/OPS_SETUP.md`. The plan for a new Supabase project is `docs/NEW_PROJECT_SETUP.md`.

**Status: tested on a local PostgreSQL only.** A full cycle (backup, wipe, restore, compare) passed on a throwaway local database with test data (section 9). It has **not** been run in GitHub Actions or against a real Supabase project. Your first real restore is the real test: use the checklist in section 8.

## 1. What is backed up

| Thing | Backed up? | Where |
|---|---|---|
| Everything entered through forms: entries, registrations, orders, customers, suppliers, items, stock, sales, purchases, accounting (journal), settings and rules, assistant notes, AI settings, audit log (468 tables) | Yes | `<table>.ndjson.gz` (or `.ndjson.gz.enc` when encrypted) |
| Staff login **list**: staff id, name, e-mail, roles, locations, grants, which login is a bot, attendance machines (no secrets) | Yes, **after you switch it on** (section 2) | `accounts.json` (or `.enc`) |
| Photos: item pictures, expense vouchers, GRN, maintenance | Yes | `photos/` |
| Other buckets: `web-refs`, `payproof`, `web-public` | Yes, **after you switch it on** | `buckets/<bucket>/` |
| A manifest with row counts, SHA-256 per file and a row checksum per table | Yes | `manifest.json` (`manifest_version` 2), `photos_manifest.json`, `storage_manifest_<bucket>.json` |
| Names (not values) of the edge function secrets | Yes | inside `manifest.json` |
| The schema (tables, functions, rules) | In the repository, not in the backup | `supabase/*.sql`, order in `tests/sql/paste_order.env` |
| **Passwords and PINs** | **Never** | Supabase cannot export them. Every person gets a new PIN after a restore (section 5, step 8) |
| 2FA enrolments, edge function secret **values**, GitHub secrets, phone settings, unsent offline records | **No** | section 7 |

## 2. Where it goes, how often, and the two switches

* Every night at 02:30 (Dhaka) the GitHub workflow `backup` makes the copy and commits it to the `backups` branch of your **private** repo `mistybari99/My-tools`: `latest/` = newest, `YYYY/MM/DD/` = that day, and the commit list = every version. It stops by itself if the repo is public. Optional second copy: Google Drive.
* The workflow uses the least-privilege bot and the public key only. It never uses the `service_role` key. Nobody but this workflow pushes.
* **Encryption (recommended):** keep a long passphrase in a password manager, store it as GitHub secret `BACKUP_PASSPHRASE` (and `BACKUP_KDF_SALT`), keep a **second copy outside GitHub**, then switch ON `backup_encrypt_on`. Without the passphrase an encrypted backup cannot be opened by anyone, including us. Photos are not encrypted.
* **Two new switches (both OFF until you turn them on)** after pasting `supabase/phase547.sql` in the SQL editor:
  * `backup_accounts_on`: put the staff login list in the nightly backup.
  * `backup_buckets_on`: let the backup bot also read `web-refs`, `payproof`, `web-public`.
  ```
  update public.rules set value = 'true'::jsonb where key = 'backup_accounts_on';
  update public.rules set value = 'true'::jsonb where key = 'backup_buckets_on';
  ```
  (or in the Switchboard). Then run the `backup` workflow once by hand and open the newest commit on `backups`: `latest/accounts.json` (or `.enc`) must be there and `manifest.json` must show `"manifest_version": 2` and a `storage` block with `"status": "ok"`.
* **If a backup fails:** the workflow run turns red (GitHub e-mails you by its normal rules). If no good backup exists for 36 hours (`backup_max_age_hours`) the bell in the app turns red and `notify.yml` sends an urgent e-mail. Nothing paid was added. Check the Actions page when you see either.

## 3. What you need before a disaster

1. Access to the private repo (2-step login on GitHub).
2. `BACKUP_PASSPHRASE` and `BACKUP_KDF_SALT` **outside GitHub**.
3. The values of the edge function secrets (names in `manifest.json`): `ANTHROPIC_API_KEY`, `INTAKE_BOT_PASSWORD`, `SCAN_AI_MODEL`, `TELEGRAM_SECRET_TOKEN`.
4. A computer with Python 3, `git` and the `psql` client. Not a phone.
5. A clone of the code repo (for `tools/` and `supabase/`).

## 4. Where the tools are

| Tool | Job |
|---|---|
| `tools/backup_crypto.py decrypt <src> <dst>` | opens an encrypted backup folder (needs the passphrase in `BACKUP_PASSPHRASE`) |
| `tools/restore_accounts.py plan / create / reset-pin` | the logins and PINs |
| `tools/restore_backup.py` | checks the files and writes the restore SQL (ends with a row-count check) |
| `tools/verify_restore.py` | compares the restored database with the backup: counts and row checksums |
| `tools/restore_storage.py` | puts photos back into the buckets |
| `tools/restore_drill.py` | a full practice restore into a local scratch database |

## 5. Restore into a NEW Supabase project, step by step

Do this on a computer. Keep the **old project paused, not deleted**, until step 11 is done and a month has passed. Never run these against the old live project.

1. **Make the new project** and note: Project URL, publishable key, and the database connection string (Project settings > Database). Note the secret (`service_role`) key too. It is used **only on your own computer, in an environment variable**, for steps 4 and 9. Never put it in GitHub or in a file in the repo.
2. **Build the schema:** paste the phase files in the order of `docs/PASTE_ORDER.md` (plan: `docs/NEW_PROJECT_SETUP.md`), including `phase547.sql`. Stop at the first error. This also creates the empty buckets `photos`, `web-refs`, `web-public`, `payproof`.
3. **Get and open the backup:**
   ```
   git clone --branch backups --single-branch https://github.com/mistybari99/My-tools.git backups
   export BACKUP_PASSPHRASE='...'            # and BACKUP_KDF_SALT if you set one
   python3 tools/backup_crypto.py decrypt backups/latest plain       # skip when the backup is not encrypted: use backups/latest as "plain"
   python3 tools/restore_backup.py plain --dry-run --photos-root backups/latest
   ```
   The dry run must print the tables and counts and finish without "NOT intact". A wrong passphrase, a damaged file or a changed photo stops here. Use `backups/2026/10/14` instead of `latest` for an older day (then keep `--photos-root backups/latest`).
4. **Logins first** (they must exist with the same ids before the data):
   ```
   python3 tools/restore_accounts.py plan plain
   export SUPABASE_SERVICE_KEY='...'         # your own computer only
   python3 tools/restore_accounts.py create plain --url https://<new-ref>.supabase.co --follow-up followups.sql
   unset SUPABASE_SERVICE_KEY
   ```
   Every person is created with the same id and e-mail and a random password that nobody knows. If there is no `accounts.json` (the switch was OFF), see "if there is no accounts.json" below.
5. **The data.** `--truncate` is right for a new project (it empties each table that the backup holds, then fills it; it is destructive, so only on the new project):
   ```
   python3 tools/restore_backup.py plain --truncate --out restore.sql
   psql "<database connection string>" -v ON_ERROR_STOP=1 -f restore.sql         # or restore.part01.sql, part02 ... in order
   ```
   (Pasting into the SQL editor also works for small backups; each file is one transaction.) The last file ends with a row-count check. If a count is wrong the file is undone and psql prints `RESTORE CHECK FAILED`.
6. **Verify the content** (reads only):
   ```
   PGPASSWORD='<db password>' python3 tools/verify_restore.py plain --allow-remote --dsn "postgresql://postgres@db.<new-ref>.supabase.co:5432/postgres?sslmode=require" --report verify.json
   ```
   It must print `"result": "PASS"` (every table identical, every login present, no profile without a login). Run it **before** step 7, because step 7 adds lines to the audit log.
7. **Bot marks:** paste `followups.sql` in the SQL editor. Then set a new long password for the backup bot in Authentication > Users and put it in the GitHub secret `BOT_PASSWORD` (see `docs/OPS_SETUP.md`). Update `SUPABASE_URL`, `SUPABASE_ANON_KEY` (publishable key) too.
8. **PINs: every person needs a new PIN.** The app signs in with the password `<PIN>-bos` (4 to 6 digits). Per person (the tool asks for the PIN, typed hidden):
   ```
   export SUPABASE_SERVICE_KEY='...'
   python3 tools/restore_accounts.py reset-pin <staff id> --url https://<new-ref>.supabase.co
   ```
   Tell the person their PIN privately. If someone is locked after 5 wrong tries, unlock them in the app (Staff) or wait 10 minutes. The same command resets a forgotten PIN at any time. People who used 2FA enrol again.
9. **Photos:**
   ```
   python3 tools/restore_storage.py plain --url https://<new-ref>.supabase.co --root backups/latest --dry-run
   python3 tools/restore_storage.py plain --url https://<new-ref>.supabase.co --root backups/latest
   ```
   It checks each file's SHA-256 before upload, never overwrites a file that exists, then compares the object count. It must print `"result": "PASS"`.
10. **Edge functions:** deploy the functions from `supabase/functions/` and set the secrets again (names listed in `manifest.json` under `edge_function_secret_names_expected`). Without them the scan, intake bot and Telegram webhook do not work.
11. **Point the app at the new project** (`web/config.js`, see `docs/NEW_PROJECT_SETUP.md` section 7), run the `backup` workflow once and check it is green and that `latest/manifest.json` is new. Then switch the two switches and encryption ON again if you want them (they come back with the data, check them).

**If there is no `accounts.json`** (the switch was OFF): the app builds every login e-mail as `<staff id>@<emailDomain>` (`web/config.js`), so the logins can be derived from the backed-up `profiles` table: add `--email-domain staff.islamia-bos.app` (the value in `web/config.js`) to `plan` and `create`. Same ids, same e-mails. What is lost then: the bot marks (mark the backup bot again as in `docs/OPS_SETUP.md` step 3) and the attendance machine list (enrol the machines again). Roles, locations and grants still come back with the data restore. This works only when `profiles` is in the backup, which it always is.

## 6. Test a restore every month (30 minutes, on a computer)

A backup nobody restored is only a hope. Once a month, on a scratch **local** database (never the live project):

```
git clone --branch backups --single-branch https://github.com/mistybari99/My-tools.git backups
python3 tools/backup_crypto.py decrypt backups/latest plain         # if encrypted
bash tests/sql/final_build.sh bos_scratch                           # needs a local Postgres 16, see docs/RESTORE_DRILL.md
python3 tools/restore_drill.py plain --dsn "postgresql://postgres@localhost:5432/bos_scratch"
python3 tools/verify_restore.py plain --dsn "postgresql://postgres@localhost:5432/bos_scratch"
python3 tools/restore_backup.py plain --dry-run --photos-root backups/latest
```
All three must say PASS / intact. Then open `#/restoredrill` in the app and record the result (the app warns after 90 days without a pass). If anything fails, **tell the lead the same day**: the nightly backup is then not trustworthy.

## 7. What is NOT covered (honest list)

* Passwords, PINs and 2FA. Everybody sets a new PIN after a restore.
* Edge function secret **values** and GitHub secrets. Keep them in your password manager. Only the names are in the backup.
* Phone settings and **records saved on a phone but not sent yet**. A lost phone loses those.
* Changes after the last night's backup (up to about 24 hours).
* Photos deleted in the app stay in the backup, and photos are not encrypted even when the tables are.
* Photos in total above 80 MB per bucket do not go to git: they need Google Drive or the seal step turns the run red.
* The app button "Download all data" holds only 77 of 478 tables. It is not a backup.
* Supabase dashboard settings (e-mail templates, auth providers, password rules, site URL): note them once by hand.
* If you lose the GitHub account and have no Drive copy, the backups are gone. Keep 2-step login on and use Drive.
* If you lose the passphrase of an encrypted backup, it cannot be recovered.
* Not verified in GitHub Actions or on a real Supabase project (section 9).

## 8. First-restore checklist (tick every line; stop at the first red)

- [ ] Old project is paused, not deleted. Last backup is less than a day old (`latest/manifest.json` `finished_at`).
- [ ] `BACKUP_PASSPHRASE` and `BACKUP_KDF_SALT` read from the password manager (not from GitHub).
- [ ] New project made; URL, publishable key, DB connection string and secret key noted.
- [ ] Phase files pasted in order, including `phase547.sql`, no error. The four buckets exist.
- [ ] `restore_backup.py --dry-run` prints the tables and counts, no "NOT intact".
- [ ] `restore_accounts.py plan` lists the people you expect (count and staff ids).
- [ ] `restore_accounts.py create` ends with `0 failed`.
- [ ] Data restore finished without `RESTORE CHECK FAILED`.
- [ ] `verify_restore.py` says `PASS` (468 tables identical, logins present).
- [ ] `followups.sql` pasted; bot has a new password; GitHub secrets updated; one backup run is green.
- [ ] `restore_storage.py` says `PASS`; open three photos in the app (an item, a voucher, a GRN).
- [ ] Edge function secrets set; one scan and one intake test work.
- [ ] You, then one staff member per role, signed in with a new PIN; one test sale and one test entry each.
- [ ] Trial balance (debit = credit) and one item's stock agree with the old project's last report.
- [ ] Staff told to close and reopen the app once. Old project kept (paused) for a month.
- [ ] Result recorded in `#/restoredrill`. Anything you could not confirm is written down and sent to the lead.

## 9. What was proved, and what was not

Proved on a throwaway local PostgreSQL 16 (`tools/test_backup_coverage.py`, test rows named `test_*` only): the schema built from every phase, a seeded database, an **encrypted** backup through the real SQL functions, the source database dropped, a new copy of the schema, logins re-created through a fake Auth admin API, data restored, `verify_restore.py` = all 468 tables identical (count and row checksum), logins present, photos from four buckets put back with the same SHA-256, and a changed row or photo is caught. The existing tests (`tools/test_ops.py`, `tools/test_backup_crypto.py`, `tools/check_backup_guard.py`) still pass.

**Not verified:** a GitHub Actions run of the changed workflow, the real Supabase Storage API (listing, upload, bucket policies), the real Supabase Auth admin API (`id` when creating a user), `psql` against a real Supabase database, the `ops_buckets_read` policy against the real storage schema (the local one is a small stand-in).

## 10. Where each piece of work lives

`supabase/phase547.sql` (+ `phase547_test.sql`), `tools/backup_dump.py`, `tools/backup_photos.py`, `tools/backup_seal.py`, `tools/restore_backup.py`, `tools/verify_restore.py`, `tools/restore_accounts.py`, `tools/restore_storage.py`, `tools/backup_coverage_matrix.py`, `.github/workflows/backup.yml`.

## 11. বাংলা সারসংক্ষেপ

* **কী ব্যাকআপ হয়:** ফর্মে দেওয়া সব তথ্য (এন্ট্রি, অর্ডার, কাস্টমার, আইটেম, স্টক, বিক্রি, হিসাব, সেটিং, অডিট লগ) - ৪৬৮টি টেবিল। ছবি (`photos`)। দুটি সুইচ চালু করলে স্টাফ লগইনের তালিকা (staff id, নাম, role, জায়গা, grant) এবং `web-refs`, `payproof`, `web-public` ছবিও।
* **কোথায়, কতবার:** প্রতি রাত ২:৩০-এ (ঢাকা) আপনার **প্রাইভেট** GitHub repo-র `backups` branch-এ। প্রতিটি রান একটি ভার্সন। repo public হলে নিজে থেমে যায়। `backup_encrypt_on` চালু করলে ফাইল পাসফ্রেজ দিয়ে তালা দেওয়া থাকে; পাসফ্রেজ GitHub-এর বাইরে আলাদা জায়গায় রাখুন, হারালে ব্যাকআপ খোলা যাবে না।
* **যা ব্যাকআপে নেই:** পাসওয়ার্ড ও PIN (কখনোই নয়), 2FA, edge function secret-এর মান, ফোনের নিজস্ব সেটিং, ফোনে সেভ করা কিন্তু এখনো না-পাঠানো রেকর্ড, শেষ ব্যাকআপের পরের পরিবর্তন (প্রায় ২৪ ঘণ্টা পর্যন্ত)। অ্যাপের "সব ডেটা ডাউনলোড" বোতামে ৪৭৮টির মধ্যে মাত্র ৭৭টি টেবিল - ওটা ব্যাকআপ নয়।
* **নতুন Supabase project-এ ফেরানো (সংক্ষেপে):** ১) নতুন project বানান ২) phase ফাইল ক্রমে paste করুন (`phase547` সহ) ৩) `backups` branch নামিয়ে `backup_crypto.py decrypt` ৪) `restore_accounts.py create` (আগে লগইন) ৫) `restore_backup.py --truncate` ও `psql` দিয়ে ডেটা ৬) `verify_restore.py` - **PASS** আসতে হবে ৭) `followups.sql` চালান ৮) প্রত্যেকের জন্য `restore_accounts.py reset-pin` - নতুন PIN (৪ থেকে ৬ সংখ্যা) ৯) `restore_storage.py` দিয়ে ছবি ১০) edge function ও secret আবার বসান ১১) অ্যাপের `config.js` নতুন project-এ দেখান, backup একবার চালিয়ে সবুজ দেখুন।
* **প্রতি মাসে পরীক্ষা:** লোকাল scratch ডাটাবেসে `restore_drill.py` ও `verify_restore.py` চালান (ধাপ ৬)। ফল `#/restoredrill`-এ লিখুন। ব্যর্থ হলে একই দিনে lead-কে জানান।
* **সতর্কতা:** ব্যাকআপ ব্যর্থ হলে GitHub-এ রান লাল হয়; ৩৬ ঘণ্টা ভালো ব্যাকআপ না থাকলে অ্যাপের ঘণ্টায় লাল চিহ্ন ও জরুরি মেইল আসে।
* **সততার কথা:** এখনো GitHub Actions-এ বা আসল Supabase-এ পরীক্ষা হয়নি; শুধু লোকাল PostgreSQL-এ নকল (test) ডেটা দিয়ে পরীক্ষা হয়েছে। প্রথম আসল রিস্টোরে ধাপ ৮-এর চেকলিস্ট মিলিয়ে চলুন।
