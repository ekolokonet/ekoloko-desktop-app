"""Package the compiled phone host for Apple Simulator only, never a device.

Uses an ephemeral self-signed simulator certificate. No Apple credentials,
provisioning profiles, account stores or private keys are copied into the app.
"""
from pathlib import Path
import hashlib
import json
import os
import plistlib
import secrets
import subprocess
import tempfile
import zipfile
from run_phone import BUILD, SDK

def main():
    env = dict(os.environ, JAVA_HOME="/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home")
    platform = subprocess.check_output(["/usr/bin/xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()
    receipt = json.loads((BUILD / "build-receipt.json").read_text())
    for filename, key in (("EkolokoAIR.swf", "hostSha256"), ("air-manifest.zlib", "manifestSha256"), ("air-assets.pack", "packSha256")):
        if hashlib.sha256((BUILD / filename).read_bytes()).hexdigest() != receipt[key]:
            raise RuntimeError("Build receipt mismatch: " + filename)
    adt = str(SDK / "bin/adt")
    # Simulator entitlements belong in __TEXT, not the macOS code signature.
    # This is an isolated app identifier, with no shared Keychain groups.
    entitlements = BUILD / "simulator-entitlements.plist"
    entitlements.write_bytes(plistlib.dumps({"application-identifier":"SIMULATOR.org.ekoloko.mobilephone"}))
    def run(args, label, password):
        result = subprocess.run(args, env=env, cwd=BUILD, capture_output=True, text=True)
        output = (result.stdout + result.stderr).replace(password, "[redacted]")
        if output: print(output)
        if result.returncode: raise RuntimeError(label + " failed, exit " + str(result.returncode))
    with tempfile.TemporaryDirectory(prefix="ekoloko-simulator-signing-") as folder:
        certificate = str(Path(folder) / "simulator.p12")
        password = secrets.token_urlsafe(32)
        run([adt, "-certificate", "-cn", "Ekoloko Local Simulator Only", "2048-RSA", certificate, password], "Simulator certificate", password)
        ipa = BUILD / "Ekoloko-Simulator.ipa"
        run([adt, "-package",
            "-Xlinker", "-sectcreate __TEXT __entitlements " + str(entitlements),
            "-target", "ipa-test-interpreter-simulator", "-storetype", "pkcs12",
            "-keystore", certificate, "-storepass", password, str(ipa), "application.xml",
            "-platformsdk", platform,
            "EkolokoAIR.swf", "air-manifest.zlib", "air-assets.pack", "bootstrap-shell.swf", "icons"], "Simulator packaging", password)
    destination = BUILD / "apple-simulator"
    with zipfile.ZipFile(ipa) as archive:
        archive.extractall(destination)
        for member in archive.infolist():
            mode = (member.external_attr >> 16) & 0o777
            if mode:
                (destination / member.filename).chmod(mode)
    app = destination / "Payload/EkolokoPhoneReview.app"
    # AIR's simulator linker omits the Swift runtime search path on this SDK.
    load_commands = subprocess.check_output(["xcrun", "otool", "-l", str(app / "EkolokoPhoneReview")], text=True)
    if "path /usr/lib/swift " not in load_commands:
        subprocess.run(["xcrun", "install_name_tool", "-add_rpath", "/usr/lib/swift", str(app / "EkolokoPhoneReview")], check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
    # Repack the corrected simulator bundle; this signature is simulator-only.
    subprocess.run(["/usr/bin/ditto", "-c", "-k", "--keepParent", str(destination / "Payload"), str(ipa)], check=True)
    receipt.update({"simulatorPackage":str(ipa), "simulatorSDK":platform,
        "simulatorAdHocSigned":True, "physicalDeviceSigned":False,
        "simulatorCertificate":"ephemeral package certificate; final bundle signed ad hoc for simulator only"})
    (BUILD / "simulator-receipt.json").write_text(json.dumps(receipt, indent=2)+"\n")
    print("Apple Simulator package ready; not an iPhone installation package.")

if __name__ == "__main__": main()
