"""Build the WGS84 WorldCRS84Quad global terrain from cached geographic sources."""

import argparse
import os
from concurrent.futures import ThreadPoolExecutor
import filecmp
from functools import lru_cache
from io import BytesIO
import json
from pathlib import Path
from shutil import copyfile
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
from rasterio.windows import Window
from scipy.ndimage import label
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

    def at(self, lon, lat):
        x = (lon+180)*240-.5
        y = np.clip((90-lat)*240-.5, 0, self.source.height-1)
        start = int(np.floor(y.min()))
        stop = min(self.source.height, int(np.floor(y.max()))+2)
        stripe = self.source.read(1, window=Window(0, start, self.source.width, stop-start))
        if self.source.nodata is not None and np.any(stripe == self.source.nodata):
            raise ValueError(f"Missing elevation in GMT source rows {start}–{stop}")
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
        # The same globally registered albedo field at all elevations and LODs.
        step = 3/self.span
        x = (lon+180)/step-.5
        y = (90-lat)/step-.5
        xi, yi = np.floor(x).astype(np.int32), np.floor(y).astype(np.int32)
        a, b = (x-xi).astype(np.float32), (y-yi).astype(np.float32)
        def gather(dx, dy):
            xx = (xi+dx) % (120*self.span)
            yy = np.clip(yi+dy,0,60*self.span-1)
            cc, rr = xx//self.span, yy//self.span
            result = np.broadcast_to(NEUTRAL, (len(lat),len(lon),3)).copy()
            # Missing WorldCover tiles are ocean and ice outside its observed coverage.
            for r in np.unique(rr):
                ii = np.flatnonzero(rr==r)
                for c in np.unique(cc):
                    tile = self.tiles.get((87-3*r, -180+3*c))
                    if tile is not None:
                        jj = np.flatnonzero(cc==c)
                        positions = (yy[ii,None]%self.span,xx[jj]%self.span)
                        color = (self.lookup[self.codes(tile)[positions]] if isinstance(tile, Path)
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


def rasterize(tree, width, rect):
    x0,y0,x1,y1 = rect
    step = 360/width
    west,north = x0*step-180, 90-y0*step
    east,south = x1*step-180, 90-y1*step
    selected = tree.geometries.take(tree.query(box(west,south,east,north), predicate="intersects"))
    if not len(selected):
        return np.zeros((y1-y0,x1-x0), dtype=np.float32)
    bits = features.rasterize(selected, out_shape=((y1-y0)*2,(x1-x0)*2), dtype="uint8",
                              transform=from_origin(west,north,step/2,step/2))
    return bits.reshape(y1-y0,2,x1-x0,2).mean(axis=(1,3), dtype=np.float32)


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
    water = np.maximum(lake,river*.78) * land
    color += (np.array([.20,.38,.45],np.float32)-color)*water[...,None]
    return color, z, land, water, lake


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


def build(sources, natural_earth, output):
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
    with TemporaryDirectory(dir=output.parent) as folder:
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


def shade_packed_water(ground, z, land, lake, enclosed):
    sea = np.maximum(0, (1-land)*(1-lake)-enclosed)
    depth = np.clip(-z/5100, 0, 1)**.43
    ocean = np.array([.17,.32,.38],np.float32)-depth[...,None]*np.array([.092,.128,.122],np.float32)
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


def ice_shelf_polygons(source):
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
        vicinity = shelf.buffer(10_000)
        for index in land.query(vicinity, predicate="intersects"):
            segment = clip_by_rect(grounded[index], *vicinity.bounds)
            ground = make_valid(segment).intersection(vicinity)
            if ground.area:
                polygons.append(ground)
    for polygon in polygons:
        prepare(polygon)
    return STRtree(polygons)


def floating_ice_coverage(polygons, projection, nx, ny, x, y):
    step = 360/(nx*TILE)
    columns = np.arange(x*TILE-GUTTER, (x+1)*TILE+GUTTER)
    rows = np.arange(y*TILE-GUTTER, (y+1)*TILE+GUTTER).clip(0, ny*TILE-1)
    west, east = columns[[0,-1]]*step-180
    north, south = 90-rows[[0,-1]]*step
    if south-step > -60:
        return None
    bounds = projection.transform_bounds(west, south-step, east+step, north)
    selected = polygons.geometries.take(polygons.query(box(*bounds)))
    if not len(selected):
        return None
    coverage = np.zeros((len(rows),len(columns)), dtype=np.uint8)
    for dx, dy in ((.25,.25), (.75,.25), (.25,.75), (.75,.75)):
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


def write_ice_shelf_candidate(original, source, destination):
    """Apply SCAR ADD floating-ice color to a complete Z6 or Z7 QPK."""
    from pyproj import Transformer
    import zstandard

    if destination.exists():
        raise FileExistsError(destination)
    polygons = ice_shelf_polygons(source)
    projection = Transformer.from_crs(4326, 3031, always_xy=True)
    decode = zstandard.ZstdDecompressor()
    encode = zstandard.ZstdCompressor(level=COMPACT_STRENGTH)
    dim = TILE+2*GUTTER
    block_dim = dim//4
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
        file.seek(0)
        pack = LevelPack(file, level, COMPACT_VERSION)
        opaque_encoder = ispc_texcomp.BC7EncSettings.from_profile("fast") if level == 6 else None

        def records():
            nonlocal changed, refitted_alpha_blocks
            for y in range(pack.ny):
                for x in range(pack.nx):
                    color_size, height_size = pack.frame_sizes(x,y)
                    color = file.read(color_size)
                    height = file.read(height_size)
                    coverage = floating_ice_coverage(polygons, projection, pack.nx, pack.ny, x, y)
                    if coverage is not None:
                        raw = decode.decompress(color, max_output_size=dim**2)
                        pixels = np.array(Image.frombytes("RGBA", (dim,dim), raw, "bcn", (7,"BC7")))
                        amount = coverage.astype(np.float32)*pixels[...,3]/(4*255)
                        if amount.any():
                            rgb = pixels[...,:3]
                            rgb[:] = np.rint(rgb+(ice_color-rgb)*amount[...,None]).astype(np.uint8)
                            bc7 = ispc_texcomp.compress_blocks_bc7(
                                ispc_texcomp.RGBASurface(pixels.tobytes(), dim, dim), ENCODER)
                            # Reuse the original blocks wherever no pixel changed. Padded edge
                            # blocks use the same global samples and stay identical across tiles.
                            updated = amount.reshape(block_dim,4,block_dim,4).any(axis=(1,3)).ravel()
                            blocks = np.frombuffer(raw,dtype="V16").copy()
                            blocks[updated] = np.frombuffer(bc7,dtype="V16")[updated]
                            if level == 6:
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
                                    raise ValueError(f"Changed decoded water coverage at Z6/{x}/{y}")
                            recolored = encode.compress(blocks.tobytes())
                            changed += int(level == 7 or recolored != color)
                            color = recolored
                    yield PACK_RECORD.pack(pack.level,x,y,len(color))+color+height

        destination.parent.mkdir(parents=True, exist_ok=True)
        with TemporaryDirectory(dir=destination.parent) as folder:
            staged = Path(folder)/destination.name
            write_level_records(staged, pack.level, COMPACT_MAGIC, records())
            if not changed:
                raise ValueError(f"No Z{level} tiles changed")
            staged.rename(destination)
    print(f"Z{level}: {pack.nx*pack.ny} tiles, {changed} color records updated, original height frames preserved")
    if level == 6:
        print(f"Z6: {refitted_alpha_blocks} BC7 blocks refitted with exact decoded water coverage")


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


def compact_package(original, output):
    manifest = json.loads((original / "index.json").read_text(encoding="utf-8"))
    if manifest["version"] != PACK_VERSION or len(manifest["levels"]) != PACK_MAX_LEVEL+1:
        raise ValueError("Repacking requires the complete original Z0–Z7 package")
    if output.exists():
        raise ValueError(f"Output already exists: {output}")
    original_levels = manifest["levels"]
    manifest.update(version=COMPACT_VERSION, compression=COMPACT_FORMAT, levels=[])
    with TemporaryDirectory(dir=output.parent) as folder:
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


def advance_packed(sources, natural_earth, output, through):
    output.mkdir(parents=True, exist_ok=True)
    scratch = output.with_name(output.name+".working")
    scratch.mkdir(exist_ok=True)
    ready = scratch / "mother.json"
    index = output / "index.json"
    if not ready.exists():
        if index.exists():
            raise ValueError("This package has an index but no matching working mother raster")
        manifest = build_packed_mother(scratch, sources, natural_earth, output)
        ready.write_text(json.dumps(manifest), encoding="utf-8")
    else:
        manifest = json.loads((index if index.exists() else ready).read_text(encoding="utf-8"))
        if manifest["version"] != PACK_VERSION:
            raise ValueError("Wrong global terrain package version")
    for level in range(len(manifest["levels"]), through+1):
        print(f"Writing Z{level} global terrain", flush=True)
        path = pack_path(output, level)
        temporary = path.with_suffix(".part")
        write_level_pack(temporary, scratch, level)
        temporary.replace(path)
        result = verify_packed_level(output, level)
        manifest["levels"].append(result)
        print(json.dumps(result), flush=True)
    if len(manifest["levels"]) != through+1:
        raise ValueError("Packed terrain levels can only advance")
    temporary = index.with_suffix(".part")
    temporary.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
    temporary.replace(index)
    if through == PACK_MAX_LEVEL:
        for level in range(PACK_MAX_LEVEL+1):
            (scratch / f"{level}.rgba").unlink()
            (scratch / f"{level}.height").unlink()
        ready.unlink()
        scratch.rmdir()


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
    parser.add_argument("--through", type=int, choices=(5,6,7), help="Build or advance the 15 arc-second package")
    parser.add_argument("sources",type=Path,nargs="?")
    parser.add_argument("natural_earth",type=Path,nargs="?")
    parser.add_argument("output",type=Path,nargs="?")
    args = parser.parse_args()
    if args.layer is not None and args.verify is None:
        parser.error("--layer requires --verify")
    if (args.index_only or args.layer_candidate is not None) and args.layer is None:
        parser.error("--index-only and --layer-candidate require --layer")
    if args.ice_shelf_candidate is not None:
        if any(arg is not None for arg in (args.verify,args.repack,args.through,args.sources)):
            parser.error("--ice-shelf-candidate does not accept other build arguments")
        write_ice_shelf_candidate(*args.ice_shelf_candidate)
        return
    if args.repack is not None:
        if args.verify is not None or args.sources is not None or args.through is not None:
            parser.error("--repack does not accept other build arguments")
        compact_package(*args.repack)
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
        advance_packed(args.sources,args.natural_earth,output,args.through)
        return
    if output.exists():
        parser.error(f"Output already exists: {output}")
    output.parent.mkdir(parents=True,exist_ok=True)
    with TemporaryDirectory(dir=output.parent) as folder:
        staged = Path(folder)/VERSION
        staged.mkdir()
        build(args.sources,args.natural_earth,staged)
        staged.rename(output)


if __name__ == "__main__":
    main()
