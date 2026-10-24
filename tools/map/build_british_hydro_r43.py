"""Bounded R43 display derivatives; modern hydrography, never 1900 banks.

Uses the existing StrategicSpatialLoader JSON/geom contracts. No routing,
navigation, ownership, economics or inferred DEM drainage is exported.
"""
from pathlib import Path
import json, math, re, zlib, zipfile, collections, concurrent.futures as futures
import requests, shapefile
from shapely import constrained_delaunay_triangles
from pyproj import Transformer
from shapely.geometry import shape, mapping, box, LineString, MultiLineString
from shapely.ops import transform, unary_union, linemerge
from build_british_surface_r43 import islands, ROOT, WORK

HYDRO=WORK/'hydro'
OUT=ROOT/'data/strategic'
SERVICE='https://image.discomap.eea.europa.eu/arcgis/rest/services/EUHydro/EUHydro_RiverNetworkDatabase/MapServer/'
TO_METRES=Transformer.from_crs(4326,3035,always_xy=True).transform
TO_DEGREES=Transformer.from_crs(3035,4326,always_xy=True).transform
OS_TO_METRES=Transformer.from_crs(27700,3035,always_xy=True).transform
MAIN={'River Thames','River Severn','River Trent','River Humber','River Mersey','River Tyne','River Great Ouse','Great Ouse',
      'River Tay','River Clyde','River Forth','River Dee','River Spey','River Tweed','River Wye','River Ouse','River Tees'}
UNCERTAIN_ENGINEERING=re.compile(r'\b(drain|drains|ditch|dyke|canal|cut|relief|dock|reservoir)\b|^Jubilee River$|^New River$',re.I)


def acquire():
    HYDRO.mkdir(parents=True,exist_ok=True)
    if not (HYDRO/'os_open_rivers/data/WatercourseLink.shp').exists():
        archive=HYDRO/'oprvrs_essh_gb.zip'
        if not archive.exists():
            response=requests.get('https://api.os.uk/downloads/v1/products/OpenRivers/downloads?area=GB&format=ESRI%C2%AE+Shapefile&redirect',timeout=180)
            response.raise_for_status(); archive.write_bytes(response.content)
        with zipfile.ZipFile(archive) as source: source.extractall(HYDRO/'os_open_rivers')
    def download(layer,where,filename,bounds):
        path=HYDRO/filename
        if path.exists(): return
        q=dict(f='geojson',where=where,geometry=bounds,geometryType='esriGeometryEnvelope',inSR=4326,outSR=4326,
               spatialRel='esriSpatialRelIntersects',returnGeometry='true',outFields='*',resultRecordCount=1000,orderByFields='OBJECTID')
        features=[]
        for offset in range(0,100000,1000):
            q['resultOffset']=offset
            for attempt in range(3):
                try:
                    response=requests.get(SERVICE+str(layer)+'/query',params=q,timeout=120)
                    response.raise_for_status(); data=response.json()
                    if 'error' in data: raise ValueError(data['error'])
                    break
                except Exception:
                    if attempt==2: raise
            features.extend(data['features'])
            if not data.get('exceededTransferLimit',False): break
        else: raise ValueError('Unexpectedly large bounded water query')
        path.write_text(json.dumps(dict(type='FeatureCollection',features=features)),encoding='utf8')
        print(filename,len(features),flush=True)
    with futures.ThreadPoolExecutor(max_workers=3) as pool:
        jobs=[pool.submit(download,2,"LKE_TYPE = 'N' AND AREA_GEO>=250000",'eu_natural_lakes.geojson','-12,49.7,2,62')]
        jobs += [pool.submit(download,layer,'1=1',f'eu_ireland_rivers_{layer}.geojson','-11,51.3,-5.3,55.6') for layer in range(7,12)]
        for job in jobs: job.result()


def flat_geometry(raw):
    # Service Z is deliberately discarded; no unverified vertical datum enters terrain.
    def xy(*p): return p[:2]
    return transform(xy,shape(raw))


