package {
 import flash.desktop.NativeApplication;
 import flash.display.Sprite;
 import flash.display.StageQuality;
 import flash.events.Event;
 public final class MobileRenderQualityTests extends Sprite {
  public function MobileRenderQualityTests() {
   var policy:MobileRenderQuality=new MobileRenderQuality(stage);
   var chosen:String=stage.quality;
   // 16x16 accepts silently on iOS yet clips the 2622px Retina scene. Never select it.
   var allowed:Array=[StageQuality.HIGH_8X8_LINEAR,StageQuality.HIGH_8X8,StageQuality.BEST,StageQuality.HIGH];
   if(allowed.indexOf(chosen.toLowerCase())<0)throw new Error('unsafe_quality_selected');
   var initial:Object=policy.snapshot();
   if(initial.preferred!=StageQuality.HIGH_8X8_LINEAR)throw new Error('unsafe_preferred_quality');
   for each(var attempt:Object in initial.attempts) {
    if(allowed.indexOf(attempt.requested)<0)throw new Error('unsafe_quality_attempted');
   }
   if(initial.actual!=chosen||initial.selected!=chosen)throw new Error('diagnostic_not_effective');
   var accepted:Array=initial.attempts.filter(function(item:*,index:int,array:Array):Boolean{return item.accepted;});
   if(accepted.length!=1||String(accepted[0].requested).toLowerCase()!=chosen.toLowerCase())throw new Error('selection_without_readback');
   stage.quality=StageQuality.HIGH;
   stage.dispatchEvent(new Event(Event.EXIT_FRAME));
   if(stage.quality!=chosen||policy.snapshot().actual!=chosen)throw new Error('legacy_downgrade_not_restored');
   var again:Object=policy.snapshot();again.attempts.push({requested:'invalid'});
   if(policy.snapshot().attempts.length!=initial.attempts.length)throw new Error('diagnostic_array_mutation');
   policy.dispose();stage.quality=StageQuality.HIGH;stage.dispatchEvent(new Event(Event.EXIT_FRAME));
   if(stage.quality.toLowerCase()!=StageQuality.HIGH)throw new Error('listener_not_removed');
   trace('MOBILE_RENDER_QUALITY_PASS '+JSON.stringify(initial));NativeApplication.nativeApplication.exit(0);
  }
 }
}
