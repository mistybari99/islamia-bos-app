/* Islamia BOS · Cash drawer option (bos95). Server side: supabase/phase95.sql (rules cash_drawer_*, grant drawer_nosale, drawer_events, drawer_settings, drawer_event_log, drawer_report).
   B.drawer.open(reason) asks the configured driver to open the drawer; drivers are pluggable (B.drawer.register). A missing or broken drawer FAILS SOFT:
   a toast "Drawer not connected", the sale carries on, and the event is logged as "failed". Nothing here can block, delay or change a sale.
   Rule cash_drawer_mode = off (the default) makes every hook a no-op: no rpc, no log, no toast.
   Drivers (all send ESC/POS "ESC p 0 25 250" = pin 2, on 50 ms, off 500 ms): web_serial, web_usb, bluetooth (experimental), browser_print_pulse (a tiny print job; the printer driver must be set
   to open the drawer on print). kiosk_url is a PLANNED placeholder. Events are queued on the device while offline and sent later (idempotent by client id).
   POS hooks (tagged bos95 in pos.js): beforeSale, afterSale, noSaleButton. Screen: #/cashdrawer. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, store } = A;
const L = B.L, lab = B.lab;
const $ = (s, el) => (typeof document === 'undefined' ? null : (el || document).querySelector(s));
const PULSE = [0x1b, 0x70, 0x00, 0x19, 0xfa];            // ESC p 0 25 250
const MODES = ['off', 'on_cash_sale', 'on_any_sale', 'manual_only'], WHENS = ['before_payment', 'after_payment'];
const METHODS = ['none', 'browser_print_pulse', 'web_serial', 'web_usb', 'bluetooth', 'kiosk_url'];
const STATUS = { none: 'ready', browser_print_pulse: 'ready', web_serial: 'ready', web_usb: 'ready', bluetooth: 'experimental', kiosk_url: 'planned' };

// ---------- texts (new texts only; Bangla mode keeps the common words English, so bn follows the mix text) ----------
const X = {
  title: L('ক্যাশ ড্রয়ার', 'Cash drawer', 'Cash drawer'),
  intro: L('এখানে ক্যাশ ড্রয়ার লাগানোর আগেই সেটিং ঠিক করে রাখা যায়। ড্রয়ার না থাকলে বা সংযোগ না থাকলে বিক্রি কখনো আটকায় না। সব বন্ধ থাকলে (ডিফল্ট) আগের মতোই চলে।',
    'Set the cash drawer option here, even before a drawer is fitted. A missing or disconnected drawer never blocks a sale. With everything off (the default) nothing changes.',
    'এখানে Cash drawer লাগানোর আগেই setting ঠিক করে রাখা যায়। Drawer না থাকলে বা connection না থাকলে sale কখনো আটকায় না। সব off থাকলে (default) আগের মতোই চলে।'),
  sql: L('এই অংশ চালু করতে নতুন SQL (phase95) চালাতে হবে।', 'The new SQL (phase95) must be run to switch this part on.', 'এই অংশ চালু করতে নতুন SQL (phase95) চালাতে হবে।'),
  gMode: L('কখন খুলবে', 'When it opens', 'কখন খুলবে'), gWhen: L('সেলের আগে না পরে', 'Before or after the sale', 'Sale-এর আগে না পরে'),
  gMethod: L('সংযোগের ধরন', 'Connection type', 'Connection type'), gReason: L('"No sale" খুলতে কারণ লাগবে', 'A "No sale" open needs a reason', '"No sale" খুলতে reason লাগবে'),
  on: L('চালু', 'On', 'On'), off: L('বন্ধ', 'Off', 'Off'),
  m_off: L('বন্ধ (আগের মতো)', 'Off (as today)', 'Off (আগের মতো)'), m_on_cash_sale: L('ক্যাশ বিক্রিতে', 'On cash sale', 'Cash sale-এ'), m_on_any_sale: L('যেকোনো বিক্রিতে', 'On any sale', 'যেকোনো sale-এ'), m_manual_only: L('শুধু হাতে (No sale)', 'Manual only (No sale)', 'শুধু manual (No sale)'),
  w_before_payment: L('সেভের আগে', 'Before payment', 'Payment-এর আগে'), w_after_payment: L('সেভের পরে', 'After payment', 'Payment-এর পরে'),
  c_none: L('কিছু না', 'None', 'None'), c_browser_print_pulse: L('প্রিন্ট পালস', 'Print pulse', 'Print pulse'), c_web_serial: L('Web Serial (USB/সিরিয়াল)', 'Web Serial (USB / serial)', 'Web Serial (USB/serial)'),
  c_web_usb: L('Web USB', 'Web USB', 'Web USB'), c_bluetooth: L('Bluetooth (পরীক্ষামূলক)', 'Bluetooth (experimental)', 'Bluetooth (experimental)'), c_kiosk_url: L('Kiosk URL (পরিকল্পিত)', 'Kiosk URL (planned)', 'Kiosk URL (planned)'),
  sugg: L('প্রস্তাব', 'Suggestion', 'Suggestion'), recmark: L('প্রস্তাবিত', 'Suggested', 'Suggested'), planned: L('পরিকল্পিত, এখনো কাজ করে না', 'planned, not built yet', 'planned, এখনো কাজ করে না'),
  d_mode_off: L('কিছুই হয় না, আজকের মতো। ড্রয়ার লাগানো না হওয়া পর্যন্ত এটাই রাখুন।', 'Nothing happens, as today. Keep this until a drawer is fitted.', 'কিছুই হয় না, আজকের মতো। Drawer লাগানো না হওয়া পর্যন্ত এটাই রাখুন।'),
  d_mode_on_cash_sale: L('প্রস্তাবিত (ড্রয়ার লাগানোর পর): শুধু ক্যাশ নিলে খোলে।', 'Suggested once a drawer is fitted: opens only when cash is taken.', 'Suggested (drawer লাগানোর পর): শুধু cash নিলে খোলে।'),
  d_mode_on_any_sale: L('মোবাইল/কার্ড বিক্রিতেও খোলে। সাধারণত দরকার নেই, আর ফাঁকা খোলা বেশি হলে নজরদারি কঠিন।', 'Opens for mobile and card sales too. Usually not needed, and more openings are harder to audit.', 'Mobile/card sale এও খোলে। সাধারণত দরকার নেই, আর বেশি খুললে audit কঠিন।'),
  d_mode_manual_only: L('সেলের সাথে খোলে না; শুধু "No sale" বোতামে খোলে, প্রতিবার কারণসহ লগ হয়।', 'Never opens with a sale; only the "No sale" button opens it, and each open is logged with a reason.', 'Sale-এর সাথে খোলে না; শুধু "No sale" button-এ খোলে, প্রতিবার reason সহ log হয়।'),
  d_when_after_payment: L('প্রস্তাবিত: সেল সেভ হলে তবেই খোলে।', 'Suggested: opens only once the sale is saved.', 'Suggested: sale save হলে তবেই খোলে।'),
  d_when_before_payment: L('সেভ চাপলেই খোলে, সেল পরে ব্যর্থ হলেও। শুধু তখনই বাছুন যখন ক্যাশিয়ার আগে থেকে ড্রয়ার প্রস্তুত চায়।', 'Opens as soon as Save is tapped, even if the sale then fails. Choose it only if the cashier wants the drawer ready first.', 'Save চাপলেই খোলে, sale পরে fail করলেও। শুধু তখনই বাছুন যখন cashier আগে থেকে drawer ready চায়।'),
  d_method_none: L('কোনো ড্রয়ার সংযুক্ত নেই। ড্রয়ার লাগানোর পর নিচের একটি বাছুন।', 'No drawer connected. Pick one below after a drawer is fitted.', 'কোনো drawer connected নেই। Drawer লাগানোর পর নিচের একটি বাছুন।'),
  d_method_browser_print_pulse: L('যেকোনো রসিদ প্রিন্টারে চলে যার ড্রাইভারে "প্রিন্ট করলে drawer খোলো" দেওয়া। প্রতিবার প্রিন্ট ডায়ালগে ট্যাপ লাগতে পারে। সবচেয়ে সহজ, কিন্তু কম নির্ভরযোগ্য।', 'Works with any receipt printer whose driver is set to open the drawer on print. A print dialog may need a tap each time. Simplest, but least reliable.', 'যেকোনো receipt printer-এ চলে যার driver-এ "print করলে drawer খোলো" দেওয়া। প্রতিবার print dialog-এ tap লাগতে পারে। সবচেয়ে সহজ, কিন্তু কম reliable।'),
  d_method_web_serial: L('প্রস্তাবিত: USB/সিরিয়াল রসিদ প্রিন্টারে (কম্পিউটার বা Android Chrome)। প্রিন্টারে সরাসরি খোলার সংকেত যায়। প্রতি ডিভাইসে একবার Connect করতে হয়।', 'Suggested for a USB or serial receipt printer on a PC or Chrome on Android: the open pulse goes straight to the printer. Connect once per device.', 'Suggested: USB/serial receipt printer-এ (computer বা Android Chrome)। Printer-এ সরাসরি open signal যায়। প্রতি device-এ একবার Connect করতে হয়।'),
  d_method_web_usb: L('Chrome-এ (কম্পিউটার বা Android) USB প্রিন্টারে, যদি প্রিন্টার সরাসরি USB অ্যাক্সেস দেয়। না চললে Web Serial বা প্রিন্ট পালস দেখুন।', 'For USB printers in Chrome (PC or Android) when the printer allows direct USB access. If it does not work, try Web Serial or Print pulse.', 'Chrome-এ (computer বা Android) USB printer-এ, যদি printer সরাসরি USB access দেয়। না চললে Web Serial বা Print pulse দেখুন।'),
  d_method_bluetooth: L('পরীক্ষামূলক: Android Chrome-এ Bluetooth প্রিন্টার; অনেক প্রিন্টার নিজস্ব সার্ভিস ব্যবহার করে তাই না-ও চলতে পারে। iPhone-এ চলে না।', 'Experimental: Bluetooth printers in Chrome on Android; many printers use their own services so it may not work. Does not work on iPhone.', 'Experimental: Android Chrome-এ Bluetooth printer; অনেক printer নিজস্ব service ব্যবহার করে তাই না-ও চলতে পারে। iPhone-এ চলে না।'),
  d_method_kiosk_url: L('পরিকল্পিত: এখনো তৈরি হয়নি, বাছলেও কিছু খুলবে না।', 'Planned: not built yet; choosing it opens nothing.', 'Planned: এখনো build হয়নি, বাছলেও কিছু খুলবে না।'),
  d_reason: L('প্রস্তাবিত: চালু। কারণ ছাড়া খোলা মানেই চুরির ঝুঁকির সংকেত।', 'Suggested: on. Every open without a sale is an anti-theft signal, so ask why.', 'Suggested: on। Sale ছাড়া প্রতিটি open একটি anti-theft signal, তাই কারণ জিজ্ঞেস করুন।'),
  device: L('এই ডিভাইস', 'This device', 'এই device'), conn: L('সংযুক্ত', 'Connected', 'Connected'), notconn: L('সংযুক্ত নয়', 'Not connected', 'Not connected'), unsup: L('এই ব্রাউজারে চলবে না', 'Not supported in this browser', 'এই browser-এ চলবে না'),
  connect: L('ডিভাইস সংযুক্ত করুন', 'Connect device', 'Device Connect করুন'), test: L('খোলার টেস্ট', 'Test open', 'Test open'),
  connected: L('সংযুক্ত হয়েছে', 'Device connected', 'Device connected'), connFail: L('সংযুক্ত করা যায়নি', 'Could not connect', 'Connect করা যায়নি'), tested: L('টেস্ট পাঠানো হয়েছে', 'Test sent', 'Test পাঠানো হয়েছে'),
  hereNote: L('Connect আর Test সেই ডিভাইসে করুন যেটা কাউন্টারে ড্রয়ারের সাথে লাগানো। মালিক নিজের ফোন থেকে শুধু সেটিং বদলাতে পারেন।', 'Connect and Test on the device that is next to the drawer at the counter. The owner can change the settings from any phone.', 'Connect আর Test সেই device-এ করুন যেটা counter-এ drawer-এর সাথে লাগানো। Owner নিজের phone থেকে শুধু setting বদলাতে পারেন।'),
  ownerOnly: L('সেটিং বদলাতে পারেন শুধু মালিক।', 'Only the owner can change these settings.', 'Setting বদলাতে পারেন শুধু owner।'),
  saved: L('সেভ হয়েছে', 'Saved', 'Saved'), badv: L('এই মান নেওয়া যায়নি', 'That value was refused', 'এই value নেওয়া যায়নি'),
  notConn: L('Drawer সংযুক্ত নেই — সেল ঠিকই হয়েছে', 'Drawer not connected — the sale is not affected', 'Drawer connected নেই — sale ঠিকই হয়েছে'),
  noBrowser: L('এই ব্রাউজারে ড্রয়ার চলবে না — সেল ঠিকই হয়েছে', 'This browser cannot open the drawer — the sale is not affected', 'এই browser-এ drawer চলবে না — sale ঠিকই হয়েছে'),
  noSale: L('No sale (ড্রয়ার খুলুন)', 'No sale (open drawer)', 'No sale (drawer খুলুন)'), noSaleH: L('সেল ছাড়া ড্রয়ার খোলা', 'Open the drawer with no sale', 'Sale ছাড়া drawer খোলা'),
  why: L('কারণ', 'Reason', 'Reason'), needWhy: L('কারণ লিখুন', 'Write a reason', 'Reason লিখুন'), w1: L('খুচরা দিতে', 'Making change', 'Change দিতে'), w2: L('ক্যাশ গোনা', 'Cash check', 'Cash check'), w3: L('অন্য', 'Other', 'Other'),
  open: L('ড্রয়ার খুলুন', 'Open drawer', 'Drawer খুলুন'), cancel: L('ক্যান্সেল', 'Cancel', 'Cancel'),
  noSaleLogged: L('No sale খোলা লগ হয়েছে', 'No-sale open logged', 'No-sale open log হয়েছে'),
  rep: L('No-sale রিপোর্ট', 'No-sale report', 'No-sale report'), repNote: L('এটা সংকেত, প্রমাণ নয়। অস্বাভাবিক সংখ্যা দেখলে আগে ক্যাশিয়ারের সাথে কথা বলুন ও দিনের ক্যাশ গোনার সাথে মেলান।', 'These are signals, not proof. If a number looks unusual, talk to the cashier first and compare with the day cash count.', 'এটা signal, proof নয়। অস্বাভাবিক সংখ্যা দেখলে আগে cashier-এর সাথে কথা বলুন ও দিনের cash count-এর সাথে মেলান।'),
  days: L('দিন', 'days', 'days'), staff: L('স্টাফ', 'Staff', 'Staff'), nosaleC: L('No sale', 'No sale', 'No sale'), autoC: L('অটো', 'Auto', 'Auto'), failC: L('ব্যর্থ', 'Failed', 'Failed'), testC: L('টেস্ট', 'Tests', 'Tests'),
  none: L('এই সময়ে কোনো ঘটনা নেই', 'No events in this period', 'এই সময়ে কোনো event নেই'), recent: L('সাম্প্রতিক No sale', 'Recent no-sale opens', 'Recent No sale'), total: L('টোটাল', 'Total', 'Total'),
  on_screen: L('চালু আছে', 'Active', 'Active'), summary: L('এখনকার সেটিং', 'Current settings', 'Current setting'),
};
for (const k of Object.keys(X)) X[k].bn = X[k].mix || X[k].bn;   // Bangla mode keeps the common words English, same as the mix text
const TX = (k) => lab(X[k]);

// ---------- small helpers ----------
const nav = () => (typeof navigator === 'undefined' ? null : navigator);
const online = () => { const n = nav(); return !n || n.onLine !== false; };
const uid = () => (typeof crypto !== 'undefined' && crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); }));
const rule = (k, f) => { try { return B.rule ? B.rule(k, f) : f; } catch (e) { return f; } };
const isOwner = () => !!(A.S && A.S.ctx && A.S.ctx.is_owner);
const uidK = () => (A.S && A.S.ctx && A.S.ctx.profile ? A.S.ctx.profile.id : 'anon');
const jget = (k, d) => { try { const v = JSON.parse(store.get(k)); return v === null || v === undefined ? d : v; } catch (e) { return d; } };
const jset = (k, v) => { try { store.set(k, JSON.stringify(v)); } catch (e) { /* storage blocked: nothing to remember */ } };
const err = (code) => { const e = new Error(code); e.code = code; return e; };
function cfg() {
  const m = rule('cash_drawer_mode', 'off'), w = rule('cash_drawer_when', 'after_payment'), c = rule('cash_drawer_method', 'none');
  return { mode: MODES.includes(m) ? m : 'off', when: WHENS.includes(w) ? w : 'after_payment', method: METHODS.includes(c) ? c : 'none', needReason: rule('cash_drawer_no_sale_requires_reason', true) !== false };
}

