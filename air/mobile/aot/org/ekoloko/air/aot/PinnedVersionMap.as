package org.ekoloko.air.aot {
    import air.security.Digest;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.utils.ByteArray;
    /** Exact public metadata snapshot for the executable catalog compiled into this binary. */
    public final class PinnedVersionMap {
        public static function matches(url:String, origin:String):Boolean {
            return url.split("?")[0] == origin + "/ekoloko/conf/files_version.xml";
        }
        public static function read(expected:String):ByteArray {
            if (!/^[0-9a-f]{64}$/.test(expected)) throw new Error("aot_version_pin");
            var file:File=File.applicationDirectory.resolvePath("aot-files-version.xml");
            if (!file.exists || file.isDirectory || file.size<1 || file.size>1048576) throw new Error("aot_version_missing");
            var stream:FileStream=new FileStream(), bytes:ByteArray=new ByteArray();
            stream.open(file,FileMode.READ);try {stream.readBytes(bytes);} finally {stream.close();}
            var digest:ByteArray=Digest.hash(Digest.SHA256,bytes), hex:String="";
            digest.position=0;
            while(digest.bytesAvailable){var value:String=digest.readUnsignedByte().toString(16);hex+=(value.length==1?"0":"")+value;}
            if(hex!=expected)throw new Error("aot_version_integrity");
            bytes.position=0;return bytes;
        }
        public static function url(expected:String):String {
            read(expected);return File.applicationDirectory.resolvePath("aot-files-version.xml").url;
        }
    }
}
