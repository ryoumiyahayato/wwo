"""Bounded European source derivatives for the national settlement renderer.

OSM/OpenMapTiles modern reference, not 1900 reconstruction. At most 3,000
source tiles per run, a 50 MB default budget and one request at a time; pinned TileJSON. No full-country
building download, per-house nodes, world entities or transport capacity.
Native conversion uses the existing save_city_meshes.gd. Raw PBF and numeric
intermediates remain outside res://. Production is single CPU worker.
"""
import json
import argparse
import math
import time
import urllib.request
import zlib
import struct
from functools import lru_cache
from pathlib import Path

from mapbox_vector_tile.decoder import TileData
import numpy as np
import requests
import shapely
from affine import Affine
from PIL import Image, ImageFilter
from rasterio.features import rasterize
from shapely.geometry import box, shape, mapping
from shapely.ops import transform, unary_union
from pyproj import Transformer

from build_city_miniature import Mesh
from build_france_settlement_context import ROOT, read, write, tile_at, tile_bounds

RAW = ROOT.parent/'offline-map-sources/benelux_settlement_reference'
OUTPUT = ROOT/'assets/settlements/benelux_context'
AGENT = 'WWO-Benelux-offline-reference/1.0'
RAW_BUDGET = 50_000_000
ENVELOPE = box(2.2, 49.2, 7.7, 54.0)
REGION = 'benelux'
COUNTRY_CODES = [210,211,212]
OWNER_MASK = None
SEA_METRIC = None
TO_METRES = Transformer.from_crs(4326,3035,always_xy=True).transform
FROM_METRES = Transformer.from_crs(3035,4326,always_xy=True).transform
IGN_BTN_TILES = 'https://vt-btn.idee.es/1.0.0/btn/tile/{z}/{y}/{x}.pbf'
POLYGON_ROOF_CACHES = {
    'gba_polygon': 'gba_roofs',
    'eubucco_polygon': 'eubucco_roofs',
    'overture_polygon': 'overture_roofs',
}
STYLE = {'woodland':(.37,.44,.32,.16), 'urban':(.46,.44,.38,.30), 'industrial':(.39,.42,.40,.26), 'water':(.34,.46,.45,1.0),
         'fields':(.46,.48,.36,.25), 'grass':(.41,.49,.34,.14)}


def configure(region):
    global REGION, COUNTRY_CODES, RAW, OUTPUT, AGENT, ENVELOPE
    REGION=region
    if region=='germany':
        COUNTRY_CODES=[255]
        RAW=ROOT.parent/'offline-map-sources/germany_settlement_reference'
        OUTPUT=ROOT/'assets/settlements/germany_context'
        AGENT='WWO-Germany-offline-reference/1.0'
        ENVELOPE=box(5.3,47.0,23.3,56.0)
    elif region=='iberia':
        COUNTRY_CODES=[230,235]
        RAW=ROOT.parent/'offline-map-sources/iberian_settlement_reference'
        OUTPUT=ROOT/'assets/settlements/iberian_context'
        AGENT='WWO-Iberian-Peninsula-offline-reference/1.0'
        ENVELOPE=box(-9.7,35.9,3.5,44.0)
    elif region=='europe':
        RAW=ROOT.parent/'offline-map-sources/europe_settlement_reference'
        OUTPUT=ROOT/'assets/settlements/europe_context'
        AGENT='WWO-European-city-offline-reference/1.0'
        ENVELOPE=box(-12.0,35.0,63.0,72.0)


def country_scope():
    countries = read(ROOT/'data/world_map/historical/cshapes_1900_snapshot.json')['features']
    scope=unary_union([shape(f['geometry']) for f in countries if f['gwcode'] in COUNTRY_CODES]).intersection(ENVELOPE)
    if REGION=='iberia':
        mainland=max(shapely.get_parts(scope),key=lambda part:part.area)
        # Include the Andorran and Gibraltar surroundings as geographic data.
        return mainland.union(box(1.40,42.42,1.82,42.67)).union(box(-5.38,36.10,-5.31,36.18))
    if REGION=='germany':
        # Named historical border towns may lie outside a coarse country
        # source. Their display windows are not a sovereignty correction.
        for city in read(ROOT/'data/local/germany_city_reference_selection.json')['cities']:
            lon,lat=city['anchor'];r=city['radius_km']
            dx=r/(111.195*math.cos(math.radians(lat)));dy=r/111.195
            scope=scope.union(box(lon-dx,lat-dy,lon+dx,lat+dy))
    return scope


def reference_scope():
    # A coarse political coastline is a selection hint, not a shore mask.
    # The small geographic fringe is bounded by complete admitted z9 tiles;
    # actual physical coast and the historical sea are applied separately.
    scope=country_scope();a,b=tile_at(9,scope.bounds[0],scope.bounds[3]),tile_at(9,scope.bounds[2],scope.bounds[1])
    cells=[box(*tile_bounds(9,x,y)) for x in range(a[0],b[0]+1) for y in range(a[1],b[1]+1) if scope.intersects(box(*tile_bounds(9,x,y)))]
    return scope.buffer(.08).intersection(unary_union(cells)).intersection(ENVELOPE)


def source_mask():
    global SEA_METRIC
    scope=reference_scope()
    index = read(ROOT/'data/strategic/index.json')
    land = []
    for parent in index['coast_regions']:
        for row in parent.get('medium_regions',[]):
            b = row['bounds']
            if not box(b[0],b[2],b[1],b[3]).intersects(scope): continue
            doc = read(ROOT/row['path'].replace('res://',''))
            record = next(f['value'] for f in doc['evidence_catalog']['facts'] if f['value']['kind']=='land_reference')
            data = json.loads(zlib.decompress((ROOT/record['geometry_asset']['path'].replace('res://','')).read_bytes()))
            land.append(shape(data['land_reference:'+row['id']]['geometry']))
    if REGION!='benelux':
        return shapely.make_valid(scope.intersection(unary_union(land)))
    wet = []
    for row in index.get('hydro_regions',[]):
        if row['id']!='benelux_hydro_overview_r46': continue
        doc = read(ROOT/row['path'].replace('res://',''))
        record = next(f['value'] for f in doc['evidence_catalog']['facts'] if 'geometry_asset' in f['value'])
        data = json.loads(zlib.decompress((ROOT/record['geometry_asset']['path'].replace('res://','')).read_bytes()))
        for identity, geometry in data.items():
            if 'zuiderzee_near1900_reference' in identity:
                wet.append(shape(geometry['geometry']))
    physical=unary_union(land);history=unary_union(wet)
    SEA_METRIC=transform(TO_METRES,ENVELOPE.difference(physical).union(history))
    return shapely.make_valid(scope.intersection(physical).difference(history))


def water_palette(positions,anchor,colors):
    positions=np.asarray(positions,dtype='float64').reshape((-1,3))
    colors=np.asarray(colors,dtype='float32').reshape((-1,4)).copy()
    selected=colors[:,2]>colors[:,0]+.05
    if not selected.any():return colors.ravel().tolist()
    sx=111195*math.cos(math.radians(anchor[1]))
    lon=anchor[0]+positions[selected,0]/sx;lat=anchor[1]-positions[selected,2]/111195
    x,y=TO_METRES(lon,lat)
    distance=shapely.distance(shapely.points(x,y),SEA_METRIC)
    amount=np.clip(distance/1500.,0,1);amount=amount*amount*(3-2*amount)
    ocean=np.array([.12,.20,.23]);river=np.array(STYLE['water'][:3])
    colors[selected,:3]=ocean+(river-ocean)*amount[:,None]
    return colors.ravel().tolist()


