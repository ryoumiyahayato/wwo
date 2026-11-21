"""Build the Romanian Old Kingdom census evidence and opening from archived figures."""
import csv
import json
from datetime import date
from fractions import Fraction
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = "kingdom_of_romania"
SOURCE = "ro_huber_1913_census_comparison"
LOCATOR = "p. 345, Population de droit, 1899 column"
OPENING_DATE = date(1900, 1, 1)
REGIONS = (
    ("Moldavie", "ro_1899_moldova", "Moldavia (Romanian Old Kingdom)",
     "De jure population of the Old Kingdom's historic Moldavian region. It excludes Austrian Bukovina and Russian Bessarabia."),
    ("Grande-Valachie", "ro_1899_muntenia", "Muntenia",
     "De jure population of Muntenia, the east-Wallachian historical region containing Bucharest."),
    ("Olténie", "ro_1899_oltenia", "Oltenia",
     "De jure population of Oltenia, the west-Wallachian historical region."),
    ("Dobroudja", "ro_1899_northern_dobruja", "Northern Dobruja",
     "De jure population of Romanian Dobruja in its pre-1913 boundaries. It excludes Southern Dobruja."),
)


def numbers(filename, key):
    with (HERE / "raw" / filename).open(encoding="utf-8", newline="") as infile:
        return {row[key]: int(row["population"]) for row in csv.DictReader(infile)}


def observation(unit_id, name, population, definition, locator, parent_id=None):
    return dict(
        unit_id=unit_id, name=name, parent_id=parent_id,
        kind="admin" if parent_id else "country", population_value=population,
        lower=None, upper=None, date="1899-12", source_id=SOURCE, locator=locator,
        definition=definition, method="census enumeration, definitive count reproduced in the official comparative series",
        mapping_status="statistical_only" if parent_id else "mapped_wwo_polity",
        quality="official_census_reproduced", region="Europe",
    )


def main():
    definitive = numbers("1899_census_comparison.csv", "printed_row")
    provisional = numbers("1899_provisional_residents.csv", "printed_row")
    country = observation(
        ROOT, "Kingdom of Romania", definitive["Roumanie"],
        "De jure population of the Romanian Old Kingdom before its 1913 and 1918 territorial gains. Source date is December 1899 in the local calendar.",
        LOCATOR + ", Roumanie and its communes rurales/urbaines",
    ) | dict(
        wwo_id=ROOT,
        source_classification={label: definitive[label] for label in ("communes rurales", "communes urbaines")},
    )
    regions = [
        observation(unit_id, name, definitive[printed], definition, LOCATOR + ", " + printed, ROOT)
        for printed, unit_id, name, definition in REGIONS
    ]
    stable_country = country | dict(
        population_value=provisional["stabili"], source_id="ro_transilvania_1900_provisional_returns",
        locator="pp. 187–188, provisional communal tabulation, stable residents",
        definition="Provisional Old Kingdom total of residents classified as stable. It excludes persons recently or temporarily present in their commune.",
        method="census enumeration, provisional tabulation condensed from the official report",
        quality="provisional_census_reproduced",
        source_classification={label: provisional[label] for label in ("commune rurale", "commune urbane")},
    )
    observations = [country, *regions, stable_country]
    with (HERE / "observations.jsonl").open("w", encoding="utf-8", newline="\n") as outfile:
        for row in observations:
            outfile.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")

    ft = numbers("ft_romania_comparison.csv", "year")
    left, right = date(1899, 7, 1), date(1900, 7, 1)
    fraction = Fraction((OPENING_DATE - left).days, (right - left).days)
    opening = dict(
        unit_id=ROOT, date=OPENING_DATE.isoformat(), population_value=country["population_value"],
        source_id=SOURCE, locator=LOCATOR + "; enumeration window in Transilvania (July 1900), pp. 186–187",
        method="carry_forward near-date baseline from the December 1899 Old Kingdom census. Fieldwork began December 1 Julian (December 13 Gregorian), with a planned December 10 Julian finish. Ialomița returns extended to January 3 Gregorian and Bucharest also reported delays. The opening date is January 1 Gregorian. Timing, enumeration and population change introduce unquantified error.",
        scope="Romanian Old Kingdom, before the 1913 and 1918 territorial gains. Historic regions are the only population partitions used.",
        uncertainty_kind="Census fieldwork straddled the opening date. Enumeration coverage and timing error have no quantified interval.",
        alternative_research_value=round(ft["1899"] + (ft["1900"] - ft["1899"]) * fraction),
        alternative_research_unit_id="ft_romania",
        units=[{key: row[key] for key in ("unit_id", "name", "population_value")} for row in regions],
    )
    (HERE / "romania_opening.json").write_text(
        json.dumps(opening, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n",
    )


if __name__ == "__main__":
    main()
