"""Caucasus then Nordic geographic surface, existing MapRelief/Mip contract.

Source extraction and fixed material computation use R42/R50/R51 functions.
Original country catalogues, physical topology and political facts stay intact.
"""
if __name__ == '__main__':
    from generation_policy import enter
    from pathlib import Path as GenerationPath
    enter(GenerationPath(__file__).resolve().parents[2], 'northern_surface_r52.json')

from pathlib import Path
import json,math,sys
import numpy as np
from scipy.ndimage import map_coordinates
import build_france_surface_r42 as common
import build_siberian_surface_r50 as sib
import build_asian_surface_r51 as asian
import build_shared_surface_r48 as europe

ROOT=common.ROOT;WORK=ROOT/'local-artifacts/caucasus-nordic-r52'
CAUCASUS=(36,36,54,48);NORDIC=(-76,54,38,86)
CAUCASUS_FINE={(x,y) for x in [40,42,44,46,48] for y in [40,42]}|{(42,38),(44,38),(46,38)}
NORDIC_FINE={(6,58),(6,60),(6,62),(8,60),(8,62),(10,62),(10,64),(12,64),
 (12,66),(14,66),(16,68),(18,68),(20,68),(22,68),(10,56),(14,58),(16,58),
 (24,60),(26,62),(28,66),(-24,64),(-24,66),(-22,64),(-20,64),(-18,64),(-16,64),
 (-20,62),(-18,62),(-16,62),(-8,60),(-8,62),(14,78),(16,78),(20,80),(-52,68),(-44,60),(-22,70)}
CACHE_DIRS=[ROOT/'local-artifacts'/v for v in ['caucasus-nordic-r52','asian-surface-r51','siberian-surface-r50',
 'france-surface-r42','british-surface-r43','german-surface-r44','spain-surface-r45','benelux-surface-r46']]
RESOLVED={}

def resolve(kind,x,y):
    key=(kind,x,y)
    if key not in RESOLVED:
        RESOLVED[key]=next((p for base in CACHE_DIRS if (p:=base/kind/f'{y:+03d}_{x:+04d}.tif').exists() and p.with_suffix('.json').exists()),None)
    return RESOLVED[key]

def caucasus(x,y):
    s=common.smooth
    return s(36,38,x)*(1-s(52,54,x))*s(36,38,y)*(1-s(46,48,y))

def nordic(x,y):
    s=common.smooth
    south=54+4*s(18,24,x)
    scandes=s(2,4,x)*(1-s(34,38,x))*s(south,south+2,y)*(1-s(72,74,y))
    iceland=s(-27,-25,x)*(1-s(-13,-11,x))*s(62,63,y)*(1-s(67,69,y))
    faroe=s(-9,-8,x)*(1-s(-6,-5,x))*s(61,61.5,y)*(1-s(63,64,y))
    svalbard=s(8,10,x)*(1-s(34,38,x))*s(73,75,y)*(1-s(82,84,y))
    west=np.interp(y,[58,60,64,68,72,75,78,81,84,86],[-48,-50,-55,-58,-60,-64,-76,-72,-64,-50])
    greenland=s(west,west+2,x)*(1-s(-12,-10,x))*s(58,60,y)*(1-s(84.5,86,y))
    return np.maximum.reduce(np.broadcast_arrays(scandes,iceland,faroe,svalbard,greenland))

def coverage(x,y):return np.maximum(caucasus(x,y),nordic(x,y))

def configure():
    asian.WORK=WORK;asian.resolve=resolve;asian.RESOLVED=RESOLVED
    # Class70 is observed snow/ice, not an elevation/latitude-derived snowline.
    sib.PALETTE[70]=[.82,.85,.86]

def acquire(stage):
    configure();bounds,fn,fine=(CAUCASUS,caucasus,CAUCASUS_FINE) if stage=='caucasus' else (NORDIC,nordic,NORDIC_FINE)
    asian.acquire(stage,bounds,fn,fine);RESOLVED.clear()

def make(bounds,size,fine=False):
    return sib.make_field(bounds,size,fine,resolve,asian.sample,coverage)[0]

