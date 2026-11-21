"""Build the source observations and mutually exclusive national opening groups."""
import csv
from collections import defaultdict
from datetime import date
import json
from pathlib import Path
import re
import unicodedata

ROOT = Path(__file__).resolve().parent
MAP = ROOT.parents[2] / "world_map"
OPENING = date(1900, 1, 1)
FR_SOURCE = "insee_sgf_censuses"
DE_SOURCE = "de_jahrbuch_1902_census"
FR_DATES = ("1896-03-29", "1901-03-24")
DE_DATES = ("1895-12-02", "1900-12-01")


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def read_csv(name):
    with (ROOT / name).open(encoding="utf-8", newline="") as stream:
        return list(csv.DictReader(stream))


def normalize(value):
    ascii_text = unicodedata.normalize("NFKD", value.lower()).encode("ascii", "ignore").decode()
    return re.sub("[^a-z0-9]", "", ascii_text)


def observation(unit, name, parent, kind, value, date_str, source, locator, definition, method,
                mapping, quality, region="Europe", **metadata):
    return dict(unit_id=unit, name=name, parent_id=parent, kind=kind, population_value=value,
                population_lower=None, population_upper=None, date=date_str, source_id=source,
                locator=locator, definition=definition, method=method, mapping_status=mapping,
                quality=quality, region=region, **metadata)


def estimate(pair):
    a, b = sorted(pair, key=lambda row: row["date"])
    left = date.fromisoformat(a["date"])
    right = date.fromisoformat(b["date"])
    elapsed, span = (OPENING - left).days, (right - left).days
    numerator = a["population_value"] * (span - elapsed) + b["population_value"] * elapsed
    out = dict(a)
    out.update(date=OPENING.isoformat(), population_value=(2 * numerator + span) // (2 * span),
               quality="interpolated", method="linear_daily_interpolation",
               locator=a["locator"] + " + " + b["locator"],
               endpoint_dates=[a["date"], b["date"]], endpoint_values=[a["population_value"], b["population_value"]])
    return out


def opening_group(country, country_estimate, units, assignments, filename):
    valid_cities = {row["id"] for row in read_json(MAP / "cities.json")["cities"]}
    ports = read_json(MAP / "ports.json")["ports"]
    output = []
    for row in units:
        ident = row["unit_id"]
        cities = assignments.get(ident, [])
        if not set(cities) <= valid_cities:
            raise ValueError(f"Unknown formal city for {ident}")
        places = [*cities, *(p["id"] for p in ports if p["city_id"] in cities)]
        output.append(dict(unit_id=ident, name=row["name"], population_value=row["population_value"],
                           place_ids=["place:" + name for name in places], locator=row["locator"],
                           endpoint_values=row["endpoint_values"]))
    total = sum(row["population_value"] for row in output)
    group = dict(unit_id=country, date=OPENING.isoformat(), population_value=total,
                 source_id=country_estimate["source_id"],
                 locator=country_estimate["locator"], method="sum_of_linearly_interpolated_first_level_census_units",
                 endpoint_dates=country_estimate["endpoint_dates"], country_endpoint_values=country_estimate["endpoint_values"],
                 country_interpolated_value=country_estimate["population_value"],
                 difference_from_country_interpolation=total-country_estimate["population_value"], units=output)
    write_json(ROOT / filename, group)


