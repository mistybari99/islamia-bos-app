/* Islamia BOS · To-do list (#/todo) and the small Home card. Package R2-B.
   What it does: the owner (or a person he designates with the grant todo_assign) gives an extra task or duty to one person or to a role: title, detail, due date,
   priority, optional repeat (daily / weekly). The person sees ONLY his own list (and a small card on Home when it is not empty): he marks a task Done (note optional) or
   "Cannot do" (reason required). Whoever gave a task sees everything he gave, with the status and notes; overdue tasks are highlighted. A task given to a role becomes
   one task for each person who holds that role at that moment.
   Switches: todo_on (OFF by default: no card, no menu entry, no request) and todo_repeat_on (OFF: the repeat field is not shown and the server refuses it).
   Server: supabase/phase131.sql (r2_todo_state / _assign / _mine / _given / _set / _manage). The server is the authority; the screen only guides.
   Home hook (docs/integration/R2.md): nav.js home() adds <div id="hv_todo"></div> and calls BOS.todo.mount(el). UNVERIFIED on a real phone and a real Supabase project. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, shell, openSheet, closeSheet, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const X = {
  title: L('করণীয় তালিকা', 'To-do list', 'To-do list (করণীয়)'), card: L('আমার করণীয়', 'My to-do', 'আমার To-do'),
  off: L('করণীয় তালিকা এখন বন্ধ আছে। মালিক সেটিংসে "করণীয় তালিকা চালু" করলে এটি কাজ করবে।', 'The to-do list is switched off. The owner can switch it on in Settings (todo_on).', 'To-do list বন্ধ। মালিক Settings-এ "todo_on" চালু করলে কাজ করবে।'),
  nofn: L('এই সুবিধা এখনো সার্ভারে বসানো হয়নি (phase131)।', 'The server does not have this yet (phase131).', 'এটি এখনো server-এ বসানো হয়নি (phase131)।'),
  mine: L('আমার', 'Mine', 'আমার'), given: L('আমি দিয়েছি', 'I gave', 'আমি দিয়েছি'), allGiven: L('সবার দেওয়া', 'All given', 'সবার দেওয়া'),
  none: L('এখন আপনার কোনো করণীয় নেই।', 'Nothing to do right now.', 'এখন কোনো করণীয় নেই।'), noneGiven: L('এখনো কাউকে কাজ দেননি।', 'You have not given any task yet.', 'এখনো কাউকে কাজ দেননি।'),
  showDone: L('শেষ হওয়াগুলোও দেখান', 'Show finished ones too', 'শেষ হওয়াগুলোও দেখান'),
  newBtn: L('নতুন কাজ দিন', 'Give a task', 'নতুন কাজ দিন'), cantAssign: L('কাজ দেওয়ার অনুমতি আপনার নেই। মালিক "কাজ দেওয়া" অধিকার দিলে পারবেন।', 'You cannot give tasks. The owner can give you the right "Give extra tasks".', 'কাজ দেওয়ার permission নেই। মালিক "Give extra tasks" অধিকার দিলে পারবেন।'),
  fTitle: L('কাজের নাম', 'Task', 'কাজের নাম'), fDetail: L('বিস্তারিত', 'Details', 'বিস্তারিত'), fDue: L('শেষ তারিখ (ফাঁকা = নির্দিষ্ট নেই)', 'Due date (blank = none)', 'শেষ তারিখ (ফাঁকা = নেই)'),
  fPri: L('গুরুত্ব', 'Priority', 'Priority'), fTo: L('কাকে', 'Give to', 'কাকে'), kPerson: L('একজনকে', 'One person', 'একজন'), kRole: L('একটি ভূমিকার সবাইকে', 'Everyone with a role', 'একটি role-এর সবাই'),
  pick: L('বাছুন…', 'Choose…', 'বাছুন…'), fRep: L('পুনরাবৃত্তি', 'Repeat', 'Repeat'), rNone: L('একবার', 'Once', 'একবার'), rDaily: L('প্রতিদিন', 'Daily', 'প্রতিদিন'), rWeekly: L('প্রতি সপ্তাহে', 'Weekly', 'প্রতি সপ্তাহে'),
  pLow: L('কম', 'Low', 'Low'), pNormal: L('সাধারণ', 'Normal', 'Normal'), pHigh: L('বেশি', 'High', 'High'), pUrgent: L('জরুরি', 'Urgent', 'জরুরি'),
  sOpen: L('বাকি', 'Open', 'Open'), sDone: L('হয়েছে', 'Done', 'Done'), sCannot: L('করা যায়নি', 'Cannot do', 'Cannot do'), sCancelled: L('বাতিল', 'Cancelled', 'Cancelled'),
  giveBtn: L('দিন', 'Give', 'Give'), cancel: L('বাতিল', 'Cancel', 'Cancel'), close: L('বন্ধ করুন', 'Close', 'Close'),
  done: L('হয়েছে', 'Done', 'Done'), cannot: L('করা যায়নি', 'Cannot do', 'Cannot do'), overdue: L('দেরি', 'Overdue', 'Overdue'), due: L('শেষ', 'Due', 'Due'),
  doneNote: L('কী করা হলো (ঐচ্ছিক)', 'What was done (optional)', 'কী করা হলো (optional)'), cannotWhy: L('কেন করা যায়নি (লিখতে হবে)', 'Why it cannot be done (required)', 'কেন করা যায়নি (লিখতে হবে)'),
  save: L('সংরক্ষণ', 'Save', 'Save'), from: L('দিয়েছেন', 'from', 'from'), to: L('কাকে', 'to', 'to'), repeats: L('পুনরাবৃত্ত', 'repeats', 'repeats'),
  cancelTask: L('কাজটি বাতিল করুন', 'Cancel this task', 'Task বাতিল'), reopen: L('আবার খুলুন', 'Reopen', 'Reopen'), why: L('কারণ (লিখতে হবে)', 'Reason (required)', 'কারণ (লিখতে হবে)'),
  all: L('সব', 'All', 'সব'), given_ok: L('কাজ দেওয়া হয়েছে', 'Task given', 'Task দেওয়া হয়েছে'), people: L('জন', 'people', 'জন'), seeAll: L('সব দেখুন', 'See all', 'সব দেখুন'),
  note: L('নোট', 'Note', 'Note'), saved: L('সংরক্ষণ হয়েছে', 'Saved', 'Saved'),
};
const T = (k) => lab(X[k]);
const E = {
  not_allowed: L('এটির অনুমতি নেই।', 'You are not allowed to do this.', 'এটির permission নেই।'), todo_off: L('করণীয় তালিকা বন্ধ আছে।', 'The to-do list is switched off.', 'To-do list বন্ধ আছে।'),
  bad_target: L('কাকে দেবেন তা ঠিকভাবে বাছুন।', 'Choose who it is for.', 'কাকে দেবেন তা বাছুন।'), title_required: L('কাজের নাম লিখুন।', 'Write the task.', 'কাজের নাম লিখুন।'),
  bad_date: L('শেষ তারিখ আজ বা তার পরের হতে হবে।', 'The due date must be today or later.', 'Due date আজ বা পরের হতে হবে।'), bad_priority: L('গুরুত্ব ঠিক নয়।', 'Priority is not valid.', 'Priority ঠিক নয়।'),
  bad_repeat: L('পুনরাবৃত্তি ঠিক নয়।', 'Repeat is not valid.', 'Repeat ঠিক নয়।'), repeat_off: L('পুনরাবৃত্তি বন্ধ আছে (সেটিংসে চালু করুন)।', 'Repeating tasks are switched off (todo_repeat_on).', 'Repeat বন্ধ (todo_repeat_on)।'),
  no_recipients: L('এই ভূমিকায় কেউ নেই।', 'Nobody holds this role.', 'এই role-এ কেউ নেই।'), reason_required: L('কারণ লিখুন।', 'Write a reason.', 'কারণ লিখুন।'),
  not_open: L('কাজটি আর খোলা নেই।', 'The task is not open any more.', 'Task আর open নেই।'), text_too_long: L('লেখা বেশি লম্বা।', 'The text is too long.', 'লেখা বেশি লম্বা।'),
};
const eText = (e) => { const m = String((e && e.message) || ''); for (const k of Object.keys(E)) if (m.indexOf(k.replace('not_allowed', 'not allowed')) >= 0) return lab(E[k]); return m || 'error'; };
const isMissing = (e) => e && (e.code === 'PGRST202' || /does not exist|could not find/i.test(e.message || ''));
const ruleOn = () => { try { return B.rule && B.rule('todo_on', false) === true; } catch (e) { return false; } };
async function rpc(fn, args) { const r = await sb.rpc(fn, args || {}); if (r.error) throw r.error; return r.data; }
const fmtD = (iso) => (iso ? new Date(String(iso).slice(0, 10) + 'T00:00:00Z').toLocaleDateString('en-GB', { timeZone: 'UTC', day: '2-digit', month: 'short' }) : '');

function css() {
  if (document.getElementById('r2t_css')) return;
  const st = document.createElement('style'); st.id = 'r2t_css';
  st.textContent = `
.r2t-card .r2t-t { font-weight: 700; overflow-wrap: anywhere; } .r2t-card .r2t-d { white-space: pre-wrap; margin: 6px 0; overflow-wrap: anywhere; }
.r2t-card.overdue { border-color: var(--bad); border-left: 6px solid var(--bad); } .r2t-card.over-text { color: var(--bad); }
.r2t-card.finished { opacity: .85; }
.r2t-chips { display: flex; flex-wrap: wrap; gap: 6px; margin: 6px 0; }
.r2t-btns { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 8px; } .r2t-btns button { flex: 1 1 130px; min-height: 44px; }
#hv_todo .hrow { text-align: start; } #hv_todo .r2t-hdue { margin-inline-start: auto; }
#r2t_all { width: 24px; min-height: 24px; flex: none; }
`;
  document.head.appendChild(st);
}

const D = { st: null, tab: 'mine', all: false, mine: [], given: [], filter: '', opts: null };
const PRI = { low: ['pLow', ''], normal: ['pNormal', ''], high: ['pHigh', 'warn'], urgent: ['pUrgent', 'bad'] };
const STA = { open: ['sOpen', 'info'], done: ['sDone', 'ok'], cannot: ['sCannot', 'warn'], cancelled: ['sCancelled', ''] };

function cardHTML(x, mode) {
  const [pk, pc] = PRI[x.priority] || PRI.normal, [sk, sc] = STA[x.status] || STA.open;
  const over = !!x.overdue;
  const acts = mode === 'mine'
    ? (x.status === 'open' ? `<div class="r2t-btns"><button type="button" class="primary" data-act="r2t_ask" data-v="${esc(x.id)}" data-k="done">${esc(T('done'))}</button><button type="button" data-act="r2t_ask" data-v="${esc(x.id)}" data-k="cannot">${esc(T('cannot'))}</button></div>` : '')
    : `<div class="r2t-btns">${x.status === 'open' ? `<button type="button" data-act="r2t_cancel" data-v="${esc(x.id)}">${esc(T('cancelTask'))}</button>` : `<button type="button" data-act="r2t_reopen" data-v="${esc(x.id)}">${esc(T('reopen'))}</button>`}</div>`;
  return `<div class="card r2t-card ${over ? 'overdue' : ''} ${x.status !== 'open' ? 'finished' : ''}" data-id="${esc(x.id)}" data-status="${esc(x.status)}">
    <div class="row between" style="align-items:flex-start;gap:8px"><span class="r2t-t">${esc(x.title)}</span>${pc || x.priority !== 'normal' ? `<span class="chip ${pc}">${esc(T(pk))}</span>` : ''}</div>
    <div class="r2t-chips">${x.status !== 'open' || mode === 'given' ? `<span class="chip ${sc}">${esc(T(sk))}</span>` : ''}
      ${x.due_date ? `<span class="chip ${over ? 'bad' : ''}">${over ? esc(T('overdue')) + ' · ' : esc(T('due')) + ' '}${esc(fmtD(x.due_date))}</span>` : ''}
      ${x.repeat_kind && x.repeat_kind !== 'none' ? `<span class="chip">${esc(T(x.repeat_kind === 'daily' ? 'rDaily' : 'rWeekly'))}</span>` : ''}
      ${mode === 'given' ? `<span class="chip">${esc(T('to'))}: ${esc(x.assignee || '')}</span>` : ''}</div>
    ${x.detail ? `<div class="r2t-d">${esc(x.detail)}</div>` : ''}
    ${mode === 'mine' ? `<div class="muted" style="font-size:.85rem">${esc(T('from'))} ${esc(x.assigner || '')}</div>` : ''}
    ${x.status_note ? `<div class="r2t-n" style="font-size:.9rem"><span class="muted">${esc(T('note'))}:</span> ${esc(x.status_note)}</div>` : ''}${acts}</div>`;
}

async function view() {
  if (B.loadStatic) { try { await B.loadStatic(); } catch (e) { /* the page still opens */ } }
  css();
  shell(T('title'), `<div id="r2t_body"><p class="muted">…</p></div>`, true);
  await load();
}
async function load() {
  const box = $('#r2t_body'); if (!box) return;
  let st;
  try { st = await rpc('r2_todo_state'); } catch (e) { box.innerHTML = `<div class="notice warn">${esc(isMissing(e) ? T('nofn') : eText(e))}</div>`; return; }
  D.st = st;
  if (!st.on) { box.innerHTML = `<div class="notice warn" data-state="off">${esc(T('off'))}</div>`; return; }
  try { D.mine = await rpc('r2_todo_mine', { p_all: D.all }); } catch (e) { D.mine = []; }
  try { D.given = await rpc('r2_todo_given', { p_status: D.filter || null }); } catch (e) { D.given = []; }
  if (D.tab === 'given' && !(st.can_assign || D.given.length)) D.tab = 'mine';
  draw();
}
function draw() {
  const box = $('#r2t_body'); if (!box || !D.st) return;
  const st = D.st, isOwner = !!(S.ctx && S.ctx.is_owner), showGiven = st.can_assign || D.given.length > 0 || D.filter;
  const tabs = showGiven ? `<div class="seg" role="group"><button type="button" data-act="r2t_tab" data-v="mine" aria-pressed="${D.tab === 'mine'}">${esc(T('mine'))} (${D.mine.filter((x) => x.status === 'open').length})</button>
    <button type="button" data-act="r2t_tab" data-v="given" aria-pressed="${D.tab === 'given'}">${esc(isOwner ? T('allGiven') : T('given'))}</button></div>` : '';
  let body = '';
  if (D.tab === 'mine') {
    body = `${D.mine.length ? D.mine.map((x) => cardHTML(x, 'mine')).join('') : B.ui.state('empty', T('none'))}
      <label class="row" style="align-items:center;margin-top:8px"><input type="checkbox" id="r2t_all" data-act="r2t_all" ${D.all ? 'checked' : ''}> ${esc(T('showDone'))}</label>`;
  } else {
    body = `<div><label for="r2t_f">${esc(T('sOpen'))} / ${esc(T('sDone'))} …</label><select id="r2t_f" data-r2t="filter"><option value="">${esc(T('all'))}</option>${['open', 'done', 'cannot', 'cancelled'].map((k) => `<option value="${k}" ${D.filter === k ? 'selected' : ''}>${esc(T(STA[k][0]))}</option>`).join('')}</select></div>
      ${D.given.length ? D.given.map((x) => cardHTML(x, 'given')).join('') : B.ui.state('empty', T('noneGiven'))}`;
  }
  box.innerHTML = `${tabs}${st.can_assign ? `<button type="button" class="primary full" style="margin:10px 0" data-act="r2t_new">${esc(T('newBtn'))}</button>` : (D.tab === 'mine' ? '' : `<div class="muted">${esc(T('cantAssign'))}</div>`)}${body}`;
}

