/* Islamia BOS · Setup advisor (#/setupadvisor) - step S2: recommended choices, "before you switch it on" checks, "is everything flowing?" checks.
   Server side: supabase/phase81.sql. ADVISORY ONLY: nothing on this page blocks a sale, purchase, production or order. The one write is the owner's own tap
   on "Apply recommended" (setup_recommend_apply): it never replaces a value the owner already chose unless he taps "Replace" on that row.
     setup_recommendations · setup_recommend_apply · setup_readiness · setup_flow_check · setup_apply_history
   Phone width: single column of cards. All texts via B.L(bn, en, mix); texts that come from the server carry bn / mix / en and are picked by the same language setting. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, shell, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const X = {
  title: L('চালু করার গাইড', 'Setup advisor', 'চালু করার guide'),
  intro: L('এটা শুধু পরামর্শ — কোনো কাজ আটকায় না। আপনি যা ঠিক করেছেন তা আপনার কথামতোই থাকে।', 'Advice only - nothing is blocked. A value you chose yourself stays as you set it.', 'এটা শুধু পরামর্শ — কোনো কাজ আটকায় না। আপনি যা ঠিক করেছেন তা আপনার কথামতোই থাকে।'),
  t_rec: L('প্রস্তাবিত', 'Recommended', 'Recommended'), t_ready: L('চালুর আগে', 'Before switching on', 'চালুর আগে'), t_flow: L('সব ঠিকঠাক বইছে?', 'Is it all flowing?', 'সব ঠিকঠাক বইছে?'), t_hist: L('ইতিহাস', 'History', 'History'),
  s_ok: L('ঠিক আছে', 'As recommended', 'ঠিক আছে'), s_recommended: L('প্রস্তাব আছে', 'Suggested', 'প্রস্তাব আছে'), s_owner_chosen: L('আপনার বেছে নেওয়া', 'Your own choice', 'আপনার বেছে নেওয়া'),
  s_info: L('আপনি ঠিক করবেন', 'Your decision', 'আপনি ঠিক করবেন'), s_not_installed: L('এখনো যোগ হয়নি', 'Not installed yet', 'এখনো যোগ হয়নি'),
  now: L('এখন', 'Now', 'এখন'), rec: L('প্রস্তাব', 'Recommended', 'প্রস্তাব'), dflt: L('শুরুর মান', 'Default', 'শুরুর value'), range: L('সীমা', 'Range', 'Range'),
  on: L('চালু', 'ON', 'ON'), off: L('বন্ধ', 'OFF', 'OFF'),
  apply: L('প্রস্তাবিত প্রয়োগ', 'Apply recommended', 'প্রস্তাবিত apply'), applyAll: L('সব প্রস্তাবিত প্রয়োগ', 'Apply all recommended', 'সব প্রস্তাবিত apply'),
  applyAny: L('তবুও প্রয়োগ', 'Apply anyway', 'তবুও apply'), replace: L('আমার মানের বদলে প্রস্তাবিত', 'Replace my value', 'আমার value বদলে প্রস্তাবিত'),
  confirmAll: L('যেগুলো তৈরি আছে সেগুলো প্রয়োগ হবে। আপনার নিজের বেছে নেওয়া কিছু বদলাবে না। চালাবেন?', 'Every row that is ready will be applied. Nothing you chose yourself is changed. Go on?', 'যেগুলো ready আছে সেগুলো apply হবে। আপনার নিজের বেছে নেওয়া কিছু বদলাবে না। চালাবেন?'),
  confirmAny: L('এখনো সব তৈরি নয়। তবুও প্রয়োগ করবেন?', 'Not everything is ready yet. Apply anyway?', 'এখনো সব ready নয়। তবুও apply করবেন?'),
  confirmOwn: L('আপনার আগের মান বদলে যাবে (ইতিহাসে থাকবে)। করবেন?', 'Your earlier value will be replaced (kept in the history). Do it?', 'আপনার আগের value বদলে যাবে (history তে থাকবে)। করবেন?'),
  changeIn: L('মান লিখতে সুইচবোর্ড খুলুন', 'Open the Switchboard to type a value', 'Value লিখতে Switchboard খুলুন'),
  notReady: L('এখনো তৈরি নয়', 'Not ready yet', 'এখনো ready নয়'), ready: L('তৈরি', 'Ready', 'Ready'),
  applied: L('প্রয়োগ হয়েছে', 'Applied', 'Apply হয়েছে'), skipped: L('বাদ', 'Skipped', 'Skipped'),
  r_not_ready: L('এখনো তৈরি নয়', 'not ready', 'ready নয়'), r_owner_chosen: L('আপনার নিজের মান', 'your own value', 'আপনার নিজের value'), r_already: L('আগেই ঠিক', 'already right', 'আগেই ঠিক'),
  r_no_recommendation: L('প্রস্তাব নেই', 'no recommendation', 'প্রস্তাব নেই'), r_not_installed: L('যোগ হয়নি', 'not installed', 'যোগ হয়নি'), r_rejected: L('নেওয়া গেল না', 'rejected', 'নেওয়া গেল না'),
  readyTopic: L('সব তৈরি ✓', 'All ready ✓', 'সব ready ✓'), problems: L('টি সমস্যা', 'to fix', 'টি সমস্যা'), fixIt: L('কী করবেন', 'What to do', 'কী করবেন'), open: L('খুলুন', 'Open', 'খুলুন'),
  na: L('বন্ধ আছে — দেখার কিছু নেই', 'Off - nothing to check', 'বন্ধ আছে — দেখার কিছু নেই'), flowOk: L('ঠিক বইছে ✓', 'Flowing ✓', 'ঠিক বইছে ✓'), warnN: L('টি সতর্কতা', 'warnings', 'টি সতর্কতা'),
  histNone: L('এখনো কিছু প্রয়োগ করা হয়নি', 'Nothing has been applied yet', 'এখনো কিছু apply করা হয়নি'), loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), none: L('কিছু নেই ✓', 'Nothing ✓', 'কিছু নেই ✓'),
  e_not_allowed: L('এই অংশ দেখার অনুমতি আপনার নেই', 'You do not have access to this part', 'এই অংশের access নেই'),
};
const T = (k) => lab(X[k]);
const D = { tab: 'rec', rec: null, ready: null, flow: null, hist: null, err: {} };
const FRIENDLY = { 'not allowed': 'e_not_allowed' };
const rid = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3) | 8).toString(16); }));
const msg = (e) => { const m = String((e && e.message) || e || ''); const k = Object.keys(FRIENDLY).find((x) => m.indexOf(x) >= 0); return k ? T(FRIENDLY[k]) : m; };

/* ---------- pure helpers (tested) ---------- */
const pick = (o, base) => lab(L(o[base + '_bn'] || '', o[base + '_en'] || '', o[base + '_mix'] || o[base + '_bn'] || ''));
const fmt = (v) => (v === true ? T('on') : v === false ? T('off') : v === null || v === undefined || v === '' ? '-' : String(v));
const tone = (s) => ({ ok: 'ok', recommended: 'warn', owner_chosen: '', info: '', not_installed: '' }[s] || '');
const canApplyRow = (it) => it && it.status === 'recommended';
const skipTxt = (r) => (X['r_' + r] ? T('r_' + r) : String(r || ''));
const goto = (nav) => (nav ? `<a class="mini" href="#/${esc(nav)}">${esc(T('open'))}</a>` : '');

