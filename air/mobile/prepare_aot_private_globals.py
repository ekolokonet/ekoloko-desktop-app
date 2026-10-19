"""Isolate defined global display classes without renaming public member strings.

This rewrites private global and authored *_fla class names, proven lexical
Multiname references, and matching SymbolClass bindings. Nonlexical uses and
reflected class strings fail closed; named public engine APIs are untouched.
Method bytes are preserved except exact reviewed, same-width style-value operands.
Timeline instructions and public instance/property keys are untouched.
"""
import hashlib, struct, sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from swf import Reader,unpack,pack,abc_parts,u30
from prepare_aot_catalog import abc_classes


# Audited room clickbleItems OPEN_EXTERANL_URL identifiers. These literals
# intentionally retain their exact server-facing values; they are not reflection.
# The complete adapted SWF digest pins the review to these precise source bytes.
REVIEWED_DATA_LITERALS = {
 "49a84a275879fa6387fa55c0aa21ea79d81d4f582c0e796c9115d215df089b40": {"waterEvent"},
 "e5e7a44316c7a70fcaf8d2a95ffda8b069c3d5f53ecc0569441a5053777a3501": {"waterEvent"},
 "8cc159781ffe13815a230490e17caf24244ee8aaf205852cc468955fb5a14c49": {"waterEvent"},
 "cc9840fb74de2d89a8a728c7bf88d05f1d46983a3d4b3d4182647cc29010f730": {"standTeva"},
 "c9607e9580e3254d6b3c2d640c8186a9abf7d6f56835ee97d114453f89374d3c": {"TimeTable"},
 "1af71017b5082b9add9968ec9afad38c566b61596f72dad8fec22c094bdef481": {"NewYears"},
}

def lexical_call_receiver(history, name, argc, static_names, runtime_names):
 """Prove a class coercion receiver without editing instructions or branches.

 Backtrack the receiver's operand-stack slot within this basic block. Unknown
 effects, runtime-name property accesses and computed receiver values reject.
 """
 depth=argc
 for op,args in reversed(history):
  if op in (0x5d,0x5e):
   if depth==0:return args[0]==name
   depth-=1;continue
  if op==0x2a: # dup
   depth=0 if depth<2 else depth-1;continue
  if op==0x2b: # swap
   if depth<2:depth=1-depth
   continue
  if op in {0x20,0x21,0x24,0x25,0x26,0x27,0x28,0x2c,0x2d,0x2e,0x2f,0x31,0x40,0x60,0x62,0x64,0x65,0xd0,0xd1,0xd2,0xd3}:pops,pushes=0,1
  elif op in {0x29,0x30,0x63,0xd4,0xd5,0xd6,0xd7}:pops,pushes=1,0
  elif op in {0x04,0x66} and args[0] in static_names:pops,pushes=1,1
  elif op in {0x04,0x66} and args[0] in runtime_names:pops,pushes=1+runtime_names[args[0]],1
  elif op in {0x61,0x68} and args[0] in static_names:pops,pushes=2,0
  elif op==0x6c:pops,pushes=1,1
  elif op==0x6d:pops,pushes=2,0
  elif op in {0x45,0x46,0x4a,0x4c} and args[0] in static_names:pops,pushes=args[1]+1,1
  elif op in {0x4e,0x4f} and args[0] in static_names:pops,pushes=args[1]+1,0
  elif op==0x42:pops,pushes=args[0]+1,1
  elif op==0x56:pops,pushes=args[0],1
  elif op==0x55:pops,pushes=args[0]*2,1
  elif op in {0x70,0x71,0x72,0x73,0x74,0x75,0x76,0x77,0x78,0x80,0x81,0x82,0x83,0x84,0x85,0x86,0x88,0x89,0x90,0x91,0x93,0x95,0x96,0x97,0xc0,0xc1}:pops,pushes=1,1
  elif 0xa0<=op<=0xb1 or op in {0x87,0xb3,0xb4,0xc5,0xc6,0xc7}:pops,pushes=2,1
  elif op in {0x02,0x08,0xef,0xf0,0xf1}:continue
  else:return False
  if depth<pushes:return False
  depth=depth-pushes+pops
 return False

