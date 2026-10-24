"""Retain original shared CShapes border lines instead of matching simplified edges."""
from pathlib import Path
import json,sys
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'local-artifacts/historical-islands-admin-r5/python-libs'),str(ROOT/'local-artifacts/local-landscape-r4/python-libs')]
from shapely.geometry import shape,mapping
from shapely.strtree import STRtree
from shapely import line_merge
sys.path.insert(0,str(ROOT/'tools/historical_data'))
from build_cshapes_1900_snapshot import active_on,TARGET_DATE
sys.path.insert(0,str(ROOT/'tools/map'))
from build_global_strategic import simple

def build_partition_borders():
 """Display edges of the actual R27 ink, not a second historical outline."""
 import zlib,datetime as dt
 from shapely.geometry import Polygon
 from shapely import unary_union
 index=json.loads((ROOT/'data/strategic/index.json').read_text(encoding='utf8'))
 fragments={}
 for descriptor in index['coast_regions']:
  asset=descriptor.get('ink_asset')
  if not asset: raise ValueError('Missing physical ink: '+descriptor['id'])
  ink=json.loads(zlib.decompress((ROOT/asset['path'].removeprefix('res://')).read_bytes()))
  if ink['physical_shard_id']!=descriptor['id'] or ink['lod']!='coarse': raise ValueError('Wrong ink shard')
  for polygon,ref_index in zip(ink['triangles'],ink['indices'],strict=True):
   ref=ink['references'][ref_index]
   if not ref: continue # Unknown land does not manufacture a national frontier.
   fragments.setdefault(ref,[]).append(Polygon(polygon[0],polygon[1:]))
 owners=sorted(fragments)
 regions=[unary_union(fragments[ref]) for ref in owners]
 if any(not g.is_valid for g in regions): raise ValueError('Invalid admitted ink union; source was not repaired')
 result=[]
 def parts(g):
  if g.geom_type=='LineString': return [g]
  if hasattr(g,'geoms'): return [line for child in g.geoms for line in parts(child)]
  return []
 # The independently simplified country polygons can have unknown slivers
 # between them. An exact intersection alone would silently omit a known
 # provider frontier. Use the existing provider's adjacency as the relation,
 # and select ACTUAL ink edges within the documented simplification envelope.
 # The envelope classifies edges offline; it is never a rendered mask.
 snapshot=json.loads((ROOT/'data/world_map/historical/cshapes_1900_snapshot.json').read_text(encoding='utf8'))
 priority={f['id']:i for i,f in enumerate(snapshot['features'])}
 tolerance=float(snapshot['source']['simplify_tolerance_degrees'])+2**0.5*0.00005
 by_owner=dict(zip(owners,regions,strict=True))
 provider=json.loads((ROOT/'data/presentation/political_border_display_r3.json').read_text(encoding='utf8'))
 relations={}
 for row in provider['boundaries']:
  pair=tuple(sorted(row['source_features']))
  if row.get('detail_path'):
   row=json.loads((ROOT/row['detail_path'].removeprefix('res://')).read_text(encoding='utf8'))
  from shapely.geometry import LineString
  relations.setdefault(pair,[]).append(LineString(row['points']))
 for pair,guides in sorted(relations.items()):
  if any(ref not in by_owner for ref in pair): continue
  guide=unary_union(guides)
  envelope=guide.buffer(tolerance,cap_style=2)
  for ref in sorted(pair,key=lambda r:priority.get(r,-1),reverse=True):
   candidate=by_owner[ref].boundary.intersection(envelope)
   if not candidate.is_empty: break
  if candidate.is_empty: continue # No physical land, no invented line.
  if candidate.geom_type!='LineString': candidate=line_merge(candidate)
  for line in parts(candidate):
   line=line.simplify(0,preserve_topology=True)
   if line.length>1e-9:
    result.append({'source_features':list(pair),'edge_reference':ref,'points':[list(p) for p in line.coords]})
 raw_source=json.loads((ROOT/'local-artifacts/map-correctness-r3/CShapes-2.0.geojson').read_text(encoding='utf8'))
 jan=[i for i,f in enumerate(raw_source['features']) if active_on(f['properties'],dt.date(1900,1,1))]
 mar=[i for i,f in enumerate(raw_source['features']) if active_on(f['properties'],TARGET_DATE)]
 dates={'world_initial_date':'1900-01-01','cshapes_snapshot_date':str(TARGET_DATE),'same_provider_records':jan==mar,
        'only_january_records':[raw_source['features'][i]['properties']['gwcode'] for i in jan if i not in mar],
        'only_snapshot_records':[raw_source['features'][i]['properties']['gwcode'] for i in mar if i not in jan]}
 validity={}
 for i in mar:
  p=raw_source['features'][i]['properties']
  start=dt.date(int(p['gwsyear']),int(p['gwsmonth']),int(p['gwsday']))
  end=dt.date(int(p['gweyear']),int(p['gwemonth']),int(p['gweday']))
  validity['gw_'+str(int(p['gwcode']))]={'valid_from':max(start,dt.date(1900,1,1)).isoformat(),
    'valid_to':(end+dt.timedelta(days=1)).isoformat(),
    'provider_valid_from':start.isoformat(),'provider_valid_to_inclusive':end.isoformat()}
 for row in result:
  periods=[validity[x] for x in row['source_features'] if x in validity]
  row['valid_from']=max(['1900-01-01']+[x['valid_from'] for x in periods])
  row['valid_to']=min(['1901-01-01']+[x['valid_to'] for x in periods])
 document={'schema_id':'political_border_display_r39','valid_from':'1900-01-01','valid_to':'1901-01-01',
  'source_locator':'https://icr.ethz.ch/data/cshapes/','source_version':'2.0','license':'CC BY-NC-SA 4.0; Natural Earth public domain',
  'geometry_role':'DISPLAY_PARTITION_SHARED_EDGES_ONLY_NOT_SOVEREIGNTY','snapshot_date':str(TARGET_DATE),
  'date_selection':dates,'feature_validity':validity,'physical_reference':'Natural Earth 5.1.2 modern generalized land; not 1900 shoreline',
  'source_assets':[x['ink_asset']['path'] for x in index['coast_regions']],
  'matching_envelope_degrees':tolerance,'source_relation':'Existing shared CShapes provider edges; 80m detail where supplied. Country edge chosen in the same descending source order used by R27 ink.',
  'methodology':'Union existing coarse ink per reference; use provider adjacency to select actual ink boundary segments within the declared 0.08-degree source simplification plus four-decimal rounding envelope; remove collinear vertices only. Unknown ink slivers remain unknown. Envelope is offline correspondence, not a visual mask. No GIS vertex shifts, nearest-owner assignment, land or sovereign changes.',
  'generator':'tools/map/build_political_border_display.py --from-ink','boundaries':result}
 path=ROOT/'data/presentation/political_border_display_r39.json'
 path.write_text(json.dumps(document,ensure_ascii=False,separators=(',',':')),encoding='utf8')
 print(json.dumps({'file':str(path),'bytes':path.stat().st_size,'lines':len(result),'points':sum(len(x['points']) for x in result),'date_selection':dates},ensure_ascii=False))

