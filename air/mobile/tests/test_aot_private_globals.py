"""Compile real ABC fixtures to verify lexical rename and rejection boundaries."""
import argparse,hashlib,json,os,subprocess,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from prepare_aot_private_globals import isolate_globals
from prepare_aot_catalog import inspect
from swf import unpack,abc_parts

def main():
 p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output=a.output.resolve();a.output.mkdir(parents=True,exist_ok=False)
 sdk=Path('/Volumes/T9/AIR/sdks/AIRSDK_51.4.1');env=dict(os.environ,JAVA_HOME='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home')
 cases={
 'lexical':('public function test():Class{return BGMC;}','',False),
 'lexical_coercion':('public function test(o:Object):*{return BGMC(o);}','',False),
 'lexical_indexed_argument':('public function test(o:Object,k:String):*{return BGMC(o[k]);}','',False),
 'dynamic_indexed_call':('public function test(o:Object,k:String):*{return o[k].BGMC(o);}','Nonlexical class reference',True),
 'lexical_postdecrement':('private static var n:int=2;public function test():*{return new BGMC(n--);}','',False),
 'dynamic_call':('public function test(o:Object):*{return o.BGMC(o);}','Nonlexical class reference',True),
 'lexical_constructor':('public function test():*{return new BGMC();}','',False),
 'dynamic_constructor':('public function test(o:Object):*{return new o.BGMC();}','Nonlexical class reference',True),
 'dynamic_member':('public function test(o:Object):*{return o.BGMC;}','Nonlexical class reference',True),
 'member_trait':('public var BGMC:Object;','Class name also used as member trait',True),
 'reflection':('public function test():*{return flash.utils.getDefinitionByName("BGMC");}','Reflected class string',True),
 'namespace':('public function test():Class{return fixture_fla.Symbol;}','',False),
 }
 results=[]
 for name,(body,reason,reject) in cases.items():
  out=a.output/name;out.mkdir();(out/'fixture_fla').mkdir()
  (out/'BGMC.as').write_text('package {public class BGMC {public function BGMC(value:*=null){}}}')
  (out/'fixture_fla/Symbol.as').write_text('package fixture_fla {public class Symbol {public function Symbol(){}}}')
  (out/'Fixture.as').write_text('package {import flash.display.Sprite;import flash.utils.getDefinitionByName;import fixture_fla.Symbol;public class Fixture extends Sprite {'+body+'}}')
  cmd=[str(sdk/'bin/amxmlc'),'-source-path+='+str(out),'-includes=BGMC,fixture_fla.Symbol','-output='+str(out/'Fixture.swf'),str(out/'Fixture.as')]
  result=subprocess.run(cmd,env=env,text=True,capture_output=True);(out/'compile.log').write_text(result.stdout+result.stderr)
  if result.returncode:raise RuntimeError(result.stdout+result.stderr)
  source=(out/'Fixture.swf').read_bytes()
  try:
   candidate,receipt=isolate_globals(source)
   if name=='namespace':
    targeted,target_receipt=isolate_globals(source, {'fixture_fla.Symbol'})
    assert set(target_receipt['classes'])=={'fixture_fla.Symbol'}
    assert 'Fixture' in {c['name'] for c in inspect(targeted)['classes']}
   if reject:raise AssertionError('Unsafe candidate accepted '+name)
   before={c['name'] for c in inspect(source)['classes']};after={c['name'] for c in inspect(candidate)['classes']}
   assert after=={receipt['classes'].get(n,n) for n in before}
   # Shape/timeline/other SWF tags are byte-identical; only ABC and SymbolClass differ.
   bt=[t for t in unpack(source)[2] if t[0] not in (76,82)];at=[t for t in unpack(candidate)[2] if t[0] not in (76,82)];assert bt==at
   (out/'candidate.swf').write_bytes(candidate);results.append({'case':name,'accepted':True,'classes':receipt['classes']})
  except ValueError as e:
   if not reject or reason not in str(e):raise
   results.append({'case':name,'rejected':str(e)})
   if name=='reflection':
    digest=hashlib.sha256(source).hexdigest()
    candidate,receipt=isolate_globals(source, reflection_review={digest:{'BGMC'}})
    assert receipt['renamedReflectionClasses']==['BGMC']
    try:isolate_globals(source, reflection_review={'0'*64:{'BGMC'}})
    except ValueError:pass
    else:raise AssertionError('Wrong digest reflection approval accepted')
    (out/'candidate.swf').write_bytes(candidate)
    probe='package {import flash.display.*;import flash.events.*;import flash.net.*;import flash.filesystem.*;import flash.system.*;import flash.desktop.NativeApplication;import flash.utils.*;public class ReflectionProbe extends Sprite {public function ReflectionProbe(){var l:Loader=new Loader();l.contentLoaderInfo.addEventListener(Event.COMPLETE,function(e:Event):void{var cls:Class=Object(l.content).test();if(getQualifiedClassName(new cls())!="'+receipt['classes']['BGMC']+'")throw new Error("reflection target");trace("REFLECTION_PASS");NativeApplication.nativeApplication.exit(0);});l.load(new URLRequest(File.applicationDirectory.resolvePath("candidate.swf").url),new LoaderContext(false,ApplicationDomain.currentDomain));}}}'
    (out/'ReflectionProbe.as').write_text(probe)
    (out/'application.xml').write_text('<application xmlns="http://ns.adobe.com/air/application/51.4"><id>org.ekoloko.reflectionprobe</id><versionNumber>0.1.0</versionNumber><filename>ReflectionProbe</filename><initialWindow><content>ReflectionProbe.swf</content><visible>false</visible></initialWindow><supportedProfiles>extendedDesktop</supportedProfiles></application>')
    subprocess.run([str(sdk/'bin/amxmlc'),'-omit-trace-statements=false','-output='+str(out/'ReflectionProbe.swf'),str(out/'ReflectionProbe.as')],env=env,check=True,capture_output=True)
    run=subprocess.run([str(sdk/'bin/adl'),str(out/'application.xml'),str(out)],env=env,capture_output=True,text=True,timeout=20)
    (out/'runtime.log').write_text(run.stdout+run.stderr)
    assert run.returncode==0 and 'REFLECTION_PASS' in (run.stdout+run.stderr)
    results.append({'case':'digest_pinned_reflection','accepted':True,'desktopRuntime':'REFLECTION_PASS'})
 (a.output/'receipt.json').write_text(json.dumps({'cases':results,'passed':True},indent=2)+'\n');print('PRIVATE_GLOBALS_PASS cases='+str(len(results)))
if __name__=='__main__':main()
