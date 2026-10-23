# DESIGN ROADMAP: বাকি সব ডিজাইনের কাজ, ক্রমে

Status: design only. Date: 21 Oct 2026. Branch: `claude/supabase-readonly-audit-xo3qkp`. Companion: `docs/DESIGN_TWO_STATE_LAYOUT.md`.
Sources read [code]/[doc]: `docs/HANDOFF.md`, `docs/NUMBERING.md`, `docs/IA_RULES.md`, `docs/IA_CONCEPT.md`, `docs/ARCHITECTURE_DESIGN.md`, `docs/DEMAND_VERIFY.md`, `docs/DESIGN_SYSTEM.md`, `docs/LANGUAGE.md`, `web/ia.js`, `web/nav.js`, `web/switchboard.js`, `web/optviews.js`, `web/theme_glass.css`, `tools/numbering_map.json`, `tools/apply_owner_words.py`.

## বাংলা সারাংশ

- এই ফাইলে ডিজাইনের বাকি সব কাজ ক্রমানুযায়ী আছে: (১) দুই-স্টেট লেআউট, (২) প্রধান ফিচার দেখানো/লুকানোর মডেল, (৩) ফর্মের ক্রম ও ছোট নাম, (৪) Home ও মেনু গোছানো, (৫) গ্লাস থিম মেলানো, (৬) খালি/লোডিং/ভুলের পাতা, (৭) বাংলা লেখার নিয়ম, (৮) ৩৬০px নিয়ম।
- প্রধান ফিচার দেখানো/লুকানো আপনি পরে ঠিক করবেন। আমাদের সুপারিশ: ডিফল্টে সব দেখা যাবে (বন্ধ থাকলে "বন্ধ" চিহ্ন)। এক সুইচ ঘুরিয়ে আগের মতো লুকানো যাবে, আবার ফেরানো যাবে।
- ছাপা ফর্মের কোড আমরা একটাও বদলাইনি। ৪২টি ফর্মের ছোট নামের তালিকা দেওয়া হলো। আপনার মাত্র একটি সিদ্ধান্ত লাগবে: "কোড যেমন আছে তেমন রাখুন (সুপারিশ)" নাকি "ফাঁকা নম্বর ভরাট করুন"।
- মিষ্টির ব্যবসা আগে; অন্য ব্যবসার পাতা আলাদা থাকবে, মিষ্টির মেনুতে আসবে না।
- সব কাজ ছোট ধাপে, প্রতি ধাপে পরীক্ষা, কোনো ডেটা মুছে না।

---

## 0. Order and dependencies

| # | Item | Needs owner approval? | Needs SQL paste? | Depends on |
|---|---|---|---|---|
| 1 | Two-state layout | No (decided) | Yes, phase 540 for the snapshot part | R8 fix first |
| 2 | Main-feature show/hide model | No for the default; later he may flip it | Rule only (phase 540) | 1 (step 1-3) |
| 3 | Form-code sequence and shortcut names | **One approval** | No (aliases are web data) | none |
| 4 | Home and drawer IA polish | No | No | 2 |
| 5 | Theme consistency (glass/premium) | No | No | none |
| 6 | Empty, loading, error state standard | No | No | none |
| 7 | Bangla copy standard | Word list already given by owner | No | none |
| 8 | 360 px rules | No | No | none |

Items 5 to 8 are standards: they are checked on every screen as a checklist in the definition of done, then fixed screen by screen when the screen is next touched (no big-bang restyle, because of `docs/UI_NO_LOSS_RULE.md` and the 11,081-item inventory guard).

Standing rules for every item: no demo or invented data; printed form codes unchanged without approval; sweets business first, other businesses separate; new behaviour OFF or safe by default; routes, aliases and favourites never renamed or removed (`docs/IA_RULES.md`); owner is not asked questions, the roadmap records the decision and the reason.

---

## 1. Two-state layout

Full design: `docs/DESIGN_TWO_STATE_LAYOUT.md`. Summary of decisions: layout covers three show-only parts (`todo_on`, `shift_on`, `announce_on`); saved default is the owner's own state, auto-saved on the server before the first change; atomic apply and revert with a diff sheet and undo; per business; owner only; no PIN. Build in 10 small steps, first step is the R8 fix in `web/ia.js`.

