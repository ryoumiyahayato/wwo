"""Finite British/Irish settlement-reference derivatives; no world entities.

Raw official boundaries stay outside res://. Reuses the existing national
context index, city numeric mesh producer and native resource conversion.
"""
import argparse
import json
import math
import struct
import time
import urllib.parse
import urllib.request
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from collections import Counter
import numpy as np
import shapely
from PIL import Image, ImageDraw
from shapely.geometry import shape, box
from shapely.ops import transform, unary_union
from build_city_miniature import Mesh
from build_france_settlement_context import tile_at, tile_bounds, read, write
from build_benelux_city_context import decode, prepare_ocean, roof_tile, tessellate, write_print

ROOT=Path(__file__).resolve().parents[2]
RAW=ROOT.parent/'offline-map-sources/british_settlement_reference'
OUTPUT=ROOT/'assets/settlements/british_context'
IRISH_NORTH=(-8.25,53.93,-5.33,55.36)
BELFAST_LOUGH=(-6.08,54.49,-5.45,54.83)
EXTRA_BUDGET=35*1024*1024
SOURCES=[
    dict(id='ons_gb_bua_2022',publisher='Office for National Statistics / Ordnance Survey',
         item='ad30b234308f4b02b4bb9b0f4766f7bb',
         url='https://services1.arcgis.com/ESMARspQHYMw9BZ9/arcgis/rest/services/BUA_2022_GB/FeatureServer/0',
         license='OGL-3.0',basis='2022_25M_GRID_BUILT_UP_REFERENCE_NOT_1900',category='urban'),
    dict(id='cso_ireland_bua_2022',publisher='Central Statistics Office / Tailte Éireann',
         item='5468708d36454d1f95a3ff23cbaeb2f5',
         url='https://services-eu1.arcgis.com/BuS9rtTsYEV5C0xh/arcgis/rest/services/Urban_Areas_National_Statistical_Boundaries_2022_Generalised_20m/FeatureServer/5',
         license='CC-BY-4.0',basis='2022_20M_GENERALISED_URBAN_REFERENCE_NOT_1900',category='urban')]

def raw_bytes():
    return sum(p.stat().st_size for source in SOURCES for p in (RAW/source['id']).rglob('*') if p.is_file())

def acquire(source):
    folder=RAW/source['id'];folder.mkdir(parents=True,exist_ok=True)
    def cached(name,url,limit=64*1024*1024):
        path=folder/name
        if not path.exists():
            for attempt in range(3):
                try:
                    with urllib.request.urlopen(url,timeout=45) as response: data=response.read(limit+1)
                    if len(data)>limit:raise ValueError('Source page exceeds declared budget')
                    parsed=json.loads(data)
                    if 'error' in parsed:raise ValueError(str(parsed['error']))
                    current=raw_bytes()
                    if current+len(data)>256*1024*1024:raise ValueError('British source cache exceeds declared 256MiB budget')
                    path.write_bytes(data);break
                except OSError:
                    if attempt==2:raise
                    time.sleep(1+attempt)
        return read(path)
    cached('metadata.json',source['url']+'?f=json')
    cached('license.json','https://www.arcgis.com/sharing/rest/content/items/'+source['item']+'?f=json')
    ids=cached('ids.json',source['url']+'/query?where=1%3D1&returnIdsOnly=true&f=json')['objectIds']
    result=[];seen=set()
    for offset in range(0,len(ids),200):
        selected=ids[offset:offset+200]
        query=dict(objectIds=','.join(map(str,selected)),outFields='*',outSR=4326,f='geojson')
        page=cached('page-%05d.geojson'%offset,source['url']+'/query?'+urllib.parse.urlencode(query))
        features=page.get('features',[])
        if len(features)!=len(selected):raise ValueError('Incomplete official boundary page')
        for feature in features:
            identity=feature.get('id',feature['properties'].get('OBJECTID'))
            if identity in seen:raise ValueError('Repeated source identity')
            seen.add(identity)
            geometry=shapely.make_valid(shape(feature['geometry']))
            if not geometry.is_empty:result.append(geometry)
        print(source['id'],min(offset+200,len(ids)),'/',len(ids),flush=True)
    if raw_bytes()>256*1024*1024:
        raise ValueError('British source cache exceeds declared 256MiB budget')
    source['source_features']=len(ids)
    return result

