package {
 import flash.display.*;import flash.events.*;import flash.text.*;import flash.desktop.NativeApplication;import flash.utils.setTimeout;
 public final class NativeChatDeliveryTests extends Sprite {
  private var field:TextField=new TextField(),chat:Sprite=new Sprite(),guard:NativeChatDelivery,shadow:String="",sends:int=0,failures:int=0,checks:int=0;
  public function NativeChatDeliveryTests(){
   loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR,function(e:UncaughtErrorEvent):void{e.preventDefault();trace("DELIVERY_FAIL "+e.error);NativeApplication.nativeApplication.exit(2);});
   addChild(chat);chat.addChild(field);guard=new NativeChatDelivery(chat,field,function():void{shadow=field.text;},function():void{failures++;},80);
   var draft:MobileChatDraft=new MobileChatDraft();
   draft.readNative("טיוטה נשמרת",true);draft.readNative("");
   NativeChatDelivery.syncInput(field,draft.text);
   check(field.text=="טיוטה נשמרת","native_empty_detach_keeps_visible_legacy_draft");
   guard.submit(function():void{chat.dispatchEvent(new DeliveryMessageEvent(field.text));field.text="";});
   check(guard.pending&&field.text==draft.text,"closed_keyboard_draft_uses_original_submit");
   guard.confirmBubble(draft.text);draft.accept(field.text);check(draft.text=="","only_bubble_clears_draft");
   draft.readNative("הודעה הבאה",true);NativeChatDelivery.syncInput(field,draft.text);
   guard.submit(function():void{chat.dispatchEvent(new DeliveryMessageEvent(field.text));field.text="";});
   check(guard.pending&&field.text==draft.text,"next_message_without_new_editor");
   guard.confirmBubble(draft.text);draft.accept(field.text);
   draft.readNative("מחק אותי",true);draft.readNative("",true);check(draft.text=="","explicit_delete_all_is_retained");
   // Physical failure: Flash contained ten characters while StageText and
   // the previous canonical draft were empty. Preserve the observed field edit
   // across native blur, then use that draft for the original send chain.
   var legacyEdit:Function=function(e:Event):void{draft.accept(field.text);};
   field.addEventListener(Event.CHANGE,legacyEdit);
   edit("טיוטה מהשדה הישן");
   check(draft.text=="טיוטה מהשדה הישן","legacy_native_edit_captured");
   draft.readNative("");NativeChatDelivery.syncInput(field,draft.text);
   check(field.text==draft.text&&draft.text.length>0,"blur_does_not_replace_legacy_edit");
   guard.submit(function():void{chat.dispatchEvent(new DeliveryMessageEvent(field.text));field.text="";});
   check(guard.pending&&field.text==draft.text,"fallback_draft_sent_without_loss");
   edit("הטיוטה הבאה");guard.confirmBubble("טיוטה מהשדה הישן");
   check(field.text=="הטיוטה הבאה"&&draft.text==field.text,"fallback_new_draft_survives_old_ack");
   edit("");check(draft.text=="","legacy_explicit_delete_supported");
   field.removeEventListener(Event.CHANGE,legacyEdit);
   edit("טיוטה שלא התקבלה");guard.submit(function():void{field.text="";});check(field.text==shadow&&shadow=="טיוטה שלא התקבלה","rejected_enter_preserves_both_editors");
   edit("שלום");guard.submit(send);check(guard.pending&&field.text=="שלום"&&shadow=="שלום","awaiting_does_not_erase");
   guard.submit(send);check(sends==1,"double_tap_not_duplicated");guard.confirmBubble("הודעה אחרת");check(guard.pending,"unrelated_bubble_not_ack");
   guard.confirmBubble(" שלום ");check(!guard.pending&&field.text==""&&shadow=="","confirmed_clears_both_editors");
   edit("ראשונה");guard.submit(send);edit("טיוטה חדשה");guard.confirmBubble("ראשונה");check(field.text=="טיוטה חדשה","late_ack_keeps_new_draft");
   edit("אותה הודעה");guard.submit(send);edit("שינוי");edit("אותה הודעה");guard.confirmBubble("אותה הודעה");check(field.text=="אותה הודעה","edited_back_draft_not_cleared");
   edit("אבגדהוזחטיכלמנסעפצקרשת");guard.submit(send);guard.confirmBubble("אבגדהוזחטיכלמנס\nעפצקרשת");check(!guard.pending,"long_token_wrapped_bubble_matches");
   edit("בדיקה מילה לדוגמה");guard.submit(send);guard.confirmBubble("בדיקה *** לדוגמה");check(field.text=="","server_masked_bubble_matches");
   edit("מיידי");guard.submit(function():void{chat.dispatchEvent(new DeliveryMessageEvent(field.text));guard.confirmBubble(field.text);check(field.text=="מיידי","synchronous_ack_preserves_original_callback_payload");field.text="";});check(field.text==""&&!guard.pending,"synchronous_tutorial_bubble_not_restored");
   edit("אחרי אישור");guard.submit(function():void{field.text="";});check(field.text=="אחרי אישור","rejection_after_success_preserved");
   edit("שגיאת שליחה");try{guard.submit(function():void{field.text="";throw new Error("test");});}catch(e:Error){}check(field.text=="שגיאת שליחה","exception_preserves_draft");
   edit("ללא אישור");guard.submit(send);var before:int=sends;
   setTimeout(function():void{
    check(!guard.pending&&failures==1&&field.text=="ללא אישור"&&shadow==field.text,"timeout_retains_draft");check(sends==before,"timeout_never_auto_retries");
    guard.submit(send);check(sends==before+1&&guard.pending,"explicit_retry_allowed");guard.dispose();
    setTimeout(function():void{check(failures==1,"dispose_cancels_timer");trace("DELIVERY_PASS checks="+checks+" network=false");NativeApplication.nativeApplication.exit(0);},110);
   },110);
  }
  private function edit(text:String):void{field.text=text;field.dispatchEvent(new Event(Event.CHANGE,true));}
  private function send():void{sends++;chat.dispatchEvent(new DeliveryMessageEvent(field.text));field.text="";}
  private function check(value:Boolean,name:String):void{if(!value)throw new Error(name);checks++;}
 }
}
import flash.events.Event;
class DeliveryMessageEvent extends Event {
 private var value:String;
 public function DeliveryMessageEvent(text:String){super("send_message");value=text;}
 public function getMessage():String{return value;}
}
