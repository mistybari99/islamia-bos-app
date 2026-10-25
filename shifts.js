/* Islamia BOS · Shift schedule (#/shifts). Package R2-C.
   Staff: "My shifts" = the next 14 days (shift and time, off-days, approved leave, holidays, notes) and, when the owner allows it, who else is on at my place.
   Schedulers (the owner, or a person holding the grant shift_manage for the place): the weekly roster of one place as people x days, tap a day to give a shift
   template, an off-day or a leave / swap note; copy last week; shift templates (name, start, end, place); and a report that compares the roster with what attendance
   recorded (read only; shown only when the server has attendance data).
   Reuses the existing tables: templates = shifts, the weekly pattern = employee_shift_assignments, holidays, approved leave, attendance_days. This file writes only through r2_* functions.
   Switches: shift_on (OFF by default: entry stays visible to the owner and the grant holder, no request, the page says it is off), shift_mates_on (ON; only matters when shift_on is ON).
   Server: supabase/phase132.sql. The server is the authority on who may schedule. UNVERIFIED on a real phone and a real Supabase project. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, shell, openSheet, closeSheet, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const X = {
  title: L('শিফট রোস্টার', 'Shift schedule', 'Shift roster'), my: L('আমার শিফট', 'My shifts', 'আমার shift'), roster: L('রোস্টার সাজান', 'Roster', 'Roster সাজান'), report: L('রোস্টার বনাম হাজিরা', 'Roster vs attendance', 'Roster বনাম হাজিরা'),
  off: L('শিফট রোস্টার এখন বন্ধ আছে। মালিক সেটিংসে "শিফট রোস্টার চালু" করলে এটি কাজ করবে।', 'Off: the shift schedule is switched off. Turn on in Settings (shift_on). Nothing is lost; rosters start when it is ON.', 'Shift roster বন্ধ। মালিক Settings-এ "shift_on" চালু করলে কাজ করবে।'),
  nofn: L('এই সুবিধা এখনো সার্ভারে বসানো হয়নি (phase132)।', 'The server does not have this yet (phase132).', 'এটি এখনো server-এ বসানো হয়নি (phase132)।'),
  notLinked: L('আপনার লগইন কোনো কর্মচারীর নথির সাথে যুক্ত নয়, তাই ব্যক্তিগত শিফট দেখানো যাচ্ছে না।', 'Your login is not linked to an employee record, so there is no personal schedule to show.', 'আপনার login কোনো employee record-এর সাথে যুক্ত নয়, তাই শিফট দেখানো যাচ্ছে না।'),
  none: L('আগামী ১৪ দিনের জন্য কোনো শিফট ঠিক করা হয়নি।', 'No shifts are planned for the next 14 days.', 'আগামী ১৪ দিনের জন্য কোনো shift ঠিক করা হয়নি।'),
  offDay: L('ছুটির দিন (অফ)', 'Off', 'Off'), leave: L('অনুমোদিত ছুটি', 'Approved leave', 'অনুমোদিত leave'), holiday: L('সরকারি / উৎসব ছুটি', 'Holiday', 'Holiday'), today: L('আজ', 'Today', 'আজ'),
  alsoOn: L('একই জায়গায় আর যারা আছে', 'Also on at my place', 'একই জায়গায় আর যারা আছে'), onlyMe: L('আর কেউ নেই', 'Nobody else', 'আর কেউ নেই'),
  place: L('জায়গা', 'Place', 'জায়গা'), prev: L('আগের সপ্তাহ', 'Previous week', 'আগের সপ্তাহ'), next: L('পরের সপ্তাহ', 'Next week', 'পরের সপ্তাহ'), copy: L('আগের সপ্তাহ কপি করুন', 'Copy last week', 'আগের সপ্তাহ copy'),
  tpls: L('শিফট টেমপ্লেট', 'Shift templates', 'Shift template'), legend: L('সংকেত', 'Key', 'Key'), noEmp: L('এই জায়গায় কোনো কর্মী নেই।', 'No staff at this place.', 'এই জায়গায় কোনো কর্মী নেই।'),
  pickShift: L('শিফট', 'Shift', 'Shift'), clearOpt: L('— কিছু ঠিক নেই (সাপ্তাহিক নিয়ম চলবে) —', '— nothing set (weekly pattern applies) —', '— কিছু নেই (weekly pattern চলবে) —'), offOpt: L('অফ-ডে', 'Off-day', 'Off-day'),
  note: L('ছুটি / বদলের নোট (ঐচ্ছিক)', 'Leave / swap note (optional)', 'Leave / swap note (optional)'), save: L('সেভ', 'Save', 'Save'), cancel: L('বাতিল', 'Cancel', 'Cancel'), close: L('বন্ধ করুন', 'Close', 'Close'),
  saved: L('সেভ হয়েছে', 'Saved', 'Saved'), copied: L('কপি হয়েছে', 'Copied', 'Copied'), skipped: L('বাদ', 'skipped', 'skipped'),
  addTpl: L('নতুন টেমপ্লেট', 'New template', 'নতুন template'), edit: L('বদলান', 'Edit', 'Edit'), retire: L('বন্ধ করুন', 'Retire', 'Retire'),
  nameBn: L('নাম (বাংলা)', 'Name (Bangla)', 'নাম (বাংলা)'), nameEn: L('নাম (ইংরেজি)', 'Name (English)', 'Name (English)'), start: L('শুরু', 'Start', 'Start'), end: L('শেষ', 'End', 'End'), allPlaces: L('সব জায়গা (শুধু মালিক)', 'Every place (owner only)', 'সব জায়গা (owner)'),
  from: L('থেকে', 'From', 'From'), to: L('পর্যন্ত', 'To', 'To'), show: L('দেখান', 'Show', 'Show'), noAtt: L('হাজিরার তথ্য এই সার্ভারে নেই, তাই তুলনা করা গেল না।', 'There is no attendance data on this server, so nothing to compare.', 'হাজিরার data নেই, তুলনা করা গেল না।'),
  nothingRep: L('এই সময়ে তুলনা করার মতো কিছু নেই।', 'Nothing to compare in this period.', 'এই সময়ে তুলনার কিছু নেই।'), planned: L('রোস্টারে', 'Rostered', 'Rostered'),
  r_ok: L('ঠিক সময়ে', 'Present', 'Present'), r_late: L('দেরি', 'Late', 'Late'), r_half_day: L('আধা দিন', 'Half day', 'Half day'), r_leave: L('ছুটি', 'Leave', 'Leave'), r_absent: L('অনুপস্থিত', 'Absent', 'Absent'),
  r_no_record: L('হাজিরার রেকর্ড নেই', 'No attendance record', 'হাজিরা record নেই'), r_worked_off: L('অফ-ডে তে কাজ করেছে', 'Worked on an off-day', 'Off-day তে কাজ'), r_off: L('অফ-ডে', 'Off', 'Off'), r_other: L('অন্যান্য', 'Other', 'Other'),
  showAll: L('ঠিক থাকাগুলোও দেখান', 'Show the matching ones too', 'ঠিকগুলোও দেখান'),
};
const T = (k) => lab(X[k]);
const E = {
  not_allowed: L('এটির অনুমতি নেই।', 'You are not allowed to do this.', 'এটির permission নেই।'), shift_off: L('শিফট রোস্টার বন্ধ আছে।', 'The shift schedule is switched off.', 'Shift roster বন্ধ আছে।'),
  bad_date: L('ডেট ঠিক নয় (খুব আগের বা খুব পরের)।', 'The date is not valid (too far back or ahead).', 'Date ঠিক নয়।'), bad_shift: L('একটি শিফট অথবা অফ-ডে বাছুন।', 'Choose a shift or an off-day.', 'Shift অথবা off-day বাছুন।'),
  not_found: L('পাওয়া যায়নি।', 'Not found.', 'পাওয়া যায়নি।'), text_too_long: L('নোট বেশি লম্বা (২০০ অক্ষর পর্যন্ত)।', 'The note is too long (200 characters).', 'Note বেশি লম্বা (২০০)।'),
  name_required: L('নাম লিখুন।', 'Write a name.', 'নাম লিখুন।'), bad_time: L('সময় ঠিক নয়।', 'The time is not valid.', 'সময় ঠিক নয়।'), bad_location: L('জায়গা ঠিক নয়।', 'The place is not valid.', 'জায়গা ঠিক নয়।'),
};
const eText = (e) => { const m = String((e && e.message) || ''); for (const k of Object.keys(E)) if (m.indexOf(k.replace('not_allowed', 'not allowed')) >= 0) return lab(E[k]); return m || 'error'; };
const isMissing = (e) => e && (e.code === 'PGRST202' || /does not exist|could not find/i.test(e.message || ''));
async function rpc(fn, args) { const r = await sb.rpc(fn, args || {}); if (r.error) throw r.error; return r.data; }

const WD = [L('রবি', 'Sun', 'রবি'), L('সোম', 'Mon', 'সোম'), L('মঙ্গল', 'Tue', 'মঙ্গল'), L('বুধ', 'Wed', 'বুধ'), L('বৃহ', 'Thu', 'বৃহ'), L('শুক্র', 'Fri', 'শুক্র'), L('শনি', 'Sat', 'শনি')];
const todayISO = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const addDays = (iso, n) => { const d = new Date(iso + 'T00:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
const dowOf = (iso) => new Date(iso + 'T00:00:00Z').getUTCDay();
const dm = (iso) => new Date(iso + 'T00:00:00Z').toLocaleDateString('en-GB', { timeZone: 'UTC', day: '2-digit', month: 'short' });
const WSMAP = { sun: 0, mon: 1, tue: 2, wed: 3, thu: 4, fri: 5, sat: 6 };
function weekStart(iso) {
  let ws = 6; try { const r = B.rule && B.rule('week_start', null); if (typeof r === 'string' && WSMAP[r] !== undefined) ws = WSMAP[r]; } catch (e) { ws = 6; }
  return addDays(iso, -((dowOf(iso) - ws + 7) % 7));
}
const nm = (o) => lab(L(o.name_bn, o.name_en || o.name_bn, o.name_en || o.name_bn));

function css() {
  if (document.getElementById('r2s_css')) return;
  const st = document.createElement('style'); st.id = 'r2s_css';
  st.textContent = `
.r2s-day.today { border-color: var(--ruby); border-left: 6px solid var(--ruby); } .r2s-day.off, .r2s-day.leave { opacity: .92; }
.r2s-day summary { cursor: pointer; min-height: 44px; display: flex; align-items: center; } .r2s-day ul { margin: 4px 0; padding-inline-start: 20px; }
.r2s-week { display: grid; grid-template-columns: repeat(7, minmax(0, 1fr)); gap: 3px; margin-top: 6px; }
.r2s-cell { min-width: 0; min-height: 48px; padding: 2px 0; border-radius: 8px; border: 1px solid var(--line); background: var(--card); color: var(--text); display: flex; flex-direction: column; align-items: center; justify-content: center; line-height: 1.15; font: 600 .72rem var(--text-font); box-shadow: none; }
.r2s-cell .c { font: 800 1rem var(--text-font); } .r2s-cell.off { background: var(--warn-bg); color: var(--warn); } .r2s-cell.pat { border-style: dashed; } .r2s-cell.none .c { opacity: .4; }
.r2s-cell.note { box-shadow: inset 0 -3px 0 var(--ruby); } .r2s-cell.lv { box-shadow: inset 0 3px 0 var(--ok); } .r2s-cell.hol { background: var(--ok-bg); }
.r2s-btns { display: flex; flex-wrap: wrap; gap: 8px; margin: 8px 0; } .r2s-btns > * { flex: 1 1 130px; min-height: 44px; }
.r2s-leg { display: flex; flex-wrap: wrap; gap: 6px; margin: 6px 0; } .r2s-nav { display: flex; gap: 8px; align-items: center; margin: 8px 0; } .r2s-nav b { flex: 1; text-align: center; } .r2s-nav button { min-width: 44px; min-height: 44px; }
.r2s-chips { display: flex; flex-wrap: wrap; gap: 6px; margin: 6px 0; }
#r2s_all, #r2s_all0 { width: 24px; min-height: 24px; flex: none; }
`;
  document.head.appendChild(st);
}

const D = { st: null, tab: 'my', my: null, loc: null, from: null, ros: null, rep: null, rfrom: null, rto: null, repAll: false, cell: null, tplId: null };
const shiftTxt = (s) => (s ? `${nm(s)} ${s.start}–${s.end}` : '');

/* ---------- my shifts ---------- */
function myHTML() {
  const m = D.my;
  if (!m.linked) return `<div class="notice" data-state="notlinked">${esc(T('notLinked'))}</div>`;
  if (!m.days.length) return B.ui.state('empty', T('none'));
  const td = todayISO();
  return m.days.map((d) => {
    const isOff = d.off, kind = d.leave ? 'leave' : isOff ? 'off' : '';
    const chip = d.shift ? `<span class="chip ok">${esc(shiftTxt(d.shift))}</span>` : isOff ? `<span class="chip warn">${esc(T('offDay'))}</span>` : '';
    const mates = (d.mates || []);
    return `<div class="card r2s-day ${d.day === td ? 'today' : ''} ${kind}" data-day="${esc(d.day)}"><div class="row between" style="align-items:flex-start;gap:8px"><b>${esc(lab(WD[d.dow]))} ${esc(dm(d.day))}${d.day === td ? ' · ' + esc(T('today')) : ''}</b>${chip}</div>
      <div class="r2s-chips">${d.leave ? `<span class="chip ok">${esc(T('leave'))}</span>` : ''}${d.holiday_bn || d.holiday_en ? `<span class="chip">${esc(T('holiday'))}: ${esc(lab(L(d.holiday_bn, d.holiday_en || d.holiday_bn, d.holiday_en || d.holiday_bn)))}</span>` : ''}</div>
      ${d.note ? `<div style="font-size:.92rem;overflow-wrap:anywhere">${esc(d.note)}</div>` : ''}
      ${D.my.mates_on && d.shift ? `<details><summary>${esc(T('alsoOn'))} (${mates.length})</summary>${mates.length ? `<ul>${mates.map((p) => `<li>${esc(lab(L(p.name_bn, p.name_en || p.name_bn, p.name_en || p.name_bn)))} <span class="muted">· ${esc(p.start)}–${esc(p.end)}</span></li>`).join('')}</ul>` : `<div class="muted">${esc(T('onlyMe'))}</div>`}</details>` : ''}</div>`;
  }).join('');
}

