"""R51 Central Asia first, then Far East; reuse R50 source and material kernel.

No source, political fact, or old runtime tile is overwritten. Geographic
overviews replace catalogue selection, not the physical globe or camera.
"""
if __name__ == '__main__':
    from generation_policy import enter
    from pathlib import Path as GenerationPath
    enter(GenerationPath(__file__).resolve().parents[2], 'asian_surface_r51.json')

from pathlib import Path
import json,math,sys,time,concurrent.futures as futures
import xml.etree.ElementTree as ET
import numpy as np
import requests,rasterio
from rasterio.enums import Resampling
import build_france_surface_r42 as common
import build_siberian_surface_r50 as sib

ROOT=common.ROOT;WORK=ROOT/'local-artifacts/asian-surface-r51'
OLD=ROOT/'local-artifacts/siberian-surface-r50'
CA=(44,30,92,56);FE=(114,40,192,78)
CA_FINE={(50,42),(54,44),(66,48),(62,42),(60,38),(56,36),(70,40),
 (74,42),(78,42),(72,38),(74,38),(74,46),(80,46)}
FE_FINE={(118,50),(126,50),(132,46),(134,44),(130,42),(140,50),(142,46),
 (136,58),(128,54),(130,56),(132,50),(142,50),(158,56),(158,52),(160,54),(160,56),
 (170,64),(178,66),(180,66),(184,66)}
RESOLVED={}

def normal(lon):return (lon+180)%360-180
def ca_support(x,y):
    s=common.smooth
    south=34+2*(1-s(54,66,x))+4*s(76,88,x)
    west=44+6*(1-s(44,48,y))
    return s(west,west+2,x)*(1-s(90,92,x))*s(south,south+2,y)*(1-s(54,56,y))
def fe_support(x,y):
    s=common.smooth
    mainland=s(114,118,x)*(1-s(140,144,x))*s(40,42,y)*(1-s(62,66,y))
    okhotsk=s(132,136,x)*(1-s(166,170,x))*s(52,54,y)*(1-s(72,76,y))
    kamchatka=s(154,156,x)*(1-s(166,168,x))*s(49,51,y)*(1-s(64,66,y))
    sakhalin=s(140,141,x)*(1-s(146,148,x))*s(44,45,y)*(1-s(55,56,y))
    chukchi=s(164,168,x)*(1-s(190,192,x))*s(59,61,y)*(1-s(76,78,y))
    return np.maximum.reduce(np.broadcast_arrays(mainland,okhotsk,kamchatka,sakhalin,chukchi))
def coverage(x,y):return np.maximum(np.maximum(sib.support(x,y),ca_support(x,y)),fe_support(x,y))
def intersects(bounds,fn):
    w,s,e,n=bounds;x,y=np.meshgrid(np.linspace(w,e,7),np.linspace(s,n,7))
    return float(fn(x,y).max())>.001
def resolve(kind,lon,lat):
    lon=normal(lon);key=(kind,lon,lat)
    if key not in RESOLVED:
        RESOLVED[key]=next((p for base in [OLD,WORK] if (p:=base/kind/f'{lat:+03d}_{lon:+04d}.tif').exists() and p.with_suffix('.json').exists()),None)
    return RESOLVED[key]
def sample(path,bounds,size,dtype='float32',method=Resampling.bilinear):
    # Align both sides of the date line to the same pixel grid. Never ask a
    # geographic warp to extrapolate a source east of its [-180,180] domain.
    w,s,e,n=bounds;nx,ny=size
    if w>=180:return sib.sample(path,(w-360,s,e-360,n),size,dtype,method)
    if e<=-180:return sib.sample(path,(w+360,s,e+360,n),size,dtype,method)
    if e>180:
        cut=round((180-w)/(e-w)*nx)
        return np.concatenate([sample(path,(w,s,180,n),(cut,ny),dtype,method),sample(path,(180,s,e,n),(nx-cut,ny),dtype,method)],axis=1)
    return sib.sample(path,bounds,size,dtype,method)

