"""Build exclusive ground coverage from the existing Paris and London sources."""

import argparse
import math
import struct
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from rasterio.features import rasterize
from rasterio.transform import from_bounds
from shapely import Polygon, STRtree, box, transform
from shapely.geometry import shape
from zstandard import ZstdCompressor, ZstdDecompressor

from build_city_models import RECORD, features, london_parks, read, rectangle, transforms
from build_london_city_ground import GROUP as LONDON, GUTTER as LONDON_GUTTER
from build_paris_city_ground import GUTTER as PARIS_GUTTER, STREETS_GROUP, STREETS_PREFIX
from city_ground_pack import read_city_coverage

PARIS = (1.966, 48.67, 2.692, 49.058)
SIDE = 2048
SAMPLES = 2
UNKNOWN, ROOF, COURT, WORK, OPEN, WOOD, MARKET_GARDEN = range(7)


class Grid:
    def __init__(self, bounds, side=SIDE):
        self.bounds = bounds
        west, south, east, north = bounds
        self.side = side * SAMPLES
        self.scale = (111195. * math.cos(math.radians((south + north) * .5)), 111195.)
        self.spacing = ((north - south) * self.scale[1] / self.side,
                        (east - west) * self.scale[0] / self.side)
        self.transform = from_bounds(*bounds, self.side, self.side)

    def mask(self, geometries):
        return rasterize((shape for shape in geometries if not shape.is_empty), out_shape=(self.side, self.side),
                         transform=self.transform, dtype=np.uint8).astype(bool)

    def point(self, lon, lat):
        west, south, east, north = self.bounds
        return ((lon - west) / (east - west) * self.side, (north - lat) / (north - south) * self.side)

    def distance(self, mask):
        from scipy.ndimage import distance_transform_edt

        return distance_transform_edt(~mask, sampling=self.spacing)


def mosaic(grid, overlays, prefix, gutter):
    # Reassemble source coverage without duplicating page gutters.
    survey = Image.new("LA", (grid.side, grid.side))
    tiles = [tile for tile in read(overlays / "catalogue.json")["tiles"] if tile["path"].startswith(prefix)]
    if not tiles:
        raise ValueError(f"Missing source pages for {prefix}")
    for tile in tiles:
        width, height = tile["size"]
        west, south, east, north = tile["core"]
        left, top = (round(p) for p in grid.point(west, north))
        right, bottom = (round(p) for p in grid.point(east, south))
        page = np.asarray(Image.frombytes("LA", (width, height), read_city_coverage(overlays / tile["path"])))
        # Resample independent scalar masks without treating the second as alpha.
        channels = tuple(Image.fromarray(page[gutter:-gutter, gutter:-gutter, index])
                         .resize((right - left, bottom - top), Image.Resampling.BILINEAR) for index in range(2))
        survey.paste(Image.merge("LA", channels), (left, top))
    return np.asarray(survey)


def london_surface(grid, sources, overlays):
    from scipy.ndimage import uniform_filter

    survey = mosaic(grid, overlays, "london-os-1890s-", LONDON_GUTTER)
    coverage = survey[:, :, 0]
    roofs = coverage >= 48
    parks = grid.mask(london_parks(sources / "london_1890s/parks-boundaries.json"))
    density = uniform_filter(coverage.astype(np.float32) / 255., size=tuple(round(95. / m) for m in grid.spacing))
    distance = grid.distance(roofs)
    # Only infer garden and yard surfaces supported by close, clustered surveyed buildings.
    courts = (distance <= 9.) | ((distance <= 15.) & (density > .23))
    gardens = (distance <= 31.) & (density > .11)

    # Surrey Commercial Docks. The 1895 OS sheet locates the docks; the work
    # surface is an approximation limited to surveyed wharf-side building land.
    dock = Polygon([(-.0621, 51.4995), (-.0527, 51.5092), (-.0364, 51.5059),
                    (-.0305, 51.4966), (-.0405, 51.4891), (-.0534, 51.4895)])
    work = grid.mask([dock]) & (distance <= 32.) & (density > .085)
    classes = np.zeros_like(coverage)
    classes[gardens & ~parks] = OPEN
    classes[courts & ~parks] = COURT
    classes[work & ~parks] = WORK
    classes[roofs] = ROOF
    return classes, survey[:, :, 1].astype(np.float32) / 255.


def placements(models, fringe):
    decoder = ZstdDecompressor()
    paris = next(city for city in read(models / "catalogue.json")["cities"] if city["name"] == "Paris")
    for tile in paris["tiles"]:
        yield from RECORD.iter_unpack(decoder.decompress((models / tile["file"]).read_bytes()[12:]))
    data = fringe.read_bytes()
    offset = 12
    for _ in range(struct.unpack_from("<I", data, 8)[0]):
        _, _, _, _, _, size = struct.unpack_from("<4iII", data, offset)
        yield from RECORD.iter_unpack(decoder.decompress(data[offset + 36:offset + 24 + size]))
        offset += 24 + size


