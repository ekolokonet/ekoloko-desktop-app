"""Actual AIR successful/missing SWF test using the unchanged RecycleItem consumer.

No server, accounts, currency or awards. Only the metadata cache/log/text seams
are stubbed. Uses original152data/item/scaler classes and one patched getter.
"""
import argparse,hashlib,json,os,shutil,subprocess
from pathlib import Path
BASE=Path(__file__).resolve().parents[2]
ORIGINAL=BASE/'build/mobile-update-152/all-152/scripts'
PATCH=BASE/'mobile/patches/recycle-art-fallback'
AS=r'''package {import flash.display.*;import flash.events.*;import flash.desktop.NativeApplication;import flash.utils.*;import com.vtweens.dataobjects.recycle.item.*;import com.vtweens.util.*;
public class RecycleFallbackProbe extends Sprite {private var phase:String="loaded",done:int=0;private var item:RecycleItem;
public function RecycleFallbackProbe(){loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR,function(e:UncaughtErrorEvent):void{e.preventDefault();var err:Error=e.error as Error;if("__VARIANT__"=="original"&&phase=="failed"&&err is TypeError){trace("RECYCLE_ORIGINAL_CRASH_CONFIRMED "+err.errorID);NativeApplication.nativeApplication.exit(0);}else{trace("RECYCLE_FAIL "+e.error);NativeApplication.nativeApplication.exit(3);}});setTimeout(function():void{trace("RECYCLE_FAIL timeout");NativeApplication.nativeApplication.exit(4);},10000);item=new RecycleItem(1,777);item.addEventListener(Event.COMPLETE,loaded);}
private function check(v:Boolean,msg:String):void{if(!v)throw new Error(msg);}
private function loaded(e:Event):void{done++;check(done==1,"duplicate successful event");check(item.getData().isLoaded,"loaded state");check(item.id==1&&item.type==1001&&item.ordinal==5&&item.price==17&&item.instanceId==777,"success metadata");var a:MovieClip=item.getData().getItem(),b:MovieClip=item.getData().getItem();check(a!==b&&a.width==20&&a.height==10,"successful constructor/clones");var bmp:BitmapData=new BitmapData(20,10,true,0);bmp.draw(a);check(bmp.getPixel32(5,5)==0xffff6600,"original artwork");bmp.dispose();check(item.numChildren==1,"room consumer addChild");trace("RECYCLE_LOADED_PASS");phase="failed";done=0;item=new RecycleItem(2,888);item.addEventListener(Event.COMPLETE,failed);}
private function failed(e:Event):void{done++;check(done==1,"duplicate failure event");check("__VARIANT__"=="patched","original unexpectedly survived");check(item.getData().isLoaded,"failed completed state");check(item.id==2&&item.type==1001&&item.ordinal==99&&item.price==17&&item.instanceId==888,"failure metadata");check(item.itemName=="recycle2"&&item.description=="description2","text metadata");var a:MovieClip=item.getData().getItem(),b:MovieClip=item.getData().getItem();check(a!==b&&a.width==1&&a.height==1,"fresh bounded fallback");check(!a.mouseEnabled&&!a.mouseChildren,"fallback mouse behavior");var bmp:BitmapData=new BitmapData(40,40,true,0);bmp.draw(a);for each(var pixel:uint in bmp.getVector(bmp.rect))check(pixel==0,"fallback must be invisible");bmp.dispose();Scaler.Rescale(a,35,35);check(isFinite(a.scaleX)&&isFinite(a.scaleY)&&a.width==35,"legacy scaler finite");check(item.numChildren==1,"failed room consumer addChild");var clone:RecycleItem=item.clone();check(clone.instanceId==888&&clone.id==2&&clone.numChildren==1,"failed cached clone");var replay:int=0;clone.addEventListener(Event.COMPLETE,function(e:Event):void{replay++;});check(replay==1,"late completion replay");clone.deactivate();check(clone.numChildren==0,"deactivate fallback");item.deactivate();check(item.numChildren==0,"deactivate item");trace("RECYCLE_FALLBACK_PASS loaded=1 failed=1 cachedClone=1 invisible=1 finiteScale=1 metadataPreserved=1");NativeApplication.nativeApplication.exit(0);}
}}
'''
STUBS={
'com/vtweens/consts/VERSION.as':'package com.vtweens.consts {public class VERSION {public static const RECYCLE_ITEMS_VERSION:String="test";}}',
'com/vtweens/text/TextResourceManager.as':'package com.vtweens.text {public class TextResourceManager {public static function getRecycleItemData(id:int):Array{return [id,"recycle"+id,"description"+id];}}}',
'com/vtweens/util/Log.as':'package com.vtweens.util {public class Log {public static function error(s:String):void{trace("EXPECTED_ART_IO "+s);}}}',
'com/vtweens/shell/ItemCache.as':'''package com.vtweens.shell {import com.vtweens.dataobjects.recycle.item.*;public class ItemCache {private static var cache:Object={};public static function GetRecycleItemData(id:int):RecycleItemData {return new RecycleItemData(id,1001,id==1?5:99,17,3);}public static function GetRecycleItemDisplayData(id:int):RecycleItemDisplayData {if(cache[id]==null)cache[id]=new RecycleItemDisplayData(id);return cache[id];}}}'''
}
def compile(sdk,source,output,env,include=None):
 cmd=[str(sdk/'bin/amxmlc'),'-debug=true','-omit-trace-statements=false','-source-path+='+str(source.parent),'-output='+str(output),str(source)]
 r=subprocess.run(cmd,env=env,text=True,capture_output=True);output.with_suffix('.compile.log').write_text(r.stdout+r.stderr)
 if r.returncode:raise RuntimeError(r.stdout+r.stderr)