def lexical_forward_argument_receiver(flow, name, argc, call_offset, static_names):
 """Prove a resolver stays beneath arguments across a forward branch diamond.

 Only side-effect-free argument stack operations are modeled. Calls, unknown
 effects, runtime multinames, backward edges, stack underflow and unequal joins
 reject. The receiver itself may never be consumed by argument evaluation.
 """
 starts=[i for i,(_,op,args,_,_) in enumerate(flow) if op in (0x5d,0x5e) and args[0]==name]
 if not starts:return False
 entries=flow[starts[-1]:]
 if len(entries)>128:return False
 instructions={offset:(op,args,end,target) for offset,op,args,end,target in entries}
 pending=[(entries[0][3],1)];seen={};arrived=False
 pushes={0x20,0x21,0x24,0x25,0x26,0x27,0x28,0x2c,0x2d,0x2e,0x2f,0x31,0x60,0x62,0xd0,0xd1,0xd2,0xd3}
 unary={0x70,0x71,0x72,0x73,0x74,0x75,0x76,0x77,0x78,0x80,0x81,0x82,0x83,0x84,0x85,0x86,0x88,0x89,0x90,0x91,0x93,0x95,0x96,0x97,0xc0,0xc1}
 while pending:
  offset,depth=pending.pop()
  if offset in seen:
   if seen[offset]!=depth:return False
   continue
  seen[offset]=depth
  if offset==call_offset:
   if depth!=argc+1:return False
   arrived=True;continue
  if offset not in instructions:return False
  op,args,end,target=instructions[offset];pops=push=0
  if op in pushes:push=1
  elif op in unary:pops=push=1
  elif op==0x66 and args[0] in static_names:pops=push=1
  elif 0xa0<=op<=0xb1 or op in {0x87,0xb3,0xb4,0xc5,0xc6,0xc7}:pops,push=2,1
  elif op==0x10:pass
  elif op in (0x11,0x12):pops=1
  elif 0x0c<=op<=0x1a:pops=2
  elif op in (0x02,0xef,0xf0,0xf1):pass
  else:return False
  if depth-pops<1:return False
  depth=depth-pops+push
  if target is not None:
   if target<=offset or target>call_offset:return False
   pending.append((target,depth))
   if op==0x10:continue
  pending.append((end,depth))
 return arrived

