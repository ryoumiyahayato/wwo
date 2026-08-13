"""Fail-closed R1 controls for the map preprocessing boundary."""

from __future__ import annotations

import hashlib
import math
import os
import re
import struct
import zlib
from collections import Counter
from pathlib import Path
from typing import Any, Iterator, Sequence

TOOL_VERSION = "1.2.0"
SCHEMA_VERSION = 1
APPROVED_CANDIDATE_ROOT = Path("artifacts/map-preprocessing")
SUPPORTED_COORDINATE_SPACES = {"PIXEL", "WGS84"}
SUPPORTED_MASK_MODES = {"alpha", "grayscale"}
SOURCE_CONTRACTS = {"approved_spatial", "synthetic_test"}
SOURCE_ADMISSION_STATUSES = {"approved", "synthetic_test"}
PROVENANCE_MANIFEST_PATH = Path("docs/data_sources/provenance_manifest.json")
APPROVED_SOURCE_CATEGORIES = {"map_visual_source", "map_raster_source"}
APPROVED_SOURCE_REVIEW_STATUSES = {"APPROVED", "REVIEWED_APPROVED", "APPROVED_FOR_MAP_PREPROCESSING"}
UNLICENSED_VALUES = {"", "LICENSE_UNKNOWN", "MIXED_EXPLICIT_AND_UNKNOWN", "NOT_APPLICABLE"}
SUPPORTED_SOURCE_FILE_TYPES = {"image/png"}


def install(namespace: dict[str, Any]) -> None:
    legacy = namespace["_legacy"]
    namespace.update({
        "TOOL_VERSION": TOOL_VERSION,
        "SCHEMA_VERSION": SCHEMA_VERSION,
        "APPROVED_CANDIDATE_ROOT": APPROVED_CANDIDATE_ROOT,
        "SUPPORTED_COORDINATE_SPACES": SUPPORTED_COORDINATE_SPACES,
        "SUPPORTED_MASK_MODES": SUPPORTED_MASK_MODES,
        "SOURCE_CONTRACTS": SOURCE_CONTRACTS,
        "SOURCE_ADMISSION_STATUSES": SOURCE_ADMISSION_STATUSES,
        "PROVENANCE_MANIFEST_PATH": PROVENANCE_MANIFEST_PATH,
        "SUPPORTED_SOURCE_FILE_TYPES": SUPPORTED_SOURCE_FILE_TYPES,
        "validate_candidate_output_dir": validate_candidate_output_dir,
        "candidate_source_status": candidate_source_status,
        "admit_source": lambda root, value, source_contract="approved_spatial": admit_source(legacy, root, value, source_contract),
        "resolve_unique_provider": resolve_unique_provider,
        "build_inventory": lambda root: build_inventory(legacy, root),
        "geometry_qa": lambda root: geometry_qa(legacy, root),
        "build_crosswalk": lambda root, inventory=None: build_crosswalk(legacy, root, inventory),
        "read_png_rgba": lambda path: read_png_rgba(legacy, path),
        "_read_png_header": lambda path: read_png_header(legacy, path),
        "_raster_metadata": lambda path: raster_metadata(legacy, path),
        "_mask_from_rgba": lambda width, height, pixels, mode=None: mask_from_rgba(width, height, pixels, mode),
        "_rasterize_polygons": lambda polygons, width, height, source_bounds=None, coordinate_space="PIXEL": rasterize_polygons(legacy, polygons, width, height, source_bounds, coordinate_space),
        "process_cutout": lambda *args, **kwargs: process_cutout(legacy, *args, **kwargs),
        "validate_manifest": lambda manifest, root=None, manifest_dir=None: validate_manifest(legacy, manifest, root, manifest_dir),
        "_output_path": lambda root, output_dir: validate_candidate_output_dir(root, output_dir),
        "run_repository": lambda root, output_dir="artifacts/map-preprocessing/batch1": run_repository(legacy, root, output_dir),
        "deterministic_replay": lambda root, output_dir="artifacts/map-preprocessing/batch1": deterministic_replay(legacy, root, output_dir),
        "main": lambda argv=None: main(legacy, argv),
    })


