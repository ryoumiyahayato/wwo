"""Bounded offline OS / RISTAT references and sourced island-to-polity links.

No world facts, generated land, population or economic data are produced.
Raw downloads and Python dependencies remain in local-artifacts.
"""
from pathlib import Path
import json
import html
import re
import sqlite3
import sys
import csv
import argparse
from collections import defaultdict

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "local-artifacts/historical-islands-admin-r5"
sys.path[:0] = [str(RAW / "python-libs"), str(ROOT / "local-artifacts/local-landscape-r4/python-libs")]
import shapefile
from pyproj import Transformer, Geod
from shapely import wkb
from shapely.geometry import shape, mapping
from shapely.geometry import Polygon, MultiPolygon, LineString, box
from shapely.ops import transform
from shapely.ops import unary_union, polygonize_full
from shapely.strtree import STRtree
import xml.etree.ElementTree as ET

OUT = ROOT / "data/world_map/historical"
PROJ = Transformer.from_crs(4326, 2154, always_xy=True)
FROM_OS = Transformer.from_crs(27700, 4326, always_xy=True)
GEOD = Geod(ellps="WGS84")


def read(p): return json.loads(p.read_text(encoding="utf-8"))


def write(p, value):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")


def polygons(g):
    if g.geom_type == "Polygon": return [g]
    return [p for c in g.geoms for p in polygons(c)] if hasattr(g, "geoms") else []


def local_xy(x, y, z=None):
    a, b = PROJ.transform(x, y)
    try: return [v - 648000 for v in a], [v - 6862000 for v in b]
    except TypeError: return a - 648000, b - 6862000


def rings_value(g):
    return [[[round(x, 2), round(y, 2)] for x, y in r.coords[:-1]] for r in [g.exterior, *g.interiors]]


def emit_reference(key, source_id, source, records, year, note):
    identities, descriptors = [], []
    folder = OUT / (key + "_boundaries")
    for row, geo in records:
        ident = row["id"]
        reference_year = int(row.get("observation_year",year))
        local = transform(local_xy, geo)
        if local.is_empty: continue
        paths = {}
        for lod, tolerance in [("coarse", 1000.0), ("detail", 65.0)]:
            # Display simplification only; the source geometry is kept offline.
            reduced = local.simplify(tolerance, preserve_topology=True)
            path = folder / (ident.split(":")[1] + "_" + lod + ".json")
            write(path, {"schema_id": "historical_administrative_reference_geometry_v1", "id": ident,
                         "source_unit_id": row["source_unit_id"], "observation_year": reference_year, "lod": lod,
                         "local_polygons": [rings_value(p) for p in polygons(reduced)]})
            paths[lod + "_path"] = "res://" + path.relative_to(ROOT).as_posix()
        b, ll = local.bounds, geo.bounds
        descriptor = {"id": ident, "source_unit_id": row["source_unit_id"], "source_area_km2": abs(GEOD.geometry_area_perimeter(geo)[0]) / 1e6,
                      "local_bounds": [b[0], b[1], b[2] - b[0], b[3] - b[1]], "bounds": [ll[0], ll[2], ll[1], ll[3]],
                      "observation_year": reference_year, "reference_display_from": "1900-01-01", "valid_from": str(reference_year)+"-01-01",
                      "valid_to": str(reference_year+1)+"-01-01", "level": row["level"], **paths}
        row.update(boundary_reference_status="HISTORICAL_GIS_RECONSTRUCTION", boundary_note_zh=note,
                   source_citation=source["attribution"], source_license=source["license"],
                   source_name_zh=source["publisher"], observation_year=reference_year,
                   historical_source_name=row["historical_name"], membership_basis_zh="历史参考范围；此处未建立正式土地成员。")
        row.setdefault("boundary_reference",source["locator"])
        row.setdefault("temporal_note_zh",note)
        row.setdefault("accuracy_note_zh",row.get("coordinate_note_zh","后期 GIS 重建；粗／细轮廓仅作显示概化，不增加原资料的测绘精度。"))
        identities.append(row); descriptors.append(descriptor)
    index_path = OUT / (key + "_index.json")
    write(index_path, {"schema_id": "historical_administrative_reference_index_v1", "entity_id": source_id, "source": source,
                       "observation_year": year, "projection": "EPSG:2154 minus [648000,6862000]; existing display coordinates only",
                       "temporal_note_zh": note, "features": descriptors})
    write(OUT / (key + "_identity.json"), {"schema_id": "historical_administrative_reference_identity_v1", "entity_id": source_id,
        "valid_from": "1900-01-01", "valid_to": "1901-01-01", "geometry_status": "HISTORICAL_GIS_RECONSTRUCTION",
        "source_basis": note, "source": source, "boundary_path": "res://"+index_path.relative_to(ROOT).as_posix(), "units": identities})
    return len(identities)


def france_lower():
    """Keep the admitted départements and their land correspondence untouched."""
    p = RAW / "trf_lower"
    source = {"publisher": "Victor Gay / TSE / IAST · TRF-GIS", "author": "Victor Gay", "year": 1900,
              "source_id": "trf_gis_lower_1900", "locator": "https://doi.org/10.7910/DVN/98ERPB",
              "supporting_locators": ["https://doi.org/10.7910/DVN/U85RSZ", "https://doi.org/10.7910/DVN/LZTZWE"],
              "license": "CC BY 4.0", "license_url": "https://creativecommons.org/licenses/by/4.0/",
              "attribution": "Gay, Victor (2021), Mapping the Third Republic, Historical Methods 54(4), 189–207. TRF-GIS v2.0. WWO: annual selection, coordinate conversion and display simplification.",
              "original_crs": "EPSG:2154", "reconstruction": True}
    deps = {int(x["source_dep_id"]): x["id"] for x in read(OUT / "france_department_boundaries_1900.json")["features"]}
    to_geo = Transformer.from_crs(2154, 4326, always_xy=True)
    def table(name):
        return list(csv.DictReader((p / name).open(encoding="latin1", newline="")))
    arr = {int(x["depar"]): x for x in table("COG_ARRONDISSEMENTS_1900.txt")}
    cantons = {int(x["depct"]): x for x in table("COG_CANTONS_1900.txt")}
    mapping_rows = list(csv.DictReader((p / "COG_CANTONS_1900_MAPPING.tab").open(encoding="utf-8"), delimiter="\t"))
    aggregate_members = defaultdict(list)
    for x in mapping_rows: aggregate_members[int(x["deppct"])].append(int(x["depct"]))
    units, geometry = {}, {}
    def identity(code, raw, kind, level, parent, name, label):
        row = {"id": "administrative_region:france_"+kind+"_"+str(code), "source_unit_id": str(code),
               "polity_id": "state:country_fra", "historical_name": name, "name_zh": name,
               "unit_type": kind, "unit_type_name_zh": label, "level": level,
               "parent_region_id": parent, "valid_from": "1900-01-01", "valid_to": "1901-01-01",
               "date_basis": "Annual reference, not independently verified legal establishment/abolition dates",
               "capital_name": raw.get("cl_name_prop", raw.get("cl_name", "未记录")), "observation_year": 1900}
        if raw.get("cl_x") and raw.get("cl_y"):
            row["capital_lon_lat"] = list(to_geo.transform(float(raw["cl_x"]), float(raw["cl_y"])))
        return row
    for code, raw in arr.items():
        units["a"+str(code)] = identity(code, raw, "arrondissement", 2, deps[int(raw["dep"])], raw["ar_name_prop"], "Arrondissement · 区")
        units["a"+str(code)]["authority_type_name_zh"] = "区级副省长行政机关（sous-préfecture）；省会区另由省长处理"
    for code, raw in cantons.items():
        municipal = raw["dep"] == "75" and raw["ct_name"].startswith("PARIS-")
        units["c"+str(code)] = identity(code, raw, "canton", 3, units["a"+str(int(raw["depar"]))]["id"], raw["ct_name_prop"], "巴黎市辖区（源名录作为 canton）" if municipal else "Canton · 历史县区")
        units["c"+str(code)]["authority_type_name_zh"] = "巴黎市辖区行政机关" if municipal else "县区为司法／选举及地方行政框架，不是独立通用地方政府"
        if municipal:
            units["c"+str(code)].update(unit_type="paris_municipal_arrondissement",parent_region_id="administrative_region:france_commune_cassini_26207",level=4,
                classification_note_zh="巴黎市辖区属于巴黎市镇；TRF-GIS 县名录与市镇名录中的重复编码合并为同一身份。")
    for family, field in [("ARRONDISSEMENTS", "depar"), ("CANTONS", "deppct")]:
        reader = shapefile.Reader(str(next((p / family).glob("**/*.shp"))))
        for item in reader.iterShapeRecords():
            raw = item.record.as_dict(); code = int(raw[field])
            key = ("a" if family == "ARRONDISSEMENTS" else "c")+str(code)
            if key not in units:
                # A source pseudo-canton is a geometry aggregation, never a legal canton.
                related = aggregate_members.get(code, [])
                row = identity(code, raw, "canton_geometry_aggregate", 3, units["a"+str(raw["depar"])]["id"], raw["pct_name"].title(), "多个县区的合并空间参考")
                row["is_administrative_unit"] = False
                row["related_region_ids"] = [units["c"+str(i)]["id"] for i in related if "c"+str(i) in units]
                row["classification_note_zh"] = "TRF-GIS 伪县：保留合并范围，不将内部实际县区画成同一独立行政单位。"
                units[key] = row
                for i in related:
                    if "c"+str(i) in units: units["c"+str(i)]["boundary_aggregate_id"] = row["id"]
            geometry[key] = transform(to_geo.transform, shape(item.shape.__geo_interface__))
    note = "1900 年年度历史 GIS 重建；省—区—县引用来自原名录。合并县区只显示联合范围，不伪造内部界线。"
    geometries = [(units[k], g) for k, g in geometry.items()]
    paris_units=[geometry[k] for k in geometry if units[k].get("unit_type")=="paris_municipal_arrondissement"]
    if len(paris_units)==20:
        paris={"id":"administrative_region:france_commune_cassini_26207","source_unit_id":"26207","source_insee_id":"75056","historical_name":"Paris","name_zh":"Paris",
            "polity_id":"state:country_fra","unit_type":"commune_nomenclature_reference","unit_type_name_zh":"Paris · 巴黎市镇","level":3,
            "parent_region_id":units["a751"]["id"],"source_arrondissement_id":units["a751"]["id"],"observation_year":1900,"capital_name":"Paris","capital_place_id":"place:paris",
            "authority_type_name_zh":"巴黎特殊制度：省长与各市辖区机关；不套用普通市长制度","classification_note_zh":"范围合成自 TRF-GIS 的 20 个巴黎市辖区，不从游戏土地格网推导。仍受源 GIS 重建精度限制。"}
        geometries.append((paris,unary_union(paris_units)))
    emit_reference("france_lower_1900", "country_fra", source, geometries, 1900, note)
    doc = read(OUT / "france_lower_1900_identity.json")
    by_id = {x["id"]: x for x in doc["units"]}
    for row in units.values():
        if row["id"] not in by_id:
            row.update(boundary_reference_status="NO_INDIVIDUAL_BOUNDARY", source_citation=source["attribution"],
                       source_license=source["license"], source_name_zh=source["publisher"], temporal_note_zh=note)
            doc["units"].append(row); by_id[row["id"]] = row
    children = defaultdict(list)
    # Commune identities are sharded by their explicit source parent. No commune geometry is inferred.
    communes = table("COG_COMMUNES_1900.txt")
    for raw in communes:
        pct = int(raw["deppct"])
        if "c"+str(pct) in units and units["c"+str(pct)].get("unit_type")=="paris_municipal_arrondissement":
            unit_id=units["c"+str(pct)]["id"]
            by_id[unit_id].update(source_cassini_id=raw["cassini"],source_insee_id=raw["insee"])
            continue
        parent = units["c"+str(pct)]["id"] if "c"+str(pct) in units and units["c"+str(pct)].get("is_administrative_unit", True) else units["a"+str(int(raw["depar"]))]["id"]
        row = {"id": "administrative_region:france_commune_cassini_"+raw["cassini"], "source_unit_id": raw["cassini"],
               "source_insee_id": raw["insee"], "historical_name": raw["com_name_prop"], "name_zh": raw["com_name_prop"],
               "polity_id": "state:country_fra", "unit_type": "commune_nomenclature_reference", "unit_type_name_zh": "Commune · 市镇名录参考",
               "level": 4, "parent_region_id": parent, "source_arrondissement_id": units["a"+str(int(raw["depar"]))]["id"],
               "observation_year": 1900, "capital_name": "未记录", "boundary_reference_status": "NO_INDIVIDUAL_BOUNDARY",
               "temporal_note_zh": "TRF-GIS 年度市镇对应名录；包含当代市镇与已合并市镇引用，不提供精确的 1900 市镇边界或全部法定沿革。",
               "authority_type_name_zh": "市镇地方行政机关；巴黎等特殊制度须另核具体机关",
               "source_commune_code_type": raw["com_act"]}
        if pct in aggregate_members:
            row["related_region_ids"] = [units["c"+str(i)]["id"] for i in aggregate_members[pct] if "c"+str(i) in units]
        if raw["cassini"]=="26207":
            row.update(level=3,unit_type_name_zh="Paris · 巴黎市镇",authority_type_name_zh="巴黎特殊制度：省长与各市辖区机关；不套用普通市长制度")
            if row["id"] not in by_id:doc["units"].append(row);by_id[row["id"]]=row
            continue
        children[parent].append(row)
    active_shards=set()
    for parent, rows in children.items():
        path = OUT / "france_communes_1900" / (parent.split(":")[1]+".json")
        active_shards.add(path.resolve())
        write(path, {"schema_id": "historical_administrative_children_v1", "parent_region_id": parent, "source": source, "units": rows})
        by_id[parent]["children_path"] = "res://"+path.relative_to(ROOT).as_posix()
        by_id[parent]["catalog_child_count"] = len(rows)
    for path in (OUT/"france_communes_1900").glob("*.json"):
        if path.resolve() not in active_shards:path.unlink()
    doc["source"]["commune_count"] = len(communes)
    doc["source"]["commune_geometry_count"] = 0
    write(OUT / "france_lower_1900_identity.json", doc)
    return {"arrondissements": len(arr), "cantons": len(cantons)-20,"paris_municipal_arrondissements":20, "geometry_aggregates": len(units)-len(arr)-len(cantons), "contours": len(geometries), "commune_references": len(communes)-20}


