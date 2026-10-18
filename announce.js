/* Islamia BOS · Announcements (#/announce) and the headline bar at the top of the app. Package R2-A.
   What it does: the owner (or a person he designates with the grant announce_post) posts a message to everyone, a role, a place or one person, with a start and an
   expiry time and an urgent flag. People it is addressed to see a slim scrolling headline bar at the top of every screen; tap it to read the full text and press
   "I have read this" (a read receipt the poster can see). With no active announcement for the viewer the bar is not drawn at all.
   Switch: announce_on (rules, OFF by default). OFF = no bar, no request to the server, no menu entry; the screen only says it is off.
   Server: supabase/phase130.sql (r2_announce_state / _post / _active / _seen / _mine / _receipts / _withdraw). The server is the authority on who may post and who may see.
   Motion: the bar scrolls slowly; it pauses on touch / hover / focus and with its own pause button; with prefers-reduced-motion it is a static one-line headline
   (the first item and "+N") and the full list is one tap away.
   Hook for the shell (docs/integration/R2.md): nav.js sync() calls BOS.announce.tick() after every screen is drawn.
   UNVERIFIED on a real phone and on a real Supabase project. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const X = {
  title: L('ঘোষণা ও নির্দেশ', 'Announcements', 'Announcements (ঘোষণা)'), bar: L('ঘোষণা', 'Announcements', 'ঘোষণা'),
  off: L('ঘোষণা এখন বন্ধ আছে। মালিক সেটিংসে "ঘোষণা চালু" করলে এটি কাজ করবে।', 'Announcements are switched off. The owner can switch them on in Settings (announce_on).', 'Announcements এখন বন্ধ। মালিক Settings-এ "announce_on" চালু করলে কাজ করবে।'),
  nofn: L('এই সুবিধা এখনো সার্ভারে বসানো হয়নি (phase130)।', 'The server does not have this yet (phase130).', 'এটি এখনো server-এ বসানো হয়নি (phase130)।'),
  nowon: L('এখন চলছে', 'On now', 'এখন চলছে'), none: L('এখন আপনার জন্য কোনো ঘোষণা নেই।', 'No announcement for you right now.', 'এখন আপনার জন্য কোনো ঘোষণা নেই।'),
  seenBtn: L('পড়েছি', 'I have read this', 'পড়েছি (Seen)'), seenDone: L('পড়েছেন', 'Read', 'পড়েছেন'), urgent: L('জরুরি', 'Urgent', 'জরুরি'),
  by: L('দিয়েছেন', 'from', 'from'), until: L('শেষ', 'until', 'until'), more: L('আরও', 'more', 'আরও'), unseen: L('না-পড়া', 'unread', 'না-পড়া'),
  pause: L('থামান', 'Pause', 'Pause'), play: L('চালান', 'Play', 'Play'), close: L('বন্ধ করুন', 'Close', 'Close'),
  newBtn: L('নতুন ঘোষণা', 'New announcement', 'নতুন ঘোষণা'), mine: L('আমার দেওয়া ঘোষণা', 'Posted by me', 'আমার দেওয়া ঘোষণা'), allPosts: L('সব ঘোষণা', 'All announcements', 'সব ঘোষণা'),
  fTitle: L('শিরোনাম (উপরের লাইনে দেখাবে)', 'Headline (shown on the bar)', 'Headline (bar-এ দেখাবে)'), fBody: L('বিস্তারিত (ট্যাপ করলে পড়া যাবে)', 'Full text (read on tap)', 'বিস্তারিত (tap করলে পড়া যাবে)'),
  fTo: L('কাদের জন্য', 'Who is it for', 'কাদের জন্য'), kAll: L('সবাই', 'Everyone', 'সবাই'), kRole: L('একটি ভূমিকা', 'A role', 'একটি role'), kLoc: L('একটি জায়গা / শাখা', 'A place', 'একটি জায়গা / শাখা'), kPerson: L('একজন', 'One person', 'একজন'),
  pick: L('বাছুন…', 'Choose…', 'বাছুন…'), fFrom: L('শুরু (ফাঁকা = এখনই)', 'Starts (blank = now)', 'শুরু (ফাঁকা = এখনই)'), fUntil: L('শেষ (ফাঁকা = তুলে না নেওয়া পর্যন্ত)', 'Expires (blank = until withdrawn)', 'শেষ (ফাঁকা = তুলে না নেওয়া পর্যন্ত)'),
  fUrgent: L('জরুরি (লাল দেখাবে)', 'Urgent (shown in red)', 'জরুরি (red দেখাবে)'), post: L('ঘোষণা দিন', 'Post', 'Post করুন'), cancel: L('বাতিল', 'Cancel', 'Cancel'),
  posted: L('ঘোষণা দেওয়া হয়েছে', 'Posted', 'Post হয়েছে'), reached: L('জন পাবে', 'will see it', 'জন পাবে'),
  receipts: L('কে পড়েছে', 'Who has read it', 'কে পড়েছে'), readList: L('পড়েছে', 'Read', 'পড়েছে'), unreadList: L('এখনো পড়েনি', 'Not read yet', 'এখনো পড়েনি'), nobody: L('কেউ না', 'Nobody', 'কেউ না'),
  withdraw: L('তুলে নিন', 'Withdraw', 'তুলে নিন'), wReason: L('কেন তুলে নিচ্ছেন (লিখতে হবে)', 'Why are you withdrawing it (required)', 'কেন তুলে নিচ্ছেন (লিখতে হবে)'), withdrawn: L('তুলে নেওয়া হয়েছে', 'Withdrawn', 'তুলে নেওয়া হয়েছে'),
  sLive: L('চলছে', 'Live', 'চলছে'), sLater: L('পরে শুরু', 'Scheduled', 'পরে শুরু'), sOver: L('শেষ', 'Expired', 'শেষ'), sWith: L('তুলে নেওয়া', 'Withdrawn', 'তুলে নেওয়া'),
  to: L('যাদের জন্য', 'To', 'To'), people: L('জন', 'people', 'জন'), readN: L('পড়েছে', 'read', 'read'), empty: L('এখনো কোনো ঘোষণা দেননি।', 'You have not posted anything yet.', 'এখনো কোনো ঘোষণা দেননি।'),
  cantPost: L('ঘোষণা দেওয়ার অনুমতি আপনার নেই। মালিক "ঘোষণা দেওয়া" অধিকার দিলে দিতে পারবেন।', 'You may read announcements but not post them. The owner can give you the right "Post announcements".', 'Post করার permission নেই। মালিক "Post announcements" অধিকার দিলে পারবেন।'),
  placeOnly: L('আপনি শুধু নিজের জায়গার জন্য ঘোষণা দিতে পারবেন।', 'You can post only to your own place.', 'আপনি শুধু নিজের জায়গার জন্য post করতে পারবেন।'),
  saved: L('হয়েছে', 'Done', 'Done'),
};
const T = (k) => lab(X[k]);
const E = {
  not_allowed: L('এটির অনুমতি নেই।', 'You are not allowed to do this.', 'এটির permission নেই।'), announce_off: L('ঘোষণা বন্ধ আছে।', 'Announcements are switched off.', 'Announcements বন্ধ আছে।'),
  bad_target: L('কাদের জন্য তা ঠিকভাবে বাছুন।', 'Choose who it is for.', 'কাদের জন্য তা বাছুন।'), title_required: L('শিরোনাম লিখুন।', 'Write a headline.', 'Headline লিখুন।'),
  text_too_long: L('লেখা বেশি লম্বা।', 'The text is too long.', 'লেখা বেশি লম্বা।'), bad_date: L('সময় ঠিক নয়: শেষ সময় শুরুর পরে এবং ভবিষ্যতে হতে হবে।', 'The times are not right: the end must be after the start and in the future.', 'সময় ঠিক নয়: end, start-এর পরে ও ভবিষ্যতে হতে হবে।'),
  reason_required: L('কারণ লিখুন।', 'Write a reason.', 'কারণ লিখুন।'),
};
const eText = (e) => { const m = String((e && e.message) || ''); for (const k of Object.keys(E)) if (m.indexOf(k.replace('not_allowed', 'not allowed')) >= 0) return lab(E[k]); return m || 'error'; };
const isMissing = (e) => e && (e.code === 'PGRST202' || /does not exist|could not find/i.test(e.message || ''));
const rm = () => { try { return !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches); } catch (e) { return false; } };

/* ---------- style (injected once) ---------- */
function css() {
  if (document.getElementById('r2a_css')) return;
  const st = document.createElement('style'); st.id = 'r2a_css';
  st.textContent = `
#r2_tick { display: flex; align-items: stretch; margin: -6px 0 12px; border: 1px solid var(--line); border-radius: 10px; background: var(--card); color: var(--text); overflow: hidden; min-height: 40px; }
#r2_tick.urgent { background: var(--bad-bg); color: var(--bad); border-color: var(--bad); }
#r2_tick .r2-main { flex: 1; min-width: 0; display: flex; align-items: center; gap: 8px; min-height: 40px; padding: 0 10px; border: 0; background: transparent; color: inherit; font: 600 .92rem/1.3 var(--text-font); text-align: start; cursor: pointer; box-shadow: none; border-radius: 0; }
#r2_tick .r2-lab { flex: none; font: 800 .72rem var(--text-font); letter-spacing: .04em; padding: 2px 8px; border-radius: 10px; background: var(--ruby); color: #fff4df; }
#r2_tick.urgent .r2-lab { background: var(--bad); color: var(--bad-bg); }
#r2_tick .r2-view { flex: 1; min-width: 0; overflow: hidden; white-space: nowrap; }
#r2_tick .r2-track { display: inline-block; white-space: nowrap; padding-inline-start: 100%; animation: r2tick var(--r2dur, 30s) linear infinite; }
#r2_tick:hover .r2-track, #r2_tick:focus-within .r2-track, #r2_tick:active .r2-track, #r2_tick.paused .r2-track { animation-play-state: paused; }
#r2_tick .r2-rest { display: none; }
#r2_tick .r2-sep { padding: 0 1.2em; opacity: .55; }
#r2_tick .r2-u { font-weight: 800; }
#r2_tick .r2-n { flex: none; align-self: center; margin-inline-end: 4px; min-width: 22px; text-align: center; font: 800 .75rem var(--text-font); padding: 1px 6px; border-radius: 10px; background: var(--warn-bg); color: var(--warn); }
#r2_tick .r2-pp { flex: none; width: 44px; min-height: 40px; padding: 0; border: 0; border-inline-start: 1px solid var(--line); border-radius: 0; background: transparent; color: inherit; box-shadow: none; font-size: .8rem; }
@keyframes r2tick { from { transform: translateX(0); } to { transform: translateX(-100%); } }
@media (prefers-reduced-motion: reduce) {
  #r2_tick .r2-track { animation: none !important; padding-inline-start: 0; display: block; overflow: hidden; text-overflow: ellipsis; }
  #r2_tick .r2-item ~ .r2-item, #r2_tick .r2-sep:not(.r2-rest) { display: none; }
  #r2_tick .r2-rest { display: inline; margin-inline-start: .6em; opacity: .8; }
  #r2_tick .r2-pp { display: none; }
}
.r2-card .r2-title { font-weight: 700; } .r2-card .r2-body { white-space: pre-wrap; margin: 6px 0; overflow-wrap: anywhere; }
.r2-card.urgent { border-color: var(--bad); }
.r2-btns { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 8px; } .r2-btns button { min-height: 44px; }
.r2-btns button { flex: 1 1 140px; }
.r2-chips { display: flex; flex-wrap: wrap; gap: 6px; margin: 4px 0; }
#r2a_u { width: 24px; min-height: 24px; flex: none; }
`;
  document.head.appendChild(st);
}

