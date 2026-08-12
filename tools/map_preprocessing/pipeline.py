"""Deterministic, non-destructive map asset inventory and preprocessing.

The repository intentionally contains authoritative map data as JSON and only a
small set of flag rasters.  This module treats those files as read-only inputs.
Generated inventories, QA findings, and candidate cutouts are written to a
caller-selected output directory, normally under the ignored ``artifacts``
directory.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import struct
import sys
import time
import zlib
from collections import Counter, defaultdict, deque
from pathlib import Path
from typing import Any, Iterable, Iterator, Sequence


TOOL_VERSION = "1.0.0"
SCHEMA_VERSION = 1
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
RASTER_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp", ".tif", ".tiff"}
VECTOR_EXTENSIONS = {".svg", ".geojson", ".topojson", ".shp", ".kml", ".wkt"}
MAP_SOURCE_EXTENSIONS = {".json", ".geojson", ".topojson", ".wkt", ".gd", ".tscn", ".tres"}
ID_KEYS = {
    "id",
    "stable_id",
    "entity_id",
    "geometry_feature_id",
    "unit_id",
    "country_id",
    "country_iso_a3",
    "iso_a3",
    "source_code",
    "code",
}
FINITE_EPSILON = 1.0e-9
TINY_FRAGMENT_RATIO = 1.0e-6
MAX_MASK_FRAGMENTS = 32


def _stable_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def stable_hash(value: Any) -> str:
    return hashlib.sha256(_stable_json(value).encode("utf-8")).hexdigest()


def _file_hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(_stable_json(value) + "\n", encoding="utf-8")


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _relative_path(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.resolve().as_posix()


def _unique_strings(values: Iterable[Any]) -> list[str]:
    return sorted({str(value) for value in values if value not in (None, "")})


def _is_finite_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))


def _scalar(value: Any) -> bool:
    return isinstance(value, (str, int, float, bool)) or value is None


def _collect_ids(value: Any, result: set[str], total: list[int]) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if key in ID_KEYS and isinstance(child, (str, int)):
                total[0] += 1
                result.add(str(child))
            _collect_ids(child, result, total)
    elif isinstance(value, list):
        for child in value:
            _collect_ids(child, result, total)


def _top_level_counts(value: Any) -> dict[str, int]:
    if not isinstance(value, dict):
        return {}
    return {
        str(key): len(child)
        for key, child in value.items()
        if isinstance(child, (list, dict))
    }


def _declared_coordinate_convention(value: Any) -> str:
    if not isinstance(value, dict):
        return "not_declared"
    candidates: list[Any] = [value.get("coordinate_system"), value.get("projection")]
    source = value.get("source")
    if isinstance(source, dict):
        candidates.extend([source.get("coordinate_system"), source.get("projection")])
    for candidate in candidates:
        if isinstance(candidate, str) and candidate:
            return candidate
        if isinstance(candidate, dict) and candidate:
            return _stable_json(candidate)
    return "not_declared"


def _provenance(value: Any) -> dict[str, Any] | None:
    if not isinstance(value, dict):
        return None
    source = value.get("source")
    if isinstance(source, dict):
        return {str(k): v for k, v in sorted(source.items()) if _scalar(v)}
    samples: set[str] = set()

    def walk(child: Any) -> None:
        if isinstance(child, dict):
            for key, item in child.items():
                if key in {"geometry_source", "geometry_provider", "provider", "dataset", "upstream"}:
                    if isinstance(item, str) and item:
                        samples.add(item)
                walk(item)
        elif isinstance(child, list):
            for item in child:
                walk(item)

    walk(value)
    return {"declared_values": sorted(samples)} if samples else None


def _read_png_header(path: Path) -> dict[str, Any]:
    data = path.read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError("not a PNG")
    position = len(PNG_SIGNATURE)
    width = height = bit_depth = color_type = None
    has_trns = False
    while position + 12 <= len(data):
        length = struct.unpack(">I", data[position : position + 4])[0]
        chunk_type = data[position + 4 : position + 8]
        chunk = data[position + 8 : position + 8 + length]
        position += 12 + length
        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type = struct.unpack(">IIBB", chunk[:10])
        elif chunk_type == b"tRNS":
            has_trns = True
        elif chunk_type == b"IEND":
            break
    if width is None or height is None:
        raise ValueError("PNG is missing IHDR")
    alpha = color_type in {4, 6} or has_trns
    return {
        "dimensions": [int(width), int(height)],
        "bit_depth": int(bit_depth),
        "color_type": int(color_type),
        "alpha_availability": "present" if alpha else "absent",
        "coordinate_convention": "pixel_origin_top_left",
    }


def _raster_metadata(path: Path) -> dict[str, Any]:
    if path.suffix.lower() == ".png":
        metadata = _read_png_header(path)
    else:
        metadata = {
            "dimensions": None,
            "alpha_availability": "unknown",
            "coordinate_convention": "pixel_origin_top_left",
        }
    try:
        from PIL import Image  # type: ignore

        with Image.open(path) as image:
            metadata["dimensions"] = [int(image.width), int(image.height)]
            bands = image.getbands()
            metadata["alpha_availability"] = "present" if "A" in bands else "absent"
            if "A" in bands:
                alpha = image.getchannel("A")
                extrema = alpha.getextrema()
                metadata["alpha_content"] = "fully_opaque" if extrema == (255, 255) else "contains_transparency"
            metadata["decoder_format"] = image.format
    except Exception as exc:  # pragma: no cover - optional decoder fallback
        metadata["decoder_error"] = type(exc).__name__
    return metadata


def _map_related(relative: Path) -> bool:
    lower = relative.as_posix().lower()
    suffix = relative.suffix.lower()
    if suffix in RASTER_EXTENSIONS or suffix in VECTOR_EXTENSIONS:
        return True
    if lower.startswith("data/world_map/") and suffix in MAP_SOURCE_EXTENSIONS:
        return True
    if lower.startswith(("scripts/map/", "scripts/world_map/", "scenes/map/", "scenes/world/")):
        return suffix in MAP_SOURCE_EXTENSIONS or suffix in {".gdshader", ".shader"}
    if suffix in MAP_SOURCE_EXTENSIONS and any(
        token in lower for token in ("map", "geometry", "coast", "admin1", "country", "region", "port", "rail", "road")
    ):
        return True
    return False


def _asset_category(relative: Path) -> str:
    suffix = relative.suffix.lower()
    lower = relative.as_posix().lower()
    if suffix in RASTER_EXTENSIONS:
        return "raster"
    if suffix in VECTOR_EXTENSIONS:
        return "vector"
    if "geometry" in lower or "cache" in lower or "coast" in lower or "cshapes" in lower:
        return "geometry_cache" if "cache" in lower else "geometry_source"
    if lower.startswith("data/world_map/"):
        return "map_data"
    return "map_source"


def _inventory_file(root: Path, path: Path) -> dict[str, Any]:
    relative = Path(_relative_path(root, path))
    record: dict[str, Any] = {
        "path": relative.as_posix(),
        "category": _asset_category(relative),
        "format": relative.suffix.lower().lstrip(".") or "unknown",
        "size_bytes": path.stat().st_size,
        "sha256": _file_hash(path),
        "dimensions": None,
        "alpha_availability": None,
        "coordinate_convention": "not_declared",
        "linked_entity_id_count": 0,
        "linked_entity_ids": [],
        "source_provenance": None,
        "details": {},
    }
    if relative.suffix.lower() in RASTER_EXTENSIONS:
        record.update(_raster_metadata(path))
        return record
    if relative.suffix.lower() not in {".json", ".geojson", ".topojson"}:
        record["details"] = {"source_file": True}
        return record
    try:
        value = _load_json(path)
    except Exception as exc:
        record["details"] = {"parse_error": f"{type(exc).__name__}: {exc}"}
        return record
    identifiers: set[str] = set()
    total = [0]
    _collect_ids(value, identifiers, total)
    sorted_ids = sorted(identifiers)
    record["coordinate_convention"] = _declared_coordinate_convention(value)
    record["linked_entity_id_count"] = total[0]
    record["linked_entity_ids"] = sorted_ids[:512]
    record["details"] = {
        "top_level_keys": sorted(value.keys()) if isinstance(value, dict) else [],
        "top_level_collection_counts": _top_level_counts(value),
        "linked_entity_ids_truncated": len(sorted_ids) > 512,
        "geometry_key_hints": sorted(
            key
            for key in (value.keys() if isinstance(value, dict) else [])
            if any(token in str(key).lower() for token in ("geometry", "polygon", "ring", "coordinate", "projection"))
        ),
    }
    record["source_provenance"] = _provenance(value)
    return record


def build_inventory(root: Path | str) -> dict[str, Any]:
    root_path = Path(root).resolve()
    files: list[dict[str, Any]] = []
    for path in sorted(root_path.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(root_path)
        if relative.parts and relative.parts[0].lower() in {".git", ".godot", "artifacts", "build", "builds"}:
            continue
        if _map_related(relative):
            files.append(_inventory_file(root_path, path))
    files.sort(key=lambda item: item["path"])
    category_counts = Counter(item["category"] for item in files)
    return {
        "schema_version": SCHEMA_VERSION,
        "tool_version": TOOL_VERSION,
        "scope": "repository map-related visual, geometry, cache, and source assets",
        "files": files,
        "summary": {
            "asset_count": len(files),
            "category_counts": dict(sorted(category_counts.items())),
            "raster_count": category_counts.get("raster", 0),
            "vector_count": category_counts.get("vector", 0),
            "geometry_and_map_data_count": sum(
                category_counts.get(category, 0)
                for category in ("geometry_source", "geometry_cache", "map_data")
            ),
        },
    }


def _point(value: Any) -> tuple[float, float] | None:
    if not isinstance(value, (list, tuple)) or len(value) < 2:
        return None
    if not _is_finite_number(value[0]) or not _is_finite_number(value[1]):
        return None
    return (float(value[0]), float(value[1]))


def _looks_like_ring(value: Any) -> bool:
    return isinstance(value, list) and bool(value) and _point(value[0]) is not None


def _geojson_rings(coordinates: Any, geometry_type: str, location: str) -> list[dict[str, Any]]:
    rings: list[dict[str, Any]] = []
    if geometry_type == "Polygon" and isinstance(coordinates, list):
        for index, ring in enumerate(coordinates):
            if isinstance(ring, list):
                rings.append({"points": ring, "role": "outer" if index == 0 else "hole", "location": f"{location}.coordinates[{index}]"})
    elif geometry_type == "MultiPolygon" and isinstance(coordinates, list):
        for polygon_index, polygon in enumerate(coordinates):
            rings.extend(_geojson_rings(polygon, "Polygon", f"{location}.coordinates[{polygon_index}]"))
    elif _looks_like_ring(coordinates):
        rings.append({"points": coordinates, "role": "outer", "location": location})
    return rings


def extract_rings(value: Any, location: str = "geometry") -> list[dict[str, Any]]:
    """Extract polygon rings from the repository's JSON and GeoJSON variants."""

    if isinstance(value, dict):
        if isinstance(value.get("geometry"), (dict, list)):
            return extract_rings(value["geometry"], f"{location}.geometry")
        if "coordinates" in value:
            return _geojson_rings(value.get("coordinates"), str(value.get("type", "")), location)
        if isinstance(value.get("polygons"), list):
            rings: list[dict[str, Any]] = []
            for index, polygon in enumerate(value["polygons"]):
                polygon_location = f"{location}.polygons[{index}]"
                if isinstance(polygon, dict):
                    if "outer" in polygon:
                        rings.append({"points": polygon["outer"], "role": "outer", "location": f"{polygon_location}.outer"})
                    for hole_index, hole in enumerate(polygon.get("holes", [])):
                        rings.append({"points": hole, "role": "hole", "location": f"{polygon_location}.holes[{hole_index}]"})
                    if "outer" not in polygon and "coordinates" in polygon:
                        rings.extend(_geojson_rings(polygon["coordinates"], str(polygon.get("type", "")), polygon_location))
                else:
                    rings.extend(extract_rings(polygon, polygon_location))
            return rings
        if "outer" in value:
            rings = [{"points": value["outer"], "role": "outer", "location": f"{location}.outer"}]
            for index, hole in enumerate(value.get("holes", [])):
                rings.append({"points": hole, "role": "hole", "location": f"{location}.holes[{index}]"})
            return rings
        if isinstance(value.get("rings"), list):
            return [
                {"points": ring, "role": "outer", "location": f"{location}.rings[{index}]"}
                for index, ring in enumerate(value["rings"])
            ]
        return []
    if _looks_like_ring(value):
        return [{"points": value, "role": "outer", "location": location}]
    if isinstance(value, list):
        rings: list[dict[str, Any]] = []
        for index, child in enumerate(value):
            rings.extend(extract_rings(child, f"{location}[{index}]"))
        return rings
    return []


