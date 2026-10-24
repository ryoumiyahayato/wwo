"""Restore only from a downloaded manifest and authenticated GitHub packages.
No original source path in the manifest is ever opened by this program.
"""
import argparse, base64, gzip, hashlib, json, os, pathlib, re, subprocess, urllib.request, urllib.error, zipfile
P=pathlib.Path
REPO='ryoumiyahayato/wwo'
CURRENT='formal-combat-authority-20261024/'
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*a,**k):return None
def digest(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest()
def download(package,destination):
    if destination.exists():raise FileExistsError('A new cloud download directory is required: '+str(destination))
    token=subprocess.check_output(['gh','auth','token'],text=True).strip()
    h=hashlib.sha256();size=0
    with destination.open('xb') as f:
        for part in package.get('parts',[package]):
            req=urllib.request.Request('https://api.github.com/repos/'+REPO+'/releases/assets/'+str(part['asset_id']),headers={'Authorization':'Bearer '+token,'Accept':'application/octet-stream','User-Agent':'WWO-Military-Cloud-Restore'})
            try:response=urllib.request.build_opener(NoRedirect()).open(req,timeout=60)
            except urllib.error.HTTPError as e:
                if e.code not in (301,302,303,307,308):raise
                response=urllib.request.urlopen(urllib.request.Request(e.headers['Location']),timeout=120)
            ph=hashlib.sha256();pn=0
            with response:
                while True:
                    b=response.read(1024*1024)
                    if not b:break
                    f.write(b);h.update(b);ph.update(b);size+=len(b);pn+=len(b)
            if pn!=part['bytes'] or ph.hexdigest()!=part['sha256']:raise ValueError('Cloud segment differs: '+part['name'])
    if size!=package['bytes'] or h.hexdigest()!=package['sha256']:raise ValueError('Cloud package checksum/length differs: '+package['name'])
    print('CLOUD_DOWNLOAD_VERIFIED',package['name'],size,flush=True)
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest',type=P,required=True)
    parser.add_argument('--packages',type=P,required=True)
    parser.add_argument('--destination',type=P,required=True)
    parser.add_argument('--user-dir',required=True)
    parser.add_argument('--archive-commit',required=True)
    parser.add_argument('--download',action='store_true')
    parser.add_argument('--include-recovery-evidence',action='store_true')
    a=parser.parse_args()
    if a.destination.exists():raise FileExistsError('Destination must be new; no overwrite')
    if not re.fullmatch(r'WWO-FormalPractice-[A-Za-z0-9_-]+',a.user_dir):raise ValueError('Dedicated military test user directory required')
    with gzip.open(a.manifest,'rt',encoding='utf-8') as f:d=json.load(f)
    if d['archive_repository']!=REPO:raise ValueError('Archive repository mismatch')
    selected=[]
    for row in d['files']:
        p=row['path'];rel=None
        if p.startswith(CURRENT+'runtime/') and not row['cache']:rel=p[len(CURRENT):]
        elif p.startswith(CURRENT+'private_state/'):rel=p[len(CURRENT):]
        elif a.include_recovery_evidence and p.startswith('formal-practice-recovery-20261023/private_state/'):
            rel='recovery_evidence/'+p[len('formal-practice-recovery-20261023/'):]
        if rel is None:continue
        if 'object' not in row:raise ValueError('Current required file missing from archive: '+p)
        if P(rel).is_absolute() or '..' in P(rel).parts:raise ValueError('Unsafe restore path')
        selected.append((row,rel))
    chunks=d['chunks'];objects=d['objects'];needed={chunks[sha]['pack'] for row,rel in selected for sha in objects[row['object']]['parts']}
    packages={p['name']:p for p in d['packages']}
    a.packages.mkdir(parents=True,exist_ok=True)
    for name in sorted(needed):
        package=packages[name];path=a.packages/name
        if a.download:download(package,path)
        elif not path.is_file() or path.stat().st_size!=package['bytes'] or digest(path)!=package['sha256']:raise ValueError('Previously downloaded package mismatch: '+name)
    a.destination.mkdir(parents=True)
    handles={};count=bytes_=0
    try:
        for row,rel in selected:
            target=a.destination/rel;target.parent.mkdir(parents=True,exist_ok=True);h=hashlib.sha256();size=0
            with target.open('xb') as out:
                for sha in objects[row['object']]['parts']:
                    name=chunks[sha]['pack']
                    if name not in handles:handles[name]=zipfile.ZipFile(a.packages/name)
                    part=hashlib.sha256();partsize=0
                    with handles[name].open(sha) as src:
                        for b in iter(lambda:src.read(1024*1024),b''):out.write(b);h.update(b);part.update(b);size+=len(b);partsize+=len(b)
                    if part.hexdigest()!=sha or partsize!=chunks[sha]['size']:raise ValueError('Archived chunk differs: '+rel)
            if h.hexdigest()!=row['object'] or size!=row['size']:raise ValueError('Restored file differs: '+rel)
            if target.stat().st_nlink!=1:raise ValueError('Restore must materialize ordinary independent files')
            count+=1;bytes_+=size
    finally:
        for z in handles.values():z.close()
    project=a.destination/'runtime/project.godot';text=project.read_bytes()
    changed,n=re.subn(rb'config/custom_user_dir_name="[^"]+"',('config/custom_user_dir_name="'+a.user_dir+'"').encode(),text)
    if n!=1:raise ValueError('Expected one dedicated user-directory setting')
    project.write_bytes(changed)
    tools=a.destination/'tools';tools.mkdir(exist_ok=True)
    launcher='''param([string]$GodotExe='D:\\tools\\Godot-4.6.3\\Godot_v4.6.3-stable_win64.exe',[switch]$VerifyCold)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$argsList=@('--path',(Join-Path $root 'runtime'),'--resolution','1280x720','res://authority/main.tscn','--',('--practice-bundle='+ (Join-Path $root 'private_state/authority_success_portable.json')))
if($VerifyCold){$argsList+=@('--authority-tour=cold',('--authority-output='+(Join-Path $root 'authority_native.json')))}
$quoted=$argsList|ForEach-Object {if($_ -match '\\s'){'"'+$_+'"'}else{$_}}
$p=Start-Process -FilePath $GodotExe -ArgumentList $quoted -PassThru -WindowStyle Hidden -Wait
exit $p.ExitCode
'''
    (tools/'Run-Military.ps1').write_text(launcher,encoding='utf-8')
    receipt={'repository':REPO,'archive_commit':a.archive_commit,'manifest_sha256':digest(a.manifest),'materialized_files':count,'materialized_bytes':bytes_,'all_restored_bytes_verified_before_allowed_changes':True,'old_source_reads':False,'resource_hardlinks_created':False,'allowed_changes':[{'file':'runtime/project.godot','field':'config/custom_user_dir_name','value':a.user_dir}],'packages':[{'name':n,'ids':[p['asset_id'] for p in packages[n].get('parts',[packages[n]])],'bytes':packages[n]['bytes'],'sha256':packages[n]['sha256']} for n in sorted(needed)],'entry':'tools/Run-Military.ps1','status':'FILE_RESTORE_VERIFIED_ENGINE_NOT_YET_RUN'}
    (a.destination/'RESTORE_RECEIPT.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8')
    print('FILE_RESTORE_VERIFIED',count,bytes_,'PACKAGES',len(needed),flush=True)
if __name__=='__main__':main()
