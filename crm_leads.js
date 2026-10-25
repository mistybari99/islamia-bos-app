/* Islamia BOS · Party and gift enquiries (#/crmleads, #/crmleads/<lead id>). Package CRM-G.
   One screen for the lead pipeline of party, wholesale, corporate and gift orders: Board (Enquiry, Quoted, Following up, Won, Lost), the enquiry sheet (notes, quote with items and
   validity, follow-up, assign, lost with a reason, reopen with a reason, turn into an order or a draft party form), Report (win and loss) and Lists (lost reasons, sources, occasions).
   Server: supabase/phase323.sql to phase327.sql (_crmg_*). The server decides every call: a hidden button is also a refused request. A lead and a quote post nothing to the books.
   Exports for the integrator (docs/integration/CRM-G.md): BOS.crmLeads.track(message) opens a new enquiry from an inbox message; BOS.crmLeads.INFO = the (i) info sheet texts.
   English labels only for now. UNVERIFIED on a real phone and on a real Supabase project. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, H } = A;
const $ = (s, el = document) => el.querySelector(s);
const val = (id) => (($('#' + id) || {}).value || '').trim();
const nnum = (v) => { const s = String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).replace(/,/g, '').trim(); if (s === '') return NaN; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const money = (n) => (n === null || n === undefined || n === '' ? '-' : '৳ ' + Number(n).toLocaleString('en-US', { maximumFractionDigits: 2 }));
const ERR = {
  not_allowed: 'You do not have permission for this.', module_off: 'Enquiry tracking is switched off. The owner can switch it on in Settings.', not_found: 'This enquiry was not found.',
  contact_name_required: 'Write the name of the person.', bad_phone: 'The phone number is not valid.', bad_date: 'The date is not valid.', bad_guests: 'Guests must be a number from 1.', bad_amount: 'The amount is not valid.',
  unknown_source: 'Choose a source from the list.', unknown_occasion: 'Choose an occasion from the list.', location_required: 'Choose the outlet.', lead_closed: 'A won or lost enquiry cannot be changed.',
  illegal_stage_move: 'That move is not allowed from this stage.', quote_needed: 'Send a quote first.', quote_needed_to_win: 'A sent quote is needed before this can be won.',
  lost_reason_required: 'Choose a lost reason from the list.', lost_note_required: 'Write a few words when the reason is Other.', reason_required: 'Write a reason (at least 3 letters).',
  not_lost: 'Only a lost enquiry can be reopened.', reopen_off: 'Reopening is switched off. Start a new enquiry.', no_items: 'Add at least one line.', line_needs_item_or_description: 'Every line needs an item or a description.',
  bad_qty: 'Quantity must be above zero.', bad_price: 'The price is not valid.', price_required: 'Write the price of the line.', bad_discount: 'The discount is more than the lines.',
  validity_required: 'Write the date until which the quote is valid.', quote_sent: 'A sent quote cannot be changed. Make a new version.', already_converted: 'This enquiry already has its order or form.',
  channel_required: 'Choose the sales channel of the order.', lines_need_items: 'A line has no item from the item list. Use the party invoice form instead.',
  price_above_list: 'The quote is above the list price. Use the party invoice form instead.', mobile_required: 'An order needs a valid mobile number on the enquiry.',
  already_linked: 'That record already belongs to another enquiry.', order_cancelled: 'A cancelled order cannot be linked.', other_outlet: 'That record belongs to another outlet.',
  form_not_allowed: 'You do not hold the right to enter that form.', assignee_not_at_outlet: 'This person does not work at this outlet.', message_already_tracked: 'This message already has an enquiry.',
  other_stays: 'The entry Other cannot be removed.', bad_code: 'The code can use small letters, digits and _ only.', address_required: 'An order that is delivered needs an address.', bad_follow_up: 'The follow-up time is not valid.',
};
const codeOf = (m) => (/^not allowed|: not allowed|not allowed:/.test(m) ? 'not_allowed' : Object.keys(ERR).find((x) => m.includes(x)) || '');
const eText = (e) => { const m = String((e && e.message) || ''); const k = codeOf(m); return k ? ERR[k] : m || 'Something went wrong'; };
async function call(fn, args) {
  const r = await sb.rpc(fn, args || {});
  if (r.error) { const e = new Error(eText(r.error)); e.raw = r.error; throw e; }
  return r.data;
}
const guard = (fn) => (a) => { fn(a).catch((e) => { if (e && e.raw !== undefined) toast(e.message); else fail(e); }); };
const lerr = (m) => { const e = new Error(m); e.raw = null; return e; };
const uuid = () => (crypto.randomUUID ? crypto.randomUUID() : null);
const STAGE = { enquiry: 'Enquiry', quoted: 'Quoted', following_up: 'Following up', won: 'Won', lost: 'Lost' };
const EVK = { created: 'Started', edited: 'Changed', stage: 'Moved', note: 'Note', quote: 'Quote', assign: 'Given to', follow_up: 'Follow-up', convert: 'Turned into a record', reopen: 'Reopened', task: 'Task' };
const when = (iso, withTime) => { try { return new Date(iso).toLocaleString('en-GB', Object.assign({ timeZone: 'Asia/Dhaka', day: 'numeric', month: 'short', year: 'numeric' }, withTime ? { hour: 'numeric', minute: '2-digit', hour12: true } : {})); } catch (e) { return ''; } };
const localToISO = (v) => (v ? v + ':00+06:00' : null);
const D = { tab: 'board', st: null, lists: null, board: null, loc: '', mine: false, sel: null, panel: null, form: null, q: null, rep: null, from: '', to: '', items: null, channels: null, cache: {} };

function css() {
  if (document.getElementById('crmg_css')) return;
  const s = document.createElement('style'); s.id = 'crmg_css';
  s.textContent = '.crmg-pill{display:inline-block;padding:2px 8px;border-radius:10px;font-size:12px;background:var(--line,#e5e5e5);margin-right:6px}.crmg-late{background:#f8d7da;color:#842029}.crmg-tag{background:#e7f1ff}'
    + '.crmg-acts{display:flex;flex-wrap:wrap;gap:8px;margin-top:8px}.crmg-acts button{min-height:44px}.crmg-sum{font-weight:600;margin:8px 0}.crmg-bar{position:sticky;bottom:0;padding:8px 0;background:var(--bg,#fff)}'
    + '.crmg-board-stage{margin:10px 0}.crmg-card{padding:10px;margin:6px 0}.crmg-grid{display:grid;gap:8px;grid-template-columns:1fr 1fr}.crmg-line{display:grid;gap:6px;grid-template-columns:1fr 4.5em 5.5em}';
  document.head.appendChild(s);
}
const pill = (t, c) => `<span class="crmg-pill ${c || ''}">${esc(t)}</span>`;
const listOpts = (arr, sel, blank) => (blank ? `<option value="">${esc(blank)}</option>` : '') + (arr || []).map((x) => `<option value="${esc(x.code)}" ${x.code === sel ? 'selected' : ''}>${esc(x.label)}</option>`).join('');
const label = (arr, code) => { const x = (arr || []).find((y) => y.code === code); return x ? x.label : code || ''; };

/* ---------- board ---------- */
function card(r) {
  const flags = (r.overdue ? pill('Follow-up missed', 'crmg-late') : '') + (r.stale ? pill('Stale', 'crmg-late') : '') + (r.quote_expired ? pill('Quote expired', 'crmg-late') : '') + (r.converted ? pill('Order made', 'crmg-tag') : '');
  return `<div class="card crmg-card" data-lead="${esc(r.id)}"><div class="row between"><b>#${esc(r.lead_no)} · ${esc(r.contact_name)}</b><span>${esc(money(r.quote_total ?? r.est_value))}</span></div>
    <div class="muted">${r.event_date ? 'Event ' + esc(when(r.event_date)) + ' · ' : ''}${r.owner_staff ? esc(r.owner_staff) : ''}${r.next_follow_up ? ' · follow up ' + esc(when(r.next_follow_up, true)) : ''}</div>
    <div>${flags}</div><div class="crmg-acts"><button class="primary" data-act="cl_open" data-id="${esc(r.id)}">Open</button></div></div>`;
}
function boardHTML() {
  const st = D.st, b = D.board;
  if (!b) return '<p class="muted">…</p>';
  const outlets = st.my_outlets || [];
  const filt = `<div class="row" id="cl_filter">${outlets.length > 1 ? `<select id="cl_loc" data-chg="cl_filter" aria-label="Outlet"><option value="">All my outlets</option>${outlets.map((o) => `<option value="${esc(o.id)}" ${String(o.id) === String(D.loc) ? 'selected' : ''}>${esc(o.name)}</option>`).join('')}</select>` : ''}
    <label class="row"><input type="checkbox" id="cl_mine" data-chg="cl_filter" ${D.mine ? 'checked' : ''}> Mine only</label></div>`;
  const sum = `<div class="crmg-sum" id="cl_sum">${esc(b.overdue)} follow-ups missed${b.stale ? ' · ' + esc(b.stale) + ' stale' : ''}</div>`;
  const stages = (b.stages || []).map((s) => `<details class="crmg-board-stage" data-stage="${esc(s.stage)}" ${s.stage !== 'won' && s.stage !== 'lost' ? 'open' : ''}><summary><b>${esc(STAGE[s.stage])} (${esc(s.count)})</b> ${s.value ? '· ' + esc(money(s.value)) : ''}</summary>
    ${(s.cards || []).map(card).join('') || '<p class="muted">Nothing here.</p>'}${s.stage === 'won' || s.stage === 'lost' ? '<p class="muted">Last 30 days.</p>' : ''}</details>`).join('');
  return filt + sum + stages + (st.can_create_lead ? `<div class="crmg-bar"><button class="primary full" data-act="cl_new">New enquiry</button></div>` : '');
}

