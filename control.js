/* Islamia BOS · Control Center (#/control): one place for everything that is SET (as opposed to entered).
   12 tiles in four groups that open the existing screens; a merged "Needs you" list (counts from the server: control_counts()).
   Access: the owner sees all 12; head management (delegable grant head_management) sees Locations, Rollout board, Location settings, Print & books (Lists only together with the list_manage grant)
   (no costs, no salaries); a person holding only location_manage / settings_approve / list_manage sees just the matching tile.
   Hiding a tile is a convenience only: every screen and RPC refuses on the server. Rollout board and Print & books arrive in later waves (shown as Soon). */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, t, esc, shell, fail } = A;
const L = B.L, lab = B.lab;
const isOwner = () => !!(S.ctx && S.ctx.is_owner);

const X = {
  title: L('কন্ট্রোল সেন্টার', 'Control Center', 'Control Center'), needs: L('আপনার সিদ্ধান্ত দরকার', 'Needs you', 'Needs you (সিদ্ধান্ত)'), nothing: L('এখন কিছু বাকি নেই ✓', 'Nothing is waiting ✓', 'এখন কিছু বাকি নেই ✓'),
  soon: L('শীঘ্রই আসছে', 'Coming soon', 'Coming soon'), noacc: L('এই পাতা দেখার অনুমতি নেই', 'You cannot open this page', 'এই page দেখার permission নেই'), note: L('সংখ্যাগুলো সার্ভার থেকে; আপনি যা সিদ্ধান্ত নিতে পারেন শুধু তাই দেখায়।', 'Counts come from the server and show only what you can decide.', 'Count server থেকে; শুধু আপনি যা decide করতে পারেন তা দেখায়।'),
  g_places: L('স্থান ও রোলআউট', 'Places and rollout', 'Places ও rollout'), g_lists: L('তালিকা ও আইটেম', 'Lists and items', 'Lists ও items'), g_people: L('মানুষ ও অনুমতি', 'People and access', 'People ও access'), g_rules: L('নিয়ম ও সিস্টেম', 'Rules and system', 'Rules ও system'),
  t_locations: L('লোকেশন', 'Locations', 'Locations'), d_locations: L('শোরুম, কারখানা, গোডাউন; নতুন শোরুম', 'Showrooms, factories, godowns; add a showroom', 'Showroom, factory, godown; নতুন showroom'),
  t_rollout: L('রোলআউট বোর্ড', 'Rollout board', 'Rollout board'), d_rollout: L('কাগজ / সমান্তরাল / অ্যাপ', 'Paper / Parallel / App', 'Paper / Parallel / App'),
  t_locset: L('লোকেশন সেটিংস (সীমা)', 'Location settings (limits)', 'Location settings (limits)'), d_locset: L('সেটিংস শিট ০-১ ও সংস্করণ', 'Settings sheet 0-1 and versions', 'Settings sheet 0-1 ও versions'),
  t_lists: L('তালিকা ও অপশন', 'Lists and options', 'Lists ও options'), d_lists: L('অপশন, যোগের নিয়ম, “অন্যান্য”', 'Options, add rules, Other queue', 'Options, add rules, Other queue'),
  t_items: L('আইটেম ও দাম', 'Items and prices', 'Items ও prices'), d_items: L('পণ্য, দাম, ধরন', 'Products, prices, types', 'Products, prices, types'),
  t_staff: L('স্টাফ ও অনুমোদন', 'Staff and approval', 'Staff ও approval'), d_staff: L('স্টাফ, ভূমিকা, লক খোলা', 'Staff, roles, unlock', 'Staff, roles, unlock'),
  t_matrix: L('ভূমিকা × ফর্ম অনুমতি', 'Role × form permissions', 'Role × form permissions'), d_matrix: L('কে কোন ফর্ম', 'Who may use which form', 'কে কোন form'),
  t_rules: L('ফর্মের নিয়ম', 'Form rules', 'Form rules'), d_rules: L('আগে গণনা, লাল ব্লক, চালু/বন্ধ', 'Count first, red block, on/off', 'Count first, red block, on/off'),
  t_printbooks: L('ছাপা ও বই', 'Print and books', 'Print ও books'), d_printbooks: L('সিরিয়াল ও ছাপার নোট', 'Serials and print notes', 'Serials ও print notes'),
  t_settings: L('সেটিংস', 'Settings', 'Settings'), d_settings: L('সাধারণ সেটিংস ও আরও', 'General settings and more', 'General settings ও more'),
  t_logs: L('পরিবর্তনের লগ', 'Change log', 'Change log'), d_logs: L('কে কী বদলেছে', 'Who changed what', 'কে কী বদলেছে'),
  t_backup: L('ব্যাকআপ', 'Backup', 'Backup'), d_backup: L('ডেটা ডাউনলোড', 'Download the data', 'Data download'),
  n_item_requests: L('আইটেম পরিবর্তনের অনুরোধ', 'Item change requests', 'Item change requests'), n_exceptions: L('খোলা ব্যতিক্রম', 'Open exceptions', 'Open exceptions'), n_releases: L('লাল-নিয়ন্ত্রণ মুক্তির অনুরোধ', 'Red-control release requests', 'Red-control release requests'),
  n_emergency: L('জরুরি অনুরোধ', 'Emergency requests', 'Emergency requests'), n_staff_pending: L('অনুমোদনের অপেক্ষায় স্টাফ', 'Staff waiting for approval', 'Staff approval-এর অপেক্ষায়'), n_wastage: L('নষ্টের অনুমোদন', 'Wastage approvals', 'Wastage approvals'),
  n_location_setup: L('নতুন লোকেশনের সেটআপ বাকি', 'New places being set up', 'নতুন Location setup বাকি'), n_settings_drafts: L('সেটিংস শিটের খসড়া', 'Settings sheet drafts', 'Settings sheet drafts'), n_lists: L('তালিকার অনুরোধ ও “অন্যান্য”', 'List requests and Other', 'List requests ও Other'),
  tier_owner: L('মালিক', 'Owner', 'Owner'), tier_head: L('হেড ম্যানেজমেন্ট', 'Head management', 'Head management'), tier_delegate: L('অনুমতিপ্রাপ্ত', 'Delegate', 'Delegate'),
};
const T = (k) => lab(X[k]);
// need rows: server key -> screen.  Order = what usually matters first.
const NEEDS = [['exceptions', 'exceptions'], ['releases', 'releases'], ['emergency', 'emergency'], ['item_requests', 'itemreq'], ['staff_pending', 'staff'], ['wastage', 'stock'], ['location_setup', 'locations'], ['settings_drafts', 'locsheet'], ['lists', 'lists']];
// tiles: g group, k key, route (null = not built yet), cnt = server count key, who: owner | head | grant code(s) that also show it
const TILES = [
  { g: 'places', k: 'locations', route: 'locations', cnt: 'location_setup', head: true, grants: ['location_manage'] },
  { g: 'places', k: 'rollout', route: 'rollout', head: false, grants: ['rollout_manage'] },
  { g: 'places', k: 'locset', route: 'locset', cnt: 'settings_drafts', head: true, grants: ['settings_approve'] },
  { g: 'lists', k: 'lists', route: 'lists', cnt: 'lists', head: false, grants: ['list_manage'] },   // the Lists screen and its queue are decided by the list_manage grant on the server
  { g: 'lists', k: 'items', route: 'items', cnt: 'item_requests', head: false, grants: [] },
  { g: 'people', k: 'staff', route: 'staff', cnt: 'staff_pending', head: false, grants: [] },
  { g: 'people', k: 'matrix', route: 'matrix', head: false, grants: [] },
  { g: 'rules', k: 'rules', route: 'rules', head: false, grants: [] },
  { g: 'rules', k: 'printbooks', route: 'printbooks', head: true, grants: [] },
  { g: 'rules', k: 'settings', route: 'settings', head: false, grants: [] },
  { g: 'rules', k: 'logs', route: 'logs', head: false, grants: [] },
  { g: 'rules', k: 'backup', route: 'backup', head: false, grants: [] },
];
const GROUPS = ['places', 'lists', 'people', 'rules'];

