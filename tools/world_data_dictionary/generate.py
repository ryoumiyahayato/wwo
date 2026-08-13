#!/usr/bin/env python3
"""Build a deterministic dictionary for the WWO world-data inputs.

The generator deliberately keeps observed JSON facts separate from evidence
found in loaders and validators.  It does not validate or rewrite production
data; it only reads the scoped inputs and source files and renders reports.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable


TOOL_VERSION = "world-data-dictionary-v2"
DATA_ROOTS = ("data/world_map", "data/vnext")
SOURCE_ROOTS = ("scripts", "tests", "tools")
JSON_SUFFIX = ".json"

PRIMARY_RECORD_PATHS: dict[str, str] = {
    "world_map.characters": "document",
    "world_map.cities": "cities[]",
    "world_map.countries": "countries[]",
    "world_map.city_detail.country_shards": "cities[]",
    "world_map.city_detail.france_shards": "cities[]",
    "world_map.city_detail.index": "countries[]",
    "world_map.city_detail.LICENSE": "document",
    "world_map.country_flag_palettes": "palettes.<key>",
    "world_map.historical.cshapes_1900_snapshot": "features[]",
    "world_map.historical.flags_1900": "records.<key>",
    "world_map.historical.historical_admin1_1900": "countries[]",
    "world_map.historical.major_economy_polity_crosswalk_1900": "records[]",
    "world_map.historical.major_state_profiles_1900": "profiles[]",
    "world_map.historical.political_units_1900": "units[]",
    "world_map.historical_political_entities_1900": "entities[]",
    "world_map.institutions": "institutions[]",
    "world_map.map_geometry_cache": "document",
    "world_map.map_modes": "modes[]",
    "world_map.name_pool_fr": "given_names[]",
    "world_map.organizations": "catalog[]",
    "world_map.ports": "ports[]",
    "world_map.regions": "regions[]",
    "world_map.relationships": "relationships[]",
    "world_map.rail_segments": "segments[]",
    "world_map.road_segments": "segments[]",
    "world_map.shipping_routes": "routes[]",
    "world_map.world_activity": "items[]",
    "world_map.world_admin1": "regions[]",
    "world_map.world_coastlines": "features[]",
    "vnext.politics.state_politics_1900": "document",
}

DATASET_DESCRIPTIONS: dict[str, str] = {
    "world_map.characters": "Prototype character identity, action, status, and plan-display definitions.",
    "world_map.cities": "Sparse world-map city node catalog used by the shared basemap.",
    "world_map.countries": "Country map-node catalog, labels, geometry links, and display metadata.",
    "world_map.city_detail.country_shards": "Modern city detail shards grouped by country; loaded lazily for regional reference.",
    "world_map.city_detail.france_shards": "Modern French administrative city detail shards; loaded lazily for regional reference.",
    "world_map.city_detail.index": "Index and runtime policy for the modern city-detail shards.",
    "world_map.city_detail.LICENSE": "Attribution and license metadata for the city-detail source dataset.",
    "world_map.country_flag_palettes": "Country color palettes used by the map flag/identity presentation.",
    "world_map.historical.cshapes_1900_snapshot": "1900 CShapes historical political geometry snapshot.",
    "world_map.historical.flags_1900": "1900 political-unit flag assignment snapshot and policy metadata.",
    "world_map.historical.historical_admin1_1900": "1900 country-to-administrative-unit reference used by the historical admin view.",
    "world_map.historical.major_economy_polity_crosswalk_1900": "Crosswalk between major economy entities and 1900 political units.",
    "world_map.historical.major_state_profiles_1900": "Selected 1900 major-state profiles and aliases.",
    "world_map.historical.political_units_1900": "1900 political-unit records linking geometry, flags, and historical identity.",
    "world_map.historical_political_entities_1900": "Historical political entity list and explicit approximation/conflict notes.",
    "world_map.institutions": "Institution nodes, hierarchy, permissions, and public/worker display definitions.",
    "world_map.map_geometry_cache": "Precomputed map geometry, anchors, LODs, and transport drawing cache.",
    "world_map.map_modes": "Map modes, zoom thresholds, label budgets, and layer-display policy.",
    "world_map.name_pool_fr": "French name-pool entries with culture, gender, class, and region tags.",
    "world_map.organizations": "Organization catalog and worker/official identity interaction definitions.",
    "world_map.ports": "Sparse port node catalog used by transport routes.",
    "world_map.regions": "Map regions and administrative-unit geometry/catalog data.",
    "world_map.relationships": "Prototype persistent relationship display records and relationship actions.",
    "world_map.rail_segments": "Rail transport segments connecting map city nodes.",
    "world_map.road_segments": "Road transport segments connecting map city nodes.",
    "world_map.shipping_routes": "Shipping routes connecting map port nodes.",
    "world_map.world_activity": "Prototype public activity feed records shown by the map UI.",
    "world_map.world_admin1": "World administrative-level-1 reference records.",
    "world_map.world_coastlines": "World coastline geometry features for the shared basemap.",
    "vnext.politics.state_politics_1900": "1900 vNext politics configuration consumed to initialize authoritative state politics.",
}

# These are source-level hints, not schema declarations.  They identify code
# that is known to consume a dataset even when the source uses an intermediate
# loader rather than repeating the data path at every access site.
SOURCE_DATASET_HINTS: dict[str, tuple[str, ...]] = {
    "scripts/world_map/internal/world_map_canvas_impl.gd": (
        "world_map.world_coastlines", "world_map.countries", "world_map.regions",
        "world_map.cities", "world_map.ports", "world_map.rail_segments",
        "world_map.road_segments", "world_map.shipping_routes",
        "world_map.institutions", "world_map.organizations", "world_map.map_modes",
        "world_map.map_geometry_cache",
    ),
    "scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd": (
        "world_map.world_coastlines", "world_map.regions", "world_map.cities",
        "world_map.institutions", "world_map.characters",
    ),
    "scripts/vnext/politics/state_politics.gd": (
        "vnext.politics.state_politics_1900",
    ),
}

# Object maps whose keys are data identifiers rather than stable field names.
# They are represented with <key> so a country code or anchor ID does not
# become hundreds of pseudo-fields in the generated reference.
DYNAMIC_OBJECT_KEYS = {
    "palettes", "anchors", "records", "identities", "administrative_lods",
    "country_lods", "macro_regions", "source_records",
}

ENUM_CONSTANT_FIELD_HINTS: dict[str, tuple[str, ...]] = {
    "REGIME_TYPES": ("regime_type",),
    "POLICY_DOMAINS": ("domain", "policy_preferences.<key>"),
    "PRESSURE_SIGNAL_KEYS": ("pressure_response.<key>",),
    "CAPACITY_KEYS": ("capacity.<key>",),
}

ID_KIND_TARGETS: dict[str, tuple[str, ...]] = {}

DECLARED_EVIDENCE_SCOPES = {
    "LOADER",
    "VALIDATOR",
    "SOURCE_CONFIG",
    "RUNTIME_SNAPSHOT",
}


SEMANTIC_FIELD_PAIRS: tuple[tuple[str, str, str], ...] = (
    ("id", "stable_id", "Both look like entity identifiers; the authoritative identity is not declared by the data file."),
    ("country_code", "parent_country_id", "Both can encode country ownership but use different naming and apparent ID conventions."),
    ("country_id", "parent_country_id", "Both can encode country ownership; target and scope must be chosen explicitly."),
    ("name", "native_name", "Display name and native name are distinct fields but their fallback/authority is not declared here."),
    ("lon_lat", "label_lon_lat", "Point geometry and label point may be intentionally different; do not substitute them automatically."),
    ("geometry_iso_a3", "source_iso_a3", "Two ISO-like fields coexist and may represent display versus source identity."),
)


def json_type(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int) and not isinstance(value, bool):
        return "integer"
    if isinstance(value, float):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    return type(value).__name__


def type_family(value: str) -> str:
    return "numeric" if value in {"integer", "number"} else value


def normalize_types(types: Iterable[str]) -> str | None:
    values = sorted(set(types))
    if not values:
        return None
    families = sorted(set(type_family(item) for item in values))
    if families == ["numeric"]:
        return "number"
    return "|".join(values)


def canonical(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def example_value(value: Any, depth: int = 0) -> Any:
    if depth >= 2:
        return "<nested>"
    if isinstance(value, dict):
        return {str(key): example_value(value[key], depth + 1) for key in sorted(value)[:6]}
    if isinstance(value, list):
        return [example_value(item, depth + 1) for item in value[:4]]
    return value


def leaf_name(field_path: str) -> str:
    path = field_path.replace("[]", "")
    return path.rsplit(".", 1)[-1]


def normalize_field_path(path: str) -> str:
    value = path.replace("\\", "/").strip().strip(".")
    if value.startswith("document."):
        value = value[len("document."):]
    return value


def function_context_by_line(text: str) -> dict[int, str]:
    contexts: dict[int, str] = {}
    current = "<module>"
    for line_number, line in enumerate(text.splitlines(), 1):
        match = re.match(r"\s*(?:static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", line)
        if match:
            current = match.group(1)
        contexts[line_number] = current
    return contexts


def source_evidence_scope(source_relative: str, function: str = "<module>") -> str:
    if source_relative.startswith("tests/"):
        return "TEST"
    if source_relative.startswith("tools/"):
        return "TOOLING"
    if source_relative.endswith("scripts/vnext/politics/state_politics.gd"):
        if function in {
            "snapshot",
            "restore",
            "_validate_snapshot",
            "_validate_force",
            "_validate_policy",
            "_validate_policy_history",
            "_validate_government_history",
            "_validate_capacity",
            "_validate_preference_dictionary",
        }:
            return "RUNTIME_SNAPSHOT"
        return "SOURCE_CONFIG"
    if "validate" in function.lower():
        return "VALIDATOR"
    return "LOADER"


def source_field_path(
    source_relative: str,
    function: str,
    receiver: str,
    field_name: str,
) -> str | None:
    # Root document/config access is exact only for a single source contract.
    # Collection variables do not carry enough structure by name alone.
    if receiver in {"document", "config"}:
        return field_name
    if not source_relative.endswith("scripts/vnext/politics/state_politics.gd"):
        return None
    if function in {"restore", "_validate_snapshot"} and receiver == "snapshot_value":
        return f"runtime_snapshot.{field_name}"
    if function == "_validate_force" and receiver == "force":
        return f"runtime_snapshot.forces[].{field_name}"
    if function == "_validate_policy" and receiver == "policy":
        return f"runtime_snapshot.policies[].{field_name}"
    if function == "_validate_policy_history" and receiver == "record":
        return f"runtime_snapshot.policy_history[].{field_name}"
    if function == "_validate_government_history" and receiver == "record":
        return f"runtime_snapshot.government_change_history[].{field_name}"
    return None


def geometry_coordinate_shape(value: Any) -> str:
    if isinstance(value, list):
        if not value:
            return "array[empty]"
        children = sorted({geometry_coordinate_shape(item) for item in value})
        child_shape = children[0] if len(children) == 1 else "|".join(children)
        return f"array[{child_shape}]"
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return "number"
    return json_type(value)


def valid_geometry_coordinates(value: Any, geometry_type: str, depth: int = 0) -> bool:
    expected_depths = {
        "Point": 0,
        "MultiPoint": 1,
        "LineString": 1,
        "MultiLineString": 2,
        "Polygon": 2,
        "MultiPolygon": 3,
    }
    expected_depth = expected_depths.get(geometry_type)
    if expected_depth is None:
        return False
    if depth == expected_depth:
        return isinstance(value, list) and len(value) >= 2 and all(
            isinstance(item, (int, float)) and not isinstance(item, bool) for item in value
        )
    if not isinstance(value, list) or not value:
        return False
    return all(valid_geometry_coordinates(item, geometry_type, depth + 1) for item in value)


def collect_geometry_evidence(dataset: "DatasetAccumulator", value: Any, source_path: str, location: str = "") -> None:
    if isinstance(value, dict):
        geometry = value.get("geometry")
        if isinstance(geometry, dict) and ("type" in geometry or "coordinates" in geometry):
            has_type = "type" in geometry
            has_coordinates = "coordinates" in geometry
            geometry_type = str(geometry.get("type", "<missing>"))
            coordinates = geometry.get("coordinates")
            dataset.geometry_records.append({
                "source": source_path,
                "location": location or "document",
                "geometry_type": geometry_type,
                "coordinate_shape": geometry_coordinate_shape(coordinates) if has_coordinates else "missing",
                "valid": has_type and has_coordinates and valid_geometry_coordinates(coordinates, geometry_type),
            })
        for key in sorted(value, key=str):
            child_location = f"{location}.{key}" if location else str(key)
            collect_geometry_evidence(dataset, value[key], source_path, child_location)
    elif isinstance(value, list):
        for index, item in enumerate(value):
            collect_geometry_evidence(dataset, item, source_path, f"{location}[{index}]")


def summarize_geometry_evidence(records: list[dict[str, Any]]) -> dict[str, Any]:
    by_type: dict[str, dict[str, Any]] = {}
    invalid: list[dict[str, Any]] = []
    for record in records:
        geometry_type = record["geometry_type"]
        entry = by_type.setdefault(
            geometry_type,
            {"record_count": 0, "coordinate_shapes": [], "invalid_count": 0},
        )
        entry["record_count"] += 1
        entry["coordinate_shapes"].append(record["coordinate_shape"])
        if not record["valid"]:
            entry["invalid_count"] += 1
            invalid.append(record)
    for entry in by_type.values():
        entry["coordinate_shapes"] = sorted(set(entry["coordinate_shapes"]))
    return {"by_type": dict(sorted(by_type.items())), "invalid_records": invalid}


def normalize_path(path: str) -> str:
    path = path.replace("\\", "/")
    if path.startswith("res://"):
        path = path[6:]
    while path.startswith("./"):
        path = path[2:]
    return path


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dataset_id_for_path(relative_path: str) -> str:
    path = normalize_path(relative_path)
    if path.startswith("data/world_map/city_detail/countries/"):
        return "world_map.city_detail.country_shards"
    if path.startswith("data/world_map/city_detail/france/"):
        return "world_map.city_detail.france_shards"
    if path.startswith("data/"):
        path = path[5:]
    if path.endswith(JSON_SUFFIX):
        path = path[:-len(JSON_SUFFIX)]
    return path.replace("/", ".")


def discover_data_files(repo_root: Path) -> list[Path]:
    files: list[Path] = []
    for root_name in DATA_ROOTS:
        root = repo_root / root_name
        if root.exists():
            files.extend(path for path in root.rglob("*.json") if path.is_file())
    return sorted(files, key=lambda path: path.relative_to(repo_root).as_posix())


def is_dynamic_object(path: str, value: dict[str, Any]) -> bool:
    key = path.rsplit(".", 1)[-1] if path else ""
    if key in DYNAMIC_OBJECT_KEYS:
        return True
    if len(value) >= 20:
        child_types = {json_type(child) for child in value.values()}
        if len(child_types) == 1:
            return True
    return False


@dataclass
class FieldAccumulator:
    field: str
    scope: str
    types: set[str] = field(default_factory=set)
    item_types: set[str] = field(default_factory=set)
    present_count: int = 0
    nullable_count: int = 0
    examples: dict[str, Any] = field(default_factory=dict)
    scalar_values: set[str] = field(default_factory=set)
    numeric_values: list[float] = field(default_factory=list)

    def observe(self, value: Any, *, item: bool = False) -> None:
        value_type = json_type(value)
        if item:
            self.item_types.add(value_type)
        else:
            self.types.add(value_type)
        self.present_count += 1
        if value is None:
            self.nullable_count += 1
        else:
            self.examples.setdefault(canonical(example_value(value)), example_value(value))
            if isinstance(value, (str, int, float, bool)) and not isinstance(value, dict):
                encoded = canonical(value)
                self.scalar_values.add(encoded)
                if isinstance(value, (int, float)) and not isinstance(value, bool):
                    self.numeric_values.append(float(value))


@dataclass
class CollectionAccumulator:
    path: str
    count: int = 0
    source_paths: set[str] = field(default_factory=set)


class DatasetAccumulator:
    def __init__(self, dataset: str) -> None:
        self.dataset = dataset
        self.source_paths: list[str] = []
        self.source_files: list[dict[str, Any]] = []
        self.root_types: set[str] = set()
        self.document_count = 0
        self.scopes: Counter[str] = Counter()
        self.fields: dict[tuple[str, str], FieldAccumulator] = {}
        self.collections: dict[str, CollectionAccumulator] = {}
        self.errors: list[dict[str, str]] = []
        self.geometry_records: list[dict[str, Any]] = []

    def add_scope(self, scope: str, count: int = 1) -> None:
        self.scopes[scope] += count

    def field(self, path: str, scope: str) -> FieldAccumulator:
        key = (path, scope)
        if key not in self.fields:
            self.fields[key] = FieldAccumulator(path, scope)
        return self.fields[key]

    def add_collection(self, path: str, source_path: str, count: int) -> None:
        collection = self.collections.setdefault(path, CollectionAccumulator(path))
        collection.count += count
        collection.source_paths.add(source_path)


def walk_value(dataset: DatasetAccumulator, value: Any, path: str, scope: str, source_path: str) -> None:
    if isinstance(value, dict):
        if path and is_dynamic_object(path, value):
            for _key, child in sorted(value.items(), key=lambda item: str(item[0])):
                record_scope = f"{path}.<key>"
                dataset.add_scope(record_scope)
                dataset.add_collection(record_scope, source_path, 1)
                dataset.field(record_scope, record_scope).observe(child)
                walk_value(dataset, child, record_scope, record_scope, source_path)
            return
        for key in sorted(value, key=str):
            child_path = f"{path}.{key}" if path else str(key)
            child = value[key]
            dataset.field(child_path, scope).observe(child)
            walk_value(dataset, child, child_path, scope, source_path)
        return
    if isinstance(value, list):
        item_scope = f"{path}[]" if path else "[]"
        for item in value:
            dataset.add_scope(item_scope)
            dataset.field(item_scope, item_scope).observe(item)
            if isinstance(item, dict):
                dataset.add_collection(item_scope, source_path, 1)
                walk_value(dataset, item, item_scope, item_scope, source_path)
            elif isinstance(item, list):
                walk_value(dataset, item, item_scope, item_scope, source_path)


def observe_document(dataset: DatasetAccumulator, document: Any, source_path: str) -> None:
    dataset.document_count += 1
    dataset.add_scope("document")
    dataset.root_types.add(json_type(document))
    if isinstance(document, dict):
        walk_value(dataset, document, "", "document", source_path)
    collect_geometry_evidence(dataset, document, source_path)


def literal_default(expression: str | None) -> Any:
    if expression is None:
        return None
    value = expression.strip()
    if not value:
        return None
    if value in {"[]", "{}", "null", "false", "true"}:
        return {"[]": [], "{}": {}, "null": None, "false": False, "true": True}[value]
    if re.fullmatch(r"-?\d+", value):
        return int(value)
    if re.fullmatch(r"-?(?:\d+\.\d*|\d*\.\d+)", value):
        return float(value)
    quoted = re.fullmatch(r"[\"'](.*)[\"']", value)
    if quoted:
        return quoted.group(1)
    return None


def type_from_line(line: str, field_name: str) -> str | None:
    if f'get("{field_name}"' not in line and f"get('{field_name}'" not in line:
        return None
    if "TYPE_BOOL" in line or re.search(r"\bbool\s*\(", line):
        return "boolean"
    if "TYPE_STRING" in line or re.search(r"\bstr\s*\(", line):
        return "string"
    if "TYPE_DICTIONARY" in line or re.search(r"as\s+Dictionary", line):
        return "object"
    if "TYPE_ARRAY" in line or re.search(r"as\s+Array", line):
        return "array"
    if re.search(r"\bint\s*\(", line):
        return "integer"
    if re.search(r"\bfloat\s*\(", line):
        return "number"
    return None


def source_target_paths(source_relative: str, text: str) -> tuple[str, ...]:
    targets: set[str] = set(SOURCE_DATASET_HINTS.get(source_relative, ()))
    for match in re.finditer(r"(?:res://)?(data/(?:world_map|vnext)/[A-Za-z0-9_./-]+\.json)", text):
        targets.add(dataset_id_for_path(match.group(1)))
    if "city_detail" in text and "world_map.city_detail.country_shards" in SOURCE_DATASET_HINTS.get(source_relative, ()):
        targets.add("world_map.city_detail.country_shards")
        targets.add("world_map.city_detail.france_shards")
    return tuple(sorted(targets))


def extract_enum_constants(text: str, line_offset: int = 0) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    pattern = re.compile(
        r"const\s+([A-Z][A-Z0-9_]*)\s*:\s*Array(?:\[String\])?\s*=\s*\[(.*?)\]",
        re.DOTALL,
    )
    for match in pattern.finditer(text):
        values = re.findall(r"[\"']([^\"']+)[\"']", match.group(2))
        if not values:
            continue
        line = text.count("\n", 0, match.start()) + 1 + line_offset
        result.append({
            "name": match.group(1),
            "values": sorted(set(values)),
            "line": line,
            "field_hints": list(ENUM_CONSTANT_FIELD_HINTS.get(match.group(1), ())),
        })
    return result


def extract_required_blocks(text: str, source_relative: str = "<unknown>") -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    contexts = function_context_by_line(text)
    pattern = re.compile(
        r"for\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*String\s+in\s*\[(.*?)\]",
        re.DOTALL,
    )
    prefixes = {
        "_validate_snapshot": "runtime_snapshot.",
        "_validate_force": "runtime_snapshot.forces[].",
        "_validate_policy": "runtime_snapshot.policies[].",
        "_validate_policy_history": "runtime_snapshot.policy_history[].",
        "_validate_government_history": "runtime_snapshot.government_change_history[].",
    }
    for match in pattern.finditer(text):
        variable = match.group(1)
        values = sorted(set(re.findall(r"[\"']([^\"']+)[\"']", match.group(2))))
        if not values:
            continue
        line = text.count("\n", 0, match.start()) + 1
        function = contexts.get(line, "<module>")
        scope = source_evidence_scope(source_relative, function)
        prefix = prefixes.get(function, "")
        result.append({
            "variable": variable,
            "fields": values,
            "field_paths": [normalize_field_path(prefix + value) for value in values],
            "required": "required" in variable.lower(),
            "line": line,
            "function": function,
            "evidence_scope": scope,
        })
    return result

def analyze_source(repo_root: Path, path: Path) -> dict[str, Any] | None:
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None
    relative = path.relative_to(repo_root).as_posix()
    contexts = function_context_by_line(text)
    targets = source_target_paths(relative, text)
    exact_contract = len(targets) == 1
    path_refs: list[dict[str, Any]] = []
    for line_number, line in enumerate(text.splitlines(), 1):
        for match in re.finditer(r"(?:res://)?(data/(?:world_map|vnext)/[A-Za-z0-9_./-]+\.json)", line):
            path_refs.append({
                "path": normalize_path(match.group(1)),
                "line": line_number,
                "text": line.strip()[:240],
            })

    accesses: list[dict[str, Any]] = []
    access_pattern = re.compile(
        r"(?P<receiver>[A-Za-z_][A-Za-z0-9_]*)\.(?P<method>get|has)"
        r"\(\s*[\"'](?P<field>[^\"']+)[\"'](?:\s*,\s*(?P<default>[^\)]*))?\s*\)"
    )
    bracket_pattern = re.compile(r"\[\s*[\"']([^\"']+)[\"']\s*\]")
    lines = text.splitlines()
    for line_number, line in enumerate(lines, 1):
        function = contexts.get(line_number, "<module>")
        evidence_scope = source_evidence_scope(relative, function)
        for match in access_pattern.finditer(line):
            field_name = match.group("field")
            receiver = match.group("receiver")
            default_expression = match.group("default").strip() if match.group("default") is not None else None
            default = literal_default(default_expression)
            kind = "has_check" if match.group("method") == "has" else "get"
            field_path = source_field_path(relative, function, receiver, field_name) if exact_contract else None
            required = kind == "has_check" and "not" in line[:match.start()]
            id_kind = None
            for id_match in re.finditer(
                r"_valid_id\([^,]*get\(\s*[\"']([^\"']+)[\"'][^)]*\)[^,]*,\s*[\"']([^\"']+)[\"']",
                line,
            ):
                if id_match.group(1) == field_name:
                    id_kind = id_match.group(2)
                    break
            accesses.append({
                "field": field_name,
                "field_path": normalize_field_path(field_path) if field_path is not None else None,
                "path_kind": "EXACT_PATH" if field_path is not None else "LEAF_ONLY",
                "line": line_number,
                "function": function,
                "evidence_scope": evidence_scope,
                "kind": kind,
                "default": default,
                "default_expression": default_expression,
                "has_explicit_default": match.group("default") is not None,
                "required": required,
                "id_kind": id_kind,
                "type": type_from_line(line, field_name),
                "text": line.strip()[:240],
            })
        for match in bracket_pattern.finditer(line):
            field_name = match.group(1)
            if field_name in {"", "res://"}:
                continue
            accesses.append({
                "field": field_name,
                "field_path": None,
                "path_kind": "LEAF_ONLY",
                "line": line_number,
                "function": function,
                "evidence_scope": evidence_scope,
                "kind": "bracket_access",
                "default": None,
                "default_expression": None,
                "has_explicit_default": False,
                "required": False,
                "type": None,
                "text": line.strip()[:240],
            })

    enums = extract_enum_constants(text)
    for enum in enums:
        enum["evidence_scope"] = source_evidence_scope(relative, "<module>")
    required_blocks = extract_required_blocks(text, relative)
    if not targets and not path_refs and not enums and not required_blocks:
        return None
    return {
        "source": relative,
        "sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
        "targets": list(targets),
        "path_references": path_refs,
        "field_accesses": sorted(accesses, key=lambda item: (item["line"], item["field"], item["kind"])),
        "enum_constants": enums,
        "required_blocks": required_blocks,
        "exact_contract": exact_contract,
        "contract_scope": "EXACT_DATASET" if exact_contract else "MULTI_DATASET_OR_INFERRED",
    }

def scan_sources(repo_root: Path) -> list[dict[str, Any]]:
    sources: list[dict[str, Any]] = []
    for root_name in SOURCE_ROOTS:
        root = repo_root / root_name
        if not root.exists():
            continue
        for path in sorted(root.rglob("*")):
            if path.suffix not in {".gd", ".py"} or not path.is_file():
                continue
            analysis = analyze_source(repo_root, path)
            if analysis is not None:
                sources.append(analysis)
    return sources


def declared_evidence_for_field(
    dataset_id: str,
    field_path: str,
    sources: list[dict[str, Any]],
) -> dict[str, Any]:
    normalized_field = normalize_field_path(field_path)
    leaf = leaf_name(normalized_field)
    declared_types: set[str] = set()
    defaults: list[Any] = []
    default_expressions: list[str] = []
    enum_values: set[str] = set()
    declared_id_kinds: set[str] = set()
    required_by_scope: dict[str, bool] = {}
    evidence: list[dict[str, Any]] = []
    heuristic_evidence: list[dict[str, Any]] = []
    usage: list[dict[str, Any]] = []

    for source in sources:
        if dataset_id not in source["targets"]:
            continue
        for access in source["field_accesses"]:
            if access["field"] != leaf:
                continue
            if access.get("field_path") != normalized_field:
                if access.get("field_path") is None:
                    heuristic_evidence.append({
                        "source": source["source"],
                        "line": access["line"],
                        "kind": "HEURISTIC_LEAF_MATCH",
                        "evidence_scope": access.get("evidence_scope", "UNKNOWN"),
                        "contract_scope": source.get("contract_scope", "UNKNOWN"),
                        "field": access["field"],
                        "field_path": None,
                    })
                continue
            scope = access.get("evidence_scope")
            row = {
                "source": source["source"],
                "line": access["line"],
                "evidence_scope": scope,
                "contract_scope": source.get("contract_scope", "UNKNOWN"),
                "field_path": normalized_field,
                "text": access["text"],
            }
            if scope not in DECLARED_EVIDENCE_SCOPES:
                heuristic_evidence.append({**row, "kind": "HEURISTIC_NON_SCHEMA_SOURCE"})
                continue
            usage.append({**row, "kind": access["kind"]})
            if access["has_explicit_default"]:
                defaults.append(access["default"])
                if access.get("default_expression") is not None:
                    default_expressions.append(str(access["default_expression"]))
                evidence.append({**row, "kind": "DECLARED_DEFAULT", "default": access["default"]})
            if access["type"] is not None:
                declared_types.add(access["type"])
                evidence.append({**row, "kind": "DECLARED_TYPE", "type": access["type"]})
            if access.get("id_kind") is not None:
                declared_id_kinds.add(str(access["id_kind"]))
                evidence.append({
                    **row,
                    "kind": "ID_KIND_CONSTRAINT",
                    "expected_kind": str(access["id_kind"]),
                })
            if access["required"]:
                required_by_scope[str(scope)] = True
                evidence.append({**row, "kind": "DECLARED_REQUIRED"})
        if not source.get("exact_contract", False):
            continue
        for block in source["required_blocks"]:
            for block_path in block.get("field_paths", block["fields"]):
                if normalize_field_path(block_path) != normalized_field:
                    continue
                scope = block.get("evidence_scope")
                row = {
                    "source": source["source"],
                    "line": block["line"],
                    "kind": "DECLARED_FIELD_LIST",
                    "variable": block["variable"],
                    "required": block["required"],
                    "evidence_scope": scope,
                    "contract_scope": source.get("contract_scope", "UNKNOWN"),
                    "field_path": normalized_field,
                }
                if scope in DECLARED_EVIDENCE_SCOPES:
                    if block["required"]:
                        required_by_scope[str(scope)] = True
                    evidence.append(row)
                    if "numeric" in block["variable"].lower() or "support" in block["variable"].lower():
                        declared_types.add("number")
                    elif "string" in block["variable"].lower():
                        declared_types.add("string")
                else:
                    heuristic_evidence.append({**row, "kind": "HEURISTIC_NON_SCHEMA_SOURCE"})
        if not source.get("exact_contract", False):
            continue
        for enum in source["enum_constants"]:
            for hint in enum["field_hints"]:
                hint_path = normalize_field_path(hint)
                if hint_path != normalized_field and not normalized_field.endswith("." + hint_path):
                    continue
                scope = enum.get("evidence_scope")
                row = {
                    "source": source["source"],
                    "line": enum["line"],
                    "kind": "DECLARED_ENUM",
                    "constant": enum["name"],
                    "values": enum["values"],
                    "evidence_scope": scope,
                    "contract_scope": source.get("contract_scope", "UNKNOWN"),
                    "field_path": normalized_field,
                }
                if scope in DECLARED_EVIDENCE_SCOPES:
                    enum_values.update(enum["values"])
                    evidence.append(row)
                else:
                    heuristic_evidence.append({**row, "kind": "HEURISTIC_NON_SCHEMA_SOURCE"})

    unique_defaults = sorted({canonical(item): item for item in defaults}.items())
    return {
        "declared": bool(evidence),
        "types": sorted(declared_types),
        "required": any(required_by_scope.values()) if evidence else None,
        "required_by_scope": dict(sorted(required_by_scope.items())),
        "default": unique_defaults[0][1] if len(unique_defaults) == 1 else None,
        "default_explicitly_defined": bool(default_expressions),
        "default_expressions": sorted(set(default_expressions)),
        "defaults": [item[1] for item in unique_defaults],
        "enum_values": sorted(enum_values),
        "id_kinds": sorted(declared_id_kinds),
        "foreign_key_targets": [],
        "evidence": sorted(evidence, key=lambda item: (item["source"], item["line"], item["kind"])),
        "heuristic_evidence": sorted(heuristic_evidence, key=lambda item: (item["source"], item["line"], item["kind"])),
        "usage": sorted(usage, key=lambda item: (item["source"], item["line"], item["kind"])),
    }

def declared_only_fields(dataset_id: str, sources: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for source in sources:
        if dataset_id not in source["targets"] or not source.get("exact_contract", False):
            continue
        for access in source["field_accesses"]:
            field_path = access.get("field_path")
            if not field_path or not access.get("id_kind"):
                continue
            scope = access.get("evidence_scope")
            if scope not in DECLARED_EVIDENCE_SCOPES:
                continue
            entry = result.setdefault(
                field_path,
                {
                    "types": set(),
                    "required": False,
                    "evidence": [],
                    "scopes": set(),
                    "enum_values": set(),
                    "id_kinds": set(),
                },
            )
            entry["scopes"].add(scope)
            entry["id_kinds"].add(str(access["id_kind"]))
            entry["evidence"].append({
                "source": source["source"],
                "line": access["line"],
                "kind": "ID_KIND_CONSTRAINT",
                "expected_kind": str(access["id_kind"]),
                "evidence_scope": scope,
                "contract_scope": source.get("contract_scope", "UNKNOWN"),
                "field_path": normalize_field_path(field_path),
                "text": access["text"],
            })
        for block in source["required_blocks"]:
            if not block["required"] or block.get("evidence_scope") not in DECLARED_EVIDENCE_SCOPES:
                continue
            for field_path in block.get("field_paths", block["fields"]):
                entry = result.setdefault(
                    field_path,
                    {
                        "types": set(),
                        "required": False,
                        "evidence": [],
                        "scopes": set(),
                        "enum_values": set(),
                        "id_kinds": set(),
                    },
                )
                entry["required"] = True
                entry["scopes"].add(block["evidence_scope"])
                if "numeric" in block["variable"].lower() or "support" in block["variable"].lower():
                    entry["types"].add("number")
                elif "string" in block["variable"].lower():
                    entry["types"].add("string")
                entry["evidence"].append({
                    "source": source["source"],
                    "line": block["line"],
                    "kind": "DECLARED_FIELD_LIST",
                    "variable": block["variable"],
                    "required": True,
                    "evidence_scope": block["evidence_scope"],
                    "field_path": field_path,
                    "contract_scope": source.get("contract_scope", "UNKNOWN"),
                })
        for enum in source["enum_constants"]:
            if enum.get("evidence_scope") not in DECLARED_EVIDENCE_SCOPES:
                continue
            for hint in enum["field_hints"]:
                if "<key>" in hint:
                    continue
                field_path = normalize_field_path(hint)
                entry = result.setdefault(
                    field_path,
                    {
                        "types": set(),
                        "required": False,
                        "evidence": [],
                        "scopes": set(),
                        "enum_values": set(),
                        "id_kinds": set(),
                    },
                )
                entry["types"].add("string")
                entry["scopes"].add(enum["evidence_scope"])
                entry["enum_values"].update(enum["values"])
                entry["evidence"].append({
                    "source": source["source"],
                    "line": enum["line"],
                    "kind": "DECLARED_ENUM",
                    "constant": enum["name"],
                    "values": enum["values"],
                    "evidence_scope": enum["evidence_scope"],
                    "contract_scope": source.get("contract_scope", "UNKNOWN"),
                    "field_path": field_path,
                })
    return result

def is_id_field(field_path: str, scope: str) -> tuple[bool, str | None]:
    leaf = leaf_name(field_path)
    if leaf in {"schema_id", "dataset_id", "source_id", "culture_id", "feature_id"}:
        return False, None
    if leaf in {"id", "stable_id"}:
        return True, "primary_candidate" if "[]" in scope or scope == "document" else "semantic_id"
    if leaf.endswith("_id") or leaf.endswith("_ids"):
        return True, "reference_candidate"
    return False, None


def enum_candidate(field: FieldAccumulator, declared: dict[str, Any]) -> tuple[list[Any], str]:
    values: list[Any] = []
    for encoded in sorted(field.scalar_values):
        try:
            values.append(json.loads(encoded))
        except json.JSONDecodeError:
            continue
    if declared["enum_values"]:
        return declared["enum_values"], "DECLARED"
    if "string" in field.types and len(values) <= 32 and values:
        return values, "OBSERVED"
    return [], "NONE"


def render_field(field: FieldAccumulator, scope_count: int, declared: dict[str, Any]) -> dict[str, Any]:
    observed_type = normalize_types(field.types)
    item_type = normalize_types(field.item_types)
    if item_type is not None:
        observed_type = f"{observed_type}<{item_type}>" if observed_type else f"array<{item_type}>"
    missing_count = max(scope_count - field.present_count, 0)
    source_required = any(
        scope in {"LOADER", "VALIDATOR", "SOURCE_CONFIG"}
        for scope in declared["required_by_scope"]
    )
    runtime_required = "RUNTIME_SNAPSHOT" in declared["required_by_scope"]
    if runtime_required and source_required:
        required_status = "source-config-and-runtime-snapshot-required"
    elif runtime_required:
        required_status = "runtime-snapshot-required"
    elif source_required and missing_count > 0:
        required_status = "declared-required-but-missing"
    elif source_required:
        required_status = "declared-required"
    elif field.types and missing_count == 0:
        required_status = "required-by-observation"
    elif field.types:
        required_status = "optional-by-observation"
    else:
        required_status = "unknown"
    id_field, id_kind = is_id_field(field.field, field.scope)
    enum_values, enum_evidence = enum_candidate(field, declared)
    scalar_unique = bool(field.scalar_values) and len(field.scalar_values) == field.present_count - field.nullable_count
    type_inconsistent = len({type_family(value) for value in field.types if value != "null"}) > 1
    notes: list[str] = []
    if type_inconsistent:
        notes.append("OBSERVED type variants are incompatible; inspect each source record before writing new data.")
    if missing_count > 0:
        notes.append("Field is absent in some records in this scope; absence is not treated as an explicit null.")
    if declared["declared"] and not field.types:
        notes.append("DECLARED by exact loader/validator path evidence but not observed in the scoped JSON input.")
    if runtime_required:
        notes.append("Required by a runtime snapshot validator; this is not a source JSON requirement.")
    if declared["default"] is not None:
        notes.append("Default is copied from exact loader evidence; it is not a production-data default.")
    if declared["id_kinds"]:
        notes.append("ID_KIND_CONSTRAINT records stable-ID syntax/kind only; it does not prove catalog membership or a foreign key.")
    return {
        "field": field.field,
        "record_scope": field.scope,
        "observed": bool(field.types),
        "observed_type": observed_type,
        "observed_type_variants": sorted(field.types),
        "observed_item_type": item_type,
        "nullable": field.nullable_count > 0,
        "required_by_observation": bool(field.types) and missing_count == 0,
        "required_status": required_status,
        "optional_by_observation": bool(field.types) and missing_count > 0 and not source_required,
        "default": declared["default"],
        "default_explicitly_defined": bool(declared["default_explicitly_defined"]),
        "default_expressions": declared["default_expressions"],
        "defaults_observed_from_loader": declared["defaults"],
        "unique": scalar_unique if field.scalar_values else None,
        "id_field": id_field,
        "id_kind": id_kind,
        "declared_id_kinds": declared["id_kinds"],
        "id_kind_constraints": declared["id_kinds"],
        "declared_foreign_key_targets": [],
        "foreign_key": None,
        "enum_candidates": enum_values,
        "enum_evidence": enum_evidence,
        "numeric_min": min(field.numeric_values) if field.numeric_values else None,
        "numeric_max": max(field.numeric_values) if field.numeric_values else None,
        "example_values": [field.examples[key] for key in sorted(field.examples)[:3]],
        "record_count": scope_count,
        "present_count": field.present_count,
        "missing_count": missing_count,
        "declared": declared["declared"],
        "declared_types": declared["types"],
        "declared_required": source_required,
        "source_config_required": "SOURCE_CONFIG" in declared["required_by_scope"],
        "runtime_snapshot_required": runtime_required,
        "declared_evidence_scopes": sorted({item.get("evidence_scope", "UNKNOWN") for item in declared["evidence"]}),
        "declared_enum_values": declared["enum_values"],
        "declared_evidence": declared["evidence"],
        "heuristic_evidence": declared["heuristic_evidence"],
        "loader_consumed": bool(declared["usage"]),
        "loader_usage": declared["usage"],
        "notes": notes,
    }

def primary_record_path(dataset_id: str, collections: dict[str, CollectionAccumulator]) -> str:
    configured = PRIMARY_RECORD_PATHS.get(dataset_id)
    if configured == "document" or not collections:
        return "document"
    if configured in collections:
        return configured
    candidates = sorted(collections.values(), key=lambda item: (-item.count, item.path))
    return candidates[0].path if candidates else "document"


def build_field_registry(datasets: list[dict[str, Any]]) -> dict[str, list[tuple[str, dict[str, Any]]]]:
    registry: dict[str, list[tuple[str, dict[str, Any]]]] = defaultdict(list)
    for dataset in datasets:
        for field in dataset["fields"]:
            if not field["observed"]:
                continue
            if not field["id_field"]:
                continue
            for example in field["example_values"]:
                if isinstance(example, (str, int, float)) and not isinstance(example, bool):
                    registry[canonical(example)].append((dataset["dataset"], field))
    return registry


def fk_target_hints(field_path: str) -> list[str]:
    leaf = leaf_name(field_path).lower()
    base = leaf[:-4] if leaf.endswith("_ids") else leaf[:-3] if leaf.endswith("_id") else ""
    mapping = {
        "country": ("world_map.countries",),
        "parent_country": ("world_map.countries",),
        "region": ("world_map.regions",),
        "parent_region": ("world_map.regions",),
        "city": ("world_map.cities", "world_map.city_detail.country_shards", "world_map.city_detail.france_shards"),
        "port": ("world_map.ports",),
        "institution": ("world_map.institutions",),
        "organization": ("world_map.organizations",),
        "geometry_feature": ("world_map.historical.cshapes_1900_snapshot", "world_map.world_coastlines"),
        "force": ("vnext.politics.state_politics_1900", "world_map.organizations"),
        "government": ("world_map.organizations", "vnext.politics.state_politics_1900"),
        "government_group": ("world_map.organizations", "vnext.politics.state_politics_1900"),
        "government_leader": ("world_map.characters",),
        "leader": ("world_map.characters",),
        "policy": ("vnext.politics.state_politics_1900",),
        "polity": ("world_map.historical.political_units_1900",),
        "entity": ("world_map.historical_political_entities_1900",),
        "admin1": ("world_map.historical.historical_admin1_1900", "world_map.world_admin1"),
    }
    return list(mapping.get(base, ()))


def attach_foreign_keys(
    datasets: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    relationships: list[dict[str, Any]] = []
    candidates: list[dict[str, Any]] = []
    ambiguous: list[dict[str, Any]] = []
    for dataset in datasets:
        for field in dataset["fields"]:
            if not field["observed"] or not field["id_field"] or field["id_kind"] != "reference_candidate":
                continue
            hints = fk_target_hints(field["field"])
            available = [target for target in hints if any(item["dataset"] == target for item in datasets)]
            if not available:
                ambiguous.append({
                    "kind": "foreign_key_unclear_target",
                    "dataset": dataset["dataset"],
                    "field": field["field"],
                    "severity": "medium",
                    "risk": "high",
                    "message": "ID-like field has no reliable target dataset from name or resolver evidence.",
                })
                continue
            candidate = {
                "from_dataset": dataset["dataset"],
                "from_field": field["field"],
                "candidates": available,
                "to_field": "id/stable_id or target-specific identifier",
                "evidence": "HEURISTIC_FK_CANDIDATE",
                "confidence": "ambiguous" if len(available) > 1 else "candidate",
                "resolution": "Name convention only; verify target IDs and resolver/catalog lookup before inserting data.",
            }
            field["foreign_key"] = candidate
            candidates.append(candidate)
            if len(available) > 1:
                ambiguous.append({
                    "kind": "foreign_key_ambiguous_target",
                    "dataset": dataset["dataset"],
                    "field": field["field"],
                    "candidates": available,
                    "severity": "high",
                    "risk": "high",
                    "message": "ID-like field matches multiple plausible target datasets; no target was selected.",
                })
    return relationships, ambiguous, candidates

def find_field(datasets: list[dict[str, Any]], dataset_id: str, leaf: str) -> list[dict[str, Any]]:
    for dataset in datasets:
        if dataset["dataset"] == dataset_id:
            return [field for field in dataset["fields"] if leaf_name(field["field"]) == leaf]
    return []


def build_findings(datasets: list[dict[str, Any]], relationships: list[dict[str, Any]], fk_issues: list[dict[str, Any]]) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = list(fk_issues)
    for dataset in datasets:
        for field in dataset["fields"]:
            if field["observed_type_variants"]:
                families = {type_family(value) for value in field["observed_type_variants"] if value != "null"}
                if len(families) > 1 and not field.get("geometry_type_conditioned"):
                    findings.append({
                        "kind": "type_inconsistency",
                        "dataset": dataset["dataset"],
                        "field": field["field"],
                        "severity": "high",
                        "risk": "high",
                        "message": "The same field has incompatible observed JSON types.",
                        "evidence": field["observed_type_variants"],
                    })
            if field["nullable"] and field["missing_count"] > 0:
                findings.append({
                    "kind": "nullable_and_missing_inconsistency",
                    "dataset": dataset["dataset"],
                    "field": field["field"],
                    "severity": "medium",
                    "risk": "medium",
                    "message": "Some records explicitly use null while other records omit the field.",
                })
            if field["declared_required"] is True and field["observed"] and field["missing_count"] > 0:
                findings.append({
                    "kind": "unexpected_missing_declared_required",
                    "dataset": dataset["dataset"],
                    "field": field["field"],
                    "severity": "high",
                    "risk": "high",
                    "message": "Loader/validator evidence marks the field required but scoped data omits it.",
                })
            if field["declared_enum_values"] and field["observed"]:
                observed = set(field["enum_candidates"])
                undocumented = sorted(observed - set(field["declared_enum_values"]))
                if undocumented:
                    findings.append({
                        "kind": "undocumented_enum_value",
                        "dataset": dataset["dataset"],
                        "field": field["field"],
                        "severity": "high",
                        "risk": "high",
                        "message": "Observed enum candidate is outside the declared loader/validator values.",
                        "evidence": undocumented,
                    })
            if field["observed"] and not field["loader_consumed"] and leaf_name(field["field"]) not in {
                "schema_version", "schema_id", "prototype_only", "snapshot_date", "source", "policy",
            }:
                findings.append({
                    "kind": "potentially_ignored_field",
                    "dataset": dataset["dataset"],
                    "field": field["field"],
                    "severity": "low",
                    "risk": "medium" if field["id_field"] else "low",
                    "message": "No known scoped loader/validator access was found; this is a lead, not proof of obsolescence.",
                })

        leaves = {leaf_name(field["field"]): field for field in dataset["fields"] if field["observed"]}
        for left, right, message in SEMANTIC_FIELD_PAIRS:
            if left in leaves and right in leaves:
                findings.append({
                    "kind": "duplicate_semantic_fields",
                    "dataset": dataset["dataset"],
                    "field": f"{left} / {right}",
                    "severity": "medium",
                    "risk": "high" if left in {"id", "stable_id"} else "medium",
                    "message": message,
                })

    # Runtime snapshot requirements are not source JSON defects.
    for dataset in datasets:
        geometry = dataset.get("geometry_evidence", {})
        if geometry.get("invalid_records"):
            findings.append({
                "kind": "malformed_geometry_structure",
                "dataset": dataset["dataset"],
                "field": "geometry.coordinates",
                "severity": "high",
                "risk": "high",
                "message": "A geometry coordinates value does not match the nesting required by its geometry.type.",
                "evidence": geometry["invalid_records"],
            })
        for field in dataset["fields"]:
            if field.get("runtime_snapshot_required") and not field["observed"]:
                findings.append({
                    "kind": "runtime_snapshot_field_not_source_config",
                    "dataset": dataset["dataset"],
                    "field": field["field"],
                    "severity": "low",
                    "risk": "medium",
                    "message": "Runtime snapshot validator requires this field; it is not a source JSON required field.",
                })
            elif field["declared"] and not field["observed"] and field["declared_required"]:
                findings.append({
                    "kind": "loader_expects_field_absent_from_data",
                    "dataset": dataset["dataset"],
                    "field": field["field"],
                    "severity": "medium",
                    "risk": "high",
                    "message": "Exact loader/validator evidence marks this source field required but scoped data omits it.",
                })
    return sorted(findings, key=lambda item: (
        {"high": 0, "medium": 1, "low": 2}.get(item.get("severity", "low"), 3),
        {"high": 0, "medium": 1, "low": 2}.get(item.get("risk", "low"), 3),
        item.get("kind", ""), item.get("dataset", ""), item.get("field", ""),
    ))


def build_dictionary(repo_root: Path) -> dict[str, Any]:
    repo_root = repo_root.resolve()
    accumulators: dict[str, DatasetAccumulator] = {}
    data_files = discover_data_files(repo_root)
    for path in data_files:
        relative = path.relative_to(repo_root).as_posix()
        dataset_id = dataset_id_for_path(relative)
        accumulator = accumulators.setdefault(dataset_id, DatasetAccumulator(dataset_id))
        accumulator.source_paths.append(relative)
        accumulator.source_files.append({
            "path": relative,
            "sha256": sha256_file(path),
            "bytes": path.stat().st_size,
        })
        try:
            document = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
            accumulator.errors.append({"path": relative, "error": str(exc)})
            continue
        observe_document(accumulator, document, relative)

    sources = scan_sources(repo_root)
    datasets: list[dict[str, Any]] = []
    for dataset_id in sorted(accumulators):
        accumulator = accumulators[dataset_id]
        fields: list[dict[str, Any]] = []
        declared_only = declared_only_fields(dataset_id, sources)
        observed_keys: set[str] = set()
        for (field_path, scope), field_accumulator in sorted(accumulator.fields.items()):
            observed_keys.add(field_path)
            declared = declared_evidence_for_field(dataset_id, field_path, sources)
            fields.append(render_field(field_accumulator, accumulator.scopes[scope], declared))
        # Add only declarations that can be matched to a known field leaf and
        # are truly absent.  This avoids turning every validator's generic
        # string into a guessed schema field.
        for field_name, declaration in sorted(declared_only.items()):
            if field_name in observed_keys:
                continue
            evidence = declaration["evidence"]
            fields.append({
                "field": field_name,
                "record_scope": "document",
                "observed": False,
                "observed_type": None,
                "observed_type_variants": [],
                "observed_item_type": None,
                "nullable": None,
                "required_by_observation": None,
                "required_status": "runtime-snapshot-required" if "RUNTIME_SNAPSHOT" in declaration["scopes"] else "declared-required" if declaration["required"] else "unknown",
                "optional_by_observation": False,
                "default": None,
                "default_explicitly_defined": False,
                "default_expressions": [],
                "defaults_observed_from_loader": [],
                "unique": None,
                "id_field": bool(declaration.get("id_kinds")),
                "id_kind": None,
                "declared_id_kinds": sorted(declaration.get("id_kinds", set())),
                "id_kind_constraints": sorted(declaration.get("id_kinds", set())),
                "declared_foreign_key_targets": [],
                "foreign_key": None,
                "enum_candidates": [],
                "enum_evidence": "NONE",
                "numeric_min": None,
                "numeric_max": None,
                "example_values": [],
                "record_count": None,
                "present_count": 0,
                "missing_count": None,
                "declared": True,
                "declared_types": sorted(declaration["types"]),
                "declared_required": declaration["required"] and "SOURCE_CONFIG" in declaration["scopes"],
                "source_config_required": "SOURCE_CONFIG" in declaration["scopes"],
                "runtime_snapshot_required": "RUNTIME_SNAPSHOT" in declaration["scopes"],
                "declared_evidence_scopes": sorted(declaration["scopes"]),
                "declared_enum_values": sorted(declaration["enum_values"]),
                "declared_evidence": sorted(evidence, key=lambda item: (item["source"], item["line"], item["kind"])),
                "heuristic_evidence": [],
                "loader_consumed": True,
                "loader_usage": [],
                "notes": [
                    "DECLARED by exact loader/validator path evidence but not observed in the scoped JSON input.",
                    "Required by a runtime snapshot validator; this is not a source JSON requirement."
                    if "RUNTIME_SNAPSHOT" in declaration["scopes"]
                    else "This field is absent from the scoped source document.",
                ],
            })
        geometry_evidence = summarize_geometry_evidence(accumulator.geometry_records)
        for field in fields:
            if field["field"].startswith("features[].geometry.coordinates") and geometry_evidence["by_type"]:
                field["geometry_type_conditioned"] = geometry_evidence["by_type"]
                field["observed_type_unconditioned"] = field["observed_type"]
                field["observed_type_variants_unconditioned"] = field["observed_type_variants"]
                field["observed_type"] = "type-conditioned geometry coordinates"
                field["observed_type_variants"] = ["type-conditioned"]
                field["notes"].append(
                    "Coordinate nesting is conditioned by geometry.type; Polygon/MultiPolygon depth differences are legal polymorphism."
                )
        fields.sort(key=lambda item: (item["field"], item["record_scope"], not item["observed"]))
        collections = [
            {
                "path": collection.path,
                "record_count": collection.count,
                "source_file_count": len(collection.source_paths),
            }
            for collection in sorted(accumulator.collections.values(), key=lambda item: item.path)
        ]
        primary = primary_record_path(dataset_id, accumulator.collections)
        record_count = accumulator.scopes.get(primary, accumulator.document_count) if primary != "document" else accumulator.document_count
        dataset_sources = [
            source for source in sources
            if dataset_id in source["targets"] or any(dataset_id_for_path(path_ref["path"]) == dataset_id for path_ref in source["path_references"])
        ]
        datasets.append({
            "dataset": dataset_id,
            "path": (
                "data/world_map/city_detail/countries/*.json" if dataset_id == "world_map.city_detail.country_shards" else
                "data/world_map/city_detail/france/*.json" if dataset_id == "world_map.city_detail.france_shards" else
                accumulator.source_paths[0]
            ),
            "source_paths": sorted(accumulator.source_paths),
            "source_files": sorted(accumulator.source_files, key=lambda item: item["path"]),
            "description": DATASET_DESCRIPTIONS.get(dataset_id, "Purpose inferred from the data path and loader evidence."),
            "record_shape": {
                "root_type": normalize_types(accumulator.root_types),
                "primary_record_path": primary,
                "record_collections": collections,
            },
            "record_count": record_count,
            "document_count": accumulator.document_count,
            "fields": fields,
            "loader_evidence": [
                {
                    "source": source["source"],
                    "sha256": source["sha256"],
                    "targets": source["targets"],
                    "path_references": source["path_references"],
                    "field_accesses": source["field_accesses"],
                    "enum_constants": source["enum_constants"],
                    "required_blocks": source["required_blocks"],
                    "exact_contract": source.get("exact_contract", False),
                    "contract_scope": source.get("contract_scope", "UNKNOWN"),
                }
                for source in dataset_sources
            ],
            "input_errors": sorted(accumulator.errors, key=lambda item: item["path"]),
            "geometry_evidence": geometry_evidence,
            "notes": [
                "Observed fields and values are derived from the current JSON inputs.",
                "Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.",
                "This dictionary does not redefine the production schema and does not imply that every loader access is a required field.",
            ],
        })

    relationships, fk_issues, fk_candidates = attach_foreign_keys(datasets)
    findings = build_findings(datasets, relationships, fk_issues)
    declared_count = sum(1 for dataset in datasets for field in dataset["fields"] if field["declared"])
    observed_only_count = sum(1 for dataset in datasets for field in dataset["fields"] if field["observed"] and not field["declared"])
    type_inconsistency_count = sum(1 for item in findings if item["kind"] == "type_inconsistency")
    obsolete_count = sum(1 for item in findings if item["kind"] == "potentially_ignored_field")
    ambiguity_count = sum(1 for item in findings if item["kind"] in {
        "foreign_key_unclear_target", "foreign_key_ambiguous_target", "duplicate_semantic_fields",
        "nullable_and_missing_inconsistency", "loader_expects_field_absent_from_data",
    })
    return {
        "schema_version": 1,
        "generator": TOOL_VERSION,
        "input_roots": list(DATA_ROOTS),
        "source_roots": list(SOURCE_ROOTS),
        "datasets": datasets,
        "foreign_key_relationships": relationships,
        "foreign_key_candidates": fk_candidates,
        "findings": findings,
        "summary": {
            "datasets_documented": len(datasets),
            "fields_documented": sum(len(dataset["fields"]) for dataset in datasets),
            "declared_schema_fields": declared_count,
            "observed_only_fields": observed_only_count,
            "type_inconsistencies": type_inconsistency_count,
            "potential_obsolete_fields": obsolete_count,
            "foreign_key_relationships": len(relationships),
            "foreign_key_candidates": len(fk_candidates),
            "ambiguous_relationships": len(fk_issues),
            "schema_ambiguities": ambiguity_count,
            "data_files_scanned": len(data_files),
            "loader_sources_scanned": len(sources),
            "input_errors": sum(len(dataset["input_errors"]) for dataset in datasets),
        },
        "generation_contract": {
            "deterministic": True,
            "production_data_modified": False,
            "observed_schema_is_normative": False,
            "declared_schema_is_normative": False,
            "evidence_kinds": ["OBSERVED", "DECLARED", "HEURISTIC", "RUNTIME_SNAPSHOT", "ID_KIND_CONSTRAINT", "FOREIGN_KEY"],
        },
    }


def compact(value: Any, limit: int = 180) -> str:
    text = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) if not isinstance(value, str) else value
    return text if len(text) <= limit else text[: limit - 3] + "..."


def markdown_cell(value: Any, limit: int = 180) -> str:
    text = compact(value, limit).replace("|", "\\|").replace("\n", " ")
    return text if text else "—"


def render_dataset_markdown(dataset: dict[str, Any]) -> str:
    lines = [
        f"# {dataset['dataset']}",
        "",
        "<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->",
        "",
        f"{dataset['description']}",
        "",
        f"- Path: `{dataset['path']}`",
        f"- Source files: `{len(dataset['source_paths'])}`",
        f"- Record count (primary collection): `{dataset['record_count']}`",
        f"- Documents: `{dataset['document_count']}`",
        f"- Root type: `{dataset['record_shape']['root_type']}`",
        f"- Primary record path: `{dataset['record_shape']['primary_record_path']}`",
        "",
        "## Record collections",
        "",
        "| path | records | source files |",
        "| --- | ---: | ---: |",
    ]
    collections = dataset["record_shape"]["record_collections"]
    if collections:
        for collection in collections:
            lines.append(f"| `{collection['path']}` | {collection['record_count']} | {collection['source_file_count']} |")
    else:
        lines.append("| `document` | 1 per source document | — |")
    lines.extend([
        "",
        "## Fields",
        "",
        "`OBSERVED` values come from JSON. `DECLARED` requires exact normalized field-path evidence. `HEURISTIC` and `RUNTIME_SNAPSHOT` evidence never silently become source-schema authority.",
        "",
        "| field | scope | observed type | nullable | required by observation | source config required | runtime snapshot required | required status | missing / records | default | unique | ID | foreign key / candidate | enum candidates | min–max | examples | evidence |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |",
    ])
    for field in dataset["fields"]:
        missing_records = f"{field['missing_count']} / {field['record_count']}" if field["missing_count"] is not None else "—"
        declared = "DECLARED" if field["declared"] else "OBSERVED"
        if field["declared"] and field["observed"]:
            declared = "OBSERVED + DECLARED"
        fk = field["foreign_key"]
        fk_text = "—"
        if fk:
            target = fk.get("to_dataset", ", ".join(fk.get("candidates", [])))
            fk_text = f"{fk.get('evidence', 'FOREIGN_KEY')}: {target}"
        range_text = "—"
        if field["numeric_min"] is not None:
            range_text = f"{field['numeric_min']}–{field['numeric_max']}"
        id_parts = []
        if field.get("id_kind"):
            id_parts.append(field["id_kind"])
        if field.get("declared_id_kinds"):
            id_parts.append("ID_KIND_CONSTRAINT: " + ", ".join(field["declared_id_kinds"]))
        id_text = "; ".join(id_parts) if id_parts else "—"
        lines.append(
            "| {field} | {scope} | {observed} / declared `{declared_types}` | {nullable} | {required} | {source_config} | {runtime_snapshot} | {status} | {missing} | {default} | {unique} | {id} | {fk} | {enum} | {range} | {examples} | {evidence} |".format(
                field=f"`{field['field']}`",
                scope=f"`{field['record_scope']}`",
                observed=field["observed_type"] or "UNOBSERVED",
                declared_types=",".join(field["declared_types"]) or "—",
                nullable=field["nullable"] if field["nullable"] is not None else "—",
                required=field["required_by_observation"] if field["required_by_observation"] is not None else "—",
                source_config=field.get("source_config_required", False),
                runtime_snapshot=field.get("runtime_snapshot_required", False),
                status=field["required_status"],
                missing=missing_records,
                default=markdown_cell(field["default"]),
                unique=field["unique"] if field["unique"] is not None else "—",
                id=id_text,
                fk=markdown_cell(fk_text),
                enum=markdown_cell(field["enum_candidates"]),
                range=range_text,
                examples=markdown_cell(field["example_values"]),
                evidence=declared,
            )
        )
    if dataset["input_errors"]:
        lines.extend(["", "## Input errors", ""])
        for error in dataset["input_errors"]:
            lines.append(f"- `{error['path']}`: {error['error']}")
    lines.extend(["", "## Geometry evidence", ""])
    geometry = dataset.get("geometry_evidence", {})
    if geometry.get("by_type"):
        for geometry_type, entry in geometry["by_type"].items():
            lines.append(
                f"- `{geometry_type}`: `{entry['record_count']}` records; shapes `{', '.join(entry['coordinate_shapes'])}`; malformed `{entry['invalid_count']}`."
            )
    else:
        lines.append("- None observed.")
    lines.extend(["", "## Notes", ""])
    for note in dataset["notes"]:
        lines.append(f"- {note}")
    return "\n".join(lines) + "\n"


def render_index_markdown(dictionary: dict[str, Any]) -> str:
    summary = dictionary["summary"]
    lines = [
        "# WWO World Data Dictionary — Batch 1",
        "",
        "<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->",
        "",
        "This reference is generated from `data/world_map/**`, pure JSON data under `data/vnext/**`, and related loader/parser/validator evidence. It is an inventory of the current state, not a schema redesign.",
        "",
        "## Evidence contract",
        "",
        "- `OBSERVED`: directly measured from the current JSON files.",
        "- `DECLARED`: exact normalized full-field-path evidence from a loader, validator, or source-config contract.",
        "- `HEURISTIC`: leaf-only, test, tooling, and name-based evidence retained for review; it is not schema authority.",
        "- `RUNTIME_SNAPSHOT`: restore/validator requirements for derived runtime state, not source JSON requirements.",
        "- `ID_KIND_CONSTRAINT`: stable-ID syntax/kind validation only; it does not prove catalog membership.",
        "- `FOREIGN_KEY`: only a resolved loader/catalog reference is declared; name-based links remain candidates or ambiguous.",
        "- `OBSERVED + DECLARED`: both kinds of evidence exist; differences remain visible in each field row.",
        "",
        "## Summary",
        "",
        "| metric | value |",
        "| --- | ---: |",
    ]
    summary_labels = (
        ("datasets documented", "datasets_documented"),
        ("fields documented", "fields_documented"),
        ("declared-schema fields", "declared_schema_fields"),
        ("observed-only fields", "observed_only_fields"),
        ("type inconsistencies", "type_inconsistencies"),
        ("potentially ignored/obsolete leads", "potential_obsolete_fields"),
        ("foreign-key relationships", "foreign_key_relationships"),
        ("foreign-key candidates", "foreign_key_candidates"),
        ("ambiguous relationships", "ambiguous_relationships"),
        ("data files scanned", "data_files_scanned"),
        ("loader sources scanned", "loader_sources_scanned"),
    )
    for label, key in summary_labels:
        lines.append(f"| {label} | {summary[key]} |")
    lines.extend(["", "## Dataset reference", "", "| dataset | path | records | fields |", "| --- | --- | ---: | ---: |"])
    for dataset in dictionary["datasets"]:
        file_name = dataset["dataset"].replace("/", "_").replace(".", "_") + ".md"
        lines.append(f"| [{dataset['dataset']}]({file_name}) | `{dataset['path']}` | {dataset['record_count']} | {len(dataset['fields'])} |")
    lines.extend(["", "## Top 30 data-schema ambiguities", "", "The list is sorted by risk/severity and stable dataset/field order. High-risk items are the most likely to cause a future Agent to insert an invalid ID, wrong type, or undocumented enum value.", "", "| # | risk | severity | kind | dataset | field | why it matters |", "| ---: | --- | --- | --- | --- | --- | --- |"])
    for index, finding in enumerate(dictionary["findings"][:30], 1):
        lines.append(
            f"| {index} | {finding.get('risk', 'low')} | {finding.get('severity', 'low')} | `{finding.get('kind', '')}` | `{finding.get('dataset', '')}` | `{finding.get('field', '')}` | {markdown_cell(finding.get('message', ''), 220)} |"
        )
    lines.extend(["", "## Generated files", "", "- `dictionary.json`: machine-readable dictionary, evidence, relationships, and findings.", "- `README.md`: this index and the top ambiguity list.", "- `datasets/*.md`: one human-readable reference per logical dataset.", "", "Production data modified: **NO**.", ""])
    return "\n".join(lines)


def render_outputs(dictionary: dict[str, Any]) -> dict[str, str]:
    outputs = {
        "dictionary.json": json.dumps(dictionary, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        "README.md": render_index_markdown(dictionary),
    }
    for dataset in dictionary["datasets"]:
        file_name = dataset["dataset"].replace("/", "_").replace(".", "_") + ".md"
        outputs[f"datasets/{file_name}"] = render_dataset_markdown(dataset)
    return outputs


def write_or_check(repo_root: Path, output_root: Path, *, check: bool) -> int:
    dictionary = build_dictionary(repo_root)
    outputs = render_outputs(dictionary)
    failures: list[str] = []
    if not check:
        output_root.mkdir(parents=True, exist_ok=True)
    expected = set(outputs)
    existing = {
        path.relative_to(output_root).as_posix()
        for path in output_root.rglob("*")
        if path.is_file()
    } if output_root.exists() else set()
    for relative, content in outputs.items():
        path = output_root / relative
        if check:
            if not path.exists() or path.read_text(encoding="utf-8") != content:
                failures.append(relative)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8", newline="\n")
    stale = sorted(existing - expected)
    if stale:
        failures.extend(f"stale:{item}" for item in stale)
    print(json.dumps(dictionary["summary"], ensure_ascii=False, sort_keys=True))
    if failures:
        print("generated output mismatch: " + ", ".join(sorted(failures)), file=sys.stderr)
        return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--output-root", type=Path, default=None)
    parser.add_argument("--check", action="store_true", help="Verify generated files without writing them.")
    args = parser.parse_args(argv)
    repo_root = args.repo_root.resolve()
    output_root = (args.output_root or repo_root / "docs/generated/world_data_dictionary").resolve()
    return write_or_check(repo_root, output_root, check=args.check)


if __name__ == "__main__":
    raise SystemExit(main())