// ---------- drivers ----------
const drivers = {};
const register = (id, d) => { drivers[id] = Object.assign({ id, status: STATUS[id] || 'ready' }, d); };
const chunks = (u8, n) => { const o = []; for (let i = 0; i < u8.length; i += n) o.push(u8.slice(i, i + n)); return o; };
const bytes = () => new Uint8Array(PULSE);

register('none', { supported: () => false, connected: async () => false, connect: async () => false, open: async () => { throw err('no_driver'); } });
register('kiosk_url', { status: 'planned', supported: () => false, connected: async () => false, connect: async () => false, open: async () => { throw err('planned'); } });

register('browser_print_pulse', {
  supported: () => typeof document !== 'undefined' && !!document.body && !!nav(),
  connected: async () => true,                      // nothing to pair: the printer driver must be set to open the drawer on print
  connect: async () => true,
  async open() {
    if (typeof document === 'undefined' || !document.body) throw err('unsupported');
    const f = document.createElement('iframe');
    f.setAttribute('aria-hidden', 'true'); f.style.cssText = 'position:fixed;width:0;height:0;border:0;right:0;bottom:0';
    document.body.appendChild(f);
    try {
      const d = f.contentWindow.document; d.open(); d.write('<!doctype html><html><head><style>@page{size:58mm 5mm;margin:0}body{margin:0}</style></head><body>&nbsp;</body></html>'); d.close();
      f.contentWindow.focus(); f.contentWindow.print();
    } finally { setTimeout(() => { try { f.remove(); } catch (e) { /* gone */ } }, 4000); }
  },
});