/* ---------- new / edit enquiry ---------- */
function formHTML() {
  const f = D.form; if (!f) return '';
  const st = D.st, outlets = st.my_outlets || [], L = D.lists || {};
  const outlet = outlets.length > 1 ? `<div><label for="cf_loc">Outlet</label><select id="cf_loc">${outlets.map((o) => `<option value="${esc(o.id)}" ${String(o.id) === String(f.loc) ? 'selected' : ''}>${esc(o.name)}</option>`).join('')}</select></div>` : '';
  return `<div class="card stack" id="cl_form"><b>${f.id ? 'Change the enquiry' : 'New enquiry'}</b>
    <div><label for="cf_name">Name</label><input id="cf_name" autocomplete="off" maxlength="80" value="${esc(f.name || '')}"></div>
    <div><label for="cf_phone">Phone</label><input id="cf_phone" inputmode="tel" autocomplete="off" value="${esc(f.phone || '')}"></div>
    <div><label for="cf_event">Event date</label><input id="cf_event" type="date" value="${esc(f.event || '')}"></div>${outlet}
    <details><summary>More</summary><div class="stack">
      <div><label for="cf_source">Where it came from</label><select id="cf_source">${listOpts(L.source, f.source, 'Not written')}</select></div>
      <div><label for="cf_occ">Occasion</label><select id="cf_occ">${listOpts(L.occasion, f.occ, 'Not written')}</select></div>
      <div class="crmg-grid"><div><label for="cf_guests">Guests</label><input id="cf_guests" inputmode="numeric" value="${esc(f.guests || '')}"></div><div><label for="cf_value">Estimated value</label><input id="cf_value" inputmode="decimal" value="${esc(f.value || '')}"></div></div>
      ${!f.id && st.can_manage_leads ? `<div><label for="cf_who">Give to</label><select id="cf_who"><option value="">Me</option>${(st.staff_here || []).map((p) => `<option value="${esc(p.id)}">${esc(p.staff_id)}${p.name ? ' · ' + esc(p.name) : ''}</option>`).join('')}</select></div>` : ''}
      <div><label for="cf_fu">Follow up on</label><input id="cf_fu" type="datetime-local" value="${esc(f.fu || '')}"></div>
      ${st.task_on && !f.id ? '<label class="row"><input type="checkbox" id="cf_task" checked> Add a task for the follow-up</label>' : ''}
      <div><label for="cf_note">Note</label><input id="cf_note" maxlength="300" value="${esc(f.note || '')}"></div></div></details>
    <div class="row"><button class="full" data-act="cl_cancel">Cancel</button><button class="full primary" data-act="cl_save">Save</button></div></div>`;
}

