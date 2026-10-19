package {
 import flash.display.*;import flash.geom.*;import flash.text.*;
 /** Original skin, actual raster bounds, long input and fractional placement. */
 public final class NativeChatBoundsTests {
  public static function run(space:Sprite):int {
   var checks:int=0;
   for each(var w:Number in [160,236,260,343,620,796,1000,1640,3200])for each(var h:Number in [36,44,48])for each(var sliced:Boolean in [false,true]){
    var container:Sprite=new Sprite();space.addChild(container);
    var art:DisplayObject;
    var skinHeight:Number=h<40?46:h,crop:Number=(skinHeight-h)/2;
    if(sliced)art=OriginalUI.chatBackground(w,skinHeight);
    else {
     var nativeBox:DisplayObjectContainer=new OriginalUI.Chat();GameArtwork.stopTree(nativeBox);
     art=nativeBox.getChildAt(0);var b:Rectangle=art.getBounds(art);
     art.scaleX=w/b.width;art.scaleY=skinHeight/b.height;art.x=-b.x*art.scaleX;art.y=-b.y*art.scaleY;
    }
    art.y-=crop;container.addChild(art);container.x=12.35;container.y=30.65;
    var r:Rectangle=NativeChatGeometry.inputBounds(art,space,container.x+w-41);
    if(r.isEmpty()||r.right>container.x+w-47||r.x<container.x||r.bottom>container.y+h)throw new Error("chat_viewport_bounds "+w);
    if(h==36&&sliced&&r.height<20)throw new Error("compact_chat_text_height "+r);
    var pixels:BitmapData=new BitmapData(Math.ceil(w+30),Math.ceil(h+65),true,0);pixels.draw(container,new Matrix(1,0,0,1,container.x,container.y));
    // Every pixel in the permitted text rectangle must be inside the white opening.
    for(var y:int=r.top;y<r.bottom;y++)for(var x:int=r.left;x<r.right;x++){
     var rgb:uint=pixels.getPixel(x,y);if(((rgb>>16)&255)<215||((rgb>>8)&255)<215||(rgb&255)<215)throw new Error("chat_outside_white w="+w+" sliced="+sliced+" at="+x+","+y);
    }
    pixels.dispose();
    var field:TextField=new TextField();field.defaultTextFormat=new TextFormat("Arial",16,0x000000,true,null,null,null,null,"right");
    field.type=TextFieldType.INPUT;field.autoSize=TextFieldAutoSize.RIGHT;field.text=new Array(80).join("שלום ABC 123 ");
    NativeChatGeometry.constrain(field,r);field.setSelection(field.length,field.length);
    var ink:BitmapData=new BitmapData(r.width+40,r.height+40,true,0);ink.draw(field,new Matrix(1,0,0,1,20,20));
    var visible:Rectangle=ink.getColorBoundsRect(0xff000000,0,false);
    if(visible.isEmpty()||!new Rectangle(20,20,r.width,r.height).containsRect(visible))throw new Error("chat_ink_clip w="+w+" rect="+r);
    ink.dispose();space.removeChild(container);checks++;
   }
   trace("CHAT_BOUNDS_PASS cases="+checks+" all_pixels_inside_white=true long_rtl_ltr_clipped=true");return checks;
  }
 }
}
