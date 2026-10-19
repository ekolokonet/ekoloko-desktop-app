package {
 import flash.display.*;import flash.system.LoaderContext;import flash.system.ApplicationDomain;import org.ekoloko.air.NativeServices;import flash.utils.setTimeout;import flash.events.*;import flash.text.*;import flash.geom.*;import flash.filesystem.*;import flash.desktop.NativeApplication;
 public final class MobileEntryTests extends Sprite {
  private var canvas:Sprite;
  [Embed(source="../../build/mobile-connected/login-timeline.swf",mimeType="application/octet-stream")] private var LoginScene:Class;
  private var shell:Loader=new Loader(),login:Loader=new Loader();
  [Embed(source="../../build/mobile-connected/selector-timeline.swf",mimeType="application/octet-stream")] private var SelectorArt:Class;
  [Embed(source="../../build/mobile-connected/selector-visual.swf",symbol="ChannelSlotMC")] private var SlotArt:Class;
  public function MobileEntryTests(){
   loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR,function(e:UncaughtErrorEvent):void{e.preventDefault();trace("ENTRY_FAIL "+e.error);NativeApplication.nativeApplication.exit(2);});
   NativeServices.initialize();
   shell.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR,failed);
   login.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR,failed);
   shell.contentLoaderInfo.addEventListener(Event.COMPLETE,function(e:Event):void{
    var context:LoaderContext=new LoaderContext(false,new ApplicationDomain(shell.contentLoaderInfo.applicationDomain));context.allowCodeImport=true;login.loadBytes(NativeServices.readAsset("website/iw/login_iw.swf"),context);
   });
   login.contentLoaderInfo.addEventListener(Event.COMPLETE,function(e:Event):void{
    var type:Class=login.contentLoaderInfo.applicationDomain.getDefinition("Login") as Class;
    loadLoginScene(new type());
   });
   var context:LoaderContext=new LoaderContext(false,new ApplicationDomain(ApplicationDomain.currentDomain));context.allowCodeImport=true;shell.loadBytes(NativeServices.readAsset("shell.swf"),context);
  }
  private function failed(e:UncaughtErrorEvent):void{e.preventDefault();trace("ENTRY_FAIL "+(e.error is Error?Error(e.error).getStackTrace():e.error));NativeApplication.nativeApplication.exit(2);}
  private function loadLoginScene(form:DisplayObjectContainer):void {
   var loader:Loader=new Loader();loader.contentLoaderInfo.addEventListener(Event.COMPLETE,function(e:Event):void{
    var scene:MovieClip=loader.content as MovieClip;scene.gotoAndStop(90);GameArtwork.stopTree(scene);
    var native:Object=scene;native.bigLeaf.gotoAndStop(2);native.loginScreen.visible=true;
    var old:DisplayObject=native.loginScreen;form.transform.matrix=old.transform.matrix;scene.addChildAt(form,scene.getChildIndex(old));scene.removeChild(old);native.loginScreen=form;
    Object(form).message.visible=false;
    var container:Sprite=new Sprite();canvas=container;addChild(container);container.addChild(scene);
    var entry:MobileEntryUI=new MobileEntryUI(position);container.addChild(entry);
    var original:Matrix=native.bigLeaf.transform.matrix.clone(),originalForm:Matrix=form.transform.matrix.clone();
    entry.update(scene,844,358);
    if(native.bannerLoader.visible)throw new Error("mobile_bottom_banner_visible");
    for each(var hidden:String in ["leaf1","leaf2","leaf5","leaf7"])if(native[hidden].visible)throw new Error("obsolete_purchase_leaf_visible_"+hidden);
    if(native.leaf4.accessibilityProperties.name!="מחיקת חשבון")throw new Error("deletion_label_missing");
    if(MobileEntryActions.accountDeletionEnabled)throw new Error("unpublished_deletion_enabled");
    var obsoleteCalls:int=0;
    native.leaf4.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void{obsoleteCalls++;});
    Object(form).registerBut.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void{obsoleteCalls++;});
    native.leaf4.dispatchEvent(new MouseEvent(MouseEvent.CLICK,true));capture(container,"deletion-unavailable-wide",844,358);
    var actions:DisplayObjectContainer=entry.getChildByName("mobileEntryActions") as DisplayObjectContainer;
    var notice:DisplayObjectContainer=actions.getChildByName("mobileEntryNotice") as DisplayObjectContainer;
    if(!notice)throw new Error("deletion_click_fell_through");notice.getChildByName("action-close").dispatchEvent(new MouseEvent(MouseEvent.CLICK,true));
    Object(form).registerBut.dispatchEvent(new MouseEvent(MouseEvent.CLICK,true));capture(container,"register-notice-wide",844,358);
    notice=actions.getChildByName("mobileEntryNotice") as DisplayObjectContainer;
    if(!notice||notice.accessibilityProperties.name!=MobileEntryActions.REGISTER_NOTICE)throw new Error("register_notice_missing");if(obsoleteCalls)throw new Error("legacy_entry_action_not_blocked");notice.getChildByName("action-close").dispatchEvent(new MouseEvent(MouseEvent.CLICK,true));
    var initial:Matrix=scene.transform.matrix.clone();
    scene.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_WHEEL,true,false,400,250,null,false,false,false,false,-9));
    scene.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_DOWN,true,false,400,250));
    stage.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_MOVE,true,false,400,80));
    stage.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_UP,true,false,400,80));
    entry.update(scene,844,358);
    if(scene.transform.matrix.toString()!=initial.toString())throw new Error("login_scroll_moves_default_framing");
    setTimeout(function():void{
     entry.update(scene,844,358);capture(container,"login-full-wide",844,358);
     if(native.bigLeaf.transform.matrix.toString()!=original.toString()||form.transform.matrix.toString()!=originalForm.toString())throw new Error("login_end_frame_jumps_from_native_position");
     // The visual timeline recreates its placeholder form as frames change.
     // Remove our injected real form first, then reattach it after the sweep.
     if(form.parent==scene)scene.removeChild(form);
     for each(var frame:int in [1,40,80,90]){
      scene.gotoAndStop(frame);entry.update(scene,844,358);
      if(scene.transform.matrix.toString()!=initial.toString())throw new Error("login_transition_changes_viewport");
      if(native.bannerLoader.visible)throw new Error("banner_reappeared_during_login");
      capture(container,"login-frame-"+frame,844,358);
     }
     old=native.loginScreen;form.transform.matrix=originalForm.clone();scene.addChildAt(form,scene.getChildIndex(old));scene.removeChild(old);native.loginScreen=form;
     native.bigLeaf.gotoAndStop(2);native.loginScreen.visible=true;
     entry.update(scene,390,812);setTimeout(function():void{
      entry.update(scene,390,812);capture(container,"login-full-portrait",390,812);
      Object(form).registerBut.dispatchEvent(new MouseEvent(MouseEvent.CLICK,true));capture(container,"register-notice-portrait",390,812);
      var resets:int=0;
      notice=actions.getChildByName("mobileEntryNotice") as DisplayObjectContainer;
      notice.addEventListener(Event.REMOVED,function(event:Event):void{
       if(event.target!=notice)return;resets++;entry.reset();
       if(entry.update(scene,390,812))throw new Error("entry_updated_during_reset");
      });
      var restoredLeaf:SimpleButton=native.leaf4;
      var leafEvents:int=0;
      restoredLeaf.upState.addEventListener(Event.REMOVED_FROM_STAGE,function(event:Event):void{leafEvents++;MobileEntryActions(actions).reset();});
      entry.reset();entry.reset();MobileEntryActions(actions).reset();
      if(resets!=1)throw new Error("notice_reset_reentrancy_not_exercised");
      trace("ENTRY_RESET_PASS notice_reentrant="+resets+" leaf_events="+leafEvents);
      if(native.bigLeaf.transform.matrix.toString()!=original.toString())throw new Error("login_matrix_not_restored");
      removeChild(container);loadSelector();
     },100);
    },100);
   });var context:LoaderContext=new LoaderContext();context.allowCodeImport=true;loader.loadBytes(new LoginScene(),context);
  }
  private function loadSelector():void {
   var loader:Loader=new Loader();loader.contentLoaderInfo.addEventListener(Event.COMPLETE,function(e:Event):void{renderSelector(loader.content as MovieClip);});var context:LoaderContext=new LoaderContext();context.allowCodeImport=true;loader.loadBytes(new SelectorArt(),context);
  }
  private function renderSelector(selector:MovieClip):void {
   var scene:Sprite=new Sprite();canvas=scene;addChild(scene);scene.addChild(selector);selector.gotoAndStop(54);GameArtwork.stopTree(selector);
   var native:Object=selector;native.title_en.visible=native.title_fr.visible=native.premiumPopup.visible=native.newbiesPop.visible=native.noNewbiePop.visible=false;native.countText.text="1";native.mobilePageCount=2;native.mobileCurrentPage=1;
   var page:Sprite=new Sprite();native.holder.addChild(page);
   var entry:MobileEntryUI=new MobileEntryUI(position);scene.addChild(entry);
   for(var i:int=0;i<12;i++){
    var slot:DisplayObjectContainer=new SlotArt();GameArtwork.stopTree(slot);page.addChild(slot);
    for each(var flag:String in ["full","noPremiumBlock","premiumImage","newbieIndicator","nobut"])Object(slot)[flag].visible=false;Object(slot).serverName.text="";var name:TextField=Object(slot).serverName_iw;name.embedFonts=false;name.text="המפל של דולפיניו";Object(slot).numTxt.text=String(i+1);
   }
   var allSlots:Array=[];for(i=0;i<page.numChildren;i++)allSlots.push(page.getChildAt(i));
   native.setMobilePageCapacity=function(capacity:int):void {
    var pages:int=Math.max(1,Math.ceil(allSlots.length/capacity));native.mobilePageCount=pages;native.mobileCurrentPage=Math.min(native.mobileCurrentPage,pages);
    while(page.numChildren)page.removeChildAt(0);
    var start:int=(native.mobileCurrentPage-1)*capacity;
    for(var index:int=start;index<Math.min(allSlots.length,start+capacity);index++)page.addChild(allSlots[index]);
   };
   var maskedCounts:Array=[];
   for each(var frame:int in [1,28,40,46,54]){
    selector.gotoAndStop(frame);entry.update(selector,844,358);capture(scene,"selector-reveal-"+frame,844,358);
    maskedCounts.push(cardPixels(scene,native.holder));
   }
   if(maskedCounts[0]!=0||maskedCounts[4]<=0||maskedCounts[2]>=maskedCounts[4])throw new Error("selector_reveal_mask_missing "+maskedCounts);
   trace("SELECTOR_MASK_PASS card_pixels="+maskedCounts);
   entry.update(selector,844,358);
   setTimeout(function():void{
    entry.update(selector,844,358);capture(scene,"selector-wide",844,358);entry.update(selector,390,812);
    setTimeout(function():void{
     entry.update(selector,390,812);capture(scene,"selector-portrait",390,812);
     entry.update(selector,844,358);
     setTimeout(function():void{
      native.mobileCurrentPage=2;entry.update(selector,844,358);capture(scene,"selector-last-page",844,358);
      if(!native.prevBut.visible||!native.nextBut.visible)throw new Error("last_page_controls_hidden");
      allSlots.splice(1);native.mobilePageCount=1;native.mobileCurrentPage=1;entry.update(selector,844,358);capture(scene,"selector-single",844,358);
      if(native.prevBut.visible||native.nextBut.visible||native.countText.visible)throw new Error("single_page_controls_visible");entry.reset();removeChild(scene);
      trace("ENTRY_RENDER_PASS entry_actions_and_native_fields=true");NativeApplication.nativeApplication.exit(0);
     },100);
    },100);
   },100);
  }
  private function cardPixels(scene:DisplayObject,holder:DisplayObject):int {
   var page:DisplayObjectContainer=DisplayObjectContainer(holder).getChildAt(0) as DisplayObjectContainer;
   var marker:Shape=new Shape();marker.graphics.beginFill(0xFE00FD);marker.graphics.drawRect(0,0,50,50);marker.graphics.endFill();page.addChild(marker);position(marker,220,110,1,1);
   var shown:BitmapData=new BitmapData(844,358,true,0);shown.draw(scene);page.removeChild(marker);
   var count:int=0;for(var y:int=0;y<358;y++)for(var x:int=0;x<844;x++)if(shown.getPixel(x,y)==0xFE00FD)count++;
   shown.dispose();return count;
  }
  private function position(o:DisplayObject,x:Number,y:Number,sx:Number,sy:Number):void {
   var a:Point=o.parent.globalToLocal(canvas.localToGlobal(new Point(x,y))),b:Point=o.parent.globalToLocal(canvas.localToGlobal(new Point(x+sx,y))),c:Point=o.parent.globalToLocal(canvas.localToGlobal(new Point(x,y+sy)));o.transform.matrix=new Matrix(b.x-a.x,b.y-a.y,c.x-a.x,c.y-a.y,a.x,a.y);
  }
  private function capture(o:DisplayObject,name:String,w:int,h:int):void {
   var pixels:BitmapData=new BitmapData(w*2,h*2,false,0xAAD93D);pixels.draw(o,new Matrix(2,0,0,2));var target:File=File.applicationStorageDirectory.resolvePath("entry-"+name+".png");var out:FileStream=new FileStream();out.open(target,FileMode.WRITE);out.writeBytes(pixels.encode(pixels.rect,new PNGEncoderOptions()));out.close();pixels.dispose();trace("ENTRY_RENDER "+target.nativePath);
  }
 }
}
