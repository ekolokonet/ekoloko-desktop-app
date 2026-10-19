"""Prepare an explicitly reviewed mobile release in a separate output directory.
Inputs are pinned HTTPS source snapshots and a reviewed Main merge, never live mutable files.
Does not publish, sign, modify the previous bundle, or edit server/client sources.
"""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess,sys,zlib,xml.etree.ElementTree as ET
from run_connected import CORE
sha=lambda b:hashlib.sha256(b).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--review',type=Path,required=True);p.add_argument('--base',type=Path,required=True);p.add_argument('--patch-directory',type=Path,help='Reviewed native patch sources when the base is a prepared bundle');p.add_argument('--shell-patch-directory',type=Path,help='Reviewed native shell patch sources, required when shell bytes change');p.add_argument('--version-map',type=Path,required=True);p.add_argument('--source-ref',required=True);a=p.parse_args()
 review=a.review.resolve();out=review/'prepared';out.mkdir(exist_ok=True)
 sources=json.loads((review/'review-sources.json').read_text());old=json.loads(zlib.decompress((a.base/'air-manifest.zlib').read_bytes()));oldreceipt=json.loads((a.base/'content-receipt.json').read_text())
 assert sha((a.base/'air-assets.pack').read_bytes())==oldreceipt['packSha256']
 version=a.version_map.read_bytes();main_version=ET.fromstring(version).findtext('main_version').strip()
 patches=review/'patch-main';shutil.copytree(a.patch_directory or a.base/'patch-main',patches,dirs_exist_ok=True)
 merged=(review/'merged-main.as').read_text();assert '<<<<<<<' not in merged and '§§goto' not in merged
 (patches/'com/vtweens/shell/Main.as').write_text(merged)
 java='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home/bin/java';ffdec='/Applications/FFDec.app/Contents/Resources/ffdec.jar'
 sys.path.insert(0,str(CORE/'resources'));from swf import adapt_swf
 replacements={};records={}
 for path,pin in sources.items():
  assert not path.startswith('/') and '..' not in Path(path).parts and path.endswith('.swf')
  raw=(review/'sources'/path).read_bytes();assert sha(raw)==pin['sha256'] and len(raw)==pin['length']
  if path in old['assets'] and old['assets'][path]['originalSha256']==pin['sha256']:continue
  b=raw
  if path in ('main.swf','shell.swf'):
   part=path[:-4];patch_source=patches if part=='main' else a.shell_patch_directory
   if patch_source is None:raise ValueError('Changed shell requires explicitly reviewed native shell patch sources')
   dest=review/(part+'-native.swf')
   with (review/('import-'+part+'.log')).open('w') as log:subprocess.run([java,'-Xmx2g','-jar',ffdec,'-onerror','abort','-importScript',str(review/'sources'/path),str(dest),str(patch_source.resolve())],check=True,stdout=log,stderr=subprocess.STDOUT)
   b=dest.read_bytes()
  b,calls=adapt_swf(b,(CORE/'resources/adapters.swf').read_bytes(),'org.ekoloko.air.compat.a'+pin['sha256'][:24])
  replacements[path]=b;records[path]=dict(sourceSha256=pin['sha256'],adaptedSha256=sha(b),adaptedCalls=calls)
 # Replace aliases of the same source object as well as its canonical path.
 for path,b in list(replacements.items()):
  previous=old['assets'].get(path)
  if previous:
   for alias,e in old['assets'].items():
    if e['originalSha256']==previous['originalSha256']:replacements[alias]=b;records[alias]=records[path]
 for path in replacements:
  if path not in old['assets']:old['assets'][path]={}
 seen={};retained=0
 with (a.base/'air-assets.pack').open('rb') as original,(out/'air-assets.pack').open('wb') as pack:
  for path,e in old['assets'].items():
   if path in replacements:b=replacements[path];e['originalSha256']=records[path]['sourceSha256']
   else:
    original.seek(e['offset']);b=original.read(e['length']);assert sha(b)==e['sha256'];retained+=1
   h=sha(b)
   if h not in seen:seen[h]=(pack.tell(),len(b));pack.write(b)
   e['offset'],e['length']=seen[h];e['sha256']=h
  old['packSize']=pack.tell()
 old.update(mainVersion=main_version,versionConfigSha256=sha(version),sourceCommit=a.source_ref)
 manifest=zlib.compress(json.dumps(old,sort_keys=True,separators=(',',':')).encode(),9);(out/'air-manifest.zlib').write_bytes(manifest)
 if 'shell.swf' in replacements:(out/'bootstrap-shell.swf').write_bytes(replacements['shell.swf'])
 else:shutil.copyfile(a.base/'bootstrap-shell.swf',out/'bootstrap-shell.swf')
 (out/'content-receipt.json').write_text(json.dumps(dict(sourceCommit=a.source_ref,source='Reviewed live HTTPS snapshot; Git ref is comparison baseline, not a claim of byte identity',liveSourcePins=sources,mainVersion=main_version,versionMapSha256=sha(version),manifestSha256=sha(manifest),packSha256=sha((out/'air-assets.pack').read_bytes()),assets=records,retainedAssetsVerified=retained,mainMergeSha256=sha(merged.encode()),published=False),indent=2)+'\n')
 print('MOBILE_CONTENT_READY main='+main_version+' replaced='+str(len(replacements))+' retained='+str(retained))
if __name__=='__main__':main()