def main():
 p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output=a.output.resolve();a.output.mkdir(parents=True,exist_ok=False)
 sdk=Path('/Volumes/T9/AIR/sdks/AIRSDK_51.4.1');env=dict(os.environ,JAVA_HOME='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home');results={}
 for variant in ('original','patched'):
  out=a.output/variant;src=out/'src';src.mkdir(parents=True);(out/'recycle_items').mkdir()
  for rel in ('com/vtweens/dataobjects/recycle/item/RecycleItem.as','com/vtweens/dataobjects/recycle/item/RecycleItemData.as','com/vtweens/dataobjects/recycle/item/RecycleItemDisplayData.as','com/vtweens/consts/RECYCLEITEM.as','com/vtweens/util/Scaler.as'):
   source=(PATCH if variant=='patched' and rel.endswith('RecycleItemDisplayData.as') else ORIGINAL)/rel;target=src/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
  for rel,content in STUBS.items():
   target=src/rel;target.parent.mkdir(parents=True,exist_ok=True);target.write_text(content)
  (src/'Artwork.as').write_text('package {import flash.display.MovieClip;public class Artwork extends MovieClip {public function getMC():Class{return Art;}}} import flash.display.MovieClip;class Art extends MovieClip {public function Art(){graphics.beginFill(0xff6600);graphics.drawRect(0,0,20,10);graphics.endFill();}}')
  compile(sdk,src/'Artwork.as',out/'recycle_items/1001_5.swf',env)
  (src/'RecycleFallbackProbe.as').write_text(AS.replace('__VARIANT__',variant));compile(sdk,src/'RecycleFallbackProbe.as',out/'RecycleFallbackProbe.swf',env)
  (out/'application.xml').write_text('<application xmlns="http://ns.adobe.com/air/application/51.4"><id>org.ekoloko.recyclefallback.'+variant+'</id><versionNumber>0.1.0</versionNumber><filename>RecycleFallbackProbe</filename><initialWindow><content>RecycleFallbackProbe.swf</content><visible>false</visible></initialWindow><supportedProfiles>extendedDesktop</supportedProfiles></application>')
  r=subprocess.run([str(sdk/'bin/adl'),str(out/'application.xml'),str(out)],env=env,text=True,capture_output=True,timeout=20);log=r.stdout+r.stderr;(out/'result.log').write_text(log);print(log)
  marker='RECYCLE_ORIGINAL_CRASH_CONFIRMED' if variant=='original' else 'RECYCLE_FALLBACK_PASS';assert r.returncode==0 and marker in log and 'RECYCLE_LOADED_PASS' in log,variant+' failed'
  results[variant]={'passed':True,'marker':marker}
 (a.output/'receipt.json').write_text(json.dumps({'tests':results,'runtime':'desktop AIR ADL','serverUsed':False,'phoneTested':False,'patchSha256':hashlib.sha256((PATCH/'com/vtweens/dataobjects/recycle/item/RecycleItemDisplayData.as').read_bytes()).hexdigest()},indent=2)+'\n')
if __name__=='__main__':main()
