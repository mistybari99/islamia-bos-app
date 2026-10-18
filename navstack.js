/* Islamia BOS · Navigation stack: Back returns to the exact screen the person came from.
   Additive: hash routes are unchanged and every page stays reachable. Loaded before app.js.
   Rules: every hash change pushes one entry; going back (the Back button, the browser back, or BOS_NAVSTACK.back)
   drops the top entry; no duplicates in a row; the stack is kept for this browser tab (sessionStorage), 30 entries at most.
   "main" = the nearest top-level screen (a route with no "/") the person entered the current deep chain from. */
(() => {
'use strict';
const KEY = 'bos_nav_stack', MAX = 30;

const keyOf = (h) => (h || '').replace(/^#\/?/, '') || 'home';   // '' and '#/' are the home screen
const isTop = (k) => k.split('?')[0].indexOf('/') < 0;            // 'home', 'pos', 'accounts' are top-level; 'accounts/journal' is deep

function load() {
  try { const a = JSON.parse(sessionStorage.getItem(KEY) || '[]'); return Array.isArray(a) ? a.filter((x) => typeof x === 'string').slice(-MAX) : []; }
  catch (e) { return []; }   // storage blocked (private mode): the stack lives only in memory
}
function save() { try { sessionStorage.setItem(KEY, JSON.stringify(stack)); } catch (e) { /* private mode */ } }

let stack = load();

// one entry per screen: a repeat of the top is a refresh, the entry just below the top is a back
function onRoute() {
  const k = keyOf(location.hash), top = stack[stack.length - 1];
  if (k === top) { /* same screen again: nothing to add */ }
  else if (stack.length >= 2 && stack[stack.length - 2] === k) stack.pop();
  else stack.push(k);
  if (stack.length > MAX) stack.splice(0, stack.length - MAX);
  save();
}

// go to a stack entry: drop the entries above it, then move there (the hash change finds the entry already on top)
function goTo(index) {
  const k = stack[index];
  if (k === undefined) return goHome();
  stack.length = index + 1; save();
  if (keyOf(location.hash) !== k) location.hash = '#/' + k;
  return true;
}
function goHome() { if (keyOf(location.hash) !== 'home') location.hash = '#/home'; return false; }

// Back: n steps (any n >= 1; the design decides how many are offered). With no history it goes to Home.
function back(n) {
  const steps = Math.max(1, Math.floor(Number(n) || 1));
  const top = stack.length - 1;
  if (top < 1) return goHome();
  return goTo(Math.max(0, top - steps));
}

// main: the nearest top-level screen below the current one (or the current one when it is deep)
function main() {
  let i = stack.length - 1;
  if (i >= 0 && isTop(stack[i])) i -= 1;   // on a top-level screen already: the main point is the one before it
  for (; i >= 0; i -= 1) if (isTop(stack[i])) return goTo(i);
  return goHome();
}

window.addEventListener('hashchange', onRoute);
if (!stack.length) onRoute();   // first screen of this tab

window.BOS_NAVSTACK = {
  back,
  main,
  peek: () => stack.slice(),                       // read-only copy, for tests and the design phase
  depth: () => stack.length,
};
})();
