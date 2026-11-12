"""Finite R57 offline repair. Optional explicit4-cell acquisition; no world state.

Encoding6 keeps the observed shaded RGB and an independently calculated neutral
DEM print luminance in A. Geographic support is rectangular with explicit core
collars, not an overloaded land-cover mask. Mips average material channels.
"""
import copy,json,math,struct,sys,zlib,time
from functools import lru_cache

def repair_shared_precision(root):
    """Recover declared DEM spacing through existing shared-source records.

    This changes selection metadata only. It does not infer source pixels,
    recover unknown cover precision or expand geographic support.
    """
    from pathlib import Path
    path=Path(root)/'data/presentation/sampling_surface_r57.json'
    doc=json.loads(path.read_text(encoding='utf-8'))
    assets=[a for f in doc['evidence_catalog']['facts'] for a in f.get('value',{}).get('assets',[])]
    byid={a['id']:a for a in assets}
    changed=[]
    for _ in range(3):
        for a in assets:
            p=a.get('precision',{})
            b=a.get('bounds_lon_lat',[])
            if len(b)!=4 or b[0]>=8.5 or b[2]<=-5.5 or b[1]>=51.5 or b[3]<=42:continue
            if p.get('dem_extract_m_ns',0)>0:continue
            ids=a.get('upstream_asset_ids',[]) or ([a['source_asset']] if a.get('source_asset') else [])
            sources=[byid.get(i,{}) for i in ids]
            values=[s.get('precision',{}).get('dem_extract_m_ns',0) for s in sources]
            if not values or min(values)<=0:continue
            p['dem_extract_m_ns']=max(values)
            p['dem_precision_sources']=ids
            p['source_note']='DEM spacing inherited from the existing declared upstream assets. Geographic NoData/support and unknown cover precision remain unchanged; no new source measurement.'
            a['precision']=p;changed.append(a['id'])
    path.write_text(json.dumps(doc,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'metadata_records':len(changed),'pixel_changes':0,'new_acquisition':False}))

def repair_overview_grid(root):
    """Finite Europe RGB repair from admitted R57 pages; retain all DEM alpha."""
    from PIL import Image
    from pathlib import Path
    import numpy as np
    catalog = root/'data/presentation/sampling_surface_r57.json'
    doc = json.loads(catalog.read_text(encoding='utf-8'))
    assets = [a for f in doc['evidence_catalog']['facts'] for a in f.get('value',{}).get('assets',[])]
    base = next(a for a in assets if a['id']=='physical_relief:euro_afro_russia_r57_continuity_base')
    pages = [a for a in assets if a['id'].startswith('physical_relief:repair_r57_mid8_r56_')
             and a['core_bounds_lon_lat'][0]>=-16 and a['core_bounds_lon_lat'][2]<=32]
    if len(pages)!=24:
        raise ValueError('Expected the existing 24 eight-degree Europe cores, without source substitution')
    def decode(asset):
        payload = (root/asset['path'].removeprefix('res://')).read_bytes()
        if payload[:8]!=b'FRT42\0\0\0': raise ValueError('Expected original FRT42 format')
        width,height,size = struct.unpack_from('<III',payload,8)
        raw = zlib.decompress(payload[20:])
        if len(raw)!=size or [width,height]!=[asset['width'],asset['height']]:
            raise ValueError('Source dimensions or decoded size changed')
        return width,height,raw
    width,height,original = decode(base)
    edited = np.frombuffer(original[:width*height*4],np.uint8).reshape(height,width,4).copy()
    for page in pages:
        pw,ph,raw = decode(page)
        bounds = page['bounds_lon_lat']; w,s,e,n = page['core_bounds_lon_lat']
        crop = (round((w-bounds[0])*pw/(bounds[2]-bounds[0])),
                round((bounds[3]-n)*ph/(bounds[3]-bounds[1])),
                round((e-bounds[0])*pw/(bounds[2]-bounds[0])),
                round((bounds[3]-s)*ph/(bounds[3]-bounds[1])))
        source = np.frombuffer(raw[:pw*ph*4],np.uint8).reshape(ph,pw,4)
        x,y = round((w+28)*30),round((86-n)*30)
        # Float area reduction preserves the actual source colours, without
        # guessing material classes, blurring coastlines or altering geometry.
        for channel in range(3):
            core = Image.fromarray(source[:,:,channel].astype(np.float32)).crop(crop)
            reduced = np.asarray(core.resize((240,240),Image.Resampling.BOX))
            edited[y:y+240,x:x+240,channel]=np.clip(np.rint(reduced),0,255).astype(np.uint8)
    result = bytearray(original)
    result[:width*height*4]=edited.tobytes()
    rgb = edited[:,:,:3].copy()
    mask = Image.new('L',(width,height),0)
    mask.paste(255,(360,660,1800,1620)) # [-16,32,32,64] in the original overview.
    offset = width*height*4; mw,mh = width,height
    while mw>1 or mh>1:
        mw,mh=max(1,mw//2),max(1,mh//2)
        next_rgb=np.empty((mh,mw,3),np.uint8)
        for channel in range(3):
            reduced=np.asarray(Image.fromarray(rgb[:,:,channel].astype(np.float32)).resize((mw,mh),Image.Resampling.BOX))
            next_rgb[:,:,channel]=np.clip(np.rint(reduced),0,255).astype(np.uint8)
        mask=mask.resize((mw,mh),Image.Resampling.BOX)
        level=np.frombuffer(original[offset:offset+mw*mh*4],np.uint8).reshape(mh,mw,4).copy()
        selected=np.asarray(mask)>0
        level[:,:,:3][selected]=next_rgb[selected]
        result[offset:offset+mw*mh*4]=level.tobytes()
        rgb=next_rgb; offset+=mw*mh*4
    if offset!=len(original): raise ValueError('Unexpected original mip chain')
    name='euro_afro_russia_r65_gridfree_base'
    output=root/'assets/maps/relief'/f'{name}.bin'
    encoded=b'FRT42\0\0\0'+struct.pack('<III',width,height,len(result))+zlib.compress(result,9)
    output.write_bytes(encoded)
    asset=copy.deepcopy(base)
    asset.update(id='physical_relief:'+name,path='res://assets/maps/relief/'+name+'.bin',bytes=len(encoded),
                 surface_replaces=['euro_afro_russia_r57_continuity_base'],
                 source_assets=[base['id']]+[a['id'] for a in pages])
    asset['grid_correction']={'bounds':[-16,32,32,64],
        'method':'Area-reduced admitted R57 eight-degree core RGB; preserve original DEM alpha in every mip and unmodified RGB outside support.',
        'historical_applicability':'Modern physical reference, not 1900 land use or historical water boundaries'}
    asset['precision']['cover_method']='Existing R57 observed European core RGB reduced to the original overview grid inside declared correction; original source bounds elsewhere.'
    src=copy.deepcopy(doc['source_registry']['sources'][-1])
    src.update(source_id='terrain_overview_grid_r65',title='Finite European overview RGB repair from existing R57 cores',version='R65',
               publisher='WWO derived display / admitted R57 upstream sources',locator='res://data/presentation/sampling_surface_r57.json')
    src['access_metadata']={'inputs':asset['source_assets'],'new_acquisition':False,'method':asset['grid_correction']}
    fact=copy.deepcopy(doc['evidence_catalog']['facts'][-1])
    fact.update(fact_id='physical_relief:overview_grid_r65',source_id=src['source_id'],source_version='R65',
                subject_id='physical_relief:europe_overview_rgb',source_locator=src['locator'],
                spatial_scope={'kind':'geographic_reference','id':'europe_overview_rgb_correction','bounds_lon_lat':[-16,32,32,64]},
                methodology=asset['grid_correction']['method'],generator='tools/map/build_surface_r57.py --repair-overview-grid')
    fact['value']['assets']=[asset]
    doc['source_registry']['sources']=[s for s in doc['source_registry']['sources'] if s['source_id']!=src['source_id']]+[src]
    doc['evidence_catalog']['facts']=[f for f in doc['evidence_catalog']['facts'] if f['fact_id']!=fact['fact_id']]+[fact]
    catalog.write_text(json.dumps(doc,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'output':str(output),'pages':len(pages),'bytes':len(encoded),'decoded_bytes':len(result),'new_acquisition':False}))

if __name__ == '__main__':
    if '--repair-shared-precision' in sys.argv:
        from pathlib import Path as GenerationPath
        repair_shared_precision(GenerationPath(__file__).resolve().parents[2])
        raise SystemExit(0)
    from generation_policy import enter
    from pathlib import Path as GenerationPath
    enter(GenerationPath(__file__).resolve().parents[2], 'sampling_surface_r57.json')
    if '--repair-overview-grid' in sys.argv:
        repair_overview_grid(GenerationPath(__file__).resolve().parents[2])
        raise SystemExit(0)

from pathlib import Path
import numpy as np
import rasterio
from rasterio.enums import Resampling
from rasterio.transform import from_bounds
from rasterio.warp import reproject
from scipy.ndimage import gaussian_filter
import build_surface_r56 as prev
import build_european_surface_r55 as euro
import build_siberian_surface_r50 as sib
from generation_policy import require_inputs

ROOT=prev.ROOT;WORK=ROOT/'local-artifacts/terrain-r57'
# R45/R46 keep pack-specific source folders. Their parent is not a raster
# cache; skipping this level silently replaces real cached DSM with ETOPO.
CACHES=[WORK,ROOT/'local-artifacts/spain-surface-r45/spain_r45',ROOT/'local-artifacts/spain-surface-r45/canary_r45',ROOT/'local-artifacts/benelux-surface-r46/benelux_r46',prev.WORK]+euro.CACHES
DOC=ROOT/'data/presentation/sampling_surface_r56.json'

def save(p,v):prev.save(p,v)
def read(p):return prev.read(p)
def key(a):return a['id'].split(':',1)[1]

@lru_cache(None)
def choices(kind,x,y):
    out=[]
    for base in CACHES:
        for source_kind in ([kind,'trees'] if kind=='cover' else [kind]):
            p=base/source_kind/f'{y:+03d}_{x:+04d}.tif'
            if p.exists():
                with rasterio.open(p) as src:
                    out.append((abs(src.transform.e),p,list(src.bounds),src.width,src.height))
    return sorted(out,key=lambda v:v[0])

def field(bounds,size,fine=True,read_cover=True,inputs=None):
    w,s,e,n=bounds;nx,ny=size
    if inputs is not None:
        inputs.validate(bounds,size,read_cover)
        h,dem=inputs.height(bounds,size,fine)
    else:h=sib.sample(sib.ETOPO,bounds,size);dem=[]
    cover=[]
    xx,yy=np.meshgrid(w+(np.arange(nx)+.5)*(e-w)/nx,n-(np.arange(ny)+.5)*(n-s)/ny)
    # DEM source spacing is retained by actual geocell. No global GLO fetch.
    for y in ([] if inputs is not None else range(math.floor(s),math.ceil(n))):
        for x in range(math.floor(w),math.ceil(e)):
            cc=choices('dem',x,y) if fine else []
            if not cc:continue
            step,p,b,sw,sh=cc[0]
            data=sib.sample(p,bounds,size);valid=np.isfinite(data);h[valid]=data[valid]
            dem.append(dict(path=str(p.relative_to(ROOT)),bounds=b,spacing_m_ns=step*111195))
    if not np.isfinite(h).all():raise ValueError('DEM has missing output support; no BIN may be written')
    lat=n-(np.arange(ny)+.5)*(n-s)/ny
    sm=gaussian_filter(h,.65);gy,gx=np.gradient(sm)
    gx/=111195*(e-w)/nx*np.cos(np.deg2rad(lat))[:,None];gy/=-111195*(n-s)/ny
    shade=np.clip(1+(((.45*(1.5*gx-1.5*gy+.70710678)+.55*(-1.5*gx-1.5*gy+.70710678))/np.sqrt(1+9*(gx*gx+gy*gy)))-.70710678)*1.7,.48,1.32)
    observed=np.broadcast_to(sib.PALETTE[0],(ny,nx,3)).copy()
    if inputs is not None and read_cover:observed,cover=inputs.colour(bounds,size)
    for y in (range(math.floor(s/3)*3,math.ceil(n/3)*3,3) if read_cover and inputs is None else []):
        for x in range(math.floor(w/3)*3,math.ceil(e/3)*3,3):
            cc=choices('cover',x,y)
            if not cc:continue
            step,p,b,sw,sh=cc[0]
            with rasterio.open(p) as src:
                classes=src.read(1)
                # R42 retains real148m class10 samples under trees/, not cover/.
                # Ignoring this independent source would coarsen French input.
                tree_only=p.parent.name=='trees'
                if tree_only:classes=np.where(classes>=128,10,0).astype('uint8')
                palette=sib.PALETTE[classes]
                rgb=np.full((ny,nx,3),np.nan,dtype='float32')
                for i in range(3):
                    reproject(palette[:,:,i],rgb[:,:,i],src_transform=src.transform,src_crs=src.crs,dst_transform=from_bounds(*bounds,nx,ny),dst_crs='EPSG:4326',dst_nodata=np.nan,resampling=Resampling.average)
                valid=np.isfinite(rgb[:,:,0]);observed[valid]=rgb[valid]
                cover.append(dict(path=str(p.relative_to(ROOT)),bounds=b,shape=[sw,sh],spacing_m_ns=step*111195,method='class10-only presence; other classes unknown' if tree_only else 'categorical palette first, area resampling of colours'))
    level=np.log1p(np.maximum(h,0)/200)/np.log(26);upland=prev.common.smooth(.2,.95,level)
    rgb=(observed*(1-upland[:,:,None]*.4)+np.array([.70,.68,.62])*upland[:,:,None]*.4)*shade[:,:,None]
    # Height and metric slope determine this independent achromatic print.
    neutral=(.57*(1-upland)+.69*upland)*shade
    return np.concatenate([np.clip(rgb,0,1),np.clip(neutral[:,:,None],.1,1)],axis=-1),h,shade,dem,cover

