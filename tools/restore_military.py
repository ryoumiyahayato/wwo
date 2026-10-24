"""Restore only from a downloaded manifest and authenticated GitHub packages.
No original source path in the manifest is ever opened by this program.
"""
import argparse, base64, gzip, hashlib, json, os, pathlib, re, subprocess, urllib.request, urllib.error, zipfile, time, http.client
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
def read_cloud_part(part):
    token=subprocess.check_output(['gh','auth','token'],text=True).strip()
    for attempt in range(2):
        try:
            req=urllib.request.Request('https://api.github.com/repos/'+REPO+'/releases/assets/'+str(part['asset_id'])+'?download=1&nonce='+str(time.time_ns()),headers={'Authorization':'Bearer '+token,'Accept':'application/octet-stream','Cache-Control':'no-cache','User-Agent':'WWO-Military-Cloud-Restore'})
            try:response=urllib.request.build_opener(NoRedirect()).open(req,timeout=60)
            except urllib.error.HTTPError as e:
                if e.code not in (301,302,303,307,308):raise
                response=urllib.request.urlopen(urllib.request.Request(e.headers['Location']),timeout=120)
            with response:
                data=response.read(part['bytes']+1)
            if len(data)!=part['bytes'] or hashlib.sha256(data).hexdigest()!=part['sha256']:raise ValueError('Cloud segment differs: '+part['name'])
            return data
        except (urllib.error.URLError,TimeoutError,http.client.IncompleteRead) as e:
            if attempt:raise
            print('RETRY_TRANSIENT_CLOUD_READ',part['name'],type(e).__name__,flush=True)