def canonical_key(path: Path) -> str:
    return os.path.normcase(str(path.resolve(strict=False)))


def is_within(path: Path, parent: Path, *, allow_equal: bool = True) -> bool:
    try:
        relative = path.resolve(strict=False).relative_to(parent.resolve(strict=False))
    except ValueError:
        return False
    return allow_equal or bool(relative.parts)


def validate_candidate_output_dir(root: Path | str, output_dir: Path | str) -> Path:
    root_path = Path(root).resolve()
    candidate_root = (root_path / APPROVED_CANDIDATE_ROOT).resolve(strict=False)
    if not is_within(candidate_root, root_path, allow_equal=False):
        raise ValueError("approved candidate root must remain inside the repository")
    path = Path(output_dir)
    if not path.is_absolute():
        path = root_path / path
    resolved = path.resolve(strict=False)
    if not is_within(resolved, root_path, allow_equal=False):
        raise ValueError("output directory must remain inside the repository")
    if resolved == root_path:
        raise ValueError("output directory must not be the repository root")
    if is_within(resolved, root_path / ".git"):
        raise ValueError("output directory must not be inside .git")
    if is_within(resolved, root_path / "data" / "world_map"):
        raise ValueError("output directory must not be inside data/world_map")
    if not is_within(resolved, candidate_root, allow_equal=False):
        raise ValueError("output directory must be inside artifacts/map-preprocessing")
    if resolved.exists() and not resolved.is_dir():
        raise ValueError("output path exists but is not a directory")
    return resolved


def resolve_input_path(root: Path, value: Path | str, label: str) -> Path:
    path = Path(value)
    if not path.is_absolute():
        path = root / path
    resolved = path.resolve(strict=False)
    if not is_within(resolved, root) or is_within(resolved, root / ".git"):
        raise ValueError(f"{label} must remain inside the repository and outside .git")
    if not resolved.is_file():
        raise ValueError(f"{label} does not exist as a file: {path}")
    return resolved


def _relative_source_key(root: Path, path: Path) -> str:
    try:
        return path.resolve(strict=False).relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.resolve(strict=False).as_posix()


def _is_historical_flag_path(root: Path, value: Path | str) -> bool:
    path = Path(value)
    if not path.is_absolute():
        path = root / path
    relative = _relative_source_key(root, path).casefold()
    return relative == "assets/historical_flags" or relative.startswith("assets/historical_flags/")


def _load_provenance_records(legacy: Any, root: Path) -> tuple[Path, list[dict[str, Any]]]:
    manifest_path = (root / PROVENANCE_MANIFEST_PATH).resolve(strict=False)
    if not manifest_path.is_file():
        raise ValueError(f"provenance manifest is missing: {PROVENANCE_MANIFEST_PATH.as_posix()}")
    try:
        document = legacy._load_json(manifest_path)
    except Exception as exc:
        raise ValueError(f"provenance manifest is not valid JSON: {type(exc).__name__}") from exc
    if not isinstance(document, dict) or not isinstance(document.get("entries"), list):
        raise ValueError("provenance manifest entries must be a list")
    records: list[dict[str, Any]] = []
    seen_paths: set[str] = set()
    for index, value in enumerate(document["entries"]):
        if not isinstance(value, dict):
            raise ValueError(f"provenance manifest entry {index} is not an object")
        path = value.get("path")
        if not isinstance(path, str) or not path or Path(path).is_absolute() or "\\" in path or ".." in Path(path).parts or Path(path).as_posix() != path:
            raise ValueError(f"provenance manifest entry {index} has an invalid path")
        if path in seen_paths:
            raise ValueError(f"provenance manifest contains duplicate path: {path}")
        seen_paths.add(path)
        records.append(value)
    return manifest_path, records


def _record_license(record: dict[str, Any]) -> str:
    value = record.get("license")
    return value.strip() if isinstance(value, str) else ""