def overlay_old(pixels,bounds,assets):
    w,s,e,n=bounds;ny,nx=pixels.shape[:2]
    x,y=np.meshgrid(w+(np.arange(nx)+.5)*(e-w)/nx,n-(np.arange(ny)+.5)*(n-s)/ny)
    for old in assets:
        data=europe.decode(old);ow,os,oe,on=old['bounds_lon_lat']
        coord=[(on-y)/(on-os)*data.shape[0]-.5,(x-ow)/(oe-ow)*data.shape[1]-.5]
        field=np.stack([map_coordinates(data[:,:,i],coord,order=1,mode='nearest') for i in range(4)],axis=-1)
        encoding=old.get('surface_encoding',0)
        if encoding==5:alpha=field[:,:,3];baked=field[:,:,:3]
        elif encoding:
            alpha=common.smooth(.01,.075,field[:,:,3]) if encoding==1 else np.ones((ny,nx))
            baked=field[:,:,:3]*(.4+field[:,:,3:4])
        else:
            alpha=field[:,:,3];t=common.smooth(.2,.95,field[:,:,0])[:,:,None]
            tone=np.array([.57,.57,.46])*(1-t)+np.array([.70,.68,.62])*t
            trees=field[:,:,2:3]*.78;tone=tone*(1-trees)+np.array([.27,.38,.27])*trees
            baked=tone*(.4+field[:,:,1:2])
        alpha=alpha*((x>=ow)&(x<=oe)&(y>=os)&(y<=on))
        # Retain the old terrain on its valid support; the new geographic
        # collar fills only its uncovered part. No same-core slot competition.
        pixels[:,:,:3]=pixels[:,:,:3]*(1-alpha[:,:,None])+baked*alpha[:,:,None]
        pixels[:,:,3]=np.maximum(pixels[:,:,3],alpha)
    return np.clip(pixels,0,1)

def build(stage,resume=False):
    configure();RESOLVED.clear();WORK.mkdir(parents=True,exist_ok=True)
    bounds,fn,fine=(CAUCASUS,caucasus,CAUCASUS_FINE) if stage=='caucasus' else (NORDIC,nordic,NORDIC_FINE)
    assets=[];reused=[]
    saved=WORK/f'{stage}_assets.json'
    completed={tuple(a['core_bounds_lon_lat'][:2]):a for a in json.loads(saved.read_text(encoding='utf8'))} if resume and saved.exists() else {}
    previous={}
    for catalogue in ['europe_surface_r48.json','asian_surface_r51.json']:
        doc=json.loads((ROOT/'data/presentation'/catalogue).read_text(encoding='utf8'))
        for fact in doc['evidence_catalog']['facts']:
            for a in fact['value']['assets']:
                if a['surface_role']=='detail':previous.setdefault(tuple(a['core_bounds_lon_lat'][:2]),[]).append(a)
    # Only produce geographical cores that intersect actual source land. The
    # ocean globe remains the original physical product, with no ocean tiles.
    from shapely.geometry import shape,box
    from shapely.ops import unary_union
    land_path=ROOT/'local-artifacts/paris-land-pilot-r1/research/ne_10m_land_v512.geojson'
    if not land_path.exists():
        land_path=next((p for p in (ROOT/'local-artifacts').glob('*/source/ne_10m_land.geojson')),None)
    if land_path is None:raise FileNotFoundError('Retained Natural Earth10m land source is required')
    from shapely.strtree import STRtree
    land=STRtree([shape(f['geometry']) for f in json.loads(land_path.read_text(encoding='utf8'))['features']])
    for y in range(bounds[1],bounds[3],2):
        for x in range(bounds[0],bounds[2],2):
            core=(x,y,x+2,y+2)
            if not asian.intersects(core,fn) or not len(land.query(box(*core),predicate='intersects')):continue
            upstream=previous.get((x,y),[])
            isfine=(x,y) in fine or any(a['height']>=1088 for a in upstream);pad=32/512 if isfine else 4/60
            b=(x-pad,y-pad,x+2+pad,y+2+pad);size=(1088,1088) if isfine else (128,128)
            if upstream:
                lon=b[0]+(np.arange(size[0])+.5)*(b[2]-b[0])/size[0]
                lat=b[3]-(np.arange(size[1])+.5)*(b[3]-b[1])/size[1]
                needed=coverage(lon[None,:],lat[:,None])
                inherited=None
                for candidate in sorted(upstream,key=lambda a:-a['height']):
                    if candidate['height']<size[1]:continue
                    old=overlay_old(np.zeros((size[1],size[0],4),dtype='float32'),b,[candidate])
                    if np.all(old[:,:,3]>=needed-.004):inherited=candidate;break
                if inherited:
                    reused.append(inherited['id']);continue
            ready=completed.get((x,y))
            if ready and ready['bounds_lon_lat']==list(b) and (ROOT/ready['path'][6:]).exists():
                assets.append(ready);continue
            pixels=overlay_old(make(b,size,isfine),b,upstream)
            a=common.write_asset(f'northern_r52_{y}_{x:+d}',pixels,b,'detail')
            gx,gy=np.meshgrid(np.linspace(x,x+2,9),np.linspace(y,y+2,9))
            a.update(core_bounds_lon_lat=list(core),core_inset_degrees=pad,surface_encoding=5,surface_group='northern_r52',
                surface_support_fraction=float(pixels[:,:,3].mean()),dem_source='GLO90-DSM-with-ETOPO-gap-reference' if isfine else 'ETOPO2022-60s',
                channels='Shared absolute-height material; RGB fixed metric hillshade and independent WC2021; A geographic support.')
            if upstream:a['surface_replaces']=[v['id'].split(':',1)[1] for v in upstream]
            assets.append(a)
            if len(assets)%50==0:print(stage,'built',len(assets),flush=True)
    (WORK/f'{stage}_assets.json').write_text(json.dumps(assets,indent=2),encoding='utf8')
    (WORK/f'{stage}_reused.json').write_text(json.dumps(reused,indent=2),encoding='utf8')
    print(stage,'packs',len(assets),'GLO90',sum(a['dem_source'].startswith('GLO90') for a in assets),'reused',len(reused),flush=True)

