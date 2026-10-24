"""Benelux geographic material, reusing existing DEM and canonical GPU tiles.

No country-specific terrain runtime or political clipping of elevations.
"""
import json, sys
import numpy as np
from PIL import Image
from shapely.geometry import shape, box
from shapely.ops import unary_union
import build_spain_surface_r45 as production

base=production.base; material=production.material; ROOT=base.ROOT
WORK=ROOT/'local-artifacts/benelux-surface-r46'
PACK=dict(id='benelux_r46',bounds=(2.,48.,8.,56.),size=(768,1024),encoding=2,feather=[.65,.7,.65,1.2])
production.WORK=WORK


def build():
    work,dims=production.configure(PACK); w,s,e,n=PACK['bounds']
    base.HEIGHT=base.mosaic('dem'); base.TREES=np.zeros(dims,dtype='uint8')
    material.COLOUR=material.colour_mosaic(); material.DOMAIN=np.ones(dims,dtype='uint8')
    raw=json.loads((ROOT/'data/world_map/historical/cshapes_1900_snapshot.json').read_text(encoding='utf8'))
    countries=[f for f in raw['features'] if f['gwcode'] in [210,211,212]]
    if len(countries)!=3: raise ValueError('Expected three existing sovereign country references')
    scope=unary_union([shape(f['geometry']) for f in countries]).intersection(box(*PACK['bounds'])).buffer(.6)
    german=json.loads((ROOT/'data/presentation/german_surface_r44.json').read_text(encoding='utf8'))['evidence_catalog']['facts'][0]['value']['assets']
    reusable={tuple(a['core_bounds_lon_lat']):a for a in german if a['surface_role']=='detail'}
    full=np.lib.format.open_memmap(work/'field.npy',mode='w+',dtype='float32',shape=(*dims,4))
    assets=[]; shared_ids=[]
    for lat in range(int(s),int(n),2):
        for lon in range(int(w),int(e),2):
            core=(lon,lat,lon+2,lat+2); pad=base.PADDING*base.STEP
            bounds=(lon-pad,lat-pad,lon+2+pad,lat+2+pad); pixels=material.field(bounds)
            row=round((n-lat-2)/base.STEP);col=round((lon-w)/base.STEP)
            full[row:row+1024,col:col+1024]=pixels[32:-32,32:-32]
            if not scope.intersects(box(*core)): continue
            if core in reusable:
                # Same immutable file, same runtime key. Never a second alias
                # that would upload the same texture under another country.
                a=reusable[core].copy();shared_ids.append(a['id'].split(':',1)[1]);assets.append(a)
            else:
                a=base.write_asset(f'benelux_r46_{lat}_{lon:+d}',pixels,bounds,'detail')
                a.update(core_bounds_lon_lat=list(core),surface_group='benelux_r46',surface_encoding=2,
                    channels='RGB observed-cover linear tones and neutral absolute elevation; A fixed DSM hillshade minus .4.')
                assets.append(a)
            print('Shared' if core in reusable else 'Built',a['id'],flush=True)
    full.flush(); coarse=np.empty((1024,768,4),dtype='float32')
    for c in range(4):coarse[:,:,c]=np.asarray(Image.fromarray(full[:,:,c]).resize((768,1024),Image.Resampling.BOX))
    a=base.write_asset('benelux_r46_base',coarse,PACK['bounds'],'base')
    a.update(surface_group='benelux_r46',surface_encoding=2,surface_feather_degrees=PACK['feather'],
        shared_detail_ids=shared_ids,channels='RGB linear observed-cover tones; A fixed DSM hillshade minus .4; independent geographic feather.')
    assets.insert(0,a)
    source=dict(source_id='benelux_modern_surface_r46',title='Belgium, Netherlands and Luxembourg modern geographic DSM and cover reference',
        publisher='Copernicus / ESA / Airbus; ESA WorldCover consortium',version='GLO90-COG+WorldCover2021-v200:R46',license='Copernicus-DEM-GLO90+CC-BY-4.0',
        locator='https://copernicus-dem-90m.s3.amazonaws.com/readme.html',access_metadata=dict(
        horizontal_crs='EPSG:4326 WGS84-G1150, actual source affine',vertical_datum='EGM2008 EPSG:3855 orthometric metres',dem_type='DSM, not bare-earth DTM',
        dem_epoch='TanDEM-X 2011-2015, older gap-fill possible',cover_epoch='ESA WorldCover 2021 v200',
        sampling='Native 3-arcsecond latitude GLO90; averaged 6-arcsecond extraction; 1/512-degree display; cover categorical 16x overview.',
        historical_applicability='Modern reference only, not historical coastline, 1900 land cover or political membership.',
        shared_detail_ids=shared_ids,bounds_lon_lat=list(PACK['bounds']),
        licence_url='https://dataspace.copernicus.eu/sites/default/files/media/files/2025-06/copernicus_contributing_mission_data_access_v2_cop_dem_licenses.pdf',
        cover_source='https://esa-worldcover.org/en/data-access',cover_doi='https://doi.org/10.5281/zenodo.7254221'))
    fact=dict(fact_id='physical_relief:benelux_r46',domain='physical_reference_content',subject_id='physical_relief:benelux',
        value=dict(status='PHYSICAL_REFERENCE',assets=assets),unit='presentation_relief',source_id=source['source_id'],source_version=source['version'],source_locator=source['locator'],
        observation_period={'from':'2011-01-01','to':'2021-12-31'},spatial_scope=dict(kind='geographic_reference',id='benelux_with_finite_collars'),
        methodology='Shared R42 DEM, R43 independent cover tones and native mips. Canonical R44 detail reuse. No height-to-landcover or historical water inference.',
        confidence=.8,lower_bound=None,upper_bound=None,license=source['license'],review_status='EVIDENCE_LINKED',generator='tools/map/build_benelux_surface_r46.py')
    document=dict(source_registry=dict(schema_id='historical_source_registry_v2',sources=[source]),evidence_catalog=dict(schema_id='historical_fact_evidence_catalog_v2',facts=[fact]))
    (ROOT/'data/presentation/benelux_surface_r46.json').write_text(json.dumps(document,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    summary=dict(new_files=len(assets)-len(shared_ids),new_bytes=sum(v['bytes'] for v in assets if v['id'].split(':',1)[1] not in shared_ids),
        shared_detail_ids=shared_ids,descriptors=len(assets))
    (work/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf8')
    Image.fromarray(np.uint8(np.clip(coarse[:,:,:3]*(.4+coarse[:,:,3,None]),0,1)*255)).save(work/'preview.png')
    print(summary,flush=True)


if __name__=='__main__':
    production.acquire(PACK); build()