def _record_is_approved_visual_source(record: dict[str, Any], source: Path) -> bool:
    category = record.get("category")
    file_type = record.get("file_type")
    review_status = record.get("review_status")
    license_name = _record_license(record)
    if category not in APPROVED_SOURCE_CATEGORIES:
        return False
    if file_type not in SUPPORTED_SOURCE_FILE_TYPES:
        return False
    if source.suffix.casefold() not in {".png"}:
        return False
    if record.get("kind") not in {"source", "generated"} or review_status not in APPROVED_SOURCE_REVIEW_STATUSES:
        return False
    coordinate_convention = record.get("coordinate_convention")
    if not isinstance(coordinate_convention, str) or not coordinate_convention.strip() or coordinate_convention == "not_declared":
        return False
    if license_name in UNLICENSED_VALUES:
        return False
    if not isinstance(record.get("source_locator"), list) or not any(isinstance(item, str) and item.strip() for item in record["source_locator"]):
        return False
    size_bytes = record.get("size_bytes")
    if not isinstance(size_bytes, int) or isinstance(size_bytes, bool) or size_bytes <= 0 or size_bytes != source.stat().st_size:
        return False
    expected_hash = record.get("sha256")
    return isinstance(expected_hash, str) and re.fullmatch(r"[0-9a-f]{64}", expected_hash) is not None


def admit_source(legacy: Any, root: Path | str, value: Path | str, source_contract: str = "approved_spatial") -> dict[str, Any]:
    if source_contract not in SOURCE_CONTRACTS:
        raise ValueError(f"source_contract must be one of {sorted(SOURCE_CONTRACTS)}")
    root_path = Path(root).resolve()
    if _is_historical_flag_path(root_path, value):
        raise ValueError("historical flag assets are visual-only and cannot be map sources")
    source = resolve_input_path(root_path, value, "source")
    if is_within(source, (root_path / APPROVED_CANDIDATE_ROOT).resolve(strict=False)):
        raise ValueError("candidate outputs cannot be admitted as source assets")
    source_key = _relative_source_key(root_path, source)
    if source_contract == "synthetic_test":
        return {"path": source, "contract": source_contract, "status": "synthetic_test", "record_file": None, "record": None, "category": "synthetic_test"}
    manifest_path, records = _load_provenance_records(legacy, root_path)
    matches = [record for record in records if record.get("path") == source_key]
    if len(matches) != 1:
        raise ValueError("source has no unique provenance record")
    record = matches[0]
    if not _record_is_approved_visual_source(record, source):
        raise ValueError("source provenance record is not approved for visual map preprocessing")
    actual_hash = legacy._file_hash(source)
    if record.get("sha256") != actual_hash:
        raise ValueError("source content hash does not match the provenance record")
    return {"path": source, "contract": source_contract, "status": "approved", "record_file": _relative_source_key(root_path, manifest_path), "record": record, "category": record["category"]}


def _png_chunks(data: bytes, signature: bytes) -> Iterator[tuple[bytes, bytes]]:
    if not data.startswith(signature):
        raise ValueError("only PNG input is supported")
    position = len(signature)
    seen_ihdr = False
    seen_iend = False
    while position < len(data):
        if position + 12 > len(data):
            raise ValueError("PNG chunk header is truncated")
        length = struct.unpack(">I", data[position : position + 4])[0]
        chunk_type = data[position + 4 : position + 8]
        end = position + 12 + length
        if end > len(data):
            raise ValueError("PNG chunk exceeds file bounds")
        chunk = data[position + 8 : position + 8 + length]
        expected_crc = struct.unpack(">I", data[position + 8 + length : end])[0]
        if zlib.crc32(chunk_type + chunk) & 0xFFFFFFFF != expected_crc:
            raise ValueError("PNG chunk CRC is invalid")
        position = end
        if not seen_ihdr and chunk_type != b"IHDR":
            raise ValueError("PNG IHDR must be the first chunk")
        if chunk_type == b"IHDR":
            if seen_ihdr or len(chunk) != 13:
                raise ValueError("PNG must contain exactly one 13-byte IHDR")
            seen_ihdr = True
        yield chunk_type, chunk
        if chunk_type == b"IEND":
            if chunk:
                raise ValueError("PNG IEND must be empty")
            seen_iend = True
            break
    if not seen_ihdr:
        raise ValueError("PNG is missing IHDR")
    if not seen_iend or position != len(data):
        raise ValueError("PNG must end at IEND")


