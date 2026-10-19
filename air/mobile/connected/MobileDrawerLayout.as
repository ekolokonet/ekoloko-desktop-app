package {
 import flash.geom.Rectangle;
 /** Scale stays independent of keyboard height; occlusion adds scrolling instead. */
 public final class MobileDrawerLayout {
  public static function calculate(w:Number,h:Number,available:Number,bounds:Rectangle):Object {
   var portrait:Boolean=h>w;
   var scale:Number=Math.min(1.65,(w-(portrait?24:112))/bounds.width,(h-(portrait?64:12))/bounds.height);
   var width:Number=bounds.width*scale,height:Number=Math.min(bounds.height*scale,Math.max(60,available-(portrait?56:8)));
   return {portrait:portrait,scale:scale,x:(w-width)/2,y:0,width:width,height:height,maxScroll:Math.max(0,bounds.height-height/scale)};
  }
 }
}
