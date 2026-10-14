/* Islamia BOS · Step W: sales channel create / edit screen (#/saleschannels) for supabase/phase76.sql sales_channel_save + sales_channels_list. OWNER ONLY (the server refuses anyone else).
   A channel is where an order comes from (web form, Facebook, WhatsApp, phone ...). Editing never deletes old orders; a channel is switched off, not erased.
   Handlers are prefixed wch_. English mode has no Bangla letters. Loaded after stepw_common.js. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS = window.BOS || {};
if (!A || !B.w) return;
const { sb, esc, toast, shell, openSheet, closeSheet } = A;
const L = B.L, lab = B.lab, W = B.w;
const $ = (s, el = document) => el.querySelector(s);
const KINDS = [
  ['web_form', L('ওয়েব ফর্ম', 'Web form', 'Web form')], ['facebook', L('ফেসবুক', 'Facebook', 'Facebook')], ['instagram', L('ইনস্টাগ্রাম', 'Instagram', 'Instagram')],
  ['whatsapp', L('হোয়াটসঅ্যাপ', 'WhatsApp', 'WhatsApp')], ['phone', L('ফোন', 'Phone', 'Phone')], ['walkin', L('সরাসরি দোকানে', 'Walk-in', 'Walk-in')], ['other', L('অন্য', 'Other', 'Other')],
];
const X = {
  title: L('সেলের চ্যানেল', 'Sales channels', 'Sales channel'), add: L('নতুন চ্যানেল', 'New channel', 'নতুন channel'), edit: L('বদলান', 'Edit', 'Edit'),
  intro: L('অর্ডার কোন পথে আসে তার তালিকা। চ্যানেল মুছে ফেলা যায় না — বন্ধ করা যায়; পুরনো অর্ডার ঠিক থাকে।', 'Where orders come from. A channel is never deleted - switch it off; old orders stay as they are.', 'Order কোন পথে আসে তার list। Channel delete হয় না — বন্ধ করা যায়; পুরনো order ঠিক থাকে।'),
  ownerOnly: L('শুধু মালিক চ্যানেল বদলাতে পারেন', 'Only the owner can change channels', 'শুধু owner channel বদলাতে পারেন'),
  code: L('কোড (ছোট ইংরেজি অক্ষর, সংখ্যা, _)', 'Code (lowercase letters, digits, _)', 'Code (ছোট English letter, digit, _)'), kind: L('ধরন', 'Type', 'Type'), other: L('অন্য হলে কী', 'If other, what', 'Other হলে কী'),
  name: L('নাম', 'Name', 'Name'), place: L('জায়গা (ফাঁকা = সব)', 'Place (blank = all)', 'Place (ফাঁকা = সব)'), role: L('দায়িত্বপ্রাপ্ত রোল (ঐচ্ছিক)', 'Role in charge (optional)', 'Role in charge (ঐচ্ছিক)'),
  acct: L('অ্যাকাউন্ট রেফারেন্স / পেজ আইডি (ঐচ্ছিক)', 'Account reference / page id (optional)', 'Account reference / page id (ঐচ্ছিক)'), active: L('চালু', 'Active', 'Active'),
  activeHint: L('পরামর্শ: চালু রাখুন; যে পথে আর অর্ডার আসে না শুধু সেটাই বন্ধ করুন — বন্ধ করলেও পুরনো অর্ডার থাকে।', 'Recommendation: keep it active; switch off only a channel that no longer gets orders - old orders stay either way.', 'পরামর্শ: Active রাখুন; যে পথে আর order আসে না শুধু সেটাই বন্ধ করুন — বন্ধ করলেও পুরনো order থাকে।'),
  save: L('সেভ', 'Save', 'Save'), close: L('বন্ধ', 'Close', 'Close'), saved: L('সেভ হয়েছে', 'Saved', 'Saved'), none: L('এখনও কোনো চ্যানেল নেই', 'No channels yet', 'এখনও কোনো channel নেই'),
  off: L('বন্ধ', 'inactive', 'inactive'), allPlaces: L('সব জায়গা', 'All places', 'সব place'), loading: L('লোড হচ্ছে…', 'Loading...', 'Loading…'), none2: L('— নেই —', '- none -', '— নেই —'),
};
const T = (k) => lab(X[k]);
const D = { rows: [], roles: [] };
const kindLabel = (c) => { const k = KINDS.find((z) => z[0] === c.kind); const base = k ? lab(k[1]) : c.kind; return c.kind === 'other' && c.other_text ? base + ': ' + c.other_text : base; };

async function view() {
  shell(T('title'), `<p class="muted">${esc(T('intro'))}</p>${W.own() ? `<button class="primary full" data-act="wch_new">${esc(T('add'))}</button>` : `<div class="notice warn">${esc(T('ownerOnly'))}</div>`}<div id="wch_body"><p class="muted">${esc(T('loading'))}</p></div>`, true);
  await W.locs(); await draw();
}
async function draw() {
  const el = $('#wch_body'); if (!el) return;
  const { data, error } = await sb.rpc('sales_channels_list', { p_all: true });
  if (error) { el.innerHTML = `<div class="notice warn">${esc(W.errText(error) || error.message)}</div>`; return; }
  D.rows = data || [];
  el.innerHTML = D.rows.length ? D.rows.map((c) => `<div class="card ${c.active ? '' : 'muted'}"><div><b>${esc(c.name_bn)}</b> <span class="muted">${esc(c.code)}</span>${c.active ? '' : ` <span class="muted">(${esc(T('off'))})</span>`}</div>
    <div class="muted">${esc(kindLabel(c))} · ${c.location_id ? esc(W.locName(c.location_id)) : esc(T('allPlaces'))}${c.role_code ? ' · ' + esc(c.role_code) : ''}</div>
    ${W.own() ? `<button class="full" data-act="wch_edit" data-v="${esc(c.id)}">${esc(T('edit'))}</button>` : ''}</div>`).join('') : `<p class="muted center pad">${esc(T('none'))}</p>`;
}
async function roles() {
  if (D.roles.length) return D.roles;
  try { const r = await sb.from('roles').select('code,name_bn,name_en').eq('active', true).order('sort'); D.roles = r.data || []; } catch (e) { D.roles = []; }
  return D.roles;
}
async function form(c) {
  const rs = await roles(); c = c || { id: null, code: '', kind: 'whatsapp', other_text: '', name_bn: '', location_id: null, role_code: null, account_ref: '', active: true };
  openSheet(`<h2>${esc(c.id ? T('edit') : T('add'))}</h2>
    <label>${esc(T('code'))}</label><input id="wch_code" maxlength="30" autocapitalize="none" value="${esc(c.code)}">
    <label>${esc(T('kind'))}</label><select id="wch_kind">${KINDS.map(([k, l]) => `<option value="${k}" ${c.kind === k ? 'selected' : ''}>${esc(lab(l))}</option>`).join('')}</select>
    <div id="wch_oth" ${c.kind === 'other' ? '' : 'hidden'}><label>${esc(T('other'))}</label><input id="wch_other" maxlength="60" value="${esc(c.other_text || '')}"></div>
    <label>${esc(T('name'))}</label><input id="wch_name" maxlength="60" value="${esc(c.name_bn)}">
    <label>${esc(T('place'))}</label><select id="wch_loc">${W.locOpts(c.location_id, true)}</select>
    <label>${esc(T('role'))}</label><select id="wch_role"><option value="">${esc(T('none2'))}</option>${rs.map((r) => `<option value="${esc(r.code)}" ${c.role_code === r.code ? 'selected' : ''}>${esc(W.nm(r, 'name_bn', 'name_en'))}</option>`).join('')}</select>
    <label>${esc(T('acct'))}</label><input id="wch_acct" maxlength="120" value="${esc(c.account_ref || '')}">
    <label class="row"><input type="checkbox" id="wch_active" ${c.active ? 'checked' : ''}> ${esc(T('active'))}</label><div class="notice info">${esc(T('activeHint'))}</div>
    <div class="row" style="margin-top:10px"><button class="full" data-act="closesheet">${esc(T('close'))}</button><button class="primary full" data-act="wch_save" data-v="${c.id === null ? '' : esc(c.id)}">${esc(T('save'))}</button></div>`);
}
// the call exactly as the server wants it (also used by the tests)
function args(v) {
  return { p_id: v.id === '' || v.id === null || v.id === undefined ? null : Number(v.id), p_code: String(v.code || '').trim(), p_kind: v.kind, p_other: v.kind === 'other' ? String(v.other || '').trim() : null,
    p_name: String(v.name || '').trim(), p_loc: v.loc === '' || v.loc === null || v.loc === undefined ? null : Number(v.loc), p_role: v.role || null, p_account_ref: String(v.acct || '').trim() || null, p_active: !!v.active };
}
async function save(id) {
  const g = (s) => ($(s) || {}).value;
  const a = args({ id, code: g('#wch_code'), kind: g('#wch_kind'), other: g('#wch_other'), name: g('#wch_name'), loc: g('#wch_loc'), role: g('#wch_role'), acct: g('#wch_acct'), active: !!($('#wch_active') || {}).checked });
  if (!/^[a-z0-9_]{2,30}$/.test(a.p_code)) return toast(W.errText({ message: 'bad_code' }));
  if (!a.p_name || a.p_name.length > 60) return toast(W.errText({ message: 'name_required' }));
  if (a.p_kind === 'other' && !a.p_other) return toast(W.errText({ message: 'other_text_required' }));
  const { error } = await sb.rpc('sales_channel_save', a);
  if (error) return W.err(error);
  closeSheet(); toast(T('saved')); return draw();
}
A.H = A.H || {};
Object.assign(A.H, {
  wch_new: () => form(null),
  wch_edit: (a) => form(D.rows.find((c) => String(c.id) === String(a.dataset.v))),
  wch_save: (a) => save(a.dataset.v),
});
document.addEventListener('change', (e) => { if (e.target && e.target.id === 'wch_kind') { const o = $('#wch_oth'); if (o) o.hidden = e.target.value !== 'other'; } });
B.chanedit = { X, T, KINDS, args, save };
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { saleschannels: view });
})();
