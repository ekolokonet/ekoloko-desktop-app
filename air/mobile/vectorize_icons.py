"""Trace approved PNG artwork into editable paths; never embed bitmaps in SVG.

Run with air/build/vector-tools/bin/python (vtracer 0.6.15, Pillow 12.3.0).
Original generated PNGs are retained unchanged next to vector/.
"""
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageFilter
import vtracer

ROOT = Path(__file__).resolve().parent
ICONS = ROOT / "assets/icons"
NAMES = ["overview", "follow", "rotate", "opacity", "zoom-in", "zoom-out",
         "older", "newer", "close", "messages"]
PARAMETERS = dict(colormode="color", hierarchical="stacked", mode="spline",
    filter_speckle=12, color_precision=6, layer_difference=12,
    corner_threshold=60, length_threshold=4, max_iterations=10,
    splice_threshold=45, path_precision=2)

def main():
    output = ICONS / "vector"
    output.mkdir(exist_ok=True)
    temporary = ROOT.parent / "build/vector-input"
    temporary.mkdir(exist_ok=True)
    receipt = {"tool": "vtracer 0.6.15", "parameters": PARAMETERS, "icons": {}}
    for name in NAMES:
        source = ICONS / (name + ".png")
        if not source.exists():
            continue
        art = Image.open(source).convert("RGBA")
        # Suppress low-alpha generation noise, then crop all tiles consistently.
        alpha = art.getchannel("A").point(lambda a: 255 if a >= 160 else 0)
        alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))
        art.putalpha(alpha)
        bounds = alpha.getbbox()
        art = art.crop(bounds)
        art.thumbnail((512, 512), Image.Resampling.LANCZOS)
        art.putalpha(art.getchannel("A").point(lambda a: 255 if a >= 128 else 0))
        normalized = temporary / (name + ".png")
        art.save(normalized)
        target = output / (name + ".svg")
        # Positional arguments avoid a PyO3 keyword-call crash on Python 3.14.
        vtracer.convert_image_to_svg_py(str(normalized), str(target), *PARAMETERS.values())
        receipt["icons"][name] = {"sourceSha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "vectorSha256": hashlib.sha256(target.read_bytes()).hexdigest(),
            "sourceBounds": bounds, "traceSize": art.size,
            "paths": target.read_text().count("<path")}
        print(name, receipt["icons"][name]["paths"], "paths", target.stat().st_size, "bytes")
    (output / "provenance.json").write_text(json.dumps(receipt, indent=2) + "\n")

if __name__ == "__main__":
    main()