def usage_after_pool(data, static_names, runtime_names, class_uses=None, occurrences=None):
 """Parse ABC structures and real instructions; never scan opcode-like bytes.

 Returns member traits, instruction multiname uses, pushstring indices, and
 repeated style-value literal positions.
 Unsupported instruction encodings fail closed instead of desynchronizing.
 """
 r=Reader(data);members=set();uses={};literals=set();class_traits=set();script_inits=set();style_pairs=[];types=set()
 for _ in range(r.num()):
  count=r.num();types.add(r.num())
  for _ in range(count):types.add(r.num())
  r.num();flags=r.take(1)[0]
  if flags&8:
   for _ in range(r.num()):r.num();r.take(1)
  if flags&128:
   for _ in range(count):r.num()
 for _ in range(r.num()):
  r.num()
  for _ in range(r.num()*2):r.num()
 def traits():
  for _ in range(r.num()):
   trait_pos=r.pos;name=r.num();flags=r.take(1)[0];kind=flags&15
   if occurrences is not None:occurrences.append({"kind":"trait","index":name,"position":trait_pos,"traitKind":kind,"guarded":kind!=4})
   if kind!=4:members.add(name)
   else:class_traits.add(name)
   if kind in (0,6):
    r.num();types.add(r.num())
    if r.num():r.take(1)
   elif kind in (1,2,3,4,5):r.num();r.num()
   else:raise ValueError('Unsupported trait')
   if flags&64:
    for _ in range(r.num()):r.num()
 classes=r.num()
 for _ in range(classes):
  types.add(r.num());types.add(r.num());flags=r.take(1)[0]
  if flags&8:r.num()
  for _ in range(r.num()):types.add(r.num())
  r.num();traits()
 for _ in range(classes):r.num();traits()
 for _ in range(r.num()):script_inits.add(r.num());traits()
 # AVM2 opcodes grouped by encoded operands. Unknown instructions are rejected.
 one=set(bytes.fromhex('04 05 06 08 25 2c 2d 2e 2f 31 40 41 42 49 53 55 56 58 59 5a 5b 5c 5d 5e 5f 60 61 62 63 66 67 68 6a 6c 6d 6e 6f 80 86 92 94 b2 c2 c3 f0 f1 f2'))
 two=set(bytes.fromhex('32 43 44 45 46 4a 4c 4e 4f'))
 zero=set(bytes.fromhex('01 02 03 07 09 1c 1d 1e 1f 20 21 23 26 27 28 29 2a 2b 30 35 36 37 38 39 3a 3b 3c 3d 3e 47 48 50 51 52 57 64 69 6b 70 71 72 73 74 75 76 77 78 81 82 83 84 85 87 88 89 90 91 93 95 96 97 a0 a1 a2 a3 a4 a5 a6 a7 a8 a9 aa ab ac ad ae af b0 b1 b3 b4 c0 c1 c4 c5 c6 c7 d0 d1 d2 d3 d4 d5 d6 d7 f3'))
 nameops=set(bytes.fromhex('04 05 45 46 4a 4c 4e 4f 59 5b 5c 5d 5e 5f 60 61 66 68 6a 80 86 b2'))
 for _ in range(r.num()):
  method=r.num()
  for _ in range(4):r.num()
  code_size=r.num();code_start=r.pos;code=Reader(r.take(code_size));history=[];flow_history=[]
  while code.pos<len(code.data):
   branch_target=None;instruction_offset=code.pos;op=code.take(1)[0];operand_start=code_start+code.pos;args=[]
   if op in one:args=[code.num()]
   elif op in two:args=[code.num(),code.num()]
   elif op in zero:pass
   elif 0x0c<=op<=0x1a:
    delta=int.from_bytes(code.take(3),"little",signed=True);branch_target=code.pos+delta
   elif op==0x1b:
    code.take(3);count=code.num();code.take(3*(count+1))
   elif op in (0x24,0x65):code.take(1)
   elif op==0xef:code.take(1);code.num();code.take(1);code.num()
   else:raise ValueError('Unsupported AVM2 opcode 0x%02x'%op)
   class_initialization=op==0x68 and method in script_inits and args[0] in class_traits
   lexical_coercion=op in (0x46,0x4f,0x4a) and lexical_call_receiver(history,args[0],args[1],static_names,runtime_names)
   if op==0x4a and not lexical_coercion:lexical_coercion=lexical_forward_argument_receiver(flow_history,args[0],args[1],instruction_offset,static_names)
   if lexical_coercion:types.add(args[0])
   if occurrences is not None and op in nameops:occurrences.append({"kind":"instruction","index":args[0],"position":operand_start,"method":method,"offset":instruction_offset,"opcode":op,"guarded":not class_initialization and not lexical_coercion})
   if op in nameops and not class_initialization and not lexical_coercion:uses.setdefault(args[0],set()).add(op)
   if op==0x2c and history and history[-1]==(0x2c,args):style_pairs.append((args[0],operand_start))
   history.append((op,args));flow_history.append((instruction_offset,op,args,code.pos,branch_target))
   if op==0x2c:literals.add(args[0])
  for _ in range(r.num()):
   r.num();r.num();r.num();types.add(r.num());r.num()
  traits()
 if r.pos!=len(data):raise ValueError('Trailing ABC data')
 if class_uses is not None:class_uses.update(types|class_traits)
 return members,uses,literals,style_pairs

