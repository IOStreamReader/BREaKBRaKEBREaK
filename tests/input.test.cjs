const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
function target() {
  const listeners = {};
  return {classList: {contains: () => true},
    addEventListener(name, fn) { (listeners[name] ??= []).push(fn); },
    fire(name, event = {}) { for (const fn of listeners[name] ?? []) fn({preventDefault() {}, ...event}); }
  };
}
const messages = [];
const win = target(), app = target(), brake = target(), body = target();
const ctx = {...win, console, document: {body, activeElement: body,
  getElementById: id => ({app, brakeBtn: brake}[id] ?? target())},
  BreakGame: {isPlaying: () => true, diagnostics: () => ({phase: 'braking'})},
  webkit: {messageHandlers: {native: {async postMessage(message) {
    messages.push(message);
    return message.action === 'mode' ? {mode: message.mode} : {ok: true};
  }}}}
};
ctx.window = ctx;
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../web/native.js'), 'utf8'), ctx);
ctx.BreakControl.bind();
const control = ctx.BreakControl;
(async () => {
  ctx.BreakNative.brakeSnap();
  assert.equal(messages.filter(m => m.action === 'brakeSnap').length, 0);
  ctx.BreakNative.setSession(true);
  ctx.BreakNative.brakeSnap();
  assert.equal(messages.filter(m => m.action === 'brakeSnap').length, 1);
  ctx.BreakPressure.setPaused(true);
  ctx.BreakNative.brakeSnap();
  assert.equal(messages.filter(m => m.action === 'brakeSnap').length, 1, 'Paused games cannot vibrate');
  ctx.BreakPressure.setPaused(false);
  app.fire('pointerdown', {pointerType: 'mouse', button: 0});
  ctx.fire('keydown', {code: 'Space'});
  assert.equal(control.sample(), 0, 'Mouse and Space do not drive pressure mode');
  await control.setMode('keyboard', true);
  ctx.BreakNative.brakeSnap();
  assert.equal(messages.filter(m => m.action === 'brakeSnap').length, 1, 'Keyboard mode cannot vibrate');
  ctx.BreakNative.setSession(true);
  ctx.fire('keydown', {code: 'Space', repeat: false});
  assert.equal(control.sample(), 1);
  app.fire('pointerdown', {pointerType: 'mouse', button: 0});
  ctx.fire('keyup', {code: 'Space'});
  assert.equal(control.sample(), 1, 'Releasing Space does not release a held mouse');
  ctx.fire('pointerup');
  assert.equal(control.sample(), 0);
  brake.fire('pointerdown', {pointerType: 'mouse', button: 0});
  assert.equal(control.sample(), 1, 'The brake button restores its original click control');
  ctx.BreakPressure.receive({value: 0, peak: 0, gesture: 1, mouseDown: false});
  assert.equal(control.sample(), 0, 'Native outside-window mouse release clears fallback input');
  app.fire('pointerdown', {pointerType: 'touch', button: 0});
  app.fire('pointerdown', {pointerType: 'mouse', button: 2});
  ctx.fire('keydown', {code: 'Space', target: {matches: () => true}});
  assert.equal(control.sample(), 0, 'Touch, right-click and nickname typing do not brake');
  ctx.fire('keydown', {code: 'Space'});
  assert.equal(control.sample(), 1);
  ctx.BreakPressure.setPaused(true); ctx.BreakPressure.setPaused(false);
  ctx.fire('keydown', {code: 'Space', repeat: true});
  assert.equal(control.sample(), 0, 'Held-key repeats cannot restart a brake after focus loss');
  ctx.fire('keydown', {code: 'Space', repeat: false});
  assert.equal(control.sample(), 1);
  ctx.fire('blur');
  assert.equal(control.sample(), 0);
  console.log('PASS: separate input modes, Space, mouse, button, release, typing and pause behavior.');
})().catch(error => {console.error(error); process.exitCode = 1;});
