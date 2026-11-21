"""Build nonadditive demographic observations retaining historical labels and scopes."""
import csv
import re
from pathlib import Path

HERE=Path(__file__).resolve().parent/"collections"

def read_csv(path):
    with path.open(encoding="utf8",newline="") as f:
        return list(csv.DictReader(f))

def province_key(name):
    return re.sub(r"\s+(губерния|область|обл\.?)$","",name.strip().casefold())

def dimensions(population):
    provinces={province_key(r["name"]): r for r in population if r.get("source_id")=="russia_first_census"
               and r.get("parent_id")=="ru_census_1897_ex_finland"}
    result=[]
    for raw in read_csv(HERE/"russia"/"structure.csv"):
        tab=raw["source_table"]
        param=raw["region_parameter"]
        name=raw["published_scope"]
        province=provinces.get(province_key(name))
        scope=(province["unit_id"] if province else "ru_census_1897_ex_finland" if param=="0" else f"{tab}:reg:{param}")
        cells={k:int(raw[k]) if raw[k].isdigit() else raw[k] or None for k in ["male","female","both","literate_male","literate_female","literate_both"]}
        result.append(dict(unit_id=scope,published_scope=name,date="1897-02-09",source_id=tab,
            locator=f"{tab}.php?reg={param}, row {raw['row']}",category=raw["category"],subcategory=raw["subcategory"] or None,
            dialect=raw["dialect"] or None,measure="published persons",values=cells,
            definition={"rus_lan_97":"Reported mother tongue; overlapping headings, languages and dialects.",
                        "rus_rel_97":"Religious denomination reported by the original census.",
                        "rus_sos_97":"Legal estate (soslovie) reported by the original census.",
                        "rus_age_97":"Age, sex and literacy. Printed subtotals overlap single-year ages."}[tab]))
    occupations=read_csv(HERE/"demography"/"occupation.csv")
    for field in ["male","female","total"]:
        if sum(int(r[field]) for r in occupations[2:])!=int(occupations[1][field]):
            raise ValueError("US occupation groups do not close")
    for r in occupations:
        result.append(dict(unit_id="us_twelfth_census_entire_enumeration",date="1900-06-01",source_id="us_occupation_special_report",
            locator="General Tables no. 1, pp. 7–8, "+r["category"],category=r["category"],measure="persons",
            values={k:int(r[k]) for k in ("total","male","female")},definition="Age 10+. Includes continental US, Alaska, Hawaii, and US military/naval service abroad including employees. Distinct from continental state controls."))
    for date,residents,present,households in [("1888-12-01",2917754,2933334,637835),("1900-12-01",3315443,3325023,728920)]:
        result.append(dict(unit_id="swiss_confederation",date=date,source_id="swiss_federal_census_comparison_1911",
            locator="I, printed p. 104, Switzerland annual rows, cols. 9–10",
            category="households and persons",values=dict(households=households,ordinary_residents=residents,persons_present=present),
            definition="Published household count, usual residents and de facto population are distinct. Population in private households is not identified separately; household size is unknown."))
    return result