def read_png_header(legacy: Any, path: Path) -> dict[str, Any]:
    width = height = bit_depth = color_type = interlace = None
    for chunk_type, chunk in _png_chunks(path.read_bytes(), legacy.PNG_SIGNATURE):
        if chunk_type == b"tRNS":
            raise ValueError("PNG tRNS transparency is unsupported")
        if chunk_type != b"IHDR":
            continue
        width, height, bit_depth, color_type, compression, filter_method, interlace = struct.unpack(">IIBBBBB", chunk)
        if width <= 0 or height <= 0 or compression != 0 or filter_method != 0 or bit_depth != 8 or color_type not in {0, 2, 4, 6} or interlace != 0:
            raise ValueError("unsupported PNG IHDR semantics")
    if width is None or height is None:
        raise ValueError("PNG is missing IHDR")
    return {"dimensions": [int(width), int(height)], "bit_depth": int(bit_depth), "color_type": int(color_type), "alpha_availability": "present" if color_type in {4, 6} else "absent", "coordinate_convention": "pixel_origin_top_left"}


def raster_metadata(legacy: Any, path: Path) -> dict[str, Any]:
    try:
        return read_png_header(legacy, path)
    except Exception as exc:
        return {"dimensions": None, "alpha_availability": "unknown", "coordinate_convention": "pixel_origin_top_left", "details": {"parse_error": f"{type(exc).__name__}: {exc}"}}


def build_inventory(legacy: Any, root: Path | str) -> dict[str, Any]:
    original = getattr(legacy, "_r1_original_build_inventory", legacy.build_inventory)
    raster_original = legacy._raster_metadata
    legacy._raster_metadata = lambda path: raster_metadata(legacy, path)
    try:
        result = original(root)
    finally:
        legacy._raster_metadata = raster_original
    result["tool_version"] = TOOL_VERSION
    return result

def _point(legacy: Any, value: Any) -> tuple[float, float] | None:
    if not isinstance(value, (list, tuple)) or len(value) != 2:
        return None
    if not legacy._is_finite_number(value[0]) or not legacy._is_finite_number(value[1]):
        return None
    return float(value[0]), float(value[1])


def _extract_polygons(legacy: Any, value: Any, location: str = "geometry", original=None) -> list[dict[str, Any]]:
    if isinstance(value, list) and not (value and _point(legacy, value[0]) is not None):
        result: list[dict[str, Any]] = []
        for index, child in enumerate(value):
            result.extend(_extract_polygons(legacy, child, f"{location}[{index}]", original))
        return result
    extractor = original if original is not None else legacy.extract_polygons
    return extractor(value, location)


def _find_geometry_polygons(legacy: Any, value: Any, geometry_id: str) -> list[dict[str, Any]]:
    if isinstance(value, dict):
        identifiers = {str(value.get(key)) for key in ("id", "stable_id", "unit_id", "geometry_feature_id", "country_id") if value.get(key) not in (None, "")}
        if geometry_id in identifiers:
            return _extract_polygons(legacy, value.get("geometry", value))
        for child in value.values():
            found = _find_geometry_polygons(legacy, child, geometry_id)
            if found:
                return found
    elif isinstance(value, list):
        for child in value:
            found = _find_geometry_polygons(legacy, child, geometry_id)
            if found:
                return found
    return []


