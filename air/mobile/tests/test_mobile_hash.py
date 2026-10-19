"""Native AIR SHA-256 correctness and timing; no game, network or credentials."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SDK = Path('/Volumes/T9/AIR/sdks/AIRSDK_51.4.1')
CORE = Path('/Users/ransaymour/Documents/Codex/2026-10-09/task-6/air-candidate/air-unified')


def main():
    env = dict(os.environ, JAVA_HOME='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home')
    with tempfile.TemporaryDirectory(prefix='mobile-native-hash-') as temporary:
        folder = Path(temporary)
        vectors = []
        for name, data in [('empty', b''), ('abc', b'abc'),
                           ('boundary', bytes(range(256)) * 256 + b'x'),
                           ('large', bytes(range(256)) * 32768)]:
            (folder / name).write_bytes(data)
            vectors.append(dict(file=name, sha=hashlib.sha256(data).hexdigest(), length=len(data)))
        (folder / 'vectors.json').write_text(json.dumps(vectors))
        subprocess.run([str(SDK / 'bin/amxmlc'), '-debug=true', '-omit-trace-statements=false',
                        '-source-path+=' + str(ROOT / 'mobile/connected'),
                        '-source-path+=' + str(CORE / 'air/src'),
                        '-source-path+=' + str(ROOT / 'build/mobile-connected/generated'),
                        '-output=' + str(folder / 'test.swf'),
                        str(ROOT / 'mobile/tests/MobileHashTests.as')], env=env, check=True)
        (folder / 'app.xml').write_text(
            '<application xmlns="http://ns.adobe.com/air/application/51.4">'
            '<id>org.ekoloko.mobile.hashtest</id><versionNumber>1.0.0</versionNumber>'
            '<filename>HashTests</filename><initialWindow><content>test.swf</content>'
            '<visible>false</visible></initialWindow><supportedProfiles>extendedDesktop</supportedProfiles></application>')
        result = subprocess.run([str(SDK / 'bin/adl'), str(folder / 'app.xml'), str(folder)],
                                env=env, text=True, capture_output=True, timeout=45)
        print(result.stdout + result.stderr)
        assert result.returncode == 0 and 'MOBILE_HASH_PASS' in result.stdout + result.stderr


if __name__ == '__main__':
    main()
