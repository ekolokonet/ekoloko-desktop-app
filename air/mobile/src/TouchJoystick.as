package {
    import flash.display.Sprite;
    import flash.display.Stage;
    import flash.events.Event;
    import flash.events.MouseEvent;
    import flash.events.TouchEvent;
    import flash.geom.Point;

    /** Emits a normalized intent; the game bridge must apply its usual path rules. */
    public final class TouchJoystick extends Sprite {
        private var knob:Sprite = new Sprite();
        private var host:Stage;
        private var touchId:int = -1;
        private var mouseDrag:Boolean = false;
        private var callback:Function;
        private var enabled:Boolean = true;
        public static const IDLE_ALPHA:Number = 0;
        public static const ACTIVE_ALPHA:Number = .55;
        public var dx:Number = 0;
        public var dy:Number = 0;
        public var travelled:Boolean=false;
        public function TouchJoystick(onChange:Function) {
            callback = onChange;
            alpha = IDLE_ALPHA;
            mouseEnabled=false;mouseChildren=false;
            graphics.lineStyle(3, 0xffffff, .85);
            graphics.beginFill(0x294f25, .85); graphics.drawCircle(0, 0, 60); graphics.endFill();
            graphics.lineStyle(1, 0xffffff, .3); graphics.drawCircle(0, 0, 38);
            knob.graphics.lineStyle(3, 0x3f6825);
            knob.graphics.beginFill(0xc1e865); knob.graphics.drawCircle(0, 0, 25); knob.graphics.endFill();
            knob.mouseEnabled = false; addChild(knob);
            addEventListener(Event.ADDED_TO_STAGE, attach);
            addEventListener(Event.REMOVED_FROM_STAGE, detach);
            addEventListener(TouchEvent.TOUCH_BEGIN, touchBegin);
            addEventListener(MouseEvent.MOUSE_DOWN, mouseBegin);
        }
        private function attach(e:Event):void {
            host = stage;
            host.addEventListener(TouchEvent.TOUCH_MOVE, touchMove);
            host.addEventListener(TouchEvent.TOUCH_END, touchEnd);
            host.addEventListener(MouseEvent.MOUSE_MOVE, mouseMove);
            host.addEventListener(MouseEvent.MOUSE_UP, mouseEnd);
            host.addEventListener(Event.MOUSE_LEAVE, cancel);
            host.addEventListener(Event.DEACTIVATE, cancel);
        }
        private function detach(e:Event):void {
            reset();
            if (!host) return;
            host.removeEventListener(TouchEvent.TOUCH_MOVE, touchMove);
            host.removeEventListener(TouchEvent.TOUCH_END, touchEnd);
            host.removeEventListener(MouseEvent.MOUSE_MOVE, mouseMove);
            host.removeEventListener(MouseEvent.MOUSE_UP, mouseEnd);
            host.removeEventListener(Event.MOUSE_LEAVE, cancel);
            host.removeEventListener(Event.DEACTIVATE, cancel); host = null;
        }
        public function setAvailable(value:Boolean):void {
            enabled = value; visible = value;
            if (!value) reset();
        }
        public function beginAt(sx:Number,sy:Number,id:int=-1):void {
            if(!enabled)return;
            var p:Point=parent.globalToLocal(new Point(sx,sy));x=p.x;y=p.y;
            touchId=id;mouseDrag=id==-1;travelled=false;alpha=ACTIVE_ALPHA;
            update(sx,sy);
        }
        private function touchBegin(e:TouchEvent):void {
            if (!enabled || touchId != -1) return;
            mouseDrag = false; touchId = e.touchPointID;
            alpha = ACTIVE_ALPHA;
            update(e.stageX, e.stageY); e.stopPropagation();
        }
        private function touchMove(e:TouchEvent):void {
            if (e.touchPointID == touchId) { update(e.stageX,e.stageY); e.stopPropagation(); }
        }
        private function touchEnd(e:TouchEvent):void { if(e.touchPointID == touchId) reset(); }
        private function mouseBegin(e:MouseEvent):void {
            if (!enabled || touchId != -1) return;
            mouseDrag = true; alpha = ACTIVE_ALPHA; update(e.stageX,e.stageY); e.stopPropagation();
        }
        private function mouseMove(e:MouseEvent):void { if(mouseDrag) update(e.stageX,e.stageY); }
        private function mouseEnd(e:MouseEvent):void { if(mouseDrag) reset(); }
        private function cancel(e:Event):void { reset(); }
        private function update(sx:Number, sy:Number):void {
            var p:Point = globalToLocal(new Point(sx,sy));
            var n:Number = Math.sqrt(p.x*p.x+p.y*p.y);
            if(n>8)travelled=true;
            var amplitude:Number = Math.min(1,Math.max(0,(n-8)/30));
            dx = n > 0 ? p.x/n*amplitude : 0;
            dy = n > 0 ? p.y/n*amplitude : 0;
            knob.x = dx*34; knob.y = dy*34;
            callback(dx,dy);
        }
        public function reset():void {
            touchId = -1; mouseDrag = false; dx = dy = 0; knob.x = knob.y = 0;
            alpha = IDLE_ALPHA;
            callback(0,0);
        }
    }
}
