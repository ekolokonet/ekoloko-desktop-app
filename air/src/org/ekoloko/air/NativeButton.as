package org.ekoloko.air {
    import flash.accessibility.AccessibilityProperties;
    import flash.display.GradientType;
    import flash.display.Sprite;
    import flash.events.Event;
    import flash.events.KeyboardEvent;
    import flash.events.MouseEvent;
    import flash.geom.Matrix;
    import flash.utils.getTimer;

    public class NativeButton extends Sprite {
        private var face:Sprite = new Sprite();
        private var targetY:Number = 0;
        private var last:int;
        public function NativeButton(text:String, width:Number, action:Function, primary:Boolean = false, night:Boolean = false, height:Number = 44, fontSize:Number = 17) {
            addChild(face); buttonMode = true; mouseChildren = false; tabEnabled = true;
            var info:AccessibilityProperties = new AccessibilityProperties(); info.name = text; accessibilityProperties = info;
            var matrix:Matrix = new Matrix(); matrix.createGradientBox(width,height,Math.PI/2);
            face.graphics.beginFill(primary ? 0xc3680a : night ? 0x061a24 : 0x719d30);
            face.graphics.drawRoundRect(0,3,width,height,20); face.graphics.endFill();
            face.graphics.beginGradientFill(GradientType.LINEAR,primary ? [0xffae3a,0xf98a12] : night ? [0x264755,0x193743] : [0xfaffef,0xe2efc2],[1,1],[0,255],matrix);
            face.graphics.drawRoundRect(0,0,width,height,20); face.graphics.endFill();
            var label:NativeLabel = new NativeLabel(text,width,fontSize,primary || night ? 0xffffff : 0x24492b);
            label.y = Math.round((height-fontSize)/2)-2; face.addChild(label);
            addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void { action(); });
            addEventListener(KeyboardEvent.KEY_DOWN,function(e:KeyboardEvent):void { if(e.keyCode==13 || e.keyCode==32) { action(); e.stopPropagation(); } });
            addEventListener(MouseEvent.ROLL_OVER,function(e:Event):void { animate(-2); });
            addEventListener(MouseEvent.ROLL_OUT,function(e:Event):void { animate(0); });
            addEventListener(MouseEvent.MOUSE_DOWN,function(e:Event):void { animate(2); });
            addEventListener(MouseEvent.MOUSE_UP,function(e:Event):void { animate(-2); });
        }
        private function animate(to:Number):void { targetY=to; last=getTimer(); addEventListener(Event.ENTER_FRAME,tick); }
        private function tick(e:Event):void {
            face.y += (targetY-face.y)*.55;
            if(Math.abs(face.y-targetY)<.1 || getTimer()-last>180) {face.y=targetY;removeEventListener(Event.ENTER_FRAME,tick);}
        }
    }
}
