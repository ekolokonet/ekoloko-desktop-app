"""Build the real pinned connected client with a mobile host, without signing.

--emulate uses AIR's mobile profile on macOS; it is not Apple Simulator or iOS.
Device packaging additionally needs Apple signing/provisioning and iOS validation.
"""
import argparse
import hashlib
import json
import os
import re
import zlib
from pathlib import Path
import subprocess
from run_connected import ROOT, CORE, BUILD as CONNECTED, copy_changed

BUILD = ROOT.parent / "build/mobile-phone"
SDK = Path("/Volumes/T9/AIR/sdks/AIRSDK_51.4.1")

def apply_content_capabilities(info, receipt, manifest):
    # A capability belongs to the exact reviewed Main, not just this host.
    # Remove any stale generated value before copying a different content pack.
    info = re.sub(r'public static const RECYCLE_ART_FALLBACK_MAIN_SHA:String="[0-9a-f]*";', '', info)
    digest = manifest['assets']['main.swf']['sha256'] if receipt.get('recycleArtFallback') is True else ''
    if digest and not re.fullmatch('[0-9a-f]{64}', digest):
        raise ValueError('recycle_fallback_digest_invalid')
    return info.replace('public final class BuildInfo {', 'public final class BuildInfo { public static const RECYCLE_ART_FALLBACK_MAIN_SHA:String="' + digest + '";')

