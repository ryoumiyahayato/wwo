"""Build the offline V2.1.2 geographic prototype fixtures from Natural Earth.

The generated files remain prototype-only. Natural Earth data is public domain:
https://www.naturalearthdata.com/about/terms-of-use/
"""

from __future__ import annotations

import json
import math
import re
import sys
import urllib.request
from pathlib import Path
from typing import Iterable


ADMIN0_SOURCE_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "master/geojson/ne_110m_admin_0_countries.geojson"
)
ADMIN1_SOURCE_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "master/geojson/ne_10m_admin_1_states_provinces.geojson"
)
ROOT = Path(__file__).parents[2]
DEFAULT_OUTPUT = ROOT / "data/prototype_v2/prototype_world_coastlines.json"
COUNTRY_OUTPUT = ROOT / "data/prototype_v2/prototype_countries.json"
REGION_OUTPUT = ROOT / "data/prototype_v2/prototype_regions.json"
ROBINSON_X = [1.0, 0.9986, 0.9954, 0.99, 0.9822, 0.973, 0.96, 0.9427, 0.9216, 0.8962, 0.8679, 0.835, 0.7986, 0.7597, 0.7186, 0.6732, 0.6213, 0.5722, 0.5322]
ROBINSON_Y = [0.0, 0.062, 0.124, 0.186, 0.248, 0.31, 0.372, 0.434, 0.4958, 0.5571, 0.6176, 0.6769, 0.7346, 0.7903, 0.8435, 0.8936, 0.9394, 0.9761, 1.0]

THEME_COUNTRIES: dict[str, dict] = {
    "FRA": {"id": "country_fra", "display_name_zh": "法兰西共和国", "formal_name_zh": "法兰西第三共和国", "native_name": "République française", "government_name": "第三共和国", "emblem_type": "french_tricolor_rf", "label_priority": 100, "visible_zoom_min": 0.82, "legal_color": "#6689a4", "market_color": "#5f9f8c", "population_color": "#d48756", "war_color": "#537a93", "capital_city_id": "paris", "diplomacy": "和平 · 与邻国保持外交关系"},
    "DEU": {"id": "german_empire", "display_name_zh": "德意志帝国", "formal_name_zh": "德意志帝国", "native_name": "Deutsches Reich", "government_name": "帝国", "label_priority": 96, "visible_zoom_min": 0.82},
    "GBR": {"id": "british_empire", "display_name_zh": "大英帝国", "formal_name_zh": "大不列颠及爱尔兰联合王国", "native_name": "United Kingdom of Great Britain and Ireland", "government_name": "君主立宪制", "label_priority": 94, "visible_zoom_min": 0.82},
    "RUS": {"id": "russian_empire", "display_name_zh": "俄罗斯帝国", "formal_name_zh": "俄罗斯帝国", "native_name": "Россійская Имперія", "government_name": "帝国", "label_priority": 98, "visible_zoom_min": 0.82},
    "AUT": {"id": "austro_hungarian_empire", "display_name_zh": "奥匈帝国", "formal_name_zh": "奥匈帝国", "native_name": "Österreich-Ungarn", "government_name": "二元君主国", "label_priority": 86, "visible_zoom_min": 0.9},
    "TUR": {"id": "ottoman_empire", "display_name_zh": "奥斯曼帝国", "formal_name_zh": "奥斯曼帝国", "native_name": "Devlet-i ʿAlīye-i ʿOsmānīye", "government_name": "帝国", "label_priority": 88, "visible_zoom_min": 0.82},
    "USA": {"id": "united_states", "display_name_zh": "美利坚合众国", "formal_name_zh": "美利坚合众国", "native_name": "United States of America", "government_name": "联邦共和国", "label_priority": 98, "visible_zoom_min": 0.82},
    "CHN": {"id": "qing_empire", "display_name_zh": "大清帝国", "formal_name_zh": "大清帝国", "native_name": "大清國", "government_name": "帝国", "label_priority": 98, "visible_zoom_min": 0.82},
    "JPN": {"id": "japanese_empire", "display_name_zh": "日本帝国", "formal_name_zh": "大日本帝国", "native_name": "大日本帝國", "government_name": "帝国", "label_priority": 84, "visible_zoom_min": 0.9},
    "ARG": {"id": "argentine_republic", "display_name_zh": "阿根廷共和国", "formal_name_zh": "阿根廷共和国", "native_name": "República Argentina", "government_name": "联邦共和国", "label_priority": 62, "visible_zoom_min": 1.15},
}