/* ---------- roster ---------- */
const letter = (i) => String.fromCharCode(65 + (i % 26));
function rosterHTML() {
  const r = D.ros; if (!r) return B.ui.state('loading');
  const tpls = r.templates, code = new Map(tpls.map((t, i) => [t.id, letter(i)]));
  const days = []; for (let i = 0; i < r.days; i++) days.push(addDays(r.from, i));
  const legend = tpls.map((t, i) => `<span class="chip" title="${esc(shiftTxt({ ...t }))}"><b>${letter(i)}</b>&nbsp;${esc(nm(t))} ${esc(t.start)}–${esc(t.end)}</span>`).join('') + `<span class="chip warn"><b>×</b>&nbsp;${esc(T('offDay'))}</span>`;
  const emps = r.employees.length ? r.employees.map((e) => {
    const byDay = new Map(e.days.map((x) => [x.day, x]));
    const cells = days.map((d) => { const x = byDay.get(d); const c = x ? (x.off ? '×' : (code.get(x.shift_id) || '?')) : '·';
      return `<button type="button" class="r2s-cell ${x ? (x.off ? 'off' : '') : 'none'} ${x && x.source === 'pattern' ? 'pat' : ''} ${x && x.note ? 'note' : ''} ${x && x.leave ? 'lv' : ''} ${x && (x.holiday_bn || x.holiday_en) ? 'hol' : ''}" data-act="r2s_cell" data-emp="${esc(e.id)}" data-day="${esc(d)}" aria-label="${esc((e.name_en || e.name_bn) + ' ' + d)}"><span>${esc(lab(WD[dowOf(d)]))} ${esc(String(Number(d.slice(8))))}</span><span class="c">${esc(c)}</span></button>`; }).join('');
    return `<div class="card r2s-emp" data-emp="${esc(e.id)}"><b>${esc(lab(L(e.name_bn, e.name_en || e.name_bn, e.name_en || e.name_bn)))}</b><div class="r2s-week">${cells}</div></div>`; }).join('') : B.ui.state('empty', T('noEmp'));
  return `<div class="r2s-leg" aria-label="${esc(T('legend'))}">${legend}</div>${emps}`;
}
function locName(id) { const l = ((B.ENV && B.ENV.locs) || []).find((x) => x.id === id); return l ? lab(L(l.name_bn, l.name_en || l.name_bn, l.name_mix || l.name_bn)) : '#' + id; }
async function loadRoster() {
  if (D.loc === null) D.loc = (D.st.locations || [])[0] || null;
  if (D.loc === null) { D.ros = { templates: [], employees: [], days: 7, from: D.from }; return; }
  if (!D.from) D.from = weekStart(todayISO());
  D.ros = await rpc('r2_shift_roster', { p_loc: D.loc, p_from: D.from, p_days: 7 });
}
function rosterTab() {
  const st = D.st; const locs = st.locations || [];
  return `<div class="stack"><div><label for="r2s_loc">${esc(T('place'))}</label><select id="r2s_loc" data-r2s="loc">${locs.map((l) => `<option value="${l}" ${l === D.loc ? 'selected' : ''}>${esc(locName(l))}</option>`).join('')}</select></div>
    <div class="r2s-nav"><button type="button" data-act="r2s_wk" data-v="-7" aria-label="${esc(T('prev'))}">‹</button><b>${esc(dm(D.from))} – ${esc(dm(addDays(D.from, 6)))}</b><button type="button" data-act="r2s_wk" data-v="7" aria-label="${esc(T('next'))}">›</button></div></div>
    <div class="r2s-btns"><button type="button" data-act="r2s_copy">${esc(T('copy'))}</button><button type="button" data-act="r2s_tpls">${esc(T('tpls'))}</button></div>
    <div id="r2s_grid">${rosterHTML()}</div>`;
}