def parts(g,kind):
    if g.is_empty: return []
    if g.geom_type==kind: return [g]
    result=[]
    if hasattr(g,'geoms'):
        for item in g.geoms: result.extend(parts(item,kind))
    return result


def sources():
    return [dict(source_id='os_open_rivers_r43',title='OS Open Rivers, Great Britain natural river axes',publisher='Ordnance Survey',
       version='2026-download',license='OGL-3.0',locator='https://osdatahub.os.uk/downloads/open/OpenRivers',
       access_metadata=dict(source_date='2026-10-18',source_crs='EPSG:27700 OSGB1936 / British National Grid',
       geometry='WatercourseLink inlandRiver/tidalRiver only; canals, lake axes and fictitious links excluded',
       attribution='Contains Ordnance Survey data © Crown copyright and database right 2026',
       licence_url='https://www.ordnancesurvey.co.uk/legal/open-government-licence',historical_applicability='Modern physical reference, not 1900 banks or engineering')),
       dict(source_id='eu_hydro_r43',title='EU-Hydro River Network Database v1',publisher='European Environment Agency / Copernicus Land Monitoring Service',
       version='v1:2006-2012',license='Copernicus-full-open-free-attribution',locator='https://land.copernicus.eu/en/products/eu-hydro/eu-hydro-river-network-database',
       access_metadata=dict(source_date='2006-2012',source_crs='Product ETRS89-LAEA; service EPSG:3857; downloaded EPSG:4326',
       geometry='Photo-interpreted River_Net_l Strahler>=3 for all Ireland; InlandWater LKE_TYPE=N natural lakes >=0.25km². Not DEM drainage model.',
       attribution="Generated using European Union's Copernicus Land Monitoring Service information; https://doi.org/10.2909/393359a7-7ebd-4a52-80ac-1a18d5f3db9c",
       licence_url='https://land.copernicus.eu/en/data-policy',historical_applicability='Modern reference; water levels, regulated natural lakes and banks not reconstructed for 1900'))]


def read_features():
    polygons,domain=islands()
    ireland=max((p for p in polygons if p.contains(shape({'type':'Point','coordinates':[-8,53]}))),key=lambda g:g.area)
    ireland_m=transform(TO_METRES,ireland.buffer(.03))
    groups=collections.defaultdict(list)
    reader=shapefile.Reader(str(HYDRO/'os_open_rivers/data/WatercourseLink.shp'),encoding='latin1')
    excluded=collections.Counter()
    for entry in reader.iterShapeRecords():
        r=entry.record.as_dict(); name=str(r.get('name1','')).strip()
        alternate=str(r.get('name2','')).strip()
        if alternate in MAIN: name=alternate
        elif alternate and alternate!=name: name+=' / '+alternate
        if r['form'] not in ['inlandRiver','tidalRiver'] or str(r['fictitious']).lower()=='true' or not name:
            excluded[str(r['form'])]+=1; continue
        # A source river-form label alone does not establish a natural or
        # pre-1900 channel. Omit clearly engineering-named candidates rather
        # than classifying them as historical drainage from their appearance.
        if UNCERTAIN_ENGINEERING.search(name): excluded['uncertain_engineering_name']+=1; continue
        g=transform(OS_TO_METRES,shape(entry.shape.__geo_interface__))
        groups[name].extend(parts(g,'LineString'))
    result=[]
    for i,(name,lines) in enumerate(sorted(groups.items())):
        length=sum(g.length for g in lines)
        if length<7000 and name not in MAIN: continue
        # Only exactly connected source endpoints merge. Never bridge an unsurveyed gap.
        g=linemerge(MultiLineString(lines)) if len(lines)>1 else lines[0]
        result.append(dict(id=f'river:gb_r43_{i}',kind='river',name=name,geometry=g,
           main=name in MAIN or length>=60000,source='os_open_rivers_r43',rank=None))
    for file in sorted(HYDRO.glob('eu_ireland_rivers_*.geojson')):
        for f in json.loads(file.read_text(encoding='utf8'))['features']:
            p=f['properties']; g=transform(TO_METRES,flat_geometry(f['geometry']))
            if not ireland_m.intersects(g): continue
            name=p.get('nameText') or p.get('nameTxtInt') or ''
            if UNCERTAIN_ENGINEERING.search(name): continue
            order=int(p['STRAHLER']); identity=p['OBJECTID']
            result.append(dict(id=f'river:ie_r43_{identity}',kind='river',name=name or f'Ireland river {identity}',geometry=g,
              main=order>=5 or any(n in name.lower() for n in ['shannon','liffey','lee']),source='eu_hydro_r43',rank=order))
    lakes=[]
    for f in json.loads((HYDRO/'eu_natural_lakes.geojson').read_text(encoding='utf8'))['features']:
        p=f['properties']; g=flat_geometry(f['geometry'])
        if not domain.contains(g.representative_point()): continue
        g=transform(TO_METRES,g)
        lakes.append(dict(id=f'lake:british_r43_{p["OBJECTID"]}',kind='lake',name=p['NAM'].strip(),geometry=g,
            main=g.area>=4000000,source='eu_hydro_r43',rank=None))
    print('OS exclusions',dict(excluded),'Rivers',len(result),'Lakes',len(lakes),flush=True)
    return result+lakes


