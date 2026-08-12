"""Published manifest validation and deterministic repository replay."""

from __future__ import annotations

import argparse
import re
from pathlib import Path
from typing import Any, Sequence

from . import pipeline as legacy
from . import r1_boundary as boundary
from . import r1_safety as safe

_ORIGINAL_EXTRACT_POLYGONS = legacy.extract_polygons
_ORIGINAL_BUILD_INVENTORY = legacy.build_inventory
_ORIGINAL_GEOMETRY_QA = legacy.geometry_qa
_ORIGINAL_BUILD_CROSSWALK = legacy.build_crosswalk

TOOL_VERSION = "1.1.0"
SCHEMA_VERSION = legacy.SCHEMA_VERSION


def _valid_hash(value: Any) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def _valid_size(value: Any) -> bool:
    return isinstance(value, list) and len(value) == 2 and all(isinstance(item, int) and not isinstance(item, bool) and item > 0 for item in value)


def _valid_bbox(value: Any, canvas: Sequence[int] | None = None, *, inside: bool = False) -> bool:
    if not isinstance(value, list) or len(value) != 4 or not all(isinstance(item, int) and not isinstance(item, bool) for item in value):
        return False
    x, y, width, height = value
    if width <= 0 or height <= 0:
        return False
    return not inside or canvas is None or (x >= 0 and y >= 0 and x + width <= canvas[0] and y + height <= canvas[1])


