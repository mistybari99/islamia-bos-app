/* Islamia BOS · editable lists (owner): expense heads, marketing heads with their monthly limit, payment services, units, categories, reasons ...
   Per list (⋮): edit options, add rule (open / approval / owner), Other on/off, lock, hide, switch the list off, reorder, Other queue, requests.
   Per option (⋮): edit names, switch on/off (a retire needs a reason), move up / down, history. Nothing is ever deleted: a retired value keeps showing on old records.
   The server enforces every rule (supabase/phase15.sql); this page guides. Without phase15 it still edits options like before. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, t, esc, toast, fail, shell, openSheet, closeSheet } = A;
const $ = (s, el = document) => el.querySelector(s);
const L = B.L, lab = B.lab;
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d));
const LISTS = {
  expense_heads: { title: L('খরচের খাত (ব্যয় ভাউচার)', 'Expense heads (expense voucher)', 'খরচের খাত (Expense voucher)'), extra: [] },
  marketing_heads: { title: L('মার্কেটিং খাত ও মাসিক সীমা', 'Marketing heads and monthly limit', 'Marketing খাত ও মাসিক limit'), extra: [{ key: 'limit_month', label: L('মাসের সীমা (৳)', 'Monthly limit (৳)', 'মাসের Limit (৳)'), kind: 'number' }] },
  item_categories: { title: L('পণ্যের ক্যাটাগরি', 'Product categories', 'Product Category'), extra: [] },
  item_subcategories: { title: L('পণ্যের সাব-ক্যাটাগরি', 'Product sub-categories', 'Product Sub-category'), extra: [] },
  units: { title: L('একক (কেজি, পিস, বক্স…)', 'Units (kg, piece, box…)', 'Unit (kg, piece, box…)'), extra: [] },
  wallets: { title: L('মোবাইল পেমেন্ট মাধ্যম (বিকাশ, নগদ…)', 'Mobile payment services (bKash, Nagad…)', 'Mobile payment মাধ্যম (bKash, Nagad…)'), extra: [] },
  supplier_types: { title: L('সাপ্লায়ারের ধরন', 'Supplier types', 'Supplier Type'), extra: [] },
  customer_types: { title: L('কাস্টমারের ধরন', 'Customer types', 'Customer Type'), extra: [] },
  wastage_reasons: { title: L('নষ্টের কারণ', 'Wastage reasons', 'Wastage কারণ'), extra: [] },
  return_reasons: { title: L('ফেরতের কারণ', 'Return reasons', 'Return কারণ'), extra: [] },
  asset_conditions: { title: L('সম্পদের অবস্থা', 'Asset conditions', 'Asset অবস্থা'), extra: [] },
};
const X = {
  title: L('তালিকা সম্পাদনা', 'Edit lists', 'List Edit'), hint: L('এখানে বদলালে ফর্মের বাছাই-তালিকা বদলে যায়। কিছু মোছা হয় না, শুধু বন্ধ করা যায়, তাই পুরনো এন্ট্রি ঠিক থাকে।', 'Changes here change the choices in the forms. Nothing is deleted, you can only switch an item off, so old entries stay correct.', 'এখানে বদলালে form এর choice বদলায়। কিছু মোছা হয় না, শুধু বন্ধ করা যায়, তাই পুরনো entry ঠিক থাকে।'),
  bn: L('বাংলা নাম', 'Bangla name', 'বাংলা নাম'), en: L('ইংরেজি নাম', 'English name', 'English নাম'), mix: L('Bng-Eng নাম (ঐচ্ছিক)', 'Bng-Eng name (optional)', 'Bng-Eng নাম (ঐচ্ছিক)'),
  add: L('＋ নতুন যোগ', '＋ Add new', '＋ নতুন Add'), save: L('সংরক্ষণ', 'Save', 'Save'), on: L('চালু', 'On', 'On'), off: L('বন্ধ', 'Off', 'Off'), saved: L('সংরক্ষিত', 'Saved', 'Saved'), needbn: L('বাংলা নাম লিখুন', 'Enter the Bangla name', 'বাংলা নাম লিখুন'),
  missing: L('এই তালিকা ডেটাবেসে নেই — নতুন SQL চালাতে হবে', 'This list is not in the database yet — the new SQL must be run', 'এই list database এ নেই — নতুন SQL চালাতে হবে'), nolimit: L('(সীমা লেখা নেই)', '(no limit written)', '(limit লেখা নেই)'),
  noP15: L('তালিকার নিয়ম (phase15) এখনো চালু হয়নি — নতুন SQL চালাতে হবে। এখন শুধু নাম বদলানো যাবে।', 'List rules (phase15) are not installed yet — the new SQL must be run. For now only the names can be edited.', 'List rule (phase15) এখনো চালু হয়নি — নতুন SQL চালাতে হবে। এখন শুধু নাম বদলানো যাবে।'),
  more: L('আরও', 'More', 'আরও'), close: L('বন্ধ করুন', 'Close', 'Close'), cancel: L('ক্যান্সেল', 'Cancel', 'Cancel'), done: L('হয়েছে', 'Done', 'Done'),
  rule: L('নতুন যোগের নিয়ম', 'Add rule', 'নতুন যোগের নিয়ম'), r_open: L('খোলা — যে কেউ যোগ করলে সঙ্গে সঙ্গে তালিকায় আসে', 'Open — anyone adds, it joins the list at once', 'Open — যে কেউ Add করলে সঙ্গে সঙ্গে list-এ আসে'),
  r_approval: L('অ্যাপ্রুভ — অনুরোধ যায়, মালিক ঠিক করেন; তত দিন "অন্যান্য" লিখুন', 'Approval — a request, the owner decides; meanwhile write "Other"', 'Approval — Request যায়, Owner ঠিক করেন; তত দিন "Other" লিখুন'),
  r_owner: L('শুধু মালিক — মালিক (ও অনুমতি-পাওয়া) যোগ করেন; বাকিরা "অন্যান্য" লিখুন', 'Owner only — the owner (and delegates) add; others write "Other"', 'Owner only — Owner (ও delegate) Add করেন; বাকিরা "Other" লিখুন'),
  ruleShort: { open: L('খোলা', 'open', 'open'), approval: L('অ্যাপ্রুভ', 'approval', 'approval'), owner: L('শুধু মালিক', 'owner only', 'owner only') },
  allowOther: L('"অন্যান্য" লেখা', '"Other" write-in', '"Other" লেখা'), locked: L('লক', 'Locked', 'Locked'), hidden: L('লুকানো', 'Hidden', 'Hidden'), inactive: L('তালিকা বন্ধ', 'List off', 'List বন্ধ'),
  m_edit: L('অপশন সম্পাদনা', 'Edit options', 'Option Edit'), m_rule: L('নতুন যোগের নিয়ম…', 'Add rule…', 'নতুন যোগের নিয়ম…'), m_other: L('"অন্যান্য" চালু/বন্ধ', 'Allow "Other" on/off', '"Other" চালু/বন্ধ'),
  m_lock: L('লক করুন', 'Lock the list', 'List Lock'), m_unlock: L('তালা খুলুন', 'Unlock the list', 'List Unlock'), m_hide: L('লুকান', 'Hide the list', 'List Hide'), m_show: L('দেখান', 'Show the list', 'List Show'),
  m_off: L('তালিকা বন্ধ করুন', 'Switch the list off', 'List বন্ধ করুন'), m_on: L('তালিকা চালু করুন', 'Switch the list on', 'List চালু করুন'), m_reorder: L('ক্রম বদলান', 'Reorder', 'ক্রম বদলান'),
  m_queue: L('"অন্যান্য" সারি', '"Other" queue', '"Other" queue'), m_req: L('নতুন অপশনের অনুরোধ', 'New-option requests', 'নতুন option-এর Request'), m_mgr: L('এই তালিকার দায়িত্বপ্রাপ্ত', 'People who manage this list', 'এই list-এর দায়িত্বপ্রাপ্ত'),
  o_edit: L('নাম সম্পাদনা', 'Edit names', 'নাম Edit'), o_on: L('চালু করুন', 'Switch on', 'চালু করুন'), o_off: L('বন্ধ করুন (কারণসহ)', 'Retire (with a reason)', 'বন্ধ করুন (কারণসহ)'), o_up: L('উপরে', 'Move up', 'উপরে'), o_down: L('নিচে', 'Move down', 'নিচে'), o_hist: L('ইতিহাস', 'History', 'History'),
  reason: L('বন্ধ করার কারণ (লাগবেই)', 'Reason for retiring (required)', 'বন্ধ করার কারণ (লাগবেই)'), needReason: L('কারণ লিখুন', 'Enter a reason', 'কারণ লিখুন'), retiredBy: L('বন্ধ', 'Retired', 'Retired'),
  q_title: L('"অন্যান্য" সারি', '"Other" queue', '"Other" queue'), r_title: L('নতুন অপশনের অনুরোধ', 'New-option requests', 'নতুন option-এর Request'), q_none: L('কিছু অপেক্ষায় নেই ✓', 'Nothing waiting ✓', 'কিছু অপেক্ষায় নেই ✓'),
  q_add: L('নতুন অপশন বানান', 'Add as a new option', 'নতুন option বানান'), q_merge: L('বিদ্যমান অপশনে মেলান', 'Merge into an existing option', 'বিদ্যমান option-এ মেলান'), q_rej: L('বাতিল করুন', 'Reject', 'Reject'),
  rq_ok: L('অ্যাপ্রুভ', 'Approve', 'Approve'), rq_no: L('নাকচ', 'Reject', 'Reject'), mergeTo: L('কোনটার সঙ্গে মেলাবেন?', 'Merge into which one?', 'কোনটার সঙ্গে মেলাবেন?'), pick: L('বাছুন', 'Pick', 'Pick'),
  back: L('← অপশনে ফিরুন', '← Back to the options', '← Option-এ ফিরুন'), by: L('জমা দিয়েছেন', 'by', 'by'), status: L('অবস্থা', 'Status', 'Status'), resolved: L('সিদ্ধান্ত হয়েছে', 'Decided', 'Decided'),
  s_pending: L('অপেক্ষায়', 'pending', 'pending'), s_merged: L('মেলানো', 'merged', 'merged'), s_added: L('যোগ হয়েছে', 'added', 'added'), s_rejected: L('বাতিল', 'rejected', 'rejected'), s_approved: L('অ্যাপ্রুভড', 'approved', 'approved'),
  hist_none: L('কোনো ইতিহাস নেই', 'No history', 'কোনো history নেই'), self: L('নিজের অনুরোধ নিজে অ্যাপ্রুভ করা যায় না', 'You cannot approve your own request', 'নিজের request নিজে approve করা যায় না'),
  noperm: L('অনুমতি নেই', 'Not allowed', 'অনুমতি নেই'), sent: L('অনুরোধ গেছে', 'Request sent', 'Request গেছে'), mgrHint: L('এরা এই তালিকার অনুরোধ ও "অন্যান্য" দেখে সিদ্ধান্ত নিতে পারেন, এবং "শুধু মালিক" নিয়মেও যোগ করতে পারেন।', 'They can decide this list\'s requests and "Other" entries and add under the owner-only rule.', 'এরা এই list-এর request ও "Other" দেখে সিদ্ধান্ত নিতে পারে, এবং "owner only" নিয়মেও Add করতে পারে।'),
  showHidden: L('লুকানো তালিকাও দেখান', 'Show hidden lists', 'Hidden list ও দেখান'), allQ: L('সব অপেক্ষমাণ', 'All waiting', 'সব অপেক্ষমাণ'), retiredNote: L('বন্ধ করা হয়েছে', 'retired', 'retired'),
};
const T = (k) => lab(X[k]);
const ERRS = { self_approval: 'self', owner_only: 'noperm', 'not allowed': 'noperm', reason_required: 'needReason', name_required: 'needbn' };
const eMsg = (e) => { const m = String((e && e.message) || e || ''); const k = Object.keys(ERRS).find((x) => m.includes(x)); return k ? T(ERRS[k]) : null; };
const errOut = (e) => { const m = eMsg(e); if (m) toast(m); else if (/list_locked/.test(String(e && e.message))) toast(B.listctl ? B.listctl.T('locked') : 'locked'); else fail(e); };
const D = { code: 'expense_heads', rows: [], err: null, defs: {}, noP15: false, view: 'options', edit: null, reorder: false, counts: { requests: 0, other: 0, lists: {} }, names: null, showHidden: false, q: [], rq: [], done: [] };
const isOwner = () => !!(S.ctx && S.ctx.is_owner);
const title = (c) => (LISTS[c] ? lab(LISTS[c].title) : (D.defs[c] && (lab({ bn: D.defs[c].title_bn, en: D.defs[c].title_en || D.defs[c].title_bn })) ) || c);
const defOf = (c) => D.defs[c] || { add_rule: 'approval', allow_other: true, active: true, locked: false, hidden: false };
const extraOf = (c) => (LISTS[c] ? LISTS[c].extra : []);
const nameOf = (id) => (D.names && D.names[id]) || '';
const when = (iso) => { try { return new Date(iso).toLocaleString('en-GB', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Dhaka' }); } catch (e) { return ''; } };
const optLabel = (r) => lab({ bn: r.label_bn, mix: r.label_mix || undefined, en: r.label_en || undefined });
const rpc = async (fn, args) => { try { const r = await sb.rpc(fn, args); if (r && r.error) { errOut(r.error); return null; } return (r && r.data) || {}; } catch (e) { fail(e); return null; } };

async function view() {
  shell(T('title'), `<p class="muted">${esc(t('loading'))}</p>`, true);
  await B.loadStatic(); await B.reloadLists();
  draw();
}
async function loadAll() {
  const dr = await sb.from('list_defs').select('*');
  D.noP15 = !!(dr && dr.error); D.defs = {}; ((dr && dr.data) || []).forEach((d) => { D.defs[d.list_code] = d; });
  const r = await sb.from('option_lists').select('*').eq('list_code', D.code).order('sort'); D.err = r.error; D.rows = r.data || [];
  if (!D.noP15) {
    try { const c = await sb.rpc('list_queue_counts'); if (c && !c.error && c.data) D.counts = Object.assign({ requests: 0, other: 0, lists: {} }, c.data); } catch (e) { /* no counts */ }
    if (D.names === null) { D.names = {}; try { const p = await sb.from('profiles').select('id,staff_id,full_name'); ((p && p.data) || []).forEach((x) => { D.names[x.id] = x.full_name || x.staff_id; }); } catch (e) { /* names stay empty */ } }
    if (D.view === 'other') { const q = await sb.from('list_other_entries').select('*').eq('list_code', D.code).order('entered_at', { ascending: false }).limit(200); D.q = (q && q.data) || []; }
    if (D.view === 'requests') { const q = await sb.from('option_requests').select('*').eq('list_code', D.code).order('requested_at', { ascending: false }).limit(200); D.rq = (q && q.data) || []; }
  }
}
const codes = () => {
  const s = new Set(Object.keys(LISTS)); Object.keys(D.defs).forEach((c) => s.add(c));
  return [...s].filter((c) => D.showHidden || !defOf(c).hidden || c === D.code);
};
const cnt = (c) => { const x = D.counts.lists && D.counts.lists[c]; return x ? (x.requests || 0) + (x.other || 0) : 0; };
async function draw() {
  await loadAll();
  const d = defOf(D.code), own = isOwner(), p15 = !D.noP15;
  const chips = codes().map((c) => `<button class="tog ${D.code === c ? 'on' : ''}" data-act="ls2_pick" data-v="${c}" style="${defOf(c).hidden || defOf(c).active === false ? 'opacity:.6' : ''}">${esc(title(c))}${cnt(c) ? ` <span class="badge">${cnt(c)}</span>` : ''}</button>`).join('');
  const state = p15 ? `<div class="row wrap" style="gap:6px;margin-top:6px"><span class="tog on">${esc(T('rule'))}: ${esc(lab(X.ruleShort[d.add_rule] || X.ruleShort.approval))}</span>
      ${d.allow_other ? `<span class="tog on">${esc(T('allowOther'))}</span>` : ''}${d.locked ? `<span class="tog">${esc(T('locked'))}</span>` : ''}${d.hidden ? `<span class="tog">${esc(T('hidden'))}</span>` : ''}${d.active === false ? `<span class="tog">${esc(T('inactive'))}</span>` : ''}</div>` : '';
  const head = `<div class="card stack"><div class="row between"><b>${esc(title(D.code))}</b>${p15 ? `<button class="mini" data-act="ls2_lmenu" aria-label="${esc(T('more'))}">⋮</button>` : ''}</div>${state}
      ${p15 && cnt(D.code) ? `<div class="row wrap" style="gap:6px">${(D.counts.lists[D.code] || {}).other ? `<button class="mini" data-act="ls2_view" data-v="other">${esc(T('q_title'))} <span class="badge">${D.counts.lists[D.code].other}</span></button>` : ''}${(D.counts.lists[D.code] || {}).requests ? `<button class="mini" data-act="ls2_view" data-v="requests">${esc(T('r_title'))} <span class="badge">${D.counts.lists[D.code].requests}</span></button>` : ''}</div>` : ''}</div>`;
  let body;
  if (D.view === 'other') body = drawOther(); else if (D.view === 'requests') body = drawRequests(); else body = drawOptions(d, own);
  shell(T('title'), `<div class="notice ok">${esc(T('hint'))}</div>${D.noP15 ? `<div class="notice bad">${esc(T('noP15'))}</div>` : ''}
    <div class="row wrap" style="margin-bottom:10px" data-ctl="select">${chips}${own && Object.values(D.defs).some((x) => x.hidden) ? `<button class="mini" data-act="ls2_showhid">${esc(T('showHidden'))}${D.showHidden ? ' ✓' : ''}</button>` : ''}</div>
    ${D.err ? `<div class="notice bad">${esc(T('missing'))}</div>` : ''}${head}${body}`, true);
}
function drawOptions(d, own) {
  const def = extraOf(D.code), lockedNow = d.locked;
  const rowsH = D.rows.map((x, i) => {
    const ed = D.edit === x.value_code;
    return `<div class="card stack" style="${x.active ? '' : 'opacity:.6'}"><div class="row between"><b>${i + 1} · ${esc(optLabel(x))}</b><div class="row">
        ${D.reorder ? `<button class="mini" data-act="ls2_move" data-c="${esc(x.value_code)}" data-d="-1" aria-label="up">↑</button><button class="mini" data-act="ls2_move" data-c="${esc(x.value_code)}" data-d="1" aria-label="down">↓</button>` : ''}
        <span class="tog ${x.active ? 'on' : ''}">${esc(x.active ? T('on') : T('off'))}</span><button class="mini" data-act="ls2_omenu" data-c="${esc(x.value_code)}" aria-label="${esc(T('more'))}">⋮</button></div></div>
      ${!x.active && x.retired_reason ? `<div class="muted" style="font-size:.85rem">${esc(T('retiredBy'))}: ${esc(x.retired_reason)}${x.retired_at ? ' · ' + esc(when(x.retired_at)) : ''}</div>` : ''}
      ${def.map((e) => !ed && x.extra && x.extra[e.key] !== undefined && x.extra[e.key] !== null ? `<div class="muted">${esc(lab(e.label))}: ${esc(String(x.extra[e.key]))}</div>` : '').join('')}
      ${ed ? `<div><label>${esc(T('bn'))}</label><input id="l2_bn_${esc(x.value_code)}" value="${esc(x.label_bn)}"></div>
      <div><label>${esc(T('en'))}</label><input id="l2_en_${esc(x.value_code)}" value="${esc(x.label_en || '')}"></div>
      <div><label>${esc(T('mix'))}</label><input id="l2_mix_${esc(x.value_code)}" value="${esc(x.label_mix || '')}"></div>
      ${def.map((e) => `<div><label>${esc(lab(e.label))}</label><input id="l2_x_${e.key}_${esc(x.value_code)}" inputmode="decimal" value="${x.extra && x.extra[e.key] !== undefined && x.extra[e.key] !== null ? esc(String(x.extra[e.key])) : ''}" placeholder="${esc(T('nolimit'))}"></div>`).join('')}
      <div class="row"><button class="full" data-act="ls2_edit" data-c="">${esc(T('cancel'))}</button><button class="primary full" data-act="ls2_save" data-c="${esc(x.value_code)}">${esc(T('save'))}</button></div>` : ''}</div>`;
  }).join('');
  void lockedNow; void own;
  return `${D.reorder ? `<div class="notice ok row between"><span>${esc(T('m_reorder'))}</span><button class="mini" data-act="ls2_reorder">${esc(T('done'))}</button></div>` : ''}${rowsH}
    ${D.err ? '' : `<div id="ls2_newbox"></div><button class="full" data-act="ls2_new">${esc(T('add'))}</button>`}`;
}
function who(id) { return nameOf(id) || '—'; }
function drawOther() {
  const pend = D.q.filter((x) => x.status === 'pending'), done = D.q.filter((x) => x.status !== 'pending').slice(0, 20);
  const row = (x) => `<div class="card stack"><div class="row between"><b>${esc(x.text)}</b>${x.status === 'pending' ? `<button class="mini" data-act="ls2_qmenu" data-id="${esc(x.id)}" aria-label="${esc(T('more'))}">⋮</button>` : `<span class="tog on">${esc(lab(X['s_' + x.status] || X.s_pending))}</span>`}</div>
      <div class="muted" style="font-size:.85rem">${esc(T('by'))} ${esc(who(x.entered_by))} · ${esc(when(x.entered_at))}${x.form_code ? ' · ' + esc(x.form_code) : ''}${x.resolved_option ? ' · → ' + esc(x.resolved_option) : ''}</div></div>`;
  return `<button class="mini" data-act="ls2_view" data-v="options">${esc(T('back'))}</button><h3>${esc(T('q_title'))}</h3>${pend.length ? pend.map(row).join('') : `<div class="dash-ok">${esc(T('q_none'))}</div>`}
    ${done.length ? `<h3>${esc(T('resolved'))}</h3>${done.map(row).join('')}` : ''}`;
}
function drawRequests() {
  const pend = D.rq.filter((x) => x.status === 'pending'), done = D.rq.filter((x) => x.status !== 'pending').slice(0, 20);
  const row = (x) => `<div class="card stack"><div class="row between"><b>${esc(lab({ bn: x.label_bn, en: x.label_en || x.label_bn }))}${x.label_en ? ' · ' + esc(x.label_en) : ''}</b>${x.status === 'pending' ? `<button class="mini" data-act="ls2_rmenu" data-id="${esc(x.id)}" aria-label="${esc(T('more'))}">⋮</button>` : `<span class="tog on">${esc(lab(X['s_' + x.status] || X.s_pending))}</span>`}</div>
      <div class="muted" style="font-size:.85rem">${esc(T('by'))} ${esc(who(x.requested_by))} · ${esc(when(x.requested_at))}${x.resulting_value ? ' · → ' + esc(x.resulting_value) : ''}</div>
      ${x.extra && Object.keys(x.extra).length ? `<div class="muted" style="font-size:.85rem">${Object.entries(x.extra).map(([k, v]) => esc(k + ': ' + v)).join(' · ')}</div>` : ''}${x.similar_opts && x.similar_opts.length ? `<div class="muted" style="font-size:.85rem">≈ ${x.similar_opts.map((s) => esc(s.label_bn)).join(', ')}</div>` : ''}</div>`;
  return `<button class="mini" data-act="ls2_view" data-v="options">${esc(T('back'))}</button><h3>${esc(T('r_title'))}</h3>${pend.length ? pend.map(row).join('') : `<div class="dash-ok">${esc(T('q_none'))}</div>`}
    ${done.length ? `<h3>${esc(T('resolved'))}</h3>${done.map(row).join('')}` : ''}`;
}
const rowOf = (c) => D.rows.find((x) => x.value_code === c);
// targeted writes only (never the whole row): the RPCs when phase15 is installed, else a column update / insert of the one option
async function patchOpt(code, fields) { const { error } = await sb.from('option_lists').update(fields).eq('list_code', D.code).eq('value_code', code); if (error) { errOut(error); return false; } await B.reloadLists(); if (B.pay && B.pay.resetWallets) B.pay.resetWallets(); return true; }
async function insertOpt(row) { const { error } = await sb.from('option_lists').insert(row); if (error) { errOut(error); return false; } await B.reloadLists(); if (B.pay && B.pay.resetWallets) B.pay.resetWallets(); return true; }
const menuBtn = (act, label, attrs, on) => `<button class="full ${on ? 'primary' : ''}" style="margin-top:8px;text-align:left" data-act="${act}" ${attrs || ''}>${esc(label)}</button>`;
async function setDef(patch) {
  const r = await rpc('list_def_set', { p_list: D.code, p_patch: patch }); if (!r) return false;
  if (B.listctl && B.listctl.reloadDefs) B.listctl.reloadDefs().catch(() => {}); return true;
}
Object.assign(A.H, {
  ls2_pick: (a) => { D.code = a.dataset.v; D.view = 'options'; D.edit = null; D.reorder = false; draw(); },
  ls2_showhid: () => { D.showHidden = !D.showHidden; draw(); },
  ls2_view: (a) => { D.view = a.dataset.v; closeSheet(); draw(); },
  ls2_edit: (a) => { D.edit = a.dataset.c || null; closeSheet(); draw(); },
  ls2_reorder: () => { D.reorder = !D.reorder; closeSheet(); draw(); },
  // ----- list ⋮ menu -----
  ls2_lmenu: () => {
    const d = defOf(D.code), own = isOwner();
    openSheet(`<h2>${esc(title(D.code))}</h2>
      ${menuBtn('ls2_edit_mode', T('m_edit'))}${menuBtn('ls2_reorder', T('m_reorder'))}
      ${own ? menuBtn('ls2_rulesheet', T('m_rule') + ' · ' + lab(X.ruleShort[d.add_rule]))
        + menuBtn('ls2_defset', T('m_other') + ' · ' + (d.allow_other ? T('on') : T('off')), 'data-k="allow_other"')
        + menuBtn('ls2_defset', d.locked ? T('m_unlock') : T('m_lock'), 'data-k="locked"')
        + menuBtn('ls2_defset', d.hidden ? T('m_show') : T('m_hide'), 'data-k="hidden"')
        + menuBtn('ls2_defset', d.active === false ? T('m_on') : T('m_off'), 'data-k="active"')
        + menuBtn('ls2_mgr', T('m_mgr')) : ''}
      ${menuBtn('ls2_view', `${T('m_queue')} (${(D.counts.lists[D.code] || {}).other || 0})`, 'data-v="other"')}${menuBtn('ls2_view', `${T('m_req')} (${(D.counts.lists[D.code] || {}).requests || 0})`, 'data-v="requests"')}
      <button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('close'))}</button>`);
  },
  ls2_edit_mode: () => { closeSheet(); D.view = 'options'; D.edit = D.rows.length ? D.rows[0].value_code : null; draw(); },
  ls2_rulesheet: () => {
    const d = defOf(D.code);
    openSheet(`<h2>${esc(T('rule'))}</h2>${['open', 'approval', 'owner'].map((k) => menuBtn('ls2_setrule', T('r_' + k), `data-v="${k}"`, d.add_rule === k)).join('')}
      <button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('close'))}</button>`);
  },
  ls2_setrule: async (a) => { if (await setDef({ add_rule: a.dataset.v })) { closeSheet(); toast(T('saved')); draw(); } },
  ls2_defset: async (a) => {
    const k = a.dataset.k, d = defOf(D.code), cur = k === 'active' ? d.active !== false : !!d[k];
    if (await setDef({ [k]: !cur })) { closeSheet(); toast(T('saved')); draw(); }
  },
  ls2_mgr: async () => {
    const r = await sb.from('list_managers').select('*').eq('list_code', D.code); const on = new Set(((r && r.data) || []).filter((x) => x.active).map((x) => x.user_id));
    const ps = await sb.from('profiles').select('id,staff_id,full_name,status'); const people = ((ps && ps.data) || []).filter((p) => p.status === 'active');
    openSheet(`<h2>${esc(T('m_mgr'))}</h2><p class="muted">${esc(T('mgrHint'))}</p>${people.map((p) => `<div class="row between" style="margin-top:6px"><span>${esc(p.full_name || p.staff_id)}</span><button class="tog ${on.has(p.id) ? 'on' : ''}" data-act="ls2_mgrset" data-u="${esc(p.id)}" data-on="${on.has(p.id) ? 0 : 1}">${esc(on.has(p.id) ? T('on') : T('off'))}</button></div>`).join('')}
      <button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('close'))}</button>`);
  },
  ls2_mgrset: async (a) => { const r = await rpc('list_manager_set', { p_list: D.code, p_user: a.dataset.u, p_on: a.dataset.on === '1' }); if (r) { closeSheet(); H.ls2_mgr(); } },
  // ----- option ⋮ menu -----
  ls2_omenu: (a) => {
    const x = rowOf(a.dataset.c); if (!x) return; const c = esc(x.value_code);
    openSheet(`<h2>${esc(optLabel(x))}</h2>
      ${menuBtn('ls2_edit', T('o_edit'), `data-c="${c}"`)}${menuBtn(x.active ? 'ls2_retire' : 'ls2_toggle', x.active ? T('o_off') : T('o_on'), `data-c="${c}"`)}
      ${menuBtn('ls2_move', T('o_up'), `data-c="${c}" data-d="-1"`)}${menuBtn('ls2_move', T('o_down'), `data-c="${c}" data-d="1"`)}${menuBtn('ls2_hist', T('o_hist'), `data-c="${c}"`)}
      <button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('close'))}</button>`);
  },
  ls2_retire: (a) => {
    const x = rowOf(a.dataset.c); if (!x) return;
    openSheet(`<h2>${esc(optLabel(x))}</h2><div><label>${esc(T('reason'))}</label><input id="ls2_reason" autocomplete="off" maxlength="200"></div>
      <div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="ls2_retire_go" data-c="${esc(x.value_code)}">${esc(T('o_off'))}</button></div>`);
  },
  ls2_retire_go: async (a) => {
    const reason = ($('#ls2_reason') && $('#ls2_reason').value || '').trim(); if (!reason) return toast(T('needReason'));
    const r = D.noP15 ? null : await rpc('option_retire', { p_list: D.code, p_value: a.dataset.c, p_reason: reason });
    if (D.noP15) { const x = rowOf(a.dataset.c); if (!(await patchOpt(x.value_code, { active: false }))) return; } else if (!r) return;
    closeSheet(); await B.reloadLists(); draw();
  },
  ls2_toggle: async (a) => {
    const x = rowOf(a.dataset.c); if (!x) return; if (!x.active && x.label_bn === '—') return toast(T('needbn'));
    if (!D.noP15) { const r = await rpc('option_reactivate', { p_list: D.code, p_value: x.value_code }); if (!r) return; await B.reloadLists(); } else if (!(await patchOpt(x.value_code, { active: true }))) return;
    closeSheet(); draw();
  },
  ls2_move: async (a) => {
    const i = D.rows.findIndex((x) => x.value_code === a.dataset.c), j = i + Number(a.dataset.d); if (i < 0 || j < 0 || j >= D.rows.length) return closeSheet();
    const order = D.rows.slice(); [order[i], order[j]] = [order[j], order[i]];
    if (!D.noP15) { const r = await rpc('option_reorder', { p_list: D.code, p_codes: order.map((x) => x.value_code) }); if (!r) return; }
    else { for (let k = 0; k < order.length; k++) { const { error } = await sb.from('option_lists').update({ sort: k + 1 }).eq('list_code', D.code).eq('value_code', order[k].value_code); if (error) return errOut(error); } }
    await B.reloadLists(); if (B.pay && B.pay.resetWallets) B.pay.resetWallets(); closeSheet(); draw();
  },
  ls2_hist: async (a) => {
    const rid = D.code + ':' + a.dataset.c;
    const r = await sb.from('audit_log').select('*').eq('table_name', 'option_lists').eq('record_id', rid).order('id', { ascending: false }).limit(30);
    const rows = (r && r.data) || [];
    openSheet(`<h2>${esc(T('o_hist'))} · ${esc(a.dataset.c)}</h2>${rows.length ? rows.map((x) => {
      const nw = (x.detail && x.detail.new) || {}, od = (x.detail && x.detail.old) || {}; const keys = Object.keys(nw).filter((k) => x.action === 'update' ? true : ['label_bn', 'label_en', 'active'].includes(k));
      return `<div class="card"><div class="muted" style="font-size:.85rem">${esc(when(x.at))} · ${esc(x.staff_id || '')} · ${esc(x.action)}</div>${keys.filter((k) => !['sort'].includes(k) || x.action === 'update').slice(0, 8).map((k) => `<div>${esc(k)}: ${x.action === 'update' ? esc(JSON.stringify(od[k]) ?? '') + ' → ' : ''}${esc(JSON.stringify(nw[k]) ?? '')}</div>`).join('')}</div>`;
    }).join('') : `<p class="muted">${esc(T('hist_none'))}</p>`}<button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('close'))}</button>`);
  },
  ls2_save: async (a) => {
    const c = a.dataset.c, x = rowOf(c), def = extraOf(D.code), bn = ($('#l2_bn_' + c).value || '').trim(); if (!bn) return toast(T('needbn'));
    const extra = { ...(x.extra || {}) };
    for (const e of def) { const raw = norm(($('#l2_x_' + e.key + '_' + c).value || '').trim()); if (raw === '') delete extra[e.key]; else { const n = Number(raw); if (!Number.isFinite(n) || n < 0) return toast(t('err_price')); extra[e.key] = n; } }
    const en = ($('#l2_en_' + c).value || '').trim() || null, mix = ($('#l2_mix_' + c).value || '').trim() || null;
    let okSave;
    if (D.noP15) okSave = await patchOpt(c, { label_bn: bn, label_en: en, label_mix: mix, extra });
    else { const ex = {}; def.forEach((e) => { ex[e.key] = extra[e.key] === undefined ? null : extra[e.key]; });
      okSave = !!(await rpc('option_update', { p_list: D.code, p_value: c, p_bn: bn, p_en: en, p_mix: mix, p_extra: def.length && isOwner() ? ex : null })); if (okSave) await B.reloadLists(); }
    if (okSave) { toast(T('saved')); D.edit = null; draw(); }
  },
  // ----- add a new option (the rule decides: owner adds at once; with owner_self_approve off it becomes a request) -----
  ls2_new: () => {
    const box = $('#ls2_newbox'); if (!box) return; const def = extraOf(D.code);
    box.innerHTML = `<div class="card stack"><div><label>${esc(T('bn'))}</label><input id="l2n_bn" autocomplete="off"></div><div><label>${esc(T('en'))}</label><input id="l2n_en" autocomplete="off"></div><div><label>${esc(T('mix'))}</label><input id="l2n_mix" autocomplete="off"></div>
      ${def.map((e) => `<div><label>${esc(lab(e.label))}</label><input id="l2n_x_${e.key}" inputmode="decimal" placeholder="${esc(T('nolimit'))}"></div>`).join('')}
      <div class="row"><button class="full" data-act="ls2_newcancel">${esc(T('cancel'))}</button><button class="primary full" data-act="ls2_newgo">${esc(T('save'))}</button></div></div>`;
  },
  ls2_newcancel: () => { const box = $('#ls2_newbox'); if (box) box.innerHTML = ''; },
  ls2_newgo: async (a, force) => {
    const bn = ($('#l2n_bn').value || '').trim(); if (!bn) return toast(T('needbn'));
    const extra = {}; for (const e of extraOf(D.code)) { const raw = norm(($('#l2n_x_' + e.key).value || '').trim()); if (raw !== '') { const n = Number(raw); if (!Number.isFinite(n) || n < 0) return toast(t('err_price')); extra[e.key] = n; } }
    const en = ($('#l2n_en').value || '').trim() || null, mix = ($('#l2n_mix').value || '').trim() || null;
    if (D.noP15) { const max = D.rows.reduce((m, x) => Math.max(m, x.sort), 0); if (await insertOpt({ list_code: D.code, value_code: 'x' + Date.now().toString(36), label_bn: bn, label_en: en, label_mix: mix, sort: max + 1, active: true, extra })) draw(); return; }
    const r = await rpc('option_add', { p_list: D.code, p_bn: bn, p_en: en, p_mix: mix, p_extra: extra, p_force: !!force }); if (!r) return;
    if (r.status === 'similar') {
      const box = $('#ls2_newbox'); const s = (r.similar || []).map((x) => esc(x.label_bn) + (x.active ? '' : ' (' + T('retiredNote') + ')')).join(', ');
      if (box && !$('#l2n_sim')) box.insertAdjacentHTML('beforeend', `<div class="notice bad" id="l2n_sim">≈ ${s}<button class="full" style="margin-top:8px" data-act="ls2_newforce">${esc(lab(L('তবু যোগ করুন', 'Add anyway', 'তবু Add করুন')))}</button></div>`);
      return;
    }
    if (r.status === 'exists') toast(lab(L('এটি আগে থেকেই আছে', 'It already exists', 'এটি আগে থেকেই আছে'))); else if (r.status === 'requested') toast(T('sent')); else toast(T('saved'));
    await B.reloadLists(); if (B.pay && B.pay.resetWallets) B.pay.resetWallets(); draw();
  },
  ls2_newforce: (a) => H.ls2_newgo(a, true),
  // ----- Other queue -----
  ls2_qmenu: (a) => {
    const x = D.q.find((y) => y.id === a.dataset.id); if (!x) return; const id = esc(x.id);
    openSheet(`<h2>${esc(x.text)}</h2>${menuBtn('ls2_qadd', T('q_add'), `data-id="${id}"`)}${menuBtn('ls2_qmergesheet', T('q_merge'), `data-id="${id}"`)}${menuBtn('ls2_qrej', T('q_rej'), `data-id="${id}"`)}
      <button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('close'))}</button>`);
  },
  ls2_qadd: (a) => {
    const x = D.q.find((y) => y.id === a.dataset.id); if (!x) return;
    openSheet(`<h2>${esc(T('q_add'))}</h2><div class="stack"><div><label>${esc(T('bn'))}</label><input id="qa_bn" value="${esc(x.text)}"></div><div><label>${esc(T('en'))}</label><input id="qa_en"></div></div>
      <div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="ls2_qadd_go" data-id="${esc(x.id)}">${esc(T('save'))}</button></div>`);
  },
  ls2_qadd_go: async (a) => {
    const r = await rpc('option_other_resolve', { p_id: a.dataset.id, p_action: 'add', p_value: null, p_bn: ($('#qa_bn').value || '').trim(), p_en: ($('#qa_en').value || '').trim() || null, p_mix: null, p_note: null, p_force: a.dataset.force === '1' }); if (!r) return;
    if (r.status === 'exists') { toast(lab(L('এটি আগে থেকেই আছে — "বিদ্যমান অপশনে মেলান" ব্যবহার করুন', 'It already exists - use "Merge into an existing option"', 'এটি আগে থেকেই আছে - "Merge" ব্যবহার করুন'))); return; }
    if (r.status === 'similar') { a.dataset.force = '1'; toast(lab(L('একই রকম আছে: ', 'Similar exists: ', 'একই রকম আছে: ')) + (r.similar || []).map((x) => x.label_bn).join(', ') + ' — ' + lab(L('আবার চাপলে তবু যোগ হবে', 'press again to add anyway', 'আবার চাপলে তবু Add হবে'))); return; }
    closeSheet(); await B.reloadLists(); draw();
  },
  ls2_qmergesheet: (a) => {
    openSheet(`<h2>${esc(T('mergeTo'))}</h2><select id="qm_to"><option value=""></option>${D.rows.filter((r) => r.active).map((r) => `<option value="${esc(r.value_code)}">${esc(optLabel(r))}</option>`).join('')}</select>
      <div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="ls2_qmerge_go" data-id="${esc(a.dataset.id)}">${esc(T('pick'))}</button></div>`);
  },
  ls2_qmerge_go: async (a) => { const v = $('#qm_to').value; if (!v) return toast(T('pick')); const r = await rpc('option_other_resolve', { p_id: a.dataset.id, p_action: 'merge', p_value: v, p_bn: null, p_en: null, p_mix: null, p_note: null }); if (r) { closeSheet(); draw(); } },
  ls2_qrej: async (a) => { const r = await rpc('option_other_resolve', { p_id: a.dataset.id, p_action: 'reject', p_value: null, p_bn: null, p_en: null, p_mix: null, p_note: null }); if (r) { closeSheet(); draw(); } },
  // ----- requests inbox -----
  ls2_rmenu: (a) => {
    const x = D.rq.find((y) => y.id === a.dataset.id); if (!x) return; const id = esc(x.id);
    openSheet(`<h2>${esc(x.label_bn)}</h2>${menuBtn('ls2_rdecide', T('rq_ok'), `data-id="${id}" data-ok="1"`)}${menuBtn('ls2_rdecide', T('rq_no'), `data-id="${id}" data-ok="0"`)}
      <button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('close'))}</button>`);
  },
  ls2_rdecide: async (a) => { const r = await rpc('option_request_decide', { p_id: a.dataset.id, p_approve: a.dataset.ok === '1', p_note: null, p_bn: null, p_en: null, p_mix: null }); if (r) { closeSheet(); await B.reloadLists(); draw(); } },
});
const H = A.H;
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { lists: view });
})();
