#!/usr/bin/env python3
"""Build deterministic Batch 2 staging records from the existing 1900 unit snapshot."""

from __future__ import annotations

import argparse
import hashlib
import json
import unicodedata
from collections import Counter
from datetime import date
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT_DIR = REPO_ROOT / "data" / "staging" / "1900"
INPUT_PATH = REPO_ROOT / "data" / "world_map" / "historical" / "political_units_1900.json"
COUNTRIES_PATH = REPO_ROOT / "data" / "world_map" / "countries.json"
SCHEMA_PATH = REPO_ROOT / "data" / "staging" / "1900" / "batch2_political_unit_records.schema.json"
RECORDS_NAME = "political_unit_records_1900.json"
MANIFEST_NAME = "batch2_manifest.json"
CORPUS_NAME = "batch2_deterministic_corpus.json"
SNAPSHOT_DATE = "1900-03-12"
SOURCE_ID = "src-cshapes-2.0"
SOURCE_TITLE = "CShapes 2.0 1900-03-12 repository snapshot"
SOURCE_AUTHOR = "ETH Zurich International Conflict Research; Schvitz et al."
SOURCE_LOCATOR = "https://beta.icr.ethz.ch/data/cshapes/"
SOURCE_DATE = "2022"
GENERATOR_VERSION = "batch2_20260812_v1"


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def canonical_name(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value).casefold()
    return " ".join(normalized.split())


def write_json(path: Path, value: Any) -> str:
    encoded = (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")
    path.write_bytes(encoded)
    return sha256_bytes(encoded)


def build_records(units: list[dict[str, Any]], country_ids: set[str]) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[str, Any]]:
    snapshot = date.fromisoformat(SNAPSHOT_DATE)
    unit_ids = {unit["id"] for unit in units}
    records: list[dict[str, Any]] = []
    relationships: list[dict[str, Any]] = []

    for unit in sorted(units, key=lambda item: (item["gwcode"], item["id"])):
        unit_id = unit["id"]
        date_from = unit["valid_from"]
        date_to = unit["valid_to"]
        snapshot_active = date.fromisoformat(date_from) <= snapshot <= date.fromisoformat(date_to)
        exact_id = unit_id if unit_id in country_ids else None
        controller_id = unit.get("controller_id") or None
        record = {
            "record_id": f"1900-unit-{unit_id}",
            "entity_type": "historical_political_unit",
            "historical_unit_id": unit_id,
            "canonical_entity_id": exact_id,
            "canonical_match": "EXACT_ID" if exact_id is not None else "NO_MATCH",
            "gwcode": unit["gwcode"],
            "historical_name": unit["source_name"],
            "normalized_name": canonical_name(unit["source_name"]),
            "date_from": date_from,
            "date_to": date_to,
            "snapshot_active": snapshot_active,
            "status": unit["status"],
            "relationship": unit["relationship"],
            "controller_id": controller_id,
            "capital": unit["capital"],
            "area_km2": unit["area_km2"],
            "geometry_feature_id": unit["geometry_feature_id"],
            "geometry_provider": unit["geometry_provider"],
            "data_quality": unit["data_quality"],
            "flag_id": unit["flag_id"],
            "flag_mode": unit["flag_mode"],
            "flag_absence_reason": unit.get("flag_absence_reason", ""),
            "source_id": SOURCE_ID,
            "source_title": SOURCE_TITLE,
            "source_author_or_institution": SOURCE_AUTHOR,
            "source_locator": SOURCE_LOCATOR,
            "source_reference": f"{INPUT_PATH.relative_to(REPO_ROOT).as_posix()}#units.{unit_id}",
            "source_date": SOURCE_DATE,
            "source_type": "historical_gis",
            "confidence": "high",
            "ambiguity_notes": "Historical unit values are copied from the dated repository snapshot; canonical resolution uses exact ID equality only and does not infer a modern match.",
            "conflict_group": None,
            "review_status": "STAGED_NOT_RUNTIME",
            "runtime_authority": False,
        }
        if not snapshot_active:
            raise ValueError(f"Unit is not active on snapshot date: {unit_id}")
        records.append(record)

        if controller_id is not None:
            if controller_id not in unit_ids:
                raise ValueError(f"Unresolved controller ID in source snapshot: {unit_id} -> {controller_id}")
            controller_exact_id = controller_id if controller_id in country_ids else None
            relationships.append(
                {
                    "record_id": f"1900-relationship-{unit_id}-{controller_id}",
                    "fact_type": "sovereignty_relationship",
                    "subject_historical_unit_id": unit_id,
                    "controller_historical_unit_id": controller_id,
                    "relationship": unit["relationship"],
                    "status": unit["status"],
                    "date_from": date_from,
                    "date_to": date_to,
                    "snapshot_active": snapshot_active,
                    "canonical_subject_entity_id": exact_id,
                    "canonical_controller_entity_id": controller_exact_id,
                    "source_id": SOURCE_ID,
                    "source_title": SOURCE_TITLE,
                    "source_author_or_institution": SOURCE_AUTHOR,
                    "source_locator": SOURCE_LOCATOR,
                    "source_reference": f"{INPUT_PATH.relative_to(REPO_ROOT).as_posix()}#units.{unit_id}.controller_id",
                    "source_date": SOURCE_DATE,
                    "source_type": "historical_gis",
                    "confidence": "high",
                    "ambiguity_notes": "The relationship and controller are copied from the dated snapshot; legal and effective-control interpretation is not expanded here.",
                    "conflict_group": None,
                    "review_status": "STAGED_NOT_RUNTIME",
                    "runtime_authority": False,
                }
            )

    status_counts = dict(sorted(Counter(record["status"] for record in records).items()))
    relationship_counts = dict(sorted(Counter(record["relationship"] for record in records).items()))
    canonical_match_counts = dict(sorted(Counter(record["canonical_match"] for record in records).items()))
    summary = {
        "unit_count": len(records),
        "snapshot_active_count": sum(record["snapshot_active"] for record in records),
        "controller_link_count": len(relationships),
        "canonical_match_counts": canonical_match_counts,
        "status_counts": status_counts,
        "relationship_counts": relationship_counts,
        "unresolved_controller_ids": [],
    }
    return records, relationships, summary