/* ---------- the enquiry sheet ---------- */
function quoteRows(q) {
  return (q.items || []).map((i) => `<div class="muted">${esc(i.qty)} × ${esc(i.desc)}${i.unit ? ' (' + esc(i.unit) + ')' : ''} @ ${esc(money(i.price))} = ${esc(money(i.amount))}</div>`).join('');
}
function quotesHTML(g) {
  const qs = g.quotes || []; if (!qs.length) return '<p class="muted">No quote yet.</p>';
  return qs.map((q) => `<div class="card crmg-card" data-quote="${esc(q.id)}"><div class="row between"><b>Quote ${esc(q.version)}</b><span>${esc(money(q.total))}</span></div>
    <div>${pill(q.status === 'sent' && q.expired ? 'expired' : q.status, q.expired ? 'crmg-late' : 'crmg-tag')}${q.valid_until ? 'valid until ' + esc(when(q.valid_until)) : ''}${q.late_reason ? ' · late: ' + esc(q.late_reason) : ''}</div>
    ${quoteRows(q)}${q.discount > 0 ? `<div class="muted">Discount ${esc(money(q.discount))}</div>` : ''}
    ${q.status === 'sent' && g.can.quote ? `<div class="crmg-acts"><button data-act="cl_qans" data-id="${esc(q.id)}" data-v="accepted">Customer said yes</button><button data-act="cl_qans" data-id="${esc(q.id)}" data-v="declined">Customer said no</button></div>` : ''}</div>`).join('');
}
function panelHTML(g) {
  const p = D.panel, L = D.lists || {}, l = g.lead; if (!p) return '';
  const back = '<div class="row"><button class="full" data-act="cl_panel" data-v="">Cancel</button>';
  if (p === 'note') return `<div class="card stack" data-panel="note"><b>Add a note</b><select id="cp_kind"><option value="note">Note</option><option value="call">Phone call</option><option value="visit">Visit</option><option value="message">Message</option></select><textarea id="cp_body" rows="3" maxlength="1000"></textarea>${back}<button class="full primary" data-act="cl_note_go">Save note</button></div></div>`;
  if (p === 'follow') return `<div class="card stack" data-panel="follow"><b>Follow up</b><div><label for="cp_fu">Follow up on</label><input id="cp_fu" type="datetime-local"></div>${D.st.task_on ? '<label class="row"><input type="checkbox" id="cp_task" checked> Add a task</label>' : ''}<div><label for="cp_note">Note (optional)</label><input id="cp_note" maxlength="300"></div>${back}<button class="full primary" data-act="cl_follow_go">Save</button></div></div>`;
  if (p === 'lost') return `<div class="card stack" data-panel="lost"><b>Close as lost</b><div><label for="cp_reason">Why</label><select id="cp_reason">${listOpts(L.lost_reason, '', 'Choose a reason')}</select></div><div><label for="cp_note">Note (needed for Other)</label><input id="cp_note" maxlength="300"></div>${back}<button class="full primary" data-act="cl_lost_go">Close as lost</button></div></div>`;
  if (p === 'reopen') return `<div class="card stack" data-panel="reopen"><b>Reopen this enquiry</b><div class="muted">A reason is needed. It goes to the Exceptions list.</div><input id="cp_reason" maxlength="300" placeholder="Why is it open again"><select id="cp_to"><option value="enquiry">Back to Enquiry</option><option value="following_up">Back to Following up</option></select>${back}<button class="full primary" data-act="cl_reopen_go">Reopen</button></div></div>`;
  if (p === 'assign') return `<div class="card stack" data-panel="assign"><b>Give to</b><select id="cp_who">${(D.st.staff_here || []).map((s) => `<option value="${esc(s.id)}" ${s.id === l.owner_user ? 'selected' : ''}>${esc(s.staff_id)}${s.name ? ' · ' + esc(s.name) : ''}</option>`).join('')}</select>${back}<button class="full primary" data-act="cl_assign_go">Give</button></div></div>`;
  if (p === 'won') return `<div class="card stack" data-panel="won"><b>Mark as won</b>${D.st.win_needs_quote ? '<div class="muted">The owner asks for a sent quote first. Without one, write a reason (it goes to the Exceptions list).</div><input id="cp_reason" maxlength="300" placeholder="Reason (only if there is no quote)">' : ''}${back}<button class="full primary" data-act="cl_won_go">Mark as won</button></div></div>`;
  if (p === 'convert') {
    const ch = D.channels || [];
    return `<div class="card stack" data-panel="convert"><b>Turn into an order or a form</b><div class="muted">This makes the normal record through the existing screens. Nothing is posted by the enquiry.</div>
      <select id="cp_kind"><option value="online_order">Make an order (from the quote lines)</option><option value="form_20_4">Make a draft party invoice (form 24-1)</option><option value="form_20_1">Make a draft customer order form (form 05-1)</option><option value="link_order">Link an order that already exists</option><option value="link_form">Link a 05-1 or 24-1 form that already exists</option></select>
      <div data-for="online_order"><label for="cp_ch">Sales channel</label><select id="cp_ch"><option value="">Choose</option>${ch.map((c) => `<option value="${esc(c.id)}">${esc(c.name_bn || c.code)}</option>`).join('')}</select>
        <label for="cp_dd">Delivery date</label><input id="cp_dd" type="date" value="${esc(l.event_date || '')}"><label for="cp_dm">Delivery</label><select id="cp_dm"><option value="pickup">Pick up from the shop</option><option value="home">Home delivery</option><option value="courier">Courier</option></select>
        <label for="cp_addr">Address (if delivered)</label><input id="cp_addr" maxlength="300"></div>
      <div data-for="link"><label for="cp_target">Order or form id</label><input id="cp_target" autocomplete="off"></div>
      ${D.st.win_needs_quote ? '<input id="cp_reason" maxlength="300" placeholder="Reason (only if there is no quote)">' : ''}${back}<button class="full primary" data-act="cl_convert_go">Go</button></div></div>`;
  }
  if (p === 'quote') {
    const q = D.q || { lines: [{}, {}], discount: '', valid: '', note: '', late: '' };
    const lines = q.lines.map((x, i) => `<div class="crmg-line" data-ql="${i}"><input id="ql_d${i}" list="cl_items" placeholder="Item or description" value="${esc(x.d || '')}"><input id="ql_q${i}" inputmode="decimal" placeholder="Qty" value="${esc(x.q || '')}"><input id="ql_p${i}" inputmode="decimal" placeholder="Price" value="${esc(x.p || '')}"></div>`).join('');
    const dl = (D.items || []).filter((i) => i.is_active).slice(0, 600).map((i) => `<option value="${esc(i.code)} · ${esc(i.name_en || i.name_bn)}"></option>`).join('');
    return `<div class="card stack" data-panel="quote"><b>Quote</b><datalist id="cl_items">${dl}</datalist><div class="muted">Pick an item to use its list price, or write a description and a price.</div>${lines}
      <button data-act="cl_qline">Add a line</button>
      <div><label for="qq_valid">Valid until${D.st.quote_valid_days ? ' (empty = ' + esc(D.st.quote_valid_days) + ' days from today)' : ''}</label><input id="qq_valid" type="date" value="${esc(q.valid)}"></div>
      <details><summary>More</summary><div class="stack"><div><label for="qq_disc">Discount</label><input id="qq_disc" inputmode="decimal" value="${esc(q.discount)}"></div><div><label for="qq_note">Note</label><input id="qq_note" maxlength="300" value="${esc(q.note)}"></div>
        <div><label for="qq_late">Reason, only if the quote is late</label><input id="qq_late" maxlength="300" value="${esc(q.late)}"></div></div></details>
      <div class="row"><button class="full" data-act="cl_panel" data-v="">Cancel</button><button class="full" data-act="cl_qsave" data-send="0">Save draft</button><button class="full primary" data-act="cl_qsave" data-send="1">Send quote</button></div></div>`;
  }
  return '';
}
function sheetHTML() {
  const g = D.sel; if (!g) return '';
  const l = g.lead, c = g.can, open = !['won', 'lost'].includes(l.stage);
  const acts = [];
  if (open && c.quote) acts.push(['cl_panel', 'quote', 'Quote', true]);
  if (open && c.move) acts.push(['cl_panel', 'follow', 'Follow up', false]);
  if (open && c.move) acts.push(['cl_panel', 'won', 'Won', false]);
  const more = [];
  if (c.note) more.push(['cl_panel', 'note', 'Add a note']);
  if (open && c.close_lost) more.push(['cl_panel', 'lost', 'Close as lost']);
  if (c.assign) more.push(['cl_panel', 'assign', 'Give to someone']);
  if (c.convert && l.stage !== 'lost') more.push(['cl_panel', 'convert', 'Turn into an order or form']);
  if (c.reopen) more.push(['cl_panel', 'reopen', 'Reopen']);
  if (c.edit) more.push(['cl_edit', '', 'Change details']);
  const btn = (a, v, t, pr) => `<button class="${pr ? 'primary' : ''}" data-act="${a}" data-v="${esc(v)}">${esc(t)}</button>`;
  const rec = l.online_order_id ? 'An order was made.' : l.entry_id ? 'A draft form was made.' : '';
  const hist = (g.events || []).map((e) => `<div class="muted"><b>${esc(EVK[e.kind] || e.kind)}</b> ${e.from && e.to && e.from !== e.to ? esc(STAGE[e.from] || e.from) + ' → ' + esc(STAGE[e.to] || e.to) : e.to ? esc(STAGE[e.to] || '') : ''} ${esc(e.note || '')} · ${esc(e.by || '')} · ${esc(when(e.at, true))}</div>`).join('');
  const tasks = (g.tasks || []).map((t) => `<div class="muted">${esc(t.title)} · ${esc(when(t.due_at, true))}</div>`).join('');
  return `<div class="card" id="cl_sheet"><div class="row between"><b>#${esc(l.lead_no)} · ${esc(l.contact_name)}</b>${pill(STAGE[l.stage], l.stage === 'lost' ? 'crmg-late' : 'crmg-tag')}</div>
    <div>${l.contact_phone ? `<a href="tel:${esc(l.contact_phone)}">${esc(l.contact_phone)}</a>` : '<span class="muted">No phone</span>'}${l.customer_name ? ' · customer ' + esc(l.customer_name) : ''}</div>
    <div class="muted">${l.event_date ? 'Event ' + esc(when(l.event_date)) + ' · ' : ''}${l.guests ? esc(l.guests) + ' guests · ' : ''}${esc(money(l.est_value))}${l.owner_staff ? ' · ' + esc(l.owner_staff) : ''}</div>
    <div class="muted">${l.occasion ? esc(label(D.lists && D.lists.occasion, l.occasion)) + ' · ' : ''}${l.source ? esc(label(D.lists && D.lists.source, l.source)) : ''}</div>
    ${l.overdue ? pill('Follow-up missed', 'crmg-late') : l.next_follow_up ? `<div class="muted">Follow up ${esc(when(l.next_follow_up, true))}</div>` : ''}${l.stale ? pill('Stale', 'crmg-late') : ''}
    ${l.lost_reason ? `<div>Lost: ${esc(label(D.lists && D.lists.lost_reason, l.lost_reason))}${l.lost_note ? ' · ' + esc(l.lost_note) : ''}</div>` : ''}${rec ? `<div>${esc(rec)}</div>` : ''}${l.note ? `<div class="muted">${esc(l.note)}</div>` : ''}
    <div class="crmg-acts">${acts.map((a) => btn(...a)).join('')}</div>
    ${more.length ? `<details><summary>More</summary><div class="crmg-acts">${more.map(([a, v, t]) => btn(a, v, t, false)).join('')}</div></details>` : ''}</div>
    ${panelHTML(g)}<h3>Quotes</h3>${quotesHTML(g)}${tasks ? '<h3>Open tasks</h3>' + tasks : ''}<details><summary><b>History (${(g.events || []).length})</b></summary>${hist}</details>
    <div class="row"><button class="full" data-act="cl_close">Back to the board</button></div>`;
}