def extract_polygons(value: Any, location: str = "geometry") -> list[dict[str, Any]]:
    """Extract grouped outer/holes polygons for rasterization."""

    if isinstance(value, dict):
        if isinstance(value.get("geometry"), (dict, list)):
            return extract_polygons(value["geometry"], f"{location}.geometry")
        if "coordinates" in value:
            geometry_type = str(value.get("type", ""))
            if geometry_type == "Polygon":
                coordinates = value["coordinates"]
                if isinstance(coordinates, list) and coordinates:
                    return [{"outer": coordinates[0], "holes": coordinates[1:], "location": location}]
            if geometry_type == "MultiPolygon":
                result: list[dict[str, Any]] = []
                for index, coordinates in enumerate(value.get("coordinates", [])):
                    result.extend(extract_polygons({"type": "Polygon", "coordinates": coordinates}, f"{location}[{index}]"))
                return result
        if isinstance(value.get("polygons"), list):
            result = []
            for index, polygon in enumerate(value["polygons"]):
                if isinstance(polygon, dict) and "outer" in polygon:
                    result.append({"outer": polygon["outer"], "holes": polygon.get("holes", []), "location": f"{location}.polygons[{index}]"})
                else:
                    result.extend(extract_polygons(polygon, f"{location}.polygons[{index}]"))
            return result
        if "outer" in value:
            return [{"outer": value["outer"], "holes": value.get("holes", []), "location": location}]
        if isinstance(value.get("rings"), list) and value["rings"]:
            return [{"outer": value["rings"][0], "holes": value["rings"][1:], "location": location}]
        return []
    if _looks_like_ring(value):
        return [{"outer": value, "holes": [], "location": location}]
    return []


def _geometry_records(root: Path) -> Iterator[dict[str, Any]]:
    documents = [
        ("data/world_map/world_coastlines.json", "features", "country_coastline"),
        ("data/world_map/world_admin1.json", "regions", "admin1"),
        ("data/world_map/regions.json", "administrative_units", "administrative_unit"),
        ("data/world_map/historical/cshapes_1900_snapshot.json", "features", "historical_unit"),
    ]
    for relative, collection_key, entity_type in documents:
        path = root / relative
        if not path.exists():
            continue
        data = _load_json(path)
        for index, row in enumerate(data.get(collection_key, [])):
            identifier = row.get("id") or row.get("stable_id") or row.get("unit_id") or f"{collection_key}_{index}"
            geometry = row.get("geometry", row)
            yield {
                "source": relative,
                "collection": collection_key,
                "entity_type": entity_type,
                "feature_id": str(identifier),
                "geometry": geometry,
                "declared_bounds": row.get("bounds"),
            }
    cache_path = root / "data/world_map/map_geometry_cache.json"
    if cache_path.exists():
        data = _load_json(cache_path)
        for group in ("country_lods", "administrative_lods"):
            for lod, rows in data.get(group, {}).items():
                if not isinstance(rows, list):
                    continue
                for index, row in enumerate(rows):
                    identifier = (
                        row.get("unit_id")
                        or row.get("stable_id")
                        or row.get("country_id")
                        or row.get("id")
                        or f"{group}_{lod}_{index}"
                    )
                    yield {
                        "source": "data/world_map/map_geometry_cache.json",
                        "collection": f"{group}.{lod}",
                        "entity_type": "cache_feature",
                        "feature_id": str(identifier),
                        "geometry": row,
                        "declared_bounds": row.get("bounds"),
                    }


def _ring_points(raw: Any) -> tuple[list[tuple[float, float]] | None, list[str]]:
    errors: list[str] = []
    if not isinstance(raw, list):
        return None, ["ring_not_array"]
    points: list[tuple[float, float]] = []
    for index, item in enumerate(raw):
        point = _point(item)
        if point is None:
            errors.append(f"invalid_point[{index}]")
        else:
            points.append(point)
    if not errors and len(points) > 1 and points[0] == points[-1]:
        points = points[:-1]
    return points if not errors else None, errors


def _signed_area(points: Sequence[tuple[float, float]]) -> float:
    return 0.5 * sum(
        points[index][0] * points[(index + 1) % len(points)][1]
        - points[(index + 1) % len(points)][0] * points[index][1]
        for index in range(len(points))
    )


def _bbox(points: Sequence[tuple[float, float]]) -> list[float]:
    return [min(point[0] for point in points), min(point[1] for point in points), max(point[0] for point in points), max(point[1] for point in points)]


def _bbox_overlap(first: Sequence[float], second: Sequence[float]) -> bool:
    return not (first[2] < second[0] - FINITE_EPSILON or second[2] < first[0] - FINITE_EPSILON or first[3] < second[1] - FINITE_EPSILON or second[3] < first[1] - FINITE_EPSILON)


def _orientation(a: tuple[float, float], b: tuple[float, float], c: tuple[float, float]) -> float:
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def _on_segment(a: tuple[float, float], b: tuple[float, float], p: tuple[float, float]) -> bool:
    return min(a[0], b[0]) - FINITE_EPSILON <= p[0] <= max(a[0], b[0]) + FINITE_EPSILON and min(a[1], b[1]) - FINITE_EPSILON <= p[1] <= max(a[1], b[1]) + FINITE_EPSILON


def _segments_intersect(a: tuple[float, float], b: tuple[float, float], c: tuple[float, float], d: tuple[float, float]) -> bool:
    first = _orientation(a, b, c)
    second = _orientation(a, b, d)
    third = _orientation(c, d, a)
    fourth = _orientation(c, d, b)
    if ((first > FINITE_EPSILON and second < -FINITE_EPSILON) or (first < -FINITE_EPSILON and second > FINITE_EPSILON)) and ((third > FINITE_EPSILON and fourth < -FINITE_EPSILON) or (third < -FINITE_EPSILON and fourth > FINITE_EPSILON)):
        return True
    return (
        abs(first) <= FINITE_EPSILON and _on_segment(a, b, c)
        or abs(second) <= FINITE_EPSILON and _on_segment(a, b, d)
        or abs(third) <= FINITE_EPSILON and _on_segment(c, d, a)
        or abs(fourth) <= FINITE_EPSILON and _on_segment(c, d, b)
    )


