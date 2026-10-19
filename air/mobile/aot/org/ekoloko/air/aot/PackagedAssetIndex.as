package org.ekoloko.air.aot {
    import air.security.Digest;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.utils.ByteArray;

    /** Immutable executable catalog, pinned by the compiled host. No network fallback. */
    public final class PackagedAssetIndex {
        private var entries:Object;
        private var hashes:Object = {};
        private var ambiguous:Object = {};
        public function PackagedAssetIndex(expectedSHA256:String) {
            if (!/^[0-9a-f]{64}$/.test(expectedSHA256)) throw new Error("aot_index_pin");
            var file:File=File.applicationDirectory.resolvePath("aot-index.json");
            if (!file.exists || file.size>16777216) throw new Error("aot_index_missing");
            var bytes:ByteArray=new ByteArray(),stream:FileStream=new FileStream();
            stream.open(file,FileMode.READ);try {stream.readBytes(bytes);} finally {stream.close();}
            if (hash(bytes)!=expectedSHA256) throw new Error("aot_index_integrity");
            bytes.position=0;var index:Object=JSON.parse(bytes.readUTFBytes(bytes.length));
            if(index.schema!==1 || !index.paths)throw new Error("aot_index_schema");
            entries=index.paths;
            for(var path:String in entries){var row:Object=entries[path];for each(var digest:String in row.acceptedSourceHashes){
                if(!/^[0-9a-f]{64}$/.test(digest))throw new Error("aot_index_hash");
                if(hashes[digest] && entries[hashes[digest]].file!==row.file)ambiguous[digest]=true;
                if(!hashes[digest] || row.reviewed===true)hashes[digest]=path;
            }}
        }
        private static function hash(bytes:ByteArray):String {
            var position:uint=bytes.position,result:ByteArray;
            try {bytes.position=0;result=Digest.hash(Digest.SHA256,bytes);} finally {bytes.position=position;}
            var hex:String="";result.position=0;
            while(result.bytesAvailable){var value:String=result.readUnsignedByte().toString(16);hex+=(value.length==1?"0":"")+value;}
            return hex;
        }
        public function url(path:String):String {
            var row:Object=entries[path];
            if(!row)throw new Error("aot_asset_requires_app_update");
            if(row.reviewed!==true)throw new Error("aot_asset_not_reviewed");
            if(!/^compiled-content\/[0-9a-f]{64}\.swf$/.test(String(row.file)))throw new Error("aot_asset_path");
            var file:File=File.applicationDirectory.resolvePath(row.file);
            if(!file.exists || file.isDirectory)throw new Error("aot_asset_missing");
            if(file.size>67108864 || !/^[0-9a-f]{64}$/.test(String(row.outputSha256)))throw new Error("aot_asset_integrity");
            var bytes:ByteArray=new ByteArray(),stream:FileStream=new FileStream();
            stream.open(file,FileMode.READ);try {stream.readBytes(bytes);} finally {stream.close();}
            if(hash(bytes)!=row.outputSha256)throw new Error("aot_asset_integrity");
            return file.url;
        }
        public function urlForBytes(bytes:ByteArray):String {
            if(!bytes || bytes.length>67108864)throw new Error("aot_asset_size");
            var position:uint=bytes.position,digest:String;
            try {bytes.position=0;digest=hash(bytes);} finally {bytes.position=position;}
            if(ambiguous[digest])throw new Error("aot_index_hash_ambiguous");
            var path:String=hashes[digest];
            if(!path)throw new Error("aot_asset_requires_app_update");
            return url(path);
        }
    }
}
