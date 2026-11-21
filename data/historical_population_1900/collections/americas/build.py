"""Build normalized records from the retained Americas census table extracts."""

import csv
import json
import re
import unicodedata
from datetime import date
from fractions import Fraction
from pathlib import Path

HERE = Path(__file__).resolve().parent
RAW = HERE / "raw"
US_MAINLAND = "united_states_1900"
US_SOURCE = "us_twelfth_census_vol1"
US_TOTAL_SOURCE = "us_twelfth_census_vol2"
US_DATES = ("1890-06-02", "1900-06-01")
TARGET_DATE = "1900-01-01"
US_TOTALS = (62_947_714, 75_994_575)
US_DIVISION_TOTALS = {
    "North Atlantic": (17_401_545, 17_406_969, 21_046_695),
    "South Atlantic": (8_857_920, 8_857_922, 10_443_480),
    "North Central": (22_362_279, 22_410_417, 26_333_004),
    "South Central": (10_972_893, 11_170_137, 14_080_047),
    "Western": (3_027_613, 3_102_269, 4_091_349),
}
US_TERRITORY_GROUP = "us_oklahoma_and_indian_territories"
US_PLACE_IDS = {
    "us_district_of_columbia": ["place:washington"],
    "us_state_new_york": ["place:new_york", "place:port_new_york"],
}
US_URBAN_SOURCE = "us_census_gibson_urban"
US_URBAN_STATES = dict(line.split(" ", 1) for line in """AL Alabama
AR Arkansas
CA California
CO Colorado
CT Connecticut
DC District of Columbia
DE Delaware
GA Georgia
IA Iowa
IL Illinois
IN Indiana
KS Kansas
KY Kentucky
LA Louisiana
MA Massachusetts
MD Maryland
ME Maine
MI Michigan
MN Minnesota
MO Missouri
NE Nebraska
NH New Hampshire
NJ New Jersey
NY New York
OH Ohio
OR Oregon
PA Pennsylvania
RI Rhode Island
SC South Carolina
TN Tennessee
TX Texas
UT Utah
VA Virginia
WA Washington
WI Wisconsin
WV West Virginia""".splitlines())
MEXICO = "mexican_republic"
MX_SOURCE = "mx_yearbook_1941_table11"
MX_DATES = ("1895-10-20", "1900-10-28")
MX_TOTALS = (12_632_427, 13_607_272)
CANADA = "dominion_of_canada"
CA_SOURCE = "ca_census_1901_vol1_table1"
CA_DATES = ("1891-04-06", "1901-03-31")
BRAZIL = "brazil_1900"
BR_SOURCE = "br_dge_1908_state_table"
BR_DATES = ("1890-12-31", "1900-12-31")


def read_csv(name):
    with (RAW / name).open(encoding="utf-8", newline="") as stream:
        return list(csv.DictReader(stream))


def slug(value):
    normalized = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "_", normalized.lower()).strip("_")


def us_admin_id(name, kind):
    prefix = "us_state" if kind == "state" else "us"
    return f"{prefix}_{slug(name)}"


def record(unit_id, name, parent_id, kind, value, when, source_id, locator,
           definition, method, mapping_status, quality, region, wwo_id=None):
    row = {
        "unit_id": unit_id,
        "name": name,
        "parent_id": parent_id,
        "kind": kind,
        "population_value": int(value),
        "lower": None,
        "upper": None,
        "date": when,
        "source_id": source_id,
        "locator": locator,
        "definition": definition,
        "method": method,
        "mapping_status": mapping_status,
        "quality": quality,
        "region": region,
    }
    if wwo_id:
        row["wwo_id"] = wwo_id
    return row


