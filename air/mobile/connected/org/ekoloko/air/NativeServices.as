// Mobile overlay of core NativeServices; source SHA256 d04a13152ed194b0e508eae34b03ad168ac7b62defb400099746abfa0f71be99.
// Adds bounded local timing aggregates; existing integrity and release policies are retained.
package org.ekoloko.air {
    import flash.display.DisplayObject;
    import flash.geom.Point;
    import air.security.Digest;
    import flash.crypto.generateRandomBytes;
    import flash.events.EventDispatcher;
    import flash.events.Event;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.net.URLRequest;
    import flash.net.URLVariables;
    import flash.system.Capabilities;
    import flash.data.EncryptedLocalStore;
    import flash.utils.ByteArray;
    import flash.utils.getTimer;
    import flash.utils.setTimeout;

    public final class NativeServices {
        public static const events:EventDispatcher = new EventDispatcher();
        public static var manifest:Object;
        public static var browserId:String = "";
        public static var reload:Function;
        public static var hostState:Function;
        public static var assetLoadsSuspended:Boolean = false;
        public static var assetGeneration:uint = 0;
        private static var packFile:File;
        private static var installedAssets:Object;
        private static var byHash:Object = {};
        private static var installId:String;
        private static var flowId:String;
        private static var entropyTimes:Array = [];
        private static var localEvents:Array = [];
        private static var callbacks:Object = {};
        private static var assetCache:Object = {};
        private static var cacheOrder:Array = [];
        private static var cacheSize:uint = 0;
        private static var failurePending:Boolean = false;
        private static var assetDiagnosticCount:uint = 0;
        private static var diagnosticsPending:Boolean = false;
        private static var runtimeFailure:Object;
        private static var lastAssetFailure:Object;
        private static var lastReleaseFailure:Object;
        private static var lastOptionalFailure:Object;
        private static var optionalFailures:Array=[],optionalFailureIndex:Object={},optionalFailureTotal:uint=0;
        private static var releases:NativeReleaseStore;

        public static function versionMapCompatible(bytes:ByteArray):Boolean {
            if (manifest && sha(bytes) == manifest.versionConfigSha256) return true;
            var info:Object = BuildInfo;
            if (!("VERSION_MAP_XML" in info) || !("VERSION_MAP_MAIN_SHA" in info)) return false;
            return MobileVersionMapPolicy.compatible(bytes,manifest,String(info.VERSION_MAP_XML),String(info.VERSION_MAP_MAIN_SHA));
        }

        public static function initialize(online:NativeReleaseStore = null):void {
            releases = online;
            if (releases == null) initializeInstalledRelease();
            var stored:ByteArray = EncryptedLocalStore.getItem("installation-v1");
            if (stored == null) {
                stored = generateRandomBytes(32);
                EncryptedLocalStore.setItem("installation-v1", stored);
            }
            if (stored.length != 32) throw new Error("installation_storage");
            installId = "air-" + base64url(stored);
            wipe(stored);
            flowId = uuid();
        }

        private static function initializeInstalledRelease():void {
            readPinnedManifest(true);
        }

        public static function readPinnedManifest(requirePack:Boolean = false):Object {
            var bytes:ByteArray = readFile(File.applicationDirectory.resolvePath("air-manifest.zlib"), 16777216);
            if (sha(bytes) != BuildInfo.MANIFEST_SHA256) throw new Error("manifest_integrity");
            bytes.uncompress();
            if (bytes.length > 33554432) throw new Error("manifest_size");
            manifest = JSON.parse(bytes.readUTFBytes(bytes.length));
            if (manifest.schema != 1 || manifest.origin != BuildInfo.ORIGIN) throw new Error("manifest_schema");
            installedAssets=manifest.assets;
            packFile = File.applicationDirectory.resolvePath("air-assets.pack");
            if (requirePack && (!packFile.exists || packFile.size != manifest.packSize)) throw new Error("pack_integrity");
            for (var path:String in manifest.assets) {
                var entry:Object = manifest.assets[path];
                if (entry.offset < 0 || entry.length < 1 || entry.length > 67108864 || entry.offset + entry.length > manifest.packSize) throw new Error("asset_bounds");
                indexHash(entry.originalSha256,path);
                indexHash(entry.sha256,path);
            }
            return manifest;
        }

        public static function refreshRelease(done:Function, failed:Function):void {
            if (!releases) { done(); return; }
            releases.refresh(function(value:Object):void {
                clearAssetCache(); byHash = {}; manifest = value;
                for (var path:String in manifest.assets) {
                    var entry:Object = manifest.assets[path];
                    indexHash(entry.originalSha256,path); indexHash(entry.sha256,path);
                }
                report({stage:"release",reasonCode:"signed_release_ready"}); done();
            }, failed);
        }

        public static function loadAsset(path:String, done:Function, failed:Function):void {
            if (releases) releases.recoverMissing(path,function():void{releases.load(path,done,failed);},failed);
            else {
                try {
                    var data:ByteArray=readAsset(path),callbackStarted:int=getTimer();
                    try {done(data);} finally {NativePerformance.record("asset_callback",getTimer()-callbackStarted,data.length);}
                } catch (error:Error) { failed(error); }
            }
        }

        public static function activateAvailableUpdate():Boolean { return releases ? releases.activateAvailableUpdate() : false; }

        public static function updateInfo():Object { return releases && releases.availableUpdate ? releases.availableUpdate.clientUpdate : null; }

        public static function checkReleaseUpdate(done:Function, failed:Function):void {
            if (releases) releases.checkUpdate(done,failed); else done(false);
        }

        private static function indexHash(digest:String,path:String):void {
            var previous:String=byHash[digest];
            if(!previous || path.length<previous.length || (path.length==previous.length && path<previous))byHash[digest]=path;
        }

        public static function loadApproved(bytes:ByteArray, done:Function, failed:Function):void {
            if (bytes.length > 67108864) { failed(new Error("asset_size")); return; }
            var digest:String = sha(bytes), path:String = byHash[digest];
            if (!path) { failed(new NativeAssetError("asset_update_required", digest, bytes.length)); return; }
            if(releases) releases.load(path,done,failed,bytes); else loadAsset(path,done,failed);
        }

        public static function readAsset(path:String):ByteArray {
            if (releases) {
                var cached:ByteArray = releases.read(path);
                if (!cached) throw new Error("asset_cache_miss");
                return cached;
            }
            var entry:Object = manifest.assets[path];
            if (entry == null) throw new Error("asset_not_installed");
            return readPackEntry(entry);
        }

        public static function readBundledAsset(path:String, desired:Object):ByteArray {
            var entry:Object=installedAssets ? installedAssets[path] : null;
            if(!entry || entry.sha256 != desired.sha256 || entry.length != desired.length)return null;
            return readPackEntry(entry);
        }
        private static function readPackEntry(entry:Object):ByteArray {
            if(assetCache[entry.sha256]) {
                var previous:int=cacheOrder.indexOf(entry.sha256);
                if(previous>=0)cacheOrder.splice(previous,1);
                cacheOrder.push(entry.sha256);
                var copyStarted:int=getTimer(),copy:ByteArray=copyBytes(assetCache[entry.sha256]);
                NativePerformance.record("asset_cache_hit",getTimer()-copyStarted,copy.length);return copy;
            }
            var readStarted:int=getTimer();
            var stream:FileStream = new FileStream();
            var data:ByteArray = new ByteArray();
            try {
                stream.open(packFile, FileMode.READ);
                stream.position = entry.offset;
                stream.readBytes(data, 0, entry.length);
            } finally { stream.close(); }
            NativePerformance.record("asset_read",getTimer()-readStarted,data.length);
            if (sha(data) != entry.sha256) throw new Error("asset_integrity");
            data.position = 0;
            if (data.length <= 4194304) {
                while (cacheOrder.length && (cacheSize + data.length > 33554432 || cacheOrder.length >= 512)) {
                    var old:String = cacheOrder.shift();
                    cacheSize -= ByteArray(assetCache[old]).length;
                    delete assetCache[old];
                }
                assetCache[entry.sha256] = data; cacheOrder.push(entry.sha256); cacheSize += data.length;
                return copyBytes(data);
            }
            return data;
        }

        public static function approvedBytes(bytes:ByteArray):ByteArray {
            if (bytes.length > 67108864) throw new Error("asset_size");
            var digest:String = sha(bytes);
            var path:String = byHash[digest];
            if (!path) throw new NativeAssetError("asset_update_required", digest, bytes.length);
            return readAsset(path);
        }

        public static function isSwf(bytes:ByteArray):Boolean {
            return bytes.length >= 8 && (bytes[0] == 67 || bytes[0] == 70 || bytes[0] == 90) && bytes[1] == 87 && bytes[2] == 83;
        }

        public static function isRaster(bytes:ByteArray):Boolean {
            if (bytes.length >= 8 && bytes[0] == 137 && bytes[1] == 80 && bytes[2] == 78 && bytes[3] == 71 && bytes[4] == 13 && bytes[5] == 10 && bytes[6] == 26 && bytes[7] == 10) return true;
            if (bytes.length >= 3 && bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255) return true;
            return bytes.length >= 6 && bytes[0] == 71 && bytes[1] == 73 && bytes[2] == 70 && bytes[3] == 56 && (bytes[4] == 55 || bytes[4] == 57) && bytes[5] == 97;
        }

        public static function planAsset(raw:String):Object {
            if (assetLoadsSuspended) throw new Error("client_stopped");
            var url:String = resolve(raw);
            var relative:String = url.substr(BuildInfo.ORIGIN.length);
            var path:String = relative.split("?")[0];
            if (assetDiagnosticCount++ < 80 && /^\/[A-Za-z0-9_./-]{1,180}$/.test(path)) trace("[AIR] asset_path=" + path);
            if (path.indexOf("/ekoloko/loading_page/swfs/") == 0 && /\.swf$/i.test(path)) {
                return {kind:"dynamic", url:BuildInfo.ORIGIN + "/ekoloko-web/roomTransition.php?file=" + encodeURIComponent(path.substr(path.lastIndexOf("/") + 1))};
            }
            // Match the web server's seasonal module selection before looking
            // up a static asset. The returned SWF still has to match an exact
            // installed digest in approvedBytes; no remote code is admitted.
            if (path == "/ekoloko/main_components/communityGroupsChallenge.swf") {
                return {kind:"dynamic", url:BuildInfo.ORIGIN + "/ekoloko-web/communityModule.php"};
            }
            var community:Array = /^\/ekoloko\/community_events\/((?:intro|gauge|images)\/[0-9]+\/[A-Za-z0-9_]+\.swf|menu_bg\/menu_bg_[A-Za-z0-9_]+\.swf)$/.exec(path);
            if (community) {
                return {kind:"dynamic", url:BuildInfo.ORIGIN + "/ekoloko-web/communityAsset.php?path=" + encodeURIComponent(community[1])};
            }
            var campaign:Array = /^\/ekoloko\/donation_campaigns\/targets\/campaign_target_([1-9][0-9]{0,9})\.swf$/.exec(path);
            if (campaign && Number(campaign[1]) <= 2147483647) return {kind:"dynamic", url:BuildInfo.ORIGIN + "/ekoloko-web/campaignContent.php?target=" + campaign[1]};
            if (path == "/ekoloko-web/questArtwork.php") return {kind:"dynamic", url:url, allowImages:true};
            if (path == "/ekoloko-web/roomTransition.php" || path == "/ekoloko-web/communityModule.php" || path == "/ekoloko-web/communityAsset.php" || path == "/ekoloko-web/campaignContent.php") return {kind:"dynamic", url:url};
            // These authenticated image services retain their existing request
            // and cookie contract. Their responses never receive code import.
            if (path == "/ekoloko-web/proofOfPlayImage.php" || path == "/ekoloko-web/captcha.php") return {kind:"image"};
            if (/\.swf$/i.test(path) || path == "/ekoloko/shell") {
                var key:String = path == "/ekoloko/shell" ? "shell.swf" : path.substr("/ekoloko/".length);
                if (path.indexOf("/ekoloko/") != 0 || (!releases && manifest.assets[key] == null)) throw new Error("asset_not_installed");
                return {kind:"installed", path:key};
            }
            if (!/\.(png|jpg|jpeg|gif)(\?|$)/i.test(relative)) throw new Error("display_type_denied");
            return {kind:"image"};
        }

        public static function resolve(raw:String):String {
            if (raw == null || raw.length > 16384 || /[\x00-\x20\x7f\\#]/.test(raw)) throw new Error("request_invalid");
            var host:String = BuildInfo.ORIGIN.substr(8);
            // Upgrade only the configured host's legacy HTTP/default-port
            // spellings. Never follow a redirect or accept another origin.
            if (raw.indexOf("http://" + host + "/") == 0) raw = BuildInfo.ORIGIN + raw.substr(("http://" + host).length);
            else if (raw.indexOf("http://" + host + ":80/") == 0) raw = BuildInfo.ORIGIN + raw.substr(("http://" + host + ":80").length);
            else if (raw.indexOf(BuildInfo.ORIGIN + ":443/") == 0) raw = BuildInfo.ORIGIN + raw.substr((BuildInfo.ORIGIN + ":443").length);
            var path:String;
            if (raw.indexOf(BuildInfo.ORIGIN + "/") == 0) path = raw.substr(BuildInfo.ORIGIN.length);
            else if (raw.indexOf("app:/") == 0) path = "/ekoloko/" + raw.substr(5);
            else if (raw.indexOf("//") == 0 || /^[a-z][a-z0-9+.-]*:/i.test(raw)) throw new Error("origin_denied");
            else path = raw.charAt(0) == "/" ? raw : "/ekoloko/" + raw;
            var question:int = path.indexOf("?");
            var query:String = question >= 0 ? path.substr(question) : "";
            path = question >= 0 ? path.substr(0, question) : path;
            var decoded:String = decodeURIComponent(path);
            if (/[\x00-\x20\x7f\\%?#]/.test(decoded)) throw new Error("path_invalid");
            var parts:Array = [];
            for each (var part:String in decoded.split("/")) {
                if (part == "" || part == ".") continue;
                if (part == "..") { if (parts.length == 0) throw new Error("path_escape"); parts.pop(); }
                else parts.push(part);
            }
            path = "/" + parts.join("/");
            if (!/^\/(ekoloko|ekoloko-web|ekoloko-i18n|ekoloko-json)\//.test(path)) throw new Error("path_denied");
            return BuildInfo.ORIGIN + path + query;
        }

        public static function request(original:URLRequest):URLRequest {
            var req:URLRequest = new URLRequest(resolve(original.url));
            req.method = original.method;
            req.data = original.data;
            req.contentType = original.contentType;
            req.requestHeaders = original.requestHeaders;
            req.manageCookies = true;
            req.followRedirects = false;
            req.authenticate = true;
            req.useCache = original.useCache;
            req.cacheResponse = original.cacheResponse;
            req.idleTimeout = 20000;
            return req;
        }

        public static function parameters(url:String):Object {
            var result:Object = {};
            var index:int = url.indexOf("?");
            if (index >= 0) {
                // Legacy movies use bare cache versions (house.swf?14).
                // URLVariables rejects these with #2101. Only name=value
                // fields are FlashVars; leave cache-only tokens out while
                // retaining AIR's decoding and duplicate-value behavior.
                var fields:Array = [];
                for each (var field:String in url.substr(index + 1).split("&")) {
                    if (field.indexOf("=") >= 0) fields.push(field);
                }
                if (fields.length) {
                    var variables:URLVariables = new URLVariables(fields.join("&"));
                    for (var key:String in variables) if (variables[key] is String) result[key] = variables[key];
                }
            }
            return result;
        }

        public static function navigate(request:URLRequest, target:String = null):void {
            NativeNavigation.open(request, target);
        }

        public static function externalCall(name:String, args:Array):* {
            if(name == "ekolokoNativePerformance") {
                var accepted:Boolean=args.length==1&&NativePerformance.add(args[0]);
                // At most one pending write, no per-packet files or polling timer.
                if(accepted&&!diagnosticsPending) {
                    diagnosticsPending=true;
                    setTimeout(function():void {diagnosticsPending=false;saveDiagnostics();},2000);
                }
                return accepted;
            }
            if(name == "ekolokoNativeSocketDispatch") {
                if(args.length!=2 || !/^[A-Za-z]{1,48}$/.test(String(args[1])))return false;
                if(args[0]=="begin")socketDispatchEvents.push(String(args[1]));
                else if(args[0]=="end" && socketDispatchEvents.length)socketDispatchEvents.pop();
                return true;
            }
            if(name == "ekolokoNativeStagePoint") {
                if(args.length!=3 || !(args[0] is DisplayObject) || !isFinite(Number(args[1])) || !isFinite(Number(args[2])))throw new Error("input_coordinates_invalid");
                var point:Point=DisplayObject(args[0]).localToGlobal(new Point(Number(args[1]),Number(args[2])));
                return {x:point.x,y:point.y};
            }

            // Installed, digest-verified assets still ask their HTML host for
            // its document URL when checking the release's allowed origin.
            // Supply that fixed logical origin in the native host. This is one
            // literal read operation; no JavaScript or arbitrary eval runs.
            if (name == "eval" && args.length == 1 && args[0] === "window.location.href")
                return BuildInfo.ORIGIN + "/ekoloko/login.html";
            if (name == "ek2BrowserEntropyBridgePresent") return true;
            if (name == "ek2GetSecureRandomBase64Url") {
                if (args.length != 1 || args[0] !== 64) throw new Error("entropy_length");
                var now:int = getTimer();
                while (entropyTimes.length && now - entropyTimes[0] > 60000) entropyTimes.shift();
                if (entropyTimes.length >= 16) throw new Error("entropy_rate");
                entropyTimes.push(now);
                var bytes:ByteArray = generateRandomBytes(64);
                try { return base64url(bytes); } finally { wipe(bytes); }
            }
            if (name == "ekolokoGetDeviceTraits") return {browserId:browserId, platform:Capabilities.os, cpuCount:0, memoryMb:0, webglVendor:"", webglRenderer:"", canvasHash:""};
            if (name == "ekolokoNativeInstallId") return installId;
            if (name == "ekolokoBrowserReportEvent") return report(args.length ? args[0] : null);
            if (name == "window.location.reload") { if (reload != null) setTimeout(reload, 0); return null; }
            // These hooks are also no-ops in the current login.html wrapper.
            if (name == "setTableSpacing" || name == "sendGoogleActionRequest" || name == "exitConfirmation") return null;
            // Presence is opt-in in the existing client. Native preview does
            // not publish it; diagnostic payloads never enter stdout.
            if (name == "ekolokoPresence") return null;
            // Browser diagnostic calls are side-effect-free in the native host.
            // In particular Main.onJoinRoom calls console.info before house.init.
            // Accept only these literal methods; never evaluate JS or log arguments.
            if (["console.log","console.info","console.warn","console.error","console.debug","console.trace"].indexOf(name)>=0) return null;
            throw new Error("native_bridge_method_denied");
        }

        public static function addCallback(name:String, callback:Function):void {
            if (name != "removeAd") throw new Error("native_callback_denied");
            callbacks[name] = callback;
        }

        public static function report(input:Object):Boolean {
            if (!input || !(input.stage is String) || !(input.reasonCode is String)) return false;
            if (!/^[a-z_]{1,48}$/.test(input.stage) || !/^[a-z_]{1,64}$/.test(input.reasonCode)) return false;
            if (localEvents.length >= 128) localEvents.shift();
            var event:Object = {stage:input.stage, reason:input.reasonCode, atMs:getTimer()};
            if ((input.stage == "window" || input.stage == "navigation") && hostState != null) {
                try { event.window = hostState(); } catch (ignored:Error) {}
            }
            localEvents.push(event);
            if(input.stage=="main_load" && input.reasonCode=="main_load_completed") gameCallbacksReady=true;
            if (!diagnosticsPending) {
                diagnosticsPending = true;
                setTimeout(function():void { diagnosticsPending = false; saveDiagnostics(); }, 250);
            }
            return true;
        }

        public static function recordReleaseFailure(path:String, status:int, reason:String):void {
            // Fixed publisher paths only; never retain headers, bodies or queries.
            if (lastReleaseFailure != null) return;
            if (!/^(current\.json|releases\/[a-z0-9][a-z0-9_-]{0,79}\/manifest\.(json|sig)|objects\/[0-9a-f]{64}\.swf)$/.test(path)) path = "redacted";
            if (!/^[a-z_]{1,64}$/.test(reason)) reason = "release_request_failed";
            lastReleaseFailure = {path:path, httpStatus:status >= 100 && status <= 599 ? status : 0, reason:reason};
            report({stage:"release", reasonCode:reason});
            saveFailureDiagnostics();
        }

        private static var socketDispatchEvents:Array=[];
        public static function recoverSocketCallback(error:Error):Boolean {
            if(!error || !socketDispatchEvents.length)return false;
            var stack:String=error.getStackTrace();
            if(error.errorID!=1009 && (!stack || stack.indexOf("Error #1009")<0))return false;
            var callbackEvent:String=String(socketDispatchEvents[socketDispatchEvents.length-1]);
            if(["onPublicMessage","onPrivateMessage","onAdminMessage","onModeratorMessage"].indexOf(callbackEvent)<0)return false;
            recordRuntimeFailure(error);
            report({stage:"socket",reasonCode:"socket_callback_null_reference"});
            trace("[AIR] socket_callback_null_reference event="+socketDispatchEvents[socketDispatchEvents.length-1]+" gameContinues=true retrySuggested=true");
            return true;
        }

        public static function recordRuntimeFailure(error:Error,scope:String=null):void {
            if (runtimeFailure != null) return;
            var frames:Array = [];
            var stack:String = error ? error.getStackTrace() : null;
            if (stack) for each (var line:String in stack.split("\n")) {
                var frame:String = line.replace(/^\s+|\s+$/g, "").split("[")[0];
                if (/^at [A-Za-z0-9_.$:/<>()[\] -]{1,160}$/.test(frame) && frames.length < 8) frames.push(frame);
            }
            runtimeFailure = {errorId:error ? error.errorID : 0, frames:frames};
            if(["mobile_frame","mobile_camera","mobile_presentation"].indexOf(scope)>=0)runtimeFailure.scope=scope;
            if(socketDispatchEvents.length) {
                runtimeFailure.callbackEvent=String(socketDispatchEvents[socketDispatchEvents.length-1]);
                trace("[AIR] runtime_callback_event="+runtimeFailure.callbackEvent);
            }
            saveDiagnostics();
            saveFailureDiagnostics();
        }

        private static var gameCallbacksReady:Boolean=false;
        public static function recoverGameCallback(error:Error):Boolean {
            if(!error || !NativeRuntimePolicy.decorativeCallback(error.errorID,error.getStackTrace(),gameCallbacksReady,socketDispatchEvents.length>0))return false;
            if(/^(native_|asset_|release_|installation_)/.test(error.message))return false;
            recordRuntimeFailure(error);
            report({stage:"host",reasonCode:"game_callback_warning"});
            trace("[AIR] game_callback_warning errorId="+error.errorID+" gameContinues=true");
            return true;
        }
        public static function clearRuntimeFailure():void { gameCallbacksReady=false; runtimeFailure = null; lastAssetFailure = null; lastReleaseFailure = null; }

        public static function saveDiagnostics():void {
            writeDiagnostics("last-native-diagnostics.json", diagnostics());
        }

        private static function saveFailureDiagnostics():void {
            // Keep one bounded, sanitized failure record across Retry and
            // application restarts. Successful startup must not erase it.
            var snapshot:Object = diagnostics();
            snapshot.recordedAtUtc = new Date().toUTCString();
            snapshot.manifestSha256 = BuildInfo.MANIFEST_SHA256;
            writeDiagnostics("last-native-failure.json", snapshot);
            // A missing update endpoint on Retry must not erase the earlier
            // game exception needed to diagnose a delayed failure.
            if(snapshot.runtimeFailure)writeDiagnostics("last-native-runtime-failure.json", snapshot);
        }

        private static function writeDiagnostics(name:String, value:Object):void {
            var stream:FileStream = new FileStream();
            try {
                stream.open(File.applicationStorageDirectory.resolvePath(name), FileMode.WRITE);
                stream.writeUTFBytes(JSON.stringify(value, null, 2));
                stream.close();
            } catch (ignored:Error) { try { stream.close(); } catch (alsoIgnored:Error) {} }
        }

        private static function recycleArtFallbackAvailable():Boolean {
            // Older harness BuildInfo classes need no capability field. A future
            // signed Main also cannot inherit a fallback it does not contain.
            var info:Object=BuildInfo;
            return "RECYCLE_ART_FALLBACK_MAIN_SHA" in info && info.RECYCLE_ART_FALLBACK_MAIN_SHA != "" &&
                manifest && manifest.assets && manifest.assets["main.swf"] &&
                manifest.assets["main.swf"].sha256 === info.RECYCLE_ART_FALLBACK_MAIN_SHA;
        }
        public static function optionalAssetPath(path:String):Boolean {
            return (/^\/ekoloko\/recycle_items\/[0-9]+_[0-9]+\.swf$/.test(path) && recycleArtFallbackAvailable()) || /^\/ekoloko\/items\/images\/(EMPTY|HFR|EYE|MTH|SHT|COT|PTS|SHZ|GLS|EAR|NEK|RNG|HOV|HAT|SKT|BDY|MKP)\/\1_[0-9]+\.swf$/.test(path) ||
                /^\/ekoloko\/items\/(HFR|HBK|HED|MTH|EYE|TOR|RAR|LAR|LEG|FET|SHT|LSV|RSV|PTS|SHZ|NEK|EAR|RNG|HOV|SDW|GLS|HAT|HBH|HFH|SKT|MKP|SKF)\/\1_[0-9]+\.swf$/.test(path) ||
                /^\/ekoloko\/loading_page\/swfs\/[A-Za-z0-9_.-]+\.swf$/.test(path) ||
                /^\/ekoloko\/welcome_animations\/animation_[0-9]+\.swf$/.test(path) ||
                /^\/ekoloko-web\/(roomTransition|communityModule|communityAsset|campaignContent|questArtwork)\.php$/.test(path) ||
                path == "/ekoloko/main_components/communityGroupsChallenge.swf" ||
                /^\/ekoloko\/(community_events\/(intro|gauge|images|menu_bg)\/|donation_campaigns\/targets\/)[A-Za-z0-9_./-]+\.swf$/.test(path);
        }

        public static function assetFailure(url:String = "", error:Error = null, status:int = 0):void {
            if (failurePending || assetLoadsSuspended) return;
            var path:String = "bytes";
            try { path = resolve(url).substr(BuildInfo.ORIGIN.length).split("?")[0]; } catch (ignored:Error) {}
            if (!/^\/[A-Za-z0-9_./-]{1,180}$/.test(path)) path = "redacted";
            // Refuse failed bytes in the loader, while preserving the legacy
            // component IOError contract for nonessential presentation assets.
            // Only essential game/code failures stop the whole native host.
            if (optionalAssetPath(path)) {
                var optionalReason:String=error && /^[a-z_]{1,64}$/.test(error.message) ? error.message : "asset_runtime";
                lastOptionalFailure={path:path,reason:optionalReason,httpStatus:status,errorId:error ? error.errorID : 0};
                optionalFailureTotal++;
                var failureKey:String=path+":"+optionalReason+":"+status;
                var detail:Object=optionalFailureIndex[failureKey];
                if(!detail){
                    if(optionalFailures.length>=32){var oldest:Object=optionalFailures.shift();delete optionalFailureIndex[oldest.key];}
                    detail={key:failureKey,path:path,reason:optionalReason,httpStatus:status,count:0};
                    optionalFailureIndex[failureKey]=detail;optionalFailures.push(detail);
                }
                detail.count++;
                trace("[AIR] optional_asset_failed path="+path+" reason="+optionalReason+" http="+status);
                report({stage:"asset_load",reasonCode:"optional_asset_failed"});
                return;
            }
            var reason:String = error && /^[a-z_]{1,64}$/.test(error.message) ? error.message : "asset_runtime";
            lastAssetFailure = {path:path, reason:reason, httpStatus:status, errorId:error ? error.errorID : 0};
            if (error is NativeAssetError) {
                lastAssetFailure.sha256 = NativeAssetError(error).sha256;
                lastAssetFailure.byteLength = NativeAssetError(error).byteLength;
            }
            if (error) recordRuntimeFailure(error);
            trace("[AIR] asset_failure=" + reason + " path=" + path + " http=" + status + " error=" + (error ? error.errorID : 0));
            report({stage:"asset_load", reasonCode:reason});
            saveFailureDiagnostics();
            failurePending = true;
            var current:uint = assetGeneration;
            // Unload the game after the failing loader's callback unwinds.
            setTimeout(function():void { failurePending = false; if (current == assetGeneration) events.dispatchEvent(new Event("assetFailure")); }, 0);
        }

        public static function clearAssetCache():void { assetCache = {}; cacheOrder = []; cacheSize = 0; }

        public static function stopAssets():void {
            assetLoadsSuspended = true;
            assetGeneration++;
            if (releases) releases.cancel();
            events.dispatchEvent(new Event("stopAssets"));
        }

        public static function diagnostics():Object {
            var window:Object = null;
            try { if (hostState != null) window = hostState(); } catch (ignored:Error) {}
            return {version:BuildInfo.VERSION, runtime:Capabilities.version, architecture:Capabilities.cpuArchitecture,
                sourceCommit:manifest ? manifest.sourceCommit : null, window:window, runtimeFailure:runtimeFailure, assetFailure:lastAssetFailure, releaseFailure:lastReleaseFailure, optionalAssetFailure:lastOptionalFailure, optionalAssetFailures:optionalFailures.concat(),optionalAssetFailureCount:optionalFailureTotal, performance:NativePerformance.snapshot(), events:localEvents.concat()};
        }

        public static function launchParameters():Object {
            return {language:"iw", loginAttemptId:uuid(), loginFlowId:flowId};
        }

        public static function sha(bytes:ByteArray):String {
            var hashStarted:int=getTimer();
            var pos:uint = bytes.position;
            var digest:ByteArray;
            try { bytes.position=0; digest=Digest.hash(Digest.SHA256,bytes); }
            finally { bytes.position=pos; }
            var result:String = "";
            for (var i:uint = 0; i < digest.length; i++) result += ("0" + digest[i].toString(16)).substr(-2);
            NativePerformance.record("asset_hash",getTimer()-hashStarted,bytes.length);
            return result;
        }

        private static function uuid():String {
            var bytes:ByteArray = generateRandomBytes(16);
            bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
            var hex:String = "";
            for (var i:uint = 0; i < 16; i++) hex += ("0" + bytes[i].toString(16)).substr(-2);
            wipe(bytes);
            return hex.substr(0,8) + "-" + hex.substr(8,4) + "-" + hex.substr(12,4) + "-" + hex.substr(16,4) + "-" + hex.substr(20);
        }

        private static function base64url(bytes:ByteArray):String {
            var alphabet:String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
            var out:String = "";
            for (var i:uint = 0; i < bytes.length; i += 3) {
                var value:uint = bytes[i] << 16;
                if (i + 1 < bytes.length) value |= bytes[i + 1] << 8;
                if (i + 2 < bytes.length) value |= bytes[i + 2];
                out += alphabet.charAt((value >>> 18) & 63) + alphabet.charAt((value >>> 12) & 63);
                if (i + 1 < bytes.length) out += alphabet.charAt((value >>> 6) & 63);
                if (i + 2 < bytes.length) out += alphabet.charAt(value & 63);
            }
            return out;
        }
        private static function wipe(bytes:ByteArray):void { for (var i:uint = 0; i < bytes.length; i++) bytes[i] = 0; bytes.clear(); }
        private static function copyBytes(bytes:ByteArray):ByteArray { var copy:ByteArray = new ByteArray(); copy.writeBytes(bytes); copy.position = 0; return copy; }
        private static function readFile(file:File, limit:uint):ByteArray {
            if (!file.exists || file.size > limit) throw new Error("file_bounds");
            var stream:FileStream = new FileStream();
            var bytes:ByteArray = new ByteArray();
            try { stream.open(file, FileMode.READ); stream.readBytes(bytes); }
            finally { stream.close(); }
            return bytes;
        }
    }
}
