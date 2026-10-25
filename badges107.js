/* Islamia BOS · Attention badges for Home / Owner mode (step Q4, bos107). NEW file; no existing file is edited for it.
   One small strip of tappable chips, each with a count, drawn at the top of Home (#hv_main) and of the Owner board (#ob_main):
     ledger problems (ledger_problem_count, phase87) · waiting for cost (cost_wait_list96, phase96) · pending auto-posts (acct_pending_alert85, phase85) ·
     forms with no screen record (unmatched_forms, phase83) · items with unknown cost (items_with_cost + items, as the cost board) · bills without payment (bills_without_payment99, phase99) · inbox new messages (inbox_board).
   A chip shows ONLY when (1) the menu entry of its screen is allowed for this person (owner / the same grant the entry needs - the server still decides on the call itself) and (2) its count is above zero.
   Loading is lazy (after the screen has drawn) with a 2 second cap per call; a missing function, a refusal or a slow call simply hides that chip. Counts are kept 60 seconds.
   Tap = data-act q4_badge, opens the screen. Texts via B.L; English mode is all English. Loaded after the other modules. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
if (!A || !B) return;
const { sb, S, esc } = A;
const H = A.H || (A.H = {}), L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const CAP_MS = () => Number(window.__Q4_CAP_MS) || 2000;
const TTL_MS = () => (window.__Q4_TTL_MS === 0 ? 0 : Number(window.__Q4_TTL_MS) || 60000);
const X = {
  region: L('মনোযোগ দরকার', 'Needs attention', 'Attention দরকার'),
  ledger: L('খাতায় পোস্টের সমস্যা', 'Ledger problems', 'Ledger post-এর সমস্যা'),
  costwait: L('কস্টের অপেক্ষায়', 'Waiting for cost', 'Cost-এর অপেক্ষায়'),
  autopost: L('অটো পোস্টের অপেক্ষায়', 'Pending auto-posts', 'Auto post-এর অপেক্ষায়'),
  unmatched: L('স্ক্রিনে রেকর্ড নেই এমন ফর্ম', 'Forms with no screen record', 'Screen-এ record নেই এমন form'),
  unkcost: L('কস্ট জানা নেই এমন আইটেম', 'Items with unknown cost', 'Cost জানা নেই এমন item'),
  billpay: L('পেমেন্ট ছাড়া বিল', 'Bills without payment', 'Payment ছাড়া bill'),
  inbox: L('নতুন বার্তা', 'New messages', 'নতুন message'),
};
const T = (k) => lab(X[k]);
const num = (v) => { const n = Number(v); return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0; };
const rpc = async (fn, args) => { const r = await sb.rpc(fn, args || {}); if (r && r.error) throw r.error; return r ? r.data : null; };

// each: route = the screen (also the menu entry that decides who sees the chip), get() = the count
const SPECS = [
  { id: 'ledger', route: 'ledgerlinks', get: async () => num(await rpc('ledger_problem_count', { p_loc: null })) },
  { id: 'costwait', route: 'books96', get: async () => { const d = await rpc('cost_wait_list96', { p_loc: null, p_limit: 1 }); return num(d && d.total); } },
  { id: 'autopost', route: 'books85', get: async () => { const d = await rpc('acct_pending_alert85', { p_limit: 1 }); return num(d && d.old_count); } },
  { id: 'unmatched', route: 'unmatched', get: async () => { const d = await rpc('unmatched_forms', { p_from: null, p_to: null, p_loc: null }); return num(d && d.lines_unmatched); } },
  { id: 'unkcost', route: 'costunknown', get: async () => {
    const [c, it] = await Promise.all([sb.rpc('items_with_cost'), sb.from('items').select('id').eq('is_active', true).eq('tracked', true).limit(1000)]);
    if ((c && c.error) || (it && it.error)) throw (c && c.error) || it.error;
    const has = new Set(((c && c.data) || []).filter((x) => Number(x.cost_price) > 0).map((x) => x.item_id));
    return ((it && it.data) || []).filter((i) => !has.has(i.id)).length; } },
  { id: 'billpay', route: 'billpay', get: async () => { const d = await rpc('bills_without_payment99', { p_kind: null, p_loc: null, p_limit: 200 }); return num(d && d.rows && d.rows.length); } },
  { id: 'inbox', route: 'inbox', get: async () => { const d = await rpc('inbox_board', { p_loc: null }); return d && d.on === false ? 0 : num(d && d.new_count); } },
];
const uid = () => (S && S.ctx && S.ctx.profile && S.ctx.profile.id) || 'anon';
let CACHE = { uid: null, at: 0, v: {} };   // v[id] = count (0 = hidden) ; absent = not loaded yet
let busy = false;

const allowed = () => {   // route -> true when the person's menu entry for that screen is allowed
  const ok = {};
  try { const es = (window.BOS_NAV && window.BOS_NAV.entries && window.BOS_NAV.entries()) || []; es.forEach((e) => { if (e.kind === 'r') ok[e.route] = !!e.ok; }); } catch (e) { /* no entries = nothing shows */ }
  return ok;
};
const cap = (p) => Promise.race([p, new Promise((_, rej) => setTimeout(() => rej(new Error('q4_timeout')), CAP_MS()))]);
function html() {
  const ok = allowed(), v = CACHE.v;
  const chips = SPECS.filter((s) => ok[s.route] && v[s.id] > 0).map((s) =>
    `<button type="button" class="q4b-chip" data-act="q4_badge" data-v="${esc(s.route)}" data-b="${esc(s.id)}"><span>${esc(T(s.id))}</span><b class="q4b-n">${v[s.id] > 999 ? '999+' : v[s.id]}</b></button>`);
  return chips.length ? `<div class="q4b-row" role="group" aria-label="${esc(T('region'))}">${chips.join('')}</div>` : '';
}
function render() { const box = $('#q4_badges'); if (!box) return; const h = html(); box.innerHTML = h; box.hidden = !h; }
async function load(force) {
  if (CACHE.uid !== uid()) CACHE = { uid: uid(), at: 0, v: {} };
  if (busy || (!force && CACHE.at && Date.now() - CACHE.at < TTL_MS())) return render();
  busy = true; const ok = allowed();
  try {
    await Promise.all(SPECS.filter((s) => ok[s.route]).map(async (s) => {
      try { CACHE.v[s.id] = await cap(s.get()); } catch (e) { CACHE.v[s.id] = 0; }   // missing function / refused / slow = no chip
      render();
    }));
    CACHE.at = Date.now();
  } finally { busy = false; render(); }
}
function place() {
  if ($('#q4_badges')) return;
  const host = $('#hv_main') && $('#hv_main').firstElementChild ? $('#hv_main') : $('#ob_bar') ? $('#ob_main') : null;
  if (!host || !S || !S.ctx) return;
  const d = document.createElement('div'); d.id = 'q4_badges'; d.hidden = true; host.insertBefore(d, host.firstChild);
  render(); setTimeout(() => load(false), 0);
}
let tick = 0;
try { if (window.MutationObserver && document.body) new MutationObserver(() => { if (tick) return; tick = setTimeout(() => { tick = 0; try { place(); } catch (e) { /* optional */ } }, 50); }).observe(document.body, { childList: true, subtree: true }); } catch (e) { /* no observer = no strip */ }
Object.assign(H, { q4_badge: (a) => { const r = a && a.dataset && a.dataset.v; if (r) location.hash = '#/' + r; } });
const css = document.createElement('style'); css.id = 'q4bcss';
css.textContent = `#q4_badges{margin:0 0 10px}.q4b-row{display:flex;flex-wrap:wrap;gap:6px}.q4b-chip{display:inline-flex;align-items:center;gap:8px;min-height:40px;padding:4px 12px;border-radius:999px;border:1px solid var(--line);background:var(--card,var(--bg));color:inherit;font:inherit;max-width:100%}
.q4b-chip span{overflow-wrap:anywhere;text-align:start}.q4b-n{flex:none;min-width:24px;padding:2px 8px;border-radius:999px;background:var(--bad,#c0392b);color:#fff;text-align:center;font-size:.85rem}`;
document.head.appendChild(css);
B.badges107 = { X, T, SPECS, load, render, place, html, _cache: () => CACHE };
})();
