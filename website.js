/* Islamia BOS · Website manager (#/website) - X2. Owner screen for the public website (site/).
   Server: supabase/phase481.sql (settings, publishing, public reads), phase482.sql (checkout, holds, owner web_admin_* functions).
   Reads: web_admin_board, web_admin_go_live, web_admin_drift, web_admin_holds_report, web_admin_web_orders, web_admin_cancel_list, web_admin_custom_list,
          rules (website_% keys), web_item_pub, items.
   Writes (owner only, each checked on the server): set_rule, web_admin_item_save, web_admin_publish_bulk, web_admin_image_add, web_admin_image_approve,
          web_admin_zone_save, web_admin_pickup_save, web_admin_closure_save, web_admin_cancel_decide, web_admin_custom_decide.
   Nothing here holds a secret. The public address is a setting; until it is set the screen says so. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const X = {
  title: L('ওয়েবসাইট', 'Website', 'Website'),
  intro: L('দোকানের অনলাইন পাতা: কী দেখাবে, কোথা থেকে অর্ডার নেবে, কী কী চালু। সবকিছু বন্ধ অবস্থায় শুরু হয়।', 'The shop website: what it shows, where orders go, what is on. Everything starts off.', 'দোকানের online পাতা: কী দেখাবে, কোথায় order যাবে, কী চালু। সব বন্ধ অবস্থায় শুরু।'),
  t_board: L('অবস্থা', 'Status', 'Status'), t_items: L('আইটেম ও ছবি', 'Items & photos', 'Items ও ছবি'), t_set: L('সেটিংস', 'Settings', 'Settings'),
  t_orders: L('অর্ডার ও অনুরোধ', 'Orders & requests', 'Order ও অনুরোধ'), t_places: L('শাখা, এলাকা, ছুটি', 'Branches, zones, closures', 'শাখা, এলাকা, ছুটি'),
  on: L('চালু', 'On', 'On'), off: L('বন্ধ', 'Off', 'Off'), none: L('এখনো কিছু নেই', 'Nothing yet', 'এখনো কিছু নেই'),
  pubItems: L('পাবলিশড আইটেম', 'Published items', 'Published item'), photos: L('অনুমোদিত ছবি', 'Approved photos', 'অনুমোদিত ছবি'),
  ordersToday: L('আজকের ওয়েব অর্ডার', "Today's web orders", 'আজকের web order'), ordersNew: L('নতুন অর্ডার', 'New orders', 'নতুন order'),
  cancelOpen: L('বাতিলের অনুরোধ', 'Cancel requests', 'বাতিলের অনুরোধ'), customNew: L('কাস্টম কেকের অনুরোধ', 'Custom cake requests', 'কাস্টম কেকের অনুরোধ'),
  holds: L('ধরে রাখা স্টক (এখন)', 'Stock held now', 'ধরা স্টক (এখন)'), reserveOn: L('স্টক ধরে রাখা চালু', 'Hard reservation on', 'স্টক ধরা চালু'),
  golive: L('লাইভ করার আগের তালিকা', 'Go-live checklist', 'Go-live তালিকা'), ready: L('লাইভ করার জন্য প্রস্তুত', 'Ready to go live', 'লাইভের জন্য প্রস্তুত'),
  notReady: L('এখনো বাকি আছে (নিচে)', 'Still missing (below)', 'এখনো বাকি (নিচে)'), req: L('জরুরি', 'Required', 'জরুরি'), opt: L('ঐচ্ছিক', 'Optional', 'ঐচ্ছিক'),
  howTo: L('কী করতে হবে', 'What to do', 'কী করবেন'), drift: L('ERP ও ওয়েবের মিল (ড্রিফট)', 'ERP vs web drift', 'ERP ও web মিল (drift)'),
  driftNote: L('দাম বদলালে আইটেমটি আবার পাবলিশ করুন। কিছুই কোনো দোকানে পাঠানো হয় না।', 'If a price changed, publish the item again. Nothing is pushed to any shop.', 'দাম বদলালে আবার publish করুন। কোথাও কিছু পাঠানো হয় না।'),
  cat: L('ক্যাটাগরি (ERP)', 'Category (ERP)', 'Category (ERP)'), bulkOn: L('এই ক্যাটাগরির সব পাবলিশ', 'Publish all of this category', 'এই category সব publish'),
  bulkOff: L('এই ক্যাটাগরির সব সরান', 'Unpublish all of this category', 'এই category সব সরান'), save: L('সংরক্ষণ', 'Save', 'Save'), saved: L('সংরক্ষিত', 'Saved', 'Saved'),
  pub: L('ওয়েবে দেখাও', 'Show on web', 'ওয়েবে দেখাও'), nameBn: L('নাম (বাংলা)', 'Name (Bangla)', 'নাম (বাংলা)'), nameEn: L('নাম (ইংরেজি)', 'Name (English)', 'নাম (English)'),
  descBn: L('বিবরণ (বাংলা)', 'Description (Bangla)', 'বিবরণ (বাংলা)'), descEn: L('বিবরণ (ইংরেজি)', 'Description (English)', 'বিবরণ (English)'),
  pcat: L('ওয়েবে ক্যাটাগরি', 'Web category', 'Web category'), sort: L('ক্রম', 'Order', 'ক্রম'), avail: L('অবস্থা', 'Availability', 'অবস্থা'),
  a_auto: L('স্টক থেকে নিজে', 'Automatic from stock', 'স্টক থেকে নিজে'), a_pre: L('প্রি-অর্ডার', 'Pre-order', 'প্রি-অর্ডার'), a_sold: L('শেষ (হাতে)', 'Sold out (by hand)', 'শেষ (হাতে)'),
  lead: L('আগাম দিন', 'Lead days', 'আগাম দিন'), allergen: L('অ্যালার্জেন/উপাদান', 'Allergens / ingredients', 'Allergen/উপাদান'), diet: L('ধরন (হালাল/ডিম ছাড়া/চিনি ছাড়া/ভেগান)', 'Diet tags (halal / eggless / sugar free / vegan)', 'ধরন (halal/eggless/sugar free/vegan)'),
  photoPath: L('ছবির পথ (web-public বাকেটে আপলোড করা, items/<আইটেম id>/ছবি.jpg)', 'Photo path in the web-public bucket (items/<item id>/photo.jpg)', 'ছবির path (web-public, items/<item id>/photo.jpg)'),
  addPhoto: L('ছবি যোগ (অপেক্ষায়)', 'Add photo (waits for approval)', 'ছবি যোগ (অপেক্ষা)'), approve: L('অনুমোদন', 'Approve', 'অনুমোদন'), unapprove: L('অনুমোদন সরাও', 'Remove approval', 'অনুমোদন সরাও'),
  setHelp: L('প্রতিটি সেটিং আলাদা করে সংরক্ষণ হয়; কোনোটি বদলালে ওয়েবে সাথে সাথে দেখাবে।', 'Each setting is saved on its own; changes show on the web at once.', 'প্রতিটি setting আলাদা save; বদলালে web-এ সাথে সাথে।'),
  url: L('পাবলিক ঠিকানা', 'Public address', 'Public ঠিকানা'), urlNone: L('ডোমেইন/হোস্টিং এখনো নেই — এখন শুধু স্থানীয় পরীক্ষা চলে', 'No domain or hosting yet — only local testing for now', 'ডোমেইন/হোস্টিং নেই — এখন শুধু স্থানীয় পরীক্ষা'),
  orders: L('ওয়েব অর্ডার', 'Web orders', 'Web order'), cancelReq: L('বাতিলের অনুরোধ', 'Cancel requests', 'বাতিলের অনুরোধ'), customReq: L('কাস্টম কেকের অনুরোধ', 'Custom cake requests', 'কাস্টম কেক অনুরোধ'),
  approveC: L('হ্যাঁ, বাতিল করুন', 'Yes, cancel it', 'হ্যাঁ, বাতিল'), declineC: L('না, রাখুন', 'No, keep it', 'না, রাখুন'), confirmC: L('নিশ্চিত', 'Confirm', 'নিশ্চিত'), declineR: L('বাতিল (অনুরোধ)', 'Decline', 'না'),
  zones: L('ডেলিভারি এলাকা', 'Delivery zones', 'ডেলিভারি এলাকা'), zoneName: L('এলাকার নাম (বাংলা)', 'Zone name (Bangla)', 'এলাকার নাম (বাংলা)'), charge: L('ডেলিভারি চার্জ (টাকা)', 'Delivery charge (Tk)', 'ডেলিভারি চার্জ'),
  minOrd: L('এই এলাকায় সর্বনিম্ন অর্ডার', 'Minimum order here', 'সর্বনিম্ন order'), addZone: L('এলাকা যোগ', 'Add zone', 'এলাকা যোগ'),
  pick: L('পিকআপ শাখা (ওয়েবে দেখাবে)', 'Pickup branches (shown on the web)', 'পিকআপ শাখা (web-এ)'), pubOn: L('ওয়েবে দেখাও', 'Show on web', 'web-এ দেখাও'), hours: L('খোলার সময় (বাংলা)', 'Opening hours (Bangla)', 'খোলার সময় (বাংলা)'), hoursEn: L('খোলার সময় (ইংরেজি)', 'Opening hours (English)', 'খোলার সময় (English)'),
  closures: L('ছুটির দিন', 'Closure days', 'ছুটির দিন'), day: L('তারিখ', 'Date', 'তারিখ'), closeNote: L('কারণ (বাংলা)', 'Reason (Bangla)', 'কারণ (বাংলা)'), closeAdd: L('ছুটি যোগ', 'Add closure', 'ছুটি যোগ'), reopen: L('ছুটি তুলুন (মুছবে না)', 'Reopen (nothing is deleted)', 'ছুটি তুলুন (মোছা হয় না)'),
  e_not_allowed: L('এই অংশ শুধু মালিক দেখতে পারেন', 'Only the owner can see this part', 'শুধু মালিক দেখতে পারেন'), e_item_not_sellable: L('আইটেম সক্রিয়, বিক্রয়যোগ্য ও দামসহ হতে হবে', 'The item must be active, sellable and priced', 'আইটেম সক্রিয়, বিক্রয়যোগ্য ও দামসহ হতে হবে'),
  e_bad_path: L('ছবির পথ আইটেমের ফোল্ডারে হতে হবে', 'The photo path must be in the item folder', 'ছবির path আইটেম ফোল্ডারে হতে হবে'), e_bad_diet: L('ধরনের মান ঠিক নয়', 'A diet tag is not valid', 'ধরনের মান ঠিক নয়'),
  e_not_open: L('এই অনুরোধ আগেই সিদ্ধান্ত হয়েছে', 'This request was already decided', 'আগেই সিদ্ধান্ত হয়েছে'),
};
const T = (k) => lab(X[k]);
const msg = (e) => { const m = String((e && e.message) || e || '').replace(/ /g, '_'); const k = Object.keys(X).find((x) => x.startsWith('e_') && m.indexOf(x.slice(2)) >= 0); return k ? T(k) : String((e && e.message) || e || ''); };
const D = { tab: 'board', board: null, golive: null, drift: null, holds: null, items: null, pub: null, rules: null, orders: null, cancels: null, customs: null, zones: null, pick: null, locs: null, closures: null, err: '' };
const SET = [ // key, kind for the input, label
  ['website_on', 'switch'], ['website_location_id', 'number'], ['website_brand_bn', 'text'], ['website_brand_en', 'text'], ['website_whatsapp', 'text'],
  ['website_messenger_url', 'text'], ['website_public_url', 'text'], ['website_stock_threshold', 'number'], ['website_min_order', 'number'], ['website_cutoff_hour', 'number'],
  ['website_lead_days', 'number'], ['website_pay_cod_on', 'switch'], ['website_pay_manual_on', 'switch'], ['website_pay_mobile_number', 'text'], ['website_reserve_on', 'switch'],
  ['website_reserve_minutes', 'number'], ['website_rate_max', 'number'], ['website_rate_window_min', 'number'], ['website_captcha_on', 'switch'], ['website_custom_cake_on', 'switch'],
  ['website_holiday_text_bn', 'text'], ['website_holiday_text_en', 'text'], ['website_festival_mode_on', 'switch'], ['website_pixel_id', 'text'], ['website_ga_id', 'text'],
  ['website_policy_privacy_bn', 'long'], ['website_policy_privacy_en', 'long'], ['website_policy_terms_bn', 'long'], ['website_policy_terms_en', 'long'],
  ['website_policy_refund_bn', 'long'], ['website_policy_refund_en', 'long'],
];
const rid = () => (crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3) | 8).toString(16); }));
const pick = (v) => (v === null || v === undefined ? '' : String(v));

/* ---------- pure helpers (tested) ---------- */
function settingValue(kind, raw) {            // what set_rule receives for a typed input
  if (kind === 'switch') return !!raw;
  if (kind === 'number') { const n = Number(raw); return Number.isFinite(n) ? n : 0; }
  return String(raw == null ? '' : raw);
}
function goLiveSummary(gl) {                   // { ready, missing:[...required not ok], optional:[...] }
  const items = (gl && gl.items) || [];
  return { ready: !!(gl && gl.ready), missing: items.filter((x) => x.required && !x.ok), optional: items.filter((x) => !x.required && !x.ok) };
}
function changedSettings(rows, before) {       // rows: [{key, kind, value}] typed now; before: {key: value}
  return rows.filter((r) => JSON.stringify(before[r.key]) !== JSON.stringify(r.value));
}

