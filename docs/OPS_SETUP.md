# স্বয়ংক্রিয় ব্যাকআপ ও জিমেইল নোটিফিকেশন - সেটআপ / Automatic backup and Gmail notifications - setup

এই গাইডটি ফোন থেকে করা যায়। প্রতিটি ধাপ বাংলা ও English-এ। / This guide can be done from a phone. Every step is in Bangla and English.

**কী পাবেন / What you get**
* প্রতি রাত ২:৩০-এ (ঢাকা) ডাটাবেসের পুরো কপি আপনার **প্রাইভেট** GitHub repo `mistybari99/My-tools`-এর `backups` branch-এ জমা হয়; প্রতিটি রান = একটি commit = একটি সংরক্ষিত ভার্সন। চাইলে Google Drive-এও কপি যায়।
  Every night at 02:30 (Dhaka) a full copy of the database is saved to the `backups` branch of your **private** repo `mistybari99/My-tools`; every run is one commit = one saved version. Optionally also copied to Google Drive.
* অ্যাপে ঘণ্টা-আইকন (নোটিফিকেশন), আর Gmail-এ জরুরি সতর্কতা (প্রতি ৩০ মিনিটে দেখে) ও দৈনিক সারাংশ (সকাল ৮টা, রাত ৯টা)।
  A bell in the app, and Gmail urgent alerts (checked every 30 minutes) plus a daily digest (08:00 and 21:00).
* কোনো মানুষ বা এই sandbox লাগে না: সব GitHub Actions-এ চলে। / No person and no sandbox is needed: everything runs on GitHub Actions.

**নিরাপত্তার নিয়ম / Safety rules (never break these)**
* গোপন তথ্য (পাসওয়ার্ড, key) শুধু GitHub Secrets-এ, আর কোথাও না - চ্যাটে, ফাইলে, ছবিতে নয়। / Secrets (passwords, keys) live only in GitHub Secrets - never in chat, files or screenshots.
* Supabase-এর `service_role` key **কখনো** ব্যবহার করা হয় না। শুধু `anon` (public) key আর আলাদা একটি "ops bot" ব্যবহারকারী। / The Supabase `service_role` key is **never** used. Only the `anon` (public) key and a separate "ops bot" user.
* ব্যাকআপে বিক্রি, খরচ, বেতন আছে - তাই repo অবশ্যই **Private** থাকবে; workflow public repo-তে চললে নিজে থেকেই থেমে যায়। এই ডাটা কখনো public repo `islamia-bos-app`-এ যাবে না। / The backup contains sales, costs and salaries, so the repo must stay **Private**; the workflow stops by itself if the repo is public. This data never goes to the public repo `islamia-bos-app`.

---

## ধাপ ১ - SQL পেস্ট করুন / Step 1 - Paste the SQL
**বাংলা:** Supabase -> আপনার project -> **SQL Editor** -> New query. `supabase/phase46.sql` ফাইলের পুরো লেখা কপি করে পেস্ট করুন -> **Run**. (phase 28 আগে চালানো থাকতে হবে। দুবার চালালেও ক্ষতি নেই।)
**English:** Supabase -> your project -> **SQL Editor** -> New query. Copy the whole of `supabase/phase46.sql`, paste, **Run**. (Phase 28 must have been run before. Running it twice is harmless.)

