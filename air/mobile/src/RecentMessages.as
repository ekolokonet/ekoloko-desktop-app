package {
    import flash.display.*;
    import flash.events.*;
    import flash.geom.*;
    import flash.filters.GlowFilter;
    /** Local presentation of messages. No transport, moderation or send logic. */
    public final class RecentMessages extends Sprite {
        private var messages:Array=[];
        private var bounds:Rectangle=new Rectangle();
        private var w:Number=340,h:Number=240;
        private var opacity:Number=.38;
        private var scrollFromBottom:Number=0;
        
        private var unread:int=0;
        private var dragID:int=-2;
        private var lastPoint:Point;
        private var draggingWindow:Boolean=false;
        private var clip:Sprite,content:Sprite;
        private var maxScroll:Number=0;
        public var onClose:Function;
        public function RecentMessages(){visible=false;addEventListener(Event.ADDED_TO_STAGE,added);}
        private function added(e:Event):void {
            stage.addEventListener(MouseEvent.MOUSE_MOVE,mouseMove);
            stage.addEventListener(MouseEvent.MOUSE_UP,endMouse);
            stage.addEventListener(TouchEvent.TOUCH_MOVE,touchMove);
            stage.addEventListener(TouchEvent.TOUCH_END,endTouch);
            stage.addEventListener(Event.DEACTIVATE,function(e:Event):void{dragID=-2;});
        }
        public function fit(rect:Rectangle):void {
            bounds=rect.clone();w=Math.min(350,rect.width);h=Math.min(244,rect.height);
            if(x==0&&y==0){x=rect.x;y=rect.y+8;}
            constrain();if(visible)draw();
        }
        private function constrain():void {x=Math.max(bounds.x,Math.min(x,bounds.right-w));y=Math.max(bounds.y,Math.min(y,bounds.bottom-h));}
        public function toggle():void {visible=!visible;if(visible){unread=0;draw();}else dragID=-2;}
        public function update(value:Array):void {
            var changed:Boolean=messages.length!=value.length||messages.length>0&&messages[messages.length-1]!=value[value.length-1];
            messages=value.concat();if(!changed)return;
            if(scrollFromBottom>0)unread++;
            if(visible){var oldMax:Number=maxScroll;draw();if(scrollFromBottom>0){scrollFromBottom=Math.min(maxScroll,scrollFromBottom+maxScroll-oldMax);content.y=-maxScroll+scrollFromBottom;}}
        }
        public function draw():void {
            removeChildren();graphics.clear();var skin:Sprite=OriginalUI.panelBackground(w,h);skin.alpha=opacity;addChild(skin);
            var title:MobileLabel=new MobileLabel("הודעות אחרונות",w-76,18,0xffffff);title.x=12;title.y=10;title.filters=[new GlowFilter(0x273647,1,3,3,3)];addChild(title);
            var header:Sprite=new Sprite();header.name="drag-header";header.graphics.beginFill(0,0);header.graphics.drawRect(0,0,w-60,44);header.graphics.endFill();addChild(header);bindDrag(header,true);
            var transparency:Sprite=OriginalUI.actionButton("opacity",function():void{opacity=opacity<.3 ? .38 : (opacity<.5 ? .72 : .22);draw();});transparency.x=w-52;addChild(transparency);
            clip=new Sprite();clip.x=12;clip.y=46;clip.scrollRect=new Rectangle(0,0,w-24,Math.max(24,h-94));addChild(clip);content=new Sprite();clip.addChild(content);
            var yy:Number=0;
            for each(var m:Object in messages){
                var own:Boolean=m.own===true;
                var row:Sprite=new Sprite();row.name=own?"own-message":"other-message";row.y=yy;content.addChild(row);
                var author:String=own?(String(m.name).indexOf("אני")==0?String(m.name):"אני · "+m.name):String(m.name);
                var line:MobileLabel=new MobileLabel(author+": "+m.text,w-42,16,own?0xffe4a1:0xffffff,"right");
                line.filters=[new GlowFilter(0x243447,1,3,3,3)];line.x=6;line.y=3;row.addChild(line);
                if(own){row.graphics.beginFill(0x5badcf,opacity*.65);row.graphics.drawRoundRect(0,0,w-24,line.height+6,10);row.graphics.endFill();row.graphics.beginFill(0xffce70,.85);row.graphics.drawRoundRect(w-28,3,3,line.height,3);row.graphics.endFill();}
                yy+=line.height+14;
            }
            maxScroll=Math.max(0,yy-clip.scrollRect.height);scrollFromBottom=Math.max(0,Math.min(scrollFromBottom,maxScroll));content.y=-maxScroll+scrollFromBottom;
            clip.graphics.beginFill(0,0);clip.graphics.drawRect(0,0,w-24,clip.scrollRect.height);clip.graphics.endFill();bindDrag(clip,false);
            clip.addEventListener(MouseEvent.MOUSE_WHEEL,function(e:MouseEvent):void{scrollBy(e.delta*22);e.stopPropagation();});
            var older:Sprite=OriginalUI.actionButton("older",function():void{scrollBy(80);});older.y=h-48;older.x=8;addChild(older);
            var newer:Sprite=OriginalUI.actionButton("newer",function():void{scrollFromBottom=0;unread=0;draw();});newer.y=h-48;newer.x=w-56;if(unread>0)newer.filters=[new GlowFilter(0xffd878,1,6,6,2)];addChild(newer);
            var close:Sprite=OriginalUI.closeButton(function():void{visible=false;dragID=-2;if(onClose!=null)onClose();});close.x=(w-48)/2;close.y=h-48;addChild(close);
        }
        private function scrollBy(delta:Number):void {scrollFromBottom=Math.max(0,Math.min(maxScroll,scrollFromBottom+delta));if(scrollFromBottom==0)unread=0;if(content)content.y=-maxScroll+scrollFromBottom;}
        private function bindDrag(s:Sprite,window:Boolean):void {
            s.addEventListener(MouseEvent.MOUSE_DOWN,function(e:MouseEvent):void{if(dragID>=0)return;begin(-1,e.stageX,e.stageY,window);e.stopPropagation();});
            s.addEventListener(TouchEvent.TOUCH_BEGIN,function(e:TouchEvent):void{begin(e.touchPointID,e.stageX,e.stageY,window);e.stopPropagation();});
        }
        private function begin(id:int,sx:Number,sy:Number,window:Boolean):void {if(dragID>=0)return;dragID=id;lastPoint=new Point(sx,sy);draggingWindow=window;}
        private function move(sx:Number,sy:Number):void {
            if(!visible)return;
            if(draggingWindow){x+=sx-lastPoint.x;y+=sy-lastPoint.y;constrain();}else scrollBy(sy-lastPoint.y);
            lastPoint.setTo(sx,sy);
        }
        private function mouseMove(e:MouseEvent):void {if(dragID==-1)move(e.stageX,e.stageY);}
        private function touchMove(e:TouchEvent):void {if(dragID==e.touchPointID)move(e.stageX,e.stageY);}
        private function endMouse(e:MouseEvent):void {if(dragID==-1)dragID=-2;}
        private function endTouch(e:TouchEvent):void {if(dragID==e.touchPointID)dragID=-2;}
        public function verify():void {
            var original:Array=messages.concat(),previous:Boolean=visible;visible=true;
            var sample:Array=[];for(var i:int=0;i<80;i++)sample.push({name:"בדיקה",text:"הודעה בעברית מספר "+i,own:i%2==0});
            update(sample);draw();
            if(!content.getChildByName("own-message")||!content.getChildByName("other-message"))throw new Error("history_authorship_not_distinguished");
            var header:Sprite=getChildByName("drag-header") as Sprite;
            header.dispatchEvent(new TouchEvent(TouchEvent.TOUCH_BEGIN,true,false,91,false,20,20));
            stage.dispatchEvent(new TouchEvent(TouchEvent.TOUCH_MOVE,true,false,91,false,bounds.right+100,bounds.bottom+100));
            stage.dispatchEvent(new TouchEvent(TouchEvent.TOUCH_END,true,false,91));
            if(x+w>bounds.right+.1||y+h>bounds.bottom+.1||dragID!=-2)throw new Error("history_drag_bounds");
            clip.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_WHEEL,true,false,0,0,null,false,false,false,false,3));
            if(scrollFromBottom<=0)throw new Error("history_scroll_older");
            var before:Number=content.y;sample.push({name:"חדש",text:"הודעה חדשה בזמן קריאת ההיסטוריה"});update(sample);
            if(Math.abs(content.y-before)>1||unread<1)throw new Error("history_read_position_on_arrival");
            if(skinAlpha()>=1)throw new Error("history_not_translucent");
            for each(var id:String in ["opacity","older","newer","close"]){
                var button:Sprite=getChildByName("action-"+id) as Sprite;
                if(!button||button.width<44||button.height<44)throw new Error("history_icon_target_"+id);
            }
            var initialOpacity:Number=opacity;
            getChildByName("action-opacity").dispatchEvent(new MouseEvent(MouseEvent.CLICK,true));
            if(opacity==initialOpacity)throw new Error("history_opacity_icon");
            getChildByName("action-newer").dispatchEvent(new MouseEvent(MouseEvent.CLICK,true));
            if(scrollFromBottom!=0||unread!=0)throw new Error("history_latest_icon");
            getChildByName("action-older").dispatchEvent(new MouseEvent(MouseEvent.CLICK,true));
            if(scrollFromBottom<=0)throw new Error("history_older_icon");
            getChildByName("action-close").dispatchEvent(new MouseEvent(MouseEvent.CLICK,true));
            if(visible)throw new Error("history_close_icon");
            opacity=initialOpacity;
            trace("MOBILE_HISTORY_ICON_ACTIONS_PASS");
            messages=original;scrollFromBottom=0;unread=0;visible=previous;draw();
            trace("MOBILE_HISTORY_DRAG_SCROLL_INCOMING_POSITION_PASS");
        }
        private function skinAlpha():Number{return getChildAt(0).alpha;}
    }
}
