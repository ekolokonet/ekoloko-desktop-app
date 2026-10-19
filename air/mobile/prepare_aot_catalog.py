"""Fail-closed, isolated AOT catalog preparation from a digest-checked content pack.

Enumerates every ABC class, not only exported display symbols. Only the already
validated promoted ItemMC transform is applied, and only where ItemMC is the
sole colliding class in the object. Remaining collisions are explicit blockers.
This never updates the release manifest, active loaders, signing, or deployment.
"""
import argparse
from collections import defaultdict, Counter
import hashlib
import json
from pathlib import Path
import struct
import sys
import zlib
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from swf import Reader, unpack, abc_parts, pack
from prepare_aot_item_prototype import namespace_item_document, rename_abc


def abc_classes(data):
    r = Reader(data)
    minor, major = struct.unpack('<HH', r.take(4))
    if minor != 16 or major not in (46, 47):
        raise ValueError('Unsupported ABC version')
    for _ in range(2):
        for _ in range(max(0, r.num() - 1)): r.num()
    r.take(max(0, r.num() - 1) * 8)
    if major >= 47: r.take(max(0, r.num() - 1) * 4)
    strings = [b'']
    for _ in range(max(0, r.num() - 1)): strings.append(r.take(r.num()))
    namespaces = [None]
    for _ in range(max(0, r.num() - 1)): namespaces.append((r.take(1)[0], r.num()))
    for _ in range(max(0, r.num() - 1)):
        for _ in range(r.num()): r.num()
    names = [None]
    for _ in range(max(0, r.num() - 1)):
        kind = r.take(1)[0]
        if kind in (7, 13): names.append((r.num(), r.num()))
        elif kind in (15, 16, 27, 28): r.num(); names.append(None)
        elif kind in (9, 14): r.num(); r.num(); names.append(None)
        elif kind == 29:
            r.num()
            for _ in range(r.num()): r.num()
            names.append(None)
        elif kind in (17, 18): names.append(None)
        else: raise ValueError('Unsupported multiname '+str(kind))
    for _ in range(r.num()):
        count = r.num(); r.num()
        for _ in range(count): r.num()
        r.num(); flags = r.take(1)[0]
        if flags & 8:
            for _ in range(r.num()): r.num(); r.take(1)
        if flags & 128:
            for _ in range(count): r.num()
    for _ in range(r.num()):
        r.num(); count = r.num()
        for _ in range(count * 2): r.num()
    def skip_traits():
        for _ in range(r.num()):
            r.num(); flags = r.take(1)[0]; kind = flags & 15
            if kind in (0, 6):
                r.num(); r.num()
                if r.num(): r.take(1)
            elif kind in (1, 2, 3, 4, 5): r.num(); r.num()
            else: raise ValueError('Unsupported trait '+str(kind))
            if flags & 64:
                for _ in range(r.num()): r.num()
    result = []
    for _ in range(r.num()):
        name = names[r.num()]
        if name is None: raise ValueError('Class is not QName')
        ns, local = name
        ns_kind, uri_index = namespaces[ns]
        uri = strings[uri_index].decode('utf-8'); local = strings[local].decode('utf-8')
        result.append({'name': (uri+'.' if uri else '')+local, 'namespaceKind': ns_kind})
        r.num(); flags = r.take(1)[0]
        if flags & 8: r.num()
        for _ in range(r.num()): r.num()
        r.num(); skip_traits()
    return result


def inspect(data):
    version, _, tags = unpack(data)
    classes = []; symbols = []; legacy = False
    for kind, payload in tags:
        if kind == 82: classes.extend(abc_classes(abc_parts(payload)[1]))
        elif kind == 72: raise ValueError('Legacy ABC unsupported')
        elif kind in (12, 59): legacy = True
        elif kind == 76:
            r = Reader(payload)
            for _ in range(struct.unpack('<H', r.take(2))[0]):
                char_id = struct.unpack('<H', r.take(2))[0]
                end = payload.index(b'\0', r.pos)
                symbols.append({'id': char_id, 'name': r.take(end-r.pos).decode('utf-8')}); r.take(1)
    return {'classes': classes, 'symbols': symbols, 'legacyActions': legacy, 'swfVersion': version}


