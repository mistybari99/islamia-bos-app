/* Islamia BOS · message texts for SMS / WhatsApp / Email (phase 93): invoice message and due reminder, 6 variants each.
   BOS.tpl.render('msg_invoice' | 'msg_due', data, variantId, { lang, channel }) returns PLAIN TEXT (email: first line "Subject: ...", blank line, body).
   The text never contains < or > from the data (control characters and angle brackets are removed), so it is safe even if a caller drops it into HTML.
   data: { customer, no, date, total, paid, due, due_date, items: [{name, qty, amount}], link }. Nothing about cost exists here. */
(() => {
'use strict';
const T = window.BOS.tpl;
T.addLabels({
  g_msg: ['Messages', 'মেসেজ', 'Message'], d_msginv: ['Invoice message (SMS / WhatsApp / Email)', 'ইনভয়েস মেসেজ (SMS / WhatsApp / Email)', 'Invoice message (SMS / WhatsApp / Email)'],
  d_msgdue: ['Due reminder (SMS / WhatsApp / Email)', 'বাকি তাগাদা (SMS / WhatsApp / Email)', 'Due reminder (SMS / WhatsApp / Email)'],
  r_msginv: ['Medium works on every channel; use Short for SMS to keep it one message.', 'সব চ্যানেলে মাঝারি চলে; SMS-এ এক মেসেজে রাখতে সংক্ষিপ্ত।', 'সব channel-এ Medium চলে; SMS-এ এক message রাখতে Short।'],
  r_msgdue: ['Friendly first, Formal only for an old due.', 'প্রথমবার বন্ধুসুলভ, পুরনো বাকিতে তবেই আনুষ্ঠানিক।', 'প্রথমবার Friendly, পুরনো due-তে তবেই Formal।'],
});
const cl = (s) => String(s === null || s === undefined ? '' : s).replace(/[\u0000-\u001f\u007f<>]+/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 80);
// a link is kept whole: only http(s), no spaces / control characters / angle brackets / quotes, no length cap
const link = (u) => { u = String(u === null || u === undefined ? '' : u).replace(/[\u0000-\u0020\u007f<>"']+/g, ''); return /^https?:\/\/[^\s]+$/i.test(u) ? u : ''; };
T.waUrl = (text) => 'https://wa.me/?text=' + encodeURIComponent(String(text === null || text === undefined ? '' : text));
const NAMES = { short: ['Short', 'সংক্ষিপ্ত', 'Short'], medium: ['Medium', 'মাঝারি', 'Medium'], detailed: ['Detailed', 'বিস্তারিত', 'Detailed'], friendly: ['Friendly', 'বন্ধুসুলভ', 'Friendly'], formal: ['Formal', 'আনুষ্ঠানিক', 'Formal'], bilingual: ['Bilingual (Bangla + English)', 'দুই ভাষায় (বাংলা + English)', 'দুই ভাষায় (Bangla + English)'] };
const mkT = () => Object.keys(NAMES).map((id) => ({ id, name: NAMES[id], page: 'text', look: id }));
function vals(d, lg) {
  const shop = Object.assign({}, T.shop, d.shop || {}), M = (v) => (T.has(v) && Number.isFinite(Number(v)) ? T.money(v, lg) : '');
  return { shop: cl(shop.name) || T.lbl('ph_shop', lg), cu: cl(d.customer), no: cl(d.no), date: cl(d.date), due_date: cl(d.due_date), total: M(d.total), paid: M(d.paid), due: M(d.due), link: link(d.link),
    items: Array.isArray(d.items) ? d.items.filter((i) => i && typeof i === 'object').slice(0, 12).map((i) => cl(i.name) + ' x' + cl(i.qty) + (T.has(i.amount) ? ' ' + M(i.amount) : '')) : [] };
}
// text banks: EN = pure English; BN = Bangla with the common words kept in English (Invoice, Tk, Due ...)
const INV = {
  en: {
    short: (v) => `${v.shop}: Invoice ${v.no}, total ${v.total}.${v.link ? ' ' + v.link : ''}`,
    medium: (v) => `Dear ${v.cu || 'customer'}, thank you for shopping at ${v.shop}. Invoice ${v.no} dated ${v.date}: total ${v.total}, paid ${v.paid}${v.due ? ', due ' + v.due : ''}.${v.link ? ' View: ' + v.link : ''}`,
    detailed: (v) => `Dear ${v.cu || 'customer'},\nThank you for shopping at ${v.shop}.\nInvoice: ${v.no}\nDate: ${v.date}\n${v.items.map((i) => '- ' + i).join('\n')}\nTotal: ${v.total}\nPaid: ${v.paid}\n${v.due ? 'Due: ' + v.due + '\n' : ''}${v.link ? 'View your invoice: ' + v.link + '\n' : ''}Regards, ${v.shop}`,
    friendly: (v) => `Hi ${v.cu || 'there'}! Thanks a lot for visiting ${v.shop}. Your bill ${v.no} is ${v.total}${v.due ? ' and ' + v.due + ' is still due' : ', all paid'}. See you again soon!${v.link ? ' ' + v.link : ''}`,
    formal: (v) => `Dear ${v.cu || 'Sir/Madam'},\nThis is to confirm invoice ${v.no} dated ${v.date} issued by ${v.shop} for ${v.total}. Amount received: ${v.paid}.${v.due ? ' Outstanding balance: ' + v.due + '.' : ''}\nSincerely,\n${v.shop}`,
  },
  bn: {
    short: (v) => `${v.shop}: Invoice ${v.no}, মোট ${v.total}।${v.link ? ' ' + v.link : ''}`,
    medium: (v) => `প্রিয় ${v.cu || 'গ্রাহক'}, ${v.shop}-এ কেনাকাটার জন্য ধন্যবাদ। Invoice ${v.no} (${v.date}): মোট ${v.total}, পরিশোধ ${v.paid}${v.due ? ', বাকি ' + v.due : ''}।${v.link ? ' দেখুন: ' + v.link : ''}`,
    detailed: (v) => `প্রিয় ${v.cu || 'গ্রাহক'},\n${v.shop}-এ কেনাকাটার জন্য ধন্যবাদ।\nInvoice: ${v.no}\nতারিখ: ${v.date}\n${v.items.map((i) => '- ' + i).join('\n')}\nমোট: ${v.total}\nপরিশোধ: ${v.paid}\n${v.due ? 'বাকি: ' + v.due + '\n' : ''}${v.link ? 'Invoice দেখুন: ' + v.link + '\n' : ''}ধন্যবাদান্তে, ${v.shop}`,
    friendly: (v) => `আসসালামু আলাইকুম ${v.cu || ''}! ${v.shop}-এ আসার জন্য অনেক ধন্যবাদ। আপনার বিল ${v.no} মোট ${v.total}${v.due ? ', ' + v.due + ' বাকি আছে' : ', সব পরিশোধ'}। আবার আসবেন!${v.link ? ' ' + v.link : ''}`,
    formal: (v) => `জনাব/জনাবা ${v.cu || ''},\n${v.shop} কর্তৃক ${v.date} তারিখের Invoice ${v.no} (মোট ${v.total}) নিশ্চিত করা হলো। প্রাপ্ত: ${v.paid}।${v.due ? ' অবশিষ্ট বাকি: ' + v.due + '।' : ''}\nবিনীত,\n${v.shop}`,
  },
};
const DUE = {
  en: {
    short: (v) => `${v.shop}: your due is ${v.due}${v.due_date ? ' (since ' + v.due_date + ')' : ''}. Please pay soon.`,
    medium: (v) => `Dear ${v.cu || 'customer'}, a balance of ${v.due} is pending on invoice ${v.no} at ${v.shop}${v.due_date ? ' (due ' + v.due_date + ')' : ''}. Kindly pay at your convenience.${v.link ? ' ' + v.link : ''}`,
    detailed: (v) => `Dear ${v.cu || 'customer'},\nThis is a reminder from ${v.shop}.\nInvoice: ${v.no}\nDate: ${v.date}\nTotal: ${v.total}\nPaid: ${v.paid}\nDue: ${v.due}\n${v.due_date ? 'Due date: ' + v.due_date + '\n' : ''}${v.link ? 'Details: ' + v.link + '\n' : ''}Please settle the balance soon. Thank you.`,
    friendly: (v) => `Hi ${v.cu || 'there'}! Just a gentle nudge from ${v.shop}: ${v.due} is still open on bill ${v.no}. Whenever you can, please drop by or pay online. Thank you!`,
    formal: (v) => `Dear ${v.cu || 'Sir/Madam'},\nOur records show an outstanding amount of ${v.due} against invoice ${v.no} dated ${v.date}${v.due_date ? ', payable by ' + v.due_date : ''}. We request you to settle it at the earliest.\nSincerely,\n${v.shop}`,
  },
  bn: {
    short: (v) => `${v.shop}: আপনার বাকি ${v.due}${v.due_date ? ' (' + v.due_date + ' থেকে)' : ''}। অনুগ্রহ করে শীঘ্র পরিশোধ করুন।`,
    medium: (v) => `প্রিয় ${v.cu || 'গ্রাহক'}, ${v.shop}-এ Invoice ${v.no}-এর ${v.due} বাকি আছে${v.due_date ? ' (শেষ তারিখ ' + v.due_date + ')' : ''}। সুবিধামতো পরিশোধ করুন।${v.link ? ' ' + v.link : ''}`,
    detailed: (v) => `প্রিয় ${v.cu || 'গ্রাহক'},\n${v.shop} থেকে মনে করিয়ে দেওয়া হচ্ছে।\nInvoice: ${v.no}\nতারিখ: ${v.date}\nমোট: ${v.total}\nপরিশোধ: ${v.paid}\nবাকি: ${v.due}\n${v.due_date ? 'শেষ তারিখ: ' + v.due_date + '\n' : ''}${v.link ? 'বিস্তারিত: ' + v.link + '\n' : ''}অনুগ্রহ করে শীঘ্র পরিশোধ করুন। ধন্যবাদ।`,
    friendly: (v) => `আসসালামু আলাইকুম ${v.cu || ''}! ${v.shop} থেকে একটু মনে করিয়ে দিচ্ছি: বিল ${v.no}-এ ${v.due} বাকি আছে। সুযোগমতো এসে বা অনলাইনে দিয়ে দেবেন। ধন্যবাদ!`,
    formal: (v) => `জনাব/জনাবা ${v.cu || ''},\nআমাদের হিসাবে ${v.date} তারিখের Invoice ${v.no}-এর বিপরীতে ${v.due} অনাদায়ী${v.due_date ? ', পরিশোধের শেষ তারিখ ' + v.due_date : ''}। অনুগ্রহ করে দ্রুত পরিশোধ করুন।\nবিনীত,\n${v.shop}`,
  },
};
function build(bank, kind) {
  return (tp, d, o) => {
    const ch = ['sms', 'whatsapp', 'email'].includes(o.channel) ? o.channel : 'sms';
    const lg = T.lang({ lang: o.lang || d.lang }), vEn = vals(d, 'en'), vBn = vals(d, 'bn');
    let body;
    if (tp.id === 'bilingual') body = bank.en.medium(vEn) + '\n\n' + bank.bn.medium(vBn);
    else body = bank[lg === 'en' ? 'en' : 'bn'][tp.id](lg === 'en' ? vEn : vBn);
    if (ch === 'sms') body = body.replace(/\n+/g, ' ');
    if (ch === 'email') {
      const v = lg === 'en' ? vEn : vBn;
      const subj = kind === 'inv' ? (lg === 'en' ? `Invoice ${v.no} from ${v.shop}` : `${v.shop}: Invoice ${v.no}`) : (lg === 'en' ? `Payment reminder, invoice ${v.no}` : `${v.shop}: বাকির অনুস্মারক, Invoice ${v.no}`);
      return 'Subject: ' + subj + '\n\n' + body;
    }
    return body;
  };
}
T.defineDoc({ id: 'msg_invoice', kind: 'text', group: 'grp_msg', title: 'd_msginv', rec: ['medium', 'r_msginv'], templates: mkT(), render: build(INV, 'inv') });
T.defineDoc({ id: 'msg_due', kind: 'text', group: 'grp_msg', title: 'd_msgdue', rec: ['friendly', 'r_msgdue'], templates: mkT(), render: build(DUE, 'due') });
T.finishLabels();
})();
