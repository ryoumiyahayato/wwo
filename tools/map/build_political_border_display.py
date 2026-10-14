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
