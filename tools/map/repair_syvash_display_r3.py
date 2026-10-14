"""Regenerate only the two physical display shards touched by existing Syvash water."""
from pathlib import Path
import json,zlib,sys
from shapely.geometry import shape,box
from shapely.ops import unary_union
from shapely import set_precision
ROOT=Path(__file__).resolve().parents[2];WORK=ROOT/'local-artifacts/map-correctness-r3'
sys.path.insert(0,str(ROOT/'tools/map'));import build_geographic_foundation as builder
sys.path.insert(0,str(ROOT/'tools/historical_data'));from build_cshapes_1900_snapshot import active_on,TARGET_DATE
def read(path):return json.loads(path.read_text(encoding='utf8'))
def write(path,data):path.write_text(json.dumps(data,ensure_ascii=False,separators=(',',':')),encoding='utf8')
physical_path=ROOT/'local-artifacts/paris-land-pilot-r1/research/ne_10m_land_v512.geojson'
lake_path=ROOT/'local-artifacts/global-strategic-r1/source/ne_10m_lakes.geojson'
water=next(shape(f['geometry']) for f in read(lake_path)['features'] if f['properties'].get('name')=='Syvash')
physical=unary_union([shape(f['geometry']) for f in read(physical_path)['features']]).difference(water)
political=unary_union([shape(f['geometry']) for name in ['cshapes_1900_snapshot.json','arabia_gulf_geography_1900.json'] for f in read(ROOT/'data/world_map/historical'/name)['features']])
canonical=read(ROOT/'data/world_map/historical/cshapes_1900_snapshot.json')['features']
scoped=set(read(ROOT/'data/presentation/arabia_political_map_regions_1900.json')['scope_feature_ids'])
raw=read(WORK/'CShapes-2.0.geojson')['features']
fine={f"gw_{int(f['properties']['gwcode'])}":shape(f['geometry']) for f in raw if active_on(f['properties'],TARGET_DATE)}
style=[f for f in canonical if f['id'] not in scoped];builder.STYLE_IDS=[f['id'] for f in style]
builder.STYLE_GEOMETRIES=[fine[f['id']] if f['id'] in fine and fine[f['id']].is_valid else shape(f['geometry']) for f in style]
directory=ROOT/'data/strategic';index=read(directory/'index.json');descriptors=list(index['coast_regions'])+[c for p in index['coast_regions'] for c in p.get('medium_regions',[])]
repaired=[]
for descriptor in descriptors:
 bounds=descriptor['bounds'];window=box(bounds[0],bounds[2],bounds[1],bounds[3])
 if not window.intersects(water):continue
 path=directory/Path(descriptor['path']).name;previous=read(path)
 sources={s['source_id']:s for s in previous['source_registry']['sources']}
 coast_source=sources['natural_earth_coast_10m_5_1_2'];difference_source=sources['physical_display_difference_r1']
 asset={'file':lake_path.name,'bytes':lake_path.stat().st_size}
 for source in [coast_source,difference_source]:
  if asset not in source['access_metadata']['source_assets']:source['access_metadata']['source_assets'].append(asset)
  source['access_metadata']['syvash_water_reference']='Pinned natural-water polygon removes inland water from land-only geometry; no new water identity or historical claim'
 lod=descriptor['lod'];land=set_precision(physical.simplify(builder.TOLERANCES[lod]/111195,preserve_topology=True),1e-9)
 builder.pack_physical(directory,descriptor['id'],bounds,lod,land.intersection(window),political.intersection(window),land.boundary.intersection(window),coast_source,difference_source)
 document=read(path);geometries={}
 for fact in document['evidence_catalog']['facts']:
  feature=fact['value'];keys=['geometry','lod_geometry']+(['lod_visual_reference_indices'] if 'lod_visual_reference_indices' in feature else [])
  geometries[feature['id']]={key:feature.pop(key) for key in keys}
 decoded=json.dumps(geometries,ensure_ascii=False,separators=(',',':')).encode();packed=zlib.compress(decoded,9);sidecar=path.with_suffix('.geom');sidecar.write_bytes(packed)
 asset={'path':'res://data/strategic/'+sidecar.name,'encoding':'ZLIB_JSON_UTF8','bytes':len(packed),'decoded_bytes':len(decoded)}
 for fact in document['evidence_catalog']['facts']:fact['value']['geometry_asset']=asset
 document['metadata']['geometry_encoding']='ZLIB_JSON_UTF8';write(path,document)
 descriptor.update({'bytes':path.stat().st_size});repaired.append(descriptor['id'])
write(directory/'index.json',index);print(json.dumps(repaired))
