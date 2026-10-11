/* Islamia BOS · editable lists (owner): expense heads, marketing heads with their monthly limit, payment services (bKash / Nagad ...).
   Add, rename, reorder, switch off. Nothing is deleted (old entries keep showing their old choice). */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, t, esc, toast, fail, shell } = A;
const $ = (s, el = document) => el.querySelector(s);
const L = B.L, lab = B.lab;
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d));
const LISTS = {
  expense_heads: { title: L('খরচের খাত (ব্যয় ভাউচার)', 'Expense heads (expense voucher)', 'খরচের খাত (Expense voucher)'), extra: [] },
  marketing_heads: { title: L('মার্কেটিং খাত ও মাসিক সীমা', 'Marketing heads and monthly limit', 'Marketing খাত ও মাসিক limit'), extra: [{ key: 'limit_month', label: L('মাসের সীমা (৳)', 'Monthly limit (৳)', 'মাসের Limit (৳)'), kind: 'number' }] },
  wallets: { title: L('মোবাইল পেমেন্ট মাধ্যম (বিকাশ, নগদ…)', 'Mobile payment services (bKash, Nagad…)', 'Mobile payment মাধ্যম (bKash, Nagad…)'), extra: [] },
};
const X = {
  title: L('তালিকা সম্পাদনা', 'Edit lists', 'List Edit'), hint: L('এখানে বদলালে ফর্মের বাছাই-তালিকা বদলে যায়। কিছু মোছা হয় না, শুধু বন্ধ করা যায়, তাই পুরনো এন্ট্রি ঠিক থাকে।', 'Changes here change the choices in the forms. Nothing is deleted, you can only switch an item off, so old entries stay correct.', 'এখানে বদলালে form এর choice বদলায়। কিছু মোছা হয় না, শুধু বন্ধ করা যায়, তাই পুরনো entry ঠিক থাকে।'),
  bn: L('বাংলা নাম', 'Bangla name', 'বাংলা নাম'), en: L('ইংরেজি নাম', 'English name', 'English নাম'), mix: L('Bng-Eng নাম (ঐচ্ছিক)', 'Bng-Eng name (optional)', 'Bng-Eng নাম (ঐচ্ছিক)'),
  add: L('＋ নতুন যোগ', '＋ Add new', '＋ নতুন Add'), save: L('সংরক্ষণ', 'Save', 'Save'), on: L('চালু', 'On', 'On'), off: L('বন্ধ', 'Off', 'Off'), saved: L('সংরক্ষিত', 'Saved', 'Saved'), needbn: L('বাংলা নাম লিখুন', 'Enter the Bangla name', 'বাংলা নাম লিখুন'),
  missing: L('এই তালিকা ডেটাবেসে নেই — নতুন SQL চালাতে হবে', 'This list is not in the database yet — the new SQL must be run', 'এই list database এ নেই — নতুন SQL চালাতে হবে'), nolimit: L('(সীমা লেখা নেই)', '(no limit written)', '(limit লেখা নেই)'),
};
const T = (k) => lab(X[k]);
const D = { code: 'expense_heads', rows: [], err: null };

