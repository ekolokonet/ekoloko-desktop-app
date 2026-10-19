"""Bounded timing aggregate contract, without network or account data."""
from pathlib import Path
import os,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
SDK=Path('/Volumes/T9/AIR/sdks/AIRSDK_51.4.1')
def main():
 env=dict(os.environ,JAVA_HOME='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home')
 with tempfile.TemporaryDirectory(prefix='mobile-perf-tests-') as name:
  d=Path(name)
  subprocess.run([str(SDK/'bin/amxmlc'),'-debug=true','-omit-trace-statements=false','-source-path+='+str(ROOT/'connected'),'-output='+str(d/'test.swf'),str(ROOT/'tests/MobilePerformanceTests.as')],env=env,check=True)
  (d/'app.xml').write_text('<application xmlns="http://ns.adobe.com/air/application/51.4"><id>org.ekoloko.mobile.perftests</id><versionNumber>1.0.0</versionNumber><filename>PerfTests</filename><initialWindow><content>test.swf</content><visible>false</visible></initialWindow><supportedProfiles>extendedDesktop</supportedProfiles></application>')
  r=subprocess.run([str(SDK/'bin/adl'),str(d/'app.xml'),str(d)],env=env,capture_output=True,text=True,timeout=30)
  print(r.stdout+r.stderr)
  assert r.returncode==0 and 'MOBILE_PERFORMANCE_PASS' in r.stdout+r.stderr
if __name__=='__main__':main()
