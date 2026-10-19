package org.ekoloko.air.compat.template {
    import flash.net.URLLoader;
    import flash.net.URLRequest;
    import flash.events.Event;
    public class URLLoader extends flash.net.URLLoader {
        public function URLLoader(request:URLRequest = null) {
            super();
            Bridge.api.events.addEventListener("stopAssets", stopped, false, 0, true);
            if (request) load(request);
        }
        override public function load(request:URLRequest):void {
            if (!Bridge.active) return;
            super.load(Bridge.api.request(request));
        }
        private function stopped(event:Event):void { try { close(); } catch (ignored:Error) {} data = null; }
    }
}
