# Superseded web tests

Old tests below break each time a file is appended (they assert "X is the LAST script/rec") or depend on UI defaults that later steps changed (for example the drawer footer collapsed by Navfold, bos101). They are kept unedited, but `run_all.sh` skips them (list: `superseded.txt`; run them anyway with `RUN_SUPERSEDED=1`).

| Old brittle test | Maintained test that supersedes it | What changed |
|---|---|---|
| nav_test | nav_b_test | Drawer footer is collapsed by default (Navfold); nav_b sets `bos_navfoot=1` first, all assertions kept |
| pos2_test | pos2b_test | Adapted copy of pos2 |
| optviews_ui_test | optviews_ui2_test | Adapted copy of optviews_ui |
| items2_test | items2_b_test | 'single upload' / last-position assertion adapted |
| landed_test | order_test + landed_pw_test | 'landed.js is LAST script / LAST rec' replaced by real order invariants; behaviour in landed_pw_test |
| landed_b_test | order_test + landed_pw_test | same |
| landed_c_test | order_test + landed_pw_test | same |
| optionsx_test | order_test | 'optionsx LAST script / LAST rec' replaced by order_test (its behaviour checks have no newer copy) |
| optionsx_b_test | order_test | same |

`order_test.js` asserts: required scripts present exactly once, no duplicate or missing script files, entry before kbdfix before pos, pos before posfail, charts before dashx (when present), integrations before setupadvisor and twofa, tpl_registry before every tpl_* consumer, landed before optionsx, ia.js before nav.js, theme.css loaded after styles.css, ia.js rec ids unique, runtime IA ids/routes unique, every non-soon route has a page handler.

## Maintained

- `lang_all_test.js` (+ `lang_baseline.json`): static acorn scan of every `web/*.js` for `L(bn,en,mix)` calls and `{bn,en,mix}` label tables (en has no Bangla letters and is non-empty, bn/mix non-empty, 3-arg form) plus `label_en`/`hint_en` cells of INSERT rows in `supabase/phase72..103.sql`. Fails only on violations not in the baseline (old texts are not edited); prints per-file baseline counts and a Latin-only-bn report (not enforced). Rebuild the baseline deliberately with `LANG_BASELINE_WRITE=1 node tests/web/lang_all_test.js`.

## Status of the three tests that failed while marked superseded (checked 23 Oct 2026, one at a time)

| Test | Result now | Decision |
|---|---|---|
| `catpick_pw_test` | passes (0 assertion failures) once `smoke.js` carries the renumbered form codes | **No longer superseded**: removed from `superseded.txt`, `run_all.sh` runs it. `catpick_pw_b2_test` stays too. |
| `glass_test` | fails: compares the three old themes with the pre-glass commit `35f8f7d`; later intended steps changed those themes (taller header on pos, S2-S4 make `form/37-1` a real form) | Stays superseded by `glass_b2_test` (same checks, baseline `36254db`, `BASE_REF` overrides). Not edited; running it would only repeat the `glass_b2` finding for the old baseline. |
| `items2_test` | fails one assertion, `upload path ITEMS/<loc>/*.jpg jpeg`: since step Img (bos103) the app also uploads a ~160 px copy at `<path>.t.jpg` | Stays superseded by `items2_b_test` (that one assertion adapted, everything else identical; now served from this checkout on a free port, it passes). |