/* ---------- report ---------- */
function reportTab() {
  const r = D.rep; const locs = D.st.locations || [];
  const filt = r ? r.rows.filter((x) => D.repAll || (x.result !== 'ok' && x.result !== 'off')) : [];
  const tot = r && r.totals ? Object.keys(r.totals).map((k) => `<span class="chip ${k === 'ok' || k === 'off' ? 'ok' : k === 'late' || k === 'half_day' || k === 'leave' ? 'warn' : 'bad'}">${esc(T('r_' + k) || k)}: ${esc(r.totals[k])}</span>`).join('') : '';
  return `<div class="stack"><div><label for="r2s_loc">${esc(T('place'))}</label><select id="r2s_loc" data-r2s="loc">${locs.map((l) => `<option value="${l}" ${l === D.loc ? 'selected' : ''}>${esc(locName(l))}</option>`).join('')}</select></div>
    <div class="row wrap"><div style="flex:1 1 140px"><label for="r2s_rf">${esc(T('from'))}</label><input id="r2s_rf" type="date" value="${esc(D.rfrom)}"></div><div style="flex:1 1 140px"><label for="r2s_rt">${esc(T('to'))}</label><input id="r2s_rt" type="date" value="${esc(D.rto)}"></div></div>
    <button type="button" class="primary full" data-act="r2s_rep">${esc(T('show'))}</button></div>
    ${!r ? '' : r.attendance === false ? `<div class="notice warn" data-state="noatt">${esc(T('noAtt'))}</div>` : `<div class="r2s-chips" id="r2s_tot">${tot}</div>
      <label class="row" style="align-items:center"><input type="checkbox" id="r2s_all" data-act="r2s_all" ${D.repAll ? 'checked' : ''}> ${esc(T('showAll'))}</label>
      <div id="r2s_rows">${filt.length ? filt.map((x) => `<div class="card r2s-row" data-result="${esc(x.result)}"><div class="row between" style="gap:8px"><b>${esc(lab(L(x.name_bn, x.name_en || x.name_bn, x.name_en || x.name_bn)))}</b><span class="chip ${x.result === 'ok' || x.result === 'off' ? 'ok' : x.result === 'late' || x.result === 'half_day' || x.result === 'leave' ? 'warn' : 'bad'}">${esc(T('r_' + x.result))}</span></div>
        <div class="muted" style="font-size:.88rem">${esc(dm(x.day))}${x.planned ? ' · ' + esc(T('planned')) + ' ' + esc(x.shift_bn || '') + ' ' + esc(x.start || '') + '–' + esc(x.end || '') : ' · ' + esc(T('r_off'))}${x.late_minutes ? ' · +' + esc(x.late_minutes) + ' min' : ''}</div></div>`).join('') : B.ui.state('empty', T('nothingRep'))}</div>`}`;
}

