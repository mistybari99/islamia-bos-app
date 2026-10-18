/* Islamia BOS · PIN signatures (rule 10; supabase/phase18.sql).
   A second signature is a DIFFERENT login with its own PIN, on the same phone. SQL cannot check another person's password, so the browser
   signs that person in on a second, throw-away Supabase client (no stored session) and calls sign_entry with THAT client: auth.uid() on
   the server is the signer. The server refuses the maker, the same login twice, a role signed twice, someone without access to the place and a locked login.
   A wrong PIN goes through login_failed (5 tries, then the lock of phase11); a locked person is refused before any sign-in is tried.
   The PIN is never stored or logged, and the second session is dropped at once. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, t, esc, toast, fail, openSheet, closeSheet } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const SID_RE = /^[a-z0-9]{3,20}$/i, PIN_RE = /^\d{4,6}$/;

const X = {
  title: L('পিন দিয়ে স্বাক্ষর', 'Sign with PIN', 'PIN দিয়ে sign'), who: L('স্বাক্ষরকারী', 'Signer', 'Signer'), pin: L('স্বাক্ষরকারীর নিজের পিন', "Signer's own PIN", 'Signer-এর নিজের PIN'),
  pick: L('— নাম বেছে নিন —', '- pick a name -', '— নাম বেছে নিন —'), go: L('স্বাক্ষর করুন', 'Sign', 'Sign করুন'), cancel: L('বাতিল', 'Cancel', 'Cancel'),
  done: L('স্বাক্ষর হয়েছে', 'Signed', 'Sign হয়েছে'),
  e_staff: L('স্বাক্ষরকারী বেছে নিন', 'Pick the signer', 'Signer বেছে নিন'), e_pin: L('পিন ৪–৬ সংখ্যার', 'PIN is 4-6 digits', 'PIN ৪–৬ সংখ্যার'),
  e_self: L('লেখক নিজে স্বাক্ষর করতে পারবেন না', 'The writer cannot sign', 'লেখক নিজে sign করতে পারবেন না'),
  e_locked: L('এই লগইন ভুল পিনে তালাবদ্ধ — ১০ মিনিট পরে চেষ্টা করুন', 'This login is locked after wrong PINs - try in 10 minutes', 'এই login ভুল PIN-এ locked — ১০ মিনিট পরে চেষ্টা করুন'),
  e_login: L('স্টাফ আইডি বা পিন ঠিক নয়', 'Staff ID or PIN is not correct', 'Staff ID বা PIN ঠিক নয়'),
};

// Core (also used by the test): returns { ok:true, staff } or { ok:false, code, message }
async function signWithPin({ entryId, role, staffId, pin }) {
  const sid = String(staffId || '').trim().toLowerCase(), cfg = window.BOS_CONFIG || {};
  if (!SID_RE.test(sid)) return { ok: false, code: 'staff' };
  if (!PIN_RE.test(String(pin || ''))) return { ok: false, code: 'pin' };
  if (S.ctx && S.ctx.profile && String(S.ctx.profile.staff_id || '').toLowerCase() === sid) return { ok: false, code: 'self' };
  const pre = await sb.rpc('login_precheck', { p_staff: sid });
  if (pre.data && pre.data.locked) return { ok: false, code: 'locked' };
  const c2 = window.supabase.createClient(cfg.url, cfg.key, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false, storageKey: 'bos-second-signer' } });
  try {
    const li = await c2.auth.signInWithPassword({ email: `${sid}@${cfg.emailDomain}`, password: `${pin}-bos` });
    if (li.error) { await sb.rpc('login_failed', { p_staff: sid }); return { ok: false, code: 'login' }; }
    const r = await c2.rpc('sign_entry', { p_entry: entryId, p_role: role });
    if (r.error) return { ok: false, code: 'server', message: String(r.error.message || '') };
    try { await c2.rpc('login_success'); } catch (e) { /* the counter reset is a convenience */ }
    return { ok: true, staff: (r.data && r.data.signer_staff) || sid };
  } finally { try { await c2.auth.signOut({ scope: 'local' }); } catch (e) { /* the session was never stored */ } }
}
B.signWithPin = signWithPin;

function pinSign({ entryId, role, exclude, onDone }) {
  const me = String((S.ctx && S.ctx.profile && S.ctx.profile.staff_id) || '').toLowerCase(), ex = (exclude || []).map((x) => String(x).toLowerCase());
  const staff = ((B.ENV && B.ENV.staff) || []).filter((s) => s.staff_id && s.staff_id.toLowerCase() !== me && !ex.includes(s.staff_id.toLowerCase()));
  openSheet(`<h2>${esc(lab(X.title))}</h2><div class="stack">
    <div><label>${esc(lab(X.who))}</label><select id="ps_staff"><option value="">${esc(lab(X.pick))}</option>${staff.map((s) => `<option value="${esc(s.staff_id)}">${esc(s.full_name || s.staff_id)} (${esc(s.staff_id)})</option>`).join('')}</select></div>
    <div><label>${esc(lab(X.pin))}</label><input id="ps_pin" type="password" inputmode="numeric" maxlength="6" autocomplete="off"></div>
    <div class="notice bad" id="ps_err" hidden></div>
    <div class="row"><button class="full" data-act="closesheet">${esc(lab(X.cancel))}</button><button class="primary full" data-act="ps_go">${esc(lab(X.go))}</button></div></div>`);
  A.psCb = async () => {
    const err = (m) => { const el = $('#ps_err'); if (el) { el.textContent = m; el.hidden = false; } };
    const btn = document.querySelector('[data-act="ps_go"]'); if (btn) btn.disabled = true;
    const pin = ($('#ps_pin') || {}).value, staffId = ($('#ps_staff') || {}).value;
    let r; try { r = await signWithPin({ entryId, role, staffId, pin }); } catch (e) { r = { ok: false, code: 'net', message: String((e && e.message) || '') }; }
    if (btn) btn.disabled = false;
    if (!r.ok) {
      if (r.code === 'staff') return err(lab(X.e_staff)); if (r.code === 'pin') return err(lab(X.e_pin)); if (r.code === 'self') return err(lab(X.e_self));
      if (r.code === 'locked') return err(lab(X.e_locked)); if (r.code === 'login') return err(lab(X.e_login));
      const m = B.X17 && Object.keys(B.X17).filter((k) => k.startsWith('e_')).find((k) => (r.message || '').includes(k.slice(2)));
      return err(m ? lab(B.X17[m]) : (r.message || t('err_generic')));
    }
    closeSheet(); toast(lab(X.done)); if (onDone) onDone(r.staff);
  };
}
B.pinSign = pinSign;
Object.assign(A.H, { ps_go: () => A.psCb && A.psCb() });
})();