const serial = {
  port: null,
  supported: () => !!(nav() && nav().serial),
  async have() { if (this.port) return this.port; const ps = await nav().serial.getPorts(); this.port = ps && ps.length ? ps[0] : null; return this.port; },
  async connected() { return !!(await this.have()); },
  async connect() { this.port = await nav().serial.requestPort(); return !!this.port; },
  async open() {
    const p = await this.have(); if (!p) throw err('not_connected');
    try { await p.open({ baudRate: 9600 }); } catch (e) { if (!/already open|InvalidState/i.test(String((e && (e.name + ' ' + e.message)) || ''))) throw e; }
    const w = p.writable.getWriter();
    try { await w.write(bytes()); } finally { w.releaseLock(); }
    try { await p.close(); } catch (e) { /* the printer keeps the pulse; a port that will not close is harmless */ }
  },
};
register('web_serial', serial);

const usb = {
  dev: null,
  supported: () => !!(nav() && nav().usb),
  async have() { if (this.dev) return this.dev; const ds = await nav().usb.getDevices(); this.dev = ds && ds.length ? ds[0] : null; return this.dev; },
  async connected() { return !!(await this.have()); },
  async connect() { this.dev = await nav().usb.requestDevice({ filters: [{ classCode: 7 }] }); return !!this.dev; },
  async open() {
    const d = await this.have(); if (!d) throw err('not_connected');
    if (!d.opened) await d.open();
    if (d.configuration === null || d.configuration === undefined) await d.selectConfiguration(1);
    let ifc = null, ep = null;
    for (const i of (d.configuration && d.configuration.interfaces) || []) {
      const alt = (i.alternates || [])[0]; if (!alt) continue;
      const out = (alt.endpoints || []).find((e) => e.direction === 'out' && e.type === 'bulk');
      if (out && (!ifc || alt.interfaceClass === 7)) { ifc = i; ep = out; if (alt.interfaceClass === 7) break; }
    }
    if (!ifc) throw err('no_endpoint');
    try { await d.claimInterface(ifc.interfaceNumber); } catch (e) { /* already claimed by this page */ }
    await d.transferOut(ep.endpointNumber, bytes());
  },
};
register('web_usb', usb);

