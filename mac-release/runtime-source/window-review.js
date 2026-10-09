// Runs only with --candidate-review, in an isolated profile and hidden window.
const fs=require('fs'),path=require('path');
module.exports=({app,window,view,restart,logger,setViewBounds,refreshZoom})=>{
  const report=path.join(app.getPath('userData'),'window-review.json');
  const events=fs.existsSync(report)?JSON.parse(fs.readFileSync(report)).events:[];
  const record=e=>{events.push({...e,pid:process.pid,time:new Date().toISOString()});fs.writeFileSync(report,JSON.stringify({events},null,2));};
  const cycle=process.argv.filter(a=>a.startsWith('--window-review-cycle=')).reduce((n,a)=>Math.max(n,Number(a.split('=')[1])||0),0);
  record({event:'start',cycle,visible:window.isVisible(),profile:app.getPath('userData')});
  for(const [name,wc] of [['toolbar',window.webContents],['game',view.webContents]])wc.on('crashed',(_e,killed)=>record({event:'crash',name,killed}));
  app.on('gpu-process-crashed',(_e,killed)=>record({event:'gpu-crash',killed}));
  // executeJavaScript may wait indefinitely for a pending navigation, so the
  // whole hidden test has an independent deadline rather than a polling-only one.
  const watchdog=setTimeout(()=>{record({event:'failure',error:'Hidden release review timed out after 45 seconds'});app.quit();},45000);
  app.on('before-quit',()=>clearTimeout(watchdog));
  const delay=ms=>new Promise(r=>setTimeout(r,ms));
  (async()=>{
    const deadline=Date.now()+30000;
    let proof;
    while(Date.now()<deadline){
      try{
        const controls=await window.webContents.executeJavaScript("({zoom:!!document.getElementById('zoom'),night:!!document.getElementById('darkModeBtn'),mute:!!document.getElementById('muteBtn'),volume:!!document.getElementById('volume')})");
        const game=await view.webContents.executeJavaScript("({url:location.origin+location.pathname,embeds:document.querySelectorAll('embed,object').length,debugOverlay:typeof window.__ekoDebugLog==='function',fit:window.ekolokoGameZoom&&window.ekolokoGameZoom.state().fit,box:(function(){var e=document.getElementById('mainSWFDIV');return e&&{w:e.offsetWidth,h:e.offsetHeight}})()})");
        if(game.url==='https://play.ekoloko.org/ekoloko/login.html'&&game.embeds===1&&game.fit&&!game.debugOverlay&&controls.mute&&!controls.zoom&&!controls.night&&!controls.volume){proof={controls,game};break;}
      }catch(_){}
      await delay(200);
    }
    if(!proof)throw Error('Final packaged candidate did not become ready with fit-only controls');
    await window.webContents.executeJavaScript("document.getElementById('muteBtn').click()");await delay(100);
    if(!view.webContents.isAudioMuted())throw Error('Mute failed');
    await window.webContents.executeJavaScript("document.getElementById('muteBtn').click()");await delay(100);
    if(view.webContents.isAudioMuted())throw Error('Unmute failed');
    for(const [w,h] of [[800,600],[1280,900],[1100,700]]){
      window.setContentSize(w,h);setViewBounds();await refreshZoom();await delay(400);
      const geometry=await view.webContents.executeJavaScript("(function(){var e=document.getElementById('mainSWFDIV'),v=document.getElementById('gameViewport');return {w:e.offsetWidth,h:e.offsetHeight,vw:v.clientWidth,vh:v.clientHeight}})()");
      if(Math.abs(geometry.w/geometry.h-1.6)>0.006||geometry.w>geometry.vw+1||geometry.h>geometry.vh+1)throw Error('Game fit overflow or aspect error: '+JSON.stringify(geometry));
      record({event:'resize',requested:{w,h},contentBounds:window.getContentBounds(),viewBounds:view.getBounds(),geometry});
    }
    const menu=require('electron').Menu.getApplicationMenu();
    if(!menu||!menu.getMenuItemById('exit-game-fullscreen'))throw Error('Native fullscreen exit menu missing');
    record({event:'ready',cycle,proof,mute:true,visible:window.isVisible(),nativeEscapeMenu:true});
    await delay(2000);
    if(cycle<3){process.argv.push('--window-review-cycle='+(cycle+1));restart('toolbar');}
    else{record({event:'complete'});app.quit();}
  })().catch(e=>{record({event:'failure',error:String(e)});logger.error('window-review',String(e));app.quit();});
};
