/* Islamia BOS · home dashboard: problems first, then a short numbers summary. Plus the "awaiting approval" page.
   Everything shown is read from what staff entered; no threshold is invented here. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, t, esc, shell, nm, fmt, fail } = A;
const $ = (s, el = document) => el.querySelector(s);
const L = B.L, lab = B.lab;
const money = (n) => '৳ ' + fmt(n);
const dhaka = (d = new Date()) => d.toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const addDays = (iso, n) => { const d = new Date(iso + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
const X = {
  problems: L('সমস্যা — আগে দেখুন', 'Problems — look first', 'Problems — আগে দেখুন'), numbers: L('আজকের সংখ্যা', 'Numbers today', 'Today সংখ্যা'),
  clear: L('এখন কোনো সমস্যা নেই ✓', 'No problems right now ✓', 'এখন কোনো Problem নেই ✓'),
  red: L('লাল ব্যতিক্রম (খোলা)', 'Open red exceptions', 'Open Red exception'), yellow: L('হলুদ ব্যতিক্রম (খোলা)', 'Open yellow exceptions', 'Open Yellow exception'),
  release: L('লাল-নিয়ন্ত্রণ ছাড়ের অনুরোধ', 'Red-control release requests', 'Red-control Release অনুরোধ'), staff: L('অনুমোদনের অপেক্ষায় স্টাফ', 'Staff waiting for approval', 'Approval এর অপেক্ষায় Staff'),
  itemreq: L('আইটেম/দাম বদলের অনুরোধ', 'Item / price change requests', 'Item/Price বদলের অনুরোধ'), pending: L('অনুমোদনের অপেক্ষায় এন্ট্রি', 'Entries awaiting approval', 'Approval এর অপেক্ষায় Entry'),
  drafts: L('আপনার অসম্পূর্ণ ড্রাফট', 'Your unfinished drafts', 'আপনার অসম্পূর্ণ Draft'), nosheet: L('আজ শোরুম শিট জমা হয়নি', "Today's showroom sheet not submitted", 'Today Showroom Sheet জমা হয়নি'),
  void: L('আজ বাতিল সেল', 'Sales voided today', 'Today Void Sale'), locset: L('লোকেশন সেটিংসে তথ্য বাকি', 'Location settings still empty', 'Location settings এ তথ্য বাকি'),
  sales: L('আজকের বিক্রি', "Today's sales", 'Today Sales'), count: L('টি সেল', 'sales', 'sales'), yday: L('গতকাল', 'Yesterday', 'Yesterday'), week: L('গত ৭ দিন', 'Last 7 days', 'Last 7 days'),
  due: L('আজ বাকিতে', 'On credit today', 'Today Due (বাকি)'), disc: L('আজ ডিসকাউন্ট', 'Discount today', 'Today Discount'),
  perloc: L('লোকেশন অনুযায়ী', 'By location', 'By Location'), cash: L('নগদ', 'Cash', 'Cash'), mobile: L('মোবাইল', 'Mobile', 'Mobile'), card: L('কার্ড', 'Card', 'Card'), duem: L('বাকি', 'Due', 'Due'),
  open: L('খুলুন', 'Open', 'Open'), title: L('অনুমোদনের অপেক্ষায়', 'Awaiting approval', 'Approval এর অপেক্ষায়'), none: L('অপেক্ষায় কিছু নেই', 'Nothing waiting', 'অপেক্ষায় কিছু নেই'),
};
const T = (k) => lab(X[k]);
const dayLetter = (iso) => ['রবি', 'সোম', 'মঙ্গল', 'বুধ', 'বৃহ', 'শুক্র', 'শনি'][new Date(iso + 'T12:00:00Z').getUTCDay()];
const dayLetterEn = (iso) => ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][new Date(iso + 'T12:00:00Z').getUTCDay()];

async function render() {
  const el = $('#dash'); if (!el) return;
  const perms = S.ctx.perms || {}, owner = S.ctx.is_owner, me = S.ctx.profile.id;
  const anyApprove = owner || Object.values(perms).some((p) => p.approve);
  const canPos = owner || (perms.POS && perms.POS.view);
  const canItems = owner || (perms.ITEMS && perms.ITEMS.approve);
  const td = dhaka(), from = addDays(td, -6);
  await B.loadStatic();
  const q = (x) => x.then((r) => (r && r.error ? { data: null, count: 0 } : r), () => ({ data: null, count: 0 }));
  const [ex, rel, stf, itm, sub, dr, sales, sheets, ls] = await Promise.all([
    anyApprove ? q(sb.from('exceptions').select('level').eq('status', 'open')) : { data: [] },
    owner ? q(sb.from('release_requests').select('id', { count: 'exact', head: true }).eq('status', 'pending')) : { count: 0 },
    owner ? q(sb.from('profiles').select('id', { count: 'exact', head: true }).eq('status', 'pending')) : { count: 0 },
    canItems ? q(sb.from('item_changes').select('id', { count: 'exact', head: true }).eq('status', 'pending')) : { count: 0 },
    anyApprove ? q(sb.from('entries').select('id,form_code,created_by').eq('status', 'submitted').limit(200)) : { data: [] },
    q(sb.from('entries').select('id', { count: 'exact', head: true }).eq('status', 'draft').eq('created_by', me)),
    canPos ? q(sb.rpc('sales_summary', { p_from: from })) : { data: [] },
    (owner || (perms['14-1'] && perms['14-1'].view)) ? q(sb.from('entries').select('location_id,status').eq('form_code', '14-1').eq('entry_date', td).neq('status', 'draft')) : { data: null },
    owner ? q(sb.from('location_settings').select('location_id,value')) : { data: null },
  ]);
  const reds = (ex.data || []).filter((x) => x.level === 'red').length, yel = (ex.data || []).filter((x) => x.level === 'yellow').length;
  const mineToApprove = (sub.data || []).filter((e) => owner || (perms[e.form_code] && perms[e.form_code].approve)).length;
  const sd = (sales.data || []).map((r) => ({ ...r, total: Number(r.total || 0), discount: Number(r.discount || 0), n: Number(r.n || 0) }));
  const sToday = sd.filter((s) => s.sale_date === td && s.status === 'done'), voids = sd.filter((s) => s.sale_date === td && s.status === 'void').reduce((a, r) => a + r.n, 0);
  const sum = (a, k = 'total') => a.reduce((s, x) => s + Number(x[k] || 0), 0);
  const cnt = (a) => a.reduce((s, x) => s + x.n, 0);
  const locs = (B.ENV.locs || []).filter((l) => owner || S.ctx.roles.includes('management') || S.ctx.locations.includes(l.id));
  let missingLoc = 0;
  if (ls.data && B.SETTING_DEFS) missingLoc = Math.max(0, B.SETTING_DEFS.length * (B.ENV.locs || []).length - ls.data.filter((x) => x.value !== null && x.value !== undefined && x.value !== '').length);
  const noSheet = sheets.data ? locs.filter((l) => !sheets.data.some((s) => s.location_id === l.id)) : [];
  const rows = [
    [reds, 'bad', T('red'), 'exceptions'], [yel, 'warn', T('yellow'), 'exceptions'], [rel.count, 'bad', T('release'), 'releases'], [mineToApprove, 'warn', T('pending'), 'pending'],
    [stf.count, 'warn', T('staff'), 'staff'], [itm.count, 'warn', T('itemreq'), 'itemreq'], [voids, 'warn', T('void'), 'pos'],
    [noSheet.length, 'warn', T('nosheet') + (noSheet.length ? ': ' + noSheet.map((l) => nm(l)).join(', ') : ''), 'form/14-1'],
    [dr.count, 'info', T('drafts'), null], [missingLoc, 'info', T('locset'), 'locset'],
  ].filter((r) => r[0]);
  const row = ([n, tone, label, to]) => `<div class="dash-row ${tone}" ${to ? `data-act="go" data-v="${to}"` : ''}><span class="dot"></span><span class="dl">${esc(label)}</span><b class="dn">${n}</b>${to ? '<span class="dc">›</span>' : ''}</div>`;
  let html = `<div class="card panel dash"><h3>${esc(T('problems'))}</h3>${rows.length ? rows.map(row).join('') : `<div class="dash-ok">${esc(T('clear'))}</div>`}</div>`;
  if (canPos) {
    const y = sum(sd.filter((s) => s.sale_date === addDays(td, -1) && s.status === 'done'));
    const days = Array.from({ length: 7 }, (_, i) => addDays(td, i - 6)).map((d) => [d, sum(sd.filter((s) => s.sale_date === d && s.status === 'done'))]);
    const mx = Math.max(1, ...days.map((d) => d[1]));
    const mode = (m) => sum(sToday.filter((s) => s.pay_mode === m));
    html += `<div class="card panel dash"><h3>${esc(T('numbers'))}</h3>
      <div class="plate"><div class="pl-k">${esc(T('sales'))}</div><div class="pl-v"><span class="cur">৳</span>${fmt(sum(sToday))}</div>
        <div class="pl-s">${cnt(sToday)} ${esc(T('count'))} · ${esc(T('yday'))} ${money(y)}</div></div>
      <div class="row wrap" style="margin:8px 0">${['cash', 'mobile', 'card', 'due'].map((m) => `<span class="chip">${esc(T(m === 'due' ? 'duem' : m))} ${money(mode(m))}</span>`).join('')}</div>
      ${sum(sToday, 'discount') ? `<div class="muted">${esc(T('disc'))}: ${money(sum(sToday, 'discount'))}</div>` : ''}
      ${locs.length > 1 ? `<div class="muted" style="margin-top:8px">${esc(T('perloc'))}</div>${locs.map((l) => `<div class="row between"><span>${esc(nm(l))}</span><b>${money(sum(sToday.filter((s) => s.location_id === l.id)))}</b></div>`).join('')}` : ''}
      <div class="muted" style="margin-top:10px">${esc(T('week'))}</div>
      <div class="bars">${days.map(([d, v]) => `<div class="bar ${d === td ? 'now' : ''}"><em>${v ? fmt(Math.round(v)) : ''}</em><i style="height:${Math.round(v / mx * 100)}%"></i><small>${S.lang === 'en' ? dayLetterEn(d) : dayLetter(d)}</small></div>`).join('')}</div></div>`;
  }
  el.innerHTML = html;
}

async function viewPending() {
  shell(T('title'), `<p class="muted">${esc(t('loading'))}</p>`, true);
  await B.loadStatic();
  const perms = S.ctx.perms || {}, owner = S.ctx.is_owner;
  const r = await sb.from('entries').select('id,form_code,location_id,serial,entry_date,created_staff,flags').eq('status', 'submitted').order('entry_date', { ascending: false }).limit(200);
  if (r.error) return fail(r.error);
  const list = r.data.filter((e) => owner || (perms[e.form_code] && perms[e.form_code].approve));
  const lc = (id) => (B.ENV.locs.find((l) => l.id === id) || {}).code || '';
  shell(T('title'), list.length ? list.map((e) => { const fl = (e.flags || []).filter((f) => f.level === 'red').length;
    return `<div class="card item" data-act="openentry" data-v="${e.id}"><div><div class="nm">${esc(e.form_code)}-${esc(lc(e.location_id))}-${e.serial}</div>
      <div class="muted" style="font-size:.85rem">${esc(e.entry_date)} · ${esc(e.created_staff || '')}</div></div>${fl ? `<span class="chip bad">● ${fl}</span>` : ''}</div>`; }).join('')
    : `<p class="muted center">${esc(T('none'))}</p>`, true);
}

window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { pending: viewPending });
B.dash = { render };
})();
