/* Input choice, startup disclosure, hardware verification and settings. */
(() => {
  const $ = id => document.getElementById(id);
  let probeTimer;
  let loaded = false;
  let checking = false;
  let saving = false;

  function refresh() {
    const input = window.BreakPressure;
    const keyboard = window.BreakControl.mode === 'keyboard';
    const value = Math.round(input.value * 100);
    $('relativePressure').textContent = `${value}%`;
    $('relativeFill').style.width = `${value}%`;
    $('relativeMeter').classList.toggle('hidden', keyboard);
    document.body.classList.toggle('keyboard-mode', keyboard);
    $('forceModeBtn').classList.toggle('selected', !keyboard);
    $('fallbackBtn').classList.toggle('selected', keyboard);
    $('forceModeBtn').setAttribute('aria-pressed', String(!keyboard));
    $('fallbackBtn').setAttribute('aria-pressed', String(keyboard));
    $('thresholdSlider').disabled = keyboard || saving;
    if (input.verified && !keyboard) {
      clearTimeout(probeTimer);
      checking = false;
      $('hardwareStatus').className = 'hardware-status ok';
      $('hardwareStatus').textContent = input.released
        ? '已检测到兼容的力度触控板，可以开始。'
        : '已收到真实力度信号。请松开触控板后继续。';
      $('probeBtn').textContent = '重新检测';
    } else if (keyboard) {
      $('hardwareStatus').className = 'hardware-status fallback';
      $('hardwareStatus').textContent = '键盘/鼠标备用模式：按住空格或鼠标左键逐渐加力，松开卸力。无法体验真实按压力度。';
    }
    $('continueBtn').disabled = !(loaded && !saving && window.BreakControl.ready && (keyboard || input.released));
    $('continueBtn').textContent = keyboard ? '进入游戏 · 键鼠模式' : '进入游戏';
    $('startBtn').disabled = !loaded || !window.BreakControl.ready;
    $('keyHint').textContent = keyboard
      ? '按住空格 / 游戏画面上的鼠标左键踩刹车；按得越久，力度越大。'
      : '光标停在游戏画面内，按压力度触控板；力度越大，制动越强。';
    $('brakeRule').innerHTML = keyboard
      ? '按住空格或鼠标左键切断动力；<b>按得越久，力度越大</b>'
      : '按压力度触控板切断动力；<b>按得越重，制动越强</b>';
    $('limitRule').innerHTML = keyboard
      ? '模拟踏板力达到 <b class="danger">1612 N</b> 会断裂翻车'
      : '相对力度达到设定阈值，<b class="danger">踏板断裂</b>，整车翻滚失败';
    $('forceLabel').textContent = keyboard ? '踏板力度（模拟）' : '触控板力度';
    $('peakLabel').textContent = keyboard ? '最大模拟踏板力' : '最大触控板力度';
    $('forceLegend').textContent = keyboard ? '踏板力（模拟 N）' : '触控板力度 %';
    $('pauseOverlay').classList.toggle('hidden', !input.paused || !window.BreakGame?.isPlaying());
  }

  function showFallbackWarning() {
    if (!loaded) return;
    $('fallbackMessage').textContent = window.BreakPressure.verified
      ? '键盘/鼠标模式无法提供真实按压力度的完整体验。备用模式采用按住逐渐加力、松开卸力的玩法。'
      : '未检测到兼容的 Mac 力度触控板，无法获得完整体验。你仍可使用空格键或鼠标左键游玩：按住逐渐加力，松开卸力。';
    $('fallbackWarning').classList.remove('hidden');
  }

  async function checkHardware() {
    clearTimeout(probeTimer);
    try {
      await window.BreakControl.setMode('pressure');
      window.BreakPressure.beginProbe();
      await window.BreakNative.call('probe');
    } catch (error) {
      $('hardwareStatus').className = 'hardware-status error';
      $('hardwareStatus').textContent = error.message;
      return;
    }
    checking = true;
    $('hardwareStatus').className = 'hardware-status';
    $('hardwareStatus').textContent = '将光标移到下方检测区，用一根手指按下触控板并逐渐加力，然后松开。';
    $('probeBtn').textContent = '等待力度信号…';
    refresh();
    probeTimer = setTimeout(() => {
      checking = false;
      if (!window.BreakPressure.verified) {
        $('hardwareStatus').className = 'hardware-status error';
        $('hardwareStatus').textContent = '未检测到兼容的力度信号。可连接支持 Force Touch 的触控板重试，或选择键盘/鼠标备用模式。';
        $('probeBtn').textContent = '重试检测';
        showFallbackWarning();
      }
    }, 12000);
  }

  window.BreakDesktop = {
    showSettings() {
      if (window.BreakGame?.isPlaying()) window.BreakGame.cancel();
      window.BreakNative.setSession(false);
      $('startup').classList.remove('hidden');
      refresh();
    },
    rawPressure(value) {
      $('probePressure').textContent = `${Math.round(value * 100)}%`;
      $('probeFill').style.width = `${value * 100}%`;
      if (checking && window.BreakPressure.verified) refresh();
    }
  };
  $('fallbackBtn').addEventListener('click', showFallbackWarning);
  $('fallbackCancel').addEventListener('click', () => $('fallbackWarning').classList.add('hidden'));
  $('fallbackConfirm').addEventListener('click', async () => {
    $('fallbackConfirm').disabled = true;
    try {
      await window.BreakControl.setMode('keyboard', true);
      clearTimeout(probeTimer);
      checking = false;
      $('fallbackWarning').classList.add('hidden');
      refresh();
    } catch (error) { $('fallbackMessage').textContent = error.message; }
    $('fallbackConfirm').disabled = false;
  });
  $('forceModeBtn').addEventListener('click', async () => {
    try { await window.BreakControl.setMode('pressure'); refresh(); }
    catch (error) { $('settingsError').textContent = error.message; }
  });
  $('probeBtn').addEventListener('click', checkHardware);
  $('continueBtn').addEventListener('click', () => {
    if (!loaded || saving || !window.BreakControl.ready ||
        (window.BreakControl.mode === 'pressure' && !window.BreakPressure.released) ||
        !$('fallbackWarning').classList.contains('hidden')) return;
    $('startup').classList.add('hidden');
  });
  $('settingsBtn').addEventListener('click', () => window.BreakDesktop.showSettings());
  const slider = $('thresholdSlider');
  slider.addEventListener('input', () => { $('thresholdValue').textContent = `${slider.value}%`; });
  slider.addEventListener('change', async () => {
    if (window.BreakControl.mode !== 'pressure') return;
    saving = true;
    refresh();
    try {
      const settings = await window.BreakNative.setThreshold(Number(slider.value));
      slider.value = settings.threshold;
      $('thresholdValue').textContent = `${settings.threshold}%`;
      $('settingsError').textContent = '';
    } catch (error) {
      slider.value = window.BreakNative.state.threshold;
      $('thresholdValue').textContent = `${slider.value}%`;
      $('settingsError').textContent = '设置保存失败：' + error.message;
    }
    saving = false;
    refresh();
  });
  window.BreakPressure.subscribe(refresh);
  window.BreakNative.initialize().then(state => {
    loaded = true;
    slider.value = state.threshold;
    $('thresholdValue').textContent = `${state.threshold}%`;
    $('nicknameInput').value = state.nickname;
    refresh();
  }).catch(error => {
    $('hardwareStatus').className = 'hardware-status error';
    $('hardwareStatus').textContent = error.message;
    $('continueBtn').disabled = true;
  });
})();