/* ---------- page ---------- */
async function view() {
  if (B.loadStatic) { try { await B.loadStatic(); } catch (e) { /* still opens */ } }
  css(); D.tab = 'my';
  shell(T('title'), `<div id="r2s_body"><p class="muted">…</p></div>`, true);
  await load();
}
async function load() {
  const box = $('#r2s_body'); if (!box) return;
  let st;
  try { st = await rpc('r2_shift_state'); } catch (e) { box.innerHTML = `<div class="notice warn">${esc(isMissing(e) ? T('nofn') : eText(e))}</div>`; return; }
  D.st = st;
  if (!st.on) { box.innerHTML = `<div class="notice warn" data-state="off">${esc(T('off'))}</div>`; return; }
  if (!D.rfrom) { D.rto = todayISO(); D.rfrom = addDays(D.rto, -6); }
  if (!D.from) D.from = weekStart(todayISO());
  await loadTab(); draw();
}
async function loadTab() {
  try {
    if (D.tab === 'my') D.my = await rpc('r2_shift_my', { p_from: todayISO(), p_days: 14 });
    else if (D.tab === 'roster') await loadRoster();
  } catch (e) { toast(eText(e)); if (D.tab === 'my') D.my = { linked: false, days: [] }; }
}
function draw() {
  const box = $('#r2s_body'); if (!box || !D.st) return;
  const can = D.st.can_manage && (D.st.locations || []).length;
  const tabs = can ? `<div class="seg" role="group"><button type="button" data-act="r2s_tab" data-v="my" aria-pressed="${D.tab === 'my'}">${esc(T('my'))}</button><button type="button" data-act="r2s_tab" data-v="roster" aria-pressed="${D.tab === 'roster'}">${esc(T('roster'))}</button><button type="button" data-act="r2s_tab" data-v="report" aria-pressed="${D.tab === 'report'}">${esc(T('report'))}</button></div>` : '';
  box.innerHTML = tabs + (D.tab === 'my' ? (D.my ? myHTML() : B.ui.state('loading')) : D.tab === 'roster' ? rosterTab() : reportTab());
}