def write_shard(name,entries,bounds,overview,registry=None,generator='tools/map/build_british_hydro_r43.py'):
    registry=sources() if registry is None else registry
    geometry={}; facts=[]; counts=collections.Counter()
    for entry,g in entries:
        kind=entry['kind']; polygons=parts(g,'Polygon') if kind=='lake' else parts(g,'LineString')
        if not polygons: continue
        tolerance=entry.get('overview_tolerance_m',80) if overview else entry.get('detail_tolerance_m',35)
        g=g.simplify(tolerance,preserve_topology=True)
        polygons=parts(g,'Polygon') if kind=='lake' else parts(g,'LineString')
        if not polygons: continue
        if kind=='lake': raw=[[list(map(list,p.exterior.coords))]+[list(map(list,h.coords)) for h in p.interiors] for p in polygons]
        else: raw=[list(map(list,p.coords)) for p in polygons if len(p.coords)>=2]
        if not raw: continue
        # Convert the completed metric simplification once, offline.
        geo=mapping(transform(TO_DEGREES,shape(dict(type='MultiPolygon' if kind=='lake' else 'MultiLineString',coordinates=raw))))
        coords=geo['coordinates']; ident=entry['id']+':'+name
        display=coords
        if kind=='lake':
            # Existing precomputed-triangle path consumes constrained triangles
            # including islands/holes; no repeated runtime polygon triangulation.
            triangles=transform(TO_DEGREES,constrained_delaunay_triangles(g))
            display=[[list(map(list,t.exterior.coords))] for t in triangles.geoms]
        geometry[ident]=dict(geometry=dict(type=geo['type'],coordinates=coords),lod_geometry=dict(coarse=display,medium=display))
        feature=dict(id=ident,kind=kind,display_name=entry['name'],source_id=entry['source'],source_type='PHYSICAL_REFERENCE',
            source_date=entry.get('source_date','2026-10-18' if entry['source'].startswith('os_') else '2006-2012'),valid_from='1900-01-01',valid_to='9999-12-31',confidence=.8,
            geometry_role='MODERN_HYDROGRAPHIC_REFERENCE_NOT_HISTORICAL',
            presentation_lods=['coarse','medium'],lod_tolerance_m=dict(coarse=tolerance,medium=tolerance),
            geometry_asset=dict(path=f'res://data/strategic/{name}.geom',encoding='ZLIB_JSON_UTF8'),
            stroke_scale=entry.get('stroke_scale',1.20 if overview else .65),source_order=entry['rank'],
            uncertainty='Modern geographic reference; line width is cartographic, not surveyed river width. No 1900 water level, navigation or transport assertion.')
        if kind=='lake': feature['lod_geometry_role']='PRECOMPUTED_DISPLAY_TRIANGLES'
        if entry.get('display_replaces'): feature['display_replaces']=entry['display_replaces']
        if entry.get('source_notes'): feature['source_notes']=entry['source_notes']
        src=next(s for s in registry if s['source_id']==entry['source'])
        facts.append(dict(fact_id='strategic_spatial:'+ident,domain='strategic_spatial_content',subject_id=ident,value=feature,unit='display_geography',
            source_id=src['source_id'],source_version=src['version'],source_locator=src['locator'],
            observation_period=entry.get('observation_period',{'from':'2026-01-01','to':'2026-12-31'} if entry['source'].startswith('os_') else {'from':'2006-01-01','to':'2012-12-31'}),
            spatial_scope=dict(kind='content_shard',id=name),methodology='Actual source geometry; metric simplification, core clipping and two cartographic line weights; no endpoints joined across gaps.',
            confidence=.8,lower_bound=None,upper_bound=None,license=src['license'],review_status='APPROXIMATE',generator=generator))
        counts[kind]+=1
    if not facts: return None
    packed=zlib.compress(json.dumps(geometry,separators=(',',':')).encode(),6)
    (OUT/(name+'.geom')).write_bytes(packed)
    document=dict(metadata=dict(schema_id='global_strategic_content_r1',shard_id=name,valid_from='1900-01-01',valid_to='9999-12-31',
        content_level='strategic',local_support=False,presentation_lods=['coarse','medium'],physical_reference=True),
        source_registry=dict(schema_id='historical_source_registry_v2',sources=registry),evidence_catalog=dict(schema_id='historical_fact_evidence_catalog_v2',facts=facts))
    path=OUT/(name+'.json'); path.write_text(json.dumps(document,ensure_ascii=False,separators=(',',':')),encoding='utf8')
    return dict(id=name,bounds=bounds,anchor=[(bounds[0]+bounds[1])/2,(bounds[2]+bounds[3])/2],path='res://data/strategic/'+path.name,
                bytes=path.stat().st_size,geometry_bytes=len(packed),feature_count=len(facts),counts=dict(counts),detail=not overview)