/* ---------- drawing ---------- */
const errBox = (k) => (D.err[k] ? `<p class="muted" role="alert">${esc(D.err[k])}</p>` : '');
function drawRow(it, canApply) {
  const isNum = it.status === 'info' && it.kind === 'number';
  const nums = isNum ? `<div class="muted">${esc(T('dflt'))}: ${esc(fmt(it.default))}${it.min !== null && it.max !== null && it.min !== undefined ? ' · ' + esc(T('range')) + ': ' + esc(String(it.min)) + '–' + esc(String(it.max)) + (it.unit ? ' ' + esc(it.unit) : '') : ''}</div>` : '';
  const vals = it.status === 'info' || it.status === 'not_installed' ? '' : `<div class="row wrap"><span class="chip">${esc(T('now'))}: ${esc(fmt(it.current))}</span><span class="chip">${esc(T('rec'))}: ${esc(fmt(it.recommended))}</span></div>`;
  const issues = (it.ready_issues || []).map((i) => `<div class="muted">• ${esc(pick(i, 'label'))} (${esc(String(i.n))})</div>`).join('');
  let btn = '';
  if (canApply && it.status === 'recommended') btn = `<button type="button" class="btn primary" data-act="sadv_apply" data-code="${esc(it.code)}" data-ready="${it.ready ? 1 : 0}">${esc(it.ready ? T('apply') : T('applyAny'))}</button>`;
  if (canApply && it.status === 'owner_chosen') btn = `<button type="button" class="mini" data-act="sadv_replace" data-code="${esc(it.code)}">${esc(T('replace'))}</button>`;
  if (isNum || (it.status === 'info' && it.kind !== 'number' && !it.recommended)) btn = `<a class="mini" href="#/switchboard">${esc(T('changeIn'))}</a>`;
  return `<div class="card stack"><div class="row between wrap"><b>${esc(pick(it, 'rule_label'))}</b><span class="chip ${tone(it.status)}">${esc(T('s_' + it.status))}</span></div>
    ${vals}${nums}<p>${esc(pick(it, 'reason'))}</p>${it.status === 'recommended' && !it.ready ? `<div class="chip warn">${esc(T('notReady'))}</div>${issues}` : ''}${btn}</div>`;
}
function drawRec() {
  const d = D.rec; if (!d) return D.err.rec ? errBox('rec') : `<p class="muted">${esc(T('loading'))}</p>`;
  const s = d.summary || {};
  return `<div class="card stack"><div class="row wrap"><span class="chip ok">${esc(T('s_ok'))}: ${esc(String(s.ok || 0))}</span><span class="chip warn">${esc(T('s_recommended'))}: ${esc(String(s.recommended || 0))}</span>
    <span class="chip">${esc(T('s_owner_chosen'))}: ${esc(String(s.owner_chosen || 0))}</span><span class="chip">${esc(T('s_info'))}: ${esc(String(s.info || 0))}</span></div>
    ${d.can_apply && (s.recommended || 0) > 0 ? `<button type="button" class="btn primary" data-act="sadv_apply_all">${esc(T('applyAll'))}</button>` : ''}${errBox('rec')}</div>
    ${(d.items || []).filter((it) => it.status !== 'not_installed').map((it) => drawRow(it, d.can_apply)).join('')}`;
}
function drawReady() {
  const d = D.ready; if (!d) return D.err.ready ? errBox('ready') : `<p class="muted">${esc(T('loading'))}</p>`;
  return (d.topics || []).map((t) => `<div class="card stack"><div class="row between wrap"><b>${esc(pick(t, 'label'))}</b>
    <span class="chip ${t.ready ? 'ok' : 'warn'}">${t.ready ? esc(T('readyTopic')) : esc(String(t.problem_checks) + ' ' + T('problems'))}</span></div>
    ${(t.checks || []).filter((c) => c.applies).map((c) => `<div class="stack"><div class="row between wrap"><span>${esc(pick(c, 'label'))}${c.ok ? '' : ' (' + esc(String(c.problems)) + ')'}</span><span class="chip ${c.ok ? 'ok' : c.level === 'info' ? '' : 'warn'}">${esc(c.ok ? T('ready') : T('notReady'))}</span></div>
      ${c.ok ? '' : `<div class="muted">${esc(T('fixIt'))}: ${esc(pick(c, 'fix'))} ${goto(c.nav)}</div>`}</div>`).join('')}</div>`).join('') + errBox('ready');
}
function drawFlow() {
  const d = D.flow; if (!d) return D.err.flow ? errBox('flow') : `<p class="muted">${esc(T('loading'))}</p>`;
  return `<div class="card stack"><span class="chip ${d.warnings ? 'warn' : 'ok'}">${d.warnings ? esc(String(d.warnings) + ' ' + T('warnN')) : esc(T('flowOk'))}</span></div>` +
    (d.checks || []).map((c) => `<div class="card stack"><div class="row between wrap"><span>${esc(pick(c, 'label'))}${c.level === 'warn' || c.level === 'info' ? ' (' + esc(String(c.problems)) + ')' : ''}</span>
      <span class="chip ${c.level === 'ok' ? 'ok' : c.level === 'warn' ? 'warn' : ''}">${esc(c.level === 'na' ? T('na') : c.level === 'ok' ? T('flowOk') : T('notReady'))}</span></div>
      ${c.level === 'warn' || c.level === 'info' ? `<div class="muted">${esc(T('fixIt'))}: ${esc(pick(c, 'fix'))} ${goto(c.nav)}</div>` : ''}</div>`).join('') + errBox('flow');
}
function drawHist() {
  const d = D.hist; if (!d) return D.err.hist ? errBox('hist') : `<p class="muted">${esc(T('loading'))}</p>`;
  if (!d.length) return `<div class="card"><p class="muted">${esc(T('histNone'))}</p></div>`;
  return d.map((b) => `<div class="card stack"><div class="muted">${esc(String(b.applied_at || '').slice(0, 16).replace('T', ' '))}</div>
    ${(b.lines || []).map((l) => `<div class="row between wrap"><span>${esc(l.rule_key)}</span><span class="muted">${esc(fmt(l.old))} → ${esc(fmt(l.new))}${l.overwrote ? ' *' : ''}</span></div>`).join('')}</div>`).join('');
}
function draw() {
  const el = $('#sadv_body'); if (!el) return;
  const tabs = ['rec', 'ready', 'flow', 'hist'];
  el.innerHTML = `<p class="muted">${esc(T('intro'))}</p><div class="row wrap" role="tablist">${tabs.map((t) => `<button type="button" class="btn ${D.tab === t ? 'primary' : ''}" role="tab" aria-selected="${D.tab === t}" data-act="sadv_tab" data-t="${t}">${esc(T('t_' + t))}</button>`).join('')}</div>
    ${D.tab === 'rec' ? drawRec() : D.tab === 'ready' ? drawReady() : D.tab === 'flow' ? drawFlow() : drawHist()}`;
}

