/* Islamia BOS · Guided flows (#/flow, #/flow/<open|close|factory|month>): a checklist that only LINKS to the existing screens and ticks each step from server state.
   A step is never ticked by tapping: it is done when the server says so, "unknown - check" when nothing can tell, or skipped with a written note (flow_skip, supabase/phase28.sql).
   No business logic and no posting here. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, H, nm } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const X = {
  title: L('দিনের কাজ (ধাপে ধাপে)', 'Guided routines', 'দিনের কাজ (ধাপে ধাপে)'), loc: L('জায়গা', 'Place', 'Place'),
  open: L('দোকান খোলা', 'Open shop', 'দোকান খোলা'), close: L('দিন শেষ', 'Close day', 'দিন শেষ'), factory: L('কারখানার দিন', 'Factory day', 'কারখানার দিন'), month: L('মাস শেষ', 'Month-end', 'মাস শেষ'),
  of: L('এর মধ্যে', 'of', 'এর মধ্যে'), left: L('বাকি', 'left', 'বাকি'), done: L('হয়েছে', 'Done', 'Done'), todo: L('বাকি', 'To do', 'বাকি'), progress: L('ড্রাফট আছে', 'Draft', 'Draft'), unknown: L('নিজে দেখে নিন', 'Check manually', 'নিজে দেখে নিন'),
  skipped: L('বাদ (নোট সহ)', 'Skipped (note)', 'Skipped'), skip: L('বাদ দিন…', 'Skip…', 'Skip…'), why: L('কেন বাদ দিচ্ছেন (অন্তত ৩ অক্ষর)', 'Why skip (3+ letters)', 'কেন skip (৩+ অক্ষর)'), open_: L('খুলুন', 'Open', 'Open'),
  back: L('সব রুটিন', 'All routines', 'সব routine'), refresh: L('আবার দেখুন', 'Refresh', 'Refresh'), saved: L('সেভ হয়েছে', 'Saved', 'Saved'),
  s_drawer: L('ড্রয়ারের ক্যাশ গোনা (14-1)', 'Count the drawer (14-1)', 'Drawer cash গোনা (14-1)'), s_attend: L('হাজিরা (02-1)', 'Attendance (02-1)', 'হাজিরা (02-1)'),
  s_stock: L('স্টক কম / মেয়াদ দেখা', 'Look at low stock and expiry', 'Stock কম / expiry দেখা'), s_exc: L('গতকালের সমস্যা (খোলা গরমিল ০ হলে ঠিক)', 'Yesterday\'s problems (done when none are open)', 'গতকালের সমস্যা'),
  s_pos: L('বিক্রি শুরু (POS)', 'Open the POS', 'POS খুলুন'), s_release: L('লাল নিয়ন্ত্রণ থাকলে ছাড়ের অনুরোধ', 'Release request if a red control is open', 'Red control থাকলে release'),
  s_hub: L('হাবে ক্যাশ হস্তান্তর (10-1)', 'Hand the cash to the hub (10-1)', 'Hub-এ cash handover (10-1)'), s_dig: L('ডিজিটাল মিলানো (10-3)', 'Digital reconcile (10-3)', 'Digital মিলানো (10-3)'),
  s_deposit: L('ব্যাংকে জমা', 'Bank deposit', 'Bank জমা'), s_exp: L('আজকের খরচ (10-2)', 'Today\'s expenses (10-2)', 'আজকের খরচ (10-2)'), s_outbox: L('ফোনে জমা থাকা কিছু নেই', 'Nothing waiting on this phone', 'Phone-এ কিছু জমা নেই'),
  s_summary: L('দিনের খাতা দেখুন', 'Look at the day book', 'Day book দেখুন'), s_daily: L('কারখানার দৈনিক শিট (05-1)', 'Factory daily sheet (05-1)', 'Factory daily sheet (05-1)'), s_grn: L('মাল গ্রহণ (04-1)', 'Goods received (04-1)', 'মাল গ্রহণ (04-1)'),
  s_issue: L('মাল ইস্যু (04-2)', 'Goods issued (04-2)', 'মাল ইস্যু (04-2)'), s_prod: L('উৎপাদন (রেসিপি)', 'Production (recipes)', 'Production (recipe)'), s_dispatch: L('দোকানে চালান (03-1)', 'Dispatch to shops (03-1)', 'দোকানে চালান (03-1)'),
  s_wastage: L('নষ্ট মাল', 'Wastage', 'Wastage'), s_days: L('সব দোকানের সব দিনের দিন-শেষ জমা', 'Every shop-day closed (14-1)', 'সব দোকানের দিন-শেষ জমা'), s_pending: L('অপেক্ষার অ্যাপ্রুভ ও গরমিল শূন্য', 'No pending approvals or open exceptions', 'Pending ও exception শূন্য'),
  s_count: L('এই মাসে স্টক কাউন্ট (04-3)', 'Stock count this month (04-3)', 'এই মাসে stock count (04-3)'), s_pay: L('সাপ্লায়ারের বাকি ও ক্রয় মিলানো', 'Supplier payables and purchases', 'Supplier বাকি ও purchase'),
  s_salary: L('বেতনের শিট', 'Salary sheet', 'Salary sheet'), s_reports: L('রিপোর্ট ও লাভ-ক্ষতি', 'Reports and profit & loss', 'Reports ও P&L'), s_lock: L('"হিসাব বন্ধ" তারিখ বসান (মালিক)', 'Set "books closed until" (owner)', '"Books closed" তারিখ (owner)'),
  e_note_required: L('কারণ লিখুন', 'Write a reason', 'কারণ লিখুন'),
};
const T = (k) => lab(X[k]);
// step kinds: entry:<code> (today, this place) | month_entry:<code> | none_open (exceptions) | outbox | link (unknown) | days_closed | no_pending | lock
const FLOWS = {
  open: [['drawer', 'entry:14-1', 'form/14-1'], ['attend', 'link', 'form/02-1'], ['stock', 'link', 'stock'], ['exc', 'none_open', 'exceptions'], ['pos', 'link', 'pos']],
  close: [['drawer', 'entry:14-1', 'form/14-1'], ['release', 'none_red', 'releases'], ['hub', 'entry:10-1', 'form/10-1'], ['dig', 'entry:10-3', 'form/10-3'], ['deposit', 'link', 'cashmoves'], ['exp', 'entry:10-2', 'form/10-2'], ['outbox', 'outbox', 'outbox'], ['summary', 'link', 'daybook']],
  factory: [['daily', 'entry:05-1', 'form/05-1'], ['grn', 'entry:04-1', 'form/04-1'], ['issue', 'entry:04-2', 'form/04-2'], ['prod', 'link', 'recipes'], ['wastage', 'link', 'stock'], ['dispatch', 'entry:03-1', 'form/03-1']],
  month: [['days', 'days_closed', 'daybook'], ['pending', 'no_pending', 'pending'], ['count', 'month_entry:04-3', 'form/04-3'], ['pay', 'link', 'payables'], ['salary', 'link', 'salary'], ['reports', 'link', 'reports'], ['lock', 'lock', 'settings']],
};
const D = { loc: null, skips: [], res: {} };
const LOCS = () => (B.liveLocs || ((a) => a))((S.ctx.is_owner || (S.ctx.roles || []).includes('management')) ? ((B.ENV && B.ENV.locs) || []) : ((B.ENV && B.ENV.locs) || []).filter((l) => (S.ctx.locations || []).includes(l.id)));
const monthStart = () => today().slice(0, 7) + '-01';
async function check(kind) {
  const loc = D.loc, td = today();
  try {
    if (kind.startsWith('entry:') || kind.startsWith('month_entry:')) {
      const code = kind.split(':')[1], mo = kind.startsWith('month_entry');
      let q = sb.from('entries').select('status').eq('form_code', code).eq('location_id', loc); q = mo ? q.gte('entry_date', monthStart()) : q.eq('entry_date', td);
      const r = await q; if (r.error) return 'unknown';
      const rows = r.data || []; return rows.some((x) => x.status === 'submitted' || x.status === 'approved') ? 'done' : rows.length ? 'progress' : 'todo';
    }
    if (kind === 'none_open') { const r = await sb.from('exceptions').select('id', { count: 'exact', head: true }).eq('status', 'open').eq('location_id', loc); return r.error ? 'unknown' : (r.count || 0) === 0 ? 'done' : 'todo'; }
    if (kind === 'none_red') { const r = await sb.from('exceptions').select('id', { count: 'exact', head: true }).eq('status', 'open').eq('level', 'red').eq('location_id', loc); return r.error ? 'unknown' : (r.count || 0) === 0 ? 'done' : 'todo'; }
    if (kind === 'outbox') return B.outbox && B.outbox.count ? (B.outbox.count() === 0 ? 'done' : 'todo') : 'unknown';
    if (kind === 'no_pending') { const [a, b] = await Promise.all([sb.from('entries').select('id', { count: 'exact', head: true }).eq('status', 'submitted').eq('location_id', loc), sb.from('exceptions').select('id', { count: 'exact', head: true }).eq('status', 'open').eq('location_id', loc)]);
      return a.error || b.error ? 'unknown' : (a.count || 0) + (b.count || 0) === 0 ? 'done' : 'todo'; }
    if (kind === 'days_closed') {
      const r = await sb.from('entries').select('entry_date,status').eq('form_code', '14-1').eq('location_id', loc).gte('entry_date', monthStart()).lte('entry_date', td); if (r.error) return 'unknown';
      const have = new Set((r.data || []).filter((x) => x.status === 'submitted' || x.status === 'approved').map((x) => x.entry_date)); const last = new Date(td + 'T00:00:00Z'); let miss = 0;
      for (let d = new Date(monthStart() + 'T00:00:00Z'); d < last; d.setUTCDate(d.getUTCDate() + 1)) { if (!have.has(d.toISOString().slice(0, 10))) miss++; }
      return miss === 0 ? 'done' : 'todo';
    }
    if (kind === 'lock') { const v = B.rule ? B.rule('period_closed_until', null) : null; return v && String(v) >= monthStart() ? 'done' : 'todo'; }
  } catch (e) { return 'unknown'; }
  return 'unknown';       // a plain link: nothing can tell, so it is never ticked
}
async function loadSkips() { const r = await sb.from('flow_skips').select('flow,step,location_id,day').eq('day', today()); D.skips = r.error ? [] : (r.data || []); }
async function listView() {
  shell(T('title'), '<div id="fl_body"><p class="muted">…</p></div>', true);
  if (B.loadStatic) await B.loadStatic();
  const locs = LOCS(); if (!D.loc || !locs.find((l) => l.id === D.loc)) D.loc = (locs[0] || {}).id;
  await loadSkips();
  const cards = await Promise.all(Object.keys(FLOWS).map(async (id) => { const res = await Promise.all(FLOWS[id].map(async ([k, kind]) => (D.skips.some((s) => s.flow === id && s.step === k && s.location_id === D.loc) ? 'skipped' : check(kind))));
    const left = res.filter((r) => r !== 'done' && r !== 'skipped').length; return `<a class="card item" href="#/flow/${id}"><div><div class="nm">${esc(T(id))}</div><div class="muted">${res.length - left} ${esc(T('of'))} ${res.length}</div></div><span class="chip ${left ? 'warn' : 'ok'}">${left ? left + ' ' + esc(T('left')) : esc(T('done'))}</span></a>`; }));
  $('#fl_body').innerHTML = `<div class="card">${locs.length > 1 ? `<select id="fl_loc" aria-label="${esc(T('loc'))}">${locs.map((l) => `<option value="${l.id}" ${l.id === D.loc ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select>` : ''}</div>${cards.join('')}`;
}
async function flowView(id) {
  shell(T(id), '<div id="fl_body"><p class="muted">…</p></div>', true);
  if (B.loadStatic) await B.loadStatic();
  const locs = LOCS(); if (!D.loc || !locs.find((l) => l.id === D.loc)) D.loc = (locs[0] || {}).id;
  await loadSkips();
  const steps = FLOWS[id]; const res = await Promise.all(steps.map(async ([k, kind]) => (D.skips.some((s) => s.flow === id && s.step === k && s.location_id === D.loc) ? 'skipped' : check(kind))));
  const left = res.filter((r) => r !== 'done' && r !== 'skipped').length;
  const rows = steps.map(([k, kind, route], i) => { const st = res[i];
    return `<div class="card" data-step="${k}"><div class="row between"><div><b>${i + 1}. ${esc(T('s_' + k))}</b></div><span class="chip ${st === 'done' ? 'ok' : st === 'skipped' ? 'info' : st === 'unknown' ? '' : 'warn'}">${esc(T(st))}</span></div>
      <div class="row"><a class="mini primary" href="#/${esc(route)}">${esc(T('open_'))}</a>${st !== 'done' && st !== 'skipped' ? `<button class="mini" data-act="fl_skip" data-f="${id}" data-s="${k}">${esc(T('skip'))}</button>` : ''}</div></div>`; }).join('');
  $('#fl_body').innerHTML = `<div class="card stack">${locs.length > 1 ? `<select id="fl_loc" data-flow="${id}" aria-label="${esc(T('loc'))}">${locs.map((l) => `<option value="${l.id}" ${l.id === D.loc ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select>` : ''}
    <div class="row between"><b>${steps.length - left} ${esc(T('of'))} ${steps.length}</b><button class="mini" data-act="fl_refresh" data-f="${id}">${esc(T('refresh'))}</button></div></div>${rows}<a class="full" href="#/flow">${esc(T('back'))}</a>`;
}
Object.assign(H, {
  fl_refresh: (a) => flowView(a.dataset.f),
  fl_skip: async (a) => { const n = window.prompt(T('why')); if (!n || n.trim().length < 3) return; const r = await sb.rpc('flow_skip', { p_flow: a.dataset.f, p_step: a.dataset.s, p_loc: D.loc, p_day: today(), p_note: n.trim() });
    if (r.error) return toast(r.error.message); toast(T('saved')); flowView(a.dataset.f); },
});
document.addEventListener('change', (e) => { if (e.target.id === 'fl_loc') { D.loc = Number(e.target.value); const f = e.target.dataset.flow; f ? flowView(f) : listView(); } });
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { flow: () => { const p = location.hash.replace(/^#\/?/, '').split('/'); return p[1] && FLOWS[p[1]] ? flowView(p[1]) : listView(); } });
B.flow = { flows: FLOWS };
})();
