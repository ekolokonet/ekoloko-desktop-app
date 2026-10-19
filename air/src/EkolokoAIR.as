package {
    import flash.desktop.NativeApplication;
    import flash.filesystem.File;
    import flash.display.Loader;
    import flash.display.Sprite;
    import flash.display.StageAlign;
    import flash.display.StageScaleMode;
    import flash.display.StageDisplayState;
    import flash.events.Event;
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
    import flash.utils.ByteArray;
    import flash.utils.Timer;
    import flash.geom.Rectangle;
    import org.ekoloko.air.NativeServices;
    import org.ekoloko.air.BuildInfo;
    import org.ekoloko.air.NativeToolbar;
    import org.ekoloko.air.NativeLayout;
    import org.ekoloko.air.NativeStatus;
    import org.ekoloko.air.NativeStagePolicy;
    import org.ekoloko.air.NativeReleaseStore;

    [SWF(width="960", height="600", frameRate="24", backgroundColor="#AAD93D")]
    public class EkolokoAIR extends Sprite {
        private var game:Loader;
        private var viewport:Sprite = new Sprite();
        private var stagePolicy:NativeStagePolicy;
        private var status:NativeStatus;
        private var generation:uint = 0;
        private var requests:Array = [];
        private var initialized:Boolean = false;
        private var starting:Boolean = false;
        private var backdrop:Sprite = new Sprite();
        private var toolbar:NativeToolbar;
        private var chromeWidth:Number;
        private var chromeHeight:Number;
        private var logExport:FileReference;
        private var handlingFailure:Boolean = false;
        private var updateTimer:Timer;
        private var updateCheckPending:Boolean = false;
        private var updateOffered:Boolean = false;

        public function EkolokoAIR() {
            // Establish the native window's visibility once, before loading
            // any legacy document. Movie swaps must not own this lifecycle.
            stage.nativeWindow.visible = true;
            // Match login.html's 960x600 (8:5) embed. AIR exposes artwork
            // outside a loaded movie's declared Stage unless it is clipped.
            // Keep Flash's native SHOW_ALL coordinates so game code still sees
            // the same logical Stage dimensions as the original HTML embed.
            stage.scaleMode = StageScaleMode.NO_SCALE;
            chromeWidth = stage.nativeWindow.width - stage.stageWidth;
            chromeHeight = stage.nativeWindow.height - stage.stageHeight;
            stage.align = "";
            stage.scaleMode = StageScaleMode.SHOW_ALL;
            addChild(backdrop);
            viewport.scrollRect = new Rectangle(0, 0, 960, 600);
            addChild(viewport);
            status = new NativeStatus(function():void {if(initialized && !starting) start();});
            addChild(status);
            toolbar = new NativeToolbar(toolbarAction); addChild(toolbar);
            // Numeric presentation state distinguishes a failed movie swap
            // from fullscreen, minimization or a closed native window.
            NativeServices.hostState = function():Object {
                return {width:stage.nativeWindow.width, height:stage.nativeWindow.height,
                    visible:stage.nativeWindow.visible, nativeState:stage.nativeWindow.displayState,
                    displayState:stage.displayState, stageWidth:stage.stageWidth, stageHeight:stage.stageHeight,
                    scaleMode:stage.scaleMode, align:stage.align,
                    focused:NativeApplication.nativeApplication.activeWindow == stage.nativeWindow,
                    sourceRect:stage.fullScreenSourceRect == null ? null : {width:stage.fullScreenSourceRect.width,height:stage.fullScreenSourceRect.height},
                    gameAttached:game != null && game.parent == viewport,
                    viewportX:viewport.x, viewportY:viewport.y, viewportScale:viewport.scaleX};
            };
            stage.nativeWindow.addEventListener(NativeWindowBoundsEvent.RESIZE, layout);
            stage.addEventListener(FullScreenEvent.FULL_SCREEN, layout);
            stage.addEventListener(FullScreenEvent.FULL_SCREEN, function(e:FullScreenEvent):void {
                NativeServices.report({stage:"window",reasonCode:e.fullScreen ? "fullscreen_entered" : "fullscreen_left"});
            });
            stage.nativeWindow.addEventListener(Event.ACTIVATE, function(e:Event):void { NativeServices.report({stage:"window",reasonCode:"window_activated"}); });
            stage.nativeWindow.addEventListener(Event.DEACTIVATE, function(e:Event):void { NativeServices.report({stage:"window",reasonCode:"window_deactivated"}); });
            stage.nativeWindow.addEventListener(NativeWindowDisplayStateEvent.DISPLAY_STATE_CHANGE, function(e:NativeWindowDisplayStateEvent):void {
                NativeServices.report({stage:"window",reasonCode:"native_display_state_changed"});
            });
            stagePolicy = new NativeStagePolicy(stage, layout);
            stage.addEventListener(KeyboardEvent.KEY_DOWN, function(e:KeyboardEvent):void {
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
                fail("runtime_error");
            });
            NativeApplication.nativeApplication.addEventListener(Event.EXITING,function(e:Event):void {
                NativeServices.report({stage:"host",reasonCode:"application_exit_requested"});NativeServices.saveDiagnostics();
            });
            NativeServices.events.addEventListener("assetFailure", function(e:Event):void {
                var failure:Object = NativeServices.diagnostics().assetFailure;
                var reason:String = failure ? failure.reason : "";
                fail(reason == "asset_update_required" || reason == "asset_not_installed" ? reason : "asset_load_failed");
            });
            try {
                NativeServices.initialize(BuildInfo.LIVE_RELEASES ? new NativeReleaseStore(BuildInfo.ORIGIN, BuildInfo.RELEASE_PUBLIC_MODULUS,
                    File.applicationStorageDirectory.resolvePath("cached-swfs")) : null);
                initialized = true;
                NativeServices.reload = start;
                if (BuildInfo.LIVE_RELEASES) {
                    updateTimer = new Timer(60000);
                    updateTimer.addEventListener(TimerEvent.TIMER,checkReleaseUpdate); updateTimer.start();
                }
                trace("[AIR] native=" + Capabilities.cpuArchitecture + " runtime=" + Capabilities.version + " release=" + BuildInfo.VERSION);
                start();
            } catch (error:Error) { fail("installation_integrity"); }
        }

        private function layout(event:Event = null):void {
            var fullscreen:Boolean = stage.displayState != StageDisplayState.NORMAL;
            var physicalWidth:Number = fullscreen ? stage.fullScreenWidth : stage.nativeWindow.width - chromeWidth;
            var physicalHeight:Number = fullscreen ? stage.fullScreenHeight : stage.nativeWindow.height - chromeHeight;
            var box:Object = NativeLayout.calculate(physicalWidth, physicalHeight, fullscreen);
            backdrop.graphics.clear(); backdrop.graphics.beginFill(toolbar.night ? 0x0d1728 : 0xaad93d);
            backdrop.graphics.drawRect(box.left,box.top,box.width,box.height); backdrop.graphics.endFill();
            viewport.scaleX = viewport.scaleY = box.gameScale; viewport.x = box.gameX; viewport.y = box.gameY;
            toolbar.visible = !fullscreen; toolbar.x = box.left; toolbar.y = box.top;
            toolbar.scaleX = toolbar.scaleY = 1 / box.outerScale;
            toolbar.resize(physicalWidth);
            status.scaleX = status.scaleY = 1 / box.outerScale;
            status.x=box.left; status.y=box.top+box.bar;
            status.configure(physicalWidth,physicalHeight-box.barPoints,toolbar.night,toolbar.motion);
        }

        private function toolbarAction(action:String):void {
            if (action == "fullscreen") { stagePolicy.enforce(); stage.displayState = stage.displayState == StageDisplayState.NORMAL ? StageDisplayState.FULL_SCREEN_INTERACTIVE : StageDisplayState.NORMAL; }
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

        private function start():void {
            if (!initialized) return;
            starting = true;
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
                if (NativeServices.sha(bytes) != NativeServices.manifest.versionConfigSha256) { fail("client_update_required"); return; }
                trace("[AIR] live_release_map=pass main=" + NativeServices.manifest.mainVersion);
                identity(current, null);
              }, true);
            },function(error:Error):void { if(current == generation) fail("release_update_failed"); });
            setTimeout(function():void { if (current == generation && starting) fail("bootstrap_timeout"); }, 45000);
        }

        private function checkReleaseUpdate(event:TimerEvent):void {
            if (!initialized || starting || updateCheckPending || updateOffered) return;
            updateCheckPending=true;var current:uint=generation;
            NativeServices.checkReleaseUpdate(function(available:Boolean):void {
                if(current!=generation)return;updateCheckPending=false;
                if(available){updateOffered=true;toolbar.setUpdateAvailable(true);NativeServices.report({stage:"release",reasonCode:"game_update_available"});}
            },function(error:Error):void {if(current==generation)updateCheckPending=false;});
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
                    // Check the real public presentation route before starting
                    // the legacy timelines; a server denial must stay a clear,
                    // responsive launch error rather than half-loaded artwork.
                    fetch("/ekoloko-web/roomTransition.php?file=bongo_iw.swf", function(unused:*):void {
                        if (current == generation) launch();
                    }, false, "HEAD");
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
            var previous:Loader = game;
            game = null;
            if (!previous) return;
            if (previous.parent == viewport) viewport.removeChild(previous);
            try { previous.close(); } catch (ignoredClose:Error) {}
            try { previous.unloadAndStop(true); } catch (ignoredUnload:Error) {}
        }
        private function fail(code:String):void {
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
                    client_update_required:BuildInfo.LIVE_RELEASES ? "גרסת המשחק בשרת אינה תואמת לעדכון הזמין. אפשר לנסות שוב." : "נדרש עדכון של היישום לגרסת המשחק הנוכחית.",
                    asset_update_required:BuildInfo.LIVE_RELEASES ? "אחד מרכיבי המשחק עדיין לא זמין בעדכון המאומת. אפשר לנסות שוב." : "גרסת הרכיב שהשרת בחר אינה תואמת להתקנה. נדרש עדכון של היישום.",
                    asset_not_installed:BuildInfo.LIVE_RELEASES ? "אחד מרכיבי המשחק אינו כלול בעדכון הזמין. אפשר לנסות שוב." : "רכיב שהמשחק ביקש אינו כלול בגרסה המותקנת.",
                    asset_load_failed:"טעינת אחד מרכיבי המשחק נכשלה. פרטי התקלה נשמרו ביומן.",
                    cookies_unavailable:"שמירת ההתחברות אינה זמינה כרגע.",
                    https_access_denied:"שרת המשחק לא אישר את החיבור.",
                    native_presentation_denied:"שרת המשחק לא מאפשר כרגע לטעון את מסכי המשחק ביישום.",
                    installation_integrity:"קובצי ההתקנה אינם תקינים. יש להתקין מחדש.",
                    release_update_failed:"לא ניתן לקבל כרגע עדכון מאומת של המשחק. אפשר לנסות שוב."
                };
                status.show("החיבור למשחק לא הושלם", messages[code] || "לא ניתן להפעיל את המשחק כרגע.", false, initialized);
                trace("[AIR] stopped=" + code);
                NativeServices.report({stage:"host", reasonCode:code});
            } finally { handlingFailure = false; }
        }
    }
}
