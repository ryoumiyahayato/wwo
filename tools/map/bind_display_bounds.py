"""Correct sub-centimetre affine clipping drift in display geometry."""
from pathlib import Path
import json,zlib,sys
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/map'))
from build_geographic_foundation import bound_display_coordinates
directory=ROOT/'data/strategic'
def read(path):return json.loads(path.read_text(encoding='utf8'))
def write(path,data):path.write_text(json.dumps(data,ensure_ascii=False,separators=(',',':')),encoding='utf8')
index=read(directory/'index.json');descriptors=list(index['coast_regions'])
for parent in index['coast_regions']:descriptors+=parent.get('medium_regions',[])
changed=[]
for descriptor in descriptors:
 path=directory/Path(descriptor['path']).name;document=read(path);asset_path=path.with_suffix('.geom')
 if not asset_path.exists():continue
 packed=asset_path.read_bytes();geometries=json.loads(zlib.decompress(packed));before=json.dumps(geometries,separators=(',',':'))
 for geometry in geometries.values():
  geometry['geometry']['coordinates']=bound_display_coordinates(geometry['geometry']['coordinates'],descriptor['bounds'])
  for lod,coordinates in geometry['lod_geometry'].items():
   if coordinates != '@geometry.coordinates':geometry['lod_geometry'][lod]=bound_display_coordinates(coordinates,descriptor['bounds'])
 raw=json.dumps(geometries,ensure_ascii=False,separators=(',',':')).encode();new=zlib.compress(raw,9)
 if before==json.dumps(geometries,separators=(',',':')):continue
 asset_path.write_bytes(new)
 for fact in document['evidence_catalog']['facts']:
  if 'geometry_asset' in fact['value']:
   fact['value']['geometry_asset'].update({'bytes':len(new),'decoded_bytes':len(raw)})
 write(path,document);payload=path.read_bytes();descriptor.update({'bytes':len(payload)})
 changed.append(descriptor['id'])
write(directory/'index.json',index)
print('BOUND_DISPLAY_COORDINATES',len(changed))
