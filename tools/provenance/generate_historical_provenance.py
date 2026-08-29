#!/usr/bin/env python3
"""Build deterministic provenance metadata from the three admitted source files.

This transforms no historical values. It records hashes and evidence bindings for
the existing political identity, aggregate population, and boundary-source facts.
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
CHECKPOINT = "c41f07f50ac355b8c85b961cd3d633fa17f37ba9"
POLITICAL_PATH = "res://data/world_map/historical/political_units_1900.json"
SPATIAL_PATH = "res://data/world_map/historical/cshapes_1900_snapshot.json"
POPULATION_PATH = "res://data/alpha/historical_world_economy_1900/countries_compact.json"
POPULATION_MANIFEST_PATH = "res://data/alpha/historical_world_economy_1900.json"
GENERATOR = "tools/provenance/generate_historical_provenance.py:v1"


def local_path(resource_path: str) -> Path:
    return ROOT / resource_path.removeprefix("res://")


def read_json(resource_path: str) -> dict[str, Any]:
    return json.loads(local_path(resource_path).read_text(encoding="utf-8"))


def file_sha256(resource_path: str) -> str:
    return hashlib.sha256(local_path(resource_path).read_bytes()).hexdigest()


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def value_sha256(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def assertion(
    subject_id: str,
    value: Any,
    unit: str,
    observation_period: dict[str, str],
    spatial_scope: dict[str, str],
    lower_bound: Any = None,
    upper_bound: Any = None,
) -> dict[str, Any]:
    return {
        "lower_bound": lower_bound,
        "observation_period": observation_period,
        "spatial_scope": spatial_scope,
        "subject_id": subject_id,
        "unit": unit,
        "upper_bound": upper_bound,
        "value": value,
    }


def evidence(
    *,
    fact_id: str,
    domain: str,
    source: dict[str, Any],
    runtime_assertion: dict[str, Any],
    methodology: str,
    confidence: float,
    review_status: str,
) -> dict[str, Any]:
    return {
        "fact_id": fact_id,
        "domain": domain,
        "subject_id": runtime_assertion["subject_id"],
        "value": runtime_assertion["value"],
        "unit": runtime_assertion["unit"],
        "source_id": source["source_id"],
        "source_version": source["version"],
        "source_locator": source["locator"],
        "observation_period": runtime_assertion["observation_period"],
        "spatial_scope": runtime_assertion["spatial_scope"],
        "methodology": methodology,
        "confidence": confidence,
        "lower_bound": runtime_assertion["lower_bound"],
        "upper_bound": runtime_assertion["upper_bound"],
        "license": source["license"],
        "review_status": review_status,
        "generator": GENERATOR,
        "input_hash": source["content_hash"],
        "output_hash": value_sha256(runtime_assertion),
    }


def build() -> tuple[dict[str, Any], dict[str, Any]]:
    political = read_json(POLITICAL_PATH)
    spatial = read_json(SPATIAL_PATH)
    population = read_json(POPULATION_PATH)
    population_manifest = read_json(POPULATION_MANIFEST_PATH)

    political_source = {
        "source_id": "wwo-political-identities-1900-v1",
        "title": "WWO dated political identity catalog for 1900",
        "publisher": "WWO repository; normalized from CShapes 2.0",
        "version": "political_units_1900.schema_version=1",
        "license": "CC BY-NC-SA 4.0; repository transformation terms apply",
        "locator": POLITICAL_PATH,
        "access_metadata": {
            "checkpoint": CHECKPOINT,
            "upstream_source_id": "src-cshapes-2.0",
            "snapshot_date": political["snapshot_date"],
        },
        "content_hash": file_sha256(POLITICAL_PATH),
    }
    spatial_source = {
        "source_id": "cshapes-2.0-wwo-snapshot-1900",
        "title": "CShapes 2.0 transformed WWO boundary snapshot",
        "publisher": "ETH Zürich ICR; repository transformation by WWO",
        "version": "2.0 / snapshot schema_version=1",
        "license": spatial["source"]["license"],
        "locator": SPATIAL_PATH,
        "access_metadata": {
            "checkpoint": CHECKPOINT,
            "source_page": spatial["source"]["source_page"],
            "upstream_content_hash": spatial["source"]["source_sha256"],
            "snapshot_date": spatial["snapshot_date"],
        },
        "content_hash": file_sha256(SPATIAL_PATH),
    }
    population_source = {
        "source_id": "wwo-population-aggregate-estimates-1900-v1",
        "title": "WWO bounded 1900 population aggregate estimate table",
        "publisher": "WWO repository; derived compilation",
        "version": population["schema_id"],
        "license": "Mixed upstream terms; see the linked WWO source manifest",
        "locator": POPULATION_PATH,
        "access_metadata": {
            "checkpoint": CHECKPOINT,
            "manifest": POPULATION_MANIFEST_PATH,
            "source_ids": sorted(
                item["source_id"] for item in population_manifest["source_manifest"]
            ),
        },
        "content_hash": file_sha256(POPULATION_PATH),
    }
    sources = sorted(
        [political_source, spatial_source, population_source],
        key=lambda item: item["source_id"],
    )

    facts: list[dict[str, Any]] = []
    for unit in sorted(political["units"], key=lambda item: item["id"]):
        identity_value = {
            "controller_id": unit["controller_id"],
            "geometry_feature_id": unit["geometry_feature_id"],
            "id": unit["id"],
            "relationship": unit["relationship"],
            "source_name": unit["source_name"],
            "status": unit["status"],
            "valid_from": unit["valid_from"],
            "valid_to": unit["valid_to"],
        }
        runtime_assertion = assertion(
            unit["id"],
            identity_value,
            "identity_record",
            {"from": unit["valid_from"], "to": unit["valid_to"]},
            {"kind": "political_unit", "id": unit["id"]},
        )
        facts.append(
            evidence(
                fact_id=f"political_identity:{unit['id']}",
                domain="political_identity",
                source=political_source,
                runtime_assertion=runtime_assertion,
                methodology=(
                    "Dated CShapes entity crosswalk plus repository identity "
                    "normalization; modern geometry fallback is forbidden."
                ),
                confidence=0.8,
                review_status="EVIDENCE_LINKED",
            )
        )

    spatial_value = {
        "feature_count": spatial["feature_count"],
        "provider": spatial["provider"],
        "snapshot_date": spatial["snapshot_date"],
        "upstream_content_hash": spatial["source"]["source_sha256"],
    }
    spatial_assertion = assertion(
        "world_boundaries_1900_03_12",
        spatial_value,
        "boundary_snapshot",
        {"from": spatial["snapshot_date"], "to": spatial["snapshot_date"]},
        {"kind": "global_boundary_snapshot", "id": "world"},
    )
    facts.append(
        evidence(
            fact_id="spatial_boundary:world_boundaries_1900_03_12",
            domain="spatial_boundary",
            source=spatial_source,
            runtime_assertion=spatial_assertion,
            methodology=spatial["source"]["selection_rule"],
            confidence=0.9,
            review_status="EVIDENCE_LINKED",
        )
    )

    indexes = {name: index for index, name in enumerate(population["field_order"])}
    method = population["common_methods"]["population"]
    date = population_manifest["calibration_date"]
    for row in sorted(population["rows"], key=lambda item: item[indexes["entity_id"]]):
        entity_id = row[indexes["entity_id"]]
        unit_id = f"population:{entity_id}"
        runtime_assertion = assertion(
            unit_id,
            row[indexes["population_value"]],
            "persons",
            {"from": date, "to": date},
            {"kind": "major_economy_aggregate", "id": entity_id},
            row[indexes["population_lower"]],
            row[indexes["population_upper"]],
        )
        facts.append(
            evidence(
                fact_id=f"population_aggregate:{unit_id}",
                domain="population_aggregate",
                source=population_source,
                runtime_assertion=runtime_assertion,
                methodology=method,
                confidence=row[indexes["population_confidence_bp"]] / 10_000.0,
                review_status="BOUNDED_ESTIMATE",
            )
        )

    facts.sort(key=lambda item: item["fact_id"])
    registry = {"schema_id": "historical_source_registry_v1", "sources": sources}
    catalog = {"schema_id": "historical_fact_evidence_catalog_v1", "facts": facts}
    return registry, catalog


def main() -> None:
    registry, catalog = build()
    output_dir = ROOT / "data" / "provenance"
    if "--check" in sys.argv[1:]:
        expected_registry = json.loads(
            (output_dir / "historical_source_registry.json").read_text(encoding="utf-8")
        )
        expected_catalog = json.loads(
            (output_dir / "historical_fact_evidence.json").read_text(encoding="utf-8")
        )
        if registry != expected_registry or catalog != expected_catalog:
            raise SystemExit("historical provenance catalogs are not deterministic/current")
        print(
            "Historical provenance catalogs deterministic: "
            f"{len(registry['sources'])} sources, {len(catalog['facts'])} facts"
        )
        return
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "historical_source_registry.json").write_text(
        json.dumps(registry, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (output_dir / "historical_fact_evidence.json").write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
