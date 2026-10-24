"""British/Irish geographic material using R42's COG, DEM and mip packer.

No political input. Modern land cover is a display reference, not 1900 facts.
Run with the R42 offline environment plus shapely: python tools/map/build_british_surface_r43.py
"""
from pathlib import Path
import sys, json, math, concurrent.futures as futures
import numpy as np
import build_france_surface_r42 as shared
import rasterio
from rasterio.warp import reproject
from rasterio.enums import Resampling
from rasterio.features import rasterize
from rasterio.transform import from_bounds
from scipy.ndimage import map_coordinates
from shapely.geometry import shape, box, mapping, Polygon
from shapely.ops import unary_union
from PIL import Image
import requests
import xml.etree.ElementTree as ET

ROOT=shared.ROOT
WORK=ROOT/'local-artifacts/british-surface-r43'
BOUNDS=(-12.,48.,4.,62.)
STEP=shared.STEP
SHAPE=(7168,8192)
TRANSFORM=from_bounds(*BOUNDS,SHAPE[1],SHAPE[0])
shared.RESEARCH=WORK
shared.BOUNDS=BOUNDS
# Shading/packing stay shared. Only the acquired geographic domain changes.
shared.support=lambda lon,lat: np.ones(np.broadcast_shapes(np.shape(lon),np.shape(lat)),dtype='float32')


def islands():
    data=json.loads((ROOT/'local-artifacts/paris-land-pilot-r1/research/ne_10m_land_v512.geojson').read_text(encoding='utf8'))
    result=[]
    for feature in data['features']:
        g=shape(feature['geometry'])
        for part in list(g.geoms) if hasattr(g,'geoms') else [g]:
            w,s,e,n=part.bounds
            if w>=-12 and e<=4 and s>=49.7 and n<=62:
                result.append(part)
    result.sort(key=lambda g:g.area,reverse=True)
    return result,unary_union(result).buffer(.15)


def acquire(domain):
    WORK.mkdir(parents=True,exist_ok=True)
    listing=WORK/'copdem_tileList.txt'
    if not listing.exists():
        # Reuse the already retrieved provider list, not a global redownload.
        previous=ROOT/'local-artifacts/france-surface-r42/copdem_tileList.txt'
        if previous.exists(): listing.write_bytes(previous.read_bytes())
        else:
            response=requests.get(shared.DEM_ROOT+'/tileList.txt',timeout=90)
            response.raise_for_status(); listing.write_bytes(response.content)
    known=listing.read_text(encoding='utf8')
    wc_listing=WORK/'worldcover_british_keys.txt'
    if not wc_listing.exists():
        keys=[]
        for lat in range(48,63,3):
            response=requests.get('https://esa-worldcover.s3.eu-central-1.amazonaws.com',params={
                'list-type':'2','prefix':f'v200/2021/map/ESA_WorldCover_10m_2021_v200_N{lat:02d}',
                'max-keys':'1000'},timeout=90)
            response.raise_for_status()
            xml=ET.fromstring(response.content)
            if any(v.text=='true' for v in xml.iter() if v.tag.endswith('}IsTruncated')):
                raise ValueError('Provider cover listing truncated')
            keys.extend(v.text for v in xml.iter() if v.tag.endswith('}Key'))
        wc_listing.write_text('\n'.join(keys),encoding='utf8')
    cover_known=wc_listing.read_text(encoding='utf8')
    jobs=[]
    for lat in range(48,62):
        for lon in range(-12,4):
            if not domain.intersects(box(lon,lat,lon+1,lat+1)): continue
            stem=f"Copernicus_DSM_COG_30_N{lat:02d}_00_{'E' if lon>=0 else 'W'}{abs(lon):03d}_00_DEM"
            if stem in known: jobs.append(('dem',lon,lat))
    for lat in range(48,63,3):
        for lon in range(-12,6,3):
            stem=f"ESA_WorldCover_10m_2021_v200_N{lat:02d}{'E' if lon>=0 else 'W'}{abs(lon):03d}_Map.tif"
            if domain.intersects(box(lon,lat,lon+3,lat+3)) and stem in cover_known: jobs.append(('cover',lon,lat))
    records=[]
    with futures.ThreadPoolExecutor(max_workers=5) as pool:
        pending={pool.submit(shared.cog_extract,*job):job for job in jobs}
        for count, future in enumerate(futures.as_completed(pending),1):
            records.append(dict(kind=pending[future][0],**future.result()))
            print(f'Source {count}/{len(jobs)} {pending[future]}',flush=True)
    (WORK/'sources.json').write_text(json.dumps(records,indent=2),encoding='utf8')


