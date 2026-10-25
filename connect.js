/* Islamia BOS · X1 foundation screens: Connect Center (#/connect) and Automation & Integration Health (#/x1health).
   Server: supabase/phase479.sql (integration_registry, integration_set, integration_config_versions, webhook_rotation_record, job_runs, site_config),
   supabase/phase480.sql (x1_health, action_proposals_list). Edge check (source only): tools/edge/x1-connect-check.ts.
   Rules this file follows: a secret VALUE is never shown, typed or stored here; the screen only shows the NAMES that must be set on the server and where.
   Every connection is OFF until the owner switches it on. A "connected" state appears only after a successful test, never because a value was typed.
   The owner board widget "x1_health" is NOT in the default board: the owner adds it. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const E = (bn, en) => L(bn, en, en);
const X = {
  ct_title: E('সংযোগ কেন্দ্র', 'Connect Center'), ct_intro: E('সব বাইরের সংযোগ এক জায়গায়। সব বন্ধ অবস্থায় শুরু হয়। গোপন চাবি (secret) এই স্ক্রিনে বসানো বা দেখানো হয় না — শুধু কোন নামে কোথায় বসাতে হবে তা দেখানো হয়।', 'All outside connections in one place. Everything starts OFF. Secret keys are never typed or shown on this screen - it only shows the names and where to set them.'),
  st_not_connected: E('সংযুক্ত নয়', 'Not connected'), st_configured: E('সেটআপ হয়েছে (পরীক্ষা বাকি)', 'Configured (test pending)'), st_connected: E('সংযুক্ত (পরীক্ষায় ঠিক)', 'Connected (test passed)'),
  st_error: E('ত্রুটি', 'Error'), st_disabled: E('বন্ধ', 'Disabled'), on: E('চালু', 'ON'), off: E('বন্ধ', 'OFF'),
  ro: E('শুধু পড়া', 'Read only'), rw: E('লেখা চালু', 'Write enabled'), dry: E('ড্রাই রান (কিছু পাঠায় না)', 'Dry run (sends nothing)'), live: E('লাইভ', 'Live'),
  need: E('লাগবে (সার্ভারে সেট করতে হবে)', 'Needed (set on the server)'), howto: E('কোথায় বসাবেন', 'Where to set it'),
  step: E('Supabase ড্যাশবোর্ড → Project Settings → Edge Functions → Secrets → নিচের নামে নতুন secret যোগ করুন। মান এই অ্যাপে লিখবেন না।', 'Supabase dashboard -> Project Settings -> Edge Functions -> Secrets -> add a secret with the name below. Do not type the value into this app.'),
  test: E('সংযোগ পরীক্ষা করুন', 'Test connection'), tested: E('শেষ পরীক্ষা', 'Last test'), lastok: E('শেষ সফল', 'Last success'), lasterr: E('শেষ ত্রুটি', 'Last error'),
  never: E('এখনও নয়', 'Never'), none: E('কোনো সংযোগ নেই', 'No connections'), owner: E('শুধু মালিক দেখতে ও বদলাতে পারেন।', 'Only the owner can see and change this.'),
  save: E('সংরক্ষণ', 'Save'), endpoint: E('ঠিকানা (https://…, গোপন নয়)', 'Address (https://…, not secret)'), domain: E('ডোমেইন / নাম', 'Domain / name'),
  rate: E('প্রতি মিনিটে সর্বোচ্চ কল', 'Max calls per minute'), cap: E('মাসে সর্বোচ্চ কল (0 = বাজেট সেট নেই, কোনো কল হবে না)', 'Max calls per month (0 = no budget set, no calls)'),
  enabled: E('এই সংযোগ চালু', 'Connection ON'), readonly: E('শুধু পড়া (লেখা বন্ধ)', 'Read only (no writes)'), dryrun: E('ড্রাই রান (লেখা শুধু রিপোর্ট)', 'Dry run (writes only reported)'),
  confirm_on: E('সংযোগ চালু করবেন? এর আগে automation_on-ও চালু থাকতে হবে।', 'Switch this connection ON? automation_on must also be ON.'),
  saved: E('সংরক্ষিত', 'Saved'), badnum: E('সংখ্যা ঠিক নয়', 'Not a valid number'),
  h_title: E('স্বয়ংক্রিয় কাজ ও সংযোগের স্বাস্থ্য', 'Automation & integration health'), h_intro: E('কোনো অংশ না থাকলে "অনুপস্থিত", পুরনো হলে "পুরনো" লেখা হয় — কখনো ভুল করে "ঠিক" দেখানো হয় না।', 'A missing part shows "missing", an old one "stale". Nothing is shown as healthy by mistake.'),
  h_auto: E('স্বয়ংক্রিয় কাজ (সব)', 'Automation (all)'), h_pause: E('বিরতি', 'Pause'), h_jobs: E('নির্ধারিত কাজ', 'Scheduled jobs'), h_conns: E('সংযোগ', 'Connections'),
  h_intake: E('ইনটেক ব্যর্থ / মৃত', 'Intake failed / dead'), h_back: E('ব্যাকআপ', 'Backup'), h_books: E('হিসাবের সতেজতা', 'Books freshness'), h_props: E('অনুমোদনের অপেক্ষায় প্রস্তাব', 'Proposals waiting for approval'),
  s_ok: E('ঠিক', 'OK'), s_failed: E('ব্যর্থ', 'Failed'), s_stale: E('পুরনো', 'Stale'), s_never_run: E('চালানো হয়নি', 'Never run'), s_off: E('বন্ধ', 'Off'), s_not_connected: E('সংযুক্ত নয়', 'Not connected'),
  s_unverified: E('যাচাই হয়নি', 'Unverified'), s_error: E('ত্রুটি', 'Error'), s_missing: E('অনুপস্থিত', 'Missing'),
  denied: E('এই পাতা শুধু মালিক দেখতে পারেন।', 'Only the owner can open this page.'), nofn: E('সার্ভারে এই অংশ এখনও চালু হয়নি (phase 479/480 চালাতে হবে)।', 'This part is not on the server yet (phase 479/480 must be run).'),
  fail_load: E('এখন আনা যায়নি', 'Could not load now'), again: E('আবার চেষ্টা', 'Try again'),
  kinds: { website: E('ওয়েবসাইট / ডোমেইন', 'Website / domain'), hosting: E('হোস্টিং', 'Hosting'), facebook_page: E('ফেসবুক পেজ', 'Facebook Page'), instagram: E('ইনস্টাগ্রাম', 'Instagram'), whatsapp_business: E('হোয়াটসঅ্যাপ বিজনেস', 'WhatsApp Business'), sms_gateway: E('এসএমএস গেটওয়ে', 'SMS gateway'), email_smtp: E('ইমেইল (SMTP)', 'E-mail (SMTP)'), payment: E('পেমেন্ট (bKash/Nagad)', 'Payment (bKash/Nagad)'), ai_provider: E('AI সেবা', 'AI provider'), vision_provider: E('ছবি পড়া (OCR)', 'Image reading (OCR)'), analytics: E('বিশ্লেষণ', 'Analytics'), other: E('অন্যান্য', 'Other') },
};
const T = (k) => lab(X[k]);
const D = { conns: null, jobs: null, health: null, err: null };
const isMissing = (e) => e && (e.code === 'PGRST202' || /does not exist|could not find/i.test(e.message || ''));
const isDenied = (e) => e && /not allowed|permission denied/i.test(e.message || '');
const when = (ts) => (ts ? new Date(ts).toLocaleString('en-GB', { timeZone: 'Asia/Dhaka', day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit', hour12: false }) : T('never'));
const STCHIP = { not_connected: '', configured: 'warn', connected: 'ok', error: 'bad', disabled: '' };
const stLabel = (st) => T('st_' + st) || st;
const red = (s) => String(s || '').replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, '[email]').replace(/(\+?880|0)?1[3-9][0-9]{8}/g, '[phone]');
const numOK = (v) => { const n = Number(v); return Number.isInteger(n) && n >= 0 && n <= 1000000; };

/* ---------- Connect Center ---------- */
function connHTML(c, own) {
  const kind = (X.kinds[c.kind] && lab(X.kinds[c.kind])) || c.kind;
  const cfg = Object.entries(c.config || {}).map(([k, v]) => `<div class="row between"><span class="muted">${esc(k)}</span><span>${esc(String(v))}</span></div>`).join('');
  const names = (c.env_names || []).map((n) => `<li><code>${esc(n)}</code></li>`).join('');
  const needs = (c.env_names && c.env_names.length) ? `<div class="stack"><b>${esc(T('need'))}</b><ul class="x1-names">${names}</ul><div class="muted">${esc(T('howto'))}: ${esc(T('step'))}</div></div>` : '';
  const flags = `<span class="chip ${c.read_only ? '' : 'warn'}">${esc(T(c.read_only ? 'ro' : 'rw'))}</span> <span class="chip ${c.dry_run ? '' : 'warn'}">${esc(T(c.dry_run ? 'dryrun' : 'live'))}</span>`;
  const last = `<div class="muted">${esc(T('tested'))}: ${esc(when(c.last_test_at))} · ${esc(T('lastok'))}: ${esc(when(c.last_ok_at))}</div>${c.last_error ? `<div class="notice warn">${esc(T('lasterr'))}: ${esc(red(c.last_error))}</div>` : ''}`;
  const ownerBox = own ? `<details class="x1-edit"><summary>${esc(T('save'))}</summary>
     <div class="stack">
       <label>${esc(T('endpoint'))}<input id="x1e_${esc(c.code)}" value="${esc((c.config || {}).endpoint || '')}" inputmode="url"></label>
       <label>${esc(T('rate'))}<input id="x1r_${esc(c.code)}" type="number" min="0" value="${esc(c.rate_per_min)}"></label>
       <label>${esc(T('cap'))}<input id="x1c_${esc(c.code)}" type="number" min="0" value="${esc(c.monthly_call_cap)}"></label>
       <label class="row"><input type="checkbox" id="x1en_${esc(c.code)}" ${c.enabled ? 'checked' : ''}> ${esc(T('enabled'))}</label>
       <label class="row"><input type="checkbox" id="x1ro_${esc(c.code)}" ${c.read_only ? 'checked' : ''}> ${esc(T('readonly'))}</label>
       <label class="row"><input type="checkbox" id="x1dr_${esc(c.code)}" ${c.dry_run ? 'checked' : ''}> ${esc(T('dryrun'))}</label>
       <button type="button" class="btn primary" data-act="x1_save" data-code="${esc(c.code)}">${esc(T('save'))}</button>
     </div></details>
     <button type="button" class="btn" data-act="x1_test" data-code="${esc(c.code)}">${esc(T('test'))}</button>` : '';
  return `<div class="card stack x1-conn" data-code="${esc(c.code)}" data-status="${esc(c.status)}">
    <div class="row between wrap"><b>${esc(lab(L(c.label_bn, c.label_en, c.label_en)) || c.label_en)}</b><span class="chip ${STCHIP[c.status] || ''}">${esc(stLabel(c.status))}</span></div>
    <div class="muted">${esc(kind)} · <span class="chip ${c.enabled ? 'ok' : ''}">${esc(T(c.enabled ? 'on' : 'off'))}</span> ${flags}</div>
    ${cfg ? `<div class="stack">${cfg}</div>` : ''}${needs}${last}${ownerBox}</div>`;
}
function drawConnect() {
  const el = $('#ct_body'); if (!el) return;
  if (D.err) { el.innerHTML = `<div class="card"><p>${esc(T(D.err))}</p></div>`; return; }
  const list = D.conns || [];
  el.innerHTML = `<p class="muted">${esc(T('ct_intro'))}</p>` + (list.length ? list.map((c) => connHTML(c, !!(S.ctx && S.ctx.is_owner))).join('') : `<div class="card"><p>${esc(T('none'))}</p></div>`);
}
async function loadConnect() {
  D.err = null;
  const r = await sb.from('integration_registry').select('code,kind,label_bn,label_en,status,enabled,read_only,dry_run,config,env_names,rate_per_min,monthly_call_cap,last_ok_at,last_error,last_test_at').order('code');
  if (r.error) { D.err = isMissing(r.error) ? 'nofn' : isDenied(r.error) ? 'denied' : 'fail_load'; return; }
  D.conns = r.data || [];
}
async function viewConnect() {
  shell(T('ct_title'), '<div id="ct_body"><p class="muted">…</p></div>', true);
  try { await loadConnect(); drawConnect(); } catch (e) { D.err = 'fail_load'; drawConnect(); }
}
Object.assign(H, {
  x1_save: async (a) => {
    const code = a.dataset.code;
    const endpoint = ($('#x1e_' + code) || {}).value || '';
    const rate = ($('#x1r_' + code) || {}).value, cap = ($('#x1c_' + code) || {}).value;
    if (!numOK(rate) || !numOK(cap)) return toast(T('badnum'));
    const enabling = $('#x1en_' + code) && $('#x1en_' + code).checked;
    const was = (D.conns || []).find((c) => c.code === code);
    if (enabling && !(was && was.enabled) && !window.confirm(T('confirm_on'))) return;
    const fields = { config: endpoint ? { endpoint } : {}, rate_per_min: Number(rate), monthly_call_cap: Number(cap),
      enabled: !!$('#x1en_' + code).checked, read_only: !!$('#x1ro_' + code).checked, dry_run: !!$('#x1dr_' + code).checked };
    const r = await sb.rpc('integration_set', { p_code: code, p_fields: fields });
    if (r.error) return fail(r.error);
    toast(T('saved')); await loadConnect(); drawConnect();
  },
  x1_test: async (a) => {
    const code = a.dataset.code;
    const r = await sb.functions.invoke('x1-connect-check', { body: { code } });
    if (r.error) { toast(T('nofn')); return; }
    toast(r.data && r.data.ok ? T('st_connected') : T('st_error'));
    await loadConnect(); drawConnect();
  },
});