def us_records():
    raw = read_csv("us_states.csv")
    columns = ("population_1890_general", "population_1890", "population_1900")
    for division, expected in US_DIVISION_TOTALS.items():
        rows = [row for row in raw if row["division"] == division]
        actual = tuple(sum(int(row[key] or 0) for row in rows) for key in columns)
        if actual != expected:
            raise ValueError(f"{division}: expected {expected}, found {actual}")

    groups = {}
    observations = []
    for row in raw:
        name = row["name"]
        unit_id = us_admin_id(name, row["kind"])
        boundary_changed = name in {"Indian Territory", "Oklahoma Territory"}
        parent_id = US_TERRITORY_GROUP if boundary_changed else US_MAINLAND
        group_id = US_TERRITORY_GROUP if boundary_changed else unit_id
        group_name = "Oklahoma Territory and Indian Territory" if boundary_changed else name
        group = groups.setdefault(group_id, (group_name, [0, 0]))
        for index, when in enumerate(US_DATES):
            value = int(row[columns[index + 1]])
            group[1][index] += value
            definition = f"{row['kind'].capitalize()} total in Twelfth Census geography."
            if boundary_changed:
                definition += " Use the two territories jointly across the decade."
            if index == 0:
                definition += " Includes the published special enumeration."
            observations.append(record(
                unit_id, name, parent_id, "admin", value, when, US_SOURCE,
                f"Vol. I, p. {row['printed_page']}, Table V, {row['division']}, {name}, "
                f"{when[:4]} {'total' if index == 0 else 'column'}",
                definition, "census_count",
                "boundary_change" if boundary_changed else "statistical_only",
                "primary_census", "North America",
            ))

    division_totals = tuple(sum(counts[index] for _, counts in groups.values())
                            for index in range(len(US_DATES)))
    if len(raw) != 50 or len(groups) != 49 or division_totals != US_TOTALS:
        raise ValueError(f"Unexpected US partitions: {len(raw)}, {len(groups)}, {division_totals}")

    territory_name, territory_counts = groups[US_TERRITORY_GROUP]
    national_locator = "Vol. II, Table I, Total population, mainland of the United States"
    for when, national, territories in zip(US_DATES, US_TOTALS, territory_counts):
        observations.append(record(
            US_MAINLAND, "Continental United States", None, "country", national, when,
            US_TOTAL_SOURCE, national_locator,
            "Enumerated contiguous mainland; covers 45 states, DC, and "
            "four enumerated territories in 1900. Excludes Alaska, Hawaii, overseas "
            "military and affiliated persons, and other overseas territories.",
            "census_count", "matched", "primary_census", "North America", US_MAINLAND,
        ))
        observations.append(record(
            US_TERRITORY_GROUP, territory_name, US_MAINLAND, "admin", territories, when,
            US_SOURCE, "Vol. I, p. xxii, Table V, Oklahoma and Indian Territory rows",
            "Combined extent of the two territories. Federal census assigns Greer County "
            "to Oklahoma in 1890. Later intraterritorial land transfers are internal.",
            "sum_of_census_counts", "statistical_only", "primary_census", "North America",
        ))

    opening = interpolate(
        US_MAINLAND, US_SOURCE,
        "Vol. I, Table V, pp. xxi-xxii; Vol. II, Table I mainland totals",
        US_DATES, groups, "Oklahoma Territory and Indian Territory form one statistical unit.",
        US_PLACE_IDS,
    )
    return observations, opening


