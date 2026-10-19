"""Build an unpublished local diagnostic pack from the verified mobile 134 bundle.
Only replaces SmartFoxClient in its matching native Shell; never publishes a feed.
"""
from pathlib import Path
import hashlib,json,shutil,subprocess,sys,zlib
from run_connected import CORE,ROOT,BUILD
sha=lambda b:hashlib.sha256(b).hexdigest()
def main():
 base=ROOT.parent/'build/mobile-update-134/prepared'
 out=ROOT.parent/'build/mobile-socket-diagnostics'
 out.mkdir(exist_ok=True)
 receipt=json.loads((base/'content-receipt.json').read_text())
 assert sha((base/'air-assets.pack').read_bytes())==receipt['packSha256']
 assert sha((base/'air-manifest.zlib').read_bytes())==receipt['manifestSha256']
 manifest=json.loads(zlib.decompress((base/'air-manifest.zlib').read_bytes()))
 shell=manifest['assets']['shell.swf'];previous=shell['sha256']
 sys.path.insert(0,str(CORE/'resources'));from swf import adapt_swf
 native=BUILD/'current-content/shell-native.swf'
 adapters=(CORE/'resources/adapters.swf').read_bytes()
 namespace='org.ekoloko.air.compat.a'+shell['originalSha256'][:24]
 before,_=adapt_swf(native.read_bytes(),adapters,namespace)
 assert sha(before)==previous,'Native Shell no longer matches the installed reviewed base'
 patch=out/'patch/it/gotoandplay/smartfoxserver';patch.mkdir(parents=True,exist_ok=True)
 source=ROOT/'compatibility/shell/it/gotoandplay/smartfoxserver/SmartFoxClient.as'
 shutil.copyfile(source,patch/'SmartFoxClient.as')
 java='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home/bin/java'
 with (out/'import-shell.log').open('w') as log:
  subprocess.run([java,'-Xmx2g','-jar','/Applications/FFDec.app/Contents/Resources/ffdec.jar','-onerror','abort','-importScript',str(native),str(out/'shell-native.swf'),str(out/'patch')],check=True,stdout=log,stderr=subprocess.STDOUT)
 data,calls=adapt_swf((out/'shell-native.swf').read_bytes(),adapters,namespace)
 # Keep all existing offsets; append only the diagnostic replacement.
 shutil.copyfile(base/'air-assets.pack',out/'air-assets.pack')
 with (out/'air-assets.pack').open('ab') as stream:
  offset=stream.tell();stream.write(data);manifest['packSize']=stream.tell()
 for e in manifest['assets'].values():
  if e['sha256']==previous:e.update(offset=offset,length=len(data),sha256=sha(data))
 encoded=zlib.compress(json.dumps(manifest,sort_keys=True,separators=(',',':')).encode(),9)
 (out/'air-manifest.zlib').write_bytes(encoded);(out/'bootstrap-shell.swf').write_bytes(data)
 receipt.update(manifestSha256=sha(encoded),packSha256=sha((out/'air-assets.pack').read_bytes()),
  diagnosticOnly=True,published=False,diagnosticShell=dict(sourceSha256=sha(source.read_bytes()),previousSha256=previous,sha256=sha(data),adaptedCalls=calls))
 (out/'content-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
 print('MOBILE_SOCKET_DIAGNOSTIC_READY '+str(out))
if __name__=='__main__':main()
