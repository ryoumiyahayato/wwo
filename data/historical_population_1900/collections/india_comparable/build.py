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
        {"title":"Census of India 1901, General Report, chapter II, section 91 and subsequent province and state sections", "url":"https://indiadisabilitywatch.in/wp-content/uploads/2025/10/report_on_the_census_of_india_1901-2.pdf"},
        {"title":"Census of the British Empire 1901, Indian Empire Table 3, pp. 87–88", "url":"https://www.tradeshouselibrary.org/uploads/4/7/7/2/47723681/census_of_the_british_empire._1901.pdf"},
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
catalog.append(("raj_comparable_bombay_ex_aden", "Bombay Presidency excluding Aden", None, table["bombay_presidency_excluding_aden"]))
rows = []
admitted = []
interior = []
# An a priori list of interior princely states whose original statistical identities
# can be located within the WWO parent. Frontier and aggregate areas are research only.
interior_states = {18: "raj_hyderabad_state", 21: "raj_mysore_state"}
scope_notes = {
    18: "Hyderabad State excludes Berar (a separate province in table II-A row 5). French Yanam lies in the Madras Godavari district. Imperial Gazetteer of India vol. IV, Native States appendix I, Hyderabad footnote; vol. XXIV p. 413.",
    21: "Mysore includes Bangalore Civil and Military Station. Census of India 1901, Mysore report, p. 19. The station and city populations are already contained here.",
}
# Use peer rows on the 1891 comparison geography. A presidency/census area
# and its corresponding group of princely states are separate in Table II-A.
extended_interior = {
    1: ("raj_ajmer_merwara", "British Ajmer-Merwara is a separate row from the Rajputana Agency that administers it."),
    4: ("raj_bengal_province", "The directly administered Bengal return precedes the 1905 partition. The Bengal States and French Chandernagore are separate census returns."),
    5: ("raj_berar", "Berar is printed apart from the Hyderabad State and Central Provinces. The transfer of administration to the Central Provinces followed in 1903."),
    8: ("raj_central_provinces", "The directly administered Central Provinces are separate from Central Provinces States and Berar."),
    9: ("raj_coorg", "Coorg was a separate census reporting territory under its Chief Commissioner."),
    10: ("raj_madras_presidency", "The directly administered Madras return uses the table's coastal and island reporting scope. Madras States and the French settlements have separate census returns."),
    12: ("raj_agra_oudh", "The census groups Agra and Oudh in one row. Their two subrows and the United Provinces States are outside this partition count."),
    13: ("raj_baroda_state", "The Baroda State is separately returned from the Bombay Presidency districts with which it was geographically interspersed. General Report §106."),
    15: ("raj_bombay_states", "The Bombay States are a separate peer group from the Bombay Presidency and Baroda, as tabulated in II-A."),
    16: ("raj_central_india_agency", "The Agency includes Gwalior. Gwalior is a subrow and enters the parent tally once. Central Provinces States are a separate peer row."),
    17: ("raj_central_provinces_states", "The grouped Central Provinces States are separately returned from the Central Provinces, the Central India Agency and Berar."),
    20: ("raj_madras_states", "Cochin and Travancore are included in the Madras States total. Their individually reported numbers are subrows. General Report §§146–147."),
    23: ("raj_rajputana_agency", "The Agency is a peer of British Ajmer-Merwara. The 1891 return includes the source's estimate of the Bhil population, per Table II-A p. 9."),
    24: ("raj_united_provinces_states", "The census separately returns the United Provinces States and the directly administered Agra and Oudh."),
}
excluded_comparable_rows = {
    2: "The comparison omits Indigenous Andamanese and Nicobarese not enumerated in the 1891 census.",
    3: "The Assam comparison excludes first enumerations and adjusts jurisdiction. The Manipur and Lushai frontier coverage needs reconciliation.",
    7: "The comparison omits first enumerations in the Shan States and Chin Hills.",
    11: "The comparable Punjab return combines the later North-West Frontier Province with Punjab and omits first-enumerated frontier districts.",
    14: "The Sikkim adjustment and external boundary prevent adopting the Bengal States comparison as a WWO subdivision.",
    19: "The Kashmir return needs alignment of northern and eastern border jurisdictions. The General Report §53 records uncertainty in the jurisdiction areas.",
    22: "The Punjab States comparison adjusts the later return and needs an opening boundary crosswalk on the northwest frontier.",
}
for key, name, parent, values in catalog:
    a, b = values["1891"], values["1901"]
    result = round(a + (b-a)*fraction)
    if result != values["estimate_1900_01_01"]:
        raise ValueError(f"interpolation mismatch for {key}")
    n = values.get("row_number")
    if key == "raj_comparable_bombay_ex_aden":
        locator = table["locator"] + " Row 6 (Bombay Presidency) minus its Aden subrow, persons."
    else:
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
    if n in extended_interior or key == "raj_comparable_bombay_ex_aden":
        unit_id, scope = extended_interior.get(n, ("raj_bombay_presidency",
            "Row 6 minus the Aden subrow at both endpoints. The remaining persons are the directly administered Bombay and Sind components, separate from the Bombay States and Baroda."))
        interior.append(dict(unit_id=unit_id, source_unit_ids=[key], name=name,
            endpoint_values=[a,b], population_value=result, locator=locator, scope=scope, place_ids=[]))

