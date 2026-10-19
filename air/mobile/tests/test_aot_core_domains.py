"""Actual Main/Shell parent-domain versus packaged shared-domain contract check.

Deliberately does not attach Shell to stage or initialize authentication/network.
The test-only NativeServices stub is excluded from all game host source paths.
"""
import argparse,json,os,shutil,subprocess
from pathlib import Path

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--catalog',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.catalog=a.catalog.resolve();a.output=a.output.resolve();a.output.mkdir(parents=True,exist_ok=False)
 catalog=json.loads((a.catalog/'catalog.json').read_text());rows={path:(digest,r) for digest,r in catalog['objects'].items() for path in r['paths']}
 common={c['name'] for c in rows['main.swf'][1]['classes'] if c['namespaceKind']==22}&{c['name'] for c in rows['shell.swf'][1]['classes'] if c['namespaceKind']==22};common.discard('Adapters')
 (a.output/'classes.json').write_text(json.dumps(sorted(common)))
 for name in ['main.swf','shell.swf']:shutil.copy2(a.catalog/'compiled-content'/(rows[name][0]+'.swf'),a.output/name)
 source=Path(__file__).resolve().parent/'aot-core';shutil.copytree(source,a.output,dirs_exist_ok=True)
 (a.output/'application.xml').write_text('<application xmlns="http://ns.adobe.com/air/application/51.4"><id>org.ekoloko.aotcoreprobe</id><versionNumber>0.1.0</versionNumber><filename>CoreDomainProbe</filename><initialWindow><content>CoreDomainProbe.swf</content><visible>false</visible></initialWindow><supportedProfiles>extendedDesktop</supportedProfiles></application>')
 sdk=Path('/Volumes/T9/AIR/sdks/AIRSDK_51.4.1');env=dict(os.environ,JAVA_HOME='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home')
 subprocess.run([str(sdk/'bin/amxmlc'),'-debug=true','-omit-trace-statements=false','-source-path+='+str(a.output),'-output='+str(a.output/'CoreDomainProbe.swf'),str(a.output/'CoreDomainProbe.as')],env=env,check=True)
 r=subprocess.run([str(sdk/'bin/adl'),str(a.output/'application.xml'),str(a.output)],capture_output=True,text=True,timeout=60);log=r.stdout+r.stderr;(a.output/'result.log').write_text(log);print(log)
 assert r.returncode==0 and 'CORE_PASS' in log
 (a.output/'receipt.json').write_text(json.dumps({'mainVersion':catalog['mainVersion'],'sharedPublicClasses':len(common),'shellAuthorityPreserved':True,'primitiveConstantParity':True,'runtime':'desktop AIR ADL','authenticatedGameplay':False,'aotRuntimeTested':False},indent=2)+'\n')
if __name__=='__main__':main()