async function newSheet() {
  const st = D.st || {};
  let roles = []; try { const r = await sb.from('roles').select('code,name_bn,name_en,name_mix,active').order('sort'); roles = (r.data || []).filter((x) => x.active !== false); } catch (e) { roles = []; }
  D.opts = { roles, staff: (B.ENV && B.ENV.staff) || [] };
  openSheet(`<h3>${esc(T('newBtn'))}</h3><div class="stack" id="r2t_form">
    <div><label for="r2t_ti">${esc(T('fTitle'))}</label><input id="r2t_ti" maxlength="120" autocomplete="off"></div>
    <div><label for="r2t_de">${esc(T('fDetail'))}</label><textarea id="r2t_de" rows="3" maxlength="2000"></textarea></div>
    <div class="row wrap"><div style="flex:1 1 150px"><label for="r2t_du">${esc(T('fDue'))}</label><input id="r2t_du" type="date"></div>
      <div style="flex:1 1 130px"><label for="r2t_pr">${esc(T('fPri'))}</label><select id="r2t_pr">${['low', 'normal', 'high', 'urgent'].map((k) => `<option value="${k}" ${k === 'normal' ? 'selected' : ''}>${esc(T(PRI[k][0]))}</option>`).join('')}</select></div></div>
    <div><label for="r2t_k">${esc(T('fTo'))}</label><select id="r2t_k"><option value="person">${esc(T('kPerson'))}</option><option value="role">${esc(T('kRole'))}</option></select></div>
    <div id="r2t_tw"></div>
    ${st.repeat_on ? `<div><label for="r2t_rp">${esc(T('fRep'))}</label><select id="r2t_rp"><option value="none">${esc(T('rNone'))}</option><option value="daily">${esc(T('rDaily'))}</option><option value="weekly">${esc(T('rWeekly'))}</option></select></div>` : ''}
    <div class="r2t-btns"><button type="button" class="primary" data-act="r2t_give">${esc(T('giveBtn'))}</button><button type="button" data-act="closesheet">${esc(T('cancel'))}</button></div></div>`);
  kindChanged(); const k = $('#r2t_k'); if (k) k.addEventListener('change', kindChanged);
}
function kindChanged() {
  const k = ($('#r2t_k') || {}).value, w = $('#r2t_tw'); if (!w) return; const o = D.opts || { roles: [], staff: [] };
  const nm = (x) => lab(L(x.name_bn, x.name_en || x.name_bn, x.name_mix || x.name_bn));
  w.innerHTML = k === 'role' ? `<select id="r2t_x" aria-label="${esc(T('kRole'))}"><option value="">${esc(T('pick'))}</option>${o.roles.map((r) => `<option value="${esc(r.code)}">${esc(nm(r))}</option>`).join('')}</select>`
    : `<select id="r2t_x" aria-label="${esc(T('kPerson'))}"><option value="">${esc(T('pick'))}</option>${o.staff.map((p) => `<option value="${esc(p.id)}">${esc((p.full_name || p.staff_id) + ' · ' + p.staff_id)}</option>`).join('')}</select>`;
}
function askSheet(id, kind) {
  openSheet(`<h3>${esc(T(kind === 'done' ? 'done' : 'cannot'))}</h3><div class="stack"><div><label for="r2t_n">${esc(T(kind === 'done' ? 'doneNote' : 'cannotWhy'))}</label><textarea id="r2t_n" rows="3" maxlength="500"></textarea></div>
    <div class="r2t-btns"><button type="button" class="primary" data-act="r2t_set" data-v="${esc(id)}" data-k="${esc(kind)}">${esc(T('save'))}</button><button type="button" data-act="closesheet">${esc(T('cancel'))}</button></div></div>`);
}

