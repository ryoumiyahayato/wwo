"""Compare the installed global map data with separately compiled geographic references."""

import argparse
from collections import Counter
from io import BytesIO
import json
import math
from pathlib import Path
from struct import Struct
from tempfile import TemporaryDirectory
from zipfile import ZipFile

import numpy as np
from PIL import Image
from pyproj import CRS, Transformer
import rasterio
from rasterio.features import rasterize
from rasterio.transform import from_origin
from scipy.ndimage import minimum_filter
from scipy.spatial import cKDTree
import shapefile
from shapely import get_coordinates, get_parts, make_valid, segmentize
from shapely.geometry import Point
from zstandard import ZstdDecompressor

from build_natural_terrain import (
    COMPACT_VERSION, GUTTER, LAND_COVER_CODES, PACK_MAX_LEVEL, RIVER_MAGIC, RIVER_SEGMENT, TILE,
    WATER_BANDS, WATER_COLUMNS, WATER_GRID, WATER_QUANTIZATION, WATER_ROWS,
    WATER_STEP, LandCover, LevelPack, physical_shapes, polygon_parts, shoreline_sources,
    water_pack_index, water_payload_cells,
)
from patrol_water_geometry import WaterProbes

SAMPLES_PER_PAGE = 32
WIDTH = WATER_COLUMNS * SAMPLES_PER_PAGE
HEIGHT = WATER_ROWS * SAMPLES_PER_PAGE
DEGREES = 360 / WIDTH
TRANSFORM = from_origin(-180, 90, DEGREES, DEGREES)
LAND, OCEAN, INLAND = 1, 2, 3
CLASS_NAMES = {LAND: "land", OCEAN: "ocean", INLAND: "inland"}
EARTH_KM = 6371.0088
CONTINENT_INTERIORS = [Point(lon, lat) for lon, lat in
                       ((20, 5), (0, -85), (135, -25), (90, 45), (-105, 40), (-65, -15))]


def mask(shapes):
    return rasterize(shapes, out_shape=(HEIGHT, WIDTH), transform=TRANSFORM,
                     dtype="uint8", fill=0).astype(bool)


def shoreline_mask(shoreline, ponds):
    # GSHHG levels are nested. Paint Antarctica's ice front over the ocean first.
    levels = {level: [] for level in (1, 2, 3, 4, 5)}
    for level, geometry in shoreline_sources(shoreline, ponds):
        levels[level].append(geometry)
    order = (5, 1, 2, 3, 4)
    classes = {1: LAND, 2: INLAND, 3: LAND, 4: INLAND, 5: LAND}
    return rasterize(((geometry, classes[level]) for level in order for geometry in levels[level]),
                     out_shape=(HEIGHT, WIDTH), transform=TRANSFORM, dtype="uint8", fill=OCEAN)


def worldcover_mask(source, center=.5):
    codes = np.zeros((HEIGHT, WIDTH), dtype=np.uint8)
    for (south, west), path in source.tiles.items():
        north = south + 3
        i0 = math.ceil((west + 180) / DEGREES - center)
        i1 = math.ceil((west + 183) / DEGREES - center)
        j0 = math.ceil((90 - north) / DEGREES - center)
        j1 = math.ceil((93 - north) / DEGREES - center)
        tile = source.codes(path)
        if tile.shape != (source.span, source.span):
            raise ValueError(f"Invalid WorldCover cache image at {path}")
        ix = ((-180 + (np.arange(i0, i1) + center) * DEGREES - west) * source.span / 3).astype(int)
        iy = ((north - 90 + (np.arange(j0, j1) + center) * DEGREES) * source.span / 3).astype(int)
        codes[j0:j1, i0:i1] = tile[np.ix_(iy, ix)]
    return codes


