#!/usr/bin/env python3
"""One-shot, deterministic migration of the seven economic-geography pilots to R1."""

from __future__ import annotations

import copy
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
EVIDENCE_PATH = ROOT / "data/economic_geography/evidence/economic_region_evidence_1900.json"
SOURCE_PATH = ROOT / "data/economic_geography/source_registry.json"
CALIBRATION_PATH = ROOT / "data/economic_geography/calibration/economic_region_calibration_1900.json"
COMPATIBILITY_PATH = ROOT / "data/economic_geography/commodity_compatibility.json"

SPATIAL_SOURCE = "wwo_world_admin1_natural_earth"
VALID_FROM = "1900-01-01"
VALID_TO = "1901-01-01"


def rows(
    entries: list[tuple[str, int, int, str]],
    source_ids: list[str],
    *,
    basis: str = "CROSSWALK_ESTIMATE",
) -> list[dict[str, Any]]:
    result = []
    for spatial_id, coverage_bp, relevance_bp, role in entries:
        result.append(
            {
                "spatial_region_id": spatial_id,
                "coverage_bp": coverage_bp,
                "relevance_bp": relevance_bp,
                "role": role,
                "valid_from": VALID_FROM,
                "valid_to": VALID_TO,
                "source_ids": sorted(set([SPATIAL_SOURCE, *source_ids])),
                "allocation_basis": basis,
                "is_historical_measurement": False,
                "notes": (
                    "Crosswalk estimate from the qualitative footprint to modern admin-1 IDs; "
                    "weights are not historical measurements and are not production quantities."
                    if basis == "CROSSWALK_ESTIMATE"
                    else "Unresolved historical crosswalk; modern admin-1 ID is retained as a review placeholder, not a measurement."
                ),
            }
        )
    return result


