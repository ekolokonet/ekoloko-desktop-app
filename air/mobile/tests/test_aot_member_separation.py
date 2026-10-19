"""Digest-pinned member separation acceptance; existing rejection suite stays intact."""
import argparse,hashlib,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from prepare_aot_private_globals import isolate_globals
from swf import unpack,abc_parts

def main():
 p=argparse.ArgumentParser();p.add_argument('--fixtures',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();results=[]
 for name in ['dynamic_call','dynamic_indexed_call','dynamic_constructor','dynamic_member']:
  data=(a.fixtures/name/'Fixture.swf').read_bytes();digest=hashlib.sha256(data).hexdigest()
  for review in [None,{'0'*64:['BGMC']},{digest:['NOT_DEFINED']}]:
   try:isolate_globals(data,member_review=review)
   except ValueError:pass
   else:raise AssertionError('Unreviewed member accepted '+name)
  output,r=isolate_globals(data,member_review={digest:['BGMC']});assert r['preservedMemberClasses']==['BGMC'];assert r['classes']['BGMC']!='BGMC'
  assert [x for x in unpack(data)[2] if x[0] not in (76,82)]==[x for x in unpack(output)[2] if x[0] not in (76,82)]
  results.append(name)
 # Same pool entry serves a class and a member trait: still unsafe even reviewed.
 for name in ['member_trait','reflection']:
  data=(a.fixtures/name/'Fixture.swf').read_bytes()
  try:isolate_globals(data,member_review={hashlib.sha256(data).hexdigest():['BGMC']})
  except ValueError:pass
  else:raise AssertionError('Shared/reflective entry accepted '+name)
 a.output.write_text(json.dumps({'passed':True,'accepted':results,'wrongDigestAndUnselectedRejected':True,'sharedAndReflectionRejected':True},indent=2)+'\n');print('MEMBER_SEPARATION_PASS')
if __name__=='__main__':main()
