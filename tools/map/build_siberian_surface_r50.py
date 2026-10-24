"""Siberian geographic display packs on the existing R42 native-Mip contract.

Offline only. Native ETOPO supports the whole domain. Selected GLO-90 windows
refine it; observed WorldCover classes never create historical land facts.
"""
if __name__ == '__main__':
    from generation_policy import enter
    from pathlib import Path as GenerationPath
    enter(GenerationPath(__file__).resolve().parents[2], 'siberian_surface_r50.json')

from pathlib import Path
import concurrent.futures as futures
import json,math,sys,time
import numpy as np
import requests
import xml.etree.ElementTree as ET
import build_france_surface_r42 as shared
import rasterio
from rasterio.enums import Resampling
from rasterio.transform import from_bounds
from rasterio.warp import reproject
from scipy.ndimage import gaussian_filter

ROOT=shared.ROOT
WORK=ROOT/'local-artifacts/siberian-surface-r50'
BOUNDS=(54.,46.,176.,84.)
ETOPO=ROOT/'local-artifacts/physical-relief-r1/source/ETOPO_2022_v1_60s_N90W180_surface.tif'
FINE={(58,60),(80,56),(68,60),(86,48),(88,48),(92,52),(96,52),
      (90,68),(92,68),(104,50),(106,52),(108,54),(100,56),(96,60),
      (100,64),(128,62),(126,72),(128,72),(130,66),(144,66),
      (148,70),(158,68),(102,74)}
PALETTE=np.tile(np.array([.56,.56,.45],dtype='float32'),(256,1))
for k,c in {10:[.28,.40,.28],20:[.46,.47,.33],30:[.54,.59,.42],
            40:[.61,.59,.42],60:[.63,.61,.55],70:[.67,.69,.67],
            90:[.43,.53,.47],100:[.50,.55,.42]}.items():PALETTE[k]=c

def support(x,y):
    s=shared.smooth
    # Geographic collars, independent of modern administrative identities.
    west=s(54,56,x)*(1-s(114,118,x))*s(46,48,y)*(1-s(82,84,y))
    # Pull the southern collar northwards east of Transbaikalia. The Amur
    # basin and Pacific coast are not a new full terrain construction area.
    east_south=48+12*s(116,144,x)
    east=s(110,114,x)*(1-s(152,156,x))*s(east_south,east_south+2,y)*(1-s(80,82,y))
    northeast=s(148,152,x)*(1-s(172,176,x))*s(59,61,y)*(1-s(80,82,y))
    return np.maximum(np.maximum(west,east),northeast)

def intersects(bounds):
    w,s,e,n=bounds
    x,y=np.meshgrid(np.linspace(w,e,7),np.linspace(s,n,7))
    return float(support(x,y).max())>0

def cover_extract(lon,lat,high):
    directory=WORK/'cover';directory.mkdir(exist_ok=True,parents=True)
    name=f'{lat:+03d}_{lon:+04d}';path=directory/(name+'.tif');record=directory/(name+'.json')
    size=2250 if high else 225
    if path.exists() and record.exists():return json.loads(record.read_text(encoding='utf8'))
    url=f'{shared.WC_ROOT}/ESA_WorldCover_10m_2021_v200_N{lat:02d}E{lon:03d}_Map.tif'
    for attempt in range(3):
        try:
            with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN='EMPTY_DIR',GDAL_HTTP_TIMEOUT='45',GDAL_CACHEMAX=16*1024*1024):
                with rasterio.open(url) as src:
                    data=src.read(1,out_shape=(size,size),resampling=Resampling.nearest)
                    affine=src.transform*src.transform.scale(src.width/size,src.height/size)
                    if not set(np.unique(data)).issubset({0,10,20,30,40,50,60,70,80,90,95,100}):raise ValueError('Invalid cover class')
                    with rasterio.open(path,'w',driver='GTiff',width=size,height=size,count=1,dtype='uint8',crs=src.crs,transform=affine,compress='deflate') as dst:dst.write(data,1)
                    info=dict(url=url,native_shape=list(src.shape),extracted_shape=[size,size],native_transform=list(src.transform),
                              extracted_transform=list(affine),crs=str(src.crs),bounds=list(src.bounds),method='nearest categorical COG overview',
                              source_epoch='2021 v200',bytes=path.stat().st_size,retrieved_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()))
            record.write_text(json.dumps(info,indent=2),encoding='utf8');return info
        except Exception:
            if attempt==2:raise
    raise RuntimeError('Unreachable')

