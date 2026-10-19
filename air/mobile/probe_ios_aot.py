"""Isolated development-signing AOT probe; never uploads or installs anything.

This deliberately packages extracted shell/main/house SWFs as explicit inputs to
ADT. A compiler success only validates this subset, not runtime compatibility.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import time


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--audit',type=Path,required=True)
    parser.add_argument('--profile',type=Path,required=True)
    parser.add_argument('--certificate',type=Path,required=True)
    parser.add_argument('--password-file',type=Path,required=True)
    parser.add_argument('--sdk',type=Path,default=Path('/Volumes/T9/AIR/sdks/AIRSDK_51.4.1'))
    parser.add_argument('--timeout',type=int,default=300)
    parser.add_argument('--all',action='store_true',help='Compile every unique extracted SWF, still no runtime/install claim')
    args=parser.parse_args()
    source=args.source.resolve(); audit=json.loads(args.audit.read_text())
    profile=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',str(args.profile)]))
    ent=profile['Entitlements']
    if ent.get('get-task-allow') is not True or not ent['application-identifier'].endswith('.org.ekoloko.mobilephone'):
        raise SystemExit('A matching development profile is required for the compile probe.')
    if profile['ExpirationDate'] <= datetime.datetime.utcnow():
        raise SystemExit('Development profile expired.')
    stage=args.audit.resolve().parent/('aot-full-probe' if args.all else 'aot-probe')
    stage.mkdir(exist_ok=False)
    for name in ('EkolokoAIR.swf','application.xml','bootstrap-shell.swf'):
        shutil.copy2(source/name,stage/name)
    shutil.copytree(source/'icons',stage/'icons')
    selected=[entry['paths'][0] for entry in audit['objects'].values() if entry['kind']=='swf'] if args.all else ['shell.swf','main.swf','main_components/house.swf']
    path_index={path:(digest,entry) for digest,entry in audit['objects'].items() for path in entry['paths']}
    inputs=[]
    for path in selected:
        digest,entry=path_index[path]
        data=Path(entry['extractedPath']).read_bytes()
        if hashlib.sha256(data).hexdigest()!=digest: raise SystemExit('Extracted SWF mismatch')
        target=stage/'compiled-content'/path
        target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
        inputs.append(str(target.relative_to(stage)))
    password=args.password_file.read_text().strip()
    platform=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip()
    env=dict(os.environ,JAVA_HOME='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home')
    command=[str(args.sdk/'bin/adt'),'-package','-target','ipa-test','-storetype','pkcs12',
       '-keystore',str(args.certificate),'-storepass',password,'-provisioning-profile',str(args.profile),
       'Ekoloko-AOT-Probe.ipa','application.xml','-platformsdk',platform,
       'EkolokoAIR.swf','bootstrap-shell.swf','icons','compiled-content']
    started=time.monotonic()
    timed_out=False
    process=subprocess.Popen(command,cwd=stage,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
    try:
        stdout,stderr=process.communicate(timeout=args.timeout)
    except subprocess.TimeoutExpired:
        timed_out=True
        os.killpg(process.pid,signal.SIGTERM)
        try: stdout,stderr=process.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid,signal.SIGKILL)
            stdout,stderr=process.communicate()
    output=stdout+stderr;code=process.returncode
    output=output.replace(password,'[redacted]') if password else output
    (stage/'compile.log').write_text(output)
    report={'target':'ipa-test','interpreter':False,'codeSWFCount':len(selected),'fullExplicitSWFSet':args.all,'codeSWFSubset':selected if not args.all else None,'returnCode':code,
       'seconds':round(time.monotonic()-started,2),'timedOut':timed_out,'appStoreReady':False,
       'runtimeTested':False,'reason':'Compile-only probe; complete runtime assets, loader adaptation and gameplay deliberately not claimed.'}
    (stage/'receipt.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2));print(output[-12000:])

if __name__=='__main__':main()
