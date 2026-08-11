#!/usr/bin/env python3
"""Validate Batch 2 political-unit staging, provenance, and cross-file consistency."""

from __future__ import annotations

import hashlib
import json
from collections import Counter
from datetime import date
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / "data" / "staging" / "1900"
INPUT_PATH = ROOT / "data" / "world_map" / "historical" / "political_units_1900.json"
COUNTRIES_PATH = ROOT / "data" / "world_map" / "countries.json"
SCHEMA_PATH = STAGING / "batch2_political_unit_records.schema.json"
RECORDS_PATH = STAGING / "political_unit_records_1900.json"
MANIFEST_PATH = STAGING / "batch2_manifest.json"
CORPUS_PATH = STAGING / "batch2_deterministic_corpus.json"
SNAPSHOT_DATE = date.fromisoformat("1900-03-12")


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def add_error(errors: list[str], message: str) -> None:
    errors.append(message)


def validate_date_interval(errors: list[str], label: str, date_from: str, date_to: str) -> None:
    try:
        start = date.fromisoformat(date_from)
        end = date.fromisoformat(date_to)
    except ValueError as exc:
        add_error(errors, f"{label}: invalid date interval: {exc}")
        return
    if start > end:
        add_error(errors, f"{label}: date_from is after date_to")
    if not (start <= SNAPSHOT_DATE <= end):
        add_error(errors, f"{label}: interval does not include snapshot date")


