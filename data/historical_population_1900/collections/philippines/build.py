"""Normalize the Philippine Census of 1903, Volume II, General Table 1."""

import csv
import json
import re
import unicodedata
from pathlib import Path


HERE = Path(__file__).resolve().parent
SOURCE = "ph_census_1903_vol2"
ROOT = "ph_archipelago_census_1903"


def identifier(name):
    ascii_name = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    return "ph_1903_" + re.sub(r"[^a-z0-9]+", "_", ascii_name.lower()).strip("_")


def main():
    observations = []
    with (HERE / "table_1.csv").open(encoding="utf-8", newline="") as raw:
        for row in csv.DictReader(raw):
            name, scope = row["name"], row["scope"]
            national = scope == "archipelago"
            definition = (
                "Population of the 1903 Philippine census reporting area. It includes "
                "population enumerated or estimated on the separate village schedule."
            )
            if name == "Marinduque":
                definition += " Subprovince of Tayabas. Table 1 reports it separately."
            if name == "Tayabas":
                definition += " Excludes the separately reported subprovince of Marinduque."
            unit = dict(
                unit_id=ROOT if national else identifier(name), name=name,
                parent_id=None if national else ROOT,
                kind="territory" if national else "city" if scope == "city" else "admin",
                population_value=int(row["total"]), lower=None, upper=None,
                date="1903-03-02", source_id=SOURCE,
                locator=f"Vol. II, p. 123, General Table 1, {name}",
                definition=definition, method="census enumeration and published village estimates",
                mapping_status="statistical_only", quality="primary_census", region="Asia",
                reporting_area_type=scope,
                source_classification={
                    "Civilized": int(row["civilized"]), "Wild": int(row["wild"]),
                },
            )
            if national:
                unit["candidate_polity_ids"] = ["cshapes_gw_840"]
            observations.append(unit)

    with (HERE / "observations.jsonl").open("w", encoding="utf-8", newline="\n") as out:
        for row in observations:
            out.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")


if __name__ == "__main__":
    main()
