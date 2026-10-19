package {
 import flash.display.Sprite;
 import flash.desktop.NativeApplication;
 import org.ekoloko.air.NativeServices;
 import org.ekoloko.air.BuildInfo;
 public class MobileOptionalAssetTests extends Sprite {
  public function MobileOptionalAssetTests(){
   var info:Object=BuildInfo;
   var enabled:Boolean="RECYCLE_ART_FALLBACK_MAIN_SHA" in info && info.RECYCLE_ART_FALLBACK_MAIN_SHA!="";
   NativeServices.manifest={assets:{"main.swf":{sha256:new Array(65).join("a")}}};
   check(NativeServices.optionalAssetPath("/ekoloko/recycle_items/1001_5.swf")==enabled,"exact_capability");
   for each(var path:String in ["/ekoloko/main.swf","/ekoloko/shell.swf","/ekoloko/rooms/100.swf","/ekoloko/recycle_items/a_5.swf","/ekoloko/recycle_items/1_5.swf/extra","/ekoloko/recycle_items/../1_5.swf"])
    check(!NativeServices.optionalAssetPath(path),"essential_or_invalid_path");
   NativeServices.manifest.assets["main.swf"].sha256=new Array(65).join("b");
   check(!NativeServices.optionalAssetPath("/ekoloko/recycle_items/1001_5.swf"),"different_core_disables_fallback");
   NativeServices.manifest=null;
   check(!NativeServices.optionalAssetPath("/ekoloko/recycle_items/1001_5.swf"),"no_core_disables_fallback");
   trace("OPTIONAL_ASSET_PASS enabled="+enabled);NativeApplication.nativeApplication.exit(0);
  }
  private function check(value:Boolean,label:String):void {if(!value)throw new Error(label);}
 }
}
