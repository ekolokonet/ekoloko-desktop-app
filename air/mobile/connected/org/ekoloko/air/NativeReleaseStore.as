// Mobile overlay: isolated signed update channel and reuse of installed objects.
package org.ekoloko.air {
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.SecurityErrorEvent;
    import flash.events.HTTPStatusEvent;
    import flash.events.ProgressEvent;
    import flash.filesystem.File;
    import flash.net.URLLoader;
    import flash.net.URLLoaderDataFormat;
    import flash.net.URLRequest;
    import flash.net.SharedObject;
    import flash.utils.ByteArray;
    import flash.utils.setTimeout;
    import flash.utils.clearTimeout;

    public final class NativeReleaseStore {
        public var manifest:Object;
        public var availableUpdate:Object;
        private var availableManifestSha:String;
        private var origin:String;
        private var modulus:String;
        private var cache:NativeAssetCache;
        private var receipt:SharedObject;
        private var queue:Array = [];
        private var active:Array = [];
        private var pending:Object = {};
        private var epoch:uint = 0;
        private var fixtureReader:Function;
        private var fixedManifest:Object;
        private var rawReader:NativeRawAssetReader;
        private var bundledReader:Function;
        private var releaseRoot:String;
        private var mobile:Boolean;
        private var additions:Object = {}, compiledDigests:Object = {};
        private var missingCallbacks:Array = null;
        private var missingChecked:Boolean = false;
        private var compatibilityCandidate:Object, compatibilityError:String;
        private function rememberCompiled(value:Object):void {
            compiledDigests={};additions={};missingChecked=false;compatibilityCandidate=null;
            for each(var entry:Object in value.assets)compiledDigests[entry.sha256]=entry.length;
        }
        private function entryFor(path:String):Object {
            return manifest && manifest.assets[path] ? manifest.assets[path] : additions[path];
        }
        private function validateChannel(value:Object):void {
            if(mobile && value.mobileHostProtocol !== 1) throw new Error("mobile_release_incompatible");
        }
        public function NativeReleaseStore(gameOrigin:String, publicModulus:String, directory:File, testReader:Function = null, mobileChannel:Boolean = false) {
            if (!/^https:\/\/[a-z0-9.-]+$/.test(gameOrigin) || !/^[89a-f][0-9a-f]{511}$/.test(publicModulus)) throw new Error("release_configuration_invalid");
            origin = gameOrigin; modulus = publicModulus; mobile = mobileChannel;
            releaseRoot = mobile ? "/ekoloko/mobile-releases/" : "/ekoloko/air-releases/";
            fixtureReader = testReader;
            cache = new NativeAssetCache(directory);
            receipt = SharedObject.getLocal(mobile ? "mobile-release-receipt-v1" : "native-release-receipt-v1");
        }
        public function usePinnedManifest(value:Object, reader:NativeRawAssetReader):void {
            fixedManifest=value;rawReader=reader;manifest=value;rememberCompiled(value);
        }
        // Seed the installed release without copying the entire pack to the cache.
        // Future signed updates reuse bundled objects only when their digest agrees.
        public function useBundledManifest(value:Object, reader:Function):void {
            fixedManifest=value;manifest=value;bundledReader=reader;rememberCompiled(value);
        }
        public function refresh(done:Function, failed:Function):void {
            if(fixedManifest){done(fixedManifest);return;}
            var current:uint = epoch;
            fetch("current.json", 4096, function(pointerBytes:ByteArray):void {
                try {
                    var point:Object = JSON.parse(pointerBytes.readUTFBytes(pointerBytes.length));
                    NativeReleaseManifest.pointer(point);
                    fetch(point.manifest, NativeReleaseManifest.MAX_MANIFEST, function(bytes:ByteArray):void {
                        fetch(point.signature, 256, function(signature:ByteArray):void {
                            try {
                                var value:Object = NativeReleaseManifest.validate(bytes, signature, point, origin, modulus); validateChannel(value);
                                var previous:Number = Number(receipt.data.generation) || 0;
                                if (value.generation < previous || (value.generation == previous && receipt.data.manifestSha256 !== point.manifestSha256)) throw new Error("release_rollback_denied");
                                if (current != epoch) return;
                                manifest = value;
                                receipt.data.generation = value.generation; receipt.data.manifestSha256 = point.manifestSha256; receipt.flush();
                                done(value);
                            } catch (invalid:Error) { failed(invalid); }
                        }, failed);
                    }, failed);
                } catch (invalid:Error) { failed(invalid); }
            }, failed);
        }
        public function checkUpdate(done:Function, failed:Function):void {

            if (!manifest) { done(false); return; }
            fetch("current.json",4096,function(pointerBytes:ByteArray):void {
                try {
                    var point:Object=JSON.parse(pointerBytes.readUTFBytes(pointerBytes.length));NativeReleaseManifest.pointer(point);
                    if (point.generation <= (Number(manifest.generation)||0)) {done(false);return;}
                    fetch(point.manifest,NativeReleaseManifest.MAX_MANIFEST,function(bytes:ByteArray):void {
                        fetch(point.signature,256,function(signature:ByteArray):void {
                            try {
                                var value:Object=NativeReleaseManifest.validate(bytes,signature,point,origin,modulus); validateChannel(value);
                                // Bundled builds may have generation zero. A high server
                                // generation must not offer an older game's Main version.
                                if(Number(value.mainVersion)<Number(manifest.mainVersion))throw new Error("release_core_rollback_denied");
                                var previous:Number=Number(receipt.data.generation)||0;
                                if(value.generation<previous || (value.generation==previous && receipt.data.manifestSha256!==point.manifestSha256))throw new Error("release_rollback_denied");
                                availableUpdate=value;availableManifestSha=point.manifestSha256;
                                // Notify only. A running session retains its
                                // manifest and classes until an explicit reload.
                                done(true);
                            } catch(invalid:Error) {failed(invalid);}
                        },failed);
                    },failed);
                } catch(invalid:Error) {failed(invalid);}
            },failed);
        }
        public function activateAvailableUpdate():Boolean {
            if(!availableUpdate || !fixedManifest)return false;
            var previous:Number=Number(receipt.data.generation)||0;
            if(availableUpdate.generation<previous || (availableUpdate.generation==previous && receipt.data.manifestSha256!==availableManifestSha))return false;
            if(NativeUpdatePolicy.decision(availableUpdate.clientUpdate,BuildInfo.VERSION)=="mandatory")return false;
            // A signed publication supplies pre-adapted content-addressed objects.
            // Do not re-adapt future Main/Shell with the installer's older templates.
            cancel();rawReader=null;fixedManifest=availableUpdate;manifest=availableUpdate;
            receipt.data.generation=availableUpdate.generation;receipt.data.manifestSha256=availableManifestSha;receipt.flush();
            availableUpdate=null;return true;
        }
        /** One signed metadata lookup per session, shared by concurrent misses.
         * A running session may gain aliases to already compiled objects only.
         * Never replace its core, known assets, or import new executable ABC. */
        public function recoverMissing(path:String, done:Function, failed:Function):void {
            if(entryFor(path)){done();return;}
            var attempt:Function=function():void {
                var candidate:Object=availableUpdate, entry:Object=candidate?candidate.assets[path]:null;
                if(!entry){failed(new Error("asset_not_installed"));return;}
                if(compatibilityCandidate!==candidate){
                    compatibilityCandidate=candidate;compatibilityError=null;
                    if(candidate.mainVersion!==manifest.mainVersion || candidate.versionConfigSha256!==manifest.versionConfigSha256)compatibilityError="asset_core_update_required";
                    else for(var known:String in manifest.assets){
                        var current:Object=manifest.assets[known],other:Object=candidate.assets[known];
                        if(!other||current.sha256!==other.sha256||current.length!==other.length){compatibilityError="asset_core_update_required";break;}
                    }
                }
                if(compatibilityError){failed(new Error(compatibilityError));return;}
                if(compiledDigests[entry.sha256]!==entry.length){failed(new Error("asset_native_update_required"));return;}
                additions[path]=entry;done();
            };
            if(missingChecked){attempt();return;}
            if(missingCallbacks){if(missingCallbacks.length>=128){failed(new Error("asset_recovery_busy"));return;}missingCallbacks.push({done:attempt,failed:failed});return;}
            missingCallbacks=[{done:attempt,failed:failed}];
            var settle:Function=function(error:Error=null):void {
                missingChecked=true;
                var callbacks:Array=missingCallbacks;missingCallbacks=null;
                for each(var callback:Object in callbacks){if(error)callback.failed(error);else callback.done();}
            };
            checkUpdate(function(available:Boolean):void{settle();},function(error:Error):void{settle(error);});
        }
        public function read(path:String):ByteArray {
            var entry:Object = entryFor(path);
            if (!entry) throw new Error("asset_not_installed");
            return readBundled(path,entry) || cache.read(entry);
        }
        public function load(path:String, done:Function, failed:Function, original:ByteArray=null):void {
            var entry:Object = entryFor(path);
            if (!entry) { failed(new Error("asset_not_installed")); return; }
            if(original && original.length==entry.length && NativeServices.sha(original)==entry.sha256) {
                cache.put(entry,original);var approved:ByteArray=new ByteArray();approved.writeBytes(original);approved.position=0;done(approved);return;
            }
            var bytes:ByteArray = readBundled(path,entry);
            if(bytes) { done(bytes);return; }
            bytes = cache.read(entry);
            if (bytes) { done(bytes); return; }
            var key:String = entry.sha256;
            var subscriber:Object = {done:done, failed:failed};
            if (pending[key]) { pending[key].push(subscriber); return; }
            pending[key] = [subscriber];
            var complete:Function = function(data:ByteArray, error:Error = null):void {
                var callbacks:Array = pending[key]; delete pending[key];
                if (!callbacks) return;
                for each (var callback:Object in callbacks) {
                    if (error) callback.failed(error);
                    else {
                        var copy:ByteArray = new ByteArray(); copy.writeBytes(data); copy.position = 0;
                        callback.done(copy);
                    }
                }
            };
            if(rawReader) {
                rawReader.load(path,entry,function(data:ByteArray):void {
                    try{cache.put(entry,data);}catch(invalid:Error){complete(null,invalid);return;}
                    complete(data);
                },function(error:Error):void{complete(null,error);},original);return;
            }
            fetch("objects/" + key + ".swf", entry.length, function(data:ByteArray):void {
                try { cache.put(entry, data); }
                catch (invalid:Error) { complete(null, invalid); return; }
                complete(data);
            }, function(error:Error):void { complete(null, error); });
        }
        private function readBundled(path:String, entry:Object):ByteArray {
            if(bundledReader == null)return null;
            // The bundle is a local cache of approved content, not the only
            // source. A missing/unreadable/corrupt entry can be recovered from
            // the signed release object. Never expose rejected local bytes.
            try {
                var bytes:ByteArray=bundledReader(path,entry);
                if(bytes && bytes.length == entry.length && NativeServices.sha(bytes) == entry.sha256)return bytes;
            } catch(unavailable:Error) {}
            return null;
        }
        public function cancel():void {
            epoch++; queue = []; pending = {}; missingCallbacks=null; missingChecked=false; additions={};
            if(rawReader)rawReader.cancel();
            var previous:Array = active; active = [];
            for each (var job:Object in previous) {
                clearTimeout(job.timer);
                try { job.loader.close(); } catch (closed:Error) {}
                job.loader.data = null;
            }
        }
        private function fetch(path:String, limit:uint, done:Function, failed:Function):void {
            // Both manifest URLs and executable URLs are derived from validated
            // fixed-shape metadata. Redirects and arbitrary origins are disabled.
            if (!/^(current\.json|releases\/[a-z0-9][a-z0-9_-]{0,79}\/manifest\.(json|sig)|objects\/[0-9a-f]{64}\.swf)$/.test(path)) { failed(new Error("release_path_invalid")); return; }
            if (fixtureReader != null) {
                var current:uint=epoch;
                fixtureReader(path,limit,function(bytes:ByteArray):void {
                    if(current!=epoch)return;
                    if(!bytes || bytes.length>limit){failed(new Error("release_response_size"));return;}
                    bytes.position=0;done(bytes);
                },function(error:Error):void {if(current==epoch)failed(error);});
                return;
            }
            if (queue.length >= 1024) { failed(new Error("release_queue_full")); return; }
            queue.push({path:path, limit:limit, done:done, failed:failed, epoch:epoch}); pump();
        }
        private function pump():void {
            while (active.length < (mobile ? 2 : 4) && queue.length) begin(queue.shift());
        }
        public static function responseReason(status:int, fallback:String):String {
            if (status == 404) return "release_endpoint_missing";
            if (status == 401 || status == 403) return "release_access_denied";
            if (status >= 300 && status < 400) return "release_redirect_denied";
            return fallback;
        }
        private function begin(job:Object):void {
            var loader:URLLoader = new URLLoader(); loader.dataFormat = URLLoaderDataFormat.BINARY;
            job.loader = loader; active.push(job); var status:int = 0; var settled:Boolean = false;
            var finish:Function = function(error:Error = null):void {
                if (settled || job.epoch != epoch) return; settled = true;
                clearTimeout(job.timer);
                var index:int = active.indexOf(job); if (index >= 0) active.splice(index,1);
                try { loader.close(); } catch (closed:Error) {}
                var bytes:ByteArray = loader.data as ByteArray; loader.data = null;
                try {
                    if (error) { NativeServices.recordReleaseFailure(job.path,status,responseReason(status,error.message)); job.failed(error); }
                    else if (status != 200 || !bytes || bytes.length > job.limit) {
                        var reason:String = responseReason(status,"release_response_invalid");
                        NativeServices.recordReleaseFailure(job.path,status,reason); job.failed(new Error(reason));
                    }
                    else { bytes.position = 0; job.done(bytes); }
                } finally { pump(); }
            };
            loader.addEventListener(HTTPStatusEvent.HTTP_RESPONSE_STATUS,function(e:HTTPStatusEvent):void {status=e.status;});
            loader.addEventListener(ProgressEvent.PROGRESS,function(e:ProgressEvent):void {if(e.bytesLoaded > job.limit || e.bytesTotal > job.limit) finish(new Error("release_response_size"));});
            loader.addEventListener(Event.COMPLETE,function(e:Event):void {finish();});
            loader.addEventListener(IOErrorEvent.IO_ERROR,function(e:Event):void {finish(new Error("release_io"));});
            loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR,function(e:Event):void {finish(new Error("release_security"));});
            var request:URLRequest = new URLRequest(origin + releaseRoot + job.path);
            request.manageCookies=true; request.authenticate=true; request.followRedirects=false;
            request.useCache=false; request.cacheResponse=false; request.idleTimeout=20000;
            job.timer=setTimeout(function():void {finish(new Error("release_timeout"));},25000);
            try { loader.load(request); } catch (error:Error) { finish(new Error("release_request_failed")); }
        }
    }
}
