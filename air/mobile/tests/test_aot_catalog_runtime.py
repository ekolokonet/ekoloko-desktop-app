"""Compare Main152 isolated item pixels/contracts with their child-domain originals.

ADL is an actual AIR runtime, but this is not a phone or an AOT runtime claim.
All transformed assets are loaded as packaged URLs in currentDomain.
"""
import argparse, hashlib, json, os
from pathlib import Path
import shutil, subprocess

AS = r'''package {
import org.ekoloko.air.aot.PackagedDisplayLoader;import flash.display.*;import flash.events.*;import flash.net.*;import flash.system.*;import flash.desktop.NativeApplication;import flash.filesystem.*;import flash.geom.*;import flash.utils.*;
public class AOTCatalogProbe extends Sprite {
private var packaged:Object={};private var rows:Array, index:int=0, original:Loader, candidate:Loader, seen:Object={};
public function AOTCatalogProbe(){var f:FileStream=new FileStream();f.open(File.applicationDirectory.resolvePath("cases.json"),FileMode.READ);rows=JSON.parse(f.readUTFBytes(f.bytesAvailable)) as Array;f.close();for each(var row:Object in rows)packaged[row.path]={file:row.candidate,blocked:false};var invalid:PackagedDisplayLoader=new PackagedDisplayLoader(packaged);var rejected:int=0;try{invalid.loadAsset("not-in-build.swf");}catch(e:Error){rejected++;}try{invalid.load(new URLRequest("https://invalid.example/asset.swf"));}catch(e:Error){rejected++;}try{invalid.loadBytes(new ByteArray());}catch(e:Error){rejected++;}if(rejected!=3)throw new Error("fail-closed gates");setTimeout(function():void{trace("CATALOG_FAIL timeout");NativeApplication.nativeApplication.exit(2);},45000);next();}
private function freeze(d:DisplayObject):void {if(d is MovieClip)MovieClip(d).gotoAndStop(1);if(d is DisplayObjectContainer){var c:DisplayObjectContainer=DisplayObjectContainer(d);for(var i:int=0;i<c.numChildren;i++)freeze(c.getChildAt(i));}}
private function pixels(d:DisplayObject):String{freeze(d);var b:Rectangle=d.getBounds(d);var w:int=Math.max(1,Math.ceil(b.width)),h:int=Math.max(1,Math.ceil(b.height));if(w>4096||h>4096)throw new Error("bounds");var bmp:BitmapData=new BitmapData(w,h,true,0);bmp.draw(d,new Matrix(1,0,0,1,-b.x,-b.y));var a:uint=2166136261,c:uint=5381;for each(var v:uint in bmp.getVector(bmp.rect)){a=(a^v)*16777619;c=((c<<5)+c)^v;}bmp.dispose();return w+"x"+h+":"+a+":"+c;}
private function load(path:String, domain:ApplicationDomain, done:Function, packagedPath:String=null):Loader {var l:Loader=packagedPath?new PackagedDisplayLoader(packaged):new Loader();l.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR,function(e:IOErrorEvent):void{trace("CATALOG_FAIL "+e.text);NativeApplication.nativeApplication.exit(3);});l.contentLoaderInfo.addEventListener(Event.COMPLETE,function(e:Event):void{freeze(l.content);done();});if(packagedPath)PackagedDisplayLoader(l).loadAsset(packagedPath);else l.load(new URLRequest(File.applicationDirectory.resolvePath(path).url),new LoaderContext(false,domain));return l;}
private function next():void {if(index==rows.length){trace("CATALOG_PASS cases="+index+" mode=packaged-url/currentDomain");NativeApplication.nativeApplication.exit(0);return;}var row:Object=rows[index];original=load(row.original,new ApplicationDomain(null),function():void{candidate=load(row.candidate,ApplicationDomain.currentDomain,compare,row.path);});}
private function compare():void {try{var a:Object=original.content,b:Object=candidate.content;var cls:Class=b["constructor"] as Class;var expected:String=pixels(original.content),actual:String=pixels(candidate.content);if(expected!=actual)throw new Error("pixels "+expected+" != "+actual);if(b.getMC()!==cls)throw new Error("getMC contract");var clone:MovieClip=new cls();if(pixels(clone)!=actual)throw new Error("clone timeline");if(seen[rows[index].privateClass])throw new Error("duplicate class");seen[rows[index].privateClass]=true;trace("CATALOG_CASE "+index+" "+rows[index].path+" pixels="+actual);original.unloadAndStop(true);candidate.unloadAndStop(true);index++;setTimeout(next,0);}catch(e:Error){trace("CATALOG_FAIL case="+index+" "+e.getStackTrace());NativeApplication.nativeApplication.exit(4);}}
}}
'''