def paris_roofs(grid, models, fringe):
    image = Image.new("L", (grid.side, grid.side))
    draw = ImageDraw.Draw(image)
    for x, y, bearing, width, depth, _, _, _ in placements(models, fringe):
        lon, lat = x / 1e6, y / 1e6
        angle = math.radians(bearing / 100.)
        east, north = math.cos(angle), math.sin(angle)
        roof = [
            grid.point(lon + (u * east - v * north) / grid.scale[0],
                       lat + (u * north + v * east) / grid.scale[1])
            for u, v in ((-width / 20., -depth / 20.), (width / 20., -depth / 20.),
                         (width / 20., depth / 20.), (-width / 20., depth / 20.))
        ]
        draw.polygon(roof, fill=1)
    return np.asarray(image).astype(bool)


def paris_surface(grid, sources, overlays, models, fringe):
    history = sources / "paris_reference/ile-de-france-land-cover-1900.geojson"
    block_map = sources / "paris_1900_ptm/PTM_Paris1900_ilots_epsg4326.geojson"
    classes = np.zeros((grid.side, grid.side), dtype=np.uint8)
    # The extract omits agricultural code 0. Leave unrecorded areas to QPK.
    historical_urban = grid.mask(features(history, lambda p: p["codzon"] == "3"))
    classes[historical_urban] = OPEN
    classes[grid.mask(features(history, lambda p: p["codzon"] == "2"))] = WOOD
    classes[grid.mask(features(history, lambda p: p["codzon"] == "4"))] = WORK
    water = grid.mask(features(history, lambda p: p["codzon"] == "1"))
    blocks = grid.mask(features(block_map, lambda p: p["Bati_nonBati"] == "Bâti"))
    unbuilt = grid.mask(features(block_map, lambda p: str(p["Bati_nonBati"]).startswith("Non-bâti")))
    roofs = paris_roofs(grid, models, fringe)
    dry_land = ~water & (classes != WOOD) & (classes != WORK)
    # Preserve the existing courtyard infill within the detailed inner
    # survey. Peripheral placements alone don't establish paved land use.
    core = grid.mask([box(*STREETS_GROUP)])
    core_courts = core & historical_urban & (grid.distance(roofs) <= 17.)
    classes[(blocks | core_courts) & dry_land & ~unbuilt] = COURT
    classes[unbuilt & dry_land] = OPEN
    classes[roofs & dry_land & ~unbuilt] = ROOF
    classes[water] = UNKNOWN

    # Approximate extent of the documented market gardens south of the
    # Croult. The Six Routes study records the small NE–SW strips and
    # successive industrial use. Only allocate ground the land-use and
    # block sources leave free. Railroad and industrial ground stays WORK.
    vertus = Polygon([
        (2.3765, 48.9192), (2.38338, 48.92181), (2.38554, 48.92972),
        (2.39330, 48.92723), (2.4020, 48.9235), (2.4050, 48.9182),
        (2.4005, 48.9135), (2.3930, 48.9118), (2.38513, 48.91488),
    ])
    garden = grid.mask([vertus]) & (classes == UNKNOWN) & ~water & ~blocks & ~roofs
    classes[garden] = MARKET_GARDEN
    streets = mosaic(grid, overlays, STREETS_PREFIX, PARIS_GUTTER).astype(np.float32) / 255.
    roads = streets[:, :, 0] + streets[:, :, 1] * (1. - streets[:, :, 0])
    return classes, roads


def mip_words(classes, roads, side=SIDE, collar=0):
    bands = [(classes == kind) * (1. - roads) for kind in range(ROOF, WOOD + 1)]
    bands.append(roads)
    garden = (classes == MARKET_GARDEN) * (1. - roads)
    levels = collar.bit_length() if collar else side.bit_length()
    for level in range(levels):
        inner = side >> level
        padding = collar >> level
        span = inner + 2 * padding
        words = np.zeros((span, span), dtype="<u4")
        for index, band in enumerate(bands):
            bands[index] = area_average(band, span)
            words |= np.rint(bands[index] * 31.).astype(np.uint32) << (index * 5)
        garden = area_average(garden, span)
        words |= np.rint(garden * 3.).astype(np.uint32) << 30
        if padding > 1:
            words = words[padding - 1 : padding + inner + 1, padding - 1 : padding + inner + 1]
        yield words.tobytes()


def area_average(band, side):
    factor = band.shape[0] // side
    return band.reshape(side, factor, side, factor).mean((1, 3))


