#!/usr/bin/env python3
"""Generate the formal evidence catalog from base content and admitted supplements.

Schema IDs express format compatibility. Internal JSON is compared as data;
checksums in upstream metadata describe only the original external artifact.
"""

from __future__ import annotations

from datetime import date
import math
import json
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
POLITICAL_PATH = "res://data/world_map/historical/political_units_1900.json"
SPATIAL_PATH = "res://data/world_map/historical/cshapes_1900_snapshot.json"
POPULATION_PATH = "res://data/alpha/historical_world_economy_1900/countries_compact.json"
POPULATION_MANIFEST_PATH = "res://data/alpha/historical_world_economy_1900.json"
GENERATOR = "tools/provenance/generate_historical_provenance.py:v2"
FRANCE_ADMIN_PATH = "res://data/world_map/historical/france_administrative_identity_1900.json"
SUPPLEMENTS = (
    ("arabia_gulf_geography_1900.json", "arabia_gulf_geography_1900_01_01", "spatial_boundary", "M2.6-v1"),
    ("historical_authorities_1900.json", "map_authorities_1900_01_01", "administrative_authority", "M2.6-v1"),
    ("arabia_authority_coverage_1900.json", "arabia_authority_coverage_1900_01_01", "administrative_authority", "M2.6.2-v1"),
)


class ProvenanceSourceContractError(RuntimeError):
    """Raised for unsupported formats or invalid historical content."""


def local_path(resource_path: str) -> Path:
    return ROOT / resource_path.removeprefix("res://")


def read_json(resource_path: str) -> dict[str, Any]:
    document = json.loads(local_path(resource_path).read_text(encoding="utf-8"))
    if not isinstance(document, dict):
        raise ProvenanceSourceContractError(f"expected JSON object: {resource_path}")
    return document


def require_schema(document: dict, field: str, supported: Any) -> None:
    if document.get(field) != supported:
        raise ProvenanceSourceContractError(f"unsupported {field}: {document.get(field)!r}; expected {supported!r}")


def unique_records(records: list, field: str) -> set[str]:
    ids = [record[field] for record in records]
    if any(not isinstance(item, str) or not item for item in ids) or len(ids) != len(set(ids)):
        raise ProvenanceSourceContractError(f"empty/duplicate {field}")
    return set(ids)


def valid_period(start: str, end: str) -> None:
    if date.fromisoformat(start).isoformat() != start or date.fromisoformat(end).isoformat() != end or start > end:
        raise ProvenanceSourceContractError(f"invalid date period: {start} / {end}")


def validate_geometry(features: list) -> None:
    unique_records(features, "id")
    for feature in features:
        geometry = feature["geometry"]
        if geometry["type"] not in ("Polygon", "MultiPolygon"):
            raise ProvenanceSourceContractError("unsupported geometry type")
        polygons = [geometry["coordinates"]] if geometry["type"] == "Polygon" else geometry["coordinates"]
        if not polygons:
            raise ProvenanceSourceContractError("empty geometry")
        for polygon in polygons:
            if not polygon:
                raise ProvenanceSourceContractError("missing exterior ring")
            for ring in polygon:
                if len(ring) < 4 or ring[0] != ring[-1]:
                    raise ProvenanceSourceContractError("invalid or unclosed geometry ring")
                for point in ring:
                    if len(point) != 2 or any(type(value) not in (int, float) or not math.isfinite(value) for value in point) or not -180 <= point[0] <= 180 or not -90 <= point[1] <= 90:
                        raise ProvenanceSourceContractError("invalid longitude/latitude")


def supplement_value(document: dict, domain: str) -> dict:
    value = {"target_date": document["target_date"]}
    if domain == "spatial_boundary":
        value.update(feature_count=document["feature_count"], features=document["features"])
    else:
        value.update(assignment_count=len(document["assignments"]), assignments=document["assignments"])
        for field in ("geometry_binding", "map_display_records", "unresolved_regions"):
            if field in document:
                value[field] = document[field]
    return value


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


