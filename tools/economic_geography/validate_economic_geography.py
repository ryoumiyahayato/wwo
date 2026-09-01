#!/usr/bin/env python3
"""Fail-closed validation for the 1900 economic-geography R1 contract.

The validator is intentionally outside the Godot runtime. It checks that
qualitative historical assertions, modern spatial crosswalks, source metadata,
compatibility mappings, and ordinal evidence priors remain separate contracts.
"""

from __future__ import annotations

import argparse
import json
import re
from datetime import date
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
EVIDENCE_PATH = Path("data/economic_geography/evidence/economic_region_evidence_1900.json")
SOURCE_PATH = Path("data/economic_geography/source_registry.json")
CALIBRATION_PATH = Path("data/economic_geography/calibration/economic_region_calibration_1900.json")
SECTOR_PATH = Path("data/economic_geography/sector_catalog.json")
COMPATIBILITY_PATH = Path("data/economic_geography/commodity_compatibility.json")
COMMODITY_PATH = Path("data/alpha/commodity_market_1900.json")
SPATIAL_PATH = Path("data/world_map/world_admin1.json")

CONFIDENCE_VALUES = {"LOW", "MEDIUM", "HIGH", "UNASSESSED"}
EVIDENCE_LEVELS = {"PRESENT", "MATERIAL", "MAJOR", "DOMINANT", "UNKNOWN"}
TEMPORAL_BASIS_VALUES = {
    "DIRECT_1900",
    "NEAR_1900",
    "RETROSPECTIVE_BUT_APPLICABLE",
    "TEMPORALLY_WEAK",
}
SIMULATION_APPLICABILITY_VALUES = {
    "DIRECT_1900_STRUCTURAL_ONLY",
    "NEAR_1900_STRUCTURAL_ONLY",
    "RETROSPECTIVE_1900_STRUCTURAL_ONLY",
    "NOT_FOR_QUANTITATIVE_CALIBRATION",
}
SOURCE_CLASS_VALUES = {
    "PRIMARY_OFFICIAL_STATISTICS",
    "CONTEMPORARY_OFFICIAL_REPORT",
    "CONTEMPORARY_REFERENCE",
    "LATER_SCHOLARLY_SYNTHESIS",
    "MODERN_SPATIAL_REFERENCE",
    "INTERNAL_PROJECT_CATALOG",
    "OTHER",
}
CLAIM_KINDS = {
    "RESOURCE_ENDOWMENT",
    "AGRICULTURAL_PROFILE",
    "EXTRACTION_PROFILE",
    "INDUSTRIAL_PROFILE",
    "INFRASTRUCTURE",
    "POPULATION_LABOR",
}
SUBJECT_KINDS = {"COMMODITY", "SECTOR", "INFRASTRUCTURE", "POPULATION_LABOR"}
ALLOCATION_BASIS_VALUES = {"EVIDENCE_DERIVED", "CROSSWALK_ESTIMATE", "UNRESOLVED"}
COMPATIBILITY_STATUS_VALUES = {
    "CANONICAL_DIRECT",
    "COMPATIBLE_ALIAS",
    "SECTOR_ONLY",
    "FUTURE_GAP_UNRESOLVED",
}
CALIBRATION_ROLES = {"EVIDENCE_PRIOR_ONLY", "DIRECT_PHYSICAL_PRODUCTION_CAPACITY"}
VALUE_KINDS = {"OBSERVED", "ESTIMATE", "INFERRED_RANGE", "CONVERTED"}
ID_PATTERN = re.compile(r"^[a-z0-9][a-z0-9_:-]*$")


def load_json(root: Path, relative_path: Path) -> Any:
    return json.loads((root / relative_path).read_text(encoding="utf-8"))


def _finding(errors: list[str], code: str, path: str, message: str) -> None:
    errors.append(f"[{code}] {path}: {message}")


