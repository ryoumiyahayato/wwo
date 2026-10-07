"""Build the bounded historical supplement; never change original CShapes dates.

The input is an explicitly approximate interpretation of a 1900 map, not modern
country boundaries. Existing geography wins every intersection. Geography and
administrative assignments are emitted separately and admitted by the formal structured provenance generator.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from shapely import make_valid, set_precision
from shapely.geometry import Polygon, MultiPolygon, box, mapping, shape
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "data/world_map/historical"
DATE = "1900-01-01"
EVIDENCE_WINDOW_END = "1901-01-01"
BOOK = "https://www.gutenberg.org/cache/epub/63928/pg63928-images.html"
TREATIES = "https://www.qdl.qa/en/archive/81055/vdc_100023462214.0x000011"
NW_ORDER = "https://upload.wikimedia.org/wikipedia/commons/a/ab/UKSRO_1901.pdf"
NE_ARCHIVE = "https://calmview.derbyshire.gov.uk/CalmView/Record.aspx?id=D3287%2FBSA%2F8%2F6&src=calmview.catalog"
NAM = "https://collection.nam.ac.uk/detail.php?acc=1998-03-21-1"


def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write(path: Path, value: dict) -> None:
    path.write_bytes((json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8"))


def polygons(geometry):
    if geometry.geom_type == "Polygon":
        return [geometry]
    return [p for g in getattr(geometry, "geoms", []) for p in polygons(g)]


def generalize(geometry):
    # Only the new supplement is generalized. This removes numerical overlay
    # slivers below the source map's resolution and records that limitation.
    fixed = set_precision(make_valid(geometry), 0.00001)
    parts = [p for p in polygons(fixed) if p.area >= 0.00001]
    return MultiPolygon(parts) if len(parts) > 1 else parts[0] if parts else Polygon()


def main():
    traces = read(BASE / "sources/arabia_1900_traces.json")
    original = read(BASE / "cshapes_1900_snapshot.json")
    if traces["schema_version"] != 1 or original["schema_version"] != 1:
        raise ValueError("Unsupported historical trace or CShapes snapshot schema")
    scope = box(34, 12, 61, 32)
    existing = unary_union([make_valid(shape(f["geometry"])) for f in original["features"]
                            if shape(f["geometry"]).intersects(scope)])
    peninsula = Polygon(traces["peninsula_outline"])
    features, claimed, already_present = [], Polygon(), []
    for row in traces["regions"]:
        outline = unary_union([Polygon(r) for r in row["rings"]])
        if not row.get("offshore"):
            outline = outline.intersection(peninsula)
        geometry = generalize(outline.difference(existing).difference(claimed))
        if geometry.is_empty:
            if outline.difference(existing).area < 0.00001:
                already_present.append(row["id"])
                continue
            raise ValueError("Supplement region unexpectedly disappeared: " + row["id"])
        claimed = unary_union([claimed, geometry])
        features.append({"id": row["id"], "source_name": row["name"],
                         "geography_status": "APPROXIMATE_HISTORICAL_GEOGRAPHY", "geography_confidence": "APPROXIMATE",
                         "geography_basis": row["basis"], "source_date": traces["source_date"], "target_date": DATE,
                         "source": traces["source"], "boundary_note": row["boundary_note"], "geometry": mapping(geometry)})
    residual = generalize(peninsula.difference(existing).difference(claimed))
    if not residual.is_empty:
        features.append({"id": "arabia_undelimited_desert_1900", "source_name": "Arabian undelimited desert / tribal geography",
                         "geography_status": "APPROXIMATE_HISTORICAL_GEOGRAPHY", "geography_confidence": "APPROXIMATE",
                         "geography_basis": "BOUNDED_HISTORICAL_MAP", "source_date": traces["source_date"], "target_date": DATE,
                         "source": traces["source"], "boundary_note": "Physical land closure only; no exclusive polity/administrator inferred over undelimited desert and tribal areas.",
                         "geometry": mapping(residual)})
    output = {"schema_version": 1, "provider": "wwo_historical_map_digitization", "target_date": DATE,
              "feature_count": len(features), "exterior_count": sum(len(polygons(shape(f["geometry"]))) for f in features), "already_present_regions": already_present,
              "source": {"title": traces["source_title"], "source_date": traces["source_date"], "source_page": traces["source"],
                         "geography_confidence": "APPROXIMATE", "geography_basis": "BOUNDED_HISTORICAL_MAP",
                         "trace_path": "res://data/world_map/historical/sources/arabia_1900_traces.json",
                         "trace_schema_version": traces["schema_version"],
                         "source_assets": [{"path": "res://" + p.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
                                           for p in [BASE / "sources/arabia_zwemer_1900_map.jpg", BASE / "sources/bahrain_zwemer_1900_map.jpg"]],
                         "method": traces["method"], "coordinate_grid_degrees": 0.00001, "minimum_overlay_component_area_degrees2": 0.00001,
                         "clip_priority": "Existing CShapes unchanged", "license": "CC-BY-NC-SA-4.0 (overlay derived from CShapes)"}, "features": features}
    geography_path = BASE / "arabia_gulf_geography_1900.json"
    write(geography_path, output)
    specs = [
        ("arabia_rashidi_1900", "拉希德酋长国 / 内志", "rashidi_emirate", "LOCAL_DYNASTIC_ADMINISTRATION", "Rashidi emirate; nominal Ottoman alliance/tribute, local administration", "rashidi_authority_1900", BOOK + "#Page_200", "1900", 0.85, [41.683,27.521]),
        ("arabia_aden_settlement_1900", "亚丁居留地", "aden_residency_bombay", "COLONIAL_ADMINISTRATION", "British possession under Bombay Presidency; distinct from inland treaty states", "uk_union_1801", BOOK + "#Page_218", "1900", 0.9, [45.03,12.78]),
        ("arabia_aden_treaty_states_1900", "亚丁条约诸邦", "aden_treaty_states", "PROTECTED_LOCAL_AUTHORITIES", "Separate local rulers, treaty relations managed by Aden Residency; not one sovereign state", "uk_union_1801", TREATIES, "1888/1895/1896 treaties (1933 compilation)", 0.7, [46.2,14.3]),
        ("arabia_kathiri_1900", "卡迪里苏丹国", "kathiri_sultanate", "LOCAL_SULTANATE", "Local Kathiri authority; the 1918 British agreement is not active in 1900", "", TREATIES, "1918 agreement (1933 retrospective compilation)", 0.7, [48.8,15.96]),
        ("arabia_quaiti_1900", "奎提苏丹国", "quaiti_sultanate", "PROTECTED_LOCAL_AUTHORITY", "Local Quaiti ruler; British protection treaty 1888, no British annexation", "uk_union_1801", BOOK + "#Page_72", "1900 (describing 1893/1897 journeys)", 0.8, [49.12,14.5]),
        ("arabia_mahra_1900", "马赫拉苏丹国", "mahra_sultanate", "PROTECTED_LOCAL_AUTHORITY", "Local Mahra ruler; British treaty/protection relationship, not annexation", "uk_union_1801", TREATIES, "1886 treaty (1933 compilation)", 0.75, [51.68,15.42]),
        ("arabia_dhofar_1900", "佐法尔 / 马斯喀特", "muscat_dhofar_administration", "LOCAL_ADMINISTRATION", "Muscat authority restored after the 1895 Kathiri incursion, port recaptured 1897", "muscat_oman_plain_red", "https://www.qdl.qa/en/archive/81055/vdc_100074465384.0x00006f", "1897 event (1929 historical narrative)", 0.75, [54.1,17.02]),
        ("arabia_kuwait_1900", "科威特酋长国", "sabah_kuwait", "PROTECTED_LOCAL_AUTHORITY", "Mubarak Al Sabah locally administers; British exclusive agreement 1899-01-23; Ottoman nominal claim remains contested", "uk_union_1801", "https://e.gov.kw/sites/kgoenglish/Pages/Visitors/AboutKuwait/GoverningBodyOverView.aspx", "1899-01-23 treaty", 0.9, [47.98,29.37]),
        ("arabia_qatar_1900", "卡塔尔 / 阿勒萨尼", "al_thani_qatar", "LOCAL_ADMINISTRATION", "Jassim Al Thani de facto local authority; Ottoman garrison/nominal sovereignty; no 1916 British protectorate", "ottoman_1844", "https://www.diwan.gov.qa/about-qatar/qatars-rulers/sheikh-jassim-bin-mohammed-bin-thani", "1893 settlement / 1900 continuity", 0.85, [51.53,25.29]),
        ("arabia_bahrain_1900", "巴林酋长国", "al_khalifa_bahrain", "PROTECTED_LOCAL_AUTHORITY", "Sheikh Isa Al Khalifa local authority; British protection, not Britain as a sovereign nation-state identity", "bahrain_authority_1900", BOOK + "#Page_219", "1900 / observation 1899", 0.9, [50.586,26.223]),
        ("gw_552", "罗得西亚 / BSAC", "bsac_southern_administration", "COMPANY_ADMINISTRATION", "British imperial charter/sphere; separate company administrator, no sovereign BSAC nation", "bsac_company_1893", NAM, "1890-1923 museum object/history", 0.9, [31.04,-17.82]),
        ("gw_5518", "东北罗得西亚 / BSAC", "bsac_northeastern_administration", "COMPANY_ADMINISTRATION", "BSAC deputy administration at Fort Jameson in April 1899; formal protectorate Order 1900-01-29 later", "bsac_company_1893", NE_ARCHIVE, "1899-04-24", 0.85, [32.63,-13.65]),
        ("gw_5519", "西北罗得西亚 / BSAC", "bsac_barotse_administration", "COMPANY_ADMINISTRATION", "BSAC administration alongside Lewanika/local courts; British protection; Order signed 1899-11-28, printed SR&O 1901/567", "bsac_company_1893", NW_ORDER, "1899-11-28 (1901 printed collection)", 0.85, [25.15,-15.3]),
    ]
    assignments = []
    historical_centers = {
        "arabia_rashidi_1900": "Hail", "arabia_aden_settlement_1900": "Aden",
        "arabia_kathiri_1900": "Seiyun", "arabia_quaiti_1900": "Mukalla",
        "arabia_mahra_1900": "Qishn", "arabia_kuwait_1900": "Kuwait",
        "arabia_qatar_1900": "Al Bida", "arabia_bahrain_1900": "Manama",
    }
    catalog_path = BASE / "political_visuals_1900.json"
    catalog = read(catalog_path)
    for asset_id in ["rashidi_authority_1900", "bahrain_authority_1900"]:
        catalog["records"][asset_id]["valid_to"] = EVIDENCE_WINDOW_END
    for feature_id, name, administrator, kind, relation, visual, source, source_date, confidence, capital in specs:
        if feature_id in already_present:
            # Dhofar is already a component of gw_698/Oman; no duplicate region
            # or whole-country administrative reassignment is needed.
            catalog["territories"].pop("map_authority:" + feature_id, None)
            continue
        source_id = "map_authority:" + feature_id
        row = {"id": source_id, "source_historical_id": source_id, "geometry_feature_id": feature_id,
               "name_zh": name, "short_name_zh": name, "label_rank": 3,
               "assignment_kind": "APPROXIMATE_HISTORICAL_AUTHORITY", "authority_type": kind,
               "administrator_id": administrator, "sovereignty_imperial_relation": relation,
               "controller_id": "", "controller_basis": "NOT_ESTABLISHED_BY_THIS_SUPPLEMENT; administrative evidence does not set a simulation/war controller",
               "valid_from": DATE, "valid_to": EVIDENCE_WINDOW_END, "target_date": DATE,
               "validity_basis": "Bounded 1900 map evidence window, not a claim that this authority dissolves on the exclusive end date",
               "source": source, "source_date": source_date, "confidence": confidence,
               "is_runtime_polity": False, "runtime_entity_id": "", "flag_id": visual,
               "flag_mode": "controller_identification_flag", "capital": {"name": historical_centers.get(feature_id, ""), "lon": capital[0], "lat": capital[1]}}
        if feature_id.startswith("gw_"):
            row.update({"source_geometry_date": "1900-03-12", "source_record_valid_from": "1900-01-29",
                        "predecessor_assignment_window": {"from": DATE, "to_exclusive": "1900-01-29"},
                        "geometry_basis": "NEARBY_DATE", "geometry_confidence": "APPROXIMATE_FOR_1900_01_01",
                        "later_source_historical_id": "cshapes_" + feature_id})
        assignments.append(row)
        catalog["territories"][source_id] = {"visual_ids": [visual] if visual in catalog["records"] else [],
                                              "historical_national_flag": "NOT_ASSERTED", "authority_type": kind,
                                              "authority_source": source, "fallback_color": "#b48a46" if not visual else "#6b8075",
                                              "evidence_note": relation + "; representative asset does not define sovereignty."}
    authority_path = BASE / "historical_authorities_1900.json"
    write(authority_path, {"schema_version": 1, "target_date": DATE,
                          "scope": "Historical map administrative authority assignments only; does not add simulation countries, economies, populations or save entities.",
                          "assignments": assignments})
    write(catalog_path, catalog)
    registry_path = ROOT / "data/world_map/territory_source_registry.json"
    registry = read(registry_path)
    snapshot_id = "territory_source:arabia_gulf_1900_bounded_supplement"
    registry["sources"] = [r for r in registry["sources"] if r["source_snapshot_id"] != snapshot_id] + [{
        "source_snapshot_id": snapshot_id, "dataset_name": "WWO Arabia/Gulf bounded historical supplement", "dataset_version": "M2.6-v1",
        "provider": "WWO interpretation of Zwemer 1900, clipped against unchanged CShapes", "source_page": traces["source"],
        "download_url": "", "local_resource_path": "res://data/world_map/historical/arabia_gulf_geography_1900.json",
        "source_sha256": "", "snapshot_date": DATE, "valid_from": DATE, "valid_to": DATE,
        "geometry_scope": "Arabian Peninsula missing geography; bounded historical map interpretation", "geometry_granularity": "approximate_historical_regions",
        "feature_count": len(features), "coordinate_reference_system": "EPSG:4326", "derivation_kind": "DERIVED_SNAPSHOT",
        "parent_source_snapshot_ids": ["territory_source:cshapes_2_0_1900_03_12"], "derivation_method": traces["method"],
        "derivation_parameters": {"trace_path": output["source"]["trace_path"], "trace_schema_version": output["source"]["trace_schema_version"],
                                  "source_assets": output["source"]["source_assets"], "preserve_existing_geometry": True},
        "historical_target_date": DATE, "historical_fit_status": "QUALIFIED", "geography_confidence": "APPROXIMATE",
        "geography_basis": "BOUNDED_HISTORICAL_MAP", "source_date": "1900", "license_id": "CC-BY-NC-SA-4.0",
        "license_url": "https://creativecommons.org/licenses/by-nc-sa/4.0/", "redistribution_allowed": True,
        "derivative_work_allowed": True, "commercial_use_allowed": False, "share_alike_required": True, "attribution_required": True,
        "prototype_only": False, "production_admission_status": "REFERENCE_ONLY", "production_admission_reason": "LICENSE_NONCOMMERCIAL",
        "formal_map_admission": "ADMITTED_APPROXIMATE_HISTORICAL_GEOGRAPHY; provenance content hash bound",
    }]
    write(registry_path, registry)
    print(json.dumps({"supplement_features": len(features), "supplement_exteriors": output["exterior_count"], "authority_assignments": len(assignments)}))


if __name__ == "__main__":
    main()
