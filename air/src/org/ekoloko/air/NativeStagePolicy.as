package org.ekoloko.air {
    import flash.display.Stage;
    import flash.display.StageScaleMode;
    import flash.events.Event;

    // The native host owns presentation. Legacy content still sees its
    // original 960x600 Stage, while AIR renders vectors at screen resolution.
    public final class NativeStagePolicy {
        private var target:Stage;
        private var resized:Function;
        private var applying:Boolean = false;

        public function NativeStagePolicy(stage:Stage, layout:Function) {
            target = stage; resized = layout;
            target.addEventListener(Event.EXIT_FRAME, enforce, false, -1000);
            enforce();
        }

        public function enforce(event:Event = null):void {
            if (applying) return;
            applying = true;
            try {
                var changed:Boolean = false;
                // Main sets a 960x600 hardware-scaled fullscreen rectangle.
                // Clear it so Retina uses native vector rendering instead.
                if (target.fullScreenSourceRect != null) { target.fullScreenSourceRect = null; changed = true; }
                if (target.align != "") { target.align = ""; changed = true; }
                if (target.scaleMode != StageScaleMode.SHOW_ALL) { target.scaleMode = StageScaleMode.SHOW_ALL; changed = true; }
                if (changed && resized != null) resized();
            } finally { applying = false; }
        }
    }
}
