"""Finite requested source comparisons. Not gameplay or GPU screenshots."""
import functools,json,math,sys
import numpy as np
from PIL import Image,ImageDraw
import rasterio
from rasterio.enums import Resampling
from rasterio.windows import from_bounds
import build_surface_r57 as build
import visualize_surface_r56 as prior

ROOT=build.ROOT;WORK=build.WORK;OUT=WORK/'visuals';OUT.mkdir(parents=True,exist_ok=True)
ASSETS={build.key(a):a for a in build.prev.assets(build.read(ROOT/'data/presentation/sampling_surface_r57.json'))}
BEFORE=build.read(WORK/'before_points.json');AFTER=build.read(WORK/'after_points.json')

@functools.lru_cache(maxsize=18)
def texture(id,mip):return build.prev.decode(ASSETS[id],mip)

def sample(a,x,y,mpp):
    w,s,e,n=a['bounds_lon_lat'];grid=min(a['display_spacing_degrees'][1]*111195,a['display_spacing_degrees'][0]*111195*math.cos(math.radians(float(y.mean()))))
    level=max(0,math.log2(mpp/grid));lo=math.floor(level);hi=lo+1
    from scipy.ndimage import map_coordinates
    def one(m):
        p=texture(build.key(a),m);coords=[(n-y)/(n-s)*p.shape[0]-.5,(x-w)/(e-w)*p.shape[1]-.5]
        return np.stack([map_coordinates(p[:,:,i],coords,order=1,mode='nearest',prefilter=False) for i in range(4)],axis=-1)
    return one(lo)*(1-level%1)+one(hi)*(level%1)

def render(row):
    x,y=prior.ll_grid(row['camera_center'],row['mpp']);out=np.zeros((*x.shape,3));cov=np.zeros(x.shape);total=out.copy();summ=np.zeros(x.shape);strength=summ.copy()
    bindings=row.get('bound_uniforms',{})
    selected=row['selected'];details=[v for v in selected if ASSETS[v]['surface_role'] not in ['base','source_base']]
    for i,id in enumerate(selected):
        a=ASSETS[id];p=sample(a,x,y,row['mpp']);enc=a.get('surface_encoding',0)
        if enc==6:
            slot='base' if a['surface_role']=='base' else str(details.index(id))
            weight=bindings['surface_cover_'+slot]
            c=p[:,:,:3]*weight+p[:,:,3:4]*np.array([1.015,1,.88])*(1-weight);alpha=build.prev.common.smooth(.01,.075,p[:,:,3])
        else:c,_,alpha=prior.material(p,enc)
        w,s,e,n=a['bounds_lon_lat'];alpha*=((x>=w)&(x<=e)&(y>=s)&(y<=n))
        if a['surface_role'] in ['base','source_base']:
            for amt,d in zip(a.get('surface_feather_degrees',[0]*4),[x-w,y-s,e-x,n-y]):
                if amt:alpha*=build.prev.common.smooth(0,amt,d)
            out=c if i==0 else out*(1-alpha[:,:,None])+c*alpha[:,:,None];cov=np.maximum(cov,alpha)
        else:
            pad=a['core_inset_degrees'];core=a['core_bounds_lon_lat']
            alpha*=build.prev.common.smooth(0,pad,np.minimum(x-w,e-x))*build.prev.common.smooth(0,pad,np.minimum(y-s,n-y))*row['detail_weight']
            slot=str(details.index(id));edges=bindings.get('surface_edges_'+slot)
            if edges is None:
                # Reproduce original R56 output-grid neighbour rule, not R57
                # source-aware edges. Before query was saved before code edits.
                edges=[.35]*4
                for other in details:
                    if other==id:continue
                    b=ASSETS[other];q=b['core_bounds_lon_lat']
                    if abs(a['display_spacing_degrees'][1]/b['display_spacing_degrees'][1]-1)>.1:continue
                    if q[1:4:2]==core[1:4:2]:
                        if q[2]==core[0]:edges[0]=0
                        if q[0]==core[2]:edges[2]=0
                    if [q[0],q[2]]==[core[0],core[2]]:
                        if q[3]==core[1]:edges[1]=0
                        if q[1]==core[3]:edges[3]=0
            for amt,d in zip(edges,[x-core[0],y-core[1],core[2]-x,core[3]-y]):
                if amt:alpha*=build.prev.common.smooth(0,amt,d)
            total+=c*alpha[:,:,None];summ+=alpha;strength=np.maximum(strength,alpha)
    avg=np.divide(total,summ[:,:,None],out=np.zeros_like(total),where=summ[:,:,None]>0)
    return out*(1-strength[:,:,None])+avg*strength[:,:,None]

def row(rows,place,mpp):return next(r for r in rows if r['place']==place and r['mpp']==mpp and r['screen_xy']==[640,360])

