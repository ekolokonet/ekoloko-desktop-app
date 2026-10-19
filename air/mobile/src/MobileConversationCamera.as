package {
    import flash.display.DisplayObject;
    import flash.geom.Point;
    import flash.geom.Rectangle;

    /** Numeric framing in mobile screen points; no display-tree traversal per frame. */
    public final class MobileConversationCamera {
        public static function keyboardBounds(space:DisplayObject,stageRect:Rectangle,width:Number,height:Number,nativePixelScale:Number=0):Rectangle {
            if(!stageRect||stageRect.isEmpty())return new Rectangle();
            // iOS AIR reports native screen pixels here (measured on the phone),
            // not SHOW_ALL stage coordinates. Convert once into adapter points.
            if(nativePixelScale>0)return new Rectangle(stageRect.x/nativePixelScale,stageRect.y/nativePixelScale,
                stageRect.width/nativePixelScale,stageRect.height/nativePixelScale).intersection(new Rectangle(0,0,width,height));
            var a:Point=space.globalToLocal(stageRect.topLeft),b:Point=space.globalToLocal(stageRect.bottomRight);
            return new Rectangle(Math.min(a.x,b.x),Math.min(a.y,b.y),Math.abs(b.x-a.x),Math.abs(b.y-a.y)).intersection(new Rectangle(0,0,width,height));
        }
        public static function target(viewport:Rectangle,safe:Rectangle,scale:Number,own:Rectangle,neighbors:Array):Object {
            var group:Rectangle=own.clone();
            // Neighbors are ordered by conversation proximity; they never displace the owner.
            for each(var neighbor:Rectangle in neighbors){
                var union:Rectangle=group.union(neighbor);
                if(union.width*scale<=safe.width&&union.height*scale<=safe.height)group=union;
            }
            var x:Number=safe.x+safe.width/2-(group.x+group.width/2)*scale;
            var y:Number=safe.y+safe.height/2-(group.y+group.height/2)*scale;
            // If the keyboard leaves less space than a tall avatar/bubble, preserve its top
            // (speech and face) rather than silently shrinking the whole room.
            if(group.height*scale>safe.height)y=safe.top-group.top*scale;
            if(group.width*scale>safe.width)x=safe.x+safe.width/2-(own.x+own.width/2)*scale;
            return constrain(viewport,{x:x,y:y,scale:scale});
        }
        /** Also clamp intermediate frames: keyboard dismissal/rotation can change the
         * visible rectangle before an otherwise valid tween has finished. */
        public static function constrain(viewport:Rectangle,camera:Object):Object {
            var roomWidth:Number=MobileCamera.ROOM_WIDTH*camera.scale,roomHeight:Number=MobileCamera.ROOM_HEIGHT*camera.scale;
            var x:Number=roomWidth<=viewport.width?viewport.x+(viewport.width-roomWidth)/2:
                Math.max(viewport.right-roomWidth,Math.min(viewport.left,camera.x));
            var y:Number=roomHeight<=viewport.height?viewport.y+(viewport.height-roomHeight)/2:
                Math.max(viewport.bottom-roomHeight,Math.min(viewport.top,camera.y));
            return {x:x,y:y,scale:camera.scale};
        }
        public static function approach(current:Object,target:Object,elapsedMs:Number):Object {
            var amount:Number=1-Math.exp(-Math.min(100,Math.max(0,elapsedMs))/1000*12);
            return {x:current.x+(target.x-current.x)*amount,y:current.y+(target.y-current.y)*amount,
                scale:current.scale+(target.scale-current.scale)*amount};
        }
    }
}