# Historical arrondissement name variants and field truncations, matched only inside their département.
ARR_NAMES = {
    "MOULINS-SUR-ALLIER":"Moulins","VILLEFRANCHE-DE-ROUERGUE":"Villefranche",
    "VILLEFRANCHE-DE-LAURAGAIS":"Villefranche","SAVENAY":"Saint-Nazaire",
    "VILLE-FR-SUR-SAON":"Villefranche-sur-Saône","NEUFCHATEL-EN-BRAY":"Neufchâtel",
    "MOULINS-SUR-ALLIE":"Moulins","ROCROY":"Rocroi","MILHAU":"Millau","VILLEFR-DE-ROUERG":"Villefranche",
    "ARLES-SUR-RHONE":"Arles","ST-JEAN-D'ANGELY":"Saint-Jean-d'Angély","ST-AMAND-MONTROND":"Saint-Amand-Montrond",
    "CHATILLON-SUR-SEI":"Châtillon-sur-Seine","SEMUR":"Semur-en-Auxois","GUINCAMP":"Guingamp",
    "BEAUME-LES-DAMES":"Baume-les-Dames","MONTELIMART":"Montélimar","VILLEFRANC DE LAU":"Villefranche",
    "YSSENGEAUX":"Yssingeaux","VILLENEUV-SUR-LOT":"Villeneuve-sur-Lot","VITRY":"Vitry-le-François",
    "VASSY":"Wassy","MONTREUIL-SUR-MER":"Montreuil","OLORON":"Oloron-Sainte-Marie","ARGELES":"Argelès-Gazost",
    "BAGNERES":"Bagnères-de-Bigorre","VILLEFR-SUR-SAONE":"Villefranche-sur-Saône","SAINT-JEAN-DE-MAU":"Saint-Jean-de-Maurienne",
    "SAINT-JULLIEN":"Saint-Julien-en-Genevois","THONON":"Thonon-les-Bains","NEUFCHATEL-EN-BRA":"Neufchâtel",
    "CASTEL-SARRAZIN":"Castelsarrasin","SABLES-D'OLONNE":"Les Sables-d'Olonne",
}
FR_PLACES = {"75":["paris"],"59":["lille"],"62":["calais"],"76":["rouen","le_havre"],
             "29":["brest"],"44":["nantes"],"33":["bordeaux"],"31":["toulouse"],"69":["lyon"],"13":["marseille"]}


def french():
    deps = {str(x["historical_source_dep_id"]).zfill(2): x for x in
            read_json(MAP / "historical/france_administrative_identity_1900.json")["units"]}
    arrs = {(x["parent_region_id"], normalize(x["historical_name"])): x for x in
            read_json(MAP / "historical/france_lower_1900_identity.json")["units"] if x["unit_type"] == "arrondissement"}
    out, pairs = [], {}
    country = "country_fra"
    for raw in read_csv("french_census.csv"):
        dep = deps.get(raw["V3"])
        level = raw["V1"]
        verified = True
        if level == "0":
            unit, name, parent, kind, wwo = country, "France métropolitaine", None, "country", "state:" + country
        elif level == "1":
            unit = wwo = dep["id"]
            name, parent, kind = dep["historical_name"], country, "admin"
        else:
            key = normalize(ARR_NAMES.get(raw["V6"], raw["V6"]))
            found = arrs.get((dep["id"], key))
            verified = found is not None
            unit = found["id"] if found else f"sgf:arr:{raw['V3']}:{raw['V4']}"
            name = found["historical_name"] if found else raw["V6"]
            wwo, parent, kind = (unit if found else None), dep["id"], "admin"
        year = FR_DATES[0] if raw["field"] in ("V132", "V21", "V114") else FR_DATES[1]
        locator = f"REC_T{raw['table']}.dbf record {raw['record']}, V3={raw['V3']} V4={raw['V4']} V6={raw['V6']}, {raw['field']}"
        definition = "SGF census: legal population within contemporaneous metropolitan enumeration units, including persons counted separately."
        row = observation(unit, name, parent, kind, int(raw["value"]), year, FR_SOURCE, locator, definition,
                          "census", "historical_identity" if verified else "unmapped", "official_transcription",
                          administrative_level=int(level), source_name=raw["V6"])
        if wwo:
            row["wwo_id"] = wwo
        out.append(row)
        if level != "2":
            pairs.setdefault(unit, []).append(row)
    estimates = [estimate(pair) for pair in pairs.values()]
    benchmark = next(row for row in estimates if row["unit_id"] == country)
    opening_group(country, benchmark, [r for r in estimates if r["kind"] == "admin"],
                  {deps[code]["id"]: places for code, places in FR_PLACES.items()}, "france_opening.json")
    return out + estimates