def _geometry_records(legacy: Any, root: Path, original=None) -> Iterator[dict[str, Any]]:
    reader = original if original is not None else legacy._geometry_records
    coordinate_cache: dict[str, str | None] = {}
    for record in reader(root):
        result = dict(record)
        source_name = str(record["source"])
        if source_name not in coordinate_cache:
            try:
                declared = legacy._declared_coordinate_convention(legacy._load_json(root / source_name)).upper()
                coordinate_cache[source_name] = "WGS84" if any(token in declared for token in ("WGS84", "LONGITUDE", "LATITUDE")) else None
            except Exception:
                coordinate_cache[source_name] = None
        result["coordinate_space"] = coordinate_cache[source_name]
        yield result

def _has_antimeridian_jump(points: Sequence[tuple[float, float]]) -> bool:
    return bool(points) and any(abs(points[index][0] - points[(index + 1) % len(points)][0]) > 180 for index in range(len(points)))


def geometry_qa(legacy: Any, root: Path | str) -> dict[str, Any]:
    originals = legacy._point, legacy.extract_polygons, legacy._geometry_records
    legacy._point = lambda value: _point(legacy, value)
    legacy.extract_polygons = lambda value, location="geometry": _extract_polygons(legacy, value, location, originals[1])
    legacy._geometry_records = lambda path: _geometry_records(legacy, path, originals[2])
    try:
        original_qa = getattr(legacy, "_r1_original_geometry_qa", legacy.geometry_qa)
        result = original_qa(root)
    finally:
        legacy._point, legacy.extract_polygons, legacy._geometry_records = originals
    records = list(_geometry_records(legacy, Path(root).resolve(), originals[2]))
    by_key = {(item["source"], item["feature_id"]): item for item in records}
    filtered: list[dict[str, Any]] = []
    for finding in result["findings"]:
        record = by_key.get((finding["source"], finding["feature_id"]))
        if record is not None and finding["code"] == "hole_outside_outer":
            rings = legacy.extract_rings(record["geometry"], "geometry")
            outers: list[list[tuple[float, float]]] = []
            holes: list[list[tuple[float, float]]] = []
            for ring in rings:
                points, errors = legacy._ring_points(ring["points"])
                if errors or points is None or len(points) < 3:
                    continue
                (holes if ring["role"] == "hole" else outers).append(points)
            if outers and holes and all(any(legacy._point_in_ring(point, outer) for outer in outers) for hole in holes for point in hole):
                continue
        if record is not None and finding["code"] == "self_intersection" and record.get("coordinate_space") == "WGS84":
            points = [legacy._ring_points(ring["points"])[0] for ring in legacy.extract_rings(record["geometry"], "geometry")]
            if any(item is not None and _has_antimeridian_jump(item) for item in points):
                continue
        filtered.append(finding)
    for record in records:
        if record.get("coordinate_space") != "WGS84":
            continue
        for ring in legacy.extract_rings(record["geometry"], "geometry"):
            points, errors = legacy._ring_points(ring["points"])
            if errors or points is None or len(points) < 3 or not _has_antimeridian_jump(points):
                continue
            filtered.append(legacy._finding("WARNING", "antimeridian_wrap_unsupported", "Geographic ring crosses the antimeridian; Cartesian intersection QA is skipped for this ring.", record["source"], record["feature_id"], ring["location"]))
    filtered.sort(key=lambda item: (item["source"], item["feature_id"], item["code"], item["location"], item["finding_id"]))
    counts = Counter(item["severity"] for item in filtered)
    result["findings"] = filtered
    result["tool_version"] = TOOL_VERSION
    result["summary"] = {"feature_count": len(records), "finding_count": len(filtered), "severity_counts": dict(sorted(counts.items())), "error_count": counts.get("ERROR", 0), "warning_count": counts.get("WARNING", 0), "info_count": counts.get("INFO", 0)}
    return result


