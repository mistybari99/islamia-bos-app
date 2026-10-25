/* Islamia BOS · Market intelligence and growth (#/market). Package X6. Research topics, sources and findings (with the source, the date and a reliability rating),
   competitor prices (manual or CSV), opportunities (evidence, KPI, confidence limits, a reason on every move, tasks, measuring from ERP sales) and growth from our own sales.
   Server: supabase/phase487.sql (tables, rights, switches), phase488.sql (write functions), phase489.sql (growth), phase490.sql (research gate OFF, summariser, alerts, digest).
   The server decides every call; a hidden button is also a refused request. Everything is OFF until the owner switches on "Market intelligence workspace".
   Nothing here fetches the internet. Labels are Bangla + English (bn | en). UNVERIFIED on a real phone and on a real Supabase project. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, H } = A;
const $ = (s, el = document) => el.querySelector(s);
const val = (id) => (($('#' + id) || {}).value || '').trim();
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const addDays = (iso, n) => { const d = new Date(iso + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
const T = (bn, en) => `${esc(bn)} <span class="muted">· ${esc(en)}</span>`;
const CAT = { competitors: 'Competitors · প্রতিযোগী', products: 'Products · পণ্য', prices: 'Prices · দাম', customer_trends: 'Customer trends · গ্রাহকের প্রবণতা', festivals: 'Festivals · উৎসব',
  channels: 'Channels · চ্যানেল', technology: 'Technology · প্রযুক্তি', operations_ideas: 'Operations ideas · কার্যক্রম ধারণা' };
const STATUS = { proposed: 'Proposed · প্রস্তাব', saved: 'Saved · সংরক্ষিত', approved: 'Approved · অনুমোদিত', rejected: 'Rejected · বাতিল', in_progress: 'In progress · চলছে', done: 'Done · শেষ', measured: 'Measured · মাপা হয়েছে' };
const NEXT = { proposed: ['saved', 'approved', 'rejected', 'in_progress'], saved: ['approved', 'rejected'], approved: ['in_progress', 'rejected'], in_progress: ['done'], done: [] };
const D = { sum: null, tab: 'overview', topics: [], sources: [], findings: [], opps: [], prices: [], festivals: [], growth: null, outlets: null, basket: null, err: null };

async function call(fn, args) {
  const r = await sb.rpc(fn, args || {});
  if (r.error) { const e = new Error(String(r.error.message || 'error')); e.raw = r.error; throw e; }
  return r.data;
}
const tell = (e) => { const m = String((e && e.message) || ''); const k = (m.match(/^([a-z_]+)/) || [])[1] || ''; const map = {
  not_allowed: 'You do not have permission for this. · এর অনুমতি নেই।', module_off: 'The market workspace is switched off. · বাজার তথ্য বন্ধ আছে।',
  reason_required: 'Write a reason (at least 3 letters). · কারণ লিখুন।', own_request: 'The person who asked can not approve it. · যে চেয়েছে সে অনুমোদন দিতে পারবে না।',
  bad_move: 'That status change is not allowed. · এই অবস্থা বদল হবে না।', locked_after_decision: 'A decided record is locked. Ask the owner for a change. · সিদ্ধান্তের পর বদলানো যায় না।',
  evidence_required: 'Link at least one finding. · অন্তত একটি তথ্য যুক্ত করুন।', kpi_required: 'Write the success measure and its target. · লক্ষ্য মাপার উপায় ও লক্ষ্যমাত্রা লিখুন।',
  confidence_limits_required: 'Say what this does not prove. · এটি কী প্রমাণ করে না তা লিখুন।', quote_not_allowed: 'Quotes are off or too long. Write your own short summary. · উদ্ধৃতি বন্ধ বা বড়।',
  publisher_required: 'Write the publisher. · প্রকাশকের নাম লিখুন।', not_done: 'Measure only after the work is done. · কাজ শেষ হলে মাপুন।',
  not_approved: 'Tasks are made after approval. · অনুমোদনের পরে কাজ তৈরি হয়।' }; return map[k] || m; };
const guard = (fn) => (a) => { fn(a).then(() => toast('Saved · সংরক্ষিত')).catch((e) => toast(tell(e))); };

function css() {
  if (document.getElementById('x6_css')) return;
  const s = document.createElement('style'); s.id = 'x6_css';
  s.textContent = '.x6-tabs{display:flex;flex-wrap:wrap;gap:6px;margin:8px 0}.x6-tabs button{min-height:44px;flex:1 1 30%}'
    + '.x6-card{padding:10px;margin:6px 0;overflow-wrap:anywhere}.x6-grid{display:grid;gap:8px}.x6-pill{display:inline-block;padding:2px 8px;border-radius:10px;background:var(--line,#e5e5e5);font-size:12px;margin:2px}'
    + '.x6-warn{border-left:3px solid #b58900;padding-left:8px}.x6-acts{display:flex;flex-wrap:wrap;gap:6px;margin-top:6px}.x6-acts button{min-height:44px}'
    + 'table.x6-t{width:100%;border-collapse:collapse;font-size:14px}table.x6-t td,table.x6-t th{padding:4px;border-bottom:1px solid var(--line,#e5e5e5);text-align:left;vertical-align:top}'
    + '@media (max-width:360px){.x6-tabs button{flex:1 1 45%}}';
  document.head.appendChild(s);
}

async function loadTab() {
  D.err = null;
  try {
    D.sum = (await call('mi_summary')) || {};
    if (D.tab === 'overview' || D.tab === 'growth') { const d1 = addDays(today(), -6); D.growth = await call('mi_growth_items', { p_d1: d1, p_d2: today(), p_c1: addDays(d1, -7), p_c2: addDays(d1, -1), p_limit: 20 }); }
    if (D.tab === 'growth') {
      const d1 = addDays(today(), -29);
      D.outlets = await call('mi_outlet_compare', { p_d1: d1, p_d2: today() });
      D.basket = await call('mi_basket_pairs', { p_d1: d1, p_d2: today(), p_loc: null, p_limit: 10 });
      D.festivals = arrOf(await sb.from('festival_calendar').select('id,name_en,name_bn,start_date,end_date').eq('active', true).order('start_date', { ascending: false }).limit(20));
    }
    if (D.tab === 'research') {
      D.topics = arrOf(await sb.from('mi_topics').select('id,category,title_bn,title_en,business_relevance,status').eq('status', 'active').order('created_at', { ascending: false }).limit(50));
      D.sources = arrOf(await sb.from('mi_sources').select('id,name,publisher,source_type,reliability,terms_allow_scraping,robots_ok,status').eq('status', 'active').order('created_at', { ascending: false }).limit(50));
      D.findings = arrOf(await sb.from('mi_findings').select('id,summary,source_url,publisher,published_on,retrieved_on,finding_type,freshness_score,quality_score,quality_basis,duplicate_of').order('created_at', { ascending: false }).limit(50));
    }
    if (D.tab === 'prices') {
      D.prices = arrOf(await sb.from('mi_price_obs').select('id,competitor,item_label,price,observed_on,source_url').order('observed_on', { ascending: false }).limit(100));
      D.watch = (await call('mi_watch_alerts')) || {};
    }
    if (D.tab === 'opps') D.opps = arrOf(await sb.from('mi_opportunities').select('id,title,category,status,confidence,confidence_limits,success_kpi,kpi_target,evidence_finding_ids,approval_needed,created_by,benefit_low,benefit_base,cost_estimate').order('created_at', { ascending: false }).limit(50));
  } catch (e) { D.err = tell(e); }
  render();
}
const arrOf = (r) => (r && r.error ? [] : (r && r.data) || []);

function off() {
  return D.sum && !D.sum.on ? `<div class="card x6-warn">${T('বাজার তথ্য এখন বন্ধ। মালিক চালু করলে এখানে লেখা যাবে। নিজে কিছু বদলায় না।', 'The market workspace is OFF. The owner switches it on in Settings. Nothing is changed by viewing this page.')}</div>` : '';
}
const warn = (t) => `<p class="muted x6-warn">${esc(t)}</p>`;
const WARN_GROWTH = 'Past sales patterns show what changed, not why. Season, festivals, price, stock and weather can explain them too. · মৌসুম, উৎসব, দাম ও স্টক কারণ হতে পারে।';

function tabs() {
  const list = [['overview', 'Overview · সারসংক্ষেপ'], ['research', 'Research · গবেষণা'], ['prices', 'Prices · দাম'], ['opps', 'Opportunities · সুযোগ'], ['growth', 'Growth · বৃদ্ধি']];
  return `<div class="x6-tabs" role="tablist">${list.map(([k, l]) => `<button role="tab" data-act="mi_tab" data-v="${k}" aria-selected="${D.tab === k}" class="${D.tab === k ? 'primary' : ''}">${T(l.split(' · ')[1], l.split(' · ')[0])}</button>`).join('')}</div>`;
}

function overview() {
  const s = D.sum || {}, o = s.opportunities || {};
  const pill = (k) => `<span class="x6-pill">${esc(STATUS[k] || k)}: ${esc(o[k] || 0)}</span>`;
  return `<div class="card x6-card"><b>${T('সারসংক্ষেপ', 'Summary')}</b><div>${T('বিষয়', 'Topics')}: ${esc(s.topics || 0)} · ${T('উৎস', 'Sources')}: ${esc(s.sources || 0)} · ${T('তথ্য', 'Findings')}: ${esc(s.findings || 0)} (${esc(s.findings_duplicates || 0)} ${T('ডুপ্লিকেট', 'duplicates')})</div>
    <div>${T('দামের নোট', 'Price notes')}: ${esc(s.price_obs || 0)} · ${T('খোলা ঘাটতি', 'Open product gaps')}: ${esc(s.open_gaps || 0)}</div><div>${Object.keys(STATUS).map(pill).join('')}</div></div>
    <div class="card x6-card"><b>${T('আমাদের বিক্রির বৃদ্ধি (গত ৭ দিন বনাম আগের ৭ দিন)', 'Our sales growth (last 7 days vs the 7 before)')}</b>
      ${growthTable(D.growth, 8)}${warn(WARN_GROWTH)}</div>`;
}
function growthTable(g, n) {
  if (!g || !g.rows) return '<p class="muted">—</p>';
  const c = g.coverage || {};
  const head = `<p class="muted">${T('বিক্রির দিন', 'Trading days')}: ${esc(c.current_trading_days || 0)}/${esc(c.current_calendar_days || 0)} · ${esc(c.base_trading_days || 0)}/${esc(c.base_calendar_days || 0)}</p>`;
  const rows = g.rows.slice(0, n).map((r) => `<tr><td>${esc(r.item_name)}</td><td>${esc(r.cur_net)}</td><td>${esc(r.base_net)}</td><td>${r.growth_pct === null || r.growth_pct === undefined ? '—' : esc(r.growth_pct) + '%'}</td></tr>`).join('');
  return head + (rows ? `<table class="x6-t"><tr><th>Item · পণ্য</th><th>Now</th><th>Before</th><th>%</th></tr>${rows}</table>` : '<p class="muted">No sales in the windows · কোনো বিক্রি নেই</p>');
}

function research() {
  const tc = D.topics.map((t) => `<div class="x6-card card"><b>${esc(t.title_bn)}</b> ${t.title_en ? '· ' + esc(t.title_en) : ''} <span class="x6-pill">${esc(CAT[t.category] || t.category)}</span><div class="muted">${esc(t.business_relevance)}</div></div>`).join('');
  const sc = D.sources.map((s) => `<div class="x6-card card"><b>${esc(s.name)}</b> · ${esc(s.publisher)} · ${esc(s.source_type)} · ${T('রেটিং', 'rating')} ${esc(s.reliability)}
      <div class="muted">${s.terms_allow_scraping ? 'Scraping allowed by owner · মালিক অনুমতি দিয়েছেন' : 'Scraping NOT allowed (default) · অনুমতি নেই'}</div></div>`).join('');
  const fc = D.findings.map((f) => `<div class="x6-card card">${esc(f.summary)}<div class="muted">${esc(f.publisher)} · ${esc(f.finding_type)} · ${T('প্রকাশ', 'published')} ${esc(f.published_on || '—')} · ${T('সংগ্রহ', 'retrieved')} ${esc(f.retrieved_on)}</div>
      <div><span class="x6-pill">freshness ${esc(f.freshness_score)}/3</span><span class="x6-pill">quality ${esc(f.quality_score)}/6</span>${f.duplicate_of ? '<span class="x6-pill">duplicate · ডুপ্লিকেট</span>' : ''}</div><div class="muted">${esc(f.quality_basis)}</div>
      <div class="muted"><a href="${esc(f.source_url)}" target="_blank" rel="noopener noreferrer">${esc(f.source_url)}</a></div></div>`).join('');
  const opts = (rows, lab) => rows.map((r) => `<option value="${esc(r.id)}">${esc(lab(r))}</option>`).join('');
  return `<div class="card x6-card"><b>${T('নতুন তথ্য', 'New finding')}</b><div class="x6-grid">
    <label for="mi_f_url">Source URL · উৎসের লিংক</label><input id="mi_f_url" inputmode="url" maxlength="500" placeholder="https://">
    <label for="mi_f_pub">Publisher · প্রকাশক</label><input id="mi_f_pub" maxlength="160">
    <label for="mi_f_sum">Summary in your words · সারসংক্ষেপ (নিজের ভাষায়)</label><textarea id="mi_f_sum" maxlength="1500" rows="3"></textarea>
    <label for="mi_f_pd">Published · প্রকাশের তারিখ</label><input id="mi_f_pd" type="date">
    <label for="mi_f_type">Type · ধরন</label><select id="mi_f_type"><option value="sourced_fact">Sourced fact · সূত্রযুক্ত তথ্য</option><option value="source_claim">Source claim · উৎসের দাবি</option><option value="analysis">Analysis · বিশ্লেষণ</option><option value="hypothesis">Hypothesis · অনুমান</option></select>
    <label for="mi_f_src">Source · উৎস</label><select id="mi_f_src"><option value="">— none · নেই</option>${opts(D.sources, (s) => s.name + ' (' + s.reliability + ')')}</select>
    <label for="mi_f_topic">Topic · বিষয়</label><select id="mi_f_topic"><option value="">—</option>${opts(D.topics, (t) => t.title_bn)}</select>
    <div class="x6-acts"><button class="primary" data-act="mi_finding_save">${T('সংরক্ষণ', 'Save')}</button></div></div></div>
    <div class="card x6-card"><b>${T('বিষয়', 'Topics')}</b><div class="x6-acts"><button data-act="mi_topic_new">${T('নতুন বিষয়', 'New topic')}</button></div>
      <div id="mi_topic_form" hidden><div class="x6-grid"><label for="mi_t_cat">Category · ধরন</label><select id="mi_t_cat">${Object.entries(CAT).map(([k, l]) => `<option value="${k}">${esc(l)}</option>`).join('')}</select>
      <label for="mi_t_bn">Title (বাংলা) · শিরোনাম</label><input id="mi_t_bn" maxlength="160"><label for="mi_t_en">Title (English)</label><input id="mi_t_en" maxlength="160">
      <label for="mi_t_rel">Why it matters for us · কেন গুরুত্বপূর্ণ</label><textarea id="mi_t_rel" rows="2" maxlength="600"></textarea>
      <div class="x6-acts"><button class="primary" data-act="mi_topic_save">${T('সংরক্ষণ', 'Save')}</button></div></div></div>${tc || '<p class="muted">—</p>'}</div>
    <div class="card x6-card"><b>${T('উৎস', 'Sources')}</b>${sc || '<p class="muted">—</p>'}${warn('Only the owner allows scraping, after reading the terms. Logins and paywalls are never bypassed. · শুধু মালিক অনুমতি দেন।')}</div>
    <div class="card x6-card"><b>${T('তথ্য', 'Findings')}</b>${fc || '<p class="muted">—</p>'}</div>`;
}

function prices() {
  const pr = D.prices.map((p) => `<tr><td>${esc(p.competitor)}</td><td>${esc(p.item_label)}</td><td>${esc(p.price)}</td><td>${esc(p.observed_on)}</td></tr>`).join('');
  const w = D.watch || {};
  const alerts = (w.alerts || []).map((a) => `<li>${esc(a.competitor)} · ${esc(a.item_label)}: ${esc(a.prev_price)} → ${esc(a.last_price)} (${esc(a.change_pct)}%)</li>`).join('');
  return `<div class="card x6-card"><b>${T('দাম যোগ করুন', 'Add a competitor price')}</b><div class="x6-grid">
    <label for="mi_p_comp">Competitor · প্রতিযোগী</label><input id="mi_p_comp" maxlength="160"><label for="mi_p_item">Item · পণ্য</label><input id="mi_p_item" maxlength="200">
    <label for="mi_p_price">Price · দাম</label><input id="mi_p_price" inputmode="decimal"><label for="mi_p_on">Seen on · তারিখ</label><input id="mi_p_on" type="date" value="${today()}">
    <div class="x6-acts"><button class="primary" data-act="mi_price_save">${T('সংরক্ষণ', 'Save')}</button></div></div>
    <label for="mi_p_csv">CSV import (competitor,item_label,price,observed_on) · CSV আমদানি</label><input id="mi_p_csv" type="file" accept=".csv,text/csv">
    <div class="x6-acts"><button data-act="mi_csv_go">${T('আমদানি', 'Import')}</button></div></div>
    <div class="card x6-card"><b>${T('দাম-সতর্কতা', 'Price watch')}</b>${w.threshold == null ? '<p class="muted">Blank threshold: no alert · সীমা খালি, সতর্কতা নেই</p>' : (alerts ? `<ul>${alerts}</ul>` : '<p class="muted">—</p>')}</div>
    <div class="card x6-card"><table class="x6-t"><tr><th>Competitor · প্রতিযোগী</th><th>Item · পণ্য</th><th>Price</th><th>Date</th></tr>${pr}</table>${warn('Typed or imported by a person. Check the source before you act. · নিজে লিখুন বা আমদানি করুন।')}</div>`;
}

function opps() {
  const rows = D.opps.map((o) => {
    const nxt = NEXT[o.status] || [];
    return `<div class="x6-card card"><b>${esc(o.title)}</b> <span class="x6-pill">${esc(STATUS[o.status] || o.status)}</span><span class="x6-pill">${T('আস্থা', 'confidence')} ${esc(o.confidence)}</span>
      <div class="muted">KPI: ${esc(o.success_kpi || '—')} → ${esc(o.kpi_target ?? '—')} · ${T('সীমা', 'limits')}: ${esc(o.confidence_limits)}</div>
      <div class="muted">${T('সুবিধা', 'benefit')} ${esc(o.benefit_low ?? '—')}–${esc(o.benefit_base ?? '—')} · ${T('খরচ', 'cost')} ${esc(o.cost_estimate ?? '—')} · ${T('তথ্য', 'evidence')} ${esc((o.evidence_finding_ids || []).length)}</div>
      <div class="x6-acts">${nxt.map((n) => `<button data-act="mi_move" data-id="${esc(o.id)}" data-to="${n}">${esc(STATUS[n])}</button>`).join('')}
        ${o.status === 'approved' || o.status === 'in_progress' ? `<button data-act="mi_task" data-id="${esc(o.id)}">${T('কাজ যোগ', 'Add task')}</button>` : ''}
        ${o.status === 'done' ? `<button data-act="mi_measure" data-id="${esc(o.id)}">${T('ERP থেকে মাপুন', 'Measure from ERP')}</button>` : ''}</div></div>`;
  }).join('');
  return `<div class="card x6-card"><b>${T('নতুন সুযোগ', 'New opportunity')}</b><div class="x6-grid">
    <label for="mi_o_title">Title · শিরোনাম</label><input id="mi_o_title" maxlength="160">
    <label for="mi_o_cat">Category · ধরন</label><select id="mi_o_cat">${Object.entries(CAT).map(([k, l]) => `<option value="${k}">${esc(l)}</option>`).join('')}<option value="growth_own_data">Own data · নিজের তথ্য</option></select>
    <label for="mi_o_ev">Evidence (finding ids, comma separated) · প্রমাণ</label><input id="mi_o_ev" placeholder="uuid, uuid">
    <label for="mi_o_kpi">Success measure · সফলতার মাপ</label><input id="mi_o_kpi" maxlength="200"><label for="mi_o_tgt">Target · লক্ষ্যমাত্রা</label><input id="mi_o_tgt" inputmode="decimal">
    <label for="mi_o_lo">Benefit low · সুবিধা (কম)</label><input id="mi_o_lo" inputmode="decimal"><label for="mi_o_base">Benefit base · সুবিধা (মূল)</label><input id="mi_o_base" inputmode="decimal">
    <label for="mi_o_cost">Cost · খরচ</label><input id="mi_o_cost" inputmode="decimal">
    <label for="mi_o_conf">Confidence · আস্থা</label><select id="mi_o_conf"><option value="low">low · কম</option><option value="medium">medium · মাঝারি</option><option value="high">high · বেশি</option></select>
    <label for="mi_o_lim">What this does NOT prove · এটি কী প্রমাণ করে না</label><textarea id="mi_o_lim" rows="2" maxlength="600"></textarea>
    <label for="mi_o_risk">Risks · ঝুঁকি</label><textarea id="mi_o_risk" rows="2" maxlength="1000"></textarea>
    <div class="x6-acts"><button class="primary" data-act="mi_opp_save">${T('সংরক্ষণ', 'Save')}</button></div></div></div>
    <div class="card x6-card"><b>${T('সুযোগের তালিকা', 'Opportunities')}</b>${rows || '<p class="muted">—</p>'}
    ${warn('Every change of status needs a reason, kept for ever. The person who asks can not approve it. · প্রতিটি বদলের কারণ লাগে।')}</div>`;
}

function growth() {
  const o = D.outlets || {}, b = D.basket || {};
  const outl = (o.rows || []).map((r) => `<tr><td>${esc(r.outlet)}</td><td>${esc(r.trading_days)}</td><td>${esc(r.net_total)}</td><td>${esc(r.net_per_trading_day)}</td></tr>`).join('');
  const bask = (b.rows || []).map((r) => `<tr><td>${esc(r.item_a)} + ${esc(r.item_b)}</td><td>${esc(r.bills_together)}</td><td>${esc(r.share_of_bills_pct)}%</td></tr>`).join('');
  const fest = D.festivals.map((f) => `<option value="${esc(f.id)}">${esc(f.name_en || f.name_bn)} (${esc(f.start_date)}–${esc(f.end_date)})</option>`).join('');
  return `<div class="card x6-card"><b>${T('আমাদের বিক্রির বৃদ্ধি (গত ৭ দিন)', 'Our sales growth (7 days)')}</b>${growthTable(D.growth, 15)}</div>
    <div class="card x6-card"><b>${T('দোকান তুলনা (প্রতি বিক্রির দিনে, গত ৩০ দিন)', 'Outlet comparison (per trading day, 30 days)')}</b>
      <table class="x6-t"><tr><th>Outlet · দোকান</th><th>Days</th><th>Net</th><th>Per day</th></tr>${outl}</table>${warn('Outlets of different size are not like for like. · ভিন্ন আকারের দোকান সমান নয়।')}</div>
    <div class="card x6-card"><b>${T('একসাথে কেনা পণ্য (গত ৩০ দিন)', 'Bought together (30 days)')}</b>${bask ? `<table class="x6-t"><tr><th>Pair · জোড়া</th><th>Bills</th><th>%</th></tr>${bask}</table>` : '<p class="muted">—</p>'}
      ${warn(b.warning || 'Bought together is a pattern, not a cause. · একসাথে কেনা মানে কারণ নয়।')}</div>
    <div class="card x6-card"><b>${T('উৎসব পর্যালোচনা', 'Festival review')}</b><div class="x6-grid"><label for="mi_fest">Festival · উৎসব</label><select id="mi_fest"><option value="">—</option>${fest}</select>
      <div class="x6-acts"><button data-act="mi_fest_go">${T('দেখুন', 'Show')}</button></div></div><div id="mi_fest_out"></div></div>`;
}

function render() {
  const el = $('#mi_body'); if (!el) return;
  if (D.err) { el.innerHTML = `${tabs()}<div class="card x6-warn">${esc(D.err)}</div>`; return; }
  if (!D.sum) { el.innerHTML = '<p class="muted">…</p>'; return; }
  const body = { overview, research, prices, opps, growth }[D.tab]();
  el.innerHTML = off() + tabs() + body;
}

Object.assign(H, {
  mi_tab: (a) => { D.tab = a.dataset.v; loadTab(); },
  mi_topic_new: () => { const f = $('#mi_topic_form'); if (f) f.hidden = !f.hidden; },
  mi_topic_save: guard(async () => {
    await call('mi_topic_save', { p_id: null, p: { category: val('mi_t_cat'), title_bn: val('mi_t_bn'), title_en: val('mi_t_en'), business_relevance: val('mi_t_rel') }, p_client: crypto.randomUUID ? crypto.randomUUID() : null });
    await loadTab();
  }),
  mi_finding_save: guard(async () => {
    const r = await call('mi_finding_add', { p: { source_url: val('mi_f_url'), publisher: val('mi_f_pub'), summary: val('mi_f_sum'), published_on: val('mi_f_pd') || null,
      finding_type: val('mi_f_type'), source_id: val('mi_f_src') || null, topic_id: val('mi_f_topic') || null }, p_client: crypto.randomUUID ? crypto.randomUUID() : null });
    if (r && r.duplicate_of) toast('Saved. This looks like a duplicate of an earlier finding. · ডুপ্লিকেট হতে পারে।');
    await loadTab();
  }),
  mi_price_save: guard(async () => {
    await call('mi_price_add', { p: { competitor: val('mi_p_comp'), item_label: val('mi_p_item'), price: val('mi_p_price'), observed_on: val('mi_p_on') }, p_client: crypto.randomUUID ? crypto.randomUUID() : null });
    await loadTab();
  }),
  mi_csv_go: async () => {
    const f = ($('#mi_p_csv') || {}).files; if (!f || !f[0]) return toast('Choose a CSV file. · CSV ফাইল বেছে নিন।');
    const text = await f[0].text();
    const lines = text.split(/\r?\n/).filter((l) => l.trim());
    const head = lines.shift().split(',').map((h) => h.trim().toLowerCase());
    const rows = lines.slice(0, 500).map((l) => { const c = l.split(','); const o = {}; head.forEach((h, i) => { o[h] = (c[i] || '').trim(); }); return o; });
    try { const r = await call('mi_price_import', { p_rows: rows }); toast(`${r.inserted} saved, ${(r.rejected || []).length} rejected · ${r.inserted} সংরক্ষিত`); await loadTab(); } catch (e) { toast(tell(e)); }
  },
  mi_opp_save: guard(async () => {
    const ev = val('mi_o_ev').split(',').map((x) => x.trim()).filter(Boolean);
    await call('mi_opportunity_save', { p_id: null, p: { title: val('mi_o_title'), category: val('mi_o_cat'), evidence_finding_ids: ev, success_kpi: val('mi_o_kpi'), kpi_target: val('mi_o_tgt'),
      benefit_low: val('mi_o_lo') || null, benefit_base: val('mi_o_base') || null, cost_estimate: val('mi_o_cost') || null, confidence: val('mi_o_conf'),
      confidence_limits: val('mi_o_lim'), risks: val('mi_o_risk') }, p_client: crypto.randomUUID ? crypto.randomUUID() : null });
    await loadTab();
  }),
  mi_move: async (a) => {
    const to = a.dataset.to; const reason = window.prompt('Reason (kept for ever) · কারণ (স্থায়ীভাবে থাকবে)', '');
    if (reason === null) return;
    try { await call('mi_opportunity_move', { p_id: a.dataset.id, p_to: to, p_reason: reason }); toast('Saved · সংরক্ষিত'); await loadTab(); } catch (e) { toast(tell(e)); }
  },
  mi_task: async (a) => {
    const title = window.prompt('Task · কাজ', ''); if (!title) return;
    try { const due = new Date(Date.now() + 86400000).toISOString(); await call('mi_opportunity_task', { p_id: a.dataset.id, p_title: title, p_due: due }); toast('Task added · কাজ যোগ হয়েছে'); } catch (e) { toast(tell(e)); }
  },
  mi_measure: async (a) => {
    const d = today();
    try { const r = await call('mi_opportunity_measure', { p_id: a.dataset.id, p_from: addDays(d, -6), p_to: d, p_base_from: addDays(d, -13), p_base_to: addDays(d, -7) });
      window.alert(`ERP sales: now ${r.actual}, before ${r.baseline}, change ${r.change}\n\n${r.warning}`); await loadTab(); } catch (e) { toast(tell(e)); }
  },
  mi_fest_go: async () => {
    const id = val('mi_fest'); if (!id) return;
    try { const r = await call('mi_festival_uplift', { p_festival: Number(id) }); const out = $('#mi_fest_out');
      if (out) out.innerHTML = `<p>${T('উৎসবের দিনে প্রতি দিন', 'Festival per trading day')}: ${esc(r.festival_net_per_trading_day ?? '—')} · ${T('আগের সময়', 'before')}: ${esc(r.comparison_net_per_trading_day ?? '—')} · ${T('পর্যবেক্ষিত', 'observed')}: ${esc(r.observed_uplift_pct ?? '—')}% · ${T('আপনার দেওয়া', 'your entered')}: ${esc(r.owner_entered_uplift_pct ?? '—')}%</p>${warn(r.warning)}`;
    } catch (e) { toast(tell(e)); }
  },
});

async function view() {
  if (B.loadStatic) await B.loadStatic();
  css(); D.tab = D.tab || 'overview';
  shell('Market & growth · বাজার ও বৃদ্ধি', '<div id="mi_body"><p class="muted">…</p></div>', true);
  await loadTab();
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { market: view });
})();
