/* Islamia BOS · Message inbox (#/inbox) - Step H. Messages that arrive from Facebook / Instagram / WhatsApp / Telegram (and the web order form) collect here; a PERSON makes the order.
   Server: supabase/phase76.sql. Reads: inbox_board / inbox_list / inbox_get / order_dup_flags_list / intake_failures_list / sales_channels_list / web_form_embed.
   Writes (only through server functions): inbox_set_status, online_order_save2 (customer + channel pre-filled, staff type items, qty, address), online_order_draft_verify, order_dup_flag_review, sales_channel_save.
   Telegram (Step Tg, supabase/phase86.sql): telegram_chat_info / telegram_chat_link / telegram_chat_unlink / telegram_status / telegram_secret_set / sales_channel_save. Nothing replies to the customer.
   Nothing here creates or confirms an order by itself. The outside connections (Meta, web form) do not exist until the owner's setup is done (docs/briefs_p2p3/step_H_REPORT.md). */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const X = {
  title: L('বার্তা ইনবক্স', 'Message inbox', 'Message inbox'),
  intro: L('বাইরের বার্তা এখানে জমা হয়। অর্ডার বানান আপনি — নিজে থেকে কোনো অর্ডার হয় না।', 'Outside messages collect here. You make the order — nothing becomes an order by itself.', 'বাইরের message এখানে জমা হয়। Order বানান আপনি — নিজে থেকে কিছু order হয় না।'),
  t_msg: L('বার্তা', 'Messages', 'Messages'), t_dup: L('একই অর্ডার?', 'Same order?', 'একই order?'), t_fail: L('ব্যর্থ তালিকা', 'Failed list', 'Failed list'), t_ch: L('মাধ্যম', 'Channels', 'Channels'),
  off: L('ইনবক্স বন্ধ (সুইচবোর্ডে চালু করুন)', 'Inbox is OFF (switch it on in the Switchboard)', 'Inbox OFF (Switchboard-এ চালু করুন)'),
  newMsg: L('নতুন বার্তা', 'New messages', 'নতুন message'), lastMsg: L('শেষ বার্তা এসেছে', 'Last message came', 'শেষ message এসেছে'), never: L('এখনো কোনো বার্তা আসেনি', 'No message has come yet', 'এখনো message আসেনি'),
  hoursAgo: L('ঘণ্টা আগে', 'hours ago', 'ঘণ্টা আগে'), silent: L('অনেকক্ষণ কোনো বার্তা আসেনি — সংযোগ ঠিক আছে কিনা দেখুন', 'No message for a long time — check the connection', 'অনেকক্ষণ message আসেনি — connection দেখুন'),
  failedN: L('ব্যর্থ ঢোকা', 'Failed intakes', 'Failed intake'), dupN: L('একই অর্ডার সন্দেহ', 'Possible duplicate orders', 'Duplicate order সন্দেহ'), drafts: L('ড্রাফট, যাচাই বাকি', 'Draft, needs checking', 'draft, যাচাই বাকি'),
  all: L('সব', 'All', 'All'), s_new: L('নতুন', 'New', 'New'), s_seen: L('দেখা হয়েছে', 'Seen', 'Seen'), s_converted: L('অর্ডারে রূপান্তরিত', 'Made into order', 'Order হয়েছে'), s_ignored: L('বাদ', 'Ignored', 'Ignored'),
  masked: L('ফোন/ঠিকানা ঢাকা (অনুমতি নেই)', 'Contact hidden (no permission)', 'Contact ঢাকা (permission নেই)'), none: L('কিছু নেই ✓', 'Nothing ✓', 'কিছু নেই ✓'),
  seen: L('দেখেছি', 'Mark seen', 'Seen'), ignore: L('বাদ', 'Ignore', 'Ignore'), restore: L('আবার নতুন', 'Back to new', 'আবার new'), mk: L('অর্ডার বানাও', 'Make order', 'Order বানাও'),
  verify: L('যাচাই করেছি', 'I checked it', 'যাচাই করেছি'), reason: L('কারণ লিখুন', 'Write the reason', 'কারণ লিখুন'),
  name: L('কাস্টমারের নাম', 'Customer name', 'Customer নাম'), mobile: L('মোবাইল', 'Mobile', 'Mobile'), addr: L('ঠিকানা', 'Address', 'Address'), dmode: L('ডেলিভারি', 'Delivery', 'Delivery'),
  pickup: L('দোকান থেকে নেবে', 'Pick up', 'Pickup'), home: L('হোম ডেলিভারি', 'Home delivery', 'Home delivery'), courier: L('কুরিয়ার', 'Courier', 'Courier'),
  items: L('আইটেম ও Qty (আপনি লিখুন)', 'Items and qty (you type)', 'item ও qty (আপনি লিখুন)'), addLine: L('+ আইটেম যোগ', '+ Add item', '+ Item যোগ'), qty: L('Qty', 'Qty', 'Qty'),
  source: L('উৎস (পেজ/ক্যাম্পেইন, ফাঁকা থাকতে পারে)', 'Source (page / campaign, may be blank)', 'Source (page/campaign, ফাঁকা চলবে)'),
  payMode: L('পেমেন্ট ধরন', 'Payment mode', 'Payment mode'), pm_cod: L('ক্যাশ অন ডেলিভারি', 'Cash on delivery', 'Cash on delivery'), pm_cash: L('ক্যাশ', 'Cash', 'Cash'), pm_mobile: L('মোবাইল ব্যাংকিং', 'Mobile money', 'Mobile money'),
  pm_card: L('কার্ড', 'Card', 'Card'), pm_bank: L('ব্যাংক', 'Bank', 'Bank'), pm_other: L('☐ অন্য:', '☐ Other:', '☐ অন্য:'), payRef: L('পেমেন্ট রেফারেন্স নম্বর (ফাঁকা থাকতে পারে)', 'Payment reference no. (may be blank)', 'Payment ref no. (ফাঁকা চলবে)'),
  note: L('নোট', 'Note', 'Note'), save: L('অর্ডার সেভ', 'Save order', 'Order save'), saved: L('অর্ডার হয়েছে', 'Order saved', 'Order হয়েছে'), back: L('ফিরে যান', 'Back', 'Back'),
  place: L('জায়গা', 'Place', 'Place'), review: L('দেখেছি, আলাদা অর্ডার', 'Checked, separate orders', 'দেখেছি, আলাদা order'), orderNo: L('অর্ডার নং', 'Order no.', 'Order নং'), day: L('দিন', 'Day', 'Day'),
  chNone: L('কোনো মাধ্যম নেই — মালিক যোগ করবেন', 'No channels yet — the owner adds them', 'Channel নেই — owner যোগ করবেন'), share: L('ফর্মের লিংক/এম্বেড কোড', 'Form link / embed code', 'Form link/embed code'),
  notCfg: L('পাবলিক ঠিকানা এখনো সেট হয়নি (ফাংশন চালু হয়নি) — লিংক বানানো যাবে না', 'Public URL not set yet (the function is not deployed) — no link can be made', 'Public URL set হয়নি — link হবে না'),
  show: L('দেখুন', 'Show', 'Show'), copy: L('কপি', 'Copy', 'Copy'), copied: L('কপি হয়েছে', 'Copied', 'Copied'),
  k_web_form: L('ওয়েব/ল্যান্ডিং ফর্ম', 'Web / landing form', 'Web/landing form'), k_facebook: L('ফেসবুক পেজ মেসেঞ্জার', 'Facebook Page Messenger', 'Facebook Page Messenger'), k_instagram: L('ইনস্টাগ্রাম', 'Instagram', 'Instagram'),
  k_whatsapp: L('হোয়াটসঅ্যাপ', 'WhatsApp', 'WhatsApp'), k_phone: L('ফোন', 'Phone', 'Phone'), k_walkin: L('ওয়াক-ইন', 'Walk-in', 'Walk-in'), k_other: L('☐ অন্য:', '☐ Other:', '☐ অন্য:'),
  k_telegram: L('টেলিগ্রাম', 'Telegram', 'Telegram'),
  tgInfo: L('চ্যাট তথ্য', 'Chat info', 'Chat তথ্য'), tgLink: L('কাস্টমারের সাথে জোড়া দিন', 'Link to customer', 'Customer-এর সাথে link'), tgUnlink: L('জোড়া খুলুন', 'Unlink', 'Unlink'),
  tgLinked: L('জোড়া আছে', 'Linked', 'Linked'), tgNot: L('এখনো জোড়া নেই', 'Not linked yet', 'এখনো link নেই'), tgMsgs: L('এই চ্যাটের বার্তা', 'Messages in this chat', 'এই chat-এর message'),
  tgAsk: L('কাস্টমারের মোবাইল নম্বর লিখুন', 'Type the customer mobile number', 'Customer-এর mobile number লিখুন'), tgNoCust: L('এই নম্বরে কোনো কাস্টমার নেই', 'No customer with this number', 'এই number-এ customer নেই'),
  tgSecret: L('গোপন টোকেন বসান', 'Set secret token', 'Secret token বসান'), tgSecretAsk: L('টেলিগ্রামে যে গোপন টোকেন দিয়েছেন সেটি লিখুন (১৬-২৫৫ অক্ষর: ইংরেজি অক্ষর, সংখ্যা, _ বা -)', 'Type the secret token you gave Telegram (16-255 characters: letters, digits, _ or -)', 'Telegram-এ দেওয়া secret token লিখুন (১৬-২৫৫ অক্ষর: ইংরেজি letter, digit, _ বা -)'),
  tgSecretOk: L('গোপন টোকেন রাখা হয়েছে', 'Secret token saved', 'Secret token রাখা হয়েছে'), tgSecretSet: L('টোকেন বসানো আছে', 'Token set', 'Token বসানো আছে'), tgSecretNone: L('টোকেন বসানো হয়নি — বার্তা ঢুকবে না', 'Token not set — no message will come in', 'Token বসানো হয়নি — message ঢুকবে না'),
  tgAdd: L('+ টেলিগ্রাম মাধ্যম যোগ', '+ Add Telegram channel', '+ Telegram channel যোগ'), tgAskName: L('মাধ্যমের নাম', 'Channel name', 'Channel-এর নাম'), tgAskRef: L('বটের ইউজারনেম বা আইডি (যেমন my_shop_bot)', 'Bot username or id (like my_shop_bot)', 'Bot-এর username বা id (যেমন my_shop_bot)'),
  tgAskPlace: L('জায়গার নম্বর বেছে লিখুন', 'Type the number of the place', 'Place-এর number লিখুন'), tgCode: L('ওয়েবহুক কোড', 'Webhook code', 'Webhook code'), tgAdded: L('টেলিগ্রাম মাধ্যম যোগ হয়েছে', 'Telegram channel added', 'Telegram channel যোগ হয়েছে'),
  e_not_telegram: L('এটি টেলিগ্রামের বার্তা নয়', 'This is not a Telegram message', 'এটি Telegram message নয়'), e_customer_not_found: L('কাস্টমার পাওয়া যায়নি', 'Customer not found', 'Customer পাওয়া যায়নি'),
  e_bad_secret: L('টোকেন ঠিক নয় (১৬-২৫৫ অক্ষর, ইংরেজি অক্ষর/সংখ্যা/_/-)', 'The token is not valid (16-255 characters, letters/digits/_/-)', 'Token ঠিক নয় (১৬-২৫৫ অক্ষর, letter/digit/_/-)'),
  e_account_ref_required: L('বটের ইউজারনেম বা আইডি দিন', 'Enter the bot username or id', 'Bot-এর username বা id দিন'), e_duplicate: L('এই মাধ্যম আগেই আছে', 'This channel already exists', 'এই channel আগেই আছে'),
  e_not_allowed: L('এই অংশ দেখার অনুমতি আপনার নেই', 'You do not have access to this part', 'এই অংশের access নেই'), e_module_off: L('এই সুবিধা এখনো চালু করা হয়নি', 'This feature is not switched on yet', 'এই feature এখনো চালু নয়'),
  e_message_closed: L('এই বার্তা থেকে আগেই অর্ডার হয়েছে বা বাদ করা হয়েছে', 'This message already became an order or was ignored', 'এই message আগেই order/ignored'),
  e_bad_mobile: L('মোবাইল নম্বর ঠিক নয়', 'The mobile number is not valid', 'Mobile number ঠিক নয়'), e_address_required: L('ঠিকানা দিন', 'Enter the address', 'Address দিন'),
  e_customer_name_required: L('কাস্টমারের নাম দিন', 'Enter the customer name', 'Customer নাম দিন'), e_no_lines: L('অন্তত একটি আইটেম দিন', 'Add at least one item', 'অন্তত একটি item দিন'),
  e_bad_qty: L('Qty ঠিক নয়', 'The quantity is not valid', 'Qty ঠিক নয়'), e_item_required: L('আইটেম বেছে নিন', 'Pick the item', 'Item বাছুন'), e_reason_required: L('কারণ লিখতে হবে', 'A reason is needed', 'কারণ লিখতে হবে'),
  e_pay_mode_other_required: L('অন্য ধরন লিখুন', 'Write the other payment mode', 'অন্য mode লিখুন'),
};
const T = (k) => lab(X[k]);
const FRIENDLY = { 'not allowed': 'e_not_allowed', module_off: 'e_module_off', message_closed: 'e_message_closed', bad_mobile: 'e_bad_mobile', address_required: 'e_address_required',
  customer_name_required: 'e_customer_name_required', no_lines: 'e_no_lines', bad_qty: 'e_bad_qty', item_required: 'e_item_required', reason_required: 'e_reason_required', pay_mode_other_required: 'e_pay_mode_other_required',
  not_telegram: 'e_not_telegram', customer_not_found: 'e_customer_not_found', bad_secret: 'e_bad_secret', account_ref_required: 'e_account_ref_required', duplicate: 'e_duplicate' };
