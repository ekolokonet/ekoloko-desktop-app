package org.ekoloko.air {
 /** Bounded local aggregates only: no account, chat, packet bodies or URLs. */
 public final class NativePerformance {
  private static const ALLOWED:Array=["socket_wire","socket_plain","socket_utf8","socket_record","socket_decode","socket_dispatch","socket_decrypt","bootstrap_static_cache","bootstrap_ui","bootstrap_proof","bootstrap_ui_data","bootstrap_inventory_requests","bootstrap_avatar","bootstrap_room","bootstrap_helper","asset_read","asset_cache_hit","asset_hash","asset_callback"];
  private static var totals:Object={};
  public static function reset():void {totals={};}
  public static function record(stage:String,ms:Number,bytes:Number=0):void {add({stage:stage,count:1,totalMs:Math.max(0,ms),maxMs:Math.max(0,ms),bytes:bytes,maxBytes:bytes,slowCount:ms>=50?1:0});}
  public static function add(value:Object):Boolean {
   if(!value||ALLOWED.indexOf(value.stage)<0)return false;
   for each(var key:String in ["count","totalMs","maxMs","bytes"]){if(!(value[key] is Number)||!isFinite(value[key])||value[key]<0||value[key]>9007199254740991)return false;}
   if(value.count<1||value.count!=Math.floor(value.count)||value.maxMs>value.totalMs)return false;
   var maxBytes:Number=value.hasOwnProperty("maxBytes")?value.maxBytes:(value.count==1?value.bytes:0);
   var slowCount:Number=value.hasOwnProperty("slowCount")?value.slowCount:0;
   if(!isFinite(maxBytes)||maxBytes<0||maxBytes>value.bytes||!isFinite(slowCount)||slowCount<0||slowCount>value.count||slowCount!=Math.floor(slowCount))return false;
   var row:Object=totals[value.stage];if(!row)row=totals[value.stage]={count:0,totalMs:0,maxMs:0,bytes:0,maxBytes:0,slowCount:0};
   row.count+=value.count;row.totalMs+=value.totalMs;row.maxMs=Math.max(row.maxMs,value.maxMs);row.bytes+=value.bytes;row.maxBytes=Math.max(row.maxBytes,maxBytes);row.slowCount+=slowCount;return true;
  }
  public static function snapshot():Object {
   var copy:Object={};for(var name:String in totals){var row:Object=totals[name];copy[name]={count:row.count,totalMs:row.totalMs,maxMs:row.maxMs,bytes:row.bytes,maxBytes:row.maxBytes,slowCount:row.slowCount};}return copy;
  }
 }
}