/* ---------- data ---------- */
const D = { items: null, at: 0, busy: null, st: null, mine: null, opts: null, timer: null, pause: false };
const dhaka = (ts) => (ts ? new Date(ts).toLocaleString('en-GB', { timeZone: 'Asia/Dhaka', day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit', hour12: false }) : '');
const live = (x) => !x.ends_at || new Date(x.ends_at).getTime() > Date.now();
const ruleOn = () => { try { return B.rule && B.rule('announce_on', false) === true; } catch (e) { return false; } };

async function fetchActive(force) {
  if (!force && D.items && Date.now() - D.at < 55000) return D.items;
  if (D.busy) return D.busy;
  D.busy = (async () => {
    try {
      const r = await sb.rpc('r2_announce_active');
      D.items = !r.error && Array.isArray(r.data) ? r.data : [];
    } catch (e) { D.items = []; }
    D.at = Date.now(); D.busy = null; return D.items;
  })();
  return D.busy;
}
const activeNow = () => (D.items || []).filter(live);

/* ---------- the bar ---------- */
function barHTML(items) {
  const urgent = items.some((x) => x.urgent);
  const seg = items.map((x) => `<span class="r2-item" data-id="${esc(x.id)}">${x.urgent ? `<span class="r2-u">${esc(T('urgent'))}: </span>` : ''}${esc(x.title)}</span>`);
  const one = seg.join('<span class="r2-sep" aria-hidden="true">•</span>');
  const rest = items.length > 1 ? `<span class="r2-rest r2-sep" aria-hidden="true">+${items.length - 1}</span>` : '';
  const unseen = items.filter((x) => !x.seen).length;
  const chars = items.reduce((n, x) => n + String(x.title || '').length + 12, 0);
  const dur = Math.max(14, Math.round(chars * 0.28));
  return { urgent, html: `<button type="button" class="r2-main" data-act="r2a_open" aria-label="${esc(T('bar') + ': ' + items.length)}"><span class="r2-lab">${esc(T('bar'))}</span>
    <span class="r2-view"><span class="r2-track" style="--r2dur:${dur}s">${one}${rest}</span></span></button>
    ${unseen ? `<span class="r2-n" aria-label="${esc(T('unseen'))}">${unseen}</span>` : ''}
    <button type="button" class="r2-pp" data-act="r2a_pause" aria-pressed="${D.pause}" aria-label="${esc(D.pause ? T('play') : T('pause'))}">${D.pause ? '▶\uFE0E' : '❚❚'}</button>` };
}
function draw() {
  const app = document.getElementById('app'); if (!app) return;
  const items = activeNow();
  let el = document.getElementById('r2_tick');
  const hd = app.querySelector('header.top');
  if (!hd || !items.length || !ruleOn()) { if (el) el.remove(); return; }
  css();
  const b = barHTML(items);
  if (el && el.previousElementSibling !== hd) { el.remove(); el = null; }
  if (!el) { el = document.createElement('div'); el.id = 'r2_tick'; el.setAttribute('role', 'region'); hd.insertAdjacentElement('afterend', el); }
  el.setAttribute('aria-label', T('bar'));
  el.className = (b.urgent ? 'urgent' : '') + (D.pause ? ' paused' : '');
  if (el.getAttribute('data-sig') !== b.html) { el.innerHTML = b.html; el.setAttribute('data-sig', b.html); }
  el.setAttribute('data-count', String(items.length));
}
async function tick(force) {
  try {
    if (!B.ENV || !B.ENV.rules) { if (B.loadStatic) B.loadStatic().then(() => tick(), () => {}); return; }
    if (!ruleOn()) { D.items = null; const el = document.getElementById('r2_tick'); if (el) el.remove(); return; }   // switch OFF: no bar, no request
    css();
    if (D.items) draw();                                   // the cached list at once (the shell was just redrawn)
    await fetchActive(!!force);
    draw();
    if (!D.timer) {
      D.timer = setInterval(() => { if (document.visibilityState === 'visible' && ruleOn()) tick(true); }, 60000);
      document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible' && ruleOn()) tick(); });
    }
  } catch (e) { /* the bar is a convenience: never break a screen */ }
}

/* ---------- the reading sheet ---------- */
function cardHTML(x) {
  return `<div class="card r2-card ${x.urgent ? 'urgent' : ''}" data-id="${esc(x.id)}"><div class="row between"><span class="r2-title">${x.urgent ? `<span class="chip bad">${esc(T('urgent'))}</span> ` : ''}${esc(x.title)}</span></div>
    ${x.body ? `<div class="r2-body">${esc(x.body)}</div>` : ''}
    <div class="muted" style="font-size:.85rem">${esc(T('by'))} ${esc(x.poster || '')} · ${esc(dhaka(x.posted_at))}${x.ends_at ? ' · ' + esc(T('until')) + ' ' + esc(dhaka(x.ends_at)) : ''}</div>
    <div class="r2-btns">${x.seen ? `<span class="chip ok">${esc(T('seenDone'))}</span>` : `<button type="button" class="primary" data-act="r2a_seen" data-v="${esc(x.id)}">${esc(T('seenBtn'))}</button>`}</div></div>`;
}
function openReader() {
  const items = activeNow();
  openSheet(`<h3>${esc(T('title'))}</h3><div id="r2a_read">${items.length ? items.map(cardHTML).join('') : B.ui.state('empty', T('none'))}</div>
    <div class="r2-btns"><button type="button" data-act="r2a_page">${esc(T('title'))} ›</button><button type="button" data-act="closesheet">${esc(T('close'))}</button></div>`);
}

/* ---------- the page ---------- */
async function rpc(fn, args) { const r = await sb.rpc(fn, args || {}); if (r.error) throw r.error; return r.data; }
const kindLabel = (x) => (x.target_kind === 'all' ? T('kAll') : x.target_kind === 'role' ? T('kRole') + ': ' + (x.target_role || '') : x.target_kind === 'location' ? T('kLoc') + ' #' + x.target_location : (x.target_name || T('kPerson')));
function statusOf(x) {
  if (x.status === 'withdrawn') return ['sWith', 'bad'];
  if (new Date(x.starts_at).getTime() > Date.now()) return ['sLater', 'warn'];
  if (x.ends_at && new Date(x.ends_at).getTime() <= Date.now()) return ['sOver', ''];
  return ['sLive', 'ok'];
}
function mineHTML(rows, st) {
  if (!rows.length) return B.ui.state('empty', T('empty'));
  return rows.map((x) => { const [sk, sc] = statusOf(x); const liveish = x.status === 'active' && !(x.ends_at && new Date(x.ends_at).getTime() <= Date.now());
    return `<div class="card r2-card ${x.urgent ? 'urgent' : ''}" data-id="${esc(x.id)}"><div class="r2-title">${esc(x.title)}</div>
      <div class="r2-chips"><span class="chip ${sc}">${esc(T(sk))}</span>${x.urgent ? `<span class="chip bad">${esc(T('urgent'))}</span>` : ''}<span class="chip">${esc(T('to'))}: ${esc(kindLabel(x))}</span>
      <span class="chip">${esc(x.seen)} / ${esc(x.audience)} ${esc(T('readN'))}</span></div>
      <div class="muted" style="font-size:.85rem">${esc(dhaka(x.starts_at))}${x.ends_at ? ' → ' + esc(dhaka(x.ends_at)) : ''} · ${esc(x.poster || '')}</div>
      ${x.withdrawn_reason ? `<div class="muted" style="font-size:.85rem">${esc(T('withdrawn'))}: ${esc(x.withdrawn_reason)}</div>` : ''}
      <div class="r2-btns"><button type="button" data-act="r2a_receipts" data-v="${esc(x.id)}">${esc(T('receipts'))}</button>${liveish ? `<button type="button" data-act="r2a_withdraw" data-v="${esc(x.id)}">${esc(T('withdraw'))}</button>` : ''}</div></div>`; }).join('');
}
async function view() {
  if (B.loadStatic) { try { await B.loadStatic(); } catch (e) { /* the page still opens */ } }
  css();
  shell(T('title'), `<div id="r2a_body"><p class="muted">…</p></div>`, true);
  await load();
}
async function load() {
  const box = $('#r2a_body'); if (!box) return;
  let st;
  try { st = await rpc('r2_announce_state'); } catch (e) { box.innerHTML = `<div class="notice warn">${esc(isMissing(e) ? T('nofn') : eText(e))}</div>`; return; }
  D.st = st;
  if (!st.on) { box.innerHTML = `<div class="notice warn" data-state="off">${esc(T('off'))}</div>`; return; }
  const items = await fetchActive(true); const act = items.filter(live);
  let mineRows = [];
  try { mineRows = await rpc('r2_announce_mine', { p_limit: 60 }); } catch (e) { mineRows = []; }
  D.mine = mineRows;
  const isOwner = !!(S.ctx && S.ctx.is_owner);
  box.innerHTML = `<div class="hsec">${esc(T('nowon'))}<small>${act.length}</small></div>
    <div id="r2a_now">${act.length ? act.map(cardHTML).join('') : B.ui.state('empty', T('none'))}</div>
    ${st.can_post ? `<button type="button" class="primary full" data-act="r2a_new">${esc(T('newBtn'))}</button>` : `<div class="muted" style="margin:8px 0">${esc(T('cantPost'))}</div>`}
    ${st.can_post || mineRows.length ? `<div class="hsec">${esc(isOwner ? T('allPosts') : T('mine'))}<small>${mineRows.length}</small></div><div id="r2a_mine">${mineHTML(mineRows, st)}</div>` : ''}`;
  draw();
}

/* ---------- compose ---------- */
const dtIso = (v) => (v ? v + ':00+06:00' : null);          // datetime-local is read as Dhaka time (no daylight saving)
async function composeSheet() {
  const st = D.st || {}; const all = !!st.can_post_all;
  let roles = []; try { const r = await sb.from('roles').select('code,name_bn,name_en,name_mix,active').order('sort'); roles = (r.data || []).filter((x) => x.active !== false); } catch (e) { roles = []; }
  const locs = ((B.ENV && B.ENV.locs) || []).filter((l) => all || (st.post_locations || []).indexOf(l.id) >= 0);
  const staff = (B.ENV && B.ENV.staff) || [];
  const nameOf = (o) => lab(L(o.name_bn, o.name_en || o.name_bn, o.name_mix || o.name_bn));
  const kinds = all ? ['all', 'role', 'location', 'person'] : ['location'];
  D.opts = { roles, locs, staff };
  openSheet(`<h3>${esc(T('newBtn'))}</h3><div class="stack" id="r2a_form">
    <div><label for="r2a_t">${esc(T('fTitle'))}</label><input id="r2a_t" maxlength="120" autocomplete="off"></div>
    <div><label for="r2a_b">${esc(T('fBody'))}</label><textarea id="r2a_b" rows="4" maxlength="2000"></textarea></div>
    ${all ? '' : `<div class="muted">${esc(T('placeOnly'))}</div>`}
    <div><label for="r2a_k">${esc(T('fTo'))}</label><select id="r2a_k">${kinds.map((k) => `<option value="${k}">${esc(T({ all: 'kAll', role: 'kRole', location: 'kLoc', person: 'kPerson' }[k]))}</option>`).join('')}</select></div>
    <div id="r2a_tw"></div>
    <div class="row wrap"><div style="flex:1 1 150px"><label for="r2a_s">${esc(T('fFrom'))}</label><input id="r2a_s" type="datetime-local"></div><div style="flex:1 1 150px"><label for="r2a_e">${esc(T('fUntil'))}</label><input id="r2a_e" type="datetime-local"></div></div>
    <label class="row" style="align-items:center"><input type="checkbox" id="r2a_u"> ${esc(T('fUrgent'))}</label>
    <div class="r2-btns"><button type="button" class="primary" data-act="r2a_post">${esc(T('post'))}</button><button type="button" data-act="closesheet">${esc(T('cancel'))}</button></div></div>`);
  kindChanged();
  const k = $('#r2a_k'); if (k) k.addEventListener('change', kindChanged);
}
function kindChanged() {
  const k = ($('#r2a_k') || {}).value, w = $('#r2a_tw'); if (!w) return;
  const o = D.opts || { roles: [], locs: [], staff: [] };
  const nm = (x) => lab(L(x.name_bn, x.name_en || x.name_bn, x.name_mix || x.name_bn));
  const opt = (v, t) => `<option value="${esc(v)}">${esc(t)}</option>`;
  w.innerHTML = k === 'role' ? `<label for="r2a_x">${esc(T('kRole'))}</label><select id="r2a_x"><option value="">${esc(T('pick'))}</option>${o.roles.map((r) => opt(r.code, nm(r))).join('')}</select>`
    : k === 'location' ? `<label for="r2a_x">${esc(T('kLoc'))}</label><select id="r2a_x"><option value="">${esc(T('pick'))}</option>${o.locs.map((l) => opt(l.id, nm(l))).join('')}</select>`
    : k === 'person' ? `<label for="r2a_x">${esc(T('kPerson'))}</label><select id="r2a_x"><option value="">${esc(T('pick'))}</option>${o.staff.map((p) => opt(p.id, (p.full_name || p.staff_id) + ' · ' + p.staff_id)).join('')}</select>` : '';
}

/* ---------- handlers ---------- */
Object.assign(H, {
  r2a_open: () => { openReader(); fetchActive(true).then(() => { draw(); const r = $('#r2a_read'); if (r) r.innerHTML = activeNow().length ? activeNow().map(cardHTML).join('') : B.ui.state('empty', T('none')); }); },
  r2a_page: () => { closeSheet(); A.go('announce'); },
  r2a_pause: () => { D.pause = !D.pause; const el = document.getElementById('r2_tick'); if (el) el.setAttribute('data-sig', ''); draw(); },
  r2a_seen: async (a) => {
    try { await rpc('r2_announce_seen', { p_id: Number(a.dataset.v) }); } catch (e) { return toast(eText(e)); }
    await fetchActive(true); draw();
    if ($('#r2a_read')) $('#r2a_read').innerHTML = activeNow().length ? activeNow().map(cardHTML).join('') : B.ui.state('empty', T('none'));
    if ($('#r2a_now')) { const act = activeNow(); $('#r2a_now').innerHTML = act.length ? act.map(cardHTML).join('') : B.ui.state('empty', T('none')); }
  },
  r2a_new: () => composeSheet(),
  r2a_post: async () => {
    const kind = ($('#r2a_k') || {}).value || 'all', tg = ($('#r2a_x') || {}).value || null;
    const title = (($('#r2a_t') || {}).value || '').trim();
    if (!title) return toast(lab(E.title_required));
    if (kind !== 'all' && !tg) return toast(lab(E.bad_target));
    const client = (window.crypto && crypto.randomUUID) ? crypto.randomUUID() : null;
    try {
      const r = await rpc('r2_announce_post', { p_title: title, p_body: (($('#r2a_b') || {}).value || '').trim(), p_urgent: !!($('#r2a_u') || {}).checked, p_kind: kind, p_target: tg === null ? null : String(tg),
        p_starts: dtIso(($('#r2a_s') || {}).value), p_ends: dtIso(($('#r2a_e') || {}).value), p_client: client });
      closeSheet(); toast(T('posted') + (r && r.audience !== undefined ? ' · ' + r.audience + ' ' + T('reached') : ''));
      await fetchActive(true); await load();
    } catch (e) { toast(eText(e)); }
  },
  r2a_receipts: async (a) => {
    let r; try { r = await rpc('r2_announce_receipts', { p_id: Number(a.dataset.v) }); } catch (e) { return toast(eText(e)); }
    const li = (arr, withTime) => (arr.length ? `<ul style="margin:4px 0;padding-inline-start:20px">${arr.map((p) => `<li>${esc(p.name)}${withTime ? ` <span class="muted">· ${esc(dhaka(p.seen_at))}</span>` : ''}</li>`).join('')}</ul>` : `<div class="muted">${esc(T('nobody'))}</div>`);
    openSheet(`<h3>${esc(T('receipts'))}</h3><div class="r2-title">${esc(r.title)}</div>
      <div class="hsec">${esc(T('readList'))}<small>${r.seen.length}</small></div><div id="r2a_seenlist">${li(r.seen, true)}</div>
      <div class="hsec">${esc(T('unreadList'))}<small>${r.unseen.length}</small></div><div id="r2a_unseenlist">${li(r.unseen, false)}</div>
      <div class="r2-btns"><button type="button" data-act="closesheet">${esc(T('close'))}</button></div>`);
  },
  r2a_withdraw: (a) => {
    openSheet(`<h3>${esc(T('withdraw'))}</h3><div class="stack"><div><label for="r2a_wr">${esc(T('wReason'))}</label><input id="r2a_wr" maxlength="200" autocomplete="off"></div>
      <div class="r2-btns"><button type="button" class="primary" data-act="r2a_wgo" data-v="${esc(a.dataset.v)}">${esc(T('withdraw'))}</button><button type="button" data-act="closesheet">${esc(T('cancel'))}</button></div></div>`);
  },
  r2a_wgo: async (a) => {
    const reason = (($('#r2a_wr') || {}).value || '').trim(); if (!reason) return toast(lab(E.reason_required));
    try { await rpc('r2_announce_withdraw', { p_id: Number(a.dataset.v), p_reason: reason }); closeSheet(); toast(T('withdrawn')); await fetchActive(true); await load(); } catch (e) { toast(eText(e)); }
  },
});

B.announce = { tick, refresh: () => tick(true), open: openReader, active: () => activeNow() };
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { announce: view });
})();