/* ---------- report and lists ---------- */
function reportHTML() {
  const r = D.rep; const ctl = `<div class="crmg-grid"><div><label for="cr_from">From</label><input id="cr_from" type="date" value="${esc(D.from)}"></div><div><label for="cr_to">To</label><input id="cr_to" type="date" value="${esc(D.to)}"></div></div><button data-act="cl_rep_go" class="full">Show</button>`;
  if (!r) return ctl + '<p class="muted">…</p>';
  const rows = (arr, cols) => (arr || []).map((x) => `<tr>${cols.map((c) => `<td>${esc(typeof c === 'function' ? c(x) : x[c])}</td>`).join('')}</tr>`).join('');
  return ctl + `<div class="crmg-grid" id="cr_tiles"><div class="card"><b>${esc(r.created)}</b><div class="muted">Enquiries made</div></div><div class="card"><b>${esc(r.won)}</b><div class="muted">Won · ${esc(money(r.won_value))}</div></div>
    <div class="card"><b>${esc(r.lost)}</b><div class="muted">Lost · ${esc(money(r.lost_value))}</div></div><div class="card"><b>${r.win_rate_pct === null ? '-' : esc(r.win_rate_pct) + '%'}</b><div class="muted">Win rate (won of won + lost)</div></div></div>
    <div class="muted">Open now: ${esc(r.open_now)} · ${esc(money(r.open_value))} · follow-ups missed ${esc(r.overdue_open)}${r.stale_open === null ? '' : ' · stale ' + esc(r.stale_open)}${r.avg_days_to_close === null ? '' : ' · average ' + esc(r.avg_days_to_close) + ' days to close'}</div>
    <h3>Why enquiries were lost</h3><table class="tbl"><tr><th>Reason</th><th>Count</th><th>Value</th></tr>${rows(r.lost_by_reason, ['label', 'count', (x) => money(x.value)]) || '<tr><td colspan="3">None</td></tr>'}</table>
    <h3>By person</h3><table class="tbl"><tr><th>Person</th><th>Made</th><th>Won</th><th>Lost</th></tr>${rows(r.by_owner, ['owner_staff', 'created', 'won', 'lost'])}</table>
    <h3>By source</h3><table class="tbl"><tr><th>Source</th><th>Made</th><th>Won</th><th>Lost</th></tr>${rows(r.by_source, ['label', 'created', 'won', 'lost'])}</table>`;
}
function listsHTML() {
  const L = D.lists; if (!L) return '<p class="muted">…</p>';
  if (!L.can_edit) return '<div class="card muted">Only the owner can change these lists.</div>';
  return [['lost_reason', 'Lost reasons'], ['source', 'Sources'], ['occasion', 'Occasions']].map(([k, t]) => `<div class="card stack" data-list="${k}"><b>${t}</b>
    ${(L[k] || []).map((x) => `<div class="row between"><span>${esc(x.label)}${x.active ? '' : ' (not used)'}</span>${x.code === 'other' ? '' : `<button data-act="cl_list_tog" data-k="${k}" data-c="${esc(x.code)}" data-a="${x.active ? '0' : '1'}" data-l="${esc(x.label)}">${x.active ? 'Stop using' : 'Use again'}</button>`}</div>`).join('')}
    <div class="row"><input id="cl_new_${k}" placeholder="Add a new entry" maxlength="60"><button data-act="cl_list_add" data-k="${k}">Add</button></div></div>`).join('');
}

