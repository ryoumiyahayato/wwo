
from pathlib import Path
import fnmatch, json, subprocess, sys, urllib.error, urllib.request, shutil
tag, pattern, destination = sys.argv[1:]
target=Path(destination)
target.mkdir(parents=True,exist_ok=True)
repo='ryoumiyahayato/wwo'
release=json.loads(subprocess.check_output(['gh','api',f'repos/{repo}/releases/tags/{tag}']))
assets=[entry for entry in release['assets'] if fnmatch.fnmatchcase(entry['name'], pattern)]
if not assets:
    raise SystemExit('No matching release assets')
token=subprocess.check_output(['gh','auth','token'],text=True).strip()
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args): return None
client=urllib.request.build_opener(NoRedirect())
for entry in assets:
    name=entry['name']
    filename=target/name
    partial=filename.with_suffix(filename.suffix+'.part')
    if filename.exists() and filename.stat().st_size==entry['size']:
        print(name,entry['size'],'already restored',flush=True)
        continue
    offset=partial.stat().st_size if partial.exists() else 0
    if offset==entry['size']:
        partial.replace(filename)
        print(name,entry['size'],flush=True)
        continue
    if offset>entry['size']:
        offset=0
    request=urllib.request.Request(entry['url'],headers={'Accept':'application/octet-stream','Authorization':f'Bearer {token}','User-Agent':'WWO-Asset-Recovery'})
    try:
        download=client.open(request,timeout=45)
    except urllib.error.HTTPError as error:
        if error.code!=302 or not error.headers.get('Location'):
            raise
        signed=urllib.request.Request(error.headers['Location'])
        if offset:
            signed.add_header('Range',f'bytes={offset}-')
        download=urllib.request.urlopen(signed,timeout=45)
    if download.status!=206:
        offset=0
    elif not download.headers.get('Content-Range','').startswith(f'bytes {offset}-'):
        raise ValueError(f'Unexpected partial response for {name}')
    with download, partial.open('ab' if offset else 'wb') as out:
        transferred=offset
        next_log=(offset//(256*1024*1024)+1)*(256*1024*1024)
        for chunk in iter(lambda:download.read(2*1024*1024),b''):
            out.write(chunk)
            transferred+=len(chunk)
            if transferred>=next_log:
                out.flush()
                print(f'{name} recovered {transferred} of {entry["size"]} bytes',flush=True)
                next_log+=256*1024*1024
    if partial.stat().st_size!=entry['size']:
        raise ValueError(f'Remote asset length differs for {name}')
    partial.replace(filename)
    print(name,entry['size'],flush=True)
