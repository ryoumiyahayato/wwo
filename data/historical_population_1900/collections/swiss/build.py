"""Swiss federal census returns, ordinary residents at the two censuses."""
import csv
import json
from datetime import date
from fractions import Fraction
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = "swiss_confederation"
SOURCE = "swiss_federal_census_comparison_1911"
DAYS = (date(1900, 1, 1) - date(1888, 12, 1)).days
SPAN = (date(1900, 12, 1) - date(1888, 12, 1)).days

def save(name, obj):
    (HERE / name).write_text(json.dumps(obj, indent=2, ensure_ascii=False) + "\n", encoding="utf8")

def build():
    with (HERE / "census.csv").open(encoding="utf8") as f:
        facts = list(csv.DictReader(f))
    dates = ["1888-12-01", "1900-12-01"]
    observations, leaves = [], []
    for r in facts:
        country = r["code"] == "CH"
        key = ROOT if country else "ch_canton_" + r["code"].lower()
        values = [int(r["1888"]), int(r["1900"])]
        exact = values[0] + Fraction(DAYS, SPAN) * (values[1] - values[0])
        locator = f"Table I, p. 104, {r['name']}, Wohnbevölkerung, cols. 6–7"
        for dt, value in zip(dates, values):
            observations.append(dict(unit_id=key, name=r["name"], parent_id=None if country else ROOT,
                kind="country" if country else "admin", population_value=value, date=dt,
                source_id=SOURCE, locator=locator, definition="Population de résidence ordinaire; absent and present residents reconciled. Bern includes the later canton of Jura.",
                method="census", mapping_status="historical_polity" if country else "historical_statistical_identity",
                quality="primary_census", region="Europe"))
        if country:
            total = round(exact)
            bases = values
        else:
            leaves.append((exact, dict(unit_id=key, name=r["name"], population_value=int(exact), endpoint_values=values, locator=locator)))
    for i in range(2):
        if sum(x["endpoint_values"][i] for _, x in leaves) != bases[i]:
            raise ValueError(f"cantons do not reproduce control at {dates[i]}")
    remainder = total - sum(x["population_value"] for _, x in leaves)
    for _, item in sorted(leaves, key=lambda pair: pair[0] % 1, reverse=True)[:remainder]:
        item["population_value"] += 1
    # These are municipality boundaries at the census, not urban agglomerations.
    cities = [("zh", "Zürich", 150703, 142), ("be", "Bern", 64227, 142), ("bs", "Basel", 109161, 142),
              ("ge", "Genève", 59437, 143), ("vd", "Lausanne", 46732, 143)]
    for code, name, value, page in cities:
        observations.append(dict(unit_id="ch_city_"+code, name=name, parent_id="ch_canton_"+code, kind="city",
            population_value=value, date=dates[1], source_id=SOURCE, locator=f"Table IV, printed p. {page}, {name}, col. 1900",
            definition="Residents of administrative municipality at the stated census; city figures are included in cantonal total. Zürich expanded between censuses.",
            method="census", mapping_status="canton_containment", quality="primary_census", region="Europe"))
    with (HERE/"observations.jsonl").open("w",encoding="utf8",newline="\n") as f:
        for x in observations:
            f.write(json.dumps(x, ensure_ascii=False)+"\n")
    save("swiss_opening.json", dict(unit_id=ROOT, date="1900-01-01", population_value=total, source_id=SOURCE,
         locator="Table I, printed p. 104, Switzerland and 25 cantons/half-cantons", endpoint_dates=dates,
         country_endpoint_values=bases, method=f"Linear interpolation of residents over {DAYS}/{SPAN} elapsed days. Whole persons by largest remainder. Intercensal model error unknown.",
         units=[x for _,x in leaves]))
    save("sources.json", [dict(id=SOURCE,title="Vorläufige Resultate der eidgenössischen Volkszählung vom 1. Dezember 1910, verglichen mit früheren Volkszählungen",
         publisher="Federal census returns published in Zeitschrift für schweizerische Statistik (1911), pp. 101–143",
         url="https://www.sses.swiss/journal/archive/pdf/1911/1911-I-8.pdf",locator="Definitions p. 101; Table I p. 104; Table IV pp. 142–143, retrospective 1888 and 1900 census columns",
         rights="Numeric facts transcribed from 1911 publication; no reproduction of its layout. Canton totals cross-checked against Statistisches Jahrbuch der Schweiz 1919, III.a.3.",
         independent_url="https://istmat.org/files/uploads/53038/statistisches_jahrbuch_der_schweiz_1919.pdf")])

if __name__ == "__main__":
    build()
