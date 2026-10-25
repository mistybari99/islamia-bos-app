/* Islamia BOS · Customer 360 (#/crm360/<customer id>). One screen for one customer: the essentials first (who, tier, spend, last visit, due, points, Call / WhatsApp),
   then four tabs: Overview (type, credit terms, next dates, favourites), Timeline (every touchpoint, newest first, 30 at a time), Contacts (phones, delivery points, family dates, tags),
   Notes (needs the grant crm_view). The sticky bar holds the few actions: Add note, Edit profile, Open dues.
   Server (supabase/phase302.sql, 301.sql): crma_state, crma_customer_360, crma_timeline, crma_note_add, crma_note_retire, crma_phone_reveal.
   The page only shows; the server decides what each person may see (a masked number is never sent to a person without the right) and every write.
   English labels only for now (owner rule). 360 px wide, no horizontal scroll. UNVERIFIED on a real phone and on a real Supabase project.
   Hooks for the integrator (customers.js, ia.js, index.html): docs/integration/CRM-A.md. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, openSheet, closeSheet, H, store } = A;
const $ = (s, el = document) => el.querySelector(s);
B.crm = B.crm || {};
const rid = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3) | 8).toString(16); }));
const fm = (n) => { if (n === null || n === undefined || n === '') return '-'; const v = Number(n); if (!Number.isFinite(v)) return '-'; return (v < 0 ? '-' : '') + Math.abs(v).toLocaleString('en-IN', { minimumFractionDigits: 0, maximumFractionDigits: 2 }); };
const money = (n) => '৳ ' + fm(n);
const dshort = (iso) => (iso ? String(iso).slice(0, 10) : '-');
const chip = (txt, cls) => `<span class="chip ${cls || ''}">${esc(txt)}</span>`;
const val = (id) => (($('#' + id) || {}).value || '').trim();
const sget = (k) => { try { return store.get(k); } catch (e) { return null; } };
const sset = (k, v) => { try { store.set(k, v); } catch (e) { /* private window: not remembered */ } };

const ERR = {
  not_allowed: 'You do not have permission.', crm_off: 'Customer profile extras are switched off. The owner turns them on in Settings.', customer_not_found: 'Customer not found.',
  note_required: 'Write the note first.', reason_required: 'Write a reason (at least 3 characters).', bad_value: 'Value is not valid.', note_not_found: 'Note not found.',
};
const eText = (e) => { const m = String((e && e.message) || '').replace(/\bnot allowed\b/, 'not_allowed'); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? ERR[k] : m || 'error'; };
async function call(fn, args) {
  const r = await sb.rpc(fn, args || {});
  if (r.error) { const e = new Error(eText(r.error)); e.raw = r.error; throw e; }
  return r.data;
}
const act = (fn) => async (a) => { try { await fn(a); } catch (e) { toast(e.message || 'error'); } };

const KIND = { sale: 'Sale', return: 'Return', collection: 'Due paid', order: 'Order', points: 'Points', gift: 'Gift', tier: 'Tier', message: 'Message', note: 'Note', enquiry: 'Enquiry' };
const FILTERS = [['all', 'All'], ['sale', 'Sales'], ['return', 'Returns'], ['collection', 'Dues paid'], ['order', 'Orders'], ['points', 'Points and gifts'], ['message', 'Messages'], ['note', 'Notes']];
const TABS = [['overview', 'Overview'], ['timeline', 'Timeline'], ['contacts', 'Contacts'], ['notes', 'Notes']];

const D = { id: null, d: null, tab: 'overview', tl: { items: [], next: null, more: false, kind: 'all', loaded: false }, notes: null, err: null, shown: {} };

