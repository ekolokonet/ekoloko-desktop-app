package org.ekoloko.air {
    import flash.utils.ByteArray;

    public final class NativeReleaseManifest {
        public static const HOST_PROTOCOL:int = 1;
        public static const MAX_MANIFEST:uint = 16777216;
        public static const MAX_ASSET:uint = 67108864;
        public static function pointer(value:Object):void {
            if (!value || value.schema !== 1 || !releaseId(value.releaseId) || !generation(value.generation) || !digest(value.manifestSha256) ||
                value.manifest !== "releases/" + value.releaseId + "/manifest.json" || value.signature !== "releases/" + value.releaseId + "/manifest.sig") throw new Error("release_pointer_invalid");
        }
        public static function validate(bytes:ByteArray, signature:ByteArray, current:Object, origin:String, modulus:String):Object {
            pointer(current);
            if (bytes.length > MAX_MANIFEST || NativeServices.sha(bytes) != current.manifestSha256 || !NativeReleaseSignature.verify(bytes, signature, modulus)) throw new Error("release_signature_invalid");
            bytes.position = 0;
            var manifest:Object = JSON.parse(bytes.readUTFBytes(bytes.length)); bytes.position = 0;
            if (!manifest || manifest.schema !== 1 || manifest.hostProtocol !== HOST_PROTOCOL || manifest.origin !== origin ||
                manifest.releaseId !== current.releaseId || manifest.generation !== current.generation || manifest.assetRoot !== "objects/" ||
                !/^[0-9a-f]{40}$/.test(manifest.sourceCommit) || !(manifest.mainVersion is String) || !/^[0-9]+$/.test(manifest.mainVersion) ||
                !digest(manifest.versionConfigSha256) || !manifest.assets || manifest.assets is Array) throw new Error("release_manifest_invalid");
            var count:int = 0;
            for (var path:String in manifest.assets) {
                var entry:Object = manifest.assets[path];
                if (++count > 100000 || path.length > 512 || !/\.swf$/.test(path) || /[\x00-\x1f\x7f?#]/.test(path) || /^[a-z][a-z0-9+.-]*:/i.test(path) || path.charAt(0) == "/" || path.indexOf("//") >= 0 || /(^|\/)\.{1,2}(\/|$)/.test(path) ||
                    !entry || !digest(entry.sha256) || !digest(entry.originalSha256) || !(entry.length is Number) || entry.length != Math.floor(entry.length) || entry.length < 1 || entry.length > MAX_ASSET) throw new Error("release_asset_invalid");
            }
            if (!manifest.assets["shell.swf"] || !manifest.assets["main.swf"]) throw new Error("release_entry_missing");
            return manifest;
        }
        private static function digest(value:*):Boolean { return value is String && /^[0-9a-f]{64}$/.test(value); }
        private static function releaseId(value:*):Boolean { return value is String && /^[a-z0-9][a-z0-9_-]{0,79}$/.test(value); }
        private static function generation(value:*):Boolean { return value is Number && value > 0 && value <= 9007199254740991 && value == Math.floor(value); }
    }
}
