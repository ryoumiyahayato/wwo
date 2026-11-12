"""Retain original shared CShapes border lines instead of matching simplified edges."""
from pathlib import Path
import json,sys
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT.parent/'offline-map-sources/python-libs'),str(ROOT/'local-artifacts/historical-islands-admin-r5/python-libs'),str(ROOT/'local-artifacts/local-landscape-r4/python-libs')]
from shapely.geometry import shape,mapping
from shapely.strtree import STRtree
from shapely import line_merge
sys.path.insert(0,str(ROOT/'tools/historical_data'))
from build_cshapes_1900_snapshot import active_on,TARGET_DATE
sys.path.insert(0,str(ROOT/'tools/map'))
from build_global_strategic import simple

def build_luxembourg_frontier(path):
 """Use surveyed limits for the display of the 1816 joint river territory."""
 from sqlite3 import connect
 from pyproj import Transformer
 from shapely import LineString, Point, from_wkb, get_parts, union_all
 from shapely.ops import nearest_points, substring

 def polygons(db, table):
  for blob, in db.execute(f'SELECT geom FROM AdministrativeUnits_AU_{table}'):
   envelope_bytes=(0,32,48,48,64)[(blob[3]>>1)&7]
   yield from_wkb(blob[8+envelope_bytes:])

 def arc(ring, start, end):
  a,b=sorted([ring.project(start),ring.project(end)])
  if b-a<=ring.length/2:return substring(ring,a,b)
  return LineString(list(substring(ring,b,ring.length).coords)+list(substring(ring,0,a).coords)[1:])

 with connect(path.resolve().as_uri()+'?mode=ro',uri=True) as db:
  country=union_all(list(polygons(db,'Country')))
  rivers=sorted(polygons(db,'Condominium'),key=lambda area:area.bounds[1])
 south,north=rivers
 output=ROOT/'data/presentation/political_border_detail'
 guide=json.loads((output/'border_050.json').read_text(encoding='utf8'))
 project=Transformer.from_crs(4326,2169,always_xy=True).transform
 unproject=Transformer.from_crs(2169,4326,always_xy=True).transform
 old_land_endpoint=Point(project(*guide['points'][0]))
 schengen=Point(min((xy for polygon in south.geoms for xy in polygon.exterior.coords),key=lambda point:point[1]))
 vianden_south,vianden_north=nearest_points(south,north)
 ring=LineString(country.exterior.coords)
 lines=[arc(ring,old_land_endpoint,schengen).simplify(20),
        arc(ring,vianden_south,vianden_north).simplify(20)]
 for river in rivers:
  lines.extend(p.exterior for p in get_parts(river.simplify(20,preserve_topology=True)))
 guide.pop('points')
 guide.update(
  source_locator='https://data.public.lu/en/datasets/r/5203367e-eb3b-4dfd-9987-e582c7dbae53',
  historical_basis='https://act.public.lu/fr/parcelles-residences/mensuration-officielle/limites-etat.html',
  license='CC0-1.0; CShapes CC BY-NC-SA 4.0 for the southern reach selection',
  source_date='2026-10-01',
  geometry_role='SURVEYED_MODERN_REFERENCE_FOR_1816_JOINT_TERRITORY_DISPLAY_ONLY',
  lines=[[[round(v,6) for v in unproject(x,y)] for x,y in line.coords] for line in lines])
 (output/'frontier_act_050.json').write_text(json.dumps(guide,separators=(',',':')),encoding='utf8')

