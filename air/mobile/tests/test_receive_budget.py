"""Compile/run the exact mobile receive methods against a deterministic socket fixture.

No network, user data or shared build directory. The compiler uses production
method bodies; only the Socket type and monotonic clock are fixture substitutes.
"""
from pathlib import Path
import os
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'compatibility/shell/it/gotoandplay/smartfoxserver/SmartFoxClient.as'
SDK = Path(os.environ.get('AIR_SDK_HOME', '/Volumes/T9/AIR/sdks/AIRSDK_51.3.4'))


def method(source, name):
    start = source.index('      private function ' + name + '(')
    end = source.find('\n      private function ', start + 1)
    return source[start:end].replace(':Socket', ':FixtureSocket').replace(' as Socket', ' as FixtureSocket').replace('getTimer()', 'clock()')


def main():
    source = SOURCE.read_text()
    with tempfile.TemporaryDirectory(prefix='ekoloko-receive-test-') as directory:
        root = Path(directory)
        constants = '\n'.join(re.findall(r'      private static const RECEIVE_\w+:int = \d+;', source))
        bodies = '\n'.join(method(source, name) for name in ['handleSocketData', 'resumeSocketData', 'drainSocketData', 'restartPartialRecordTimer', 'retireSocketConnection'])
        fixture = (ROOT / 'tests/ReceiveBudgetTests.as.in').read_text().replace('// PRODUCTION_CONSTANTS', constants).replace('// PRODUCTION_METHODS', bodies)
        (root / 'ReceiveBudgetTests.as').write_text(fixture)
        (root / 'EK2Config.as').write_text('package { public class EK2Config { public static const MAX_ENCODED_RECORD_BYTES:int=131072; } }')
        (root / 'app.xml').write_text('''<application xmlns="http://ns.adobe.com/air/application/51.3"><id>org.ekoloko.receivebudget.tests</id><versionNumber>1.0.0</versionNumber><filename>ReceiveBudgetTests</filename><initialWindow><content>test.swf</content><visible>false</visible></initialWindow><supportedProfiles>extendedDesktop</supportedProfiles></application>''')
        env = dict(os.environ, JAVA_HOME='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home')
        subprocess.run([str(SDK / 'bin/amxmlc'), '-debug=true', '-omit-trace-statements=false', '-source-path+=' + str(root), '-output=' + str(root / 'test.swf'), str(root / 'ReceiveBudgetTests.as')], env=env, check=True)
        subprocess.run([str(SDK / 'bin/adl'), str(root / 'app.xml'), str(root)], env=env, timeout=30, check=True)


if __name__ == '__main__':
    main()
