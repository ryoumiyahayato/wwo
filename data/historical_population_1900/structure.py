"""Build nonadditive demographic observations retaining historical labels and scopes."""
import csv
import json
import re
from pathlib import Path

HERE=Path(__file__).resolve().parent/"collections"
AGE_SOURCES = HERE / "age_sex"
OPENING_METHOD = (
    "Hold the census age-by-sex shares at 1900-01-01. Apply the source ratios to "
    "the anonymous opening balance using integer largest remainders."
)

def read_csv(path):
    with path.open(encoding="utf8",newline="") as f:
        return list(csv.DictReader(f))

def province_key(name):
    return re.sub(r"\s+(губерния|область|обл\.?)$","",name.strip().casefold())

def dimensions(population):
    age_panels = age_sex_panels()
    russian_panel, russian_rows = next(
        (panel, rows) for panel, rows in age_panels if panel["id"] == "russia_empire_1897"
    )
    russian_ages = {row["label"]: row for row in russian_rows}
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
        observation = dict(unit_id=scope,published_scope=name,date="1897-02-09",source_id=tab,
            locator=f"{tab}.php?reg={param}, row {raw['row']}",category=raw["category"],subcategory=raw["subcategory"] or None,
            dialect=raw["dialect"] or None,measure="published persons",values=cells,
            definition={"rus_lan_97":"Reported mother tongue; overlapping headings, languages and dialects.",
                        "rus_rel_97":"Religious denomination reported by the original census.",
                        "rus_sos_97":"Legal estate (soslovie) reported by the original census.",
                        "rus_age_97":"Age, sex and literacy. Printed subtotals overlap single-year ages."}[tab])
        if tab == "rus_age_97" and param == "0":
            row = russian_ages[raw["category"]]
            observation.update(
                dimension="age_by_sex", panel_id=russian_panel["id"], row_role=row["role"],
                age_min=row["age_min"], age_max=row["age_max"],
            )
        result.append(observation)
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
    for panel, rows in age_panels:
        if panel["source_id"] == "rus_age_97" or "component_panels" in panel:
            continue
        for row in rows:
            result.append(dict(
                unit_id=panel["observed_unit_id"], published_scope=panel["published_scope"],
                date=panel["observed_date"], source_id=panel["source_id"],
                locator=f"{panel['locator']}, {row['label']}", category=row["label"],
                measure="published persons", values={key: row[key] for key in ("both", "male", "female")},
                definition=panel["definition"], dimension=panel.get("dimension", "age_by_sex"),
                panel_id=panel["id"], row_role=row["role"],
                age_min=row["age_min"], age_max=row["age_max"],
            ))
    return result


def regroup_age_rows(rows, target):
    counts = ("both", "male", "female")
    for band in target:
        selected = [
            row
            for row in rows
            if row["role"] == band["role"] and (
                band["age_min"] is None and row["age_min"] is None
                or band["age_min"] is not None and row["age_min"] is not None
                and row["age_min"] >= band["age_min"]
                and (band["age_max"] is None
                     or row["age_max"] is not None and row["age_max"] <= band["age_max"])
            )
        ]
        yield band | {field: sum(row[field] for row in selected) for field in counts}


