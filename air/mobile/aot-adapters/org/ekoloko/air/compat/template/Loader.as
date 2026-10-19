package org.ekoloko.air.compat.template {
    import flash.display.Loader;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.SecurityErrorEvent;
    import flash.events.ProgressEvent;
    import flash.events.HTTPStatusEvent;
    import flash.net.URLLoader;
    import flash.net.URLLoaderDataFormat;
    import flash.net.URLRequest;
    import flash.system.ApplicationDomain;
    import flash.system.LoaderContext;
    import flash.utils.ByteArray;
    import flash.utils.setTimeout;

    public class Loader extends flash.display.Loader {
        private var pending:flash.net.URLLoader;
        private var generation:uint = 0;
        // AOT executable definitions are compiled into one application domain.

        public function Loader() {
            super();
            Bridge.api.events.addEventListener("stopAssets", stopped, false, 0, true);
        }

        override public function load(request:URLRequest, context:LoaderContext = null):void {
            cancelPending();
            if (!Bridge.active) return;
            var current:uint = generation;
            try {
                var plan:Object = Bridge.api.planAsset(request.url);
                if (plan.kind == "installed") {
                    loadPackaged(String(Bridge.api.packagedURL(plan.path)), context, request.url);
                } else if (plan.kind == "dynamic") {
                    var download:flash.net.URLLoader = new flash.net.URLLoader();
                    pending = download;
                    var status:int = 0;
                    download.dataFormat = URLLoaderDataFormat.BINARY;
                    download.addEventListener(HTTPStatusEvent.HTTP_RESPONSE_STATUS, function(e:HTTPStatusEvent):void { status = e.status; });
                    download.addEventListener(ProgressEvent.PROGRESS, function(e:ProgressEvent):void {
                        if (current == generation && (e.bytesLoaded > 67108864 || e.bytesTotal > 67108864)) { cancelPending(); fail(request.url, new Error("asset_size"), status); }
                    });
                    download.addEventListener(Event.COMPLETE, function(e:Event):void {
                        if (current != generation) return;
                        pending = null;
                        try {
                            if (status != 200) throw new Error("asset_response");
                            var bytes:ByteArray = download.data as ByteArray;
                            if (Bridge.api.isSwf(bytes)) loadInstalled(bytes, context, request.url);
                            else if (plan.allowImages === true && Bridge.api.isRaster(bytes)) loadImage(bytes, context);
                            else throw new Error("asset_display_type_denied");
                        }
                        catch (error:Error) { fail(request.url, error, status); }
                        download.data = null;
                    });
                    download.addEventListener(IOErrorEvent.IO_ERROR, function(e:Event):void { if (current == generation) { pending = null; fail(request.url, new Error("asset_io"), status); } });
                    download.addEventListener(SecurityErrorEvent.SECURITY_ERROR, function(e:Event):void { if (current == generation) { pending = null; fail(request.url, new Error("asset_security"), status); } });
                    download.load(Bridge.api.request(new URLRequest(plan.url)));
                    setTimeout(function():void { if (current == generation && pending == download) { cancelPending(); fail(request.url, new Error("asset_timeout"), status); } }, 20000);
                } else {
                    var safe:LoaderContext = context || new LoaderContext();
                    safe.allowCodeImport = false;
                    super.load(Bridge.api.request(request), safe);
                }
            } catch (error:Error) { fail(request.url, error); }
        }

        override public function loadBytes(bytes:ByteArray, context:LoaderContext = null):void {
            cancelPending();
            if (!Bridge.active) return;
            var current:uint = generation;
            try {
                if (bytes.length > 67108864) throw new Error("asset_size");
                if (Bridge.api.isSwf(bytes)) loadInstalled(bytes,context,"");
                else loadImage(bytes, context);
            } catch (error:Error) { fail("", error); }
        }

        private function loadImage(bytes:ByteArray, context:LoaderContext):void {
            var safe:LoaderContext = context || new LoaderContext();
            safe.allowCodeImport = false;
            super.loadBytes(bytes, safe);
        }

        private function loadInstalled(bytes:ByteArray, context:LoaderContext, url:String):void {
            if (!Bridge.active) return;
            loadPackaged(String(Bridge.api.packagedURLForBytes(bytes)), context, url);
        }

        private function loadPackaged(packagedURL:String, context:LoaderContext, sourceURL:String):void {
            if (!Bridge.active) return;
            var safe:LoaderContext = new LoaderContext(false, ApplicationDomain.currentDomain);
            safe.parameters = context && context.parameters ? context.parameters : Bridge.api.parameters(sourceURL);
            // The host returns only build-pinned package files. Never import
            // downloaded bytecode, including a previously approved SWF response.
            super.load(new URLRequest(packagedURL), safe);
        }

        private function fail(url:String, error:Error, status:int = 0):void {
            if (!Bridge.active) return;
            // ImageItemData already retries missing item art and creates its
            // installed NoImageItem fallback. Keep that component's I/O contract.
            if (!isOptionalMissingItemImage(url, error, status)) Bridge.api.assetFailure(url, error, status);
            var current:uint = generation;
            setTimeout(function():void { if (current == generation && Bridge.active) signalLoadError(); }, 0);
        }

        private function signalLoadError():void {
            // AIR forbids dispatchEvent on LoaderInfo (#2118). Let its decoder
            // emit the real asynchronous IOError with the original target.
            // This fixed invalid byte is neither executable content nor a
            // network request; no rejected server bytes reach the decoder.
            var invalid:ByteArray = new ByteArray(); invalid.writeByte(0); invalid.position = 0;
            var safe:LoaderContext = new LoaderContext(); safe.allowCodeImport = false;
            super.loadBytes(invalid, safe);
        }

        private function isOptionalMissingItemImage(url:String, error:Error, status:int):Boolean {
            if (!error || error.message != "asset_not_installed" || status != 0) return false;
            try {
                // Reuse the origin and path validation that already rejected the
                // unavailable installed asset. This performs no network request.
                var resolved:String = Bridge.api.resolve(url);
                var path:String = resolved.substr(Bridge.api.manifest.origin.length).split("?")[0];
                return /^\/ekoloko\/items\/images\/(EMPTY|HFR|EYE|MTH|SHT|COT|PTS|SHZ|GLS|EAR|NEK|RNG|HOV|HAT|SKT|BDY|MKP)\/\1_[0-9]+\.swf$/.test(path);
            } catch (invalid:Error) { return false; }
        }

        private function stopped(event:Event):void {
            cancelPending();
            try { super.unloadAndStop(true); } catch (ignored:Error) {}
        }

        private function cancelPending():void {
            generation++;
            if (pending) { try { pending.close(); } catch (error:Error) {} pending.data = null; pending = null; }
        }
        override public function close():void { cancelPending(); super.close(); }
        override public function unload():void { cancelPending(); super.unload(); }
        override public function unloadAndStop(gc:Boolean = true):void { cancelPending(); super.unloadAndStop(gc); }
    }
}
