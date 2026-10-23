# SINGLE REPO: one repository, one branch, one published site

Written 23 Oct 2026. Status: **prepared locally, nothing pushed, nothing switched on.** Owner decision of 23 Oct 2026: there is ONE repository, `islamia-bos-app`, and its default branch will be `Main-Img`. Everything that used to live in `My-tools` is brought into it.

**বাংলা সারাংশ (সংক্ষেপে):**
- এখন থেকে একটাই repository: `islamia-bos-app`, আর তার মূল branch হবে `Main-Img`। `My-tools`-এর সব কাজ এখানে আনা হয়েছে, কিছু হারায়নি (প্রমাণ: `docs/NO_LOSS_REPORT_23OCT.md`)।
- সাইটে শুধু বানানো (build করা) web ফোল্ডার যাবে। SQL, docs, tests, tools, secret, আর `data/` ফোল্ডার কখনো সাইটে যাবে না।
- `Main-Img`-এ কিছু push হলে নিজে নিজে build হয়ে সাইট বদলায়। ভুল হলে আগের সবুজ run আবার চালালেই আগের সংস্করণ ফিরে আসে।
- নিচের CHECKLIST-এর সেটিংগুলো শুধু মালিক GitHub-এ বদলাতে পারেন। repository public থাকবে না private হবে, সেই সিদ্ধান্ত এখনো খোলা।

## 1. Repository layout

| Folder or file | What it is | Published on the site? |
|---|---|---|
| `web/` | The app: HTML, JS, CSS, `config.js` (public URL and publishable key only), `web/data/*.json` (word list, knowledge base, report registry). | **Yes, but only after `tools/build_web.sh` has built it** (minified, hashed file names). |
| `supabase/` | Every SQL phase file and its test. | **No.** |
| `docs/` | All guides, plans, decisions, paste order, generated paste parts and `setup-all.html`. | **No.** |
| `tests/` | SQL and web test suites. | **No.** |
| `tools/` | Build, check, backup and restore scripts. | **No.** |
| `data/` | Item dictionary and seed CSV files (the seed holds cost and price columns). | **No, never.** |
| `site/`, `android/` | Storefront package source and the Android wrapper. | **No** (not part of the Pages build). |
| `.github/workflows/` | CI checks, backup, notify, automation, and the new `pages.yml`. | No. |
| `CLAUDE.md` | Rules for every agent and contributor. | No. |

## 2. What is published and what is not

The workflow `.github/workflows/pages.yml` runs `bash tools/build_web.sh --out "$RUNNER_TEMP/site"`. That folder (about 212 files, 17 MB) is the only thing uploaded. Before the upload, `tools/check_pages_dist.py` refuses the build if it finds any of: a `.sql`, `.md`, `.csv`, `.env`, key or source-map file; a `tests`, `docs`, `supabase`, `tools`, `.github` or `.git` folder; a `data/` file that is not a `.json` that also exists in `web/data/`; a secret-looking value or a JWT; a conflict marker; a JavaScript syntax error; or a `config.js` whose URL, key or domain differs from `web/config.js`, or whose key is not a `sb_publishable_` key.

Not carried over automatically from the old public repository: the owner copy pages `setup-*.html`, `audit-a.html`, `PUBLISH_NOTES.md`, `DEPLOY_CHECKLIST.md`. They hold SQL text. In the single repo the SQL copy pages live in `docs/paste_parts/` and stay unpublished. OPEN OWNER QUESTION: if the owner wants to open the SQL copy page from the phone, it must be served from somewhere; decide this together with the visibility question (section 6).

## 3. Branch rules

- `Main-Img` is the only long-lived branch and becomes the default branch. Scheduled workflows (backup, notify, automation) only run from the default branch, so they start working only after the default branch is `Main-Img`.
- Work happens on short branches named by what they do (for example `fix-xyz`), merged into `Main-Img` after the checks pass. Never force-push `Main-Img`. History is kept in full (no squash of the imported history).
- Nothing is deleted without the owner's explicit yes (branches included). The old `My-tools` repository is left untouched until the owner says otherwise.
- Old SQL phase files are never edited. New SQL goes in a new phase file, safe to paste twice, new behaviour OFF by default (`CLAUDE.md`, `docs/BUILD-RULES.md`).

## 4. How a normal change becomes a published build

1. Change code on a branch. Run the local checks: `python3 tools/check_no_demo_leak.py` (must print OK) and the other checks listed in `docs/NO_LOSS_REPORT_23OCT.md`.
2. If web files changed, make sure `web/config.js` still holds only the public URL and publishable key.
3. Merge into `Main-Img` (a pull request is preferred).
4. The push to `Main-Img` starts the `pages` workflow: build, guard, upload, deploy. The run log prints the build id (a hash of the output; same id means same bytes).
5. Phones pick up the new files on their next open (file names carry the content hash, so old and new files are never mixed).
6. SQL is never published or run by the workflow. The owner pastes SQL by hand after review.

