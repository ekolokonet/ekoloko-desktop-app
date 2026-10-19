"""Read-only iOS AOT audit; optionally extract packed SWFs for ADT compilation.

Does not sign, upload, edit loaders, or modify the development build. Extracting
code makes it visible to ADT but does NOT establish compatible runtime loading.
"""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import struct
import sys
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from swf import unpack


def inspect_swf(data):
    version, _, tags = unpack(data)
    abc = sum(kind in (72, 82) for kind, _ in tags)
    symbols = []
    legacy = any(kind in (12, 59) for kind, _ in tags)
    for kind, payload in tags:
        if kind == 76:
            count = struct.unpack_from('<H', payload)[0]
            cursor = 2
            for _ in range(count):
                cursor += 2
                end = payload.index(b'\0', cursor)
                symbols.append(payload[cursor:end].decode('utf-8'))
                cursor = end + 1
    return {'swfVersion': version, 'abcBlocks': abc,
            'topLevelAVM1Actions': legacy, 'symbolClasses': symbols}


def audit(source, output, extract=False):
    output.mkdir(parents=True, exist_ok=True)
    receipt = json.loads((source / 'build-receipt.json').read_text())
    for name, key in [('EkolokoAIR.swf','hostSha256'), ('air-manifest.zlib','manifestSha256'), ('air-assets.pack','packSha256')]:
        with (source/name).open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest() if hasattr(hashlib,'file_digest') else hashlib.sha256(stream.read()).hexdigest()
        if digest != receipt[key]:
            raise ValueError('Build receipt mismatch: '+name)
    manifest = json.loads(zlib.decompress((source/'air-manifest.zlib').read_bytes()))
    objects = {}
    with (source/'air-assets.pack').open('rb') as pack:
        for path, entry in manifest['assets'].items():
            digest = entry['sha256']
            if digest in objects:
                objects[digest]['paths'].append(path)
                continue
            pack.seek(entry['offset'])
            data = pack.read(entry['length'])
            if hashlib.sha256(data).hexdigest() != digest:
                raise ValueError('Packed asset digest mismatch: '+path)
            if data[:3] not in (b'FWS',b'CWS',b'ZWS'):
                objects[digest] = {'paths':[path], 'length':len(data), 'kind':'data'}
                continue
            record = dict(inspect_swf(data), paths=[path], length=len(data), kind='swf')
            if extract:
                target = output/'aot-swfs'/(digest+'.swf')
                target.parent.mkdir(exist_ok=True)
                if not target.exists() or hashlib.sha256(target.read_bytes()).hexdigest() != digest:
                    target.write_bytes(data)
                record['extractedPath'] = str(target.resolve())
            objects[digest] = record
    symbols = defaultdict(set)
    for digest, record in objects.items():
        for symbol in record.get('symbolClasses',[]):
            symbols[symbol].add(digest)
    duplicates = {name: sorted(values) for name,values in symbols.items() if len(values)>1}
    code = [record for record in objects.values() if record.get('abcBlocks',0)]
    result = {
      'appStoreReady':False, 'sourceBuild':str(source.resolve()),
      'manifestSha256':receipt['manifestSha256'], 'mainVersion':manifest.get('mainVersion'),
      'assetPaths':len(manifest['assets']), 'uniqueObjects':len(objects),
      'codeBearingSWFs':len(code), 'codeBearingPaths':sum(len(r['paths']) for r in code),
      'duplicateSymbolClassNames':len(duplicates),
      'blockers':['Packed SWFs must be exposed to ADT AOT compilation.',
                  'Current loaders use loadBytes and child ApplicationDomains; a packaged main-domain loading path is required.',
                  'Duplicate SymbolClass bindings require compatibility review before flattening domains.',
                  'Signing and real-device AOT gameplay validation have not been completed.'],
      'duplicateSymbolClasses':duplicates, 'objects':objects}
    (output/'aot-preflight.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({key:value for key,value in result.items() if key not in ('objects','duplicateSymbolClasses')},indent=2))
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,default=Path(__file__).resolve().parents[1]/'build/mobile-phone')
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--extract',action='store_true')
    args=parser.parse_args()
    audit(args.source,args.output,args.extract)

if __name__=='__main__': main()
