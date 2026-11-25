"""Build exclusive ground coverage from the existing Paris and London sources."""

import argparse
import math
import struct
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from rasterio.features import rasterize
from rasterio.transform import from_bounds
from scipy.ndimage import distance_transform_edt, uniform_filter
from shapely import Polygon
from zstandard import ZstdCompressor, ZstdDecompressor

from build_city_models import RECORD, features, london_parks, read
from build_london_city_ground import GROUP as LONDON, GUTTER as LONDON_GUTTER
from build_paris_city_ground import GUTTER as PARIS_GUTTER, STREETS_PREFIX
from city_ground_pack import read_city_coverage

PARIS = (1.966, 48.67, 2.692, 49.058)
SIDE = 2048
SAMPLES = 2
UNKNOWN, ROOF, COURT, WORK, OPEN, WOOD = range(6)


class Grid:
    def __init__(self, bounds):
        self.bounds = bounds
        west, south, east, north = bounds
        self.side = SIDE * SAMPLES
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
    outer_courts = historical_urban & (grid.distance(roofs) <= 17.)
    dry_land = ~water & (classes != WOOD) & (classes != WORK)
    classes[(blocks | outer_courts) & dry_land & ~unbuilt] = COURT
    classes[unbuilt & dry_land] = OPEN
    classes[roofs & dry_land & ~unbuilt] = ROOF
    classes[water] = UNKNOWN
    streets = mosaic(grid, overlays, STREETS_PREFIX, PARIS_GUTTER).astype(np.float32) / 255.
    roads = streets[:, :, 0] + streets[:, :, 1] * (1. - streets[:, :, 0])
    return classes, roads


def mip_words(classes, roads):
    bands = [(classes == kind) * (1. - roads) for kind in range(ROOF, WOOD + 1)]
    bands.append(roads)
    for side in (SIDE >> level for level in range(SIDE.bit_length())):
        words = np.zeros((side, side), dtype="<u4")
        for index, band in enumerate(bands):
            bands[index] = area_average(band, side)
            words |= np.rint(bands[index] * 31.).astype(np.uint32) << (index * 5)
        yield words.tobytes()


def area_average(band, side):
    factor = band.shape[0] // side
    return band.reshape(side, factor, side, factor).mean((1, 3))


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
