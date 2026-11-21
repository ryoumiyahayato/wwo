"""Reproduce the reported census populations and 23 opening divisions offline."""

from datetime import date, timedelta
from fractions import Fraction
import json
from pathlib import Path

OUT = Path(__file__).resolve().parent
AUSTRIAN_SOURCE = "ah_galician_statistical_bureau_1913"
HUNGARIAN_SOURCE = "ah_hungarian_statistical_yearbook_1901"
COMBINED_SOURCE = "ah_census_fassmann_table7"
REALM = "ah_dual_monarchy_excluding_bosnia"
WWO_POLITY = "austria_hungary"
AUSTRIA = "ah_cisleithania"
HUNGARY = "ah_lands_of_st_stephen"
HUNGARY_PROPER = "ah_hungary_including_fiume"
CENSUS_DATES = [date(1890, 12, 31), date(1900, 12, 31)]
INSTANTS = [d + timedelta(days=1) for d in CENSUS_DATES]
TARGET = date(1900, 1, 1)
WEIGHT = Fraction((TARGET - INSTANTS[0]).days, (INSTANTS[1] - INSTANTS[0]).days)

sources = {s["id"]: s for s in json.loads((OUT / "sources.json").read_text(encoding="utf-8"))}
divisions = [
    (AUSTRIA, "Cisleithania", 23895413, 26150708, AUSTRIAN_SOURCE),
    (HUNGARY, "Lands of the Hungarian Crown", 17463791, 19254559, HUNGARIAN_SOURCE),
]
austrian_lands = [
    ("ah_galicia", "Galicia", 6607816, 7315939),
    ("ah_bukovina", "Bukovina", 646591, 730195),
    ("ah_silesia", "Austrian Silesia", 605649, 680422),
    ("ah_moravia", "Moravia", 2276870, 2437706),
    ("ah_bohemia", "Bohemia", 5843094, 6318697),
    ("ah_lower_austria", "Lower Austria", 2661799, 3100493),
    ("ah_upper_austria", "Upper Austria", 785831, 810246),
    ("ah_salzburg", "Salzburg", 173510, 192763),
    ("ah_tyrol_vorarlberg", "Tyrol and Vorarlberg", 928769, 981949),
    ("ah_styria", "Styria", 1282708, 1356494),
    ("ah_carinthia", "Carinthia", 361008, 367324),
    ("ah_carniola", "Carniola", 498958, 508150),
    ("ah_littoral", "Austrian Littoral", 695384, 756546),
    ("ah_dalmatia", "Dalmatia", 527426, 593784),
]
hungarian_lands = [
    (HUNGARY_PROPER, "Hungary including Fiume", 15261864, 16838255),
    ("ah_croatia_slavonia", "Croatia-Slavonia", 2201927, 2416304),
]
hungarian_statistical_divisions = [
    ("ah_danube_left", "Left bank of the Danube", 1889099, 2049611),
    ("ah_danube_right", "Right bank of the Danube", 2771294, 2923401),
    ("ah_danube_tisza", "Between the Danube and Tisza", 2778514, 3284233),
    ("ah_tisza_right", "Right bank of the Tisza", 1529259, 1674241),
    ("ah_tisza_left", "Left bank of the Tisza", 2076803, 2336104),
    ("ah_tisza_maros", "Tisza–Maros angle", 1918623, 2054712),
    ("ah_transylvania", "Beyond the Királyhágó (Transylvania)", 2267935, 2476998),
    ("ah_fiume", "Fiume town and district", 30337, 38955),
]

observations = []


def record(unit, name, earlier, later, source, parent, kind="admin"):
    for label, value in zip(CENSUS_DATES, [earlier, later]):
        row = {
            "unit_id": unit, "name": name, "parent_id": parent, "kind": kind, "region": "Europe",
            "date": label.isoformat(), "population_value": value, "population_lower": None,
            "population_upper": None, "source_id": source, "locator": sources[source]["locator"],
            "definition": "Population physically present, civilians and military combined, at midnight ending the census date. Bosnia-Herzegovina is outside the two constituent territories.",
            "method": "published_census_population", "quality": "historical_census",
            "mapping_status": "historical_identity_link" if parent is None else "historical_census_division",
        }
        if parent is None:
            row["wwo_id"] = WWO_POLITY
        observations.append(row)


country_values = [41359204, 45405267]
record(REALM, "Austria-Hungary excluding Bosnia-Herzegovina", *country_values, COMBINED_SOURCE, None, "country")
for division in divisions:
    record(*division, REALM)
for parent, rows, source in [
    (AUSTRIA, austrian_lands, AUSTRIAN_SOURCE),
    (HUNGARY, hungarian_lands, HUNGARIAN_SOURCE),
    (HUNGARY_PROPER, hungarian_statistical_divisions, HUNGARIAN_SOURCE),
]:
    for row in rows:
        record(*row, source, parent)

units = []
division_controls = []
leaves_by_division = {
    AUSTRIA: austrian_lands,
    HUNGARY: [*hungarian_statistical_divisions, hungarian_lands[1]],
}
for division_id, division_name, earlier, later, source in divisions:
    leaves = leaves_by_division[division_id]
    estimates = {unit: first + (last - first) * WEIGHT for unit, _, first, last in leaves}
    allocated = {unit: value.numerator // value.denominator for unit, value in estimates.items()}
    control = round(earlier + (later - earlier) * WEIGHT)
    remainder_order = sorted(estimates, key=lambda unit: (allocated[unit] - estimates[unit], unit))
    for unit in remainder_order[:control - sum(allocated.values())]:
        allocated[unit] += 1
    division_controls.append({
        "unit_id": division_id, "name": division_name, "endpoint_values": [earlier, later],
        "population_value": control,
    })
    for unit, name, first, last in leaves:
        row = {
            "unit_id": unit, "name": name, "source_unit_ids": [unit], "source_id": source,
            "locator": sources[source]["locator"], "endpoint_values": [first, last],
            "control_unit_id": division_id, "population_value": allocated[unit],
            "geometry_status": "no_base_map_geometry", "place_ids": [],
        }
        if unit == "ah_lower_austria":
            row["place_ids"] = ["place:vienna"]
            row["place_membership_source"] = "https://www.wien.gv.at/en/education/history-capital"
        units.append(row)

opening = {
    "unit_id": WWO_POLITY, "date": TARGET.isoformat(), "source_id": COMBINED_SOURCE,
    "source_ids": [AUSTRIAN_SOURCE, HUNGARIAN_SOURCE, COMBINED_SOURCE],
    "source_unit_ids": [REALM], "locator": sources[COMBINED_SOURCE]["locator"],
    "census_date_labels": [d.isoformat() for d in CENSUS_DATES],
    "endpoint_dates": [d.isoformat() for d in INSTANTS],
    "country_endpoint_values": country_values,
    "population_value": round(country_values[0] + (country_values[1] - country_values[0]) * WEIGHT),
    "method": "Linear interpolation across 3,287 of 3,652 elapsed days from the midnight ending each census date. The equivalent opening instants are 1 January 1891 and 1901. Round each half to whole persons and apportion its total among its census divisions by largest remainder, with unit ID breaking ties. Both halves exclude separately administered Bosnia-Herzegovina.",
    "division_controls": division_controls,
    "units": units,
}

(OUT / "observations.jsonl").write_text(
    "".join(json.dumps(r, ensure_ascii=False, separators=(",", ":")) + "\n" for r in observations),
    encoding="utf-8",
)
(OUT / "austria_hungary_opening.json").write_text(
    json.dumps(opening, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
)
