#!/usr/bin/env python3
"""Execute the tracked JSON Schemas for all Batch 1-4 staged payloads."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from json_schema_validator import validate_json_document


ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / "data" / "staging" / "1900"


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


SCHEMA_DRAFT = "https://json-schema.org/draft/2020-12/schema"


def validate_schema_metadata(schema_name: str, schema: Any, expected_id: str) -> list[str]:
    errors: list[str] = []
    if not isinstance(schema, dict):
        return [f"{schema_name}: schema must be an object"]
    if schema.get("$schema") != SCHEMA_DRAFT:
        errors.append(f"{schema_name}: unexpected $schema")
    if schema.get("$id") != expected_id:
        errors.append(f"{schema_name}: unexpected $id {schema.get('$id')!r}")
    return errors


def validate_file(document_name: str, schema_name: str, expected_id: str) -> list[str]:
    document = load_json(STAGING / document_name)
    schema = load_json(STAGING / schema_name)
    errors = validate_schema_metadata(schema_name, schema, expected_id)
    errors.extend(f"{document_name}: {message}" for message in validate_json_document(document, schema))
    return errors


def validate_source_records() -> list[str]:
    payload = load_json(STAGING / "source_records.json")
    wrapper_schema = load_json(STAGING / "source_records.schema.json")
    item_schema = load_json(STAGING / "source_record.schema.json")
    errors = validate_schema_metadata(
        "source_records.schema.json", wrapper_schema, "wwo_1900_source_records_v2"
    )
    errors.extend(
        validate_schema_metadata(
            "source_record.schema.json",
            item_schema,
            "https://wwo.example.invalid/schema/1900/source-record-v2.json",
        )
    )
    wrapper_schema["properties"]["records"]["items"] = item_schema
    errors.extend(
        f"source_records.json: {message}"
        for message in validate_json_document(payload, wrapper_schema)
    )
    return errors


def run() -> tuple[list[str], dict[str, Any]]:
    targets = [
        ("canonical_crosswalk.json", "canonical_crosswalk.schema.json", "wwo_1900_canonical_crosswalk_v2"),
        ("political_unit_records_1900.json", "batch2_political_unit_records.schema.json", "wwo_1900_batch2_political_unit_records_v1"),
        ("batch3_source_gap_candidates.json", "batch3_source_gap_candidates.schema.json", "wwo_1900_batch3_source_gap_candidates_v1"),
        ("batch4_coverage_review_queue.json", "batch4_coverage_review_queue.schema.json", "wwo_1900_batch4_coverage_review_queue_v1"),
    ]
    errors: list[str] = []
    checked: list[str] = []
    for document_name, schema_name, expected_id in targets:
        errors.extend(validate_file(document_name, schema_name, expected_id))
        checked.append(f"{document_name} against {schema_name}")
    errors.extend(validate_source_records())
    checked.append("source_records.json records against source_record.schema.json")
    return errors, {"checked": checked, "error_count": len(errors)}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()
    errors, metrics = run()
    result = {"ok": not errors, "errors": errors, "metrics": metrics}
    print(json.dumps(result if not args.quiet or errors else {"ok": True, "metrics": metrics}, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