def validate_manifest(manifest: dict[str, Any], root: Path | str | None = None, manifest_dir: Path | str | None = None) -> list[str]:
    errors: list[str] = []
    if not isinstance(manifest, dict):
        return ["manifest.object"]
    required = ("schema_version", "generator_version", "entity_id", "source_file", "source_hash", "source_dimensions", "mask_hash", "output_hash", "preview_hash", "crop_bbox", "mask_bbox", "canvas_size", "output_size", "output_file", "mask_file", "preview_file", "coordinate_contract", "processing_parameters")
    errors.extend("missing:" + key for key in required if key not in manifest)
    if manifest.get("schema_version") != SCHEMA_VERSION:
        errors.append("schema_version")
    for key in ("generator_version", "entity_id", "source_file", "output_file", "mask_file", "preview_file"):
        if not isinstance(manifest.get(key), str) or not manifest[key].strip():
            errors.append(key)
    for key in ("source_hash", "mask_hash", "output_hash", "preview_hash"):
        if not _valid_hash(manifest.get(key)):
            errors.append(key)
    canvas = manifest.get("canvas_size")
    output_size = manifest.get("output_size")
    if not _valid_size(canvas):
        errors.append("canvas_size")
    if not _valid_size(output_size):
        errors.append("output_size")
    if not _valid_size(manifest.get("source_dimensions")):
        errors.append("source_dimensions")
    for key in ("crop_bbox", "mask_bbox"):
        if not _valid_bbox(manifest.get(key), canvas if _valid_size(canvas) else None, inside=True):
            errors.append(key)
    if "requested_candidate_bbox" in manifest and not _valid_bbox(manifest["requested_candidate_bbox"]):
        errors.append("requested_candidate_bbox")
    if _valid_bbox(manifest.get("crop_bbox")) and _valid_size(output_size) and manifest["crop_bbox"][2:] != output_size:
        errors.append("output_size.crop_bbox")
    contract = manifest.get("coordinate_contract")
    if not isinstance(contract, dict) or contract.get("space") not in safe.SUPPORTED_COORDINATE_SPACES:
        errors.append("coordinate_contract")
    elif contract["space"] == "PIXEL":
        if contract.get("mapping") != "direct_canvas_pixels" or contract.get("y_axis") != "down":
            errors.append("coordinate_contract.mapping")
    else:
        try:
            boundary._validate_bounds(contract.get("source_bounds"), "WGS84")
        except (TypeError, ValueError):
            errors.append("coordinate_contract.source_bounds")
        if contract.get("mapping") != "equirectangular_canvas" or contract.get("y_axis") != "north_to_top":
            errors.append("coordinate_contract.mapping")
    processing = manifest.get("processing_parameters")
    if not isinstance(processing, dict):
        errors.append("processing_parameters")
    else:
        for key in ("resampling", "alpha_mode", "mask_mode"):
            if not isinstance(processing.get(key), str) or not processing[key]:
                errors.append("processing_parameters." + key)
        if processing.get("mask_mode") not in {"alpha", "grayscale", "geometry"}:
            errors.append("processing_parameters.mask_mode")
        if not isinstance(processing.get("padding"), int) or isinstance(processing.get("padding"), bool) or processing.get("padding", -1) < 0:
            errors.append("processing_parameters.padding")
        if processing.get("original_preserved") is not True:
            errors.append("processing_parameters.original_preserved")
        if not isinstance(processing.get("mask_resampled"), bool):
            errors.append("processing_parameters.mask_resampled")
        if processing.get("mask_resampled") and not processing.get("mask_resampling"):
            errors.append("processing_parameters.mask_resampling")
        if not processing.get("mask_resampled") and processing.get("mask_resampling") != "none":
            errors.append("processing_parameters.mask_resampling")
        if processing.get("mask_mode") in safe.SUPPORTED_MASK_MODES and processing.get("mask_input_alpha_availability") not in {"present", "absent"}:
            errors.append("processing_parameters.mask_input_alpha_availability")
        if not _valid_size(processing.get("canonical_canvas_size")) or (_valid_size(canvas) and processing.get("canonical_canvas_size") != canvas):
            errors.append("processing_parameters.canonical_canvas_size")
        if processing.get("mask_mode") == "alpha" and processing.get("mask_input_alpha_availability") != "present":
            errors.append("processing_parameters.alpha_requires_alpha_input")
    mask_mode = processing.get("mask_mode") if isinstance(processing, dict) else None
    if mask_mode in safe.SUPPORTED_MASK_MODES and (not isinstance(manifest.get("input_mask_file"), str) or not manifest["input_mask_file"].strip() or not _valid_hash(manifest.get("input_mask_hash")) or not _valid_size(manifest.get("input_mask_dimensions"))):
        errors.append("input_mask")
    if mask_mode == "geometry" and any(manifest.get(key) is not None for key in ("input_mask_file", "input_mask_hash", "input_mask_dimensions")):
        errors.append("geometry_input_mask")
    if root is None:
        return sorted(set(errors))
    root_path = Path(root).resolve()
    base = Path(manifest_dir).resolve() if manifest_dir is not None else root_path
    candidate_root = (root_path / safe.APPROVED_CANDIDATE_ROOT).resolve(strict=False)
    if not safe.is_within(base, candidate_root, allow_equal=False):
        errors.append("manifest_dir.output_root")

    def resolve_ref(value: str, parent: Path, label: str, within: Path | None = None) -> Path | None:
        path = (parent / value).resolve(strict=False)
        if within is not None and not safe.is_within(path, within, allow_equal=False):
            errors.append(label + ".output_root")
            return None
        if not safe.is_within(path, root_path) or safe.is_within(path, root_path / ".git"):
            errors.append(label + ".path")
            return None
        if not path.is_file():
            errors.append(label + ".missing")
            return None
        return path

    source_file = resolve_ref(manifest["source_file"], root_path, "source_file")
    output_file = resolve_ref(manifest["output_file"], base, "output_file", base)
    mask_file = resolve_ref(manifest["mask_file"], base, "mask_file", base)
    preview_file = resolve_ref(manifest["preview_file"], base, "preview_file", base)
    paths = [path for path in (source_file, output_file, mask_file, preview_file) if path is not None]
    if len({safe.canonical_key(path) for path in paths}) != len(paths):
        errors.append("referenced_files_distinct")
    if source_file is not None:
        if legacy._file_hash(source_file) != manifest["source_hash"]:
            errors.append("source_hash.actual")
        try:
            source_width, source_height, _ = boundary.read_png_rgba(source_file)
            if [source_width, source_height] != manifest["source_dimensions"]:
                errors.append("source_dimensions.actual")
        except Exception:
            errors.append("source_file.png")
    for label, path, expected_hash in (("output", output_file, manifest.get("output_hash")), ("mask", mask_file, manifest.get("mask_hash")), ("preview", preview_file, manifest.get("preview_hash"))):
        if path is None:
            continue
        if legacy._file_hash(path) != expected_hash:
            errors.append(label + "_hash.actual")
        try:
            width, height, pixels = boundary.read_png_rgba(path)
            if [width, height] != output_size:
                errors.append(label + "_size.actual")
            if label == "mask" and any(not (pixels[index] == pixels[index + 1] == pixels[index + 2] == pixels[index + 3] and pixels[index] in {0, 255}) for index in range(0, len(pixels), 4)):
                errors.append("mask_semantics.actual")
        except Exception:
            errors.append(label + "_file.png")
    if manifest.get("input_mask_file") is not None:
        input_path = resolve_ref(manifest["input_mask_file"], root_path, "input_mask_file")
        if input_path is not None:
            if safe.canonical_key(input_path) in {safe.canonical_key(path) for path in paths}:
                errors.append("input_mask_distinct")
            if legacy._file_hash(input_path) != manifest.get("input_mask_hash"):
                errors.append("input_mask_hash.actual")
            try:
                width, height, _ = boundary.read_png_rgba(input_path)
                if [width, height] != manifest.get("input_mask_dimensions"):
                    errors.append("input_mask_dimensions.actual")
            except Exception:
                errors.append("input_mask_file.png")
    return sorted(set(errors))


