"""Pinned offline physical display derivatives; no territorial identities.

Run with the development-only Shapely environment. Raw GIS and libraries do not ship.
--output defaults to a review candidate; --apply publishes only after native review.
"""
from pathlib import Path
import argparse, json, math, sys, zlib
from shapely.geometry import shape, box, mapping, Polygon, LineString
from shapely.ops import unary_union, transform
from shapely import constrained_delaunay_triangles, set_precision
from shapely.strtree import STRtree
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/map'))
from build_global_strategic import RIVERS, simple, fact
WORK=ROOT/'local-artifacts/geographic-foundation-r1'
TAG='f1890d9f152c896d250a77557a5751a93d494776'
TOLERANCES={'coarse':1500.0,'medium':300.0}
DISPLAY_SKIN_MAX_M: float = 9000.0
COAST_MASK_HALO_M: float = 6371008.8*(1.0-math.cos(math.radians(2.0)*0.5))*1.1
STYLE_GEOMETRIES=[]
STYLE_IDS=[]

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
def pack_physical(out,id,bounds,lod,land,old,coast,coast_source,difference_source):
 if isinstance(old,dict): old=old[lod].intersection(box(bounds[0],bounds[2],bounds[1],bounds[3]))
 west,east,south,north=bounds;tol=TOLERANCES[lod]
 features=[];lines=[]
 for line in parts(coast,'LineString'):
  raw=list(map(list,line.coords))
  if len(raw)<2:continue
  # This boundary already belongs to the globally simplified land surface.
  # A second independent simplification opens coastline/fill gaps at tile edges.
  reduced=raw
  if len(reduced)>=2 and any(p!=reduced[0] for p in reduced[1:]):lines.append(reduced)
 if lines:
  f={'id':'coast:'+id,'kind':'coast','display_name':'Physical coastline reference','geometry':{'type':'MultiLineString','coordinates':lines},'lod_geometry':{lod:lines},'presentation_lods':[lod],'source_type':'PHYSICAL_REFERENCE','source_geometry_file':'ne_10m_land_v512.geojson','lod_tolerance_m':{lod:tol},'uncertainty':coast_source['access_metadata']['historical_applicability']}
  features.append(fact(f,id,coast_source,'Boundary of the same globally simplified Natural Earth land surface used for fill correction. Conservative degree-space DP'+str(tol)+'m maximum; no subsequent per-shard simplification. Clip edges are not drawn.','APPROXIMATE'))
 face_count=0
 sx=111195*max(.2,math.cos(math.radians((south+north)*.5)));sy=111195
 # The canonical surface is drawn with spherical chords up to two degrees.
 # Its projected edge is not the planar ring used by the boolean operation.
 # Cover that finite chord sagitta only in physical water, then clip to shard.
 old_mask=transform(lambda a,b:(a/sx,b/sy),transform(lambda a,b:(a*sx,b*sy),old).buffer(COAST_MASK_HALO_M,quad_segs=1,join_style='mitre',mitre_limit=2.0)).intersection(box(west,south,east,north))
 for kind,g in [('land_reference',land.difference(old)),('ocean_reference',old_mask.difference(land))]:
  if g.is_empty:continue
  sx=111195*max(.2,math.cos(math.radians((south+north)*.5)));sy=111195
  metric=set_precision(transform(lambda a,b:(a*sx,b*sy),g),0.001)
  # Simplify physical land before the boolean operation. Simplifying its thin
  # difference afterwards moves both shared edges and creates cross-water tips.
  reduced=set_precision(transform(lambda a,b:(a/sx,b/sy),metric),1e-9)
  assert reduced.is_valid
  polygons=[bound_display_coordinates(mapping(p)['coordinates'],bounds) for p in parts(reduced,'Polygon') if p.area>1e-12]
  if not polygons:continue
  triangles=[]
  for polygon in parts(reduced,'Polygon'):
   if polygon.area<=1e-12: continue
   try:
    triangulated=constrained_delaunay_triangles(polygon)
   except Exception as error:
    raise RuntimeError(f'{id}/{kind}: area={polygon.area}, valid={polygon.is_valid}, clearance={polygon.minimum_clearance}, bounds={polygon.bounds}') from error
   triangles.extend([bound_display_coordinates([[list(c) for c in t.exterior.coords]],bounds) for t in parts(triangulated,'Polygon') if t.area>1e-12])
  face_count+=len(triangles)
  f={'id':kind+':'+id,'kind':kind,'display_name':'Physical display correction','geometry':{'type':'MultiPolygon','coordinates':polygons},'lod_geometry':{lod:triangles},'lod_geometry_role':'PRECOMPUTED_DISPLAY_TRIANGLES','presentation_lods':[lod],'lod_tolerance_m':{lod:tol},'display_precision_grid_m':0.001,'display_precision_grid_degrees':1e-9,'source_type':'REFERENCE_ONLY','geometry_role':'PRESENTATION_DIFFERENCE_ONLY','uncertainty':'Physical-minus-existing-display only. Explicit submillimetre display precision grids remove affine floating-point topology noise; canonical source polygons and territorial identities unchanged. Simplified display polygons are not territorial units, political ownership or1900 shoreline facts.'}
  if kind=='ocean_reference':f['display_chord_mask_halo_m']=COAST_MASK_HALO_M
  if kind=='land_reference':
   candidates=[(id,transform(lambda x,y:(x*sx,y*sy),geometry)) for id,geometry in zip(STYLE_IDS,STYLE_GEOMETRIES) if geometry.distance(reduced)<DISPLAY_SKIN_MAX_M/min(sx,sy)]
   coverage=[geometry.buffer(DISPLAY_SKIN_MAX_M) for _,geometry in candidates]
   references=[''];indices=[]
   tree=STRtree([geometry for _,geometry in candidates]) if candidates else None
   for triangle in triangles:
    point=transform(lambda x,y:(x*sx,y*sy),Polygon(triangle[0]).representative_point())
    reference=''
    if tree is not None:
     nearest=int(tree.nearest(point));distance=candidates[nearest][1].distance(point)
     matches=tree.query(point.buffer(DISPLAY_SKIN_MAX_M))
     competing=[int(i) for i in matches if int(i)!=nearest and candidates[int(i)][1].distance(point)<=distance+150.0]
     if distance<=DISPLAY_SKIN_MAX_M and not competing and coverage[nearest].covers(transform(lambda x,y:(x*sx,y*sy),Polygon(triangle[0]))):reference=candidates[nearest][0]
    if reference not in references:references.append(reference)
    indices.append(references.index(reference))
   f.update({'visual_reference_features':references,'lod_visual_reference_indices':{lod:indices},'visual_reference_role':'BOUNDED_TEXTURE_CONTINUATION_ONLY','visual_reference_max_distance_m':DISPLAY_SKIN_MAX_M,'visual_reference_distance_metric':'SHARD_LOCAL_EQUIRECTANGULAR','visual_reference_ambiguity_margin_m':150.0,'visual_reference_authority':False})
  features.append(fact(f,id,difference_source,'Globally simplified physical land minus exact canonical political footprint, or inverse; no post-boolean simplification. Constrained triangulation preserves shared edges and holes. Canonical political geometry and picking unchanged.','APPROXIMATE'))
 if not features:return None,None
 doc={'metadata':{'schema_id':'global_strategic_content_r1','shard_id':id,'valid_from':'1900-01-01','valid_to':'1901-01-01','content_level':'strategic','local_support':False,'presentation_lods':[lod],'packing_only':True},'source_registry':{'schema_id':'historical_source_registry_v2','sources':[coast_source,difference_source]},'evidence_catalog':{'schema_id':'historical_fact_evidence_catalog_v2','facts':features}}
 p=out/(id+'.json');write(p,doc)
 d=descriptor(p,id,bounds,[(west+east)*.5,(south+north)*.5]);d['lod']=lod
 return d,{'id':id,'lod':lod,'bytes':p.stat().st_size,'segments':sum(len(line)-1 for line in lines),'faces':face_count}