def us_ranked_places():
    cell = re.compile(r"(\d+)\s{2,}(.+?)(?:,\s*|\s+)([A-Z]{2})(\s*\*)?\.{2,}\s+([\d,]+)")
    places = {
        "us_city_new_york_new_york": "place:new_york",
        "us_city_district_of_columbia_washington": "place:washington",
    }
    observations = []
    for table, when in zip((12, 13), US_DATES):
        source_text = (RAW / f"us_urban_tab{table}.txt").read_text(encoding="ascii")
        rows = sorted(cell.findall(source_text), key=lambda row: int(row[0]))
        if [int(row[0]) for row in rows] != list(range(1, 101)):
            raise ValueError(f"Incomplete United States urban rank table {table}")
        for rank, designation, state_code, note, population in rows:
            state = slug(US_URBAN_STATES[state_code])
            name, _ = designation.rsplit(" ", 1)
            label = slug(name)
            unit = f"us_city_{state}_{label}"
            parent = "us_district_of_columbia" if state_code == "DC" else f"us_state_{state}"
            definition = f"{designation} in its {when[:4]} legal limits."
            if note:
                definition += " The source flags a special note on this place."
            status = "statistical_only"
            if name == "New York" and when == US_DATES[0]:
                unit = "us_city_new_york_pre_1898"
                name = "New York City (pre-1898 jurisdiction)"
                status = "boundary_change"
            elif name == "New York":
                name = "New York City (five boroughs)"
            elif name == "Wilkes-Barre":
                unit = "us_city_pennsylvania_wilkesbarre"
            observations.append(record(
                unit, name, parent, "city", population.replace(",", ""), when,
                US_URBAN_SOURCE, f"Table {table}, rank {rank}, {designation}, {state_code}",
                definition, "census_count", status, "official_retrospective", "North America",
                places.get(unit),
            ))
    observations.append(record(
        "us_city_honolulu_1900", "Honolulu", "cshapes_gw_4", "city", 39_306, US_DATES[1],
        US_URBAN_SOURCE, "Table 13, footnote 1",
        "Published Honolulu figure excluded from the table's national rank.",
        "census_count", "statistical_only", "official_retrospective", "Oceania",
    ))
    return observations


