"""Build four small WGS84 material samples for the Rust terrain-review host."""

import argparse
import io
import json
import math
import re
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
import rasterio
from PIL import Image
from rasterio.enums import Resampling
from rasterio.transform import from_bounds
from rasterio.warp import reproject
from rasterio.windows import from_bounds as source_window, Window
from scipy.ndimage import gaussian_filter

BLOCK=1048576
SITES={
    'emilia': (11.29,44.68),
    'tisza': (20.15,46.71),
    'shortgrass': (-104.36,41.64),
    'fagaras': (24.66,45.61),
}
SIDE=(1664,1472)
PALETTE={10:(88,107,73),20:(147,143,97),30:(154,151,102),40:(165,156,110),
         50:(151,146,130),60:(166,153,128),70:(229,230,223),80:(72,103,114),
         90:(114,132,92),95:(93,120,83),100:(128,138,112)}

class RemoteCog:
    def __init__(self,url):
        self.url=url
        self.length=None
        self.parts={}
    def route(self,path,mode='rb'):
        if not path.endswith('.tif'): raise FileNotFoundError(path)
        return CogReader(self)
    def block(self,start,size):
        if start in self.parts: return self.parts[start]
        end=min(start+size,self.length or start+size)-1
        for attempt in range(3):
            try:
                req=urllib.request.Request(self.url+f'?wwo-window={start}-{end}',
                    headers={'Range':f'bytes={start}-{end}','Accept-Encoding':'identity'})
                with urllib.request.urlopen(req,timeout=7) as response:
                    match=re.fullmatch(r'bytes (\d+)-(\d+)/(\d+)',response.headers.get('Content-Range',''))
                    if response.status!=206 or not match or int(match[1])!=start:
                        raise ValueError('Invalid COG range response: '+self.url)
                    self.length=int(match[3])
                    count=int(match[2])-start+1
                    if count!=min(size,self.length-start): raise ValueError('Short COG range')
                    data=response.read(count+1)
                    if len(data)!=count: raise ValueError('Short COG data')
                    self.parts[start]=data
                    return data
            except (OSError,ValueError):
                if attempt==2: raise
        raise RuntimeError('unreachable')

class CogReader(io.RawIOBase):
    def __init__(self,cog):
        self.cog=cog
        self.pos=0
    def readable(self): return True
    def seekable(self): return True
    def tell(self): return self.pos
    def seek(self,offset,whence=0):
        self.pos=offset+(0,self.pos,self.cog.length)[whence]
        return self.pos
    def read(self,n=-1):
        remain=min(self.cog.length-self.pos,n) if n>=0 else self.cog.length-self.pos
        if remain>8*1024**2: raise ValueError('Large individual read refused')
        chunks=[]
        while remain>0:
            start=self.pos//BLOCK*BLOCK
            block=self.cog.block(start,BLOCK)
            index=self.pos-start
            count=min(len(block)-index,remain)
            chunks.append(block[index:index+count])
            self.pos+=count
            remain-=count
        return b''.join(chunks)

def loc(lat,lon):
    return f'{"N" if lat>=0 else "S"}{abs(lat):02}{"E" if lon>=0 else "W"}{abs(lon):03}'

def window(src,bounds):
    f=source_window(*bounds,src.transform)
    left,top=math.floor(f.col_off)-2,math.floor(f.row_off)-2
    right,bottom=math.ceil(f.col_off+f.width)+2,math.ceil(f.row_off+f.height)+2
    return Window(left,top,right-left,bottom-top).intersection(Window(0,0,src.width,src.height))

def read_cog(url,bounds):
    remote=RemoteCog(url)
    remote.block(0,BLOCK)
    with rasterio.open(url.rsplit('/',1)[1],opener=remote.route) as src:
        region=window(src,bounds)
        data=src.read(1,window=region)
        transform=src.window_transform(region)
    print('source bytes',sum(map(len,remote.parts.values())),url,flush=True)
    return data,transform

