package {
 import flash.display.Sprite;
 import flash.desktop.NativeApplication;
 import org.ekoloko.air.NativePerformance;
 public class MobilePerformanceTests extends Sprite {
  private var checks:int=0;
  private function check(ok:Boolean,label:String):void {if(!ok)throw new Error(label);checks++;}
  public function MobilePerformanceTests() {
   try {
    NativePerformance.reset();
    NativePerformance.record("socket_record",12,100);
    NativePerformance.record("socket_record",2500,200000);
    var row:Object=NativePerformance.snapshot().socket_record;
    check(row.count==2&&row.totalMs==2512&&row.maxMs==2500,"time_totals");
    check(row.bytes==200100&&row.maxBytes==200000&&row.slowCount==1,"large_record_and_stall");
    row.count=99;check(NativePerformance.snapshot().socket_record.count==2,"snapshot_detached");
    check(!NativePerformance.add({stage:"private_body",count:1,totalMs:1,maxMs:1,bytes:9}),"unknown_category_rejected");
    check(!NativePerformance.add({stage:"socket_record",count:1,totalMs:1,maxMs:2,bytes:9}),"invalid_time_rejected");
    check(!NativePerformance.add({stage:"socket_record",count:1,totalMs:1,maxMs:1,bytes:9,maxBytes:10}),"invalid_max_bytes");
    check(!NativePerformance.add({stage:"socket_record",count:1,totalMs:1,maxMs:1,bytes:9,slowCount:2}),"invalid_slow_count");
    check(!NativePerformance.add({stage:"socket_record",count:1,totalMs:1,maxMs:1,bytes:NaN}),"nonfinite_rejected");
    check(NativePerformance.add({stage:"socket_decode",count:2,totalMs:10,maxMs:7,bytes:0}),"legacy_aggregate_accepted");
    check(NativePerformance.add({stage:"socket_decode",count:1,totalMs:1,maxMs:1,bytes:0,body:"not retained"}),"extra_data_ignored");
    check(!NativePerformance.snapshot().socket_decode.hasOwnProperty("body"),"body_never_retained");
    NativePerformance.reset();check(!NativePerformance.snapshot().hasOwnProperty("socket_record"),"reset");
    trace("MOBILE_PERFORMANCE_PASS checks="+checks);NativeApplication.nativeApplication.exit(0);
   }catch(e:Error){trace("MOBILE_PERFORMANCE_FAIL "+e);NativeApplication.nativeApplication.exit(1);}
  }
 }
}
