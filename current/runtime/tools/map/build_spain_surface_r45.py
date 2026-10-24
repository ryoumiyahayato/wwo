"""Spain/Iberian collars and Canary geographic packs, using R42/R43 machinery.

History selects required detail cells, never clips height or defines coastline.
Run with the existing offline Python GIS environment. No game dependency.
"""
import json, math, os, sys, concurrent.futures as futures
import numpy as np
import requests
import xml.etree.ElementTree as ET
from PIL import Image
from shapely.geometry import shape, box
import build_british_surface_r43 as material
import build_france_surface_r42 as base
import build_german_surface_r44 as previous

ROOT=base.ROOT
WORK=ROOT/'local-artifacts/spain-surface-r45'
PACKS=[dict(id='spain_r45',bounds=(-10.,34.,6.,44.),size=(1024,640),encoding=3,feather=[.6,1.8,.6,.6]),
       dict(id='canary_r45',bounds=(-20.,26.,-12.,30.),size=(512,256),encoding=4,feather=[.6,.6,.6,.4])]


def configure(pack):
    work=WORK/pack['id']; work.mkdir(parents=True,exist_ok=True)
    b=pack['bounds']; dims=(round((b[3]-b[1])/base.STEP),round((b[2]-b[0])/base.STEP))
    base.RESEARCH=work; base.BOUNDS=b
    material.WORK=work; material.BOUNDS=b; material.SHAPE=dims
    material.TRANSFORM=base.from_bounds(*b,dims[1],dims[0])
    base.support=lambda lon,lat: np.ones(np.broadcast_shapes(np.shape(lon),np.shape(lat)),dtype='float32')
    return work,dims


def acquire(pack):
    work,_=configure(pack); w,s,e,n=pack['bounds']
    known=(ROOT/'local-artifacts/france-surface-r42/copdem_tileList.txt').read_text(encoding='utf8')
    jobs=[]
    for lat in range(int(s),int(n)):
        for lon in range(int(w),int(e)):
            stem=f"Copernicus_DSM_COG_30_N{lat:02d}_00_{'E' if lon>=0 else 'W'}{abs(lon):03d}_00_DEM"
            if stem in known: jobs.append(('dem',lon,lat))
    listing=work/'worldcover_keys.txt'
    if not listing.exists():
        keys=[]
        for lat in range(math.floor(s/3)*3,math.ceil(n/3)*3,3):
            r=requests.get('https://esa-worldcover.s3.eu-central-1.amazonaws.com',params={
                'list-type':'2','prefix':f'v200/2021/map/ESA_WorldCover_10m_2021_v200_N{lat:02d}','max-keys':1000},timeout=90)
            r.raise_for_status(); xml=ET.fromstring(r.content)
            if any(v.text=='true' for v in xml.iter() if v.tag.endswith('}IsTruncated')): raise ValueError('Truncated cover catalogue')
            keys.extend(v.text for v in xml.iter() if v.tag.endswith('}Key'))
        listing.write_text('\n'.join(keys),encoding='utf8')
    cover_known=listing.read_text(encoding='utf8')
    for lat in range(math.floor(s/3)*3,math.ceil(n/3)*3,3):
        for lon in range(math.floor(w/3)*3,math.ceil(e/3)*3,3):
            stem=f"ESA_WorldCover_10m_2021_v200_N{lat:02d}{'E' if lon>=0 else 'W'}{abs(lon):03d}_Map.tif"
            if stem in cover_known: jobs.append(('cover',lon,lat))
    reused=0
    for kind,lon,lat in jobs:
        name=f'{lat:+03d}_{lon:+04d}'; target=work/kind; target.mkdir(exist_ok=True)
        for old in ['german-surface-r44','british-surface-r43','france-surface-r42']:
            origin=ROOT/'local-artifacts'/old/kind
            if not all((origin/(name+ext)).exists() for ext in ['.tif','.json']): continue
            # Immutable extracted data, not a second copy of French raw DEM.
            for ext in ['.tif','.json']:
                if not (target/(name+ext)).exists(): os.link(origin/(name+ext),target/(name+ext))
            reused+=1; break
    records=[]
    with futures.ThreadPoolExecutor(max_workers=5) as pool:
        pending={pool.submit(base.cog_extract,*job):job for job in jobs}
        for index,job in enumerate(futures.as_completed(pending),1):
            records.append(dict(kind=pending[job][0],**job.result()))
            print(pack['id'],f'Source {index}/{len(jobs)}',pending[job],flush=True)
    (work/'sources.json').write_text(json.dumps(dict(reused_extracts=reused,records=records),indent=2),encoding='utf8')


