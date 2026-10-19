"""Build a separate phone-sized live-game host from the current AIR core.

No release files, account stores, server settings or signed content are modified.
The current core uses NativeProcess adaptation, so this first connected review
runs in extendedDesktop, not Apple Simulator or an iOS package.
"""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent
CORE = Path(os.environ.get("EKOLOKO_CONNECTED_CORE", "/Users/ransaymour/Documents/Codex/2026-10-09/task-6/air-candidate/air-unified"))
SDK = Path(os.environ.get("AIR_SDK_HOME", "/Volumes/T9/AIR/sdks/AIRSDK_51.3.4"))
BUILD = ROOT.parent / "build/mobile-connected"

def copy_changed(source, target):
    if target.exists() and hashlib.sha256(source.read_bytes()).digest() == hashlib.sha256(target.read_bytes()).digest():
        return
    temporary=target.with_name(target.name+".pending")
    shutil.copyfile(source,temporary)
    temporary.replace(target)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--build-only",action="store_true")
    p.add_argument("--portrait",action="store_true")
    p.add_argument("--test",action="store_true")
    p.add_argument("--chat-test",action="store_true")
    p.add_argument("--quest-test",action="store_true")
    p.add_argument("--cleanup-test",action="store_true")
    p.add_argument("--entry-test",action="store_true")
    p.add_argument("--panel-test",action="store_true")
    p.add_argument("--map-test",action="store_true")
    p.add_argument("--recycle-test",action="store_true")
    p.add_argument("--delivery-test",action="store_true")
    p.add_argument("--lifecycle-test",action="store_true")
    p.add_argument("--composer-test",action="store_true")
    p.add_argument("--probe",action="store_true",help="Read public deployed content without executing it")
    p.add_argument("--snapshot",action="store_true",help="Save one native startup render after 15 seconds")
    args=p.parse_args()
    BUILD.mkdir(parents=True,exist_ok=True)
    if args.entry_test or args.recycle_test:
        from prepare_entry_assets import prepare
        prepare(BUILD)
    generated=BUILD / "generated/org/ekoloko/air/BuildInfo.as"
    generated.parent.mkdir(parents=True,exist_ok=True)
    content=BUILD / "current-content"
    packed=(content / "content-receipt.json").exists() and not args.probe
    resource=content if packed else CORE / "resources"
    for name in ["air-manifest.zlib","bootstrap-shell.swf"]:
        copy_changed(resource / name,BUILD / name)
    if packed:
        receipt=json.loads((content / "content-receipt.json").read_text())
        assert hashlib.sha256((content / "air-assets.pack").read_bytes()).hexdigest()==receipt["packSha256"]
        copy_changed(content / "air-assets.pack",BUILD / "air-assets.pack")
    helper=CORE / "air/build/release-1.1.1-scoped-display-error/stage/air-adapter"
    shutil.copyfile(helper,BUILD / "air-adapter");(BUILD / "air-adapter").chmod(0o755)
    info=(CORE / "air/build/generated/org/ekoloko/air/BuildInfo.as").read_text()
    info=info.replace('VERSION:String="0.1.6"','VERSION:String="1.1.1"')
    pin=hashlib.sha256((BUILD / "air-manifest.zlib").read_bytes()).hexdigest()
    if packed:
        assert pin==receipt["manifestSha256"]
        info=re.sub(r'MANIFEST_SHA256:String="[0-9a-f]{64}"','MANIFEST_SHA256:String="'+pin+'"',info)
    info=info.replace('public final class BuildInfo {','public final class BuildInfo { public static const PACKED_REVIEW:Boolean='+str(packed).lower()+';')
    if packed:
        mobile_pin=json.loads((ROOT / "config/release-public-key.json").read_text())
        assert mobile_pin["algorithm"]=="RSA-SHA256" and mobile_pin["exponent"]==65537 and re.fullmatch('[89a-f][0-9a-f]{511}',mobile_pin['modulusHex'])
        info=re.sub(r'RELEASE_PUBLIC_MODULUS:String="[0-9a-f]+"','RELEASE_PUBLIC_MODULUS:String="'+mobile_pin['modulusHex']+'"',info)
    generated.write_text(info)
    if 'MANIFEST_SHA256:String="'+pin+'"' not in info:raise ValueError("Current core manifest pin differs")
    env=dict(os.environ,JAVA_HOME="/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home")
    root_class="MobilePanelTests" if args.panel_test else "ConnectedComposerTests" if args.composer_test else "PublicAssetProbe" if args.probe else "MobileEntryTests" if args.entry_test else "NativeCleanupTests" if args.cleanup_test else "MobileQuestTests" if args.quest_test else "ConnectedChatTests" if args.chat_test else "ConnectedInputTests" if args.test else "EkolokoAIR"
    if args.map_test:root_class="MobileMapTests"
    if args.recycle_test:root_class="MobileRecycleTests"
    if args.delivery_test:root_class="NativeChatDeliveryTests"
    if args.lifecycle_test:root_class="MobileLifecycleTests"
    entry=ROOT / "connected" / (root_class+".as")
    output=BUILD / (root_class+".swf")
    command=[str(SDK / "bin/amxmlc"),"-debug=true","-omit-trace-statements=false",
        "-define=CONFIG::desktop,true","-define=CONFIG::mobile,false",
        "-external-library-path+="+str(CORE / "private-motion/Shutter.swc"),
        "-source-path+="+str(ROOT / "connected"),"-source-path+="+str(ROOT / "src"),
        "-source-path+="+str(CORE / "air/src"),"-source-path+="+str(BUILD / "generated"),
        "-output="+str(output),str(entry)]
    subprocess.run(command,env=env,check=True)
    w,h=(390,844) if args.portrait else (844,390)
    xml=(CORE / "air/application.xml").read_text()
    xml=xml.replace("org.ekoloko.nativeair.lazycandidate20261009","org.ekoloko.mobileconnected")
    xml=xml.replace("Ekoloko AIR On Demand Candidate v6","Ekoloko — Connected Mobile Review")
    xml=xml.replace("<width>1000</width><height>700</height>",f"<width>{w}</width><height>{h}</height>")
    xml=xml.replace("<minSize>800 560</minSize>","<minSize>375 350</minSize>")
    testing=args.recycle_test or args.lifecycle_test or args.delivery_test or args.map_test or args.panel_test or args.composer_test or args.test or args.chat_test or args.quest_test or args.cleanup_test or args.entry_test or args.probe
    if testing:xml=xml.replace("EkolokoAIR.swf",root_class+".swf").replace("org.ekoloko.mobileconnected","org.ekoloko.mobileconnected.tests")
    descriptor=BUILD / ("probe.xml" if args.probe else "tests.xml" if testing else "application.xml");descriptor.write_text(xml)
    receipt={"core":str(CORE),"coreCommit":"3e34b4edc12aef97f3d55f956885f14626fcc829",
        "originalHostSha256":hashlib.sha256((CORE / "air/src/EkolokoAIR.as").read_bytes()).hexdigest(),
        "manifestSha256":pin,"adapterSha256":hashlib.sha256(helper.read_bytes()).hexdigest(),
        "profile":"extendedDesktop","connected":not testing,"credentialsCopied":False,
        "localPinnedPack":packed,"liveBinaryHashVerified":False,
        "hostSha256":hashlib.sha256(output.read_bytes()).hexdigest()}
    (BUILD / ("probe-build.json" if args.probe else "test-build.json" if testing else "build-receipt.json")).write_text(json.dumps(receipt,indent=2)+"\n")
    if args.build_only:return
    ext=BUILD / "extensions/Shutter.ane"
    if not ext.exists():
        ext.mkdir(parents=True)
        subprocess.run(["ditto","-x","-k",str(CORE / "private-motion/Shutter.ane"),str(ext)],check=True)
    command=[str(SDK / "bin/adl"),"-profile","extendedDesktop","-extdir",str(ext.parent),str(descriptor),str(BUILD)]
    if args.snapshot:command += ["--","--mobile-snapshot"]
    subprocess.run(command,env=env,check=True,timeout=90 if args.chat_test else 30 if testing else None)

if __name__=="__main__":main()
