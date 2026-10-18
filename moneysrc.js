/* Islamia BOS · Payment source picker (shared component, BOS.moneySrc). One select "Payment source" on every screen that enters a payment.
   The owner decides per payment where the money comes from or goes to: a cash drawer, a mobile wallet, a bank account (registry: #/moneyaccounts).
   Server: supabase/phase87.sql (money_pick). The chosen account travels IN BAND as the text "ma#<id>;" in front of the free text field of the payment
   (tag()), so an offline saved payment keeps it; the server reads it, sets the payment mode from the account and removes the tag.
   Nothing is shown until at least one money account exists (an install that has not configured accounts looks exactly as before).
   Use: put BOS.moneySrc.slot('id', 'event', { locSel: '#place_select' }) in the form markup (the slot fills itself), send BOS.moneySrc.tag('id', text) in the text field,
   BOS.moneySrc.get('id') is the chosen account id or null. Events: salary_payment salary_advance expense_10_2 quick_expense supplier_payment purchase_payment owner_topup
   owner_draw partner_capital partner_payout customer_refund supplier_refund customer_advance cash_handover.
   English labels only for now (the owner will translate them later). UNVERIFIED on a real phone and on a real Supabase project. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
if (!A || !B) return;
const { sb, esc } = A;
const T = {
  label: 'Payment source', none: 'Not named (as before)', hint: 'The payment mode follows the account you choose.', def: 'Default', fixed: 'Fixed by the owner setting', required: 'Choose the payment source',
};
const cache = new Map();                       // "event|loc" -> { at, data }
const TTL = 60000;

async function prefetch(event, loc) {
  const key = event + '|' + (loc || '');
  const c = cache.get(key);
  if (c && Date.now() - c.at < TTL) return c.data;
  let data = null;
  try {
    const r = await sb.rpc('money_pick', { p_event: event, p_loc: loc ? Number(loc) : null });
    data = r && !r.error ? r.data : null;       // phase87 not on the server, or not allowed: no picker, the screen works as before
  } catch (e) { data = null; }
  cache.set(key, { at: Date.now(), data });
  return data;
}
const cached = (event, loc) => { const c = cache.get(event + '|' + (loc || '')); return c ? c.data : null; };
const label = (a) => [a.name_en, a.provider && a.kind !== 'cash' ? a.provider : '', a.account_no ? '…' + String(a.account_no).slice(-4) : ''].filter(Boolean).join(' · ') + ' (' + a.kind + ')';

function options(d, sel) {
  const rows = d.rows || [];
  const def = rows.find((a) => a.is_default);
  const first = d.require_source ? `<option value="" disabled ${sel ? '' : 'selected'}>${esc(T.required)}</option>` : `<option value="">${esc(def ? T.def + ': ' + def.name_en : T.none)}</option>`;
  return first + rows.map((a) => `<option value="${esc(String(a.id))}" ${String(sel) === String(a.id) ? 'selected' : ''}>${esc(label(a))}</option>`).join('');
}

// ---- the slot: placeholder in the form markup that fills itself ----
const slot = (id, event, o = {}) => `<div class="ms-slot" id="ms_${esc(id)}" data-ms-id="${esc(id)}" data-ev="${esc(event)}"${o.locSel ? ` data-locsel="${esc(o.locSel)}"` : ''}${o.loc ? ` data-loc="${esc(String(o.loc))}"` : ''}></div>`;
async function fill(el) {
  if (!el || el.dataset.msBusy) return;
  el.dataset.msBusy = '1';
  try {
    const id = el.dataset.msId, ev = el.dataset.ev;
    const locEl = el.dataset.locsel ? document.querySelector(el.dataset.locsel) : null;
    const loc = locEl ? locEl.value : el.dataset.loc || '';
    const d = await prefetch(ev, loc);
    if (!d || !(d.rows || []).length) { el.innerHTML = ''; return; }          // nothing configured: invisible
    const prev = el.querySelector('select') ? el.querySelector('select').value : '';
    const sel = prev || (d.require_source && d.default_id ? d.default_id : '');
    const fixed = !d.allow_override && d.default_id;
    el.innerHTML = `<div><label for="ms_sel_${esc(id)}">${esc(T.label)}</label><select id="ms_sel_${esc(id)}" data-ms-sel="${esc(id)}"${fixed ? ' disabled' : ''}>${options(d, fixed ? d.default_id : sel)}</select>
      <div class="muted" style="font-size:.85rem">${esc(fixed ? T.fixed : T.hint)}</div></div>`;
    if (locEl && !locEl.dataset.msBound) { locEl.dataset.msBound = '1'; locEl.addEventListener('change', () => fill(el)); }
  } finally { delete el.dataset.msBusy; el.dataset.msReady = '1'; }
}
const fillAll = (root) => (root || document).querySelectorAll('.ms-slot:not([data-ms-ready])').forEach((el) => { fill(el); });
function setEvent(id, event) { const el = document.getElementById('ms_' + id); if (!el || el.dataset.ev === event) return; el.dataset.ev = event; el.innerHTML = ''; fill(el); }
function get(id) {
  const s = document.getElementById('ms_sel_' + id), box = document.getElementById('ms_' + id);
  if (!s || (box && box.hidden) || (s.disabled && !s.value)) return null;
  const v = Number(s.value);
  return Number.isFinite(v) && v > 0 ? v : null;
}
const tag = (id, text) => { const a = get(id); const t = text == null || text === '' ? null : String(text); return a ? 'ma#' + a + ';' + (t || '') : t; };

// ---- a row select for list components (pay.js): synchronous, from the prefetched list ----
function rowSelect(event, i, selected, row) {
  const d = cached(event, '');
  if (!d || !(d.rows || []).length) return '';
  if (d.require_source && !selected && row) row.macc = String(d.default_id || d.rows[0].id);
  const sel = selected || (row && row.macc) || '';
  return `<div><label>${esc(T.label)}</label><select data-pay="${i}.macc"${!d.allow_override && d.default_id ? ' disabled' : ''}>${options(d, sel)}</select></div>`;
}
const taggedWallet = (macc, wallet) => (macc ? 'ma#' + macc + ';' : '') + (wallet || '');

// ---- for the form engine (entry.js SEL field of the 10-2 voucher): the account id is stored inside the form data (money_account_id) ----
function hasAccounts(event) { const d = cached(event, ''); if (!d) { prefetch(event, ''); return false; } return (d.rows || []).length > 0; }
const formOpts = (event) => () => { const d = cached(event, ''); if (!d) { prefetch(event, ''); return []; } return (d.rows || []).map((a) => [String(a.id), { bn: label(a), mix: label(a), en: label(a) }]); };

B.moneySrc = { prefetch, cached, slot, fill, fillAll, setEvent, get, tag, rowSelect, taggedWallet, hasAccounts, formOpts, reset() { cache.clear(); } };
// the 10-2 voucher form reads its accounts synchronously: warm the cache a moment after start and on each page change (one small call, cached for a minute)
const warm = () => { if (A.S && A.S.ctx) prefetch('expense_10_2', ''); };
setTimeout(warm, 2500); window.addEventListener('hashchange', () => setTimeout(warm, 300));
try {
  new MutationObserver((ms) => { for (const m of ms) m.addedNodes.forEach((n) => { if (n.nodeType === 1) { if (n.matches && n.matches('.ms-slot:not([data-ms-ready])')) fill(n); else if (n.querySelectorAll) fillAll(n); } }); })
    .observe(document.documentElement, { childList: true, subtree: true });
} catch (e) { /* no observer: call BOS.moneySrc.fillAll() after drawing */ }
})();
