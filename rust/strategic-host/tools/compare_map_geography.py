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
CELL_DEGREES = WATER_STEP / WATER_GRID
CELL_SHAPE = (WATER_ROWS * WATER_GRID, WATER_COLUMNS * WATER_GRID)
COAST, LAKE, RIVER, WETLAND, MEASURED_WATER, QHL_RIVER = (1 << i for i in range(6))


def refinement_inputs(land, lakes, rivers, worldcover):
    transform = from_origin(-180, 90, CELL_DEGREES, CELL_DEGREES)
    flags = np.zeros(CELL_SHAPE, dtype=np.uint8)
    for geometries, kind in (([g.boundary for g in land], COAST),
                             ([g.boundary for g in lakes], LAKE), (rivers, RIVER)):
        hit = rasterize(geometries, out_shape=CELL_SHAPE, transform=transform,
                        all_touched=True, dtype="uint8")
        flags[hit > 0] |= kind
    # Index native cache postings directly. A narrow observed river or wetland
    # can fall between all of the coarse grid centres and the game geometry.
    centres = (np.arange(worldcover.span) + .5) * 3 / worldcover.span
    for (south, west), path in worldcover.tiles.items():
        native = worldcover.codes(path)
        y = ((87 - south + centres) / CELL_DEGREES).astype(int)
        x = ((west + 180 + centres) / CELL_DEGREES).astype(int)
        for codes, kind in (((90, 95), WETLAND), ((80,), MEASURED_WATER)):
            rows, cols = np.nonzero(np.isin(native, codes))
            flags[y[rows], x[cols]] |= kind
    return flags


def cover_at(worldcover, lon, lat):
    rows = ((90 - lat) * (worldcover.span / 3)).astype(int)
    cols = ((lon + 180) * (worldcover.span / 3)).astype(int)
    tile_rows, local_rows = np.divmod(rows, worldcover.span)
    tile_cols, local_cols = np.divmod(cols, worldcover.span)
    result = np.zeros((len(lat), len(lon)), dtype=np.uint8)
    for y in np.unique(tile_rows):
        iy = np.flatnonzero(tile_rows == y)
        for x in np.unique(tile_cols):
            path = worldcover.tiles.get((87 - 3 * y, -180 + 3 * x))
            if path:
                ix = np.flatnonzero(tile_cols == x)
                result[np.ix_(iy, ix)] = worldcover.codes(path)[np.ix_(local_rows[iy], local_cols[ix])]
    return result


def sampled_qwg_cell(cell, texel_x, texel_y, paired=False):
    shape = (len(texel_y),) if paired else (len(texel_y), len(texel_x))
    if isinstance(cell, int):
        return np.full(shape, cell, dtype=np.uint8)
    seed, bands = cell
    px = (texel_x + .5) * (WATER_QUANTIZATION / TILE)
    py = (TILE - texel_y - .5) * (WATER_QUANTIZATION / TILE)
    bit_values = np.full(shape, seed, dtype=np.uint32)
    for band, edges in enumerate(bands):
        indices = np.flatnonzero(((py * (WATER_GRID * WATER_BANDS) / WATER_QUANTIZATION)
                                 .astype(int) % WATER_BANDS) == band)
        if not len(indices) or not len(edges):
            continue
        a, b, flags = edges.T
        lo, hi = a >> 16, b >> 16
        y = py[indices, None]
        active = (lo <= y) & (y < hi)
        ax, bx = (a & 65535).astype(float), (b & 65535).astype(float)
        crossing = ax + (bx - ax) * (y - lo) / (hi - lo)
        if paired:
            crosses = active & (px[indices, None] < crossing)
        else:
            crosses = active[:, None, :] & (px[None, :, None] < crossing[:, None, :])
        bit_values[indices] ^= np.bitwise_xor.reduce(np.where(crosses, flags, 0), axis=-1)
    return np.select(
        (bit_values >> 4 != 0, bit_values & 8 != 0, bit_values & 4 != 0,
         bit_values & 2 != 0, bit_values & 1 != 0),
        (np.where(bit_values & 1, INLAND, OCEAN), INLAND, LAND, INLAND, LAND),
        default=OCEAN,
    ).astype(np.uint8)


