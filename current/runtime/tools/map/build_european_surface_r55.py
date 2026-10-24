"""European Russia derivatives and a continuous shared regional overview.

Reuses the R42/R50 extraction, material and native-Mip contract. No political
polygon, water topology or simulation record is generated here.
"""
import json,sys
import numpy as np
from scipy.ndimage import map_coordinates
from shapely.geometry import shape,box
from shapely.strtree import STRtree
import build_france_surface_r42 as common
import build_siberian_surface_r50 as sib
import build_asian_surface_r51 as asian
import build_northern_surface_r52 as northern

ROOT=common.ROOT;WORK=ROOT/'local-artifacts/european-surface-r55'
BOUNDS=(18,40,70,82)
FINE={(36,54),(38,56),(32,56),(34,58),(42,54),(48,54),(46,48),
      (26,50),(28,52),(30,48),(32,46),(34,44),(56,54),(58,58),(58,62),(58,66)}
CACHES=[WORK,ROOT/'local-artifacts/arid-surface-r53']+northern.CACHE_DIRS
RESOLVED={}

def resolve(kind,x,y):
    key=(kind,x,y)
    if key not in RESOLVED:
        RESOLVED[key]=next((p for base in CACHES if (p:=base/kind/f'{y:+03d}_{x:+04d}.tif').exists() and p.with_suffix('.json').exists()),None)
    return RESOLVED[key]

def support(x,y):
    s=common.smooth
    return s(18,20,x)*(1-s(68,70,x))*s(40,42,y)*(1-s(80,82,y))

def configure():
    WORK.mkdir(parents=True,exist_ok=True)
    asian.WORK=WORK;asian.resolve=resolve;asian.RESOLVED=RESOLVED
    sib.PALETTE[70]=[.82,.85,.86]

def acquire():
    configure();asian.acquire('european_russia',BOUNDS,support,FINE);RESOLVED.clear()

