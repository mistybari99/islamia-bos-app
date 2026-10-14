/* Islamia BOS · Attendance (#/attendance) and Leave (#/leave): today board per place, manual mark with a reason + approval by a second person,
   overtime approval, month grid per person, fingerprint device file import (preview first, then a batch that can be undone), unmapped device ids,
   device list (owner registers a machine and sees its token once), shifts / roster / holidays, leave requests + approvals + balances,
   optional staff check in / out (rule app_punch_on, default OFF).
   Server: supabase/phase42.sql - attendance_board / attendance_month / attendance_recompute / attendance_mark / attendance_approve / attendance_ot_approve /
   attendance_import (p_dry = preview) / attendance_import_void / attendance_unmapped / attendance_map_user / attendance_device_register /
   attendance_device_token_reset / attendance_device_set_active / attendance_app_punch / shift_save / shift_assign / shift_assign_end / holiday_save /
   holiday_retire / leave_request_save / leave_decide / leave_cancel / leave_balances. No money is shown here (pay lives in #/payroll). Nothing is deleted. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet, H, nm } = A;
const L = B.L, lab = B.lab;
const U = B.s2;
const { rid, LOCS } = U;
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const hm = (x) => (x ? new Date(x).toLocaleTimeString('en-GB', { timeZone: 'Asia/Dhaka', hour: '2-digit', minute: '2-digit' }) : '');
const dhm = (x) => (x ? new Date(x).toLocaleString('en-GB', { timeZone: 'Asia/Dhaka', day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }) : '');
const mins = (m) => { m = Number(m) || 0; return m >= 60 ? Math.floor(m / 60) + 'h ' + (m % 60 ? (m % 60) + 'm' : '') : m + 'm'; };
const X = {
  title: L('হাজিরা', 'Attendance', 'Attendance'), leaveT: L('ছুটি', 'Leave', 'Leave'), place: L('জায়গা', 'Place', 'Place'), date: L('ডেট', 'Date', 'Date'), month: L('মাস', 'Month', 'Month'),
  tToday: L('আজকের বোর্ড', 'Today', 'Today'), tMonth: L('মাসের ছক', 'Month grid', 'Month grid'), tImport: L('মেশিনের ফাইল', 'Device file', 'Device file'), tDevices: L('মেশিন', 'Devices', 'Devices'), tSetup: L('শিফট ও ছুটির দিন', 'Shifts & holidays', 'Shift ও holiday'),
  present: L('উপস্থিত', 'Present', 'Present'), absent: L('অনুপস্থিত', 'Absent', 'Absent'), late: L('দেরি', 'Late', 'Late'), half_day: L('অর্ধ দিন', 'Half day', 'Half day'), leave: L('ছুটিতে', 'On leave', 'On leave'),
  off: L('সাপ্তাহিক ছুটি', 'Weekly off', 'Weekly off'), holiday: L('ছুটির দিন', 'Holiday', 'Holiday'), unpaid: L('বিনা বেতনে', 'Unpaid', 'Unpaid'), pending: L('অ্যাপ্রুভ অপেক্ষায়', 'Waiting approval', 'Approval অপেক্ষায়'),
  inT: L('ঢোকা', 'In', 'In'), outT: L('বের', 'Out', 'Out'), ot: L('ওভারটাইম', 'Overtime', 'Overtime'), lateM: L('দেরি', 'late', 'late'), single: L('একবার আঙুল (বের হওয়া নেই)', 'One punch only (no out)', 'একবার punch (out নেই)'),
  recompute: L('পাঞ্চ থেকে আবার হিসাব', 'Recompute from punches', 'Punch থেকে আবার হিসাব'), recomputed: L('আবার হিসাব হয়েছে', 'Recomputed', 'আবার হিসাব হয়েছে'),
  mark: L('হাতে লিখুন / সংশোধন', 'Mark / correct', 'হাতে লিখুন / সংশোধন'), status: L('অবস্থা', 'Status', 'Status'), reason: L('কারণ (জরুরি)', 'Reason (required)', 'কারণ (জরুরি)'), note: L('নোট', 'Note', 'Note'),
  otMin: L('ওভারটাইম মিনিট (ফাঁকা = সময় থেকে)', 'Overtime minutes (empty = from the times)', 'OT মিনিট (ফাঁকা = সময় থেকে)'), save: L('সেভ', 'Save', 'Save'), saved: L('সেভ হয়েছে', 'Saved', 'Saved'),
  approve: L('অ্যাপ্রুভ', 'Approve', 'Approve'), reject: L('বাতিল (পাঞ্চে ফেরত)', 'Reject (back to punches)', 'Reject (punch-এ ফেরত)'), otApprove: L('ওভারটাইম অ্যাপ্রুভ', 'Approve overtime', 'OT approve'),
  monthOf: L('মাসের হাজিরা', 'Month view', 'Month view'), who: L('কর্মচারী', 'Employee', 'Employee'), pick: L('বাছুন', 'Choose', 'বাছুন'), none: L('কেউ নেই', 'Nobody', 'কেউ নেই'), nothing: L('কিছু নেই', 'Nothing yet', 'কিছু নেই'),
  locked: L('এই মাসের বেতন অ্যাপ্রুভড - হাজিরা বন্ধ', 'Payroll approved - this month is locked', 'Payroll approved - মাস lock'), manual: L('হাতে লেখা', 'manual', 'manual'),
  file: L('ফাইল বাছুন (.dat / .txt / .csv)', 'Choose the file (.dat / .txt / .csv)', 'File বাছুন (.dat / .txt / .csv)'), paste: L('অথবা লেখা পেস্ট করুন', 'or paste the text', 'অথবা text paste করুন'),
  device: L('কোন মেশিনের', 'From which device', 'কোন device'), noDevice: L('উল্লেখ নেই', 'Not given', 'উল্লেখ নেই'), colUser: L('আইডি কলাম', 'ID column', 'ID column'), colTs: L('সময় কলাম', 'Time column', 'Time column'), colDir: L('ঢোকা/বের কলাম', 'In/out column', 'In/out column'),
  preview: L('আগে দেখুন (কিছু লেখা হবে না)', 'Preview (nothing is saved)', 'আগে দেখুন (কিছু save হবে না)'), doImport: L('আমদানি করুন', 'Import', 'Import'), read: L('পড়া হলো', 'Rows read', 'Rows read'),
  pNew: L('নতুন', 'New', 'New'), pDup: L('আগেই আছে / দুবার', 'Duplicates', 'Duplicate'), pBad: L('পড়া যায়নি', 'Unreadable', 'Unreadable'), pUnm: L('অচেনা আইডি', 'Unknown ids', 'অচেনা ID'), pPeople: L('কর্মচারী', 'People', 'People'), range: L('সময়সীমা', 'Range', 'Range'),
  batches: L('আগের আমদানি', 'Earlier imports', 'আগের import'), undo: L('ফেরত নিন', 'Undo', 'Undo'), undone: L('ফেরত নেওয়া হয়েছে', 'Undone', 'Undone'), why: L('কারণ লিখুন (কমপক্ষে ৩ অক্ষর)', 'Write a reason (3+ letters)', 'কারণ লিখুন'),
  unmapped: L('অচেনা মেশিন-আইডি', 'Unknown device ids', 'অচেনা device ID'), link: L('জুড়ুন', 'Link', 'Link'), linked: L('জোড়া হয়েছে', 'Linked', 'Linked'), punches: L('পাঞ্চ', 'punches', 'punch'),
  devices: L('ফিঙ্গারপ্রিন্ট মেশিন', 'Fingerprint devices', 'Fingerprint device'), register: L('＋ মেশিন যোগ', '＋ Register device', '＋ Device যোগ'), dName: L('নাম', 'Name', 'Name'), vendor: L('কোম্পানি', 'Brand', 'Brand'), serial: L('সিরিয়াল', 'Serial', 'Serial'),
  token: L('গোপন টোকেন (একবারই দেখাবে - এখনই কপি করুন)', 'Secret token (shown once - copy it now)', 'Secret token (একবারই দেখাবে)'), copy: L('কপি', 'Copy', 'Copy'), copied: L('কপি হয়েছে', 'Copied', 'Copied'),
  reset: L('নতুন টোকেন', 'New token', 'নতুন token'), on: L('চালু', 'On', 'On'), offS: L('বন্ধ', 'Off', 'Off'), lastSeen: L('শেষ যোগাযোগ', 'Last seen', 'Last seen'), never: L('এখনো না', 'never', 'never'), rows: L('সারি', 'rows', 'rows'),
  bridge: L('PC / Raspberry Pi-তে tools/fingerprint_bridge.py চালান (docs/FINGERPRINT.md):', 'Run tools/fingerprint_bridge.py on a PC / Raspberry Pi (docs/FINGERPRINT.md):', 'PC / Raspberry Pi-তে fingerprint_bridge.py চালান:'),
  shifts: L('শিফট', 'Shifts', 'Shifts'), addShift: L('＋ শিফট', '＋ Shift', '＋ Shift'), start: L('শুরু', 'Start', 'Start'), end: L('শেষ', 'End', 'End'), grace: L('দেরি ছাড় (মিনিট)', 'Late grace (min)', 'Late grace (min)'),
  graceE: L('আগে যাওয়া ছাড় (মিনিট)', 'Early-leave grace (min)', 'Early grace (min)'), brk: L('বিরতি (মিনিট)', 'Break (min)', 'Break (min)'), full: L('পূর্ণ দিন কমপক্ষে (ঘণ্টা)', 'Full day at least (hours)', 'Full day (hours)'),
  half: L('অর্ধ দিন কমপক্ষে (ঘণ্টা)', 'Half day at least (hours)', 'Half day (hours)'), dflt: L('এই জায়গার সাধারণ শিফট', 'Default for this place', 'এই জায়গার default'), night: L('রাত পেরোয়', 'crosses midnight', 'রাত পেরোয়'),
  assign: L('শিফট দিন', 'Assign shift', 'Shift দিন'), from: L('থেকে', 'From', 'From'), to: L('পর্যন্ত (ফাঁকা = চলবে)', 'To (empty = open)', 'To (ফাঁকা = চলবে)'), days: L('যে দিনগুলোতে', 'On these days', 'যে দিনগুলোতে'),
  offDays: L('সাপ্তাহিক ছুটি (ফাঁকা = সাধারণ নিয়ম)', 'Weekly off (empty = the general rule)', 'Weekly off (ফাঁকা = সাধারণ নিয়ম)'), holidays: L('ছুটির দিন', 'Holidays', 'Holidays'), addHol: L('＋ ছুটির দিন', '＋ Holiday', '＋ Holiday'),
  hName: L('নাম (বাংলা)', 'Name (Bangla)', 'নাম (বাংলা)'), hNameEn: L('নাম (ইংরেজি)', 'Name (English)', 'Name (English)'), paid: L('বেতনসহ', 'Paid', 'Paid'), allPlaces: L('সব জায়গা', 'All places', 'সব জায়গা'), remove: L('বাদ দিন', 'Remove', 'Remove'),
  checkIn: L('চেক ইন', 'Check in', 'Check in'), checkOut: L('চেক আউট', 'Check out', 'Check out'), punched: L('হাজিরা নেওয়া হয়েছে', 'Punch recorded', 'Punch হয়েছে'),
  // leave
  tReq: L('অনুরোধ', 'Requests', 'Requests'), tBal: L('বাকি ছুটি', 'Balances', 'Balances'), newReq: L('＋ ছুটির অনুরোধ', '＋ Leave request', '＋ Leave request'), type: L('ধরন', 'Type', 'Type'), lReason: L('কারণ', 'Reason', 'Reason'),
  dayCount: L('দিন', 'days', 'days'), lPending: L('অপেক্ষায়', 'Pending', 'Pending'), lApproved: L('অ্যাপ্রুভড', 'Approved', 'Approved'), lRejected: L('নাকচ', 'Rejected', 'Rejected'), lCancelled: L('ক্যান্সেল', 'Cancelled', 'Cancelled'),
  cancelL: L('ক্যান্সেল করুন', 'Cancel', 'Cancel'), entitled: L('বছরে প্রাপ্য', 'Per year', 'Per year'), taken: L('নেওয়া', 'Taken', 'Taken'), remaining: L('বাকি', 'Left', 'Left'), year: L('বছর', 'Year', 'Year'),
  noLimit: L('সীমা নেই', 'no limit', 'no limit'), decideNote: L('নোট (ঐচ্ছিক)', 'Note (optional)', 'Note (optional)'),
  sun: L('রবি', 'Sun', 'Sun'), mon: L('সোম', 'Mon', 'Mon'), tue: L('মঙ্গল', 'Tue', 'Tue'), wed: L('বুধ', 'Wed', 'Wed'), thu: L('বৃহঃ', 'Thu', 'Thu'), fri: L('শুক্র', 'Fri', 'Fri'), sat: L('শনি', 'Sat', 'Sat'),
};
const T = (k) => lab(X[k]);
const WD = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
const STATUS = ['present', 'late', 'half_day', 'absent', 'off', 'holiday', 'unpaid'];
const stCls = (s) => (s === 'present' ? 'ok' : s === 'late' || s === 'half_day' ? 'warn' : s === 'absent' || s === 'unpaid' ? 'bad' : s === 'leave' ? 'info' : '');
const ERR = {
  'not allowed': L('অনুমতি নেই', 'Not allowed', 'Permission নেই'), attendance_off: L('হাজিরা এখন বন্ধ (সুইচবোর্ড)', 'Attendance is switched off (Switchboard)', 'Attendance বন্ধ (Switchboard)'),
  reason_required: L('কারণ লিখুন (কমপক্ষে ৩ অক্ষর)', 'Write a reason (3+ letters)', 'কারণ লিখুন'), bad_date: L('ডেট ঠিক নয়', 'Date is not valid', 'Date ঠিক নয়'), bad_time: L('সময় ঠিক নয় (যেমন 09:05)', 'Time is not valid (e.g. 09:05)', 'Time ঠিক নয় (09:05)'),
  bad_range: L('সর্বোচ্চ ৬২ দিন একসাথে', 'At most 62 days at a time', 'সর্বোচ্চ ৬২ দিন'), month_locked: X.locked, maker_cannot_approve: L('নিজের লেখা নিজে অ্যাপ্রুভ করা যায় না', 'You cannot approve your own entry', 'নিজের entry নিজে approve নয়'),
  leave_overlap: L('এই ডেটে আগেই ছুটির অনুরোধ আছে', 'There is already a leave request on these dates', 'এই date-এ আগেই leave আছে'), leave_balance_short: L('যথেষ্ট ছুটি বাকি নেই', 'Not enough leave left', 'যথেষ্ট leave বাকি নেই'),
  leave_no_working_days: L('এই সময়ে কোনো কাজের দিন নেই', 'No working day in these dates', 'কোনো কাজের দিন নেই'), leave_cross_year: L('এক বছরের মধ্যে রাখুন', 'Keep it inside one year', 'এক বছরের মধ্যে রাখুন'),
  bad_leave_type: L('ছুটির ধরন বাছুন', 'Choose the leave type', 'Leave type বাছুন'), leave_not_pending: L('এই অনুরোধের সিদ্ধান্ত হয়ে গেছে', 'This request was already decided', 'আগেই decide হয়েছে'),
  too_many_rows: L('ফাইল অনেক বড় (একবারে সর্বোচ্চ ৫০০০ সারি) - ভাগ করুন', 'The file is too big (5000 rows at most) - split it', 'File বড় (৫০০০ সারি) - ভাগ করুন'),
  duplicate_device_id: L('এই মেশিন-আইডি অন্য কারো', 'This device id belongs to someone else', 'এই device ID অন্য কারো'), device_id_in_use: L('এই কর্মীর আগের আইডিতে পাঞ্চ আছে', 'This person already has punches under another id', 'আগের ID-তে punch আছে'),
  bad_user_id: L('আইডি ঠিক নয়', 'The id is not valid', 'ID ঠিক নয়'), app_punch_off: L('অ্যাপ থেকে হাজিরা বন্ধ', 'App check-in is switched off', 'App check-in বন্ধ'), too_soon: L('এক মিনিট পরে আবার চেষ্টা করুন', 'Try again in a minute', 'এক মিনিট পরে'),
  no_employee_record: L('আপনার কর্মচারী-তথ্য জোড়া নেই', 'Your login is not linked to an employee record', 'Employee record জোড়া নেই'), name_required: L('নাম লিখুন', 'Write the name', 'নাম লিখুন'),
  bad_status: L('অবস্থা বাছুন', 'Choose a status', 'Status বাছুন'), bad_hours: L('অর্ধ দিনের ঘণ্টা পূর্ণ দিনের চেয়ে কম হবে', 'Half-day hours must be below full-day hours', 'Half < full'),
  bad_shift: L('শিফট বাছুন', 'Choose a shift', 'Shift বাছুন'), bad_mask: L('অন্তত একটি দিন বাছুন', 'Choose at least one day', 'অন্তত একটি দিন'), not_found: L('পাওয়া যায়নি', 'Not found', 'Not found'),
};
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? lab(ERR[k]) : (m || 'error'); };
const D = { loc: null, day: today(), tab: 'today', board: null, emps: [], emp: null, month: today().slice(0, 7), grid: null, imp: null, prev: null, devices: [], batches: [], shifts: [], hols: [], unm: [], client: rid(), can: {} };
const LV = { tab: 'req', reqs: [], types: [], emp: null, year: Number(today().slice(0, 4)), bal: null };

async function can(code) {
  if (S.ctx.is_owner) return true;
  const k = code + '|' + D.loc; if (k in D.can) return D.can[k];
  D.can[k] = await U.grant(code, D.loc); return D.can[k];
}
const locSel = (id) => `<select id="${id}" aria-label="${esc(T('place'))}">${LOCS().map((l) => `<option value="${l.id}" ${l.id === D.loc ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select>`;
const empName = (e) => (S.lang === 'en' && (e.full_name_en || e.name_en) ? (e.full_name_en || e.name_en) : (e.full_name_bn || e.name_bn || ''));
async function loadEmps() {
  const r = await sb.from('employees').select('id,employee_no,full_name_bn,full_name_en,primary_location_id,status,device_user_id,photo_path,profile_id').in('status', ['active', 'on_leave']).order('employee_no');
  D.emps = (r.data || []).filter((e) => e.primary_location_id === D.loc);
}
const css = document.createElement('style'); css.id = 'attcss';
css.textContent = `.at-row{display:flex;gap:8px;align-items:center;justify-content:space-between}.at-row .nm{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis}
.at-sum{display:flex;flex-wrap:wrap;gap:6px;margin:8px 0}.at-grid{display:grid;grid-template-columns:repeat(7,minmax(0,1fr));gap:3px}.at-grid .c{border:1px solid var(--hair);border-radius:8px;padding:3px 1px;min-height:44px;font-size:11px;text-align:center;overflow:hidden;overflow-wrap:anywhere}
.at-pick{display:flex;flex-wrap:wrap;gap:8px}.at-pick>div{flex:1 1 140px;min-width:0}.at-pick select,.at-pick input{width:100%;max-width:100%}
.at-grid .c.ok{background:var(--ok-bg)}.at-grid .c.warn{background:var(--warn-bg)}.at-grid .c.bad{background:var(--bad-bg)}.at-grid .c.info{background:var(--info-tint,var(--card))}.at-grid .h{font-size:11px;text-align:center;opacity:.7}
.at-tok{word-break:break-all;font-family:monospace;font-size:12px;padding:8px;border:1px dashed var(--line);border-radius:8px}.at-wd{display:flex;flex-wrap:wrap;gap:6px}.at-wd label{display:flex;gap:4px;align-items:center;min-height:40px}
.at-num{font-variant-numeric:tabular-nums}`;
if (!document.getElementById('attcss')) document.head.appendChild(css);
const tabs = (list, cur, act) => `<div class="ptabs" role="tablist">${list.map(([k, l]) => `<button role="tab" data-act="${act}" data-v="${k}" aria-selected="${cur === k}">${esc(T(l))}</button>`).join('')}</div>`;

// ---------------- today board ----------------
async function boardHTML() {
  const appOn = B.rule ? B.rule('app_punch_on', false) === true : false;
  const punchBtns = appOn ? `<button class="full" data-act="at_punch" data-v="in">${esc(T('checkIn'))}</button><button class="full" data-act="at_punch" data-v="out">${esc(T('checkOut'))}</button>` : '';
  const r = await sb.rpc('attendance_board', { p_loc: D.loc, p_day: D.day });
  if (r.error) return `${punchBtns ? `<div class="row">${punchBtns}</div>` : ''}<p class="muted">${esc(eText(r.error))}</p>`;   // staff without the board right may still check in
  D.board = r.data || { rows: [], counts: {} }; const c = D.board.counts || {};
  const mg = await can('attendance_manage');
  const sum = `<div class="at-sum"><span class="chip ok">${esc(T('present'))} ${c.present || 0}</span><span class="chip warn">${esc(T('late'))} ${c.late || 0}</span><span class="chip bad">${esc(T('absent'))} ${c.absent || 0}</span>
    <span class="chip info">${esc(T('leave'))} ${c.leave || 0}</span><span class="chip">${esc(T('off'))} ${c.off || 0}</span>${c.pending ? `<span class="chip warn">${esc(T('pending'))} ${c.pending}</span>` : ''}</div>`;
  const rows = (D.board.rows || []).map((x) => `<div class="card at-row" data-emp="${esc(x.employee_id)}"><div class="nm"><b>${esc(empName(x))}</b> <span class="muted">${esc(x.employee_no || '')}</span>
      <div class="muted at-num">${x.first_in ? esc(T('inT')) + ' ' + esc(hm(x.first_in)) : ''}${x.last_out ? ' · ' + esc(T('outT')) + ' ' + esc(hm(x.last_out)) : ''}${x.late_minutes ? ' · ' + esc(mins(x.late_minutes)) + ' ' + esc(T('lateM')) : ''}${x.ot_minutes ? ' · ' + esc(T('ot')) + ' ' + esc(mins(x.ot_minutes)) + (x.ot_approved ? ' ✓' : '') : ''}${x.single_punch ? ' · ' + esc(T('single')) : ''}${x.source === 'manual' ? ' · ' + esc(T('manual')) : ''}</div></div>
      <span class="chip ${stCls(x.status)}">${esc(T(x.status || 'absent'))}</span>${x.pending ? `<span class="chip warn">${esc(T('pending'))}</span>` : ''}<button class="mini" data-act="at_menu" data-v="${esc(x.employee_id)}" aria-label="⋮">⋮</button></div>`).join('');
  return `${sum}<div class="row">${mg ? `<button class="full" data-act="at_recompute">${esc(T('recompute'))}</button>` : ''}${punchBtns}</div>
    <div id="at_rows">${rows || `<p class="muted">${esc(T('none'))}</p>`}</div>`;
}
function rowOf(id) { return ((D.board && D.board.rows) || []).find((x) => x.employee_id === id) || {}; }
function markSheet(id) {
  const x = rowOf(id);
  openSheet(`<h3>${esc(T('mark'))}: ${esc(empName(x))}</h3><div class="stack">
    <div><label for="mk_s">${esc(T('status'))}</label><select id="mk_s">${STATUS.map((s) => `<option value="${s}" ${s === x.status ? 'selected' : ''}>${esc(T(s))}</option>`).join('')}</select></div>
    <div class="row"><div><label for="mk_in">${esc(T('inT'))}</label><input id="mk_in" type="time" value="${esc(hm(x.first_in))}"></div><div><label for="mk_out">${esc(T('outT'))}</label><input id="mk_out" type="time" value="${esc(hm(x.last_out))}"></div></div>
    <div><label for="mk_ot">${esc(T('otMin'))}</label><input id="mk_ot" inputmode="numeric" autocomplete="off"></div>
    <div><label for="mk_r">${esc(T('reason'))}</label><input id="mk_r" autocomplete="off"></div>
    <div><label for="mk_n">${esc(T('note'))}</label><input id="mk_n" autocomplete="off"></div>
    <button class="primary full" data-act="mk_save" data-v="${esc(id)}">${esc(T('save'))}</button></div>`);
}
function menuSheet(id) {
  const x = rowOf(id); const mg = D.can['attendance_manage|' + D.loc] || S.ctx.is_owner;
  openSheet(`<h3>${esc(empName(x))} <span class="muted">${esc(x.employee_no || '')}</span></h3><div class="stack">
    ${mg ? `<button class="full" data-act="at_mark" data-v="${esc(id)}">${esc(T('mark'))}</button>` : ''}
    ${mg && x.pending ? `<button class="full primary" data-act="at_appr" data-v="${esc(id)}" data-ok="1">${esc(T('approve'))}</button><button class="full" data-act="at_appr" data-v="${esc(id)}" data-ok="0">${esc(T('reject'))}</button>` : ''}
    ${mg && x.ot_minutes > 0 && !x.ot_approved ? `<button class="full" data-act="at_ot" data-v="${esc(id)}">${esc(T('otApprove'))} (${esc(mins(x.ot_minutes))})</button>` : ''}
    ${x.reason ? `<p class="muted">${esc(T('reason'))}: ${esc(x.reason)}</p>` : ''}
    <button class="full" data-act="at_monthof" data-v="${esc(id)}">${esc(T('monthOf'))}</button></div>`);
}

// ---------------- month grid ----------------
async function monthHTML() {
  if (!D.emps.length) await loadEmps();
  if (!D.emp && D.emps[0]) D.emp = D.emps[0].id;
  const sel = `<div class="at-pick"><div><label for="at_emp">${esc(T('who'))}</label><select id="at_emp">${D.emps.map((e) => `<option value="${esc(e.id)}" ${e.id === D.emp ? 'selected' : ''}>${esc(empName(e))} ${esc(e.employee_no || '')}</option>`).join('')}</select></div>
    <div><label for="at_month">${esc(T('month'))}</label><input id="at_month" type="month" value="${esc(D.month)}" max="${esc(today().slice(0, 7))}"></div></div>`;
  if (!D.emp) return sel + `<p class="muted">${esc(T('none'))}</p>`;
  const r = await sb.rpc('attendance_month', { p_emp: D.emp, p_month: D.month + '-01' });
  if (r.error) return sel + `<p class="muted">${esc(eText(r.error))}</p>`;
  D.grid = r.data || { days: [] }; const days = D.grid.days || [];
  const cnt = (s) => days.filter((d) => d.status === s).length;
  const first = new Date(D.month + '-01T00:00:00Z').getUTCDay();
  const cells = WD.map((w) => `<div class="h">${esc(T(w))}</div>`).join('') + '<div></div>'.repeat(first) + days.map((d) => `<div class="c ${stCls(d.status)}" title="${esc(d.status ? T(d.status) : '')}"><b>${esc(String(d.day).slice(8, 10))}</b><br>${d.status ? esc(T(d.status)).slice(0, 8) : '·'}${d.ot_minutes ? '<br>+' + esc(mins(d.ot_minutes)) : ''}</div>`).join('');
  return sel + `${D.grid.locked ? `<p class="chip warn">${esc(T('locked'))}</p>` : ''}<div class="at-sum"><span class="chip ok">${esc(T('present'))} ${cnt('present') + cnt('late')}</span><span class="chip warn">${esc(T('late'))} ${cnt('late')}</span>
    <span class="chip bad">${esc(T('absent'))} ${cnt('absent')}</span><span class="chip info">${esc(T('leave'))} ${cnt('leave')}</span><span class="chip">${esc(T('half_day'))} ${cnt('half_day')}</span></div><div class="at-grid" id="at_grid">${cells}</div>`;
}

// ---------------- device file import ----------------
const pad = (n) => String(n).padStart(2, '0');
function normTs(s) {
  s = String(s || '').trim(); let m;
  if ((m = s.match(/^(\d{4})[-/](\d{1,2})[-/](\d{1,2})[ T](\d{1,2}):(\d{2})(?::(\d{2}))?/))) return `${m[1]}-${pad(m[2])}-${pad(m[3])} ${pad(m[4])}:${m[5]}:${m[6] || '00'}`;
  if ((m = s.match(/^(\d{1,2})[-/](\d{1,2})[-/](\d{4})[ T](\d{1,2}):(\d{2})(?::(\d{2}))?/))) return `${m[3]}-${pad(m[2])}-${pad(m[1])} ${pad(m[4])}:${m[5]}:${m[6] || '00'}`;
  return null;
}
function splitCsv(line, sep) { const out = []; let cur = '', q = false; for (const ch of line) { if (ch === '"') q = !q; else if (ch === sep && !q) { out.push(cur); cur = ''; } else cur += ch; } out.push(cur); return out.map((x) => x.trim()); }
function parseFile(text) {
  const lines = String(text || '').replace(/^﻿/, '').split(/\r?\n/).filter((l) => l.trim());
  if (!lines.length) return { rows: [], bad: 0, csv: null };
  const first = lines[0]; const sep = first.includes(',') ? ',' : first.includes(';') ? ';' : null;
  if (sep && !/^\s*\d/.test(first)) {
    const head = splitCsv(first, sep); const body = lines.slice(1).map((l) => splitCsv(l, sep));
    const find = (names) => { const i = head.findIndex((h) => names.includes(h.toLowerCase())); return i; };
    const map = { u: find(['user_id', 'uid', 'userid', 'user id', 'ac-no.', 'ac-no', 'id', 'pin', 'enroll id']), t: find(['ts', 'datetime', 'date time', 'date/time', 'time', 'punch time', 'checktime']), d: find(['dir', 'direction', 'state', 'status', 'in/out']) };
    return mapCsv({ head, body, map });
  }
  const rows = []; let bad = 0;
  lines.forEach((l) => { let p = l.includes('\t') ? l.split('\t').map((x) => x.trim()) : l.trim().split(/\s+/); if (!l.includes('\t') && p.length >= 3) p = [p[0], p[1] + ' ' + p[2], ...p.slice(3)];
    const ts = normTs(p[1]); if (!p[0] || !ts) { bad++; return; } const r = { user_id: p[0], ts }; if (p[3] !== undefined && p[3] !== '') r.dir = p[3]; if (p[2]) r.verify = p[2]; if (p[4]) r.workcode = p[4]; rows.push(r); });
  return { rows, bad, csv: null };
}
function mapCsv(csv) {
  const rows = []; let bad = 0; const { u, t, d } = csv.map;
  csv.body.forEach((c) => { const ts = t >= 0 ? normTs(c[t]) : null; const uid = u >= 0 ? (c[u] || '').trim() : ''; if (!uid || !ts) { bad++; return; } const r = { user_id: uid, ts }; if (d >= 0 && c[d]) r.dir = c[d]; rows.push(r); });
  return { rows, bad, csv };
}
async function importHTML() {
  const mg = await can('attendance_manage');
  if (!mg) return `<p class="muted">${esc(lab(ERR['not allowed']))}</p>`;
  const [dv, bt] = await Promise.all([sb.from('attendance_devices').select('id,name,location_id,vendor,serial,active,last_seen,pushed_rows').eq('location_id', D.loc).order('id'),
    sb.from('attendance_import_batches').select('*').eq('location_id', D.loc).order('created_at', { ascending: false }).limit(20)]);
  D.devices = dv.data || []; D.batches = bt.data || [];
  const unm = await sb.rpc('attendance_unmapped', { p_loc: D.loc }); D.unm = unm.error ? [] : unm.data || [];
  if (!D.emps.length) await loadEmps();
  const im = D.imp; const csv = im && im.csv;
  const colSel = (id, k) => `<select id="${id}"><option value="-1">-</option>${csv.head.map((h, i) => `<option value="${i}" ${csv.map[k] === i ? 'selected' : ''}>${esc(h)}</option>`).join('')}</select>`;
  const pv = D.prev;
  const prevBox = pv ? `<div class="card" id="im_prev"><div class="at-sum"><span class="chip">${esc(T('read'))} ${pv.total}</span><span class="chip ok">${esc(T('pNew'))} ${pv.new}</span>
      <span class="chip">${esc(T('pDup'))} ${(pv.already_in || 0) + (pv.duplicates_in_file || 0)}</span><span class="chip bad">${esc(T('pBad'))} ${pv.rejected}</span><span class="chip warn">${esc(T('pUnm'))} ${pv.unmapped}</span><span class="chip info">${esc(T('pPeople'))} ${pv.employees}</span></div>
      ${pv.from ? `<p class="muted">${esc(T('range'))}: ${esc(dhm(pv.from))} – ${esc(dhm(pv.to))}</p>` : ''}${(pv.unmapped_ids || []).length ? `<p class="muted">${esc(T('pUnm'))}: ${esc((pv.unmapped_ids || []).slice(0, 30).join(', '))}</p>` : ''}
      <button class="primary full" data-act="im_go" ${pv.new > 0 ? '' : 'disabled'}>${esc(T('doImport'))} (${pv.new})</button></div>` : '';
  const batches = D.batches.length ? D.batches.map((b) => `<div class="card at-row ${b.status === 'void' ? 'muted' : ''}"><div class="nm">${esc(b.file_name || '-')} <span class="muted">${esc(dhm(b.created_at))}</span><div class="muted">${esc(T('pNew'))} ${b.rows_new} · ${esc(T('pDup'))} ${b.rows_dup} · ${esc(T('pUnm'))} ${b.rows_unmapped}${b.status === 'void' ? ' · ' + esc(T('undone')) : ''}</div></div>
      ${b.status === 'active' ? `<button class="mini" data-act="im_undo" data-v="${esc(b.id)}">${esc(T('undo'))}</button>` : ''}</div>`).join('') : `<p class="muted">${esc(T('nothing'))}</p>`;
  const free = D.emps.filter((e) => !e.device_user_id);
  const unmap = D.unm.length ? D.unm.map((u, i) => `<div class="card"><div class="at-row"><b class="nm">ID ${esc(u.device_user_id)}</b><span class="muted">${u.punches} ${esc(T('punches'))} · ${esc(u.device_name || '')}</span></div>
      <div class="row"><select id="um_e${i}" aria-label="${esc(T('who'))}"><option value="">${esc(T('pick'))}</option>${free.map((e) => `<option value="${esc(e.id)}">${esc(empName(e))} ${esc(e.employee_no || '')}</option>`).join('')}</select>
      <button class="mini" data-act="um_link" data-i="${i}">${esc(T('link'))}</button></div></div>`).join('') : `<p class="muted">${esc(T('nothing'))}</p>`;
  return `<div class="card stack"><div><label for="im_file">${esc(T('file'))}</label><input id="im_file" type="file" accept=".dat,.txt,.csv,text/plain,text/csv"></div>
      <div><label for="im_paste">${esc(T('paste'))}</label><textarea id="im_paste" rows="3"></textarea></div>
      <div><label for="im_dev">${esc(T('device'))}</label><select id="im_dev"><option value="">${esc(T('noDevice'))}</option>${D.devices.map((d) => `<option value="${d.id}">${esc(d.name)}</option>`).join('')}</select></div>
      ${csv ? `<div class="row"><div><label for="im_cu">${esc(T('colUser'))}</label>${colSel('im_cu', 'u')}</div><div><label for="im_ct">${esc(T('colTs'))}</label>${colSel('im_ct', 't')}</div><div><label for="im_cd">${esc(T('colDir'))}</label>${colSel('im_cd', 'd')}</div></div>` : ''}
      ${im ? `<p class="muted" id="im_read">${esc(T('read'))}: ${im.rows.length}${im.bad ? ' · ' + esc(T('pBad')) + ' ' + im.bad : ''}</p>` : ''}
      <button class="full" data-act="im_prev" ${im && im.rows.length ? '' : 'disabled'}>${esc(T('preview'))}</button></div>${prevBox}
    <h3>${esc(T('unmapped'))}</h3><div id="um_list">${unmap}</div><h3>${esc(T('batches'))}</h3><div id="im_batches">${batches}</div>`;
}
async function devicesHTML() {
  const r = await sb.from('attendance_devices').select('id,name,location_id,vendor,serial,active,last_seen,pushed_rows').eq('location_id', D.loc).order('id');
  D.devices = r.data || [];
  const own = !!S.ctx.is_owner;
  const list = D.devices.length ? D.devices.map((d) => `<div class="card at-row"><div class="nm"><b>${esc(d.name)}</b> <span class="muted">${esc(d.vendor)} ${esc(d.serial || '')}</span>
      <div class="muted">${esc(T('lastSeen'))}: ${d.last_seen ? esc(dhm(d.last_seen)) : esc(T('never'))} · ${d.pushed_rows || 0} ${esc(T('rows'))}</div></div>
      <span class="chip ${d.active ? 'ok' : ''}">${esc(T(d.active ? 'on' : 'offS'))}</span>${own ? `<button class="mini" data-act="dv_menu" data-v="${d.id}" aria-label="⋮">⋮</button>` : ''}</div>`).join('') : `<p class="muted">${esc(T('nothing'))}</p>`;
  return `${own ? `<button class="full primary" data-act="dv_new">${esc(T('register'))}</button>` : ''}<div id="dv_list">${list}</div>`;
}
function tokenSheet(tok, name) {
  const cmd = `SUPABASE_URL=<url> SUPABASE_ANON_KEY=<anon key> DEVICE_TOKEN=${tok} python3 tools/fingerprint_bridge.py --zk 192.168.1.201`;
  openSheet(`<h3>${esc(name || '')}</h3><p>${esc(T('token'))}</p><div class="at-tok" id="dv_tok">${esc(tok)}</div><button class="full" data-act="dv_copy">${esc(T('copy'))}</button>
    <p class="muted">${esc(T('bridge'))}</p><div class="at-tok">${esc(cmd)}</div>`);
  D.tok = tok;
}

// ---------------- shifts, roster, holidays ----------------
async function setupHTML() {
  const y = today().slice(0, 4);
  const [s, h] = await Promise.all([sb.from('shifts').select('*').order('id'), sb.from('holidays').select('*').gte('day', y + '-01-01').order('day')]);
  D.shifts = (s.data || []).filter((x) => x.active && (x.location_id == null || x.location_id === D.loc));
  D.hols = (h.data || []).filter((x) => x.active && (x.location_id == null || x.location_id === D.loc));
  const mg = await can('attendance_manage');
  const sh = D.shifts.map((x) => `<div class="card at-row"><div class="nm"><b>${esc(S.lang === 'en' && x.name_en ? x.name_en : x.name_bn)}</b> <span class="muted at-num">${esc(String(x.start_time).slice(0, 5))}–${esc(String(x.end_time).slice(0, 5))}${x.crosses_midnight ? ' (' + esc(T('night')) + ')' : ''}</span>
      <div class="muted">${esc(T('grace'))} ${x.grace_late_min} · ${esc(T('brk'))} ${x.break_min}${x.is_default ? ' · ' + esc(T('dflt')) : ''}${x.location_id == null ? ' · ' + esc(T('allPlaces')) : ''}</div></div>
      ${mg && (x.location_id != null || S.ctx.is_owner) ? `<button class="mini" data-act="sh_edit" data-v="${x.id}">✎</button>` : ''}</div>`).join('');
  const hol = D.hols.length ? D.hols.map((x) => `<div class="card at-row"><div class="nm"><b>${esc(x.day)}</b> ${esc(S.lang === 'en' && x.name_en ? x.name_en : x.name_bn)} ${x.paid ? `<span class="chip ok">${esc(T('paid'))}</span>` : `<span class="chip">${esc(T('unpaid'))}</span>`}</div>
      ${mg && (x.location_id != null || S.ctx.is_owner) ? `<button class="mini" data-act="hol_del" data-v="${x.id}">${esc(T('remove'))}</button>` : ''}</div>`).join('') : `<p class="muted">${esc(T('nothing'))}</p>`;
  return `<h3>${esc(T('shifts'))}</h3>${sh}${mg ? `<div class="row"><button class="full" data-act="sh_edit" data-v="">${esc(T('addShift'))}</button><button class="full" data-act="sh_assign">${esc(T('assign'))}</button></div>` : ''}
    <h3>${esc(T('holidays'))} ${esc(y)}</h3>${hol}${mg ? `<button class="full" data-act="hol_add">${esc(T('addHol'))}</button>` : ''}`;
}
function shiftSheet(x) {
  x = x || { name_bn: '', start_time: '09:00', end_time: '18:00', grace_late_min: 10, grace_early_min: 10, break_min: 60, min_hours_full_day: 7, min_hours_half_day: 4, is_default: false, location_id: D.loc };
  const f = (id, l, v, t = 'text') => `<div><label for="${id}">${esc(T(l))}</label><input id="${id}" type="${t}" value="${esc(v)}" ${t === 'text' ? 'autocomplete="off"' : ''}></div>`;
  openSheet(`<h3>${esc(T('shifts'))}</h3><div class="stack">${f('sh_bn', 'hName', x.name_bn)}${f('sh_en', 'hNameEn', x.name_en || '')}<div class="row">${f('sh_st', 'start', String(x.start_time).slice(0, 5), 'time')}${f('sh_et', 'end', String(x.end_time).slice(0, 5), 'time')}</div>
    <div class="row">${f('sh_g', 'grace', x.grace_late_min, 'number')}${f('sh_ge', 'graceE', x.grace_early_min, 'number')}${f('sh_b', 'brk', x.break_min, 'number')}</div><div class="row">${f('sh_f', 'full', x.min_hours_full_day, 'number')}${f('sh_h', 'half', x.min_hours_half_day, 'number')}</div>
    <label class="row"><input type="checkbox" id="sh_d" ${x.is_default ? 'checked' : ''}> ${esc(T('dflt'))}</label>
    <button class="primary full" data-act="sh_save" data-v="${x.id || ''}">${esc(T('save'))}</button></div>`);
}
const wdBoxes = (cls, on) => `<div class="at-wd">${WD.map((w, i) => `<label><input type="checkbox" class="${cls}" value="${i}" ${on(i) ? 'checked' : ''}>${esc(T(w))}</label>`).join('')}</div>`;
async function assignSheet() {
  if (!D.emps.length) await loadEmps();
  openSheet(`<h3>${esc(T('assign'))}</h3><div class="stack"><div><label for="as_e">${esc(T('who'))}</label><select id="as_e">${D.emps.map((e) => `<option value="${esc(e.id)}">${esc(empName(e))} ${esc(e.employee_no || '')}</option>`).join('')}</select></div>
    <div><label for="as_s">${esc(T('shifts'))}</label><select id="as_s">${D.shifts.map((s) => `<option value="${s.id}">${esc(s.name_bn)} ${esc(String(s.start_time).slice(0, 5))}–${esc(String(s.end_time).slice(0, 5))}</option>`).join('')}</select></div>
    <div class="row"><div><label for="as_f">${esc(T('from'))}</label><input id="as_f" type="date" value="${today()}"></div><div><label for="as_t">${esc(T('to'))}</label><input id="as_t" type="date"></div></div>
    <div>${esc(T('days'))}${wdBoxes('as_wd', () => true)}</div><div>${esc(T('offDays'))}${wdBoxes('as_off', () => false)}</div>
    <button class="primary full" data-act="shf_save">${esc(T('save'))}</button></div>`);
}

// ---------------- page ----------------
async function draw() {
  const el = $('#at_body'); if (!el) return;
  el.innerHTML = `<p class="muted">…</p>`;
  let body = '';
  try {
    if (D.tab === 'today') body = await boardHTML(); else if (D.tab === 'month') body = await monthHTML(); else if (D.tab === 'import') body = await importHTML();
    else if (D.tab === 'devices') body = await devicesHTML(); else body = await setupHTML();
  } catch (e) { body = `<p class="muted">${esc(eText(e))}</p>`; }
  if ($('#at_body')) $('#at_body').innerHTML = body;
}
async function view() {
  if (B.loadStatic) await B.loadStatic();
  const locs = LOCS(); if (!D.loc || !locs.find((l) => l.id === D.loc)) D.loc = (locs[0] || {}).id;
  const t = [['today', 'tToday'], ['month', 'tMonth'], ['import', 'tImport'], ['devices', 'tDevices'], ['setup', 'tSetup']];
  shell(T('title'), `<div class="row"><div>${locSel('at_loc')}</div><div><input id="at_day" type="date" value="${esc(D.day)}" max="${today()}" aria-label="${esc(T('date'))}"></div></div>
    ${tabs(t, D.tab, 'at_tab')}<div id="at_body"></div>`, true);
  try { await draw(); } catch (e) { fail(e); }
}

// ---------------- leave page ----------------
async function leaveView() {
  if (B.loadStatic) await B.loadStatic();
  const locs = LOCS(); if (!D.loc || !locs.find((l) => l.id === D.loc)) D.loc = (locs[0] || {}).id;
  shell(T('leaveT'), `<div class="row"><div>${locSel('lv_loc')}</div></div>${tabs([['req', 'tReq'], ['bal', 'tBal']], LV.tab, 'lv_tab')}<div id="lv_body"><p class="muted">…</p></div>`, true);
  try { await drawLeave(); } catch (e) { fail(e); }
}
const lvL = (s) => T({ pending: 'lPending', approved: 'lApproved', rejected: 'lRejected', cancelled: 'lCancelled' }[s] || 'lPending');
const lvC = (s) => ({ pending: 'warn', approved: 'ok', rejected: 'bad', cancelled: '' }[s] || '');
const typeName = (code) => { const t = LV.types.find((x) => x.code === code); return t ? (S.lang === 'en' ? t.name_en : t.name_bn) : code; };
async function drawLeave() {
  const el = $('#lv_body'); if (!el) return;
  await loadEmps();
  if (!LV.types.length) { const t = await sb.from('leave_types').select('code,name_bn,name_en,paid,active,sort').order('sort'); LV.types = (t.data || []).filter((x) => x.active !== false); }
  const mg = await can('attendance_manage');
  if (LV.tab === 'req') {
    const r = await sb.from('leave_requests').select('*').order('from_date', { ascending: false }).limit(200);
    const ids = new Set(D.emps.map((e) => e.id));
    LV.reqs = (r.data || []).filter((x) => ids.has(x.employee_id)).sort((a, b) => (a.status === 'pending' ? 0 : 1) - (b.status === 'pending' ? 0 : 1));
    const en = (id) => empName(D.emps.find((e) => e.id === id) || {});
    const rows = LV.reqs.length ? LV.reqs.map((x) => `<div class="card" data-lr="${x.id}"><div class="at-row"><b class="nm">${esc(en(x.employee_id))}</b><span class="chip ${lvC(x.status)}">${esc(lvL(x.status))}</span></div>
        <div class="muted">${esc(typeName(x.leave_type))} · ${esc(x.from_date)}${x.to_date !== x.from_date ? ' – ' + esc(x.to_date) : ''} · ${esc(x.days)} ${esc(T('dayCount'))}${x.reason ? ' · ' + esc(x.reason) : ''}${x.decision_note ? ' · ' + esc(x.decision_note) : ''}</div>
        <div class="row">${mg && x.status === 'pending' ? `<button class="mini" data-act="lv_dec" data-v="${x.id}" data-ok="1">${esc(T('approve'))}</button><button class="mini" data-act="lv_dec" data-v="${x.id}" data-ok="0">${esc(T('reject'))}</button>` : ''}
        ${x.status === 'pending' || (mg && x.status === 'approved') ? `<button class="mini" data-act="lv_cancel" data-v="${x.id}">${esc(T('cancelL'))}</button>` : ''}</div></div>`).join('') : `<p class="muted">${esc(T('nothing'))}</p>`;
    el.innerHTML = `${mg || D.emps.some((e) => e.profile_id && S.ctx.profile && e.profile_id === S.ctx.profile.id) ? `<button class="full primary" data-act="lv_new">${esc(T('newReq'))}</button>` : ''}<div id="lv_list">${rows}</div>`;
    return;
  }
  if (!LV.emp && D.emps[0]) LV.emp = D.emps[0].id;
  let tbl = `<p class="muted">${esc(T('none'))}</p>`;
  if (LV.emp) {
    const b = await sb.rpc('leave_balances', { p_emp: LV.emp, p_year: LV.year });
    LV.bal = b.error ? null : b.data || [];
    tbl = b.error ? `<p class="muted">${esc(eText(b.error))}</p>` : `<div id="lv_bal">${LV.bal.map((x) => `<div class="card at-row"><div class="nm"><b>${esc(S.lang === 'en' ? x.name_en : x.name_bn)}</b><div class="muted at-num">${esc(T('entitled'))} ${esc(x.entitled)} · ${esc(T('taken'))} ${esc(x.taken)}${Number(x.pending) ? ' · ' + esc(T('lPending')) + ' ' + esc(x.pending) : ''}</div></div>
      <b class="at-num">${x.remaining == null ? esc(T('noLimit')) : esc(T('remaining')) + ' ' + esc(x.remaining)}</b></div>`).join('')}</div>`;
  }
  el.innerHTML = `<div class="row"><div><label for="lv_emp">${esc(T('who'))}</label><select id="lv_emp">${D.emps.map((e) => `<option value="${esc(e.id)}" ${e.id === LV.emp ? 'selected' : ''}>${esc(empName(e))}</option>`).join('')}</select></div>
    <div><label for="lv_year">${esc(T('year'))}</label><input id="lv_year" type="number" value="${LV.year}"></div></div>${tbl}`;
}
function leaveSheet() {
  const mine = D.emps.filter((e) => S.ctx.is_owner || D.can['attendance_manage|' + D.loc] || (e.profile_id && S.ctx.profile && e.profile_id === S.ctx.profile.id));
  openSheet(`<h3>${esc(T('newReq'))}</h3><div class="stack"><div><label for="lr_e">${esc(T('who'))}</label><select id="lr_e">${mine.map((e) => `<option value="${esc(e.id)}">${esc(empName(e))} ${esc(e.employee_no || '')}</option>`).join('')}</select></div>
    <div><label for="lr_t">${esc(T('type'))}</label><select id="lr_t">${LV.types.map((t) => `<option value="${esc(t.code)}">${esc(S.lang === 'en' ? t.name_en : t.name_bn)}</option>`).join('')}</select></div>
    <div class="row"><div><label for="lr_f">${esc(T('from'))}</label><input id="lr_f" type="date" value="${today()}"></div><div><label for="lr_to">${esc(T('end'))}</label><input id="lr_to" type="date" value="${today()}"></div></div>
    <div><label for="lr_r">${esc(T('lReason'))}</label><input id="lr_r" autocomplete="off"></div><button class="primary full" data-act="lr_save">${esc(T('save'))}</button></div>`);
  D.lrClient = rid();
}

const val = (id) => (($('#' + id) || {}).value || '').trim();
const ask = (k) => { const n = window.prompt(T(k || 'why')); return n && n.trim().length >= 3 ? n.trim() : null; };
async function rpc(fn, args, ok) { const r = await sb.rpc(fn, args); if (r.error) { toast(eText(r.error)); return null; } if (ok) toast(T(ok)); return r.data; }
Object.assign(H, {
  at_tab: (a) => { D.tab = a.dataset.v; D.prev = null; $$('[data-act=at_tab]').forEach((b) => b.setAttribute('aria-selected', String(b.dataset.v === D.tab))); draw(); },
  at_recompute: async () => { const d = await rpc('attendance_recompute', { p_from: D.day, p_to: D.day, p_employee: null }, 'recomputed'); if (d) draw(); },
  at_punch: async (a) => { const d = await rpc('attendance_app_punch', { p_dir: a.dataset.v }, 'punched'); if (d) draw(); },
  at_menu: (a) => menuSheet(a.dataset.v),
  at_mark: (a) => markSheet(a.dataset.v),
  mk_save: async (a) => { const r = val('mk_r'); if (r.length < 3) return toast(lab(ERR.reason_required)); const ot = val('mk_ot');
    const d = await rpc('attendance_mark', { p_emp: a.dataset.v, p_day: D.day, p_status: val('mk_s'), p_in: val('mk_in') || null, p_out: val('mk_out') || null, p_ot_minutes: ot === '' ? null : Number(ot), p_reason: r, p_note: val('mk_n') || null }, 'saved');
    if (d) { closeSheet(); draw(); } },
  at_appr: async (a) => { const ok = a.dataset.ok === '1'; const note = ok ? null : ask(); if (!ok && !note) return;
    const d = await rpc('attendance_approve', { p_emp: a.dataset.v, p_day: D.day, p_approve: ok, p_note: note }, 'saved'); if (d) { closeSheet(); draw(); } },
  at_ot: async (a) => { const d = await rpc('attendance_ot_approve', { p_emp: a.dataset.v, p_day: D.day, p_ok: true }, 'saved'); if (d) { closeSheet(); draw(); } },
  at_monthof: (a) => { closeSheet(); D.emp = a.dataset.v; D.month = D.day.slice(0, 7); H.at_tab({ dataset: { v: 'month' } }); },
  im_prev: async () => { if (!D.imp || !D.imp.rows.length) return; if (D.imp.rows.length > 5000) return toast(lab(ERR.too_many_rows));
    const r = await sb.rpc('attendance_import', { p_loc: D.loc, p_device: val('im_dev') ? Number(val('im_dev')) : null, p_rows: D.imp.rows, p_file: D.impName || 'paste', p_dry: true, p_client: null });
    if (r.error) return toast(eText(r.error)); D.prev = r.data; D.impDev = val('im_dev'); await draw(); if ($('#im_dev')) $('#im_dev').value = D.impDev || ''; },
  im_go: async () => { const r = await sb.rpc('attendance_import', { p_loc: D.loc, p_device: D.impDev ? Number(D.impDev) : null, p_rows: D.imp.rows, p_file: D.impName || 'paste', p_dry: false, p_client: D.client });
    if (r.error) return toast(eText(r.error)); D.client = rid(); D.imp = null; D.prev = null; toast(T('saved') + ' · ' + T('pNew') + ' ' + (r.data.new || 0)); draw(); },
  im_undo: async (a) => { const n = ask(); if (!n) return; const d = await rpc('attendance_import_void', { p_batch: a.dataset.v, p_reason: n }, 'undone'); if (d) draw(); },
  um_link: async (a) => { const u = D.unm[Number(a.dataset.i)]; const e = val('um_e' + a.dataset.i); if (!u || !e) return toast(T('pick'));
    const d = await rpc('attendance_map_user', { p_device_user_id: u.device_user_id, p_emp: e }, 'linked'); if (d) { D.emps = []; draw(); } },
  dv_new: () => openSheet(`<h3>${esc(T('register'))}</h3><div class="stack"><div><label for="dv_n">${esc(T('dName'))}</label><input id="dv_n" autocomplete="off"></div>
      <div><label for="dv_v">${esc(T('vendor'))}</label><select id="dv_v">${['zkteco', 'hikvision', 'suprema', 'other'].map((v) => `<option value="${v}">${v}</option>`).join('')}</select></div>
      <div><label for="dv_s">${esc(T('serial'))}</label><input id="dv_s" autocomplete="off"></div><button class="primary full" data-act="dv_save">${esc(T('save'))}</button></div>`),
  dv_save: async () => { const n = val('dv_n'); if (!n) return toast(lab(ERR.name_required)); const d = await rpc('attendance_device_register', { p_name: n, p_loc: D.loc, p_vendor: val('dv_v'), p_serial: val('dv_s') || null });
    if (d) { tokenSheet(d.token, n); draw(); } },
  dv_menu: (a) => { const d = D.devices.find((x) => x.id === Number(a.dataset.v)); if (!d) return;
    openSheet(`<h3>${esc(d.name)}</h3><div class="stack"><button class="full" data-act="dv_reset" data-v="${d.id}">${esc(T('reset'))}</button><button class="full" data-act="dv_onoff" data-v="${d.id}" data-on="${d.active ? 0 : 1}">${esc(T(d.active ? 'offS' : 'on'))}</button></div>`); },
  dv_reset: async (a) => { const d = await rpc('attendance_device_token_reset', { p_id: Number(a.dataset.v) }); if (d) tokenSheet(d.token, (D.devices.find((x) => x.id === Number(a.dataset.v)) || {}).name); },
  dv_onoff: async (a) => { const d = await rpc('attendance_device_set_active', { p_id: Number(a.dataset.v), p_active: a.dataset.on === '1' }, 'saved'); if (d) { closeSheet(); draw(); } },
  dv_copy: async () => { try { await navigator.clipboard.writeText(D.tok || ''); } catch (e) { /* select by hand */ } toast(T('copied')); },
  sh_edit: (a) => shiftSheet(D.shifts.find((x) => String(x.id) === a.dataset.v)),
  sh_save: async (a) => { const data = { name_bn: val('sh_bn'), name_en: val('sh_en') || null, start_time: val('sh_st'), end_time: val('sh_et'), grace_late_min: Number(val('sh_g')), grace_early_min: Number(val('sh_ge')),
      break_min: Number(val('sh_b')), min_hours_full_day: Number(val('sh_f')), min_hours_half_day: Number(val('sh_h')), is_default: !!($('#sh_d') || {}).checked };
    if (!a.dataset.v) data.location_id = D.loc;
    const d = await rpc('shift_save', { p_id: a.dataset.v ? Number(a.dataset.v) : null, p_data: data }, 'saved'); if (d) { closeSheet(); draw(); } },
  sh_assign: () => assignSheet(),
  shf_save: async () => { const m = (cls) => $$('.' + cls).reduce((s, b) => s | (b.checked ? 1 << Number(b.value) : 0), 0); const off = m('as_off');
    const d = await rpc('shift_assign', { p_emp: val('as_e'), p_shift: Number(val('as_s')), p_from: val('as_f'), p_to: val('as_t') || null, p_weekdays: m('as_wd'), p_off_mask: off || null, p_client: rid() }, 'saved'); if (d) closeSheet(); },
  hol_add: () => openSheet(`<h3>${esc(T('addHol'))}</h3><div class="stack"><div><label for="ho_d">${esc(T('date'))}</label><input id="ho_d" type="date"></div><div><label for="ho_bn">${esc(T('hName'))}</label><input id="ho_bn" autocomplete="off"></div>
      <div><label for="ho_en">${esc(T('hNameEn'))}</label><input id="ho_en" autocomplete="off"></div>${S.ctx.is_owner ? `<label class="row"><input type="checkbox" id="ho_all"> ${esc(T('allPlaces'))}</label>` : ''}
      <label class="row"><input type="checkbox" id="ho_p" checked> ${esc(T('paid'))}</label><button class="primary full" data-act="ho_save">${esc(T('save'))}</button></div>`),
  ho_save: async () => { const d = await rpc('holiday_save', { p_day: val('ho_d') || null, p_loc: ($('#ho_all') || {}).checked ? null : D.loc, p_name_bn: val('ho_bn'), p_name_en: val('ho_en') || null, p_paid: !!($('#ho_p') || {}).checked }, 'saved'); if (d) { closeSheet(); draw(); } },
  hol_del: async (a) => { const d = await rpc('holiday_retire', { p_id: Number(a.dataset.v) }, 'saved'); if (d) draw(); },
  lv_tab: (a) => { LV.tab = a.dataset.v; $$('[data-act=lv_tab]').forEach((b) => b.setAttribute('aria-selected', String(b.dataset.v === LV.tab))); drawLeave(); },
  lv_new: () => leaveSheet(),
  lr_save: async () => { const d = await rpc('leave_request_save', { p_emp: val('lr_e'), p_type: val('lr_t'), p_from: val('lr_f') || null, p_to: val('lr_to') || null, p_reason: val('lr_r') || null, p_client: D.lrClient }, 'saved'); if (d) { closeSheet(); drawLeave(); } },
  lv_dec: async (a) => { const ok = a.dataset.ok === '1'; const note = ok ? null : ask(); if (!ok && !note) return; const d = await rpc('leave_decide', { p_id: Number(a.dataset.v), p_approve: ok, p_note: note }, 'saved'); if (d) drawLeave(); },
  lv_cancel: async (a) => { const n = ask(); if (!n) return; const d = await rpc('leave_cancel', { p_id: Number(a.dataset.v), p_reason: n }, 'saved'); if (d) drawLeave(); },
});
document.addEventListener('change', async (e) => {
  const id = e.target.id;
  if (id === 'at_loc' || id === 'lv_loc') { D.loc = Number(e.target.value); D.emps = []; D.emp = null; LV.emp = null; D.prev = null; D.imp = null; if (id === 'at_loc') draw(); else drawLeave(); }
  if (id === 'at_day') { D.day = e.target.value || today(); draw(); }
  if (id === 'at_emp') { D.emp = e.target.value; draw(); }
  if (id === 'at_month') { D.month = e.target.value || today().slice(0, 7); draw(); }
  if (id === 'lv_emp') { LV.emp = e.target.value; drawLeave(); }
  if (id === 'lv_year') { LV.year = Number(e.target.value) || LV.year; drawLeave(); }
  if (id === 'im_file' && e.target.files && e.target.files[0]) { const f = e.target.files[0]; D.impName = f.name; try { D.imp = parseFile(await f.text()); } catch (er) { return fail(er); } D.prev = null; draw(); }
  if (id === 'im_cu' || id === 'im_ct' || id === 'im_cd') { const c = D.imp.csv; c.map = { u: Number(val('im_cu')), t: Number(val('im_ct')), d: Number(val('im_cd')) }; D.imp = mapCsv(c); D.prev = null; draw(); }
});
document.addEventListener('input', (e) => {
  if (e.target.id === 'im_paste') { clearTimeout(D.pt); D.pt = setTimeout(() => { const t = e.target.value; if (!t.trim()) return; D.impName = 'paste'; D.imp = parseFile(t); D.prev = null; const keep = t; draw().then(() => { const p = $('#im_paste'); if (p) p.value = keep; }); }, 400); }
});
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { attendance: view, leave: leaveView });
B.attendance = { parseFile, normTs, eText };
})();
