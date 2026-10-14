"""Compressed geometry sidecars for strategic map content."""
from pathlib import Path
import json,zlib,sys
ROOT=Path(__file__).resolve().parents[2];DIRECTORY=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else ROOT/'data/strategic'
def read(path):return json.loads(path.read_text(encoding='utf8'))
def write(path,value):path.write_text(json.dumps(value,ensure_ascii=False,separators=(',',':')),encoding='utf8')
index=read(DIRECTORY/'index.json');descriptors=list(index['regions'])+list(index['coast_regions'])
for parent in index['coast_regions']:descriptors+=parent.get('medium_regions',[])
report=[]
for descriptor in descriptors:
 path=DIRECTORY/Path(descriptor['path']).name;document=read(path)
 geometries={}
 for fact in document['evidence_catalog']['facts']:
  feature=fact['value']
  if feature['kind']=='settlement':continue
  if 'geometry_asset' in feature:raise RuntimeError('Pack only newly generated inline source data')
  fields=['geometry','lod_geometry']+(['lod_visual_reference_indices'] if 'lod_visual_reference_indices' in feature else [])
  geometries[feature['id']]={key:feature.pop(key) for key in fields}
 if geometries:
  raw=json.dumps(geometries,ensure_ascii=False,separators=(',',':')).encode('utf8');packed=zlib.compress(raw,9)
  asset_path=path.with_suffix('.geom');asset_path.write_bytes(packed)
  asset={'path':'res://data/strategic/'+asset_path.name,'encoding':'ZLIB_JSON_UTF8','bytes':len(packed),'decoded_bytes':len(raw)}
  for fact in document['evidence_catalog']['facts']:
   if fact['value']['id'] in geometries:fact['value']['geometry_asset']=asset
  document['metadata']['geometry_encoding']='ZLIB_JSON_UTF8'
 write(path,document);payload=path.read_bytes();descriptor.update({'bytes':len(payload)})
 report.append({'id':descriptor['id'],'manifest_bytes':len(payload),'packed_geometry_bytes':len(packed) if geometries else 0,'decoded_geometry_bytes':len(raw) if geometries else 0})
write(DIRECTORY/'index.json',index)
print(json.dumps({'shards':len(report),'manifest_bytes':sum(r['manifest_bytes'] for r in report),'geometry_bytes':sum(r['packed_geometry_bytes'] for r in report),'geometry_decoded_bytes':sum(r['decoded_geometry_bytes'] for r in report)}))