---

## 2. Main-feature show/hide model (the later owner decision)

### 2.1 Problem

Owner: main features must be visible at their proper place; only inner settings start OFF; showing or hiding whole main features is decided LATER. So the system must support both outcomes today and make the switch between them cheap and reversible.

### 2.2 The model: three independent layers

| Layer | Question | Controlled by | Default | Reversible |
|---|---|---|---|---|
| Allowed | May this person use it? | grants and RLS on the server | per role | yes (owner) |
| Placed | Is it shown at its place? | `ia_show_off_features` (business) and `optviews` Show/Hide/Locked (person or role) | Show | yes |
| Enabled | Is the feature switch ON? | the rule row (Switchboard, Layout card, feature-off card) | OFF for optional parts | yes |

A hidden or locked screen never grants or removes permission (`web/optviews.js` header rule). The server remains the authority.

### 2.3 Options considered

| Option | Behaviour | For | Against |
|---|---|---|---|
| P1 Show all permitted, mark OFF ones | every main feature in its group; OFF ones carry a "বন্ধ" chip and open an explainer | matches owner intent (a); discoverable; staff know the feature exists | slightly longer menus; a tap leads to an explainer |
| P2 Hide while OFF (today for 3 screens) | menu shows only enabled features | short menu | owner cannot find features (the reason R8 is PARTIAL); contradicts intent (a) |
| P3 Hide by business type | menu shows only features the business template needs | sweets menu is clean; other trades separate | needs the template mapping; wrong mapping hides a needed screen |

### 2.4 Recommended default (decided)

**P1 plus P3 for other-trade screens only.**

1. Every main feature a role is allowed to use is placed in its group, whether or not its switch is ON. OFF ones show the chip and the feature-off card. This is rule `ia_show_off_features`, default ON.
2. The five other-trade screens (`impexp`, `variants`, `cheques`, `schemes`, `tinting`, `web/ia.js` 190-194) are placed only when the active business's template needs them. Mapping is data (a small table in `web/ia.js` keyed by `org_units.template_code`, `supabase/phase122.sql`), default: shown only for a business whose template lists them; in the sweets business they are not placed. Owner can still open them by direct link and from the Switchboard "all screens" list while `org_scope_on` is OFF (single business, no template known): rule `ia_trade_screens` choice `auto | show | hide`, default `auto`; `auto` with no template = hide the five (the sweets business is the only live business).
3. Per-person or per-role Hide stays in `optviews` ("কে কী দেখবে"). No new UI for that.

Reason: the owner said features must be visible and that other businesses stay separate. P1 serves the first, P3 serves the second, and each is one switch.

### 2.5 How to flip it later (reversible, no data change)

| Owner's later choice | Do this | Undo |
|---|---|---|
| "Hide the off ones" (short menu) | `ia_show_off_features` = OFF | set ON |
| "Show other-trade screens" | `ia_trade_screens` = `show` | `auto` |
| "Hide feature X for the cashier role only" | `optviews` Role defaults: X = Hide | Show |
| "Hide feature X for everyone" | `optviews` Role defaults for every role: X = Hide (button "সব রোলে লুকান" added to the optviews row in a later step) | button "সব রোলে দেখান" |
| "Hide a group" | not offered: groups always show if any child shows | none |

Each flip is audited by `set_rule` / `optviews` as today and takes effect on the next menu draw (no reload instruction).

### 2.6 Build steps

1. R8 fix, chip, feature-off card (same as layout steps 1-3).
2. Rule `ia_show_off_features` in phase 540 (with info entry) and the read in `ia.js` (absent = ON).
3. Trade-screen gating table and `ia_trade_screens` (phase 541 outline, own file, rule + info entry).
4. Tests: placed in sweets, absent in sweets for the five, present when the template lists them, direct link still opens, flips both ways.

Files: `web/ia.js`, `web/nav.js`, `web/optviews.js` (button only), `web/i18n.js`, `web/data/info.json`, `supabase/phase540.sql`, `supabase/phase541.sql` and their tests, `tests/web/layout_test.js`, `tests/web/ia_test.js`.

---

## 3. Form-code sequencing and shortcut names (needs ONE owner approval)

