/* Islamia BOS · Locations (#/locations) + settings sheet versions (#/locsheet) + limit helpers (BOS.LOC).
   Owner, or anyone holding the delegable grants location_manage / head_management (settings_approve for the sheet approval).
   Every rule is enforced on the server (supabase/phase16.sql); this page only guides.  Nothing is deleted: a place is paused or closed, never removed.
   Per place (⋮): edit, setup steps, start / pause / resume, close, switch active, hub on/off, supplied by, settings sheet.  + Add showroom wizard. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, t, esc, toast, fail, shell, openSheet, closeSheet, nm } = A;
const H = A.H, L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).trim();
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const isOwner = () => !!(S.ctx && S.ctx.is_owner);

const X = {
  title: L('লোকেশন', 'Locations', 'Location'), back: L('কন্ট্রোল সেন্টার', 'Control Center', 'Control Center'),
  add: L('＋ নতুন শোরুম', '＋ Add showroom', '＋ নতুন Showroom'), search: L('নাম বা কোড খুঁজুন…', 'Search name or code…', 'Name বা code খুঁজুন…'),
  all: L('সব', 'All', 'All'), planned: L('পরিকল্পিত', 'Planned', 'Planned'), setting_up: L('সেটআপ চলছে', 'Setting up', 'Setting up'), live: L('চালু', 'Live', 'Live'), paused: L('বিরতি', 'Paused', 'Paused'), closed: L('বন্ধ', 'Closed', 'Closed'),
  showroom: L('শোরুম', 'Showroom', 'Showroom'), factory: L('কারখানা', 'Factory', 'Factory'), godown: L('গোডাউন', 'Godown', 'Godown'), hub: L('হাব', 'Hub', 'Hub'), online: L('অনলাইন', 'Online', 'Online'), other: L('অন্য', 'Other', 'Other'),
  hubchip: L('হাব', 'Hub', 'Hub'), inactive: L('নিষ্ক্রিয়', 'Inactive', 'Inactive'), model: L('মডেল', 'Model', 'Model'), kind: L('ধরন', 'Kind', 'Kind'),
  code: L('কোড (বদলানো যায় না)', 'Code (cannot be changed)', 'Code (বদলানো যায় না)'), nbn: L('বাংলা নাম', 'Bangla name', 'বাংলা নাম'), nen: L('ইংরেজি নাম', 'English name', 'English নাম'), nmix: L('Bng-Eng নাম (ঐচ্ছিক)', 'Bng-Eng name (optional)', 'Bng-Eng নাম (ঐচ্ছিক)'),
  opening: L('পরিকল্পিত খোলার তারিখ (YYYY-MM-DD)', 'Planned opening (YYYY-MM-DD)', 'Planned opening (YYYY-MM-DD)'), note: L('নোট', 'Note', 'Note'), sort: L('ক্রম', 'Order', 'Order'), supby: L('কে সরবরাহ করে', 'Supplied by', 'Supplied by'), none: L('— কেউ নয় —', '— none —', '— none —'),
  save: L('সংরক্ষণ', 'Save', 'Save'), cancel: L('বাতিল', 'Cancel', 'Cancel'), close: L('বন্ধ করুন', 'Close', 'Close'), saved: L('সংরক্ষিত', 'Saved', 'Saved'), more: L('আরও', 'More', 'More'), next: L('পরের ধাপ ›', 'Next ›', 'Next ›'), prev: L('‹ আগের', '‹ Back', '‹ Back'),
  m_edit: L('সম্পাদনা', 'Edit', 'Edit'), m_steps: L('সেটআপ ধাপ (১৭)', 'Setup steps (17)', 'Setup steps (17)'), m_start: L('চালু করুন', 'Start (go live)', 'Start (go live)'), m_pause: L('বিরতি দিন', 'Pause', 'Pause'), m_resume: L('আবার চালু', 'Resume', 'Resume'), m_close: L('স্থায়ীভাবে বন্ধ', 'Close for good', 'Close for good'),
  m_active: L('সক্রিয়', 'Active', 'Active'), m_inactive: L('নিষ্ক্রিয় করুন', 'Switch inactive', 'Switch inactive'), m_activate: L('সক্রিয় করুন', 'Switch active', 'Switch active'), m_hub_on: L('হাব হিসেবে চিহ্নিত', 'Set as hub', 'Set as hub'), m_hub_off: L('হাব চিহ্ন সরান', 'Remove hub mark', 'Remove hub mark'),
  m_sup: L('কে সরবরাহ করে', 'Supplied by', 'Supplied by'), m_sheet: L('সেটিংস শিট (সীমা) ও সংস্করণ', 'Settings sheet (limits) and versions', 'Settings sheet (limits) ও versions'), m_init: L('১৭ ধাপের তালিকা শুরু করুন', 'Start the 17-step checklist', '17-step checklist শুরু'),
  reason: L('কারণ (আবশ্যক)', 'Reason (required)', 'Reason (আবশ্যক)'), warn_t: L('আগে এগুলো মেটান', 'Settle these first', 'আগে এগুলো মেটান'), override: L('তবুও করুন (শুধু মালিক, কারণ লিখে)', 'Do it anyway (owner only, with a reason)', 'তবুও করুন (শুধু owner, reason সহ)'),
  w_title: L('নতুন শোরুম যোগ', 'Add a showroom', 'নতুন Showroom যোগ'), w1: L('১. নাম ও ধরন', '1. Name and kind', '1. Name ও kind'), w2: L('২. মডেল, সরবরাহ, তারিখ', '2. Model, supply, date', '2. Model, supply, date'), w3: L('৩. দেখে নিন', '3. Check', '3. Check'),
  w_code: L('কোড হবে', 'The code will be', 'Code হবে'), w_hint: L('সংরক্ষণ করলে ১৭টি সেটআপ ধাপ, ফাঁকা সেটিংস শিট (সংস্করণ ১) তৈরি হবে এবং জায়গাটি “পরিকল্পিত” থাকবে।', 'On save: 17 setup steps and a blank settings sheet (version 1) are created; the place stays “Planned”.', 'Save করলে 17 setup step ও blank settings sheet (version 1) তৈরি হবে; place “Planned” থাকবে।'),
  steps: L('সেটআপ ধাপ', 'Setup steps', 'Setup steps'), done_of: L('সম্পন্ন', 'done', 'done'), owner_yes: L('মালিকের হ্যাঁ লাগবে', "needs the owner's yes", 'owner-এর yes লাগবে'), optional: L('ঐচ্ছিক', 'optional', 'optional'),
  gate: L('১–১৫ ধাপ শেষ না হলে ১৬ (চালু) বন্ধ থাকে', 'Step 16 (start) stays locked until steps 1-15 are done', 'Step 1-15 শেষ না হলে 16 (start) locked'), nosteps: L('এই জায়গার জন্য ধাপের তালিকা নেই।', 'No checklist for this place yet.', 'এই place-এর checklist নেই।'),
  noLoc: L('কোনো লোকেশন নেই', 'No locations', 'কোনো location নেই'), paused_why: L('বিরতির কারণ', 'Paused because', 'Paused কারণ'), closed_why: L('বন্ধের কারণ', 'Closed because', 'Closed কারণ'),
  e_name_in_use: L('এই নামে লোকেশন আছে', 'A place with this name exists', 'এই নামে location আছে'), e_code_in_use: L('এই কোড আছে বা আগে ব্যবহার হয়েছে; কোড আবার দেওয়া হয় না', 'This code is in use or was used before; codes are never reused', 'এই code আছে বা আগে ব্যবহার হয়েছে'),
  e_supplied_by_loop: L('সরবরাহের চক্র হয়ে যাচ্ছে', 'That would make a supply loop', 'Supply loop হয়ে যাচ্ছে'), e_supplied_by_itself: L('নিজে নিজেকে সরবরাহ করা যায় না', 'A place cannot supply itself', 'নিজে নিজেকে supply করা যায় না'),
  e_name_required: L('নাম দিন', 'Enter a name', 'Name দিন'), e_bad_date: L('তারিখ ঠিক নয়', 'Date is not valid', 'Date ঠিক নয়'), e_bad_model: L('এই মডেল এখন চালু নেই', 'This model is not switched on', 'এই model চালু নেই'), e_reason_required: L('কারণ লিখুন', 'Write a reason', 'Reason লিখুন'),
  e_owner_only_step: L('এই ধাপে শুধু মালিকের হ্যাঁ', 'Only the owner can tick this step', 'এই step শুধু owner tick করবেন'), e_steps_open: L('১–১৫ ধাপ শেষ করুন', 'Finish steps 1-15 first', 'Step 1-15 আগে শেষ করুন'), e_closed_is_final: L('বন্ধ করা জায়গা আর খোলা যায় না', 'A closed place cannot be reopened', 'Closed place আর খোলা যায় না'),
  e_not_allowed: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'), e_owner_override_only: L('শুধু মালিক এটা পার করতে পারেন', 'Only the owner can override this', 'শুধু owner override করতে পারেন'), e_maker_cannot_approve: L('যিনি খসড়া বানিয়েছেন তিনি নিজে অনুমোদন করতে পারেন না', 'The maker cannot approve their own draft', 'Maker নিজের draft approve করতে পারেন না'),
  e_effective_before_previous: L('কার্যকর তারিখ আগের সংস্করণের আগে হতে পারে না', 'Effective date cannot be before the previous version', 'Effective date আগের version-এর আগে হবে না'), e_sheet_not_draft: L('এটা আর খসড়া নয়', 'This is no longer a draft', 'এটা আর draft নয়'),
  e_bad_number: L('সংখ্যা ঠিক নয়', 'Number is not valid', 'সংখ্যা ঠিক নয়'), e_bad_value: L('মান ঠিক নয়', 'Value is not valid', 'Value ঠিক নয়'), e_location_paused: L('এই জায়গা বিরতিতে/বন্ধ — নতুন এন্ট্রি হবে না', 'This place is paused or closed — no new entries', 'এই place paused/closed — নতুন entry হবে না'),
  e_bad_transition: L('এই অবস্থা থেকে ওই অবস্থায় যাওয়া যায় না', 'That status change is not allowed from here', 'এই status change এখান থেকে হবে না'), e_newer_version_exists: L('এর মধ্যে নতুন সংস্করণ অনুমোদিত হয়েছে — নতুন খসড়া শুরু করুন', 'A newer version was approved meanwhile — start a new draft', 'এর মধ্যে নতুন version approve হয়েছে — নতুন draft শুরু করুন'),
  e_unknown_key: L('এই সেটিংস-কী চেনা নেই', 'This settings key is not known', 'এই settings key চেনা নেই'), e_effective_too_early: L('কার্যকর তারিখ জায়গা তৈরির আগে হতে পারে না', 'Effective date cannot be before the place was created', 'Effective date place তৈরির আগে হবে না'),
  e_effective_too_far: L('কার্যকর তারিখ এক বছরের বেশি দূরে', 'Effective date is more than a year ahead', 'Effective date এক বছরের বেশি দূরে'), e_supplier_not_active: L('এই জায়গা সক্রিয় নয় বা বন্ধ — সরবরাহকারী হতে পারে না', 'That place is inactive or closed — it cannot be a supplier', 'এই place active নয়/closed — supplier হবে না'),
  e_place_paused: L('জায়গাটি বিরতিতে — আগে ইচ্ছা করে আবার চালু করুন', 'The place is paused — resume it on purpose first', 'Place paused — আগে ইচ্ছা করে resume করুন'), e_bad_key: L('সেটিংস-কী ঠিক নয়', 'Settings key is not valid', 'Settings key ঠিক নয়'),
  m_override: L('দেরিতে আসা কাজের জন্য সাময়িক অনুমতি (মালিক)', 'Allow late work for a while (owner)', 'Late work-এর জন্য সাময়িক অনুমতি (owner)'), ov_done: L('সাময়িক অনুমতি দেওয়া হয়েছে', 'Late-work window opened', 'Late-work window খোলা হয়েছে'), ov_min: L('কত মিনিট', 'Minutes', 'Minutes'),
  w_open_dues: L('বাকিতে বিক্রির টাকা এখনও আদায় হয়নি', 'Credit sales not yet collected', 'Credit sale এখনও আদায় হয়নি'), w_stock_on_hand: L('মজুত মাল আছে', 'Stock on hand', 'Stock on hand'), w_open_entries: L('খোলা এন্ট্রি', 'Open entries', 'Open entries'),
  w_transfers_in_transit: L('পথে থাকা ট্রান্সফার', 'Transfers in transit', 'Transfers in transit'), w_setup_steps_open: L('সেটআপ ধাপ বাকি', 'Setup steps still open', 'Setup steps বাকি'), w_not_first_of_month: L('চালু করা যায় শুধু মাসের ১ তারিখে', 'A new place may start only on the 1st of a month', 'Start শুধু মাসের ১ তারিখে'),
  // settings sheet
  sh_title: L('সেটিংস শিট ০-১ — সংস্করণ', 'Settings sheet 0-1 — versions', 'Settings sheet 0-1 — versions'), sh_hint: L('প্রতিটি পরিবর্তন নতুন সংস্করণ। খসড়া → অনুমোদন। ফাঁকা ঘর = “তথ্য লাগবে”। পুরোনো সংস্করণ পড়া যায়।', 'Every change is a new version: draft → approval. A blank cell = “Data needed”. Old versions stay readable.', 'প্রতিটি change নতুন version: draft → approval। ফাঁকা = “Data লাগবে”। পুরোনো version পড়া যায়।'),
  sh_new: L('নতুন সংস্করণ (খসড়া) শুরু', 'Start a new version (draft)', 'নতুন version (draft) শুরু'), sh_draft: L('খসড়া', 'Draft', 'Draft'), sh_approved: L('অনুমোদিত', 'Approved', 'Approved'), sh_discarded: L('বাতিল খসড়া', 'Discarded draft', 'Discarded draft'), sh_inforce: L('এখন কার্যকর', 'in force', 'in force'),
  sh_eff: L('কার্যকর তারিখ', 'Effective from', 'Effective from'), sh_filled: L('পূরণ', 'filled', 'filled'), sh_blank: L('ফাঁকা', 'blank', 'blank'), sh_save: L('খসড়া সংরক্ষণ', 'Save draft', 'Save draft'), sh_approve: L('অনুমোদন করুন', 'Approve this version', 'Approve this version'), sh_discard: L('খসড়া বাতিল', 'Discard draft', 'Discard draft'),
  sh_view: L('দেখুন', 'View', 'View'), sh_need: L('তথ্য লাগবে', 'Data needed', 'Data লাগবে'), sh_old: L('পুরোনো সংস্করণ (শুধু পড়া)', 'Old version (read only)', 'Old version (read only)'), sh_maker: L('বানিয়েছেন', 'by', 'by'), sh_oldlink: L('সংস্করণ ও অনুমোদন ›', 'Versions & approval ›', 'Versions ও approval ›'),
  sh_blockmsg: L('সীমা ফাঁকা (তথ্য লাগবে) — আগে সেটিংস শিট পূরণ করুন', 'A limit is blank (Data needed) — fill the settings sheet first', 'Limit ফাঁকা (Data লাগবে) — আগে settings sheet পূরণ করুন'),
  sh_noacc: L('এই পাতা দেখার অনুমতি নেই', 'You cannot open this page', 'এই page দেখার permission নেই'), sh_none: L('কোনো সংস্করণ নেই', 'No versions', 'কোনো version নেই'),
};
const T = (k) => lab(X[k]);
const KINDS = ['showroom', 'factory', 'godown', 'hub', 'online', 'other'];
const STATUSES = ['planned', 'setting_up', 'live', 'paused', 'closed'];
const TONE = { planned: 'info', setting_up: 'info', live: 'ok', paused: 'warn', closed: 'bad' };
const errText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(X).filter((x) => x.startsWith('e_')).find((x) => m.includes(x.slice(2)) || m.includes(x.slice(2).replace(/_/g, ' '))); return k ? T(k) : null; };
const fx = (e) => { const m = errText(e); if (m) { toast(m); return; } if (/location_paused/.test((e && e.message) || '')) return toast(T('e_location_paused')); fail(e); };

const D = { locs: [], steps: {}, models: [], f: 'all', q: '', mgr: false, sheets: {}, ready: false };
const freeCode = (name) => { const base = slug(name); let c = base, n = 1; const used = new Set(D.locs.map((x) => x.code)); while (used.has(c)) { n += 1; c = base.slice(0, 26) + '_' + n; } return c; };
const slug = (p) => { const s = String(p || '').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 30); return /^[a-z]/.test(s) && s.length >= 2 ? s : 'loc'; };

async function load() {
  const [lr, sr, mr] = await Promise.all([sb.from('locations').select('*').order('sort'), sb.from('location_setup_steps').select('location_id,step_no,done,optional').then((r) => r, () => ({ data: [] })),
    sb.from('option_lists').select('value_code,label_bn,label_en,label_mix,active,sort').eq('list_code', 'location_models').order('sort').then((r) => r, () => ({ data: [] }))]);
  if (lr.error) { fail(lr.error); return false; }
  D.locs = lr.data || []; D.models = (mr && mr.data) || [];
  D.steps = {}; ((sr && sr.data) || []).forEach((x) => { (D.steps[x.location_id] = D.steps[x.location_id] || []).push(x); });
  D.mgr = isOwner() || await A.hasAnyGrant(['location_manage', 'head_management']);
  D.ready = true; return true;
}
const locById = (id) => D.locs.find((l) => l.id === Number(id));
const stepsInfo = (id) => { const s = D.steps[id] || []; return { n: s.filter((x) => x.done).length, total: s.length }; };
const modelName = (code) => { const m = D.models.find((x) => x.value_code === code); return m ? lab({ bn: m.label_bn, en: m.label_en, mix: m.label_mix || m.label_bn }) : code; };

// ---------- list ----------
async function view() {
  shell(T('title'), `<p class="muted">${esc(t('loading'))}</p>`, 'control');
  if (!(await load())) return;
  if (!D.mgr) return shell(T('title'), `<div class="notice bad">${esc(T('sh_noacc'))}</div>`, 'control');
  draw();
}
function draw() {
  const q = D.q.trim().toLowerCase();
  const rows = D.locs.filter((l) => (D.f === 'all' || l.status === D.f) && (!q || (l.code + ' ' + (l.name_bn || '') + ' ' + (l.name_en || '') + ' ' + (l.name_mix || '')).toLowerCase().includes(q)));
  const cnt = (s) => D.locs.filter((l) => s === 'all' || l.status === s).length;
  shell(T('title'), `<div class="row between"><b>${D.locs.length}</b><button class="primary" data-act="lo_wiz">${esc(T('add'))}</button></div>
    <input id="lo_q" type="search" autocomplete="off" placeholder="${esc(T('search'))}" value="${esc(D.q)}">
    <div class="row wrap" id="lo_chips" data-ctl="select">${['all', ...STATUSES].map((s) => `<button class="tog ${D.f === s ? 'on' : ''}" data-act="lo_filter" data-v="${s}">${esc(T(s))} ${cnt(s)}</button>`).join('')}</div>
    <div id="lo_list">${rows.length ? rows.map(card).join('') : `<p class="muted">${esc(T('noLoc'))}</p>`}</div>`, 'control');
}
function card(l) {
  const si = stepsInfo(l.id), pending = l.status === 'planned' || l.status === 'setting_up';
  const why = l.status === 'paused' && l.paused_reason ? `<div class="muted" style="font-size:.85rem">${esc(T('paused_why'))}: ${esc(l.paused_reason)}</div>` : l.status === 'closed' && l.closed_reason ? `<div class="muted" style="font-size:.85rem">${esc(T('closed_why'))}: ${esc(l.closed_reason)}</div>` : '';
  const sup = l.supplied_by && locById(l.supplied_by) ? `<span class="chip">${esc(T('supby'))}: ${esc(nm(locById(l.supplied_by)))}</span>` : '';
  return `<div class="card item mk ${TONE[l.status] || ''}" data-loc="${l.id}" data-status="${esc(l.status)}"><div style="flex:1;min-width:0"><div class="nm">${esc(nm(l))}</div>
    <div class="sub">${esc(l.code)} · ${esc(l.kind ? T(l.kind) : '')} · ${esc(T('model'))} ${esc(modelName(l.model))}</div>
    <div class="row wrap" style="gap:6px;margin-top:4px"><span class="chip ${TONE[l.status] || ''}">${esc(T(l.status))}</span>${l.hub_functions ? `<span class="chip info">${esc(T('hubchip'))}</span>` : ''}${l.is_active ? '' : `<span class="chip">${esc(T('inactive'))}</span>`}${sup}${pending && si.total ? `<span class="chip warn">${si.n}/${si.total} ${esc(T('done_of'))}</span>` : ''}</div>${why}</div>
    <button class="mini" data-act="lo_menu" data-v="${l.id}" aria-label="${esc(T('more'))}">⋮</button></div>`;
}
document.addEventListener('input', (e) => { if (e.target && e.target.id === 'lo_q' && /^#\/locations/.test(location.hash)) { D.q = e.target.value; const box = $('#lo_list'); if (box) { const q = D.q.trim().toLowerCase(); const rows = D.locs.filter((l) => (D.f === 'all' || l.status === D.f) && (!q || (l.code + ' ' + (l.name_bn || '') + ' ' + (l.name_en || '') + ' ' + (l.name_mix || '')).toLowerCase().includes(q))); box.innerHTML = rows.length ? rows.map(card).join('') : `<p class="muted">${esc(T('noLoc'))}</p>`; } } });

// ---------- ⋮ menu ----------
const mbtn = (act, label, attrs) => `<button class="full" style="margin-top:8px;text-align:left" data-act="${act}" ${attrs || ''}>${esc(label)}</button>`;
function menu(id) {
  const l = locById(id); if (!l) return;
  const closed = l.status === 'closed', hasSteps = (D.steps[l.id] || []).length > 0;
  openSheet(`<h2>${esc(nm(l))}</h2><div class="muted">${esc(l.code)} · ${esc(T(l.status))}</div>
    ${closed ? '' : mbtn('lo_edit', T('m_edit'), `data-v="${l.id}"`)}
    ${hasSteps ? mbtn('lo_steps', `${T('m_steps')} · ${stepsInfo(l.id).n}/${stepsInfo(l.id).total}`, `data-v="${l.id}"`) : (closed ? '' : mbtn('lo_stepsinit', T('m_init'), `data-v="${l.id}"`))}
    ${l.status === 'planned' || l.status === 'setting_up' ? mbtn('lo_status', T('m_start'), `data-v="${l.id}" data-to="live"`) : ''}
    ${l.status === 'live' || l.status === 'setting_up' ? mbtn('lo_status', T('m_pause'), `data-v="${l.id}" data-to="paused"`) : ''}
    ${l.status === 'paused' ? mbtn('lo_status', T('m_resume'), `data-v="${l.id}" data-to="live"`) : ''}
    ${closed ? '' : mbtn('lo_status', T('m_close'), `data-v="${l.id}" data-to="closed"`)}
    ${closed ? '' : mbtn('lo_active', l.is_active ? T('m_inactive') : T('m_activate'), `data-v="${l.id}"`)}
    ${closed ? '' : mbtn('lo_hub', l.hub_functions ? T('m_hub_off') : T('m_hub_on'), `data-v="${l.id}"`)}
    ${closed ? '' : mbtn('lo_supsheet', T('m_sup'), `data-v="${l.id}"`)}
    ${isOwner() && (l.status === 'paused' || l.status === 'closed') ? mbtn('lo_override', T('m_override'), `data-v="${l.id}"`) : ''}
    ${mbtn('lo_sheetgo', T('m_sheet'), `data-v="${l.id}"`)}
    <button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('close'))}</button>`);
}
const sel = (id, opts, cur, blank) => `<select id="${id}">${blank !== undefined ? `<option value="">${esc(blank)}</option>` : ''}${opts.map(([v, l]) => `<option value="${esc(v)}" ${String(v) === String(cur ?? '') ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select>`;
const modelOpts = (cur) => D.models.filter((m) => m.active || m.value_code === cur).map((m) => [m.value_code, modelName(m.value_code)]);
const kindOpts = () => KINDS.map((k) => [k, T(k)]);

function editSheet(id) {
  const l = locById(id); if (!l) return;
  openSheet(`<h2>${esc(T('m_edit'))}</h2><div class="stack">
    <div><label>${esc(T('code'))}</label><input value="${esc(l.code)}" disabled></div>
    <div><label>${esc(T('nbn'))}</label><input id="e_bn" value="${esc(l.name_bn || '')}"></div><div><label>${esc(T('nen'))}</label><input id="e_en" value="${esc(l.name_en || '')}"></div><div><label>${esc(T('nmix'))}</label><input id="e_mix" value="${esc(l.name_mix || '')}"></div>
    <div><label>${esc(T('kind'))}</label>${sel('e_kind', kindOpts(), l.kind)}</div><div><label>${esc(T('model'))}</label>${sel('e_model', modelOpts(l.model), l.model)}</div>
    <div><label>${esc(T('opening'))}</label><input id="e_open" inputmode="numeric" value="${esc(l.planned_opening || '')}"></div>
    <div><label>${esc(T('sort'))}</label><input id="e_sort" inputmode="numeric" value="${esc(l.sort ?? '')}"></div>
    <div><label>${esc(T('note'))}</label><input id="e_note" value="${esc(l.note || '')}"></div>
    <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="lo_edit_save" data-v="${l.id}">${esc(T('save'))}</button></div></div>`);
}
async function saveEdit(id) {
  const patch = { name_bn: $('#e_bn').value, name_en: $('#e_en').value, name_mix: $('#e_mix').value, kind: $('#e_kind').value, model: $('#e_model').value, planned_opening: norm($('#e_open').value) || null, note: $('#e_note').value };
  const so = norm($('#e_sort').value); if (so !== '') { if (!/^\d{1,4}$/.test(so)) return toast(T('e_bad_number')); patch.sort = Number(so); }
  const r = await sb.rpc('location_save', { p_id: Number(id), p_patch: patch }); if (r.error) return fx(r.error);
  closeSheet(); toast(T('saved')); await reload();
}
async function reload() { await load(); if (/^#\/locations/.test(location.hash)) draw(); }

// ---------- status: start / pause / resume / close (server returns warnings; the owner may override) ----------
function statusSheet(id, to, warnings, reason) {
  const l = locById(id); if (!l) return;
  const needReason = to === 'paused' || to === 'closed' || (warnings && warnings.length);
  const wl = (warnings || []).map((w) => `<li>${esc(T('w_' + w.code))}${w.steps ? ': ' + esc(w.steps.join(', ')) : ''}${w.amount ? ': ৳ ' + esc(w.amount) : ''}${w.items ? ': ' + esc(w.items) : ''}${w.count ? ': ' + esc(w.count) : ''}</li>`).join('');
  openSheet(`<h2>${esc(nm(l))} · ${esc(T(to === 'live' ? (l.status === 'paused' ? 'm_resume' : 'm_start') : to === 'paused' ? 'm_pause' : 'm_close'))}</h2>
    ${wl ? `<div class="notice warn"><b>${esc(T('warn_t'))}</b><ul style="margin:6px 0 0;padding-inline-start:18px">${wl}</ul></div>` : ''}
    ${needReason ? `<div><label>${esc(T('reason'))}</label><input id="st_reason" value="${esc(reason || '')}"></div>` : ''}
    <div class="stack" style="margin-top:10px"><button class="primary full" data-act="lo_status_go" data-v="${l.id}" data-to="${to}" data-ov="0">${esc(T('save'))}</button>
    ${wl && isOwner() ? `<button class="danger full" data-act="lo_status_go" data-v="${l.id}" data-to="${to}" data-ov="1">${esc(T('override'))}</button>` : ''}
    <button class="full" data-act="closesheet">${esc(T('cancel'))}</button></div>`);
}
async function doStatus(id, to, ov) {
  const reasonEl = $('#st_reason'), reason = reasonEl ? reasonEl.value.trim() : '';
  if ((to === 'paused' || to === 'closed' || ov) && !reason) return toast(T('e_reason_required'));
  const r = await sb.rpc('location_set_status', { p_id: Number(id), p_status: to, p_reason: reason || null, p_override: !!ov });
  if (r.error) return fx(r.error);
  if (r.data && r.data.ok === false) return statusSheet(id, to, r.data.warnings || [], reason);
  closeSheet(); toast(T('saved')); await reload();
}

// ---------- setup steps ----------
async function stepsSheet(id) {
  const l = locById(id); if (!l) return;
  const r = await sb.from('location_setup_steps').select('*').eq('location_id', Number(id)).order('step_no'); if (r.error) return fail(r.error);
  const st = r.data || []; D.steps[l.id] = st;
  const n = st.filter((x) => x.done).length, ow = isOwner();
  const nm_ = (x) => (S.lang === 'en' ? x.title : x.title_bn);
  openSheet(`<h2>${esc(T('steps'))} · ${esc(nm(l))}</h2><div class="muted">${n}/${st.length} ${esc(T('done_of'))}</div><div class="notice ok" style="margin:8px 0">${esc(T('gate'))}</div>
    <div style="max-height:56vh;overflow:auto">${st.map((x) => `<div class="card mk ${x.done ? 'ok' : (x.owner_yes ? 'warn' : '')}" data-step="${x.step_no}"><div class="row between"><div style="flex:1"><b>${x.step_no}.</b> ${esc(nm_(x))}
      <div class="muted" style="font-size:.8rem">${esc(x.owner_role || '')}${x.owner_yes ? ' · ' + esc(T('owner_yes')) : ''}${x.optional ? ' · ' + esc(T('optional')) : ''}</div></div>
      <button class="tog ${x.done ? 'on' : ''}" data-act="lo_step" data-loc="${l.id}" data-v="${x.step_no}" data-done="${x.done ? 0 : 1}" ${x.owner_yes && !ow ? 'disabled' : ''} aria-label="${esc(x.done ? 'done' : 'todo')}">${x.done ? '✓' : '○'}</button></div></div>`).join('')}</div>
    <button class="full" style="margin-top:10px" data-act="closesheet">${esc(T('close'))}</button>`);
}
async function stepToggle(loc, step, done) {
  const r = await sb.rpc('location_step_set', { p_loc: Number(loc), p_step: Number(step), p_done: !!done }); if (r.error) return fx(r.error);
  if (r.data && r.data.ok === false) { const w = (r.data.warnings || [])[0]; toast(w ? T('w_' + w.code) : T('e_steps_open')); }
  await load(); await stepsSheet(loc); if (/^#\/locations/.test(location.hash)) draw();
}

// ---------- add showroom wizard ----------
const W = { n: 1, d: {} };
function wizSheet() {
  const d = W.d, stp = W.n;
  const sup = D.locs.filter((x) => x.status !== 'closed' && x.is_active).map((x) => [x.id, nm(x)]);
  const body = stp === 1 ? `<div><label>${esc(T('nbn'))}</label><input id="w_bn" value="${esc(d.name_bn || '')}"></div><div><label>${esc(T('nen'))}</label><input id="w_en" value="${esc(d.name_en || '')}"></div>
      <div><label>${esc(T('kind'))}</label>${sel('w_kind', kindOpts(), d.kind || 'showroom')}</div>`
    : stp === 2 ? `<div><label>${esc(T('model'))}</label>${sel('w_model', modelOpts(d.model || 'A'), d.model || 'A')}</div><div><label>${esc(T('supby'))}</label>${sel('w_sup', sup, d.supplied_by, T('none'))}</div>
      <div><label>${esc(T('opening'))}</label><input id="w_open" inputmode="numeric" value="${esc(d.planned_opening || '')}"></div><div><label>${esc(T('note'))}</label><input id="w_note" value="${esc(d.note || '')}"></div>`
    : `<div class="card stack"><b>${esc(d.name_bn || d.name_en || '')}</b><div>${esc(d.name_en || '')}</div><div class="muted">${esc(T(d.kind || 'showroom'))} · ${esc(T('model'))} ${esc(modelName(d.model || 'A'))}${d.supplied_by ? ' · ' + esc(T('supby')) + ': ' + esc(nm(locById(d.supplied_by))) : ''}${d.planned_opening ? ' · ' + esc(d.planned_opening) : ''}</div>
       <div>${esc(T('w_code'))}: <b id="w_code">${esc(freeCode(d.name_en))}</b></div></div><div class="notice ok">${esc(T('w_hint'))}</div>`;
  openSheet(`<h2>${esc(T('w_title'))}</h2><div class="muted">${esc(T('w' + stp))}</div><div class="stack" style="margin-top:8px">${body}
    <div class="row">${stp > 1 ? `<button class="full" data-act="lo_wiz_prev">${esc(T('prev'))}</button>` : `<button class="full" data-act="closesheet">${esc(T('cancel'))}</button>`}
    ${stp < 3 ? `<button class="primary full" data-act="lo_wiz_next">${esc(T('next'))}</button>` : `<button class="primary full" data-act="lo_wiz_save">${esc(T('save'))}</button>`}</div></div>`);
}
function wizRead() {
  const d = W.d, g = (id) => { const e = $('#' + id); return e ? e.value : undefined; };
  if (W.n === 1) { d.name_bn = (g('w_bn') || '').trim(); d.name_en = (g('w_en') || '').trim(); d.kind = g('w_kind'); }
  if (W.n === 2) { d.model = g('w_model'); d.supplied_by = g('w_sup') ? Number(g('w_sup')) : null; d.planned_opening = norm(g('w_open') || '') || null; d.note = (g('w_note') || '').trim(); }
}
async function wizSave() {
  const d = W.d, patch = { name_bn: d.name_bn, name_en: d.name_en || null, kind: d.kind || 'showroom', model: d.model || 'A', supplied_by: d.supplied_by || null, planned_opening: d.planned_opening || null, note: d.note || null };
  const r = await sb.rpc('location_save', { p_id: null, p_patch: patch }); if (r.error) return fx(r.error);
  closeSheet(); toast(T('saved')); await reload(); if (r.data && r.data.id) stepsSheet(r.data.id);
}

// ---------- settings sheet versions (#/locsheet) ----------
const SH = { loc: null, view: null, edit: null, vals: {}, sheets: [], canApprove: false };
const defs = () => (B.SETTING_DEFS || []).filter((d) => !d.hidden);
const fmtv = (v) => (v === null || v === undefined || v === '' ? '' : typeof v === 'object' ? JSON.stringify(v) : String(v));
async function viewSheet() {
  shell(T('sh_title'), `<p class="muted">${esc(t('loading'))}</p>`, 'control');
  try { await B.loadStatic(); } catch (e) { /* defaults */ }
  const ok = isOwner() || await A.hasAnyGrant(['settings_approve', 'head_management', 'location_manage']);
  if (!ok) return shell(T('sh_title'), `<div class="notice bad">${esc(T('sh_noacc'))}</div>`, 'control');
  SH.canApprove = isOwner() || await A.hasAnyGrant(['settings_approve']);
  const locs = (B.ENV && B.ENV.locs) || (await sb.from('locations').select('*').order('sort')).data || [];
  if (!SH.loc || !locs.find((l) => l.id === SH.loc)) SH.loc = (locs[0] || {}).id;
  SH.view = null; SH.edit = null; SH.locs = locs;
  await drawSheet();
}
async function drawSheet() {
  const r = await sb.rpc('sheet_list', { p_loc: SH.loc }); if (r.error) return fail(r.error);
  SH.sheets = r.data || [];
  const draft = SH.sheets.find((s) => s.status === 'draft');
  const versions = SH.sheets.map((s) => `<div class="card item mk ${s.status === 'draft' ? 'warn' : s.in_force ? 'ok' : ''}" data-sheet="${s.id}"><div style="flex:1"><div class="nm">v${s.version} · ${esc(T('sh_' + (s.status)))}${s.in_force ? ' · ' + esc(T('sh_inforce')) : ''}</div>
      <div class="sub">${s.effective_from ? esc(T('sh_eff')) + ' ' + esc(s.effective_from) + ' · ' : ''}${s.filled} ${esc(T('sh_filled'))} · ${s.blank} ${esc(T('sh_blank'))}${s.note ? ' · ' + esc(s.note) : ''}</div></div>
      <button class="mini" data-act="lo_sh_open" data-v="${s.id}" data-st="${esc(s.status)}">${esc(s.status === 'draft' ? T('m_edit') : T('sh_view'))}</button></div>`).join('');
  shell(T('sh_title'), `<div class="notice ok">${esc(T('sh_hint'))}</div>
    <select id="sh_loc">${(SH.locs || []).map((l) => `<option value="${l.id}" ${l.id === SH.loc ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select>
    ${draft ? '' : `<button class="primary full" data-act="lo_sh_new" style="margin-top:8px">${esc(T('sh_new'))}</button>`}
    <div id="sh_list" style="margin-top:8px">${versions || `<p class="muted">${esc(T('sh_none'))}</p>`}</div><div id="sh_edit"></div>`, 'control');
}
document.addEventListener('change', (e) => { if (e.target && e.target.id === 'sh_loc') { SH.loc = Number(e.target.value); SH.edit = null; drawSheet(); } });
async function openSheetVersion(id, st) {
  const r = await sb.from('settings_values').select('key,value').eq('sheet_id', Number(id)); if (r.error) return fail(r.error);
  const vals = {}; (r.data || []).forEach((x) => { vals[x.key] = x.value; });
  const meta = SH.sheets.find((s) => s.id === Number(id)) || {};
  const keys = [...new Set([...defs().map((d) => d.key), ...Object.keys(vals)])];
  const label = (k) => { const d = (B.SETTING_DEFS || []).find((x) => x.key === k); return d ? lab(d.label) : k; };
  const edit = st === 'draft';
  const rows = keys.map((k) => { const v = vals[k], blank = v === null || v === undefined || v === '';
    return `<div class="card stack" data-key="${esc(k)}"><div class="row between"><b>${esc(label(k))}</b>${blank ? `<span class="chip warn">${esc(T('sh_need'))}</span>` : ''}</div>${edit ? `<input id="shv_${esc(k)}" data-k="${esc(k)}" value="${esc(fmtv(v))}">` : `<div>${blank ? '—' : esc(fmtv(v))}</div>`}</div>`; }).join('');
  SH.edit = { id: Number(id), st, vals };
  const box = $('#sh_edit'); if (!box) return;
  box.innerHTML = `<h2>v${meta.version || ''} ${edit ? '' : '· ' + esc(T('sh_old'))}</h2>${rows}
    ${edit ? `<div class="card stack"><button class="primary full" data-act="lo_sh_save">${esc(T('sh_save'))}</button>
      ${SH.canApprove ? `<div><label>${esc(T('sh_eff'))}</label><input id="sh_eff" inputmode="numeric" value="${today()}"></div><button class="primary full" data-act="lo_sh_approve">${esc(T('sh_approve'))}</button>` : ''}
      <button class="danger full" data-act="lo_sh_discard">${esc(T('sh_discard'))}</button></div>` : ''}`;
  box.scrollIntoView && box.scrollIntoView();
}
function collect() {
  const out = {}; document.querySelectorAll('#sh_edit input[data-k]').forEach((el) => {
    const k = el.dataset.k, raw = norm(el.value), d = (B.SETTING_DEFS || []).find((x) => x.key === k), old = SH.edit.vals[k];
    let v = null; if (raw !== '') { if ((d && d.kind === 'number') || (typeof old === 'number')) { v = Number(raw); if (!Number.isFinite(v)) { v = NaN; } } else v = raw; }
    out[k] = v; });
  return out;
}
async function shSave(quiet) {
  const vals = collect(); if (Object.values(vals).some((v) => Number.isNaN(v))) { toast(T('e_bad_number')); return false; }
  const changed = {}; Object.keys(vals).forEach((k) => { const o = SH.edit.vals[k]; if ((o === undefined ? null : o) !== vals[k]) changed[k] = vals[k]; });
  if (Object.keys(changed).length) { const r = await sb.rpc('sheet_set', { p_sheet: SH.edit.id, p_values: changed }); if (r.error) { fx(r.error); return false; } }
  if (!quiet) toast(T('saved')); return true;
}

Object.assign(H, {
  lo_filter: (a) => { D.f = a.dataset.v; draw(); },
  lo_menu: (a) => menu(a.dataset.v),
  lo_edit: (a) => editSheet(a.dataset.v),
  lo_edit_save: (a) => saveEdit(a.dataset.v),
  lo_status: (a) => { closeSheet(); statusSheet(a.dataset.v, a.dataset.to, null); },
  lo_status_go: (a) => doStatus(a.dataset.v, a.dataset.to, a.dataset.ov === '1'),
  lo_active: async (a) => { const l = locById(a.dataset.v); const r = await sb.rpc('location_set_active', { p_id: l.id, p_active: !l.is_active }); if (r.error) return fx(r.error); closeSheet(); toast(T('saved')); await reload(); },
  lo_hub: async (a) => { const l = locById(a.dataset.v); const r = await sb.rpc('location_save', { p_id: l.id, p_patch: { hub_functions: !l.hub_functions } }); if (r.error) return fx(r.error); closeSheet(); toast(T('saved')); await reload(); },
  lo_supsheet: (a) => { const l = locById(a.dataset.v); openSheet(`<h2>${esc(T('m_sup'))} · ${esc(nm(l))}</h2><div class="stack">${sel('sp_sel', D.locs.filter((x) => x.id !== l.id && x.status !== 'closed' && x.is_active).map((x) => [x.id, nm(x)]), l.supplied_by, T('none'))}
      <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="lo_sup_save" data-v="${l.id}">${esc(T('save'))}</button></div></div>`); },
  lo_sup_save: async (a) => { const v = $('#sp_sel').value; const r = await sb.rpc('location_save', { p_id: Number(a.dataset.v), p_patch: { supplied_by: v ? Number(v) : null } }); if (r.error) return fx(r.error); closeSheet(); toast(T('saved')); await reload(); },
  lo_sheetgo: (a) => { SH.loc = Number(a.dataset.v); closeSheet(); location.hash = '#/locsheet'; },
  lo_override: (a) => { const l = locById(a.dataset.v); openSheet(`<h2>${esc(T('m_override'))} · ${esc(nm(l))}</h2><div class="stack"><div><label>${esc(T('reason'))}</label><input id="ov_reason"></div><div><label>${esc(T('ov_min'))}</label><input id="ov_min" inputmode="numeric" value="30"></div>
      <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="lo_override_go" data-v="${l.id}">${esc(T('save'))}</button></div></div>`); },
  lo_override_go: async (a) => { const reason = $('#ov_reason').value.trim(); if (!reason) return toast(T('e_reason_required')); const mins = Number(norm($('#ov_min').value));
    const r = await sb.rpc('location_block_override', { p_loc: Number(a.dataset.v), p_reason: reason, p_minutes: mins }); if (r.error) return fx(r.error); closeSheet(); toast(T('ov_done')); },
  lo_steps: (a) => { closeSheet(); stepsSheet(a.dataset.v); },
  lo_stepsinit: async (a) => { const r = await sb.rpc('location_steps_init', { p_id: Number(a.dataset.v) }); if (r.error) return fx(r.error); closeSheet(); await reload(); stepsSheet(a.dataset.v); },
  lo_step: (a) => stepToggle(a.dataset.loc, a.dataset.v, a.dataset.done === '1'),
  lo_wiz: () => { W.n = 1; W.d = {}; wizSheet(); },
  lo_wiz_next: () => { wizRead(); if (W.n === 1 && !(W.d.name_bn || W.d.name_en)) return toast(T('e_name_required')); W.n += 1; wizSheet(); },
  lo_wiz_prev: () => { wizRead(); W.n -= 1; wizSheet(); },
  lo_wiz_save: () => wizSave(),
  lo_sh_new: async () => { const r = await sb.rpc('sheet_draft', { p_loc: SH.loc }); if (r.error) return fx(r.error); await drawSheet(); openSheetVersion(r.data, 'draft'); },
  lo_sh_open: (a) => openSheetVersion(a.dataset.v, a.dataset.st),
  lo_sh_save: async () => { if (await shSave()) { const id = SH.edit.id; await drawSheet(); openSheetVersion(id, 'draft'); } },
  lo_sh_approve: async () => { if (!(await shSave(true))) return; const eff = norm(($('#sh_eff') || {}).value || '') || null;
    const r = await sb.rpc('sheet_approve', { p_sheet: SH.edit.id, p_effective: eff, p_note: null }); if (r.error) return fx(r.error); toast(T('saved')); SH.edit = null; delete (B.ENV && B.ENV.byLoc || {})[SH.loc]; await drawSheet(); },
  lo_sh_discard: async () => { const r = await sb.rpc('sheet_discard', { p_sheet: SH.edit.id }); if (r.error) return fx(r.error); SH.edit = null; await drawSheet(); },
});

// ---------- the old limits screen (#/locset): a link to the versions page ----------
const origLocset = (window.BOS_PAGES || {}).locset;
if (origLocset) {
  window.BOS_PAGES.locset = async function () {
    await origLocset();
    const put = () => { const sel_ = $('#ls_loc'); if (sel_ && !$('#lv_link')) { const b = document.createElement('button'); b.id = 'lv_link'; b.className = 'full'; b.dataset.act = 'go'; b.dataset.v = 'locsheet'; b.style.marginBottom = '8px'; b.textContent = T('sh_oldlink'); sel_.parentNode.insertBefore(b, sel_); } };
    put();
    const root = $('#app'); if (root && window.MutationObserver) { const mo = new MutationObserver(() => { if (!/^#\/locset/.test(location.hash)) { mo.disconnect(); return; } put(); }); mo.observe(root, { childList: true, subtree: true }); }
  };
}

// ---------- limit helpers for forms: BOS.LOC ----------
async function getLimit(loc, key, date) {
  const r = await sb.rpc('get_limit', { p_loc: Number(loc), p_key: key, p_date: date || null });
  if (r.error) return undefined;            // function missing (phase16 not installed) or not allowed: caller falls back to location_settings
  return r.data === undefined ? null : r.data;   // null = blank = Data needed
}
async function limitMissing(loc, keys, date) { const r = await sb.rpc('limit_missing', { p_loc: Number(loc), p_keys: keys, p_date: date || null }); return r.error ? [] : (r.data || []); }
const blockOn = () => { try { return B.rule('block_on_missing_limit', false) === true; } catch (e) { return false; } };
// optional block: when the switch is on and the form shows the “limit missing” notice, the submit is refused (the server cannot know which form needs which key)
const prevSubmit = H.e_submit;
if (prevSubmit) H.e_submit = function () {
  if (blockOn()) { const n = [...document.querySelectorAll('.notice.warn')].find((x) => x.textContent.includes(t('need_settings'))); if (n) return toast(T('sh_blockmsg')); }
  return prevSubmit.apply(this, arguments);
};
B.LOC = { reload, list: () => D.locs.slice(), getLimit, limitMissing, blockOn, slug, TONE, statuses: STATUSES };

window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { locations: view, locsheet: viewSheet });
})();
