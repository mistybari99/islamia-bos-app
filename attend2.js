/* Islamia BOS · Attendance 2 (#/attend2) + server form check (#/eqcheck).  Server: supabase/phase54.sql (gaps #29, #20) + a small client-id RPC queue (gap #19 add-on).
   attend2 tabs
     me     self punch from the phone (needs rule app_punch_on; the owner can lock one person / one role). Optional EVIDENCE: browser passkey (WebAuthn) or a face photo,
            soft GPS flag. Evidence is a flag + a reference ONLY - the server cannot verify a passkey or a face, nothing here proves who is holding the phone.
     mark   owner / holder of the grant attendance_mark_others marks ANOTHER person's day: status, in, closing time, rest minutes, source tag device/finger/face/manual
            (the tag is the marker's own word, not a proof). Every mark goes to an append-only log. A month locked by payroll is refused.
     staff  owner: lock / unlock self punch per person or per role, place coordinates for the soft GPS flag; manager: record "fingerprint enrolled on the device" flag.
     count  staff attendance (path A) vs the monthly register 02-1 (path B): which one is counted, shadow copies, per-person differences.
   RPCs: attendance_self_punch, att_my_status, att_self_lock_set, att_site_geo_set, att_staff_overview, att_evidence_register / void, attendance_mark_others,
         att_others_board, attendance_count_once, attendance_form_link_run, entry_equation_check.
   B.rpcq (this file): a client-id outbox for RPC writes (IndexedDB + localStorage copy). A write that cannot reach the server waits here with its p_client key and is resent
   on 'online' / at start / every 30 s; the server answers a repeated key with the first result, so a resend never writes twice. A server refusal is shown, not retried.
   The form entry screen already has its own queue (web/entry.js, #/outbox); B.rpcq.saveEntry() is the same idea for save_entry for any other screen. Nothing is deleted. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet, H, nm } = A;
const L = B.L, lab = B.lab;
const U = B.s2 || {};
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const rid = () => (crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); }));
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const hm = (x) => (x ? new Date(x).toLocaleTimeString('en-GB', { timeZone: 'Asia/Dhaka', hour: '2-digit', minute: '2-digit' }) : '');
const LOCS = () => { const all = B.liveLocs ? B.liveLocs((B.ENV && B.ENV.locs) || []) : ((B.ENV && B.ENV.locs) || []); return S.ctx.is_owner || (S.ctx.roles || []).includes('management') ? all : all.filter((l) => (S.ctx.locations || []).includes(l.id)); };

/* ================= B.rpcq : client-id outbox for RPC writes ================= */
const Q = (() => {
  const uid = () => (S.ctx && S.ctx.profile ? S.ctx.profile.id : 'anon');
  const LK = () => 'bos_rpcq_' + uid();
  let mem = null, flushing = false; const subs = new Set();
  const lsRead = () => { try { const v = JSON.parse(localStorage.getItem(LK()) || '[]'); return Array.isArray(v) ? v : []; } catch (e) { return []; } };
  const lsWrite = (a) => { try { const v = JSON.stringify(a); localStorage.setItem(LK(), v); return localStorage.getItem(LK()) === v; } catch (e) { return false; } };
  const idb = () => new Promise((res) => { try { const r = indexedDB.open('bos_rpcq', 1); r.onupgradeneeded = () => r.result.createObjectStore('q', { keyPath: 'k' }); r.onsuccess = () => res(r.result); r.onerror = () => res(null); r.onblocked = () => res(null); } catch (e) { res(null); } });
  const idbAll = async () => { const db = await idb(); if (!db) return []; return new Promise((res) => { try { const q = db.transaction('q').objectStore('q').getAll(); q.onsuccess = () => res(q.result || []); q.onerror = () => res([]); } catch (e) { res([]); } }); };
  const idbSync = async (a) => { const db = await idb(); if (!db) return; try { const tx = db.transaction('q', 'readwrite'), st = tx.objectStore('q'); st.clear(); a.forEach((x) => st.put({ ...x, k: uid() + '|' + x.id })); } catch (e) { /* the localStorage copy still holds it */ } };
  const notify = () => subs.forEach((f) => { try { f(); } catch (e) { /* ignore */ } });
  const all = () => { if (!mem) mem = lsRead(); return mem; };
  const persist = () => { const ok = lsWrite(mem); idbSync(mem); return ok; };
  const isNet = (e) => !navigator.onLine || (!!e && !e.code && /fetch|network|load failed|timeout|offline/i.test(e.message || ''));
  const isAuth = (m) => /jwt|token|401|not authenticated|unauthor|expired/i.test(String(m || ''));
  const api = {
    list: () => all().slice(), count: () => all().filter((x) => x.state !== 'refused').length,
    subscribe: (f) => { subs.add(f); return () => subs.delete(f); },
    /* item = { fn, args (must carry its own client key), label } ; returns false when it could not even be kept on this phone */
    enqueue(item) {
      all(); const id = item.id || rid(); mem = mem.filter((x) => x.id !== id);
      mem.push({ id, fn: item.fn, args: item.args, label: item.label || item.fn, at: new Date().toISOString(), state: 'wait', msg: '' });
      const ok = persist(); notify(); return ok ? id : null;
    },
    saveEntry(args, meta) { const cid = (meta && meta.client_id) || rid(); return api.enqueue({ id: cid, fn: 'save_entry', args: { ...args, p_meta: { ...(meta || {}), client_id: cid } }, label: 'save_entry ' + (args.p_form || '') }); },
    discard(id) { all(); mem = mem.filter((x) => x.id !== id); persist(); notify(); },
    retry(id) { all(); const it = mem.find((x) => x.id === id); if (it) { it.state = 'wait'; it.msg = ''; persist(); notify(); } return api.flush(); },
    async restore() { all(); const have = new Set(mem.map((x) => x.id)); const from = await idbAll(); let add = 0;   // IndexedDB may still hold what localStorage lost
      from.filter((x) => String(x.k || '').startsWith(uid() + '|') && !have.has(x.id)).forEach((x) => { const { k, ...rest } = x; mem.push(rest); add++; });
      if (add) { persist(); notify(); } return add; },
    /* resend everything that waits, oldest first, one at a time. Returns { sent, left, refused } */
    async flush() {
      if (flushing) return { busy: true }; flushing = true; let sent = 0;
      try {
        all();
        for (const it of mem.filter((x) => x.state === 'wait').sort((a, b) => a.at.localeCompare(b.at))) {
          let r; try { r = await sb.rpc(it.fn, it.args); } catch (e) { r = { error: e || { message: 'Failed to fetch' } }; }
          if (r.error) {
            if (isNet(r.error) || isAuth(r.error.message)) break;        // no network / expired login: keep waiting, never mark refused
            it.state = 'refused'; it.msg = String(r.error.message || r.error); persist(); continue;
          }
          mem = mem.filter((x) => x.id !== it.id); persist(); sent++;   // the answer may be {duplicate:true}: also a success
        }
      } finally { flushing = false; notify(); }
      return { sent, left: all().filter((x) => x.state === 'wait').length, refused: all().filter((x) => x.state === 'refused').length };
    },
    /* try now; if the network is down keep it for later. Returns { sent:true, data } | { queued:true } | { error } */
    async send(fn, args, label) {
      let r; try { r = await sb.rpc(fn, args); } catch (e) { r = { error: e || { message: 'Failed to fetch' } }; }
      if (!r.error) return { sent: true, data: r.data };
      if (isNet(r.error)) { const id = api.enqueue({ fn, args, label }); return id ? { queued: true, id } : { error: r.error, nostore: true }; }
      return { error: r.error };
    },
    _reset() { mem = null; },
  };
  window.addEventListener('online', () => { api.flush(); });
  setTimeout(() => { api.restore().then(() => api.flush()); }, 2500);
  setInterval(() => { if (all().some((x) => x.state === 'wait')) api.flush(); }, 30000);
  return api;
})();
B.rpcq = Q;