def uk():
    source = {"publisher": "Ordnance Survey / DCLG", "source_id": "os_historic_counties_c1888", "year": "c.1888 / 1890; Scottish alignment from 1940 mapping",
              "locator": "https://docs.os.uk/os-downloads/products/areas-and-zones-portfolio/boundary-line/boundary-line-downloads",
              "license": "Open Government Licence v3.0", "attribution": "Contains OS data © Crown copyright and database right 2026. Ordnance Survey Historic County Boundaries.",
              "original_file": "boundary-line-historic-counties-shape.zip", "original_crs": "EPSG:27700", "reconstruction": True}
    r = shapefile.Reader(str(next((RAW / "os_historic").glob("*.shp"))))
    note = "约 1888—1890 年历史郡界重建参考，非 1900 年完整法定行政郡；苏格兰线位使用 1940 年图。爱尔兰不在本文件范围。"
    rename = {"Angus": "Forfarshire", "East Lothian": "Haddingtonshire", "West Lothian": "Linlithgowshire", "Shetland": "Zetland (Shetland)"}
    towns = {"Dundee", "Aberdeen", "Glasgow", "Edinburgh"}
    rows = []
    for rec in r.iterShapeRecords():
        fields = rec.record.as_dict(); name = fields["NAME"]; hist = rename.get(name, name)
        kind = "historic_city_county_reference" if name in towns else "historic_county_reference"
        row = {"id": "administrative_region:gb_historic_"+re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_"),
               "source_unit_id": name, "polity_id": "state:british_isles_1900", "historical_name": hist, "name_zh": hist,
               "source_original_name": name, "unit_type": kind, "unit_type_name_zh": "历史城市郡参考" if name in towns else "历史郡参考",
               "level": 1, "parent_region_id": None, "capital_name": "未记录"}
        rows.append((row, transform(FROM_OS.transform, shape(rec.shape.__geo_interface__))))
    count = emit_reference("britain_historic_counties", "british_isles_1900", source, rows, 1888, note)
    path = OUT / "britain_historic_counties_identity.json"
    document = read(path)
    roster = (RAW / "ireland_census_search.html").read_text(encoding="utf-8")
    county_select = re.search(r'<select id="county"[^>]*>(.*?)</select>', roster, re.S).group(1)
    for name in re.findall(r'<option>(.*?)</option>', county_select, re.S):
        name = html.unescape(name).strip()
        document["units"].append({"id": "administrative_region:ireland_census_"+re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_"),
            "source_unit_id": name, "polity_id": "state:british_isles_1900", "historical_name": name, "name_zh": name,
            "unit_type": "historic_county_identity_reference", "unit_type_name_zh": "爱尔兰历史郡名录参考", "level": 1,
            "parent_region_id": None, "capital_name": "未记录", "observation_year": 1901,
            "temporal_note_zh": "1901 年近期开局郡名录参考；未取得可分发的适用郡界。不是 1900 年完整法定行政郡界。",
            "source_name_zh": "爱尔兰国家档案馆", "source_citation": "National Archives of Ireland, Census 1901 county index; factual names only, no census returns or personal records reproduced.",
            "source_license": "Factual names extracted and attributed; source records not redistributed",
            "accuracy_note_zh": "仅提取郡名；没有可用于测绘的几何。",
            "boundary_reference": "https://nationalarchives.ie/collections/search-the-census/", "boundary_reference_status": "IDENTITY_ONLY_NO_GEOMETRY"})
    document["units"].append({"id": "administrative_region:gb_county_of_london", "source_unit_id": "County of London", "polity_id": "state:british_isles_1900",
        "historical_name": "County of London", "name_zh": "伦敦行政郡", "unit_type": "administrative_county", "unit_type_name_zh": "Administrative county · 行政郡", "level": 1,
        "parent_region_id": None, "capital_name": "London", "capital_place_id": "place:london", "observation_year": 1889,
        "temporal_note_zh": "1889 年成立的伦敦行政郡；当前 OS 文件是历史郡参考，未提供该法定行政郡的适用几何。",
        "source_name_zh": "Ordnance Survey / DCLG", "source_citation": "OS Historic County Boundaries documentation, list of administrative counties created in 1889.",
        "accuracy_note_zh": "仅有名称与类型依据；不将历史郡参考线当作法定伦敦行政郡界。",
        "source_license": source["license"], "boundary_reference": source["locator"], "boundary_reference_status": "IDENTITY_ONLY_NO_GEOMETRY"})
    write(path, document)
    return count, len(document["units"])-count


def uk_hierarchy():
    key = "britain_historic_counties"
    doc = read(OUT/(key+"_identity.json")); index = read(OUT/(key+"_index.json"))
    original = {x["id"]:x for x in doc["units"]}
    index["features"]=[x for x in index["features"] if "_additions_boundaries/" not in x["coarse_path"] and "_constituents_boundaries/" not in x["coarse_path"]]
    scot = set("Peebleshire,Caithness,Shetland,Orkney,Dundee,Banffshire,Nairn,Aberdeenshire,Aberdeen,Angus,Kinross-shire,Clackmannanshire,Perthshire,Stirlingshire,Selkirkshire,Roxburghshire,Midlothian,Berwickshire,Dumfriesshire,Kirkcudbrightshire,Glasgow,Renfrewshire,Lanarkshire,Kincardineshire,Fife,West Lothian,Edinburgh,East Lothian,Wigtownshire,Sutherland,Inverness-shire,Ross and Cromarty,Ayrshire,Argyllshire,Buteshire,Dunbartonshire".split(","))
    wales = set("Pembrokeshire,Cardiganshire,Carmarthenshire,Brecknockshire,Radnorshire,Montgomeryshire,Merionethshire,Anglesey,Glamorgan,Denbighshire,Flintshire,Carnarvonshire".split(","))
    def rid(country): return "administrative_region:uk_constituent_"+country
    country_shapes = defaultdict(list); english_names=[]; welsh_names=[]
    for item in shapefile.Reader(str(next((RAW/"os_historic").glob("*.shp")))).iterShapeRecords():
        name=item.record.as_dict()["NAME"]; country="scotland" if name in scot else "wales" if name in wales else "england"
        ident="administrative_region:gb_historic_"+re.sub(r"[^a-z0-9]+","_",name.lower()).strip("_")
        original[ident].update(parent_region_id=rid(country),level=2,display_max_mpp=3500,
            authority_type_name_zh="历史地理郡参考；不将其自动等同于行政郡议会辖区")
        if name=="Monmouthshire":original[ident]["classification_note_zh"]="本层按当时英格兰地方政府法规口径关联；不套用现代威尔士行政边界。"
        country_shapes[country].append(transform(FROM_OS.transform,shape(item.shape.__geo_interface__)))
        if country=="england":english_names.append(name)
        elif country=="wales":welsh_names.append(name)
    trust={"publisher":"Historic Counties Trust / Historic County Borders Project","author":"Historic Counties Trust","source_id":"historic_counties_trust_definition_a",
        "year":"Retrospective Historic Counties Standard","locator":"https://www.county-borders.co.uk/","license":"Freely available for public and commercial use; retain attribution",
        "attribution":"Historic Counties Trust, Historic County Borders Project, Definition A. WWO: selected components, reprojection and display simplification.",
        "original_file":"UKDefinitionA_WG84_Simplified.zip","original_crs":"EPSG:4326","reconstruction":True}
    added=[]
    for item in shapefile.Reader(str(next((RAW/"uk_trust").glob("**/*.shp")))).iterShapeRecords():
        name=item.record.as_dict()["NAME"]
        if name in {"Antrim","Armagh","Down","Fermanagh","Londonderry","Tyrone"}:
            row=original["administrative_region:ireland_census_"+name.lower()]
            row.update(parent_region_id=rid("ireland"),level=2,display_max_mpp=3500,unit_type_name_zh="爱尔兰历史郡参考（非完整行政郡辖界）")
            added.append((row,shape(item.shape.__geo_interface__)))
        elif name in {"Morayshire","Cromartyshire","Ross-shire"}:
            row={"id":"administrative_region:gb_historic_"+re.sub(r"[^a-z0-9]+","_",name.lower()),"source_unit_id":name,"name_zh":name,"historical_name":name,
                "polity_id":"state:british_isles_1900","unit_type":"historic_county_reference","unit_type_name_zh":"苏格兰历史郡参考","parent_region_id":rid("scotland"),"level":2,"display_max_mpp":3500,"capital_name":"未记录"}
            added.append((row,shape(item.shape.__geo_interface__)))
    ne=read(ROOT/"local-artifacts/paris-land-pilot-r1/research/ne_10m_land_v512.geojson")
    country_shapes["ireland"]=[x for f in ne["features"] for x in polygons(shape(f["geometry"])) if -11.0<x.bounds[0] and x.bounds[2]<-5.3 and 51.0<x.bounds[1] and x.bounds[3]<55.6]
    for row in original.values():
        if row["id"].startswith("administrative_region:ireland_census_"):row.update(parent_region_id=rid("ireland"),level=2)
    root_source={**trust,"source_id":"uk_historical_constituents_reference","year":1900,
        "license":"OS OGL v3.0; Historic Counties Trust public/commercial use; Natural Earth public domain",
        "attribution":trust["attribution"]+" Contains OS data © Crown copyright and database right 2026; Natural Earth contributors (public domain)."}
    roots=[]
    for country,zh in [("england","英格兰"),("wales","威尔士"),("scotland","苏格兰"),("ireland","爱尔兰")]:
        row={"id":rid(country),"source_unit_id":country,"polity_id":"state:british_isles_1900","historical_name":country.title(),"name_zh":zh,
            "unit_type":"historical_constituent_country","unit_type_name_zh":"联合王国组成地域","level":1,"parent_region_id":None,"capital_name":"未记录",
            "classification_note_zh":"地方制度按组成地域区别。英格兰与威尔士使用共同地方政府法规；组成地域不等同于独立主权国家。"}
        roots.append((row,unary_union(country_shapes[country])))
    emit_reference(key+"_additions","british_isles_1900",trust,added,1900,"历史地理郡重建，非 1900 完整法定行政郡。原下载不含爱尔兰南部 26 郡。")
    emit_reference(key+"_constituents","british_isles_1900",root_source,roots,1900,"1900 组成地域参考：历史郡合成；爱尔兰全岛以现代物理岸线辅助，不是精密行政测绘。")
    for suffix in ["_additions","_constituents"]:
        original.update({x["id"]:x for x in read(OUT/(key+suffix+"_identity.json"))["units"]})
        index["features"].extend(read(OUT/(key+suffix+"_index.json"))["features"])
    act="https://www.legislation.gov.uk/ukpga/Vict/51-52/41/enacted"
    def legal(name,kind,country,capital="未记录"):
        ident="administrative_region:uk_"+kind+"_"+re.sub(r"[^a-z0-9]+","_",name.lower()).strip("_")
        row={"id":ident,"source_unit_id":name,"polity_id":"state:british_isles_1900","name_zh":name,"historical_name":name,
            "unit_type":kind,"unit_type_name_zh":"郡级自治市" if kind=="county_borough" else "行政郡","parent_region_id":rid(country),"level":2,"capital_name":capital,
            "boundary_reference_status":"NO_INDIVIDUAL_BOUNDARY","identity_reference":act,"source_name_zh":"UK Parliament · Local Government Act 1888",
            "source_citation":"Local Government Act 1888, 51 & 52 Vict. c.41, sections 31 and 46 and Third Schedule. Factual unit names and legal types only.",
            "source_license":"UK public legislation / factual extraction; no restricted GIS reproduced","observation_year":1900,
            "temporal_note_zh":"1900 身份参考；没有可分发且适用的独立行政辖界，历史地理郡不得替代。",
            "authority_type_name_zh":"自治市议会；行政上独立于所在郡" if kind=="county_borough" else "郡议会（county council）"}
        original[ident]=row;return row
    boroughs=0
    for schedule in ET.parse(RAW/"uk_act1888_enacted.xml").getroot().iter():
        if not (schedule.tag.endswith("Schedule") and schedule.get("id")=="schedule-THIRD"):continue
        for tr in schedule.iter():
            if not tr.tag.endswith("}tr"):continue
            cells=[" ".join(x.itertext()).strip() for x in tr]
            if not cells or cells[0]=="Name of Borough.":continue
            row=legal(cells[0],"county_borough","wales" if cells[0] in ["Cardiff","Swansea"] else "england",cells[0]);row["source_geographic_county_description"]=cells[1];boroughs+=1
    splits={"Cambridgeshire":["Cambridgeshire","Isle of Ely"],"Lincolnshire":["Parts of Holland","Parts of Kesteven","Parts of Lindsey"],"Northamptonshire":["Northamptonshire","Soke of Peterborough"],"Suffolk":["East Suffolk","West Suffolk"],"Sussex":["East Sussex","West Sussex"],"Yorkshire":["East Riding of Yorkshire","North Riding of Yorkshire","West Riding of Yorkshire"]}
    for name in english_names:
        for actual in splits.get(name,[name]):legal(actual,"administrative_county","england")
    for name in welsh_names:legal(name,"administrative_county","wales")
    original["administrative_region:gb_county_of_london"].update(parent_region_id=rid("england"),level=2,authority_type_name_zh="London County Council")
    legal("Isle of Wight","administrative_county","england")["temporal_note_zh"]="1890 年独立为行政郡；历史地理郡仍另列。独立辖界未接入。"
    for name,url in [("Oxford","https://visionofbritain.org.uk/unit/10166664"),("Grimsby","https://www.visionofbritain.org.uk/census/EW1891PRE/2"),("Newport","https://www.ordnancesurvey.co.uk/documents/product-support/support/historic-county-boundaries-c1890.pdf")]:
        r=legal(name,"county_borough","england",name);r.update(identity_reference=url,source_citation="Original 1891 census and OS historical local-government notes; factual names and types only.")
        r["temporal_note_zh"]="1889—1891 已成为郡级自治市；不包含 1900 年稍后或 1901 年才设立的自治市。"
    city=legal("City of London","county_of_a_city","england","London")
    city.update(unit_type_name_zh="伦敦城 · 特殊市郡",authority_type_name_zh="City of London Corporation；部分职能与 London County Council 关联",classification_note_zh="与伦敦行政郡分别记录；不将全部大伦敦范围当作伦敦城。")
    scot_names="Aberdeenshire,Forfarshire,Argyllshire,Ayrshire,Banffshire,Berwickshire,Buteshire,Caithness,Clackmannanshire,Dumfriesshire,Dunbartonshire,Haddingtonshire,Fife,Inverness-shire,Kincardineshire,Kinross-shire,Kirkcudbrightshire,Lanarkshire,Midlothian,Moray,Nairnshire,Orkney,Peebleshire,Perthshire,Renfrewshire,Ross and Cromarty,Roxburghshire,Selkirkshire,Zetland,Stirlingshire,Sutherland,Linlithgowshire,Wigtownshire".split(",")
    scot_url="https://www.scotlandspeople.gov.uk/help-and-support/guides/counties-cities-and-burghs"
    for name in scot_names:
        r=legal(name,"scottish_administrative_county","scotland")
        r.update(unit_type_name_zh="苏格兰行政郡 · county",authority_type_name_zh="郡议会；Convenor 主持",identity_reference=scot_url,
            source_citation="National Records of Scotland; Ordnance Survey historical county notes, Local Government (Scotland) Act 1889. Factual identity extraction.",legal_valid_from_year=1890,legal_valid_to=None)
        r["classification_note_zh"]="1900 名称保留 Forfarshire、Haddingtonshire、Linlithgowshire、Zetland；现代常用名称只作别名。行政郡辖界与历史地理郡分别记录。"
    # Valuation-roll dates establish existing burgh identities, not their full legal lifecycle or a guessed county parent.
    html_text=(RAW/"scottish_counties_burghs.html").read_text(encoding="utf8")
    clean=html.unescape(re.sub(r"<[^>]+>"," ",html_text))
    burgh_count=0
    for name,start,end in re.findall(r"VR\d+\s+([^()]+?)\s+Burgh\s*\((\d{4})[-–](\d{4})\)",clean):
        if int(start)>1900 or int(end)<1900:continue
        name=" ".join(name.split());r=legal(name,"scottish_burgh","scotland",name)
        r.update(unit_type_name_zh="苏格兰 burgh · 自治市镇",authority_type_name_zh="市镇议会（town council）",identity_reference=scot_url,
            source_citation="National Records of Scotland, named burgh valuation-roll catalogue; historical identity only.",parent_relationship_name_zh="所属组成地域（县属待核定）",
            parent_relation_type="CONSTITUENT_GEOGRAPHIC_SCOPE",record_period={"from":int(start),"to":int(end)},classification_note_zh="名录证明该市镇同期存在；档案起止年不作为行政单位创建和撤销日期。即时县属与独立辖界未逐项取得。")
        burgh_count+=1
    ireland_act="https://www.legislation.gov.uk/ukpga/Vict/61-62/37/enacted"
    irish_names=[r["historical_name"] for r in original.values() if r.get("unit_type")=="historic_county_identity_reference"]
    for name in irish_names:
        for county in (["Tipperary, North Riding","Tipperary, South Riding"] if name=="Tipperary" else [name]):
            r=legal(county,"irish_administrative_county","ireland")
            r.update(unit_type_name_zh="爱尔兰行政郡",authority_type_name_zh="郡议会（county council）",identity_reference=ireland_act,
                source_citation="Local Government (Ireland) Act 1898, 61 & 62 Vict. c.37, sections 1, 21 and 115; original King's Printer PDF. County names from original 1901 census.",
                legal_valid_from="1899-04-01",legal_valid_to=None,classification_note_zh="与传统 32 郡分别记录；Tipperary 分南、北 Riding。1898 法令调整后的独立辖界未取得，不套用今日爱尔兰或北爱尔兰制度。")
    for name in ["Dublin","Belfast","Cork","Limerick","Londonderry","Waterford"]:
        r=legal(name,"irish_county_borough","ireland",name)
        r.update(unit_type_name_zh="爱尔兰郡级自治市",authority_type_name_zh="自治市议会，行使行政郡职能",identity_reference=ireland_act,
            source_citation="Local Government (Ireland) Act 1898, section 21 and Second Schedule; original King's Printer PDF. Factual names and legal types only.",legal_valid_from="1899-04-01",legal_valid_to=None)
    # Generated helper catalogues are merged into the existing national catalogue; only their geometry folders remain.
    doc["units"]=list(original.values());doc["source_basis"]="联合王国组成地域、历史郡参考与地方政府身份分别记录；历史郡线位不能替代行政郡和自治市辖界。"
    for feature in index["features"]:feature["level"]=original[feature["id"]]["level"]
    write(OUT/(key+"_identity.json"),doc);write(OUT/(key+"_index.json"),index)
    for suffix in ["_additions","_constituents"]:
        for kind in ["_identity.json","_index.json"]:(OUT/(key+suffix+kind)).unlink()
    return {"identities":len(original),"geometries":len(index["features"]),"act_1888_boroughs":boroughs,"scottish_burgh_references":burgh_count,"irish_county_geometry_missing":26}


