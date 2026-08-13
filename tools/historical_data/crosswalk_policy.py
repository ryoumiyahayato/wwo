"""Shared policy checks for staged historical crosswalk records.

This module intentionally treats current-catalog code resolution as a
reference lookup. It never infers historical identity, sovereignty, or a
successor relationship from a name, code, or current ID.
"""

from __future__ import annotations

import re
from datetime import date
from typing import Any


CODE_RESOLUTION_STATUSES = {"EXACT", "MULTI_MATCH", "AMBIGUOUS", "NO_MATCH"}
CLASSIFICATION_STATUSES = {"EXACT_CODE", "LIKELY_COMPOSITE", "AMBIGUOUS", "NO_MATCH"}
IDENTITY_STATUSES = {"UNVERIFIED", "REVIEW_REQUIRED", "EXPLICIT_EVIDENCE"}
EVIDENCE_TYPES = {
    "date_scoped_entity_identity",
    "date_scoped_successor_relation",
}
SOURCE_REFERENCE_RE = re.compile(r"^[^#\s]+#[^\s]+$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def _parse_date(value: Any) -> date | None:
    if not isinstance(value, str) or not DATE_RE.fullmatch(value):
        return None
    try:
        return date.fromisoformat(value)
    except ValueError:
        return None


def evidence_errors(
    evidence: Any,
    *,
    label: str,
    known_source_ids: set[str],
    known_current_ids: set[str],
    snapshot_date: str,
) -> list[str]:
    errors: list[str] = []
    if not isinstance(evidence, dict):
        return [f"{label} must be an evidence object"]
    required = {
        "source_id",
        "source_reference",
        "date_from",
        "date_to",
        "target_entity_id",
        "evidence_type",
        "authority_consideration",
    }
    missing = sorted(required - set(evidence))
    if missing:
        errors.append(f"{label} missing required fields: {missing}")
        return errors
    if evidence.get("source_id") not in known_source_ids:
        errors.append(f"{label}.source_id is not a known source")
    reference = evidence.get("source_reference")
    if not isinstance(reference, str) or not SOURCE_REFERENCE_RE.fullmatch(reference):
        errors.append(f"{label}.source_reference must contain a non-empty fragment")
    start = _parse_date(evidence.get("date_from"))
    end = _parse_date(evidence.get("date_to"))
    snapshot = _parse_date(snapshot_date)
    if start is None or end is None:
        errors.append(f"{label} date scope must use valid ISO dates")
    elif start > end:
        errors.append(f"{label} date_from is after date_to")
    elif snapshot is not None and not (start <= snapshot <= end):
        errors.append(f"{label} date scope does not include the pack snapshot")
    target = evidence.get("target_entity_id")
    if not isinstance(target, str) or target not in known_current_ids:
        errors.append(f"{label}.target_entity_id is not a known current catalog ID")
    if evidence.get("evidence_type") not in EVIDENCE_TYPES:
        errors.append(f"{label}.evidence_type is not allowed for authority consideration")
    if evidence.get("authority_consideration") is not True:
        errors.append(f"{label}.authority_consideration must be true for promotion")
    return errors


def automatic_authority_errors(
    record: dict[str, Any],
    *,
    known_source_ids: set[str],
    known_current_ids: set[str],
    snapshot_date: str = "1900-03-12",
) -> list[str]:
    """Return hard errors for an attempted automatic authority promotion."""

    errors: list[str] = []
    if record.get("automatic_authoritative_candidate") is not True:
        return errors

    code_status = record.get("code_resolution_status")
    if code_status != "EXACT":
        errors.append("automatic authority requires EXACT code resolution")
    target = record.get("resolved_current_id")
    if not isinstance(target, str) or target not in known_current_ids:
        errors.append("automatic authority requires one known resolved_current_id")
    target_ids = record.get("resolved_current_ids")
    if target_ids != [target]:
        errors.append("automatic authority requires resolved_current_ids=[resolved_current_id]")

    evidence_candidates = [
        ("historical_identity_evidence", record.get("historical_identity_evidence")),
        ("successor_evidence", record.get("successor_evidence")),
    ]
    supplied = [(label, value) for label, value in evidence_candidates if value is not None]
    if not supplied:
        errors.append(
            "automatic authority requires explicit date-scoped historical identity or successor evidence"
        )
        return errors
    if (
        record.get("historical_identity_status") != "EXPLICIT_EVIDENCE"
        and record.get("successor_relation_status") != "EXPLICIT_EVIDENCE"
    ):
        errors.append(
            "automatic authority requires an EXPLICIT_EVIDENCE identity or successor status"
        )
    evidence_ok = False
    for label, evidence in supplied:
        candidate_errors = evidence_errors(
            evidence,
            label=label,
            known_source_ids=known_source_ids,
            known_current_ids=known_current_ids,
            snapshot_date=snapshot_date,
        )
        errors.extend(candidate_errors)
        if not candidate_errors and evidence.get("target_entity_id") == target:
            evidence_ok = True
        elif not candidate_errors:
            errors.append(f"{label}.target_entity_id must equal resolved_current_id")
    if not evidence_ok:
        errors.append("no valid identity/successor evidence targets the resolved current ID")
    return errors


def crosswalk_policy_errors(
    record: dict[str, Any],
    *,
    known_source_ids: set[str],
    known_current_ids: set[str],
    snapshot_date: str = "1900-03-12",
) -> list[str]:
    """Validate separation fields without requiring a promotion."""

    errors: list[str] = []
    code_status = record.get("code_resolution_status")
    if code_status not in CODE_RESOLUTION_STATUSES:
        errors.append(f"unsupported code_resolution_status: {code_status!r}")
    classification = record.get("classification_status")
    if classification not in CLASSIFICATION_STATUSES:
        errors.append(f"unsupported classification_status: {classification!r}")
    identity_status = record.get("historical_identity_status")
    if identity_status not in IDENTITY_STATUSES:
        errors.append(f"unsupported historical_identity_status: {identity_status!r}")
    successor_status = record.get("successor_relation_status")
    if successor_status not in IDENTITY_STATUSES:
        errors.append(f"unsupported successor_relation_status: {successor_status!r}")

    target_ids = record.get("resolved_current_ids")
    if not isinstance(target_ids, list) or any(
        not isinstance(target, str) or target not in known_current_ids for target in target_ids
    ):
        errors.append("resolved_current_ids must be a list of known current catalog IDs")
    target = record.get("resolved_current_id")
    if target is not None and target not in known_current_ids:
        errors.append("resolved_current_id is not a known current catalog ID")
    if code_status == "EXACT":
        if not isinstance(target_ids, list) or len(target_ids) != 1 or target != target_ids[0]:
            errors.append("EXACT code resolution requires exactly one resolved_current_id")
    elif target is not None:
        errors.append("non-EXACT code resolution cannot expose resolved_current_id")
    if code_status in {"MULTI_MATCH", "AMBIGUOUS", "NO_MATCH"} and record.get("automatic_authoritative_candidate") is True:
        errors.append("automatic authority is forbidden for non-EXACT code resolution")

    for label, evidence in (
        ("historical_identity_evidence", record.get("historical_identity_evidence")),
        ("successor_evidence", record.get("successor_evidence")),
    ):
        if evidence is not None:
            errors.extend(
                evidence_errors(
                    evidence,
                    label=label,
                    known_source_ids=known_source_ids,
                    known_current_ids=known_current_ids,
                    snapshot_date=snapshot_date,
                )
            )
    errors.extend(
        automatic_authority_errors(
            record,
            known_source_ids=known_source_ids,
            known_current_ids=known_current_ids,
            snapshot_date=snapshot_date,
        )
    )
    if record.get("automatic_authoritative_candidate") is not True:
        if record.get("historical_identity_status") == "EXPLICIT_EVIDENCE" and record.get("historical_identity_evidence") is None:
            errors.append("EXPLICIT_EVIDENCE identity status requires historical_identity_evidence")
        if record.get("successor_relation_status") == "EXPLICIT_EVIDENCE" and record.get("successor_evidence") is None:
            errors.append("EXPLICIT_EVIDENCE successor status requires successor_evidence")
    return errors
