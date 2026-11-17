"""Rasterize local USGS Upper Mississippi historical land-cover KMZ polygons for QDT."""

import argparse
import json
import math
import re
from pathlib import Path
from xml.etree import ElementTree
from zipfile import ZipFile

import numpy as np
from PIL import Image
from rasterio.features import rasterize
from rasterio.transform import from_bounds
from scipy.ndimage import distance_transform_edt


KML = {"kml": "http://www.opengis.net/kml/2.2"}
CLASSES = {
    "Open water": 1,
    "Floodplain forest": 2,
    "Upland forest": 2,
    "Plantation": 2,
    "Agriculture": 3,
    "Wet meadow": 4,
    "Wet meadow shrub": 4,
    "Sand bar": 4,
    "Mud": 4,
    "Developed": 0,
    "No coverage": 0,
}
# Raster class 4 contributes to the validity channel only.
SUBPIXELS = 4
METRES_PER_DEGREE = 111_195


def polygon_ring(ring):
    raw = ring.findtext("kml:LinearRing/kml:coordinates", namespaces=KML)
    return [tuple(map(float, point.split(",")[:2])) for point in raw.split()]


def read_shapes(path):
    with ZipFile(path) as archive, archive.open("doc.kml") as document:
        tree = ElementTree.parse(document)
    shapes = []
    west, south, east, north = math.inf, math.inf, -math.inf, -math.inf
    for placemark in tree.findall(".//kml:Placemark", KML):
        polygons = placemark.findall(".//kml:Polygon", KML)
        if not polygons:
            continue
        name = placemark.findtext("kml:name", namespaces=KML).strip()
        if name not in CLASSES:
            raise ValueError(f"Unmapped USGS survey class {name!r}")
        code = CLASSES[name]
        for polygon in polygons:
            outer = polygon_ring(polygon.find("kml:outerBoundaryIs", KML))
            holes = [polygon_ring(ring) for ring in polygon.findall("kml:innerBoundaryIs", KML)]
            shapes.append(({"type": "Polygon", "coordinates": [outer, *holes]}, code))
            if code:
                longitude, latitude = zip(*outer)
                west = min(west, min(longitude))
                south = min(south, min(latitude))
                east = max(east, max(longitude))
                north = max(north, max(latitude))
    if west >= east or south >= north:
        raise ValueError("No supported survey polygons found")
    # Explicit gaps take precedence if the source has overlapping polygons.
    shapes.sort(key=lambda item: item[1] == 0)
    return shapes, (west, south, east, north)


def sampling(extent, mpp, pad_extent):
    west, south, east, north = extent
    if not (-180 <= west < east <= 180 and -90 < south < north < 90):
        raise ValueError("Expected a non-wrapping WGS84 extent in west, south, east, north order")
    lon_metres = METRES_PER_DEGREE * math.cos(math.radians((south + north) / 2))
    width = 32 * math.ceil((east - west) * lon_metres / (mpp * 32))
    height = 32 * math.ceil((north - south) * METRES_PER_DEGREE / (mpp * 32))
    if max(width, height) > 2048:
        raise ValueError("Survey exceeds 2048 pixels; crop with --extent")
    if pad_extent:
        # Round the automatic extent outward while retaining the chosen spacing.
        extra_lon = (width * mpp / lon_metres - (east - west)) / 2
        extra_lat = (height * mpp / METRES_PER_DEGREE - (north - south)) / 2
        west, south, east, north = west - extra_lon, south - extra_lat, east + extra_lon, north + extra_lat
    dx, dy = (east - west) / width, (north - south) / height
    return (west, south, east, north), (width, height), (dx, dy), (dx * lon_metres, dy * METRES_PER_DEGREE)


def render(shapes, extent, size, spacing, metre_spacing, fade_metres):
    west, south, east, north = extent
    width, height = size
    dx, dy = spacing
    mx, my = metre_spacing
    # Include source geometry around a crop so a crop edge never becomes a survey edge.
    padx, pady = math.ceil(fade_metres / mx) + 1, math.ceil(fade_metres / my) + 1
    # A tiny crop can force very fine spacing after rounding to the 32-pixel grid.
    if max(padx, pady) > 128:
        raise ValueError("Extent is too small for the selected survey boundary fade")
    padded = (west - padx * dx, south - pady * dy, east + padx * dx, north + pady * dy)
    cols, rows = width + 2 * padx, height + 2 * pady
    transform = from_bounds(*padded, cols * SUBPIXELS, rows * SUBPIXELS)
    samples = rasterize(shapes, out_shape=(rows * SUBPIXELS, cols * SUBPIXELS),
                        transform=transform, dtype="uint8")
    texels = samples.reshape(rows, SUBPIXELS, cols, SUBPIXELS)
    covered = np.count_nonzero(texels, axis=(1, 3))
    interior = covered >= SUBPIXELS**2 / 2
    crop = np.s_[pady:pady + height, padx:padx + width]
    # This measures the union of all supported classes. Class boundaries remain sharp.
    distance = distance_transform_edt(interior, sampling=(my, mx))[crop]
    t = np.clip((distance - 0.5 * min(mx, my)) / fade_metres, 0, 1)
    strength = (t * t * (3 - 2 * t) * (255 / SUBPIXELS**2)).astype(np.float32)
    pixels = np.empty((height, width, 4), dtype=np.uint8)
    for channel in range(3):
        count = np.count_nonzero(texels[crop[0], :, crop[1], :] == channel + 1, axis=(1, 3))
        # Round down so RGB remains a premultiplied partition of the rounded validity.
        pixels[..., channel] = np.floor(count * strength)
    pixels[..., 3] = np.rint(covered[crop] * strength)
    return pixels


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kmz", type=Path)
    parser.add_argument("--output", type=Path, required=True, help="PNG and manifest directory")
    parser.add_argument("--stem", required=True, help="QDT region identifier and output stem")
    parser.add_argument("--source", action="append", required=True, help="Original USGS data or metadata citation")
    parser.add_argument("--extent", nargs=4, type=float, metavar=("WEST", "SOUTH", "EAST", "NORTH"))
    parser.add_argument("--mpp", type=float, default=25, help="Target pixel spacing, in metres")
    parser.add_argument("--fade-metres", type=float, default=800, help="Survey boundary feather width")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", args.stem):
        parser.error("invalid QDT region identifier")
    if not 20 <= args.mpp <= 30 or not 500 <= args.fade_metres <= 1200:
        parser.error("expected 20–30 metres per pixel and a 500–1200 metre boundary fade")

    shapes, coverage = read_shapes(args.kmz)
    extent, size, spacing, metre_spacing = sampling(args.extent or coverage, args.mpp, args.extent is None)
    pixels = render(shapes, extent, size, spacing, metre_spacing, args.fade_metres)
    if not pixels[..., 3].any():
        raise ValueError("No survey coverage remains in this extent after boundary feathering")
    args.output.mkdir(parents=True, exist_ok=True)
    image_name = f"{args.stem}.png"
    Image.fromarray(pixels).save(args.output / image_name, compress_level=3)
    manifest = {
        "sources": args.source,
        "extent": extent,
        "image": image_name,
        "modern_reference": False,
        "surface": "survey",
        "source_file": args.kmz.name,
        "sample_mpp": metre_spacing,
        "survey_boundary_fade_metres": args.fade_metres,
        "center": [(extent[0] + extent[2]) / 2, (extent[1] + extent[3]) / 2],
    }
    (args.output / f"{args.stem}.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"{args.stem}: {size[0]} by {size[1]} pixels, extent {extent}")


if __name__ == "__main__":
    main()
