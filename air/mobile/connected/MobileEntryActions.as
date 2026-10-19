package {
 import flash.display.*;import flash.events.*;import flash.geom.*;import flash.text.*;import flash.net.URLRequest;import flash.accessibility.AccessibilityProperties;
 import org.ekoloko.air.NativeServices;
 /** Mobile-only entry actions; leaf vectors and embedded glyphs are original art. */
 public final class MobileEntryActions extends Sprite {
  [Embed(source="../assets/account-deletion-leaf.swf",symbol="AccountDeletionLeaf")] private static var DeletionLeaf:Class;
  [Embed(source="../../../assets/Gan CLM Bold.ttf",fontName="EkolokoEntryGan",mimeType="application/x-font",embedAsCFF="false")] private static var NoticeFont:Class;
  public static var accountDeletionEnabled:Boolean=false;
  public static const DELETION_URL:String="https://play.ekoloko.org/ekoloko-web/accountDeletion.php";
  public static const REGISTER_NOTICE:String="ההרשמה אינה זמינה כרגע בנייד. כדי להירשם למשחק, יש לעבור למחשב.";
  private var owner:DisplayObjectContainer,leaf:SimpleButton,states:Array,access:AccessibilityProperties;
  private var resetting:Boolean=false,revision:uint=0;
  private var notice:Sprite,w:Number,h:Number,noticeKind:String="",noticeW:Number=-1,noticeH:Number=-1;
  public function MobileEntryActions(){mouseEnabled=false;name="mobileEntryActions";Font.registerFont(NoticeFont);}
  public function update(root:DisplayObjectContainer,width:Number,height:Number):void {
   if(resetting||!root)return;
   owner=root;w=width;h=height;
   var updateRevision:uint=revision,next:SimpleButton="leaf4" in root?Object(root).leaf4 as SimpleButton:null;
   if(next!=leaf){restoreLeaf();if(updateRevision!=revision)return;leaf=next;
    if(leaf){states=[leaf.upState,leaf.overState,leaf.downState,leaf.hitTestState];access=leaf.accessibilityProperties;
     var art:SimpleButton=new DeletionLeaf(),button:SimpleButton=leaf,token:uint=revision;
     button.upState=art.upState;if(token!=revision)return;
     button.overState=art.overState;if(token!=revision)return;
     button.downState=art.downState;if(token!=revision)return;
     button.accessibilityProperties=new AccessibilityProperties();button.accessibilityProperties.name="מחיקת חשבון";
    }
   }
   if(notice&&(noticeW!=w||noticeH!=h))renderNotice();
  }
  private function inside(target:DisplayObject,ancestor:DisplayObject):Boolean {
   if(!ancestor)return false;
   for(var current:DisplayObject=target;current;current=current.parent)if(current==ancestor)return true;
   return false;
  }
  public function handle(event:MouseEvent):Boolean {
   if(!owner)return false;
   var target:DisplayObject=event.target as DisplayObject,native:Object=owner;
   var register:DisplayObject=native.loginScreen&&"registerBut" in native.loginScreen?native.loginScreen.registerBut:null;
   if(inside(target,leaf)){
    event.stopImmediatePropagation();
    if(accountDeletionEnabled)NativeServices.navigate(new URLRequest(DELETION_URL),"_blank");
    else showNotice("deletion");
    return true;
   }
   if(inside(target,native.regBtnHolder)||inside(target,register)){
    event.stopImmediatePropagation();showNotice("register");return true;
   }
   return false;
  }
  private function showNotice(kind:String):void {noticeKind=kind;renderNotice();}
  private function renderNotice():void {
   closeNotice(false);noticeW=w;noticeH=h;notice=new Sprite();notice.name="mobileEntryNotice";addChild(notice);
   notice.graphics.beginFill(0,0.38);notice.graphics.drawRect(0,0,w,h);notice.graphics.endFill();
   var width:Number=Math.min(540,w-32),height:Number=Math.min(220,h-24),x:Number=(w-width)/2,y:Number=(h-height)/2;
   var background:Sprite=OriginalUI.panelBackground(width,height);background.x=x;background.y=y;notice.addChild(background);
   var lines:Array=noticeKind=="register"?["ההרשמה אינה זמינה כרגע בנייד.","כדי להירשם למשחק,","יש לעבור למחשב."]:["מחיקת חשבון","האפשרות אינה זמינה כרגע בנייד."];
   var label:TextField=new TextField();label.name="mobileEntryNoticeText";label.embedFonts=true;label.selectable=false;label.mouseEnabled=false;
   var format:TextFormat=new TextFormat("EkolokoEntryGan",Math.min(26,(width-40)/17),0x173D2A);format.align=TextFormatAlign.CENTER;format.leading=8;
   label.defaultTextFormat=format;var visual:Array=[];for each(var line:String in lines)visual.push(line.split("").reverse().join(""));label.text=visual.join("\n");label.setTextFormat(format);
   label.width=width-32;label.height=height-70;label.x=x+16;label.y=y+24;notice.addChild(label);
   notice.accessibilityProperties=new AccessibilityProperties();notice.accessibilityProperties.name=noticeKind=="register"?REGISTER_NOTICE:lines.join(" ");
   var close:Sprite=OriginalUI.closeButton(function():void{closeNotice();});close.x=x+(width-48)/2;close.y=y+height-56;notice.addChild(close);
   notice.addEventListener(MouseEvent.MOUSE_DOWN,block);notice.addEventListener(MouseEvent.CLICK,block);
  }
  private function block(e:MouseEvent):void{e.stopPropagation();}
  private function closeNotice(clear:Boolean=true):void {
   var previous:Sprite=notice;notice=null;if(clear)noticeKind="";
   if(previous&&previous.parent)previous.parent.removeChild(previous);
  }
  private function restoreLeaf():void {
   // State setters dispatch synchronous display-list events. Detach ownership
   // before restoring so a nested scene reset cannot clear these references.
   var previous:SimpleButton=leaf,saved:Array=states,savedAccess:AccessibilityProperties=access;
   leaf=null;states=null;access=null;
   if(previous&&saved){previous.upState=saved[0];previous.overState=saved[1];previous.downState=saved[2];previous.hitTestState=saved[3];previous.accessibilityProperties=savedAccess;}
  }
  public function reset():void {
   if(resetting)return;resetting=true;revision++;owner=null;
   try{closeNotice();restoreLeaf();}finally{resetting=false;}
  }
 }
}
