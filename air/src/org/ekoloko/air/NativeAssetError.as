package org.ekoloko.air {
    public final class NativeAssetError extends Error {
        public var sha256:String;
        public var byteLength:uint;
        public function NativeAssetError(reason:String, digest:String, length:uint) {
            super(reason);
            sha256 = digest;
            byteLength = length;
        }
    }
}
