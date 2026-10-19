"""Build a pinned local review pack from authenticated Git source and verified AIR assets.

No server writes or download-gate changes. Re-run only after reviewing changed
Main/Shell classes and replacing the explicit source/version pins below.
"""
from pathlib import Path
import hashlib, json, shutil, subprocess, sys, zlib
from run_connected import CORE, BUILD

GIT='/Users/ransaymour/.cache/codex-runtimes/codex-primary-runtime/dependencies/bin/fallback/git'
REPO='/Volumes/T9/ekoloko-rewritten-new'
COMMIT='88cd36c3a99619261fc9b7ed982b9d6febff361a'
EXPECTED={'main.swf':'81f5a3e4b19910315779778cdc587505d362f0de870ca383c3ca1585d2fbf4e8',
          'shell.swf':'c062a2ff3f56f8f6bffd2b4b52a58c5c5fbb84681d0e38f684f5c7327f06bd6e'}
MAP_SHA='3b531a67244937e695724e41b4f169d44935893e504a7d6ac5f40d2e4f119abd'
JAVA='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home/bin/java'
FFDEC='/Applications/FFDec.app/Contents/Resources/ffdec.jar'
OUT=BUILD/'current-content'
sha=lambda data:hashlib.sha256(data).hexdigest()

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    version=(Path.home()/'Library/Application Support/org.ekoloko.mobileconnected.tests/Local Store/public-source/conf/files_version.xml').read_bytes()
    assert sha(version)==MAP_SHA,'Re-review the deployed version map before refreshing'
    changed=subprocess.check_output([GIT,'-C',REPO,'diff','--name-only','c8b8943023e06c54ef7749fd496fcd87ed5b7b92..'+COMMIT,'--','ekoloko-client/ekoloko'],stderr=subprocess.DEVNULL).decode().splitlines()
    assert set(changed)=={'ekoloko-client/ekoloko/'+p for p in ['conf/files_version.xml','login.html','main.swf','shell.swf']}
    for name,digest in EXPECTED.items():
        raw=subprocess.check_output([GIT,'-C',REPO,'show',COMMIT+':ekoloko-client/ekoloko/'+name],stderr=subprocess.DEVNULL)
        assert sha(raw)==digest
        (OUT/('git-'+name)).write_bytes(raw)
    # Export the exact classes that will receive the already-reviewed AIR changes.
    def export(source,destination,classes):
        with (OUT/(destination+'.log')).open('w') as log:
            subprocess.run([JAVA,'-Xmx2g','-jar',FFDEC,'-selectclass',classes,'-export','script',str(OUT/destination),str(source)],check=True,stdout=log,stderr=subprocess.STDOUT)
    export(OUT/'git-main.swf','export-main','com.vtweens.shell.Main,com.vtweens.util.pathfinding.PathFinder')
    export(OUT/'git-shell.swf','export-shell','com.vtweens.shell.Shell,it.gotoandplay.smartfoxserver.SmartFoxClient')
    export(CORE/'air/build/main127/shell.swf','export-old-shell','com.vtweens.shell.Shell,it.gotoandplay.smartfoxserver.SmartFoxClient')
    for cls in ['com/vtweens/shell/Main.as','com/vtweens/util/pathfinding/PathFinder.as']:
        assert (OUT/'export-main/scripts'/cls).read_text()==(CORE/'air/build/main127-current/export/scripts'/cls).read_text(),cls+' changed; review before patching'
    cls='it/gotoandplay/smartfoxserver/SmartFoxClient.as'
    assert (OUT/'export-shell/scripts'/cls).read_text()==(OUT/'export-old-shell/scripts'/cls).read_text()
    patch=OUT/'patch-shell';shutil.copytree(CORE/'compatibility/shell',patch,dirs_exist_ok=True)
    # Merge current gift/house visibility changes with the small AIR lifecycle patch.
    cls='com/vtweens/shell/Shell.as'
    inputs=[OUT/'export-shell/scripts'/cls,OUT/'export-old-shell/scripts'/cls,CORE/'air/build/main127/patch-shell/Shell.as']
    normalized=[]
    for i,p in enumerate(inputs):
        target=OUT/('merge-'+str(i)+'.as');target.write_text(p.read_text());normalized.append(str(target))
    merged=subprocess.check_output([GIT,'merge-file','-p',*normalized])
    assert b'<<<<<<<' not in merged
    (patch/cls).write_bytes(merged)
    mobile_patches=Path(__file__).resolve().parent/'compatibility'
    shutil.copytree(mobile_patches/'shell',patch,dirs_exist_ok=True)
    main_patch=OUT/'patch-main'
    shutil.copytree(CORE/'compatibility/main',main_patch,dirs_exist_ok=True)
    shutil.copytree(mobile_patches/'main',main_patch,dirs_exist_ok=True)
    sys.path.insert(0,str(CORE/'resources'))
    from swf import adapt_swf
    adapted={};receipt={}
    for part in ['main','shell']:
        name=part+'.swf';native=OUT/(part+'-native.swf')
        with (OUT/('import-'+part+'.log')).open('w') as log:
            subprocess.run([JAVA,'-Xmx2g','-jar',FFDEC,'-onerror','abort','-importScript',str(OUT/('git-'+name)),str(native),str(main_patch if part=='main' else patch)],check=True,stdout=log,stderr=subprocess.STDOUT)
        data,calls=adapt_swf(native.read_bytes(),(CORE/'resources/adapters.swf').read_bytes(),'org.ekoloko.air.compat.a'+EXPECTED[name][:24])
        adapted[name]=data;receipt[name]={'sourceSha256':EXPECTED[name],'adaptedSha256':sha(data),'adaptedCalls':calls}
    manifest=json.loads(zlib.decompress((CORE/'resources/air-manifest.zlib').read_bytes()))
    selector_path='website/common/server_selector/serverSelector.swf'
    selector_pin='9cb001cf32e766b219c7673eac38c29412f7af2154cdcca56954c127e539c6ad'
    selector_entry=manifest['assets'][selector_path]
    with (CORE/'air/build/main127-current/air-assets.pack').open('rb') as old:
        old.seek(selector_entry['offset']);selector=old.read(selector_entry['length'])
    assert sha(selector)==selector_pin,'Review selector before applying presentation getters'
    (OUT/'selector-original.swf').write_bytes(selector)
    with (OUT/'import-selector.log').open('w') as log:
        subprocess.run([JAVA,'-Xmx2g','-jar',FFDEC,'-onerror','abort','-importScript',str(OUT/'selector-original.swf'),str(OUT/'selector-native.swf'),str(mobile_patches/'selector')],check=True,stdout=log,stderr=subprocess.STDOUT)
    selector=(OUT/'selector-native.swf').read_bytes()
    for path,entry in manifest['assets'].items():
        if entry['sha256']==selector_pin:adapted[path]=selector
    receipt[selector_path]={'sourceSha256':selector_pin,'adaptedSha256':sha(selector),'change':'native-slot pagination with screen-sized capacity and page metadata'}
    seen={};retained=0
    with (CORE/'air/build/main127-current/air-assets.pack').open('rb') as old,(OUT/'air-assets.pack').open('wb') as pack:
        for path,entry in manifest['assets'].items():
            if path in adapted:
                data=adapted[path]
                if path in EXPECTED:entry['originalSha256']=EXPECTED[path]
            else:
                old.seek(entry['offset']);data=old.read(entry['length']);assert sha(data)==entry['sha256'],path;retained+=1
            digest=sha(data)
            if digest not in seen:seen[digest]=(pack.tell(),len(data));pack.write(data)
            entry['offset'],entry['length']=seen[digest];entry['sha256']=digest
        manifest['packSize']=pack.tell()
    manifest.update(sourceCommit=COMMIT,mainVersion='130',versionConfigSha256=MAP_SHA)
    encoded=zlib.compress(json.dumps(manifest,sort_keys=True,separators=(',',':')).encode(),9)
    (OUT/'air-manifest.zlib').write_bytes(encoded);(OUT/'bootstrap-shell.swf').write_bytes(adapted['shell.swf'])
    (OUT/'content-receipt.json').write_text(json.dumps({'sourceCommit':COMMIT,'versionMapSha256':MAP_SHA,'manifestSha256':sha(encoded),'packSha256':sha((OUT/'air-assets.pack').read_bytes()),'assets':receipt,'retainedAssetsVerified':retained,'compatibilityPatchSha256':{str(p.relative_to(mobile_patches)):sha(p.read_bytes()) for p in sorted(mobile_patches.rglob('*.as'))},'liveBinaryHashVerified':False,'source':'authenticated Git; effective public map is 130, source XML is 128','published':False},indent=2)+'\n')
    print('CONNECTED_CONTENT_PASS retained='+str(retained)+' manifest='+sha(encoded))

if __name__=='__main__':main()