def resample(data,source,dest,method,nodata=None):
    result=np.empty(SIDE[::-1],np.float32)
    reproject(data,result,src_transform=source,src_crs='EPSG:4326',dst_transform=dest,
              dst_crs='EPSG:4326',resampling=method,src_nodata=nodata,dst_nodata=np.nan)
    return result

def generate(output,name,lon,lat):
    dx=SIDE[0]*25/2/(111195*math.cos(math.radians(lat)))
    dy=SIDE[1]*25/2/111195
    bounds=(lon-dx,lat-dy,lon+dx,lat+dy)
    print(name,bounds,flush=True)
    w=f'ESA_WorldCover_10m_2021_v200_{loc(math.floor(lat/3)*3,math.floor(lon/3)*3)}_Map.tif'
    wurl='https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/'+w
    dest=from_bounds(*bounds,*SIDE)
    classes,tf=read_cog(wurl,bounds)
    print('classes',np.unique(classes,return_counts=True),flush=True)
    rgb=np.zeros(SIDE[::-1]+(3,),np.float32)
    weight=np.zeros(SIDE[::-1],np.float32)
    water=None
    for code,color in PALETTE.items():
        mask=resample((classes==code).astype(np.float32),tf,dest,Resampling.average)
        np.nan_to_num(mask,copy=False,nan=0)
        if code==80:
            water=mask
        else:
            # Resolve classes on the source footprint; suppress isolated single-pixel speckle.
            mask=gaussian_filter(mask,.55)
        rgb+=mask[...,None]*color
        weight+=mask
    if weight.min()<.5: raise ValueError('Missing valid land-cover data in '+name)
    rgb/=weight[...,None]
    elev=np.full(SIDE[::-1],np.nan,np.float32)
    dem_sources=[]
    for alat in range(math.floor(bounds[1]),math.ceil(bounds[3])):
        for alon in range(math.floor(bounds[0]),math.ceil(bounds[2])):
            path=loc(alat,alon)
            d=f'Copernicus_DSM_COG_10_{path[:3]}_00_{path[3:]}_00_DEM'
            durl=f'https://copernicus-dem-30m.s3.amazonaws.com/{d}/{d}.tif'
            dem,tf=read_cog(durl,bounds)
            local=resample(dem,tf,dest,Resampling.bilinear,nodata=-32767)
            np.copyto(elev,local,where=np.isfinite(local))
            dem_sources.append(durl)
    if not np.isfinite(elev).all(): raise ValueError('Missing elevation in '+name)
    # Relief change derives solely from the DEM and is filtered over 50–120 m.
    smooth=gaussian_filter(elev,1.6)
    gy,gx=np.gradient(smooth,25,25)
    slope=np.hypot(gx,gy)
    light=(.81+(gy+gx)*.43)/np.sqrt(1+slope*slope)
    broad=gaussian_filter(elev,8.)
    light=(light-.81)*.65+np.clip((smooth-broad)/340,-.07,.07)
    exposure=np.clip((slope-.26)*1.6,0,.45)*(1-water)
    light*=1-water
    rgb=rgb*(1-exposure[...,None])+np.array([153,141,119])*exposure[...,None]
    rgb*=np.clip(1+light,.65,1.24)[...,None]
    pixels=np.concatenate([rgb,water[...,None]*255],axis=2).clip(0,255).round().astype(np.uint8)
    Image.fromarray(pixels).save(output/(name+'.png'),compress_level=3)
    (output/(name+'.json')).write_text(json.dumps(dict(extent=bounds,image=name+'.png',center=[lon,lat],
        sample_mpp=25,sources=[wurl,*dem_sources],modern_reference=True),indent=2),encoding='utf-8')
    print('saved',name,(output/(name+'.png')).stat().st_size,flush=True)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--site",choices=SITES,action="append")
    args=parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=True)

    def build(name):
        with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR"):
            generate(args.output,name,*SITES[name])

    with ThreadPoolExecutor(max_workers=2) as pool:
        for _ in pool.map(build,dict.fromkeys(args.site or SITES)):
            pass


if __name__=="__main__":
    main()