/* ---------- shell ---------- */
function body() {
  const st = D.st;
  if (!st) return '<p class="muted">…</p>';
  if (!st.signed_in) return '<div class="card muted">Sign in to see enquiries.</div>';
  if (!st.lead_on) return '<div class="card muted">Enquiry tracking is switched off. The owner can switch on "Track party, wholesale, corporate and gift enquiries" in Settings.</div>';
  if (D.sel) return sheetHTML();
  const tabs = [['board', 'Board'], ['report', 'Report']].concat(D.lists && D.lists.can_edit ? [['lists', 'Lists']] : []);
  return `<div class="ptabs" role="tablist">${tabs.map(([k, l]) => `<button role="tab" data-act="cl_tab" data-v="${k}" aria-selected="${D.tab === k}">${esc(l)}</button>`).join('')}</div>`
    + formHTML() + (D.tab === 'board' ? boardHTML() : D.tab === 'report' ? reportHTML() : listsHTML());
}
function render() { const el = $('#cl_body'); if (el) el.innerHTML = body(); }
async function loadBoard() { D.board = await call('_crmg_lead_board', { p_loc: D.loc ? Number(D.loc) : null, p_owner: D.mine ? D.st.uid || null : null }); }
async function loadItems() {
  if (D.items) return; const E = B.ENV || {};
  if (E.items) { D.items = E.items; return; }
  try { const r = window.BOS_ALL ? await window.BOS_ALL(sb.from('items').select('id,code,name_bn,name_en,is_active').order('code')) : { data: [] }; D.items = r.data || []; } catch (e) { D.items = []; }
}
async function loadChannels() { if (D.channels) return; try { const r = await sb.rpc('sales_channels_list', { p_all: false }); D.channels = r.error ? [] : (r.data || []); } catch (e) { D.channels = []; } }
async function load() {
  D.st = await call('_crmg_status');
  if (D.st.lead_on) { D.lists = await call('_crmg_lists', { p_all: true }); if (D.tab === 'board' && !D.sel) await loadBoard(); }
  render();
}
async function openLead(id) { D.sel = await call('_crmg_lead_get', { p_lead: id }); D.panel = null; D.q = null; render(); window.scrollTo && window.scrollTo(0, 0); }
async function refreshSel() { if (D.sel) D.sel = await call('_crmg_lead_get', { p_lead: D.sel.lead.id }); render(); }
function formData() {
  const d = { contact_name: val('cf_name'), contact_phone: val('cf_phone') };
  d.event_date = val('cf_event') || null; d.source = val('cf_source') || null; d.occasion = val('cf_occ') || null;
  const g = val('cf_guests'); if (g) { const n = nnum(g); if (!(n >= 1)) throw lerr(ERR.bad_guests); d.guests = n; } else d.guests = null;
  const v = val('cf_value'); if (v) { const n = nnum(v); if (!(n >= 0)) throw lerr(ERR.bad_amount); d.est_value = n; } else d.est_value = null;
  const fu = localToISO(val('cf_fu')); if (fu) { d.next_follow_up = fu; if ($('#cf_task') && $('#cf_task').checked) d.make_task = true; }
  const who = val('cf_who'); if (who) d.owner_user = who;
  d.note = val('cf_note') || null; return d;
}
function readQuote() {
  const items = [];
  (D.q.lines || []).forEach((_, i) => {
    const d = val('ql_d' + i), q = val('ql_q' + i), p = val('ql_p' + i); D.q.lines[i] = { d, q, p };
    if (!d && !q && !p) return;
    const code = d.split(' · ')[0].trim(); const it = (D.items || []).find((x) => x.code === code);
    const qn = nnum(q); if (!(qn > 0)) throw lerr(ERR.bad_qty);
    const line = { qty: qn };
    if (it) { line.item_id = it.id; if (p) { const pn = nnum(p); if (!(pn >= 0)) throw lerr(ERR.bad_price); line.price = pn; } } else { if (!d) throw lerr(ERR.line_needs_item_or_description); line.desc = d; const pn = nnum(p); if (!(pn >= 0)) throw lerr(ERR.price_required); line.price = pn; }
    items.push(line);
  });
  if (!items.length) throw lerr(ERR.no_items);
  D.q.valid = val('qq_valid'); D.q.discount = val('qq_disc'); D.q.note = val('qq_note'); D.q.late = val('qq_late');
  const out = { items }; if (D.q.valid) out.valid_until = D.q.valid;
  if (D.q.discount) { const dn = nnum(D.q.discount); if (!(dn >= 0)) throw lerr(ERR.bad_amount); out.discount = dn; }
  if (D.q.note) out.note = D.q.note; if (D.q.late) out.late_reason = D.q.late;
  return out;
}
Object.assign(H, {
  cl_tab: guard(async (a) => { D.tab = a.dataset.v; D.form = null; if (D.tab === 'report' && !D.rep) await repLoad(); if (D.tab === 'board') await loadBoard(); render(); }),
  cl_open: guard(async (a) => { await Promise.all([loadItems(), loadChannels()]); await openLead(a.dataset.id); }),
  cl_close: guard(async () => { D.sel = null; D.panel = null; await load(); }),
  cl_new: () => { D.form = { loc: D.loc || ((D.st.my_outlets || [])[0] || {}).id || '' }; render(); const n = $('#cf_name'); if (n) n.focus(); },
  cl_cancel: () => { D.form = null; render(); },
  cl_edit: () => { const l = D.sel.lead; D.form = { id: l.id, name: l.contact_name, phone: l.contact_phone || '', event: l.event_date || '', source: l.source, occ: l.occasion, guests: l.guests || '', value: l.est_value || '', note: l.note || '', loc: l.location_id }; D.sel = null; render(); },
  cl_save: guard(async () => {
    const f = D.form; const d = formData(); if (!d.contact_name && !f.id) return toast(ERR.contact_name_required);
    const loc = Number(val('cf_loc') || f.loc) || null;
    const r = await call('_crmg_lead_save', { p_id: f.id || null, p_client: f.id ? null : uuid(), p_loc: loc, p_data: d });
    D.form = null; toast(f.id ? 'Saved' : 'Saved as enquiry ' + r.lead_no + ((r.same_phone_open_leads || []).length ? '. Note: another open enquiry has this phone.' : ''));
    await load(); if (f.id) await openLead(f.id);
  }),
  cl_filter: guard(async () => { D.loc = val('cl_loc'); D.mine = !!($('#cl_mine') || {}).checked; await loadBoard(); render(); }),
  cl_panel: guard(async (a) => { D.panel = a.dataset.v || null; if (D.panel === 'quote') { await loadItems(); const q = (D.sel.quotes || [])[0]; D.q = { lines: [{}, {}], discount: '', valid: '', note: '', late: '' }; if (q && q.status === 'draft') D.q = { id: q.id, lines: q.items.map((i) => ({ d: i.code ? i.code + ' · ' + i.desc : i.desc, q: i.qty, p: i.price })), discount: q.discount || '', valid: q.valid_until || '', note: q.note || '', late: '' }; }
    if (D.panel === 'convert') await loadChannels(); render(); }),
  cl_qline: () => { readQuote0(); D.q.lines.push({}); render(); },
  cl_qsave: guard(async (a) => {
    const send = a.dataset.send === '1'; const d = readQuote(); d.send = send; if (D.q.id) d.quote_id = D.q.id;
    const r = await call('_crmg_quote_save', { p_lead: D.sel.lead.id, p_client: uuid(), p_data: d });
    D.panel = null; D.q = null; toast(send ? 'Quote sent' : 'Draft saved'); await refreshSel(); return r;
  }),
  cl_qans: guard(async (a) => { await call('_crmg_quote_respond', { p_quote: a.dataset.id, p_result: a.dataset.v, p_note: null }); await refreshSel(); }),
  cl_note_go: guard(async () => { const b = val('cp_body'); if (!b) return toast(ERR.reason_required.replace('a reason (at least 3 letters)', 'a note')); await call('_crmg_lead_note', { p_lead: D.sel.lead.id, p_kind: val('cp_kind'), p_body: b }); D.panel = null; toast('Saved'); await refreshSel(); }),
  cl_follow_go: guard(async () => {
    const fu = localToISO(val('cp_fu')); if (!fu) return toast(ERR.bad_follow_up);
    const id = D.sel.lead.id; const stg = D.sel.lead.stage;
    if (stg === 'following_up') await call('_crmg_lead_save', { p_id: id, p_client: null, p_loc: null, p_data: { next_follow_up: fu, make_task: !!($('#cp_task') || {}).checked } });
    else await call('_crmg_lead_stage', { p_lead: id, p_to: 'following_up', p_note: val('cp_note') || null, p_args: { follow_up: fu, make_task: !!($('#cp_task') || {}).checked } });
    D.panel = null; toast('Saved'); await refreshSel();
  }),
  cl_won_go: guard(async () => { const r = val('cp_reason'); await call('_crmg_lead_stage', { p_lead: D.sel.lead.id, p_to: 'won', p_note: null, p_args: r ? { reason: r } : {} }); D.panel = null; toast('Marked as won'); await refreshSel(); }),
  cl_lost_go: guard(async () => { const r = val('cp_reason'); if (!r) return toast(ERR.lost_reason_required); await call('_crmg_lead_stage', { p_lead: D.sel.lead.id, p_to: 'lost', p_note: val('cp_note') || null, p_args: { lost_reason: r } }); D.panel = null; toast('Closed as lost'); await refreshSel(); }),
  cl_reopen_go: guard(async () => { const r = val('cp_reason'); if (r.length < 3) return toast(ERR.reason_required); await call('_crmg_lead_reopen', { p_lead: D.sel.lead.id, p_reason: r, p_to: val('cp_to') || 'enquiry' }); D.panel = null; toast('Reopened'); await refreshSel(); }),
  cl_assign_go: guard(async () => { await call('_crmg_lead_assign', { p_lead: D.sel.lead.id, p_user: val('cp_who'), p_reason: null }); D.panel = null; toast('Saved'); await refreshSel(); }),
  cl_convert_go: guard(async () => {
    const kind = val('cp_kind'); const args = {}; const rs = val('cp_reason'); if (rs) args.reason = rs;
    if (kind === 'online_order') { const ch = val('cp_ch'); if (!ch) return toast(ERR.channel_required); Object.assign(args, { channel_id: Number(ch), delivery_mode: val('cp_dm') || 'pickup' }); if (val('cp_dd')) args.delivery_date = val('cp_dd'); if (val('cp_addr')) args.address = val('cp_addr'); }
    if (kind === 'link_order') args.order_id = val('cp_target'); if (kind === 'link_form') args.entry_id = val('cp_target');
    const r = await call('_crmg_lead_convert', { p_lead: D.sel.lead.id, p_client: uuid(), p_kind: kind, p_args: args });
    D.panel = null; toast(r.order_no ? 'Order ' + r.order_no + ' made' : r.form ? 'Draft form ' + r.form + ' made' : 'Linked'); await refreshSel();
  }),
  cl_rep_go: guard(async () => { D.from = val('cr_from') || D.from; D.to = val('cr_to') || D.to; await repLoad(); render(); }),
  cl_list_add: guard(async (a) => { const k = a.dataset.k, t = val('cl_new_' + k); if (!t) return; const code = t.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').replace(/^([0-9])/, 'x$1').slice(0, 30); await call('_crmg_list_save', { p_kind: k, p_code: code, p_label: t, p_active: true }); toast('Added'); await load(); }),
  cl_list_tog: guard(async (a) => { await call('_crmg_list_save', { p_kind: a.dataset.k, p_code: a.dataset.c, p_label: a.dataset.l, p_active: a.dataset.a === '1' }); await load(); }),
});
function readQuote0() { (D.q.lines || []).forEach((_, i) => { D.q.lines[i] = { d: val('ql_d' + i), q: val('ql_q' + i), p: val('ql_p' + i) }; }); }
async function repLoad() { D.rep = null; D.rep = await call('_crmg_lead_report', { p_from: D.from || null, p_to: D.to || null, p_loc: D.loc ? Number(D.loc) : null }); if (!D.from) { D.from = D.rep.from; D.to = D.rep.to; } }
document.addEventListener('change', (e) => { const t = e.target && e.target.closest ? e.target.closest('[data-chg]') : null; if (t && H[t.dataset.chg]) H[t.dataset.chg](t); });

/* ---------- the (i) info sheet texts and the inbox hook ---------- */
const INFO = {};   // filled from docs/integration/CRM-G_info.json by the generated block below
const CL = {
  INFO,
  /* an inbox message becomes an enquiry (the integrator adds one button in inbox.js; docs/integration/CRM-G.md) */
  async track(msg) {
    const r = await call('_crmg_lead_save', { p_id: null, p_client: uuid(), p_loc: msg.location_id, p_data: { inbound_message_id: msg.id, source: 'message', contact_name: msg.customer_name || msg.customer_handle || null, contact_phone: msg.phone || null } });
    location.hash = '#/crmleads/' + r.id; return r;
  },
};
B.crmLeads = CL;
/*INFO-BEGIN*/
Object.assign(INFO, {
 "crm_lead_on": {
  "kind": "setting",
  "label": "Track party, wholesale, corporate and gift enquiries",
  "what_it_does": "Lets staff write down an enquiry, send a quote with items and a valid-until date, follow it up, and mark it won or lost. A won enquiry can be turned into the normal order or a draft party form.",
  "why_it_matters": "Big orders are won by following up. Without a list, quotes are forgotten and nobody learns why orders were lost.",
  "default": "Off. The enquiry screen shows a short note and nothing else.",
  "if_switched": "On: the Party and gift enquiries screen works for people who may use it. Nothing is posted to the books, no message is sent to a customer, and no order is made until a manager turns a won enquiry into one.",
  "who_can_change": "Only the owner, in Settings."
 },
 "crm_task_on": {
  "kind": "setting",
  "label": "Use follow-up tasks and the My tasks list",
  "what_it_does": "Lets staff add a task with a due date and time, tick it done, snooze it, or skip it with a reason. Overdue tasks are listed first on My tasks.",
  "why_it_matters": "A reminder with a name and a time gets done. A thing everybody should do is done by nobody.",
  "default": "Off. No task can be added.",
  "if_switched": "On: staff keep their own list and managers can give tasks to others (if allowed). A task never posts to the books and never messages a customer.",
  "who_can_change": "Only the owner, in Settings."
 },
 "crm_lead_lost_by": {
  "kind": "setting",
  "label": "Who may close an enquiry as lost",
  "what_it_does": "Chooses whether only managers, or also the person the enquiry is assigned to, may close it as lost. A lost reason from the list is always needed.",
  "why_it_matters": "Closing as lost ends the follow-up. A manager check stops a good enquiry from being dropped quietly.",
  "default": "Manager: only the owner or a holder of the right Manage enquiries.",
  "if_switched": "Assignee: the person it is assigned to can also close it, still with a reason from the list.",
  "who_can_change": "Only the owner, in Settings."
 },
 "crm_lead_reopen_mode": {
  "kind": "setting",
  "label": "Reopening a lost enquiry",
  "what_it_does": "Decides who may bring a lost enquiry back. Every reopen needs a written reason and appears on the Exceptions list.",
  "why_it_matters": "Customers sometimes come back. Reopening keeps the old history instead of starting again, but it should be visible.",
  "default": "Reason: a manager may reopen with a written reason.",
  "if_switched": "Owner: only the owner may reopen. Off: a lost enquiry can never be reopened; a new enquiry must be started.",
  "who_can_change": "Only the owner, in Settings."
 },
 "crm_lead_win_needs_quote": {
  "kind": "setting",
  "label": "An enquiry can be won only after a quote was sent",
  "what_it_does": "Asks for a sent quote before an enquiry can be marked won.",
  "why_it_matters": "A quote is the written price the customer agreed to. Without it, disputes about price are hard to settle.",
  "default": "Off. An enquiry can be won without a quote.",
  "if_switched": "On: staff must send a quote first. A manager can still win it without one by writing a reason, which goes to the Exceptions list.",
  "who_can_change": "Only the owner, in Settings."
 },
 "crm_lead_quote_valid_days": {
  "kind": "setting",
  "label": "Quote validity: default number of days",
  "what_it_does": "Fills in the valid-until date of a quote as today plus this many days.",
  "why_it_matters": "A quote that never ends can be used months later at an old price.",
  "default": "Blank. The person must type the valid-until date; a quote without one cannot be sent.",
  "if_switched": "With a number: the date is filled in automatically and can still be changed.",
  "who_can_change": "Only the owner, in Settings."
 },
 "crm_quote_min_lead_days": {
  "kind": "setting",
  "label": "Late quote: least days between the quote and the event",
  "what_it_does": "Treats a quote as late when the event is closer than this many days, or the valid-until date is already past.",
  "why_it_matters": "Cakes and party orders need time to make. A late quote is a promise that may not be kept.",
  "default": "Blank. No check on the event date. A valid-until date in the past is always treated as late.",
  "if_switched": "With a number: a late quote needs a written reason and appears on the Exceptions list. It is not blocked.",
  "who_can_change": "Only the owner, in Settings."
 },
 "crm_lead_stale_days": {
  "kind": "setting",
  "label": "Flag an open enquiry as stale after this many days of silence",
  "what_it_does": "Marks an open enquiry with no note, quote, task or stage change for this many days.",
  "why_it_matters": "Enquiries go cold when nobody touches them. A flag shows which ones to call first.",
  "default": "Blank. No stale flag.",
  "if_switched": "With a number: a Stale flag shows on the board and the report, and counts in the in-app reminder if reminders are on.",
  "who_can_change": "Only the owner, in Settings."
 },
 "crm_lead_list_add_mode": {
  "kind": "setting",
  "label": "Who may add a lost reason, source or occasion to the lists",
  "what_it_does": "Chooses who can add or retire entries in the three lists. The entry Other can never be removed.",
  "why_it_matters": "Clean lists make the win and loss report readable. Many near-duplicate reasons make it useless.",
  "default": "Owner only.",
  "if_switched": "Manager: a holder of the right Manage enquiries can also add and retire entries.",
  "who_can_change": "Only the owner, in Settings."
 },
 "crm_task_default_due_hours": {
  "kind": "setting",
  "label": "Task due time when none is typed",
  "what_it_does": "Fills in the due time of a new task as now plus this many hours when the person leaves it empty.",
  "why_it_matters": "A task with no due time never becomes overdue and is easy to forget.",
  "default": "Blank. The person must type a due date and time.",
  "if_switched": "With a number: the due time is filled in; it can be changed.",
  "who_can_change": "Only the owner, in Settings."
 },
 "crm_task_snooze_max_days": {
  "kind": "setting",
  "label": "Longest snooze for a task",
  "what_it_does": "Limits how far into the future a task can be snoozed.",
  "why_it_matters": "Snoozing again and again is a way to avoid a task. A limit keeps it in view.",
  "default": "Blank. No limit.",
  "if_switched": "With a number: a longer snooze is refused with a message.",
  "who_can_change": "Only the owner, in Settings."
 },
 "crm_order_task_days": {
  "kind": "setting",
  "label": "Add a delivery task when an enquiry becomes an order",
  "what_it_does": "When a won enquiry is turned into an order that has a delivery date, adds a task for the assigned person this many days before the delivery. It closes by itself when the order is delivered or cancelled.",
  "why_it_matters": "A reminder before delivery protects the biggest orders from being missed.",
  "default": "Blank. No task is added.",
  "if_switched": "With a number (0 = on the day): the task appears on My tasks. Needs tasks switched on.",
  "who_can_change": "Only the owner, in Settings."
 },
 "crm_task_reminder_on": {
  "kind": "setting",
  "label": "Send staff an in-app reminder for due tasks and stale enquiries",
  "what_it_does": "Lets the 30-minute notify job add one in-app line per person per day with counts of overdue tasks, tasks due today and enquiries to follow up.",
  "why_it_matters": "Staff who do not open My tasks still hear that something is waiting.",
  "default": "Off. Nothing is sent; staff see their list when they open My tasks.",
  "if_switched": "On: one line per person per day, counts only (no customer name or phone). It never messages a customer. It works only after the notify job is told to call it (see the integration note).",
  "who_can_change": "Only the owner, in Settings."
 },
 "crm_lead_manage": {
  "kind": "right",
  "label": "Manage enquiries of my outlets",
  "what_it_does": "Lets a person see every enquiry of the outlets they work at, give an enquiry to someone, close one as lost, reopen one, and turn a won one into an order or form.",
  "why_it_matters": "This is the manager's right. Without it, a person sees only the enquiries they started or were given.",
  "default": "Given to nobody. Only the owner has it.",
  "if_switched": "Given to a role or a person: they get these powers inside their own outlets only.",
  "who_can_change": "Only the owner, under Roles and permissions."
 },
 "crm_lead_all": {
  "kind": "right",
  "label": "See and work on the enquiries of every outlet",
  "what_it_does": "Removes the outlet limit: the person sees and works on enquiries of all outlets.",
  "why_it_matters": "A showroom manager should see only their own outlet's enquiries. Head office may need all of them.",
  "default": "Given to nobody. Only the owner has it.",
  "if_switched": "Given to a person: they see every outlet's enquiries and the report for all outlets.",
  "who_can_change": "Only the owner, under Roles and permissions."
 },
 "crm_task_assign": {
  "kind": "right",
  "label": "Give tasks to other people",
  "what_it_does": "Lets a person add a task for a colleague.",
  "why_it_matters": "A task with a named person is done; a task for everybody is not.",
  "default": "Given to nobody. Only the owner has it.",
  "if_switched": "Given to a person: they can choose who a task goes to, among people who work at the same outlet.",
  "who_can_change": "Only the owner, under Roles and permissions."
 },
 "crm_task_all": {
  "kind": "right",
  "label": "See the tasks of every person",
  "what_it_does": "Lets a person see all tasks in the Team view of My tasks.",
  "why_it_matters": "A supervisor needs to see what is overdue across the team.",
  "default": "Given to nobody. Only the owner has it.",
  "if_switched": "Given to a person: the Team view shows every task.",
  "who_can_change": "Only the owner, under Roles and permissions."
 },
 "screen_crmleads": {
  "kind": "screen",
  "label": "Party and gift enquiries",
  "what_it_does": "The board of enquiries by stage (Enquiry, Quoted, Following up, Won, Lost), the enquiry sheet with notes, quotes and history, the win and loss report, and the three lists.",
  "why_it_matters": "It is the one place where a big order is followed from the first question to the delivered cake.",
  "default": "Visible, but it says that tracking is switched off until the owner switches it on.",
  "if_switched": "Turning enquiry tracking on makes the board work. Nothing starts by itself.",
  "who_can_change": "Only the owner switches it on."
 },
 "screen_crmtasks": {
  "kind": "screen",
  "label": "My tasks",
  "what_it_does": "Overdue tasks first, then due today, later and snoozed. Done, snooze or skip with one tap.",
  "why_it_matters": "It is the staff member's daily to-do list for customers and orders.",
  "default": "Visible, but it says that tasks are switched off until the owner switches them on.",
  "if_switched": "Turning tasks on makes the list work.",
  "who_can_change": "Only the owner switches it on."
 }
});
/*INFO-END*/

async function view() {
  if (B.loadStatic) await B.loadStatic();
  css(); Object.assign(D, { tab: 'board', st: null, board: null, sel: null, panel: null, form: null, q: null, rep: null });
  shell('Party and gift enquiries', '<div id="cl_body"><p class="muted">…</p></div>', true);
  try {
    await load();
    const id = location.hash.replace(/^#\/?/, '').split('/')[1];
    if (id && D.st.lead_on) { await Promise.all([loadItems(), loadChannels()]); await openLead(id); }
  } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { crmleads: view });
})();
