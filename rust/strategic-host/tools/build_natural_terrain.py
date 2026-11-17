"""Build the WGS84 WorldCRS84Quad global terrain from cached geographic sources."""

import argparse
import os
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager, ExitStack, nullcontext
from datetime import datetime
import filecmp
from functools import lru_cache, partial
from io import BytesIO
import json
from pathlib import Path
from shutil import copyfile, disk_usage
from struct import Struct, unpack_from
from tempfile import TemporaryDirectory
from zipfile import ZipFile
import zlib

import ispc_texcomp
import numpy as np
from PIL import Image
import rasterio
from rasterio import features
from rasterio.enums import Resampling
from rasterio.transform import from_origin
from rasterio.vrt import WarpedVRT
from rasterio.windows import Window
from scipy.ndimage import gaussian_filter, label
import shapefile
from shapely import clip_by_rect, intersects_xy, make_valid, prepare
from shapely.affinity import translate
from shapely.geometry import LineString, Polygon, box, shape
from shapely.strtree import STRtree


VERSION = "worldcrs84quad-z4-v3"
PACK_VERSION = "worldcrs84quad-15s-v1"
PACK_MAGIC = b"WWOQ4PK1"
COMPACT_VERSION = "worldcrs84quad-15s-v2"
COMPACT_MAGIC = b"WWOQ4PK2"
COMPACT_STRENGTH = 6
COMPACT_FORMAT = {
    "color": "BC7 RGBA UNORM with land coverage in alpha; original blocks",
    "height": "signed little-endian i16 metres; 2D difference, zigzag, byte planes",
    "storage": "independent Zstandard frames",
    "strength": COMPACT_STRENGTH,
}
PACK_RECORD = Struct("<IIII")
PACK_MAX_LEVEL = 7
DEM_15S = "gmt-15s-p-nju.grd"
DEM_URL = "https://mirror.nju.edu.cn/gmtdata/earth_relief_15s_p.grd"
TILE = 256
GUTTER = 4
MAX_LEVEL = 4
RIVER_REACHES = 8_477_883
HEADER = Struct("<8sIII")
COLOR_MAGIC = b"WWOQ3BC7"
HEIGHT_MAGIC = b"WWOQ3I16"
STRIPE = 256
M_PER_DEGREE = 111195.
COVER_COLORS = {
    10: (.29, .44, .32), 20: (.59, .59, .42), 30: (.55, .59, .40),
    40: (.66, .64, .44), 50: (.57, .57, .43), 60: (.73, .60, .43),
    70: (.87, .91, .90), 90: (.44, .53, .41), 95: (.31, .45, .35),
    100: (.48, .51, .44),
}
NEUTRAL = np.array([.57, .57, .43], dtype=np.float32)
ENCODER = ispc_texcomp.BC7EncSettings.from_profile("alpha_fast")
RIVER_COLOR = np.array([.20, .38, .45], dtype=np.float32)
RIVER_OPACITY = .78
LAND_COVER_CODES = (0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 100)
LAND_PALETTE = np.array([
    [.53,.51,.37], [.255,.41,.31], [.47,.49,.35], [.47,.53,.33],
    [.61,.57,.36], [.53,.51,.37], [.73,.61,.44], [.89,.92,.91],
    [.53,.51,.37], [.36,.46,.34], [.25,.41,.33], [.47,.49,.36],
], dtype=np.float32)
LAND_FRACTIONS = np.eye(len(LAND_COVER_CODES), dtype=np.float32)
LAND_CLASS_LOOKUP = LAND_FRACTIONS[np.zeros(256, dtype=np.int32)]
LAND_CLASS_LOOKUP[list(LAND_COVER_CODES)] = LAND_FRACTIONS
HISTORICAL_CROP = LAND_COVER_CODES.index(40)
HISTORICAL_CROP_REPLACEMENT = tuple(LAND_COVER_CODES.index(code) for code in (0,10,20,30,50,60))


def centres(start, stop):
    return np.arange(start, stop, dtype=np.float64) + .5


def grid(width, bounds):
    x0, y0, x1, y1 = bounds
    step = 360 / width
    lon = centres(x0, x1) * step - 180
    lat = 90 - centres(y0, y1) * step
    return lon, lat


def sample(image, x, y, wrap=False):
    """Bilinear samples over the already mosaicked source, at texel centres."""
    xi, yi = np.floor(x).astype(np.int32), np.floor(y).astype(np.int32)
    a, b = (x - xi).astype(np.float32), (y - yi).astype(np.float32)
    if wrap:
        x0, x1 = xi % image.shape[1], (xi+1) % image.shape[1]
    else:
        x0, x1 = np.clip(xi, 0, image.shape[1]-1), np.clip(xi+1, 0, image.shape[1]-1)
    y0, y1 = np.clip(yi, 0, image.shape[0]-1), np.clip(yi+1, 0, image.shape[0]-1)
    extra = (None,) * (image.ndim - 2)
    a, b = a[(None, slice(None), *extra)], b[(slice(None), None, *extra)]
    top = image[y0[:, None], x0] * (1-a) + image[y0[:, None], x1] * a
    bottom = image[y1[:, None], x0] * (1-a) + image[y1[:, None], x1] * a
    return top * (1-b) + bottom * b


class Relief:
    def __init__(self, data, lon0, lat0, step):
        self.data, self.lon0, self.lat0, self.step = data, lon0, lat0, step

    def at(self, lon, lat):
        return sample(self.data, (lon-self.lon0)/self.step, (self.lat0-lat)/self.step)


def global_relief(path):
    with rasterio.open(path) as source:
        t = source.transform
        if (source.shape != (10801, 21601) or source.nodata != -32768
                or not np.allclose(t * (.5, .5), (-180, 90))
                or not np.allclose((t.a, t.e), (1/60, -1/60))):
            raise ValueError("Expected the GMT gridline-registered global 1 arc-minute DEM")
        if "SRTM15+V2.1" not in source.tags().get("NC_GLOBAL#description",""):
            raise ValueError("The configured global mother source is SRTM15+ V2.1")
        return Relief(source.read(1), -180, 90, 1/60)


class Relief15s:
    def __init__(self, source):
        self.source = source
        self.description = source.tags().get("NC_GLOBAL#description", "")
        if (source.shape != (43200, 86400)
                or not np.allclose(tuple(source.transform)[:6], (1/240, 0, -180, 0, -1/240, 90))
                or "SRTM15_V2.5.5.nc" not in self.description):
            raise ValueError("Expected the GMT pixel-registered SRTM15+ V2.5.5 15 arc-second grid")
        self.scale = source.scales[0]
        self.offset = source.offsets[0]
        self.last_extent = None
        self.last_stripe = None

    def stripe(self, start, stop):
        if self.last_extent == (start, stop):
            return self.last_stripe
        stripe = self.source.read(1, window=Window(0, start, self.source.width, stop-start))
        if self.source.nodata is not None and np.any(stripe == self.source.nodata):
            raise ValueError(f"Missing elevation in GMT source rows {start}–{stop}")
        self.last_extent = (start, stop)
        self.last_stripe = stripe
        return stripe

    def at(self, lon, lat):
        x = (lon+180)*240-.5
        y = np.clip((90-lat)*240-.5, 0, self.source.height-1)
        start = int(np.floor(y.min()))
        stop = min(self.source.height, int(np.floor(y.max()))+2)
        stripe = self.stripe(start, stop)
        return sample(stripe, x, y-start, wrap=True)*self.scale+self.offset


class LandCover:
    def __init__(self, folder, native=False):
        self.lookup = np.broadcast_to(NEUTRAL, (256, 3)).copy()
        for code, tint in COVER_COLORS.items():
            self.lookup[code] = tint
        keys = [path.removesuffix("_Map.tif").split("_")[-1]
                for path in (folder / "keys.txt").read_text().splitlines()]
        self.tiles = {}
        self.span = 562 if native else 96
        for key in keys:
            y = int(key[1:3]) * (-1 if key[0]=="S" else 1)
            x = int(key[4:]) * (-1 if key[3]=="W" else 1)
            if native:
                self.tiles[y, x] = folder / f"{key}.png"
                continue
            with Image.open(folder / f"{key}.png") as tile:
                colors = self.lookup[np.asarray(tile)]
            reduced = [np.asarray(Image.fromarray(colors[...,i]).resize((self.span,)*2, Image.Resampling.BOX))
                       for i in range(3)]
            self.tiles[y, x] = (np.clip(np.stack(reduced, axis=-1), 0, 1)*255+.5).astype(np.uint8)

    @staticmethod
    @lru_cache(maxsize=256)
    def codes(path):
        with Image.open(path) as image:
            return np.array(image)

    def at(self, lon, lat):
        return self.sample(lon, lat, self.lookup, NEUTRAL)

    def fractions(self, lon, lat):
        return self.sample(lon, lat, LAND_CLASS_LOOKUP, LAND_FRACTIONS[0])

    def sample(self, lon, lat, lookup, default):
        # Globally registered source cells, with the same interpolation on both sides of each page.
        step = 3/self.span
        x = (lon+180)/step-.5
        y = (90-lat)/step-.5
        xi, yi = np.floor(x).astype(np.int32), np.floor(y).astype(np.int32)
        a, b = (x-xi).astype(np.float32), (y-yi).astype(np.float32)
        def gather(dx, dy):
            xx = (xi+dx) % (120*self.span)
            yy = np.clip(yi+dy,0,60*self.span-1)
            cc, rr = xx//self.span, yy//self.span
            result = np.broadcast_to(default, (len(lat),len(lon),len(default))).copy()
            # Missing WorldCover tiles are ocean and ice outside its observed coverage.
            for r in np.unique(rr):
                ii = np.flatnonzero(rr==r)
                for c in np.unique(cc):
                    tile = self.tiles.get((87-3*r, -180+3*c))
                    if tile is not None:
                        jj = np.flatnonzero(cc==c)
                        positions = (yy[ii,None]%self.span,xx[jj]%self.span)
                        color = (lookup[self.codes(tile)[positions]] if isinstance(tile, Path)
                                 else tile[positions] * (1/255))
                        result[ii[:,None],jj] = color
            return result
        a, b = a[None,:,None], b[:,None,None]
        return (gather(0,0)*(1-a)+gather(1,0)*a)*(1-b) + (gather(0,1)*(1-a)+gather(1,1)*a)*b


def physical_shapes(directory, name):
    with ZipFile(directory / f"us10-{name}.zip") as archive:
        stem = f"ne_10m_{name}"
        reader = shapefile.Reader(shp=BytesIO(archive.read(f"{stem}.shp")),
                                  dbf=BytesIO(archive.read(f"{stem}.dbf")))
        return [shape(row.__geo_interface__) for row in reader.iterShapes()]


