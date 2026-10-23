-- Phase 547 (READINESS D8) - stock_recon_period: the movement reason transit_loss is a listed movement.
-- Paste AFTER phase546. Paste-twice safe (a second paste finds the text already patched and does nothing). Earlier phase files are not edited.
-- DRAFT from the readiness audit of 23 Oct 2026 (docs/READINESS_99.md, defect D8). Tested on a LOCAL throwaway PostgreSQL 16 only; the owner pastes it himself after review.
-- Problem (reproduced): with transit_short_mode = loss (the setup advisor sets it), a short receipt writes a ledger row with reason transit_loss
--   (phase 499 / 114). stock_recon_period (phase 423) does not know that reason, so the period statement shows "unclassified -0.5" and state
--   "unclassified" for the receiving place although opening + movements = closing holds. Nothing is lost; the statement is just not able to say so.
-- Fix: the function text is read from the database (so later patches to it are kept), three anchors are replaced, and the function is created again:
--   (1) one more column in the movement sums: transit_loss, (2) it is part of the listed movements, (3) it is returned as the key transit_loss in every row.
-- No new switch: with no transit_loss row in a period the result is identical to today (the new key is 0).
-- Business reason (decided, not asked): a statement that calls a known, costed movement "unclassified" teaches people to ignore the word.

do $p547$
declare d text; o text; sig regprocedure := 'public.stock_recon_period(date, date, integer, text[])'::regprocedure;
  a2 constant text := 'coalesce(a.reversal, 0) as listed';
  a3 constant text := '''reversal'', coalesce(r.reversal, 0),';
begin
  select pg_get_functiondef(sig) into d;
  if d is null then raise exception 'phase547: stock_recon_period not found'; end if;
  if position('transit_loss' in d) > 0 then return; end if;                       -- already patched: paste twice does nothing
  o := d;
  if position(a2 in d) = 0 or position(a3 in d) = 0 or position('as reversal' in d) = 0 then
    raise exception 'phase547: an anchor of stock_recon_period was not found (the function text changed); nothing was changed';
  end if;
  d := replace(d, 'as reversal', 'as reversal, sum(l.qty_delta) filter (where l.reason = ''transit_loss'' and (l.made_at at time zone ''Asia/Dhaka'')::date between p_from and p_to) as transit_loss');
  d := replace(d, a2, 'coalesce(a.reversal, 0) + coalesce(a.transit_loss, 0) as listed');
  d := replace(d, a3, '''reversal'', coalesce(r.reversal, 0), ''transit_loss'', coalesce(r.transit_loss, 0),');
  if d = o then raise exception 'phase547: nothing replaced'; end if;
  execute d;
end $p547$;
