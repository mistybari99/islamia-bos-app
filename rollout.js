/* Islamia BOS · W5a screens (supabase/phase17.sql):
   #/rollout  Paper / Parallel / App board per form x place (owner, or the delegable grant rollout_manage): chips, ⋮ menu, bulk set, switches.
   #/changes  Change requests on approved (locked) entries: inbox for the owner / change_approve holders, "my requests" for everybody; B.showRevisions(entryId).
   #/outbox   Form records that could not be sent yet (rule 12): retry, open, discard (discard is local only, with a confirm).
   Every rule is enforced on the server; this page only guides. Nothing is deleted: a state is switched, a request is decided, a queue line is removed from THIS phone only. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, t, esc, toast, fail, shell, openSheet, closeSheet, nm, store } = A;
const H = A.H, L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const isOwner = () => !!(S.ctx && S.ctx.is_owner);

const X = {
  title: L('কাগজ / পাশাপাশি / অ্যাপ', 'Paper / Parallel / App', 'Paper / Parallel / App'), back: L('কন্ট্রোল সেন্টার', 'Control Center', 'Control Center'),
  paper: L('কাগজ', 'Paper', 'Paper'), parallel: L('পাশাপাশি', 'Parallel', 'Parallel'), app: L('অ্যাপ', 'App', 'App'), all: L('সব', 'All', 'All'),
  search: L('ফর্মের কোড বা নাম…', 'Form code or name…', 'Form code বা name…'), place: L('লোকেশন', 'Place', 'Location'), allplaces: L('সব লোকেশন', 'All places', 'সব Location'),
  hint: L('প্রতিটি ফর্ম × লোকেশনের অবস্থা। এখন সব ‘অ্যাপ’। ‘কাগজ’ করলে সার্ভার নতুন অ্যাপ-এন্ট্রি নেবে না (শুধু ‘কাগজ থেকে পরে তোলা’); ‘পাশাপাশি’ ও ‘অ্যাপ’-এ কিছু আটকায় না।', 'The state of every form x place. Everything is App now. On Paper the server refuses new app entries (except “entered later from paper”); Parallel and App block nothing.', 'প্রতিটি form × location-এর state। এখন সব ‘App’। ‘Paper’ হলে server নতুন app entry নেবে না (শুধু ‘paper থেকে পরে তোলা’); ‘Parallel’ ও ‘App’-এ কিছু আটকায় না।'),
  bulk: L('একসাথে বদলান', 'Bulk set', 'একসাথে বদলান'), save: L('সেভ', 'Save', 'Save'), cancel: L('ক্যান্সেল', 'Cancel', 'Cancel'), done: L('হয়েছে', 'Done', 'Done'), saved: L('সেভ হয়েছে', 'Saved', 'Saved'),
  note: L('কারণ / নোট (ঐচ্ছিক)', 'Reason / note (optional)', 'Reason / note (ঐচ্ছিক)'), more: L('আরও', 'More', 'More'),
  setall: L('সব লোকেশনে', 'Set all places to', 'সব location-এ'), setplace: L('এই লোকেশনের সব ফর্ম', 'Set all forms at this place to', 'এই location-এর সব form'),
  scopeForms: L('কোন ফর্ম', 'Which forms', 'কোন form'), scopeAllF: L('সব ফর্ম', 'All forms', 'সব form'), scopeShown: L('এখন যেগুলো দেখাচ্ছে', 'Only those shown now', 'এখন যেগুলো দেখাচ্ছে'),
  scopePlaces: L('কোন লোকেশন', 'Which places', 'কোন location'), apply: L('অ্যাপ্লাই করুন', 'Apply', 'Apply'), ack: L('বুঝেছি: ‘কাগজ’ হলে নতুন অ্যাপ-এন্ট্রি আটকে যাবে', 'I understand: on Paper new app entries are refused', 'বুঝেছি: ‘Paper’ হলে নতুন app entry আটকে যাবে'),
  ackneed: L('আগে নিশ্চিত করুন', 'Tick the confirmation first', 'আগে confirm করুন'), n_cells: L('টি ঘর বদলাবে', 'cells will change', 'টি cell বদলাবে'),
  sw_title: L('সুইচ', 'Switches', 'Switch'), sw_enforce: L('‘কাগজ’ অবস্থায় অ্যাপে নতুন এন্ট্রি আটকানো', 'Refuse new app entries on Paper', 'Paper অবস্থায় app-এ নতুন entry আটকানো'), sw_later: L('‘কাগজ থেকে পরে তোলা’ চালু', 'Allow “entered later from paper”', '‘Paper থেকে পরে তোলা’ চালু'),
  sw_change: L('অ্যাপ্রুভড এন্ট্রি বদলের অনুরোধ চালু', 'Allow change requests on approved entries', 'Approved entry বদলের request চালু'), sw_self: L('মালিক নিজের অনুরোধ নিজে অ্যাপ্রুভ করতে পারবেন', 'Owner may approve his / her own request', 'Owner নিজের request নিজে approve করতে পারবেন'),
  on: L('চালু', 'On', 'On'), off: L('বন্ধ', 'Off', 'Off'), noacc: L('এই পাতা দেখার অনুমতি নেই', 'You cannot open this page', 'এই page দেখার permission নেই'), nof: L('কোনো ফর্ম মেলেনি', 'No forms match', 'কোনো form মেলেনি'),
  since: L('বদলেছে', 'Changed', 'Changed'), openlist: L('ফর্মের তালিকা', 'Open the form list', 'Form list'), numaudit: L('নম্বর মিলানো (ফাঁক ধরা)', 'Number audit (gaps)', 'Number audit (gap)'),
  // change requests
  c_title: L('বদলের অনুরোধ', 'Change requests', 'Change request'), c_pending: L('অপেক্ষায়', 'Waiting', 'Waiting'), c_mine: L('আমার অনুরোধ', 'My requests', 'My requests'), c_done: L('সিদ্ধান্ত হয়েছে', 'Decided', 'Decided'),
  c_none: L('কোনো অনুরোধ নেই', 'No requests', 'কোনো request নেই'), c_approve: L('অ্যাপ্রুভ', 'Approve', 'Approve'), c_reject: L('বাতিল করুন', 'Reject', 'Reject'), c_reason: L('কারণ', 'Reason', 'Reason'), c_by: L('অনুরোধ', 'Asked by', 'Asked by'),
  c_diff: L('যা বদলাবে', 'What changes', 'যা বদলাবে'), c_nodiff: L('ডেটায় বদল নেই (ফ্ল্যাগ/চেক অংশ)', 'No data fields change (flags / check part)', 'Data-তে বদল নেই (flag/check অংশ)'), c_more: L('আরও', 'more', 'more'),
  c_open: L('এন্ট্রি খুলুন', 'Open the entry', 'Entry খুলুন'), c_hist: L('সংস্করণের ইতিহাস', 'Revision history', 'Revision history'), c_cancel: L('অনুরোধ ফিরিয়ে নিন', 'Withdraw my request', 'Request ফিরিয়ে নিন'),
  c_rejnote: L('বাতিলের কারণ (লাগবেই)', 'Reason for rejecting (required)', 'Reject-এর কারণ (লাগবেই)'), c_approved: L('অ্যাপ্রুভড', 'Approved', 'Approved'), c_rejected: L('বাতিল', 'Rejected', 'Rejected'), c_cancelled: L('ফিরিয়ে নেওয়া', 'Withdrawn', 'Withdrawn'), c_pend: L('অপেক্ষায়', 'Waiting', 'Waiting'),
  c_ok: L('অ্যাপ্রুভড — নতুন সংস্করণ হয়েছে', 'Approved — a new revision was made', 'Approved — নতুন revision হয়েছে'),
  r_title: L('সংস্করণের ইতিহাস', 'Revision history', 'Revision history'), r_cur: L('বর্তমান', 'Current', 'Current'), r_first: L('প্রথম সংস্করণ', 'First version', 'First version'), r_rev: L('সংস্করণ', 'Revision', 'Revision'),
  r_hint: L('পুরনো সংস্করণ বদলানো যায় না; প্রতিটি বদল কে চেয়েছিলেন আর কে অ্যাপ্রুভ করেছেন তা থাকে।', 'Old versions can never be changed; each shows who asked and who approved.', 'পুরনো revision বদলানো যায় না; কে চেয়েছিলেন, কে approve করেছেন থাকে।'),
  r_asked: L('চেয়েছেন', 'Asked', 'Asked'), r_appr: L('অ্যাপ্রুভ', 'Approved by', 'Approved by'),
  // outbox
  o_title: L('ফোনে জমা — পাঠানো হয়নি', 'Not sent yet', 'Phone-এ জমা — Not sent yet'), o_none: L('কিছু জমা নেই — সবই পাঠানো হয়েছে', 'Nothing waiting — everything was sent', 'কিছু জমা নেই — সব পাঠানো হয়েছে'),
  o_hint: L('নেট না থাকলে এন্ট্রি এই ফোনে থাকে এবং নেট এলে নিজে থেকে যায়। এখান থেকে ফেলে দিলে শুধু এই ফোনের কপি মোছে, সার্ভারে কিছু বদলায় না।', 'Without network a record waits on this phone and goes by itself when online. Discarding here only removes the copy on THIS phone; nothing changes on the server.', 'Net না থাকলে entry এই phone-এ থাকে, online হলে নিজে যায়। এখানে discard করলে শুধু এই phone-এর copy মোছে।'),
  o_retry: L('আবার পাঠান', 'Retry', 'Retry'), o_retry_all: L('সব আবার পাঠান', 'Retry all', 'Retry all'), o_open: L('খুলুন', 'Open', 'Open'), o_disc: L('ফেলে দিন (শুধু এই ফোন থেকে)', 'Discard (this phone only)', 'Discard (শুধু এই phone)'),
  o_sure: L('এই ফোনে জমা থাকা এন্ট্রিটি ফেলে দেবেন? সার্ভারে এটি যায়নি, ফেললে তথ্য হারাবে।', 'Discard the entry waiting on this phone? It never reached the server, so the data will be lost.', 'এই phone-এ জমা entry ফেলে দেবেন? Server-এ যায়নি, তথ্য হারাবে।'),
  o_yes: L('হ্যাঁ, ফেলে দিন', 'Yes, discard', 'হ্যাঁ, discard'), o_wait: L('এখনও পাঠানো হয়নি', 'Not sent yet', 'Not sent yet'), o_refused: L('সার্ভার নেয়নি', 'Refused by the server', 'Server নেয়নি'), o_submit: L('জমা দেওয়া অপেক্ষায়', 'Submit pending', 'Submit pending'),
  o_others: L('এই ফোনে অন্য লগইনের জমা এন্ট্রি আছে — যিনি রেখেছিলেন তিনি সাইন-ইন করলে সেগুলো যাবে; মোছা হয়নি।', 'records of ANOTHER login are waiting on this phone - they will be sent when that person signs in; nothing was deleted.', 'এই phone-এ অন্য login-এর জমা entry আছে — সেই person sign-in করলে যাবে; মোছা হয়নি।'), o_others_n: L('অন্য লগইনের', 'Not yours', 'Not yours'),
  f_period: L('এই ডেটের হিসাব বন্ধ — মালিকের অনুমতি লাগবে', 'This date is closed - the owner must allow it', 'এই date-এর হিসাব বন্ধ — owner-এর অনুমতি লাগবে'), f_paused: L('এই লোকেশন এখন বিরতি/বন্ধ - নতুন এন্ট্রি নেওয়া হয় না', 'This place is paused or closed - no new entries', 'এই location paused/closed - নতুন entry নেওয়া হয় না'),
  f_perm: L('এই কাজের অনুমতি নেই', 'You are not allowed to do this', 'এই কাজের permission নেই'), f_note: L('কারণ/নোট লাগবে - এন্ট্রিটি খুলে লিখুন', 'A note is required - open the entry and add it', 'Note লাগবে - entry খুলে লিখুন'),
  f_red: L('লাল নিয়ন্ত্রণ - ছাড়ের অনুরোধ লাগবে, এন্ট্রিটি খুলুন', 'A red control needs a release request - open the entry', 'Red control - release request লাগবে, entry খুলুন'), f_auth: L('লগইনের মেয়াদ শেষ - আবার সাইন-ইন করলে নিজে যাবে', 'Login expired - it will go by itself after you sign in again', 'Login expired - আবার sign-in করলে নিজে যাবে'),
  f_locked: L('এন্ট্রি ইতিমধ্যে জমা/অ্যাপ্রুভড', 'The entry is already submitted / approved', 'Entry আগেই submitted/approved'), f_off: L('ফর্মটি বন্ধ আছে', 'This form is switched off', 'Form বন্ধ আছে'),
  sw_confirm_t: L('নিজের অনুরোধ নিজে অ্যাপ্রুভ বন্ধ করবেন?', 'Switch off owner self-approval?', 'Owner self-approval বন্ধ করবেন?'),
  sw_confirm: L('বন্ধ করলে মালিকের নিজের এন্ট্রি, ছাড়ের অনুরোধ, জরুরি অনুরোধ, আইটেম বদল ও বদলের অনুরোধ অন্য একজন অনুমোদনকারী ছাড়া আটকে থাকবে। অন্তত একজন অন্য অনুমোদনকারী থাকতে হবে।', "When off, the owner's own entries, release requests, emergency requests, item changes and change requests wait for another approver. At least one other approver must exist.", 'Off করলে owner-এর নিজের entry, release/emergency request, item change, change request অন্য approver ছাড়া আটকে থাকবে। অন্তত একজন অন্য approver লাগবে।'),
  sw_noother: L('অন্য কোনো অনুমোদনকারী নেই — আগে একজনকে অনুমতি দিন', 'There is no other approver - give someone the right first', 'অন্য approver নেই — আগে কাউকে অনুমতি দিন'), sw_off_go: L('হ্যাঁ, বন্ধ করুন', 'Yes, switch off', 'হ্যাঁ, বন্ধ করুন'),
  o_offline: L('এখন নেট নেই', 'You are offline', 'এখন net নেই'), o_online: L('নেট আছে', 'Online', 'Online'), o_sent: L('পাঠানো হয়েছে', 'Sent', 'Sent'),
};
const T = (k) => lab(X[k]);
const MODES = ['paper', 'parallel', 'app'];
const TONE = { paper: 'warn', parallel: 'info', app: 'ok' };
const norm = (v) => String(v ?? '').trim();
const fmtDT = (iso) => (iso ? String(iso).replace('T', ' ').slice(0, 16) : '');
const staffName = (sid) => { const s = ((B.ENV && B.ENV.staff) || []).find((x) => x.staff_id === sid); return s ? (s.full_name || s.staff_id) : (sid || ''); };
const errTxt = (e) => { const m = String((e && e.message) || ''); const hit = Object.keys(B.X17 || {}).filter((x) => x.startsWith('e_')).find((x) => m.includes(x.slice(2))); return hit ? lab(B.X17[hit]) : null; };
const fx = (e) => { const m = errTxt(e); if (m) return toast(m); if (/not allowed/.test((e && e.message) || '')) return toast(T('noacc')); fail(e); };
const mbtn = (act, label, attrs) => `<button class="full" style="margin-top:8px;text-align:left" data-act="${act}" ${attrs || ''}>${esc(label)}</button>`;
const friendly = (m) => { m = String(m || ''); const R = [[/pin_signature_stale/, () => lab(B.X17.e_pin_signature_stale)], [/pin_signature_required/, () => lab(B.X17.e_pin_signature_required)], [/rollout_paper/, () => lab(B.X17.e_rollout_paper)], [/period_closed/, 'f_period'], [/location_paused/, 'f_paused'], [/red_blocked/, 'f_red'], [/note_required/, 'f_note'], [/jwt|token|401|expired|unauthor/i, 'f_auth'],
  [/locked/, 'f_locked'], [/switched off/, 'f_off'], [/not allowed|permission|row-level/i, 'f_perm']];
  for (const [re, k] of R) if (re.test(m)) return typeof k === 'function' ? k() : T(k);
  return errTxt({ message: m }) || m.slice(0, 160); };

// ================= rollout board =================
const D = { forms: [], locs: [], cells: new Map(), q: '', fm: 'all', loc: 'all', mgr: false, sel: [] };
const key = (f, l) => f + '|' + l;
const modeOf = (f, l) => (D.cells.get(key(f, l)) || {}).mode || 'app';
async function allowed() {
  if (isOwner()) return true;
  try { return await A.hasAnyGrant(['rollout_manage']); } catch (e) { return false; }
}
async function loadBoard() {
  const [fr, lr, cr] = await Promise.all([sb.from('forms').select('code,name_bn,name_mix,name_en,sort,enabled').order('sort'), sb.from('locations').select('*').order('sort'), sb.from('form_rollout').select('*')]);
  if (fr.error || lr.error) { fail(fr.error || lr.error); return false; }
  D.forms = (fr.data || []).filter((f) => /^\d{1,2}-\d+$/.test(f.code) && f.code !== '0-1');
  D.locs = (lr.data || []).filter((l) => l.is_active !== false && l.status !== 'closed');
  D.cells = new Map(); ((cr && !cr.error && cr.data) || []).forEach((c) => D.cells.set(key(c.form_code, c.location_id), c));
  try { await B.reloadRules(); } catch (e) { /* ignore */ }
  return true;
}
async function viewRollout() {
  shell(T('title'), `<p class="muted">${esc(t('loading'))}</p>`, 'control');
  D.mgr = await allowed();
  if (!D.mgr) return shell(T('title'), `<div class="notice bad">${esc(T('noacc'))}</div>`, 'control');
  if (!(await loadBoard())) return;
  drawBoard();
}
const shownForms = () => {
  const q = D.q.trim().toLowerCase();
  return D.forms.filter((f) => (!q || (f.code + ' ' + (f.name_bn || '') + ' ' + (f.name_en || '') + ' ' + (f.name_mix || '')).toLowerCase().includes(q))
    && (D.fm === 'all' || (D.loc === 'all' ? D.locs.some((l) => modeOf(f.code, l.id) === D.fm) : modeOf(f.code, Number(D.loc)) === D.fm)));
};
const cellCount = (m) => D.forms.reduce((n, f) => n + D.locs.filter((l) => (D.loc === 'all' || l.id === Number(D.loc)) && modeOf(f.code, l.id) === m).length, 0);
const swOn = (k) => B.rule(k, true) !== false;
function drawBoard() {
  const rows = shownForms();
  const sw = (k, lb) => `<button class="tog ${swOn(k) ? 'on' : ''}" data-act="ro_sw" data-v="${k}" aria-pressed="${swOn(k)}" style="text-align:left">${esc(lb)} · ${esc(swOn(k) ? T('on') : T('off'))}</button>`;
  shell(T('title'), `<div class="notice ok">${esc(T('hint'))}</div>
    <div class="row wrap" id="ro_sum">${MODES.map((m) => `<span class="chip ${TONE[m]}" data-mode="${m}">${esc(T(m))} ${cellCount(m)}</span>`).join('')}</div>
    <div class="row"><input id="ro_q" type="search" autocomplete="off" placeholder="${esc(T('search'))}" value="${esc(D.q)}"><button class="primary" data-act="ro_bulk">${esc(T('bulk'))}</button></div>
    <div class="row wrap"><select id="ro_loc"><option value="all">${esc(T('allplaces'))}</option>${D.locs.map((l) => `<option value="${l.id}" ${String(l.id) === String(D.loc) ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select></div>
    <div class="row wrap" id="ro_chips" data-ctl="select">${['all', ...MODES].map((m) => `<button class="tog ${D.fm === m ? 'on' : ''}" data-act="ro_filter" data-v="${m}">${esc(T(m))}</button>`).join('')}</div>
    <div id="ro_list">${rows.length ? rows.map(card).join('') : `<p class="muted">${esc(T('nof'))}</p>`}</div>
    ${isOwner() ? `<h2>${esc(T('sw_title'))}</h2><div class="stack" id="ro_sw">${sw('rollout_enforce', T('sw_enforce'))}${sw('entered_later_on', T('sw_later'))}${sw('change_requests_on', T('sw_change'))}${sw('owner_self_approve', T('sw_self'))}</div>` : ''}`, 'control');
}
function card(f) {
  const ls = D.loc === 'all' ? D.locs : D.locs.filter((l) => l.id === Number(D.loc));
  const modes = ls.map((l) => modeOf(f.code, l.id));
  const tone = modes.includes('paper') ? 'warn' : modes.includes('parallel') ? 'info' : 'ok';
  return `<div class="card item mk ${tone}" data-form="${esc(f.code)}"><div style="flex:1;min-width:0"><div class="nm">${esc(f.code)} · ${esc(nm(f))}</div>
    <div class="row wrap" style="gap:6px;margin-top:6px">${ls.map((l) => { const m = modeOf(f.code, l.id); return `<button class="chip ${TONE[m]}" data-act="ro_cell" data-f="${esc(f.code)}" data-l="${l.id}" data-m="${m}" title="${esc(nm(l))}">${esc(String(l.code || l.id).slice(0, 7))} · ${esc(T(m))}</button>`; }).join('')}</div></div>
    <button class="mini" data-act="ro_menu" data-f="${esc(f.code)}" aria-label="${esc(T('more'))}">⋮</button></div>`;
}
document.addEventListener('input', (e) => { if (e.target && e.target.id === 'ro_q' && /^#\/rollout/.test(location.hash)) { D.q = e.target.value; const box = $('#ro_list'); if (box) { const r = shownForms(); box.innerHTML = r.length ? r.map(card).join('') : `<p class="muted">${esc(T('nof'))}</p>`; } } });
document.addEventListener('change', (e) => { if (e.target && e.target.id === 'ro_loc' && /^#\/rollout/.test(location.hash)) { D.loc = e.target.value; drawBoard(); } });
const locOf = (id) => D.locs.find((l) => l.id === Number(id));
const formOf = (c) => D.forms.find((f) => f.code === c);
function modeButtons(act, attrs, cur) { return MODES.map((m) => `<button class="${m === cur ? 'primary ' : ''}full" style="margin-top:8px" data-act="${act}" data-m="${m}" ${attrs}>${esc(T(m))}</button>`).join(''); }
function cellSheet(f, l) {
  const c = D.cells.get(key(f, l)) || {}, cur = modeOf(f, l);
  openSheet(`<h2>${esc(f)} · ${esc(nm(formOf(f) || {}))}</h2><div class="muted">${esc(nm(locOf(l) || {}))} · <span class="chip ${TONE[cur]}">${esc(T(cur))}</span>${c.changed_at ? ' · ' + esc(T('since')) + ' ' + esc(fmtDT(c.changed_at)) : ''}</div>
    ${c.note ? `<div class="muted" style="font-size:.85rem">${esc(c.note)}</div>` : ''}
    <div class="stack" style="margin-top:8px"><input id="ro_note" placeholder="${esc(T('note'))}" autocomplete="off">${modeButtons('ro_apply', `data-f="${esc(f)}" data-l="${l}"`, cur)}<button class="full" data-act="closesheet">${esc(T('cancel'))}</button></div>`);
}
function menuSheet(f) {
  openSheet(`<h2>${esc(f)} · ${esc(nm(formOf(f) || {}))}</h2><div class="stack"><input id="ro_note" placeholder="${esc(T('note'))}" autocomplete="off">
    <div class="muted">${esc(T('setall'))}</div>${modeButtons('ro_apply_all', `data-f="${esc(f)}"`, '')}
    ${mbtn('go', T('openlist'), `data-v="form/${esc(f)}"`)}${mbtn('go', T('numaudit'), 'data-v="numaudit"')}<button class="full" data-act="closesheet">${esc(T('cancel'))}</button></div>`);
}
async function rpcMany(forms, locs, mode, note) {
  const r = await sb.rpc('rollout_set_many', { p_forms: forms, p_locs: locs, p_mode: mode, p_note: note || null });
  if (r.error) return fx(r.error);
  toast(T('saved') + ' · ' + r.data); closeSheet(); await loadBoard(); drawBoard();
}
function bulkSheet() {
  const shown = shownForms().length;
  openSheet(`<h2>${esc(T('bulk'))}</h2><div class="stack">
    <div class="row wrap" id="bk_mode">${MODES.map((m, i) => `<button class="tog ${i === 2 ? 'on' : ''}" data-act="bk_m" data-m="${m}" id="bk_${m}">${esc(T(m))}</button>`).join('')}</div>
    <label>${esc(T('scopeForms'))}</label><select id="bk_forms"><option value="all">${esc(T('scopeAllF'))} (${D.forms.length})</option><option value="shown">${esc(T('scopeShown'))} (${shown})</option></select>
    <label>${esc(T('scopePlaces'))}</label><div class="stack" id="bk_places">${D.locs.map((l) => `<label class="ckrow"><input type="checkbox" class="bk_l" value="${l.id}" ${D.loc === 'all' || String(l.id) === String(D.loc) ? 'checked' : ''}><span>${esc(nm(l))}</span></label>`).join('')}</div>
    <input id="ro_note" placeholder="${esc(T('note'))}" autocomplete="off">
    <label class="ckrow" id="bk_ack_row" hidden><input type="checkbox" id="bk_ack"><span>${esc(T('ack'))}</span></label>
    <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="bk_go">${esc(T('apply'))}</button></div></div>`);
  H._bkMode = 'app';
}

// ================= diff / revisions =================
function flat(o, pre, out) {
  if (o === null || o === undefined) { out[pre] = ''; return out; }
  if (Array.isArray(o)) { if (!o.length) out[pre] = '[]'; o.forEach((v, i) => flat(v, pre + '.' + i, out)); return out; }
  if (typeof o === 'object') { const ks = Object.keys(o); if (!ks.length) out[pre] = '{}'; ks.forEach((k) => flat(o[k], pre ? pre + '.' + k : k, out)); return out; }
  out[pre] = String(o); return out;
}
function diff(a, b) {
  const fa = flat(a || {}, '', {}), fb = flat(b || {}, '', {}), out = [];
  new Set([...Object.keys(fa), ...Object.keys(fb)]).forEach((k) => { if ((fa[k] ?? '') !== (fb[k] ?? '')) out.push({ p: k, from: fa[k] ?? '', to: fb[k] ?? '' }); });
  return out;
}
const diffHTML = (d, max = 8) => `${d.slice(0, max).map((x) => `<div class="muted" style="font-size:.85rem;word-break:break-word"><b>${esc(x.p)}</b>: ${esc(x.from || '—')} → ${esc(x.to || '—')}</div>`).join('')}${d.length > max ? `<div class="muted" style="font-size:.85rem">+${d.length - max} ${esc(T('c_more'))}</div>` : ''}`;
async function showRevisions(id) {
  const r = await sb.rpc('entry_revisions_list', { p_entry: id });
  if (r.error) return fx(r.error);
  const list = r.data || [];
  openSheet(`<h2>${esc(T('r_title'))}</h2><div class="muted" style="font-size:.85rem">${esc(T('r_hint'))}</div><div class="stack" id="rev_list" style="margin-top:8px">${list.map((v, i) => {
    const older = list[i + 1], d = older ? diff(older.data, v.data) : [];
    return `<div class="card stack" data-rev="${v.rev_no}"><div class="row between"><b>${esc(T('r_rev'))} ${v.rev_no}</b>${v.current ? `<span class="chip ok">${esc(T('r_cur'))}</span>` : ''}</div>
      <div class="muted" style="font-size:.85rem">${esc(fmtDT(v.at))}${v.changed_staff ? ' · ' + esc(T('r_asked')) + ': ' + esc(staffName(v.changed_staff)) : ''}${v.approved_staff && !v.current ? ' · ' + esc(T('r_appr')) + ': ' + esc(staffName(v.approved_staff)) : ''}</div>
      ${v.reason ? `<div>${esc(v.reason)}</div>` : ''}${older ? (d.length ? diffHTML(d) : `<div class="muted" style="font-size:.85rem">${esc(T('c_nodiff'))}</div>`) : `<div class="muted" style="font-size:.85rem">${esc(T('r_first'))}</div>`}</div>`; }).join('')}</div>
    <button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('done'))}</button>`);
}
B.showRevisions = showRevisions;

// ================= change requests inbox =================
const C = { tab: 'pending', rows: [], ents: new Map(), mgr: false, me: null };
async function viewChanges() {
  shell(T('c_title'), `<p class="muted">${esc(t('loading'))}</p>`, 'home');
  try { await B.loadStatic(); } catch (e) { /* ignore */ }
  C.me = S.ctx.profile.id; C.mgr = isOwner() || (await A.hasAnyGrant(['change_approve']).catch(() => false));
  const r = await sb.from('entry_change_requests').select('*').order('id', { ascending: false }).limit(150);
  if (r.error) { shell(T('c_title'), `<div class="notice bad">${esc(T('noacc'))}</div>`, 'home'); return; }
  C.rows = r.data || [];
  const ids = [...new Set(C.rows.map((x) => x.entry_id))];
  C.ents = new Map();
  if (ids.length) { const e = await sb.from('entries').select('id,form_code,location_id,serial,entry_date,data,rev_no,status').in('id', ids); ((e && e.data) || []).forEach((x) => C.ents.set(x.id, x)); }
  drawChanges();
}
const canDecideRow = (x) => C.mgr && x.status === 'pending' && (x.requested_by !== C.me || (isOwner() && B.rule('owner_self_approve', true) !== false));
const chgRows = () => C.rows.filter((x) => (C.tab === 'pending' ? x.status === 'pending' && (C.mgr || x.requested_by === C.me) : C.tab === 'mine' ? x.requested_by === C.me : x.status !== 'pending'));
function drawChanges() {
  const rows = chgRows(), cnt = (k) => C.rows.filter((x) => (k === 'pending' ? x.status === 'pending' && (C.mgr || x.requested_by === C.me) : k === 'mine' ? x.requested_by === C.me : x.status !== 'pending')).length;
  shell(T('c_title'), `<div class="row wrap" id="ch_tabs">${[['pending', 'c_pending'], ['mine', 'c_mine'], ['done', 'c_done']].map(([k, lb]) => `<button class="tog ${C.tab === k ? 'on' : ''}" data-act="ch_tab" data-v="${k}">${esc(T(lb))} ${cnt(k)}</button>`).join('')}</div>
    <div id="ch_list">${rows.length ? rows.map(chgCard).join('') : `<p class="muted center">${esc(T('c_none'))}</p>`}</div>`, 'home');
}
function chgCard(x) {
  const e = C.ents.get(x.entry_id) || {}, lc = ((B.ENV && B.ENV.locs) || []).find((l) => l.id === e.location_id) || {};
  const d = x.patch && x.patch.data ? diff(e.data, x.patch.data) : [];
  const tone = x.status === 'approved' ? 'ok' : x.status === 'pending' ? 'warn' : 'bad';
  return `<div class="card stack mk ${tone}" data-req="${x.id}"><div class="row between"><b>${esc(e.form_code || '')}-${esc(lc.code || '')}-${e.serial || ''}</b><span class="chip ${tone}">${esc(T('c_' + (x.status === 'pending' ? 'pend' : x.status)))}</span></div>
    <div class="muted" style="font-size:.85rem">${esc(T('c_by'))}: ${esc(staffName(x.requested_staff))} · ${esc(fmtDT(x.created_at))} · ${esc(T('r_rev'))} ${x.base_rev}</div>
    <div><span class="muted">${esc(T('c_reason'))}:</span> ${esc(x.reason)}</div>
    <div><b style="font-size:.9rem">${esc(T('c_diff'))}</b>${d.length ? diffHTML(d) : `<div class="muted" style="font-size:.85rem">${esc(T('c_nodiff'))}</div>`}</div>
    ${x.decision_note ? `<div class="muted" style="font-size:.85rem">${esc(x.decision_note)}</div>` : ''}
    <div class="row">${canDecideRow(x) ? `<button class="danger full" data-act="ch_reject" data-v="${x.id}">${esc(T('c_reject'))}</button><button class="primary full" data-act="ch_approve" data-v="${x.id}">${esc(T('c_approve'))}</button>` : ''}<button class="mini" data-act="ch_menu" data-v="${x.id}" aria-label="${esc(T('more'))}">⋮</button></div></div>`;
}

// ================= outbox =================
const O = { off: null };
function itemTitle(it) { return `${it.code || ''} · ${it.date || (it.args && it.args.p_date) || ''}`; }
function viewOutbox() {
  shell(T('o_title'), `<p class="muted">${esc(t('loading'))}</p>`, 'home');
  drawOutbox();
  if (O.off) O.off();
  O.off = B.outbox.subscribe(() => { if (/^#\/outbox/.test(location.hash)) drawOutbox(); });
}
function drawOutbox() {
  const q = B.outbox.list().sort((a, z) => (a.at > z.at ? 1 : -1));
  shell(T('o_title'), `<div class="notice ${navigator.onLine ? 'ok' : 'warn'}">${esc(navigator.onLine ? T('o_online') : T('o_offline'))} · ${esc(T('o_hint'))}</div>
    ${B.outbox.others() ? `<div class="notice warn" id="ob_others"><b>${esc(T('o_others_n'))}: ${B.outbox.others()}</b> · ${esc(T('o_others'))}</div>` : ''}
    ${q.length ? `<button class="primary full" data-act="ob_retry_all">${esc(T('o_retry_all'))}</button>` : ''}
    <div id="ob_list">${q.length ? q.map((it) => {
      const refused = it.state === 'refused', tone = refused ? 'bad' : 'warn';
      return `<div class="card stack mk ${tone}" data-k="${esc(it.k)}"><div class="row between"><b>${esc(itemTitle(it))}</b><span class="chip ${tone}">${esc(refused ? T('o_refused') : it.kind === 'submit' ? T('o_submit') : T('o_wait'))}</span></div>
        <div class="muted" style="font-size:.85rem">${esc(fmtDT(it.at))}${it.ps ? ' · № ' + esc(it.ps) : ''}${it.submit && it.kind === 'entry' ? ' · ' + esc(T('o_submit')) : ''}</div>
        ${refused && it.msg ? `<div class="notice bad">${esc(friendly(it.msg))}<div class="muted" style="font-size:.75rem">${esc(String(it.msg).slice(0, 80))}</div></div>` : ''}
        <div class="row"><button class="full" data-act="ob_open" data-v="${esc(it.k)}">${esc(T('o_open'))}</button><button class="full" data-act="ob_retry" data-v="${esc(it.k)}">${esc(T('o_retry'))}</button><button class="mini" data-act="ob_disc" data-v="${esc(it.k)}" aria-label="${esc(T('o_disc'))}">⋮</button></div></div>`; }).join('') : `<p class="muted center">${esc(T('o_none'))}</p>`}</div>`, 'home');
}
window.addEventListener('online', () => { if (/^#\/outbox/.test(location.hash)) setTimeout(drawOutbox, 400); });
window.addEventListener('offline', () => { if (/^#\/outbox/.test(location.hash)) drawOutbox(); });

// ================= handlers =================
Object.assign(H, {
  ro_filter: (a) => { D.fm = a.dataset.v; drawBoard(); },
  ro_cell: (a) => cellSheet(a.dataset.f, Number(a.dataset.l)),
  ro_menu: (a) => menuSheet(a.dataset.f),
  ro_apply: async (a) => {
    const r = await sb.rpc('rollout_set', { p_form: a.dataset.f, p_loc: Number(a.dataset.l), p_mode: a.dataset.m, p_note: norm(($('#ro_note') || {}).value) || null });
    if (r.error) return fx(r.error); toast(T('saved')); closeSheet(); await loadBoard(); drawBoard(); },
  ro_apply_all: async (a) => { await rpcMany([a.dataset.f], null, a.dataset.m, norm(($('#ro_note') || {}).value)); },
  ro_bulk: () => bulkSheet(),
  bk_m: (a) => { H._bkMode = a.dataset.m; MODES.forEach((m) => { const b = $('#bk_' + m); if (b) b.classList.toggle('on', m === a.dataset.m); }); const r = $('#bk_ack_row'); if (r) r.hidden = a.dataset.m !== 'paper'; },
  bk_go: async () => {
    const mode = H._bkMode || 'app';
    if (mode === 'paper' && !($('#bk_ack') || {}).checked) return toast(T('ackneed'));
    const locs = [...document.querySelectorAll('.bk_l:checked')].map((x) => Number(x.value)); if (!locs.length) return toast(T('scopePlaces'));
    const forms = ($('#bk_forms') || {}).value === 'shown' ? shownForms().map((f) => f.code) : null;
    await rpcMany(forms, locs.length === D.locs.length ? null : locs, mode, norm(($('#ro_note') || {}).value)); },
  ro_sw_off_go: async () => {
    const r = await sb.rpc('owner_self_approve_set', { p_on: false });
    closeSheet(); if (r.error) return /no_other_approver/.test(r.error.message || '') ? toast(T('sw_noother')) : fx(r.error);
    toast(T('saved')); await B.reloadRules(); drawBoard(); },
  ro_sw: async (a) => {
    const k = a.dataset.v, on = !swOn(k);
    if (k === 'owner_self_approve') {      // guarded switch: OFF needs a confirmation and another approver (server checks)
      if (!on) return openSheet(`<h2>${esc(T('sw_confirm_t'))}</h2><div class="notice warn">${esc(T('sw_confirm'))}</div><div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="danger full" data-act="ro_sw_off_go">${esc(T('sw_off_go'))}</button></div>`);
      const r0 = await sb.rpc('owner_self_approve_set', { p_on: true }); if (r0.error) return fx(r0.error);
      toast(T('saved')); await B.reloadRules(); return drawBoard();
    }
    const r = await sb.rpc('set_rule', { p_key: k, p_value: on }); if (r.error) return fx(r.error);
    toast(T('saved')); await B.reloadRules(); drawBoard(); },
  ch_tab: (a) => { C.tab = a.dataset.v; drawChanges(); },
  ch_approve: async (a) => {
    const r = await sb.rpc('entry_change_decide', { p_id: Number(a.dataset.v), p_approve: true, p_note: null });
    if (r.error) return fx(r.error); toast(T('c_ok')); viewChanges(); },
  ch_reject: (a) => {
    openSheet(`<h2>${esc(T('c_reject'))}</h2><textarea id="ch_note" rows="3" placeholder="${esc(T('c_rejnote'))}"></textarea><div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="danger full" data-act="ch_reject_go" data-v="${a.dataset.v}">${esc(T('c_reject'))}</button></div>`); },
  ch_reject_go: async (a) => {
    const n = norm(($('#ch_note') || {}).value); if (!n) return toast(T('c_rejnote'));
    const r = await sb.rpc('entry_change_decide', { p_id: Number(a.dataset.v), p_approve: false, p_note: n });
    if (r.error) return fx(r.error); closeSheet(); toast(T('saved')); viewChanges(); },
  ch_menu: (a) => {
    const x = C.rows.find((r) => r.id === Number(a.dataset.v)); if (!x) return;
    openSheet(`<h2>#${x.id}</h2><div class="stack">${mbtn('ch_open', T('c_open'), `data-e="${x.entry_id}"`)}${mbtn('ch_hist', T('c_hist'), `data-e="${x.entry_id}"`)}${x.status === 'pending' && x.requested_by === C.me ? mbtn('ch_cancel', T('c_cancel'), `data-v="${x.id}"`) : ''}<button class="full" data-act="closesheet">${esc(T('cancel'))}</button></div>`); },
  ch_open: (a) => { closeSheet(); location.hash = '#/entry/' + a.dataset.e; },
  ch_hist: (a) => { closeSheet(); showRevisions(a.dataset.e); },
  ch_cancel: async (a) => { const r = await sb.rpc('entry_change_cancel', { p_id: Number(a.dataset.v) }); if (r.error) return fx(r.error); closeSheet(); toast(T('saved')); viewChanges(); },
  ob_retry: async (a) => { await B.outbox.retry(a.dataset.v); drawOutbox(); },
  ob_retry_all: async () => { B.outbox.list().filter((x) => x.state === 'refused').forEach((x) => B.outbox.retry(x.k)); await B.outbox.flush(); drawOutbox(); },
  ob_open: (a) => {
    const it = B.outbox.list().find((x) => x.k === a.dataset.v); if (!it) return;
    if (it.id) { location.hash = '#/entry/' + it.id; return; }
    const m = it.meta || {}, args = it.args || {};
    store.set('bos_tmp_' + it.code + '_' + it.loc, JSON.stringify({ d: args.p_data || {}, date: args.p_date, cid: it.cid || m.client_id, later: !!m.entered_later, ps: m.paper_serial || '', pat: m.paper_at ? String(m.paper_at).slice(0, 16) : '' }));
    location.hash = '#/entry/new/' + it.code + '/' + it.loc; },
  ob_disc: (a) => openSheet(`<h2>${esc(T('o_disc'))}</h2><div class="notice bad">${esc(T('o_sure'))}</div><div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="danger full" data-act="ob_disc_go" data-v="${esc(a.dataset.v)}">${esc(T('o_yes'))}</button></div>`),
  ob_disc_go: (a) => { B.outbox.discard(a.dataset.v); closeSheet(); drawOutbox(); },
});

window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { rollout: viewRollout, changes: viewChanges, outbox: viewOutbox });
})();
