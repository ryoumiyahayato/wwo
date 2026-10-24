"""Arabia, then North Africa; shared source extraction and fixed terrain kernel.

WorldCover60 means bare/sparse, never an invented sand/rock or oasis map.
The common geographic overview retains the entire admitted R52 visual support.
"""
if __name__ == '__main__':
    from generation_policy import enter
    from pathlib import Path as GenerationPath
    enter(GenerationPath(__file__).resolve().parents[2], 'arid_surface_r53.json')

from pathlib import Path
import sys,json
import numpy as np
from shapely.geometry import shape,box
from shapely.strtree import STRtree
import build_france_surface_r42 as common
import build_siberian_surface_r50 as sib
import build_asian_surface_r51 as asian
import build_northern_surface_r52 as northern

ROOT=common.ROOT;WORK=ROOT/'local-artifacts/arid-surface-r53'
ARABIA=(34,10,62,34);AFRICA=(-20,14,40,38)
ARABIA_FINE={(46,24),(44,20),(44,22),(42,28),(40,28),(40,24),(42,18),(42,16),
 (44,14),(44,16),(46,14),(48,14),(54,16),(56,22),(58,22),(54,22),(48,20),(50,18),(48,28),(50,26),(56,24)}
AFRICA_FINE={(-6,30),(-8,30),(-6,32),(-4,32),(-6,34),(-4,34),(-10,28),
 (2,34),(4,34),(6,34),(6,32),(8,34),(8,32),(10,32),(4,22),(6,22),(8,24),
 (10,24),(12,24),(14,26),(20,32),(22,30),(26,28),(24,28),(28,26),
 (30,24),(30,26),(30,28),(30,30),(32,30),(32,28),(32,26),(32,24),(32,22),
 (34,28),(34,26),(34,24),(34,20),(30,18)}
CACHES=[WORK]+northern.CACHE_DIRS;RESOLVED={}

def arabia(x,y):
    s=common.smooth
    north=34-6*s(48,54,x)
    return s(34,36,x)*(1-s(60,62,x))*s(10,12,y)*(1-s(north-2,north,y))

def africa(x,y):
    s=common.smooth
    # Geographic transition only: no claim to complete the Sahel or Sudan.
    south=18-4*s(28,34,x)
    return s(-20,-18,x)*(1-s(38,40,x))*s(south,south+2,y)*(1-s(36,38,y))

def coverage(x,y):return np.maximum(arabia(x,y),africa(x,y))

def resolve(kind,x,y):
    key=(kind,x,y)
    if key not in RESOLVED:
        RESOLVED[key]=next((p for root in CACHES if (p:=root/kind/f'{y:+03d}_{x:+04d}.tif').exists() and p.with_suffix('.json').exists()),None)
    return RESOLVED[key]

def configure():
    asian.WORK=WORK;asian.resolve=resolve;asian.RESOLVED=RESOLVED

def acquire(stage):
    configure();b,fn,fine=(ARABIA,arabia,ARABIA_FINE) if stage=='arabia' else (AFRICA,africa,AFRICA_FINE)
    asian.acquire(stage,b,fn,fine);RESOLVED.clear()

def make(b,size,fine=False):return sib.make_field(b,size,fine,resolve,asian.sample,coverage)[0]

def build(stage):
    configure();RESOLVED.clear();WORK.mkdir(parents=True,exist_ok=True)
    b,fn,fine=(ARABIA,arabia,ARABIA_FINE) if stage=='arabia' else (AFRICA,africa,AFRICA_FINE)
    previous={}
    for name in ['northern_surface_r52.json','asian_surface_r51.json']:
        doc=json.loads((ROOT/'data/presentation'/name).read_text(encoding='utf8'))
        for fact in doc['evidence_catalog']['facts']:
            for a in fact['value']['assets']:
                if a['surface_role']=='detail':previous.setdefault(tuple(a['core_bounds_lon_lat'][:2]),[]).append(a)
    land=STRtree([shape(f['geometry']) for f in json.loads((ROOT/'local-artifacts/paris-land-pilot-r1/research/ne_10m_land_v512.geojson').read_text(encoding='utf8'))['features']])
    assets=[];reused=[]
    for y in range(b[1],b[3],2):
        for x in range(b[0],b[2],2):
            core=(x,y,x+2,y+2)
            if not asian.intersects(core,fn) or not len(land.query(box(*core),predicate='intersects')):continue
            old=previous.get((x,y),[]);fine_here=(x,y) in (ARABIA_FINE|AFRICA_FINE) or any(a['height']>=1088 for a in old)
            pad=32/512 if fine_here else 4/60;bounds=(x-pad,y-pad,x+2+pad,y+2+pad);size=(1088,1088) if fine_here else (128,128)
            data=northern.overlay_old(make(bounds,size,fine_here),bounds,old)
            a=common.write_asset(f'arid_r53_{y}_{x:+d}',data,bounds,'detail')
            a.update(core_bounds_lon_lat=list(core),core_inset_degrees=pad,surface_encoding=5,surface_group='arid_r53',surface_support_fraction=float(data[:,:,3].mean()),dem_source='GLO90-DSM-with-ETOPO-gap-reference' if fine_here else 'ETOPO2022-60s',channels='Fixed R50 absolute-height and metric hillshade; independently observed WC2021 classes. Bare/sparse is not a sand, salt or rock subtype. No water inferred from height.')
            if old:a['surface_replaces']=[v['id'].split(':',1)[1] for v in old]
            assets.append(a)
            if len(assets)%40==0:print(stage,'packs',len(assets),flush=True)
    (WORK/f'{stage}_assets.json').write_text(json.dumps(assets,indent=2),encoding='utf8')
    print(stage,'finished',len(assets),'fine',sum(a['height']>=1088 for a in assets),flush=True)