def validate_france_administrative_identity(document: dict, political_ids: set[str], place_ids: set[str]) -> None:
    require_schema(document, "schema_id", "france_administrative_identity_r1")
    valid_period(document["valid_from"], document["valid_to"])
    if not document["valid_from"] <= document["target_date"] < document["valid_to"]:
        raise ProvenanceSourceContractError("administrative evidence date outside coverage")
    if document["entity_id"] not in political_ids or document["coverage_status"] != "PARTIAL_IDENTITY_ONLY" or document["geometry_status"] != "ADMIN_BOUNDARY_DATA_GAP" or document["membership_status"] != "BLOCKED_SPATIAL_MODEL":
        raise ProvenanceSourceContractError("unsupported administrative evidence scope")
    source_ids = unique_records(document["sources"], "source_id")
    unique_records(document["units"], "id")
    if not document["units"]:
        raise ProvenanceSourceContractError("empty administrative identity evidence")
    for unit in document["units"]:
        if not unit["id"].startswith("administrative_region:") or unit["polity_id"] != "state:" + document["entity_id"] or unit["unit_type"] != "departement" or type(unit["level"]) is not int or unit["level"] != 1 or unit["parent_region_id"] is not None:
            raise ProvenanceSourceContractError("invalid administrative identity/type/level")
        if not unit["historical_name"] or not unit["name_zh"] or not unit["capital_name"] or not unit["identity_locator"] or not unit["source_ids"] or not set(unit["source_ids"]) <= source_ids:
            raise ProvenanceSourceContractError("unresolved administrative identity evidence")
        capital = unit["capital_place_id"]
        if (capital is not None and (capital not in place_ids or unit["capital_reference_status"] != "EXISTING_STABLE_PLACE")) or (capital is None and unit["capital_reference_status"] != "PLACE_REFERENCE_MISSING"):
            raise ProvenanceSourceContractError("unresolved administrative capital reference")
        if any(key in unit for key in ("members", "geometry", "controller_id", "population")):
            raise ProvenanceSourceContractError("identity evidence cannot carry world facts or boundaries")


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
    }


