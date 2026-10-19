package org.ekoloko.air.compat.template {
    import flash.media.Sound;
    import flash.media.SoundLoaderContext;
    import flash.net.URLRequest;
    import flash.events.Event;
    public class Sound extends flash.media.Sound {
        public function Sound(stream:URLRequest = null, context:SoundLoaderContext = null) {
            super();
            Bridge.api.events.addEventListener("stopAssets", stopped, false, 0, true);
            if (stream) load(stream, context);
        }
        override public function load(stream:URLRequest, context:SoundLoaderContext = null):void {
            if (!Bridge.active) return;
            super.load(Bridge.api.request(stream), context);
        }
        private function stopped(event:Event):void { try { close(); } catch (ignored:Error) {} }
    }
}
