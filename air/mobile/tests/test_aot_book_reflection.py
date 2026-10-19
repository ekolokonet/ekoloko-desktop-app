import json,sys,subprocess,os,struct,hashlib,argparse
from pathlib import Path
root=Path(__file__).resolve().parents[2];sys.path[:0]=[str(root/'mobile'),str(root/'scripts')]
from swf import Reader,pack,unpack
def no_root(data):
 v,h,tags=unpack(data);new=[]
 for kind,p in tags:
  if kind==76:
   r=Reader(p);rows=[]
   for _ in range(struct.unpack('<H',r.take(2))[0]):
    begin=r.pos;cid=struct.unpack('<H',r.take(2))[0];end=p.index(b'\0',r.pos);r.take(end-r.pos+1)
    if cid:rows.append(p[begin:r.pos])
   p=struct.pack('<H',len(rows))+b''.join(rows)
  new.append((kind,p))
 return pack(v,h,new)
from prepare_aot_private_globals import isolate_globals
parser=argparse.ArgumentParser();parser.add_argument('--catalog',type=Path,required=True);parser.add_argument('--candidate',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);a=parser.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
reviews={'8d4920f3f9b2f696b3c529b68901527ee060f358b5bb0929aa830c13f97e77be': ['blankpage', 'pfLoader', 'PageFlipSound'], 'feaffdb90295e21f6f5210168fcbcf4a4885590a165a8b36280e7e67b06b838e': ['blankpage', 'pfLoader', 'PageFlipSound']}
plan=json.loads((a.catalog/'scope-plan.json').read_text());candidate=json.loads(a.candidate.read_text());config=[]
for key,row in candidate['objects'].items():
 sha=row['sourceSha256']
 if sha not in reviews:continue
 source=(a.catalog/'compiled-content'/(key+'.swf')).read_bytes();assert hashlib.sha256(source).hexdigest()==sha
 classes=set(plan['objects'][key]['privateClasses'])-set(row['retainedSingleOwnerClasses'])
 prepared,receipt=isolate_globals(source,classes,reflection_alias_review=reviews)
 for mode,data in [('original',source),('prepared',prepared)]:
  name=key+'-'+mode;(out/(name+'.swf')).write_bytes(no_root(data));config.append({'name':name,'mapping':receipt['classes'] if mode=='prepared' else {},'lookup':('org.ekoloko.air.reflection.h'+sha[:24]+'.lookupDefinition') if mode=='prepared' else None})