def write(name,p,bounds,out=None):
    if not np.isfinite(p).all() or p.ndim!=3 or p.shape[2]!=4:raise ValueError('Invalid material before BIN write')
    h,w=p.shape[:2];level=p;levels=[]
    while True:
        levels.append(np.uint8(np.clip(level,0,1)*255+.5).tobytes())
        if level.shape[:2]==(1,1):break
        level=prev.resize(level,(max(1,level.shape[1]//2),max(1,level.shape[0]//2)))
    raw=b''.join(levels);path=(prev.common.OUT if out is None else Path(out))/(name+'.bin')
    path.write_bytes(b'FRT42\0\0\0'+struct.pack('<III',w,h,len(raw))+zlib.compress(raw,6))
    dx=(bounds[2]-bounds[0])/w;dy=(bounds[3]-bounds[1])/h
    return dict(id='physical_relief:'+name,path='res://'+path.relative_to(ROOT).as_posix(),format='RGBA8_MIP_DEFLATE',width=w,height=h,decoded_bytes=len(raw),bytes=path.stat().st_size,bounds_lon_lat=list(bounds),surface_role='detail',core_inset_degrees=32*dx,display_spacing_degrees=[dx,dy],surface_encoding=6,surface_support_fraction=1.,channels='RGB observed WC2021 + fixed DEM hillshade; A independent neutral DEM print luminance, NOT geographic or WC alpha. Linear per-channel area Mips.',surface_group='sampling_r57')

def precision(a,dem,cover):
    # Bounds of actual input cells, not output texture size. ETOPO is explicit
    # outside supplied DSM cells. These short records also drive view ranking.
    dc=[dict(bounds=v['bounds'],m=v['spacing_m_ns'],extract_path=v['path'],**{k:v[k] for k in ('provider_key','provider_url') if k in v}) for v in dem]
    cc=[dict(bounds=v['bounds'],m=v['spacing_m_ns'],extract_path=v['path'],shape=v['shape'],meaning=v['method'],**{k:v[k] for k in ('provider_key','provider_url') if k in v}) for v in cover]
    cv=[v['spacing_m_ns'] for v in cover]
    return dict(dem_native_m_ns=93 if dem else 1853.25,dem_extract_m_ns=185.325 if dem else 1853.25,dem_fallback_m_ns=1853.25,dem_cells=dc,cover_cells=cc,cover_m_ns_max=max(cv) if cv else 0,cover_m_ns_min=min(cv) if cv else 0,cover_epoch='2021 v200 modern reference',cover_method='palette before area reduction',output_m_ns=a['display_spacing_degrees'][1]*111195,neutral_channel=True,horizontal_crs='EPSG:4326',vertical_datum='EGM2008 orthometric metres',dem_type='DSM where cached GLO90; ETOPO surface elsewhere')


def require_rebuild_inputs(asset):
    # Existing precision cells are required inputs, not optional cache hints.
    # Restoring ETOPO alone must not downgrade a published GLO/WC successor.
    cells = asset.get('precision', {})
    paths = [sib.ETOPO]
    paths += [c['extract_path'] for kind in ('dem_cells', 'cover_cells') for c in cells.get(kind, [])]
    require_inputs(ROOT, paths, key(asset))

def build():
    WORK.mkdir(parents=True,exist_ok=True)
    doc=read(DOC);aa=prev.assets(doc);result=[];records=[]
    # Repair the existing R56 material pyramid, not a new geographic domain.
    targets=[a for a in aa if key(a).startswith(('fine_r56_','mid8_r56_','mid16_r56_'))]
    # Existing reported representative fine/coarse pair. No new sources fetched.
    targets += [next(a for a in aa if key(a)==f'european_r55_{y}_{x:+d}') for x,y in [(36,54),(38,54),(36,56),(38,56)]]
    # User supplied France/Spain, Warsaw and German-Austrian vicinity. Rebuild
    # only the existing fine consumers of these named representative windows.
    names=['canonical_r56_france_r42_46_'+f'{x:+d}' for x in [0,2,4]]
    names+=['canonical_r56_shared_r48_40_'+f'{x:+d}' for x in [-6,-4]]
    names+=['canonical_r56_shared_r48_42_+0']
    # Both sides of the demonstrated24E seam need the same independent
    # classification weight. Keeping the old western baked colour shifts it.
    names+=[f'canonical_r56_german_r44_{y}_{x:+d}' for y in [50,52] for x in [20,22]]
    targets += [next(a for a in aa if key(a)==name) for name in names]
    refresh=set(next((v.split('=',1)[1].split(',') for v in sys.argv if v.startswith('--refresh=')),[]))
    if '--refresh-cover-readers' in sys.argv:
        for old in targets:
            w,s,e,n=old['bounds_lon_lat']
            if w<13 and e>-13 and s<55 and n>32:refresh.add(key(old))
    current_path=ROOT/'data/presentation/sampling_surface_r57.json'
    current={key(a):a for a in prev.assets(read(current_path))} if current_path.exists() else {}
    # Check the whole selected rebuild before writing its first BIN. Cached
    # metadata reuse needs no source pixels; actual regeneration does.
    for old in targets:
        name='repair_r57_'+key(old)
        if (WORK/(name+'.json')).exists() and key(old) not in refresh:continue
        require_rebuild_inputs(current.get(name,old))
    require_rebuild_inputs(current.get('euro_afro_russia_r57_base',next(a for a in aa if key(a)=='euro_afro_russia_r56_base')))
    for old in targets:
        core=old['core_bounds_lon_lat'];span=core[2]-core[0];step=span/1024;pad=32*step
        bounds=(core[0]-pad,core[1]-pad,core[2]+pad,core[3]+pad)
        name='repair_r57_'+key(old)
        meta=WORK/(name+'.json')
        if meta.exists() and key(old) not in refresh:
            pair=read(meta);pair['asset']['precision']=precision(pair['asset'],pair['dem'],pair['cover']);save(meta,pair);result.append(pair['asset']);records.append(pair);continue
        p,h,shade,dem,cover=field(bounds,(1088,1088))
        a=write(name,p,bounds)
        a.update(core_bounds_lon_lat=core,surface_lod_degrees=int(span),surface_replaces=[key(old)],surface_display_max_mpp=old.get('surface_display_max_mpp',750),surface_fade_mpp=old.get('surface_fade_mpp',300),precision=precision(a,dem,cover),dem_source='Actual cached GLO90 6arcsec cells plus ETOPO60arcsec gaps; see precision.dem_cells',cover_source='Finest existing WC2021 cached categorical extracts; no new network acquisition')
        pair=dict(asset=a,dem=dem,cover=cover,replaces=key(old));save(meta,pair);records.append(pair);result.append(a)
        print('R57 material',len(result),len(targets),key(old),flush=True)
    # The shared fallback also needs a neutral channel at close scale. Keep
    # R56 observed RGB; its coarse information cannot become near classification.
    base=next(a for a in aa if key(a)=='euro_afro_russia_r56_base')
    p=prev.decode(base);neutral,_,_,dem,cover=field(base['bounds_lon_lat'],(base['width'],base['height']),False,False)
    p[:,:,3]=neutral[:,:,3]
    a=write('euro_afro_russia_r57_base',p,base['bounds_lon_lat'])
    a.update(surface_role='base',core_inset_degrees=0,surface_feather_degrees=base['surface_feather_degrees'],surface_replaces=[key(base)],precision=precision(a,dem,cover))
    a['precision'].update(cover_m_ns_max=1483.,cover_m_ns_min=148.,cover_method='Retained R56 mixed-source observed RGB; conservative coarsest-source scale bound, not uniform measured spacing')
    result.append(a)
    replaced={v for a in result for v in a['surface_replaces']}
    # Original records remain provenance inputs; never selected as successors.
    for a in aa:
        if key(a) in replaced:a['surface_role']='source_base' if a['surface_role']=='base' else 'source_detail'
    enrich(aa)
    src=copy.deepcopy(doc['source_registry']['sources'][-1]);src.update(source_id='terrain_sampling_r57',title='R57 source precision, neutral DEM print and actual shader input diagnosis',version='R57')
    src['access_metadata'].update(sampling='Existing caches plus four explicit GLO90 collar cells N53/N54 E039/E040; independent neutral DEM luminance. Same R56 European page band, not uniform GLO90.',cover_sampling='Actual source affines and class scope recorded per asset: 225/450/2250 samples per3degrees; class10-only tree extracts retained; not full regional10m coverage.',new_dem_domains={'finite_moscow_collar_cells':[[39,53],[40,53],[39,54],[40,54]]},rebuilt_fine_windows=[a['core_bounds_lon_lat'] for a in result if a.get('surface_lod_degrees')==2],historical_applicability='Modern physical reference only, no1900 land state or water classification')
    f=copy.deepcopy(doc['evidence_catalog']['facts'][-1]);f.update(fact_id='physical_relief:sampling_r57',source_id=src['source_id'],source_version='R57',generator='tools/map/build_surface_r57.py',methodology=__doc__)
    f['value']['assets']=result;doc['source_registry']['sources'].append(src);doc['evidence_catalog']['facts'].append(f)
    save(ROOT/'data/presentation/sampling_surface_r57.json',doc)
    save(WORK/'source_records.json',records)
    save(WORK/'summary.json',dict(files=len(result),bytes=sum(a['bytes'] for a in result),decoded_max=max(a['decoded_bytes'] for a in result),new_dem_source_cells=len(read(WORK/'finite_dem_sources.json')) if (WORK/'finite_dem_sources.json').exists() else 0))

def enrich(aa):
    # Unknown legacy provenance is explicitly unknown, not inferred from width.
    byid={a['id']:a for a in aa}
    for a in aa:
        if 'precision' in a:continue
        origin=byid.get(a.get('source_asset'),a)
        dem=origin.get('dem_source','')
        legacy=key(origin).startswith(('france_r42','british_r43','german_r44','spain_r45','canary_r45','benelux_r46'))
        step=185.325 if 'GLO90' in dem or legacy else 1853.25 if 'ETOPO' in dem else 0
        a['precision']=dict(dem_extract_m_ns=step,dem_fallback_m_ns=1853.25,cover_m_ns_max=0,output_m_ns=a['display_spacing_degrees'][1]*111195,neutral_channel=False,source_note='Known producer DEM spacing; original per-cell cover precision not retained in this legacy record. Query original research extraction, not output dimensions.')
        if key(origin).startswith('european_r55_') and a.get('core_bounds_lon_lat'):
            w,s,e,n=a['core_bounds_lon_lat'];cc=[]
            for y in range(math.floor(s/3)*3,math.ceil(n/3)*3,3):
                for x in range(math.floor(w/3)*3,math.ceil(e/3)*3,3):
                    path=euro.resolve('cover',x,y)
                    if not path:continue
                    with rasterio.open(path) as src:cc.append(dict(bounds=list(src.bounds),m=abs(src.transform.e)*111195,extract_path=str(path.relative_to(ROOT)),shape=[src.width,src.height]))
            if cc:a['precision'].update(cover_cells=cc,cover_m_ns_max=max(v['m'] for v in cc),cover_m_ns_min=min(v['m'] for v in cc),cover_method='R50 producer nearest categorical expansion; no new independent output samples',cover_epoch='2021 v200')


# Explicit finite production inputs. This is the same material kernel above;
# acquisition is an opt-in offline CLI operation, never a game service.
PETERSBURG=WORK/'petersburg-2026-10-21'
PILOT=ROOT/'local-artifacts/terrain-source-recovery/pilot-2026-10-20/source_records.json'
CORE_ORDER=[(30,58),(28,58),(28,60),(30,60)]
UPGRADE=(27.9375,57.9375,32.0625,62.0625)

def intersects(a,b):return a[0]<b[2] and a[2]>b[0] and a[1]<b[3] and a[3]>b[1]
def contains(a,b,epsilon=1e-10):return a[0]<=b[0]+epsilon and a[1]<=b[1]+epsilon and a[2]>=b[2]-epsilon and a[3]>=b[3]-epsilon
def intersection(a,b):return [max(a[0],b[0]),max(a[1],b[1]),min(a[2],b[2]),min(a[3],b[3])]

def raster_metadata(path):
    with rasterio.open(path) as src:
        return dict(shape=list(src.shape),crs=str(src.crs),transform=list(src.transform),bounds=list(src.bounds),nodata=src.nodata,dtype=src.dtypes[0],area_or_point=src.tags().get('AREA_OR_POINT','Area'),units=list(src.units),overviews=src.overviews(1))

class FiniteInputs:
    """Declared real source windows with per-pixel fine/coarse continuation."""
    def __init__(self,etopo,dem,cover,up_dem=(),up_cover=(),feather=None):
        self.etopo=etopo;self.dem=list(dem);self.cover=list(cover)
        self.up_dem=list(up_dem);self.up_cover=list(up_cover);self.feather=feather

    def validate(self,bounds,size,read_cover=True):
        records=[self.etopo]+self.dem+self.up_dem+(self.cover+self.up_cover if read_cover else [])
        require_inputs(ROOT,[r['path'] for r in records],'R57 declared finite source windows')
        for r in records:
            m=raster_metadata(ROOT/r['path'])
            for k in ('shape','crs','nodata','dtype','area_or_point'):
                if m[k]!=r['raster'][k]:raise ValueError(f'{r["path"]}: changed source {k}')
            if not np.allclose(m['transform'],r['raster']['transform'],atol=1e-12,rtol=0):raise ValueError('Changed source affine')
            if r['kind']=='dem' and (m['crs']!='EPSG:4326' or m['area_or_point']!='Point' or r['method']!='average600'):raise ValueError('Invalid GLO extract identity')
            if r['kind']=='cover' and (m['area_or_point']!='Area' or r['product']!='WorldCover2021-v200' or r['method']!='nearest'):raise ValueError('Invalid categorical input identity')
        e=self.etopo
        if e['product']!='ETOPO2022-v1-60s-surface' or e['raster']['crs']!='EPSG:9518' or e['raster']['nodata']!=-99999:raise ValueError('Wrong ETOPO datum/product/NoData')
        # One native pixel outside the requested output bounds supports bilinear
        # sampling. The output itself already includes its32-pixel hillshade collar.
        guard=1/60
        if not contains(e['raster']['bounds'],[bounds[0]-guard,bounds[1]-guard,bounds[2]+guard,bounds[3]+guard]):raise ValueError('ETOPO window lacks interpolation neighbors')
        if read_cover:
            # Geometric support is separate from known class0 (unknown). Check
            # coarse coverage before considering any finer partial replacement.
            xx,yy=self.grid(bounds,size);supported=np.zeros(xx.shape,dtype=bool)
            for r in self.cover:
                b=r['raster']['bounds'];supported|=(xx>=b[0])&(xx<b[2])&(yy>=b[1])&(yy<b[3])
            if not supported.all():raise ValueError('Declared coarse classification support has a gap')

    @staticmethod
    def grid(bounds,size):
        w,s,e,n=bounds;nx,ny=size
        return np.meshgrid(w+(np.arange(nx)+.5)*(e-w)/nx,n-(np.arange(ny)+.5)*(n-s)/ny)

    def weights(self,bounds,size):
        if self.feather is None:return np.ones((size[1],size[0]),dtype='float32')
        x,y=self.grid(bounds,size);w,s,e,n=self.feather;pad=32/512
        return prev.common.smooth(w,w+pad,x)*(1-prev.common.smooth(e-pad,e,x))*prev.common.smooth(s,s+pad,y)*(1-prev.common.smooth(n-pad,n,y))

    @staticmethod
    def cell(r):
        return dict(path=r['path'],bounds=r['raster']['bounds'],spacing_m_ns=abs(r['raster']['transform'][4])*111195,provider_key=r['provider_key'],provider_url=r['url'])

    @staticmethod
    def stable_dem(r,bounds,size):
        # GDAL's default resampling scale varies with warp chunk geometry.
        # Here both grids are geographic and scale is constant. Pin the actual
        # affine ratio so identical geographic samples agree across collars.
        nx,ny=size;out=np.full((ny,nx),np.nan,dtype='float32')
        with rasterio.open(ROOT/r['path']) as src:
            reproject(rasterio.band(src,1),out,src_transform=src.transform,src_crs=src.crs,dst_transform=from_bounds(*bounds,nx,ny),dst_crs='EPSG:4326',dst_nodata=np.nan,resampling=Resampling.bilinear,XSCALE=src.transform.a/((bounds[2]-bounds[0])/nx),YSCALE=abs(src.transform.e)/((bounds[3]-bounds[1])/ny))
        return out

    def height(self,bounds,size,fine):
        h=sib.sample(ROOT/self.etopo['path'],bounds,size);records=[];glo_support=np.zeros(h.shape,dtype=bool)
        if not fine:return h,records
        weight=self.weights(bounds,size)
        for source_list,upgrade in [(self.dem,False),(self.up_dem,True)]:
            for r in sorted(source_list,key=lambda r:(r['cell'][1],r['cell'][0])):
                if not intersects(r['raster']['bounds'],bounds):continue
                data=self.stable_dem(r,bounds,size) if upgrade or self.feather is None else sib.sample(ROOT/r['path'],bounds,size)
                valid=np.isfinite(data)
                if upgrade:valid&=weight>0
                if not valid.any():continue
                glo_support|=valid
                if upgrade:h[valid]=h[valid]*(1-weight[valid])+data[valid]*weight[valid]
                else:h[valid]=data[valid]
                c=self.cell(r);c['bounds']=intersection(c['bounds'],bounds)
                if upgrade and self.feather is not None:c['bounds']=intersection(c['bounds'],self.feather);c['edge_feather_degrees']=32/512
                if not any(v['path']==c['path'] for v in records):records.append(c)
        if self.feather is None:
            xx,yy=self.grid(bounds,size);coverage=np.zeros(xx.shape,dtype=bool)
            for r in self.dem:
                b=r['raster']['bounds'];coverage|=(xx>=b[0])&(xx<b[2])&(yy>=b[1])&(yy<b[3])
            if not coverage.all() or not glo_support.all():raise ValueError('Fine target lacks real GLO contribution')
        return h,records

    def colour(self,bounds,size):
        nx,ny=size;observed=np.broadcast_to(sib.PALETTE[0],(ny,nx,3)).copy();records=[]
        weight=self.weights(bounds,size);owner=np.full((ny,nx),-1,dtype='int32');mixed=set()
        for source_list,upgrade in [(self.cover,False),(self.up_cover,True)]:
            # Coarse first. A fine partial window cannot erase the rest of a
            # coarser3degree source. Distinct225/450/2250 inputs keep their identity.
            for r in sorted(source_list,key=lambda r:(r['native']['bounds'][1],r['native']['bounds'][0],-abs(r['raster']['transform'][4]))):
                if not intersects(r['raster']['bounds'],bounds):continue
                with rasterio.open(ROOT/r['path']) as src:
                    classes=src.read(1)
                    if not set(np.unique(classes)).issubset({0,10,20,30,40,50,60,70,80,90,95,100}):raise ValueError('Noncategorical source')
                    palette=sib.PALETTE[classes].copy()
                    # Legacy0 remains the declared neutral unknown. Fine0 must
                    # fall back to the real coarser observation, never interpolate IDs.
                    if upgrade:palette[classes==0]=np.nan
                    rgb=np.full((ny,nx,3),np.nan,dtype='float32')
                    for i in range(3):
                        reproject(palette[:,:,i],rgb[:,:,i],src_transform=src.transform,src_crs=src.crs,src_nodata=np.nan,dst_transform=from_bounds(*bounds,nx,ny),dst_crs='EPSG:4326',dst_nodata=np.nan,resampling=Resampling.average)
                    blend=weight
                    if upgrade:
                        known=np.zeros((ny,nx),dtype='float32')
                        reproject((classes!=0).astype('float32'),known,src_transform=src.transform,src_crs=src.crs,dst_transform=from_bounds(*bounds,nx,ny),dst_crs='EPSG:4326',dst_nodata=0,resampling=Resampling.average)
                        blend=weight*known
                    valid=np.isfinite(rgb).all(axis=2)
                    if upgrade:valid&=blend>0
                    if not valid.any():continue
                    if upgrade:observed[valid]=observed[valid]*(1-blend[valid,None])+rgb[valid]*blend[valid,None]
                    else:observed[valid]=rgb[valid]
                    c=self.cell(r);c['bounds']=intersection(c['bounds'],bounds);c.update(shape=[src.width,src.height],method='categorical palette first, area resampling of colours')
                    if upgrade and self.feather is not None:c['bounds']=intersection(c['bounds'],self.feather)
                    index=len(records)
                    if upgrade:
                        owner[valid&(blend>=1-1e-7)]=index
                        if np.any(valid&(blend<1-1e-7)):mixed.add(index)
                    else:owner[valid]=index
                    records.append(c)
        contributing=set(np.unique(owner).tolist())|mixed
        return observed,[r for index,r in enumerate(records) if index in contributing]


class PetersburgSources:
    """Single finite batch ledger; originals retained, temporary outputs declared."""
    def __init__(self):
        self.root=PETERSBURG;self.path=self.root/'sources.json';self.root.mkdir(parents=True,exist_ok=True)
        self.pilot=read(PILOT);self.plan=self.pilot['four_core_readiness']
        self.data=read(self.path) if self.path.exists() else dict(schema='r57_finite_inputs_1',product_scope='Petersburg four cores and two8degree consumers only',network_body_bytes=0,network_reserved_bytes=0,write_bytes=0,peak_bytes=0,dem={},cover={},etopo={},outputs={})
        self.cache={};self.http=None

    def persist(self):save(self.path,self.data)
    def disk(self,reserve=0):
        total=sum(p.stat().st_size for p in self.root.rglob('*') if p.is_file())
        if total+reserve>640*1024**2:raise RuntimeError('640MiB terrain disk budget would be exceeded')
        self.data['peak_bytes']=max(self.data['peak_bytes'],total+reserve)
    def charge(self,amount):
        if self.data['network_reserved_bytes']+amount>400*1024**2:raise RuntimeError('400MiB source network budget would be exceeded')
        self.data['network_reserved_bytes']+=amount;self.persist()
    def fetch(self,url,length,start=None):
        import requests
        self.charge(length)
        headers={'Accept-Encoding':'identity'}
        if start is not None:headers['Range']=f'bytes={start}-{start+length-1}'
        r=requests.get(url,headers=headers,stream=True,timeout=60)
        if r.status_code!=(206 if start is not None else 200):r.close();raise ValueError(f'Provider HTTP {r.status_code}; no whole-object fallback')
        if int(r.headers.get('Content-Length',-1))!=length:r.close();raise ValueError('Unexpected provider response length')
        if start is not None and not r.headers.get('Content-Range','').startswith(f'bytes {start}-{start+length-1}/'):r.close();raise ValueError('Invalid provider Range')
        chunks=[];count=0
        try:
            for chunk in r.iter_content(65536):
                count+=len(chunk);self.data['network_body_bytes']+=len(chunk)
                if count>length:raise ValueError('Oversized source response')
                chunks.append(chunk)
            if count!=length:raise ValueError('Truncated source response')
            return b''.join(chunks),dict(last_modified=r.headers.get('Last-Modified'),version_id=r.headers.get('x-amz-version-id'))
        finally:r.close();self.persist()

    def original(self,item):
        key=item['key']
        if key==self.pilot['glo']['provider_key'].split('/')[0]:return ROOT/self.pilot['glo']['path']
        path=self.root/'source'/(key+'.tif')
        if path.exists():
            if path.stat().st_size!=item['bytes']:raise ValueError('Incomplete retained GLO')
            return path
        self.disk(item['bytes']);payload,head=self.fetch(item['url'],item['bytes']);path.parent.mkdir(exist_ok=True);path.write_bytes(payload);self.data['write_bytes']+=len(payload)
        return path

    def dem(self,key):
        if key in self.data['dem']:return self.data['dem'][key]
        import re
        y,x=map(int,re.search(r'_N(\d+)_00_E(\d+)_00_DEM',key).groups())
        if key not in (ROOT/'local-artifacts/france-surface-r42/copdem_tileList.txt').read_text().splitlines():raise ValueError('GLO not in retained provider list')
        item=next(v for v in self.plan['head_metadata'] if v['kind']=='dem' and v['key']==key)
        original=self.original(item);native=raster_metadata(original)
        if native['crs']!='EPSG:4326' or native['area_or_point']!='Point' or native['dtype']!='float32' or native['shape'][0]!=1200:raise ValueError('Wrong native GLO identity')
        gt=native['transform']
        if not np.allclose([gt[2]+gt[0]/2,gt[5]+gt[4]/2,gt[0]*native['shape'][1],-gt[4]*native['shape'][0]],[x,y+1,1,1],atol=1e-9,rtol=0):raise ValueError('Wrong GLO point location or sampling grid')
        path=self.root/'dem'/(key+'.tif')
        if key==self.pilot['glo']['provider_key'].split('/')[0]:path=ROOT/self.pilot['glo']['extraction']['path']
        else:
            with rasterio.open(original) as src:
                values=src.read(1,out_shape=(600,600),resampling=Resampling.average,masked=True)
                if np.ma.count_masked(values) or not np.isfinite(values).all():raise ValueError('GLO NoData requires explicit resolution before production')
                transform=src.transform*src.transform.scale(src.width/600,src.height/600)
                self.tiff(path,np.asarray(values),transform,src.crs,src.nodata,'Point')
        r=dict(kind='dem',cell=[x,y],provider_key=key,url=item['url'],product='Copernicus-GLO90-COG',native=native,path=path.relative_to(ROOT).as_posix(),raster=raster_metadata(path),method='average600',vertical='EGM2008 orthometric metres',raw_path=original.relative_to(ROOT).as_posix(),retrieved_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),historical_byte_identity='Not proven; no oldVersionId or digest')
        self.data['dem'][key]=r;self.persist();return r

    def tiff(self,path,values,transform,crs,nodata,area):
        self.disk(values.nbytes+65536);path.parent.mkdir(parents=True,exist_ok=True)
        with rasterio.open(path,'w',driver='GTiff',width=values.shape[1],height=values.shape[0],count=1,dtype=str(values.dtype),crs=crs,transform=transform,nodata=nodata,compress='deflate') as dst:dst.write(values,1);dst.update_tags(AREA_OR_POINT=area)
        self.data['write_bytes']+=path.stat().st_size

    def __enter__(self):
        import threading,re
        from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
        owner=self
        class RangeHandler(BaseHTTPRequestHandler):
            def log_message(self,*args):pass
            def do_HEAD(self):
                item=owner.urls.get(self.path)
                if not item:self.send_error(404);return
                self.send_response(200);self.send_header('Content-Length',str(item['bytes']));self.send_header('Accept-Ranges','bytes');self.end_headers()
            def do_GET(self):
                item=owner.urls.get(self.path);m=re.fullmatch(r'bytes=(\d+)-(\d+)',self.headers.get('Range',''))
                if not item or not m:self.send_error(400);return
                start,end=map(int,m.groups());end=min(end,item['bytes']-1)
                try:
                    if end-start+1>16*1024**2:raise ValueError('Oversized finite range')
                    # Canonical16KiB blocks reuse overlapping COG requests in RAM.
                    first=start//16384;last=end//16384;i=first;blocks={}
                    # Keep this response's bytes alive while the bounded shared
                    # cache evicts unrelated ranges or concurrent COG requests.
                    for k in range(first,last+1):
                        try:blocks[k]=owner.cache[item['url'],k]
                        except KeyError:pass
                    while i<=last:
                        if i in blocks:i+=1;continue
                        j=i
                        while j<last and j+1 not in blocks:j+=1
                        begin=i*16384;stop=min((j+1)*16384,item['bytes']);payload,_=owner.fetch(item['url'],stop-begin,begin)
                        for k in range(i,j+1):
                            blocks[k]=payload[(k-i)*16384:(k-i+1)*16384];owner.cache[item['url'],k]=blocks[k]
                        i=j+1
                    payload=b''.join(blocks[k] for k in range(first,last+1))[start-first*16384:end-first*16384+1]
                    self.send_response(206);self.send_header('Content-Length',str(len(payload)));self.send_header('Content-Range',f'bytes {start}-{end}/{item["bytes"]}');self.end_headers();self.wfile.write(payload)
                except Exception as error:owner.data['http_error']=str(error);self.send_error(502,str(error))
        self.urls={'/etopo.tif':dict(url=self.pilot['etopo']['url'],bytes=self.pilot['etopo']['length'])}
        for v in self.plan['head_metadata']:
            if v['kind']=='cover':self.urls['/'+v['key']]=v
        self.http=ThreadingHTTPServer(('127.0.0.1',0),RangeHandler);threading.Thread(target=self.http.serve_forever,daemon=True).start()
        self.env=rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN='EMPTY_DIR',GDAL_HTTP_TIMEOUT='70',GDAL_HTTP_MAX_RETRY='1',GDAL_HTTP_RETRY_DELAY='1',GDAL_HTTP_MULTIRANGE='SERIAL',GDAL_CACHEMAX=16*1024**2,CPL_VSIL_CURL_ALLOWED_EXTENSIONS='.tif',PROJ_NETWORK='OFF');self.env.__enter__();return self
    def __exit__(self,*args):
        self.env.__exit__(*args);self.http.shutdown();self.http.server_close()
        if args[0] is None and self.data.get('http_error'):self.data['recovered_transport_error']=self.data.pop('http_error')
        self.persist()
    def remote(self,key):return f'http://127.0.0.1:{self.http.server_port}/'+key

    def cover(self,key,samples,bounds=None,label='legacy'):
        from rasterio.windows import Window,transform as wt
        identity=f'{key}:{samples}:{label}'
        if identity in self.data['cover']:return self.data['cover'][identity]
        item=self.urls['/'+key]
        with rasterio.open(self.remote(key)) as src:
            tags=src.tags()
            if tags.get('product_version')!='V2.0.0' or tags.get('product_type')!='LandCover Map' or src.shape!=(36000,36000) or src.nodata!=0 or str(src.crs)!='EPSG:4326' or src.dtypes[0]!='uint8' or src.tags().get('AREA_OR_POINT')!='Area' or not np.allclose([src.transform.a,src.transform.e],[1/12000,-1/12000],atol=1e-12,rtol=0):raise ValueError('Wrong WorldCover product/grid')
            scale=src.width/samples;window=Window(0,0,samples,samples)
            if bounds is not None:
                b=intersection(bounds,list(src.bounds));t=src.transform*rasterio.Affine.scale(scale,scale)
                c0=max(0,math.floor((b[0]-t.c)/t.a)-1);c1=min(samples,math.ceil((b[2]-t.c)/t.a)+1)
                r0=max(0,math.floor((t.f-b[3])/-t.e)-1);r1=min(samples,math.ceil((t.f-b[1])/-t.e)+1)
                window=Window(c0,r0,c1-c0,r1-r0)
            native_win=Window(window.col_off*scale,window.row_off*scale,window.width*scale,window.height*scale)
            values=src.read(1,window=native_win,out_shape=(int(window.height),int(window.width)),resampling=Resampling.nearest)
            if not set(np.unique(values)).issubset({0,10,20,30,40,50,60,70,80,90,95,100}):raise ValueError('Wrong WorldCover class values')
            transform=wt(native_win,src.transform)*rasterio.Affine.scale(scale,scale)
            path=self.root/'cover'/(key.removesuffix('.tif')+f'_{samples}_{label}.tif');self.tiff(path,values,transform,src.crs,src.nodata,'Area')
            record=dict(kind='cover',provider_key=key,url=item['url'],product='WorldCover2021-v200',native=raster_metadata_remote(src),path=path.relative_to(ROOT).as_posix(),raster=raster_metadata(path),method='nearest',full_grid_samples=samples,source_window=[native_win.col_off,native_win.row_off,native_win.width,native_win.height],retrieved_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),class0='NoData unknown; coarse neutral, fine falls back to coarse',class_scope='all classes; not class10-only')
        self.data['cover'][identity]=record;self.persist();return record

    def etopo(self,bounds,label):
        from rasterio.windows import from_bounds as window_bounds,Window,transform as wt
        if label in self.data['etopo']:return self.data['etopo'][label]
        with rasterio.open(self.remote('etopo.tif')) as src:
            if str(src.crs)!='EPSG:9518' or src.shape!=(10800,21600) or src.nodata!=-99999 or src.dtypes[0]!='float32' or not np.allclose(list(src.transform)[:6],[1/60,0,-180,0,-1/60,90],atol=1e-12,rtol=0):raise ValueError('Wrong ETOPO surface source/grid')
            w=window_bounds(*bounds,src.transform);c0=math.floor(w.col_off)-2;r0=math.floor(w.row_off)-2;c1=math.ceil(w.col_off+w.width)+2;r1=math.ceil(w.row_off+w.height)+2
            win=Window(c0,r0,c1-c0,r1-r0);values=src.read(1,window=win,masked=True)
            if np.ma.count_masked(values) or not np.isfinite(values).all():raise ValueError('ETOPO window contains unresolvedNoData')
            path=self.root/'etopo'/('etopo60s_'+label+'.tif');self.tiff(path,np.asarray(values),wt(win,src.transform),src.crs,src.nodata,'Area')
            record=dict(kind='etopo',provider_key='ETOPO_2022_v1_60s_N90W180_surface.tif',url=self.pilot['etopo']['url'],product='ETOPO2022-v1-60s-surface',native=raster_metadata_remote(src),path=path.relative_to(ROOT).as_posix(),raster=raster_metadata(path),method='native_integer_window',source_window=[c0,r0,c1-c0,r1-r0],source_pixel_guard=2,retrieved_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),vertical='EPSG:3855 EGM2008 metre')
        self.data['etopo'][label]=record;self.persist();return record

