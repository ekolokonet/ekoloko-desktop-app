package org.ekoloko.air {
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.utils.ByteArray;

    public final class NativeAssetCache {
        private var root:File;
        private var touched:Object = {};
        private var quota:Number;
        public function NativeAssetCache(directory:File, maxBytes:Number = 268435456) {
            root = directory; quota = maxBytes; root.createDirectory();
            // Interrupted writes are never executable cache entries. They must
            // not accumulate outside the quota after repeated failed updates.
            for each (var part:File in root.getDirectoryListing()) {
                if (!part.isDirectory && /^[0-9a-f]{64}\.part$/.test(part.name)) {
                    try { part.deleteFile(); } catch (busy:Error) {}
                }
            }
            prune("");
        }
        public function read(entry:Object):ByteArray {
            var file:File = objectFile(entry.sha256);
            if (!file.exists) return null;
            var bytes:ByteArray = new ByteArray(); var stream:FileStream = new FileStream();
            try {
                if (file.isDirectory || file.size != entry.length) throw new Error("cache_invalid");
                stream.open(file, FileMode.READ); stream.readBytes(bytes); stream.close();
                if (NativeServices.sha(bytes) != entry.sha256) throw new Error("cache_invalid");
                touched[entry.sha256] = new Date().time; bytes.position = 0; return bytes;
            } catch (invalid:Error) {
                try { stream.close(); } catch (closed:Error) {}
                if (!file.isDirectory) try { file.deleteFile(); } catch (removeFailed:Error) {}
                return null;
            }
        }
        public function put(entry:Object, bytes:ByteArray):void {
            if (bytes.length != entry.length || NativeServices.sha(bytes) != entry.sha256) throw new Error("asset_integrity");
            var file:File = objectFile(entry.sha256), part:File = root.resolvePath(entry.sha256 + ".part");
            var stream:FileStream = new FileStream();
            try {
                stream.open(part, FileMode.WRITE); stream.writeBytes(bytes); stream.close();
                part.moveTo(file, true); touched[entry.sha256] = new Date().time;
            } finally {
                try { stream.close(); } catch (closed:Error) {}
                if (part.exists && !part.isDirectory) try { part.deleteFile(); } catch (removeFailed:Error) {}
            }
            prune(entry.sha256);
        }
        private function objectFile(sha:String):File {
            if (!/^[0-9a-f]{64}$/.test(sha)) throw new Error("cache_key_invalid");
            return root.resolvePath(sha + ".swf");
        }
        private function prune(keep:String):void {
            var files:Array = [], size:Number = 0;
            for each (var file:File in root.getDirectoryListing()) {
                if (file.isDirectory || !/^[0-9a-f]{64}\.swf$/.test(file.name)) continue;
                var key:String = file.name.substr(0,64); size += file.size;
                files.push({file:file, key:key, used:touched[key] || file.modificationDate.time});
            }
            files.sortOn("used", Array.NUMERIC);
            for each (var item:Object in files) {
                if (size <= quota) break;
                if (item.key == keep) continue;
                var length:Number = item.file.size;
                try { item.file.deleteFile(); size -= length; delete touched[item.key]; } catch (busy:Error) {}
            }
        }
    }
}
