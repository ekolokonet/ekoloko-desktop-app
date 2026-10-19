"""Prepare a verified public-only mobile delta, with explicit portable permissions."""
from pathlib import Path
import argparse, hashlib, json, shutil, sys, tarfile
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import publish_release as release

def prepare(source, baseline, public_key, output):
    source,baseline,output=map(Path,(source,baseline,output))
    public=Path(public_key).read_bytes()
    oldp,old=release.read_current(baseline,public,False)
    newp,new=release.read_current(source,public,True)
    old_hashes={e['sha256'] for e in old['assets'].values()}
    hashes=sorted({e['sha256'] for e in new['assets'].values()}-old_hashes)
    output.mkdir(exist_ok=False)
    payload=output/'payload';payload.mkdir()
    files=['objects/'+h+'.swf' for h in hashes]+[newp['manifest'],newp['signature']]
    for rel in files:
        target=payload/rel;target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(source/rel,target)
    shutil.copyfile(source/'current.json',payload/'candidate-current.json')
    files.append('candidate-current.json')
    archive=output/'mobile-release-delta.tar.gz'
    with tarfile.open(archive,'w:gz',compresslevel=9) as tar:
        for rel in files:
            path=payload/rel
            info=tar.gettarinfo(str(path),arcname=rel)
            info.mode=0o644;info.uid=info.gid=0;info.uname=info.gname='root'
            with path.open('rb') as content:tar.addfile(info,content)
    with tarfile.open(archive) as tar:
        members=tar.getmembers()
        assert [m.name for m in members]==files
        assert all(m.isfile() and m.mode==0o644 for m in members)
    sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
    receipt={'baselineRelease':oldp['releaseId'],'baselineManifestSha256':oldp['manifestSha256'],
        'baselinePointerSha256':sha(baseline/'current.json'),'releaseId':newp['releaseId'],
        'generation':newp['generation'],'manifestSha256':newp['manifestSha256'],
        'versionConfigSha256':new['versionConfigSha256'],'newObjects':hashes,
        'compressedBytes':archive.stat().st_size,'archiveSha256':sha(archive),'files':files,
        'allPublicMemberModes':'0644','releaseDirectoryMode':'0755','privateKeysIncluded':False,
        'sourceSignatureVerified':True,'allCandidateObjectsVerified':True,'publicHTTPVerified':False}
    template=Path(__file__).resolve().parents[1]/'server/mobile-releases/activate_delta.sh.in'
    script=template.read_text().replace('@@ARCHIVE_SHA@@',receipt['archiveSha256']).replace('@@BASELINE_SHA@@',receipt['baselinePointerSha256']).replace('@@RELEASE_ID@@',receipt['releaseId'])
    assert '@@' not in script
    (output/'activate-delta.sh').write_text(script)
    receipt['activationScriptSha256']=sha(output/'activate-delta.sh')
    (output/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    return receipt

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('source','baseline','public-key','output'):p.add_argument('--'+name,required=True,type=Path)
    args=p.parse_args()
    print(json.dumps(prepare(args.source,args.baseline,args.public_key,args.output)))