/* ================= texts ================= */
const X = {
  title: L('হাজিরা ২ — পাঞ্চ, লেখা, একবার গোনা', 'Attendance 2 - punch, mark, counted once', 'Attendance 2 — punch, mark, একবার গোনা'),
  tMe: L('আমার পাঞ্চ', 'My punch', 'আমার punch'), tMark: L('অন্যের হাজিরা লিখুন', 'Mark others', 'অন্যের হাজিরা'), tStaff: L('কর্মী ও লক', 'Staff & locks', 'Staff ও lock'), tCount: L('একবার গোনা', 'Counted once', 'একবার গোনা'),
  place: L('জায়গা', 'Place', 'Place'), date: L('তারিখ', 'Date', 'Date'), month: L('মাস', 'Month', 'Month'), none: L('কিছু নেই', 'Nothing here', 'কিছু নেই'),
  limitsT: L('সীমাবদ্ধতা — সৎ কথা', 'Honest limits', 'Honest limits'),
  limits: L('এখানে আঙুল/মুখ/পাসকি শুধু প্রমাণের রেফারেন্স (evidence)। সার্ভার পাসকি বা মুখ যাচাই করতে পারে না — তাই কেউ নিজে সেই ফোন ধরেছে তার প্রমাণ নয়। আঙুলের ছাপ শুধু আলাদা ফিঙ্গারপ্রিন্ট মেশিন-ব্রিজ দিয়ে আসে। জিপিএস শুধু নরম পতাকা — ভুল বা নকল হতে পারে, পাঞ্চ আটকায় না। "সোর্স ট্যাগ" লেখকের নিজের ঘোষণা।',
    'Fingerprint, face and passkey here are EVIDENCE references only. The server cannot verify a passkey or a face, so none of them proves who is holding the phone. A fingerprint only arrives through the separate device bridge. GPS is a soft flag - it can be wrong or faked and never blocks a punch. The "source tag" is the marker\'s own declaration.',
    'Finger/face/passkey এখানে শুধু evidence reference। Server passkey বা মুখ verify করতে পারে না — তাই ফোন কার হাতে তার প্রমাণ নয়। Fingerprint শুধু আলাদা device bridge দিয়ে আসে। GPS শুধু soft flag — ভুল/নকল হতে পারে, punch আটকায় না। "Source tag" লেখকের নিজের ঘোষণা।'),
  state: L('অবস্থা', 'State', 'State'), canPunch: L('আপনি এখন পাঞ্চ করতে পারেন', 'You can punch now', 'এখন punch করতে পারেন'),
  s_app_punch_off: L('অ্যাপ থেকে পাঞ্চ বন্ধ (সুইচবোর্ডে app_punch_on)', 'Self punch is OFF (Switchboard: app_punch_on)', 'App punch বন্ধ (app_punch_on)'),
  s_self_punch_locked: L('মালিক আপনার (বা আপনার ভূমিকার) স্ব-পাঞ্চ লক করেছেন', 'The owner has locked self punch for you or your role', 'Owner আপনার/role-এর self punch lock করেছেন'),
  s_path_locked: L('এই জায়গায় হাজিরা পথ (ক) লক', 'Attendance path A is locked here', 'এখানে attendance path A lock'),
  s_attendance_off: L('হাজিরা বন্ধ', 'Attendance is off', 'Attendance বন্ধ'), s_no_employee_record: L('আপনার লগইন কর্মী-তথ্যের সাথে জোড়া নেই', 'Your login is not linked to an employee record', 'Login employee record-এর সাথে জোড়া নেই'),
  inB: L('চেক ইন', 'Check in', 'Check in'), outB: L('চেক আউট', 'Check out', 'Check out'), evid: L('প্রমাণ (evidence) সংযুক্ত করুন', 'Attach evidence', 'Evidence যোগ করুন'),
  ev_none: L('কিছু না', 'None', 'None'), ev_pass: L('ব্রাউজার পাসকি', 'Browser passkey', 'Browser passkey'), ev_face: L('মুখের ছবি', 'Face photo', 'Face photo'),
  geo: L('আমার অবস্থান পাঠান (নরম পতাকা)', 'Send my location (soft flag)', 'আমার location পাঠান (soft flag)'), punched: L('পাঞ্চ হয়েছে', 'Punch recorded', 'Punch হয়েছে'),
  regPass: L('এই ফোনের পাসকি নিবন্ধন', 'Register this phone\'s passkey', 'এই phone-এর passkey register'), regFace: L('রেফারেন্স মুখের ছবি যোগ', 'Add a reference face photo', 'Reference face photo যোগ'),
  mine: L('আমার নিবন্ধন', 'My registrations', 'আমার registration'), voidB: L('বাতিল', 'Remove', 'Remove'), why: L('কারণ লিখুন', 'Write the reason', 'কারণ লিখুন'),
  noPass: L('এই ফোন/ব্রাউজারে পাসকি চলে না', 'Passkeys are not available on this phone / browser', 'এই phone/browser-এ passkey চলে না'), registered: L('নিবন্ধিত', 'Registered', 'Registered'),
  evState_registered: L('নিবন্ধিত রেফারেন্স মিলেছে', 'matches a registration', 'registration মিলেছে'), evState_unregistered: L('নিবন্ধনের সাথে মেলেনি', 'not a registered one', 'registration মেলেনি'), evState_none: L('প্রমাণ নেই', 'no evidence', 'evidence নেই'),
  geoF_ok: L('জায়গার কাছে', 'near the place', 'জায়গার কাছে'), geoF_outside: L('জায়গা থেকে দূরে (পতাকা)', 'far from the place (flag)', 'জায়গা থেকে দূরে (flag)'), geoF_no_fix: L('অবস্থান পাওয়া যায়নি', 'no location fix', 'location পাওয়া যায়নি'), geoF_unchecked: L('অবস্থান যাচাই বন্ধ', 'location not checked', 'location check বন্ধ'),
  // mark
  st_present: L('উপস্থিত', 'Present', 'Present'), st_late: L('দেরি', 'Late', 'Late'), st_half_day: L('অর্ধ দিন', 'Half day', 'Half day'), st_absent: L('অনুপস্থিত', 'Absent', 'Absent'), st_off: L('সাপ্তাহিক ছুটি', 'Weekly off', 'Weekly off'), st_holiday: L('ছুটির দিন', 'Holiday', 'Holiday'), st_unpaid: L('বিনা বেতনে', 'Unpaid', 'Unpaid'), st_leave: L('ছুটি', 'On leave', 'Leave'),
  inT: L('ঢোকার সময়', 'In time', 'In time'), outT: L('বন্ধ/বের হওয়ার সময়', 'Closing / out time', 'Closing/out time'), rest: L('বিরতি (মিনিট)', 'Rest time (minutes)', 'Rest (minutes)'),
  src: L('সোর্স ট্যাগ', 'Source tag', 'Source tag'), src_device: L('মেশিন (device)', 'Device', 'Device'), src_finger: L('আঙুল (finger)', 'Finger', 'Finger'), src_face: L('মুখ (face)', 'Face', 'Face'), src_manual: L('হাতে (manual)', 'Manual', 'Manual'),
  srcHint: L('ট্যাগ আপনার নিজের ঘোষণা হিসেবে লগে থাকবে — প্রমাণ নয়।', 'The tag is stored in the log as YOUR declaration - not a proof.', 'Tag log-এ আপনার ঘোষণা হিসেবে থাকবে — proof নয়।'),
  reason: L('কারণ (জরুরি)', 'Reason (required)', 'কারণ (জরুরি)'), note: L('নোট', 'Note', 'Note'), save: L('সংরক্ষণ', 'Save', 'Save'), saved: L('সংরক্ষিত', 'Saved', 'Saved'), markB: L('লিখুন', 'Mark', 'Mark'),
  waits: L('পাঠানো হয়নি — নেট এলে নিজে যাবে', 'Not sent yet - goes by itself when the net is back', 'Send হয়নি — net এলে নিজে যাবে'), queued: L('ফোনে রাখা হয়েছে, নেট এলে যাবে', 'Kept on the phone, will go when the net is back', 'Phone-এ রাখা হয়েছে, net এলে যাবে'),
  sendNow: L('এখনই পাঠান', 'Send now', 'এখনই send'), discard: L('ফেলে দিন', 'Discard', 'Discard'), refused: L('সার্ভার নিল না', 'Refused by the server', 'Server নেয়নি'), pending: L('অনুমোদন বাকি', 'Waiting approval', 'Approval বাকি'),
  me2: L('নিজে', 'you', 'নিজে'), selfNo: L('নিজের হাজিরা নিজে লেখা যায় না', 'You cannot mark yourself', 'নিজের হাজিরা নিজে লেখা যায় না'), needGrant: L('এই কাজের অনুমতি (attendance_mark_others) মালিক দেন।', 'The owner gives this right (attendance_mark_others).', 'Owner এই right (attendance_mark_others) দেন।'),
  // staff
  lockP: L('স্ব-পাঞ্চ লক', 'Self-punch lock', 'Self-punch lock'), locked: L('লক', 'Locked', 'Locked'), open: L('খোলা', 'Open', 'Open'), roles: L('ভূমিকা অনুযায়ী লক', 'Lock by role', 'Role অনুযায়ী lock'),
  geoSet: L('এই জায়গার অবস্থান = আমার এখনকার অবস্থান', 'Set this place = my location now', 'এই জায়গা = আমার এখনকার location'), geoSaved: L('জায়গার অবস্থান রাখা হয়েছে', 'Place location saved', 'Place location রাখা হয়েছে'),
  fingerFlag: L('আঙুল মেশিনে তোলা আছে (ডিভাইস আইডি)', 'Fingerprint enrolled on the device (device user id)', 'Finger device-এ তোলা আছে (device user id)'), add: L('যোগ', 'Add', 'Add'),
  master: L('মাস্টার সুইচ app_punch_on', 'Master switch app_punch_on', 'Master switch app_punch_on'), on: L('চালু', 'ON', 'ON'), off: L('বন্ধ', 'OFF', 'OFF'),
  k_webauthn: L('পাসকি', 'passkey', 'passkey'), k_face_photo: L('মুখের ছবি', 'face photo', 'face photo'), k_finger_device: L('আঙুল (মেশিনে)', 'finger (device)', 'finger (device)'),
  // count
  counted: L('গোনা হচ্ছে', 'Counted', 'Counted'), c_attendance_record: L('হাজিরা রেকর্ড (পাঞ্চ/লেখা)', 'Attendance record (punch / marked)', 'Attendance record (punch/marked)'), c_form_02_1: L('ফর্ম 02-1', 'Form 02-1', 'Form 02-1'),
  shadow: L('শ্যাডো কপি (লক)', 'Shadow copy (locked)', 'Shadow copy (lock)'), record: L('রেকর্ড', 'Record', 'Record'), a_has: L('পথ ক-এ এই মাসের তথ্য আছে', 'Path A holds this month', 'Path A-তে এই মাসের data আছে'),
  linkNow: L('ফর্ম এখনই জোড়া লাগান', 'Link the forms now', 'Form এখনই link করুন'), linked: L('জোড়া হয়েছে', 'Linked', 'Linked'), dev: L('হাজিরা রেকর্ড', 'Record', 'Record'), frm: L('ফর্ম 02-1', 'Form 02-1', 'Form 02-1'),
  pres: L('উপস্থিত', 'present', 'present'), late: L('দেরি', 'late', 'late'), abs: L('অনুপস্থিত', 'absent', 'absent'), ot: L('ওভারটাইম ঘ.', 'OT h', 'OT h'), differ: L('মিলছে না', 'Differs', 'মিলছে না'), same: L('মিলছে', 'Matches', 'মিলছে'),
  note14: L('ফর্ম 14-1 (দৈনিক শোরুম শিট) ক্যাশ ড্রয়ারের শিট — এই সুইচের আওতায় নয়।', 'Form 14-1 (daily showroom sheet) is the cash drawer sheet - it is not under this switch.', 'Form 14-1 (daily showroom sheet) cash drawer sheet — এই switch-এর বাইরে।'),
  nameMatch: L('নাম/কর্মী নম্বর মিলিয়ে ধরা হয়েছে — পার্থক্য দেখার ইঙ্গিত, রায় নয়।', 'People are matched by name / employee no.; a difference is a prompt to look, not a verdict.', 'নাম/employee no. মিলিয়ে — পার্থক্য দেখার ইঙ্গিত, রায় নয়।'),
  // eqcheck
  eqTitle: L('সার্ভারে হিসাব মেলানো (10-2 / 02-2)', 'Server re-check of totals (10-2 / 02-2)', 'Server-এ হিসাব মেলানো (10-2 / 02-2)'),
  eqIntro: L('ফোনে হওয়া হিসাব আর পতাকা সার্ভার আবার করে মেলায়। শুধু দেখা — কিছু বদলায় না। 14-1 এখনো নয়।', 'The server re-works the totals and compares them with the flags the phone stored. Read only - nothing is changed. 14-1 is not covered yet.', 'Phone-এর হিসাব/flag server আবার মেলায়। শুধু দেখা — কিছু বদলায় না। 14-1 এখনো নয়।'),
  check: L('মেলান', 'Check', 'Check'), allOk: L('সব মিলেছে ✓', 'All match ✓', 'সব মিলেছে ✓'), recomputed: L('সার্ভারের হিসাব', 'Server figures', 'Server figures'), mism: L('অমিল', 'Differences', 'Differences'),
  k_flag_missing: L('ফোনে পতাকা পড়েনি', 'the phone raised no flag', 'phone-এ flag পড়েনি'), k_flag_extra: L('ফোনে লাল পতাকা ছিল কিন্তু হিসাবে মিলছে', 'the phone has a red flag but the figures agree', 'phone-এ red flag কিন্তু হিসাব মিলছে'), k_amount_differs: L('পতাকার অঙ্ক আলাদা', 'flag amount differs', 'flag-এর amount আলাদা'),
  obs: L('তথ্য', 'For information', 'For information'),
};
const T = (k) => lab(X[k]);
const ERR = {
  app_punch_off: X.s_app_punch_off, self_punch_locked: X.s_self_punch_locked, path_locked: X.s_path_locked, attendance_off: X.s_attendance_off, no_employee_record: X.s_no_employee_record,
  too_soon: L('এক মিনিটের মধ্যে আবার নয়', 'Not twice within a minute', 'এক মিনিটের মধ্যে আবার নয়'), bad_geo: L('অবস্থান ঠিক নয়', 'Bad location', 'Location ঠিক নয়'), bad_evidence: L('প্রমাণের তথ্য ঠিক নয়', 'Bad evidence', 'Evidence ঠিক নয়'),
  cannot_mark_self: X.selfNo, month_locked: L('এই মাসের বেতন অনুমোদিত — হাজিরা বন্ধ', 'Payroll is approved for this month - attendance is locked', 'Payroll approved — month lock'),
  reason_required: L('কারণ লিখুন (কমপক্ষে ৩ অক্ষর)', 'Write a reason (3+ letters)', 'কারণ লিখুন (৩+ অক্ষর)'), bad_date: L('তারিখ ঠিক নয় (আজ থেকে ৬২ দিনের মধ্যে)', 'Date not valid (within 62 days)', 'Date ঠিক নয় (৬২ দিনের মধ্যে)'),
  bad_source: L('সোর্স ট্যাগ বাছুন', 'Choose the source tag', 'Source tag বাছুন'), bad_rest: L('বিরতি ০–৭২০ মিনিট', 'Rest must be 0-720 minutes', 'Rest ০–৭২০ min'), bad_time: L('সময় ঠিক নয়', 'Time is not valid', 'Time ঠিক নয়'), bad_status: L('অবস্থা বাছুন', 'Choose a status', 'Status বাছুন'),
  client_id_in_use: L('এই ক্লায়েন্ট কী অন্যের', 'This client key belongs to someone else', 'Client key অন্যের'), not_found: L('পাওয়া যায়নি', 'Not found', 'পাওয়া যায়নি'), too_many: L('সর্বোচ্চ ১০টি নিবন্ধন', 'At most 10 registrations', 'সর্বোচ্চ ১০টি'),
  'not allowed': L('অনুমতি নেই', 'Not allowed', 'Permission নেই'),
};
const eText = (e) => { const m = String((e && e.message) || e || ''); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? lab(ERR[k]) : (m || 'error'); };
const showErr = (e) => toast(eText(e));

