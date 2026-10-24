"""Restore archived main-WWO resources into missing paths, without old-machine links."""
import argparse,base64,io,json,pathlib,subprocess,urllib.request,urllib.error,zipfile,time
P=pathlib.Path
class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,*a,**k):return None
def main():
 a=argparse.ArgumentParser(description=__doc__);a.add_argument('--inventory',type=P,required=True);a.add_argument('--destination',type=P,required=True);a.add_argument('--scope',choices=['runtime','rebuild','history','private_test','all'],default='all');a.add_argument('--only-path',action='append',help='Restore only these exact inventory paths');x=a.parse_args()
 d=json.loads(x.inventory.read_text(encoding='utf-8'));s=d['resource_supplement'];repo='ryoumiyahayato/wwo'
 assert d['repository']==repo and s['state']=='UPLOADED_VERIFIED'
 root=x.destination.resolve();rows=[r for r in s['files']+s.get('reused_git_files',[]) if (x.scope=='all' or r['kind']==x.scope) and (not x.only_path or r['path'] in x.only_path)]
 if not rows:raise RuntimeError('No files selected')
 root.mkdir(parents=True,exist_ok=True)
 parts={p['name']:p for p in s['parts']};selected={n for r in rows for n in r['parts']}
 for row in rows:
  relative=P(row['path'])
  if relative.drive or relative.is_absolute() or '..' in relative.parts:raise RuntimeError('Unsafe archive path')
  target=root/relative
  if not target.resolve().is_relative_to(root):raise RuntimeError('Destination escapes restore root')
  if target.exists() or target.is_symlink():raise FileExistsError('Existing input retained: '+str(target))
  for ancestor in target.parents:
   if ancestor==root.parent:break
   if ancestor.exists() and ancestor.lstat().st_file_attributes&0x400:raise RuntimeError('Reparse destination retained')
 token=subprocess.check_output(['gh','auth','token'],text=True).strip()
 for row in rows:
  if row['bytes']==0 and not row.get('already_remote'):
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
 print('RESOURCE_FILE_RESTORE_COMPLETED',len(rows),sum(r['bytes'] for r in rows),flush=True)
 print('File/ZIP checks only. No engine, gameplay or complete world rebuild validation was run.',flush=True)
if __name__=='__main__':main()
