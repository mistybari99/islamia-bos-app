# Open owner questions carried over from the daily workflow guide

Source: the daily workflow guide on branch `ccr-46b26d91-81vl9s` (15 Oct 2026). That guide was left out of this branch because it uses invented staff names and a demo day (CLAUDE.md). Only the open questions and gaps are kept here, without names.

## Open items (owner decides)
- What `IMG-3`, `CF`, `SF` and `GD` stand for (the guide's mapping was the author's guess).
- Where the cash hub is, and whether it is a separate place.
- Whether `SF` (`mishti_factory`) resumes.
- Whether a separate sales place is needed for the factory-to-showroom step.
- Who holds each role at each place (no staff accounts are seeded).
- Whether `blind_count_on`, `forms_post_to_ledger` and the `stock_*` switches are turned on, and in what order.

## Gaps listed in the guide
- A showroom manager at each showroom and a dedicated storekeeper at each showroom are not seeded.
- ONLINE_INTAKE form: listed in the old manual, no code found.
- Some reports remain in `docs/REMAINING.md`.

## How to verify on the phone (after the owner grants access)
1. Check that each role's screen list matches its place.
2. Try a transfer from the godown to a showroom with a short received quantity.
3. Try a count where the counter is the storekeeper; the form must refuse.
