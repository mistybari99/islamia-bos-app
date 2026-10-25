/* Islamia BOS · barcode item labels and price-tag stickers (phase 93). 6 sizes each. Shows the SELLING price only: no cost field exists here.
   data: { name, code (barcode digits), sku, price, old_price, unit, copies } ; shop comes from settings (BOS.tpl.setShop). */
(() => {
'use strict';
const T = window.BOS.tpl, esc = T.esc;
T.addLabels({
  d_blabel: ['Barcode item label', 'বারকোড লেবেল', 'Barcode label'], d_ptag: ['Price tag sticker', 'প্রাইস ট্যাগ স্টিকার', 'Price tag sticker'],
  r_blabel: ['50 x 30 mm on a roll suits most shelves; use the A4 sheet if you print on a normal printer.', 'বেশিরভাগ তাকের জন্য রোলে ৫০ x ৩০ মিমি ভালো; সাধারণ প্রিন্টারে A4 শিট।', 'বেশিরভাগ shelf-এর জন্য roll-এ 50 x 30 mm ভালো; সাধারণ printer-এ A4 sheet।'],
  r_ptag: ['70 x 35 mm shelf tag is easiest to read from a distance; 45 x 30 mm for small boxes.', 'দূর থেকে পড়তে ৭০ x ৩৫ মিমি শেলফ ট্যাগ সবচেয়ে সহজ; ছোট বাক্সে ৪৫ x ৩০ মিমি।', 'দূর থেকে পড়তে 70 x 35 mm shelf tag সহজ; ছোট box-এ 45 x 30 mm।'],
  lb_sale: ['SALE', 'সেল', 'SALE'], lb_was: ['Was', 'আগে', 'Was'], lb_unit: ['per', 'প্রতি', 'per'],
});
const m = (n) => T.money(n, 'en').replace('Tk ', '');                 // number part only; the symbol is added per language below
const price = (d, lg) => (Number.isFinite(Number(d.price)) ? T.money(d.price, lg) : '');
function shopName(o) { const s = Object.assign({}, T.shop, o.shop || {}); return T.has(s.name) ? esc(s.name) : esc(T.lbl('ph_shop', T.lang(o))); }
function bars(d, w, h) { return T.has(d.code) ? T.barcodeSVG(d.code, w, h) : ''; }
function codeTxt(d) { if (!T.has(d.code)) return ''; const b = T.barcodeModules(d.code); return esc(b ? b.text : d.code); }   // when no bars can be drawn the typed number is still printed
const SIZES = {};
// each layout: [w mm, h mm, sheet cols (0 = one per page), css, html(d, lg, o)]
SIZES.barcode_label = {
  label_50x30: [50, 30, 0, '.u{padding:1.5mm 2mm}.sn{font-size:7px;color:#444}.nm{font-size:9px;font-weight:700;line-height:1.1;max-height:2.3em;overflow:hidden}.pr{font-size:13px;font-weight:800;text-align:right}.cd{font:7px monospace;text-align:center}',
    (d, lg, o) => `<div class="sn">${shopName(o)}</div><div class="nm">${esc(d.name)}</div>${bars(d, 44, 10)}<div class="cd">${codeTxt(d)}</div><div class="pr">${price(d, lg)}</div>`],
  label_38x25: [38, 25, 0, '.u{padding:1mm 1.5mm}.nm{font-size:7.5px;font-weight:700;line-height:1.1;max-height:2.2em;overflow:hidden}.pr{font-size:10px;font-weight:800;text-align:right}.cd{font:7px monospace;text-align:center}',
    (d, lg) => `<div class="nm">${esc(d.name)}</div>${bars(d, 34, 8)}<div class="cd">${codeTxt(d)}</div><div class="pr">${price(d, lg)}</div>`],
  label_40x20: [40, 20, 0, '.u{padding:.8mm 1.5mm;text-align:center}.cd{font:7px monospace}.pr{font-size:9px;font-weight:800}',
    (d, lg) => `${bars(d, 36, 9)}<div class="cd">${codeTxt(d)}</div><div class="pr">${price(d, lg)}</div>`],
  label_58x40: [58, 40, 0, '.u{padding:2mm 3mm}.sn{font-size:8px;text-align:center;color:#444}.nm{font-size:12px;font-weight:700;text-align:center;line-height:1.15;max-height:2.4em;overflow:hidden}.pr{font-size:18px;font-weight:800;text-align:center}.cd{font:8px monospace;text-align:center}.un{font-size:8px;text-align:center;color:#444}',
    (d, lg, o) => `<div class="sn">${shopName(o)}</div><div class="nm">${esc(d.name)}</div><div style="text-align:center">${bars(d, 50, 13)}</div><div class="cd">${codeTxt(d)}</div><div class="pr">${price(d, lg)}</div>${T.has(d.unit) ? `<div class="un">${esc(T.lbl('lb_unit', lg))} ${esc(d.unit)}</div>` : ''}`],
  sheet_70x37: [70, 37, 3, '.u{padding:3mm 4mm;border:.2mm dotted #bbb}.sn{font-size:8px;color:#444}.nm{font-size:11px;font-weight:700;line-height:1.15;max-height:2.4em;overflow:hidden}.pr{font-size:15px;font-weight:800;text-align:right}.cd{font:8px monospace;text-align:center}',
    (d, lg, o) => `<div class="sn">${shopName(o)}</div><div class="nm">${esc(d.name)}</div><div style="text-align:center">${bars(d, 56, 11)}</div><div class="cd">${codeTxt(d)}</div><div class="pr">${price(d, lg)}</div>`],
  label_100x50: [100, 50, 0, '.u{padding:4mm 5mm;display:flex;gap:4mm}.a{flex:1}.sn{font-size:10px;color:#444}.nm{font-size:16px;font-weight:700;line-height:1.15;max-height:3.5em;overflow:hidden}.pr{font-size:28px;font-weight:800;text-align:right;align-self:flex-end}.cd{font:10px monospace}',
    (d, lg, o) => `<div class="a"><div class="sn">${shopName(o)}</div><div class="nm">${esc(d.name)}</div>${bars(d, 52, 16)}<div class="cd">${codeTxt(d)}</div></div><div class="pr">${price(d, lg)}</div>`],
};
SIZES.price_tag = {
  tag_45x30: [45, 30, 0, '.u{padding:2mm;text-align:center}.nm{font-size:9px;font-weight:700;max-height:2.3em;overflow:hidden;line-height:1.1}.pr{font-size:20px;font-weight:800;margin-top:1mm}.un{font-size:7px;color:#444}',
    (d, lg) => `<div class="nm">${esc(d.name)}</div><div class="pr">${price(d, lg)}</div>${T.has(d.unit) ? `<div class="un">${esc(T.lbl('lb_unit', lg))} ${esc(d.unit)}</div>` : ''}`],
  tag_60x40: [60, 40, 0, '.u{padding:3mm;text-align:center;border:.4mm solid #000}.sn{font-size:8px;color:#444}.nm{font-size:12px;font-weight:700;max-height:2.4em;overflow:hidden;line-height:1.15}.pr{font-size:26px;font-weight:800;margin-top:2mm}.un{font-size:9px;color:#444}',
    (d, lg, o) => `<div class="sn">${shopName(o)}</div><div class="nm">${esc(d.name)}</div><div class="pr">${price(d, lg)}</div>${T.has(d.unit) ? `<div class="un">${esc(T.lbl('lb_unit', lg))} ${esc(d.unit)}</div>` : ''}`],
  shelf_70x35: [70, 35, 0, '.u{padding:3mm;display:flex;align-items:center;gap:3mm;border-left:3mm solid #0f6b4f}.a{flex:1}.nm{font-size:12px;font-weight:700;line-height:1.15;max-height:3.5em;overflow:hidden}.cd{font:7px monospace;color:#444}.pr{font-size:28px;font-weight:800}',
    (d, lg) => `<div class="a"><div class="nm">${esc(d.name)}</div>${bars(d, 30, 7)}<div class="cd">${codeTxt(d)}</div></div><div class="pr">${price(d, lg)}</div>`],
  hang_30x50: [30, 50, 0, '.u{padding:2mm;text-align:center}.nm{font-size:9px;font-weight:700;max-height:3.4em;overflow:hidden;line-height:1.15}.pr{font-size:17px;font-weight:800;margin:3mm 0}.cd{font:7px monospace}',
    (d, lg) => `<div class="nm">${esc(d.name)}</div><div class="pr">${price(d, lg)}</div>${bars(d, 24, 9)}<div class="cd">${codeTxt(d)}</div>`],
  sale_50x30: [50, 30, 0, '.u{padding:2mm;text-align:center;border:.5mm dashed #b00020}.sl{font-size:9px;font-weight:800;color:#b00020;letter-spacing:.1em}.nm{font-size:9px;font-weight:700;max-height:2.2em;overflow:hidden;line-height:1.1}.ow{font-size:9px;color:#444;text-decoration:line-through}.pr{font-size:19px;font-weight:800}',
    (d, lg) => `<div class="sl">${esc(T.lbl('lb_sale', lg))}</div><div class="nm">${esc(d.name)}</div>${T.has(d.old_price) ? `<div class="ow">${esc(T.lbl('lb_was', lg))} ${T.money(d.old_price, lg)}</div>` : ''}<div class="pr">${price(d, lg)}</div>`],
  sheet_105x50: [105, 49.5, 2, '.u{padding:5mm;text-align:center;border:.2mm dotted #bbb}.sn{font-size:9px;color:#444}.nm{font-size:15px;font-weight:700;line-height:1.15;max-height:2.4em;overflow:hidden}.pr{font-size:32px;font-weight:800;margin-top:3mm}.un{font-size:10px;color:#444}',
    (d, lg, o) => `<div class="sn">${shopName(o)}</div><div class="nm">${esc(d.name)}</div><div class="pr">${price(d, lg)}</div>${T.has(d.unit) ? `<div class="un">${esc(T.lbl('lb_unit', lg))} ${esc(d.unit)}</div>` : ''}`],
};
const NAMES = {
  label_50x30: ['50 x 30 mm roll', '৫০ x ৩০ মিমি রোল', '50 x 30 mm roll'], label_38x25: ['38 x 25 mm small', '৩৮ x ২৫ মিমি ছোট', '38 x 25 mm ছোট'], label_40x20: ['40 x 20 mm barcode only', '৪০ x ২০ মিমি শুধু বারকোড', '40 x 20 mm শুধু barcode'],
  label_58x40: ['58 x 40 mm roll', '৫৮ x ৪০ মিমি রোল', '58 x 40 mm roll'], sheet_70x37: ['A4 sheet 3 x 8', 'A4 শিট ৩ x ৮', 'A4 sheet 3 x 8'], label_100x50: ['100 x 50 mm large', '১০০ x ৫০ মিমি বড়', '100 x 50 mm বড়'],
  tag_45x30: ['45 x 30 mm small tag', '৪৫ x ৩০ মিমি ছোট ট্যাগ', '45 x 30 mm ছোট tag'], tag_60x40: ['60 x 40 mm boxed tag', '৬০ x ৪০ মিমি বক্স ট্যাগ', '60 x 40 mm box tag'], shelf_70x35: ['70 x 35 mm shelf tag', '৭০ x ৩৫ মিমি শেলফ ট্যাগ', '70 x 35 mm shelf tag'],
  hang_30x50: ['30 x 50 mm hanging tag', '৩০ x ৫০ মিমি ঝোলানো ট্যাগ', '30 x 50 mm hanging tag'], sale_50x30: ['50 x 30 mm sale tag', '৫০ x ৩০ মিমি সেল ট্যাগ', '50 x 30 mm sale tag'], sheet_105x50: ['A4 sheet 2 x 6', 'A4 শিট ২ x ৬', 'A4 sheet 2 x 6'],
};
function labelRender(group) {
  return (tp, d, o) => {
    const [w, h, cols, css, fn] = SIZES[group][tp.id], lg = T.lang(o), copies = Math.max(1, Math.min(500, Math.floor(T.num(d.copies)) || 1));
    const unit = `<div class="u">${fn(d, lg, o)}</div>`;
    const sheet = cols > 0, rows = sheet ? Math.floor(297 / h) : 0, per = sheet ? cols * rows : 1;
    const pageCss = sheet ? '@page{size:A4;margin:0}' : `@page{size:${w}mm ${h}mm;margin:0}`;
    const P = '.tl-' + tp.id;
    const base = `${P}{font:10px system-ui,"Noto Sans Bengali",sans-serif;color:#000;background:#fff;box-sizing:border-box}${P} *{box-sizing:border-box}${P} .c{width:${w}mm;height:${h}mm;overflow:hidden;${sheet ? '' : 'page-break-after:always;break-after:page;'}}`
      + `${P} .g{display:grid;grid-template-columns:repeat(${cols || 1},${w}mm);width:${w * (cols || 1)}mm}${P} .c .u{height:100%}${P} .tp-bc{display:block;margin:0 auto}${P} .a{min-width:0}${P} .u,${P} .nm,${P} .pr,${P} .a,${P} .cd{overflow-wrap:anywhere;word-break:break-word;min-width:0}`;
    const mk = (k) => { let c = ''; for (let i = 0; i < k; i++) c += `<div class="c">${unit}</div>`; return c; };
    if (!sheet) return `<style>${pageCss}${base}${css.replace(/(^|\})\./g, '$1' + P + ' .')}</style><div class="tl tl-${esc(tp.id)}" data-doc="${esc(group)}" data-tpl="${esc(tp.id)}">${mk(copies)}</div>`;
    let pages = '', left = copies; while (left > 0) { pages += `<div class="g">${mk(Math.min(left, per))}</div>`; left -= per; }   // as many A4 pages as the copies need
    return `<style>${pageCss}${base}${P} .g{page-break-after:always;break-after:page}${P} .g:last-child{page-break-after:auto;break-after:auto}${css.replace(/(^|\})\./g, '$1' + P + ' .')}</style><div class="tl tl-${esc(tp.id)}" data-doc="${esc(group)}" data-tpl="${esc(tp.id)}">${pages}</div>`;
  };
}
const tpls = (g) => Object.keys(SIZES[g]).map((id) => ({ id, name: NAMES[id], page: 'label', look: id }));
T.defineDoc({ id: 'barcode_label', kind: 'label', group: 'grp_label', title: 'd_blabel', rec: ['label_50x30', 'r_blabel'], templates: tpls('barcode_label'), render: labelRender('barcode_label') });
T.defineDoc({ id: 'price_tag', kind: 'label', group: 'grp_label', title: 'd_ptag', rec: ['shelf_70x35', 'r_ptag'], templates: tpls('price_tag'), render: labelRender('price_tag') });
void m;
T.finishLabels();
})();
