package org.ekoloko.air.aot {
    import flash.display.Loader;
    import flash.utils.ByteArray;
    import flash.filesystem.File;
    import flash.net.URLRequest;
    import flash.system.ApplicationDomain;
    import flash.system.LoaderContext;

    /** Store-target loader, deliberately outside the active interpreter build.
     * The caller supplies the build-pinned packaged index, never a remote index.
     * All executable inputs must be explicit ADT compilation inputs. Downloaded
     * SWF code and unclassified exports are never fallback options here.
     */
    public final class PackagedDisplayLoader extends Loader {
        private var index:Object;
        public function PackagedDisplayLoader(pinnedIndex:Object) {
            super();
            if (!pinnedIndex) throw new ArgumentError("aot_index_missing");
            index = pinnedIndex;
        }
        public function loadAsset(path:String, parameters:Object = null):void {
            var entry:Object = index[path];
            if (!entry) throw new Error("aot_asset_requires_app_update");
            if (entry.blocked !== false) throw new Error("aot_asset_not_reviewed");
            var name:String = entry.file as String;
            if (!name || !/^compiled-content\/[0-9a-f]{64}\.swf$/.test(name))
                throw new Error("aot_packaged_path_invalid");
            var file:File = File.applicationDirectory.resolvePath(name);
            if (!file.exists || file.isDirectory) throw new Error("aot_packaged_asset_missing");
            var context:LoaderContext = new LoaderContext(false, ApplicationDomain.currentDomain);
            context.parameters = parameters;
            super.load(new URLRequest(file.url), context);
        }
        // Every caller must use the pinned logical path API. In particular no
        // generic URL route may accidentally make network SWFs executable.
        override public function load(request:URLRequest, context:LoaderContext = null):void {
            throw new Error("aot_use_packaged_asset_path");
        }
        override public function loadBytes(bytes:ByteArray, context:LoaderContext = null):void {
            throw new Error("aot_runtime_bytecode_disabled");
        }
    }
}
