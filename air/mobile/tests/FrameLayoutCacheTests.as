package {
 import flash.display.*;import flash.text.*;import flash.desktop.NativeApplication;
 public class FrameLayoutCacheTests extends Sprite {
  private var checks:int=0;
  public function FrameLayoutCacheTests(){
   try {
    var cache:NativeFrameLayoutCache=new NativeFrameLayoutCache(),button:Sprite=new Sprite(),field:TextField=new TextField();
    var objects:Array=[button,field,null];addChild(button);addChild(field);
    check(cache.needs(objects),"initial_layout");cache.commit(objects);
    var repeats:int=0;for(var i:int=0;i<1000;i++)if(cache.needs(objects))repeats++;
    check(repeats==0,"thousand_stable_frames_no_reflow");
    button.x=10;check(cache.needs(objects),"native_position_change");cache.commit(objects);check(!cache.needs(objects),"post_layout_snapshot_stable");
    button.scaleX=2;check(cache.needs(objects),"native_scale_change");cache.commit(objects);
    button.visible=false;check(cache.needs(objects),"visibility");cache.commit(objects);
    button.mouseEnabled=false;check(cache.needs(objects),"hit_state");cache.commit(objects);
    button.mouseChildren=false;check(cache.needs(objects),"child_hit_state");cache.commit(objects);
    button.alpha=.5;check(cache.needs(objects),"alpha");cache.commit(objects);
    button.addChild(new Sprite());check(cache.needs(objects),"direct_content_added");cache.commit(objects);
    button.removeChildAt(0);check(cache.needs(objects),"direct_content_removed");cache.commit(objects);
    field.text="שלום";check(cache.needs(objects),"programmatic_chat_text");cache.commit(objects);
    field.width+=20;check(cache.needs(objects),"text_bounds");cache.commit(objects);
    field.type=TextFieldType.INPUT;check(cache.needs(objects),"chat_eligibility");cache.commit(objects);
    field.wordWrap=true;check(cache.needs(objects),"text_wrapping_reset");cache.commit(objects);
    var parent:Sprite=new Sprite();addChild(parent);parent.addChild(button);check(cache.needs(objects),"reparent");cache.commit(objects);
    var replacement:Sprite=new Sprite();var replaced:Array=[replacement,field,null];check(cache.needs(replaced),"same_count_replacement");cache.commit(replaced);
    check(cache.needs([field,replacement,null]),"display_order");cache.commit(objects);
    cache.invalidate();check(cache.needs(objects),"orientation_keyboard_layout_invalidation");cache.commit(objects);
    // Deep subtree events invalidate via ConnectedMobileUI's ADDED/REMOVED/CHANGE listeners.
    cache.invalidate();check(cache.needs(objects),"deep_content_event");cache.commit(objects);
    repeats=0;for(i=0;i<60;i++)if(cache.needs(objects,true))repeats++;
    check(repeats==60,"modal_shutter_animation_every_frame");check(!cache.needs(objects),"settled_modal_gate_returns_to_cache");
    trace("FRAME_LAYOUT_CACHE_PASS checks="+checks);NativeApplication.nativeApplication.exit(0);
   }catch(e:Error){trace("FRAME_LAYOUT_CACHE_FAIL "+e.message);NativeApplication.nativeApplication.exit(2);}
  }
  private function check(ok:Boolean,label:String):void{if(!ok)throw new Error(label);checks++;}
 }
}