const BT_SERVICES = ['000018f0-0000-1000-8000-00805f9b34fb', 'e7810a71-73ae-499d-8c15-faa9aef0c3f2', '49535343-fe7d-4ae5-8fa9-9fafd205e455', '0000ff00-0000-1000-8000-00805f9b34fb', '0000fee7-0000-1000-8000-00805f9b34fb'];
const bt = {
  dev: null, status: 'experimental',
  supported: () => !!(nav() && nav().bluetooth),
  async connected() { return !!(this.dev && this.dev.gatt && this.dev.gatt.connected) || !!this.dev; },
  async connect() { this.dev = await nav().bluetooth.requestDevice({ acceptAllDevices: true, optionalServices: BT_SERVICES }); return !!this.dev; },
  async open() {
    if (!this.dev) throw err('not_connected');
    const srv = await this.dev.gatt.connect(); let ch = null;
    for (const s of await srv.getPrimaryServices()) { for (const c of await s.getCharacteristics()) { if (c.properties && (c.properties.write || c.properties.writeWithoutResponse)) { ch = c; break; } } if (ch) break; }
    if (!ch) throw err('no_endpoint');
    for (const part of chunks(bytes(), 20)) { if (ch.properties.writeWithoutResponse && ch.writeValueWithoutResponse) await ch.writeValueWithoutResponse(part); else await ch.writeValue(part); }
  },
};
register('bluetooth', bt);