def acquire():
    WORK.mkdir(exist_ok=True,parents=True);shared.RESEARCH=WORK
    known=(ROOT/'local-artifacts/france-surface-r42/copdem_tileList.txt').read_text(encoding='utf8')
    jobs=[];dem=set()
    for lon,lat in FINE:
        for yy in range(lat-1,lat+3):
            for xx in range(lon-1,lon+3):
                stem=f'Copernicus_DSM_COG_30_N{yy:02d}_00_E{xx:03d}_00_DEM'
                if stem in known:dem.add((xx,yy))
    jobs.extend(('dem',x,y,True) for x,y in sorted(dem))
    listing=WORK/'worldcover_keys.txt'
    if not listing.exists():
        keys=[]
        for lat in range(45,84,3):
            r=requests.get('https://esa-worldcover.s3.eu-central-1.amazonaws.com',params={'list-type':'2','prefix':f'v200/2021/map/ESA_WorldCover_10m_2021_v200_N{lat:02d}','max-keys':1000},timeout=60)
            r.raise_for_status();doc=ET.fromstring(r.content)
            if any(v.text=='true' for v in doc.iter() if v.tag.endswith('}IsTruncated')):raise ValueError('Cover listing truncated')
            keys.extend(v.text for v in doc.iter() if v.tag.endswith('}Key'))
        listing.write_text('\n'.join(keys),encoding='utf8')
    available=listing.read_text(encoding='utf8')
    for lat in range(45,84,3):
        for lon in range(54,177,3):
            if not intersects((lon,lat,lon+3,lat+3)):continue
            if f'v200_N{lat:02d}E{lon:03d}_Map.tif' not in available:continue
            high=any(lon<xx+2.1 and lon+3>xx-.1 and lat<yy+2.1 and lat+3>yy-.1 for xx,yy in FINE)
            jobs.append(('cover',lon,lat,high))
    records=[];failures=[]
    def fetch(job):
        kind,x,y,high=job
        if kind=='dem':return shared.cog_extract('dem',x,y)
        try:return cover_extract(x,y,high)
        except Exception:
            if not high:raise
            return cover_extract(x,y,False)
    with futures.ThreadPoolExecutor(max_workers=5) as pool:
        pending={pool.submit(fetch,j):j for j in jobs}
        for count,done in enumerate(futures.as_completed(pending),1):
            job=pending[done]
            try:records.append(dict(kind=job[0],**done.result()))
            except Exception as error:failures.append(dict(job=job,error=str(error)))
            if count%10==0 or count==len(jobs):print('Sources',count,'/',len(jobs),'missing',len(failures),flush=True)
    (WORK/'sources.json').write_text(json.dumps(dict(records=records,failures=failures),indent=2),encoding='utf8')
    # Failed classes stay unknown; do not replace them with inferred vegetation.

def retry_cover_low():
    """Retry only failed high-resolution COG reads at a real coarse overview."""
    p=WORK/'sources.json';d=json.loads(p.read_text(encoding='utf8'));remaining=[]
    for failure in d['failures']:
        kind,x,y,high=failure['job']
        if kind!='cover' or not high:remaining.append(failure);continue
        try:
            info=cover_extract(x,y,False)
            d['records'].append(dict(kind='cover',resolution_fallback='225-pixel provider overview',**info))
            print('Coarse cover recovered',x,y,flush=True)
        except Exception as error:remaining.append(dict(job=failure['job'],error=str(error)))
    d['failures']=remaining;p.write_text(json.dumps(d,indent=2),encoding='utf8')

def sample(path,bounds,size,dtype='float32',method=Resampling.bilinear):
    w,h=size;out=np.full((h,w),np.nan if dtype=='float32' else 0,dtype=dtype)
    with rasterio.open(path) as src:
        reproject(rasterio.band(src,1),out,src_transform=src.transform,src_crs=src.crs,
                  dst_transform=from_bounds(*bounds,w,h),dst_crs='EPSG:4326',dst_nodata=np.nan if dtype=='float32' else 0,resampling=method)
    return out