/* ---------- loading + actions ---------- */
async function load(tab) {
  D.err[tab] = '';
  try {
    if (tab === 'rec') { const r = await sb.rpc('setup_recommendations'); if (r.error) throw r.error; D.rec = r.data; }
    if (tab === 'ready') { const r = await sb.rpc('setup_readiness', { p_topic: null }); if (r.error) throw r.error; D.ready = r.data; }
    if (tab === 'flow') { const r = await sb.rpc('setup_flow_check'); if (r.error) throw r.error; D.flow = r.data; }
    if (tab === 'hist') { const r = await sb.rpc('setup_apply_history', { p_limit: 30 }); if (r.error) throw r.error; D.hist = r.data; }
  } catch (e) { D.err[tab] = msg(e); D[tab] = null; }
  draw();
}
async function doApply(codes, overwrite, ignoreReady) {
  const r = await sb.rpc('setup_recommend_apply', { p_client: rid(), p_codes: codes, p_overwrite: !!overwrite, p_ignore_ready: !!ignoreReady });
  if (r.error) return toast(msg(r.error));
  const n = (r.data && r.data.count) || 0, sk = ((r.data && r.data.skipped) || []).filter((x) => x.reason !== 'no_recommendation' && x.reason !== 'already');
  toast(`${T('applied')}: ${n}` + (sk.length ? ` · ${T('skipped')}: ${sk.map((x) => skipTxt(x.reason)).filter((v, i, a) => a.indexOf(v) === i).join(', ')}` : ''));
  D.hist = null; await load('rec');
}
Object.assign(H, {
  sadv_tab: async (a) => { D.tab = a.dataset.t; draw(); await load(D.tab); },
  sadv_apply: async (a) => { if (a.dataset.ready === '0' && !window.confirm(T('confirmAny'))) return; await doApply([a.dataset.code], false, a.dataset.ready === '0'); },
  sadv_apply_all: async () => { if (!window.confirm(T('confirmAll'))) return; await doApply(null, false, false); },
  sadv_replace: async (a) => { if (!window.confirm(T('confirmOwn'))) return; await doApply([a.dataset.code], true, true); },
});
async function view() {
  if (B.loadStatic) await B.loadStatic();
  D.rec = D.ready = D.flow = D.hist = null; D.err = {};
  shell(T('title'), '<div id="sadv_body" class="stack"></div>', true);
  draw(); await load(D.tab);
}
B.setupadvisor = { pick, fmt, tone, canApplyRow, skipTxt, msg };
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { setupadvisor: view });
})();