def gpkg(path, table):
    c = sqlite3.connect(path); c.row_factory = sqlite3.Row
    for raw in c.execute('SELECT * FROM "'+table+'"'):
        row = dict(raw); blob = row.pop("geom")
        flags = blob[3]; envelope = (flags >> 1) & 7
        offset = 8 + {0: 0, 1: 32, 2: 48, 3: 48, 4: 64}[envelope]
        yield row, wkb.loads(blob[offset:])
    c.close()


def german_references():
    """Georeference licensed historical cartography, not restricted HGIS geometry."""
    import numpy as np
    from svgelements import SVG, Path as SVGPath, Move, Line, Close
    from shapely.geometry import Polygon
    from shapely import make_valid
    def slug(s):return re.sub(r"[^a-z0-9]+","_",s.lower()).strip("_")
    def gid(s):return "administrative_region:germany_"+slug(s)
    source={"publisher":"Ziegelbrenner / Franzpaul · historical cartography","author":"Ziegelbrenner; Franzpaul; SVG corrections Intforce and Fünffingerfaultier",
        "source_id":"german_licensed_historical_cartography","year":"1871–1918 overview; Württemberg 1900; Baden 1890",
        "locator":"https://commons.wikimedia.org/wiki/File:Deutsches_Reich_(1871-1918)-de.svg",
        "supporting_locators":["https://commons.wikimedia.org/wiki/File:VkDE-wt_1900.svg","https://commons.wikimedia.org/wiki/File:VkDE-bd_1890.svg"],
        "license":"CC BY-SA 3.0 (processed cartographic geometry and attribution)","license_url":"https://creativecommons.org/licenses/by-sa/3.0/",
        "attribution":"Ziegelbrenner, Deutsches Reich (1871–1918), based on Putzger Historischer Weltatlas (1965); Franzpaul, Verwaltungskarte Württemberg 1900 / Baden 1890. WWO: selected contours, cartographic georeferencing, aggregation and display simplification. Derived geographic resources remain CC BY-SA 3.0.",
        "original_files":["german_states.svg","wuerttemberg_1900.svg","baden_1890.svg"],"reconstruction":True,
        "original_crs":"SVG cartographic coordinates; no CRS supplied. Overview registered on identified city markers; southern common metric grid registered on Baden town markers.",
        "identity_locator":"https://www.hgisg-ekompendium.ieg-mainz.de/Register_Verzeichnisse/Staaten/Liste_DR-Staaten.php"}
    note="历史地图衍生参考，非 1900 原始测绘。帝国总图适用 1871—1918 大致格局；下级图分别为 1900 与 1890。概化和配准误差不能当作精密国界或后续年度事实。"
    # Markers identify actual named cities on the source, rather than region centroids.
    gcps=[(42,13.405,52.520),(22,11.576,48.137),(18,9.183,48.775),(59,6.960,50.938),(87,20.507,54.710),(15,7.752,48.583),(75,12.373,51.340),(14,8.651,49.872),(10,8.404,49.006),(9,16.373,48.208),(106,21.118,55.706)]
    dots=read(RAW/"germany_dots.json")
    # A bounded map registration; this never edits runtime political geometry.
    from_geo=Transformer.from_crs(4326,"+proj=lcc +lat_1=48 +lat_2=56 +lat_0=52 +lon_0=10 +datum=WGS84 +units=m",always_xy=True)
    to_geo=Transformer.from_crs(from_geo.target_crs,4326,always_xy=True)
    design=np.array([[dots[i][0],dots[i][1],1] for i,lon,lat in gcps]); target=np.array([from_geo.transform(lon,lat) for i,lon,lat in gcps])
    matrix=np.linalg.lstsq(design,target,rcond=None)[0]
    source["georeferencing_control_points"]=[{"source_marker":i,"svg_xy":dots[i],"lon_lat":[lon,lat]} for i,lon,lat in gcps]
    def registered(x,y,z=None):
        a=np.asarray(x);b=np.asarray(y);e=a*matrix[0,0]+b*matrix[1,0]+matrix[2,0];n=a*matrix[0,1]+b*matrix[1,1]+matrix[2,1]
        return to_geo.transform(e,n)
    def mesh_path(path):
        result=Polygon()
        for part in path.as_subpaths():
            points=[]
            for segment in part:
                if isinstance(segment,Move):continue
                count=1 if isinstance(segment,(Line,Close)) else 6
                points.extend((float(v.x),float(v.y)) for v in [segment.point(i/count) for i in range(count+1)])
            if len(points)>=3:
                poly=make_valid(Polygon(points))
                if not poly.is_empty:result=result.symmetric_difference(poly)
        return result
    elements=list(SVG.parse(str(RAW/"german_states.svg")).elements())
    states=[("Preussen","Königreich Preußen","普鲁士王国","Berlin","#86bbe6","kingdom"),("Bayern","Königreich Bayern","巴伐利亚王国","München","#c1dfc4","kingdom"),
        ("Sachsen","Königreich Sachsen","萨克森王国","Dresden","#e07b3d","kingdom"),("Wuerttemberg","Königreich Württemberg","符腾堡王国","Stuttgart","#ffdd00","kingdom"),
        ("Baden","Großherzogtum Baden","巴登大公国","Karlsruhe","#eda456","grand_duchy"),("Hessen","Großherzogtum Hessen","黑森大公国","Darmstadt","#d08d69","grand_duchy"),
        ("Mecklenburg_Schwerin","Großherzogtum Mecklenburg-Schwerin","梅克伦堡—什未林大公国","Schwerin","#b4a497","grand_duchy"),("Mecklenburg_Strelitz","Großherzogtum Mecklenburg-Strelitz","梅克伦堡—施特雷利茨大公国","Neustrelitz","#d2a38b","grand_duchy"),
        ("Oldenburg","Großherzogtum Oldenburg","奥尔登堡大公国","Oldenburg","#a7c8bb","grand_duchy"),("Sachsen_Weimar","Großherzogtum Sachsen-Weimar-Eisenach","萨克森—魏玛—艾森纳赫大公国","Weimar","#55a930","grand_duchy"),
        ("Braunschweig","Herzogtum Braunschweig","不伦瑞克公国","Braunschweig","#ffcc00","duchy"),("Anhalt","Herzogtum Anhalt","安哈尔特公国","Dessau","#8fafa0","duchy"),
        ("Sachsen_Meiningen","Herzogtum Sachsen-Meiningen","萨克森—迈宁根公国","Meiningen","#94ba1e","duchy"),("Sachsen_Altenburg","Herzogtum Sachsen-Altenburg","萨克森—阿尔滕堡公国","Altenburg","#c7cc00","duchy"),
        ("Sachsen_Coburg_Gotha","Herzogtum Sachsen-Coburg und Gotha","萨克森—科堡—哥达公国","Coburg / Gotha","#009656","duchy"),
        ("Schwarzburg_Rudolstadt","Fürstentum Schwarzburg-Rudolstadt","施瓦茨堡—鲁多尔施塔特侯国","Rudolstadt","#f7a940","principality"),("Schwarzburg_Sondershausen","Fürstentum Schwarzburg-Sondershausen","施瓦茨堡—松德斯豪森侯国","Sondershausen","#cc6e4b","principality"),
        ("Reuss_aelter","Fürstentum Reuß ältere Linie","罗伊斯长系侯国","Greiz","#3773b9","principality"),("Reuss_juenger","Fürstentum Reuß jüngere Linie","罗伊斯幼系侯国","Gera","#0097d7","principality"),
        ("Lippe","Fürstentum Lippe","利珀侯国","Detmold","#9fb577","principality"),("Schaumburg_Lippe","Fürstentum Schaumburg-Lippe","绍姆堡—利珀侯国","Bückeburg","#ebcb7a","principality"),
        ("Waldeck","Fürstentum Waldeck und Pyrmont","瓦尔德克—皮尔蒙特侯国","Arolsen","#e0eab8","principality"),("Elsass_Lothringen","Reichsland Elsaß-Lothringen","阿尔萨斯—洛林帝国直辖领地","Straßburg","#f3987a","reichsland")]
    by_color=defaultdict(list);red=[];blue=[]
    for i,x in enumerate(elements):
        if not isinstance(x,SVGPath):continue
        color=str(x.fill)
        if color not in {row[4] for row in states}|{"#e4001f"}:continue
        b=x.bbox()
        if len(x)<=10 and color!="#e4001f":continue  # legends and city marker circles are not regions
        if color=="#f7a940" and b[1]<350:continue  # Sweden uses the same colour
        g=mesh_path(x)
        if g.is_empty or g.area<=0:continue
        if color=="#e4001f":red.append((i,g))
        elif color=="#86bbe6":blue.append((i,g));by_color[color].append(g)
        else:by_color[color].append(g)
    rows=[];metadata=[]
    def row(name,historical,label,kind,level,parent=None,capital="未记录"):
        return {"id":gid(name),"source_unit_id":name,"polity_id":"state:german_empire","historical_name":historical,"name_zh":label,
            "unit_type":kind,"unit_type_name_zh":kind,"level":level,"parent_region_id":parent,"capital_name":capital,
            "valid_from":"1900-01-01","valid_to":"1901-01-01","date_basis":"Dated reference, not a complete legal lifecycle","identity_reference":source["identity_locator"]}
    for key,name,zh,capital,color,kind in states:
        r=row(key,name,zh,kind,1,capital=capital);r["unit_type_name_zh"]="帝国直辖领地（非联邦邦国）" if kind=="reichsland" else "帝国组成邦 · "+kind
        rows.append((r,transform(registered,unary_union(by_color[color]))))
    # Three free cities share the map colour. Components are separated by their explicitly labelled source locations.
    for key,name,indices in [("Bremen","Freie Hansestadt Bremen",[269,272]),("Hamburg","Freie und Hansestadt Hamburg",[266,275,635,644]),("Luebeck","Freie und Hansestadt Lübeck",[263])]:
        # The labelled source separates Bremen/Bremerhaven from Hamburg/Cuxhaven.
        parts=[g for i,g in red if i in indices]
        r=row(key,name,name,"free_city",1,capital=key);r["unit_type_name_zh"]="自由汉萨城市邦"
        rows.append((r,transform(registered,unary_union(parts))))
    provinces=[(4,"Rheinprovinz","Koblenz"),(7,"Hannover","Hannover"),(10,"Westfalen","Münster"),(12,"Schleswig_Holstein","Schleswig"),(14,"Brandenburg","Potsdam"),(17,"Ostpreussen","Königsberg"),(19,"Westpreussen","Danzig"),(21,"Posen","Posen"),(24,"Pommern","Stettin"),(27,"Schlesien","Breslau"),(30,"Sachsen_Provinz","Magdeburg"),(32,"Hessen_Nassau","Kassel")]
    for i,name,capital in provinces:
        r=row("prussia_"+name,name.replace("_","-"),name.replace("_","-"),"provinz",2,gid("Preussen"),capital);r["unit_type_name_zh"]="普鲁士 Provinz · 省";r["display_max_mpp"]=3500
        r["classification_note_zh"]="总图的省级轮廓参考，不能代替逐年法定省界；柏林自 1881 年具有省外特殊行政地位。"
        rows.append((r,transform(registered,mesh_path(elements[i]))))
    r=row("prussia_hohenzollern","Hohenzollernsche Lande","霍亨索伦地域","regierungsbezirk",2,gid("Preussen"),"Sigmaringen");r["unit_type_name_zh"]="普鲁士特殊地域／Sigmaringen 行政区（非省）"
    rows.append((r,transform(registered,mesh_path(elements[40]))))
    berlin=row("prussia_berlin","Stadtkreis Berlin","柏林特殊行政区","province_free_city",2,gid("Preussen"),"Berlin");berlin["classification_note_zh"]="省外特殊行政地位；不将其作为 Brandenburg 下属县。独立法定市界未取得。";metadata.append(berlin)
    for province,names in {"Ostpreussen":"Königsberg,Gumbinnen","Westpreussen":"Danzig,Marienwerder","Brandenburg":"Potsdam,Frankfurt","Pommern":"Stettin,Köslin,Stralsund","Posen":"Posen,Bromberg","Schlesien":"Breslau,Liegnitz,Oppeln","Sachsen_Provinz":"Magdeburg,Merseburg,Erfurt","Schleswig_Holstein":"Schleswig","Hannover":"Hannover,Hildesheim,Lüneburg,Stade,Osnabrück,Aurich","Hessen_Nassau":"Kassel,Wiesbaden","Westfalen":"Münster,Minden,Arnsberg","Rheinprovinz":"Koblenz,Düsseldorf,Köln,Trier,Aachen"}.items():
        for name in names.split(","):
            r=row("prussia_rb_"+name,"Regierungsbezirk "+name,name,"regierungsbezirk",3,gid("prussia_"+province),name);r["unit_type_name_zh"]="普鲁士 Regierungsbezirk · 行政区";metadata.append(r)
    for name,capital in [("Oberbayern","München"),("Niederbayern","Landshut"),("Pfalz","Speyer"),("Oberpfalz und Regensburg","Regensburg"),("Oberfranken","Bayreuth"),("Mittelfranken","Ansbach"),("Unterfranken und Aschaffenburg","Würzburg"),("Schwaben und Neuburg","Augsburg")]:
        r=row("bavaria_"+name,name,name,"bavarian_kreis",2,gid("Bayern"),capital);r["unit_type_name_zh"]="巴伐利亚 Kreis · 中级行政地域（不是普鲁士县）";metadata.append(r)
    for name in ["Dresden","Leipzig","Bautzen","Zwickau"]:
        r=row("saxony_"+name,"Kreishauptmannschaft "+name,name,"kreishauptmannschaft",2,gid("Sachsen"),name);r["unit_type_name_zh"]="萨克森 Kreishauptmannschaft";r["classification_note_zh"]="Chemnitz 的独立 Kreishauptmannschaft 在 1900 年 7 月才设立，不写入 1900-01-01 开局。";metadata.append(r)
    for key,name,capital,i in [("oldenburg_core","Herzogtum Oldenburg","Oldenburg",297),("oldenburg_luebeck","Fürstentum Lübeck","Eutin",291),("oldenburg_birkenfeld","Fürstentum Birkenfeld","Birkenfeld",300)]:
        r=row(key,name,name,"oldenburg_landesteil",2,gid("Oldenburg"),capital)
        r.update(unit_type_name_zh="奥尔登堡 Landesteil · 分离组成地域",identity_reference="https://www.hgisg-ekompendium.ieg-mainz.de/Dokumentation_Datensaetze/Multimedia/Staaten/Oldenburg.php",authority_type_name_zh="Landesteil 地方行政机构；不与自由市 Lübeck 混同",display_max_mpp=3500)
        rows.append((r,transform(registered,mesh_path(elements[i]))))
    for name,capital in [("Oberhessen","Gießen"),("Rheinhessen","Mainz"),("Starkenburg","Darmstadt")]:
        r=row("hessen_"+name,name,name,"hessian_provinz",2,gid("Hessen"),capital)
        r.update(unit_type_name_zh="黑森 Provinz · 省",identity_reference="https://rp-darmstadt.hessen.de/ueber-uns/organisation/geschichte",authority_type_name_zh="黑森省行政机构；不等同于普鲁士省制");metadata.append(r)
    for name,capital in [("Unterelsass","Straßburg"),("Oberelsass","Colmar"),("Lothringen","Metz")]:
        r=row("elsass_bezirk_"+name,name,name,"reichsland_bezirk",2,gid("Elsass_Lothringen"),capital)
        r.update(unit_type_name_zh="帝国直辖领地 Bezirk · 行政区",authority_type_name_zh="Bezirkspräsidium",identity_reference="https://www.hgisg-ekompendium.ieg-mainz.de/Dokumentation_Datensaetze/Multimedia/Regierungsbezirke.php");metadata.append(r)
    # Register the author’s common metric grid on explicitly labelled administrative-seat markers.
    # UTM is the target of this registration, not an invented declaration of the SVG source CRS.
    broot=ET.parse(RAW/"baden_1890.svg").getroot()
    bpaths=[x for x in broot.iter() if x.tag.endswith("}path") and x.get("id","").startswith("BA")]
    bmarkers=[x for x in broot.iter() if x.tag.endswith("}use") and x.get("{http://www.w3.org/1999/xlink}href")=="#syBA"]
    locations={p.get("id"):(float(m.get("x")),float(m.get("y"))) for p,m in zip(bpaths,bmarkers)}
    controls=[("BAKonstanz",9.175,47.660),("BAFreiburg",7.849,47.996),("BAKarlsruhe",8.404,49.006),("BAMannheim",8.466,49.487),("BAWertheim",9.517,49.758)]
    metric_from_geo=Transformer.from_crs(4326,32632,always_xy=True);metric_to_geo=Transformer.from_crs(32632,4326,always_xy=True)
    mdesign=np.array([[*locations[name],1] for name,lon,lat in controls]);mtarget=np.array([metric_from_geo.transform(lon,lat) for name,lon,lat in controls])
    mmatrix=np.linalg.lstsq(mdesign,mtarget,rcond=None)[0]
    source["southern_georeferencing_control_points"]=[{"source_marker":name,"svg_xy":locations[name],"lon_lat":[lon,lat]} for name,lon,lat in controls]
    source["southern_georeferencing_method"]="Affine registration of the shared maptool kilometre grid on five labelled Baden town markers; reused for the same author's Württemberg grid. Cartographic approximation, not cadastral surveying."
    def southern(x,y,z=None):
        a=np.asarray(x);b=np.asarray(y)
        return metric_to_geo.transform(a*mmatrix[0,0]+b*mmatrix[1,0]+mmatrix[2,0],a*mmatrix[0,1]+b*mmatrix[1,1]+mmatrix[2,1])
    coordinate_note="原图未声明 CRS；依据巴登图明确标注的五座城市配准同作者公里网格，复用于符腾堡。存在制图与配准误差，不宣称精密法定界线。"
    wroot=ET.parse(RAW/"wuerttemberg_1900.svg").getroot();groups=defaultdict(list)
    for x in wroot.iter():
        if not x.tag.endswith("}path"):continue
        name=x.get("id");parent={"kN":"Neckarkreis","kS":"Schwarzwaldkreis","kJ":"Jagstkreis","kD":"Donaukreis"}[x.get("class")]
        r=row("wuerttemberg_"+name,name,name,"city_administration" if name=="Stuttgart" else "oberamt",3,gid("wuerttemberg_"+parent),"Stuttgart" if name=="Stuttgart-Amt" else name)
        r["unit_type_name_zh"]="Stuttgart · 城市行政" if name=="Stuttgart" else "符腾堡 Oberamt"
        r["coordinate_note_zh"]=coordinate_note
        r["boundary_reference"]="https://commons.wikimedia.org/wiki/File:VkDE-wt_1900.svg";r["authority_type_name_zh"]="Oberamt 行政机关；不生成具体任职人物"
        g=transform(southern,mesh_path(SVGPath(x.get("d"))));rows.append((r,g));groups[parent].append(g)
    for name,ps in groups.items():
        r=row("wuerttemberg_"+name,name,name,"wuerttemberg_kreis",2,gid("Wuerttemberg"));r.update(unit_type_name_zh="符腾堡 Kreis · 中级行政地域",coordinate_note_zh=coordinate_note,boundary_reference="https://commons.wikimedia.org/wiki/File:VkDE-wt_1900.svg");rows.append((r,unary_union(ps)))
    # Baden's state supervision and self-government Kreise are parallel institutions, not one invented ladder.
    kreis_names={1:"Konstanz",2:"Villingen",3:"Waldshut",4:"Freiburg",5:"Loerrach",6:"Offenburg",7:"Baden",8:"Karlsruhe",9:"Heidelberg",10:"Mannheim",11:"Mosbach"}
    lcs={1:"Konstanz",2:"Konstanz",3:"Konstanz",4:"Freiburg",5:"Freiburg",6:"Freiburg",7:"Karlsruhe",8:"Karlsruhe",9:"Mannheim",10:"Mannheim",11:"Mannheim"}
    lc_shapes=defaultdict(list);kreis_shapes=defaultdict(list)
    for x in bpaths:
        name=x.get("id")[2:];k=int(x.get("class")[1:]);lc=lcs[k]
        r=row("baden_ba_"+name,"Bezirksamt "+name,name,"baden_bezirksamt",3,gid("baden_lc_"+lc),name)
        r.update(unit_type_name_zh="巴登 Bezirksamt · 行政署辖区",observation_year=1890,coordinate_note_zh=coordinate_note,
            boundary_reference="https://commons.wikimedia.org/wiki/File:VkDE-bd_1890.svg",temporal_note_zh="1890 辖界参考；该图不证明全部 1900 法定辖界已逐项核定。",
            related_region_ids=[gid("baden_kreis_"+kreis_names[k])],related_relationship_name_zh="并行地方自治范围",authority_type_name_zh="Bezirksamt；由 Landeskommissär 监督，与 Kreis 自治机关区别")
        g=transform(southern,mesh_path(SVGPath(x.get("d"))));rows.append((r,g));lc_shapes[lc].append(g);kreis_shapes[k].append(g)
    for name,ps in lc_shapes.items():
        r=row("baden_lc_"+name,"Landeskommissariat "+name,name,"landeskommissariat",2,gid("Baden"),name)
        r.update(unit_type_name_zh="巴登 Landeskommissariat · 监督辖区",observation_year=1890,coordinate_note_zh=coordinate_note,boundary_reference="https://commons.wikimedia.org/wiki/File:VkDE-bd_1890.svg",
            identity_reference="https://www.hgisg-ekompendium.ieg-mainz.de/Dokumentation_Datensaetze/Multimedia/Regierungsbezirke/Landeskommissariat_"+name+".php",
            authority_type_name_zh="Landeskommissär：监督与协调下级行政署，不是 1864 前的 Kreisregierung",temporal_note_zh="1864—1914 机构身份；范围由 1890 下级历史地图组成。")
        rows.append((r,unary_union(ps)))
    for k,ps in kreis_shapes.items():
        name=kreis_names[k];r=row("baden_kreis_"+name,"Kreis "+name,name,"baden_self_government_kreis",2,gid("Baden"),name)
        r.update(unit_type_name_zh="巴登 Kreis · 地方自治联合体",observation_year=1890,coordinate_note_zh=coordinate_note,boundary_reference="https://commons.wikimedia.org/wiki/File:VkDE-bd_1890.svg",
            classification_note_zh="与 Landeskommissariat 的国家监督体系并行，不编成普鲁士式省—县链。",authority_type_name_zh="Kreisversammlung / Kreisausschuss",temporal_note_zh="1890 地方自治范围参考，非 1900 当日原始测绘。",display_max_mpp=1400)
        rows.append((r,unary_union(ps)))
    emit_reference("german_administration_1900","german_empire",source,rows,1900,note)
    doc=read(OUT/"german_administration_1900_identity.json")
    for r in metadata:
        r.update(boundary_reference_status="NO_INDIVIDUAL_BOUNDARY",source_citation="Historical administrative identity and type extraction from the cited institutional reference; no restricted HGIS geometry reproduced.",source_license="Historical factual extraction only",source_name_zh="HGIS Germany eKompendium / historical factual extraction",temporal_note_zh="1900 行政身份参考；适用且可分发的独立辖界尚未取得。",observation_year=1900)
        doc["units"].append(r)
    write(OUT/"german_administration_1900_identity.json",doc)
    return {"identities":len(doc["units"]),"geometries":len(rows),"federal_states_and_reichsland":26,"prussian_provinces":12,"wuerttemberg_lower":64,"baden_1890_lower":52}


