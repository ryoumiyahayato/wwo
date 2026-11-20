"""Reassemble Library's ZIP-wrapped raw chunks using only Python standard library.
Usage: python restore_raw_evidence.py /folder/with/all15zip /output/full.zip
"""
import hashlib,json,sys,zipfile
from pathlib import Path
folder=Path(sys.argv[1]);output=Path(sys.argv[2]);manifest=json.loads(Path(__file__).with_name('raw_parts_manifest.json').read_text());whole=hashlib.sha256();total=0
if output.exists():raise SystemExit('Output exists; choose a new path to avoid overwriting evidence.')
try:
 with output.open('xb') as out:
  for row in manifest['parts']:
   p=folder/row['filename'];part=hashlib.sha256();length=0
   with zipfile.ZipFile(p) as z:
    assert json.loads(z.read('PART.json'))==row,p
    with z.open(row['member']) as f:
     while chunk:=f.read(1048576):out.write(chunk);whole.update(chunk);part.update(chunk);length+=len(chunk)
   assert length==row['bytes'] and part.hexdigest()==row['sha256'],p;total+=length;print('verified',row['index'],flush=True)
 assert total==manifest['original_bytes'] and whole.hexdigest()==manifest['original_sha256']
 print('PASS',output,total,whole.hexdigest())
except BaseException:
 print('Assembly failed; any partial output is NOT a verified full archive.',file=sys.stderr);raise
