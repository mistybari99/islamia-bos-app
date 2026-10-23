const _P = require('./_paths');
const PORT = _P.freePort();
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || _P.TESTS_DIR, ROOT = _P.WEB_DIR;
// sample data from the real seed files
const csv = fs.readFileSync(process.env.BOS_REPO_DIR + '/data/items_seed.csv', 'utf8').trim().split('\n').slice(1).map((l, i) => { const c = l.split(','); return { id: 'i' + i, code: 'I-' + String(i + 1).padStart(3, '0'), name_bn: c[0], name_en: null, name_mix: null, category: ({ 'Misty / KG': 'sweet_kg', 'Misty / Piece': 'sweet_pc', 'Doi': 'doi', 'Cake / Pound': 'cake_lb', 'Cake / Piece': 'cake_pc' })[c[1]], category_bn: c[1], unit: (({ 'Misty / KG': 'kg', 'Cake / Pound': 'lb' })[c[1]] || 'pc'), sell_price: +c[2], cost_price: +c[3], is_active: true }; });
const sql = fs.readFileSync(process.env.BOS_REPO_DIR + '/supabase/schema.sql', 'utf8');
const forms0 = [...sql.matchAll(/^\s+\('([^']+)','(\w+)','([^']*)','([^']*)','([^']*)','([^']*)',(\d+)\)/gm)].map((m) => ({ code: m[1], area: m[2], name_bn: m[3], name_mix: m[4], name_en: m[5], version: m[6], sort: +m[7], count_first: true, red_block: true, enabled: true }));
// supabase/schema.sql still carries the OLD printed codes; phase 543 renumbered them in the database (tools/numbering_map.json).
// Apply the same map here (all at once, so no code is mapped twice) so the fixture matches the app. 0-1 is unchanged.
const _fmap = new Map(JSON.parse(fs.readFileSync(process.env.BOS_REPO_DIR + '/tools/numbering_map.json', 'utf8')).form_codes.map((r) => [r.old, r]));
const forms = forms0.map((f) => { const r = _fmap.get(f.code); return r ? { ...f, code: r.new, sort: r.sort, name_bn: r.bn, name_en: r.en, name_mix: r.bn } : f; });
const roles = [...sql.matchAll(/^\s+\('(\w+)','([^']+)','([^']+)','([^']+)',(\d+)\)/gm)].filter((m) => ['owner','management','cash_controller','showroom_manager','salesperson','storekeeper','factory_incharge','purchasing','party_coordinator','carrier','hr'].includes(m[1])).map((m) => ({ code: m[1], name_bn: m[2], name_mix: m[3], name_en: m[4], sort: +m[5], allow_self_approve: false }));
const data = { tables: { forms, roles, items: csv,
  profiles: [{ id: 'u1', staff_id: 'owner1', full_name: 'TestK Uddin', status: 'active', created_at: '2026-10-11' }, { id: 'u2', staff_id: 'testf02', full_name: 'TestF', status: 'pending', created_at: '2026-10-12' }],
  user_roles: [{ user_id: 'u1', role_code: 'owner' }], user_locations: [], locations: [{ id: 1, code: 'main', name_bn: 'ইসলামিয়া মেইন', name_mix: 'ইসলামিয়া Main', name_en: 'Islamia Main', sort: 1 }, { id: 2, code: 'branch2', name_bn: '২য় শাখা', name_mix: '২য় Branch', name_en: '2nd Branch', sort: 2 }], login_failures: [{ staff_id: 'testf02', locked: true }],
  entries: [], location_settings: [{ location_id: 1, key: 'drawer_float', value: 2000 }, { location_id: 1, key: 'imprest', value: 5000 }, { location_id: 1, key: 'expense_max', value: 1000 }, { location_id: 1, key: 'cash_tol', value: 50 }, { location_id: 1, key: 'daytag_1', value: 'লাল' }, { location_id: 1, key: 'fridge1_name', value: 'শো ফ্রিজ' }, { location_id: 1, key: 'fridge1_min', value: 2 }, { location_id: 1, key: 'fridge1_max', value: 8 }],
  role_form_perms: [{ role_code: 'cash_controller', form_code: '03-1', can_view: true, can_enter: true, can_approve: true }], settings: [{ key: 'max_fails', value: 5, label_bn: 'ভুল PIN কতবার হলে লক হবে', label_mix: 'x', label_en: 'Wrong PIN attempts' }, { key: 'x', value: null, label_bn: 'খালি সেটিং', label_mix: 'x', label_en: 'Empty' }],
  item_costs: csv.map((c) => ({ item_id: c.id, cost_price: c.cost_price })), item_changes: [{ id: 1, item_id: 'i0', patch: { sell_price: 300, cost_price: 240 }, note: 'rate up', status: 'pending', requested_by: 'u9', requested_staff: 'buyer3', requested_at: '2026-10-12T05:00:00Z' }, { id: 2, item_id: null, patch: { name_bn: 'নতুন মিষ্টি', sell_price: 50, unit: 'pc' }, status: 'approved', requested_by: 'u9', requested_staff: 'buyer3', requested_at: '2026-10-12T04:00:00Z', decided_staff: 'owner1' }],
  audit_log: [{ id: 1, at: '2026-10-11T08:00:00Z', staff_id: 'owner1', action: 'update', table_name: 'items', record_id: 'abc', detail: { old: { sell_price: 260 }, new: { sell_price: 270 } } }] } };
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { 'content-type': f.endsWith('.js') ? 'text/javascript' : f.endsWith('.css') ? 'text/css' : f.endsWith('.json') ? 'application/json' : 'text/html' }); r.end(b); }); }).listen(PORT);
(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' }).catch(() => chromium.launch());
  const errors = [];
  async function page(init, hash, name, lang) {
    const ctx = await br.newContext({ viewport: { width: 390, height: 800 }, deviceScaleFactor: 2, locale: 'bn-BD' });
    const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push(name + ': ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push(name + ' console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};${init};try{localStorage.setItem('bos_lang','${lang || 'bn'}')}catch(e){}`);
    await p.goto('http://localhost:' + PORT + '/' + (hash || '')); await p.waitForTimeout(500);
    return p;
  }
  let p = await page('window.__SESSION=false', '', 'login'); await p.screenshot({ path: SP + '/s_login.png' });
  await p.click('[data-act=authmode][data-v=register]'); await p.screenshot({ path: SP + '/s_register.png' });
  await p.fill('#a_name', 'Test'); await p.fill('#a_sid', 'ab'); await p.fill('#a_pin', '123456'); await p.click('[data-act=doregister]');
  console.log('bad-id msg:', (await p.textContent('.notice.bad')));
  await p.fill('#a_sid', 'abc1'); await p.fill('#a_pin', '1234'); await p.click('[data-act=doregister]'); console.log('no-session msg:', (await p.textContent('.notice.bad')).slice(0, 60));
  await p.click('[data-act=authmode][data-v=login]'); await p.fill('#a_sid', 'owner1'); await p.fill('#a_pin', '0000'); await p.click('[data-act=dologin]'); console.log('wrong pin:', await p.textContent('.notice.bad'));
  await p.fill('#a_sid', 'owner1'); await p.fill('#a_pin', '1234'); await p.click('[data-act=dologin]'); await p.waitForTimeout(400); console.log('after login h1:', await p.textContent('h1'), '| tiles:', await p.locator('.tile').count());
  for (const [lang, hash, name] of [['bn', '#/home', 'home_bn'], ['mix', '#/home', 'home_mix'], ['en', '#/home', 'home_en'], ['bn', '#/items', 'items'], ['mix', '#/staff', 'staff'], ['bn', '#/matrix', 'matrix'], ['en', '#/rules', 'rules'], ['bn', '#/settings', 'settings'], ['bn', '#/logs', 'logs'], ['bn', '#/backup', 'backup'], ['bn', '#/itemreq', 'itemreq']]) {
    const q = await page('', hash, name, lang); await q.screenshot({ path: `${SP}/s_${name}.png`, fullPage: false });
    if (name === 'items') { await q.fill('#p2_q', 'কালো'); console.log('search কালো ->', await q.locator('.p2-row').count()); await q.click('.p2-row >> nth=0'); await q.waitForTimeout(200); await q.screenshot({ path: SP + '/s_item_sheet.png' }); await q.click('[data-act=p2_save]'); await q.waitForTimeout(300); }
    if (name === 'staff') { await q.click('[data-act=staffopen]'); await q.waitForTimeout(200); await q.screenshot({ path: SP + '/s_staff_sheet.png' }); }
    if (name === 'matrix') { await q.click('[data-act=mrole][data-v=cash_controller]'); await q.click('[data-act=perm][data-f="03-1"][data-k=view]'); await q.waitForTimeout(200); console.log('after view off, 03-1 on-toggles:', await q.locator('.perm:has-text("03-1") .tog.on').count()); }
    await q.context().close();
  }
  const NOCOST = 'window.__OWNER=false;window.__PERMS={ITEMS:{view:true,enter:true,approve:false}}';
  const nc = await page(NOCOST, '#/items', 'nocost', 'bn'); await nc.waitForTimeout(300);
  console.log('no-cost user sees cost numbers? (expect 0 muted prices):', await nc.locator('#i_list .pr .muted').count());
  await nc.click('.p2-row >> nth=0'); await nc.waitForTimeout(200); console.log('no-cost sheet has cost field:', await nc.locator('#p_cost').count(), '| approval notice:', await nc.locator('.notice.warn').count());
  await nc.screenshot({ path: SP + '/s_nocost_sheet.png' });
  await nc.fill('#p_sell', '999'); await nc.click('[data-act=p2_save]'); await nc.waitForTimeout(300); console.log('toast after non-owner save:', await nc.textContent('#toast'));
  const ncr = await page(NOCOST, '#/itemreq', 'nocost_req', 'bn'); console.log('non-approver sees approve buttons:', await ncr.locator('[data-act=itemdecide]').count());
  const pend = await page('window.__PROFILE={id:"u3",staff_id:"new1",full_name:"New",status:"pending",lang:"bn"};window.__OWNER=false', '', 'pending', 'bn'); await pend.screenshot({ path: SP + '/s_pending.png' });
  const staff = await page('window.__OWNER=false', '#/staff', 'nonowner', 'bn'); console.log('non-owner reaching #/staff sees tiles:', await staff.locator('.tile').count(), 'h1:', await staff.textContent('h1'));
  console.log('JS errors:', errors.length ? errors : 'none');
  await br.close(); srv.close();
})().catch((e) => { console.error('SMOKE FAIL', e); process.exit(1); });