def cover_extract(lon,lat,size=450):
    old=resolve('cover',lon,lat)
    if old:return dict(reused=str(old.relative_to(ROOT)),**json.loads(old.with_suffix('.json').read_text(encoding='utf8')))
    lon=normal(lon);directory=WORK/'cover';directory.mkdir(parents=True,exist_ok=True)
    path=directory/f'{lat:+03d}_{lon:+04d}.tif';record=path.with_suffix('.json')
    stem=f'ESA_WorldCover_10m_2021_v200_N{lat:02d}{"E" if lon>=0 else "W"}{abs(lon):03d}_Map'
    url=f'{common.WC_ROOT}/{stem}.tif'
    for attempt in range(3):
        try:
            with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN='EMPTY_DIR',GDAL_HTTP_TIMEOUT='45',GDAL_CACHEMAX=16*1024*1024):
                with rasterio.open(url) as src:
                    data=src.read(1,out_shape=(size,size),resampling=Resampling.nearest)
                    affine=src.transform*src.transform.scale(src.width/size,src.height/size)
                    if not set(np.unique(data)).issubset({0,10,20,30,40,50,60,70,80,90,95,100}):raise ValueError('Invalid observed class')
                    with rasterio.open(path,'w',driver='GTiff',width=size,height=size,count=1,dtype='uint8',crs=src.crs,transform=affine,compress='deflate') as dst:dst.write(data,1)
                    info=dict(url=url,native_shape=list(src.shape),extracted_shape=[size,size],crs=str(src.crs),native_transform=list(src.transform),extracted_transform=list(affine),bounds=list(src.bounds),method='nearest categorical provider overview',source_epoch='2021 v200',bytes=path.stat().st_size)
            record.write_text(json.dumps(info,indent=2),encoding='utf8');return info
        except Exception:
            if attempt==2:raise

def acquire(stage,bounds=None,fn=None,fine=None):
    WORK.mkdir(parents=True,exist_ok=True);common.RESEARCH=WORK
    if bounds is None:bounds,fn,fine=(CA,ca_support,CA_FINE) if stage=='central' else (FE,fe_support,FE_FINE)
    listing=(ROOT/'local-artifacts/france-surface-r42/copdem_tileList.txt').read_text(encoding='utf8')
    dem=set()
    for xx,yy in fine:
        for y in range(yy-1,yy+3):
            for x0 in range(xx-1,xx+3):
                x=normal(x0);stem=f'Copernicus_DSM_COG_30_N{y:02d}_00_{"E" if x>=0 else "W"}{abs(x):03d}_00_DEM'
                if stem in listing:dem.add((x,y))
    jobs=[('dem',x,y) for x,y in sorted(dem)]
    key_path=WORK/f'worldcover_{stage}_keys.txt'
    if not key_path.exists():
        keys=[]
        for y in range(math.floor(bounds[1]/3)*3,math.ceil(bounds[3]/3)*3,3):
            r=requests.get('https://esa-worldcover.s3.eu-central-1.amazonaws.com',params={'list-type':'2','prefix':f'v200/2021/map/ESA_WorldCover_10m_2021_v200_N{y:02d}','max-keys':1000},timeout=60);r.raise_for_status();doc=ET.fromstring(r.content)
            if any(v.text=='true' for v in doc.iter() if v.tag.endswith('}IsTruncated')):raise ValueError('Truncated cover listing')
            keys.extend(v.text for v in doc.iter() if v.tag.endswith('}Key'))
        key_path.write_text('\n'.join(keys),encoding='utf8')
    keys=key_path.read_text(encoding='utf8')
    for yy in range(math.floor(bounds[1]/3)*3,math.ceil(bounds[3]/3)*3,3):
        for xx in range(math.floor(bounds[0]/3)*3,math.ceil(bounds[2]/3)*3,3):
            if not intersects((xx,yy,xx+3,yy+3),fn):continue
            x=normal(xx)
            if f'v200_N{yy:02d}{"E" if x>=0 else "W"}{abs(x):03d}_Map.tif' in keys:jobs.append(('cover',x,yy))
    def fetch(job):
        kind,x,y=job
        if kind=='cover':
            try:return cover_extract(x,y)
            except Exception:return cover_extract(x,y,225)
        old=resolve('dem',x,y)
        if old:return dict(reused=str(old.relative_to(ROOT)),**json.loads(old.with_suffix('.json').read_text(encoding='utf8')))
        return common.cog_extract('dem',x,y)
    records=[];missing=[]
    with futures.ThreadPoolExecutor(max_workers=5) as pool:
        pending={pool.submit(fetch,j):j for j in jobs}
        for count,f in enumerate(futures.as_completed(pending),1):
            j=pending[f]
            try:records.append(dict(kind=j[0],**f.result()))
            except Exception as e:missing.append(dict(job=j,error=str(e)))
            if count%20==0 or count==len(jobs):print(stage,'sources',count,'/',len(jobs),'missing',len(missing),flush=True)
    (WORK/f'{stage}_sources.json').write_text(json.dumps(dict(records=records,failures=missing),indent=2),encoding='utf8');RESOLVED.clear()

