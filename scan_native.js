/* Islamia BOS · native bridge for the Android wrapper (X5). OFF and inert in the PWA: available() is false, every call returns
   { error: 'not_native' }. Inside the Capacitor wrapper (android/, see docs/ANDROID_WRAPPER.md) it calls the ML Kit plugins that the
   wrapper installs. web/scan_items.js picks this bridge automatically when available() is true (caps().native).
   Plugin names and methods (BarcodeScanner.scan, TextRecognition.processImage, ImageLabeling.processImage) are taken from the published
   @capacitor-mlkit/* 8.2.1 type definitions; they are NOT run in this package (no APK was built). */
(() => {
'use strict';
function cap() { return (typeof window !== 'undefined' && window.Capacitor) || null; }
function plugin(name) { const c = cap(); return c && c.Plugins ? c.Plugins[name] || null : null; }
function available() { const c = cap(); try { return !!(c && typeof c.isNativePlatform === 'function' && c.isNativePlatform()); } catch (e) { return false; } }

// barcode / QR: one shot scan with the ML Kit barcode scanner (camera UI owned by the plugin)
async function barcodeScan(opts) {
  if (!available()) return { error: 'not_native' };
  const p = plugin('BarcodeScanner'); if (!p || typeof p.scan !== 'function') return { error: 'plugin_missing' };
  try { const r = await p.scan({ formats: (opts && opts.formats) || ['EAN_13', 'EAN_8', 'CODE_128', 'CODE_39', 'QR_CODE', 'UPC_A'] }); return { value: r && r.barcodes && r.barcodes[0] ? r.barcodes[0].rawValue : null }; }
  catch (e) { return { error: 'failed', message: String(e && e.message || e) }; }
}
// label text: ML Kit text recognition on an image file that the wrapper can read (path from the Filesystem plugin)
async function textFromImage(path) {
  if (!available()) return { error: 'not_native' };
  const p = plugin('TextRecognition'); if (!p || typeof p.processImage !== 'function') return { error: 'plugin_missing' };
  try { const r = await p.processImage({ path: String(path || '') }); return { text: r && r.text ? String(r.text) : '' }; }
  catch (e) { return { error: 'failed', message: String(e && e.message || e) }; }
}
// image labels: ML Kit image labeling (generic labels, e.g. "Sugar", "Cake"). Suggestions only; never saved.
async function labelsFromImage(path) {
  if (!available()) return { error: 'not_native' };
  const p = plugin('ImageLabeling'); if (!p || typeof p.processImage !== 'function') return { error: 'plugin_missing' };
  try { const r = await p.processImage({ path: String(path || ''), confidenceThreshold: 0.6 }); return { labels: Array.isArray(r && r.labels) ? r.labels.map((x) => ({ text: String(x.text || ''), confidence: Number(x.confidence) || 0 })) : [] }; }
  catch (e) { return { error: 'failed', message: String(e && e.message || e) }; }
}

const BRIDGE = { available, barcodeScan, textFromImage, labelsFromImage, version: 1 };
if (typeof window !== 'undefined') window.BOS_SCAN_NATIVE = BRIDGE;
if (typeof module !== 'undefined' && module.exports) module.exports = BRIDGE;
})();
