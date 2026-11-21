"""Comparable-area returns from Table II-A. Keep the incomplete India total on its legacy basis."""
import json
from datetime import date
from fractions import Fraction
from pathlib import Path

HERE = Path(__file__).resolve().parent
source = json.loads((HERE.parent / "eastern/reconciliation.json").read_text(encoding="utf8"))
table = next(x["common_area"] for x in source["items"] if x["territory"] == "India")
source_id = "india_census_1901_comparable_area"
source_dates = table["census_dates"]
start, end = map(date.fromisoformat, source_dates)
day = date(1900, 1, 1)
fraction = Fraction((day - start).days, (end - start).days)

def write_json(path, value):
    (HERE/path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf8")

write_json("sources.json", [dict(id=source_id, title=table["source_title"],
    publisher="Government of India, 1903", url=table["source_url"], locator=table["locator"],
    rights="Historical government publication. Numeric transcription and derived counts. Original scans linked.",
    boundary_references=[
        {"title":"Mysore census 1901, report p. 19", "url":"https://dspace.gipe.ac.in/xmlui/bitstream/handle/10973/18854/GIPE-017294.pdf?isAllowed=y&sequence=3"},
        {"title":"Imperial Gazetteer of India, vol. IV, Native States, appendix I, Hyderabad footnote", "url":"https://upload.wikimedia.org/wikipedia/commons/3/31/Imperial_gazetteer_of_India_.._%28IA_imperialgazettee04grea%29.pdf"}])])

catalog = [
    ("raj_comparable_control", "Common enumeration area including Aden", None, table["empire"]),
    ("raj_comparable_provinces", "Provinces in the common area", "raj_comparable_control", table["provinces_including_aden"]),
    ("raj_comparable_states", "States and agencies in the common area", "raj_comparable_control", table["states_and_agencies"]),
]
for item in table["provincial_and_state_rows"]:
    n = item["row_number"]
    parent = "raj_comparable_provinces" if n <= 12 else "raj_comparable_states"
    catalog.append((f"raj_comparable_row_{n:02}", item["name"], parent, item))
catalog.append(("raj_comparable_ex_aden", "Common enumeration area excluding Aden", None, table["empire_excluding_aden"]))
rows = []
admitted = []
# An a priori list of interior princely states whose original statistical identities
# can be located within the WWO parent. Frontier and aggregate areas are research only.
interior_states = {18: "raj_hyderabad_state", 21: "raj_mysore_state"}
scope_notes = {
    18: "Hyderabad State excludes Berar (a separate province in table II-A row 5). French Yanam lies in the Madras Godavari district. Imperial Gazetteer of India vol. IV, Native States appendix I, Hyderabad footnote; vol. XXIV p. 413.",
    21: "Mysore includes Bangalore Civil and Military Station. Census of India 1901, Mysore report, p. 19. The station and city populations are already contained here.",
}
for key, name, parent, values in catalog:
    a, b = values["1891"], values["1901"]
    result = round(a + (b-a)*fraction)
    if result != values["estimate_1900_01_01"]:
        raise ValueError(f"interpolation mismatch for {key}")
    n = values.get("row_number")
    locator = table["locator"] + (f" Row {n}: {name}." if n else f" Control: {name}.")
    for when, value in zip([*source_dates, day.isoformat()], [a,b,result]):
        interpolated = when == day.isoformat()
        rows.append(dict(unit_id=key, parent_id=parent, name=name, region="Asia", kind="admin",
            date=when, population_value=value, population_lower=None, population_upper=None,
            definition=table["boundary_basis"], method=table["method"] if interpolated else "published comparable-area census return",
            source_id=source_id, locator=locator, mapping_status="source_statistical_extent_no_polygon",
            quality="intercensal_reconstruction" if interpolated else "official_census_table",
            **(dict(source_dates=source_dates, endpoint_values=[a,b], fraction=str(fraction)) if interpolated else {})))
    if n in interior_states:
        admitted.append(dict(unit_id=interior_states[n], source_unit_ids=[key], name=name,
            endpoint_values=[a,b], population_value=result, locator=locator, scope=scope_notes[n], place_ids=[]))

with (HERE/"observations.jsonl").open("w", encoding="utf8", newline="\n") as f:
    for row in rows:
        print(json.dumps(row, ensure_ascii=False), file=f)

legacy = json.loads((HERE.parents[2]/"alpha/historical_world_economy_1900/countries_compact.json").read_text(encoding="utf8"))
economic_rows = (dict(zip(legacy["field_order"],r)) for r in legacy["rows"])
root = "cshapes_gw_750"
control = next(r["population_value"] for r in economic_rows if r["entity_id"] == root)
write_json("india_opening.json", dict(unit_id=root, population_value=control, date=day.isoformat(),
    units=admitted, source_id=source_id, locator=table["locator"], endpoint_dates=source_dates,
    method=table["method"], scope="Only documented interior subdivisions. The parent retains the prior 50-unit opening estimate.",
    legacy_unlocated_balance=control-sum(r["population_value"] for r in admitted),
    legacy_control_source="data/alpha/historical_world_economy_1900/countries_compact.json: cshapes_gw_750 population_value",
    uncertainty_kind="The unlocated remainder is an accounting residual with unknown geographic distribution and census error."))
