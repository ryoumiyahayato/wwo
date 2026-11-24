"""Rasterize the late-Victorian London building survey into existing WCM city pages."""

import argparse
import json
import sqlite3
from pathlib import Path

import numpy as np
import shapely
from rasterio.enums import Resampling
from rasterio.features import rasterize
from rasterio.transform import from_bounds
from rasterio.warp import reproject, transform_bounds

from city_ground_pack import write_city_tile

SOURCE = "London / Ordnance Survey 1891–1896 building footprints"
GROUP = (-0.371, 51.371, 0.104, 51.638)
COLUMNS, ROWS = 6, 6
PIXELS, GUTTER = 448, 8
TABLE = "london_buildings_1891-96_corr_v1"


def buildings(database, extent):
    west, south, east, north = extent
    query = f"""SELECT buildings.geom FROM "rtree_{TABLE}_geom" AS idx
        JOIN "{TABLE}" AS buildings ON buildings.fid = idx.id
        WHERE idx.maxx >= ? AND idx.minx <= ? AND idx.maxy >= ? AND idx.miny <= ?"""
    wkbs = []
    for (blob,) in database.execute(query, (west, east, south, north)):
        if not blob or blob[3] & 16:
            continue
        envelope_size = (0, 32, 48, 48, 64)[(blob[3] >> 1) & 7]
        wkbs.append(blob[8 + envelope_size:])
    return shapely.from_wkb(wkbs, on_invalid="ignore")


def page(database, bounds):
    width = PIXELS + GUTTER * 2
    mercator = transform_bounds("EPSG:4326", "EPSG:3857", *bounds)
    geometries = buildings(database, mercator)
    if not len(geometries):
        return None
    supersampled = width * 2
    source_transform = from_bounds(*mercator, supersampled, supersampled)
    footprints = rasterize(
        ((geometry, 255) for geometry in geometries if geometry is not None and not geometry.is_empty),
        out_shape=(supersampled, supersampled), transform=source_transform, dtype="uint8",
    )
    coverage = np.zeros((width, width, 2), dtype="uint8")
    reproject(
        footprints, coverage[:, :, 0], src_transform=source_transform, src_crs="EPSG:3857",
        dst_transform=from_bounds(*bounds, width, width), dst_crs="EPSG:4326",
        resampling=Resampling.average,
    )
    return coverage


def build(source, output):
    output.mkdir(parents=True, exist_ok=True)
    catalogue_path = output / "catalogue.json"
    catalogue = json.loads(catalogue_path.read_text(encoding="utf-8")) if catalogue_path.exists() else {"tiles": []}
    west, south, east, north = GROUP
    dx, dy = (east - west) / COLUMNS, (north - south) / ROWS
    gx, gy = dx * GUTTER / PIXELS, dy * GUTTER / PIXELS
    tiles = [tile for tile in catalogue["tiles"] if not tile["path"].startswith("london-os-1890s-")]
    with sqlite3.connect(source.resolve().as_uri() + "?mode=ro", uri=True) as database:
        for y in range(ROWS):
            for x in range(COLUMNS):
                left, bottom, right, top = west + x * dx, south + y * dy, west + (x + 1) * dx, south + (y + 1) * dy
                bounds = (left - gx, bottom - gy, right + gx, top + gy)
                coverage = page(database, bounds)
                if coverage is None or not coverage.max():
                    continue
                name = f"london-os-1890s-{x}-{y}.wcm"
                write_city_tile(output / name, coverage.shape[0], coverage.tobytes())
                tiles.append(dict(
                    path=name, level=3, core=[left, bottom, right, top], bounds=bounds,
                    group=GROUP, source=SOURCE, size=list(coverage.shape[:2]), cover=False, city=True, ids=False,
                ))
                print(name, flush=True)
    catalogue.update({
        "tiles": tiles,
        "source": "https://doi.org/10.5281/zenodo.19497435",
        "creator": "Rémi Petitpierre, Isabella di Lenardo, Polly Hudson, Hendrik Herold, Katherine McDonough, Beatrice Vaienti, Robert Hecht and Christopher Fleet",
        "license": "CC-BY-4.0",
        "processing": "Building footprints rasterized to coverage. No road or bridge geometry is inferred.",
    })
    catalogue_path.write_text(json.dumps(catalogue, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    build(args.source, args.output)