/* ---------- drawing ---------- */
const errBox = () => (D.err ? `<p class="notice bad" role="alert">${esc(D.err)}</p>` : '');
const tabs = () => ['board', 'items', 'settings', 'orders', 'places'].map((t) => `<button class="${D.tab === t ? 'primary' : ''}" data-act="web_tab" data-t="${t}">${esc(T('t_' + (t === 'board' ? 'board' : t === 'items' ? 'items' : t === 'settings' ? 'set' : t === 'orders' ? 'orders' : 'places')))}</button>`).join(' ');
function drawBoard() {
  const b = D.board; if (!b) return '<p class="muted">…</p>';
  const gl = goLiveSummary(D.golive);
  const dr = D.drift || {}; const dc = dr.counts || {};
  return `<div class="card stack"><div class="row wrap"><span class="chip ${b.on ? 'ok' : 'warn'}">${esc(b.on ? T('on') : T('off'))}</span>
      <span class="chip">${esc(T('pubItems'))} ${esc(String(b.published_items || 0))}</span><span class="chip">${esc(T('photos'))} ${esc(String(b.approved_photos || 0))}</span>
      <span class="chip">${esc(T('ordersToday'))} ${esc(String(b.web_orders_today || 0))}</span><span class="chip ${b.web_orders_new ? 'warn' : ''}">${esc(T('ordersNew'))} ${esc(String(b.web_orders_new || 0))}</span>
      <span class="chip ${b.cancel_requests_open ? 'warn' : ''}">${esc(T('cancelOpen'))} ${esc(String(b.cancel_requests_open || 0))}</span><span class="chip">${esc(T('customNew'))} ${esc(String(b.custom_requests_new || 0))}</span>
      <span class="chip">${esc(T('holds'))} ${esc(String(b.holds_held || 0))}</span><span class="chip">${esc(T('reserveOn'))}: ${esc(b.reserve_on ? T('on') : T('off'))}</span></div>
      <p class="muted">${esc(T('url'))}: ${esc(D.urlSet ? D.urlSet : T('urlNone'))}</p></div>
    <div class="card stack"><h3>${esc(T('golive'))}</h3><p class="${gl.ready ? 'chip ok' : 'chip warn'}">${esc(gl.ready ? T('ready') : T('notReady'))}</p>
      ${(D.golive ? D.golive.items : []).map((x) => `<div class="row between wrap"><span>${x.ok ? '✓' : '✗'} ${esc(lab(x))} <span class="muted">(${esc(x.required ? T('req') : T('opt'))})</span></span>
        ${x.ok ? '' : `<span class="muted" style="font-size:.9rem">${esc(lab({ bn: x.how_bn, en: x.how_en }))}</span>`}</div>`).join('')}</div>
    <div class="card stack"><h3>${esc(T('drift'))}</h3><p class="muted">${esc(T('driftNote'))}</p>
      <div class="row wrap"><span class="chip ${dc.price_changed ? 'warn' : 'ok'}">${esc(T('drift'))}: ${esc(String(dc.price_changed || 0))} / ${esc(String(dc.not_sellable || 0))} / ${esc(String(dc.holds_over_stock || 0))}</span></div>
      ${(dr.not_sellable || []).length ? `<p class="muted">${esc(String(dr.not_sellable.length))} ×</p>` : ''}</div>`;
}
function drawItems() {
  if (!D.items) return '<p class="muted">…</p>';
  const pub = D.pub || {};
  const cats = [...new Set(D.items.map((i) => i.category).filter(Boolean))].sort();
  return `<div class="card stack"><label>${esc(T('cat'))}<select id="w_cat">${cats.map((c) => `<option>${esc(c)}</option>`).join('')}</select></label>
      <div class="row wrap"><button data-act="web_bulk" data-on="1">${esc(T('bulkOn'))}</button><button data-act="web_bulk" data-on="0">${esc(T('bulkOff'))}</button></div></div>
    ${D.items.map((i) => { const p = pub[i.id] || {}; return `<div class="card stack" data-item="${esc(i.id)}">
      <div class="row between wrap"><b>${esc(i.name_bn || '')}</b><span class="muted">${esc(i.category || '')}${i.sell_price != null ? ' · ৳' + esc(String(i.sell_price)) : ''}</span></div>
      <label class="row"><input type="checkbox" class="w_pub" ${p.published ? 'checked' : ''}> ${esc(T('pub'))}</label>
      <label>${esc(T('nameBn'))}<input class="w_nb" value="${esc(pick(p.name_bn))}"></label>
      <label>${esc(T('nameEn'))}<input class="w_ne" value="${esc(pick(p.name_en))}"></label>
      <label>${esc(T('descBn'))}<textarea class="w_db" rows="2">${esc(pick(p.desc_bn))}</textarea></label>
      <label>${esc(T('descEn'))}<textarea class="w_de" rows="2">${esc(pick(p.desc_en))}</textarea></label>
      <div class="row wrap"><label>${esc(T('pcat'))}<input class="w_pc" value="${esc(pick(p.category_pub))}"></label>
        <label>${esc(T('sort'))}<input class="w_so" type="number" value="${esc(String(p.sort || 0))}"></label>
        <label>${esc(T('lead'))}<input class="w_ld" type="number" min="0" max="60" value="${esc(String(p.lead_days || 0))}"></label></div>
      <label>${esc(T('avail'))}<select class="w_av"><option value="auto" ${(p.avail_mode || 'auto') === 'auto' ? 'selected' : ''}>${esc(T('a_auto'))}</option><option value="preorder" ${p.avail_mode === 'preorder' ? 'selected' : ''}>${esc(T('a_pre'))}</option><option value="sold_out" ${p.avail_mode === 'sold_out' ? 'selected' : ''}>${esc(T('a_sold'))}</option></select></label>
      <label>${esc(T('allergen'))}<input class="w_al" value="${esc(pick(p.allergens))}"></label>
      <label>${esc(T('diet'))}<input class="w_dt" value="${esc((p.diet || []).join(','))}"></label>
      <div><button class="primary" data-act="web_item_save" data-id="${esc(i.id)}">${esc(T('save'))}</button></div></div>`; }).join('')}
    <div class="card stack"><h3>${esc(T('photos'))}</h3><p class="muted">${esc(T('photoPath'))}</p>
      <label>${esc(T('photoPath'))}<input id="w_ph_path"></label><div class="row wrap"><button data-act="web_photo_add">${esc(T('addPhoto'))}</button></div>
      ${(D.photos || []).map((x) => `<div class="row between wrap"><span>${esc(x.storage_path)}</span><span class="chip ${x.approved ? 'ok' : 'warn'}">${esc(x.approved ? T('approve') : T('addPhoto'))}</span>
        <button data-act="web_photo_ok" data-id="${esc(String(x.id))}" data-v="${x.approved ? '0' : '1'}">${esc(x.approved ? T('unapprove') : T('approve'))}</button></div>`).join('')}</div>`;
}
function drawSettings() {
  if (!D.rules) return '<p class="muted">…</p>';
  return `<div class="card stack"><p class="muted">${esc(T('setHelp'))}</p>${SET.map(([k, kind]) => {
    const r = D.rules[k] || {}; const v = r.value;
    const lbl = esc(lab(L(r.label_bn || k, r.label_en || k, r.label_en || k)));
    if (kind === 'switch') return `<label class="row"><input type="checkbox" class="w_set" data-key="${esc(k)}" data-kind="switch" ${v === true ? 'checked' : ''}> ${lbl}</label>`;
    if (kind === 'long') return `<label>${lbl}<textarea class="w_set" data-key="${esc(k)}" data-kind="text" rows="4">${esc(pick(v))}</textarea></label>`;
    return `<label>${lbl}<input class="w_set" data-key="${esc(k)}" data-kind="${kind}" ${kind === 'number' ? 'type="number"' : ''} value="${esc(pick(v))}"></label>`;
  }).join('')}
  <div class="row wrap"><button class="primary" data-act="web_settings_save">${esc(T('save'))}</button></div></div>`;
}
function drawOrders() {
  if (!D.orders) return '<p class="muted">…</p>';
  const rows = D.orders;
  return `<div class="card stack"><h3>${esc(T('orders'))}</h3>${rows.length ? rows.map((o) => `<div class="row between wrap"><span>#${esc(String(o.order_no))} · ${esc(o.web_code || '')} · ${esc(o.customer_name || '')} · ${esc(o.customer_mobile || '')}</span>
      <span class="chip">${esc(o.status)} · ${esc(String(o.subtotal || 0))}${o.sale_id ? ' ✓' : ''}</span></div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`}</div>
    <div class="card stack"><h3>${esc(T('cancelReq'))}</h3>${(D.cancels || []).map((c) => `<div class="stack"><div>#${esc(String(c.order_no))} · ${esc(c.reason || '')}</div>
      <div class="row wrap"><button class="primary" data-act="web_cancel_dec" data-id="${esc(String(c.id))}" data-v="1">${esc(T('approveC'))}</button><button data-act="web_cancel_dec" data-id="${esc(String(c.id))}" data-v="0">${esc(T('declineC'))}</button></div></div>`).join('') || `<p class="muted">${esc(T('none'))}</p>`}</div>
    <div class="card stack"><h3>${esc(T('customReq'))}</h3>${(D.customs || []).map((c) => `<div class="stack"><div>${esc(c.code)} · ${esc(c.name)} · ${esc(c.mobile)} · ${esc(c.flavour || '')} · ${esc(String(c.weight_kg || ''))}kg · ${esc(String(c.wanted_date))} ${esc(c.slot || '')}</div>
      <div>${esc(c.message || '')}${c.ref_path ? ' · photo: ' + esc(c.ref_path) : ''}</div>
      ${c.state === 'new' ? `<div class="row wrap"><button class="primary" data-act="web_custom_dec" data-id="${esc(String(c.id))}" data-v="confirmed">${esc(T('confirmC'))}</button><button data-act="web_custom_dec" data-id="${esc(String(c.id))}" data-v="declined">${esc(T('declineR'))}</button></div>` : `<span class="chip">${esc(c.state)}</span>`}</div>`).join('') || `<p class="muted">${esc(T('none'))}</p>`}</div>`;
}
function drawPlaces() {
  const z = D.zones || [], p = D.pick || [], c = D.closures || [], L2 = D.locs || [];
  return `<div class="card stack"><h3>${esc(T('zones'))}</h3>${z.map((x) => `<div class="row between wrap"><span>${esc(x.name_bn)} · ৳${esc(String(x.charge))} · ${esc(T('minOrd'))} ৳${esc(String(x.min_order))}</span><span class="chip ${x.active ? 'ok' : ''}">${esc(x.active ? T('on') : T('off'))}</span></div>`).join('') || `<p class="muted">${esc(T('none'))}</p>`}
      <div class="row wrap"><label>${esc(T('zoneName'))}<input id="w_z_name"></label><label>${esc(T('charge'))}<input id="w_z_charge" type="number" min="0"></label>
      <label>${esc(T('minOrd'))}<input id="w_z_min" type="number" min="0" value="0"></label><button data-act="web_zone_add">${esc(T('addZone'))}</button></div></div>
    <div class="card stack"><h3>${esc(T('pick'))}</h3>${L2.map((l) => { const pp = p.find((x) => x.location_id === l.id) || {}; return `<div class="stack"><div class="row between wrap"><b>${esc(l.name_bn || '')}</b>
      <label class="row"><input type="checkbox" class="w_pk" data-loc="${esc(String(l.id))}" ${pp.public ? 'checked' : ''}> ${esc(T('pubOn'))}</label></div>
      <label>${esc(T('hours'))}<input class="w_hb" data-loc="${esc(String(l.id))}" value="${esc(pick(pp.hours_bn))}"></label>
      <label>${esc(T('hoursEn'))}<input class="w_he" data-loc="${esc(String(l.id))}" value="${esc(pick(pp.hours_en))}"></label>
      <div><button data-act="web_pick_save" data-loc="${esc(String(l.id))}">${esc(T('save'))}</button></div></div>`; }).join('')}</div>
    <div class="card stack"><h3>${esc(T('closures'))}</h3>${c.map((x) => `<div class="row between wrap"><span>${esc(String(x.day))} · ${esc(x.note_bn || '')}</span><span class="chip ${x.reopened ? '' : 'warn'}">${esc(x.reopened ? T('on') : T('off'))}</span>
      ${x.reopened ? '' : `<button data-act="web_close_reopen" data-day="${esc(String(x.day))}">${esc(T('reopen'))}</button>`}</div>`).join('') || `<p class="muted">${esc(T('none'))}</p>`}
      <div class="row wrap"><label>${esc(T('day'))}<input id="w_cl_day" type="date"></label><label>${esc(T('closeNote'))}<input id="w_cl_note"></label><button data-act="web_close_add">${esc(T('closeAdd'))}</button></div></div>`;
}
function draw() {
  const body = $('#w_body'); if (!body) return;
  const parts = { board: drawBoard, items: drawItems, settings: drawSettings, orders: drawOrders, places: drawPlaces }[D.tab] || drawBoard;
  body.innerHTML = `<p class="muted">${esc(T('intro'))}</p><div class="row wrap">${tabs()}</div>${errBox()}${parts()}`;
}

