/* Islamia BOS · Customer profile, more details (sheet opened from the customer form "More profile details" and from Customer 360 "Edit profile").
   Essentials first: language, preferred outlet, tags. The "More" fold (open/closed remembered on this phone) holds: extra phone numbers, delivery points, family dates, and
   - for the owner or a customer manager - customer type, credit days and the staff member who looks after the customer.
   Server (supabase/phase301.sql, 302.sql): crma_state, crma_customer_360, crma_customer_extras_save, crma_phone_add / retire / make_primary, crma_address_save / retire,
   crma_date_save / retire, crma_tag_save, crma_tag_set. The page only shows; the server checks every right and the owner's switches (crm_on, crm_second_phone_on).
   Every field is optional. English labels only for now (owner rule). 360 px wide. UNVERIFIED on a real phone and on a real Supabase project.
   Hooks for the integrator: docs/integration/CRM-A.md. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, openSheet, closeSheet, H, store } = A;
const $ = (s, el = document) => el.querySelector(s);
B.crm = B.crm || {};
const rid = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3) | 8).toString(16); }));
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).trim();
const val = (id) => (($('#' + id) || {}).value || '').trim();
const sget = (k) => { try { return store.get(k); } catch (e) { return null; } };
const sset = (k, v) => { try { store.set(k, v); } catch (e) { /* private window: not remembered */ } };

const ERR = {
  not_allowed: 'You do not have permission.', crm_off: 'Customer profile extras are switched off. The owner turns them on in Settings.', second_phone_off: 'Extra phone numbers are switched off. The owner turns them on in Settings.',
  bad_mobile: 'The phone number is not valid (01XXXXXXXXX).', bad_value: 'Value is not valid.', bad_number: 'The number is not valid.', bad_date: 'The date is not valid.',
  customer_not_found: 'Customer not found.', location_not_found: 'Outlet not found.', type_not_found: 'Customer type not found.', user_not_found: 'That person is not an active user.',
  too_many_phones: 'No more than 10 extra numbers.', too_many_addresses: 'No more than 20 delivery points.', too_many_dates: 'No more than 30 dates.', address_required: 'Write the address.',
  person_required: 'Write whose date it is (for example Spouse).', reason_required: 'Write a reason (at least 3 characters).', mobile_taken: 'That number is the main number of another customer.',
  code_exists: 'That tag code already exists.', bad_code: 'Tag code: 2-30 lower-case letters, digits or _.', name_required: 'Write a name.', unknown_key: 'The form sent a field the server does not know.',
};
const eText = (e) => { const m = String((e && e.message) || '').replace(/\bnot allowed\b/, 'not_allowed'); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? ERR[k] : m || 'error'; };
async function call(fn, args) {
  const r = await sb.rpc(fn, args || {});
  if (r.error) { const e = new Error(eText(r.error)); e.raw = r.error; throw e; }
  return r.data;
}
const act = (fn) => async (a) => { try { await fn(a); } catch (e) { toast(e.message || 'error'); } };

const D = { id: null, d: null, st: null, locs: [], types: [], tags: [], users: [], done: null, client: rid() };

async function loadAll(id) {
  D.id = id;
  const [st, d] = await Promise.all([call('crma_state'), call('crma_customer_360', { p_customer: id })]);
  D.st = st; D.d = d;
  const jobs = [sb.from('locations').select('id,name_en,name_bn').eq('is_active', true).order('sort'), sb.from('crm_tags').select('id,code,label,active').order('label')];
  if (st.can_manage) jobs.push(sb.from('option_lists').select('value_code,label_en,active').eq('list_code', 'customer_types').order('sort'));
  const res = await Promise.all(jobs.map((j) => j.then((r) => r, () => ({ data: [] }))));
  D.locs = (res[0] && res[0].data) || []; D.tags = ((res[1] && res[1].data) || []).filter((t) => t.active);
  D.types = ((res[2] && res[2].data) || []).filter((t) => t.active);
}

