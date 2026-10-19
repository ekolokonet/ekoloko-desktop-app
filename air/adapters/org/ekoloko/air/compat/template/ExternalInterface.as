package org.ekoloko.air.compat.template {
    public final class ExternalInterface {
        public static var marshallExceptions:Boolean = false;
        public static function get available():Boolean { return Bridge.active; }
        public static function get objectID():String { return "shell"; }
        public static function call(name:String, ...args):* { return Bridge.active ? Bridge.api.externalCall(name, args) : null; }
        public static function addCallback(name:String, callback:Function):void { if (Bridge.active) Bridge.api.addCallback(name, callback); }
    }
}