/* ---------- Health ---------- */
const JOB_LABEL = { notify_digest: E('ইমেইল ও সতর্কতা', 'E-mail & alerts'), notify_sms: E('এসএমএস কিউ', 'SMS queue'), intake_retry: E('ইনটেক পুনঃচেষ্টা', 'Intake retry'), kb_rebuild: E('সহায়তা তথ্য (KB) পুনর্গঠন', 'Help knowledge base rebuild'), backup: E('ব্যাকআপ', 'Backup') };
function drawHealth() {
  const el = $('#x1h_body'); if (!el) return;
  if (D.err) { el.innerHTML = `<div class="card"><p>${esc(T(D.err))}</p><button type="button" class="btn" data-act="x1_health_again">${esc(T('again'))}</button></div>`; return; }
  const h = D.health || {};
  const sl = (s) => T('s_' + s) || s;
  const chip = (s) => `<span class="chip ${s === 'ok' ? 'ok' : (s === 'failed' || s === 'error') ? 'bad' : (s === 'stale' || s === 'never_run' || s === 'unverified') ? 'warn' : ''}">${esc(sl(s))}</span>`;
  const jobs = (h.jobs || []).map((j) => `<div class="row between x1-job" data-job="${esc(j.job)}"><span>${esc(lab(JOB_LABEL[j.job] || L(j.job, j.job, j.job)))}</span>${chip(j.state)}</div>`).join('');
  const conns = (h.integrations || []).map((c) => `<div class="row between x1-conn-row" data-code="${esc(c.code)}"><span>${esc(c.label_en)}</span>${chip(c.state)}</div>`).join('');
  const back = h.backup || {}, books = h.books || {};
  el.innerHTML = `<p class="muted">${esc(T('h_intro'))}</p>
    <div class="card stack"><div class="row between"><b>${esc(T('h_auto'))}</b>${chip(h.automation_on ? 'ok' : 'off')}</div>
      <div class="row between"><span>${esc(T('h_pause'))}</span><span>${esc(h.paused ? (h.pause_until || '') : '—')}</span></div>
      <div class="row between"><span>${esc(T('h_props'))}</span><span>${esc(String(h.proposals_open || 0))}</span></div>
      <div class="row between"><span>${esc(T('h_intake'))}</span><span>${esc(String(h.intake_failed_or_dead || 0))}</span></div>
      <div class="row between"><span>${esc(T('h_back'))}</span>${chip(back.stale ? 'stale' : (back.last_ok ? 'ok' : 'missing'))}</div>
      <div class="row between"><span>${esc(T('h_books'))}</span><span>${esc(String(books.status || (books.state || 'missing')))}</span></div>
    </div>
    <div class="card stack"><b>${esc(T('h_jobs'))}</b>${jobs || `<span class="muted">—</span>`}</div>
    <div class="card stack"><b>${esc(T('h_conns'))}</b>${conns || `<span class="muted">—</span>`}</div>`;
}
async function loadHealth() {
  D.err = null;
  const r = await sb.rpc('x1_health');
  if (r.error) { D.err = isMissing(r.error) ? 'nofn' : isDenied(r.error) ? 'denied' : 'fail_load'; return; }
  D.health = r.data || {};
}
async function viewHealth() {
  shell(T('h_title'), '<div id="x1h_body"><p class="muted">…</p></div>', true);
  try { await loadHealth(); } catch (e) { D.err = 'fail_load'; }
  drawHealth();
}
Object.assign(H, { x1_health_again: async () => { try { await loadHealth(); } catch (e) { D.err = 'fail_load'; } drawHealth(); } });

