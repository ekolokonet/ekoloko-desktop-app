package org.ekoloko.air.compat.template {
    import flash.system.Security;
    public final class Security {
        public static const APPLICATION:String = "application";
        public static const REMOTE:String = "remote";
        public static const LOCAL_TRUSTED:String = "localTrusted";
        public static const LOCAL_WITH_FILE:String = "localWithFile";
        public static const LOCAL_WITH_NETWORK:String = "localWithNetwork";
        public static function get sandboxType():String { return flash.system.Security.sandboxType; }
        public static function get exactSettings():Boolean { return flash.system.Security.exactSettings; }
        public static function set exactSettings(value:Boolean):void { flash.system.Security.exactSettings = value; }
        // All executable modules are installed application code. There is no
        // remote sandbox to grant cross-scripting access to in this bundle.
        public static function allowDomain(...domains):void { requireApplication(); }
        public static function allowInsecureDomain(...domains):void { requireApplication(); }
        public static function loadPolicyFile(url:String):void { flash.system.Security.loadPolicyFile(url); }
        public static function showSettings(panel:String = "default"):void { flash.system.Security.showSettings(panel); }
        private static function requireApplication():void {
            if (sandboxType != APPLICATION) throw new SecurityError("Installed AIR content required");
        }
    }
}
