/* Islamia BOS · Organization (#/organization): the company tree (Group > legal entity > business > branches / sites / departments / cost centres / projects), owner or grant org_manage only.
   Server (supabase/phase122.sql): org_unit_save(p_id, p_parent, p_kind, p_code, p_name_bn, p_name_en, p_template, p_status, p_from, p_to, p_currency, p_tz, p_attrs, p_le, p_client) -> jsonb {dup,id,code},
   org_unit_deactivate(p_id, p_reason, p_client) -> jsonb; org_tree() returns a FLAT list of rows (parent_id, depth, path, template_status, trade_licence_ref ...); templates from table business_templates (code, name_bn, name_en, status). Nothing is deleted: a unit is deactivated with a reason.
   A template whose status is not_implemented is NEVER shown as ready. No business or brand names are written in this file: every name comes from the data. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const rid = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : 'o' + Date.now().toString(36) + Math.random().toString(36).slice(2, 10));
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const KINDS = {
  group: L('গ্রুপ', 'Group', 'Group'), legal_entity: L('আইনি প্রতিষ্ঠান', 'Legal entity', 'Legal entity'), business: L('ব্যবসা', 'Business', 'Business'), branch: L('শাখা', 'Branch', 'Branch'),
  site: L('সাইট', 'Site', 'Site'), department: L('বিভাগ', 'Department', 'Department'), cost_centre: L('খরচ কেন্দ্র', 'Cost centre', 'Cost centre'), project: L('প্রকল্প', 'Project', 'Project'),
};
// mirrors phase122 _org_parent_ok122 (the server is the judge; this only keeps the pick-lists short). A group cannot be created (seeded once).
const CHILD = { group: ['legal_entity'], legal_entity: ['business'], business: ['branch', 'site', 'department', 'cost_centre', 'project'],
  branch: ['branch', 'site', 'department', 'cost_centre', 'project'], site: ['site', 'department', 'cost_centre', 'project'], department: ['department', 'cost_centre'], cost_centre: ['cost_centre'], project: [] };
const TPL = { available: [L('পাওয়া যায়', 'Available', 'Available'), 'ok'], configured: [L('সাজানো হয়েছে', 'Configured', 'Configured'), 'ok'], needs_setup: [L('সেটআপ লাগবে', 'Needs setup', 'Setup লাগবে'), 'warn'],
  planned: [L('পরিকল্পনায়', 'Planned', 'Planned'), 'muted'], not_implemented: [L('এখনো তৈরি হয়নি', 'Not built yet', 'এখনো তৈরি হয়নি'), 'bad'] };
const X = {
  title: L('প্রতিষ্ঠানের কাঠামো', 'Organization', 'Organization কাঠামো'), add: L('যোগ করুন', 'Add', 'Add'), addRoot: L('নতুন গ্রুপ / ব্যবসা যোগ', 'Add a group or business', 'নতুন group / business যোগ'),
  rename: L('নাম বদল', 'Rename', 'Rename'), off: L('বন্ধ করুন', 'Deactivate', 'Deactivate'), inactive: L('বন্ধ', 'Inactive', 'Inactive'), kind: L('ধরন', 'Kind', 'ধরন'),
  code: L('কোড (ইংরেজি/সংখ্যা)', 'Code (letters / digits)', 'Code (English/সংখ্যা)'), nbn: L('নাম (বাংলা)', 'Name (Bangla)', 'নাম (বাংলা)'), nen: L('নাম (ইংরেজি)', 'Name (English)', 'নাম (English)'),
  tpl: L('ব্যবসার টেমপ্লেট', 'Business template', 'Business template'), none: L('কোনোটি নয়', 'None', 'কোনোটি নয়'), from: L('শুরুর ডেট', 'Effective from', 'শুরুর Date'),
  save: L('সেভ', 'Save', 'Save'), cancel: L('বাতিল', 'Cancel', 'Cancel'), saved: L('সেভ হয়েছে', 'Saved', 'Saved'), offDone: L('বন্ধ করা হয়েছে', 'Deactivated', 'Deactivated'),
  why: L('বন্ধের কারণ', 'Reason', 'বন্ধের কারণ'), offHint: L('কিছু মুছবে না; ইউনিটটি বন্ধ হিসেবে থাকবে।', 'Nothing is deleted; the unit stays as inactive.', 'কিছু মুছবে না; unit inactive থাকবে।'),
  empty: L('এখনো কোনো প্রতিষ্ঠান যোগ করা হয়নি। প্রথমে একটি গ্রুপ বা ব্যবসা যোগ করুন।', 'No organization added yet. Start by adding a group or a business.', 'এখনো কিছু যোগ হয়নি। আগে একটি group বা business যোগ করুন।'),
  noperm: L('এই পাতা শুধু মালিক বা সংশ্লিষ্ট অনুমতিপ্রাপ্তদের জন্য।', 'This page is for the owner or people with the organization right.', 'এই page শুধু owner বা permission-ওয়ালাদের জন্য।'),
  tplNote: L('এই টেমপ্লেট এখনো তৈরি হয়নি, তাই এটি চালু নয়।', 'This template is not built yet, so it is not live.', 'এই template এখনো তৈরি হয়নি, তাই চালু নয়।'),
  child: L('ভেতরে', 'Inside', 'ভেতরে'), lic: L('ট্রেড লাইসেন্স', 'Trade licence', 'Trade licence'), pct: L('মালিকানা %', 'Owner %', 'Owner %'), fy: L('অর্থবছর শুরু', 'Fiscal start', 'Fiscal start'),
};
const T = (k) => lab(X[k]);
const D = { tree: [], flat: new Map(), tpl: [], ok: false };
const ERR = {
  not_allowed: L('অনুমতি নেই', 'Not allowed', 'অনুমতি নেই'), 'not allowed': L('অনুমতি নেই', 'Not allowed', 'অনুমতি নেই'), client_id_needed: L('আবার চেষ্টা করুন', 'Please try again', 'আবার চেষ্টা করুন'), client_id_taken: L('আবার চেষ্টা করুন', 'Please try again', 'আবার চেষ্টা করুন'),
  bad_code: L('কোড ঠিক নয় (ইংরেজি অক্ষর/সংখ্যা, ২-৪০)', 'Code is not valid (letters / digits, 2-40)', 'কোড ঠিক নয় (ইংরেজি অক্ষর/সংখ্যা, ২-৪০)'), code_taken: L('এই কোড আগেই আছে', 'This code is already used', 'এই কোড আগেই আছে'), code_duplicate: L('এই কোড আগেই আছে', 'This code is already used', 'এই কোড আগেই আছে'),
  code_required: L('কোড লিখুন', 'Enter a code', 'কোড লিখুন'), bad_name: L('নাম ঠিক নয় (১-১২০ অক্ষর)', 'Name is not valid (1-120 characters)', 'নাম ঠিক নয় (১-১২০ অক্ষর)'), name_required: L('একটি নাম লিখুন', 'Enter a name', 'একটি নাম লিখুন'),
  bad_kind: L('ধরন ঠিক নয়', 'Kind is not valid', 'ধরন ঠিক নয়'), bad_parent: L('উপরের ইউনিট ঠিক নয়', 'The parent unit is not valid', 'উপরের ইউনিট ঠিক নয়'), parent_inactive: L('উপরের ইউনিট বন্ধ', 'The parent unit is inactive', 'উপরের ইউনিট বন্ধ'),
  bad_parent_kind: L('এই ধরন এই ইউনিটের ভেতরে হয় না', 'This kind cannot go inside that unit', 'এই ধরন এই ইউনিটের ভেতরে হয় না'), parent_cycle: L('নিজের ভেতরে নেওয়া যায় না', 'A unit cannot go inside itself', 'নিজের ভেতরে নেওয়া যায় না'),
  bad_template: L('টেমপ্লেট ঠিক নয়', 'Template is not valid', 'টেমপ্লেট ঠিক নয়'), template_only_for_business: L('টেমপ্লেট শুধু ব্যবসার জন্য', 'A template is only for a business', 'টেমপ্লেট শুধু ব্যবসার জন্য'),
  template_not_implemented: L('এই টেমপ্লেট এখনো তৈরি হয়নি', 'This template is not built yet', 'এই টেমপ্লেট এখনো তৈরি হয়নি'), bad_date: L('ডেট ঠিক নয়', 'Date is not valid', 'Date ঠিক নয়'), bad_status: L('অবস্থা ঠিক নয়', 'Status is not valid', 'অবস্থা ঠিক নয়'),
  kind_fixed: L('ধরন বদলানো যায় না', 'The kind cannot be changed', 'ধরন বদলানো যায় না'), code_fixed: L('কোড বদলানো যায় না', 'The code cannot be changed', 'কোড বদলানো যায় না'), bad_attrs: L('তথ্য ঠিক নয়', 'Details are not valid', 'তথ্য ঠিক নয়'),
  bad_legal: L('আইনি তথ্য ঠিক নয়', 'Legal details are not valid', 'আইনি তথ্য ঠিক নয়'), owner_only: L('এটি শুধু মালিক বদলাতে পারেন', 'Only the owner can change this', 'এটি শুধু মালিক বদলাতে পারেন'), bad_owner_pct: L('মালিকানা % ০ থেকে ১০০ হতে হবে', 'Owner % must be 0 to 100', 'মালিকানা % ০ থেকে ১০০ হতে হবে'),
  legal_only_for_legal_entity: L('এটি শুধু আইনি প্রতিষ্ঠানের জন্য', 'Only for a legal entity', 'এটি শুধু আইনি প্রতিষ্ঠানের জন্য'),
  has_active_children: L('ভেতরে চালু ইউনিট আছে; আগে সেগুলো বন্ধ করুন', 'It still has active units inside; deactivate those first', 'ভেতরে চালু ইউনিট আছে; আগে সেগুলো বন্ধ করুন'),
  has_active_locations: L('এর অধীনে চালু জায়গা (লোকেশন) আছে; আগে সেগুলো সরান বা বন্ধ করুন', 'It still has active places (locations); move or close those first', 'এর অধীনে active location আছে; আগে সেগুলো সরান বা বন্ধ করুন'),
  unit_not_found: L('ইউনিট পাওয়া যায়নি', 'Unit not found', 'Unit পাওয়া যায়নি'), reason_required: L('কারণ লিখুন (কমপক্ষে ৩ অক্ষর)', 'Write a reason (at least 3 characters)', 'কারণ লিখুন (কমপক্ষে ৩ অক্ষর)'), bad_reason: L('কারণ খুব বড়', 'The reason is too long', 'কারণ খুব বড়'),
};
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).sort((x, y) => y.length - x.length).find((x) => m.includes(x)); return k ? lab(ERR[k]) : m || 'error'; };
const isOwner = () => !!(S.ctx && S.ctx.is_owner);
const kl = (k) => (KINDS[k] ? lab(KINDS[k]) : String(k || ''));
const uname = (u) => lab(L(u.name_bn || u.name_en || u.code || '', u.name_en || u.name_bn || u.code || '', u.name_en || u.name_bn || u.code || ''));
const tplOf = (c) => D.tpl.find((t) => t.code === c);
const tplName = (t) => lab(L(t.name_bn || t.name_en || t.name || t.code, t.name_en || t.name_bn || t.name || t.code, t.name_en || t.name_bn || t.name || t.code));
const tplStatus = (n) => (n.template_code ? n.template_status || (tplOf(n.template_code) || {}).status || '' : '');
const tplBadge = (n) => {
  const code = n.template_code; if (!code) return '';
  const t = tplOf(code), stc = tplStatus(n), st = TPL[stc];
  const nm = t ? tplName(t) : code;
  if (!st) return `<span class="chip muted">${esc(nm)}</span>`;
  return `<span class="chip ${st[1]}">${esc(nm)} · ${esc(lab(st[0]))}</span>`;
};

function norm(raw) {
  let a = raw;
  // real shape (phase122 org_tree): a FLAT list of rows {id, parent_id, kind, code, name_bn, name_en, template_code, template_status, status, effective_from, attrs, depth, path, location_ids, trade_licence_ref, owner_pct, fiscal_start, ...}
  if (a && !Array.isArray(a)) a = a.tree || a.units || a.roots || [a];
  const flat = new Map(), roots = [];
  const walk = (n, par) => { if (!n || typeof n !== 'object') return; const o = Object.assign({}, n, { children: [] }); delete o.children; o.children = []; if (o.parent_id === undefined && par) o.parent_id = par.id; flat.set(String(o.id), o); (n.children || []).forEach((c) => walk(c, o)); };
  (a || []).forEach((n) => walk(n, null));
  flat.forEach((o) => { const p = o.parent_id != null ? flat.get(String(o.parent_id)) : null; if (p) p.children.push(o); else roots.push(o); });
  D.flat = flat; D.tree = roots;
}
async function load() {
  const [t, p] = await Promise.all([sb.rpc('org_tree'), sb.from('business_templates').select('*')]);
  if (t.error) throw t.error;
  norm(t.data); D.tpl = p && p.data ? p.data : [];
}
function nodeHTML(n, depth) {
  const off = n.status && n.status !== 'active';
  const lx = n.kind === 'legal_entity' ? [n.trade_licence_ref ? esc(T('lic')) + ': ' + esc(n.trade_licence_ref) : '', n.owner_pct != null ? esc(T('pct')) + ': ' + esc(Number(n.owner_pct)) : '', n.fiscal_start ? esc(T('fy')) + ': ' + esc(n.fiscal_start) : ''].filter(Boolean) : [];
  const le = lx.length ? `<div class="muted">${lx.join(' · ')}</div>` : '';
  const nb = tplStatus(n) === 'not_implemented' ? `<div class="muted">${esc(T('tplNote'))}</div>` : '';
  const acts = off ? '' : `<div class="row" style="flex-wrap:wrap;gap:6px">${(CHILD[n.kind] || []).length ? `<button class="mini" style="min-height:40px" data-act="og_add" data-v="${esc(n.id)}">+ ${esc(T('add'))}</button>` : ''}
      <button class="mini" style="min-height:40px" data-act="og_edit" data-v="${esc(n.id)}">${esc(T('rename'))}</button>${n.kind === 'group' ? '' : `<button class="mini" style="min-height:40px" data-act="og_off" data-v="${esc(n.id)}">${esc(T('off'))}</button>`}</div>${n.kind === 'business' && window.BOS_PLACES135 ? window.BOS_PLACES135.cardHTML(n) : ''}`;
  return `<div class="og-node" data-id="${esc(n.id)}" style="margin-left:${Math.min(depth, 4) * 12}px"><div class="card ${off ? 'muted' : ''}" style="word-break:break-word;overflow-wrap:anywhere">
    <div class="row" style="flex-wrap:wrap;gap:6px;align-items:center"><span class="chip">${esc(kl(n.kind))}</span><b>${esc(uname(n))}</b>${n.code ? `<span class="muted">${esc(n.code)}</span>` : ''}${off ? `<span class="chip muted">${esc(T('inactive'))}</span>` : ''}${tplBadge(n)}</div>
    ${le}${nb}${acts}</div>${n.children.map((c) => nodeHTML(c, depth + 1)).join('')}</div>`;
}
function draw() {
  const el = $('#og_body'); if (!el) return;
  // the single group is seeded; legal entities / businesses are added inside the tree. Only an empty tree (nothing seeded yet) shows the empty text.
  const top = $('#og_top'); if (top) top.innerHTML = window.BOS_PLACES135 ? window.BOS_PLACES135.topHTML() : '';   // phase135: "New business" (owner only)
  el.innerHTML = (D.tree.length ? D.tree.map((n) => nodeHTML(n, 0)).join('') : `<div class="card" id="og_empty"><p class="muted">${esc(T('empty'))}</p></div>`);
}
function tplOptions(sel) {
  const opts = D.tpl.map((t) => { const st = TPL[t.status]; return `<option value="${esc(t.code)}" ${t.code === sel ? 'selected' : ''} ${t.status === 'not_implemented' ? 'disabled' : ''}>${esc(tplName(t))}${st ? ' · ' + esc(lab(st[0])) : ''}</option>`; }).join('');
  return `<option value="">${esc(T('none'))}</option>${opts}`;
}
function formSheet(o) {
  const kinds = o.kinds;
  openSheet(`<h3>${esc(o.title)}</h3><div class="stack" id="og_form">
    <div><label for="og_kind">${esc(T('kind'))}</label><select id="og_kind" ${o.id ? 'disabled' : ''}>${kinds.map((k) => `<option value="${k}" ${k === o.kind ? 'selected' : ''}>${esc(kl(k))}</option>`).join('')}</select></div>
    <div><label for="og_code">${esc(T('code'))}</label><input id="og_code" autocomplete="off" maxlength="24" value="${esc(o.code || '')}"></div>
    <div><label for="og_nbn">${esc(T('nbn'))}</label><input id="og_nbn" autocomplete="off" maxlength="120" value="${esc(o.nbn || '')}"></div>
    <div><label for="og_nen">${esc(T('nen'))}</label><input id="og_nen" autocomplete="off" maxlength="120" value="${esc(o.nen || '')}"></div>
    <div id="og_tplw" ${o.kind === 'business' ? '' : 'hidden'}><label for="og_tpl">${esc(T('tpl'))}</label><select id="og_tpl">${tplOptions(o.tpl)}</select></div>
    <div id="og_lew" ${o.kind === 'legal_entity' ? '' : 'hidden'}><label for="og_lic">${esc(T('lic'))}</label><input id="og_lic" autocomplete="off" maxlength="80" value="${esc(o.lic || '')}">
      ${isOwner() ? `<label for="og_pct">${esc(T('pct'))}</label><input id="og_pct" inputmode="decimal" autocomplete="off" maxlength="8" value="${esc(o.pct == null ? '' : o.pct)}">` : ''}</div>
    <div><label for="og_from">${esc(T('from'))}</label><input id="og_from" type="date" value="${esc(o.from || today())}"></div>
    <div id="og_err" class="muted" role="alert"></div>
    <div class="row"><button class="full" style="min-height:40px" data-act="closesheet">${esc(T('cancel'))}</button><button class="full primary" style="min-height:40px" data-act="og_save" data-id="${esc(o.id || '')}" data-par="${esc(o.parent || '')}">${esc(T('save'))}</button></div></div>`);
  D.client = rid();
}
function showErr(m) { const e = $('#og_err'); if (e) e.textContent = m; else toast(m); }
const CODE_RE = /^[A-Za-z0-9][A-Za-z0-9_-]{1,23}$/;
Object.assign(H, {
  og_add: (a) => { const pid = a.dataset.v || ''; const par = pid ? D.flat.get(String(pid)) : null;
    const kinds = par ? CHILD[par.kind] || [] : []; if (!kinds.length) return;
    formSheet({ title: T('add') + ' · ' + uname(par), kinds, kind: kinds[0], parent: pid }); },
  og_edit: (a) => { const n = D.flat.get(String(a.dataset.v)); if (!n) return;
    D.editing = n; formSheet({ title: T('rename') + ' · ' + uname(n), kinds: [n.kind], kind: n.kind, id: n.id, parent: n.parent_id == null ? '' : n.parent_id, code: n.code, nbn: n.name_bn, nen: n.name_en, tpl: n.template_code, from: n.effective_from, lic: n.trade_licence_ref, pct: n.owner_pct }); },
  og_off: (a) => { const n = D.flat.get(String(a.dataset.v)); if (!n) return;
    openSheet(`<h3>${esc(T('off'))} · ${esc(uname(n))}</h3><div class="stack"><p class="muted">${esc(T('offHint'))}</p><div><label for="og_why">${esc(T('why'))}</label><input id="og_why" autocomplete="off" maxlength="200"></div>
      <div id="og_err" class="muted" role="alert"></div><div class="row"><button class="full" style="min-height:40px" data-act="closesheet">${esc(T('cancel'))}</button><button class="full primary" style="min-height:40px" data-act="og_offgo" data-id="${esc(n.id)}">${esc(T('off'))}</button></div></div>`); },
  og_offgo: async (a) => {
    const why = (($('#og_why') || {}).value || '').trim(); if (why.length < 3) return showErr(lab(ERR.reason_required));
    const r = await sb.rpc('org_unit_deactivate', { p_id: Number(a.dataset.id), p_reason: why, p_client: rid() }); if (r.error) return showErr(eText(r.error));
    closeSheet(); toast(T('offDone')); await refresh(); },
  og_save: async (a) => {
    const id = a.dataset.id ? Number(a.dataset.id) : null, kind = ($('#og_kind') || {}).value, code = (($('#og_code') || {}).value || '').trim();
    const nbn = (($('#og_nbn') || {}).value || '').trim(), nen = (($('#og_nen') || {}).value || '').trim(), from = (($('#og_from') || {}).value || '').trim(), tpl = kind === 'business' ? (($('#og_tpl') || {}).value || '') : '';
    if (!CODE_RE.test(code)) return showErr(lab(ERR.code_required));
    if (!nbn && !nen) return showErr(lab(ERR.name_required));
    if (from && !/^\d{4}-\d{2}-\d{2}$/.test(from)) return showErr(lab(ERR.bad_date));
    const t = tpl && tplOf(tpl); if (t && t.status === 'not_implemented') return showErr(lab(ERR.template_not_implemented));
    let le = null;
    if (kind === 'legal_entity') {
      le = {}; const lic = (($('#og_lic') || {}).value || '').trim(); const pc = (($('#og_pct') || {}).value || '').trim();
      if (lic || id) le.trade_licence_ref = lic;
      if ($('#og_pct') && pc !== '') { const v = Number(pc); if (!Number.isFinite(v) || v < 0 || v > 100) return showErr(lab(ERR.bad_owner_pct)); le.owner_pct = v; }
      if (!Object.keys(le).length) le = null;
    }
    const old = id ? D.flat.get(String(id)) : null;
    const r = await sb.rpc('org_unit_save', { p_client: D.client, p_id: id, p_parent: a.dataset.par ? Number(a.dataset.par) : null, p_kind: kind, p_code: code, p_name_bn: nbn || nen, p_name_en: nen || null,
      p_template: tpl || null, p_attrs: (old && old.attrs) || {}, p_from: from || null, p_le: le });
    if (r.error) return showErr(eText(r.error));
    closeSheet(); toast(T('saved')); await refresh(); },
});
document.addEventListener('change', (e) => { if (e.target && e.target.id === 'og_kind') { const w = $('#og_tplw'); if (w) w.hidden = e.target.value !== 'business'; const l = $('#og_lew'); if (l) l.hidden = e.target.value !== 'legal_entity'; } });
async function refresh() { await load(); draw(); }
// phase135 (web/places135.js) reads the tree through this small door; nothing else is exposed
window.BOS_ORG122 = { flat: () => D.flat, tpl: () => D.tpl, refresh: async () => { if ($('#og_body')) await refresh(); else await load(); } };
async function allowed() {
  if (isOwner()) return true;
  try { const r = await sb.rpc('has_grant', { p_code: 'org_manage' }); return !!(r && !r.error && r.data === true); } catch (e) { return false; }
}
async function view() {
  if (B.loadStatic) await B.loadStatic();
  shell(T('title'), '<div id="og_top" class="stack"></div><div id="og_body" class="stack"><p class="muted">…</p></div>', true);
  try {
    D.ok = await allowed();
    if (!D.ok) { $('#og_body').innerHTML = `<div class="card" id="og_noperm"><p class="muted">${esc(T('noperm'))}</p></div>`; return; }
    await refresh();
  } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { organization: view });
})();
