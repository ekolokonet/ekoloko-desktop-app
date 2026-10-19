"""Compile and replace only the generated adapter ABC, preserving all game ABCs.

This writes isolated candidate files. It never changes the interpreter templates.
"""
import argparse,hashlib,json,os,shutil,subprocess,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from swf import unpack,pack,abc_parts,adapt_abc
from prepare_aot_catalog import abc_classes
from prepare_aot_item_prototype import rename_abc

def replace_adapter(data,template):
 version,header,tags=unpack(data);template_blocks=[v for k,v in unpack(template)[2] if k==82]
 if len(template_blocks)!=1:raise ValueError('Expected one compiled adapter ABC')
 result=[];count=0
 for kind,payload in tags:
  if kind==82:
   prefix,abc=abc_parts(payload);names={x['name'] for x in abc_classes(abc)};roots=[n for n in names if n.startswith('org.ekoloko.air.compat.') and n.endswith('.AssetRoot')]
   if roots:
    if len(roots)!=1 or not all(n.startswith('org.ekoloko.air.compat.') or n.startswith('Adapters_') for n in names):raise ValueError('Mixed adapter/game ABC')
    namespace=roots[0].rsplit('.',1)[0];anchors=[n for n in names if n.startswith('Adapters_')]
    if len(anchors)!=1:raise ValueError('Adapter anchor not isolated')
    # Extract the existing generated AssetRoot constructor name from its ABC.
    # The replacement keeps every string except its template-specific origin.
    from swf import Reader
    import struct
    r=Reader(abc);minor,major=struct.unpack('<HH',r.take(4))
    for _ in range(2):
     for _ in range(max(0,r.num()-1)):r.num()
    r.take(max(0,r.num()-1)*8)
    if major>=47:r.take(max(0,r.num()-1)*4)
    strings=['']+[r.take(r.num()).decode(errors='strict') for _ in range(max(0,r.num()-1))]
    for _ in range(max(0,r.num()-1)):r.take(1);r.num()
    for _ in range(max(0,r.num()-1)):
     for _ in range(r.num()):r.num()
    for _ in range(max(0,r.num()-1)):
     name_kind=r.take(1)[0]
     if name_kind in (7,13,9,14):r.num();r.num()
     elif name_kind in (15,16,27,28):r.num()
     elif name_kind==29:
      r.num()
      for _ in range(r.num()):r.num()
     elif name_kind not in (17,18):raise ValueError('Unexpected adapter multiname')
    from prepare_aot_private_globals import usage_after_pool
    _,_,literals,_style_value_pairs=usage_after_pool(abc[r.pos:],set(),{})
    documents=sorted({strings[i] for i in literals if strings[i] in {'ItemMC','NpcMC'} or strings[i].startswith('ItemMC_') or strings[i].startswith('NpcMC_')})
    if len(documents)!=1:raise ValueError('Ambiguous adapter document string '+repr(documents))
    newprefix,newabc=abc_parts(template_blocks[0]);newabc,_=adapt_abc(newabc,namespace,template=True,document_class=documents[0]);newabc,anchor_changes=rename_abc(newabc,b'Adapters',anchors[0].encode())
    if anchor_changes!=1 or {c['name'] for c in abc_classes(newabc)}!=names:raise ValueError('Adapter class contract changed')
    payload=newprefix+newabc;count+=1
  result.append((kind,payload))
 if count>1:raise ValueError('Multiple generated adapters')
 if [k for k,_ in result]!=[k for k,_ in tags]:raise ValueError('SWF tag order changed')
 return pack(version,header,result),count

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--candidate',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output=a.output.resolve();a.output.mkdir(parents=True,exist_ok=False);(a.output/'compiled-content').mkdir()
 mobile=Path(__file__).resolve().parent;air=mobile.parent;sdk=Path('/Volumes/T9/AIR/sdks/AIRSDK_51.4.1');env=dict(os.environ,JAVA_HOME='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home')
 adapter_source=a.output/'adapter-source';shutil.copytree(air/'adapters',adapter_source,ignore=shutil.ignore_patterns('._*'))
 for path in (mobile/'aot-adapters').rglob('*.as'):
  if path.name.startswith('._'):continue
  target=adapter_source/path.relative_to(mobile/'aot-adapters');target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(path,target)
 subprocess.run([str(sdk/'bin/amxmlc'),'-source-path+='+str(adapter_source),'-output='+str(a.output/'adapters.swf'),str(adapter_source/'Adapters.as')],env=env,check=True)
 template=(a.output/'adapters.swf').read_bytes();source=json.loads((a.candidate/'candidate.json').read_text());count=0
 for digest,row in source['objects'].items():
  data=(a.candidate/'compiled-content'/(digest+'.swf')).read_bytes();output,n=replace_adapter(data,template);count+=n;(a.output/'compiled-content'/(digest+'.swf')).write_bytes(output);row['adapterReplaced']=bool(n);row['outputSha256']=hashlib.sha256(output).hexdigest()
 source['aotAdapterCount']=count;source['aotAdapterTemplateSha256']=hashlib.sha256(template).hexdigest();(a.output/'candidate.json').write_text(json.dumps(source,indent=2)+'\n');print('AOT_ADAPTERS_PREPARED',count)
if __name__=='__main__':main()