> **Superseded (23 Oct 2026).** The owner approved the sorted form-code sequence (Option B, A-Z by English short name, `NN-1`) on 21 Oct 2026 and it was applied (phase 543). The rule is `docs/FORM_SEQUENCE.md`; change a code only through `tools/renumber.py` and a numbered phase. The text below is the earlier proposal.


### 3.1 Facts

- 42 paper forms in 12 groups (`docs/ARCHITECTURE_DESIGN.md` 5.8). Codes are the kit's numbers.
- `docs/LANGUAGE.md` section 5 says the kit's number never changes. `docs/NUMBERING.md` section 1 says printed codes are not printed yet, so they can change **only after owner approval**; `tools/numbering_map.json` `form_groups_approved` is `false`. The map proposes closing gaps: 08→07, 10→08, 11→09, 14→10, 18→11, 20→12 (groups 01 to 06 unchanged).
- Nothing in this roadmap changes any printed code. `tools/renumber.py` stays refused until the flag is true.

### 3.2 Options

| Option | What changes | Risk |
|---|---|---|
| **A (recommended): keep every code, add short names and a display order** | No code changes. A short name (1-2 words) and a display order are added as search aliases and a sort order in the app | none for paper; the sequence 01..06, 08, 10, 11, 14, 18, 20 has gaps, which is how the kit is; no one has to relearn anything |
| B: close the gaps with the existing map | six group prefixes change on paper and in the app | the guidebook, training, any already-filled book, and the "Form number" field of old entries use the old codes; a mixed period; every doc and test referencing codes changes; `check_ui_inventory` baseline must be re-based |

Decision: recommend **A**. Reason: the form code is the one identifier shared by the paper book, staff memory and the database; a gap in numbering costs nothing, a changed number costs everyone. A gives the "easy to remember" benefit through short names, which is what the owner wanted ("short names").

**The one approval the owner needs to give:** choose A (nothing else is required; the agent proceeds) or B (then set `form_groups_approved` true and run the 9-step procedure in `docs/NUMBERING.md` section 3). If the owner gives no answer, A applies automatically and `form_groups_approved` stays `false`.

### 3.3 Display order (for lists and the form picker)

Order by the daily flow, not by code: Sell counter (14, 20) → Goods (04, 03, 06, 08) → Make (05) → Money (10, 18) → People (02, 11) → Reports (01) → Setup (0-1). Within a group by code. This is a sort key in the form list only; the code never moves.

### 3.4 Proposal table: 42 forms (code unchanged, short name added)

Short name = what the owner's staff would say or type in the search box (alias). Bangla in the owner's word style. Job text comes from `docs/ARCHITECTURE_DESIGN.md` 5.8; the table adds only the alias.

| Code (unchanged) | Short name EN | সংক্ষিপ্ত নাম বাংলা |
|---|---|---|
| 14-1 | Close day | দিন শেষ |
| 14-2 | Jalebi counter | জিলাপি কাউন্টার |
| 20-1 | Order | অর্ডার |
| 20-2 | Discount | ডিসকাউন্ট |
| 20-3 | Return | ফেরত |
| 20-4 | Party invoice | পার্টি ইনভয়েস |
| 20-5 | Party ledger | পার্টি খাতা |
| 20-6 | Online money | অনলাইনের টাকা |
| 03-1 | Send stock | স্টক পাঠান |
| 04-1 | Receive goods | মাল গ্রহণ |
| 04-2 | Issue | মাল দেওয়া |
| 04-3 | Stock count | স্টক গণনা |
| 04-4 | Store ledger | স্টোর খাতা |
| 08-1 | Repair | মেরামত |
| 06-1 | Ask to buy | কেনার অনুরোধ |
| 06-2 | Compare quotes | দাম তুলনা |
| 06-3 | Order supplier | সরবরাহকারীকে অর্ডার |
| 06-4 | Pay request | বিল ও পেমেন্ট |
| 06-5 | Supplier ledger | সরবরাহকারীর খাতা |
| 05-1 | Factory day | কারখানার দিন |
| 05-2 | Product spec | পণ্যের বিবরণ |
| 05-3 | Recipe | রেসিপি |
| 05-4 | Yield test | ফলন পরীক্ষা |
| 05-5 | New product | নতুন পণ্য |
| 10-1 | Cash to hub | ক্যাশ জমা |
| 10-2 | Expense | খরচ |
| 10-3 | Digital payments | ডিজিটাল পেমেন্ট মেলানো |
| 10-4 | Cash position | ক্যাশের অবস্থা |
| 10-5 | Receivables | পাওনা ও অগ্রিম মেলানো |
| 18-1 | Marketing spend | মার্কেটিং খরচ |
| 01-1 | Weekly review | সাপ্তাহিক রিভিউ |
| 01-2 | Monthly P&L | মাসিক লাভ-ক্ষতি |
| 02-1 | Attendance | হাজিরা |
| 02-2 | Payroll | বেতন |
| 02-3 | Staff advance | স্টাফ অ্যাডভান্স |
| 02-4 | New employee | নতুন কর্মী |
| 02-5 | Leave | ছুটি |
| 02-6 | Clearance | ছাড়পত্র |
| 02-7 | Duty plan | ডিউটি প্ল্যান |
| 02-8 | Skills | দক্ষতা |
| 11-1 | Shift handover | শিফট হস্তান্তর |
| 0-1 | Location limits | লোকেশনের সীমা |