const msg = (e) => { const m = String((e && e.message) || e || ''); const k = Object.keys(FRIENDLY).find((x) => m.indexOf(x) >= 0); return k ? T(FRIENDLY[k]) : m; };
const rid = () => (crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3) | 8).toString(16); }));
const D = { tab: 'msg', board: null, list: null, st: '', dup: null, fail: null, ch: null, items: [], form: null, err: '', emb: {}, tg: {}, tgs: null };

/* ---------- pure helpers (tested) ---------- */
const kindTxt = (k) => (X['k_' + k] ? T('k_' + k) : String(k || ''));
const statusTxt = (s) => (X['s_' + s] ? T('s_' + s) : String(s || ''));
const phoneLike = (h) => { const d = String(h || '').replace(/\D/g, ''); return d.length >= 10 && d.length <= 15 && /^[+\d][\d\s\-+]*$/.test(String(h || '')) ? d.replace(/^880/, '0') : ''; };
function boardLine(b) {
  if (!b || !b.on) return { off: true };
  return { off: false, newCount: Number(b.new_count || 0), last: b.last_at ? b.hours_since : null, silent: !!b.silent, failed: Number(b.failed_count || 0), dup: Number(b.dup_open || 0), drafts: Number(b.drafts || 0) };
}
function orderArgs(f, clientId) {
  return { p_id: null, p_client: clientId, p_loc: Number(f.loc), p_channel_id: Number(f.channel_id), p_name: f.name, p_mobile: f.mobile, p_address: f.address || null,
    p_lines: f.lines.filter((l) => l.item_id && Number(l.qty) > 0).map((l) => ({ item_id: l.item_id, qty: Number(l.qty) })), p_delivery_mode: f.dmode, p_delivery_by: null, p_delivery_date: null,
    p_charge: 0, p_discount: 0, p_advance: 0, p_adv_mode: null, p_adv_wallet: null, p_note: f.note || null, p_external_ref: null, p_source: f.source || null,
    p_pay_mode: f.pay_mode || null, p_pay_mode_other: f.pay_mode === 'other' ? (f.pay_other || null) : null, p_pay_ref: f.pay_ref || null, p_msg_id: f.msg_id, p_draft: false };
}

