/* Islamia BOS · SAMPLE data for the template picker preview (phase 93). Invented items and amounts only: no real names, no real prices, no cost fields. */
(() => {
'use strict';
const T = window.BOS.tpl;
const IT = [{ code: 'S-001', name: 'Sample item A', qty: 2, unit: 'pc', price: 100, amount: 200 }, { code: 'S-002', name: 'Sample item B', qty: 1.5, unit: 'kg', price: 200, amount: 300 }, { code: 'S-003', name: 'Sample item C', qty: 3, unit: 'pc', price: 50, amount: 150 }];
const cust = { name: 'Sample Customer', phone: '01XXXXXXXXX', address: 'Sample address, Sample city' };
const sale = { no: 'INV-0001', date: '2026-01-15', cashier: 'Sample cashier', location: 'Sample branch', customer: cust, items: IT, subtotal: 650, discount: 50, vat: 0, total: 600, paid: 700, change: 100, due: 0 };
const S = {
  pos_receipt: sale,
  sale_return: { no: 'CN-0001', date: '2026-01-16', orig_no: 'INV-0001', reason: 'Sample reason', cashier: 'Sample cashier', customer: cust, items: IT.slice(0, 2), subtotal: 500, vat: 0, refund: 500 },
  order_confirm: { no: 'ORD-0001', date: '2026-01-15', eta: '2026-01-17', pay_method: 'Cash on delivery', customer: cust.name, address: cust.address, items: IT, subtotal: 650, discount: 50, delivery: 60, total: 660, paid: 0, due: 660, note: 'Sample note for the order.' },
  delivery_challan: { no: 'DC-0001', date: '2026-01-15', order_no: 'ORD-0001', vehicle: 'Sample vehicle', customer: cust.name, address: cust.address, items: IT, note: 'Goods received in good condition.' },
  purchase_bill: { no: 'PB-0001', date: '2026-01-10', supplier_bill_no: 'SB-77', location: 'Sample branch', supplier: { name: 'Sample Supplier', phone: '01XXXXXXXXX' }, items: IT.map((i) => Object.assign({}, i, { rate: i.price })), subtotal: 800, discount: 0, vat: 0, total: 800, paid: 300, due: 500, note: 'Sample note.' },
  grn: { no: 'GRN-0001', date: '2026-01-10', po_no: 'PO-0001', location: 'Sample branch', supplier: 'Sample Supplier', items: IT.map((i) => ({ code: i.code, name: i.name, ordered: i.qty + 1, qty: i.qty, unit: i.unit })), note: 'One item short.' },
  stock_transfer: { no: 'TR-0001', date: '2026-01-12', from: 'Sample store 1', to: 'Sample store 2', vehicle: 'Sample vehicle', items: IT, note: 'Handle with care.' },
  stock_count: { date: '2026-01-31', location: 'Sample branch', counter: 'Sample staff', items: IT },
  wastage_sheet: { no: 'WS-0001', date: '2026-01-14', location: 'Sample branch', items: IT.map((i) => ({ code: i.code, name: i.name, qty: 1, unit: i.unit, reason: 'Sample reason' })), note: '' },
  production_slip: { no: 'PR-0001', date: '2026-01-13', product: 'Sample product', batch: 'B-01', yield: '20 pc', items: [{ name: 'Sample ingredient 1', qty: 5, unit: 'kg' }, { name: 'Sample ingredient 2', qty: 2.5, unit: 'kg' }, { name: 'Sample ingredient 3', qty: 1, unit: 'l' }], note: 'Sample note.' },
  recipe_card: { product: 'Sample product', yield: '20 pc', items: [{ name: 'Sample ingredient 1', qty: 5, unit: 'kg' }, { name: 'Sample ingredient 2', qty: 2.5, unit: 'kg' }], steps: ['Mix the ingredients.', 'Cook on a low flame.', 'Cool and cut.'] },
  pay_slip: { employee: 'Sample Employee', emp_no: 'E-001', month: '2026-01', days: 26, sections: [{ title: 'Earnings', rows: [{ label: 'Basic', amount: 10000 }, { label: 'Allowance', amount: 1500 }], total: 11500 }, { title: 'Deductions', rows: [{ label: 'Advance', amount: 1000 }], total: 1000 }], net: 10500 },
  partner_statement: { partner: 'Sample Partner', period: '2026-01-01 to 2026-01-31', opening: 5000, closing: 7000, items: [{ date: '2026-01-05', desc: 'Sample share', debit: 0, credit: 3000, balance: 8000 }, { date: '2026-01-20', desc: 'Sample withdrawal', debit: 1000, credit: 0, balance: 7000 }], note: 'Sample note.' },
  daily_report: { period: '2026-01-15', location: 'Sample branch', sections: [{ title: 'Sales', rows: [{ label: 'Cash sales', amount: 5000 }, { label: 'Card sales', amount: 2000 }], total: 7000 }, { title: 'Expenses', rows: [{ label: 'Sample expense', amount: 800 }], total: 800 }], result: 6200 },
  pnl: { period: '2026-01-01 to 2026-01-31', location: 'All branches', sections: [{ title: 'Income', rows: [{ label: 'Sales', amount: 90000 }], total: 90000 }, { title: 'Expenses', rows: [{ label: 'Rent', amount: 12000 }, { label: 'Wages', amount: 30000 }], total: 42000 }], result: 48000 },
  balance_sheet: { period: 'As of 2026-01-31', location: 'All branches', sections: [{ title: 'Assets', rows: [{ label: 'Cash', amount: 20000 }, { label: 'Stock', amount: 50000 }], total: 70000 }, { title: 'Liabilities', rows: [{ label: 'Payables', amount: 20000 }], total: 20000 }, { title: 'Equity', rows: [{ label: 'Capital', amount: 50000 }], total: 50000 }], result: 70000 },
  msg_invoice: { customer: 'Sample Customer', no: 'INV-0001', date: '2026-01-15', total: 600, paid: 500, due: 100, items: [{ name: 'Sample item A', qty: 2, amount: 200 }, { name: 'Sample item B', qty: 1, amount: 400 }], link: 'https://example.com/i/0001' },
  msg_due: { customer: 'Sample Customer', no: 'INV-0001', date: '2026-01-05', due_date: '2026-01-20', total: 600, paid: 500, due: 100, link: 'https://example.com/i/0001' },
  barcode_label: { name: 'Sample item A', code: '590123412345', unit: 'pc', price: 120, copies: 1 },
  price_tag: { name: 'Sample item A', code: '590123412345', unit: 'pc', price: 120, old_price: 150, copies: 1 },
};
T.sample = (docType) => (S[docType] ? JSON.parse(JSON.stringify(S[docType])) : {});
T.sampleShop = { name: 'Sample Shop', address: 'Sample address', phone: '01XXXXXXXXX', taxId: 'TAX-000000', footer: 'Sample footer line' };
})();
