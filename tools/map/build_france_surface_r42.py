"""France/Corsica display derivatives, not historical terrain/land-use facts.

Offline dependencies: numpy, scipy, Pillow, rasterio, requests. HTTP COG range
reads retain bounded, georeferenced research extracts, not the global archive.
Run: python tools/map/build_france_surface_r42.py
Only assets/maps/relief/france_r42_*.bin and the presentation catalogue ship.
"""
from __future__ import annotations
import concurrent.futures as futures
import json
import math
import os
from pathlib import Path
import struct
import sys
import time
import zlib

# Windows embedded Python does not add wheel DLL directories automatically.
_dll = None
if os.name == "nt":
    dlls = Path(sys.executable).parent / "Lib/site-packages/rasterio.libs"
    if dlls.exists():
        _dll = os.add_dll_directory(str(dlls))
import numpy as np
import rasterio
from rasterio.enums import Resampling
from rasterio.transform import from_bounds
from rasterio.warp import reproject
from scipy.ndimage import gaussian_filter, map_coordinates
from PIL import Image
import requests

ROOT = Path(__file__).resolve().parents[2]
RESEARCH = ROOT / "local-artifacts/france-surface-r42"
OUT = ROOT / "assets/maps/relief"
DEM_ROOT = "https://copernicus-dem-90m.s3.amazonaws.com"
WC_ROOT = "https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map"
BOUNDS = (-6., 40., 12., 54.)
STEP = 1 / 512  # 217.2m N-S, longitude-dependent E-W; display, not native DEM.
PADDING = 32


def smooth(a, b, x):
    t = np.clip((x-a)/(b-a), 0, 1)
    return t*t*(3-2*t)


def support(lon, lat):
    # Geographic rectangular collars outside mainland and Corsica. They do not
    # use ownership, administrative or political polygon edges as terrain cuts.
    mainland = (smooth(-6., -5.3, lon) * (1-smooth(8., 8.8, lon)) *
                smooth(41.4, 42.15, lat) * (1-smooth(51.35, 52., lat)))
    corsica = (smooth(8., 8.5, lon) * (1-smooth(9.8, 10.4, lon)) *
               smooth(40.8, 41.25, lat) * (1-smooth(43.15, 43.65, lat)))
    return np.maximum(mainland, corsica)