def relief_grid(path):
    with rasterio.open(path) as source:
        transform = source.transform
        if (transform.a <= 0 or transform.e >= 0 or transform.b or transform.d
                or source.width * transform.a < 359 or source.height * -transform.e < 179):
            raise ValueError("Expected a north-up global geographic elevation grid")
        lon = -180 + (np.arange(WIDTH) + .5) * DEGREES
        lat = 90 - (np.arange(HEIGHT) + .5) * DEGREES
        # Some NOAA ERDDAP products store longitude as 0 to 360.
        west, north = transform * (.5, .5)
        if west >= 0:
            lon %= 360
        grid = source.read(1, masked=True).astype(np.float32).filled(np.nan)
        # A partial ERDDAP file can have a complete header with unread cells
        # filled with zero. A global relief grid must have ocean bathymetry.
        if np.count_nonzero(np.isfinite(grid) & (grid != 0)) < grid.size * .9:
            raise ValueError(f"Global relief contains more than 10% blank or zero postings: {path}")
        rows = np.rint((lat - north) / transform.e).astype(int).clip(0, source.height - 1)
        columns = np.rint((lon - west) / transform.a).astype(int).clip(0, source.width - 1)
        return grid[np.ix_(rows, columns)], [transform.a * 60, -transform.e * 60]


def qwg_classes(cells):
    result = np.empty((SAMPLES_PER_PAGE, SAMPLES_PER_PAGE), dtype=np.uint8)
    samples_per_cell = SAMPLES_PER_PAGE // WATER_GRID
    positions = (np.arange(SAMPLES_PER_PAGE) + .5) / SAMPLES_PER_PAGE
    quantized = positions * WATER_QUANTIZATION
    band_index = (positions * WATER_GRID * WATER_BANDS).astype(int) % WATER_BANDS
    for index, cell in enumerate(cells):
        row, column = divmod(index, WATER_GRID)
        y, x = row * samples_per_cell, column * samples_per_cell
        block = result[y:y + samples_per_cell, x:x + samples_per_cell]
        if isinstance(cell, int):
            block[:] = cell
            continue
        seed, bands = cell
        for j in range(samples_per_cell):
            edges = bands[band_index[y + j]]
            py = quantized[y + j]
            a, b, flags = edges.T
            lower, upper = a >> 16, b >> 16
            mask = (lower <= py) & (py < upper)
            origin = (a[mask] & 65535).astype(float)
            endpoint = (b[mask] & 65535).astype(float)
            crossing = origin + (endpoint - origin) * (py - lower[mask]) / (upper[mask] - lower[mask])
            crosses = quantized[x:x + samples_per_cell, None] < crossing
            bits = seed ^ np.bitwise_xor.reduce(np.where(crosses, flags[mask], 0), axis=1)
            block[j] = np.select(
                (bits >> 4 != 0, bits & 8 != 0, bits & 4 != 0, bits & 2 != 0, bits & 1 != 0),
                (np.where(bits & 1, INLAND, OCEAN), INLAND, LAND, INLAND, LAND),
                default=OCEAN,
            )
    return result[::-1]


def classify_qwg(path):
    actual = np.empty((HEIGHT, WIDTH), dtype=np.uint8)
    with path.open("rb") as source:
        offsets, classes = water_pack_index(source)
        source.seek(int(offsets[0]))
        for page, kind in enumerate(classes):
            y, x = divmod(page, WATER_COLUMNS)
            block = actual[y * SAMPLES_PER_PAGE:(y + 1) * SAMPLES_PER_PAGE,
                           x * SAMPLES_PER_PAGE:(x + 1) * SAMPLES_PER_PAGE]
            payload = source.read(int(offsets[page + 1] - offsets[page]))
            if kind in CLASS_NAMES and not payload:
                block[:] = kind
            else:
                block[:] = qwg_classes(water_payload_cells(kind, payload))
            if x == WATER_COLUMNS - 1 and (y + 1) % 16 == 0:
                print(f"QWG rows {y + 1}/{WATER_ROWS}", flush=True)
    return actual


def matrix(ref, actual):
    paired = np.bincount((ref * 4 + actual).ravel(), minlength=16).reshape(4, 4)
    return {name: {label: int(paired[i, j]) for j, label in CLASS_NAMES.items()}
            for i, name in CLASS_NAMES.items()}