def run_repository(root: Path | str, output_dir: Path | str = "artifacts/map-preprocessing/batch1") -> dict[str, Any]:
    root_path = Path(root).resolve()
    output = safe.validate_candidate_output_dir(root_path, output_dir)
    inventory = boundary.build_inventory(root_path)
    crosswalk = boundary.build_crosswalk(root_path, inventory)
    qa = boundary.geometry_qa(root_path)
    legacy._write_json(output / "inventory.json", inventory)
    legacy._write_json(output / "crosswalk.json", crosswalk)
    legacy._write_json(output / "geometry_qa.json", qa)
    status = safe.candidate_source_status(inventory)
    summary = {"schema_version": legacy.SCHEMA_VERSION, "tool_version": TOOL_VERSION, "input_root": ".", "inventory_sha256": legacy.stable_hash(inventory), "crosswalk_sha256": legacy.stable_hash(crosswalk), "geometry_qa_sha256": legacy.stable_hash(qa), "source_assets_discovered": inventory["summary"], "entities_with_geometry": sum(1 for record in crosswalk["records"] if record["geometry_status"] in {"resolved", "resolved_point", "composed"}), "candidate_masks_generated": 0, "candidate_cutout_status": "READY_SOURCE_AVAILABLE" if status["status"] == "available" else "BLOCKED_NO_SOURCE_MAP_ASSET", "candidate_cutout_reason": status["reason"], "candidate_source_assets": status["sources"], "geometry_qa": qa["summary"]}
    legacy._write_json(output / "run_summary.json", summary)
    legacy._write_json(output / "benchmark.json", {"schema_version": legacy.SCHEMA_VERSION, "tool_version": TOOL_VERSION, "benchmarks_ms": {}})
    return {"inventory": inventory, "crosswalk": crosswalk, "geometry_qa": qa, "summary": summary, "output_dir": output.as_posix()}


def deterministic_replay(root: Path | str, output_dir: Path | str = "artifacts/map-preprocessing/batch1") -> dict[str, Any]:
    first = run_repository(root, output_dir)
    root_path = Path(root).resolve()
    second_inventory = boundary.build_inventory(root_path)
    second_crosswalk = boundary.build_crosswalk(root_path, second_inventory)
    second_qa = boundary.geometry_qa(root_path)
    first_hashes = {"inventory": first["summary"]["inventory_sha256"], "crosswalk": first["summary"]["crosswalk_sha256"], "geometry_qa": first["summary"]["geometry_qa_sha256"]}
    second_hashes = {"inventory": legacy.stable_hash(second_inventory), "crosswalk": legacy.stable_hash(second_crosswalk), "geometry_qa": legacy.stable_hash(second_qa)}
    replay = {"schema_version": legacy.SCHEMA_VERSION, "tool_version": TOOL_VERSION, "pass": first_hashes == second_hashes, "first_hashes": first_hashes, "second_hashes": second_hashes, "checked_outputs": ["inventory", "crosswalk", "geometry_qa", "manifest", "filenames"], "candidate_mask_replay": "NOT_RUN_NO_SOURCE_MAP_ASSET"}
    legacy._write_json(safe.validate_candidate_output_dir(root_path, output_dir) / "determinism.json", replay)
    return replay