CONTINENT_COLORS: dict[str, str] = {
    "Africa": "#777d68", "Asia": "#747a68", "Europe": "#6e7d76",
    "North America": "#6e7c71", "South America": "#6f806e",
    "Oceania": "#7b806d", "Seven seas (open ocean)": "#737b70",
    "Antarctica": "#7b8178",
}

MACRO_REGION_SPECS: list[dict] = [
    {"id": "northern_industrial_belt", "name": "北部工业带", "native_name": "Ceinture industrielle du Nord", "modern_regions": ["Hauts-de-France"], "label_anchor": [2.8, 50.35], "label_priority": 100, "population": "高", "market": "煤炭与机械行业观察", "institution_ids": ["prefecture_nord", "labor_inspectorate_nord", "sous_prefecture_lille", "mairie_lille"], "colors": ["#7799b1", "#c0834e", "#d7794b"]},
    {"id": "paris_basin", "name": "巴黎盆地", "native_name": "Bassin parisien", "modern_regions": ["Île-de-France", "Grand Est"], "label_anchor": [2.35, 48.55], "label_priority": 96, "population": "极高", "market": "首都综合市场", "institution_ids": ["national_assembly"], "colors": ["#7394ad", "#4f9c82", "#dc7449"]},
    {"id": "normandy", "name": "诺曼底", "native_name": "Normandie", "modern_regions": ["Normandie"], "label_anchor": [0.0, 49.15], "label_priority": 90, "population": "中等", "market": "塞纳河口行业观察", "institution_ids": ["prefecture_seine_inferieure"], "colors": ["#6f8da6", "#bc8353", "#b98a5a"]},
    {"id": "brittany", "name": "布列塔尼", "native_name": "Bretagne", "modern_regions": ["Bretagne"], "label_anchor": [-3.15, 48.05], "label_priority": 78, "population": "较低", "market": "沿海食品行业观察", "institution_ids": [], "colors": ["#68879f", "#65927d", "#8f9167"]},
    {"id": "loire_valley", "name": "卢瓦尔河谷", "native_name": "Val de Loire", "modern_regions": ["Pays de la Loire", "Centre-Val de Loire"], "label_anchor": [0.0, 46.9], "label_priority": 74, "population": "中等", "market": "农业与港口行业观察", "institution_ids": [], "colors": ["#708fa7", "#60917e", "#af8a5d"]},
    {"id": "aquitaine", "name": "阿基坦", "native_name": "Aquitaine", "modern_regions": ["Nouvelle-Aquitaine"], "department_codes": ["FR-31"], "label_anchor": [-0.1, 44.25], "label_priority": 80, "population": "中等", "market": "葡萄酒与农业行业观察", "institution_ids": [], "colors": ["#6b89a0", "#6e9472", "#a9895e"]},
    {"id": "massif_central", "name": "中央高原", "native_name": "Massif central", "modern_regions": ["Bourgogne-Franche-Comté"], "department_codes": ["FR-03", "FR-15", "FR-43", "FR-63"], "label_anchor": [2.75, 45.2], "label_priority": 72, "population": "较低", "market": "山地农业行业观察", "institution_ids": [], "colors": ["#748e9f", "#748c72", "#9a8d62"]},
    {"id": "rhone_valley", "name": "罗讷河谷", "native_name": "Vallée du Rhône", "modern_regions": [], "department_codes": ["FR-01", "FR-07", "FR-26", "FR-38", "FR-42", "FR-69", "FR-73", "FR-74"], "label_anchor": [5.15, 45.65], "label_priority": 86, "population": "较高", "market": "机械与纺织行业观察", "institution_ids": [], "colors": ["#7897ad", "#639082", "#c58053"]},
    {"id": "mediterranean_coast", "name": "地中海沿岸", "native_name": "Littoral méditerranéen", "modern_regions": ["Occitanie", "Provence-Alpes-Côte-d'Azur", "Corse"], "label_anchor": [4.3, 43.25], "label_priority": 88, "population": "较高", "market": "地中海港口行业观察", "institution_ids": ["marseille_port_authority"], "colors": ["#7191a8", "#5b958d", "#c47e54"]},
]


