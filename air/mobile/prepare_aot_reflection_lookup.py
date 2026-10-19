"""Build an asset-private getDefinitionByName delegate for audited dynamic names.

Original public string tokens remain untouched. Only the original flash.utils
lookup QName is routed to the delegate, which maps audited owned classes and
passes every unknown name through to flash.utils.getDefinitionByName unchanged.
"""
import json,os,struct,subprocess,tempfile
from pathlib import Path
from swf import Reader,u30,unpack

def build_lookup(mapping,source_sha):
 namespace='org.ekoloko.air.reflection.h'+source_sha[:24]
 root_name='AotLookup_'+source_sha[:24]
 with tempfile.TemporaryDirectory(prefix='ekoloko-aot-reflection-') as folder:
  root=Path(folder);package=root/namespace.replace('.','/');package.mkdir(parents=True)
  cases=''.join('if(name=='+json.dumps(old)+') return flash.utils.getDefinitionByName('+json.dumps(new)+');' for old,new in sorted(mapping.items()))
  (package/'lookupDefinition.as').write_text('package '+namespace+' {import flash.utils.getDefinitionByName;public function lookupDefinition(name:String):Object {'+cases+'return flash.utils.getDefinitionByName(name);}}')
  (root/(root_name+'.as')).write_text('package {import flash.display.Sprite;public class '+root_name+' extends Sprite {}}')
  sdk=Path('/Volumes/T9/AIR/sdks/AIRSDK_51.4.1');env=dict(os.environ,JAVA_HOME='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home')
  r=subprocess.run([str(sdk/'bin/amxmlc'),'-source-path+='+str(root),'-includes='+namespace+'.lookupDefinition','-output='+str(root/'lookup.swf'),str(root/(root_name+'.as'))],env=env,capture_output=True,text=True,timeout=30)
  if r.returncode:raise ValueError('Reflection delegate compilation failed: '+r.stdout+r.stderr)
  tags=[(kind,payload) for kind,payload in unpack((root/'lookup.swf').read_bytes())[2] if kind==82]
  if not tags:raise ValueError('Reflection delegate has no ABC')
 return namespace,tags

def redirect_lookup(data,namespace):
 r=Reader(data);minor,major=struct.unpack('<HH',r.take(4))
 if minor!=16 or major not in (46,47):raise ValueError('Unsupported ABC')
 for _ in range(2):
  for _ in range(max(0,r.num()-1)):r.num()
 r.take(max(0,r.num()-1)*8)
 if major>=47:r.take(max(0,r.num()-1)*4)
 start=r.pos;strings=[b'']
 for _ in range(max(0,r.num()-1)):strings.append(r.take(r.num()))
 namespaces=[None]
 for _ in range(max(0,r.num()-1)):namespaces.append((r.take(1)[0],r.num()))
 sets_start=r.pos
 for _ in range(max(0,r.num()-1)):
  for _ in range(r.num()):r.num()
 sets_bytes=data[sets_start:r.pos];count=r.num();names=[];changes=0;target=len(namespaces)
 for _ in range(max(0,count-1)):
  begin=r.pos;kind=r.take(1)[0]
  if kind in (7,13):
   ns,idx=r.num(),r.num()
   if kind==7 and namespaces[ns][0]==0x16 and strings[idx]==b'getDefinitionByName' and strings[namespaces[ns][1]]==b'flash.utils':
    names.append(bytes([kind])+u30(target)+u30(len(strings)+1));changes+=1;continue
  elif kind in (9,14):r.num();r.num()
  elif kind in (15,16,27,28):r.num()
  elif kind==29:
   r.num()
   for _ in range(r.num()):r.num()
  elif kind not in (17,18):raise ValueError('Unsupported multiname')
  names.append(data[begin:r.pos])
 if not changes:return data,0
 namespaces.append((0x16,len(strings)));strings.append(namespace.encode());strings.append(b'lookupDefinition')
 result=data[:start]+u30(len(strings))+b''.join(u30(len(s))+s for s in strings[1:])
 result+=u30(len(namespaces))+b''.join(bytes([kind])+u30(idx) for kind,idx in namespaces[1:])
 return result+sets_bytes+u30(count)+b''.join(names)+data[r.pos:],changes