def main():
 global STYLE_IDS,STYLE_GEOMETRIES
 parser=argparse.ArgumentParser();parser.add_argument('--apply',action='store_true');parser.add_argument('--output',type=Path);parser.add_argument('--display-footprint',type=Path);args=parser.parse_args()
 if args.apply and args.output:parser.error('--apply and --output are mutually exclusive')
 out=args.output or (ROOT/'data/strategic' if args.apply else WORK/'candidate');out.mkdir(parents=True,exist_ok=True)
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
 # Political geometry remains untouched. Only thin display differences are
 # overlaid, with the inherited NC-SA restriction explicitly recorded.
 physical_file=ROOT/'local-artifacts/paris-land-pilot-r1/research/ne_10m_land_v512.geojson'
 physical=unary_union([shape(f['geometry']) for f in read(physical_file)['features']])
 # Natural Earth's land layer includes inland-water interiors. Syvash is
 # independently present in its natural-water source; treating it as land
 # filled the historical polygon's water hole with conspicuous triangles.
 syvash=[shape(f['geometry']) for f in lake_records if f['properties'].get('name')=='Syvash']
 assert len(syvash)==1 and syvash[0].is_valid
 physical=physical.difference(syvash[0])
 assert physical.is_valid
 physical_lods={lod:set_precision(physical.simplify(tolerance/111195.0,preserve_topology=True),1e-9) for lod,tolerance in TOLERANCES.items()}
 assert all(land.is_valid for land in physical_lods.values())
 political_files=[ROOT/'data/world_map/historical'/n for n in ['cshapes_1900_snapshot.json','arabia_gulf_geography_1900.json']]
 original=[shape(f['geometry']) for p in political_files for f in read(p)['features']]
 scoped=set(read(ROOT/'data/presentation/arabia_political_map_regions_1900.json')['scope_feature_ids'])
 style_features=[f for f in read(political_files[0])['features'] if f['id'] not in scoped]
 STYLE_IDS=[f['id'] for f in style_features];STYLE_GEOMETRIES=[shape(f['geometry']) for f in style_features]
 # Texture continuation may inspect the original dated provider footprint;
 # the coarsened canonical ring must not turn a real bay's land into arbitrary
 # triangle-colour patches. This is an offline visual association only.
 sys.path.insert(0,str(ROOT/'tools/historical_data'))
 from build_cshapes_1900_snapshot import active_on,TARGET_DATE
 raw_style_file=ROOT/'local-artifacts/map-correctness-r3/CShapes-2.0.geojson'
 original_style={f"gw_{int(f['properties']['gwcode'])}":shape(f['geometry']) for f in read(raw_style_file)['features'] if active_on(f['properties'],TARGET_DATE)}
 invalid_style=[]
 for i,feature_id in enumerate(STYLE_IDS):
  geometry=original_style.get(feature_id)
  if geometry is not None and geometry.is_valid:STYLE_GEOMETRIES[i]=geometry
  else:invalid_style.append(feature_id)
 # Reject invalid sources rather than quietly inventing a repaired boundary.
 assert all(g.is_valid for g in original)
 political=unary_union(original)
 coast=unary_union([shape(f['geometry']) for f in read(WORK/'source/ne_10m_coastline.geojson')['features']])
 coast_source=source('natural_earth_coast_10m_5_1_2','Natural Earth physical coastline5.0.0-pre9 / land5.1.1, pinned v5.1.2',assets+[{'file':physical_file.name,'bytes':physical_file.stat().st_size}])
 coast_source['access_metadata']['source_assets'].append({'file':lake_file.name,'bytes':lake_file.stat().st_size})
 difference_source=source('physical_display_difference_r1','Presentation difference: Natural Earth physical land versus existing admitted political display footprint',coast_source['access_metadata']['source_assets']+[{'file':p.name,'bytes':p.stat().st_size} for p in political_files],'CC BY-NC-SA 4.0')
 difference_source['publisher']='Natural Earth / NACIS; CShapes2.0 ETH Zurich; existing WWO bounded1900 Arabia tracing'
 difference_source['access_metadata']['source_assets'].append({'file':lake_file.name,'bytes':lake_file.stat().st_size})
 difference_source['access_metadata']['syvash_water_reference']='Existing pinned Natural Earth natural-water polygon removes inland water from the land-only dataset; display correction only, no new lake identity or historical water-level claim'
 difference_source['access_metadata']['source_assets'].append({'file':raw_style_file.name,'bytes':raw_style_file.stat().st_size})
 difference_source['access_metadata']['texture_reference_geometry']='Original same-date CShapes provider footprint, only for bounded texture continuity; no authority or picking changes'
 difference_source['access_metadata']['invalid_texture_reference_fallback_ids']=invalid_style
 difference_source['access_metadata'].update({'source_type':'REFERENCE_ONLY','usage_status':'Derivative of existing CC BY-NC-SA4.0 political footprint, noncommercial share-alike; Natural Earth contribution public domain','political_source':'https://icr.ethz.ch/data/cshapes/','scope':'Display subtraction/addition only. Never territorial classification or picking geometry.'})
 if args.display_footprint:
  display=read(args.display_footprint)['evidence_catalog']['facts'][0]['value']
  scopes=set(read(ROOT/'data/presentation/arabia_political_map_regions_1900.json')['scope_feature_ids'])
  fallback=[shape(f['geometry']) for p in political_files for f in read(p)['features'] if f['id'] in scopes]
  lod_unions={}
  for asset in display['assets']:
   path=ROOT/asset['path'].removeprefix('res://');payload=path.read_bytes()
   rows=json.loads(zlib.decompress(payload))['features']
   lod_unions[asset['id']]=unary_union([shape(f['geometry']) for f in rows if f['id'] not in scopes]+fallback)
   difference_source['access_metadata']['source_assets'].append({'file':path.name,'bytes':path.stat().st_size})
  difference_source['access_metadata']['scope']='Physical minus independently admitted higher-resolution regional display footprint, or inverse. Canonical territorial geometry and ownership remain unchanged.'
  political=lod_unions
 descriptors=[];summary=[]
 for y in range(6):
  for x in range(4):
   west=-180+x*90;south=-90+y*30;bounds=[west,west+90,south,south+30]
   window=box(west,south,west+90,south+30)
   land=physical_lods['coarse'].intersection(window);old=political if isinstance(political,dict) else political.intersection(window);shore=physical_lods['coarse'].boundary.intersection(window)
   id=f'physical_{x}_{y}'
   parent,row=pack_physical(out,id,bounds,'coarse',land,old,shore,coast_source,difference_source)
   assert parent is not None
   summary.append(row);children=[]
   # Existing Content shards at two finite LODs, not a general tile manager.
   # Fine files are small enough that source admission and GPU residency
   # correspond to the actual regional viewport rather than a quadrant.
   for b in range(3):
    for a in range(6):
     child_bounds=[west+a*15,west+(a+1)*15,south+b*10,south+(b+1)*10]
     cell=box(child_bounds[0],child_bounds[2],child_bounds[1],child_bounds[3])
     fine_land=physical_lods['medium']
     child,child_row=pack_physical(out,id+f'_mid_{a}_{b}',child_bounds,'medium',fine_land.intersection(cell),political if isinstance(political,dict) else political.intersection(cell),fine_land.boundary.intersection(cell),coast_source,difference_source)
     if child is not None:children.append(child);summary.append(child_row)
   parent['medium_regions']=children;descriptors.append(parent)
 index['coast_regions']=descriptors;index['coastline_status']='PHYSICAL_REFERENCE_SEPARATE_FROM_POLITICS'
 index['counts']['settlement']+=3
 index['data_gaps']=[g for g in index['data_gaps'] if not g.startswith('Global medium physical coastline')]
 write(out/'index.json',index)
 print(json.dumps({'shards':len(summary),'coarse':len(descriptors),'medium':sum(len(p['medium_regions']) for p in descriptors),'runtime_bytes':sum(p.stat().st_size for p in out.glob('*.json'))}))
if __name__=='__main__':main()
