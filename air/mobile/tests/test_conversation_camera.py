"""AIR camera geometry, keyboard conversion, real display-list collection and smoothing."""
from pathlib import Path
import os,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
SDK=Path('/Volumes/T9/AIR/sdks/AIRSDK_51.4.1')
def main():
 env=dict(os.environ,JAVA_HOME='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home')
 with tempfile.TemporaryDirectory(prefix='conversation-camera-') as name:
  d=Path(name);package=d/'com/vtweens/components/chat';package.mkdir(parents=True)
  (package/'ChatBaloon.as').write_text('package com.vtweens.components.chat {import flash.display.Sprite;public class ChatBaloon extends Sprite {public function ChatBaloon(){graphics.beginFill(0xffffff);graphics.drawRect(-70,-200,140,60);graphics.endFill();}}}')
  subprocess.run([str(SDK/'bin/amxmlc'),'-debug=true','-omit-trace-statements=false','-source-path+='+str(ROOT/'src'),'-source-path+='+str(ROOT/'connected'),'-source-path+='+str(d),'-output='+str(d/'test.swf'),str(ROOT/'tests/ConversationCameraTests.as')],env=env,check=True)
  (d/'app.xml').write_text('<application xmlns="http://ns.adobe.com/air/application/51.4"><id>org.ekoloko.mobile.cameratests</id><versionNumber>1.0.0</versionNumber><filename>CameraTests</filename><initialWindow><content>test.swf</content><visible>false</visible></initialWindow><supportedProfiles>extendedDesktop</supportedProfiles></application>')
  r=subprocess.run([str(SDK/'bin/adl'),str(d/'app.xml'),str(d)],env=env,capture_output=True,text=True,timeout=30)
  print(r.stdout+r.stderr);assert r.returncode==0 and 'CONVERSATION_CAMERA_PASS' in r.stdout+r.stderr
if __name__=='__main__':main()
