#!/usr/bin/env python3
"""Build loader/data contracts, explicit flag coverage, and record signatures.

All relationships in this tool come from literal loader paths or existing
source fields. It does not infer historical identities and never edits source.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter
from pathlib import Path
from typing import Any, Iterator, Mapping


SCHEMA_VERSION = "wwo_world_data_batch3_contracts_v1"
RESOURCE_FILE_RE = re.compile(r"res://data/world_map/[A-Za-z0-9_./-]+\.json")
RESOURCE_DIR_RE = re.compile(r"res://data/world_map/[A-Za-z0-9_./-]+/")
DATA_MAP_ENTRY_RE = re.compile(r'"(?P<key>[^"]+)"\s*:\s*"(?P<resource>res://data/world_map/[^\"]+\.json)"')


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def canonical_file_bytes(path: Path) -> bytes:
    if path.suffix.lower() in {".json", ".md", ".py", ".gd", ".ps1"}:
        text = path.read_text(encoding="utf-8")
        return text.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")
    return path.read_bytes()


def sha256_file(path: Path) -> str:
    return hashlib.sha256(canonical_file_bytes(path)).hexdigest()


def sha256_lines(lines: list[str]) -> str:
    return hashlib.sha256("".join(f"{line}\n" for line in lines).encode("utf-8")).hexdigest()


def resource_to_local_path(repository_root: Path, resource: str) -> Path:
    return repository_root / resource[6:]


def build_loader_contract(repository_root: Path) -> dict[str, Any]:
    script_roots = [repository_root / "scripts" / "world_map", repository_root / "scripts" / "formal"]
    scripts = sorted(path for root in script_roots for path in root.rglob("*.gd"))
    data_files = sorted(repository_root.joinpath("data", "world_map").rglob("*.json"))
    data_file_resources = {"res://" + path.relative_to(repository_root).as_posix() for path in data_files}
    file_references: list[dict[str, Any]] = []
    directory_references: list[dict[str, Any]] = []
    map_entries: list[dict[str, Any]] = []
    script_hashes: list[str] = []

    for script in scripts:
        text = script.read_text(encoding="utf-8")
        script_rel = script.relative_to(repository_root).as_posix()
        script_hashes.append(f"{script_rel}\t{sha256_file(script)}")
        file_resources = sorted(set(RESOURCE_FILE_RE.findall(text)))
        directory_resources = sorted(set(RESOURCE_DIR_RE.findall(text)))
        for resource in file_resources:
            local = resource_to_local_path(repository_root, resource)
            file_references.append(
                {
                    "script": script_rel,
                    "resource": resource,
                    "exists": local.is_file(),
                }
            )
        for resource in directory_resources:
            local = resource_to_local_path(repository_root, resource)
            matches = sorted(path for path in local.rglob("*.json")) if local.is_dir() else []
            directory_references.append(
                {
                    "script": script_rel,
                    "resource": resource,
                    "exists": local.is_dir(),
                    "json_file_count": len(matches),
                }
            )
        if script.name == "world_map_data_impl.gd":
            for match in DATA_MAP_ENTRY_RE.finditer(text):
                resource = match.group("resource")
                local = resource_to_local_path(repository_root, resource)
                map_entries.append(
                    {
                        "key": match.group("key"),
                        "resource": resource,
                        "exists": local.is_file(),
                    }
                )

    direct_paths = sorted({reference["resource"] for reference in file_references})
    missing_direct = sorted(resource for resource in direct_paths if resource not in data_file_resources)
    missing_direct_records = sorted(
        (reference["script"], reference["resource"])
        for reference in file_references
        if not reference["exists"]
    )
    missing_directories = sorted(
        (reference["script"], reference["resource"])
        for reference in directory_references
        if not reference["exists"]
    )
    unused_direct_json = sorted(data_file_resources - set(direct_paths))
    return {
        "schema_version": SCHEMA_VERSION,
        "production_script_roots": ["scripts/world_map", "scripts/formal"],
        "production_script_count": len(scripts),
        "script_digest": sha256_lines(sorted(script_hashes)),
        "data_json_count": len(data_files),
        "literal_file_reference_count": len(file_references),
        "literal_directory_reference_count": len(directory_references),
        "literal_file_references": file_references,
        "literal_directory_references": directory_references,
        "world_map_data_loader_entries": map_entries,
        "missing_direct_json_paths": missing_direct,
        "missing_direct_references": missing_direct_records,
        "missing_directory_references": missing_directories,
        "not_directly_literal_referenced_json": unused_direct_json,
        "contract_gate": "PASS" if not missing_direct_records and not missing_directories else "REVIEW_REQUIRED",
    }


def build_flag_coverage(repository_root: Path) -> dict[str, Any]:
    units_document = read_json(repository_root / "data" / "world_map" / "historical" / "political_units_1900.json")
    flags_document = read_json(repository_root / "data" / "world_map" / "historical" / "flags_1900.json")
    units = units_document.get("units", [])
    flags = flags_document.get("records", {})
    rows: list[dict[str, Any]] = []
    status_counts: dict[str, int] = {}
    for unit in units:
        flag_id = unit.get("flag_id")
        flag_record = flags.get(flag_id) if isinstance(flag_id, str) else None
        if not isinstance(flag_record, Mapping):
            status = "MISSING_FLAG_RECORD"
            asset_path = None
        elif flag_id == "no_single_standard_flag" or flag_record.get("flag_type") == "documented_absence":
            status = "DOCUMENTED_ABSENCE"
            asset_path = flag_record.get("asset_path")
        else:
            asset_path_value = flag_record.get("asset_path")
            if not isinstance(asset_path_value, str) or not asset_path_value:
                status = "MISSING_ASSET"
            elif not resource_to_local_path(repository_root, asset_path_value).is_file():
                status = "MISSING_ASSET"
            elif not isinstance(flag_record.get("asset_sha256"), str) or sha256_file(resource_to_local_path(repository_root, asset_path_value)) != flag_record["asset_sha256"]:
                status = "HASH_MISMATCH"
            else:
                status = "VERIFIED_ASSET"
            asset_path = asset_path_value
        status_counts[status] = status_counts.get(status, 0) + 1
        rows.append(
            {
                "unit_id": unit.get("id"),
                "source_name": unit.get("source_name"),
                "status": unit.get("status"),
                "flag_id": flag_id,
                "flag_mode": unit.get("flag_mode"),
                "asset_path": asset_path,
                "coverage_status": status,
            }
        )
    return {
        "schema_version": SCHEMA_VERSION,
        "source": "data/world_map/historical/political_units_1900.json",
        "flag_source": "data/world_map/historical/flags_1900.json",
        "unit_count": len(units),
        "flag_record_count": len(flags),
        "status_counts": dict(sorted(status_counts.items())),
        "missing_flag_record_count": status_counts.get("MISSING_FLAG_RECORD", 0),
        "missing_asset_count": status_counts.get("MISSING_ASSET", 0),
        "hash_mismatch_count": status_counts.get("HASH_MISMATCH", 0),
        "units": rows,
    }


def iter_objects(value: Any) -> Iterator[Mapping[str, Any]]:
    if isinstance(value, Mapping):
        yield value
        for child in value.values():
            yield from iter_objects(child)
    elif isinstance(value, list):
        for child in value:
            yield from iter_objects(child)


def build_record_signatures(repository_root: Path) -> dict[str, Any]:
    rows: list[dict[str, Any]] = []
    for path in sorted(repository_root.joinpath("data", "world_map").rglob("*.json")):
        document = read_json(path)
        ids: list[str] = []
        id_field_counts: dict[str, int] = {}
        for obj in iter_objects(document):
            if isinstance(obj.get("id"), str):
                ids.append(obj["id"])
                id_field_counts["id"] = id_field_counts.get("id", 0) + 1
            elif isinstance(obj.get("stable_id"), str):
                ids.append(obj["stable_id"])
                id_field_counts["stable_id"] = id_field_counts.get("stable_id", 0) + 1
        sorted_ids = sorted(ids)
        id_counts = Counter(ids)
        rows.append(
            {
                "path": path.relative_to(repository_root).as_posix(),
                "id_record_count": len(ids),
                "id_field_counts": dict(sorted(id_field_counts.items())),
                "duplicate_ids": sorted(item for item, count in id_counts.items() if count > 1),
                "id_digest": sha256_lines(sorted_ids),
            }
        )
    row_digest = sha256_lines([f"{row['path']}\t{row['id_digest']}\t{row['id_record_count']}" for row in rows])
    return {
        "schema_version": SCHEMA_VERSION,
        "data_json_count": len(rows),
        "files_with_id_records": sum(1 for row in rows if row["id_record_count"]),
        "duplicate_id_file_count": sum(1 for row in rows if row["duplicate_ids"]),
        "record_signature_digest": row_digest,
        "files": rows,
    }


def build_gap_report(loader: Mapping[str, Any], flags: Mapping[str, Any], signatures: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "loader_contract_gaps": {
            "missing_direct_references": loader.get("missing_direct_references", []),
            "missing_directory_references": loader.get("missing_directory_references", []),
        },
        "flag_coverage_gaps": {
            "missing_flag_records": flags.get("missing_flag_record_count", 0),
            "missing_assets": flags.get("missing_asset_count", 0),
            "hash_mismatches": flags.get("hash_mismatch_count", 0),
        },
        "record_signature_duplicate_file_count": signatures.get("duplicate_id_file_count", 0),
        "manual_or_historical_review_remains": True,
        "notes": [
            "Not-directly-literal-referenced JSON includes dynamically loaded shards and historical catalogs; it is not itself an error.",
            "Flag coverage uses only political_units_1900.flag_id and flags_1900.records references.",
            "No historical identity was inferred from names or aliases.",
        ],
    }


def build_staging(flags: Mapping[str, Any]) -> dict[str, Any]:
    entries = [
        {
            "unit_id": row.get("unit_id"),
            "flag_id": row.get("flag_id"),
            "asset_path": row.get("asset_path"),
            "coverage_status": row.get("coverage_status"),
        }
        for row in flags.get("units", [])
        if row.get("coverage_status") in ("VERIFIED_ASSET", "DOCUMENTED_ABSENCE")
    ]
    return {
        "schema_version": SCHEMA_VERSION,
        "authoritative_source_modified": False,
        "candidate_type": "explicit_historical_unit_flag_index",
        "entries": entries,
    }


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--output-dir", type=Path, default=Path("local-artifacts/world-data-audit"))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    output_dir = args.output_dir if args.output_dir.is_absolute() else root / args.output_dir
    loader = build_loader_contract(root)
    flags = build_flag_coverage(root)
    signatures = build_record_signatures(root)
    gap_report = build_gap_report(loader, flags, signatures)
    staging = build_staging(flags)
    write_json(output_dir / "batch3_loader_contract.json", loader)
    write_json(output_dir / "batch3_historical_flag_coverage.json", flags)
    write_json(output_dir / "batch3_record_signature_manifest.json", signatures)
    write_json(output_dir / "batch3_gap_report.json", gap_report)
    write_json(output_dir / "batch3_staging_candidates.json", staging)
    gate_passed = (
        loader["contract_gate"] == "PASS"
        and flags["missing_flag_record_count"] == 0
        and flags["missing_asset_count"] == 0
        and flags["hash_mismatch_count"] == 0
    )
    print(
        json.dumps(
            {
                "loader_entries": len(loader["world_map_data_loader_entries"]),
                "loader_missing_direct": len(loader["missing_direct_references"]),
                "loader_missing_directories": len(loader["missing_directory_references"]),
                "historical_units": flags["unit_count"],
                "verified_or_documented_flag_units": flags["status_counts"].get("VERIFIED_ASSET", 0) + flags["status_counts"].get("DOCUMENTED_ABSENCE", 0),
                "record_signature_files": signatures["data_json_count"],
                "duplicate_id_files": signatures["duplicate_id_file_count"],
                "mechanical_gate": "PASS" if gate_passed else "REVIEW_REQUIRED",
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )
    return 0 if gate_passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