Object.assign(H, {
  r2t_tab: (a) => { D.tab = a.dataset.v; draw(); },
  r2t_all: async (a) => { D.all = !!a.checked; await load(); },
  r2t_filter: async (a) => { D.filter = a.value; try { D.given = await rpc('r2_todo_given', { p_status: D.filter || null }); } catch (e) { D.given = []; } draw(); },
  r2t_new: () => newSheet(),
  r2t_give: async () => {
    const kind = ($('#r2t_k') || {}).value || 'person', tg = ($('#r2t_x') || {}).value || '', title = (($('#r2t_ti') || {}).value || '').trim();
    if (!title) return toast(lab(E.title_required)); if (!tg) return toast(lab(E.bad_target));
    const client = (window.crypto && crypto.randomUUID) ? crypto.randomUUID() : null;
    try {
      const r = await rpc('r2_todo_assign', { p_title: title, p_detail: (($('#r2t_de') || {}).value || '').trim(), p_due: ($('#r2t_du') || {}).value || null, p_priority: ($('#r2t_pr') || {}).value || 'normal',
        p_kind: kind, p_target: tg, p_repeat: ($('#r2t_rp') || {}).value || 'none', p_client: client });
      closeSheet(); toast(T('given_ok') + (r && r.count > 1 ? ' · ' + r.count + ' ' + T('people') : '')); D.tab = 'given'; await load();
    } catch (e) { toast(eText(e)); }
  },
  r2t_ask: (a) => askSheet(a.dataset.v, a.dataset.k),
  r2t_set: async (a) => {
    const note = (($('#r2t_n') || {}).value || '').trim(), kind = a.dataset.k;
    if (kind === 'cannot' && !note) return toast(lab(E.reason_required));
    try { await rpc('r2_todo_set', { p_id: Number(a.dataset.v), p_status: kind, p_note: note || null }); closeSheet(); toast(T('saved')); await load(); } catch (e) { toast(eText(e)); }
  },
  r2t_cancel: (a) => {
    openSheet(`<h3>${esc(T('cancelTask'))}</h3><div class="stack"><div><label for="r2t_cr">${esc(T('why'))}</label><input id="r2t_cr" maxlength="500" autocomplete="off"></div>
      <div class="r2t-btns"><button type="button" class="primary" data-act="r2t_cgo" data-v="${esc(a.dataset.v)}">${esc(T('cancelTask'))}</button><button type="button" data-act="closesheet">${esc(T('close'))}</button></div></div>`);
  },
  r2t_cgo: async (a) => {
    const r = (($('#r2t_cr') || {}).value || '').trim(); if (!r) return toast(lab(E.reason_required));
    try { await rpc('r2_todo_manage', { p_id: Number(a.dataset.v), p_action: 'cancel', p_note: r }); closeSheet(); toast(T('saved')); await load(); } catch (e) { toast(eText(e)); }
  },
  r2t_reopen: async (a) => { try { await rpc('r2_todo_manage', { p_id: Number(a.dataset.v), p_action: 'reopen', p_note: null }); toast(T('saved')); await load(); } catch (e) { toast(eText(e)); } },
});

