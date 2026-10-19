"""Real AIR path policy, with legacy and reviewed-capability BuildInfo fixtures."""
from pathlib import Path
import os, subprocess, sys, tempfile
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from run_phone import apply_content_capabilities
CORE=Path('/Users/ransaymour/Documents/Codex/2026-10-09/task-6/air-candidate/air-unified')
SDK=Path('/Volumes/T9/AIR/sdks/AIRSDK_51.3.4')
info=(ROOT.parent/'build/mobile-connected/generated/org/ekoloko/air/BuildInfo.as').read_text()
manifest={'assets':{'main.swf':{'sha256':'a'*64}}}
reviewed=apply_content_capabilities(info,{'recycleArtFallback':True},manifest)
assert 'RECYCLE_ART_FALLBACK_MAIN_SHA:String="'+'a'*64+'"' in reviewed
assert 'RECYCLE_ART_FALLBACK_MAIN_SHA:String=""' in apply_content_capabilities(reviewed,{},manifest)
assert 'RECYCLE_ART_FALLBACK_MAIN_SHA:String=""' in apply_content_capabilities(info,{'recycleArtFallback':'true'},manifest)
env=dict(os.environ,JAVA_HOME='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home')
for mode,source in [('legacy',info),('reviewed',reviewed),('disabled',apply_content_capabilities(reviewed,{},manifest))]:
 with tempfile.TemporaryDirectory(prefix='optional-assets-') as tmp:
  p=Path(tmp);generated=p/'generated/org/ekoloko/air';generated.mkdir(parents=True)
  (generated/'BuildInfo.as').write_text(source)
  subprocess.run([str(SDK/'bin/amxmlc'),'-debug=true','-omit-trace-statements=false','-source-path+='+str(ROOT/'connected'),'-source-path+='+str(CORE/'air/src'),'-source-path+='+str(p/'generated'),'-output='+str(p/'test.swf'),str(ROOT/'tests/MobileOptionalAssetTests.as')],env=env,check=True,stdout=subprocess.DEVNULL)
  (p/'app.xml').write_text('<application xmlns="http://ns.adobe.com/air/application/51.3"><id>org.ekoloko.mobile.optional.tests</id><versionNumber>1.0.0</versionNumber><filename>OptionalTests</filename><initialWindow><content>test.swf</content><visible>false</visible></initialWindow><supportedProfiles>extendedDesktop</supportedProfiles></application>')
  r=subprocess.run([str(SDK/'bin/adl'),str(p/'app.xml'),str(p)],env=env,text=True,capture_output=True,timeout=30)
  print(mode,r.stdout,r.stderr)
  assert r.returncode==0 and 'OPTIONAL_ASSET_PASS enabled='+str(mode=='reviewed').lower() in r.stdout+r.stderr
print('OPTIONAL_ASSET_GATE_PASS fixtures=3')