def french_arrondissement_references(records):
    controls = {}
    departments = defaultdict(lambda: defaultdict(dict))
    for row in records:
        if row["source_id"] != FR_SOURCE:
            continue
        if row["administrative_level"] == 1:
            controls[row["unit_id"], row["date"]] = row["population_value"]
        if row["administrative_level"] == 2:
            departments[row["parent_id"]][row["unit_id"]][row["date"]] = row

    first, last = map(date.fromisoformat, FR_DATES)
    elapsed, span = (OPENING - first).days, (last - first).days
    references = []
    for department, series in departments.items():
        if any(set(pair) != set(FR_DATES) or any(row.get("wwo_id") != unit for row in pair.values())
               for unit, pair in series.items()):
            continue
        if any(sum(pair[d]["population_value"] for pair in series.values()) != controls[department, d]
               for d in FR_DATES):
            continue
        floor = {}
        remainders = {}
        for unit, pair in series.items():
            a, b = (pair[d]["population_value"] for d in FR_DATES)
            floor[unit], remainders[unit] = divmod(a * (span - elapsed) + b * elapsed, span)
        control = controls[department, OPENING.isoformat()]
        extra = control - sum(floor.values())
        if not 0 <= extra <= len(floor):
            raise ValueError(f"Arrondissement estimates do not reconcile to {department}")
        for unit in sorted(remainders, key=lambda unit: (-remainders[unit], unit))[:extra]:
            floor[unit] += 1
        for unit, pair in series.items():
            row = estimate(pair.values())
            row.update(
                population_value=floor[unit], method="linear_daily_interpolation_within_department",
                control_unit_id=department, control_population_value=control,
                aggregation="contained_arrondissement_reference_never_add",
                quality_note=("The two source partitions close to the published department totals. "
                              "Largest remainders reconcile to the department opening estimate. "
                              "Timing of boundary changes and interpolation error have no quantified interval."),
            )
            references.append(row)
    return references


CONTINENTS = {
    "Africa": "Algeria|Algiers|Egypt|Madagascar|Mauritius|Morocco|Nigeria|South Africa|Sudan|Tunisia",
    "North America":"Canada|Cuba|El Salvador|Guatemala|Haiti|Mexico|Trinidad and Tobago|United States of America",
    "South America":"Argentina|Bolivia|Brazil|Chile|Colombia|Columbia|Ecuador|Guyana|Paraguay|Peru|Uraguay|Venezuela",
    "Oceania":"Australia|New Zealand",
    "Europe":"Austria|Belarus|Belgium|Britain|Bulgaria|Crimea|Croatia|Czech Republic|Denmark|Estonia|Finland|France|Germany|Greece|Hungary|Ireland|Italy|Latvia|Lithuania|Malta|Netherlands|Norway|Poland|Portugal|Republic of Moldova|Romania|Russian Federation|Serbia|Slovakia|Spain|Sweden|Switzerland|Ukraine|United Kingdom|Wales",
    "Asia":"Afghanistan|Azerbaijan|China|Georgia|India|Indonesia|Iran|Iraq|Israel|Japan|Lebanon|Malaysia|Myanmar|Pakistan|Philippines|Republic of Korea|Saudi Arabia|Singapore|Sri Lanka|Syria|Taiwan|Thailand|Turkey|Uzbekistan|Vietnam|Yemen",
}
CITY_ALIASES = {"Gent":"ghent", "Brussel":"brussels", "Saint Petersburg":"st_petersburg",
                "Washington D.C.":"washington", "Calcutta":"kolkata"}
CITY_COUNTRIES = {"alexandria":"khedivate_of_egypt", "kolkata":"cshapes_gw_750",
                  "vienna":"austria_hungary", "london":"british_isles_1900", "istanbul":"ottoman_empire",
                  "new_york":"united_states_1900", "washington":"united_states_1900", "buenos_aires":"argentina_1900",
                  "strasbourg":"german_empire", "cologne":"german_empire", "berlin":"german_empire",
                  "st_petersburg":"russian_empire", "moscow":"russian_empire", "beijing":"qing_empire",
                  "tokyo":"empire_of_japan","ghent":"kingdom_of_belgium","brussels":"kingdom_of_belgium","antwerp":"kingdom_of_belgium"}
# Cities with the same published name in different countries must be resolved by both fields.
CITY_COUNTRY_LABELS = {"london":"United Kingdom","alexandria":"Egypt","washington":"United States of America",
                       "new_york":"United States of America","brest":"France","paris":"France"}
DISPUTED = {
    "Barrow": "Publisher places Barrow (Alaska) at 71.29 N. Historical place unresolved.",
    "St. Helens": "Source geocode is Oregon. U.S. Census Bulletin 65, Table 8 gives 258 persons there in 1900.",
    "Lawrence": "Source geocode is Kansas. U.S. Census Bulletin 24, Table 5 gives 10,862 persons there in 1900.",
    "Dayton": "Named Ohio, but the printed coordinates match Dayton, Kentucky. US Census 2024 Gazetteer GEOIDs 2120350 and 3921000.",
    "Minneapolis": "Named Minnesota, but the printed latitude is 39.12194; the US Census Gazetteer places the city near 44.96 N, GEOID 2743000.",
    "Richmond": "Named Virgina [sic], but the printed longitude is east; the US Census Gazetteer gives 77.48 W, GEOID 5167000.",
    "Toledo": "Named Ohio, but the compiled point is about 34 km west of the US Census Gazetteer representative point, GEOID 3977000.",
}