def finish():
    configure();RESOLVED.clear()
    doc=json.loads((ROOT/'data/presentation/northern_surface_r52.json').read_text(encoding='utf8'))
    old=next(a for f in doc['evidence_catalog']['facts'] for a in f['value']['assets'] if a['id']=='physical_relief:euro_north_r52_base')
    b=(-28,10,62,86);size=(2700,2280)
    data=northern.overlay_old(make(b,size),b,[old])
    base=common.write_asset('euro_afro_arabia_r53_base',data,b,'base')
    base.update(surface_encoding=5,surface_group='arid_r53',surface_feather_degrees=[0,0,0,0],dem_source='ETOPO2022-60s plus retained R52 visual support')
    assets=[base]
    # Shared Red Sea cores are generated once per final geographic ID. The
    # second phase may refine an unpublished first-phase core, never keep two.
    cores={}
    for stage in ['arabia','africa']:
        for a in json.loads((WORK/f'{stage}_assets.json').read_text(encoding='utf8')):cores[a['id']]=a
    assets.extend(cores.values())
    occupied={tuple(a['core_bounds_lon_lat'][:2]) for a in assets if a['surface_role']=='detail' and a['surface_support_fraction']>=.99}
    for f in doc['evidence_catalog']['facts']:
        for a in f['value']['assets']:
            if a['id']==old['id']:a['surface_role']='source_base'
            if a['surface_role']=='detail' and tuple(a['core_bounds_lon_lat'][:2]) in occupied:a['surface_role']='source_detail'
    src=dict(doc['source_registry']['sources'][-1]);src.update(source_id='arid_surface_r53',title='Arabian Peninsula and North Africa, shared Europe/Caucasus geographic overview',version='ETOPO2022+GLO90+WC2021:R53')
    src['access_metadata']=dict(src['access_metadata'],sampling='120arcsec shared overview,60arcsec ordinary cores, selected6arcsec DSM extracts resampled1/512degree',cover_semantics='WorldCover2021 classes only.60=bare/sparse; no sand/rock/salt subclass inferred.80 water remains neutral. No1900 oasis/irrigation extent inferred.',reuse='OriginalR52 visual support composited; R42-R52 extraction caches and source-affine kernel reused')
    fact=dict(doc['evidence_catalog']['facts'][-1],fact_id='physical_relief:arid_r53',subject_id='physical_relief:arabia_north_africa_reference',value=dict(status='PHYSICAL_REFERENCE',assets=assets),source_id=src['source_id'],source_version=src['version'],source_locator=src['locator'],spatial_scope=dict(kind='geographic_reference',id='arabia_north_africa_bounded_sahara_nile_transition'),generator='tools/map/build_arid_surface_r53.py',methodology='SharedR50 material and actual source affines. Independent observed cover, no inferred permanent water or1900 land use. ExistingR52 reference retained in common overview.')
    doc['source_registry']['sources'].append(src);doc['evidence_catalog']['facts'].append(fact)
    target=ROOT/'data/presentation/arid_surface_r53.json';target.write_text(json.dumps(doc,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    summary=dict(files=len(assets),bytes=sum(a['bytes'] for a in assets),fine=sum(a.get('height',0)>=1088 and a['surface_role']=='detail' for a in assets),catalogue_bytes=target.stat().st_size,overview=dict(width=base['width'],height=base['height'],decoded_bytes=base['decoded_bytes']))
    (WORK/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf8');print(summary,flush=True)

if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf8');stage=sys.argv[1]
    if stage=='finish':finish()
    else:
        if '--build-only' not in sys.argv:acquire(stage)
        if '--acquire-only' not in sys.argv:build(stage)