/* ---------- loading ---------- */
async function load(tab) {
  D.err = '';
  const ask = async (name, args) => { const r = await sb.rpc(name, args || {}); if (r.error) throw r.error; return r.data; };
  try {
    if (tab === 'board') {
      D.board = await ask('web_admin_board'); D.golive = await ask('web_admin_go_live'); D.drift = await ask('web_admin_drift'); D.holds = await ask('web_admin_holds_report');
      const u = await sb.from('rules').select('value').eq('key', 'website_public_url'); if (u.error) throw u.error;
      D.urlSet = u.data && u.data[0] && u.data[0].value ? String(u.data[0].value) : '';
    }
    if (tab === 'items') {
      const it = await sb.from('items').select('id,name_bn,category,sell_price,is_active,sellable,hidden,retired_at').eq('is_active', true).order('name_bn', { ascending: true }).limit(500);
      if (it.error) throw it.error; D.items = (it.data || []).filter((x) => x.sellable && !x.hidden && !x.retired_at);
      const p = await sb.from('web_item_pub').select('*'); if (p.error) throw p.error;
      D.pub = {}; (p.data || []).forEach((x) => { D.pub[x.item_id] = x; });
      const ph = await sb.from('web_item_images').select('id,storage_path,approved').order('id', { ascending: false }).limit(200); D.photos = ph.data || [];
    }
    if (tab === 'settings') {
      const r = await sb.from('rules').select('key,value,label_bn,label_en,kind').like('key', 'website\\_%'); if (r.error) throw r.error;
      D.rules = {}; (r.data || []).forEach((x) => { D.rules[x.key] = x; });
      D.urlSet = D.rules.website_public_url && D.rules.website_public_url.value ? String(D.rules.website_public_url.value) : '';
    }
    if (tab === 'orders') { D.orders = await ask('web_admin_web_orders', { p_limit: 100 }); D.cancels = await ask('web_admin_cancel_list'); D.customs = await ask('web_admin_custom_list'); }
    if (tab === 'places') {
      D.zones = (await sb.from('web_zones').select('*').order('sort', { ascending: true })).data || [];
      D.pick = (await sb.from('web_pickup_points').select('*')).data || [];
      D.locs = ((await sb.from('locations').select('id,name_bn,is_active').eq('is_active', true).order('sort', { ascending: true })).data || []);
      D.closures = ((await sb.from('web_closures').select('*').order('day', { ascending: false }).limit(100)).data) || [];
    }
  } catch (e) { D.err = msg(e); }
  draw();
}
const bodyOf = (a) => a.closest('[data-item]');

