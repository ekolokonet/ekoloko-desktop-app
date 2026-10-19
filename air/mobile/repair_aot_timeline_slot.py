"""Exact-source GLS40604 timeline slot repair; never unseal a class."""
import hashlib,struct,sys,json
from pathlib import Path
root=Path(__file__).resolve().parent.parent;sys.path[:0]=[str(root/'scripts')]
from swf import Reader,u30,unpack,pack,abc_parts
# Confirmed missing named timeline field; see full-frame slot regression.
SOURCE_DIGESTS={'8f6e94f26fd7a14b98d3d19c7c22e7cdbb81c4c644273ff7eb3e24604fe69ba4','e27e7f469f24b8ffff4909e27c59a1da14cec58988f77a4a59c33fdb17b89af2'}
def repair_abc(data):
 r=Reader(data);minor,major=struct.unpack('<HH',r.take(4));assert minor==16 and major in (46,47)
 for _ in range(2):
  for _ in range(max(0,r.num()-1)):r.num()
 r.take(max(0,r.num()-1)*8)
 if major>=47:r.take(max(0,r.num()-1)*4)
 strings=[b'']+[r.take(r.num()) for _ in range(max(0,r.num()-1))];ns=[None]
 for _ in range(max(0,r.num()-1)):ns.append((r.take(1)[0],r.num()))
 for _ in range(max(0,r.num()-1)):
  for _ in range(r.num()):r.num()
 pool_start=r.pos;count=r.num();pool_body=r.pos;names=[None];raw=[]
 for _ in range(max(0,count-1)):
  start=r.pos;kind=r.take(1)[0];name=None
  if kind in (7,13):
   n,s=r.num(),r.num();name=(strings[ns[n][1]].decode()+'.' if strings[ns[n][1]] else '')+strings[s].decode()
  elif kind in (9,14,15,16):r.num();r.num() if kind in (9,14) else None
  elif kind in (27,28):r.num()
  elif kind==29:
   r.num()
   for _ in range(r.num()):r.num()
  elif kind not in (17,18):raise ValueError('Unsupported multiname')
  names.append(name);raw.append(data[start:r.pos])
 pool_end=r.pos
 if 'ItemMC' not in names:return data,None
 bubble_idx=names.index('bubble');movie_idx=names.index('flash.display.MovieClip');new_name=raw[bubble_idx-1]
 assert new_name[0]==7
 for _ in range(r.num()):
  argc=r.num();r.num()
  for _ in range(argc):r.num()
  r.num();flags=r.take(1)[0]
  if flags&8:
   for _ in range(r.num()):r.num();r.take(1)
  if flags&128:
   for _ in range(argc):r.num()
 for _ in range(r.num()):
  r.num()
  for _ in range(r.num()*2):r.num()
 edits=[];detail=None
 for _ in range(r.num()):
  name=r.num();superclass=r.num();flags=r.take(1)[0]
  if flags&8:r.num()
  for _ in range(r.num()):r.num()
  r.num();traits_start=r.pos;traits_count=r.num();traits_body=r.pos;traits=[];slots=[]
  for _ in range(traits_count):
   tname=r.num();tf=r.take(1)[0];kind=tf&15;traits.append(names[tname])
   if kind in (0,6):
    slots.append(r.num());r.num()
    if r.num():r.take(1)
   elif kind in (1,2,3,4,5):r.num();r.num()
   else:raise ValueError('Unsupported trait')
   if tf&64:
    for _ in range(r.num()):r.num()
  if names[name]=='ItemMC':
   if not flags&1 or superclass!=movie_idx or 'bubble' in traits:raise ValueError('Unexpected ItemMC contract')
   slot=0;trait=u30(count)+b'\0'+u30(slot)+u30(movie_idx)+u30(0)
   edits.append((traits_start,r.pos,u30(traits_count+1)+data[traits_body:r.pos]+trait));detail={'class':'ItemMC','field':'bubble','type':'flash.display.MovieClip','slotId':slot,'sealed':True,'existingTraits':traits,'oldMultinameCount':count,'newMultinameIndex':count,'instanceTraitsEnd':r.pos}
 if detail is None:raise ValueError('ItemMC QName without class')
 edits.append((pool_start,pool_end,u30(count+1)+data[pool_body:pool_end]+new_name))
 out=data
 for start,end,replacement in sorted(edits,reverse=True):out=out[:start]+replacement+out[end:]
 assert out.endswith(data[detail["instanceTraitsEnd"]:])
 return out,detail

def repair(data):
 sha=hashlib.sha256(data).hexdigest()
 if sha not in SOURCE_DIGESTS:raise ValueError('Unreviewed GLS40604 source digest')
 v,h,tags=unpack(data);result=[];records=[]
 for kind,payload in tags:
  if kind==82:
   prefix,abc=abc_parts(payload);abc,record=repair_abc(abc);payload=prefix+abc
   if record:records.append(record)
  result.append((kind,payload))
 if len(records)!=1:raise ValueError('Expected exactly one ItemMC slot repair')
 assert [(k,b) for k,b in tags if k!=82]==[(k,b) for k,b in result if k!=82]
 output=pack(v,h,result);return output,{'sourceSha256':sha,'outputSha256':hashlib.sha256(output).hexdigest(),'repair':records[0],'classFlagsUnchanged':True,'existingMethodsUnchanged':True,'timelineTagsUnchanged':True}
