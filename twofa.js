/* Islamia BOS · Two-factor sign-in (2FA, TOTP) · screen #/twofa for every signed-in user. Gap #18 (safe core).
   Uses Supabase Auth MFA (sb.auth.mfa.enroll / challenge / verify / unenroll / listFactors / getAuthenticatorAssuranceLevel). The owner must switch MFA on in the
   Supabase dashboard first (docs/TWOFA.md). Server side: supabase/phase71.sql (twofa_policy, twofa_status_report, optional guard on the most sensitive owner actions).
   Login hook: sb.auth.signInWithPassword is wrapped; PIN login is untouched unless the person HAS a verified factor, then a code is asked before the app opens.
   The PIN scheme (`${pin}-bos`) is NOT changed (#16 stays postponed). The overlay is a browser-side gate; the real server refusal is only the optional owner-actions guard. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const X = {
  title: L('দুই-ধাপ যাচাই (2FA)', 'Two-factor sign-in (2FA)', '২-ধাপ যাচাই (2FA)'),
  intro: L('পিনের পরে মোবাইলের অথেনটিকেটর অ্যাপের ৬ অঙ্কের কোড লাগবে। এতে পিন কেউ জেনে গেলেও একা ঢুকতে পারবে না।', 'After your PIN you also type a 6-digit code from an authenticator app on your phone. A leaked PIN alone then cannot open your account.', 'PIN-এর পরে phone-এর authenticator app-এর ৬ অঙ্কের code লাগবে। PIN জেনে গেলেও একা ঢোকা যাবে না।'),
  status: L('আপনার অবস্থা', 'Your status', 'আপনার অবস্থা'),
  on: L('চালু আছে ✓', 'ON ✓', 'চালু আছে ✓'), off: L('চালু নেই', 'OFF', 'চালু নেই'),
  lvl: L('এই সেশনের স্তর', 'This session level', 'এই session-এর level'),
  l1: L('শুধু পিন (aal1)', 'PIN only (aal1)', 'শুধু PIN (aal1)'), l2: L('পিন + কোড (aal2)', 'PIN + code (aal2)', 'PIN + code (aal2)'),
  facts: L('আপনার ফ্যাক্টর', 'Your factors', 'আপনার factor'), nofact: L('কোনো ফ্যাক্টর নেই', 'No factor yet', 'কোনো factor নেই'),
  verified: L('যাচাই-করা', 'verified', 'verified'), unver: L('অসম্পূর্ণ', 'not finished', 'অসম্পূর্ণ'),
  enroll: L('2FA চালু করুন', 'Turn 2FA on', '2FA চালু করুন'),
  scan: L('অথেনটিকেটর অ্যাপে (Google Authenticator, Microsoft Authenticator ইত্যাদি) এই QR স্ক্যান করুন। স্ক্যান না হলে নিচের গোপন কোড হাতে লিখুন।', 'Scan this QR with an authenticator app (Google Authenticator, Microsoft Authenticator, etc.). If scanning fails, type the secret below by hand.', 'Authenticator app-এ এই QR scan করুন। না হলে নিচের secret হাতে লিখুন।'),
  secret: L('গোপন কোড (কাউকে দেবেন না)', 'Secret (share with nobody)', 'Secret (কাউকে দেবেন না)'),
  code: L('অ্যাপের ৬ অঙ্কের কোড', '6-digit code from the app', 'App-এর ৬ অঙ্কের code'),
  verify: L('যাচাই করে চালু করুন', 'Verify and turn on', 'Verify করে চালু করুন'),
  cancel: L('বাতিল', 'Cancel', 'বাতিল'),
  off2: L('2FA বন্ধ করুন (কোড লাগবে)', 'Turn 2FA off (code needed)', '2FA বন্ধ করুন (code লাগবে)'),
  warn: L('ফোন হারালে বা অ্যাপ মুছলে আপনি লগইন করতে পারবেন না — তখন মালিককে বলুন, তিনি Supabase থেকে ফ্যাক্টর সরাবেন। এই অ্যাপে কোনো রিকভারি কোড নেই।', 'If you lose the phone or delete the app you cannot sign in - ask the owner, who removes the factor in Supabase. This app has NO recovery codes.', 'Phone হারালে বা app মুছলে login করা যাবে না — owner-কে বলুন, তিনি Supabase থেকে factor সরাবেন। এখানে recovery code নেই।'),
  nomfa: L('2FA এখনো সার্ভারে চালু করা হয়নি (মালিক Supabase ড্যাশবোর্ডে MFA চালু করবেন)।', '2FA is not enabled on the server yet (the owner turns MFA on in the Supabase dashboard).', '2FA server-এ এখনো চালু নেই (owner Supabase dashboard-এ MFA চালু করবেন)।'),
  pol: L('নীতি', 'Policy', 'নীতি'), must: L('আপনার ভূমিকায় 2FA লাগার কথা — এখনই চালু করুন।', 'Your role is expected to use 2FA - please turn it on now.', 'আপনার role-এ 2FA লাগার কথা — এখনই চালু করুন।'),
  blocked: L('সার্ভার-সুইচ চালু: মালিকের সংবেদনশীল কাজ করতে কোড দিয়ে আবার লগইন করতে হবে।', 'Server switch is ON: sensitive owner actions need a sign-in with a code.', 'Server switch চালু: owner-এর sensitive কাজে code দিয়ে আবার login লাগবে।'),
  rep: L('কার 2FA আছে (মালিক)', 'Who has 2FA (owner)', 'কার 2FA আছে (owner)'), run: L('দেখুন', 'Show', 'দেখুন'),
  missing: L('নেই — লাগার কথা', 'missing - expected', 'নেই — লাগার কথা'),
  done: L('2FA চালু হয়েছে', '2FA is on', '2FA চালু হয়েছে'), gone: L('2FA বন্ধ হয়েছে', '2FA is off', '2FA বন্ধ হয়েছে'),
  bad: L('কোড ভুল বা মেয়াদ শেষ', 'Wrong or expired code', 'Code ভুল বা মেয়াদ শেষ'), need6: L('৬ অঙ্কের কোড দিন', 'Enter the 6-digit code', '৬ অঙ্কের code দিন'),
  gtitle: L('কোড দিন', 'Enter your code', 'Code দিন'), gtext: L('আপনার অথেনটিকেটর অ্যাপ খুলে ৬ অঙ্কের কোড লিখুন।', 'Open your authenticator app and type the 6-digit code.', 'Authenticator app খুলে ৬ অঙ্কের code লিখুন।'),
  gok: L('ঢুকুন', 'Continue', 'ঢুকুন'), gout: L('লগ আউট', 'Sign out', 'লগ আউট'), tries: L('অনেকবার ভুল — লগ আউট করা হলো', 'Too many wrong codes - signed out', 'অনেকবার ভুল — logout করা হলো'),
  loading: L('লোড হচ্ছে…', 'Loading…', 'লোড হচ্ছে…'),
};
const T = (k) => lab(X[k]);
const D = { enr: null, busy: false, gating: false };
const mfa = () => sb.auth && sb.auth.mfa;
const digits = (v) => String(v || '').replace(/\D/g, '');

/* ---------- AAL helpers ---------- */
async function aal() {
  if (!mfa() || !mfa().getAuthenticatorAssuranceLevel) return null;
  const r = await mfa().getAuthenticatorAssuranceLevel();
  return r && !r.error ? r.data : null;
}
// true when the signed-in session has a verified factor but has not yet been raised to aal2
async function needsCode() {
  try { const a = await aal(); return !!(a && a.nextLevel === 'aal2' && a.currentLevel !== 'aal2'); } catch (e) { return false; }
}
async function factors() {
  const r = await mfa().listFactors();
  if (r.error) throw r.error;
  const all = (r.data && (r.data.all || r.data.totp)) || [];
  return all.filter((f) => !f.factor_type || f.factor_type === 'totp');
}
async function codeCheck(factorId, code) {
  const c = await mfa().challenge({ factorId });
  if (c.error) return c.error;
  const v = await mfa().verify({ factorId, challengeId: c.data.id, code });
  return v.error || null;
}

