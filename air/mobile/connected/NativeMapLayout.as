package {
 import flash.display.DisplayObject;import flash.geom.Rectangle;
 /** The authored map canvas and shutter handle, excluding hidden region labels. */
 public final class NativeMapLayout {
  public static function bounds():Rectangle{return new Rectangle(-4,-16,865,590);}
  public static function fit(panel:DisplayObject,safe:Rectangle,offset:Number,position:Function):void{
   var b:Rectangle=bounds(),area:Rectangle=safe.clone();area.inflate(-4,-4);
   var scale:Number=Math.min(area.width/b.width,area.height/b.height);
   var top:Number=area.y+(area.height-b.height*scale)/2;
   // The entire map, including its close handle, travels off the top edge.
   var travel:Number=top+b.height*scale+4;
   position(panel,area.x+(area.width-b.width*scale)/2-b.x*scale,
    top-b.y*scale+Math.max(-1,Math.min(0,offset))*travel,scale,scale);
  }
 }
}