def scoped_memberships(region_id: str, claim_kind: str, subject_id: str, source_ids: list[str]) -> list[dict[str, Any]]:
    subject = subject_id.lower()
    if region_id == "economic_region_ruhr_coal_steel_1900":
        if subject in {"coal", "iron_ore", "limestone", "pig_iron", "steelmaking", "machinery"}:
            return rows([("DEU-1572", 5200, 9000, "RUHR_CORE_PROXY")], source_ids)
        if claim_kind == "INFRASTRUCTURE":
            return rows([("DEU-1572", 7000, 7600, "MINERAL_CORRIDOR_PROXY")], source_ids)
        return rows([("DEU-1572", 4200, 5200, "COEXISTING_CONTEXT")], source_ids)

    if region_id == "economic_region_lancashire_cotton_1900":
        if subject in {"cotton_textiles", "machinery", "wool_textiles"}:
            return rows([("GBR-2123", 6500, 9200, "TEXTILE_CORE_PROXY")], source_ids)
        if subject in {"coal", "coal_mining"}:
            return rows([("GBR-2123", 6500, 8500, "COALFIELD_CORE_PROXY")], source_ids)
        if claim_kind == "INFRASTRUCTURE":
            return rows([("GBR-2123", 7000, 8200, "PORT_RAIL_CANAL_SYSTEM")], source_ids)
        return rows([("GBR-2123", 5000, 5200, "COEXISTING_CONTEXT")], source_ids)

    if region_id == "economic_region_south_wales_coalfield_1900":
        industrial_core = [
            ("GBR-2131", 6500, 9300, "VALLEY_CORE_PROXY"),
            ("GBR-2114", 6500, 9300, "VALLEY_CORE_PROXY"),
            ("GBR-2115", 6200, 8800, "VALLEY_CORE_PROXY"),
            ("GBR-2118", 5200, 7600, "VALLEY_CORE_PROXY"),
            ("GBR-2119", 4800, 7000, "VALLEY_CORE_PROXY"),
            ("GBR-2116", 2600, 4800, "PORT_AND_MARKET_CONTEXT"),
            ("GBR-2117", 2400, 4200, "PORT_AND_MARKET_CONTEXT"),
        ]
        if subject in {"coal", "coal_mining", "iron_ore", "pig_iron", "steelmaking", "copper_smelting", "tinplate"}:
            return rows(industrial_core, source_ids)
        if subject == "port":
            return rows(
                [
                    ("GBR-2116", 8500, 9800, "CARDIFF_PORT_CORE"),
                    ("GBR-2117", 7800, 9000, "SWANSEA_PORT_CORE"),
                    ("GBR-2118", 5200, 6500, "PORT_CATCHMENT"),
                    ("GBR-2119", 5200, 6500, "PORT_CATCHMENT"),
                    ("GBR-2131", 1800, 2600, "VALLEY_CONTEXT"),
                    ("GBR-2114", 1800, 2600, "VALLEY_CONTEXT"),
                    ("GBR-2115", 1800, 2600, "VALLEY_CONTEXT"),
                ],
                source_ids,
            )
        if claim_kind == "INFRASTRUCTURE":
            return rows(
                [(spatial_id, 4000, 6200, "VALLEY_CONNECTIVITY_PROXY") for spatial_id in [
                    "GBR-2131", "GBR-2114", "GBR-2115", "GBR-2116", "GBR-2117", "GBR-2118", "GBR-2119"
                ]],
                source_ids,
            )
        return rows(industrial_core, source_ids)

    if region_id == "economic_region_donbas_coal_metals_1900":
        if subject in {"coal", "coal_mining"}:
            return rows(
                [
                    ("UKR-327", 6200, 9500, "DONETS_COAL_CORE_PROXY"),
                    ("UKR-329", 6800, 9200, "DONETS_COAL_CORE_PROXY"),
                    ("RUS-2367", 1500, 2800, "CROSS_BORDER_CONTEXT"),
                ],
                source_ids,
            )
        if subject in {"iron_ore", "pig_iron", "steelmaking"}:
            return rows(
                [
                    ("UKR-327", 5200, 8500, "METALS_CORE_PROXY"),
                    ("UKR-329", 5200, 8200, "METALS_CORE_PROXY"),
                    ("RUS-2367", 1200, 2600, "AZOV_CONTEXT"),
                ],
                source_ids,
            )
        if subject == "port":
            return rows(
                [
                    ("RUS-2367", 6000, 9000, "AZOV_PORT_CONTEXT"),
                    ("UKR-327", 1800, 3000, "BASIN_CONNECTION"),
                    ("UKR-329", 1800, 3000, "BASIN_CONNECTION"),
                ],
                source_ids,
            )
        if claim_kind == "INFRASTRUCTURE":
            return rows(
                [
                    ("UKR-327", 4500, 7000, "BASIN_CONNECTIVITY_PROXY"),
                    ("UKR-329", 4500, 7000, "BASIN_CONNECTIVITY_PROXY"),
                    ("RUS-2367", 3500, 6500, "AZOV_CONNECTIVITY_PROXY"),
                ],
                source_ids,
            )
        return rows(
            [
                ("UKR-327", 3500, 5000, "BASIN_CONTEXT"),
                ("UKR-329", 3500, 5000, "BASIN_CONTEXT"),
                ("RUS-2367", 3000, 4000, "CROSS_BORDER_CONTEXT"),
            ],
            source_ids,
        )

    if region_id == "economic_region_pennsylvania_coal_steel_1900":
        return rows([("USA-3560", 10000, 10000, "STATE_LEVEL_PROXY")], source_ids)

    if region_id == "economic_region_bengal_delta_jute_rice_1900":
        delta = [
            ("BGD-1806", 7200, 8600, "EASTERN_DELTA_CORE"),
            ("BGD-2432", 7600, 9100, "EASTERN_DELTA_CORE"),
            ("BGD-3255", 7600, 9000, "EASTERN_DELTA_CORE"),
            ("IND-3257", 4600, 6800, "CALCUTTA_AND_WESTERN_CONTEXT"),
        ]
        if subject in {"jute", "rice", "tea", "agricultural_labor_base"}:
            if subject == "tea":
                return rows(
                    [("IND-3257", 2800, 2600, "PLANTATION_CONTEXT"), *[(sid, 700, 800, "DELTA_CONTEXT") for sid in ["BGD-1806", "BGD-2432", "BGD-3255"]]],
                    source_ids,
                )
            return rows(delta, source_ids)
        if subject in {"jute_textiles", "port", "port_commerce_labor"}:
            return rows(
                [
                    ("IND-3257", 9000, 10000, "CALCUTTA_MILL_PORT_CORE"),
                    ("BGD-1806", 3200, 5000, "JUTE_FEED_CATCHMENT"),
                    ("BGD-2432", 3600, 5600, "JUTE_FEED_CATCHMENT"),
                    ("BGD-3255", 3600, 5600, "JUTE_FEED_CATCHMENT"),
                ],
                source_ids,
            )
        if subject == "coal":
            return rows(
                [("IND-3257", 1200, 2400, "UNRESOLVED_COALFIELD_CONTEXT")],
                source_ids,
                basis="UNRESOLVED",
            )
        if claim_kind == "INFRASTRUCTURE":
            return rows(
                [
                    ("IND-3257", 8500, 9000, "CALCUTTA_PORT_RAIL_NODE"),
                    ("BGD-1806", 4500, 6500, "DELTA_WATERWAY_CONTEXT"),
                    ("BGD-2432", 4500, 6500, "DELTA_WATERWAY_CONTEXT"),
                    ("BGD-3255", 4500, 6500, "DELTA_WATERWAY_CONTEXT"),
                ],
                source_ids,
            )
        return rows(delta, source_ids)

    if region_id == "economic_region_lower_yangtze_silk_port_1900":
        if subject in {"raw_silk", "rice", "raw_cotton", "tea", "agricultural_labor_base"}:
            return rows(
                [("CHN-1818", 9000, 9300, "JIANGSU_PRODUCTION_CORE"), ("CHN-1819", 5000, 6000, "SHANGHAI_TRADE_CONTEXT")],
                source_ids,
            )
        if subject in {"silk_textiles", "cotton_textiles", "food_processing", "shipbuilding", "port", "port_commerce_labor"}:
            return rows(
                [("CHN-1819", 9500, 10000, "SHANGHAI_PORT_INDUSTRIAL_CORE"), ("CHN-1818", 5200, 6200, "LOWER_YANGTZE_CATCHMENT")],
                source_ids,
            )
        if claim_kind == "INFRASTRUCTURE":
            return rows(
                [("CHN-1818", 8000, 8200, "RIVER_CANAL_RAIL_CATCHMENT"), ("CHN-1819", 8500, 8800, "PORT_RIVER_NODE")],
                source_ids,
            )
        return rows(
            [("CHN-1818", 5000, 3600, "LOCAL_RESOURCE_CONTEXT"), ("CHN-1819", 1200, 1000, "PORT_CONTEXT")],
            source_ids,
        )

    raise ValueError(f"unhandled pilot region {region_id}")


