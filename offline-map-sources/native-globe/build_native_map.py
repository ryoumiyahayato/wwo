"""Build the native globe from elevation and geographic vectors in EPSG:4326.

Inputs can be Natural Earth shapefile ZIPs or GeoJSON. DEM must be a
georeferenced raster with elevations in metres. No legacy atlas is read.
"""
import argparse
import json
from pathlib import Path
import zipfile
import zlib

import numpy as np
import rasterio
from rasterio.features import rasterize
from rasterio.transform import from_bounds
from rasterio.warp import reproject, Resampling
import shapefile
from shapely import make_valid
from shapely.geometry import Polygon, box, shape
from shapely.ops import unary_union
from shapely.strtree import STRtree


WIDTH, HEIGHT = 16384, 8192
BORDER_WIDTH, BORDER_HEIGHT = 512, 256
PAGE, GUTTER = 256, 4
TRANSFORM = from_bounds(-180, -90, 180, 90, WIDTH, HEIGHT)
SHAPE = HEIGHT, WIDTH


def features(path):
    if path.suffix.lower() == ".zip":
        with zipfile.ZipFile(path) as archive:
            shp = next(name for name in archive.namelist() if name.endswith(".shp"))
            with archive.open(shp) as stream:
                return [row.__geo_interface__ for row in shapefile.Reader(shp=stream).iterShapes()]
    return [row["geometry"] for row in read(path)["features"] if row["geometry"]]


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def mask(path, lines=False):
    return rasterize(
        features(path), out_shape=SHAPE, default_value=255, dtype="uint8",
        transform=TRANSFORM, all_touched=lines,
    )


def historical_owners(history, world):
    geometry_dir = history / "world_map/historical"
    display = read(history / "presentation/arabia_political_map_regions_1900.json")
    ids = {
        row["geometry_feature_id"]: i + 1 for i, row in enumerate(world["polities"])
        if row.get("geometry_feature_id") and not row["id"].startswith("political_map_region:")
    }
    display_ids = {row["id"]: i + 1 for i, row in enumerate(world["polities"])}

    def cells(rows):
        return unary_union([Polygon(row["outer"], row.get("holes", [])) for row in rows])

    partial = {key: cells(rows) for key, rows in display.get("partial_scope_masks", {}).items()}
    shapes, scoped = [], []
    for name in ("cshapes_1900_snapshot.json", "arabia_gulf_geography_1900.json"):
        for row in read(geometry_dir / name)["features"]:
            key = row["id"]
            geom = make_valid(shape(row["geometry"]))
            if key in display["scope_feature_ids"]:
                limit = partial.get(key)
                scoped.append(geom if limit is None else geom.intersection(limit))
                geom = Polygon() if limit is None else geom.difference(limit)
            if key in ids and not geom.is_empty:
                shapes.append((geom, ids[key]))
    scope = unary_union(scoped)
    for region in display["political_map_regions"]:
        key = region["id"]
        if key not in display_ids:
            raise ValueError(f"historical boundary has no matching polity: {key}")
        geom = scope.intersection(cells(region["mask_cells"]))
        if not geom.is_empty:
            shapes.append((geom, display_ids[key]))
    return shapes


def polygons(geometry):
    if geometry.geom_type == "Polygon":
        if not geometry.is_empty:
            yield geometry
    elif hasattr(geometry, "geoms"):
        for part in geometry.geoms:
            yield from polygons(part)


def write_borders(shapes, output):
    transform = from_bounds(-180, -90, 180, 90, BORDER_WIDTH, BORDER_HEIGHT)
    # The unmarked cells contain no source edge. Their sampled ID is exact
    # throughout the cell. Marked cells use the clipped source geometry.
    marked = rasterize(
        [geom.boundary for geom, _ in shapes], out_shape=(BORDER_HEIGHT, BORDER_WIDTH),
        dtype="uint8", default_value=1, transform=transform, all_touched=True,
    )
    geoms = [geom for geom, _ in shapes]
    tree = STRtree(geoms)
    owners = rasterize(shapes, out_shape=marked.shape, dtype="uint8", transform=transform)
    lookup = np.repeat(owners[:, :, None], 2, axis=2).astype("<u4")
    words = []
    for row, col in zip(*np.nonzero(marked)):
        west, north = transform * (int(col), int(row))
        east, south = transform * (int(col) + 1, int(row) + 1)
        bounds = box(west, south, east, north)
        start = len(words)
        for index in sorted(tree.query(bounds, predicate="intersects"), reverse=True):
            count = 0
            coordinates = []
            for polygon in polygons(geoms[index].intersection(bounds)):
                for ring in [polygon.exterior, *polygon.interiors]:
                    points = np.asarray(ring.coords, dtype=np.float64)
                    points -= (west, south)
                    points /= (east - west, north - south)
                    edges = np.column_stack((points[:-1], points[1:])).astype("<f4")
                    coordinates.extend(edges.view("<u4").ravel())
                    count += len(edges)
            if count:
                words.extend((shapes[index][1], count))
                words.extend(coordinates)
        # A nonempty interval identifies an edge cell. Equal words encode
        # the uniform polity of a cell through which no polygon passes.
        if len(words) != start:
            lookup[row, col] = start, len(words)
    data = np.asarray(words, dtype="<u4").tobytes()
    (output / "borders.z").write_bytes(zlib.compress(lookup.tobytes() + data, level=4))