## ধাপ ২ - ops bot ব্যবহারকারী বানান / Step 2 - Create the ops bot user
**বাংলা:** Supabase -> **Authentication -> Users -> Add user -> Create new user**.
* Email: যেমন `backup-bot@yourname.com` (আপনার নিজের ডোমেইন/ইমেইল ধরনের ঠিকানা; আসল ইনবক্স না হলেও চলে)।
* Password: লম্বা, এলোমেলো (২৪+ অক্ষর)। Password manager-এ রাখুন।
* **Auto Confirm User** টিক দিন। -> Create user।
* এই ব্যবহারকারীকে অ্যাপে "অনুমোদন" করবেন না, কোনো role দেবেন না। Owner-কে কখনো bot বানাবেন না (সিস্টেম মানবে না)।
**English:** Supabase -> **Authentication -> Users -> Add user -> Create new user**. Email e.g. `backup-bot@yourname.com` (it does not have to be a real inbox). A long random password (24+ characters), kept in a password manager. Tick **Auto Confirm User**. Do NOT approve this user in the app and give it no role. The owner can never be the bot (the system refuses).
*(ঐচ্ছিক / optional)* ইমেইল পাঠানোর জন্য আলাদা দ্বিতীয় bot (`notify-bot@...`) বানালে নিরাপত্তা আরও ভালো। না বানালে একই bot দুটো কাজই করবে। / A second bot (`notify-bot@...`) for e-mail is slightly safer; without it the same bot does both jobs.

## ধাপ ৩ - bot-কে চিহ্নিত করুন / Step 3 - Mark it as an ops bot
**বাংলা:** SQL Editor-এ নিচেরটি চালান। `backup-bot` অংশটি আপনার bot-এর ইমেইলের `@`-এর আগের অংশ (staff id) দিয়ে বদলান।
**English:** In the SQL Editor run the lines below. Replace `backup-bot` with the part of the bot's e-mail before the `@` (its staff id).
```sql
insert into public.ops_accounts (user_id, purpose)
select id, 'backup' from public.profiles where staff_id = 'backup-bot'
on conflict (user_id, purpose) do update set active = true;

-- same bot also sends the e-mail (or use the second bot's staff id, e.g. 'notify-bot'):
insert into public.ops_accounts (user_id, purpose)
select id, 'notify' from public.profiles where staff_id = 'backup-bot'
on conflict (user_id, purpose) do update set active = true;

select user_id, purpose, active from public.ops_accounts;      -- must show your rows
```
**বাংলা:** বন্ধ করতে: `update public.ops_accounts set active = false where purpose = 'backup';`
**English:** To switch a bot off: `update public.ops_accounts set active = false where purpose = 'backup';`

## ধাপ ৪ - GitHub Secrets / Step 4 - GitHub Secrets
**বাংলা:** GitHub -> repo `mistybari99/My-tools` -> **Settings -> Secrets and variables -> Actions -> New repository secret**. নামগুলো হুবহু এভাবে লিখুন (বড় হাতের অক্ষর):
**English:** GitHub -> repo `mistybari99/My-tools` -> **Settings -> Secrets and variables -> Actions -> New repository secret**. Use exactly these names (capital letters):

| Secret name | বাংলা: কোথায় পাবেন / English: where to find it |
|---|---|
| `SUPABASE_URL` | Supabase -> Project Settings -> API -> **Project URL** |
| `SUPABASE_ANON_KEY` | same page -> **anon public** key. **NOT** `service_role`! / **NOT** the `service_role` key! |
| `BOT_EMAIL` | ধাপ ২-এর ইমেইল / the e-mail from step 2 |
| `BOT_PASSWORD` | ধাপ ২-এর পাসওয়ার্ড / the password from step 2 |
| `GMAIL_USER` | যে Gmail থেকে মেইল যাবে / the Gmail address that sends the mail |
| `GMAIL_APP_PASSWORD` | ধাপ ৫ / step 5 (16-character app password, not your Gmail password) |
| `MAIL_TO` | যাঁরা মেইল পাবেন, কমা দিয়ে (সর্বোচ্চ ১০) / recipients, comma separated (max 10) |
| `NOTIFY_BOT_EMAIL`, `NOTIFY_BOT_PASSWORD` | ঐচ্ছিক: দ্বিতীয় bot / optional: the second bot |
| `GDRIVE_*` | ঐচ্ছিক, নিচে "Google Drive" / optional, see "Google Drive" below |

ঐচ্ছিক **Variable** (Secret নয়): `APP_URL` = আপনার অ্যাপের ঠিকানা (মেইলের নিচে দেখাবে)। / Optional **Variable** (not a secret): `APP_URL` = your app address (shown at the bottom of the mails).