def temporal_fields(source_ids: list[str]) -> tuple[str, str | None, str | None, str]:
    if "us_census_1900_manufactures_iron_steel" in source_ids:
        return (
            "DIRECT_1900",
            "1900-01-01",
            "1901-01-01",
            "The official report concerns the Twelfth Census taken in 1900; publication in 1902 is not used as the observation date.",
        )
    if "us_census_1900_mines_quarries" in source_ids:
        return (
            "NEAR_1900",
            "1902-01-01",
            "1903-01-01",
            "The official locator presents mines-and-quarries statistics for 1902; it is near-period evidence, not a direct 1900 observation.",
        )
    if any(source_id.startswith("eb1911_") for source_id in source_ids):
        return (
            "RETROSPECTIVE_BUT_APPLICABLE",
            None,
            None,
            "The 1911 reference is a retrospective structural description; no bounded observation year is silently inferred from publication date.",
        )
    return (
        "TEMPORALLY_WEAK",
        None,
        None,
        "No bounded observation period was established; retain only as a qualified structural lead.",
    )


def convert_assertion(
    record: dict[str, Any],
    category: str,
    item: dict[str, Any],
) -> dict[str, Any]:
    claim_kind = {
        "resource_endowments": "RESOURCE_ENDOWMENT",
        "agricultural_profiles": "AGRICULTURAL_PROFILE",
        "extraction_profiles": "EXTRACTION_PROFILE",
        "industrial_profiles": "INDUSTRIAL_PROFILE",
        "infrastructure_evidence": "INFRASTRUCTURE",
        "population_labor_evidence": "POPULATION_LABOR",
    }[category]
    if category in {"resource_endowments", "agricultural_profiles", "extraction_profiles"}:
        subject_kind = "COMMODITY"
        subject_id = item["commodity_id"]
    elif category == "industrial_profiles":
        subject_kind = "SECTOR"
        subject_id = item["sector_id"]
    elif category == "infrastructure_evidence":
        subject_kind = "INFRASTRUCTURE"
        subject_id = item["infrastructure_type"].lower()
    else:
        subject_kind = "POPULATION_LABOR"
        subject_id = item["population_labor_type"].lower()

    source_ids = list(item["source_ids"])
    region_id = record["economic_region_id"]
    correction_note = ""
    if region_id == "economic_region_ruhr_coal_steel_1900" and category == "resource_endowments" and subject_id == "coal":
        source_ids = [source_id for source_id in source_ids if source_id != "eb1911_russia"]
        correction_note = " Unrelated eb1911_russia provenance was removed from this Ruhr assertion."
    if region_id == "economic_region_pennsylvania_coal_steel_1900" and category == "industrial_profiles" and subject_id == "machinery":
        source_ids = ["eb1911_pittsburg"]
        correction_note = " The mines-and-quarries source mismatch was removed; machinery is retained only with the Pittsburg reference."

    temporal_basis, observation_from, observation_to, observation_note = temporal_fields(source_ids)
    assertion_id = f"{region_id}__{category.removesuffix('_evidence').removesuffix('_profiles').removesuffix('_endowments')}__{subject_id}"
    assertion: dict[str, Any] = {
        "assertion_id": assertion_id,
        "economic_region_id": region_id,
        "claim_kind": claim_kind,
        "subject_kind": subject_kind,
        "subject_id": subject_id,
        "claim_level": item["evidence_level"],
        "spatial_memberships": scoped_memberships(region_id, claim_kind, subject_id, source_ids),
        "temporal_basis": temporal_basis,
        "observation_from": observation_from,
        "observation_to": observation_to,
        "observation_period_note": observation_note,
        "simulation_applicability": {
            "DIRECT_1900": "DIRECT_1900_STRUCTURAL_ONLY",
            "NEAR_1900": "NEAR_1900_STRUCTURAL_ONLY",
            "RETROSPECTIVE_BUT_APPLICABLE": "RETROSPECTIVE_1900_STRUCTURAL_ONLY",
            "TEMPORALLY_WEAK": "NOT_FOR_QUANTITATIVE_CALIBRATION",
        }[temporal_basis],
        "source_ids": source_ids,
        "confidence": item["confidence"],
        "notes": item["notes"] + correction_note,
    }
    if "role" in item:
        assertion["role"] = item["role"]
    if "importance" in item:
        assertion["importance"] = item["importance"]
    if "sector_id" in item:
        assertion["sector_id"] = item["sector_id"]
    if "output_commodity_ids" in item:
        assertion["output_commodity_ids"] = list(item["output_commodity_ids"])
    if category == "infrastructure_evidence":
        assertion["infrastructure_type"] = item["infrastructure_type"]
    if category == "population_labor_evidence":
        assertion["population_labor_type"] = item["population_labor_type"]
    if subject_id == "silk_textiles":
        assertion["notes"] += " Canonical raw_silk is a process/output proxy only; no observed silk-output quantity is asserted."
    return assertion


