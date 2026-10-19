package org.ekoloko.air {
    import flash.utils.ByteArray;
    import org.ekoloko.air.math.BigInteger;

    public final class NativeReleaseSignature {
        // RSA-2048 / RSASSA-PKCS1-v1_5 / SHA-256. Match the whole encoded
        // message, including DER and padding; a matching digest suffix alone
        // is not a valid signature. The public modulus comes from the host.
        public static function verify(bytes:ByteArray, signature:ByteArray, modulus:String):Boolean {
            if (!bytes || !signature || signature.length != 256 || !/^[89a-f][0-9a-f]{511}$/.test(modulus)) return false;
            var saved:uint = signature.position;
            try {
                signature.position = 0;
                var value:BigInteger = new BigInteger(signature, signature.length, true);
                var key:BigInteger = new BigInteger(modulus, 16);
                if (value.compareTo(key) >= 0 || !/[13579bdf]$/.test(modulus)) return false;
                var encoded:String = value.modPowInt(65537, key).toString(16);
                while (encoded.length < 512) encoded = "0" + encoded;
                var digestInfo:String = "3031300d060960864801650304020105000420" + NativeServices.sha(bytes);
                var expected:String = "0001";
                for (var i:int = 0; i < 256 - 3 - digestInfo.length / 2; i++) expected += "ff";
                expected += "00" + digestInfo;
                return encoded == expected;
            } catch (invalid:Error) { return false; }
            finally { signature.position = saved; }
            return false;
        }
    }
}
