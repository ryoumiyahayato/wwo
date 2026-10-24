"""Finite R56 source/material repair. Offline only; no world or save state.

Stages: acquire, demos, canonical, pages, catalogue. Original sources and R55
assets remain intact. Intermediate pages reuse actual admitted source material.
"""
import concurrent.futures as futures
import copy,json,math,struct,sys,zlib
if __name__ == '__main__':
    from generation_policy import enter
    from pathlib import Path as GenerationPath
    enter(GenerationPath(__file__).resolve().parents[2], 'sampling_surface_r56.json')

from pathlib import Path
import numpy as np
from PIL import Image
import rasterio
from rasterio.enums import Resampling
from rasterio.transform import from_bounds
from rasterio.warp import reproject
from scipy.ndimage import gaussian_filter,map_coordinates
import build_france_surface_r42 as common
import build_siberian_surface_r50 as sib
import build_european_surface_r55 as old

ROOT=common.ROOT
WORK=ROOT/'local-artifacts/terrain-r56'
DOMAINS={'alps_po':(8,40,16,48),'polesia':(24,48,32,56)}
CAT=ROOT/'data/presentation/european_surface_r55.json'
STEP=1/512

def save(path,obj):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf8')

def read(path):return json.loads(path.read_text(encoding='utf8'))

def assets(doc):return [a for f in doc['evidence_catalog']['facts'] for a in f['value']['assets']]

