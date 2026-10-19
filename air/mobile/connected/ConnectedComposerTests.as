package {
 import flash.display.*;import flash.events.*;import flash.geom.*;import flash.text.*;import flash.utils.*;import flash.filesystem.*;import flash.desktop.NativeApplication;
 [SWF(width="960",height="600",frameRate="24")]
 public final class ConnectedComposerTests extends Sprite {
  private var canvas:Sprite;
  private var background:Sprite; private var physicalRect:Rectangle;
  private var input:StageText, index:int=0,blank:BitmapData;
  private var cases:Array=[{w:844,h:358,k:0},{w:390,h:812,k:0},{w:390,h:812,k:320},{w:844,h:358,k:170}];
  public function ConnectedComposerTests(){
   canvas=this;stage.scaleMode=StageScaleMode.SHOW_ALL;stage.align="";
   loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR,function(e:UncaughtErrorEvent):void{e.preventDefault();trace("COMPOSER_FAIL "+e.error);NativeApplication.nativeApplication.exit(2);});
   input=new StageText();input.fontFamily="Arial";input.fontWeight="bold";input.fontSize=18;input.color=0x203C2B;input.locale="he-IL";input.textAlign="right";input.returnKeyLabel="done";
   input.stage=stage;run();
  }
  private function run():void{
   var c:Object=cases[index];stage.nativeWindow.width=c.w;stage.nativeWindow.height=c.h+32;
   var keyboard:Rectangle=c.k?new Rectangle(0,c.h-c.k,c.w,c.k):null;
   var box:Object=MobileLayout.calculate(c.w,c.h,{left:12,right:12,top:8,bottom:12},keyboard,true);
   if(box.viewport.bottom!=(c.k?c.h-c.k:c.h))throw new Error("room_footer_gap");
   var outer:Number=Math.min(c.w/960,c.h/600);canvas.scaleX=canvas.scaleY=1/outer;canvas.x=(960-c.w/outer)/2;canvas.y=(600-c.h/outer)/2;
   if(background)removeChild(background);
   background=OriginalUI.chatBackground(box.composer.width-50,box.composer.height);background.x=box.composer.x+50;background.y=box.composer.y;addChild(background);
   physicalRect=NativeChatGeometry.inputBounds(background,this,box.composer.right-41);
   input.text="";input.fontSize=18;input.viewPort=NativeChatGeometry.stageBounds(this,physicalRect);input.visible=true;
   if(!box.composer.containsRect(physicalRect))throw new Error("native_input_outside_composer");
   setTimeout(function():void{
    blank=new BitmapData(input.viewPort.width,input.viewPort.height,true,0);input.drawViewPortToBitmapData(blank);
    input.text="שלום אקולוקו 123";
    setTimeout(function():void{
     var ink:BitmapData=new BitmapData(input.viewPort.width,input.viewPort.height,true,0);input.drawViewPortToBitmapData(ink);
     var diff:Object=ink.compare(blank);if(!(diff is BitmapData))throw new Error("native_text_invisible case="+index);var inkBounds:Rectangle=BitmapData(diff).getColorBoundsRect(0x00ffffff,0,false);trace("COMPOSER_INK_BOUNDS case="+index+" bounds="+inkBounds);if(inkBounds.height<12||!new Rectangle(0,0,physicalRect.width,physicalRect.height).containsRect(inkBounds))throw new Error("native_text_glyphs_clipped case="+index);BitmapData(diff).dispose();blank.dispose();
     var pixels:BitmapData=new BitmapData(c.w,c.h,false,0x286F38);pixels.draw(canvas,new Matrix());pixels.copyPixels(ink,new Rectangle(0,0,physicalRect.width,physicalRect.height),physicalRect.topLeft,null,null,true);ink.dispose();
     var out:FileStream=new FileStream(),file:File=File.applicationStorageDirectory.resolvePath("composer-"+index+".png");out.open(file,FileMode.WRITE);out.writeBytes(pixels.encode(pixels.rect,new PNGEncoderOptions()));out.close();pixels.dispose();
     trace("COMPOSER_INK_PASS case="+index+" rect="+input.viewPort);index++;if(index<cases.length)run();else{input.dispose();trace("COMPOSER_PASS native_hebrew_ink=4 no_network=true");NativeApplication.nativeApplication.exit(0);}
    },300);
   },300);
  }
 }
}
