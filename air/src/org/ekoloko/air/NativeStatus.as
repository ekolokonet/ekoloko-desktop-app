package org.ekoloko.air {
    import flash.display.Bitmap;
    import flash.display.GradientType;
    import flash.display.Sprite;
    import flash.events.Event;
    import flash.geom.Matrix;
    import flash.geom.Rectangle;
    import flash.utils.getTimer;

    public class NativeStatus extends Sprite {
        [Embed(source="../../../../assets/welcome-jungle.jpg")]
        private static const Jungle:Class;
        [Embed(source="../../../../../assets/3.png")]
        private static const Wordmark:Class;
        private var scene:Bitmap = new Jungle();
        private var sceneClip:Sprite = new Sprite();
        private var veil:Sprite = new Sprite();
        private var panel:Sprite = new Sprite();
        private var dots:Array = [];
        private var title:String = "בדרך לעולם של אקולוקו";
        private var detail:String = "מתחברים למשחק…";
        private var busy:Boolean = true;
        private var retryEnabled:Boolean;
        private var retry:Function;
        private var w:Number = 1000;
        private var h:Number = 600;
        private var night:Boolean;
        private var motion:Boolean = true;
        private var sceneScale:Number = 1;
        private var sceneLeft:Number;
        private var sceneTop:Number;
        public function NativeStatus(onRetry:Function) {
            retry = onRetry; scene.smoothing = true;
            addChild(sceneClip); sceneClip.addChild(scene); addChild(veil); addChild(panel);
            addEventListener(Event.ENTER_FRAME,tick); redraw();
        }
        public function configure(width:Number,height:Number,dark:Boolean,animate:Boolean):void { w=width;h=height;night=dark;motion=animate;redraw(); }
        public function show(headline:String,body:String,loading:Boolean,canRetry:Boolean):void {
            title=headline;detail=body;busy=loading;retryEnabled=canRetry;visible=true;redraw();
        }
        private function redraw():void {
            graphics.clear();
            var matrix:Matrix = new Matrix(); matrix.createGradientBox(w,h,Math.PI/2);
            graphics.beginGradientFill(GradientType.LINEAR,night ? [0x0c2330,0x163c38] : [0xf1f8db,0xd8edb4],[1,1],[0,255],matrix); graphics.drawRect(0,0,w,h); graphics.endFill();
            var sceneHeight:Number = Math.min(h*.75,510);
            sceneScale = Math.max(w/scene.bitmapData.width,sceneHeight/scene.bitmapData.height)*1.025;
            scene.scaleX=scene.scaleY=sceneScale;
            sceneLeft=(w-scene.width)/2;sceneTop=0;
            scene.x=sceneLeft;scene.y=sceneTop;scene.alpha=night ? .32 : .78;
            sceneClip.scrollRect=new Rectangle(0,0,w,sceneHeight);
            veil.graphics.clear();var fade:Matrix=new Matrix();fade.createGradientBox(w,sceneHeight,Math.PI/2);
            var tint:uint=night ? 0x133936 : 0xe3f1c4;
            veil.graphics.beginGradientFill(GradientType.LINEAR,[tint,tint,tint],[0,0,1],[0,155,255],fade);veil.graphics.drawRect(0,0,w,sceneHeight);veil.graphics.endFill();
            panel.removeChildren(); panel.graphics.clear(); dots=[];
            var pw:Number=Math.min(580,w-56);
            var ph:Number=busy ? 314 : 346;
            if(h<490) ph-=36;
            panel.x=Math.round((w-pw)/2);panel.y=Math.round(Math.max(22,(h-ph)/2));
            panel.graphics.beginFill(night ? 0x03121d : 0x32663d,.13);panel.graphics.drawRoundRect(0,10,pw,ph,36);panel.graphics.endFill();
            panel.graphics.beginFill(night ? 0x15313d : 0xfffff6,.97);panel.graphics.drawRoundRect(0,0,pw,ph,36);panel.graphics.endFill();
            panel.graphics.lineStyle(1,night ? 0x3b606c : 0xffffff,.8);panel.graphics.drawRoundRect(.5,.5,pw-1,ph-1,36);
            var logo:Bitmap=new Wordmark();logo.smoothing=true;logo.width=205;logo.height=87;logo.x=(pw-205)/2;logo.y=h<490 ? 14 : 24;panel.addChild(logo);
            var head:NativeLabel=new NativeLabel(title,pw-44,29,night ? 0xf2f8df : 0x25452b);head.x=22;head.y=h<490 ? 103 : 116;panel.addChild(head);
            var body:NativeLabel=new NativeLabel(detail,pw-64,18,night ? 0xc2d4d2 : 0x50624a);body.x=32;body.y=h<490 ? 150 : 167;panel.addChild(body);
            if(busy) {
                for(var i:int=0;i<3;i++) {var dot:Sprite=new Sprite();dot.graphics.beginFill(0x79aa2d);dot.graphics.drawCircle(0,0,5);dot.graphics.endFill();dot.x=pw/2+(i-1)*20;dot.y=ph-38;panel.addChild(dot);dots.push(dot);}
            } else if(retryEnabled) {
                var button:NativeButton=new NativeButton("ניסיון נוסף",168,retry,true,night,46,19);button.x=(pw-168)/2;button.y=ph-70;panel.addChild(button);
            }
            var foot:NativeLabel=new NativeLabel("Ekoloko Rewritten  ·  0.1.0",w,13,night ? 0xabc8bb : 0x4c6841);foot.y=Math.max(h-30,panel.y+ph+14);foot.x=-panel.x;panel.addChild(foot);foot.y-=panel.y;
        }
        private function tick(event:Event):void {
            if(!visible || !motion) return;
            var t:Number=getTimer()/1000;
            // Slow movement of the game's own background; all copy stays still.
            scene.x=sceneLeft+Math.sin(t*.18)*5;scene.y=sceneTop+Math.sin(t*.14)*3;
            if(busy) for(var i:int=0;i<dots.length;i++) Sprite(dots[i]).alpha=.35+.65*(Math.sin(t*3-i*.8)+1)/2;
        }
    }
}
