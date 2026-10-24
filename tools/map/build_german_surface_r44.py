"""German European terrain display, shared R42/R43 production machinery.

No political geometry becomes a height mask. Research scope is a geographic
rectangle including the historical eastern territories and finite collars.
"""
from pathlib import Path
import concurrent.futures as futures
import json, sys, os, math
import numpy as np
from PIL import Image
from shapely.geometry import box
import build_british_surface_r43 as material
import build_france_surface_r42 as base
import requests
import xml.etree.ElementTree as ET

ROOT=base.ROOT
WORK=ROOT/'local-artifacts/german-surface-r44'
BOUNDS=(4.,46.,24.,58.)
STEP=base.STEP
SHAPE=(6144,10240)

# Existing functions read module configuration; no copied DEM algorithm.
base.RESEARCH=WORK; base.BOUNDS=BOUNDS
material.WORK=WORK; material.BOUNDS=BOUNDS; material.SHAPE=SHAPE
material.TRANSFORM=base.from_bounds(*BOUNDS,SHAPE[1],SHAPE[0])
base.support=lambda lon,lat: np.ones(np.broadcast_shapes(np.shape(lon),np.shape(lat)),dtype='float32')


def acquire():
    WORK.mkdir(parents=True,exist_ok=True)
    known=(ROOT/'local-artifacts/france-surface-r42/copdem_tileList.txt').read_text(encoding='utf8')
    jobs=[]
    for lat in range(46,58):
        for lon in range(4,24):
            stem=f'Copernicus_DSM_COG_30_N{lat:02d}_00_E{lon:03d}_00_DEM'
            if stem in known: jobs.append(('dem',lon,lat))
    listing=WORK/'worldcover_keys.txt'
    if not listing.exists():
        keys=[]
        for lat in range(45,60,3):
            response=requests.get('https://esa-worldcover.s3.eu-central-1.amazonaws.com',params={
                'list-type':'2','prefix':f'v200/2021/map/ESA_WorldCover_10m_2021_v200_N{lat:02d}','max-keys':1000},timeout=90)
            response.raise_for_status(); xml=ET.fromstring(response.content)
            if any(v.text=='true' for v in xml.iter() if v.tag.endswith('}IsTruncated')): raise ValueError('Truncated cover catalogue')
            keys.extend(v.text for v in xml.iter() if v.tag.endswith('}Key'))
        listing.write_text('\n'.join(keys),encoding='utf8')
    cover_known=listing.read_text(encoding='utf8')
    for lat in range(45,60,3):
        for lon in range(3,24,3):
            if f'ESA_WorldCover_10m_2021_v200_N{lat:02d}E{lon:03d}_Map.tif' in cover_known: jobs.append(('cover',lon,lat))
    reused=0
    for kind,lon,lat in jobs:
        name=f'{lat:+03d}_{lon:+04d}'
        target=WORK/kind; target.mkdir(exist_ok=True)
        for previous in [ROOT/'local-artifacts/british-surface-r43',ROOT/'local-artifacts/france-surface-r42']:
            # R42's binary trees are NOT equivalent to the R43 class raster.
            if not all((previous/kind/(name+suffix)).exists() for suffix in ['.tif','.json']): continue
            for suffix in ['.tif','.json']:
                destination=target/(name+suffix)
                if not destination.exists(): os.link(previous/kind/(name+suffix),destination)
            reused+=1; break
    records=[]
    with futures.ThreadPoolExecutor(max_workers=5) as pool:
        pending={pool.submit(base.cog_extract,*job):job for job in jobs}
        for n,job in enumerate(futures.as_completed(pending),1):
            records.append(dict(kind=pending[job][0],**job.result()))
            print(f'Source {n}/{len(jobs)} {pending[job]}',flush=True)
    (WORK/'sources.json').write_text(json.dumps(dict(reused_extracts=reused,records=records),indent=2),encoding='utf8')


def french_core(core):
    # An already complete French tile remains the source for this location.
    w,s,e,n=core
    return base_france_support(w,s)==1 and base_france_support(e,n)==1


def base_france_support(lon,lat):
    return float(base.smooth(-6,-5.3,lon)*(1-base.smooth(8,8.8,lon))*base.smooth(41.4,42.15,lat)*(1-base.smooth(51.35,52,lat)))