Rules for the aliases: they are search aliases (`aliases` in `web/ia.js` records and the forms picker), never the form title on paper, never replacing the code. Both the code and the short name find the form. Where a short name equals an existing screen label, the screen label wins and the form is listed under it (one name, one meaning, `docs/IA_CONCEPT.md` 6.1). Short names are checked by `tools/glossary.py` and `tools/check_ui_inventory.py`.

### 3.5 Build steps (after approval, still no code change to printed numbers)

1. Add the alias and display-order data (one JSON, `web/data/form_short.json`), read by the form picker and search.
2. Show "code + short name" in the picker ("14-1 · দিন শেষ"); the code stays first.
3. Tests: both find the same form; the picker order follows 3.3; `python3 tools/check_numbering.py` and `check_ui_inventory.py` pass; no form code string changed (`git diff` against `forms` seed).

Files: `web/data/form_short.json` (new), `web/ia.js` or the form picker module, `web/i18n.js`, `tests/web/ia_test.js`.

---

## 4. Home and drawer information architecture polish

Page jobs (one sentence each):

- Home: show what needs me now and start the three most common jobs of my role in one tap.
- Drawer (Menu): find any screen I am allowed to use, by its group or by search.
- Category page `#/group/<id>`: list every screen of one group, including ones that are not in the drawer.

Decisions:

1. Group order in the drawer follows persona (`docs/IA_CONCEPT.md` 3.2); all 13 groups stay, none removed.
2. Optional parts (To-do, Shifts, Announcements) sit in `people` (Staff group). Rationale: they are about staff work; moving them would break favourites and habits. Their "বন্ধ" chip is the only change.
3. Drawer top, in order: brand, business switcher (only when more than one business), search, location box (collapsible, one line when collapsed), groups. Footer (language, theme, online, log out) collapsible as now.
4. Location up/down: the box is a single row "লোকেশন: <name> ^/v"; collapsed by default after the first choice; remembered per device (`bos_navloc`, try/catch).
5. Home shows no optional-part tiles by default; they appear in Recent after use and in search by their verbs ("কাজ দিন", "আমার শিফট").
6. One name per screen across drawer, title, button (`IA_RULES` rule). Run `node tests/web/ia_test.js` after every change.
7. Funnel check: every group page ends with its main action first (primary button), never only in a three-dot menu (`IA_RULES` Row actions).
8. Orphan check: the 8 screens not in the menu (`docs/ARCHITECTURE_DESIGN.md` 5.9) get a category-page entry or a search keyword; none is left reachable only by URL.

Build: small steps, each independently shippable, ia_test after each. Files: `web/ia.js`, `web/nav.js`, `web/styles.css`, `tests/web/nav_test.js`, `tests/web/navfold_test.js`.

---

## 5. Theme consistency checklist (glass and premium)

Themes: Classic, Premium Dark, Premium Light, Glass Light, Glass Dark (`web/index.html`, `web/theme_glass.css`, `web/theme.css`, `docs/DESIGN_SYSTEM.md`). Glass only re-points tokens; every glass selector starts with `html[data-theme^="glass"]`, so Classic is unchanged.