def _fetch_json(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=120) as response:
        return json.load(response)


def _round_point(point: Iterable[float]) -> list[float]:
    values = list(point)
    return [round(float(values[0]), 4), round(float(values[1]), 4)]


def _orientation(a: list[float], b: list[float], c: list[float]) -> float:
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def _segments_cross(a: list[float], b: list[float], c: list[float], d: list[float]) -> bool:
    first = _orientation(a, b, c)
    second = _orientation(a, b, d)
    third = _orientation(c, d, a)
    fourth = _orientation(c, d, b)
    return (first > 0.0) != (second > 0.0) and (third > 0.0) != (fourth > 0.0)


def _self_intersection(points: list[list[float]]) -> tuple[int, int] | None:
    count = len(points)
    for first_index in range(count):
        a = points[first_index]
        b = points[(first_index + 1) % count]
        for second_index in range(first_index + 2, count):
            if (second_index + 1) % count == first_index:
                continue
            c = points[second_index]
            d = points[(second_index + 1) % count]
            if _segments_cross(a, b, c, d):
                return first_index, second_index
    return None


def _robinson_point(point: list[float]) -> list[float]:
    longitude, latitude = point
    coefficient_index = abs(latitude) / 5.0
    lower = min(int(math.floor(coefficient_index)), len(ROBINSON_X) - 1)
    upper = min(lower + 1, len(ROBINSON_X) - 1)
    weight = coefficient_index - lower
    x_coefficient = ROBINSON_X[lower] * (1.0 - weight) + ROBINSON_X[upper] * weight
    y_coefficient = ROBINSON_Y[lower] * (1.0 - weight) + ROBINSON_Y[upper] * weight
    projected_x = 0.8487 * math.radians(longitude) * x_coefficient
    projected_y = 1.3523 * (1.0 if latitude >= 0.0 else -1.0) * y_coefficient
    return [(projected_x / (2.6662696851 * 2.0) + 0.5) * 1080.0, (0.5 - projected_y / (1.3523 * 2.0)) * 540.0]


def _sanitize_ring(raw_ring: Iterable[Iterable[float]]) -> tuple[list[list[float]], list[str]]:
    points: list[list[float]] = []
    for raw_point in raw_ring:
        point = _round_point(raw_point)
        if not points or point != points[-1]:
            points.append(point)
    if points and points[0] == points[-1]:
        points.pop()
    repairs: list[str] = []
    while len(points) >= 3:
        crossing = _self_intersection(points)
        if crossing is None:
            break
        first_index, second_index = crossing
        # Natural Earth occasionally contains a one-vertex backtracking spike. Removing
        # the first vertex of the later crossing segment preserves the surrounding border.
        removed_index = second_index
        removed = points.pop(removed_index)
        repairs.append(f"removed self-intersection spike at {removed}")
    while len(points) >= 3:
        crossing = _self_intersection([_robinson_point(point) for point in points])
        if crossing is None:
            break
        first_index, second_index = crossing
        removed_index = len(points) - 1 if first_index == 0 and second_index == len(points) - 2 else second_index
        removed = points.pop(removed_index)
        repairs.append(f"removed Robinson-projection self-intersection spike at {removed}")
    if len(points) < 3:
        return [], repairs
    points.append(points[0])
    return points, repairs


