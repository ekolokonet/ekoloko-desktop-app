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
        private var origin:String;
        private var modulus:String;
        private var cache:NativeAssetCache;
        private var receipt:SharedObject;
        private var queue:Array = [];
        private var active:Array = [];
        private var pending:Object = {};
        private var epoch:uint = 0;
        private var fixtureReader:Function;
        public function NativeReleaseStore(gameOrigin:String, publicModulus:String, directory:File, testReader:Function = null) {
            if (!/^https:\/\/[a-z0-9.-]+$/.test(gameOrigin) || !/^[89a-f][0-9a-f]{511}$/.test(publicModulus)) throw new Error("release_configuration_invalid");
            origin = gameOrigin; modulus = publicModulus;
            fixtureReader = testReader;
            cache = new NativeAssetCache(directory);
            receipt = SharedObject.getLocal("native-release-receipt-v1");
        }
        public function refresh(done:Function, failed:Function):void {
            var current:uint = epoch;
            fetch("current.json", 4096, function(pointerBytes:ByteArray):void {
                try {
                    var point:Object = JSON.parse(pointerBytes.readUTFBytes(pointerBytes.length));
                    NativeReleaseManifest.pointer(point);
                    fetch(point.manifest, NativeReleaseManifest.MAX_MANIFEST, function(bytes:ByteArray):void {
                        fetch(point.signature, 256, function(signature:ByteArray):void {
                            try {
                                var value:Object = NativeReleaseManifest.validate(bytes, signature, point, origin, modulus);
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
                    if (point.generation <= manifest.generation) {done(false);return;}
                    fetch(point.manifest,NativeReleaseManifest.MAX_MANIFEST,function(bytes:ByteArray):void {
                        fetch(point.signature,256,function(signature:ByteArray):void {
                            try {
                                NativeReleaseManifest.validate(bytes,signature,point,origin,modulus);
                                // Notify only. A running session retains its
                                // manifest and classes until an explicit reload.
                                done(true);
                            } catch(invalid:Error) {failed(invalid);}
                        },failed);
                    },failed);
                } catch(invalid:Error) {failed(invalid);}
            },failed);
        }
        public function read(path:String):ByteArray {
            var entry:Object = manifest ? manifest.assets[path] : null;
            if (!entry) throw new Error("asset_not_installed");
            return cache.read(entry);
        }
        public function load(path:String, done:Function, failed:Function):void {
            var entry:Object = manifest ? manifest.assets[path] : null;
            if (!entry) { failed(new Error("asset_not_installed")); return; }
            var bytes:ByteArray = cache.read(entry);
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
            fetch("objects/" + key + ".swf", entry.length, function(data:ByteArray):void {
                try { cache.put(entry, data); }
                catch (invalid:Error) { complete(null, invalid); return; }
                complete(data);
            }, function(error:Error):void { complete(null, error); });
        }
        public function cancel():void {
            epoch++; queue = []; pending = {};
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
            while (active.length < 4 && queue.length) begin(queue.shift());
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
                    if (error) job.failed(error);
                    else if (status != 200 || !bytes || bytes.length > job.limit) job.failed(new Error("release_response_invalid"));
                    else { bytes.position = 0; job.done(bytes); }
                } finally { pump(); }
            };
            loader.addEventListener(HTTPStatusEvent.HTTP_RESPONSE_STATUS,function(e:HTTPStatusEvent):void {status=e.status;});
            loader.addEventListener(ProgressEvent.PROGRESS,function(e:ProgressEvent):void {if(e.bytesLoaded > job.limit || e.bytesTotal > job.limit) finish(new Error("release_response_size"));});
            loader.addEventListener(Event.COMPLETE,function(e:Event):void {finish();});
            loader.addEventListener(IOErrorEvent.IO_ERROR,function(e:Event):void {finish(new Error("release_io"));});
            loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR,function(e:Event):void {finish(new Error("release_security"));});
            var request:URLRequest = new URLRequest(origin + "/ekoloko/air-releases/" + job.path);
            request.manageCookies=true; request.authenticate=true; request.followRedirects=false;
            request.useCache=false; request.cacheResponse=false; request.idleTimeout=20000;
            job.timer=setTimeout(function():void {finish(new Error("release_timeout"));},25000);
            try { loader.load(request); } catch (error:Error) { finish(new Error("release_request_failed")); }
        }
    }
}