def isolate_adapter_anchor(data, digest):
    version, header, tags = unpack(data)
    result = []; changed = 0
    replacement = ('Adapters_'+digest[:24]).encode()
    for kind, payload in tags:
        if kind == 82:
            prefix, abc = abc_parts(payload)
            names = {c['name'] for c in abc_classes(abc)}
            if 'Adapters' in names:
                if not all(n == 'Adapters' or n.startswith('org.ekoloko.air.compat.') for n in names):
                    raise ValueError('Adapters anchor is not isolated generated code')
                abc, changes = rename_abc(abc, b'Adapters', replacement)
                if not changes: raise ValueError('Adapter anchor rename failed')
                changed += 1; payload = prefix+abc
        result.append((kind, payload))
    if changed != 1: raise ValueError('Expected exactly one generated adapter anchor')
    return pack(version, header, result), replacement.decode()


def prepare(source, output):
    output.mkdir(parents=True, exist_ok=False)
    (output/'compiled-content').mkdir()
    manifest_bytes = (source/'air-manifest.zlib').read_bytes()
    manifest = json.loads(zlib.decompress(manifest_bytes))
    objects = {}; owners = defaultdict(set)
    with (source/'air-assets.pack').open('rb') as pack:
        for path, entry in manifest['assets'].items():
            digest = entry['sha256']
            if digest in objects:
                objects[digest]['paths'].append(path); continue
            pack.seek(entry['offset']); data = pack.read(entry['length'])
            if hashlib.sha256(data).hexdigest() != digest: raise ValueError('Digest mismatch '+path)
            record = {'paths':[path], 'offset':entry['offset'], 'length':entry['length']}
            if data[:3] in (b'FWS', b'CWS', b'ZWS'):
                record.update(inspect(data))
                for cls in record['classes']: owners[cls['name']].add(digest)
            objects[digest] = record
    duplicate = {name:sorted(values) for name,values in owners.items() if len(values)>1}
    transformed = 0; adapters = 0; blocked = []; index = {}
    with (source/'air-assets.pack').open('rb') as pack:
        for digest, record in objects.items():
            if 'classes' not in record: continue
            collisions = sorted({c['name'] for c in record['classes'] if c['name'] in duplicate})
            record['collidingClasses'] = collisions
            pack.seek(record['offset']); data = pack.read(record['length'])
            expected = {c['name'] for c in record['classes']}
            unresolved = list(collisions)
            if 'Adapters' in unresolved:
                data, private_anchor = isolate_adapter_anchor(data, digest)
                expected.remove('Adapters'); expected.add(private_anchor)
                record['adapterAnchor'] = private_anchor; adapters += 1
                unresolved.remove('Adapters')
            if unresolved == ['ItemMC'] and not record['legacyActions']:
                try:
                    candidate, receipt = namespace_item_document(data)
                    expected.remove('ItemMC'); expected.add(receipt['privateClass'])
                    if {c['name'] for c in inspect(candidate)['classes']} != expected:
                        raise ValueError('Unexpected class change')
                    data = candidate; record['transform'] = receipt; transformed += 1
                    unresolved = []
                except ValueError as error:
                    record['blockedReason'] = str(error)
            if unresolved:
                record.setdefault('blockedReason', 'Unreviewed shared or private class collisions')
                blocked.append(digest)
            record['remainingCollisions'] = unresolved
            record['preparedClasses'] = inspect(data)['classes']
            filename = 'compiled-content/'+digest+'.swf'
            (output/filename).write_bytes(data)
            output_digest = hashlib.sha256(data).hexdigest()
            for path in record['paths']:
                index[path] = {'file':filename, 'sourceSha256':digest, 'preparedSha256':output_digest,
                               'executable':bool(record['classes']), 'blocked':digest in blocked}
    report = {'mainVersion':manifest.get('mainVersion'), 'sourceManifestSha256':hashlib.sha256(manifest_bytes).hexdigest(),
              'transformedItemObjects':transformed, 'isolatedAdapterAnchors':adapters, 'duplicateABCClassNames':len(duplicate),
              'blockedObjects':len(blocked), 'releaseReady':False, 'runtimeTested':False,
              'duplicateABCClasses':duplicate, 'objects':objects}
    (output/'catalog.json').write_text(json.dumps(report,indent=2)+'\n')
    (output/'packaged-index.json').write_text(json.dumps(index,separators=(',',':'))+'\n')
    summary = {k:v for k,v in report.items() if k not in ('duplicateABCClasses','objects')}
    summary['mostFrequentCollisions'] = sorted(((n,len(v)) for n,v in duplicate.items()),key=lambda x:-x[1])[:20]
    (output/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(json.dumps(summary,indent=2))

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();prepare(args.source.resolve(),args.output.resolve())