async function view() {
  shell(T('title'), `<p class="muted">${esc(t('loading'))}</p>`, true);
  await B.loadStatic(); await B.reloadLists();
  draw();
}
async function draw() {
  const r = await sb.from('option_lists').select('*').eq('list_code', D.code).order('sort'); D.err = r.error; D.rows = r.data || [];
  const def = LISTS[D.code];
  shell(T('title'), `<div class="notice ok">${esc(T('hint'))}</div>
    <div class="row wrap" style="margin-bottom:10px">${Object.keys(LISTS).map((c) => `<button class="tog ${D.code === c ? 'on' : ''}" data-act="ls2_pick" data-v="${c}">${esc(lab(LISTS[c].title))}</button>`).join('')}</div>
    ${D.err ? `<div class="notice bad">${esc(T('missing'))}</div>` : ''}
    ${D.rows.map((x, i) => `<div class="card stack" style="${x.active ? '' : 'opacity:.6'}"><div class="row between"><b>${i + 1}</b><div class="row">
        <button class="mini" data-act="ls2_move" data-c="${esc(x.value_code)}" data-d="-1" aria-label="up">↑</button><button class="mini" data-act="ls2_move" data-c="${esc(x.value_code)}" data-d="1" aria-label="down">↓</button>
        <button class="tog ${x.active ? 'on' : ''}" data-act="ls2_toggle" data-c="${esc(x.value_code)}">${esc(x.active ? T('on') : T('off'))}</button></div></div>
      <div><label>${esc(T('bn'))}</label><input id="l2_bn_${esc(x.value_code)}" value="${esc(x.label_bn)}"></div>
      <div><label>${esc(T('en'))}</label><input id="l2_en_${esc(x.value_code)}" value="${esc(x.label_en || '')}"></div>
      <div><label>${esc(T('mix'))}</label><input id="l2_mix_${esc(x.value_code)}" value="${esc(x.label_mix || '')}"></div>
      ${def.extra.map((e) => `<div><label>${esc(lab(e.label))}</label><input id="l2_x_${e.key}_${esc(x.value_code)}" inputmode="decimal" value="${x.extra && x.extra[e.key] !== undefined && x.extra[e.key] !== null ? esc(String(x.extra[e.key])) : ''}" placeholder="${esc(T('nolimit'))}"></div>`).join('')}
      <button class="primary full" data-act="ls2_save" data-c="${esc(x.value_code)}">${esc(T('save'))}</button></div>`).join('')}
    ${D.err ? '' : `<button class="full" data-act="ls2_new">${esc(T('add'))}</button>`}`, true);
}
const rowOf = (c) => D.rows.find((x) => x.value_code === c);
async function upsert(row) { const { error } = await sb.from('option_lists').upsert(row, { onConflict: 'list_code,value_code' }); if (error) { fail(error); return false; } await B.reloadLists(); if (B.pay && B.pay.resetWallets) B.pay.resetWallets(); return true; }
Object.assign(A.H, {
  ls2_pick: (a) => { D.code = a.dataset.v; draw(); },
  ls2_toggle: async (a) => { const x = rowOf(a.dataset.c); if (!x.active && x.label_bn === '—') return toast(T('needbn')); if (await upsert({ ...x, active: !x.active })) draw(); },
  ls2_move: async (a) => {
    const i = D.rows.findIndex((x) => x.value_code === a.dataset.c), j = i + Number(a.dataset.d); if (j < 0 || j >= D.rows.length) return;
    const order = D.rows.slice(); [order[i], order[j]] = [order[j], order[i]];
    const rows = order.map((r, k) => ({ ...r, sort: k + 1 }));                       // renumber 1..n in one write (no ties, nothing half-done)
    const { error } = await sb.from('option_lists').upsert(rows, { onConflict: 'list_code,value_code' }); if (error) return fail(error);
    await B.reloadLists(); if (B.pay && B.pay.resetWallets) B.pay.resetWallets(); draw();
  },
  ls2_save: async (a) => {
    const c = a.dataset.c, x = rowOf(c), def = LISTS[D.code], bn = ($('#l2_bn_' + c).value || '').trim(); if (!bn) return toast(T('needbn'));
    const extra = { ...(x.extra || {}) };
    for (const e of def.extra) { const raw = norm(($('#l2_x_' + e.key + '_' + c).value || '').trim()); if (raw === '') delete extra[e.key]; else { const n = Number(raw); if (!Number.isFinite(n) || n < 0) return toast(t('err_price')); extra[e.key] = n; } }
    if (await upsert({ ...x, label_bn: bn, label_en: ($('#l2_en_' + c).value || '').trim() || null, label_mix: ($('#l2_mix_' + c).value || '').trim() || null, extra })) { toast(T('saved')); draw(); }
  },
  ls2_new: async () => {
    const max = D.rows.reduce((m, x) => Math.max(m, x.sort), 0), code = 'x' + Date.now().toString(36);
    if (await upsert({ list_code: D.code, value_code: code, label_bn: '—', label_en: null, label_mix: null, sort: max + 1, active: false, extra: {} })) draw();
  },
});
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { lists: view });
})();
