#!/usr/bin/env python3
"""Audit the repository's authoritative world-data tree without mutating it.

The validator deliberately knows the schemas already consumed by the current
world-map loaders.  It produces findings and derived staging data; it never
rewrites an authoritative JSON file.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Iterator, Mapping, Sequence


VALIDATOR_SCHEMA_VERSION = 1
PROJECT_ROOT = Path(__file__).resolve().parents[2]


@dataclass(frozen=True)
class CatalogSpec:
    dataset: str
    collection: str
    kind: str
    id_field: str
    display_name: str


@dataclass(frozen=True)
class RecordRef:
    kind: str
    dataset: str
    collection: str
    index: int
    record_id: str
    record: Mapping[str, Any]
    map_key: str = ""

    @property
    def location(self) -> str:
        suffix = f"[{self.index}]"
        if self.map_key:
            suffix = f"[{self.map_key!r}]"
        return f"{self.dataset}:{self.collection}{suffix}"


@dataclass(frozen=True)
class Finding:
    severity: str
    code: str
    dataset: str
    location: str
    message: str
    record_id: str = ""
    evidence: Mapping[str, Any] | None = None
    suggested_action: str = ""

    def as_dict(self) -> dict[str, Any]:
        return {
            "severity": self.severity,
            "code": self.code,
            "dataset": self.dataset,
            "location": self.location,
            "record_id": self.record_id,
            "message": self.message,
            "evidence": dict(self.evidence or {}),
            "suggested_action": self.suggested_action,
        }


CATALOG_SPECS: tuple[CatalogSpec, ...] = (
    CatalogSpec("countries.json", "countries", "country", "id", "countries"),
    CatalogSpec("regions.json", "regions", "region", "id", "macro regions"),
    CatalogSpec(
        "regions.json",
        "administrative_units",
        "administrative_unit",
        "id",
        "administrative units",
    ),
    CatalogSpec("cities.json", "cities", "city", "id", "curated cities"),
    CatalogSpec("ports.json", "ports", "port", "id", "ports"),
    CatalogSpec("road_segments.json", "segments", "road", "id", "road links"),
    CatalogSpec("rail_segments.json", "segments", "rail", "id", "rail links"),
    CatalogSpec("shipping_routes.json", "routes", "shipping", "id", "shipping links"),
    CatalogSpec("organizations.json", "catalog", "organization", "id", "organizations"),
    CatalogSpec("institutions.json", "institutions", "institution", "id", "institutions"),
    CatalogSpec("characters.json", "identities", "character", "id", "characters"),
    CatalogSpec("relationships.json", "relationships", "relationship", "id", "relationship seeds"),
    CatalogSpec("world_activity.json", "items", "activity", "id", "world activity items"),
    CatalogSpec(
        "world_coastlines.json",
        "features",
        "modern_coastline",
        "id",
        "modern country geometry",
    ),
    CatalogSpec("world_admin1.json", "regions", "modern_admin1", "id", "modern admin1 geometry"),
    CatalogSpec(
        "historical_political_entities_1900.json",
        "entities",
        "historical_entity",
        "id",
        "historical political entities",
    ),
    CatalogSpec(
        "historical_political_entities_1900.json",
        "conflicts",
        "conflict",
        "id",
        "historical conflict paths",
    ),
    CatalogSpec(
        "historical/political_units_1900.json",
        "units",
        "historical_unit",
        "id",
        "historical political units",
    ),
    CatalogSpec(
        "historical/cshapes_1900_snapshot.json",
        "features",
        "historical_geometry",
        "id",
        "historical geometry",
    ),
    CatalogSpec(
        "historical/historical_admin1_1900.json",
        "countries",
        "historical_admin1",
        "entity_id",
        "historical admin1 coverage",
    ),
    CatalogSpec(
        "historical/major_state_profiles_1900.json",
        "profiles",
        "major_state_profile",
        "entity_id",
        "major historical profiles",
    ),
    CatalogSpec(
        "historical/flags_1900.json",
        "records",
        "historical_flag",
        "id",
        "historical flags",
    ),
    CatalogSpec(
        "historical/major_economy_polity_crosswalk_1900.json",
        "records",
        "historical_crosswalk",
        "economy_entity_id",
        "historical economy crosswalk",
    ),
    CatalogSpec(
        "city_detail/index.json",
        "countries",
        "city_detail_shard",
        "country_code",
        "city-detail shard index",
    ),
    CatalogSpec(
        "country_flag_palettes.json",
        "palettes",
        "flag_palette",
        "__key__",
        "modern theme palettes",
    ),
)


REFERENCE_RULES: tuple[tuple[str, str, str, tuple[str, ...], bool, str], ...] = (
    ("regions.json", "regions", "parent_country_id", ("country",), False, "country"),
    ("regions.json", "regions", "administrative_unit_ids", ("administrative_unit",), False, "admin unit"),
    ("regions.json", "regions", "institution_ids", ("institution",), False, "institution"),
    ("regions.json", "administrative_units", "parent_country_id", ("country",), False, "country"),
    ("regions.json", "administrative_units", "parent_id", ("administrative_unit", "country"), True, "parent admin unit or country"),
    ("cities.json", "cities", "parent_country_id", ("country",), False, "country"),
    ("cities.json", "cities", "parent_region_id", ("region",), True, "region"),
    ("cities.json", "cities", "departement_id", ("administrative_unit",), True, "admin unit"),
    ("ports.json", "ports", "city_id", ("city",), False, "city"),
    ("ports.json", "ports", "parent_region_id", ("region",), True, "region"),
    ("ports.json", "ports", "parent_country_id", ("country",), False, "country"),
    ("road_segments.json", "segments", "from_city_id", ("city",), False, "road endpoint"),
    ("road_segments.json", "segments", "to_city_id", ("city",), False, "road endpoint"),
    ("rail_segments.json", "segments", "from_city_id", ("city",), False, "rail endpoint"),
    ("rail_segments.json", "segments", "to_city_id", ("city",), False, "rail endpoint"),
    ("shipping_routes.json", "routes", "from_port_id", ("port",), False, "shipping endpoint"),
    ("shipping_routes.json", "routes", "to_port_id", ("port",), False, "shipping endpoint"),
    ("organizations.json", "catalog", "city_id", ("city",), False, "city"),
    ("organizations.json", "catalog", "country_id", ("country",), False, "country"),
    ("organizations.json", "catalog", "parent_region_id", ("region",), False, "region"),
    ("organizations.json", "catalog", "institution_id", ("institution",), True, "institution"),
    ("institutions.json", "institutions", "administrative_unit_id", ("administrative_unit", "country"), True, "admin unit or country"),
    ("institutions.json", "institutions", "city_id", ("city",), True, "city"),
    ("institutions.json", "institutions", "parent_country_id", ("country",), False, "country"),
    ("institutions.json", "institutions", "parent_region_id", ("region",), True, "region"),
    ("institutions.json", "institutions", "parent_institution_id", ("institution",), True, "parent institution"),
    ("institutions.json", "institutions", "child_institution_ids", ("institution",), True, "child institution"),
    ("characters.json", "identities", "nationality_id", ("country",), False, "country"),
    ("characters.json", "identities", "city_id", ("city",), False, "city"),
    ("characters.json", "identities", "workplace_city_id", ("city",), True, "workplace city"),
    ("characters.json", "identities", "region_id", ("region",), False, "region"),
    ("characters.json", "identities", "employer_id", ("organization",), True, "employer"),
    ("characters.json", "identities", "institution_id", ("institution",), True, "institution"),
    ("characters.json", "identities", "jurisdiction_id", ("administrative_unit", "region", "country"), True, "jurisdiction"),
    ("characters.json", "identities", "school_id", ("organization",), True, "school"),
    ("characters.json", "identities", "union_id", ("organization",), True, "union"),
    ("relationships.json", "relationships", "city_id", ("city",), False, "city"),
    ("relationships.json", "relationships", "employer_id", ("organization",), True, "employer"),
    ("relationships.json", "relationships", "institution_id", ("institution",), True, "institution"),
    ("relationships.json", "relationships", "organization_id", ("organization",), True, "organization"),
    ("relationships.json", "relationships", "region_id", ("region",), False, "region"),
    ("relationships.json", "relationships", "nationality_id", ("country",), False, "country"),
)


EXPECTED_OBJECT_LEVELS: dict[str, set[str]] = {
    "country": {"country"},
    "region": {"region"},
    "administrative_unit": {"administrative_unit", "region"},
    "city": {"city"},
    "port": {"port"},
    "organization": {"organization"},
    "institution": {"institution"},
}


ID_PREFIX_RULES: dict[str, tuple[str, ...]] = {
    "road": ("road_",),
    "rail": ("rail_",),
    "shipping": ("shipping_",),
    "modern_coastline": ("ne_admin0_",),
    "historical_geometry": ("gw_",),
}


COORDINATE_FIELDS: tuple[tuple[str, str, str, bool, bool], ...] = (
    ("countries.json", "countries", "label_anchor", True, True),
    ("countries.json", "countries", "label_lon_lat", True, True),
    ("regions.json", "regions", "label_anchor", True, True),
    ("regions.json", "regions", "label_lon_lat", True, True),
    ("regions.json", "administrative_units", "label_anchor", True, True),
    ("cities.json", "cities", "lon_lat", True, True),
    ("ports.json", "ports", "lon_lat", True, True),
    ("organizations.json", "catalog", "lon_lat", True, False),
    ("institutions.json", "institutions", "lon_lat", True, True),
)


SOURCE_FIELD_PATTERN = re.compile(
    r"(?:source|license|url|citation|provider|historical|notice|snapshot|attribution|provenance)",
    re.IGNORECASE,
)
ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]*$")
SOURCE_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:+?\-]*$")


def _reject_nonfinite(value: str) -> Any:
    raise ValueError(f"non-standard JSON constant {value}")


def load_json_documents(data_root: Path) -> tuple[dict[str, Any], list[Finding], dict[str, int]]:
    documents: dict[str, Any] = {}
    findings: list[Finding] = []
    sizes: dict[str, int] = {}
    for path in sorted(data_root.rglob("*.json")):
        relative = path.relative_to(data_root).as_posix()
        sizes[relative] = path.stat().st_size
        try:
            with path.open("r", encoding="utf-8") as handle:
                value = json.load(handle, parse_constant=_reject_nonfinite)
        except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as exc:
            findings.append(
                Finding(
                    "ERROR",
                    "JSON_PARSE_ERROR",
                    relative,
                    relative,
                    f"unable to parse JSON: {exc}",
                    suggested_action="Keep the authoritative file unchanged and repair it through a reviewed source-data change.",
                )
            )
            continue
        if not isinstance(value, dict):
            findings.append(
                Finding(
                    "ERROR",
                    "JSON_ROOT_NOT_OBJECT",
                    relative,
                    relative,
                    "runtime loader expects a JSON object at the document root",
                )
            )
            continue
        documents[relative] = value
    return documents, findings, sizes


def iter_collection(document: Any, collection: str) -> Iterator[tuple[int, str, Mapping[str, Any]]]:
    if not isinstance(document, Mapping):
        return
    value = document.get(collection)
    if isinstance(value, list):
        for index, row in enumerate(value):
            if isinstance(row, Mapping):
                yield index, "", row
            else:
                yield index, "", {"__invalid_record__": row}
    elif isinstance(value, Mapping):
        for index, (map_key, row) in enumerate(value.items()):
            if isinstance(row, Mapping):
                yield index, str(map_key), row
            else:
                yield index, str(map_key), {"__invalid_record__": row}


def iter_path_rows(documents: Mapping[str, Any], dataset: str, collection: str) -> Iterator[RecordRef]:
    document = documents.get(dataset)
    for index, map_key, row in iter_collection(document, collection):
        yield RecordRef("", dataset, collection, index, "", row, map_key)


def is_empty_reference(value: Any) -> bool:
    return value is None or value == "" or value == []


def number_is_finite(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))


def coordinate_pair(value: Any) -> bool:
    return isinstance(value, (list, tuple)) and len(value) == 2 and all(number_is_finite(item) for item in value)


def iter_coordinate_pairs(value: Any) -> Iterator[tuple[float, float]]:
    if coordinate_pair(value):
        yield float(value[0]), float(value[1])
        return
    if isinstance(value, list):
        for child in value:
            yield from iter_coordinate_pairs(child)


def ring_area(ring: Sequence[Sequence[float]]) -> float:
    if len(ring) < 3:
        return 0.0
    points = ring[:-1] if len(ring) > 1 and ring[0] == ring[-1] else ring
    if len(points) < 3:
        return 0.0
    return 0.5 * sum(
        points[index][0] * points[(index + 1) % len(points)][1]
        - points[(index + 1) % len(points)][0] * points[index][1]
        for index in range(len(points))
    )


def cross(a: Sequence[float], b: Sequence[float], c: Sequence[float]) -> float:
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def segments_intersect(
    a: Sequence[float],
    b: Sequence[float],
    c: Sequence[float],
    d: Sequence[float],
) -> bool:
    epsilon = 1e-12
    ab_c = cross(a, b, c)
    ab_d = cross(a, b, d)
    cd_a = cross(c, d, a)
    cd_b = cross(c, d, b)
    if ((ab_c > epsilon and ab_d < -epsilon) or (ab_c < -epsilon and ab_d > epsilon)) and (
        (cd_a > epsilon and cd_b < -epsilon) or (cd_a < -epsilon and cd_b > epsilon)
    ):
        return True

    def on_segment(p: Sequence[float], q: Sequence[float], r: Sequence[float]) -> bool:
        return (
            min(p[0], r[0]) - epsilon <= q[0] <= max(p[0], r[0]) + epsilon
            and min(p[1], r[1]) - epsilon <= q[1] <= max(p[1], r[1]) + epsilon
        )

    return (
        abs(ab_c) <= epsilon and on_segment(a, c, b)
        or abs(ab_d) <= epsilon and on_segment(a, d, b)
        or abs(cd_a) <= epsilon and on_segment(c, a, d)
        or abs(cd_b) <= epsilon and on_segment(c, b, d)
    )


def ring_self_intersects(ring: Sequence[Sequence[float]]) -> bool:
    if len(ring) < 4:
        return False
    points = list(ring[:-1] if ring[0] == ring[-1] else ring)
    edge_count = len(points)
    for left in range(edge_count):
        left_end = (left + 1) % edge_count
        for right in range(left + 1, edge_count):
            right_end = (right + 1) % edge_count
            if left == right or left_end == right or right_end == left:
                continue
            if segments_intersect(points[left], points[left_end], points[right], points[right_end]):
                return True
    return False


def canonical_ring(ring: Sequence[Sequence[float]]) -> str:
    rounded = [(round(float(point[0]), 9), round(float(point[1]), 9)) for point in ring]
    if rounded and rounded[0] == rounded[-1]:
        rounded = rounded[:-1]
    if not rounded:
        return ""
    rotations = [rounded[index:] + rounded[:index] for index in range(len(rounded))]
    reversed_points = list(reversed(rounded))
    rotations.extend(reversed_points[index:] + reversed_points[:index] for index in range(len(reversed_points)))
    return json.dumps(min(rotations), separators=(",", ":"))


def bbox_for_points(points: Sequence[Sequence[float]]) -> list[float] | None:
    if not points:
        return None
    return [
        min(float(point[0]) for point in points),
        min(float(point[1]) for point in points),
        max(float(point[0]) for point in points),
        max(float(point[1]) for point in points),
    ]


def flatten_rings(value: Any) -> Iterator[list[list[float]]]:
    """Yield lists of coordinate pairs from GeoJSON-like nested coordinates."""
    if isinstance(value, list) and value and all(coordinate_pair(item) for item in value):
        yield [[float(point[0]), float(point[1])] for point in value]
        return
    if isinstance(value, list):
        for child in value:
            yield from flatten_rings(child)


def nested_field_names(value: Any, prefix: str = "") -> Iterator[str]:
    if isinstance(value, Mapping):
        for key, child in value.items():
            path = f"{prefix}.{key}" if prefix else str(key)
            yield path
            yield from nested_field_names(child, path)
    elif isinstance(value, list):
        for child in value[:3]:
            yield from nested_field_names(child, prefix + "[]")


class WorldDataAudit:
    def __init__(self, data_root: Path) -> None:
        self.data_root = data_root
        self.documents: dict[str, Any] = {}
        self.sizes: dict[str, int] = {}
        self.findings: list[Finding] = []
        self.rows_by_kind: dict[str, list[RecordRef]] = defaultdict(list)
        self.ids_by_kind: dict[str, set[str]] = defaultdict(set)
        self.duplicate_ids: dict[str, list[str]] = defaultdict(list)
        self.geometry_metadata: list[dict[str, Any]] = []

    def add(
        self,
        severity: str,
        code: str,
        dataset: str,
        location: str,
        message: str,
        record_id: str = "",
        evidence: Mapping[str, Any] | None = None,
        suggested_action: str = "",
    ) -> None:
        self.findings.append(
            Finding(severity, code, dataset, location, message, record_id, evidence, suggested_action)
        )

    def run(self) -> dict[str, Any]:
        self.documents, load_findings, self.sizes = load_json_documents(self.data_root)
        self.findings.extend(load_findings)
        self._validate_root_schemas()
        self._build_catalogs()
        self._validate_references()
        self._validate_dynamic_references()
        self._validate_coordinates()
        self._validate_geometries()
        self._validate_geometry_cache()
        self._validate_metadata_consistency()
        inventory = self._build_inventory()
        coverage = self._build_coverage()
        staging = self._build_staging_candidates(inventory)
        normalization = self._build_normalization_candidates()
        findings = [finding.as_dict() for finding in sorted(self.findings, key=self._finding_sort_key)]
        return {
            "validator": {
                "name": "wwo_world_data_validator",
                "schema_version": VALIDATOR_SCHEMA_VERSION,
                "read_only": True,
                "data_root": self.data_root.as_posix(),
            },
            "inventory": inventory,
            "findings": findings,
            "coverage": coverage,
            "staging_candidates": staging,
            "normalization_candidates": normalization,
            "summary": self._summary(findings),
        }

    @staticmethod
    def _finding_sort_key(finding: Finding) -> tuple[Any, ...]:
        severity_order = {"ERROR": 0, "WARNING": 1, "INFO": 2}
        return (severity_order.get(finding.severity, 9), finding.dataset, finding.location, finding.code)

    @staticmethod
    def _summary(findings: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
        severity_counts = Counter(str(finding.get("severity", "")) for finding in findings)
        code_counts = Counter(str(finding.get("code", "")) for finding in findings)
        return {
            "finding_count": len(findings),
            "severity_counts": dict(sorted(severity_counts.items())),
            "code_counts": dict(sorted(code_counts.items())),
        }

    def _validate_root_schemas(self) -> None:
        for dataset, document in sorted(self.documents.items()):
            if dataset == "city_detail/LICENSE.json":
                continue
            if "schema_version" not in document and "schema_id" not in document:
                self.add(
                    "WARNING",
                    "SCHEMA_IDENTIFIER_MISSING",
                    dataset,
                    dataset,
                    "document has no schema_version or schema_id; loader compatibility is implicit",
                    suggested_action="Document the schema identifier in a reviewed data change if the file is runtime input.",
                )
            if "schema_version" in document and not isinstance(document["schema_version"], int):
                self.add("ERROR", "SCHEMA_VERSION_TYPE", dataset, dataset, "schema_version must be an integer")
            if "schema_id" in document and not isinstance(document["schema_id"], str):
                self.add("ERROR", "SCHEMA_ID_TYPE", dataset, dataset, "schema_id must be a string")

    def _build_catalogs(self) -> None:
        specs = list(CATALOG_SPECS)
        for dataset in sorted(self.documents):
            if dataset.startswith("city_detail/") and dataset.endswith(".json") and dataset not in {
                "city_detail/index.json",
                "city_detail/LICENSE.json",
            }:
                specs.append(CatalogSpec(dataset, "cities", "city_detail_city", "id", "city-detail records"))

        for spec in specs:
            seen: dict[str, RecordRef] = {}
            for index, map_key, raw_row in iter_collection(self.documents.get(spec.dataset), spec.collection):
                location = f"{spec.dataset}:{spec.collection}[{map_key!r}]" if map_key else f"{spec.dataset}:{spec.collection}[{index}]"
                if "__invalid_record__" in raw_row:
                    self.add(
                        "ERROR",
                        "RECORD_NOT_OBJECT",
                        spec.dataset,
                        location,
                        "catalog record must be a JSON object",
                    )
                    continue
                raw_id: Any
                if spec.id_field == "__key__":
                    raw_id = map_key
                else:
                    raw_id = raw_row.get(spec.id_field)
                record_id = "" if raw_id is None else str(raw_id).strip()
                ref = RecordRef(spec.kind, spec.dataset, spec.collection, index, record_id, raw_row, map_key)
                if not record_id:
                    self.add(
                        "ERROR",
                        "EMPTY_ID",
                        spec.dataset,
                        location,
                        f"{spec.display_name} record has an empty {spec.id_field}",
                        suggested_action="Add or derive a stable ID only after confirming the source identity.",
                    )
                    continue
                if record_id in seen:
                    self.duplicate_ids[spec.kind].append(record_id)
                    self.add(
                        "ERROR",
                        "DUPLICATE_ID",
                        spec.dataset,
                        location,
                        f"duplicate {spec.display_name} ID {record_id!r}",
                        record_id,
                        {"first_location": seen[record_id].location},
                        "Do not merge or rename records automatically; resolve the source identity explicitly.",
                    )
                else:
                    seen[record_id] = ref
                self.rows_by_kind[spec.kind].append(ref)
                self.ids_by_kind[spec.kind].add(record_id)
                stable_id = raw_row.get("stable_id")
                if stable_id is not None and str(stable_id) != record_id:
                    self.add(
                        "WARNING",
                        "STABLE_ID_MISMATCH",
                        spec.dataset,
                        location,
                        "stable_id does not equal the catalog id",
                        record_id,
                        {"id": record_id, "stable_id": stable_id},
                        "Confirm whether the two identifiers intentionally represent different identity layers.",
                    )
                allowed_levels = EXPECTED_OBJECT_LEVELS.get(spec.kind)
                object_level = raw_row.get("object_level")
                if allowed_levels and object_level is not None and object_level not in allowed_levels:
                    self.add(
                        "ERROR",
                        "OBJECT_LEVEL_MISMATCH",
                        spec.dataset,
                        location,
                        f"object_level {object_level!r} contradicts the {spec.kind} catalog",
                        record_id,
                        {"allowed": sorted(allowed_levels)},
                    )
                prefixes = ID_PREFIX_RULES.get(spec.kind, ())
                if prefixes and not record_id.startswith(prefixes):
                    self.add(
                        "ERROR",
                        "MALFORMED_ID_PREFIX",
                        spec.dataset,
                        location,
                        f"ID {record_id!r} does not use an expected prefix",
                        record_id,
                        {"expected_prefixes": list(prefixes)},
                    )
                elif not (
                    ID_PATTERN.fullmatch(record_id)
                    or (spec.kind == "modern_admin1" and SOURCE_ID_PATTERN.fullmatch(record_id))
                ):
                    self.add(
                        "ERROR",
                        "MALFORMED_ID",
                        spec.dataset,
                        location,
                        f"ID {record_id!r} contains characters outside the repository ID alphabet",
                        record_id,
                    )

    def _target_ids(self, kinds: Iterable[str]) -> set[str]:
        result: set[str] = set()
        for kind in kinds:
            result.update(self.ids_by_kind.get(kind, set()))
        return result

    def _check_reference(
        self,
        ref: RecordRef,
        field: str,
        target_kinds: tuple[str, ...],
        allow_empty: bool,
        relation_label: str,
    ) -> None:
        if field not in ref.record:
            if not allow_empty:
                self.add(
                    "ERROR",
                    "REQUIRED_REFERENCE_FIELD_MISSING",
                    ref.dataset,
                    ref.location,
                    f"required {relation_label} field {field!r} is missing",
                    ref.record_id,
                )
            return
        value = ref.record.get(field)
        values = value if isinstance(value, list) else [value]
        targets = self._target_ids(target_kinds)
        for offset, candidate in enumerate(values):
            if is_empty_reference(candidate):
                if not allow_empty:
                    self.add(
                        "ERROR",
                        "EMPTY_FOREIGN_KEY",
                        ref.dataset,
                        f"{ref.location}.{field}[{offset}]" if isinstance(value, list) else f"{ref.location}.{field}",
                        f"required {relation_label} reference is empty",
                        ref.record_id,
                    )
                continue
            candidate_id = str(candidate)
            if candidate_id not in targets:
                placeholder = "placeholder" in candidate_id.casefold()
                self.add(
                    "WARNING" if placeholder else "ERROR",
                    "PLACEHOLDER_FOREIGN_KEY" if placeholder else "DANGLING_FOREIGN_KEY",
                    ref.dataset,
                    f"{ref.location}.{field}[{offset}]" if isinstance(value, list) else f"{ref.location}.{field}",
                    f"{relation_label} reference {candidate_id!r} does not resolve",
                    ref.record_id,
                    {"target_kinds": list(target_kinds), "placeholder": placeholder},
                    "Keep the unresolved reference in findings/TODO until the source identity is established.",
                )
    def _validate_references(self) -> None:
        for dataset, collection, field, target_kinds, allow_empty, relation_label in REFERENCE_RULES:
            for ref in self._refs_for(dataset, collection):
                self._check_reference(ref, field, target_kinds, allow_empty, relation_label)

        for ref in self._refs_for("countries.json", "countries"):
            self._check_reference(ref, "capital_city_id", ("city",), True, "capital city")
            self._check_reference(ref, "geometry_feature_ids", ("modern_coastline",), False, "country geometry")

        for ref in self._refs_for("historical/political_units_1900.json", "units"):
            self._check_reference(ref, "geometry_feature_id", ("historical_geometry",), False, "historical geometry")
            self._check_reference(ref, "flag_id", ("historical_flag",), False, "historical flag")
            self._check_reference(ref, "controller_id", ("historical_entity",), True, "historical controller")

        for ref in self._refs_for("historical/major_state_profiles_1900.json", "profiles"):
            self._check_reference(
                ref,
                "entity_id",
                ("historical_entity", "historical_unit", "country", "major_state_profile"),
                False,
                "historical profile entity",
            )

        for ref in self._refs_for("historical/historical_admin1_1900.json", "countries"):
            self._check_reference(
                ref,
                "entity_id",
                ("historical_entity", "historical_unit", "country"),
                False,
                "historical admin1 entity",
            )

        for ref in self._refs_for("historical/major_economy_polity_crosswalk_1900.json", "records"):
            self._check_reference(
                ref,
                "economy_entity_id",
                ("historical_entity", "historical_unit", "country", "major_state_profile"),
                False,
                "economy entity",
            )
            self._check_reference(ref, "polity_ids", ("historical_unit",), False, "mapped political unit")

    def _validate_dynamic_references(self) -> None:
        activity_ids = self._target_ids(("activity",))
        activity = self.documents.get("world_activity.json", {})
        items = activity.get("items", []) if isinstance(activity, Mapping) else []
        if isinstance(activity, Mapping):
            latest_id = activity.get("default_summary", {}).get("latest_id") if isinstance(activity.get("default_summary"), Mapping) else None
            if latest_id and str(latest_id) not in {str(row.record_id) for row in self._refs_for("world_activity.json", "items")}:
                self.add("ERROR", "DANGLING_ACTIVITY_ID", "world_activity.json", "world_activity.json:default_summary.latest_id", "latest activity ID does not resolve")
        for ref in self._refs_for("world_activity.json", "items"):
            location_type = str(ref.record.get("location_type", ""))
            location_targets = {
                "country": ("country",),
                "region": ("region",),
                "city": ("city",),
                "administrative_unit": ("administrative_unit",),
            }.get(location_type)
            if location_targets:
                self._check_reference(ref, "location_id", location_targets, False, f"{location_type} location")
            object_type = str(ref.record.get("object_type", ""))
            object_targets = {
                "country": ("country",),
                "region": ("region",),
                "city": ("city",),
                "institution": ("institution",),
                "organization": ("organization",),
            }.get(object_type)
            if object_targets:
                self._check_reference(ref, "object_id", object_targets, False, f"{object_type} object")
            self._check_reference(ref, "region_id", ("region",), False, "activity region")
            self._check_reference(ref, "organization_ids", ("organization",), True, "activity organization")
            self._check_reference(ref, "institution_ids", ("institution",), True, "activity institution")
            self._check_reference(ref, "city_ids", ("city",), True, "activity city")

        if not isinstance(items, list):
            self.add("ERROR", "ACTIVITY_COLLECTION_TYPE", "world_activity.json", "world_activity.json:items", "items must be an array")

        index = self.documents.get("city_detail/index.json", {})
        if isinstance(index, Mapping):
            country_codes = set()
            for ref in self._refs_for("city_detail/index.json", "countries"):
                code = ref.record_id
                country_codes.add(code)
                for shard_index, shard in enumerate(ref.record.get("shards", [])):
                    if not isinstance(shard, Mapping):
                        self.add("ERROR", "CITY_DETAIL_SHARD_TYPE", ref.dataset, f"{ref.location}.shards[{shard_index}]", "shard entry must be an object", ref.record_id)
                        continue
                    shard_path = str(shard.get("path", ""))
                    if not shard_path or Path(shard_path).is_absolute() or ".." in Path(shard_path).parts:
                        self.add("ERROR", "CITY_DETAIL_SHARD_PATH", ref.dataset, f"{ref.location}.shards[{shard_index}].path", "shard path is not a safe relative path", ref.record_id)
                        continue
                    normalized = Path("city_detail") / Path(shard_path)
                    if normalized.as_posix() not in self.documents:
                        self.add("ERROR", "DANGLING_CITY_DETAIL_SHARD", ref.dataset, f"{ref.location}.shards[{shard_index}].path", f"shard file {shard_path!r} does not exist", ref.record_id)
                    else:
                        shard_document = self.documents[normalized.as_posix()]
                        self._validate_city_detail_shard(ref, shard_document, normalized.as_posix(), shard)
            totals = index.get("totals", {})
            if isinstance(totals, Mapping):
                actual_shards = len([name for name in self.documents if name.startswith("city_detail/") and name not in {"city_detail/index.json", "city_detail/LICENSE.json"}])
                actual_records = sum(len(list(iter_collection(document, "cities"))) for name, document in self.documents.items() if name.startswith("city_detail/") and name not in {"city_detail/index.json", "city_detail/LICENSE.json"})
                if totals.get("shards") != actual_shards:
                    self.add("WARNING", "CITY_DETAIL_SHARD_COUNT", "city_detail/index.json", "city_detail/index.json:totals.shards", "index shard total differs from files on disk", evidence={"declared": totals.get("shards"), "actual": actual_shards})
                if totals.get("records") != actual_records:
                    self.add("WARNING", "CITY_DETAIL_RECORD_COUNT", "city_detail/index.json", "city_detail/index.json:totals.records", "index record total differs from shard records on disk", evidence={"declared": totals.get("records"), "actual": actual_records})

    def _validate_city_detail_shard(
        self,
        index_ref: RecordRef,
        document: Mapping[str, Any],
        dataset: str,
        shard_metadata: Mapping[str, Any],
    ) -> None:
        expected_code = index_ref.record_id
        actual_code = str(document.get("country_code", ""))
        if actual_code != expected_code:
            self.add("ERROR", "CITY_DETAIL_COUNTRY_MISMATCH", dataset, dataset, "shard country_code differs from index entry", evidence={"index": expected_code, "shard": actual_code})
        expected_shard = str(shard_metadata.get("id", ""))
        actual_shard = str(document.get("shard_id", ""))
        if expected_shard and expected_shard != actual_shard:
            self.add("ERROR", "CITY_DETAIL_SHARD_ID_MISMATCH", dataset, dataset, "shard_id differs from index entry", evidence={"index": expected_shard, "shard": actual_shard})
        rows = list(iter_collection(document, "cities"))
        declared_count = document.get("count")
        if declared_count != len(rows):
            self.add("ERROR", "CITY_DETAIL_COUNT_MISMATCH", dataset, dataset, "shard count differs from rows on disk", evidence={"declared": declared_count, "actual": len(rows)})
        seen: set[str] = set()
        for index, _, row in rows:
            record_id = str(row.get("id", ""))
            if record_id in seen:
                self.add("ERROR", "DUPLICATE_ID", dataset, f"{dataset}:cities[{index}].id", "duplicate city-detail ID", record_id)
            seen.add(record_id)
            self._validate_coordinate_value(dataset, f"{dataset}:cities[{index}].lon_lat", row.get("lon_lat"), True, record_id, True)

    def _refs_for(self, dataset: str, collection: str) -> list[RecordRef]:
        return [ref for refs in self.rows_by_kind.values() for ref in refs if ref.dataset == dataset and ref.collection == collection]

    def _validate_coordinate_value(
        self,
        dataset: str,
        location: str,
        value: Any,
        lon_lat: bool,
        record_id: str,
        required: bool,
    ) -> None:
        if value is None:
            if required:
                self.add("ERROR", "MISSING_COORDINATES", dataset, location, "required coordinate field is missing", record_id)
            return
        if not coordinate_pair(value):
            self.add("ERROR", "INVALID_COORDINATES", dataset, location, "coordinate must be a finite two-number array", record_id)
            return
        x, y = float(value[0]), float(value[1])
        if lon_lat and not (-180.0 <= x <= 180.0 and -90.0 <= y <= 90.0):
            self.add("ERROR", "COORDINATE_OUT_OF_RANGE", dataset, location, "longitude/latitude is outside the valid range", record_id, {"lon": x, "lat": y})

    def _validate_coordinates(self) -> None:
        for dataset, collection, field, lon_lat, required in COORDINATE_FIELDS:
            for ref in self._refs_for(dataset, collection):
                self._validate_coordinate_value(dataset, f"{ref.location}.{field}", ref.record.get(field), lon_lat, ref.record_id, required)

        for ref in self._refs_for("shipping_routes.json", "routes"):
            waypoints = ref.record.get("waypoints_lon_lat")
            if waypoints is None:
                self.add("ERROR", "MISSING_COORDINATES", ref.dataset, f"{ref.location}.waypoints_lon_lat", "shipping route has no waypoint geometry", ref.record_id)
                continue
            for index, pair in enumerate(waypoints if isinstance(waypoints, list) else [waypoints]):
                self._validate_coordinate_value(
                    ref.dataset,
                    f"{ref.location}.waypoints_lon_lat[{index}]",
                    pair,
                    True,
                    ref.record_id,
                    True,
                )

        for ref in self._refs_for("historical/cshapes_1900_snapshot.json", "features"):
            capital = ref.record.get("capital")
            if isinstance(capital, Mapping):
                self._validate_coordinate_value(ref.dataset, f"{ref.location}.capital", [capital.get("lon"), capital.get("lat")], True, ref.record_id, True)
            else:
                self.add("WARNING", "HISTORICAL_CAPITAL_MISSING", ref.dataset, f"{ref.location}.capital", "historical geometry feature has no capital coordinate", ref.record_id)

        for ref in self._refs_for("historical_political_entities_1900.json", "conflicts"):
            paths = ref.record.get("paths", [])
            if not isinstance(paths, list) or not paths:
                self.add("ERROR", "EMPTY_CONFLICT_PATHS", ref.dataset, f"{ref.location}.paths", "conflict record has no paths", ref.record_id)
                continue
            for path_index, path in enumerate(paths):
                if not isinstance(path, list) or len(path) < 2:
                    self.add("ERROR", "INVALID_CONFLICT_PATH", ref.dataset, f"{ref.location}.paths[{path_index}]", "conflict path must contain at least two points", ref.record_id)
                    continue
                for point_index, point in enumerate(path):
                    self._validate_coordinate_value(ref.dataset, f"{ref.location}.paths[{path_index}][{point_index}]", point, True, ref.record_id, True)

    def _geometry_rings(self, dataset: str, collection: str, ref: RecordRef) -> Iterator[tuple[str, list[list[float]], bool]]:
        row = ref.record
        if dataset == "world_coastlines.json" and collection == "features":
            for polygon_index, polygon in enumerate(row.get("polygons", [])):
                if not isinstance(polygon, Mapping):
                    continue
                for ring_name in ("outer", "holes"):
                    rings = polygon.get(ring_name, [])
                    ring_values = rings if ring_name == "holes" else [rings]
                    for ring_index, ring in enumerate(ring_values):
                        if isinstance(ring, list):
                            yield f"{ref.location}.polygons[{polygon_index}].{ring_name}[{ring_index}]", ring, True
        elif dataset == "world_admin1.json" and collection == "regions":
            for polygon_index, ring in enumerate(row.get("polygons", [])):
                if isinstance(ring, list):
                    yield f"{ref.location}.polygons[{polygon_index}]", ring, True
        elif dataset == "regions.json" and collection == "administrative_units":
            for geometry_index, geometry in enumerate(row.get("geometry", [])):
                if not isinstance(geometry, Mapping):
                    continue
                for ring_name in ("outer", "holes"):
                    rings = geometry.get(ring_name, [])
                    ring_values = rings if ring_name == "holes" else [rings]
                    for ring_index, ring in enumerate(ring_values):
                        if isinstance(ring, list):
                            yield f"{ref.location}.geometry[{geometry_index}].{ring_name}[{ring_index}]", ring, True
        elif dataset == "historical/cshapes_1900_snapshot.json" and collection == "features":
            geometry = row.get("geometry", {})
            coordinates = geometry.get("coordinates") if isinstance(geometry, Mapping) else None
            for ring_index, ring in enumerate(flatten_rings(coordinates)):
                yield f"{ref.location}.geometry.coordinates[{ring_index}]", ring, True
        elif dataset == "map_geometry_cache.json":
            for path, value in self._projected_outer_rings(row, ref.location):
                yield path, value, False

    def _projected_outer_rings(self, value: Any, prefix: str) -> Iterator[tuple[str, list[list[float]]]]:
        if isinstance(value, Mapping):
            for key, child in value.items():
                child_path = f"{prefix}.{key}"
                if key == "outer" and isinstance(child, list):
                    yield child_path, child
                else:
                    yield from self._projected_outer_rings(child, child_path)
        elif isinstance(value, list):
            for index, child in enumerate(value):
                yield from self._projected_outer_rings(child, f"{prefix}[{index}]")

    def _validate_rings_for_ref(self, ref: RecordRef, lon_lat: bool) -> None:
        rings = list(self._geometry_rings(ref.dataset, ref.collection, ref))
        if not rings:
            self.add("ERROR", "EMPTY_GEOMETRY", ref.dataset, f"{ref.location}.geometry", "geometry-bearing record has no rings", ref.record_id)
            return
        all_points: list[list[float]] = []
        ring_count = 0
        nonzero_count = 0
        duplicate_hashes: dict[str, str] = {}
        for location, raw_ring, _ in rings:
            ring_count += 1
            points = list(iter_coordinate_pairs(raw_ring))
            normalized = [[point[0], point[1]] for point in points]
            all_points.extend(normalized)
            if len(points) < 3:
                self.add("ERROR", "INVALID_RING", ref.dataset, location, "ring has fewer than three coordinate points", ref.record_id)
                continue
            for point in points:
                if lon_lat and not (-180.0 <= point[0] <= 180.0 and -90.0 <= point[1] <= 90.0):
                    self.add("ERROR", "GEOMETRY_COORDINATE_OUT_OF_RANGE", ref.dataset, location, "geometry coordinate is outside the longitude/latitude range", ref.record_id, {"point": list(point)})
            if points[0] != points[-1]:
                self.add("WARNING", "RING_NOT_CLOSED", ref.dataset, location, "polygon ring is not explicitly closed", ref.record_id)
            area = ring_area(points)
            if abs(area) <= 1e-12:
                self.add("ERROR", "ZERO_AREA_GEOMETRY", ref.dataset, location, "polygon ring has zero area", ref.record_id)
            else:
                nonzero_count += 1
            if len(points) <= 300 and ring_self_intersects(points):
                self.add("ERROR", "SELF_INTERSECTING_RING", ref.dataset, location, "polygon ring self-intersects", ref.record_id)
            digest = hashlib.sha256(canonical_ring(points).encode("utf-8")).hexdigest()
            if digest in duplicate_hashes:
                self.add("WARNING", "DUPLICATE_POLYGON", ref.dataset, location, "polygon ring is byte/geometry-equivalent to another ring in the audit scope", ref.record_id, {"first_location": duplicate_hashes[digest]})
            else:
                duplicate_hashes[digest] = location
        metadata = {
            "dataset": ref.dataset,
            "collection": ref.collection,
            "record_id": ref.record_id,
            "location": ref.location,
            "ring_count": ring_count,
            "nonzero_ring_count": nonzero_count,
            "point_count": len(all_points),
            "bbox": bbox_for_points(all_points),
            "coordinate_system": "lon_lat" if lon_lat else "projected",
        }
        self.geometry_metadata.append(metadata)

    def _validate_geometries(self) -> None:
        geometry_specs = (
            ("world_coastlines.json", "features", True),
            ("world_admin1.json", "regions", True),
            ("regions.json", "administrative_units", True),
            ("historical/cshapes_1900_snapshot.json", "features", True),
        )
        for dataset, collection, lon_lat in geometry_specs:
            for ref in self._refs_for(dataset, collection):
                self._validate_rings_for_ref(ref, lon_lat)
        # The cache stores projected triangulation boundaries.  They are not
        # source GeoJSON rings: LODs intentionally repeat geometry and their
        # outer vertex lists need not be closed.  Index/reference checks below
        # validate the cache without misclassifying generated triangulation.
    def _validate_geometry_cache(self) -> None:
        cache = self.documents.get("map_geometry_cache.json")
        if not isinstance(cache, Mapping):
            return
        country_ids = self.ids_by_kind.get("country", set())
        admin_ids = self.ids_by_kind.get("administrative_unit", set())
        region_ids = self.ids_by_kind.get("region", set())
        coastline_ids = self.ids_by_kind.get("modern_coastline", set())
        for lod_name, entries in (cache.get("country_lods", {}) or {}).items() if isinstance(cache.get("country_lods"), Mapping) else []:
            self._validate_cache_index(lod_name, entries, "country_id", country_ids, "country", "map_geometry_cache.json")
            for index, entry in enumerate(entries if isinstance(entries, list) else []):
                if not isinstance(entry, Mapping):
                    continue
                source_index = entry.get("source_index")
                if isinstance(source_index, int) and not (0 <= source_index < len(self.rows_by_kind.get("modern_coastline", []))):
                    self.add("ERROR", "GEOMETRY_SOURCE_INDEX", "map_geometry_cache.json", f"map_geometry_cache.json:country_lods.{lod_name}[{index}].source_index", "country geometry source_index is outside the coastline catalog")
        for lod_name, entries in (cache.get("administrative_lods", {}) or {}).items() if isinstance(cache.get("administrative_lods"), Mapping) else []:
            self._validate_cache_index(lod_name, entries, "unit_id", admin_ids, "administrative unit", "map_geometry_cache.json")
        for entry_index, entry in enumerate(cache.get("macro_regions", []) if isinstance(cache.get("macro_regions"), list) else []):
            if isinstance(entry, Mapping):
                region_id = str(entry.get("region_id", ""))
                if region_id not in region_ids:
                    self.add("ERROR", "DANGLING_FOREIGN_KEY", "map_geometry_cache.json", f"map_geometry_cache.json:macro_regions[{entry_index}].region_id", "macro-region geometry points to an unknown region", region_id)
        transport = cache.get("transport", {})
        if isinstance(transport, Mapping):
            for transport_kind, entries in transport.items():
                target_kind = {"rail": "rail", "road": "road", "shipping": "shipping"}.get(str(transport_kind))
                if not target_kind:
                    continue
                target_ids = self.ids_by_kind.get(target_kind, set())
                for index, entry in enumerate(entries if isinstance(entries, list) else []):
                    if isinstance(entry, Mapping) and str(entry.get("id", "")) not in target_ids:
                        self.add("ERROR", "DANGLING_FOREIGN_KEY", "map_geometry_cache.json", f"map_geometry_cache.json:transport.{transport_kind}[{index}].id", "transport geometry points to an unknown source link", str(entry.get("id", "")))
        anchors = cache.get("anchors", {})
        anchor_targets = {
            "countries": "country",
            "regions": "region",
            "administrative_units": "administrative_unit",
            "cities": "city",
            "ports": "port",
            "organizations": "organization",
            "institutions": "institution",
        }
        if isinstance(anchors, Mapping):
            for anchor_kind, target_kind in anchor_targets.items():
                values = anchors.get(anchor_kind, {})
                if not isinstance(values, Mapping):
                    continue
                for anchor_id in values:
                    if str(anchor_id) not in self.ids_by_kind.get(target_kind, set()):
                        self.add("ERROR", "DANGLING_ANCHOR_ID", "map_geometry_cache.json", f"map_geometry_cache.json:anchors.{anchor_kind}.{anchor_id}", "geometry anchor points to an unknown catalog entity", str(anchor_id))
        projection = cache.get("projection")
        if isinstance(projection, Mapping):
            world_size = projection.get("world_size")
            if not coordinate_pair(world_size) or world_size[0] <= 0 or world_size[1] <= 0:
                self.add("ERROR", "PROJECTION_WORLD_SIZE", "map_geometry_cache.json", "map_geometry_cache.json:projection.world_size", "projected world_size must be two positive finite numbers")
        thresholds = cache.get("lod_thresholds")
        if isinstance(thresholds, Mapping):
            values = [thresholds.get(f"lod{index}_max") for index in range(5)]
            numeric = [float(value) for value in values if number_is_finite(value)]
            if len(numeric) != len(values) or numeric != sorted(numeric):
                self.add("ERROR", "LOD_THRESHOLD_ORDER", "map_geometry_cache.json", "map_geometry_cache.json:lod_thresholds", "LOD thresholds must be finite and monotonically increasing")

    def _validate_cache_index(
        self,
        lod_name: str,
        entries: Any,
        id_field: str,
        target_ids: set[str],
        target_label: str,
        dataset: str,
    ) -> None:
        if not isinstance(entries, list):
            self.add("ERROR", "GEOMETRY_CACHE_COLLECTION_TYPE", dataset, f"{dataset}:{lod_name}", "geometry cache LOD must be an array")
            return
        seen: set[str] = set()
        for index, entry in enumerate(entries):
            if not isinstance(entry, Mapping):
                self.add("ERROR", "GEOMETRY_CACHE_RECORD_TYPE", dataset, f"{dataset}:{lod_name}[{index}]", "geometry cache entry must be an object")
                continue
            record_id = str(entry.get(id_field, ""))
            if record_id in seen:
                self.add("ERROR", "DUPLICATE_ID", dataset, f"{dataset}:{lod_name}[{index}].{id_field}", f"duplicate {target_label} geometry cache ID", record_id)
            seen.add(record_id)
            if record_id not in target_ids:
                self.add("ERROR", "DANGLING_FOREIGN_KEY", dataset, f"{dataset}:{lod_name}[{index}].{id_field}", f"geometry cache points to an unknown {target_label}", record_id)
        missing = sorted(target_ids - seen)
        if missing:
            self.add("WARNING", "GEOMETRY_CACHE_COVERAGE", dataset, f"{dataset}:{lod_name}", f"geometry cache LOD is missing {len(missing)} {target_label} entries", evidence={"missing_sample": missing[:20]})

    def _validate_metadata_consistency(self) -> None:
        countries = self._refs_for("countries.json", "countries")
        coastlines = self._refs_for("world_coastlines.json", "features")
        country_iso = {
            str(value).upper()
            for ref in countries
            for value in (
                ref.record.get("geometry_iso_a3", [])
                if isinstance(ref.record.get("geometry_iso_a3"), list)
                else [ref.record.get("geometry_iso_a3")]
            )
            if value
        }
        coastline_iso = {str(ref.record.get("iso_a3", "")).upper() for ref in coastlines if ref.record.get("iso_a3")}
        for iso in sorted(country_iso - coastline_iso):
            self.add("WARNING", "GEOMETRY_ISO_MISSING", "countries.json", "countries.json:countries", "country geometry_iso_a3 has no matching coastline ISO", evidence={"iso_a3": iso})
        for iso in sorted(coastline_iso - country_iso):
            self.add("WARNING", "CATALOG_ISO_MISSING", "world_coastlines.json", "world_coastlines.json:features", "coastline ISO is not represented by a country geometry_iso_a3", evidence={"iso_a3": iso})

        for ref in countries:
            geometry_ids = ref.record.get("geometry_feature_ids")
            if isinstance(geometry_ids, list) and len(geometry_ids) != len(set(map(str, geometry_ids))):
                self.add("ERROR", "DUPLICATE_GEOMETRY_REFERENCE", ref.dataset, f"{ref.location}.geometry_feature_ids", "country has duplicate geometry feature references", ref.record_id)

        for ref in self._refs_for("historical/cshapes_1900_snapshot.json", "features"):
            if not isinstance(ref.record.get("geometry"), Mapping):
                self.add("ERROR", "HISTORICAL_GEOMETRY_MISSING", ref.dataset, f"{ref.location}.geometry", "historical geometry feature has no geometry", ref.record_id)
        for document_name, declared_key, actual_kind in (
            ("historical/cshapes_1900_snapshot.json", "feature_count", "historical_geometry"),
            ("historical/political_units_1900.json", "unit_count", "historical_unit"),
            ("historical/flags_1900.json", "record_count", "historical_flag"),
        ):
            document = self.documents.get(document_name, {})
            if isinstance(document, Mapping) and isinstance(document.get(declared_key), int):
                actual = len(self.rows_by_kind.get(actual_kind, []))
                if document[declared_key] != actual:
                    self.add("ERROR", "DECLARED_COUNT_MISMATCH", document_name, f"{document_name}:{declared_key}", "declared record count differs from parsed records", evidence={"declared": document[declared_key], "actual": actual})

        for ref in self._refs_for("historical_political_entities_1900.json", "entities"):
            for field in ("members", "core_members"):
                value = ref.record.get(field)
                if value is None:
                    continue
                if not isinstance(value, list):
                    self.add("ERROR", "HISTORICAL_MEMBER_TYPE", ref.dataset, f"{ref.location}.{field}", "historical membership field must be an array or null", ref.record_id)

    def _collection_inventory(self, spec: CatalogSpec) -> dict[str, Any]:
        refs = self._refs_for(spec.dataset, spec.collection)
        fields: dict[str, dict[str, Any]] = {}
        for ref in refs:
            for field, value in ref.record.items():
                if field.startswith("__"):
                    continue
                entry = fields.setdefault(field, {"present": 0, "types": Counter(), "examples": []})
                entry["present"] += 1
                entry["types"][type(value).__name__] += 1
                if len(entry["examples"]) < 3 and value not in (None, "", []):
                    entry["examples"].append(value)
        field_inventory: dict[str, Any] = {}
        total = len(refs)
        rule_fields = {rule[2] for rule in REFERENCE_RULES if rule[0] == spec.dataset and rule[1] == spec.collection}
        for field in sorted(fields):
            entry = fields[field]
            presence = entry["present"] / total if total else 0.0
            field_inventory[field] = {
                "presence_count": entry["present"],
                "presence_ratio": round(presence, 6),
                "required_candidate": total > 0 and entry["present"] == total,
                "optional_candidate": entry["present"] < total,
                "types": dict(sorted(entry["types"].items())),
                "examples": entry["examples"],
                "foreign_key_candidate": field in rule_fields,
                "source_or_history_candidate": bool(SOURCE_FIELD_PATTERN.search(field)),
            }
        return {
            "kind": spec.kind,
            "display_name": spec.display_name,
            "dataset": spec.dataset,
            "collection": spec.collection,
            "id_field": spec.id_field,
            "record_count": total,
            "id_samples": [ref.record_id for ref in refs[:10]],
            "field_inventory": field_inventory,
        }

    def _build_inventory(self) -> dict[str, Any]:
        specs = list(CATALOG_SPECS)
        for dataset in sorted(self.documents):
            if dataset.startswith("city_detail/") and dataset.endswith(".json") and dataset not in {"city_detail/index.json", "city_detail/LICENSE.json"}:
                specs.append(CatalogSpec(dataset, "cities", "city_detail_city", "id", "city-detail records"))
        collections = [self._collection_inventory(spec) for spec in specs if spec.dataset in self.documents]
        geometry_objects = len(self.geometry_metadata)
        counts = {
            "country_count": len(self.rows_by_kind.get("country", [])),
            "region_count": len(self.rows_by_kind.get("region", [])),
            "city_count": len(self.rows_by_kind.get("city", [])),
            "port_count": len(self.rows_by_kind.get("port", [])),
            "road_link_count": len(self.rows_by_kind.get("road", [])),
            "rail_link_count": len(self.rows_by_kind.get("rail", [])),
            "shipping_link_count": len(self.rows_by_kind.get("shipping", [])),
            "historical_political_entity_count": len(self.rows_by_kind.get("historical_entity", [])),
            "organization_count": len(self.rows_by_kind.get("organization", [])),
            "institution_count": len(self.rows_by_kind.get("institution", [])),
            "character_person_like_record_count": len(self.rows_by_kind.get("character", [])),
            "geometry_bearing_object_count": geometry_objects,
            "modern_city_detail_record_count": len(self.rows_by_kind.get("city_detail_city", [])),
        }
        schema_identifiers: dict[str, Any] = {}
        coordinate_fields: set[str] = set()
        source_fields: set[str] = set()
        for dataset, document in sorted(self.documents.items()):
            schema_identifiers[dataset] = {
                key: document[key]
                for key in ("schema_version", "schema_id")
                if key in document
            }
            for field_path in nested_field_names(document):
                leaf = field_path.rsplit(".", 1)[-1].replace("[]", "")
                if leaf in {"lon_lat", "label_anchor", "label_lon_lat", "waypoints_lon_lat", "coordinates", "capital", "paths", "start", "end", "outer", "rings", "polygons", "geometry"}:
                    coordinate_fields.add(f"{dataset}:{field_path}")
                if SOURCE_FIELD_PATTERN.search(leaf):
                    source_fields.add(f"{dataset}:{field_path}")
        foreign_keys = [
            {
                "dataset": dataset,
                "collection": collection,
                "field": field,
                "target_kinds": list(targets),
                "allow_empty": allow_empty,
                "relation": label,
            }
            for dataset, collection, field, targets, allow_empty, label in REFERENCE_RULES
        ]
        foreign_keys.extend(
            [
                {"dataset": "countries.json", "collection": "countries", "field": "capital_city_id", "target_kinds": ["city"], "allow_empty": True, "relation": "capital city"},
                {"dataset": "countries.json", "collection": "countries", "field": "geometry_feature_ids", "target_kinds": ["modern_coastline"], "allow_empty": False, "relation": "country geometry"},
                {"dataset": "historical/political_units_1900.json", "collection": "units", "field": "geometry_feature_id", "target_kinds": ["historical_geometry"], "allow_empty": False, "relation": "historical geometry"},
                {"dataset": "historical/political_units_1900.json", "collection": "units", "field": "flag_id", "target_kinds": ["historical_flag"], "allow_empty": False, "relation": "historical flag"},
            ]
        )
        return {
            "validator_schema_version": VALIDATOR_SCHEMA_VERSION,
            "source_tree": "data/world_map/**/*.json",
            "file_count": len(self.documents),
            "files": [
                {
                    "path": dataset,
                    "bytes": self.sizes.get(dataset, 0),
                    "root_keys": sorted(document.keys()) if isinstance(document, Mapping) else [],
                    "schema_identifier": schema_identifiers.get(dataset, {}),
                }
                for dataset, document in sorted(self.documents.items())
            ],
            "counts": counts,
            "schema_version_identifiers": schema_identifiers,
            "collections": sorted(collections, key=lambda item: (item["dataset"], item["collection"], item["kind"])),
            "foreign_keys": foreign_keys,
            "coordinate_fields": sorted(coordinate_fields),
            "source_and_historical_reference_fields": sorted(source_fields),
            "id_formats": {
                kind: {
                    "record_count": len(refs),
                    "samples": [ref.record_id for ref in refs[:10]],
                    "id_alphabet": "ASCII alphanumeric plus _ . : -",
                    "prefix_rule": list(ID_PREFIX_RULES.get(kind, ())),
                }
                for kind, refs in sorted(self.rows_by_kind.items())
            },
            "duplicate_ids_by_kind": {kind: sorted(set(ids)) for kind, ids in sorted(self.duplicate_ids.items())},
            "optional_vs_required_policy": "required_candidate means present in every parsed record; optional_candidate means presence varies. These are audit hints, not schema authority.",
        }

    def _country_dimension_status(self, count: int, applicable: bool = True, complete: bool = False) -> str:
        if not applicable:
            return "NOT_APPLICABLE"
        if count <= 0:
            return "MISSING"
        return "COMPLETE" if complete else "PARTIAL"

    def _build_coverage(self) -> dict[str, Any]:
        countries = self._refs_for("countries.json", "countries")
        focus_country = str(self.documents.get("regions.json", {}).get("focus_country_id", "")) if isinstance(self.documents.get("regions.json"), Mapping) else ""
        by_country: dict[str, list[RecordRef]] = defaultdict(list)
        for kind, field in (
            ("region", "parent_country_id"),
            ("administrative_unit", "parent_country_id"),
            ("city", "parent_country_id"),
            ("port", "parent_country_id"),
            ("organization", "country_id"),
            ("institution", "parent_country_id"),
            ("character", "nationality_id"),
        ):
            for ref in self.rows_by_kind.get(kind, []):
                country_id = str(ref.record.get(field, ""))
                if country_id:
                    by_country[country_id].append(ref)

        links_by_country: dict[str, Counter[str]] = defaultdict(Counter)
        city_country = {ref.record_id: str(ref.record.get("parent_country_id", "")) for ref in self.rows_by_kind.get("city", [])}
        port_country = {ref.record_id: str(ref.record.get("parent_country_id", "")) for ref in self.rows_by_kind.get("port", [])}
        for kind, from_field, to_field, lookup in (
            ("road", "from_city_id", "to_city_id", city_country),
            ("rail", "from_city_id", "to_city_id", city_country),
            ("shipping", "from_port_id", "to_port_id", port_country),
        ):
            for ref in self.rows_by_kind.get(kind, []):
                for field in (from_field, to_field):
                    country_id = lookup.get(str(ref.record.get(field, "")), "")
                    if country_id:
                        links_by_country[country_id][kind] += 1

        geometry_ids = {ref.record_id for ref in self.rows_by_kind.get("modern_coastline", [])}
        historical_entity_ids = self.ids_by_kind.get("historical_entity", set())
        historical_unit_ids = self.ids_by_kind.get("historical_unit", set())
        profile_aliases: dict[str, set[str]] = defaultdict(set)
        for ref in self.rows_by_kind.get("major_state_profile", []):
            entity_id = str(ref.record_id)
            for alias in ref.record.get("aliases", []) if isinstance(ref.record.get("aliases"), list) else []:
                profile_aliases[str(alias).upper()].add(entity_id)
        historical_members: dict[str, set[str]] = defaultdict(set)
        for ref in self.rows_by_kind.get("historical_entity", []):
            for member in ref.record.get("members", []) if isinstance(ref.record.get("members"), list) else []:
                historical_members[str(member).upper()].add(ref.record_id)

        rows: list[dict[str, Any]] = []
        for country_ref in countries:
            country_id = country_ref.record_id
            related = by_country.get(country_id, [])
            counts = Counter(ref.kind for ref in related)
            city_ids = {ref.record_id for ref in related if ref.kind == "city"}
            port_ids = {ref.record_id for ref in related if ref.kind == "port"}
            roads = links_by_country.get(country_id, Counter())
            geometry_refs = [str(item) for item in country_ref.record.get("geometry_feature_ids", []) if item]
            geometry_ok = bool(geometry_refs) and all(item in geometry_ids for item in geometry_refs)
            iso_values = [str(country_ref.record.get(key, "")).upper() for key in ("data_code", "geometry_iso_a3") if country_ref.record.get(key)]
            historical_matches = set()
            for candidate in (country_id, *iso_values):
                if candidate in historical_entity_ids or candidate in historical_unit_ids:
                    historical_matches.add(candidate)
                historical_matches.update(profile_aliases.get(str(candidate).upper(), set()))
                historical_matches.update(historical_members.get(str(candidate).upper(), set()))
            history_status = "COMPLETE" if len(historical_matches) == 1 else "AMBIGUOUS" if len(historical_matches) > 1 else "MISSING"
            macro_applicable = country_id == focus_country
            character_applicable = counts["character"] > 0 or country_id == focus_country
            dimensions = {
                "country_record": {"status": "COMPLETE", "count": 1},
                "regions": {"status": self._country_dimension_status(counts["region"], macro_applicable, counts["region"] > 0), "count": counts["region"], "scope": "gameplay macro regions; source focus_country_id"},
                "administrative_units": {"status": self._country_dimension_status(counts["administrative_unit"], macro_applicable, counts["administrative_unit"] > 0), "count": counts["administrative_unit"], "scope": "curated administrative units; source focus_country_id"},
                "cities": {"status": self._country_dimension_status(counts["city"]), "count": counts["city"], "scope": "curated city catalog, not exhaustive modern city detail shards"},
                "capital": {"status": "COMPLETE" if country_ref.record.get("capital_city_id") and str(country_ref.record.get("capital_city_id")) in city_ids else "MISSING", "count": 1 if country_ref.record.get("capital_city_id") else 0},
                "ports": {"status": self._country_dimension_status(counts["port"]), "count": counts["port"]},
                "road_connectivity": {"status": self._country_dimension_status(roads["road"]), "count": roads["road"]},
                "rail_connectivity": {"status": self._country_dimension_status(roads["rail"]), "count": roads["rail"]},
                "shipping_connectivity": {"status": self._country_dimension_status(roads["shipping"]), "count": roads["shipping"]},
                "geometry": {"status": "COMPLETE" if geometry_ok else "MISSING", "count": len(geometry_refs), "geometry_feature_ids": geometry_refs},
                "historical_1900_identity": {"status": history_status, "count": len(historical_matches), "matches": sorted(historical_matches)},
                "institutions": {"status": self._country_dimension_status(counts["institution"]), "count": counts["institution"]},
                "organizations": {"status": self._country_dimension_status(counts["organization"]), "count": counts["organization"]},
                "character_person_seed": {"status": self._country_dimension_status(counts["character"], character_applicable), "count": counts["character"], "scope": "static seed data is currently focused on the selected French scenario"},
            }
            rows.append({
                "entity_id": country_id,
                "display_name": country_ref.record.get("display_name_zh", country_ref.record.get("name", country_id)),
                "data_code": country_ref.record.get("data_code", ""),
                "dimensions": dimensions,
            })

        historical_rows: list[dict[str, Any]] = []
        for ref in self.rows_by_kind.get("major_state_profile", []):
            entity_id = ref.record_id
            unit_matches = [unit.record_id for unit in self.rows_by_kind.get("historical_unit", []) if str(unit.record.get("controller_id", "")) == entity_id or unit.record_id == entity_id]
            geometry_count = sum(1 for unit in self.rows_by_kind.get("historical_unit", []) if unit.record_id in unit_matches and unit.record.get("geometry_feature_id"))
            historical_rows.append({
                "entity_id": entity_id,
                "rank": ref.record.get("rank"),
                "aliases": ref.record.get("aliases", []),
                "dimensions": {
                    "major_profile": {"status": "COMPLETE", "count": 1},
                    "political_units": {"status": "COMPLETE" if unit_matches else "MISSING", "count": len(unit_matches)},
                    "historical_geometry": {"status": "COMPLETE" if geometry_count else "MISSING", "count": geometry_count},
                    "historical_admin1_detail": {"status": "COMPLETE" if any(str(item.record.get("entity_id", "")) == entity_id for item in self.rows_by_kind.get("historical_admin1", [])) else "MISSING", "count": sum(1 for item in self.rows_by_kind.get("historical_admin1", []) if str(item.record.get("entity_id", "")) == entity_id)},
                },
            })
        return {
            "schema_version": 1,
            "scope": {
                "current_country_catalog": len(rows),
                "major_historical_profiles": len(historical_rows),
                "macro_region_focus_country": focus_country,
                "status_semantics": {
                    "COMPLETE": "mechanically present and resolving for this dimension",
                    "PARTIAL": "some records exist; exhaustiveness is not established",
                    "MISSING": "no record was found in the current repository sources",
                    "NOT_APPLICABLE": "current schema explicitly scopes this dimension elsewhere",
                    "AMBIGUOUS": "more than one mechanically plausible historical match exists",
                },
            },
            "countries": rows,
            "major_historical_entities": historical_rows,
        }

    def _build_staging_candidates(self, inventory: Mapping[str, Any]) -> dict[str, Any]:
        indexes: dict[str, Any] = {}

        def group_by_country(kind: str, field: str) -> dict[str, list[str]]:
            grouped: dict[str, list[str]] = defaultdict(list)
            for ref in self.rows_by_kind.get(kind, []):
                country_id = str(ref.record.get(field, ""))
                if country_id:
                    grouped[country_id].append(ref.record_id)
            return {key: sorted(values) for key, values in sorted(grouped.items())}

        indexes["country_to_regions"] = group_by_country("region", "parent_country_id")
        indexes["country_to_administrative_units"] = group_by_country("administrative_unit", "parent_country_id")
        indexes["country_to_cities"] = group_by_country("city", "parent_country_id")
        indexes["country_to_ports"] = group_by_country("port", "parent_country_id")
        indexes["country_to_organizations"] = group_by_country("organization", "country_id")
        indexes["country_to_institutions"] = group_by_country("institution", "parent_country_id")
        indexes["country_to_characters"] = group_by_country("character", "nationality_id")

        def reverse_by_field(kind: str, field: str) -> dict[str, list[str]]:
            grouped: dict[str, list[str]] = defaultdict(list)
            for ref in self.rows_by_kind.get(kind, []):
                value = ref.record.get(field)
                values = value if isinstance(value, list) else [value]
                for item in values:
                    if not is_empty_reference(item):
                        grouped[str(item)].append(ref.record_id)
            return {key: sorted(values) for key, values in sorted(grouped.items())}

        indexes["city_to_ports"] = reverse_by_field("port", "city_id")
        indexes["city_to_roads"] = self._link_reverse_index("road", "from_city_id", "to_city_id")
        indexes["city_to_rails"] = self._link_reverse_index("rail", "from_city_id", "to_city_id")
        indexes["port_to_shipping_routes"] = self._link_reverse_index("shipping", "from_port_id", "to_port_id")
        indexes["region_to_institutions"] = reverse_by_field("region", "institution_ids")
        indexes["institution_to_organizations"] = reverse_by_field("organization", "institution_id")
        indexes["institution_to_characters"] = reverse_by_field("character", "institution_id")
        organization_to_characters: dict[str, list[str]] = defaultdict(list)
        for character_ref in self.rows_by_kind.get("character", []):
            for field in ("employer_id", "school_id", "union_id"):
                value = character_ref.record.get(field)
                if not is_empty_reference(value):
                    organization_to_characters[str(value)].append(character_ref.record_id)
        indexes["organization_to_characters"] = {
            key: sorted(set(values))
            for key, values in sorted(organization_to_characters.items())
        }

        geometry_index = {
            ref.record_id: [str(item) for item in ref.record.get("geometry_feature_ids", []) if item]
            for ref in self.rows_by_kind.get("country", [])
        }
        indexes["country_to_geometry_features"] = dict(sorted(geometry_index.items()))
        indexes["historical_unit_to_geometry"] = {
            ref.record_id: str(ref.record.get("geometry_feature_id", ""))
            for ref in self.rows_by_kind.get("historical_unit", [])
            if ref.record.get("geometry_feature_id")
        }
        indexes["historical_unit_to_flag"] = {
            ref.record_id: str(ref.record.get("flag_id", ""))
            for ref in self.rows_by_kind.get("historical_unit", [])
            if ref.record.get("flag_id")
        }

        return {
            "schema_version": 1,
            "policy": "derived-only staging; no authoritative source JSON is overwritten",
            "source_documents": sorted(self.documents),
            "derived_indexes": indexes,
            "geometry_metadata": sorted(self.geometry_metadata, key=lambda item: (item["dataset"], item["location"])),
            "data_counts": dict(inventory.get("counts", {})),
            "candidate_actions": [
                {
                    "kind": "reverse_index",
                    "status": "safe_to_generate",
                    "examples": ["country_to_cities", "city_to_roads", "historical_unit_to_geometry"],
                    "basis": "forward references already present in repository source files",
                },
                {
                    "kind": "derived_geometry_metadata",
                    "status": "safe_to_generate",
                    "basis": "bounding boxes, ring counts, and point counts are calculated directly from existing geometry",
                },
            ],
        }

    def _link_reverse_index(self, kind: str, from_field: str, to_field: str) -> dict[str, list[str]]:
        grouped: dict[str, list[str]] = defaultdict(list)
        for ref in self.rows_by_kind.get(kind, []):
            for field in (from_field, to_field):
                value = str(ref.record.get(field, ""))
                if value:
                    grouped[value].append(ref.record_id)
        return {key: sorted(set(values)) for key, values in sorted(grouped.items())}

    def _build_normalization_candidates(self) -> dict[str, Any]:
        candidates: list[dict[str, Any]] = []
        for dataset, document in sorted(self.documents.items()):
            for path in self._string_paths(document):
                value = path[2]
                if value != value.strip() or "  " in value:
                    candidates.append({
                        "kind": "whitespace",
                        "dataset": dataset,
                        "location": path[0],
                        "current": value,
                        "candidate": " ".join(value.strip().split()),
                        "safe": True,
                    })
        for kind in ("country", "city", "region", "organization", "institution"):
            groups: dict[str, list[RecordRef]] = defaultdict(list)
            for ref in self.rows_by_kind.get(kind, []):
                name = ref.record.get("name", ref.record.get("display_name_zh", ""))
                if isinstance(name, str) and name.strip():
                    groups[" ".join(name.casefold().split())].append(ref)
            for normalized, refs in sorted(groups.items()):
                if len({ref.record_id for ref in refs}) > 1:
                    candidates.append({
                        "kind": "duplicate_literal_alias_candidate",
                        "catalog": kind,
                        "normalized_name": normalized,
                        "record_ids": sorted({ref.record_id for ref in refs}),
                        "safe": False,
                        "reason": "same normalized display name is not proof of semantic identity",
                    })
        if not candidates:
            candidates.append({
                "kind": "none",
                "safe": True,
                "reason": "No mechanically safe normalization candidate was found; authoritative data remains unchanged.",
            })
        return {
            "schema_version": 1,
            "policy": "candidate report only; no normalization is applied automatically",
            "candidates": candidates,
        }

    def _string_paths(self, value: Any, prefix: str = "") -> Iterator[tuple[str, str, str]]:
        if isinstance(value, Mapping):
            for key, child in value.items():
                path = f"{prefix}.{key}" if prefix else str(key)
                if isinstance(child, str):
                    yield path, str(key), child
                else:
                    yield from self._string_paths(child, path)
        elif isinstance(value, list):
            for index, child in enumerate(value):
                yield from self._string_paths(child, f"{prefix}[{index}]")


def render_markdown(result: Mapping[str, Any]) -> str:
    summary = result.get("summary", {})
    inventory = result.get("inventory", {})
    counts = inventory.get("counts", {})
    findings = result.get("findings", [])
    severity_counts = summary.get("severity_counts", {})
    lines = [
        "# WWO World Data Foundation — Batch 1 Audit",
        "",
        "This report is generated from `data/world_map/**/*.json` by the read-only validator.",
        "",
        "## Inventory",
        "",
        f"- Files: {inventory.get('file_count', 0)}",
        f"- Countries: {counts.get('country_count', 0)}",
        f"- Regions: {counts.get('region_count', 0)}",
        f"- Curated cities: {counts.get('city_count', 0)}",
        f"- Ports: {counts.get('port_count', 0)}",
        f"- Roads / rails / shipping: {counts.get('road_link_count', 0)} / {counts.get('rail_link_count', 0)} / {counts.get('shipping_link_count', 0)}",
        f"- Historical political entities: {counts.get('historical_political_entity_count', 0)}",
        f"- Organizations / institutions / characters: {counts.get('organization_count', 0)} / {counts.get('institution_count', 0)} / {counts.get('character_person_like_record_count', 0)}",
        f"- Geometry-bearing catalog objects: {counts.get('geometry_bearing_object_count', 0)}",
        f"- Modern city-detail records: {counts.get('modern_city_detail_record_count', 0)}",
        "",
        "## Findings",
        "",
        f"- Total: {summary.get('finding_count', 0)}",
        f"- ERROR / WARNING / INFO: {severity_counts.get('ERROR', 0)} / {severity_counts.get('WARNING', 0)} / {severity_counts.get('INFO', 0)}",
        "",
    ]
    if findings:
        lines.extend(["| Severity | Code | Location | Message |", "|---|---|---|---|"])
        for finding in findings:
            message = str(finding.get("message", "")).replace("|", "\\|").replace("\n", " ")
            lines.append(f"| {finding.get('severity', '')} | {finding.get('code', '')} | `{finding.get('location', '')}` | {message} |")
    else:
        lines.append("No findings.")
    lines.extend(
        [
            "",
            "## Staging",
            "",
            "Derived reverse indexes and geometry metadata are written only to `staging_candidates.json` when an output directory is requested.",
            "",
            "## Authoritative data",
            "",
            "Production authoritative data modified: NO.",
            "",
        ]
    )
    return "\n".join(lines)


def write_outputs(result: Mapping[str, Any], output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    files = {
        "inventory.json": result["inventory"],
        "findings.json": result["findings"],
        "coverage.json": result["coverage"],
        "staging_candidates.json": result["staging_candidates"],
        "normalization_candidates.json": result["normalization_candidates"],
    }
    for name, value in files.items():
        (output_dir / name).write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (output_dir / "report.md").write_text(render_markdown(result), encoding="utf-8")


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=PROJECT_ROOT, help="repository root")
    parser.add_argument("--data-root", type=Path, help="world-data root; defaults to <root>/data/world_map")
    parser.add_argument("--output-dir", type=Path, help="optional explicit staging/report output directory")
    parser.add_argument("--allow-errors", action="store_true", help="return zero even when ERROR findings exist")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    root = args.root.resolve()
    data_root = (args.data_root or root / "data" / "world_map").resolve()
    result = WorldDataAudit(data_root).run()
    if args.output_dir:
        output_dir = args.output_dir if args.output_dir.is_absolute() else root / args.output_dir
        write_outputs(result, output_dir.resolve())
    print(json.dumps({"summary": result["summary"], "output_dir": str(args.output_dir) if args.output_dir else ""}, ensure_ascii=False, sort_keys=True))
    return 1 if result["summary"]["severity_counts"].get("ERROR", 0) and not args.allow_errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
