"""Complete public R1 boundary for non-destructive map preprocessing."""

from __future__ import annotations

import argparse
import hashlib
import math
import re
import struct
import zlib
from collections import Counter
from pathlib import Path
from typing import Any, Sequence

from . import pipeline as legacy
from . import r1_safety as safe

TOOL_VERSION = safe.TOOL_VERSION
SCHEMA_VERSION = legacy.SCHEMA_VERSION
SUPPORTED_COORDINATE_SPACES = safe.SUPPORTED_COORDINATE_SPACES
SUPPORTED_MASK_MODES = safe.SUPPORTED_MASK_MODES
APPROVED_CANDIDATE_ROOT = safe.APPROVED_CANDIDATE_ROOT


def install(namespace: dict[str, Any]) -> None:
    namespace.update({
        "TOOL_VERSION": TOOL_VERSION,
        "SCHEMA_VERSION": SCHEMA_VERSION,
        "SUPPORTED_COORDINATE_SPACES": SUPPORTED_COORDINATE_SPACES,
        "SUPPORTED_MASK_MODES": SUPPORTED_MASK_MODES,
        "APPROVED_CANDIDATE_ROOT": APPROVED_CANDIDATE_ROOT,
        "validate_candidate_output_dir": safe.validate_candidate_output_dir,
        "candidate_source_status": safe.candidate_source_status,
        "resolve_unique_provider": safe.resolve_unique_provider,
        "build_inventory": build_inventory,
        "geometry_qa": geometry_qa,
        "build_crosswalk": build_crosswalk,
        "read_png_rgba": read_png_rgba,
        "_read_png_header": lambda path: safe.read_png_header(legacy, path),
        "_raster_metadata": lambda path: safe.raster_metadata(legacy, path),
        "_mask_from_rgba": mask_from_rgba,
        "_rasterize_polygons": rasterize_polygons,
        "process_cutout": process_cutout,
        "validate_manifest": validate_manifest,
        "_output_path": safe.validate_candidate_output_dir,
        "run_repository": run_repository,
        "deterministic_replay": deterministic_replay,
        "main": main,
    })


def build_inventory(root: Path | str) -> dict[str, Any]:
    return safe.build_inventory(legacy, root)


def geometry_qa(root: Path | str) -> dict[str, Any]:
    return safe.geometry_qa(legacy, root)


def build_crosswalk(root: Path | str, inventory: dict[str, Any] | None = None) -> dict[str, Any]:
    return safe.build_crosswalk(legacy, root, inventory)


def _png_chunks(data: bytes) -> list[tuple[bytes, bytes]]:
    return list(safe._png_chunks(data, legacy.PNG_SIGNATURE))


def read_png_rgba(path: Path) -> tuple[int, int, bytes]:
    data = path.read_bytes()
    width = height = bit_depth = color_type = interlace = None
    compressed: list[bytes] = []
    for chunk_type, chunk in _png_chunks(data):
        if chunk_type == b"tRNS":
            raise ValueError("PNG tRNS transparency is unsupported")
        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type, compression, filter_method, interlace = struct.unpack(">IIBBBBB", chunk)
            if compression != 0 or filter_method != 0:
                raise ValueError("unsupported PNG compression or filter method")
        elif chunk_type == b"IDAT":
            compressed.append(chunk)
    if width is None or height is None or bit_depth != 8 or interlace != 0 or not compressed:
        raise ValueError("PNG must be 8-bit, non-interlaced, and contain IDAT data")
    channels = {0: 1, 2: 3, 4: 2, 6: 4}.get(color_type)
    if channels is None:
        raise ValueError(f"unsupported PNG color type {color_type}")
    raw = legacy._unfilter_png(zlib.decompress(b"".join(compressed)), width, height, channels)
    output = bytearray(width * height * 4)
    for index in range(width * height):
        source = index * channels
        target = index * 4
        if color_type == 6:
            output[target : target + 4] = raw[source : source + 4]
        elif color_type == 4:
            output[target : target + 4] = bytes((raw[source], raw[source], raw[source], raw[source + 1]))
        elif color_type == 2:
            output[target : target + 4] = bytes((raw[source], raw[source + 1], raw[source + 2], 255))
        else:
            output[target : target + 4] = bytes((raw[source], raw[source], raw[source], 255))
    return int(width), int(height), bytes(output)


