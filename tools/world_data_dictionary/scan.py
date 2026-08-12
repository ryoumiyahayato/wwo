#!/usr/bin/env python3
"""Validate the structural consistency of a generated world-data dictionary."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def scan_dictionary(path: Path) -> list[str]:
    errors: list[str] = []
    try:
        dictionary: dict[str, Any] = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        return [f"cannot read dictionary: {exc}"]
    if dictionary.get("schema_version") != 1:
        errors.append("unsupported dictionary schema_version")
    datasets = dictionary.get("datasets")
    if not isinstance(datasets, list):
        return errors + ["datasets must be an array"]
    dataset_ids: set[str] = set()
    for dataset in datasets:
        if not isinstance(dataset, dict):
            errors.append("dataset entry is not an object")
            continue
        dataset_id = str(dataset.get("dataset", ""))
        if not dataset_id:
            errors.append("dataset has no dataset ID")
        if dataset_id in dataset_ids:
            errors.append(f"duplicate dataset ID: {dataset_id}")
        dataset_ids.add(dataset_id)
        fields = dataset.get("fields")
        if not isinstance(fields, list):
            errors.append(f"{dataset_id}: fields must be an array")
            continue
        field_keys: set[tuple[str, str]] = set()
        for field in fields:
            if not isinstance(field, dict):
                errors.append(f"{dataset_id}: field entry is not an object")
                continue
            key = (str(field.get("field", "")), str(field.get("record_scope", "")))
            if key in field_keys:
                errors.append(f"{dataset_id}: duplicate field/scope {key}")
            field_keys.add(key)
            record_count = field.get("record_count")
            present_count = field.get("present_count")
            missing_count = field.get("missing_count")
            if record_count is not None and (not isinstance(record_count, int) or record_count < 0):
                errors.append(f"{dataset_id}.{key[0]}: invalid record_count")
            if not isinstance(present_count, int) or present_count < 0:
                errors.append(f"{dataset_id}.{key[0]}: invalid present_count")
            if missing_count is not None and (not isinstance(missing_count, int) or missing_count < 0):
                errors.append(f"{dataset_id}.{key[0]}: invalid missing_count")
            if record_count is not None and present_count > record_count:
                errors.append(f"{dataset_id}.{key[0]}: present_count exceeds record_count")
            if record_count is not None and missing_count is not None and present_count + missing_count != record_count:
                errors.append(f"{dataset_id}.{key[0]}: present + missing does not equal records")
            if field.get("declared") and not field.get("declared_evidence"):
                errors.append(f"{dataset_id}.{key[0]}: declared field has no evidence")
            for evidence in field.get("declared_evidence", []):
                if evidence.get("evidence_scope") not in {"LOADER", "VALIDATOR", "SOURCE_CONFIG", "RUNTIME_SNAPSHOT"}:
                    errors.append(f"{dataset_id}.{key[0]}: declared evidence has invalid scope")
            if field.get("declared_foreign_key_targets"):
                errors.append(f"{dataset_id}.{key[0]}: ID-kind evidence cannot declare catalog FK targets")
    relationships = dictionary.get("foreign_key_relationships", [])
    if not isinstance(relationships, list):
        errors.append("foreign_key_relationships must be an array")
    for relationship in relationships:
        if relationship.get("evidence") != "DECLARED_FOREIGN_KEY":
            errors.append("foreign_key_relationships may only contain resolved declared references")
    contract = dictionary.get("generation_contract", {})
    if contract.get("production_data_modified") is not False:
        errors.append("generation contract does not prove production_data_modified=false")
    if dictionary.get("summary", {}).get("input_errors", 0) != 0:
        errors.append("dictionary contains input_errors")
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dictionary", type=Path)
    args = parser.parse_args(argv)
    errors = scan_dictionary(args.dictionary)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    dictionary = json.loads(args.dictionary.read_text(encoding="utf-8"))
    print(json.dumps({"status": "ok", **dictionary.get("summary", {})}, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
