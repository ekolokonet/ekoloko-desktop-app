"""Compile an isolated reviewed-content host to a development AOT IPA; never install.

A successful compile is not App Store readiness or physical runtime acceptance.
"""
import hashlib,argparse,datetime,json,os,plistlib,signal,subprocess,time
from pathlib import Path

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',type=Path,required=True);p.add_argument('--signing-directory',type=Path,required=True);p.add_argument('--timeout',type=int,default=180);a=p.parse_args();stage=a.source.resolve();sign=a.signing_directory.resolve()
 receipt=json.loads((stage/'receipt.json').read_text())
 if not receipt.get('compiled'):raise ValueError('Host compile receipt required')
 index_bytes=(stage/'aot-index.json').read_bytes()
 if hashlib.sha256(index_bytes).hexdigest()!=receipt['indexSha256']:raise ValueError('Index drift')
 if hashlib.sha256((stage/'aot-files-version.xml').read_bytes()).hexdigest()!=receipt['versionMapSha256']:raise ValueError('Version snapshot drift')
 index=json.loads(index_bytes)['paths'];files={}
 for path,row in index.items():
  if row['reviewed']:
   file=stage/row['file']
   if file.parent!=stage/'compiled-content' or file.suffix!='.swf':raise ValueError('Unsafe executable file')
   files[file]=row['outputSha256']
 for file,digest in files.items():
  if hashlib.sha256(file.read_bytes()).hexdigest()!=digest:raise ValueError('Executable drift '+file.name)
 actual={x for x in (stage/'compiled-content').glob('*.swf') if not x.name.startswith('._')}
 if actual!=set(files):raise ValueError('Unindexed executable content')
 profile=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',str(sign/'development.mobileprovision')]))
 ent=profile['Entitlements']
 if ent.get('get-task-allow') is not True or not ent['application-identifier'].endswith('.org.ekoloko.mobilephone'):raise ValueError('Matching development profile required')
 if profile['ExpirationDate']<=datetime.datetime.utcnow():raise ValueError('Expired development profile')
 if (stage/'aot-compile-receipt.json').exists():raise ValueError('Compile receipt already exists; use a new stage')
 password=(sign/'development.pass').read_text().strip();sdk=Path('/Volumes/T9/AIR/sdks/AIRSDK_51.4.1');platform=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip();env=dict(os.environ,JAVA_HOME='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home')
 command=[str(sdk/'bin/adt'),'-package','-target','ipa-test','-storetype','pkcs12','-keystore',str(sign/'development.p12'),'-storepass',password,'-provisioning-profile',str(sign/'development.mobileprovision'),'Ekoloko-AOT-Candidate.ipa','application.xml','-platformsdk',platform,'EkolokoAIR.swf','air-manifest.zlib','air-assets.pack','aot-index.json','aot-files-version.xml','bootstrap-shell.swf','compiled-content']
 started=time.monotonic();process=subprocess.Popen(command,cwd=stage,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True);timed_out=False
 try:stdout,stderr=process.communicate(timeout=a.timeout)
 except subprocess.TimeoutExpired:
  timed_out=True;os.killpg(process.pid,signal.SIGTERM)
  try:stdout,stderr=process.communicate(timeout=10)
  except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);stdout,stderr=process.communicate()
 log=(stdout+stderr).replace(password,'[redacted]');(stage/'aot-compile.log').write_text(log)
 report={'compiled':process.returncode==0 and not timed_out,'target':'ipa-test','interpreter':False,'compiledContentFiles':sum(not x.name.startswith('._') for x in (stage/'compiled-content').glob('*.swf')),'reviewedPaths':receipt['executablePathsEnabled'],'gatedPaths':sum(row['reviewed'] is not True for row in index.values()),'versionMapSha256':receipt['versionMapSha256'],'elapsedSeconds':round(time.monotonic()-started,2),'returnCode':process.returncode,'timedOut':timed_out,'installed':False,'runtimeTested':False,'appStoreReady':False,'limitation':'Native compile of explicitly reviewed catalog paths only. Gated paths remain unavailable; compilation alone is not playable or distributable release acceptance.'};(stage/'aot-compile-receipt.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));print(log[-6000:])
if __name__=='__main__':main()