def migrate_evidence(document: dict[str, Any]) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    categories = [
        "resource_endowments",
        "agricultural_profiles",
        "extraction_profiles",
        "industrial_profiles",
        "infrastructure_evidence",
        "population_labor_evidence",
    ]
    records = []
    assertions_by_subject: dict[str, dict[str, Any]] = {}
    for old_record in document["evidence_records"]:
        record = {
            "economic_region_id": old_record["economic_region_id"],
            "display_name": old_record["display_name"],
            "region_kind": old_record["region_kind"],
            "valid_from": old_record["valid_from"],
            "valid_to": old_record["valid_to"],
            "confidence": old_record["confidence"],
            "source_ids": list(old_record["source_ids"]),
            "assertions": [],
            "notes": old_record["notes"],
        }
        if record["economic_region_id"] == "economic_region_ruhr_coal_steel_1900":
            record["source_ids"] = [source_id for source_id in record["source_ids"] if source_id != "eb1911_russia"]
            record["notes"] += " R1 correction: unrelated Russia provenance is not retained for the Ruhr coal claim."
        skipped = []
        for category in categories:
            for item in old_record.get(category, []):
                subject = item.get("sector_id") or item.get("commodity_id") or item.get("infrastructure_type") or item.get("population_labor_type")
                region_id = record["economic_region_id"]
                if region_id in {
                    "economic_region_ruhr_coal_steel_1900",
                    "economic_region_donbas_coal_metals_1900",
                } and category == "industrial_profiles" and subject == "coke_production":
                    skipped.append("unsupported coke_production assertion")
                    continue
                if region_id == "economic_region_south_wales_coalfield_1900" and category in {"resource_endowments", "extraction_profiles"} and (item.get("commodity_id") == "copper_ore" or item.get("sector_id") == "copper_mining"):
                    skipped.append("unsupported local copper_ore extraction assertion")
                    continue
                if region_id == "economic_region_bengal_delta_jute_rice_1900" and category == "industrial_profiles" and subject == "food_processing":
                    skipped.append("unsupported food_processing assertion")
                    continue
                assertion = convert_assertion(record, category, item)
                record["assertions"].append(assertion)
                assertions_by_subject[f"{region_id}:{category}:{assertion['subject_id']}"] = assertion
        if skipped:
            record["notes"] += " R1 corrections removed: " + "; ".join(skipped) + "."
        records.append(record)
    return {
        "schema_id": "wwo_economic_region_evidence_1900_r1_v2",
        "schema_version": 2,
        "target_year": 1900,
        "evidence_records": records,
    }, assertions_by_subject


