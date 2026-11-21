"""Write dated Danish census observations from the numerical transcription."""
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
TABLES = {
    "A": ("177", "1890-02-01", "1901-02-01", "Europe"),
    "B": ("179", "1890-11-01", "1901-11-01", "Europe"),
    "C": ("182", "1890-10-01", "1901-10-01", "North America"),
    "D": ("183", "1890-10-09", "1901-02-01", "North America"),
}

# Source terminology and counts. In 1890 the southern row excludes East Greenland.
GREENLAND = {
    "dk_greenland": ((309, 10207), (272, 11621)),
    "dk_greenland_north": ((84, 4600), (79, 5138)),
    "dk_greenland_south": ((225, 5607), None),
    "dk_greenland_se": (None, (193, 6483)),
    "dk_greenland_east": (None, (10, 431)),
}


def observations():
    with (ROOT / "census_facts.csv").open(encoding="utf-8", newline="") as source:
        for raw in csv.DictReader(source):
            table, unit = raw["table"], raw["unit_id"]
            page, earlier, later, region = TABLES[table]
            for index, (date, value) in enumerate(((earlier, raw["earlier_total"]), (later, raw["later_total"]))):
                if not value:
                    continue
                definition = "Both sexes in the named census territory or subdivision at the printed census date."
                if table == "C":
                    definition = ("Danish census coverage in Greenland. East Greenland was first counted in 1901."
                                  " The table distinguishes Europeans and Greenlanders including persons of mixed ancestry.")
                if unit == "dk_island_ne_1890_residual":
                    definition = "Rural districts including the future town of Seyðisfjörður. It gained town status in 1894."
                row = dict(unit_id=unit, name=raw["name"], parent_id=raw["parent_id"], kind=raw["kind"],
                           population_value=int(value), population_lower=None, population_upper=None, date=date,
                           source_id="dk_yearbook_1903_dependencies", locator=f"Tabel C, {table}.1, p. {page}, {raw['source_row']}, {date}",
                           definition=definition, method="published_census_count", mapping_status="historical_statistical_unit",
                           quality="official_census", region=region)
                if unit == "iceland_under_denmark":
                    row["wwo_id"] = "state:iceland_under_denmark"
                    row["mapping_status"] = "historical_identity"
                if index and raw["later_male"]:
                    row["sex"] = {"male": int(raw["later_male"]), "female": int(raw["later_female"])}
                if table == "C":
                    european, indigenous = GREENLAND[unit][index]
                    row["source_group_counts"] = {"Europæere": european, "Grønlændere og Blandinger": indigenous}
                if index and unit == "dk_west_indies":
                    row["birthplace_counts"] = {"Danish West Indies": 23847, "Denmark proper": 427, "elsewhere": 6253}
                    row["other_West_Indian_islands_within_elsewhere"] = 5591
                    row["locator"] += "; D.2, p. 184, note 1"
                if unit == "dk_greenland_east":
                    row["locator"] += "; C.2 note 1 (431 indigenous persons)"
                yield row


if __name__ == "__main__":
    with (ROOT / "observations.jsonl").open("w", encoding="utf-8", newline="\n") as out:
        for record in observations():
            out.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")

