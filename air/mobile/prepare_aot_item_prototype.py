"""Isolated ItemMC symbol-isolation prototype, not a release transformation.

Only exact ItemMC string-pool entries and its SymbolClass binding change. This
also updates the generated AssetRoot's internal getDefinition lookup; callers
continue using content.constructor/getMC() without knowing the private name.
No Main, shared engine classes, method bytecode or timeline records are edited.
"""
import hashlib
from pathlib import Path
import struct
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from swf import Reader, abc_parts, pack, u30, unpack


def rename_abc(data, old, new):
    reader=Reader(data)
    minor,major=struct.unpack('<HH',reader.take(4))
    if minor!=16 or major not in (46,47):raise ValueError('Unsupported ABC version')
    for _ in range(2):
        for _ in range(max(0,reader.num()-1)):reader.num()
    reader.take(max(0,reader.num()-1)*8)
    if major>=47:reader.take(max(0,reader.num()-1)*4)
    start=reader.pos;count=reader.num();strings=[];changes=0
    for _ in range(max(0,count-1)):
        value=reader.take(reader.num())
        if value==old: value=new;changes+=1
        strings.append(value)
    suffix=data[reader.pos:]
    return data[:start]+u30(count)+b''.join(u30(len(v))+v for v in strings)+suffix,changes


def namespace_item_document(data):
    identifier=hashlib.sha256(data).hexdigest()[:24]
    name=('ItemMC_'+identifier).encode()
    version,header,tags=unpack(data)
    roots=[];renamed=0;result=[];constant_changes=0
    for kind,payload in tags:
        if kind==76:
            cursor=2;entries=[]
            for _ in range(struct.unpack_from('<H',payload)[0]):
                charid=struct.unpack_from('<H',payload,cursor)[0];cursor+=2
                end=payload.index(b'\0',cursor);symbol=payload[cursor:end];cursor=end+1
                if charid==0:roots.append(symbol)
                if symbol==b'ItemMC':
                    if charid==0:raise ValueError('Expected promoted item library sprite')
                    symbol=name;renamed+=1
                entries.append(struct.pack('<H',charid)+symbol+b'\0')
            payload=struct.pack('<H',len(entries))+b''.join(entries)
        elif kind==82:
            prefix,abc=abc_parts(payload);abc,n=rename_abc(abc,b'ItemMC',name)
            constant_changes+=n;payload=prefix+abc
        elif kind==72:
            raise ValueError('Legacy ABC is outside this prototype')
        result.append((kind,payload))
    if renamed!=1 or len(roots)!=1 or not roots[0].startswith(b'org.ekoloko.air.compat.') or not roots[0].endswith(b'.AssetRoot'):
        raise ValueError('Only a promoted isolated ItemMC wrapper is supported')
    if constant_changes<2:raise ValueError('Expected both item class and wrapper lookup changes')
    output=pack(version,header,result)
    return output,{'originalClass':'ItemMC','privateClass':name.decode(),'constantPoolReplacements':constant_changes,
                   'sourceSha256':hashlib.sha256(data).hexdigest(),'outputSha256':hashlib.sha256(output).hexdigest()}

if __name__=='__main__':
    import argparse,json
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('source',type=Path);parser.add_argument('output',type=Path)
    args=parser.parse_args();data,receipt=namespace_item_document(args.source.read_bytes());args.output.write_bytes(data)
    print(json.dumps(receipt,indent=2))