## ধাপ ৫ - Gmail app password / Step 5 - Gmail app password
**বাংলা:** Google Account -> **Security** -> **2-Step Verification** চালু করুন (না থাকলে app password হয় না) -> আবার Security -> **App passwords** -> নাম দিন `Islamia BOS` -> Create -> যে ১৬ অক্ষরের কোড দেখাবে (ফাঁকা ছাড়া) সেটি `GMAIL_APP_PASSWORD` secret-এ বসান। সাধারণ Gmail পাসওয়ার্ড দেবেন না।
**English:** Google Account -> **Security** -> turn on **2-Step Verification** (app passwords need it) -> Security -> **App passwords** -> name it `Islamia BOS` -> Create -> put the 16-character code (without spaces) into the `GMAIL_APP_PASSWORD` secret. Never use your normal Gmail password. Revoke it any time from the same page.

## ধাপ ৬ - Default branch (খুব জরুরি) / Step 6 - Default branch (very important)
**বাংলা:** GitHub-এর নিয়ম: **schedule (সময়মতো চলা) workflow শুধু repo-র DEFAULT branch থেকে চলে।** তাই `.github/workflows/backup.yml` ও `notify.yml` দুটোই My-tools-এর default branch-এ থাকতে হবে। কোনটা default দেখতে: Settings -> Branches। ফাইল দুটি default branch-এ merge করুন (Pull request -> Merge), অথবা lead-কে বলুন, তিনি চাইলে করে দেবেন। না করলে কিছুই নিজে চলবে না (হাতে "Run workflow" চালানো যাবে না)।
**English:** GitHub rule: **scheduled workflows only run from the repository's DEFAULT branch.** So both `.github/workflows/backup.yml` and `notify.yml` must be on the default branch of My-tools. See which one it is under Settings -> Branches. Merge the two files into the default branch (Pull request -> Merge) or ask the lead, who will do it when asked. Until then nothing runs by itself (and "Run workflow" by hand will not even list them).

## ধাপ ৭ - একবার হাতে চালিয়ে দেখুন / Step 7 - Run each once by hand
**বাংলা:** repo -> **Actions** -> বাঁ দিকে **backup** -> **Run workflow** -> Run। ২-৫ মিনিটে সবুজ টিক আসা উচিত। তারপর **notify** -> Run workflow -> প্রথমে **dry_run** টিক দিয়ে চালান (মেইল যাবে না, লগে দেখাবে); ঠিক লাগলে dry_run ছাড়া আবার চালান, আর "digest" টিক দিলে সারাংশ-মেইলও যাবে।
**English:** repo -> **Actions** -> **backup** on the left -> **Run workflow** -> Run. A green tick should come in 2-5 minutes. Then **notify** -> Run workflow -> first with **dry_run** ticked (no mail is sent, the log shows it); if it looks right run again without dry_run, and tick "digest" to also get the summary mail.

