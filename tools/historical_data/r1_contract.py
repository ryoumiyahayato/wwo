"""R1 crosswalk and provenance contract checks shared by validators."""

from __future__ import annotations

from collections import Counter
from pathlib import Path
from typing import Any

from crosswalk_policy import crosswalk_policy_errors
from source_reference import validate_repository_source_reference


def validate_crosswalk_records(
    validation: Any,
    crosswalk: Any,
    historical_entities: Any,
    countries: Any,
    source_ids: set[str],
    root: Path,
) -> dict[str, Any]:
    records = crosswalk.get("records", []) if isinstance(crosswalk, dict) else []
    expected_entities = {
        item.get("id")
        for item in (historical_entities.get("entities", []) if isinstance(historical_entities, dict) else [])
        if isinstance(item, dict) and item.get("id")
    }
    current_ids = {
        item.get("id")
        for item in (countries.get("countries", []) if isinstance(countries, dict) else [])
        if isinstance(item, dict) and item.get("id")
    }
    if not isinstance(records, list):
        validation.error("crosswalk.records must be a list")
        records = []

    seen: set[str] = set()
    code_counts: Counter[str] = Counter()
    classification_counts: Counter[str] = Counter()
    identity_counts: Counter[str] = Counter()
    successor_counts: Counter[str] = Counter()
    for index, record in enumerate(records):
        label = f"crosswalk.records[{index}]"
        if not isinstance(record, dict):
            validation.error(f"{label} must be an object")
            continue
        entity_id = record.get("historical_entity_id")
        if not isinstance(entity_id, str) or not entity_id:
            validation.error(f"{label} missing historical_entity_id")
            continue
        if entity_id in seen:
            validation.error(f"duplicate crosswalk historical_entity_id: {entity_id}")
        seen.add(entity_id)
        if entity_id not in expected_entities:
            validation.error(f"{label} is not in the existing historical aggregate file: {entity_id}")
        for message in crosswalk_policy_errors(
            record,
            known_source_ids=source_ids,
            known_current_ids=current_ids,
        ):
            validation.error(f"{label}: {message}")
        for evidence_field in ("historical_identity_evidence", "successor_evidence"):
            evidence = record.get(evidence_field)
            if isinstance(evidence, dict):
                for message in validate_repository_source_reference(
                    root, evidence.get("source_reference")
                ):
                    validation.error(f"{label}.{evidence_field}.source_reference: {message}")
        if record.get("canonical_entity_ids") != record.get("resolved_current_ids"):
            validation.error(f"{label}: canonical_entity_ids must equal code-resolution targets")
        for relative_path in record.get("source_paths", []):
            path = root / relative_path
            if Path(relative_path).is_absolute() or ".." in Path(relative_path).parts or not path.is_file():
                validation.error(f"{label}: source path is not a safe repository file: {relative_path!r}")
        code_counts[record.get("code_resolution_status")] += 1
        classification_counts[record.get("classification_status")] += 1
        identity_counts[record.get("historical_identity_status")] += 1
        successor_counts[record.get("successor_relation_status")] += 1

    if seen != expected_entities:
        validation.error(
            "crosswalk coverage does not match historical aggregate entities: "
            f"missing={sorted(expected_entities - seen)}, extra={sorted(seen - expected_entities)}"
        )
    expected_summary = {
        "code_resolution": {
            key: code_counts.get(key, 0) for key in ("EXACT", "MULTI_MATCH", "AMBIGUOUS", "NO_MATCH")
        },
        "classification": {
            key: classification_counts.get(key, 0)
            for key in ("EXACT_CODE", "LIKELY_COMPOSITE", "AMBIGUOUS", "NO_MATCH")
        },
        "historical_identity": dict(sorted(identity_counts.items())),
        "successor_relation": dict(sorted(successor_counts.items())),
        "automatic_authoritative_candidate_count": sum(
            record.get("automatic_authoritative_candidate") is True
            for record in records
            if isinstance(record, dict)
        ),
    }
    if crosswalk.get("summary") != expected_summary:
        validation.error(
            f"crosswalk summary mismatch: declared={crosswalk.get('summary')!r}, computed={expected_summary!r}"
        )
    return {
        "records": len(records),
        "code_resolution": expected_summary["code_resolution"],
        "classification": expected_summary["classification"],
        "historical_identity": expected_summary["historical_identity"],
        "successor_relation": expected_summary["successor_relation"],
        "automatic_authoritative_candidate_count": expected_summary[
            "automatic_authoritative_candidate_count"
        ],
        "canonical_country_ids": len(current_ids),
    }


def validate_source_record_reference(
    validation: Any,
    root: Path,
    label: str,
    record: dict[str, Any],
    source_ids: set[str],
) -> None:
    if record.get("source_id") not in source_ids:
        validation.error(f"{label} references missing source_id: {record.get('source_id')!r}")
    for message in validate_repository_source_reference(
        root,
        record.get("source_reference"),
        expected_record_id=record.get("historical_entity_id"),
    ):
        validation.error(f"{label}.source_reference: {message}")