def candidate_source_status(inventory: dict[str, Any], root: Path | str | None = None, legacy: Any | None = None) -> dict[str, Any]:
    sources: set[str] = set()
    if root is None or legacy is None:
        sources = {str(record["path"]) for record in inventory.get("files", []) if record.get("category") in {"raster", "vector"} and not str(record.get("path", "")).lower().startswith("assets/historical_flags/") and record.get("coordinate_convention") not in (None, "not_declared") and isinstance(record.get("source_provenance"), dict) and record["source_provenance"].get("license")}
    if root is not None and legacy is not None:
        root_path = Path(root).resolve()
        try:
            _, records = _load_provenance_records(legacy, root_path)
        except ValueError:
            records = []
        for record in records:
            path = record.get("path")
            if not isinstance(path, str) or path.lower().startswith("assets/historical_flags/"):
                continue
            try:
                candidate = resolve_input_path(root_path, path, "provenance source")
            except ValueError:
                continue
            if _relative_source_key(root_path, candidate) == path and _record_is_approved_visual_source(record, candidate) and legacy._file_hash(candidate) == record.get("sha256"):
                sources.add(path)
    ordered = sorted(sources)
    return {"status": "available", "reason": "Approved source is inventoried with provenance, license, and coordinate convention.", "sources": ordered} if ordered else {"status": "blocked", "reason": "BLOCKED_NO_SOURCE_MAP_ASSET", "sources": []}


def resolve_unique_provider(matches: Sequence[dict[str, Any]]) -> tuple[dict[str, Any] | None, str]:
    return (matches[0], "RESOLVED") if len(matches) == 1 else (None, "AMBIGUOUS" if len(matches) > 1 else "MISSING")


def build_crosswalk(legacy: Any, root: Path | str, inventory: dict[str, Any] | None = None) -> dict[str, Any]:
    root_path = Path(root).resolve()
    status = candidate_source_status(inventory if inventory is not None else build_inventory(legacy, root_path), root_path, legacy)
    original_point, original_candidate = legacy._point, legacy._no_map_mask_candidate
    legacy._point = lambda value: _point(legacy, value)
    legacy._no_map_mask_candidate = lambda: {"status": "not_generated", "reason": status["reason"], "source_raster_candidates": status["sources"]}
    try:
        original_crosswalk = getattr(legacy, "_r1_original_build_crosswalk", legacy.build_crosswalk)
        result = original_crosswalk(root_path)
    finally:
        legacy._point, legacy._no_map_mask_candidate = original_point, original_candidate
    admin_rows = legacy._load_json(root_path / "data/world_map/world_admin1.json").get("regions", [])
    by_code: dict[str, list[dict[str, Any]]] = {}
    for row in admin_rows:
        if row.get("code"):
            by_code.setdefault(str(row["code"]), []).append(row)
    regions = legacy._load_json(root_path / "data/world_map/regions.json")
    records = {item["entity_id"]: item for item in result["records"]}
    for row in regions.get("administrative_units", []):
        code = str(row.get("source_code", ""))
        matches = by_code.get(code, [])
        if code and len(matches) > 1:
            entity_id = str(row.get("id"))
            record = records.get(entity_id)
            if record:
                record["geometry_status"] = "ambiguous"
                record["geometry_refs"] = [ref for ref in record.get("geometry_refs", []) if ref.get("method") != "source_code"]
            result["findings"].append(legacy._finding("ERROR", "ambiguous_provider_id", "Provider code resolves to multiple source features; no automatic binding was made.", "data/world_map/world_admin1.json", entity_id, related_ids=[str(item.get("id")) for item in matches]))
    for record in result["records"]:
        if record.get("candidate_mask", {}).get("status") != "not_applicable":
            record["candidate_mask"] = {"status": "not_generated", "reason": status["reason"], "source_raster_candidates": status["sources"]}
    result["findings"].sort(key=lambda item: (item["severity"], item["code"], item["source"], item["feature_id"], item["finding_id"]))
    result["summary"]["candidate_source_status"] = status
    result["summary"]["candidate_mask_block_reason"] = status["reason"]
    result["summary"]["geometry_status_counts"] = dict(sorted(Counter(item["geometry_status"] for item in result["records"]).items()))
    result["tool_version"] = TOOL_VERSION
    return result
