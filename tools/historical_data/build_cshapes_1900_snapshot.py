#!/usr/bin/env python3
"""Build the offline 1900-03-12 CShapes snapshot used by the game.

The generated file is an isolated third-party non-commercial data layer. It is
not relicensed as project-owned data. Runtime code can replace this provider
without changing historical entity or flag registries.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import urllib.request
from pathlib import Path
from typing import Any

from shapely.geometry import mapping, shape

SOURCE_URL = "https://icr.ethz.ch/data/cshapes/CShapes-2.0.geojson"
SOURCE_PAGE = "https://icr.ethz.ch/data/cshapes/"
TARGET_DATE = dt.date(1900, 3, 12)
SIMPLIFY_TOLERANCE_DEGREES = 0.08
USER_AGENT = "wwo-cshapes-snapshot-builder/1.0"
OUTPUT_PATH = Path("data/world_map/historical/cshapes_1900_snapshot.json")
ATTRIBUTION_PATH = Path("data/world_map/historical/CShapes-2.0-ATTRIBUTION.md")


def fetch_source() -> bytes:
    request = urllib.request.Request(SOURCE_URL, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=180) as response:
        return response.read()


def active_on(properties: dict[str, Any], target: dt.date) -> bool:
    start = dt.date(
        int(properties["gwsyear"]),
        int(properties["gwsmonth"]),
        int(properties["gwsday"]),
    )
    end = dt.date(
        int(properties["gweyear"]),
        int(properties["gwemonth"]),
        int(properties["gweday"]),
    )
    return start <= target <= end


def date_string(properties: dict[str, Any], prefix: str) -> str:
    return "%04d-%02d-%02d" % (
        int(properties[prefix + "year"]),
        int(properties[prefix + "month"]),
        int(properties[prefix + "day"]),
    )


def rounded_coordinates(value: Any) -> Any:
    if isinstance(value, (list, tuple)):
        return [rounded_coordinates(item) for item in value]
    if isinstance(value, float):
        return round(value, 4)
    return value


def build_snapshot(source_payload: bytes) -> dict[str, Any]:
    source = json.loads(source_payload.decode("utf-8"))
    features: list[dict[str, Any]] = []
    for source_feature in source.get("features", []):
        properties = source_feature.get("properties", {})
        if not active_on(properties, TARGET_DATE):
            continue
        geometry = shape(source_feature["geometry"])
        simplified = geometry.simplify(
            SIMPLIFY_TOLERANCE_DEGREES,
            preserve_topology=True,
        )
        if simplified.is_empty or not simplified.is_valid:
            raise ValueError(
                "Invalid simplified geometry for gwcode %s"
                % properties.get("gwcode")
            )
        features.append(
            {
                "id": "gw_%s" % int(properties["gwcode"]),
                "gwcode": int(properties["gwcode"]),
                "source_name": str(properties["cntry_name"]),
                "valid_from": date_string(properties, "gws"),
                "valid_to": date_string(properties, "gwe"),
                "capital": {
                    "name": str(properties.get("capname", "")),
                    "lon": round(float(properties.get("caplong", 0.0)), 5),
                    "lat": round(float(properties.get("caplat", 0.0)), 5),
                },
                "area_km2": round(float(properties.get("area", 0.0)), 2),
                "geometry": {
                    "type": simplified.geom_type,
                    "coordinates": rounded_coordinates(
                        mapping(simplified)["coordinates"]
                    ),
                },
            }
        )
    features.sort(key=lambda feature: feature["gwcode"])
    if len(features) != 151:
        raise ValueError(
            "Expected 151 CShapes units on %s, found %d"
            % (TARGET_DATE.isoformat(), len(features))
        )
    return {
        "schema_version": 1,
        "snapshot_date": TARGET_DATE.isoformat(),
        "provider": "cshapes_2_0",
        "source": {
            "dataset": "CShapes 2.0",
            "version": "2.0",
            "source_page": SOURCE_PAGE,
            "download_url": SOURCE_URL,
            "source_sha256": hashlib.sha256(source_payload).hexdigest(),
            "license": "CC BY-NC-SA 4.0",
            "commercial_use_allowed": False,
            "citation": (
                "Schvitz et al. (2022), Mapping the International System, "
                "1886-2019: The CShapes 2.0 Dataset"
            ),
            "selection_rule": "gwsdate <= 1900-03-12 <= gwedate",
            "simplify_tolerance_degrees": SIMPLIFY_TOLERANCE_DEGREES,
        },
        "feature_count": len(features),
        "features": features,
    }


def attribution_text() -> str:
    return """# CShapes 2.0 attribution and license boundary

`cshapes_1900_snapshot.json` is a transformed snapshot of **CShapes 2.0**
for **1900-03-12**. It is kept as an isolated third-party data provider and is
not represented as project-owned historical research.

- Dataset: CShapes 2.0
- Official page: https://icr.ethz.ch/data/cshapes/
- Citation: Schvitz et al. (2022), *Mapping the International System,
  1886-2019: The CShapes 2.0 Dataset*.
- License: Creative Commons Attribution-NonCommercial-ShareAlike 4.0
  International (CC BY-NC-SA 4.0).
- Commercial use: not allowed by this provider's license.
- Transformation: select records active on 1900-03-12, simplify geometry with
  topology preservation at 0.08 degrees, round coordinates to four decimals.

A future commercial build must replace or omit this provider. Runtime code is
therefore required to load historical geometry through a provider boundary and
must not silently fall back to modern Natural Earth polygons.
"""


def main() -> int:
    payload = fetch_source()
    snapshot = build_snapshot(payload)
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(
        json.dumps(snapshot, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    ATTRIBUTION_PATH.write_text(attribution_text(), encoding="utf-8")
    print(
        json.dumps(
            {
                "output": str(OUTPUT_PATH),
                "feature_count": snapshot["feature_count"],
                "bytes": OUTPUT_PATH.stat().st_size,
                "source_sha256": snapshot["source"]["source_sha256"],
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
