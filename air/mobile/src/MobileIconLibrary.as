package {
    import flash.display.DisplayObject;
    import flash.display.Sprite;
    import flash.geom.Rectangle;
    /** Standalone Flash vector library and contact sheet. No bitmap assets. */
    [SWF(width="800",height="340",backgroundColor="#173d32",frameRate="30")]
    public final class MobileIconLibrary extends Sprite {
        public function MobileIconLibrary() {
            for(var i:int=0;i<MobileActionArt.IDS.length;i++){
                var art:DisplayObject=createIcon(MobileActionArt.IDS[i]);
                var r:Rectangle=art.getBounds(art),s:Number=Math.min(136/r.width,136/r.height);
                art.scaleX=art.scaleY=s;art.x=(i%5)*160+12-r.x*s;art.y=int(i/5)*170+12-r.y*s;addChild(art);
                var small:DisplayObject=createIcon(MobileActionArt.IDS[i]);r=small.getBounds(small);s=Math.min(44/r.width,44/r.height);
                small.scaleX=small.scaleY=s;small.x=(i%5)*160+108-r.x*s;small.y=int(i/5)*170+120-r.y*s;addChild(small);
            }
        }
        public function createIcon(id:String):DisplayObject {return MobileActionArt.make(id);}
    }
}