def catalogue(pack,assets,reused):
    source=dict(source_id=pack['id']+'_modern_surface',title='Spain modern geographic DSM and observed cover reference',
        publisher='Copernicus / ESA / Airbus; ESA WorldCover consortium',version='GLO90-COG+WorldCover2021-v200:R45',
        license='Copernicus-DEM-GLO90+CC-BY-4.0',locator='https://copernicus-dem-90m.s3.amazonaws.com/readme.html',
        access_metadata=dict(horizontal_crs='EPSG:4326 WGS84-G1150; actual PixelIsPoint affine',vertical_datum='EGM2008 EPSG:3855 orthometric metres',
          dem_type='DSM, not bare-earth DTM',dem_epoch='TanDEM-X 2011-2015; older gap-fill possible',cover_epoch='ESA WorldCover 2021 v200',
          sampling='Native GLO90 3-arcsecond latitude, variable longitude; averaged 6-arcsecond extraction; 1/512-degree display. Cover 16x categorical overview.',
          bounds_lon_lat=list(pack['bounds']),historical_applicability='Modern reference, no 1900 land-use, ownership, production or military facts.',
          france_shared_cores=reused,licence_url='https://dataspace.copernicus.eu/sites/default/files/media/files/2025-06/copernicus_contributing_mission_data_access_v2_cop_dem_licenses.pdf',
          cover_source='https://esa-worldcover.org/en/data-access',cover_doi='https://doi.org/10.5281/zenodo.7254221'))
    for asset in assets:
        asset.update(surface_group=pack['id'],surface_encoding=pack['encoding'],channels='RGB observed-cover linear tones and neutral absolute elevation; A fixed DSM hillshade minus .4. Geographic feather separate.')
    assets[0]['surface_feather_degrees']=pack['feather']
    fact=dict(fact_id='physical_relief:'+pack['id'],domain='physical_reference_content',subject_id='physical_relief:'+pack['id'],
        value=dict(status='PHYSICAL_REFERENCE',assets=assets),unit='presentation_relief',source_id=source['source_id'],source_version=source['version'],source_locator=source['locator'],
        observation_period={'from':'2011-01-01','to':'2021-12-31'},spatial_scope=dict(kind='geographic_reference',id=pack['id']+'_finite_collars'),
        methodology='Existing R42 DEM resampling, metric hillshade, R43 independent observed-class tones, shared native mip packer. No political height clipping.',
        confidence=.8,lower_bound=None,upper_bound=None,license=source['license'],review_status='EVIDENCE_LINKED',generator='tools/map/build_spain_surface_r45.py')
    path=ROOT/'data/presentation'/(pack['id'].replace('_r','_surface_r')+'.json')
    path.write_text(json.dumps(dict(source_registry=dict(schema_id='historical_source_registry_v2',sources=[source]),
        evidence_catalog=dict(schema_id='historical_fact_evidence_catalog_v2',facts=[fact])),ensure_ascii=False,indent=2)+'\n',encoding='utf8')


def build(pack):
    work,dims=configure(pack); w,s,e,n=pack['bounds']
    base.HEIGHT=base.mosaic('dem'); base.TREES=np.zeros(dims,dtype='uint8')
    material.COLOUR=material.colour_mosaic(); material.DOMAIN=np.ones(dims,dtype='uint8')
    # Only chooses *detail cells*. The geographical cell edge has a real-data
    # collar and nationwide base beneath it; it never clips at a state border.
    historical=json.loads((ROOT/'data/world_map/historical/cshapes_1900_snapshot.json').read_text(encoding='utf8'))
    spain=shape(next(f for f in historical['features'] if f['gwcode']==230)['geometry']).intersection(box(*pack['bounds'])).buffer(.6)
    full=np.lib.format.open_memmap(work/'field.npy',mode='w+',dtype='float32',shape=(*dims,4))
    assets=[]; reused=[]
    for lat in range(int(s),int(n),2):
        for lon in range(int(w),int(e),2):
            core=(lon,lat,lon+2,lat+2); pad=base.PADDING*base.STEP
            bounds=(lon-pad,lat-pad,lon+2+pad,lat+2+pad)
            pixels=material.field(bounds)
            row=round((n-lat-2)/base.STEP); col=round((lon-w)/base.STEP)
            full[row:row+1024,col:col+1024]=pixels[32:-32,32:-32]
            if not spain.intersects(box(*core)): continue
            if pack['id']=='spain_r45' and previous.french_core(core):
                reused.append(list(core)); continue
            detail=pixels
            # R42 is complete north of 42.15N in this longitude band. Keep
            # only a southern transition strip, not a duplicate Pyrenean tile.
            # The .10-degree overlap beyond full coverage exceeds the .0625
            # sampling collar; derivatives on both sides still use real data.
            if pack['id']=='spain_r45' and lat==42 and previous.french_core((lon,42.25,lon+2,44)):
                reused.append([lon,42.25,lon+2,44])
                core=(lon,lat,lon+2,42.25)
                bounds=(lon-pad,lat-pad,lon+2+pad,42.25+pad)
                detail=pixels[-round((42.25-lat+2*pad)/base.STEP):]
            a=base.write_asset(f"{pack['id']}_{lat}_{lon:+d}",detail,bounds,'detail')
            a['core_bounds_lon_lat']=list(core); assets.append(a); print('Built',a['id'],flush=True)
    full.flush(); width,height=pack['size']; coarse=np.empty((height,width,4),dtype='float32')
    for c in range(4): coarse[:,:,c]=np.asarray(Image.fromarray(full[:,:,c]).resize((width,height),Image.Resampling.BOX))
    assets.insert(0,base.write_asset(pack['id']+'_base',coarse,pack['bounds'],'base'))
    catalogue(pack,assets,reused)
    Image.fromarray(np.uint8(np.clip(coarse[:,:,:3]*(.4+coarse[:,:,3,None]),0,1)*255)).save(work/'preview.png')
    summary=dict(files=len(assets),bytes=sum(a['bytes'] for a in assets),reused_france_cores=reused)
    (work/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf8'); print(summary,flush=True)


if __name__=='__main__':
    for pack in PACKS:
        acquire(pack)
        if '--acquire-only' not in sys.argv: build(pack)