def _self_intersection(points: Sequence[tuple[float, float]]) -> tuple[int, int] | None:
    # A pathological source ring should not monopolize a batch run.  The
    # repository's generated rings are far below this bound; if a future
    # provider exceeds it, the QA output records that the check was skipped.
    if len(points) > 5000:
        return (-1, -1)
    segments = [
        (points[index], points[(index + 1) % len(points)], _bbox([points[index], points[(index + 1) % len(points)]]))
        for index in range(len(points))
    ]
    for first_index, (first_a, first_b, first_bbox) in enumerate(segments):
        for second_index in range(first_index + 1, len(segments)):
            if second_index in {first_index + 1, first_index - 1}:
                continue
            if first_index == 0 and second_index == len(segments) - 1:
                continue
            second_a, second_b, second_bbox = segments[second_index]
            if _bbox_overlap(first_bbox, second_bbox) and _segments_intersect(first_a, first_b, second_a, second_b):
                shared_endpoint = any(
                    abs(first_point[0] - second_point[0]) <= FINITE_EPSILON
                    and abs(first_point[1] - second_point[1]) <= FINITE_EPSILON
                    for first_point in (first_a, first_b)
                    for second_point in (second_a, second_b)
                )
                if shared_endpoint:
                    continue
                return (first_index, second_index)
    return None


def _point_in_ring(point: tuple[float, float], ring: Sequence[tuple[float, float]]) -> bool:
    inside = False
    x, y = point
    for index in range(len(ring)):
        first = ring[index]
        second = ring[(index + 1) % len(ring)]
        if (first[1] > y) != (second[1] > y):
            crossing = (second[0] - first[0]) * (y - first[1]) / (second[1] - first[1]) + first[0]
            if x < crossing:
                inside = not inside
    return inside


def _canonical_ring(points: Sequence[tuple[float, float]]) -> tuple[tuple[float, float], ...]:
    normalized = [(round(x, 9), round(y, 9)) for x, y in points]
    if len(normalized) > 1 and normalized[0] == normalized[-1]:
        normalized = normalized[:-1]
    if not normalized:
        return ()
    variants: list[tuple[tuple[float, float], ...]] = []
    for sequence in (normalized, list(reversed(normalized))):
        for index in range(len(sequence)):
            variants.append(tuple(sequence[index:] + sequence[:index]))
    return min(variants)


def _finding(severity: str, code: str, message: str, source: str = "", feature_id: str = "", location: str = "", related_ids: Iterable[str] = ()) -> dict[str, Any]:
    finding = {
        "severity": severity,
        "code": code,
        "message": message,
        "source": source,
        "feature_id": feature_id,
        "location": location,
        "related_ids": sorted({str(value) for value in related_ids}),
    }
    finding["finding_id"] = hashlib.sha256(_stable_json(finding).encode("utf-8")).hexdigest()[:16]
    return finding


def geometry_qa(root: Path | str) -> dict[str, Any]:
    root_path = Path(root).resolve()
    findings: list[dict[str, Any]] = []
    source_stats: dict[str, dict[str, int]] = defaultdict(lambda: {"features": 0, "rings": 0, "polygons": 0})
    seen_polygons: dict[str, dict[tuple[tuple[float, float], ...], str]] = defaultdict(dict)
    records = list(_geometry_records(root_path))
    for record in records:
        source = record["source"]
        feature_id = record["feature_id"]
        stats = source_stats[source]
        stats["features"] += 1
        rings = extract_rings(record["geometry"], "geometry")
        polygons = extract_polygons(record["geometry"], "geometry")
        stats["rings"] += len(rings)
        stats["polygons"] += len(polygons)
        if not rings:
            findings.append(_finding("ERROR", "empty_geometry", "Feature has no polygon rings.", source, feature_id))
            continue
        valid_rings: list[dict[str, Any]] = []
        outer_rings: list[list[tuple[float, float]]] = []
        hole_rings: list[list[tuple[float, float]]] = []
        for ring in rings:
            points, errors = _ring_points(ring["points"])
            if errors:
                for error in errors:
                    severity = "ERROR" if error == "invalid_point[0]" or error == "ring_not_array" else "ERROR"
                    findings.append(_finding(severity, "malformed_ring", error, source, feature_id, ring["location"]))
                continue
            assert points is not None
            if len(points) < 3:
                findings.append(_finding("ERROR", "invalid_ring", "Ring contains fewer than three valid vertices.", source, feature_id, ring["location"]))
                continue
            area = _signed_area(points)
            if abs(area) <= FINITE_EPSILON:
                findings.append(_finding("ERROR", "zero_area", "Ring has zero signed area.", source, feature_id, ring["location"]))
            if len(set((round(x, 9), round(y, 9)) for x, y in points)) != len(points):
                findings.append(_finding("WARNING", "duplicate_vertex", "Ring contains duplicate vertices.", source, feature_id, ring["location"]))
            intersection = _self_intersection(points)
            if intersection == (-1, -1):
                findings.append(_finding("INFO", "self_intersection_check_skipped", "Ring exceeds the bounded intersection-check size.", source, feature_id, ring["location"]))
            elif intersection is not None:
                findings.append(_finding("ERROR", "self_intersection", f"Non-adjacent edges {intersection[0]} and {intersection[1]} intersect.", source, feature_id, ring["location"]))
            canonical = _canonical_ring(points)
            previous = seen_polygons[source + ":" + record["collection"]].get(canonical)
            if previous is not None:
                findings.append(_finding("WARNING", "duplicate_polygon", "Polygon ring is duplicated within the same geometry collection.", source, feature_id, ring["location"], [previous]))
            else:
                seen_polygons[source + ":" + record["collection"]][canonical] = feature_id
            validated = {"points": points, "role": ring["role"], "location": ring["location"], "area": area}
            valid_rings.append(validated)
            if ring["role"] == "hole":
                hole_rings.append(points)
            else:
                outer_rings.append(points)
        for hole in hole_rings:
            if outer_rings and not _point_in_ring(hole[0], outer_rings[0]):
                findings.append(_finding("WARNING", "hole_outside_outer", "Hole representative point is outside the first outer ring.", source, feature_id))
        if outer_rings:
            areas = sorted(((abs(_signed_area(ring)), ring) for ring in outer_rings), reverse=True, key=lambda item: item[0])
            total_area = sum(item[0] for item in areas)
            if total_area > FINITE_EPSILON and len(areas) > 1:
                for fragment_area, _ in areas[1:]:
                    if fragment_area / total_area < TINY_FRAGMENT_RATIO:
                        findings.append(_finding("WARNING", "extremely_small_fragment", "Outer polygon is an unusually small fraction of its feature area.", source, feature_id))
        if record.get("declared_bounds") is not None and valid_rings:
            bounds = record["declared_bounds"]
            if not isinstance(bounds, list) or len(bounds) != 4 or not all(_is_finite_number(item) for item in bounds):
                findings.append(_finding("ERROR", "impossible_bounds", "Declared bounds are not four finite numbers.", source, feature_id))
            else:
                min_x, min_y, width, height = [float(item) for item in bounds]
                if width < -FINITE_EPSILON or height < -FINITE_EPSILON:
                    findings.append(_finding("ERROR", "impossible_bounds", "Declared bounds have negative width or height.", source, feature_id))
                else:
                    maximum_x = min_x + width
                    maximum_y = min_y + height
                    for ring in valid_rings:
                        for x, y in ring["points"]:
                            if x < min_x - FINITE_EPSILON or x > maximum_x + FINITE_EPSILON or y < min_y - FINITE_EPSILON or y > maximum_y + FINITE_EPSILON:
                                findings.append(_finding("ERROR", "impossible_bounds", "Coordinate falls outside declared bounds.", source, feature_id, ring["location"]))
                                break
                        else:
                            continue
                        break
        if len(outer_rings) and hole_rings:
            outer_sign = 1 if _signed_area(outer_rings[0]) >= 0 else -1
            for hole in hole_rings:
                if (1 if _signed_area(hole) >= 0 else -1) == outer_sign:
                    findings.append(_finding("WARNING", "malformed_winding", "Hole winding matches its outer ring where opposite winding is expected.", source, feature_id))
    findings.sort(key=lambda item: (item["source"], item["feature_id"], item["code"], item["location"], item["finding_id"]))
    severity_counts = Counter(item["severity"] for item in findings)
    source_output = []
    for source in sorted(source_stats):
        source_output.append({"source": source, **source_stats[source]})
    return {
        "schema_version": SCHEMA_VERSION,
        "tool_version": TOOL_VERSION,
        "sources": source_output,
        "findings": findings,
        "summary": {
            "feature_count": len(records),
            "finding_count": len(findings),
            "severity_counts": dict(sorted(severity_counts.items())),
            "error_count": severity_counts.get("ERROR", 0),
            "warning_count": severity_counts.get("WARNING", 0),
            "info_count": severity_counts.get("INFO", 0),
        },
    }


