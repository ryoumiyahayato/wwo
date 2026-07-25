#!/usr/bin/env python3
"""Build a compact Natural Earth admin-1 runtime file for the isolated UI spike."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any, Iterable


def distance_to_segment(point: list[float], start: list[float], end: list[float]) -> float:
    dx = end[0] - start[0]
    dy = end[1] - start[1]
    length_sq = dx * dx + dy * dy
    if length_sq <= 1e-16:
        return math.hypot(point[0] - start[0], point[1] - start[1])
    ratio = max(0.0, min(1.0, ((point[0] - start[0]) * dx + (point[1] - start[1]) * dy) / length_sq))
    return math.hypot(point[0] - (start[0] + dx * ratio), point[1] - (start[1] + dy * ratio))


def rdp(points: list[list[float]], epsilon: float) -> list[list[float]]:
    if len(points) < 3:
        return points
    maximum_distance = -1.0
    maximum_index = -1
    for index in range(1, len(points) - 1):
        distance = distance_to_segment(points[index], points[0], points[-1])
        if distance > maximum_distance:
            maximum_distance = distance
            maximum_index = index
    if maximum_distance <= epsilon or maximum_index <= 0:
        return [points[0], points[-1]]
    left = rdp(points[: maximum_index + 1], epsilon)
    right = rdp(points[maximum_index:], epsilon)
    return left[:-1] + right


def simplify_ring(raw_ring: Iterable[Iterable[float]], max_points: int = 72) -> list[list[float]]:
    points = [[round(float(point[0]), 4), round(float(point[1]), 4)] for point in raw_ring]
    if len(points) < 4:
        return []
    if points[0] == points[-1]:
        points = points[:-1]
    epsilon = 0.006
    simplified = points
    while len(simplified) > max_points and epsilon < 1.5:
        simplified = rdp(points, epsilon)
        epsilon *= 1.48
    if len(simplified) < 3:
        return []
    if simplified[0] != simplified[-1]:
        simplified.append(simplified[0])
    return simplified


def polygon_area(ring: list[list[float]]) -> float:
    if len(ring) < 4:
        return 0.0
    area = 0.0
    for index in range(len(ring) - 1):
        x1, y1 = ring[index]
        x2, y2 = ring[index + 1]
        area += x1 * y2 - x2 * y1
    return abs(area) * 0.5


def outer_rings(geometry: dict[str, Any]) -> list[list[list[float]]]:
    geometry_type = geometry.get("type")
    coordinates = geometry.get("coordinates", [])
    if geometry_type == "Polygon":
        return [coordinates[0]] if coordinates else []
    if geometry_type == "MultiPolygon":
        return [polygon[0] for polygon in coordinates if polygon]
    return []


def build(source: Path, output: Path) -> None:
    document = json.loads(source.read_text(encoding="utf-8"))
    records: list[dict[str, Any]] = []
    country_counts: dict[str, int] = {}
    polygon_count = 0

    for feature in document.get("features", []):
        properties = feature.get("properties", {})
        admin0 = str(properties.get("adm0_a3") or properties.get("sov_a3") or "").upper()
        name = str(properties.get("name") or properties.get("name_en") or "").strip()
        if not admin0 or not name:
            continue
        simplified_rings: list[list[list[float]]] = []
        ranked: list[tuple[float, list[list[float]]]] = []
        for raw_ring in outer_rings(feature.get("geometry", {})):
            ring = simplify_ring(raw_ring)
            if len(ring) >= 4:
                ranked.append((polygon_area(ring), ring))
        ranked.sort(key=lambda item: item[0], reverse=True)
        for _area, ring in ranked[:6]:
            simplified_rings.append(ring)
        if not simplified_rings:
            continue
        polygon_count += len(simplified_rings)
        country_counts[admin0] = country_counts.get(admin0, 0) + 1
        records.append(
            {
                "id": str(properties.get("adm1_code") or properties.get("iso_3166_2") or f"{admin0}-{len(records)}"),
                "country_iso_a3": admin0,
                "name": name,
                "name_zh": str(properties.get("name_zh") or ""),
                "type": str(properties.get("type_en") or properties.get("type") or "Region"),
                "code": str(properties.get("iso_3166_2") or properties.get("code_hasc") or ""),
                "label_rank": int(properties.get("labelrank") or 6),
                "min_zoom": float(properties.get("min_zoom") or 4.0),
                "label_lon_lat": [
                    round(float(properties.get("longitude") or 0.0), 4),
                    round(float(properties.get("latitude") or 0.0), 4),
                ],
                "polygons": simplified_rings,
            }
        )

    output.parent.mkdir(parents=True, exist_ok=True)
    compact = {
        "schema_version": 1,
        "source": {
            "dataset": "Natural Earth 1:10m Admin-1 States and Provinces",
            "upstream": "nvkelso/natural-earth-vector geojson/ne_10m_admin_1_states_provinces.geojson",
            "license": "Public domain",
            "historical_notice": "Modern admin-1 geometry used only as an approximate fallback where dedicated 1900 subdivisions are unavailable.",
        },
        "audit": {
            "region_count": len(records),
            "country_count": len(country_counts),
            "polygon_count": polygon_count,
            "countries_without_admin1_are_expected": True,
        },
        "regions": records,
    }
    output.write_text(json.dumps(compact, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(json.dumps(compact["audit"], ensure_ascii=False))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    build(args.source, args.output)


if __name__ == "__main__":
    main()
