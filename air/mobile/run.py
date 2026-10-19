#!/usr/bin/env python3
"""Compile/run the isolated AIR mobile input lab, never the desktop release."""
import argparse
import os
from pathlib import Path
import subprocess
from prepare_assets import prepare

ROOT = Path(__file__).resolve().parent
SIZES = {"phone-small": "375x667:375x667", "phone": "390x844:390x844",
         "phone-large": "430x932:430x932", "tablet": "768x1024:768x1024"}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", choices=SIZES, default="phone")
    parser.add_argument("--orientation",choices=["landscape","portrait"],default="landscape")
    parser.add_argument("--test", action="store_true")
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--render", action="store_true", help="Render local room and keyboard layout fixtures to PNG")
    parser.add_argument("--show-history", action="store_true", help="Open the recent-message window for visual review")
    args = parser.parse_args()
    sdk = Path(os.environ.get("AIR_SDK_HOME", "/Volumes/T9/AIR/sdks/AIRSDK_51.3.4"))
    if not (sdk / "bin/amxmlc").is_file():
        parser.error("Set AIR_SDK_HOME to the installed HARMAN AIR SDK")
    build = ROOT.parent / "build/mobile-lab"
    build.mkdir(parents=True, exist_ok=True)
    prepare(build / "assets")
    env = dict(os.environ)
    java = Path("/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home")
    if not env.get("JAVA_HOME") and java.exists():
        env["JAVA_HOME"] = str(java)
        env["PATH"] = str(java / "bin") + os.pathsep + env["PATH"]
    subprocess.run([str(sdk / "bin/amxmlc"), "-debug=true", "-omit-trace-statements=false",
                    "-source-path+=" + str(ROOT / "src"),
                    "-source-path+=" + str(ROOT.parent / "src"),
                    "-output=" + str(build / "MobileLab.swf"), str(ROOT / "src/MobileLab.as")],
                   env=env, check=True)
    descriptor=(ROOT / "application.xml").read_text().replace("<aspectRatio>landscape</aspectRatio>",
        "<aspectRatio>"+args.orientation+"</aspectRatio>")
    (build / "application.xml").write_text(descriptor)
    if args.build_only:
        return
    command = [str(sdk / "bin/adl"), "-profile", "mobileDevice", "-screensize", SIZES[args.device],
               str(build / "application.xml"), str(build)]
    if args.test:
        command += ["--", "--self-test"]
    elif args.render:
        command += ["--", "--render"]
    elif args.show_history:
        command += ["--", "--show-history"]
    subprocess.run(command, env=env, check=True, timeout=45 if args.test or args.render else None)

if __name__ == "__main__":
    main()
