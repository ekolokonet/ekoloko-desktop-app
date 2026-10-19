"""Validate a narrowed canonical module candidate with its original ancestor scope.

Only a prototype: retained global names require a final single-owner catalog.
"""
import argparse,json,os,shutil,subprocess,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from prepare_aot_private_globals import isolate_globals

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--catalog',type=Path,required=True);p.add_argument('--path',required=True);p.add_argument('--retain',action='append',default=[]);p.add_argument('--adapter-template',type=Path);p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.catalog=a.catalog.resolve();a.output=a.output.resolve();a.output.mkdir(parents=True,exist_ok=False)
 cat=json.loads((a.catalog/'catalog.json').read_text());plan=json.loads((a.catalog/'scope-plan.json').read_text());rows={path:(digest,r) for digest,r in cat['objects'].items() for path in r['paths']}
 for folder in ['original','prepared']:(a.output/folder).mkdir()
 for role,path in {'shell':'shell.swf','main':'main.swf','module':a.path}.items():
  digest,row=rows[path];data=(a.catalog/'compiled-content'/(digest+'.swf')).read_bytes();(a.output/'original'/(role+'.swf')).write_bytes(data)
  if role=='module':
   names=set(plan['objects'][digest]['privateClasses'])-set(a.retain);data,receipt=isolate_globals(data,class_names=names);(a.output/'transform.json').write_text(json.dumps(receipt,indent=2))
  if a.adapter_template:
   from prepare_aot_adapter import replace_adapter
   data,_=replace_adapter(data,a.adapter_template.read_bytes())
  (a.output/'prepared'/(role+'.swf')).write_bytes(data)
 config={'path':a.path,'retained':a.retain,'ancestorClasses':[n for n in plan['objects'][rows[a.path][0]]['preserveAncestorClasses'] if not n.startswith('Adapters')]};(a.output/'module.json').write_text(json.dumps(config));source=Path(__file__).resolve().parent;shutil.copy2(source/'aot-module/ModuleDomainProbe.as',a.output);shutil.copytree(source/'aot-core/org',a.output/'org')
 (a.output/'application.xml').write_text('<application xmlns="http://ns.adobe.com/air/application/51.4"><id>org.ekoloko.aotmoduleprobe</id><versionNumber>0.1.0</versionNumber><filename>ModuleDomainProbe</filename><initialWindow><content>ModuleDomainProbe.swf</content><visible>false</visible></initialWindow><supportedProfiles>extendedDesktop</supportedProfiles></application>')
 sdk=Path('/Volumes/T9/AIR/sdks/AIRSDK_51.4.1');env=dict(os.environ,JAVA_HOME='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home')
 subprocess.run([str(sdk/'bin/amxmlc'),'-debug=true','-omit-trace-statements=false','-source-path+='+str(a.output),'-output='+str(a.output/'ModuleDomainProbe.swf'),str(a.output/'ModuleDomainProbe.as')],env=env,check=True)
 r=subprocess.run([str(sdk/'bin/adl'),str(a.output/'application.xml'),str(a.output)],capture_output=True,text=True,timeout=60);log=r.stdout+r.stderr;(a.output/'result.log').write_text(log);print(log);assert r.returncode==0 and 'MODULE_PASS' in log
 (a.output/'receipt.json').write_text(json.dumps({'passed':True,'path':a.path,'ancestorClasses':len(config['ancestorClasses']),'retainedGlobalNames':a.retain,'requiresUniqueOwnerCatalog':True,'runtime':'desktop AIR ADL','authenticatedGameplay':False,'aotRuntimeTested':False},indent=2)+'\n')
if __name__=='__main__':main()
