#!/usr/bin/env python3
"""R1 contract checks for code-resolution separation and source references.

This is intentionally a separate focused validator so the shared variable
state audit remains untouched. The base validator imports these functions and
therefore still fails closed on the same invariants.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from crosswalk_policy import crosswalk_policy_errors
from source_reference import validate_repository_source_reference


ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / "data" / "staging" / "1900"


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def validate_crosswalk_document() -> tuple[list[str], dict[str, Any]]:
    errors: list[str] = []
    manifest = load_json(STAGING / "source_manifest.json")
    crosswalk = load_json(STAGING / "canonical_crosswalk.json")
    countries = load_json(ROOT / "data/world_map/countries.json")
    source_ids = {item.get("source_id") for item in manifest.get("sources", [])}
    current_ids = {item.get("id") for item in countries.get("countries", [])}
    records = crosswalk.get("records", [])
    for index, record in enumerate(records):
        for message in crosswalk_policy_errors(
            record,
            known_source_ids=source_ids,
            known_current_ids=current_ids,
        ):
            errors.append(f"crosswalk.records[{index}]: {message}")
        for evidence_field in ("historical_identity_evidence", "successor_evidence"):
            evidence = record.get(evidence_field)
            if isinstance(evidence, dict):
                errors.extend(
                    f"crosswalk.records[{index}].{evidence_field}.source_reference: {message}"
                    for message in validate_repository_source_reference(
                        ROOT, evidence.get("source_reference")
                    )
                )
    automatic_count = sum(record.get("automatic_authoritative_candidate") is True for record in records)
    if automatic_count != 0:
        errors.append(f"unsafe automatic-authority flags remain: {automatic_count}")
    return errors, {
        "records": len(records),
        "automatic_authoritative_candidate_count": automatic_count,
        "historical_identity_unverified": sum(
            record.get("historical_identity_status") == "UNVERIFIED" for record in records
        ),
    }


def validate_source_references() -> tuple[list[str], dict[str, Any]]:
    errors: list[str] = []
    manifest = load_json(STAGING / "source_manifest.json")
    records = load_json(STAGING / "source_records.json").get("records", [])
    source_ids = {item.get("source_id") for item in manifest.get("sources", [])}
    resolved = 0
    for index, record in enumerate(records):
        if record.get("source_id") not in source_ids:
            errors.append(f"source_records.records[{index}]: unknown source_id")
        reference_errors = validate_repository_source_reference(
            ROOT,
            record.get("source_reference"),
            expected_record_id=record.get("historical_entity_id"),
        )
        errors.extend(f"source_records.records[{index}]: {message}" for message in reference_errors)
        if not reference_errors:
            resolved += 1
    return errors, {"records": len(records), "resolved_source_references": resolved}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()
    crosswalk_errors, crosswalk_metrics = validate_crosswalk_document()
    reference_errors, reference_metrics = validate_source_references()
    errors = crosswalk_errors + reference_errors
    result = {"ok": not errors, "errors": errors, "metrics": {**crosswalk_metrics, **reference_metrics}}
    print(json.dumps(result if not args.quiet or errors else {"ok": True, "metrics": result["metrics"]}, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