def compose_overview(name,b,size,old=None):
    pixels=make(b,size)
    if old:
        # Retain the admitted R48 visual interpretation on its original support.
        # Decode its fixed shade before combining with baked RGB encoding5.
        w,s,e,n=b;nx,ny=size;x,y=np.meshgrid(w+(np.arange(nx)+.5)*(e-w)/nx,n-(np.arange(ny)+.5)*(n-s)/ny)
        data=europe.decode(old);ow,os,oe,on=old['bounds_lon_lat']
        coord=[(on-y)/(on-os)*data.shape[0]-.5,(x-ow)/(oe-ow)*data.shape[1]-.5]
        field=np.stack([map_coordinates(data[:,:,i],coord,order=1,mode='nearest') for i in range(4)],axis=-1)
        alpha=common.smooth(.01,.075,field[:,:,3])*((x>=ow)&(x<=oe)&(y>=os)&(y<=on))
        for amount,distance in zip(old.get('surface_feather_degrees',[0]*4),[x-ow,y-os,oe-x,on-y]):
            if amount:alpha*=common.smooth(0,amount,distance)
        baked=field[:,:,:3]*(.4+field[:,:,3:4])
        pixels[:,:,:3]=pixels[:,:,:3]*(1-alpha[:,:,None])+baked*alpha[:,:,None]
        pixels[:,:,3]=np.maximum(pixels[:,:,3],alpha)
    a=common.write_asset(name,pixels,b,'base');a.update(surface_encoding=5,surface_group='northern_r52',dem_source='ETOPO2022-60s plus retained R48 material',surface_feather_degrees=[0,0,0,0]);return a

