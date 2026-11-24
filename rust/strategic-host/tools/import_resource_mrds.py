"""Extract dated locations from the USGS MRDS service for the 1900 resource map."""

import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import json
import math
from pathlib import Path
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen


LAYER = "https://energy.usgs.gov/arcgis/rest/services/MRData/Mineral_Resource_Data_System/MapServer/3/query"
YEAR = 1900
MATERIALS = {
    "PB": "lead_ore", "ZN": "zinc_ore", "SN": "tin_ore", "AL": "bauxite",
    "MN": "manganese_ore", "NI": "nickel_ore", "CR": "chromium_ore",
    "S": "sulfur", "HAL": "industrial_salt", "NA": "industrial_salt",
    "P": "phosphate_ore", "K": "potash", "NIT": "nitrate",
    "LS": "limestone", "STN": "stone", "SDG": "aggregate", "CLY": "clay",
}
GRADES = ("A", "B", "C")
PAGE = 240


def rows(table):
    if isinstance(table, dict):
        return [table]
    return table or []


def year(raw):
    if isinstance(raw, str) and len(raw) == 4 and raw.isascii() and raw.isdecimal():
        return int(raw)
    return None


def query(**options):
    arguments = urlencode(dict(f="json", **options), quote_via=quote)
    request = Request(f"{LAYER}?{arguments}", headers={"User-Agent": "WWO Resource Geography"})
    with urlopen(request, timeout=45) as response:
        result = json.load(response)
    if "error" in result:
        raise RuntimeError(result["error"])
    return result


def source_features():
    materials = " OR ".join(f"code_list LIKE '% {code} %'" for code in MATERIALS)
    dates = " OR ".join(f"""json LIKE '%"{field}":"1%'""" for field in ("yr_fst_prd", "disc_yr"))
    grades = ",".join(f"'{grade}'" for grade in GRADES)
    where = f"grade IN ({grades}) AND ({materials}) AND ({dates})"
    # The service carries the historical fields in one nested JSON column.
    identifiers = query(where=where, returnIdsOnly="true")["objectIds"]
    print(f"MRDS returned {len(identifiers)} dated candidates", flush=True)

    def features(batch):
        page = query(objectIds=",".join(map(str, batch)),
                     outFields="gid,dep_id,site_name,grade,json", returnGeometry="false")
        if page.get("exceededTransferLimit") or len(page["features"]) != len(batch):
            raise RuntimeError("MRDS feature batch was truncated")
        return [entry["attributes"] for entry in page["features"]]

    with ThreadPoolExecutor(max_workers=3) as workers:
        batches = (identifiers[start:start + PAGE] for start in range(0, len(identifiers), PAGE))
        for batch in workers.map(features, batches):
            yield from batch


def historical_status(deposit):
    discovered = year(deposit.get("disc_yr"))
    first = year(deposit.get("yr_fst_prd"))
    last = year(deposit.get("yr_lst_prd"))
    # Before/after qualifiers do not establish an exact year.
    if deposit.get("dy_ba") in ("<", ">"):
        discovered = None
    if deposit.get("yfp_ba") in ("<", ">"):
        first = None
    if deposit.get("ylp_ba") in ("<", ">"):
        last = None
    if (first and last and last < first) or (first and discovered and first < discovered):
        return None
    if first and first <= YEAR:
        # First/last dates do not show uninterrupted production between them.
        status = "former" if last is not None and last < YEAR else "unknown"
        return "working", status, discovered, first, last
    if discovered is not None and discovered <= YEAR:
        return "deposit", "discovered", discovered, first, last
    return None


def convert(entry):
    source = json.loads(entry["json"])
    properties = source["properties"]
    deposit = properties["deposits"]
    if deposit.get("oper_tp") == "Processing Plant" or not entry["site_name"]:
        return []
    dated = historical_status(deposit)
    if dated is None:
        return []
    kind, development, discovered, first, last = dated
    geometry = source.get("geometry") or {}
    coordinates = geometry.get("coordinates") or []
    if geometry.get("type") != "Point" or len(coordinates) != 2:
        return []
    lon, lat = coordinates
    if not (isinstance(lon, (float, int)) and isinstance(lat, (float, int))
            and math.isfinite(lon) and math.isfinite(lat) and -180 <= lon <= 180
            and -90 <= lat <= 90 and (lon, lat) != (0, 0)):
        return []
    variants = {}
    for commodity in rows(properties.get("commodity")):
        code = commodity.get("code")
        if code not in MATERIALS or commodity.get("import") != "Primary":
            continue
        resource_type = MATERIALS[code]
        label = commodity.get("commod", "")
        if resource_type == "bauxite" and "bauxite" not in label.casefold():
            continue
        if resource_type == "industrial_salt" and not any(
            salt in label.casefold() for salt in ("salt", "halite", "sodium chloride")
        ):
            continue
        variants[resource_type] = label
    site = entry["dep_id"]
    linked_duplicates = {d["dep_id_dup"] for d in rows(properties.get("dups")) if d.get("dep_id_dup")}
    positions = rows(properties.get("geo_coordinates"))
    accuracy = str(positions[0].get("loc_prec", "")) if len(positions) == 1 else ""
    precision_m = int(accuracy) if accuracy.isascii() and accuracy.isdecimal() else 0
    location = rows(properties.get("location"))
    country = location[0].get("country", "") if location else ""
    return [
        ({
            "resource_id": f"mrds:{site}:{resource_type}",
            "resource_type": resource_type,
            "kind": kind,
            "name": entry["site_name"],
            "variant": variant,
            "geometry": {"shape": "point", "coordinates": [lon, lat]},
            "spatial_accuracy_m": precision_m if 0 < precision_m <= 40_075_000 else None,
            "valid_from": YEAR,
            "valid_to": YEAR + 1,
            "discovered_on": discovered if discovered is not None and discovered <= YEAR else None,
            "first_production_year": first if first is not None and first <= YEAR else None,
            "last_production_year": last if last is not None and last <= YEAR else None,
            "development_status": development,
            "evidence_status": "estimated",
            "source": f"{LAYER}?where=dep_id%3D%27{site}%27&outFields=dep_id,site_name,grade,json&returnGeometry=false&f=json",
        }, country, entry["grade"], site, linked_duplicates)
        for resource_type, variant in sorted(variants.items())
    ]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    candidates = [record for entry in source_features() for record in convert(entry)]
    accepted = []
    seen = {}
    for record, country, grade, site, duplicates in sorted(
        candidates, key=lambda value: (value[2], value[0]["resource_id"])
    ):
        material = record["resource_type"]
        seen_for_material = seen.setdefault(material, set())
        if site in seen_for_material or not seen_for_material.isdisjoint(duplicates):
            continue
        seen_for_material.update(duplicates | {site})
        accepted.append((record, country))
    accepted.sort(key=lambda entry: entry[0]["resource_id"])
    encoded = [json.dumps({k: v for k, v in record.items() if v is not None},
                          ensure_ascii=False, separators=(",", ":")) for record, _ in accepted]
    args.output.write_text("[\n  " + ",\n  ".join(encoded) + "\n]\n", encoding="utf-8")
    print(Counter(record["resource_type"] for record, _ in accepted))
    print(Counter(country for _, country in accepted))


if __name__ == "__main__":
    main()
