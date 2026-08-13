#!/usr/bin/env python3
"""Validate Batch 4 coverage review queue against its two existing inputs."""

from __future__ import annotations

import hashlib
import json
from collections import Counter
from pathlib import Path
from typing import Any

from json_schema_validator import validate_json_document


ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / "data" / "staging" / "1900"
SCHEMA_PATH = STAGING / "batch4_coverage_review_queue.schema.json"
QUEUE_PATH = STAGING / "batch4_coverage_review_queue.json"
CORPUS_PATH = STAGING / "batch4_deterministic_corpus.json"
MANIFEST_PATH = STAGING / "batch4_manifest.json"
ADMIN1_PATH = ROOT / "data" / "world_map" / "historical" / "historical_admin1_1900.json"
ECONOMY_PATH = ROOT / "data" / "alpha" / "historical_economy_coverage_1900.json"


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate() -> tuple[list[str], dict[str, Any]]:
    errors: list[str] = []
    schema = load_json(SCHEMA_PATH)
    queue = load_json(QUEUE_PATH)
    corpus = load_json(CORPUS_PATH)
    manifest = load_json(MANIFEST_PATH)
    admin1 = load_json(ADMIN1_PATH)
    economy = load_json(ECONOMY_PATH)
    errors.extend(
        f"JSON Schema: {message}"
        for message in validate_json_document(queue, schema)
    )
    admin1_sha = sha256_file(ADMIN1_PATH)
    economy_sha = sha256_file(ECONOMY_PATH)

    if schema.get("$id") != "wwo_1900_batch4_coverage_review_queue_v1":
        errors.append("schema $id mismatch")
    if queue.get("schema_id") != "wwo_1900_batch4_coverage_review_queue_v1" or queue.get("batch") != 4 or queue.get("snapshot_date") != "1900-03-12":
        errors.append("queue schema, batch, or snapshot mismatch")
    policy = queue.get("policy", {})
    if policy.get("historical_fact") is not False or policy.get("runtime_authority") is not False or policy.get("numeric_values") != "none_added" or policy.get("no_inference") is not True:
        errors.append("queue safety policy mismatch")

    admin_queue = queue.get("admin1_queue", [])
    economy_queue = queue.get("economy_queue", [])
    if len(admin_queue) != len(admin1.get("countries", [])):
        errors.append("admin1 queue count mismatch")
    expected_economy_count = sum(len(record.get("missing_dimensions", [])) for record in economy.get("countries", []))
    if len(economy_queue) != expected_economy_count:
        errors.append("economy queue count mismatch")
    queue_ids = [item.get("queue_id") for item in admin_queue + economy_queue]
    if len(queue_ids) != len(set(queue_ids)):
        errors.append("duplicate queue IDs")

    expected_admin_ids = {record["entity_id"] for record in admin1["countries"]}
    actual_admin_ids = {item.get("source_record_id") for item in admin_queue}
    if actual_admin_ids != expected_admin_ids:
        errors.append("admin1 queue IDs do not cover source records exactly")
    for index, source_record in enumerate(admin1["countries"]):
        matches = [item for item in admin_queue if item.get("source_record_id") == source_record["entity_id"]]
        if len(matches) != 1:
            errors.append(f"admin1 source record missing or duplicated: {source_record['entity_id']}")
            continue
        item = matches[0]
        expected = {
            "queue_id": f"admin1:{source_record['entity_id']}",
            "queue_type": "admin1_coverage_review",
            "source_path": "data/world_map/historical/historical_admin1_1900.json",
            "source_index": index,
            "source_sha256": admin1_sha,
            "candidate_status": "REVIEW_REQUIRED",
            "historical_fact": False,
            "runtime_authority": False,
            "source_record": source_record,
        }
        for key, value in expected.items():
            if item.get(key) != value:
                errors.append(f"admin1:{source_record['entity_id']}: field {key} mismatch")
        if not item.get("required_evidence") or not item.get("notes", "").startswith("Copied from existing admin1 coverage"):
            errors.append(f"admin1:{source_record['entity_id']}: safety metadata missing")

    expected_economy_pairs = {(record["entity_id"], dimension) for record in economy["countries"] for dimension in record.get("missing_dimensions", [])}
    actual_economy_pairs = {(item.get("entity_id"), item.get("dimension")) for item in economy_queue}
    if actual_economy_pairs != expected_economy_pairs:
        errors.append("economy queue pairs do not cover missing dimensions exactly")
    for index, source_record in enumerate(economy["countries"]):
        for dimension in source_record.get("missing_dimensions", []):
            queue_id = f"economy:{source_record['entity_id']}:{dimension}"
            matches = [item for item in economy_queue if item.get("queue_id") == queue_id]
            if len(matches) != 1:
                errors.append(f"economy queue item missing or duplicated: {queue_id}")
                continue
            item = matches[0]
            expected = {
                "queue_type": "economy_dimension_review",
                "source_path": "data/alpha/historical_economy_coverage_1900.json",
                "source_record_id": source_record["entity_id"],
                "source_index": index,
                "source_sha256": economy_sha,
                "entity_id": source_record["entity_id"],
                "dimension": dimension,
                "source_status": source_record["status"],
                "candidate_status": "REVIEW_REQUIRED",
                "historical_fact": False,
                "runtime_authority": False,
                "source_record": source_record,
            }
            for key, value in expected.items():
                if item.get(key) != value:
                    errors.append(f"{queue_id}: field {key} mismatch")
            if not item.get("required_evidence") or not item.get("notes", "").startswith("Generated from an existing missing-dimension declaration"):
                errors.append(f"{queue_id}: safety metadata missing")

    expected_summary = {
        "admin1_items": len(admin1["countries"]),
        "economy_items": expected_economy_count,
        "total_items": len(admin1["countries"]) + expected_economy_count,
        "admin1_unit_names": sum(len(record["units"]) for record in admin1["countries"]),
        "economy_dimensions": len(economy["dimensions"]),
        "source_file_counts": {
            "data/alpha/historical_economy_coverage_1900.json": len(economy["countries"]),
            "data/world_map/historical/historical_admin1_1900.json": len(admin1["countries"]),
        },
    }
    if queue.get("summary") != expected_summary:
        errors.append("queue summary mismatch")

    input_digests = corpus.get("input_digests", {})
    if input_digests.get("data/world_map/historical/historical_admin1_1900.json") != admin1_sha or input_digests.get("data/alpha/historical_economy_coverage_1900.json") != economy_sha:
        errors.append("corpus input digest mismatch")
    queue_sha = sha256_file(QUEUE_PATH)
    corpus_sha = sha256_file(CORPUS_PATH)
    schema_sha = sha256_file(SCHEMA_PATH)
    if corpus.get("expected_queue_sha256") != queue_sha or corpus.get("expected_schema_sha256") != schema_sha:
        errors.append("corpus output digest mismatch")
    if manifest.get("outputs", {}).get("batch4_coverage_review_queue.json", {}).get("sha256") != queue_sha:
        errors.append("manifest queue digest mismatch")
    if manifest.get("outputs", {}).get("batch4_deterministic_corpus.json", {}).get("sha256") != corpus_sha:
        errors.append("manifest corpus digest mismatch")
    if manifest.get("outputs", {}).get("batch4_coverage_review_queue.schema.json", {}).get("sha256") != schema_sha:
        errors.append("manifest schema digest mismatch")
    if manifest.get("runtime_authority") is not False or manifest.get("protected_scope", {}).get("historical_fact_inferred") is not False or manifest.get("protected_scope", {}).get("numeric_values_added") is not False:
        errors.append("manifest safety guards mismatch")

    output_text = "\n".join(path.read_text(encoding="utf-8") for path in [QUEUE_PATH, CORPUS_PATH, MANIFEST_PATH])
    if str(ROOT).replace("\\", "/").lower() in output_text.replace("\\", "/").lower():
        errors.append("generated output contains an absolute repository path")

    metrics = {
        "admin1_items": len(admin_queue),
        "economy_items": len(economy_queue),
        "total_items": len(admin_queue) + len(economy_queue),
        "admin1_unit_names": expected_summary["admin1_unit_names"],
        "economy_dimensions": len(economy["dimensions"]),
        "queue_sha256": queue_sha,
        "corpus_sha256": corpus_sha,
        "manifest_sha256": sha256_file(MANIFEST_PATH),
        "schema_sha256": schema_sha,
    }
    return errors, metrics


def main() -> int:
    errors, metrics = validate()
    print(json.dumps({"ok": not errors, "errors": errors, "metrics": metrics}, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