const css = document.createElement('style'); css.id = 'a2css';
css.textContent = `.a2-row{display:flex;gap:8px;align-items:center;justify-content:space-between;flex-wrap:wrap}.a2-row .nm{flex:1 1 140px;min-width:0;overflow-wrap:anywhere}.a2-lim{font-size:12px;opacity:.85}.a2-num{font-variant-numeric:tabular-nums}
.a2-pick{display:flex;flex-wrap:wrap;gap:8px}.a2-pick>div{flex:1 1 140px;min-width:0}.a2-pick select,.a2-pick input{width:100%;max-width:100%}.a2-diff{outline:2px solid var(--bad,#c33)}
.a2-pre{white-space:pre-wrap;overflow-wrap:anywhere;font-size:12px}`;
if (!document.getElementById('a2css')) document.head.appendChild(css);

const D = { tab: 'me', loc: null, day: today(), month: today().slice(0, 7), me: null, board: null, staff: null, count: null, can: {}, ev: null, geo: false };
const tabsHTML = (list) => `<div class="ptabs" role="tablist">${list.map(([k, l]) => `<button role="tab" data-act="a2_tab" data-v="${k}" aria-selected="${D.tab === k}">${esc(T(l))}</button>`).join('')}</div>`;
const locSel = () => `<select id="a2_loc" aria-label="${esc(T('place'))}">${LOCS().map((l) => `<option value="${l.id}" ${l.id === D.loc ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select>`;
const limitsBox = () => `<details data-ctl="off" class="card"><summary>${esc(T('limitsT'))}</summary><p class="a2-lim">${esc(T('limits'))}</p></details>`;
async function grant(code) {
  if (S.ctx.is_owner) return true; const k = code + '|' + D.loc; if (k in D.can) return D.can[k];
  D.can[k] = U.grant ? await U.grant(code, D.loc) : false; return D.can[k];
}

/* ================= me ================= */
const b64u = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const unb64u = (s) => { s = String(s).replace(/-/g, '+').replace(/_/g, '/'); while (s.length % 4) s += '='; return Uint8Array.from(atob(s), (c) => c.charCodeAt(0)); };
const passOk = () => !!(window.PublicKeyCredential && navigator.credentials && navigator.credentials.create);
function getPos() {
  return new Promise((res) => { if (!navigator.geolocation) return res(null); let done = false; const t = setTimeout(() => { if (!done) { done = true; res(null); } }, 8000);
    navigator.geolocation.getCurrentPosition((p) => { if (!done) { done = true; clearTimeout(t); res({ lat: p.coords.latitude, lng: p.coords.longitude, acc: p.coords.accuracy }); } }, () => { if (!done) { done = true; clearTimeout(t); res(null); } }, { enableHighAccuracy: true, timeout: 7000, maximumAge: 30000 }); });
}
async function meHTML() {
  const r = await sb.rpc('att_my_status'); if (r.error) return `<p class="muted">${esc(eText(r.error))}</p>`;
  D.me = r.data || {};
  if (!D.me.employee) return `<div class="card"><p>${esc(T('s_no_employee_record'))}</p></div>${limitsBox()}`;
  let regs = [];
  const rr = await sb.from('att_evidence_reg').select('id,kind,label,ref').eq('employee_id', D.me.employee_id).eq('active', true); regs = rr.data || []; D.ev = regs;
  const ok = D.me.can_punch;
  const regHTML = regs.map((x) => `<div class="a2-row"><span class="chip">${esc(T('k_' + x.kind))}</span><span class="nm muted">${esc(x.label || '')}</span><button class="mini" data-act="a2_evvoid" data-v="${esc(x.id)}">${esc(T('voidB'))}</button></div>`).join('');
  return `<div class="card stack"><div class="a2-row"><b>${esc(lab({ bn: D.me.name_bn, en: D.me.name_en || D.me.name_bn, mix: D.me.name_bn }))}</b><span class="chip ${ok ? 'ok' : 'warn'}">${esc(ok ? T('canPunch') : T('s_' + D.me.state))}</span></div>
    ${ok ? `<div class="a2-pick"><div><label for="a2_ev">${esc(T('evid'))}</label><select id="a2_ev"><option value="">${esc(T('ev_none'))}</option><option value="webauthn">${esc(T('ev_pass'))}</option><option value="face_photo">${esc(T('ev_face'))}</option></select></div></div>
      <label class="row"><input type="checkbox" id="a2_geo" ${D.me.geo_check_on ? 'checked' : ''}> ${esc(T('geo'))}</label>
      <div class="row"><button class="full primary" data-act="a2_punch" data-v="in">${esc(T('inB'))}</button><button class="full" data-act="a2_punch" data-v="out">${esc(T('outB'))}</button></div>
      <input type="file" id="a2_face" accept="image/*" capture="user" hidden>` : ''}
    ${D.me.last_punch ? `<p class="muted a2-num">${esc(hm(D.me.last_punch.punched_at))} · ${esc(T('evState_' + (D.me.last_punch.evidence_state || 'none')))} · ${esc(T('geoF_' + (D.me.last_punch.geo_flag || 'unchecked')))}</p>` : ''}</div>
    <div class="card stack"><b>${esc(T('mine'))}</b>${regHTML || `<p class="muted">${esc(T('none'))}</p>`}
      <div class="row">${passOk() ? `<button class="full" data-act="a2_regpass">${esc(T('regPass'))}</button>` : `<span class="muted">${esc(T('noPass'))}</span>`}<button class="full" data-act="a2_regface">${esc(T('regFace'))}</button></div>
      <input type="file" id="a2_regfile" accept="image/*" capture="user" hidden></div>${limitsBox()}`;
}
function pickFace() { return new Promise((res) => { const f = $('#a2_face') || $('#a2_regfile'); if (!f) return res(null); f.value = ''; f.onchange = () => res(f.files && f.files[0]); f.click(); }); }
async function doPunch(dir) {
  const evk = ($('#a2_ev') || {}).value || ''; let ev_kind = null, ev_ref = null;
  try {
    if (evk === 'webauthn') {
      const cred = (D.ev || []).find((x) => x.kind === 'webauthn'); if (!cred || !passOk()) return toast(cred ? T('noPass') : T('ev_pass') + ': ' + T('none'));
      const a = await navigator.credentials.get({ publicKey: { challenge: crypto.getRandomValues(new Uint8Array(32)), allowCredentials: [{ id: unb64u(cred.ref), type: 'public-key' }], userVerification: 'preferred', timeout: 60000 } });
      if (!a) return; ev_kind = 'webauthn'; ev_ref = cred.ref;
    } else if (evk === 'face_photo') {
      const f = await pickFace(); if (!f) return; toast('…');
      ev_ref = await U.uploadPhoto(f, ['EMP'], (LOCS()[0] || {}).id || 1); ev_kind = 'face_photo';
    }
  } catch (e) { return toast(T('ev_' + (evk === 'webauthn' ? 'pass' : 'face')) + ': ' + (e && e.name ? e.name : 'error')); }
  let pos = null; if ($('#a2_geo') && $('#a2_geo').checked) pos = await getPos();
  const r = await sb.rpc('attendance_self_punch', { p_dir: dir, p_lat: pos ? pos.lat : null, p_lng: pos ? pos.lng : null, p_acc: pos ? pos.acc : null, p_ev_kind: ev_kind, p_ev_ref: ev_ref });
  if (r.error) return showErr(r.error);
  toast(T('punched') + ' · ' + T('evState_' + (r.data.evidence_state || 'none')) + ' · ' + T('geoF_' + (r.data.geo_flag || 'unchecked'))); draw();
}
async function regPass() {
  try {
    const me = D.me; const cred = await navigator.credentials.create({ publicKey: { challenge: crypto.getRandomValues(new Uint8Array(32)), rp: { name: 'Islamia BOS', id: location.hostname },
      user: { id: new TextEncoder().encode(String(me.employee_id)).slice(0, 64), name: String(me.employee_id), displayName: me.name_en || me.name_bn || 'staff' }, pubKeyCredParams: [{ type: 'public-key', alg: -7 }, { type: 'public-key', alg: -257 }],
      authenticatorSelection: { authenticatorAttachment: 'platform', userVerification: 'preferred' }, timeout: 60000 } });
    if (!cred) return; const ref = b64u(cred.rawId);
    const r = await sb.rpc('att_evidence_register', { p_emp: me.employee_id, p_kind: 'webauthn', p_ref: ref, p_label: String(navigator.platform || 'phone').slice(0, 60) });
    if (r.error) return showErr(r.error); toast(T('saved')); draw();
  } catch (e) { toast(T('noPass') + (e && e.name ? ' · ' + e.name : '')); }
}
async function regFace() {
  try { const f = await pickFace(); if (!f) return; toast('…'); const path = await U.uploadPhoto(f, ['EMP'], (LOCS()[0] || {}).id || 1);
    const r = await sb.rpc('att_evidence_register', { p_emp: D.me.employee_id, p_kind: 'face_photo', p_ref: path, p_label: 'reference photo' }); if (r.error) return showErr(r.error); toast(T('saved')); draw(); } catch (e) { fail(e); }
}

/* ================= mark others ================= */
const STAT = ['present', 'late', 'half_day', 'absent', 'off', 'holiday', 'unpaid'];
const SRC = ['manual', 'finger', 'face', 'device'];
async function markHTML() {
  const okG = await grant('attendance_mark_others');
  const pick = `<div class="a2-pick"><div><label for="a2_loc">${esc(T('place'))}</label>${locSel()}</div><div><label for="a2_day">${esc(T('date'))}</label><input id="a2_day" type="date" value="${esc(D.day)}" max="${today()}"></div></div>`;
  const waiting = Q.list().filter((x) => x.fn === 'attendance_mark_others');
  const wHTML = waiting.length ? `<div class="card stack"><b>${esc(T('waits'))} · ${waiting.length}</b>${waiting.map((x) => `<div class="a2-row"><span class="nm">${esc(x.label)} <span class="muted">${esc(x.args.p_day || '')}</span>${x.state === 'refused' ? `<br><span class="chip bad">${esc(T('refused'))}</span> ${esc(eText({ message: x.msg }))}` : ''}</span>
      <button class="mini" data-act="a2_qsend" data-v="${esc(x.id)}">${esc(T('sendNow'))}</button><button class="mini" data-act="a2_qdrop" data-v="${esc(x.id)}">${esc(T('discard'))}</button></div>`).join('')}</div>` : '';
  if (!okG) return pick + `<div class="card"><p>${esc(T('needGrant'))}</p></div>` + wHTML + limitsBox();
  const r = await sb.rpc('att_others_board', { p_loc: D.loc, p_day: D.day }); if (r.error) return pick + `<p class="muted">${esc(eText(r.error))}</p>` + wHTML;
  D.board = r.data || { rows: [] };
  const rows = (D.board.rows || []).map((x) => `<div class="card a2-row" data-emp="${esc(x.employee_id)}"><div class="nm"><b>${esc(lab({ bn: x.name_bn, en: x.name_en || x.name_bn, mix: x.name_bn }))}</b> <span class="muted">${esc(x.employee_no || '')}</span>
      <div class="muted a2-num">${x.first_in ? esc(hm(x.first_in)) : '–'} → ${x.last_out ? esc(hm(x.last_out)) : '–'}${x.rest_minutes != null ? ' · ' + esc(T('rest')) + ' ' + esc(String(x.rest_minutes)) : ''}</div></div>
      <span class="chip">${esc(T('st_' + (x.status || 'absent')))}</span>${x.mark_source ? `<span class="chip info">${esc(T('src_' + x.mark_source))}</span>` : ''}${x.pending ? `<span class="chip warn">${esc(T('pending'))}</span>` : ''}
      ${x.is_me ? `<span class="chip">${esc(T('me2'))}</span>` : `<button class="mini" data-act="a2_mark" data-v="${esc(x.employee_id)}">${esc(T('markB'))}</button>`}</div>`).join('');
  return pick + `<div id="a2_rows">${rows || `<p class="muted">${esc(T('none'))}</p>`}</div>` + wHTML + limitsBox();
}
function markSheet(id) {
  const x = ((D.board && D.board.rows) || []).find((r) => r.employee_id === id) || {};
  openSheet(`<h3>${esc(T('markB'))}: ${esc(lab({ bn: x.name_bn, en: x.name_en || x.name_bn, mix: x.name_bn }))} · ${esc(D.day)}</h3><div class="stack">
    <div><label for="a2_s">${esc(T('state'))}</label><select id="a2_s">${STAT.map((s) => `<option value="${s}" ${s === (x.status || 'present') ? 'selected' : ''}>${esc(T('st_' + s))}</option>`).join('')}</select></div>
    <div class="row"><div><label for="a2_in">${esc(T('inT'))}</label><input id="a2_in" type="time" value="${esc(hm(x.first_in))}"></div><div><label for="a2_out">${esc(T('outT'))}</label><input id="a2_out" type="time" value="${esc(hm(x.last_out))}"></div></div>
    <div><label for="a2_rest">${esc(T('rest'))}</label><input id="a2_rest" inputmode="numeric" autocomplete="off" value="${x.rest_minutes != null ? esc(String(x.rest_minutes)) : ''}"></div>
    <div><label for="a2_src">${esc(T('src'))}</label><select id="a2_src">${SRC.map((s) => `<option value="${s}">${esc(T('src_' + s))}</option>`).join('')}</select><div class="a2-lim">${esc(T('srcHint'))}</div></div>
    <div><label for="a2_r">${esc(T('reason'))}</label><input id="a2_r" autocomplete="off"></div><div><label for="a2_n">${esc(T('note'))}</label><input id="a2_n" autocomplete="off"></div>
    <button class="primary full" data-act="a2_marksave" data-v="${esc(id)}">${esc(T('save'))}</button></div>`);
}
let markClient = null;       // one key per open sheet: a double tap or a retry resends the SAME key
async function markSave(id) {
  const reason = ($('#a2_r').value || '').trim(); if (reason.length < 3) return toast(T('reason'));
  const rest = ($('#a2_rest').value || '').trim();
  if (!markClient || markClient.emp !== id) markClient = { emp: id, key: rid() };
  const args = { p_emp: id, p_day: D.day, p_status: $('#a2_s').value, p_in: $('#a2_in').value || null, p_out: $('#a2_out').value || null, p_rest_min: rest === '' ? null : Number(rest),
    p_source: $('#a2_src').value, p_reason: reason, p_note: ($('#a2_n').value || '').trim() || null, p_client: markClient.key };
  if (args.p_rest_min !== null && !(args.p_rest_min >= 0 && args.p_rest_min <= 720)) return toast(ERR.bad_rest ? lab(ERR.bad_rest) : 'rest');
  const x = ((D.board && D.board.rows) || []).find((r) => r.employee_id === id) || {};
  const res = await Q.send('attendance_mark_others', args, (x.name_en || x.name_bn || id) + ' · ' + args.p_status);
  if (res.error) return showErr(res.error);
  markClient = null; closeSheet(); toast(res.queued ? T('queued') : T('saved')); draw();
}

/* ================= staff & locks ================= */
async function staffHTML() {
  const r = await sb.rpc('att_staff_overview', { p_loc: D.loc }); if (r.error) return `<div class="a2-pick"><div>${locSel()}</div></div><p class="muted">${esc(eText(r.error))}</p>`;
  D.staff = r.data || { rows: [] }; const own = !!S.ctx.is_owner; const roles = [...new Set((D.staff.rows || []).map((x) => x.role).filter(Boolean))];
  const rl = Object.fromEntries((D.staff.role_locks || []).map((x) => [x.role, x.locked]));
  const rows = (D.staff.rows || []).map((x) => `<div class="card a2-row"><div class="nm"><b>${esc(lab({ bn: x.name_bn, en: x.name_en || x.name_bn, mix: x.name_bn }))}</b> <span class="muted">${esc(x.employee_no || '')}</span>
      <div>${(x.evidence || []).map((e) => `<span class="chip info">${esc(T('k_' + e.kind))}</span>`).join(' ')}</div></div>
      ${own ? `<button class="tog ${x.person_locked ? '' : 'on'}" role="switch" aria-checked="${!x.person_locked}" data-act="a2_lockp" data-v="${esc(x.employee_id)}" data-l="${x.person_locked ? 0 : 1}">${esc(T('lockP'))}: ${esc(x.person_locked ? T('locked') : T('open'))}</button>` : ''}</div>`).join('');
  const roleBox = own && roles.length ? `<div class="card stack"><b>${esc(T('roles'))}</b>${roles.map((c) => `<button class="tog ${rl[c] ? '' : 'on'}" role="switch" aria-checked="${!rl[c]}" data-act="a2_lockr" data-v="${esc(c)}" data-l="${rl[c] ? 0 : 1}">${esc(c)}: ${esc(rl[c] ? T('locked') : T('open'))}</button>`).join('')}</div>` : '';
  const geo = own ? `<button class="full" data-act="a2_geoset">${esc(T('geoSet'))}</button>` : '';
  const fin = `<div class="card stack"><label for="a2_fe">${esc(T('fingerFlag'))}</label><div class="a2-pick"><div><select id="a2_fe">${(D.staff.rows || []).map((x) => `<option value="${esc(x.employee_id)}">${esc(lab({ bn: x.name_bn, en: x.name_en || x.name_bn, mix: x.name_bn }))}</option>`).join('')}</select></div><div><input id="a2_fd" placeholder="device user id" maxlength="60"></div></div><button class="full" data-act="a2_finger">${esc(T('add'))}</button></div>`;
  return `<div class="a2-pick"><div>${locSel()}</div></div><p class="muted">${esc(T('master'))}: <b>${esc(D.staff.self_punch_master ? T('on') : T('off'))}</b></p>${roleBox}${geo}${rows || `<p class="muted">${esc(T('none'))}</p>`}${fin}${limitsBox()}`;
}

/* ================= counted once ================= */
async function countHTML() {
  const pick = `<div class="a2-pick"><div><label for="a2_loc">${esc(T('place'))}</label>${locSel()}</div><div><label for="a2_month">${esc(T('month'))}</label><input id="a2_month" type="month" value="${esc(D.month)}" max="${esc(today().slice(0, 7))}"></div></div>`;
  const r = await sb.rpc('attendance_count_once', { p_loc: D.loc, p_month: D.month + '-01' }); if (r.error) return pick + `<p class="muted">${esc(eText(r.error))}</p>`;
  const d = D.count = r.data || {}; const nf = (o) => (o ? `${esc(String(o.present))} ${esc(T('pres'))} · ${esc(String(o.late))} ${esc(T('late'))} · ${esc(String(o.absent))} ${esc(T('abs'))} · ${esc(String(o.ot_hours))} ${esc(T('ot'))}` : '–');
  const forms = (d.forms || []).map((f) => `<div class="a2-row"><span>02-1 #${esc(String(f.serial))} · ${esc(f.status)}</span><span class="chip ${f.is_shadow ? 'info' : 'ok'}">${esc(f.is_shadow ? T('shadow') : T('record'))}</span></div>`).join('');
  const rows = (d.rows || []).map((x) => `<div class="card stack ${x.mismatch ? 'a2-diff' : ''}"><div class="a2-row"><b class="nm">${esc(lab({ bn: x.name_bn, en: x.name_en || x.name_bn, mix: x.name_bn }))}</b><span class="chip ${x.mismatch ? 'bad' : 'ok'}">${esc(x.mismatch ? T('differ') : T('same'))}</span></div>
      <div class="a2-num muted">${esc(T('dev'))}: ${nf(x.device)}</div><div class="a2-num muted">${esc(T('frm'))}: ${nf(x.form)}</div></div>`).join('');
  return pick + `<div class="card stack"><div class="a2-row"><b>${esc(T('counted'))}</b><span class="chip ok">${esc(T('c_' + d.counted))}</span></div><div class="muted">${esc(T('a_has'))}: ${d.path_a_has_month ? '✓' : '✗'}</div>${forms}
    <button class="full" data-act="a2_link">${esc(T('linkNow'))}</button></div>${rows || `<p class="muted">${esc(T('none'))}</p>`}<p class="a2-lim">${esc(T('nameMatch'))}</p><p class="a2-lim">${esc(T('note14'))}</p>`;
}