def build_stage(stage):
    RESOLVED.clear();bounds,fn,fine=(CA,ca_support,CA_FINE) if stage=='central' else (FE,fe_support,FE_FINE)
    old=json.loads((ROOT/'data/presentation/siberian_surface_r50.json').read_text(encoding='utf8'))['evidence_catalog']['facts'][0]['value']['assets']
    old_cells={(round(a['core_bounds_lon_lat'][0]),round(a['core_bounds_lon_lat'][1])):a for a in old if a['surface_role']=='detail'}
    assets=[];reused=[]
    for yy in range(bounds[1],bounds[3],2):
        for xx in range(bounds[0],bounds[2],2):
            core=(xx,yy,xx+2,yy+2)
            if not intersects(core,fn):continue
            previous=old_cells.get((xx,yy));gx,gy=np.meshgrid(np.linspace(xx,xx+2,7),np.linspace(yy,yy+2,7))
            finer_requested=(xx,yy) in fine and previous is not None and not previous.get('dem_source','').startswith('GLO90')
            if previous and not finer_requested and np.all(sib.support(gx,gy)>=fn(gx,gy)-.001):reused.append(previous['id']);continue
            isfine=(xx,yy) in fine or previous is not None and previous.get('dem_source','').startswith('GLO90')
            pad=32/512 if isfine else 4/60;b=(xx-pad,yy-pad,xx+2+pad,yy+2+pad);size=(1088,1088) if isfine else (128,128)
            pixels,_=sib.make_field(b,size,isfine,resolve,sample,coverage)
            a=common.write_asset(f'asian_r51_{yy}_{normal(xx):+d}',pixels,b,'detail')
            a.update(core_bounds_lon_lat=list(core),core_inset_degrees=pad,surface_encoding=5,surface_group='asian_r51',dem_source='GLO90-DSM-with-ETOPO-gap-reference' if isfine else 'ETOPO2022-60s',surface_support_fraction=1.0,channels='Linear RGB shared R50 observed-class/absolute-height material with fixed offline hillshade; independent A geographic support')
            assets.append(a)
            if len(assets)%50==0:print(stage,'built',len(assets),flush=True)
    (WORK/f'{stage}_assets.json').write_text(json.dumps(dict(assets=assets,reused=reused),indent=2),encoding='utf8')
    print(stage,'detail packs',len(assets),'reused',len(reused),flush=True)

