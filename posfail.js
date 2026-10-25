/* Islamia BOS · Offline POS failed cards (step E-b / E8, supabase/phase83.sql).
   A sale that was queued offline and then refused on replay stays on the phone as a "failed card". This module adds to that card:
   - "Re-send on manager override": pos_replay_override(payload, reason, err) with the ORIGINAL client_id (so it can never become a second sale; a reason is required).
   - "Export JSON": the card as a file / clipboard text, so nothing is lost if the browser storage is cleared.
   - the cards are reported to the server (pos_failed_note) so the owner board can count them; discard / resend close the server card.
   - the queue replay calls record_sale_offline (same arguments as record_sale2; the owner switch offline_soft_stock decides whether "stock is short" refuses it).
   Everything is optional: without this file web/pos.js behaves exactly as before. Every text has bn / en / mix through B.L; English mode has no Bangla letters. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS = window.BOS || {};
if (!A) return;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet, store } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const X = {
  resend: L('ম্যানেজার-ওভাররাইডে আবার পাঠাও', 'Re-send on manager override', 'Manager override-এ আবার পাঠাও'),
  export: L('JSON export', 'Export JSON', 'JSON export'),
  reasonL: L('কারণ লিখুন (জরুরি)', 'Reason (required)', 'কারণ লিখুন (required)'),
  send: L('আবার পাঠাও', 'Send again', 'আবার পাঠাও'),
  hint: L('আসল client id-ই ব্যবহার হবে, তাই একই sale দুবার হবে না। এটা শুধু "stock কম" আটকানো পার করে; closed period, credit limit ইত্যাদি অন্য নিয়ম থাকবেই।',
    'The original client id is used, so the same sale cannot happen twice. This only overrides "stock is short"; the other rules (closed period, credit limit ...) still apply.',
    'আসল client id-ই ব্যবহার হবে, তাই একই sale দুবার হবে না। এটা শুধু "stock কম" আটকানো পার করে; closed period, credit limit ইত্যাদি অন্য rule থাকবেই।'),
  needGrant: L('এই কাজের জন্য manager-এর অনুমতি (pos_replay_override) লাগবে', 'This needs manager permission (pos_replay_override)', 'এই কাজের জন্য manager permission (pos_replay_override) লাগবে'),
  needReason: L('কারণ লিখতে হবে', 'Write a reason first', 'কারণ লিখতে হবে'),
  done: L('সেল রেকর্ড হয়েছে', 'Sale recorded', 'Sale record হয়েছে'),
  dup: L('এই সেল আগেই রেকর্ড হয়ে আছে', 'This sale was already recorded', 'এই sale আগেই record হয়ে আছে'),
  exported: L('JSON কপি / ডাউনলোড হয়েছে', 'JSON copied / downloaded', 'JSON copy / download হয়েছে'),
  close: L('বন্ধ', 'Close', 'Close'),
  title: L('Offline POS — আটকে যাওয়া সেল', 'Offline POS - refused sales', 'Offline POS — আটকে যাওয়া sale'),
  intro: L('ফোনে জমা থাকা যে sale replay-এর সময় নিয়মে আটকেছে, তার সংখ্যা। কার্ড ফোনেই থাকে; এখানে শুধু গোনা হয়।',
    'Sales queued on a phone that were refused when they were replayed. The cards stay on the phone; only the count is kept here.',
    'ফোনে জমা থাকা যে sale replay-এর সময় rule-এ আটকেছে, তার সংখ্যা। Card ফোনেই থাকে; এখানে শুধু count থাকে।'),
  open: L('আটকে আছে', 'waiting', 'আটকে আছে'), none: L('কিছু নেই ✓', 'Nothing waiting ✓', 'কিছু নেই ✓'),
  place: L('জায়গা', 'Place', 'Place'), total: L('টোটাল', 'Total', 'Total'), loading: L('লোড হচ্ছে…', 'Loading...', 'Loading…'),
  trail: L('ওভাররাইডের ইতিহাস', 'Override history', 'Override history'), why: L('কারণ', 'Reason', 'কারণ'),
  noperm: L('এটা দেখার অনুমতি নেই', 'You are not allowed to see this', 'এটা দেখার permission নেই'),
};
const T = (k) => lab(X[k]);
const clean = (p) => { const r = {}; Object.keys(p || {}).forEach((k) => { if (k[0] !== '_') r[k] = p[k]; }); return r; };
const uidK = () => (S.ctx && S.ctx.profile ? S.ctx.profile.id : 'anon');
const XK = () => 'bos_pos_failed_' + uidK();
const failedQ = () => { try { return JSON.parse(store.get(XK())) || []; } catch (e) { return []; } };
const setFailed = (q) => store.set(XK(), JSON.stringify(q));
const NOFN = /record_sale_offline|Could not find the function|PGRST202|schema cache/i;
let missing = false;

// ---- the hooks web/pos.js calls (each is optional there) ----
function buttons(x) {
  const id = esc(x.p_client);
  return `<button class="full" data-act="posfail_resend" data-v="${id}">${esc(T('resend'))}</button><button class="full" data-act="posfail_export" data-v="${id}">${esc(T('export'))}</button>`;
}
// the queue replay: record_sale_offline when the database has it, else exactly record_sale2 as before
async function sendOffline(args) {
  if (!missing) {
    const r = await sb.rpc('record_sale_offline', args);
    if (!(r.error && NOFN.test(r.error.message || '') && /record_sale_offline|PGRST202|Could not find/i.test(r.error.message || ''))) return r;
    missing = true;
  }
  return sb.rpc('record_sale2', args);
}
const summary = (x) => ({ client_id: x.p_client, loc: x.p_loc, total: x._total || 0, err: String(x._err || '').slice(0, 300), sold_at: x.p_sold_at || null, lines_n: (x.p_lines || []).length });
async function report(list) {
  try { if (list && list.length) await sb.rpc('pos_failed_note', { p_items: list.map(summary) }); } catch (e) { /* the card stays on the phone either way */ }
}
async function discarded(id) { try { await sb.rpc('pos_failed_close', { p_client: id, p_status: 'discarded', p_note: 'discarded on the phone' }); } catch (e) { /* ignore */ } }

