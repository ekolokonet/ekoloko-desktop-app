import sys,json,hashlib,subprocess,os,struct,argparse
from pathlib import Path
root=Path(__file__).resolve().parents[2];sys.path.extend([str(root/'mobile'),str(root/'scripts')])
from prepare_aot_private_globals import isolate_globals
parser=argparse.ArgumentParser(description='Exact style-value splitting and original/prepared AIR pixel parity for audited login variants')
parser.add_argument('--catalog',type=Path,required=True);parser.add_argument('--candidate',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
a=parser.parse_args()
from swf import unpack,pack,Reader
SKINS={'CheckBox_upIcon','CheckBox_downIcon','CheckBox_overIcon','CheckBox_disabledIcon','CheckBox_selectedDisabledIcon','CheckBox_selectedUpIcon','CheckBox_selectedDownIcon','CheckBox_selectedOverIcon'}
AUDITED_SOURCES={
 'website/en/login_en.swf':'afef20474440a68e65ea8496c0f8c30fbb54c7995ea80c1de5f8d78e1f767c3b',
 'website/fr/login_fr.swf':'ade742310cae46d75302860f1e58ede5f2c1086a845135acdbb94156f2245bbb',
 'website/us/login_us.swf':'b15daf865ffacf2da4c5e23047f1d5529db77579ad6a2246fc11de2c9410d03c',
}
# Source review: CheckBox.defaultStyles has exactly eight reflected class values.
# UIComponent defaultStyles repeats focusRectSkin as key/value; its other uses
# and BaseButton/CheckBox focusRectSkin literals are public style keys.
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
out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
cat=a.catalog;plan=json.loads((cat/'scope-plan.json').read_text());p=json.loads(a.candidate.read_text());config=[];reviews={}
for k,x in p['objects'].items():
 if x['paths'][0] not in ['website/en/login_en.swf','website/fr/login_fr.swf','website/us/login_us.swf']:continue
 data=(cat/'compiled-content'/(k+'.swf')).read_bytes();sha=hashlib.sha256(data).hexdigest();classes=set(plan['objects'][k]['privateClasses'])-set(x.get('retainedSingleOwnerClasses',[]))
 assert sha==AUDITED_SOURCES[x['paths'][0]], 'Source bytes differ from reviewed style inputs'
 prepared,r=isolate_globals(data,classes,reflection_review={sha:SKINS},style_value_review={sha:{'focusRectSkin'}});reviews[sha]=sorted(SKINS)
 for mode,content in [('original',data),('prepared',prepared)]:
  name=x['paths'][0].split('/')[1]+'-'+mode;(out/(name+'.swf')).write_bytes(no_root(content));config.append({'name':name,'mapping':r['classes'] if mode=='prepared' else {},'skins':sorted(SKINS)})
assert len(config)==6, 'Expected all three exact reviewed login assets'
(out/'config.json').write_text(json.dumps(config));(out/'reviews.json').write_text(json.dumps(reviews,indent=2))
(out/'Probe.as').write_text('''package {import flash.display.*;import flash.events.*;import flash.net.*;import flash.filesystem.*;import flash.system.*;import flash.desktop.NativeApplication;import flash.utils.*;public class Probe extends Sprite {var rows:Array;var i:int=0;var l:Loader;var reference:Array;public function Probe(){var f:FileStream=new FileStream();f.open(File.applicationDirectory.resolvePath("config.json"),FileMode.READ);rows=JSON.parse(f.readUTFBytes(f.bytesAvailable)) as Array;f.close();next();}function next():void{if(i==rows.length){trace("SKINS_PASS assets="+i);NativeApplication.nativeApplication.exit(0);return;}l=new Loader();trace("START "+rows[i].name);l.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR,function(u:UncaughtErrorEvent):void{trace("UNCAUGHT "+u.error);u.preventDefault();NativeApplication.nativeApplication.exit(1);});l.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR,function(e:IOErrorEvent):void{trace(e.text);NativeApplication.nativeApplication.exit(1);});l.contentLoaderInfo.addEventListener(Event.COMPLETE,done);l.load(new URLRequest(File.applicationDirectory.resolvePath(rows[i].name+".swf").url),new LoaderContext(false,new ApplicationDomain(ApplicationDomain.currentDomain)));}function done(e:Event):void{try{var row:Object=rows[i];var d:ApplicationDomain=l.contentLoaderInfo.applicationDomain;var pics:Array=[];var U:Class=d.getDefinition(row.mapping["fl.core.UIComponent"] || "fl.core.UIComponent") as Class;var defaults:Object=U.getStyleDefinition();if(!defaults.hasOwnProperty("focusRectSkin") || defaults.focusRectSkin!=(row.mapping.focusRectSkin || "focusRectSkin"))throw new Error("focus style key/value split");var C:Class=d.getDefinition(row.mapping["fl.controls.CheckBox"] || "fl.controls.CheckBox") as Class;var styles:Object=C.getStyleDefinition();var count:int=0;for(var key:String in styles){var val:String=String(styles[key]);for each(var old:String in row.skins){if(val==String(row.mapping[old] || old))count++;}}if(count!=8)throw new Error("skin resolution count "+count);for each(old in row.skins){var S:Class=d.getDefinition(row.mapping[old] || old) as Class;var display:DisplayObject=new S();var b:BitmapData=new BitmapData(64,64,true,0);b.draw(display);pics.push(b);}var F:Class=d.getDefinition(row.mapping.focusRectSkin || "focusRectSkin") as Class;b=new BitmapData(64,64,true,0);b.draw(new F());pics.push(b);var cb:Object=new C();addChild(cb as DisplayObject);cb.label="Parity";for(var s:int=0;s<4;s++){cb.selected=Boolean(s&1);cb.enabled=!(s&2);cb.drawNow();b=new BitmapData(120,40,true,0);b.draw(cb as DisplayObject);pics.push(b);}removeChild(cb as DisplayObject);if(i%2==0)reference=pics;else{for(s=0;s<pics.length;s++)if(BitmapData(pics[s]).compare(reference[s])!==0)throw new Error("pixel parity "+s);}trace("SKIN_CASE_PASS "+row.name+" images="+pics.length);i++;next();}catch(err:Error){trace(err.getStackTrace());NativeApplication.nativeApplication.exit(1);}}}}''')
(out/'application.xml').write_text('<application xmlns="http://ns.adobe.com/air/application/51.4"><id>org.ekoloko.skinparity</id><versionNumber>0.1.0</versionNumber><filename>Probe</filename><initialWindow><content>Probe.swf</content><visible>false</visible></initialWindow><supportedProfiles>extendedDesktop</supportedProfiles></application>')
stub=out/'org/ekoloko/air/NativeServices.as';stub.parent.mkdir(parents=True,exist_ok=True)
stub.write_text('package org.ekoloko.air {import flash.events.EventDispatcher;public final class NativeServices {public static var assetGeneration:uint=1;public static var assetLoadsSuspended:Boolean=true;public static var events:EventDispatcher=new EventDispatcher();}}')
sdk=Path('/Volumes/T9/AIR/sdks/AIRSDK_51.4.1');env=dict(os.environ,JAVA_HOME='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home')
r=subprocess.run([str(sdk/'bin/amxmlc'),'-debug=true','-source-path+='+str(out),'-includes=org.ekoloko.air.NativeServices','-omit-trace-statements=false','-output='+str(out/'Probe.swf'),str(out/'Probe.as')],env=env,capture_output=True,text=True);(out/'compile.log').write_text(r.stdout+r.stderr);assert r.returncode==0,r.stdout+r.stderr
r=subprocess.run([str(sdk/'bin/adl'),str(out/'application.xml'),str(out)],capture_output=True,text=True,timeout=45);(out/'result.log').write_text(r.stdout+r.stderr);print(r.stdout+r.stderr);assert r.returncode==0 and 'SKINS_PASS' in r.stdout+r.stderr

(out/'receipt.json').write_text(json.dumps({'passed':True,'assets':6,'pixelComparisons':39,'runtime':'desktop AIR ADL','documentAutoStartupRemoved':True,'networkAssetLoadsSuspended':True,'scope':'full canonical private-class transforms for three language variants','reflectionReview':reviews,'styleValueReview':{sha:['focusRectSkin'] for sha in reviews}},indent=2)+'\n')
