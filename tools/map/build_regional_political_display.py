"""Unchanged dated CShapes identities; finer, separately bound display geometry."""
from pathlib import Path
import sys,json,zlib
from shapely.geometry import shape,mapping
from shapely.ops import transform
import math
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/historical_data'))
from build_cshapes_1900_snapshot import active_on,TARGET_DATE
sys.path.insert(0,str(ROOT/'tools/map'))
from build_global_strategic import fact
WORK=ROOT/'local-artifacts/map-correctness-r3'
raw=(WORK/'CShapes-2.0.geojson').read_bytes()
original=json.loads((ROOT/'data/world_map/historical/cshapes_1900_snapshot.json').read_text(encoding='utf8'))
features=[];fallback=[];by_id={f['id']:f for f in original['features']}
for row in json.loads(raw)['features']:
 if not active_on(row['properties'],TARGET_DATE):continue
 feature_id=f"gw_{int(row['properties']['gwcode'])}"
 geometry=shape(row['geometry'])
 if not geometry.is_valid:
  fallback.append(feature_id)
  geometry=shape(by_id[feature_id]['geometry'])
  assert geometry.is_valid
 # Keep the provider's full resolution. This replaces the old 0.08-degree
 # display simplification, without updating any canonical territorial fact.
 features.append({'id':f"gw_{int(row['properties']['gwcode'])}",'geometry':mapping(geometry)})
features.sort(key=lambda f:int(f['id'][3:]))
directory=ROOT/'data/presentation';assets=[]
for lod,tolerance in [('coarse',1500.0),('medium',300.0)]:
 rows=[]
 for feature in features:
  geometry=shape(feature['geometry'])
  # The same metre tolerances as the admitted physical coast, rather than
  # the old global angular 0.08-degree reduction. Bound polar contraction.
  sx=111195*max(.15,math.cos(math.radians(geometry.centroid.y)))
  reduced=transform(lambda x,y:(x/sx,y/111195),transform(lambda x,y:(x*sx,y*111195),geometry).simplify(tolerance,preserve_topology=True))
  assert reduced.is_valid
  rows.append({'id':feature['id'],'geometry':mapping(reduced)})
 payload=json.dumps({'features':rows},ensure_ascii=False,separators=(',',':')).encode()
 path=directory/f'cshapes_region_display_r3_{lod}.geom'
 packed=zlib.compress(payload,9);path.write_bytes(packed)
 assets.append({'id':lod,'path':'res://data/presentation/'+path.name,'bytes':len(packed),'decoded_bytes':len(payload),'tolerance_m':tolerance})
source={'source_id':'cshapes_region_display_r3','title':'Full-resolution CShapes 2.0 dated regional display derivative','publisher':'ETH Zurich, International Conflict Research','version':'2.0','locator':'https://icr.ethz.ch/data/cshapes/','license':'CC BY-NC-SA 4.0','access_metadata':{'source_type':'HISTORICAL_EVIDENCE','retrieved_on':'2026-10-09','scope':'Presentation only; canonical geometry, ownership, selection and saved facts unchanged','data_transformation':'Same 1900-03-12 records as existing snapshot; provider coordinates retained without 0.08-degree simplification; zlib transport encoding only','uncertainty':'Provider historical boundary accuracy is not quantified; original shoreline is not an exact 1900 coastal survey'}}
source['access_metadata']['data_transformation']='Same dated CShapes records; topology-preserving metric display LODs at 1500m/300m, matching the existing physical coast tolerances. Canonical 0.08-degree historical geometry and WorldState remain unchanged. Invalid provider polygons use the admitted canonical fallback.'
value={'id':'regional_display:cshapes_1900','kind':'regional_display_geometry','assets':assets,'encoding':'ZLIB_JSON_UTF8','feature_ids':[f['id'] for f in features],'invalid_provider_geometry_fallback_ids':fallback,'snapshot_date':original['snapshot_date'],'geometry_role':'PRESENTATION_ONLY','uncertainty':source['access_metadata']['uncertainty']+' Invalid provider geometries retain the already admitted canonical display; no automatic make_valid or boundary invention.'}
source['access_metadata']['source_date']=original['snapshot_date']
record=fact(value,'global',source,source['access_metadata']['data_transformation'],'APPROXIMATE')
record['domain']='spatial_boundary';record['fact_id']='regional_display:cshapes_1900'
document={'schema_id':'regional_political_display_r3','source_registry':{'schema_id':'historical_source_registry_v2','sources':[source]},'evidence_catalog':{'schema_id':'historical_fact_evidence_catalog_v2','facts':[record]}}
(directory/'cshapes_region_display_r3.json').write_text(json.dumps(document,ensure_ascii=False,separators=(',',':')),encoding='utf8')
(WORK/'regional-display-source.json').write_text(json.dumps({'features':features}),encoding='utf8')
print(json.dumps({'assets':assets,'features':len(features),'fallback_ids':fallback}))
