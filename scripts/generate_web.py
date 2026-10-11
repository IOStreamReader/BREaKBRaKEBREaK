#!/usr/bin/env python3
"""Adapt the preserved public bundle. Fail if the upstream bundle changes."""
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
WEB = ROOT / 'web'
source = (ROOT / 'web-original/assets/index-BMfj2Faj.js').read_text()
# The bundle is self-contained and is now loaded as a classic script.
# Remove Vite's unused module-preload shim and its fetch implementation.
preload_end = source.index('var e=1e3')
assert source[:preload_end].startswith('(function(){')
assert source[:preload_end].endswith('})();')
source = source[preload_end:]


def replace_once(old, new):
    global source
    assert source.count(old) == 1, f'Unexpected source match: {old[:90]}'
    source = source.replace(old, new, 1)


# Retain the original time ramp in fallback mode; pressure remains continuous.
replace_once(
    'if(this.powerCut)t?(this.holdTime+=e,this.pedalForce+=(Xh.rampBase+2*Xh.rampGrowth*this.holdTime)*e):(this.holdTime=0,this.pedalForce=Math.max(0,this.pedalForce-Xh.releaseRate*e)),n=',
    'if(this.powerCut){if(BreakControl.mode===`keyboard`){if(t){this.holdTime+=e;this.pedalForce+=(Xh.rampBase+2*Xh.rampGrowth*this.holdTime)*e}else{this.holdTime=0;this.pedalForce=Math.max(0,this.pedalForce-Xh.releaseRate*e)}}else this.pedalForce=Math.min(1,Math.max(0,t)/BreakPressure.threshold)*Xh.breakForceN;n=')
# Close the new mode branch before the original acceleration branch.
replace_once('Xh.decelPerNewton*this.pedalForce);else{', 'Xh.decelPerNewton*this.pedalForce)}else{')
replace_once('brakeElapsed=0;v0Kmh=0;peakForce=0;countdown=0;',
             'brakeElapsed=0;v0Kmh=0;peakForce=0;peakPressure=0;currentPressure=0;countdown=0;')
replace_once('this.v0Kmh=0,this.peakForce=0,this.samples=[]',
             'this.v0Kmh=0,this.peakForce=0,this.peakPressure=0,this.currentPressure=0,this.samples=[]')
replace_once('stepBraking(e,t,n){let r=this.dynamics.step(e,t);',
             'stepBraking(e,t,n){this.currentPressure=t;this.peakPressure=Math.max(this.peakPressure,t);let r=this.dynamics.step(e,t);')
replace_once('force:Math.min(this.dynamics.pedalForce,Pd.brake.breakForceN)})',
             'force:Math.min(this.dynamics.pedalForce,Pd.brake.breakForceN),pressure:this.currentPressure})')
replace_once('return{success:e,reason:t,v0Kmh:r,stopSeconds:n',
             'return{success:e,reason:t,relativePeak:this.peakPressure,v0Kmh:r,stopSeconds:n')

# Delete the entire network implementation, including both original API paths.
begin = source.index('async function Wg(')
end = source.index('var qg=', begin)
source = source[:begin] + '''async function Gg(limit) {
  return (await BreakNative.scores(limit)).entries;
}
async function Kg(nickname, v0, stopTime) {
  return BreakNative.saveScore(nickname, v0, stopTime);
}
''' + source[end:]
source = source.replace('localStorage.getItem(e_)', 'BreakNative.state.nickname')
replace_once('localStorage.setItem(e_,t),', '')
source = source.replace('已上榜！当前排名第 ', '已保存到本机！本地排名第 ')
source = source.replace('已提交，你的最佳成绩 ', '已保存，你的本地最佳成绩 ')
source = source.replace('提交中…', '正在保存…').replace('提交失败', '保存失败')
source = source.replace('快来抢第一！', '完成挑战后保存你的第一个成绩！')

replace_once('function k_(){p_.unlock(),O_()',
             'function k_(){if(!BreakControl.ready||!document.getElementById("startup").classList.contains("hidden"))return;BreakNative.setSession(true);p_.unlock(),O_()')
replace_once('function M_(e){let t=m_.step(e,g_||__);__=!1,A_(t)}',
             'function M_(e){let input=BreakControl.sample();g_=input>0;let t=m_.step(e,input);A_(t)}')
replace_once('case`stopped`:c_.setMode', 'case`stopped`:BreakNative.setSession(false);c_.setMode')
replace_once('case`crash`:{let e=', 'case`crash`:{if(t.reason===`brake_snap`)BreakNative.brakeSnap();BreakNative.setSession(false);let e=')

# AppKit provides the trackpad feedback; normal braking has no app vibration.
replace_once('function N_(e){`vibrate`in navigator&&navigator.vibrate(e)}',
             'function N_(e){}')

# The brake icon is clickable only in the explicitly selected fallback mode.
replace_once('this.brakeBtn.disabled=!(e.canBrake||e.braking),',
             'this.brakeBtn.disabled=BreakControl.mode!==`keyboard`||!(e.canBrake||e.braking),')