def _geometry_parts(geometry: dict) -> tuple[list[dict], list[str]]:
    geometry_type = str(geometry.get("type", ""))
    coordinates = geometry.get("coordinates", [])
    raw_polygons: list = []
    if geometry_type == "Polygon" and coordinates:
        raw_polygons = [coordinates]
    elif geometry_type == "MultiPolygon":
        raw_polygons = [polygon for polygon in coordinates if polygon]
    result: list[dict] = []
    repairs: list[str] = []
    for raw_polygon in raw_polygons:
        outer, outer_repairs = _sanitize_ring(raw_polygon[0])
        repairs.extend(outer_repairs)
        if not outer:
            continue
        holes: list[list[list[float]]] = []
        for raw_hole in raw_polygon[1:]:
            hole, hole_repairs = _sanitize_ring(raw_hole)
            repairs.extend(hole_repairs)
            if hole:
                holes.append(hole)
        result.append({"outer": outer, "holes": holes})
    return result, repairs


def _valid_code(value: object) -> str:
    code = str(value or "").strip().upper()
    return code if code and code != "-99" else ""


def _stable_country_code(properties: dict) -> str:
    for field in ("ADM0_A3", "ISO_A3", "BRK_A3", "SOV_A3"):
        code = _valid_code(properties.get(field))
        if code:
            return code
    ne_id = str(properties.get("NE_ID", "unknown"))
    return f"NE{ne_id}"


def _slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")


def _country_label_min(label_rank: int) -> float:
    if label_rank <= 3:
        return 0.82
    if label_rank == 4:
        return 1.15
    if label_rank == 5:
        return 1.7
    if label_rank == 6:
        return 2.4
    if label_rank == 7:
        return 3.2
    return 4.5


def _country_record(properties: dict, code: str, feature_id: str) -> dict:
    source_iso = str(properties.get("ISO_A3", ""))
    display_name = str(properties.get("NAME_ZH") or properties.get("NAME_EN") or properties.get("NAME") or code)
    native_name = str(properties.get("NAME_EN") or properties.get("NAME") or display_name)
    label_rank = int(properties.get("LABELRANK", 9))
    base = {
        "id": f"country_{_slug(code)}",
        "stable_id": f"country_{_slug(code)}",
        "data_code": code,
        "source_iso_a3": source_iso,
        "display_name_zh": display_name,
        "formal_name_zh": display_name,
        "native_name": native_name,
        "native_name_source": "natural_earth_name_en_fallback",
        "government_name": "政体资料待扩充",
        "name": display_name,
        "object_level": "country",
        "geometry_feature_ids": [feature_id],
        "geometry_iso_a3": [code],
        "label_anchor": [round(float(properties.get("LABEL_X", 0.0)), 4), round(float(properties.get("LABEL_Y", 0.0)), 4)],
        "label_lon_lat": [round(float(properties.get("LABEL_X", 0.0)), 4), round(float(properties.get("LABEL_Y", 0.0)), 4)],
        "label_priority": max(18, 112 - label_rank * 8),
        "visible_zoom_min": _country_label_min(label_rank),
        "min_zoom": _country_label_min(label_rank),
        "max_zoom": 96.0,
        "neutral_land_color": CONTINENT_COLORS.get(str(properties.get("CONTINENT", "")), "#738077"),
        "diplomacy": "公开外交资料待扩充",
        "boundary_status": "modern_natural_earth_prototype_geometry",
        "theme_label_placeholder": code not in THEME_COUNTRIES,
    }
    override = THEME_COUNTRIES.get(code, {})
    base.update(override)
    base["stable_id"] = base["id"]
    base["name"] = base["display_name_zh"]
    base["min_zoom"] = base["visible_zoom_min"]
    if code in THEME_COUNTRIES:
        base["native_name_source"] = "v2_1_theme_override"
    return base


