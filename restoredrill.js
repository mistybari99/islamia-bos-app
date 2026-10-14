/* Islamia BOS · Restore drill (#/restoredrill, owner only).
   The job: show whether a backup was ever PROVEN restorable - the last drill, its age, a warning when none was recorded within restore_drill_warn_days (default 90) -
   explain the 3 steps in plain words, and let the owner record the result printed by tools/restore_drill.py.
   Server (supabase/phase70.sql): restore_drill_status(), restore_drill_list(p_limit), restore_drill_record(p_backup_name, p_result, p_tables_ok, p_rows_ok, p_notes, p_drilled_at).
   The drill itself runs on a laptop / GitHub runner against a SCRATCH Postgres (docs/RESTORE_DRILL.md) - never from this phone screen, never against the live project.
   UNVERIFIED on a real Supabase project: the app only keeps the record. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const X = {
  title: L('রিস্টোর ড্রিল', 'Restore drill', 'Restore drill'),
  intro: L('ব্যাকআপ আছে মানেই ফেরত আনা যাবে - এটা প্রমাণ হয় না। মাঝে মাঝে একটা আলাদা (স্ক্র্যাচ) ডাটাবেসে ফেরত এনে দেখতে হয়। আসল ডাটাবেসে কিছু হয় না।',
    'Having a backup does not prove it can be restored. Now and then restore it into a separate (scratch) database and check. The live database is never touched.',
    'Backup আছে মানেই restore হবে - তা প্রমাণ হয় না। মাঝে মাঝে আলাদা (scratch) database-এ restore করে দেখতে হয়। Live database-এ কিছু হয় না।'),
  status: L('অবস্থা', 'Status', 'Status'),
  never: L('এখনো কোনো ড্রিল রেকর্ড নেই - সতর্কতা', 'No drill recorded yet - warning', 'এখনো কোনো drill record নেই - warning'),
  stale: L('অনেক দিন ড্রিল হয়নি - সতর্কতা', 'No passing drill for a long time - warning', 'অনেক দিন drill হয়নি - warning'),
  okst: L('ঠিক আছে', 'Up to date', 'Up to date'),
  last: L('শেষ ড্রিল', 'Last drill', 'শেষ drill'), lastpass: L('শেষ সফল ড্রিল', 'Last passing drill', 'শেষ pass drill'),
  daysago: L('দিন আগে', 'days ago', 'দিন আগে'), warnafter: L('এত দিনের বেশি হলে সতর্কতা', 'Warns after (days)', 'এত দিনের বেশি হলে warning'),
  lastfail: L('সর্বশেষ ড্রিল ব্যর্থ হয়েছে', 'The latest drill failed', 'সর্বশেষ drill fail করেছে'),
  how: L('৩ ধাপে ড্রিল', 'The drill in 3 steps', '৩ ধাপে drill'),
  s1: L('১) সর্বশেষ ব্যাকআপ নামান: GitHub -> Actions -> backup -> সর্বশেষ সবুজ রান (অথবা backups branch)।',
    '1) Download the newest backup: GitHub -> Actions -> backup -> the latest green run (or the backups branch).',
    '1) সর্বশেষ backup নামান: GitHub -> Actions -> backup -> latest green run (বা backups branch)।'),
  s2: L('২) নিজের কম্পিউটারে একটি স্ক্র্যাচ Postgres বানিয়ে (নামে scratch থাকতে হবে) চালান: python3 tools/restore_drill.py <ফোল্ডার> --dsn postgresql://postgres@localhost/bos_scratch',
    '2) On your own computer make a scratch Postgres (its name must contain "scratch") and run: python3 tools/restore_drill.py <folder> --dsn postgresql://postgres@localhost/bos_scratch',
    '2) নিজের computer-এ scratch Postgres বানিয়ে (নামে scratch থাকতে হবে) চালান: python3 tools/restore_drill.py <folder> --dsn postgresql://postgres@localhost/bos_scratch'),
  s3: L('৩) যে PASS / FAIL রিপোর্ট আসে তা নিচের ফর্মে লিখে রাখুন। পুরো ধাপ docs/RESTORE_DRILL.md-তে।',
    '3) Write the PASS / FAIL result it prints into the form below. Full steps: docs/RESTORE_DRILL.md.',
    '3) যে PASS / FAIL report আসে তা নিচের form-এ লিখে রাখুন। Full steps: docs/RESTORE_DRILL.md।'),
  note: L('লগইন ব্যবহারকারী (Auth) ও ছবি ব্যাকআপে নেই; আসল Supabase-এ এই ড্রিল এখনো যাচাই করা হয়নি।',
    'Auth users (logins) and photos are not in the backup; this drill is still UNVERIFIED on a real Supabase project.',
    'Auth user (login) আর ছবি backup-এ নেই; আসল Supabase-এ এই drill এখনো যাচাই করা হয়নি।'),
  rec: L('ফলাফল লিখুন', 'Record a result', 'ফলাফল লিখুন'),
  bname: L('ব্যাকআপের নাম / ডেট', 'Backup name / date', 'Backup-এর নাম / date'),
  result: L('ফল', 'Result', 'ফল'), pass: L('পাস', 'Pass', 'Pass'), failr: L('ফেল', 'Fail', 'Fail'),
  tok: L('টেবিল তালিকা, RLS ও ফাংশন ঠিক', 'Tables, RLS and functions OK', 'Table list, RLS ও function ঠিক'),
  rok: L('সারি-গণনা, জার্নাল ও স্টক ঠিক', 'Row counts, journal and stock OK', 'Row count, journal ও stock ঠিক'),
  notes: L('মন্তব্য', 'Notes', 'মন্তব্য'), when: L('ড্রিলের ডেট (ফাঁকা = এখন)', 'Drill date (empty = now)', 'Drill-এর date (ফাঁকা = এখন)'),
  save: L('সেভ', 'Save', 'Save'), saved: L('সেভ হয়েছে', 'Saved', 'Saved'),
  needname: L('ব্যাকআপের নাম লিখুন', 'Write the backup name', 'Backup-এর নাম লিখুন'),
  needboth: L('"পাস" লিখতে দুটো টিকই লাগবে', 'A "pass" needs both ticks', '"Pass" লিখতে দুটো tick-ই লাগবে'),
  hist: L('আগের ড্রিল', 'Earlier drills', 'আগের drill'), empty: L('কিছু নেই', 'Nothing yet', 'কিছু নেই'),
  owneronly: L('শুধু মালিক এই পাতা দেখতে পারেন।', 'Only the owner can open this page.', 'শুধু owner এই page দেখতে পারেন।'),
  nofn: L('সার্ভারে phase70.sql চালানো হয়নি।', 'phase70.sql has not been run on the server yet.', 'Server-এ phase70.sql চালানো হয়নি।'),
};
const T = (k) => lab(X[k]);
const D = { st: null, rows: [], err: null };
const fdate = (v) => (v ? String(v).slice(0, 10) : '-');

async function load() {
  D.err = null;
  const [s, l] = await Promise.all([sb.rpc('restore_drill_status'), sb.rpc('restore_drill_list', { p_limit: 20 })]);
  if (s.error || l.error) {
    const e = s.error || l.error;
    if (e.code === 'PGRST202' || /does not exist|could not find/i.test(e.message || '')) { D.err = 'nofn'; return; }
    throw e;
  }
  D.st = s.data; D.rows = l.data || [];
}
function statusHTML() {
  const s = D.st; if (!s) return '';
  const cls = s.warn ? 'warn' : 'ok', msg = s.never ? T('never') : s.warn ? T('stale') : T('okst');
  const last = s.last ? `${esc(fdate(s.last.at))} · ${esc(s.last.result === 'pass' ? T('pass') : T('failr'))} · ${esc(String(s.age_days))} ${esc(T('daysago'))}` : '-';
  const lp = s.last_pass_age_days == null ? '-' : `${esc(String(s.last_pass_age_days))} ${esc(T('daysago'))}`;
  return `<div class="card stack" id="rdr_status"><div class="row between"><b>${esc(T('status'))}</b><span class="chip ${cls}">${esc(msg)}</span></div>
    <div class="row between"><span>${esc(T('last'))}</span><span>${last}</span></div>
    <div class="row between"><span>${esc(T('lastpass'))}</span><span>${lp}</span></div>
    <div class="row between"><span>${esc(T('warnafter'))}</span><span>${esc(String(s.warn_days))}</span></div>
    ${s.last_failed ? `<div class="chip bad">${esc(T('lastfail'))}</div>` : ''}</div>`;
}
function howHTML() {
  return `<div class="card stack"><b>${esc(T('how'))}</b><p>${esc(T('s1'))}</p><p>${esc(T('s2'))}</p><p>${esc(T('s3'))}</p><p class="muted" style="font-size:.85rem">${esc(T('note'))}</p></div>`;
}
function formHTML() {
  return `<div class="card stack"><b>${esc(T('rec'))}</b>
    <label>${esc(T('bname'))} <input id="rdr_name" maxlength="200" placeholder="2026-10-14"></label>
    <label>${esc(T('result'))} <select id="rdr_result"><option value="pass">${esc(T('pass'))}</option><option value="fail">${esc(T('failr'))}</option></select></label>
    <label class="row"><input type="checkbox" id="rdr_tok"> ${esc(T('tok'))}</label>
    <label class="row"><input type="checkbox" id="rdr_rok"> ${esc(T('rok'))}</label>
    <label>${esc(T('when'))} <input type="date" id="rdr_when"></label>
    <label>${esc(T('notes'))} <textarea id="rdr_notes" rows="2" maxlength="2000"></textarea></label>
    <button type="button" class="btn primary" data-act="rdr_save">${esc(T('save'))}</button></div>`;
}
function listHTML() {
  const rows = D.rows.length ? D.rows.map((r) => `<div class="row between rdr-row" style="gap:.5rem"><span>${esc(fdate(r.drilled_at))} · ${esc(r.backup_name)}${r.notes ? ' · <span class="muted">' + esc(r.notes) + '</span>' : ''}</span>
    <span class="chip ${r.result === 'pass' ? 'ok' : 'bad'}">${esc(r.result === 'pass' ? T('pass') : T('failr'))}</span></div>`).join('') : `<p class="muted">${esc(T('empty'))}</p>`;
  return `<div class="card stack"><b>${esc(T('hist'))}</b>${rows}</div>`;
}
function draw() {
  const el = $('#rdr_body'); if (!el) return;
  if (D.err === 'nofn') { el.innerHTML = `<div class="card"><p>${esc(T('nofn'))}</p></div>`; return; }
  el.innerHTML = `<p class="muted">${esc(T('intro'))}</p>${statusHTML()}${howHTML()}${formHTML()}${listHTML()}`;
}
Object.assign(H, {
  rdr_save: async () => {
    const name = $('#rdr_name').value.trim(), result = $('#rdr_result').value, tok = $('#rdr_tok').checked, rok = $('#rdr_rok').checked;
    if (!name) return toast(T('needname'));
    if (result === 'pass' && !(tok && rok)) return toast(T('needboth'));
    const when = $('#rdr_when').value, notes = $('#rdr_notes').value.trim();
    const r = await sb.rpc('restore_drill_record', { p_backup_name: name, p_result: result, p_tables_ok: tok, p_rows_ok: rok, p_notes: notes || null, p_drilled_at: when ? when + 'T12:00:00+06:00' : null });
    if (r.error) return fail(r.error);
    toast(T('saved'));
    try { await load(); draw(); } catch (e) { fail(e); }
  },
});
async function viewRestoreDrill() {
  if (!(S && S.ctx && S.ctx.is_owner)) { shell(T('title'), `<div class="card"><p>${esc(T('owneronly'))}</p></div>`, true); return; }
  shell(T('title'), '<div id="rdr_body"><p class="muted">…</p></div>', true);
  try { await load(); draw(); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { restoredrill: viewRestoreDrill });
})();