Checklist for every new or touched screen (tick all, in all themes):

| # | Check |
|---|---|
| 1 | Colours only from tokens (`--ink --muted --ok --warn --bad --info --brand`, `--glass-*`); no hex in screens |
| 2 | Text contrast at least 4.5:1 and UI edges at least 3:1 in Glass Light and Glass Dark (the glass tokens were tuned for this; re-check on any new surface) |
| 3 | `backdrop-filter` only on the ~8 structural layers (header, bottom bar, drawer, sheets, toast, POS bar); never on list rows or cards inside lists |
| 4 | New sheets and the revert sheet use the existing sheet class, so blur, scrim and `html[data-fx="lite"]` fallback come free |
| 5 | Status chips = word + marker (`.chip.draft|pending|approved|rejected|locked|paper|later`); the new "বন্ধ" chip uses the `locked`-style neutral chip, not green or red |
| 6 | Switch/toggle: the existing `.tog` classes (purple on, `--btn-t-*`), not a new look |
| 7 | One glow per screen region, glow only for focus, selected, primary |
| 8 | Radius from tokens (glass `--r-3 14px`, `--r-4 20px`); pills only for chips, toggles, language buttons |
| 9 | Spacing from the scale `--sp-1..7`; touch 44 px (primary 48) |
| 10 | Reduced motion: no animation beyond the sheet; fx lite on weak phones |
| 11 | Dark and light checked with screenshots (not committed); design-guide rule: verify BOTH |
| 12 | Brand fixed: ISLAMIYA MISTY GHAR never translated or recoloured |
| 13 | Segmented control (new) is built from the same button tokens as toggles: selected = `--btn-g-*` (green = selected/confirmed in glass), unselected = `--btn-n-*`; checked state also shown by a tick mark, not colour alone |

Definition of done: a one-line note in BUILD-LOG "themes checked: classic, dark, light, glass-light, glass-dark".

---

## 6. Empty, loading, error state standards

One component: `BOS.ui.state(kind, msg, retry)` in `web/ia.js` (`docs/IA_RULES.md` States). Add kind `off` (feature off) in layout step 3. Every async surface has all four.

| State | Marker | Text pattern (বাংলা) | Action |
|---|---|---|---|
| loading | `data-state="loading"`; skeleton rows `.skel` for lists longer than 3 rows | "লোড হচ্ছে…" | none; do not block the whole page for one slow call |
| empty | `data-state="empty"` | one sentence on what is missing and the next step: "এখনো কোনো করণীয় নেই। নতুন কাজ দিতে + চাপুন।" | primary action if the person can create |
| error | `data-state="error"` notice (bad) | what failed and what to do: "সেভ হয়নি। আবার চেষ্টা করুন।" Never "কিছু ভুল হয়েছে" alone | "আবার চেষ্টা করুন" re-runs the route |
| offline | `data-state="offline"` notice (warn) | "ইন্টারনেট নেই। আপনার কাজ ফোনে রাখা আছে।" (only where the outbox really holds it) | retry |
| off | `data-state="off"` | "এই অংশ এখন বন্ধ। চালু হলে এখানে কাজ করবে।" | owner: "চালু করুন" |

Rules:

1. A failed fetch must never render the empty state (design-guide: no silent failures into empty states). Error and empty are different branches in code and different texts.
2. Errors do not apologise and say what happened and how to fix it; server error codes (`announce_off`) are mapped to plain sentences in one table in `web/i18n.js`.
3. Same verb through a flow: button "ফিরিয়ে দিন", toast "ফিরে এসেছে".
4. Destructive or behaviour-changing actions confirm with a sheet that shows what changes (see the revert sheet).
5. Test: each new screen has a test that forces each of the four states and asserts the marker and no horizontal scroll at 360 px.

---

## 7. Bangla copy standard (owner word list)

Source: owner word list in `tools/apply_owner_words.py`, `docs/LANGUAGE.md`, `docs/IA_CONCEPT.md` 6.1.

Three language modes: বাংলা, Bng-Eng, English. In বাংলা mode a common English word is written in Bangla letters; in Bng-Eng it is written in Latin; English mode is all English. Brand names are never translated.