def hydro_attributes(dbf):
    # Read only the needed columns in the fixed-width dBASE table.
    wanted = {"HYRIV_ID":"i4", "NEXT_DOWN":"i4", "UPLAND_SKM":"f4", "DIS_AV_CMS":"f4"}
    with dbf.open("rb") as table:
        rows,header_size,row_size = unpack_from("<IHH",table.read(32),4)
        offsets = {}
        offset = 1
        for _ in range((header_size-33)//32):
            field = table.read(32)
            name = field[:11].split(b"\0",1)[0].decode("ascii")
            width = field[16]
            if name in wanted:
                offsets[name] = (offset,width)
            offset += width
    if offset!=row_size or offsets.keys()!=wanted.keys():
        raise ValueError("Invalid HydroRIVERS table layout")
    records = np.memmap(dbf,mode="r",offset=header_size,shape=(rows,),dtype=f"V{row_size}")
    return {name: np.ndarray((rows,),dtype=f"S{width}",buffer=records,
                             offset=offset,strides=(row_size,)).astype(wanted[name])
            for name,(offset,width) in offsets.items()}


def river_polygons(shp, width):
    # Keep physical lines crossing the antimeridian on both sides of the grid.
    for start,end in zip(shp.parts,[*shp.parts[1:],len(shp.points)]):
        points = np.asarray(shp.points[start:end])
        if len(points)<2:
            continue
        if np.ptp(points[:,0])>180:
            points[:,0] = np.degrees(np.unwrap(np.radians(points[:,0])))
        polygon = LineString(points).buffer(width,quad_segs=2)
        yield polygon
        if polygon.bounds[0]<-180:
            yield translate(polygon,xoff=360)
        if polygon.bounds[2]>180:
            yield translate(polygon,xoff=-360)


def hydrography(source, output, scratch):
    stem = "HydroRIVERS_v10_shp/HydroRIVERS_v10"
    with ZipFile(source) as archive:
        for extension in (".dbf",".shp",".shx"):
            archive.extract(stem+extension,scratch)
    base = scratch / stem
    columns = hydro_attributes(base.with_suffix(".dbf"))
    ids, downstream = columns["HYRIV_ID"], columns["NEXT_DOWN"]
    order = np.argsort(ids)
    sorted_ids = ids[order]
    if len(ids)!=RIVER_REACHES or np.any(sorted_ids[1:]<=sorted_ids[:-1]):
        raise ValueError("Expected the complete HydroRIVERS v1.0 global network with unique reach IDs")
    position = np.searchsorted(sorted_ids, downstream).clip(0,len(ids)-1)
    matched = sorted_ids[position]==downstream
    missing = np.unique(downstream[(downstream!=0)&~matched])
    if len(missing):
        raise ValueError(f"Unresolved HydroRIVERS downstream identifiers: {missing[:20]}")

    connectivity = np.column_stack((sorted_ids,downstream[order])).astype("<u4",copy=False)
    connectivity.tofile(output/"river-topology.u32")

    # Use a global visibility threshold and retain downstream links to the outlet.
    # The topology retains all reaches, including those below Z4 resolution.
    area, flow = columns["UPLAND_SKM"], columns["DIS_AV_CMS"]
    selected = (area>=4000) | (flow>=200)
    next_record = np.where(matched,order[position],len(ids))
    front = np.flatnonzero(selected)
    while front.size:
        following = next_record[front]
        following = following[following<len(ids)]
        front = np.unique(following[~selected[following]])
        selected[front] = True
    displayed = np.flatnonzero(selected)
    geometries = []
    with shapefile.Reader(str(base)) as reader:
        for row in displayed:
            half_width = .006 if area[row]>=15_000 or flow[row]>=1000 else .004
            geometries.extend(river_polygons(reader.shape(int(row)),half_width))
    return STRtree(geometries), len(ids),len(displayed)


def rasterize(tree, width, rect, *, samples=2):
    x0,y0,x1,y1 = rect
    step = 360/width
    west,north = x0*step-180, 90-y0*step
    east,south = x1*step-180, 90-y1*step
    selected = tree.geometries.take(tree.query(box(west,south,east,north), predicate="intersects"))
    if not len(selected):
        return np.zeros((y1-y0,x1-x0), dtype=np.float32)
    bits = features.rasterize(selected, out_shape=((y1-y0)*samples,(x1-x0)*samples), dtype="uint8",
                              transform=from_origin(west,north,step/samples,step/samples))
    return bits.reshape(y1-y0,samples,x1-x0,samples).mean(axis=(1,3), dtype=np.float32)


def surface(relief, cover, vectors, width, rect, *, elevation_snow):
    # One extra sample on each side for metric central differences, independent of page padding.
    x0,y0,x1,y1 = rect
    lon,lat = grid(width, (x0-1,y0-1,x1+1,y1+1))
    z = relief.at((lon+180)%360-180, np.clip(lat,-90,90))
    if np.any(z < -12_000):
        raise ValueError(f"Missing or invalid elevation in {rect}")
    step = M_PER_DEGREE*360/width
    ground = np.maximum(z,-450.)
    east = (ground[1:-1,2:]-ground[1:-1,:-2])/(2*step*np.maximum(.035,np.cos(np.radians(lat[1:-1,None]))))
    south = (ground[2:,1:-1]-ground[:-2,1:-1])/(2*step)
    z, lon, lat = z[1:-1,1:-1], lon[1:-1], lat[1:-1,None]
    slope = np.hypot(east,south)
    light = (1+.91*east+.82*south)/np.sqrt(1+2.1*slope**2)
    light = np.clip(.98+.53*(light-1),.57,1.22)
    high = np.clip((z-480)/3800,0,1)
    rock = np.clip((slope-.19)*.54+high*.49,0,.77)
    # WorldCover class 70 contributes snow and ice through the base palette.
    snow = rasterize(vectors["glaciated_areas"],width,rect)*.96
    if elevation_snow:
        snow = np.maximum(np.clip((z-(5200-32*np.abs(lat)))/900,0,.91), snow)
    color = cover.at(lon,lat[:,0])
    # Latitude and elevation supply the same climatic tint in all levels.
    polar = np.clip((np.abs(lat) + np.maximum(z, 0)*.003 - 63)/22, 0, .48)
    color += (np.array([.70,.73,.69],np.float32)-color)*polar[...,None]
    color += (np.array([.65,.60,.53],np.float32)-color)*rock[...,None]
    color += (np.array([.89,.92,.91],np.float32)-color)*snow[...,None]
    color *= light[...,None]
    land = rasterize(vectors["land"],width,rect)
    lake = rasterize(vectors["lakes"],width,rect)
    river = rasterize(vectors["rivers_lake_centerlines"],width,rect)
    water = np.maximum(lake,river*RIVER_OPACITY) * land
    color += (RIVER_COLOR-color)*water[...,None]
    return color, z, land, water, lake


def smooth_weight(lower, upper, value):
    t = np.clip((value-lower)/(upper-lower), 0, 1)
    return t*t*(3-2*t)


def read_wrapped_grid(source, rect, index=1):
    x0,y0,x1,y1 = rect
    left = x0 % source.width
    first = min(source.width-left,x1-x0)
    boundless = y0 < 0 or y1 > source.height
    values = source.read(index,window=Window(left,y0,first,y1-y0),boundless=boundless)
    if first == x1-x0:
        return values
    wrap = source.read(index,window=Window(0,y0,x1-x0-first,y1-y0),boundless=boundless)
    return np.concatenate((values,wrap),axis=-1)


def apply_historical_cropland(fractions, estimate):
    crop = fractions[...,HISTORICAL_CROP].copy()
    other = fractions[...,HISTORICAL_CROP_REPLACEMENT]
    eligible = other.sum(axis=-1)
    valid = np.isfinite(estimate) & (estimate>=0) & (estimate<=1)
    target = np.where(valid,np.minimum(estimate,crop+eligible),crop)
    added = np.maximum(target-crop,0)
    lost = np.maximum(crop-target,0)
    scale = 1-np.divide(added,eligible,out=np.zeros_like(eligible),where=eligible>0)
    fractions[...,HISTORICAL_CROP_REPLACEMENT] = other*scale[...,None]
    # The reconstruction tracks crops only. The freed area has unknown cover.
    fractions[...,0] += lost
    fractions[...,HISTORICAL_CROP] = target


def historical_cropland_grid(source, width):
    step = 1/120
    if (source.count != 1 or source.shape != (21600,43200) or source.crs is None
            or source.crs.to_epsg() != 4326
            or not source.transform.almost_equals(from_origin(-180,90,step,step))):
        raise ValueError("Expected global WGS84 30 arc-second Cao 1900 cropland fractions")
    step = 360/width
    return WarpedVRT(source,width=width,height=width//2,transform=from_origin(-180,90,step,step),
                     dtype="float32",nodata=np.nan,resampling=Resampling.average)


def worldcover_fraction_grid(source, width):
    step = 360/width
    if (source.crs is None or source.crs.to_epsg() != 4326
            or source.shape != (width//2,width)
            or not source.transform.almost_equals(from_origin(-180,90,step,step))
            or source.dtypes != ("uint8",)*len(LAND_COVER_CODES)
            or source.descriptions != tuple(map(str,LAND_COVER_CODES))
            or source.tags().get("product") != "ESA WorldCover 2021 v200"):
        raise ValueError("Expected ESA WorldCover class fractions on the Z7 grid")
    return source


def apply_worldcover_fractions(fractions, source, rect):
    native = np.moveaxis(read_wrapped_grid(source,rect,index=None),0,-1)
    total = native.sum(axis=-1,keepdims=True,dtype=np.float32)
    np.divide(native,total,out=fractions,where=total>0)


def z7_land_material(relief, cover, glaciers, width, rect, historical_cropland=None, dunes=None,
                     worldcover_fractions=None):
    """Derive Z7 land colors from measured relief and modern cover, on the global grid."""
    x0,top,x1,bottom = rect
    y0,y1 = max(0,top),min(width//2,bottom)
    lon,lat = grid(width, (x0-1,y0-1,x1+1,y1+1))
    lon = (lon+180)%360-180
    lat = np.clip(lat, -90+180/width, 90-180/width)
    z = relief.at(lon, lat)
    ground = np.maximum(z, -450)
    center = ground[1:-1,1:-1]
    north, south = ground[:-2,1:-1], ground[2:,1:-1]
    west, east = ground[1:-1,:-2], ground[1:-1,2:]
    step = M_PER_DEGREE*360/width
    meridian = np.maximum(.035, np.cos(np.radians(lat[1:-1,None])))
    dx = (east-west)/(2*step*meridian)
    dy = (south-north)/(2*step)
    slope = np.hypot(dx,dy)
    relief_span = np.maximum.reduce((center,north,south,west,east))-np.minimum.reduce((center,north,south,west,east))
    fractions = cover.fractions(lon[1:-1],lat[1:-1])
    if worldcover_fractions is not None:
        apply_worldcover_fractions(fractions,worldcover_fractions,(x0,y0,x1,y1))
    if historical_cropland is not None:
        apply_historical_cropland(fractions,read_wrapped_grid(historical_cropland,(x0,y0,x1,y1)))
    unknown, _, shrubs, grass, crop, _, bare, ice, mapped_water, wetland, _, moss = np.moveaxis(fractions,-1,0)
    color = fractions @ LAND_PALETTE

    # WorldCover groups rock, sand and sparsely vegetated ground. Use terrain form
    # to shade that class. The result is a material cue, not mapped lithology.
    rugged = np.maximum(smooth_weight(.14,.53,slope), smooth_weight(100,400,relief_span))
    exposed = np.array([.51,.47,.41],np.float32)
    dune_cover = 0
    if dunes is not None:
        # Resolve the composition of the bare-ground fraction only.
        # Mixed vegetation, snow and water retain their original cover fractions.
        dune_cover = dunes.material_weight((x0,y0,x1,y1))*bare
        sand = np.array([.775,.632,.433],np.float32)
        color += (sand-LAND_PALETTE[6])*dune_cover[...,None]
    color += (exposed-LAND_PALETTE[6])*((bare-dune_cover)*rugged)[...,None]
    # Retain tree, shrub and crop cover at any altitude. Rock influence on
    # transitional land is confined to steep, locally rugged terrain.
    outcrop = .40*smooth_weight(.37,.86,slope)*smooth_weight(150,390,relief_span)
    color += (exposed-color)*(outcrop*(unknown+grass+.5*shrubs+.55*moss))[...,None]
    concavity = (north+south+east+west)*.25-center
    lowland = smooth_weight(5,55,concavity)*(1-smooth_weight(.08,.24,slope))
    color += (np.array([.37,.44,.31],np.float32)-color)*(.21*lowland*(grass+crop+wetland))[...,None]

    ice_shape = rasterize(glaciers,width,(x0,y0,x1,y1))
    color += (LAND_PALETTE[7]-color)*np.maximum(0,ice_shape-ice)[...,None]
    directional = (1+.91*dx+.82*dy)/np.sqrt(1+2.1*slope**2)
    ridge_and_valley = np.clip(-concavity/180,-1,1)*smooth_weight(.10,.45,slope)
    light = np.clip(1+(.51+.10*rugged)*(directional-1)+.055*ridge_and_valley,.58,1.22)
    # A modern water classification cannot establish a historical shoreline.
    # Keep the accepted color where the modern data identify water.
    material = np.dstack((np.clip(color*light[...,None],0,1),np.clip(1-mapped_water,0,1)))
    if y0 != top or y1 != bottom:
        return np.pad(material,((y0-top,bottom-y1),(0,0),(0,0)),mode="edge")
    return material


def z6_land_material(fine_material, rect, width):
    """Area-average the same land albedo that is used to build Z7."""
    x0, top, x1, bottom = rect
    y0, y1 = max(0, top), min(width//2, bottom)
    fine = fine_material((2*x0, 2*y0, 2*x1, 2*y1))
    rgb = fine[..., :3]
    edit_weight = fine[..., 3:]
    shape = (y1-y0, 2, x1-x0, 2)
    weight = edit_weight.reshape(*shape, 1).mean(axis=(1, 3))
    weighted_rgb = (rgb*edit_weight).reshape(*shape, 3).mean(axis=(1, 3))
    color = np.divide(weighted_rgb, weight, out=np.zeros_like(weighted_rgb), where=weight>0)
    material = np.concatenate((color, weight), axis=-1)
    if y0 != top or y1 != bottom:
        return np.pad(material, ((y0-top, bottom-y1), (0, 0), (0, 0)), mode="edge")
    return material


def build_master(scratch, relief, cover, vectors, width):
    shape = (width//2, width)
    ground = np.memmap(scratch / "ground", mode="w+", shape=(*shape, 3), dtype=np.uint8)
    height = np.memmap(scratch / "height", mode="w+", shape=shape, dtype=np.float32)
    coast = np.memmap(scratch / "coast", mode="w+", shape=shape, dtype=np.uint8)
    water = np.memmap(scratch / "water", mode="w+", shape=shape, dtype=np.uint8)
    for y in range(0, shape[0], STRIPE):
        end = min(shape[0], y+STRIPE)
        rgb, z, land, river, _ = surface(relief, cover, vectors, width, (0, y, width, end), elevation_snow=True)
        ground[y:end] = np.clip(rgb*255+.5, 0, 255).astype(np.uint8)
        height[y:end] = z
        coast[y:end] = (land*255+.5).astype(np.uint8)
        water[y:end] = (river*255+.5).astype(np.uint8)

    # Classify open ocean over the complete globe, then render water. This prevents
    # bathymetry source discontinuities in enclosed seas from changing surface color.
    water_labels, _ = label(np.asarray(coast)<128)
    parent = np.arange(int(water_labels.max())+1)
    def representative(index):
        while parent[index] != index:
            index = parent[index]
        return index
    for west, east in zip(water_labels[:, 0], water_labels[:, -1]):
        if west and east:
            parent[representative(east)] = representative(west)
    ocean_root = representative(water_labels[shape[0]//2, int(width*5/12)])  # Equatorial Atlantic.
    open_ocean = np.array([i>0 and representative(i)==ocean_root for i in range(len(parent))])
    color = np.memmap(scratch / "rgba", mode="w+", shape=(*shape, 4), dtype=np.uint8)
    for y in range(0, shape[0], STRIPE):
        end = min(shape[0], y+STRIPE)
        land = np.asarray(coast[y:end], dtype=np.float32)/255
        depth = np.clip(-height[y:end]/5100, 0, 1)**.43
        ocean = np.array([.17,.32,.38],np.float32)-depth[...,None]*np.array([.092,.128,.122],np.float32)
        inland = np.array([.15,.29,.36],np.float32)
        ocean = np.where(open_ocean[water_labels[y:end], None], ocean, inland)
        color[y:end, :, :3] = np.clip(ground[y:end]*land[...,None] + 255*ocean*(1-land[...,None])+.5, 0, 255)
        color[y:end, :, 3] = np.maximum(255-coast[y:end], water[y:end])
    return color, height


def paths(root, level, x, y):
    prefix = root / str(level) / str(x) / str(y)
    return prefix.with_suffix(".bc7"), prefix.with_suffix(".i16")


def read_payload(path, dtype):
    return np.fromfile(path, dtype=dtype, offset=HEADER.size)


def tile_bytes(color, elevation, level, x, y, reduction):
    size = TILE+2*GUTTER
    samples = np.arange(reduction)
    ix = np.arange(x*TILE-GUTTER,(x+1)*TILE+GUTTER) % (color.shape[1]//reduction)
    iy = np.arange(y*TILE-GUTTER,(y+1)*TILE+GUTTER).clip(0,color.shape[0]//reduction-1)
    ix = (ix[:,None]*reduction+samples).ravel()
    iy = (iy[:,None]*reduction+samples).ravel()
    raster = color[iy[:,None],ix]
    raw = elevation[iy[:,None],ix]
    if reduction>1:
        raster = np.asarray(Image.fromarray(raster,"RGBX").resize((size,size),Image.Resampling.BOX))
        raw = raw.reshape(size,reduction,size,reduction).mean(axis=(1,3),dtype=np.float64)
    blocks = ispc_texcomp.compress_blocks_bc7(ispc_texcomp.RGBASurface(
        raster.tobytes(),size,size),ENCODER)
    return (HEADER.pack(COLOR_MAGIC,level,x,y)+blocks,
            HEADER.pack(HEIGHT_MAGIC,level,x,y)+np.rint(raw).astype("<i2").tobytes())


def verify_edges(output, level, nx, ny):
    dim = TILE+2*GUTTER
    files = lambda x,y: (read_payload(path,dtype).reshape(count,count) for path,dtype,count
                         in zip(paths(output,level,x,y),("V16","<i2"),(dim//4,dim)))
    checked = 0
    for y in range(ny):
        for x in range(nx):
            a = tuple(files(x,y))
            for vertical,b in [(False,files((x+1)%nx,y))] + ([(True,files(x,y+1))] if y+1<ny else []):
                for edge,first,second in zip((2*GUTTER//4,2*GUTTER),a,b):
                    if vertical:
                        first,second = first[-edge:,:],second[:edge,:]
                    else:
                        first,second = first[:,-edge:],second[:,:edge]
                    if not np.array_equal(first,second):
                        raise ValueError(f"Unequal Z{level} shared samples at ({x}, {y}), vertical={vertical}")
                checked += 1
    return checked


def parent_error(output, level, nx, ny):
    if level==0:
        return None
    size = TILE+2*GUTTER
    errors = []
    for y in range(ny//2):
        for x in range(nx//2):
            def core(z,i,j):
                arr = read_payload(paths(output,z,i,j)[1],"<i2").reshape(size,size)
                return arr[GUTTER:-GUTTER,GUTTER:-GUTTER].astype(np.float32)
            fine = np.block([[core(level,2*x+i,2*y+j) for i in range(2)] for j in range(2)])
            parent = core(level-1,x,y)
            difference = np.abs(parent-fine.reshape(TILE,2,TILE,2).mean(axis=(1,3)))
            errors.append(float(difference.max()))
    result = max(errors)
    if result>1:
        raise ValueError(f"Z{level} parent reduction differs by {result} m")
    return result


def verify_level(output, level):
    nx, ny = 2 << level, 1 << level
    size = TILE + 2 * GUTTER
    total = 0
    for x in range(nx):
        for y in range(ny):
            for path, magic, stride in zip(paths(output, level, x, y),
                                           (COLOR_MAGIC, HEIGHT_MAGIC), (1, 2)):
                length = path.stat().st_size
                with path.open("rb") as tile:
                    header = tile.read(HEADER.size)
                if (length != HEADER.size + size * size * stride
                        or header != HEADER.pack(magic, level, x, y)):
                    raise ValueError(f"Wrong tile version, coordinates or length: {path}")
                total += length
            if y in (0, ny - 1):
                height = read_payload(paths(output, level, x, y)[1], "<i2").reshape(size, size)
                if ((y == 0 and np.any(height[:GUTTER] != height[GUTTER]))
                        or (y == ny - 1 and np.any(height[-GUTTER:] != height[-GUTTER - 1]))):
                    raise ValueError(f"Unequal Z{level} polar height padding at ({x}, {y})")
    return dict(z=level, width=nx, height=ny, tiles=nx * ny, sample_degrees=360 / (nx * TILE),
                bytes=total, shared_edges=verify_edges(output, level, nx, ny),
                shared_height_error_m=0, parent_reduction_error_m=parent_error(output, level, nx, ny),
                status="generated_and_numeric_edges_verified")


def verify_package(output, layer=None, index_only=False, candidate=None):
    index = json.loads((output / "index.json").read_text(encoding="utf-8"))
    if index["version"] in (PACK_VERSION, COMPACT_VERSION):
        verify_packed(output, index, layer, index_only, candidate)
        return
    if layer is not None:
        raise ValueError("Independent layer checks require a QPK package")
    declared_grid = tuple(index[field] for field in
                          ("version", "tile_matrix_set", "axes", "origin", "tile_size", "gutter"))
    if declared_grid != (VERSION, "WorldCRS84Quad", "longitude,latitude", [-180, 90], TILE, GUTTER):
        raise ValueError("Wrong global terrain version or tile matrix")
    if len(index["levels"]) != MAX_LEVEL + 1:
        raise ValueError("Incomplete global terrain inventory")
    verify_topology(output, index)
    for level, declared in enumerate(index["levels"]):
        result = verify_level(output, level)
        if any(declared.get(key) != value for key, value in result.items()):
            raise ValueError(f"Z{level} inventory differs from stored resources")
        print(json.dumps(result), flush=True)


def verify_topology(output, index):
    topology = index["river_topology"]
    if (topology["file"] != "river-topology.u32" or topology["reaches"] != RIVER_REACHES
            or topology["unresolved_downstream_ids"] != 0
            or (output / "river-topology.u32").stat().st_size != RIVER_REACHES * 8):
        raise ValueError("Incomplete global river topology")
    reaches = np.fromfile(output / "river-topology.u32", dtype="<u4").reshape(-1, 2)
    ids, downstream = reaches.T
    if ids[0] == 0 or np.any(ids[1:] <= ids[:-1]):
        raise ValueError("Invalid global river reach identifiers")
    links = np.searchsorted(ids, downstream).clip(0, RIVER_REACHES - 1)
    if np.any((downstream != 0) & (ids[links] != downstream)):
        raise ValueError("Unresolved global river links")


def pack_path(root, level):
    return root / f"{level}.qpk"


class LevelPack:
    def __init__(self, file, level, version=PACK_VERSION):
        self.file, self.level = file, level
        self.version = version
        self.nx, self.ny = 2 << level, 1 << level
        self.decoder = None
        magic = COMPACT_MAGIC if version == COMPACT_VERSION else PACK_MAGIC
        expected = HEADER.pack(magic, level, self.nx, self.ny)
        if file.read(HEADER.size) != expected:
            raise ValueError(f"Wrong packed terrain header at Z{level}")
        size = (self.nx*self.ny+1)*8
        self.offsets = np.frombuffer(file.read(size), dtype="<u8")
        if (self.offsets.size != self.nx*self.ny+1 or self.offsets[0] != HEADER.size+size
                or np.any(self.offsets[1:] <= self.offsets[:-1])
                or int(self.offsets[-1]) != os.fstat(file.fileno()).st_size):
            raise ValueError(f"Wrong packed terrain offsets at Z{level}")

    def frame_sizes(self, x, y):
        i = y*self.nx+x
        start, end = map(int, self.offsets[i:i+2])
        if self.file.tell() != start:
            self.file.seek(start)
        z, tx, ty, size = PACK_RECORD.unpack(self.file.read(PACK_RECORD.size))
        height_size = end-start-PACK_RECORD.size-size
        if (z, tx, ty) != (self.level, x, y) or size <= 0 or height_size <= 0:
            raise ValueError(f"Wrong packed tile coordinates or size at Z{self.level}/{x}/{y}")
        return size, height_size

    def at(self, x, y):
        color_size, height_size = self.frame_sizes(x, y)
        color_frame, height_frame = self.file.read(color_size), self.file.read(height_size)
        dim = TILE+2*GUTTER
        if self.version == COMPACT_VERSION:
            if self.decoder is None:
                import zstandard
                self.decoder = zstandard.ZstdDecompressor()
            pixels = self.decoder.decompress(color_frame, max_output_size=dim**2)
            residual = self.decoder.decompress(height_frame, max_output_size=2*dim**2)
            height = restore_heights(residual, dim)
        else:
            pixels = zlib.decompress(color_frame)
            height = zlib.decompress(height_frame)
        return (np.frombuffer(pixels, dtype="V16").reshape(dim//4,dim//4),
                np.frombuffer(height, dtype="<i2").reshape(dim,dim))


def predict_heights(height):
    values = height.view("<u2")
    delta = values.copy()
    delta[:, 1:] -= values[:, :-1]
    delta[1:, :] -= delta[:-1, :].copy()
    zigzag = (delta << 1) ^ (np.uint16(0) - (delta >> 15))
    return zigzag.astype("<u2", copy=False).view("u1").reshape(-1, 2).T.tobytes()


def restore_heights(residual, dim):
    planes = np.frombuffer(residual, dtype="u1").reshape(2, dim*dim)
    zigzag = planes.T.copy().view("<u2").reshape(dim, dim)
    delta = (zigzag >> 1) ^ (np.uint16(0) - (zigzag & 1))
    np.cumsum(delta, axis=0, dtype=np.uint16, out=delta)
    np.cumsum(delta, axis=1, dtype=np.uint16, out=delta)
    return delta.astype("<u2", copy=False).tobytes()


def verify_packed_level(output, level, version=PACK_VERSION, reference=None, candidate=None, index_only=False):
    with (candidate or pack_path(output, level)).open("rb") as file:
        pack = LevelPack(file, level, version)
        if index_only:
            for y in range(pack.ny):
                for x in range(pack.nx):
                    pack.frame_sizes(x, y)
            return dict(z=level, width=pack.nx, height=pack.ny, tiles=pack.nx*pack.ny,
                        bytes=int(pack.offsets[-1]), status="global_index_verified")
        if level == 0:
            return packed_edges(pack, None, reference)
        with pack_path(output, level-1).open("rb") as parent:
            return packed_edges(pack, LevelPack(parent, level-1, version), reference)


def packed_edges(pack, parent, reference=None):
    nx, ny, level = pack.nx, pack.ny, pack.level
    checked, max_error = 0, None if parent is None else 0.0
    overlap = (2*GUTTER//4, 2*GUTTER)
    previous = [None]*nx
    for y in range(ny):
        if parent is not None and y % 2 == 0:
            coarse = [parent.at(x, y//2)[1][GUTTER:-GUTTER,GUTTER:-GUTTER] for x in range(nx//2)]
        west = None
        for x in range(nx):
            tile = pack.at(x, y)
            if reference is not None and any(
                    not np.array_equal(actual, original)
                    for actual, original in zip(tile, reference.at(x, y))):
                raise ValueError(f"Changed BC7 blocks or elevation at Z{level}/{x}/{y}")
            if y > 0:
                if any(not np.array_equal(s, t[:d,:]) for s,t,d in zip(previous[x],tile,overlap)):
                    raise ValueError(f"Unequal Z{level} north edge at ({x},{y})")
                checked += 1
            previous[x] = tuple(t[-d:,:].copy() for t,d in zip(tile,overlap))
            left = tuple(t[:,:d] for t,d in zip(tile,overlap))
            if x == 0:
                first = left
            else:
                if any(not np.array_equal(a,b) for a,b in zip(west,left)):
                    raise ValueError(f"Unequal Z{level} west edge at ({x},{y})")
                checked += 1
            west = tuple(t[:,-d:] for t,d in zip(tile,overlap))
            height = tile[1]
            if ((y == 0 and np.any(height[:GUTTER] != height[GUTTER]))
                    or (y == ny-1 and np.any(height[-GUTTER:] != height[-GUTTER-1]))):
                raise ValueError(f"Unequal Z{level} polar padding at ({x},{y})")
            if parent is not None:
                half = TILE//2
                i, j = x%2*half, y%2*half
                fine = height[GUTTER:-GUTTER,GUTTER:-GUTTER].reshape(half,2,half,2)
                delta = np.abs(coarse[x//2][j:j+half,i:i+half]-fine.mean(axis=(1,3),dtype=np.float32))
                max_error = max(max_error, float(delta.max()))
        if any(not np.array_equal(a,b) for a,b in zip(west,first)):
            raise ValueError(f"Unequal Z{level} antimeridian edge at row {y}")
        checked += 1
    if max_error is not None and max_error > 1:
        raise ValueError(f"Z{level} parent reduction differs by {max_error} m")
    return dict(z=level, width=nx, height=ny, tiles=nx*ny, sample_degrees=360/(nx*TILE),
                bytes=int(pack.offsets[-1]), shared_edges=checked, shared_height_error_m=0,
                parent_reduction_error_m=max_error, status="generated_and_numeric_edges_verified")


def verify_packed(output, manifest, layer=None, index_only=False, candidate=None):
    grid = tuple(manifest[key] for key in ("tile_matrix_set", "axes", "origin", "tile_size", "gutter"))
    if grid != ("WorldCRS84Quad", "longitude,latitude", [-180,90], TILE, GUTTER):
        raise ValueError("Wrong packed terrain grid")
    version = manifest["version"]
    levels = len(manifest["levels"])
    if not 6 <= levels <= PACK_MAX_LEVEL+1:
        raise ValueError("Incomplete packed terrain inventory")
    if version == COMPACT_VERSION and (
            levels != PACK_MAX_LEVEL+1 or manifest.get("compression") != COMPACT_FORMAT):
        raise ValueError("Wrong compact terrain compression or level count")
    if layer is None:
        verify_topology(output, manifest)
    elif layer >= levels:
        raise ValueError(f"Z{layer} is absent from the package")
    for level in range(levels) if layer is None else (layer,):
        declared = manifest["levels"][level]
        result = verify_packed_level(output, level, version, candidate=candidate, index_only=index_only)
        if any(declared.get(key) != value for key,value in result.items()
               if not (candidate is not None and key in ("bytes", "parent_reduction_error_m"))
               and not (index_only and key == "status")):
            raise ValueError(f"Z{level} inventory differs from stored resources")
        print(json.dumps(result), flush=True)


def build(sources, natural_earth, output, *, scratch=None):
    relief = global_relief(sources / "gmt-1m-nju.grd")
    cover = LandCover(sources / "worldcover")
    vectors = {key: STRtree(physical_shapes(natural_earth,key)) for key in
               ("land","lakes","glaciated_areas")}
    print("Preparing the global river network",flush=True)
    with TemporaryDirectory(dir=output.parent) as folder:
        river_tree, reaches, displayed = hydrography(sources/"HydroRIVERS_v10_shp.zip",output,Path(folder))
        vectors["rivers_lake_centerlines"] = river_tree
    print(f"HydroRIVERS {reaches} reaches, {displayed} rasterized",flush=True)
    levels = []
    with staging_directory(output.parent, scratch) as folder:
        print("Building the global mother raster", flush=True)
        color, height = build_master(Path(folder),relief,cover,vectors,8192*2)
        for level in range(MAX_LEVEL + 1):
            nx, ny = 2<<level, 1<<level
            reduction = 2 << (MAX_LEVEL - level)
            for x in range(nx):
                (output/str(level)/str(x)).mkdir(parents=True)
                for y in range(ny):
                    render_path, height_path = paths(output,level,x,y)
                    pixels, metres = tile_bytes(color,height,level,x,y,reduction)
                    render_path.write_bytes(pixels)
                    height_path.write_bytes(metres)
            result = verify_level(output,level)
            levels.append(result)
            print(json.dumps(result), flush=True)
        del color, height
    manifest = {
        "version": VERSION, "tile_matrix_set": "WorldCRS84Quad", "axes": "longitude,latitude",
        "origin": [-180,90], "tile_size": TILE, "gutter": GUTTER, "levels": levels,
        "render": "z/x/y.bc7, RGBA unorm, alpha is water coverage",
        "height": "z/x/y.i16, little endian meters, shared source vertical reference",
        "tile_header": "8-byte format identifier followed by little-endian uint32 Z, X, Y",
        "sources": {"relief":"SRTM15+ V2.1, global GMT 60 arc second, sea-level reference",
                    "land_cover":"ESA WorldCover 2021, reduced source cache; modern reference",
                    "coasts_lakes_glaciers":"Natural Earth 1:10m; modern reference",
                    "rivers":"HydroRIVERS v1.0 (Lehner and Grill 2013); modern reference, https://www.hydrosheds.org/products/hydrorivers"},
        "land_cover_license": {"license":"CC BY 4.0", "url":"https://doi.org/10.5281/zenodo.7254221",
            "attribution":"© ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium"},
        "gaps": ["No global 1900 land-cover or reservoir reconstruction",
                 "HydroRIVERS resolution is coarser north of 60 degrees; streams below its source thresholds and Antarctic ice drainage are not represented",
                 "Z5 and higher not generated"],
        "river_topology": {"file":"river-topology.u32","reaches":reaches,"rasterized_reaches":displayed,
            "format":"uint32 little endian pairs (HYRIV_ID, NEXT_DOWN), sorted by ID; terminal NEXT_DOWN=0",
            "unresolved_downstream_ids":0},
    }
    (output/"index.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")


def packed_rasters(scratch, level, mode):
    width = 2*TILE << level
    shape = (width//2, width)
    return (np.memmap(scratch / f"{level}.rgba", mode=mode, shape=(*shape,4), dtype=np.uint8),
            np.memmap(scratch / f"{level}.height", mode=mode, shape=shape, dtype=np.float32))


def inland_holes(land_shapes):
    return [Polygon(ring) for geom in land_shapes
            for polygon in (geom.geoms if geom.geom_type == "MultiPolygon" else [geom])
            for ring in polygon.interiors]


def packed_ocean_color(z):
    depth = np.clip(-z/5100, 0, 1)**.43
    return np.array([.17,.32,.38],np.float32)-depth[...,None]*np.array([.092,.128,.122],np.float32)


def shade_packed_water(ground, z, land, lake, enclosed):
    sea = np.maximum(0, (1-land)*(1-lake)-enclosed)
    ocean = packed_ocean_color(z)
    inland = np.array([.15,.29,.36],np.float32)
    ground *= land[...,None]
    ground += ocean*sea[...,None] + inland*np.maximum(0,1-land-sea)[...,None]
    return np.clip(ground*255+.5,0,255).astype(np.uint8)


def build_packed_mother(scratch, sources, natural_earth, output):
    cover = LandCover(sources / "worldcover", native=True)
    vectors = {key: STRtree(physical_shapes(natural_earth,key)) for key in
               ("land", "lakes", "glaciated_areas")}
    enclosed = STRtree(inland_holes(vectors["land"].geometries))
    print("Preparing the global river network", flush=True)
    with TemporaryDirectory(dir=scratch) as unpacked:
        river_tree, reaches, displayed = hydrography(sources / "HydroRIVERS_v10_shp.zip", output, Path(unpacked))
        vectors["rivers_lake_centerlines"] = river_tree
    manifest = {
        "version": PACK_VERSION, "tile_matrix_set": "WorldCRS84Quad", "axes": "longitude,latitude",
        "origin": [-180,90], "tile_size": TILE, "gutter": GUTTER, "levels": [],
        "render": "row-major Z.qpk, DEFLATE-wrapped BC7 RGBA unorm, alpha is water coverage",
        "height": "DEFLATE-wrapped little endian signed metres from one vertical reference",
        "sources": {"relief": {"description": "", "sample_arc_seconds": 15, "url": DEM_URL,
                               "vertical_reference": "SRTM15+ sea-level reference"},
                    "land_cover": "ESA WorldCover 2021 reduced cache at 562 cells per 3 degrees; modern reference",
                    "coasts_lakes_glaciers": "Natural Earth 1:10m coastlines, lakes and glaciation; modern reference",
                     "permanent_snow_and_ice": "ESA WorldCover 2021 v200 class 70 and Natural Earth 1:10m glaciated areas",
                    "rivers": "HydroRIVERS v1.0; modern reference, https://www.hydrosheds.org/products/hydrorivers"},
        "land_cover_license": {"license": "CC BY 4.0", "url": "https://doi.org/10.5281/zenodo.7254221",
                                "attribution": "© ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium"},
        "river_topology": {"file": "river-topology.u32", "reaches": reaches,
                           "rasterized_reaches": displayed, "unresolved_downstream_ids": 0,
                           "format": "uint32 little endian pairs (HYRIV_ID, NEXT_DOWN), sorted by ID; terminal NEXT_DOWN=0"},
        "gaps": ["No global reconstruction of 1900 land cover or reservoirs",
                 "Bathymetry includes gravity-predicted estimates; 15 arc seconds is grid spacing",
                 "HydroRIVERS resolution is coarser north of 60 degrees; low-flow streams and Antarctic ice drainage are not represented"],
    }
    verify_topology(output, manifest)
    color, height = packed_rasters(scratch, PACK_MAX_LEVEL, "w+")
    rows, width = height.shape
    stripe_rows = 96
    with rasterio.Env(GDAL_CACHEMAX=256*2**20), rasterio.open(sources / DEM_15S) as source:
        relief = Relief15s(source)
        manifest["sources"]["relief"]["description"] = relief.description
        for y in range(0, rows, stripe_rows):
            end = min(rows, y+stripe_rows)
            rect = (0,y,width,end)
            ground, z, land, inland_water, lake = surface(relief, cover, vectors, width, rect, elevation_snow=False)
            color[y:end,:,:3] = shade_packed_water(ground,z,land,lake,rasterize(enclosed,width,rect))
            color[y:end,:,3] = np.rint(255*np.maximum(1-land,inland_water)).astype(np.uint8)
            height[y:end] = z
            if y == 0 or (y//stripe_rows)%16 == 15 or end == rows:
                print(f"Global mother raster {end}/{rows} rows", flush=True)
    color.flush()
    height.flush()
    del color, height
    reduce_packed_mother(scratch)
    return manifest


def reduce_packed_mother(scratch):
    for level in reversed(range(PACK_MAX_LEVEL)):
        source_color, source_height = packed_rasters(scratch, level+1, "r")
        color, height = packed_rasters(scratch, level, "w+")
        for y in range(0, height.shape[0], STRIPE):
            end = min(y+STRIPE,height.shape[0])
            c, h = source_color[2*y:2*end], source_height[2*y:2*end]
            sums = c[::2,::2].astype(np.uint16) + c[1::2,::2] + c[::2,1::2] + c[1::2,1::2]
            color[y:end] = (sums+2)//4
            height[y:end] = .25*(h[::2,::2]+h[1::2,::2]+h[::2,1::2]+h[1::2,1::2])
        color.flush()
        height.flush()
        del color, height, source_color, source_height, c, h


def write_level_records(path, level, magic, records):
    nx, ny = 2 << level, 1 << level
    offsets = np.zeros(nx*ny+1, dtype="<u8")
    with path.open("wb") as file:
        file.write(HEADER.pack(magic,level,nx,ny))
        file.write(offsets.tobytes())
        for i, record in enumerate(records):
            offsets[i] = file.tell()
            file.write(record)
        offsets[-1] = file.tell()
        file.seek(HEADER.size)
        file.write(offsets.tobytes())


def ice_shelf_polygons(source, grounding_distance=10_000):
    data = json.loads(source.read_text(encoding="utf-8"))
    if (data.get("spatialReference", {}).get("wkid") != 3031
            or data.get("geometryType") != "esriGeometryPolygon"
            or data.get("exceededTransferLimit")):
        raise ValueError("Expected a complete SCAR ADD polygon extract in EPSG:3031")
    floating, grounded = [], []
    for feature in data["features"]:
        surface_type = feature["attributes"]["surface"]
        if surface_type not in ("ice shelf", "ice tongue", "land", "rumple"):
            continue
        points, parts = [], []
        for ring in feature["geometry"]["rings"]:
            parts.append(len(points))
            points.extend(ring)
        polygon = shape(shapefile.Shape(shapeType=5, points=points, parts=parts).__geo_interface__)
        if polygon.is_empty:
            raise ValueError(f"Invalid SCAR ADD polygon {feature['attributes']['FID']}")
        if not polygon.is_valid:
            polygon = make_valid(polygon)
        group = grounded if surface_type in ("land", "rumple") else floating
        group.append(polygon)
    if not floating or not grounded:
        raise ValueError("Expected both floating ice and grounded coastline from SCAR ADD")
    land = STRtree(grounded)
    polygons = floating.copy()
    for shelf in floating:
        # Old Natural Earth land and newer ADD shelves do not share the same
        # grounding line. Reconcile mapped ground near it without growing the ice
        # out into water or changing the underlying physical mask.
        vicinity = shelf.buffer(grounding_distance)
        for index in land.query(vicinity, predicate="intersects"):
            segment = clip_by_rect(grounded[index], *vicinity.bounds)
            ground = make_valid(segment).intersection(vicinity)
            if ground.area:
                polygons.append(ground)
    for polygon in polygons:
        prepare(polygon)
    return STRtree(polygons)


def floating_ice_coverage(polygons, projection, nx, ny, x, y, samples=2):
    step = 360/(nx*TILE)
    columns = np.arange(x*TILE-GUTTER, (x+1)*TILE+GUTTER)
    rows = np.arange(y*TILE-GUTTER, (y+1)*TILE+GUTTER).clip(0, ny*TILE-1)
    west, east = columns[[0,-1]]*step-180
    north, south = 90-rows[[0,-1]]*step
    if south-step > -60:
        return None
    bounds = projection.transform_bounds(west, south-step, east+step, north)
    footprint = box(*bounds)
    selected = polygons.geometries.take(polygons.query(footprint))
    if not len(selected):
        return None
    if samples > 2 and any(polygon.covers(footprint.buffer(2)) for polygon in selected):
        return np.full((len(rows),len(columns)), samples*samples, dtype=np.uint8)
    coverage = np.zeros((len(rows),len(columns)), dtype=np.uint8)
    offsets = (np.arange(samples)+.5)/samples
    for dy in offsets:
        for dx in offsets:
            lon = ((columns+dx) % (nx*TILE))*step-180
            lat = 90-(rows+dy)*step
            lon, lat = np.meshgrid(lon,lat)
            east, north = projection.transform(lon,lat)
            ice = np.zeros(coverage.shape, dtype=bool)
            for polygon in selected:
                ice |= intersects_xy(polygon, east, north)
            coverage += ice
    return coverage if coverage.any() else None


def recolor_bc7_preserving_alpha(original, pixels, opaque_encoder):
    """Fit a BC7 color block while preserving each of its decoded alpha samples."""
    if np.all(pixels[...,3] == 255):
        opaque = ispc_texcomp.compress_blocks_bc7(
            ispc_texcomp.RGBASurface(pixels.tobytes(), 4, 4), opaque_encoder)
        if (opaque[0] & 0b1111111) == 0b1000000:
            # Mode 6 shares endpoint p-bits with alpha. Force both alpha endpoints
            # to 255, which can adjust the RGB endpoint low bits by one step.
            alpha_endpoints_and_pbits = 0xFFFF << 49
            bits = int.from_bytes(opaque, "little") | alpha_endpoints_and_pbits
            return bits.to_bytes(16, "little")
        return opaque

    bits = int.from_bytes(original, "little")
    mode = (bits & -bits).bit_length() - 1
    # First endpoint bit, width of one endpoint per encoded channel, endpoints per channel.
    start, widths, count = {
        4: (8, (5,5,5,6), 2), 5: (8, (7,7,7,8), 2),
        6: (7, (7,7,7,7), 2), 7: (14, (5,5,5,5), 4),
    }[mode]
    fields = []
    for width in widths:
        fields.append((start, width))
        start += width*count
    if mode in (4,5):
        rotation = (bits >> (mode+1)) & 3
        if rotation:
            fields[rotation-1], fields[3] = fields[3], fields[rotation-1]

    # Probe the original interpolation using one maximum endpoint at a time.
    # The probes clear p-bits; the final block keeps the original p-bits,
    # selectors, subsets, rotation and physical alpha endpoints.
    has_pbits = mode in (6,7)
    probe_base = bits
    if has_pbits:
        probe_base &= ~(((1 << count)-1) << start)
    for offset, width in fields[:3]:
        probe_base &= ~(((1 << (count*width))-1) << offset)
    scales = np.array([255-(1 << (7-width)) if has_pbits else 255 for _,width in fields[:3]])
    weights = np.empty((16,3,count))
    for endpoint in range(count):
        probe = probe_base
        for offset, width in fields[:3]:
            probe |= ((1 << width)-1) << (offset+width*endpoint)
        rgba = Image.frombytes("RGBA", (4,4), probe.to_bytes(16,"little"), "bcn", (7,"BC7"))
        weights[:,:,endpoint] = np.asarray(rgba).reshape(16,4)[:,:3]/scales

    target = pixels.reshape(16,4)
    for channel, (offset, width) in enumerate(fields[:3]):
        endpoints = np.linalg.lstsq(weights[:,channel], target[:,channel], rcond=None)[0]
        mask = (1 << width)-1
        for endpoint, value in enumerate(endpoints):
            if has_pbits:
                pbit = (bits >> (start+endpoint)) & 1
                value = (value*((1 << (width+1))-1)/255-pbit)/2
            else:
                value *= mask/255
            field = offset+width*endpoint
            bits = (bits & ~(mask << field)) | (max(0,min(mask,round(value))) << field)
    return bits.to_bytes(16,"little")


def write_ice_shelf_candidate(original, source, destination, *, refine_edges=False, scratch=None):
    """Apply SCAR ADD floating-ice color to a complete Z6 or Z7 QPK."""
    from pyproj import Transformer
    import zstandard

    if destination.exists():
        raise FileExistsError(destination)
    # The old 10 km clip truncates mapped ground at Ronne and Amery.
    # Only the SCAR ground polygons can extend coverage into this collar.
    polygons = ice_shelf_polygons(source, grounding_distance=15_000 if refine_edges else 10_000)
    projection = Transformer.from_crs(4326, 3031, always_xy=True)
    decode = zstandard.ZstdDecompressor()
    encode = zstandard.ZstdCompressor(level=COMPACT_STRENGTH)
    dim = TILE+2*GUTTER
    block_dim = dim//4
    samples = 4 if refine_edges else 2
    ice_color = np.array([215,226,229], dtype=np.float32)
    changed = 0
    refitted_alpha_blocks = 0

    with original.open("rb") as file:
        header = file.read(HEADER.size)
        if len(header) != HEADER.size:
            raise ValueError("Incomplete packed terrain header")
        _, level, _, _ = HEADER.unpack(header)
        if level not in (6, 7):
            raise ValueError("Floating-ice candidates require a Z6 or Z7 QPK")
        if refine_edges and level != 7:
            raise ValueError("Ice-shelf edge refinement requires a Z7 QPK")
        file.seek(0)
        pack = LevelPack(file, level, COMPACT_VERSION)
        preserve_alpha = level == 6 or refine_edges
        opaque_encoder = ispc_texcomp.BC7EncSettings.from_profile("fast") if preserve_alpha else None

        def records():
            nonlocal changed, refitted_alpha_blocks
            for y in range(pack.ny):
                for x in range(pack.nx):
                    color_size, height_size = pack.frame_sizes(x,y)
                    color = file.read(color_size)
                    height = file.read(height_size)
                    coverage = floating_ice_coverage(polygons, projection, pack.nx, pack.ny, x, y, samples)
                    if coverage is not None:
                        raw = decode.decompress(color, max_output_size=dim**2)
                        pixels = np.array(Image.frombytes("RGBA", (dim,dim), raw, "bcn", (7,"BC7")))
                        amount = coverage.astype(np.float32)*pixels[...,3]/(samples*samples*255)
                        if amount.any():
                            rgb = pixels[...,:3]
                            water_rgb = rgb
                            if refine_edges:
                                # The original shore pixels already combine sea and ground.
                                # Replace their water contribution without tinting the ground again.
                                residual = decode.decompress(height, max_output_size=dim**2*2)
                                z = np.frombuffer(restore_heights(residual, dim), dtype="<i2").reshape(dim,dim)
                                water_rgb = np.where(pixels[...,3:4] == 255, rgb, packed_ocean_color(z)*255)
                            rgb[:] = np.rint(np.clip(rgb+(ice_color-water_rgb)*amount[...,None], 0, 255)).astype(np.uint8)
                            bc7 = ispc_texcomp.compress_blocks_bc7(
                                ispc_texcomp.RGBASurface(pixels.tobytes(), dim, dim), ENCODER)
                            # Reuse the original blocks wherever no pixel changed. Padded edge
                            # blocks use the same global samples and stay identical across tiles.
                            updated = amount.reshape(block_dim,4,block_dim,4).any(axis=(1,3)).ravel()
                            blocks = np.frombuffer(raw,dtype="V16").copy()
                            blocks[updated] = np.frombuffer(bc7,dtype="V16")[updated]
                            if preserve_alpha:
                                decoded = np.asarray(Image.frombytes("RGBA", (dim, dim), bc7, "bcn", (7, "BC7")))
                                alpha_changed = (decoded[...,3] != pixels[...,3])
                                alpha_changed = alpha_changed.reshape(block_dim,4,block_dim,4).any(axis=(1,3)).ravel()
                                for index in np.flatnonzero(updated & alpha_changed):
                                    row, col = divmod(int(index), block_dim)
                                    target = pixels[4*row:4*(row+1),4*col:4*(col+1)]
                                    blocks[index] = np.void(recolor_bc7_preserving_alpha(
                                        raw[16*index:16*(index+1)], target, opaque_encoder))
                                    refitted_alpha_blocks += 1
                                decoded = Image.frombytes("RGBA", (dim,dim), blocks.tobytes(), "bcn", (7,"BC7"))
                                if not np.array_equal(np.asarray(decoded)[...,3], pixels[...,3]):
                                    raise ValueError(f"Changed decoded water coverage at Z{level}/{x}/{y}")
                            recolored = encode.compress(blocks.tobytes())
                            changed += int((level == 7 and not refine_edges) or recolored != color)
                            color = recolored
                    yield PACK_RECORD.pack(pack.level,x,y,len(color))+color+height

        destination.parent.mkdir(parents=True, exist_ok=True)
        with staging_directory(destination.parent, scratch) as folder:
            staged = Path(folder)/destination.name
            write_level_records(staged, pack.level, COMPACT_MAGIC, records())
            if not changed:
                raise ValueError(f"No Z{level} tiles changed")
            staged.rename(destination)
    print(f"Z{level}: {pack.nx*pack.ny} tiles, {changed} color records updated, original height frames preserved")
    if preserve_alpha:
        print(f"Z{level}: {refitted_alpha_blocks} BC7 blocks refitted with exact decoded water coverage")


def outlet_corridors(source):
    """Buffer documented outlet alignments in metres and wrap them on the global grid."""
    from pyproj import Transformer
    from shapely import transform

    entries = json.loads(source.read_text(encoding="utf-8"))
    if entries.get("type") != "FeatureCollection" or not entries.get("features"):
        raise ValueError("Expected documented outlet features in WGS84")
    polygons = []
    for feature in entries["features"]:
        line = shape(feature["geometry"])
        props = feature["properties"]
        half_width = float(props["half_width_metres"])
        if (line.geom_type != "LineString" or line.is_empty or not line.is_valid
                or not np.isfinite(half_width) or half_width <= 0):
            raise ValueError(f"Invalid outlet geometry or width for {props.get('name')}")
        points = np.array(line.coords)
        if (points.shape[1] != 2 or not np.isfinite(points).all() or np.any(np.abs(points[:,0]) > 180)
                or np.any(np.abs(points[:,1]) >= 90)):
            raise ValueError("Outlet coordinates must be WGS84 longitude and latitude")
        points[:,0] = np.degrees(np.unwrap(np.radians(points[:,0])))
        lon, lat = points[0]
        local = f"+proj=aeqd +lon_0={lon} +lat_0={lat} +ellps=WGS84 +units=m"
        forward = Transformer.from_crs(4326, local, always_xy=True, force_over=True)
        reverse = Transformer.from_crs(local, 4326, always_xy=True, force_over=True)
        metric = transform(LineString(points), forward.transform, interleaved=False)
        corridor = transform(metric.buffer(half_width), reverse.transform, interleaved=False)
        polygons.append(corridor)
        if corridor.bounds[0] < -180:
            polygons.append(translate(corridor, xoff=360))
        if corridor.bounds[2] > 180:
            polygons.append(translate(corridor, xoff=-360))
    return STRtree(polygons)


def outlet_water_coverage(corridors, land, width, rect):
    coverage = rasterize(corridors, width, rect, samples=4)
    if not coverage.any():
        return coverage
    x0, y0, x1, y1 = rect
    land_cover = rasterize(land, width, rect)
    if x0 < 0:
        land_cover[:,:-x0] = rasterize(land, width, (width+x0, y0, width, y1))
    if x1 > width:
        land_cover[:,width-x0:] = rasterize(land, width, (0, y0, x1-width, y1))
    if y0 < 0:
        coverage[:-y0] = coverage[-y0]
        land_cover[:-y0] = land_cover[-y0]
    if y1 > width//2:
        coverage[width//2-y0:] = coverage[width//2-y0-1]
        land_cover[width//2-y0:] = land_cover[width//2-y0-1]
    inland = coverage * land_cover * RIVER_OPACITY
    # Keep the mapped ocean fraction while applying river material to the land.
    return np.where(inland > 0, (1-land_cover) + inland, 0)


def inland_water_polygons(source):
    entries = json.loads(source.read_text(encoding="utf-8"))
    if entries.get("type") != "FeatureCollection" or not entries.get("features"):
        raise ValueError("Expected documented inland water features in WGS84")
    polygons = []
    gutter_degrees = 360 * GUTTER / ((2*TILE) << PACK_MAX_LEVEL)
    for feature in entries["features"]:
        geom = shape(feature["geometry"])
        name = feature["properties"].get("name")
        if geom.geom_type not in ("Polygon", "MultiPolygon") or geom.is_empty or not geom.is_valid:
            raise ValueError(f"Invalid inland water polygon for {name}")
        parts = geom.geoms if geom.geom_type == "MultiPolygon" else (geom,)
        for polygon in parts:
            west, south, east, north = polygon.bounds
            if not (-180 <= west < east <= 180 and -90 < south < north < 90 and east-west < 180):
                raise ValueError(f"Expected WGS84 inland water split at the antimeridian for {name}")
            polygons.append(polygon)
            # The QPK gutter includes samples from the other side of the antimeridian.
            if west < -180 + gutter_degrees:
                polygons.append(translate(polygon, xoff=360))
            if east > 180 - gutter_degrees:
                polygons.append(translate(polygon, xoff=-360))
    return STRtree(polygons)


def inland_water_coverage(lakes, width, rect):
    coverage = rasterize(lakes, width, rect, samples=4)
    y0, y1 = rect[1], rect[3]
    if y0 < 0 or y1 > width//2:
        rows = np.clip(np.arange(y0, y1), 0, width//2-1) - y0
        return coverage[rows]
    return coverage


def water_color_frame(color, coverage, decode, encode):
    if not coverage.any():
        return color
    dim = TILE + 2*GUTTER
    raw = decode.decompress(color, max_output_size=dim**2)
    pixels = np.array(Image.frombytes("RGBA", (dim, dim), raw, "bcn", (7, "BC7")))
    alpha = pixels[...,3].astype(np.float32) / 255
    target = np.rint(np.maximum(coverage, alpha)*255).astype(np.uint8)
    affected = target > pixels[...,3]
    if not affected.any():
        return color
    addition = (target[affected]/255 - alpha[affected]) / (1 - alpha[affected])
    before = pixels[affected,:3].astype(np.float32)
    pixels[affected,:3] = np.rint(before + (RIVER_COLOR*255 - before)*addition[:,None])
    pixels[...,3] = target

    rendered = ispc_texcomp.compress_blocks_bc7(
        ispc_texcomp.RGBASurface(pixels.tobytes(), dim, dim), ENCODER)
    update = affected.reshape(dim//4, 4, dim//4, 4).any(axis=(1, 3)).ravel()
    blocks = np.frombuffer(raw, dtype="V16").copy()
    blocks[update] = np.frombuffer(rendered, dtype="V16")[update]
    return encode.compress(blocks.tobytes())


def write_water_candidate(original, destination, footprints, coverage_at, *, scratch=None):
    """Apply one water inventory to the complete Z7 QPK without rebuilding elevations."""
    import zstandard

    if destination.exists():
        raise FileExistsError(destination)
    decode = zstandard.ZstdDecompressor()
    encode = zstandard.ZstdCompressor(level=COMPACT_STRENGTH)
    changed = []

    with original.open("rb") as file:
        pack = LevelPack(file, PACK_MAX_LEVEL, COMPACT_VERSION)
        width = pack.nx*TILE
        step = 360/width

        def records():
            for y in range(pack.ny):
                for x in range(pack.nx):
                    color_size, height_size = pack.frame_sizes(x, y)
                    color, height = file.read(color_size), file.read(height_size)
                    rect = (x*TILE-GUTTER, y*TILE-GUTTER,
                            (x+1)*TILE+GUTTER, (y+1)*TILE+GUTTER)
                    x0, y0, x1, y1 = rect
                    bounds = box(x0*step-180, 90-y1*step, x1*step-180, 90-y0*step)
                    if footprints.query(bounds, predicate="intersects").size:
                        updated = water_color_frame(color, coverage_at(width, rect), decode, encode)
                        if updated != color:
                            changed.append((x, y))
                            color = updated
                    yield PACK_RECORD.pack(pack.level, x, y, len(color)) + color + height

        destination.parent.mkdir(parents=True, exist_ok=True)
        with staging_directory(destination.parent, scratch) as folder:
            staged = Path(folder)/destination.name
            write_level_records(staged, pack.level, COMPACT_MAGIC, records())
            if not changed:
                raise ValueError("No Z7 water coverage changed")
            staged.rename(destination)
    print(f"Z7: {pack.nx*pack.ny} tiles, updated color records {changed}, original height frames preserved")


def write_outlet_candidate(original, source, natural_earth, destination, *, scratch=None):
    corridors = outlet_corridors(source)
    land = STRtree([geom if geom.is_valid else make_valid(geom)
                    for geom in physical_shapes(natural_earth, "land")])
    coverage_at = partial(outlet_water_coverage, corridors, land)
    write_water_candidate(original, destination, corridors, coverage_at, scratch=scratch)


def write_inland_water_candidate(original, source, destination, *, scratch=None):
    lakes = inland_water_polygons(source)
    coverage_at = partial(inland_water_coverage, lakes)
    write_water_candidate(original, destination, lakes, coverage_at, scratch=scratch)


def fractional_edges(edges, length):
    locations = np.clip(edges,0,length)
    pixel = np.minimum(np.floor(locations).astype(np.intp),length-1)
    return pixel, locations-pixel


def sand_coverage(tile, eastings, northings):
    # Integrate only the source cells that overlap this target window.
    x = (eastings-tile.bounds.left)/30
    y = (tile.bounds.top-northings)/30
    left, right = max(0, int(np.floor(x[0]))), min(tile.width, int(np.ceil(x[-1])))
    top, bottom = max(0, int(np.floor(y[0]))), min(tile.height, int(np.ceil(y[-1])))
    width, length = right-left, bottom-top
    if width <= 0 or length <= 0:
        return None
    columns, column_fraction = fractional_edges(x-left, width)
    rows, row_fraction = fractional_edges(y-top, length)
    horizontal = np.zeros((length,len(columns)-1),dtype=np.float32)
    for start in range(0,length,STRIPE):
        height = min(STRIPE,length-start)
        classes = tile.read(1, window=Window(left,top+start,width,height), masked=True).filled(255)
        # ClassificationScheme.xlsx: 0–8 are dunes or sand sheets, 10 is
        # parabolic dunes. Class 9 is non-sand ground.
        mapped = (classes <= 8) | (classes == 10)
        if mapped.any():
            counts = np.zeros((height,width+1),dtype=np.uint16)
            np.cumsum(mapped,axis=1,dtype=np.uint16,out=counts[:,1:])
            at_edges = counts[:,columns]+mapped[:,columns]*column_fraction
            horizontal[start:start+height] = np.diff(at_edges,axis=1)
    if not horizontal.any():
        return None
    counts = np.zeros((length+1,horizontal.shape[1]),dtype=np.float64)
    np.cumsum(horizontal,axis=0,dtype=np.float64,out=counts[1:])
    at_edges = counts[rows]+horizontal[rows]*row_fraction[:,None]
    return np.diff(at_edges,axis=0)/(np.diff(y)[:,None]*np.diff(x))


class DuneCoverage:
    """GSDP30 v1 Landsat classification, read in source windows."""
    def __init__(self, archive, width):
        self.width = width
        self.members = sorted(name for name in archive.namelist() if name.endswith(".tif"))
        if len(self.members) != 331:
            raise ValueError("Expected the 331 GeoTIFFs of GSDP30 version 1")
        bounds = []
        for member in self.members:
            with rasterio.MemoryFile(archive.read(member)) as memory, memory.open() as tile:
                expected = from_origin(tile.bounds.left, tile.bounds.top, 30, 30)
                if (tile.crs is None or tile.crs.to_epsg() != 3857 or tile.shape != (15360,15360)
                        or tile.transform != expected or tile.nodata != 255):
                    raise ValueError(f"Unexpected GSDP30 raster grid in {member}")
                bounds.append(box(*tile.bounds))
        self.index = STRtree(bounds)
        for i, j in self.index.query(bounds, predicate="intersects").T:
            if i<j and bounds[i].intersection(bounds[j]).area>1:
                raise ValueError(f"Overlapping GSDP30 rasters: {self.members[i]}, {self.members[j]}")
        self.read = lru_cache(maxsize=8)(archive.read)

    def fractions(self, rect):
        x0,y0,x1,y1 = rect
        step = 360/self.width
        left = x0 % self.width
        first = min(self.width-left, x1-x0)
        radius = 6378137
        lat = np.deg2rad(90-np.arange(y0,y1+1)*step)
        northings = np.arcsinh(np.tan(lat))*radius
        result = np.zeros((y1-y0,x1-x0),dtype=np.float32)
        for start, dest in ((left,result[:,:first]), (0,result[:,first:])):
            if not dest.shape[1]:
                continue
            eastings = np.deg2rad(np.arange(start,start+dest.shape[1]+1)*step-180)*radius
            footprint = box(eastings[0],northings[-1],eastings[-1],northings[0])
            for i in sorted(self.index.query(footprint)):
                with rasterio.MemoryFile(self.read(self.members[i])) as memory, memory.open() as tile:
                    fraction = sand_coverage(tile,eastings,northings)
                    if fraction is not None:
                        dest += fraction
        return np.clip(result,0,1,out=result)

    def material_weight(self, rect):
        # Soften the albedo transition at classification edges. Read a halo
        # on the global grid so both sides of each QPK overlap agree.
        x0,y0,x1,y1 = rect
        radius = 8
        top = max(0,y0-radius)
        bottom = min(self.width//2,y1+radius)
        coverage = self.fractions((x0-radius,top,x1+radius,bottom))
        if coverage.any():
            coverage = gaussian_filter(coverage, sigma=2.5, radius=radius, mode="nearest")
        return coverage[y0-top:y1-top,radius:-radius]


def land_material_color_frame(color, material, decode, encode, opaque_encoder):
    dim = TILE+2*GUTTER
    block_dim = dim//4
    raw = decode.decompress(color, max_output_size=dim**2)
    pixels = np.array(Image.frombytes("RGBA",(dim,dim),raw,"bcn",(7,"BC7")))
    coverage = pixels[...,3]
    land = coverage < 255
    if not land.any():
        return color
    rgb = pixels[...,:3]
    ground = material(rgb)
    if ground is None:
        return color
    weight = ground[...,3]*((255-coverage).astype(np.float32)/255)
    updated_rgb = np.rint(rgb + (ground[...,:3]*255-rgb)*weight[...,None]).astype(np.uint8)
    changed = (updated_rgb!=rgb).reshape(block_dim,4,block_dim,4,3).any(axis=(1,3,4)).ravel()
    if not changed.any():
        return color
    rgb[:] = updated_rgb
    encoded = ispc_texcomp.compress_blocks_bc7(ispc_texcomp.RGBASurface(pixels.tobytes(),dim,dim),ENCODER)
    decoded = np.asarray(Image.frombytes("RGBA",(dim,dim),encoded,"bcn",(7,"BC7")))
    affected_alpha = (decoded[...,3]!=coverage).reshape(block_dim,4,block_dim,4).any(axis=(1,3)).ravel()
    blocks = np.frombuffer(raw,dtype="V16").copy()
    blocks[changed] = np.frombuffer(encoded,dtype="V16")[changed]
    repairs = np.flatnonzero(changed & affected_alpha)
    for index in repairs:
        row,col = divmod(int(index),block_dim)
        target = pixels[4*row:4*(row+1),4*col:4*(col+1)]
        blocks[index] = np.void(recolor_bc7_preserving_alpha(raw[16*index:16*(index+1)],target,opaque_encoder))
    material_blocks = blocks.tobytes()
    if repairs.size:
        updated = np.asarray(Image.frombytes("RGBA",(dim,dim),material_blocks,"bcn",(7,"BC7")))
        if not np.array_equal(updated[...,3],coverage):
            raise ValueError("Land material build changed decoded water coverage")
    return encode.compress(material_blocks)


@contextmanager
def land_material_recipe(sources, natural_earth, level, historical_cropland=None, sand_dunes=None,
                         worldcover_fractions=None):
    """Use one globally registered source grid for Z6 and Z7 land albedo."""
    if level not in (6, 7):
        raise ValueError("Shared land materials currently support Z6 and Z7")
    cover = LandCover(sources/"worldcover", native=True)
    fine_width = 2*TILE << PACK_MAX_LEVEL
    width = 2*TILE << level
    collar = GUTTER*360/width
    glacier_shapes = physical_shapes(natural_earth,"glaciated_areas")
    across_west = [translate(geometry,xoff=-360) for geometry in glacier_shapes if geometry.bounds[2] > 180-collar]
    across_east = [translate(geometry,xoff=360) for geometry in glacier_shapes if geometry.bounds[0] < collar-180]
    glaciers = STRtree(glacier_shapes+across_west+across_east)
    with rasterio.Env(GDAL_CACHEMAX=192*2**20), rasterio.open(sources/DEM_15S) as source, ExitStack() as inputs:
        relief = Relief15s(source)
        historical = None
        if historical_cropland is not None:
            crops = inputs.enter_context(rasterio.open(historical_cropland))
            historical = inputs.enter_context(historical_cropland_grid(crops,fine_width))
        dunes = None
        if sand_dunes is not None:
            dunes = DuneCoverage(inputs.enter_context(ZipFile(sand_dunes)),fine_width)
        fractions = None
        if worldcover_fractions is not None:
            native = inputs.enter_context(rasterio.open(worldcover_fractions))
            fractions = worldcover_fraction_grid(native,fine_width)
        fine = partial(z7_land_material, relief, cover, glaciers, fine_width,
                       historical_cropland=historical, dunes=dunes, worldcover_fractions=fractions)
        if level == 7:
            yield fine
        else:
            yield partial(z6_land_material, fine, width=width)


def write_land_candidate(original, sources, natural_earth, destination, *, preview_pages=None,
                         historical_cropland=None, sand_dunes=None, worldcover_fractions=None,
                         level=7, scratch=None):
    with land_material_recipe(sources, natural_earth, level, historical_cropland, sand_dunes,
                              worldcover_fractions) as recipe:
        def material(rect, _rgb):
            return recipe(rect)
        write_material_candidate(original, destination, material, preview_pages=preview_pages,
                                 level=level, scratch=scratch)


def write_material_candidate(original, destination, material, *, preview_pages=None, level=7, scratch=None):
    import zstandard

    if destination.exists():
        raise FileExistsError(destination)
    decode = zstandard.ZstdDecompressor()
    encode = zstandard.ZstdCompressor(level=COMPACT_STRENGTH)
    opaque_encoder = ispc_texcomp.BC7EncSettings.from_profile("fast")
    changed = 0
    destination.parent.mkdir(parents=True, exist_ok=True)
    with original.open("rb") as file, staging_directory(destination.parent, scratch) as folder:
        pack = LevelPack(file, level, COMPACT_VERSION)

        def records():
            nonlocal changed
            for y in range(pack.ny):
                for x in range(pack.nx):
                    color_size,height_size = pack.frame_sizes(x,y)
                    color,height = file.read(color_size),file.read(height_size)
                    if preview_pages is None or (x,y) in preview_pages:
                        rect = (x*TILE-GUTTER,y*TILE-GUTTER,(x+1)*TILE+GUTTER,(y+1)*TILE+GUTTER)
                        updated = land_material_color_frame(color,partial(material,rect),decode,encode,opaque_encoder)
                        changed += int(updated != color)
                        color = updated
                    yield PACK_RECORD.pack(pack.level,x,y,len(color))+color+height
                if (y+1)%8 == 0 and preview_pages is None:
                    print(f"Z{level} land materials: {y+1}/{pack.ny} rows, {changed} pages rebuilt",flush=True)

        staged = Path(folder)/destination.name
        write_level_records(staged,pack.level,COMPACT_MAGIC,records())
        if not changed:
            raise ValueError(f"No Z{level} land materials changed")
        staged.rename(destination)
    print(f"Z{level}: {pack.nx*pack.ny} pages, {changed} rebuilt land colors; original height and water coverage preserved")


def write_level_pack(path, scratch, level):
    color, height = packed_rasters(scratch, level, "r")
    nx, ny = 2 << level, 1 << level
    def encode(x, y):
        bc7, metres = tile_bytes(color,height,level,x,y,1)
        bc7 = zlib.compress(bc7[HEADER.size:], level=1)
        metres = zlib.compress(metres[HEADER.size:], level=1)
        return PACK_RECORD.pack(level,x,y,len(bc7))+bc7+metres
    with ThreadPoolExecutor(max_workers=min(8, os.cpu_count() or 1)) as pool:
        rows = (pool.map(lambda x: encode(x, y), range(nx)) for y in range(ny))
        write_level_records(path, level, PACK_MAGIC, (record for row in rows for record in row))


def write_compact_level(path, original, level):
    from threading import local
    import zstandard

    workers = local()

    def encode(item):
        x, y, (color, height) = item
        if not hasattr(workers, "compressor"):
            workers.compressor = zstandard.ZstdCompressor(level=COMPACT_STRENGTH)
        compress = workers.compressor.compress
        bc7 = compress(color.tobytes())
        metres = compress(predict_heights(height))
        return PACK_RECORD.pack(level, x, y, len(bc7))+bc7+metres

    with pack_path(original, level).open("rb") as file, ThreadPoolExecutor(max_workers=min(8, os.cpu_count() or 1)) as pool:
        source = LevelPack(file, level)
        rows = (pool.map(encode, ((x, y, source.at(x, y)) for x in range(source.nx)))
                for y in range(source.ny))
        write_level_records(path, level, COMPACT_MAGIC, (record for row in rows for record in row))


def compact_package(original, output, *, scratch=None):
    manifest = json.loads((original / "index.json").read_text(encoding="utf-8"))
    if manifest["version"] != PACK_VERSION or len(manifest["levels"]) != PACK_MAX_LEVEL+1:
        raise ValueError("Repacking requires the complete original Z0–Z7 package")
    if output.exists():
        raise ValueError(f"Output already exists: {output}")
    original_levels = manifest["levels"]
    manifest.update(version=COMPACT_VERSION, compression=COMPACT_FORMAT, levels=[])
    with staging_directory(output.parent, scratch) as folder:
        staged = Path(folder) / COMPACT_VERSION
        staged.mkdir()
        river_file = "river-topology.u32"
        copyfile(original / river_file, staged / river_file)
        verify_topology(staged, manifest)
        if not filecmp.cmp(original / river_file, staged / river_file, shallow=False):
            raise ValueError("Changed global river topology")
        for level, declared in enumerate(original_levels):
            print(f"Repacking Z{level} global terrain", flush=True)
            write_compact_level(pack_path(staged, level), original, level)
            with pack_path(original, level).open("rb") as file:
                result = verify_packed_level(staged, level, COMPACT_VERSION, LevelPack(file, level))
            if any(declared.get(key) != value for key, value in result.items() if key != "bytes"):
                raise ValueError(f"Z{level} differs from the original inventory")
            manifest["levels"].append(result)
            print(json.dumps(result), flush=True)
        (staged / "index.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
        staged.rename(output)


def advance_packed(sources, natural_earth, output, through, job, cleanup):
    output.mkdir(parents=True, exist_ok=True)
    scratch = output.with_name(output.name+".working")
    ready = scratch / "mother.json"
    index = output / "index.json"
    if not ready.exists():
        if index.exists():
            raise ValueError("This package has an index but no matching working mother raster")
        if scratch.exists():
            raise ValueError(f"Unfinished mother raster from an earlier run: {scratch}")
        staged = job / "mother"
        staged.mkdir()
        manifest = build_packed_mother(staged, sources, natural_earth, output)
        (staged / ready.name).write_text(json.dumps(manifest), encoding="utf-8")
        staged.rename(scratch)
    else:
        manifest = json.loads((index if index.exists() else ready).read_text(encoding="utf-8"))
        if manifest["version"] != PACK_VERSION:
            raise ValueError("Wrong global terrain package version")
    for level in range(len(manifest["levels"]), through+1):
        print(f"Writing Z{level} global terrain", flush=True)
        path = pack_path(output, level)
        temporary = job / path.name
        write_level_pack(temporary, scratch, level)
        result = verify_packed_level(output, level, candidate=temporary)
        temporary.replace(path)
        manifest["levels"].append(result)
        print(json.dumps(result), flush=True)
    if len(manifest["levels"]) != through+1:
        raise ValueError("Packed terrain levels can only advance")
    temporary = job / index.name
    temporary.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
    temporary.replace(index)
    if through == PACK_MAX_LEVEL:
        cleanup.callback(remove_completed_mother, scratch, ready)


def remove_completed_mother(scratch, ready):
    for level in range(PACK_MAX_LEVEL+1):
        (scratch / f"{level}.rgba").unlink()
        (scratch / f"{level}.height").unlink()
    ready.unlink()
    scratch.rmdir()


def staging_directory(parent, scratch):
    return TemporaryDirectory(dir=parent) if scratch is None else nullcontext(scratch)


@contextmanager
def generation_disk_usage(output, estimated_bytes):
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    volumes = {Path(output.anchor)}
    if os.name == "nt":
        volumes.update(path for path in (Path("C:/"), Path("D:/")) if path.is_dir())
    log_path = output.parent / "terrain-disk-usage.jsonl"
    started = datetime.now().astimezone().isoformat()

    def record(state, scratch=None, cleanup_error=None):
        data = dict(started=started, time=datetime.now().astimezone().isoformat(),
                    output=str(output), state=state, estimated_new_bytes=estimated_bytes,
                    free_bytes={str(volume): disk_usage(volume).free for volume in sorted(volumes)})
        if scratch is not None:
            data["scratch"] = str(scratch)
        if cleanup_error is not None:
            data["cleanup_error"] = str(cleanup_error)
        line = json.dumps(data, ensure_ascii=False)
        print(line, flush=True)
        try:
            with log_path.open("a", encoding="utf-8") as file:
                file.write(line + "\n")
        except OSError as error:
            print(f"Could not save the disk log: {error}", flush=True)

    if estimated_bytes > 10_000_000_000:
        print(f"Estimated new disk use: {estimated_bytes / 1e9:.1f} GB on {output.anchor}", flush=True)
    cleanup = ExitStack()
    scratch = None
    outcome = "failed_or_cancelled"
    try:
        scratch = Path(cleanup.enter_context(TemporaryDirectory(dir=output.parent, prefix="terrain-job-")))
        record("started", scratch)
        yield scratch, cleanup
        outcome = "finished"
    finally:
        try:
            record(outcome, scratch)
        finally:
            try:
                cleanup.close()
            except BaseException as error:
                record("cleanup_failed", scratch, error)
                raise
            else:
                record("cleaned", scratch)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", type=Path, metavar="PACKAGE", help="Check an existing global package")
    parser.add_argument("--layer", type=int, choices=range(PACK_MAX_LEVEL+1), help="Check one packed level with --verify")
    parser.add_argument("--index-only", action="store_true", help="Check every tile record header without decoding")
    parser.add_argument("--layer-candidate", type=Path, metavar="QPK", help="Check a replacement QPK with --layer")
    parser.add_argument("--repack", type=Path, nargs=2, metavar=("ORIGINAL", "COMPACT"),
                        help="Losslessly repack and compare all global Z0–Z7 tiles")
    parser.add_argument("--ice-shelf-candidate", type=Path, nargs=3, metavar=("ORIGINAL_QPK", "SCAR_ADD_JSON", "CANDIDATE_QPK"),
                        help="Build a complete Z6 or Z7 QPK with SCAR ADD floating-ice color")
    parser.add_argument("--refine-ice-shelf-edges", action="store_true",
                        help="Use 4x4 coverage and preserve decoded water coverage in a Z7 ice-shelf candidate")
    terrain_candidate = parser.add_mutually_exclusive_group()
    terrain_candidate.add_argument("--river-outlet-candidate", type=Path, nargs=4,
                        metavar=("ORIGINAL_QPK", "OUTLETS_GEOJSON", "NATURAL_EARTH", "CANDIDATE_QPK"),
                        help="Build a complete Z7 QPK with documented river outlet connections")
    terrain_candidate.add_argument("--inland-water-candidate", type=Path, nargs=3,
                        metavar=("ORIGINAL_QPK", "LAKES_GEOJSON", "CANDIDATE_QPK"),
                        help="Build a complete Z7 QPK with documented missing inland water")
    terrain_candidate.add_argument("--z6-land-candidate", type=Path, nargs=4,
                        metavar=("ORIGINAL_QPK", "SOURCES", "NATURAL_EARTH", "CANDIDATE_QPK"),
                        help="Build a complete Z6 QPK using the Z7 land material source grid")
    terrain_candidate.add_argument("--z7-land-candidate", type=Path, nargs=4,
                        metavar=("ORIGINAL_QPK", "SOURCES", "NATURAL_EARTH", "CANDIDATE_QPK"),
                        help="Build a complete Z7 QPK with terrain-derived land materials")
    parser.add_argument("--historical-cropland",type=Path,metavar="CAO_1900_TIFF",
                        help="Apply Cao 1900 reconstructed cropland fractions in a land candidate")
    parser.add_argument("--sand-dunes", type=Path, metavar="GSDP30_ZIP",
                        help="Read mapped dune coverage from GSDP30 in a land candidate")
    parser.add_argument("--worldcover-fractions", type=Path, metavar="WORLDCOVER_TIFF",
                        help="Use modern ESA WorldCover area fractions on the Z7 grid")
    parser.add_argument("--through", type=int, choices=(5,6,7), help="Build or advance the 15 arc-second package")
    parser.add_argument("sources",type=Path,nargs="?")
    parser.add_argument("natural_earth",type=Path,nargs="?")
    parser.add_argument("output",type=Path,nargs="?")
    args = parser.parse_args()
    if args.layer is not None and args.verify is None:
        parser.error("--layer requires --verify")
    if (args.index_only or args.layer_candidate is not None) and args.layer is None:
        parser.error("--index-only and --layer-candidate require --layer")
    if args.refine_ice_shelf_edges and args.ice_shelf_candidate is None:
        parser.error("--refine-ice-shelf-edges requires --ice-shelf-candidate")
    land_candidate = args.z7_land_candidate or args.z6_land_candidate
    if args.historical_cropland is not None and land_candidate is None:
        parser.error("--historical-cropland requires a Z6 or Z7 land candidate")
    if args.sand_dunes is not None and land_candidate is None:
        parser.error("--sand-dunes requires a Z6 or Z7 land candidate")
    if args.worldcover_fractions is not None and land_candidate is None:
        parser.error("--worldcover-fractions requires a Z6 or Z7 land candidate")
    if land_candidate is not None:
        if any(arg is not None for arg in (args.verify,args.repack,args.through,args.sources,
                                           args.ice_shelf_candidate)):
            parser.error("Land candidate generation does not accept other build arguments")
        level = 7 if args.z7_land_candidate else 6
        with generation_disk_usage(land_candidate[-1], 3_000_000_000) as (scratch, _):
            write_land_candidate(*land_candidate,historical_cropland=args.historical_cropland,
                                 sand_dunes=args.sand_dunes,worldcover_fractions=args.worldcover_fractions,
                                 level=level,scratch=scratch)
        return
    if args.river_outlet_candidate is not None or args.inland_water_candidate is not None:
        if any(arg is not None for arg in (args.verify,args.repack,args.through,args.sources,
                                           args.ice_shelf_candidate)):
            parser.error("Water candidates do not accept other build arguments")
        if args.river_outlet_candidate is not None:
            with generation_disk_usage(args.river_outlet_candidate[-1], 3_000_000_000) as (scratch, _):
                write_outlet_candidate(*args.river_outlet_candidate, scratch=scratch)
        else:
            with generation_disk_usage(args.inland_water_candidate[-1], 3_000_000_000) as (scratch, _):
                write_inland_water_candidate(*args.inland_water_candidate, scratch=scratch)
        return
    if args.ice_shelf_candidate is not None:
        if any(arg is not None for arg in (args.verify,args.repack,args.through,args.sources)):
            parser.error("--ice-shelf-candidate does not accept other build arguments")
        with generation_disk_usage(args.ice_shelf_candidate[-1], 3_000_000_000) as (scratch, _):
            write_ice_shelf_candidate(*args.ice_shelf_candidate, refine_edges=args.refine_ice_shelf_edges,
                                      scratch=scratch)
        return
    if args.repack is not None:
        if args.verify is not None or args.sources is not None or args.through is not None:
            parser.error("--repack does not accept other build arguments")
        original, output = args.repack
        estimate = sum(path.stat().st_size for path in original.glob("*.qpk")) + 1_000_000_000
        with generation_disk_usage(output, estimate) as (scratch, _):
            compact_package(original, output, scratch=scratch)
        return
    if args.verify is not None:
        if args.sources is not None or args.through is not None:
            parser.error("--verify does not accept build arguments")
        verify_package(args.verify, args.layer, args.index_only, args.layer_candidate)
        return
    if args.output is None:
        parser.error("Build requires sources, natural_earth and output")
    output = args.output
    if args.through is not None:
        if output.name != PACK_VERSION:
            parser.error(f"Expected the output directory name {PACK_VERSION}")
        ready = output.with_name(output.name+".working") / "mother.json"
        estimate = 10_000_000_000 if ready.exists() else 36_000_000_000
        with generation_disk_usage(output, estimate) as (scratch, cleanup):
            advance_packed(args.sources,args.natural_earth,output,args.through,scratch,cleanup)
        return
    if output.exists():
        parser.error(f"Output already exists: {output}")
    with generation_disk_usage(output, 6_000_000_000) as (scratch, _):
        staged = scratch / VERSION
        staged.mkdir()
        build(args.sources,args.natural_earth,staged,scratch=scratch)
        staged.rename(output)


if __name__ == "__main__":
    main()