def _cache_index(data: dict[str, Any], group: str) -> dict[str, list[dict[str, Any]]]:
    index: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for lod, rows in data.get(group, {}).items():
        if not isinstance(rows, list):
            continue
        for row in rows:
            for key in ("id", "stable_id", "unit_id", "country_id", "country_iso_a3"):
                value = row.get(key)
                if value not in (None, ""):
                    index[str(value)].append({"lod": str(lod), "id": str(value), "row": row})
    return index


def _crosswalk_record(
    entity_id: str,
    entity_type: str,
    source_path: str,
    geometry_status: str,
    geometry_ids: Iterable[str] = (),
    geometry_refs: Iterable[dict[str, Any]] = (),
    source_assets: Iterable[str] = (),
    parent_entity_ids: Iterable[str] = (),
    notes: Iterable[str] = (),
    candidate_mask: dict[str, Any] | None = None,
) -> dict[str, Any]:
    return {
        "entity_id": entity_id,
        "entity_type": entity_type,
        "source_record": source_path,
        "geometry_status": geometry_status,
        "geometry_ids": sorted({str(value) for value in geometry_ids}),
        "geometry_refs": sorted(list(geometry_refs), key=lambda item: _stable_json(item)),
        "source_assets": sorted({str(value) for value in source_assets}),
        "parent_entity_ids": sorted({str(value) for value in parent_entity_ids}),
        "candidate_mask": candidate_mask,
        "notes": sorted({str(value) for value in notes}),
    }


def _no_map_mask_candidate() -> dict[str, Any]:
    return {
        "status": "not_generated",
        "reason": "No suitable source map raster or map vector asset is present in the repository.",
        "source_raster_candidates": [],
    }


def _point_status(value: Any) -> bool:
    point = _point(value)
    return point is not None


def _find_geometry_refs(ids: Iterable[Any], by_id: dict[str, dict[str, Any]], by_stable: dict[str, dict[str, Any]], by_iso: dict[str, list[dict[str, Any]]], source: str, findings: list[dict[str, Any]], entity_id: str) -> list[dict[str, Any]]:
    refs: list[dict[str, Any]] = []
    for raw_id in ids:
        identifier = str(raw_id)
        feature = by_id.get(identifier) or by_stable.get(identifier)
        method = "exact_id"
        if feature is None:
            matches = by_iso.get(identifier, [])
            if len(matches) == 1:
                feature = matches[0]
                method = "iso_fallback"
            elif len(matches) > 1:
                findings.append(_finding("ERROR", "ambiguous_geometry_assignment", "Geometry identifier resolves to multiple features.", source, entity_id, related_ids=[str(item.get("id")) for item in matches]))
                continue
        if feature is None:
            findings.append(_finding("ERROR", "entity_without_geometry", "Entity geometry identifier does not resolve in the source geometry asset.", source, entity_id, related_ids=[identifier]))
            continue
        refs.append({"id": str(feature.get("id", "")), "stable_id": str(feature.get("stable_id", "")), "method": method, "source": "data/world_map/world_coastlines.json"})
    return refs


