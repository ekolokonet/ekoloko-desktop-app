package {
 import flash.display.Sprite;
 import flash.desktop.NativeApplication;
 import flash.filesystem.*;
 import flash.utils.*;
 import org.ekoloko.air.*;
 // Explicit production read-only smoke: no account, socket login, or game action.
 public class MobileLiveUpdateSmoke extends Sprite {
  private var store:NativeReleaseStore, cache:File, expected:Object;
  public function MobileLiveUpdateSmoke() {
   var stream:FileStream=new FileStream(),bytes:ByteArray=new ByteArray();
   stream.open(File.applicationDirectory.resolvePath("config.json"),FileMode.READ);
   stream.readBytes(bytes);stream.close();var config:Object=JSON.parse(bytes.toString());
   expected=config.manifest;cache=File.createTempDirectory();
   store=new NativeReleaseStore("https://play.ekoloko.org",config.modulus,cache,null,true);
   var installed:Object=JSON.parse(JSON.stringify(expected));installed.generation=0;installed.mainVersion="130";
   store.useBundledManifest(installed,function(p:String,e:Object):ByteArray{return null;});
   store.checkUpdate(function(available:Boolean):void {
    if(!available || !store.activateAvailableUpdate()) { fail(new Error("signed_activation_failed"));return; }
    if(store.manifest.releaseId!=expected.releaseId) { fail(new Error("unexpected_live_release"));return; }
    store.load("main.swf",function(b:ByteArray):void {
     if(NativeServices.sha(b)!=expected.assets["main.swf"].sha256) { fail(new Error("download_digest_mismatch"));return; }
     trace("MOBILE_LIVE_UPDATE_PASS release="+store.manifest.releaseId+" mainBytes="+b.length+" signature=verified download=verified");
     cache.deleteDirectory(true);NativeApplication.nativeApplication.exit(0);
    },fail);
   },fail);
   setTimeout(function():void{fail(new Error("live_update_timeout"));},45000);
  }
  private function fail(error:Error):void {
   trace("MOBILE_LIVE_UPDATE_FAIL "+error.message);NativeApplication.nativeApplication.exit(1);
  }
 }
}