def build(output_dir: Path) -> dict[str, Any]:
    source_bytes = INPUT_PATH.read_bytes()
    source = load_json(INPUT_PATH)
    countries = load_json(COUNTRIES_PATH)["countries"]
    units = source["units"]
    country_ids = {country["id"] for country in countries}
    records, relationships, summary = build_records(units, country_ids)

    output_dir.mkdir(parents=True, exist_ok=True)
    records_payload = {
        "schema_id": "wwo_1900_batch2_political_unit_records_v1",
        "batch": 2,
        "snapshot_date": SNAPSHOT_DATE,
        "source_snapshot": {
            "path": INPUT_PATH.relative_to(REPO_ROOT).as_posix(),
            "sha256": sha256_bytes(source_bytes),
            "record_count": len(units),
        },
        "policy": {
            "runtime_authority": False,
            "canonical_resolution": "EXACT_ID_ONLY; all other units remain NO_MATCH",
            "historical_values": "copied from the existing dated repository snapshot without inference",
            "modern_geometry_fallback": False,
        },
        "summary": summary,
        "units": records,
        "relationships": sorted(relationships, key=lambda item: item["record_id"]),
    }
    records_path = output_dir / RECORDS_NAME
    records_sha = write_json(records_path, records_payload)
    schema_sha = sha256_file(SCHEMA_PATH)

    corpus_payload = {
        "schema_id": "wwo_1900_source_pack_batch2_deterministic_corpus_v1",
        "batch": 2,
        "generator_version": GENERATOR_VERSION,
        "snapshot_date": SNAPSHOT_DATE,
        "input_sha256": sha256_bytes(source_bytes),
        "expected_records_sha256": records_sha,
        "expected_schema_sha256": schema_sha,
        "expected_summary": summary,
        "comparison_outputs": [RECORDS_NAME, MANIFEST_NAME, CORPUS_NAME],
        "policy": "Generated bytes must be identical across two clean output directories; no timestamp or absolute path is permitted.",
    }
    corpus_path = output_dir / CORPUS_NAME
    corpus_sha = write_json(corpus_path, corpus_payload)

    manifest_payload = {
        "schema_id": "wwo_1900_source_pack_batch2_manifest_v1",
        "batch": 2,
        "snapshot_date": SNAPSHOT_DATE,
        "generator_version": GENERATOR_VERSION,
        "runtime_authority": False,
        "input": {
            "path": INPUT_PATH.relative_to(REPO_ROOT).as_posix(),
            "sha256": sha256_bytes(source_bytes),
            "unit_count": len(units),
            "canonical_country_count": len(country_ids),
        },
        "outputs": {
            RECORDS_NAME: {"path": f"data/staging/1900/{RECORDS_NAME}", "sha256": records_sha, "units": len(records), "relationships": len(relationships)},
            "batch2_political_unit_records.schema.json": {"path": "data/staging/1900/batch2_political_unit_records.schema.json", "sha256": schema_sha},
            CORPUS_NAME: {"path": f"data/staging/1900/{CORPUS_NAME}", "sha256": corpus_sha},
        },
        "summary": summary,
        "protected_scope": {
            "authoritative_runtime_data_changed": False,
            "vnext_core_changed": False,
            "gameplay_balance_changed": False,
            "modern_geometry_fallback_used": False,
        },
    }
    manifest_path = output_dir / MANIFEST_NAME
    manifest_sha = write_json(manifest_path, manifest_payload)
    return {
        "records_sha256": records_sha,
        "manifest_sha256": manifest_sha,
        "corpus_sha256": corpus_sha,
        "schema_sha256": schema_sha,
        "summary": summary,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    args = parser.parse_args()
    result = build(args.output_dir.resolve())
    print(json.dumps({"ok": True, **result}, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