def recolor_water():
    source_mask() # Admitted physical sea and the existing 1905 water reference.
    index=read(OUTPUT/'index.json');scratch=RAW/'numeric';updated=0
    for row in index['tiles'].values():
        if row.get('texture_source'):continue
        path=scratch/(row['name']+'.bin')
        with path.open('rb') as stream:
            if stream.read(8)!=b'CITYMSH2':raise ValueError('Expected existing coloured numeric mesh')
            mesh=Mesh()
            for surface in range(2):
                count,indices=struct.unpack('<II',stream.read(8))
                mesh.positions[surface]=np.frombuffer(stream.read(count*12),dtype='<f4').tolist()
                mesh.indices[surface]=np.frombuffer(stream.read(indices*4),dtype='<u4').tolist()
                original=np.frombuffer(stream.read(count*16),dtype='<f4')
                mesh.colors[surface]=water_palette(mesh.positions[surface],row['anchor'],original)
        mesh.write(path);updated+=1
    index['water_palette']=dict(basis='Connected water cartographic tone, not depth or salinity',ocean_rgb=[.12,.20,.23],river_rgb=list(STYLE['water'][:3]),transition_m=1500,source='Installed physical ocean and original 1905 Zuiderzee water reference',geometry_unchanged=True)
    write(OUTPUT/'index.json',index)
    print('Recoloured existing context meshes',updated,'geometry unchanged',flush=True)


def coastal_jobs():
    scope=country_scope().buffer(.12)
    index=read(ROOT/'data/strategic/index.json');lines=[]
    for parent in index['coast_regions']:
        for row in parent.get('medium_regions',[]):
            b=row['bounds']
            if not box(b[0],b[2],b[1],b[3]).intersects(scope):continue
            doc=read(ROOT/row['path'].replace('res://',''))
            record=next(f['value'] for f in doc['evidence_catalog']['facts'] if f['value']['kind']=='land_reference')
            geometry=json.loads(zlib.decompress((ROOT/record['geometry_asset']['path'].replace('res://','')).read_bytes()))
            coast=shape(geometry['coast:'+row['id']]['geometry']).intersection(scope).intersection(ENVELOPE)
            if not coast.is_empty:lines.append(coast)
    band=unary_union(lines).buffer(.035)
    a,b=tile_at(12,band.bounds[0],band.bounds[3]),tile_at(12,band.bounds[2],band.bounds[1])
    return {(12,x,y) for x in range(a[0],b[0]+1) for y in range(a[1],b[1]+1) if band.intersects(box(*tile_bounds(12,x,y)))}


def decode(path, z, x, y, names):
    tile=TileData(path.read_bytes(),default_options={'y_coord_down':True})
    # Ignore geometry for layers this derivative never consumes.
    for index in range(len(tile.tile.layers)-1,-1,-1):
        if tile.tile.layers[index].name not in names:del tile.tile.layers[index]
    doc=tile.get_message()
    result = {}
    for name in names:
        layer = doc.get(name,{})
        extent = layer.get('extent',4096)
        def geographic(px,py,pz=None):
            gx = (x+np.asarray(px)/extent)/2**z
            gy = (y+np.asarray(py)/extent)/2**z
            return gx*360-180,np.degrees(np.arctan(np.sinh(math.pi*(1-2*gy))))
        result[name] = []
        for feature in layer.get('features',[]):
            if name == 'waterway' and feature['geometry']['type'] in ('LineString', 'MultiLineString'):
                line = shapely.transform(shape(feature['geometry']), geographic, interleaved=False)
                result[name].append((feature['properties'], line))
                continue
            if feature['geometry']['type'] not in ['Polygon','MultiPolygon']:continue
            # Repair can retain collapsed lines in a GeometryCollection.
            # Only actual faces enter the area renderer and polygon overlays.
            geometry=shapely.make_valid(shapely.transform(shape(feature['geometry']),geographic,interleaved=False))
            stack=[geometry];faces=[]
            while stack:
                part=stack.pop()
                if part.geom_type=='Polygon':faces.append(part)
                else:stack.extend(getattr(part,'geoms',[]))
            geometry=shapely.set_precision(unary_union(faces),1e-9)
            if not geometry.is_empty:result[name].append((feature['properties'],geometry))
    return result


def prepare_ocean(jobs, tile_url, cache=None, output=None):
    cache=cache or RAW
    coverage=unary_union([box(*tile_bounds(*key)) for key in jobs])
    sea=[]
    for z,x,y in sorted(jobs):
        for props,geometry in decode(cache/f'{z}-{x}-{y}.pbf',z,x,y,['water'])['water']:
            if props.get('class')=='ocean':
                sea.append(geometry.intersection(box(*tile_bounds(z,x,y))))
    if not sea:raise ValueError('No admitted ocean polygons in coastal source tiles')
    write(output or RAW/'coastal_sea.geojson',dict(geometry=mapping(unary_union(sea)),coverage=mapping(coverage),source_tiles=len(jobs),source_z=min(key[0] for key in jobs),tile_url=tile_url,license='ODbL-1.0',basis='MODERN_OSM_SEA_POLYGONS_NOT_1900_COAST'))


def cover_cells(bounds):
    w,s,e,n=bounds
    for lon in range(math.floor(w/3)*3,math.ceil(e/3)*3,3):
        for lat in range(math.floor(s/3)*3,math.ceil(n/3)*3,3):
            yield lon,lat


def cover_mask(lon,lat,acquire=False):
    name=f"N{lat:02d}E{lon:03d}"
    path=RAW/'worldcover'/f'{name}.png'
    if not path.exists() and acquire:
        import rasterio
        from rasterio.enums import Resampling
        path.parent.mkdir(exist_ok=True)
        url='https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/'+f'ESA_WorldCover_10m_2021_v200_{name}_Map.tif'
        with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN='EMPTY_DIR', GDAL_HTTP_TIMEOUT='25', CPL_VSIL_CURL_ALLOWED_EXTENSIONS='.tif', GDAL_CACHEMAX=32*1024*1024):
            with rasterio.open(url) as source:
                data=source.read(1,out_shape=(1125,1125),resampling=Resampling.nearest)
        Image.fromarray((data==50).astype('uint8')*255).save(path)
        print('Acquired WorldCover built-up overview',name,flush=True)
    return path


@lru_cache(maxsize=4)
def cover_pixels(lon,lat):
    with Image.open(cover_mask(lon,lat)) as image:
        return np.asarray(image).copy()


def cover_image(bounds,size):
    w,s,e,n=bounds
    # Sample a common geographic grid before reducing to the stored mask.
    # Area coverage retains isolated settlements without inventing footprints.
    side=size*2
    longitude=w+(np.arange(side)+.5)*(e-w)/side
    latitude=n-(np.arange(side)+.5)*(n-s)/side
    result=np.zeros((side,side),dtype=np.uint8)
    for lon,lat in cover_cells(bounds):
        if not cover_mask(lon,lat).exists():continue # Outside the acquired land window.
        x=np.flatnonzero((longitude>=lon)&(longitude<lon+3))
        y=np.flatnonzero((latitude>lat)&(latitude<=lat+3))
        if not x.size or not y.size:continue
        pixels=cover_pixels(lon,lat)
        column=((longitude[x]-lon)*pixels.shape[1]/3).astype(int)
        row=((lat+3-latitude[y])*pixels.shape[0]/3).astype(int)
        result[np.ix_(y,x)]=pixels[np.ix_(row,column)]
    return np.asarray(Image.fromarray(result).resize((size,size),Image.Resampling.BOX)).copy()


