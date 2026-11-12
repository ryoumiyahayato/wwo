"""Offline mainland settlement context, not a 1900 reconstruction.

Uses IGN Plan vector tiles under Open Licence 2.0. Raw PBF stays outside res://.
Two geographic levels retain sourced built-up/industrial/woodland polygons.
No random houses, field boundaries, firms, inventory or transport capacity.
Uses the existing city numeric mesh and native resource producer.
"""
import argparse
import json
import math
import shutil
import struct
import subprocess
import time
import urllib.request
import uuid
import zlib
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import numpy as np
import shapely
from shapely.geometry import shape, box
from shapely.ops import transform, unary_union
import mapbox_vector_tile
from build_city_miniature import Mesh

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT.parent/'offline-map-sources/france_mainland_reference'
OUTPUT = ROOT/'assets/settlements/france_context'
URL = 'https://data.geopf.fr/tms/1.0.0/PLAN.IGN/{z}/{x}/{y}.pbf'
SOURCE = dict(publisher='© IGN', url='https://www.data.gouv.fr/datasets/plan-ign',
              service='https://data.geopf.fr/tms/1.0.0/PLAN.IGN', license='Etalab-Open-Licence-2.0',
              basis='MODERN_GENERALISED_REFERENCE_NOT_1900_BUILDINGS_OR_INDUSTRY', retrieved_on='2026-11-07')


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, separators=(',', ':'))+'\n', encoding='utf-8')


