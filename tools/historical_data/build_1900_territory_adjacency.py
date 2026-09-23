#!/usr/bin/env python3
"""Build deterministic land adjacency for the production 1900 TerritoryUnit catalog.

Adjacency is derived mechanically from the committed CShapes geometry snapshot.
No political ownership, population, weights, density estimates, or synthetic
geometry participate in this artifact.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from shapely.geometry import shape

SNAPSHOT_PATH = Path("data/world_map/historical/cshapes_1900_snapshot.json")
OUTPUT_PATH = Path("data/vnext/territory/cshapes_1900_land_adjacency.json")
SCHEMA_ID = "cshapes_1900_land_adjacency_v1"
EXPECTED_SNAPSHOT_DATE = "1900-03-12"
EXPECTED_PROVIDER = "cshapes_2_0"
MIN_SHARED_BOUNDARY_DEGREES = 1e-9


def _read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _feature_sort_key(feature_id: str) -> tuple[int, str]:
    if feature_id.startswith("gw_") and feature_id[3:].isdigit():
        return (int(feature_id[3:]), feature_id)
    return (2**31 - 1, feature_id)


def _bounds_overlap(
    left: tuple[float, float, float, float],
    right: tuple[float, float, float, float],
) -> bool:
    return not (
        left[2] < right[0]
        or right[2] < left[0]
        or left[3] < right[1]
        or right[3] < left[1]
    )


def build_adjacency(snapshot: dict[str, Any]) -> dict[str, Any]:
    if snapshot.get("snapshot_date") != EXPECTED_SNAPSHOT_DATE:
        raise ValueError("unexpected CShapes snapshot date")
    if snapshot.get("provider") != EXPECTED_PROVIDER:
        raise ValueError("unexpected CShapes provider")
    source = snapshot.get("source")
    if not isinstance(source, dict) or not isinstance(source.get("source_sha256"), str):
        raise ValueError("CShapes source provenance is missing")

    raw_features = snapshot.get("features")
    if not isinstance(raw_features, list) or not raw_features:
        raise ValueError("CShapes snapshot has no features")
    expected_count = snapshot.get("feature_count")
    if not isinstance(expected_count, int) or expected_count != len(raw_features):
        raise ValueError("CShapes feature count is inconsistent")

    geometries: dict[str, Any] = {}
    bounds: dict[str, tuple[float, float, float, float]] = {}
    for raw_feature in raw_features:
        if not isinstance(raw_feature, dict):
            raise ValueError("CShapes feature is not an object")
        feature_id = raw_feature.get("id")
        geometry_value = raw_feature.get("geometry")
        if not isinstance(feature_id, str) or not feature_id:
            raise ValueError("CShapes feature ID is invalid")
        if feature_id in geometries:
            raise ValueError(f"duplicate CShapes feature ID: {feature_id}")
        if not isinstance(geometry_value, dict):
            raise ValueError(f"missing geometry for {feature_id}")
        geometry = shape(geometry_value)
        if geometry.is_empty or not geometry.is_valid:
            raise ValueError(f"invalid geometry for {feature_id}")
        geometries[feature_id] = geometry
        bounds[feature_id] = geometry.bounds

    feature_ids = sorted(geometries, key=_feature_sort_key)
    neighbors: dict[str, set[str]] = {feature_id: set() for feature_id in feature_ids}
    for left_index, left_id in enumerate(feature_ids):
        left = geometries[left_id]
        left_bounds = bounds[left_id]
        for right_id in feature_ids[left_index + 1 :]:
            if not _bounds_overlap(left_bounds, bounds[right_id]):
                continue
            right = geometries[right_id]
            shared_boundary = left.boundary.intersection(right.boundary)
            if (
                shared_boundary.is_empty
                or shared_boundary.length <= MIN_SHARED_BOUNDARY_DEGREES
            ):
                continue
            neighbors[left_id].add(right_id)
            neighbors[right_id].add(left_id)

    edge_count = sum(len(values) for values in neighbors.values()) // 2
    if edge_count <= 0:
        raise ValueError("derived adjacency contains no land-border edges")

    records = [
        {
            "geometry_feature_id": feature_id,
            "neighbor_geometry_feature_ids": sorted(
                neighbors[feature_id], key=_feature_sort_key
            ),
        }
        for feature_id in feature_ids
    ]
    return {
        "schema_id": SCHEMA_ID,
        "snapshot_date": EXPECTED_SNAPSHOT_DATE,
        "geometry_provider": EXPECTED_PROVIDER,
        "source_dataset_sha256": source["source_sha256"],
        "derivation": {
            "kind": "shared_boundary_on_committed_geometry",
            "minimum_shared_boundary_degrees_exclusive": MIN_SHARED_BOUNDARY_DEGREES,
            "political_identity_used": False,
            "population_used": False,
            "synthetic_geometry_used": False,
        },
        "feature_count": len(feature_ids),
        "undirected_edge_count": edge_count,
        "records": records,
    }


def _write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()
    snapshot_path = root / SNAPSHOT_PATH
    output_path = root / OUTPUT_PATH
    generated = build_adjacency(_read_json(snapshot_path))

    if args.check:
        if not output_path.is_file():
            print(f"missing generated adjacency: {output_path}")
            return 1
        tracked = _read_json(output_path)
        if tracked != generated:
            print("tracked TerritoryUnit adjacency is stale")
            return 1
        print(
            json.dumps(
                {
                    "status": "PASS",
                    "feature_count": generated["feature_count"],
                    "undirected_edge_count": generated["undirected_edge_count"],
                },
                sort_keys=True,
            )
        )
        return 0

    _write_json(output_path, generated)
    print(
        json.dumps(
            {
                "output": OUTPUT_PATH.as_posix(),
                "feature_count": generated["feature_count"],
                "undirected_edge_count": generated["undirected_edge_count"],
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
