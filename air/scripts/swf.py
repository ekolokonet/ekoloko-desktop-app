"""Lossless AVM2 constant-pool adaptation for the AIR-only asset bundle.

Runtime adapter namespaces and the legacy isPlaying member are remapped in
constant pools. ItemMC/NpcMC root timelines become cloneable library sprites.
Method bytecode, game commands, crypto constants and timeline records retain
their bytes; the pinned Shell lifecycle/identity patch is applied separately.
"""
import lzma
import struct
import zlib

ADAPTERS = {("flash.display", "Loader"), ("flash.net", "URLLoader"),
            ("flash.external", "ExternalInterface"), ("flash.system", "Security"),
            ("flash.media", "Sound"), ("flash.net", "navigateToURL")}
TEMPLATE_NS = "org.ekoloko.air.compat.template"
LEGACY_MEMBERS = {"isPlaying": "ekolokoLegacyIsPlaying"}


def u30(value):
    if not 0 <= value <= 0x3fffffff:
        raise ValueError("Invalid U30")
    out = bytearray()
    while value >= 128:
        out.append((value & 127) | 128)
        value >>= 7
    out.append(value)
    return bytes(out)


class Reader:
    def __init__(self, data):
        self.data, self.pos = data, 0

    def take(self, size):
        end = self.pos + size
        if end > len(self.data):
            raise ValueError("Truncated SWF/ABC")
        result = self.data[self.pos:end]
        self.pos = end
        return result

    def num(self):
        value = 0
        for shift in range(0, 35, 7):
            part = self.take(1)[0]
            value |= (part & 127) << shift
            if not part & 128:
                return value
        raise ValueError("Invalid ABC integer")


