"""Build an RGBA coastal reference from a local ESA WorldCover 2021 GeoTIFF."""

import argparse
import json
import math
from pathlib import Path
import re

import numpy as np
from PIL import Image
import rasterio
from rasterio.transform import from_bounds, rowcol
from rasterio.warp import Resampling, reproject, transform, transform_bounds
from rasterio.windows import Window, from_bounds as window_from_bounds
from scipy.ndimage import binary_propagation, distance_transform_edt


WORLDCOVER_URL = "https://doi.org/10.5281/zenodo.7254221"
BARE_CLASS = 60
WATER_CLASS = 80
KNOWN_CLASSES = (10, 20, 30, 40, 50, BARE_CLASS, 70, WATER_CLASS, 100)
UNKNOWN = 256
MAX_SOURCE_PIXELS = 16_777_216


def build_reference(source_path, extent, width, height, feather_pixels, ocean_seed):
    west, south, east, north = extent
    if not (-180 <= west < east <= 180 and -85 <= south < north <= 85):
        raise ValueError("expected ordered west south east north bounds within ±180°, ±85°")
    if any(size < 32 or size > 2048 or size % 32 for size in (width, height)):
        raise ValueError("width and height must be multiples of 32 from 32 to 2048")
    if not math.isfinite(feather_pixels) or not 0 <= feather_pixels <= 64:
        raise ValueError("feather must be between 0 and 64 pixels")
    if not (west < ocean_seed[0] < east and south < ocean_seed[1] < north):
        raise ValueError("coastal sampling requires an ocean seed inside the output extent")

    lon_step = (east - west) / width
    lat_step = (north - south) / height
    padding = math.ceil(feather_pixels) + 1
    padded_extent = (
        west - padding * lon_step,
        south - padding * lat_step,
        east + padding * lon_step,
        north + padding * lat_step,
    )
    padded_width = width + 2 * padding
    padded_height = height + 2 * padding
    # Sample the categorical source at four subpixel centers. Aggregate the
    # classes after warping, so interpolation cannot create new classes.
    warp_shape = (2 * padded_height, 2 * padded_width)
    warped = np.full(warp_shape, UNKNOWN, dtype=np.uint16)
    with rasterio.open(source_path) as source:
        if source.crs is None or source.count != 1 or source.dtypes[0] != "uint8":
            raise ValueError("expected a georeferenced single-band uint8 classification")
        if source.nodata in KNOWN_CLASSES:
            raise ValueError("source nodata conflicts with a documented source class")
        source_url = source.tags().get("SOURCE_URL")
        source_bounds = transform_bounds("EPSG:4326", source.crs, *padded_extent)
        window = window_from_bounds(*source_bounds, transform=source.transform)
        col_start = max(0, math.floor(window.col_off) - 2)
        row_start = max(0, math.floor(window.row_off) - 2)
        col_stop = min(source.width, math.ceil(window.col_off + window.width) + 2)
        row_stop = min(source.height, math.ceil(window.row_off + window.height) + 2)
        if col_start >= col_stop or row_start >= row_stop:
            raise ValueError("requested extent does not intersect the source")
        source_window = Window(col_start, row_start, col_stop - col_start, row_stop - row_start)
        if source_window.width * source_window.height > MAX_SOURCE_PIXELS:
            raise ValueError("requested extent requires more than 16 Mi source pixels")
        mask = source.read(1, window=source_window, masked=True).astype(np.uint16).filled(UNKNOWN)
        source_transform = source.window_transform(source_window)
        seed_x, seed_y = transform("EPSG:4326", source.crs, [ocean_seed[0]], [ocean_seed[1]])
        seed_row, seed_col = rowcol(source_transform, seed_x[0], seed_y[0])
        is_water = mask == WATER_CLASS
        if not (0 <= seed_row < mask.shape[0] and 0 <= seed_col < mask.shape[1]
                and is_water[seed_row, seed_col]):
            raise ValueError("ocean seed must fall on an observed class-80 source pixel")
        seed = np.zeros(mask.shape, dtype=bool)
        seed[seed_row, seed_col] = True
        connected = binary_propagation(seed, mask=is_water)
        mask[is_water & ~connected] = UNKNOWN
        reproject(
            source=mask,
            destination=warped,
            src_transform=source_transform,
            src_crs=source.crs,
            src_nodata=UNKNOWN,
            dst_transform=from_bounds(*padded_extent, warp_shape[1], warp_shape[0]),
            dst_crs="EPSG:4326",
            dst_nodata=UNKNOWN,
            resampling=Resampling.nearest,
        )

    subpixel_shape = (padded_height, 2, padded_width, 2)
    known = np.isin(warped, KNOWN_CLASSES).reshape(subpixel_shape).mean(axis=(1, 3))
    water = (warped == WATER_CLASS).reshape(subpixel_shape).mean(axis=(1, 3))
    bare = (warped == BARE_CLASS).reshape(subpixel_shape).mean(axis=(1, 3))
    if feather_pixels:
        interior = np.pad(known == 1, 1, constant_values=False)
        distance = distance_transform_edt(interior)[1:-1, 1:-1]
        distance = np.where(known == 1, distance - 0.5, known * 0.5)
        feather = np.clip(distance / feather_pixels, 0, 1)
        known *= feather
        water *= feather
        bare *= feather
    crop = np.s_[padding:padding + height, padding:padding + width]
    pixels = np.zeros((height, width, 4), dtype=np.uint8)
    pixels[:, :, 0] = np.rint(water[crop] * 255).astype(np.uint8)
    pixels[:, :, 1] = np.rint(bare[crop] * 255).astype(np.uint8)
    pixels[:, :, 3] = np.rint(known[crop] * 255).astype(np.uint8)
    if not pixels[:, :, 3].any():
        raise ValueError("no documented observations within requested extent")
    sources = [WORLDCOVER_URL]
    if source_url and source_url.startswith("https://") and source_url not in sources:
        sources.append(source_url)
    return pixels, sources


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="local WorldCover 2021 GeoTIFF")
    parser.add_argument("--ocean-seed", type=float, nargs=2, required=True, metavar=("LON", "LAT"))
    parser.add_argument("--extent", type=float, nargs=4, required=True,
                        metavar=("WEST", "SOUTH", "EAST", "NORTH"))
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--feather-pixels", type=float, default=8.0)
    parser.add_argument("--id", required=True, help="manifest ID and output filename stem")
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    if len(args.id) > 64 or not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", args.id):
        parser.error("id must be 1–64 characters using lowercase ASCII letters, digits and hyphens")
    image_path = args.output_dir / f"{args.id}.png"
    manifest_path = args.output_dir / f"{args.id}.json"
    for path in (image_path, manifest_path):
        if path.exists():
            parser.error(f"output already exists: {path}")
    try:
        pixels, sources = build_reference(
            args.source, args.extent, args.width, args.height, args.feather_pixels, args.ocean_seed
        )
    except (ValueError, rasterio.errors.RasterioError) as error:
        parser.error(str(error))

    manifest = {
        "id": args.id,
        "extent": args.extent,
        "image": image_path.name,
        "modern_reference": True,
        "surface": "coast",
        "sources": sources,
        "source_product": "worldcover-2021",
        "source_member": args.source.name,
        "width": args.width,
        "height": args.height,
        "feather_pixels": args.feather_pixels,
        "encoding": (
            "R = ocean-connected water coverage; G = bare/sparse coverage; B = 0; "
            "A = source confidence. R and G are premultiplied by A."
        ),
        "source_classes": (
            "Class 80 contributes water only where four-connected to the supplied ocean seed. "
            "Class 60 contributes bare/sparse coverage. Disconnected water, herbaceous wetland (90), "
            "mangroves (95), nodata (0), undocumented codes and pixels outside the source carry no confidence."
        ),
        "attribution": (
            "© ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) "
            "processed by ESA WorldCover consortium"
        ),
        "license": "CC BY 4.0",
        "ocean_seed": args.ocean_seed,
    }
    args.output_dir.mkdir(parents=True, exist_ok=True)
    with image_path.open("xb") as image_output:
        try:
            Image.fromarray(pixels).save(image_output, format="PNG")
            with manifest_path.open("x", encoding="utf-8") as manifest_output:
                try:
                    json.dump(manifest, manifest_output, indent=2, ensure_ascii=False)
                    manifest_output.write("\n")
                except OSError:
                    manifest_output.close()
                    manifest_path.unlink()
                    raise
        except OSError:
            image_output.close()
            image_path.unlink()
            raise
    print(image_path)
    print(manifest_path)


if __name__ == "__main__":
    main()
