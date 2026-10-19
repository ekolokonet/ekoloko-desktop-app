"""Package the connected AIR client for a registered physical iPhone.

Development interpreter build for real-device testing, not App Store delivery.
Signing files stay outside the source tree and are never included in the app.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import zipfile

from run_phone import BUILD, SDK


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, required=True)
    parser.add_argument('--certificate', type=Path, required=True)
    parser.add_argument('--password-file', type=Path, required=True)
    parser.add_argument('--device-udid', required=True)
    args = parser.parse_args()
    profile = plistlib.loads(subprocess.check_output(
        ['security', 'cms', '-D', '-i', str(args.profile)]))
    ent = profile['Entitlements']
    app_id = 'org.ekoloko.mobilephone'
    assert ent['application-identifier'].endswith('.' + app_id), 'Wrong application profile'
    assert ent.get('get-task-allow') is True, 'Development profile required'
    assert args.device_udid in profile['ProvisionedDevices'], 'Device not provisioned'
    assert profile['ExpirationDate'] > datetime.datetime.utcnow(), 'Profile expired'
    receipt = json.loads((BUILD / 'build-receipt.json').read_text())
    for filename, key in [('EkolokoAIR.swf', 'hostSha256'), ('air-manifest.zlib', 'manifestSha256')]:
        assert hashlib.sha256((BUILD / filename).read_bytes()).hexdigest() == receipt[key], filename
    # Match the exact reviewed content selected by run_phone --content, including
    # signed mobile releases newer than the original development snapshot.
    assert hashlib.sha256((BUILD / 'air-assets.pack').read_bytes()).hexdigest() == receipt['packSha256']
    platform = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
    password = args.password_file.read_text().strip()
    ipa = BUILD / 'Ekoloko-iPhone-Development.ipa'
    env = dict(os.environ, JAVA_HOME='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home')
    result = subprocess.run([str(SDK / 'bin/adt'), '-package', '-target', 'ipa-test-interpreter',
        '-storetype', 'pkcs12', '-keystore', str(args.certificate), '-storepass', password,
        '-provisioning-profile', str(args.profile), str(ipa), 'application.xml',
        '-platformsdk', platform, 'EkolokoAIR.swf', 'air-manifest.zlib', 'air-assets.pack',
        'bootstrap-shell.swf', 'icons'], cwd=BUILD, env=env, capture_output=True, text=True)
    print((result.stdout + result.stderr).replace(password, '[redacted]'))
    if result.returncode:
        raise SystemExit('Device packaging failed: ' + str(result.returncode))
    destination = BUILD / 'apple-device'
    with zipfile.ZipFile(ipa) as archive:
        archive.extractall(destination)
        for member in archive.infolist():
            mode = (member.external_attr >> 16) & 0o777
            if mode:
                (destination / member.filename).chmod(mode)
    app = destination / 'Payload/EkolokoPhoneReview.app'
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == app_id
    assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS']
    embedded = plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', str(app / 'embedded.mobileprovision')]))
    assert embedded['UUID'] == profile['UUID']
    receipt.update({'signed': True, 'physicalDeviceSigned': True, 'physicalDeviceTested': False,
        'target': 'ipa-test-interpreter', 'devicePackage': str(ipa), 'deviceApp': str(app),
        'profileUUID': profile['UUID'], 'profileExpiration': profile['ExpirationDate'].isoformat(),
        'teamID': profile['TeamIdentifier'][0], 'packageSha256': hashlib.sha256(ipa.read_bytes()).hexdigest()})
    (BUILD / 'device-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print('Signed physical-device package ready:', app)
    print('Installation and real-device gameplay have not been verified yet.')


if __name__ == '__main__':
    main()