def make_field(bounds,size,fine=False,resolve=None,sampler=None,coverage=None):
    # Optional offline consumers share this material kernel. Defaults preserve
    # the original R50 production path and source files.
    read=sample if sampler is None else sampler
    coverage=support if coverage is None else coverage
    def find(kind,x,y):
        if resolve is not None:return resolve(kind,x,y)
        p=WORK/kind/f'{y:+03d}_{x:+04d}.tif'
        return p if p.exists() and p.with_suffix('.json').exists() else None
    w,h=size;west,south,east,north=bounds
    lon=west+(np.arange(w)+.5)*(east-west)/w;lat=north-(np.arange(h)+.5)*(north-south)/h
    height=read(ETOPO,bounds,size)
    if not np.isfinite(height).all():raise ValueError('Missing ETOPO coverage')
    if fine:
        for yy in range(math.floor(south),math.ceil(north)):
            for xx in range(math.floor(west),math.ceil(east)):
                path=find('dem',xx,yy)
                if path is None:continue
                data=read(path,bounds,size);valid=np.isfinite(data);height[valid]=data[valid]
    classes=np.zeros((h,w),dtype='uint8')
    confidence=np.zeros((h,w),dtype='float32')
    def ready(x,y):
        return find('cover',x,y) is not None
    for yy in range(math.floor(south/3)*3,math.ceil(north/3)*3,3):
        for xx in range(math.floor(west/3)*3,math.ceil(east/3)*3,3):
            path=find('cover',xx,yy)
            if not ready(xx,yy):continue
            data=read(path,bounds,size,'uint8',Resampling.nearest);valid=data!=0;classes[valid]=data[valid]
            weight=np.ones((h,w),dtype='float32')
            # A missing source stays unknown. Fade only its adjacent class
            # confidence, never copy a vegetation class into the missing cell.
            if not ready(xx-3,yy):weight*=shared.smooth(xx,xx+.2,lon)[None,:]
            if not ready(xx+3,yy):weight*=1-shared.smooth(xx+2.8,xx+3,lon)[None,:]
            if not ready(xx,yy-3):weight*=shared.smooth(yy,yy+.2,lat)[:,None]
            if not ready(xx,yy+3):weight*=1-shared.smooth(yy+2.8,yy+3,lat)[:,None]
            confidence[valid]=weight[valid]
    smooth=gaussian_filter(height,.65);gy,gx=np.gradient(smooth)
    gx/=111195*(east-west)/w*np.cos(np.deg2rad(lat))[:,None]
    gy/=-111195*(north-south)/h
    norm=np.sqrt(1+9*(gx*gx+gy*gy))
    shade=(.45*(1.5*gx-1.5*gy+.70710678)+.55*(-1.5*gx-1.5*gy+.70710678))/norm
    shade=np.clip(1+(shade-.70710678)*1.7,.48,1.32)
    level=np.log1p(np.maximum(height,0)/200)/np.log(26)
    upland=shared.smooth(.2,.95,level)*.4
    observed=PALETTE[classes]*confidence[:,:,None]+PALETTE[0]*(1-confidence[:,:,None])
    rgb=observed*(1-upland[:,:,None])+np.array([.70,.68,.62])*upland[:,:,None]
    # Keep geographic coverage independent of shade. Otherwise the collar
    # darkens before it fades and exposes the support rectangle.
    return np.concatenate([np.clip(rgb*shade[:,:,None],0,1),coverage(lon[None,:],lat[:,None])[:,:,None]],axis=-1),classes