/* ---------- sheets ---------- */
function cellSheet(emp, day) {
  const r = D.ros; const e = r.employees.find((x) => x.id === emp); const x = e && e.days.find((d) => d.day === day);
  const cur = x ? (x.off ? 'off' : (x.source === 'day' ? String(x.shift_id) : '')) : '';
  D.cell = { emp, day };
  openSheet(`<h3>${esc(e ? lab(L(e.name_bn, e.name_en || e.name_bn, e.name_en || e.name_bn)) : '')} · ${esc(lab(WD[dowOf(day)]))} ${esc(dm(day))}</h3><div class="stack">
    <div><label for="r2s_sel">${esc(T('pickShift'))}</label><select id="r2s_sel"><option value="">${esc(T('clearOpt'))}</option>${r.templates.map((t, i) => `<option value="${t.id}" ${cur === String(t.id) ? 'selected' : ''}>${letter(i)} · ${esc(nm(t))} ${esc(t.start)}–${esc(t.end)}</option>`).join('')}<option value="off" ${cur === 'off' ? 'selected' : ''}>× ${esc(T('offOpt'))}</option></select></div>
    <div><label for="r2s_note">${esc(T('note'))}</label><input id="r2s_note" maxlength="200" autocomplete="off" value="${esc((x && x.source === 'day' && x.note) || '')}"></div>
    <div class="r2s-btns"><button type="button" class="primary" data-act="r2s_cellsave">${esc(T('save'))}</button><button type="button" data-act="closesheet">${esc(T('cancel'))}</button></div></div>`);
}
function tplListSheet() {
  const r = D.ros;
  openSheet(`<h3>${esc(T('tpls'))}</h3><div id="r2s_tpllist">${r.templates.map((t, i) => `<div class="card"><div class="row between" style="gap:8px"><span><b>${letter(i)}</b> · ${esc(nm(t))} <span class="muted">${esc(t.start)}–${esc(t.end)}${t.location_id ? '' : ' · ' + esc(T('allPlaces'))}</span></span></div>
    <div class="r2s-btns"><button type="button" data-act="r2s_tpledit" data-v="${esc(t.id)}">${esc(T('edit'))}</button><button type="button" data-act="r2s_tplretire" data-v="${esc(t.id)}">${esc(T('retire'))}</button></div></div>`).join('')}</div>
    <div class="r2s-btns"><button type="button" class="primary" data-act="r2s_tplnew">${esc(T('addTpl'))}</button><button type="button" data-act="closesheet">${esc(T('close'))}</button></div>`);
}
function tplForm(t) {
  D.tplId = t ? t.id : null; const isOwner = !!(S.ctx && S.ctx.is_owner);
  openSheet(`<h3>${esc(t ? T('edit') : T('addTpl'))}</h3><div class="stack">
    <div><label for="r2s_nb">${esc(T('nameBn'))}</label><input id="r2s_nb" maxlength="60" autocomplete="off" value="${esc(t ? t.name_bn : '')}"></div>
    <div><label for="r2s_ne">${esc(T('nameEn'))}</label><input id="r2s_ne" maxlength="60" autocomplete="off" value="${esc((t && t.name_en) || '')}"></div>
    <div class="row wrap"><div style="flex:1 1 130px"><label for="r2s_st">${esc(T('start'))}</label><input id="r2s_st" type="time" value="${esc(t ? t.start : '09:00')}"></div><div style="flex:1 1 130px"><label for="r2s_en">${esc(T('end'))}</label><input id="r2s_en" type="time" value="${esc(t ? t.end : '17:00')}"></div></div>
    ${isOwner ? `<label class="row" style="align-items:center"><input type="checkbox" id="r2s_all0" ${t && !t.location_id ? 'checked' : ''}> ${esc(T('allPlaces'))}</label>` : ''}
    <div class="r2s-btns"><button type="button" class="primary" data-act="r2s_tplsave">${esc(T('save'))}</button><button type="button" data-act="closesheet">${esc(T('cancel'))}</button></div></div>`);
}