replace_once('this.brakeText.textContent=e.braking?`按住加力`:e.canBrake?`踩刹车!`:`刹车`',
             'this.brakeText.innerHTML=!(e.canBrake||e.braking)?`<span class="brake-caption">等待车速</span><span class="brake-speed">100 <small>km/h</small></span>`:BreakControl.mode===`keyboard`?`<span class="brake-caption">${e.braking?`按住加力`:`踩刹车`}</span><span class="brake-caption">空格 / 左键</span>`:`<span class="brake-caption">力度制动</span><span class="brake-caption">按压触控板</span>`')
replace_once('this.forceValue.textContent=`${Math.round(e.pedalForce)} N`',
             'this.forceValue.textContent=BreakControl.mode===`keyboard`?`${Math.round(e.pedalForce)} N`:`${Math.round(e.pedalForce/Pd.brake.breakForceN*BreakPressure.threshold*100)}%`')
replace_once('this.root,e)}update(e){let t=',
             'this.root,e)}update(e){document.getElementById("hudThreshold").textContent=BreakControl.mode===`keyboard`?`1612N`:`${Math.round(BreakPressure.threshold*100)}%`;let t=')
replace_once('踏板力度达到 ${Pd.brake.breakForceN} N，整车失控翻滚飞出',
             '${BreakControl.mode===`keyboard`?`模拟踏板力度达到 1612 N`:`相对力度达到 ${Math.round(BreakPressure.threshold*100)}%`}，整车失控翻滚飞出')
replace_once('`${Math.round(e.peakForce)} N`',
             '(BreakControl.mode===`keyboard`?`${Math.round(e.peakForce)} N`:`${(e.relativePeak*100).toFixed(1)}%`)')
replace_once('function $g(e,t,n,r){let i=',
             'function $g(e,t,n,r){if(BreakControl.mode===`pressure`){t=t.map(s=>({...s,force:s.pressure*100}));n=BreakPressure.threshold*100}let i=')
replace_once('p=Math.ceil(n*1.08/100)*100', 'p=Math.max(1,n*1.12,...t.map(s=>s.force*1.08))')
replace_once('for(let e of[0,500,1e3])', 'for(let e of[0,Math.round(n*.33),Math.round(n*.66)])')

# Replace the unconditional listeners with the explicit, gated control bridge.
begin = source.index('function I_(e)')
end = source.index('window.addEventListener(`contextmenu`', begin)
source = source[:begin] + source[end:]
replace_once('document.addEventListener(`visibilitychange`,()=>{document.hidden&&I_(!1)})',
             'document.addEventListener(`visibilitychange`,()=>{document.hidden&&BreakPressure.reset()})')
replace_once('$(`keyHint`).textContent=i_.isMobile?`按住屏幕任意位置或右下角按钮踩刹车`:`按住空格 / 鼠标左键踩刹车`',
             '$(`keyHint`).textContent=`光标停在游戏画面内，按压力度触控板；力度越大，制动越强。`')

# Freeze both gameplay and countdown on deactivation; frame time is rebased.
replace_once('function F_(e){T_+=e;',
             'function F_(e){if(BreakPressure.paused){u_.render();return}T_+=e;')
source += '''
let lastPauseState = false;
BreakPressure.subscribe(() => {
  if (lastPauseState === BreakPressure.paused) return;
  lastPauseState = BreakPressure.paused;
  if (p_.ctx) {
    const action = lastPauseState ? p_.ctx.suspend() : p_.ctx.resume();
    action.catch(() => {});
  }
});
window.BreakGame = {
  start: k_,
  isPlaying: () => ['countdown','accelerating','braking','crashed'].includes(m_.phase),
  cancel() {
    BreakNative.setSession(false); BreakPressure.reset();
    S_=null; m_.toMenu(); O_(); p_.stopLoops(0);
    h_.setVisible(false); h_.showCountdown(null); h_.hideToast();
    D_.hideAll(); D_.showMenu(true); c_.setMode('showcase');
  },
  diagnostics: () => ({phase:m_.phase, speed:m_.dynamics.speedKmh,
    pedalForce:m_.dynamics.pedalForce, frames:o_.info.render.frame,
    webgl:!!o_.getContext(), threshold:BreakPressure.threshold,
    pressure:BreakPressure.value, verified:BreakPressure.verified, mode:BreakControl.mode})
};
BreakControl.bind();
'''
assert '/api/' not in source
assert 'fetch(' not in source
assert 'localStorage' not in source
assert 'pointerdown`,e=>{(m_.phase' not in source
assert 'e.code===`Space`' not in source
(WEB / 'game.js').write_text("(() => {\n'use strict';\n" + source + '\n})();\n')
shutil.copyfile(ROOT / 'web-original/assets/index-D0EtOSyi.css', WEB / 'original.css')
print('Generated offline game bundle.')