def build(args):
    RAW.mkdir(exist_ok=True);OUTPUT.mkdir(parents=True,exist_ok=True)
    scratch=RAW/'numeric';scratch.mkdir(exist_ok=True)
    geometries=[]
    for source in SOURCES:geometries.extend(acquire(source))
    tree=shapely.STRtree(geometries)
    envelope=box(-11.0,49.5,2.1,61.1)
    jobs=[]
    for z in [8,10]:
        a,b=tile_at(z,-11,61.1),tile_at(z,2.1,49.5)
        for x in range(a[0],b[0]+1):
            for y in range(a[1],b[1]+1):
                bounds=tile_bounds(z,x,y)
                area=box(*bounds).intersection(envelope)
                if len(tree.query(area,predicate='intersects')):jobs.append((z,x,y,bounds))
    def one(job):
        z,x,y,bounds=job;name=f'context_{z}_{x}_{y}'
        previous=scratch/(name+'.json')
        if not args.rebuild and previous.exists() and (scratch/(name+'.bin')).exists():return read(previous)
        anchor=[(bounds[0]+bounds[2])/2,(bounds[1]+bounds[3])/2]
        sx=111195*math.cos(math.radians(anchor[1]))
        def local(lon,lat,z=None):return (np.asarray(lon)-anchor[0])*sx,(np.asarray(lat)-anchor[1])*111195
        area=box(*bounds).intersection(envelope)
        selected=tree.query(area,predicate='intersects')
        geometry=unary_union([geometries[i].intersection(area) for i in selected])
        geometry=transform(local,geometry).simplify(45 if z==8 else 8,preserve_topology=True)
        mesh=Mesh();mesh.geometry(geometry,.3)
        mesh.colors[0]=[.46,.44,.38,.54]*(len(mesh.positions[0])//3)
        vertices,triangles=mesh.write(scratch/(name+'.bin'))
        row=dict(id=f'{z}/{x}/{y}',name=name,z=z,x=x,y=y,bounds=bounds,anchor=anchor,
                 path=f'res://assets/settlements/british_context/{name}.res',vertices=vertices,triangles=triangles,
                 source_features={'urban':len(selected)})
        write(previous,row);return row
    rows=[]
    with ThreadPoolExecutor(max_workers=1) as pool:
        for i,row in enumerate(pool.map(one,jobs)):
            rows.append(row)
            if (i+1)%25==0:print('Prepared',i+1,'/',len(jobs),flush=True)
    index=dict(schema='national_cartographic_context_v1',anchor=[-3,54],bounds=[-11,49.5,2.1,61.1],
               levels=[dict(z=8,role='overview',simplification_m=45),dict(z=10,role='district',simplification_m=8)],
               tiles={r['id']:r for r in rows if r['triangles']},sources=SOURCES,
               coverage=dict(scope='Modern GB and Republic of Ireland reference. Northern Ireland pending qualified built-up source; no claim of complete 1900 UK coverage.'),
               limits=['Not 1900 urban extent, individual buildings, population or industry.',
                       'No Northern Ireland development-planning boundary is treated as occupied built-up land.',
                       'Existing London historical detail is retained; no modern motorway or railway inferred.'])
    write(OUTPUT/'index.json',index);write(RAW/'source.json',dict(sources=SOURCES,coverage=index['coverage'],raw_bytes=raw_bytes(),numeric_bytes=sum(p.stat().st_size for p in scratch.glob('*.bin'))))
    print('Prepared British context',len(index['tiles']),dict(Counter(r['z'] for r in rows)),flush=True)

def tile_window(z, bounds):
    west,south,east,north=bounds
    a,b=tile_at(z,west,north),tile_at(z,east,south)
    return [(z,x,y) for x in range(a[0],b[0]+1) for y in range(a[1],b[1]+1)]


def add_london_overview(index, scratch):
    # The same generalized 1891–1896 roofs as the established London mesh.
    # Project the existing numeric triangles onto small coverage textures.
    source=ROOT.parent/'offline-map-sources/london_1890s/numeric-meshes/overview.bin'
    if not source.exists(): raise ValueError('Prepare the original historical London overview first')
    raw=source.read_bytes()
    if raw[:8]!=b'CITYMSH1': raise ValueError('Unexpected historical London roof input')
    vertices,count=struct.unpack_from('<II',raw,8)
    points=np.frombuffer(raw,'<f4',vertices*3,16).reshape((-1,3))
    faces=np.frombuffer(raw,'<u4',count,16+vertices*12).reshape((-1,3))
    lon,lat=read(ROOT/'assets/settlements/london_1890s/index.json')['anchor']
    geographic=np.column_stack((lon+points[:,0]/(111195*math.cos(math.radians(lat))),lat-points[:,2]/111195))
    triangles=geographic[faces]; minimum=triangles.min(axis=1); maximum=triangles.max(axis=1)
    bounds=[*minimum.min(axis=0),*maximum.max(axis=0)]
    for key in tile_window(12,bounds):
        _,x,y=key; w,s,e,n=tile_bounds(*key)
        selected=triangles[(maximum[:,0]>=w)&(minimum[:,0]<=e)&(maximum[:,1]>=s)&(minimum[:,1]<=n)]
        if not selected.size: continue
        pixels=(selected-np.array([w,n]))*np.array([512/(e-w),-512/(n-s)])
        mask=Image.new('L',(512,512)); draw=ImageDraw.Draw(mask)
        for triangle in pixels: draw.polygon([tuple(point) for point in triangle],fill=255)
        row=write_print(scratch,12,x,y,mask.resize((256,256),Image.Resampling.LANCZOS),['london_historical'],0,OUTPUT)
        row.pop('source_z'); row['overview_only']='london_historical'
        index['tiles'][row['id']]=row
    cities=index['building_print']['cities']
    cities[:]=[city for city in cities if city['id']!='london_historical']
    cities.append(dict(id='london_historical',anchor=[lon,lat],radius_km=18))
    index['building_print']['historical_london']='Same Petitpierre et al. 1891–1896 roofs as the original London view, CC BY 4.0; overview only.'


def augment():
    index=read(OUTPUT/'index.json')
    scratch=RAW/'numeric'; scratch.mkdir(exist_ok=True)
    cache=RAW/'osm'; cache.mkdir(exist_ok=True)
    selection=read(ROOT/'data/local/britain_city_reference_selection.json')
    url='https://tiles.openfreemap.org/planet/20261101_080013_pt/{z}/{x}/{y}.pbf'
    raw_total=sum(path.stat().st_size for path in cache.glob('*.pbf'))

    def tile(key):
        nonlocal raw_total
        z,x,y=key; path=cache/f'{z}-{x}-{y}.pbf'
        if path.exists(): return path
        limit=min(2*1024*1024,EXTRA_BUDGET-raw_total)
        if limit<=0: raise ValueError('British OSM source budget exceeded')
        request=urllib.request.Request(url.format(z=z,x=x,y=y),headers={'User-Agent':'WWO bounded cartography'})
        for attempt in range(3):
            try:
                with urllib.request.urlopen(request,timeout=35) as response: payload=response.read(limit+1)
                break
            except OSError:
                if attempt==2: raise
                time.sleep(1+attempt)
        if len(payload)>limit: raise ValueError('British source tile exceeds its budget')
        path.write_bytes(payload); raw_total+=len(payload)
        return path

    coast_jobs=tile_window(12,BELFAST_LOUGH)
    for key in coast_jobs: tile(key)
    prepare_ocean(coast_jobs,url,cache,RAW/'coastal_sea.geojson')

    north=box(*IRISH_NORTH)
    occupied=[]
    for key in tile_window(9,IRISH_NORTH):
        landuse=decode(tile(key),*key,['landuse'])['landuse']
        area=box(*tile_bounds(*key)).intersection(north)
        occupied.extend(geom.intersection(area) for props,geom in landuse if props.get('class') in ['residential','commercial','retail','industrial'])
    collar=north.buffer(1.5)
    official_shapes=[geometry for source in SOURCES for geometry in acquire(source) if geometry.intersects(collar)]
    official_tree=shapely.STRtree(official_shapes)
    occupied=unary_union(occupied)
    tiles={key:row for key,row in index['tiles'].items() if not row.get('texture_source')}
    for z in (8,10):
        for key in tile_window(z,IRISH_NORTH):
            _,x,y=key; bounds=tile_bounds(*key); area=box(*bounds)
            local_urban=occupied.intersection(area)
            if local_urban.is_empty: continue
            # Keep the original coverage over the whole output tile, including
            # Scotland when the same overview cell straddles the North Channel.
            official=[official_shapes[i].intersection(area) for i in official_tree.query(area,predicate='intersects')]
            urban=unary_union([local_urban,*official])
            anchor=[(bounds[0]+bounds[2])/2,(bounds[1]+bounds[3])/2]
            scale=111195*math.cos(math.radians(anchor[1]))
            def metres(lon,lat): return (np.asarray(lon)-anchor[0])*scale,(np.asarray(lat)-anchor[1])*111195
            urban=shapely.transform(urban,metres,interleaved=False).simplify(45 if z==8 else 8,preserve_topology=True)
            mesh=Mesh(); tessellate(mesh,urban,.3)
            mesh.colors[0]=[.46,.44,.38,.54]*(len(mesh.positions[0])//3)
            name=f'northern_ireland_{z}_{x}_{y}'
            vertices,triangles=mesh.write(scratch/(name+'.bin'))
            if not triangles: continue
            identity=f'{z}/{x}/{y}'
            tiles[identity]=dict(id=identity,name=name,z=z,x=x,y=y,bounds=bounds,anchor=anchor,path=f'res://assets/settlements/british_context/{name}.res',vertices=vertices,triangles=triangles,source_features={'urban':len(shapely.get_parts(urban))})

    jobs={}
    for city in selection['cities']:
        lon,lat=city['anchor']; dy=city['radius_km']/111.195; dx=dy/math.cos(math.radians(lat))
        for key in tile_window(13,(lon-dx,lat-dy,lon+dx,lat+dy)): jobs.setdefault(key,[]).append(city['id'])
    parents=set()
    for count,(key,cities) in enumerate(jobs.items(),1):
        _,x,y=key; bounds=tile_bounds(*key)
        image,_=roof_tile(decode(tile(key),*key,['building','water']),bounds,box(*bounds))
        for ox in range(2):
            for oy in range(2):
                child=image.crop((ox*256,oy*256,(ox+1)*256,(oy+1)*256))
                if child.getbbox() is None: continue
                cx,cy=x*2+ox,y*2+oy
                row=write_print(scratch,14,cx,cy,child,cities,0,OUTPUT)
                tiles[row['id']]=row; parents.add((cx//4,cy//4))
        if count%20==0: print('British roof source',count,'/',len(jobs),flush=True)
    for x,y in sorted(parents):
        canvas=Image.new('L',(1024,1024)); cities=set()
        for ox in range(4):
            for oy in range(4):
                child=tiles.get(f'14/{x*4+ox}/{y*4+oy}')
                if child:
                    with Image.open(scratch/child['texture_source']) as image: canvas.paste(image,(ox*256,oy*256))
                    cities.update(child['cities'])
        row=write_print(scratch,12,x,y,canvas.resize((256,256),Image.Resampling.LANCZOS),sorted(cities),0,OUTPUT)
        tiles[row['id']]=row
    index['tiles']=tiles
    index['sources']=[source for source in index['sources'] if source.get('id')!='osm_british_context']
    index['sources'].append(dict(id='osm_british_context',publisher='© OpenStreetMap contributors / OpenFreeMap',license='ODbL-1.0',tiles=url,raw_bytes=raw_total,source_roof_tiles=len(jobs),northern_ireland_bounds=IRISH_NORTH))
    index['coverage']['scope']='Modern GB and Irish urban reference, supplemented by mapped land use across Northern Ireland and its geographic collar.'
    index['limits']=[row for row in index['limits'] if 'Northern Ireland' not in row]
    index['building_print']=dict(cities=selection['cities'],levels=[12,14],source_z=13,mask_size={'12':256,'14':256},basis=selection['geometry_basis'])
    add_london_overview(index,scratch)
    write(OUTPUT/'index.json',index)
    manifest=read(RAW/'source.json'); manifest.update(sources=index['sources'],coverage=index['coverage'])
    write(RAW/'source.json',manifest)
    print('British native tiles ready',dict(Counter(row['z'] for row in tiles.values())),raw_total,'OSM source bytes',flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rebuild',action='store_true')
    parser.add_argument('--augment-existing',action='store_true',help='Add bounded OSM inputs to the installed GB and Irish base')
    parser.add_argument('--london-overview-only',action='store_true',help='Refresh only the original London roof overview')
    args=parser.parse_args()
    if args.london_overview_only:
        index=read(OUTPUT/'index.json')
        add_london_overview(index,RAW/'numeric')
        write(OUTPUT/'index.json',index)
    else:
        if not args.augment_existing: build(args)
        augment()
