package {
 import flash.display.*;import flash.events.*;import flash.system.*;import flash.desktop.NativeApplication;
 import org.ekoloko.air.NativeServices;import flash.utils.setTimeout;
 /** Runs the shipped cleanup utility against re-entrant display-list removal. */
 public final class NativeCleanupTests extends Sprite {
  private var shell:Loader=new Loader(),game:Loader=new Loader();
  public function NativeCleanupTests(){
   loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR,failed);
   shell.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR,failed);
   game.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR,failed);
   NativeServices.initialize();
   shell.contentLoaderInfo.addEventListener(Event.COMPLETE,function(e:Event):void{
    var context:LoaderContext=new LoaderContext(false,new ApplicationDomain(shell.contentLoaderInfo.applicationDomain));context.allowCodeImport=true;game.loadBytes(NativeServices.readAsset("main.swf"),context);
   });
   game.contentLoaderInfo.addEventListener(Event.COMPLETE,function(e:Event):void{run();});
   var context:LoaderContext=new LoaderContext(false,new ApplicationDomain(ApplicationDomain.currentDomain));context.allowCodeImport=true;shell.loadBytes(NativeServices.readAsset("shell.swf"),context);
  }
  private function run():void {
   var cleanup:Object=game.contentLoaderInfo.applicationDomain.getDefinition("com.vtweens.util.DisplayObjectContainerUtils");
   for(var mode:int=0;mode<3;mode++)scenario(cleanup,mode);
   var root:MovieClip=new MovieClip();root.addChild(new MovieClip());cleanup.stopAndRemoveHierarchy(root);cleanup.stopAndRemoveHierarchy(root);cleanup.stopAndRemoveHierarchy(null);
   if(root.numChildren!=0)throw new Error("normal_cleanup");
   trace("NATIVE_CLEANUP_PASS checks=6 actual_packed_main=true networkChat=false");
   var ops:Object=game.contentLoaderInfo.applicationDomain.getDefinition("com.vtweens.util.menu.MenuDisplayOps");
   var pane:Sprite=new Sprite();pane.graphics.beginFill(0xabcdef);pane.graphics.drawRect(0,0,400,300);pane.graphics.endFill();addChild(pane);
   ops.HideMenu(pane);var start:Number=ops.mobileMenuOffset(pane);
   setTimeout(function():void{
    pane.y=0;var offset:Number=ops.mobileMenuOffset(pane);if(offset==start||!isFinite(offset))throw new Error("native_motion_overwritten");
    setTimeout(function():void{if(pane.visible||pane.parent)throw new Error("native_hide_lifecycle");trace("NATIVE_MOTION_PASS countertransform_independent=true hide_callback=true");checkMotion(ops);},800);
   },250);
  }
  private function checkMotion(ops:Object):void {
   var owner:Sprite=this;
   game.contentLoaderInfo.applicationDomain.getDefinition("com.vtweens.util.MainGetter").MainCaller={getUILayer:function():Object{return {placeMenu:function(p:Sprite):void{owner.addChild(p);}};}};
   var panel:Sprite=new Sprite();panel.graphics.beginFill(0xabcdef);panel.graphics.drawRect(0,0,400,300);panel.graphics.endFill();
   ops.ShowMenu(panel);var last:Number=-1,samples:int=0,closing:Boolean=false;
   var sample:Function=function():void {
    if(closing&&!panel.parent){if(panel.visible||last>-.8)throw new Error("reversed_curtain_hide_callback");trace("NATIVE_CURTAIN_PASS samples="+samples+" both_directions=true reversal_continuous=true");checkSelector();return;}
    // Native counter-transforms must not feed back into normalized progress.
    panel.y=(samples%2)*43;panel.scaleX=panel.scaleY=samples%2?1.2:.8;
    var value:Number=ops.mobileMenuOffset(panel);
    if(value < -1.0001||value>.0001||(closing?value>last+.0001:value<last-.0001))throw new Error("curtain_motion_reversed_or_overshot sample="+samples+" previous="+last+" current="+value);
    last=value;samples++;
    if(!closing&&samples==8){ops.HideMenu(panel);last=ops.mobileMenuOffset(panel);if(Math.abs(last-value)>.015)throw new Error("curtain_reversal_jumped");closing=true;}
    if(samples>=48)throw new Error("reversed_curtain_hide_timeout");
    setTimeout(sample,30);
   };sample();
  }
  private function checkSelector():void {
   var selector:Loader=new Loader();selector.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR,failed);
   selector.contentLoaderInfo.addEventListener(Event.COMPLETE,function(e:Event):void{var type:Class=selector.contentLoaderInfo.applicationDomain.getDefinition("com.vtweens.components.website.server_selector.ServerSelector") as Class;
    var native:Object=selector.content;if(!("mobilePageCount" in native)||native.mobilePageCount!=0||native.mobileCurrentPage!=1)throw new Error("native_selector_page_getters");
    trace("NATIVE_SELECTOR_PASS actual_packed_getters=true");NativeApplication.nativeApplication.exit(0);
   });var context:LoaderContext=new LoaderContext(false,new ApplicationDomain(shell.contentLoaderInfo.applicationDomain));context.allowCodeImport=true;selector.loadBytes(NativeServices.readAsset("website/common/server_selector/serverSelector.swf"),context);
  }
  private function scenario(cleanup:Object,mode:int):void {
   var root:Sprite=new Sprite(),branch:Sprite=new Sprite(),leaf:Sprite=new Sprite(),sibling:Sprite=new Sprite(),outside:Sprite=new Sprite(),once:Boolean=false;
   root.addChild(branch);if(mode==1)root.addChild(sibling);branch.addChild(leaf);
   leaf.addEventListener(Event.REMOVED,function(e:Event):void{
    if(once)return;once=true;
    if(mode==0&&branch.parent==root)root.removeChild(branch);
    if(mode==1&&sibling.parent==root)root.removeChild(sibling);
    if(mode==2)outside.addChild(branch);
   });
   cleanup.stopAndRemoveHierarchy(root);
   if(root.numChildren!=0||mode==2&&branch.parent!=outside)throw new Error("reentrant_mode_"+mode);
  }
  private function failed(e:UncaughtErrorEvent):void {e.preventDefault();trace("NATIVE_CLEANUP_FAIL "+(e.error is Error?Error(e.error).getStackTrace():e.error));NativeApplication.nativeApplication.exit(2);}
 }
}