def age_sex_panels():
    panels = json.loads((AGE_SOURCES / "panels.json").read_text(encoding="utf8"))
    panels.extend(json.loads((AGE_SOURCES / "us_census_1900_panels.json").read_text(encoding="utf8")))
    panels.extend(json.loads((AGE_SOURCES / "uk_county_age_panels.json").read_text(encoding="utf8")))
    panels.extend(json.loads((AGE_SOURCES / "france_census_1901_panels.json").read_text(encoding="utf8")))
    panels.extend(json.loads((AGE_SOURCES / "germany_census_1900_panels.json").read_text(encoding="utf8")))
    panels.extend(json.loads((AGE_SOURCES / "india_census_1901_panels.json").read_text(encoding="utf8")))
    panels.extend(json.loads((AGE_SOURCES / "india_census_1891_panels.json").read_text(encoding="utf8")))
    panels.extend(json.loads((AGE_SOURCES / "cape_1904_panels.json").read_text(encoding="utf8")))
    by_panel = {panel["id"]: [] for panel in panels}
    for filename in (
        "age_sex.csv", "us_census_1900.csv", "uk_county_age.csv", "france_census_1901.csv",
        "germany_census_1900.csv", "india_census_1901.csv", "india_census_1891.csv", "cape_1904.csv",
    ):
        for row in read_csv(AGE_SOURCES / filename):
            for key in ("age_min", "age_max", "both", "male", "female"):
                row[key] = int(row[key]) if row[key] else None
            by_panel[row["panel"]].append(row)

    russian = by_panel["russia_empire_1897"]
    for row in read_csv(HERE / "russia" / "structure.csv"):
        if row["source_table"] != "rus_age_97" or row["region_parameter"] != "0":
            continue
        label = row["category"]
        if label == "Дети моложе 1 года":
            age_min = age_max = 0
        elif label.isdecimal():
            age_min = age_max = int(label)
        elif label == "110 и более":
            age_min, age_max = 110, None
        else:
            age_min = age_max = None
        russian.append(dict(
            label=label, age_min=age_min, age_max=age_max,
            role="total" if label == "ИТОГО" else "subtotal" if "-" in label else "band",
            **{key: int(row[key]) for key in ("both", "male", "female")},
        ))
    for panel in panels:
        if "component_panels" not in panel:
            continue
        components = []
        for panel_id in panel["component_panels"]:
            rows = by_panel[panel_id]
            adjustments = panel.get("component_count_corrections", {}).get(panel_id, {})
            if adjustments:
                rows = [row | adjustments.get(row["label"], {}) for row in rows]
            if "regroup_to" in panel and panel_id != panel["regroup_to"]:
                rows = regroup_age_rows(rows, by_panel[panel["regroup_to"]])
            components.append(rows)
        for matched_rows in zip(*components, strict=True):
            row = matched_rows[0].copy()
            if any(
                component[key] != row[key]
                for component in matched_rows[1:]
                for key in ("label", "role", "age_min", "age_max")
            ):
                raise ValueError(f"{panel['id']}: component age groups do not match")
            for key in ("both", "male", "female"):
                row[key] = sum(component[key] for component in matched_rows)
            by_panel[panel["id"]].append(row)
    return [(panel, by_panel[panel["id"]]) for panel in panels]


def opening_structure(opening_groups, observations, *, version=6):
    opening_totals = {
        unit["unit_id"]: unit["population_value"]
        for group in opening_groups
        for unit in (group["units"] or [group])
    }
    groups = []
    for panel, rows in age_sex_panels():
        unit_id = panel.get("opening_unit_id")
        if unit_id is None or not (
            panel.get("opening_from_version", 1) <= version <= panel.get("opening_through_version", version)
        ):
            continue
        totals = [row for row in rows if row["role"] == "total"]
        bands = [
            {key: row[key] for key in ("label", "age_min", "age_max", "male", "female")}
            for row in rows if row["role"] == "band"
        ]
        if len(totals) != 1:
            raise ValueError(f"{panel['id']}: expected one printed age table control")
        total = totals[0]
        for sex in ("male", "female"):
            if sum(band[sex] for band in bands) != total[sex]:
                raise ValueError(f"{panel['id']}: {sex} age rows do not sum to the printed total")
        if total["male"] + total["female"] != total["both"]:
            raise ValueError(f"{panel['id']}: published sex totals do not sum to the population")
        for band in bands:
            low, high = band["age_min"], band["age_max"]
            band["id"] = "unknown" if low is None else f"age_{low}_{high if high is not None else 'plus'}"
        groups.append(dict(
            unit_id=unit_id, opening_total=opening_totals[unit_id], observed_total=total["both"],
            method=OPENING_METHOD, bands=bands,
            **{key: panel[key] for key in ("source_id", "observed_unit_id", "observed_date", "locator", "uncertainty")},
        ))
    unit = "statistical_area:bosnia_herzegovina_1900"
    if unit in opening_totals:
        row = next(r for r in observations if r["unit_id"] == unit and r["date"] == "1895-04-22"
                   and r["source_id"] == "bosnia_herzegovina_demography_2024")
        if sum(row["sex"].values()) != row["population_value"]:
            raise ValueError(f"{unit}: published sex totals do not sum to the population")
        groups.append(dict(
            unit_id=unit, opening_total=opening_totals[unit], observed_total=row["population_value"],
            source_id=row["source_id"], observed_unit_id=unit, observed_date=row["date"], locator=row["locator"],
            method="Hold the nearer 1895 civilian census sex shares at opening and use integer largest remainders. Ages are unknown.",
            uncertainty="The sex ratio may have changed. Both dated census controls remain available. No opening error interval is known.",
            sex_only=True,
            bands=[dict(id="unknown", label="Published sex totals; ages unavailable", age_min=None, age_max=None, **row["sex"])],
        ))
    return dict(version=1, groups=sorted(groups, key=lambda group: group["unit_id"]))