def build_french_frontiers(requested=()):
 """Keep dated TRF-GIS edges where they meet the existing shared reference."""
 from pyproj import Transformer
 from shapely import LineString, Point, Polygon, get_parts, make_valid, union_all
 from shapely.ops import substring

 def read(path):
  return json.loads(path.read_text(encoding='utf8'))

 def projected_ring(ring):
  return [(x+648000,y+6862000) for x,y in ring]

 forward=Transformer.from_crs(4326,2154,always_xy=True).transform
 inverse=Transformer.from_crs(2154,4326,always_xy=True).transform
 admin=read(ROOT/'data/world_map/historical/france_lower_1900_index.json')
 output=ROOT/'data/presentation/political_border_detail'

 def exterior(bounds):
  west,south,east,north=bounds
  pieces=[]
  for unit in admin['features']:
   w,e,s,n=unit['bounds']
   if unit['level']!=2 or not (w<east and e>west and s<north and n>south):continue
   data=read(ROOT/unit['detail_path'].removeprefix('res://'))
   for shell,*holes in data['local_polygons']:
    pieces.append(make_valid(Polygon(projected_ring(shell),[projected_ring(hole) for hole in holes])))
  country=max((p for p in get_parts(union_all(pieces,grid_size=1)) if p.geom_type=='Polygon'),key=lambda p:p.area)
  return LineString(country.exterior.coords)

 def line(points):
  return LineString([forward(*point) for point in points])

 def to_coords(geometry):
  return [[round(v,6) for v in inverse(*point)] for point in geometry.coords]

 provider=read(output.parent/'political_border_display_r3.json')
 french_paths=[Path(row['detail_path']).stem for row in provider['boundaries']
               if 'gw_220' in row['source_features'] and row.get('detail_path')]
 for name in french_paths:
  suffix=name.removeprefix('border_')
  if requested and suffix not in requested:continue
  guide=read(output/f'border_{suffix}.json')
  xs,ys=zip(*guide['points'])
  west,east,south,north=min(xs)-.4,max(xs)+.4,min(ys)-.4,max(ys)+.4
  reference=line(guide['points'])
  ring=exterior((west,south,east,north))
  start,end=sorted(ring.project(Point(reference.coords[i])) for i in (0,-1))
  direct=substring(ring,start,end)
  around=LineString(list(substring(ring,end,ring.length).coords)+list(substring(ring,0,start).coords)[1:])
  arc=min((direct,around),key=lambda line:line.hausdorff_distance(reference))
  origin=Point(reference.coords[0])
  if origin.distance(Point(arc.coords[0]))>origin.distance(Point(arc.coords[-1])):arc=arc.reverse()
  joins=sorted((reference.project(p),arc.project(p)) for p in get_parts(reference.intersection(arc)) if p.geom_type=='Point')
  if len(joins)<2 or joins[0][1]>=joins[-1][1]:
   raise ValueError(f'No ordered common joins for {suffix}')
  (left_ref,left_arc),(right_ref,right_arc)=joins[0],joins[-1]
  detail=substring(arc,left_arc,right_arc).simplify(80,preserve_topology=True)
  points=list(substring(reference,0,left_ref).coords)[:-1]+list(detail.coords)+list(substring(reference,right_ref,reference.length).coords)[1:]
  method='Dissolved TRF-GIS 1900 arrondissements, 80 m display simplification between intersections with the dated CShapes reference. Outside the joins CShapes is retained.'
  if 'gw_225' in guide['source_features']:
   # TRF-GIS ends at the French shore of Léman. The dated bilateral
   # reference crosses the lake; reconnect it at the common shore approaches.
   stitched=LineString(points)
   east=[];west=[]
   for point in get_parts(stitched.intersection(reference)):
    if point.geom_type!='Point':continue
    x,y=inverse(point.x,point.y)
    if 6.79<x<6.82 and 46.37<y<46.405:east.append(point)
    if 6.23<x<6.26 and 46.295<y<46.32:west.append(point)
   start=max(east,key=reference.project)
   end=min(west,key=reference.project)
   before=substring(stitched,0,stitched.project(start))
   lake=substring(reference,reference.project(start),reference.project(end))
   after=substring(stitched,stitched.project(end),stitched.length)
   points=list(before.coords)[:-1]+list(lake.coords)+list(after.coords)[1:]
   method+=' The shared CShapes reach across Lake Geneva is retained between the two common joins.'
   guide['lake_basis']='https://archivesdiplomatiques.diplomatie.gouv.fr/ark%3A/14366/p41723klhzjg'
  guide.update(source_locator=admin['source']['locator'],license='TRF-GIS CC BY 4.0; CShapes 2.0 CC BY-NC-SA 4.0',
               attribution=admin['source']['attribution'],reference_date='1900-01-01',
               fallback=f'border_{suffix}.json',method=method,
               detail_km=round(detail.length/1000,1),points=to_coords(LineString(points)))
  path=output/f'frontier_trf_{suffix}.json'
  path.write_text(json.dumps(guide,ensure_ascii=False,separators=(',',':')),encoding='utf8')
  print(path.name,len(points),'points;',round(LineString(points).length/1000,1),'km display')

 if requested and 'neighbors' not in requested:return

 def short_arc(ring, start, end):
  a,b=ring.project(start),ring.project(end)
  if abs(a-b)>=ring.length/2:raise ValueError('Frontier arc crosses exterior origin')
  return substring(ring,a,b).simplify(80,preserve_topology=True)

 def join_frontier(old, ring, end, sector):
  west,south,east,north=sector
  joins=[]
  for point in get_parts(old.intersection(ring)):
   if point.geom_type!='Point':continue
   x,y=inverse(point.x,point.y)
   if west<x<east and south<y<north:joins.append(point)
  join=max(joins,key=old.project)
  head=substring(old,0,old.project(join))
  return LineString(list(head.coords)+list(short_arc(ring,join,end).coords)[1:])

 # ACT's historic LF49/FL1 junction is where the 1900 French exterior
 # leaves the surveyed southern Luxembourg edge between Hussigny and Rédange.
 ring=exterior((5.1,48.8,6.7,50.1))
 lux=read(output/'frontier_act_050.json')
 south=line(lux['lines'][0])
 historic_sector=Point(forward(5.8934,49.4969)).buffer(350)
 junction=min((p for p in get_parts(south.intersection(ring)) if p.geom_type=='Point' and historic_sector.covers(p)),key=south.project)
 rodange=ring.interpolate(ring.project(Point(south.coords[-1])))
 belgium=join_frontier(line(read(output/'frontier_trf_047.json')['points']),ring,rodange,(5.60,49.50,5.79,49.62))
 germany=join_frontier(line(read(output/'frontier_trf_055.json')['points']),ring,junction,(5.95,48.90,6.35,49.20))
 belgium_lux=read(output/'border_048.json')['points']
 belgium_lux[0]=to_coords(short_arc(ring,rodange,junction))[0]
 lux_germany=[to_coords(substring(south,0,south.project(junction)))]+lux['lines'][1:]

 # The provider omits two small jurisdictions. Trace only the 1900 French
 # exterior between the admitted sector ends. These strokes have no fill.
 andorra=exterior((0.8,42.0,2.3,43.0))
 spain=[read(output/f'frontier_trf_{suffix}.json')['points'] for suffix in ('051','052')]
 andorra_line=to_coords(short_arc(andorra,Point(forward(*spain[0][-1])),Point(forward(*spain[1][0]))))
 spain[0][-1],spain[1][0]=andorra_line[0],andorra_line[-1]
 monaco=exterior((6.8,43.3,8.0,44.1))
 monaco_line=short_arc(monaco,Point(forward(7.412827,43.731725)),Point(forward(7.439239,43.749028)))
 frontiers=[
  dict(source_features=['gw_211','gw_220'],lines=[to_coords(belgium)]),
  dict(source_features=['gw_220','gw_255'],lines=[to_coords(germany)]),
  dict(source_features=['gw_212','gw_220'],lines=[to_coords(short_arc(ring,rodange,junction))]),
  dict(source_features=['gw_211','gw_212'],lines=[belgium_lux]),
  dict(source_features=['gw_212','gw_255'],lines=lux_germany),
  dict(source_features=['gw_220','gw_230'],lines=spain),
  dict(source_features=['gw_220','gw_225'],lines=[read(output/'frontier_trf_054.json')['points']]),
  dict(source_features=['gw_220','gw_325'],lines=[read(output/'frontier_trf_053.json')['points']]),
  dict(source_features=['gw_220'],reference_neighbor='Andorra',lines=[andorra_line]),
  dict(source_features=['gw_220'],reference_neighbor='Monaco',lines=[to_coords(monaco_line)]),
 ]
 result=dict(schema_id='historical_frontier_overrides_1900',reference_date='1900-01-01',
             source_locator=admin['source']['locator'],attribution=admin['source']['attribution'],
             license='TRF-GIS CC BY 4.0; Luxembourg ACT CC0-1.0; CShapes CC BY-NC-SA 4.0',
             historical_basis=['https://mjp.univ-perp.fr/traites/1871francfort.htm',
              'https://act.public.lu/dam-assets/fr/publications/brochures/brochure-200-joer-kadaster.pdf',
              'https://cnig.gouv.fr/andorre-a25930.html',
              'https://archives-annuaire-officiel.gouv.mc/Plans/Plan-de-la-principaute-de-Monaco-en-1900'],
             method='Dated TRF-GIS outer edges. Surveyed Luxembourg geometry locates the junctions and supplies the joint river territory. Andorra and Monaco use generalized land-side display strokes without political geometry.',
             frontiers=frontiers)
 path=output/'frontier_france_neighbors_1900.json'
 path.write_text(json.dumps(result,ensure_ascii=False,separators=(',',':')),encoding='utf8')
 print(path.name,len(frontiers),'frontiers')

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

if '--luxembourg-frontier' in sys.argv:
 build_luxembourg_frontier(Path(sys.argv[sys.argv.index('--luxembourg-frontier')+1]))
 raise SystemExit(0)

if '--french-frontiers' in sys.argv:
 build_french_frontiers(sys.argv[sys.argv.index('--french-frontiers')+1:])
 raise SystemExit(0)

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
