"""Reconcile the two territorial census series with different date precision."""
import csv
import json
from datetime import date
from fractions import Fraction
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCES = {s["id"]:s for s in json.loads((HERE/"sources.json").read_text(encoding="utf8"))}
with (HERE/"returns.csv").open(encoding="utf8") as f:
    facts = list(csv.DictReader(f))

rows = []
for fact in facts:
    source = fact["source_id"]
    unit = fact["unit_id"]
    row = dict(unit_id=unit, name=fact["name"], wwo_id=fact["wwo_id"] or None, parent_id=None,
               kind="territory", region="Africa", population_value=int(fact["population"]),
               population_lower=None, population_upper=None, date=fact["date"], source_id=source,
               locator=SOURCES[source]["locator"]+" Row "+fact["date"]+", "+fact["name"]+".",
               method="published historical count", quality="official_or_research_republication",
               definition="Reported population on the island or in the territory. Subordinate institutions included where enumerated.",
               mapping_status="island_part_of_group" if unit=="mu_main_island" else "territory_identity" if fact["wwo_id"] else "statistical_only")
    if fact["male"]:
        row["breakdowns"] = {"sex": {k:int(fact[k]) for k in ("male","female")}}
        if fact["printed_white_male"]:
            row["breakdowns"]["historical_colonial_classification_by_sex"] = {
                k:int(fact[k]) for k in fact if k.startswith("printed_")}
    rows.append(row)
with (HERE/"observations.jsonl").open("w", encoding="utf8", newline="\n") as output:
    for row in rows:
        print(json.dumps(row,ensure_ascii=False), file=output)

for unit,first,last in [("basutoland","1891","1904-04-18"), ("reunion_island","1897","1902")]:
    endpoints = [next(r for r in rows if r["unit_id"]==unit and r["date"]==d) for d in (first,last)]
    ref = [date.fromisoformat(d+"-07-01" if len(d)==4 else d) for d in (first,last)]
    fraction = Fraction((date(1900,1,1)-ref[0]).days, (ref[1]-ref[0]).days)
    a,b = [r["population_value"] for r in endpoints]
    opening = dict(unit_id=endpoints[0]["wwo_id"], date="1900-01-01", source_id=endpoints[0]["source_id"],
        endpoint_sources=[r["source_id"] for r in endpoints], locator=" / ".join(r["locator"] for r in endpoints),
        endpoint_dates=[first,last], interpolation_reference_dates=[d.isoformat() for d in ref],
        country_endpoint_values=[a,b], population_value=round(a+(b-a)*fraction), units=[],
        population_lower=None,population_upper=None,
        scope="Basutoland excluding Cape, Natal and Orange Free State." if unit=="basutoland" else "Réunion island alone; outside metropolitan France, Mauritius and Madagascar.",
        method=f"Linear interpolation over {fraction}. July 1 is a computational midpoint for year-only returns. 1904 Basutoland day follows the imperial census report p. 71.",
        uncertainty_kind="No statistical interval. War interrupted the 1901 census in southern Africa; enumeration error and changes within the intercensal period are unquantified." if unit=="basutoland" else "No statistical interval. Enumeration-day and between-census variation are unquantified.")
    (HERE/(unit+"_opening.json")).write_text(json.dumps(opening,ensure_ascii=False,indent=2)+"\n",encoding="utf8")