def rewrite_abc(data, mapping, approved_data_literals=(), renamed_reflection=(), reviewed_style_values=(), style_changes=None, reviewed_members=(), member_changes=None, reviewed_sites=(), site_changes=None):
 r=Reader(data);minor,major=struct.unpack('<HH',r.take(4))
 if minor!=16 or major not in (46,47):raise ValueError('Unsupported ABC')
 for _ in range(2):
  for _ in range(max(0,r.num()-1)):r.num()
 r.take(max(0,r.num()-1)*8)
 if major>=47:r.take(max(0,r.num()-1)*4)
 start=r.pos;strings=[b'']
 for _ in range(max(0,r.num()-1)):strings.append(r.take(r.num()))
 original_count=len(strings);new_names={}
 for old,new in mapping.items():new_names[old]=len(strings);strings.append(new.rsplit(".",1)[-1].encode())
 namespaces=[None]
 for _ in range(max(0,r.num()-1)):namespaces.append((r.take(1)[0],r.num()))
 sets=[None]
 for _ in range(max(0,r.num()-1)):sets.append([r.num() for _ in range(r.num())])
 count=r.num();names=[];original_names={};generic_types=set();changes=0;ambiguous={};renamed_indices={};static_names=set();runtime_names={}
 for _ in range(max(0,count-1)):
  begin=r.pos;kind=r.take(1)[0]
  if kind in (7,13,9,14):static_names.add(len(names)+1)
  elif kind in (15,16,27,28):runtime_names[len(names)+1]=1
  elif kind in (17,18):runtime_names[len(names)+1]=2
  if kind in (7,13):
   ns,idx=r.num(),r.num();local=strings[idx].decode();uri=strings[namespaces[ns][1]].decode()
   full=(uri+'.' if uri else '')+local
   if full in mapping:
    original_names[len(names)+1]=data[begin:r.pos];names.append(bytes([kind])+u30(ns)+u30(new_names[full]));renamed_indices[len(names)]=full;changes+=1;continue
  elif kind in (9,14):
   idx,setidx=r.num(),r.num();local=strings[idx].decode()
   matches=[(strings[namespaces[n][1]].decode()+'.' if strings[namespaces[n][1]] else '')+local for n in sets[setidx]]
   matched={n for n in matches if n in mapping}
   if matched:
    if len(matched)!=1:raise ValueError('Ambiguous multiple class namespaces '+local)
    full=next(iter(matched));ambiguous[len(names)+1]=full;original_names[len(names)+1]=data[begin:r.pos]
    names.append(bytes([kind])+u30(new_names[full])+u30(setidx));changes+=1;continue
  elif kind in (15,16,27,28):r.num()
  elif kind==29:
   generic_types.add(r.num())
   for _ in range(r.num()):generic_types.add(r.num())
  elif kind not in (17,18):raise ValueError('Unsupported multiname')
  names.append(data[begin:r.pos])
 suffix=data[r.pos:]
 class_uses=set(generic_types);occurrences=[]
 members,uses,literals,style_pairs=usage_after_pool(suffix,static_names,runtime_names,class_uses,occurrences)
 # Source-digest-pinned exact operand sites; never infer object receiver meaning.
 site_suffix=bytearray(suffix);selected_positions=set();duplicates={}
 mapped={**renamed_indices,**ambiguous}
 for review in reviewed_sites:
  found=[o for o in occurrences if o["position"]==review["position"] and mapped.get(o["index"])==review["name"] and all(o.get(k)==v for k,v in review.items() if k!="name")]
  if len(found)!=1:raise ValueError("Reviewed member operand not found "+repr(review))
  o=found[0];idx=o["index"]
  if not o["guarded"]:raise ValueError("Cannot split proven class initialization/coercion")
  if o["kind"]=="trait" and o["traitKind"]==4:raise ValueError("Cannot split class definition trait")
  if o["kind"]=="instruction" and o["opcode"] not in {0x04,0x05,0x45,0x46,0x4a,0x4c,0x4e,0x4f,0x59,0x5b,0x5c,0x5d,0x5e,0x5f,0x60,0x61,0x66,0x68,0x6a}:raise ValueError("Cannot split class type operand")
  if o["position"] in selected_positions:raise ValueError("Duplicate reviewed member operand")
  if idx not in duplicates:duplicates[idx]=len(names)+1;names.append(original_names[idx])
  before=u30(idx);after=u30(duplicates[idx])
  if len(before)!=len(after):raise ValueError("Member operand rewrite requires offset relocation")
  if site_suffix[o["position"]:o["position"]+len(before)]!=before:raise ValueError("Member operand mismatch")
  site_suffix[o["position"]:o["position"]+len(before)]=after;selected_positions.add(o["position"])
  if site_changes is not None:site_changes.append(dict(review))
 suffix=bytes(site_suffix)
 if selected_positions:
  members={o["index"] for o in occurrences if o["kind"]=="trait" and o["guarded"] and o["position"] not in selected_positions}
  uses={}
  for o in occurrences:
   if o["kind"]=="instruction" and o["guarded"] and o["position"] not in selected_positions:uses.setdefault(o["index"],set()).add(o["opcode"])
 # Preserve a reviewed separate member entry only; class/type entries stay renamed.
 for idx,full in list({**renamed_indices,**ambiguous}.items()):
  if full in reviewed_members and idx not in class_uses and not (uses.get(idx,set()) & {0x60,0x5d,0x5e,0x80,0x86,0xb2}) and (idx in members or uses.get(idx)):
   names[idx-1]=original_names[idx];changes-=1
   renamed_indices.pop(idx,None);ambiguous.pop(idx,None)
   if member_changes is not None:member_changes.add(full)
 # Exact reviewed style object pair: preserve its public key and all key lookups,
 # replace only the immediately repeated literal value. Keep operand widths so
 # branch offsets and exception ranges remain byte-for-byte valid.
 suffix=bytearray(suffix)
 for idx,pos in style_pairs:
  value=strings[idx].decode(errors='replace')
  if value not in reviewed_style_values or value not in mapping:continue
  old=u30(idx);new=u30(len(strings))
  if len(old)!=len(new):raise ValueError('Style value rewrite requires offset relocation '+value)
  strings.append(mapping[value].encode());suffix[pos:pos+len(old)]=new
  if style_changes is not None:style_changes.add(value)
 suffix=bytes(suffix)
 for idx,local in {**renamed_indices,**ambiguous}.items():
  if idx in members:raise ValueError('Class name also used as member trait '+local)
 for idx,local in {**renamed_indices,**ambiguous}.items():
  # getlex resolves a class lexically; findpropstrict/findproperty + constructprop
  # are the compiler's lexical constructor sequence. No arbitrary property read.
  unsafe=uses.get(idx,set())-{0x60,0x5d,0x5e,0x80,0x86,0xb2}
  if unsafe:raise ValueError('Nonlexical class reference '+local+' opcodes='+str(sorted(unsafe)))
 for idx in literals:
  value=strings[idx].decode(errors='replace')
  if value in mapping and value not in approved_data_literals and value not in reviewed_style_values:
   if value in renamed_reflection:strings[idx]=mapping[value].encode()
   else:raise ValueError('Reflected class string '+value)
 protected_mapping={(old.rsplit('.',1)[0]+':'+old.rsplit('.',1)[1] if '.' in old else old):(new.rsplit('.',1)[0]+':'+new.rsplit('.',1)[1] if '.' in new else new) for old,new in mapping.items()}
 protected_mapping.update(mapping)
 mapped_ns=[]
 for kind,idx in namespaces[1:]:
  uri=strings[idx].decode()
  if kind in (0x18,0x1a) and uri in protected_mapping:
   strings.append(protected_mapping[uri].encode());idx=len(strings)-1
  mapped_ns.append((kind,idx))
 result=data[:start]+u30(len(strings))+b''.join(u30(len(s))+s for s in strings[1:])
 result+=u30(len(namespaces))+b''.join(bytes([k])+u30(i) for k,i in mapped_ns)
 result+=u30(len(sets))+b''.join(u30(len(ns))+b''.join(u30(n) for n in ns) for ns in sets[1:])
 return result+u30(len(names)+1)+b''.join(names)+suffix,changes