def raster_metadata_remote(src):
    return dict(shape=list(src.shape),crs=str(src.crs),transform=list(src.transform),bounds=list(src.bounds),nodata=src.nodata,dtype=src.dtypes[0],area_or_point=src.tags().get('AREA_OR_POINT','Area'),units=list(src.units),tags=src.tags())

def petersburg_target(x,y):
    core=[x,y,x+2,y+2];pad=32/512
    old=(f'european_r55_{y}_{x:+d}' if y==58 else f'northern_r52_{y}_{x:+d}')
    return dict(name=f'petersburg_r57_{y}_{x:+d}',core=core,bounds=[x-pad,y-pad,x+2+pad,y+2+pad],replaces=[old],size=[1088,1088])

def petersburg_keys(bounds):
    w,s,e,n=bounds
    return [f'Copernicus_DSM_COG_30_N{y:02d}_00_E{x:03d}_00_DEM' for y in range(math.floor(s),math.ceil(n)) for x in range(math.floor(w),math.ceil(e))]

def petersburg_acquire(stage):
    targets=[petersburg_target(*p) for p in (CORE_ORDER[:1] if stage=='first' else CORE_ORDER)]
    if stage!='first' and not (PETERSBURG/'first_verified.json').exists():raise ValueError('First complete source validation must pass before expansion')
    with PetersburgSources() as sources:
        for target in targets:
            for key_name in petersburg_keys(target['bounds']):sources.dem(key_name)
            sources.etopo(target['bounds'],target['name'])
            w,s,e,n=target['bounds']
            for y in range(math.floor(s/3)*3,math.ceil(n/3)*3,3):
                for x in range(math.floor(w/3)*3,math.ceil(e/3)*3,3):
                    name=f'ESA_WorldCover_10m_2021_v200_N{y:02d}E{x:03d}_Map.tif'
                    sources.cover(name,450)
                    sources.cover(name,2250,target['bounds'],target['name'])
            print('Finite sources ready',target['name'],sources.data['network_body_bytes'],flush=True)
        if stage!='first':
            for item in sources.plan['head_metadata']:
                if item['kind']=='dem':sources.dem(item['key'])
            for v in sources.plan['existing_extract_variants']:
                sources.cover(v['provider_key'],v['specs'][0]['shape'][0])
            sources.etopo([23.75,55.75,40.25,64.25],'two_pages')
        sources.disk();sources.persist()

