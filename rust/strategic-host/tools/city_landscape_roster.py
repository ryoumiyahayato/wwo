"""Generate and query the historical landscape planning roster, without altering population data."""

import argparse
import csv
import gzip
import json
import math
import sys
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
POPULATION = ROOT / "data/historical_population_1900"
HISTORICAL_MAP = ROOT / "data/world_map/historical"
DATA = HISTORICAL_MAP / "city_landscape_1900"
REFERENCE_DATE = "1900-01-01"
CANDIDATE_YEARS = range(1895, 1906)
MINIMUM = 100_000
REGIONS = (
    "Europe", "East Asia", "South Asia", "Southeast Asia",
    "West Asia and North Africa", "Sub-Saharan Africa", "North America",
    "Latin America and Caribbean", "Oceania", "Central Asia",
)
REGIONAL_GAPS = {
    "Europe": "Missing comparable city limits for parts of Belgium, the Ottoman Balkans, and western Russia; industrial conurbations require municipal separation.",
    "East Asia": "Qing and Korean municipal totals and homogeneous boundaries are incomplete. Maritime Customs port districts can exceed the corresponding city.",
    "South Asia": "Some princely jurisdictions and cantonments need smaller-unit returns. Combined civilian and military town counts do not establish a continuous urban footprint.",
    "Southeast Asia": "Java city versus regency, Saigon versus Cholon, and Bangkok city versus province remain uneven. Burmese cities use the Indian census while their region is Southeast Asia.",
    "West Asia and North Africa": "Province and registration totals must not stand in for cities. Some Moroccan and Arabian urban estimates are broad or disagree.",
    "Sub-Saharan Africa": "Local counts often omit people and settlements. City limits for Yoruba and Hausa centres and urban counts in Portuguese and Ottoman territories are incomplete.",
    "North America": "Primary returns are strongest for the US and Canada. Canadian province totals do not imply the presence or absence of a major city.",
    "Latin America and Caribbean": "1900–1905 city-specific returns are uneven. Separate federal districts, municipal rural hinterland and built-up settlements. Rio's 1900 return was annulled.",
    "Oceania": "Australian comparisons combine cities and suburbs; New Zealand returns list principal towns and suburbs. Island-wide returns are not urban counts.",
    "Central Asia": "1897 Russian city returns cover some cities. Separate Bukhara and Khiva and avoid replacing absent counts with district totals.",
}