def build_crosswalk(root: Path | str) -> dict[str, Any]:
    root_path = Path(root).resolve()
    findings: list[dict[str, Any]] = []
    records: list[dict[str, Any]] = []
    countries_data = _load_json(root_path / "data/world_map/countries.json")
    regions_data = _load_json(root_path / "data/world_map/regions.json")
    cities_data = _load_json(root_path / "data/world_map/cities.json")
    ports_data = _load_json(root_path / "data/world_map/ports.json")
    rail_data = _load_json(root_path / "data/world_map/rail_segments.json")
    coast_data = _load_json(root_path / "data/world_map/world_coastlines.json")
    admin1_data = _load_json(root_path / "data/world_map/world_admin1.json")
    cache_data = _load_json(root_path / "data/world_map/map_geometry_cache.json")
    political_data = _load_json(root_path / "data/world_map/historical_political_entities_1900.json")
    historical_units_data = _load_json(root_path / "data/world_map/historical/political_units_1900.json")
    cshapes_data = _load_json(root_path / "data/world_map/historical/cshapes_1900_snapshot.json")
    historical_admin1_path = root_path / "data/world_map/historical/historical_admin1_1900.json"
    historical_admin1_data = _load_json(historical_admin1_path) if historical_admin1_path.exists() else {"countries": []}

    country_rows = countries_data.get("countries", [])
    country_by_id = {str(row.get("id")): row for row in country_rows}
    country_by_code = {
        str(row.get(key)): row
        for row in country_rows
        for key in ("data_code", "source_iso_a3")
        if row.get(key) not in (None, "", "-99")
    }
    coast_rows = coast_data.get("features", [])
    coast_by_id = {str(row.get("id")): row for row in coast_rows}
    coast_by_stable = {str(row.get("stable_id")): row for row in coast_rows if row.get("stable_id")}
    coast_by_iso: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in coast_rows:
        for key in ("iso_a3", "source_iso_a3"):
            if row.get(key) not in (None, ""):
                coast_by_iso[str(row[key])].append(row)
    admin1_rows = admin1_data.get("regions", [])
    admin1_by_code = {str(row.get("code")): row for row in admin1_rows if row.get("code")}
    admin1_by_id = {str(row.get("id")): row for row in admin1_rows if row.get("id")}
    cache_country = _cache_index(cache_data, "country_lods")
    cache_admin = _cache_index(cache_data, "administrative_lods")
    cshapes_rows = cshapes_data.get("features", [])
    cshapes_by_id = {str(row.get("id")): row for row in cshapes_rows}
    flag_dir = root_path / "assets/historical_flags/1900"
    flag_files = {path.stem: _relative_path(root_path, path) for path in flag_dir.glob("*") if path.is_file()}

    assigned_coast: dict[str, list[str]] = defaultdict(list)
    for row in country_rows:
        entity_id = str(row.get("id"))
        geometry_ids = row.get("geometry_feature_ids", [])
        refs = _find_geometry_refs(geometry_ids, coast_by_id, coast_by_stable, coast_by_iso, "data/world_map/countries.json", findings, entity_id)
        for ref in refs:
            assigned_coast[ref["id"]].append(entity_id)
        status = "resolved" if refs else "missing"
        records.append(
            _crosswalk_record(
                entity_id,
                "country",
                "data/world_map/countries.json",
                status,
                geometry_ids,
                refs,
                ["data/world_map/world_coastlines.json", "data/world_map/map_geometry_cache.json"],
                candidate_mask=_no_map_mask_candidate(),
            )
        )
        if not geometry_ids:
            findings.append(_finding("ERROR", "entity_without_geometry", "Country record has no geometry_feature_ids.", "data/world_map/countries.json", entity_id))
    for feature in coast_rows:
        feature_id = str(feature.get("id"))
        if feature_id not in assigned_coast:
            findings.append(_finding("INFO", "geometry_without_entity", "Coastline feature is not referenced by a current country record.", "data/world_map/world_coastlines.json", feature_id))
    for feature_id, entities in sorted(assigned_coast.items()):
        if len(entities) > 1:
            findings.append(_finding("ERROR", "duplicate_geometry_assignment", "One current country geometry is assigned to multiple country entities.", "data/world_map/countries.json", feature_id, related_ids=entities))

    admin_by_id: dict[str, dict[str, Any]] = {}
    for row in regions_data.get("administrative_units", []):
        entity_id = str(row.get("id"))
        admin_by_id[entity_id] = row
        geometry = row.get("geometry")
        has_geometry = bool(extract_rings(geometry))
        source_code = str(row.get("source_code", ""))
        source_assets = ["data/world_map/regions.json"]
        refs: list[dict[str, Any]] = []
        if source_code and source_code in admin1_by_code:
            source_feature = admin1_by_code[source_code]
            refs.append({"id": str(source_feature.get("id")), "code": source_code, "method": "source_code", "source": "data/world_map/world_admin1.json"})
            source_assets.append("data/world_map/world_admin1.json")
            expected_country = country_by_id.get(str(row.get("parent_country_id")), {}).get("data_code")
            if expected_country and str(source_feature.get("country_iso_a3")) != str(expected_country):
                findings.append(_finding("ERROR", "region_country_mismatch", "Administrative unit parent country differs from source geometry country.", "data/world_map/regions.json", entity_id, related_ids=[str(source_feature.get("country_iso_a3")), str(expected_country)]))
        elif source_code:
            findings.append(_finding("WARNING", "geometry_without_entity", "Administrative unit source_code does not resolve in world_admin1 provider.", "data/world_map/regions.json", entity_id, related_ids=[source_code]))
        if entity_id in cache_admin:
            source_assets.append("data/world_map/map_geometry_cache.json")
            refs.extend({"id": entity_id, "lod": item["lod"], "method": "cache_unit_id", "source": "data/world_map/map_geometry_cache.json"} for item in cache_admin[entity_id])
        elif has_geometry:
            findings.append(_finding("INFO", "geometry_without_entity", "Administrative unit has inline geometry but no matching cache unit entry.", "data/world_map/map_geometry_cache.json", entity_id))
        if not has_geometry:
            findings.append(_finding("ERROR", "empty_geometry", "Administrative unit geometry is empty or malformed.", "data/world_map/regions.json", entity_id))
        records.append(_crosswalk_record(entity_id, "administrative_unit", "data/world_map/regions.json", "resolved" if has_geometry else "malformed", [entity_id], refs, source_assets, [str(row.get("parent_country_id", ""))], candidate_mask=_no_map_mask_candidate()))
    for row in regions_data.get("regions", []):
        entity_id = str(row.get("id"))
        child_ids = [str(value) for value in row.get("administrative_unit_ids", [])]
        missing = [value for value in child_ids if value not in admin_by_id]
        if missing:
            findings.append(_finding("ERROR", "entity_without_geometry", "Macro region references missing administrative units.", "data/world_map/regions.json", entity_id, related_ids=missing))
        records.append(_crosswalk_record(entity_id, "macro_region", "data/world_map/regions.json", "composed" if child_ids and not missing else "missing", child_ids, [{"id": value, "method": "administrative_unit_composition", "source": "data/world_map/regions.json"} for value in child_ids if value in admin_by_id], ["data/world_map/regions.json", "data/world_map/map_geometry_cache.json"], [str(row.get("parent_country_id", ""))], candidate_mask=_no_map_mask_candidate()))

    city_ids = {str(row.get("id")) for row in cities_data.get("cities", [])}
    for row in cities_data.get("cities", []):
        entity_id = str(row.get("id"))
        if not _point_status(row.get("lon_lat")):
            findings.append(_finding("ERROR", "entity_without_geometry", "City has no finite lon_lat point.", "data/world_map/cities.json", entity_id))
        parent_ids = [str(row.get("parent_country_id", "")), str(row.get("parent_region_id", ""))]
        records.append(_crosswalk_record(entity_id, "city", "data/world_map/cities.json", "resolved_point" if _point_status(row.get("lon_lat")) else "missing", [entity_id] if _point_status(row.get("lon_lat")) else [], [{"id": entity_id, "kind": "lon_lat", "method": "inline_point", "source": "data/world_map/cities.json"}] if _point_status(row.get("lon_lat")) else [], ["data/world_map/cities.json"], parent_ids, candidate_mask={"status": "not_applicable", "reason": "Point entity has no polygon mask candidate."}))
    for row in ports_data.get("ports", []):
        entity_id = str(row.get("id"))
        if not _point_status(row.get("lon_lat")):
            findings.append(_finding("ERROR", "entity_without_geometry", "Port has no finite lon_lat point.", "data/world_map/ports.json", entity_id))
        city_id = str(row.get("city_id", ""))
        if city_id and city_id not in city_ids:
            findings.append(_finding("ERROR", "broken_entity_reference", "Port city_id does not resolve in cities.json.", "data/world_map/ports.json", entity_id, related_ids=[city_id]))
        records.append(_crosswalk_record(entity_id, "port", "data/world_map/ports.json", "resolved_point" if _point_status(row.get("lon_lat")) else "missing", [entity_id] if _point_status(row.get("lon_lat")) else [], [{"id": entity_id, "kind": "lon_lat", "method": "inline_point", "source": "data/world_map/ports.json"}] if _point_status(row.get("lon_lat")) else [], ["data/world_map/ports.json"], [city_id, str(row.get("parent_region_id", "")), str(row.get("parent_country_id", ""))], candidate_mask={"status": "not_applicable", "reason": "Point entity has no polygon mask candidate."}))
    for row in rail_data.get("segments", []):
        entity_id = str(row.get("id"))
        endpoints = [str(row.get("from_city_id", "")), str(row.get("to_city_id", ""))]
        missing = [value for value in endpoints if value not in city_ids]
        if missing:
            findings.append(_finding("ERROR", "broken_entity_reference", "Rail segment endpoint does not resolve in cities.json.", "data/world_map/rail_segments.json", entity_id, related_ids=missing))
        findings.append(_finding("INFO", "route_geometry_not_present", "Rail segment stores city endpoints but not exact track geometry.", "data/world_map/rail_segments.json", entity_id))
        records.append(_crosswalk_record(entity_id, "rail_segment", "data/world_map/rail_segments.json", "missing_expected", [], [], ["data/world_map/rail_segments.json"], endpoints, ["transport data explicitly has no exact track geometry"], {"status": "not_applicable", "reason": "Route is represented by endpoints only."}))

    historical_feature_ids: dict[str, list[str]] = defaultdict(list)
    for row in historical_units_data.get("units", []):
        entity_id = str(row.get("id"))
        geometry_id = str(row.get("geometry_feature_id", ""))
        feature = cshapes_by_id.get(geometry_id)
        if feature is None:
            findings.append(_finding("ERROR", "entity_without_geometry", "Historical political unit geometry_feature_id does not resolve in CShapes snapshot.", "data/world_map/historical/political_units_1900.json", entity_id, related_ids=[geometry_id]))
        else:
            historical_feature_ids[geometry_id].append(entity_id)
        flag_id = str(row.get("flag_id", ""))
        sources = ["data/world_map/historical/political_units_1900.json", "data/world_map/historical/cshapes_1900_snapshot.json"]
        notes: list[str] = []
        if flag_id in flag_files:
            sources.append(flag_files[flag_id])
        elif flag_id:
            findings.append(_finding("WARNING", "missing_visual_source", "Historical unit flag_id has no local raster asset.", "data/world_map/historical/political_units_1900.json", entity_id, related_ids=[flag_id]))
            notes.append("flag_visual_source_missing")
        records.append(_crosswalk_record(entity_id, "historical_political_unit_1900", "data/world_map/historical/political_units_1900.json", "resolved" if feature else "missing", [geometry_id] if feature else [], [{"id": geometry_id, "method": "geometry_feature_id", "source": "data/world_map/historical/cshapes_1900_snapshot.json"}] if feature else [], sources, [str(row.get("controller_id", ""))] if row.get("controller_id") else [], notes, _no_map_mask_candidate()))
    for geometry_id, entities in sorted(historical_feature_ids.items()):
        if len(entities) > 1:
            findings.append(_finding("ERROR", "duplicate_geometry_assignment", "CShapes geometry is assigned to multiple historical unit records.", "data/world_map/historical/political_units_1900.json", geometry_id, related_ids=entities))
    for feature in cshapes_rows:
        feature_id = str(feature.get("id"))
        if feature_id not in historical_feature_ids:
            findings.append(_finding("INFO", "geometry_without_entity", "CShapes feature is not referenced by political_units_1900.json.", "data/world_map/historical/cshapes_1900_snapshot.json", feature_id))
    for row in political_data.get("entities", []):
        entity_id = str(row.get("id"))
        members = [str(value) for value in row.get("members", []) if isinstance(value, (str, int))]
        member_rows = [country_by_id.get(member) or country_by_code.get(member) for member in members]
        member_geometry_ids = sorted({str(gid) for member_row in member_rows if member_row for gid in member_row.get("geometry_feature_ids", [])})
        missing_members = [member for member, member_row in zip(members, member_rows) if member_row is None]
        if missing_members:
            findings.append(_finding("WARNING", "ambiguous_geometry_assignment", "Historical political entity member is not a current country id.", "data/world_map/historical_political_entities_1900.json", entity_id, related_ids=missing_members))
        records.append(_crosswalk_record(entity_id, "historical_political_entity_1900", "data/world_map/historical_political_entities_1900.json", "composed" if member_geometry_ids else "missing", member_geometry_ids, [{"id": value, "method": "current_country_member", "source": "data/world_map/world_coastlines.json"} for value in member_geometry_ids], ["data/world_map/historical_political_entities_1900.json", "data/world_map/world_coastlines.json"], members, candidate_mask=_no_map_mask_candidate()))
    for row in historical_admin1_data.get("countries", []):
        entity_id = str(row.get("entity_id"))
        status = str(row.get("geometry_status", "declared_missing"))
        findings.append(_finding("INFO", "historical_geometry_not_digitized", "Historical admin-1 source declares geometry digitization is still required.", "data/world_map/historical/historical_admin1_1900.json", entity_id))
        records.append(_crosswalk_record(entity_id, "historical_admin1_group_1900", "data/world_map/historical/historical_admin1_1900.json", "declared_missing", [], [], ["data/world_map/historical/historical_admin1_1900.json"], notes=[status], candidate_mask=_no_map_mask_candidate()))

    unmatched_admin1 = [str(row.get("id")) for row in admin1_rows if str(row.get("code", "")) not in {str(item.get("source_code", "")) for item in regions_data.get("administrative_units", [])}]
    if unmatched_admin1:
        findings.append(_finding("INFO", "geometry_without_entity", "Global Natural Earth admin-1 provider contains features outside the project's focused administrative-unit crosswalk.", "data/world_map/world_admin1.json", related_ids=unmatched_admin1[:20]))
        findings[-1]["unmatched_count"] = len(unmatched_admin1)

    records.sort(key=lambda item: (item["entity_type"], item["entity_id"]))
    findings.sort(key=lambda item: (item["severity"], item["code"], item["source"], item["feature_id"], item["finding_id"]))
    status_counts = Counter(record["geometry_status"] for record in records)
    type_counts = Counter(record["entity_type"] for record in records)
    finding_counts = Counter(item["severity"] for item in findings)
    return {
        "schema_version": SCHEMA_VERSION,
        "tool_version": TOOL_VERSION,
        "input_sources": [
            "data/world_map/countries.json",
            "data/world_map/regions.json",
            "data/world_map/cities.json",
            "data/world_map/ports.json",
            "data/world_map/rail_segments.json",
            "data/world_map/world_coastlines.json",
            "data/world_map/world_admin1.json",
            "data/world_map/map_geometry_cache.json",
            "data/world_map/historical_political_entities_1900.json",
            "data/world_map/historical/political_units_1900.json",
            "data/world_map/historical/cshapes_1900_snapshot.json",
            "data/world_map/historical/historical_admin1_1900.json",
        ],
        "records": records,
        "findings": findings,
        "summary": {
            "entity_count": len(records),
            "entity_type_counts": dict(sorted(type_counts.items())),
            "geometry_status_counts": dict(sorted(status_counts.items())),
            "finding_severity_counts": dict(sorted(finding_counts.items())),
            "current_country_geometry_resolved": sum(1 for record in records if record["entity_type"] == "country" and record["geometry_status"] == "resolved"),
            "historical_unit_geometry_resolved": sum(1 for record in records if record["entity_type"] == "historical_political_unit_1900" and record["geometry_status"] == "resolved"),
            "candidate_masks_generated": 0,
            "candidate_mask_block_reason": "No suitable source map raster or map vector asset is present in the repository.",
        },
    }