def migrate_sources(document: dict[str, Any]) -> dict[str, Any]:
    result = {"schema_id": "wwo_economic_geography_source_registry_r1_v2", "schema_version": 2, "sources": []}
    for old_source in document["sources"]:
        source = {key: value for key, value in old_source.items() if key not in {"source_type"}}
        source_class = (
            "MODERN_SPATIAL_REFERENCE"
            if old_source["source_id"] == SPATIAL_SOURCE
            else "INTERNAL_PROJECT_CATALOG"
            if old_source["source_id"] == "wwo_canonical_commodity_catalog_1900"
            else "PRIMARY_OFFICIAL_STATISTICS"
            if old_source["source_id"].startswith("us_census_1900_")
            else "CONTEMPORARY_REFERENCE"
            if old_source["source_id"].startswith("eb1911_")
            else "OTHER"
        )
        source["source_class"] = source_class
        if old_source["source_id"] == "us_census_1900_manufactures_iron_steel":
            source["observation_from"] = "1900-01-01"
            source["observation_to"] = "1901-01-01"
            source["observation_period_notes"] = "Twelfth Census was taken in 1900; this report was published in 1902."
        elif old_source["source_id"] == "us_census_1900_mines_quarries":
            source["observation_from"] = "1902-01-01"
            source["observation_to"] = "1903-01-01"
            source["observation_period_notes"] = "The official locator identifies statistics for mines and quarries for 1902; this is not a direct 1900 observation."
        else:
            source["observation_from"] = None
            source["observation_to"] = None
            source["observation_period_notes"] = "No bounded observation period is extracted from this locator; publication date is not an observation date."
        result["sources"].append(source)
    return result


