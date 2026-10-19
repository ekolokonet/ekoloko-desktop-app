package {
 import flash.desktop.NativeApplication;
 import flash.display.Sprite;
 import flash.events.*;
 import flash.filesystem.*;
 import flash.net.*;
 import flash.utils.*;
 import org.ekoloko.air.NativeServices;
 /** Read public deployed bytes for an explicit local content refresh; never executes them. */
 public class PublicAssetProbe extends Sprite {
  private var paths:Array=["conf/files_version.xml","main.swf","shell.swf"];
  private var loader:URLLoader;
  public function PublicAssetProbe(){next();}
  private function next():void {
   if(!paths.length){trace("PUBLIC_ASSET_PROBE_PASS");NativeApplication.nativeApplication.exit(0);return;}
   var path:String=paths.shift(),status:int=0;loader=new URLLoader();loader.dataFormat=URLLoaderDataFormat.BINARY;
   loader.addEventListener(HTTPStatusEvent.HTTP_RESPONSE_STATUS,function(e:HTTPStatusEvent):void{status=e.status;});
   loader.addEventListener(IOErrorEvent.IO_ERROR,function(e:Event):void{trace("PUBLIC_ASSET_PROBE_FAIL status="+status);NativeApplication.nativeApplication.exit(2);});
   loader.addEventListener(Event.COMPLETE,function(e:Event):void{
    if(status!=200){trace("PUBLIC_ASSET_PROBE_FAIL path="+path+" status="+status);NativeApplication.nativeApplication.exit(2);return;}
    var bytes:ByteArray=loader.data as ByteArray;
    var target:File=File.applicationStorageDirectory.resolvePath("public-source/"+path);target.parent.createDirectory();
    var f:FileStream=new FileStream();f.open(target,FileMode.WRITE);f.writeBytes(bytes);f.close();
    trace("PUBLIC_ASSET path="+path+" bytes="+bytes.length+" sha256="+NativeServices.sha(bytes));next();
   });
   var request:URLRequest=NativeServices.request(new URLRequest("/ekoloko/"+path+"?mobile_review="+new Date().time));request.useCache=false;request.cacheResponse=false;loader.load(request);
  }
 }
}
