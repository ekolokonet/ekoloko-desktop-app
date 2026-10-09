"use strict";
// Runs only with BOTH fixture and self-test flags. No production requests,
// windows shown, account login, cookies imported, or system settings changed.
const fs = require('fs');
const path = require('path');
let windowCount = 0;
module.exports = async function selfTest({ app, window, view, log }) {
  const count = ++windowCount;
  const reportPath = path.join(app.getPath('userData'), 'self-test.json');
  const events = process.argv.includes('--candidate-restarted') && fs.existsSync(reportPath) ? JSON.parse(fs.readFileSync(reportPath)).events : [];
  const deadline = Date.now() + 20000;
  let proof;
  while (Date.now() < deadline) {
    try {
      const controls = await window.webContents.executeJavaScript("!!document.getElementById('restartBtn') && !document.getElementById('zoom') && !document.getElementById('darkModeBtn') && !!document.getElementById('muteBtn') && !document.getElementById('volume')");
      const state = await view.webContents.executeJavaScript("window.fixtureReady && document.getElementById('nativeFlash').getDemoState()");
      if (controls && state && state.runtime === 'MAC 34,0,0,372') { proof = state; break; }
    } catch (_) {}
    await new Promise(resolve => setTimeout(resolve, 200));
  }
  if (!proof) throw Error('Offline toolbar + Flash fixture did not become ready within 20 seconds');
  await window.webContents.executeJavaScript("document.getElementById('muteBtn').click()");
  await new Promise(resolve => setTimeout(resolve, 100));
  if (!view.webContents.isAudioMuted()) throw Error('Mac mute button did not mute the game view');
  await window.webContents.executeJavaScript("document.getElementById('muteBtn').click()");
  await new Promise(resolve => setTimeout(resolve, 100));
  if (view.webContents.isAudioMuted()) throw Error('Mac mute button did not restore audio');
  const restarted = process.argv.includes('--candidate-restarted');
  const recovered = process.argv.includes('--candidate-recovered');
  const phase = !restarted ? 'cold-start' : !recovered ? 'after-relaunch' : 'after-renderer-recovery';
  events.push({phase, pid:process.pid, flash:proof.runtime, playerType:proof.playerType, toolbar:true, muteVerified:true, noVolumeSlider:true, windowVisible:window.isVisible()});
  fs.writeFileSync(reportPath, JSON.stringify({events, passed:false}, null, 2));
  log(`offline fixture ready phase=${phase} pid=${process.pid}`);
  if (!restarted) {
    await window.webContents.executeJavaScript("require('electron').ipcRenderer.send('restart')");
  } else if (!recovered) {
    log('intentional crash of isolated toolbar renderer');
    window.webContents.executeJavaScript('process.crash()').catch(() => {});
  } else {
    const image = await window.webContents.capturePage();
    fs.writeFileSync(path.join(app.getPath('userData'), 'toolbar.png'), image.toPNG());
    const report = {passed:events.some(e=>e.phase==='cold-start') && events.some(e=>e.phase==='after-relaunch') && events.some(e=>e.phase==='after-renderer-recovery'), events};
    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
    log(`offline self-test completed passed=${report.passed}`);
    app.quit();
  }
};