def catalogue(assets):
    source=dict(source_id='german_modern_surface_r44',title='German Empire European geographic terrain reference',
        publisher='Copernicus / ESA / Airbus; ESA WorldCover consortium',version='GLO90-COG+WorldCover2021-v200:R44',
        license='Copernicus-DEM-GLO90+CC-BY-4.0',locator='https://copernicus-dem-90m.s3.amazonaws.com/readme.html',
        access_metadata=dict(horizontal_crs='EPSG:4326 WGS84-G1150; actual source affine',vertical_datum='EGM2008 EPSG:3855 orthometric metres',
          dem_type='DSM includes surface objects, not bare-earth DTM',dem_epoch='TanDEM-X 2011-2015, older gap-fill possible',cover_epoch='ESA WorldCover 2021 v200',
          sampling='GLO90 native 3-arcsecond latitude, variable longitude; averaged 6-arcsecond extraction, 1/512-degree display. Cover 16x categorical overview.',
          bounds_lon_lat=list(BOUNDS),historical_applicability='Modern reference, not 1900 environmental facts. Geographic collars, no ownership mask.',
          shared_france='Same DSM, metric gradients and mip generator; full French cores not duplicated. Existing French material takes precedence where valid.',
          licence_url='https://dataspace.copernicus.eu/sites/default/files/media/files/2025-06/copernicus_contributing_mission_data_access_v2_cop_dem_licenses.pdf',
          cover_source='https://esa-worldcover.org/en/data-access',cover_doi='https://doi.org/10.5281/zenodo.7254221'))
    for a in assets:
        a['surface_group']='german_r44'; a['surface_encoding']=2
        a['channels']='RGB linear geographic albedo; A fixed DSM hillshade minus .4. Geographic extent feather supplied separately, no elevation-derived vegetation.'
    assets[0]['surface_feather_degrees']=[1.5,1.,1.,1.5]
    fact=dict(fact_id='physical_relief:german_r44',domain='physical_reference_content',subject_id='physical_relief:german_europe',
        value=dict(status='PHYSICAL_REFERENCE',assets=assets),unit='presentation_relief',source_id=source['source_id'],source_version=source['version'],source_locator=source['locator'],
        observation_period={'from':'2011-01-01','to':'2021-12-31'},spatial_scope=dict(kind='geographic_reference',id='german_europe_with_finite_collars'),
        methodology='R42 DSM resampling, metric hillshade, R43 observed cover palette, shared mips. No political clipping or world facts.',confidence=.8,
        lower_bound=None,upper_bound=None,license=source['license'],review_status='EVIDENCE_LINKED',generator='tools/map/build_german_surface_r44.py')
    document=dict(source_registry=dict(schema_id='historical_source_registry_v2',sources=[source]),evidence_catalog=dict(schema_id='historical_fact_evidence_catalog_v2',facts=[fact]))
    (ROOT/'data/presentation/german_surface_r44.json').write_text(json.dumps(document,ensure_ascii=False,indent=2)+'\n',encoding='utf8')


if __name__=='__main__':
    acquire()
    base.HEIGHT=base.mosaic('dem'); base.TREES=np.zeros(SHAPE,dtype='uint8')
    material.COLOUR=material.colour_mosaic(); material.DOMAIN=np.ones(SHAPE,dtype='uint8')
    full=np.lib.format.open_memmap(WORK/'field.npy',mode='w+',dtype='float32',shape=(*SHAPE,4))
    assets=[]; reused=[]
    for lat in range(46,58,2):
        for lon in range(4,24,2):
            collar=base.PADDING*STEP; bounds=(lon-collar,lat-collar,lon+2+collar,lat+2+collar)
            pixels=material.field(bounds)
            row=round((58-lat-2)/STEP); col=round((lon-4)/STEP)
            full[row:row+1024,col:col+1024]=pixels[32:-32,32:-32]
            if french_core((lon,lat,lon+2,lat+2)):
                reused.append([lon,lat,lon+2,lat+2]); continue
            a=base.write_asset(f'german_r44_{lat}_{lon:+d}',pixels,bounds,'detail')
            a['core_bounds_lon_lat']=[lon,lat,lon+2,lat+2]; assets.append(a)
            print('Built',a['id'],flush=True)
    full.flush(); coarse=np.empty((768,1280,4),dtype='float32')
    for c in range(4): coarse[:,:,c]=np.asarray(Image.fromarray(full[:,:,c],'F').resize((1280,768),Image.Resampling.BOX))
    assets.insert(0,base.write_asset('german_r44_base',coarse,BOUNDS,'base'))
    catalogue(assets)
    Image.fromarray(np.uint8(np.clip(coarse[:,:,:3]*(.4+coarse[:,:,3,None]),0,1)*255)).save(WORK/'german_preview.png')
    summary=dict(files=len(assets),bytes=sum(a['bytes'] for a in assets),reused_france_cores=reused)
    (WORK/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf8'); print(summary,flush=True)