def russia():
    source = {"publisher": "IISH / RISTAT · Gijs Kessler, Andrei Markevich; GIS preparation Rombert Stapel",
              "source_id": "ristat_1897", "year": 1897, "locator": "https://doi.org/10.34894/NQOASN",
              "original_locator": "https://hdl.handle.net/10622/DN9QDM", "original_crs": "EPSG:4326",
              "original_files": ["provinces_1897.gpkg", "districts_1897.gpkg"], "license": "CC0 with RISTAT citation requirement",
              "attribution": "Kessler, Gijs and Andrei Markevich, Electronic Repository of Russian Historical Statistics, XVIII–XXI centuries, Version I (2020), https://ristat.org/; Russian Empire Historical GIS Maps (1897), IISH, prepared by Rombert Stapel.", "reconstruction": True}
    note = "1897 年历史 GIS 重建，作为 1900 开局的近年参考，不宣称已核定所有 1897—1900 县界变化；不套用现代国界。"
    rows = []
    for raw, geo in gpkg(RAW / "provinces_1897.gpkg", "provinces_1897"):
        code, name = raw["Gub_ID"], raw["prov_ENG"]
        if code in ["62a", "62b", "70a", "70b"]: continue  # Alternative subdivisions are already in districts_1897.
        if code in ["103", "105"]: continue  # Khiva and Bukhara are protectorates, not imperial provinces.
        kind = "finnish_laani" if code in [str(x) for x in range(1, 11) if x != 2 and x != 3] else "oblast" if "region" in name or code in ["58", "64"] else "special_island_administration" if code == "95" else "guberniya"
        types = {"guberniya": "губерния · 省", "oblast": "область · 州／军政地域", "finnish_laani": "芬兰大公国 · 省（lääni）", "okrug": "округ · 特殊区", "special_island_administration": "萨哈林特殊行政地域"}
        row = {"id": "administrative_region:ristat_province_"+code, "source_unit_id": code, "source_ristat_id": raw["RISTAT_ID"],
               "polity_id": "state:russian_empire", "historical_name": raw["prov_RU"], "name_zh": "圣彼得堡省" if code == "2" else name,
               "source_original_name": name, "source_original_name_ru": raw["prov_RU"], "unit_type": kind, "unit_type_name_zh": types[kind], "level": 1,
               "parent_region_id": None,
               "capital_name": "Saint Petersburg" if code == "2" else "未记录"}
        if code == "2": row.update(capital_place_id="place:st_petersburg", identity_reference="https://nlr.ru/elibrarypro/memo/RA6068/ukazatel?id=11", identity_1900_status="CONFIRMED_NAME_AND_TYPE")
        else: row["identity_1900_status"] = "NEARBY_DATED_REFERENCE_NOT_EXACT_1900_VERIFICATION"
        if code == "64":
            row.update(name_zh="卡尔斯州", historical_name="Карсская область")
            row["classification_note_zh"] = "源文件将卡尔斯称作 governorate；按同期制度标为州，不修改源字段或几何。"
            row["identity_reference"] = "https://nlr.ru/res/epubl/rue/bd/izd_type.php?id=29"
        if code == "58": row.update(name_zh="顿河哥萨克军州", historical_name="Область Войска Донского", identity_reference="https://kp.rusneb.ru/item/material/vsya-oblast-voyska-donskogo-adres-kalendarnaya-torgovo-promyshlennaya-spravochnaya-kniga-sostavil-d-s-neyfeld-na-1899-god-god-izdaniya-5-y")
        if code == "100": row["classification_note_zh"] = "七河州在 1897—1900 间上级总督辖区发生变化；此文件不提供已核定的 1900 上级边界。"
        rows.append((row, geo))
    provinces = len([r for r, _ in rows if r["level"] == 1])
    seen = set()
    for raw, geo in gpkg(RAW / "districts_1897.gpkg", "districts_1897"):
        code = str(raw["Distr_ID"]); parent = str(raw["Gub_ID"])
        if code in seen: raise ValueError("Duplicate district source ID")
        seen.add(code)
        if parent in ["103", "105"]: continue
        name = raw["Name_ENG"] or raw["Name_RU"]
        special = code in ["562", "597"]
        kind = "okrug" if special else "finnish_district_reference" if parent in ["1", "4", "5", "6", "7", "8", "9", "10"] else "district_reference"
        row = {"id": "administrative_region:ristat_district_"+code, "source_unit_id": code, "source_ristat_id": raw["RISTAT_ID"],
               "polity_id": "state:russian_empire", "historical_name": raw["Name_RU"], "name_zh": name,
               "unit_type": kind, "unit_type_name_zh": "округ · 特殊区参考" if special else "芬兰大公国 · 下级区参考" if kind.startswith("finnish") else "县／区级 · 1897 参考",
               "level": 2, "parent_region_id": None if special else "administrative_region:ristat_province_"+parent,
               "source_aggregation_region_id": "administrative_region:ristat_province_"+parent, "capital_name": "未记录",
               "identity_1900_status": "1897_REFERENCE_ONLY"}
        if special: row["classification_note_zh"] = "源 GIS 的统计整合范围不是已确认的法定上级关系；特殊区使用下级文件的实际几何，避免重复绘制。"
        rows.append((row, geo))
    total = emit_reference("russian_empire_1897", "russian_empire", source, rows, 1897, note)
    return provinces, total - provinces