def petersburg_inputs(sources,target,page=None,baseline=False):
    data=sources.data;bounds=target['bounds']
    if page is None:
        dem=[data['dem'][k] for k in petersburg_keys(bounds)]
        cover=[v for k,v in data['cover'].items() if k.endswith(':450:legacy') and intersects(v['raster']['bounds'],bounds)]
        fine=[v for k,v in data['cover'].items() if k.endswith(':'+target['name'])]
        return FiniteInputs(data['etopo'][target['name']],dem,cover,up_cover=fine)
    bycell={tuple(v['cell']):v for v in data['dem'].values()}
    import re
    dem=[];cover=[]
    for c in page['precision']['dem_cells']:
        y,x=map(int,re.search(r'([+-]\d+)_([+-]\d+)\.tif',c['extract_path']).groups());dem.append(bycell[x,y])
    for c in page['precision']['cover_cells']:
        y,x=map(int,re.search(r'([+-]\d+)_([+-]\d+)\.tif',c['extract_path']).groups());name=f'ESA_WorldCover_10m_2021_v200_N{y:02d}E{x:03d}_Map.tif';samples=c['shape'][0]
        cover.append(data['cover'][f'{name}:{samples}:legacy'])
    up=[data['dem'][k] for k in petersburg_keys(UPGRADE)] if not baseline else []
    fine=[v for k,v in data['cover'].items() if not k.endswith(':legacy')] if not baseline else []
    return FiniteInputs(data['etopo']['two_pages'],dem,cover,up,fine,UPGRADE)

