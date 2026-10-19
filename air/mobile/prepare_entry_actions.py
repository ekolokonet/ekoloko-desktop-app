"""Build the mobile deletion leaf from original login glyphs/art; never imports a font."""
from pathlib import Path
import copy,hashlib,json,struct,subprocess,sys,xml.etree.ElementTree as E
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT.parent/'scripts'))
from swf import unpack,pack
from prepare_assets import visual_tags
SRC=ROOT.parent/'build/mobile-update-152/sources/website/iw/login_iw.swf'
PIN='b17450b4a41bb6be26255431eedf0ca30fd9d5e489c7e189e710b15f652da4f0'
JAVA='/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home/bin/java'
FFDEC='/Applications/FFDec.app/Contents/Resources/ffdec.jar'
def main():
 raw=SRC.read_bytes();assert hashlib.sha256(raw).hexdigest()==PIN
 work=ROOT.parent/'build/mobile-entry-actions';work.mkdir(exist_ok=True)
 subprocess.run([JAVA,'-jar',FFDEC,'-swf2xml',str(SRC),str(work/'login.xml')],check=True,capture_output=True)
 root=E.parse(work/'login.xml');tags=root.getroot().find('tags')
 def by(key,value):return next(t for t in tags if t.get(key)==str(value))
 fonts={i:by('fontID',i) for i in [623,636]};codes={i:[int(x.text) for x in f.find('codeTable')] for i,f in fonts.items()}
 # Reuse actual authored advances of each embedded glyph, normalised to28px.
 advances={i:{} for i in fonts}
 for tag in tags:
  if tag.get('type') not in ('DefineTextTag','DefineText2Tag'):continue
  font=None;height=560
  for rec in tag.find('textRecords'):
   if rec.get('styleFlagsHasFont')=='true':font=int(rec.get('fontId'));height=int(rec.get('textHeight'))
   if font not in advances:continue
   for g in rec.find('glyphEntries'):
    gi=int(g.get('glyphIndex'));adv=round(int(g.get('glyphAdvance'))*560/height)
    advances[font][gi]=max(adv,advances[font].get(gi,0))
 ids=[int(t.get(k)) for t in tags for k in ('characterID','spriteId','buttonId','fontID','shapeId') if t.get(k)]
 text_id=max(ids)+1;sprite_id=text_id+1
 top=copy.deepcopy(by('characterID',829));top.set('characterID',str(text_id))
 top_sprite=copy.deepcopy(by('spriteId',847));top_sprite.set('spriteId',str(sprite_id))
 top_sprite.find('subTags/item').set('characterId',str(text_id))
 bottom=by('characterID',865)
 def replace(tag,font,logical):
  records=tag.find('textRecords');assert len(records)==1
  rec=records[0];glyphs=rec.find('glyphEntries');glyphs.clear()
  indices=[codes[font].index(ord(c)) for c in logical[::-1]]
  width=sum(advances[font][i] for i in indices);bounds=tag.find('textBounds')
  # Preserve original text rectangle and centre the new word within it.
  rec.set('styleFlagsHasXOffset','true');rec.set('xOffset',str(round((int(bounds.get('Xmax'))-width)/2)))
  for i in indices:E.SubElement(glyphs,'item',type='GLYPHENTRY',glyphAdvance=str(advances[font][i]),glyphIndex=str(i))
 replace(top,623,'מחיקת');replace(bottom,636,'חשבון')
 button=by('buttonId',868)
 for record in button.find('characters'):
  if record.get('characterId')=='847':record.set('characterId',str(sprite_id))
 at=list(tags).index(button);tags.insert(at,top);tags.insert(at+1,top_sprite)
 root.write(work/'patched.xml',encoding='utf-8',xml_declaration=True)
 subprocess.run([JAVA,'-jar',FFDEC,'-xml2swf',str(work/'patched.xml'),str(work/'patched.swf')],check=True,capture_output=True)
 version,header,original=unpack(raw);_,_,patched=unpack((work/'patched.swf').read_bytes())
 wanted={(11,865),(34,868),(11,text_id),(39,sprite_id)}
 changed={(k,struct.unpack_from('<H',d)[0]):(k,d) for k,d in patched if k in (11,34,39) and len(d)>2 and (k,struct.unpack_from('<H',d)[0]) in wanted}
 assert set(changed)==wanted
 output=[]
 for k,d in original:
  key=(k,struct.unpack_from('<H',d)[0]) if k in (11,34,39) and len(d)>2 else None
  if key==(34,868):output.extend([changed[(11,text_id)],changed[(39,sprite_id)]])
  output.append(changed.get(key,(k,d)))
 visual=[(k,d) for k,d in visual_tags(output) if k not in (76,0)]
 visual.append((76,struct.pack('<HH',1,868)+b'AccountDeletionLeaf\0'));visual.append((0,b''))
 target=ROOT/'assets/account-deletion-leaf.swf';target.write_bytes(pack(version,header,visual))
 receipt={'sourceSha256':PIN,'label':'מחיקת חשבון','fonts':['Spacer Bold','SpacerBlack'],'fontBytesUnmodified':True,'leafGeometryUnmodified':True,'modifiedTextIds':[865,text_id],'newSpriteId':sprite_id,'outputSha256':hashlib.sha256(target.read_bytes()).hexdigest()}
 (ROOT/'assets/account-deletion-leaf.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n');print(json.dumps(receipt,ensure_ascii=False))
if __name__=='__main__':main()