## 5. How to roll back

GitHub: Actions > `pages` > open the last run that was good > **Re-run all jobs**. It rebuilds that older commit and deploys it, so the site returns to the older build. Afterwards fix the problem on a branch and merge as usual. A rollback changes only the website; it never changes the database. (If a repository environment rule restricts which branches may deploy, re-running an old run still works because it runs on `Main-Img`.)

## 6. CHECKLIST: settings only the owner can change on GitHub

Nothing in this list has been done. Each item needs the owner's explicit yes.

- [ ] **Bring the content in.** The local branch `Main-Img` must first be pushed to `islamia-bos-app` by the owner or by an agent the owner has told to do it. The exact commands are in the final report of this task; they have not been run.
- [ ] **Default branch = `Main-Img`.** Repository Settings > Branches > Default branch > switch to `Main-Img`. Until then the backup, notify and automation schedules do not run from it.
- [ ] **Pages source = GitHub Actions.** Settings > Pages > Build and deployment > Source: **GitHub Actions** (the old setting is "deploy from a branch"). Optional: Settings > Environments > `github-pages` > restrict deployment branches to `Main-Img`.
- [ ] **Repository visibility (OPEN, not decided here).**
  - Also note (docs/SETUP.md): `supabase/schema.sql` and `data/items_seed.csv` contain cost prices; the SETUP note says to keep the repository private.
  - If **public**: anyone can read all source code, all SQL phase files, all docs (business processes, decisions, form codes, the rules list) and the history. The 12 Oct owner decision says costs and prices never go in a public repo; `data/items_seed.csv` carries cost and price columns, so a public repo is in conflict with it unless that file is removed from history first. The backup workflow and the automation workflow refuse to run in a public repository (by design), so **no automatic backup and no scheduled jobs while public**.
  - If **private**: the above is protected, but the Pages site then depends on the GitHub plan. UNVERIFIED: whether GitHub Pages from a private repository is available on the owner's plan, and the number of free Actions minutes (an older workflow comment says 2,000 per month for a private repo on the free plan; that was not re-checked on 23 Oct).
  - A middle way (also an owner decision): keep this repository private and publish the built site from a second, tiny public repository. That would again be two repositories, which the owner decided against; so it is listed only for completeness.
- [ ] **Secrets and variables** (Settings > Secrets and variables > Actions). The new `pages.yml` needs none. The other workflows need these, to be created only for the NEW Supabase project (values never go in chat, files or screenshots):
  - Secrets: `SUPABASE_URL`, `SUPABASE_ANON_KEY` (the publishable or anon key, never `service_role`), `BOT_EMAIL`, `BOT_PASSWORD`, `BACKUP_PASSPHRASE`, `BACKUP_KDF_SALT`; optional `NOTIFY_BOT_EMAIL`, `NOTIFY_BOT_PASSWORD`, `GMAIL_APP_PASSWORD`, `SMS_PROVIDER_URL`, `SMS_PROVIDER_TOKEN`, `GDRIVE_FOLDER_ID`, `GDRIVE_SERVICE_ACCOUNT_JSON` or `GDRIVE_OAUTH_TOKEN`, `GDRIVE_SHARED_DRIVE_ID`. The exact list per workflow is in `docs/OPS_SETUP.md`.
  - Variables: `APP_URL`, `AI_KB_REBUILD`, `X1_AUTOMATION_LIVE`, `SMS_SEND_ENABLED` (all optional, all off by default).
- [ ] **Actions are enabled** for the repository (Settings > Actions > General), with workflow permissions "Read repository contents" as the default; `pages.yml` asks for `pages: write` and `id-token: write` only in its deploy job.
- [ ] **Do not delete** `My-tools`, any branch, or the old Pages content until the new site has been checked on a phone and the owner says so.

## 7. Known limits of this design (honest list)

- UNVERIFIED: the exact action tags used in `pages.yml` (`actions/checkout@v4.2.2`, `actions/setup-node@v4.4.0`, `actions/configure-pages@v5.0.0`, `actions/upload-pages-artifact@v3.0.1`, `actions/deploy-pages@v4.0.5`). They were chosen from earlier releases known to be older than two weeks; GitHub could not be reached from the build machine to confirm each tag or its date. The first run will fail loudly if a tag does not exist. Pinning to a full commit SHA is the stronger option once the owner can look the tags up.
- `tools/build_web.sh` installs `terser` and `esbuild` with `npm` on a runner that does not have them (unpinned versions). The build id can therefore change if those tools change. This is the same behaviour as before; pinning them is a later task.
- The workflow has never run on GitHub. It was checked only as YAML and by building and guarding locally (build id `a8a8addc5e`, guard PASS).
- The old public site serves builds of older `My-tools` commits (for example `ed3bac3`). The first deploy from `Main-Img` will change the public site to the newest build. Check it on a phone before the old Pages setting is switched.