def json_file(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def ledger(table):
    with gzip.open(POPULATION / f"{table}_1900.jsonl.gz", "rt", encoding="utf-8-sig") as handle:
        return [json.loads(line) for line in handle]


def table(path):
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def year(date):
    return int(date[:4]) if date and date[:4].isdigit() else None


def tier(population):
    if population >= 500_000:
        return 7
    if population >= 200_000:
        return 8
    if population >= MINIMUM:
        return 9
    return None


def as_point(row):
    lon, lat = row.get("longitude"), row.get("latitude")
    if lon is not None and lon != "" and lat is not None and lat != "":
        return [float(lon), float(lat)]
    return None


def reading(row):
    return {
        k: row[k] for k in (
            "record_id", "unit_id", "name", "source_id", "locator", "date",
            "population_value", "population_lower", "population_upper", "definition",
            "method", "quality", "parent_id", "source_country_label", "date_basis",
        ) if row.get(k) is not None
    }


def district_region(unit, point=None):
    code = unit["gwcode"]
    if code in (2, 3, 20, 21):
        return "North America"
    if code == 4 or 901 <= code <= 950:
        return "Oceania"
    if code < 200:
        return "Latin America and Caribbean"
    if code == 365 and point and point[0] >= 47 and point[1] < 49:
        if point[0] >= 50:
            return "Central Asia"
        if point[1] < 43:
            return "West Asia and North Africa"
    if code == 640 and point and point[0] < 29.1 and point[1] >= 40:
        return "Europe"
    if code <= 395 or code in (3461, 3462):
        return "Europe"
    if code < 600 or 4781 <= code <= 5519:
        return "Sub-Saharan Africa"
    if code in (7020, 7030):
        return "Central Asia"
    if code < 700:
        return "West Asia and North Africa"
    if code in (710, 713, 730, 740):
        return "East Asia"
    if code == 750 and point and point[0] >= 92.14 and point[1] < 27.1:
        return "Southeast Asia"
    if code < 800:
        return "South Asia"
    return "Southeast Asia"


def fallback_region(rows, point):
    for row in rows:
        if row.get("region") == "Europe":
            return "Europe"
        if row.get("region") in {"South America", "America"}:
            return "Latin America and Caribbean"
        if row.get("region") in {"North America", "Oceania"}:
            return row["region"]
    if point:
        lon, lat = point
        if lat >= 12 and lon >= 98 and lat >= 23:
            return "East Asia"
        if lon > 90:
            return "Southeast Asia"
        if lat >= 8 and 65 <= lon <= 90:
            return "South Asia"
        if lat >= 20 and -18 <= lon < 65:
            return "West Asia and North Africa"
        if -25 <= lon <= 55 and -36 <= lat < 20:
            return "Sub-Saharan Africa"
    return "unresolved"


def political_index(geography):
    from shapely.geometry import shape
    from shapely.strtree import STRtree

    registry = json_file(HISTORICAL_MAP / "political_units_1900.json")
    units = {row["id"]: row for row in registry["units"]}
    geometry_keys = {row["geometry_feature_id"]: row["id"] for row in units.values()}
    features = json_file(HISTORICAL_MAP / "cshapes_1900_snapshot.json")["features"]
    parts = []
    for feature in features:
        geom = shape(feature["geometry"])
        polygons = geom.geoms if geom.geom_type == "MultiPolygon" else (geom,)
        parts.extend((geometry_keys[feature["id"]], polygon) for polygon in polygons)
    tree = STRtree([polygon for _, polygon in parts])
    observation_to_unit = {
        reference: row["id"] for row in geography
        if row["catalogue"] == "political_unit" and row["id"] in units
        for reference in row["historical_observation_ids"]
    }
    return registry["snapshot_date"], units, parts, tree, observation_to_unit


def political_owner(point, refs, rows, population, indices):
    from shapely.geometry import Point

    _, units, parts, tree, observation_to_unit = indices
    linked = [r["historical_polity"] for r in refs if r.get("historical_polity") in units]
    if linked:
        return {"id": linked[0], "method": "existing_map_place"}
    ancestry = set()
    ancestors = [r.get("parent_id") for r in rows]
    ancestors.extend(r.get("wwo_id") for r in rows)
    while ancestors:
        key = ancestors.pop()
        if not key or key in ancestry:
            continue
        ancestry.add(key)
        ancestors.extend(r.get("parent_id") for r in population.get(key, ()))
        ancestors.extend(r.get("wwo_id") for r in population.get(key, ()) if r.get("wwo_id") != key)
    direct = {observation_to_unit.get(key, key) for key in ancestry}
    direct.intersection_update(units)
    if len(direct) == 1:
        return {"id": direct.pop(), "method": "observation_ancestry"}

    if point is not None:
        location = Point(point)
        matches = {parts[int(i)][0] for i in tree.query(location, predicate="within")}
        if len(matches) == 1:
            return {"id": matches.pop(), "method": "snapshot_point"}
        if not matches:
            index = int(tree.nearest(location))
            unit, polygon = parts[index]
            distance = polygon.distance(location)
            if distance <= 0.15:
                return {"id": unit, "method": "coastal_snapshot_nearest", "distance_degrees": round(distance, 5)}
    return {"id": None, "method": "unresolved", "source_ancestry": sorted(direct)}


def preference(row, preferred_record):
    """Use existing selected evidence first and preserve all alternatives."""
    source = row["source_id"]
    return (
        source == "reba_chandler_1900",
        row["record_id"] != preferred_record,
        abs(year(row["date"]) - 1900),
        row["record_id"],
    )


def index_sources():
    population = ledger("population")
    cities = {row["city_key"]: row for row in ledger("cities")}
    geography = ledger("geography")
    all_rows = defaultdict(list)
    observations = defaultdict(list)
    place_links = defaultdict(list)
    for row in population:
        all_rows[row["unit_id"]].append(row)
        if row["kind"] == "city" and row.get("city_key"):
            observations[row["city_key"]].append(row)
    for row in geography:
        if row["catalogue"] == "map_place" and row.get("city_key"):
            place_links[row["city_key"]].append(row)
    return cities, all_rows, observations, place_links, geography


def evidence_and_identity(key, source_rows, registry_row, amendment, supplement, place_links, names_zh):
    rows = list(source_rows)
    comparable = [
        row for row in source_rows
        if year(row.get("date")) in CANDIDATE_YEARS and row.get("population_value") is not None
    ]
    source_frequency = Counter(row["source"] for row in supplement)
    selected_supplement = None
    for supplement_row in supplement:
        use = supplement_row.get("use", "")
        source = supplement_row["source"]
        record_id = f"supplement:{source}:{key}"
        if source_frequency[source] > 1:
            record_id = f"{record_id}:{supplement_row['date']}"
        row = {
            "name": supplement_row["name"],
            "record_id": record_id,
            "date": supplement_row["date"],
            "source_id": source,
            "population_value": int(supplement_row["population"]),
            "definition": supplement_row["definition"],
            "locator": supplement_row["locator"],
            "method": "published_estimate" if use.startswith("dated_publication") else "named_period_reference",
            **{field: supplement_row[field] for field in ("longitude", "latitude")},
        }
        if use.startswith("dated_publication"):
            if not row["date"]:
                raise ValueError(f"Missing publication year: {key}")
            row["date_basis"] = "publication_year; observation year unspecified"
        if use == "dated_publication":
            if amendment.get("decision") not in {"P", "X"} or not row["date"]:
                raise ValueError(f"Publication-dated reading requires an explicit decision: {key}")
        rows.append(row)
        if use == "dated_publication" or (not use and year(row["date"]) in CANDIDATE_YEARS):
            if selected_supplement:
                raise ValueError(f"Multiple selected supplement rows for {key}")
            selected_supplement = row
    chosen = selected_supplement
    if not chosen and comparable:
        chosen = min(comparable, key=lambda row: preference(row, registry_row.get("representative_record")))
    name = amendment.get("historic_name") or (chosen or {}).get("name") or registry_row.get("name") or key
    locator = next((row for row in rows[len(source_rows):] if as_point(row)), None)
    point = as_point(amendment) or as_point(chosen or {}) or as_point(registry_row) or as_point(locator or {})
    point_source = "decisions.csv" if as_point(amendment) else (
        chosen["record_id"] if as_point(chosen or {}) else registry_row.get("coordinate_record")
        or (locator["record_id"] if locator else None)
    )
    aliases = {row["name"] for row in rows} - {name}
    for row in rows:
        aliases.update(part.strip() for part in (row.get("source_alternate_name") or "").split(",") if part.strip())
    if key in names_zh:
        aliases.add(names_zh[key])
    aliases.update(row["name"] for row in place_links if row["name"] != name)
    return name, sorted(aliases), point, point_source, rows, chosen


def choose_scope(rows, adopted, amendment):
    if amendment.get("decision") == "X":
        return "X", None, None, amendment["reason"]
    if adopted is None:
        return "X", None, None, "No usable 1895–1905 city-level figure among checked records. Coverage is unresolved."
    value = adopted["population_value"]
    lower = int(amendment["lower"]) if amendment.get("lower") else adopted.get("population_lower")
    upper = int(amendment["upper"]) if amendment.get("upper") else adopted.get("population_upper")
    if amendment.get("decision") == "P":
        allocation = max(value, upper or 0)
        if record := amendment.get("scheduling_record"):
            alternative = next((row for row in rows if row["record_id"] == record), None)
            if not alternative:
                raise ValueError(f"Missing scheduling evidence: {record}")
            allocation = max(allocation, alternative["population_value"])
        if tier(allocation) is None:
            raise ValueError(f"No qualifying scheduling evidence: {adopted['record_id']}")
        return "P", tier(value), tier(allocation), amendment["reason"]
    if value < MINIMUM and (upper or 0) < MINIMUM:
        return "X", tier(value), None, amendment.get("reason") or "Adopted city-level figure is below 100000."
    nominal = tier(value)
    batch = tier(max(value, upper or 0))
    estimate = adopted["source_id"] in {"reba_chandler_1900", "de_yearbook_municipal"} or (
        adopted.get("quality") == "historical_population_estimate"
    )
    uncertain = (lower is not None and lower < MINIMUM) or estimate or nominal != batch
    return (
        amendment.get("decision") or ("P" if uncertain else "D"),
        nominal, batch,
        amendment.get("reason") or (
            "Historical urban reading retained provisionally; confirm its settlement boundary before geometry."
            if uncertain else "Use the nearest selected historical urban count in its published scope."
        ),
    )


def place_name_key(name):
    letters = unicodedata.normalize("NFKD", name.casefold())
    return "".join(char for char in letters if char.isalnum())


def screen_named_places(candidates, published_places, coverage):
    """Compare historical spellings against the offline city and place catalogues."""
    checks = {}
    candidate_names = defaultdict(list)
    geography_names = defaultdict(list)
    for city in candidates:
        for name in {city["name"], *city["aliases"]}:
            candidate_names[place_name_key(name)].append(city)
    for place in published_places.values():
        geography_names[place_name_key(place["name"])].append(place)
    for row in table(DATA / "political-screening.csv"):
        unit = row["unit"]
        if unit not in coverage or unit in checks:
            raise ValueError(f"Invalid political screening unit: {unit}")
        places = []
        for entry in row["places"].split("|"):
            aliases = entry.split("/")
            names = {place_name_key(alias) for alias in aliases}
            matches = {city["city_id"]: city for name in names for city in candidate_names[name]}
            maps = {place["id"]: place for name in names for place in geography_names[name]}
            places.append({
                "aliases": aliases,
                "same_unit": [
                    {"id": key, "decision": city["decision"]}
                    for key, city in sorted(matches.items()) if city["polity"]["id"] == unit
                ],
                "other_or_unassigned": [
                    {"id": key, "polity": city["polity"]["id"], "decision": city["decision"]}
                    for key, city in sorted(matches.items()) if city["polity"]["id"] != unit
                ],
                "map_places": sorted(key for key, place in maps.items() if place.get("historical_polity") == unit),
            })
        checks[unit] = {
            "offline_sources": ["reba_chandler_1900", "historical_population_1900/geography"],
            "comparison_sources": row["references"].split("|") if row["references"] else [],
            "note": row["scope"],
            "places": places,
        }
    return checks


def compile_roster():
    cities, population, observations, places, geography = index_sources()
    supplement = defaultdict(list)
    for row in table(DATA / "supplement-population.csv"):
        supplement[row["key"]].append(row)
    amendments = {row["key"]: row for row in table(DATA / "decisions.csv")}
    manual = json_file(DATA / "site-plans.json")
    names_zh = {
        row["city_key"]: row["chinese_name"] for row in
        table(POPULATION / "collections/cities_europe/city_chinese_names.csv")
    }
    indices = political_index(geography)
    date, units, _, _, _ = indices
    published_places = {row["id"]: row for row in geography if row["catalogue"] == "map_place"}
    coverage = {
        key: {"city_sources": set(), "comparison_sources": set(), "noncity_sources": set(), "references": []}
        for key in units
    }
    for key, rows in population.items():
        direct = indices[4].get(key)
        if direct in units:
            coverage[direct]["noncity_sources"].update(
                row["source_id"] for row in rows if row["kind"] in {"admin", "country", "territory", "historical_territory"}
            )
    for rows in population.values():
        for row in rows:
            if row["kind"] in {"admin", "country", "territory", "historical_territory"}:
                owner = political_owner(None, [], [row], population, indices)["id"]
                if owner in units:
                    coverage[owner]["noncity_sources"].add(row["source_id"])

    candidates = []
    keys = set(cities) | set(observations) | set(supplement) | set(amendments)
    for key, amendment in amendments.items():
        aliases = amendment.get("other_key", "").split("|")
        if amendment.get("adopt_place_links") == "yes":
            if len(aliases) != 1 or aliases[0] not in keys:
                raise ValueError(f"Unresolved canonical place linkage for {key}")
            places[aliases[0]].extend(places[key])
        for alias in filter(None, aliases):
            if alias not in keys:
                raise ValueError(f"Unresolved related identity for {key}: {alias}")
    for key in sorted(keys):
        amendment = amendments.get(key, {})
        if place_id := amendment.get("existing_place_id"):
            places[key].append(published_places[place_id])
        identity = evidence_and_identity(
            key, observations[key], cities.get(key, {}), amendment, supplement[key], places[key], names_zh
        )
        name, aliases, point, point_source, rows, adopted = identity
        plan = manual["sites"].get(key)
        polity = political_owner(point, places[key], rows, population, indices)
        if unit_id := amendment.get("polity"):
            if unit_id not in units:
                raise ValueError(f"Unknown political unit {unit_id} for {key}")
            polity = {"id": unit_id, "method": "reviewed_historical_jurisdiction"}
        elif plan and plan.get("jurisdiction"):
            polity = plan["jurisdiction"]
        region = plan.get("region") if plan else None
        if not region:
            region = district_region(units[polity["id"]], point) if polity["id"] in units else fallback_region(rows, point)
        if polity["id"] in units:
            for row in rows:
                in_window = year(row.get("date")) in CANDIDATE_YEARS and not row.get("date_basis")
                sources = "city_sources" if in_window else "comparison_sources"
                coverage[polity["id"]][sources].add(row["source_id"])
        disposition, nominal, batch, reason = choose_scope(rows, adopted, amendment)
        if disposition != "X" and (point is None or region == "unresolved"):
            raise ValueError(f"Target {key} has unresolved point or region")
        item = {
            "city_id": key,
            "name": name,
            "aliases": aliases,
            "point": point,
            "point_source": point_source,
            "region": region,
            "polity": polity,
            "existing_place_ids": sorted({r["id"] for r in places[key]}),
            "evidence_ids": sorted({r["record_id"] for r in rows}),
            "selected_observation": reading(adopted) if adopted else None,
            "comparison_observations": [reading(row) for row in rows if row is not adopted],
            "scheduling_record": amendment.get("scheduling_record") or None,
            "decision": disposition,
            "reason": reason,
            "related_ids": amendment["other_key"].split("|") if amendment.get("other_key") else [],
        }
        if batch:
            quality = (plan or {}).get("grade", "C")
            preferred_sources = dict.fromkeys(
                (plan or {}).get("source_preference", [])
                + manual["source_search_by_evidence"].get(adopted["source_id"], [])
                + manual["source_search_by_polity"].get(polity["id"], [])
                + manual["regional_source_search"][region]
            )
            item.update({
                "reference_date": REFERENCE_DATE,
                "observation_year_delta": None if adopted.get("date_basis") else year(adopted["date"]) - 1900,
                "nominal_batch": nominal,
                "batch": batch,
                "grade": quality,
                "phase": "planned",
                "construction": {
                    "profile": (plan or {}).get("profile", "anchored_evidence"),
                    "regional_style": region,
                    "seed": point,
                    "seed_precision": "locator_only" if quality == "C" else "see_source_mask",
                    "site_plan": key if plan and plan.get("anchors") else None,
                    "extent_state": "anchor_reviewed" if plan and plan.get("anchors") else "period_anchor_needed",
                    "source_lookup": {
                        "place": name,
                        "preference": list(preferred_sources),
                    },
                    "local_reference": manual["local_reference"].get(key, []),
                    "nearest_independent_targets": [],
                },
            })
            lower = int(amendment["lower"]) if amendment.get("lower") else adopted.get("population_lower")
            upper = int(amendment["upper"]) if amendment.get("upper") else adopted.get("population_upper")
            if lower is not None or upper is not None:
                item["adopted_interval"] = {
                    "lower": lower, "upper": upper,
                    "source": amendment.get("interval_source") or adopted["source_id"],
                }
        candidates.append(item)
        if polity["id"] in units and rows:
            coverage[polity["id"]]["references"].append({
                "id": key, "decision": disposition,
            })

    targets = [row for row in candidates if row.get("batch")]
    for row in targets:
        lon, lat = row["point"]
        near = []
        for other in targets:
            if other["city_id"] == row["city_id"]:
                continue
            x, y = other["point"]
            dx = ((x - lon + 180) % 360 - 180) * math.cos(math.radians((lat + y) / 2))
            kilometres = math.hypot(dx, y - lat) * 111.2
            if kilometres < 30:
                near.append((round(kilometres, 2), other["city_id"]))
        row["construction"]["nearest_independent_targets"] = [
            {"id": key, "km": km} for km, key in sorted(near)
        ]

    checks = screen_named_places(candidates, published_places, coverage)
    by_unit = []
    for key, unit in units.items():
        city_sources = sorted(coverage[key]["city_sources"])
        noncity = sorted(coverage[key]["noncity_sources"])
        by_unit.append({
            "id": key, "name": unit["source_name"], "region": district_region(unit),
            "coverage": "city_list" if city_sources else "noncity_only" if noncity else "no_city_statistics_located",
            "city_sources": city_sources, "noncity_sources": noncity,
            "comparison_city_sources": sorted(coverage[key]["comparison_sources"] - set(city_sources)),
            "city_sources_only_compiled": city_sources == ["reba_chandler_1900"],
            "screened_city_records": coverage[key]["references"],
            "historical_name_screen": checks.get(key),
            "target_count": sum(row["polity"]["id"] == key for row in targets),
        })
    return {
        "schema_version": 1,
        "status": "review",
        "reference_date": REFERENCE_DATE,
        "political_metadata_date": date,
        "sources": "supplement-sources.csv",
        "site_plan_file": "site-plans.json",
        "political_screening_file": "political-screening.csv",
        "regional_gaps": REGIONAL_GAPS,
        "coverage": by_unit,
        "candidates": candidates,
    }


def write_roster(roster):
    header = {key: value for key, value in roster.items() if key not in ("candidates", "coverage")}
    (DATA / "roster.json").write_text(
        json.dumps(header | {"coverage": "coverage.jsonl", "candidates": "candidates.jsonl"},
                   ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n"
    )
    for key in ("candidates", "coverage"):
        with (DATA / f"{key}.jsonl").open("w", encoding="utf-8", newline="\n") as handle:
            for row in roster[key]:
                handle.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")


def read_roster():
    header = json_file(DATA / "roster.json")
    for key in ("candidates", "coverage"):
        with (DATA / header[key]).open(encoding="utf-8") as handle:
            header[key] = [json.loads(line) for line in handle]
    return header


def summarize(roster):
    candidates = roster["candidates"]
    targets = [row for row in candidates if row.get("batch")]
    print(f"Status {roster['status']}; world opening {roster['reference_date']}; political metadata {roster['political_metadata_date']}")
    print(f"Candidate identities {len(candidates)}. Decisions {dict(sorted(Counter(r['decision'] for r in candidates).items()))}")
    print(f"N {len(targets)}. Batches {dict(sorted(Counter(r['batch'] for r in targets).items()))}")
    print(f"Grades {dict(sorted(Counter(r['grade'] for r in targets).items()))}")
    print(f"Construction {dict(sorted(Counter(r['construction']['profile'] for r in targets).items()))}")
    print(f"Delivery {dict(sorted(Counter(r['phase'] for r in targets).items()))}")
    print(f"Extent reviews {dict(sorted(Counter(r['construction']['extent_state'] for r in targets).items()))}")
    print(f"Style requirements {dict(sorted(Counter(r['construction']['regional_style'] for r in targets).items()))}")
    print(f"Political coverage {dict(sorted(Counter(r['coverage'] for r in roster['coverage']).items()))}")
    print("Region | D | P | X | B7 | B8 | B9")
    for region in (*REGIONS, "unresolved"):
        matching = [row for row in candidates if row["region"] == region]
        dispositions = Counter(r["decision"] for r in matching)
        batches = Counter(r.get("batch") for r in matching)
        print(f"{region} | {dispositions['D']} | {dispositions['P']} | {dispositions['X']} | {batches[7]} | {batches[8]} | {batches[9]}")


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--generate", action="store_true", help="Regenerate from local ledgers (requires Shapely).")
    action.add_argument("--city", metavar="ID", help="Print a single city card, resolving inherited rules.")
    action.add_argument("--unit", metavar="ID", help="Print a political unit's sources and named-place screening.")
    options = parser.parse_args()
    if options.generate:
        roster = compile_roster()
        write_roster(roster)
        summarize(roster)
    elif options.city:
        roster = read_roster()
        city = next((row for row in roster["candidates"] if row["city_id"] == options.city), None)
        if not city:
            parser.error(f"Unknown city: {options.city}")
        if "construction" in city:
            plans = json_file(DATA / roster["site_plan_file"])
            city["construction"]["rules"] = plans["profiles"][city["construction"]["profile"]]
            city["construction"]["style"] = plans["regional_styles"][city["region"]]
            city["construction"]["detail"] = plans["sites"].get(city["city_id"])
            source_keys = set(city["construction"]["rules"]["inputs"])
            source_keys.update(city["construction"]["source_lookup"]["preference"])
            source_keys.update(row["source"] for row in city["construction"]["local_reference"])
            city["construction"]["inputs"] = {key: plans["sources"][key] for key in sorted(source_keys)}
        print(json.dumps(city, ensure_ascii=False, indent=2))
    elif options.unit:
        coverage = read_roster()["coverage"]
        unit = next((row for row in coverage if row["id"] == options.unit), None)
        if not unit:
            parser.error(f"Unknown political unit: {options.unit}")
        print(json.dumps(unit, ensure_ascii=False, indent=2))
    else:
        summarize(read_roster())


if __name__ == "__main__":
    main()
