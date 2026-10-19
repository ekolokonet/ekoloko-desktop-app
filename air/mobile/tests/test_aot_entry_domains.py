"""Validate entry siblings and Main after private-class isolation, without login/network.

This is actual desktop AIR runtime parity, not iOS AOT acceptance.
"""
import argparse,hashlib,json,os,shutil,subprocess,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from prepare_aot_private_globals import isolate_globals

# Reviewed exclusively as reflected CheckBox class values in exact Main152 Login.
LOGIN_SOURCE_SHA='7b16bc9c9ca952bbc7a12ea5021d45cefcf91bae9ef9f90f795543775bc4f854'
SKINS={'CheckBox_upIcon','CheckBox_downIcon','CheckBox_overIcon','CheckBox_disabledIcon','CheckBox_selectedDisabledIcon','CheckBox_selectedUpIcon','CheckBox_selectedDownIcon','CheckBox_selectedOverIcon'}

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--catalog',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.catalog=a.catalog.resolve();a.output=a.output.resolve();a.output.mkdir(parents=True,exist_ok=False)
 cat=json.loads((a.catalog/'catalog.json').read_text());plan=json.loads((a.catalog/'scope-plan.json').read_text());rows={path:(digest,r) for digest,r in cat['objects'].items() for path in r['paths']};receipts={};config={}
 for folder in ['original','prepared']:(a.output/folder).mkdir()
 paths={'shell':'shell.swf','login':'website/iw/login_iw.swf','selector':'website/common/server_selector/serverSelector.swf','main':'main.swf'}
 for role,path in paths.items():
  digest,row=rows[path];data=(a.catalog/'compiled-content'/(digest+'.swf')).read_bytes();(a.output/'original'/(role+'.swf')).write_bytes(data)
  if role in {'login','selector'}:
   classes=set(plan['objects'][digest]['privateClasses']);classes.discard('focusRectSkin')
   if role=='login' and hashlib.sha256(data).hexdigest()!=LOGIN_SOURCE_SHA:raise ValueError('Login reflection review is not valid for these source bytes')
   data,receipt=isolate_globals(data,class_names=classes,reflection_review={LOGIN_SOURCE_SHA:SKINS} if role=='login' else None);receipts[role]=receipt
  (a.output/'prepared'/(role+'.swf')).write_bytes(data)
 config['loginMapping']=receipts['login']['classes'];config['mainOnly']=plan['objects'][rows[paths['login']][0]]['mainOnlyEarlyDefinitions'];config['shared']=sorted({c['name'] for c in rows['main.swf'][1]['classes'] if c['namespaceKind']==22}&{c['name'] for c in rows['shell.swf'][1]['classes'] if c['namespaceKind']==22}-{'Adapters'})
 (a.output/'entry.json').write_text(json.dumps(config));(a.output/'transforms.json').write_text(json.dumps(receipts,indent=2));source=Path(__file__).resolve().parent;shutil.copy2(source/'aot-entry/EntryDomainProbe.as',a.output);shutil.copytree(source/'aot-core/org',a.output/'org')
 (a.output/'application.xml').write_text('<application xmlns="http://ns.adobe.com/air/application/51.4"><id>org.ekoloko.aotentryprobe</id><versionNumber>0.1.0</versionNumber><filename>EntryDomainProbe</filename><initialWindow><content>EntryDomainProbe.swf</content><visible>false</visible></initialWindow><supportedProfiles>extendedDesktop</supportedProfiles></application>')
 sdk=Path('/Volumes/T9/AIR/sdks/AIRSDK_51.4.1');env=dict(os.environ,JAVA_HOME='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home')
 subprocess.run([str(sdk/'bin/amxmlc'),'-debug=true','-omit-trace-statements=false','-source-path+='+str(a.output),'-output='+str(a.output/'EntryDomainProbe.swf'),str(a.output/'EntryDomainProbe.as')],env=env,check=True)
 r=subprocess.run([str(sdk/'bin/adl'),str(a.output/'application.xml'),str(a.output)],capture_output=True,text=True,timeout=60);log=r.stdout+r.stderr;(a.output/'result.log').write_text(log);print(log)
 assert r.returncode==0 and 'ENTRY_PASS' in log
 (a.output/'receipt.json').write_text(json.dumps({'passed':True,'mainVersion':cat['mainVersion'],'mainOnlyEntryDefinitions':len(config['mainOnly']),'sharedShellClasses':len(config['shared']),'transformedClassCounts':{k:len(v['classes']) for k,v in receipts.items()},'runtime':'desktop AIR ADL','authenticatedGameplay':False,'aotRuntimeTested':False},indent=2)+'\n')
if __name__=='__main__':main()