// ---------- the event log (queued on the device while offline; the client id makes a replay harmless) ----------
const QK = () => 'bos_cdr_q_' + uidK();
let flushing = false;
async function flushLog() {
  if (flushing || !online()) return;
  const q = jget(QK(), []); if (!Array.isArray(q) || !q.length) return;
  flushing = true; const done = new Set();
  try {
    for (const e of q) {
      let r; try { r = await sb.rpc('drawer_event_log', { p_client: e.client, p_event: e.event, p_loc: e.loc, p_sale_ref: e.sale_ref, p_reason: e.reason, p_method: e.method, p_at: e.at }); } catch (x) { break; }
      if (!r || !r.error) { done.add(e.client); continue; }
      const m = String(r.error.message || '');
      if (!online() || /fetch|network|load failed|timeout|jwt|token|401|not authenticated/i.test(m)) break;   // keep and retry later
      done.add(e.client);                                      // refused by the rules (or SQL not run yet): never retry forever
    }
  } finally { if (done.size) jset(QK(), jget(QK(), []).filter((x) => !done.has(x.client))); flushing = false; }
}
function log(event, o) {
  try {
    const q = jget(QK(), []); q.push({ client: uid(), event, loc: o.loc === undefined ? null : o.loc, sale_ref: o.sale_ref || null, reason: o.reason || null, method: o.method || null, at: new Date().toISOString() });
    jset(QK(), q.slice(-200)); const p = flushLog(); if (p && p.catch) p.catch(() => {});
  } catch (e) { /* the log must never break a sale */ }
}

