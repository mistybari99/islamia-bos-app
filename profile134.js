/* Islamia BOS · Business profile (#/profile): the name, logo, address, phone, email, receipt header / footer and colour of ONE business. Owner, or the holder of the org_manage right inside that business.
   Server (supabase/phase134.sql): business_profile_get(p_biz) -> jsonb (can_edit, trade_licence_ref only for the owner / manager), business_profile_save(p_biz, p_patch jsonb, p_client uuid) -> jsonb {dup,id}.
   The business list comes from bizctx (B.biz.list()): the server returns only the caller's own business, so a person of one business never sees a picker, a group or another business; the owner with
   several businesses gets a picker. No business name is written in this file. The logo is a photo of the private bucket (path stored, signed URL shown). */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const rid = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : 'p' + Date.now().toString(36) + Math.random().toString(36).slice(2, 10));
const X = {
  title: L('ব্যবসার প্রোফাইল', 'Business profile', 'Business প্রোফাইল'), biz: L('ব্যবসা', 'Business', 'Business'),
  nbn: L('নাম (বাংলা)', 'Name (Bangla)', 'নাম (বাংলা)'), nen: L('নাম (ইংরেজি)', 'Name (English)', 'নাম (English)'), sn: L('ছোট নাম', 'Short name', 'ছোট নাম'),
  logo: L('লোগো', 'Logo', 'Logo'), pick: L('লোগো বেছে নিন', 'Choose a logo', 'Logo বাছুন'), clear: L('লোগো সরান', 'Remove logo', 'Logo সরান'),
  addr: L('ঠিকানা', 'Address', 'ঠিকানা'), phone: L('ফোন', 'Phone', 'ফোন'), email: L('ইমেইল', 'Email', 'Email'),
  rh: L('রসিদের উপরের লেখা', 'Receipt header', 'Receipt-এর উপরের লেখা'), rf: L('রসিদের নিচের লেখা', 'Receipt footer', 'Receipt-এর নিচের লেখা'),
  color: L('থিম রং', 'Theme colour', 'Theme রং'), lic: L('ট্রেড লাইসেন্স নম্বর', 'Trade licence number', 'Trade licence নম্বর'),
  save: L('সেভ', 'Save', 'Save'), saved: L('সেভ হয়েছে', 'Saved', 'Saved'), view: L('শুধু দেখা যাবে; বদলাতে মালিকের অনুমতি লাগবে।', 'View only; changing it needs the owner or the organization right.', 'শুধু দেখা যাবে; বদলাতে owner-এর অনুমতি লাগবে।'),
  err: L('সেভ করা যায়নি', 'Could not save', 'Save করা যায়নি'),
};
const ERR = {
  not_allowed: L('অনুমতি নেই', 'Not allowed', 'অনুমতি নেই'), bad_name: L('নাম ঠিক নয় (১-১২০ অক্ষর)', 'Name is not valid (1-120 characters)', 'নাম ঠিক নয়'),
  bad_phone: L('ফোন নম্বর ঠিক নয়', 'Phone number is not valid', 'Phone নম্বর ঠিক নয়'), bad_email: L('ইমেইল ঠিক নয়', 'Email is not valid', 'Email ঠিক নয়'),
  bad_color: L('রং #RRGGBB হতে হবে', 'Colour must look like #RRGGBB', 'রং #RRGGBB হতে হবে'), bad_logo: L('লোগো ঠিক নয়', 'Logo is not valid', 'Logo ঠিক নয়'),
  bad_receipt_text: L('লেখা খুব বড় (৩০০ অক্ষর)', 'Text is too long (300 characters)', 'লেখা খুব বড়'), bad_address: L('ঠিকানা খুব বড়', 'Address is too long', 'ঠিকানা খুব বড়'),
};
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).find((x) => m.includes(x) || m.includes(x.replace(/_/g, ' '))); return k ? lab(ERR[k]) : m || 'error'; };
const P = { biz: null, d: null, logo: null };
const FIELD = { display_name_bn: 'pf_nbn', display_name_en: 'pf_nen', short_name: 'pf_sn', address: 'pf_addr', phone: 'pf_phone', email: 'pf_email', receipt_header: 'pf_rh', receipt_footer: 'pf_rf', theme_color: 'pf_color', trade_licence_ref: 'pf_lic' };
function row(id, label, val, dis, extra) { return `<div><label for="${id}">${esc(lab(label))}</label><input id="${id}" autocomplete="off" maxlength="300" value="${esc(val == null ? '' : val)}" ${dis ? 'disabled' : ''} ${extra || ''}></div>`; }
function form() {
  const d = P.d, ed = !!d.can_edit, el = $('#pf_body'); if (!el) return;
  const picker = B.biz && B.biz.list().length > 1 ? `<div><label for="pf_biz">${esc(lab(X.biz))}</label><select id="pf_biz">${B.biz.list().map((b) => `<option value="${b.id}" ${b.id === P.biz ? 'selected' : ''}>${esc(S.lang === 'en' ? (b.name_en || b.name_bn) : (b.name_bn || b.name_en))}</option>`).join('')}</select></div>` : '';
  el.innerHTML = `<div class="card stack">${picker}${ed ? '' : `<p class="muted">${esc(lab(X.view))}</p>`}
    ${row('pf_nbn', X.nbn, d.display_name_bn, !ed)}${row('pf_nen', X.nen, d.display_name_en, !ed)}${row('pf_sn', X.sn, d.short_name, !ed)}
    <div><label>${esc(lab(X.logo))}</label><div class="row" style="gap:8px;align-items:center;flex-wrap:wrap"><img id="pf_logo" alt="" style="max-height:56px;max-width:120px;${P.logo ? '' : 'display:none'}" ${P.logo ? `src="${esc(P.logo)}"` : ''}>
      ${ed ? `<input id="pf_file" type="file" accept="image/*" hidden><button class="mini" style="min-height:40px" data-act="pf_pick">${esc(lab(X.pick))}</button><button class="mini" style="min-height:40px" data-act="pf_clear">${esc(lab(X.clear))}</button>` : ''}</div></div>
    ${row('pf_addr', X.addr, d.address, !ed)}${row('pf_phone', X.phone, d.phone, !ed, 'inputmode="tel"')}${row('pf_email', X.email, d.email, !ed, 'inputmode="email"')}
    ${row('pf_rh', X.rh, d.receipt_header, !ed)}${row('pf_rf', X.rf, d.receipt_footer, !ed)}
    <div><label for="pf_color">${esc(lab(X.color))}</label><input id="pf_color" type="color" value="${esc(d.theme_color || '#a1111e')}" ${ed ? '' : 'disabled'}></div>
    ${ed ? row('pf_lic', X.lic, d.trade_licence_ref, false) : ''}
    <div id="pf_err" class="muted" role="alert"></div>
    ${ed ? `<button class="full primary" style="min-height:44px" data-act="pf_save">${esc(lab(X.save))}</button>` : ''}</div>`;
}
async function loadLogo() {
  P.logo = null; const path = P.d && P.d.logo_path; if (!path) return;
  try { const r = await sb.storage.from('photos').createSignedUrl(path, 3600); P.logo = r && r.data ? r.data.signedUrl : null; } catch (e) { P.logo = null; }
}
async function load(biz) {
  const r = await sb.rpc('business_profile_get', { p_biz: biz == null ? null : biz });
  if (r.error) throw r.error;
  P.d = r.data; P.biz = Number(P.d.business_id); P.newLogo = undefined; await loadLogo(); form();
}
Object.assign(H, {
  pf_pick: () => { const f = $('#pf_file'); if (f) f.click(); },
  pf_clear: () => { P.newLogo = ''; P.logo = null; const i = $('#pf_logo'); if (i) i.style.display = 'none'; },
  pf_save: async () => {
    const err = (m) => { const e = $('#pf_err'); if (e) e.textContent = m; else toast(m); };
    const patch = {}; Object.keys(FIELD).forEach((k) => { const el = $('#' + FIELD[k]); if (el) patch[k] = el.value.trim(); });
    if (patch.theme_color === '#a1111e' && !(P.d && P.d.theme_color)) delete patch.theme_color;   // untouched default
    if (P.newLogo !== undefined) patch.logo_path = P.newLogo;
    if (!patch.display_name_bn) return err(lab(ERR.bad_name));
    try { const r = await sb.rpc('business_profile_save', { p_biz: P.biz, p_patch: patch, p_client: rid() }); if (r.error) return err(eText(r.error)); toast(lab(X.saved)); if (B.biz && B.biz.reload) await B.biz.reload(); await load(P.biz); } catch (e) { err(eText(e)); }
  },
});
document.addEventListener('change', async (e) => {
  if (!e.target) return;
  if (e.target.id === 'pf_biz') { try { await load(Number(e.target.value)); } catch (x) { fail(x); } }
  if (e.target.id === 'pf_file' && e.target.files && e.target.files[0]) {
    try {
      const U = B.s2; if (!U || !U.uploadPhoto) throw new Error('photo');
      const loc = ((B.ENV.locsAll || B.ENV.locs || []).find((l) => B.biz.locBizId(l) === P.biz) || (B.ENV.locs || [])[0] || {}).id;
      toast('…'); const path = await U.uploadPhoto(e.target.files[0], ['STOCK'], loc); P.newLogo = path;
      const r = await sb.storage.from('photos').createSignedUrl(path, 3600); P.logo = r && r.data ? r.data.signedUrl : null;
      const i = $('#pf_logo'); if (i && P.logo) { i.src = P.logo; i.style.display = ''; }
    } catch (x) { const m = $('#pf_err'); if (m) m.textContent = lab(ERR.bad_logo); }
  }
});
async function view() {
  if (B.loadStatic) await B.loadStatic();
  shell(lab(X.title), '<div id="pf_body" class="stack"><p class="muted">…</p></div>', true);
  try { await load(null); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { profile: view });
})();
