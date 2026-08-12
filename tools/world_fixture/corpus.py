"""Parser and focused contract checks for the WWO world-data fixture corpus.

The checker intentionally operates on fixture documents only.  It mirrors the
field names consumed by the current world-map loader, but it is not a second
gameplay data source and it does not change authoritative files.
"""

from __future__ import annotations

import copy
import hashlib
import json
import math
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable, Mapping


CORPUS_PATH = Path(__file__).resolve().parents[2] / "tests" / "fixtures" / "world_data" / "corpus.json"

DOCUMENT_COLLECTIONS: dict[str, str] = {
    "countries.json": "countries",
    "regions.json": "regions",
    "cities.json": "cities",
    "ports.json": "ports",
    "road_segments.json": "segments",
    "rail_segments.json": "segments",
    "shipping_routes.json": "routes",
    "organizations.json": "catalog",
    "institutions.json": "institutions",
    "relationships.json": "relationships",
    "historical_political_entities_1900.json": "entities",
    "historical/political_units_1900.json": "units",
    "historical/cshapes_1900_snapshot.json": "features",
    "historical/flags_1900.json": "records",
    "historical/major_state_profiles_1900.json": "profiles",
    "world_coastlines.json": "features",
}

REQUIRED_FIELDS: dict[str, tuple[str, ...]] = {
    "countries.json": ("id", "object_level", "name"),
    "regions.json": ("id", "object_level", "name", "parent_country_id"),
    "cities.json": ("id", "object_level", "name", "parent_country_id", "lon_lat"),
    "ports.json": ("id", "object_level", "name", "city_id", "parent_country_id", "lon_lat"),
    "road_segments.json": ("id", "type", "from_city_id", "to_city_id"),
    "rail_segments.json": ("id", "type", "from_city_id", "to_city_id"),
    "shipping_routes.json": ("id", "type", "from_port_id", "to_port_id", "waypoints_lon_lat"),
    "organizations.json": ("id", "object_level", "name"),
    "institutions.json": ("id", "object_level", "name"),
    "relationships.json": ("id", "city_id", "nationality_id", "region_id"),
    "historical_political_entities_1900.json": ("id", "status", "members"),
    "historical/political_units_1900.json": ("id", "geometry_feature_id", "flag_id"),
    "historical/cshapes_1900_snapshot.json": ("id", "geometry"),
    "historical/flags_1900.json": ("id",),
    "historical/major_state_profiles_1900.json": ("entity_id", "aliases"),
    "world_coastlines.json": ("id", "geometry_type", "polygons"),
}

REFERENCE_RULES: dict[str, tuple[str, str, bool]] = {
    "cities.json.parent_country_id": ("countries.json", "countries", False),
    "cities.json.parent_region_id": ("regions.json", "regions", True),
    "ports.json.city_id": ("cities.json", "cities", False),
    "ports.json.parent_country_id": ("countries.json", "countries", False),
    "ports.json.parent_region_id": ("regions.json", "regions", True),
    "road_segments.json.from_city_id": ("cities.json", "cities", False),
    "road_segments.json.to_city_id": ("cities.json", "cities", False),
    "rail_segments.json.from_city_id": ("cities.json", "cities", False),
    "rail_segments.json.to_city_id": ("cities.json", "cities", False),
    "shipping_routes.json.from_port_id": ("ports.json", "ports", False),
    "shipping_routes.json.to_port_id": ("ports.json", "ports", False),
    "organizations.json.city_id": ("cities.json", "cities", True),
    "organizations.json.country_id": ("countries.json", "countries", True),
    "organizations.json.parent_region_id": ("regions.json", "regions", True),
    "organizations.json.institution_id": ("institutions.json", "institutions", True),
    "institutions.json.city_id": ("cities.json", "cities", True),
    "institutions.json.parent_country_id": ("countries.json", "countries", True),
    "institutions.json.parent_region_id": ("regions.json", "regions", True),
    "institutions.json.parent_institution_id": ("institutions.json", "institutions", True),
    "relationships.json.city_id": ("cities.json", "cities", False),
    "relationships.json.nationality_id": ("countries.json", "countries", False),
    "relationships.json.region_id": ("regions.json", "regions", False),
    "relationships.json.employer_id": ("organizations.json", "catalog", True),
    "relationships.json.institution_id": ("institutions.json", "institutions", True),
    "historical/political_units_1900.json.controller_id": (
        "historical_political_entities_1900.json",
        "entities",
        True,
    ),
    "historical/political_units_1900.json.geometry_feature_id": (
        "historical/cshapes_1900_snapshot.json",
        "features",
        False,
    ),
    "historical/political_units_1900.json.flag_id": ("historical/flags_1900.json", "records", False),
    "historical/major_state_profiles_1900.json.entity_id": (
        "historical_political_entities_1900.json",
        "entities",
        False,
    ),
}