// ---------------- pieces ----------------
function head(d) {
  const c = d.customer, s = d.stats, can = d.can || {};
  const ph = (d.phones || [])[0] || {};
  const callBtn = ph.masked ? `<button type="button" class="full" data-act="crm_reveal">Show number to call</button>`
    : `<a class="tog full" href="tel:${esc(ph.phone || '')}" style="text-align:center;padding:10px">Call</a><a class="tog full" href="https://wa.me/880${esc(String(ph.phone || '').replace(/^0/, ''))}" target="_blank" rel="noopener" style="text-align:center;padding:10px">WhatsApp</a>`;
  return `<div class="card stack" id="c360_head">
    <div class="row wrap" style="gap:6px;align-items:center"><b style="font-size:1.1rem">${esc(c.name)}</b>${c.tier ? chip((c.tier.badge || '') + ' ' + c.tier.name) : ''}${c.type_label ? chip(c.type_label) : ''}${c.active ? '' : chip('Switched off', 'bad')}${(d.tags || []).map((t) => chip(t.label)).join('')}</div>
    <div class="muted" id="c360_phone">${esc(ph.phone || '')}${ph.masked ? ' (hidden)' : ''}</div>
    <div class="row wrap" style="gap:6px">${callBtn}</div>
    <div class="row between"><span>Spent</span><b>${money(s.spend)}</b></div>
    <div class="row between"><span>Last purchase</span><b>${esc(dshort(s.last_sale))}</b></div>
    <div class="row between"><span>Due</span><b>${Number(s.balance) > 0 ? money(s.balance) : '-'}</b></div>
    <div class="row between"><span>Points</span><b>${Number(s.points) || 0}</b></div>
  </div>`;
}
function tabsBar() { return `<div class="row wrap" id="c360_tabs" style="gap:.3rem">${TABS.filter(([k]) => k !== 'notes' || (D.d.can || {}).view).map(([k, l]) => `<button type="button" class="tog ${D.tab === k ? 'on' : ''}" data-act="crm_tab" data-v="${k}">${esc(l)}</button>`).join('')}</div>`; }

function overview(d) {
  const c = d.customer, s = d.stats, nd = d.next_date;
  const more = sget('crma_more_overview') === '1';
  return `<div class="card stack">
    ${nd ? `<div class="row between"><span>Next date</span><b>${esc(nd.person)}${nd.kind === 'anniversary' ? ' anniversary' : nd.kind === 'birthday' ? ' birthday' : ''} · ${esc(dshort(nd.next_date))} (${Number(nd.days_until) === 0 ? 'today' : nd.days_until + ' days'})</b></div>` : ''}
    <div class="row between"><span>Orders</span><b>${Number(s.orders) || 0}</b></div>
    <div class="row between"><span>Average bill</span><b>${s.avg_bill === null || s.avg_bill === undefined ? '-' : money(s.avg_bill)}</b></div>
    ${(d.counts || {}).open_orders ? `<div class="row between"><span>Open online orders</span><b>${d.counts.open_orders}</b></div>` : ''}
    ${(d.counts || {}).messages_waiting ? `<div class="row between"><span>Messages waiting</span><b>${d.counts.messages_waiting}</b></div>` : ''}
  </div>
  <div class="card stack"><b>Usually buys</b>${(d.favourites || []).map((f) => `<div class="row between"><span>${esc(f.name_en || f.name || '')}</span><span class="muted">${f.orders}x${f.qty ? ' · ' + fm(f.qty) + (f.unit ? ' ' + esc(f.unit) : '') : ''}</span></div>`).join('') || '<p class="muted">Nothing bought yet.</p>'}</div>
  <details class="card" id="c360_more" ${more ? 'open' : ''}><summary>More</summary><div class="stack" style="margin-top:8px">
    <div class="row between"><span>Customer type</span><b>${esc(c.type_label || '-')}</b></div>
    <div class="row between"><span>Credit limit</span><b>${c.credit_limit === null || c.credit_limit === undefined ? '-' : money(c.credit_limit)}</b></div>
    <div class="row between"><span>Credit days</span><b>${c.credit_days === null || c.credit_days === undefined ? '-' : c.credit_days}</b></div>
    <div class="row between"><span>Language</span><b>${c.language === 'bn' ? 'Bangla' : c.language === 'en' ? 'English' : '-'}</b></div>
    <div class="row between"><span>Preferred outlet</span><b>${esc((c.preferred_location || {}).name || '-')}</b></div>
    <div class="row between"><span>Looked after by</span><b>${esc((c.owner || {}).name || '-')}</b></div>
    <div class="row between"><span>How they came</span><b>${esc(c.source || '-')}</b></div>
    <div class="row between"><span>Customer since</span><b>${esc(dshort(c.customer_since))}</b></div>
    ${c.note ? `<div class="muted">Old note: ${esc(c.note)}</div>` : ''}
  </div></details>`;
}

