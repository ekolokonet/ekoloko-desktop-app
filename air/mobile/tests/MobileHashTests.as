package {
 import flash.display.Sprite;
 import flash.desktop.NativeApplication;
 import flash.filesystem.*;
 import flash.utils.*;
 import org.ekoloko.air.NativeServices;
 public class MobileHashTests extends Sprite {
  public function MobileHashTests() {
   try {
    var stream:FileStream=new FileStream(),configBytes:ByteArray=new ByteArray();
    stream.open(File.applicationDirectory.resolvePath("vectors.json"),FileMode.READ);stream.readBytes(configBytes);stream.close();
    var vectors:Array=JSON.parse(configBytes.toString()) as Array,count:int=0;
    for each(var v:Object in vectors) {
     var bytes:ByteArray=new ByteArray();stream.open(File.applicationDirectory.resolvePath(v.file),FileMode.READ);stream.readBytes(bytes);stream.close();
     for each(var pos:uint in [0,uint(bytes.length/2),bytes.length]) {
      bytes.position=pos;var started:int=getTimer();
      if(NativeServices.sha(bytes)!=v.sha || bytes.position!=pos || bytes.length!=v.length)throw new Error("hash_vector_failed_"+v.file);
      trace("HASH_VECTOR_PASS file="+v.file+" bytes="+bytes.length+" elapsedMs="+(getTimer()-started));count++;
     }
     if(bytes.length) {var old:String=v.sha;bytes[0]^=1;if(NativeServices.sha(bytes)==old)throw new Error("mutation_not_detected");count++;}
    }
    trace("MOBILE_HASH_PASS checks="+count);NativeApplication.nativeApplication.exit(0);
   } catch(e:Error) {trace("MOBILE_HASH_FAIL "+e);NativeApplication.nativeApplication.exit(1);}
  }
 }
}
