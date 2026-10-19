package {
 import flash.display.*;import flash.geom.*;import flash.events.*;import flash.utils.*;
 /** Retains native content, fonts, controls and callbacks in a top-edge drawer. */
 public final class MobileNativeDrawer extends Sprite {
  private var root:DisplayObjectContainer,position:Function,bounds:Rectangle,originalScroll:Rectangle;
  private var box:Object,swipe:NativeInventorySwipe;
  private var labels:NativeProfileLabels;
  private var storage:DisplayObject,storageLayer:Sprite,storageIndex:int;
  private var popupMatrices:Dictionary=new Dictionary(true);
  public function MobileNativeDrawer(panel:DisplayObjectContainer,setPosition:Function){
   root=panel;position=setPosition;originalScroll=root.scrollRect;
   var art:DisplayObject="window" in root?Object(root).window as DisplayObject:null;
   if(art)bounds=art.getBounds(root).clone();
   else bounds=new Rectangle(-1,-11,515,404); // Native MyAnimalPanel's outer panel shape.
   var nativeClose:DisplayObject=Object(root).closeBut as DisplayObject;
   if(nativeClose)bounds=bounds.union(nativeClose.getBounds(root));
   storage="storageContainer" in root?Object(root).storageContainer as DisplayObject:null;
   // Include the original protruding help/storage handles in the fixed frame.
   for(var i:int=0;i<root.numChildren;i++){
    var part:DisplayObjectContainer=root.getChildAt(i) as DisplayObjectContainer;
    var handle:DisplayObject=part?part.getChildByName("closeBut"):null;
    if(!handle)continue;var handleBounds:Rectangle=handle.getBounds(root);
    if(part==storage)handleBounds.x-=storage.x;
    if(handleBounds.width<100&&handleBounds.height<100&&handleBounds.x>bounds.x-100&&handleBounds.right<bounds.right+100)bounds=bounds.union(handleBounds);
   }
   bounds.inflate(3,0);
   if(storage){storageIndex=root.getChildIndex(storage);storageLayer=new Sprite();storageLayer.mouseEnabled=false;root.addChildAt(storageLayer,storageIndex);storageLayer.addChild(storage);}
   swipe=new NativeInventorySwipe(root);
   labels=new NativeProfileLabels(root);
   mouseEnabled=false;

  }
  public function refresh(w:Number,h:Number,available:Number,offset:Number=0):void {
   // The keyboard closes when a card opens; the entire fixed frame stays visible.
   box=MobileDrawerLayout.calculate(w,h,h,bounds);
   for each(var name:String in ["giveKokosPane","gameDataPanel","pokeDataPanel","blockChatDataPanel","snitchPanel","dropItemConfirm","setRecycleItemDropQuantity","dropRecycleItemConfirm","confirmBG","notEnoughMoney","buyAck"]){
    if(!(name in root))continue;var child:DisplayObject=Object(root)[name];if(!child)continue;
    if(!child.visible||child.alpha<=0){if(popupMatrices[child]){child.transform.matrix=popupMatrices[child];delete popupMatrices[child];}continue;}
    var extra:Rectangle=child.getBounds(root);
    if(!bounds.containsRect(extra)&&extra.width>0&&extra.height>0){
     if(!popupMatrices[child])popupMatrices[child]=child.transform.matrix.clone();
     var fit:Number=Math.min(1,(bounds.width-16)/extra.width,(bounds.height-16)/extra.height);
     if(fit<1){child.scaleX*=fit;child.scaleY*=fit;extra=child.getBounds(root);}
     child.x+=Math.max(bounds.x+8,Math.min(extra.x,bounds.right-8-extra.width))-extra.x;
     child.y+=Math.max(bounds.y+8,Math.min(extra.y,bounds.bottom-8-extra.height))-extra.y;
    }
   }
   // Only internal lists are clipped. The native help/storage tabs extend beyond
   // the window artwork, and storage owns its own slide tween and x coordinate.
   position(root,box.x-bounds.x*box.scale,box.height*offset-bounds.y*box.scale,box.scale,box.scale);
   if(storage){
    var storageBounds:Rectangle=storage.getBounds(root);storageBounds.x-=storageLayer.x;
    var rightLimit:Number=bounds.x+(w-8-box.x)/box.scale;
    storageLayer.x=Math.min(0,rightLimit-storageBounds.right);
    // On narrow screens the drawer overlays the card rather than leaving the
    // screen. Its native x tween and callbacks remain owned by Inventory.
    root.setChildIndex(storageLayer,storageLayer.x<-.1?root.numChildren-1:Math.min(storageIndex,root.numChildren-1));
   }
   swipe.refresh();labels.refresh();
   visible=offset>-.98;
  }
  public function dispose():void{
   swipe.dispose();labels.dispose();root.scrollRect=originalScroll;
   if(storage){root.addChildAt(storage,Math.min(storageIndex,root.numChildren));root.removeChild(storageLayer);}
   for(var item:Object in popupMatrices)DisplayObject(item).transform.matrix=popupMatrices[item];
   if(parent)parent.removeChild(this);
  }
 }
}
