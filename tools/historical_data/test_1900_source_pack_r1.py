#!/usr/bin/env python3
"""Focused regression tests for R1 identity, schema, and provenance guards."""

from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

from crosswalk_policy import crosswalk_policy_errors
from json_schema_validator import validate_json_document
from source_reference import validate_repository_source_reference


ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / "data" / "staging" / "1900"


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def base_record() -> dict:
    return {
        "historical_entity_id": "korean_empire",
        "member_codes": ["KOR"],
        "core_member_codes": [],
        "canonical_entity_ids": ["country_kor"],
        "code_resolution_status": "EXACT",
        "resolved_current_id": "country_kor",
        "resolved_current_ids": ["country_kor"],
        "classification_status": "EXACT_CODE",
        "historical_identity_status": "UNVERIFIED",
        "historical_identity_evidence": None,
        "successor_relation_status": "UNVERIFIED",
        "successor_evidence": None,
        "automatic_authoritative_candidate": False,
        "mapping_reason": "Code resolution only.",
        "source_id": "src-test",
        "source_paths": ["data/world_map/historical_political_entities_1900.json"],
    }


def test_identity_promotion_rules() -> None:
    known_sources = {"src-test"}
    known_ids = {"country_kor"}
    record = base_record()
    unsafe = copy.deepcopy(record)
    unsafe["automatic_authoritative_candidate"] = True
    require(
        crosswalk_policy_errors(unsafe, known_source_ids=known_sources, known_current_ids=known_ids),
        "code-only exact resolution must not promote",
    )

    evidence = {
        "source_id": "src-test",
        "source_reference": "data/world_map/historical/political_units_1900.json#units.korean_empire",
        "date_from": "1900-01-01",
        "date_to": "1900-12-31",
        "target_entity_id": "country_kor",
        "evidence_type": "date_scoped_entity_identity",
        "authority_consideration": True,
    }
    reviewable = copy.deepcopy(record)
    reviewable["historical_identity_status"] = "EXPLICIT_EVIDENCE"
    reviewable["historical_identity_evidence"] = evidence
    reviewable["automatic_authoritative_candidate"] = True
    require(
        not crosswalk_policy_errors(reviewable, known_source_ids=known_sources, known_current_ids=known_ids),
        "explicit tracked date-scoped evidence should satisfy the promotion invariant",
    )
    require(
        not validate_repository_source_reference(ROOT, evidence["source_reference"]),
        "explicit evidence source reference should resolve in the repository graph",
    )
    crosswalk_schema = load_json(STAGING / "canonical_crosswalk.schema.json")
    require(
        not validate_json_document(reviewable, {"$defs": crosswalk_schema["$defs"], **crosswalk_schema["$defs"]["record"]}),
        "explicit evidence record should satisfy the record schema",
    )

    missing_evidence = copy.deepcopy(reviewable)
    missing_evidence["historical_identity_evidence"] = None
    require(
        crosswalk_policy_errors(missing_evidence, known_source_ids=known_sources, known_current_ids=known_ids),
        "missing successor/identity evidence must not promote",
    )

    ambiguous = copy.deepcopy(record)
    ambiguous["code_resolution_status"] = "AMBIGUOUS"
    ambiguous["classification_status"] = "AMBIGUOUS"
    ambiguous["resolved_current_id"] = None
    ambiguous["automatic_authoritative_candidate"] = True
    require(
        crosswalk_policy_errors(ambiguous, known_source_ids=known_sources, known_current_ids=known_ids),
        "ambiguous current code must not promote",
    )

    no_match = copy.deepcopy(record)
    no_match["code_resolution_status"] = "NO_MATCH"
    no_match["classification_status"] = "NO_MATCH"
    no_match["canonical_entity_ids"] = []
    no_match["resolved_current_id"] = None
    no_match["resolved_current_ids"] = []
    require(
        not crosswalk_policy_errors(no_match, known_source_ids=known_sources, known_current_ids=known_ids),
        "no code match must remain unresolved when promotion is attempted",
    )


def test_schema_rejects_unknown_fields() -> None:
    schema = load_json(STAGING / "canonical_crosswalk.schema.json")
    document = load_json(STAGING / "canonical_crosswalk.json")
    mutated = copy.deepcopy(document)
    mutated["unexpected_r1_field"] = True
    require(
        validate_json_document(mutated, schema),
        "canonical crosswalk additionalProperties=false must reject unknown fields",
    )
    source_schema = load_json(STAGING / "source_record.schema.json")
    source_record = load_json(STAGING / "source_records.json")["records"][0]
    mutated_record = copy.deepcopy(source_record)
    mutated_record["unexpected_r1_field"] = True
    require(
        validate_json_document(mutated_record, source_schema),
        "source record additionalProperties=false must reject unknown fields",
    )


def test_source_reference_graph() -> None:
    source_records = load_json(STAGING / "source_records.json")["records"]
    for record in source_records:
        require(
            not validate_repository_source_reference(
                ROOT,
                record["source_reference"],
                expected_record_id=record["historical_entity_id"],
            ),
            f"source reference should resolve: {record['record_id']}",
        )
    dangling = "data/world_map/historical/political_units_1900.json#units.not_a_real_id"
    require(
        validate_repository_source_reference(ROOT, dangling),
        "dangling source reference must fail",
    )
    require(
        validate_repository_source_reference(ROOT, "data/world_map/historical/political_units_1900.json"),
        "source reference without a fragment must fail",
    )
    require(
        validate_repository_source_reference(ROOT, "../countries.json#countries.country_fra"),
        "repository-traversal source reference must fail",
    )


def main() -> int:
    test_identity_promotion_rules()
    test_schema_rejects_unknown_fields()
    test_source_reference_graph()
    print(json.dumps({"ok": True, "tests": 3}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