/* ---------- sign-in gate (overlay) ---------- */
function gate() {
  if (D.gating) return Promise.resolve(false);
  D.gating = true;
  return new Promise(async (resolve) => {
    let fs = [];
    try { fs = (await factors()).filter((f) => f.status === 'verified'); } catch (e) { fs = []; }
    const f = fs[0];
    if (!f) { D.gating = false; return resolve(true); }          // nothing to ask: PIN login as before
    const el = document.createElement('div'); el.id = 'tf_gate';
    el.style.cssText = 'position:fixed;inset:0;z-index:99999;background:rgba(20,23,58,.96);display:flex;align-items:center;justify-content:center;padding:16px';
    el.innerHTML = `<div class="card panel stack" style="max-width:340px;width:100%"><h2 style="margin:0">${esc(T('gtitle'))}</h2><p>${esc(T('gtext'))}</p>
      <div id="tf_gerr" class="notice bad" style="display:none"></div>
      <input id="tf_gcode" type="text" inputmode="numeric" autocomplete="one-time-code" maxlength="6" aria-label="${esc(T('code'))}">
      <button class="primary full" id="tf_gok" type="button">${esc(T('gok'))}</button><button class="full" id="tf_gout" type="button">${esc(T('gout'))}</button></div>`;
    document.body.appendChild(el);
    let tries = 0;
    const end = (ok) => { el.remove(); D.gating = false; resolve(ok); };
    const err = (m) => { const e = $('#tf_gerr', el); e.textContent = m; e.style.display = ''; };
    $('#tf_gcode', el).focus();
    $('#tf_gout', el).onclick = () => end(false);
    $('#tf_gok', el).onclick = async () => {
      const code = digits($('#tf_gcode', el).value);
      if (code.length !== 6) return err(T('need6'));
      const bad = await codeCheck(f.id, code);
      if (!bad) return end(true);
      tries++; $('#tf_gcode', el).value = '';
      if (tries >= 5) { err(T('tries')); setTimeout(() => end(false), 900); } else err(T('bad'));
    };
  });
}

