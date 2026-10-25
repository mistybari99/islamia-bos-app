/* Islamia BOS · Switchboard (#/switchboard): every ON/OFF setting (and every pick-one setting) of the app on ONE searchable page, owner only.
   Reads the rules table, writes only through set_rule (owner, validated and audited on the server). Per-form blind-count and PIN-signature switches use
   blind_cfg_set / pin_sig_cfg_set (supabase/phase18.sql + phase23.sql). Numbers (limits, rates) stay in Settings - this page links there. Nothing is deleted; "back to default" sends null. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, H, nm } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const X = {
  title: L('সুইচবোর্ড — সব চালু/বন্ধ এক জায়গায়', 'Switchboard — every on/off in one place', 'Switchboard — সব on/off এক জায়গায়'),
  search: L('নাম বা কোড দিয়ে খুঁজুন', 'Search by name or key', 'নাম বা key দিয়ে খুঁজুন'), all: L('সব বিভাগ', 'All sections', 'সব section'),
  on: L('চালু', 'ON', 'ON'), off: L('বন্ধ', 'OFF', 'OFF'), changed: L('বদলানো', 'Changed', 'Changed'), onlyChanged: L('শুধু বদলানো', 'Only changed', 'শুধু changed'),
  reset: L('ডিফল্টে ফেরান', 'Back to default', 'Default-এ ফেরান'), saved: L('সেভ হয়েছে', 'Saved', 'Saved'), none: L('কিছু মেলেনি', 'Nothing matches', 'কিছু মেলেনি'),
  perForm: L('ফর্ম / জায়গা অনুযায়ী সুইচ', 'Per form / place switches', 'Form / place অনুযায়ী switch'), blind: L('ব্লাইন্ড কাউন্ট', 'Blind count', 'Blind count'), pin: L('পিন স্বাক্ষর', 'PIN signature', 'PIN signature'),
  blindOff: L('মূল সুইচ "ব্লাইন্ড গণনা" বন্ধ — নিচের সুইচ কাজ করবে না', 'Master "blind count" is OFF - these do nothing', 'Master "blind count" OFF - এগুলো কাজ করবে না'),
  pinOff: L('মূল সুইচ "পিন স্বাক্ষর" বন্ধ — নিচের সুইচ কাজ করবে না', 'Master "PIN signature" is OFF - these do nothing', 'Master "PIN signature" OFF - এগুলো কাজ করবে না'),
  more: L('সংখ্যার সীমা সেটিংসে', 'Numbers and limits are in Settings', 'Number/limit Settings-এ'), count: L('টি', 'items', 'টি'),
  lay: L('লেআউট: ডিফল্ট / সব চালু', 'Layout: default / all on', 'Layout: Default / সব on'), layPick: L('লেআউট বাছুন', 'Choose a layout', 'Layout বাছুন'),
  layDef: L('ডিফল্ট (বর্তমান অ্যাপ)', 'Default (current app)', 'Default (বর্তমান app)'), layAll: L('সব ঐচ্ছিক অংশ দৃশ্যমান', 'All optional sections visible', 'সব optional section visible'),
  layCustom: L('কাস্টম (মিশ্র)', 'Custom (mixed)', 'Custom (মিশ্র)'), laySnap: L('ডিফল্ট স্ন্যাপশট ফাইল নামান', 'Download the defaults snapshot file', 'Defaults snapshot file নামান'),
  layRevert: L('ডিফল্ট স্ন্যাপশটে ফেরান', 'Revert to the defaults snapshot', 'Defaults snapshot-এ ফেরান'),
  layNote: L('শুধু ঐচ্ছিক অংশ দেখানো বা লুকানো হয়। টাকা, হিসাব ও হাজিরার সুইচ এখানে বদলায় না।', 'Only optional sections are shown or hidden. Money, books and attendance switches are not changed here.', 'শুধু optional section দেখানো/লুকানো হয়। টাকা, হিসাব ও attendance-এর switch এখানে বদলায় না।'),
  layDone: L('লেআউট বদলানো হয়েছে', 'Layout changed', 'Layout বদলানো হয়েছে'), laySaved: L('স্ন্যাপশট ফাইল নামানো হয়েছে', 'Snapshot file downloaded', 'Snapshot file নামানো হয়েছে'),
};
// Layout = a named state of OWNER switches that only show optional sections (rules with module "people", default OFF). Money, books, attendance and loyalty
// switches are deliberately NOT in this list: they change what the app does, so they stay on the rule's own row. Nothing new is stored: every change is a set_rule call.
const LAYOUT_KEYS = ['todo_on', 'shift_on', 'announce_on'];
const T = (k) => lab(X[k]);
const D = { rows: [], q: '', mod: '', onlyCh: false, blind: [], pin: [], locs: [] };
const FORMS_BLIND = ['06-1', '03-1', '36-1', '13-1'], FORMS_PIN = ['06-1', '03-1', '36-1'];
const rl = (r) => ({ bn: r.label_bn || r.key, mix: r.label_mix || r.label_bn || r.key, en: r.label_en || r.label_bn || r.key });
const rh = (r) => (r.hint_bn || r.hint_en) ? { bn: r.hint_bn || r.hint_en, mix: r.hint_mix || r.hint_bn || r.hint_en, en: r.hint_en || r.hint_bn } : null;
const cur = (r) => (r.value !== null && r.value !== undefined ? r.value : r.default_value);
const isOn = (r) => cur(r) === true || cur(r) === 'true';
const changed = (r) => r.value !== null && r.value !== undefined && JSON.stringify(r.value) !== JSON.stringify(r.default_value);
const layRow = (k) => D.rows.find((r) => r.key === k);
const layRows = () => LAYOUT_KEYS.map(layRow).filter(Boolean);
const defOn = (r) => r.default_value === true || r.default_value === 'true';   // the defaults snapshot value of a switch
// default = every layout row sits at its default_value; all_on = every layout row is ON; otherwise custom
const layState = () => { const rs = layRows(); if (!rs.length) return 'none'; if (rs.every((r) => !changed(r))) return 'default'; return rs.every(isOn) ? 'all_on' : 'custom'; };
const MOD = { entries: L('ফর্ম ও এন্ট্রি', 'Forms & entries', 'Form ও entry'), stock: L('স্টক', 'Stock', 'Stock'), pos: L('সেল / POS', 'Sales / POS', 'Sales / POS'), lists: L('তালিকা ও অ্যাপ্রুভ', 'Lists & approvals', 'List ও approval'),
  settings: L('সেটিংস', 'Settings', 'Settings'), books: L('অ্যাকাউন্টিং', 'Accounting', 'Accounting'), customers: L('কাস্টমার ও টিয়ার', 'Customers & tiers', 'Customer ও Tier'), notify: L('নোটিফিকেশন ও ব্যাকআপ', 'Notifications & backup', 'Notification ও Backup'), partners: L('অংশীদারি ও বিনিয়োগ', 'Partners & investment', 'Partners ও Investment'), people: L('স্টাফ, হাজিরা ও পে-রোল', 'People, attendance & payroll', 'Staff, হাজিরা ও Payroll'), items: L('আইটেম', 'Items', 'Items'), lists: L('তালিকা', 'Lists', 'Lists'), locations: L('লোকেশন', 'Locations', 'Locations'), purchase: L('ক্রয়', 'Purchases', 'Purchases'), reports: L('রিপোর্ট', 'Reports', 'Reports'), emergency: L('জরুরি', 'Emergency', 'Emergency'), ui: L('দেখতে কেমন (থিম/রং)', 'Look & feel', 'Look & feel'), cash: L('ক্যাশ', 'Cash', 'Cash') };
const modName = (m) => (MOD[m] ? lab(MOD[m]) : m);

async function load() {
  const [r, bc, ps, lc] = await Promise.all([sb.from('rules').select('*').order('sort'), sb.from('blind_count_cfg').select('form_code,location_id,enabled'), sb.from('pin_sig_cfg').select('form_code,enabled'), sb.from('locations').select('id,code,name_bn,name_en,name_mix').order('sort')]);
  D.rows = (r.data || []).filter((x) => x.kind === 'switch' || x.kind === 'choice');
  D.blind = bc.data || []; D.pin = ps.data || []; D.locs = lc.data || [];
}
function visible() {
  const q = D.q.trim().toLowerCase();
  return D.rows.filter((r) => (!D.mod || r.module === D.mod) && (!D.onlyCh || changed(r)) && (!q || (r.key + ' ' + (r.label_bn || '') + ' ' + (r.label_mix || '') + ' ' + (r.label_en || '')).toLowerCase().includes(q)));
}
function rowHTML(r) {
  const h = rh(r), ch = changed(r);
  const ctl = r.kind === 'switch'
    ? `<button type="button" class="tog ${isOn(r) ? 'on' : ''}" role="switch" aria-checked="${isOn(r)}" data-act="sw_set" data-k="${esc(r.key)}" data-v="${isOn(r) ? '0' : '1'}">${esc(isOn(r) ? T('on') : T('off'))}</button>`
    : `<select data-sw-choice="${esc(r.key)}" aria-label="${esc(lab(rl(r)))}">${(Array.isArray(r.choices) ? r.choices : []).map((c) => `<option value="${esc(c)}" ${String(cur(r)) === String(c) ? 'selected' : ''}>${esc(c)}</option>`).join('')}</select>`;
  return `<div class="card sw-row" data-key="${esc(r.key)}"><div class="row between"><div style="min-width:0"><b>${esc(lab(rl(r)))}</b>${B.info ? B.info('rule:' + r.key) : ''}${ch ? ` <span class="chip warn">${esc(T('changed'))}</span>` : ''}
      <div class="muted" style="font-size:.78rem">${esc(r.key)}</div></div>${ctl}</div>${h ? `<div class="muted" style="font-size:.85rem;margin-top:4px">${esc(lab(h))}</div>` : ''}
      ${ch ? `<div class="row" style="margin-top:6px"><button type="button" class="mini" data-act="sw_reset" data-k="${esc(r.key)}">${esc(T('reset'))}</button></div>` : ''}</div>`;
}
const blindOn = (f, loc) => { const x = D.blind.find((b) => b.form_code === f && b.location_id === loc); return x ? x.enabled : true; };
const pinOn = (f) => { const x = D.pin.find((b) => b.form_code === f); return x ? x.enabled : true; };
function perFormHTML() {
  const mB = D.rows.find((r) => r.key === 'blind_count_on'), mP = D.rows.find((r) => r.key === 'pin_signature_on');
  const blind = `<div class="card"><b>${esc(T('blind'))}</b>${mB && !isOn(mB) ? `<div class="notice warn">${esc(T('blindOff'))}</div>` : ''}${FORMS_BLIND.map((f) => `<div class="stack" style="margin-top:6px"><b>${esc(f)}</b><div class="row wrap">${D.locs.map((l) =>
      `<button type="button" class="tog ${blindOn(f, l.id) ? 'on' : ''}" role="switch" aria-checked="${blindOn(f, l.id)}" data-act="sw_blind" data-f="${esc(f)}" data-l="${l.id}" data-v="${blindOn(f, l.id) ? '0' : '1'}">${esc(nm(l))}</button>`).join('')}</div></div>`).join('')}</div>`;
  const pin = `<div class="card"><b>${esc(T('pin'))}</b>${mP && !isOn(mP) ? `<div class="notice warn">${esc(T('pinOff'))}</div>` : ''}<div class="row wrap" style="margin-top:6px">${FORMS_PIN.map((f) =>
      `<button type="button" class="tog ${pinOn(f) ? 'on' : ''}" role="switch" aria-checked="${pinOn(f)}" data-act="sw_pin" data-f="${esc(f)}" data-v="${pinOn(f) ? '0' : '1'}">${esc(f)}</button>`).join('')}</div></div>`;
  return `<details data-ctl="off" id="sw_perform" ${D.openPer ? 'open' : ''}><summary><b>${esc(T('perForm'))}</b></summary>${blind}${pin}</details>`;
}
function layoutHTML() {
  const rs = layRows(); if (!rs.length) return '';
  const st = layState();
  return `<div class="card stack" id="lay_card"><b>${esc(T('lay'))}</b><div class="muted" style="font-size:.85rem">${esc(T('layNote'))}</div>
    <label for="lay_pick">${esc(T('layPick'))}</label>
    <select id="lay_pick">
      <option value="default" ${st === 'default' ? 'selected' : ''}>${esc(T('layDef'))}</option>
      <option value="all_on" ${st === 'all_on' ? 'selected' : ''}>${esc(T('layAll'))}</option>
      <option value="custom" disabled ${st === 'custom' ? 'selected' : ''}>${esc(T('layCustom'))}</option>
    </select>
    <div class="row wrap"><button type="button" data-act="lay_snap">${esc(T('laySnap'))}</button><button type="button" data-act="lay_revert">${esc(T('layRevert'))}</button></div></div>`;
}
// the defaults snapshot as a file on this device: every switch and choice with its current value and its default_value. Nothing is sent anywhere.
function downloadSnapshot() {
  const body = { kind: 'bos-layout-defaults', saved_at: new Date().toISOString(), rules: D.rows.map((r) => ({ key: r.key, module: r.module, kind: r.kind, value: r.value === undefined ? null : r.value, default_value: r.default_value === undefined ? null : r.default_value })) };
  const url = URL.createObjectURL(new Blob([JSON.stringify(body, null, 2)], { type: 'application/json' }));
  const a = document.createElement('a'); a.href = url; a.download = 'bos-layout-defaults-' + body.saved_at.slice(0, 10) + '.json';
  document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 1000);
  toast(T('laySaved'));
}
// target 'default' restores each layout row to its default_value (the snapshot); 'all_on' sets each layout row to ON. Only rows that differ are written.
async function applyLayout(target) {
  if (target !== 'default' && target !== 'all_on') return;
  for (const r of layRows()) {
    const want = target === 'all_on' ? true : defOn(r);
    if (isOn(r) === want) continue;
    const res = await sb.rpc('set_rule', { p_key: r.key, p_value: want }); if (res.error) return fail(res.error);
  }
  toast(T('layDone')); await load(); if (B.reloadRules) await B.reloadRules(); draw();
}
function draw() {
  const mods = [...new Set(D.rows.map((r) => r.module))].sort();
  const rows = visible();
  const el = $('#sw_body'); if (!el) return;
  el.innerHTML = layoutHTML() + `<div class="card stack"><input id="sw_q" type="search" placeholder="${esc(T('search'))}" value="${esc(D.q)}" autocomplete="off" aria-label="${esc(T('search'))}">
      <div class="row wrap"><select id="sw_mod" aria-label="${esc(T('all'))}"><option value="">${esc(T('all'))}</option>${mods.map((m) => `<option value="${esc(m)}" ${D.mod === m ? 'selected' : ''}>${esc(modName(m))}</option>`).join('')}</select>
      <label class="row"><input type="checkbox" id="sw_ch" ${D.onlyCh ? 'checked' : ''}> ${esc(T('onlyChanged'))}</label></div>
      <div class="muted">${rows.length} ${esc(T('count'))} · <a href="#/settings2">${esc(T('more'))}</a></div></div>
    <div id="sw_list">${rows.length ? rows.map(rowHTML).join('') : `<p class="muted">${esc(T('none'))}</p>`}</div>${perFormHTML()}`;
}
async function setRule(k, v) {
  const r = await sb.rpc('set_rule', { p_key: k, p_value: v }); if (r.error) return fail(r.error);
  toast(T('saved')); await load(); if (B.reloadRules) await B.reloadRules(); const keep = $('#sw_q') && document.activeElement === $('#sw_q'); draw(); if (keep) $('#sw_q').focus();
}
Object.assign(H, {
  sw_set: (a) => setRule(a.dataset.k, a.dataset.v === '1'),
  sw_reset: (a) => setRule(a.dataset.k, null),
  lay_snap: () => downloadSnapshot(),
  lay_revert: () => applyLayout('default'),
  sw_blind: async (a) => { const r = await sb.rpc('blind_cfg_set', { p_form: a.dataset.f, p_loc: Number(a.dataset.l), p_enabled: a.dataset.v === '1' }); if (r.error) return fail(r.error); D.openPer = true; toast(T('saved')); await load(); draw(); },
  sw_pin: async (a) => { const r = await sb.rpc('pin_sig_cfg_set', { p_form: a.dataset.f, p_enabled: a.dataset.v === '1' }); if (r.error) return fail(r.error); D.openPer = true; toast(T('saved')); await load(); draw(); },
});
document.addEventListener('input', (e) => { if (e.target.id === 'sw_q') { D.q = e.target.value; const pos = e.target.selectionStart; draw(); const q = $('#sw_q'); if (q) { q.focus(); try { q.setSelectionRange(pos, pos); } catch (x) { /* not all types */ } } } });
document.addEventListener('change', (e) => {
  if (e.target.id === 'lay_pick') applyLayout(e.target.value);
  if (e.target.id === 'sw_mod') { D.mod = e.target.value; draw(); }
  if (e.target.id === 'sw_ch') { D.onlyCh = e.target.checked; draw(); }
  if (e.target.dataset && e.target.dataset.swChoice) setRule(e.target.dataset.swChoice, e.target.value);
});
document.addEventListener('toggle', (e) => { if (e.target && e.target.id === 'sw_perform') D.openPer = e.target.open; }, true);
async function view() {
  shell(T('title'), '<div id="sw_body"><p class="muted">…</p></div>', true);
  try { await load(); draw(); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { switchboard: view });
})();
