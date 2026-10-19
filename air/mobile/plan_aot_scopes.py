"""Plan AOT class ownership from the actual Shell -> entry/Main -> modules graph.

A scope plan is not a runtime acceptance. Preserve ancestor class authority; do
not let an earlier sibling (Login, Selector) supply Main's private definitions.
Unknown contexts remain explicit blockers. Nothing is dropped from the pack.
"""
import argparse,json,hashlib
from pathlib import Path

# Shell's audited loadMain() and host use exactly main.swf / shell.swf. Historical
# root copies are not alternative runtime sources. The plan excludes only these
# exact filenames, not a general substring that might match a real game asset.
OLD_ROOTS={'main - Copy.swf','main9.1bak.swf','main_2026_05_31.swf','main_BAK.swf.bak.swf',
 'main_backup_20251012_094140.swf','main_backup_20251012_095019.swf','main_decomp.swf','main_patched.swf','shell-code-panel.swf','shell8.5.swf','shell_with_logs.swf'}
SHELL_PREFIXES=('website/','loading_page/','welcome_animations/','life_levels/')
MAIN_PREFIXES=('world_rooms/','main_components/','house/','games/','1-1games/','npcs/',
 'emoticons/','potions/','community_events/','world_room_links/','tutorial/','animals/',
 'quiz/','studio/','moderator/','cards/','recycle_items/','recycle_bins/','map/','helper/','player_data/','donation_campaigns/')

def canonical(path):
 for prefix in ('play.ekoloko.com/ekoloko/','play.ekoloko.org/ekoloko/','ekoloko/','play.ekoloko.com/'):
  if path.startswith(prefix):return path[len(prefix):]
 return path

def scope(path):
 if path in {'ekoloko/main.swf','ekoloko/shell.swf'}:return 'obsolete_root_candidate'
 path=canonical(path)
 if path in OLD_ROOTS:return 'obsolete_root_candidate'
 if path=='shell.swf':return 'host'
 if path=='main.swf':return 'shell'
 if path.startswith(SHELL_PREFIXES) or path in {'login.swf','register.swf','avatarLoader.swf','MinimaFlatCustomColorPlayBackSeekCounterVolMute.swf','ima_preloader.swf'}:return 'shell'
 if path.startswith(MAIN_PREFIXES):return 'main'
 if path.startswith('items/') or path.startswith('images/'):return 'multiple_parents'
 return 'unknown'

def definition_fingerprint(digest, row):
 return hashlib.sha256(json.dumps([digest,row['classes'],row.get('preparedClasses')],sort_keys=True,separators=(',',':')).encode()).hexdigest()

def plan(catalog, evidence=None):
 # Pin both ancestors and each reviewed object; unrelated room refreshes do not
 # invalidate an unchanged item. Changed ancestors or definitions fail closed.
 reviewed={} if evidence is None else evidence.get('objects',{})
 if evidence is not None:
  parents={p:definition_fingerprint(d,r) for d,r in catalog['objects'].items() for p in r['paths'] if p in {'main.swf','shell.swf'}}
  if evidence.get('schema')!=1 or evidence.get('parents')!=parents:
   raise ValueError('Scope evidence ancestors do not match this catalog')
 rows={p:(digest,r) for digest,r in catalog['objects'].items() for p in r['paths']}
 shell={c['name'] for c in rows['shell.swf'][1]['classes'] if c['namespaceKind']==22}
 main={c['name'] for c in rows['main.swf'][1]['classes'] if c['namespaceKind']==22}|shell
 result={};counts={}
 for digest,r in catalog['objects'].items():
  if not r.get('classes'):continue
  scopes={scope(p) for p in r['paths']};defined={c['name'] for c in r['classes']};ancestors=set()
  if scopes=={'shell'}:ancestors=shell
  elif scopes=={'main'}:ancestors=main
  elif scopes=={'host'}:pass
  elif scopes <= {'main','shell','multiple_parents'} and 'multiple_parents' in scopes:
   # Items loaded during entry/avatar preview cannot assume Main exists. If the
   # object defines any Main-only API, resolve its actual callers before use.
   ancestors=shell
  state=next(iter(scopes)) if len(scopes)==1 else 'ambiguous_alias_scopes'
  if scopes <= {'main','shell','multiple_parents'} and 'multiple_parents' in scopes:
   if not ((defined&main)-shell):state='portable_leaf'
   else:
    proof=reviewed.get(digest,{})
    if (proof.get('objectFingerprint')==definition_fingerprint(digest,r) and proof.get('equivalent') is True and proof.get('allRootFrames') is True
        and proof.get('cloneParity') is True and proof.get('getMCParity') is True
        and proof.get('testedParents')==['shell','main','currentDomain']
        and proof.get('mainOnlyDefinitions')==sorted((defined&main)-shell)):
     state='portable_leaf'
  if state=='unknown' and evidence is not None:
   proof=evidence.get('standaloneObjects',{}).get(digest,{})
   if (proof.get('objectFingerprint')==definition_fingerprint(digest,r)
       and proof.get('standaloneRoot') is True and proof.get('constructorAndTimelineParity') is True
       and proof.get('loaderParametersFixture') is True):
    # Independent browser roots construct their own services from loaderInfo.
    # No Shell or Main API is an ancestor; keep every definition private.
    state='host'
  counts[state]=counts.get(state,0)+1
  private=sorted(defined-ancestors)
  private=[n for n in private if not n.startswith('org.ekoloko.air.compat.') and not n.startswith('Adapters')]
  result[digest]={'paths':r['paths'],'parentScope':state,'preserveAncestorClasses':sorted(defined&ancestors),
    'privateClasses':private,'mainOnlyEarlyDefinitions':sorted((defined&main)-shell) if 'shell' in scopes or 'multiple_parents' in scopes else [],
    'approvedForRelease':False}
 return {'mainVersion':catalog['mainVersion'],'scopeCounts':counts,'objects':result,'releaseReady':False,
 'evidence':['Shell.loadMain requests main.swf only; host launches shell.swf only.',
 'Shell loads Login/Selector before Main as sibling domains.',
 'Shell.videoAdsPlayer.skin names MinimaFlatCustomColorPlayBackSeekCounterVolMute.swf; ShellAdsPlayer.loadAd names ima_preloader.swf.',
 'Runtime-reviewed multiple-parent display assets retain Shell ancestors and isolate Main-only display definitions; evidence is catalog-pinned.',
 'Main WorldRoom/ItemCache/house loaders create child domains beneath Main.',
 '115 shared public Main/Shell classes preserve Shell authority in parent/currentDomain ADL test.'],
 'limitations':['Module instances/reflective class lookups still require transformed contract checks.',
 'Standalone website-root probes suspend network and printing; full avatar/print/navigation feature acceptance remains pending.',
 'Unknown scopes and ambiguous aliases are blocked. Obsolete root candidates are not removed here.',
 'All final executable SWFs must be explicit inputs to ADT; runtime download cannot introduce AS3.']}
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--catalog',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--scope-evidence',type=Path);a=p.parse_args()
 report=plan(json.loads(a.catalog.read_text()),json.loads(a.scope_evidence.read_text()) if a.scope_evidence else None);a.output.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k!='objects'},indent=2))