// wrap the PIN sign-in: PIN login stays exactly as it was unless a verified factor exists
function wrapSignIn() {
  const au = sb.auth; if (!au || au.__tfWrapped || !au.signInWithPassword) return;
  const orig = au.signInWithPassword.bind(au);
  au.signInWithPassword = async (...args) => {
    const r = await orig(...args);
    if (!r || r.error || !(r.data && r.data.session)) return r;
    if (!(await needsCode())) return r;
    if (await gate()) return r;
    try { await au.signOut(); } catch (e) { /* already out */ }
    return { data: { user: null, session: null }, error: { message: 'twofa_cancelled' } };
  };
  au.__tfWrapped = true;
}
// a PIN-only session left over (page reloaded while the code box was open) must not slip into the app
async function bootCheck() {
  try {
    const { data } = await sb.auth.getSession();
    if (!(data && data.session) || D.gating || !(await needsCode())) return;
    if (!(await gate())) { try { await sb.auth.signOut(); } catch (e) { /* ignore */ } location.reload(); }
  } catch (e) { /* MFA not enabled: PIN login only */ }
}

/* ---------- screen ---------- */
function fRow(f) {
  return `<div class="row wrap" data-fid="${esc(f.id)}"><b>${esc(f.friendly_name || 'TOTP')}</b> <span class="chip ${f.status === 'verified' ? 'ok' : 'warn'}">${esc(T(f.status === 'verified' ? 'verified' : 'unver'))}</span></div>`;
}
async function draw() {
  const el = $('#tf_body'); if (!el) return;
  let fs = [], a = null, pol = null, mfaErr = '';
  try { fs = await factors(); a = await aal(); } catch (e) { mfaErr = e.message || String(e); }
  try { const r = await sb.rpc('twofa_policy'); if (!r.error) pol = r.data; } catch (e) { /* phase71 not pasted yet */ }
  if (mfaErr) { el.innerHTML = `<div class="card stack"><p>${esc(T('nomfa'))}</p><p class="muted" style="font-size:.8rem">${esc(mfaErr)}</p></div>`; return; }
  const ver = fs.filter((f) => f.status === 'verified'), on = ver.length > 0;
  const lvl = a && a.currentLevel === 'aal2' ? 'l2' : 'l1';
  el.innerHTML = `<p class="muted">${esc(T('intro'))}</p>
    <div class="card stack"><b>${esc(T('status'))}</b>
      <div class="row wrap"><span class="chip ${on ? 'ok' : 'warn'}" id="tf_state">${esc(T(on ? 'on' : 'off'))}</span><span class="muted">${esc(T('lvl'))}: <span id="tf_lvl">${esc(T(lvl))}</span></span></div>
      ${pol && pol.must_enroll ? `<div class="notice bad" id="tf_must">${esc(T('must'))}</div>` : ''}
      ${pol && pol.sensitive_actions_blocked_now ? `<div class="notice bad" id="tf_blk">${esc(T('blocked'))}</div>` : ''}
      <b>${esc(T('facts'))}</b>${fs.length ? fs.map(fRow).join('') : `<span class="muted">${esc(T('nofact'))}</span>`}
      ${on ? `<div><label>${esc(T('code'))}</label><input id="tf_off_code" inputmode="numeric" maxlength="6" autocomplete="one-time-code"></div>
        <button class="btn full" type="button" data-act="tf_unenroll" data-fid="${esc(ver[0].id)}">${esc(T('off2'))}</button>`
        : `<button class="primary full" type="button" data-act="tf_enroll">${esc(T('enroll'))}</button>`}
      <div class="notice" id="tf_warn">${esc(T('warn'))}</div></div>
    <div id="tf_enroll"></div>
    ${A.S && A.S.ctx && A.S.ctx.is_owner ? `<div class="card stack"><b>${esc(T('rep'))}</b><button class="btn" type="button" data-act="tf_report">${esc(T('run'))}</button><div id="tf_rep"></div></div>` : ''}`;
  if (D.enr) drawEnroll();
}
function drawEnroll() {
  const el = $('#tf_enroll'); if (!el || !D.enr) return;
  const e = D.enr;
  el.innerHTML = `<div class="card stack"><p>${esc(T('scan'))}</p>
    <img id="tf_qr" alt="QR" src="${esc(e.qr)}" style="width:200px;height:200px;max-width:100%;background:#fff;align-self:center">
    <div><label>${esc(T('secret'))}</label><code id="tf_secret" style="word-break:break-all;user-select:all">${esc(e.secret)}</code></div>
    <div><label>${esc(T('code'))}</label><input id="tf_code" inputmode="numeric" maxlength="6" autocomplete="one-time-code"></div>
    <div class="row wrap"><button class="primary" type="button" data-act="tf_verify">${esc(T('verify'))}</button><button class="btn" type="button" data-act="tf_cancel">${esc(T('cancel'))}</button></div></div>`;
}
async function dropHalf() {   // an unfinished enrolment blocks a new one with the same name: clear them first
  for (const f of (await factors()).filter((x) => x.status !== 'verified')) await mfa().unenroll({ factorId: f.id });
}
Object.assign(H, {
  tf_enroll: async () => {
    await dropHalf();
    const r = await mfa().enroll({ factorType: 'totp', friendlyName: 'BOS-' + Date.now().toString(36) });
    if (r.error) return fail(r.error);
    D.enr = { id: r.data.id, qr: r.data.totp.qr_code, secret: r.data.totp.secret }; drawEnroll();
  },
  tf_cancel: async () => { if (D.enr) { try { await mfa().unenroll({ factorId: D.enr.id }); } catch (e) { /* ignore */ } } D.enr = null; await draw(); },
  tf_verify: async () => {
    const code = digits($('#tf_code').value); if (code.length !== 6) return toast(T('need6'));
    const bad = await codeCheck(D.enr.id, code); if (bad) return toast(T('bad'));
    D.enr = null; toast(T('done')); await draw();
  },
  tf_unenroll: async (a) => {
    const code = digits($('#tf_off_code').value); if (code.length !== 6) return toast(T('need6'));
    const bad = await codeCheck(a.dataset.fid, code); if (bad) return toast(T('bad'));      // Supabase wants aal2 before it removes a verified factor
    const r = await mfa().unenroll({ factorId: a.dataset.fid }); if (r.error) return fail(r.error);
    toast(T('gone')); await draw();
  },
  tf_report: async () => {
    const r = await sb.rpc('twofa_status_report'); if (r.error) return fail(r.error);
    $('#tf_rep').innerHTML = ((r.data && r.data.users) || []).map((u) => `<div class="row wrap"><b>${esc(u.name || u.staff_id)}</b> <span class="muted">${esc((u.roles || []).join(', '))}</span> <span class="chip ${u.has_2fa ? 'ok' : (u.missing ? 'bad' : 'warn')}">${esc(u.has_2fa ? T('on') : (u.missing ? T('missing') : T('off')))}</span></div>`).join('') || `<span class="muted">-</span>`;
  },
});
async function viewTwofa() {
  shell(T('title'), `<div id="tf_body"><p class="muted">${esc(T('loading'))}</p></div>`, true);
  try { await draw(); } catch (e) { fail(e); }
}

window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { twofa: viewTwofa });
window.BOS_TWOFA = { gate, needsCode, wrapSignIn, bootCheck };
wrapSignIn();
bootCheck();
})();