def _build_admin0(source: dict) -> tuple[dict, dict]:
    features: list[dict] = []
    countries: list[dict] = []
    for source_index, feature in enumerate(source.get("features", [])):
        properties = feature.get("properties", {})
        polygons, repairs = _geometry_parts(feature.get("geometry", {}))
        if not polygons:
            continue
        code = _stable_country_code(properties)
        ne_id = str(properties.get("NE_ID", source_index))
        feature_id = f"ne_admin0_{_slug(ne_id)}"
        source_iso = str(properties.get("ISO_A3", ""))
        features.append({
            "id": feature_id,
            "stable_id": feature_id,
            "iso_a3": code,
            "source_iso_a3": source_iso,
            "fallback_code_used": source_iso in ("", "-99"),
            "name": str(properties.get("NAME_EN") or properties.get("NAME") or code),
            "display_name_zh": str(properties.get("NAME_ZH") or properties.get("NAME_EN") or code),
            "continent": str(properties.get("CONTINENT", "")),
            "label_rank": int(properties.get("LABELRANK", 9)),
            "geometry_type": str(feature.get("geometry", {}).get("type", "")),
            "polygons": polygons,
            "rings": [polygon["outer"] for polygon in polygons],
            "outer_ring_count": len(polygons),
            "hole_count": sum(len(polygon["holes"]) for polygon in polygons),
            "repair_notes": repairs,
        })
        countries.append(_country_record(properties, code, feature_id))
    countries.sort(key=lambda record: (-int(record["label_priority"]), str(record["stable_id"])))
    repaired = [feature for feature in features if feature["repair_notes"]]
    geometry_document = {
        "prototype_only": True,
        "schema_version": 3,
        "source": {
            "dataset": "Natural Earth Vector 1:110m Admin 0 Countries",
            "upstream_url": ADMIN0_SOURCE_URL,
            "terms_url": "https://www.naturalearthdata.com/about/terms-of-use/",
            "license": "Public domain",
            "processing": "All Polygon and MultiPolygon exteriors retained; true interior rings retained separately; coordinates rounded to four decimals; self-intersection spikes repaired without drawing manual land patches.",
            "prototype_notice": "本轮仅用于视觉原型；政治边界仅为视觉原型近似，采用现代 Natural Earth 数据，不作为最终历史地图。",
        },
        "coordinate_system": "WGS84 longitude/latitude",
        "audit": {
            "feature_count": len(features),
            "africa_feature_count": sum(1 for feature in features if feature["continent"] == "Africa"),
            "fallback_id_count": sum(1 for feature in features if feature["fallback_code_used"]),
            "outer_ring_count": sum(feature["outer_ring_count"] for feature in features),
            "hole_count": sum(feature["hole_count"] for feature in features),
            "repaired_features": [{"stable_id": feature["stable_id"], "iso_a3": feature["iso_a3"], "name": feature["name"], "reason": feature["repair_notes"]} for feature in repaired],
        },
        "features": features,
    }
    country_document = {
        "prototype_only": True,
        "schema_version": 4,
        "hierarchy": "world/country",
        "historical_notice": "世界边界采用现代 Natural Earth 几何。主要国家保留 1900 年主题名称，其余国家名称用于完整标签与交互覆盖，不代表完整历史疆域。",
        "name_coverage": {"records": len(countries), "display_name_zh": len(countries), "formal_name_zh": len(countries), "native_name": len(countries), "label_anchor": len(countries)},
        "countries": countries,
    }
    return geometry_document, country_document