def validate() -> tuple[list[str], dict[str, Any]]:
    errors: list[str] = []
    schema = load_json(SCHEMA_PATH)
    source = load_json(INPUT_PATH)
    countries = load_json(COUNTRIES_PATH)["countries"]
    payload = load_json(RECORDS_PATH)
    manifest = load_json(MANIFEST_PATH)
    corpus = load_json(CORPUS_PATH)

    if schema.get("$id") != "wwo_1900_batch2_political_unit_records_v1":
        add_error(errors, "schema $id mismatch")
    if payload.get("schema_id") != "wwo_1900_batch2_political_unit_records_v1":
        add_error(errors, "records schema_id mismatch")
    if payload.get("batch") != 2 or payload.get("snapshot_date") != "1900-03-12":
        add_error(errors, "records batch or snapshot mismatch")
    if payload.get("policy", {}).get("runtime_authority") is not False:
        add_error(errors, "records runtime_authority must be false")
    if payload.get("policy", {}).get("modern_geometry_fallback") is not False:
        add_error(errors, "records modern_geometry_fallback must be false")

    source_units = source.get("units", [])
    units = payload.get("units", [])
    relationships = payload.get("relationships", [])
    source_by_id = {unit.get("id"): unit for unit in source_units}
    country_ids = {country.get("id") for country in countries}
    unit_by_id = {record.get("historical_unit_id"): record for record in units}
    relation_by_id = {record.get("record_id"): record for record in relationships}

    if len(source_by_id) != len(source_units):
        add_error(errors, "source snapshot contains duplicate unit IDs")
    if len(unit_by_id) != len(units):
        add_error(errors, "staging records contain duplicate historical_unit_id values")
    if len(relation_by_id) != len(relationships):
        add_error(errors, "staging relationships contain duplicate record IDs")
    if set(unit_by_id) != set(source_by_id):
        add_error(errors, "staging unit IDs do not exactly cover source snapshot unit IDs")

    expected_controller_links = 0
    expected_status = Counter()
    expected_relationships = Counter()
    expected_matches = Counter()
    for unit_id, source_unit in source_by_id.items():
        record = unit_by_id.get(unit_id)
        if record is None:
            continue
        expected_controller = source_unit.get("controller_id") or None
        expected_exact = unit_id if unit_id in country_ids else None
        expected_status[source_unit["status"]] += 1
        expected_relationships[source_unit["relationship"]] += 1
        expected_matches["EXACT_ID" if expected_exact is not None else "NO_MATCH"] += 1
        if expected_controller is not None:
            expected_controller_links += 1

        for key, expected in {
            "record_id": f"1900-unit-{unit_id}",
            "entity_type": "historical_political_unit",
            "historical_unit_id": unit_id,
            "canonical_entity_id": expected_exact,
            "canonical_match": "EXACT_ID" if expected_exact is not None else "NO_MATCH",
            "gwcode": source_unit["gwcode"],
            "historical_name": source_unit["source_name"],
            "date_from": source_unit["valid_from"],
            "date_to": source_unit["valid_to"],
            "status": source_unit["status"],
            "relationship": source_unit["relationship"],
            "controller_id": expected_controller,
            "capital": source_unit["capital"],
            "area_km2": source_unit["area_km2"],
            "geometry_feature_id": source_unit["geometry_feature_id"],
            "geometry_provider": source_unit["geometry_provider"],
            "data_quality": source_unit["data_quality"],
            "flag_id": source_unit["flag_id"],
            "flag_mode": source_unit["flag_mode"],
            "flag_absence_reason": source_unit.get("flag_absence_reason", ""),
            "source_id": "src-cshapes-2.0",
            "source_type": "historical_gis",
            "confidence": "high",
            "review_status": "STAGED_NOT_RUNTIME",
            "runtime_authority": False,
        }.items():
            if record.get(key) != expected:
                add_error(errors, f"{unit_id}: field {key} differs from source snapshot")
        if not record.get("normalized_name"):
            add_error(errors, f"{unit_id}: normalized_name is empty")
        if record.get("snapshot_active") is not True:
            add_error(errors, f"{unit_id}: snapshot_active is not true")
        validate_date_interval(errors, unit_id, record.get("date_from", ""), record.get("date_to", ""))
        if not record.get("source_reference", "").endswith(f"#units.{unit_id}"):
            add_error(errors, f"{unit_id}: source_reference does not point to source unit")
        if record.get("canonical_match") == "NO_MATCH" and record.get("canonical_entity_id") is not None:
            add_error(errors, f"{unit_id}: NO_MATCH must not carry a canonical entity ID")

    expected_relation_ids = set()
    for unit_id, source_unit in source_by_id.items():
        controller_id = source_unit.get("controller_id") or None
        if controller_id is None:
            continue
        expected_relation_id = f"1900-relationship-{unit_id}-{controller_id}"
        expected_relation_ids.add(expected_relation_id)
        relation = relation_by_id.get(expected_relation_id)
        if relation is None:
            add_error(errors, f"missing relationship record: {expected_relation_id}")
            continue
        if controller_id not in source_by_id:
            add_error(errors, f"unresolved controller in relationship: {expected_relation_id}")
        expected_subject_exact = unit_id if unit_id in country_ids else None
        expected_controller_exact = controller_id if controller_id in country_ids else None
        expected_fields = {
            "fact_type": "sovereignty_relationship",
            "subject_historical_unit_id": unit_id,
            "controller_historical_unit_id": controller_id,
            "relationship": source_unit["relationship"],
            "status": source_unit["status"],
            "date_from": source_unit["valid_from"],
            "date_to": source_unit["valid_to"],
            "snapshot_active": True,
            "canonical_subject_entity_id": expected_subject_exact,
            "canonical_controller_entity_id": expected_controller_exact,
            "source_id": "src-cshapes-2.0",
            "source_type": "historical_gis",
            "confidence": "high",
            "review_status": "STAGED_NOT_RUNTIME",
            "runtime_authority": False,
        }
        for key, expected in expected_fields.items():
            if relation.get(key) != expected:
                add_error(errors, f"{expected_relation_id}: field {key} differs from source snapshot")
        validate_date_interval(errors, expected_relation_id, relation.get("date_from", ""), relation.get("date_to", ""))

    if set(relation_by_id) != expected_relation_ids:
        add_error(errors, "relationship record IDs do not exactly cover source controller links")

    actual_status = Counter(record.get("status") for record in units)
    actual_relationships = Counter(record.get("relationship") for record in units)
    actual_matches = Counter(record.get("canonical_match") for record in units)
    if actual_status != expected_status:
        add_error(errors, "status counts differ from source snapshot")
    if actual_relationships != expected_relationships:
        add_error(errors, "relationship counts differ from source snapshot")
    if actual_matches != expected_matches:
        add_error(errors, "canonical match counts differ from exact-ID calculation")
    if len(relationships) != expected_controller_links:
        add_error(errors, "controller link count differs from source snapshot")

    summary = payload.get("summary", {})
    expected_summary = {
        "unit_count": len(source_units),
        "snapshot_active_count": len(source_units),
        "controller_link_count": expected_controller_links,
        "canonical_match_counts": dict(sorted(expected_matches.items())),
        "status_counts": dict(sorted(expected_status.items())),
        "relationship_counts": dict(sorted(expected_relationships.items())),
        "unresolved_controller_ids": [],
    }
    if summary != expected_summary:
        add_error(errors, "payload summary differs from independently derived source summary")

    source_sha = sha256_file(INPUT_PATH)
    if payload.get("source_snapshot", {}).get("sha256") != source_sha:
        add_error(errors, "source snapshot SHA-256 mismatch")
    if payload.get("source_snapshot", {}).get("record_count") != len(source_units):
        add_error(errors, "source snapshot record count mismatch")
    if manifest.get("input", {}).get("sha256") != source_sha:
        add_error(errors, "manifest input SHA-256 mismatch")
    if corpus.get("input_sha256") != source_sha:
        add_error(errors, "deterministic corpus input SHA-256 mismatch")
    records_sha = sha256_file(RECORDS_PATH)
    corpus_sha = sha256_file(CORPUS_PATH)
    schema_sha = sha256_file(SCHEMA_PATH)
    if corpus.get("expected_records_sha256") != records_sha:
        add_error(errors, "deterministic corpus record SHA-256 mismatch")
    if corpus.get("expected_schema_sha256") != schema_sha:
        add_error(errors, "deterministic corpus schema SHA-256 mismatch")
    manifest_records = manifest.get("outputs", {}).get("political_unit_records_1900.json", {})
    if manifest_records.get("sha256") != records_sha:
        add_error(errors, "manifest record SHA-256 mismatch")
    if manifest.get("outputs", {}).get("batch2_deterministic_corpus.json", {}).get("sha256") != corpus_sha:
        add_error(errors, "manifest corpus SHA-256 mismatch")
    if manifest.get("outputs", {}).get("batch2_political_unit_records.schema.json", {}).get("sha256") != schema_sha:
        add_error(errors, "manifest schema SHA-256 mismatch")
    if manifest.get("runtime_authority") is not False:
        add_error(errors, "manifest runtime_authority must be false")
    if any(record.get("runtime_authority") is not False for record in units + relationships):
        add_error(errors, "a Batch 2 record declares runtime authority")

    metrics = {
        "source_units": len(source_units),
        "staged_units": len(units),
        "staged_relationships": len(relationships),
        "canonical_match_counts": dict(sorted(actual_matches.items())),
        "status_counts": dict(sorted(actual_status.items())),
        "relationship_counts": dict(sorted(actual_relationships.items())),
        "source_sha256": source_sha,
        "records_sha256": records_sha,
        "manifest_sha256": sha256_file(MANIFEST_PATH),
        "corpus_sha256": corpus_sha,
        "schema_sha256": schema_sha,
    }
    return errors, metrics


def main() -> int:
    errors, metrics = validate()
    print(json.dumps({"ok": not errors, "errors": errors, "metrics": metrics}, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