def build(acquire_only=False, rebuild=False, reuse_district=False):
    global OWNER_MASK
    RAW.mkdir(exist_ok=True);OUTPUT.mkdir(parents=True,exist_ok=True)
    if not acquire_only and not rebuild and (OUTPUT/'index.json').exists():
        previous=read(OUTPUT/'index.json')
        if previous.get('recipe_version')==4 and all((OUTPUT/(row['name']+'.res')).exists() for row in previous['tiles'].values()):
            print('Reusing installed derivatives; --rebuild regenerates numeric inputs.',flush=True)
            return
    scratch=RAW/'numeric';scratch.mkdir(exist_ok=True)
    metadata_path=RAW/'tilejson.json'
    shared=ROOT.parent/'offline-map-sources/benelux_settlement_reference'
    if REGION in ('germany','iberia') and not metadata_path.exists():
        metadata_path.write_bytes((shared/'tilejson.json').read_bytes())
    if not metadata_path.exists():
        with urllib.request.urlopen(urllib.request.Request('https://tiles.openfreemap.org/planet',headers={'User-Agent':AGENT}),timeout=35) as response:
            metadata_path.write_bytes(response.read(1024*1024))
    metadata=read(metadata_path)
    selection=read(ROOT/f'data/local/{REGION}_city_reference_selection.json')
    scope=country_scope()
    source_jobs=set()
    a,b=tile_at(9,scope.bounds[0],scope.bounds[3]),tile_at(9,scope.bounds[2],scope.bounds[1])
    for x in range(a[0],b[0]+1):
        for y in range(a[1],b[1]+1):
            if scope.intersects(box(*tile_bounds(9,x,y))):source_jobs.add((9,x,y))
    cities_by_source={}
    for city in selection['cities']:
        lon,lat=city['anchor'];r=city['radius_km']
        dx=r/(111.195*math.cos(math.radians(lat)));dy=r/111.195
        a,b=tile_at(13,lon-dx,lat+dy),tile_at(13,lon+dx,lat-dy)
        for x in range(a[0],b[0]+1):
            for y in range(a[1],b[1]+1):cities_by_source.setdefault((13,x,y),[]).append(city['id'])
    source_jobs.update(cities_by_source)
    shore_jobs=(coastal_jobs() if acquire_only or not (RAW/'coastal_sea.geojson').exists() else {tuple(map(int,p.stem.split('-'))) for p in RAW.glob('12-*.pbf')}) if REGION=='benelux' else set()
    source_jobs.update(shore_jobs)
    if len(source_jobs)>3000:raise ValueError('Offline tile-count budget exceeded')
    print(REGION,'source tiles',len(source_jobs),'cities',len(selection['cities']),flush=True)
    reused={key:shared/f'{key[0]}-{key[1]}-{key[2]}.pbf' for key in source_jobs if REGION=='germany' and key[0]==13 and (shared/f'{key[0]}-{key[1]}-{key[2]}.pbf').exists() and not (RAW/f'{key[0]}-{key[1]}-{key[2]}.pbf').exists()}
    cover_jobs={key for key in source_jobs if REGION=='germany' and key[0]==9}
    source_bytes=sum(p.stat().st_size for p in RAW.glob('*.pbf'))+sum(p.stat().st_size for p in reused.values())
    def download(key):
        nonlocal source_bytes
        z,x,y=key;path=RAW/f'{z}-{x}-{y}.pbf'
        if path.exists():return path
        if key in reused:return reused[key]
        request=urllib.request.Request(metadata['tiles'][0].format(z=z,x=x,y=y),headers={'User-Agent':AGENT})
        remaining=RAW_BUDGET-source_bytes
        if remaining<=0:raise ValueError('50 MB offline source budget exceeded')
        with urllib.request.urlopen(request,timeout=35) as response:
            declared=response.headers.get('Content-Length')
            if declared is not None and int(declared)>remaining:
                raise ValueError('50 MB offline source budget exceeded')
            payload=response.read(min(2*1024*1024,remaining)+1)
        if len(payload)>2*1024*1024:raise ValueError('Source tile exceeds 2 MiB')
        if len(payload)>remaining:raise ValueError('50 MB offline source budget exceeded')
        path.write_bytes(payload);source_bytes+=len(payload)
        return path
    tiles={};overview={};print_parents=set();groups_count=0
    ordered=sorted(source_jobs,reverse=True)
    cover_scope=scope.buffer(.08)
    cover_source_cells=sorted({(lon,lat) for key in cover_jobs for lon,lat in cover_cells(tile_bounds(*key)) if cover_scope.intersects(box(lon,lat,lon+3,lat+3))})
    if acquire_only:
        if REGION=='iberia':
            portugal=shape(next(f['geometry'] for f in read(ROOT/'data/world_map/historical/cshapes_1900_snapshot.json')['features'] if f['gwcode']==235))
            ordered.sort(key=lambda key: (portugal.covers(box(*tile_bounds(*key)).centroid),-key[0]))
        for lon,lat in cover_source_cells:
            cover_mask(lon,lat,acquire=True)
        for number,key in enumerate((key for key in ordered if key not in cover_jobs),1):
            download(key)
            if number%20==0:print('Acquired',number,'/',len(ordered),'source bytes',source_bytes,flush=True)
        ocean_jobs=shore_jobs
        if REGION=='iberia':
            ports={'barcelona','bilbao','malaga','vigo','cadiz','irun_hendaye','lisboa','porto','setubal','valencia'}
            ocean_jobs={key for key,cities in cities_by_source.items() if ports.intersection(cities)}
        if ocean_jobs:prepare_ocean(ocean_jobs,metadata['tiles'][0])
        print('Source cache ready',source_bytes,'bytes; coast tiles',len(ocean_jobs),flush=True)
        return
    if any(not cover_mask(lon,lat).exists() for lon,lat in cover_source_cells):
        raise ValueError('Acquire the required WorldCover land windows before production')
    mask=source_mask()
    owner_scope=reference_scope()
    if REGION=='germany':
        benelux=read(ROOT/'assets/settlements/benelux_context/index.json')
        owner_scope=owner_scope.difference(shape(benelux['coverage']['geometry']))
    OWNER_MASK=mask.intersection(owner_scope)
    fine={kind:[] for kind in STYLE};shore_water=[]
    fine_coverage=unary_union([box(*tile_bounds(*key)) for key in cities_by_source])
    shore_coverage=unary_union([box(*tile_bounds(*key)) for key in shore_jobs])
    refined=None
    prepared_path=RAW/'context_inputs.geojson'
    if prepared_path.exists():
        prepared=read(prepared_path)
        if prepared.get('recipe_version')==2 and prepared.get('tile_url')==metadata['tiles'][0] and prepared.get('city_windows')==selection['cities']:
            refined={kind:shape(value) for kind,value in prepared['groups'].items()}
            groups_count=prepared['source_geometry_groups']
            for z,x,y in cities_by_source:
                for ox in [0,1]:
                    for oy in [0,1]:
                        tx,ty=x*2+ox,y*2+oy
                        row=read(scratch/f'buildings_14_{tx}_{ty}.json')
                        tiles[row['id']]=row;print_parents.add((tx//4,ty//4))
            ordered=[key for key in ordered if key[0]==9]
            print('Reusing prepared city/river source geometry and roof masks',flush=True)
    if reuse_district:
        remaining=[]
        for key in ordered:
            z,x,y=key
            parent=scratch/f'context_8_{x//2}_{y//2}.json'
            if z!=9 or not parent.exists():
                remaining.append(key)
                continue
            row=read(parent)
            tiles[row['id']]=row
            for ox in (0,1):
                for oy in (0,1):
                    child=scratch/f'context_10_{x*2+ox}_{y*2+oy}.json'
                    if child.exists():
                        row=read(child)
                        tiles[row['id']]=row
        ordered=remaining
    for number,key in enumerate(ordered,1):
        z,x,y=key
        if key in cover_jobs:
            overview[(x//2,y//2)]={}
            for ox in (0,1):
                for oy in (0,1):
                    row=write_context(scratch,10,x*2+ox,y*2+oy,{})
                    if row:tiles[row['id']]=row
            if number%20==0:print('Prepared',number,'/',len(ordered),'source cells',flush=True)
            continue
        path=download(key)
        if z==9:
            if refined is None:
                refined={kind:unary_union(values) for kind,values in fine.items()}
                refined['water']=refined['water'].union(unary_union(shore_water).difference(fine_coverage))
                write(prepared_path,dict(recipe_version=2,tile_url=metadata['tiles'][0],city_windows=selection['cities'],groups={k:mapping(v) for k,v in refined.items()},source_geometry_groups=groups_count))
            data=decode(path,z,x,y,['landuse','landcover','water'] if REGION=='benelux' else ['landuse'])
            groups={kind:[] for kind in STYLE}
            cell=box(*tile_bounds(z,x,y))
            # For the peninsula, these groups are clipped per source cell.
            # Intersecting each feature with the whole national coast is costly.
            feature_mask=shapely.make_valid(shapely.clip_by_rect(mask,*cell.bounds)) if REGION!='benelux' else mask
            for props,geometry in data['landuse']:
                category='urban' if props.get('class') in ['residential','retail','commercial'] else 'industrial' if props.get('class')=='industrial' else None
                if category:groups[category].append(geometry.intersection(feature_mask))
            if REGION=='benelux':
                for props,geometry in data['landcover']:
                    if props.get('class')=='wood':groups['woodland'].append(geometry.intersection(mask))
                for props,geometry in data['water']:
                    if props.get('class')=='river' and not props.get('intermittent',0):groups['water'].append(geometry.intersection(mask))
            # The already acquired city source replaces coarse land-use
            # geometry, not just its colour. No street/urban shape is invented.
            groups={k:unary_union(v).difference(fine_coverage.union(shore_coverage) if k=='water' else fine_coverage).union(refined[k].intersection(cell)) for k,v in groups.items()}
            parent=overview.setdefault((x//2,y//2),{kind:[] for kind in STYLE})
            for kind,geometry in groups.items():parent[kind].append(geometry)
            for ox in [0,1]:
                for oy in [0,1]:
                    tx,ty=x*2+ox,y*2+oy
                    if reuse_district:
                        metadata_path=scratch/f'context_10_{tx}_{ty}.json'
                        row=read(metadata_path) if metadata_path.exists() else None
                    else:
                        row=write_context(scratch,10,tx,ty,groups)
                    if row:tiles[row['id']]=row
        elif z==12:
            cell=box(*tile_bounds(z,x,y)).intersection(mask)
            for props,geometry in decode(path,z,x,y,['water'])['water']:
                if props.get('class')=='river' and not props.get('intermittent',0):shore_water.append(geometry.intersection(cell))
        elif z==13:
            data=decode(path,z,x,y,['building','water','landuse','landcover'])
            cell=box(*tile_bounds(z,x,y)).intersection(mask)
            for props,geometry in data['landuse']:
                category='urban' if props.get('class') in ['residential','retail','commercial'] else 'industrial' if props.get('class')=='industrial' else None
                if category:fine[category].append(geometry.intersection(cell))
            if REGION=='benelux':
                for props,geometry in data['landcover']:
                    if props.get('class')=='wood':fine['woodland'].append(geometry.intersection(cell))
                for props,geometry in data['water']:
                    if props.get('class')=='river' and not props.get('intermittent',0):fine['water'].append(geometry.intersection(cell))
            image,count=roof_tile(data,tile_bounds(z,x,y),cell);groups_count+=count
            for ox in [0,1]:
                for oy in [0,1]:
                    tx,ty=x*2+ox,y*2+oy
                    child=image.crop((ox*256,oy*256,(ox+1)*256,(oy+1)*256))
                    row=write_print(scratch,14,tx,ty,child,cities_by_source[key],count)
                    tiles[row['id']]=row;print_parents.add((tx//4,ty//4))
        if number%20==0:print('Prepared',number,'/',len(ordered),'source bytes',source_bytes,flush=True)
    for (x,y),groups in overview.items():
        row=write_context(scratch,8,x,y,{k:unary_union(v) for k,v in groups.items()})
        if row:tiles[row['id']]=row
    for x,y in sorted(print_parents):
        canvas=Image.new('L',(1024,1024));cities=set()
        for ox in range(4):
            for oy in range(4):
                child=tiles.get(f'14/{x*4+ox}/{y*4+oy}')
                if not child:continue
                canvas.paste(Image.open(scratch/child['texture_source']),(ox*256,oy*256));cities.update(child['cities'])
        row=write_print(scratch,12,x,y,canvas.resize((512,512),Image.Resampling.LANCZOS),sorted(cities),0)
        tiles[row['id']]=row
    source=dict(publisher='OpenStreetMap contributors / OpenFreeMap / OpenMapTiles',license='ODbL-1.0',url='https://openfreemap.org/quick_start/',tilejson='https://tiles.openfreemap.org/planet',tiles=metadata['tiles'][0],schema_version=metadata.get('version'),basis='MODERN_OSM_CARTOGRAPHIC_REFERENCE_NOT_1900',raw_budget_bytes=RAW_BUDGET,source_bytes=source_bytes,source_tiles=len(source_jobs))
    index=dict(schema='national_cartographic_context_v1',recipe_version=3,anchor=[4.8,51.5],bounds=[2.2,49.2,7.7,54.0],levels=[dict(z=8,source_z=9,role='overview',simplification_m=45),dict(z=10,source_z=9,role='district',simplification_m=8)],tiles=tiles,sources=[source],refined_context=dict(urban_source_z=13,coastal_river_source_z=12,water_classes=['river'],basis='Modern source polygons, not historical canal/port engineering. Lake/reservoir polygons not admitted as rivers.'),building_print=dict(cities=selection['cities'],selection='res://data/local/benelux_city_reference_selection.json',levels=[12,14],source_z=13,mask_size={'12':512,'14':256},basis=selection['geometry_basis'],source_geometry_groups=groups_count),coverage=dict(scope='Finite three-country selection plus 0.08-degree geographic fringe, bounded by complete admitted z9 tiles; physical coast clips land independently; admitted near-1900 Zuiderzee excluded.',geometry=mapping(reference_scope()),role='OFFLINE_SOURCE_HANDOFF_ONLY_NOT_SOVEREIGNTY_OR_SHORE'),limits=['Source zoom 13 roofs are already generalised; nominal print LOD 14 does not add surveyed detail.','Not 1900 urban limits, buildings, population, ownership or transport capacity.','OSM coverage varies; neighbourhood/suburb place polygons never become built-up land.','No modern reclaimed settlement is painted over the admitted near-1900 Zuiderzee.'])
    index.update(recipe_version=4,anchor=list(ENVELOPE.centroid.coords[0]),bounds=list(ENVELOPE.bounds))
    index['sources'][0].update(reused_source_tiles=len(reused),region=REGION)
    index['building_print']['selection']=f'res://data/local/{REGION}_city_reference_selection.json'
    index['coverage'].update(scope=REGION+' geographic reference with 0.08-degree fringe; physical coast applied independently',geometry=mapping(owner_scope),reference_source='res://data/world_map/historical/cshapes_1900_snapshot.json',reference_license='CC BY-NC-SA 4.0; existing source notice retained; reference selection only')
    if REGION!='benelux':
        index['refined_context']=dict(urban_source_z=13,water_classes=[],basis='Built-up and industrial land only. Existing regional hydro and relief remain separate.')
        index['limits'].pop()
        prune_empty_prints(index['tiles'],scratch)
    if cover_jobs:
        index['sources'][0]['source_tiles']-=len(cover_jobs)
        index['sources'].append(dict(publisher='ESA WorldCover 2021 v200',license='CC-BY-4.0',url='https://esa-worldcover.org/en/data-access',basis='MODERN_CLASS_50_BUILT_UP_32X_OVERVIEW',source_tiles=len(cover_source_cells),coverage_cells=len(cover_jobs)))
    if REGION=='germany':
        index['levels']=[dict(z=8,role='overview',mask_size=128),dict(z=10,role='district',mask_size=256)]
    if reuse_district:
        for row in tiles.values():
            row['path']=f"res://assets/settlements/{OUTPUT.name}/{row['name']}.res"
    write(OUTPUT/'index.json',index);write(RAW/'source.json',dict(sources=[source],coverage=index['coverage'],limits=index['limits'],city_windows=selection['cities']))
    print('Ready',len(tiles),'resources; raw',source_bytes,'bytes',flush=True)


def prune_empty_prints(tiles,scratch):
    for tile_id,row in list(tiles.items()):
        if not row.get('texture_source'):continue
        with Image.open(scratch/row['texture_source']) as image:
            if image.getbbox() is None:del tiles[tile_id]


def write_context(scratch,z,x,y,groups):
    bounds=tile_bounds(z,x,y);area=box(*bounds)
    anchor=[(bounds[0]+bounds[2])/2,(bounds[1]+bounds[3])/2]
    if REGION=='germany':
        # Use coverage masks for the broad German layer. At these scales the
        # raster source and the generalised land-use don't need triangulation.
        w,s,e,n=bounds
        size=128 if z==8 else 256
        frame=Affine((e-w)/size,0,w,0,-(n-s)/size,n)
        land=shapely.clip_by_rect(OWNER_MASK,*bounds)
        if land.is_empty:return None
        image=cover_image(bounds,size)
        image*=rasterize([(land,1)],out_shape=(size,size),transform=frame,dtype='uint8')
        if not image.any():return None
        name=f'context_{z}_{x}_{y}'
        Image.fromarray(image).save(scratch/(name+'.png'))
        row=dict(id=f'{z}/{x}/{y}',name=name,z=z,x=x,y=y,bounds=bounds,anchor=anchor,path=f'res://assets/settlements/{OUTPUT.name}/{name}.res',vertices=4,triangles=2,texture_source=name+'.png',resident_bytes=size*size*4//3+128)
        write(scratch/(name+'.json'),row)
        return row
    sx=111195*math.cos(math.radians(anchor[1]))
    def local(lon,lat,z=None):return (np.asarray(lon)-anchor[0])*sx,(np.asarray(lat)-anchor[1])*111195
    clipped=shapely.clip_by_rect(OWNER_MASK,*bounds) if REGION!='benelux' else area.intersection(OWNER_MASK)
    clip=polygonal(shapely.transform(clipped,local,interleaved=False))
    if clip.is_empty:return None
    mesh=Mesh();counts={}
    for rank,(kind,geometry) in enumerate(groups.items()):
        if geometry.is_empty:continue
        # Boolean seams can retain sub-millimetre slivers. Use centimetre
        # numeric precision before map-scale simplification and triangulation.
        source=polygonal(shapely.transform(geometry,local,interleaved=False))
        tolerance=45 if z==8 else 8
        if REGION=='europe':
            tolerance=95 if z==8 else (8 if kind=='water' else 16)
        geometry=source.simplify(tolerance,preserve_topology=True)
        if geometry.is_empty:continue
        # Simplify source content first. The shared source handoff edge must
        # survive exactly on both sides, independent of LOD and country.
        try:
            geometry=polygonal(geometry).intersection(clip,grid_size=.01)
        except shapely.errors.GEOSException:
            if REGION!='iberia' or z!=8:raise
            # The source cells are already clipped to the same land mask.
            # Keep their unsimplified outline if the overview overlay fails.
            geometry=source
            print('Kept source outline for overview',x,y,kind,flush=True)
        geometry=shapely.set_precision(shapely.make_valid(geometry),.01)
        start=len(mesh.positions[0])//3
        tessellate(mesh,geometry,.25+rank*.08)
        mesh.colors[0].extend(list(STYLE[kind])*(len(mesh.positions[0])//3-start))
        counts[kind]=len(shapely.get_parts(geometry)) if not geometry.is_empty else 0
    if not mesh.indices[0]:return None
    if SEA_METRIC is not None:
        mesh.colors[0]=water_palette(mesh.positions[0],anchor,mesh.colors[0])
    name=f'context_{z}_{x}_{y}';vertices,triangles=mesh.write(scratch/(name+'.bin'))
    row=dict(id=f'{z}/{x}/{y}',name=name,z=z,x=x,y=y,bounds=bounds,anchor=anchor,path=f'res://assets/settlements/{OUTPUT.name}/{name}.res',vertices=vertices,triangles=triangles,source_features=counts,source_z=9,refinement_source_z=[12,13])
    write(scratch/(name+'.json'),row);return row


def polygonal(geometry):
    geometry=shapely.make_valid(geometry)
    if geometry.geom_type=='GeometryCollection':
        faces=[]
        pending=list(geometry.geoms)
        while pending:
            part=pending.pop()
            if part.geom_type=='Polygon':faces.append(part)
            else:pending.extend(getattr(part,'geoms',[]))
        geometry=unary_union(faces)
    if geometry.geom_type not in ('Polygon','MultiPolygon'):
        return shapely.Polygon()
    return shapely.set_precision(geometry,.01)


def tessellate(mesh,geometry,height,depth=0):
    for polygon in shapely.get_parts(geometry):
        if polygon.geom_type in ['MultiPolygon','GeometryCollection']:
            tessellate(mesh,polygon,height,depth);continue
        if polygon.geom_type!='Polygon' or polygon.area<=1:continue
        try:
            mesh.polygon(polygon,height)
        except shapely.errors.GEOSException:
            if depth>=12:raise
            # GEOS may reject a valid multiply connected face. Partition its
            # interior and tessellate the exact clipped faces; holes and source
            # edges remain. These internal cuts have no rendered border.
            w,s,e,n=polygon.bounds
            if e-w>=n-s:
                middle=(w+e)/2;cells=[box(w,s,middle,n),box(middle,s,e,n)]
            else:
                middle=(s+n)/2;cells=[box(w,s,e,middle),box(w,middle,e,n)]
            for cell in cells:tessellate(mesh,polygon.intersection(cell),height,depth+1)


def roof_tile(data, bounds, area):
    wet=unary_union([g for _,g in data['water']])
    roofs=[g.intersection(area).difference(wet) for _,g in data['building']]
    grid=Affine((bounds[2]-bounds[0])/512,0,bounds[0],0,-(bounds[3]-bounds[1])/512,bounds[3])
    shapes=[(g,255) for g in roofs if not g.is_empty]
    image=rasterize(shapes,out_shape=(512,512),transform=grid,dtype='uint8') if shapes else np.zeros((512,512),dtype=np.uint8)
    return Image.fromarray(image),len(roofs)


def write_print(scratch,z,x,y,image,cities,count,output=None):
    name=f'buildings_{z}_{x}_{y}';image.save(scratch/(name+'.png'))
    bounds=tile_bounds(z,x,y);size=image.width
    row=dict(id=f'{z}/{x}/{y}',name=name,z=z,x=x,y=y,bounds=bounds,anchor=[(bounds[0]+bounds[2])/2,(bounds[1]+bounds[3])/2],path=f'res://assets/settlements/{(output or OUTPUT).name}/{name}.res',texture_source=name+'.png',vertices=4,triangles=2,resident_bytes=size*size*4//3+128,source_features={'building_geometry_groups':count},cities=cities,source_z=13)
    write(scratch/(name+'.json'),row);return row


def print_window_weight(z,x,y,size,windows):
    w,s,e,n=tile_bounds(z,x,y)
    px=w+(np.arange(size)+.5)*(e-w)/size
    py=n-(np.arange(size)+.5)*(n-s)/size
    weight=np.zeros((size,size),dtype=np.float32)
    for city in windows:
        lon,lat=city['anchor'];radius=city['radius_km']
        dx=(px-lon)*111.195*math.cos(math.radians(lat));dy=(py-lat)*111.195
        distance=np.hypot(dx[None,:],dy[:,None])
        feather=min(2.5,radius*.35) if city.get('detailed_print') else min(3,max(1,radius*.3))
        edge=np.clip((radius-distance)/feather,0,1)
        weight=np.maximum(weight,edge*edge*(3-2*edge))
    return weight


def fetch_detail_tile(session, url, limit):
    for attempt in range(3):
        try:
            with session.get(url,timeout=30,stream=True) as response:
                response.raise_for_status()
                payload=bytearray()
                for chunk in response.iter_content(65536):
                    if len(payload)+len(chunk)>limit:
                        raise ValueError('Detailed source byte budget exceeded')
                    payload.extend(chunk)
                return payload
        except requests.RequestException:
            if attempt==2:raise
            time.sleep(attempt+1)


def build_mainland_context(stage, bounds, budget):
    """Stage land cover and inland water for selected city surroundings."""
    global OWNER_MASK
    source=read(RAW/'tilejson.json')['tiles'][0]
    cache=RAW/'context_12'
    cache.mkdir(exist_ok=True)
    stage.mkdir(parents=True,exist_ok=True)
    def source_cells(window):
        west,south,east,north=window
        if not west<east or not south<north or not ENVELOPE.covers(box(west,south,east,north)):
            raise ValueError('Context bounds must be within continental coverage')
        first,last=tile_at(12,west,north),tile_at(12,east,south)
        return ((x,y) for x in range(first[0],last[0]+1) for y in range(first[1],last[1]+1))
    jobs={key for window in bounds for key in source_cells(window)}
    overview_parents={(x//16,y//16) for x,y in jobs}
    index_path=OUTPUT/'index.json'
    previous=read(index_path).get('surroundings',{}).get('windows',[]) if index_path.exists() else []
    # A rebuilt overview page includes the older windows sharing that page.
    for window in previous:
        jobs.update((x,y) for x,y in source_cells(window) if (x//16,y//16) in overview_parents)
    if len(jobs)>800:raise ValueError('Context source tile budget exceeded')
    groups={}
    areas=[]
    oceans=[]
    remaining=budget
    land_kinds={'wood':'woodland','farmland':'fields','grass':'grass'}
    profile = read(ROOT/'data/local/europe_settlement_context.json')
    pond_ids = set(profile.get('pond_ids', []))
    river_windows = [(box(*window['bounds']), set(window['names']))
                     for window in profile.get('river_stroke_windows', [])]
    with requests.Session() as session:
        session.headers['User-Agent']=AGENT+'-context'
        for x,y in sorted(jobs):
            path=cache/f'12-{x}-{y}.pbf'
            if not path.exists():
                payload=fetch_detail_tile(session,source.format(z=12,x=x,y=y),min(2*1024*1024,remaining))
                temporary=path.with_suffix('.tmp')
                temporary.write_bytes(payload)
                temporary.replace(path)
            remaining-=path.stat().st_size
            if remaining<0:raise ValueError('Context source byte budget exceeded')
            area=box(*tile_bounds(12,x,y))
            areas.append(area)
            river_scopes = [(scope, names) for scope, names in river_windows if scope.intersects(area)]
            layers = ['landcover', 'water', 'waterway'] if river_scopes else ['landcover', 'water']
            data=decode(path,12,x,y,layers)
            cell=groups.setdefault((x//4,y//4),{kind:[] for kind in ['fields','grass','woodland','water']})
            for props,geometry in data['landcover']:
                kind=land_kinds.get(props.get('class'))
                if kind:cell[kind].append(geometry.intersection(area))
            for props,geometry in data['water']:
                kind=props.get('class')
                if kind=='ocean':oceans.append(geometry.intersection(area))
                if kind in ('river','lake') or (kind == 'pond' and props.get('id') in pond_ids):
                    cell['water'].append(geometry.intersection(area))
            for props, line in data.get('waterway', []):
                for scope, names in river_scopes:
                    if props.get('class') == 'river' and props.get('name') in names:
                        # Draw a fixed-width stroke for rivers mapped only as a centreline.
                        metric = shapely.transform(line, TO_METRES, interleaved=False)
                        stroke = shapely.transform(metric.buffer(13, quad_segs=2), FROM_METRES, interleaved=False)
                        cell['water'].append(stroke.intersection(area).intersection(scope))
    OWNER_MASK=unary_union(areas).difference(unary_union(oceans))
    tiles={}
    districts={}
    overview={}
    for (x,y),cell in groups.items():
        district={kind:unary_union(features) for kind,features in cell.items()}
        districts[(x,y)]=district
        parent=overview.setdefault((x//4,y//4),{kind:[] for kind in cell})
        for kind,geometry in district.items():
            if not geometry.is_empty:parent[kind].append(geometry)
    broad={key:{kind:unary_union(features) for kind,features in cell.items()}
           for key,cell in overview.items()}
    for z,layer in [(10,districts),(8,broad)]:
        for (x,y),cell in sorted(layer.items()):
            row=write_context(stage,z,x,y,cell)
            if row is None:continue
            row.update(source_z=12,refinement_source_z=[])
            tiles[row['id']]=row
    source_record={'url':source,'source_z':12,'source_tiles':len(jobs),'bytes':budget-remaining,
                   'windows':bounds,'basis':'MODERN_REFERENCE_NOT_1900'}
    write(stage/'index.json',dict(schema='national_cartographic_context_v1',anchor=[15,50],tiles=tiles,
                                  surroundings=source_record))
    print('Context prepared',len(jobs),'source tiles',budget-remaining,'bytes',len(tiles),'pages',flush=True)


def build_detailed_prints(stage, city_ids=None, budget=RAW_BUDGET):
    """Update selected city prints without rebaking the national coverage."""
    selection=read(ROOT/f'data/local/{REGION}_city_reference_selection.json')
    cities=[city for city in selection['cities'] if city.get('detailed_print')]
    if REGION=='europe':
        cities=[city for city in cities if city.get('geography')=='mainland']
    if not cities:raise ValueError('No detailed city windows selected')
    by_id={city['id']:city for city in selection['cities']}
    detailed_ids={city['id'] for city in cities}
    if city_ids and city_ids-detailed_ids:
        raise ValueError(f'Unknown detailed windows: {sorted(city_ids-detailed_ids)}')
    RAW.mkdir(exist_ok=True)
    metadata_path=RAW/'tilejson.json'
    if not metadata_path.exists() and REGION=='europe':
        shared=ROOT.parent/'offline-map-sources/benelux_settlement_reference/tilejson.json'
        metadata_path.write_bytes(shared.read_bytes())
    source=read(metadata_path)['tiles'][0]
    stage.mkdir(parents=True,exist_ok=True)
    detail_cache=RAW/'detail_14'
    detail_cache.mkdir(exist_ok=True)
    scratch=RAW/'numeric'
    all_jobs={}
    for city in cities:
        lon,lat=city['anchor'];r=city['radius_km']
        dx=r/(111.195*math.cos(math.radians(lat)));dy=r/111.195
        first,last=tile_at(14,lon-dx,lat+dy),tile_at(14,lon+dx,lat-dy)
        for x in range(first[0],last[0]+1):
            for y in range(first[1],last[1]+1):
                all_jobs.setdefault((x,y),[]).append(city)
    # Regenerate the complete near coverage within changed overview parents.
    # This preserves adjacent detailed windows when their overview page is shared.
    parents={(x//4,y//4) for (x,y),windows in all_jobs.items()
             if not city_ids or any(city['id'] in city_ids for city in windows)}
    jobs={key:windows for key,windows in all_jobs.items()
          if (key[0]//4,key[1]//4) in parents}
    if len(jobs)>3000:raise ValueError('Detailed source tile budget exceeded')
    ign_cache = RAW/'ign_btn_14'
    ign_jobs = {
        key: [city for city in windows if city.get('roof_source') == 'ign_btn']
        for key, windows in jobs.items()
        if any(city.get('roof_source') == 'ign_btn' for city in windows)
    }
    if ign_jobs:
        ign_cache.mkdir(exist_ok=True)
    polygon_cities = {city['id']: city['roof_source'] for windows in jobs.values() for city in windows
                      if city.get('roof_source') in POLYGON_ROOF_CACHES}
    polygon_inputs = {}
    polygon_bytes = 0
    def web_tile_coordinates(lon, lat):
        return (lon+180)*(2**14/360), (1-np.arcsinh(np.tan(np.radians(lat)))/math.pi)*(2**13)
    for city_id, roof_source in sorted(polygon_cities.items()):
        path = RAW/POLYGON_ROOF_CACHES[roof_source]/f'{city_id}.geojson'
        document = read(path)
        polygons = [shape(feature['geometry']) for feature in document['features']]
        projected = shapely.transform(polygons, web_tile_coordinates, interleaved=False)
        polygon_inputs[city_id] = (shapely.STRtree(projected), document['source'])
        polygon_bytes += path.stat().st_size
    raw_bytes=sum(path.stat().st_size for x,y in jobs
                  if (path:=detail_cache/f'14-{x}-{y}.pbf').exists())
    raw_bytes += sum(path.stat().st_size for x, y in ign_jobs
                     if (path := ign_cache/f'14-{x}-{y}.pbf').exists())
    raw_bytes += polygon_bytes
    if raw_bytes>budget:raise ValueError('Detailed source byte budget exceeded')
    print('Detailed city windows',len(city_ids or detailed_ids),'tiles',len(jobs),'budget',budget,flush=True)
    index_path=OUTPUT/'index.json'
    if REGION=='europe' and not index_path.exists():
        index=dict(schema='national_cartographic_context_v1',anchor=[15.0,50.0],
                   bounds=list(ENVELOPE.bounds),tiles={},building_print=dict(
                       selection='res://data/local/europe_city_reference_selection.json',
                       levels=[12,14],basis=selection['geometry_basis']))
    else:
        index=read(index_path)
    tiles=index['tiles']
    staged={}
    size=256
    fine_size=128 if REGION=='europe' else 192
    overview_size=128 if REGION=='europe' else size
    land=source_mask() if REGION=='benelux' else None
    if land is not None:shapely.prepare(land)
    session=requests.Session()
    session.headers['User-Agent']=AGENT+'-detail'
    for number,((x,y),windows) in enumerate(sorted(jobs.items()),1):
        path=detail_cache/f'14-{x}-{y}.pbf'
        if not path.exists():
            remaining=min(2*1024*1024,budget-raw_bytes)
            if remaining<=0:raise ValueError('Detailed source byte budget exceeded')
            payload=fetch_detail_tile(session,source.format(z=14,x=x,y=y),remaining)
            temporary=path.with_suffix('.tmp')
            temporary.write_bytes(payload)
            temporary.replace(path)
            raw_bytes+=len(payload)
        tile=TileData(path.read_bytes(),default_options={'y_coord_down':True})
        for i in range(len(tile.tile.layers)-1,-1,-1):
            if tile.tile.layers[i].name not in ('building','transportation','water'):del tile.tile.layers[i]
        layers=tile.get_message()
        def raster(data, kinds, road=False):
            features=[(feature['geometry'],255) for feature in data.get('features',[])
                      if feature['geometry']['type'] in kinds and (not road or
                         feature['properties'].get('class') in ('primary','secondary','tertiary','minor','service') and
                         not feature['properties'].get('brunnel'))]
            return (rasterize(features,out_shape=(size,size),
                              transform=Affine.scale(data.get('extent',4096)/size),
                              dtype='uint8',all_touched=road) if features else np.zeros((size,size),dtype=np.uint8)),len(features)
        polygons = ('Polygon', 'MultiPolygon')
        roofs,count=raster(layers.get('building', {}),polygons)
        ign_count = 0
        if (x, y) in ign_jobs:
            path = ign_cache/f'14-{x}-{y}.pbf'
            if not path.exists():
                remaining = min(2*1024*1024, budget-raw_bytes)
                if remaining <= 0:
                    raise ValueError('Detailed source byte budget exceeded')
                payload = fetch_detail_tile(session, IGN_BTN_TILES.format(z=14, x=x, y=y), remaining)
                temporary = path.with_suffix('.tmp')
                temporary.write_bytes(payload)
                temporary.replace(path)
                raw_bytes += len(payload)
            ign_tile = TileData(path.read_bytes(), default_options={'y_coord_down': True})
            for layer_index in range(len(ign_tile.tile.layers)-1, -1, -1):
                if ign_tile.tile.layers[layer_index].name != 'btn0507s_edific':
                    del ign_tile.tile.layers[layer_index]
            official_roofs, ign_count = raster(ign_tile.get_message().get('btn0507s_edific', {}), polygons)
            weight = print_window_weight(14, x, y, size, ign_jobs[x, y])
            roofs = np.maximum(roofs, (official_roofs*weight).astype(np.uint8))
        supplemental_count = 0
        for city in windows:
            if city['id'] not in polygon_inputs:
                continue
            tree, _ = polygon_inputs[city['id']]
            candidates = tree.query(box(x, y, x+1, y+1), predicate='intersects')
            if not len(candidates):
                continue
            footprints = tree.geometries.take(candidates)
            supplement = rasterize([(geometry, 255) for geometry in footprints],
                                   out_shape=(size,size),
                                   transform=Affine.translation(x,y)*Affine.scale(1/size),
                                   dtype='uint8')
            weight = print_window_weight(14, x, y, size, [city])
            roofs = np.maximum(roofs, (supplement*weight).astype(np.uint8))
            supplemental_count += len(candidates)
        water,_=raster(layers.get('water', {}),polygons)
        roads,streets=raster(layers.get('transportation', {}),('LineString','MultiLineString'),True)
        roofs[water>0]=0
        roads[water>0]=0
        if land is not None:
            west,south,east,north=tile_bounds(14,x,y)
            if not land.covers(box(west,south,east,north)):
                tile_land=shapely.clip_by_rect(land,west,south,east,north)
                if tile_land.is_empty:
                    roofs.fill(0)
                    roads.fill(0)
                else:
                    transform=Affine((east-west)/size,0,west,0,(south-north)/size,north)
                    mask=rasterize([(tile_land,1)],out_shape=(size,size),transform=transform,dtype='uint8')
                    roofs[mask==0]=0
                    roads[mask==0]=0
        vicinity=Image.fromarray(roofs).filter(ImageFilter.MaxFilter(13)).filter(ImageFilter.GaussianBlur(3))
        roads=roads.astype(np.float32)*np.asarray(vicinity)/255.0
        # Bake the union of admitted windows into the coverage. Adjacent towns
        # can share a tile without a limited set of runtime clipping circles.
        key=f'14/{x}/{y}'
        legacy=[by_id[cid] for cid in tiles.get(key,{}).get('cities',[])
                if cid in by_id and not by_id[cid].get('detailed_print')]
        windows=windows+legacy
        weight=print_window_weight(14,x,y,size,windows)
        image=Image.fromarray(np.stack((roofs*weight,roads*weight,np.zeros_like(roofs)),axis=-1).astype(np.uint8))
        # The two-channel near page has to fit alongside neighbouring pages
        # at the normal 8 m/px view. Keep the filtered source coverage.
        image=image.resize((fine_size,fine_size),Image.Resampling.BOX)
        if image.getbbox():
            row=write_print(stage,14,x,y,image,[city['id'] for city in windows],count)
            row.update(street_print=True,window_baked=True,source_z=14,resident_bytes=2*fine_size*fine_size*4//3+128)
            row['source_features']['streets']=streets
            if ign_count:
                row['source_features']['ign_btn_buildings'] = ign_count
            if supplemental_count:
                row['source_features']['supplemental_buildings'] = supplemental_count
            tiles[key]=staged[key]=row
        else:
            tiles.pop(key,None)
        if number%25==0:print('Prepared',number,'/',len(jobs),'detail tiles',flush=True)
    session.close()
    for x,y in sorted(parents):
        roofs=Image.new('L',(size*4,size*4))
        roads=Image.new('L',roofs.size)
        overview_city_ids=set()
        for ox in range(4):
            for oy in range(4):
                row=tiles.get(f'14/{x*4+ox}/{y*4+oy}')
                if row is None:continue
                origin=(ox*size,oy*size)
                if row['id'] in staged:
                    with Image.open(stage/row['texture_source']) as image:
                        tile=image.resize((size,size),Image.Resampling.BILINEAR)
                        roofs.paste(tile.getchannel('R'),origin)
                        roads.paste(tile.getchannel('G'),origin)
                else:
                    legacy=[by_id[cid] for cid in row['cities']
                            if cid in by_id and not by_id[cid].get('detailed_print')]
                    if not legacy:continue
                    with Image.open(scratch/row['texture_source']) as image:
                        mask=print_window_weight(14,x*4+ox,y*4+oy,size,legacy)
                        roofs.paste(Image.fromarray((np.asarray(image)*mask).astype(np.uint8)),origin)
                overview_city_ids.update(row['cities'])
        key=f'12/{x}/{y}'
        if not roofs.getbbox():
            tiles.pop(key,None)
            continue
        dimensions=(overview_size,overview_size)
        image=Image.merge('RGB',(roofs.resize(dimensions,Image.Resampling.LANCZOS),
                                 roads.resize(dimensions,Image.Resampling.LANCZOS),Image.new('L',dimensions)))
        row=write_print(stage,12,x,y,image,sorted(overview_city_ids),0)
        row.update(street_print=True,window_baked=True,source_z=14,resident_bytes=2*overview_size*overview_size*4//3+128)
        tiles[key]=staged[key]=row
    index['building_print']['cities']=selection['cities']
    previous=index['building_print'].get('detailed_source',{})
    installed_ids=set(previous.get('cities',[]))|(city_ids or detailed_ids)
    index['building_print']['detailed_source']={'url':source,'source_z':14,'last_build_bytes':raw_bytes,'near_mask_size':fine_size,
                                                  'overview_mask_size':overview_size,'cities':sorted(installed_ids)}
    if ign_jobs:
        index['building_print']['supplemental_roof_source'] = {
            'url': IGN_BTN_TILES, 'publisher': 'Instituto Geográfico Nacional de España',
            'attribution': 'Obra derivada de BTN · CC BY 4.0 · ign.es', 'source_z': 14,
        }
    if polygon_inputs:
        sources = index['building_print'].setdefault('polygon_roof_sources', {})
        sources.update(index['building_print'].pop('gba_roof_sources', {}))
        sources.update({city_id: source for city_id, (_, source) in polygon_inputs.items()})
    write(stage/'index.json',{'schema':index['schema'],'anchor':index['anchor'],'tiles':staged})
    write(stage/'installed-index.json',index)
    print('Detailed prints staged',len(jobs),'source tiles',raw_bytes,'bytes',flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--acquire-only',action='store_true',help='Fill the bounded raw cache without rewriting derivatives.')
    parser.add_argument('--region',choices=['benelux','germany','iberia','europe'],default='benelux',help='Selected geographic source recipe; shared renderer and bounded input cache.')
    parser.add_argument('--recolor-water',action='store_true',help='Recolour existing numeric meshes from admitted sea proximity; preserve geometry.')
    parser.add_argument('--rebuild',action='store_true',help='Regenerate numeric derivatives from the cached source.')
    parser.add_argument('--reuse-district',action='store_true',help='Resume remaining overview cells after a complete district pass with the same inputs.')
    parser.add_argument('--detail-stage',type=Path,help='Stage selected z14 city roofs and streets without rebuilding national context.')
    parser.add_argument('--detail-cities',help='Comma-separated detailed window IDs to rebuild.')
    parser.add_argument('--detail-budget-mb',type=int,default=50,help='Maximum raw input MB for the selected detail rebuild.')
    parser.add_argument('--context-stage',type=Path,help='Stage continental land cover and inland water.')
    parser.add_argument('--context-bounds',action='append',type=float,nargs=4,metavar=('WEST','SOUTH','EAST','NORTH'))
    args=parser.parse_args()
    configure(args.region)
    if args.context_stage:
        if args.region!='europe' or not args.context_bounds or args.detail_budget_mb<=0:
            parser.error('Context staging requires Europe, at least one bounding window and a positive byte budget')
        build_mainland_context(args.context_stage,args.context_bounds,args.detail_budget_mb*1_000_000)
    elif args.region=='europe' and not args.detail_stage:
        parser.error('The European city layer requires --detail-stage')
    elif args.detail_stage:
        if args.detail_budget_mb<=0:parser.error('--detail-budget-mb must be positive')
        build_detailed_prints(args.detail_stage,set(args.detail_cities.split(',')) if args.detail_cities else None,
                              args.detail_budget_mb*1_000_000)
    elif args.recolor_water:recolor_water()
    else:build(args.acquire_only,args.rebuild,args.reuse_district)