def cog_extract(kind, lon, lat):
    """600px/degree DSM average, 750px/degree tree-class reference sample."""
    directory = RESEARCH / kind
    directory.mkdir(parents=True, exist_ok=True)
    name = f"{lat:+03d}_{lon:+04d}"
    path = directory / (name + ".tif")
    record = directory / (name + ".json")
    if path.exists() and record.exists():
        return json.loads(record.read_text(encoding="utf8"))
    if kind == "dem":
        stem = f"Copernicus_DSM_COG_30_N{lat:02d}_00_{'E' if lon>=0 else 'W'}{abs(lon):03d}_00_DEM"
        url = f"{DEM_ROOT}/{stem}/{stem}.tif"
        shape = (600, 600)
        method = Resampling.average
    else:
        stem = f"ESA_WorldCover_10m_2021_v200_N{lat:02d}{'E' if lon>=0 else 'W'}{abs(lon):03d}_Map"
        url = f"{WC_ROOT}/{stem}.tif"
        shape = (2250, 2250)  # COG 16x categorical overview, no invented classes.
        method = Resampling.nearest
    for attempt in range(3):
        try:
            input_path = url
            if kind == "dem":
                # A GLO90 geocell is only a few MB. Retain its original locally;
                # this avoids many high-latency small HTTP TIFF range requests.
                original = RESEARCH / "source" / (stem+".tif")
                original.parent.mkdir(exist_ok=True)
                if not original.exists():
                    response = requests.get(url,timeout=90)
                    response.raise_for_status()
                    temporary=original.with_suffix(".download")
                    temporary.write_bytes(response.content)
                    temporary.replace(original)
                input_path = str(original)
            with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR", GDAL_HTTP_TIMEOUT="90",
                              CPL_VSIL_CURL_ALLOWED_EXTENSIONS=".tif", GDAL_CACHEMAX=32*1024*1024):
                with rasterio.open(input_path) as src:
                    data = src.read(1, out_shape=shape, resampling=method)
                    transform = src.transform * src.transform.scale(src.width/shape[1], src.height/shape[0])
                    info = dict(url=url, native_shape=list(src.shape), crs=str(src.crs),
                                bounds=list(src.bounds), overview_factors=src.overviews(1),
                                native_transform=list(src.transform), extracted_transform=list(transform),
                                extracted_shape=list(shape), method=method.name,
                                retrieved_utc=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
                    if kind == "trees":
                        classes = np.unique(data).tolist()
                        if not set(classes).issubset({0,10,20,30,40,50,60,70,80,90,95,100}):
                            raise ValueError(f"Noncategorical WorldCover overview: {classes}")
                        # Class 10 includes plantations. This is not crown-density,
                        # species, historical forest or economic forestry data.
                        data = (data == 10).astype("uint8") * 255
                        info["meaning"] = "2021 class-10 presence, sampled categorical overview; not canopy percent"
                    with rasterio.open(path, "w", driver="GTiff", width=shape[1], height=shape[0],
                                       count=1, dtype=str(data.dtype), crs=src.crs,
                                       transform=transform, compress="deflate") as dst:
                        dst.write(data, 1)
                    info["bytes"] = path.stat().st_size
                    record.write_text(json.dumps(info, indent=2), encoding="utf8")
                    return info
        except Exception:
            if attempt == 2:
                raise
            time.sleep(1 + attempt)


def acquire():
    RESEARCH.mkdir(parents=True, exist_ok=True)
    listing = RESEARCH / "copdem_tileList.txt"
    if not listing.exists():
        r = requests.get(f"{DEM_ROOT}/tileList.txt", timeout=90)
        r.raise_for_status()
        listing.write_text(r.text, encoding="utf8")
    known = listing.read_text(encoding="utf8")
    jobs = []
    for lat in range(40, 54):
        for lon in range(-6, 12):
            xx, yy = np.meshgrid(np.linspace(lon,lon+1,7),np.linspace(lat,lat+1,7))
            if support(xx,yy).max() <= 0: continue
            stem = f"Copernicus_DSM_COG_30_N{lat:02d}_00_{'E' if lon>=0 else 'W'}{abs(lon):03d}_00_DEM"
            if stem in known: jobs.append(("dem",lon,lat))
    # The selected 3-degree forest COGs cover only the two geographic collars.
    for lat in range(39, 54, 3):
        for lon in range(-6, 12, 3):
            xx, yy = np.meshgrid(np.linspace(lon,lon+3,13),np.linspace(lat,lat+3,13))
            if support(xx,yy).max() > 0: jobs.append(("trees",lon,lat))
    records = []
    with futures.ThreadPoolExecutor(max_workers=5) as pool:
        pending = {pool.submit(cog_extract,*job):job for job in jobs}
        for count, future in enumerate(futures.as_completed(pending), 1):
            records.append(dict(kind=pending[future][0], **future.result()))
            print(f"Source {count}/{len(jobs)} {pending[future]}", flush=True)
    (RESEARCH / "sources.json").write_text(json.dumps(records,indent=2),encoding="utf8")


def mosaic(kind):
    w, s, e, n = BOUNDS
    shape = (round((n-s)/STEP),round((e-w)/STEP))
    path = RESEARCH / f"{kind}_aligned.npy"
    if path.exists() and "--rebuild" not in sys.argv: return np.load(path, mmap_mode="r")
    data = np.lib.format.open_memmap(path, mode="w+", dtype="float32", shape=shape)
    data[:] = 0  # Absent CopDEM tiles in provider's list are ocean, not missing land.
    counts = np.zeros(shape,dtype="uint8")
    transform = from_bounds(w,s,e,n,shape[1],shape[0])
    for file in sorted((RESEARCH/kind).glob("*.tif")):
        with rasterio.open(file) as src:
            # Write just the overlapping output window, preserving the provider's
            # half-cell PixelIsPoint offset instead of concatenating by tile name.
            win = rasterio.windows.from_bounds(*src.bounds,transform=transform)
            col0=max(0,math.floor(win.col_off)); row0=max(0,math.floor(win.row_off))
            col1=min(shape[1],math.ceil(win.col_off+win.width)); row1=min(shape[0],math.ceil(win.row_off+win.height))
            if col1<=col0 or row1<=row0: continue
            region = np.full((row1-row0,col1-col0),np.nan,dtype="float32")
            reproject(rasterio.band(src,1),region,src_transform=src.transform,src_crs=src.crs,
                      dst_transform=transform*rasterio.Affine.translation(col0,row0),dst_crs="EPSG:4326",
                      dst_nodata=np.nan,resampling=Resampling.bilinear if kind=="dem" else Resampling.average)
            # Source half-cell footprints can overlap. Average valid samples;
            # retain true negative heights and never mix a missing edge with 0.
            old=data[row0:row1,col0:col1]
            valid=np.isfinite(region)
            old[valid]+=region[valid]
            counts[row0:row1,col0:col1][valid]+=1
    # Row strips avoid a second nationwide floating-point temporary.
    for row in range(0,shape[0],256):
        count=counts[row:row+256]
        np.divide(data[row:row+256],count,out=data[row:row+256],where=count>0)
    data.flush()
    return data


def field(bounds):
    """Common EPSG:4326 sampling with real neighbouring cells around every tile."""
    w,s,e,n=bounds
    nx=round((e-w)/STEP); ny=round((n-s)/STEP)
    lon=w+(np.arange(nx,dtype="float32")+.5)*STEP
    lat=n-(np.arange(ny,dtype="float32")+.5)*STEP
    x=(lon-BOUNDS[0])/STEP-.5
    y=(BOUNDS[3]-lat)/STEP-.5
    coordinates=np.meshgrid(y,x,indexing="ij")
    h=map_coordinates(HEIGHT,coordinates,order=1,mode="nearest",prefilter=False)
    trees=map_coordinates(TREES,coordinates,order=1,mode="nearest",prefilter=False)/255
    # Derivatives are geographic metres, with a common 3x *shading* factor.
    # Geometry and source heights are never altered. A second broader band
    # retains valley shape; neither band predicts a vegetation/rock class.
    h=gaussian_filter(h,.65)
    dy=111195*STEP
    dx=dy*np.cos(np.deg2rad(lat))[:,None]
    gy,gx=np.gradient(h)
    gx=gx/dx; gy=-gy/dy
    normal=np.sqrt(1+9*(gx*gx+gy*gy))
    shade=(.45*(-3*gx*(-.5)-3*gy*.5+.70710678)+
           .55*(-3*gx*.5-3*gy*.5+.70710678))/normal
    shade=np.clip(1+(shade-.70710678)*1.7,.48,1.32)
    height=np.log1p(np.maximum(h,0)/200)/np.log1p(5000/200)
    alpha=support(lon[None,:],lat[:,None])
    return np.stack([np.clip(height,0,1),(shade-.4)/1.0,np.clip(trees,0,1),alpha],axis=-1)


def write_asset(name, pixels, bounds, role):
    # Offline mip chain in linear data space. zlib is the same decoder already
    # used by .geom. One bounded image upload, no runtime normal or mip builder.
    image=Image.fromarray(np.uint8(np.clip(pixels,0,1)*255+.5),"RGBA")
    width,height=image.size
    levels=[]; mip=image
    while True:
        levels.append(mip.tobytes())
        if mip.size==(1,1): break
        # These are data channels. In some consumers A stores hillshade,
        # rather than transparency. Pillow RGBA resize premultiplies RGB by A
        # and corrupts those formats. Reduce every channel independently.
        size=(max(1,mip.width//2),max(1,mip.height//2))
        channels=[channel.resize(size,Image.Resampling.BOX) for channel in mip.split()]
        mip=Image.merge('RGBA',channels)
    raw=b"".join(levels)
    path=OUT/(name+".bin")
    path.write_bytes(b"FRT42\0\0\0"+struct.pack("<III",width,height,len(raw))+zlib.compress(raw,6))
    descriptor=dict(id="physical_relief:"+name,path="res://"+path.relative_to(ROOT).as_posix(),
                    format="RGBA8_MIP_DEFLATE",width=width,height=height,decoded_bytes=len(raw),
                    bytes=path.stat().st_size,bounds_lon_lat=list(bounds),surface_role=role,
                    core_inset_degrees=PADDING*STEP if role=="detail" else 0,
                    channels="R log1p(height/200)/log(26); G hillshade minus .4; B sampled 2021 tree class fraction; A geographic support",
                    display_spacing_degrees=[(bounds[2]-bounds[0])/width,(bounds[3]-bounds[1])/height],
                    display_spacing_m_approx=[111195*(bounds[2]-bounds[0])/width*math.cos(math.radians((bounds[1]+bounds[3])/2)),111195*(bounds[3]-bounds[1])/height])
    return descriptor


def catalogue(assets):
    source=dict(source_id="copdem90_france_wc2021_r42",title="France/Corsica modern surface display: Copernicus GLO-90 and ESA WorldCover 2021",publisher="European Union / ESA / Airbus; ESA WorldCover consortium",version="GLO90-COG-public+WorldCover-2021-v200:R42",license="Copernicus-DEM-GLO90+CC-BY-4.0",locator="https://copernicus-dem-90m.s3.amazonaws.com/readme.html",access_metadata=dict(
        horizontal_crs="EPSG:4326; GLO90 WGS84-G1150 pixel-is-point corrected by source affine",
        vertical_datum="EPSG:3855 EGM2008 orthometric metres; DSM includes vegetation/infrastructure",
        elevation_epoch="TanDEM-X 2011-2015, older gap-fill possible; public COG release as retrieved",
        cover_epoch="2021-01-01/2021-12-31; WorldCover v200 class 10 includes plantations",
        native_sampling="GLO90 3 arcseconds latitude, longitude variable 3/4.5 arcseconds here; WorldCover 1/12000 degree",
        research_extraction="GLO90 600 rows/degree average (6 arcsec); WorldCover categorical 16x overview (~148m N-S), binary class 10 then area average; not measured crown density",
        bounds_lon_lat=list(BOUNDS),historical_applicability="Modern geographic reference only. No 1900 land cover, terrain precision, historical coast, ownership, forestry or simulation input.",
        license_url="https://dataspace.copernicus.eu/sites/default/files/media/files/2025-06/copernicus_contributing_mission_data_access_v2_cop_dem_licenses.pdf",
        cover_source="https://esa-worldcover.org/en/data-access",cover_doi="https://doi.org/10.5281/zenodo.7254221",
        generator="tools/map/build_france_surface_r42.py"))
    fact=dict(fact_id="physical_relief:france_r42",domain="physical_reference_content",subject_id="physical_relief:france_corsica",
              value=dict(status="PHYSICAL_REFERENCE",assets=assets),unit="presentation_relief",source_id=source["source_id"],source_version=source["version"],source_locator=source["locator"],
              observation_period={"from":"2011-01-01","to":"2021-12-31"},spatial_scope={"kind":"geographic_reference","id":"france_mainland_corsica_with_collars"},
              methodology="Geographic DSM resampling, fixed metric hillshade, shared palette, sampled modern tree class. Offline RGBA linear-data mips; no new land geometry or domain facts.",confidence=.8,lower_bound=None,upper_bound=None,license=source["license"],review_status="EVIDENCE_LINKED",generator="tools/map/build_france_surface_r42.py")
    document={"source_registry":{"schema_id":"historical_source_registry_v2","sources":[source]},"evidence_catalog":{"schema_id":"historical_fact_evidence_catalog_v2","facts":[fact]}}
    (ROOT/"data/presentation/france_surface_r42.json").write_text(json.dumps(document,ensure_ascii=False,indent=2)+"\n",encoding="utf8")


if __name__=="__main__":
    OUT.mkdir(parents=True,exist_ok=True)
    acquire()
    HEIGHT=mosaic("dem"); TREES=mosaic("trees")
    # Assemble a common display field tile by tile, with a 32-cell real collar.
    full=np.lib.format.open_memmap(RESEARCH/"field.npy",mode="w+",dtype="float32",shape=(*HEIGHT.shape,4))
    assets=[]
    for lat in range(40,54,2):
        for lon in range(-6,12,2):
            c0=round((lon-BOUNDS[0])/STEP); r0=round((BOUNDS[3]-lat-2)/STEP)
            core=(lon,lat,lon+2,lat+2)
            collar=PADDING*STEP
            b=(lon-collar,lat-collar,lon+2+collar,lat+2+collar)
            pixels=field(b)
            full[r0:r0+1024,c0:c0+1024]=pixels[PADDING:-PADDING,PADDING:-PADDING]
            # A halo touching a dataset edge is not a needed detail tile.
            if pixels[PADDING:-PADDING,PADDING:-PADDING,3].max()<.001: continue
            name=f"france_r42_{lat}_{lon:+d}"
            a=write_asset(name,pixels,b,"detail"); a["core_bounds_lon_lat"]=list(core)
            assets.append(a)
            print("Built",name,flush=True)
    full.flush()
    coarse=np.empty((896,1152,4),dtype="float32")
    for channel in range(4):
        coarse[:,:,channel]=np.asarray(Image.fromarray(full[:,:,channel],"F").resize((1152,896),Image.Resampling.BOX))
    assets.insert(0,write_asset("france_r42_base",coarse,BOUNDS,"base"))
    catalogue(assets)
    # Static GIS preview, not a game or performance test.
    h=coarse[:,:,0]; shade=.4+coarse[:,:,1]; tree=coarse[:,:,2]
    low=np.array([.57,.57,.46]); high=np.array([.70,.68,.62]); green=np.array([.27,.38,.27])
    rgb=low+(high-low)*smooth(.2,.95,h)[:,:,None]
    rgb=rgb*(1-tree[:,:,None]*.78)+green*tree[:,:,None]*.78
    rgb*=shade[:,:,None]
    rgb*=coarse[:,:,3,None]
    Image.fromarray(np.uint8(np.clip(rgb,0,1)*255)).save(RESEARCH/"france_preview.png")
    print(json.dumps(dict(files=len(assets),bytes=sum(a["bytes"] for a in assets),decoded_bytes=sum(a["decoded_bytes"] for a in assets))),flush=True)