def russia_hierarchy():
    key="russian_empire_1897"
    doc=read(OUT/(key+"_identity.json"));index=read(OUT/(key+"_index.json"))
    units={r["id"]:r for r in doc["units"]}
    def pid(code):return "administrative_region:ristat_province_"+str(code)
    def gid(name):return "administrative_region:ristat_group_"+name
    general="https://old.bigenc.ru/domestic_history/text/2350060"
    seven="https://old.bigenc.ru/domestic_history/text/3826076"
    trans="https://old.bigenc.ru/domestic_history/text/3821806"
    amur="https://m.bigenc.ru/vault/c67e189beb234ae7a05baf3ce303ae23.pdf"
    geo={str(r["Gub_ID"]):g for r,g in gpkg(RAW/"provinces_1897.gpkg","provinces_1897")}
    groups=[("finland","Великое княжество Финляндское","芬兰大公国","grand_duchy","Helsingfors",[1,4,5,6,7,8,9,10],"https://nlr.ru/allrussia/RA8001/administrativno-territorialnoe-delenie"),
        ("warsaw","Варшавское генерал-губернаторство","华沙总督辖区","governor_generalship","Warsaw",[29,30,31,32,33,34,107,25,27,28],general),
        ("kiev","Киевское, Подольское и Волынское генерал-губернаторство","基辅—波多利亚—沃里尼亚总督辖区","governor_generalship","Kiev",[40,39,38],general),
        ("vilna","Виленское, Ковенское и Гродненское генерал-губернаторство","维尔纳—科夫诺—格罗德诺总督辖区","governor_generalship","Vilna",[26,22,36],general),
        ("steppe","Степное генерал-губернаторство","草原总督辖区","governor_generalship","Omsk",[98,99],seven),
        ("turkestan","Туркестанское генерал-губернаторство","突厥斯坦总督辖区","governor_generalship","Tashkent",[101,106,104,100,102],seven),
        ("amur","Приамурское генерал-губернаторство","阿穆尔总督辖区","governor_generalship","Khabarovsk",[89,90,88,95],amur),
        ("irkutsk","Иркутское генерал-губернаторство","伊尔库茨克总督辖区","governor_generalship","Irkutsk",[91,86,96],"https://m.bigenc.ru/vault/c29f2e4efe291dff90bbdb0159975ad0.pdf"),
        ("moscow","Московское генерал-губернаторство","莫斯科总督管辖","governor_generalship","Moscow",[48],general)]
    source=dict(doc["source"])
    source["supporting_locators"]=list(dict.fromkeys(source.get("supporting_locators",[])+[general,seven,trans,amur,"https://nlr.ru/allrussia/RA8853/period?id=2"]))
    source["hierarchy_method"]="Explicit sourced membership as of 1900; dissolved 1897 GIS components. No new officers, organizations, sovereignty or land members."
    records=[]
    for name,historical,label,kind,capital,codes,url in groups:
        row={"id":gid(name),"source_unit_id":name,"polity_id":"state:russian_empire","historical_name":historical,"name_zh":label,
            "unit_type":kind,"unit_type_name_zh":"特殊政治组成地域 · 芬兰大公国" if kind=="grand_duchy" else "генерал-губернаторство · 总督管辖",
            "level":1,"parent_region_id":None,"capital_name":capital,"identity_reference":url,"observation_year":1897,
            "hierarchy_reference_date":"1900-01-01","temporal_note_zh":"1900 上级隶属参考；轮廓由对应 1897 GIS 组成，不宣称为 1900 当日测绘。",
            "authority_type_name_zh":"芬兰特殊制度；总督与芬兰参议院分别存在" if kind=="grand_duchy" else "总督机关；不生成任职人物或政府行为"}
        if name in ["steppe","turkestan"]:row["classification_note_zh"]="七河州 1899 年由草原改属突厥斯坦；跨里海州 1900 已属突厥斯坦。参考轮廓不包括希瓦、布哈拉保护国。"
        if name=="amur":row["classification_note_zh"]="含当时的萨哈林特殊管辖；不将俄日战争以后的南萨哈林分界倒写到开局。"
        records.append((row,unary_union([geo[str(c)] for c in codes])))
        for code in codes:
            units[pid(code)].update(parent_region_id=row["id"],level=2,display_max_mpp=3500,parent_relationship_name_zh="行政上级",hierarchy_reference_date="1900-01-01")
    units[pid(100)].update(capital_name="Верный",classification_note_zh="1897 源几何不变；1900 上级为突厥斯坦总督辖区，已按 1899 改隶处理。",identity_reference=seven)
    units[pid(102)].update(capital_name="Асхабад",identity_reference=trans)
    # Civil Caucasus administration in 1900 was not the restored 1905 viceroyalty.
    caucasus={"id":gid("caucasus_civil_chief"),"source_unit_id":"caucasus_civil_chief","polity_id":"state:russian_empire",
        "historical_name":"Главноначальствующий гражданской частью на Кавказе","name_zh":"高加索民政总管管辖参考",
        "unit_type":"caucasus_civil_chief_reference","unit_type_name_zh":"高加索民政特殊管辖（非 1905 总督区）","level":1,"parent_region_id":None,
        "capital_name":"Tiflis","boundary_reference_status":"NO_INDIVIDUAL_BOUNDARY","identity_reference":"https://nlr.ru/allrussia/RA8853/period?id=2",
        "classification_note_zh":"1882—1905 特殊民政制度。下级完整隶属范围未逐项核定，不据概略范围生成辖界。"}
    leased={"id":gid("kwantung_lease"),"source_unit_id":"kwantung_lease","polity_id":"state:russian_empire","historical_name":"Квантунская область",
        "name_zh":"关东租借地行政参考","unit_type":"leased_territory_administration","unit_type_name_zh":"1899—1905 租借地特殊行政参考","level":1,
        "parent_region_id":None,"capital_name":"Port Arthur","boundary_reference_status":"NO_INDIVIDUAL_BOUNDARY",
        "identity_reference":"https://nlr.ru/allrussia/RA8853/period?id=2","classification_note_zh":"不在 1897 GIS 内；租借关系不等于将中国主权直接改写为俄国主权。精确辖界尚未接入。"}
    for row in [caucasus,leased]:
        row.update(observation_year=1900,source_license="Historical factual extraction; RISTAT geometries CC0 where present",source_name_zh="俄罗斯国家图书馆 · 历史行政参考",temporal_note_zh="1900 特殊行政身份；没有已接入的独立辖界。")
        units[row["id"]]=row
    for row in units.values():
        if row.get("unit_type") in ["district_reference","finnish_district_reference"]:
            parent=units.get(row.get("parent_region_id"),{})
            row["level"]=int(parent.get("level",1))+1;row["display_max_mpp"]=900
            if parent.get("unit_type")=="guberniya":row["unit_type_name_zh"]="уезд · 县级（1897 辖界参考）";row["authority_type_name_zh"]="县级行政机关；不生成官员"
            elif parent.get("unit_type")=="oblast":row["unit_type_name_zh"]="州下县／区 · 1897 参考";row["classification_note_zh"]="各州县、区制度不同；保留原名，不统一改称 губерния 下的 уезд。"
    emit_reference(key+"_groups","russian_empire",source,records,1897,"1900 隶属名录与 1897 空间轮廓分别记录；不是完整逐年行政变更资料。")
    units.update({r["id"]:r for r in read(OUT/(key+"_groups_identity.json"))["units"]})
    index["features"]=[r for r in index["features"] if "_groups_boundaries/" not in r["coarse_path"]]
    index["features"].extend(read(OUT/(key+"_groups_index.json"))["features"])
    for f in index["features"]:f["level"]=units[f["id"]]["level"]
    doc.update(units=list(units.values()),source=source);index["source"]=source
    write(OUT/(key+"_identity.json"),doc);write(OUT/(key+"_index.json"),index)
    for kind in ["_identity.json","_index.json"]:(OUT/(key+"_groups"+kind)).unlink()
    return {"identities":len(units),"geometries":len(index["features"]),"higher_groups":len(records),"province_references":97,"lower_references":822,"special_without_geometry":2}


def display_edges(country_keys=None):
    """Presentation clipping only. Original reference polygons and source areas stay intact."""
    ne=read(ROOT/"local-artifacts/paris-land-pilot-r1/research/ne_10m_land_v512.geojson")
    physical=unary_union([Polygon(p.exterior) for f in ne["features"] for p in polygons(shape(f["geometry"]))])
    def local_geometry(parts):
        return unary_union([Polygon(r[0],r[1:]) for r in parts if r and len(r[0])>=3])
    def lines(g):
        if g.geom_type=="LineString":return [g]
        return [line for part in getattr(g,"geoms",[]) for line in lines(part)]
    total=0
    note="显示线段以 Natural Earth 10m 现代物理陆地遮罩裁切，保留内陆湖泊管辖；拾取不延伸到该遮罩之外的海面。原历史多边形、面积和世界成员不变。国家外缘仍由政治来源表达，未将行政线吸附到国界。"
    for key in country_keys or ["britain_historic_counties","german_administration_1900","russian_empire_1897"]:
        doc=read(OUT/(key+"_identity.json"));index=read(OUT/(key+"_index.json"))
        units={r["id"]:r for r in doc["units"]};geometries={}
        for f in index["features"]:
            geometries[f["id"]]=local_geometry(read(ROOT/f["detail_path"].removeprefix("res://"))["local_polygons"])
        root_ids=[r["id"] for r in doc["units"] if r["id"] in geometries and ((r.get("level")==1) if key!="russian_empire_1897" else r.get("unit_type") in ["guberniya","oblast","finnish_laani","special_island_administration"])]
        perimeter=unary_union([geometries[x] for x in root_ids]).boundary
        outer_strip=perimeter.buffer(90)
        root_sources={units[x].get("boundary_reference","") for x in root_ids}
        parent_strips={}
        geometry_ids=list(geometries)
        neighbors=STRtree(list(geometries.values()))
        bounds=index["features"]
        roi=box(min(x["bounds"][0] for x in bounds)-1,min(x["bounds"][2] for x in bounds)-1,max(x["bounds"][1] for x in bounds)+1,min(89.9,max(x["bounds"][3] for x in bounds)+1))
        land=transform(local_xy,physical.intersection(roi))
        for f in index["features"]:
            ident=f["id"];base=geometries[ident];parent=units[ident].get("parent_region_id")
            # Sharing is only within the same admitted administrative catalogue.
            shared=outer_strip if units[ident].get("boundary_reference","") in root_sources else LineString()
            if parent in geometries and units[ident].get("boundary_reference")==units[parent].get("boundary_reference") and units[ident].get("observation_year")==units[parent].get("observation_year"):
                if parent not in parent_strips:parent_strips[parent]=geometries[parent].boundary.buffer(90)
                shared=unary_union([shared,parent_strips[parent]])
            outline=unary_union(lines(base.boundary.intersection(land)))
            interior=unary_union(lines(outline.difference(shared)))
            # Suppress only coincident sibling segments in the same source and
            # layer. Keep one owner's stroke; selected outlines remain complete.
            for neighbor_index in neighbors.query(base):
                other=geometry_ids[int(neighbor_index)]
                if other>=ident:continue
                if any(units[ident].get(field)!=units[other].get(field) for field in ["level","unit_type","source_citation","observation_year"]):continue
                coincident=unary_union(lines(base.boundary.intersection(geometries[other].boundary)))
                if not coincident.is_empty and not interior.is_empty:interior=interior.difference(coincident)
            pick=base.intersection(land)
            for lod,tolerance in [("coarse",1000), ("detail",65)]:
                path=ROOT/f[lod+"_path"].removeprefix("res://");data=read(path)
                data["display_lines"]=[[[round(x,2),round(y,2)] for x,y in c.coords] for l in lines(interior) for c in lines(l.simplify(tolerance).intersection(land))]
                data["display_outline_lines"]=[[[round(x,2),round(y,2)] for x,y in c.coords] for l in lines(outline) for c in lines(l.simplify(tolerance).intersection(land))]
                data["display_pick_polygons"]=[rings_value(p) for p in polygons(pick)]
                data["display_geometry_basis"]="MODERN_PHYSICAL_COAST_MASK_AND_SAME_CATALOGUE_PARENT_EDGES_ONLY"
                write(path,data)
            units[ident]["display_note_zh"]=note;total+=1
        write(OUT/(key+"_identity.json"),doc)
    return {"administrative_display_units":total,"reference_polygons_changed":False}