def refinement_side(cell, flag, neighbour_count):
    # The least complex selected cell still doubles the coarse posting rate.
    # Use native Z7 texel centres at intersecting features and dense water edges.
    if flag & WETLAND or (flag & (COAST | LAKE) and flag & (RIVER | QHL_RIVER | MEASURED_WATER)):
        return 32
    if not isinstance(cell, int):
        edge_counts = sum(len(band) for band in cell[1])
        return 32 if edge_counts >= 32 or neighbour_count >= 24 else 16
    return 16 if flag & (RIVER | QHL_RIVER) and neighbour_count >= 12 else 8 if flag else 0


def qhl_midpoints(path, flags):
    records = qhl_records(path)
    end_points = records["coordinates"]
    if not np.isfinite(end_points).all() or (np.abs(end_points) > [180, 90]).any():
        raise ValueError("Invalid QHL coordinates")
    lon = end_points[:, :, 0].astype(float)
    lat = end_points[:, :, 1].mean(axis=1, dtype=float)
    lon = (lon[:, 0] + ((lon[:, 1] - lon[:, 0] + 180) % 360 - 180) / 2 + 180) % 360 - 180
    x = (lon + 180) / WATER_STEP
    y = np.minimum((90 - lat) / WATER_STEP, np.nextafter(float(WATER_ROWS), 0))
    col, row = (x * WATER_GRID).astype(int), (y * WATER_GRID).astype(int)
    flags[row, col] |= QHL_RIVER
    page = (row // WATER_GRID) * WATER_COLUMNS + col // WATER_GRID
    cell = (row % WATER_GRID) * WATER_GRID + col % WATER_GRID
    key = page * WATER_GRID**2 + cell
    order = np.argsort(key, kind="stable")
    offsets = np.searchsorted(key[order], np.arange(WATER_COLUMNS * WATER_ROWS * WATER_GRID**2 + 1))
    return (x[order] % 1) * TILE - .5, (y[order] % 1) * TILE - .5, offsets


def compare_adaptive(args, worldcover, land, lakes, rivers):
    flags = refinement_inputs(land, lakes, rivers, worldcover)
    river_x, river_y, river_offsets = qhl_midpoints(args.terrain / "river-centrelines.qhl", flags)
    paths = [args.terrain / f"{z}.qpk" for z in range(PACK_MAX_LEVEL + 1)]
    dim = TILE + 2 * GUTTER
    dims = (dim, dim)
    cover_codes = np.asarray(LAND_COVER_CODES, dtype=np.uint8)
    decoder = ZstdDecompressor()
    cell_width = TILE // WATER_GRID
    prior_pages = sum(2 << (2 * z) for z in range(7))
    prior_cover_pages = 2 << 12
    pages = []
    with (args.terrain / "water-geometry.qwg").open("rb") as qwg, \
            (args.terrain / "hydrology-color.qhw").open("rb") as qhw, \
            (args.terrain / "landscape-cover-v2.qsc").open("rb") as qsc, paths[7].open("rb") as qpk:
        offsets, kinds = water_pack_index(qwg)
        overrides = read_color_overrides(qhw, paths)
        if qsc.read(20) != Struct("<8sIII").pack(b"WWOZ7LC2", WATER_COLUMNS, WATER_ROWS, dim):
            raise ValueError("Expected the installed Z6–Z7 QSC")
        covers = page_offsets(qsc, prior_cover_pages + len(kinds), dim ** 2 + 256)
        pack = LevelPack(qpk, 7, COMPACT_VERSION)
        for page, kind in enumerate(kinds):
            kind = int(kind)
            y, x = divmod(page, WATER_COLUMNS)
            region = flags[y * WATER_GRID:(y + 1) * WATER_GRID, x * WATER_GRID:(x + 1) * WATER_GRID]
            if kind in CLASS_NAMES and not region.any():
                pages.append({"tile": [7, x, y], "sampling": "global_grid", "data": "unverified",
                              "reference": "limited", "game": "unverified", "dynamic": "unverified"})
                continue
            start, end = map(int, offsets[page:page + 2])
            qwg.seek(start)
            cells = water_payload_cells(kind, qwg.read(end - start))
            mixed = sum(not isinstance(cell, int) for cell in cells)
            color, _ = pack.at(x, y)
            base = np.asarray(Image.frombytes("RGBA", dims, color.tobytes(), "bcn", (7, "BC7")))
            start, end = map(int, overrides[prior_pages + page:prior_pages + page + 2])
            surface = base
            if start != end:
                qhw.seek(start)
                raw = decoder.decompress(qhw.read(end - start), max_output_size=dim ** 2)
                surface = np.asarray(Image.frombytes("RGBA", dims, raw, "bcn", (7, "BC7")))
            start, end = map(int, covers[prior_cover_pages + page:prior_cover_pages + page + 2])
            cover = np.zeros(dims, dtype=np.uint8)
            if start != end:
                qsc.seek(start)
                raw = decoder.decompress(qsc.read(end - start), max_output_size=dim ** 2)
                cover = cover_codes[np.frombuffer(raw, dtype=np.uint8)].reshape(dims)
            strata = Counter()
            evidence = Counter()
            layers = Counter()
            examples = {}
            for (row, col), flag in np.ndenumerate(region):
                cell = cells[(WATER_GRID - 1 - row) * WATER_GRID + col]
                side = refinement_side(cell, flag, mixed)
                if not side:
                    continue
                stride = cell_width // side
                axis = np.arange(side) * stride + stride // 2
                tx, ty = col * cell_width + axis, row * cell_width + axis
                lon = -180 + (x + (tx + .5) / TILE) * WATER_STEP
                lat = 90 - (y + (ty + .5) / TILE) * WATER_STEP
                geom = sampled_qwg_cell(cell, tx, ty)
                known = cover_at(worldcover, lon, lat)
                texels = np.ix_(ty + GUTTER, tx + GUTTER)
                qpk_wet = base[texels][..., 3] >= 128
                qhw_wet = surface[texels][..., 3] >= 128
                qwg_wet = geom != LAND
                packed = cover[texels]
                strata[f"{side * side}_samples_per_cell"] += 1
                strata["coast_cells"] += bool(flag & COAST)
                strata["lake_shore_cells"] += bool(flag & LAKE)
                strata["river_cells"] += bool(flag & RIVER)
                strata["qhl_cells"] += bool(flag & QHL_RIVER)
                strata["wetland_or_mangrove_cells"] += bool(flag & WETLAND)
                strata["estuary_or_delta_candidates"] += bool(flag & COAST and flag & (RIVER | WETLAND))
                evidence["worldcover_observed_samples"] += int((known != 0).sum())
                evidence["worldcover_water_samples"] += int((known == 80).sum())
                evidence["worldcover_snow_ice_samples"] += int((known == 70).sum())
                comparisons = (
                    (evidence, "worldcover_water_qwg_land", (known == 80) & ~qwg_wet),
                    (evidence, "worldcover_snow_ice_qwg_water", (known == 70) & qwg_wet),
                    (evidence, "worldcover_water_rendered_fallback_land", (known == 80) & ~qhw_wet),
                    (layers, "qpk_vs_qhw_alpha", qpk_wet != qhw_wet),
                    (layers, "qwg_water_qhw_or_qpk_fallback_land", qwg_wet & ~qhw_wet),
                    (layers, "qwg_land_qhw_or_qpk_fallback_water", ~qwg_wet & qhw_wet),
                    (layers, "qsc_water_qwg_land", (packed == 80) & ~qwg_wet),
                    (layers, "qsc_snow_ice_qwg_water", (packed == 70) & qwg_wet),
                    (layers, "qsc_vs_same_source_worldcover", (known != 0) & (packed != known)),
                )
                for counts, name, clash in comparisons:
                    count = int(clash.sum())
                    if count:
                        counts[name] += count
                        if name not in examples:
                            iy, ix = np.unravel_index(clash.argmax(), clash.shape)
                            examples[name] = [round(float(lon[ix]), 7), round(float(lat[iy]), 7)]
                if flag & QHL_RIVER:
                    first = page * WATER_GRID**2 + row * WATER_GRID + col
                    start, end = river_offsets[first:first + 2]
                    x_at, y_at = river_x[start:end], river_y[start:end]
                    qhl_area = sampled_qwg_cell(cell, x_at, y_at, paired=True)
                    x_at = (x_at + .5).astype(int) + GUTTER
                    y_at = (y_at + .5).astype(int) + GUTTER
                    layers["qhl_midpoints"] += len(qhl_area)
                    layers["qhl_on_qwg_inland"] += int((qhl_area == INLAND).sum())
                    layers["qhl_on_qwg_ocean"] += int((qhl_area == OCEAN).sum())
                    layers["qhl_on_qwg_land_qsc_water"] += int(((qhl_area == LAND) &
                                                               (cover[y_at, x_at] == 80)).sum())
                    layers["qhl_on_qwg_land_qhw_or_qpk_water"] += int(((qhl_area == LAND) &
                                                                     (surface[y_at, x_at, 3] >= 128)).sum())
            pages.append({"tile": [7, x, y], "sampling": "adaptive", "data": "pass",
                          "reference": "limited", "game": "unverified", "dynamic": "unverified",
                          "strata": dict(+strata), "independent_screening": dict(+evidence),
                          "layer_conflicts": dict(layers), "examples": examples})
            if x == WATER_COLUMNS - 1 and (y + 1) % 16 == 0:
                print(f"Adaptive rows {y + 1}/{WATER_ROWS}", flush=True)
    return {
        "scope": "Z7 cells at 8, 16 or 32 postings per axis; nominal N–S intervals 2443, 1222 or 611 m",
        "coarse_scope": "Stable cells use the separate global grid; no adaptive claim for those cells",
        "references": {
            "independent_screening": "ESA WorldCover 2021 against QWG; Natural Earth routes refinement",
            "same_source": "QSC compared to its ESA classification cache",
            "layer_conflicts": "Asset differences at the same positions; not a geography verdict",
            "qhl": "All reach midpoints classified against exact QWG and co-located QPK/QHW and QSC. Wet midpoints require a game check for duplicate strokes; a dry midpoint can be an intended schematic river.",
            "limits": "562 postings per 3 degrees in this cache; land-cover classes do not resolve tidal stage, historic banks, or glacier grounding",
        },
        "summary": {key: dict(sum((Counter(p.get(key, {})) for p in pages), Counter()))
                    for key in ("strata", "independent_screening", "layer_conflicts")},
        "pages": pages,
    }


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


def qhl_records(path):
    with path.open("rb") as file:
        if file.read(len(RIVER_MAGIC)) != RIVER_MAGIC:
            raise ValueError("Invalid QHL magic")
    size = path.stat().st_size - len(RIVER_MAGIC)
    if size < 0 or size % RIVER_SEGMENT.itemsize:
        raise ValueError("Invalid QHL record length")
    return np.memmap(path, mode="r", offset=len(RIVER_MAGIC), dtype=RIVER_SEGMENT)


def qhl_support(path, ice):
    records = qhl_records(path)
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
    parser.add_argument("--adaptive-only", action="store_true",
                        help="Repeat the detailed water checks without the coarse global comparison")
    args = parser.parse_args()
    ne_land = physical_shapes(args.natural_earth, "land")
    ne_lakes = physical_shapes(args.natural_earth, "lakes")
    rivers = physical_shapes(args.natural_earth, "rivers_lake_centerlines")
    worldcover = LandCover(args.worldcover, native=True)
    result = {
        "terrain": str(args.terrain.resolve()),
        "references": {name: str(getattr(args, name).resolve()) if getattr(args, name) else None
                       for name in ("natural_earth", "shoreline", "shoreline_ponds", "worldcover",
                                    "relief", "antarctic_coast")},
        "adaptive_hydrology": compare_adaptive(args, worldcover, ne_land, ne_lakes, rivers),
    }
    if not args.adaptive_only:
        result.update(compare_global(args, worldcover, ne_land, ne_lakes, rivers))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(prefix="geography-", dir=args.output.parent) as scratch:
        report = Path(scratch) / args.output.name
        with report.open("w", encoding="utf-8") as file:
            json.dump(result, file, indent=2, allow_nan=False)
            file.write("\n")
        report.replace(args.output)


def compare_global(args, worldcover, ne_land, ne_lakes, rivers):
    relief, relief_resolution = relief_grid(args.relief)
    glaciers = physical_shapes(args.natural_earth, "glaciated_areas")
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
    return {
        "global_grid": {"width": WIDTH, "height": HEIGHT, "posting_degrees": DEGREES,
                        "relief_reference_arcminutes": relief_resolution},
        "qwg": qwg_result, "qhl_and_river_surfaces": river_result, "qpk_with_qhw": qpk, "qsc": qsc,
    }


if __name__ == "__main__":
    main()