def build_overview(godot):
    """Bake the existing district coverage into the regional map's mipmapped tiles."""
    from PIL import Image, ImageDraw

    index_path = OUTPUT/'index.json'
    index = read(index_path)
    districts = {}
    for tile in index['tiles'].values():
        if tile['z'] == 10:
            districts.setdefault((tile['x']//4, tile['y']//4), []).append(tile)

    size, samples = 128, 1024
    overview = {}
    work = (ROOT/'local-artifacts').resolve()
    staging = (work/f'france-overview-{uuid.uuid4().hex}').resolve()
    if staging.parent != work or not staging.is_relative_to(ROOT):
        raise ValueError('Overview staging directory must be inside the project')
    staging.mkdir()
    try:
        for (x, y), children in sorted(districts.items()):
            bounds = tile_bounds(8, x, y)
            west, south, east, north = bounds
            urban = Image.new('L', (samples, samples))
            woodland = Image.new('L', (samples, samples))
            draws = (ImageDraw.Draw(urban), ImageDraw.Draw(woodland))
            counts = Counter()
            for tile in children:
                path = RAW/'numeric'/(tile['name']+'.bin')
                source = path.read_bytes()
                count, elements = struct.unpack_from('<II', source, 8)
                if source[:8] != b'CITYMSH2' or (count, elements) != (tile['vertices'], tile['triangles']*3):
                    raise ValueError(f'District mesh differs from installed catalogue: {path}')
                positions = np.frombuffer(source, '<f4', count*3, 16).reshape(-1, 3).astype('float64')
                faces = np.frombuffer(source, '<u4', elements, 16+count*12).reshape(-1, 3)
                colors = np.frombuffer(source, '<f4', count*4, 16+count*12+elements*4).reshape(-1, 4)
                lon, lat = tile['anchor']
                px = (lon-west+positions[:, 0]/(111195*math.cos(math.radians(lat))))*(samples/(east-west))
                py = (north-lat+positions[:, 2]/111195)*(samples/(north-south))
                points = list(zip(px, py))
                is_woodland = (colors[:, 1]>colors[:, 0]+.035) & (colors[:, 1]>colors[:, 2]+.035)
                for a, b, c in faces:
                    draws[int(is_woodland[a])].polygon((points[a], points[b], points[c]), fill=255)
                counts.update(tile['source_features'])
            if not urban.getbbox() and not woodland.getbbox():
                continue
            name = f'context_8_{x}_{y}'
            texture = name+'.png'
            Image.merge('RGB', (
                urban.resize((size, size), Image.Resampling.BOX),
                woodland.resize((size, size), Image.Resampling.BOX),
                Image.new('L', (size, size)),
            )).save(staging/texture)
            tile_id = f'8/{x}/{y}'
            overview[tile_id] = dict(
                id=tile_id, name=name, z=8, x=x, y=y, bounds=bounds,
                anchor=[(west+east)/2, (south+north)/2],
                path=f'res://assets/settlements/france_context/{name}.res',
                vertices=4, triangles=2, texture_source=texture, woodland_mask=True,
                resident_bytes=2*size*size*4//3+128, source_features=dict(counts),
            )
        staging_index = staging/'index.json'
        write(staging_index, dict(schema=index['schema'], anchor=index['anchor'], tiles=overview))
        subprocess.run([godot, '--headless', '--path', str(ROOT), '--log-file', str(staging/'convert.log'), '--script',
                        'res://tools/map/save_city_meshes.gd', '--', str(staging), str(staging)], check=True)
        for tile in overview.values():
            (staging/(tile['name']+'.res')).replace(ROOT/tile['path'][6:])
        index['tiles'].update(overview)
        index['levels'][0] = dict(z=8, role='overview', mask_size=size, source_z=10,
                                  method='Area-reduced built-up/industrial and woodland coverage from installed IGN district meshes')
        write(staging_index, index)
        staging_index.replace(index_path)
    finally:
        shutil.rmtree(staging)
    print('Baked', len(overview), 'regional settlement coverage tiles', flush=True)


def tile_bounds(z, x, y):
    n = 2**z
    latitude = lambda p: math.degrees(math.atan(math.sinh(math.pi*(1-2*p/n))))
    return [x/n*360-180, latitude(y+1), (x+1)/n*360-180, latitude(y)]


def tile_at(z, lon, lat):
    return int((lon+180)/360*2**z), int((1-math.asinh(math.tan(math.radians(lat)))/math.pi)/2*2**z)


def source_mask():
    # Geographic acquisition envelope only. Each accepted feature must carry
    # IGN's FXX source territory below; this does not assign 1900 sovereignty.
    mainland = box(-5.2,42.25,8.3,51.15)
    # Follow the currently installed physical coast, including the finite
    # Seine-mouth correction. New reference geometry cannot paint the sea.
    physical = []
    index = read(ROOT/'data/strategic/index.json')
    for parent in index['coast_regions']:
        for row in parent['medium_regions']:
            b = row['bounds']
            if not box(b[0],b[2],b[1],b[3]).intersects(mainland):
                continue
            document = read(ROOT/row['path'].replace('res://',''))
            record = next(f['value'] for f in document['evidence_catalog']['facts'] if f['value']['kind']=='land_reference')
            asset = ROOT/record['geometry_asset']['path'].replace('res://','')
            geometry = json.loads(zlib.decompress(asset.read_bytes()))
            physical.append(shape(geometry['land_reference:'+row['id']]['geometry']))
    pieces=shapely.get_parts(shapely.make_valid(mainland.intersection(unary_union(physical))))
    mainland=max((p for p in pieces if p.geom_type=='Polygon'),key=lambda p:p.area)
    # IGN's FXX cartographic layer also includes foreign built-up reference.
    # The installed Benelux derivative owns its admitted three-country scope;
    # remove duplicate display there, not a rectangular border or sovereignty.
    for region in ['benelux']:
        installed=ROOT/f'assets/settlements/{region}_context/index.json'
        if not installed.exists():continue
        admitted=read(installed).get('coverage',{}).get('geometry')
        if not admitted:raise ValueError('Installed source must declare its geographic handoff: '+region)
        mainland=mainland.difference(shape(admitted))
    return mainland


def build(args):
    RAW.mkdir(exist_ok=True)
    scratch = RAW/'numeric';scratch.mkdir(exist_ok=True)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    mask = source_mask()
    settlement_handoff=[]
    for region in ['germany','iberian']:
        installed=ROOT/f'assets/settlements/{region}_context/index.json'
        if installed.exists():
            settlement_handoff.append(shape(read(installed)['coverage']['geometry']))
    settlement_handoff=unary_union(settlement_handoff)
    window=box(*map(float,args.window.split(','))) if args.window else None
    jobs = []
    for z in (8,10):
        west,south,east,north = mask.bounds
        a,b = tile_at(z,west,north),tile_at(z,east,south)
        for x in range(a[0],b[0]+1):
            for y in range(a[1],b[1]+1):
                bounds = tile_bounds(z,x,y)
                if box(*bounds).intersects(mask if window is None else window): jobs.append((z,x,y,bounds))
    print('Source tiles',dict(Counter(job[0] for job in jobs)),flush=True)
    styles = {'woodland':(.37,.44,.32,.16),'urban':(.46,.44,.38,.54),'industrial':(.39,.42,.40,.46)}

    def one(job):
        z,x,y,bounds = job
        name = f'context_{z}_{x}_{y}'
        source_path = RAW/f'{z}-{x}-{y}.pbf'
        output_meta = scratch/(name+'.json')
        if output_meta.exists() and (scratch/(name+'.bin')).exists() and not args.rebuild:
            previous=read(output_meta)
            if previous.get('recipe_version')==2:return previous
        if not source_path.exists():
            for attempt in range(3):
                try:
                    req = urllib.request.Request(URL.format(z=z,x=x,y=y),headers={'User-Agent':'WWO offline geographic reference'})
                    with urllib.request.urlopen(req,timeout=40) as response: data=response.read(2*1024*1024+1)
                    if len(data)>2*1024*1024: raise ValueError('Source tile exceeds 2MiB budget')
                    mapbox_vector_tile.decode(data,default_options={'y_coord_down':True})
                    source_path.write_bytes(data);break
                except OSError:
                    if attempt==2: raise
                    time.sleep(1+attempt)
        decoded = mapbox_vector_tile.decode(source_path.read_bytes(),default_options={'y_coord_down':True})
        area = box(*bounds).intersection(mask)
        urban_area=area.difference(settlement_handoff)
        anchor = [(bounds[0]+bounds[2])/2,(bounds[1]+bounds[3])/2]
        sx,sy = 111195*math.cos(math.radians(anchor[1])),111195.
        def local(lon,lat,z=None): return (np.asarray(lon)-anchor[0])*sx,(np.asarray(lat)-anchor[1])*sy
        groups = {'woodland':[],'urban':[],'industrial':[]}
        references = Counter()
        for layer_name in ('bati_zone_surf','ocs_vegetation_surf'):
            layer = decoded.get(layer_name,{})
            extent = int(layer.get('extent',4096))
            def geographic(px,py,pz=None):
                gx=(x+np.asarray(px)/extent)/2**z
                gy=(y+np.asarray(py)/extent)/2**z
                return gx*360-180,np.degrees(np.arctan(np.sinh(math.pi*(1-2*gy))))
            for feature in layer.get('features',[]):
                if feature['properties'].get('territoire')!='FXX': continue
                symbol = feature['properties'].get('symbo')
                category = {'ZONE_BATI':'urban','ZONE_INDUS_ACTI':'industrial','ZONE_BOISEE':'woodland'}.get(symbol)
                if category is None: continue
                original = transform(geographic,shape(feature['geometry']))
                geometry = shapely.make_valid(original).intersection(area if category=='woodland' else urban_area)
                if geometry.is_empty: continue
                groups[category].append(transform(local,geometry))
                references[category]+=1
        mesh = Mesh()
        for rank,(category,geometries) in enumerate(groups.items()):
            if not geometries: continue
            geometry = unary_union(geometries).simplify(45.0 if z==8 else 8.0,preserve_topology=True)
            start = len(mesh.positions[0])//3
            mesh.geometry(geometry,.25+rank*.08)
            mesh.colors[0].extend(list(styles[category])*(len(mesh.positions[0])//3-start))
        vertices,triangles = mesh.write(scratch/(name+'.bin'))
        row = dict(recipe_version=2,id=f'{z}/{x}/{y}',name=name,z=z,x=x,y=y,bounds=bounds,anchor=anchor,
                   path='res://assets/settlements/france_context/'+name+'.res',vertices=vertices,triangles=triangles,
                   source_features=dict(references),source_bytes=source_path.stat().st_size)
        write(output_meta,row)
        return row

    rows = []
    with ThreadPoolExecutor(max_workers=1) as pool:
        for i,row in enumerate(pool.map(one,jobs)):
            rows.append(row)
            if (i+1)%25==0:print('Prepared',i+1,'/',len(jobs),flush=True)
    raw_bytes=sum(p.stat().st_size for p in RAW.glob('*.pbf'))
    if raw_bytes>512*1024*1024:raise ValueError('Raw PBF exceeds declared 512MiB budget')
    index = dict(schema='national_cartographic_context_v1',anchor=[2.5,46.5],bounds=list(mask.bounds),
        levels=[dict(z=8,role='overview',simplification_m=45),dict(z=10,role='district',simplification_m=8)],
        tiles={r['id']:r for r in rows if r['triangles']>0},sources=[SOURCE],
        coverage=dict(scope='IGN FXX modern geographic source, on the continental component of installed physical land inside the finite mainland-France acquisition envelope; Corsica and overseas excluded. Historical sovereignty is unchanged.',
                      requested_tiles=len(jobs),prepared_tiles=len(rows),raw_bytes=raw_bytes),
        limits=['Modern generalised built-up and woodland reference, not 1900 extent or individual buildings.',
                'Woodland/open ground is not a farm, ownership, yield or economic production statement.',
                'No artificial streets, random houses, population, industry output or transport capacity.'])
    # The bounded major-city print is a separate derivative of its declared
    # inputs. Updating the generalised national layer must not drop it.
    if (OUTPUT/'index.json').exists():
        previous=read(OUTPUT/'index.json')
        if window is not None:
            index['tiles']=dict(previous['tiles'])
            for row in rows:
                index['tiles'].pop(row['id'],None)
                if row['triangles']>0:index['tiles'][row['id']]=row
            index['coverage']=previous['coverage']|dict(geographic_handoff='Installed adjoining source footprints; German and Iberian sources take over built-up and industrial ink only. Display only, not sovereignty.',last_rebuilt_window=list(window.bounds),last_rebuilt_tiles=len(rows))
            selected=RAW/args.window_output;selected.mkdir(exist_ok=True)
            for row in rows:shutil.copyfile(scratch/(row['name']+'.bin'),selected/(row['name']+'.bin'))
        if 'building_print' in previous:
            index['building_print']=previous['building_print']
            index['tiles'].update({k:v for k,v in previous['tiles'].items() if v.get('texture_source')})
    write(OUTPUT/'index.json',index)
    write(RAW/'source.json',dict(sources=[SOURCE],coverage=index['coverage'],tile_levels=[8,10],outputs=str(OUTPUT),
        numeric_bytes=sum(p.stat().st_size for p in scratch.glob('*.bin'))))
    print('Prepared mainland context',len(index['tiles']),'meshes',raw_bytes,'raw bytes',flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--overview-from-districts', metavar='GODOT', help='Bake regional coverage from cached district meshes with the existing Godot converter.')
    parser.add_argument('--rebuild',action='store_true',help='Explicitly regenerate numeric derivatives; raw cache remains.')
    parser.add_argument('--window',help='Only regenerate west,south,east,north and merge into the installed index.')
    parser.add_argument('--window-output',choices=['benelux_handoff_numeric','iberian_handoff_numeric','germany_handoff_numeric'],default='benelux_handoff_numeric',help='Select the bounded numeric output directory for a window rebuild.')
    args = parser.parse_args()
    if args.overview_from_districts:
        build_overview(args.overview_from_districts)
    else:
        build(args)
