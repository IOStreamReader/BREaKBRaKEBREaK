/* Native bridge and relative Force Touch input. No network requests. */
(() => {
  const callbacks = new Set();
  let threshold = 1;
  let pressure = 0;
  let peak = 0;
  let verified = false;
  let paused = false;
  let sessionEnabled = false;
  let released = true;
  let lastGesture = 0;
  let requiresRelease = false;

  const emit = () => callbacks.forEach(fn => fn());
  window.BreakNative = {
    state: { nickname: '', threshold: 100 },
    async call(action, payload = {}) {
      const handler = window.webkit?.messageHandlers?.native;
      if (!handler) throw new Error('请使用 macOS App 打开游戏；网页无法读取力度触控板。');
      return handler.postMessage({ action, ...payload });
    },
    async initialize() {
      const state = await this.call('bootstrap');
      this.state = state;
      threshold = state.threshold / 100;
      return state;
    },
    async setThreshold(value) {
      const saved = await this.call('settings', { threshold: value });
      threshold = saved.threshold / 100;
      this.state.threshold = saved.threshold;
      pressure = peak = 0;
      emit();
      return saved;
    },
    async scores(limit) { return this.call('leaderboard', { limit }); },
    async saveScore(nickname, v0, stopTime) {
      const result = await this.call('score', { nickname, v0, stopTime });
      this.state.nickname = nickname;
      return result;
    },
    brakeSnap() {
      if (!sessionEnabled || paused || window.BreakControl.mode !== 'pressure') return;
      this.call('brakeSnap').catch(() => {});
    },
    setSession(active) {
      sessionEnabled = active;
      pressure = peak = 0;
      requiresRelease = !released;
      window.BreakControl.reset();
      this.call('session', { active }).catch(() => {});
    }
  };
  window.BreakPressure = {
    get threshold() { return threshold; },
    get value() { return pressure; },
    get verified() { return verified; },
    get paused() { return paused; },
    get released() { return released; },
    subscribe(fn) { callbacks.add(fn); },
    beginProbe() {
      verified = false;
      sessionEnabled = false;
      pressure = peak = 0;
      requiresRelease = true;
      emit();
    },
    receive(sample) {
      // This entry point is called by the native NSEvent.pressure handler only.
      if (!Number.isFinite(sample.value) || !Number.isFinite(sample.peak)) return;
      if (sample.verified === true) verified = true;
      const gestureChanged = sample.gesture !== lastGesture;
      lastGesture = sample.gesture;
      if (sample.mouseDown === false) window.BreakControl.press('mouse', false);
      released = sample.value === 0;
      if (released || gestureChanged) requiresRelease = false;
      if (sessionEnabled && !paused && !requiresRelease && verified) {
        pressure = Math.max(0, Math.min(1, sample.value));
        peak = Math.max(peak, Math.max(0, Math.min(1, sample.peak)));
      } else pressure = peak = 0;
      emit();
    },
    sample() {
      const result = Math.max(pressure, peak);
      peak = 0;
      return result;
    },
    reset() { pressure = peak = 0; window.BreakControl.reset(); },
    setPaused(value) {
      paused = value;
      pressure = peak = 0;
      requiresRelease = !released;
      window.BreakControl.reset();
      emit();
    }
  };

  let mode = 'pressure';
  const held = new Set();
  let pressedSinceSample = false;
  window.BreakControl = {
    get mode() { return mode; },
    get ready() { return mode === 'keyboard' || verified; },
    async setMode(value, acknowledged = false) {
      if (!['pressure', 'keyboard'].includes(value)) throw new Error('不支持这个操控方式。');
      const result = await window.BreakNative.call('mode', {mode: value, acknowledged});
      mode = result.mode;
      this.reset();
      pressure = peak = 0;
      emit();
    },
    press(source, down) {
      if (mode !== 'keyboard' || !sessionEnabled || paused) return;
      if (down) { held.add(source); pressedSinceSample = true; }
      else held.delete(source);
    },
    sample() {
      if (mode === 'pressure') return window.BreakPressure.sample();
      const down = held.size > 0 || pressedSinceSample;
      pressedSinceSample = false;
      return down ? 1 : 0;
    },
    reset() { held.clear(); pressedSinceSample = false; },
    bind() {
      const canUse = () => mode === 'keyboard' && !paused &&
        document.getElementById('startup').classList.contains('hidden');
      const pressMouse = event => {
        if (!canUse() || event.button !== 0 || event.pointerType !== 'mouse' || !window.BreakGame.isPlaying()) return;
        event.preventDefault();
        this.press('mouse', true);
      };
      for (const id of ['app', 'brakeBtn']) document.getElementById(id).addEventListener('pointerdown', pressMouse);
      for (const name of ['pointerup', 'pointercancel']) window.addEventListener(name, () => this.press('mouse', false));
      window.addEventListener('blur', () => this.reset());
      window.addEventListener('keydown', event => {
        if (!canUse() || event.code !== 'Space' || event.metaKey || event.ctrlKey || event.altKey ||
            event.target?.matches?.('input, textarea, [contenteditable="true"]')) return;
        if (window.BreakGame.diagnostics().phase === 'menu') {
          if (!event.repeat && document.activeElement === document.body) {
            event.preventDefault(); window.BreakGame.start();
          }
          return;
        }
        if (!window.BreakGame.isPlaying() || (event.repeat && !held.has('space'))) return;
        event.preventDefault(); this.press('space', true);
      });
      window.addEventListener('keyup', event => { if (event.code === 'Space') this.press('space', false); });
    }
  };

  window.addEventListener('error', event => {
    if (window.BreakGame) return;
    const label = document.getElementById('loading');
    if (label) label.textContent = '游戏初始化失败：' + event.message;
  });
})();