TRANSPORT_DOCUMENTS = {"road_segments.json", "rail_segments.json", "shipping_routes.json"}


def _reject_nonfinite(value: str) -> Any:
    raise ValueError(f"non-standard JSON constant {value}")


def canonical_json(value: Any) -> str:
    """Return stable UTF-8 JSON for hashing and replay comparisons."""

    return json.dumps(
        value,
        ensure_ascii=False,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    )


def canonical_hash(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def load_corpus(path: Path = CORPUS_PATH) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        corpus = json.load(handle, parse_constant=_reject_nonfinite)
    if not isinstance(corpus, dict) or not isinstance(corpus.get("fixtures"), list):
        raise ValueError("world-data corpus must be an object with a fixtures array")
    ids = [fixture.get("fixture_id") for fixture in corpus["fixtures"] if isinstance(fixture, dict)]
    if len(ids) != len(set(ids)):
        raise ValueError("fixture IDs must be globally unique")
    return corpus


def _fixture_index(corpus: Mapping[str, Any]) -> dict[str, Mapping[str, Any]]:
    return {str(item["fixture_id"]): item for item in corpus["fixtures"]}


def _merge_documents(left: dict[str, Any], right: Mapping[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(left)
    for dataset, right_document in right.items():
        if dataset not in result:
            result[dataset] = copy.deepcopy(right_document)
            continue
        left_document = result[dataset]
        for key, value in right_document.items():
            if isinstance(value, list) and isinstance(left_document.get(key), list):
                left_document[key].extend(copy.deepcopy(value))
            elif isinstance(value, dict) and isinstance(left_document.get(key), dict):
                left_document[key].update(copy.deepcopy(value))
            else:
                left_document[key] = copy.deepcopy(value)
    return result


def _apply_mutation(documents: dict[str, Any], mutation: Mapping[str, Any]) -> None:
    dataset = str(mutation.get("dataset", ""))
    collection = str(mutation.get("collection", DOCUMENT_COLLECTIONS.get(dataset, "")))
    index = int(mutation.get("index", 0))
    records = documents[dataset][collection]
    operation = str(mutation.get("op", ""))
    if operation == "duplicate_record":
        record = copy.deepcopy(records[index])
        records.append(record)
        return
    if operation == "duplicate_edge":
        record = copy.deepcopy(records[index])
        record["id"] = str(mutation["new_id"])
        records.append(record)
        return
    record = records[index]
    field = str(mutation.get("field", ""))
    if operation == "remove_field":
        record.pop(field, None)
    elif operation == "set_value":
        record[field] = copy.deepcopy(mutation.get("value"))
    else:
        raise ValueError(f"unsupported fixture mutation: {operation}")


def materialize_fixture(corpus: Mapping[str, Any], fixture_id: str) -> dict[str, Any]:
    fixtures = _fixture_index(corpus)
    if fixture_id not in fixtures:
        raise KeyError(f"unknown fixture: {fixture_id}")
    fixture = fixtures[fixture_id]
    if fixture.get("base_fixture_id"):
        documents = materialize_fixture(corpus, str(fixture["base_fixture_id"]))
    else:
        documents = {}
    documents = _merge_documents(documents, fixture.get("documents", {}))
    for mutation in fixture.get("mutations", []):
        _apply_mutation(documents, mutation)
    return documents


def _is_empty(value: Any) -> bool:
    return value is None or value == "" or value == []


def _finite_coordinate(value: Any) -> bool:
    return (
        isinstance(value, list)
        and len(value) == 2
        and all(isinstance(item, (int, float)) and not isinstance(item, bool) and math.isfinite(float(item)) for item in value)
    )


def _coordinate_in_range(value: list[Any]) -> bool:
    return -180.0 <= float(value[0]) <= 180.0 and -90.0 <= float(value[1]) <= 90.0


def _records_for(documents: Mapping[str, Any], dataset: str) -> list[dict[str, Any]]:
    collection = DOCUMENT_COLLECTIONS[dataset]
    value = documents.get(dataset, {}).get(collection, [])
    return value if isinstance(value, list) else []


def _ids_for(documents: Mapping[str, Any], dataset: str) -> set[str]:
    id_field = "entity_id" if dataset == "historical/major_state_profiles_1900.json" else "id"
    return {str(record.get(id_field)) for record in _records_for(documents, dataset) if record.get(id_field)}


def _finding(code: str, severity: str, dataset: str, index: int, message: str) -> dict[str, Any]:
    return {
        "code": code,
        "severity": severity,
        "dataset": dataset,
        "index": index,
        "message": message,
    }


def _validate_geometry_metadata(dataset: str, index: int, record: Mapping[str, Any]) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []
    polygons = record.get("polygons")
    if dataset == "world_coastlines.json" and isinstance(polygons, list):
        if "outer_ring_count" in record and int(record["outer_ring_count"]) != len(polygons):
            findings.append(_finding("MALFORMED_GEOMETRY_METADATA", "ERROR", dataset, index, "outer_ring_count disagrees with polygons"))
        if "hole_count" in record:
            actual_holes = sum(len(item.get("holes", [])) for item in polygons if isinstance(item, dict))
            if int(record["hole_count"]) != actual_holes:
                findings.append(_finding("MALFORMED_GEOMETRY_METADATA", "ERROR", dataset, index, "hole_count disagrees with polygon holes"))
    geometry = record.get("geometry")
    if dataset == "historical/cshapes_1900_snapshot.json" and isinstance(geometry, dict):
        if geometry.get("type") not in {"Polygon", "MultiPolygon"}:
            findings.append(_finding("MALFORMED_GEOMETRY_METADATA", "ERROR", dataset, index, "historical geometry type is unsupported"))
        coordinates = geometry.get("coordinates")
        if not isinstance(coordinates, list) or not coordinates:
            findings.append(_finding("MALFORMED_GEOMETRY_METADATA", "ERROR", dataset, index, "historical geometry has no coordinates"))
    return findings


def validate_fixture(documents: Mapping[str, Any]) -> list[dict[str, Any]]:
    """Run only mechanical fixture checks derived from existing field names."""

    findings: list[dict[str, Any]] = []
    ids_by_dataset: dict[str, set[str]] = {}
    for dataset, collection in DOCUMENT_COLLECTIONS.items():
        if dataset not in documents:
            continue
        document = documents[dataset]
        if not isinstance(document, dict) or not isinstance(document.get(collection), list):
            findings.append(_finding("DOCUMENT_COLLECTION_TYPE", "ERROR", dataset, -1, f"{collection} must be an array"))
            continue
        ids_by_dataset[dataset] = set()
        for index, record in enumerate(document[collection]):
            if not isinstance(record, dict):
                findings.append(_finding("RECORD_TYPE", "ERROR", dataset, index, "record must be an object"))
                continue
            id_field = "entity_id" if dataset == "historical/major_state_profiles_1900.json" else "id"
            record_id = record.get(id_field)
            if record_id in (None, ""):
                findings.append(_finding("EMPTY_REQUIRED_VALUE", "ERROR", dataset, index, f"{id_field} is empty"))
            elif str(record_id) in ids_by_dataset[dataset]:
                findings.append(_finding("DUPLICATE_ID", "ERROR", dataset, index, f"duplicate {id_field}: {record_id}"))
            else:
                ids_by_dataset[dataset].add(str(record_id))
            for field in REQUIRED_FIELDS.get(dataset, ()):
                if field not in record or _is_empty(record.get(field)):
                    if field in {"from_city_id", "to_city_id", "from_port_id", "to_port_id"}:
                        findings.append(_finding("MISSING_ENDPOINT", "ERROR", dataset, index, f"{field} is required"))
                    elif not (field == "controller_id" and dataset == "historical/political_units_1900.json"):
                        findings.append(_finding("EMPTY_REQUIRED_VALUE", "ERROR", dataset, index, f"{field} is required"))
            for field in ("lon_lat", "label_anchor", "label_lon_lat"):
                if field in record and not _finite_coordinate(record[field]):
                    findings.append(_finding("INVALID_COORDINATE", "ERROR", dataset, index, f"{field} is not a finite pair"))
                elif field in record and not _coordinate_in_range(record[field]):
                    findings.append(_finding("INVALID_COORDINATE", "ERROR", dataset, index, f"{field} is out of range"))
            if field := record.get("capital"):
                if isinstance(field, dict) and ("lon" in field or "lat" in field):
                    pair = [field.get("lon"), field.get("lat")]
                    if not _finite_coordinate(pair) or not _coordinate_in_range(pair):
                        findings.append(_finding("INVALID_COORDINATE", "ERROR", dataset, index, "capital coordinate is invalid"))
            if dataset == "shipping_routes.json":
                for point in record.get("waypoints_lon_lat", []):
                    if not _finite_coordinate(point) or not _coordinate_in_range(point):
                        findings.append(_finding("INVALID_COORDINATE", "ERROR", dataset, index, "shipping waypoint is invalid"))
            findings.extend(_validate_geometry_metadata(dataset, index, record))

    for dataset, records in ((name, _records_for(documents, name)) for name in TRANSPORT_DOCUMENTS if name in documents):
        seen_edges: set[tuple[str, str, str]] = set()
        for index, record in enumerate(records):
            if dataset == "shipping_routes.json":
                edge = ("shipping", str(record.get("from_port_id", "")), str(record.get("to_port_id", "")))
            else:
                edge = (str(record.get("type", dataset.split("_")[0])), str(record.get("from_city_id", "")), str(record.get("to_city_id", "")))
            if edge in seen_edges and edge[1] and edge[2]:
                findings.append(_finding("DUPLICATE_TRANSPORT_EDGE", "ERROR", dataset, index, f"duplicate edge {edge[1]} -> {edge[2]}"))
            seen_edges.add(edge)

    for dataset, collection, field, (target_dataset, target_collection, allow_empty) in (
        (dataset, DOCUMENT_COLLECTIONS[dataset], field, rule)
        for reference, rule in REFERENCE_RULES.items()
        for dataset, field in [reference.rsplit(".", 1)]
        if dataset in documents
    ):
        target_ids = _ids_for(documents, target_dataset)
        for index, record in enumerate(_records_for(documents, dataset)):
            value = record.get(field)
            if _is_empty(value):
                continue
            if str(value) not in target_ids:
                findings.append(_finding("MISSING_FOREIGN_KEY", "ERROR", dataset, index, f"{field} does not resolve"))

    alias_targets: defaultdict[str, set[str]] = defaultdict(set)
    for record in _records_for(documents, "historical/major_state_profiles_1900.json"):
        for alias in record.get("aliases", []):
            if alias:
                alias_targets[str(alias).casefold()].add(str(record.get("entity_id", "")))
    for alias, targets in sorted(alias_targets.items()):
        if len(targets) > 1:
            findings.append(_finding("NO_CURRENT_RULE", "WARNING", "historical/major_state_profiles_1900.json", -1, f"alias collision has no current validator rule: {alias}"))
    return findings


def expected_result(findings: Iterable[Mapping[str, Any]]) -> str:
    if any(item.get("severity") == "ERROR" for item in findings):
        return "INVALID"
    if any(item.get("severity") == "WARNING" for item in findings):
        return "WARNING"
    return "VALID"
