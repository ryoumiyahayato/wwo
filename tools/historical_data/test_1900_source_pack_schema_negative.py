#!/usr/bin/env python3
"""Negative tests proving tracked schemas reject unknown fields."""

from __future__ import annotations

import copy
import json
from pathlib import Path

from json_schema_validator import validate_json_document


ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / "data" / "staging" / "1900"


def load(name: str):
    return json.loads((STAGING / name).read_text(encoding="utf-8-sig"))


def main() -> int:
    cases = [
        ("canonical_crosswalk.json", "canonical_crosswalk.schema.json", None),
        ("political_unit_records_1900.json", "batch2_political_unit_records.schema.json", None),
        ("batch3_source_gap_candidates.json", "batch3_source_gap_candidates.schema.json", None),
        ("batch4_coverage_review_queue.json", "batch4_coverage_review_queue.schema.json", None),
    ]
    checked = []
    for document_name, schema_name, _ in cases:
        document = load(document_name)
        document["unknown_r1_field"] = True
        errors = validate_json_document(document, load(schema_name))
        if not errors:
            raise AssertionError(f"{schema_name} accepted an unknown top-level field")
        checked.append(schema_name)

    source_schema = load("source_record.schema.json")
    source_record = copy.deepcopy(load("source_records.json")["records"][0])
    source_record["unknown_r1_field"] = True
    if not validate_json_document(source_record, source_schema):
        raise AssertionError("source_record.schema.json accepted an unknown field")
    wrapper_schema = load("source_records.schema.json")
    wrapper_schema["properties"]["records"]["items"] = source_schema
    wrapper = load("source_records.json")
    wrapper["records"][0]["unknown_r1_field"] = True
    if not validate_json_document(wrapper, wrapper_schema):
        raise AssertionError("source_records.schema.json accepted an unknown nested field")
    checked.extend(["source_record.schema.json", "source_records.schema.json"])
    print(json.dumps({"ok": True, "schemas": checked}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