/* ---------- drawing ---------- */
const errBox = () => (D.err ? `<p class="muted" role="alert">${esc(D.err)}</p>` : '');
function drawBoard() {
  const b = boardLine(D.board); if (!D.board) return '<p class="muted">…</p>';
  if (b.off) return `<div class="card"><span class="chip warn">${esc(T('off'))}</span></div>`;
  return `<div class="card stack"><div class="row wrap"><span class="chip ${b.newCount ? 'warn' : 'ok'}">${esc(T('newMsg'))} ${esc(String(b.newCount))}</span>
    ${b.failed ? `<span class="chip bad">${esc(T('failedN'))} ${esc(String(b.failed))}</span>` : ''}${b.dup ? `<span class="chip warn">${esc(T('dupN'))} ${esc(String(b.dup))}</span>` : ''}${b.drafts ? `<span class="chip warn">${esc(T('drafts'))} ${esc(String(b.drafts))}</span>` : ''}</div>
    <div class="muted">${esc(T('lastMsg'))}: ${b.last == null ? esc(T('never')) : esc(String(b.last)) + ' ' + esc(T('hoursAgo'))}</div>${b.silent ? `<p class="chip bad" role="alert">${esc(T('silent'))}</p>` : ''}</div>`;
}
function drawMsg() {
  const rows = D.list;
  const filt = `<select id="ib_st"><option value="">${esc(T('all'))}</option>${['new', 'seen', 'converted', 'ignored'].map((s) => `<option value="${s}" ${D.st === s ? 'selected' : ''}>${esc(statusTxt(s))}</option>`).join('')}</select><button type="button" class="mini" data-act="ib_filter">${esc(T('show'))}</button>`;
  if (!rows) return `<div class="card stack">${filt}${errBox()}${D.err ? '' : '<p class="muted">…</p>'}</div>`;
  return `<div class="card stack">${filt}${errBox()}</div>` + (rows.length ? rows.map((m) => `<div class="card stack"><div class="row between wrap"><b>${esc(m.channel || '')} · ${esc(kindTxt(m.kind))}</b><span class="chip ${m.status === 'new' ? 'warn' : ''}">${esc(statusTxt(m.status))}</span></div>
    <div>${m.masked ? `<span class="muted">${esc(T('masked'))}</span>` : `<div>${esc(m.name || m.handle || '')}</div><div class="muted">${esc(m.text || '')}</div>`}</div>
    <div class="muted" style="font-size:.85rem">${esc(String(m.received_at || '').slice(0, 16).replace('T', ' '))}${m.draft_order_id && m.status !== 'converted' ? ' · ' + esc(T('drafts')) : ''}</div>
    <div class="row wrap">${m.status === 'new' ? `<button type="button" class="mini" data-act="ib_seen" data-id="${esc(String(m.id))}">${esc(T('seen'))}</button>` : ''}
    ${m.status === 'new' || m.status === 'seen' ? `<button type="button" class="btn primary" data-act="ib_make" data-id="${esc(String(m.id))}">${esc(T('mk'))}</button><button type="button" class="mini" data-act="ib_ignore" data-id="${esc(String(m.id))}">${esc(T('ignore'))}</button>` : ''}
    ${m.status === 'ignored' ? `<button type="button" class="mini" data-act="ib_restore" data-id="${esc(String(m.id))}">${esc(T('restore'))}</button>` : ''}
    ${m.draft_order_id && m.status !== 'converted' ? `<button type="button" class="mini" data-act="ib_verify" data-id="${esc(String(m.draft_order_id))}">${esc(T('verify'))}</button>` : ''}
    ${m.kind === 'telegram' ? `<button type="button" class="mini" data-act="ib_tg_info" data-id="${esc(String(m.id))}">${esc(T('tgInfo'))}</button>` : ''}</div>${m.kind === 'telegram' && D.tg[m.id] ? tgBlock(m.id, D.tg[m.id]) : ''}</div>`).join('') : `<div class="card"><p class="muted">${esc(T('none'))}</p></div>`);
}
function tgBlock(id, i) {
  const sid = esc(String(id));
  return `<div class="stack"><div class="row wrap"><span class="chip ${i.linked ? 'ok' : ''}">${esc(i.linked ? T('tgLinked') : T('tgNot'))}</span><span class="muted">${esc(T('tgMsgs'))}: ${esc(String(i.message_count || 0))}</span></div>
    ${i.linked && !i.masked ? `<div>${esc(i.customer_name || '')} ${esc(i.customer_mobile || '')} ${i.order_no ? '· ' + esc(T('orderNo')) + ' #' + esc(String(i.order_no)) : ''}</div>` : (i.linked && i.order_no ? `<div>${esc(T('orderNo'))} #${esc(String(i.order_no))}</div>` : '')}
    <div class="row wrap"><button type="button" class="mini" data-act="ib_tg_link" data-id="${sid}">${esc(T('tgLink'))}</button>${i.linked ? `<button type="button" class="mini" data-act="ib_tg_unlink" data-id="${sid}">${esc(T('tgUnlink'))}</button>` : ''}</div></div>`;
}
const f = (k) => (D.form && D.form[k] != null ? D.form[k] : '');
function drawForm() {
  const F = D.form;
  const itemOpts = (sel) => `<option value="">—</option>${D.items.map((i) => `<option value="${esc(i.id)}" ${sel === i.id ? 'selected' : ''}>${esc(i.name_bn)} (${esc(String(i.sell_price == null ? '' : i.sell_price))})</option>`).join('')}`;
  return `<div class="card stack"><button type="button" class="mini" data-act="ib_back">← ${esc(T('back'))}</button>${errBox()}
    <label>${esc(T('name'))}<input id="ib_f_name" value="${esc(F.name)}" maxlength="80"></label><label>${esc(T('mobile'))}<input id="ib_f_mobile" inputmode="tel" value="${esc(F.mobile)}"></label>
    <label>${esc(T('dmode'))}<select id="ib_f_dmode">${['pickup', 'home', 'courier'].map((v) => `<option value="${v}" ${F.dmode === v ? 'selected' : ''}>${esc(T(v))}</option>`).join('')}</select></label>
    <label>${esc(T('addr'))}<textarea id="ib_f_address" maxlength="300">${esc(F.address)}</textarea></label>
    <b>${esc(T('items'))}</b>${F.lines.map((l, i) => `<div class="row"><select data-ib-item="${i}">${itemOpts(l.item_id)}</select><input data-ib-qty="${i}" inputmode="decimal" placeholder="${esc(T('qty'))}" value="${esc(String(l.qty || ''))}" style="width:90px"></div>`).join('')}
    <button type="button" class="mini" data-act="ib_addline">${esc(T('addLine'))}</button>
    <label>${esc(T('source'))}<input id="ib_f_source" value="${esc(F.source)}" maxlength="80"></label>
    <label>${esc(T('payMode'))}<select id="ib_f_pay">${['', 'cod', 'cash', 'mobile', 'card', 'bank', 'other'].map((v) => `<option value="${v}" ${F.pay_mode === v ? 'selected' : ''}>${v ? esc(T('pm_' + v)) : '—'}</option>`).join('')}</select></label>
    <label><input id="ib_f_payother" value="${esc(F.pay_other)}" maxlength="60" placeholder="${esc(T('pm_other'))}"></label>
    <label>${esc(T('payRef'))}<input id="ib_f_payref" value="${esc(F.pay_ref)}" maxlength="80"></label>
    <label>${esc(T('note'))}<input id="ib_f_note" value="${esc(F.note)}" maxlength="300"></label>
    <button type="button" class="btn primary" data-act="ib_save">${esc(T('save'))}</button></div>`;
}
function drawDup() {
  const d = D.dup; if (!d) return D.err ? errBox() : '<p class="muted">…</p>';
  return d.length ? d.map((x) => `<div class="card stack"><div>${esc(T('orderNo'))} #${esc(String(x.order_no_a))} (${esc(x.channel_a || '')}) ↔ #${esc(String(x.order_no_b))} (${esc(x.channel_b || '')})</div>
    <div class="muted">${esc(T('day'))}: ${esc(String(x.day))}</div><button type="button" class="mini" data-act="ib_dupok" data-id="${esc(String(x.id))}">${esc(T('review'))}</button></div>`).join('') : `<div class="card"><p class="muted">${esc(T('none'))}</p></div>`;
}
function drawFail() {
  const d = D.fail; if (!d) return D.err ? errBox() : '<p class="muted">…</p>';
  return d.length ? d.map((x) => `<div class="card"><div class="row between wrap"><span>#${esc(String(x.id))} · ${esc(x.kind)} · ${esc(x.state)}</span><span class="muted">${esc(String(x.attempts))}</span></div><div class="muted">${esc(x.error || '')}</div></div>`).join('') : `<div class="card"><p class="muted">${esc(T('none'))}</p></div>`;
}
function tgChannel(c) {
  const st = D.tgs && (D.tgs.channels || []).find((x) => x.id === c.id);
  return `<div class="muted">${esc(T('tgCode'))}: <code>?c=${esc(c.code)}</code></div>${st ? `<div class="row wrap"><span class="chip ${st.secret_set ? 'ok' : 'bad'}">${esc(st.secret_set ? T('tgSecretSet') : T('tgSecretNone'))}</span><button type="button" class="mini" data-act="ib_tg_secret" data-id="${esc(String(c.id))}">${esc(T('tgSecret'))}</button></div>` : ''}`;
}
function drawCh() {
  const d = D.ch; if (!d) return D.err ? errBox() : '<p class="muted">…</p>';
  const add = D.tgs ? `<div class="card"><button type="button" class="btn" data-act="ib_tg_add">${esc(T('tgAdd'))}</button></div>` : '';
  return add + (d.length ? d.map((c) => `<div class="card stack"><div class="row between wrap"><b>${esc(c.name_bn)}</b><span class="chip ${c.active ? 'ok' : ''}">${esc(kindTxt(c.kind))}${c.kind === 'other' ? ' ' + esc(c.other_text || '') : ''}</span></div>
    ${c.kind === 'telegram' ? tgChannel(c) : ''}
    ${c.kind === 'web_form' ? `<button type="button" class="mini" data-act="ib_embed" data-code="${esc(c.code)}">${esc(T('share'))}</button>${D.emb[c.code] ? (D.emb[c.code].configured ? `<textarea readonly rows="3">${esc(D.emb[c.code].link + '\n' + D.emb[c.code].embed)}</textarea>` : `<p class="muted">${esc(T('notCfg'))}</p>`) : ''}` : ''}</div>`).join('') : `<div class="card"><p class="muted">${esc(T('chNone'))}</p></div>`);
}
function draw() {
  const el = $('#ib_body'); if (!el) return;
  if (D.form) { el.innerHTML = drawForm(); return; }
  const tabs = ['msg', 'dup', 'fail', 'ch'];
  el.innerHTML = `<p class="muted">${esc(T('intro'))}</p>${drawBoard()}<div class="row wrap" role="tablist">${tabs.map((t) => `<button type="button" class="btn ${D.tab === t ? 'primary' : ''}" role="tab" aria-selected="${D.tab === t}" data-act="ib_tab" data-t="${t}">${esc(T('t_' + t))}</button>`).join('')}</div>
    ${D.tab === 'msg' ? drawMsg() : D.tab === 'dup' ? drawDup() : D.tab === 'fail' ? drawFail() : drawCh()}`;
}