// ---- JSON export ----
function exportCard(id) {
  const x = failedQ().find((c) => c.p_client === id); if (!x) return;
  const txt = JSON.stringify(x, null, 2);
  try {
    const url = URL.createObjectURL(new Blob([txt], { type: 'application/json' }));
    const a = document.createElement('a'); a.href = url; a.download = 'pos-failed-' + id + '.json'; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 2000);
  } catch (e) { try { navigator.clipboard.writeText(txt); } catch (e2) { /* nothing more to try */ } }
  toast(T('exported'));
}

// ---- manager override ----
function resendSheet(id) {
  const x = failedQ().find((c) => c.p_client === id); if (!x) return;
  openSheet(`<h2>${esc(T('resend'))}</h2><div class="notice warn">${esc(x._err || '')}</div><div class="muted" style="margin:6px 0">${esc(T('hint'))}</div>
    <label>${esc(T('reasonL'))}</label><textarea id="pf_reason" rows="3"></textarea>
    <div class="row" style="margin-top:10px"><button class="full" data-act="closesheet">${esc(T('close'))}</button><button class="primary full" data-act="posfail_go" data-v="${esc(id)}">${esc(T('send'))}</button></div>`);
}
async function resendGo(id) {
  const x = failedQ().find((c) => c.p_client === id); if (!x) return;
  const reason = (($('#pf_reason') || {}).value || '').trim();
  if (reason.length < 3) return toast(T('needReason'));
  const { data, error } = await sb.rpc('pos_replay_override', { p_payload: clean(x), p_reason: reason, p_err: x._err || null });
  if (error) {
    if (/replay_override_needs_approval/.test(error.message || '')) return toast(T('needGrant'));
    return fail(error);
  }
  setFailed(failedQ().filter((c) => c.p_client !== id));
  closeSheet(); toast(data && data.dup ? T('dup') : T('done'));
  if (A.H && A.H.pos_tab && location.hash.startsWith('#/pos')) A.H.pos_tab({ dataset: { v: 'today' } });
}

// ---- owner board: how many failed cards are waiting, per place ----
async function boardCount() { try { const r = await sb.rpc('pos_failed_board'); return r.error ? null : r.data; } catch (e) { return null; } }
async function view() {
  shell(T('title'), `<div id="pf_body"><p class="muted">${esc(T('loading'))}</p></div>`, true);
  const b = await boardCount(); const el = $('#pf_body'); if (!el) return;
  if (!b) { el.innerHTML = `<p class="muted">${esc(T('noperm'))}</p>`; return; }
  const locs = (B.ENV && B.ENV.locs) || [];
  const nmLoc = (id) => { const l = locs.find((z) => z.id === id); return l ? lab({ bn: l.name_bn || l.code, en: l.name_en || l.code, mix: l.name_bn || l.code }) : '#' + id; };
  let trail = [];
  try { const r = await sb.from('pos_replay_log').select('client_id,location_id,reason,result,at').order('at', { ascending: false }).limit(20); trail = r.data || []; } catch (e) { /* not allowed = empty */ }
  el.innerHTML = `<p class="muted">${esc(T('intro'))}</p><div class="card"><b style="font-size:1.4rem">${esc(String(b.open ?? 0))}</b> ${esc(T('open'))}</div>
    ${(b.by_location || []).length ? (b.by_location || []).map((z) => `<div class="card row between"><span>${esc(T('place'))}: ${esc(nmLoc(z.location_id))}</span><span>${esc(String(z.n))} · ${esc(T('total'))} ${esc(String(z.total))}</span></div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`}
    ${trail.length ? `<h3>${esc(T('trail'))}</h3>${trail.map((z) => `<div class="card"><div class="muted">${esc(String(z.at).slice(0, 16).replace('T', ' '))} · ${esc(nmLoc(z.location_id))}</div><div>${esc(T('why'))}: ${esc(z.reason)}</div></div>`).join('')}` : ''}`;
}

A.H = A.H || {};
Object.assign(A.H, {
  posfail_resend: (a) => resendSheet(a.dataset.v),
  posfail_go: (a) => resendGo(a.dataset.v),
  posfail_export: (a) => exportCard(a.dataset.v),
});
B.posfail = { X, T, buttons, sendOffline, report, discarded, boardCount, exportCard, clean, summary };
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { posfailed: view });
})();
