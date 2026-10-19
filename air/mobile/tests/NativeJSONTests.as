package {
 import com.adobe.serialization.json.JSON;
 import flash.display.Sprite;import flash.desktop.NativeApplication;import flash.utils.getTimer;import flash.utils.getDefinitionByName;
 public class NativeJSONTests extends Sprite {
  private var checks:int=0;
  private var nativeJSON:Object=getDefinitionByName("JSON");
  public function NativeJSONTests(){
   try{
    var valid:Array=['{"t":"xt","b":{"r":-1,"o":{"21":"123","92":"abc","93":1}}}',
     '{"a":[0,-0,-1,1.25,1e2,9007199254740991,2147483648],"null":null,"true":true,"false":false}',
     '{"text":"שלום 🙂 English","escape":"\\u05e9\\u05dc\\u05d5\\u05dd\\n\\t\\b\\f\\r\\\\\\\"\\/","s":"\\ud83d\\ude42"}',
     '{"empty":{},"array":[],"deep":{"a":[{"b":[null,{},[]]}]}}',
     '{"duplicate":1,"duplicate":2,"__proto__":{"x":1},"constructor":3}',
     ' {"trailing":true} trailing','{/* original tokenizer accepts comments */"a":1}','{"escape":"\\q"}',
     '{"float":1e-400,"zero":-0}'];
    for each(var source:String in valid){check(equal(com.adobe.serialization.json.JSON.decode(source),decode(source)),"accepted_parity");}
    var invalid:Array=['{"a":01}','{"a":1e400}','{"a":NaN}','{"a":Infinity}','{"a":true,}','{"a":','{"a":"\\uQ000"}','{"a":[1,]}'];
    for each(source in invalid){var a:Boolean=false,b:Boolean=false;try{com.adobe.serialization.json.JSON.decode(source);}catch(e:*){a=true;}try{decode(source);}catch(f:*){b=true;}trace("REJECT_CASE index="+invalid.indexOf(source)+" legacy="+a+" native="+b);}
    for each(var rows:int in [100,1000,10000]){
     var list:Array=[];for(var i:int=0;i<rows;i++)list.push({"id":i,"type":i%12,"name":"פריט בדיקה Item "+i,"price":42,"flags":[true,false,null],"meta":{"x":12.25,"y":-1,"owned":true}});
     var payload:String=nativeJSON.stringify({"t":"xt","b":{"r":-1,"o":{"21":"static_data","items":list}}});
     // Same string and repetitions for each parser; no payload is logged.
     decode(payload);com.adobe.serialization.json.JSON.decode(payload);
     var start:int=getTimer(),last:Object;for(i=0;i<3;i++)last=com.adobe.serialization.json.JSON.decode(payload);var legacy:int=getTimer()-start;
     start=getTimer();for(i=0;i<3;i++)last=decode(payload);var nativeMs:int=getTimer()-start;
     check(equal(last,com.adobe.serialization.json.JSON.decode(payload)),"large_payload_parity");
     trace("NATIVE_JSON_BENCH rows="+rows+" chars="+payload.length+" repeats=3 legacyMs="+legacy+" guardedNativeMs="+nativeMs);
    }
    trace("NATIVE_JSON_PASS checks="+checks);NativeApplication.nativeApplication.exit(0);
   }catch(error:*){trace("NATIVE_JSON_FAIL "+error);NativeApplication.nativeApplication.exit(2);}
  }
  private function decode(source:String):* {try{return nativeJSON.parse(source,finiteNumber);}catch(e:*){return com.adobe.serialization.json.JSON.decode(source);}}
  private function finiteNumber(key:String,value:*):* {if(value is Number&&!isFinite(Number(value)))throw new Error("non_finite_json_number");return value;}
  private function equal(a:*,b:*):Boolean{if(a===b)return true;if(a==null||b==null||typeof a!=typeof b)return false;if(a is Array){if(!(b is Array)||a.length!=b.length)return false;for(var i:int=0;i<a.length;i++)if(!equal(a[i],b[i]))return false;return true;}if(typeof a=="object"){var n:int=0,m:int=0;for(var k:String in a){n++;if(!b.hasOwnProperty(k)||!equal(a[k],b[k]))return false;}for(k in b)m++;return n==m;}return false;}
  private function check(ok:Boolean,label:String):void{if(!ok)throw new Error(label);checks++;}
 }
}