def _is_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _is_integer(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _check_confidence(value: Any, path: str, errors: list[str]) -> None:
    if value not in CONFIDENCE_VALUES:
        _finding(errors, "MALFORMED_CONFIDENCE", path, f"expected one of {sorted(CONFIDENCE_VALUES)}")


def _check_id(value: Any, path: str, errors: list[str]) -> None:
    if not isinstance(value, str) or not ID_PATTERN.fullmatch(value):
        _finding(errors, "INVALID_ID", path, "expected a lowercase stable ID")


def _check_unique_string_list(
    value: Any,
    path: str,
    errors: list[str],
    *,
    required: bool = True,
) -> list[str]:
    if not isinstance(value, list):
        _finding(errors, "INVALID_LIST", path, "expected an array")
        return []
    if required and not value:
        _finding(errors, "EMPTY_LIST", path, "expected at least one item")
    result: list[str] = []
    seen: set[str] = set()
    for index, item in enumerate(value):
        if not isinstance(item, str) or not item.strip():
            _finding(errors, "INVALID_LIST_ITEM", f"{path}[{index}]", "expected a non-empty string")
            continue
        if item in seen:
            _finding(errors, "DUPLICATE_LIST_ID", f"{path}[{index}]", f"duplicate value {item!r}")
        seen.add(item)
        result.append(item)
    return result


def _check_date(value: Any, path: str, errors: list[str], *, nullable: bool = False) -> date | None:
    if value is None and nullable:
        return None
    if not isinstance(value, str):
        _finding(errors, "INVALID_DATE", path, "expected ISO-8601 date")
        return None
    try:
        return date.fromisoformat(value)
    except ValueError:
        _finding(errors, "INVALID_DATE", path, "expected ISO-8601 date")
        return None


def _check_date_pair(
    start_value: Any,
    end_value: Any,
    path: str,
    errors: list[str],
    *,
    nullable: bool,
) -> tuple[date | None, date | None]:
    start = _check_date(start_value, f"{path}.from", errors, nullable=nullable)
    end = _check_date(end_value, f"{path}.to", errors, nullable=nullable)
    if (start is None) != (end is None):
        _finding(errors, "INVALID_OBSERVATION_PERIOD", path, "from and to must both be dates or both be null")
    if start is not None and end is not None and start >= end:
        _finding(errors, "INVALID_OBSERVATION_PERIOD", path, "from must be earlier than to")
    return start, end


def _check_source_ids(
    value: Any,
    path: str,
    known_sources: set[str],
    errors: list[str],
    *,
    required: bool = True,
) -> list[str]:
    source_ids = _check_unique_string_list(value, path, errors, required=required)
    for index, source_id in enumerate(source_ids):
        if source_id not in known_sources:
            _finding(errors, "UNKNOWN_SOURCE_ID", f"{path}[{index}]", f"unknown source ID {source_id!r}")
    return source_ids


def _check_quantitative_evidence(
    value: Any,
    path: str,
    known_sources: set[str],
    errors: list[str],
) -> int:
    if value is None:
        return 0
    if not isinstance(value, list):
        _finding(errors, "INVALID_QUANTITATIVE_EVIDENCE", path, "expected an array")
        return 0
    count = 0
    for index, item in enumerate(value):
        item_path = f"{path}[{index}]"
        if not isinstance(item, dict):
            _finding(errors, "INVALID_QUANTITATIVE_EVIDENCE", item_path, "expected an object")
            continue
        has_value = "value" in item and _is_number(item.get("value"))
        has_range = (
            "range_low" in item
            and "range_high" in item
            and _is_number(item.get("range_low"))
            and _is_number(item.get("range_high"))
        )
        if not has_value and not has_range:
            _finding(errors, "INVALID_QUANTITATIVE_VALUE", item_path, "requires numeric value or numeric range")
        if not _is_string(item.get("unit")):
            _finding(errors, "QUANTITATIVE_VALUE_WITHOUT_UNIT", item_path, "quantitative evidence requires a unit")
        source_ids = item.get("source_ids")
        if not isinstance(source_ids, list) or not source_ids:
            _finding(errors, "QUANTITATIVE_VALUE_WITHOUT_PROVENANCE", item_path, "quantitative evidence requires source_ids")
        else:
            _check_source_ids(source_ids, f"{item_path}.source_ids", known_sources, errors)
        value_kind = item.get("value_kind")
        if value_kind not in VALUE_KINDS:
            _finding(errors, "INVALID_QUANTITATIVE_VALUE_KIND", item_path, f"expected one of {sorted(VALUE_KINDS)}")
        if value_kind == "INFERRED_RANGE" and not has_range:
            _finding(errors, "INVALID_QUANTITATIVE_VALUE", item_path, "INFERRED_RANGE requires range_low and range_high")
        if has_range and float(item["range_low"]) > float(item["range_high"]):
            _finding(errors, "INVALID_QUANTITATIVE_RANGE", item_path, "range_low must not exceed range_high")
        if value_kind == "CONVERTED":
            if not _is_string(item.get("original_unit")):
                _finding(errors, "MISSING_ORIGINAL_UNIT", item_path, "converted value must retain original_unit")
            conversion = item.get("conversion")
            if not isinstance(conversion, dict) or not all(
                _is_string(conversion.get(key)) for key in ("from_unit", "to_unit", "method")
            ):
                _finding(errors, "MISSING_UNIT_CONVERSION", item_path, "converted value requires explicit from_unit, to_unit, and method")
        count += 1
    return count


def _validate_source_registry(document: Any, errors: list[str]) -> set[str]:
    known_sources: set[str] = set()
    if not isinstance(document, dict):
        _finding(errors, "INVALID_SOURCE_REGISTRY", "source_registry", "expected an object")
        return known_sources
    if document.get("schema_id") != "wwo_economic_geography_source_registry_r1_v2":
        _finding(errors, "INVALID_SOURCE_REGISTRY", "source_registry.schema_id", "unexpected schema ID")
    if document.get("schema_version") != 2:
        _finding(errors, "INVALID_SOURCE_REGISTRY", "source_registry.schema_version", "expected version 2")
    sources = document.get("sources")
    if not isinstance(sources, list):
        _finding(errors, "INVALID_SOURCE_REGISTRY", "source_registry.sources", "expected an array")
        return known_sources
    for index, source in enumerate(sources):
        path = f"source_registry.sources[{index}]"
        if not isinstance(source, dict):
            _finding(errors, "INVALID_SOURCE_RECORD", path, "expected an object")
            continue
        source_id = source.get("source_id")
        _check_id(source_id, f"{path}.source_id", errors)
        if source_id in known_sources:
            _finding(errors, "DUPLICATE_SOURCE_ID", f"{path}.source_id", f"duplicate source ID {source_id!r}")
        if isinstance(source_id, str):
            known_sources.add(source_id)
        for field in (
            "title",
            "author_or_institution",
            "publication_date",
            "source_class",
            "accessed_at",
            "version_or_edition",
            "locator",
            "reliability_notes",
            "observation_period_notes",
        ):
            if not _is_string(source.get(field)):
                _finding(errors, "MISSING_SOURCE_FIELD", f"{path}.{field}", "required non-empty source metadata")
        if source.get("source_class") not in SOURCE_CLASS_VALUES:
            _finding(errors, "INVALID_SOURCE_CLASS", f"{path}.source_class", f"expected one of {sorted(SOURCE_CLASS_VALUES)}")
        if source.get("stable_url") is None and source.get("archive_reference") is None:
            _finding(errors, "MISSING_SOURCE_REFERENCE", path, "stable_url or archive_reference is required")
        _check_date(source.get("accessed_at"), f"{path}.accessed_at", errors)
        _check_date_pair(
            source.get("observation_from"),
            source.get("observation_to"),
            f"{path}.observation_period",
            errors,
            nullable=True,
        )
    return known_sources


def _validate_catalogs(
    commodity_document: Any,
    spatial_document: Any,
    sector_document: Any,
    errors: list[str],
) -> tuple[set[str], set[str], set[str]]:
    commodities: set[str] = set()
    sectors: set[str] = set()
    spatial_ids: set[str] = set()
    if not isinstance(commodity_document, dict):
        _finding(errors, "INVALID_COMMODITY_CATALOG", "commodity_catalog", "expected an object")
    else:
        for index, item in enumerate(commodity_document.get("commodities", [])):
            path = f"commodity_catalog.commodities[{index}]"
            if not isinstance(item, dict):
                _finding(errors, "INVALID_COMMODITY_RECORD", path, "expected an object")
                continue
            commodity_id = item.get("commodity_id")
            if not isinstance(commodity_id, str) or not commodity_id:
                _finding(errors, "INVALID_COMMODITY_ID", path, "missing commodity_id")
            elif commodity_id in commodities:
                _finding(errors, "DUPLICATE_COMMODITY_ID", path, f"duplicate commodity ID {commodity_id!r}")
            else:
                commodities.add(commodity_id)
    if not isinstance(spatial_document, dict):
        _finding(errors, "INVALID_SPATIAL_CATALOG", "spatial_catalog", "expected an object")
    else:
        for index, item in enumerate(spatial_document.get("regions", [])):
            path = f"spatial_catalog.regions[{index}]"
            if not isinstance(item, dict):
                _finding(errors, "INVALID_SPATIAL_RECORD", path, "expected an object")
                continue
            region_id = item.get("id")
            if not isinstance(region_id, str) or not region_id:
                _finding(errors, "INVALID_SPATIAL_ID", path, "missing id")
            elif region_id in spatial_ids:
                _finding(errors, "DUPLICATE_SPATIAL_ID", path, f"duplicate spatial ID {region_id!r}")
            else:
                spatial_ids.add(region_id)
    if not isinstance(sector_document, dict):
        _finding(errors, "INVALID_SECTOR_CATALOG", "sector_catalog", "expected an object")
    else:
        for index, item in enumerate(sector_document.get("sectors", [])):
            path = f"sector_catalog.sectors[{index}]"
            if not isinstance(item, dict):
                _finding(errors, "INVALID_SECTOR_RECORD", path, "expected an object")
                continue
            sector_id = item.get("sector_id")
            if not isinstance(sector_id, str) or not sector_id:
                _finding(errors, "INVALID_SECTOR_ID", path, "missing sector_id")
            elif sector_id in sectors:
                _finding(errors, "DUPLICATE_SECTOR_ID", path, f"duplicate sector ID {sector_id!r}")
            else:
                sectors.add(sector_id)
    return commodities, sectors, spatial_ids


def _check_reference(value: Any, known_ids: set[str], path: str, errors: list[str], code: str) -> None:
    if not isinstance(value, str) or not value:
        _finding(errors, code, path, "reference must be a non-empty ID")
    elif value not in known_ids:
        _finding(errors, code, path, f"unknown reference {value!r}")


def _validate_memberships(
    memberships: Any,
    path: str,
    known_sources: set[str],
    known_spatial_ids: set[str],
    errors: list[str],
) -> None:
    if not isinstance(memberships, list) or not memberships:
        _finding(errors, "ASSERTION_WITHOUT_SPATIAL_MEMBERSHIP", path, "at least one scoped spatial membership is required")
        return
    seen_spatial: set[str] = set()
    for index, membership in enumerate(memberships):
        item_path = f"{path}[{index}]"
        if not isinstance(membership, dict):
            _finding(errors, "INVALID_SPATIAL_MEMBERSHIP", item_path, "expected an object")
            continue
        spatial_id = membership.get("spatial_region_id")
        _check_reference(spatial_id, known_spatial_ids, f"{item_path}.spatial_region_id", errors, "UNKNOWN_SPATIAL_REGION_ID")
        if isinstance(spatial_id, str):
            if spatial_id in seen_spatial:
                _finding(errors, "DUPLICATE_SPATIAL_MEMBERSHIP", item_path, f"duplicate spatial ID {spatial_id!r} within assertion")
            seen_spatial.add(spatial_id)
        for field in ("coverage_bp", "relevance_bp"):
            value = membership.get(field)
            if not _is_integer(value) or not 0 <= value <= 10000:
                _finding(errors, f"INVALID_{field.upper()}", f"{item_path}.{field}", "expected an integer in the inclusive range 0..10000")
        if not _is_string(membership.get("role")):
            _finding(errors, "INVALID_SPATIAL_MEMBERSHIP", f"{item_path}.role", "role is required")
        _check_date_pair(
            membership.get("valid_from"),
            membership.get("valid_to"),
            f"{item_path}.validity",
            errors,
            nullable=False,
        )
        membership_sources = _check_source_ids(
            membership.get("source_ids"),
            f"{item_path}.source_ids",
            known_sources,
            errors,
        )
        if not membership_sources:
            _finding(errors, "MEMBERSHIP_WITHOUT_PROVENANCE", item_path, "membership provenance is required")
        if membership.get("allocation_basis") not in ALLOCATION_BASIS_VALUES:
            _finding(errors, "INVALID_ALLOCATION_BASIS", f"{item_path}.allocation_basis", f"expected one of {sorted(ALLOCATION_BASIS_VALUES)}")
        if membership.get("is_historical_measurement") is not False:
            _finding(
                errors,
                "CROSSWALK_MARKED_HISTORICAL_MEASUREMENT",
                f"{item_path}.is_historical_measurement",
                "R1 crosswalk weights must explicitly remain non-historical measurements",
            )
        if not _is_string(membership.get("notes")):
            _finding(errors, "INVALID_SPATIAL_MEMBERSHIP", f"{item_path}.notes", "membership notes are required")
        elif membership.get("allocation_basis") == "CROSSWALK_ESTIMATE" and "crosswalk" not in membership["notes"].lower():
            _finding(errors, "CROSSWALK_PROVENANCE_NOT_EXPLICIT", f"{item_path}.notes", "crosswalk estimate must be named in notes")


def _validate_assertion(
    assertion: Any,
    path: str,
    record_region_id: str,
    known_sources: set[str],
    known_commodities: set[str],
    known_sectors: set[str],
    known_spatial_ids: set[str],
    errors: list[str],
) -> tuple[str | None, set[str], set[str], int]:
    used_commodities: set[str] = set()
    used_sectors: set[str] = set()
    quantitative_count = 0
    if not isinstance(assertion, dict):
        _finding(errors, "INVALID_ASSERTION", path, "expected an object")
        return None, used_commodities, used_sectors, quantitative_count
    assertion_id = assertion.get("assertion_id")
    _check_id(assertion_id, f"{path}.assertion_id", errors)
    if assertion.get("economic_region_id") != record_region_id:
        _finding(errors, "ASSERTION_REGION_MISMATCH", f"{path}.economic_region_id", "must match containing evidence record")
    claim_kind = assertion.get("claim_kind")
    if claim_kind not in CLAIM_KINDS:
        _finding(errors, "INVALID_CLAIM_KIND", f"{path}.claim_kind", f"expected one of {sorted(CLAIM_KINDS)}")
    subject_kind = assertion.get("subject_kind")
    if subject_kind not in SUBJECT_KINDS:
        _finding(errors, "INVALID_SUBJECT_KIND", f"{path}.subject_kind", f"expected one of {sorted(SUBJECT_KINDS)}")
    subject_id = assertion.get("subject_id")
    _check_id(subject_id, f"{path}.subject_id", errors)
    if subject_kind == "COMMODITY":
        _check_reference(subject_id, known_commodities, f"{path}.subject_id", errors, "UNKNOWN_COMMODITY_REFERENCE")
        if isinstance(subject_id, str):
            used_commodities.add(subject_id)
    elif subject_kind == "SECTOR":
        _check_reference(subject_id, known_sectors, f"{path}.subject_id", errors, "UNKNOWN_SECTOR_REFERENCE")
        if isinstance(subject_id, str):
            used_sectors.add(subject_id)
    if assertion.get("claim_level") not in EVIDENCE_LEVELS:
        _finding(errors, "INVALID_EVIDENCE_LEVEL", f"{path}.claim_level", f"expected one of {sorted(EVIDENCE_LEVELS)}")
    temporal_basis = assertion.get("temporal_basis")
    if temporal_basis not in TEMPORAL_BASIS_VALUES:
        _finding(errors, "UNSUPPORTED_TEMPORAL_BASIS", f"{path}.temporal_basis", f"expected one of {sorted(TEMPORAL_BASIS_VALUES)}")
    if assertion.get("simulation_applicability") not in SIMULATION_APPLICABILITY_VALUES:
        _finding(
            errors,
            "INVALID_SIMULATION_APPLICABILITY",
            f"{path}.simulation_applicability",
            f"expected one of {sorted(SIMULATION_APPLICABILITY_VALUES)}",
        )
    _check_date_pair(
        assertion.get("observation_from"),
        assertion.get("observation_to"),
        f"{path}.observation_period",
        errors,
        nullable=True,
    )
    if not _is_string(assertion.get("observation_period_note")):
        _finding(errors, "MISSING_OBSERVATION_PERIOD_NOTE", f"{path}.observation_period_note", "observation-period qualification is required")
    source_ids = _check_source_ids(assertion.get("source_ids"), f"{path}.source_ids", known_sources, errors)
    if not source_ids:
        _finding(errors, "ASSERTION_WITHOUT_PROVENANCE", path, "every historical claim requires source_ids")
    _check_confidence(assertion.get("confidence"), f"{path}.confidence", errors)
    if not _is_string(assertion.get("notes")):
        _finding(errors, "MISSING_ASSERTION_NOTES", f"{path}.notes", "assertion notes are required")
    _validate_memberships(
        assertion.get("spatial_memberships"),
        f"{path}.spatial_memberships",
        known_sources,
        known_spatial_ids,
        errors,
    )
    output_ids = assertion.get("output_commodity_ids", [])
    if output_ids is None:
        output_ids = []
    if not isinstance(output_ids, list):
        _finding(errors, "INVALID_OUTPUT_COMMODITY_IDS", f"{path}.output_commodity_ids", "expected an array")
    else:
        for index, commodity_id in enumerate(output_ids):
            _check_reference(commodity_id, known_commodities, f"{path}.output_commodity_ids[{index}]", errors, "UNKNOWN_COMMODITY_REFERENCE")
            if isinstance(commodity_id, str):
                used_commodities.add(commodity_id)
    sector_id = assertion.get("sector_id")
    if sector_id is not None:
        _check_reference(sector_id, known_sectors, f"{path}.sector_id", errors, "UNKNOWN_SECTOR_REFERENCE")
        if isinstance(sector_id, str):
            used_sectors.add(sector_id)
    quantitative_count += _check_quantitative_evidence(
        assertion.get("quantitative_evidence"),
        f"{path}.quantitative_evidence",
        known_sources,
        errors,
    )
    return assertion_id if isinstance(assertion_id, str) else None, used_commodities, used_sectors, quantitative_count


def _validate_evidence(
    document: Any,
    known_sources: set[str],
    known_commodities: set[str],
    known_sectors: set[str],
    known_spatial_ids: set[str],
    errors: list[str],
) -> tuple[set[str], dict[str, dict[str, Any]], set[str], set[str], int]:
    region_ids: set[str] = set()
    assertions: dict[str, dict[str, Any]] = {}
    used_commodities: set[str] = set()
    used_sectors: set[str] = set()
    quantitative_count = 0
    if not isinstance(document, dict):
        _finding(errors, "INVALID_EVIDENCE_DOCUMENT", "evidence", "expected an object")
        return region_ids, assertions, used_commodities, used_sectors, quantitative_count
    if document.get("schema_id") != "wwo_economic_region_evidence_1900_r1_v2":
        _finding(errors, "INVALID_EVIDENCE_DOCUMENT", "evidence.schema_id", "unexpected schema ID")
    if document.get("schema_version") != 2:
        _finding(errors, "INVALID_EVIDENCE_DOCUMENT", "evidence.schema_version", "expected version 2")
    records = document.get("evidence_records")
    if not isinstance(records, list) or not records:
        _finding(errors, "EMPTY_EVIDENCE_RECORDS", "evidence.evidence_records", "at least one evidence record is required")
        return region_ids, assertions, used_commodities, used_sectors, quantitative_count
    legacy_fields = {
        "spatial_region_ids",
        "resource_endowments",
        "agricultural_profiles",
        "extraction_profiles",
        "industrial_profiles",
        "infrastructure_evidence",
        "population_labor_evidence",
    }
    for index, record in enumerate(records):
        path = f"evidence.evidence_records[{index}]"
        if not isinstance(record, dict):
            _finding(errors, "INVALID_EVIDENCE_RECORD", path, "expected an object")
            continue
        region_id = record.get("economic_region_id")
        _check_id(region_id, f"{path}.economic_region_id", errors)
        if isinstance(region_id, str) and region_id in region_ids:
            _finding(errors, "DUPLICATE_REGION_ID", f"{path}.economic_region_id", f"duplicate economic region ID {region_id!r}")
        if isinstance(region_id, str):
            region_ids.add(region_id)
        for legacy_field in sorted(legacy_fields.intersection(record)):
            _finding(errors, "LEGACY_UNSCOPED_ASSERTION_FIELD", f"{path}.{legacy_field}", "R1 requires assertion-scoped records")
        valid_from = _check_date(record.get("valid_from"), f"{path}.valid_from", errors)
        valid_to = _check_date(record.get("valid_to"), f"{path}.valid_to", errors)
        if valid_from is not None and valid_to is not None:
            if valid_from >= valid_to:
                _finding(errors, "INVALID_VALIDITY_INTERVAL", path, "valid_from must be earlier than valid_to")
            target_start = date(1900, 1, 1)
            if not (valid_from <= target_start < valid_to):
                _finding(errors, "INVALID_VALIDITY_INTERVAL", path, "1900 target date must be inside the half-open interval")
        _check_confidence(record.get("confidence"), f"{path}.confidence", errors)
        _check_source_ids(record.get("source_ids"), f"{path}.source_ids", known_sources, errors)
        if not _is_string(record.get("display_name")) or not _is_string(record.get("notes")):
            _finding(errors, "INVALID_EVIDENCE_RECORD", path, "display_name and notes are required")
        record_assertions = record.get("assertions")
        if not isinstance(record_assertions, list) or not record_assertions:
            _finding(errors, "MISSING_ASSERTIONS", f"{path}.assertions", "at least one assertion is required")
            continue
        for assertion_index, assertion in enumerate(record_assertions):
            assertion_path = f"{path}.assertions[{assertion_index}]"
            assertion_id, assertion_commodities, assertion_sectors, assertion_quantitative_count = _validate_assertion(
                assertion,
                assertion_path,
                region_id if isinstance(region_id, str) else "",
                known_sources,
                known_commodities,
                known_sectors,
                known_spatial_ids,
                errors,
            )
            quantitative_count += assertion_quantitative_count
            used_commodities.update(assertion_commodities)
            used_sectors.update(assertion_sectors)
            if assertion_id is not None:
                if assertion_id in assertions:
                    _finding(errors, "DUPLICATE_ASSERTION_ID", f"{assertion_path}.assertion_id", f"duplicate assertion ID {assertion_id!r}")
                else:
                    assertions[assertion_id] = assertion
    return region_ids, assertions, used_commodities, used_sectors, quantitative_count


def _validate_compatibility(
    document: Any,
    known_commodities: set[str],
    known_sectors: set[str],
    errors: list[str],
) -> tuple[int, set[str], set[str]]:
    resolved_commodities: set[str] = set()
    resolved_sectors: set[str] = set()
    if not isinstance(document, dict):
        _finding(errors, "INVALID_COMPATIBILITY_DOCUMENT", "compatibility", "expected an object")
        return 0, resolved_commodities, resolved_sectors
    if document.get("schema_id") != "wwo_economic_geography_commodity_compatibility_r1_v2":
        _finding(errors, "INVALID_COMPATIBILITY_DOCUMENT", "compatibility.schema_id", "unexpected schema ID")
    if document.get("schema_version") != 2:
        _finding(errors, "INVALID_COMPATIBILITY_DOCUMENT", "compatibility.schema_version", "expected version 2")
    concepts = document.get("concepts")
    if not isinstance(concepts, list):
        _finding(errors, "INVALID_COMPATIBILITY_DOCUMENT", "compatibility.concepts", "expected an array")
        return 0, resolved_commodities, resolved_sectors
    seen_keys: set[str] = set()
    seen_scoped_ids: set[tuple[Any, Any]] = set()
    for index, concept in enumerate(concepts):
        path = f"compatibility.concepts[{index}]"
        if not isinstance(concept, dict):
            _finding(errors, "INVALID_COMPATIBILITY_RECORD", path, "expected an object")
            continue
        concept_id = concept.get("historical_concept_id")
        compatibility_key = concept.get("compatibility_key")
        _check_id(compatibility_key, f"{path}.compatibility_key", errors)
        _check_id(concept_id, f"{path}.historical_concept_id", errors)
        kind = concept.get("concept_kind")
        if isinstance(compatibility_key, str) and compatibility_key in seen_keys:
            _finding(errors, "DUPLICATE_COMPATIBILITY_CONCEPT_ID", f"{path}.compatibility_key", f"duplicate compatibility key {compatibility_key!r}")
        if isinstance(compatibility_key, str):
            seen_keys.add(compatibility_key)
        scoped_id = (kind, concept_id)
        if scoped_id in seen_scoped_ids:
            _finding(errors, "DUPLICATE_COMPATIBILITY_CONCEPT_ID", f"{path}.historical_concept_id", f"duplicate scoped concept ID {scoped_id!r}")
        seen_scoped_ids.add(scoped_id)
        if isinstance(concept_id, str):
            if isinstance(compatibility_key, str) and compatibility_key != f"{kind}:{concept_id}":
                _finding(errors, "INVALID_COMPATIBILITY_KEY", f"{path}.compatibility_key", "key must namespace the concept kind and historical concept ID")
        status = concept.get("resolution_status")
        if status not in COMPATIBILITY_STATUS_VALUES:
            _finding(errors, "INVALID_COMPATIBILITY_STATUS", f"{path}.resolution_status", f"expected one of {sorted(COMPATIBILITY_STATUS_VALUES)}")
        if kind == "commodity":
            canonical_id = concept.get("canonical_commodity_id")
            _check_reference(canonical_id, known_commodities, f"{path}.canonical_commodity_id", errors, "UNKNOWN_COMMODITY_REFERENCE")
            if isinstance(concept_id, str) and isinstance(canonical_id, str) and canonical_id in known_commodities and status != "FUTURE_GAP_UNRESOLVED":
                resolved_commodities.add(concept_id)
        elif kind == "industrial_sector":
            canonical_id = concept.get("canonical_sector_id")
            _check_reference(canonical_id, known_sectors, f"{path}.canonical_sector_id", errors, "UNKNOWN_SECTOR_REFERENCE")
            if isinstance(concept_id, str) and isinstance(canonical_id, str) and canonical_id in known_sectors and status != "FUTURE_GAP_UNRESOLVED":
                resolved_sectors.add(concept_id)
        else:
            _finding(errors, "INVALID_COMPATIBILITY_RECORD", f"{path}.concept_kind", "unknown concept kind")
    return len(concepts), resolved_commodities, resolved_sectors


def _validate_calibration(
    document: Any,
    evidence_region_ids: set[str],
    assertions: dict[str, dict[str, Any]],
    known_commodities: set[str],
    known_sectors: set[str],
    errors: list[str],
) -> tuple[int, int]:
    if not isinstance(document, dict):
        _finding(errors, "INVALID_CALIBRATION_DOCUMENT", "calibration", "expected an object")
        return 0, 0
    if document.get("schema_id") != "wwo_economic_region_calibration_1900_r1_v2":
        _finding(errors, "INVALID_CALIBRATION_DOCUMENT", "calibration.schema_id", "unexpected schema ID")
    if document.get("schema_version") != 2:
        _finding(errors, "INVALID_CALIBRATION_DOCUMENT", "calibration.schema_version", "expected version 2")
    records = document.get("calibration_records")
    if not isinstance(records, list):
        _finding(errors, "INVALID_CALIBRATION_DOCUMENT", "calibration.calibration_records", "expected an array")
        return 0, 0
    seen: set[tuple[Any, Any, Any]] = set()
    outside_range_count = 0
    for index, record in enumerate(records):
        path = f"calibration.calibration_records[{index}]"
        if not isinstance(record, dict):
            _finding(errors, "INVALID_CALIBRATION_RECORD", path, "expected an object")
            continue
        region_id = record.get("economic_region_id")
        if region_id not in evidence_region_ids:
            _finding(errors, "UNKNOWN_CALIBRATION_REGION_ID", f"{path}.economic_region_id", f"unknown evidence region {region_id!r}")
        subject_type = record.get("subject_type")
        subject_id = record.get("commodity_or_sector_id")
        if subject_type == "COMMODITY":
            _check_reference(subject_id, known_commodities, f"{path}.commodity_or_sector_id", errors, "UNKNOWN_COMMODITY_REFERENCE")
        elif subject_type == "SECTOR":
            _check_reference(subject_id, known_sectors, f"{path}.commodity_or_sector_id", errors, "UNKNOWN_SECTOR_REFERENCE")
        else:
            _finding(errors, "INVALID_CALIBRATION_SUBJECT_TYPE", f"{path}.subject_type", "expected COMMODITY or SECTOR")
        key = (region_id, subject_type, subject_id)
        if key in seen:
            _finding(errors, "DUPLICATE_CALIBRATION_ID", path, f"duplicate calibration subject {key!r}")
        seen.add(key)
        capacities = [record.get("capacity_low"), record.get("capacity_baseline"), record.get("capacity_high")]
        if not all(_is_number(value) for value in capacities):
            _finding(errors, "INVALID_CALIBRATION_CAPACITY", path, "capacity low, baseline, and high must be numeric")
        elif not (capacities[0] <= capacities[1] <= capacities[2]):
            _finding(errors, "INVALID_CALIBRATION_CAPACITY", path, "capacity_low <= capacity_baseline <= capacity_high is required")
        unit = record.get("canonical_unit")
        if not _is_string(unit):
            _finding(errors, "INVALID_CALIBRATION_UNIT", f"{path}.canonical_unit", "canonical_unit is required")
        role = record.get("calibration_role")
        if role not in CALIBRATION_ROLES:
            _finding(errors, "INVALID_CALIBRATION_ROLE", f"{path}.calibration_role", f"expected one of {sorted(CALIBRATION_ROLES)}")
        runtime_usage = record.get("runtime_usage")
        if not _is_string(runtime_usage):
            _finding(errors, "INVALID_RUNTIME_USAGE", f"{path}.runtime_usage", "runtime_usage is required")
        source_assertion_ids = record.get("source_assertion_ids")
        if not isinstance(source_assertion_ids, list) or not source_assertion_ids:
            _finding(errors, "CALIBRATION_WITHOUT_SOURCE_ASSERTION", f"{path}.source_assertion_ids", "at least one exact assertion ID is required")
            checked_ids: list[str] = []
        else:
            checked_ids = _check_unique_string_list(source_assertion_ids, f"{path}.source_assertion_ids", errors)
            for source_index, assertion_id in enumerate(checked_ids):
                if assertion_id not in assertions:
                    _finding(errors, "UNKNOWN_SOURCE_ASSERTION_ID", f"{path}.source_assertion_ids[{source_index}]", f"unknown assertion ID {assertion_id!r}")
        if role == "DIRECT_PHYSICAL_PRODUCTION_CAPACITY" and unit == "ordinal_capacity_index_0_5":
            _finding(errors, "ORDINAL_PRIOR_AS_DIRECT_CAPACITY", path, "ordinal_capacity_index_0_5 is an evidence prior only and cannot be direct physical production capacity")
        if unit == "ordinal_capacity_index_0_5":
            if role != "EVIDENCE_PRIOR_ONLY":
                _finding(errors, "ORDINAL_PRIOR_AS_DIRECT_CAPACITY", path, "ordinal capacity must have calibration_role EVIDENCE_PRIOR_ONLY")
            if runtime_usage != "NONE":
                _finding(errors, "ORDINAL_PRIOR_RUNTIME_OUTPUT", path, "ordinal capacity must have runtime_usage NONE")
            if record.get("forbidden_runtime_uses") != [
                "TONNES",
                "WORKERS",
                "MONEY",
                "PHYSICAL_INSTALLED_CAPACITY",
                "PRODUCTION_MULTIPLIER",
                "YIELD",
                "DIRECT_RUNTIME_OUTPUT",
            ]:
                _finding(errors, "ORDINAL_PRIOR_LOCK_INCOMPLETE", path, "ordinal prior must enumerate forbidden runtime interpretations")
        if not _is_string(record.get("confidence")):
            _finding(errors, "INVALID_CALIBRATION_RECORD", f"{path}.confidence", "confidence is required")
        else:
            _check_confidence(record.get("confidence"), f"{path}.confidence", errors)
        if not _is_string(record.get("notes")):
            _finding(errors, "INVALID_CALIBRATION_RECORD", f"{path}.notes", "notes are required")
        method = record.get("calibration_method")
        if not isinstance(method, dict):
            _finding(errors, "INVALID_CALIBRATION_METHOD", f"{path}.calibration_method", "expected an object")
            method = {}
        if not _is_string(method.get("method_id")) or not _is_string(method.get("method_kind")) or not _is_string(method.get("description")):
            _finding(errors, "INVALID_CALIBRATION_METHOD", f"{path}.calibration_method", "method_id, method_kind, and description are required")
        explicit_extrapolation = method.get("explicit_extrapolation") is True
        declared_range = record.get("declared_source_assertion_range")
        range_low: float | None = None
        range_high: float | None = None
        if not isinstance(declared_range, dict):
            _finding(errors, "INVALID_DECLARED_SOURCE_RANGE", f"{path}.declared_source_assertion_range", "declared assertion range is required")
        else:
            range_low_value = declared_range.get("low")
            range_high_value = declared_range.get("high")
            if not _is_number(range_low_value) or not _is_number(range_high_value):
                _finding(errors, "INVALID_DECLARED_SOURCE_RANGE", f"{path}.declared_source_assertion_range", "low and high must be numeric")
            else:
                range_low = float(range_low_value)
                range_high = float(range_high_value)
                if range_low > range_high:
                    _finding(errors, "INVALID_DECLARED_SOURCE_RANGE", f"{path}.declared_source_assertion_range", "low must not exceed high")
            if declared_range.get("canonical_unit") != unit:
                _finding(errors, "INVALID_DECLARED_SOURCE_RANGE", f"{path}.declared_source_assertion_range.canonical_unit", "range unit must match calibration unit")
        if range_low is not None and range_high is not None and all(_is_number(value) for value in capacities):
            if float(capacities[0]) < range_low or float(capacities[2]) > range_high:
                outside_range_count += 1
                if not explicit_extrapolation or not _is_string(method.get("extrapolation_justification")):
                    _finding(errors, "CALIBRATION_OUTSIDE_DECLARED_RANGE", path, "outside declared assertion range without explicit extrapolation method and justification")
    return len(records), outside_range_count


def validate_documents(
    evidence_document: Any,
    source_document: Any,
    calibration_document: Any,
    sector_document: Any,
    compatibility_document: Any,
    commodity_document: Any,
    spatial_document: Any,
) -> dict[str, Any]:
    """Validate already-loaded documents; mutation tests use this entry point."""

    errors: list[str] = []
    known_sources = _validate_source_registry(source_document, errors)
    known_commodities, known_sectors, known_spatial_ids = _validate_catalogs(
        commodity_document, spatial_document, sector_document, errors
    )
    evidence_region_ids, assertions, used_commodities, used_sectors, quantitative_count = _validate_evidence(
        evidence_document,
        known_sources,
        known_commodities,
        known_sectors,
        known_spatial_ids,
        errors,
    )
    compatibility_count, resolved_commodities, resolved_sectors = _validate_compatibility(
        compatibility_document,
        known_commodities,
        known_sectors,
        errors,
    )
    for commodity_id in sorted(used_commodities - resolved_commodities):
        _finding(errors, "UNRESOLVED_COMPATIBILITY_REFERENCE", "evidence", f"commodity {commodity_id!r} has no compatibility resolution")
    for sector_id in sorted(used_sectors - resolved_sectors):
        _finding(errors, "UNRESOLVED_COMPATIBILITY_REFERENCE", "evidence", f"sector {sector_id!r} has no compatibility resolution")
    calibration_count, outside_range_count = _validate_calibration(
        calibration_document,
        evidence_region_ids,
        assertions,
        known_commodities,
        known_sectors,
        errors,
    )
    errors.sort()
    return {
        "valid": not errors,
        "errors": errors,
        "summary": {
            "source_count": len(known_sources),
            "commodity_count": len(known_commodities),
            "sector_count": len(known_sectors),
            "spatial_region_count": len(known_spatial_ids),
            "evidence_region_count": len(evidence_region_ids),
            "assertion_count": len(assertions),
            "calibration_record_count": calibration_count,
            "compatibility_concept_count": compatibility_count,
            "compatibility_resolved_commodity_count": len(resolved_commodities),
            "compatibility_resolved_sector_count": len(resolved_sectors),
            "historical_quantitative_value_count": quantitative_count,
            "calibrations_outside_declared_range": outside_range_count,
            "error_count": len(errors),
        },
    }


def validate_repository(root: Path = ROOT) -> dict[str, Any]:
    documents = {
        "evidence": load_json(root, EVIDENCE_PATH),
        "sources": load_json(root, SOURCE_PATH),
        "calibration": load_json(root, CALIBRATION_PATH),
        "sectors": load_json(root, SECTOR_PATH),
        "compatibility": load_json(root, COMPATIBILITY_PATH),
        "commodities": load_json(root, COMMODITY_PATH),
        "spatial": load_json(root, SPATIAL_PATH),
    }
    return validate_documents(
        documents["evidence"],
        documents["sources"],
        documents["calibration"],
        documents["sectors"],
        documents["compatibility"],
        documents["commodities"],
        documents["spatial"],
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT, help="repository root (default: this checkout)")
    args = parser.parse_args(argv)
    try:
        result = validate_repository(args.root.resolve())
    except (OSError, json.JSONDecodeError) as exc:
        print(f"ECONOMIC_GEOGRAPHY_VALIDATION: FAIL — {exc}")
        return 1
    if result["valid"]:
        payload = {"success": True, **result["summary"]}
        print("ECONOMIC_GEOGRAPHY_VALIDATION: PASS")
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0
    print("ECONOMIC_GEOGRAPHY_VALIDATION: FAIL")
    for error in result["errors"]:
        print(error)
    print(json.dumps(result["summary"], ensure_ascii=False, sort_keys=True))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
