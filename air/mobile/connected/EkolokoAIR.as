package {
    import flash.desktop.NativeApplication;
    import flash.filesystem.File;
    import flash.filesystem.FileStream;
    import flash.filesystem.FileMode;
    import flash.display.Loader;
    import flash.display.Sprite;
    import flash.display.StageAlign;
    import flash.display.StageScaleMode;
    import flash.display.StageDisplayState;
    import flash.events.Event;
    import flash.events.InvokeEvent;
    import flash.events.IOErrorEvent;
    import flash.events.SecurityErrorEvent;
    import flash.events.UncaughtErrorEvent;
    import flash.events.HTTPStatusEvent;
    import flash.events.MouseEvent;
    import flash.events.ProgressEvent;
    import flash.events.FullScreenEvent;
    import flash.events.NativeWindowBoundsEvent;
    import flash.events.NativeWindowDisplayStateEvent;
    import flash.events.KeyboardEvent;
    import flash.events.TimerEvent;
    import flash.net.URLLoader;
    import flash.net.URLLoaderDataFormat;
    import flash.net.URLRequest;
    import flash.net.navigateToURL;
    import flash.net.FileReference;
    import flash.net.SharedObject;
    import flash.media.SoundMixer;
    import flash.system.ApplicationDomain;
    import flash.system.Capabilities;
    import flash.system.LoaderContext;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.utils.setTimeout;
    import flash.utils.clearTimeout;
    import flash.utils.ByteArray;
    import flash.utils.Timer;
    import flash.geom.Rectangle;
    import org.ekoloko.air.NativeServices;
    import org.ekoloko.air.BuildInfo;
    import org.ekoloko.air.NativeToolbar;
    import org.ekoloko.air.IncidentController;
    import org.ekoloko.air.NativeBoardMotion;
    import org.ekoloko.air.NativeLayout;
    import org.ekoloko.air.NativeStatus;
    import org.ekoloko.air.NativeStagePolicy;
    import org.ekoloko.air.NativeReleaseStore;
    import org.ekoloko.air.NativeRawAssetReader;
    import org.ekoloko.air.NativeUpdatePolicy;
    import org.ekoloko.air.NativeNavigation;

    [SWF(width="960", height="600", frameRate="24", backgroundColor="#AAD93D")]
    public class EkolokoAIR extends Sprite {
        private var game:Loader;
        private var mobileBridge:ConnectedMobileUI;
        private var viewport:Sprite = new Sprite();
        private var stagePolicy:NativeStagePolicy;
        private var renderQuality:MobileRenderQuality;
        private var status:NativeStatus;
        private var generation:uint = 0;
        private var requests:Array = [];
        private var initialized:Boolean = false;
        private var starting:Boolean = false;
        private var backdrop:Sprite = new Sprite();
        private var toolbar:NativeToolbar;
        private var incidentBoard:IncidentController;
        private var chromeWidth:Number;
        private var chromeHeight:Number;
        private var logExport:FileReference;
        private var handlingFailure:Boolean = false;
        private var updateTimer:Timer;
        private var updateCheckPending:Boolean = false;
        private var updateOffered:Boolean = false;
        private var localBootstrapCheck:Boolean = false;
        private var localUIReview:Boolean = false;
        private var localUIQA:Boolean = false;
        private var localUIDemo:Boolean = false;
        private var requiredClientUpdate:Boolean = false;
        private var mapUpdateAttempted:Boolean = false;
        private var rawAssets:NativeRawAssetReader;
        private var metadataOnlyCheck:Boolean = false;
        private var cacheRepairCheck:Boolean = false;
        private var testCacheCorrupted:Boolean = false;
        private var backgroundAt:Number=0,foregroundFrameRate:Number=24;
        private var backgroundSession:Boolean=false,backgroundLoading:Boolean=false,reloadPending:Boolean=false;
        CONFIG::mobile { private const mobileRuntime:Boolean = true; }
        CONFIG::desktop { private const mobileRuntime:Boolean = false; }

        public function EkolokoAIR() {
            renderQuality = new MobileRenderQuality(stage);
            // Establish the native window's visibility once, before loading
            // any legacy document. Movie swaps must not own this lifecycle.
            if(!mobileRuntime)stage.nativeWindow.visible = true;
            // Match login.html's 960x600 (8:5) embed. AIR exposes artwork
            // outside a loaded movie's declared Stage unless it is clipped.
            // Keep Flash's native SHOW_ALL coordinates so game code still sees
            // the same logical Stage dimensions as the original HTML embed.
            stage.scaleMode = StageScaleMode.NO_SCALE;
            chromeWidth = mobileRuntime?0:stage.nativeWindow.width - stage.stageWidth;
            chromeHeight = mobileRuntime?0:stage.nativeWindow.height - stage.stageHeight;
            stage.align = "";
            stage.scaleMode = StageScaleMode.SHOW_ALL;
            addChild(backdrop);
            viewport.scrollRect = new Rectangle(0, 0, 960, 600);
            addChild(viewport);
            status = new NativeStatus(function():void {if(initialized && !starting) start();});
            addChild(status);
            toolbar = new NativeToolbar(toolbarAction); addChild(toolbar);
            incidentBoard = new IncidentController("public-notices", "https://ekdash.ekoloko.org/api/public/incidents", toolbar.setIncidentAttention,false); addChild(incidentBoard);
            CONFIG::desktop { incidentBoard.board.motionBackend = new NativeBoardMotion(incidentBoard.board,reviewViewport,incidentBoard.open); }
            mobileBridge = new ConnectedMobileUI(viewport,function():Loader{return game;},layout,mobileRuntime);addChild(mobileBridge);
            // Numeric presentation state distinguishes a failed movie swap
            // from fullscreen, minimization or a closed native window.
            NativeServices.hostState = function():Object {
                return {width:physicalWidth(), height:physicalHeight(),screenDPI:Capabilities.screenDPI,displayDensity:displayDensity(),
                    visible:mobileRuntime||stage.nativeWindow.visible, nativeState:mobileRuntime?"mobile":stage.nativeWindow.displayState,
                    displayState:stage.displayState, stageWidth:stage.stageWidth, stageHeight:stage.stageHeight,
                    scaleMode:stage.scaleMode, align:stage.align, renderingQuality:renderQuality.snapshot(),
                    focused:mobileRuntime||NativeApplication.nativeApplication.activeWindow == stage.nativeWindow,
                    sourceRect:stage.fullScreenSourceRect == null ? null : {width:stage.fullScreenSourceRect.width,height:stage.fullScreenSourceRect.height},
                    gameAttached:game != null && game.parent == viewport,
                    viewportX:viewport.x, viewportY:viewport.y, viewportScale:viewport.scaleX,
                    chatCamera:mobileBridge?mobileBridge.cameraDiagnostics:null};
            };
            if(mobileRuntime)stage.addEventListener(Event.RESIZE,layout);
            else stage.nativeWindow.addEventListener(NativeWindowBoundsEvent.RESIZE, layout);
            stage.addEventListener(FullScreenEvent.FULL_SCREEN, layout);
            stage.addEventListener(FullScreenEvent.FULL_SCREEN, function(e:FullScreenEvent):void {
                NativeServices.report({stage:"window",reasonCode:e.fullScreen ? "fullscreen_entered" : "fullscreen_left"});
            });
            if(!mobileRuntime){
            stage.nativeWindow.addEventListener(Event.ACTIVATE, function(e:Event):void { NativeServices.report({stage:"window",reasonCode:"window_activated"}); });
            stage.nativeWindow.addEventListener(Event.DEACTIVATE, function(e:Event):void { NativeServices.report({stage:"window",reasonCode:"window_deactivated"}); });
            stage.nativeWindow.addEventListener(NativeWindowDisplayStateEvent.DISPLAY_STATE_CHANGE, function(e:NativeWindowDisplayStateEvent):void {
                NativeServices.report({stage:"window",reasonCode:"native_display_state_changed"});
            });
            }
            if(mobileRuntime){
                NativeApplication.nativeApplication.addEventListener(Event.DEACTIVATE,mobileDeactivated);
                NativeApplication.nativeApplication.addEventListener(Event.ACTIVATE,mobileActivated);
            }
            stagePolicy = new NativeStagePolicy(stage, layout);
            stage.addEventListener(KeyboardEvent.KEY_DOWN, function(e:KeyboardEvent):void {
                if(e.keyCode==73 && e.commandKey){e.preventDefault();e.stopImmediatePropagation();incidentBoard.open();}
                if (e.keyCode == 122 || (e.keyCode == 70 && e.controlKey && e.commandKey)) {
                    e.preventDefault(); e.stopImmediatePropagation(); toolbarAction("fullscreen");
                }
            }, true, 1000);
            layout();
            loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, function(e:UncaughtErrorEvent):void {
                e.preventDefault();
                if (handlingFailure) return;
                if (e.error is Error) trace("[AIR] runtime_error_id=" + Error(e.error).errorID);
                NativeServices.recordRuntimeFailure(e.error as Error);
                if(NativeServices.recoverSocketCallback(e.error as Error) || NativeServices.recoverGameCallback(e.error as Error)) {
                    toolbar.setRuntimeWarning(true);
                    return;
                }
                fail("runtime_error");
            });
            NativeApplication.nativeApplication.addEventListener(Event.EXITING,function(e:Event):void {
                NativeServices.report({stage:"host",reasonCode:"application_exit_requested"});NativeServices.saveDiagnostics();
            });
            NativeServices.events.addEventListener("assetFailure", function(e:Event):void {
                var failure:Object = NativeServices.diagnostics().assetFailure;
                var reason:String = failure ? failure.reason : "";
                fail(reason == "asset_update_required" || reason == "asset_not_installed" || reason == "asset_access_denied" ? reason : "asset_load_failed");
            });
            try {
                if(BuildInfo.PACKED_REVIEW){
                    // Local developer build uses the core's verified pack reader.
                    // Account/bootstrap/world/chat still use their original server paths.
                    var installed:Object=NativeServices.readPinnedManifest(true);
                    var mobileStore:NativeReleaseStore=new NativeReleaseStore(BuildInfo.ORIGIN,BuildInfo.RELEASE_PUBLIC_MODULUS,
                        File.applicationStorageDirectory.resolvePath("mobile-cached-swfs"),null,true);
                    mobileStore.useBundledManifest(installed,NativeServices.readBundledAsset);
                    NativeServices.initialize(mobileStore);
                } else {
                var store:NativeReleaseStore = new NativeReleaseStore(BuildInfo.ORIGIN, BuildInfo.RELEASE_PUBLIC_MODULUS,
                    File.applicationStorageDirectory.resolvePath("cached-swfs"));
                rawAssets=new NativeRawAssetReader();
                store.usePinnedManifest(NativeServices.readPinnedManifest(),rawAssets);
                NativeServices.initialize(store);
                }
                initialized = true;
                NativeNavigation.internalLogin=mobileRuntime;
                NativeServices.reload = requestRestart;
                if (true) {
                    updateTimer = new Timer(60000);
                    updateTimer.addEventListener(TimerEvent.TIMER,checkReleaseUpdate); updateTimer.start();
                }
                trace("[AIR] native=" + Capabilities.cpuArchitecture + " runtime=" + Capabilities.version + " release=" + BuildInfo.VERSION);
                NativeApplication.nativeApplication.addEventListener(InvokeEvent.INVOKE, initialInvoke);
            } catch (error:Error) {
                NativeServices.recordRuntimeFailure(error);
                fail("installation_integrity");
            }
        }

        private function requestRestart():void {
            if(backgroundAt>0){reloadPending=true;return;}
            if(starting)return;
            mobileBridge.retainDraftForRestart();
            start();
        }
        private function mobileDeactivated(e:Event):void {
            if(backgroundAt>0)return;
            backgroundAt=new Date().time;backgroundSession=mobileBridge.hasSession;backgroundLoading=starting;
            foregroundFrameRate=stage.frameRate;stage.frameRate=1;
            mobileBridge.retainDraftForRestart();
            mobileBridge.suspend(true);
            if(updateTimer)updateTimer.stop();
            NativeServices.report({stage:"mobile",reasonCode:"application_backgrounded"});
        }
        private function mobileActivated(e:Event):void {
            if(backgroundAt==0)return;
            var elapsed:Number=new Date().time-backgroundAt;
            backgroundAt=0;stage.frameRate=foregroundFrameRate;mobileBridge.suspend(false);
            if(updateTimer)updateTimer.start();
            NativeServices.report({stage:"mobile",reasonCode:"application_resumed"});
            var restart:Boolean=reloadPending||MobileResumePolicy.restart(elapsed,backgroundSession,mobileBridge.sessionConnected,backgroundLoading);
            reloadPending=false;backgroundSession=false;backgroundLoading=false;
            if(restart){
                mobileBridge.retainDraftForRestart();
                NativeServices.report({stage:"mobile",reasonCode:"session_restart_after_background"});
                start();
            }
        }

        // The native visible viewport may extend beyond the legacy 960x600
        // logical Stage under SHOW_ALL. Review captures include that whole area.
        public function reviewViewport():Object {
            var full:Boolean=stage.displayState!=StageDisplayState.NORMAL;
            return NativeLayout.calculate(physicalWidth(),physicalHeight(),full||mobileRuntime);
        }
        // iOS reports Retina pixels here. The responsive UI is measured in
        // display points, otherwise its capped controls become 3x too small.
        private function displayDensity():Number {
            if(!mobileRuntime||Capabilities.version.indexOf("IOS")!=0)return 1;
            return Math.max(1,stage.contentsScaleFactor,Math.round(Capabilities.screenDPI/160));
        }
        private function physicalWidth():Number {return mobileRuntime||stage.displayState!=StageDisplayState.NORMAL?stage.fullScreenWidth/displayDensity():stage.nativeWindow.width-chromeWidth;}
        private function physicalHeight():Number {return mobileRuntime||stage.displayState!=StageDisplayState.NORMAL?stage.fullScreenHeight/displayDensity():stage.nativeWindow.height-chromeHeight;}

        private function captureLocalUIReview():void {
                    incidentBoard.open();
                    var captureTimer:Timer=new Timer(localUIQA?6000:1200,1);captureTimer.addEventListener(TimerEvent.TIMER_COMPLETE,function(e:TimerEvent):void{
                        var view:Object=reviewViewport();var pixels:flash.display.BitmapData=new flash.display.BitmapData(Math.round(view.width*view.outerScale),Math.round(view.height*view.outerScale),false);pixels.draw(stage,new flash.geom.Matrix(view.outerScale,0,0,view.outerScale,-view.left*view.outerScale,-view.top*view.outerScale));
                        var image:ByteArray=pixels.encode(pixels.rect,new flash.display.PNGEncoderOptions());
                        var target:File=File.applicationStorageDirectory.resolvePath("unified-review.png");var output:flash.filesystem.FileStream=new flash.filesystem.FileStream();output.open(target,flash.filesystem.FileMode.WRITE);output.writeBytes(image);output.close();pixels.dispose();trace("UNIFIED_UI_REVIEW_PASS screenshot="+target.nativePath+" gameCadence="+stage.frameRate+" authenticated=false");NativeApplication.nativeApplication.exit(0);
                    });captureTimer.start();
        }

        private function initialInvoke(e:InvokeEvent):void {
            NativeApplication.nativeApplication.removeEventListener(InvokeEvent.INVOKE, initialInvoke);
            if(e.arguments.indexOf("--mobile-snapshot")>=0){
                setTimeout(captureMobileStartup,15000);
                var captures:int=0;
                var typingCapture:uint=0;
                mobileBridge.addEventListener("mobileInputChanged",function(event:Event):void{clearTimeout(typingCapture);typingCapture=setTimeout(captureMobileStartup,350);});
                stage.addEventListener(MouseEvent.CLICK,function(click:MouseEvent):void{if(captures++<96)setTimeout(captureMobileStartup,1200);},true,2000);
                mobileBridge.addEventListener("mobileReady",function(event:Event):void{
                    setTimeout(captureMobileStartup,1200);
                });
            }
            if(BuildInfo.PRODUCTION){incidentBoard.feed.refresh();start();return;}
            localUIDemo=e.arguments.indexOf("--local-ui-demo")>=0;
            if(localUIDemo){
                updateTimer.stop();
                incidentBoard.feed.useLocalDemo({schemaVersion:1,feedRevision:1,incidents:[{id:"12345678-1234-1234-1234-123456789001",revision:1,kind:"update",important:false,attentionEligible:false,feature:"הדגמה מקומית",severity:"low",impact:"informational",handlingStatus:"known",playerText:"הדגמה מקומית בלבד. אפשר לבדוק את הלוח, לסגור ולפתוח אותו מהסרגל ולבדוק מסך מלא. אין כאן משחק מחובר או הודעות מהשרת.",workaround:null,sortOrder:1}]});
                status.show("הדגמה מקומית","בדיקת ממשק בלבד · ללא כניסה למשחק",false,false);
                incidentBoard.board.update();incidentBoard.open();
                trace("UNIFIED_LOCAL_DEMO_READY native="+Capabilities.cpuArchitecture+" noGameBootstrap=true noNetwork=true");return;
            }
            incidentBoard.feed.refresh();
            localUIQA=e.arguments.indexOf("--local-ui-qa")>=0;
            localUIReview=localUIQA || e.arguments.indexOf("--local-ui-review")>=0;
            if(localUIReview){trace("UNIFIED_UI_REVIEW_ONLY noGameBootstrap=true");captureLocalUIReview();return;}
            metadataOnlyCheck=e.arguments.indexOf("--metadata-only-check")>=0;
            cacheRepairCheck=e.arguments.indexOf("--cache-repair-check")>=0;
            localBootstrapCheck = localUIReview || metadataOnlyCheck || cacheRepairCheck || e.arguments.indexOf("--local-bootstrap-check") >= 0;
            start();
        }

        private function captureMobileStartup():void {
            var view:Object=NativeLayout.calculate(physicalWidth(),physicalHeight(),true);
            var pixels:flash.display.BitmapData=new flash.display.BitmapData(Math.round(view.width*view.outerScale),Math.round(view.height*view.outerScale),false);
            pixels.draw(stage,new flash.geom.Matrix(view.outerScale,0,0,view.outerScale,-view.left*view.outerScale,-view.top*view.outerScale));
            mobileBridge.drawInputReview(pixels);
            var output:FileStream=new FileStream();var target:File=File.applicationStorageDirectory.resolvePath("connected-startup.png");
            output.open(target,FileMode.WRITE);output.writeBytes(pixels.encode(pixels.rect,new flash.display.PNGEncoderOptions()));output.close();pixels.dispose();
            trace("MOBILE_STARTUP_RENDER path="+target.nativePath);
        }

        private function layout(event:Event = null):void {
            var fullscreen:Boolean = stage.displayState != StageDisplayState.NORMAL;
            var physicalWidth:Number = this.physicalWidth();
            var physicalHeight:Number = this.physicalHeight();
            var box:Object = NativeLayout.calculate(physicalWidth, physicalHeight, true);
            backdrop.graphics.clear(); backdrop.graphics.beginFill(toolbar.night ? 0x0d1728 : 0xaad93d);
            backdrop.graphics.drawRect(box.left,box.top,box.width,box.height); backdrop.graphics.endFill();
            viewport.scaleX = viewport.scaleY = box.gameScale; viewport.x = box.gameX; viewport.y = box.gameY;
            toolbar.visible = false; toolbar.x = box.left; toolbar.y = box.top;
            toolbar.scaleX = toolbar.scaleY = 1 / box.outerScale;
            toolbar.resize(physicalWidth);
            status.scaleX = status.scaleY = 1 / box.outerScale;
            status.x=box.left; status.y=box.top+box.bar;
            status.configure(physicalWidth,physicalHeight-box.barPoints,toolbar.night,toolbar.motion);
            incidentBoard.scaleX=incidentBoard.scaleY=1/box.outerScale;incidentBoard.x=box.left;incidentBoard.y=box.top+box.bar;incidentBoard.configure(physicalWidth,physicalHeight-box.barPoints);
            if(mobileBridge)mobileBridge.configure(box,physicalWidth,physicalHeight);
        }

        private function toolbarAction(action:String):void {
            if(localUIDemo && action!="fullscreen" && action!="incidents" && action!="appearance") return;
            if (action == "fullscreen") { stagePolicy.enforce(); stage.displayState = stage.displayState == StageDisplayState.NORMAL ? StageDisplayState.FULL_SCREEN_INTERACTIVE : StageDisplayState.NORMAL; }
            else if (action == "incidents") incidentBoard.open();
            else if (action == "check-update") checkReleaseUpdate(null,true);
            else if (action == "appearance") layout();
            else if (action == "community") navigateToURL(new URLRequest("https://discord.gg/5uBSQx4yWa"));
            else if (action == "logs") { logExport = new FileReference(); logExport.save(JSON.stringify(NativeServices.diagnostics(), null, 2), "Ekoloko-AIR-diagnostics.json"); }
            else if (action == "repair" || action == "restart") {
                if (action == "repair") {
                    NativeServices.clearAssetCache();
                    // Only the legacy remembered-login settings are reset.
                    // The managed identity cookie and encrypted install ID stay.
                    SharedObject.getLocal("shellData").clear();
                }
                start();
            }
        }

        private function start(afterContentUpdate:Boolean=false):void {
            if (localUIDemo || !initialized || requiredClientUpdate) return;
            starting = true;
            mapUpdateAttempted=afterContentUpdate;
            updateCheckPending=false;updateOffered=false;toolbar.setUpdateAvailable(false);
            NativeServices.clearRuntimeFailure();
            NativeServices.report({stage:"host",reasonCode:"launch_started"});
            NativeServices.stopAssets();
            SoundMixer.stopAll();
            generation++;
            NativeServices.browserId = "";
            cancelRequests();
            disposeGame();
            NativeServices.assetLoadsSuspended = false;
            status.visible = true;
            status.show("בדרך לעולם של אקולוקו", "בודקים את החיבור ומכינים את המשחק…", true, false);
            var current:uint = generation;
            // Keep one signed release consistent with the server version map.
            // Executable objects are verified again before every load; a new
            // game release does not require replacing the host application.
            NativeServices.refreshRelease(function():void {
              if (current != generation) return;
              fetch("/ekoloko/conf/files_version.xml", function(bytes:ByteArray):void {
                if (current != generation) return;
                if (!NativeServices.versionMapCompatible(bytes)) {
                    // Public version metadata only; retain the normal fail-closed update check.
                    var mapDiagnostic:FileStream = new FileStream();
                    mapDiagnostic.open(File.applicationStorageDirectory.resolvePath("public-files-version.xml"), FileMode.WRITE);
                    mapDiagnostic.writeBytes(bytes);mapDiagnostic.close();
                    trace("[MOBILE] public_map_sha256="+NativeServices.sha(bytes));
                    if(mapUpdateAttempted){fail("client_update_required");return;}
                    mapUpdateAttempted=true;
                    NativeServices.checkReleaseUpdate(function(available:Boolean):void {
                        if(current!=generation)return;
                        var update:Object=NativeServices.updateInfo();
                        if(NativeUpdatePolicy.decision(update,BuildInfo.VERSION)=="mandatory") {
                            starting=false;requiredClientUpdate=true;showClientUpdate(update,true);return;
                        }
                        if(available && NativeServices.activateAvailableUpdate()){start(true);return;}
                        fail("mobile_release_pending");
                    },function(error:Error):void{if(current==generation)fail(BuildInfo.PACKED_REVIEW ? "mobile_release_pending" : "client_update_required");});return;
                }
                trace("[AIR] live_release_map=pass main=" + NativeServices.manifest.mainVersion);
                if (localBootstrapCheck) {
                    try {
                        if (BuildInfo.LIVE_RELEASES || Capabilities.cpuArchitecture != "ARM") throw new Error("local_check_mode");
                        if(metadataOnlyCheck){
                            if(rawAssets.downloads!=0 || File.applicationDirectory.resolvePath("air-assets.pack").exists)throw new Error("unexpected_prefetch");
                            trace("LAZY_METADATA_ONLY_PASS downloads=0 fullPack=false native="+Capabilities.cpuArchitecture);NativeApplication.nativeApplication.exit(0);return;
                        }
                        checkLocalAsset(0);
                    } catch (checkError:Error) {
                        trace("BUNDLED_CHECK_FAIL reason=" + checkError.message);
                        NativeApplication.nativeApplication.exit(2);
                    }
                    return;
                }
                NativeServices.checkReleaseUpdate(function(available:Boolean):void {
                    if(current!=generation)return;
                    var policy:Object=NativeServices.updateInfo();
                    if(NativeUpdatePolicy.decision(policy,BuildInfo.VERSION)=="mandatory") {
                        starting=false;requiredClientUpdate=true;showClientUpdate(policy,true);return;
                    }
                    if(available){updateOffered=true;toolbar.setUpdateAvailable(true);}
                    identity(current,null);
                },function(error:Error):void{if(current==generation)identity(current,null);});
              }, true);
            },function(error:Error):void { if(current == generation) { var failure:Object = NativeServices.diagnostics().releaseFailure; fail(failure && /^(release_endpoint_missing|release_access_denied|release_redirect_denied)$/.test(failure.reason) ? failure.reason : "release_update_failed"); } });
            setTimeout(function():void { if (current == generation && starting) fail("bootstrap_timeout"); }, 45000);
        }

        private function checkLocalAsset(index:uint):void {
            var paths:Array=["shell.swf","main.swf","main_components/house.swf"];
            if(index==paths.length) {
                if(cacheRepairCheck && !testCacheCorrupted){
                    testCacheCorrupted=true;
                    var entry:Object=NativeServices.manifest.assets["main.swf"];
                    var file:File=File.applicationStorageDirectory.resolvePath("cached-swfs/"+entry.sha256+".swf");
                    var stream:flash.filesystem.FileStream=new flash.filesystem.FileStream();stream.open(file,flash.filesystem.FileMode.WRITE);stream.writeUTFBytes("broken-test-cache");stream.close();
                    trace("LAZY_CACHE_TEST_CORRUPTED mainOnly=true");checkLocalAsset(1);return;
                }
                if(cacheRepairCheck)trace("LAZY_CACHE_REPAIR_PASS downloads="+rawAssets.downloads+" identityRequested=false");
                trace("LAZY_CHECK_PASS native="+Capabilities.cpuArchitecture+" main="+NativeServices.manifest.mainVersion+" fullPack=false identityRequested=false");
                if(localUIReview){
                    captureLocalUIReview();return;
                }
                NativeApplication.nativeApplication.exit(0);return;
            }
            var path:String=paths[index];
            NativeServices.loadAsset(path,function(bytes:ByteArray):void {
                if(NativeServices.sha(bytes)!=NativeServices.manifest.assets[path].sha256){fail("asset_integrity");return;}
                trace("LAZY_CHECK_ASSET path="+path+" bytes="+bytes.length);
                checkLocalAsset(index+1);
            },function(error:Error):void{fail(error.message);});
        }

        private function checkReleaseUpdate(event:TimerEvent = null, manual:Boolean = false):void {
            if(backgroundAt>0 || starting || updateCheckPending || requiredClientUpdate) return;
            updateCheckPending=true;
            NativeServices.checkReleaseUpdate(function(available:Boolean):void {
                updateCheckPending=false;
                var policy:Object=NativeServices.updateInfo();
                var decision:String=NativeUpdatePolicy.decision(policy,BuildInfo.VERSION);
                if(decision=="mandatory" || decision=="optional") {
                    updateOffered=true;toolbar.setUpdateAvailable(true);
                    if(decision=="mandatory") {
                        requiredClientUpdate=true;NativeServices.stopAssets();cancelRequests();disposeGame();SoundMixer.stopAll();
                    }
                    if(manual || decision=="mandatory") showClientUpdate(policy,decision=="mandatory");
                } else if(available) {
                    toolbar.setUpdateAvailable(true);
                    if(manual) status.showUpdate("עדכון תוכן זמין","נמצאה גרסת תוכן חדשה. אפשר להמשיך במשחק הנוכחי.",null,function():void{status.visible=false;});
                } else if(manual) status.showUpdate("הגרסה מעודכנת","לא נמצא עדכון חדש לגרסה הזו.",null,function():void{status.visible=false;});
            },function(error:Error):void {
                updateCheckPending=false;
                if(manual) status.showUpdate("בדיקת העדכון לא זמינה","לא התקבל כרגע מידע עדכון מאומת מהשרת.",null,function():void{status.visible=false;});
            });
        }
        private function showClientUpdate(policy:Object,required:Boolean):void {
            status.showUpdate(required ? "נדרש עדכון גרסה" : "גרסה חדשה זמינה",
                "גרסה "+policy.version+(required ? " נדרשת כדי להמשיך למשחק." : " זמינה להורדה. אפשר להמשיך בינתיים."),
                function():void{navigateToURL(new URLRequest(BuildInfo.ORIGIN+policy.downloadPath),"_blank");},
                required ? null : function():void{status.visible=false;});
        }

        private function identity(current:uint, previous:String):void {
            fetch("/ekoloko-web/browserIdentity.php", function(text:String):void {
                if (current != generation) return;
                try {
                    var value:Object = JSON.parse(text);
                    if (value.ok !== true || !(value.browserId is String) || !/^[A-Za-z0-9_-]{43}$/.test(value.browserId)) { fail("identity_invalid"); return; }
                    if (previous == null) { identity(current, value.browserId); return; }
                    if (previous != value.browserId) { fail("cookies_unavailable"); return; }
                    NativeServices.browserId = value.browserId;
                    trace("[AIR] managed_cookie_roundtrip=pass");
                    // Presentation assets have their own optional loader error
                    // handling; a missing loading screen must not block login.
                    launch();
                } catch (error:Error) { fail("identity_invalid"); }
            });
        }

        private function launch():void {
            try {
                var current:uint = generation;
                game = new Loader();
                viewport.addChild(game);
                var context:LoaderContext = new LoaderContext(false, new ApplicationDomain(ApplicationDomain.currentDomain));
                context.allowCodeImport = true;
                context.parameters = NativeServices.launchParameters();
                game.contentLoaderInfo.addEventListener(Event.COMPLETE, function(e:Event):void { if (current == generation) { starting = false; status.visible = false; trace("[AIR] shell_loaded=true"); } });
                game.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, function(e:Event):void { if (current == generation) fail("shell_load_error"); });
                NativeServices.loadAsset("shell.swf",function(bytes:ByteArray):void {
                    if (current == generation) game.loadBytes(bytes,context);
                },function(error:Error):void {if(current == generation) fail("shell_load_error");});
            } catch (error:Error) { fail("shell_load_error"); }
        }

        private function fetch(path:String, complete:Function, binary:Boolean = false, method:String = "GET"):void {
            var current:uint = generation;
            var loader:URLLoader = new URLLoader();
            if (binary) loader.dataFormat = URLLoaderDataFormat.BINARY;
            requests.push(loader);
            var code:int = 0;
            loader.addEventListener(HTTPStatusEvent.HTTP_RESPONSE_STATUS, function(e:HTTPStatusEvent):void { code = e.status; });
            loader.addEventListener(ProgressEvent.PROGRESS, function(e:ProgressEvent):void {
                if (current == generation && (e.bytesLoaded > 1048576 || e.bytesTotal > 1048576)) fail("https_response_invalid");
            });
            loader.addEventListener(Event.COMPLETE, function(e:Event):void {
                removeRequest(loader);
                if (current != generation) return;
                if (code != 200 || loader.bytesLoaded > 1048576) { fail(code == 403 && path.indexOf("/ekoloko-web/roomTransition.php") == 0 ? "native_presentation_denied" : "https_response_invalid"); return; }
                complete(binary ? loader.data : String(loader.data));
                loader.data = null;
            });
            var failed:Function = function(e:Event):void { removeRequest(loader); if (current == generation) fail(code == 403 && path.indexOf("/ekoloko-web/roomTransition.php") == 0 ? "native_presentation_denied" : code == 403 ? "https_access_denied" : "https_request_failed"); };
            loader.addEventListener(IOErrorEvent.IO_ERROR, failed);
            loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, failed);
            var request:URLRequest = NativeServices.request(new URLRequest(BuildInfo.ORIGIN + path));
            request.method = method;
            request.useCache = false; request.cacheResponse = false;
            try { loader.load(request); } catch (error:Error) { fail("https_request_failed"); }
        }

        private function removeRequest(loader:URLLoader):void { var i:int = requests.indexOf(loader); if (i >= 0) requests.splice(i, 1); }
        private function cancelRequests():void { for each (var loader:URLLoader in requests) { try { loader.close(); } catch (error:Error) {} } requests = []; }
        private function disposeGame():void {
            // Legacy unload listeners can synchronously reenter error handling.
            if(mobileBridge)mobileBridge.detachGame();
            var previous:Loader = game;
            game = null;
            if (!previous) return;
            if (previous.parent == viewport) viewport.removeChild(previous);
            try { previous.close(); } catch (ignoredClose:Error) {}
            try { previous.unloadAndStop(true); } catch (ignoredUnload:Error) {}
        }
        private function fail(code:String):void {
            if (localBootstrapCheck) {
                trace("BUNDLED_CHECK_FAIL reason=" + code);
                NativeApplication.nativeApplication.exit(2);
                return;
            }
            if (handlingFailure) return;
            handlingFailure = true;
            try {
                starting = false;
                NativeServices.stopAssets();
                SoundMixer.stopAll();
                generation++;
                cancelRequests();
                disposeGame();
                status.visible = true;
                var messages:Object = {
                    asset_access_denied:"השרת חוסם כרגע הורדת רכיב של המשחק. נדרש לאפשר את גישת AIR בשרת.",
                    mobile_release_pending:"עדכון המובייל עדיין לא זמין בשרת. נסו שוב בעוד מעט — אין צורך למחוק את האפליקציה.",
                    mobile_release_incompatible:"עדכון המשחק דורש גרסה חדשה של אפליקציית המובייל.",
                    client_update_required:BuildInfo.LIVE_RELEASES ? "גרסת המשחק בשרת אינה תואמת לעדכון הזמין. אפשר לנסות שוב." : "נדרש עדכון של היישום לגרסת המשחק הנוכחית.",
                    asset_update_required:BuildInfo.LIVE_RELEASES ? "אחד מרכיבי המשחק עדיין לא זמין בעדכון המאומת. אפשר לנסות שוב." : "גרסת הרכיב שהשרת בחר אינה תואמת להתקנה. נדרש עדכון של היישום.",
                    asset_not_installed:BuildInfo.LIVE_RELEASES ? "אחד מרכיבי המשחק אינו כלול בעדכון הזמין. אפשר לנסות שוב." : "רכיב שהמשחק ביקש אינו כלול בגרסה המותקנת.",
                    asset_load_failed:"טעינת אחד מרכיבי המשחק נכשלה. פרטי התקלה נשמרו ביומן.",
                    cookies_unavailable:"שמירת ההתחברות אינה זמינה כרגע.",
                    https_access_denied:"שרת המשחק לא אישר את החיבור.",
                    native_presentation_denied:"שרת המשחק לא מאפשר כרגע לטעון את מסכי המשחק ביישום.",
                    installation_integrity:"קובצי ההתקנה אינם תקינים. יש להתקין מחדש.",
                    release_endpoint_missing:"עדכון המשחק עדיין לא זמין בשרת. פרטי התקלה נשמרו ביומן.",
                    release_access_denied:"שרת המשחק לא אישר את הורדת העדכון. פרטי התקלה נשמרו ביומן.",
                    release_redirect_denied:"לא ניתן להוריד את העדכון מכתובת השרת הנוכחית. פרטי התקלה נשמרו ביומן.",
                    release_update_failed:"לא ניתן לקבל כרגע עדכון מאומת של המשחק. אפשר לנסות שוב."
                };
                status.show("החיבור למשחק לא הושלם", messages[code] || "לא ניתן להפעיל את המשחק כרגע.", false, initialized);
                trace("[AIR] stopped=" + code);
                NativeServices.report({stage:"host", reasonCode:code});
            } finally { handlingFailure = false; }
        }
    }
}
