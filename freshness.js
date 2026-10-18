/* Islamia BOS · Books freshness (#/freshness) and the switch-coupling warning. Package W1-G, item U-11.
   Server (supabase/phase98.sql): _w1g_freshness() and _w1g_acct_readiness() READ ONLY; _w1g_post_scheduled(p_dry) (a dry run writes nothing);
   _w1g_switch_coupling_warning(key, value) READ ONLY; _w1g_switch_coupling_ack(key, value, note) (owner; one change-log line).
   What this file gives the rest of the app (the integrator wires it, see docs/integration/W1-G.md):
     BOS.freshness.mount(el)            fills el with the "last posted at" strip (Home, Accounts). Silent when the server has no phase98 or the person has no accounts view.
     BOS.freshness.confirmSwitch(k, v)  Promise<boolean>. Shows what a coupled switch will lock BEFORE it is saved (#/ledgerlinks, #/paths); false = the person backed out.
                                        Never blocks when the warning cannot be read: the server decides (mode "confirm" is enforced there).
   The page itself is read only except one owner button (scheduled posting ON/OFF, through the same warning). English labels only (owner rule 5).
   UNVERIFIED on a real Supabase project and on a real phone. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const E = (s) => L(s, s, s);                      // English only: the same text in all three modes
const X = {
  title: E('Books freshness'), strip: E('Books'),
  fresh: E('Up to date'), waiting: E('Documents waiting'), stale: E('Not posted for too long'), off: E('Accounting is off'), data_needed: E('Start date not set'),
  intro: E('Shows how recently sales, purchases and expenses were posted to the books, what is still waiting, and whether the books are ready to be filled automatically.'),
  last: E('Last posted'), never: E('Nothing posted yet'), ago: E('ago'), pending: E('waiting'), errors: E('failed'), checked: E('Scheduler last checked'), nocheck: E('Scheduler has not run yet'),
  sched: E('Scheduled posting'), on: E('ON'), offs: E('OFF'),
  ready: E('Ready to post automatically'), notready: E('Not ready yet'), checks: E('Readiness checklist'),
  turnon: E('Turn scheduled posting ON'), turnoff: E('Turn scheduled posting OFF'), dry: E('Check now (changes nothing)'), dryres: E('If it ran now, it would post'),
  nothing: E('nothing: everything is already posted'), bytype: E('By kind of document'), kind: E('Kind'), lastp: E('Last posted'), wm: E('Posted up to'), left: E('Waiting'),
  docs: E('documents'), where: E('Settings (cap per run, kinds, look-back window, red warning after N hours) are in the Switchboard under Books.'),
  denied: E('You do not have permission to open this page.'), nofn: E('phase98.sql has not been run on the server yet.'),
  stop: E('Stop - this switch locks other screens'), note: E('Read this before you save the switch.'), fix: E('How to keep a screen working'),
  go: E('Turn it on anyway'), back: E('Cancel'), ask: E('Saved. Nothing already recorded changes.'), swerr: E('Could not save the switch.'),
  confirmlabel: E('I have read this and want to continue'),
};
const T = (k) => lab(X[k]);
const D = { f: null, r: null, err: null, dry: null };

/* ---------- small helpers ---------- */
const dhaka = (ts) => (ts ? new Date(ts).toLocaleString('en-GB', { timeZone: 'Asia/Dhaka', day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit', hour12: false }) : '');
const dhakaDay = (d) => (d ? new Date(d + 'T00:00:00Z').toLocaleDateString('en-GB', { timeZone: 'UTC', day: '2-digit', month: 'short', year: 'numeric' }) : '-');
function ago(min) {
  if (min === null || min === undefined) return '';
  const m = Math.max(0, Number(min));
  if (m < 60) return m + ' min';
  if (m < 2880) return Math.round(m / 60) + ' h';
  return Math.round(m / 1440) + ' days';
}
const isMissing = (e) => e && (e.code === 'PGRST202' || /does not exist|could not find/i.test(e.message || ''));
const isDenied = (e) => e && /not allowed/i.test(e.message || '');
const COLOR = { fresh: '#2e7d32', waiting: '#b26a00', stale: '#c62828', off: '#6b6b6b', data_needed: '#6b6b6b' };
const CHIP = { fresh: 'ok', waiting: 'warn', stale: 'bad', off: '', data_needed: '' };

/* ---------- the strip (also used by Home and Accounts) ---------- */
function stripHTML(f) {
  if (!f) return '';
  const st = f.status || 'off';
  const last = f.last_posted_at ? `${T('last')}: ${dhaka(f.last_posted_at)} (${ago(f.age_minutes)} ${T('ago')})` : T('never');
  const chk = f.last_check_at ? `${T('checked')}: ${dhaka(f.last_check_at)}` : (f.sched_on ? T('nocheck') : '');
  return `<div class="card stack fr-strip" id="fr_strip" data-status="${esc(st)}" style="border-left:6px solid ${COLOR[st] || '#6b6b6b'}">
    <div class="row between"><b>${esc(T('strip'))}</b><span class="chip ${CHIP[st] || ''}">${esc(T(st) || st)}</span></div>
    <div class="muted fr-last">${esc(last)}</div>
    <div class="muted fr-count">${esc(String(f.pending || 0))} ${esc(T('pending'))}${Number(f.errors) > 0 ? ` · ${esc(String(f.errors))} ${esc(T('errors'))}` : ''}</div>
    <div class="muted fr-sched">${esc(T('sched'))}: ${esc(f.sched_on ? T('on') : T('offs'))}${chk ? ' · ' + esc(chk) : ''}</div></div>`;
}
async function loadStrip() {
  const r = await sb.rpc('_w1g_freshness');
  if (r.error) { if (isMissing(r.error) || isDenied(r.error)) return null; throw r.error; }
  return r.data;
}
async function mount(el) {
  if (!el) return;
  try { const f = await loadStrip(); el.innerHTML = f ? stripHTML(f) : ''; } catch (e) { el.innerHTML = ''; }
}

/* ---------- the switch-coupling warning (shown BEFORE the switch is saved) ---------- */
let pendingResolve = null;
function settle(v) { if (pendingResolve) { const r = pendingResolve; pendingResolve = null; r(v); } }
async function getWarning(key, value) {
  try {
    const r = await sb.rpc('_w1g_switch_coupling_warning', { p_key: key, p_value: value });
    if (r.error) return null;
    return r.data;
  } catch (e) { return null; }
}
async function confirmSwitch(key, value) {
  const w = await getWarning(key, value);
  if (!w || (!w.show && !w.confirm)) return true;                       // nothing to say (mode off, no change, unknown key, function missing): the old behaviour
  settle(false);
  return new Promise((resolve) => {
    pendingResolve = resolve;
    const high = w.severity === 'high';
    const acts = (w.actions || []).map((a) => `<li><b>${esc(a.screen)}</b> → ${esc(a.form)} <span class="muted">(${esc(String((a.places || []).length))})</span></li>`).join('');
    openSheet(`<h2>${esc(high ? T('stop') : T('note'))}</h2><div class="stack" id="fr_warn" data-sev="${esc(w.severity || 'info')}" data-key="${esc(key)}">
      <p>${esc(w.text || '')}</p>${acts ? `<ul class="fr-acts">${acts}</ul>` : ''}
      ${w.fix ? `<div class="notice warn"><b>${esc(T('fix'))}</b><br>${esc(w.fix)}</div>` : ''}
      ${w.confirm ? `<label class="row"><input type="checkbox" id="fr_ack"> ${esc(T('confirmlabel'))}</label>` : ''}
      <div class="row"><button type="button" class="btn" data-act="fr_back">${esc(T('back'))}</button>
      <button type="button" class="btn primary" id="fr_go" data-act="fr_go" ${w.confirm ? 'disabled' : ''}>${esc(T('go'))}</button></div></div>`);
    pendingResolve.key = key; pendingResolve.value = value; pendingResolve.confirm = !!w.confirm;
    const bg = $('#sheet');
    if (bg) {
      const obs = new MutationObserver(() => { if (!document.body.contains(bg)) { obs.disconnect(); settle(false); } });
      obs.observe(document.body, { childList: true });
    }
    const ack = $('#fr_ack');
    if (ack) ack.addEventListener('change', () => { $('#fr_go').disabled = !ack.checked; });
  });
}
Object.assign(H, {
  fr_back: () => { settle(false); closeSheet(); },
  fr_go: async () => {
    const p = pendingResolve; if (!p) return closeSheet();
    if (p.confirm) {                                                    // mode "confirm": the owner's confirmation is recorded in the change log and unlocks the server guard
      const r = await sb.rpc('_w1g_switch_coupling_ack', { p_key: p.key, p_value: p.value, p_note: 'confirmed on screen' });
      if (r.error) { settle(false); closeSheet(); return fail(r.error); }
    }
    settle(true); closeSheet();
  },
});

/* ---------- the page ---------- */
function readinessHTML(r) {
  if (!r) return '';
  const rows = (r.checks || []).map((c) => `<div class="row between fr-check" data-k="${esc(c.key)}"><span>${esc(c.text)}</span><span class="chip ${c.ok ? 'ok' : 'bad'}">${c.ok ? 'OK' : 'Fix'}</span></div>`).join('');
  return `<div class="card stack" id="fr_ready"><div class="row between"><b>${esc(T('checks'))}</b><span class="chip ${r.ready ? 'ok' : 'warn'}">${esc(r.ready ? T('ready') : T('notready'))}</span></div>${rows}</div>`;
}
function typesHTML(f) {
  const rows = (f.by_type || []);
  if (!rows.length) return '';
  const body = rows.map((x) => `<div class="row between fr-type" data-k="${esc(x.source_type)}" style="gap:.5rem"><span>${esc(x.source_type)}</span>
    <span class="muted">${esc(T('lastp'))} ${esc(dhaka(x.last_posted_at) || '-')} · ${esc(T('wm'))} ${esc(dhakaDay(x.watermark_date))} · ${esc(T('left'))} ${esc(String(x.pending_after || 0))}</span></div>`).join('');
  return `<div class="card stack" id="fr_types"><b>${esc(T('bytype'))}</b>${body}</div>`;
}
function dryHTML() {
  const d = D.dry; if (!d) return '';
  const rows = Object.entries(d.by_type || {}).map(([k, v]) => `<div class="row between"><span>${esc(k)}</span><span>${esc(String((v.posted || 0) + (v.reversed || 0)))}</span></div>`).join('');
  return `<div class="card stack" id="fr_dry"><b>${esc(T('dryres'))}: ${esc(String((d.posted || 0) + (d.reversed || 0)))} ${esc(T('docs'))}</b>${rows || `<span class="muted">${esc(T('nothing'))}</span>`}</div>`;
}
function draw() {
  const el = $('#fr_body'); if (!el) return;
  if (D.err) { el.innerHTML = `<div class="card"><p>${esc(T(D.err))}</p></div>`; return; }
  const f = D.f, own = !!(S.ctx && S.ctx.is_owner);
  const sw = own ? `<button type="button" class="btn ${f.sched_on ? '' : 'primary'}" data-act="fr_sched" id="fr_sched_btn">${esc(f.sched_on ? T('turnoff') : T('turnon'))}</button>` : '';
  el.innerHTML = `<p class="muted">${esc(T('intro'))}</p>${stripHTML(f)}${readinessHTML(D.r)}
    <div class="card stack"><div class="row wrap" style="gap:.5rem">${sw}<button type="button" class="btn" data-act="fr_dry" id="fr_dry_btn">${esc(T('dry'))}</button></div></div>
    ${dryHTML()}${typesHTML(f)}<p class="muted" style="font-size:.85rem">${esc(T('where'))}</p>`;
}
async function load() {
  D.err = null;
  const [f, r] = await Promise.all([sb.rpc('_w1g_freshness'), sb.rpc('_w1g_acct_readiness')]);
  for (const x of [f, r]) {
    if (x.error) { D.err = isMissing(x.error) ? 'nofn' : isDenied(x.error) ? 'denied' : null; if (!D.err) throw x.error; return; }
  }
  D.f = f.data; D.r = r.data;
}
Object.assign(H, {
  fr_dry: async () => {
    const r = await sb.rpc('_w1g_post_scheduled', { p_dry: true });
    if (r.error) return isDenied(r.error) ? toast(T('denied')) : fail(r.error);
    D.dry = r.data; draw();
  },
  fr_sched: async () => {
    const want = !(D.f && D.f.sched_on);
    if (!(await confirmSwitch('journal_sched_post_on', want))) return;
    const r = await sb.rpc('set_rule', { p_key: 'journal_sched_post_on', p_value: want });
    if (r.error) return fail(r.error);
    toast(T('ask'));
    try { await load(); draw(); } catch (e) { fail(e); }
  },
});
async function viewFreshness() {
  shell(T('title'), '<div id="fr_body"><p class="muted">…</p></div>', true);
  try { await load(); draw(); } catch (e) { fail(e); }
}
window.BOS = window.BOS || B;
window.BOS.freshness = { mount, stripHTML, confirmSwitch, getWarning, load: loadStrip, version: 1 };
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { freshness: viewFreshness });
})();
