package {
    /** Calls the existing Main/WorldRoom navigation path, never the socket. */
    public final class ConnectedGameInput {
        public static function move(main:Object,dx:Number,dy:Number):Boolean {
            if(!main||!main.room||!main.myPlayer||!main.room.active||main.isMenuOpened()||main.isIninWorldGame())return false;
            var p:Object=main.myPlayer,n:Number=Math.sqrt(dx*dx+dy*dy);if(n<.05)return false;
            dx/=n;dy/=n;
            for(var distance:int=55;distance>=10;distance-=15){
                var x:int=Math.round(p.x+dx*distance),y:int=Math.round(p.y+dy*distance);
                if(x<0||x>959||y<0||y>599||!main.IsWalkable(x,y))continue;
                var direction:*=main.room.walkPlayer(p.getPlayerId(),x,y,false);
                main.SetMyPositionVariables(x,y,direction,false);return true;
            }return false;
        }
    }
}