def ireland_local():
    """Dated OHM reconstruction, linked to existing legal identities, not modern counties."""
    work=ROOT/"local-artifacts/historical-coasts-islands-r7"
    relations={r["id"]:r for r in read(work/"ireland_ohm_geometry.json")["elements"]}
    way_tags={r["id"]:r.get("tags",{}) for r in read(work/"ireland_ohm_way_tags.json")["elements"]}
    key="britain_historic_counties"
    document=read(OUT/(key+"_identity.json"));index=read(OUT/(key+"_index.json"))
    units={r["id"]:r for r in document["units"]}
    law="https://www.irishstatutebook.ie/eli/1898/act/37/enacted/en/print.html"
    source={"publisher":"OpenHistoricalMap contributors / historical Ordnance Survey Ireland maps", "author":"OpenHistoricalMap contributors",
        "year":"dated 1899–1900 reference; contributing OS editions 1840s–1915", "source_id":"ohm_ireland_local_1900",
        "locator":"https://www.openhistoricalmap.org/", "supporting_locators":[law,"https://www.cso.ie/en/statistics/historicalreports/census1901/"],
        "license":"CC0 except tagged OS-derived ways: CC BY 4.0; retain contributor and map attribution",
        "license_url":"https://www.openhistoricalmap.org/copyright", "original_crs":"EPSG:4326", "reconstruction":True,
        "attribution":"OpenHistoricalMap contributors. OS Six-Inch Ireland, first and second editions, via OHM CC BY 4.0 tagged ways. WWO: dated selection, explicit identity links and display conversion."}
    county_names={2892375:"londonderry",2893637:"kilkenny",2918529:"tipperary_north_riding",2941267:"galway",2941268:"clare",2943391:"louth",2943394:"meath"}
    district_ids=[2890293,2890305,2890545,2890547,2890799,2914167]
    records=[];skipped=[]
    for relation_id in [*county_names,2943003,*district_ids]:
        relation=relations[relation_id];tags=relation["tags"];rings={}
        for role in ["outer","inner"]:
            edges=[]
            for member in relation["members"]:
                if member["type"]!="way" or member.get("role","")!=role:continue
                license=way_tags.get(member["ref"],{}).get("license","CC0")
                if license not in ["CC0","CC-BY-4.0"]:raise ValueError("Unresolved source permission: "+str(member["ref"]))
                points=[(v["lon"],v["lat"]) for v in member.get("geometry",[]) if v]
                if len(points)>=2:edges.append(LineString(points))
            faces,cuts,dangles,invalid=polygonize_full(unary_union(edges))
            if not cuts.is_empty or not dangles.is_empty or not invalid.is_empty:
                skipped.append(relation_id);break
            rings[role]=unary_union(list(faces.geoms))
        if relation_id in skipped:continue
        geometry=rings["outer"].difference(rings["inner"])
        if geometry.is_empty:skipped.append(relation_id);continue
        if relation_id in county_names:
            row=dict(units["administrative_region:uk_irish_administrative_county_"+county_names[relation_id]])
        elif relation_id==2943003:
            row=dict(units["administrative_region:uk_irish_county_borough_waterford"])
        else:
            kind="urban_district" if relation_id in [2890545,2914167] else "rural_district"
            parent="dublin" if relation_id==2914167 else "tyrone"
            row={"id":"administrative_region:ireland_"+kind+"_"+str(relation_id),"polity_id":"state:british_isles_1900",
                "historical_name":tags.get("name:en",tags["name"]),"name_zh":tags.get("name:en",tags["name"]),
                "unit_type":kind,"unit_type_name_zh":"Urban District · 市区" if kind=="urban_district" else "Rural District · 乡村区",
                "level":3,"parent_region_id":"administrative_region:uk_irish_administrative_county_"+parent,
                "capital_name":"未记录", "authority_type_name_zh":"市区议会" if kind=="urban_district" else "乡村区议会",
                "identity_reference":law,"parent_relationship_name_zh":"1898 年地方政府制度下的行政郡"}
        row.update(source_unit_id="OHM relation "+str(relation_id),boundary_reference="https://www.openhistoricalmap.org/relation/"+str(relation_id),
            valid_from="1899-03-25" if relation_id in district_ids else tags.get("start_date","1899-03-25"),
            valid_to=tags.get("end_date","9999-12-31"),observation_year=1900,
            source_start_date=tags.get("start_date",""),source_end_date=tags.get("end_date",""),
            date_basis="Legal identity and OHM interval recorded separately; no independently surveyed 1900-01-01 geometry",
            display_max_mpp=250 if relation_id in district_ids else 700 if relation_id==2943003 else 1800,
            accuracy_note_zh="社区历史 GIS 重建。部分线位依据跨年代的六英寸 OS 图，部分线位未列原始地图；不能认定为逐段核定的 1900 法定界线。",
            classification_note_zh="1898 年法下的地方行政身份；几何采用有对应历史日期的 OHM 重建，历史郡资料另列。")
        if relation_id==2914167:row["temporal_note_zh"]="Pembroke 1900 为市区；本轮廓记录 1880 township 范围，未独立证明 1899—1900 全部线位不变。"
        records.append((row,geometry))
    generated="britain_irish_local_1900"
    emit_reference(generated,"british_isles_1900",source,records,1900,"1898 年法的地方制度与带历史日期的社区 GIS 分别记录；不是完整法定行政郡测绘。")
    produced=read(OUT/(generated+"_identity.json"))
    units.update({r["id"]:r for r in produced["units"]})
    # Traditional county outlines remain selectable references, but do not compete
    # with available administrative county reconstructions at their close scale.
    for name in county_names.values():
        historic="administrative_region:ireland_census_"+name
        if historic in units:units[historic]["display_min_mpp"]=1800
    ireland=units["administrative_region:uk_constituent_ireland"]
    ireland.update(capital_name="Dublin",classification_note_zh="1900 年联合王国组成地域，不是独立主权国家。地方制度依 1898 年法区分行政郡、郡级自治市、市区与乡村区。",
        identity_reference=law,temporal_note_zh="整体为组成地域参考；内部仅显示已取得的传统郡或地方行政重建范围，二者不是同一法定层级。")
    new_index=read(OUT/(generated+"_index.json"))["features"]
    new_ids={r["id"] for r in new_index}
    index["features"]=[r for r in index["features"] if r["id"] not in new_ids]+new_index
    document["units"]=list(units.values())
    document["source"]["supporting_locators"]=list(dict.fromkeys(document["source"].get("supporting_locators",[])+[source["locator"],law,source["license_url"]]))
    write(OUT/(key+"_identity.json"),document);write(OUT/(key+"_index.json"),index)
    # The temporary documents are generation intermediates, not parallel catalogues.
    for suffix in ["_identity.json","_index.json"]:(OUT/(generated+suffix)).unlink()
    return {"administrative_county_geometries":sum(r["id"].find("irish_administrative_county")>=0 for r,g in records),
        "county_borough_geometries":sum(r["id"].find("irish_county_borough")>=0 for r,g in records),
        "district_geometries":sum(r["id"].find("ireland_urban_district")>=0 or r["id"].find("ireland_rural_district")>=0 for r,g in records),"incomplete_source_relations":skipped}


def islands():
    raw = read(ROOT / "local-artifacts/paris-land-pilot-r1/research/ne_10m_land_v512.geojson")
    pieces = [p for f in raw["features"] for p in polygons(shape(f["geometry"]))]
    archive = "https://www.archives.go.jp/ayumi/kobetsu/m28_1895_01.html"
    kinmen = "https://cabkc.kinmen.gov.tw/uploads/files/202304/9c14e6bc-8d26-4ebb-a14f-dd008e549ff6.pdf"
    matsu = "https://www.matsu-news.gov.tw/news/article/109983"
    scot = "https://docs.os.uk/os-downloads/products/areas-and-zones-portfolio/boundary-line/boundary-line-downloads"
    faroe = "https://www.faroeislands.fo/the-big-picture/history-of-the-faroe-islands/the-faroe-islands-in-the-norwegiandanish-monarchy"
    norway = "https://www.stortinget.no/no/english/about-the-storting/historical-highlights/milestones-in-norways-democratic-history/"
    bahrain = "https://www.gutenberg.org/cache/epub/63928/pg63928-images.html#Page_219"
    factual = "Historical factual extraction and attribution only; no copyrighted source text, photographs or maps reproduced"
    sources = [
        {"source_id": "ne_land_v512", "publisher": "Natural Earth", "author": "Natural Earth contributors", "year": None, "version": "5.1.2", "historical_scope": "Modern physical coastline reference; not 1900 sovereignty geometry", "license": "Public domain", "locator": "https://www.naturalearthdata.com/about/terms-of-use/", "historical_gis_reconstruction": False},
        {"source_id": "japan_archives_shimonoseki", "publisher": "National Archives of Japan", "author": "National Archives of Japan", "year": 1895, "historical_scope": "Treaty cession of Taiwan and Penghu, applied as the 1900 reference", "license": factual, "locator": archive, "historical_gis_reconstruction": False},
        {"source_id": "kinmen_county_history", "publisher": "Kinmen County Government / Cultural Affairs Bureau", "author": "Kinmen County Gazetteer editors", "year": None, "historical_scope": "Qing-era Tong'an and Kinmen territorial history", "license": factual, "locator": kinmen, "historical_gis_reconstruction": False},
        {"source_id": "matsu_qing_maritime", "publisher": "Matsu Daily", "author": "He Guangyi / Lin Jinyan / Lin Guoqing", "year": "2010 / 2011 / 2013 retrospective articles", "historical_scope": "Qing Fujian maritime jurisdiction; county-level differences not resolved here", "license": factual, "locator": matsu, "supporting_locators": ["https://www.matsu-news.gov.tw/news/article/102931", "https://www.matsu-news.gov.tw/news/article/108111"], "historical_gis_reconstruction": False},
        {"source_id": "os_scottish_counties", "publisher": "Ordnance Survey / DCLG", "author": "Ordnance Survey", "year": "c.1888 / 1890; Scottish alignment from 1940 mapping", "historical_scope": "Historic Scottish counties and associated island parts", "license": "Open Government Licence v3.0", "attribution": "Contains OS data © Crown copyright and database right 2026", "locator": scot, "historical_gis_reconstruction": True},
        {"source_id": "faroe_monarchy", "publisher": "Government of the Faroe Islands", "author": "Government of the Faroe Islands", "year": None, "historical_scope": "Danish crown relationship after 1814, including 1900", "license": factual, "locator": faroe, "historical_gis_reconstruction": False},
        {"source_id": "norway_union", "publisher": "Stortinget", "author": "Norwegian Parliament", "year": None, "historical_scope": "Norwegian kingdom in the Sweden–Norway union, 1814–1905", "license": factual, "locator": norway, "historical_gis_reconstruction": False},
        {"source_id": "bahrain_zwemer_1900", "publisher": "S. M. Zwemer, Arabia: The Cradle of Islam", "author": "Samuel Marinus Zwemer", "year": 1900, "historical_scope": "Bahrain and Muharraq; local Al Khalifa authority and British protection kept distinct", "license": "Public-domain historical text; factual extraction only", "locator": bahrain, "historical_gis_reconstruction": False},
    ]
    by_url = {s["locator"]: s for s in sources}
    groups = [
        ("taiwan", "台湾本岛及离岸岛屿", "taiwan_under_japan", (120.0, 21.7, 122.2, 25.6), archive, "1895 年割让日本；对应既有台湾日本统治地域，不将台湾海峡其他岛屿一并归入。"),
        ("penghu", "澎湖群岛", "taiwan_under_japan", (119.2, 23.1, 119.8, 23.85), archive, "《马关条约》明确列出澎湖列岛割让日本。"),
        ("orkney", "奥克尼群岛", "british_isles_1900", (-3.5, 58.6, -2.1, 59.5), scot, "英国苏格兰历史郡 Orkney；不与法罗群岛混同。"),
        ("shetland", "设得兰群岛", "british_isles_1900", (-2.2, 59.7, -0.6, 60.95), scot, "英国苏格兰历史郡 Zetland；源文件现用 Shetland 名称。"),
        ("hebrides", "赫布里底群岛", "british_isles_1900", (-8.7, 56.3, -5.7, 58.65), scot, "英国苏格兰历史地域；横跨多个历史郡，不作为单一行政郡。"),
        ("faroe", "法罗群岛", "kingdom_of_denmark", (-7.8, 61.2, -6.0, 62.5), faroe, "1900 年丹麦王冠体系内的独特地域；不归英国或挪威。"),
        ("lofoten_vesteralen", "挪威北部沿岸群岛", "sweden_norway_union", (11.8, 67.3, 16.4, 69.45), norway, "罗弗敦、西奥伦及邻近挪威沿岸岛屿。瑞典—挪威联合王国中的挪威王国地域；不将联合关系解释为瑞典地方行政。"),
    ]
    annotations = []
    def append(key, name, source, chosen, url, note):
        if not chosen: raise ValueError("No actual island component for "+key)
        geo = {"type": "MultiPolygon", "coordinates": [mapping(pieces[i])["coordinates"] for i in chosen]}
        point = max((pieces[i] for i in chosen), key=lambda x: x.area).representative_point()
        annotations.append({"id": "geographic_region:islands_"+key, "name_zh": name, "name": name, "spatial_kind": "island",
                            "geometry": geo, "physical_component_indices": chosen, "physical_source": "Natural Earth 10m land v5.1.2; public domain",
                            "political_source_id": source, "political_reference_date": "1900-01-01", "valid_from": "1900-01-01", "valid_to": "1901-01-01",
                            "lon_lat": [point.x, point.y], "source_name_zh": by_url[url]["publisher"]+" / Natural Earth 岸线",
                            "source_ids": [by_url[url]["source_id"], "ne_land_v512"], "geographic_scope": name, "source_reference": url,
                            "note_zh": note+" 岸线为现代物理参考，不是 1900 年精密政治界线；不写入主权或控制状态。"})
    for key, name, source, b, url, note in groups:
        selected = [i for i, p in enumerate(pieces) if b[0] <= p.bounds[0] and b[1] <= p.bounds[1] and p.bounds[2] <= b[2] and p.bounds[3] <= b[3]]
        append(key, name, source, selected, url, note)
    # Explicit components avoid accidentally labelling nearby Xiamen as Kinmen.
    append("kinmen", "金门与烈屿", "qing_empire", [1045, 5162], kinmen, "清帝国福建同安县地域；没有随台湾、澎湖割让日本。")
    append("dadeng", "大嶝岛", "qing_empire", [5166], kinmen, "福建同安沿海地域；与金门条约割让问题分别处理。")
    append("bahrain_muharraq", "巴林本岛与穆哈拉格岛", "map_authority:arabia_bahrain_1900", [1315, 3987], bahrain, "对应已有巴林酋长国历史权威参考。阿勒哈利法地方权威与英国保护关系分别保留；不建立新的主权或军事控制事实，也不将哈瓦尔诸岛一并推定归属。")
    for key, name, indices in [("nangan", "南竿", [5446]), ("beigan", "北竿", [5447]), ("juguang", "东沙／白犬诸岛（今莒光）", [5438, 5440]), ("dongyin", "东引／西引", [5452])]:
        append(key, name, "qing_empire", indices, matsu, "清帝国福建沿海岛屿。细部县属与海防管辖存在不同资料口径，本条不统一套用现代连江县范围。")
    write(OUT / "island_political_references_1900.json", {"schema_id": "island_political_references_1900_v1", "target_date": "1900-01-01",
        "geometry_role": "PHYSICAL_COMPONENTS_WITH_SEPARATE_HISTORICAL_IDENTITY", "license": "Natural Earth public domain; factual historical extraction with source attribution; no source illustrations reproduced", "sources": sources, "annotations": annotations})
    return len(annotations), sum(len(x["physical_component_indices"]) for x in annotations)


