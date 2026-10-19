package {
    import flash.display.BitmapData;
    import flash.display.DisplayObject;
    import flash.display.Sprite;
    import flash.events.MouseEvent;
    import flash.geom.Rectangle;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.filters.GlowFilter;

    /** Original visual assets and walk mask, with explicitly local demo actors. */
    public final class MobileScene extends Sprite {
        public var player:Sprite;
        public var actors:Sprite=new Sprite();
        private var peers:Array=[];
        private var walkMask:BitmapData;
        private var poseName:String="";
        private var elapsed:Number=0;
        private var speech:Array=[];
        public var onInteract:Function;
        public function MobileScene() {
            var bg:Sprite=new GameArtwork.Background(); GameArtwork.stopTree(bg);addChild(bg);
            var mask:Sprite=new GameArtwork.Walkarea();GameArtwork.stopTree(mask);
            walkMask=new BitmapData(960,600,true,0);walkMask.draw(mask);
            addChild(actors);
            player=makePlayer("אני",480,390);
            if(!canWalk(player.x,player.y)) {
                for(var y:int=220;y<560;y+=10)if(canWalk(480,y)){player.y=y;break;}
            }
            peers.push(makePlayer("נועה · דוגמה",650,380));
            peers.push(makePlayer("אורי · דוגמה",280,420));
            var npc:Sprite=new Sprite(),art:DisplayObject=new GameArtwork.Resident();GameArtwork.stopTree(art);
            var b:Rectangle=art.getBounds(art); art.scaleX=art.scaleY=120/b.height;
            art.x=-(b.x+b.width/2)*art.scaleX;art.y=-b.bottom*art.scaleY;npc.addChild(art);
            npc.x=790;npc.y=360;npc.name="resident";npc.mouseChildren=false;npc.buttonMode=true;
            npc.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void {e.stopPropagation();if(onInteract!=null)onInteract("resident");});
            actors.addChild(npc);tag(npc,"היתקליף",100);
            var fg:Sprite=new GameArtwork.Foreground();GameArtwork.stopTree(fg);fg.mouseEnabled=false;fg.mouseChildren=false;addChild(fg);
            trace("MOBILE_REAL_ARTWORK room=jungle101 avatarLayers="+Sprite(player.getChildByName("layers")).numChildren+" walkable="+canWalk(player.x,player.y));
        }
        private function makePlayer(name:String,x:Number,y:Number):Sprite {
            var a:Sprite=GameArtwork.avatar();a.x=x;a.y=y;a.name=name;actors.addChild(a);tag(a,name,100);
            return a;
        }
        private function tag(parent:Sprite,text:String,width:Number):void {
            // Match WorldPlayer.setNameField rather than inventing a name badge.
            var label:TextField=new TextField();label.defaultTextFormat=new TextFormat("Arial",14,0,true,null,null,null,null,"center");
            label.text=text;label.width=label.textWidth+4;label.height=label.textHeight+4;
            label.x=-label.width/2+5;label.y=5;label.selectable=false;label.mouseEnabled=false;
            label.filters=[new GlowFilter(0xffffff,1,6,6,2)];parent.addChild(label);
        }

        public function canWalk(x:Number,y:Number):Boolean {
            if(x<20||x>940||y<110||y>570)return false;
            return (walkMask.getPixel32(int(x),int(y))>>>24)>127;
        }
        public function move(dx:Number,dy:Number,dt:Number):Boolean {
            var x:Number=player.x+dx*140*dt,y:Number=player.y+dy*140*dt;
            var moved:Boolean=false;
            if(canWalk(x,y)) {player.x=x;player.y=y;moved=dx!=0||dy!=0;}
            else if(canWalk(x,player.y)){moved=player.x!=x;player.x=x;}
            else if(canWalk(player.x,y)){moved=player.y!=y;player.y=y;}
            var direction:String=Math.abs(dx)>.45?(dx>0?"e":"w"):(dy<0?"n":"s");
            var next:String=(moved?direction:"s")+(moved?"_walk":"_stand");
            if(next!=poseName){poseName=next;GameArtwork.pose(player,next);}
            return moved;
        }
        public function tick(dt:Number):void {
            elapsed+=dt;
            for(var s:int=speech.length-1;s>=0;s--){
                speech[s].time-=dt;
                if(speech[s].time<=0){if(speech[s].clip.parent)speech[s].clip.parent.removeChild(speech[s].clip);speech.splice(s,1);}
            }
            // Ambient actors continue independently while the user is composing.
            var a:Sprite=peers[0],candidate:Number=650+Math.sin(elapsed*.45)*55;
            if(canWalk(candidate,a.y))a.x=candidate;
            var sorted:Array=[];
            for(var i:int=0;i<actors.numChildren;i++)sorted.push(actors.getChildAt(i));
            sorted.sortOn("y",Array.NUMERIC);
            for(i=0;i<sorted.length;i++)actors.setChildIndex(sorted[i],i);
        }
        public function clothingPreview():Sprite {
            return GameArtwork.avatar();
        }
        public function speak(x:Number,text:String):void {
            var actor:Sprite=x<0?player:(x>500?peers[0]:peers[1]);
            for(var i:int=speech.length-1;i>=0;i--)if(speech[i].actor==actor){
                if(speech[i].clip.parent)speech[i].clip.parent.removeChild(speech[i].clip);speech.splice(i,1);
            }
            var bubble:Sprite=new Sprite();bubble.mouseEnabled=false;bubble.mouseChildren=false;
            var content:MobileLabel=new MobileLabel(text.length>42?text.substr(0,39)+"…":text,160,14,0x244422);
            bubble.addChild(OriginalUI.speechBackground(176,Math.max(40,content.height+22)));
            content.x=8;content.y=5;bubble.addChild(content);bubble.x=-88;bubble.y=-120-bubble.height;actor.addChild(bubble);
            speech.push({actor:actor,clip:bubble,time:5});
        }
    }
}