function contacts(d) {
  const ph = (d.phones || []).map((p) => `<div class="row between"><span>${esc(p.phone || '')}${p.masked ? ' (hidden)' : ''}</span><span class="muted">${esc(p.kind === 'main' ? 'Main' : p.kind === 'whatsapp' ? 'WhatsApp' : p.label)}${p.wa_ok ? ' · WhatsApp' : ''}${p.shared ? ' · also on another customer' : ''}</span></div>`).join('');
  const ad = (d.addresses || []).map((a) => `<div class="stack" style="gap:2px"><div class="row between"><b>${esc(a.label)}${a.is_default ? ' · default' : ''}</b></div><div>${a.hidden ? '<span class="muted">(hidden)</span>' : esc(a.address || '')}${a.area ? ' · ' + esc(a.area) : ''}</div>${a.landmark ? `<div class="muted">${esc(a.landmark)}</div>` : ''}${a.delivery_note ? `<div class="muted">${esc(a.delivery_note)}</div>` : ''}</div>`).join('<hr>');
  const dt = (d.dates || []).map((x) => `<div class="row between"><span>${esc(x.person)} · ${esc(x.kind)}</span><span class="muted">${esc(dshort(x.next_date))}${x.turning ? ' · turns ' + x.turning : ''}</span></div>`).join('');
  return `<div class="card stack"><b>Phones</b>${ph || '<p class="muted">-</p>'}</div>
    <div class="card stack"><b>Addresses and delivery points</b>${ad || '<p class="muted">No address.</p>'}</div>
    <div class="card stack"><b>Birthdays and dates</b>${dt || '<p class="muted">No dates.</p>'}</div>`;
}

