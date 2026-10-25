/* Islamia BOS · CRM-B consent and privacy (#/crmconsent). Record and withdraw a customer's yes / no to messages per channel (SMS, WhatsApp), do-not-contact, the paper-list import,
   the consent register, the access log (who opened a hidden phone number), the customer export (with reason, cap and log) and the owner's privacy settings.
   Also the small API other screens call (docs/integration/CRM-B.md has the exact hook lines):  BOS.crmConsent.directory() / profile(id) / menuHTML(row) / sheet(id) / callHTML(row) / posStrip(mobile) / afterSale(mobile) / printGate(what, n).
   Server: supabase/phase303.sql, phase304.sql (_crmb_consent_*, _crmb_prefs_set, _crmb_customer_list, _crmb_phone_reveal, _crmb_export, _crmb_print_log, _crmb_policy, _crmb_view_log_list, _crmb_export_log_list).
   Every setting defaults to today's behaviour; the server decides every right (a hidden button is also a refused request). English labels only for now (owner rule). UNVERIFIED on a real phone and on a real Supabase project. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet, H } = A;
const $ = (s, el = document) => el.querySelector(s);
const rid = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3) | 8).toString(16); }));
const val = (id) => (($('#' + id) || {}).value || '').trim();
const chip = (txt, cls) => `<span class="chip ${cls || ''}">${esc(txt)}</span>`;
const fld = (id, label, inner) => `<div><label for="${id}">${esc(label)}</label>${inner}</div>`;

const ERR = {
  not_allowed: 'You do not have permission.', bad_input: 'Something in the form is not valid.', customer_not_found: 'Customer not found.', bad_phone: 'This customer has no valid mobile number, so a yes cannot be recorded.',
  bad_mobile: 'That is not a mobile number.', reason_required: 'Write a reason (at least 3 characters).', module_off: 'This is switched off in Settings.', export_limit_not_set: 'The most rows one export may contain is not set yet (Settings).',
  bad_filter: 'The filter is not valid.', no_rows: 'The list is empty.', too_many_rows: 'More than 2000 rows: split the list.',
};
const eText = (e) => { const m = String((e && e.message) || '').replace(/\bnot allowed\b/, 'not_allowed'); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? ERR[k] : m || 'error'; };
const HOW = { pos_tick: 'Ticked at the counter', phone: 'Told us by phone', paper_form: 'Paper form', message_reply: 'Replied to a message', owner_entry: 'Entered by the owner or manager', import: 'Paper list import', other: 'Other' };
const HOW_COUNTER = ['pos_tick', 'phone', 'paper_form', 'message_reply'];
const STAT = { in: 'Agrees', out: 'Does not agree', not_asked: 'Not asked' };
const CH = { sms: 'SMS', whatsapp: 'WhatsApp' };

const missing = (e) => e && e.raw && (e.raw.code === 'PGRST202' || /does not exist|could not find/i.test(String(e.raw.message || '')));
async function call(fn, args) {
  const r = await sb.rpc(fn, args || {});
  if (r.error) { const e = new Error(eText(r.error)); e.raw = r.error; throw e; }
  return r.data;
}

// ---------------- policy (what this person may do now; cached 60 s) ----------------
const P = { pol: null, at: 0, pending: null };
function policy(force) {
  if (!force && P.pol && Date.now() - P.at < 60000) return Promise.resolve(P.pol);
  if (P.pending) return P.pending;
  P.pending = (async () => {
    try { P.pol = await call('_crmb_policy', {}); } catch (e) { P.pol = missing(e) ? { missing: true } : (P.pol || { missing: true, error: e.message }); }
    P.at = Date.now(); P.pending = null; return P.pol;
  })();
  return P.pending;
}

// ---------------- API for the existing screens ----------------
// customers.js: the list. Same rows as customer_directory (plus masked / linked_to / linked_count). Falls back to customer_directory when phase304 is not on the server.
async function directory(collapse) {
  policy();   // warm the cache so the menu buttons know what this person may do
  const r = await sb.rpc('_crmb_customer_list', { p_limit: 5000, p_collapse: !!collapse });
  if (r.error && (r.error.code === 'PGRST202' || /does not exist|could not find/i.test(String(r.error.message || '')))) return sb.rpc('customer_directory');
  return r;
}
// customers.js: the profile sheet. Same answer as customer_profile (plus masked); falls back to it when phase304 is not on the server.
async function profile(id) {
  const r = await sb.rpc('_crmb_customer_profile', { p_customer: id });
  if (r.error && (r.error.code === 'PGRST202' || /does not exist|could not find/i.test(String(r.error.message || '')))) return sb.rpc('customer_profile', { p_customer: id });
  return r;
}
// the extra buttons of the customer menu (⋮): "Messages" for people who may record consent
function menuHTML(row) {
  const pol = P.pol; if (!pol) { policy(); return ''; }
  if (pol.missing || !pol.can_consent || !row) return '';
  return `<button type="button" class="full" data-act="crmc_open" data-v="${esc(row.id)}" data-n="${esc(row.name)}">Messages (consent)</button>`;
}
// the Call button of a list row / menu: a plain tel link when the number is visible, a "ask first" button when it is hidden
function callHTML(row, label) {
  const l = esc(label || 'Call');
  if (row && row.masked) {
    const pol = P.pol || {};
    return pol.can_reveal ? `<button type="button" class="full tog" data-act="crmc_call" data-v="${esc(row.id)}" style="text-align:center;padding:10px">${l}</button>` : `<div class="muted center">Phone number is hidden</div>`;
  }
  return `<a class="full tog" href="tel:${esc(row ? row.mobile : '')}" style="text-align:center;padding:10px">${l}</a>`;
}
// customers.js print button: true = go ahead (the print is logged), false = refused with a message
async function printGate(what, n) {
  const pol = await policy();
  if (pol.missing) return true;
  if (!pol.can_print) { toast('You do not have permission to print the customer list.'); return false; }
  try { await call('_crmb_print_log', { p_what: what || 'customer_list', p_count: Math.max(0, Number(n) || 0), p_reason: null }); } catch (e) { if (!missing(e)) { toast(e.message); return false; } }
  return true;
}

// ---------------- the consent sheet (one customer) ----------------
const C = { id: null, name: '', st: null, hist: null, how: 'phone' };
async function sheet(id, name) {
  C.id = id; C.name = name || ''; C.st = null; C.hist = null;
  const pol = await policy();
  if (pol.missing || !pol.can_consent) { toast(pol.missing ? 'Consent is not set up on the server yet.' : 'You do not have permission to record consent.'); return; }
  try {
    C.st = await call('_crmb_consent_get', { p_customer: id });
    if (pol.can_manage_consent) C.hist = await call('_crmb_consent_history', { p_customer: id, p_limit: 5 });
  } catch (e) { return toast(e.message); }
  drawSheet();
}
function howOptions(pol) {
  const keys = pol.can_manage_consent ? Object.keys(HOW) : HOW_COUNTER;
  if (!keys.includes(C.how)) C.how = keys[0];
  return keys.map((k) => `<option value="${k}" ${C.how === k ? 'selected' : ''}>${esc(HOW[k])}</option>`).join('');
}
function drawSheet() {
  const pol = P.pol || {}, st = C.st; if (!st) return;
  const chRow = (ch) => {
    const s = (st.channels && st.channels[ch]) || { status: 'not_asked' };
    return `<div class="card stack crmc-ch" data-ch="${ch}"><div class="row between"><b>${esc(CH[ch])}</b>${chip(STAT[s.status] || s.status, s.status === 'in' ? 'ok' : s.status === 'out' ? 'bad' : '')}</div>
      ${s.how ? `<div class="muted">${esc(HOW[s.how] || s.how)}${s.by ? ' · ' + esc(s.by) : ''}</div>` : ''}
      <div class="row wrap"><button type="button" class="primary" data-act="crmc_set" data-ch="${ch}" data-in="1" ${s.status === 'in' ? 'disabled' : ''}>Customer agrees</button>
      <button type="button" class="btn" data-act="crmc_set" data-ch="${ch}" data-in="0" ${s.status === 'out' ? 'disabled' : ''}>Customer does not agree</button></div></div>`;
  };
  const dnc = st.dnc;
  openSheet(`<h3>Messages: ${esc(C.name || 'customer')}</h3><div class="stack" id="crmc_sheet">
    <p class="muted">Write down what the customer told us. Nothing is ever sent to a customer who has not agreed. A "no" stops waiting messages at once.</p>
    ${chRow('sms')}${chRow('whatsapp')}
    ${fld('crmc_how', 'How did the customer say it?', `<select id="crmc_how">${howOptions(pol)}</select>`)}
    ${fld('crmc_note', 'Note (needed when a customer who said no agrees again)', `<input id="crmc_note" autocomplete="off" maxlength="300">`)}
    <div class="card stack"><div class="row between"><b>Do not contact</b>${chip(dnc ? 'On' : 'Off', dnc ? 'bad' : '')}</div>
      <div class="muted">${dnc ? 'No message at all is sent, on any channel, even if the customer agreed before.' : 'Switch this on when a customer asks not to be contacted at all.'}</div>
      ${dnc ? (pol.can_manage_consent ? '<button type="button" class="btn" data-act="crmc_dnc" data-on="0">Allow contact again (note needed)</button>' : '<div class="muted">Only a manager can switch this off.</div>') : '<button type="button" class="btn" data-act="crmc_dnc" data-on="1">Do not contact</button>'}</div>
    ${st.block === 'group_opted_out' || st.block === 'group_dnc' ? '<div class="notice warn">Another number of the same person said no, so this one is protected too.</div>' : ''}
    ${C.hist && C.hist.length ? `<b>Last changes</b>${C.hist.map((h) => `<div class="muted crmc-hist">${esc(String(h.at).slice(0, 10))} · ${esc(h.kind === 'dnc' ? 'Do not contact ' + h.status : (CH[h.channel] || h.channel) + ' ' + (h.status === 'in' ? 'agrees' : 'does not agree'))} · ${esc(HOW[h.how] || h.how)}${h.note ? ' · ' + esc(h.note) : ''}</div>`).join('')}` : ''}
    <button type="button" class="full" data-act="closesheet">Close</button></div>`);
}
async function afterWrite() { try { C.st = await call('_crmb_consent_get', { p_customer: C.id }); if ((P.pol || {}).can_manage_consent) C.hist = await call('_crmb_consent_history', { p_customer: C.id, p_limit: 5 }); } catch (e) { /* keep the old view */ } drawSheet(); if (D.tab === 'register' && $('#cc_body')) { await loadTab(); draw(); } }

