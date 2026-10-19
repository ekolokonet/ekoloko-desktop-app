package org.ekoloko.air.compat.template {
    import flash.system.ApplicationDomain;
    public final class Bridge {
        private static const run:uint = api.assetGeneration;
        public static function get active():Boolean {
            return run == api.assetGeneration && !api.assetLoadsSuspended;
        }
        public static function get api():Object {
            return ApplicationDomain.currentDomain.getDefinition("org.ekoloko.air.NativeServices");
        }
    }
}