def check_material_file(a,pixels):
    data=(ROOT/a['path'].removeprefix('res://')).read_bytes()
    w,h,length=struct.unpack('<III',data[8:20]);raw=zlib.decompress(data[20:])
    if data[:8]!=b'FRT42\0\0\0' or (w,h)!=(1088,1088) or len(raw)!=length or length!=6313256:raise ValueError('Wrong finite BIN layout')
    offset=0;level=pixels;checks=[]
    while True:
        count=level.shape[0]*level.shape[1]*4;actual=np.frombuffer(raw[offset:offset+count],dtype='uint8').reshape(level.shape)
        error=float(np.max(np.abs(actual.astype('float64')/255-level)))
        if error>0.5/255+1e-7:raise ValueError('Material Mip differs from per-channel area contract')
        checks.append(dict(size=list(level.shape[:2]),max_quantization_error=error));offset+=count
        if level.shape[:2]==(1,1):break
        level=prev.resize(level,(max(1,level.shape[1]//2),max(1,level.shape[0]//2)))
    if offset!=length:raise ValueError('Extra or missing Mip bytes')
    return checks

def finite_input_metadata(paths):
    declared=[Path(__file__).resolve(),ROOT/'tools/map/build_surface_r56.py',ROOT/'tools/map/build_siberian_surface_r50.py']+[ROOT/p for p in paths]
    return {p.relative_to(ROOT).as_posix():dict(bytes=p.stat().st_size,mtime_ns=p.stat().st_mtime_ns) for p in dict.fromkeys(declared)}

def declared_target_input(target,stage):
    first=target['name']==petersburg_target(30,58)['name']
    path=PETERSBURG/('first_target.json' if first else 'batch_targets.json')
    document=read(path)
    descriptor=document if first else next(v for v in document['targets'] if v['target']['name']==target['name'])
    if descriptor['target']!=target:raise ValueError('Finite target descriptor disagrees with authorized geometry')
    config=descriptor['inputs']
    return FiniteInputs(config['etopo'],config['dem'],config['cover'],config.get('up_dem',[]),config.get('up_cover',[]),config.get('feather')),path

def petersburg_build(stage):
    sources=PetersburgSources();targets=[petersburg_target(*p) for p in (CORE_ORDER[:1] if stage=='first' else CORE_ORDER)]
    if stage!='first' and not (PETERSBURG/'first_verified.json').exists():raise ValueError('First target not source-verified')
    out=PETERSBURG/'products';out.mkdir(exist_ok=True)
    for t in targets:
        record=out/(t['name']+'.json')
        inputs,descriptor=declared_target_input(t,stage)
        paths=[descriptor.relative_to(ROOT).as_posix()]+[r['path'] for r in [inputs.etopo]+inputs.dem+inputs.cover+inputs.up_cover]
        metadata=finite_input_metadata(paths)
        if record.exists() and read(record).get('input_metadata')==metadata and (ROOT/read(record)['asset']['path'].removeprefix('res://')).is_file():
            # CLI reuse is supplemented by the unified recipe input size/mtime
            # comparison. Do not recalculate unchanged material during export.
            print('Retained finite product',t['name'],flush=True);continue
        pixels,height,shade,dem,cover=field(t['bounds'],t['size'],inputs=inputs)
        coarse=sib.sample(ROOT/inputs.etopo['path'],t['bounds'],t['size']);difference=height-coarse
        if not np.isfinite(pixels).all() or float(np.std(difference))<.01:raise ValueError('New fine target does not contain measured GLO detail')
        # Same geographic samples with an additional computation collar must
        # agree inside the32-pixel core; no artificial image-edge hillshade.
        step=1/512;b=t['bounds'];expanded=[b[0]-8*step,b[1]-8*step,b[2]+8*step,b[3]+8*step]
        more=field(expanded,(1104,1104),inputs=inputs)[0]
        halo_error=float(np.max(np.abs(pixels[32:-32,32:-32]-more[40:-40,40:-40])))
        if halo_error>1e-6:raise ValueError('Core depends on computation boundary')
        sources.disk(6315256);a=write(t['name'],pixels,t['bounds'],out)
        a.update(core_bounds_lon_lat=t['core'],surface_lod_degrees=2,surface_replaces=t['replaces'],surface_display_max_mpp=750,surface_fade_mpp=300,precision=precision(a,dem,cover),dem_source='Recovered real GLO90 DSM600/degree; native93m N-S, average185m; no ETOPO-only fine label',cover_source='WC2021-v200 actual2250-grid cropped classes over separately retained450-grid categorical sources')
        result=dict(asset=a,dem=dem,cover=cover,input_paths=paths,input_metadata=metadata,checks=dict(all_glo_output_support=True,height_range=[float(height.min()),float(height.max())],shade_range=[float(shade.min()),float(shade.max())],glo_vs_etopo_rms_m=float(np.sqrt(np.mean(difference**2))),glo_vs_etopo_std_m=float(np.std(difference)),core_extra_collar_max_error=halo_error,mips=check_material_file(a,pixels)))
        save(record,result);sources.data['write_bytes']+=a['bytes']+record.stat().st_size;sources.data['outputs'][t['name']]=record.relative_to(ROOT).as_posix();sources.disk();sources.persist()
        if t['name']==petersburg_target(30,58)['name']:save(PETERSBURG/'first_verified.json',dict(target=t['name'],source_checks=result['checks'],status='Source-complete isolated first tile; not yet published'))
        print('Verified real fine product',t['name'],a['bytes'],result['checks']['glo_vs_etopo_rms_m'],flush=True)
    if stage=='first':return
    current=prev.assets(read(ROOT/'data/presentation/sampling_surface_r57.json'))
    for old_name in sources.plan['pages']:
        page=next(a for a in current if key(a)==old_name['id']);name='petersburg_r57_mid8_56_'+f'{int(page["core_bounds_lon_lat"][0]):+d}'
        record=out/(name+'.json')
        t=dict(name=name,bounds=page['bounds_lon_lat'],size=[1088,1088])
        inputs,descriptor=declared_target_input(t,stage)
        paths=[descriptor.relative_to(ROOT).as_posix()]+[r['path'] for r in [inputs.etopo]+inputs.dem+inputs.cover+inputs.up_dem+inputs.up_cover]+[page['path'].removeprefix('res://')]
        metadata=finite_input_metadata(paths)
        if record.exists() and read(record).get('input_metadata')==metadata and (ROOT/read(record)['asset']['path'].removeprefix('res://')).is_file():continue
        baseline_inputs=petersburg_inputs(sources,t,page,True);baseline=field(t['bounds'],t['size'],inputs=baseline_inputs)[0]
        encoded_baseline=np.uint8(np.clip(baseline,0,1)*255+.5);old=np.uint8(prev.decode(page)*255+.5)
        base_error=np.abs(encoded_baseline.astype('int16')-old.astype('int16'))
        # Recovered objects cannot silently replace old source meaning elsewhere.
        if base_error.max()>1:raise ValueError(f'{name}: restored baseline differs from old page by{base_error.max()}/255')
        pixels,height,shade,dem,cover=field(t['bounds'],t['size'],inputs=inputs)
        xx,yy=inputs.grid(t['bounds'],t['size']);pad=4/128
        outside=(xx<UPGRADE[0]-pad)|(xx>UPGRADE[2]+pad)|(yy<UPGRADE[1]-pad)|(yy>UPGRADE[3]+pad)
        delta=np.abs(np.uint8(np.clip(pixels,0,1)*255+.5).astype('int16')-old.astype('int16'))
        if delta[outside].max()>1:raise ValueError('Unmodified page region changed beyond quantization')
        sources.disk(6315256);a=write(name,pixels,t['bounds'],out)
        a.update(core_bounds_lon_lat=page['core_bounds_lon_lat'],surface_lod_degrees=8,surface_replaces=[key(page)],surface_display_max_mpp=page['surface_display_max_mpp'],surface_fade_mpp=page['surface_fade_mpp'],precision=precision(a,dem,cover),dem_source='Preserved all original GLO source cells plus recovered Petersburg DSM in declared feathered domain; ETOPO60s elsewhere',cover_source='Original450/2250 class versions retained; actual2250-grid finite upgrades inside declared supported domain')
        result=dict(asset=a,dem=dem,cover=cover,input_paths=paths,input_metadata=metadata,checks=dict(baseline_max_error_u8=base_error.max(axis=(0,1)).tolist(),outside_upgrade_max_error_u8=delta[outside].max(axis=0).tolist(),upgraded_pixels=int(np.any(delta>0,axis=2).sum()),upgrade_bounds=list(UPGRADE),source_feather_degrees=32/512,mips=check_material_file(a,pixels)))
        save(record,result);sources.data['outputs'][name]=record.relative_to(ROOT).as_posix();sources.data['write_bytes']+=a['bytes']+record.stat().st_size;sources.disk();sources.persist();print('Verified complete8degree product',name,a['bytes'],flush=True)
    # New pages share the exact1/128degree lattice. Exclude the external
    # computation edges; the common geographic overlap must be identical.
    pa=read(out/'petersburg_r57_mid8_56_+24.json')['asset'];pb=read(out/'petersburg_r57_mid8_56_+32.json')['asset']
    aa=prev.decode(pa);bb=prev.decode(pb);overlap=np.abs(aa[4:-4,-60:-4]-bb[4:-4,4:60]);maximum=float(overlap.max())
    if maximum>1/255+1e-7:raise ValueError('Two8degree pages disagree in their overlap')
    mip_edges=[]
    for lod in range(7):
        a=prev.decode(pa,lod);b=prev.decode(pb,lod);width=a.shape[1];offset=round(8/8.5*width);shared=width-offset;margin=4//(2**lod)
        rows=slice(margin,-margin) if margin else slice(None)
        difference=np.abs(a[rows,offset+margin:width-margin if margin else width]-b[rows,margin:shared-margin if margin else shared])
        error=float(difference.max())
        if error>1/255+1e-7:raise ValueError('Page overlap Mip exceeds one quantization unit')
        mip_edges.append(dict(lod=lod,max_error=error))
    core_edges=[]
    for first,second,axis in [('58_+28','58_+30','x'),('60_+28','60_+30','x'),('58_+28','60_+28','y'),('58_+30','60_+30','y')]:
        a=prev.decode(read(out/('petersburg_r57_'+first+'.json'))['asset']);b=prev.decode(read(out/('petersburg_r57_'+second+'.json'))['asset'])
        difference=np.abs(a[4:-4,-60:-4]-b[4:-4,4:60]) if axis=='x' else np.abs(a[4:60,4:-4]-b[-60:-4,4:-4])
        error=float(difference.max())
        if error>1/255+1e-7:raise ValueError('Fine core overlap differs')
        core_edges.append(dict(first=first,second=second,max_error=error))
    save(PETERSBURG/'batch_verified.json',dict(products=list(sources.data['outputs']),page_overlap_max_error=maximum,page_overlap_mips=mip_edges,fine_core_overlap=core_edges,all11_mips='Each material level validated against per-channel area contract; last4levels have unequal geographic footprint phase, not equal-texel seam comparisons',status='Source and material checks passed; game display acceptance pending'))

def petersburg_publish():
    if not (PETERSBURG/'batch_verified.json').exists():raise ValueError('Complete bounded batch must pass before catalogue publication')
    sources=PetersburgSources();doc=read(ROOT/'data/presentation/sampling_surface_r57.json');aa=prev.assets(doc)
    existing={key(a):a for a in aa}
    pairs=[read(ROOT/p) for p in sources.data['outputs'].values()]
    if all(key(p['asset']) in existing and p['asset']['path']==existing[key(p['asset'])]['path'] and (ROOT/p['asset']['path'].removeprefix('res://')).is_file() for p in pairs):print('Finite catalogue retained');return
    new=[];out=prev.common.OUT
    for record_path in sources.data['outputs'].values():
        pair=read(ROOT/record_path);a=pair['asset'];src=ROOT/a['path'].removeprefix('res://');destination=out/(key(a)+'.bin')
        if src!=destination:
            sources.disk(src.stat().st_size);destination.write_bytes(src.read_bytes());sources.data['write_bytes']+=destination.stat().st_size
        a=copy.deepcopy(a);a['path']='res://'+destination.relative_to(ROOT).as_posix();new.append(a)
        pair['asset']=a;save(ROOT/record_path,pair)
    replacements={v for a in new for v in a['surface_replaces']}
    for a in aa:
        if key(a) in replacements:a['surface_role']='source_detail'
    source=copy.deepcopy(doc['source_registry']['sources'][-1]);source.update(source_id='petersburg_surface_r57',title='Petersburg finite real DSM and categorical source recovery',version='R57-Petersburg-2026-10-21')
    source['access_metadata'].update(finite_upgrade_bounds=list(UPGRADE),sampling='GLO native93m N-S;600/degree average185m;2degree217m and8degree869m output',finite_production_inputs=sources.path.relative_to(ROOT).as_posix(),cover_sampling='Existing450/2250 retained;2250-grid finite classified windows, palette before average',historical_applicability='Modern physical reference only; no1900 land/water/political facts')
    fact=copy.deepcopy(doc['evidence_catalog']['facts'][-1]);fact.update(fact_id='physical_relief:petersburg_r57',source_id=source['source_id'],source_version=source['version'],generator='tools/map/build_surface_r57.py',methodology='Explicit source windows, native affines, complete source support, categorical continuation, sameR57 metric material kernel and full encoding6 Mips');fact['value']['assets']=new
    doc['source_registry']['sources']=[s for s in doc['source_registry']['sources'] if s['source_id']!=source['source_id']]+[source]
    doc['evidence_catalog']['facts']=[f for f in doc['evidence_catalog']['facts'] if f['fact_id']!=fact['fact_id']]+[fact]
    save(ROOT/'data/presentation/sampling_surface_r57.json',doc)
    sources.data['published']=[a['path'] for a in new];sources.persist();print('Published finite six-asset catalogue',sum(a['bytes'] for a in new))

def france_support_repair():
    # Two observed French seams only; reconstruct from retained admitted
    # material, not from a fictitious recovered DEM or national download.
    import build_shared_surface_r48 as shared
    root=ROOT/'local-artifacts/r57-mode-repair-2026-10-21';out=root/'material'
    out.mkdir(parents=True,exist_ok=True)
    doc=read(ROOT/'data/presentation/sampling_surface_r57.json')
    upstream={a['id']:a for a in prev.assets(read(ROOT/'data/presentation/europe_surface_r48.json'))}
    current={key(a):a for a in prev.assets(doc)}
    names=['canonical_r56_shared_r48_48_+2','canonical_r56_shared_r48_48_+4']
    produced=[];records=[]
    old_out=prev.common.OUT;prev.common.OUT=out
    try:
        for name in names:
            old=current[name];source=upstream[old['source_asset']]
            inputs=[upstream[v] for v in source['upstream_asset_ids']]
            require_inputs(ROOT,[a['path'][6:] for a in inputs],'French support material repair')
            pixels=shared.compose(old['bounds_lon_lat'],old['width'],old['height'],inputs,canonical_output=True)
            if not np.isfinite(pixels).all():raise ValueError('Invalid French material')
            a=prev.write('support_r57_'+name,pixels,old['bounds_lon_lat'])
            for field_name in ['core_bounds_lon_lat','surface_lod_degrees','precision']:
                a[field_name]=copy.deepcopy(old[field_name])
            a.update(surface_group='sampling_r57',surface_replaces=[name],source_asset=old['source_asset'],source_assets=source['upstream_asset_ids'],dem_source='Retained R42/R46 admitted baked material; no raw DEM reacquisition',cover_source='Original class10-only/all-class inputs unchanged; no precision upgrade',method='Decode each source to linear shaded RGB and independent support before interpolation; weighted RGB; separate coverage; coverage-premultiplied area Mips')
            decoded=prev.decode(a)
            if np.max(np.abs(decoded-pixels))>0.5/255+1e-6:raise ValueError('Material write differs')
            destination=old_out/Path(a['path']).name
            destination.write_bytes((ROOT/a['path'][6:]).read_bytes())
            a['path']='res://'+destination.relative_to(ROOT).as_posix();produced.append(a)
            records.append(dict(asset=a,inputs=[dict(id=v['id'],path=v['path'],bytes=(ROOT/v['path'][6:]).stat().st_size,mtime_ns=(ROOT/v['path'][6:]).stat().st_mtime_ns) for v in inputs],note='Legacy admitted material, not recovery of historical raw source bytes'))
    finally:prev.common.OUT=old_out
    for a in prev.assets(doc):
        if key(a) in names:a['surface_role']='source_detail'
    source=copy.deepcopy(doc['source_registry']['sources'][-1]);source.update(source_id='france_support_r57',version='R57-support-2026-10-21',title='Finite correction of retained French material support')
    source['access_metadata']=dict(upstream_catalogue='data/presentation/europe_surface_r48.json',sampling='Original admitted grids and classes retained; no new source precision',scope=[a['core_bounds_lon_lat'] for a in produced],historical_applicability='Modern physical display reference only')
    fact=copy.deepcopy(doc['evidence_catalog']['facts'][-1]);fact.update(fact_id='physical_relief:france_support_r57',source_id=source['source_id'],source_version=source['version'],generator='tools/map/build_surface_r57.py',methodology='Canonical colour/support composition; preserved source spacing; complete existing area-Mip writer');fact['value']['assets']=produced
    doc['source_registry']['sources']=[v for v in doc['source_registry']['sources'] if v['source_id']!=source['source_id']]+[source]
    doc['evidence_catalog']['facts']=[v for v in doc['evidence_catalog']['facts'] if v['fact_id']!=fact['fact_id']]+[fact]
    save(ROOT/'data/presentation/sampling_surface_r57.json',doc);save(root/'france_support_sources.json',records)
    print('French support repair',len(produced),sum(a['bytes'] for a in produced),'bytes; no network')


def africa_edge_repair(stage):
    """One proved R55 classification edge; retained material elsewhere."""
    root=WORK/'continuity-repair-2026-10-21';root.mkdir(parents=True,exist_ok=True)
    target_path=root/'africa_target.json'
    bounds=[-20,10,40,21];guard=[-20.2,9.8,40.2,21.2]
    if stage=='acquire':
        class Sources(PetersburgSources):
            def __init__(self):
                self.root=root;self.path=root/'sources.json';self.pilot=read(PILOT)
                self.plan={'head_metadata':[]};self.cache={};self.http=None
                self.data=read(self.path) if self.path.exists() else dict(schema='r57_local_edge_sources_1',network_body_bytes=0,network_reserved_bytes=0,write_bytes=0,peak_bytes=0,dem={},cover={},etopo={},outputs={})
            def charge(self,amount):
                if self.data['network_reserved_bytes']+amount>32*1024**2:raise RuntimeError('Local edge32MiB network limit reached')
                super().charge(amount)
            def disk(self,reserve=0):
                total=sum(p.stat().st_size for p in self.root.rglob('*') if p.is_file())
                if total+reserve>64*1024**2:raise RuntimeError('Local edge64MiB retained-input limit reached')
                self.data['peak_bytes']=max(self.data['peak_bytes'],total+reserve)
        owner=Sources();known=read(GLOBAL_WORK/'worldcover_objects.json');cache=read(GLOBAL_WORK/'sources.json')['cover']
        needed=[f'ESA_WorldCover_10m_2021_v200_N{y:02d}{"E" if x>=0 else "W"}{abs(x):03d}_Map.tif' for y in (9,12,15,18) for x in range(-21,42,3)]
        reused=[];unavailable=[]
        for name in needed:
            prior=cache.get(name+':225:foundation')
            if prior is not None:reused.append(prior)
            else:
                if name not in known:
                    unavailable.append(name);continue # Declared provider ocean/absent cells remain unknown.
                owner.plan['head_metadata'].append(dict(kind='cover',**known[name]))
        with owner:
            etopo=owner.etopo(guard,'africa_edge_18N_full_south')
            cover=reused+[owner.cover(item['key'],225,label='africa_edge') for item in owner.plan['head_metadata']]
        doc=read(ROOT/'data/presentation/sampling_surface_r57.json')
        original=next(a for a in prev.assets(doc) if key(a)=='euro_afro_russia_r57_base')
        # Freeze the source-only predecessor, not a copy of the whole PCK.
        target=dict(schema='r57_local_classification_edge_1',bounds=bounds,calculation_bounds=guard,size=[1800,330],calculation_size=[1812,342],original=original,etopo=etopo,cover=cover,unavailable_provider_cells=unavailable,network_body_bytes=owner.data['network_body_bytes'],method='Real225/3degree WorldCover palette-before-area colours across missing-source18N edge down to existing10N overview edge; same ETOPO metric shade. Preserve original Mip0 outside local support and independent A in Mip0. Rebuild all area Mips.')
        save(target_path,target);print('Local edge sources',target['network_body_bytes'],'network bytes;',len(cover),'classification windows',flush=True);return
    if stage!='build':raise ValueError('Unknown local edge stage')
    target=read(target_path);original=target['original']
    require_inputs(ROOT,[original['path'][6:],target['etopo']['path']]+[r['path'] for r in target['cover']],'Local18N material correction')
    inputs=FoundationInputs(target['etopo'],[],target['cover'],feather=bounds)
    _,height,shade,_,_=field(guard,(1812,342),False,False,inputs)
    observed,records=inputs.colour(bounds,(1800,330))
    height=height[6:-6,6:-6];shade=shade[6:-6,6:-6]
    if height.shape!=(330,1800):raise ValueError('Local correction is not aligned with retained overview')
    level=np.log1p(np.maximum(height,0)/200)/np.log(26);upland=prev.common.smooth(.2,.95,level)
    corrected=np.clip((observed*(1-upland[:,:,None]*.4)+np.array([.70,.68,.62])*upland[:,:,None]*.4)*shade[:,:,None],0,1)
    pixels=prev.decode(original);before=pixels.copy();w,s,e,n=original['bounds_lon_lat']
    x0=round((bounds[0]-w)*30);y0=round((n-bounds[3])*30)
    xx,yy=FiniteInputs.grid(bounds,(1800,330))
    # Only the proved classification boundary changes. This is a transition
    # between real observations and retained material, never blurred terrain.
    weight=prev.common.smooth(-20,-18,xx)*(1-prev.common.smooth(38,40,xx))*(1-prev.common.smooth(19.5,21,yy))
    patch=pixels[y0:y0+330,x0:x0+1800,:3]
    patch[:]=patch*(1-weight[:,:,None])+corrected*weight[:,:,None]
    expected=np.uint8(pixels*255+.5)
    if not np.array_equal(expected[:,:,3],np.uint8(before[:,:,3]*255+.5)):raise ValueError('Neutral DEM channel changed')
    mask=np.ones(before.shape[:2],dtype=bool);mask[y0:y0+330,x0:x0+1800]=False
    if not np.array_equal(expected[mask],np.uint8(before[mask]*255+.5)):raise ValueError('Material outside declared correction changed')
    name='euro_afro_russia_r57_continuity_base';a=write(name,pixels,original['bounds_lon_lat'])
    for k in ('surface_role','core_inset_degrees','surface_feather_degrees','precision'):a[k]=copy.deepcopy(original[k])
    a['surface_role']='base'
    a.update(surface_replaces=[key(original)],source_assets=[original['id']],dem_source='Retained R57 ETOPO overview; real native60s ETOPO only inside declared local correction',cover_source='Retained material elsewhere; WorldCover2021-v200 nearest225/3degree in declared10-21N20W-40E correction',local_correction=dict(bounds=bounds,source_record=target_path.relative_to(ROOT).as_posix(),method=target['method']))
    actual=prev.decode(a)
    if np.max(np.abs(actual-pixels))>0.5/255+1e-7:raise ValueError('Local material quantization mismatch')
    # Verify every Mip using the existing writer's area method; no extra images.
    offset=0;level=pixels;raw=zlib.decompress((ROOT/a['path'][6:]).read_bytes()[20:]);old_raw=zlib.decompress((ROOT/original['path'][6:]).read_bytes()[20:]);mips=[]
    while True:
        count=level.shape[0]*level.shape[1]*4;decoded=np.frombuffer(raw[offset:offset+count],dtype='uint8').reshape(level.shape)
        error=float(np.max(np.abs(decoded.astype('float64')/255-level)))
        if error>0.5/255+1e-7:raise ValueError('Local correction Mip mismatch')
        prior=np.frombuffer(old_raw[offset:offset+count],dtype='uint8').reshape(level.shape)
        mx,my=FiniteInputs.grid(a['bounds_lon_lat'],(level.shape[1],level.shape[0]));dx=104/level.shape[1];dy=76/level.shape[0]
        protected=(mx+dx<bounds[0])|(mx-dx>bounds[2])|(my+dy<bounds[1])|(my-dy>bounds[3])
        outside_error=int(np.max(np.abs(decoded[protected].astype('int16')-prior[protected]))) if protected.any() else 0
        neutral_error=int(np.max(np.abs(decoded[:,:,3].astype('int16')-prior[:,:,3])))
        if outside_error>1 or neutral_error>1:raise ValueError('Unrelated overview Mip material changed beyond one quantization unit')
        mips.append(dict(size=list(level.shape[:2]),max_error=error,outside_quantized_error=outside_error,neutral_quantized_error=neutral_error));offset+=count
        if level.shape[:2]==(1,1):break
        level=prev.resize(level,(max(1,level.shape[1]//2),max(1,level.shape[0]//2)))
    if offset!=len(raw):raise ValueError('Unexpected local correction Mip length')
    doc=read(ROOT/'data/presentation/sampling_surface_r57.json')
    for old in prev.assets(doc):
        if key(old)==key(original):old['surface_role']='source_base'
    source=copy.deepcopy(doc['source_registry']['sources'][-1]);source.update(source_id='r57_local_classification_edge',version='R57-18N-2026-10-21',title='Correction of retained shared overview classification support edge')
    source['locator']=target['etopo']['url']
    source['access_metadata']=dict(bounds=bounds,source_record=target_path.relative_to(ROOT).as_posix(),method=target['method'],historical_applicability='Modern natural-reference display only')
    fact=copy.deepcopy(doc['evidence_catalog']['facts'][-1]);fact.update(fact_id='physical_relief:r57_local_classification_edge',subject_id='physical_relief:shared_continuity',spatial_scope={'kind':'geographic_reference','id':'shared_overview_local18N_correction'},source_id=source['source_id'],source_version=source['version'],source_locator=source['locator'],generator='tools/map/build_surface_r57.py',methodology=target['method']);fact['value']={'status':'PHYSICAL_REFERENCE','assets':[a]}
    doc['source_registry']['sources']=[s for s in doc['source_registry']['sources'] if s['source_id']!=source['source_id']]+[source]
    doc['evidence_catalog']['facts']=[f for f in doc['evidence_catalog']['facts'] if f['fact_id']!=fact['fact_id']]+[fact]
    save(ROOT/'data/presentation/sampling_surface_r57.json',doc)
    save(root/'africa_result.json',dict(asset=a,mips=mips,unchanged_outside=True,unchanged_neutral=True,changed_pixels=int(np.count_nonzero(np.any(expected!=np.uint8(before*255+.5),axis=2))),inputs=finite_input_metadata([original['path'][6:],target['etopo']['path']]+[r['path'] for r in target['cover']]),cover=records))
    print('Local18N corrected',a['bytes'],'bytes; other regions and neutral channel retained',flush=True)

# Continental foundation batches reuse the finite source transport, Rasterio,
# material kernel and Mip writer above. No raw sources enter the game catalogue.
GLOBAL_WORK=WORK/'global-region-2026-10-21'
# Bump when field/colour/resampling/Mip semantics change. Transport changes
# alone do not invalidate already-verified material made from identical rasters.
FOUNDATION_MATERIAL_CONTRACT='R57-foundation-material-2'
GLOBAL_BATCHES={
    'oceania':[(104,-56,179.25,0)],
    'south_america':[(-88,-56,-32,16)],
    'africa':[(-20,-36,56,12)],
    'south_asia':[(56,-16,179.25,40)],
    'north_america':[(-179.25,0,-104,84),(-112,0,-48,84)],
    'north_asia':[(64,32,179.25,84)],
}

class GlobalSources(PetersburgSources):
    def __init__(self,batch):
        from collections import OrderedDict
        self.root=GLOBAL_WORK;self.path=self.root/'sources.json';self.root.mkdir(parents=True,exist_ok=True)
        self.pilot=read(PILOT);self.plan={'head_metadata':[]};self.batch=batch
        self.data=read(self.path) if self.path.exists() else dict(schema='r57_global_finite_1',network_body_bytes=0,network_reserved_bytes=0,write_bytes=0,peak_bytes=0,dem={},cover={},etopo={},outputs={},batches={})
        self.data['batches'].setdefault(batch,dict(network_body_bytes=0,network_reserved_bytes=0))
        self.batch_files=set()
        plan=self.root/'production_targets.json'
        declared=read(plan) if plan.exists() else {}
        # Once acquisition is complete, the recipe freezes source declarations
        # in this existing target descriptor. Counters/output-cache changes in
        # sources.json are then outputs, not spurious rebuild inputs.
        if 'source_inputs' in declared:
            for kind in ('etopo','cover'):self.data[kind]=copy.deepcopy(declared['source_inputs'][kind])
        names={t['name'] for t in declared.get('batches',{}).get(batch,[])}
        for name,r in self.data['outputs'].items():
            if name in names:self.batch_files.update([r['etopo'],*r['cover'],r['asset']['path'][6:]])
        if 'batch_'+batch in self.data['etopo']:self.batch_files.add(self.data['etopo']['batch_'+batch]['path'])
        import threading
        self.ledger_lock=threading.RLock();self.last_full_persist=0
        import queue,requests
        self.http_sessions=queue.Queue(4)
        for _ in range(4):self.http_sessions.put(requests.Session())
        budget=self.root/'transport_totals.json'
        if budget.exists():
            old=read(budget)
            for k in ('network_body_bytes','network_reserved_bytes','write_bytes','metadata_write_bytes'):self.data[k]=max(self.data.get(k,0),old.get(k,0))
            for name,row in old.get('batches',{}).items():
                b=self.data['batches'].setdefault(name,{})
                for k,v in row.items():b[k]=max(b.get(k,0),v)
        class LimitedCache(OrderedDict):
            def __setitem__(self,k,v):
                super().__setitem__(k,v)
                while len(self)>8192:self.popitem(last=False) #128MiB, process-local only.
            def __getitem__(self,k):
                value=super().__getitem__(k);self.move_to_end(k);return value
        self.cache=LimitedCache();self.http=None
    def persist(self,force=False):
        with self.ledger_lock:
            def store(path,document):
                before=self.data.get('metadata_write_bytes',0);size=-1
                while True:
                    document['metadata_write_bytes']=self.data.get('metadata_write_bytes',0)
                    payload=(json.dumps(document,ensure_ascii=False,separators=(',',':'))+'\n').encode('utf8')
                    if len(payload)==size:break
                    size=len(payload);self.data['metadata_write_bytes']=before+size
                path.write_bytes(payload)
            if force or time.monotonic()-self.last_full_persist>60:
                store(self.path,self.data);self.last_full_persist=time.monotonic()
            budget={k:self.data.get(k,0) for k in ('network_body_bytes','network_reserved_bytes','write_bytes')}
            budget['batches']={name:{k:r.get(k,0) for k in ('network_body_bytes','network_reserved_bytes')} for name,r in self.data['batches'].items()}
            store(self.root/'transport_totals.json',budget)
    def charge(self,amount):
        with self.ledger_lock:
            b=self.data['batches'][self.batch]
            if b['network_reserved_bytes']+amount>512*1024**2 or self.data['network_reserved_bytes']+amount>2*1024**3:raise RuntimeError('Source network batch/round budget reached')
            b['network_reserved_bytes']+=amount;self.data['network_reserved_bytes']+=amount;self.persist()
    def fetch(self,url,length,start=None):
        session=self.http_sessions.get()
        try:return self.fetch_range(session,url,length,start)
        finally:self.http_sessions.put(session)
    def fetch_range(self,session,url,length,start=None):
        self.charge(length);headers={'Accept-Encoding':'identity'}
        if start is not None:headers['Range']=f'bytes={start}-{start+length-1}'
        r=session.get(url,headers=headers,stream=True,timeout=60);chunks=[];count=0
        try:
            if r.status_code!=(206 if start is not None else 200) or int(r.headers.get('Content-Length',-1))!=length:raise ValueError('Invalid finite provider response; no full fallback')
            if start is not None and not r.headers.get('Content-Range','').startswith(f'bytes {start}-{start+length-1}/'):raise ValueError('Invalid provider Range')
            for chunk in r.iter_content(65536):
                with self.ledger_lock:
                    self.data['network_body_bytes']+=len(chunk);self.data['batches'][self.batch]['network_body_bytes']+=len(chunk)
                count+=len(chunk);chunks.append(chunk)
                if count>length:raise ValueError('Oversized source body')
            if count!=length:raise ValueError('Incomplete source body')
            return b''.join(chunks),dict(last_modified=r.headers.get('Last-Modified'),version_id=r.headers.get('x-amz-version-id'))
        finally:r.close();self.persist()
    def tiff(self,*args):
        with self.ledger_lock:
            self.batch_files.add(Path(args[0]).relative_to(ROOT).as_posix());super().tiff(*args)
    def disk(self,reserve=0):
        total=sum(p.stat().st_size for p in self.root.rglob('*') if p.is_file())
        formal=sum((ROOT/p).stat().st_size for p in self.data.get('published',[]) if (ROOT/p).is_file())
        if total+formal+reserve>2*1024**3:raise RuntimeError('2GiB new terrain round disk budget reached')
        b=self.data['batches'][self.batch];b.setdefault('disk_start',total+formal)
        own=sum((ROOT/p).stat().st_size for p in tuple(self.batch_files) if (ROOT/p).is_file())
        if own+reserve>1024**3:raise RuntimeError('1GiB batch input/output disk budget reached')
        b['peak_bytes']=max(b.get('peak_bytes',0),own+reserve)
        self.data['peak_bytes']=max(self.data['peak_bytes'],total+formal+reserve)
    def listing(self):
        path=self.root/'worldcover_objects.json'
        if path.exists():return read(path)
        import requests,xml.etree.ElementTree as ET
        objects={};token=None
        while True:
            params={'list-type':'2','prefix':'v200/2021/map/','max-keys':1000}
            if token:params['continuation-token']=token
            r=requests.get('https://esa-worldcover.s3.eu-central-1.amazonaws.com',params=params,stream=True,timeout=60)
            try:
                r.raise_for_status();reserved=int(r.headers.get('Content-Length',1024**2));self.charge(reserved)
                chunks=[];length=0
                for chunk in r.iter_content(65536):
                    length+=len(chunk);self.data['network_body_bytes']+=len(chunk);self.data['batches'][self.batch]['network_body_bytes']+=len(chunk)
                    if length>reserved:raise ValueError('Provider listing exceeds finite reservation')
                    chunks.append(chunk)
                payload=b''.join(chunks)
                self.data['network_reserved_bytes']-=reserved-length;self.data['batches'][self.batch]['network_reserved_bytes']-=reserved-length
                doc=ET.fromstring(payload);ns={'s':'http://s3.amazonaws.com/doc/2006-03-01/'}
                for item in doc.findall('s:Contents',ns):
                    key=item.findtext('s:Key',namespaces=ns)
                    if not key.endswith('_Map.tif'):continue
                    objects[key.rsplit('/',1)[1]]=dict(key=key.rsplit('/',1)[1],url='https://esa-worldcover.s3.eu-central-1.amazonaws.com/'+key,bytes=int(item.findtext('s:Size',namespaces=ns)))
                token=doc.findtext('s:NextContinuationToken',namespaces=ns)
                self.persist()
                if not token:break
            finally:r.close()
        save(path,objects);return objects
    def __enter__(self):
        if self.data.get('http_error'):self.data['last_failed_transport']=self.data.pop('http_error')
        self.objects=self.listing();super().__enter__()
        self.parallel_env=rasterio.Env(GDAL_HTTP_MULTIRANGE='YES',GDAL_HTTP_MERGE_CONSECUTIVE_RANGES='NO',GDAL_HTTP_MAX_TOTAL_CONNECTIONS='4',GDAL_HTTP_MAX_CACHED_CONNECTIONS='4');self.parallel_env.__enter__()
        for key,item in self.objects.items():self.urls['/'+key]=item
        return self
    def __exit__(self,*args):
        self.parallel_env.__exit__(*args);super().__exit__(*args);self.persist(True)
        while not self.http_sessions.empty():self.http_sessions.get().close()
    def etopo(self,*args):
        r=super().etopo(*args);self.batch_files.add(r['path']);return r
    def cover_box(self,bounds):
        keys=[]
        for key,item in self.objects.items():
            import re
            m=re.search(r'_([NS])(\d+)([EW])(\d+)_Map',key)
            y=int(m[2])*(1 if m[1]=='N' else -1);x=int(m[4])*(1 if m[3]=='E' else -1)
            if intersects([x,y,x+3,y+3],bounds):keys.append(key)
        from concurrent.futures import ThreadPoolExecutor
        def extract(key):
            with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN='EMPTY_DIR',GDAL_HTTP_TIMEOUT='70',GDAL_HTTP_MAX_RETRY='1',GDAL_HTTP_RETRY_DELAY='1',GDAL_HTTP_MULTIRANGE='SERIAL',CPL_VSIL_CURL_ALLOWED_EXTENSIONS='.tif',PROJ_NETWORK='OFF'):
                r=self.cover(key,225,label='foundation');self.batch_files.add(r['path']);return r
        with ThreadPoolExecutor(max_workers=4) as pool:return list(pool.map(extract,keys))

class FoundationInputs(FiniteInputs):
    def validate(self,bounds,size,read_cover=True):
        super().validate(bounds,size,False)
        for r in self.cover:
            require_inputs(ROOT,[r['path']],'Global foundation categorical window')
            if raster_metadata(ROOT/r['path'])!=r['raster'] or r['product']!='WorldCover2021-v200' or r['method']!='nearest':raise ValueError('Changed foundation classification input')
        # Absent provider tiles and actual class0 are explicitly unavailable,
        # not invented zero-valued WorldCover observations. DEM support is full.
    def height(self,bounds,size,fine):return self.stable_dem(self.etopo,bounds,size),[]
    def colour(self,bounds,size):
        # Assemble the declared categorical grid in memory before its palette.
        # One warp can integrate real neighbouring classes across3degree files;
        # per-file overwrite at a fractional output pixel is not area mixing.
        nx,ny=size;w=math.floor(bounds[0]/3)*3;s=math.floor(bounds[1]/3)*3
        e=math.ceil(bounds[2]/3)*3;n=math.ceil(bounds[3]/3)*3
        classes=np.zeros((round((n-s)*75),round((e-w)*75)),dtype='uint8');records=[]
        for r in self.cover:
            if not intersects(r['raster']['bounds'],bounds):continue
            with rasterio.open(ROOT/r['path']) as src:
                values=src.read(1)
                if src.shape!=(225,225) or not np.allclose([src.transform.a,src.transform.e],[1/75,-1/75],atol=1e-12,rtol=0):raise ValueError('Foundation categorical grid changed')
                if not set(np.unique(values)).issubset({0,10,20,30,40,50,60,70,80,90,95,100}):raise ValueError('Invalid discrete foundation class')
                x=round((src.bounds.left-w)*75);y=round((n-src.bounds.top)*75)
                classes[y:y+225,x:x+225]=values
                c=self.cell(r);c.update(bounds=intersection(c['bounds'],bounds),shape=[225,225],method='nearest225/3degree categorical mosaic; palette before area colour resampling;0 unavailable')
                records.append(c)
        transform=from_bounds(w,s,e,n,classes.shape[1],classes.shape[0]);target=from_bounds(*bounds,nx,ny)
        observed=np.empty((ny,nx,3),dtype='float32')
        for channel in range(3):
            reproject(sib.PALETTE[classes,channel],observed[:,:,channel],src_transform=transform,src_crs='EPSG:4326',dst_transform=target,dst_crs='EPSG:4326',resampling=Resampling.average,XSCALE=transform.a/target.a,YSCALE=abs(transform.e/target.e))
        return observed,records

def foundation_targets(batch):
    declared=GLOBAL_WORK/'production_targets.json'
    if declared.exists():
        document=read(declared)
        if document['domains']!={k:[list(v) for v in values] for k,values in GLOBAL_BATCHES.items()}:raise ValueError('Foundation declared domains changed')
        return document['batches'][batch]
    import re
    known=(ROOT/'local-artifacts/france-surface-r42/copdem_tileList.txt').read_text(encoding='utf8')
    cells={(int(m[4])*(1 if m[3]=='E' else -1),int(m[2])*(1 if m[1]=='N' else -1)) for m in re.finditer(r'Copernicus_DSM_COG_30_([NS])(\d+)_00_([EW])(\d+)_00_DEM',known)}
    current=prev.assets(read(ROOT/'data/presentation/sampling_surface_r57.json'))
    middle=[a['core_bounds_lon_lat'] for a in current if a.get('surface_role')=='detail' and a.get('surface_lod_degrees') in [8,16] and not a.get('foundation_batch')]
    targets={}
    for index,domain in enumerate(GLOBAL_BATCHES[batch]):
        overview=[max(-179.25,math.floor(domain[0]/16)*16),max(-84,math.floor(domain[1]/16)*16),min(179.25,math.ceil(domain[2]/16)*16),min(84,math.ceil(domain[3]/16)*16)]
        targets[f'global_region_r57_{batch}_base{index}']=dict(name=f'global_region_r57_{batch}_base{index}',core=overview,role='base',step=1/32)
        for y in range(math.floor(domain[1]/16)*16,math.ceil(domain[3]/16)*16,16):
            for x in range(math.floor(domain[0]/16)*16,math.ceil(domain[2]/16)*16,16):
                core=[max(-179.25,x),max(-84,y),min(179.25,x+16),min(84,y+16)]
                continuity_only=not any(intersects(core,[xx,yy,xx+1,yy+1]) for xx,yy in cells)
                if any(contains(b,core) for b in middle):continue
                name=f'global_region_r57_16_{y:+03d}_{x:+04d}'
                targets[name]=dict(name=name,core=core,role='detail',step=1/64)
                if continuity_only:targets[name]['continuity_neighbor']=True
    return list(targets.values())

def foundation_build(batch):
    if batch not in GLOBAL_BATCHES:raise ValueError('Undeclared foundation batch')
    with GlobalSources(batch) as sources:
        targets=foundation_targets(batch);targets.sort(key=lambda t:(t['role']=='base',t['name']!='global_region_r57_16_-48_+144',t['name']))
        out=GLOBAL_WORK/'material';out.mkdir(exist_ok=True)
        # Native windows cover the whole page,32display-pixel collar and8extra
        # calculation pixels. No global file or falsely named original is made.
        union=[min(t['core'][0] for t in targets),min(t['core'][1] for t in targets),max(t['core'][2] for t in targets),max(t['core'][3] for t in targets)]
        class_count=sum(1 for key in sources.objects if any(intersects([int(m[4])*(1 if m[3]=='E' else -1),int(m[2])*(1 if m[1]=='N' else -1),int(m[4])*(1 if m[3]=='E' else -1)+3,int(m[2])*(1 if m[1]=='N' else -1)+3],[union[0]-.625,union[1]-.625,union[2]+.625,union[3]+.625]) for m in [__import__('re').search(r'_([NS])(\d+)([EW])(\d+)_Map',key)]))
        raw_upper=(union[2]-union[0]+2)*(union[3]-union[1]+2)*60**2*4
        estimates=dict(native_window_payload_upper=raw_upper,categorical_windows=class_count,categorical_payload_upper=class_count*(225*225+65536),network_estimate=raw_upper*1.3+class_count*262144,mip_bin_upper=sum(int((t['core'][2]-t['core'][0]+1)/t['step'])*int((t['core'][3]-t['core'][1]+1)/t['step'])*4*4/3+65536 for t in targets),network_hard_limit=512*1024**2,temporary_hard_limit=1024**3)
        sources.data['batches'][batch]['estimate']=estimates;sources.persist();print(batch,'targets',len(targets),'estimate',estimates,flush=True)
        records=[]
        unfinished=[t for t in targets if not sources.data['outputs'].get(t['name'])]
        broad=None
        if unfinished:
            union=[min(t['core'][0] for t in targets)-.625,min(t['core'][1] for t in targets)-.625,max(t['core'][2] for t in targets)+.625,max(t['core'][3] for t in targets)+.625]
            broad=sources.etopo(union,'batch_'+batch)
        for t in targets:
            previous=sources.data['outputs'].get(t['name'])
            if previous and (ROOT/previous['asset']['path'][6:]).is_file() and previous['target']==t:
                raster_paths=[previous['etopo']]+previous['cover'];now=finite_input_metadata(raster_paths)
                if all(previous['inputs'].get(p)==now[p] for p in raster_paths) and previous.get('material_contract','R57-foundation-material-1')==FOUNDATION_MATERIAL_CONTRACT:
                    records.append(previous);continue
            step=t['step'];core=t['core'];pad=.375 if t['role']=='base' else 32*step
            bounds=[core[0]-pad,core[1]-pad,core[2]+pad,core[3]+pad];size=[round((bounds[2]-bounds[0])/step),round((bounds[3]-bounds[1])/step)]
            calc=[bounds[0]-8*step,bounds[1]-8*step,bounds[2]+8*step,bounds[3]+8*step]
            # Individual finite windows bound network/disk; cached catalogue
            # objects and extracted classes are reused by every later consumer.
            supported=[r for r in sources.data['etopo'].values() if contains(r['raster']['bounds'],[calc[0]-1/60,calc[1]-1/60,calc[2]+1/60,calc[3]+1/60])]
            etopo=min(supported,key=lambda r:(r['raster']['bounds'][2]-r['raster']['bounds'][0])*(r['raster']['bounds'][3]-r['raster']['bounds'][1])) if supported else sources.etopo(calc,t['name'])
            cover=sources.cover_box(calc)
            inputs=FoundationInputs(etopo,[],cover)
            pixels,h,shade,dem,classes=field(calc,[size[0]+16,size[1]+16],False,True,inputs)
            pixels=pixels[8:-8,8:-8];sources.disk(pixels.nbytes*2+65536)
            a=write(t['name'],pixels,bounds,out)
            a.update(core_bounds_lon_lat=core,surface_role=t['role'],surface_lod_degrees=16,surface_replaces=[],surface_display_max_mpp=3500,surface_fade_mpp=2000,precision=precision(a,dem,classes),foundation_batch=batch,dem_source='ETOPO2022-v1 native60arcsec surface only;1853.25m N-S; not GLO',cover_source='Actual WC2021-v200 nearest225 samples/3degrees,1482.6m N-S; provider-absent tiles and class0 unavailable',surface_group='sampling_r57')
            if t.get('continuity_neighbor'):a['foundation_continuity_neighbor']=True
            a['precision'].update(dem_type='ETOPO surface',dem_native_m_ns=1853.25,dem_extract_m_ns=1853.25,cover_unavailable='Neutral reference only where provider tile absent or class0; not a land-use assertion')
            if t['role']=='base':a.update(core_inset_degrees=0,surface_feather_degrees=[pad,pad,pad,pad],foundation_domain=True,surface_display_max_mpp=4500,surface_fade_mpp=3000)
            # Read the just-written stream, including all Mip lengths and the
            # same existing per-channel area/quantization contract.
            payload=(ROOT/a['path'][6:]).read_bytes();w,hh,length=struct.unpack('<III',payload[8:20]);raw=zlib.decompress(payload[20:]);offset=0;level=pixels;largest=0
            while True:
                count=level.size;decoded=np.frombuffer(raw[offset:offset+count],dtype='uint8').reshape(level.shape);largest=max(largest,float(np.max(np.abs(decoded/255-level))))
                offset+=count
                if level.shape[:2]==(1,1):break
                level=prev.resize(level,(max(1,level.shape[1]//2),max(1,level.shape[0]//2)))
            if (w,hh)!=(size[0],size[1]) or offset!=length or len(raw)!=length or largest>0.5/255+1e-7:raise ValueError('Foundation Mip layout or quantization failed')
            sources.data['write_bytes']+=len(payload)
            record=dict(target=t,material_contract=FOUNDATION_MATERIAL_CONTRACT,asset=a,etopo=etopo['path'],cover=[r['path'] for r in cover],inputs=finite_input_metadata([etopo['path']]+[r['path'] for r in cover]),height_range=[float(h.min()),float(h.max())],max_mip_quantization_error=largest)
            sources.data['outputs'][t['name']]=record;sources.batch_files.add(a['path'][6:]);records.append(record);sources.persist(True)
            print('built',t['name'],a['bytes'],'network',sources.data['network_body_bytes'],flush=True)
        save(GLOBAL_WORK/(batch+'_targets.json'),records)
        sources.data['batches'][batch]['seams']=foundation_seams(records)
        sources.data['batches'][batch]['offline_complete']=True;sources.persist(True)

def foundation_seams(records):
    # Only neighbouring outputs of this new batch. No scan of existing BINs.
    from rasterio.windows import from_bounds as wb
    pairs=0;maximum=0;levels_checked=set()
    details=[r['asset'] for r in records if r['asset']['surface_role']=='detail']
    for index,a in enumerate(details):
        for b in details[index+1:]:
            ca,cb=a['core_bounds_lon_lat'],b['core_bounds_lon_lat']
            adjacent=(ca[2]==cb[0] or cb[2]==ca[0]) and ca[1]==cb[1] and ca[3]==cb[3] or (ca[3]==cb[1] or cb[3]==ca[1]) and ca[0]==cb[0] and ca[2]==cb[2]
            if not adjacent:continue
            overlap=intersection(a['bounds_lon_lat'],b['bounds_lon_lat']);chains=[]
            for v in [a,b]:
                raw=zlib.decompress((ROOT/v['path'][6:]).read_bytes()[20:]);offset=0;ww,hh=v['width'],v['height'];chain=[]
                for mip in range(7):
                    count=ww*hh*4;arr=np.frombuffer(raw[offset:offset+count],dtype='uint8').reshape(hh,ww,4);offset+=count
                    win=wb(*overlap,from_bounds(*v['bounds_lon_lat'],ww,hh));aligned=all(abs(q-round(q))<1e-7 for q in [win.row_off,win.col_off,win.width,win.height])
                    chain.append(arr[round(win.row_off):round(win.row_off+win.height),round(win.col_off):round(win.col_off+win.width)] if aligned else None);ww=max(1,ww//2);hh=max(1,hh//2)
                chains.append(chain)
            for mip,(left,right) in enumerate(zip(*chains)):
                if left is None or right is None or left.shape!=right.shape or not left.size:continue
                error=int(np.max(np.abs(left.astype('int16')-right.astype('int16'))));maximum=max(maximum,error);levels_checked.add(mip)
            pairs+=1
    if maximum>1:raise ValueError(f'New foundation shared collar differs {maximum}/255')
    print('foundation shared collars',pairs,'aligned Mips',sorted(levels_checked),'maximum',maximum,'/255',flush=True)
    return dict(adjacent_pairs=pairs,aligned_mips=sorted(levels_checked),maximum_byte_error=maximum,coarse_mips='Full per-channel area contract checked; geographically different footprints are not compared as identical samples')

def foundation_publish(batch):
    sources=GlobalSources(batch);records=read(GLOBAL_WORK/(batch+'_targets.json'))
    if not sources.data['batches'][batch].get('offline_complete'):raise ValueError('Batch not offline complete')
    # All declared inputs and staged products must still be the validated
    # generation before the first formal file is replaced. Metadata only;
    # the material/NoData/Mip checks were performed by the producer above.
    for r in records:
        paths=[r['etopo']]+r['cover'];require_inputs(ROOT,paths+[r['asset']['path'][6:]],'Foundation publication')
        current=finite_input_metadata(paths)
        if r.get('material_contract')!=FOUNDATION_MATERIAL_CONTRACT or any(r['inputs'].get(p)!=current[p] for p in paths):raise ValueError('Foundation inputs changed after material validation')
        if (ROOT/r['asset']['path'][6:]).stat().st_size!=r['asset']['bytes']:raise ValueError('Changed staged foundation product')
    doc=read(ROOT/'data/presentation/sampling_surface_r57.json');new=[];temporary=[]
    for record in records:
        a=copy.deepcopy(record['asset']);src=ROOT/a['path'][6:];dst=prev.common.OUT/src.name
        sources.batch_files.add(dst.relative_to(ROOT).as_posix())
        if src!=dst and (not dst.exists() or dst.stat().st_size!=src.stat().st_size or dst.stat().st_mtime_ns<src.stat().st_mtime_ns):sources.disk(src.stat().st_size);dst.write_bytes(src.read_bytes());sources.data['write_bytes']+=dst.stat().st_size
        a['path']='res://'+dst.relative_to(ROOT).as_posix();new.append(a)
        if src!=dst:temporary.append(src)
        record['asset']=a;sources.data['outputs'][record['target']['name']]=record
    source=copy.deepcopy(next((s for s in doc['source_registry']['sources'] if s['source_id']=='global_foundation_r57_'+batch),doc['source_registry']['sources'][-1]));source.update(source_id='global_foundation_r57_'+batch,title='Finite continental REGION foundation: '+batch,version='R57-foundation-2026-10-21',publisher='NOAA NCEI; ESA WorldCover consortium',license='CC0-1.0+CC-BY-4.0',locator=sources.pilot['etopo']['url'])
    source['access_metadata']=dict(product='ETOPO2022-v1-60s-surface and WorldCover2021-v200',sampling='Native ETOPO60s, compoundEPSG9518, original integer row/column offsets retained. WC nearest225/3degree, palette then area RGB. Sources are finite windows, not full originals.',source_records=sources.path.relative_to(ROOT).as_posix(),source_epoch='2022 composite /2021 modern reference',cover_source='https://esa-worldcover.org/en/data-access',cover_doi='10.5281/zenodo.7254221',cover_license='https://creativecommons.org/licenses/by/4.0/',historical_applicability='Modern physical display reference only, no1900 land-use/economic/political facts',attribution='NOAA NCEI ETOPO2022; © ESA WorldCover project2021 / Contains modified Copernicus Sentinel data2021 processed by ESA WorldCover consortium',limitations='ETOPO1853m effective N-S. No GLO precision. Native sea/land geometry remains the existing physical GIS. Missing class0/provider tiles are unknown.')
    fact=copy.deepcopy(next((f for f in doc['evidence_catalog']['facts'] if f['fact_id']=='physical_relief:global_foundation_r57_'+batch),doc['evidence_catalog']['facts'][-1]));fact.update(fact_id='physical_relief:global_foundation_r57_'+batch,source_id=source['source_id'],source_version=source['version'],source_locator=source['locator'],license=source['license'],subject_id='physical_relief:global_foundation_'+batch,spatial_scope={'kind':'geographic_reference','id':batch},observation_period={'from':'2021-01-01','to':'2022-12-31'},generator='tools/map/build_surface_r57.py',methodology='Same R57 finite-source material kernel and encoding6 Mips; continental source windows; categorical nearest then colour area sampling.');fact['value']['assets']=new
    if source not in doc['source_registry']['sources'] or fact not in doc['evidence_catalog']['facts']:
        doc['source_registry']['sources']=[s for s in doc['source_registry']['sources'] if s['source_id']!=source['source_id']]+[source]
        doc['evidence_catalog']['facts']=[f for f in doc['evidence_catalog']['facts'] if f['fact_id']!=fact['fact_id']]+[fact];save(ROOT/'data/presentation/sampling_surface_r57.json',doc)
    save(GLOBAL_WORK/(batch+'_targets.json'),records)
    sources.data['published']=sorted(set(sources.data.get('published',[]))|{a['path'][6:] for a in new})
    b=sources.data['batches'][batch];b['published_scope_bytes']=sum(a['bytes'] for a in new);b['published_bytes']=sum(a['bytes'] for a in new if a['foundation_batch']==batch);b['owned_assets']=len([a for a in new if a['foundation_batch']==batch]);sources.persist(True);print('published',batch,len(new),sum(a['bytes'] for a in new),flush=True)
    if temporary:
        if '--defer-cleanup' in sys.argv:
            # The unified recipe owns these exact temporary_outputs and holds
            # the build lock. It retires them after export; do not lock twice.
            sources.data['batches'][batch]['cleanup_deferred_to_recipe']=[p.relative_to(ROOT).as_posix() for p in temporary];sources.persist(True);return
        sys.path.insert(0,str(ROOT/'tools/build'));from preview import Manager,record as file_record
        manager=Manager();owned={p.relative_to(ROOT).as_posix():file_record(p.stat()) for p in temporary if p.resolve().is_relative_to(GLOBAL_WORK/'material')}
        with manager.lock():
            manager.state.setdefault('temporary',{}).update(owned);manager.save();clean=manager.cleanup(True,only=owned)
        b=sources.data['batches'][batch];b['cleanup']=dict(files=clean['deleted_files'],bytes=clean['deleted_bytes'],skipped=clean['skipped'])
        total=b.setdefault('cleanup_cumulative',dict(files=0,bytes=0));total['files']+=clean['deleted_files'];total['bytes']+=clean['deleted_bytes'];sources.persist(True)

if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf8')
    phase=next((v.split('=',1)[1] for v in sys.argv if v.startswith('--petersburg=')),None)
    global_phase=next((v.split('=',1)[1] for v in sys.argv if v.startswith('--foundation=')),None)
    edge=next((v.split('=',1)[1] for v in sys.argv if v.startswith('--repair-africa-edge=')),None)
    if edge is not None:africa_edge_repair(edge)
    elif global_phase is not None:
        action,batch=global_phase.split(':',1)
        if action=='build':foundation_build(batch)
        elif action=='publish':foundation_publish(batch)
        elif action=='deliver':
            for name in (GLOBAL_BATCHES if batch=='all' else batch.split(',')):foundation_build(name);foundation_publish(name)
        else:raise ValueError('Unknown foundation phase')
    elif '--france-support' in sys.argv:france_support_repair()
    elif phase is not None:
        if phase.startswith('acquire-'):petersburg_acquire(phase.split('-',1)[1])
        elif phase.startswith('build-'):petersburg_build(phase.split('-',1)[1])
        elif phase=='publish':petersburg_publish()
        elif phase=='deliver':petersburg_build('rest');petersburg_publish()
        else:raise ValueError('Unknown finite phase')
    elif '--acquire-moscow-collar' in sys.argv:
        prev.common.RESEARCH=WORK
        records=[dict(x=x,y=y,**prev.common.cog_extract('dem',x,y)) for y in [53,54] for x in [39,40]]
        save(WORK/'finite_dem_sources.json',records)
    else:build()
