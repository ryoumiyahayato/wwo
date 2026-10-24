"""Requested finite offline visual comparisons; not Godot screenshots.

CPU reproduces actual AEQD coordinates, decoded channel math, selected assets,
spatial weights and approximate trilinear Mips. Godot derivative/GPU/lighting,
flags, water, models and UI are not reproduced. No sharpening or fake detail.
"""
import functools,json,math,sys
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont
from scipy.ndimage import map_coordinates
import rasterio
from rasterio.windows import from_bounds
from rasterio.enums import Resampling
from rasterio.warp import reproject
from rasterio.transform import from_bounds as affine
from shapely.geometry import shape,box
from shapely import contains_xy
from shapely.ops import unary_union
import build_surface_r56 as build

ROOT=build.ROOT;WORK=build.WORK;OUT=WORK/'visuals'
FONT=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',18)
SMALL=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',15)

def rgb(a):return Image.fromarray(np.uint8(np.clip(a,0,1)*255+.5),'RGB')

def sheet(panels,labels,path,columns=2,note='Offline CPU reference. No game run or GPU screenshot.'):
    pw,ph=640,360;rows=math.ceil(len(panels)/columns)
    page=Image.new('RGB',(columns*pw,rows*(ph+48)+64),'#f1f0ea');draw=ImageDraw.Draw(page)
    draw.text((14,12),note,font=SMALL,fill='#17242a')
    for i,(panel,label) in enumerate(zip(panels,labels)):
        x=(i%columns)*pw;y=48+(i//columns)*(ph+48)
        draw.text((x+10,y),label,font=FONT,fill='#17242a')
        page.paste(panel.resize((pw,ph),Image.Resampling.BOX),(x,y+34))
    page.save(path)

@functools.lru_cache(maxsize=16)
def texture(key,lod):return build.decode(ASSETS[key],lod)

def ll_grid(center,mpp,size=(1280,720)):
    # Exactly RegionProjection.inverse for bearing0: east/right, north/up.
    w,h=size;x,y=np.meshgrid((np.arange(w)+.5-w/2)*mpp,(h/2-np.arange(h)-.5)*mpp)
    radius=np.hypot(x,y);angle=radius/6371008.8
    lon0,lat0=np.deg2rad(center)
    sine=np.sin(angle);cosine=np.cos(angle)
    lat=np.arcsin(cosine*np.sin(lat0)+np.divide(y, radius,out=np.zeros_like(y),where=radius>0)*sine*np.cos(lat0))
    lon=lon0+np.arctan2(x*sine,radius*np.cos(lat0)*cosine-y*np.sin(lat0)*sine)
    return np.rad2deg(lon),np.rad2deg(lat)

def sample(a,x,y,mpp):
    w,s,e,n=a['bounds_lon_lat'];dx,dy=a['display_spacing_degrees']
    # Approximate texture derivatives including latitude contraction. Actual
    # Godot LOD depends on the rasterizer and the local chart Jacobian.
    meter=min(111195*dy,111195*dx*math.cos(math.radians(float(np.mean(y)))))
    lod=max(0,math.log2(mpp/max(meter,1e-6)));low=math.floor(lod);high=low+1
    maxlod=math.floor(math.log2(max(a['width'],a['height'])));low=min(low,maxlod);high=min(high,maxlod)
    def one(level):
        p=texture(a['id'],level)
        coords=[(n-y)/(n-s)*p.shape[0]-.5,(x-w)/(e-w)*p.shape[1]-.5]
        return np.stack([map_coordinates(p[:,:,i],coords,order=1,mode='nearest',prefilter=False) for i in range(4)],axis=-1)
    return one(low)*(1-(lod%1))+one(high)*(lod%1),lod

def material(p,enc,old=False):
    if enc==5:return p[:,:,:3],np.ones(p.shape[:2]),p[:,:,3]
    if enc:
        shade=.4+p[:,:,3];coverage=build.common.smooth(.01,.075,p[:,:,3]) if enc==1 or not old else np.ones(p.shape[:2]);colour=p[:,:,:3]
    else:
        t=build.common.smooth(.2,.95,p[:,:,0:1]);tone=np.array([.57,.57,.46])*(1-t)+np.array([.70,.68,.62])*t;trees=p[:,:,2:3]*.78
        colour=tone*(1-trees)+np.array([.27,.38,.27])*trees;shade=.4+p[:,:,1];coverage=p[:,:,3]
    return (colour,shade,coverage) if old else (colour*shade[:,:,None],np.ones_like(shade),coverage)

def render(row):
    x,y=ll_grid(row['center'],row['mpp']);shape_=x.shape;old=row['catalog']=='european_catalog'
    colour=np.full((*shape_,3),.5);shade=np.ones(shape_);coverage=np.zeros(shape_)
    total=np.zeros((*shape_,4));weight=np.zeros(shape_);strength=np.zeros(shape_)
    spacing=np.full(shape_,np.nan);tile_weight=np.zeros(shape_);mips=[]
    for item in row['selected']:
        a=item['asset'];w,s,e,n=a['bounds_lon_lat'];p,lod=sample(a,x,y,row['mpp']);c,sh,cov=material(p,a.get('surface_encoding',0),old)
        cov*=((x>=w)&(x<=e)&(y>=s)&(y<=n));mips.append(dict(id=a['id'],approx_mip=lod,source=a.get('dem_source','upstream GLO90/ETOPO'),sampling=a['display_spacing_degrees']))
        if a['surface_role']=='base':
            for amt,dist in zip(a.get('surface_feather_degrees',[0]*4),[x-w,y-s,e-x,n-y]):
                if amt:cov*=build.common.smooth(0,amt,dist)
            combined=coverage+cov*(1-coverage);blend=np.divide(cov,combined,out=np.zeros_like(cov),where=combined>0)
            colour=colour*(1-blend[:,:,None])+c*blend[:,:,None];shade=shade*(1-blend)+sh*blend;coverage=combined
            spacing[cov>.5]=111195*a['display_spacing_degrees'][1]
        else:
            pad=a['core_inset_degrees'];cw,cs,ce,cn=a['core_bounds_lon_lat']
            blend=build.common.smooth(0,pad,np.minimum(x-w,e-x))*build.common.smooth(0,pad,np.minimum(y-s,n-y))*row['detail_weight']*cov
            for amt,dist in zip(item['edges'],[x-cw,y-cs,ce-x,cn-y]):
                if amt:blend*=build.common.smooth(0,amt,dist)
            total[:,:,:3]+=c*blend[:,:,None];total[:,:,3]+=sh*blend;weight+=blend;strength=np.maximum(strength,blend)
            spacing[blend>.5]=111195*a['display_spacing_degrees'][1];tile_weight=np.maximum(tile_weight,blend)
    average=np.divide(total,weight[:,:,None],out=np.zeros_like(total),where=weight[:,:,None]>0)
    colour=colour*(1-strength[:,:,None])+average[:,:,:3]*strength[:,:,None];shade=shade*(1-strength)+average[:,:,3]*strength
    return np.clip(colour*shade[:,:,None],0,1),spacing,tile_weight,mips

def ramp(values,lo,hi,colours):
    t=np.clip((values-lo)/(hi-lo),0,1);stops=np.linspace(0,1,len(colours))
    return np.stack([np.interp(t,stops,np.array(colours)[:,i]) for i in range(3)],axis=-1)

def terrain_rows(rows):
    metrics=[]
    for name in ['alps_po','polesia']:
        panels=[];labels=[];resolution=[];weights=[]
        for mpp in [800,250,75]:
            for cat in ['european_catalog','sampling_catalog']:
                row=next(r for r in rows if r['place']==name and r['mpp']==mpp and r['catalog']==cat)
                p,spacing,weight,mips=render(row);panels.append(rgb(p));labels.append(f'{"R55" if cat=="european_catalog" else "R56"}: {mpp}m/px, {row["center"][0]:.2f}E {row["center"][1]:.2f}N')
                resolution.append(rgb(ramp(np.log2(spacing),math.log2(217),math.log2(3707),[[.1,.38,.67],[.95,.8,.2],[.75,.2,.2]])))
                weights.append(rgb(np.repeat(weight[:,:,None],3,axis=2)))
                metrics.append(dict(place=name,mpp=mpp,catalog=cat,detail_weight=row['detail_weight'],textures=mips,ns_material_sampling_range_m=[float(np.nanmin(spacing)),float(np.nanmax(spacing))],source_precision_is_not_material_grid_precision=True))
        sheet(panels,labels,OUT/(name+'_comparison.png'))
        sheet(resolution,labels,OUT/(name+'_sampling_grid.png'),note='Material grid N-S: blue217m / yellowintermediate / red3707m. Source DEM may be coarser.')
        sheet(weights,labels,OUT/(name+'_refinement_weights.png'),note='Actual selected detail spatial weight. Black0 / white1. CPU approximation.')
    build.save(WORK/'visual_metrics.json',metrics)

def source_panels(name,center):
    x,y=center;b=(x-.18,y-.12,x+.18,y+.12);size=(900,600)
    extracted=build.resolve('dem',math.floor(x),math.floor(y));meta=build.read(extracted.with_suffix('.json'))
    filename=meta['url'].rsplit('/',1)[1];native=extracted.parent.parent/'source'/filename
    if not native.exists():
        native=next((base/'source'/filename for base in [WORK]+build.old.CACHES if (base/'source'/filename).exists()),None)
    if native is None:raise FileNotFoundError(filename)
    original=build.sib.sample(native,b,size);reduced=build.sib.sample(extracted,b,size)
    p,height,shade=build.corrected_field(b,(round((b[2]-b[0])*512),round((b[3]-b[1])*512)))
    oldcover=build.old.resolve('cover',math.floor(x/3)*3,math.floor(y/3)*3)
    classes_old=build.sib.sample(oldcover,b,size,'uint8',Resampling.nearest)
    finer=build.cover_path(math.floor(x/3)*3,math.floor(y/3)*3)
    classes_fine=build.sib.sample(finer,b,size,'uint8',Resampling.nearest)
    panels=[rgb(ramp(original,-50,3000,[[.14,.28,.23],[.65,.62,.4],[.9,.88,.81]])),rgb(ramp(reduced,-50,3000,[[.14,.28,.23],[.65,.62,.4],[.9,.88,.81]])),rgb(np.repeat(np.clip((shade-.48)/.84,0,1)[:,:,None],3,axis=2)),rgb(build.sib.PALETTE[classes_old]),rgb(build.sib.PALETTE[classes_fine]),rgb(p[:,:,:3])]
    sheet(panels,['Native GLO90 source (same fixed height colours)','Actual6arcsec DEM extraction (185m N-S)','Fixed metric hillshade; range0.48..1.32','R55 categorical reference, nearest display','2250/3degree sampled classes; no ID interpolation','R56 palette area mean + actual DEM shading'],OUT/(name+'_source_chain.png'),columns=3,note=f'Offline source chain {b}. Native10m cover is not claimed for the whole domain.')
    # A small real native WorldCover10m window. No nationwide native download.
    sx,sy=math.floor(x/3)*3,math.floor(y/3)*3
    url=f'{build.common.WC_ROOT}/ESA_WorldCover_10m_2021_v200_N{sy:02d}E{sx:03d}_Map.tif'
    patch=WORK/(name+'_worldcover_native10m.tif')
    if not patch.exists():
        with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN='EMPTY_DIR',GDAL_HTTP_TIMEOUT='45'):
            with rasterio.open(url) as src:
                win=from_bounds(x-.025,y-.025,x+.025,y+.025,src.transform).round_offsets().round_lengths();data=src.read(1,window=win)
                with rasterio.open(patch,'w',driver='GTiff',width=data.shape[1],height=data.shape[0],count=1,dtype='uint8',crs=src.crs,transform=src.window_transform(win),compress='deflate') as dst:dst.write(data,1)
    with rasterio.open(patch) as src:
        actual=src.read(1);pb=tuple(src.bounds)
    oldp=build.sib.sample(oldcover,pb,(actual.shape[1],actual.shape[0]),'uint8',Resampling.nearest)
    finep=build.sib.sample(finer,pb,(actual.shape[1],actual.shape[0]),'uint8',Resampling.nearest)
    sheet([rgb(build.sib.PALETTE[a]) for a in [actual,oldp,finep]],['Actual native10m categorical window','R55 categorical overview in same window','R56 sampled148m categorical grid'],OUT/(name+'_cover_source.png'),columns=3,note=f'WorldCover2021 native source comparison {pb}; classes never interpolated.')