def migrate_compatibility(document: dict[str, Any], evidence: dict[str, Any]) -> dict[str, Any]:
    concepts: list[dict[str, Any]] = []
    seen_keys: set[str] = set()
    for old_concept in document["concepts"]:
        kind = old_concept["concept_kind"]
        historical_id = old_concept["historical_concept_id"]
        key = f"{kind}:{historical_id}"
        migrated = {
            "compatibility_key": key,
            "historical_concept_id": historical_id,
            "concept_kind": kind,
            "mapping_status": old_concept["mapping_status"],
            "resolution_status": "CANONICAL_DIRECT" if kind == "commodity" else "SECTOR_ONLY",
            "notes": old_concept.get("difference_note", "") + " Namespaced compatibility key prevents commodity/sector identity collisions.",
        }
        if kind == "commodity":
            migrated["canonical_commodity_id"] = old_concept["canonical_commodity_id"]
        else:
            migrated["canonical_sector_id"] = old_concept["canonical_sector_id"]
        concepts.append(migrated)
        seen_keys.add(key)

    used_sector_ids: set[str] = set()
    for record in evidence["evidence_records"]:
        for assertion in record["assertions"]:
            if assertion["subject_kind"] == "SECTOR":
                used_sector_ids.add(assertion["subject_id"])
            if "sector_id" in assertion:
                used_sector_ids.add(assertion["sector_id"])
    used_commodity_ids = {
        assertion["subject_id"]
        for record in evidence["evidence_records"]
        for assertion in record["assertions"]
        if assertion["subject_kind"] == "COMMODITY"
    }
    used_commodity_ids.update(
        commodity_id
        for record in evidence["evidence_records"]
        for assertion in record["assertions"]
        for commodity_id in assertion.get("output_commodity_ids", [])
    )
    for commodity_id in sorted(used_commodity_ids):
        key = f"commodity:{commodity_id}"
        if key not in seen_keys:
            concepts.append(
                {
                    "compatibility_key": key,
                    "historical_concept_id": commodity_id,
                    "concept_kind": "commodity",
                    "canonical_commodity_id": commodity_id,
                    "mapping_status": "DIRECT",
                    "resolution_status": "CANONICAL_DIRECT",
                    "notes": "Existing canonical commodity identity resolves this pilot reference; no duplicate commodity identity is created.",
                }
            )
            seen_keys.add(key)
    for sector_id in sorted(used_sector_ids):
        key = f"industrial_sector:{sector_id}"
        if key not in seen_keys:
            concepts.append(
                {
                    "compatibility_key": key,
                    "historical_concept_id": sector_id,
                    "concept_kind": "industrial_sector",
                    "canonical_sector_id": sector_id,
                    "mapping_status": "SECTOR_ONLY",
                    "resolution_status": "SECTOR_ONLY",
                    "notes": "Sector-scoped identity resolves through the existing sector catalog; it is not a commodity alias or production quantity.",
                }
            )
            seen_keys.add(key)
    concepts.sort(key=lambda concept: concept["compatibility_key"])
    return {
        "schema_id": "wwo_economic_geography_commodity_compatibility_r1_v2",
        "schema_version": 2,
        "concepts": concepts,
    }


