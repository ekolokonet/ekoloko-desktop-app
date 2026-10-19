#!/usr/bin/env python3
"""Build native AIR releases using Python's standard library and HARMAN SDK."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zlib
import lzma
import struct
import tarfile
import secrets
import plistlib

from swf import adapt_swf, unpack

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
APP = BUILD / "application"
MAC_CACHE = Path.home() / "Library/Caches/EkolokoAIRBuilds"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def run(args, **kwargs):
    return subprocess.run([str(x) for x in args], check=True, **kwargs)


def sdk_tool(name):
    sdk = Path(os.environ.get("AIR_SDK_HOME", ""))
    suffix = ".bat" if os.name == "nt" and name != "adl" else ".exe" if os.name == "nt" else ""
    tool = sdk / "bin" / (name + suffix)
    if not tool.is_file():
        raise ValueError("Set AIR_SDK_HOME to a HARMAN AIR SDK 51.3.4 or newer installation")
    return tool.resolve()


def compile_adapters():
    BUILD.mkdir(parents=True, exist_ok=True)
    run([sdk_tool("amxmlc"), f"-source-path+={ROOT / 'adapters'}", "-debug=false", "-omit-trace-statements=true", f"-output={BUILD / 'adapters.swf'}", ROOT / "adapters/Adapters.as"])


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise ValueError("Shell source drift: expected one reviewed adaptation anchor")
    return source.replace(old, new, 1)


def native_shell(source, ffdec):
    """Export the *pinned shipped* Shell; adapt lifecycle/installation identity.

    The current encrypted transport and every other source class stay intact.
    """
    source = source.resolve()
    work = BUILD / "shell-adaptation"
    work.mkdir(parents=True, exist_ok=True)
    shell = source / "ekoloko-client/ekoloko/shell.swf"
    pin = (source / "tools/EKOLOKO_CLIENT_EK2/patched-shell.sha256").read_text().split()[0]
    if digest(shell.read_bytes()) != pin:
        raise ValueError("Shipped shell does not match the existing EK2 release pin")
    relative = Path("com/vtweens/shell/Shell.as")
    run(["java", "-Xmx2g", "-jar", ffdec, "-onerror", "abort", "-selectclass", "com.vtweens.shell.Shell", "-export", "script", work / "export", shell], stdout=subprocess.DEVNULL)
    original = (work / "export/scripts" / relative).read_text()
    code = replace_once(original,
        "public function Shell()\n      {\n         super();",
        "public function Shell()\n      {\n         super();\n         if(videoAdsPlayer != null) videoAdsPlayer.fullScreenTakeOver = false;\n         if(stage) initializeNativeShell();\n         else addEventListener(Event.ADDED_TO_STAGE,initializeNativeShell);\n      }\n\n      private function initializeNativeShell(event:Event = null) : void\n      {\n         removeEventListener(Event.ADDED_TO_STAGE,initializeNativeShell);")
    # This exact method's first statement is the existing local-install lookup.
    anchor = "private function persistentInstallId() : String\n      {"
    code = replace_once(code, anchor, anchor + '\n         return String(ExternalInterface.call("ekolokoNativeInstallId"));\n      }\n\n      private function legacyPersistentInstallIdUnused() : String\n      {')
    patch = work / "patch" / relative
    patch.parent.mkdir(parents=True, exist_ok=True)
    patch.write_text(code)
    result = work / "shell-native.swf"
    run(["java", "-Xmx2g", "-jar", ffdec, "-onerror", "abort", "-importScript", shell, result, work / "patch"], stdout=subprocess.DEVNULL)
    run(["java", "-Xmx2g", "-jar", ffdec, "-onerror", "abort", "-selectclass", "com.vtweens.shell.Shell", "-export", "script", work / "verify", result], stdout=subprocess.DEVNULL)
    verified = (work / "verify/scripts" / relative).read_text()
    for marker in ("initializeNativeShell", "fullScreenTakeOver = false", "ekolokoNativeInstallId", "recordDeviceObservation", "validApplicationLoginResponse", "setEncryptedFallbackEndpoint"):
        if marker not in verified:
            raise ValueError("Native Shell decompile verification failed: " + marker)
    (work / "audit.json").write_text(json.dumps({"baseSha256": pin, "nativeSha256": digest(result.read_bytes()), "adaptedClass": str(relative), "source": "current pinned shipped SWF", "changes": ["defer startup until attached to AIR Stage", "read persistent native installation identity", "disable legacy video fullscreen takeover of the native game window"]}, indent=2) + "\n")
    return result.read_bytes(), pin


def prepare(args):
    source = Path(args.source).resolve()
    source_commit = None
    if args.ref:
        source_commit = subprocess.check_output(["git", "-C", str(source), "rev-parse", "--verify", args.ref + "^{commit}"], stderr=subprocess.DEVNULL, text=True).strip()
        snapshot = Path(tempfile.mkdtemp(prefix="ekoloko-air-source-")).resolve()
        selected = ("ekoloko-client/ekoloko/conf/files_version.xml", "tools/EKOLOKO_CLIENT_EK2/patched-shell.sha256")
        with subprocess.Popen(["git", "-C", str(source), "archive", source_commit, "ekoloko-client/ekoloko", selected[1]], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL) as archive:
            with tarfile.open(fileobj=archive.stdout, mode="r|*") as tar:
                for member in tar:
                    if not member.isfile() or not (member.name in selected or member.name.endswith(".swf")):
                        continue
                    target = snapshot / member.name
                    if not target.resolve().is_relative_to(snapshot):
                        raise ValueError("Archive path escapes snapshot")
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with tar.extractfile(member) as reader, target.open("wb") as writer:
                        shutil.copyfileobj(reader, writer)
            if archive.wait():
                raise ValueError("Could not extract requested Git snapshot")
        source = snapshot
        print("Building isolated source commit:", source_commit, flush=True)
    asset_root = source / "ekoloko-client/ekoloko"
    if not asset_root.is_dir():
        raise ValueError("--source must name the Ekoloko source repository")
    if not re.fullmatch(r"https://[a-z0-9.-]+", args.origin):
        raise ValueError("A fixed HTTPS origin without credentials, path or port is required")
    ffdec = Path(args.ffdec).resolve()
    if not ffdec.is_file():
        raise ValueError("Provide --ffdec /path/to/ffdec.jar")
    compile_adapters()
    shell_bytes, shell_pin = native_shell(source, ffdec)
    adapters = (BUILD / "adapters.swf").read_bytes()
    version_xml = (asset_root / "conf/files_version.xml").read_bytes()
    main_version = ET.fromstring(version_xml).findtext("main_version")
    APP.mkdir(parents=True, exist_ok=True)
    assets, skipped, changed, seen = {}, [], {}, {}
    with (APP / "air-assets.pack.tmp").open("wb") as pack:
        for path in sorted(asset_root.rglob("*.swf")):
            key = path.relative_to(asset_root).as_posix()
            if not path.is_file() or any(part.startswith(".") or part in {"node_modules", "backup", "backups", "src", "scripts", "decompiled"} for part in path.relative_to(asset_root).parts):
                continue
            raw = path.read_bytes()
            original_sha = digest(raw)
            if not raw.startswith((b"FWS", b"CWS", b"ZWS")):
                skipped.append({"path": key, "reason": "not_swf"})
                continue
            if key == "shell.swf":
                raw = shell_bytes
            try:
                native, count = adapt_swf(raw, adapters, "org.ekoloko.air.compat.a" + digest(raw)[:24])
            except (ValueError, IndexError, EOFError, zlib.error, lzma.LZMAError, struct.error) as error:
                if key in {"shell.swf", "main.swf"}:
                    raise ValueError(f"Cannot safely adapt required asset {key}: {error}") from error
                skipped.append({"path": key, "reason": "malformed_or_unsupported_swf", "detail": str(error)})
                continue
            sha = digest(native)
            if sha in seen:
                offset, length = seen[sha]
            else:
                offset, length = pack.tell(), len(native)
                pack.write(native)
                seen[sha] = (offset, length)
            assets[key] = {"offset": offset, "length": length, "sha256": sha, "originalSha256": original_sha}
            if count:
                changed[key] = count
            if len(assets) % 3000 == 0:
                print(f"Prepared {len(assets)} SWFs", flush=True)
        size = pack.tell()
    if not {"shell.swf", "main.swf"} <= assets.keys():
        raise ValueError("Required game entry assets are missing")
    (APP / "air-assets.pack.tmp").replace(APP / "air-assets.pack")
    manifest = {"schema": 1, "version": "0.1.0", "origin": args.origin, "mainVersion": main_version,
                "baseShellSha256": shell_pin, "versionConfigSha256": digest(version_xml), "sourceCommit": source_commit, "packSize": size, "assets": assets}
    manifest_bytes = (json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()
    (APP / "air-manifest.json").write_bytes(manifest_bytes)
    compressed_manifest = zlib.compress(manifest_bytes, 9)
    (APP / "air-manifest.zlib").write_bytes(compressed_manifest)
    (BUILD / "asset-audit.json").write_text(json.dumps({"assets": len(assets), "uniqueAssets": len(seen), "packBytes": size, "runtimeAdapterReferences": changed, "excludedInvalidFiles": skipped}, ensure_ascii=False, indent=2) + "\n")
    print(f"Prepared {len(assets)} SWFs, {len(changed)} adapted, {size / 1048576:.1f} MiB. Shipped assets untouched.")
    if not getattr(args, "assets_only", False):
        build(args)


def build(args):
    live = getattr(args, "live", False)
    if not live and not (APP / "air-manifest.json").exists():
        raise ValueError("Run prepare first")
    APP.mkdir(parents=True, exist_ok=True)
    modulus = ""
    if live:
        public_key = getattr(args, "public_key", None)
        if not public_key:
            raise ValueError("Live builds require --public-key with the publisher's public pin JSON")
        key = json.loads(Path(public_key).read_text())
        modulus = key.get("modulusHex", "")
        if key.get("algorithm") != "RSA-SHA256" or key.get("exponent") != 65537 or not re.fullmatch(r"[89a-f][0-9a-f]{510}[13579bdf]", modulus):
            raise ValueError("Invalid RSA2048 release public-key pin")
        origin = getattr(args, "origin", "https://play.ekoloko.org")
        manifest_sha = ""
    else:
        origin = json.loads((APP / "air-manifest.json").read_text())["origin"]
        manifest_sha = digest((APP / "air-manifest.zlib").read_bytes())
    if not re.fullmatch(r"https://[a-z0-9.-]+", origin):
        raise ValueError("A fixed HTTPS game origin is required")
    generated = BUILD / "generated/org/ekoloko/air/BuildInfo.as"
    generated.parent.mkdir(parents=True, exist_ok=True)
    generated.write_text('package org.ekoloko.air { public final class BuildInfo {\n' +
        f'public static const ORIGIN:String="{origin}";\npublic static const VERSION:String="0.1.0";\n' +
        f'public static const MANIFEST_SHA256:String="{manifest_sha}";\n' +
        f'public static const LIVE_RELEASES:Boolean={str(live).lower()};\n' +
        f'public static const RELEASE_PUBLIC_MODULUS:String="{modulus}";\n' + '}}\n')
    run([sdk_tool("amxmlc"), f"-source-path+={ROOT / 'src'}", f"-source-path+={BUILD / 'generated'}", "-debug=true" if getattr(args, "debug", False) else "-debug=false", "-omit-trace-statements=false", f"-output={APP / 'EkolokoAIR.swf'}", ROOT / "src/EkolokoAIR.as"])
    shutil.copyfile(ROOT / "application.xml", APP / "application.xml")
    shutil.copyfile(ROOT / "AS3CRYPTO_LICENSE.md", APP / "AS3CRYPTO_LICENSE.md")
    (APP / "air-build.json").write_text(json.dumps({"mode": "live" if live else "bundled", "origin": origin,
        "publicKeySha256": digest(modulus.encode()) if live else None}, sort_keys=True) + "\n")
    print("Built native AIR application:", APP)


def verify(args):
    if build_mode() == "live":
        if not (APP / "EkolokoAIR.swf").is_file():
            raise ValueError("Live host is not built")
        print("PASS: live host packaging excludes the game pack; release signatures are checked at startup")
        return
    manifest_bytes = zlib.decompress((APP / "air-manifest.zlib").read_bytes())
    if manifest_bytes != (APP / "air-manifest.json").read_bytes():
        raise ValueError("Manifest review copy differs from runtime manifest")
    manifest = json.loads(manifest_bytes)
    with (APP / "air-assets.pack").open("rb") as pack:
        checked = set()
        for entry in manifest["assets"].values():
            if entry["sha256"] in checked:
                continue
            pack.seek(entry["offset"])
            if digest(pack.read(entry["length"])) != entry["sha256"]:
                raise ValueError("Pack digest mismatch")
            checked.add(entry["sha256"])
    print(f"PASS: {len(checked)} installed asset digests; {len(manifest['assets'])} paths")


def build_mode():
    path = APP / "air-build.json"
    if not path.is_file():
        raise ValueError("Build the host before packaging; delivery-mode metadata is missing")
    mode = json.loads(path.read_text()).get("mode")
    if mode not in {"live", "bundled"}:
        raise ValueError("Unrecognized host delivery mode")
    return mode


def package_files():
    names = ["EkolokoAIR.swf", "AS3CRYPTO_LICENSE.md", "air-build.json"]
    if build_mode() == "bundled":
        names += ["air-manifest.zlib", "air-assets.pack"]
    return names


def package(args):
    verify(args)
    if not args.certificate:
        raise ValueError("--certificate is required; signing passwords are entered at ADT's prompt")
    certificate = Path(args.certificate).resolve()
    if not certificate.is_file():
        raise ValueError("Signing certificate not found")
    out = ROOT / "dist" / ("EkolokoAIR-" + platform.system().lower())
    if out.exists() or out.with_suffix(".app").exists():
        raise ValueError("Output already exists; move it aside before packaging a new release")
    out.parent.mkdir(parents=True, exist_ok=True)
    run([sdk_tool("adt"), "-package", "-storetype", "pkcs12", "-keystore", certificate, "-target", "bundle", out,
         APP / "application.xml", "-C", APP, *package_files()])
    print("Created host-native captive bundle. Distribution still requires platform signing/notarization validation.")


def package_preview(args):
    """Create a local macOS bundle with a development-only AIR certificate."""
    if platform.system() != "Darwin":
        raise ValueError("The current preview target is macOS")
    verify(args)
    MAC_CACHE.mkdir(parents=True, exist_ok=True)
    # The repository may be on ExFAT, which cannot preserve framework symlinks
    # and adds AppleDouble files inside bundles. Package on the Mac filesystem;
    # distribute one DMG file, which preserves the signed bundle on any drive.
    out = Path(tempfile.mkdtemp(prefix="preview-", dir=MAC_CACHE)) / "Ekoloko AIR Preview.app"
    # This key is for a local preview only, never an Apple distribution identity.
    # Keep it out of Git and preserve it across rebuilds of the same preview.
    signing = ROOT / "local/preview-signing"
    signing.mkdir(parents=True, exist_ok=True, mode=0o700)
    certificate, password_file = signing / "preview.p12", signing / "password"
    if not certificate.exists():
        password = secrets.token_urlsafe(32)
        password_file.touch(mode=0o600, exist_ok=False)
        password_file.write_text(password)
        result = subprocess.run([str(sdk_tool("adt")), "-certificate", "-cn", "Ekoloko Local AIR Preview", "-validityPeriod", "1", "2048-RSA", str(certificate), password], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if result.returncode:
            raise ValueError("Could not create local preview certificate")
        certificate.chmod(0o600)
    else:
        password = password_file.read_text()
    command = [str(sdk_tool("adt")), "-package", "-storetype", "pkcs12", "-keystore", str(certificate), "-storepass", password, "-tsa", "none", "-target", "bundle", str(out), str(APP / "application.xml"), "-C", str(APP), *package_files()]
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode:
        # ADT may echo command arguments on failure. Do not print its raw output.
        raise ValueError("Local bundle packaging failed (ADT exit " + str(result.returncode) + ")")
    brand_mac_bundle(out)
    sign_local_bundle(out)
    resources = out / "Contents/Resources"
    for name in package_files():
        if digest((resources / name).read_bytes()) != digest((APP / name).read_bytes()):
            raise ValueError("Packaged resource differs from the current build: " + name)
    if build_mode() == "live" and any((resources / name).exists() for name in ("air-assets.pack", "air-manifest.json", "air-manifest.zlib")):
        raise ValueError("Thin preview unexpectedly contains a fixed game pack")
    (BUILD / "mac-preview.json").write_text(json.dumps({"application": str(out), "mode":build_mode(), "manifestSha256": digest((APP / "air-manifest.zlib").read_bytes()) if build_mode() == "bundled" else None, "hostSha256": digest((APP / "EkolokoAIR.swf").read_bytes()), "descriptorSha256": digest((APP / "application.xml").read_bytes()), "distributionSigned": False}, indent=2) + "\n")
    print("Created local macOS preview:", out)
    print("Not signed with Apple Developer ID or notarized for distribution.")


def sign_local_bundle(bundle):
    # ADT's template executable must be sealed again after its Info.plist and
    # resources are populated. This local ad-hoc signature grants no debugger
    # entitlement and does not change Gatekeeper or system trust settings.
    for extra in bundle.rglob("._*"):
        if extra.is_file() or extra.is_symlink():
            extra.unlink()  # generated copy only; never modify the SDK/source
    run(["codesign", "--force", "--sign", "-", "--entitlements", ROOT / "macos/preview.entitlements.plist", bundle])
    run(["codesign", "--verify", "--deep", "--strict", bundle])


def brand_mac_bundle(bundle):
    shutil.copyfile(ROOT.parent / "build/icon.icns", bundle / "Contents/Resources/Ekoloko.icns")
    info = bundle / "Contents/Info.plist"
    plist = plistlib.loads(info.read_bytes())
    plist["CFBundleIconFile"] = "Ekoloko.icns"
    plist["CFBundleDisplayName"] = "Ekoloko AIR Preview"
    info.write_bytes(plistlib.dumps(plist))


def dmg(args):
    if platform.system() != "Darwin":
        raise ValueError("DMG packaging requires macOS")
    record = json.loads((BUILD / "mac-preview.json").read_text())
    bundle = Path(record["application"])
    if record.get("mode", "bundled") != build_mode():
        raise ValueError("Package the current release delivery mode before creating its DMG")
    if build_mode() == "bundled" and record["manifestSha256"] != digest((APP / "air-manifest.zlib").read_bytes()):
        raise ValueError("Package the current asset release before creating its DMG")
    if record.get("hostSha256") != digest((APP / "EkolokoAIR.swf").read_bytes()) or record.get("descriptorSha256") != digest((APP / "application.xml").read_bytes()):
        raise ValueError("Package the current interface and application settings before creating its DMG")
    run(["codesign", "--verify", "--deep", "--strict", bundle])
    sys.path.insert(0, str(ROOT / "local/dmgtools"))
    try:
        import dmgbuild
    except ImportError as error:
        raise ValueError("Install macos/requirements.txt into air/local/dmgtools with pip") from error
    out = ROOT / ("dist/Ekoloko-AIR-0.1.0-macOS-live-preview.dmg" if build_mode() == "live" else "dist/Ekoloko-AIR-0.1.0-macOS-preview.dmg")
    if out.exists():
        raise ValueError("DMG already exists; move it aside before creating a new image")
    out.parent.mkdir(parents=True, exist_ok=True)
    dmgbuild.build_dmg(str(out), "Ekoloko AIR Preview", settings={
        "format": "UDZO", "filesystem": "HFS+", "files": [str(bundle)],
        "symlinks": {"Applications": "/Applications"},
        "icon": str(ROOT.parent / "build/icon.icns"),
        "background": str(ROOT.parent / "build/dmg-background.png"),
        "window_rect": ((120, 90), (768, 512)), "default_view": "icon-view",
        "show_status_bar": False, "show_tab_view": False, "show_toolbar": False,
        "show_pathbar": False, "show_sidebar": False,
        "icon_size": 96, "text_size": 13, "grid_spacing": 80,
        "icon_locations": {bundle.name: (224, 383), "Applications": (543, 383)},
        # SetFile's hidden-extension flag adds com.apple.FinderInfo to the
        # signed bundle and makes strict codesign verification fail.
        "arrange_by": None,
    })
    run(["hdiutil", "verify", out])
    with tempfile.TemporaryDirectory(prefix="ekoloko-air-installer-check-") as mount:
        run(["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", mount, out], stdout=subprocess.DEVNULL)
        try:
            installed = Path(mount) / bundle.name
            run(["codesign", "--verify", "--deep", "--strict", installed])
            checks = [("EkolokoAIR.swf", "hostSha256")]
            if build_mode() == "bundled": checks.append(("air-manifest.zlib", "manifestSha256"))
            for name, key in checks:
                if digest((installed / "Contents/Resources" / name).read_bytes()) != record[key]:
                    raise ValueError("Installer contains unexpected bytes: " + name)
            if build_mode() == "live":
                if (installed / "Contents/Resources/air-assets.pack").exists() or (installed / "Contents/Resources/air-manifest.zlib").exists():
                    raise ValueError("Live installer unexpectedly contains a fixed game pack")
            else:
                with (installed / "Contents/Resources/air-assets.pack").open("rb") as packed, (APP / "air-assets.pack").open("rb") as source:
                    if hashlib.file_digest(packed, "sha256").digest() != hashlib.file_digest(source, "sha256").digest():
                        raise ValueError("Installer asset pack differs from the reviewed build")
        finally:
            run(["hdiutil", "detach", mount], stdout=subprocess.DEVNULL)
    print("PASS: installed app signature and current host/manifest/asset bytes")
    (out.with_suffix(".dmg.sha256")).write_text(digest(out.read_bytes()) + "  " + out.name + "\n")
    print("Created branded macOS preview installer:", out)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prep = commands.add_parser("prepare")
    prep.add_argument("--source", required=True)
    prep.add_argument("--ref", help="Build an isolated immutable Git revision rather than the working tree")
    prep.add_argument("--ffdec", required=True)
    prep.add_argument("--origin", default="https://play.ekoloko.org")
    prep.add_argument("--debug", action="store_true")
    prep.add_argument("--assets-only", action="store_true", help="Prepare a server content release without rebuilding or changing the installed host")
    compiler = commands.add_parser("build")
    compiler.add_argument("--debug", action="store_true")
    compiler.add_argument("--live", action="store_true", help="Build a thin client that fetches signed releases and caches only requested SWFs")
    compiler.add_argument("--public-key", help="Publisher public pin JSON; never a private key")
    compiler.add_argument("--origin", default="https://play.ekoloko.org")
    commands.add_parser("run")
    commands.add_parser("verify")
    packaging = commands.add_parser("package")
    packaging.add_argument("--certificate", required=True)
    commands.add_parser("package-preview")
    commands.add_parser("dmg")
    args = parser.parse_args()
    if args.command == "run":
        # Legacy SWFs can contain their own trace() calls. Only the native
        # host's fixed status fields go to the terminal; no raw game log is kept.
        with subprocess.Popen([str(sdk_tool("adl")), str(APP / "application.xml"), str(APP)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True) as process:
            for line in process.stdout:
                if re.fullmatch(r"\[AIR\] (?:stopped=[a-z_]+|asset_path=/[A-Za-z0-9_./-]{1,180}|asset_failure=[a-z_]+ path=[A-Za-z0-9_./-]+ http=[0-9]+ error=[0-9]+|runtime_error_id=[0-9]+|live_release_map=pass main=[0-9]+|managed_cookie_roundtrip=pass|shell_loaded=true|native=[A-Z0-9_]+ runtime=[A-Z0-9 ,]+ release=[0-9.]+)\n?", line):
                    print(line, end="", flush=True)
            if process.wait():
                raise ValueError("AIR runtime stopped; inspect the native error screen or run the local fixture tests")
    else:
        globals()[args.command.replace("-", "_")](args)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print("AIR build stopped:", str(error), file=sys.stderr)
        raise SystemExit(1)
