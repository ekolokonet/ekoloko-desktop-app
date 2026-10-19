package {
 import flash.desktop.NativeApplication;
 import flash.display.*;
 import flash.events.*;
 import flash.system.*;
 import flash.text.*;
 import flash.utils.*;
 import flash.geom.*;import flash.filesystem.*;
 import org.ekoloko.air.NativeServices;
 /** Actual shipped ChatInput, isolated event sink. Never creates an SFS session. */
 public final class ConnectedChatTests extends Sprite {
  private var shell:Loader=new Loader(),game:Loader=new Loader(),domain:ApplicationDomain,config:Object;
  private var chat:DisplayObjectContainer,field:TextField,sent:Array=[],popups:int=0,checks:int=0;
  private var phase:String="shell";
  private var delivery:NativeChatDelivery;
  public function ConnectedChatTests(){
   loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR,failed);
   shell.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR,failed);
   game.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR,failed);
   NativeServices.initialize();
   shell.contentLoaderInfo.addEventListener(Event.COMPLETE,function(e:Event):void{
    phase="main";trace("CHAT_PROBE_PHASE "+phase);
    var context:LoaderContext=new LoaderContext(false,new ApplicationDomain(shell.contentLoaderInfo.applicationDomain));context.allowCodeImport=true;game.loadBytes(NativeServices.readAsset("main.swf"),context);
   });
   game.contentLoaderInfo.addEventListener(Event.COMPLETE,function(e:Event):void{
    phase="config";trace("CHAT_PROBE_PHASE "+phase);
    domain=game.contentLoaderInfo.applicationDomain;domain.getDefinition("com.vtweens.text.LanugageControl").language="iw";domain.getDefinition("com.vtweens.text.TextFormats").init();
    var type:Class=domain.getDefinition("com.vtweens.shell.ServerConfig") as Class;config=new type();
    config.addEventListener(type.DATA_LOADED,function(e:Event):void{
     phase="texts";trace("CHAT_PROBE_PHASE "+phase);
     var texts:Object=domain.getDefinition("com.vtweens.text.TextResourceManager");texts.AddEventListener(texts.DATA_LOADED,function(e:Event):void{run();});texts.Load(config);
    });
   });
   var context:LoaderContext=new LoaderContext(false,new ApplicationDomain(ApplicationDomain.currentDomain));context.allowCodeImport=true;shell.loadBytes(NativeServices.readAsset("shell.swf"),context);
   setTimeout(function():void{trace("CONNECTED_CHAT_FAIL timeout phase="+phase);NativeApplication.nativeApplication.exit(3);},80000);
  }
  private function run():void {
   phase="component";trace("CHAT_PROBE_PHASE "+phase);
   domain.getDefinition("com.vtweens.util.MainGetter").MainCaller={popup:function(...args):void{popups++;}};
   var type:Class=domain.getDefinition("com.vtweens.components.chat.ChatInput") as Class;chat=new type();addChild(chat);
   for(var i:int=0;i<chat.numChildren;i++)if(chat.getChildAt(i) is TextField&&TextField(chat.getChildAt(i)).type==TextFieldType.INPUT)field=chat.getChildAt(i) as TextField;
   check(field!=null,"original_input_found");
   Object(chat).hideInstructions();field.alpha=1;
   var send:DisplayObject=findNamed(chat,"submitBut"),originalParent:DisplayObjectContainer=field.parent;
   var presentation:NativeChatPresentation=new NativeChatPresentation(chat,field,send.parent.getChildAt(0),this,position);
   var coordinateSpace:DisplayObject=this;
   var widths:Array=[260,343,796,1640],caseIndex:int=0;
   var nextCase:Function=function():void {
    if(caseIndex==widths.length){presentation.dispose();check(field.parent==originalParent,"native_input_parent_restored");check(chat.mask==null,"native_chat_mask_restored");runNativePreview();runInventorySwipe();runSecurityPopup();runProtocol();return;}
    var width:Number=widths[caseIndex++];
    chat.transform.matrix=new Matrix(1.37,0,0,1.18,17.3,-9.1);
    var outer:Rectangle=new Rectangle(12,10,width,48),rect:Rectangle=presentation.refresh(outer,outer.right-41);field.text="";
    setTimeout(function():void {
    var buttonBounds:Rectangle=send.getBounds(send),buttonScale:Number=Math.min(36/buttonBounds.width,36/buttonBounds.height,2.4);
    position(send,outer.right-41+(36-buttonBounds.width*buttonScale)/2-buttonBounds.x*buttonScale,outer.y+6+(36-buttonBounds.height*buttonScale)/2-buttonBounds.y*buttonScale,buttonScale,buttonScale);
    for each(var dx:Number in [2,8,20,44]){
     for each(var probe:Point in [new Point(outer.right+dx,outer.y+24),new Point(outer.left-dx,outer.y+24),new Point(outer.x+width/2,outer.top-dx),new Point(outer.x+width/2,outer.bottom+dx)]){
      var hit:Array=chat.getObjectsUnderPoint(coordinateSpace.localToGlobal(probe));
      check(hit.length==0,"chat_steals_adjacent_button width="+width+" point="+probe+" count="+hit.length);
     }
    }
    trace("REAL_CHAT_GEOMETRY width="+width+" input="+rect+" background="+chat.getChildAt(0).getBounds(coordinateSpace)+" field="+field.getBounds(coordinateSpace));
    check(Math.abs(chat.getChildAt(0).getBounds(coordinateSpace).width-width)<.2,"actual_background_width");
    check(field.defaultTextFormat.align==TextFormatAlign.RIGHT,"hebrew_paragraph_aligned_right");
    field.text="שלום";field.dispatchEvent(new Event(Event.CHANGE,true));
    if(width==260){
     var directionPixels:BitmapData=new BitmapData(800,220,false,0xffffff);directionPixels.draw(field,new Matrix(4,0,0,4,0,0));directionPixels.draw(new MobileLabel("שלום",185,16,0x000066,"right"),new Matrix(4,0,0,4,0,120));
     var diagnostic:FileStream=new FileStream();diagnostic.open(File.applicationStorageDirectory.resolvePath("rtl-direction.png"),FileMode.WRITE);diagnostic.writeBytes(directionPixels.encode(directionPixels.rect,new PNGEncoderOptions()));diagnostic.close();directionPixels.dispose();
    }
    // Flash reports logical character bounds even when its bidi renderer paints
    // Hebrew in visual RTL order. The saved native/FTE comparison covers that.
    check(field.text.replace(/[\u200e\u200f]/g,"")=="שלום","hebrew_logical_order_preserved");
    field.text="test";field.dispatchEvent(new Event(Event.CHANGE,true));
    check(field.text.replace(/[\u200e\u200f]/g,"")=="test","latin_logical_order_preserved");
    field.text="שלום test 123";field.dispatchEvent(new Event(Event.CHANGE,true));
    check(field.text.replace(/[\u200e\u200f]/g,"")=="שלום test 123","mixed_draft_logical_order_preserved");
    field.text="";
    var blank:BitmapData=new BitmapData(rect.width,rect.height,true,0);blank.draw(field);
    field.text="שלום אקולוקו 123";field.dispatchEvent(new Event(Event.CHANGE,true));
    var ink:BitmapData=new BitmapData(rect.width,rect.height,true,0);ink.draw(field);var diff:Object=ink.compare(blank);
    check(diff is BitmapData,"native_desktop_field_has_hebrew_ink width="+width);if(diff is BitmapData)BitmapData(diff).dispose();blank.dispose();ink.dispose();
    check(field.getLineMetrics(0).height<=rect.height,"native_text_line_fits_height width="+width);
    // Snapshot the whole real ChatInput, not the TextField in isolation.
    var originalAlpha:Number=send.alpha;send.alpha=0;field.alpha=0;
    var clean:BitmapData=new BitmapData(width+30,80,true,0);clean.draw(coordinateSpace);
    field.alpha=1;field.text=new Array(12).join("בדיקה ");field.dispatchEvent(new Event(Event.CHANGE,true));field.setSelection(field.length,field.length);
    var caret:int=field.caretIndex;for(var repeat:int=0;repeat<5;repeat++)presentation.refresh(outer,outer.right-41);
    check(field.caretIndex==caret,"reflow_preserves_caret");
    setTimeout(function():void {
    var typed:BitmapData=new BitmapData(width+30,80,true,0);typed.draw(coordinateSpace);
    var changed:BitmapData=typed.compare(clean) as BitmapData;check(changed!=null,"real_chat_long_text_visible");
    var textBounds:Rectangle=changed.getColorBoundsRect(0x00ffffff,0,false);
    check(rect.containsRect(textBounds),"real_chat_text_outside_viewport width="+width);
    for(var y:int=textBounds.top;y<textBounds.bottom;y++)for(var x:int=textBounds.left;x<textBounds.right;x++){
     if(changed.getPixel(x,y)==0)continue;var rgb:uint=clean.getPixel(x,y);
     if(((rgb>>16)&255)<215||((rgb>>8)&255)<215||(rgb&255)<215)throw new Error("real_chat_text_outside_white width="+width);
    }
    check(outer.right-rect.right<65,"send_gap_grows_with_width");
    var out:FileStream=new FileStream();out.open(File.applicationStorageDirectory.resolvePath("real-chat-"+width+".png"),FileMode.WRITE);out.writeBytes(typed.encode(typed.rect,new PNGEncoderOptions()));out.close();
    changed.dispose();clean.dispose();typed.dispose();send.alpha=originalAlpha;
    var sendBounds:Rectangle=send.getBounds(send),scale:Number=Math.min(36/sendBounds.width,36/sendBounds.height,2.4);
    position(send,outer.right-41+(36-sendBounds.width*scale)/2-sendBounds.x*scale,outer.y+6+(36-sendBounds.height*scale)/2-sendBounds.y*scale,scale,scale);
    var preview:BitmapData=new BitmapData(width+30,80,true,0);preview.draw(coordinateSpace);
    out.open(File.applicationStorageDirectory.resolvePath("real-chat-control-"+width+".png"),FileMode.WRITE);out.writeBytes(preview.encode(preview.rect,new PNGEncoderOptions()));out.close();preview.dispose();nextCase();
    },60);
    },60);
   };nextCase();
  }
  private function runNativePreview():void {
   var type:Class=domain.getDefinition("com.vtweens.components.chat.ChatInput") as Class;
   var owner:DisplayObjectContainer=new type();addChild(owner);
   var input:TextField;
   for(var i:int=0;i<owner.numChildren;i++)if(owner.getChildAt(i) is TextField&&TextField(owner.getChildAt(i)).type==TextFieldType.INPUT)input=owner.getChildAt(i) as TextField;
   var button:DisplayObject=findNamed(owner,"submitBut"),opens:int=0;
   owner.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void{opens++;},true);
   var p:NativeChatPresentation=new NativeChatPresentation(owner,input,button.parent.getChildAt(0),this,position,true);
   for each(var width:Number in [260,343,796,1640]){
    var outer:Rectangle=new Rectangle(12,10,width,46),r:Rectangle=p.refresh(outer,outer.right-41);
    var hit:Sprite=owner.getChildByName("mobileChatOpenTarget") as Sprite;
    var preview:TextField=findNamed(owner,"mobileChatDraftPreview") as TextField;
    check(hit&&hit.mouseEnabled,"native_reopen_has_independent_hit_target");
    check(hit.hitTestPoint(r.x+r.width/2,r.y+r.height/2,true),"white_opening_receives_reopen_tap");
    check(!hit.hitTestPoint(outer.right-20,outer.y+23,true),"reopen_target_excludes_send_button");
    check(!hit.hitTestPoint(outer.left-3,outer.y+23,true),"reopen_target_excludes_adjacent_buttons");
    p.showDraft("טיוטה נשמרת 123",false);
    check(preview.type==TextFieldType.DYNAMIC&&!preview.mouseEnabled&&!input.mouseEnabled&&input.alpha==0,"single_editable_native_surface");
    check(preview.visible&&preview.text=="טיוטה נשמרת 123","closed_draft_is_rendered_independently");
    var pixels:BitmapData=new BitmapData(r.width,r.height,true,0);pixels.draw(preview);
    check(!pixels.getColorBoundsRect(0xff000000,0,false).isEmpty(),"closed_native_preview_has_ink");pixels.dispose();
    var before:int=opens;
    for(var cycle:int=0;cycle<4;cycle++){
     hit.dispatchEvent(new MouseEvent(MouseEvent.CLICK,true));p.showDraft("טיוטה נשמרת 123",true);
     check(!preview.visible,"native_preview_hides_while_editing");
     p.showDraft("טיוטה נשמרת 123",false);check(preview.visible&&preview.text.length>0,"repeated_close_restores_draft");
    }
    check(opens==before+4,"reopen_clicks_reach_chat_handler_each_cycle");
    p.showDraft("",false);check(preview.visible&&preview.text.length>0,"empty_bar_restores_original_instruction");
   }
   p.dispose();check(input.alpha==1&&input.mouseEnabled,"native_preview_restores_original_input");removeChild(owner);
  }
  private function runInventorySwipe():void {
   var owner:Sprite=new Sprite();owner.x=30;owner.y=20;addChild(owner);
   var type:Class=domain.getDefinition("fl.containers.ScrollPane") as Class;
   var pane:Object=new type();owner.addChild(pane as DisplayObject);
   var items:Sprite=new Sprite();items.graphics.beginFill(0x77bb55);items.graphics.drawRect(0,0,130,1200);items.graphics.endFill();
   pane.source=items;pane.setSize(210,160);pane.drawNow();
   check(pane.maxVerticalScrollPosition>800,"real_inventory_pane_overflows");
   var swipe:NativeInventorySwipe=new NativeInventorySwipe(owner),clicks:int=0;
   var pad:Sprite=DisplayObjectContainer(pane).getChildByName("mobileInventoryScrollSurface") as Sprite;
   check(pad!=null&&pad.hitTestPoint(owner.x+160,owner.y+70,true),"empty_inventory_space_receives_input");
   var wheelStart:Number=pane.verticalScrollPosition;
   pad.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_WHEEL,true,false,160,70,null,false,false,false,false,-3));
   check(pane.verticalScrollPosition==wheelStart+3*pane.verticalLineScrollSize,"wheel_on_empty_space_uses_native_direction_once");
   pane.verticalScrollPosition=0;
   items.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void{clicks++;});
   var start:Point=items.localToGlobal(new Point(60,110));
   items.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_DOWN,true,false,60,110));
   stage.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_MOVE,true,false,start.x,start.y-70));
   stage.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_UP,true,false,start.x,start.y-70));
   check(pane.verticalScrollPosition>=69,"real_inventory_swipes_up");
   items.dispatchEvent(new MouseEvent(MouseEvent.CLICK,true));check(clicks==0,"swipe_does_not_select_item");
   items.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_DOWN,true,false,60,110));
   stage.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_UP,true));items.dispatchEvent(new MouseEvent(MouseEvent.CLICK,true));
   check(clicks==1,"ordinary_item_tap_preserved");
   var nativeBar:DisplayObjectContainer=pane.verticalScrollBar as DisplayObjectContainer;
   var nativeStart:Number=pane.verticalScrollPosition,receivedMoves:int=0;
   var receiveMove:Function=function(e:MouseEvent):void{receivedMoves++;};stage.addEventListener(MouseEvent.MOUSE_MOVE,receiveMove);
   start=nativeBar.localToGlobal(new Point(4,40));nativeBar.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_DOWN,true,false,4,40));
   stage.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_MOVE,true,false,start.x,start.y-40));stage.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_UP,true,false,start.x,start.y-40));
   check(pane.verticalScrollPosition==nativeStart&&receivedMoves==1,"mouse_scrollbar_does_not_compete_with_content_drag");stage.removeEventListener(MouseEvent.MOUSE_MOVE,receiveMove);
   start=pad.localToGlobal(new Point(160,100));pad.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_DOWN,true,false,160,100));
   stage.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_MOVE,true,false,start.x,start.y-30));stage.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_UP,true,false,start.x,start.y-30));
   check(pane.verticalScrollPosition>=nativeStart+29,"empty_space_drag_scrolls_without_an_item");
   var before:Number=pane.verticalScrollPosition;start=items.localToGlobal(new Point(60,110));
   items.dispatchEvent(new TouchEvent(TouchEvent.TOUCH_BEGIN,true,false,23,true,60,110));
   stage.dispatchEvent(new TouchEvent(TouchEvent.TOUCH_MOVE,true,false,23,true,start.x,start.y+45));
   stage.dispatchEvent(new TouchEvent(TouchEvent.TOUCH_END,true,false,23,true,start.x,start.y+45));
   check(pane.verticalScrollPosition<before-40,"real_inventory_touch_swipes_down");
   check(owner.x==30&&owner.y==20,"inventory_swipe_leaves_card_fixed");
   // Touching the actual native bar must not run content-drag semantics.
   var bar:DisplayObjectContainer=pane.verticalScrollBar as DisplayObjectContainer;
   var thumb:DisplayObject=bar.getChildAt(bar.numChildren-1),barStart:Number=pane.verticalScrollPosition;
   start=thumb.localToGlobal(new Point(4,4));
   thumb.dispatchEvent(new TouchEvent(TouchEvent.TOUCH_BEGIN,true,false,24,true,4,4));
   stage.dispatchEvent(new TouchEvent(TouchEvent.TOUCH_MOVE,true,false,24,true,start.x,start.y-60));
   stage.dispatchEvent(new TouchEvent(TouchEvent.TOUCH_END,true,false,24,true,start.x,start.y-60));
   check(pane.verticalScrollPosition==barStart,"touch_scrollbar_is_not_inverted_by_content_swipe");
   var other:Sprite=new Sprite(),otherClicks:int=0;owner.addChild(other);other.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void{otherClicks++;});
   other.dispatchEvent(new MouseEvent(MouseEvent.CLICK,true));check(otherClicks==1,"swipe_does_not_swallow_unrelated_control");
   swipe.dispose();removeChild(owner);
   check(pad.parent==null,"inventory_hit_surface_removed_on_dispose");
  }
  private function runSecurityPopup():void {
   var getter:Object=domain.getDefinition("com.vtweens.util.MainGetter"),previous:Object=getter.MainCaller;
   var callbacks:int=0,generated:int=0;
   getter.MainCaller={SecurityCodeAtInitState:true,SecurityCodeEnabled:false,resetSecurityForm:function(...args):void{},generateSecurityCode:function():void{generated++;}};
   var type:Class=domain.getDefinition("com.vtweens.dataobjects.security.code.SecurityCodePopup") as Class;
   var popup:DisplayObjectContainer=new type();addChild(popup);Object(popup).checkCode(function():void{callbacks++;});
   var dialog:Object=popup.getChildAt(0),originalMessage:String=dialog.message.text;
   check(originalMessage.length>10,"real_unsecured_vault_message_loaded");
   chat.visible=false;
   for each(var size:Array in [[932,430],[844,358],[375,812],[390,844],[1024,736]]){
    var area:Rectangle=new Rectangle(24,16,size[0]-48,size[1]-32);
    check(NativeSecurityPopupLayout.fit(popup,area,position),"vault_modal_fitted");
    area.inflate(.2,.2);
    for each(var name:String in ["title","message","close","okBut","closeText","okButText","linkToForm"]){
     check(area.containsRect(DisplayObject(dialog[name]).getBounds(this)),"vault_modal_content_inside_screen "+name+" "+size);
    }
    check(dialog.message.text==originalMessage,"vault_message_preserved");
    check(TextField(dialog.message).maxScrollV==1,"vault_message_not_internally_clipped");
    var pixels:BitmapData=new BitmapData(size[0]*2,size[1]*2,false,0x286F38);pixels.draw(this,new Matrix(2,0,0,2));
    var stream:FileStream=new FileStream();stream.open(File.applicationStorageDirectory.resolvePath("vault-"+size[0]+"x"+size[1]+".png"),FileMode.WRITE);stream.writeBytes(pixels.encode(pixels.rect,new PNGEncoderOptions()));stream.close();pixels.dispose();
   }
   dialog.close.dispatchEvent(new MouseEvent(MouseEvent.CLICK,true));
   check(callbacks==1&&generated==0&&popup.numChildren==0,"native_vault_continue_callback_preserved");
   removeChild(popup);chat.visible=true;getter.MainCaller=previous;
  }
  private function runProtocol():void {
   delivery=new NativeChatDelivery(chat,field,function():void{},function():void{throw new Error("unexpected_delivery_timeout");});
   chat.addEventListener("send_message",function(e:Event):void{sent.push(Object(e).getMessage());});
   field.text="שלום?";field.dispatchEvent(new Event(Event.CHANGE,true));enter();
   check(sent.length==1&&sent[0]=="שלום?","rtl_logical_payload");check(field.text.replace(/[\u200e\u200f]/g,"")=="שלום?","dispatch_retains_draft_until_bubble");
   NativeChatDelivery.syncInput(field,"שלום?");
   delivery.confirmBubble("שלום?");check(field.text=="","displayed_clears");
   field.text="עוד הודעה";enter();check(sent.length==1&&field.text!="","original_cooldown_retains_draft");
   setTimeout(function():void{
    field.text=new Array(46).join("א");field.dispatchEvent(new Event(Event.CHANGE,true));enter();
    check(sent.length==2&&String(sent[1]).length==39,"original_max_length");
    delivery.confirmBubble(String(sent[1]));check(field.text=="","truncated_displayed_clears");
    setTimeout(function():void{
     field.text="   ";enter();check(sent.length==2,"blank_not_sent");
     field.text="😀";enter();check(sent.length==2&&popups==1,"original_restriction_popup");
     check(field.text=="😀","rejected_message_keeps_draft");
     delivery.dispose();trace("CONNECTED_CHAT_PASS checks="+checks+" component=original networkChat=false");NativeServices.stopAssets();NativeApplication.nativeApplication.exit(0);
    },1600);
   },1600);
  }
  private function enter():void{delivery.submit(function():void{field.dispatchEvent(new KeyboardEvent(KeyboardEvent.KEY_UP,true,false,13,13));});}
  private function findNamed(root:DisplayObjectContainer,name:String):DisplayObject{var found:DisplayObject=root.getChildByName(name);if(found)return found;for(var i:int=0;i<root.numChildren;i++)if(root.getChildAt(i) is DisplayObjectContainer){found=findNamed(root.getChildAt(i) as DisplayObjectContainer,name);if(found)return found;}return null;}
  private function position(o:DisplayObject,x:Number,y:Number,sx:Number,sy:Number):void{var a:Point=o.parent.globalToLocal(localToGlobal(new Point(x,y))),b:Point=o.parent.globalToLocal(localToGlobal(new Point(x+sx*1024,y))),c:Point=o.parent.globalToLocal(localToGlobal(new Point(x,y+sy*1024)));o.transform.matrix=new Matrix((b.x-a.x)/1024,(b.y-a.y)/1024,(c.x-a.x)/1024,(c.y-a.y)/1024,a.x,a.y);}
  private function check(value:Boolean,label:String):void{if(!value)throw new Error(label);checks++;}
  private function failed(e:UncaughtErrorEvent):void{e.preventDefault();trace("CONNECTED_CHAT_FAIL phase="+phase+" checks="+checks+" "+(e.error is Error?Error(e.error).getStackTrace():e.error));NativeApplication.nativeApplication.exit(2);}
 }
}