def colour_mosaic():
    path=WORK/'cover_colour.npy'
    if path.exists() and '--rebuild' not in sys.argv: return np.load(path,mmap_mode='r')
    # Linear display tones of *observed classes*. No terrain-derived vegetation,
    # heather, peat, agriculture, snowline or simulated production classification.
    neutral=np.array([.56,.56,.45])
    palette=np.tile(neutral,(256,1)).astype('float32')
    palette[10]=[.28,.40,.28] # tree cover, including plantations
    palette[20]=[.46,.47,.33] # shrubs, not specifically heather/moor
    palette[30]=[.54,.59,.42] # herbaceous cover, not historical pasture
    palette[40]=[.61,.59,.42] # 2021 cropland, never a 1900 field assertion
    palette[60]=[.63,.61,.55] # bare/sparse, not lithology
    palette[90]=[.43,.53,.47] # herbaceous wetland, not peat depth/type
    data=np.lib.format.open_memmap(path,mode='w+',dtype='float32',shape=(*SHAPE,3))
    data[:]=neutral
    for file in sorted((WORK/'cover').glob('*.tif')):
        with rasterio.open(file) as src:
            classes=src.read(1)
            win=rasterio.windows.from_bounds(*src.bounds,transform=TRANSFORM)
            x0=max(0,math.floor(win.col_off)); y0=max(0,math.floor(win.row_off))
            x1=min(SHAPE[1],math.ceil(win.col_off+win.width)); y1=min(SHAPE[0],math.ceil(win.row_off+win.height))
            if x1<=x0 or y1<=y0: continue
            for c in range(3):
                dest=np.full((y1-y0,x1-x0),np.nan,dtype='float32')
                reproject(palette[classes,c],dest,src_transform=src.transform,src_crs=src.crs,
                          dst_transform=TRANSFORM*rasterio.Affine.translation(x0,y0),dst_crs='EPSG:4326',
                          dst_nodata=np.nan,resampling=Resampling.average)
                view=data[y0:y1,x0:x1,c]; valid=np.isfinite(dest); view[valid]=dest[valid]
    data.flush(); return data


def field(bounds):
    d=shared.field(bounds) # Same true metric gradients / fixed shading as R42.
    w,s,e,n=bounds
    lon=w+(np.arange(d.shape[1],dtype='float32')+.5)*STEP
    lat=n-(np.arange(d.shape[0],dtype='float32')+.5)*STEP
    coord=np.meshgrid((BOUNDS[3]-lat)/STEP-.5,(lon-BOUNDS[0])/STEP-.5,indexing='ij')
    rgb=np.stack([map_coordinates(COLOUR[:,:,c],coord,order=1,mode='nearest',prefilter=False) for c in range(3)],axis=-1)
    # One absolute elevation interpretation for every island, no local min/max.
    upland=shared.smooth(.20,.95,d[:,:,0])*.40
    rgb=rgb*(1-upland[:,:,None])+np.array([.70,.68,.62])*upland[:,:,None]
    valid=map_coordinates(DOMAIN,coord,order=0,mode='constant',cval=0,prefilter=False)
    return np.concatenate([rgb,(d[:,:,1]*valid)[:,:,None]],axis=-1)