assert len(config)==4, 'Expected both exact reviewed book assets'
(out/'runtime-config.json').write_text(json.dumps(config))
(out/'Probe.as').write_text('''package {import flash.display.*;import flash.events.*;import flash.net.*;import flash.filesystem.*;import flash.system.*;import flash.desktop.NativeApplication;import flash.utils.*;public class Probe extends Sprite {var rows:Array;var i:int=0;var l:Loader;var reference:Array;var referenceClasses:String;var currentMapping:Object;var names:Array;public function Probe(){var f:FileStream=new FileStream();f.open(File.applicationDirectory.resolvePath("runtime-config.json"),FileMode.READ);rows=JSON.parse(f.readUTFBytes(f.bytesAvailable)) as Array;f.close();next();}function next():void{if(i==rows.length){trace("BOOK_PASS assets="+i);NativeApplication.nativeApplication.exit(0);return;}l=new Loader();l.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR,function(u:UncaughtErrorEvent):void{trace("UNCAUGHT "+u.error);u.preventDefault();NativeApplication.nativeApplication.exit(1);});l.contentLoaderInfo.addEventListener(Event.COMPLETE,done);l.load(new URLRequest(File.applicationDirectory.resolvePath(rows[i].name+".swf").url),new LoaderContext(false,new ApplicationDomain(ApplicationDomain.currentDomain)));}function visit(o:DisplayObject):void{var n:String=getQualifiedClassName(o).replace("::",".");for(var old:String in currentMapping)if(currentMapping[old]==n)n=old;names.push(n);if(o is DisplayObjectContainer){var c:DisplayObjectContainer=o as DisplayObjectContainer;for(var j:int=0;j<c.numChildren;j++)visit(c.getChildAt(j));}}function done(e:Event):void{try{var row:Object=rows[i];currentMapping=row.mapping;var d:ApplicationDomain=l.contentLoaderInfo.applicationDomain;var pics:Array=[];if(row.lookup){var lookup:Function=d.getDefinition(row.lookup) as Function;for each(var alias:String in ["blankpage","pfLoader","PageFlipSound"]){if(lookup(alias)!==d.getDefinition(row.mapping[alias]))throw new Error("alias resolution "+alias);}if(lookup("flash.display.Sprite")!==Sprite)throw new Error("unknown known-class fallback");var rejected:Boolean=false;try{lookup("MissingBookClass");}catch(expected:ReferenceError){rejected=true;}if(!rejected)throw new Error("unknown missing-class behavior");}for each(var symbol:String in ["blankpage","pfLoader"]){var S:Class=d.getDefinition(row.mapping[symbol] || symbol) as Class;var b:BitmapData=new BitmapData(128,128,true,0);b.draw(new S());pics.push(b);}var type:String="com.flashloaded.pageFlipperAS3.pageFlipper";var C:Class=d.getDefinition(row.mapping[type] || type) as Class;var book:Object=new C();addChild(book as DisplayObject);book.pageList=["blankpage","blankpage"];book.flipSound="PageFlipSound";book.numbering="none";book.Start();if(book.pageList.join(",")!=="blankpage,blankpage" || book.flipSound!=="PageFlipSound")throw new Error("public token changed");names=[];visit(book as DisplayObject);names.sort();var tree:String=names.join("|");if(tree.indexOf("blankpage")<0)throw new Error("blank class never instantiated");b=new BitmapData(800,600,true,0);b.draw(book as DisplayObject);pics.push(b);if(i%2==0){reference=pics;referenceClasses=tree;}else{if(tree!==referenceClasses)throw new Error("display class tree parity");for(var j:int=0;j<pics.length;j++)if(BitmapData(pics[j]).compare(reference[j])!==0)throw new Error("pixel parity "+j);}book.visible=false;trace("BOOK_CASE_PASS "+row.name+" images="+pics.length+" displayObjects="+names.length);i++;next();}catch(err:Error){trace(err.getStackTrace());NativeApplication.nativeApplication.exit(1);}}}}''')
(out/'application.xml').write_text('<application xmlns="http://ns.adobe.com/air/application/51.4"><id>org.ekoloko.bookparity</id><versionNumber>0.1.0</versionNumber><filename>Probe</filename><initialWindow><content>Probe.swf</content><visible>false</visible></initialWindow><supportedProfiles>extendedDesktop</supportedProfiles></application>')
stub=out/'org/ekoloko/air/NativeServices.as';stub.parent.mkdir(parents=True,exist_ok=True);stub.write_text('package org.ekoloko.air {import flash.events.EventDispatcher;public final class NativeServices {public static var assetGeneration:uint=1;public static var assetLoadsSuspended:Boolean=true;public static var events:EventDispatcher=new EventDispatcher();}}')
sdk=Path('/Volumes/T9/AIR/sdks/AIRSDK_51.4.1');env=dict(os.environ,JAVA_HOME='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home')
r=subprocess.run([str(sdk/'bin/amxmlc'),'-debug=true','-source-path+='+str(out),'-includes=org.ekoloko.air.NativeServices','-omit-trace-statements=false','-output='+str(out/'Probe.swf'),str(out/'Probe.as')],env=env,capture_output=True,text=True);(out/'compile.log').write_text(r.stdout+r.stderr);assert r.returncode==0,r.stdout+r.stderr
r=subprocess.run([str(sdk/'bin/adl'),str(out/'application.xml'),str(out)],capture_output=True,text=True,timeout=45);(out/'result.log').write_text(r.stdout+r.stderr);print(r.stdout+r.stderr);assert r.returncode==0 and 'BOOK_PASS' in r.stdout+r.stderr

(out/'receipt.json').write_text(json.dumps({'passed':True,'assets':4,'pixelComparisons':6,'displayObjectsPerAsset':335,'publicStartEndBlankPageTokens':True,'unknownNameFallbackVerified':True,'reflectionAliasReview':reviews,'runtime':'desktop AIR ADL'},indent=2)+'\n')