def cities():
    geo = {label: region for region, labels in CONTINENTS.items() for label in labels.split("|")}
    city_ids = {row["id"] for row in read_json(MAP / "cities.json")["cities"]}
    french_places = {city for names in FR_PLACES.values() for city in names}
    polities = {row["id"]: row["source_name"] for row in read_json(MAP / "historical/political_units_1900.json")["units"]}
    out = []
    for raw in read_csv("chandler_1900.csv"):
        name, country = raw["City"].strip(), raw["Country"].strip()
        geocode_note = DISPUTED.get(name) if country == "United States of America" else None
        region = geo[country]
        if country == "Turkey" and name in {"Edirne", "Istanbul"}:
            region = "Europe"
        if name in {"Omsk", "Tomsk", "Yekaterinburg"} and country == "Russian Federation":
            region = "Asia"
        slug = CITY_ALIASES.get(name, name.lower().replace(" ", "_"))
        wwo = slug if slug in city_ids and country == CITY_COUNTRY_LABELS.get(slug, country) else None
        parent = "country_fra" if wwo in french_places else CITY_COUNTRIES.get(wwo)
        if parent and parent not in polities:
            raise ValueError(parent)
        locator = f"chandlerV2.csv data record {raw['record']}, {name} ({country}), AD_1900"
        row = observation("reba:chandler:" + raw["record"], name, parent, "city", int(raw["AD_1900"]), "1900",
                          "reba_chandler_1900", locator, "Historically compiled urban settlement; the territorial extent can include suburbs and differs by city.",
                          "historical_compilation", "place_identity_only" if wwo else "unmapped",
                          "disputed_geocode" if geocode_note else "compiled_estimate", region,
                          source_country_label=country, source_alternate_name=raw["OtherName"].strip(),
                          source_geocode_certainty=int(raw["Certainty"]), latitude=float(raw["Latitude"]),
                          longitude=float(raw["Longitude"]), aggregation="non_additive")
        if wwo:
            row["wwo_id"] = "place:" + wwo
        if geocode_note:
            row["quality_note"] = geocode_note
        out.append(row)
    return out


def german():
    registry = {x["id"]: x for x in read_json(MAP / "historical/german_administration_1900_identity.json")["units"]}
    country = "german_empire"
    out, estimates = [], []
    for raw in read_csv("german_census.csv"):
        ident = raw["unit"]
        if ident == "reich":
            unit, name, kind, parent, wwo, level = country, "Deutsches Reich", "country", None, "state:" + country, 0
        else:
            unit = wwo = "administrative_region:germany_" + ident
            entry = registry[unit]
            name, kind, parent, level = entry["historical_name"], "admin", entry["parent_region_id"] or country, entry["level"]
        pair = []
        for date_str in DE_DATES:
            locator = f"Statistisches Jahrbuch 1902, printed p. 1, I.1, row {raw['printed_name']}, {date_str}"
            pair.append(observation(unit, name, parent, kind, int(raw[date_str]), date_str, DE_SOURCE,
                                    locator, "Ortsanwesende Bevölkerung: population present within the European census unit.",
                                    "census", "historical_identity", "official_census", wwo_id=wwo, administrative_level=level))
        out.extend(pair)
        estimates.append(estimate(pair))
    benchmark = next(r for r in estimates if r["unit_id"] == country)
    places = {"administrative_region:germany_preussen":["berlin","cologne"],
              "administrative_region:germany_elsass_lothringen":["strasbourg"]}
    opening_group(country, benchmark, [r for r in estimates if r["administrative_level"] == 1], places, "germany_opening.json")
    return out + estimates



if __name__ == "__main__":
    records = french() + german() + cities()
    records.extend(french_arrondissement_references(records))
    with (ROOT / "observations.jsonl").open("w", encoding="utf-8", newline="\n") as stream:
        for record in records:
            stream.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")