def apply_version_map_capability(info, baseline, manifest):
    for name in ('VERSION_MAP_XML', 'VERSION_MAP_MAIN_SHA'):
        info = re.sub(r'public static const '+name+r':String="(?:[^"\\]|\\.)*";', '', info)
    if baseline is None:
        baseline = b''
    if baseline and hashlib.sha256(baseline).hexdigest() != manifest['versionConfigSha256']:
        raise ValueError('version_map_capability_hash_mismatch')
    xml = baseline.decode('utf-8')
    digest = manifest['assets']['main.swf']['sha256'] if baseline else ''
    fields = ' public static const VERSION_MAP_XML:String='+json.dumps(xml,ensure_ascii=True)+'; public static const VERSION_MAP_MAIN_SHA:String="'+digest+'";'
    return info.replace('public final class BuildInfo {', 'public final class BuildInfo {'+fields)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--emulate", action="store_true")
    parser.add_argument("--portrait", action="store_true")
    parser.add_argument("--snapshots", action="store_true", help="Enable expensive review captures in ADL; leave off for play testing")
    parser.add_argument("--version-map", type=Path, help="Reviewed current public version map; only text-catalog changes are accepted")
    parser.add_argument("--baseline-version-map", type=Path, help="Original map matching the signed review pack receipt")
    parser.add_argument("--content",type=Path,help="Explicitly reviewed prepared mobile release directory")
    parser.add_argument("--release-public-pin",type=Path,default=ROOT / "config/release-public-key.json",help="Public RSA pin for the isolated mobile update channel")
    args = parser.parse_args()
    BUILD.mkdir(parents=True, exist_ok=True)
    content=args.content or CONNECTED / "current-content"
    receipt = json.loads((content / "content-receipt.json").read_text())
    for name in ["air-assets.pack", "air-manifest.zlib", "bootstrap-shell.swf"]:
        copy_changed(content / name, BUILD / name)
    assert hashlib.sha256((BUILD / "air-assets.pack").read_bytes()).hexdigest() == receipt["packSha256"]
    assert hashlib.sha256((BUILD / "air-manifest.zlib").read_bytes()).hexdigest() == receipt["manifestSha256"]
    generated = BUILD / "generated/org/ekoloko/air/BuildInfo.as"
    generated.parent.mkdir(parents=True, exist_ok=True)
    info = (CONNECTED / "generated/org/ekoloko/air/BuildInfo.as").read_text()
    assert 'PACKED_REVIEW:Boolean=true' in info
    info=re.sub(r'MANIFEST_SHA256:String="[0-9a-f]{64}"', 'MANIFEST_SHA256:String="'+receipt["manifestSha256"]+'"',info)
    text_update = None
    if args.version_map:
        if not args.baseline_version_map:
            parser.error('--version-map requires --baseline-version-map')
        from mobile_version_map import validate_text_catalog_update
        baseline, current = args.baseline_version_map.read_bytes(), args.version_map.read_bytes()
        text_update = validate_text_catalog_update(baseline, current, receipt['versionMapSha256'])
        manifest = json.loads(zlib.decompress((BUILD / 'air-manifest.zlib').read_bytes()))
        manifest['versionConfigSha256'] = hashlib.sha256(current).hexdigest()
        (BUILD / 'air-manifest.zlib').write_bytes(zlib.compress(json.dumps(manifest, sort_keys=True, separators=(',', ':')).encode(), 9))
        receipt['manifestSha256'] = hashlib.sha256((BUILD / 'air-manifest.zlib').read_bytes()).hexdigest()
        info = re.sub(r'MANIFEST_SHA256:String="[0-9a-f]{64}"', 'MANIFEST_SHA256:String="'+receipt['manifestSha256']+'"', info)
    if args.release_public_pin:
        pin=json.loads(args.release_public_pin.read_text())
        assert pin.get('algorithm')=='RSA-SHA256' and pin.get('exponent')==65537 and re.fullmatch('[89a-f][0-9a-f]{511}',pin.get('modulusHex',''))
        info=re.sub(r'RELEASE_PUBLIC_MODULUS:String="[0-9a-f]+"','RELEASE_PUBLIC_MODULUS:String="'+pin['modulusHex']+'"',info)
    (BUILD / "air-manifest.json").write_bytes(zlib.decompress((BUILD / "air-manifest.zlib").read_bytes()))
    info = apply_content_capabilities(info, receipt, json.loads((BUILD / "air-manifest.json").read_text()))
    baseline_map = args.version_map or content / "files-version.xml"
    info = apply_version_map_capability(info, baseline_map.read_bytes() if baseline_map.exists() else None, json.loads((BUILD / "air-manifest.json").read_text()))
    generated.write_text(info)
    env = dict(os.environ, JAVA_HOME="/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home")
    subprocess.run([str(SDK / "bin/amxmlc"), "-debug=true", "-omit-trace-statements=false",
        "-define=CONFIG::desktop,false", "-define=CONFIG::mobile,true",
        "-external-library-path+=" + str(CORE / "private-motion/Shutter.swc"),
        "-source-path+=" + str(ROOT / "connected"), "-source-path+=" + str(ROOT / "src"),
        "-source-path+=" + str(CORE / "air/src"), "-source-path+=" + str(BUILD / "generated"),
        "-output=" + str(BUILD / "EkolokoAIR.swf"), str(ROOT / "connected/EkolokoAIR.as")], env=env, check=True)
    xml = (ROOT / "application.xml").read_text().replace("org.ekoloko.mobilelab", "org.ekoloko.mobilephone")
    xml = xml.replace("MobileLab.swf", "EkolokoAIR.swf").replace("EkolokoMobileLab", "EkolokoPhoneReview")
    xml = xml.replace("Ekoloko Mobile Lab", "Ekoloko Phone Review").replace("Ekoloko — Mobile Input Lab", "Ekoloko — Connected Phone Review")
    xml = xml.replace("application/51.3", "application/51.4")
    if args.portrait: xml = xml.replace("<aspectRatio>landscape</aspectRatio>", "<aspectRatio>portrait</aspectRatio>")
    (BUILD / "application.xml").write_text(xml)
    # Reuse the approved desktop artwork verbatim; only export required sizes.
    icons = BUILD / 'icons'
    icons.mkdir(exist_ok=True)
    icon_source = ROOT / 'assets/app-icon/desktop-1024.png'
    sizes = (29, 40, 48, 50, 57, 58, 60, 72, 76, 80, 87, 96, 100, 114, 120, 128, 144, 152, 167, 180, 512, 1024)
    for size in sizes:
        target = icons / ('icon-%d.png' % size)
        if size == 1024:
            copy_changed(icon_source, target)
        else:
            subprocess.run(['sips', '-z', str(size), str(size), str(icon_source), '--out', str(target)], check=True, stdout=subprocess.DEVNULL)
    icon_xml = '<icon>' + ''.join('<image{0}x{0}>icons/icon-{0}.png</image{0}x{0}>'.format(size) for size in sizes) + '</icon>'
    xml = xml.replace('</application>', icon_xml + '</application>')
    (BUILD / 'application.xml').write_text(xml)
    (BUILD / "build-receipt.json").write_text(json.dumps({"manifestSha256":receipt["manifestSha256"],
        "profile":"mobileDevice", "mobileHostProtocol":1, "game":"original pinned connected client", "signed":False,
        "appleSimulatorTested":False, "physicalDeviceTested":False, "credentialsCopied":False,
        "airSDK":str(SDK),
        "iconSourceSha256":hashlib.sha256(icon_source.read_bytes()).hexdigest(),
        "packSha256":receipt['packSha256'],
        "recycleArtFallback":receipt.get("recycleArtFallback") is True,
        "reviewedTextCatalogUpdate":text_update,
        "hostSha256":hashlib.sha256((BUILD / "EkolokoAIR.swf").read_bytes()).hexdigest()}, indent=2)+"\n")
    print("Mobile host compiled; not signed or installed on iPhone.")
    if args.emulate:
        launch_args = ["--", "--mobile-snapshot"] if args.snapshots else []
        subprocess.run([str(SDK / "bin/adl"), "-profile", "mobileDevice", "-screensize", "390x844:390x844",
            str(BUILD / "application.xml"), str(BUILD), *launch_args], env=env, check=True)

if __name__ == "__main__": main()