if __name__=='__main__':
    acquire(); features=read_features()
    descriptors=[]
    descriptors.append(write_shard('british_hydro_overview_r43',[(e,e['geometry']) for e in features if e['main']],[-12,4,48,62],True))
    minor=[e for e in features if not e['main']]
    for lat in range(48,62,4):
        for lon in range(-12,4,4):
            bounds=[lon,lon+4,lat,min(lat+4,62)]
            core=transform(TO_METRES,box(bounds[0],bounds[2],bounds[1],bounds[3]))
            # Exact shared core edges; all intersecting shards are demanded together.
            entries=[(e,e['geometry'].intersection(core)) for e in minor if e['geometry'].intersects(core)]
            descriptor=write_shard(f'british_hydro_{lat}_{lon:+d}_r43',entries,bounds,False)
            if descriptor: descriptors.append(descriptor)
    index_path=OUT/'index.json'; index=json.loads(index_path.read_text(encoding='utf8'))
    index['hydro_regions']=[d for d in index.get('hydro_regions',[]) if not str(d['id']).startswith('british_hydro_')]+descriptors
    index_path.write_text(json.dumps(index,ensure_ascii=False,separators=(',',':')),encoding='utf8')
    summary=dict(descriptors=descriptors,rivers=[dict(id=e['id'],name=e['name'],main=e['main'],source=e['source'],order=e['rank']) for e in features if e['kind']=='river'],
                 lakes=[dict(id=e['id'],name=e['name'],main=e['main']) for e in features if e['kind']=='lake'])
    (HYDRO/'runtime_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf8')
    print('Runtime shards',len(descriptors),'bytes',sum(d['bytes']+d['geometry_bytes'] for d in descriptors),flush=True)