def migrate_calibration(document: dict[str, Any], evidence: dict[str, Any]) -> dict[str, Any]:
    assertion_map = {
        "economic_region_ruhr_coal_steel_1900": "economic_region_ruhr_coal_steel_1900__resource__coal",
        "economic_region_lancashire_cotton_1900": "economic_region_lancashire_cotton_1900__industrial__cotton_textiles",
        "economic_region_south_wales_coalfield_1900": "economic_region_south_wales_coalfield_1900__resource__coal",
        "economic_region_donbas_coal_metals_1900": "economic_region_donbas_coal_metals_1900__resource__coal",
        "economic_region_pennsylvania_coal_steel_1900": "economic_region_pennsylvania_coal_steel_1900__industrial__steelmaking",
        "economic_region_bengal_delta_jute_rice_1900": "economic_region_bengal_delta_jute_rice_1900__industrial__jute_textiles",
        "economic_region_lower_yangtze_silk_port_1900": "economic_region_lower_yangtze_silk_port_1900__industrial__silk_textiles",
    }
    records = []
    for old_record in document["calibration_records"]:
        record = copy.deepcopy(old_record)
        record.pop("source_evidence_ids", None)
        record["source_assertion_ids"] = [assertion_map[record["economic_region_id"]]]
        record.pop("declared_source_evidence_range", None)
        record["declared_source_assertion_range"] = {
            "low": 0.0,
            "high": 5.0,
            "canonical_unit": "ordinal_capacity_index_0_5",
        }
        record["calibration_role"] = "EVIDENCE_PRIOR_ONLY"
        record["runtime_usage"] = "NONE"
        record["forbidden_runtime_uses"] = [
            "TONNES",
            "WORKERS",
            "MONEY",
            "PHYSICAL_INSTALLED_CAPACITY",
            "PRODUCTION_MULTIPLIER",
            "YIELD",
            "DIRECT_RUNTIME_OUTPUT",
        ]
        record["notes"] += " R1 lock: ordinal_capacity_index_0_5 is evidence-prior-only and cannot become tonnes, workers, money, physical installed capacity, a production multiplier, yield, or direct runtime output."
        record["calibration_method"]["description"] = "Illustrative mapping of qualitative evidence into a bounded 0-5 prior; it is not a historical quantity conversion."
        records.append(record)
    return {
        "schema_id": "wwo_economic_region_calibration_1900_r1_v2",
        "schema_version": 2,
        "target_year": 1900,
        "calibration_notice": "All current records are EVIDENCE_PRIOR_ONLY. ordinal_capacity_index_0_5 is a bounded qualitative prior and is forbidden from representing tonnes, workers, money, physical installed capacity, production multipliers, yield, or direct runtime output.",
        "calibration_records": records,
    }


def write_json(path: Path, document: dict[str, Any]) -> None:
    path.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    old_evidence = json.loads(EVIDENCE_PATH.read_text(encoding="utf-8"))
    old_sources = json.loads(SOURCE_PATH.read_text(encoding="utf-8"))
    old_calibration = json.loads(CALIBRATION_PATH.read_text(encoding="utf-8"))
    old_compatibility = json.loads(COMPATIBILITY_PATH.read_text(encoding="utf-8"))
    evidence, _ = migrate_evidence(old_evidence)
    write_json(EVIDENCE_PATH, evidence)
    write_json(SOURCE_PATH, migrate_sources(old_sources))
    write_json(COMPATIBILITY_PATH, migrate_compatibility(old_compatibility, evidence))
    write_json(CALIBRATION_PATH, migrate_calibration(old_calibration, evidence))
    print(f"migrated {len(evidence['evidence_records'])} evidence records")
    print(f"migrated {sum(len(record['assertions']) for record in evidence['evidence_records'])} assertions")


if __name__ == "__main__":
    main()
