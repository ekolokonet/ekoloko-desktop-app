package {
    import flash.display.*;
    import flash.geom.*;
    import flash.utils.*;

    /** Sample only the player's sibling layer while composing, at most five times a second. */
    public final class MobileConversationFocus {
        private var nextSample:int=0,lastPlayer:DisplayObject,lastParent:DisplayObjectContainer;
        private var envelopes:Dictionary=new Dictionary(true),snapshot:Object;
        public function reset():void {nextSample=0;lastPlayer=null;lastParent=null;envelopes=new Dictionary(true);snapshot=null;}
        public function sample(player:DisplayObject,space:DisplayObject,now:int):Object {
            if(player!=lastPlayer||player.parent!=lastParent){reset();lastPlayer=player;lastParent=player.parent;}
            if(snapshot&&now<nextSample)return snapshot;
            nextSample=now+200;
            var own:Object=measure(player,space),near:Array=[],parent:DisplayObjectContainer=player.parent;
            if(parent){
                // Bounded to the closest players in the same room layer, never the whole stage.
                for(var i:int=0;i<parent.numChildren;i++){
                    var candidate:DisplayObject=parent.getChildAt(i);
                    if(candidate==player||!candidate.visible||candidate.alpha<=0||!("getPlayerName" in candidate))continue;
                    var anchor:Point=space.globalToLocal(parent.localToGlobal(new Point(candidate.x,candidate.y)));
                    var dx:Number=Math.abs(anchor.x-own.anchor.x),dy:Number=Math.abs(anchor.y-own.anchor.y);
                    if(dx>260||dy>65)continue;
                    near.push({player:candidate,score:dx+dy*2});
                }
            }
            near.sortOn("score",Array.NUMERIC);
            var neighbors:Array=[];
            for(i=0;i<Math.min(4,near.length);i++)neighbors.push(measure(near[i].player,space).bounds);
            snapshot={own:own.bounds,neighbors:neighbors};return snapshot;
        }
        private function measure(player:DisplayObject,space:DisplayObject):Object {
            var local:Rectangle=new Rectangle(-40,-120,80,138),container:DisplayObjectContainer=player as DisplayObjectContainer;
            if(container&&container.numChildren){
                // Player constructs its avatar as the first child. Its authored transform is
                // stable through walking frames, unlike getBounds() on hats/pets/effects.
                var avatar:DisplayObject=container.getChildAt(0);
                var name:String=getQualifiedClassName(avatar);
                if(name.indexOf("avatar::")>=0){
                    var top:Number=Math.min(-120,avatar.y-12),half:Number=Math.max(40,Math.abs(avatar.scaleX)*40);
                    local=new Rectangle(-half,top,half*2,18-top);
                }
                for(var i:int=0;i<container.numChildren;i++){
                    var child:DisplayObject=container.getChildAt(i);
                    if(child.visible&&child.alpha>0&&getQualifiedClassName(child)=="com.vtweens.components.chat::ChatBaloon")local=local.union(child.getBounds(player));
                }
            }
            // Hold space for bubbles until composing ends, avoiding jumps when they expire.
            if(envelopes[player])local=local.union(envelopes[player]);envelopes[player]=local.clone();
            var a:Point=space.globalToLocal(player.localToGlobal(local.topLeft));
            var b:Point=space.globalToLocal(player.localToGlobal(local.bottomRight));
            return {anchor:space.globalToLocal(player.localToGlobal(new Point())),bounds:new Rectangle(Math.min(a.x,b.x),Math.min(a.y,b.y),Math.abs(b.x-a.x),Math.abs(b.y-a.y))};
        }
    }
}