/* ---------- owner board widget (added by the owner; not in the default board) ---------- */
function registerWidget() {
  const ob = B.ownerboard;
  if (!ob || !ob.KINDS || ob.KINDS.x1_health) return;
  ob.KINDS.x1_health = { g: 'sys', l: E('স্বয়ংক্রিয় কাজ ও সংযোগ', 'Automation & connections'), route: 'x1health', async load() {
    const r = await sb.rpc('x1_health');
    if (r.error) { if (isMissing(r.error) || isDenied(r.error)) { const e = new Error('x1'); e.name = 'Miss'; throw e; } throw r.error; }
    const h = r.data || {}, jobs = h.jobs || [], bad = jobs.filter((j) => j.state === 'failed' || j.state === 'stale').length;
    const tone = (h.intake_failed_or_dead || 0) > 0 || bad > 0 ? 'warn' : (h.automation_on ? 'ok' : 'info');
    return { value: h.automation_on ? 'ON' : 'OFF', tone, sub: `${bad} ${lab(E('কাজে সমস্যা', 'jobs with a problem'))} · ${h.intake_failed_or_dead || 0} ${lab(E('ইনটেক ব্যর্থ', 'intake failed'))}`, route: 'x1health' };
  } };
}

window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { connect: viewConnect, x1health: viewHealth });
registerWidget();
window.BOS = window.BOS || B;
window.BOS.connect = { version: 1, drawConnect, drawHealth, registerWidget };
})();