/* ---------- actions ---------- */
Object.assign(H, {
  web_tab: async (a) => { D.tab = a.dataset.t; await load(D.tab); },
  web_item_save: async (a) => {
    const card = bodyOf(a); const v = (c) => (card.querySelector(c) || {}).value || '';
    const diet = v('.w_dt').split(',').map((x) => x.trim()).filter(Boolean);
    const r = await sb.rpc('web_admin_item_save', { p_item: a.dataset.id, p: { published: card.querySelector('.w_pub').checked, name_bn: v('.w_nb'), name_en: v('.w_ne'),
      desc_bn: v('.w_db'), desc_en: v('.w_de'), category_pub: v('.w_pc'), sort: Number(v('.w_so')) || 0, lead_days: Number(v('.w_ld')) || 0, avail_mode: v('.w_av'),
      allergens: v('.w_al'), diet } });
    if (r.error) return toast(msg(r.error)); toast(T('saved')); await load('items');
  },
  web_bulk: async (a) => {
    const cat = ($('#w_cat') || {}).value; if (!cat) return;
    const r = await sb.rpc('web_admin_publish_bulk', { p_category: cat, p_published: a.dataset.on === '1' });
    if (r.error) return toast(msg(r.error)); toast(T('saved') + ' · ' + (r.data && r.data.items)); await load('items');
  },
  web_photo_add: async () => {
    const path = (($('#w_ph_path') || {}).value || '').trim(); const m = path.match(/^items\/([0-9a-f-]{36})\//i);
    if (!m) return toast(T('e_bad_path'));
    const ext = path.toLowerCase().split('.').pop(); const mime = ext === 'png' ? 'image/png' : ext === 'webp' ? 'image/webp' : 'image/jpeg';
    const r = await sb.rpc('web_admin_image_add', { p_item: m[1], p_path: path, p_mime: mime, p_bytes: 1 });
    if (r.error) return toast(msg(r.error)); toast(T('saved')); await load('items');
  },
  web_photo_ok: async (a) => { const r = await sb.rpc('web_admin_image_approve', { p_id: Number(a.dataset.id), p_approve: a.dataset.v === '1' }); if (r.error) return toast(msg(r.error)); await load('items'); },
  web_settings_save: async () => {
    const rows = [...document.querySelectorAll('.w_set')].map((el) => ({ key: el.dataset.key, kind: el.dataset.kind, value: settingValue(el.dataset.kind, el.dataset.kind === 'switch' ? el.checked : el.value) }));
    const before = {}; Object.keys(D.rules || {}).forEach((k) => { before[k] = D.rules[k].value; });
    const todo = changedSettings(rows, before);
    for (const r of todo) { const x = await sb.rpc('set_rule', { p_key: r.key, p_value: r.value }); if (x.error) return toast(msg(x.error)); }
    toast(T('saved') + ' · ' + todo.length); await load('settings');
  },
  web_cancel_dec: async (a) => { const r = await sb.rpc('web_admin_cancel_decide', { p_id: Number(a.dataset.id), p_approve: a.dataset.v === '1', p_note: null }); if (r.error) return toast(msg(r.error)); await load('orders'); },
  web_custom_dec: async (a) => { const r = await sb.rpc('web_admin_custom_decide', { p_id: Number(a.dataset.id), p_state: a.dataset.v, p_note: null }); if (r.error) return toast(msg(r.error)); await load('orders'); },
  web_zone_add: async () => {
    const r = await sb.rpc('web_admin_zone_save', { p_id: null, p: { name_bn: ($('#w_z_name').value || '').trim(), charge: Number($('#w_z_charge').value) || 0, min_order: Number($('#w_z_min').value) || 0, active: true } });
    if (r.error) return toast(msg(r.error)); toast(T('saved')); await load('places');
  },
  web_pick_save: async (a) => {
    const loc = Number(a.dataset.loc); const pk = document.querySelector(`.w_pk[data-loc="${loc}"]`);
    const hb = document.querySelector(`.w_hb[data-loc="${loc}"]`).value; const he = document.querySelector(`.w_he[data-loc="${loc}"]`).value;
    const r = await sb.rpc('web_admin_pickup_save', { p_loc: loc, p: { public: pk.checked, hours_bn: hb, hours_en: he } });
    if (r.error) return toast(msg(r.error)); toast(T('saved')); await load('places');
  },
  web_close_add: async () => {
    const day = ($('#w_cl_day').value || ''); const note = ($('#w_cl_note').value || '').trim();
    if (!day) return toast(T('day'));
    const r = await sb.rpc('web_admin_closure_save', { p_day: day, p_bn: note, p_en: note, p_reopen: false });
    if (r.error) return toast(msg(r.error)); toast(T('saved')); await load('places');
  },
  web_close_reopen: async (a) => { const r = await sb.rpc('web_admin_closure_save', { p_day: a.dataset.day, p_bn: null, p_en: null, p_reopen: true }); if (r.error) return toast(msg(r.error)); await load('places'); },
});

async function view() {
  if (B.loadStatic) await B.loadStatic();
  D.tab = 'board'; D.err = '';
  shell(T('title'), '<div id="w_body" class="stack"></div>', true);
  await load('board');
}
B.website = { settingValue, goLiveSummary, changedSettings, SET, rid };
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { website: view });
})();