def mask_from_rgba(width: int, height: int, pixels: bytes, mode: str | None) -> list[bool]:
    if mode not in SUPPORTED_MASK_MODES:
        raise ValueError(f"mask_mode is required and must be one of {sorted(SUPPORTED_MASK_MODES)}")
    if len(pixels) != width * height * 4:
        raise ValueError("mask pixel buffer has the wrong length")
    if mode == "alpha":
        return [pixels[index + 3] > 0 for index in range(0, len(pixels), 4)]
    if any(pixels[index] != pixels[index + 1] or pixels[index] != pixels[index + 2] for index in range(0, len(pixels), 4)):
        raise ValueError("grayscale mask mode requires equal RGB channels")
    return [pixels[index] > 0 for index in range(0, len(pixels), 4)]


def _validate_bounds(source_bounds: Sequence[float] | None, coordinate_space: str) -> list[float] | None:
    space = str(coordinate_space).upper()
    if space not in SUPPORTED_COORDINATE_SPACES:
        raise ValueError(f"coordinate_space must be one of {sorted(SUPPORTED_COORDINATE_SPACES)}")
    if source_bounds is None:
        if space == "WGS84":
            raise ValueError("WGS84 geometry requires explicit source_bounds mapping")
        return None
    if len(source_bounds) != 4 or not all(legacy._is_finite_number(value) for value in source_bounds):
        raise ValueError("source_bounds must contain four finite values")
    bounds = [float(value) for value in source_bounds]
    if not (-180.0 <= bounds[0] < bounds[2] <= 180.0 and -90.0 <= bounds[1] < bounds[3] <= 90.0) or bounds[2] - bounds[0] > 360.0:
        raise ValueError("source_bounds must be finite WGS84 longitude/latitude bounds")
    if space == "PIXEL":
        raise ValueError("source_bounds is only valid with WGS84 coordinate_space")
    return bounds


def _strict_ring(raw: Any, label: str) -> list[tuple[float, float]]:
    if not isinstance(raw, list):
        raise ValueError(f"{label} must be a ring array")
    points: list[tuple[float, float]] = []
    for index, item in enumerate(raw):
        point = safe._point(legacy, item)
        if point is None:
            raise ValueError(f"{label}[{index}] is not a finite two-number point")
        points.append(point)
    if points and points[0] == points[-1]:
        points.pop()
    if len(points) < 3:
        raise ValueError(f"{label} must contain at least three vertices")
    return points


def rasterize_polygons(polygons: Sequence[dict[str, Any]], width: int, height: int, source_bounds: Sequence[float] | None = None, coordinate_space: str = "PIXEL") -> list[bool]:
    bounds = _validate_bounds(source_bounds, coordinate_space)
    mask = [False] * (width * height)

    def transform(point: tuple[float, float]) -> tuple[float, float]:
        if bounds is None:
            return point
        min_x, min_y, max_x, max_y = bounds
        return ((point[0] - min_x) / (max_x - min_x) * (width - 1), (max_y - point[1]) / (max_y - min_y) * (height - 1))

    for polygon_index, polygon in enumerate(polygons):
        if not isinstance(polygon, dict):
            raise ValueError(f"polygon[{polygon_index}] is not an object")
        outer = [transform(point) for point in _strict_ring(polygon.get("outer"), f"polygon[{polygon_index}].outer")]
        holes = [[transform(point) for point in _strict_ring(hole, f"polygon[{polygon_index}].holes[{hole_index}]")] for hole_index, hole in enumerate(polygon.get("holes", []))]
        box = legacy._bbox(outer)
        min_x, max_x = max(0, int(math.floor(box[0]))), min(width - 1, int(math.ceil(box[2])))
        min_y, max_y = max(0, int(math.floor(box[1]))), min(height - 1, int(math.ceil(box[3])))
        for y in range(min_y, max_y + 1):
            for x in range(min_x, max_x + 1):
                sample = (x + 0.5, y + 0.5)
                if legacy._point_in_ring(sample, outer) and not any(legacy._point_in_ring(sample, hole) for hole in holes):
                    mask[y * width + x] = True
    return mask


def _find_geometry_polygons(value: Any, geometry_id: str) -> list[dict[str, Any]]:
    if isinstance(value, dict):
        identifiers = {str(value.get(key)) for key in ("id", "stable_id", "unit_id", "geometry_feature_id", "country_id") if value.get(key) not in (None, "")}
        if geometry_id in identifiers:
            return safe._extract_polygons(legacy, value.get("geometry", value))
        for child in value.values():
            found = _find_geometry_polygons(child, geometry_id)
            if found:
                return found
    elif isinstance(value, list):
        for child in value:
            found = _find_geometry_polygons(child, geometry_id)
            if found:
                return found
    return []