def isolate_globals(data, class_names=None, reflection_review=None, style_value_review=None, reflection_alias_review=None, member_review=None, member_site_review=None):
 """Isolate owned definitions, with optional explicit class scope.

 reflection_review maps an exact input SWF SHA256 to class names whose string
 pool uses have been audited as exclusively reflected class values. It must not
 contain style keys or other member/data strings, even when spelling matches.
 style_value_review separately pins names whose audited key/value pair repeats
 a literal; only that value is rewritten, with every other occurrence an audited
 public style key. Unchanged operand widths preserve all branch/exception offsets.
 reflection_alias_review pins mixed public tokens and reflected class names; an
 asset-private delegate redirects only the built-in lookup QName, translates
 owned definitions, and passes unknown names to the original lookup unchanged.
 """
 source_digest=hashlib.sha256(data).hexdigest()
 identifier=source_digest[:24]
 version,header,tags=unpack(data);definitions=[]
 for kind,payload in tags:
  if kind==82:definitions.extend(abc_classes(abc_parts(payload)[1]))
 defined={c['name'] for c in definitions}
 if class_names is None:
  selected={n for n in defined if ('.' not in n or n.rsplit('.',1)[0].endswith('_fla')) and not n.startswith('Adapters_')}
 else:
  selected=set(class_names)
  if selected-defined:raise ValueError('Requested classes not defined in asset: '+str(sorted(selected-defined)))
  if any(n.startswith('org.ekoloko.air.compat.') for n in selected):raise ValueError('Adapter APIs must not be renamed')
 mapping={name:name+'_'+identifier for name in sorted(selected)}
 if not mapping:raise ValueError('No private global classes')
 renamed_reflection=set((reflection_review or {}).get(source_digest,()))
 reviewed_style_values=set((style_value_review or {}).get(source_digest,()))
 if reviewed_style_values-set(mapping):raise ValueError("Style review contains unselected class names")
 reviewed_members=set((member_review or {}).get(source_digest,()))
 if reviewed_members-set(mapping):raise ValueError("Member review contains unselected class names")
 member_changes=set()
 style_changes=set()
 alias_names=set((reflection_alias_review or {}).get(source_digest,()))
 if alias_names-set(mapping):raise ValueError('Reflection alias review contains unselected class names')
 lookup_tags=[];lookup_namespace=None;lookup_changes=0
 if alias_names:
  from prepare_aot_reflection_lookup import build_lookup,redirect_lookup
  lookup_namespace,lookup_tags=build_lookup(mapping,source_digest)
 if renamed_reflection-set(mapping):raise ValueError('Reflection review contains unselected class names')
 site_reviews=(member_site_review or {}).get(source_digest,{})
 if any(not str(k).isdigit() for k in site_reviews):raise ValueError("Malformed ABC site review")
 site_changes={};abc_ordinal=0
 result=[];changes=0
 for kind,payload in tags:
  if kind==82:
   prefix,abc=abc_parts(payload)
   # The existing trusted build injects one isolated AssetRoot adapter ABC.
   # Its document-class string is its constructor lookup, never a public label.
   # Approve only this ABC; matching game-script literals still fail closed.
   adapter_classes={c['name'] for c in abc_classes(abc)}
   is_adapter=any(n.endswith('.AssetRoot') and n.startswith('org.ekoloko.air.compat.') for n in adapter_classes) and all(n.startswith('org.ekoloko.air.compat.') or n.startswith('Adapters_') for n in adapter_classes)
   adapter_reflection=({'ItemMC','NpcMC'} & set(mapping)) if is_adapter else set()
   abc,n=rewrite_abc(abc,mapping,set(REVIEWED_DATA_LITERALS.get(source_digest,()))|alias_names,renamed_reflection|adapter_reflection,reviewed_style_values,style_changes,reviewed_members,member_changes,site_reviews.get(str(abc_ordinal),()),site_changes.setdefault(str(abc_ordinal),[]))
   abc_ordinal+=1
   if lookup_namespace:
    abc,redirects=redirect_lookup(abc,lookup_namespace);lookup_changes+=redirects
   payload=prefix+abc;changes+=n
  elif kind==76:
   r=Reader(payload);entries=[]
   for _ in range(struct.unpack('<H',r.take(2))[0]):
    charid=r.take(2);end=payload.index(b'\0',r.pos);symbol=r.take(end-r.pos).decode();r.take(1)
    entries.append(charid+mapping.get(symbol,symbol).encode()+b'\0')
   payload=struct.pack('<H',len(entries))+b''.join(entries)
  elif kind==72:raise ValueError('Unsupported ABC')
  result.append((kind,payload))
 if any(int(k)>=abc_ordinal for k in site_reviews):raise ValueError("Reviewed ABC not found")
 if reviewed_style_values-style_changes:raise ValueError("Reviewed style value pair not found: "+str(sorted(reviewed_style_values-style_changes)))
 if reviewed_members-member_changes:raise ValueError("Reviewed separate member entry not found: "+str(sorted(reviewed_members-member_changes)))
 if changes<len(mapping):raise ValueError('Missing class definition rewrites')
 if alias_names:
  if not lookup_changes:raise ValueError('Reviewed reflection lookup QName not found')
  first=next(i for i,t in enumerate(result) if t[0]==82)
  result[first:first]=lookup_tags
 output=pack(version,header,result)
 return output,{'classes':mapping,'qnameChanges':changes,'sourceSha256':hashlib.sha256(data).hexdigest(),'outputSha256':hashlib.sha256(output).hexdigest(),'renamedReflectionClasses':sorted(renamed_reflection),'rewrittenStyleValueClasses':sorted(style_changes),'reflectionAliasClasses':sorted(alias_names),'reflectionLookupQNameChanges':lookup_changes,'preservedMemberClasses':sorted(member_changes),'preservedMemberSites':{k:v for k,v in site_changes.items() if v}}