function itemRow(x) {
  const amt = x.amount !== null && x.amount !== undefined ? money(x.amount) : (x.detail && x.detail.points !== undefined ? (x.detail.points > 0 ? '+' : '') + x.detail.points + ' pts' : '');
  const sub = x.kind === 'message' ? `${esc((x.detail || {}).to || '')} · ${esc((x.detail || {}).text || '')}` : x.kind === 'note' || x.kind === 'enquiry' ? esc((x.detail || {}).text || '') + ((x.detail || {}).by ? ' · ' + esc(x.detail.by) : '') : '';
  return `<div class="card stack" style="gap:2px"><div class="row between"><b>${esc(x.title || KIND[x.kind])}</b><b>${esc(amt)}</b></div>
    <div class="row between muted" style="font-size:.85rem"><span>${esc(KIND[x.kind] || x.kind)} · ${esc(dshort(x.at))}</span><span>${esc(x.status && x.status !== 'done' ? x.status : '')}</span></div>${sub ? `<div class="muted" style="font-size:.85rem">${sub}</div>` : ''}</div>`;
}
function timeline() {
  const T = D.tl;
  const f = `<div class="row wrap"><select id="c360_kind" aria-label="Show">${FILTERS.filter(([k]) => k !== 'note' || (D.d.can || {}).view).filter(([k]) => k !== 'message' || (D.d.can || {}).view).map(([k, l]) => `<option value="${k}" ${T.kind === k ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select></div>`;
  return f + (T.items.map(itemRow).join('') || (T.loaded ? '<p class="muted">Nothing yet.</p>' : '<p class="muted">…</p>')) + (T.more ? '<button type="button" class="full" data-act="crm_tlmore">Show more</button>' : '');
}
function notesPane() {
  const n = D.notes;
  if (!n) return '<p class="muted">…</p>';
  return (n.items.map((x) => `<div class="card stack" style="gap:2px"><div class="row between"><b>${esc(x.title)}</b><span class="muted">${esc(dshort(x.at))}</span></div><div>${esc((x.detail || {}).text || '')}</div><div class="row between muted" style="font-size:.85rem"><span>${esc((x.detail || {}).by || '')}</span>
    <button type="button" class="mini" data-act="crm_noteretire" data-v="${esc((x.detail || {}).note_id)}">Retire</button></div></div>`).join('') || '<p class="muted">No notes.</p>') + (n.more ? '<button type="button" class="full" data-act="crm_notemore">Show more</button>' : '');
}
function bar() {
  const can = D.d.can || {};
  return `<div id="c360_bar" style="position:sticky;bottom:0;background:var(--bg,#fff);padding:8px 0;display:flex;gap:6px">
    ${can.view && can.crm_on ? '<button type="button" class="primary full" data-act="crm_noteadd" style="min-height:44px">Add note</button>' : ''}
    ${can.edit ? '<button type="button" class="full" data-act="crm_edit" style="min-height:44px">Edit profile</button>' : ''}
    <button type="button" class="full" data-act="crm_dues" style="min-height:44px">Dues</button></div>`;
}
function draw() {
  const el = $('#c360_body'); if (!el) return;
  if (D.err) { el.innerHTML = `<div class="notice warn">${esc(D.err)}</div>`; return; }
  const d = D.d; if (!d) { el.innerHTML = '<p class="muted">…</p>'; return; }
  const pane = ({ overview: () => overview(d), timeline, contacts: () => contacts(d), notes: notesPane })[D.tab]();
  el.innerHTML = head(d) + tabsBar() + `<div id="c360_pane" class="stack">${pane}</div>` + bar();
}

// ---------------- loading ----------------
async function loadTimeline(more) {
  const T = D.tl;
  const args = { p_customer: D.id, p_limit: 30, p_kinds: T.kind === 'all' ? null : (T.kind === 'points' ? ['points', 'gift', 'tier'] : [T.kind]) };
  if (more && T.next) { args.p_before = T.next.before; args.p_before_key = T.next.key; }
  const r = await call('crma_timeline', args);
  T.items = more ? T.items.concat(r.items || []) : (r.items || []); T.next = r.next; T.more = !!r.has_more; T.loaded = true;
}
async function loadNotes(more) {
  const n = D.notes || { items: [], next: null, more: false };
  const args = { p_customer: D.id, p_limit: 30, p_kinds: ['note'] };
  if (more && n.next) { args.p_before = n.next.before; args.p_before_key = n.next.key; }
  const r = await call('crma_timeline', args);
  D.notes = { items: more ? n.items.concat(r.items || []) : (r.items || []), next: r.next, more: !!r.has_more };
}
async function load(id, tab) {
  D.id = id; D.d = null; D.err = null; D.tab = tab || D.tab || 'overview'; D.tl = { items: [], next: null, more: false, kind: 'all', loaded: false }; D.notes = null;
  draw();
  try { D.d = await call('crma_customer_360', { p_customer: id }); } catch (e) { D.err = e.message; draw(); return; }
  if (D.tab === 'notes' && !(D.d.can || {}).view) D.tab = 'overview';
  try { if (D.tab === 'timeline') await loadTimeline(false); if (D.tab === 'notes') await loadNotes(false); } catch (e) { toast(e.message); }
  draw();
}
B.crm.reload360 = () => (D.id ? load(D.id, D.tab) : null);

// ---------------- actions ----------------
Object.assign(H, {
  crm_tab: act(async (a) => {
    D.tab = a.dataset.v;
    if (D.tab === 'timeline' && !D.tl.loaded) await loadTimeline(false);
    if (D.tab === 'notes' && !D.notes) await loadNotes(false);
    draw();
  }),
  crm_tlmore: act(async () => { await loadTimeline(true); draw(); }),
  crm_notemore: act(async () => { await loadNotes(true); draw(); }),
  crm_edit: () => { if (B.crm.openEdit) B.crm.openEdit(D.id, () => load(D.id, D.tab)); else toast('Profile editor is not loaded.'); },
  crm_dues: () => { location.hash = '#/dues'; },
  crm_noteadd: () => {
    D.noteClient = rid();
    openSheet(`<h2>Add note</h2><div class="stack" id="nt_form"><div><label for="nt_kind">Kind</label><select id="nt_kind"><option value="note">Note</option><option value="call">Phone call</option><option value="visit">Visit</option><option value="message">Message</option><option value="other">Other</option></select></div>
      <div><label for="nt_body">Note</label><textarea id="nt_body" rows="4" maxlength="1000"></textarea></div>
      <div class="row"><button class="full" data-act="closesheet">Cancel</button><button class="primary full" data-act="crm_notego">Save</button></div></div>`);
  },
  crm_notego: act(async () => {
    const body = val('nt_body'); if (!body) return toast(ERR.note_required);
    await call('crma_note_add', { p_customer: D.id, p_body: body, p_kind: val('nt_kind') || 'note', p_client: D.noteClient });
    closeSheet(); toast('Saved'); D.notes = null; D.tl.loaded = false;
    if (D.tab === 'notes') await loadNotes(false); if (D.tab === 'timeline') await loadTimeline(false);
    D.d = await call('crma_customer_360', { p_customer: D.id }); draw();
  }),
  crm_noteretire: (a) => {
    openSheet(`<h2>Retire note</h2><p class="muted">The note stays in the record; it is only hidden from this list.</p><div class="stack"><div><label for="nr_why">Reason (at least 3 characters)</label><input id="nr_why" autocomplete="off"></div>
      <div class="row"><button class="full" data-act="closesheet">Cancel</button><button class="primary full" data-act="crm_noteretirego" data-v="${esc(a.dataset.v)}">Retire</button></div></div>`);
  },
  crm_noteretirego: act(async (a) => {
    const why = val('nr_why'); if (why.length < 3) return toast(ERR.reason_required);
    await call('crma_note_retire', { p_id: Number(a.dataset.v), p_reason: why });
    closeSheet(); toast('Retired'); await loadNotes(false); D.d = await call('crma_customer_360', { p_customer: D.id }); draw();
  }),
  crm_reveal: () => {
    openSheet(`<h2>Show the phone number</h2><p class="muted">Numbers are hidden. Showing one is written to the change log with your reason.</p><div class="stack"><div><label for="rv_why">Reason (at least 3 characters)</label><input id="rv_why" autocomplete="off"></div>
      <div id="rv_out"></div><div class="row"><button class="full" data-act="closesheet">Close</button><button class="primary full" data-act="crm_revealgo">Show</button></div></div>`);
  },
  crm_revealgo: act(async () => {
    const why = val('rv_why'); if (why.length < 3) return toast(ERR.reason_required);
    const r = await call('crma_phone_reveal', { p_customer: D.id, p_reason: why });
    const o = $('#rv_out'); if (o) o.innerHTML = `<a class="tog full" href="tel:${esc(r.mobile)}" style="text-align:center;padding:10px">Call ${esc(r.mobile)}</a>`;
  }),
});
document.addEventListener('toggle', (e) => { if (e.target && e.target.id === 'c360_more') sset('crma_more_overview', e.target.open ? '1' : '0'); }, true);
document.addEventListener('change', (e) => {
  if (e.target && e.target.id === 'c360_kind') { D.tl.kind = e.target.value; D.tl.loaded = false; loadTimeline(false).then(draw, (x) => toast(x.message)); }
});

// ---------------- hooks other screens call ----------------
B.crm.open360 = (id) => { location.hash = '#/crm360/' + id; };
// POS lookup fallback: the typed number is an extra number of a customer
B.crm.findAny = async (mobile) => {
  try { const r = await sb.rpc('crma_find_by_any_phone', { p_phone: mobile }); return r && !r.error && r.data && r.data.found ? r.data : null; } catch (e) { return null; }
};

function view() {
  const id = (location.hash.replace(/^#\/?/, '').split('/')[1] || '').split('?')[0];
  shell('Customer 360', '<div id="c360_body"><p class="muted">…</p></div>', 'customers');
  if (!/^[0-9a-f-]{36}$/i.test(id)) { D.err = 'Open a customer from the customer list.'; D.d = null; draw(); return; }
  load(id).catch(fail);
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { crm360: view });
})();
