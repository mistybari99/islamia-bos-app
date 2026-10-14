/* Islamia BOS · Setup advisor: "Undo this apply" (step Q4, bos107). NEW file; setupadvisor.js only calls B.setupundo.btn(batch) inside its History cards.
   There is NO restore function on the server (phase81 keeps setup_apply_history only). So this is a plain re-set: every row of one history batch keeps the value it had BEFORE the apply (old);
   the owner sees "now -> back to" for each row and, on confirm, set_rule(rule_key, old) is called once per row (set_rule is owner-only and is the existing audited way; old = null means
   "it was on its default": set_rule with null clears the owner's own value). Nothing else is touched. Handlers are prefixed q4_. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
if (!A || !B) return;
const { sb, S, esc, toast, openSheet, closeSheet } = A;
const H = A.H || (A.H = {}), L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const X = {
  btn: L('এই অ্যাপ্লাই ফিরিয়ে নিন', 'Undo this apply', 'এই apply ফিরিয়ে নিন'),
  title: L('আগের মান ফিরিয়ে আনা', 'Put the earlier values back', 'আগের value ফিরিয়ে আনা'),
  hint: L('প্রতিটি সেটিং অ্যাপ্লাইর আগের মানে ফিরবে। "ডিফল্ট" মানে আপনার নিজের মান মুছে শুরুর মান।', 'Each setting goes back to the value it had before this apply. "Default" clears your own value so the starting value is used.', 'প্রতিটি setting apply-এর আগের value-তে ফিরবে। "Default" মানে আপনার নিজের value মুছে শুরুর value।'),
  now: L('এখন', 'Now', 'এখন'), back: L('ফিরবে', 'Back to', 'ফিরবে'), dflt: L('ডিফল্ট', 'Default', 'Default'), same: L('আগের মানেই আছে', 'already at that value', 'আগের value-তেই আছে'),
  go: L('ফিরিয়ে নিন', 'Undo', 'ফিরিয়ে নিন'), close: L('বন্ধ', 'Close', 'Close'), nothing: L('ফিরিয়ে নেওয়ার কিছু নেই', 'Nothing to put back', 'ফিরিয়ে নেওয়ার কিছু নেই'),
  done: L('ফিরিয়ে আনা হয়েছে', 'Put back', 'ফিরিয়ে আনা হয়েছে'), failed: L('হয়নি', 'failed', 'হয়নি'), owner: L('শুধু মালিক পারবেন', 'Owner only', 'শুধু owner পারবে'),
  on: L('চালু', 'ON', 'ON'), off: L('বন্ধ', 'OFF', 'OFF'),
};
const T = (k) => lab(X[k]);
const isOwner = () => !!(S && S.ctx && S.ctx.is_owner);
const same = (a, b) => JSON.stringify(a === undefined ? null : a) === JSON.stringify(b === undefined ? null : b);
const fmt = (v) => (v === true ? T('on') : v === false ? T('off') : v === null || v === undefined || v === '' ? T('dflt') : String(v));
const nowVal = (k) => { try { return B.rule ? B.rule(k, null) : null; } catch (e) { return null; } };
const batch = (id) => { const h = B.setupadvisor && B.setupadvisor._hist && B.setupadvisor._hist(); return (h || []).find((b) => String(b.client_id) === String(id)) || null; };
// the plan of one batch: one entry per distinct rule (the FIRST line holds the value before the batch); rows already at the old value are marked
function plan(b) {
  const seen = new Set(), out = [];
  ((b && b.lines) || []).forEach((l) => { if (seen.has(l.rule_key)) return; seen.add(l.rule_key); out.push({ key: l.rule_key, old: l.old === undefined ? null : l.old, now: nowVal(l.rule_key), noop: false }); });
  return out;
}
const btn = (b) => (isOwner() && b && b.client_id && (b.lines || []).length ? `<button type="button" class="mini" data-act="q4_undo" data-v="${esc(b.client_id)}">${esc(T('btn'))}</button>` : '');
function sheet(id) {
  if (!isOwner()) return toast(T('owner'));
  const b = batch(id); if (!b) return;
  const p = plan(b); const todo = p.filter((r) => !r.noop);
  openSheet(`<h2>${esc(T('title'))}</h2><p class="muted">${esc(T('hint'))}</p><div class="stack" id="q4_ulist">${p.map((r) => `<div class="row between wrap"><span>${esc(r.key)}</span><span class="muted">${r.noop ? esc(T('same')) : `${esc(T('now'))}: ${esc(fmt(r.now))} → ${esc(T('back'))}: ${esc(fmt(r.old))}`}</span></div>`).join('') || `<p class="muted">${esc(T('nothing'))}</p>`}</div>
    <div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('close'))}</button>${todo.length ? `<button class="primary full" data-act="q4_undogo" data-v="${esc(id)}">${esc(T('go'))}</button>` : ''}</div>`);
}
let busy = false;
async function go(id, el) {
  if (busy || !isOwner()) return; const b = batch(id); if (!b) return;
  busy = true; if (el) el.disabled = true;
  const bad = []; let n = 0;
  try {
    for (const r of plan(b).filter((x) => !x.noop)) {
      try { const res = await sb.rpc('set_rule', { p_key: r.key, p_value: r.old }); if (res && res.error) throw res.error; n++; } catch (e) { bad.push(r.key); }
    }
  } finally { busy = false; if (el) el.disabled = false; }
  closeSheet(); toast(`${T('done')}: ${n}` + (bad.length ? ` · ${T('failed')}: ${bad.join(', ')}` : ''));
  try { if (B.loadStatic) await B.loadStatic(true); } catch (e) { /* the page reloads its own data below */ }
  try { if (B.setupadvisor && B.setupadvisor._reload) await B.setupadvisor._reload(); } catch (e) { /* ignore */ }
}
Object.assign(H, { q4_undo: (a) => sheet(a.dataset.v), q4_undogo: (a) => go(a.dataset.v, a) });
B.setupundo = { X, T, btn, plan, same, fmt, sheet, go };
})();