def adapt_abc(data, namespace, template=False, document_class="ItemMC"):
    r = Reader(data)
    minor, major = struct.unpack("<HH", r.take(4))
    if minor != 16 or major not in (46, 47):
        raise ValueError("Unsupported ABC version")
    for _ in range(2):
        for _ in range(max(0, r.num() - 1)):
            r.num()
    r.take(max(0, r.num() - 1) * 8)
    if major >= 47:
        r.take(max(0, r.num() - 1) * 4)
    string_start = r.pos
    strings = [b""]
    for _ in range(max(0, r.num() - 1)):
        strings.append(r.take(r.num()))
    if template:
        strings = [document_class.encode() if s == b"__EKOLOKO_DOCUMENT_CLASS__" else s for s in strings]
    namespaces = [None]
    for _ in range(max(0, r.num() - 1)):
        namespaces.append((r.take(1)[0], r.num()))
    namespace_sets = [None]
    for _ in range(max(0, r.num() - 1)):
        namespace_sets.append([r.num() for _ in range(r.num())])
    count = r.num()
    multinames, changes = [], 0
    original_string_count = len(strings)
    strings.append(namespace.encode())
    namespaces.append((0x16, len(strings) - 1))
    new_ns = len(namespaces) - 1
    for _ in range(max(0, count - 1)):
        start = r.pos
        kind = r.take(1)[0]
        if kind in (0x07, 0x0d):
            ns, name = r.num(), r.num()
            if not 0 < ns < new_ns or name >= original_string_count:
                raise ValueError("Invalid QName")
            uri = strings[namespaces[ns][1]].decode("utf-8")
            local = strings[name].decode("utf-8")
            if not template and local in LEGACY_MEMBERS:
                # The browser-only game uses its own isPlaying() method.
                # AIR adds a MovieClip.isPlaying getter, making that class
                # unverifiable. Rename game traits and static call sites as
                # one ABI change; method bodies and their logic stay intact.
                strings.append(LEGACY_MEMBERS[local].encode())
                multinames.append(bytes([kind]) + u30(ns) + u30(len(strings) - 1))
                changes += 1
                continue
            if (template and uri == TEMPLATE_NS) or (not template and (uri, local) in ADAPTERS):
                multinames.append(bytes([kind]) + u30(new_ns) + u30(name))
                changes += 1
                continue
        elif kind in (0x0f, 0x10):
            name = r.num()
            local = strings[name].decode("utf-8")
            if not template and local in LEGACY_MEMBERS:
                strings.append(LEGACY_MEMBERS[local].encode())
                multinames.append(bytes([kind]) + u30(len(strings) - 1))
                changes += 1
                continue
        elif kind in (0x1b, 0x1c):
            r.num()
        elif kind in (0x09, 0x0e):
            name, ns_set = r.num(), r.num()
            if name >= original_string_count or not 0 < ns_set < len(namespace_sets):
                raise ValueError("Invalid Multiname")
            local = strings[name].decode("utf-8")
            if not template and local in LEGACY_MEMBERS:
                strings.append(LEGACY_MEMBERS[local].encode())
                multinames.append(bytes([kind]) + u30(len(strings) - 1) + u30(ns_set))
                changes += 1
                continue
            if not template:
                # FFDec-authored assets often use Multiname namespace sets
                # instead of QName for imports. Change only this class lookup's
                # matching namespace; shared sets used by other names stay intact.
                mapped = []
                for ns in namespace_sets[ns_set]:
                    if not 0 < ns < new_ns:
                        raise ValueError("Invalid namespace set")
                    uri = strings[namespaces[ns][1]].decode("utf-8")
                    mapped.append(new_ns if (uri, local) in ADAPTERS else ns)
                if mapped != namespace_sets[ns_set]:
                    if mapped not in namespace_sets:
                        namespace_sets.append(mapped)
                    multinames.append(bytes([kind]) + u30(name) + u30(namespace_sets.index(mapped)))
                    changes += 1
                    continue
        elif kind == 0x1d:
            r.num()
            for _ in range(r.num()):
                r.num()
        elif kind not in (0x11, 0x12):
            raise ValueError(f"Unsupported ABC multiname: {kind}")
        multinames.append(data[start:r.pos])
    if not changes:
        return data, 0
    # Namespace sets can reference a template namespace without a QName.
    if template:
        namespaces = [(kind, len(strings) - 1) if strings[index].decode("utf-8") == TEMPLATE_NS else (kind, index)
                      for kind, index in namespaces[1:]]
        namespaces.insert(0, None)
    result = data[:string_start] + u30(len(strings))
    result += b"".join(u30(len(s)) + s for s in strings[1:])
    result += u30(len(namespaces)) + b"".join(bytes([kind]) + u30(index) for kind, index in namespaces[1:])
    result += u30(len(namespace_sets)) + b"".join(u30(len(s)) + b"".join(u30(n) for n in s) for s in namespace_sets[1:])
    result += u30(count) + b"".join(multinames) + data[r.pos:]
    return result, changes


def unpack(data):
    signature = data[:3]
    if signature == b"FWS":
        body = data[8:]
    elif signature == b"CWS":
        body = zlib.decompress(data[8:])
    elif signature == b"ZWS":
        props = data[12:17]
        size = struct.unpack_from("<I", data, 4)[0] - 8
        body = lzma.decompress(props + struct.pack("<Q", size) + data[17:], format=lzma.FORMAT_ALONE)
    else:
        raise ValueError("Not a SWF")
    if len(body) + 8 != struct.unpack_from("<I", data, 4)[0]:
        raise ValueError("SWF size mismatch")
    rect_size = ((body[0] >> 3) * 4 + 5 + 7) // 8
    pos = rect_size + 4
    header, tags = body[:pos], []
    while pos < len(body):
        encoded = struct.unpack_from("<H", body, pos)[0]
        pos += 2
        kind, size = encoded >> 6, encoded & 63
        if size == 63:
            size = struct.unpack_from("<I", body, pos)[0]
            pos += 4
        if pos + size > len(body):
            raise ValueError("Truncated SWF tag")
        tags.append((kind, body[pos:pos + size]))
        pos += size
        if kind == 0:
            if pos != len(body):
                raise ValueError("Trailing SWF bytes")
            break
    return data[3], header, tags


