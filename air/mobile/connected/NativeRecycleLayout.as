package {
 import flash.display.DisplayObject;import flash.geom.Rectangle;
 /** Original 960px reward panel, including its bottom shutter handle. */
 public final class NativeRecycleLayout {
  public static function bounds():Rectangle{return new Rectangle(-1,-5,962,534);}
  public static function fit(panel:DisplayObject,safe:Rectangle,offset:Number,position:Function):void {
   var b:Rectangle=bounds(),area:Rectangle=safe.clone();area.inflate(-4,-4);
   var s:Number=Math.min(area.width/b.width,area.height/b.height);
   var top:Number=area.y+(area.height-b.height*s)/2;
   position(panel,area.x+(area.width-b.width*s)/2-b.x*s,
    top-b.y*s+Math.max(-1,Math.min(0,offset))*(top+b.height*s+4),s,s);
  }
 }
}