with (HERE/"observations.jsonl").open("w", encoding="utf8", newline="\n") as f:
    for row in rows:
        print(json.dumps(row, ensure_ascii=False), file=f)

legacy = json.loads((HERE.parents[2]/"alpha/historical_world_economy_1900/countries_compact.json").read_text(encoding="utf8"))
economic_rows = (dict(zip(legacy["field_order"],r)) for r in legacy["rows"])
root = "cshapes_gw_750"
control = next(r["population_value"] for r in economic_rows if r["entity_id"] == root)
opening = dict(unit_id=root, population_value=control, date=day.isoformat(),
    units=admitted, source_id=source_id, locator=table["locator"], endpoint_dates=source_dates,
    method=table["method"], scope="Only documented interior subdivisions. The parent retains the prior 50-unit opening estimate.",
    legacy_unlocated_balance=control-sum(r["population_value"] for r in admitted),
    legacy_control_source="data/alpha/historical_world_economy_1900/countries_compact.json: cshapes_gw_750 population_value",
    uncertainty_kind="The unlocated remainder is an accounting residual with unknown geographic distribution and census error.")
write_json("india_opening.json", opening)
interior.extend(admitted)
interior.sort(key=lambda row: row["unit_id"])
located = sum(row["population_value"] for row in interior)
excluded_rows = [dict(source_unit_id=f"raj_comparable_row_{n:02}", population_value=item["estimate_1900_01_01"],
    reason=excluded_comparable_rows[n]) for item in table["provincial_and_state_rows"]
    if (n := item["row_number"]) in excluded_comparable_rows]
common_ex_aden = table["empire_excluding_aden"]["estimate_1900_01_01"]
write_json("india_opening_v2.json", opening | dict(units=interior,
    scope="Partition of the old India control using peer statistical areas in the 1891 comparison geography. Isolated frontier or enumeration differences stay in the residual. The source units have no WWO province polygons.",
    legacy_unlocated_balance=control-located,
    balance_basis=dict(comparable_area_excluding_aden=common_ex_aden,
        comparable_area_minus_admitted=common_ex_aden-located,
        comparable_rows_left_out=excluded_rows,
        comparable_rows_left_out_total=sum(row["population_value"] for row in excluded_rows),
        legacy_control_minus_comparable_area=control-common_ex_aden,
        excluded_aden=table["aden_within_bombay_presidency"]["estimate_1900_01_01"],
        scope="The implied balance includes published comparison areas held out and the arithmetic difference between the legacy and comparable controls. The source rounds the combined and component estimates independently. There is no measured 1900 population for the unenumerated remainder.")))