def main():
 p=argparse.ArgumentParser();p.add_argument('--catalog',type=Path,required=True);p.add_argument('--source',type=Path,required=True);p.add_argument('--candidate',type=Path,help='Use actual AOT adapter candidate files and loader');p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.catalog=a.catalog.resolve();a.source=a.source.resolve();a.output=a.output.resolve()
 catalog=json.loads((a.catalog/'catalog.json').read_text());a.output.mkdir(parents=True,exist_ok=False);(a.output/'compiled-content').mkdir()
 chosen={}; extra=[]
 for digest,r in catalog['objects'].items():
  if 'transform' not in r or r.get('remainingCollisions'):continue
  paths=[x for x in r['paths'] if x.startswith('items/') and len(x.split('/'))==3]
  if not paths:continue
  path=paths[0];family=path.split('/')[1]
  if family not in chosen:chosen[family]=(digest,r,path)
  if path in ('items/HAT/HAT_10101.swf','items/HAT/HAT_10104.swf'):extra.append((digest,r,path))
 rows=[];selected=list(chosen.values())+extra
 with (a.source/'air-assets.pack').open('rb') as pack:
  for digest,r,path in selected:
   original='original-'+str(len(rows))+'.swf';candidate='compiled-content/'+digest+'.swf'
   pack.seek(r['offset']);data=pack.read(r['length']);assert hashlib.sha256(data).hexdigest()==digest
   (a.output/original).write_bytes(data);shutil.copy2((a.candidate or a.catalog)/'compiled-content'/(digest+'.swf'),a.output/candidate)
   rows.append(dict(path=path,original=original,candidate=candidate,privateClass=r['transform']['privateClass']))
 # Avoid selecting the same object twice across a family representative and explicit regression pair.
 unique=[];seen=set()
 for row in rows:
  if row['privateClass'] not in seen:unique.append(row);seen.add(row['privateClass'])
 rows=unique
 (a.output/'cases.json').write_text(json.dumps(rows));probe=AS
 source_paths=[Path(__file__).resolve().parents[1]/'aot']
 if a.candidate:
  source_paths += [a.candidate.resolve()/'adapter-source',a.output]
  (a.output/'TestPackagedLoader.as').write_text('package {import org.ekoloko.air.compat.template.Loader;public class TestPackagedLoader extends Loader {public function TestPackagedLoader(){super();}}}')
  index={'schema':1,'paths':{row['path']:{'file':row['candidate'],'reviewed':True,'outputSha256':hashlib.sha256((a.output/row['candidate']).read_bytes()).hexdigest(),'acceptedSourceHashes':[hashlib.sha256((a.output/row['original']).read_bytes()).hexdigest()]} for row in rows}}
  data=json.dumps(index).encode();(a.output/'aot-index.json').write_bytes(data);pin=hashlib.sha256(data).hexdigest()
  stub=a.output/'org/ekoloko/air/NativeServices.as';stub.parent.mkdir(parents=True,exist_ok=True)
  stub.write_text('''package org.ekoloko.air {import flash.events.EventDispatcher;import flash.net.URLRequest;import flash.utils.ByteArray;import org.ekoloko.air.aot.PackagedAssetIndex;public final class NativeServices {public static var assetGeneration:uint=1;public static var assetLoadsSuspended:Boolean=false;public static var events:EventDispatcher=new EventDispatcher();private static var index:PackagedAssetIndex=new PackagedAssetIndex("'''+pin+'''");public static function planAsset(path:String):Object{return {kind:"installed",path:path};}public static function packagedURL(path:String):String{return index.url(path);}public static function packagedURLForBytes(bytes:ByteArray):String{return index.urlForBytes(bytes);}public static function parameters(url:String):Object{return {};}public static function isSwf(bytes:ByteArray):Boolean{return bytes.length>3&&bytes[1]==87&&bytes[2]==83;}public static function isRaster(bytes:ByteArray):Boolean{return false;}public static function request(request:URLRequest):URLRequest{throw new Error("TEST_NETWORK_FORBIDDEN");}public static function assetFailure(url:String,error:Error,status:int):void{throw error;}}}''')
  probe=probe.replace('import org.ekoloko.air.aot.PackagedDisplayLoader;','import org.ekoloko.air.aot.PackagedDisplayLoader;import org.ekoloko.air.NativeServices;')
  probe=probe.replace('public function AOTCatalogProbe(){','public function AOTCatalogProbe(){NativeServices;var denied:int=0;try{NativeServices.packagedURL("not-in-build.swf");}catch(rejectPath:Error){denied++;}try{NativeServices.packagedURLForBytes(new ByteArray());}catch(rejectBytes:Error){denied++;}if(denied!=2)throw new Error("actual AOT index gates");')
  probe=probe.replace('packagedPath?new PackagedDisplayLoader(packaged):new Loader()','packagedPath?new TestPackagedLoader():new Loader()')
  probe=probe.replace('if(packagedPath)PackagedDisplayLoader(l).loadAsset(packagedPath);','if(packagedPath){if(index%2==0)l.load(new URLRequest(packagedPath));else {var f:FileStream=new FileStream(),bytes:ByteArray=new ByteArray();f.open(File.applicationDirectory.resolvePath(rows[index].original),FileMode.READ);f.readBytes(bytes);f.close();l.loadBytes(bytes);}}')
 (a.output/'AOTCatalogProbe.as').write_text(probe)
 (a.output/'application.xml').write_text('<application xmlns="http://ns.adobe.com/air/application/51.4"><id>org.ekoloko.aotcatalogprobe.'+hashlib.sha256(str(a.output).encode()).hexdigest()[:12]+'</id><versionNumber>0.1.0</versionNumber><filename>AOTCatalogProbe</filename><initialWindow><content>AOTCatalogProbe.swf</content><visible>false</visible></initialWindow><supportedProfiles>extendedDesktop</supportedProfiles></application>')
 sdk=Path('/Volumes/T9/AIR/sdks/AIRSDK_51.4.1');env=dict(os.environ,JAVA_HOME='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home')
 subprocess.run([str(sdk/'bin/amxmlc'),'-debug=true','-omit-trace-statements=false',*['-source-path+='+str(path) for path in source_paths],'-output='+str(a.output/'AOTCatalogProbe.swf'),str(a.output/'AOTCatalogProbe.as')],env=env,check=True)
 r=subprocess.run([str(sdk/'bin/adl'),str(a.output/'application.xml'),str(a.output)],env=env,capture_output=True,text=True,timeout=60)
 (a.output/'result.log').write_text(r.stdout+r.stderr);print(r.stdout+r.stderr)
 assert r.returncode==0 and 'CATALOG_PASS' in (r.stdout+r.stderr), 'ADL exit '+str(r.returncode)
 (a.output/'receipt.json').write_text(json.dumps(dict(cases=len(rows),runtime='desktop AIR ADL',packagedURL=True,currentDomain=True,pixelAndCloneParity=True,actualAOTAdapter=bool(a.candidate),phoneTested=False,aotRuntimeTested=False),indent=2)+'\n')
if __name__=='__main__':main()