def biggest_pages(disagreements, level):
    ny, nx = 1 << level, 2 << level
    h, w = disagreements.shape
    by_tile = disagreements.reshape(ny, h // ny, nx, w // nx).sum(axis=(1, 3))
    descending = np.argsort(-by_tile.ravel().astype(np.int64), kind="stable")
    return {
        "tiles_with_disagreement": int(np.count_nonzero(by_tile)),
        "largest_tile_counts": [
            {"x": int(i % nx), "y": int(i // nx), "samples": int(by_tile.flat[i])}
            for i in descending[:20] if by_tile.flat[i]
        ],
    }


def interior(mask):
    return minimum_filter(mask, size=3, mode=("constant", "wrap"))


def worldcover_evidence(classes, codes):
    # Erode single grid postings so positional offsets near the edge are counted separately.
    groups = {}
    for code, name in ((80, "permanent_water"), (70, "snow_ice")):
        ref = codes == code
        inside = interior(ref)
        # Class 80 may observe a river, lake, or tidal water body. Class 70
        # indicates terrain expected to be above water and includes polar snow.
        clash = classes == LAND if code == 80 else classes != LAND
        groups[name] = {
            "source_samples": int(ref.sum()),
            "all_disagreements": int(np.count_nonzero(ref & clash)),
            "core_samples": int(inside.sum()),
            "core_disagreements": int(np.count_nonzero(inside & clash)),
            **biggest_pages(inside & clash, 7),
        }
    return groups


def compare_qwg(path, ne_land, ne_lakes, codes):
    classes = classify_qwg(path)
    coast = mask(ne_land)
    lakes = mask(ne_lakes)
    reference = np.where(lakes, INLAND, np.where(coast, LAND, OCEAN)).astype(np.uint8)
    stable = np.zeros(reference.shape, dtype=bool)
    for code in CLASS_NAMES:
        stable |= interior(reference == code)
    clash = (reference != classes) & stable
    report = {
        "pages": WATER_COLUMNS * WATER_ROWS, "grid_samples": WIDTH * HEIGHT,
        "natural_earth_all_samples": matrix(reference, classes),
        "natural_earth_away_from_generalized_boundaries": matrix(reference[stable], classes[stable]),
        "natural_earth_off_boundary_disagreements": biggest_pages(clash, 7),
        "esa_worldcover": worldcover_evidence(classes, codes),
    }
    return report, classes


def compare_antarctica(path, surface):
    """Evaluate grounded land and floating ice separately using the BAS SCAR ADD."""
    scar = {"land": 1, "ice shelf": 2, "ice tongue": 3, "rumple": 4}
    crs = CRS.from_epsg(3031)
    with ZipFile(path) as archive:
        shp = next(name for name in archive.namelist() if name.endswith(".shp"))
        stem = shp.removesuffix(".shp")
        if not CRS.from_wkt(archive.read(stem + ".prj").decode()).equals(crs):
            raise ValueError("Expected SCAR ADD polygons in EPSG:3031")
        with shapefile.Reader(shp=BytesIO(archive.read(shp)),
                              dbf=BytesIO(archive.read(stem + ".dbf"))) as source:
            # Native polar coordinates avoid introducing an artificial 180-degree boundary.
            shapes = [(feature.shape.__geo_interface__, scar[feature.record["surface"]])
                      for feature in source.iterShapeRecords()]
    metres = 1000
    extent = 3_500_000
    side = 2 * extent // metres
    grid = rasterize(shapes, out_shape=(side, side), dtype="uint8",
                     transform=from_origin(-extent, extent, metres, metres))
    del shapes
    lon = -180 + (np.arange(WIDTH) + .5) * DEGREES
    first_row = math.ceil(150 / DEGREES - .5)
    lat = 90 - (np.arange(first_row, HEIGHT) + .5) * DEGREES
    reference = np.zeros((len(lat), WIDTH), dtype=np.uint8)
    polar = Transformer.from_crs(4326, crs, always_xy=True)
    for start in range(0, len(lat), 32):
        ll = np.meshgrid(lon, lat[start:start + 32])
        east, north = polar.transform(*ll)
        ix = ((east + extent) / metres).astype(int)
        iy = ((extent - north) / metres).astype(int)
        reference[start:start + len(east)] = grid[iy, ix]
    result = {}
    surface = surface[first_row:]
    for name, code in {"open_ocean": 0, **scar}.items():
        ref = reference == code
        core = interior(ref)
        result[name] = {"reference_samples": int(ref.sum()), "core_samples": int(core.sum()),
                        "qwg_on_core": {name: int(np.count_nonzero(core & (surface == klass)))
                                        for klass, name in CLASS_NAMES.items()}}
    return {"source": str(path.resolve()), "reference_raster_metres": metres, "south_of_degrees": -60,
            "surface_counts": result}


def raster_indices(points):
    cols = (((points[:, 0] + 180) % 360) / DEGREES).astype(int)
    rows = ((90 - points[:, 1]) / DEGREES).astype(int).clip(0, HEIGHT - 1)
    return rows, cols


def feature_samples(probes, geometries, expected, islands=False):
    candidates = []
    for geometry in geometries:
        for polygon in polygon_parts(geometry if geometry.is_valid else make_valid(geometry)):
            point = polygon.representative_point()
            if islands and any(polygon.covers(point) for point in CONTINENT_INTERIORS):
                continue
            # Holes remain holes in the representative-point calculation.
            if (islands and polygon.area > 0) or not islands:
                candidates.append((point.x, point.y, polygon.area))
    candidates.sort(key=lambda sample: (int((90 - sample[1]) / WATER_STEP),
                                         int((sample[0] + 180) / WATER_STEP)))
    counts = Counter()
    disagreements = []
    for lon, lat, area in candidates:
        actual = probes.area(lon, lat)
        counts[CLASS_NAMES[actual]] += 1
        if actual not in expected:
            disagreements.append((area, lon, lat, CLASS_NAMES[actual]))
    disagreements.sort(reverse=True)
    return {"features": len(candidates), "expected_classes": [CLASS_NAMES[c] for c in expected],
            "actual_classes": dict(counts),
            "largest_disagreements": [
                {"lon": lon, "lat": lat, "area_degrees2": area, "actual": actual}
                for area, lon, lat, actual in disagreements[:20]
            ]}


def sphere_xy(coordinates):
    lon, lat = np.radians(coordinates).T
    return np.column_stack((np.cos(lat) * np.cos(lon), np.cos(lat) * np.sin(lon), np.sin(lat)))


def qhl_support(path, ice):
    with path.open("rb") as file:
        if file.read(len(RIVER_MAGIC)) != RIVER_MAGIC:
            raise ValueError("Invalid QHL magic")
    size = path.stat().st_size - len(RIVER_MAGIC)
    if size < 0 or size % RIVER_SEGMENT.itemsize:
        raise ValueError("Invalid QHL record length")
    records = np.memmap(path, mode="r", offset=len(RIVER_MAGIC), dtype=RIVER_SEGMENT)
    support = []
    ice_segments = 0
    ice_examples = []
    for start in range(0, len(records), 32768):
        chunk = records["coordinates"][start:start + 32768].astype(float)
        if not np.isfinite(chunk).all() or (np.abs(chunk) > [180, 90]).any():
            raise ValueError(f"Invalid QHL coordinates at record block {start}")
        delta = chunk[:, 1] - chunk[:, 0]
        delta[:, 0] = (delta[:, 0] + 180) % 360 - 180
        # Shortest longitude difference is required for segments crossing the date line.
        scale = np.cos(np.radians(np.min(np.abs(chunk[:, :, 1]), axis=1)))
        length = np.hypot(delta[:, 0] * scale, delta[:, 1]) * (math.pi * EARTH_KM / 180)
        steps = np.maximum(1, np.ceil(length)).astype(int)
        base = np.cumsum(steps + 1) - steps - 1
        index = np.repeat(np.arange(len(chunk)), steps + 1)
        fraction = (np.arange(len(index)) - base[index]) / steps[index]
        points = chunk[index, 0] + delta[index] * fraction[:, None]
        support.append(sphere_xy(points))
        on_ice = ice[raster_indices(points)]
        wholly = np.add.reduceat(on_ice, base) == steps + 1
        ice_segments += int(wholly.sum())
        free_examples = 20 - len(ice_examples)
        if free_examples > 0:
            ice_examples.extend(chunk[wholly, 0][:free_examples].tolist())
    return cKDTree(np.concatenate(support)), {
        "segments": len(records), "segment_samples": sum(len(x) for x in support),
        "segments_wholly_within_agreed_ice_grid": ice_segments, "sample_starts": ice_examples,
    }


def compare_rivers(probes, qhl, rivers, ice):
    tree, qhl_counts = qhl_support(qhl, ice)
    # A 0.04-degree interval is at most 4.5 km, with shorter intervals at high latitude.
    points = np.asarray([
        point for feature in rivers for line in get_parts(feature)
        for point in get_coordinates(segmentize(line, max_segment_length=.04))
    ])
    chord, _ = tree.query(sphere_xy(points), workers=4)
    km = 2 * EARTH_KM * np.arcsin(np.minimum(1., chord / 2))
    y = ((90 - points[:, 1]) / WATER_STEP).astype(int)
    x = ((points[:, 0] + 180) / WATER_STEP).astype(int)
    order = np.argsort(y * WATER_COLUMNS + x, kind="stable")
    on_surface = np.zeros(len(points), dtype=bool)
    for i in order:
        on_surface[i] = probes.area(*points[i]) != LAND
    no_support = ~on_surface & (km > 5)
    farthest = np.flatnonzero(no_support)
    farthest = farthest[np.argsort(-km[farthest], kind="stable")[:20]]
    return {"natural_earth_features": len(rivers), "reference_line_samples": len(points),
            "on_qwg_water": int(on_surface.sum()),
            "qhl_within_km": {str(limit): int((km <= limit).sum()) for limit in (1, 2, 5)},
            "on_qwg_water_or_qhl_within_5_km": int((~no_support).sum()),
            "farthest_reference_samples_without_support": [
                {"lon": float(points[i, 0]), "lat": float(points[i, 1]), "qhl_km": round(km[i], 2)}
                for i in farthest],
            "qhl": qhl_counts}


def page_offsets(file, pages, limit):
    offsets = np.frombuffer(file.read((pages + 1) * 8), dtype="<u8")
    if (len(offsets) != pages + 1 or offsets[0] != file.tell()
            or offsets[-1] != Path(file.name).stat().st_size or np.any(offsets[:-1] > offsets[1:])
            or np.any(np.diff(offsets) > limit)):
        raise ValueError(f"Invalid map page offsets in {file.name}")
    return offsets


def read_color_overrides(file, paths):
    index = Struct("<8s8Q")
    header = file.read(index.size)
    expected = index.pack(b"WWOHYD01", *(p.stat().st_size for p in paths))
    if header != expected:
        raise ValueError("QHW header and QPK level files do not match")
    return page_offsets(file, sum(2 << (2 * z) for z in range(PACK_MAX_LEVEL + 1)),
                        (TILE + 2 * GUTTER) ** 2 + 1024)


def compare_qsc(path, worldcover, geographic_surface):
    dim = TILE + 2 * GUTTER
    header = Struct("<8sIII")
    decoder = ZstdDecompressor()
    class_count = len(LAND_COVER_CODES)
    classes = np.asarray(LAND_COVER_CODES, dtype=np.uint8)
    result = {}
    with path.open("rb") as file:
        if file.read(header.size) != header.pack(b"WWOZ7LC2", WATER_COLUMNS, WATER_ROWS, dim):
            raise ValueError("Expected the installed Z6–Z7 QSC")
        offsets = page_offsets(file, sum(2 << (2 * z) for z in (6, 7)), dim ** 2 + 256)
        page = 0
        for z in (6, 7):
            ny, nx = 1 << z, 2 << z
            side = WIDTH // nx
            stride = TILE // side
            texels = GUTTER + np.arange(side) * stride + stride // 2
            cache = worldcover_mask(worldcover, (stride // 2 + .5) / stride)
            packed = np.zeros(cache.shape, dtype=np.uint8)
            nonempty = 0
            for y in range(ny):
                for x in range(nx):
                    length = int(offsets[page + 1] - offsets[page])
                    if length:
                        raw = decoder.decompress(file.read(length), max_output_size=dim ** 2)
                        cover = np.frombuffer(raw, dtype=np.uint8)
                        if cover.size != dim ** 2 or cover.max() >= class_count:
                            raise ValueError(f"Invalid QSC samples at Z{z}/{x}/{y}")
                        packed[y * side:(y + 1) * side, x * side:(x + 1) * side] = classes[
                            cover.reshape(dim, dim)[np.ix_(texels, texels)]]
                        nonempty += 1
                    page += 1
            cache_known = cache != 0
            observed = int(cache_known.sum())
            matched = int(np.count_nonzero((packed == cache) & cache_known))
            unknown_packed = int(np.count_nonzero((packed == 0) & cache_known))
            conflict = {}
            for cover_code, name, expected in ((70, "snow_ice_on_water", LAND),
                                               (80, "permanent_water_on_land", None)):
                footprint = interior(packed == cover_code)
                is_land = geographic_surface == LAND
                disagreement = (is_land if expected is None else ~is_land) & footprint
                conflict[name] = {
                    "core_samples": int(footprint.sum()), "disagreements": int(disagreement.sum()),
                    **biggest_pages(disagreement, z),
                }
            result[z] = {"pages": nx * ny, "nonempty_pages": nonempty, "samples": WIDTH * HEIGHT,
                         "source_cache_nonzero_samples": observed, "same_source_cache_matches": matched,
                         "source_cache_nonzero_but_qsc_unknown": unknown_packed,
                         "packed_sample_counts_by_esa_code": {
                             str(int(code)): int(np.count_nonzero(packed == code)) for code in classes},
                         "surface_conflicts": conflict}
            print(f"QSC Z{z}: {nx * ny} indexed pages", flush=True)
    return result


def compare_qpk(path, level, coast, relief, qwg=None, qhw=None, color_offsets=None):
    # At wide scales a raster texel intentionally averages geography. Measure
    # its full footprint against the higher-resolution reference.
    side = min(TILE, WIDTH // (2 << level))
    reference_step = WIDTH // ((2 << level) * side)
    pack_step = TILE // side
    sample = GUTTER + np.arange(side) * pack_step + pack_step // 2
    source_index = np.ix_(sample, sample)
    results = Counter()
    layer_consistency = Counter()
    height_sums = Counter()
    tile_diffs = []
    height_outliers = []
    with path.open("rb") as file:
        pack = LevelPack(file, level, COMPACT_VERSION)
        span = side * reference_step
        page = sum(2 << (2 * z) for z in range(level))
        dims = ((TILE + 2 * GUTTER),) * 2
        decode = ZstdDecompressor()
        for y in range(pack.ny):
            for x in range(pack.nx):
                color, height = pack.at(x, y)
                raw = color.tobytes()
                if color_offsets is not None:
                    start, end = map(int, color_offsets[page:page + 2])
                    if start != end:
                        qhw.seek(start)
                        raw = decode.decompress(qhw.read(end - start), max_output_size=dims[0] ** 2)
                        results["hydrology_color_override_pages"] += 1
                page += 1
                rgba = np.asarray(Image.frombytes("RGBA", dims, raw, "bcn", (7, "BC7")))
                # Alpha encodes water coverage in the installed QPK.
                land = rgba[source_index][..., 3] < 128
                rect = np.s_[y * span:(y + 1) * span, x * span:(x + 1) * span]
                ref = coast[rect].reshape(side, reference_step, side, reference_step)
                solid_land = (ref == LAND).all(axis=(1, 3))
                solid_ocean = (ref == OCEAN).all(axis=(1, 3))
                solid_inland = (ref == INLAND).all(axis=(1, 3))
                mismatch = {
                    "land_decoded_as_water": int(np.count_nonzero(solid_land & ~land)),
                    "ocean_decoded_as_land": int(np.count_nonzero(solid_ocean & land)),
                    "inland_water_decoded_as_land": int(np.count_nonzero(solid_inland & land)),
                }
                results.update(mismatch)
                differences = sum(mismatch.values())
                if differences:
                    tile_diffs.append((differences, x, y))
                results.update({"tiles": 1, "samples": side * side,
                                "gshhg_land": int(solid_land.sum()), "gshhg_ocean": int(solid_ocean.sum()),
                                "gshhg_inland_water": int(solid_inland.sum())})
                offset = reference_step * (pack_step // 2 + .5) / pack_step
                ref_sample = np.minimum(reference_step - 1, int(offset))
                ref_height = relief[rect][ref_sample::reference_step, ref_sample::reference_step]
                pack_height = height[source_index]
                error = np.abs(pack_height.astype(np.float32) - ref_height)
                layer_consistency["gshhg_land_above_50_m_but_qpk_water"] += int(
                    np.count_nonzero(solid_land & (ref_height > 50) & ~land))
                layer_consistency["gshhg_ocean_below_50_m_but_qpk_land"] += int(
                    np.count_nonzero(solid_ocean & (ref_height < -50) & land))
                layer_consistency["gshhg_ocean_below_50_m_but_qpk_height_above_50_m"] += int(
                    np.count_nonzero(solid_ocean & (ref_height < -50) & (pack_height > 50)))
                if qwg is not None:
                    geom = qwg[rect].reshape(side, reference_step, side, reference_step)
                    geo_dry = (geom == LAND).all(axis=(1, 3))
                    geo_water = (geom != LAND).all(axis=(1, 3))
                    layer_consistency["gshhg_and_qwg_dry_but_qpk_water"] += int(
                        np.count_nonzero(solid_land & geo_dry & ~land))
                    layer_consistency["gshhg_and_qwg_wet_but_qpk_land"] += int(
                        np.count_nonzero((solid_ocean | solid_inland) & geo_water & land))
                for name, domain in (("land", solid_land), ("ocean", solid_ocean)):
                    valid = domain & np.isfinite(error)
                    e = error[valid]
                    prefix = name + "_"
                    height_sums[prefix + "samples"] += len(e)
                    height_sums[prefix + "absolute_error"] += float(e.sum(dtype=float))
                    height_sums[prefix + "over_200_m"] += int((e > 200).sum())
                    height_sums[prefix + "over_1000_m"] += int((e > 1000).sum())
                terrestrial = np.where(solid_land & np.isfinite(error), error, -1)
                iy, ix = np.unravel_index(np.argmax(terrestrial), terrestrial.shape)
                if terrestrial[iy, ix] > 200:
                    height_outliers.append((float(terrestrial[iy, ix]), x, y, int(ix), int(iy),
                                            int(pack_height[iy, ix]), float(ref_height[iy, ix])))
        print(f"QPK Z{level}: {results['tiles']} decoded tiles", flush=True)
    results["mixed_reference"] = results["samples"] - sum(
        results[key] for key in ("gshhg_land", "gshhg_ocean", "gshhg_inland_water"))
    return {
        "coverage": dict(results),
        "height_and_surface_consistency": dict(layer_consistency),
        "tiles_with_coverage_disagreement": len(tile_diffs),
        "largest_tile_coverage_disagreements": [
            {"x": x, "y": y, "samples": n} for n, x, y in sorted(tile_diffs, reverse=True)[:20]],
        "height": {name: {
            "samples": height_sums[f"{name}_samples"],
            "mean_absolute_error_m": round(height_sums[f"{name}_absolute_error"] /
                                           height_sums[f"{name}_samples"], 2)
            if height_sums[f"{name}_samples"] else None,
            "over_200_m": height_sums[f"{name}_over_200_m"],
            "over_1000_m": height_sums[f"{name}_over_1000_m"],
        } for name in ("land", "ocean")},
        "largest_terrestrial_height_disagreements": [
            {"x": x, "y": y, "lon": (x * TILE + int(sample[ix]) - GUTTER + .5)
                                    * 360 / (TILE * (2 << level)) - 180,
             "lat": 90 - (y * TILE + int(sample[iy]) - GUTTER + .5)
                         * 180 / (TILE * (1 << level)),
             "qpk_m": game, "reference_m": reference, "absolute_error_m": delta}
            for delta, x, y, ix, iy, game, reference in sorted(height_outliers, reverse=True)[:20]],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("terrain", "natural_earth", "shoreline", "worldcover", "relief", "output"):
        parser.add_argument(name, type=Path)
    parser.add_argument("--shoreline-ponds", type=Path)
    parser.add_argument("--antarctic-coast", type=Path, help="SCAR ADD EPSG:3031 polygon ZIP")
    args = parser.parse_args()
    relief, relief_resolution = relief_grid(args.relief)
    ne_land = physical_shapes(args.natural_earth, "land")
    ne_lakes = physical_shapes(args.natural_earth, "lakes")
    glaciers = physical_shapes(args.natural_earth, "glaciated_areas")
    rivers = physical_shapes(args.natural_earth, "rivers_lake_centerlines")
    worldcover = LandCover(args.worldcover, native=True)
    codes = worldcover_mask(worldcover)
    if not np.any(codes == 80) or not np.any(codes == 70):
        raise ValueError("WorldCover raster comparison expects water and snow/ice observations")
    ice = interior(mask(glaciers) & (codes == 70))
    qwg = args.terrain / "water-geometry.qwg"
    qhl = args.terrain / "river-centrelines.qhl"
    qwg_result, qwg_surface = compare_qwg(qwg, ne_land, ne_lakes, codes)
    if args.antarctic_coast:
        qwg_result["scar_add"] = compare_antarctica(args.antarctic_coast, qwg_surface)
    with qwg.open("rb") as file:
        probes = WaterProbes(file)
        qwg_result["island_points"] = feature_samples(probes, ne_land, (LAND,), islands=True)
        qwg_result["lake_points"] = feature_samples(probes, ne_lakes, (INLAND,))
        qwg_result["glacier_points"] = feature_samples(probes, glaciers, (LAND,))
        river_result = compare_rivers(probes, qhl, rivers, ice)
    print("Independent QWG/QHL geography comparison complete", flush=True)
    coast = shoreline_mask(args.shoreline, args.shoreline_ponds)
    paths = [args.terrain / f"{z}.qpk" for z in range(PACK_MAX_LEVEL + 1)]
    with (args.terrain / "hydrology-color.qhw").open("rb") as qhw:
        color_offsets = read_color_overrides(qhw, paths)
        qpk = {z: compare_qpk(path, z, coast, relief, qwg_surface, qhw, color_offsets)
               for z, path in enumerate(paths)}
    qsc = compare_qsc(args.terrain / "landscape-cover-v2.qsc", worldcover, qwg_surface)
    result = {
        "terrain": str(args.terrain.resolve()),
        "references": {name: str(getattr(args, name).resolve()) if getattr(args, name) else None
                       for name in ("natural_earth", "shoreline", "shoreline_ponds", "worldcover", "relief")},
        "global_grid": {"width": WIDTH, "height": HEIGHT, "posting_degrees": DEGREES,
                        "relief_reference_arcminutes": relief_resolution},
        "qwg": qwg_result, "qhl_and_river_surfaces": river_result, "qpk_with_qhw": qpk, "qsc": qsc,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(prefix="geography-", dir=args.output.parent) as scratch:
        report = Path(scratch) / args.output.name
        with report.open("w", encoding="utf-8") as file:
            json.dump(result, file, indent=2, allow_nan=False)
            file.write("\n")
        report.replace(args.output)


if __name__ == "__main__":
    main()
