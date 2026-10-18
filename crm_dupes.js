/* Islamia BOS · CRM-B duplicate customers (#/crmdupes). A "possible duplicates" review list (same phone, same name, a name one letter apart), the SOFT link ("same person")
   and its undo, and the person view of a linked group. Nothing is merged, moved or deleted: customer ids, sales, payments, dues and the books stay exactly as they are; the link only
   groups customers for CRM views (the collapsed customer list, the person view, the message check).
   Also the API for the customer menu:  BOS.crmDupes.sheet(customerId, name)  (see docs/integration/CRM-B.md).
   Server: supabase/phase305.sql (_crmb_dup_candidates, _crmb_dup_review, _crmb_link_customers, _crmb_unlink_customers, _crmb_customer_group, _crmb_links_list).
   Two settings (owner): crm_dup_check_on (OFF), crm_dup_similar_names_on (OFF). English labels only for now. UNVERIFIED on a real phone and on a real Supabase project. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet, H } = A;
const $ = (s, el = document) => el.querySelector(s);
const rid = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3) | 8).toString(16); }));
const val = (id) => (($('#' + id) || {}).value || '').trim();
const chip = (txt, cls) => `<span class="chip ${cls || ''}">${esc(txt)}</span>`;
const fld = (id, label, inner) => `<div><label for="${id}">${esc(label)}</label>${inner}</div>`;
const fm = (n) => { const v = Number(n); return Number.isFinite(v) ? v.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) : '-'; };

const ERR = {
  not_allowed: 'You do not have permission.', module_off: 'The duplicate check is switched off in Settings.', self_link: 'That is the same customer.', reason_required: 'Write a reason (at least 3 characters).',
  customer_not_found: 'Customer not found.', already_linked: 'These two are already linked.', primary_is_linked: 'The main customer is itself linked under another one. Choose the other one as main, or unlink first.',
  linked_elsewhere: 'This customer is already linked under another main customer. Unlink it first.', not_linked: 'This customer is not linked.', bad_input: 'Something in the form is not valid.',
};
const eText = (e) => { const m = String((e && e.message) || '').replace(/\bnot allowed\b/, 'not_allowed'); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? ERR[k] : m || 'error'; };
const missing = (e) => e && e.raw && (e.raw.code === 'PGRST202' || /does not exist|could not find/i.test(String(e.raw.message || '')));
async function call(fn, args) {
  const r = await sb.rpc(fn, args || {});
  if (r.error) { const e = new Error(eText(r.error)); e.raw = r.error; throw e; }
  return r.data;
}
const REASON = { same_phone: 'same phone number', same_name: 'same name', similar_name: 'name one letter different', same_address: 'same address', same_birthday: 'same birthday' };
const STRENGTH = { strong: 'Very likely', possible: 'Possible', weak: 'Weak hint' };

const D = { tab: 'list', err: null, cand: null, links: null, rules: null, pol: null, pair: null, grp: null, limit: 50 };
const RULE_KEYS = ['crm_dup_check_on', 'crm_dup_similar_names_on'];

const tabsBar = () => `<div class="row wrap" id="dp_tabs" style="gap:.3rem">${[['list', 'Possible duplicates'], ['linked', 'Linked'], ['settings', 'Settings']].map(([k, l]) => `<button type="button" class="tog ${D.tab === k ? 'on' : ''}" data-act="dp_tab" data-v="${k}">${esc(l)}</button>`).join('')}</div>`;
const person = (p) => `<div style="min-width:0"><b>${esc(p.name)}</b>${p.active === false ? ' ' + chip('inactive', 'bad') : ''}<div class="muted">${esc(p.mobile || '')}</div></div>`;
function listHTML() {
  const C = D.cand; if (!C) return '';
  if (C.off) return '<div class="card"><p id="dp_off">The duplicate check is switched off. The owner switches it on in Settings. Until then saving a customer only stops on an identical mobile number, as before.</p></div>';
  const rows = (C.rows || []).map((r) => `<div class="card stack dp-pair" data-a="${esc(r.a_id)}" data-b="${esc(r.b_id)}">
      <div class="row between">${chip(STRENGTH[r.strength] || r.strength, r.strength === 'strong' ? 'bad' : r.strength === 'possible' ? 'warn' : '')}<span class="muted">${(r.reasons || []).map((x) => esc(REASON[x] || x)).join(' · ')}</span></div>
      <div class="row between" style="gap:8px">${person(r.a)}${person(r.b)}</div>
      ${D.pol && D.pol.can_link ? `<div class="row wrap"><button type="button" class="primary" data-act="dp_same" data-a="${esc(r.a_id)}" data-b="${esc(r.b_id)}">Same person</button><button type="button" class="btn" data-act="dp_not" data-a="${esc(r.a_id)}" data-b="${esc(r.b_id)}">Not the same</button></div>`
        : '<div class="muted">You can look, but you cannot link or dismiss.</div>'}</div>`).join('');
  return `<p class="muted">${esc(String(C.total))} pair(s) to look at${C.masked ? '. Phone numbers are partly hidden for you' : ''}. A link never changes sales, payments, dues or the books.</p>` + (rows || '<p class="muted" id="dp_none">No possible duplicates.</p>')
    + ((C.rows || []).length < Number(C.total) ? '<button type="button" class="full" data-act="dp_more">Show more</button>' : '');
}
function linkedHTML() {
  const L = D.links || [];
  return '<p class="muted">Customers grouped as one person. Dues and payments stay on each customer; only spend, orders, last purchase and points are shown together.</p>'
    + (L.map((l) => `<div class="card stack dp-link" data-id="${esc(l.id)}"><div class="row between"><div><b>${esc(l.primary_name)}</b> <span class="muted">${esc(l.primary_mobile || '')}</span></div>${chip('main')}</div>
        <div class="row between"><div><b>${esc(l.linked_name)}</b> <span class="muted">${esc(l.linked_mobile || '')}</span></div>${l.undone_at ? chip('unlinked', 'warn') : chip('linked', 'ok')}</div>
        <div class="muted">${esc(l.reason)} · ${esc(l.created_staff || '')} · ${esc(String(l.created_at).slice(0, 10))}${l.undo_reason ? ' · unlinked: ' + esc(l.undo_reason) : ''}</div>
        ${!l.undone_at && D.pol && D.pol.can_merge ? `<button type="button" class="mini" data-act="dp_unlink" data-v="${esc(l.linked_id)}" data-n="${esc(l.linked_name)}">Unlink</button>` : ''}</div>`).join('') || '<p class="muted" id="dp_nolinks">No customers are linked.</p>');
}
function settingsHTML() {
  const owner = !!(D.pol && D.pol.is_owner);
  return '<p class="muted">Both are OFF by default. Every change is written to the change log.</p>' + (D.rules || []).map((r) => {
    const cur = r.value === null || r.value === undefined ? r.default_value : r.value;
    return `<div class="card stack dp-rule" data-key="${esc(r.key)}"><b>${esc(r.label_en)}</b><div class="muted">${esc(r.hint_en)}</div>
      ${owner ? `<label class="row"><input type="checkbox" id="rl_${esc(r.key)}" ${cur === true ? 'checked' : ''}> On</label><button type="button" class="mini" data-act="dp_rulesave" data-v="${esc(r.key)}">Save</button>` : chip(cur === true ? 'On' : 'Off') + '<div class="muted">Only the owner changes this.</div>'}</div>`;
  }).join('');
}
function draw() {
  const el = $('#dp_body'); if (!el) return;
  if (D.err) { el.innerHTML = `<div class="card"><p>${esc(D.err === 'nofn' ? 'phase305.sql has not been run on the server yet.' : D.err === 'denied' ? 'You do not have permission to open this page.' : D.err)}</p></div>`; return; }
  el.innerHTML = tabsBar() + `<div id="dp_pane">${({ list: listHTML, linked: linkedHTML, settings: settingsHTML })[D.tab]()}</div>`;
}
async function loadTab() {
  D.pol = await call('_crmb_policy', {});
  if (D.tab === 'list') D.cand = await call('_crmb_dup_candidates', { p_limit: D.limit, p_offset: 0 });
  if (D.tab === 'linked') D.links = await call('_crmb_links_list', { p_limit: 100, p_include_undone: true });
  if (D.tab === 'settings') { const r = await sb.from('rules').select('key,kind,value,default_value,label_en,hint_en').in('key', RULE_KEYS); D.rules = ((r && r.data) || []).sort((a, b) => RULE_KEYS.indexOf(a.key) - RULE_KEYS.indexOf(b.key)); }
}
async function show(tab) {
  if (tab) D.tab = tab;
  try { D.err = null; await loadTab(); } catch (e) { D.err = missing(e) ? 'nofn' : /permission/i.test(e.message) ? 'denied' : e.message; }
  draw();
}
const act = (fn) => async (a) => { try { await fn(a); } catch (e) { toast(e.message || 'error'); } };
const pairOf = (a, b) => { const r = ((D.cand && D.cand.rows) || []).find((x) => x.a_id === a && x.b_id === b); return r ? [r.a, r.b] : null; };

// ---------------- the person view (customer menu) ----------------
async function sheet(id, name) {
  const g = await call('_crmb_customer_group', { p_customer: id });
  const pol = await call('_crmb_policy', {}).catch(() => ({}));
  D.pol = pol; D.grp = { id, g };
  const m = (g.members || []).map((x) => `<div class="row between dp-member"><div><b>${esc(x.name)}</b> ${x.is_primary ? chip('main') : ''}<div class="muted">${esc(x.mobile || '')}</div></div><div class="mnum">${Number(x.balance) > 0 ? 'owes ' + fm(x.balance) : '-'}</div></div>`).join('');
  openSheet(`<h3>Same person: ${esc(name || '')}</h3><div class="stack" id="dp_sheet">
    ${g.in_group ? `<div class="card stack">${m}<div class="muted">Together: spent ${fm(g.combined.spend)} in ${esc(String(g.combined.orders))} order(s), ${esc(String(g.combined.points))} point(s). ${esc(g.note)}</div></div>`
      : '<p class="muted">This customer is not linked to anyone.</p>'}
    ${pol.can_link ? `<div class="card stack"><b>Link another customer as the same person</b>
        ${fld('dp_other', 'Mobile number of the other customer', '<input id="dp_other" inputmode="tel" autocomplete="off" maxlength="20">')}
        ${fld('dp_why', 'Reason (required)', '<input id="dp_why" maxlength="300" autocomplete="off" placeholder="for example: second number on the paper form">')}
        <button type="button" class="primary full" data-act="dp_linkmobile" data-v="${esc(id)}">Link as the same person</button></div>` : ''}
    <button type="button" class="full" data-act="closesheet">Close</button></div>`);
}
function sameSheet(a, b) {
  const pr = pairOf(a, b); if (!pr) return;
  D.pair = { a, b };
  openSheet(`<h3>Same person</h3><div class="stack" id="dp_samesheet">
    <p class="muted">Choose the customer that stays as the main one. The other is linked under it. Neither customer changes: dues, payments and the books stay where they are.</p>
    <label class="card row"><input type="radio" name="dp_main" value="a" checked> ${person(pr[0])}</label><label class="card row"><input type="radio" name="dp_main" value="b"> ${person(pr[1])}</label>
    ${fld('dp_why', 'Reason (required)', '<input id="dp_why" maxlength="300" autocomplete="off" placeholder="for example: same shop owner, two numbers">')}
    <button type="button" class="primary full" data-act="dp_samego">Link</button><button type="button" class="full" data-act="closesheet">Cancel</button></div>`);
}

Object.assign(H, {
  dp_tab: (a) => show(a.dataset.v),
  dp_more: act(async () => { D.limit += 50; await show(); }),
  dp_same: (a) => sameSheet(a.dataset.a, a.dataset.b),
  dp_samego: act(async () => {
    const why = val('dp_why'); if (why.length < 3) return toast(ERR.reason_required);
    const main = (document.querySelector('input[name=dp_main]:checked') || {}).value === 'b' ? 'b' : 'a';
    const P = D.pair; const primary = main === 'a' ? P.a : P.b, linked = main === 'a' ? P.b : P.a;
    await call('_crmb_link_customers', { p_client: rid(), p_primary: primary, p_linked: linked, p_reason: why });
    closeSheet(); toast('Linked as the same person'); await show('list');
  }),
  dp_not: (a) => {
    D.pair = { a: a.dataset.a, b: a.dataset.b };
    openSheet(`<h3>Not the same person</h3><div class="stack" id="dp_notsheet"><p class="muted">The pair will not be offered again. You can bring it back later.</p>
      ${fld('dp_why', 'Reason (required)', '<input id="dp_why" maxlength="300" autocomplete="off" placeholder="for example: different people, checked with the shop">')}
      <button type="button" class="primary full" data-act="dp_notgo">Save</button><button type="button" class="full" data-act="closesheet">Cancel</button></div>`);
  },
  dp_notgo: act(async () => {
    const why = val('dp_why'); if (why.length < 3) return toast(ERR.reason_required);
    await call('_crmb_dup_review', { p_client: rid(), p_a: D.pair.a, p_b: D.pair.b, p_not_duplicate: true, p_reason: why });
    closeSheet(); toast('Saved'); await show('list');
  }),
  dp_unlink: (a) => {
    D.unl = a.dataset.v;
    openSheet(`<h3>Unlink: ${esc(a.dataset.n || '')}</h3><div class="stack" id="dp_unsheet"><p class="muted">The customer becomes its own person again. Nothing else changes.</p>
      ${fld('dp_why', 'Reason (required)', '<input id="dp_why" maxlength="300" autocomplete="off">')}
      <button type="button" class="primary full" data-act="dp_unlinkgo">Unlink</button><button type="button" class="full" data-act="closesheet">Cancel</button></div>`);
  },
  dp_unlinkgo: act(async () => {
    const why = val('dp_why'); if (why.length < 3) return toast(ERR.reason_required);
    await call('_crmb_unlink_customers', { p_client: rid(), p_linked: D.unl, p_reason: why }); closeSheet(); toast('Unlinked'); await show('linked');
  }),
  dp_linkmobile: act(async (a) => {
    const why = val('dp_why'), mob = val('dp_other'); if (why.length < 3) return toast(ERR.reason_required); if (mob.length < 10) return toast('Write the mobile number of the other customer.');
    const f = await sb.rpc('find_customer', { p_mobile: mob }); if (f.error) throw new Error(eText(f.error)); if (!f.data || !f.data.found) return toast('No customer has that mobile number.');
    // the customer opened here becomes the main one unless it is already linked under another (the server explains)
    await call('_crmb_link_customers', { p_client: rid(), p_primary: a.dataset.v, p_linked: f.data.id, p_reason: why });
    closeSheet(); toast('Linked as the same person');
  }),
  dp_rulesave: act(async (a) => {
    const key = a.dataset.v; const res = await sb.rpc('set_rule', { p_key: key, p_value: !!$('#rl_' + key).checked }); if (res.error) throw new Error(eText(res.error));
    toast('Saved'); await show('settings');
  }),
});

async function view() {
  if (B.loadStatic) await B.loadStatic();
  shell('Duplicate customers', '<div id="dp_body"><p class="muted">…</p></div>', true);
  try { await show(D.tab); } catch (e) { fail(e); }
}
// the extra button of the customer menu (⋮): "Same person" for people who may link (the server decides again)
function menuHTML(row) {
  const pol = B.crmConsent && B.crmConsent.cached ? B.crmConsent.cached() : null;   // the policy the consent file already fetched
  if (!pol || pol.missing || !pol.dup_on || !(pol.can_merge || pol.can_manage_consent) || !row) return '';
  return `<button type="button" class="full" data-act="dp_open" data-v="${esc(row.id)}" data-n="${esc(row.name)}">Same person / duplicates</button>`;
}
H.dp_open = act(async (a) => { closeSheet(); await sheet(a.dataset.v, a.dataset.n); });
B.crmDupes = { sheet, menuHTML };
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { crmdupes: view });
})();
