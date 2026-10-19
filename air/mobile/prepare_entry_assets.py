"""Extract verified native entry artwork for offline rendering, without game code."""
import hashlib
import json
from pathlib import Path
import sys
import zlib

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT.parent / "scripts"))
from swf import unpack, pack
from prepare_assets import visual_tags


def prepare(build):
    content = build / "current-content"
    manifest = json.loads(zlib.decompress((content / "air-manifest.zlib").read_bytes()))
    receipt = {}
    with (content / "air-assets.pack").open("rb") as stream:
        for name, logical in {
            "login": "website/iw/login_iw.swf",
            "selector": "website/common/server_selector/serverSelector.swf",
            "recycle": "main_components/recycleGiftMachine.swf",
        }.items():
            entry = manifest["assets"][logical]
            stream.seek(entry["offset"])
            original = stream.read(entry["length"])
            digest = hashlib.sha256(original).hexdigest()
            if digest != entry["sha256"]:
                raise ValueError("Entry asset hash mismatch: " + logical)
            version, header, tags = unpack(original)
            visual = visual_tags(tags)
            (build / (name + "-visual.swf")).write_bytes(pack(version, header, visual))
            if name in ("selector", "login", "recycle"):
                # Loader needs the complete native opening timeline, but no
                # SymbolClass references to stripped executable classes.
                (build / (name + "-timeline.swf")).write_bytes(
                    pack(version, header, [(k, d) for k, d in visual if k != 76]))
            receipt[name] = {"logical": logical, "sourceSha256": digest}
    (build / "entry-artwork-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")


if __name__ == "__main__":
    prepare(ROOT.parent / "build/mobile-connected")
