"""Real hidden AIR runtime checks; ADL mobile profile is not iOS device proof."""
import json,os,subprocess,tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SDK=Path(os.environ.get('AIR_SDK_HOME','/Volumes/T9/AIR/sdks/AIRSDK_51.4.1'))
# iOS ignores initialWindow's desktop Retina preference. Both host builders use
# this base descriptor; phone-specific string replacements must preserve one child.
ns={'a':'http://ns.adobe.com/air/application/51.3'}
root=ET.parse(ROOT/'application.xml').getroot()
values=root.findall('a:iPhone/a:requestedDisplayResolution',ns)
assert len(values)==1 and values[0].text=='high', 'iOS Retina must be explicitly high'
assert root.find('a:initialWindow/a:requestedDisplayResolution',ns).text=='high'
print('DESCRIPTOR_RETINA_PASS')
env=dict(os.environ,JAVA_HOME=os.environ.get('JAVA_HOME','/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home'))
with tempfile.TemporaryDirectory(prefix='ekoloko-render-quality-') as tmp:
 p=Path(tmp)
 subprocess.run([str(SDK/'bin/amxmlc'),'-debug=true','-omit-trace-statements=false','-source-path+='+str(ROOT/'src'),'-output='+str(p/'test.swf'),str(ROOT/'tests/MobileRenderQualityTests.as')],env=env,check=True,capture_output=True)
 for profile in ['extendedDesktop','mobileDevice']:
  descriptor=p/(profile+'.xml');descriptor.write_text('<application xmlns="http://ns.adobe.com/air/application/51.4"><id>org.ekoloko.quality.tests.'+profile.lower()+'</id><versionNumber>1.0</versionNumber><filename>QualityTests</filename><initialWindow><content>test.swf</content><visible>false</visible><renderMode>direct</renderMode></initialWindow><supportedProfiles>'+profile+'</supportedProfiles></application>')
  result=subprocess.run([str(SDK/'bin/adl'),'-profile',profile,str(descriptor),str(p)],env=env,text=True,capture_output=True,timeout=30)
  output=result.stdout+result.stderr
  assert result.returncode==0 and 'MOBILE_RENDER_QUALITY_PASS ' in output,(profile,result.returncode,result.stdout,result.stderr)
  print(profile,output.strip())
