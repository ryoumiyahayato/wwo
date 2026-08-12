#!/usr/bin/env python3
"""Focused regression tests for the standalone transport topology audit."""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TOOL_PATH = ROOT / "tools" / "world_map" / "world_transport_topology_audit.py"
SPEC = importlib.util.spec_from_file_location("world_transport_topology_audit", TOOL_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot import audit tool: {TOOL_PATH}")
AUDIT = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = AUDIT
SPEC.loader.exec_module(AUDIT)


def node(node_id: str, node_type: str) -> AUDIT.GraphNode:
    return AUDIT.GraphNode(node_id=node_id, node_type=node_type)


def edge(edge_id: str, mode: str, from_id: str, to_id: str) -> AUDIT.GraphEdge:
    return AUDIT.GraphEdge(edge_id=edge_id, mode=mode, from_id=from_id, to_id=to_id)


class TransportTopologyGraphTests(unittest.TestCase):
    def test_valid_connected_graph(self) -> None:
        graph = AUDIT.TransportGraph()
        for node_id in ("city:a", "city:b", "city:c"):
            graph.add_node(node(node_id, "city"))
        graph.add_edge(edge("road:a-b", "road", "city:a", "city:b"))
        graph.add_edge(edge("road:b-c", "road", "city:b", "city:c"))

        self.assertEqual(
            graph.components({"road"}, {"city"}),
            [["city:a", "city:b", "city:c"]],
        )
        self.assertEqual(
            graph.reachable("city:a", {"road"}),
            ["city:a", "city:b", "city:c"],
        )

    def test_disconnected_component_is_preserved(self) -> None:
        graph = AUDIT.TransportGraph()
        for node_id in ("city:a", "city:b", "city:c", "city:d"):
            graph.add_node(node(node_id, "city"))
        graph.add_edge(edge("road:a-b", "road", "city:a", "city:b"))
        graph.add_edge(edge("road:c-d", "road", "city:c", "city:d"))

        self.assertEqual(
            graph.components({"road"}, {"city"}),
            [["city:a", "city:b"], ["city:c", "city:d"]],
        )

    def test_dangling_endpoint_is_reported(self) -> None:
        graph = AUDIT.TransportGraph()
        graph.add_node(node("city:a", "city"))
        findings: list[dict[str, object]] = []
        AUDIT.validate_transport_records(
            graph,
            {
                "data/world_map/road_segments.json": {
                    "segments": [
                        {
                            "id": "road:a-missing",
                            "type": "road",
                            "from_city_id": "a",
                            "to_city_id": "missing",
                        }
                    ]
                },
                "data/world_map/rail_segments.json": {"segments": []},
                "data/world_map/shipping_routes.json": {"routes": []},
            },
            {"a": {"id": "a", "lon_lat": [0.0, 0.0]}},
            {},
            findings,
        )

        self.assertTrue(
            any(
                finding["check"] == "TRANSPORT_EDGE_REFERENCING_MISSING_PLACE"
                and finding["status"] == "BROKEN_REFERENCE"
                for finding in findings
            )
        )

    def test_duplicate_edge_and_reverse_duplicate_are_distinguished(self) -> None:
        graph = AUDIT.TransportGraph()
        graph.add_node(node("a", "city"))
        graph.add_node(node("b", "city"))
        findings: list[dict[str, object]] = []
        AUDIT.validate_transport_records(
            graph,
            {
                "data/world_map/road_segments.json": {
                    "segments": [
                        {"id": "road:one", "type": "road", "from_city_id": "a", "to_city_id": "b"},
                        {"id": "road:two", "type": "road", "from_city_id": "a", "to_city_id": "b"},
                        {"id": "road:three", "type": "road", "from_city_id": "b", "to_city_id": "a"},
                    ]
                },
                "data/world_map/rail_segments.json": {"segments": []},
                "data/world_map/shipping_routes.json": {"routes": []},
            },
            {
                "a": {"id": "a", "lon_lat": [0.0, 0.0]},
                "b": {"id": "b", "lon_lat": [1.0, 0.0]},
            },
            {},
            findings,
        )

        checks = [finding["check"] for finding in findings]
        self.assertIn("DUPLICATE_EDGE", checks)
        self.assertIn("REVERSE_DUPLICATE", checks)
        self.assertIn("SUSPICIOUS_PARALLEL_EDGE", checks)

    def test_isolated_port_and_multimodal_transfer(self) -> None:
        graph = AUDIT.TransportGraph()
        for node_id, node_type in (("city:a", "city"), ("city:b", "city"), ("port:a", "port"), ("port:isolated", "port")):
            graph.add_node(node(node_id, node_type))
        graph.add_edge(edge("road:a-b", "road", "city:a", "city:b"))
        graph.add_edge(edge("shipping:a", "shipping", "port:a", "port:a"))
        graph.add_edge(edge("transfer:a", "transfer", "port:a", "city:a"))

        self.assertTrue(AUDIT.mode_connected(graph, "city:a", "road", "city"))
        self.assertFalse(AUDIT.mode_connected(graph, "port:isolated", "shipping", "port"))
        self.assertEqual(graph.reachable("city:a", {"road"}), ["city:a", "city:b"])

    def test_deterministic_traversal_and_finding_order(self) -> None:
        graph = AUDIT.TransportGraph()
        for node_id in ("c", "a", "b"):
            graph.add_node(node(node_id, "city"))
        graph.add_edge(edge("e2", "road", "b", "c"))
        graph.add_edge(edge("e1", "road", "a", "b"))
        first = graph.reachable("a", {"road"})
        second = graph.reachable("a", {"road"})
        self.assertEqual(first, ["a", "b", "c"])
        self.assertEqual(first, second)

        findings = [
            AUDIT.make_issue("Z", "AMBIGUOUS", "z", "P2", "z", impacts=["Spatial"]),
            AUDIT.make_issue("A", "SUSPICIOUS_ISOLATION", "a", "P1", "a", impacts=["Economy"]),
        ]
        first_order = [row["id"] for row in AUDIT.finalize_findings(findings)]
        second_order = [row["id"] for row in AUDIT.finalize_findings(findings)]
        self.assertEqual(first_order, second_order)


class TransportTopologyAuditArtifactTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.audit = AUDIT.build_audit(ROOT, "4b738ab8b0a21e8685aae95381717e9efd2327a8")

    def test_current_source_counts_and_loader_contract(self) -> None:
        summary = self.audit["summary"]
        self.assertEqual(summary["transport_node_count"], 40)
        self.assertEqual(summary["road_edge_count"], 3)
        self.assertEqual(summary["rail_edge_count"], 9)
        self.assertEqual(summary["shipping_edge_count"], 3)
        self.assertEqual(summary["broken_reference_count"], 0)
        self.assertEqual(self.audit["loader_contract"]["status"], "PASS")

    def test_current_findings_include_required_review_classes(self) -> None:
        checks = {finding["check"] for finding in self.audit["findings"]}
        self.assertIn("ISOLATED_CITY", checks)
        self.assertIn("PORT_WITHOUT_SHIPPING_CONNECTIVITY", checks)
        self.assertIn("ROAD_COMPONENT_FRAGMENTATION", checks)
        self.assertIn("SHIPPING_COMPONENT_FRAGMENTATION", checks)
        self.assertIn("MISSING_DIRECTIONALITY_DECLARATION", checks)
        self.assertIn("MISSING_MAP_ANCHOR", checks)

    def test_current_audit_has_no_authoritative_write(self) -> None:
        self.assertFalse(self.audit["scope"]["production_world_data_modified"])
        self.assertFalse(self.audit["summary"]["production_world_data_modified"])
        self.assertEqual(self.audit["candidate_fixes"], [])

    def test_machine_output_is_byte_deterministic(self) -> None:
        first = AUDIT.canonical_bytes(
            AUDIT.build_audit(ROOT, "4b738ab8b0a21e8685aae95381717e9efd2327a8")
        )
        second = AUDIT.canonical_bytes(
            AUDIT.build_audit(ROOT, "4b738ab8b0a21e8685aae95381717e9efd2327a8")
        )
        self.assertEqual(first, second)


if __name__ == "__main__":
    unittest.main()