// ---------- open (never throws, never blocks a sale) ----------
async function open(reason, o) {
  o = o || {}; const event = o.event || 'auto_open', method = o.method || cfg().method; let res;
  try {
    const d = drivers[method];
    if (!d || method === 'none' || method === 'kiosk_url') res = { ok: false, err: method === 'kiosk_url' ? 'planned' : 'no_driver' };
    else if (!d.supported()) res = { ok: false, err: 'unsupported' };
    else if (d.connected && !(await d.connected())) res = { ok: false, err: 'not_connected' };
    else { await d.open(); res = { ok: true }; }
  } catch (e) { res = { ok: false, err: String((e && (e.code || e.name || e.message)) || 'error').slice(0, 40) }; }
  try {
    if (res.ok) log(event, { loc: o.loc, sale_ref: o.sale_ref, reason, method });
    else {
      log('failed', { loc: o.loc, sale_ref: o.sale_ref, reason: (event + ': ' + res.err + (reason ? ' · ' + reason : '')).slice(0, 300), method });
      if (!o.quiet) toast(res.err === 'unsupported' ? TX('noBrowser') : TX('notConn'));
    }
  } catch (e) { /* ignore */ }
  return Object.assign({ method, event }, res);
}

// ---------- POS hooks (all guarded: mode off = nothing at all) ----------
const cashIn = (p) => Array.isArray(p && p.p_payments) && p.p_payments.some((x) => x && x.mode === 'cash' && Number(x.amount) > 0);
function applies(p, c) { return c.mode === 'on_any_sale' || (c.mode === 'on_cash_sale' && cashIn(p)); }
function fire(p) { try { const r = open('', { event: 'auto_open', loc: p.p_loc, sale_ref: p.p_client }); if (r && r.catch) r.catch(() => {}); } catch (e) { /* never block a sale */ } }
function beforeSale(p) { try { const c = cfg(); if (c.mode !== 'off' && c.when === 'before_payment' && applies(p, c)) fire(p); } catch (e) { /* ignore */ } }
function afterSale(p) { try { const c = cfg(); if (c.mode !== 'off' && c.when === 'after_payment' && applies(p, c)) fire(p); } catch (e) { /* ignore */ } }

// ---------- settings cache (for the "No sale" button; the grant is checked on the server too) ----------
const D = { set: null, at: 0, loc: null, rep: null, days: 30, ready: false, err: false, conn: null };
const SK = () => 'bos_cdr_set_' + uidK();
async function loadSettings(loc) {
  const r = await sb.rpc('drawer_settings', { p_loc: loc === undefined ? null : loc });
  if (r.error) throw r.error;
  D.set = r.data; D.at = Date.now(); D.loc = loc; jset(SK(), r.data); return r.data;
}
function canNoSale() { if (isOwner()) return true; const s = D.set || jget(SK(), null); return !!(s && s.can_no_sale); }
function slotHtml(loc) { return canNoSale() ? `<div class="card"><button type="button" class="full" data-act="cdr_nosale" data-v="${esc(String(loc))}">${esc(TX('noSale'))}</button></div>` : ''; }
function prime(loc) {
  if (D.at && Date.now() - D.at < 60000 && D.loc === loc) return;
  D.at = Date.now(); D.loc = loc;
  loadSettings(loc).then(() => { const el = $('#cdr_slot'); if (el) el.innerHTML = slotHtml(loc); }).catch(() => { /* offline or SQL not run: the cached answer is used */ });
}
function noSaleButton(loc) {
  try { if (cfg().mode === 'off') return ''; prime(loc); return `<div id="cdr_slot">${slotHtml(loc)}</div>`; } catch (e) { return ''; }
}
function noSaleSheet(loc) {
  A.openSheet(`<h2>${esc(TX('noSaleH'))}</h2><label for="cdr_why">${esc(TX('why'))}${cfg().needReason ? ' *' : ''}</label><input id="cdr_why" autocomplete="off" maxlength="200">
    <div class="row wrap" style="margin-top:6px">${['w1', 'w2', 'w3'].map((k) => `<button type="button" class="chip" data-act="cdr_why_set" data-v="${esc(TX(k))}">${esc(TX(k))}</button>`).join('')}</div>
    <div class="stack" style="margin-top:12px"><button type="button" class="primary full" data-act="cdr_nosale_go" data-v="${esc(String(loc))}" style="min-height:52px">${esc(TX('open'))}</button><button type="button" class="full" data-act="closesheet">${esc(TX('cancel'))}</button></div>`);
}

