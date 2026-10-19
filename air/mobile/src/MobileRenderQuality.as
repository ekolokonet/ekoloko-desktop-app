package {
    import flash.display.Stage;
    import flash.display.StageQuality;
    import flash.events.Event;

    /** Choose by runtime read-back, since AIR silently ignores unsupported values. */
    public final class MobileRenderQuality {
        private var target:Stage;
        private var selected:String;
        private var initial:String;
        private var attempts:Array=[];
        private var restored:uint=0;
        public function MobileRenderQuality(stage:Stage) {
            target=stage; initial=target.quality;
            // AIR 51.4.1.2 iOS accepted 16x16 but clipped full-game Retina rendering
            // near physical x=2048 at 2622px width. 8x8 rendered the same scene fully.
            // Read-back alone is insufficient: cap at the visually verified mode.
            for each(var candidate:String in [StageQuality.HIGH_8X8_LINEAR,
                    StageQuality.HIGH_8X8,StageQuality.BEST,StageQuality.HIGH]) {
                var errorName:String=null;
                try { target.quality=candidate; } catch(error:Error) { errorName=error.name; }
                var accepted:Boolean=target.quality.toLowerCase()==candidate.toLowerCase();
                attempts.push({requested:candidate,actual:target.quality,accepted:accepted,error:errorName});
                if(accepted)break;
            }
            selected=target.quality;
            // Legacy SWFs can change Stage quality; keep the verified host setting.
            target.addEventListener(Event.EXIT_FRAME,enforce,false,-999,true);
        }
        private function enforce(event:Event):void {
            if(target.quality==selected)return;
            try { target.quality=selected; if(target.quality==selected)restored++; }
            catch(ignored:Error) { /* diagnostics retains the effective value */ }
        }
        public function snapshot():Object {
            return {preferred:StageQuality.HIGH_8X8_LINEAR,initial:initial,selected:selected,
                actual:target.quality,attempts:attempts.concat(),restorations:restored,
                contentsScaleFactor:target.contentsScaleFactor};
        }
        public function dispose():void { target.removeEventListener(Event.EXIT_FRAME,enforce); }
    }
}
