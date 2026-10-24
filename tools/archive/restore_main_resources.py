"""Restore archived main-WWO resources into missing paths, without old-machine links."""
import argparse,base64,io,json,pathlib,subprocess,urllib.request,urllib.error,zipfile,time,shutil,os
P=pathlib.Path
class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,*a,**k):return None
def main():
 a=argparse.ArgumentParser(description=__doc__);a.add_argument('--inventory',type=P,required=True);a.add_argument('--destination',type=P,required=True);a.add_argument('--scope',choices=['runtime','rebuild','history','private_test','all'],default='all');a.add_argument('--only-path',action='append',help='Restore only these exact inventory paths');x=a.parse_args()
 d=json.loads(x.inventory.read_text(encoding='utf-8'));s=d['resource_supplement'];repo='ryoumiyahayato/wwo'
 assert d['repository']==repo and s['state']=='UPLOADED_VERIFIED'
 root=x.destination.resolve();all_rows=s['files']+s.get('reused_git_files',[])
 rows=[r for r in all_rows if (x.scope=='all' or r['kind']==x.scope) and (not x.only_path or r['path'] in x.only_path)]
 aliases=[r for r in s.get('file_aliases',[]) if (x.scope=='all' or r['kind']==x.scope) and (not x.only_path or r['path'] in x.only_path)]
 by_path={r['path']:r for r in all_rows}
 for alias in aliases:
  if alias['source_path'] not in {r['path'] for r in rows}:rows.append(by_path[alias['source_path']])
 if not rows:raise RuntimeError('No files selected')
 root.mkdir(parents=True,exist_ok=True)
 token=subprocess.check_output(['gh','auth','token'],text=True).strip();skipped=set()
 parts={p['name']:p for p in s['parts']}
 for row in rows+aliases:
  relative=P(row['path'])
  if relative.drive or relative.is_absolute() or '..' in relative.parts:raise RuntimeError('Unsafe archive path')
  target=root/relative
  if not target.resolve().is_relative_to(root):raise RuntimeError('Destination escapes restore root')
  for ancestor in target.parents:
   if ancestor==root.parent:break
   if ancestor.exists() and ancestor.lstat().st_file_attributes&0x400:raise RuntimeError('Reparse destination retained')
  if target.exists() or target.is_symlink():
   if row.get('already_remote') and target.is_file() and not target.is_symlink() and not target.lstat().st_file_attributes&0x400:
    req=urllib.request.Request('https://api.github.com/repos/'+repo+'/git/blobs/'+row['git_blob'],headers={'Authorization':'Bearer '+token,'Accept':'application/vnd.github.raw+json'})
    with urllib.request.urlopen(req,timeout=60) as response:existing_cloud=response.read()
    if target.read_bytes()==existing_cloud:skipped.add(row['path']);continue
   raise FileExistsError('Existing input retained: '+str(target))
 rows=[r for r in rows if r['path'] not in skipped];selected={n for r in rows for n in r['parts']}
 if skipped:print('EXISTING_GIT_FILES_REUSED',len(skipped),flush=True)
 for row in rows:
  if row['bytes']==0 and not row.get('already_remote') and not row.get('parts'):
   target=root/row['path'];target.parent.mkdir(parents=True,exist_ok=True);target.open('xb').close()
 for package in s['packages']:
  members=[n for n in package['members'] if n in selected]
  if not members:continue
  assert package['state']=='UPLOADED_VERIFIED'
  req=urllib.request.Request('https://api.github.com/repos/'+repo+'/releases/assets/'+str(package['asset_id'])+'?nonce='+str(time.time_ns()),headers={'Authorization':'Bearer '+token,'Accept':'application/octet-stream','User-Agent':'WWO-Main-Resource-Restore'})
  try:response=urllib.request.build_opener(NoRedirect()).open(req,timeout=60)
  except urllib.error.HTTPError as error:
   if error.code not in (301,302,303,307,308):raise
   response=urllib.request.urlopen(error.headers['Location'],timeout=120)
  with response:raw=response.read()
  if len(raw)!=package['bytes']:raise RuntimeError('Incomplete cloud package; retain partial new destination and retry only after review')
  with zipfile.ZipFile(io.BytesIO(raw)) as z:
   if set(z.namelist())!=set(package['members']):raise RuntimeError('Package member map differs')
   for name in members:
    part=parts[name];target=root/part['path'];target.parent.mkdir(parents=True,exist_ok=True)
    if part['offset']==0:
     mode='xb'
    else:
     if not target.is_file() or target.stat().st_size!=part['offset']:raise RuntimeError('Missing or conflicting preceding file part')
     mode='ab'
    data=z.read(name) # ZIP's built-in CRC is enforced here.
    if len(data)!=part['bytes']:raise RuntimeError('File part length differs')
    with target.open(mode) as output:output.write(data)
  print('CLOUD_RESOURCE_PACKAGE_RESTORED',package['name'],flush=True)
 for row in rows:
  if not row.get('already_remote'):continue
  req=urllib.request.Request('https://api.github.com/repos/'+repo+'/git/blobs/'+row['git_blob'],headers={'Authorization':'Bearer '+token,'Accept':'application/vnd.github+json','User-Agent':'WWO-Main-Resource-Restore'})
  with urllib.request.urlopen(req,timeout=60) as response:data=base64.b64decode(json.load(response)['content'])
  if len(data)!=row['bytes']:raise RuntimeError('Reused Git evidence length differs')
  target=root/row['path'];target.parent.mkdir(parents=True,exist_ok=True)
  with target.open('xb') as output:output.write(data)
 for row in rows:
  if (root/row['path']).stat().st_size!=row['bytes']:raise RuntimeError('Incomplete restored file: '+row['path'])
 for alias in aliases:
  target=root/alias['path'];target.parent.mkdir(parents=True,exist_ok=True)
  with (root/alias['source_path']).open('rb') as source,target.open('xb') as output:shutil.copyfileobj(source,output,1024*1024)
  if target.stat().st_size!=alias['bytes']:raise RuntimeError('Incomplete restored alias: '+alias['path'])
 for row in rows+aliases:
  if 'mtime_ns' in row:os.utime(root/row['path'],ns=(row['mtime_ns'],row['mtime_ns']))
 print('RESOURCE_FILE_RESTORE_COMPLETED',len(rows)+len(aliases),sum(r['bytes'] for r in rows+aliases),flush=True)
 print('File/ZIP checks only. No engine, gameplay or complete world rebuild validation was run.',flush=True)
if __name__=='__main__':main()
