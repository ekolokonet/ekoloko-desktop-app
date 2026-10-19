"""Real AIR semantic map gate, bound to the active signed map and native Main."""
from pathlib import Path
import hashlib,json,os,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT));from run_phone import apply_version_map_capability
SDK=Path('/Volumes/T9/AIR/sdks/AIRSDK_51.4.1')
base='<data><main_version>152</main_version><rooms version="161"><room id="4" version="9"/></rooms><text>4008</text></data>'
sha=lambda s:hashlib.sha256(s.encode()).hexdigest()
main='a'*64
manifest={'versionConfigSha256':sha(base),'assets':{'main.swf':{'sha256':main}}}
cases=[]
def add(label,current,expected,baseline=base,active=None,pin=main):
 cases.append(dict(label=label,current=current,expected=expected,baseline=baseline,manifest=active or manifest,mainSha=pin))
add('unchanged',base,True)
add('text_advance',base.replace('4008','4009'),True)
add('whitespace_comment_attribute_order','<?xml version="1.0"?>\n'+base.replace('><','> \n <').replace('<room id="4" version="9"','<!-- description --><room version="9" id="4"'),True)
add('text_rollback',base.replace('4008','4007'),False)
add('room_counter',base.replace('161','162'),False)
add('room_override',base.replace('version="9"','version="10"'),False)
add('room_id',base.replace('id="4"','id="5"'),False)
add('main_version',base.replace('152','153'),False)
add('new_component',base.replace('</data>','<loader>2</loader></data>'),False)
add('missing_component',base.replace('<main_version>152</main_version>',''),False)
add('duplicate_text',base.replace('</data>','<text>4009</text></data>'),False)
add('text_attributes',base.replace('<text>','<text version="1">'),False)
add('text_children',base.replace('4008','<v>4008</v>'),False)
add('fraction_counter',base.replace('4008','4008.5'),False)
add('overflow_counter',base.replace('4008','9999999999999999999999'),False)
add('namespace',base.replace('<data>','<data xmlns="urn:test">'),False)
add('attribute_namespace',base.replace('<data>','<data xmlns:a="urn:test" a:key="1">'),False)
add('entity','<!DOCTYPE data [<!ENTITY v "4009">]>'+base.replace('4008','&v;'),False)
add('malformed',base[:-4],False)
add('child_order',base.replace('<main_version>152</main_version>','').replace('</data>','<main_version>152</main_version></data>'),False)
add('wrong_active_map',base,False,active={**manifest,'versionConfigSha256':'b'*64})
add('wrong_active_main',base,False,active={**manifest,'assets':{'main.swf':{'sha256':'b'*64}}})
add('wrong_compiled_main_pin',base,False,pin='b'*64)
add('empty_baseline',base,False,baseline='')
add('excessive_depth',base.replace('</data>','<a>'*34+'</a>'*34+'</data>'),False)
add('excessive_nodes',base.replace('</data>','<a/>'*10001+'</data>'),False)
real=(ROOT/'tests/fixtures/files-version-152-rooms161.xml').read_text()
realmanifest={**manifest,'versionConfigSha256':sha(real)}
add('actual_pinned_map',real,True,baseline=real,active=realmanifest)
add('actual_text_only',real.replace('<text>4008</text>','<text>4009</text>'),True,baseline=real,active=realmanifest)
add('actual_room_change',real.replace('<rooms version="161">','<rooms version="162">'),False,baseline=real,active=realmanifest)
info='public final class BuildInfo {}'
generated=apply_version_map_capability(info,base.encode(),manifest)
assert 'VERSION_MAP_XML' in generated
assert apply_version_map_capability(generated,None,manifest).count('VERSION_MAP_XML')==1
try:apply_version_map_capability(info,b'wrong',manifest)
except ValueError:pass
else:raise AssertionError('unverified baseline embedded')
env=dict(os.environ,JAVA_HOME='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home')
with tempfile.TemporaryDirectory(prefix='mobile-version-policy-') as tmp:
 p=Path(tmp);(p/'fixtures.json').write_text(json.dumps(cases))
 subprocess.run([str(SDK/'bin/amxmlc'),'-debug=true','-omit-trace-statements=false','-source-path+='+str(ROOT/'connected'),'-output='+str(p/'test.swf'),str(ROOT/'tests/MobileVersionMapTests.as')],env=env,check=True)
 (p/'app.xml').write_text('<application xmlns="http://ns.adobe.com/air/application/51.4"><id>org.ekoloko.mobile.map.tests</id><versionNumber>1.0.0</versionNumber><filename>MapTests</filename><initialWindow><content>test.swf</content><visible>false</visible></initialWindow><supportedProfiles>extendedDesktop</supportedProfiles></application>')
 r=subprocess.run([str(SDK/'bin/adl'),str(p/'app.xml'),str(p)],env=env,text=True,capture_output=True,timeout=30)
 print(r.stdout,r.stderr);assert r.returncode==0 and 'VERSION_MAP_POLICY_PASS cases=29' in r.stdout+r.stderr
