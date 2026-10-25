/* Islamia BOS · Parallel month (#/parallel): comparison pairs (named by the owner), the daily comparison rows (the keeper writes the paper figure, someone else the app figure),
   and the month-end Pass / Fail. Server: supabase/phase28.sql. Pass moves the form at that place to App; Fail keeps it in Parallel. Nothing is invented: the list of pairs starts empty. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, H, nm } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const X = {
  title: L('পাশাপাশি মাস: তুলনা ও পাস/ফেল', 'Parallel month: comparison and pass / fail', 'Parallel মাস: তুলনা ও pass/fail'),
  none: L('কোনো ফর্ম এখন "পাশাপাশি" অবস্থায় নেই। রোলআউট বোর্ডে আগে বদলান।', 'No form is in Parallel now. Change it on the rollout board first.', 'কোনো form এখন Parallel-এ নেই। Rollout board-এ আগে বদলান।'),
  pairs: L('তুলনার জোড়া (মালিক ঠিক করেন)', 'Comparison pairs (named by the owner)', 'তুলনার জোড়া (owner ঠিক করেন)'), noPair: L('এখনও কোনো জোড়া নেই — মালিক একটি নাম দিন', 'No pair yet - the owner must name one', 'এখনও কোনো জোড়া নেই'),
  addPair: L('নতুন জোড়া', 'New pair', 'নতুন জোড়া'), nameBn: L('নাম (বাংলা)', 'Name (Bangla)', 'নাম (বাংলা)'), nameEn: L('নাম (ইংরেজি)', 'Name (English)', 'নাম (English)'),
  howPaper: L('কাগজের অঙ্ক কোথা থেকে পড়া হয়', 'Where the paper figure is read', 'কাগজের অঙ্ক কোথা থেকে'), howApp: L('অ্যাপের অঙ্ক কোথা থেকে', 'Where the app figure is read', 'App-এর অঙ্ক কোথা থেকে'),
  save: L('সেভ', 'Save', 'Save'), day: L('ডেট', 'Day', 'Day'), paper: L('কাগজের অঙ্ক', 'Paper figure', 'কাগজের অঙ্ক'), app: L('অ্যাপের অঙ্ক', 'App figure', 'App-এর অঙ্ক'),
  recPaper: L('কাগজের অঙ্ক লিখুন (রক্ষক)', 'Record the paper figure (keeper)', 'কাগজের অঙ্ক লিখুন (keeper)'), recApp: L('অ্যাপের অঙ্ক লিখুন (অন্য জন)', 'Record the app figure (someone else)', 'App-এর অঙ্ক লিখুন (অন্য জন)'),
  month: L('এই মাসের অবস্থা', 'This month', 'এই মাসের অবস্থা'), days: L('দিন', 'Days', 'Days'), match: L('মিলেছে', 'Match', 'Match'), differ: L('মেলেনি', 'Differ', 'Differ'), waiting: L('অপেক্ষায়', 'Waiting', 'Waiting'),
  explain: L('কারণ ও ঠিক করার ব্যবস্থা', 'Reason and fix', 'কারণ ও fix'), reason: L('কারণ', 'Reason', 'কারণ'), fix: L('ঠিক করার ব্যবস্থা', 'Fix', 'Fix'),
  pass: L('পাস — অ্যাপে যান', 'Pass - move to App', 'Pass - App-এ যান'), failB: L('ফেল — পাশাপাশিই থাকুক', 'Fail - stay in Parallel', 'Fail - Parallel-ই থাকুক'), note: L('নোট', 'Note', 'Note'),
  decided: L('সিদ্ধান্ত হয়ে গেছে', 'Decided', 'Decided'), notEnded: L('মাস শেষ হয়নি', 'The month is not over yet', 'মাস শেষ হয়নি'), saved: L('সেভ হয়েছে', 'Saved', 'Saved'),
  e_keeper_is_enterer: L('যিনি কাগজের অঙ্ক লিখেছেন তিনিই অ্যাপের অঙ্ক লিখতে পারবেন না', 'The keeper cannot also record the app figure of the same row', 'Keeper নিজেই app figure লিখতে পারবে না'),
  e_days_waiting: L('কিছু দিনের তুলনা অপেক্ষায়', 'Some days are still waiting', 'কিছু দিনের তুলনা অপেক্ষায়'), e_differ_without_reason: L('যে দিন মেলেনি তার কারণ ও ব্যবস্থা লিখুন', 'Every differing day needs a reason and a fix', 'যে দিন মেলেনি তার কারণ ও fix লিখুন'),
  e_no_pair_named: L('আগে একটি জোড়া ঠিক করুন', 'Name a pair first', 'আগে একটি জোড়া ঠিক করুন'), e_no_comparison_days: L('এই মাসে কোনো তুলনার দিন নেই', 'No comparison days this month', 'এই মাসে কোনো তুলনার দিন নেই'),
  e_month_not_ended: L('মাস শেষ হয়নি', 'The month is not over yet', 'মাস শেষ হয়নি'), e_already_decided: L('এই মাসের সিদ্ধান্ত আগেই হয়েছে', 'This month is already decided', 'এই মাসের সিদ্ধান্ত হয়ে গেছে'),
  e_already_recorded: L('এই অঙ্ক আগেই অন্য কেউ লিখেছেন', 'Someone else already recorded this figure', 'অন্য কেউ আগেই লিখেছেন'), e_not_parallel: L('ফর্মটি এখন পাশাপাশি অবস্থায় নেই', 'The form is not in Parallel', 'Form এখন Parallel-এ নেই'),
  e_month_decided: L('এই মাসের সিদ্ধান্ত হয়ে গেছে — আর বদলানো যাবে না', 'This month is already decided - no more changes', 'এই মাসের সিদ্ধান্ত হয়ে গেছে'), e_not_allowed: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'), e_note_required: L('নোট লিখুন', 'Write a note', 'Note লিখুন'), e_bad_amount: L('অঙ্ক ঠিক নয়', 'Figure is not valid', 'অঙ্ক ঠিক নয়'),
  e_reason_and_fix_required: L('কারণ ও ব্যবস্থা দুটোই লিখুন', 'Write both reason and fix', 'কারণ ও fix দুটোই লিখুন'),
};
const T = (k) => lab(X[k]);
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(X).filter((x) => x.startsWith('e_')).find((x) => m.includes(x.slice(2))); return k ? lab(X[k]) : m; };
const D = { cells: [], pairs: [], cur: null, status: null, days: [] };
const isOwner = () => !!(S.ctx && S.ctx.is_owner);
const monthStart = (d) => d.slice(0, 7) + '-01';
const prevMonth = () => { const t = new Date(monthStart(today()) + 'T00:00:00Z'); t.setUTCMonth(t.getUTCMonth() - 1); return t.toISOString().slice(0, 7) + '-01'; };

async function load() {
  const [c, p] = await Promise.all([sb.from('form_rollout').select('form_code,location_id,mode').eq('mode', 'parallel'), sb.from('comparison_pairs').select('*').order('id')]);
  D.cells = c.data || []; D.pairs = p.data || [];
  if (!D.cur || !D.cells.find((x) => x.form_code === D.cur.f && x.location_id === D.cur.l)) { const f = D.cells[0]; D.cur = f ? { f: f.form_code, l: f.location_id, m: monthStart(today()) } : null; }
  D.status = null; D.days = [];
  if (D.cur) {
    const r = await sb.rpc('parallel_month_status', { p_form: D.cur.f, p_loc: D.cur.l, p_month: D.cur.m }); D.status = r.error ? null : r.data;
    const d = await sb.from('comparison_days').select('*').eq('form_code', D.cur.f).eq('location_id', D.cur.l).gte('day', D.cur.m).lt('day', nextMonth(D.cur.m)).order('day', { ascending: false });
    D.days = d.data || [];
  }
}
const nextMonth = (m) => { const t = new Date(m + 'T00:00:00Z'); t.setUTCMonth(t.getUTCMonth() + 1); return t.toISOString().slice(0, 10); };
const locName = (id) => nm(((B.ENV && B.ENV.locs) || []).find((l) => l.id === id) || { name_bn: '#' + id });
function draw() {
  const el = $('#pl_body'); if (!el) return;
  if (!D.cells.length) { el.innerHTML = `<div class="card"><p class="muted">${esc(T('none'))}</p></div>`; return; }
  const cur = D.cur, st = D.status || {}, pairs = D.pairs.filter((p) => p.form_code === cur.f);
  const cellSel = `<select id="pl_cell" aria-label="${esc(T('title'))}">${D.cells.map((c) => `<option value="${esc(c.form_code + '|' + c.location_id)}" ${c.form_code === cur.f && c.location_id === cur.l ? 'selected' : ''}>${esc(c.form_code)} · ${esc(locName(c.location_id))}</option>`).join('')}</select>`;
  const monthSel = `<select id="pl_month"><option value="${monthStart(today())}" ${cur.m === monthStart(today()) ? 'selected' : ''}>${esc(monthStart(today()).slice(0, 7))}</option><option value="${prevMonth()}" ${cur.m === prevMonth() ? 'selected' : ''}>${esc(prevMonth().slice(0, 7))}</option></select>`;
  const stat = `<div class="card stack"><b>${esc(T('month'))}</b><div class="row wrap"><span class="chip">${esc(T('days'))}: ${st.days || 0}</span><span class="chip ok">${esc(T('match'))}: ${st.match || 0}</span>
      <span class="chip ${st.differ ? 'bad' : ''}">${esc(T('differ'))}: ${st.differ || 0}</span><span class="chip ${st.waiting ? 'warn' : ''}">${esc(T('waiting'))}: ${st.waiting || 0}</span></div>
    ${st.decision ? `<div class="notice ${st.decision.result === 'pass' ? 'ok' : 'warn'}">${esc(T('decided'))}: ${esc(st.decision.result)} ${esc(st.decision.note || '')}</div>` : ''}
    ${isOwner() && !st.decision ? (st.month_ended ? `<input id="pl_note" placeholder="${esc(T('note'))}" autocomplete="off"><div class="row"><button class="full primary" data-act="pl_decide" data-v="1" ${st.pass_ready ? '' : ''}>${esc(T('pass'))}</button><button class="full" data-act="pl_decide" data-v="0">${esc(T('failB'))}</button></div>` : `<div class="muted">${esc(T('notEnded'))}</div>`) : ''}</div>`;
  const pairsH = `<div class="card stack"><b>${esc(T('pairs'))}</b>${pairs.length ? pairs.map((p) => `<div class="row between"><span>${esc(p.name_bn)}${p.name_en ? ' · ' + esc(p.name_en) : ''}<div class="muted" style="font-size:.8rem">${esc(p.how_paper || '')} ↔ ${esc(p.how_app || '')}</div></span></div>`).join('') : `<p class="muted">${esc(T('noPair'))}</p>`}
    ${isOwner() ? `<details data-ctl="off"><summary>＋ ${esc(T('addPair'))}</summary><div class="stack"><input id="pp_bn" placeholder="${esc(T('nameBn'))}" autocomplete="off"><input id="pp_en" placeholder="${esc(T('nameEn'))}" autocomplete="off">
      <input id="pp_hp" placeholder="${esc(T('howPaper'))}" autocomplete="off"><input id="pp_ha" placeholder="${esc(T('howApp'))}" autocomplete="off"><button class="primary" data-act="pl_pair">${esc(T('save'))}</button></div></details>` : ''}</div>`;
  const rec = pairs.length && cur.m === monthStart(today()) ? `<div class="card stack"><b>${esc(T('recPaper'))} / ${esc(T('recApp'))}</b>
      <select id="pr_pair">${pairs.map((p) => `<option value="${p.id}">${esc(p.name_bn)}</option>`).join('')}</select><input id="pr_day" type="date" value="${today()}" max="${today()}">
      <input id="pr_val" inputmode="decimal" placeholder="৳" autocomplete="off"><div class="row"><button class="full" data-act="pl_rec" data-v="paper">${esc(T('recPaper'))}</button><button class="full" data-act="pl_rec" data-v="app">${esc(T('recApp'))}</button></div></div>` : '';
  const rows = D.days.length ? D.days.map((d) => { const p = D.pairs.find((x) => x.id === d.pair_id);
    return `<div class="card"><div class="row between"><b>${esc(d.day)}</b><span class="chip ${d.result === 'match' ? 'ok' : d.result === 'differ' ? 'bad' : 'warn'}">${esc(T(d.result === 'waiting' ? 'waiting' : d.result))}</span></div>
      <div class="muted">${esc(p ? p.name_bn : '')}</div><div class="row between"><span>${esc(T('paper'))}: <b>${d.paper_value === null ? '—' : esc(String(d.paper_value))}</b></span><span>${esc(T('app'))}: <b>${d.app_value === null ? '—' : esc(String(d.app_value))}</b></span></div>
      ${d.result === 'differ' ? (d.reason ? `<div class="muted">${esc(d.reason)} → ${esc(d.fix || '')}</div>` : `<div class="stack"><input data-ex-r="${d.id}" placeholder="${esc(T('reason'))}" autocomplete="off"><input data-ex-f="${d.id}" placeholder="${esc(T('fix'))}" autocomplete="off"><button class="mini" data-act="pl_explain" data-v="${d.id}">${esc(T('explain'))}</button></div>`) : ''}</div>`; }).join('') : '';
  el.innerHTML = `<div class="card stack">${cellSel}${monthSel}</div>${stat}${pairsH}${rec}${rows}`;
}
Object.assign(H, {
  pl_pair: async () => { const r = await sb.rpc('comparison_pair_save', { p_form: D.cur.f, p_name_bn: $('#pp_bn').value, p_name_en: $('#pp_en').value, p_how_paper: $('#pp_hp').value, p_how_app: $('#pp_ha').value }); if (r.error) return toast(eText(r.error)); toast(T('saved')); await load(); draw(); },
  pl_rec: async (a) => { const v = Number(String($('#pr_val').value).replace(/,/g, '')); const r = await sb.rpc('comparison_record', { p_pair: Number($('#pr_pair').value), p_loc: D.cur.l, p_day: $('#pr_day').value, p_role: a.dataset.v, p_value: v });
    if (r.error) return toast(eText(r.error)); toast(T('saved')); $('#pr_val').value = ''; await load(); draw(); },
  pl_explain: async (a) => { const id = a.dataset.v; const r = await sb.rpc('comparison_explain', { p_id: Number(id), p_reason: ($(`[data-ex-r="${id}"]`) || {}).value, p_fix: ($(`[data-ex-f="${id}"]`) || {}).value }); if (r.error) return toast(eText(r.error)); toast(T('saved')); await load(); draw(); },
  pl_decide: async (a) => { const r = await sb.rpc('parallel_month_decide', { p_form: D.cur.f, p_loc: D.cur.l, p_month: D.cur.m, p_pass: a.dataset.v === '1', p_note: ($('#pl_note') || {}).value || null }); if (r.error) return toast(eText(r.error)); toast(T('saved')); await load(); draw(); },
});
document.addEventListener('change', async (e) => {
  if (e.target.id === 'pl_cell') { const [f, l] = e.target.value.split('|'); D.cur = { f, l: Number(l), m: D.cur ? D.cur.m : monthStart(today()) }; await load(); draw(); }
  if (e.target.id === 'pl_month') { D.cur.m = e.target.value; await load(); draw(); }
});
async function view() {
  shell(T('title'), '<div id="pl_body"><p class="muted">…</p></div>', true);
  if (B.loadStatic) await B.loadStatic();
  try { await load(); draw(); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { parallel: view });
})();
