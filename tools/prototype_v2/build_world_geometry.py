"""Build the offline V2.1 world geometry fixture from Natural Earth GeoJSON.

The generated file is prototype-only. Natural Earth data is public domain:
https://www.naturalearthdata.com/about/terms-of-use/
"""

from __future__ import annotations

import json
import sys
import urllib.request
from pathlib import Path
from typing import Iterable


SOURCE_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "master/geojson/ne_110m_admin_0_countries.geojson"
)
DEFAULT_OUTPUT = Path(__file__).parents[2] / "data/prototype_v2/prototype_world_coastlines.json"
def _simplify_ring(raw_ring: Iterable[Iterable[float]]) -> list[list[float]]:
    ring = [[round(float(point[0]), 4), round(float(point[1]), 4)] for point in raw_ring]
    if len(ring) < 4:
        return []
    if ring[0] != ring[-1]:
        ring.append(ring[0])
    return ring


def _exterior_rings(geometry: dict) -> list[list[list[float]]]:
    geometry_type = geometry.get("type", "")
    coordinates = geometry.get("coordinates", [])
    raw_rings: list = []
    if geometry_type == "Polygon" and coordinates:
        raw_rings = [coordinates[0]]
    elif geometry_type == "MultiPolygon":
        raw_rings = [polygon[0] for polygon in coordinates if polygon]
    result: list[list[list[float]]] = []
    for raw_ring in raw_rings:
        ring = _simplify_ring(raw_ring)
        if ring:
            result.append(ring)
    return result


def build(output_path: Path) -> None:
    with urllib.request.urlopen(SOURCE_URL, timeout=30) as response:
        source = json.load(response)

    features: list[dict] = []
    for index, feature in enumerate(source.get("features", [])):
        properties = feature.get("properties", {})
        rings = _exterior_rings(feature.get("geometry", {}))
        if not rings:
            continue
        iso_a3 = str(properties.get("ADM0_A3") or properties.get("ISO_A3") or "")
        name = str(properties.get("NAME_EN") or properties.get("NAME") or iso_a3)
        features.append(
            {
                "id": f"ne_{iso_a3.lower()}_{index}",
                "iso_a3": iso_a3,
                "name": name,
                "continent": str(properties.get("CONTINENT", "")),
                "label_rank": int(properties.get("LABELRANK", 9)),
                "rings": rings,
            }
        )

    document = {
        "prototype_only": True,
        "schema_version": 2,
        "source": {
            "dataset": "Natural Earth Vector 1:110m Admin 0 Countries",
            "upstream_url": SOURCE_URL,
            "terms_url": "https://www.naturalearthdata.com/about/terms-of-use/",
            "license": "Public domain",
            "processing": (
                "Natural Earth 1:110m source simplification retained; exterior rings only; "
                "unused attributes removed; coordinates rounded to four decimals; no additional topology-changing simplification."
            ),
            "prototype_notice": "本轮仅用于视觉原型；政治边界仅为视觉原型近似，不作为最终历史数据。",
        },
        "coordinate_system": "WGS84 longitude/latitude",
        "features": features,
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(document, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"Wrote {len(features)} country features to {output_path}")


if __name__ == "__main__":
    destination = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUTPUT
    build(destination.resolve())