def planned_surface_pages(plan, rows):
    """Rasterize sourced uses and the accepted site layout on one 16 m grid."""
    from build_city_water import METRES, ROAD_PAGE_METRES

    meta = plan["wwo"]
    lon, lat = meta["origin"]
    xs, ys = METRES * math.cos(math.radians(lat)), METRES
    page_m = ROAD_PAGE_METRES
    side, collar = 256, 8  # The fourth mip still has one texel past each edge.
    style = meta.get("ground_material", 0)
    if type(style) is not int or not 0 <= style <= 2:
        raise ValueError("Invalid city ground material")
    kind_classes = {"courtyard": COURT, "yard": WORK, "rail": WORK, "work_ground": WORK,
                    "park": OPEN, "open_ground": OPEN, "woodland": WOOD}
    water_kinds = {"water", "water_surface"}
    masks = []
    parents = []
    forward, backward = transforms(meta["origin"])
    for feature in sorted(plan["features"], key=lambda row: row["id"]):
        props = feature["properties"]
        kind = props["kind"]
        if kind not in kind_classes and kind not in water_kinds and kind != "road":
            continue
        geom = shape(feature["geometry"])
        if kind == "road":
            geom = transform(geom, forward.transform, interleaved=False).buffer(props["width_m"] * .5)
            geom = transform(geom, backward.transform, interleaved=False)
        masks.append(("road" if kind == "road" else kind_classes.get(kind, UNKNOWN), feature["id"], geom))
        parents.append(feature)
    for x, y, _, _, angle, width, depth, _, _ in rows:
        roof = transform(rectangle(x,y,angle,width,depth), backward.transform, interleaved=False)
        masks.append((ROOF, "placement_origins", roof))
    cells = set()
    for kind, _, geom in masks:
        if kind == UNKNOWN:
            continue
        w, s, e, n = geom.bounds
        cells.update((x, y) for x in range(math.floor((w-lon)*xs/page_m), math.ceil((e-lon)*xs/page_m))
                     for y in range(math.floor((s-lat)*ys/page_m), math.ceil((n-lat)*ys/page_m)))
    tree = STRtree([row[2] for row in masks])
    pages = []
    for x, y in sorted(cells):
        w, s, e, n = x*page_m, y*page_m, (x+1)*page_m, (y+1)*page_m
        bounds = [lon+w/xs, lat+s/ys, lon+e/xs, lat+n/ys]
        margin = collar * page_m / side
        sample = (lon+(w-margin)/xs, lat+(s-margin)/ys, lon+(e+margin)/xs, lat+(n+margin)/ys)
        grid = Grid(sample, side + 2 * collar)
        by_use = {}
        used = set()
        for i in sorted(tree.query(box(*sample), predicate="intersects")):
            kind, parent, geom = masks[i]
            by_use.setdefault(kind, []).append(geom)
            used.add(parent)
        classes = np.zeros((grid.side, grid.side), dtype=np.uint8)
        # The same protected areas already constrain placements. Leave all
        # gaps between sourced features to the world surface.
        for kind in (OPEN, COURT, WORK, WOOD, ROOF, UNKNOWN):
            if kind in by_use:
                classes[grid.mask(by_use[kind])] = kind
        roads = grid.mask(by_use["road"]) if "road" in by_use else np.zeros_like(classes, dtype=bool)
        if UNKNOWN in by_use:
            roads &= ~grid.mask(by_use[UNKNOWN])
        payload = struct.pack("<8fI", lon,lat,xs,ys,w,s,e,n,style)
        payload += b"".join(mip_words(classes, roads, side, collar))
        pages.append((x,y,bounds,payload,sorted(used)))
    return parents, pages


def build(sources, data, fringe, output):
    surfaces = [
        (LONDON, london_surface(Grid(LONDON), sources, data / "city-overlays")),
        (PARIS, paris_surface(Grid(PARIS), sources, data / "city-overlays", data / "city-models", fringe)),
    ]
    offset = 1 + 6 * len(surfaces)
    header = bytearray(struct.pack("<I", len(surfaces)))
    for (west, south, east, north), _ in surfaces:
        header.extend(struct.pack("<4f2I", west, south, east, north, SIDE, offset))
        offset += (4 * SIDE * SIDE - 1) // 3
    with output.open("wb") as file, ZstdCompressor(level=12).stream_writer(file) as stream:
        stream.write(header)
        for _, (classes, roads) in surfaces:
            for level in mip_words(classes, roads):
                stream.write(level)


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("sources", type=Path)
    cli.add_argument("data", type=Path)
    cli.add_argument("fringe", type=Path)
    cli.add_argument("output", type=Path)
    args = cli.parse_args()
    build(args.sources, args.data, args.fringe, args.output)
