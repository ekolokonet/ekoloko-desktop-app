"""Compile traced vector paths with the installed AIR SDK, without rasterization."""
import os
import re
import subprocess
import sys
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
NAMES = {"overview":"Overview", "follow":"Follow", "rotate":"Rotate", "opacity":"Opacity",
         "zoom-in":"ZoomIn", "zoom-out":"ZoomOut", "older":"Older", "newer":"Newer",
         "close":"Close", "messages":"Messages"}

def compile_icons():
    sdk = Path(os.environ.get("AIR_SDK_HOME", "/Volumes/T9/AIR/sdks/AIRSDK_51.3.4"))
    java = Path(os.environ.get("JAVA_HOME", "/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home"))
    build = ROOT.parent / "build/vector-compiler"
    build.mkdir(parents=True, exist_ok=True)
    paths = []
    for stem, name in NAMES.items():
        svg = ET.parse(ROOT / "assets/icons/vector" / (stem+".svg")).getroot()
        graphic = ET.Element("Graphic", {"xmlns":"http://ns.adobe.com/fxg/2008", "version":"2.0",
            "viewWidth":svg.attrib["width"], "viewHeight":svg.attrib["height"]})
        for node in svg:
            if not node.tag.endswith("}path"):
                raise ValueError("Only traced paths are supported: " + node.tag)
            transform = re.fullmatch(r"translate\(([-.\d]+),([-.\d]+)\)", node.attrib.get("transform", "translate(0,0)"))
            if not transform:
                raise ValueError("Unsupported path transform")
            path = ET.SubElement(graphic, "Path", {"data":node.attrib["d"], "x":transform[1], "y":transform[2], "winding":"nonZero"})
            fill = ET.SubElement(path, "fill")
            ET.SubElement(fill, "SolidColor", {"color":node.attrib["fill"]})
        target = ROOT / "assets/icons/vector" / (name+".fxg")
        ET.ElementTree(graphic).write(target, encoding="utf-8", xml_declaration=True)
        paths.append(str(target))
    classpath = str(sdk / "lib/*")
    subprocess.run([str(java / "bin/javac"), "-cp", classpath, "-d", str(build), str(ROOT / "VectorIconCompiler.java")], check=True)
    library = ROOT / "assets/icons/MobileActionIcons.swf"
    subprocess.run([str(java / "bin/java"), "-cp", str(build)+os.pathsep+classpath,
        "VectorIconCompiler", str(library), *paths], check=True)
    sys.path.insert(0, str(ROOT.parent / "scripts"))
    from swf import unpack
    _, _, tags = unpack(library.read_bytes())
    bitmap = {6, 20, 21, 35, 36, 90}
    assert not any(kind in bitmap for kind, _ in tags), "Unexpected bitmap in vector library"
    assert sum(kind in {2, 22, 32, 83} for kind, _ in tags) > 0, "No vector shapes"
    print("VECTOR_SHAPES_NO_BITMAPS_PASS")

if __name__ == "__main__":
    compile_icons()
