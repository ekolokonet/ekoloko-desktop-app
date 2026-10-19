"""Prepare unapproved private-scope candidates; never silently skip failed assets.

Runtime suites establish acceptance separately. This output is not a release index.
"""
import argparse,hashlib,json,sys
from collections import defaultdict
from pathlib import Path
from prepare_aot_catalog import inspect
from prepare_aot_private_globals import isolate_globals
sys.path.insert(0,str(Path(__file__).parent/'tests'))
from test_aot_entry_domains import LOGIN_SOURCE_SHA,SKINS

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--catalog',type=Path,required=True);p.add_argument('--class-review',type=Path,help='Digest-pinned reflection/style runtime review receipt');p.add_argument('--output',type=Path,required=True);p.add_argument('--canonical-mobile',action='store_true',help='Prototype canonical resolver catalog; retain globally unique member/class names');a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False);(a.output/'compiled-content').mkdir();cat=json.loads((a.catalog/'catalog.json').read_text());plan=json.loads((a.catalog/'scope-plan.json').read_text());results={};counts={}
 reflection_reviews={LOGIN_SOURCE_SHA:SKINS};style_reviews={};alias_reviews={};member_reviews={};member_site_reviews={}
 if a.class_review:
  review=json.loads(a.class_review.read_text())
  if review.get('passed') is not True:raise ValueError('Class review did not pass')
  for field,target in [('reviews',reflection_reviews),('reflectionReview',reflection_reviews),('styleValueReview',style_reviews),('reflectionAliasReview',alias_reviews),('memberReview',member_reviews)]:
   for digest,names in review.get(field,{}).items():
    if len(digest)!=64 or any(c not in '0123456789abcdef' for c in digest) or not isinstance(names,list) or not all(isinstance(n,str) and n for n in names):raise ValueError('Malformed digest-pinned class review')
    target[digest]=set(target.get(digest,()))|set(names)
  for digest,abcs in review.get('memberSiteReview',{}).items():
   if len(digest)!=64 or any(c not in '0123456789abcdef' for c in digest) or not isinstance(abcs,dict):raise ValueError('Malformed digest-pinned member site review')
   for abc,sites in abcs.items():
    if not str(abc).isdigit() or not isinstance(sites,list) or not all(isinstance(site,dict) and isinstance(site.get('name'),str) and isinstance(site.get('position'),int) for site in sites):raise ValueError('Malformed member operand sites')
   member_site_reviews[digest]=abcs
 excluded={};owners=defaultdict(set)
 if a.canonical_mobile:
  for digest,row in cat['objects'].items():
   if all(path.startswith(('ekoloko/','play.ekoloko.com/','play.ekoloko.org/')) for path in row['paths']):excluded[digest]='noncanonical-manifest-alias'
   elif plan['objects'].get(digest,{}).get('parentScope')=='obsolete_root_candidate':excluded[digest]='historical-root'
   elif any(path in {'main_components/house_1.swf','main_components/main9.1.bakup.swf'} for path in row['paths']):excluded[digest]='historical-module-copy'
  for digest,row in cat['objects'].items():
   if digest not in excluded:
    for c in row['classes']:owners[c['name']].add(digest)
 for digest,row in cat['objects'].items():
  data=(a.catalog/'compiled-content'/(digest+'.swf')).read_bytes();scope=plan['objects'].get(digest);record={'paths':row['paths'],'sourceSha256':hashlib.sha256(data).hexdigest(),'approvedForRelease':False};state='not-executable'
  if record['sourceSha256']=='e27e7f469f24b8ffff4909e27c59a1da14cec58988f77a4a59c33fdb17b89af2':
   from repair_aot_timeline_slot import repair
   data,record['sourceRepair']=repair(data)
  if digest in excluded:state='excluded-candidate';record['exclusionReason']=excluded[digest]
  elif scope:
   state=scope['parentScope'];record['scope']=state
   if state in {'main','shell','portable_leaf','host'}:
    if 'main.swf' in row['paths'] or 'shell.swf' in row['paths']:state='core-preserve'
    else:
     classes={c['name'] for c in inspect(data)['classes']}&set(scope['privateClasses'])
     if a.canonical_mobile:
      unique={n for n in classes if len(owners[n])==1};record['retainedSingleOwnerClasses']=sorted(unique);classes-=unique
     if record['sourceSha256']==LOGIN_SOURCE_SHA:classes.discard('focusRectSkin')
     if classes:
      try:data,record['transform']=isolate_globals(data,class_names=classes,reflection_review=reflection_reviews,style_value_review=style_reviews,reflection_alias_review=alias_reviews,member_review=member_reviews,member_site_review=member_site_reviews);state='transformed'
      except ValueError as e:state='blocked-transform';record['reason']=str(e)
     else:state='already-private'
   else:state='blocked-scope'
  record['state']=state;record['outputSha256']=hashlib.sha256(data).hexdigest();results[digest]=record;counts[state]=counts.get(state,0)+1
  (a.output/'compiled-content'/(digest+'.swf')).write_bytes(data)
 (a.output/'candidate.json').write_text(json.dumps({'sourceManifestSha256':cat.get('sourceManifestSha256'),'canonicalMobilePrototype':a.canonical_mobile,'counts':counts,'objects':results,'releaseReady':False},indent=2)+'\n');print(json.dumps(counts,indent=2))
if __name__=='__main__':main()
