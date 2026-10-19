package {
    import flash.geom.Rectangle;
    public final class MobileCamera {
        public static const ROOM_WIDTH:Number=960;
        public static const ROOM_HEIGHT:Number=600;

        /** Scale depends on the unoccluded screen, never on keyboard height. */
        public static function followScale(screenWidth:Number,screenHeight:Number):Number {
            return Math.max(.9,Math.max(screenWidth,screenHeight)/960);
        }
        public static function follow(viewport:Rectangle,scale:Number,playerX:Number,playerY:Number,
                                      currentX:Number,currentY:Number,snap:Boolean):Object {
            if(snap)return calculate(viewport,scale,playerX,playerY,false);
            var x:Number=currentX,y:Number=currentY;
            var screenX:Number=x+playerX*scale,screenY:Number=y+playerY*scale;
            var marginX:Number=viewport.width*.28,marginY:Number=viewport.height*.25;
            if(screenX<marginX)x+=marginX-screenX;
            if(screenX>viewport.width-marginX)x+=viewport.width-marginX-screenX;
            if(screenY<marginY)y+=marginY-screenY;
            if(screenY>viewport.height-marginY)y+=viewport.height-marginY-screenY;
            x=scale*960<=viewport.width?(viewport.width-scale*960)/2:Math.max(viewport.width-scale*960,Math.min(0,x));
            y=scale*600<=viewport.height?(viewport.height-scale*600)/2:Math.max(viewport.height-scale*600,Math.min(0,y));
            return {x:x,y:y,scale:scale};
        }
        public static function smoothFollow(viewport:Rectangle,scale:Number,playerX:Number,playerY:Number,
                                            current:Object,elapsedMs:Number):Object {
            var target:Object=follow(viewport,scale,playerX,playerY,current.x,current.y,false);
            var amount:Number=1-Math.exp(-Math.min(100,Math.max(0,elapsedMs))/1000*12);
            return {scale:scale,x:current.x+(target.x-current.x)*amount,y:current.y+(target.y-current.y)*amount};
        }
        public static function calculate(viewport:Rectangle,scale:Number,playerX:Number,
                                         playerY:Number,overview:Boolean):Object {
            if(overview) scale=Math.min(viewport.width/ROOM_WIDTH,viewport.height/ROOM_HEIGHT);
            var width:Number=ROOM_WIDTH*scale,height:Number=ROOM_HEIGHT*scale;
            var x:Number=width<=viewport.width?(viewport.width-width)/2:
                Math.max(viewport.width-width,Math.min(0,viewport.width/2-playerX*scale));
            var y:Number=height<=viewport.height?(viewport.height-height)/2:
                Math.max(viewport.height-height,Math.min(0,viewport.height/2-playerY*scale));
            return {x:x,y:y,scale:scale};
        }
    }
}