def finish():
    RESOLVED.clear();new=[]
    for stage in ['central','far_east']:new.extend(json.loads((WORK/f'{stage}_assets.json').read_text(encoding='utf8'))['assets'])
    for name,b in [('asia_west_r51_base',(44,30,128,84)),('asia_east_r51_base',(120,40,192,84))]:
        size=(round((b[2]-b[0])*30),round((b[3]-b[1])*30));pixels,_=sib.make_field(b,size,False,resolve,sample,coverage)
        a=common.write_asset(name,pixels,b,'base');a.update(surface_encoding=5,surface_group='asian_r51',surface_feather_degrees=[0 if b[0]==44 else 4,0,4 if b[2]==128 else 0,0],dem_source='ETOPO2022-60s');new.insert(0,a)
    old_doc=json.loads((ROOT/'data/presentation/siberian_surface_r50.json').read_text(encoding='utf8'));old_fact=old_doc['evidence_catalog']['facts'][0]
    occupied={tuple(a['core_bounds_lon_lat'][:2]) for a in new if a['surface_role']=='detail'}
    retained=[a for a in old_fact['value']['assets'] if a['surface_role']=='detail' and tuple(a['core_bounds_lon_lat'][:2]) not in occupied]
    old_fact['value']['assets']=retained
    src=dict(source_id='asian_surface_r51',title='Central Asia and Far East geographic surface, shared Siberian kernel',publisher='NOAA NCEI; European Union / Airbus; ESA WorldCover consortium',version='ETOPO2022-60s+GLO90+WC2021-v200:R51',license='CC0-1.0+Copernicus-DEM-GLO90+CC-BY-4.0',locator='https://www.ncei.noaa.gov/products/etopo-global-relief-model',access_metadata=dict(horizontal_crs='EPSG:4326 with unwrapped display collars, source affines retained',vertical_datum='EGM2008 orthometric metres EPSG:3855',epochs='ETOPO composite1998-2022; GLO90 mainly2011-2015; WorldCover2021 v200',sampling='Overview120arcsec, ordinary60arcsec; selected6arcsec DSM extracts resampled at1/512degree. No local metre DEM.',attribution='NOAA ETOPO2022; Copernicus DEM © DLR e.V.2010–2014 / Airbus Defence and Space2014–2018, COPERNICUS European Union/ESA; © ESA WorldCover project2021 / Contains modified Copernicus Sentinel data(2021) processed by ESA WorldCover consortium',cover_doi='https://doi.org/10.5281/zenodo.7254221',cover_license='https://creativecommons.org/licenses/by/4.0/',copdem_license='https://dataspace.copernicus.eu/sites/default/files/media/files/2025-06/copernicus_contributing_mission_data_access_v2_cop_dem_licenses.pdf',historical_applicability='Modern physical display, no1900 land-use, snow, permafrost, water level or political assertion. WorldCover water stays neutral.'))
    fact=dict(fact_id='physical_relief:asian_r51',domain='physical_reference_content',subject_id='physical_relief:asian_reference',value=dict(status='PHYSICAL_REFERENCE',assets=new),unit='presentation_relief',source_id=src['source_id'],source_version=src['version'],source_locator=src['locator'],observation_period={'from':'1998-01-01','to':'2022-12-31'},spatial_scope=dict(kind='geographic_reference',id='central_asia_far_east_with_finite_collars'),methodology='Existing R50 material and source-affine processing; two shared geographic overviews, bounded refinement and date-line sampling.',confidence=.8,lower_bound=None,upper_bound=None,license=src['license'],review_status='EVIDENCE_LINKED',generator='tools/map/build_asian_surface_r51.py')
    doc=dict(source_registry=dict(schema_id='historical_source_registry_v2',sources=old_doc['source_registry']['sources']+[src]),evidence_catalog=dict(schema_id='historical_fact_evidence_catalog_v2',facts=[fact,old_fact]))
    (ROOT/'data/presentation/asian_surface_r51.json').write_text(json.dumps(doc,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    summary=dict(new_files=len(new),new_bytes=sum(a['bytes'] for a in new),retained_r50_details=len(retained),new_fine=sum(a.get('dem_source','').startswith('GLO90') for a in new),overviews=[dict(id=a['id'],width=a['width'],height=a['height'],decoded_bytes=a['decoded_bytes']) for a in new if a['surface_role']=='base'])
    (WORK/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf8');print(summary,flush=True)

if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf8');stage=sys.argv[1]
    if stage=='finish':finish()
    else:
        if '--build-only' not in sys.argv:acquire(stage)
        if '--acquire-only' not in sys.argv:build_stage(stage)
