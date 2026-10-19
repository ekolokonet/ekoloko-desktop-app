package {
 import flash.display.*;import flash.events.*;import flash.geom.*;import flash.utils.getTimer;import flash.utils.Dictionary;
 /** Swipe the existing ScrollPane, never translate the player card. */
 public final class NativeInventorySwipe {
  private var root:DisplayObjectContainer,screen:Stage,pane:Object,origin:Point,initial:Number,touch:int=-1,lastTouch:int=-1000;
  private var swiped:Boolean=false;
  private var surfaces:Dictionary=new Dictionary(true),gesturePane:DisplayObjectContainer,suppressUntil:int=0;
  public function NativeInventorySwipe(owner:DisplayObjectContainer){
   root=owner;screen=root.stage;
   root.addEventListener(MouseEvent.MOUSE_DOWN,down,true,1600);root.addEventListener(TouchEvent.TOUCH_BEGIN,touchDown,true,1600);root.addEventListener(MouseEvent.CLICK,click,true,1600);
   discover(root);root.addEventListener(Event.ADDED,added,true);refresh();
   if(screen){screen.addEventListener(MouseEvent.MOUSE_MOVE,move,true,1600);screen.addEventListener(MouseEvent.MOUSE_UP,up,true,1600);screen.addEventListener(TouchEvent.TOUCH_MOVE,touchMove,true,1600);screen.addEventListener(TouchEvent.TOUCH_END,touchUp,true,1600);screen.addEventListener(Event.DEACTIVATE,cancel);}
  }
  private function isPane(o:DisplayObject):Boolean{return o is DisplayObjectContainer&&"verticalScrollPosition" in o&&"maxVerticalScrollPosition" in o&&"verticalScrollBar" in o;}
  private function discover(o:DisplayObject):void {
   if(isPane(o)){install(o as DisplayObjectContainer);return;}
   var c:DisplayObjectContainer=o as DisplayObjectContainer;if(c)for(var i:int=0;i<c.numChildren;i++)discover(c.getChildAt(i));
  }
  private function added(e:Event):void{if(isPane(e.target as DisplayObject))install(e.target as DisplayObjectContainer);}
  private function install(c:DisplayObjectContainer):void {
   if(surfaces[c])return;
   // A hit surface behind the items lets gaps receive wheel and touch input.
   // It adds no visible artwork and does not cover the native scrollbar/items.
   var pad:Sprite=new Sprite();pad.name="mobileInventoryScrollSurface";pad.mouseChildren=false;
   surfaces[c]={pad:pad,w:-1,h:-1,scrollDrag:"scrollDrag" in c?Object(c).scrollDrag:false};
   if("scrollDrag" in c)Object(c).scrollDrag=false;
   c.addChildAt(pad,0);
  }
  public function refresh():void {
   for(var key:Object in surfaces){
    var c:DisplayObjectContainer=key as DisplayObjectContainer,record:Object=surfaces[key];
    if(!root.contains(c))continue;
    if(record.w!=c.width||record.h!=c.height){
     record.w=c.width;record.h=c.height;var pad:Sprite=record.pad;
     pad.graphics.clear();pad.graphics.beginFill(0,0);pad.graphics.drawRect(0,0,c.width,c.height);pad.graphics.endFill();
    }
   }
  }
  private function inControl(target:DisplayObject,control:DisplayObject):Boolean {
   return control&&(target==control||control is DisplayObjectContainer&&DisplayObjectContainer(control).contains(target));
  }
  private function begin(target:DisplayObject,x:Number,y:Number):void {
   pane=null;swiped=false;gesturePane=null;suppressUntil=0;var hit:DisplayObject=target;
   while(target&&target!=root){
    if(isPane(target)&&Number(Object(target).maxVerticalScrollPosition)>0){
     // Thumb/track/arrows belong exclusively to the original ScrollBar. A
     // content swipe uses the opposite direction and must never capture them.
     var candidate:Object=target;
     if(inControl(hit,candidate.verticalScrollBar)||inControl(hit,candidate.horizontalScrollBar))return;
     pane=target;gesturePane=target as DisplayObjectContainer;break;
    }target=target.parent;
   }
   if(pane){origin=DisplayObject(pane).globalToLocal(new Point(x,y));initial=Number(pane.verticalScrollPosition);}
  }
  private function drag(x:Number,y:Number,event:Event):void {
   if(!pane)return;
   if(!root.contains(pane as DisplayObject)){pane=null;return;}
   var now:Point=DisplayObject(pane).globalToLocal(new Point(x,y)),delta:Number=origin.y-now.y;
   if(Math.abs(delta)>8)swiped=true;
   if(swiped){pane.verticalScrollPosition=Math.max(0,Math.min(Number(pane.maxVerticalScrollPosition),initial+delta));event.stopImmediatePropagation();}
  }
  private function down(e:MouseEvent):void{if(getTimer()-lastTouch<600)return;begin(e.target as DisplayObject,e.stageX,e.stageY);}
  private function move(e:MouseEvent):void{if(touch<0)drag(e.stageX,e.stageY,e);}
  private function up(e:MouseEvent):void{if(touch<0){pane=null;if(swiped)suppressUntil=getTimer()+600;}}
  private function touchDown(e:TouchEvent):void{lastTouch=getTimer();touch=e.touchPointID;begin(e.target as DisplayObject,e.stageX,e.stageY);}
  private function touchMove(e:TouchEvent):void{if(touch==e.touchPointID)drag(e.stageX,e.stageY,e);}
  private function touchUp(e:TouchEvent):void{if(touch==e.touchPointID){lastTouch=getTimer();touch=-1;pane=null;if(swiped)suppressUntil=getTimer()+600;}}
  private function click(e:MouseEvent):void{if(swiped&&getTimer()<=suppressUntil&&gesturePane&&gesturePane.contains(e.target as DisplayObject)){e.stopImmediatePropagation();swiped=false;}}
  private function cancel(e:Event):void{pane=null;gesturePane=null;touch=-1;swiped=false;}
  public function dispose():void{
   root.removeEventListener(MouseEvent.MOUSE_DOWN,down,true);root.removeEventListener(TouchEvent.TOUCH_BEGIN,touchDown,true);root.removeEventListener(MouseEvent.CLICK,click,true);
   root.removeEventListener(Event.ADDED,added,true);
   for(var key:Object in surfaces){var c:DisplayObjectContainer=key as DisplayObjectContainer,record:Object=surfaces[key];if(record.pad.parent)record.pad.parent.removeChild(record.pad);if("scrollDrag" in c)Object(c).scrollDrag=record.scrollDrag;}
   surfaces=new Dictionary(true);
   if(screen){screen.removeEventListener(MouseEvent.MOUSE_MOVE,move,true);screen.removeEventListener(MouseEvent.MOUSE_UP,up,true);screen.removeEventListener(TouchEvent.TOUCH_MOVE,touchMove,true);screen.removeEventListener(TouchEvent.TOUCH_END,touchUp,true);screen.removeEventListener(Event.DEACTIVATE,cancel);}
  }
 }
}