def catalogue(assets):
    source=dict(source_id='siberian_surface_r50',title='Siberian ETOPO regional surface, selected GLO90 and WorldCover 2021',
      publisher='NOAA NCEI; European Union / Airbus; ESA WorldCover consortium',version='ETOPO2022-60s+GLO90+WC2021-v200:R50',
      license='CC0-1.0+Copernicus-DEM-GLO90+CC-BY-4.0',locator='https://www.ncei.noaa.gov/products/etopo-global-relief-model',
      access_metadata=dict(bounds_lon_lat=list(BOUNDS),horizontal_crs='EPSG:4326 WGS84; Copernicus WGS84-G1150 source affine',
      vertical_datum='EGM2008 orthometric metres EPSG:3855',source_epoch='ETOPO 2022 composite; GLO90 mainly 2011-2015 plus gap fill; cover 2021 v200',
      sampling='ETOPO native 60 arcsec; overview 120 arcsec; ordinary detail 60 arcsec. Selected GLO90 DSM extracts at 6 arcsec; display 1/512 degree.',
      cover_sampling='Categorical COG: 225x225 per 3 degrees for broad areas, 2250x2250 for selected detailed areas. Unknown and water classes use neutral land material.',
      historical_applicability='Modern physical reference only; no 1900 cover, glacier, permafrost, water level, ownership or economic effects.',
      copdem_license='https://dataspace.copernicus.eu/sites/default/files/media/files/2025-06/copernicus_contributing_mission_data_access_v2_cop_dem_licenses.pdf',
      copdem_notice='Copernicus DEM © DLR e.V. (2010–2014), © Airbus Defence and Space GmbH (2014–2018). COPERNICUS: European Union / ESA.',
      cover_license='https://creativecommons.org/licenses/by/4.0/',cover_doi='https://doi.org/10.5281/zenodo.7254221',
      attribution='NOAA NCEI ETOPO 2022; Copernicus DEM GLO-90; © ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium'))
    fact=dict(fact_id='physical_relief:siberian_r50',domain='physical_reference_content',subject_id='physical_relief:siberian_reference',
       value=dict(status='PHYSICAL_REFERENCE',assets=assets),unit='presentation_relief',source_id=source['source_id'],source_version=source['version'],source_locator=source['locator'],
       observation_period={'from':'1998-01-01','to':'2022-12-31'},spatial_scope=dict(kind='geographic_reference',id='siberian_finite_geographic_collars'),
       methodology='Native ETOPO bounded sampling, selected GLO90 source-affine refinement, metric fixed hillshade, independent observed classes and existing linear RGBA mip packer.',
       confidence=.8,lower_bound=None,upper_bound=None,license=source['license'],review_status='EVIDENCE_LINKED',generator='tools/map/build_siberian_surface_r50.py')
    out=dict(source_registry=dict(schema_id='historical_source_registry_v2',sources=[source]),evidence_catalog=dict(schema_id='historical_fact_evidence_catalog_v2',facts=[fact]))
    (ROOT/'data/presentation/siberian_surface_r50.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n',encoding='utf8')

def build():
    assets=[];coarse_bounds=BOUNDS
    # Keep a single bounded Siberian overview rather than one resident per basin.
    pixels,classes=make_field(coarse_bounds,(3660,1140))
    a=shared.write_asset('siberian_r50_base',pixels,coarse_bounds,'base')
    a.update(surface_feather_degrees=[0,0,0,0],dem_source='ETOPO2022-60s',surface_group='siberian_r50',surface_encoding=5)
    assets.append(a)
    for lat in range(46,84,2):
        for lon in range(54,176,2):
            core=(lon,lat,lon+2,lat+2)
            if not intersects(core):continue
            fine=(lon,lat) in FINE;pad=32/512 if fine else 4/60
            bounds=(lon-pad,lat-pad,lon+2+pad,lat+2+pad);size=(1088,1088) if fine else (128,128)
            pixels,_=make_field(bounds,size,fine)
            a=shared.write_asset(f'siberian_r50_{lat}_{lon:+d}',pixels,bounds,'detail')
            a.update(core_bounds_lon_lat=list(core),core_inset_degrees=pad,surface_group='siberian_r50',surface_encoding=5,
                     dem_source='GLO90-DSM-with-ETOPO-gap-reference' if fine else 'ETOPO2022-60s',surface_support_fraction=1.0,
                     channels='Linear RGB observed-class and absolute-height material with offline metric hillshade; A independent geographic support. No water or permafrost inference.')
            assets.append(a)
            if len(assets)%50==0:print('Built',len(assets),'packs',flush=True)
    catalogue(assets)
    summary=dict(files=len(assets),fine_glo90=sum(a.get('dem_source','').startswith('GLO90') for a in assets),bytes=sum(a['bytes'] for a in assets),
                 overview_decoded=assets[0]['decoded_bytes'],max_detail_decoded=max(a['decoded_bytes'] for a in assets[1:]),bounds=list(BOUNDS))
    (WORK/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf8');print(summary,flush=True)

if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf8')
    if '--retry-cover-low' in sys.argv:retry_cover_low()
    else:
        if '--build-only' not in sys.argv:acquire()
        if '--acquire-only' not in sys.argv:build()
