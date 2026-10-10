const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const elements = new Map();
function element(id) {
  if (!elements.has(id)) {
    const classes = new Set();
    elements.set(id, {textContent: '', value: '100', disabled: false, className: '', style: {},
      listeners: {}, classList: {
        contains: key => classes.has(key), add: key => classes.add(key), remove: key => classes.delete(key),
        toggle: (key, enabled) => enabled ? classes.add(key) : classes.delete(key)
      }, setAttribute() {}, addEventListener(name, handler) { this.listeners[name] = handler; }
    });
  }
  return elements.get(id);
}
let timers = new Map(), serial = 0;
element('fallbackWarning').classList.add('hidden');
const ctx = {console, document: {getElementById: element, body: element('body')}, addEventListener() {},
  setTimeout(fn) { const id = ++serial; timers.set(id, fn); return id; },
  clearTimeout(id) { timers.delete(id); },
  webkit: {messageHandlers: {native: {async postMessage(message) {
    if (message.action === 'bootstrap') return {threshold: 100, nickname: '本地玩家'};
    if (message.action === 'settings') return {threshold: message.threshold};
    if (message.action === 'mode') {
      if (message.mode === 'keyboard' && !message.acknowledged) throw new Error('Confirm warning first');
      return {mode: message.mode};
    }
    return {ok: true};
  }}}}
};
ctx.window = ctx;
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(root, 'web/native.js'), 'utf8'), ctx);
vm.runInContext(fs.readFileSync(path.join(root, 'web/desktop.js'), 'utf8'), ctx);
(async () => {
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(element('continueBtn').disabled, true);
  assert.equal(element('startBtn').disabled, true);
  assert.equal(element('nicknameInput').value, '本地玩家');
  assert.equal(element('thresholdSlider').value, 100);
  await element('probeBtn').listeners.click();
  for (const fn of [...timers.values()]) fn();
  assert.ok(element('hardwareStatus').textContent.includes('未检测到兼容的力度信号'));
  assert.equal(element('fallbackWarning').classList.contains('hidden'), false, 'Missing hardware shows a warning dialog');
  assert.ok(element('fallbackMessage').textContent.includes('无法获得完整体验'));
  element('continueBtn').listeners.click();
  assert.equal(element('startup').classList.contains('hidden'), false);
  element('fallbackCancel').listeners.click();
  ctx.BreakPressure.receive({value: .4, peak: .4, verified: true, gesture: 1});
  assert.equal(element('continueBtn').disabled, true, 'Must release after verification');
  ctx.BreakPressure.receive({value: 0, peak: 0, verified: true, gesture: 1});
  assert.equal(element('continueBtn').disabled, false);
  element('continueBtn').listeners.click();
  assert.equal(element('startup').classList.contains('hidden'), true);
  ctx.BreakDesktop.showSettings();
  await element('probeBtn').listeners.click();
  assert.equal(element('continueBtn').disabled, true, 'Recheck must discard cached hardware success');
  element('fallbackBtn').listeners.click();
  assert.equal(ctx.BreakControl.mode, 'pressure', 'Warning alone does not change the controls');
  await element('fallbackConfirm').listeners.click();
  assert.equal(ctx.BreakControl.mode, 'keyboard');
  assert.equal(element('continueBtn').disabled, false, 'Fallback allows starting without hardware');
  assert.equal(element('thresholdSlider').disabled, true, 'Force threshold does not affect fallback mode');
  element('continueBtn').listeners.click();
  assert.equal(element('startup').classList.contains('hidden'), true);
  ctx.BreakDesktop.showSettings();
  await element('forceModeBtn').listeners.click();
  assert.equal(element('continueBtn').disabled, true, 'Force mode still requires genuine hardware');
  for (const threshold of ['1', '100']) {
    element('thresholdSlider').value = threshold;
    await element('thresholdSlider').listeners.change();
    assert.equal(ctx.BreakPressure.threshold, Number(threshold) / 100);
  }
  console.log('PASS: default 100%, hardware warning, fallback confirmation, mode switching, release gate and slider.');
})().catch(error => {console.error(error); process.exitCode = 1;});
