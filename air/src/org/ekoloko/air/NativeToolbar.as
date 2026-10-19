package org.ekoloko.air {
    import flash.display.Bitmap;
    import flash.display.GradientType;
    import flash.display.NativeMenu;
    import flash.display.NativeMenuItem;
    import flash.display.Sprite;
    import flash.events.Event;
    import flash.events.KeyboardEvent;
    import flash.events.MouseEvent;
    import flash.geom.Matrix;
    import flash.media.SoundMixer;
    import flash.media.SoundTransform;
    import flash.net.SharedObject;
    import flash.accessibility.AccessibilityProperties;

    public class NativeToolbar extends Sprite {
        [Embed(source="../../../../../assets/3.png")]
        private static const Logo:Class;
        [Embed(source="../../../../../build/icon-1024.png")]
        private static const Emblem:Class;
        private var action:Function;
        private var settings:SharedObject = SharedObject.getLocal("native-interface-v1");
        private var widthValue:Number = 1000;
        public var night:Boolean;
        public var motion:Boolean;
        private var volume:Number = 1;
        private var lastVolume:Number = .7;
        private var track:Sprite;
        private var volumeCaption:NativeLabel;
        private var soundArea:Sprite;
        private var menu:NativeMenu;
        private var updateAvailable:Boolean = false;
        public function NativeToolbar(onAction:Function) {
            action = onAction;
            night = settings.data.night === true;
            motion = settings.data.motion !== false;
            if (settings.data.volume is Number && isFinite(settings.data.volume)) volume = Math.max(0, Math.min(1, settings.data.volume));
            if(volume>0) lastVolume=volume;
            SoundMixer.soundTransform = new SoundTransform(volume); draw();
        }
        public function resize(width:Number):void { widthValue = Math.round(width); draw(); }
        public function setUpdateAvailable(value:Boolean):void {if(updateAvailable!=value){updateAvailable=value;draw();}}
        private function draw():void {
            removeChildren(); graphics.clear();
            var matrix:Matrix = new Matrix(); matrix.createGradientBox(widthValue,92,Math.PI/2);
            graphics.beginGradientFill(GradientType.LINEAR,night ? [0x163a48,0x0e2936] : [0x9bcf42,0x71ab2a],[1,1],[0,255],matrix);
            graphics.drawRect(0,0,widthValue,92);graphics.endFill();
            graphics.beginFill(night ? 0x051e2b : 0x4c861c);graphics.drawRect(0,89,widthValue,3);graphics.endFill();
            graphics.beginFill(0xffffff,.18);graphics.drawRect(0,0,widthValue,1);graphics.endFill();

            // The circular community emblem stays anchored to the window edge.
            var emblem:Sprite = new Sprite();emblem.x=widthValue-92;emblem.y=12;
            emblem.graphics.beginFill(night ? 0x3e645a : 0xf4ffd9);emblem.graphics.drawCircle(34,34,36);emblem.graphics.endFill();
            var icon:Bitmap=new Emblem();icon.smoothing=true;icon.width=icon.height=72;icon.x=icon.y=-2;emblem.addChild(icon);
            var maskShape:Sprite=new Sprite();maskShape.graphics.beginFill(0);maskShape.graphics.drawCircle(34,34,32);maskShape.graphics.endFill();emblem.addChild(maskShape);icon.mask=maskShape;
            activate(emblem,"קהילת אקולוקו בדיסקורד",function():void {action("community");});addChild(emblem);
            var brandWidth:Number=widthValue>=1140 ? 258 : widthValue>=950 ? 214 : 110;
            if(widthValue>=950) {
                var logo:Bitmap=new Logo();logo.smoothing=true;logo.width=widthValue>=1140 ? 138 : 102;logo.height=logo.width*.424;
                logo.x=widthValue-100-logo.width-18;logo.y=Math.round((89-logo.height)/2);addChild(logo);
            }
            var right:Number=widthValue-brandWidth;
            var specs:Array=[
                {text:"מסך מלא",width:114,key:"fullscreen",primary:true},
                {text:updateAvailable ? "עדכון משחק" : "הפעלה מחדש",width:132,key:"restart",primary:updateAvailable},
                {text:"תיקון התחברות",width:145,key:"repair"}
            ];
            if(widthValue>=1300) {specs.push({text:"שמירת לוגים",width:126,key:"logs"});specs.push({text:night ? "מצב יום" : "מצב לילה",width:110,key:"appearance"});}
            for each(var spec:Object in specs) {
                right-=spec.width;
                var button:NativeButton=new NativeButton(spec.text,spec.width,callback(spec.key),spec.primary===true,night);
                button.x=Math.round(right);button.y=23;addChild(button);right-=10;
            }
            right-=66;
            var more:NativeButton=new NativeButton("עוד",66,showMenu,false,night);more.x=Math.round(right);more.y=23;addChild(more);
            soundArea=new Sprite();soundArea.x=20;soundArea.y=20;addChild(soundArea);
            var mute:NativeButton=new NativeButton(volume==0 ? "קול" : "השתקה",66,function():void {
                if(volume>0) {lastVolume=volume;volume=0;} else volume=lastVolume;
                commitVolume();draw();
            },false,night,34,15);mute.y=8;soundArea.addChild(mute);
            if(right>=245) {
                track=new Sprite();track.x=78;track.y=18;soundArea.addChild(track);paintTrack();
                var a:AccessibilityProperties=new AccessibilityProperties();a.name="עוצמת קול";track.accessibilityProperties=a;track.tabEnabled=true;track.buttonMode=true;
                track.addEventListener(MouseEvent.MOUSE_DOWN,startDragVolume);
                track.addEventListener(KeyboardEvent.KEY_DOWN,function(e:KeyboardEvent):void {
                    if(e.keyCode==37 || e.keyCode==39) {volume=Math.max(0,Math.min(1,volume+(e.keyCode==39 ? .05 : -.05)));commitVolume();paintTrack();e.stopPropagation();}
                });
            }
        }
        private function callback(key:String):Function {
            return function():void {if(key=="appearance") {night=!night;settings.data.night=night;save();draw();}action(key);};
        }
        private function showMenu():void {
            menu=new NativeMenu();
            menuItem("שמירת לוגים",callback("logs"));
            menuItem(night ? "מצב יום" : "מצב לילה",callback("appearance"));
            menuItem("תנועה עדינה בממשק",function():void {motion=!motion;settings.data.motion=motion;save();action("appearance");},motion);
            menu.addItem(new NativeMenuItem("",true));
            menuItem("קהילת אקולוקו בדיסקורד",callback("community"));
            menu.display(stage,stage.mouseX,stage.mouseY);
        }
        private function menuItem(text:String,callback:Function,checked:Boolean=false):void {
            var item:NativeMenuItem=new NativeMenuItem(text);item.checked=checked;item.addEventListener(Event.SELECT,function(e:Event):void {callback();});menu.addItem(item);
        }
        private function startDragVolume(event:MouseEvent):void {
            updateVolumeFromPointer();stage.addEventListener(MouseEvent.MOUSE_MOVE,dragVolume);stage.addEventListener(MouseEvent.MOUSE_UP,endDragVolume);
        }
        private function dragVolume(event:MouseEvent):void {updateVolumeFromPointer();event.updateAfterEvent();}
        private function endDragVolume(event:MouseEvent):void {stage.removeEventListener(MouseEvent.MOUSE_MOVE,dragVolume);stage.removeEventListener(MouseEvent.MOUSE_UP,endDragVolume);commitVolume();}
        private function updateVolumeFromPointer():void {volume=Math.max(0,Math.min(1,track.mouseX/124));SoundMixer.soundTransform=new SoundTransform(volume);paintTrack();}
        private function paintTrack():void {
            track.graphics.clear();track.graphics.beginFill(0,0);track.graphics.drawRect(-8,-10,140,36);track.graphics.endFill();
            track.graphics.beginFill(night ? 0x4c6971 : 0x467523,.65);track.graphics.drawRoundRect(0,0,124,7,7);track.graphics.endFill();
            track.graphics.beginFill(0xffb347);track.graphics.drawRoundRect(0,0,Math.max(4,124*volume),7,7);track.graphics.endFill();
            track.graphics.beginFill(0xffffff);track.graphics.drawCircle(124*volume,3.5,6);track.graphics.endFill();
            if(volumeCaption && soundArea.contains(volumeCaption))soundArea.removeChild(volumeCaption);
            volumeCaption=new NativeLabel(Math.round(volume*100)+"%",124,12,night ? 0xbacfca : 0x2d5126);volumeCaption.x=78;volumeCaption.y=31;soundArea.addChild(volumeCaption);
        }
        private function activate(button:Sprite,text:String,click:Function):void {
            button.buttonMode=true;button.mouseChildren=false;button.tabEnabled=true;
            var a:AccessibilityProperties=new AccessibilityProperties();a.name=text;button.accessibilityProperties=a;
            button.addEventListener(MouseEvent.CLICK,function(e:Event):void {click();});
            button.addEventListener(KeyboardEvent.KEY_DOWN,function(e:KeyboardEvent):void {if(e.keyCode==13 || e.keyCode==32){click();e.stopPropagation();}});
            button.addEventListener(MouseEvent.ROLL_OVER,function(e:Event):void {button.alpha=.86;});
            button.addEventListener(MouseEvent.ROLL_OUT,function(e:Event):void {button.alpha=1;});
        }
        private function commitVolume():void {SoundMixer.soundTransform=new SoundTransform(volume);if(volume>0)lastVolume=volume;settings.data.volume=volume;save();}
        private function save():void {try {settings.flush();}catch(error:Error){}}
    }
}