def write_rivers(path, output):
    # Keep the source lines for close views. The index only selects visible segments.
    records = []
    for geometry in features(path):
        if geometry["type"] == "LineString":
            lines = [geometry["coordinates"]]
        elif geometry["type"] == "MultiLineString":
            lines = geometry["coordinates"]
        else:
            continue
        for line in lines:
            for (x, y, *_), (a, b, *_) in zip(line, line[1:]):
                if abs(x - a) > 180:
                    continue
                records.append([x, y, a, b])
    points = np.asarray(records, dtype="<f4")
    (output / "rivers.z").write_bytes(zlib.compress(points.tobytes(), level=4))


def average(values):
    h, w = values.shape
    return values.reshape(h // 2, 2, w // 2, 2).mean(axis=(1, 3), dtype=np.float32)


def encode(height, water, surface):
    values = np.clip(np.rint(height * 2 + 32768), 0, 65535).astype(np.uint16)
    out = np.empty((*height.shape, 4), dtype=np.uint8)
    out[:, :, 0] = values & 255
    out[:, :, 1] = values >> 8
    out[:, :, 2] = np.rint(water)
    out[:, :, 3] = np.rint(surface)
    return out


def build(args):
    world = read(args.world)
    if len(world["polities"]) > 255:
        raise ValueError("native globe polity identifiers must fit in one byte")
    height = np.full(SHAPE, np.nan, dtype=np.float32)
    with rasterio.open(args.dem) as dem:
        reproject(
            rasterio.band(dem, 1), height, src_crs=dem.crs or "EPSG:4326", dst_transform=TRANSFORM,
            dst_crs="EPSG:4326", dst_nodata=np.nan, resampling=Resampling.bilinear,
            num_threads=4,
        )
        scale, offset = dem.scales[0], dem.offsets[0]
        height *= scale
        height += offset
    if not np.isfinite(height).all():
        raise ValueError("DEM does not cover the complete WGS84 globe")

    land = mask(args.land)
    land[mask(args.lakes) != 0] = 0
    river = mask(args.rivers, lines=True)
    ice = mask(args.glaciers)
    surface = np.full(SHAPE, 128, dtype=np.uint8)
    surface[river != 0] = 0
    surface[ice != 0] = 255
    surface[land == 0] = 128
    water = 255 - land
    boundaries = historical_owners(args.history, world)
    del land, river, ice

    output = args.output
    fine = output / "detail"
    fine.mkdir(parents=True, exist_ok=True)
    write_rivers(args.rivers, output)
    write_borders(boundaries, output)
    (output / "land.z").write_bytes(zlib.compress(np.packbits(water[1::2, 1::2] == 0).tobytes(), level=4))
    for y in range(HEIGHT // PAGE):
        rows = np.arange(y * PAGE - GUTTER, (y + 1) * PAGE + GUTTER).clip(0, HEIGHT - 1)
        for x in range(WIDTH // PAGE):
            cols = np.arange(x * PAGE - GUTTER, (x + 1) * PAGE + GUTTER) % WIDTH
            ix = np.ix_(rows, cols)
            tile = encode(height[ix], water[ix], surface[ix])
            (fine / f"{x}-{y}.z").write_bytes(zlib.compress(tile.tobytes(), level=4))

    # Coarser levels are reductions of the same elevation and coverage samples.
    fields = (height, water, surface)
    for _ in range(3):
        fields = tuple(map(average, fields))
    out = bytearray()
    while min(fields[0].shape) >= 1:
        out.extend(encode(*fields).tobytes())
        if min(fields[0].shape) == 1:
            out.extend(encode(*(v.mean(keepdims=True) for v in fields)).tobytes())
            break
        fields = tuple(map(average, fields))
    (output / "surface.z").write_bytes(zlib.compress(out, level=4))
    (output / "polities.json").write_text(
        json.dumps([row["id"] for row in world["polities"]]), encoding="utf-8",
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("dem", "land", "lakes", "rivers", "glaciers", "world", "history", "output"):
        parser.add_argument(f"--{name}", type=Path, required=True)
    build(parser.parse_args())
