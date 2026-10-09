"""Build unsigned Intel x64 Mac app from reviewed source and an Electron 8.2 template.

Only supplied public runtime/dependency bytes are reused. No profile or external
settings directory is read. Finder is never scripted and no app is installed.
"""
from pathlib import Path
import argparse,hashlib,json,plistlib,shutil,struct,subprocess
p=argparse.ArgumentParser()
p.add_argument('--template',type=Path,required=True)
p.add_argument('--node',required=True)
p.add_argument('--asar-module',required=True)
p.add_argument('--output',type=Path,required=True)
p.add_argument('--fixture',type=Path,required=True)
a=p.parse_args()
root=Path(__file__).resolve().parent
repo=root.parent
out=a.output.resolve()
app=out/'ekoloko.app'
if app.exists():raise RuntimeError('Refusing to overwrite existing release app')
out.mkdir(parents=True,exist_ok=True)
shutil.copytree(a.template,app,symlinks=True,ignore=shutil.ignore_patterns('._*','.DS_Store'))
stage=out/'asar-source'
stage.mkdir()
(stage/'src/main').mkdir(parents=True)
for src in sorted((root/'runtime-source').glob('*.js')):shutil.copy2(src,stage/'src/main'/src.name)
raw=(a.template/'Contents/Resources/app.asar').read_bytes()
h=json.loads(raw[16:16+struct.unpack_from('<I',raw,12)[0]])
base=8+struct.unpack_from('<I',raw,4)[0]
def extract(files,dir):
  dir.mkdir(parents=True,exist_ok=True)
  for name,e in files.items():
    dest=dir/name
    if 'files' in e:extract(e['files'],dest)
    else:
      assert not e.get('unpacked') and 'link' not in e
      start=base+int(e['offset']);dest.write_bytes(raw[start:start+e['size']])
      if e.get('executable'):dest.chmod(0o755)
extract(h['files']['node_modules']['files'],stage/'node_modules')
package=json.loads((repo/'package.json').read_text())
package.update(name='ekoloko-mac-flash34',version='1.1.1',main='src/main/index.js')
(stage/'package.json').write_text(json.dumps(package,indent=2)+'\n')
resources=app/'Contents/Resources'
subprocess.run([a.node,'-e','require(process.argv[1]).createPackage(process.argv[2],process.argv[3]).catch(e=>{console.error(e);process.exitCode=1})',a.asar_module,str(stage),str(resources/'app.asar')],check=True)
shutil.rmtree(resources/'plugins/mac34')
shutil.copytree(root/'plugins/mac34',resources/'plugins/mac34',ignore=shutil.ignore_patterns('._*','.DS_Store'))
fixture=resources/'candidate-fixture'
shutil.rmtree(fixture)
shutil.copytree(a.fixture,fixture,ignore=shutil.ignore_patterns('._*','.DS_Store'))
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
info.update(CFBundleIdentifier='org.ekoloko.flash34',CFBundleName='Ekoloko Flash34',CFBundleDisplayName='ekoloko',CFBundleShortVersionString='1.1.1',CFBundleVersion='1112')
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
sha=lambda file:hashlib.sha256(file.read_bytes()).hexdigest()
player=resources/'plugins/mac34/PepperFlashPlayer.plugin/Contents/MacOS/PepperFlashPlayer'
assert sha(player)=='e412191a202ddf3627f433509353cc90fd94713950c55072b493a4dcb851d4d7'
runtime=plistlib.loads((app/'Contents/Frameworks/Electron Framework.framework/Resources/Info.plist').read_bytes())
assert runtime['CFBundleVersion']=='8.2.0'
shutil.rmtree(stage)
commit=subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip()
receipt={'version':'1.1.1','build':'1112','source_commit':commit,'source_branch':'mac-support-1.1.1-flash34','base_tag_commit':'6a09ae534858f9674c6aa9cd29139ab25eb4a72e','electron':'8.2.0','architecture':'x86_64','flash':'34.0.0.372','flash_sha256':sha(player),'app_asar_sha256':sha(resources/'app.asar'),'main_sha256':sha(root/'runtime-source/index.js'),'signed':False,'notarized':False,'auto_update_mac':False}
(resources/'mac-build-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
(out/'mac-build-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(receipt,indent=2))
