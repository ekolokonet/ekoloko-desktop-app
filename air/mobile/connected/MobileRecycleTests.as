package {
 import flash.display.*;import flash.events.*;import flash.system.*;import flash.geom.*;import flash.filesystem.*;import flash.desktop.NativeApplication;import flash.text.*;
 public final class MobileRecycleTests extends Sprite {
  [Embed(source="../../build/mobile-lab/assets/ui.swf",symbol="DaysPalyedRewardPane")] private var Panel:Class;
  [Embed(source="../../build/mobile-connected/recycle-timeline.swf",mimeType="application/octet-stream")] private var Art:Class;
  public function MobileRecycleTests(){
   loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR,function(e:UncaughtErrorEvent):void{e.preventDefault();trace("RECYCLE_FAIL "+e.error);NativeApplication.nativeApplication.exit(2);});
   var owner:Sprite=this;var loader:Loader=new Loader();loader.contentLoaderInfo.addEventListener(Event.COMPLETE,function(e:Event):void{
    var panel:DisplayObjectContainer=new Panel();addChild(panel);panel.addChild(loader);GameArtwork.stopTree(panel);
    var machine:DisplayObjectContainer=loader.content as DisplayObjectContainer;
    for each(var hidden:String in ["timerPopup","splashPopup","prizePopup","splash","arrow2"])machine.getChildByName(hidden).visible=false;
    machine.getChildByName("description").y=95;machine.getChildByName("timer").y=303;
    var title:TextField=machine.getChildByName("title") as TextField,subtitle:TextField=machine.getChildByName("subtitle") as TextField;
    title.text="מכונת המתנות";subtitle.text="מכניסים פריטים למחזור ומקבלים מתנה!";
    var description:DisplayObjectContainer=machine.getChildByName("description") as DisplayObjectContainer;
    for(var j:int=0;j<description.numChildren;j++){var label:TextField=description.getChildAt(j) as TextField;if(label){label.text="הכניסו למכונה פריטי מחזור מנייר";}}
    for each(var size:Array in [[932,430],[844,390],[375,812],[390,844],[1024,736]]){
     var portrait:Boolean=size[1]>size[0],safe:Rectangle=new Rectangle(portrait?12:24,8,size[0]-(portrait?24:48),size[1]-20);
     NativeRecycleLayout.fit(panel,safe,0,position);var initial:Matrix=panel.transform.matrix.clone();
     for each(var control:DisplayObject in [title,subtitle,description,machine.getChildByName("timer"),Object(panel).closeButton]){
      if(!safe.containsRect(control.getBounds(owner)))throw new Error("recycle_control_clipped "+control.name+" "+size+" "+control.getBounds(owner));
     }
     if(panel.scaleX!=panel.scaleY)throw new Error("machine_stretched");
     capture("recycle-"+size[0]+"x"+size[1],size[0],size[1]);
     description.y=-105;machine.getChildByName("timer").y=-105;
     NativeRecycleLayout.fit(panel,safe,0,position);
     if(initial.toString()!=panel.transform.matrix.toString())throw new Error("machine_resized_for_animated_contents");
     description.y=95;machine.getChildByName("timer").y=303;
     NativeRecycleLayout.fit(panel,safe,-1,position);
     if(Object(panel).closeButton.getBounds(owner).bottom>0)throw new Error("recycle_shutter_visible_when_closed");
    }
    trace("RECYCLE_PASS sizes=5 native_art=true instructions_and_handle_visible=true stable_animation=true");
    NativeApplication.nativeApplication.exit(0);
   });var context:LoaderContext=new LoaderContext();context.allowCodeImport=true;loader.loadBytes(new Art(),context);
  }
  private function position(o:DisplayObject,x:Number,y:Number,sx:Number,sy:Number):void{o.transform.matrix=new Matrix(sx,0,0,sy,x,y);}
  private function capture(name:String,w:int,h:int):void{var pixels:BitmapData=new BitmapData(w*2,h*2,false,0x286F38);pixels.draw(this,new Matrix(2,0,0,2));var out:FileStream=new FileStream();out.open(File.applicationStorageDirectory.resolvePath(name+".png"),FileMode.WRITE);out.writeBytes(pixels.encode(pixels.rect,new PNGEncoderOptions()));out.close();pixels.dispose();}
 }
}
