/* Islamia BOS · Delegation board (#/delegation, owner): who holds which delegated right, where, until when - on one page, with remove and add.
   Reads user_grants / grant_defs / profiles; writes only through set_user_grant (owner, audit-logged). A right can be given for one place and an end date. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, H, nm } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const X = {
  title: L('দায়িত্ব বণ্টন (কে কী অধিকার ধরে আছে)', 'Delegation board (who holds what)', 'Delegation board (কে কী অধিকার ধরে)'), search: L('নাম বা অনুমতি খুঁজুন', 'Search person or right', 'নাম বা অধিকার খুঁজুন'),
  allPlaces: L('সব জায়গা', 'All places', 'সব জায়গা'), until: L('শেষ তারিখ', 'Until', 'শেষ তারিখ'), noEnd: L('শেষ ডেট নেই', 'No end date', 'শেষ date নেই'), expired: L('মেয়াদ শেষ', 'Expired', 'মেয়াদ শেষ'),
  soon: L('শিগগির শেষ', 'Ends soon', 'শিগগির শেষ'), remove: L('সরান', 'Remove', 'সরান'), add: L('নতুন দায়িত্ব দিন', 'Give a right', 'নতুন right দিন'), person: L('কাকে', 'To whom', 'কাকে'), right: L('কোন অনুমতি', 'Which right', 'কোন right'),
  place: L('কোন জায়গায়', 'Which place', 'কোন জায়গায়'), give: L('দিন', 'Give', 'দিন'), none: L('কেউ কোনো দায়িত্ব ধরে নেই', 'Nobody holds a delegated right', 'কেউ কোনো right ধরে নেই'), saved: L('সেভ হয়েছে', 'Saved', 'Saved'),
  sure: L('এই অনুমতি সরাবেন?', 'Remove this right?', 'এই right সরাবেন?'), pick: L('বাছুন', 'Choose', 'বাছুন'), count: L('টি', 'rights', 'টি'),
};
const T = (k) => lab(X[k]);
const D = { rows: [], defs: [], people: [], q: '', hint: null };
const locName = (id) => id ? nm(((B.ENV && B.ENV.locs) || []).find((l) => l.id === id) || { name_bn: '#' + id }) : T('allPlaces');
const gl = (d) => lab({ bn: d.label_bn, en: d.label_en || d.label_bn, mix: d.label_mix || d.label_bn });
async function load() {
  const [g, d, p] = await Promise.all([sb.from('user_grants').select('id,user_id,grant_code,location_id,valid_until,note,granted_at'), sb.from('grant_defs').select('grant_code,module,sort,label_bn,label_mix,label_en,window_type').order('sort'), sb.from('profiles').select('id,staff_id,full_name,status').eq('status', 'active').order('full_name')]);
  D.rows = g.data || []; D.defs = d.data || []; D.people = p.data || [];
}
const pname = (id) => { const p = D.people.find((x) => x.id === id); return p ? (p.full_name || p.staff_id) : '—'; };
function draw() {
  const el = $('#dg_body'); if (!el) return;
  const q = D.q.trim().toLowerCase(), now = Date.now(), week = now + 7 * 864e5;
  const rows = D.rows.map((r) => ({ ...r, def: D.defs.find((x) => x.grant_code === r.grant_code) })).filter((r) => r.def && (!q || (pname(r.user_id) + ' ' + gl(r.def) + ' ' + r.grant_code).toLowerCase().includes(q)));
  const by = {}; rows.forEach((r) => { (by[r.grant_code] = by[r.grant_code] || []).push(r); });
  const groups = Object.keys(by).sort((a, b) => (D.defs.find((x) => x.grant_code === a).sort || 0) - (D.defs.find((x) => x.grant_code === b).sort || 0));
  const list = groups.length ? groups.map((c) => { const d = D.defs.find((x) => x.grant_code === c);
    return `<div class="card stack"><b>${esc(gl(d))}</b><div class="muted" style="font-size:.78rem">${esc(c)}</div>${by[c].map((r) => { const exp = r.valid_until ? new Date(r.valid_until).getTime() : null; const st = exp === null ? '' : exp < now ? 'bad' : exp < week ? 'warn' : '';
      return `<div class="row between"><span>${esc(pname(r.user_id))} · ${esc(locName(r.location_id))}<div class="muted" style="font-size:.8rem">${r.valid_until ? esc(T('until')) + ' ' + esc(String(r.valid_until).slice(0, 10)) : esc(T('noEnd'))}${st === 'bad' ? ' · ' + esc(T('expired')) : st === 'warn' ? ' · ' + esc(T('soon')) : ''}</div></span>
        <button class="mini" data-act="dg_remove" data-u="${esc(r.user_id)}" data-c="${esc(c)}" data-l="${r.location_id === null ? '' : r.location_id}">⋮ ${esc(T('remove'))}</button></div>`; }).join('')}</div>`; }).join('') : `<p class="muted center">${esc(T('none'))}</p>`;
  const add = `<details data-ctl="off"><summary><b>＋ ${esc(T('add'))}</b></summary><div class="card stack"><select id="dg_p"><option value="">${esc(T('person'))} — ${esc(T('pick'))}</option>${D.people.map((p) => `<option value="${esc(p.id)}">${esc(p.full_name || p.staff_id)}</option>`).join('')}</select>
    <select id="dg_c"><option value="">${esc(T('right'))} — ${esc(T('pick'))}</option>${D.defs.map((d) => `<option value="${esc(d.grant_code)}">${esc(gl(d))}</option>`).join('')}</select>
    <select id="dg_l"><option value="">${esc(T('allPlaces'))}</option>${((B.ENV && B.ENV.locs) || []).map((l) => `<option value="${l.id}">${esc(nm(l))}</option>`).join('')}</select>
    <div><label for="dg_u">${esc(T('until'))}</label><input id="dg_u" type="date"></div><button class="primary" data-act="dg_add">${esc(T('give'))}</button></div></details>`;
  el.innerHTML = `${D.hint ? `<div class="notice warn" id="dg_hint">${esc(D.hint)}</div>` : ''}<div class="card"><input id="dg_q" type="search" placeholder="${esc(T('search'))}" value="${esc(D.q)}" autocomplete="off"><div class="muted">${rows.length} ${esc(T('count'))}</div></div>${add}${list}`;
}
Object.assign(H, {
  dg_remove: async (a) => { if (!window.confirm(T('sure'))) return; const r = await sb.rpc('set_user_grant', { p_user: a.dataset.u, p_code: a.dataset.c, p_loc: a.dataset.l === '' ? null : Number(a.dataset.l), p_until: null, p_allowed: false, p_note: null });
    if (r.error) return fail(r.error); toast(T('saved')); await load(); draw(); },
  dg_add: async () => { const u = $('#dg_p').value, c = $('#dg_c').value, l = $('#dg_l').value, d = $('#dg_u').value; if (!u || !c) return toast(T('pick'));
    const r = await sb.rpc('set_user_grant', { p_user: u, p_code: c, p_loc: l ? Number(l) : null, p_until: d ? d + 'T23:59:59+06:00' : null, p_allowed: true, p_note: null }); if (r.error) return fail(r.error); toast(T('saved'));
    D.hint = null; try { const h = await sb.rpc('grant_separation_hint', { p_user: u, p_grant: c }); if (h && h.data && h.data.suggest) D.hint = lab({ bn: h.data.message_bn, mix: h.data.message_bn, en: h.data.message_en }); } catch (e) { /* the hint is advice only (phase78); never blocks */ } /* bos78 */
    await load(); draw(); },
});
document.addEventListener('input', (e) => { if (e.target.id === 'dg_q') { D.q = e.target.value; const pos = e.target.selectionStart; draw(); const q = $('#dg_q'); if (q) { q.focus(); try { q.setSelectionRange(pos, pos); } catch (x) { /* ignore */ } } } });
async function view() { D.hint = null; shell(T('title'), '<div id="dg_body"><p class="muted">…</p></div>', true); try { if (B.loadStatic) await B.loadStatic(); await load(); draw(); } catch (e) { fail(e); } }
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { delegation: view });
})();