def mip_panels():
    a=next(a for a in build.read(WORK/'canonical_assets.json') if 'canonical_r56_german_r44_46_+10' in a['id'])
    source=ASSETS[a['source_asset']];panels=[];labels=[]
    for level in range(math.floor(math.log2(max(a['width'],a['height'])))+1):
        for old,asset in [(True,source),(False,a)]:
            p=build.decode(asset,level);c,s,_=material(p,asset.get('surface_encoding',0),old)
            panels.append(rgb(c*s[:,:,None]));labels.append(f'{"R55 stored" if old else "R56 canonical"} Mip{level}')
    sheet(panels,labels,OUT/'legacy_mip_comparison.png',note='Same source DEM information. Old A=shade Mips versus canonical baked RGB Mips.')

def coast_panels(rows):
    doc=build.read(WORK/'coast/geometry_comparison.geojson');geos=[shape(f['geometry']) for f in doc['features']]
    panels=[];labels=[]
    # Finite west Crete, source envelopes drawn directly in the same chart.
    for mpp in [800,250,75]:
        x,y=ll_grid([23.65,35.55],mpp)
        for i,g in enumerate(geos):
            land=contains_xy(g,x,y)
            p=np.broadcast_to([.07,.22,.29],(*x.shape,3)).copy();p[land]=[.64,.64,.46]
            panels.append(rgb(p));labels.append(f'{"R55 NE +300m simplification" if i==0 else "R56 GSHHG2.3.7 full"}: {mpp}m/px')
    sheet(panels,labels,OUT/'crete_coast_comparison.png',note='Offline Crete physical component silhouettes only. Modern references; not1900 shore survey.')
    # Show actual vertices; increased count alone does not prove positional accuracy.
    b=(23.45,35.45,23.85,35.75);page=Image.new('RGB',(1200,700),'#f1f0ea');d=ImageDraw.Draw(page)
    for g,c in zip(geos,['#bd603c','#286385']):
        parts=list(g.geoms) if hasattr(g,'geoms') else [g]
        for poly in parts:
            coords=list(poly.exterior.coords)
            pts=[((xx-b[0])/(b[2]-b[0])*1200,(b[3]-yy)/(b[3]-b[1])*660+40) for xx,yy in coords]
            d.line(pts,fill=c,width=2)
    d.text((14,12),'West Crete: orangeR55 simplified NE / blueGSHHG full. No invented connecting coast.',font=FONT,fill='#17242a');page.save(OUT/'crete_vertex_overlay.png')

if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf8');OUT.mkdir(parents=True,exist_ok=True)
    ASSETS={a['id']:a for a in build.assets(build.read(ROOT/'data/presentation/sampling_surface_r56.json'))}
    # Source aliases remain available for the before comparison.
    ASSETS.update({a['id']:a for a in build.assets(build.read(build.CAT))})
    rows=build.read(WORK/'selection.json')['rows']
    terrain_rows(rows);print('terrain composites done',flush=True)
    source_panels('alps_po',[10.8,45.8]);source_panels('polesia',[27.5,51.2]);print('source panels done',flush=True)
    mip_panels();coast_panels(rows);print('three finite offline comparison groups complete',flush=True)