def island_coasts():
    """Extend the existing reference file; never expand a runtime sovereignty polygon."""
    path=OUT/"island_political_references_1900.json"
    document=read(path)
    annotations={r["id"]:r for r in document["annotations"]}
    physical=read(ROOT/"local-artifacts/paris-land-pilot-r1/research/ne_10m_land_v512.geojson")
    pieces=[p for f in physical["features"] for p in polygons(shape(f["geometry"]))]
    added=[]
    factual="Historical factual extraction with attribution; source text, maps and photographs are not reproduced"
    sources={r["source_id"]:r for r in document["sources"]}
    def source(key,publisher,year,url,scope,license=factual):
        sources[key]={"source_id":key,"publisher":publisher,"author":publisher,"year":year,"locator":url,
            "historical_scope":scope,"license":license,"historical_gis_reconstruction":False}
        return key
    changdao=source("changdao_chorography","长岛地方志 / 长岛政府",2024,"https://www.changdao.gov.cn/art/2024/1/21/art_7122_952787.html","庙岛群岛长期隶属蓬莱，1945 特区以前的历史沿革")
    lease=source("frus_china_leases_1899","U.S. Department of State · FRUS 1900",1899,"https://history.state.gov/historicaldocuments/frus1900/d508","1898 旅顺、大连、胶州湾、威海卫租借制度；主权与租借行政分别记录")
    gulf=source("india_office_qeshm_history","British Library India Office Records / Qatar Digital Library",1947,"https://www.qdl.qa/en/archive/81055/vdc_100059806291.0x000014","历史回顾：马斯喀特租借 1868 终止；不是 1900 精密岛界")
    basidu=source("india_office_basidu","British Library India Office Records / Qatar Digital Library","1928–1933 retrospective correspondence","https://www.qdl.qa/en/archive/81055/vdc_100077104051.0x00009b","Qeshm 的波斯关系与 Basidu 英国据点例外；1856 条约副本")
    gulf_claims=source("foreign_office_gulf_claims","UK Foreign Office Research Department / British Library",1947,"https://www.qdl.qa/en/archive/81055/vdc_100059806291.0x000015","1887 Sirri 改由波斯占有；Tanb、Abu Musa 的不同权利主张分别记录","Open Government Licence; historical factual extraction only")
    cook=source("frus_cook_proclamation_1888","U.S. Department of State · FRUS 1889",1888,"https://history.state.gov/historicaldocuments/frus1889/d186","1888 保护声明逐岛列出南库克群岛")
    nz=source("nz_pacific_history","Manatū Taonga / NZ History",2016,"https://nzhistory.govt.nz/war/capture-of-samoa/background","1901 新西兰扩界，不提前到 1900 开局")
    niue=source("niue_proclamation_1900","Museum of New Zealand Te Papa Tongarewa",1900,"https://collections.tepapa.govt.nz/object/64043","Alofi 1900-04-20 保护声明，开局尚未生效")
    samoa=source("frus_samoa_convention_1899","U.S. Department of State · FRUS 1899",1899,"https://history.state.gov/historicaldocuments/frus1899/d625","1899-12-02 三国公约；1900-02-16 交换批准，不将后来分治提前")
    tonga=source("tonga_treaties","Kingdom of Tonga Attorney General's Office",2023,"https://www.ago.gov.to/cms/coming-soon/treaty-collection-in-chronological-order.html?download=2583%3Atonga-treaty-collection-in-chronological-order","条约目录：1900-05-18 英国保护条约签署，开局不提前生效")
    panama=source("frus_panama_1903","U.S. Department of State · FRUS 1903",1903,"https://history.state.gov/historicaldocuments/frus1903/d308","1903 巴拿马脱离哥伦比亚，1900 仍属哥伦比亚")
    cuba=source("us_archives_cuba_occupation","U.S. National Archives",1903,"https://www.archives.gov/milestone-documents/platt-amendment","1898 战后古巴军事占领；不作为已独立共和国")
    arctic=source("canada_arctic_title","Parks Canada / Canadian Heritage",1880,"https://www.pc.gc.ca/apps/dfhd/page_nhs_eng.aspx?id=1147","1880 移交北极群岛权利与主张；不是 1900 全部实际行政或军事控制")
    svalbard=source("storting_svalbard_treaty","Norwegian Parliament",1920,"https://www.stortinget.no/en/in-english/about-the-storting/historical-highlights/the-svalbard-treaty/","1920 条约，1925 生效；不套用 1900 挪威主权")
    fjl=source("franz_josef_history","Birger Kledal / Lex",None,"https://lex.dk/Franz_Josefs_Land","1873 发现与探险；1926 苏联主张不提前到 1900")
    cshape=source("cshapes_2_original_1900","ETH Zürich / CShapes 2.0",1900,"https://icr.ethz.ch/data/cshapes/","原始 GIS 按 1900-01-01 日期选取；与现有历史身份对应，不用国家中心猜测","CC BY-NC-SA 4.0 (existing project source restriction retained)")
    sources[cshape].update(historical_gis_reconstruction=True,publication_year=2022,
        method_note="Later historical GIS reconstruction, not an original 1900 survey; the unsimplified provider file is retained offline.")
    def inside(bounds):
        return [i for i,p in enumerate(pieces) if any(box(*b).contains(p) for b in bounds)]
    def add(key,name,polity,chosen,evidence,note,history=None,end="1901-01-01",geometry=None,priority=20):
        if geometry is None:geometry=MultiPolygon([pieces[i] for i in chosen])
        if geometry.is_empty:return
        biggest=max(polygons(geometry),key=lambda p:p.area)
        anchor=biggest.representative_point()
        row={"id":"geographic_region:islands_"+key,"name":name,"name_zh":name,"spatial_kind":"geographic_region" if key.endswith("_source") else "island",
            "geometry":mapping(geometry),"lon_lat":[anchor.x,anchor.y],"physical_component_indices":chosen,
            "physical_source":"Natural Earth 10m land v5.1.2; public domain", "political_source_id":polity,
            "political_reference_date":"1900-01-01","valid_from":"1900-01-01","valid_to":end,"pick_priority":priority,
            "source_ids":[*evidence,"ne_land_v512"],"source_name_zh":sources[evidence[0]]["publisher"]+" / Natural Earth",
            "source_license":"; ".join(dict.fromkeys([sources[e]["license"] for e in evidence]))+"; Natural Earth public domain",
            "source_reference":sources[evidence[0]]["locator"],"geographic_scope":name,
            "note_zh":note+" 岸线为现代物理参考，历史关系另列；不写入当前主权、控制或行政成员。"}
        if history:row["historical_political_identity"]=history
        annotations[row["id"]]=row;added.append(row)
    add("miaodao","庙岛群岛／长山列岛","qing_empire",inside([(120.4,37.85,121.1,38.85)]),[changdao],"1900 清帝国登州府蓬莱县沿海地域。只对应群岛物理部件，不扩大为周边海域。")
    add("liugong","刘公岛","qing_empire",[5861],[lease],"1898 威海卫租借条约明确包含刘公岛。中国主权关系与英国租借行政并存；不能把它当作清方实际直接治理或英国本土。",
        {"name_zh":"威海卫租借地 · 刘公岛","status_zh":"中国主权关系／英国租借行政","relationship_zh":"1898 条约：英国租借辖区；不改写世界控制状态","related_polity_source_ids":["qing_empire","british_isles_1900"]})
    add("qeshm","格什姆岛（Qeshm）","persia_qajar",[3870],[gulf,basidu],"马斯喀特旧租借于 1868 年终止；波斯关系与 Basidu 英国据点例外分别保留，未取得该据点的精确边界。",
        {"name_zh":"卡扎尔波斯 · 格什姆岛","status_zh":"波斯关系；Basidu 英国据点例外","relationship_zh":"岛内例外范围未接入，不能将全岛视为单一实际控制范围"})
    add("hormuz","霍尔木兹岛","persia_qajar",[2340],[gulf],"与 Bandar Abbas 的旧马斯喀特租借一同于1868年终止，1900 对应卡扎尔波斯历史关系。未以海峡位置推定整个霍尔木兹海峡主权。")
    add("sirri","西里岛（Sirri）","persia_qajar",[2910],[gulf_claims],"英国外交部历史回顾记录1887年波斯占有西里。不能据此将附近大通布、小通布与阿布穆萨全部划归波斯。")
    add("abu_musa_tunb","阿布穆萨与大通布岛","",[3618,5449],[gulf_claims],"历史记录存在波斯与停战海岸统治者的不同权利主张。该回顾不能证明1900-01-01逐岛统一的法定关系；小通布在本物理资料中未取得对应部件。",
        {"name_zh":"阿布穆萨／大通布 · 历史争议参考","status_zh":"不同权利主张；当日逐岛关系未核定","relationship_zh":"不以英国保护、波斯主张或现代归属相互替代"})
    add("cook_south","南库克群岛","",inside([(-160,-22,-157,-18)]),[cook,nz],"1888 保护声明列出的 Hervey／Cook 群岛。1900 开局不能显示为新西兰地方行政区域。北部群岛不按此声明一并推定。",
        {"name_zh":"库克群岛 · 英国保护关系","status_zh":"地方政体／英国保护","relationship_zh":"1901-06-11 才纳入新西兰殖民地疆界"})
    add("niue","纽埃","",[1294],[niue],"1900 年 1 月仍按岛内既有制度展示。Te Papa 保存的保护声明日期为 1900-04-20，不提前生效；不提前使用 1901 新西兰行政关系。",
        {"name_zh":"纽埃 · 岛内政治共同体","status_zh":"英国保护安排尚未在开局生效","relationship_zh":"1900稍后保护声明与1901新西兰扩界分别记录"})
    annotations["geographic_region:islands_niue"]["historical_political_periods"]=[
        {"valid_from":"1900-01-01","valid_to":"1900-04-20","historical_political_identity":annotations["geographic_region:islands_niue"]["historical_political_identity"]},
        {"valid_from":"1900-04-20","valid_to":"1901-01-01","political_reference_date":"1900-04-20",
            "historical_political_identity":{"name_zh":"纽埃 · 英国保护关系","status_zh":"1900 保护声明参考","relationship_zh":"不提前归入1901新西兰行政范围"},
            "note_zh":"Te Papa 所藏声明在1900-04-20确认维多利亚女王的关系。仅为有日期的历史参考，不触发世界政治变更；现代岸线另列。"}]
    # These two geographic groups already exist; dated treaty metadata does not
    # create colonial runtime states or apply military/civil administration.
    annotations.pop("geographic_region:islands_samoa_transition",None)
    for key,name,chosen,power in [("samoa_west","萨摩亚西部 · 萨瓦伊与乌波卢",[3786,3863],"德国"),("samoa_east","萨摩亚东部 · 图图伊拉与马努阿",[1303,2310,2375],"美国")]:
        add(key,name,"",chosen,[samoa],"1899年公约1900-02-16才交换批准。开局显示三国安排过渡期，不将后来殖民政府、地方割让或Swains岛归属提前。",
            {"name_zh":name+" · 分治过渡","status_zh":"三国安排过渡期","relationship_zh":"1899公约尚未完成批准交换"})
        row=annotations["geographic_region:islands_"+key]
        row["historical_political_periods"]=[
            {"valid_from":"1900-01-01","valid_to":"1900-02-16","historical_political_identity":row["historical_political_identity"]},
            {"valid_from":"1900-02-16","valid_to":"1901-01-01","political_reference_date":"1900-02-16",
                "historical_political_identity":{"name_zh":name+" · "+power+"条约权利参考","status_zh":"已生效三国公约的地域安排","relationship_zh":"殖民政府、海军行政与当地割让时间另行区分"},
                "note_zh":"1900-02-16三国公约批准交换。这里仅记录对应条约权利；不把全部地方割让或同一实际控制视为已完成，不写入世界状态。"}]
    add("tonga","汤加群岛","",inside([(-176,-23,-173,-15)]),[tonga],"1900-01-01 展示汤加王国；1900-05-18 签署的英国保护条约不能提前生效。",
        {"name_zh":"汤加王国","status_zh":"王国（开局参考）","relationship_zh":"英国保护条约尚未签署"})
    annotations["geographic_region:islands_tonga"]["historical_political_periods"]=[
        {"valid_from":"1900-01-01","valid_to":"1900-05-18","historical_political_identity":annotations["geographic_region:islands_tonga"]["historical_political_identity"]},
        {"valid_from":"1900-05-18","valid_to":"1901-01-01","political_reference_date":"1900-05-18",
            "historical_political_identity":{"name_zh":"汤加王国 · 英国保护条约","status_zh":"1900 条约关系参考","relationship_zh":"英国对外关系安排不等于取消汤加本地制度"},
            "note_zh":"1900-05-18签署英国保护条约；只读历史关系，不触发主权、实际控制或外交算法。现代物理岸线不定义条约边界。"}]
    add("svalbard","斯瓦尔巴群岛与熊岛","",inside([(10,74,35,81.6)]),[svalbard],"1920 条约及 1925 生效不能提前至 1900。该地有探索和商业活动；未确立现代挪威主权，不以无国色推断无人活动。",
        {"name_zh":"斯瓦尔巴 · 历史地理地域","status_zh":"1900 未确立现代挪威主权","relationship_zh":"近代主权制度在本参考日期以后"})
    add("franz_josef","弗朗茨约瑟夫地群岛","",inside([(42,79.5,66,82)]),[fjl],"1873 年发现后已有多国探险记录；不因今日归属俄罗斯，将1926苏联主张写成1900俄国主权。",
        {"name_zh":"弗朗茨约瑟夫地 · 探索地域","status_zh":"1900 历史地理参考","relationship_zh":"后来的苏联主张尚未生效；不新建操作国家"})
    # Full original political references recover coastline pieces lost by the old
    # 0.08-degree reduction. Clip to real land; never extend a state across water.
    raw=read(ROOT/"local-artifacts/map-correctness-r3/CShapes-2.0.geojson")
    political={}
    for f in raw["features"]:
        r=f["properties"]
        begin="%04d-%02d-%02d"%(r["gwsyear"],r["gwsmonth"],r["gwsday"])
        finish="%04d-%02d-%02d"%(r["gweyear"],r["gwemonth"],r["gweday"])
        if begin<="1900-01-01"<=finish:political[int(r["gwcode"])]=shape(f["geometry"])
    targets=[
        ("shandong_source","山东沿岸 · 既有清帝国范围",710,"qing_empire",[(119,35.5,123.1,38.5)],"清帝国历史范围参考；胶州湾、威海卫租借须另读对应资料，不用本范围推定实际控制。"),
        ("liaodong_source","辽东沿岸 · 既有清帝国范围",710,"qing_empire",[(120.5,39.3,124.5,40.7)],"清帝国历史范围参考；本片段避开旅顺、大连租借地核心，不将全辽东归俄国。租借外缘仍缺精确几何。"),
        ("fujian_source","福建近岸 · 既有清帝国范围",710,"qing_empire",[(118,24,120.1,26.8)],"台湾、澎湖日本统治与清帝国沿海岛屿分别对应。"),
        ("persian_gulf_source","波斯湾北岸与东岸 · 波斯范围参考",630,"persia_qajar",[(47.7,26,56.7,30.5)],"仅采用已存在的日期政治多边形与实际陆地交集；没有命中的争议岛屿不推定为波斯。"),
        ("new_zealand_source","新西兰本岛与近岸岛屿",920,"cshapes_gw_920",[(165,-49,180,-33)],"1900 为新西兰殖民地，不提前使用 1907 自治领身份。"),
        ("chatham_source","查塔姆群岛",920,"cshapes_gw_920",[(-178,-45,-175,-43)],"关联原有新西兰殖民地历史范围。"),
        ("fiji_source","斐济殖民地岛屿",950,"cshapes_gw_950",[(175,-22,180,-12),(-180,-22,-178,-12)],"日期线两侧物理部件对应同一既有斐济殖民地，保护国汤加不并入。"),
        ("panama_source","哥伦比亚 · 巴拿马地域",100,"republic_of_colombia_1900",[(-83.2,7,-77,10)],"1900 属哥伦比亚；1903 巴拿马独立不提前。"),
        ("guatemala_source","危地马拉沿岸",90,"guatemala_1900",[(-93,13,-88,18.5)],"采用现有1900共和国身份，不从陆地距离分配。"),
        ("british_honduras_source","英属洪都拉斯沿岸与岛礁",80,"cshapes_gw_80",[(-89.5,15.8,-87.3,18.6)],"采用现有英属洪都拉斯身份，不作为今日独立伯利兹。"),
        ("honduras_source","洪都拉斯沿岸与岛屿",91,"honduras_1900",[(-89.7,12.5,-82,17.9)],"仅显示来源实际覆盖的共和国范围；洪都拉斯湾邻国岛屿不按最近国家归属。"),
        ("salvador_source","萨尔瓦多沿岸",92,"el_salvador_1900",[(-90.3,12.8,-87.5,14.6)],"采用现有共和国历史范围。"),
        ("nicaragua_source","尼加拉瓜沿岸与岛屿",93,"nicaragua_1900",[(-88,10.5,-82.5,15.3)],"采用现有共和国历史范围。"),
        ("costa_rica_source","哥斯达黎加沿岸",94,"costa_rica_1900",[(-86.2,8,-82.5,11.3)],"采用现有共和国历史范围。"),
        ("cuba_source","古巴及来源覆盖的近岸岛屿",40,"cuba_occupation_1900",[(-85.2,19.6,-73.8,23.6)],"使用已有古巴军事占领参考身份，不视为1902以后独立共和国；松树岛的后来条约争议不据海岸推定。"),
        ("puerto_rico_source","波多黎各及邻岛",6,"cshapes_gw_6",[(-67.5,17.7,-65.1,18.6)],"1898以后美国属地；不提前使用1900年稍后的文官制度。"),
        ("bahamas_source","巴哈马群岛",31,"cshapes_gw_31",[(-80.6,20.7,-72,27.6)],"采用既有英国属地历史参考。"),
        ("canada_arctic_source","加拿大北极群岛 · 历史权利参考",20,"dominion_of_canada",[(-141,65,-60,84)],"1880 英国移交权利与主张，不等于每岛已形成相同实际治理。Sverdrup 等复杂主张仍需分岛资料。"),
        ("russian_arctic_source","俄罗斯北部 · 既有历史范围",365,"russian_empire",[(45,68,75,78)],"只对应原日期政治来源覆盖的陆地；不把1926以后弗朗茨约瑟夫地主权提前。")]
    for key,name,gw,polity,boxes,note in targets:
        if gw not in political or not political[gw].is_valid:continue
        window=unary_union([box(*b) for b in boxes])
        historical=political[gw].intersection(window)
        chosen=[];clipped=[]
        for i,p in enumerate(pieces):
            if not p.intersects(window):continue
            piece=p.intersection(historical)
            if not polygons(piece):continue
            chosen.append(i);clipped.extend(polygons(piece))
        evidence=[cshape]
        if key=="panama_source":evidence=[panama,cshape]
        elif key=="cuba_source":evidence=[cuba,cshape]
        elif key=="canada_arctic_source":evidence=[arctic,cshape]
        elif key in ["new_zealand_source","chatham_source","fiji_source"]:evidence=[nz,cshape]
        add(key,name,polity,chosen,evidence,note,geometry=unary_union(clipped),priority=0)
    document.update(annotations=list(annotations.values()),sources=list(sources.values()),
        license="Natural Earth physical geometry public domain; attributed factual extraction. CShapes-derived intersection references retain existing CC BY-NC-SA 4.0 restriction; individual sources separately recorded.")
    write(path,document)
    # Preserve the established physical objects and identities; enrich their cards.
    geographic_path=ROOT/"data/presentation/geographic_annotations_r3.json"
    geographic=read(geographic_path)
    for row in geographic["annotations"]:
        if row["id"]=="geography:greenland":
            row.update(political_source_id="",political_reference_date="1900-01-01",source_name_zh="Klaus Georg Hansen / Lex · 格陵兰宪制史；Natural Earth 岸线",
                source_reference="https://lex.dk/Gr%C3%B8nlands_forfatningsretslige_historie",
                source_license=factual+"; physical coastline public domain",
                historical_political_identity={"name_zh":"格陵兰 · 丹麦殖民关系","status_zh":"殖民地治理与地方据点","relationship_zh":"1782—1908 两个督察辖区与殖民据点制度；不宣称全岛一致实际控制","related_polity_source_ids":["kingdom_of_denmark"]},
                note_zh="1900 存在丹麦殖民统治与地方治理制度，不能继续视为无历史关系。现有全岛轮廓仅为物理参考，不据此推定全岛法定主权与一致实际控制；不采用现代格陵兰旗帜。")
        elif row["id"]=="geography:antarctica":
            row.update(political_source_id="",political_reference_date="1900-01-01",source_name_zh="British Antarctic Territory · 历史说明；Natural Earth 岸线",
                source_reference="https://www.britishantarcticterritory.org.uk/heritage/history-of-the-territory/",source_license=factual+"; physical coastline public domain",
                historical_political_identity={"name_zh":"南极洲 · 历史地理与探索地域","status_zh":"不套用现代南极领土分区","relationship_zh":"英国正式主张始于1908，不能提前至1900"},
                note_zh="1900 为历史地理与探索参考；英国1908主张未生效，不按现代各国主张着色。物理冰盖和海岸不等于国家、占领或行政范围。")
        if row["id"] in ["geography:greenland","geography:antarctica"]:
            row["note_lines_zh"]=[row["historical_political_identity"]["name_zh"],row["historical_political_identity"]["status_zh"],row["historical_political_identity"]["relationship_zh"]]
    write(geographic_path,geographic)
    return {"added_reference_groups":len(added),"total_reference_groups":len(annotations),"physical_component_links":sum(len(r.get("physical_component_indices",[])) for r in annotations.values()),
        "coastline_source":"Natural Earth 5.1.2; full original CShapes dated reference where used","new_runtime_polities":0}