def decode(a,lod=0):
    data=(ROOT/a['path'].removeprefix('res://')).read_bytes()
    w,h,length=struct.unpack('<III',data[8:20]);raw=zlib.decompress(data[20:])
    assert len(raw)==length
    offset=0
    for _ in range(lod):
        if w==h==1:break
        offset+=w*h*4;w=max(1,w//2);h=max(1,h//2)
    return np.frombuffer(raw[offset:offset+w*h*4],dtype='uint8').reshape(h,w,4).astype('float32')/255

def canonical(p,encoding):
    p=p.copy()
    if encoding==5:return p
    if encoding:
        # R43/R44/R45/R46 use shade-.4, whose valid range starts at.08.
        # Their shared producer multiplies that channel by the actual domain
        # mask. A=0 is therefore unsupported, not legitimate dark terrain.
        coverage=common.smooth(.01,.075,p[:,:,3])
        p[:,:,:3]*=(.4+p[:,:,3:4])
    else:
        coverage=p[:,:,3].copy();t=common.smooth(.2,.95,p[:,:,0:1])
        tone=np.array([.57,.57,.46])*(1-t)+np.array([.70,.68,.62])*t
        trees=p[:,:,2:3]*.78
        p[:,:,:3]=(tone*(1-trees)+np.array([.27,.38,.27])*trees)*(.4+p[:,:,1:2])
    p[:,:,3]=coverage
    return np.clip(p,0,1)

def resize(a,size):
    return np.stack([np.asarray(Image.fromarray(a[:,:,i].astype('float32')).resize(size,Image.Resampling.BOX)) for i in range(a.shape[2])],axis=-1)

def write(name,p,bounds,role='detail'):
    """Linear RGB; A geographic coverage only. Never use Pillow RGBA resize."""
    h,w=p.shape[:2];levels=[];level=np.clip(p,0,1).astype('float32')
    while True:
        levels.append(np.uint8(np.clip(level,0,1)*255+.5).tobytes())
        if level.shape[:2]==(1,1):break
        size=(max(1,level.shape[1]//2),max(1,level.shape[0]//2))
        prem=level.copy();prem[:,:,:3]*=prem[:,:,3:4]
        prem=resize(prem,size)
        prem[:,:,:3]=np.divide(prem[:,:,:3],prem[:,:,3:4],out=np.zeros_like(prem[:,:,:3]),where=prem[:,:,3:4]>1e-8)
        level=prem
    raw=b''.join(levels);path=common.OUT/(name+'.bin')
    path.write_bytes(b'FRT42\0\0\0'+struct.pack('<III',w,h,len(raw))+zlib.compress(raw,6))
    dx=(bounds[2]-bounds[0])/w;dy=(bounds[3]-bounds[1])/h
    return dict(id='physical_relief:'+name,path='res://'+path.relative_to(ROOT).as_posix(),format='RGBA8_MIP_DEFLATE',width=w,height=h,decoded_bytes=len(raw),bytes=path.stat().st_size,bounds_lon_lat=list(bounds),surface_role=role,core_inset_degrees=32*dx,display_spacing_degrees=[dx,dy],display_spacing_m_approx=[111195*dx*math.cos(math.radians((bounds[1]+bounds[3])/2)),111195*dy],surface_encoding=5,surface_group='sampling_r56',surface_support_fraction=float(p[:,:,3].mean()),channels='Linear RGB baked metric hillshade; independent geographic A. Coverage-premultiplied linear area Mips; never categorical-ID interpolation.')

def resolve(kind,x,y):
    local=WORK/kind/f'{y:+03d}_{x:+04d}.tif'
    if local.exists():return local
    return old.resolve(kind,x,y)

def acquire():
    WORK.mkdir(parents=True,exist_ok=True);common.RESEARCH=WORK;sib.WORK=WORK
    known=(ROOT/'local-artifacts/france-surface-r42/copdem_tileList.txt').read_text()
    jobs=set();records=[]
    for w,s,e,n in DOMAINS.values():
        for y in range(s-1,n+1):
            for x in range(w-1,e+1):
                stem=f'Copernicus_DSM_COG_30_N{y:02d}_00_E{x:03d}_00_DEM'
                if stem not in known:continue
                p=resolve('dem',x,y)
                if p:records.append(dict(kind='dem',reused=str(p.relative_to(ROOT))))
                else:jobs.add(('dem',x,y))
        for y in range((s-1)//3*3,(n//3+1)*3,3):
            for x in range((w-1)//3*3,(e//3+1)*3,3):
                candidates=[base/'cover'/f'{y:+03d}_{x:+04d}.tif' for base in [WORK]+old.CACHES]
                adequate=None
                for p in candidates:
                    if p.exists():
                        with rasterio.open(p) as src:
                            if src.width>=2250:adequate=p;break
                if adequate:
                    # Record the higher-resolution source path, never overwrite
                    # a lower-resolution source or infer its missing classes.
                    records.append(dict(kind='cover',x=x,y=y,reused=str(adequate.relative_to(ROOT))))
                else:jobs.add(('cover',x,y))
    failures=[]
    def fetch(job):
        kind,x,y=job
        return common.cog_extract(kind,x,y) if kind=='dem' else sib.cover_extract(x,y,True)
    with futures.ThreadPoolExecutor(max_workers=4) as pool:
        pending={pool.submit(fetch,j):j for j in sorted(jobs)}
        for count,f in enumerate(futures.as_completed(pending),1):
            j=pending[f]
            try:records.append(dict(kind=j[0],x=j[1],y=j[2],**f.result()))
            except Exception as error:failures.append(dict(job=j,error=str(error)))
            if count%10==0 or count==len(jobs):print('R56 sources',count,len(jobs),'failed',len(failures),flush=True)
    save(WORK/'sources.json',dict(records=records,failures=failures))
    if failures:raise RuntimeError(f'{len(failures)} finite sources unavailable; do not label those areas complete')

def cover_path(x,y):
    choices=[base/'cover'/f'{y:+03d}_{x:+04d}.tif' for base in [WORK]+old.CACHES]
    for p in choices:
        if p.exists():
            with rasterio.open(p) as src:
                if src.width>=2250:return p
    return None

def corrected_field(bounds,size,fine=True,strict_cover=True):
    w,s,e,n=bounds;nx,ny=size
    height=sib.sample(sib.ETOPO,bounds,size)
    if fine:
        for y in range(math.floor(s),math.ceil(n)):
            for x in range(math.floor(w),math.ceil(e)):
                p=resolve('dem',x,y)
                if p is None:continue
                data=sib.sample(p,bounds,size);valid=np.isfinite(data);height[valid]=data[valid]
    lat=n-(np.arange(ny)+.5)*(n-s)/ny
    sm=gaussian_filter(height,.65);gy,gx=np.gradient(sm)
    gx/=111195*(e-w)/nx*np.cos(np.deg2rad(lat))[:,None];gy/=-111195*(n-s)/ny
    shade=np.clip(1+(((.45*(1.5*gx-1.5*gy+.70710678)+.55*(-1.5*gx-1.5*gy+.70710678))/np.sqrt(1+9*(gx*gx+gy*gy)))-.70710678)*1.7,.48,1.32)
    observed=np.broadcast_to(sib.PALETTE[0],(ny,nx,3)).copy()
    for y in range(math.floor(s/3)*3,math.ceil(n/3)*3,3):
        for x in range(math.floor(w/3)*3,math.ceil(e/3)*3,3):
            p=cover_path(x,y)
            if p is None and not strict_cover:p=resolve('cover',x,y)
            if p is None:
                if strict_cover:raise FileNotFoundError(f'Fine observed-cover source missing {x},{y}')
                continue
            with rasterio.open(p) as src:
                classes=src.read(1);palette=sib.PALETTE[classes]
                rgb=np.full((ny,nx,3),np.nan,dtype='float32')
                for i in range(3):
                    reproject(palette[:,:,i],rgb[:,:,i],src_transform=src.transform,src_crs=src.crs,dst_transform=from_bounds(*bounds,nx,ny),dst_crs='EPSG:4326',dst_nodata=np.nan,resampling=Resampling.average)
                valid=np.isfinite(rgb[:,:,0]);observed[valid]=rgb[valid]
    level=np.log1p(np.maximum(height,0)/200)/np.log(26);upland=common.smooth(.2,.95,level)*.4
    rgb=(observed*(1-upland[:,:,None])+np.array([.70,.68,.62])*upland[:,:,None])*shade[:,:,None]
    return np.concatenate([np.clip(rgb,0,1),np.ones((ny,nx,1))],axis=-1),height,shade

def demos():
    result=[]
    for name,(w,s,e,n) in DOMAINS.items():
        for y in range(s,n,2):
            for x in range(w,e,2):
                pad=32/512;b=(x-pad,y-pad,x+2+pad,y+2+pad)
                pixels,_,_=corrected_field(b,(1088,1088))
                # Finite source support transition, applied only at the two
                # outer acquisition domains. Internal 2-degree cores retain
                # full weight; real neighbouring DEM cells form all collars.
                xx,yy=np.meshgrid(b[0]+(np.arange(1088)+.5)*STEP,b[3]-(np.arange(1088)+.5)*STEP)
                pixels[:,:,3]=common.smooth(w,w+1,xx)*(1-common.smooth(e-1,e,xx))*common.smooth(s,s+1,yy)*(1-common.smooth(n-1,n,yy))
                a=write(f'fine_r56_{y}_{x:+d}',pixels,b)
                a.update(core_bounds_lon_lat=[x,y,x+2,y+2],dem_source='GLO90-6arcsec-extract; 1/512degree display; ETOPO only provider ocean/gap',cover_source='WorldCover2021-v200 categorical2250/3degree, palette then area average',surface_lod_degrees=2)
                result.append(a);print('R56 fine',name,x,y,flush=True)
    save(WORK/'fine_assets.json',result)

def canonical_assets():
    result=[]
    for a in assets(read(CAT)):
        if a['surface_role']!='detail' or a.get('surface_encoding',0)==5:continue
        p=canonical(decode(a),a.get('surface_encoding',0))
        name='canonical_r56_'+a['id'].split(':')[1]
        new=write(name,p,a['bounds_lon_lat'])
        for k in ['core_bounds_lon_lat','core_inset_degrees','surface_feather_degrees','dem_source']:
            if k in a:new[k]=a[k]
        new.update(surface_replaces=[a['id'].split(':')[1]],source_asset=a['id'],surface_lod_degrees=2)
        result.append(new)
        if len(result)%25==0:print('R56 legacy material conversion',len(result),flush=True)
    save(WORK/'canonical_assets.json',result)

def composite(bounds,size,candidates,initial=None):
    w,s,e,n=bounds;nx,ny=size
    xx,yy=np.meshgrid(w+(np.arange(nx)+.5)*(e-w)/nx,n-(np.arange(ny)+.5)*(n-s)/ny)
    out=np.zeros((ny,nx,4),dtype='float32') if initial is None else initial.copy();out[:,:,3]=1
    # Coarser valid inputs first. Fine cores overwrite only their real support.
    for a in candidates:
        b=a['bounds_lon_lat'];aw,ass,ae,an=b
        mask=(xx>=aw)&(xx<=ae)&(yy>=ass)&(yy<=an)
        if not mask.any():continue
        spacing=a['display_spacing_degrees'][1]
        lod=max(0,math.floor(math.log2((n-s)/ny/spacing)))
        p=canonical(decode(a,lod),a.get('surface_encoding',0));aw,ass,ae,an=a['bounds_lon_lat']
        coords=[(an-yy[mask])/(an-ass)*p.shape[0]-.5,(xx[mask]-aw)/(ae-aw)*p.shape[1]-.5]
        field=np.stack([map_coordinates(p[:,:,i],coords,order=1,mode='nearest',prefilter=False) for i in range(4)],axis=-1)
        pad=a['core_inset_degrees']
        strength=common.smooth(0,pad,np.minimum(xx[mask]-aw,ae-xx[mask]))*common.smooth(0,pad,np.minimum(yy[mask]-ass,an-yy[mask]))
        alpha=field[:,3:4]*strength[:,None];out[mask,:3]=out[mask,:3]*(1-alpha)+field[:,:3]*alpha
    return out

def page_assets():
    doc=read(CAT);all_old=assets(doc)
    canon=read(WORK/'canonical_assets.json');fine=read(WORK/'fine_assets.json')
    replaced={v for a in canon for v in a.get('surface_replaces',[])}
    admitted=[a for a in all_old if a['surface_role'] in ['base','detail'] and a['id'].split(':')[1] not in replaced]
    # The old shared base already contains baked rectangles. Do not magnify it
    # into the new LOD. Rebuild its material from actual height/classes, mapping
    # classes to RGB before area reduction. Reuse genuinely fine source assets.
    detailed=sorted([a for a in admitted+canon if a['surface_role']=='detail' and a['height']>=1088],key=lambda a:a['display_spacing_degrees'][0],reverse=True)+fine
    result=[]
    for span in [8,16]:
        step=span/1024;pad=32*step
        for y in range(32,64,span):
            for x in range(-16,48,span):
                b=(x-pad,y-pad,x+span+pad,y+span+pad)
                relevant=[a for a in detailed if (a['bounds_lon_lat'][0]<b[2] and a['bounds_lon_lat'][2]>b[0] and a['bounds_lon_lat'][1]<b[3] and a['bounds_lon_lat'][3]>b[1])]
                # Supersample existing *material*, then area-reduce. This
                # preserves real shaded relief; never invent higher DEM data.
                underlay,_,_=corrected_field(b,(2176,2176),fine=False,strict_cover=False)
                p=composite(b,(2176,2176),relevant,underlay)
                p=resize(p,(1088,1088))
                a=write(f'mid{span}_r56_{y}_{x:+d}',p,b)
                a.update(core_bounds_lon_lat=[x,y,x+span,y+span],surface_lod_degrees=span,dem_source='ETOPO2022-60s rebuilt material plus actual admitted GLO90 source material; mixed precision, never upsampled high-resolution DEM',cover_source='Existing real WC2021 samples225/450/2250 per3degrees; palette then area reduction. Missing cover stays neutral.',source_assets=[v['id'] for v in relevant],surface_display_max_mpp=1800 if span==8 else 3500,surface_fade_mpp=1200 if span==8 else 2600)
                result.append(a);print('R56 intermediate',span,x,y,flush=True)
    save(WORK/'page_assets.json',result)

def catalogue():
    doc=read(CAT);new=read(WORK/'canonical_assets.json')+read(WORK/'fine_assets.json')+read(WORK/'page_assets.json')+read(WORK/'overview_asset.json')
    finecores={tuple(a['core_bounds_lon_lat']) for a in new if a['id'].split(':')[1].startswith('fine_r56')}
    for a in assets(doc):
        if a['surface_role']=='detail' and tuple(a['core_bounds_lon_lat']) in finecores:
            next(v for v in new if tuple(v['core_bounds_lon_lat'])==tuple(a['core_bounds_lon_lat']) and 'fine_r56' in v['id']).setdefault('surface_replaces',[]).append(a['id'].split(':')[1])
    # New fine sources replace canonical aliases too, without leaving an
    # already uploaded old image behind an identical ID/new encoding.
    for a in new:
        if 'canonical_r56' in a['id'] and tuple(a['core_bounds_lon_lat']) in finecores:
            a['surface_role']='source_detail'
            next(v for v in new if tuple(v['core_bounds_lon_lat'])==tuple(a['core_bounds_lon_lat']) and 'fine_r56' in v['id']).setdefault('surface_replaces',[]).append(a['id'].split(':')[1])
            # This newly generated conversion is superseded by a true source
            # rebuild. Retain it for the requested Mip comparison, outside PCK.
            path=ROOT/a['path'].removeprefix('res://');target=WORK/'unpublished'/path.name
            if not path.is_relative_to(WORK/'unpublished'):
                target.parent.mkdir(parents=True,exist_ok=True)
                if not path.name.startswith('canonical_r56_'):raise ValueError('Not an R56 conversion')
                path.replace(target)
                a['path']='res://'+target.relative_to(ROOT).as_posix()
    save(WORK/'canonical_assets.json',[a for a in new if 'canonical_r56' in a['id']])
    new=[a for a in new if a['surface_role']!='source_detail']
    replaced={v for a in new for v in a.get('surface_replaces',[])}
    for a in assets(doc):
        if a['id'].split(':')[1] in replaced:a['surface_role']='source_base' if a['surface_role']=='base' else 'source_detail'
    src=copy.deepcopy(doc['source_registry']['sources'][-1]);src.update(source_id='terrain_sampling_r56',title='R56 finite material/Mip repair and geographic intermediate pages',version='R56')
    src['access_metadata'].update(bounds_lon_lat=[-28,10,76,86],sampling='Fine1/512degree from6arcsec GLO90 extracts; intermediate1/128 and1/64degree mixed-source material, NOT uniform GLO90',cover_sampling='Demonstration areas2250 categorical samples/3degrees; RGB palette before area reduction',new_dem_domains=DOMAINS,material_scope='Existing admitted European geographic material; finite intermediate band -16..48E,32..64N',historical_applicability='Modern physical display only; no new1900 land-use, water, sovereignty or economics')
    f=copy.deepcopy(doc['evidence_catalog']['facts'][-1]);f.update(fact_id='physical_relief:sampling_r56',subject_id='physical_relief:finite_sampling_repair',source_id=src['source_id'],source_version='R56',generator='tools/map/build_surface_r56.py',methodology='Canonical baked RGB with independent coverage; explicit linear material Mips; real finite GLO90/WC sources and offline geographic page pyramid. No runtime DEM generation.')
    f['value']['assets']=new;doc['source_registry']['sources'].append(src);doc['evidence_catalog']['facts'].append(f)
    f['spatial_scope']=dict(kind='geographic_reference',id='existing_materials_and_two_finite_glo_demonstrations')
    save(ROOT/'data/presentation/sampling_surface_r56.json',doc)
    save(WORK/'summary.json',dict(files=len(new),bytes=sum(a['bytes'] for a in new),fine=sum('fine_r56' in a['id'] for a in new),intermediate=sum('mid' in a['id'].split(':')[1][:3] for a in new),canonical=sum('canonical_r56' in a['id'] for a in new),decoded_max=max(a['decoded_bytes'] for a in new)))

def overview():
    base=next(a for a in assets(read(CAT)) if a['id'].endswith('euro_afro_russia_r55_base'))
    pages=[a for a in read(WORK/'page_assets.json') if a['surface_lod_degrees']==16]
    p=composite(base['bounds_lon_lat'],(base['width'],base['height']),pages,decode(base))
    a=write('euro_afro_russia_r56_base',p,base['bounds_lon_lat'],'base')
    a.update(core_inset_degrees=0,surface_feather_degrees=[0,0,4,0],surface_replaces=['euro_afro_russia_r55_base'],dem_source='ETOPO2022-60s; retained R55 outside finite repaired European page band',source_assets=[v['id'] for v in pages],surface_support_fraction=1.0)
    save(WORK/'overview_asset.json',[a])

if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf8');WORK.mkdir(parents=True,exist_ok=True)
    {'acquire':acquire,'demos':demos,'canonical':canonical_assets,'pages':page_assets,'overview':overview,'catalogue':catalogue}[sys.argv[1]]()
