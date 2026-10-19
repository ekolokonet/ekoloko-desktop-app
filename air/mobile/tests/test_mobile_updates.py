"""Actual AIR signed mobile update flow; no network, credentials, or game actions."""
from pathlib import Path
import hashlib,json,os,subprocess,tempfile,copy
ROOT=Path(__file__).resolve().parents[1]
CORE=Path('/Users/ransaymour/Documents/Codex/2026-10-09/task-6/air-candidate/air-unified')
SDK=Path('/Volumes/T9/AIR/sdks/AIRSDK_51.3.4')
sha=lambda b:hashlib.sha256(b).hexdigest()
with tempfile.TemporaryDirectory(prefix='mobile-updates-') as tmp:
 p=Path(tmp);key=p/'key.pem'
 subprocess.run(['openssl','genpkey','-algorithm','RSA','-pkeyopt','rsa_keygen_bits:2048','-out',str(key)],check=True,capture_output=True)
 modulus=subprocess.check_output(['openssl','rsa','-in',str(key),'-noout','-modulus'],stderr=subprocess.DEVNULL).decode().strip().split('=')[1].lower()
 old=b'FWS old bundled fixture';new=b'FWS changed downloaded fixture';(p/'old.bin').write_bytes(old);(p/'new.bin').write_bytes(new)
 asset=lambda b:dict(sha256=sha(b),originalSha256=sha(b),length=len(b))
 m=dict(schema=1,hostProtocol=1,mobileHostProtocol=1,releaseId='next',generation=2,origin='https://play.ekoloko.org',sourceCommit='1'*40,mainVersion='134',versionConfigSha256='2'*64,assetRoot='objects/',assets={'main.swf':asset(new),'shell.swf':asset(old)})
 for name in ['next','desktop','rollback','bad','alias','newcode','corechange','oldercore']:
  v=copy.deepcopy(m);v['releaseId']=name
  if name in ('alias','newcode','corechange','oldercore'):
   v['generation']=3
   v['assets']['images/addition.swf']=asset(new)
   if name=='newcode':v['assets']['images/addition.swf']=asset(b'FWS unknown executable fixture')
   if name=='corechange':v['assets']['shell.swf']=asset(new)
   if name=='oldercore':v['mainVersion']='135';v['generation']=2026101203
  if name=='bad':v['generation']=3
  if name=='desktop':v.pop('mobileHostProtocol');v['generation']=3
  if name=='rollback':v['generation']=1
  raw=json.dumps(v,sort_keys=True,separators=(',',':')).encode();(p/(name+'.json')).write_bytes(raw)
  subprocess.run(['openssl','dgst','-sha256','-sign',str(key),'-out',str(p/(name+'.sig')),str(p/(name+'.json'))],check=True,capture_output=True)
  if name=='bad':(p/(name+'.sig')).write_bytes(b'0'*256)
  (p/(name+'.pointer.json')).write_text(json.dumps(dict(schema=1,releaseId=name,generation=v['generation'],manifest='releases/'+name+'/manifest.json',signature='releases/'+name+'/manifest.sig',manifestSha256=sha(raw))))
 initial=copy.deepcopy(m);initial.update(mainVersion='130',generation=0);initial['assets']['main.swf']=asset(old)
 (p/'config.json').write_text(json.dumps(dict(old=initial,next=m,modulus=modulus)))
 env=dict(os.environ,JAVA_HOME='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home')
 subprocess.run([str(SDK/'bin/amxmlc'),'-debug=true','-omit-trace-statements=false','-source-path+='+str(ROOT/'connected'),'-source-path+='+str(CORE/'air/src'),'-source-path+='+str(ROOT.parent/'build/mobile-connected/generated'),'-output='+str(p/'test.swf'),str(ROOT/'tests/MobileReleaseTests.as')],env=env,check=True)
 (p/'app.xml').write_text('<application xmlns="http://ns.adobe.com/air/application/51.3"><id>org.ekoloko.mobile.update.tests</id><versionNumber>1.0.0</versionNumber><filename>UpdateTests</filename><initialWindow><content>test.swf</content><visible>false</visible></initialWindow><supportedProfiles>extendedDesktop</supportedProfiles></application>')
 r=subprocess.run([str(SDK/'bin/adl'),str(p/'app.xml'),str(p)],env=env,text=True,capture_output=True,timeout=60)
 print(r.stdout[-6000:]);print(r.stderr[-1000:]);print("adl exit",r.returncode);assert r.returncode==0 and 'MOBILE_UPDATE_PASS' in (r.stdout+r.stderr)