def _entity_output_stem(entity_id: str) -> str:
    safe_name = re.sub(r"[^A-Za-z0-9._-]+", "_", entity_id).strip("_") or "entity"
    return f"{safe_name}--{hashlib.sha256(entity_id.encode('utf-8')).hexdigest()[:16]}"


def _coordinate_contract(coordinate_space: str, source_bounds: Sequence[float] | None) -> dict[str, Any]:
    bounds = _validate_bounds(source_bounds, coordinate_space)
    if str(coordinate_space).upper() == "PIXEL":
        return {"space": "PIXEL", "mapping": "direct_canvas_pixels", "y_axis": "down"}
    assert bounds is not None
    return {"space": "WGS84", "mapping": "equirectangular_canvas", "source_bounds": bounds, "y_axis": "north_to_top"}


def process_cutout(root: Path | str, source_path: Path | str, entity_id: str, output_dir: Path | str, mask_path: Path | str | None = None, geometry_file: Path | str | None = None, geometry_id: str | None = None, canonical_size: tuple[int, int] | None = None, padding: int = 0, source_bounds: Sequence[float] | None = None, coordinate_space: str = "PIXEL", mask_mode: str | None = None, allow_mask_resample: bool = False) -> dict[str, Any]:
    root_path = Path(root).resolve()
    if not isinstance(entity_id, str) or not entity_id.strip():
        raise ValueError("entity_id must be a non-empty string")
    if padding < 0:
        raise ValueError("padding must be non-negative")
    output = safe.validate_candidate_output_dir(root_path, output_dir)
    source = safe.resolve_input_path(root_path, source_path, "source")
    source_hash = legacy._file_hash(source)
    original_width, original_height, pixels = read_png_rgba(source)
    source_dimensions = [original_width, original_height]
    width, height = original_width, original_height
    requested_size = canonical_size or (width, height)
    if len(requested_size) != 2 or requested_size[0] <= 0 or requested_size[1] <= 0:
        raise ValueError("canonical_size must contain two positive dimensions")
    if requested_size != (width, height):
        pixels = legacy._resize_rgba(width, height, pixels, requested_size[0], requested_size[1])
        width, height = requested_size
    coordinate = _coordinate_contract(coordinate_space, source_bounds)
    input_mask_file: Path | None = None
    input_mask_hash: str | None = None
    input_mask_dimensions: list[int] | None = None
    mask_resampled = False
    mask_resampling = "none"
    if mask_path is not None:
        if mask_mode not in SUPPORTED_MASK_MODES:
            raise ValueError(f"mask_mode is required and must be one of {sorted(SUPPORTED_MASK_MODES)}")
        input_mask_file = safe.resolve_input_path(root_path, mask_path, "mask")
        input_mask_header = safe.read_png_header(legacy, input_mask_file)
        if mask_mode == "alpha" and input_mask_header["alpha_availability"] != "present":
            raise ValueError("alpha mask mode requires a PNG with an explicit alpha channel")
        input_mask_hash = legacy._file_hash(input_mask_file)
        mask_width, mask_height, mask_pixels = read_png_rgba(input_mask_file)
        input_mask_dimensions = [mask_width, mask_height]
        if (mask_width, mask_height) != (width, height):
            if not allow_mask_resample:
                raise ValueError("mask dimensions differ from the canonical source canvas; explicit resampling opt-in is required")
            mask_resampled = True
            mask_resampling = "nearest_neighbor"
        mask = mask_from_rgba(mask_width, mask_height, mask_pixels, mask_mode)
        if mask_resampled:
            mask = legacy._resize_mask(mask_width, mask_height, mask, width, height)
        mask_source = legacy._relative_path(root_path, input_mask_file)
    elif geometry_file is not None and geometry_id:
        geometry_path = safe.resolve_input_path(root_path, geometry_file, "geometry")
        geometry_document = legacy._load_json(geometry_path)
        declared = legacy._declared_coordinate_convention(geometry_document).upper()
        if any(token in declared for token in ("WGS84", "LONGITUDE", "LATITUDE")) and str(coordinate_space).upper() != "WGS84":
            raise ValueError("geographic geometry requires coordinate_space=WGS84 and explicit source_bounds")
        polygons = _find_geometry_polygons(geometry_document, geometry_id)
        if not polygons:
            raise ValueError(f"geometry id {geometry_id!r} was not found or has no polygon")
        mask = rasterize_polygons(polygons, width, height, source_bounds, coordinate_space)
        mask_source = legacy._relative_path(root_path, geometry_path) + "#" + geometry_id
        mask_mode = "geometry"
    else:
        raise ValueError("provide either mask_path or geometry_file plus geometry_id")
    requested_bbox = legacy._mask_bbox(width, height, mask)
    if requested_bbox is None:
        raise ValueError("mask is empty")
    x, y, box_width, box_height = requested_bbox
    candidate_bbox = [x - padding, y - padding, box_width + padding * 2, box_height + padding * 2]
    qa = legacy.mask_qa(width, height, mask, mask_source, candidate_bbox)
    crop_bbox = [max(0, candidate_bbox[0]), max(0, candidate_bbox[1]), min(width, candidate_bbox[0] + candidate_bbox[2]) - max(0, candidate_bbox[0]), min(height, candidate_bbox[1] + candidate_bbox[3]) - max(0, candidate_bbox[1])]
    if crop_bbox[2] <= 0 or crop_bbox[3] <= 0:
        raise ValueError("candidate crop has no positive dimensions")
    crop_width, crop_height, cutout = legacy._crop_rgba(width, height, pixels, crop_bbox, mask)
    stem = _entity_output_stem(entity_id)
    normalized_path = output / f"{stem}.png"
    mask_output_path = output / f"{stem}.mask.png"
    preview_path = output / f"{stem}.preview.png"
    manifest_path = output / f"{stem}.manifest.json"
    input_keys = {safe.canonical_key(source)} | ({safe.canonical_key(input_mask_file)} if input_mask_file is not None else set())
    targets = [normalized_path, mask_output_path, preview_path, manifest_path]
    if any(safe.canonical_key(target) in input_keys for target in targets):
        raise ValueError("source or input mask aliases a candidate output path")
    if len({safe.canonical_key(target) for target in targets}) != len(targets):
        raise ValueError("candidate output paths are not distinct")
    if any(target.is_symlink() for target in targets):
        raise ValueError("candidate output path must not be a symlink")
    if any(target.exists() for target in targets):
        raise ValueError("candidate output already exists")
    output.mkdir(parents=True, exist_ok=True)
    legacy.write_png_rgba(normalized_path, crop_width, crop_height, cutout)
    crop_mask = bytearray(crop_width * crop_height * 4)
    for local_y in range(crop_height):
        for local_x in range(crop_width):
            source_x = crop_bbox[0] + local_x
            source_y = crop_bbox[1] + local_y
            value = 255 if 0 <= source_x < width and 0 <= source_y < height and mask[source_y * width + source_x] else 0
            index = (local_y * crop_width + local_x) * 4
            crop_mask[index : index + 4] = bytes((value, value, value, value))
    legacy.write_png_rgba(mask_output_path, crop_width, crop_height, bytes(crop_mask))
    legacy.write_png_rgba(preview_path, crop_width, crop_height, legacy._preview_pixels(crop_width, crop_height, cutout))
    manifest = {
        "schema_version": SCHEMA_VERSION, "generator_version": TOOL_VERSION, "entity_id": entity_id,
        "source_file": legacy._relative_path(root_path, source), "source_hash": source_hash, "source_dimensions": source_dimensions,
        "input_mask_file": legacy._relative_path(root_path, input_mask_file) if input_mask_file is not None else None,
        "input_mask_hash": input_mask_hash, "input_mask_dimensions": input_mask_dimensions,
        "mask_source": mask_source, "mask_hash": legacy._file_hash(mask_output_path),
        "output_hash": legacy._file_hash(normalized_path), "preview_hash": legacy._file_hash(preview_path),
        "crop_bbox": crop_bbox, "requested_candidate_bbox": candidate_bbox, "mask_bbox": requested_bbox,
        "canvas_size": [width, height], "output_size": [crop_width, crop_height],
        "output_file": normalized_path.name, "mask_file": mask_output_path.name, "preview_file": preview_path.name,
        "coordinate_contract": coordinate,
        "processing_parameters": {
            "canonical_canvas_size": [width, height], "padding": int(padding), "resampling": "nearest_neighbor",
            "source_bounds": list(source_bounds) if source_bounds is not None else None,
            "alpha_mode": "source_alpha_intersect_mask", "mask_mode": mask_mode,
            "mask_input_alpha_availability": input_mask_header["alpha_availability"] if input_mask_file is not None else "not_applicable",
            "mask_resampled": mask_resampled, "mask_resampling": mask_resampling, "original_preserved": True,
        },
        "mask_qa": qa,
    }
    legacy._write_json(manifest_path, manifest)
    from .r1_manifest import validate_manifest

    errors = validate_manifest(manifest, root_path, manifest_path.parent)
    if errors:
        raise ValueError("manifest validation failed: " + ", ".join(errors))
    return manifest