def download(package,destination):
    receipts=destination.parent/'.cloud-download-receipts.jsonl';known={}
    if receipts.exists():
        for line in receipts.read_text(encoding='utf-8').splitlines():
            row=json.loads(line);known[row['name']]=row
    parts=package.get('parts',[package]);h=hashlib.sha256();size=0;skip=0
    if destination.exists():
        with destination.open('rb') as existing:
            for part in parts:
                row=known.get(part['name'])
                if not row or row['id']!=part['asset_id'] or row['sha256']!=part['sha256']:break
                data=existing.read(part['bytes'])
                if len(data)!=part['bytes'] or hashlib.sha256(data).hexdigest()!=part['sha256']:raise ValueError('Existing cloud-download segment differs')
                h.update(data);size+=len(data);skip+=1
            if existing.read(1):raise ValueError('Unrecorded partial download retained; not treated as verified')
    with destination.open('ab' if destination.exists() else 'xb') as f:
        for part in parts[skip:]:
            data=read_cloud_part(part);f.write(data);f.flush();h.update(data);size+=len(data)
            with receipts.open('a',encoding='utf-8') as log:log.write(json.dumps({'name':part['name'],'id':part['asset_id'],'sha256':part['sha256'],'bytes':part['bytes'],'time':time.time()})+'\n')
            print('CLOUD_SEGMENT_VERIFIED',part['name'],len(data),flush=True)
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
    parser.add_argument('--archive-prefix',help='Explicit historical directory prefix; file restoration only, no automatic engine run')
    a=parser.parse_args()
    if a.destination.exists():raise FileExistsError('Destination must be new; no overwrite')
    if not re.fullmatch(r'WWO-FormalPractice-[A-Za-z0-9_-]+',a.user_dir):raise ValueError('Dedicated military test user directory required')
    with gzip.open(a.manifest,'rt',encoding='utf-8') as f:d=json.load(f)
    if d['archive_repository']!=REPO:raise ValueError('Archive repository mismatch')
    selected=[];historical_metadata_changes=[]
    historical=a.archive_prefix.strip('/')+'/' if a.archive_prefix else None
    if historical and (P(historical).is_absolute() or '..' in P(historical).parts):raise ValueError('Unsafe historical prefix')
    for row in d['files']:
        p=row['path'];rel=None
        if historical:
            if p.startswith(historical):rel=p[len(historical):]
        elif p.startswith(CURRENT+'runtime/') and not row['cache']:rel=p[len(CURRENT):]
        elif p.startswith(CURRENT+'private_state/'):rel=p[len(CURRENT):]
        elif a.include_recovery_evidence and p.startswith('formal-practice-recovery-20261023/private_state/'):
            rel='recovery_evidence/'+p[len('formal-practice-recovery-20261023/'):]
        if rel is None:continue
        if historical and P(rel).name=='.git':
            oldrel=rel;rel='.archive_origin/'+rel+'.txt';historical_metadata_changes.append({'original':oldrel,'restored':rel,'reason':'preserve pointer bytes without reconnecting the old shared main Git worktree'})
        if 'object' not in row:raise ValueError('Current required file missing from archive: '+p)
        if P(rel).is_absolute() or '..' in P(rel).parts:raise ValueError('Unsafe restore path')
        selected.append((row,rel))
    if not selected:raise ValueError('No archived files for the requested prefix')
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
    if historical:
        receipt={'repository':REPO,'archive_commit':a.archive_commit,'archive_prefix':historical,'materialized_files':count,'materialized_bytes':bytes_,'old_source_reads':False,'resource_hardlinks_created':False,'metadata_path_changes':historical_metadata_changes,'status':'HISTORICAL_FILE_RESTORE_VERIFIED_ENGINE_NOT_RUN','scope':'exact archived file contents; historical launch/dependency limitations remain as originally documented'}
        rp=a.destination/'ARCHIVE_FILE_RESTORE_RECEIPT.json'
        if rp.exists():raise FileExistsError('Do not overwrite an original historical receipt')
        rp.write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8');print('HISTORICAL_FILE_RESTORE_VERIFIED',historical,count,bytes_,flush=True);return
    project=a.destination/'runtime/project.godot';text=project.read_bytes()
    changed,n=re.subn(rb'config/custom_user_dir_name="[^"]+"',('config/custom_user_dir_name="'+a.user_dir+'"').encode(),text)
    if n!=1:raise ValueError('Expected one dedicated user-directory setting')
    project.write_bytes(changed)
    recovery_script=a.destination/'runtime/authority/recovery_checks.gd'
    old=b'FileAccess.open("D:/programs/WWO/research/military/formal-combat-authority-20261024/run/recovery_checks.json",FileAccess.WRITE)'
    new=b'FileAccess.open(task_root+"/recovery_checks.json",FileAccess.WRITE)'
    original=recovery_script.read_bytes()
    if original.count(old)!=1:raise ValueError('Expected the declared original recovery-report path')
    recovery_script.write_bytes(original.replace(old,new))
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
    receipt={'repository':REPO,'archive_commit':a.archive_commit,'manifest_sha256':digest(a.manifest),'materialized_files':count,'materialized_bytes':bytes_,'all_restored_bytes_verified_before_allowed_changes':True,'old_source_reads':False,'resource_hardlinks_created':False,'filesystem_policy':'new independent regular files; source READONLY/link flags are not reapplied','allowed_changes':[{'file':'runtime/project.godot','field':'config/custom_user_dir_name','value':a.user_dir},{'file':'runtime/authority/recovery_checks.gd','field':'report output path','value':'task_root + /recovery_checks.json; prevents writing into original military source'}],'packages':[{'name':n,'ids':[p['asset_id'] for p in packages[n].get('parts',[packages[n]])],'bytes':packages[n]['bytes'],'sha256':packages[n]['sha256']} for n in sorted(needed)],'entry':'tools/Run-Military.ps1','status':'FILE_RESTORE_VERIFIED_ENGINE_NOT_YET_RUN'}
    receipt['critical_input_sha256']={rel:row['object'] for row,rel in selected if rel.startswith('private_state/') and P(rel).name in {'authority_success_portable.json','authority_revoked_portable.json','authority_success_formal.json','authority_revoked_formal.json'}}
    (a.destination/'RESTORE_RECEIPT.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8')
    print('FILE_RESTORE_VERIFIED',count,bytes_,'PACKAGES',len(needed),flush=True)
if __name__=='__main__':main()