/* ---------- the small card on Home: only when the person has something open ---------- */
async function mount(el) {
  if (!el) return;
  if (!ruleOn()) { el.innerHTML = ''; return; }                              // switch OFF: nothing, no request
  try {
    const st = await rpc('r2_todo_state');
    if (!st || !st.on || !st.open) { el.innerHTML = ''; return; }
    css();
    const rows = (st.next || []).map((x) => `<button type="button" class="hrow mk ${x.overdue ? 'bad' : ''}" data-act="go" data-v="todo"><span>${esc(x.title)}</span>${x.due_date ? `<span class="chip r2t-hdue ${x.overdue ? 'bad' : ''}">${x.overdue ? esc(T('overdue')) + ' · ' : ''}${esc(fmtD(x.due_date))}</span>` : ''}<span class="cv">›</span></button>`).join('');
    el.innerHTML = `<div class="hsec">${esc(T('card'))}<small>${st.open}${st.overdue ? ' · ' + st.overdue + ' ' + esc(T('overdue')) : ''}</small></div><div class="card" style="padding:4px 12px" data-r2-card="todo">${rows}
      ${st.open > (st.next || []).length ? `<button type="button" class="hrow" data-act="go" data-v="todo"><span>${esc(T('seeAll'))}</span><span class="cv">›</span></button>` : ''}</div>`;
  } catch (e) { el.innerHTML = ''; }
}

document.addEventListener('change', (e) => { const el = e.target; if (el && el.getAttribute && el.getAttribute('data-r2t') === 'filter') H.r2t_filter(el); });
B.todo = { mount };
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { todo: view });
})();
