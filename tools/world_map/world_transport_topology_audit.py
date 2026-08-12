#!/usr/bin/env python3
"""Deterministic, read-only QA for the current world transport topology.

This tool intentionally does not import Godot or any gameplay service.  It
loads the accepted world-map JSON documents, mirrors the endpoint contract
used by the current map loader, and builds an analysis-only graph.  It never
writes under ``data/world_map``.  Output files are written only when an
explicit output argument is supplied.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import subprocess
import sys
from collections import Counter, defaultdict, deque
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Optional


SCHEMA_VERSION = "world-transport-topology-audit/v1"
DEFAULT_STARTING_MASTER = "unknown"
WORLD_MAP_ROOT = Path("data/world_map")
LOADER_PATHS = (
    "scripts/world_map/internal/world_map_data_impl.gd",
    "scripts/world_map/internal/world_map_canvas_impl.gd",
)
SOURCE_PATHS = (
    "data/world_map/countries.json",
    "data/world_map/regions.json",
    "data/world_map/cities.json",
    "data/world_map/ports.json",
    "data/world_map/road_segments.json",
    "data/world_map/rail_segments.json",
    "data/world_map/shipping_routes.json",
    "data/world_map/map_geometry_cache.json",
)
MODE_SPECS: dict[str, dict[str, str]] = {
    "road": {
        "path": "data/world_map/road_segments.json",
        "collection": "segments",
        "endpoint_type": "city",
        "from_key": "from_city_id",
        "to_key": "to_city_id",
    },
    "rail": {
        "path": "data/world_map/rail_segments.json",
        "collection": "segments",
        "endpoint_type": "city",
        "from_key": "from_city_id",
        "to_key": "to_city_id",
    },
    "shipping": {
        "path": "data/world_map/shipping_routes.json",
        "collection": "routes",
        "endpoint_type": "port",
        "from_key": "from_port_id",
        "to_key": "to_port_id",
    },
}
MODE_ORDER = ("road", "rail", "shipping")
ENTITY_ORDER = ("country", "region", "city", "port")
STATUS_ORDER = {
    "BROKEN_REFERENCE": 0,
    "SUSPICIOUS_ISOLATION": 1,
    "AMBIGUOUS": 2,
    "EXPECTED_ISOLATION": 3,
}
PRIORITY_ORDER = {"P0": 0, "P1": 1, "P2": 2, "P3": 3}
IMPACT_ORDER = {"Economy": 0, "Military": 1, "Spatial": 2}
ZERO_LENGTH_EPSILON = 1e-9
GEOMETRY_ENDPOINT_TOLERANCE_DEGREES = 0.25


def canonical_bytes(value: Any) -> bytes:
    """Return the stable JSON representation used by tests and artifacts."""

    return (
        json.dumps(
            value,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
        + b"\n"
    )


def relative_path(path: Path, root: Path) -> str:
    return path.resolve().relative_to(root.resolve()).as_posix()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def as_string(value: Any) -> str:
    if value is None:
        return ""
    return str(value).strip()


def as_records(document: Any, key: str) -> list[dict[str, Any]]:
    if not isinstance(document, dict):
        return []
    value = document.get(key, [])
    if not isinstance(value, list):
        return []
    return [item for item in value if isinstance(item, dict)]


def coordinate(value: Any) -> Optional[tuple[float, float]]:
    if not isinstance(value, (list, tuple)) or len(value) < 2:
        return None
    try:
        lon = float(value[0])
        lat = float(value[1])
    except (TypeError, ValueError):
        return None
    if not math.isfinite(lon) or not math.isfinite(lat):
        return None
    return lon, lat


def coordinate_distance(first: Optional[tuple[float, float]], second: Optional[tuple[float, float]]) -> float:
    if first is None or second is None:
        return math.inf
    return math.hypot(first[0] - second[0], first[1] - second[1])


def sorted_unique(values: Iterable[str]) -> list[str]:
    return sorted({value for value in values if value})


@dataclass(frozen=True)
class GraphNode:
    node_id: str
    node_type: str
    country_id: str = ""
    region_id: str = ""
    city_id: str = ""
    major: bool = False
    label_priority: int = 0


@dataclass(frozen=True)
class GraphEdge:
    edge_id: str
    mode: str
    from_id: str
    to_id: str
    source_path: str = ""
    source_index: int = -1
    directionality: str = "UNSPECIFIED"


class TransportGraph:
    """Small analysis-only graph with deterministic undirected traversal."""

    def __init__(self) -> None:
        self.nodes: dict[str, GraphNode] = {}
        self.edges: list[GraphEdge] = []

    def add_node(self, node: GraphNode) -> None:
        self.nodes[node.node_id] = node

    def add_edge(self, edge: GraphEdge) -> None:
        self.edges.append(edge)

    def edges_for_mode(self, mode: str) -> list[GraphEdge]:
        return sorted(
            (edge for edge in self.edges if edge.mode == mode),
            key=lambda edge: (edge.edge_id, edge.from_id, edge.to_id),
        )

    def neighbors(self, node_id: str, modes: Optional[set[str]] = None) -> list[str]:
        neighbors: set[str] = set()
        for edge in self.edges:
            if modes is not None and edge.mode not in modes:
                continue
            if edge.from_id == node_id:
                neighbors.add(edge.to_id)
            elif edge.to_id == node_id:
                neighbors.add(edge.from_id)
        return sorted(neighbors)

    def reachable(self, start_id: str, modes: Optional[set[str]] = None) -> list[str]:
        if start_id not in self.nodes:
            return []
        visited: set[str] = {start_id}
        queue: deque[str] = deque([start_id])
        while queue:
            current = queue.popleft()
            for neighbor in self.neighbors(current, modes):
                if neighbor in visited:
                    continue
                visited.add(neighbor)
                queue.append(neighbor)
        return sorted(visited)

    def components(
        self,
        modes: set[str],
        node_types: Optional[set[str]] = None,
    ) -> list[list[str]]:
        node_ids = sorted(
            node_id
            for node_id, node in self.nodes.items()
            if node_types is None or node.node_type in node_types
        )
        remaining = set(node_ids)
        result: list[list[str]] = []
        while remaining:
            start_id = min(remaining)
            component = self.reachable(start_id, modes)
            component = sorted(
                node_id for node_id in component if node_id in remaining
            )
            if not component:
                component = [start_id]
            result.append(component)
            remaining.difference_update(component)
        return sorted(result, key=lambda component: (component[0], len(component), component))

    def component_for(
        self,
        node_id: str,
        modes: set[str],
        node_types: Optional[set[str]] = None,
    ) -> list[str]:
        allowed = {
            candidate_id
            for candidate_id, node in self.nodes.items()
            if node_types is None or node.node_type in node_types
        }
        return sorted(candidate_id for candidate_id in self.reachable(node_id, modes) if candidate_id in allowed)


def directionality_of(record: dict[str, Any]) -> str:
    if "directed" in record:
        return "DIRECTED" if bool(record.get("directed")) else "BIDIRECTIONAL"
    if "bidirectional" in record:
        return "BIDIRECTIONAL" if bool(record.get("bidirectional")) else "DIRECTED"
    if "directionality" in record:
        value = as_string(record.get("directionality")).upper()
        return value or "UNSPECIFIED"
    return "UNSPECIFIED"


def classification_basis(check: str, status: str, evidence: dict[str, Any]) -> str:
    if status == "BROKEN_REFERENCE":
        return "concrete_schema_reference_or_loader_cache_evidence"
    if check == "UNREACHABLE_MAJOR_NODE" and evidence.get("major") is True:
        return "explicit_city_major_metadata"
    if check == "ISOLATED_CITY":
        if evidence.get("major") is True:
            return "explicit_city_major_metadata"
        return "explicit_non_major_metadata_coverage_heuristic"
    if check == "MISSING_MAP_ANCHOR" and evidence.get("major") is True:
        return "explicit_major_metadata_plus_loader_anchor_contract"
    if check == "PORT_WITHOUT_SHIPPING_CONNECTIVITY":
        return "declared_port_without_route_review_heuristic"
    if check == "ISOLATED_ADMINISTRATIVE_REGION" and evidence.get("has_port") is True:
        return "declared_port_in_region_review_heuristic"
    if status == "EXPECTED_ISOLATION" and evidence.get("child_city_count", 1) == 0 and evidence.get("child_port_count", 1) == 0:
        return "explicit_empty_child_catalog"
    if status == "AMBIGUOUS":
        return "missing_intent_or_directionality_review"
    return "catalog_coverage_review_signal"

def make_issue(
    check: str,
    status: str,
    subject: str,
    priority: str,
    message: str,
    *,
    mode: str = "",
    source_paths: Optional[Iterable[str]] = None,
    evidence: Optional[dict[str, Any]] = None,
    impacts: Optional[Iterable[str]] = None,
    suggestion: str = "",
    mechanical_fix: bool = False,
) -> dict[str, Any]:
    return {
        "id": "",
        "check": check,
        "status": status,
        "priority": priority,
        "priority_semantics": "AUDIT_TRIAGE_ONLY_NOT_CODE_REVIEW_SEVERITY",
        "concrete_contract_error": status == "BROKEN_REFERENCE",
        "authoritative_data_error_proven": False,
        "automatic_repair_authorized": False,
        "review_only": status != "BROKEN_REFERENCE",
        "classification_basis": classification_basis(check, status, evidence or {}),
        "mode": mode,
        "subject": subject,
        "message": message,
        "source_paths": sorted_unique(source_paths or []),
        "evidence": evidence or {},
        "impacts": sorted(
            set(impacts or []),
            key=lambda impact: IMPACT_ORDER.get(impact, 99),
        ),
        "suggestion": suggestion,
        "mechanical_fix": mechanical_fix,
    }


def finding_sort_key(finding: dict[str, Any]) -> tuple[Any, ...]:
    impact_rank = min(
        (IMPACT_ORDER.get(str(impact), 99) for impact in finding.get("impacts", [])),
        default=99,
    )
    return (
        impact_rank,
        PRIORITY_ORDER.get(str(finding.get("priority", "P3")), 99),
        STATUS_ORDER.get(str(finding.get("status", "AMBIGUOUS")), 99),
        str(finding.get("check", "")),
        str(finding.get("mode", "")),
        str(finding.get("subject", "")),
        str(finding.get("message", "")),
    )


def finalize_findings(findings: list[dict[str, Any]]) -> list[dict[str, Any]]:
    finalized = sorted(findings, key=finding_sort_key)
    for index, finding in enumerate(finalized, start=1):
        finding["id"] = f"TT-{index:04d}"
    return finalized


def load_source_documents(root: Path) -> tuple[dict[str, Any], list[dict[str, str]]]:
    documents: dict[str, Any] = {}
    errors: list[dict[str, str]] = []
    for path_string in sorted(set(SOURCE_PATHS)):
        path = root / Path(path_string)
        try:
            documents[path_string] = read_json(path)
        except FileNotFoundError:
            errors.append({"path": path_string, "error": "missing_file"})
        except (OSError, UnicodeError, json.JSONDecodeError) as error:
            errors.append({"path": path_string, "error": str(error)})
    return documents, errors


def inventory_world_map(root: Path) -> tuple[list[dict[str, Any]], list[dict[str, str]]]:
    base = root / WORLD_MAP_ROOT
    inventory: list[dict[str, Any]] = []
    parse_errors: list[dict[str, str]] = []
    if not base.is_dir():
        return [], [{"path": WORLD_MAP_ROOT.as_posix(), "error": "missing_directory"}]
    for path in sorted(path for path in base.rglob("*") if path.is_file()):
        data = path.read_bytes()
        rel = relative_path(path, root)
        entry: dict[str, Any] = {
            "path": rel,
            "size_bytes": len(data),
            "sha256": sha256_bytes(data),
        }
        if path.suffix.lower() == ".json":
            try:
                json.loads(data.decode("utf-8"))
                entry["json_parse"] = "PASS"
            except (UnicodeDecodeError, json.JSONDecodeError, TypeError) as error:
                entry["json_parse"] = "FAIL"
                parse_errors.append({"path": rel, "error": str(error)})
        inventory.append(entry)
    return inventory, parse_errors


def loader_contract(root: Path) -> dict[str, Any]:
    required: dict[str, list[str]] = {
        "scripts/world_map/internal/world_map_data_impl.gd": [
            '"ports": "res://data/world_map/ports.json"',
            '"rail_segments": "res://data/world_map/rail_segments.json"',
            '"road_segments": "res://data/world_map/road_segments.json"',
            '"shipping_routes": "res://data/world_map/shipping_routes.json"',
        ],
        "scripts/world_map/internal/world_map_canvas_impl.gd": [
            '_ports = _document_array("ports", "ports")',
            '_rail_segments = _document_array("rail_segments", "segments")',
            '_road_segments = _document_array("road_segments", "segments")',
            '_shipping_routes = _document_array("shipping_routes", "routes")',
            '_load_fixed_geometry_cache()',
            '_build_transport_tie_cache()',
        ],
    }
    files: list[dict[str, Any]] = []
    missing_tokens: list[dict[str, str]] = []
    for path_string in LOADER_PATHS:
        path = root / Path(path_string)
        try:
            content = path.read_text(encoding="utf-8")
        except (FileNotFoundError, OSError, UnicodeError) as error:
            files.append({"path": path_string, "status": "FAIL", "error": str(error)})
            for token in required.get(path_string, []):
                missing_tokens.append({"path": path_string, "token": token})
            continue
        files.append(
            {
                "path": path_string,
                "status": "PASS",
                "sha256": sha256_bytes(content.encode("utf-8")),
            }
        )
        for token in required.get(path_string, []):
            if token not in content:
                missing_tokens.append({"path": path_string, "token": token})
    return {
        "status": "PASS" if not missing_tokens else "FAIL",
        "files": files,
        "required_tokens": required,
        "missing_tokens": missing_tokens,
        "field_contract": {
            mode: {
                "source_path": spec["path"],
                "collection": spec["collection"],
                "endpoint_type": spec["endpoint_type"],
                "from_key": spec["from_key"],
                "to_key": spec["to_key"],
            }
            for mode, spec in sorted(MODE_SPECS.items())
        },
        "interpretation": {
            "road_endpoints": "city",
            "rail_endpoints": "city",
            "shipping_endpoints": "port",
            "transport_traversal": "undirected_analysis_assumption",
            "geometry_cache": "index_aligned_with_source_records",
        },
    }


def add_catalog_nodes(
    graph: TransportGraph,
    records: list[dict[str, Any]],
    node_type: str,
    findings: list[dict[str, Any]],
) -> dict[str, dict[str, Any]]:
    catalog: dict[str, dict[str, Any]] = {}
    for index, record in enumerate(records):
        node_id = as_string(record.get("id"))
        source = f"data/world_map/{'cities' if node_type == 'city' else 'ports'}.json"
        if not node_id:
            findings.append(
                make_issue(
                    "MISSING_NODE_ID",
                    "BROKEN_REFERENCE",
                    f"{node_type}[{index}]",
                    "P1",
                    f"{node_type} record has no stable id.",
                    source_paths=[source],
                    evidence={"record_index": index},
                    impacts=["Spatial"],
                )
            )
            continue
        if node_id in catalog:
            findings.append(
                make_issue(
                    "DUPLICATE_NODE_ID",
                    "BROKEN_REFERENCE",
                    node_id,
                    "P1",
                    f"Duplicate {node_type} id appears more than once.",
                    source_paths=[source],
                    evidence={"first_index": catalog[node_id].get("_index"), "duplicate_index": index},
                    impacts=["Spatial", "Economy"],
                )
            )
            continue
        existing_node = graph.nodes.get(node_id)
        if existing_node is not None and existing_node.node_type != node_type:
            other_source = "data/world_map/ports.json" if node_type == "city" else "data/world_map/cities.json"
            findings.append(
                make_issue(
                    "CITY_PORT_ID_NAMESPACE_COLLISION",
                    "BROKEN_REFERENCE",
                    node_id,
                    "P0",
                    "City and port catalogs reuse the same id; graph identity would be ambiguous.",
                    source_paths=[source, other_source],
                    evidence={"existing_node_type": existing_node.node_type, "colliding_id": node_id},
                    impacts=["Economy", "Military", "Spatial"],
                )
            )
            continue
        record = dict(record)
        record["_index"] = index
        catalog[node_id] = record
        graph.add_node(
            GraphNode(
                node_id=node_id,
                node_type=node_type,
                country_id=as_string(record.get("parent_country_id")),
                region_id=as_string(record.get("parent_region_id")),
                city_id=as_string(record.get("city_id")) if node_type == "port" else node_id,
                major=bool(record.get("major", False)),
                label_priority=int(record.get("label_priority", 0) or 0),
            )
        )
    return catalog


def validate_place_references(
    cities: dict[str, dict[str, Any]],
    ports: dict[str, dict[str, Any]],
    regions: list[dict[str, Any]],
    countries: list[dict[str, Any]],
    findings: list[dict[str, Any]],
) -> None:
    region_ids = {as_string(record.get("id")) for record in regions if as_string(record.get("id"))}
    country_ids = {as_string(record.get("id")) for record in countries if as_string(record.get("id"))}
    for city_id, city in sorted(cities.items()):
        country_id = as_string(city.get("parent_country_id"))
        region_id = as_string(city.get("parent_region_id"))
        if country_id not in country_ids:
            findings.append(
                make_issue(
                    "CITY_PARENT_COUNTRY_REFERENCE",
                    "BROKEN_REFERENCE",
                    city_id,
                    "P1",
                    "City references a missing parent country.",
                    source_paths=["data/world_map/cities.json", "data/world_map/countries.json"],
                    evidence={"parent_country_id": country_id},
                    impacts=["Economy", "Military", "Spatial"],
                )
            )
        if region_id and region_id not in region_ids:
            findings.append(
                make_issue(
                    "CITY_PARENT_REGION_REFERENCE",
                    "BROKEN_REFERENCE",
                    city_id,
                    "P1",
                    "City references a missing parent region.",
                    source_paths=["data/world_map/cities.json", "data/world_map/regions.json"],
                    evidence={"parent_region_id": region_id},
                    impacts=["Economy", "Military", "Spatial"],
                )
            )
    for port_id, port in sorted(ports.items()):
        city_id = as_string(port.get("city_id"))
        country_id = as_string(port.get("parent_country_id"))
        region_id = as_string(port.get("parent_region_id"))
        if city_id not in cities:
            findings.append(
                make_issue(
                    "PORT_CITY_REFERENCE",
                    "BROKEN_REFERENCE",
                    port_id,
                    "P1",
                    "Port references a missing city.",
                    source_paths=["data/world_map/ports.json", "data/world_map/cities.json"],
                    evidence={"city_id": city_id},
                    impacts=["Economy", "Military", "Spatial"],
                )
            )
        if country_id not in country_ids:
            findings.append(
                make_issue(
                    "PORT_PARENT_COUNTRY_REFERENCE",
                    "BROKEN_REFERENCE",
                    port_id,
                    "P1",
                    "Port references a missing parent country.",
                    source_paths=["data/world_map/ports.json", "data/world_map/countries.json"],
                    evidence={"parent_country_id": country_id},
                    impacts=["Economy", "Military", "Spatial"],
                )
            )
        if region_id and region_id not in region_ids:
            findings.append(
                make_issue(
                    "PORT_PARENT_REGION_REFERENCE",
                    "BROKEN_REFERENCE",
                    port_id,
                    "P1",
                    "Port references a missing parent region.",
                    source_paths=["data/world_map/ports.json", "data/world_map/regions.json"],
                    evidence={"parent_region_id": region_id},
                    impacts=["Economy", "Military", "Spatial"],
                )
            )
        city = cities.get(city_id, {})
        if city and country_id and country_id != as_string(city.get("parent_country_id")):
            findings.append(
                make_issue(
                    "PORT_COUNTRY_MISMATCH",
                    "BROKEN_REFERENCE",
                    port_id,
                    "P1",
                    "Port parent country disagrees with its city parent country.",
                    source_paths=["data/world_map/ports.json", "data/world_map/cities.json"],
                    evidence={"port_country_id": country_id, "city_country_id": as_string(city.get("parent_country_id"))},
                    impacts=["Economy", "Military", "Spatial"],
                )
            )
    for index, region in enumerate(regions):
        region_id = as_string(region.get("id"))
        country_id = as_string(region.get("parent_country_id"))
        if country_id and country_id not in country_ids:
            findings.append(
                make_issue(
                    "REGION_PARENT_COUNTRY_REFERENCE",
                    "BROKEN_REFERENCE",
                    region_id or f"region[{index}]",
                    "P2",
                    "Region references a missing parent country.",
                    source_paths=["data/world_map/regions.json", "data/world_map/countries.json"],
                    evidence={"parent_country_id": country_id},
                    impacts=["Economy", "Military", "Spatial"],
                )
            )


def endpoint_coordinate(
    node_id: str,
    node_type: str,
    cities: dict[str, dict[str, Any]],
    ports: dict[str, dict[str, Any]],
) -> Optional[tuple[float, float]]:
    record = (cities if node_type == "city" else ports).get(node_id, {})
    return coordinate(record.get("lon_lat"))


def validate_transport_records(
    graph: TransportGraph,
    documents: dict[str, Any],
    cities: dict[str, dict[str, Any]],
    ports: dict[str, dict[str, Any]],
    findings: list[dict[str, Any]],
) -> dict[str, list[dict[str, Any]]]:
    raw_records: dict[str, list[dict[str, Any]]] = {}
    all_ids = set(cities) | set(ports)
    directionality_by_mode: dict[str, Counter[str]] = {}
    for mode in MODE_ORDER:
        spec = MODE_SPECS[mode]
        records = as_records(documents.get(spec["path"], {}), spec["collection"])
        raw_records[mode] = records
        expected = cities if spec["endpoint_type"] == "city" else ports
        other = ports if spec["endpoint_type"] == "city" else cities
        seen_ids: dict[str, int] = {}
        seen_directed: dict[tuple[str, str], str] = {}
        seen_undirected: dict[tuple[str, str], list[str]] = defaultdict(list)
        directionality_by_mode[mode] = Counter()
        for index, record in enumerate(records):
            source = spec["path"]
            edge_id = as_string(record.get("id"))
            if not edge_id:
                findings.append(
                    make_issue(
                        "MISSING_EDGE_ID",
                        "BROKEN_REFERENCE",
                        f"{mode}[{index}]",
                        "P1",
                        "Transport record has no stable edge id.",
                        mode=mode,
                        source_paths=[source],
                        evidence={"record_index": index},
                        impacts=["Economy", "Military", "Spatial"],
                    )
                )
                edge_id = f"{mode}[{index}]"
            elif edge_id in seen_ids:
                findings.append(
                    make_issue(
                        "DUPLICATE_EDGE_ID",
                        "BROKEN_REFERENCE",
                        edge_id,
                        "P1",
                        "Transport records reuse the same edge id.",
                        mode=mode,
                        source_paths=[source],
                        evidence={"first_index": seen_ids[edge_id], "duplicate_index": index},
                        impacts=["Economy", "Military", "Spatial"],
                    )
                )
            else:
                seen_ids[edge_id] = index
            declared_type = as_string(record.get("type"))
            if declared_type and declared_type != mode:
                findings.append(
                    make_issue(
                        "IMPOSSIBLE_ENDPOINT_TYPE",
                        "BROKEN_REFERENCE",
                        edge_id,
                        "P1",
                        f"Transport record declares type {declared_type!r}, not {mode!r}.",
                        mode=mode,
                        source_paths=[source],
                        evidence={"declared_type": declared_type, "expected_type": mode},
                        impacts=["Economy", "Military", "Spatial"],
                    )
                )
            from_id = as_string(record.get(spec["from_key"]))
            to_id = as_string(record.get(spec["to_key"]))
            directionality = directionality_of(record)
            directionality_by_mode[mode][directionality] += 1
            if not from_id or not to_id:
                findings.append(
                    make_issue(
                        "MISSING_ENDPOINT",
                        "BROKEN_REFERENCE",
                        edge_id,
                        "P1",
                        "Transport record is missing an endpoint field.",
                        mode=mode,
                        source_paths=[source],
                        evidence={"from_id": from_id, "to_id": to_id, "from_key": spec["from_key"], "to_key": spec["to_key"]},
                        impacts=["Economy", "Military", "Spatial"],
                    )
                )
                continue
            if from_id not in expected or to_id not in expected:
                wrong_type_ids = sorted(
                    endpoint_id
                    for endpoint_id in (from_id, to_id)
                    if endpoint_id in other
                )
                if wrong_type_ids:
                    check = "INLAND_NODE_AS_SEA_ENDPOINT" if mode == "shipping" else "IMPOSSIBLE_ENDPOINT_TYPE"
                    findings.append(
                        make_issue(
                            check,
                            "BROKEN_REFERENCE",
                            edge_id,
                            "P0" if mode == "shipping" else "P1",
                            f"{mode} edge uses an id from the wrong endpoint catalog.",
                            mode=mode,
                            source_paths=[source],
                            evidence={"wrong_type_ids": wrong_type_ids, "expected_endpoint_type": spec["endpoint_type"]},
                            impacts=["Economy", "Military", "Spatial"],
                        )
                    )
                missing_ids = sorted(
                    endpoint_id
                    for endpoint_id in (from_id, to_id)
                    if endpoint_id not in all_ids
                )
                if missing_ids:
                    findings.append(
                        make_issue(
                            "TRANSPORT_EDGE_REFERENCING_MISSING_PLACE",
                            "BROKEN_REFERENCE",
                            edge_id,
                            "P0" if mode == "shipping" else "P1",
                            f"{mode} edge references a missing place.",
                            mode=mode,
                            source_paths=[source],
                            evidence={"missing_ids": missing_ids, "expected_endpoint_type": spec["endpoint_type"]},
                            impacts=["Economy", "Military", "Spatial"],
                        )
                    )
                continue
            if from_id == to_id:
                findings.append(
                    make_issue(
                        "SELF_LOOP",
                        "BROKEN_REFERENCE",
                        edge_id,
                        "P1",
                        "Transport edge starts and ends at the same node.",
                        mode=mode,
                        source_paths=[source],
                        evidence={"node_id": from_id},
                        impacts=["Economy", "Military", "Spatial"],
                    )
                )
            directed_pair = (from_id, to_id)
            reverse_pair = (to_id, from_id)
            if directed_pair in seen_directed:
                findings.append(
                    make_issue(
                        "DUPLICATE_EDGE",
                        "BROKEN_REFERENCE",
                        edge_id,
                        "P1",
                        "Transport edge duplicates an earlier directed edge.",
                        mode=mode,
                        source_paths=[source],
                        evidence={"prior_edge_id": seen_directed[directed_pair], "from_id": from_id, "to_id": to_id},
                        impacts=["Economy", "Military", "Spatial"],
                    )
                )
            elif reverse_pair in seen_directed:
                findings.append(
                    make_issue(
                        "REVERSE_DUPLICATE",
                        "SUSPICIOUS_ISOLATION",
                        edge_id,
                        "P1",
                        "Transport edge duplicates an earlier edge in reverse order.",
                        mode=mode,
                        source_paths=[source],
                        evidence={"prior_edge_id": seen_directed[reverse_pair], "from_id": from_id, "to_id": to_id},
                        impacts=["Economy", "Military", "Spatial"],
                    )
                )
                findings.append(
                    make_issue(
                        "ROUTE_INCONSISTENT_DIRECTIONALITY",
                        "AMBIGUOUS",
                        f"{from_id}<->{to_id}",
                        "P2",
                        "Both endpoint directions are present, but route directionality is not declared consistently.",
                        mode=mode,
                        source_paths=[source],
                        evidence={"edge_id": edge_id, "prior_edge_id": seen_directed[reverse_pair], "directionality": directionality},
                        impacts=["Economy", "Military"],
                        suggestion="Confirm whether this route is bidirectional, then retain one canonical edge or declare directionality explicitly.",
                    )
                )
            seen_directed[directed_pair] = edge_id
            undirected_pair = tuple(sorted((from_id, to_id)))
            seen_undirected[undirected_pair].append(edge_id)
            if len(seen_undirected[undirected_pair]) > 1:
                findings.append(
                    make_issue(
                        "SUSPICIOUS_PARALLEL_EDGE",
                        "SUSPICIOUS_ISOLATION",
                        f"{undirected_pair[0]}<->{undirected_pair[1]}",
                        "P2",
                        "More than one same-mode edge joins the same node pair.",
                        mode=mode,
                        source_paths=[source],
                        evidence={"edge_ids": sorted(seen_undirected[undirected_pair])},
                        impacts=["Economy", "Military", "Spatial"],
                        suggestion="Confirm whether parallel capacity is intentional; if not, stage a canonical edge removal candidate.",
                        mechanical_fix=True,
                    )
                )
            graph.add_edge(
                GraphEdge(
                    edge_id=edge_id,
                    mode=mode,
                    from_id=from_id,
                    to_id=to_id,
                    source_path=source,
                    source_index=index,
                    directionality=directionality,
                )
            )
            first_coord = endpoint_coordinate(from_id, spec["endpoint_type"], cities, ports)
            last_coord = endpoint_coordinate(to_id, spec["endpoint_type"], cities, ports)
            if coordinate_distance(first_coord, last_coord) <= ZERO_LENGTH_EPSILON:
                findings.append(
                    make_issue(
                        "ZERO_LENGTH_EDGE",
                        "BROKEN_REFERENCE",
                        edge_id,
                        "P1",
                        "Transport edge endpoints have identical coordinates.",
                        mode=mode,
                        source_paths=[source],
                        evidence={"from_id": from_id, "to_id": to_id},
                        impacts=["Economy", "Military", "Spatial"],
                    )
                )
            if mode == "shipping":
                waypoints = [coordinate(item) for item in record.get("waypoints_lon_lat", [])]
                waypoints = [item for item in waypoints if item is not None]
                if len(waypoints) >= 2:
                    if all(coordinate_distance(waypoints[0], item) <= ZERO_LENGTH_EPSILON for item in waypoints[1:]):
                        findings.append(
                            make_issue(
                                "ZERO_LENGTH_EDGE",
                                "BROKEN_REFERENCE",
                                edge_id,
                                "P1",
                                "Shipping route waypoints collapse to one coordinate.",
                                mode=mode,
                                source_paths=[source],
                                evidence={"waypoint_count": len(waypoints)},
                                impacts=["Economy", "Military", "Spatial"],
                            )
                        )
                    if coordinate_distance(waypoints[0], first_coord) > GEOMETRY_ENDPOINT_TOLERANCE_DEGREES or coordinate_distance(waypoints[-1], last_coord) > GEOMETRY_ENDPOINT_TOLERANCE_DEGREES:
                        findings.append(
                            make_issue(
                                "ROUTE_ENDPOINT_GEOMETRY_MISMATCH",
                                "AMBIGUOUS",
                                edge_id,
                                "P2",
                                "Shipping route waypoint endpoints do not closely match port coordinates.",
                                mode=mode,
                                source_paths=[source],
                                evidence={"first_waypoint": waypoints[0], "from_coordinate": first_coord, "last_waypoint": waypoints[-1], "to_coordinate": last_coord},
                                impacts=["Economy", "Spatial"],
                                suggestion="Confirm the route endpoints before using the route for physical transfer semantics.",
                            )
                        )
        unspecified = directionality_by_mode[mode].get("UNSPECIFIED", 0)
        if unspecified:
            findings.append(
                make_issue(
                    "MISSING_DIRECTIONALITY_DECLARATION",
                    "AMBIGUOUS",
                    mode,
                    "P2",
                    "One or more routes omit an explicit directionality declaration; audit traversal treats them as undirected because the current renderer draws line segments without a direction contract.",
                    mode=mode,
                    source_paths=[spec["path"]],
                    evidence={"directionality_counts": dict(sorted(directionality_by_mode[mode].items()))},
                    impacts=["Economy", "Military"],
                    suggestion="Document or encode directed/bidirectional semantics before a gameplay system uses this graph for routing.",
                )
            )
    return raw_records


def add_transfer_edges(graph: TransportGraph, ports: dict[str, dict[str, Any]]) -> None:
    for port_id, port in sorted(ports.items()):
        city_id = as_string(port.get("city_id"))
        if city_id in graph.nodes and port_id in graph.nodes:
            graph.add_edge(
                GraphEdge(
                    edge_id=f"transfer:{port_id}:{city_id}",
                    mode="transfer",
                    from_id=port_id,
                    to_id=city_id,
                    source_path="data/world_map/ports.json",
                )
            )


def component_map(graph: TransportGraph, mode: str, node_type: str) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    for component in graph.components({mode}, {node_type}):
        key = component[0] if component else ""
        for node_id in component:
            result[node_id] = component
    return result


def mode_connected(graph: TransportGraph, node_id: str, mode: str, node_type: str) -> bool:
    return len(component_map(graph, mode, node_type).get(node_id, [node_id])) > 1


def sea_connected_for_city(
    graph: TransportGraph,
    city_id: str,
    ports: dict[str, dict[str, Any]],
) -> bool:
    return any(
        as_string(port.get("city_id")) == city_id
        and mode_connected(graph, port_id, "shipping", "port")
        for port_id, port in sorted(ports.items())
    )


def entity_node_ids(
    entity_type: str,
    entity_id: str,
    cities: dict[str, dict[str, Any]],
    ports: dict[str, dict[str, Any]],
    regions: list[dict[str, Any]],
    countries: list[dict[str, Any]],
) -> tuple[list[str], list[str]]:
    if entity_type == "city":
        return ([entity_id] if entity_id in cities else []), []
    if entity_type == "port":
        city_id = as_string(ports.get(entity_id, {}).get("city_id"))
        return ([city_id] if city_id in cities else []), ([entity_id] if entity_id in ports else [])
    source = regions if entity_type == "region" else countries
    record = next((item for item in source if as_string(item.get("id")) == entity_id), {})
    country_id = entity_id if entity_type == "country" else as_string(record.get("parent_country_id"))
    selected_cities = [
        city_id
        for city_id, city in sorted(cities.items())
        if as_string(city.get("parent_country_id")) == country_id
        and (entity_type == "country" or as_string(city.get("parent_region_id")) == entity_id)
    ]
    selected_ports = [
        port_id
        for port_id, port in sorted(ports.items())
        if as_string(port.get("parent_country_id")) == country_id
        and (entity_type == "country" or as_string(port.get("parent_region_id")) == entity_id)
    ]
    return selected_cities, selected_ports


def connectivity_row(
    graph: TransportGraph,
    entity_type: str,
    entity_id: str,
    cities: dict[str, dict[str, Any]],
    ports: dict[str, dict[str, Any]],
    regions: list[dict[str, Any]],
    countries: list[dict[str, Any]],
) -> dict[str, Any]:
    city_ids, port_ids = entity_node_ids(entity_type, entity_id, cities, ports, regions, countries)
    road_ids = [city_id for city_id in city_ids if mode_connected(graph, city_id, "road", "city")]
    rail_ids = [city_id for city_id in city_ids if mode_connected(graph, city_id, "rail", "city")]
    sea_ids = [
        port_id
        for port_id in port_ids
        if mode_connected(graph, port_id, "shipping", "port")
    ]
    sea_ids.extend(city_id for city_id in city_ids if sea_connected_for_city(graph, city_id, ports))
    road_reachable = bool(road_ids)
    rail_reachable = bool(rail_ids)
    sea_reachable = bool(sea_ids)
    multimodal_members: list[str] = []
    for city_id in city_ids:
        mode_count = int(mode_connected(graph, city_id, "road", "city")) + int(mode_connected(graph, city_id, "rail", "city")) + int(sea_connected_for_city(graph, city_id, ports))
        if mode_count >= 2:
            multimodal_members.append(city_id)
    for port_id in port_ids:
        city_id = as_string(ports.get(port_id, {}).get("city_id"))
        mode_count = int(mode_connected(graph, city_id, "road", "city")) + int(mode_connected(graph, city_id, "rail", "city")) + int(mode_connected(graph, port_id, "shipping", "port"))
        if mode_count >= 2:
            multimodal_members.append(port_id)
    multimodal_reachable = bool(multimodal_members)
    child_count = len(city_ids) + len(port_ids)
    if road_reachable or rail_reachable or sea_reachable or multimodal_reachable:
        isolation_class = "CONNECTED"
    elif child_count == 0:
        isolation_class = "EXPECTED_ISOLATION"
    elif entity_type == "port":
        isolation_class = "SUSPICIOUS_ISOLATION"
    elif entity_type == "city" and bool(cities.get(entity_id, {}).get("major", False)):
        isolation_class = "SUSPICIOUS_ISOLATION"
    elif entity_type == "region" and any(as_string(port.get("parent_region_id")) == entity_id for port in ports.values()):
        isolation_class = "SUSPICIOUS_ISOLATION"
    else:
        isolation_class = "AMBIGUOUS"
    return {
        "entity_type": entity_type,
        "entity_id": entity_id,
        "country_id": as_string((cities if entity_type == "city" else ports if entity_type == "port" else {}).get(entity_id, {}).get("parent_country_id")) if entity_type in {"city", "port"} else (entity_id if entity_type == "country" else as_string(next((item for item in regions if as_string(item.get("id")) == entity_id), {}).get("parent_country_id"))),
        "region_id": as_string(cities.get(entity_id, {}).get("parent_region_id")) if entity_type == "city" else as_string(ports.get(entity_id, {}).get("parent_region_id")) if entity_type == "port" else (entity_id if entity_type == "region" else ""),
        "road_reachable": road_reachable,
        "rail_reachable": rail_reachable,
        "sea_reachable": sea_reachable,
        "multimodal_reachable": multimodal_reachable,
        "road_component_members": road_ids,
        "rail_component_members": rail_ids,
        "sea_component_members": sorted_unique(sea_ids),
        "multimodal_members": sorted_unique(multimodal_members),
        "child_city_count": len(city_ids),
        "child_port_count": len(port_ids),
        "isolation_class": isolation_class,
    }


def build_connectivity_matrix(
    graph: TransportGraph,
    cities: dict[str, dict[str, Any]],
    ports: dict[str, dict[str, Any]],
    regions: list[dict[str, Any]],
    countries: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    entities: list[tuple[str, str]] = []
    entities.extend(("country", as_string(record.get("id"))) for record in countries if as_string(record.get("id")))
    entities.extend(("region", as_string(record.get("id"))) for record in regions if as_string(record.get("id")))
    entities.extend(("city", city_id) for city_id in sorted(cities))
    entities.extend(("port", port_id) for port_id in sorted(ports))
    entities.sort(key=lambda item: (ENTITY_ORDER.index(item[0]), item[1]))
    return [connectivity_row(graph, entity_type, entity_id, cities, ports, regions, countries) for entity_type, entity_id in entities]


def summarize_components(graph: TransportGraph) -> dict[str, Any]:
    summary: dict[str, Any] = {}
    for mode, node_type in (("road", "city"), ("rail", "city"), ("shipping", "port")):
        components = graph.components({mode}, {node_type})
        active = [component for component in components if len(component) > 1]
        summary[mode] = {
            "total_components_in_catalog": len(components),
            "nontrivial_components": len(active),
            "largest_component_size": max((len(component) for component in components), default=0),
            "components": components,
            "nontrivial_components_detail": active,
        }
    return summary


def add_component_findings(
    graph: TransportGraph,
    component_summary: dict[str, Any],
    findings: list[dict[str, Any]],
) -> None:
    for mode in MODE_ORDER:
        active = component_summary[mode]["nontrivial_components_detail"]
        if len(active) <= 1:
            continue
        node_type = "port" if mode == "shipping" else "city"
        findings.append(
            make_issue(
                f"{mode.upper()}_COMPONENT_FRAGMENTATION",
                "AMBIGUOUS",
                mode,
                "P2",
                f"{mode} has {len(active)} nontrivial connected components; no global all-places-connect assumption is applied.",
                mode=mode,
                source_paths=[MODE_SPECS[mode]["path"]],
                evidence={"components": active, "node_type": node_type},
                impacts=["Economy", "Military", "Spatial"],
                suggestion="Confirm whether the split represents intended regional coverage or a missing bridge.",
            )
        )
        findings.append(
            make_issue(
                "TOPOLOGY_COMPONENTS_UNEXPECTEDLY_SPLIT",
                "AMBIGUOUS",
                mode,
                "P2",
                f"The active {mode} topology is split into multiple components.",
                mode=mode,
                source_paths=[MODE_SPECS[mode]["path"]],
                evidence={"nontrivial_component_count": len(active)},
                impacts=["Economy", "Military", "Spatial"],
            )
        )


def add_connectivity_findings(
    matrix: list[dict[str, Any]],
    cities: dict[str, dict[str, Any]],
    ports: dict[str, dict[str, Any]],
    regions: list[dict[str, Any]],
    findings: list[dict[str, Any]],
) -> None:
    for row in matrix:
        entity_type = str(row["entity_type"])
        entity_id = str(row["entity_id"])
        any_mode = any(bool(row[key]) for key in ("road_reachable", "rail_reachable", "sea_reachable"))
        if entity_type == "city" and not any_mode:
            major = bool(cities.get(entity_id, {}).get("major", False))
            findings.append(
                make_issue(
                    "ISOLATED_CITY",
                    "SUSPICIOUS_ISOLATION" if major else "EXPECTED_ISOLATION",
                    entity_id,
                    "P1" if major else "P3",
                    "City has no reachable road, rail, or sea connection in the current topology.",
                    source_paths=["data/world_map/cities.json"],
                    evidence={"major": major, "isolation_class": row["isolation_class"]},
                    impacts=["Economy", "Military", "Spatial"],
                    suggestion="Confirm whether this sparse prototype catalog intentionally leaves the city outside transport coverage.",
                )
            )
            if major:
                findings.append(
                    make_issue(
                        "UNREACHABLE_MAJOR_NODE",
                        "SUSPICIOUS_ISOLATION",
                        entity_id,
                        "P1",
                        "Major city is absent from every connected transport mode.",
                        source_paths=["data/world_map/cities.json"],
                        evidence={"major": True},
                        impacts=["Economy", "Military", "Spatial"],
                        suggestion="Treat as a coverage review item; do not infer or synthesize a route without source data.",
                    )
                )
        if entity_type == "port" and not row["sea_reachable"]:
            findings.append(
                make_issue(
                    "PORT_WITHOUT_SHIPPING_CONNECTIVITY",
                    "SUSPICIOUS_ISOLATION",
                    entity_id,
                    "P1",
                    "Declared port has no connected shipping route.",
                    source_paths=["data/world_map/ports.json", "data/world_map/shipping_routes.json"],
                    evidence={"city_id": as_string(ports.get(entity_id, {}).get("city_id")), "isolation_class": row["isolation_class"]},
                    impacts=["Economy", "Military", "Spatial"],
                    suggestion="Confirm whether the port is display-only or needs a sourced shipping connection.",
                )
            )
        if entity_type == "region" and not any_mode:
            has_port = any(as_string(port.get("parent_region_id")) == entity_id for port in ports.values())
            status = "SUSPICIOUS_ISOLATION" if has_port else str(row["isolation_class"])
            findings.append(
                make_issue(
                    "ISOLATED_ADMINISTRATIVE_REGION",
                    status,
                    entity_id,
                    "P2" if status == "SUSPICIOUS_ISOLATION" else "P3",
                    "Region has no reachable transport mode in the current catalog.",
                    source_paths=["data/world_map/regions.json"],
                    evidence={"child_city_count": row["child_city_count"], "child_port_count": row["child_port_count"], "has_port": has_port},
                    impacts=["Economy", "Military", "Spatial"],
                    suggestion="Keep as expected isolation only if the region is intentionally outside the prototype transport coverage.",
                )
            )
    # A multi-city region whose connected cities do not share one component is
    # a useful review signal, but remains ambiguous because full connectivity
    # is explicitly not an invariant of this prototype.
    region_city_map: dict[str, list[str]] = defaultdict(list)
    for city_id, city in sorted(cities.items()):
        region_id = as_string(city.get("parent_region_id"))
        if region_id:
            region_city_map[region_id].append(city_id)
    for region_id, city_ids in sorted(region_city_map.items()):
        if len(city_ids) < 2:
            continue
        for mode in ("road", "rail"):
            components: dict[str, set[str]] = defaultdict(set)
            for city_id in city_ids:
                row = next((item for item in matrix if item["entity_type"] == "city" and item["entity_id"] == city_id), {})
                members = row.get(f"{mode}_component_members", [])
                key = members[0] if members else city_id
                components[key].add(city_id)
            if len(components) > 1 and any(len(members) > 1 for members in components.values()):
                findings.append(
                    make_issue(
                        "DISCONNECTED_REGION",
                        "AMBIGUOUS",
                        f"{region_id}:{mode}",
                        "P2",
                        f"Cities assigned to region {region_id} are split across {mode} components.",
                        mode=mode,
                        source_paths=["data/world_map/regions.json", MODE_SPECS[mode]["path"]],
                        evidence={"city_ids": city_ids, "component_groups": {key: sorted(value) for key, value in sorted(components.items())}},
                        impacts=["Economy", "Military", "Spatial"],
                        suggestion="Review whether the regional split is intentional before adding a bridge edge.",
                    )
                )


def validate_geometry_cache(
    root: Path,
    documents: dict[str, Any],
    raw_records: dict[str, list[dict[str, Any]]],
    cities: dict[str, dict[str, Any]],
    ports: dict[str, dict[str, Any]],
    findings: list[dict[str, Any]],
) -> dict[str, Any]:
    cache = documents.get("data/world_map/map_geometry_cache.json", {})
    transport_cache = cache.get("transport", {}) if isinstance(cache, dict) else {}
    anchors = cache.get("anchors", {}) if isinstance(cache, dict) else {}
    cache_summary: dict[str, Any] = {}
    for mode in MODE_ORDER:
        source = raw_records[mode]
        cached = transport_cache.get(mode, []) if isinstance(transport_cache, dict) else []
        if not isinstance(cached, list):
            cached = []
        source_ids = [as_string(record.get("id")) for record in source]
        cache_ids = [as_string(record.get("id")) for record in cached if isinstance(record, dict)]
        cache_summary[mode] = {"source_count": len(source), "cache_count": len(cached), "source_ids": source_ids, "cache_ids": cache_ids}
        if source_ids != cache_ids:
            findings.append(
                make_issue(
                    "CACHE_ALIGNMENT_MISMATCH",
                    "BROKEN_REFERENCE",
                    mode,
                    "P0",
                    "Renderer geometry-cache records are not index-aligned with source transport records.",
                    mode=mode,
                    source_paths=[MODE_SPECS[mode]["path"], "data/world_map/map_geometry_cache.json"],
                    evidence={"source_ids": source_ids, "cache_ids": cache_ids},
                    impacts=["Economy", "Military", "Spatial"],
                    suggestion="Regenerate the cache from authoritative transport records in a separate reviewed change.",
                )
            )
        endpoint_category = "ports" if mode == "shipping" else "cities"
        endpoint_ids: set[str] = set()
        spec = MODE_SPECS[mode]
        for record in source:
            endpoint_ids.add(as_string(record.get(spec["from_key"])))
            endpoint_ids.add(as_string(record.get(spec["to_key"])))
        anchor_map = anchors.get(endpoint_category, {}) if isinstance(anchors, dict) else {}
        if not isinstance(anchor_map, dict):
            anchor_map = {}
        for endpoint_id in sorted(endpoint_ids):
            if endpoint_id and endpoint_id not in anchor_map:
                findings.append(
                    make_issue(
                        "MISSING_TRANSPORT_GEOMETRY_ANCHOR",
                        "BROKEN_REFERENCE",
                        endpoint_id,
                        "P0",
                        f"{mode} endpoint is absent from the geometry-cache {endpoint_category} anchors used by the renderer.",
                        mode=mode,
                        source_paths=[MODE_SPECS[mode]["path"], "data/world_map/map_geometry_cache.json"],
                        evidence={"endpoint_category": endpoint_category},
                        impacts=["Spatial", "Economy", "Military"],
                    )
                )
        for index, cached_record in enumerate(cached):
            if not isinstance(cached_record, dict):
                continue
            if mode == "shipping":
                points = cached_record.get("points", [])
                if not isinstance(points, list) or len(points) < 2:
                    findings.append(
                        make_issue(
                            "INVALID_CACHED_GEOMETRY",
                            "BROKEN_REFERENCE",
                            f"{mode}[{index}]",
                            "P1",
                            "Cached shipping geometry has fewer than two points.",
                            mode=mode,
                            source_paths=["data/world_map/map_geometry_cache.json"],
                            evidence={"record_index": index},
                            impacts=["Spatial"],
                        )
                    )
            else:
                start = coordinate(cached_record.get("start"))
                end = coordinate(cached_record.get("end"))
                if start is not None and end is not None and coordinate_distance(start, end) <= ZERO_LENGTH_EPSILON:
                    findings.append(
                        make_issue(
                            "ZERO_LENGTH_CACHED_GEOMETRY",
                            "BROKEN_REFERENCE",
                            f"{mode}[{index}]",
                            "P1",
                            "Cached road/rail geometry collapses to one point.",
                            mode=mode,
                            source_paths=["data/world_map/map_geometry_cache.json"],
                            evidence={"record_index": index, "id": as_string(cached_record.get("id"))},
                            impacts=["Spatial"],
                        )
                    )
    missing_catalog_anchors: list[dict[str, Any]] = []
    for node_type, catalog, category in (("city", cities, "cities"), ("port", ports, "ports")):
        anchor_map = anchors.get(category, {}) if isinstance(anchors, dict) else {}
        anchor_map = anchor_map if isinstance(anchor_map, dict) else {}
        for node_id, record in sorted(catalog.items()):
            if node_id in anchor_map:
                continue
            missing_catalog_anchors.append({"node_type": node_type, "node_id": node_id, "major": bool(record.get("major", False))})
            findings.append(
                make_issue(
                    "MISSING_MAP_ANCHOR",
                    "SUSPICIOUS_ISOLATION" if bool(record.get("major", False)) else "AMBIGUOUS",
                    node_id,
                    "P2" if bool(record.get("major", False)) else "P3",
                    f"Declared {node_type} is absent from the map geometry anchor cache; current loader fallback is Vector2.ZERO.",
                    source_paths=[f"data/world_map/{'cities' if node_type == 'city' else 'ports'}.json", "data/world_map/map_geometry_cache.json", "scripts/world_map/internal/world_map_canvas_impl.gd"],
                    evidence={"node_type": node_type, "major": bool(record.get("major", False))},
                    impacts=["Spatial"],
                    suggestion="Regenerate or explicitly review the geometry cache; do not hand-edit authoritative transport records to compensate.",
                )
            )
    cache_summary["missing_catalog_anchors"] = missing_catalog_anchors
    return cache_summary


def candidate_fixes(findings: list[dict[str, Any]]) -> list[dict[str, Any]]:
    candidates: list[dict[str, Any]] = []
    for finding in findings:
        if not finding.get("mechanical_fix"):
            continue
        candidates.append(
            {
                "candidate_id": f"CAND-{len(candidates) + 1:04d}",
                "finding_id": finding["id"],
                "status": "STAGING_ONLY",
                "operation": "review_parallel_edge",
                "target": {"mode": finding.get("mode", ""), "subject": finding.get("subject", "")},
                "reason": finding.get("suggestion", ""),
                "authoritative_data_write": False,
            }
        )
    return candidates


def source_manifest(root: Path) -> list[dict[str, Any]]:
    manifest: list[dict[str, Any]] = []
    for path_string in (*SOURCE_PATHS, *LOADER_PATHS):
        path = root / Path(path_string)
        entry: dict[str, Any] = {"path": path_string}
        if path.is_file():
            data = path.read_bytes()
            entry.update({"exists": True, "size_bytes": len(data), "sha256": sha256_bytes(data)})
        else:
            entry["exists"] = False
        manifest.append(entry)
    return manifest


def git_sha(root: Path) -> str:
    try:
        completed = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=root,
            check=True,
            capture_output=True,
            text=True,
            timeout=10,
        )
        return completed.stdout.strip() or DEFAULT_STARTING_MASTER
    except (OSError, subprocess.SubprocessError):
        return DEFAULT_STARTING_MASTER


def build_audit(root: Path, starting_master: str = DEFAULT_STARTING_MASTER) -> dict[str, Any]:
    root = root.resolve()
    documents, source_errors = load_source_documents(root)
    inventory, world_map_parse_errors = inventory_world_map(root)
    findings: list[dict[str, Any]] = []
    graph = TransportGraph()
    cities = add_catalog_nodes(graph, as_records(documents.get("data/world_map/cities.json", {}), "cities"), "city", findings)
    ports = add_catalog_nodes(graph, as_records(documents.get("data/world_map/ports.json", {}), "ports"), "port", findings)
    regions = as_records(documents.get("data/world_map/regions.json", {}), "regions")
    countries = as_records(documents.get("data/world_map/countries.json", {}), "countries")
    validate_place_references(cities, ports, regions, countries, findings)
    raw_records = validate_transport_records(graph, documents, cities, ports, findings)
    add_transfer_edges(graph, ports)
    component_summary = summarize_components(graph)
    add_component_findings(graph, component_summary, findings)
    matrix = build_connectivity_matrix(graph, cities, ports, regions, countries)
    add_connectivity_findings(matrix, cities, ports, regions, findings)
    cache_summary = validate_geometry_cache(root, documents, raw_records, cities, ports, findings)
    finalized_findings = finalize_findings(findings)
    candidates = candidate_fixes(finalized_findings)
    status_counts = Counter(str(finding["status"]) for finding in finalized_findings)
    suspicious_subjects = sorted({
        f"{finding['check']}:{finding['subject']}"
        for finding in finalized_findings
        if finding["status"] == "SUSPICIOUS_ISOLATION"
        and finding["check"] in {"ISOLATED_CITY", "PORT_WITHOUT_SHIPPING_CONNECTIVITY", "ISOLATED_ADMINISTRATIVE_REGION", "UNREACHABLE_MAJOR_NODE"}
    })
    major_unreachable = sorted({
        finding["subject"]
        for finding in finalized_findings
        if finding["check"] == "UNREACHABLE_MAJOR_NODE"
    })
    loader = loader_contract(root)
    fatal_source_errors = source_errors + world_map_parse_errors
    summary = {
        "transport_node_count": len(cities) + len(ports),
        "city_node_count": len(cities),
        "port_node_count": len(ports),
        "road_edge_count": len(raw_records.get("road", [])),
        "rail_edge_count": len(raw_records.get("rail", [])),
        "shipping_edge_count": len(raw_records.get("shipping", [])),
        "broken_reference_count": sum(1 for finding in finalized_findings if finding["status"] == "BROKEN_REFERENCE"),
        "suspicious_isolated_node_count": len({subject.split(":", 1)[1] for subject in suspicious_subjects}),
        "unreachable_major_entity_count": len(major_unreachable),
        "candidate_fix_count": len(candidates),
        "finding_count": len(finalized_findings),
        "finding_status_counts": {key: status_counts.get(key, 0) for key in STATUS_ORDER},
        "world_map_file_count": len(inventory),
        "world_map_json_parse_error_count": len(world_map_parse_errors),
        "source_error_count": len(source_errors),
        "loader_contract": loader["status"],
        "production_world_data_modified": False,
    }
    top_problems = [
        finding
        for finding in finalized_findings
        if finding["status"] != "EXPECTED_ISOLATION"
    ][:30]
    return {
        "schema_version": SCHEMA_VERSION,
        "starting_master": starting_master,
        "scope": {
            "world_map_root": WORLD_MAP_ROOT.as_posix(),
            "source_paths": list(SOURCE_PATHS),
            "loader_paths": list(LOADER_PATHS),
            "production_world_data_modified": False,
            "graph_role": "analysis_only",
            "directionality_assumption": "undirected_for_current_renderer_and_topology_QA; explicit directionality remains an ambiguity finding",
            "connectivity_policy": "No global all-places-connect invariant; isolation is classified from declared catalog relationships and current connectivity only.",
            "priority_policy": "P0-P3 are audit triage labels only, not code-review severity or proof of authoritative data error.",
            "repair_policy": "No finding authorizes automatic route creation or authoritative data repair; suspicious and ambiguous findings require independent source review.",
            "major_entity_basis": "Explicit cities.json major boolean metadata; no real-world fame inference is used.",
            "port_connectivity_policy": "A declared port without a current shipping route is a review-only coverage signal, not a validity invariant.",
            "node_identity_policy": "City and port IDs are checked for namespace collision; current catalogs use disjoint IDs."
        },
        "source_manifest": source_manifest(root),
        "world_map_inventory": inventory,
        "source_errors": fatal_source_errors,
        "loader_contract": loader,
        "summary": summary,
        "components": component_summary,
        "geometry_cache": cache_summary,
        "connectivity_matrix": matrix,
        "findings": finalized_findings,
        "top_problems": top_problems,
        "candidate_fixes": candidates,
    }


def render_markdown(audit: dict[str, Any]) -> str:
    summary = audit["summary"]
    lines: list[str] = [
        "# WWO WORLD TRANSPORT TOPOLOGY AUDIT — BATCH 1 REPORT",
        "",
        f"Starting master: `{audit['starting_master']}`",
        "",
        "## Scope and safety boundary",
        "",
        "This is a deterministic, read-only audit of the existing world-map transport source data and the current map loader contract. The graph is analysis-only; it is not a gameplay authority and does not integrate Economy, Military, or Spatial systems. No file under `data/world_map/` is rewritten by the tool.",
        "The current loader registers source collections and draws transport geometry from index-aligned cached records; the audit records endpoint field semantics for QA but does not claim the renderer performs endpoint routing.",
        "",
        "Classification policy: `EXPECTED_ISOLATION` means the catalog gives no evidence that a connection is required; `SUSPICIOUS_ISOLATION` is a review-only signal based on explicit metadata or a documented coverage heuristic and does not prove authoritative data is wrong; `BROKEN_REFERENCE` is a concrete schema/reference/cache failure; `AMBIGUOUS` requires domain confirmation because the current data does not declare intent or directionality.",
        "Priority policy: P0-P3 are audit triage labels, not code-review severity. Sparse current coverage may explain isolated cities, ports, and split components; no finding authorizes automatic route creation or authoritative data repair.",
        "Major entities use the explicit `major` boolean in `cities.json`; no real-world fame inference is used. A declared port without a current shipping route is a review-only coverage signal, not a validity invariant.",
        "Candidate staging is NON_AUTHORITATIVE, is not consumed by runtime, is never automatically applied, and requires independent source review before any separate authoritative change.",
        "",
        "## Summary",
        "",
        "| Metric | Result |",
        "| --- | ---: |",
        f"| Transport nodes | {summary['transport_node_count']} ({summary['city_node_count']} city + {summary['port_node_count']} port) |",
        f"| Road edges | {summary['road_edge_count']} |",
        f"| Rail edges | {summary['rail_edge_count']} |",
        f"| Shipping edges | {summary['shipping_edge_count']} |",
        f"| Broken references | {summary['broken_reference_count']} |",
        f"| Suspicious isolated nodes | {summary['suspicious_isolated_node_count']} |",
        f"| Unreachable major entities | {summary['unreachable_major_entity_count']} |",
        f"| Candidate fixes | {summary['candidate_fix_count']} |",
        f"| World-map files scanned | {summary['world_map_file_count']} |",
        f"| World-map JSON parse errors | {summary['world_map_json_parse_error_count']} |",
        f"| Production world data modified | **NO** |",
        "",
        "## Loader contract",
        "",
        f"Static loader contract: **{audit['loader_contract']['status']}**. The current data loader registers ports, road segments, rail segments, and shipping routes; the map canvas reads the same collections and consumes index-aligned transport geometry from `map_geometry_cache.json`.",
        "",
        "| Loader file | Status |",
        "| --- | --- |",
    ]
    for file_record in audit["loader_contract"]["files"]:
        lines.append(f"| `{file_record['path']}` | {file_record['status']} |")
    lines.extend(["", "## Connected components", ""])
    lines.extend([
        "| Mode | Catalog components | Nontrivial components | Largest |",
        "| --- | ---: | ---: | ---: |",
    ])
    for mode in MODE_ORDER:
        component = audit["components"][mode]
        lines.append(f"| {mode} | {component['total_components_in_catalog']} | {component['nontrivial_components']} | {component['largest_component_size']} |")
    lines.extend(["", "Nontrivial component membership:", ""])
    for mode in MODE_ORDER:
        lines.append(f"- `{mode}`: " + "; ".join(", ".join(component) for component in audit["components"][mode]["nontrivial_components_detail"]) if audit["components"][mode]["nontrivial_components_detail"] else f"- `{mode}`: none")
    lines.extend(["", "## Findings by status", ""])
    counts = Counter(str(finding["status"]) for finding in audit["findings"])
    for status in STATUS_ORDER:
        lines.append(f"- `{status}`: {counts.get(status, 0)}")
    lines.extend(["", "## TOP 30 TRANSPORT TOPOLOGY PROBLEMS", "", "Ordered by gameplay impact (Economy, Military, Spatial), then priority, status, check, and stable subject. Expected isolation is retained in the machine-readable matrix but omitted from this ranked problem list.", ""])
    lines.extend([
        "| Rank | Priority | Status | Check | Mode | Subject | Impact | Message |",
        "| ---: | --- | --- | --- | --- | --- | --- | --- |",
    ])
    for rank, finding in enumerate(audit["top_problems"], start=1):
        message = str(finding["message"]).replace("|", "\\|")
        impacts = ", ".join(finding.get("impacts", [])) or "—"
        lines.append(f"| {rank} | {finding['priority']} | {finding['status']} | `{finding['check']}` | {finding.get('mode') or '—'} | `{finding['subject']}` | {impacts} | {message} |")
    lines.extend(["", "## Connectivity matrix", "", "Semantics: road/rail/sea columns mean the entity has a non-self reachable path in that mode. For cities and ports, sea uses an associated port; for countries and regions, a column is true when any declared child city/port has that reachability. Multimodal means one representative child can use at least two of road, rail, and sea through the explicit city-port transfer relationship.", ""])
    lines.extend([
        "| Type | Entity | Road | Rail | Sea | Multimodal | Isolation class | Child cities | Child ports |",
        "| --- | --- | ---: | ---: | ---: | ---: | --- | ---: | ---: |",
    ])
    for row in audit["connectivity_matrix"]:
        lines.append(f"| {row['entity_type']} | `{row['entity_id']}` | {'YES' if row['road_reachable'] else 'NO'} | {'YES' if row['rail_reachable'] else 'NO'} | {'YES' if row['sea_reachable'] else 'NO'} | {'YES' if row['multimodal_reachable'] else 'NO'} | {row['isolation_class']} | {row['child_city_count']} | {row['child_port_count']} |")
    lines.extend(["", "## Candidate fixes", "", "Candidate output is staging-only. No authoritative transport record is modified by this audit.", ""])
    if audit["candidate_fixes"]:
        lines.extend(["| Candidate | Finding | Operation | Target |", "| --- | --- | --- | --- |"])
        for candidate in audit["candidate_fixes"]:
            lines.append(f"| `{candidate['candidate_id']}` | `{candidate['finding_id']}` | {candidate['operation']} | `{candidate['target']['mode']}:{candidate['target']['subject']}` |")
    else:
        lines.append("No mechanically safe candidate fixes were generated from the current data.")
    lines.extend(["", "## Tooling and tests", "", "- Tool: `tools/world_map/world_transport_topology_audit.py`", "- Focused tests: `tests/tools/test_world_transport_topology_audit.py`", "- Machine-readable audit: `docs/audits/world_transport_topology_audit_batch1.json`", "- Candidate staging suggestion: `data/staging/world_transport_topology_audit_batch1_candidate_fixes.json`", "- This report is generated from the machine-readable artifact; rerunning with the same starting master and source tree must produce byte-identical output.", ""])
    return "\n".join(lines).rstrip("\n") + "\n"


def write_output(path_string: str, data: bytes) -> None:
    path = Path(path_string)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def parse_args(argv: Optional[list[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("."), help="repository root")
    parser.add_argument("--starting-master", default="", help="recorded live-master SHA")
    parser.add_argument("--json-output", default="", help="explicit machine-readable output path")
    parser.add_argument("--markdown-output", default="", help="explicit human-readable report path")
    parser.add_argument("--candidate-output", default="", help="explicit staging-only candidate output path")
    parser.add_argument("--stdout-json", action="store_true", help="also print the machine-readable result")
    return parser.parse_args(argv)


def main(argv: Optional[list[str]] = None) -> int:
    args = parse_args(argv)
    root = args.root.resolve()
    starting_master = args.starting_master or git_sha(root)
    audit = build_audit(root, starting_master)
    if args.json_output:
        write_output(args.json_output, canonical_bytes(audit))
    if args.markdown_output:
        write_output(args.markdown_output, render_markdown(audit).encode("utf-8"))
    if args.candidate_output:
        candidate_payload = {
            "schema_version": "world-transport-topology-audit-candidates/v2",
            "starting_master": starting_master,
            "source_audit": "world_transport_topology_audit_batch1",
            "authority": "NON_AUTHORITATIVE_STAGING_ONLY",
            "authoritative_data_write": False,
            "runtime_consumed": False,
            "automatic_apply": False,
            "requires_independent_source_review": True,
            "candidate_fixes": audit["candidate_fixes"],
        }
        write_output(args.candidate_output, canonical_bytes(candidate_payload))
    if args.stdout_json or not (args.json_output or args.markdown_output or args.candidate_output):
        sys.stdout.buffer.write(canonical_bytes(audit))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
