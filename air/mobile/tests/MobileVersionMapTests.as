package {
 import flash.display.Sprite;
 import flash.events.UncaughtErrorEvent;
 import flash.desktop.NativeApplication;
 import flash.filesystem.File;
 import flash.filesystem.FileStream;
 import flash.filesystem.FileMode;
 import flash.utils.ByteArray;
 import org.ekoloko.air.MobileVersionMapPolicy;
 public class MobileVersionMapTests extends Sprite {
  public function MobileVersionMapTests() {
   loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR,function(e:UncaughtErrorEvent):void { e.preventDefault();trace("POLICY_FAIL "+e.error);NativeApplication.nativeApplication.exit(2);});
   var stream:FileStream=new FileStream();stream.open(File.applicationDirectory.resolvePath("fixtures.json"),FileMode.READ);
   var cases:Array=JSON.parse(stream.readUTFBytes(stream.bytesAvailable)) as Array;stream.close();
   for each(var c:Object in cases) {
    var bytes:ByteArray=new ByteArray();bytes.writeUTFBytes(c.current);bytes.position=bytes.length;
    var result:Boolean=MobileVersionMapPolicy.compatible(bytes,c.manifest,c.baseline,c.mainSha);
    if(result!=c.expected)throw new Error(c.label+" expected="+c.expected+" actual="+result);
    if(bytes.position!=bytes.length)throw new Error("position_changed:"+c.label);
   }
   trace("VERSION_MAP_POLICY_PASS cases="+cases.length);NativeApplication.nativeApplication.exit(0);
  }
 }
}