def interpolate(root, source, locator, dates, groups, boundary_note, place_ids):
    start, finish = (date.fromisoformat(value) for value in dates)
    weight = Fraction((date.fromisoformat(TARGET_DATE) - start).days, (finish - start).days)
    shares = {
        unit_id: counts[0] + (counts[1] - counts[0]) * weight
        for unit_id, (_, counts) in groups.items()
    }
    total = round(sum(shares.values()))
    floors = {unit_id: value.numerator // value.denominator for unit_id, value in shares.items()}
    order = sorted(shares, key=lambda unit_id: (floors[unit_id] - shares[unit_id], unit_id))
    for unit_id in order[:total - sum(floors.values())]:
        floors[unit_id] += 1
    return {
        "unit_id": root,
        "date": TARGET_DATE,
        "population_value": total,
        "source_id": source,
        "locator": locator,
        "endpoint_dates": dates,
        "country_endpoint_values": [sum(counts[index] for _, counts in groups.values())
                                    for index in range(len(dates))],
        "method": f"Linear interpolation by elapsed days ({weight}), followed by "
                  f"largest-remainder rounding to the national total. {boundary_note}",
        "units": [
            {"unit_id": unit_id, "name": groups[unit_id][0], "population_value": floors[unit_id],
             "endpoint_values": groups[unit_id][1],
             **({"place_ids": place_ids[unit_id]} if unit_id in place_ids else {})}
            for unit_id in sorted(floors)
        ],
    }


def comparable_opening(rows, root, source, dates, count, totals, locator, boundary_note,
                       overlapping_rows=()):
    groups = {}
    for row in rows:
        if (row["parent_id"] != root or row["source_id"] != source
                or row["unit_id"] in overlapping_rows):
            continue
        name, endpoints = groups.setdefault(row["unit_id"], (row["name"], {}))
        if name != row["name"] or row["date"] in endpoints:
            raise ValueError(f"Conflicting subdivision: {row['unit_id']}")
        endpoints[row["date"]] = int(row["population_value"])
    comparable = {
        identifier: (name, [endpoints[when] for when in dates])
        for identifier, (name, endpoints) in groups.items()
    }
    actual = tuple(sum(counts[index] for _, counts in comparable.values()) for index in range(len(dates)))
    if len(comparable) != count or actual != totals:
        raise ValueError(f"Unexpected {root} partitions: {len(comparable)}, {actual}")
    return interpolate(root, source, locator, dates, comparable, boundary_note, {})


def whole_opening(root, source, locator, dates, counts, note, precision=None):
    group = interpolate(root, source, locator, dates, {root: (root, counts)}, note, {})
    group["units"] = []
    group["method"] = group["method"].replace(
        "followed by largest-remainder rounding to the national total.", "rounded once."
    )
    if precision:
        group["endpoint_date_precision"] = precision
    return group


def main():
    observations, opening = us_records()
    observations.extend(us_ranked_places())
    census_rows = read_csv("censuses.csv")
    for row in census_rows:
        observations.append(record(
            row["unit_id"], row["name"], row["parent_id"] or None, row["kind"],
            row["population_value"], row["date"], row["source_id"], row["locator"],
            row["definition"], row["method"], row["mapping_status"], row["quality"],
            row["region"], row["wwo_id"],
        ))
    openings = {
        "us_opening.json": opening,
        "mexico_opening.json": comparable_opening(
            census_rows, MEXICO, MX_SOURCE, MX_DATES, 30, MX_TOTALS,
            "pp. 24-25, Table 11, 1895 and 1900 columns; INEGI 1996, p. 68",
            "Baja California is combined across both districts. Yucatán includes the later Quintana Roo.",
        ),
        "canada_opening.json": comparable_opening(
            census_rows, CANADA, CA_SOURCE, CA_DATES, 8, (4_833_239, 5_371_315),
            "Vol. I, Table I, pp. 2-3, 1891 and 1901 columns",
            "Quebec and the unorganized territories are combined across the 1898 boundary change. "
            "The remaining four territories are combined on the 1901 electoral limits.",
            overlapping_rows=("ca_quebec", "ca_unorganized_territories"),
        ),
        "brazil_opening.json": comparable_opening(
            census_rows, BRAZIL, BR_SOURCE, BR_DATES, 21, (14_333_915, 17_318_556),
            "pp. 73-74, População do Brazil por Estados, 1890 and 1900 columns; "
            "Distrito Federal and Brazil total footnotes",
            "Acre is outside both endpoints. The 1900 Federal District endpoint is the official "
            "estimate published in 1908. Pará follows the reported administrative totals.",
        ),
        "hawaii_opening.json": whole_opening(
            "cshapes_gw_4", US_SOURCE, "pp. xix-xx, Table III, Hawaii, with footnote",
            ("1890-12-28", "1900-06-01"), (89_990, 154_001),
            "Includes the Hawaiian Islands as reported by both censuses. Hawaii is outside the mainland group.",
        ),
        "alaska_opening.json": whole_opening(
            "cshapes_gw_3", US_SOURCE, "p. xx, Table III, Alaska; Census Bureau Alaska fieldwork chronology",
            US_DATES, (32_052, 63_592),
            "Federal Census Days serve as nominal interpolation anchors. Alaska's "
            "1890 enumeration ran from February 1890 into 1891, and 1900 fieldwork "
            "ran from July 1899 through October 1900.",
            precision=["nominal national reference day", "nominal national reference day"],
        ),
        "cuba_opening.json": whole_opening(
            "cuba_occupation_1900", "cu_census_1907_ch4",
            "1907 census, Population Tables, No. 1 and No. 2, total Cuba",
            ("1899-10-16", "1907-09-30"), (1_572_797, 2_048_980),
            "Uses the two census reference days. Includes the Isle of Pines and adjacent keys.",
        ),
        "newfoundland_opening.json": whole_opening(
            "colony_of_newfoundland", "nf_census_1901_table1",
            "1901 Census, Table I, p. viii, grand total; Newfoundland Historical Statistics "
            "(1994), Table A-1, footnote 2 for dates",
            ("1891-06-01", "1901-06-01"), (202_040, 220_984),
            "Uses the June 1 historical reference-day convention reported by the "
            "Newfoundland Statistics Agency. Original comparative table identifies census years. "
            "Both totals include the Labrador area in the historical returns.",
            precision=["June 1 by official retrospective convention", "June 1 by official retrospective convention"],
        ),
    }
    for filename, group in openings.items():
        (HERE / filename).write_text(
            json.dumps(group, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    with (HERE / "observations.jsonl").open("w", encoding="utf-8", newline="\n") as stream:
        for row in observations:
            print(json.dumps(row, ensure_ascii=False, separators=(",", ":")), file=stream)


if __name__ == "__main__":
    main()