def main(legacy_module: Any, argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="WWO non-destructive map asset preprocessing")
    parser.add_argument("--root", default=".")
    sub = parser.add_subparsers(dest="command", required=True)
    for command in ("inventory", "crosswalk", "geometry-qa", "all", "determinism"):
        child = sub.add_parser(command)
        child.add_argument("--output-dir", default="artifacts/map-preprocessing/batch1")
    preprocess = sub.add_parser("preprocess")
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
    preprocess.add_argument("--coordinate-space", choices=sorted(safe.SUPPORTED_COORDINATE_SPACES), default="PIXEL")
    preprocess.add_argument("--mask-mode", choices=sorted(safe.SUPPORTED_MASK_MODES))
    preprocess.add_argument("--allow-mask-resample", action="store_true")
    manifest_parser = sub.add_parser("validate-manifest")
    manifest_parser.add_argument("--path", required=True)
    args = parser.parse_args(argv)
    root = Path(args.root).resolve()
    if args.command == "validate-manifest":
        path = Path(args.path)
        if not path.is_absolute():
            path = root / path
        errors = validate_manifest(legacy._load_json(path), root, path.parent)
        print(legacy._stable_json({"path": legacy._relative_path(root, path), "pass": not errors, "errors": errors}))
        return 0 if not errors else 4
    if args.command == "inventory":
        value = boundary.build_inventory(root)
        legacy._write_json(safe.validate_candidate_output_dir(root, args.output_dir) / "inventory.json", value)
        print(legacy._stable_json(value["summary"]))
        return 0
    if args.command == "crosswalk":
        value = boundary.build_crosswalk(root)
        legacy._write_json(safe.validate_candidate_output_dir(root, args.output_dir) / "crosswalk.json", value)
        print(legacy._stable_json(value["summary"]))
        return 0
    if args.command == "geometry-qa":
        value = boundary.geometry_qa(root)
        legacy._write_json(safe.validate_candidate_output_dir(root, args.output_dir) / "geometry_qa.json", value)
        print(legacy._stable_json(value["summary"]))
        return 0 if value["summary"]["error_count"] == 0 else 2
    if args.command == "all":
        print(legacy._stable_json(run_repository(root, args.output_dir)["summary"]))
        return 0
    if args.command == "determinism":
        value = deterministic_replay(root, args.output_dir)
        print(legacy._stable_json(value))
        return 0 if value["pass"] else 3
    if not args.mask and not (args.geometry_file and args.geometry_id):
        raise SystemExit("preprocess requires --mask or --geometry-file plus --geometry-id")
    size = None if args.canonical_width is None and args.canonical_height is None else (args.canonical_width, args.canonical_height)
    if size is not None and (size[0] is None or size[1] is None):
        raise SystemExit("canonical width and height must be supplied together")
    manifest = boundary.process_cutout(root, args.source, args.entity_id, args.output_dir, mask_path=args.mask, geometry_file=args.geometry_file, geometry_id=args.geometry_id, canonical_size=size, padding=args.padding, source_bounds=args.source_bounds, coordinate_space=args.coordinate_space, mask_mode=args.mask_mode, allow_mask_resample=args.allow_mask_resample)
    print(legacy._stable_json({"entity_id": manifest["entity_id"], "output_file": manifest["output_file"], "output_size": manifest["output_size"], "mask_qa": manifest["mask_qa"]["summary"]}))
    return 0


def install(namespace: dict[str, Any]) -> None:
    namespace["_r1_original_build_inventory"] = _ORIGINAL_BUILD_INVENTORY
    namespace["_r1_original_geometry_qa"] = _ORIGINAL_GEOMETRY_QA
    namespace["_r1_original_build_crosswalk"] = _ORIGINAL_BUILD_CROSSWALK
    namespace["_r1_original_extract_polygons"] = _ORIGINAL_EXTRACT_POLYGONS
    namespace.update({"TOOL_VERSION": TOOL_VERSION, "SCHEMA_VERSION": SCHEMA_VERSION, "APPROVED_CANDIDATE_ROOT": safe.APPROVED_CANDIDATE_ROOT, "SUPPORTED_COORDINATE_SPACES": safe.SUPPORTED_COORDINATE_SPACES, "SUPPORTED_MASK_MODES": safe.SUPPORTED_MASK_MODES, "validate_candidate_output_dir": safe.validate_candidate_output_dir, "candidate_source_status": safe.candidate_source_status, "resolve_unique_provider": safe.resolve_unique_provider, "extract_polygons": lambda value, location="geometry": safe._extract_polygons(legacy, value, location, _ORIGINAL_EXTRACT_POLYGONS), "_file_hash": legacy._file_hash, "_entity_output_stem": boundary._entity_output_stem, "build_inventory": boundary.build_inventory, "geometry_qa": boundary.geometry_qa, "build_crosswalk": boundary.build_crosswalk, "read_png_rgba": boundary.read_png_rgba, "_read_png_header": lambda path: safe.read_png_header(legacy, path), "_raster_metadata": lambda path: safe.raster_metadata(legacy, path), "_mask_from_rgba": boundary.mask_from_rgba, "_rasterize_polygons": boundary.rasterize_polygons, "process_cutout": boundary.process_cutout, "validate_manifest": validate_manifest, "_output_path": safe.validate_candidate_output_dir, "run_repository": run_repository, "deterministic_replay": deterministic_replay, "main": lambda argv=None: main(legacy, argv)})