/* ================= page ================= */
async function draw() {
  const el = $('#a2_body'); if (!el) return; let h = '';
  try { h = D.tab === 'me' ? await meHTML() : D.tab === 'mark' ? await markHTML() : D.tab === 'staff' ? await staffHTML() : await countHTML(); } catch (e) { h = `<p class="muted">${esc(eText(e))}</p>`; }
  if ($('#a2_body')) $('#a2_body').innerHTML = h;
}
async function view() {
  if (B.loadStatic) await B.loadStatic();
  const locs = LOCS(); if (!D.loc || !locs.find((l) => l.id === D.loc)) D.loc = (locs[0] || {}).id;
  shell(T('title'), `${tabsHTML([['me', 'tMe'], ['mark', 'tMark'], ['staff', 'tStaff'], ['count', 'tCount']])}<div id="a2_body"><p class="muted">…</p></div>`, true);
  try { await draw(); } catch (e) { fail(e); }
}
Q.subscribe(() => { if ($('#a2_body') && D.tab === 'mark') draw(); });
Object.assign(H, {
  a2_tab: (a) => { D.tab = a.dataset.v; $$('[data-act=a2_tab]').forEach((b) => b.setAttribute('aria-selected', String(b.dataset.v === D.tab))); draw(); },
  a2_punch: (a) => doPunch(a.dataset.v), a2_regpass: regPass, a2_regface: regFace,
  a2_evvoid: async (a) => { const why = window.prompt(T('why')); if (!why) return; const r = await sb.rpc('att_evidence_void', { p_id: Number(a.dataset.v), p_reason: why }); if (r.error) return showErr(r.error); toast(T('saved')); draw(); },
  a2_mark: (a) => { markClient = null; markSheet(a.dataset.v); }, a2_marksave: (a) => markSave(a.dataset.v),
  a2_qsend: async (a) => { await Q.retry(a.dataset.v); draw(); }, a2_qdrop: (a) => { if (window.confirm(T('discard') + '?')) Q.discard(a.dataset.v); },
  a2_lockp: async (a) => { const r = await sb.rpc('att_self_lock_set', { p_scope: 'person', p_ref: a.dataset.v, p_locked: a.dataset.l === '1', p_note: null }); if (r.error) return showErr(r.error); toast(T('saved')); draw(); },
  a2_lockr: async (a) => { const r = await sb.rpc('att_self_lock_set', { p_scope: 'role', p_ref: a.dataset.v, p_locked: a.dataset.l === '1', p_note: null }); if (r.error) return showErr(r.error); toast(T('saved')); draw(); },
  a2_geoset: async () => { const p = await getPos(); if (!p) return toast(T('geoF_no_fix')); const r = await sb.rpc('att_site_geo_set', { p_loc: D.loc, p_lat: p.lat, p_lng: p.lng }); if (r.error) return showErr(r.error); toast(T('geoSaved')); },
  a2_finger: async () => { const ref = ($('#a2_fd').value || '').trim(); if (!ref) return; const r = await sb.rpc('att_evidence_register', { p_emp: $('#a2_fe').value, p_kind: 'finger_device', p_ref: ref, p_label: 'device' }); if (r.error) return showErr(r.error); toast(T('saved')); draw(); },
  a2_link: async () => { const r = await sb.rpc('attendance_form_link_run', { p_loc: D.loc, p_month: D.month + '-01' }); if (r.error) return showErr(r.error); toast(T('linked') + ' ' + JSON.stringify(r.data.result || {})); draw(); },
});
document.addEventListener('change', (e) => {
  const t = e.target; if (!t || !$('#a2_body')) return;
  if (t.id === 'a2_loc') { D.loc = Number(t.value); draw(); } else if (t.id === 'a2_day') { D.day = t.value; draw(); } else if (t.id === 'a2_month') { D.month = t.value; draw(); }
});