async function who() {
  if (isOwner()) return { tier: 'owner', head: true, g: { location_manage: true, settings_approve: true, list_manage: true, rollout_manage: true } };
  const [head, lm, sa, lg, rm] = await Promise.all(['head_management', 'location_manage', 'settings_approve', 'list_manage', 'rollout_manage'].map((c) => A.hasAnyGrant([c])));
  return { tier: head ? 'head' : (lm || sa || lg || rm) ? 'delegate' : 'none', head, g: { location_manage: lm, settings_approve: sa, list_manage: lg, rollout_manage: rm } };
}
const visible = (tl, w) => w.tier === 'owner' || (w.head && tl.head) || tl.grants.some((g) => w.g[g]);

async function view() {
  shell(T('title'), B.ui.state('loading'), true);
  const w = await who();
  if (w.tier === 'none') return shell(T('title'), B.ui.state('error', T('noacc')), true);
  let cc = {}; try { const r = await sb.rpc('control_counts'); if (r && !r.error && r.data) cc = r.data; } catch (e) { /* phase16 not installed: tiles without counts */ }
  const icon = (k) => (A.ICON && (A.ICON[k] || A.ICON.rulehub)) || '';
  const needs = NEEDS.filter(([key]) => Number(cc[key]) > 0 && (w.tier === 'owner' || ['location_setup', 'settings_drafts', 'lists'].includes(key)));
  const total = needs.reduce((s, [key]) => s + Number(cc[key]), 0);
  const tile = (tl) => {
    const c = tl.cnt ? Number(cc[tl.cnt]) || 0 : 0, soon = !tl.route;
    return soon ? `<div class="tile soon" data-tile="${tl.k}" aria-disabled="true" style="opacity:.6"><div>${icon('rulehub')}</div><span>${esc(T('t_' + tl.k))}</span><span class="chip">${esc(T('soon'))}</span></div>`
      : `<button class="tile" data-tile="${tl.k}" data-act="go" data-v="${tl.route}">${icon(tl.route)}<span>${esc(T('t_' + tl.k))}</span><small class="muted" style="font-weight:400">${esc(T('d_' + tl.k))}</small>${c ? `<span class="badge">${c}</span>` : ''}</button>`;
  };
  // owner extras come from the one registry (ia.js, field cc): screens that were only in the drawer before
  const xt = (g) => (w.tier === 'owner' && B.IA ? B.IA.filter((r) => r.cc === g && r.status === 'live').map((r) => `<button class="tile" data-xtile="${r.route}" data-act="go" data-v="${r.route}">${icon(r.icon)}<span>${esc(B.ia.label(r))}</span></button>`).join('') : '');
  const body = GROUPS.map((g) => { const ts = TILES.filter((x) => x.g === g && visible(x, w)); return ts.length || xt(g) ? `<div class="hsec">${esc(T('g_' + g))}</div><div class="grid" data-group="${g}">${ts.map(tile).join('')}${xt(g)}</div>` : ''; }).join('');
  shell(T('title'), `<div class="row between"><span class="chip info" id="cc_tier">${esc(T('tier_' + w.tier))}</span></div>
    <div class="hsec">${esc(T('needs'))}${total ? `<small>${total}</small>` : ''}</div>
    <div class="card" id="cc_needs" style="padding:4px 12px">${needs.length ? needs.map(([key, route]) => `<button class="hrow mk info" data-act="go" data-v="${route}" data-need="${key}"><span>${esc(T('n_' + key))}</span><span class="n">${Number(cc[key])}</span><span class="cv">›</span></button>`).join('') : `<div class="dash-ok">${esc(T('nothing'))}</div>`}</div>
    ${body}<p class="muted" style="font-size:.8rem;margin-top:12px">${esc(T('note'))}</p>`, true);
}

window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { control: view });
B.control = { TILES, NEEDS, visible };
})();
