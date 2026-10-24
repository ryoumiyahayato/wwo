"""Pinned offline physical display derivatives; no territorial identities.

Run with the development-only Shapely environment. Raw GIS and libraries do not ship.
--output defaults to a candidate; --apply writes the existing formal derivative paths.
Physical-only generation never reads political source files.
"""
from pathlib import Path
import argparse, json, math, sys, zlib, subprocess
# Display compilation reads existing derivatives through the native encoder.
# It neither imports GIS packages nor rebuilds the source land/ink partition.
if '--compile-display' not in sys.argv:
 from shapely.geometry import shape, box, mapping, Polygon, LineString
 from shapely.ops import unary_union, transform
 from shapely import constrained_delaunay_triangles, set_precision
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/map'))
if '--compile-display' not in sys.argv:
 from build_global_strategic import RIVERS, simple, fact
WORK=ROOT/'local-artifacts/geographic-foundation-r1'
TAG='f1890d9f152c896d250a77557a5751a93d494776'
TOLERANCES={'coarse':1500.0,'medium':300.0}

def read(p):return json.loads(p.read_text(encoding='utf8'))
def write(p,d):
 p.parent.mkdir(parents=True,exist_ok=True)
 p.write_text(json.dumps(d,ensure_ascii=False,separators=(',',':')),encoding='utf8')
def parts(g,kind):
 if g.is_empty:return []
 if g.geom_type==kind:return [g]
 if hasattr(g,'geoms'):return [p for child in g.geoms for p in parts(child,kind)]
 return []

def bound_display_coordinates(value,bounds):
 if isinstance(value,(tuple,list)):
  if len(value)==2 and isinstance(value[0],(float,int)):
   west,east,south,north=bounds;x,y=value
   if west-1e-7<=x<west:x=west
   if east<x<=east+1e-7:x=east
   if south-1e-7<=y<south:y=south
   if north<y<=north+1e-7:y=north
   return [x,y]
  return [bound_display_coordinates(child,bounds) for child in value]
 return value
def river_lod(raw,tolerance):
 lines=[]
 for original in raw:
  line=simple(original,tolerance)
  # Quantized display endpoints can coincide for tiny source fragments.
  # Keep canonical raw evidence; a zero-area stroke cannot be a valid LOD.
  if len(line)>=2 and any(p!=line[0] for p in line[1:]):lines.append(line)
 assert lines
 return lines
def source(id,title,assets,license='PUBLIC_DOMAIN'):
 return {'source_id':id,'title':title,'publisher':'Natural Earth / NACIS; Tom Patterson and Nathaniel Vaughn Kelso','version':'v5.1.2@'+TAG,'locator':'https://github.com/nvkelso/natural-earth-vector/tree/'+TAG,'license':license,'access_metadata':{'source_date':'2022-05-13','retrieved_on':'2026-10-09','source_type':'PHYSICAL_REFERENCE','historical_applicability':'Modern generalized physical reference only; not circa1900 shoreline, engineering, water level or political evidence','usage_status':'Public domain Natural Earth; full GIS excluded from release','source_scale':'1:10,000,000 (not 10 metres)','geographic_accuracy':'Not quantified by provider','scope':'Global physical coastline / selected existing major rivers','data_transformation':'Finite offline LOD, exact source clipping and bounded display shards; no inserted river connections','uncertainty':'Modern shoreline alterations, glacial change, reservoirs and channel migration are not reconstructed','source_assets':assets}}
def descriptor(p,id,bounds,anchor):return {'id':id,'bounds':bounds,'anchor':anchor,'path':'res://data/strategic/'+p.name,'bytes':p.stat().st_size}

