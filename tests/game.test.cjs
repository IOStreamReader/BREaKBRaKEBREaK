const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const bundle = fs.readFileSync(path.join(root, 'web/game.js'), 'utf8');
const ctx = { console, addEventListener() {}, webkit: {messageHandlers: {native: {
  async postMessage(message) {
    if (message.action === 'bootstrap') return {threshold: 100, nickname: ''};
    if (message.action === 'settings') return {threshold: message.threshold};
    if (message.action === 'mode') {
      if (message.mode === 'keyboard' && !message.acknowledged) throw new Error('Warning must be acknowledged');
      return {mode: message.mode};
    }
    return {ok: true};
  }
}}}};
ctx.window = ctx;
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(root, 'web/native.js'), 'utf8'), ctx);
const configStart = bundle.indexOf('var Nd=');
const configEnd = bundle.indexOf('var Id=', configStart);
const dynamicsStart = bundle.indexOf('var{car:Yh,brake:Xh}=Pd');
const dynamicsEnd = bundle.indexOf(',rg=new U', dynamicsStart);
assert.ok(configStart > 0 && dynamicsStart > configStart && dynamicsEnd > dynamicsStart);
vm.runInContext(bundle.slice(configStart, configEnd) + bundle.slice(dynamicsStart, dynamicsEnd) +
  ';window.Engine={Physics:Qh,Game:ng};', ctx);

(async () => {
  await ctx.BreakNative.initialize();
  assert.equal(ctx.BreakPressure.threshold, 1);
  await ctx.BreakNative.setThreshold(50);
  const {Physics, Game} = ctx.Engine;
  const physics = new Physics();
  physics.speed = 100;
  physics.powerCut = true;
  physics.step(1 / 120, 0.2);
  assert.equal(physics.pedalForce, 644.8000000000001);
  const constantForce = physics.pedalForce;
  for (let i = 0; i < 600; i++) physics.step(1 / 120, 0.2);
  assert.equal(physics.pedalForce, constantForce, 'Holding constant pressure must not ramp force');
  physics.step(1 / 120, 0);
  assert.equal(physics.pedalForce, 0, 'Releasing must immediately stop applying force');

  const early = new Game();
  early.phase = 'accelerating'; early.dynamics.speed = 90 / 3.6;
  assert.equal(early.step(1 / 120, .2)[0].type, 'brake_too_early');
  assert.equal(early.dynamics.powerCut, false);
  early.dynamics.speed = 150 / 3.6;
  assert.equal(early.step(1 / 120, .2)[0].type, 'brake_start');
  assert.equal(early.dynamics.powerCut, true);
  assert.equal(early.step(1 / 120, .5)[0].reason, 'brake_snap');
  const overshoot = new Game();
  overshoot.phase = 'accelerating'; overshoot.dynamics.speed = 150 / 3.6;
  const snap = overshoot.step(1 / 120, .8).find(event => event.type === 'crash');
  assert.equal(snap.result.relativePeak, .8, 'Show actual peak pressure beyond the snap threshold');
  assert.equal(snap.result.samples.at(-1).pressure, .8);

  const success = new Game();
  success.phase = 'accelerating'; success.dynamics.speed = 200 / 3.6;
  let result;
  for (let i = 0; i < 10000 && !result; i++) {
    const events = success.step(1 / 120, .4);
    result = events.find(event => event.type === 'stopped')?.result;
  }
  assert.ok(result?.success && result.score > 0 && result.stopDistance < 2600);
  assert.ok(result.samples.length > 2);
  success.start();
  assert.equal(success.dynamics.pedalForce, 0);
  assert.equal(success.phase, 'countdown');

  for (const threshold of [1, 100]) {
    await ctx.BreakNative.setThreshold(threshold);
    const p = new Physics(); p.powerCut = true; p.speed = 100;
    assert.equal(p.step(1 / 120, threshold / 100 - 0.001), false);
    assert.equal(p.step(1 / 120, threshold / 100), true);
  }
  await ctx.BreakNative.setThreshold(50);

  const input = ctx.BreakPressure;
  assert.equal(input.verified, false);
  assert.equal(input.sample(), 0, 'No hardware must supply no brake input');
  input.receive({value: .8, peak: .8, verified: true, gesture: 1});
  ctx.BreakNative.setSession(true);
  input.receive({value: .8, peak: .8, verified: true, gesture: 1});
  assert.equal(input.sample(), 0, 'Calibration press must not leak into gameplay');
  input.receive({value: 0, peak: 0, verified: true, gesture: 1});
  input.receive({value: .15, peak: .25, verified: true, gesture: 2});
  assert.equal(input.sample(), .25, 'Keep between-frame peaks');
  assert.equal(input.sample(), .15, 'Steady pressure remains after consuming peak');
  input.setPaused(true); input.setPaused(false);
  input.receive({value: .15, peak: .15, verified: true, gesture: 2});
  assert.equal(input.sample(), 0, 'A held press must not resume a brake on refocusing');
  input.receive({value: .2, peak: .2, verified: true, gesture: 3});
  assert.equal(input.sample(), .2, 'A fresh press resumes input');
  ctx.BreakNative.setSession(false);
  input.receive({value: .9, peak: .9, verified: true, gesture: 4});
  assert.equal(input.sample(), 0, 'Menus must not control game physics');
  input.receive({value: NaN, peak: Infinity, verified: true, gesture: 5});
  assert.equal(input.sample(), 0);

  await assert.rejects(ctx.BreakControl.setMode('keyboard'));
  await ctx.BreakControl.setMode('keyboard', true);
  const fallback = new Physics(); fallback.speed = 100; fallback.powerCut = true;
  fallback.step(.25, 1);
  const lightForce = fallback.pedalForce;
  fallback.step(.25, 1);
  assert.ok(fallback.pedalForce > lightForce, 'Holding grows force in the original fallback mode');
  const heldForce = fallback.pedalForce;
  fallback.step(.05, 0);
  assert.equal(fallback.pedalForce, heldForce - 45, 'Original release rate is preserved');
  assert.equal(fallback.holdTime, 0);
  for (let i = 0; i < 400; i++) fallback.step(1/120, 1);
  assert.ok(fallback.pedalForce >= 1612, 'Holding too long snaps the original brake');
  await ctx.BreakControl.setMode('pressure');

  assert.ok(!bundle.includes('/api/'));
  assert.ok(!bundle.includes('localStorage'));
  assert.ok(!bundle.includes('e.code===`Space`'));
  assert.ok(!bundle.includes('function I_('));
  console.log('PASS: pressure physics, thresholds, successful stop, snap, hardware gate, release and pause handling.');
})().catch(error => { console.error(error); process.exitCode = 1; });
