"""Record Scottish civil county totals on the boundaries used for comparison in 1901."""
import csv
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
SOURCE = "scotland_civil_counties_census_1901"
DATES = ("1891-04-05", "1901-03-31")


def main():
    with (HERE / "raw/civil_counties.tsv").open(encoding="utf8", newline="") as source:
        counts = list(csv.DictReader(source, delimiter="\t"))
    with (HERE / "observations.jsonl").open("w", encoding="utf8", newline="\n") as output:
        for county in counts:
            for census_date in DATES:
                row = dict(
                    unit_id=county["unit_id"], name=county["name"], parent_id="uk_scotland",
                    kind="admin", population_value=int(county[census_date]),
                    population_lower=None, population_upper=None, date=census_date,
                    source_id=SOURCE, locator=f"Vol. 1, Table 1_1, {county['name']}, both sexes",
                    definition="Persons enumerated in the civil county, on the comparison geography of the 1901 report.",
                    method="published_census_return", mapping_status="statistical_only",
                    quality="historical_census", region="Europe",
                )
                output.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")


if __name__ == "__main__":
    main()