Object.assign(H, {
  r2s_tab: async (a) => { D.tab = a.dataset.v; D.my = D.tab === 'my' ? null : D.my; draw(); await loadTab(); draw(); },
  r2s_wk: async (a) => { D.from = addDays(D.from, Number(a.dataset.v)); D.ros = null; draw(); await loadTab(); draw(); },
  r2s_all: (a) => { D.repAll = !!a.checked; draw(); },
  r2s_cell: (a) => cellSheet(a.dataset.emp, a.dataset.day),
  r2s_cellsave: async () => {
    const c = D.cell; if (!c) return; const v = ($('#r2s_sel') || {}).value || '', note = (($('#r2s_note') || {}).value || '').trim();
    try {
      if (v === '') await rpc('r2_roster_clear', { p_emp: c.emp, p_day: c.day });
      else await rpc('r2_roster_set', { p_emp: c.emp, p_day: c.day, p_shift: v === 'off' ? null : Number(v), p_off: v === 'off', p_note: note || null, p_loc: null });
      closeSheet(); toast(T('saved')); await loadTab(); draw();
    } catch (e) { toast(eText(e)); }
  },
  r2s_copy: async () => {
    try { const r = await rpc('r2_roster_copy_week', { p_loc: D.loc, p_from: addDays(D.from, -7), p_to: D.from }); toast(T('copied') + ': ' + r.copied + (r.skipped ? ' · ' + T('skipped') + ' ' + r.skipped : '')); await loadTab(); draw(); } catch (e) { toast(eText(e)); }
  },
  r2s_tpls: () => tplListSheet(),
  r2s_tplnew: () => tplForm(null),
  r2s_tpledit: (a) => tplForm(D.ros.templates.find((t) => String(t.id) === a.dataset.v)),
  r2s_tplretire: async (a) => { try { await rpc('r2_shift_template_save', { p_id: Number(a.dataset.v), p_data: { active: false } }); closeSheet(); toast(T('saved')); await loadTab(); draw(); } catch (e) { toast(eText(e)); } },
  r2s_tplsave: async () => {
    const all0 = !!($('#r2s_all0') || {}).checked;
    const data = { name_bn: (($('#r2s_nb') || {}).value || '').trim(), name_en: (($('#r2s_ne') || {}).value || '').trim() || null, start_time: ($('#r2s_st') || {}).value, end_time: ($('#r2s_en') || {}).value };
    if (!D.tplId) data.location_id = all0 ? null : D.loc; else if (all0) data.location_id = null;
    if (!data.name_bn) return toast(lab(E.name_required));
    try { await rpc('r2_shift_template_save', { p_id: D.tplId, p_data: data }); closeSheet(); toast(T('saved')); await loadTab(); draw(); } catch (e) { toast(eText(e)); }
  },
  r2s_rep: async () => {
    D.rfrom = ($('#r2s_rf') || {}).value || D.rfrom; D.rto = ($('#r2s_rt') || {}).value || D.rto;
    if (D.loc === null) D.loc = (D.st.locations || [])[0] || null;
    try { D.rep = await rpc('r2_shift_report', { p_loc: D.loc, p_from: D.rfrom, p_to: D.rto }); draw(); } catch (e) { toast(eText(e)); }
  },
});
document.addEventListener('change', async (e) => {
  const el = e.target; if (!el || !el.getAttribute || el.getAttribute('data-r2s') !== 'loc') return;
  D.loc = Number(el.value); D.ros = null; D.rep = null; if (D.tab === 'roster') { draw(); await loadTab(); } draw();
});

B.shifts = { load };
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { shifts: view });
})();