def island_gaps_r8():
    """Bounded coastline references; no sovereignty or runtime identity mutation."""
    path = OUT / "island_political_references_1900.json"
    document = read(path)
    annotations = {r["id"]: r for r in document["annotations"]}
    sources = {r["source_id"]: r for r in document["sources"]}
    factual = "Attributed historical factual extraction; no source image or text reproduced"
    sources["naa_new_guinea_administration"] = dict(source_id="naa_new_guinea_administration",
        publisher="National Archives of Australia", author="National Archives of Australia", year="1884–1906 chronology",
        locator="https://www.naa.gov.au/help-your-research/fact-sheets/records-papua-new-guinea-1883-1942",
        historical_scope="1888 British New Guinea; German direct administration from 1899; Australian Papua from 1906, not 1900",
        license=factual, historical_gis_reconstruction=False)
    sources["times_new_guinea_1900"] = dict(source_id="times_new_guinea_1900",
        publisher="The Office of The Times / David Rumsey Historical Map Collection", author="Richard Andree / The Times",
        year=1900, locator="https://www.davidrumsey.com/luna/servlet/detail/RUMSEY~8~1~253893~5519269:New-Guinea-and-the-Papuan-Archipela",
        historical_scope="New Guinea and the Papuan Archipelago, Times Atlas 1900; British, German and Dutch colonial reference",
        license=factual+"; catalogue facts only, collection scan not redistributed", historical_gis_reconstruction=False)
    sources["frus_liaodong_1899"] = dict(source_id="frus_liaodong_1899",
        publisher="U.S. Department of State / Office of the Historian", author="John Hay", year=1899,
        locator="https://history.state.gov/historicaldocuments/frus1899/d103",
        supporting_locators=["https://history.state.gov/historicaldocuments/frus1900/d508"],
        historical_scope="Port Arthur and Talienwan lease, 1898; sovereignty distinct from Russian lease administration",
        license=factual, historical_gis_reconstruction=False)
    physical = read(ROOT / "local-artifacts/paris-land-pilot-r1/research/ne_10m_land_v512.geojson")
    pieces = [p for f in physical["features"] for p in polygons(shape(f["geometry"]))]
    physical_index = STRtree(pieces)
    political = {}
    for f in read(ROOT / "local-artifacts/map-correctness-r3/CShapes-2.0.geojson")["features"]:
        p = f["properties"]
        start = "%04d-%02d-%02d" % (p["gwsyear"], p["gwsmonth"], p["gwsday"])
        end = "%04d-%02d-%02d" % (p["gweyear"], p["gwemonth"], p["gweday"])
        if start <= "1900-01-01" <= end: political[int(p["gwcode"])] = shape(f["geometry"])
    country_union = {code: g if g.is_valid else g.buffer(0) for code, g in political.items()}
    targets = [
        ("liaodong_source", "辽东沿岸与南部 · 清方主权／租借例外", 710, "qing_empire", (120.5,38.4,124.5,40.7), ["frus_liaodong_1899"],
         "清帝国主权参考。旅顺、大连及邻接地域已有俄罗斯租借行政，但本政治 GIS 未单列精确租借外缘；不能据此宣称全片由清方直接治理，更不将整个辽东归俄。"),
        ("new_guinea_dutch_source", "新几内亚西部 · 荷属东印度参考", 850, "cshapes_gw_850", (130,-11.5,141.1,0), ["times_new_guinea_1900"],
         "按原日期荷属东印度几何对应西部；不使用现代印度尼西亚省制。殖民权利与实际据点治理范围不合并。"),
        ("new_guinea_german_source", "德属新几内亚 · 东北部", 912, "cshapes_gw_912", (140.8,-9.5,152,-0.5), ["naa_new_guinea_administration","times_new_guinea_1900"],
         "1900 为德属新几内亚，1899 起由德国直接行政。使用已有殖民地域身份，不扩大为新几内亚全岛。"),
        ("new_guinea_british_source", "英属新几内亚 · 东南部与相关岛屿", 911, "cshapes_gw_911", (140.8,-12,156.5,-5), ["naa_new_guinea_administration","times_new_guinea_1900"],
         "1888 以后英属新几内亚。1906 澳大利亚巴布亚行政不提前至1900；殖民范围不等于每一内陆地点具有相同实际治理。"),
        ("bismarck_source", "俾斯麦群岛 · 德属新几内亚", 912, "cshapes_gw_912", (146,-6.9,154.8,-1), ["naa_new_guinea_administration","times_new_guinea_1900"],
         "新不列颠、新爱尔兰、阿德默勒尔蒂群岛等只在原日期几何支持处关联德属新几内亚；不并入英属东南部。")]
    # Revisit the existing Central American references with original dated GIS,
    # preserving all existing names and political identities.
    for key in ["panama_source","guatemala_source","british_honduras_source","honduras_source","salvador_source","nicaragua_source","costa_rica_source","cuba_source","puerto_rico_source"]:
        r = annotations["geographic_region:islands_"+key]
        code = {"panama_source":100,"guatemala_source":90,"british_honduras_source":80,"honduras_source":91,"salvador_source":92,"nicaragua_source":93,"costa_rica_source":94,"cuba_source":40,"puerto_rico_source":6}[key]
        bounds = country_union[code].bounds
        targets.append((key,r["name"],code,r["political_source_id"],bounds,
            [s for s in r["source_ids"] if s not in ["ne_land_v512","cshapes_2_original_1900"]],r["note_zh"].split(" 岸线为现代物理参考")[0]))
    updated = []
    for key,name,code,polity,bounds,evidence,note in targets:
        window = box(*bounds)
        historical = country_union[code].intersection(window)
        chosen, clipped, complete = [], [], []
        for candidate in physical_index.query(historical):
            i = int(candidate)
            p = pieces[i]
            if key=="bismarck_source" and p.area>=15: continue
            overlap = p.intersection(historical)
            if not polygons(overlap): continue
            chosen.append(i)
            # A discrete island can carry its entire physical outline only when
            # one historical source covers its interior and no other polity
            # competes. Never assign a continental component by nearest centre.
            ratio = overlap.area / max(p.area, 1e-12)
            other = any(g.intersects(p) and g.intersection(p).area > p.area*0.02
                        for n,g in country_union.items() if n != code)
            whole = p.area < 15 and window.covers(p) and ratio >= 0.80 and not other
            clipped.extend(polygons(p if whole else overlap))
            if whole: complete.append(i)
        geometry = unary_union(clipped)
        if geometry.is_empty: continue
        anchor = max(polygons(geometry),key=lambda p:p.area).representative_point()
        identity = "geographic_region:islands_"+key
        row = dict(annotations.get(identity,{}))
        evidence = list(dict.fromkeys(evidence+["cshapes_2_original_1900"]))
        row.update(id=identity,name=name,name_zh=name,spatial_kind="geographic_region",geometry=mapping(geometry),
            lon_lat=[anchor.x,anchor.y],physical_component_indices=chosen,whole_physical_component_indices=complete,
            physical_source="Natural Earth 10m land v5.1.2; public domain",political_source_id=polity,
            political_reference_date="1900-01-01",valid_from="1900-01-01",valid_to="1901-01-01",pick_priority=10 if key=="bismarck_source" else 0,
            source_ids=evidence+["ne_land_v512"],source_name_zh=sources[evidence[0]]["publisher"]+" / CShapes / Natural Earth",
            source_reference=sources[evidence[0]]["locator"],source_license="; ".join(dict.fromkeys(sources[s]["license"] for s in evidence))+"; Natural Earth public domain",
            geographic_scope=name,geometry_method="Dated original political geometry intersected with physical land; discrete whole islands only on single-source interior coverage, not proximity; source boundary accuracy retained",
            note_zh=note+" 岸线为现代物理参考，历史关系另列；不写入当前主权、控制或行政成员。")
        if key=="liaodong_source":
            row["historical_political_identity"] = dict(name_zh="辽东 · 清方主权与俄方租借行政分别记录",
                status_zh="清帝国主权；南部旅顺／大连租借例外",relationship_zh="俄罗斯租借不等于割让。此片段未给出可核定的租借外缘，不能作为统一实际控制范围。",
                related_polity_source_ids=["qing_empire","russian_empire"])
        annotations[identity] = row
        updated.append(dict(id=identity,physical_components=len(chosen),whole_islands=len(complete)))
    document.update(annotations=list(annotations.values()),sources=list(sources.values()))
    write(path,document)
    return {"updated_groups":updated,"total_groups":len(annotations),"new_world_facts":0}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("parts", nargs="*", default=["uk", "russia", "islands"])
    for part in parser.parse_args().parts:
        print(part, {"uk": uk, "uk_hierarchy": uk_hierarchy, "russia": russia, "russia_hierarchy":russia_hierarchy, "islands": islands, "france": france_lower, "germany": german_references,"display_edges":display_edges,"ireland_local":ireland_local,"island_coasts":island_coasts,"island_gaps_r8":island_gaps_r8}[part]())