## ব্যাকআপ কোথায় দেখবেন / Where to see the backups
**বাংলা:** repo -> branch বদলে **backups** বেছে নিন (ফোনে: "Code" ট্যাব -> branch নাম -> backups)। ভিতরে:
* `latest/` - সবসময় সর্বশেষ কপি (প্রতি টেবিলের `<table>.ndjson.gz`, `manifest.json`, ছবি `photos/`)
* `2026/10/14/` - সেই দিনের কপি (বছর/মাস/তারিখ, ঢাকা সময়)
* **Commits** তালিকা = সব ভার্সন। message: `backup 2026-10-14 02:31 rows=12345`। পুরনো ভার্সন দেখতে commit খুলে "Browse files"।
* `manifest.json`-এ প্রতি টেবিলের সারি-সংখ্যা ও sha256 আছে। অ্যাপে **নোটিফিকেশন** পেজে "স্বয়ংক্রিয় ব্যাকআপ" কার্ডে শেষ সফল রান ও ঘণ্টা দেখায়; ৩৬ ঘণ্টার বেশি পুরনো হলে (বা ব্যর্থ হলে) লাল নোটিফিকেশন ও জরুরি মেইল আসে।
**English:** repo -> switch the branch to **backups**. Inside: `latest/` (always the newest: one `<table>.ndjson.gz` per table, `manifest.json`, `photos/`), `YYYY/MM/DD/` (that day's copy, Dhaka date), and the **commit list** = every saved version (`backup 2026-10-14 02:31 rows=12345`; open a commit -> "Browse files" for an old version). `manifest.json` has the row count and sha256 of every table. In the app, **Notifications -> Automatic backup** shows the last good run; if it is older than 36 hours (the rule `backup_max_age_hours`) or failed, a red notification and an urgent mail arrive.
Unchanged tables produce identical files, so the repo grows only by real changes.

## নোটিফিকেশন / Notifications
**বাংলা:** অ্যাপে ঘণ্টা-আইকন প্রতি ৬০ সেকেন্ডে সংখ্যা দেখে। কী কী জানাবে (লাল এক্সেপশন অনেকক্ষণ খোলা, অনুমোদন বাকি, কম স্টক, মেয়াদ শেষ হতে চলা, সরবরাহকারীর বকেয়া, গ্রাহকের বাকির সীমা, দিন-শেষ জমা হয়নি, অপচয় হঠাৎ বেশি, বড় ক্যাশ কম/বেশি, পাশাপাশি মাসের সিদ্ধান্ত, ব্যাকআপ পুরনো/ব্যর্থ) তার প্রতিটির চালু/বন্ধ সুইচ **সুইচবোর্ডে (#/switchboard)**। সংখ্যার সীমা (যেমন ২৪ ঘণ্টা, ৫০০ টাকা) rules টেবিলে; SQL Editor-এ: `update public.rules set value = '800'::jsonb where key = 'notify_cash_limit';`। দিন-শেষের সময়: `update public.rules set value = '"22:30"'::jsonb where key = 'day_close_deadline';`। ইমেইল বন্ধ: `update public.rules set value = 'false'::jsonb where key = 'notify_email_on';`। (ডিফল্টে ফেরাতে `value = null`।)
**English:** The bell in the app reads its number every 60 seconds. Every kind (red exceptions open too long, approvals waiting, low stock, expiring batches, overdue supplier dues, customer credit limit, day-close not submitted, wastage spike, big cash short/over, parallel-month decision, backup stale/failed) has an ON/OFF switch in the **Switchboard (#/switchboard)**. Number limits (24 hours, 500 taka ...) are rules; in the SQL Editor: `update public.rules set value = '800'::jsonb where key = 'notify_cash_limit';`, deadline `update public.rules set value = '"22:30"'::jsonb where key = 'day_close_deadline';`, e-mail off `update public.rules set value = 'false'::jsonb where key = 'notify_email_on';` (`value = null` = back to the default). Digest hours: rule `notify_digest_times` = `off`, `08`, `21` or `08,21`. The 08:00 mail reports yesterday, the 21:00 mail reports today.

## ব্যাকআপ থেকে ফেরত আনা / How to restore
**নতুন:** নতুন Supabase project-এ পুরো ধাপে ধাপে ফেরানো, লগইন, PIN, ছবি, মাসিক পরীক্ষা ও চেকলিস্ট এখন `docs/BACKUP_AND_RESTORE_GUIDE.md`-এ; কী ব্যাকআপে আছে/নেই `docs/BACKUP_COVERAGE.md`-এ। নিচের লেখা পুরনো ছোট সংস্করণ। / **New:** the full step-by-step restore into a NEW Supabase project (logins, PINs, photos, monthly test, checklist) is in `docs/BACKUP_AND_RESTORE_GUIDE.md`; what is and is not saved is in `docs/BACKUP_COVERAGE.md`. The text below is the older short version.
**বাংলা:**
1. repo-র `backups` branch **Download ZIP** করুন (Code -> Download ZIP, branch backups), অথবা কম্পিউটারে `git clone --branch backups --single-branch https://github.com/mistybari99/My-tools.git backups`। যে তারিখের ভার্সন চান সেই commit/ফোল্ডার ব্যবহার করুন (`latest/` অথবা `2026/10/14/`)।
2. কোড branch থেকে `tools/restore_backup.py` নিন। কম্পিউটারে (Python 3):
   `python3 tools/restore_backup.py backups/latest --dry-run` - শুধু টেবিল ও সংখ্যা দেখায়, কিছু লেখে না। ফাইল নষ্ট হলে এখানেই ধরা পড়ে।
   `python3 tools/restore_backup.py backups/latest --out restore.sql` - SQL ফাইল বানায় (বড় হলে restore.part01.sql, part02 ... ক্রমে)।
3. Supabase **SQL Editor**-এ ফাইলগুলো **ক্রমে** পেস্ট করে Run করুন (একটি ফাইল = একটি transaction)। কোনো database-এ সরাসরি ঢোকার দরকার নেই।
4. দুটি ধরন: (ক) ডিফল্ট - শুধু যা নেই সেই সারিগুলো যোগ হয়, আগের কিছু বদলায় না। (খ) `--truncate` - নতুন, ফাঁকা কপিতে সবকিছু হুবহু ফিরিয়ে আনতে; আগে সব টেবিল খালি করে (**বিপজ্জনক**: শুধু নতুন project-এ, phase SQL চালানোর পরে)। append-only টেবিলের (audit_log ইত্যাদি) পাহারা শুধু ওই মুহূর্তের জন্য বন্ধ হয়ে আবার আগের মতো চালু হয়।
5. **একই Supabase project**-এ ফেরান, অথবা নতুন project-এ আগে একই `id` দিয়ে লগইন-ব্যবহারকারী বানান: লগইন তথ্য (Authentication users) ব্যাকআপে নেই (Supabase নিজে রাখে)। ছবি Storage থেকে: `photos/` ফোল্ডার bucket `photos`-এ আবার আপলোড করুন।
6. তারপর অ্যাপে দেখুন: টেবিল-সংখ্যা মিলিয়ে নিন (`manifest.json`)।
**English:**
1. **Download ZIP** of the `backups` branch (Code -> Download ZIP, branch backups) or on a computer `git clone --branch backups --single-branch https://github.com/mistybari99/My-tools.git backups`. Use `latest/` or a dated folder / an older commit for an older version.
2. Take `tools/restore_backup.py` from the code branch. On a computer with Python 3: `python3 tools/restore_backup.py backups/latest --dry-run` (prints the tables and counts, writes nothing, refuses a damaged backup: every file is checked against sha256 and row count), then `python3 tools/restore_backup.py backups/latest --out restore.sql` (it makes `restore.part01.sql`, `part02` ... when big).
3. Paste the files **in order** into the Supabase **SQL Editor** and Run (one file = one transaction). No direct database access is needed.
4. Two modes: default adds only the rows that are missing and changes nothing existing; `--truncate` empties every restored table first and is for a **new copy** whose phase SQL you just ran (**destructive**). The append-only / no-delete guards are switched off for that moment only and put back exactly as they were. The restore turns off foreign-key checks (`session_replication_role = replica`), so the order of tables does not matter. Serial counters are moved past the highest restored id.
5. Restore into the **same Supabase project**, or first create the login users with the same ids in a new project: the login accounts (Authentication users) are not in the dump (Supabase keeps them). Photos: upload the `photos/` folder into the bucket `photos` again.
6. Check the table counts against `manifest.json`.
Tested: a full dump of a 91-table test database restored into a fresh copy gave identical content in every table.

## bot-এর পাসওয়ার্ড বদলানো / Rotating the bot password
**বাংলা:** Supabase -> Authentication -> Users -> bot -> user-এর মেনু -> পাসওয়ার্ড বদলান (নতুন লম্বা পাসওয়ার্ড দিন) -> GitHub -> Settings -> Secrets -> `BOT_PASSWORD` (এবং `NOTIFY_BOT_PASSWORD` থাকলে) **Update** -> Actions-এ backup একবার Run করে সবুজ দেখুন। সন্দেহ হলে (ফোন হারালে, secret ফাঁস হলে) আগে bot বন্ধ করুন: `update public.ops_accounts set active = false;` তারপর পাসওয়ার্ড বদলান, তারপর `active = true`। Gmail app password বদলাতে: Google Account -> App passwords -> পুরনোটি Revoke, নতুন বানিয়ে `GMAIL_APP_PASSWORD` Update।
**English:** Supabase -> Authentication -> Users -> the bot -> its menu -> change the password (a new long password) -> GitHub -> Settings -> Secrets -> **Update** `BOT_PASSWORD` (and `NOTIFY_BOT_PASSWORD` if you use it) -> run the backup workflow once and check it is green. If you suspect a leak (lost phone, exposed secret) first switch the bot off with `update public.ops_accounts set active = false;`, change the password, then set `active = true` again. For Gmail: Google Account -> App passwords -> Revoke the old one, make a new one, Update `GMAIL_APP_PASSWORD`.

## Google Drive (ঐচ্ছিক / optional)
**বাংলা:** `GDRIVE_FOLDER_ID` এবং (`GDRIVE_SERVICE_ACCOUNT_JSON` অথবা `GDRIVE_OAUTH_TOKEN`) - এই secret-গুলো থাকলেই backup workflow শেষে rclone দিয়ে Drive-এও কপি করে; না থাকলে ধাপটি নিজে বাদ যায়। দুটি পথ:
* **পথ ক - Service account:** Google Cloud Console -> নতুন project -> "Google Drive API" Enable -> IAM -> Service Accounts -> Create -> Keys -> Add key -> JSON (ফাইলটির পুরো লেখা `GDRIVE_SERVICE_ACCOUNT_JSON` secret)। Drive-এ একটি ফোল্ডার বানিয়ে service account-এর ইমেইলের (`...@...iam.gserviceaccount.com`) সঙ্গে **Editor** হিসেবে share করুন; ফোল্ডারের ঠিকানার শেষ অংশ (`/folders/<এইটা>`) = `GDRIVE_FOLDER_ID`। সতর্কতা: service account-এর নিজের কোটা নেই, সাধারণ My Drive-এ আপলোড ব্যর্থ হতে পারে; তখন **Shared Drive** (Workspace) ব্যবহার করুন এবং তার id `GDRIVE_SHARED_DRIVE_ID` secret-এ দিন, নয়তো পথ খ।
* **পথ খ - OAuth token (ব্যক্তিগত Drive-এর জন্য সহজ):** কম্পিউটারে rclone ইনস্টল করে `rclone authorize "drive"` চালান, ব্রাউজারে আপনার Google অ্যাকাউন্টে অনুমতি দিন, শেষে যে `{"access_token":...}` JSON আসে সেটি `GDRIVE_OAUTH_TOKEN` secret; `GDRIVE_FOLDER_ID` = আপনার ফোল্ডারের id। (এই token দিয়ে সেই Drive-এ ঢোকা যায় - Secret-এর বাইরে কোথাও রাখবেন না।)
**English:** If `GDRIVE_FOLDER_ID` and (`GDRIVE_SERVICE_ACCOUNT_JSON` or `GDRIVE_OAUTH_TOKEN`) exist, the backup workflow also copies the dump (and the photos) to Drive with rclone at the end; otherwise that step is skipped. Two ways:
* **A - Service account:** Google Cloud Console -> new project -> enable "Google Drive API" -> IAM -> Service Accounts -> Create -> Keys -> Add key -> JSON; paste the whole file into the secret `GDRIVE_SERVICE_ACCOUNT_JSON`. In Drive create a folder and share it with the service account's e-mail (`...@...iam.gserviceaccount.com`) as **Editor**; the last part of the folder URL (`/folders/<this>`) is `GDRIVE_FOLDER_ID`. Caution: a service account has no storage quota of its own, so uploads into an ordinary My Drive can fail; then use a **Shared Drive** (Workspace) and put its id in the secret `GDRIVE_SHARED_DRIVE_ID`, or use way B.
* **B - OAuth token (simplest for a personal Drive):** on a computer install rclone and run `rclone authorize "drive"`, allow access in the browser, and paste the `{"access_token":...}` JSON it prints into the secret `GDRIVE_OAUTH_TOKEN`; `GDRIVE_FOLDER_ID` = your folder id. (That token opens your Drive: keep it only in the Secret.)
Photos bigger than 80 MB in total are not put in git; with Drive set up they go to Drive only (`photos/` folder), without Drive they are listed in `photos_manifest.json` as "not copied".

## পুরনো ভার্সন ছাঁটাই / Pruning old versions
**বাংলা:** ছাঁটাই নিজে থেকে হয় না: ইতিহাসই ভার্সন-ভাণ্ডার। repo ছোট রাখতে চাইলে (বছরে একবার, কম্পিউটারে; আগে `backups` ফোল্ডার আলাদা জায়গায় কপি রাখুন):
**English:** Pruning is NOT automatic: the history is the version store. To shrink the repo (about once a year, on a computer; copy the folder somewhere safe first):
```bash
git clone --branch backups --single-branch https://github.com/mistybari99/My-tools.git bk && cd bk
# keep only the newest state as one fresh commit (all older versions are dropped!)
git checkout --orphan fresh && git add -A && git commit -m "backup history pruned $(date +%F)"
git push --force origin fresh:backups
```
Old dated folders can also be deleted in a normal commit (this keeps history, so it does not shrink the repo). Run `git gc` locally. After a force-push GitHub keeps the old data for a while until it garbage-collects.

## কী সুরক্ষিত নয় / What is NOT protected
* **ছবি (Storage `photos`)** ডাটাবেস-ডাম্পে নেই। `tools/backup_photos.py` ব্যাকআপ-bot-এর পড়ার অনুমতি দিয়ে সেগুলো `latest/photos/`-এ কপি করে (নতুনগুলো শুধু; আগেরগুলো আবার নামে না)। / **Photos (Storage `photos`)** are not in the database dump. `tools/backup_photos.py` copies them to `latest/photos/` (only new ones) using the bot's read-only access to that bucket.
* **লগইন অ্যাকাউন্ট ও পাসওয়ার্ড** (Supabase Auth) ব্যাকআপে নেই; লগইন ডেটা (`login_failures`, `login_attempts`) ও PIN/secret-ধরনের কলামওয়ালা টেবিলও বাদ। / **Login accounts and passwords** (Supabase Auth) are not in the backup; login-attempt tables and any table with a password/PIN/secret column are excluded.
* Supabase project-এর সেটিংস, Edge function, public schema-র বাইরের কিছু। এগুলো কোড repo-র SQL ফাইলে আছে। / Supabase project settings and anything outside schema `public`. The SQL files in the code repo rebuild the structure.
* **শেষ ব্যাকআপের পরের পরিবর্তন** (সর্বোচ্চ প্রায় ২৪ ঘণ্টা)। বেশি চাইলে `backup.yml`-এর cron আরও ঘনঘন করুন। / **Changes after the last backup** (up to about 24 hours). Make the cron in `backup.yml` more frequent for less.
* GitHub বা আপনার Google/GitHub অ্যাকাউন্ট হারালে ব্যাকআপও যায়: দুটোতে 2-Step চালু রাখুন, আর মাঝে মাঝে Drive কপিও রাখুন। / If you lose your GitHub account the backup goes too: keep 2-step verification on, and use the Drive copy as a second place.

## সমস্যা হলে / Troubleshooting
| লক্ষণ / Symptom | কারণ ও সমাধান / Cause and fix |
|---|---|
| `not allowed` (backup/notify) | bot ধাপ ৩-এ চিহ্নিত নয় বা `active = false`; অথবা ভুল purpose। / the bot is not marked in step 3, is inactive, or has the wrong purpose. |
| login `400 invalid_grant` | পাসওয়ার্ড/ইমেইল ভুল, বা user "Auto Confirm" হয়নি। / wrong password or e-mail, or the user was not auto-confirmed. |
| `table_not_allowed` | টেবিলটি whitelist-এ নেই (ইচ্ছাকৃত, উপরে দেখুন)। / the table is not in the whitelist (by design). |
| `dumped N rows but the server counted ...` | ডাম্প চলার সময় সারি হারিয়েছে বা কেউ মুছেছে: ব্যাকআপ ব্যর্থ ধরা হয়, আবার চালান। / rows vanished while dumping: the run counts as failed; run again. |
| push rejected | repo-র Actions অনুমতি: Settings -> Actions -> General -> Workflow permissions -> "Read and write". / Settings -> Actions -> General -> Workflow permissions -> "Read and write". |
| "This repository is not private" | repo Private করুন (Settings -> Danger zone)। / make the repo Private. |
| মেইল আসে না / no mail | `GMAIL_APP_PASSWORD` ভুল বা 2-Step বন্ধ; `MAIL_TO` ভুল; সুইচবোর্ডে `notify_email_on` বন্ধ; Spam দেখুন; `notify` workflow-র লগ খুলুন। / wrong app password or 2-step off; wrong `MAIL_TO`; `notify_email_on` off in the Switchboard; check Spam; open the `notify` workflow log. |
| কিছুই নিজে চলে না / nothing runs by itself | ধাপ ৬: workflow ফাইল default branch-এ নেই; অথবা ৬০ দিন repo-তে কোনো কাজ না হলে GitHub schedule বন্ধ করে দেয় (Actions-এ "Enable workflow")। / step 6: the files are not on the default branch; or GitHub pauses schedules after 60 days without repo activity (press "Enable workflow"). |
| Actions মিনিট শেষ / minutes used up | `notify.yml`-এর প্রথম cron ঘণ্টায়-একবার করুন (ফাইলের মাথায় লেখা আছে)। Private repo-তে ফ্রি প্ল্যানে মাসে ২,০০০ মিনিট। / make the first cron in `notify.yml` hourly (noted at the top of the file). Free plan: 2,000 minutes a month on a private repo. |

## ডেভেলপারদের জন্য / For developers
* কোড: `supabase/phase46.sql` (+ `phase46_test.sql`), `web/notifications.js` (+ `tests/web/notifications_test.js`), `tools/ops_common.py`, `backup_dump.py`, `backup_photos.py`, `notify_digest.py`, `restore_backup.py`, `test_ops.py`, `.github/workflows/backup.yml`, `notify.yml`। রেজিস্ট্রেশন: `docs/regs/notifications.md`।
* Python পরীক্ষা (নেটওয়ার্ক ছাড়া, নকল সার্ভারে): `python3 tools/test_ops.py -v`। আসল Postgres-এ restore পরীক্ষা: ফাঁকা db বানিয়ে `BOS_PG_RESTORE_DB=<db> python3 tools/test_ops.py`।
* মেইল না পাঠিয়ে দেখতে: `python3 tools/notify_digest.py --dry-run --mode digest` (env: SUPABASE_URL, SUPABASE_ANON_KEY, BOT_EMAIL, BOT_PASSWORD)। dry-run কেবল পড়ে: scan চালায় না, mark করে না, পাঠায় না।
* Python code and tests: `python3 tools/test_ops.py -v` (fake Supabase + stub SMTP, no network). Real-Postgres restore test: create an empty db and run `BOS_PG_RESTORE_DB=<db> python3 tools/test_ops.py`.
* `--dry-run` only reads: it does not scan, mark or send.