def independent_foundation(out, with_ink=False):
 """R27: physical geometry needs only pinned NE. Political ink is optional."""
 physical_file=ROOT/'local-artifacts/paris-land-pilot-r1/research/ne_10m_land_v512.geojson'
 lake_file=ROOT/'local-artifacts/global-strategic-r1/source/ne_10m_lakes.geojson'
 physical=unary_union([shape(f['geometry']) for f in read(physical_file)['features']])
 # Preserve the already admitted natural-water correction, not a political mask.
 syvash=next(shape(f['geometry']) for f in read(lake_file)['features'] if f['properties'].get('name')=='Syvash')
 physical=physical.difference(syvash)
 lods={lod:set_precision(physical.simplify(tol/111195.0,preserve_topology=True),1e-9) for lod,tol in TOLERANCES.items()}
 coasts={lod:land.boundary.difference(box(-180,-90,180,90).boundary) for lod,land in lods.items()}
 src=source('natural_earth_independent_physical_r27','Independent Natural Earth land and water reference',[
  {'file':physical_file.name,'bytes':physical_file.stat().st_size}, {'file':lake_file.name,'bytes':lake_file.stat().st_size}])
 src['access_metadata']['data_transformation']='R27 independent globally simplified land; full tile land and its water complement; constrained triangulation; same source boundary for coast. No political input, difference halo, inferred owner or nearest-country association.'
 src['access_metadata']['scope']='Modern physical reference. Original NE land holes/components and existing Syvash natural-water correction. Inland lake overlays retain their own sources; not a complete global lake survey.'
 ink_geometries=[];ink_sources=[]
 if with_ink:
  # A separate display operation partitions the fixed physical land for a
  # single draw. It cannot change the physical dataset's shape or provenance.
  political_files=[ROOT/'data/world_map/historical'/n for n in ['cshapes_1900_snapshot.json','arabia_gulf_geography_1900.json']]
  display=read(ROOT/'data/presentation/arabia_political_map_regions_1900.json')
  def cells(rows):return unary_union([Polygon(c['outer'],c.get('holes',[])) for c in rows])
  regions=[(r['id'],cells(r['mask_cells'])) for r in display['political_map_regions']]
  partial={key:cells(rows) for key,rows in display.get('partial_scope_masks',{}).items()}
  scoped=[]
  for p in political_files:
   for row in read(p)['features']:
    g=shape(row['geometry']);key=row['id']
    if key in display['scope_feature_ids']:
     inside=g.intersection(partial[key]) if key in partial else g
     scoped.append(inside)
     g=g.difference(partial[key]) if key in partial else Polygon()
    if not g.is_empty:ink_geometries.append((key,g))
  scope=unary_union(scoped)
  ink_geometries.extend((key,scope.intersection(g)) for key,g in regions)
  ink_sources=[{'path':'res://'+p.relative_to(ROOT).as_posix(),'bytes':p.stat().st_size} for p in political_files]
  ink_sources.append({'path':'res://data/presentation/arabia_political_map_regions_1900.json','bytes':(ROOT/'data/presentation/arabia_political_map_regions_1900.json').stat().st_size})
 def triangulate(g):
  return [[[list(c) for c in t.exterior.coords]] for p in parts(set_precision(g,1e-9),'Polygon') for t in parts(constrained_delaunay_triangles(p),'Polygon') if t.area>0]
 def pack(id,bounds,lod):
  west,east,south,north=bounds;cell=box(west,south,east,north)
  land=lods[lod].intersection(cell);water=cell.difference(land)
  # World-frame closures close planar polygons but are not physical coasts.
  shore=coasts[lod].intersection(cell)
  values=[];geometries={}
  for kind,g,role in [('land_reference',land,'INDEPENDENT_PHYSICAL_LAND'),('ocean_reference',water,'INDEPENDENT_PHYSICAL_WATER_MASK')]:
   if g.is_empty or g.area<=0:continue
   key=kind+':'+id
   geometry={'type':'MultiPolygon','coordinates':[mapping(p)['coordinates'] for p in parts(g,'Polygon') if p.area>0]}
   triangles=triangulate(g) if kind=='land_reference' else []
   geometries[key]={'geometry':geometry,'lod_geometry':{lod:triangles}}
   f={'id':key,'kind':kind,'display_name':'Independent physical land' if kind=='land_reference' else 'Physical water reference',
    'presentation_lods':[lod],'geometry_role':role,'lod_geometry_role':'PRECOMPUTED_DISPLAY_TRIANGLES' if kind=='land_reference' else 'REFERENCE_MASK_ONLY',
    'source_type':'PHYSICAL_REFERENCE','bounds_lon_lat':bounds,'lod_tolerance_m':{lod:TOLERANCES[lod]}}
   values.append(fact(f,id,src,src['access_metadata']['data_transformation'],'APPROXIMATE'))
  lines=[list(map(list,line.coords)) for line in parts(shore,'LineString') if len(line.coords)>1]
  if lines:
   key='coast:'+id;geometries[key]={'geometry':{'type':'MultiLineString','coordinates':lines},'lod_geometry':{lod:lines}}
   values.append(fact({'id':key,'kind':'coast','display_name':'Physical coastline','presentation_lods':[lod],'source_type':'PHYSICAL_REFERENCE','source_geometry_file':physical_file.name,'lod_tolerance_m':{lod:TOLERANCES[lod]}},id,src,'Boundary of the same globally simplified independent land; tile cut edges are not coast.','APPROXIMATE'))
  path=out/(id+'.json');side=path.with_suffix('.geom')
  decoded=json.dumps(geometries,ensure_ascii=False,separators=(',',':')).encode();side.write_bytes(zlib.compress(decoded,9))
  asset={'path':'res://data/strategic/'+side.name,'encoding':'ZLIB_JSON_UTF8','bytes':side.stat().st_size,'decoded_bytes':len(decoded)}
  for v in values:v['value']['geometry_asset']=asset
  write(path,{'metadata':{'schema_id':'global_strategic_content_r1','shard_id':id,'valid_from':'1900-01-01','valid_to':'1901-01-01','content_level':'strategic','physical_foundation':True,'presentation_lods':[lod],'geometry_encoding':'ZLIB_JSON_UTF8'},'source_registry':{'schema_id':'historical_source_registry_v2','sources':[src]},'evidence_catalog':{'schema_id':'historical_fact_evidence_catalog_v2','facts':values}})
  row=descriptor(path,id,bounds,[(west+east)*.5,(south+north)*.5]);row['lod']=lod
  if with_ink and not land.is_empty:
   remaining=land;polygons=[];references=[''];indices=[]
   # Exact historical intersections; last displayed historical source wins an
   # overlap. Unknown physical land remains uncoloured, never nearest-owned.
   for key,g in reversed(ink_geometries):
    if not g.intersects(remaining):continue
    overlap=remaining.intersection(g)
    if overlap.is_empty:continue
    triangles=triangulate(overlap)
    if triangles:
     if key not in references:references.append(key)
     polygons.extend(triangles);indices.extend([references.index(key)]*len(triangles))
    remaining=remaining.difference(overlap)
    if remaining.is_empty:break
   triangles=triangulate(remaining);polygons.extend(triangles);indices.extend([0]*len(triangles))
   ink=out/(id+'.ink.geom')
   payload={'schema_id':'physical_political_ink_partition_r27','physical_shard_id':id,'lod':lod,'references':references,'indices':indices,'triangles':polygons,
    'source_assets':ink_sources,'license':'CC BY-NC-SA 4.0; physical contribution public domain','role':'DISPLAY_INTERSECTION_ONLY_NOT_SOVEREIGNTY','method':'Complete partition of independent physical land by existing dated display geometry; no nearest-country assignment; unused when political ink is unavailable.'}
   data=json.dumps(payload,ensure_ascii=False,separators=(',',':')).encode();ink.write_bytes(zlib.compress(data,9))
   row['ink_asset']={'path':'res://data/strategic/'+ink.name,'encoding':'ZLIB_JSON_UTF8','bytes':ink.stat().st_size,'decoded_bytes':len(data)}
  return row
 index=read(out/'index.json') if (out/'index.json').exists() else read(ROOT/'data/strategic/index.json');parents=[]
 for y in range(6):
  for x in range(4):
   west=-180+x*90;south=-90+y*30;id=f'physical_{x}_{y}'
   parent=pack(id,[west,west+90,south,south+30],'coarse')
   parent['medium_regions']=[pack(id+f'_mid_{a}_{b}',[west+a*15,west+(a+1)*15,south+b*10,south+(b+1)*10],'medium') for b in range(3) for a in range(6)]
   parents.append(parent)
   print(id,flush=True)
 index.update(coast_regions=parents,physical_foundation='INDEPENDENT_NATURAL_EARTH_R27',coastline_status='INDEPENDENT_PHYSICAL_LAND_AND_MATCHING_COAST')
 write(out/'index.json',index)
 print(json.dumps({'physical_shards':sum(1+len(p['medium_regions']) for p in parents),'physical_source':src['source_id'],'political_ink_optional':with_ink,'bytes':sum(p.stat().st_size for p in out.glob('physical_*') if p.is_file())}),flush=True)
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--apply',action='store_true');parser.add_argument('--output',type=Path);parser.add_argument('--independent',action='store_true',help='Generate only the independent physical foundation');parser.add_argument('--political-ink',action='store_true');parser.add_argument('--compile-display',action='store_true',help='Compile existing physical/ink derivatives with the native Godot encoder, without rebuilding GIS');parser.add_argument('--godot',type=Path);args=parser.parse_args()
 if args.apply and args.output:parser.error('--apply and --output are mutually exclusive')
 out=args.output or (ROOT/'data/strategic' if args.apply else WORK/'candidate');out.mkdir(parents=True,exist_ok=True)
 if args.compile_display:
  if not args.godot or not args.godot.is_file():parser.error('--compile-display requires --godot pointing to the Godot 4.6.3 console')
  subprocess.run([str(args.godot),'--headless','--path',str(ROOT),'--script','res://tools/map/compile_political_display.gd','--',str(out.resolve())],cwd=ROOT,check=True)
  return
 if args.independent:
  independent_foundation(out,args.political_ink);return
 assets=read(WORK/'source-assets.json')
 rivers=read(WORK/'source/ne_10m_rivers_lake_centerlines.geojson')['features']
 river_source=source('natural_earth_rivers_10m_5_1_2','Natural Earth 1:10M rivers; physical layer version5.0.0, pinned repository v5.1.2',[a for a in assets if 'rivers' in a['file']])
 baseline=WORK/'before-project/data/strategic'
 index=read(baseline/'index.json')
 lake_file=ROOT/'local-artifacts/global-strategic-r1/source/ne_10m_lakes.geojson'
 lake_records=read(lake_file)['features']
 ocean_file=WORK/'source/ne_10m_ocean.geojson'
 oceans=read(ocean_file)['features'][0]['geometry']['coordinates']
 caspian=[(i,p) for i,p in enumerate(oceans) if 40<min(c[0] for c in p[0])<52 and 32<min(c[1] for c in p[0])<48]
 assert len(caspian)==1
 lake_source=source('natural_earth_water_10m_5_1_2','Natural Earth 1:10M natural lakes and closed Caspian ocean component; pinned v5.1.2',[{'file':p.name,'bytes':p.stat().st_size} for p in [lake_file,ocean_file]])
 for desc in index['regions']:
  doc=read(baseline/Path(desc['path']).name)
  doc['source_registry']['sources'].extend([river_source,lake_source])
  for entry in doc['evidence_catalog']['facts']:
   f=entry['value']
   if f['kind']=='lake':
    if f['id']=='lake:caspiansea':
     polygons=[caspian[0][1]];record=0;component=caspian[0][0];filename='ne_10m_ocean.geojson'
    else:
     found=[(i,r) for i,r in enumerate(lake_records) if r['properties'].get('name')==f['display_name'] and r['properties'].get('featurecla') in ['Lake','Alkaline Lake']]
     assert len(found)==1
     record,r=found[0];g=r['geometry'];polygons=g['coordinates'] if g['type']=='MultiPolygon' else [g['coordinates']];component=None;filename='ne_10m_lakes.geojson'
    geo=shape({'type':'MultiPolygon','coordinates':polygons});assert geo.is_valid
    f.update({'geometry':{'type':'MultiPolygon','coordinates':polygons},'lod_geometry':{},'lod_tolerance_m':TOLERANCES,'source_geometry_file':filename,'natural_earth_record':record,'source_geometry_component':component})
    for lod,tol in TOLERANCES.items():
     sx=111195*max(.2,math.cos(math.radians(geo.centroid.y)));sy=111195
     reduced=transform(lambda a,b:(a/sx,b/sy),transform(lambda a,b:(a*sx,b*sy),geo).simplify(tol,preserve_topology=True))
     f['lod_geometry'][lod]=[mapping(p)['coordinates'] for p in parts(reduced,'Polygon')]
    entry.update(fact(f,desc['id'],lake_source,'Same nineteen natural water identities; source Lake/Alkaline Lake polygons, explicit closed Caspian inland component. Topology-preserving offline1500m/300m; modern levels remain reference only.','APPROXIMATE'))
    continue
   if f['kind']!='river':continue
   _,aliases=RIVERS[f['id'].split(':')[1]]
   records=[(j,r) for j,r in enumerate(rivers) if r['properties'].get('name') in aliases and r['properties'].get('featurecla')=='River']
   raw=[line for _,r in records for line in (r['geometry']['coordinates'] if r['geometry']['type']=='MultiLineString' else [r['geometry']['coordinates']])]
   assert raw and all(len(line)>=2 for line in raw)
   f.update({'geometry':{'type':'MultiLineString','coordinates':raw},'lod_geometry':{lod:river_lod(raw,tol) for lod,tol in TOLERANCES.items()},'lod_tolerance_m':TOLERANCES,'source_geometry_file':'ne_10m_rivers_lake_centerlines.geojson','natural_earth_records':[j for j,_ in records]})
   f['uncertainty']='1:10M modern generalized river-axis reference. Only River features admitted; reservoir Lake Centerline and artificial canals excluded. Source discontinuities and suspect Amazon/northeastRussia alignments remain; no 1900 bank, navigability or engineering claim.'
   entry.update(fact(f,desc['id'],river_source,'Same stable natural river ID. Source River segments only; offline DP1500m/300m without interpolation or forced joins.','APPROXIMATE'))
  if desc['id']=='europe':
   atlas=next(s for s in doc['source_registry']['sources'] if s['source_id']=='rand_atlas_1899')
   atlas['access_metadata']['source_assets'].extend([{'file':'atlas-nordic-'+str(page)+'.jpg','bytes':(WORK/'source'/('atlas-nordic-'+str(page)+'.jpg')).stat().st_size} for page in [126,127]])
   locators=read(ROOT/'local-artifacts/global-strategic-r1/source/ne_10m_populated_places_simple.geojson')['features']
   for slug,name,modern,page,leaf,rank in [('stockholm','Stockholm','Stockholm',126,139,0),('oslo','Christiania','Oslo',127,140,0),('bergen','Bergen','Bergen',127,140,1)]:
    found=[r for r in locators if r['properties'].get('name')==modern and 4<r['geometry']['coordinates'][0]<20 and 55<r['geometry']['coordinates'][1]<65]
    assert len(found)==1,(slug,len(found))
    coords=found[0]['geometry']['coordinates']
    f={'id':'place:'+slug,'kind':'settlement','historical_name':name,'display_name':name,'geometry':{'type':'Point','coordinates':coords},'latitude':coords[1],'longitude':coords[0],'rank':rank,'max_mpp':8000 if rank==0 else 6000,'source_type':'HISTORICAL_EVIDENCE','source_reference':'https://archive.org/details/philadelphiapubl00rand/page/n'+str(leaf)+'/mode/1up','source_printed_page':page,'coordinate_source':'Natural Earth modern locator only','coordinate_source_id':'natural_earth_locator_5_1_2','coordinate_evidence_type':'REFERENCE_ONLY','importance_basis':'Visually reviewed1899 chief-city panel; Stockholm/Christiania marked Capital, Bergen named chief city. Modern population and administrative relations unused.','identity_status':'NEW','uncertainty':'Representative modern city locator only, not1900 built-up extent, population or station. Christiania uses stable Oslo locator identity with contemporary display name.'}
    assert not any(e['subject_id']==f['id'] for e in doc['evidence_catalog']['facts'])
    doc['evidence_catalog']['facts'].append(fact(f,desc['id'],atlas,'1899 printed pages126/127 and their CHIEF CITIES lists visually reviewed; bounded strategic rank only. No administrative geometry or simulation entities.'))
  doc['metadata']['coastline_status']='SEPARATE_PHYSICAL_REFERENCE'
  p=out/Path(desc['path']).name;write(p,doc)
  desc.update(descriptor(p,desc['id'],desc['bounds'],desc['anchor']))
  desc['feature_count']=len(doc['evidence_catalog']['facts'])
 # Existing optional river/locator rebuild also ends in the one physical path.
 index['counts']['settlement']+=3
 write(out/'index.json',index)
 independent_foundation(out,args.political_ink)
if __name__=='__main__':main()