// ---------- screen #/cashdrawer ----------
const RECS = { mode: 'on_cash_sale', when: 'after_payment', method: 'web_serial' };
function group(kind, ruleKey, opts, cur, labelKey, own) {
  const chip = (v) => {
    const planned = kind === 'method' && STATUS[v] === 'planned';
    const lbl = TX(labelKey + v) + (v === RECS[kind] ? ' · ' + TX('recmark') : '');
    if (!own || planned) return `<span class="chip ${v === cur ? 'warn' : ''}" ${v === cur ? 'aria-current="true"' : ''}>${esc(lbl)}</span>`;
    return `<button type="button" class="chip ${v === cur ? 'warn' : ''}" data-act="cdr_set" data-k="${ruleKey}" data-v="${v}" ${v === cur ? 'aria-current="true"' : ''}>${esc(lbl)}</button>`;
  };
  return `<div class="card stack"><b>${esc(TX('g' + kind[0].toUpperCase() + kind.slice(1)))}</b><div class="row wrap">${opts.map(chip).join('')}</div>
    ${opts.map((v) => `<div class="muted" style="font-size:.9rem${v === cur ? ';font-weight:600' : ''}">${v === cur ? '▸ ' : ''}${esc(TX(labelKey + v))}: ${esc(TX('d_' + kind + '_' + v))}${kind === 'method' && STATUS[v] === 'planned' ? ' (' + esc(TX('planned')) + ')' : ''}</div>`).join('')}</div>`;
}
async function devState(method) {
  const d = drivers[method]; if (!d || method === 'none') return null;
  if (method === 'kiosk_url') return 'planned';
  try { if (!d.supported()) return 'unsupported'; return (await d.connected()) ? 'connected' : 'notconnected'; } catch (e) { return 'notconnected'; }
}
function repHtml() {
  const r = D.rep; if (!r) return '';
  const t = r.totals || {}, rows = r.by_user || [];
  return `<div class="card stack"><b>${esc(TX('rep'))}</b>
    <div class="row wrap">${[7, 30, 90].map((n) => `<button type="button" class="chip ${D.days === n ? 'warn' : ''}" data-act="cdr_range" data-v="${n}">${n} ${esc(TX('days'))}</button>`).join('')}</div>
    <div class="muted">${esc(TX('total'))}: ${esc(TX('nosaleC'))} ${Number(t.no_sale_open) || 0} · ${esc(TX('autoC'))} ${Number(t.auto_open) || 0} · ${esc(TX('failC'))} ${Number(t.failed) || 0} · ${esc(TX('testC'))} ${Number(t.test_open) || 0}</div>
    ${rows.length ? `<table style="width:100%;border-collapse:collapse"><thead><tr><th style="text-align:left">${esc(TX('staff'))}</th><th>${esc(TX('nosaleC'))}</th><th>${esc(TX('autoC'))}</th><th>${esc(TX('failC'))}</th></tr></thead><tbody>${rows.map((u) =>
      `<tr><td>${esc(u.name || u.staff || '')}${u.staff && u.name ? ' · ' + esc(u.staff) : ''}</td><td style="text-align:center"><b>${Number(u.no_sale_open) || 0}</b></td><td style="text-align:center">${Number(u.auto_open) || 0}</td><td style="text-align:center">${Number(u.failed) || 0}</td></tr>`).join('')}</tbody></table>`
      : `<p class="muted">${esc(TX('none'))}</p>`}
    ${(r.recent_no_sale || []).length ? `<b>${esc(TX('recent'))}</b>${r.recent_no_sale.slice(0, 15).map((e) => `<div class="muted" style="font-size:.9rem">${esc(String(e.at || '').slice(0, 16).replace('T', ' '))} · ${esc(e.staff || '')} · ${esc(e.reason || '')}</div>`).join('')}` : ''}
    <div class="notice">${esc(TX('repNote'))}</div></div>`;
}
async function draw() {
  const el = $('#cdr_body'); if (!el) return;
  const c = cfg(), own = isOwner(), st = await devState(c.method);
  const stTxt = st === null ? '' : st === 'connected' ? TX('conn') : st === 'unsupported' ? TX('unsup') : st === 'planned' ? TX('planned') : TX('notconn');
  const sw = (on) => ['true', 'false'].map((v) => (own ? `<button type="button" class="chip ${String(on) === v ? 'warn' : ''}" data-act="cdr_set" data-k="cash_drawer_no_sale_requires_reason" data-v="${v}">${esc(v === 'true' ? TX('on') : TX('off'))}</button>`
    : `<span class="chip ${String(on) === v ? 'warn' : ''}">${esc(v === 'true' ? TX('on') : TX('off'))}</span>`)).join('');
  el.innerHTML = `<p class="muted">${esc(TX('intro'))}</p>${own ? '' : `<div class="notice">${esc(TX('ownerOnly'))}</div>`}
    ${group('mode', 'cash_drawer_mode', MODES, c.mode, 'm_', own)}${group('when', 'cash_drawer_when', WHENS, c.when, 'w_', own)}${group('method', 'cash_drawer_method', METHODS, c.method, 'c_', own)}
    <div class="card stack"><b>${esc(TX('gReason'))}</b><div class="row wrap">${sw(c.needReason)}</div><div class="muted" style="font-size:.9rem">${esc(TX('d_reason'))}</div></div>
    <div class="card stack"><b>${esc(TX('device'))}</b>${stTxt ? `<div>${esc(c.method === 'none' ? '' : TX('c_' + c.method))}: <b>${esc(stTxt)}</b></div>` : ''}
      <div class="row wrap"><button type="button" class="btn" data-act="cdr_connect" ${c.method === 'none' || c.method === 'kiosk_url' ? 'disabled' : ''}>${esc(TX('connect'))}</button><button type="button" class="btn primary" data-act="cdr_test" ${c.method === 'none' || c.method === 'kiosk_url' ? 'disabled' : ''}>${esc(TX('test'))}</button></div>
      <div class="muted" style="font-size:.9rem">${esc(TX('hereNote'))}</div></div>
    ${repHtml()}`;
}
function myLoc() { const v = Number(store.get('bos_pos_loc')); if (Number.isFinite(v) && v > 0) return v; const l = A.S && A.S.ctx && A.S.ctx.locations; return Array.isArray(l) && l.length ? l[0] : null; }
async function loadReport() {
  const to = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' }), f = new Date(Date.now() - (D.days - 1) * 86400000).toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
  const r = await sb.rpc('drawer_report', { p_from: f, p_to: to }); D.rep = r.error ? null : r.data;
}
async function viewCashdrawer() {
  shell(TX('title'), '<div id="cdr_body"><p class="muted">…</p></div>', true);
  try { await loadSettings(myLoc()); D.ready = true; } catch (e) { const el = $('#cdr_body'); if (el) el.innerHTML = `<div class="notice bad">${esc(TX('sql'))}</div>`; return; }
  D.rep = null; if (D.set && D.set.can_report) { try { await loadReport(); } catch (e) { D.rep = null; } }
  await draw();
}

