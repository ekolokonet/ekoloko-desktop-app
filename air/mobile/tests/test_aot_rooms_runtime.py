"""Compare real room contracts and frozen artwork in isolated/shared AIR domains.

A desktop AIR probe, not an iOS AOT/phone acceptance claim. Writes only output.
"""
import argparse,hashlib,json,os,subprocess,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from prepare_aot_private_globals import isolate_globals
from prepare_aot_catalog import inspect
AS=r'''package {import org.ekoloko.air.NativeServices;import flash.display.*;import flash.events.*;import flash.net.*;import flash.system.*;import flash.desktop.NativeApplication;import flash.filesystem.*;import flash.geom.*;import flash.utils.*;
public class AOTRoomsProbe extends Sprite {
private var rows:Array,index:int=0,original:Loader,candidate:Loader;private var originalBase:ApplicationDomain=new ApplicationDomain(null);private var failures:int=0;
private var fields:Array=["BG","FG","walkarea","FGAnimations","BGAnimations","doors","objects","recycleBinsData","inWorlGameData","clickbleItems","taskItems","traps","inWorldQuizGamesData","storesData","potionStoresData","animalStoresData"];
public function AOTRoomsProbe(){NativeServices.assetLoadsSuspended=true;var f:FileStream=new FileStream();f.open(File.applicationDirectory.resolvePath("cases.json"),FileMode.READ);rows=JSON.parse(f.readUTFBytes(f.bytesAvailable)) as Array;f.close();setTimeout(function():void{trace("ROOMS_FAIL timeout");NativeApplication.nativeApplication.exit(2);},180000);load("Stub.swf",originalBase,next);}
private function freeze(d:DisplayObject):void {if(d is MovieClip)MovieClip(d).gotoAndStop(1);if(d is DisplayObjectContainer){var c:DisplayObjectContainer=DisplayObjectContainer(d);for(var i:int=0;i<c.numChildren;i++)freeze(c.getChildAt(i));}}
private function pixels(d:DisplayObject):String{freeze(d);var b:Rectangle=d.getBounds(d);var w:int=Math.max(1,Math.ceil(b.width)),h:int=Math.max(1,Math.ceil(b.height));var scale:Number=Math.min(1,1024/w,768/h);var bmp:BitmapData=new BitmapData(Math.max(1,Math.ceil(w*scale)),Math.max(1,Math.ceil(h*scale)),true,0);bmp.draw(d,new Matrix(scale,0,0,scale,-b.x*scale,-b.y*scale));var a:uint=2166136261,c:uint=5381;for each(var v:uint in bmp.getVector(bmp.rect)){a=(a^v)*16777619;c=((c<<5)+c)^v;}bmp.dispose();return w+"x"+h+":"+a+":"+c;}
private function norm(v:*):* {if(v===null||v===undefined)return null;if(v is Class)return {kind:"class",value:norm(new v())};if(v is DisplayObject)return {kind:"display",pixels:pixels(v),x:v.x,y:v.y};if(v is Array){var arr:Array=[];for each(var item:* in v)arr.push(norm(item));return arr;}if(typeof v=="object"){var result:Object={};var keys:Array=[];for(var key:String in v)keys.push(key);keys.sort();for each(key in keys)result[key]=norm(v[key]);return result;}return v;}
private function load(path:String, domain:ApplicationDomain, done:Function):Loader {var l:Loader=new Loader();l.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR,function(e:IOErrorEvent):void{trace("ROOMS_FAIL "+e.text);NativeApplication.nativeApplication.exit(3);});l.contentLoaderInfo.addEventListener(Event.COMPLETE,function(e:Event):void{freeze(l.content);done();});l.load(new URLRequest(File.applicationDirectory.resolvePath(path).url),new LoaderContext(false,domain));return l;}
private function next():void{if(index==rows.length){trace("ROOMS_"+(failures?"FAIL":"PASS")+" cases="+index+" failures="+failures);NativeApplication.nativeApplication.exit(failures?4:0);return;}original=load(rows[index].original,new ApplicationDomain(originalBase),function():void{candidate=load(rows[index].candidate,ApplicationDomain.currentDomain,compare);});}
private function compare():void {try{var a:Object=original.content,b:Object=candidate.content;var checked:int=0;for each(var field:String in fields){if((field in a)!=(field in b))throw new Error("contract missing "+field);if(!(field in a))continue;var expected:String=JSON.stringify(norm(a[field])),actual:String=JSON.stringify(norm(b[field]));if(expected!=actual){var control:String=JSON.stringify(norm(a[field]));if(control==expected)throw new Error("mismatch "+field+" expected="+expected+" actual="+actual);trace("ROOMS_NONDETERMINISTIC "+rows[index].path+" "+field);}checked++;}if(checked<8)throw new Error("not a room");trace("ROOMS_CASE "+index+" "+rows[index].path+" contracts="+checked);}catch(e:Error){failures++;trace("ROOMS_CASE_FAIL "+index+" "+rows[index].path+" "+e.getStackTrace());}original.unloadAndStop(true);candidate.unloadAndStop(true);index++;setTimeout(next,0);}
}}
'''
def main():
 p=argparse.ArgumentParser();p.add_argument('--catalog',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--limit',type=int,default=0);a=p.parse_args();a.catalog=a.catalog.resolve();a.output=a.output.resolve();a.output.mkdir(parents=True,exist_ok=False)
 cat=json.loads((a.catalog/'catalog.json').read_text());rows=[];blocked=[]
 for digest,r in cat['objects'].items():
  paths=[x for x in r['paths'] if x.startswith('world_rooms/') or '/world_rooms/' in x]
  if not paths:continue
  data=(a.catalog/'compiled-content'/(digest+'.swf')).read_bytes()
  try:
   candidate,receipt=isolate_globals(data)
   original='original-'+str(len(rows))+'.swf';output='candidate-'+str(len(rows))+'.swf';(a.output/original).write_bytes(data);(a.output/output).write_bytes(candidate)
   rows.append(dict(path=paths[0],original=original,candidate=output,transform=receipt,sourceCatalogDigest=digest))
  except ValueError as e:blocked.append(dict(path=paths[0],reason=str(e)))
  if a.limit and len(rows)>=a.limit:break
 (a.output/'cases.json').write_text(json.dumps(rows,indent=2));(a.output/'blocked.json').write_text(json.dumps(blocked,indent=2));(a.output/'AOTRoomsProbe.as').write_text(AS)
 (a.output/'application.xml').write_text('<application xmlns="http://ns.adobe.com/air/application/51.4"><id>org.ekoloko.aotroomsprobe</id><versionNumber>0.1.0</versionNumber><filename>AOTRoomsProbe</filename><initialWindow><content>AOTRoomsProbe.swf</content><visible>false</visible></initialWindow><supportedProfiles>extendedDesktop</supportedProfiles></application>')
 stub=a.output/'org/ekoloko/air/NativeServices.as';stub.parent.mkdir(parents=True);stub.write_text('package org.ekoloko.air {import flash.events.EventDispatcher;public final class NativeServices {public static var assetGeneration:uint=1;public static var assetLoadsSuspended:Boolean=true;public static var events:EventDispatcher=new EventDispatcher();}}')
 (a.output/'Stub.as').write_text('package {import flash.display.Sprite;import org.ekoloko.air.NativeServices;public class Stub extends Sprite {public function Stub(){NativeServices.assetLoadsSuspended=true;}}}')
 sdk=Path('/Volumes/T9/AIR/sdks/AIRSDK_51.4.1');env=dict(os.environ,JAVA_HOME='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home')
 subprocess.run([str(sdk/'bin/amxmlc'),'-source-path+='+str(a.output),'-output='+str(a.output/'Stub.swf'),str(a.output/'Stub.as')],env=env,check=True)
 subprocess.run([str(sdk/'bin/amxmlc'),'-source-path+='+str(a.output),'-debug=true','-omit-trace-statements=false','-output='+str(a.output/'AOTRoomsProbe.swf'),str(a.output/'AOTRoomsProbe.as')],env=env,check=True)
 r=subprocess.run([str(sdk/'bin/adl'),str(a.output/'application.xml'),str(a.output)],env=env,capture_output=True,text=True,timeout=190)
 (a.output/'result.log').write_text(r.stdout+r.stderr);print(r.stdout+r.stderr)
 (a.output/'receipt.json').write_text(json.dumps(dict(cases=len(rows),blocked=len(blocked),runtime='desktop AIR ADL',passed=r.returncode==0 and 'ROOMS_PASS' in (r.stdout+r.stderr),phoneTested=False,aotRuntimeTested=False,externalAssetLoading='disabled by explicit harness-only NativeServices stub',nondeterministicFields=(r.stdout+r.stderr).count('ROOMS_NONDETERMINISTIC'),runtimeErrors=('Error #' in (r.stdout+r.stderr))),indent=2)+'\n')
 if r.returncode!=0:raise SystemExit(r.returncode)
if __name__=='__main__':main()
