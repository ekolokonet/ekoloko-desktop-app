import sys,json,copy,hashlib,argparse
from pathlib import Path
root=Path(__file__).resolve().parents[2];sys.path[:0]=[str(root/'mobile'),str(root/'scripts')]
p=argparse.ArgumentParser();p.add_argument('--catalog',type=Path,required=True);p.add_argument('--candidate',type=Path,required=True);p.add_argument('--review',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
from prepare_aot_private_globals import isolate_globals
from swf import unpack,abc_parts
review=json.loads(a.review.read_text());sha=next(iter(review));rows=json.loads((a.candidate/'candidate.json').read_text())['objects'];digest=next(k for k,r in rows.items() if r['sourceSha256']==sha);data=((a.catalog/'compiled-content')/(digest+'.swf')).read_bytes();classes=set(json.loads((a.catalog/'scope-plan.json').read_text())['objects'][digest]['privateClasses'])-set(rows[digest]['retainedSingleOwnerClasses'])
cases={}
wrong=copy.deepcopy(review);wrong['0'*64]=wrong.pop(sha);cases['wrongDigest']=wrong
wrong=copy.deepcopy(review);wrong[sha]['1'][0]['position']+=1;cases['wrongOffset']=wrong
wrong=copy.deepcopy(review);wrong[sha]['1'][0]['traitKind']=4;wrong[sha]['1'][0]['position']=112;cases['classDefinition']=wrong
wrong=copy.deepcopy(review);wrong[sha]['1']=[{'kind':'instruction','index':8,'position':388,'method':10,'offset':36,'opcode':104,'name':'bubble'}];cases['classInitialization']=wrong
wrong=copy.deepcopy(review);wrong[sha]['2']=wrong[sha].pop('1');cases['missingABC']=wrong
wrong=copy.deepcopy(review);wrong[sha]['1']*=2;cases['duplicateSite']=wrong
for name,r in cases.items():
 try:isolate_globals(data,classes,member_site_review=r)
 except ValueError as e:cases[name]=str(e)
 else:raise AssertionError(name)
out,r=isolate_globals(data,classes,member_site_review=review);assert len(r['preservedMemberSites']['1'])==1
assert [t for t in unpack(data)[2] if t[0] not in (76,82)]==[t for t in unpack(out)[2] if t[0] not in (76,82)]
a.output.write_text(json.dumps({'passed':True,'rejected':cases,'preciseTraitSitePassed':True},indent=2));print('SITE_SAFETY_PASS',len(cases))