/* ================= form equation check page (gap #20) ================= */
const EQ = { rows: [], res: {} };
async function eqView() {
  if (B.loadStatic) await B.loadStatic();
  shell(T('eqTitle'), `<p class="muted">${esc(T('eqIntro'))}</p><div id="eq_body"><p class="muted">…</p></div>`, true);
  try {
    const r = await sb.from('entries').select('id,form_code,serial,entry_date,status,location_id').in('form_code', ['10-2', '02-2']).order('entry_date', { ascending: false }).limit(30);
    if (r.error) throw r.error; EQ.rows = r.data || []; drawEq();
  } catch (e) { fail(e); }
}
function eqOne(x) {
  const c = EQ.res[x.id]; if (!c) return '';
  if (c.supported === false) return `<p class="muted">${esc(c.why || '')}</p>`;
  const rec = Object.entries(c.recomputed || {}).filter(([, v]) => v !== null).map(([k, v]) => `${esc(k)}: ${esc(String(v))}`).join(' · ');
  const mm = (c.mismatches || []).map((m) => `<div class="chip bad">${esc(m.code)} - ${esc(T('k_' + m.kind))} (${esc(String(m.stored))} → ${esc(String(m.recomputed))})</div>`).join('');
  const ob = (c.observations || []).map((m) => `<div class="chip info">${esc(T('obs'))}: ${esc(m.code)} ${esc(String(m.receipts_total))} / ${esc(String(m.sheet_net))}</div>`).join('');
  return `<div class="stack"><div class="a2-pre muted"><b>${esc(T('recomputed'))}</b> ${rec}</div>${c.ok ? `<span class="chip ok">${esc(T('allOk'))}</span>` : `<b>${esc(T('mism'))}</b>${mm}`}${ob}</div>`;
}
function drawEq() {
  const el = $('#eq_body'); if (!el) return;
  el.innerHTML = EQ.rows.map((x) => `<div class="card stack"><div class="a2-row"><b>${esc(x.form_code)} #${esc(String(x.serial))}</b><span class="muted">${esc(x.entry_date)} · ${esc(x.status)}</span><button class="mini" data-act="eq_check" data-v="${esc(x.id)}">${esc(T('check'))}</button></div>${eqOne(x)}</div>`).join('') || `<p class="muted">${esc(T('none'))}</p>`;
}
Object.assign(H, { eq_check: async (a) => { const r = await sb.rpc('entry_equation_check', { p_entry: a.dataset.v }); if (r.error) return showErr(r.error); EQ.res[a.dataset.v] = r.data; drawEq(); } });

window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { attend2: view, eqcheck: eqView });
})();
