"""Extract a hash-checked, visual-only subset of the existing local AIR pack.

No account/network bootstrap is executed. Flex embeds selected library symbols
into the lab; ActionScript from the source games is not included in these files.
"""
import hashlib
import json
import os
from pathlib import Path
import struct
import sys

AIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(AIR / "scripts"))
from swf import unpack, pack

ASSETS = {
    "room": "world_rooms/jungle101.swf",
    "faces": "avatarLoader.swf",
    "npc": "npcs/01_Heathcliff_Greenleaf.swf",
    "hair": "items/HFR/HFR_10501.swf",
    "shadow": "items/SDW/SDW_1.swf",
    "torso": "items/TOR/TOR_1.swf", "legs": "items/LEG/LEG_1.swf",
    "leftarm": "items/LAR/LAR_1.swf", "rightarm": "items/RAR/RAR_1.swf",
    "shirt": "items/SHT/SHT_10101.swf", "leftsleeve": "items/LSV/LSV_10101.swf",
    "rightsleeve": "items/RSV/RSV_10101.swf", "pants": "items/PTS/PTS_10101.swf",
    "shoes": "items/SHZ/SHZ_10104.swf",
}

def visual_tags(tags):
    result = []
    for kind, data in tags:
        if kind in (12, 59, 72, 82):
            continue
        if kind == 76:
            # Keep library exports, remove the executable document class.
            pos, entries = 2, []
            for _ in range(struct.unpack_from("<H", data)[0]):
                start = pos
                symbol_id = struct.unpack_from("<H", data, pos)[0]
                pos = data.index(0, pos + 2) + 1
                if symbol_id:
                    entries.append(data[start:pos])
            data = struct.pack("<H", len(entries)) + b"".join(entries)
        result.append((kind, data))
    return result

def prepare(output):
    manifest = json.loads((AIR / "build/application/air-manifest.json").read_text())
    output.mkdir(parents=True, exist_ok=True)
    receipt = {"sourceCommit": manifest["sourceCommit"], "assets": {}}
    with (AIR / "build/application/air-assets.pack").open("rb") as stream:
        for name, logical in ASSETS.items():
            entry = manifest["assets"][logical]
            stream.seek(entry["offset"])
            original = stream.read(entry["length"])
            if hashlib.sha256(original).hexdigest() != entry["sha256"]:
                raise ValueError("Local pack hash mismatch: " + logical)
            version, header, tags = unpack(original)
            result = pack(version, header, visual_tags(tags))
            (output / (name + ".swf")).write_bytes(result)
            receipt["assets"][name] = {"path": logical, "sourceSha256": entry["sha256"],
                "visualSha256": hashlib.sha256(result).hexdigest()}
    # Use the checked-out game's real UI library, never a redrawn mobile skin.
    main = Path(os.environ.get("EKOLOKO_UI_SWF",
        "/Volumes/T9/ekoloko-rewritten-new/ekoloko-client/ekoloko/main.swf"))
    original = main.read_bytes()
    version, header, tags = unpack(original)
    result = pack(version, header, visual_tags(tags))
    (output / "ui.swf").write_bytes(result)
    receipt["assets"]["ui"] = {"path": str(main),
        "sourceSha256": hashlib.sha256(original).hexdigest(),
        "visualSha256": hashlib.sha256(result).hexdigest()}
    (output / "provenance.json").write_text(json.dumps(receipt, indent=2) + "\n")

if __name__ == "__main__":
    prepare(AIR / "build/mobile-lab/assets")