def sources():
    center=(37.3,55.4);bounds=(37.26,55.36,37.34,55.44);size=(900,600)
    coarse=build.euro.resolve('cover',36,54)
    patch=WORK/'moscow_wc2021_native10m.tif'
    if not patch.exists():
        meta=build.read(coarse.with_suffix('.json'));url=meta['url']
        with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN='EMPTY_DIR',GDAL_HTTP_TIMEOUT='45'):
            with rasterio.open(url) as src:
                win=from_bounds(*bounds,src.transform).round_offsets().round_lengths();p=src.read(1,window=win);transform=src.window_transform(win)
                with rasterio.open(patch,'w',driver='GTiff',width=p.shape[1],height=p.shape[0],count=1,dtype='uint8',crs=src.crs,transform=transform,compress='deflate') as dst:dst.write(p,1)
                build.save(WORK/'native_patch_source.json',dict(url=url,window_bounds=list(rasterio.windows.bounds(win,src.transform)),native_transform=list(src.transform),window_transform=list(transform),shape=list(p.shape),source_epoch='2021 v200',license='CC-BY-4.0',purpose='finite research comparison only, not a full modern land-use update'))
    old_class=build.sib.sample(coarse,bounds,size,'uint8',Resampling.nearest)
    native=build.sib.sample(patch,bounds,size,'uint8',Resampling.nearest)
    old=next(a for id,a in ASSETS.items() if id=='european_r55_54_+36')
    oldp,classes=build.sib.make_field(old['bounds_lon_lat'],(1088,1088),True,build.euro.resolve,coverage=lambda x,y:np.ones(np.broadcast_shapes(x.shape,y.shape),dtype='float32'))
    actual=build.prev.decode(old)
    error=np.abs(oldp[100:-100,100:-100,:3]-actual[100:-100,100:-100,:3])
    # Confirm actual values from class->palette->metric shade production, not
    # an assumption based on a large output image's width.
    return [prior.rgb(build.sib.PALETTE[native]),prior.rgb(build.sib.PALETTE[old_class])],dict(original_cover=str(coarse.relative_to(ROOT)),sample_m_ns=741.3,original_texture=old['path'],old_nearest_producer_rgb_max_abs=float(error.max()),old_nearest_producer_rgb_mean_abs=float(error.mean()),native_patch=str(patch.relative_to(ROOT)),native_reference_not_installed_as_whole_region=True)

def main():
    metrics={};sourcepanels,metrics['grid']=sources()
    panels=sourcepanels;labels=['WC2021 actual native10m research patch','Same window: actual450/3deg nearest classes (741m)']
    for rows,name in [(BEFORE,'R56 bound source'),(AFTER,'R57 bound source')]:
        r=row(rows,'moscow',75);panels.append(prior.rgb(render(r)));labels.append(name+': 75m/px,37.3E55.4N')
    prior.sheet(panels,labels,OUT/'green_grid_source_and_binding.png',note='Top: 0.08degree research patch. Bottom: actual selected material inputs in 1280x720 chart. CPU, not framebuffer.')
    for place,file in [('german_polesia_edge','source_boundary'),('alps','alps_detail'),('france','france_medium'),('spain','spain_medium'),('pyrenees','pyrenees_medium'),('baltic','baltic_boundary'),('warsaw','warsaw_boundary'),('germany_austria','germany_austria_boundary')]:
        panels=[];labels=[]
        for mpp in [800,250,75]:
            for rows,name in [(BEFORE,'R56'),(AFTER,'R57')]:
                r=row(rows,place,mpp);panels.append(prior.rgb(render(r)));labels.append(f'{name} {mpp}m/px {r["camera_center"]}')
        prior.sheet(panels,labels,OUT/(file+'.png'),note='Production selector + bound material inputs, CPU reconstruction of shared shader. GPU implicit Mip not measured.')
    g=build.read(WORK/'geometry.json')
    page=Image.new('RGB',(1280,620),'#f1f0ea');d=ImageDraw.Draw(page)
    lines=['Finite geometry request: 24.5E35.3N /75m per pixel /medium',f'Actual physical IDs: {g["requested"]}',f'Read -> prepare: {g["before"]["wanted"]}; generation {g["before"]["generation"]}',f'Upload -> staged: {g["uploaded"]["cpu_ready"]}; batches {g["uploaded"]["last_result"]["chunks"]}',f'Complete current cap: {g["can_present_complete"]}',f'Update -> published: {g["published"]["published_lod"]}, {g["published"]["published"]}',f'Cancellation returns: {g["cancelled_result"]}','No missing ID in this finite package. User failure location/state unavailable.','Headless resource preparation and dummy-server publication. Not a game/GPU test.','R57 Ctrl+Alt+click (only --r57-terrain-probe) records actual current jobs and bindings.']
    for i,line in enumerate(lines):d.text((24,28+i*52),line,font=prior.FONT,fill='#17242a')
    page.save(OUT/'geometry_publication.png')
    metrics['geometry']=g;metrics['paris_geometry']=build.read(WORK/'geometry_paris.json');metrics['images']=list(p.name for p in OUT.glob('*.png'));build.save(WORK/'visual_sources.json',metrics)
    print('R57 source, boundary and geometry comparisons complete',flush=True)

if __name__=='__main__':sys.stdout.reconfigure(encoding='utf8');main()
