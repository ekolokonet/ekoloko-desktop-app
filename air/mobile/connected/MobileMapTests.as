package {
 import flash.display.*;import flash.events.*;import flash.system.*;import flash.desktop.NativeApplication;import flash.geom.*;import flash.filesystem.*;import flash.utils.*;
 import org.ekoloko.air.NativeServices;
 public final class MobileMapTests extends Sprite {
  private var shell:Loader=new Loader(),game:Loader=new Loader(),map:Loader=new Loader(),panel:DisplayObjectContainer;
  public function MobileMapTests(){
   NativeServices.initialize();loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR,failed);
   for each(var l:Loader in [shell,game,map])l.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR,failed);
   shell.contentLoaderInfo.addEventListener(Event.COMPLETE,function(e:Event):void{load(game,"main.swf",shell.contentLoaderInfo.applicationDomain);});
   game.contentLoaderInfo.addEventListener(Event.COMPLETE,function(e:Event):void{
    var type:Class=game.contentLoaderInfo.applicationDomain.getDefinition("MapPanelMC") as Class;panel=new type();addChild(panel);GameArtwork.stopTree(panel);
    load(map,"map/map.swf",game.contentLoaderInfo.applicationDomain);
   });
   map.contentLoaderInfo.addEventListener(Event.COMPLETE,function(e:Event):void{
    panel.addChild(map);GameArtwork.stopTree(map);
    var domain:ApplicationDomain=game.contentLoaderInfo.applicationDomain;domain.getDefinition("com.vtweens.text.LanugageControl").language="iw";domain.getDefinition("com.vtweens.text.TextFormats").init();
    var type:Class=domain.getDefinition("com.vtweens.shell.ServerConfig") as Class;var config:Object=new type();
    config.addEventListener(type.DATA_LOADED,function(e:Event):void{var texts:Object=domain.getDefinition("com.vtweens.text.TextResourceManager");texts.AddEventListener(texts.DATA_LOADED,function(e:Event):void{run();});texts.Load(config);});
   });
   load(shell,"shell.swf",ApplicationDomain.currentDomain);
  }
  private function load(loader:Loader,path:String,parent:ApplicationDomain):void{var c:LoaderContext=new LoaderContext(false,new ApplicationDomain(parent));c.allowCodeImport=true;loader.loadBytes(NativeServices.readAsset(path),c);}
  private function run():void{
   var root:DisplayObjectContainer=map.content as DisplayObjectContainer;
   for(var i:int=0;i<root.numChildren;i++){var o:DisplayObject=root.getChildAt(i);if(/^z\d+$/.test(o.name)||/Popup$/.test(o.name)||o.name=="backBut")o.visible=false;}
   var top:Object=root.getChildByName("topMap"),domain:ApplicationDomain=game.contentLoaderInfo.applicationDomain,texts:Object=domain.getDefinition("com.vtweens.text.TextResourceManager"),formats:Object=domain.getDefinition("com.vtweens.text.TextFormats");
   top.games.visible=top.stores.visible=false;
   for each(var section:String in ["z1s1","z1s2","z1s3","z1s4","z2s1","z2s2","z2s3","z2s4","z3s1"]){var region:Object=(top.sections?top.sections:top).getChildByName(section);region.alpha=.01;}
   top.title1.defaultTextFormat=formats.CenterRegular20;top.title1.text=texts.getString("ekoloko");top.title2.defaultTextFormat=formats.CenterBold20;top.title2.text=texts.getString("world_map_title");
   for each(var pair:Array in [["storesBut","map_button_stores"],["locBut","map_button_locs"],["gamesBut","map_button_games"]]){var control:Object=root.getChildByName(pair[0]);control.txt.defaultTextFormat=formats.CenterBold13;control.txt.text=texts.getString(pair[1]);}
   for each(var data:Object in texts.getZonesData().getValues()){var label:Object=top.getChildByName("z"+data[texts.ZONE_ID]+"txt");if(label){label.defaultTextFormat=formats.CenterBold16;label.text=data[texts.ZONE_NAME];}}
   var close:DisplayObject=Object(panel).close,clicks:int=0;
   close.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void{clicks++;});
   for each(var size:Array in [[932,430],[844,390],[375,812],[390,844],[1024,736]]){
    var portrait:Boolean=size[1]>size[0],safe:Rectangle=new Rectangle(portrait?12:24,8,size[0]-(portrait?24:48),size[1]-20);
    NativeMapLayout.fit(panel,safe,0,position);var stable:Matrix=panel.transform.matrix.clone(),b:Rectangle=NativeMapLayout.bounds();
    var visible:Rectangle=new Rectangle(panel.x+b.x*panel.scaleX,panel.y+b.y*panel.scaleY,b.width*panel.scaleX,b.height*panel.scaleY);
    if(!safe.containsRect(visible))throw new Error("map_outside_safe_area "+size);
    if(Math.abs(panel.scaleX-panel.scaleY)>.0001)throw new Error("map_stretched");
    if(size[0]==932&&visible.height<395)throw new Error("map_not_using_phone_height");
    for each(var button:DisplayObject in [close,root.getChildByName("storesBut"),root.getChildByName("locBut"),root.getChildByName("gamesBut")])if(!safe.containsRect(button.getBounds(this)))throw new Error("map_control_clipped "+button.name);
    var zone:DisplayObject=root.getChildByName("z1");zone.visible=true;zone.y-=150;
    NativeMapLayout.fit(panel,safe,0,position);if(panel.scaleX!=stable.a||panel.x!=stable.tx||panel.y!=stable.ty)throw new Error("map_jumps_for_region_or_tooltip");zone.y+=150;zone.visible=false;
    close.dispatchEvent(new MouseEvent(MouseEvent.CLICK));
    capture("map-"+size[0]+"x"+size[1],size[0],size[1]);
    var lastY:Number=panel.y;
    for each(var progress:Number in [-.25,-.5,-.75,-1]){NativeMapLayout.fit(panel,safe,progress,position);if(panel.y>=lastY||panel.scaleX!=stable.a)throw new Error("map_curtain_jumps");lastY=panel.y;}
    if(panel.y+b.bottom*panel.scaleY>0)throw new Error("map_handle_not_fully_closed");
    NativeMapLayout.fit(panel,safe,0,position);if(panel.y!=stable.ty)throw new Error("map_does_not_reopen");
   }
   if(clicks!=5||close.parent!=panel)throw new Error("native_map_close_changed");
   trace("MAP_PASS sizes=5 original_map_art=true stable_regions=true shutter=true close_callback=true");
   NativeApplication.nativeApplication.exit(0);
  }
  private function position(o:DisplayObject,x:Number,y:Number,sx:Number,sy:Number):void{o.transform.matrix=new Matrix(sx,0,0,sy,x,y);}
  private function capture(name:String,w:int,h:int):void{var pixels:BitmapData=new BitmapData(w*2,h*2,false,0x286F38);pixels.draw(this,new Matrix(2,0,0,2));var out:FileStream=new FileStream();out.open(File.applicationStorageDirectory.resolvePath(name+".png"),FileMode.WRITE);out.writeBytes(pixels.encode(pixels.rect,new PNGEncoderOptions()));out.close();pixels.dispose();}
  private function failed(e:UncaughtErrorEvent):void{e.preventDefault();trace("MAP_FAIL "+(e.error is Error?Error(e.error).getStackTrace():e.error));NativeApplication.nativeApplication.exit(2);}
 }
}