| Word | বাংলা mode | Bng-Eng mode | Notes |
|---|---|---|---|
| Save | সেভ | Save | owner word |
| Date | ডেট | Date | owner word; not "তারিখ" |
| Approve | অ্যাপ্রুভ | Approve | the bare word only; "অনুমোদিত", "অনুমোদনকারী" stay as they are |
| Default | ডিফল্ট | Default | |
| Layout | লেআউট | Layout | |
| Switch / on / off | সুইচ / চালু / বন্ধ | Switch / on / off | |
| Copy (backup) | কপি | copy | do not use "স্ন্যাপশট" |
| Menu / Home | মেনু / হোম | Menu / হোম | `docs/IA_CONCEPT.md` 6.1 |
| Stock, POS, Item | স্টক, POS, আইটেম | same | |

Style rules:

1. Short sentences, active voice, sentence case. One idea per sentence.
2. Buttons are verbs that say what happens: "সেভ", "চালু করুন", "ফিরিয়ে দিন", never "Submit" or "ঠিক আছে" alone.
3. No jargon the staff do not say: not "feature flag", "rule", "RPC", "snapshot", "scope". Use "সুইচ", "অংশ", "কপি".
4. Numbers in Latin digits; dates `2026-10-21` with day name beside it (`docs/LANGUAGE.md` 4).
5. Same word for the same thing everywhere; new words go to the glossary first (`tools/glossary.py` must print "terms still inconsistent: 0").
6. Every visible string exists in all three modes through `L(bn, en, mix)`; test T19 style check (no raw key shown).
7. Run `python3 tools/apply_owner_words.py --dry-run web/*.js` before a release. Today it reports 94 older strings (`docs/DEMAND_VERIFY.md` R11). Decision: convert them in one reviewed pass after the layout work (`python3 tools/apply_owner_words.py web/*.js`, idempotent), then run `check_ui_inventory.py` and the web suites; it only touches the bn and mix slots, never code or the English slot.
8. No invented names, no demo sentences in examples or tests; test fixtures use neutral `test_*` identifiers.

---

## 8. 360 px rules

The standard device is 360 x 740 (the tests already measure `scrollWidth`; `docs/DEMAND_VERIFY.md` N13). Real phone not yet verified: owner task (`docs/HANDOFF.md` section 4).

| # | Rule |
|---|---|
| 1 | No horizontal page scroll at 360 px. Test: `document.documentElement.scrollWidth <= 360` on every route touched |
| 2 | Side gutter 16 px; content width 328 px |
| 3 | Touch targets 44 px minimum, primary actions 48 px, at least 8 px between neighbours |
| 4 | Single column. Two columns only for short tiles (Home quick actions, 2 across) |
| 5 | Bangla needs line height 1.6, no letter spacing, no `white-space: nowrap` on labels; labels may wrap to two lines |
| 6 | Longest-locale test: judge every screen in the longest of the three modes (Bng-Eng or English) |
| 7 | Tables become stacked rows; a data table never forces sideways scroll (a wrapper with its own scroll is the last resort, with a visible hint) |
| 8 | Bottom bar 4 slots plus Menu; sticky bars never cover the last row (reserve bottom padding) |
| 9 | Sheets: full width, max height 85 percent, internal scroll, primary button in reach of the thumb at the bottom |
| 10 | Forms: one field per row, label above, error under the field, "missing fields" jump (`ARCHITECTURE_DESIGN` S-1) |
| 11 | Chrome budget: about 600 px of visible height when installed; header 56 px, bottom bar 56 px |
| 12 | Input type matches the data (number, tel, date) and `inputmode` set for money |
| 13 | Check in portrait only as the baseline; landscape must not break (no fixed heights) |

Definition of done for any screen: rules 1, 3, 5 and 6 pass in an automated check; rules 7 to 13 reviewed by eye on a phone by the owner (listed in the owner's phone check).

---

## 9. What is NOT in this roadmap

- Any change to a printed form code (needs approval, section 3).
- Any new business template or other-business detail.
- Per-person layouts, PINs on layout, tagging switches as "optional".
- Anything that writes to the live Supabase project: the owner pastes SQL himself (phases 540 and 541 are outlines only).
- Social (X3) and camera (X5), which wait for the owner's accounts and a phone test (`docs/HANDOFF.md`).