def build() -> tuple[dict[str, Any], dict[str, Any]]:
    political = read_json(POLITICAL_PATH)
    spatial = read_json(SPATIAL_PATH)
    population = read_json(POPULATION_PATH)
    population_manifest = read_json(POPULATION_MANIFEST_PATH)
    require_schema(political, "schema_version", 1)
    require_schema(spatial, "schema_version", 1)
    require_schema(population, "schema_id", "historical_world_economy_1900_compact_country_table_v1")
    require_schema(population_manifest, "schema_id", "historical_world_economy_1900_estimates_v1")
    valid_period(political["snapshot_date"], political["snapshot_date"])
    valid_period(spatial["snapshot_date"], spatial["snapshot_date"])
    political_ids = unique_records(political["units"], "id")
    geometry_ids = unique_records(spatial["features"], "id")
    validate_geometry(spatial["features"])
    for feature in spatial["features"]:
        valid_period(feature["valid_from"], feature["valid_to"])
    if political["unit_count"] != len(political_ids) or spatial["feature_count"] != len(geometry_ids):
        raise ProvenanceSourceContractError("declared count disagrees with records")
    for record in political["units"]:
        valid_period(record["valid_from"], record["valid_to"])
        if record["geometry_feature_id"] not in geometry_ids or (record["controller_id"] and record["controller_id"] not in political_ids):
            raise ProvenanceSourceContractError(f"invalid political geometry/controller reference: {record['id']}")

    political_source = {
        "source_id": "wwo-political-identities-1900-v1",
        "title": "WWO dated political identity catalog for 1900",
        "publisher": "WWO repository; normalized from CShapes 2.0",
        "version": "political_units_1900.schema_version=1",
        "license": "CC BY-NC-SA 4.0; repository transformation terms apply",
        "locator": POLITICAL_PATH,
        "access_metadata": {
            "upstream_source_id": "src-cshapes-2.0",
            "snapshot_date": political["snapshot_date"],
        },
    }
    spatial_source = {
        "source_id": "cshapes-2.0-wwo-snapshot-1900",
        "title": "CShapes 2.0 transformed WWO boundary snapshot",
        "publisher": "ETH Zürich ICR; repository transformation by WWO",
        "version": "2.0 / snapshot schema_version=1",
        "license": spatial["source"]["license"],
        "locator": SPATIAL_PATH,
        "access_metadata": {
            "source_page": spatial["source"]["source_page"],
            "upstream_content_hash": spatial["source"]["source_sha256"],
            "snapshot_date": spatial["snapshot_date"],
        },
    }
    population_source = {
        "source_id": "wwo-population-aggregate-estimates-1900-v1",
        "title": "WWO bounded 1900 population aggregate estimate table",
        "publisher": "WWO repository; derived compilation",
        "version": population["schema_id"],
        "license": "Mixed upstream terms; see the linked WWO source manifest",
        "locator": POPULATION_PATH,
        "access_metadata": {
            "manifest": POPULATION_MANIFEST_PATH,
            "source_ids": sorted(
                item["source_id"] for item in population_manifest["source_manifest"]
            ),
        },
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
    valid_period(date, date)
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

    for filename, subject, domain, version in SUPPLEMENTS:
        path = "res://data/world_map/historical/" + filename
        document = read_json(path)
        require_schema(document, "schema_version", 1)
        valid_period(document["target_date"], document["target_date"])
        if domain == "spatial_boundary":
            new_ids = unique_records(document["features"], "id")
            validate_geometry(document["features"])
            if geometry_ids & new_ids or document["feature_count"] != len(new_ids):
                raise ProvenanceSourceContractError("duplicate geometry or incorrect feature_count")
            geometry_ids |= new_ids
        else:
            unique_records(document["assignments"], "id")
            unique_records(document.get("map_display_records", []), "id")
            for record in document.get("map_display_records", []):
                valid_period(record["valid_from"], record["valid_to"])
            for record in document["assignments"]:
                valid_period(record["valid_from"], record["valid_to"])
                if record["geometry_feature_id"] not in geometry_ids or not record["source"]:
                    raise ProvenanceSourceContractError("invalid authority geometry/source reference")
            if "geometry_binding" in document:
                binding = document["geometry_binding"]
                geometry = read_json(binding["path"])
                feature = next(item for item in geometry["features"] if item["id"] == binding["feature_id"])
                if geometry["schema_version"] != binding["schema_version"] or len(feature["geometry"]["coordinates"]) != binding["exterior_count"]:
                    raise ProvenanceSourceContractError("authority geometry binding mismatch")
                for record in document["assignments"]:
                    if any(type(index) is not int or not 0 <= index < binding["exterior_count"] for index in record["geometry_component_indices"]):
                        raise ProvenanceSourceContractError("invalid geometry component index")
        source = {
            "source_id": subject, "title": subject.replace("_", " "),
            "publisher": "WWO historical map supplement", "version": version,
            "license": "CC-BY-NC-SA-4.0" if domain == "spatial_boundary" else "PROJECT_AUTHORED_EVIDENCE",
            "locator": path,
            "access_metadata": {"target_date": document["target_date"], "approximate": True,
                                "provenance": document.get("source", {}),
                                "sources": sorted({row["source"] for row in document.get("assignments", [])})},
        }
        sources.append(source)
        facts.append(evidence(
            fact_id=domain + ":" + subject, domain=domain, source=source,
            runtime_assertion=assertion(subject, supplement_value(document, domain), "historical_content_supplement",
                                        {"from": document["target_date"], "to": document["target_date"]},
                                        {"kind": "historical_supplement", "id": subject}),
            methodology=document.get("method", "Bounded historical approximation; separate geography and administrative facts. See supplement provenance."),
            confidence=.55 if filename == "arabia_authority_coverage_1900.json" else .6,
            review_status="APPROXIMATE",
        ))
    admin = read_json(FRANCE_ADMIN_PATH)
    place_ids = {"place:" + record["id"] for record in read_json("res://data/world_map/cities.json")["cities"]}
    local = read_json("res://data/local/paris_northern_france_1900.json")
    place_ids.update(fact["value"]["id"] for fact in local["evidence_catalog"]["facts"]
                     if isinstance(fact["value"], dict) and fact["value"].get("kind") == "settlement")
    validate_france_administrative_identity(admin, political_ids, place_ids)
    sources.extend(admin["sources"])
    admin_source = {
        "source_id": "france_administrative_identity_1900",
        "title": "WWO partial France 1900 administrative identity evidence",
        "publisher": "WWO factual extraction from SGF and official institutional histories",
        "version": admin["schema_id"], "license": "PROJECT_AUTHORED_FACTUAL_COMPILATION",
        "locator": FRANCE_ADMIN_PATH,
        "access_metadata": {"source_ids": sorted(item["source_id"] for item in admin["sources"]),
                            "geometry_admission": "NONE", "membership_admission": "NONE"},
    }
    sources.append(admin_source)
    facts.append(evidence(
        fact_id="administrative_identity:france_administrative_identity_1900", domain="administrative_identity",
        source=admin_source,
        runtime_assertion=assertion("france_administrative_identity_1900", admin, "historical_identity_reference",
                                    {"from": admin["target_date"], "to": admin["target_date"]},
                                    {"kind": "partial_department_roster", "id": admin["entity_id"]}),
        methodology="SGF T210 1900 records 73/76 verify historical names. Official archives/prefecture histories verify capitals. Identity reference only; no geometry, membership, exact founding/dissolution dates or modern crosswalk admitted.",
        confidence=.95, review_status="VERIFIED",
    ))
    land_path = "res://data/land/paris_land_pilot_r1.json"
    land = read_json(land_path)
    require_schema(land, "schema_id", "paris_land_pilot_r1")
    land_source = {
        "source_id": "paris_land_pilot_r1", "title": "Paris mainland pilot: qualified physical source and generated partition",
        "publisher": "WWO derivation from Natural Earth", "version": land["seed_version"],
        "license": "PUBLIC_DOMAIN", "locator": land_path,
        "access_metadata": {"source_review": land["source_review"], "historical_admin_boundary": "UNRESOLVED"},
    }
    sources.append(land_source)
    facts.append(evidence(
        fact_id="spatial_boundary:paris_land_pilot_r1", domain="spatial_boundary", source=land_source,
        runtime_assertion=assertion("paris_land_pilot_r1", land, "qualified_physical_source_generated_partition",
                                   {"from":"1900-01-01", "to":"1900-01-01"},
                                   {"kind":"bounded_paris_pilot", "id":"paris_land_pilot_r1"}),
        methodology="Pinned public-domain continental mask admits bounded interior inclusion only. Extent and partitions are generated game geometry; inland waters unclassified; France controller is an explicit opening-world assumption; historical administrative membership unresolved.",
        confidence=.8, review_status="GENERATED_SIMULATION_ASSUMPTION",
    ))
    sources.sort(key=lambda item: item["source_id"])
    facts.sort(key=lambda item: item["fact_id"])
    unique_records(sources, "source_id")
    unique_records(facts, "fact_id")
    registry = {"schema_id": "historical_source_registry_v2", "sources": sources}
    catalog = {"schema_id": "historical_fact_evidence_catalog_v2", "facts": facts}
    return registry, catalog


def write_json(path: Path, value: Any) -> None:
    payload = (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")
    path.write_bytes(payload)


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
    write_json(output_dir / "historical_source_registry.json", registry)
    write_json(output_dir / "historical_fact_evidence.json", catalog)


if __name__ == "__main__":
    main()