def build():
    configure();RESOLVED.clear()
    doc=json.loads((ROOT/'data/presentation/arid_surface_r53.json').read_text(encoding='utf8'))
    previous={}
    # Reuse admitted Finland, Caucasus and Siberian cores, rather than making
    # another national copy. Only extend a core when its support is incomplete.
    for name in ['arid_surface_r53.json','asian_surface_r51.json']:
        d=json.loads((ROOT/'data/presentation'/name).read_text(encoding='utf8'))
        for f in d['evidence_catalog']['facts']:
            for a in f['value']['assets']:
                if a['surface_role']=='detail':previous.setdefault(tuple(a['core_bounds_lon_lat'][:2]),[]).append(a)
    land=STRtree([shape(f['geometry']) for f in json.loads((ROOT/'local-artifacts/paris-land-pilot-r1/research/ne_10m_land_v512.geojson').read_text(encoding='utf8'))['features']])
    existing={};existing_base=None
    target=ROOT/'data/presentation/european_surface_r55.json'
    if '--resume' in sys.argv and target.exists():
        completed=json.loads(target.read_text(encoding='utf8'))
        existing={tuple(a['core_bounds_lon_lat'][:2]):a for a in completed['evidence_catalog']['facts'][-1]['value']['assets'] if a['surface_role']=='detail'}
        existing_base=next(a for a in completed['evidence_catalog']['facts'][-1]['value']['assets'] if a['surface_role']=='base')
    assets=[];reused=[];fine_coverage=[]
    for y in range(BOUNDS[1],BOUNDS[3],2):
        for x in range(BOUNDS[0],BOUNDS[2],2):
            core=(x,y,x+2,y+2)
            if not asian.intersects(core,support) or not len(land.query(box(*core),predicate='intersects')):continue
            old=previous.get((x,y),[])
            fine=(x,y) in FINE or any(a['height']>=1088 for a in old)
            pad=32/512 if fine else 4/60;b=(x-pad,y-pad,x+2+pad,y+2+pad);size=(1088,1088) if fine else (128,128)
            gx,gy=np.meshgrid(np.linspace(x,x+2,9),np.linspace(y,y+2,9));needed=support(gx,gy)
            inherited=None
            for candidate in old:
                if candidate['height']<size[1] or candidate.get('surface_support_fraction',1)<.999:continue
                # Older R50 metadata called partial geographic collars fully
                # supported. Read actual alpha before deciding to reuse one.
                field=northern.europe.decode(candidate);w,s,e,n=candidate['bounds_lon_lat']
                actual=map_coordinates(field[:,:,3],[(n-gy)/(n-s)*field.shape[0]-.5,(gx-w)/(e-w)*field.shape[1]-.5],order=1,mode='nearest')
                encoding=candidate.get('surface_encoding',0)
                if encoding==1:actual=common.smooth(.01,.075,actual)
                elif encoding in (2,3,4):actual=np.ones_like(actual)
                if np.all(actual>=needed-.004):inherited=candidate;break
            if inherited:
                reused.append(inherited['id']);continue
            a=existing.get((x,y))
            if a is None:
                pixels,_=sib.make_field(b,size,fine,resolve,asian.sample,support)
                pixels=northern.overlay_old(pixels,b,old)
                a=common.write_asset(f'european_r55_{y}_{x:+d}',pixels,b,'detail')
                a.update(core_bounds_lon_lat=list(core),core_inset_degrees=pad,surface_encoding=5,surface_group='european_r55',surface_support_fraction=float(pixels[:,:,3].mean()),dem_source='GLO90-DSM-with-ETOPO-gap-reference' if fine else 'ETOPO2022-60s',channels='Fixed absolute-height R50 kernel; independent WC2021 class reference; A geographic support, never water.')
            if old:a['surface_replaces']=[v['id'].split(':',1)[1] for v in old]
            assets.append(a)
            if (x,y) in FINE:
                sources=[(xx,yy) for yy in range(y,y+2) for xx in range(x,x+2) if resolve('dem',xx,yy)]
                fine_coverage.append(dict(core=list(core),source_cells=sources))
            if len(assets)%40==0:print('R55 cores',len(assets),flush=True)
    # Full geographic ETOPO support inside this common overview, including the
    # real R49 gap. No national alpha mask or artificial shoreline. Original
    # R53 supported material is retained; existing detailed packs stay intact.
    bounds=(-28,10,76,86);size=(3120,2280)
    oldbase=next(a for f in doc['evidence_catalog']['facts'] for a in f['value']['assets'] if a['id']=='physical_relief:euro_afro_arabia_r53_base')
    if existing_base is not None:base=existing_base
    else:
        pixels,_=sib.make_field(bounds,size,False,resolve,asian.sample,lambda x,y:np.ones(np.broadcast_shapes(x.shape,y.shape),dtype='float32'))
        pixels=northern.overlay_old(pixels,bounds,[oldbase])
        base=common.write_asset('euro_afro_russia_r55_base',pixels,bounds,'base')
    base.update(surface_encoding=5,surface_group='european_r55',surface_feather_degrees=[0,0,4,0],dem_source='ETOPO2022-60s with retained R53 valid support',surface_support_fraction=1.0,channels='Linear RGB fixed metric hillshade and absolute-height/observed WC2021 material; independent A geographic coverage')
    assets.insert(0,base)
    replaced={v for a in assets for v in a.get('surface_replaces',[])}
    for f in doc['evidence_catalog']['facts']:
        for a in f['value']['assets']:
            if a['id']==oldbase['id']:a['surface_role']='source_base'
            if a['id'].split(':',1)[1] in replaced:a['surface_role']='source_detail'
    template=doc['source_registry']['sources'][-1]
    src=dict(template,source_id='european_surface_r55',title='Continuous shared European Russian regional surface',version='ETOPO2022+GLO90+WC2021:R55')
    src['access_metadata']=dict(template['access_metadata'],bounds_lon_lat=list(BOUNDS),sampling='Shared overview120arcsec, ordinary cores60arcsec, selectedGLO90 extracts6arcsec and display1/512degree',reuse='R52 Finland/Caucasus and R50/51 adjacent cores retained; no modern sovereignty mask',historical_applicability='Modern reference only; no1900 water, cover, sovereignty or economic assertion')
    fact=dict(doc['evidence_catalog']['facts'][-1],fact_id='physical_relief:european_r55',subject_id='physical_relief:european_russia_reference',value=dict(status='PHYSICAL_REFERENCE',assets=assets),source_id=src['source_id'],source_version=src['version'],source_locator=src['locator'],spatial_scope=dict(kind='geographic_reference',id='european_russia_with_finite_neighbours'),generator='tools/map/build_european_surface_r55.py',methodology='Shared R50 source-affine height/metric hillshade kernel, independent WorldCover2021, full common coarse support and selected sourced refinement. Existing terrain and politics retained.')
    doc['source_registry']['sources'].append(src);doc['evidence_catalog']['facts'].append(fact)
    target=ROOT/'data/presentation/european_surface_r55.json';target.write_text(json.dumps(doc,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    summary=dict(files=len(assets),bytes=sum(a['bytes'] for a in assets),fine=sum(a['height']>=1088 and a['surface_role']=='detail' for a in assets),catalogue_bytes=target.stat().st_size,reused_cores=reused,fine_source_coverage=fine_coverage,base=base)
    (WORK/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf8');print({k:v for k,v in summary.items() if k not in ['base','reused_cores','fine_source_coverage']},flush=True)

if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf8')
    if '--build-only' not in sys.argv:acquire()
    if '--acquire-only' not in sys.argv:build()