def pack(version, header, tags):
    body = bytearray(header)
    for kind, value in tags:
        size = len(value)
        body += struct.pack("<H", (kind << 6) | min(size, 63))
        if size >= 63:
            body += struct.pack("<I", size)
        body += value
    return b"CWS" + bytes([version]) + struct.pack("<I", len(body) + 8) + zlib.compress(body, 9)


def abc_parts(tag):
    offset = tag.index(b"\0", 4) + 1
    return tag[:offset], tag[offset:]


def encode_tag(kind, value):
    size = len(value)
    return struct.pack("<H", (kind << 6) | min(size, 63)) + (struct.pack("<I", size) if size >= 63 else b"") + value


def promote_item_timeline(header, tags, namespace):
    """Bind a known cloned document class to its original library timeline.

    Root control records move byte-for-byte into DefineSprite. Graphics,
    nested sprites, frame scripts and item classes retain their original bytes.
    No network-delivered or unreviewed code is accepted by this adaptation.
    """
    root_binding = None
    symbols = []
    maximum = 0
    definition_tags = {2, 6, 7, 10, 11, 14, 20, 21, 22, 32, 33, 34, 35, 36, 37, 39, 46, 48, 60, 75, 83, 84, 87, 90, 91}
    for kind, value in tags:
        if kind in definition_tags:
            maximum = max(maximum, struct.unpack_from("<H", value)[0])
        if kind != 76:
            continue
        pos = 2
        entries = []
        for _ in range(struct.unpack_from("<H", value)[0]):
            identifier = struct.unpack_from("<H", value, pos)[0]
            pos += 2
            end = value.index(b"\0", pos)
            name = value[pos:end]
            pos = end + 1
            if identifier == 0:
                root_binding = name.decode() if name in {b"ItemMC", b"NpcMC"} else None
            entries.append((identifier, name))
        symbols.extend(entries)
    if not root_binding:
        return header, tags, None
    sprite_id = maximum + 1
    if sprite_id > 65535:
        raise ValueError("No character ID available for document timeline")
    controls = {1, 4, 5, 15, 18, 19, 26, 28, 43, 45, 61, 70, 89, 94}
    timeline = [(kind, value) for kind, value in tags if kind in controls]
    frames = struct.unpack_from("<H", header, len(header) - 2)[0]
    if sum(kind == 1 for kind, _ in timeline) != frames:
        raise ValueError("Document frame count differs from its timeline")
    # AS3-only timeline: do not reinterpret legacy ActionScript records.
    if any(kind in {12, 59} for kind, _ in tags):
        raise ValueError("Unsupported document legacy action record")
    output = [(kind, value) for kind, value in tags if kind not in controls | {0, 76, 86}]
    sprite = struct.pack("<HH", sprite_id, frames) + b"".join(encode_tag(k, v) for k, v in timeline) + b"\0\0"
    output.append((39, sprite))
    bindings = [(sprite_id if identifier == 0 else identifier, name) for identifier, name in symbols]
    bindings.append((0, (namespace + ".AssetRoot").encode()))
    output.append((76, struct.pack("<H", len(bindings)) + b"".join(struct.pack("<H", i) + name + b"\0" for i, name in bindings)))
    output.extend([(1, b""), (0, b"")])
    return header[:-2] + struct.pack("<H", 1), output, root_binding


def adapt_swf(data, adapter_swf, namespace):
    version, header, tags = unpack(data)
    header, tags, promoted = promote_item_timeline(header, tags, namespace)
    output, count = [], 0
    for kind, value in tags:
        if kind == 82:
            prefix, abc = abc_parts(value)
            adapted, changed = adapt_abc(abc, namespace)
            value = prefix + adapted
            count += changed
        output.append((kind, value))
    if not count and not promoted:
        return data, 0
    _, _, adapter_tags = unpack(adapter_swf)
    injected = []
    for kind, value in adapter_tags:
        if kind == 82:
            prefix, abc = abc_parts(value)
            adapted, _ = adapt_abc(abc, namespace, template=True, document_class=promoted or "ItemMC")
            injected.append((82, prefix + adapted))
    index = next(i for i, (kind, _) in enumerate(output) if kind == 82)
    output[index:index] = injected
    return pack(version, header, output), count + int(bool(promoted))
