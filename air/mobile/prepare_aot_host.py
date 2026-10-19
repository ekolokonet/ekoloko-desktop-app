"""Stage the existing mobile host with packaged executable loading, without signing.

Only explicit runtime-review receipts enable executable entries. This never
modifies active mobile-phone sources/builds, signed release packs, or accounts.
"""
import argparse,hashlib,json,os,re,shutil,subprocess,zlib
from pathlib import Path
from run_connected import CORE,BUILD as CONNECTED


def replace_once(text,old,new):
 if text.count(old)!=1:raise ValueError('Host source drift at '+old[:80])
 return text.replace(old,new,1)

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--version-map',type=Path,required=True);p.add_argument('--content',type=Path,required=True);p.add_argument('--candidate',type=Path,required=True);p.add_argument('--reviewed-paths',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output=a.output.resolve();a.output.mkdir(parents=True,exist_ok=False)
 mobile=Path(__file__).resolve().parent;candidate=json.loads((a.candidate/'candidate.json').read_text());review=json.loads(a.reviewed_paths.read_text());manifest=zlib.decompress((a.content/'air-manifest.zlib').read_bytes());manifest=json.loads(manifest);index={'schema':1,'paths':{}};reviewed=set(review['paths']);seen=set()
 manifest_pin=hashlib.sha256((a.content/'air-manifest.zlib').read_bytes()).hexdigest()
 if candidate.get('sourceManifestSha256') != manifest_pin:raise ValueError('Candidate/content manifest mismatch')
 version_bytes=a.version_map.read_bytes()
 if not 0<len(version_bytes)<=1048576 or hashlib.sha256(version_bytes).hexdigest()!=manifest['versionConfigSha256']:raise ValueError('Version snapshot does not match content manifest')
 (a.output/'aot-files-version.xml').write_bytes(version_bytes)
 for digest,row in candidate['objects'].items():
  source=a.candidate/'compiled-content'/(digest+'.swf');data=source.read_bytes()
  if hashlib.sha256(data).hexdigest()!=row['outputSha256']:raise ValueError('Prepared asset drift '+digest)
  permitted=bool(set(row['paths'])&reviewed)
  if permitted and (row['state'].startswith('blocked') or row['state']=='excluded-candidate'):raise ValueError('Blocked asset cannot be reviewed '+repr(row['paths']))
  if permitted:
   target=a.output/'compiled-content'/(digest+'.swf');target.parent.mkdir(exist_ok=True);target.write_bytes(data);seen.update(set(row['paths'])&reviewed)
  for path in row['paths']:
   entry=manifest['assets'][path];index['paths'][path]={'file':'compiled-content/'+digest+'.swf','reviewed':path in reviewed,'outputSha256':row['outputSha256'],'acceptedSourceHashes':sorted({digest,row['sourceSha256'],entry['sha256'],entry['originalSha256']})}
 if reviewed-seen:raise ValueError('Review contains missing paths '+repr(reviewed-seen))
 index_bytes=json.dumps(index,sort_keys=True,separators=(',',':')).encode();(a.output/'aot-index.json').write_bytes(index_bytes);index_pin=hashlib.sha256(index_bytes).hexdigest()
 for name in ['air-assets.pack','air-manifest.zlib','bootstrap-shell.swf']:shutil.copyfile(a.content/name,a.output/name)
 stage=a.output/'host-source';stage.mkdir()
 # Merge overlays deterministically and resolve Embed paths against each source.
 # Multiple source roots with duplicate classes otherwise make selection unclear.
 for root in [CORE/'air/src',mobile/'src',mobile/'connected',mobile/'aot']:
  for path in root.rglob('*.as'):
   if path.name.startswith('._'):continue
   target=stage/path.relative_to(root);target.parent.mkdir(parents=True,exist_ok=True);code=path.read_text()
   def embedded(match):
    value=match.group(1);asset=(path.parent/value).resolve()
    return 'source="'+str(asset)+'"' if asset.exists() else match.group(0)
   code=re.sub(r'''source=["']([^"'\n]+)["']''',embedded,code);target.write_text(code)
 native=stage/'org/ekoloko/air/NativeServices.as';code=native.read_text();code=replace_once(code,'public final class NativeServices {','''public final class NativeServices {
        public static function pinnedVersionMap(done:Function):void {
            done(PinnedVersionMap.read(BuildInfo.AOT_VERSION_SHA256));
        }
        private static var packagedIndex:org.ekoloko.air.aot.PackagedAssetIndex;
        public static function packagedURL(path:String):String {
            if(assetLoadsSuspended)throw new Error("client_stopped");
            if(!packagedIndex)packagedIndex=new org.ekoloko.air.aot.PackagedAssetIndex(BuildInfo.AOT_INDEX_SHA256);
            return packagedIndex.url(path);
        }
        public static function packagedURLForBytes(bytes:ByteArray):String {
            if(assetLoadsSuspended)throw new Error("client_stopped");
            if(!packagedIndex)packagedIndex=new org.ekoloko.air.aot.PackagedAssetIndex(BuildInfo.AOT_INDEX_SHA256);
            return packagedIndex.urlForBytes(bytes);
        }''');code=replace_once(code,'public static function optionalAssetPath(path:String):Boolean {','''public static function optionalAssetPath(path:String):Boolean {
            // Exact optional Hebrew banner presentation paths. Index denial still
            // reaches Loader's real asynchronous IOError; never execute denied bytes.
            if (["/ekoloko/website/iw/banners/banner_1_heb.swf","/ekoloko/website/iw/banners/banner_2_heb.swf","/ekoloko/website/iw/banners/banner_3_heb.swf","/ekoloko/website/iw/banners/banner_5_heb.swf","/ekoloko/website/iw/banners/preloader_2014_purim.swf"].indexOf(path)>=0) return true;''');code=replace_once(code,'releases = online;','if(online)throw new Error("aot_remote_code_store_forbidden");\n            releases = null;');code=replace_once(code,'public final class NativeServices {','import org.ekoloko.air.aot.PackagedAssetIndex;\n    import org.ekoloko.air.aot.PinnedVersionMap;\n    public final class NativeServices {');code=code.replace('org.ekoloko.air.aot.PackagedAssetIndex;', 'PackagedAssetIndex;').replace('new org.ekoloko.air.aot.PackagedAssetIndex(', 'new PackagedAssetIndex(');code=code.replace('import PackagedAssetIndex;', 'import org.ekoloko.air.aot.PackagedAssetIndex;');code=replace_once(code,'var req:URLRequest = new URLRequest(resolve(original.url));','''var resolved:String=resolve(original.url);
            if(PinnedVersionMap.matches(resolved,BuildInfo.ORIGIN)) {
                if(original.method!="GET" || original.data!=null)throw new Error("aot_version_request");
                return new URLRequest(PinnedVersionMap.url(BuildInfo.AOT_VERSION_SHA256));
            }
            var req:URLRequest = new URLRequest(resolved);''');native.write_text(code)
 host=stage/'EkolokoAIR.as';code=host.read_text();begin=code.index('                if(BuildInfo.PACKED_REVIEW){');end=code.index('                initialized = true;',begin);code=code[:begin]+'''                // Executable catalog is fixed by the compiled binary. Data/API
                // requests keep their existing origin and authentication checks.
                NativeServices.initialize();
'''+code[end:];code=replace_once(code,'new LoaderContext(false, new ApplicationDomain(ApplicationDomain.currentDomain))','new LoaderContext(false, ApplicationDomain.currentDomain)');code=replace_once(code,'''                NativeServices.loadAsset("shell.swf",function(bytes:ByteArray):void {
                    if (current == generation) game.loadBytes(bytes,context);
                },function(error:Error):void {if(current == generation) fail("shell_load_error");});''','''                game.load(new URLRequest(NativeServices.packagedURL("shell.swf")),context);''');code=replace_once(code,'fetch("/ekoloko/conf/files_version.xml", function(bytes:ByteArray):void {','NativeServices.pinnedVersionMap(function(bytes:ByteArray):void {');code=replace_once(code,'}, true);','});');host.write_text(code)
 generated=a.output/'generated/org/ekoloko/air/BuildInfo.as';generated.parent.mkdir(parents=True);info=(CONNECTED/'generated/org/ekoloko/air/BuildInfo.as').read_text();info=re.sub(r'MANIFEST_SHA256:String="[0-9a-f]{64}"','MANIFEST_SHA256:String="'+hashlib.sha256((a.content/'air-manifest.zlib').read_bytes()).hexdigest()+'"',info);info=replace_once(info,'public final class BuildInfo {','public final class BuildInfo { public static const AOT_VERSION_SHA256:String=\"'+manifest['versionConfigSha256']+'\"; public static const AOT_INDEX_SHA256:String="'+index_pin+'";');generated.write_text(info);shutil.copyfile(generated,stage/'org/ekoloko/air/BuildInfo.as')
 sdk=Path('/Volumes/T9/AIR/sdks/AIRSDK_51.4.1');env=dict(os.environ,JAVA_HOME='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home')
 subprocess.run([str(sdk/'bin/amxmlc'),'-debug=true','-omit-trace-statements=false','-define=CONFIG::desktop,false','-define=CONFIG::mobile,true','-external-library-path+='+str(CORE/'private-motion/Shutter.swc'),'-source-path+='+str(stage),'-output='+str(a.output/'EkolokoAIR.swf'),str(host)],env=env,check=True)
 xml=(mobile/'application.xml').read_text().replace('org.ekoloko.mobilelab','org.ekoloko.mobilephone').replace('MobileLab.swf','EkolokoAIR.swf').replace('application/51.3','application/51.4');(a.output/'application.xml').write_text(xml)
 (a.output/'receipt.json').write_text(json.dumps({'compiled':True,'versionMapSha256':manifest['versionConfigSha256'],'candidateManifestSha256':manifest_pin,'indexSha256':index_pin,'executablePathsEnabled':len(reviewed),'reviewEvidence':review.get('evidence',[]),'interpreterSourceChanged':False,'signed':False,'runtimeTested':False,'appStoreReady':False,'limitation':'Only explicitly reviewed executable paths enabled. Host and game use the identical build-pinned version snapshot; future new AS3 requires a new binary.'},indent=2)+'\n');print('AOT_HOST_STAGED reviewedPaths='+str(len(reviewed)))
if __name__=='__main__':main()
