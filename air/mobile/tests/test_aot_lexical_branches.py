import sys,json,os,subprocess,argparse
from pathlib import Path
root=Path(__file__).resolve().parents[2];sys.path[:0]=[str(root/'mobile'),str(root/'scripts')]
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args()
from prepare_aot_private_globals import isolate_globals,lexical_forward_argument_receiver
out=a.output.resolve();out.mkdir(parents=True,exist_ok=False);sdk=Path('/Volumes/T9/AIR/sdks/AIRSDK_51.4.1');env=dict(os.environ,JAVA_HOME='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home')
(out/'BGMC.as').write_text('package{public class BGMC{public var value:Number;public function BGMC(v:Number){value=v;}}}')
config=[]
for name,body in [('lexical','new BGMC(flag?12:24)'),('dynamic','new o.BGMC(flag?12:24)')]:
 (out/'Fixture.as').write_text('package{import flash.display.Sprite;public class Fixture extends Sprite{public function test(flag:Boolean,o:Object=null):*{return '+body+';}}}')
 r=subprocess.run([str(sdk/'bin/amxmlc'),'-source-path+='+str(out),'-includes=BGMC','-output='+str(out/(name+'.swf')),str(out/'Fixture.as')],env=env,capture_output=True,text=True);assert r.returncode==0,r.stdout+r.stderr
 data=(out/(name+'.swf')).read_bytes()
 try:b,report=isolate_globals(data)
 except ValueError:
  assert name=='dynamic';continue
 assert name=='lexical';(out/'prepared.swf').write_bytes(b)
 config=[{'file':name+'.swf','class':'BGMC'},{'file':'prepared.swf','class':report['classes']['BGMC']}]
assert len(config)==2
(out/'config.json').write_text(json.dumps(config))
(out/'Probe.as').write_text('''package{import flash.display.*;import flash.events.*;import flash.net.*;import flash.filesystem.*;import flash.system.*;import flash.desktop.NativeApplication;public class Probe extends Sprite{var rows:Array;var i:int=0;var l:Loader;public function Probe(){var f:FileStream=new FileStream();f.open(File.applicationDirectory.resolvePath("config.json"),FileMode.READ);rows=JSON.parse(f.readUTFBytes(f.bytesAvailable)) as Array;f.close();next();}function next():void{if(i==rows.length){trace("DIAMOND_PASS branches=4");NativeApplication.nativeApplication.exit(0);return;}l=new Loader();l.contentLoaderInfo.addEventListener(Event.COMPLETE,function(e:Event):void{try{var C:Class=l.contentLoaderInfo.applicationDomain.getDefinition(rows[i]["class"]) as Class;var a:Object=Object(l.content).test(true),b:Object=Object(l.content).test(false);if(!(a is C)||!(b is C)||a.value!=12||b.value!=24)throw new Error("branch receiver");i++;next();}catch(err:Error){trace(err.getStackTrace());NativeApplication.nativeApplication.exit(1);}});l.load(new URLRequest(File.applicationDirectory.resolvePath(rows[i].file).url),new LoaderContext(false,new ApplicationDomain(null)));}}}''')
(out/'application.xml').write_text('<application xmlns="http://ns.adobe.com/air/application/51.4"><id>org.ekoloko.diamond.regression</id><versionNumber>0.1.0</versionNumber><filename>Probe</filename><initialWindow><content>Probe.swf</content><visible>false</visible></initialWindow><supportedProfiles>extendedDesktop</supportedProfiles></application>')
r=subprocess.run([str(sdk/'bin/amxmlc'),'-debug=true','-omit-trace-statements=false','-output='+str(out/'Probe.swf'),str(out/'Probe.as')],env=env,capture_output=True,text=True);assert r.returncode==0,r.stdout+r.stderr
r=subprocess.run([str(sdk/'bin/adl'),str(out/'application.xml'),str(out)],capture_output=True,text=True,timeout=30);(out/'result.log').write_text(r.stdout+r.stderr);print(r.stdout+r.stderr);assert r.returncode==0 and 'DIAMOND_PASS' in r.stdout+r.stderr
# Unit boundary probes: no proof for loops, unknown calls, argument underflow or unequal joins.
for flow,argc,end in [([(0,0x5d,[1],1,None),(1,0x10,[],2,1)],0,2), ([(0,0x5d,[1],1,None),(1,0x46,[1,0],2,None)],0,2), ([(0,0x5d,[1],1,None),(1,0x73,[],2,None)],0,2), ([(0,0x5d,[1],1,None),(1,0x26,[],2,None),(2,0x12,[],3,4),(3,0x26,[],4,None)],0,4)]:assert not lexical_forward_argument_receiver(flow,1,argc,end,{1})
(out/'receipt.json').write_text(json.dumps({'passed':True,'runtimeBranches':4,'dynamicConstructorRejected':True,'loopUnknownCallUnderflowUnequalJoinRejected':True},indent=2))
