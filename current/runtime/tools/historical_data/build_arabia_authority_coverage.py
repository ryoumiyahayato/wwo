"""Preserve local evidence and aggregate the world's macro political display.

No geography output, new exterior, nearest-country rule or modern boundary input.
Masks are political evidence only; display uses the existing mesh resolution.
"""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "data/world_map/historical"
FEATURE = "arabia_undelimited_desert_1900"
SUBJECT = "arabia_authority_coverage_1900_01_01"
BOOK = "https://www.gutenberg.org/cache/epub/63928/pg63928-images.html"
HARB = "https://qdl.qa/en/archive/81055/vdc_100023514406.0x00003a"
DHAFRAH = "https://www.qdl.qa/en/archive/81055/vdc_100023515713.0x00003d"
MURRAH = "https://www.qdl.qa/en/archive/81055/vdc_100023526379.0x000047"
JANABAH = "https://www.qdl.qa/en/archive/81055/vdc_100000000831.0x00024d"
RASHIDI = "map_authority:arabia_rashidi_1900"
HEJAZ = "map_display:hejaz_1900"
HASA = "map_display:hasa_1900"
YEMEN = "map_display:yemen_1900"
HADRAMAUT = "map_display:hadramaut_1900"
MAHRA = "map_authority:arabia_mahra_1900"
OMAN = "sultanate_of_muscat_oman"
GULF = "trucial_states"
QUAITI_SOURCE = "https://commons.wikimedia.org/wiki/File:Flag_of_Qu%27aiti_State_in_Hadhramaut_(1880-1939).svg"


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def write(path, value):
    path.write_bytes((json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8"))


def rect(west, south, east, north):
    return [[west, south], [east, south], [east, north], [west, north]]


def main():
    geography_path = BASE / "arabia_gulf_geography_1900.json"
    geography = read(geography_path)
    if geography["schema_version"] != 1:
        raise ValueError("Unsupported geography schema")
    feature = next(row for row in geography["features"] if row["id"] == FEATURE)
    exterior_count = len(feature["geometry"]["coordinates"])
    # Priority is explicit: coastal administration and bounded named tribal
    # influence precede wider local-authority aggregates. These are approximate
    # influence envelopes, not sovereign borders or a distance-based partition.
    specs = [
        ("hejaz_coast", "汉志沿海行政", "LOCAL_DYNASTIC_AUTHORITY", [0,1,2], [rect(34,19,44,31)], "Sharifian/local coastal administration with Ottoman provincial presence; no new independent Hejaz state", BOOK+"#Page_206", "1900", .7, "ottoman_1844", [36.7,25.7]),
        ("tihama", "帖哈麦地方部落", "LOCAL_TRIBAL_AUTHORITY", [2], [rect(38,12,44,19)], "Coastal Bni Meruan and local sheikhs; Ottoman port/garrison claims overlap, not exclusive sovereign control", BOOK+"#Page_213", "1892 events / 1900 account", .55, "", [42.3,16.9]),
        ("mahra_fringe", "马赫拉地方行政边缘", "SULTANATE", [4], [], "Mahra local ruler/protection relation; approximate fringe, not annexation", "https://qdl.qa/en/archive/81055/vdc_100023462215.0x00000b", "1886 treaty / 1933 compilation", .6, "uk_union_1801", [52.1,15.8]),
        ("janabah", "贾纳巴地方部落", "LOCAL_TRIBAL_AUTHORITY", [5,6], [], "Janabah local control; 1898 rebellion documents limits of Muscat's authority at Sur; no unconditional Sultan sovereignty inferred", JANABAH, "1898", .65, "", [58.05,20.4]),
        ("omani_hajar", "阿曼哈杰尔地方谢赫", "LOCAL_TRIBAL_AUTHORITY", [7], [], "Omani hereditary local sheikhs and tribal allegiances; nominal Muscat relations do not mean uniform direct administration", BOOK+"#Page_78", "1900", .6, "", [57.0,24.6]),
        ("qasimi", "卡西米沿海地方行政", "LOCAL_DYNASTIC_AUTHORITY", [8], [], "Qasimi coastal authority/trucial relationship around Ras-al-Khaimah; disputed mountain fringe remains approximate", "https://rakheritage.rak.ae/chapters/the-beginnings-of-the-uae/", "1892 exclusive agreement; official retrospective history", .55, "", [55.81,25.73]),
        ("bani_yas", "巴尼亚斯／马纳西尔", "TRIBAL_CONFEDERATION", [9,10,11,3], [rect(51.3,22.0,56.1,25.3)], "Bani Yas local Al Bu Falah leadership and Manasir grazing/well communities; shared authority, not a modern UAE border", DHAFRAH, "1908; earlier Al Nahyan continuity corroborated by 1904 historical precis", .65, "", [53.6,23.7]),
        ("hasa_coast", "哈萨沿海行政", "APPROXIMATE_HISTORICAL_AUTHORITY", [12,13,14], [], "Ottoman Hasa coastal administration/ports after 1871, alongside local tribes; does not reassign all Gulf land", BOOK+"#Page_110", "1900 / observed journey", .7, "ottoman_1844", [49.2,27.7]),
        ("anazeh", "阿纳扎地方部落联盟", "TRIBAL_CONFEDERATION", [3], [[[34,27],[39.8,27],[43,29.3],[48,30.2],[48,35],[34,35]]], "Anaeze/Ruwalla seasonal local sheikhs in Syrian/northern Arabian desert; Ottoman and Rashidi tribute claims are distinct from direct control", BOOK+"#Page_154", "1900; nineteenth-century observations synthesized", .65, "", [40.5,32]),
        ("shammar_fringe", "沙马尔／拉希德影响区", "LOCAL_DYNASTIC_AUTHORITY", [3], [rect(39.8,26.5,48.5,31)], "Shammar/Rashidi tributary fringe; approximate influence, original Rashidi core geometry and assignment unchanged", BOOK+"#Page_154", "1900", .6, "rashidi_authority_1900", [43.8,29.5]),
        ("harb", "哈尔卜／朱海纳地方部落", "LOCAL_TRIBAL_AUTHORITY", [3], [[[34,20],[41.8,20],[42.8,23],[41,27.6],[34,28]]], "Harb/Juhaynah local tribal authority on Hejaz-Western Nejd fringe; 1917 handbook explicitly cites older Burton/Doughty, no 1916 kingdom projected backward", HARB, "1917 synthesis explicitly referencing nineteenth-century travelers", .55, "", [40.2,24.7]),
        ("dawasir", "达瓦西尔绿洲与部落", "LOCAL_TRIBAL_AUTHORITY", [3], [[[42.5,19],[47.5,19],[47.8,23],[44,24],[42.5,23]]], "Dawasir oasis/tribal sheikhs; named village/tribal ownership from Miles 1873 repeated by contemporary 1900 account, no unified modern state", BOOK+"#Footnote_44", "1873 observations / 1900 synthesis", .65, "", [45.1,20.5]),
        ("najran_asir", "奈季兰／阿西尔地方权威", "LOCAL_TRIBAL_AUTHORITY", [3], [rect(40,14,47.5,21)], "Local oasis/highland sheikhs and tribal military authority; contested Ottoman and Imam influence recorded separately, no later Idrisid state invented", BOOK+"#Page_145", "1870 journey / 1900 account", .55, "", [44.6,17.8]),
        ("murrah", "穆拉／哈杰尔地方部落", "LOCAL_TRIBAL_AUTHORITY", [3], [[[46.5,21.5],[51.5,21.5],[52.3,24.4],[49.5,27.2],[46.5,27.2]]], "Al Murrah/Bani Hajir wells, migration and military action in Hasa-Qatar hinterland; no assumption of exclusive Ottoman/British control", MURRAH, "1873-1904 historical precis; earlier events documented", .55, "", [49,23.3]),
        ("southern_local", "南阿拉伯地方谢赫与部落", "LOCAL_TRIBAL_AUTHORITY", [3], [rect(44,14,57,24.0)], "Independent local communities, Mahra/Gharah hinterland and western Oman sheikhs; map aggregate is not a unified confederation or sovereign polity. Seasonal/well/resource influence, exact reach unknown", BOOK+"#Page_143", "1900 contemporary synthesis", .4, "", [50.8,19.0]),
    ]
    assignments = []
    imperial_relations = {
        "hejaz_coast": "Sharifian local administration / Ottoman imperial framework",
        "tihama": "Ottoman provincial/port claims overlap independent local tribal control",
        "mahra_fringe": "Local sultan; British protection relationship, no annexation",
        "janabah": "Muscat claim contested by independent tribal action",
        "omani_hajar": "Nominal Muscat relations; hereditary local sheikhs; no 1913 imamate backdating",
        "qasimi": "Qasimi local administration; British maritime treaty relationship",
        "bani_yas": "Al Bu Falah local leadership under Zayed bin Khalifah; Manasir shared resource authority; British maritime truce",
        "hasa_coast": "Ottoman Hasa provincial framework alongside local sheikhs",
        "anazeh": "Independent local sheikhs; variable Ottoman/Rashidi tribute claims",
        "shammar_fringe": "Rashidi tributary influence; Ottoman alliance does not imply direct administration",
        "harb": "Local sheikhs; overlapping Sharifian/Rashidi relationships, no exclusive sovereignty inferred",
        "dawasir": "Local oasis/tribal authority; wider Najd influence does not imply direct exclusive control",
        "najran_asir": "Local sheikhs; contested Ottoman/Zaidi claims; no later Idrisid state backdating",
        "murrah": "Local tribal authority despite competing Hasa/Qatar external claims",
        "southern_local": "Several independent local communities; no unified sovereignty or exclusive imperial ownership asserted",
    }
    catalog_path = BASE / "political_visuals_1900.json"
    catalog = read(catalog_path)
    for key, name, kind, components, regions, basis, source, date, confidence, flag, center in specs:
        identity = "map_authority:arabia_coverage:" + key
        row = {"id": identity, "source_historical_id": identity, "geometry_feature_id": FEATURE,
               "geometry_component_indices": components, "authority_regions": regions,
               "name_zh": name, "short_name_zh": name, "label_rank": 3,
               "assignment_kind": "APPROXIMATE_HISTORICAL_AUTHORITY", "authority_type": kind,
               "administrator_id": key, "authority_confidence": confidence, "confidence": confidence,
               "sovereignty_imperial_relation": imperial_relations[key], "diplomacy_identity": "",
               "authority_basis": basis, "source": source, "source_date": date, "target_date": "1900-01-01", "approximate": True,
               "valid_from": "1900-01-01", "valid_to": "1901-01-01", "validity_basis": "Bounded 1900 evidence window, not authority dissolution",
               "controller_id": "", "controller_basis": "No simulation/war controller inferred", "is_runtime_polity": False, "runtime_entity_id": "",
               "flag_id": flag, "flag_mode": "controller_identification_flag", "label_anchor": {"lon": center[0], "lat": center[1]}}
        assignments.append(row)
        # Retire the micro-authority palette from the world-map visual catalog.
        catalog["territories"].pop(identity, None)
    document = {"schema_version": 1, "target_date": "1900-01-01", "scope": "Political coverage only; no geometry, diplomacy, economy, population, controller or save entities",
        "geometry_binding": {"path": "res://data/world_map/historical/arabia_gulf_geography_1900.json", "schema_version": 1, "feature_id": FEATURE, "exterior_count": exterior_count},
        "method": "Ordered historical influence envelopes sampled at existing source triangle centroids; no added/split triangle, exterior or geographic boundary. Display edges reflect frozen mesh resolution, not surveyed political borders.",
        "unresolved_regions": [{"component_index": 3, "authority_region": rect(49.5,20.0,50.2,20.7), "decision": "TRULY_UNRESOLVED", "source": BOOK+"#Page_143", "source_date": "1900",
            "reason": "Small interior sand core between documented peripheral well/tribal influence envelopes. Contemporary account explicitly lacks local authority knowledge; later coastal/tribal sources do not establish a specific ruler for this core. It remains unknown, not declared a political vacuum."}],
        "assignments": assignments}
    # Display aggregation is separate from the retained local-authority claim.
    # It never asserts that autonomous tribes became directly governed provinces.
    macro_links = {
        "hejaz_coast": (HEJAZ, "LOCAL", .7), "tihama": (YEMEN, "NOMINAL", .5),
        "mahra_fringe": (MAHRA, "LOCAL", .6), "janabah": (OMAN, "AUTONOMOUS", .55),
        "omani_hajar": (OMAN, "NOMINAL", .6), "qasimi": (GULF, "LOCAL", .65),
        "bani_yas": (GULF, "LOCAL", .65), "hasa_coast": (HASA, "LOCAL", .7),
        "anazeh": (RASHIDI, "AUTONOMOUS", .4), "shammar_fringe": (RASHIDI, "TRIBUTARY", .6),
        "harb": (HEJAZ, "AUTONOMOUS", .5), "dawasir": (RASHIDI, "AUTONOMOUS", .5),
        "najran_asir": (YEMEN, "NOMINAL", .4), "murrah": (HASA, "AUTONOMOUS", .45),
        "southern_local": (RASHIDI, "AUTONOMOUS", .25),
    }
    for row in assignments:
        key = row["administrator_id"]
        target, status, confidence = macro_links[key]
        row.update(map_display_authority_id=target, map_assignment="APPROXIMATE", authority_status=status,
                   map_confidence=confidence, map_assignment_basis="Macro presentation aggregation; local control and imperial claims remain separate. " + row["sovereignty_imperial_relation"])
        if key in ["anazeh", "dawasir", "shammar_fringe", "southern_local"]:
            row["map_assignment_source"] = BOOK + "#Page_200"
            row["map_assignment_basis"] += " Contemporary central-Arabia Rashidi predominance; peripheral reach is approximate, not exclusive sovereignty."
        if key == "southern_local":
            row["map_display_regions"] = [
                {"region": rect(52.2,19,57,24), "map_display_authority_id": OMAN, "authority_status": "NOMINAL", "confidence": .35, "basis": "Western Oman hinterland, within the retained contemporary local-sheikh description"},
                {"region": rect(51,14,57,19), "map_display_authority_id": MAHRA, "authority_status": "AUTONOMOUS", "confidence": .35, "basis": "Mahra/Gharah southern hinterland; loose influence, not surveyed Sultanate border"},
                {"region": rect(44,14,51,19), "map_display_authority_id": HADRAMAUT, "authority_status": "AUTONOMOUS", "confidence": .35, "basis": "Hadramaut sultanates' inland regional grouping; no unified government or blanket British sovereignty"},
            ]
    # The historical unknown remains unknown locally, but is no longer a grey
    # display hole. Its macro association is explicitly the weakest inference.
    document["unresolved_regions"][0].update(map_display_authority_id=RASHIDI, map_assignment="APPROXIMATE", authority_status="LOCAL", confidence=.25, approximate=True,
        map_assignment_basis="Low-confidence central-interior macro association, not discovery of a local ruler or taxation/control evidence")
    display_specs = [
        (HEJAZ, "汉志／奥斯曼关联行政", "ottoman_1844", [39.5,24.3], BOOK+"#Page_206"),
        (HASA, "哈萨／奥斯曼行政", "ottoman_1844", [49.6,26.7], BOOK+"#Page_110"),
        (YEMEN, "也门／奥斯曼关联行政", "ottoman_1844", [43.6,17.6], BOOK+"#Page_213"),
        (HADRAMAUT, "哈德拉毛地方苏丹国", "hadramaut_quaiti_livery_1900", [49.2,16.1], BOOK+"#Page_72"),
    ]
    document["map_display_records"] = [
        {"id": identity, "source_historical_id": identity, "geometry_feature_id": "arabia_kathiri_1900" if identity == HADRAMAUT else FEATURE,
         "display_only": True, "name_zh": name, "short_name_zh": name, "label_rank": 3,
         "flag_id": flag, "flag_mode": "controller_identification_flag", "label_anchor": {"lon": center[0], "lat": center[1]},
         "is_runtime_polity": False, "runtime_entity_id": "", "authority_type": "MACRO_DISPLAY_AGGREGATE",
         "valid_from": "1900-01-01", "valid_to": "1901-01-01", "source": source,
         "target_date": "1900-01-01", "approximate": True,
         "evidence_note": "Display identity only; not a sovereignty, administration or simulation entity"}
        for identity, name, flag, center, source in display_specs]
    document["map_display_bindings"] = {"map_authority:arabia_kathiri_1900": HADRAMAUT, "map_authority:arabia_quaiti_1900": HADRAMAUT}
    document["method"] = "Retain local historical influence envelopes. World Political Map consumes only final macro display authority; existing source faces are neither split nor added. Macro grouping is approximate and does not overwrite local authority, sovereignty or controller."
    asset_path = ROOT / "assets/historical_liveries/1900/quaiti_1880.svg"
    catalog["records"]["hadramaut_quaiti_livery_1900"] = {
        "id": "hadramaut_quaiti_livery_1900", "visual_kind": "AUTHORITY_LIVERY", "display_role": "APPROXIMATE_HISTORICAL_VISUAL", "priority_role": "LOCAL_OFFICIAL_FLAG",
        "valid_from": "1900-01-01", "valid_to": "1901-01-01", "asset_path": "res://assets/historical_liveries/1900/quaiti_1880.svg",
        "asset_sha256": hashlib.sha256(asset_path.read_bytes()).hexdigest(), "source_page": QUAITI_SOURCE,
        "source_asset": "https://upload.wikimedia.org/wikipedia/commons/b/b2/Flag_of_Qu%27aiti_State_in_Hadhramaut_%281880-1939%29.svg",
        "source_artist": "Dekodrak; Andel", "license": "Public domain (PD-shape)", "source_date": "1880-1939 design / 2019 reconstruction",
        "confidence": "medium_low", "historical_national_flag": "NOT_ASSERTED", "historical_design_claim": False,
        "evidence_note": "Full red/white Quaiti historical flag reconstruction used as an approximate regional Hadramaut livery. Not a Kathiri national flag, unified Hadramaut state, or assertion of 1900 British protection over Kathiri. No 1939 emblem flag used."}
    for row in document["map_display_records"]:
        catalog["territories"][row["id"]] = {"visual_ids": [row["flag_id"]] if row["flag_id"] in catalog["records"] else [],
            "historical_national_flag": "NOT_ASSERTED", "map_assignment": "APPROXIMATE", "display_only": True,
            "evidence_note": row["evidence_note"]}
    locations = ["Aqaba coastal fringe", "Yanbu / northern Hejaz coastal fringe", "Red Sea coast: Hejaz to Tihama",
        "Connected inland residual: Syrian desert, Najd fringe, Dawasir/Najran, southeastern tribal hinterland",
        "Eastern Mahra / Qishn-Nishtun fringe", "Masirah-facing Janabah coastal fringe", "Sur / Janabah coastal fringe",
        "Hajar / Batinah local tribal fringe", "Ras-al-Khaimah / Qasimi coastal fringe", "Abu Dhabi northeastern coastal remnant",
        "Abu Dhabi / Bani Yas coastal fringe", "Western Dhafrah / Bainunah fringe", "Small Hasa coastal remnant",
        "Hasa / Qatif coastal fringe", "Northern Hasa / Jubail coastal fringe"]
    feature = next(f for f in read(geography_path)["features"] if f["id"] == FEATURE)
    document["exterior_decisions"] = []
    for index, part in enumerate(feature["geometry"]["coordinates"]):
        ring = part[0]
        linked = [r for r in assignments if index in r["geometry_component_indices"]]
        document["exterior_decisions"].append({"component_index": index, "location": locations[index],
            "lon_lat_bounds": [min(p[0] for p in ring),min(p[1] for p in ring),max(p[0] for p in ring),max(p[1] for p in ring)],
            "old_status": "GEOGRAPHY_PRESENT_NO_POLITY", "decision": "APPROXIMATE_AUTHORITY_ASSIGNED",
            "authority_ids": [r["id"] for r in linked], "partial_unresolved": index == 3,
            "confidence_range": [min(r["authority_confidence"] for r in linked),max(r["authority_confidence"] for r in linked)],
            "sources": list(dict.fromkeys(r["source"] for r in linked))})
    path = BASE / "arabia_authority_coverage_1900.json"
    write(path, document)
    write(catalog_path, catalog)
    print(json.dumps({"coverage_assignments": len(assignments), "geometry_written": False}))


if __name__ == "__main__":
    main()
