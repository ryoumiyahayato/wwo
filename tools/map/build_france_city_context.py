"""Bounded French city and rural map prints.

IGN Plan modern footprints, not a historical city reconstruction. Single-worker
offline rasterisation avoids millions of resident roof triangles. Raw PBF and
numeric masks stay outside res://; the existing native mesh writer embeds the
mipmapped masks. Selected rural windows include modern street linework for display.
"""
import argparse
import math
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import date
from pathlib import Path
from threading import Lock
import numpy as np
from mapbox_vector_tile.decoder import TileData
from PIL import Image, ImageFilter
from rasterio.features import rasterize
from affine import Affine
from build_france_settlement_context import ROOT, tile_at, tile_bounds, read, write

RAW = ROOT.parent/'offline-map-sources/france_major_city_reference'
OUTPUT = ROOT/'assets/settlements/france_context'
SIZE = 512
FINE_SIZE = 256
STREET_SIZE = 192


def build(city_ids=None, stage=None):
    RAW.mkdir(exist_ok=True)
    scratch=RAW/'numeric';scratch.mkdir(exist_ok=True)
    selection=read(ROOT/'data/local/france_major_cities_1901.json')
    street_cities={city['id'] for city in selection['cities'] if city.get('street_print')}
    requested=set(city_ids or [])
    cities_to_build=[city for city in selection['cities'] if not requested or city['id'] in requested]
    unknown=requested-{city['id'] for city in cities_to_build}
    if unknown:raise ValueError(f'Unknown cities: {sorted(unknown)}')
    jobs={}
    for city in cities_to_build:
        lon,lat=city['anchor'];r=city['radius_km']
        dx=r/(111.195*math.cos(math.radians(lat)));dy=r/111.195
        a,b=tile_at(14,lon-dx,lat+dy),tile_at(14,lon+dx,lat-dy)
        for x in range(a[0],b[0]+1):
            for y in range(a[1],b[1]+1):jobs.setdefault((x,y),[]).append(city['id'])
    print('Major-city source tiles',len(jobs),'cities',len(cities_to_build),flush=True)
    index=read(OUTPUT/'index.json')
    tiles={k:v for k,v in index['tiles'].items() if v.get('texture_source')} if requested else {}
    parents=set()
    raw_sources=(RAW/f'14-{x}-{y}.pbf' for x,y in jobs) if requested else RAW.glob('*.pbf')
    raw_bytes=sum(path.stat().st_size for path in raw_sources if path.is_file())
    raw_lock=Lock()
    # Only bounded network waits overlap. Rasterisation stays on one CPU
    # worker, and the native preview remains stopped during production.
    def download(coordinate):
        nonlocal raw_bytes
        x,y=coordinate
        source=RAW/f'14-{x}-{y}.pbf'
        if source.exists():return source
        for attempt in range(3):
            try:
                request=urllib.request.Request(f'https://data.geopf.fr/tms/1.0.0/PLAN.IGN/14/{x}/{y}.pbf',headers={'User-Agent':'WWO bounded offline cartographic reference'})
                with urllib.request.urlopen(request,timeout=40) as response:data=response.read(2*1024*1024+1)
                if len(data)>2*1024*1024:raise ValueError('Source tile exceeds 2MiB')
                with raw_lock:
                    if raw_bytes+len(data)>256*1024*1024:raise ValueError('Major-city raw PBF exceeds 256MiB budget')
                    temporary=source.with_suffix('.tmp')
                    temporary.write_bytes(data)
                    temporary.replace(source)
                    raw_bytes+=len(data)
                return source
            except OSError:
                if attempt==2:raise
                time.sleep(1+attempt)
    network=ThreadPoolExecutor(max_workers=3)
    ordered=sorted(jobs.items())
    downloads=network.map(download,[key for key,_ in ordered])
    for i,(((x,y),cities),source) in enumerate(zip(ordered,downloads)):
        name=f'buildings_14_{x}_{y}';meta=scratch/(name+'.json')
        parents.add((x//4,y//4))
        previous=read(meta) if meta.exists() else {}
        if requested: cities=sorted(set(previous.get('cities',[]))|set(cities))
        street_print=bool(street_cities.intersection(cities))
        if (previous and (scratch/(name+'.png')).exists()
                and previous.get('street_print',False)==street_print
                and (not street_print or previous.get('recipe_version')==4)):
            if previous.get('recipe_version')==1:
                image=Image.open(scratch/(name+'.png'))
                image.resize((FINE_SIZE,FINE_SIZE),Image.Resampling.LANCZOS).save(scratch/(name+'.png'))
                previous.update(recipe_version=2,resident_bytes=FINE_SIZE*FINE_SIZE*4//3+128)
                write(meta,previous)
            previous['cities']=cities
            tiles[f'14/{x}/{y}']=previous;continue
        tile=TileData(source.read_bytes(),default_options={'y_coord_down':True})
        layers={'bati_surf','routier_route'} if street_print else {'bati_surf'}
        for layer_index in range(len(tile.tile.layers)-1,-1,-1):
            if tile.tile.layers[layer_index].name not in layers:del tile.tile.layers[layer_index]
        decoded=tile.get_message()
        layer=decoded.get('bati_surf',{})
        extent=layer.get('extent',4096)
        # Actual roof/hangar outlines only; electricity facilities and towers
        # are not enlarged into occupied building blocks.
        features=[f for f in layer.get('features',[]) if f['properties'].get('territoire')=='FXX' and f['properties'].get('symbo') in ('BATI_QQUE','BATI_INDUSTRIEL','BATI_REMARQUABLE','HANGAR','SERRE') and f['geometry']['type'] in ('Polygon','MultiPolygon')]
        image=rasterize([(f['geometry'],255) for f in features],out_shape=(FINE_SIZE,FINE_SIZE),transform=Affine(extent/FINE_SIZE,0,0,0,extent/FINE_SIZE,0),dtype='uint8') if features else np.zeros((FINE_SIZE,FINE_SIZE),dtype=np.uint8)
        if street_print:
            streets=decoded.get('routier_route',{})
            street_shapes=[(feature['geometry'],255) for feature in streets.get('features',[])
                           if feature['properties'].get('territoire')=='FXX'
                           and not feature['properties'].get('fictif')
                           and 'AUTOROUTE' not in feature['properties'].get('symbo','')
                           and feature['geometry']['type'] in ('LineString','MultiLineString')]
            street_step=streets.get('extent',4096)/FINE_SIZE
            street_mask=rasterize(street_shapes,out_shape=image.shape,transform=Affine.scale(street_step),dtype='uint8',all_touched=True) if street_shapes else np.zeros_like(image)
            # Show local street structure around mapped roofs. Leave the
            # through-network to its independent map layer.
            vicinity=Image.fromarray(image).filter(ImageFilter.MaxFilter(17)).filter(ImageFilter.GaussianBlur(3))
            street_mask=(street_mask.astype(np.uint16)*np.asarray(vicinity)//255).astype(np.uint8)
            image=np.stack((image,street_mask,np.zeros_like(image)),axis=-1)
        texture=Image.fromarray(image)
        if street_print:texture=texture.resize((STREET_SIZE,STREET_SIZE),Image.Resampling.BOX)
        texture.save(scratch/(name+'.png'))
        bounds=tile_bounds(14,x,y)
        row=dict(id=f'14/{x}/{y}',name=name,z=14,x=x,y=y,bounds=bounds,anchor=[(bounds[0]+bounds[2])/2,(bounds[1]+bounds[3])/2],path=f'res://assets/settlements/france_context/{name}.res',texture_source=name+'.png',vertices=4,triangles=2,resident_bytes=FINE_SIZE*FINE_SIZE*4//3+128,source_features={'buildings':len(features)},cities=cities,recipe_version=2)
        if street_print:
            row.update(street_print=True,recipe_version=4,resident_bytes=2*STREET_SIZE*STREET_SIZE*4//3+128)
            row['source_features']['streets']=len(street_shapes)
        write(meta,row);tiles[row['id']]=row
        if (i+1)%20==0:print('Acquired',i+1,'/',len(jobs),flush=True)
    network.shutdown()
    # The coarser print is a filtered view of exactly the same roof masks.
    # Missing child tiles stay empty; neither a street nor a roof is invented.
    for x,y in sorted(parents):
        canvas=Image.new('L',(SIZE*4,SIZE*4))
        street_canvas=None
        cities=set();features=0;streets=0
        for ox in range(4):
            for oy in range(4):
                child=tiles.get(f'14/{x*4+ox}/{y*4+oy}')
                if not child:continue
                with Image.open(scratch/child['texture_source']) as source:
                    image=source.resize((SIZE,SIZE),Image.Resampling.NEAREST)
                origin=(ox*SIZE,oy*SIZE)
                canvas.paste(image.getchannel('R') if child.get('street_print') else image,origin)
                if child.get('street_print'):
                    if street_canvas is None: street_canvas=Image.new('L',canvas.size)
                    street_canvas.paste(image.getchannel('G'),origin)
                    streets+=child['source_features']['streets']
                cities.update(child['cities']);features+=child['source_features']['buildings']
        name=f'buildings_12_{x}_{y}'
        # Large metro windows use the same bounded overview resolution.
        # Close view still uses the original z14 masks.
        size=256 if cities.intersection({'paris','lille','lyon'}|street_cities) else SIZE
        roof=canvas.resize((size,size),Image.Resampling.LANCZOS)
        if street_canvas is not None:
            streets_print=street_canvas.resize((size,size),Image.Resampling.LANCZOS)
            roof=Image.merge('RGB',(roof,streets_print,Image.new('L',roof.size)))
        roof.save(scratch/(name+'.png'))
        bounds=tile_bounds(12,x,y)
        row=dict(id=f'12/{x}/{y}',name=name,z=12,x=x,y=y,bounds=bounds,anchor=[(bounds[0]+bounds[2])/2,(bounds[1]+bounds[3])/2],path=f'res://assets/settlements/france_context/{name}.res',texture_source=name+'.png',vertices=4,triangles=2,resident_bytes=size*size*4//3+128,source_features={'buildings':features},cities=sorted(cities),recipe_version=1)
        if street_canvas is not None:
            row.update(street_print=True,resident_bytes=2*size*size*4//3+128)
            row['source_features']['streets']=streets
        write(scratch/(name+'.json'),row);tiles[row['id']]=row
    index['tiles']={k:v for k,v in index['tiles'].items() if not v.get('texture_source')}
    index['tiles'].update(tiles)
    index['building_print']={'selection':'res://data/local/france_major_cities_1901.json','cities':selection['cities'],'levels':[12,14],'mask_size':{'12':SIZE,'14':FINE_SIZE,'metro_12':256},'basis':selection['geometry_basis'],'source':'https://data.geopf.fr/tms/1.0.0/PLAN.IGN','license':'Etalab-Open-Licence-2.0','raw_budget_mib':256,'source_features':sum(t['source_features']['buildings'] for t in tiles.values() if t['z']==14)}
    index['building_print']['mask_size']['street_14']=STREET_SIZE
    if stage:
        stage.mkdir(parents=True,exist_ok=True)
        changed={f'14/{x}/{y}' for x,y in jobs}|{f'12/{x}/{y}' for x,y in parents}
        write(stage/'index.json',{'schema':index['schema'],'anchor':index['anchor'],'tiles':{key:tiles[key] for key in sorted(changed)}})
        write(stage/'installed-index.json',index)
    else:
        write(OUTPUT/'index.json',index)
        write(RAW/'source.json',index['building_print']|{'raw_bytes':raw_bytes,'prepared_tiles':len(tiles),'retrieved_on':date.today().isoformat()})
    print('Building prints ready',len(tiles),'tiles',index['building_print']['source_features'],'source appearances',flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--city',action='append',help='Refresh a selected city without discarding the other prints; repeat for multiple cities')
    parser.add_argument('--detail-stage',type=Path,help='Stage affected native inputs and the replacement index separately')
    args=parser.parse_args()
    build(args.city,args.detail_stage)
