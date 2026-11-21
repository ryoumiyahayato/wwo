"""Twelfth Census occupations and the Bureau's 1900 urban/rural series."""
import csv
import json
from pathlib import Path


COLLECTIONS = Path(__file__).resolve().parent / "collections"
DATE = "1900-06-01"
OCCUPATIONS = {
    "agriculture": "Agricultural pursuits",
    "professional": "Professional service",
    "domestic_personal": "Domestic and personal service",
    "trade_transport": "Trade and transportation",
    "manufacturing_mechanical": "Manufacturing and mechanical pursuits",
}
OKLAHOMA = "Oklahoma Territory and Indian Territory"


def table(collection, name):
    with (COLLECTIONS / collection / name).open(encoding="utf8", newline="") as stream:
        return list(csv.DictReader(stream))


def united_states_structure(pools, distribution):
    panels = json.loads((COLLECTIONS / "age_sex" / "us_census_1900_panels.json").read_text(encoding="utf8"))
    scopes = {panel["published_scope"]: panel for panel in panels}
    population = {
        row["panel"]: int(row["both"])
        for row in table("age_sex", "us_census_1900.csv") if row["role"] == "total"
    }
    jobs = {}
    for row in table("us_social", "occupations_1900.csv"):
        categories = {label: int(row[field]) for field, label in OCCUPATIONS.items()}
        if sum(categories.values()) != int(row["gainful_workers"]):
            raise ValueError(f"US census occupation categories do not close for {row['scope']}")
        jobs[row["scope"]] = categories
    jobs[OKLAHOMA] = {
        label: jobs["Oklahoma"][label] + jobs["Indian Territory"][label]
        for label in OCCUPATIONS.values()
    }
    for row in table("us_social", "residence_1900.csv"):
        scope = OKLAHOMA if row["scope"] == "Oklahoma" else row["scope"]
        panel = scopes[scope]
        unit = panel["opening_unit_id"]
        if unit not in pools:
            continue
        observed_total = int(row["total"])
        if observed_total != sum(population[key] for key in panel.get("component_panels", [panel["id"]])):
            raise ValueError(f"US census occupation and residence control mismatch for {scope}")
        source = dict(date=DATE, observed_unit=panel["observed_unit_id"], scope=scope, total=observed_total)
        opening_total = pools[unit]["population_value"]
        yield unit, "occupation", distribution(
            opening_total, **source, classification="us_twelfth_census_gainful_occupations",
            source="us_twelfth_census_table_31_occupations", locator="Table 31, printed pp. 92–93",
            observed_counts=jobs[scope], unknown=observed_total - sum(jobs[scope].values()),
            definition="Primary gainful occupations reported for residents aged 10 or older. "
                       "The unassigned balance includes children and residents without a reported gainful occupation.",
        )
        yield unit, "residence", distribution(
            opening_total, **source, classification="us_census_1900_urban_rural",
            source="us_thirteenth_census_table_36_residence", locator="Table 36, printed p. 56, 1900 columns",
            observed_counts={"Urban": int(row["urban"]), "Rural": int(row["rural"])}, unknown=0,
            definition="1900 Census residents partitioned by the Census Bureau's comparative 1910 urban/rural classification.",
        )
