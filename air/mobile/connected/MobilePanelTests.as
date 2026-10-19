package {
 import flash.display.*;import flash.events.*;import flash.geom.*;import flash.filesystem.*;import flash.desktop.NativeApplication;import flash.text.*;import flash.utils.getQualifiedClassName;
 public final class MobilePanelTests extends Sprite {
  [Embed(source="../../build/mobile-lab/assets/ui.swf",symbol="OtherPlayerData")] private var Other:Class;
  [Embed(source="../../build/mobile-lab/assets/ui.swf",symbol="MyPlayerPanelMC")] private var Own:Class;
  [Embed(source="../../build/mobile-lab/assets/ui.swf",symbol="MyAnimalPanel")] private var Pet:Class;
  private var canvas:Sprite=new Sprite();
  public function MobilePanelTests(){
   loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR,function(e:UncaughtErrorEvent):void{e.preventDefault();trace("PANEL_FAIL "+e.error);NativeApplication.nativeApplication.exit(2);});addChild(canvas);
   var n:int=0;
   for each(var type:Class in [Other,Own,Pet]){
    var panel:DisplayObjectContainer=new type();GameArtwork.stopTree(panel);canvas.addChild(panel);
    for each(var name:String in ["giveKokosPane","gameDataPanel","pokeDataPanel","blockChatDataPanel","snitchPanel","moreInfo","storageContainer","gamesBG","bgMask","dropItemConfirm","setRecycleItemDropQuantity","dropRecycleItemConfirm","awaySign","confirmBG","notEnoughMoney","buyAck"]){if(name in panel)Object(panel)[name].visible=false;}
    for(var i:int=0;i<panel.numChildren;i++){var child:DisplayObject=panel.getChildAt(i);if(child is TextField&&TextField(child).text.length)TextField(child).text=TextField(child).text;}
    if(n==1){
     var caption:TextField=Object(panel).seniorityLevelNameText;caption.text="לונה קיד";
     var lock:TextField=Object(panel).securityButton.lockItemsText;lock.text="החפצים שלי\nאינם מאובטחים";
     var fmt:TextFormat=new TextFormat("Arial",12,0x333333,true);fmt.align="center";var originalCaption:String=caption.text,originalLock:String=lock.text;caption.defaultTextFormat=fmt;caption.setTextFormat(fmt);lock.defaultTextFormat=fmt;lock.setTextFormat(fmt);
    }
    var drawer:MobileNativeDrawer=new MobileNativeDrawer(panel,position);canvas.addChild(drawer);
    for each(var size:Array in [[844,358,358],[390,812,812],[844,358,182],[1024,736,736]]){
     drawer.refresh(size[0],size[1],size[2],0);capture("panel-"+n+"-"+size[0]+"-"+size[2],size[0],size[1]);
     var before:Rectangle=panel.scrollRect,beforeMatrix:Matrix=panel.transform.matrix.clone();
     panel.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_DOWN,true,false,100,100));stage.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_MOVE,true,false,230,260));stage.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_UP,true,false,230,260));panel.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_WHEEL,true,false,100,100,null,false,false,false,false,-4));drawer.refresh(size[0],size[1],size[2],0);
     if(panel.scrollRect!=before||panel.x!=beforeMatrix.tx||panel.y!=beforeMatrix.ty)throw new Error("profile_moved_on_drag_or_wheel");
    }
    if(n==0){
     drawer.refresh(844,358,358,0);var stable:Matrix=panel.transform.matrix.clone();var popup:DisplayObject=Object(panel).pokeDataPanel;popup.visible=true;popup.y+=315;drawer.refresh(844,358,358,0);
     if(panel.scaleX!=stable.a||panel.x!=stable.tx)throw new Error("profile_resized_for_subpanel");
     if(drawer.numChildren!=0)throw new Error("redundant_external_controls_present");
     if(panel.scrollRect)throw new Error("native_side_controls_clipped");capture("panel-expanded",844,358);
    }
    if(n==1){
     var storage:DisplayObject=Object(panel).storageContainer;storage.visible=true;
     Object(panel).logo.visible=false;
     for each(var storageX:Number in [0,77,154]){storage.x=storageX;drawer.refresh(844,358,358,0);if(storage.x!=storageX)throw new Error("native_storage_tween_overwritten");capture("panel-storage-"+storageX,844,358);}
     storage.x=154;drawer.refresh(390,812,812,0);if(storage.getBounds(canvas).right>383)throw new Error("portrait_storage_outside_screen");capture("panel-storage-portrait",390,812);
     if(caption.text!=originalCaption||lock.text!=originalLock)throw new Error("native_caption_changed");
    }
    drawer.dispose();if(n==1&&(caption.alpha!=1||lock.alpha!=1))throw new Error("native_caption_not_restored");if(panel.scrollRect!=null)throw new Error("scroll_not_restored");canvas.removeChild(panel);n++;
   }
   var menu:DisplayObjectContainer=new OriginalUI.Menu();GameArtwork.stopTree(menu);var house:DisplayObjectContainer=Object(menu).myHouse;
   var b:Rectangle=house.getChildAt(0).getBounds(house);if(b.width<40||b.width>55)throw new Error("house_icon_bounds");
   trace("PANEL_PASS native_art_renders=17 house_target=48 original_scroll_restored=true");NativeApplication.nativeApplication.exit(0);
  }
  private function position(o:DisplayObject,x:Number,y:Number,sx:Number,sy:Number):void{o.transform.matrix=new Matrix(sx,0,0,sy,x,y);}
  private function capture(name:String,w:int,h:int):void {
   var pixels:BitmapData=new BitmapData(w*2,h*2,false,0x286F38);pixels.draw(canvas,new Matrix(2,0,0,2));var out:FileStream=new FileStream();out.open(File.applicationStorageDirectory.resolvePath(name+".png"),FileMode.WRITE);out.writeBytes(pixels.encode(pixels.rect,new PNGEncoderOptions()));out.close();pixels.dispose();
  }
 }
}