/* ---------- loading ---------- */
async function load(tab) {
  D.err = '';
  try {
    const b = await sb.rpc('inbox_board'); if (!b.error) D.board = b.data; else if (!/module_off/.test(b.error.message)) throw b.error;
    if (tab === 'msg') { D.list = null; const r = await sb.rpc('inbox_list', { p_loc: null, p_status: D.st || null, p_limit: 100 }); if (r.error) throw r.error; D.list = r.data || []; }
    if (tab === 'dup') { D.dup = null; const r = await sb.rpc('order_dup_flags_list', { p_loc: null, p_state: 'open' }); if (r.error) throw r.error; D.dup = r.data || []; }
    if (tab === 'fail') { D.fail = null; const r = await sb.rpc('intake_failures_list', { p_state: 'failed', p_limit: 100 }); if (r.error) throw r.error; D.fail = r.data || []; }
    if (tab === 'ch') { D.ch = null; const r = await sb.rpc('sales_channels_list', { p_all: false }); if (r.error) throw r.error; D.ch = r.data || []; const ts = await sb.rpc('telegram_status'); D.tgs = ts.error ? null : ts.data; }   // owner only: others get 'not allowed' and simply see no setup buttons
  } catch (e) { D.err = msg(e); }
  draw();
}
const readForm = () => {
  const F = D.form; if (!F) return;
  const v = (id) => ($(id) || {}).value;
  F.name = v('#ib_f_name') ?? F.name; F.mobile = v('#ib_f_mobile') ?? F.mobile; F.dmode = v('#ib_f_dmode') ?? F.dmode; F.address = v('#ib_f_address') ?? F.address; F.source = v('#ib_f_source') ?? F.source;
  F.pay_mode = v('#ib_f_pay') ?? F.pay_mode; F.pay_other = v('#ib_f_payother') ?? F.pay_other; F.pay_ref = v('#ib_f_payref') ?? F.pay_ref; F.note = v('#ib_f_note') ?? F.note;
  document.querySelectorAll && document.querySelectorAll('[data-ib-item]').forEach((s) => { F.lines[Number(s.dataset.ibItem)].item_id = s.value; });
  document.querySelectorAll && document.querySelectorAll('[data-ib-qty]').forEach((s) => { F.lines[Number(s.dataset.ibQty)].qty = s.value; });
};
Object.assign(H, {
  ib_tab: async (a) => { D.tab = a.dataset.t; D.form = null; draw(); await load(D.tab); },
  ib_seen: async (a) => { const r = await sb.rpc('inbox_set_status', { p_id: Number(a.dataset.id), p_to: 'seen', p_note: null }); if (r.error) return toast(msg(r.error)); await load('msg'); },
  ib_restore: async (a) => { const r = await sb.rpc('inbox_set_status', { p_id: Number(a.dataset.id), p_to: 'new', p_note: null }); if (r.error) return toast(msg(r.error)); await load('msg'); },
  ib_ignore: async (a) => { const why = (window.prompt ? window.prompt(T('reason')) : '') || ''; if (!why.trim()) return toast(T('e_reason_required')); const r = await sb.rpc('inbox_set_status', { p_id: Number(a.dataset.id), p_to: 'ignored', p_note: why }); if (r.error) return toast(msg(r.error)); await load('msg'); },
  ib_filter: async () => { D.st = ($('#ib_st') || {}).value || ''; await load('msg'); },
  ib_make: async (a) => {
    // the order screen opens with the customer and channel pre-filled from the message; the staff type items, qty and address themselves
    const r = await sb.rpc('inbox_get', { p_id: Number(a.dataset.id) }); if (r.error) return toast(msg(r.error));
    const m = r.data; if (m.masked) return toast(T('e_not_allowed'));
    if (!D.items.length) { const it = await sb.from('items').select('id,code,name_bn,sell_price').eq('is_active', true).eq('sellable', true).order('code').limit(800); D.items = it.data || []; }
    D.err = ''; D.form = { msg_id: m.id, channel_id: m.channel_id, loc: m.location_id, name: m.name || '', mobile: phoneLike(m.handle), address: '', dmode: 'home', lines: [{ item_id: '', qty: '' }], source: '', pay_mode: '', pay_other: '', pay_ref: '', note: '', client: rid() };
    draw();
  },
  ib_addline: () => { readForm(); D.form.lines.push({ item_id: '', qty: '' }); draw(); },
  ib_back: async () => { D.form = null; draw(); await load('msg'); },
  ib_save: async () => {
    readForm(); D.err = '';
    const r = await sb.rpc('online_order_save2', orderArgs(D.form, D.form.client));    // same client id on a re-send = the same order
    if (r.error) { D.err = msg(r.error); return draw(); }
    toast(T('saved') + ' #' + ((r.data && r.data.order_no) || '')); D.form = null; D.tab = 'msg'; await load('msg');
  },
  ib_verify: async (a) => { const r = await sb.rpc('online_order_draft_verify', { p_id: a.dataset.id, p_note: null }); if (r.error) return toast(msg(r.error)); await load('msg'); },
  ib_dupok: async (a) => { const why = (window.prompt ? window.prompt(T('reason')) : '') || ''; if (!why.trim()) return toast(T('e_reason_required')); const r = await sb.rpc('order_dup_flag_review', { p_id: Number(a.dataset.id), p_note: why }); if (r.error) return toast(msg(r.error)); await load('dup'); },
  ib_tg_info: async (a) => { const id = Number(a.dataset.id); const r = await sb.rpc('telegram_chat_info', { p_msg_id: id }); if (r.error) return toast(msg(r.error)); if (D.tg[id]) delete D.tg[id]; else D.tg[id] = r.data; draw(); },
  ib_tg_link: async (a) => {
    const id = Number(a.dataset.id); const mob = ((window.prompt ? window.prompt(T('tgAsk')) : '') || '').replace(/\D/g, '');
    if (!mob) return;
    const c = await sb.from('customers').select('id,name').eq('mobile', mob.replace(/^880/, '0')).limit(1); const cu = c.data && c.data[0]; if (!cu) return toast(T('tgNoCust'));
    const r = await sb.rpc('telegram_chat_link', { p_msg_id: id, p_customer: cu.id, p_order: null, p_note: null }); if (r.error) return toast(msg(r.error));
    const i = await sb.rpc('telegram_chat_info', { p_msg_id: id }); if (!i.error) D.tg[id] = i.data; draw();
  },
  ib_tg_unlink: async (a) => {
    const id = Number(a.dataset.id); const why = (window.prompt ? window.prompt(T('reason')) : '') || ''; if (!why.trim()) return toast(T('e_reason_required'));
    const r = await sb.rpc('telegram_chat_unlink', { p_msg_id: id, p_reason: why }); if (r.error) return toast(msg(r.error));
    const i = await sb.rpc('telegram_chat_info', { p_msg_id: id }); if (!i.error) D.tg[id] = i.data; draw();
  },
  ib_tg_secret: async (a) => {
    const tok = ((window.prompt ? window.prompt(T('tgSecretAsk')) : '') || '').trim(); if (!tok) return;
    const r = await sb.rpc('telegram_secret_set', { p_channel: Number(a.dataset.id), p_secret: tok }); if (r.error) return toast(msg(r.error));
    toast(T('tgSecretOk')); await load('ch');
  },
  ib_tg_add: async () => {
    const ask = (k) => ((window.prompt ? window.prompt(T(k)) : '') || '').trim();
    const name = ask('tgAskName'); if (!name) return; const ref = ask('tgAskRef'); if (!ref) return toast(T('e_account_ref_required'));
    const lo = await sb.from('locations').select('id,name_bn').order('id').limit(50); const locs = lo.data || [];
    const pick = ask('tgAskPlace') || ''; const loc = locs.find((x) => String(x.id) === pick); if (!loc) return;
    const code = 'tg_' + rid().replace(/-/g, '').slice(0, 6);
    const r = await sb.rpc('sales_channel_save', { p_id: null, p_code: code, p_kind: 'telegram', p_other: null, p_name: name, p_loc: loc.id, p_role: null, p_account_ref: ref, p_active: true });
    if (r.error) return toast(msg(r.error)); toast(T('tgAdded')); await load('ch');
  },
  ib_embed: async (a) => { const r = await sb.rpc('web_form_embed', { p_channel: a.dataset.code }); if (r.error) return toast(msg(r.error)); D.emb[a.dataset.code] = r.data; draw(); },
});
async function view() {
  if (B.loadStatic) await B.loadStatic();
  D.board = D.list = D.dup = D.fail = D.ch = null; D.form = null; D.err = '';
  shell(T('title'), '<div id="ib_body" class="stack"></div>', true);
  draw(); await load(D.tab);
}
B.inbox = { tgBlock, kindTxt, statusTxt, phoneLike, boardLine, orderArgs, msg };
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { inbox: view });
})();
