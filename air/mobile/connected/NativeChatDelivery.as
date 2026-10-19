package {
 import flash.display.DisplayObjectContainer;import flash.events.*;import flash.text.TextField;import flash.utils.Timer;
 /** Retain the draft until the original client actually displays our message.
  * No network calls, synthetic bubbles, automatic retries or chat-body logging. */
 public final class NativeChatDelivery {
  private var chat:DisplayObjectContainer,field:TextField,changed:Function,failed:Function;
  private var timer:Timer,payload:String="",draft:String="",revision:uint=0,sentRevision:uint=0;
  private var dispatching:Boolean=false,confirmed:Boolean=false;
  public function NativeChatDelivery(owner:DisplayObjectContainer,input:TextField,onChanged:Function,onFailed:Function,timeout:int=8000){
   chat=owner;field=input;changed=onChanged;failed=onFailed;timer=new Timer(timeout,1);
   timer.addEventListener(TimerEvent.TIMER,expired);
   chat.addEventListener("send_message",sent,false,10000);
   field.addEventListener(Event.CHANGE,edited);
  }
  public function get pending():Boolean{return payload.length>0;}
  public static function syncInput(field:TextField,text:String):void{
   // The shipped Hebrew field adds direction marks for display. They are not
   // user edits and must not invalidate an acknowledgement on every sync.
   if(field.text.replace(/[\u200e\u200f]/g,"")==text)return;
   field.text=text;field.dispatchEvent(new Event(Event.CHANGE,true));
  }
  public function submit(originalSubmit:Function):void{
   if(pending||dispatching)return;
   var before:String=field.text,beforeRevision:uint=revision;
   draft="";confirmed=false;dispatching=true;
   try{originalSubmit();}
   finally{
    dispatching=false;
    // ChatInput clears even when its validation rejects Enter. It also clears
    // immediately after dispatch, before the room/server can accept a message.
    if(revision==beforeRevision){if(confirmed)field.text="";else if(field.text=="")field.text=before;}
    changed();
   }
  }
  private function sent(e:Event):void{
   if(!dispatching)return;
   payload=String(Object(e).getMessage());draft=field.text;sentRevision=revision;
   timer.reset();timer.start();changed();trace("MOBILE_CHAT_DELIVERY awaiting_bubble");
  }
  private function edited(e:Event):void{revision++;}
  public function confirmBubble(text:String):void{
   if(!pending||!matches(payload,text))return;
   confirmed=true;
   if(!dispatching&&revision==sentRevision&&field.text==draft)field.text="";
   // A synchronous tutorial bubble is completed after the native submit returns.
   payload="";timer.reset();changed();trace("MOBILE_CHAT_DELIVERY displayed");
  }
  private static function normalized(value:String):String{return value.replace(/[\s\u200e\u200f]/g,"");}
  private static function matches(sent:String,shown:String):Boolean{
   var a:String=normalized(sent),b:String=normalized(shown);if(a==b)return true;
   // The original server may mask words/phone numbers. A displayed mask is
   // accepted only in this player's bubble and only against the pending text.
   if(b.indexOf("*")<0)return false;
   var parts:Array=b.split(/\*+/),pattern:String="";
   for(var i:int=0;i<parts.length;i++){if(i)pattern+=".*";pattern+=String(parts[i]).replace(/[.*+?^${}()|[\]\\]/g,"\\$&");}
   return new RegExp("^"+pattern+"$").test(a);
  }
  private function expired(e:TimerEvent):void{
   payload="";draft="";timer.reset();changed();trace("MOBILE_CHAT_DELIVERY unconfirmed_draft_retained");failed();
  }
  public function dispose():void{
   timer.stop();timer.removeEventListener(TimerEvent.TIMER,expired);
   chat.removeEventListener("send_message",sent);field.removeEventListener(Event.CHANGE,edited);payload="";
  }
 }
}
