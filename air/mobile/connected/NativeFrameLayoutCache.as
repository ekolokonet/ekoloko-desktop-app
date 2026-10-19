package {
 import flash.display.*;
 import flash.text.TextField;
 /** Cache only presentation work. Animation/camera/input clocks remain independent. */
 public final class NativeFrameLayoutCache {
  private var dirty:Boolean=true,states:Array=[];
  public function invalidate():void{dirty=true;}
  public function clear():void{states=[];dirty=true;}
  public function needs(objects:Array,continuous:Boolean=false):Boolean {
   if(continuous||dirty||states.length!=objects.length)return true;
   for(var i:int=0;i<objects.length;i++)if(!same(states[i],objects[i]))return true;
   return false;
  }
  public function commit(objects:Array):void {
   states=[];for each(var o:DisplayObject in objects)states.push(snapshot(o));dirty=false;
  }
  private function snapshot(o:DisplayObject):Object {
   if(!o)return {object:null};
   var c:DisplayObjectContainer=o as DisplayObjectContainer,t:TextField=o as TextField,hit:InteractiveObject=o as InteractiveObject;
   return {object:o,parent:o.parent,x:o.x,y:o.y,sx:o.scaleX,sy:o.scaleY,rotation:o.rotation,visible:o.visible,alpha:o.alpha,
    children:c?c.numChildren:-1,mouse:hit?hit.mouseEnabled:false,mouseChildren:c?c.mouseChildren:false,
    text:t?t.text:null,width:t?t.width:0,height:t?t.height:0,type:t?t.type:null,wrap:t?t.wordWrap:false,multiline:t?t.multiline:false,auto:t?t.autoSize:null};
  }
  private function same(s:Object,o:DisplayObject):Boolean {
   if(s.object!==o)return false;if(!o)return true;
   var c:DisplayObjectContainer=o as DisplayObjectContainer,t:TextField=o as TextField,hit:InteractiveObject=o as InteractiveObject;
   return s.parent===o.parent&&near(s.x,o.x)&&near(s.y,o.y)&&near(s.sx,o.scaleX)&&near(s.sy,o.scaleY)&&near(s.rotation,o.rotation)&&s.visible==o.visible&&s.alpha==o.alpha&&
    s.children==(c?c.numChildren:-1)&&s.mouse==(hit?hit.mouseEnabled:false)&&s.mouseChildren==(c?c.mouseChildren:false)&&
    (!t||(s.text==t.text&&near(s.width,t.width)&&near(s.height,t.height)&&s.type==t.type&&s.wrap==t.wordWrap&&s.multiline==t.multiline&&s.auto==t.autoSize));
  }
  private function near(a:Number,b:Number):Boolean{return Math.abs(a-b)<.0001;}
 }
}
