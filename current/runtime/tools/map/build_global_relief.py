"""Offline ETOPO physical-reference derivation. Raw inputs stay outside exports."""
from pathlib import Path
import argparse, io, json, math, struct, time
import numpy as np
from PIL import Image, TiffImagePlugin

ROOT=Path(__file__).resolve().parents[2]
SOURCE_ID='noaa_etopo_2022_v1_60s_surface'
URL='https://www.ngdc.noaa.gov/mgg/global/relief/ETOPO2022/data/60s/60s_surface_elev_gtif/ETOPO_2022_v1_60s_N90W180_surface.tif'

def native_window(source, anchor, width, height):
    """Decode only intersecting original TIFF tiles; never the full global DEM."""
    with source.open('rb') as fp:
        header=fp.read(8)
        if header[:4]!=b'II*\x00': raise ValueError('Expected source little-endian TIFF')
        fp.seek(struct.unpack('<I',header[4:])[0])
        tags=TiffImagePlugin.ImageFileDirectory_v2(header);tags.load(fp)
        if (tags[256],tags[257])!=(21600,10800) or tuple(tags[33550][:2])!=(1/60,1/60): raise ValueError('Unexpected DEM grid')
        if tuple(tags[33922])!=(0.,0.,0.,-180.,90.,0.): raise ValueError('Unexpected DEM origin')
        col=math.floor((anchor[0]+180)*60)-width//2
        row=math.floor((90-anchor[1])*60)-height//2
        tw,th=int(tags[322]),int(tags[323]);tiles_across=math.ceil(tags[256]/tw)
        tiles={};values=[]
        for y in range(row,row+height):
            line=[]
            for x in range(col,col+width):
                tile=(y//th)*tiles_across+x//tw
                if tile not in tiles:
                    fp.seek(tags[324][tile]);payload=fp.read(tags[325][tile])
                    small=TiffImagePlugin.ImageFileDirectory_v2()
                    for tag in [258,259,262,277,284,317,339]:
                        if tag in tags: small[tag]=tags[tag]
                    for tag,value in [(256,tw),(257,th),(322,tw),(323,th),(324,0),(325,len(payload))]:
                        small[tag]=value;small.tagtype[tag]=4
                    block=small.tobytes(offset=8);small[324]=8+len(block)
                    tile_file=b'II'+struct.pack('<HI',42,8)+small.tobytes(offset=8)+payload
                    with Image.open(io.BytesIO(tile_file)) as decoded: tiles[tile]=np.asarray(decoded,dtype=np.float32).copy()
                value=float(tiles[tile][y%th,x%tw])
                if not math.isfinite(value) or value<=-20000: raise ValueError('DEM contains missing cells')
                line.append(round(value,2))
            values.append(line)
    return np.asarray(values,dtype=np.float32),col,row

def paris_native_surface(source):
    """Preserve the existing Eiffel-area native-cell export."""
    width,height=15,13
    grid,col,row=native_window(source,(2.2945,48.858333),width,height)
    values=grid.tolist()
    document={'schema_id':'local_native_height_reference_r1','source_id':SOURCE_ID,'source_reference':URL,'license':'CC0-1.0',
        'horizontal_crs':'EPSG:4326','vertical_datum':'EGM2008; metres','source_epoch':'ETOPO 2022 composite; not a 1900 survey',
        'anchor_lon_lat':[2.2945,48.858333],'width':width,'height':height,'west_cell_centre':-180+(col+.5)/60,
        'north_cell_centre':90-(row+.5)/60,'step_degrees':1/60,'height_rows_m':values,
        'native_spacing_m_approx':[1220,1853],'display_min_mpp':80,'display_max_mpp':200,
        'terrain_note_zh':'ETOPO 2022 原生60角秒，约1.2×1.85千米，仅表现局部大尺度起伏。80米/像素以内继续使用平面；无1900年河岸或建筑基座高程。',
        'limitations':['No new samples, smoothing or invented hills.','No historical shoreline, lake surface, street or terrain-use reconstruction.','The modern composite cannot establish a precise 1900 surface.']}
    out=ROOT/'data/local/paris_surface_etopo_60s.json'
    out.write_text(json.dumps(document,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print(json.dumps({'output':str(out),'native_vertices':width*height,'triangles':2*(width-1)*(height-1),'height_range_m':[min(map(min,values)),max(map(max,values))],'bytes':out.stat().st_size}))

def regional_windows(source):
    """Bounded detail residuals over the unchanged continuous global relief."""
    def lowpass(values, sigma=3.0):
        radius=math.ceil(sigma*3)
        x=np.arange(-radius,radius+1,dtype=np.float32)
        kernel=np.exp(-.5*(x/sigma)**2);kernel/=kernel.sum()
        result=values
        for axis in [0,1]:
            pads=[(0,0),(0,0)];pads[axis]=(radius,radius)
            result=np.apply_along_axis(lambda a:np.convolve(a,kernel,mode='valid'),axis,np.pad(result,pads,mode='reflect'))
        return result
    target=ROOT/'assets/maps/relief';target.mkdir(parents=True,exist_ok=True)
    assets=[]
    for name,anchor in [('paris',(2.2945,48.858333)),('london',(-0.1246,51.5007)),('zermatt',(7.748,46.02)),('giza',(31.1342,29.9792))]:
        width=height=97
        # Derivatives and the low-pass footprint both use actual source cells
        # outside the displayed window, never reflected data at its boundary.
        collar=12
        raw,col,row=native_window(source,anchor,width+2*collar,height+2*collar)
        elevation=np.maximum(raw,0.0)
        step=2*math.pi*6371008.8/(360*60)
        lat=np.deg2rad(90-(np.arange(elevation.shape[0])+row+.5)/60)
        east=(elevation[1:-1,2:]-elevation[1:-1,:-2])/(2*step*np.cos(lat[1:-1,None]))
        north=-(elevation[2:,1:-1]-elevation[:-2,1:-1])/(2*step)
        nx,ny=-east,-north
        norm=np.sqrt(nx*nx+ny*ny+1)
        shade=(.45*(-.5*nx+.5*ny+math.sqrt(.5))+.55*(.5*nx+.5*ny+math.sqrt(.5)))/norm
        shade=(shade-math.sqrt(.5))*1.35
        # Preserve the global mountain/plateau base. Add only the shorter
        # native-cell band, with fixed global units, not a per-tile stretch.
        trim=slice(collar-1,-(collar-1))
        directional=(shade-lowpass(shade))[trim,trim]
        # R25: the finite window contributes directional form only. Height
        # and the printing palette remain on the continuous global reference.
        # Integer 128 decodes to exactly zero, including flat areas.
        detail=np.rint(128+127*np.clip(directional/.10,-1,1)).astype('uint8')
        path=target/('native_'+name+'.bin');Image.fromarray(detail).save(path,format='PNG',optimize=True)
        col+=collar;row+=collar
        bounds=[-180+col/60,90-(row+height)/60,-180+(col+width)/60,90-row/60]
        assets.append({'id':'physical_relief:native_'+name,'path':'res://'+path.relative_to(ROOT).as_posix(),'width':width,'height':height,'format':'R8','decoded_bytes':width*height,'bytes':path.stat().st_size,'bounds_lon_lat':bounds,'anchor_lon_lat':list(anchor),'angular_pixel_degrees':1/60,'native_spacing_m_approx':[round(step*math.cos(math.radians(anchor[1]))),round(step)],'display_max_mpp':1600,'release_mpp':2200,'edge_fraction':.22,'source_epoch':'ETOPO 2022 composite; modern physical reference, not 1900 survey','representation':'R25 directional-only short-band residual: (R*255-128)/127*0.10; 3-cell Gaussian low-pass removed; true 1x slope normals; continuous global height and palette unchanged; no new height mesh, coast or land cover'})
    path=ROOT/'data/presentation/global_physical_relief.json'
    doc=json.loads(path.read_text(encoding='utf8'))
    fact=next(f for f in doc['evidence_catalog']['facts'] if f['fact_id']=='physical_relief:etopo_2022')
    fact['value']['assets']=[a for a in fact['value']['assets'] if not a['id'].startswith('physical_relief:native_')]+assets
    fact['value']['bounded_derivation']={'generator':'tools/map/build_global_relief.py --regional-windows','method':'R25: four 97x97 native-60s R8 directional-only residuals; 12-source-cell collar supports metric derivatives and Gaussian sigma 3 low-pass; remove the low-frequency band; actual 1x slope normals and fixed directional bound 0.10. Integer 128 is neutral. No finite-window height tint: global height and palette remain continuous. Existing 22% geographic border and scale admission 1600/release 2200 mpp retained. One active window plus at most one pending replacement. No synthetic height or new DEM mesh.','limits':'About 1.15-1.61km east-west and 1.85km north-south. These are cartographic derivatives, not finer elevation, historical land cover or water edges. Original LOCAL grids and their different vertical datums remain unchanged.'}
    fact['value']['representation']='Two global LODs and at most one bounded native-60s reference texture; no terrain simulation'
    path.write_text(json.dumps(doc,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print(json.dumps({'bounded_reliefs':assets},ensure_ascii=False))

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--source',type=Path,required=True);parser.add_argument('--local-paris',action='store_true');parser.add_argument('--regional-windows',action='store_true');args=parser.parse_args()
    if args.regional_windows:
        regional_windows(args.source);return
    if args.local_paris:
        paris_native_surface(args.source);return
    from scipy.ndimage import gaussian_filter
    started=time.monotonic();Image.MAX_IMAGE_PIXELS=None
    raw=Image.open(args.source)
    if raw.size!=(21600,10800) or raw.mode!='F': raise ValueError((raw.size,raw.mode))
    if tuple(raw.tag_v2[33922])!=(0.0,0.0,0.0,-180.0,90.0,0.0) or not np.allclose(raw.tag_v2[33550][:2],[1/60,1/60]): raise ValueError('Unexpected source georeference')
    # Area-average first, then derive broad land relief. Bathymetry is not drawn.
    elevation=np.asarray(raw.resize((4096,2048),Image.Resampling.BOX),dtype=np.float32).copy()
    if not np.isfinite(elevation).all() or (elevation < -20000).any(): raise ValueError('Missing/invalid DEM cells')
    raw.close();elevation=np.maximum(elevation,0)
    elevation=gaussian_filter(elevation,0.65,mode=('nearest','wrap'))
    step=2*np.pi*6371008.8/4096
    lat=np.pi/2-(np.arange(2048)+0.5)*np.pi/2048
    east=(np.roll(elevation,-1,axis=1)-np.roll(elevation,1,axis=1))/(2*step*np.maximum(np.cos(lat)[:,None],0.1))
    north=-np.gradient(elevation,axis=0)/step
    # Two fixed northwest/northeast lights avoid very dark one-sided ridges.
    exaggeration=6.0; nx=-east*exaggeration;ny=-north*exaggeration
    normal=np.sqrt(nx*nx+ny*ny+1)
    shade=(0.45*(-0.5*nx+0.5*ny+np.sqrt(0.5))+0.55*(0.5*nx+0.5*ny+np.sqrt(0.5)))/normal
    shade=(shade-np.sqrt(0.5))*1.35
    height=np.log1p(elevation/400)/np.log1p(6000/400)
    signal=np.clip(shade+0.28*height,-0.9,0.9)
    # A pole has no longitude: fade directional shading, average last cap rows.
    signal[:3]=signal[:3].mean(axis=1,keepdims=True);signal[-3:]=signal[-3:].mean(axis=1,keepdims=True)
    rgb=np.zeros((2048,4096,3),dtype=np.uint8)
    rgb[:,:,0]=np.rint(127.5+127.5*signal).astype('uint8')
    rgb[:,:,1]=np.rint(255*np.clip(height,0,1)).astype('uint8')
    rgb[:3,:,1]=np.rint(rgb[:3,:,1].mean(axis=1,keepdims=True));rgb[-3:,:,1]=np.rint(rgb[-3:,:,1].mean(axis=1,keepdims=True))
    image=Image.fromarray(rgb,'RGB')
    out=ROOT/'assets/maps/relief';out.mkdir(parents=True,exist_ok=True)
    assets=[]
    for level,size in [('world',(1024,512)),('region',(4096,2048))]:
        # Raw PNG bytes use a non-imported extension for worker decoding.
        derived=np.asarray(image.resize(size,Image.Resampling.BOX)).copy()
        derived[0]=np.rint(derived[0].mean(axis=0));derived[-1]=np.rint(derived[-1].mean(axis=0))
        p=out/(level+'.bin');Image.fromarray(derived,'RGB').save(p,format='PNG',optimize=True)
        assets.append({'id':'physical_relief:'+level,'path':'res://'+p.relative_to(ROOT).as_posix(),'width':size[0],'height':size[1],'format':'RG8','decoded_bytes':2*size[0]*size[1],'bytes':p.stat().st_size,'angular_pixel_degrees':360/size[0],'equatorial_pixel_m':2*np.pi*6371008.8/size[0]})
    retrieved=json.loads((args.source.parent/'retrieval.json').read_text(encoding='utf8'))
    source={'source_id':SOURCE_ID,'title':'ETOPO 2022 15 Arc-Second Global Relief Model; v1 60s ice-surface global grid','publisher':'NOAA National Centers for Environmental Information','version':'2022-v1-60s-surface','license':'CC0-1.0','locator':URL,'access_metadata':{'source_date':'2022-10-01','retrieved_on':retrieved[0]['retrieved_utc'],'source_type':'PHYSICAL_REFERENCE','doi':'https://doi.org/10.25921/fd45-gt74','metadata_url':'https://www.ncei.noaa.gov/access/metadata/landing-page/bin/iso?id=gov.noaa.ngdc.mgg.dem:etopo_2022','license_url':'https://creativecommons.org/publicdomain/zero/1.0/','resolution':'60 arc-seconds (downsampled by NOAA from 15s); approx 1853m at equator','coverage':[-180,-90,180,90],'horizontal_crs':'EPSG:4326 WGS84','vertical_datum':'EPSG:3855 EGM2008; elevations in metres; surface of Greenland/Antarctic ice sheets','polar_coverage':'Full global grid. Last three derivative rows per pole are longitude-invariant; not a historical ice reconstruction.','known_gaps':'NOAA declares no nodata cells in source grid. Composite observations, spatially variable accuracy, current ice/engineering and lake bathymetry cannot reconstruct 1900.','ocean_handling':'Negative elevations clipped to zero before derivation; no bathymetry, shoreline, land owner or water identity created. Below-sea-level land depressions also suppressed.','historical_applicability':'PHYSICAL_REFERENCE: broad mountain/plateau/plain forms only; not 1900 precise surface, ice, coast, settlement, land use, roads or population.','uncertainty':'Runtime region sampling about 9.8km north-south and longitude-dependent east-west; World about 39.1km. Not usable for slope/path/combat queries.','data_transformation':'Area box average DEM to 4096x2048; nonnegative elevation; periodic longitude Gaussian sigma .65; metric derivatives; two fixed lights and 6x visual slope exaggeration; log-height tint; R8 signed modulation; 1024x512 box-average LOD; no runtime elevation.','source_assets':retrieved}}
    source['access_metadata']['data_transformation']+=' Runtime RG8: red signed form, green quantized log-positive-height for unowned background only; no elevation values or ownership. Physical background is not a historical coastline.'
    value={'status':'PHYSICAL_REFERENCE','assets':assets,'generator':'tools/map/build_global_relief.py:R1','representation':'Two finite static global RG8 LODs; shared source fact, no terrain simulation'}
    fact={'fact_id':'physical_relief:etopo_2022','domain':'physical_reference_content','subject_id':'physical_relief:global','value':value,'unit':'presentation_relief','source_id':SOURCE_ID,'source_version':source['version'],'source_locator':URL,'observation_period':{'from':'1998-01-01','to':'2022-09-01'},'spatial_scope':{'kind':'global','id':'earth'},'methodology':source['access_metadata']['data_transformation'],'confidence':0.8,'lower_bound':None,'upper_bound':None,'license':'CC0-1.0','review_status':'BOUNDED_ESTIMATE','generator':'tools/map/build_global_relief.py:R1'}
    document={'source_registry':{'schema_id':'historical_source_registry_v2','sources':[source]},'evidence_catalog':{'schema_id':'historical_fact_evidence_catalog_v2','facts':[fact]}}
    p=ROOT/'data/presentation/global_physical_relief.json';p.write_text(json.dumps(document,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print(json.dumps({'seconds':time.monotonic()-started,'source_bytes':args.source.stat().st_size,'assets':assets},indent=2))
if __name__=='__main__':main()