def finish():
    configure();RESOLVED.clear()
    previous=json.loads((ROOT/'data/presentation/europe_surface_r48.json').read_text(encoding='utf8'))
    old=next(a for f in previous['evidence_catalog']['facts'] for a in f['value']['assets'] if a['id']=='physical_relief:europe_r48_base')
    assets=[compose_overview('euro_north_r52_base',(-28,34,60,86),(2640,1560),old)]
    if (WORK/'nordic_assets.json').exists():
        macro=compose_overview('greenland_r52_base',(-76,58,-10,86),(1980,840))
        macro.update(surface_display_max_mpp=60000.,surface_fade_mpp=35000.)
        assets.append(macro)
    for st in ['caucasus','nordic']:
        p=WORK/f'{st}_assets.json'
        if p.exists():assets.extend(json.loads(p.read_text(encoding='utf8')))
    reused=set()
    for st in ['caucasus','nordic']:
        p=WORK/f'{st}_reused.json'
        if p.exists():reused.update(json.loads(p.read_text(encoding='utf8')))
    asian_doc=json.loads((ROOT/'data/presentation/asian_surface_r51.json').read_text(encoding='utf8'))
    used_sources=set()
    for f in asian_doc['evidence_catalog']['facts']:
        selected=[a for a in f['value']['assets'] if a['id'] in reused]
        if selected:
            previous['evidence_catalog']['facts'].append(dict(f,value=dict(f['value'],assets=selected)))
            used_sources.add(f['source_id'])
    previous['source_registry']['sources'].extend(s for s in asian_doc['source_registry']['sources'] if s['source_id'] in used_sources)
    occupied={tuple(a['core_bounds_lon_lat'][:2]):a for a in assets if a['surface_role']=='detail'}
    # New geographical cores only replace old alternatives where their whole
    # support is available. Original catalogues and binary files are retained.
    retained=0
    for f in previous['evidence_catalog']['facts']:
        for a in f['value']['assets']:
            if a['surface_role']!='detail':continue
            key=tuple(a['core_bounds_lon_lat'][:2]);new=occupied.get(key)
            if new and new['surface_support_fraction']>=.99:a['surface_role']='source_detail'
            else:retained+=1
    src=json.loads((ROOT/'data/presentation/asian_surface_r51.json').read_text(encoding='utf8'))['source_registry']['sources'][-1]
    src=dict(src,source_id='northern_surface_r52',title='Caucasus and Nordic surface with original R48 visual support',version='ETOPO2022+GLO90+WC2021:R52')
    src['access_metadata'].update(sampling='120arcsec overview,60arcsec ordinary cores, selected6arcsec DSM resampled1/512degree',ice_surface='ETOPO2022 Ice Surface, not subglacial bedrock; observed WC2021 class70 only, not1900 ice margins',reuse='R42-R51 cached sources; original R48 visual support composited, original detail assets retained')
    fact=dict(previous['evidence_catalog']['facts'][-1],fact_id='physical_relief:northern_r52',subject_id='physical_relief:caucasus_nordic_reference',value=dict(status='PHYSICAL_REFERENCE',assets=assets),source_id=src['source_id'],source_version=src['version'],source_locator=src['locator'],spatial_scope=dict(kind='geographic_reference',id='caucasus_scandinavia_iceland_greenland_finite_collars'),observation_period={'from':'1998-01-01','to':'2022-12-31'},generator='tools/map/build_northern_surface_r52.py',methodology='Existing R50 source-affine metric hillshade and independent observed classes. Shared European/Nordic overview, bounded Greenland overview, selected geographic cores. Modern reference only.')
    previous['source_registry']['sources'].append(src);previous['evidence_catalog']['facts'].append(fact)
    target=ROOT/'data/presentation/northern_surface_r52.json';target.write_text(json.dumps(previous,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    summary=dict(files=len(assets),bytes=sum(a['bytes'] for a in assets),fine=sum(a.get('dem_source','').startswith('GLO90') for a in assets),retained_old_details=retained,reused_old_cores=len(reused),catalogue_bytes=target.stat().st_size,overviews=[dict(id=a['id'],width=a['width'],height=a['height'],decoded_bytes=a['decoded_bytes']) for a in assets if a['surface_role']=='base'])
    (WORK/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf8');print(summary,flush=True)

if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf8');stage=sys.argv[1]
    if stage=='finish':finish()
    else:
        if '--build-only' not in sys.argv:acquire(stage)
        if '--acquire-only' not in sys.argv:build(stage,'--reuse-existing' in sys.argv)