def _png_chunks(data: bytes) -> Iterator[tuple[bytes, bytes]]:
    position = len(PNG_SIGNATURE)
    while position + 12 <= len(data):
        length = struct.unpack(">I", data[position : position + 4])[0]
        chunk_type = data[position + 4 : position + 8]
        chunk = data[position + 8 : position + 8 + length]
        position += 12 + length
        yield chunk_type, chunk
        if chunk_type == b"IEND":
            break


def _unfilter_png(raw: bytes, width: int, height: int, bytes_per_pixel: int) -> bytes:
    row_length = width * bytes_per_pixel
    expected = height * (row_length + 1)
    if len(raw) != expected:
        raise ValueError("PNG decompressed data length does not match IHDR")
    output = bytearray(height * row_length)
    input_position = 0
    for row in range(height):
        filter_type = raw[input_position]
        input_position += 1
        current = bytearray(raw[input_position : input_position + row_length])
        input_position += row_length
        previous_start = (row - 1) * row_length
        current_start = row * row_length
        for index in range(row_length):
            left = current[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
            up = output[previous_start + index] if row else 0
            up_left = output[previous_start + index - bytes_per_pixel] if row and index >= bytes_per_pixel else 0
            if filter_type == 1:
                current[index] = (current[index] + left) & 255
            elif filter_type == 2:
                current[index] = (current[index] + up) & 255
            elif filter_type == 3:
                current[index] = (current[index] + ((left + up) // 2)) & 255
            elif filter_type == 4:
                prediction = left + up - up_left
                distance_left = abs(prediction - left)
                distance_up = abs(prediction - up)
                distance_up_left = abs(prediction - up_left)
                if distance_left <= distance_up and distance_left <= distance_up_left:
                    predictor = left
                elif distance_up <= distance_up_left:
                    predictor = up
                else:
                    predictor = up_left
                current[index] = (current[index] + predictor) & 255
            elif filter_type != 0:
                raise ValueError(f"Unsupported PNG filter type {filter_type}")
        output[current_start : current_start + row_length] = current
    return bytes(output)


def read_png_rgba(path: Path) -> tuple[int, int, bytes]:
    data = path.read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError("only PNG input is supported without optional image decoders")
    width = height = bit_depth = color_type = interlace = None
    compressed: list[bytes] = []
    for chunk_type, chunk in _png_chunks(data):
        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type, _, _, interlace = struct.unpack(">IIBBBBB", chunk)
        elif chunk_type == b"IDAT":
            compressed.append(chunk)
    if width is None or height is None or bit_depth != 8 or interlace != 0:
        raise ValueError("PNG must be 8-bit and non-interlaced")
    channels = {0: 1, 2: 3, 4: 2, 6: 4}.get(color_type)
    if channels is None:
        raise ValueError(f"unsupported PNG color type {color_type}")
    raw = _unfilter_png(zlib.decompress(b"".join(compressed)), width, height, channels)
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


def write_png_rgba(path: Path, width: int, height: int, pixels: bytes) -> None:
    if len(pixels) != width * height * 4:
        raise ValueError("RGBA pixel buffer has the wrong length")

    def chunk(chunk_type: bytes, payload: bytes) -> bytes:
        return struct.pack(">I", len(payload)) + chunk_type + payload + struct.pack(">I", zlib.crc32(chunk_type + payload) & 0xFFFFFFFF)

    scanlines = b"".join(b"\x00" + pixels[row * width * 4 : (row + 1) * width * 4] for row in range(height))
    payload = PNG_SIGNATURE + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(scanlines, 9)) + chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)


def _resize_rgba(width: int, height: int, pixels: bytes, new_width: int, new_height: int) -> bytes:
    if (width, height) == (new_width, new_height):
        return pixels
    output = bytearray(new_width * new_height * 4)
    for y in range(new_height):
        source_y = min(height - 1, int(y * height / new_height))
        for x in range(new_width):
            source_x = min(width - 1, int(x * width / new_width))
            source = (source_y * width + source_x) * 4
            target = (y * new_width + x) * 4
            output[target : target + 4] = pixels[source : source + 4]
    return bytes(output)


def _mask_from_rgba(width: int, height: int, pixels: bytes) -> list[bool]:
    alpha_varies = any(pixels[index + 3] != 255 for index in range(0, len(pixels), 4))
    if alpha_varies:
        return [pixels[index + 3] > 0 for index in range(0, len(pixels), 4)]
    return [sum(pixels[index : index + 3]) > 0 for index in range(0, len(pixels), 4)]


def _resize_mask(width: int, height: int, mask: Sequence[bool], new_width: int, new_height: int) -> list[bool]:
    if (width, height) == (new_width, new_height):
        return list(mask)
    output: list[bool] = []
    for y in range(new_height):
        source_y = min(height - 1, int(y * height / new_height))
        for x in range(new_width):
            source_x = min(width - 1, int(x * width / new_width))
            output.append(bool(mask[source_y * width + source_x]))
    return output


def _mask_bbox(width: int, height: int, mask: Sequence[bool]) -> list[int] | None:
    points = [(index % width, index // width) for index, value in enumerate(mask) if value]
    if not points:
        return None
    min_x = min(point[0] for point in points)
    min_y = min(point[1] for point in points)
    max_x = max(point[0] for point in points)
    max_y = max(point[1] for point in points)
    return [min_x, min_y, max_x - min_x + 1, max_y - min_y + 1]


def _mask_components(width: int, height: int, mask: Sequence[bool]) -> tuple[int, int]:
    remaining = {index for index, value in enumerate(mask) if value}
    components = 0
    while remaining:
        components += 1
        start = remaining.pop()
        queue = deque([start])
        while queue:
            index = queue.popleft()
            x, y = index % width, index // width
            for dx, dy in ((-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < width and 0 <= ny < height:
                    neighbor = ny * width + nx
                    if neighbor in remaining:
                        remaining.remove(neighbor)
                        queue.append(neighbor)
    return components, sum(1 for value in mask if value)


def mask_qa(width: int, height: int, mask: Sequence[bool], source: str = "", candidate_bbox: Sequence[int] | None = None) -> dict[str, Any]:
    findings: list[dict[str, Any]] = []
    if len(mask) != width * height:
        findings.append(_finding("ERROR", "mask_size_mismatch", "Mask buffer size does not match its canvas.", source))
        return {"width": width, "height": height, "pixel_count": 0, "bbox": None, "components": 0, "findings": findings, "summary": {"error_count": 1, "warning_count": 0, "info_count": 0}}
    bbox = _mask_bbox(width, height, mask)
    components, pixel_count = _mask_components(width, height, mask)
    if pixel_count == 0:
        findings.append(_finding("ERROR", "empty_mask", "Mask contains no opaque pixels.", source))
    if pixel_count == width * height:
        findings.append(_finding("WARNING", "fully_opaque_mask", "Mask covers the entire source canvas.", source))
    if 0 < pixel_count < max(1, int(width * height * TINY_FRAGMENT_RATIO)):
        findings.append(_finding("WARNING", "extremely_tiny_mask", "Mask covers an unusually small fraction of its canvas.", source))
    if components > 1:
        severity = "WARNING" if components <= MAX_MASK_FRAGMENTS else "ERROR"
        findings.append(_finding(severity, "disconnected_fragments", f"Mask contains {components} disconnected fragments.", source))
    if components > MAX_MASK_FRAGMENTS:
        findings.append(_finding("ERROR", "excessive_fragment_count", f"Mask exceeds the configured fragment limit of {MAX_MASK_FRAGMENTS}.", source))
    if candidate_bbox is not None:
        x, y, box_width, box_height = [int(value) for value in candidate_bbox]
        if x < 0 or y < 0 or x + box_width > width or y + box_height > height:
            findings.append(_finding("WARNING", "candidate_bbox_outside_source_canvas", "Requested candidate bbox extends beyond the source canvas and will be clamped.", source))
    # A hole is a transparent component that does not touch the canvas edge.
    transparent = {index for index, value in enumerate(mask) if not value}
    holes = 0
    while transparent:
        start = transparent.pop()
        queue = deque([start])
        touches_edge = False
        while queue:
            index = queue.popleft()
            x, y = index % width, index // width
            if x in {0, width - 1} or y in {0, height - 1}:
                touches_edge = True
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < width and 0 <= ny < height:
                    neighbor = ny * width + nx
                    if neighbor in transparent:
                        transparent.remove(neighbor)
                        queue.append(neighbor)
        if not touches_edge:
            holes += 1
    if holes:
        findings.append(_finding("WARNING", "suspicious_holes", f"Mask contains {holes} enclosed transparent holes.", source))
    findings.sort(key=lambda item: (item["severity"], item["code"], item["finding_id"]))
    severity_counts = Counter(item["severity"] for item in findings)
    return {
        "width": width,
        "height": height,
        "pixel_count": pixel_count,
        "coverage_ratio": pixel_count / float(width * height) if width and height else 0.0,
        "bbox": bbox,
        "components": components,
        "holes": holes,
        "findings": findings,
        "summary": {
            "error_count": severity_counts.get("ERROR", 0),
            "warning_count": severity_counts.get("WARNING", 0),
            "info_count": severity_counts.get("INFO", 0),
        },
    }


def _rasterize_polygons(polygons: Sequence[dict[str, Any]], width: int, height: int, source_bounds: Sequence[float] | None = None) -> list[bool]:
    mask = [False] * (width * height)
    bounds = [float(value) for value in source_bounds] if source_bounds is not None else None
    if bounds is not None and len(bounds) != 4:
        raise ValueError("source_bounds must contain min_x,min_y,max_x,max_y")

    def transform(point: Any) -> tuple[float, float] | None:
        raw = _point(point)
        if raw is None:
            return None
        x, y = raw
        if bounds is None:
            return x, y
        min_x, min_y, max_x, max_y = bounds
        if max_x <= min_x or max_y <= min_y:
            raise ValueError("source_bounds must have positive width and height")
        return ((x - min_x) / (max_x - min_x) * (width - 1), (max_y - y) / (max_y - min_y) * (height - 1))

    for polygon in polygons:
        outer = [point for point in (transform(item) for item in polygon.get("outer", [])) if point is not None]
        holes = [[point for point in (transform(item) for item in hole) if point is not None] for hole in polygon.get("holes", [])]
        if len(outer) < 3:
            continue
        box = _bbox(outer)
        min_x = max(0, int(math.floor(box[0])))
        max_x = min(width - 1, int(math.ceil(box[2])))
        min_y = max(0, int(math.floor(box[1])))
        max_y = min(height - 1, int(math.ceil(box[3])))
        for y in range(min_y, max_y + 1):
            for x in range(min_x, max_x + 1):
                sample = (x + 0.5, y + 0.5)
                if _point_in_ring(sample, outer) and not any(len(hole) >= 3 and _point_in_ring(sample, hole) for hole in holes):
                    mask[y * width + x] = True
    return mask


def _find_geometry_polygons(value: Any, geometry_id: str) -> list[dict[str, Any]]:
    if isinstance(value, dict):
        identifiers = {str(value.get(key)) for key in ("id", "stable_id", "unit_id", "geometry_feature_id", "country_id") if value.get(key) not in (None, "")}
        if geometry_id in identifiers:
            geometry = value.get("geometry", value)
            polygons = extract_polygons(geometry)
            if polygons:
                return polygons
        for child in value.values():
            polygons = _find_geometry_polygons(child, geometry_id)
            if polygons:
                return polygons
    elif isinstance(value, list):
        for child in value:
            polygons = _find_geometry_polygons(child, geometry_id)
            if polygons:
                return polygons
    return []


def _crop_rgba(width: int, height: int, pixels: bytes, bbox: Sequence[int], mask: Sequence[bool]) -> tuple[int, int, bytes]:
    x, y, crop_width, crop_height = [int(value) for value in bbox]
    output = bytearray(crop_width * crop_height * 4)
    for local_y in range(crop_height):
        for local_x in range(crop_width):
            source_x = x + local_x
            source_y = y + local_y
            target = (local_y * crop_width + local_x) * 4
            if 0 <= source_x < width and 0 <= source_y < height and mask[source_y * width + source_x]:
                source = (source_y * width + source_x) * 4
                output[target : target + 4] = pixels[source : source + 4]
            else:
                output[target : target + 4] = b"\x00\x00\x00\x00"
    return crop_width, crop_height, bytes(output)


def _preview_pixels(width: int, height: int, pixels: bytes) -> bytes:
    output = bytearray(width * height * 4)
    for index in range(width * height):
        x, y = index % width, index // width
        checker = 218 if ((x // 8) + (y // 8)) % 2 == 0 else 190
        source = index * 4
        alpha = pixels[source + 3]
        output[source] = (pixels[source] * alpha + checker * (255 - alpha)) // 255
        output[source + 1] = (pixels[source + 1] * alpha + checker * (255 - alpha)) // 255
        output[source + 2] = (pixels[source + 2] * alpha + checker * (255 - alpha)) // 255
        output[source + 3] = 255
    return bytes(output)


def process_cutout(
    root: Path | str,
    source_path: Path | str,
    entity_id: str,
    output_dir: Path | str,
    mask_path: Path | str | None = None,
    geometry_file: Path | str | None = None,
    geometry_id: str | None = None,
    canonical_size: tuple[int, int] | None = None,
    padding: int = 0,
    source_bounds: Sequence[float] | None = None,
) -> dict[str, Any]:
    root_path = Path(root).resolve()
    source = Path(source_path)
    if not source.is_absolute():
        source = root_path / source
    output = Path(output_dir)
    if not output.is_absolute():
        output = root_path / output
    if source.resolve() == output.resolve() or output.resolve() in source.resolve().parents:
        raise ValueError("output directory must not contain or overwrite the source raster")
    width, height, pixels = read_png_rgba(source)
    requested_size = canonical_size or (width, height)
    if requested_size[0] <= 0 or requested_size[1] <= 0:
        raise ValueError("canonical_size must be positive")
    if requested_size != (width, height):
        pixels = _resize_rgba(width, height, pixels, requested_size[0], requested_size[1])
        width, height = requested_size
    mask_source = ""
    if mask_path is not None:
        mask_file = Path(mask_path)
        if not mask_file.is_absolute():
            mask_file = root_path / mask_file
        mask_width, mask_height, mask_pixels = read_png_rgba(mask_file)
        mask = _resize_mask(mask_width, mask_height, _mask_from_rgba(mask_width, mask_height, mask_pixels), width, height)
        mask_source = _relative_path(root_path, mask_file)
    elif geometry_file is not None and geometry_id:
        geometry_path = Path(geometry_file)
        if not geometry_path.is_absolute():
            geometry_path = root_path / geometry_path
        polygons = _find_geometry_polygons(_load_json(geometry_path), geometry_id)
        if not polygons:
            raise ValueError(f"geometry id {geometry_id!r} was not found or has no polygon")
        mask = _rasterize_polygons(polygons, width, height, source_bounds)
        mask_source = _relative_path(root_path, geometry_path) + "#" + geometry_id
    else:
        raise ValueError("provide either mask_path or geometry_file plus geometry_id")
    requested_bbox = _mask_bbox(width, height, mask)
    if requested_bbox is None:
        qa = mask_qa(width, height, mask, mask_source)
        raise ValueError("mask is empty: " + _stable_json(qa["summary"]))
    x, y, box_width, box_height = requested_bbox
    candidate_bbox = [x - padding, y - padding, box_width + padding * 2, box_height + padding * 2]
    qa = mask_qa(width, height, mask, mask_source, candidate_bbox)
    crop_bbox = [max(0, candidate_bbox[0]), max(0, candidate_bbox[1]), min(width, candidate_bbox[0] + candidate_bbox[2]) - max(0, candidate_bbox[0]), min(height, candidate_bbox[1] + candidate_bbox[3]) - max(0, candidate_bbox[1])]
    crop_width, crop_height, cutout = _crop_rgba(width, height, pixels, crop_bbox, mask)
    safe_entity = re.sub(r"[^A-Za-z0-9._-]+", "_", entity_id).strip("_") or "entity"
    normalized_name = safe_entity + ".png"
    mask_name = safe_entity + ".mask.png"
    preview_name = safe_entity + ".preview.png"
    manifest_name = safe_entity + ".manifest.json"
    output.mkdir(parents=True, exist_ok=True)
    normalized_path = output / normalized_name
    mask_output_path = output / mask_name
    preview_path = output / preview_name
    manifest_path = output / manifest_name
    write_png_rgba(normalized_path, crop_width, crop_height, cutout)
    crop_mask = bytearray(crop_width * crop_height * 4)
    for local_y in range(crop_height):
        for local_x in range(crop_width):
            source_x = crop_bbox[0] + local_x
            source_y = crop_bbox[1] + local_y
            opaque = 0 <= source_x < width and 0 <= source_y < height and mask[source_y * width + source_x]
            value = 255 if opaque else 0
            index = (local_y * crop_width + local_x) * 4
            crop_mask[index : index + 4] = bytes((value, value, value, value))
    write_png_rgba(mask_output_path, crop_width, crop_height, bytes(crop_mask))
    write_png_rgba(preview_path, crop_width, crop_height, _preview_pixels(crop_width, crop_height, cutout))
    manifest = {
        "schema_version": SCHEMA_VERSION,
        "generator_version": TOOL_VERSION,
        "entity_id": entity_id,
        "source_file": _relative_path(root_path, source),
        "source_hash": _file_hash(source),
        "mask_source": mask_source,
        "mask_hash": _file_hash(mask_output_path),
        "crop_bbox": crop_bbox,
        "requested_candidate_bbox": candidate_bbox,
        "mask_bbox": requested_bbox,
        "canvas_size": [width, height],
        "output_size": [crop_width, crop_height],
        "output_file": normalized_name,
        "mask_file": mask_name,
        "preview_file": preview_name,
        "processing_parameters": {
            "canonical_canvas_size": [width, height],
            "padding": int(padding),
            "resampling": "nearest_neighbor",
            "source_bounds": list(source_bounds) if source_bounds is not None else None,
            "alpha_mode": "source_alpha_intersect_mask",
            "original_preserved": True,
        },
        "mask_qa": qa,
    }
    _write_json(manifest_path, manifest)
    validation_errors = validate_manifest(manifest)
    if validation_errors:
        raise ValueError("manifest validation failed: " + ", ".join(validation_errors))
    return manifest


def validate_manifest(manifest: dict[str, Any]) -> list[str]:
    """Validate the stable fields required by manifest.schema.json."""
    errors: list[str] = []
    required = ("schema_version", "generator_version", "entity_id", "source_file", "source_hash", "crop_bbox", "mask_bbox", "canvas_size", "output_size", "processing_parameters")
    errors.extend("missing:" + key for key in required if key not in manifest)
    if manifest.get("schema_version") != SCHEMA_VERSION:
        errors.append("schema_version")
    for key in ("source_hash", "mask_hash"):
        value = manifest.get(key)
        if value is not None and (not isinstance(value, str) or re.fullmatch(r"[0-9a-f]{64}", value) is None):
            errors.append(key)
    for key in ("crop_bbox", "mask_bbox", "requested_candidate_bbox"):
        value = manifest.get(key)
        if value is not None and (not isinstance(value, list) or len(value) != 4 or not all(isinstance(item, int) for item in value)):
            errors.append(key)
    for key in ("canvas_size", "output_size"):
        value = manifest.get(key)
        if not isinstance(value, list) or len(value) != 2 or not all(isinstance(item, int) and item > 0 for item in value):
            errors.append(key)
    processing = manifest.get("processing_parameters")
    if not isinstance(processing, dict):
        errors.append("processing_parameters")
    else:
        if not isinstance(processing.get("padding"), int) or processing.get("padding", -1) < 0:
            errors.append("processing_parameters.padding")
        if processing.get("original_preserved") is not True:
            errors.append("processing_parameters.original_preserved")
    return sorted(set(errors))
def _output_path(root: Path, output_dir: Path | str) -> Path:
    path = Path(output_dir)
    return path if path.is_absolute() else root / path


def run_repository(root: Path | str, output_dir: Path | str = "artifacts/map-preprocessing/batch1") -> dict[str, Any]:
    root_path = Path(root).resolve()
    output = _output_path(root_path, output_dir)
    timings: dict[str, float] = {}
    start = time.perf_counter()
    inventory = build_inventory(root_path)
    timings["inventory_ms"] = round((time.perf_counter() - start) * 1000, 3)
    start = time.perf_counter()
    crosswalk = build_crosswalk(root_path)
    timings["crosswalk_ms"] = round((time.perf_counter() - start) * 1000, 3)
    start = time.perf_counter()
    qa = geometry_qa(root_path)
    timings["geometry_qa_ms"] = round((time.perf_counter() - start) * 1000, 3)
    _write_json(output / "inventory.json", inventory)
    _write_json(output / "crosswalk.json", crosswalk)
    _write_json(output / "geometry_qa.json", qa)
    summary = {
        "schema_version": SCHEMA_VERSION,
        "tool_version": TOOL_VERSION,
        "input_root": ".",
        "inventory_sha256": stable_hash(inventory),
        "crosswalk_sha256": stable_hash(crosswalk),
        "geometry_qa_sha256": stable_hash(qa),
        "source_assets_discovered": inventory["summary"],
        "entities_with_geometry": sum(
            1
            for record in crosswalk["records"]
            if record["geometry_status"] in {"resolved", "resolved_point", "composed"}
        ),
        "candidate_masks_generated": 0,
        "candidate_cutout_status": "BLOCKED_NO_SOURCE_MAP_ASSET",
        "candidate_cutout_reason": "Repository contains no suitable map raster or vector source; flag PNGs are visual flag assets, not spatial map sources.",
        "geometry_qa": qa["summary"],
        "benchmarks_ms": timings,
    }
    _write_json(output / "run_summary.json", summary)
    _write_json(output / "benchmark.json", {"schema_version": SCHEMA_VERSION, "tool_version": TOOL_VERSION, "benchmarks_ms": timings})
    return {"inventory": inventory, "crosswalk": crosswalk, "geometry_qa": qa, "summary": summary, "output_dir": output.as_posix()}


def deterministic_replay(root: Path | str, output_dir: Path | str = "artifacts/map-preprocessing/batch1") -> dict[str, Any]:
    result = run_repository(root, output_dir)
    root_path = Path(root).resolve()
    second_inventory = build_inventory(root_path)
    second_crosswalk = build_crosswalk(root_path)
    second_qa = geometry_qa(root_path)
    first_hashes = {
        "inventory": result["summary"]["inventory_sha256"],
        "crosswalk": result["summary"]["crosswalk_sha256"],
        "geometry_qa": result["summary"]["geometry_qa_sha256"],
    }
    second_hashes = {
        "inventory": stable_hash(second_inventory),
        "crosswalk": stable_hash(second_crosswalk),
        "geometry_qa": stable_hash(second_qa),
    }
    replay = {
        "schema_version": SCHEMA_VERSION,
        "tool_version": TOOL_VERSION,
        "pass": first_hashes == second_hashes,
        "first_hashes": first_hashes,
        "second_hashes": second_hashes,
        "checked_outputs": ["mask", "bbox", "manifest", "filenames", "QA findings"],
        "candidate_mask_replay": "not_run_no_source_map_asset",
    }
    _write_json(_output_path(root_path, output_dir) / "determinism.json", replay)
    return replay


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="WWO non-destructive map asset preprocessing")
    parser.add_argument("--root", default=".", help="repository root")
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("inventory", "crosswalk", "geometry-qa", "all", "determinism"):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("--output-dir", default="artifacts/map-preprocessing/batch1")
    preprocess = subparsers.add_parser("preprocess")
    preprocess.add_argument("--source", required=True)
    preprocess.add_argument("--entity-id", required=True)
    preprocess.add_argument("--output-dir", default="artifacts/map-preprocessing/candidates")
    preprocess.add_argument("--mask")
    preprocess.add_argument("--geometry-file")
    preprocess.add_argument("--geometry-id")
    preprocess.add_argument("--canonical-width", type=int)
    preprocess.add_argument("--canonical-height", type=int)
    preprocess.add_argument("--padding", type=int, default=0)
    preprocess.add_argument("--source-bounds", nargs=4, type=float)
    manifest_parser = subparsers.add_parser("validate-manifest")
    manifest_parser.add_argument("--path", required=True)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except AttributeError:  # pragma: no cover
        pass
    args = _parser().parse_args(argv)
    root = Path(args.root).resolve()
    if args.command == "validate-manifest":
        manifest_path = Path(args.path)
        if not manifest_path.is_absolute():
            manifest_path = root / manifest_path
        manifest = _load_json(manifest_path)
        errors = validate_manifest(manifest)
        print(_stable_json({"path": _relative_path(root, manifest_path), "pass": not errors, "errors": errors}))
        return 0 if not errors else 4
    if args.command == "inventory":
        value = build_inventory(root)
        _write_json(_output_path(root, args.output_dir) / "inventory.json", value)
        print(_stable_json(value["summary"]))
        return 0
    if args.command == "crosswalk":
        value = build_crosswalk(root)
        _write_json(_output_path(root, args.output_dir) / "crosswalk.json", value)
        print(_stable_json(value["summary"]))
        return 0
    if args.command == "geometry-qa":
        value = geometry_qa(root)
        _write_json(_output_path(root, args.output_dir) / "geometry_qa.json", value)
        print(_stable_json(value["summary"]))
        return 0 if value["summary"]["error_count"] == 0 else 2
    if args.command == "all":
        value = run_repository(root, args.output_dir)
        print(_stable_json(value["summary"]))
        return 0
    if args.command == "determinism":
        value = deterministic_replay(root, args.output_dir)
        print(_stable_json(value))
        return 0 if value["pass"] else 3
    if args.command == "preprocess":
        if not args.mask and not (args.geometry_file and args.geometry_id):
            raise SystemExit("preprocess requires --mask or --geometry-file plus --geometry-id")
        size = None
        if args.canonical_width is not None or args.canonical_height is not None:
            if args.canonical_width is None or args.canonical_height is None:
                raise SystemExit("canonical width and height must be supplied together")
            size = (args.canonical_width, args.canonical_height)
        manifest = process_cutout(root, args.source, args.entity_id, args.output_dir, args.mask, args.geometry_file, args.geometry_id, size, args.padding, args.source_bounds)
        print(_stable_json({"entity_id": manifest["entity_id"], "output_file": manifest["output_file"], "output_size": manifest["output_size"], "mask_qa": manifest["mask_qa"]["summary"]}))
        return 0
    raise AssertionError(args.command)


if __name__ == "__main__":
    raise SystemExit(main())
