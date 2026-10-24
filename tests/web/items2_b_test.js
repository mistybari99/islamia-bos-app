// items2_b_test.js = items2_test.js with the upload assertion adapted: step Img (bos103) uploads a ~160px copy at <path>.t.jpg right after the photo. Everything else is identical.
// Products v2 (items2.js) + supplier picker (entry.js SUP field). Run: node items2_test.js <scratchpad>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const _P = require('./_paths');
const SP = process.argv[2] || _P.TESTS_DIR, ROOT = _P.WEB_DIR, PORT = _P.freePort();
const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); const dataFn = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;'); const base = dataFn(fs);
const R = (key, kind, def, extra = {}) => ({ key, module: 'settings', kind, value: null, default_value: def, label_bn: key, label_en: key, label_mix: key, sort: 1, ...extra });
function mkData(o = {}) {
  const data = JSON.parse(JSON.stringify(base)); const T = data.tables;
  T.rules = [R('vat_on', 'switch', false, o.vat ? { value: true } : {}), R('barcode_camera_on', 'switch', false), R('barcode_device_on', 'switch', false, o.dev ? { value: true } : {}), R('ui_noperm_mode', 'choice', 'lock')];
  T.option_lists = [{ list_code: 'units', value_code: 'kg', label_bn: 'কেজি', label_en: 'kg', sort: 1, active: true }, { list_code: 'units', value_code: 'piece', label_bn: 'পিস', label_en: 'piece', sort: 2, active: true },
    { list_code: 'units', value_code: 'box', label_bn: 'বক্স', label_en: 'box', sort: 3, active: true }, { list_code: 'units', value_code: 'gram', label_bn: 'গ্রাম', label_en: 'gram', sort: 4, active: true },
    { list_code: 'item_categories', value_code: 'packed', label_bn: 'প্যাকেটজাত', label_en: 'Packed', sort: 1, active: true }, { list_code: 'item_subcategories', value_code: 'syrup', label_bn: 'সিরাপ', label_en: 'Syrup', sort: 1, active: true }];
  const it = T.items; Object.assign(it[0], { barcode: '8901', min_stock: 5, tracked: true, wholesale_price: 240, source: 'made', sub_category: 'syrup', images: ['ITEMS/1/x.jpg'], sell_units: ['kg'], base_unit: 'kg' });
  Object.assign(it[1], { is_active: false, source: 'bought' }); Object.assign(it[2], { source: 'bought', barcode: '8902' });
  T.unit_conversions = [{ id: 1, item_id: null, from_unit: 'kg', to_unit: 'gram', factor: 1000, active: true }, { id: 2, item_id: it[0].id, from_unit: 'box', to_unit: 'kg', factor: 2, active: true }];
  T.suppliers = [{ id: 'sp1', name: 'Dudh Ghor', type_code: 'milk', active: true }, { id: 'sp2', name: 'Chini Mill', type_code: 'sugar', active: true }];
  return data;
}
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
const GIF = 'data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==';
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; window.__CALLS = []; window.__UP = []; const T = window.__DATA.tables;
 c.rpc = async (fn, args) => { window.__CALLS.push([fn, JSON.parse(JSON.stringify(args || {}))]);
  if (fn === 'supplier_pick') return { data: T.suppliers.filter((s) => s.active).map((s) => ({ id: s.id, name: s.name, type_code: s.type_code })), error: null };
  if (fn === 'has_grant') return { data: window.__GRANT !== false, error: null };
  if (fn === 'save_supplier') { const id = 'sp' + (T.suppliers.length + 1); T.suppliers.push({ id, active: true, ...args.p_patch }); return { data: id, error: null }; }
  if (fn === 'submit_item_change') { if (window.__DUP) return { data: null, error: { message: 'duplicate key value violates unique constraint items_barcode_uq' } }; return { data: { status: window.__OWNER === false ? 'pending' : 'applied' }, error: null }; }
  return rpc(fn, args); };
 c.storage = { from: () => ({ upload: async (p, b) => { window.__UP.push([p, b.size, b.type]); return { error: null }; },
   createSignedUrls: async (ps) => ({ data: ps.map((p) => ({ path: p, signedUrl: '${GIF}' })), error: null }), createSignedUrl: async () => ({ data: { signedUrl: '${GIF}' }, error: null }) }) };
 return c; }; })();`;
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(mkData(o))};${o.init || ''};try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto('http://localhost:' + PORT + '/' + hash); await p.waitForTimeout(900); return p;
  }
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);
  const calls = (p, fn) => p.evaluate((f) => window.__CALLS.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const go = async (p, h) => { await p.evaluate((x) => { location.hash = x; }, h); await p.waitForTimeout(500); };

  // ---------- owner list ----------
  let p = await open({}, '#/items');
  const n = await p.locator('.p2-row').count(); log('rows:', n); ok(n > 20 && n <= 50, 'first page of rows');
  ok((await p.textContent('#p2_count')).startsWith(String(base.tables.items.length)), 'count line');
  ok(/Cost/.test(await p.textContent('#p2_list')), 'owner sees cost on rows'); ok(/Wholesale/.test(await p.textContent('#p2_list')), 'wholesale on row');
  ok(await p.locator('.p2-row .chip.info').count() >= 1, 'tracked chip'); ok(await p.locator('.p2-row .chip.bad').count() >= 1, 'inactive chip');
  await p.screenshot({ path: SP + '/it_list.png' }); await noOverflow(p, 'list');
  await p.click('#p2_more').catch(() => {}); await p.waitForTimeout(200); ok(await p.locator('.p2-row').count() > n, 'show more');
  await p.fill('#p2_q', '8901'); await p.waitForTimeout(350); ok(await p.locator('.p2-row').count() === 1, 'search by barcode'); await p.fill('#p2_q', '');
  await p.waitForTimeout(350);
  // filter sheet
  await p.click('#p2_fb'); await p.waitForTimeout(250); await p.screenshot({ path: SP + '/it_filter.png' }); await noOverflow(p, 'filter sheet');
  await p.selectOption('#ff_src', 'bought'); await p.click('[data-act=p2_apply]'); await p.waitForTimeout(250);
  ok(await p.locator('.p2-row').count() === 2, 'source=bought -> 2 rows'); ok(await p.locator('#p2_chips .chip').count() === 1, 'chip shown'); ok((await p.textContent('#p2_fb .cnt')) === '1', 'filter count badge');
  await p.click('#p2_chips .chip'); await p.waitForTimeout(200); ok(await p.locator('#p2_chips .chip').count() === 0, 'chip removes filter');
  await p.click('#p2_fb'); await p.waitForTimeout(200); await p.click('#ff_low'); await p.click('[data-act=p2_apply]'); await p.waitForTimeout(200); ok(await p.locator('.p2-row').count() === 1, 'low-alert filter -> 1');
  await p.click('#p2_fb'); await p.waitForTimeout(200); await p.click('[data-act=p2_reset]'); await p.waitForTimeout(200);
  await p.click('#p2_fb'); await p.waitForTimeout(200); await p.selectOption('#ff_act', 'no'); await p.selectOption('#ff_trk', 'no'); await p.click('[data-act=p2_apply]'); await p.waitForTimeout(200); ok(await p.locator('.p2-row').count() === 1, 'inactive+untracked -> 1');
  await p.click('#p2_fb'); await p.waitForTimeout(200); await p.click('[data-act=p2_reset]'); await p.waitForTimeout(200);
  await p.click('#p2_fb'); await p.waitForTimeout(200); await p.selectOption('#ff_sub', 'syrup'); await p.selectOption('#ff_cat', { index: 1 }); await p.click('[data-act=p2_apply]'); await p.waitForTimeout(200); log('cat+sub rows:', await p.locator('.p2-row').count());
  await p.click('#p2_fb'); await p.waitForTimeout(200); await p.click('[data-act=p2_reset]'); await p.waitForTimeout(200);

  // ---------- add product ----------
  await p.click('[data-act=itemnew]'); await p.waitForTimeout(700); ok(/#\/items\/new/.test(await p.evaluate(() => location.hash)), 'new route');
  ok(await p.locator('#p_vat, [data-grp=vat]').count() === 0, 'VAT hidden while vat_on false'); ok(await p.locator('#p_cost').count() === 1, 'owner sees cost field');
  ok(!(await p.locator('#p_adv').getAttribute('open')) && await p.locator('#p_adv[open]').count() === 0, 'advance closed by default'); ok(await p.locator('#p_wh_w').isHidden(), 'wholesale hidden until on');
  await p.screenshot({ path: SP + '/it_add.png' }); await noOverflow(p, 'add form');
  await p.click('#p_adv summary'); await p.waitForTimeout(200); await p.screenshot({ path: SP + '/it_add_adv.png', fullPage: true }); await noOverflow(p, 'advance open');
  await p.click('[data-act=itemnew]').catch(() => {});
  await p.fill('#p_bn', 'টেস্ট ক্যান'); await p.fill('#p_en', 'Test can'); await p.fill('#p_sell', '১২০'); await p.fill('#p_cost', '80');
  await p.click('#p_wh_on'); ok(await p.locator('#p_wh_w').isVisible(), 'wholesale shows'); await p.fill('#p_whs', '100');
  await p.click('#p_low_on'); await p.fill('#p_min', '3'); await p.click('#p_trk');
  await p.click('[data-grp=src] [data-v=bought]'); await p.click('#p_su [data-su=box]'); await p.selectOption('#p_base', 'piece'); await p.selectOption('#p_cat', 'packed'); await p.selectOption('#p_sub', 'syrup');
  await p.setInputFiles('#p_file', { name: 'a.png', mimeType: 'image/png', buffer: PNG }); await p.waitForTimeout(700);
  ok(await p.locator('#p_imgs img').count() === 1, 'image thumb'); const up = await p.evaluate(() => window.__UP); ok(up.length === 2 && /^ITEMS\/\d+\/.+\.jpg$/.test(up[0][0]) && up[0][2] === 'image/jpeg' && up[1][0] === up[0][0] + '.t.jpg' && up[1][2] === 'image/jpeg' && up[1][1] <= up[0][1], 'upload path ITEMS/<loc>/*.jpg jpeg + small copy path.t.jpg (step Img)');
  for (let i = 0; i < 5; i++) await p.setInputFiles('#p_file', { name: 'a.png', mimeType: 'image/png', buffer: PNG }).catch(() => {}), await p.waitForTimeout(250);
  ok(await p.locator('#p_imgs img').count() === 5 && await p.locator('#p_file').count() === 0, 'max 5 images, add button gone');
  await p.click('#p_imgs .mini >> nth=0'); await p.waitForTimeout(150); ok(await p.locator('#p_imgs img').count() === 4, 'image removed');
  await p.fill('#p_bc', '8901'); await p.waitForTimeout(100); ok(/already used/.test(await p.textContent('#p_bc_h')), 'duplicate barcode hint');
  await p.click('[data-act=p2_save]'); await p.waitForTimeout(300); ok((await calls(p, 'submit_item_change')).length === 0, 'duplicate barcode blocks save');
  await p.fill('#p_bc', '8909001'); await p.click('[data-act=p2_save]'); await p.waitForTimeout(600);
  let sc = await calls(p, 'submit_item_change'); ok(sc.length === 1, 'one submit'); const pt = sc[0] ? sc[0].p_patch : {}; log('new patch:', JSON.stringify(pt));
  ok(pt.name_bn === 'টেস্ট ক্যান' && pt.sell_price === 120 && pt.cost_price === 80 && pt.wholesale_price === 100 && pt.min_stock === 3 && pt.tracked === true && pt.source === 'bought' && pt.barcode === '8909001', 'new patch core fields');
  ok(JSON.stringify(pt.sell_units) === '["box"]' && pt.base_unit === 'piece' && pt.category === 'packed' && pt.sub_category === 'syrup' && pt.images.length === 4, 'new patch advance fields'); ok(!('vat_applicable' in pt), 'no vat key while off');
  ok(sc[0] && sc[0].p_item === null, 'new item has null id'); ok(/#\/items$/.test(await p.evaluate(() => location.hash)), 'back to the list after save');

  // ---------- edit ----------
  await p.fill('#p2_q', '8901'); await p.waitForTimeout(350); await p.click('.p2-row'); await p.waitForTimeout(700);
  ok(/items\/edit\//.test(await p.evaluate(() => location.hash)), 'edit route'); await p.click('#p_adv summary'); ok((await p.inputValue('#p_whs')) === '240', 'wholesale prefilled'); ok(await p.locator('#p_min').isVisible(), 'min stock shown'); ok((await p.inputValue('#p_bc')) === '8901', 'barcode prefilled');
  ok(await p.locator('#p_imgs img').count() === 1, 'existing image'); ok(/1 box = 2 kg/.test(await p.textContent('.card:has-text("Conversions")')) , 'item conversion shown'); ok(await p.locator('a[href^="#/settings2/units/"]').count() === 1, 'owner conversion link');
  await p.screenshot({ path: SP + '/it_edit.png', fullPage: true }); await noOverflow(p, 'edit form');
  await p.click('[data-act=p2_save]'); await p.waitForTimeout(400); ok((await calls(p, 'submit_item_change')).length === 1, 'no change -> no submit');
  await p.click('.p2-row'); await p.waitForTimeout(600); await p.click('#p_adv summary'); await p.fill('#p_sell', '555'); await p.click('#p_low_on'); await p.click('[data-act=p2_save]'); await p.waitForTimeout(600);
  sc = await calls(p, 'submit_item_change'); const ep = sc[1] ? sc[1].p_patch : {}; log('edit patch:', JSON.stringify(ep)); ok(ep.sell_price === 555 && ep.min_stock === null && Object.keys(ep).length === 2, 'edit patch has only the changes'); ok(sc[1] && sc[1].p_item === base.tables.items[0].id, 'edit item id');
  // conversion link opens the right scope
  await go(p, '#/settings2/units/' + base.tables.items[0].id); ok((await p.inputValue('#u_scope')) === base.tables.items[0].id, 'units page opens at the item scope');
  // old routes
  await go(p, '#/itemreq'); ok(await p.locator('.card').count() >= 1, 'itemreq still works'); await go(p, '#/products'); ok(await p.locator('.p2-row').count() > 0, 'products alias');
  await p.evaluate(() => window.BOS_APP.H.itemnew()); await p.waitForTimeout(500); ok(/items\/new/.test(await p.evaluate(() => location.hash)), 'old H.itemnew redirects (POS new item)');
  // 3 languages
  for (const l of ['bn', 'mix']) { await p.evaluate((x) => localStorage.setItem('bos_lang', x), l); await p.reload(); await p.waitForTimeout(800); ok((await p.textContent('h1')).length > 2, 'title ' + l); }
  await p.screenshot({ path: SP + '/it_add_mix.png' });
  await p.close();

  // ---------- VAT rule on + device scan from the form ----------
  p = await open({ vat: true, dev: true }, '#/items/new');
  ok(await p.locator('[data-grp=vat]').count() === 1, 'VAT shown when vat_on'); await p.click('#p_adv summary');
  await p.click('[data-grp=vat] [data-v=yes]'); await p.fill('#p_bn', 'ভ্যাট পণ্য'); await p.fill('#p_sell', '10');
  await p.click('[data-act=p2_scan]'); await p.waitForTimeout(300); ok(await p.locator('#bc_in').isVisible(), 'device scan input appears (only device on)');
  await p.keyboard.type('7770001'); await p.keyboard.press('Enter'); await p.waitForTimeout(300); ok((await p.inputValue('#p_bc')) === '7770001', 'scanned code lands in barcode field'); ok(await p.locator('#bcOverlay').count() === 0, 'overlay closed');
  await p.click('[data-act=p2_save]'); await p.waitForTimeout(500); const vp = (await calls(p, 'submit_item_change'))[0].p_patch; ok(vp.vat_applicable === true && vp.barcode === '7770001', 'vat + barcode in patch');
  await p.close();

  // ---------- non-owner: approval path, no cost ----------
  p = await open({ init: 'window.__OWNER=false;window.__PERMS={ITEMS:{view:true,enter:true,approve:false}};window.__PROFILE={id:"u3",staff_id:"test_user_a02",full_name:"test_user_a",status:"active",lang:"en"};' }, '#/items');
  ok(!/Cost/.test(await p.textContent('#p2_list')), 'no cost on rows without ITEM_COST'); ok(/Wholesale/.test(await p.textContent('#p2_list')), 'wholesale still visible');
  await p.click('.p2-row'); await p.waitForTimeout(600); ok(await p.locator('#p_cost').count() === 0, 'no cost field'); ok(await p.locator('.notice.warn').count() >= 1, 'needs-approval notice'); ok(await p.locator('[data-act=p2_newbox]').count() === 0, 'no add-category for non-owner');
  ok(await p.locator('a[href^="#/settings2/units/"]').count() === 0, 'no conversion edit link for non-owner'); await p.fill('#p_sell', '999'); await p.click('[data-act=p2_save]'); await p.waitForTimeout(500);
  ok(/approval/i.test(await p.textContent('#toast')), 'sent for approval toast'); const np = (await calls(p, 'submit_item_change'))[0].p_patch; ok(!('cost_price' in np) && np.sell_price === 999, 'non-owner patch has no cost');
  await p.close();
  // read-only role: rows are not clickable
  p = await open({ init: 'window.__OWNER=false;window.__PERMS={ITEMS:{view:true,enter:false}};window.__PROFILE={id:"u3",staff_id:"test_user_a02",full_name:"test_user_a",status:"active",lang:"en"};' }, '#/items');
  ok(await p.locator('[data-act=itemnew]').count() === 0 && await p.locator('.p2-row[data-act]').count() === 0, 'view-only: no add, rows not editable'); await p.close();

  // ---------- supplier picker (goods received 13-1 / quotation 29-1) ----------
  p = await open({}, '#/entry/new/13-1/1');
  ok(await p.locator('input[data-sup]').count() >= 1, 'supplier field is a picker'); ok(await p.locator('#dl_sup option').count() === 2, 'datalist has 2 suppliers');
  const sup = p.locator('input[data-sup]').first(); await sup.fill('dudh ghor'); await sup.dispatchEvent('change'); await p.waitForTimeout(200); ok(/Listed supplier/.test(await p.textContent('.supwrap + .hint')), 'listed supplier hint');
  await p.screenshot({ path: SP + '/it_supplier.png' }); await noOverflow(p, 'supplier form');
  ok(await p.locator('.supnew').count() >= 1, 'add-new for supplier_manage');
  await p.click('.supnew >> nth=0'); await p.waitForTimeout(250); await p.fill('#sn_name', 'Nobo Supplier'); await p.fill('#sn_mob', '01712345678'); await p.click('[data-act=sup_save]'); await p.waitForTimeout(500);
  const ss = await calls(p, 'save_supplier'); ok(ss.length === 1 && ss[0].p_id === null && ss[0].p_patch.name === 'Nobo Supplier' && ss[0].p_patch.mobile === '01712345678', 'save_supplier called'); ok((await p.locator('input[data-sup]').first().inputValue()) === 'Nobo Supplier', 'new supplier filled in');
  const saveBtn = p.locator('[data-act=savedraft], [data-act=save]').first(); log('save btn count', await p.locator('[data-act=savedraft], [data-act=save]').count());
  await p.close();
  p = await open({}, '#/entry/new/13-1/1'); const s2 = p.locator('input[data-sup]').first(); await s2.fill('Dudh Ghor'); await s2.dispatchEvent('change');
  const acts = await p.locator('[data-act]').evaluateAll((els) => [...new Set(els.map((e) => e.dataset.act))].filter((x) => /save|draft|submit/i.test(x))); log('entry actions:', acts.join(','));
  if (acts.length) { await p.click(`[data-act=${acts[0]}]`); await p.waitForTimeout(500); const sv = await p.evaluate(() => window.__SAVED); log('saved supplier:', sv && JSON.stringify([sv.data.supplier, sv.data.supplier_id])); ok(sv && sv.data.supplier === 'Dudh Ghor' && sv.data.supplier_id === 'sp1', 'stored name + supplier_id'); }
  await s2.fill('Random Shop'); await s2.dispatchEvent('change'); await p.waitForTimeout(150); ok(/Not in the list/.test(await p.textContent('.supwrap + .hint')), 'free text keeps working');
  await p.close();
  // without supplier_manage: no add button; unknown rpc: free text only
  p = await open({ init: 'window.__GRANT=false;window.__OWNER=false;window.__PERMS={"13-1":{view:true,enter:true}};window.__PROFILE={id:"u3",staff_id:"test_user_a02",full_name:"test_user_a",status:"active",lang:"en"};' }, '#/entry/new/13-1/1');
  ok(await p.locator('.supnew').count() === 0, 'no add-new without supplier_manage'); ok(await p.locator('input[data-sup]').count() >= 1, 'picker still shown');
  await p.close();

  log('errors:', errors.length ? [...new Set(errors)] : 'none'); log('assert failures:', bad); await br.close(); srv.close();
} catch (e) { console.log('TEST CRASH:', e.message.split('\n').slice(0,6).join(' | ')); process.exit(1); } })();