// ---------------- POS: "Agrees to messages?" under the mobile number ----------------
const POS = { mobile: '', choice: null, known: {}, busy: false };
const digits = (m) => String(m || '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).replace(/[^0-9]/g, '');
function posStrip(mobile) {
  const pol = P.pol; if (!pol) { policy().then(() => { const el = $('#crmc_pos'); if (el && P.pol && P.pol.consent_pos_on && P.pol.can_consent) el.outerHTML = posStrip(mobile); }); return ''; }
  if (pol.missing || !pol.consent_pos_on || !pol.can_consent) return '';
  const m = digits(mobile); if (m.length < 10) return '';
  if (POS.mobile !== m) { POS.mobile = m; POS.choice = null; }
  if (POS.known[m] === undefined) {
    POS.known[m] = null;
    sb.rpc('_crmb_consent_get_mobile', { p_mobile: m }).then((r) => { POS.known[m] = (!r.error && r.data && r.data.found) ? ((r.data.channels || {}).sms || {}).status || 'not_asked' : 'new'; const el = $('#crmc_pos'); if (el && POS.mobile === m) el.outerHTML = posStrip(m); });
  }
  const k = POS.known[m], c = POS.choice;
  const b = (v, label) => `<button type="button" class="tog ${c === v ? 'on' : ''}" data-act="crmc_pos" data-v="${v}" style="min-height:40px">${esc(label)}</button>`;
  return `<div class="stack" id="crmc_pos" style="margin-top:6px"><div class="muted">Agrees to messages?${k && k !== 'new' ? ' Now: ' + esc(STAT[k] || k) : ''}</div>
    <div class="row wrap" style="gap:6px">${b('yes', 'Yes')}${b('no', 'No')}${b('none', 'Not asked')}</div></div>`;
}
// pos.js after a sale was sent: write down the tick (never blocks the sale)
async function afterSale(mobile) {
  const m = digits(mobile); const c = POS.choice;
  if (!m || POS.mobile !== m || (c !== 'yes' && c !== 'no')) return false;
  try {
    await call('_crmb_consent_set_mobile', { p_client: rid(), p_mobile: m, p_channel: 'sms', p_in: c === 'yes', p_how: 'pos_tick', p_note: c === 'yes' && POS.known[m] === 'out' ? 'customer agreed again at the counter' : null, p_loc: null, p_text_version: null });
    POS.choice = null; delete POS.known[m]; return true;
  } catch (e) { toast('Consent was not saved: ' + e.message); return false; }
}

// ---------------- the screen ----------------
const TABS = [['register', 'Consent'], ['import', 'Paper list'], ['export', 'Export'], ['access', 'Access log'], ['settings', 'Settings']];
const RULE_KEYS = ['crm_consent_pos_on', 'crm_quiet_from', 'crm_quiet_to', 'crm_pii_guard_on', 'crm_mask_style', 'crm_unmask_reason_required', 'crm_reveal_for_call', 'crm_export_on', 'crm_export_max_rows', 'crm_print_needs_export'];
const D = { tab: 'register', err: null, reg: null, q: '', status: '', channel: 'sms', limit: 50, imp: { text: '', channel: 'sms', yes: true, note: '', dry: null, hash: '', client: rid() }, vlog: null, elog: null, rules: null, exp: { client: rid() } };

function tabsBar(pol) {
  const show = TABS.filter(([k]) => (k === 'import' ? pol.can_manage_consent : k === 'export' ? pol.export_on || pol.is_owner : k === 'access' ? pol.is_owner : true));
  return `<div class="row wrap" id="cc_tabs" style="gap:.3rem">${show.map(([k, l]) => `<button type="button" class="tog ${D.tab === k ? 'on' : ''}" data-act="cc_tab" data-v="${k}">${esc(l)}</button>`).join('')}</div>`;
}
function summaryHTML(sm) {
  if (!sm || !sm.channels) return '';
  const c = sm.channels[D.channel] || {};
  return `<div class="card stack" id="cc_sum"><div class="row wrap">${chip((c.in ?? 0) + ' agree', 'ok')}${chip((c.out ?? 0) + ' do not agree', 'bad')}${chip((c.not_asked ?? 0) + ' not asked')}${chip((sm.dnc ?? 0) + ' do not contact', sm.dnc ? 'warn' : '')}</div>
    <div class="muted">${c.coverage_pct === null || c.coverage_pct === undefined ? 'No customers yet.' : 'Asked so far: ' + esc(String(c.coverage_pct)) + '% of active customers. A customer who was never asked gets no message.'}</div></div>`;
}
function registerHTML(pol) {
  const R = D.reg;
  if (!pol.can_manage_consent) return '<div class="card"><p>The consent register is for the owner and customer managers. To record a customer\'s answer, open the customer and choose "Messages".</p></div>';
  const bar = `<div class="card stack"><div class="row wrap">${fld('cc_ch', 'Channel', `<select id="cc_ch">${Object.keys(CH).map((k) => `<option value="${k}" ${D.channel === k ? 'selected' : ''}>${CH[k]}</option>`).join('')}</select>`)}
    ${fld('cc_st', 'Show', `<select id="cc_st">${[['', 'Everyone'], ['in', 'Agrees'], ['out', 'Does not agree'], ['not_asked', 'Not asked'], ['dnc', 'Do not contact']].map(([k, l]) => `<option value="${k}" ${D.status === k ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select>`)}</div>
    ${fld('cc_q', 'Search by name' + (R && R.masked ? '' : ' or mobile'), `<input id="cc_q" autocomplete="off" maxlength="60" value="${esc(D.q)}">`)}
    <button type="button" class="primary full" data-act="cc_show">Show</button></div>`;
  if (!R) return bar;
  const rows = (R.rows || []).map((r) => `<div class="card item crmc-row" data-act="cc_open" data-v="${esc(r.id)}" data-n="${esc(r.name)}"><div style="min-width:0;flex:1"><div class="nm">${esc(r.name)}</div><div class="muted">${esc(r.mobile)}${r.how ? ' · ' + esc(HOW[r.how] || r.how) : ''}</div></div>
      <div class="pr">${r.dnc ? chip('Do not contact', 'bad') : ''}${chip(STAT[r.status] || r.status, r.status === 'in' ? 'ok' : r.status === 'out' ? 'bad' : '')}</div></div>`).join('');
  return summaryHTML(R.summary) + bar + (rows || '<p class="muted" id="cc_none">Nobody matches.</p>') + ((R.rows || []).length < Number(R.total) ? '<button type="button" class="full" data-act="cc_more">Show more</button>' : '') + `<p class="muted">${esc(String((R.rows || []).length))} of ${esc(String(R.total))}</p>`;
}
function parseMobiles(text) {
  return String(text || '').split(/\r?\n/).map((l) => l.trim()).filter(Boolean).map((l) => ({ mobile: l.split(/[;,\t]/)[0].trim() })).filter((r) => r.mobile && !/^mobile$/i.test(r.mobile));
}
const impHash = () => [D.imp.channel, D.imp.yes, D.imp.note, D.imp.text].join('|');
const IMPST = { will_change: 'will change', same: 'no change', withdrawn_kept: 'said no before: kept', bad_mobile: 'not a mobile number', duplicate_row: 'repeated', unknown_customer: 'no such customer' };
function importHTML() {
  const I = D.imp, r = I.dry, fresh = r && I.hash === impHash();
  const head = `<div class="card stack"><b>Paste a paper list</b>
    <p class="muted">One mobile number per line (the first column is read). Use it for a list the customers signed, or for a list of people who asked to stop. Check first; nothing is written until you press Apply. A customer who said no before is never turned back to yes by a list.</p>
    <div class="row wrap">${fld('im_ch', 'Channel', `<select id="im_ch">${Object.keys(CH).map((k) => `<option value="${k}" ${I.channel === k ? 'selected' : ''}>${CH[k]}</option>`).join('')}</select>`)}
    ${fld('im_yes', 'The list says', `<select id="im_yes"><option value="1" ${I.yes ? 'selected' : ''}>Agrees to messages</option><option value="0" ${!I.yes ? 'selected' : ''}>Does not want messages</option></select>`)}</div>
    ${fld('im_note', 'Name of the list (required, for example "Eid form 2026")', `<input id="im_note" maxlength="200" value="${esc(I.note)}">`)}
    <label for="im_text">Mobile numbers</label><textarea id="im_text" rows="6" spellcheck="false" autocomplete="off">${esc(I.text)}</textarea>
    <div class="row"><button type="button" class="primary" data-act="cc_imcheck">Check</button>${fresh && Number(r.will_change) > 0 ? `<button type="button" class="btn" id="cc_imgo" data-act="cc_imgo">Apply to ${esc(String(r.will_change))} customer(s)</button>` : ''}</div></div>`;
  if (!r) return head;
  return head + `<div class="card stack" id="cc_imres"><div class="row wrap">${chip(r.will_change + ' will change', 'ok')}${chip(r.same + ' no change')}${Number(r.withdrawn_kept) ? chip(r.withdrawn_kept + ' said no before: kept', 'warn') : ''}${Number(r.errors) ? chip(r.errors + ' not valid', 'bad') : ''}</div>
    ${fresh ? '' : '<div class="notice warn">The list changed after the check. Check again.</div>'}
    ${(r.rows || []).filter((x) => x.status !== 'will_change' && x.status !== 'same').map((x) => `<div class="row between"><span>#${esc(String(x.i))} ${esc(x.mobile || '')}</span>${chip(IMPST[x.status] || x.status, x.status === 'withdrawn_kept' ? 'warn' : 'bad')}</div>`).join('')}</div>`;
}
function exportHTML(pol) {
  const log = D.elog;
  const can = pol.can_export;
  const box = `<div class="card stack"><b>Export the customer list</b>
    ${!pol.export_on ? '<p class="muted">Export is switched off in Settings (default).</p>' : pol.export_cap === null || pol.export_cap === undefined ? '<p class="muted">Set the most rows one export may contain in Settings first.</p>'
      : !can ? '<p class="muted">You do not have the right to export.</p>'
      : `<p class="muted">Up to ${esc(String(pol.export_cap))} customers. ${pol.contact_ok ? 'Phone numbers are included.' : 'Phone numbers and addresses are hidden for you, so the file has them hidden too.'} Every export is written to the export log.</p>
        ${fld('ex_reason', pol.is_owner ? 'Reason (optional)' : 'Reason (required)', '<input id="ex_reason" maxlength="200" autocomplete="off">')}
        ${fld('ex_due', 'Who', '<select id="ex_due"><option value="">All customers</option><option value="1">Only customers who owe money</option></select>')}
        <button type="button" class="primary full" data-act="cc_export">Download CSV</button>`}</div>`;
  const rows = (log || []).map((x) => `<div class="card"><div class="row between"><b>${esc(x.kind === 'print' ? 'Print' : 'Export')}: ${esc(x.what)}</b><span class="muted">${esc(String(x.at).slice(0, 16).replace('T', ' '))}</span></div>
      <div class="muted">${esc(x.staff_id || '')} · ${esc(String(x.row_count))} row(s)${x.masked ? ' · hidden numbers' : ''}${x.reason ? ' · ' + esc(x.reason) : ''}</div></div>`).join('');
  return box + (pol.is_owner ? `<h3>Export and print log</h3>${rows || '<p class="muted">Nothing exported or printed yet.</p>'}` : '');
}
function accessHTML() {
  const rows = (D.vlog || []).map((x) => `<div class="card"><div class="row between"><b>${esc(x.customer_name || (x.what === 'list' ? 'Customer list' : '-'))}</b><span class="muted">${esc(String(x.at).slice(0, 16).replace('T', ' '))}</span></div>
      <div class="muted">${esc(x.staff_id || '')} · ${esc(x.what === 'call' ? 'opened to call' : x.what === 'list' ? 'opened the list (' + (x.row_count ?? '') + ')' : 'opened full details')}${x.reason ? ' · ' + esc(x.reason) : ''}</div></div>`).join('');
  return `<p class="muted">Who opened a hidden phone number or address, and why. Only the owner can read this. Nothing is logged while the privacy switch is off.</p>${rows || '<p class="muted" id="cc_nolog">Nobody has opened a hidden number yet.</p>'}`;
}
function settingsHTML(pol) {
  const owner = !!pol.is_owner;
  return '<p class="muted">The defaults keep today\'s behaviour. Every change is written to the change log. Only the owner changes these.</p>' + (D.rules || []).map((r) => {
    const cur = r.value === null || r.value === undefined ? r.default_value : r.value;
    let ctl;
    if (r.kind === 'switch') ctl = owner ? `<label class="row"><input type="checkbox" id="rl_${esc(r.key)}" ${cur === true ? 'checked' : ''}> On</label>` : chip(cur === true ? 'On' : 'Off');
    else if (r.kind === 'choice') ctl = owner ? `<select id="rl_${esc(r.key)}">${(r.choices || []).map((c) => `<option value="${esc(c)}" ${c === cur ? 'selected' : ''}>${esc(c === 'first3_last2' ? 'First 3 and last 2 digits' : c === 'last4' ? 'Last 4 digits only' : c)}</option>`).join('')}</select>` : chip(String(cur));
    else ctl = owner ? `<input id="rl_${esc(r.key)}" inputmode="${r.kind === 'number' ? 'numeric' : 'text'}" value="${esc(cur ?? '')}" placeholder="blank">` : chip(cur === null || cur === undefined || cur === '' ? 'blank' : String(cur));
    return `<div class="card stack cc-rule" data-key="${esc(r.key)}"><b>${esc(r.label_en)}</b><div class="muted">${esc(r.hint_en)}</div>${ctl}${owner ? `<button type="button" class="mini" data-act="cc_rulesave" data-v="${esc(r.key)}">Save</button>` : ''}</div>`;
  }).join('');
}
function draw() {
  const el = $('#cc_body'); if (!el) return;
  if (D.err) { el.innerHTML = `<div class="card"><p>${esc(D.err === 'nofn' ? 'phase303.sql and phase304.sql have not been run on the server yet.' : D.err === 'denied' ? 'You do not have permission to open this page.' : D.err)}</p></div>`; return; }
  const pol = P.pol || {};
  const body = ({ register: () => registerHTML(pol), import: importHTML, export: () => exportHTML(pol), access: accessHTML, settings: () => settingsHTML(pol) })[D.tab]();
  el.innerHTML = `<div class="card" id="cc_head"><div class="row wrap">${chip(pol.guard_on ? 'Phone numbers hidden: ON' : 'Phone numbers hidden: OFF', pol.guard_on ? 'ok' : '')}${chip(pol.consent_pos_on ? 'Counter staff can record: ON' : 'Counter staff can record: OFF')}${chip(pol.export_on ? 'Export: ON' : 'Export: OFF')}</div></div>` + tabsBar(pol) + `<div id="cc_pane">${body}</div>`;
}
async function loadTab() {
  const pol = await policy(true);
  if (pol.missing) { D.err = 'nofn'; return; }
  if (D.tab === 'register' && pol.can_manage_consent) D.reg = await call('_crmb_consent_register', { p_status: D.status || null, p_channel: D.channel, p_search: D.q || null, p_limit: D.limit, p_offset: 0 });
  if (D.tab === 'access' && pol.is_owner) D.vlog = await call('_crmb_view_log_list', { p_limit: 100, p_customer: null });
  if (D.tab === 'export' && pol.is_owner) D.elog = await call('_crmb_export_log_list', { p_limit: 50 });
  if (D.tab === 'settings') { const r = await sb.from('rules').select('key,kind,value,default_value,choices,label_en,hint_en').in('key', RULE_KEYS); D.rules = ((r && r.data) || []).sort((a, b) => RULE_KEYS.indexOf(a.key) - RULE_KEYS.indexOf(b.key)); }
}
async function show(tab) {
  if (tab) D.tab = tab;
  try { D.err = null; await loadTab(); } catch (e) { D.err = missing(e) ? 'nofn' : /permission/i.test(e.message) ? 'denied' : e.message; }
  draw();
}
const act = (fn) => async (a) => { try { await fn(a); } catch (e) { toast(e.message || 'error'); } };
function csvDownload(name, text) {
  try { const b = new Blob([text], { type: 'text/csv' }); const u = URL.createObjectURL(b); const l = document.createElement('a'); l.href = u; l.download = name; document.body.appendChild(l); l.click(); l.remove(); setTimeout(() => URL.revokeObjectURL(u), 2000); } catch (e) { toast('The file could not be saved on this phone.'); }
}

Object.assign(H, {
  crmc_set: act(async (a) => {
    const ch = a.dataset.ch, yes = a.dataset.in === '1', how = val('crmc_how') || 'phone', note = val('crmc_note');
    const was = ((C.st.channels || {})[ch] || {}).status;
    if (yes && was === 'out' && note.length < 3) return toast(ERR.reason_required);
    await call('_crmb_consent_set', { p_client: rid(), p_customer: C.id, p_channel: ch, p_in: yes, p_how: how, p_note: note || null, p_loc: null, p_text_version: null });
    C.how = how; toast(yes ? 'Saved: agrees' : 'Saved: does not agree'); await afterWrite();
  }),
  crmc_dnc: act(async (a) => {
    const on = a.dataset.on === '1', note = val('crmc_note');
    if (!on && note.length < 3) return toast(ERR.reason_required);
    await call('_crmb_prefs_set', { p_client: rid(), p_customer: C.id, p_dnc: on, p_note: note || null, p_how: val('crmc_how') || 'phone', p_loc: null });
    toast(on ? 'Saved: do not contact' : 'Saved: contact allowed'); await afterWrite();
  }),
  crmc_call: (a) => {
    const id = a.dataset.v, pol = P.pol || {};
    openSheet(`<h3>Open the phone number</h3><div class="stack"><p class="muted">The number is hidden. Opening it is written to the access log with your reason.</p>
      ${fld('cl_why', pol.reason_required ? 'Reason (required)' : 'Reason (optional)', '<input id="cl_why" maxlength="200" autocomplete="off" placeholder="for example: order is ready">')}
      <button type="button" class="primary full" data-act="crmc_callgo" data-v="${esc(id)}">Open and call</button><button type="button" class="full" data-act="closesheet">Cancel</button></div>`);
  },
  crmc_callgo: act(async (a) => {
    const why = val('cl_why'); if ((P.pol || {}).reason_required && why.length < 3) return toast(ERR.reason_required);
    const r = await call('_crmb_phone_reveal', { p_customer: a.dataset.v, p_reason: why || null });
    closeSheet(); if (r && r.mobile) window.location.href = 'tel:' + r.mobile;
  }),
  crmc_open: (a) => { closeSheet(); return sheet(a.dataset.v, a.dataset.n); },
  crmc_pos: (a) => { POS.choice = a.dataset.v === 'none' ? null : a.dataset.v; const el = $('#crmc_pos'); if (el) el.outerHTML = posStrip(POS.mobile); },
  cc_tab: (a) => show(a.dataset.v),
  cc_show: act(async () => { D.q = val('cc_q'); D.status = val('cc_st'); D.channel = val('cc_ch') || 'sms'; D.limit = 50; await show(); }),
  cc_more: act(async () => { D.limit += 50; await show(); }),
  cc_open: (a) => sheet(a.dataset.v, a.dataset.n),
  cc_imcheck: act(async () => {
    const I = D.imp; I.channel = val('im_ch') || 'sms'; I.yes = val('im_yes') !== '0'; I.note = val('im_note'); I.text = ($('#im_text') || {}).value || '';
    if (I.note.length < 3) return toast('Write the name of the list.');
    const rows = parseMobiles(I.text); if (!rows.length) return toast('Paste at least one mobile number.');
    I.dry = await call('_crmb_consent_import', { p_client: I.client, p_rows: rows, p_channel: I.channel, p_in: I.yes, p_list_note: I.note, p_dry: true }); I.hash = impHash(); draw();
  }),
  cc_imgo: act(async () => {
    const I = D.imp; if (I.hash !== impHash()) return toast('Check again first.');
    const r = await call('_crmb_consent_import', { p_client: I.client, p_rows: parseMobiles(I.text), p_channel: I.channel, p_in: I.yes, p_list_note: I.note, p_dry: false });
    toast('Applied to ' + (r.will_change ?? 0) + ' customer(s)'); D.imp = { text: '', channel: I.channel, yes: I.yes, note: '', dry: null, hash: '', client: rid() }; await show('import');
  }),
  cc_export: act(async () => {
    const why = val('ex_reason'), pol = P.pol || {}; if (!pol.is_owner && why.length < 3) return toast(ERR.reason_required);
    const f = val('ex_due') === '1' ? { has_due: true } : {};
    const r = await call('_crmb_export', { p_dataset: 'customers', p_filter: f, p_format: 'csv', p_limit: null, p_reason: why || null });
    csvDownload('customers.csv', r.csv || ''); toast('Exported ' + r.count + ' customer(s)' + (r.truncated ? ' (the cap was reached)' : '')); if (pol.is_owner) await show('export');
  }),
  cc_rulesave: act(async (a) => {
    const key = a.dataset.v, r = (D.rules || []).find((x) => x.key === key); if (!r) return;
    let v;
    if (r.kind === 'switch') v = !!$('#rl_' + key).checked;
    else if (r.kind === 'number') { const t = val('rl_' + key); if (t === '') v = null; else { v = Number(t); if (!Number.isFinite(v)) return toast('That is not a number.'); } }
    else { const t = val('rl_' + key); v = t === '' ? null : t; }
    const res = await sb.rpc('set_rule', { p_key: key, p_value: v }); if (res.error) throw new Error(eText(res.error));
    P.pol = null; toast('Saved'); await show('settings');
  }),
});
document.addEventListener('input', (e) => { if (e.target && e.target.id === 'im_text') D.imp.text = e.target.value; });

async function view() {
  if (B.loadStatic) await B.loadStatic();
  shell('Customer consent and privacy', '<div id="cc_body"><p class="muted">…</p></div>', true);
  try { await show(D.tab); } catch (e) { fail(e); }
}
B.crmConsent = { policy, cached: () => P.pol, directory, profile, menuHTML, sheet, callHTML, posStrip, afterSale, printGate };
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { crmconsent: view });
})();