Object.assign(A.H, {
  cdr_set: async (a) => {
    if (!isOwner()) return;
    const k = a.dataset.k, v = a.dataset.v, val = v === 'true' ? true : v === 'false' ? false : v;
    const r = await sb.rpc('set_rule', { p_key: k, p_value: val });
    if (r.error) { if (/bad_value/.test(r.error.message || '')) return toast(TX('badv')); return fail(r.error); }
    try { if (B.reloadRules) await B.reloadRules(); } catch (e) { /* the old value stays on screen until reload */ }
    toast(TX('saved')); await draw();
  },
  cdr_connect: async () => {
    const c = cfg(), d = drivers[c.method]; if (!d || !d.supported()) return toast(TX('unsup'));
    try { const ok = await d.connect(); toast(ok ? TX('connected') : TX('connFail')); } catch (e) { toast(TX('connFail')); }
    await draw();
  },
  cdr_test: async () => {
    const r = await open('test', { event: 'test_open', loc: myLoc() });
    if (r.ok) toast(TX('tested'));
    await draw();
  },
  cdr_range: async (a) => { D.days = Number(a.dataset.v) || 30; try { await loadReport(); } catch (e) { D.rep = null; } await draw(); },
  cdr_nosale: (a) => noSaleSheet(Number(a.dataset.v) || a.dataset.v),
  cdr_why_set: (a) => { const i = $('#cdr_why'); if (i) i.value = a.dataset.v; },
  cdr_nosale_go: async (a) => {
    const i = $('#cdr_why'), why = ((i && i.value) || '').trim();
    if (cfg().needReason && !why) return toast(TX('needWhy'));
    if (A.closeSheet) A.closeSheet();
    const loc = Number(a.dataset.v) || null;
    const r = await open(why || 'no reason', { event: 'no_sale_open', loc });
    if (r.ok) toast(TX('noSaleLogged'));
  },
});
if (typeof window.addEventListener === 'function') window.addEventListener('online', () => { flushLog(); });
if (typeof setInterval === 'function') setInterval(() => { flushLog(); }, 60000);

window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { cashdrawer: viewCashdrawer });
B.drawer = { open, register, drivers, cfg, beforeSale, afterSale, noSaleButton, flushLog, PULSE, log };
})();