def catalogue(assets,polygons):
    source=dict(source_id='british_modern_surface_r43',title='British Isles modern DSM and land-cover reference',
        publisher='Copernicus / ESA / Airbus; ESA WorldCover consortium; Natural Earth',version='GLO90-COG+WorldCover2021-v200:R43',
        license='Copernicus-DEM-GLO90+CC-BY-4.0+Natural-Earth-Public-Domain',locator='https://copernicus-dem-90m.s3.amazonaws.com/readme.html',
        access_metadata=dict(horizontal_crs='EPSG:4326 WGS84-G1150; actual source affine',vertical_datum='EGM2008 EPSG:3855 orthometric metres',
        dem_type='DSM, includes vegetation/infrastructure; not bare-earth DTM',dem_epoch='TanDEM-X 2011-2015, older gap-fill possible',
        cover_epoch='2021, WorldCover v200 classes 10/20/30/40/60/90; no specific heather or peat classification',
        sampling='Native GLO90 3 arcseconds latitude, variable longitude. 6-arcsecond averaged research extraction; 1/512-degree display. Cover from 16x categorical overview, class colours area-averaged in linear space.',
        historical_applicability='Modern geographic reference only. No 1900 cover, ownership, yield, forestry or military effect.',
        footprint='Only physical island components from existing R27 Natural Earth land, with sea-side material sampling collar. Not political borders.',
        licence_url='https://dataspace.copernicus.eu/sites/default/files/media/files/2025-06/copernicus_contributing_mission_data_access_v2_cop_dem_licenses.pdf',
        cover_source='https://esa-worldcover.org/en/data-access',cover_doi='https://doi.org/10.5281/zenodo.7254221'))
    assets[0]['footprint_rings']=[list(map(list,p.simplify(.03,preserve_topology=True).exterior.coords)) for p in polygons if p.area>.0001]
    for a in assets:
        a['surface_group']='british_r43'; a['surface_encoding']=1
        a['channels']='RGB linear albedo from observed 2021 cover and absolute DSM hypsometry; A hillshade minus .4, zero outside physical-island material collar. No encoded world facts.'
    fact=dict(fact_id='physical_relief:british_r43',domain='physical_reference_content',subject_id='physical_relief:british_isles',
        value=dict(status='PHYSICAL_REFERENCE',assets=assets),unit='presentation_relief',source_id=source['source_id'],source_version=source['version'],source_locator=source['locator'],
        observation_period={'from':'2011-01-01','to':'2021-12-31'},spatial_scope={'kind':'geographic_reference','id':'great_britain_ireland_and_islands'},
        methodology='Shared R42 georeferencing, DSM derivatives, overlapping geographic tiles and offline mip packing; independently sourced modern cover; physical-island material collar.',
        confidence=.8,lower_bound=None,upper_bound=None,license=source['license'],review_status='EVIDENCE_LINKED',generator='tools/map/build_british_surface_r43.py')
    document={'source_registry':{'schema_id':'historical_source_registry_v2','sources':[source]},'evidence_catalog':{'schema_id':'historical_fact_evidence_catalog_v2','facts':[fact]}}
    (ROOT/'data/presentation/british_surface_r43.json').write_text(json.dumps(document,ensure_ascii=False,indent=2)+'\n',encoding='utf8')


if __name__=='__main__':
    polygons,domain=islands()
    acquire(domain)
    shared.HEIGHT=shared.mosaic('dem')
    shared.TREES=np.zeros(SHAPE,dtype='uint8') # R42's forest channel not used by this encoding.
    COLOUR=colour_mosaic()
    DOMAIN=rasterize([(mapping(domain),1)],out_shape=SHAPE,transform=TRANSFORM,dtype='uint8')
    full=np.lib.format.open_memmap(WORK/'field.npy',mode='w+',dtype='float32',shape=(*SHAPE,4))
    assets=[]
    for lat in range(48,62,2):
        for lon in range(-12,4,2):
            col=round((lon-BOUNDS[0])/STEP); row=round((BOUNDS[3]-lat-2)/STEP)
            collar=shared.PADDING*STEP
            b=(lon-collar,lat-collar,lon+2+collar,lat+2+collar)
            pixels=field(b); core=pixels[32:-32,32:-32]
            full[row:row+1024,col:col+1024]=core
            if not DOMAIN[row:row+1024,col:col+1024].any(): continue
            a=shared.write_asset(f'british_r43_{lat}_{lon:+d}',pixels,b,'detail')
            a['core_bounds_lon_lat']=[lon,lat,lon+2,lat+2]; assets.append(a)
            print('Built',a['id'],flush=True)
    full.flush()
    coarse=np.empty((896,1024,4),dtype='float32')
    for c in range(4): coarse[:,:,c]=np.asarray(Image.fromarray(full[:,:,c],'F').resize((1024,896),Image.Resampling.BOX))
    assets.insert(0,shared.write_asset('british_r43_base',coarse,BOUNDS,'base'))
    catalogue(assets,polygons)
    image=np.clip(coarse[:,:,:3]*(.4+coarse[:,:,3,None]),0,1)
    image[coarse[:,:,3]<.01]=[.10,.17,.20]
    Image.fromarray(np.uint8(image*255)).save(WORK/'british_preview.png')
    print(json.dumps(dict(files=len(assets),bytes=sum(a['bytes'] for a in assets),decoded_bytes=sum(a['decoded_bytes'] for a in assets))),flush=True)