function sheetHTML() {
  const d = D.d, c = d.customer, st = D.st, can = d.can || {}, on = !!st.crm_on, ro = !on || !st.can_write;
  const mine = new Set((d.tags || []).map((t) => String(t.id)));
  const more = sget('crma_more_edit') === '1';
  const dis = ro ? 'disabled' : '';
  const sel = (id, opts, cur) => `<select id="${id}" ${dis}>${opts.map(([v, l]) => `<option value="${esc(v)}" ${String(cur ?? '') === String(v) ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select>`;
  const phones = (d.phones || []).filter((p) => p.kind === 'extra').map((p) => `<div class="row between"><span>${esc(p.phone)}${p.masked ? ' (hidden)' : ''} <span class="muted">${esc(p.label)}${p.wa_ok ? ' · WhatsApp' : ''}${p.shared ? ' · also on another customer' : ''}</span></span>
      <span><button type="button" class="mini" data-act="crmp_phone_retire" data-v="${p.id}" ${dis}>Remove</button>${st.can_manage && !p.masked ? ` <button type="button" class="mini" data-act="crmp_phone_main" data-v="${p.id}">Make main</button>` : ''}</span></div>`).join('');
  const addrs = (d.addresses || []).filter((a) => a.kind === 'extra').map((a) => `<div class="row between"><span>${esc(a.label)}${a.is_default ? ' · default' : ''}: ${a.hidden ? '(hidden)' : esc(a.address)}</span><button type="button" class="mini" data-act="crmp_addr_retire" data-v="${a.id}" ${dis}>Remove</button></div>`).join('');
  const dates = (d.dates || []).filter((x) => !x.own).map((x) => `<div class="row between"><span>${esc(x.person)} · ${esc(x.kind)} · ${x.day}/${x.month}${x.year ? '/' + x.year : ''}</span><button type="button" class="mini" data-act="crmp_date_retire" data-v="${x.id}" ${dis}>Remove</button></div>`).join('');
  return `<h2>More about ${esc(c.name)}</h2>
  ${!on ? '<div class="notice warn" id="crmp_off">Customer profile extras are switched off. The owner turns them on in Settings. You can look but not change.</div>' : ''}
  <div class="stack" id="crmp_form">
    <div><label for="crmp_lang">Language</label>${sel('crmp_lang', [['', 'Not set'], ['bn', 'Bangla'], ['en', 'English']], c.language)}</div>
    <div><label for="crmp_loc">Preferred outlet</label>${sel('crmp_loc', [['', 'Not set']].concat(D.locs.map((l) => [l.id, l.name_en || l.name_bn])), (c.preferred_location || {}).id)}</div>
    <div><label>Tags</label><div class="row wrap" id="crmp_tags" style="gap:.3rem">${D.tags.map((t) => `<button type="button" class="tog ${mine.has(String(t.id)) ? 'on' : ''}" data-act="crmp_tag" data-v="${t.id}" ${dis}>${esc(t.label)}</button>`).join('') || '<span class="muted">No tags yet.</span>'}</div></div>
    <details id="crmp_more" ${more ? 'open' : ''}><summary>More</summary><div class="stack" style="margin-top:8px">
      ${st.can_manage ? `<div><label for="crmp_type">Customer type</label>${sel('crmp_type', [['', 'Not set']].concat(D.types.map((t) => [t.value_code, t.label_en])), c.type_code)}</div>
        <div><label for="crmp_cdays">Credit days (how long they may pay later)</label><input id="crmp_cdays" inputmode="numeric" value="${c.credit_days === null || c.credit_days === undefined ? '' : esc(c.credit_days)}" ${dis}></div>` : ''}
      <div class="stack"><b>Extra phone numbers</b>${st.second_phone_on ? '' : '<div class="muted">Switched off by the owner.</div>'}${phones}
        ${st.second_phone_on ? `<div class="row wrap"><input id="crmp_ph" inputmode="tel" placeholder="01XXXXXXXXX" ${dis} style="flex:2"><select id="crmp_phl" ${dis} style="flex:1"><option value="mobile">Mobile</option><option value="home">Home</option><option value="work">Work</option><option value="other">Other</option></select></div>
        <button type="button" class="full" data-act="crmp_phone_add" ${dis}>Add number</button>` : ''}</div>
      <div class="stack"><b>Delivery points</b>${addrs}
        <div><input id="crmp_ad" placeholder="Address" ${dis}></div><div class="row wrap"><input id="crmp_ar" placeholder="Area" ${dis} style="flex:1"><input id="crmp_alm" placeholder="Landmark" ${dis} style="flex:1"></div>
        <label class="row"><input type="checkbox" id="crmp_adf" ${dis}> Use as the default delivery point</label><button type="button" class="full" data-act="crmp_addr_add" ${dis}>Add delivery point</button></div>
      <div class="stack"><b>Family dates</b>${dates}
        <div class="row wrap"><input id="crmp_dp" placeholder="Whose (for example Spouse)" ${dis} style="flex:2"><select id="crmp_dk" ${dis} style="flex:1"><option value="birthday">Birthday</option><option value="anniversary">Anniversary</option><option value="other">Other</option></select></div>
        <div class="row wrap"><input id="crmp_dd" inputmode="numeric" placeholder="Day" ${dis} style="flex:1"><input id="crmp_dm" inputmode="numeric" placeholder="Month" ${dis} style="flex:1"><input id="crmp_dy" inputmode="numeric" placeholder="Year (optional)" ${dis} style="flex:1"></div>
        <button type="button" class="full" data-act="crmp_date_add" ${dis}>Add date</button></div>
      ${st.can_manage ? `<div class="stack"><b>New tag</b><div class="row wrap"><input id="crmp_tc" placeholder="code (a-z, 0-9, _)" style="flex:1" ${dis}><input id="crmp_tl" placeholder="Name" style="flex:1" ${dis}></div><button type="button" class="full" data-act="crmp_tag_new" ${dis}>Add tag</button></div>` : ''}
    </div></details>
    <div class="row"><button class="full" data-act="crmp_close">Close</button><button class="primary full" data-act="crmp_save" ${dis}>Save</button></div>
  </div>`;
}
async function reopen() { await loadAll(D.id); openSheet(sheetHTML()); }

B.crm.openEdit = async (id, done) => {
  try { D.done = done || null; D.client = rid(); await loadAll(id); openSheet(sheetHTML()); } catch (e) { toast(e.message); }
};

Object.assign(H, {
  crm_more: (a) => { closeSheet(); B.crm.openEdit(a.dataset.v); },        // the button in the customer form
  crmp_close: () => { closeSheet(); if (D.done) D.done(); },
  crmp_save: act(async () => {
    const p = { language: val('crmp_lang') || null, preferred_location_id: val('crmp_loc') || null };
    if ($('#crmp_type')) p.type_code = val('crmp_type') || null;
    if ($('#crmp_cdays')) { const v = norm(val('crmp_cdays')); if (v !== '' && !/^\d{1,3}$/.test(v)) return toast(ERR.bad_number); p.credit_days = v === '' ? null : Number(v); }
    await call('crma_customer_extras_save', { p_id: D.id, p, p_client: D.client });
    D.client = rid(); toast('Saved'); closeSheet(); if (D.done) D.done();
  }),
  crmp_tag: act(async (a) => {
    const on = !(a.classList.contains('on'));
    await call('crma_tag_set', { p_customer: D.id, p_tag: Number(a.dataset.v), p_on: on });
    a.classList.toggle('on', on);
  }),
  crmp_tag_new: act(async () => {
    const code = val('crmp_tc'), label = val('crmp_tl'); if (!label) return toast(ERR.name_required);
    await call('crma_tag_save', { p_id: null, p_code: code, p_label: label, p_active: true }); toast('Saved'); await reopen();
  }),
  crmp_phone_add: act(async () => {
    const ph = norm(val('crmp_ph')); if (!ph) return toast(ERR.bad_mobile);
    const r = await call('crma_phone_add', { p_customer: D.id, p_phone: ph, p_label: val('crmp_phl') || 'mobile', p_wa: false, p_note: null, p_client: rid() });
    toast(r && r.warning === 'phone_shared' ? 'Saved. This number is also on another customer: check for a duplicate.' : r && r.dup ? 'Already there' : 'Saved'); await reopen();
  }),
  crmp_phone_retire: act(async (a) => { await call('crma_phone_retire', { p_phone_id: Number(a.dataset.v) }); toast('Removed'); await reopen(); }),
  crmp_phone_main: (a) => {
    openSheet(`<h2>Make this the main number</h2><p class="muted">The old main number stays on the profile as an extra number. This is written to the change log.</p><div class="stack"><div><label for="pm_why">Reason (at least 3 characters)</label><input id="pm_why" autocomplete="off"></div>
      <div class="row"><button class="full" data-act="crmp_reopen">Cancel</button><button class="primary full" data-act="crmp_phone_maingo" data-v="${esc(a.dataset.v)}">Change</button></div></div>`);
  },
  crmp_reopen: act(async () => { await reopen(); }),
  crmp_phone_maingo: act(async (a) => {
    const why = val('pm_why'); if (why.length < 3) return toast(ERR.reason_required);
    await call('crma_phone_make_primary', { p_phone_id: Number(a.dataset.v), p_reason: why }); toast('Changed'); await reopen();
  }),
  crmp_addr_add: act(async () => {
    const ad = val('crmp_ad'); if (!ad) return toast(ERR.address_required);
    await call('crma_address_save', { p_customer: D.id, p: { address: ad, area: val('crmp_ar') || null, landmark: val('crmp_alm') || null, is_default: !!($('#crmp_adf') && $('#crmp_adf').checked) }, p_id: null, p_client: rid() });
    toast('Saved'); await reopen();
  }),
  crmp_addr_retire: act(async (a) => { await call('crma_address_retire', { p_id: Number(a.dataset.v) }); toast('Removed'); await reopen(); }),
  crmp_date_add: act(async () => {
    const who = val('crmp_dp'); if (!who) return toast(ERR.person_required);
    const dd = norm(val('crmp_dd')), mm = norm(val('crmp_dm')), yy = norm(val('crmp_dy'));
    if (!/^\d{1,2}$/.test(dd) || !/^\d{1,2}$/.test(mm) || (yy !== '' && !/^\d{4}$/.test(yy))) return toast(ERR.bad_date);
    const p = { kind: val('crmp_dk') || 'birthday', person_label: who, month: Number(mm), day: Number(dd) }; if (yy !== '') p.year = Number(yy);
    await call('crma_date_save', { p_customer: D.id, p, p_id: null }); toast('Saved'); await reopen();
  }),
  crmp_date_retire: act(async (a) => { await call('crma_date_retire', { p_id: Number(a.dataset.v) }); toast('Removed'); await reopen(); }),
});
document.addEventListener('toggle', (e) => { if (e.target && e.target.id === 'crmp_more') sset('crma_more_edit', e.target.open ? '1' : '0'); }, true);
})();