if '--from-ink' in sys.argv:
 build_partition_borders()
 raise SystemExit(0)

raw=(ROOT/'local-artifacts/map-correctness-r3/CShapes-2.0.geojson').read_bytes()
rows=[f for f in json.loads(raw)['features'] if active_on(f['properties'],TARGET_DATE)]
geometries=[shape(f['geometry']) for f in rows];tree=STRtree(geometries);borders=[]
def lines(geometry):
 if geometry.geom_type=='LineString':return [geometry]
 if hasattr(geometry,'geoms'):return [line for child in geometry.geoms for line in lines(child)]
 return []
for index,geometry in enumerate(geometries):
 if not geometry.is_valid:continue
 for neighbor in tree.query(geometry):
  neighbor=int(neighbor)
  if neighbor<=index or not geometries[neighbor].is_valid:continue
  shared=line_merge(geometry.boundary.intersection(geometries[neighbor].boundary))
  for line in lines(shared):
   if line.length<=1e-6:continue
   coordinates=simple([list(point) for point in line.coords],1500.0)
   if len(coordinates)>=2:
    features=[f"gw_{int(rows[index]['properties']['gwcode'])}",f"gw_{int(rows[neighbor]['properties']['gwcode'])}"]
    row={'source_features':features,'points':coordinates}
    # Detail is the same dated provider's shared line, never an administrative outline.
    import datetime as dt
    if all(active_on(rows[i]['properties'],dt.date(1900,1,1)) for i in [index,neighbor]):
     detail=simple([list(point) for point in line.coords],80.0)
     path=ROOT/'data/presentation/political_border_detail'/('border_%03d.json'%len(borders))
     path.parent.mkdir(parents=True,exist_ok=True)
     path.write_text(json.dumps({'schema_id':'historical_political_display_line_v1','source_features':features,'source_locator':'https://icr.ethz.ch/data/cshapes/','license':'CC BY-NC-SA 4.0','reference_date':'1900-01-01','points':detail},separators=(',',':')),encoding='utf8')
     row['detail_path']='res://'+path.relative_to(ROOT).as_posix()
    borders.append(row)
document={'schema_id':'political_border_display_r3','source_locator':'https://icr.ethz.ch/data/cshapes/','source_version':'2.0','license':'CC BY-NC-SA 4.0','snapshot_date':str(TARGET_DATE),'geometry_role':'PRESENTATION_SHARED_SOURCE_EDGES_ONLY','methodology':'Exact shared provider boundaries: 1500m WORLD reduction, bounded 80m REGION detail for source records valid on 1900-01-01. No invented joins, no canonical ownership or polygon changes. Existing Arabia display frontiers retained.','boundaries':borders}
(ROOT/'data/presentation/political_border_display_r3.json').write_text(json.dumps(document,ensure_ascii=False,separators=(',',':')),encoding='utf8')
print(len(borders),sum(len(line['points']) for line in borders))
