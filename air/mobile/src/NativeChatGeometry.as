package {
 import flash.display.*;import flash.geom.*;import flash.utils.Dictionary;import flash.text.*;
 /** Measure the actual light input opening in the original chat skin once. */
 public final class NativeChatGeometry {
  private static var cache:Dictionary=new Dictionary(true);
  /** A single inward-rounded viewport shared by native and Flash input. */
  public static function inputBounds(art:DisplayObject,space:DisplayObject,sendLeft:Number):Rectangle {
   var white:Rectangle=opening(art);if(!white)return new Rectangle();
   var start:Point=space.globalToLocal(art.localToGlobal(white.topLeft));
   var end:Point=space.globalToLocal(art.localToGlobal(white.bottomRight));
   var left:Number=Math.ceil(start.x+2),top:Number=Math.ceil(start.y+1);
   var right:Number=Math.floor(Math.min(end.x-2,sendLeft-6)),bottom:Number=Math.floor(end.y-1);
   return new Rectangle(left,top,Math.max(0,right-left),Math.max(0,bottom-top));
  }
  public static function constrain(field:TextField,rect:Rectangle,clip:Boolean=true):void {
   if(field.autoSize!=TextFieldAutoSize.NONE)field.autoSize=TextFieldAutoSize.NONE;
   if(field.multiline)field.multiline=false;if(field.wordWrap)field.wordWrap=false;
   if(Math.abs(field.width-rect.width)>.01)field.width=rect.width;
   if(Math.abs(field.height-rect.height)>.01)field.height=rect.height;
   var viewport:Rectangle=new Rectangle(0,0,rect.width,rect.height);
   if(clip){if(!field.scrollRect||!field.scrollRect.equals(viewport))field.scrollRect=viewport;}
   else if(field.scrollRect)field.scrollRect=null;
  }
  /** StageText's viewport follows stage coordinates; its font size is in pixels. */
  public static function stageBounds(space:DisplayObject,rect:Rectangle):Rectangle {
   var a:Point=space.localToGlobal(rect.topLeft),b:Point=space.localToGlobal(rect.bottomRight);
   var x:Number=Math.ceil(a.x),y:Number=Math.ceil(a.y);
   return new Rectangle(x,y,Math.max(0,Math.floor(b.x)-x),Math.max(0,Math.floor(b.y)-y));
  }
  public static function opening(art:DisplayObject):Rectangle {
   if(cache[art])return Rectangle(cache[art]).clone();
   var bounds:Rectangle=art.getBounds(art);if(bounds.width<2||bounds.height<2||bounds.width>16384||bounds.height>1024)return null;
   var pixels:BitmapData=new BitmapData(Math.ceil(bounds.width),Math.ceil(bounds.height),true,0);pixels.draw(art,new Matrix(1,0,0,1,-bounds.x,-bounds.y));
   var first:int=-1,best:int=0,left:int=0,y:int=int(pixels.height/2),x:int;
   for(x=0;x<=pixels.width;x++){
    if(x<pixels.width&&light(pixels.getPixel32(x,y))){if(first<0)first=x;}
    else if(first>=0){if(x-first>best){best=x-first;left=first;}first=-1;}
   }
   if(best<20){pixels.dispose();return null;}
   x=left+int(best/2);var top:int=y,bottom:int=y;
   while(top>0&&light(pixels.getPixel32(x,top-1)))top--;
   while(bottom+1<pixels.height&&light(pixels.getPixel32(x,bottom+1)))bottom++;
   // Intersect the white span on every row, not just the widest center row.
   // This also handles caps deformed by the legacy stretch / nine-slice skin.
   top++;bottom--;var right:int=left+best;
   for(var row:int=top;row<=bottom;row++){
    var a:int=x,b:int=x;
    while(a>0&&light(pixels.getPixel32(a-1,row)))a--;
    while(b+1<pixels.width&&light(pixels.getPixel32(b+1,row)))b++;
    left=Math.max(left,a);right=Math.min(right,b+1);
   }
   pixels.dispose();var result:Rectangle=new Rectangle(bounds.x+left,bounds.y+top,Math.max(0,right-left),Math.max(0,bottom-top+1));cache[art]=result;return result.clone();
  }
  private static function light(pixel:uint):Boolean {var r:int=(pixel>>16)&255,g:int=(pixel>>8)&255,b:int=pixel&255;return (pixel>>>24)>240&&r>220&&g>220&&b>220&&Math.max(r,g,b)-Math.min(r,g,b)<12;}
 }
}