def _admin_stable_id(iso_code: str, native_name: str) -> str:
    if iso_code == "FR-59":
        return "departement_nord"
    return f"departement_{_slug(iso_code or native_name)}"


def _build_admin1(source: dict) -> dict:
    units: list[dict] = []
    unit_by_code: dict[str, dict] = {}
    for feature in source.get("features", []):
        properties = feature.get("properties", {})
        if properties.get("adm0_a3") != "FRA" or properties.get("type_en") != "Metropolitan department":
            continue
        polygons, repairs = _geometry_parts(feature.get("geometry", {}))
        if not polygons:
            continue
        iso_code = str(properties.get("iso_3166_2") or properties.get("adm1_code") or "")
        native_name = str(properties.get("name_fr") or properties.get("name") or iso_code)
        display_name = str(properties.get("name_zh") or native_name)
        unit = {
            "id": _admin_stable_id(iso_code, native_name),
            "stable_id": _admin_stable_id(iso_code, native_name),
            "source_code": iso_code,
            "administrative_level": "departement",
            "object_level": "administrative_unit",
            "region_kind": "historical_administrative_unit",
            "parent_country_id": "country_fra",
            "parent_id": "country_fra",
            "geometry": polygons,
            "label_anchor": [round(float(properties.get("longitude", 0.0)), 4), round(float(properties.get("latitude", 0.0)), 4)],
            "label_priority": 96 if iso_code in {"FR-59", "FR-62", "FR-75", "FR-76", "FR-44", "FR-33", "FR-69", "FR-13"} else 45,
            "visible_zoom_min": 8.4 if iso_code in {"FR-59", "FR-62", "FR-75", "FR-76", "FR-44", "FR-33", "FR-69", "FR-13", "FR-14", "FR-27", "FR-50", "FR-61"} else 12.5,
            "min_zoom": 8.4 if iso_code in {"FR-59", "FR-62", "FR-75", "FR-76", "FR-44", "FR-33", "FR-69", "FR-13", "FR-14", "FR-27", "FR-50", "FR-61"} else 12.5,
            "max_zoom": 96.0,
            "display_name_zh": display_name,
            "name": display_name,
            "native_name": native_name,
            "modern_region_name": str(properties.get("region", "")),
            "jurisdiction_name": display_name,
            "geometry_source": "Natural Earth 1:10m Admin 1 modern department boundary; reliable simplified placeholder for the 1900 theme",
            "repair_notes": repairs,
        }
        if iso_code == "FR-75":
            unit["historical_context"] = "巴黎相关行政区占位；1900 年塞纳省制度边界尚未完整录入"
        units.append(unit)
        unit_by_code[iso_code] = unit

    # The institution prototype already references these two local levels. Their small,
    # irregular outlines are review placeholders and never replace the department source.
    units.extend([
        {"id": "arrondissement_lille", "stable_id": "arrondissement_lille", "administrative_level": "arrondissement", "object_level": "administrative_unit", "region_kind": "historical_administrative_unit", "parent_country_id": "country_fra", "parent_id": "departement_nord", "geometry": [{"outer": [[2.72, 50.42], [3.02, 50.31], [3.38, 50.39], [3.48, 50.66], [3.24, 50.88], [2.84, 50.82], [2.65, 50.61], [2.72, 50.42]], "holes": []}], "label_anchor": [3.06, 50.64], "label_priority": 82, "visible_zoom_min": 17.0, "min_zoom": 17.0, "max_zoom": 96.0, "display_name_zh": "里尔区", "name": "里尔区", "native_name": "Arrondissement de Lille", "jurisdiction_name": "里尔区", "geometry_source": "simplified local review placeholder"},
        {"id": "commune_lille", "stable_id": "commune_lille", "administrative_level": "commune", "object_level": "administrative_unit", "region_kind": "historical_administrative_unit", "parent_country_id": "country_fra", "parent_id": "arrondissement_lille", "geometry": [{"outer": [[3.015, 50.61], [3.055, 50.59], [3.105, 50.608], [3.122, 50.648], [3.083, 50.677], [3.032, 50.665], [3.006, 50.637], [3.015, 50.61]], "holes": []}], "label_anchor": [3.063, 50.637], "label_priority": 78, "visible_zoom_min": 20.0, "min_zoom": 20.0, "max_zoom": 96.0, "display_name_zh": "里尔市", "name": "里尔市", "native_name": "Commune de Lille", "jurisdiction_name": "里尔市", "geometry_source": "simplified local review placeholder"},
    ])

    assigned_codes: set[str] = set()
    regions: list[dict] = []
    for spec in MACRO_REGION_SPECS:
        selected_codes: list[str] = []
        for code, unit in unit_by_code.items():
            if code in assigned_codes:
                continue
            if unit["modern_region_name"] in spec.get("modern_regions", []) or code in spec.get("department_codes", []):
                selected_codes.append(code)
        assigned_codes.update(selected_codes)
        colors = spec["colors"]
        regions.append({
            "id": spec["id"], "stable_id": spec["id"], "name": spec["name"], "display_name_zh": spec["name"], "native_name": spec["native_name"],
            "object_level": "region", "region_kind": "gameplay_macro_region", "administrative_level": "gameplay_macro", "parent_country_id": "country_fra",
            "administrative_unit_ids": [unit_by_code[code]["stable_id"] for code in selected_codes],
            "geometry_composition": "runtime union of referenced administrative unit polygons",
            "label_anchor": spec["label_anchor"], "label_lon_lat": spec["label_anchor"], "label_priority": spec["label_priority"], "visible_zoom_min": 6.21, "min_zoom": 6.21, "max_zoom": 96.0,
            "population": spec["population"], "market": spec["market"], "market_state": "静态原型占位", "institution_ids": spec["institution_ids"],
            "legal_color": colors[0], "market_color": colors[1], "population_color": colors[2],
        })

    unassigned = [code for code in unit_by_code if code not in assigned_codes]
    return {
        "prototype_only": True,
        "schema_version": 4,
        "focus_country_id": "country_fra",
        "macro_region_notice": "游戏宏观地区由行政单位组合形成，不等同于历史行政区划。",
        "administrative_geometry_notice": "省界采用 Natural Earth 1:10m 现代法国省级边界，作为 1900 主题的可靠简化占位；塞纳省等历史差异尚未完整录入。",
        "source": {"dataset": "Natural Earth Vector 1:10m Admin 1 States/Provinces", "upstream_url": ADMIN1_SOURCE_URL, "license": "Public domain"},
        "coverage": {"metropolitan_department_count": len(unit_by_code), "macro_region_count": len(regions), "unassigned_department_codes": unassigned},
        "regions": regions,
        "administrative_units": units,
    }


def build(output_path: Path) -> None:
    admin0_source = _fetch_json(ADMIN0_SOURCE_URL)
    geometry_document, country_document = _build_admin0(admin0_source)
    region_document = _build_admin1(_fetch_json(ADMIN1_SOURCE_URL))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(geometry_document, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    COUNTRY_OUTPUT.write_text(json.dumps(country_document, ensure_ascii=False, indent=2), encoding="utf-8")
    REGION_OUTPUT.write_text(json.dumps(region_document, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"Wrote {len(geometry_document['features'])} country features to {output_path}")
    print(f"Wrote {len(country_document['countries'])} complete country name records to {COUNTRY_OUTPUT}")
    print(f"Wrote {region_document['coverage']['metropolitan_department_count']} French department geometries to {REGION_OUTPUT}")
    for repair in geometry_document["audit"]["repaired_features"]:
        print(f"GEOMETRY_REPAIR {repair['iso_a3']} {repair['name']}: {'; '.join(repair['reason'])}")


if __name__ == "__main__":
    destination = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUTPUT
    build(destination.resolve())
