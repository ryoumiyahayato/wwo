"""Record district totals and the separate Rodrigues returns from both censuses."""
import csv
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
RETURNS = (
    ("1891-04-06", "mauritius_census_1891", "Paragraph 1, district table",
     "Paragraph 50, population of Rodrigues"),
    ("1901-04-01", "mauritius_census_1911_district_comparison", "Statistical Abstracts, Table I, Total Population",
     "Section II, district and dependency comparison, 1901"),
)


def main():
    with (HERE / "raw/mauritius_and_rodrigues.tsv").open(encoding="utf8", newline="") as source:
        counts = list(csv.DictReader(source, delimiter="\t"))
    with (HERE / "observations.jsonl").open("w", encoding="utf8", newline="\n") as output:
        for area in counts:
            is_rodrigues = area["unit_id"] == "mu_rodrigues"
            for census_date, source_id, district_table, island_table in RETURNS:
                table = island_table if is_rodrigues else district_table
                row = dict(
                    unit_id=area["unit_id"], name=area["name"],
                    parent_id="mu_two_islands" if is_rodrigues else "mu_main_island",
                    kind="admin", population_value=int(area[census_date]),
                    population_lower=None, population_upper=None, date=census_date,
                    source_id=source_id, locator=f"{table}, {area['name']}",
                    definition=("Residents enumerated on Rodrigues." if is_rodrigues else
                                "Residents enumerated in the district, including its reported adjacent islets. "
                                "Excludes barracks, shipping and separately reported island dependencies."),
                    method="published_census_return", quality="historical_census", region="Africa",
                    mapping_status="matched_historical_island" if is_rodrigues else "statistical_only",
                )
                output.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")


if __name__ == "__main__":
    main()
