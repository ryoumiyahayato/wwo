"""Read Federico–Tena's historical-border series (not their separate 1991-border file)."""
import csv
import json
import math
import re
import unicodedata
from collections import Counter
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

from openpyxl import load_workbook
from openpyxl.utils import get_column_letter

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
RAW = HERE / "raw"
BASE = "https://edatos.consorciomadrono.es/api/access/datafile/"
SERIES = "ft_world_v5"
PAPER = "https://hdl.handle.net/10016/45843"
RIGHTS = "CC BY 4.0. Giovanni Federico and Antonio Tena-Junguito. WWO extracts, converts units and interpolates."
SOURCE = [
    dict(id=SERIES, title="Federico–Tena World Population Historical Database, List of Polities V5",
         publisher="e-cienciaDatos / Universidad Carlos III de Madrid", url="https://doi.org/10.21950/3SK54X",
         locator="Country series rows 103–104; Summary data rows 104–105 (thousands)", rights=RIGHTS,
         downloads={k: BASE+str(v)+"?format=original" for k,v in {"world_2026.xlsx":51075,"world_2026_readme.pdf":51076,"world_2025.xlsx":34045}.items()},
         methods=PAPER, african_revision="See 2026 workbook Sources and V4 African Population Database (Frankema and Jerven)."),
    dict(id="ft_world_v4", title="Federico–Tena historical-border series V4, 2025",publisher="e-cienciaDatos",
         url="https://doi.org/10.21950/3SK54X", locator="V4 Country series!EC103:EC104; Trucial coast omitted from V5 country sheet",
         rights=RIGHTS, download=BASE+"34045?format=original"),
    dict(id="ft_quality_2025", title="Quality Assessment Population (2025)", publisher="e-cienciaDatos",
         url="https://doi.org/10.21950/U6AANV", locator="Quality Assessment rows 103–104. Numerical sensitivity assumptions in working paper p.27.",
         rights=RIGHTS, downloads={k:BASE+str(v)+"?format=original" for k,v in {"quality_2025.xlsx":34065,"quality_2025_readme.pdf":34066}.items()}),
    dict(id="census_world_comparison", title="Historical Estimates of World Population", publisher="US Census Bureau, International Programs Center",
         url="https://www.census.gov/data/tables/time-series/demo/international-programs/historical-est-worldpop.html",
         locator="1900 AD row; population in millions, lower/upper summary. Original references listed below the table.",
         rights="Factual numeric extract from US federal table; underlying researchers credited by the publisher.")
]
SENSITIVITY = dict(A=.0125,B=.0375,C=.0875,D=.1625,E=.25)
REGIONS = ["Africa", "America", "Asia", "Europe", "Oceania", "World"]
OPENING_WEIGHT = 184 / 365
V4_AFRICAN_COLUMNS = {
    "british east africa": "british east africa (kenia & uganda)",
    "cape verde (portuguese africa)": "cabo verde (portuguese africa)",
    "comoros and mayote (french)": "comoros",
    "german east africa": "tanganyka (german east africa)",
    "german west africa": "togo (german west africa)",
    "italian somaliland": "italia somalia",
    "morocco": "marocco",
    "réunion": "reunion",
    "sao tome and principe (portuguese africa)": "s.tome e principe (portuguess africa)",
    "southern rhodesia": "zimbabwe (southern rhodesia)",
    "zanzibar island": "zanzibar isl.",
}

def key(name):
    return " ".join(str(name or "").casefold().split())

def slug(name):
    value = unicodedata.normalize("NFKD",name).encode("ascii","ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+","_",value).strip("_")

def people(thousands):
    return int((Decimal(str(thousands))*1000).to_integral_value(rounding=ROUND_HALF_UP))

def rows(file, sheet):
    wb = load_workbook(RAW/file,read_only=True,data_only=True)
    try:
        return list(wb[sheet].values)
    finally:
        wb.close()

def colmap(table):
    return {key(name):i for i,name in enumerate(table[1]) if name}

def write_json(name, value):
    (HERE/name).write_text(json.dumps(value,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")

def opening_value(first, second):
    return round((first * (1 - OPENING_WEIGHT) + second * OPENING_WEIGHT) * 1000)


def version_comparisons(series, prior, summary, prior_summary):
    """Keep published revisions distinct from account changes and independent rounding."""
    for col, region in enumerate(REGIONS, 8):
        references = []
        for table in (prior_summary, summary):
            first, second = [next(i for i, row in enumerate(table) if row[0] == year) for year in (1899, 1900)]
            letter = get_column_letter(col + 1)
            references.append((opening_value(table[first][col], table[second][col]),
                f"Summary data!{letter}{first+1}:{letter}{second+1}"))
        (v4, v4_locator), (v5, v5_locator) = references
        yield dict(comparison="published_research_revision", region=region, date="1900-01-01",
            v4=v4, v4_locator=v4_locator, v5=v5, v5_locator=v5_locator, v5_minus_v4=v5-v4)

    old_columns = colmap(prior)
    for col, name in enumerate(series[1]):
        if key(series[0][col]) != "africa" or not name:
            continue
        old_col = old_columns[V4_AFRICAN_COLUMNS.get(key(name), key(name))]
        first, second = prior[102][old_col], prior[103][old_col]
        next_first, next_second = series[102][col], series[103][col]
        if not all(isinstance(value, (int, float)) for value in (first, second, next_first, next_second)):
            continue
        if (first, second) == (next_first, next_second):
            continue
        v4, v5 = opening_value(first, second), opening_value(next_first, next_second)
        old_letter, new_letter = get_column_letter(old_col+1), get_column_letter(col+1)
        yield dict(comparison="matched_african_research_series_revision", region="Africa", date="1900-01-01",
            unit_id="ft_"+slug(name), v4_name=prior[1][old_col].strip(), v5_name=name.strip(), v4=v4,
            v4_locator=f"Country series!{old_letter}103:{old_letter}104", v5=v5,
            v5_locator=f"Country series!{new_letter}103:{new_letter}104", v5_minus_v4=v5-v4)


def build():
    series=rows("world_2026.xlsx","Country series")
    prior=rows("world_2025.xlsx","Country series")
    quality=rows("quality_2025.xlsx","Quality Assessment")
    summary=rows("world_2026.xlsx","Summary data")
    map25, mapq=colmap(prior),colmap(quality)
    politics=json.loads((ROOT/"data/world_map/historical/political_units_1900.json").read_text(encoding="utf-8"))["units"]
    politics={str(p["gwcode"]):p["id"] for p in politics}
    with (HERE/"series_crosswalk.tsv").open(encoding="utf-8") as src:
        links={r["column"]:r for r in csv.DictReader(src,delimiter="\t")}
    observations=[]
    comparisons=[]
    used=set()
    # V5 Summary counts 33 Asian units; its country sheet contains 32. The missing
    # UAE series is present in V4 and both years explain the V5 discrepancy.
    # Keep its actual version and locator, including the remaining rounding error.
    table_columns=[(series,i,SERIES) for i in range(1,len(series[1]))]
    table_columns.append((prior,map25[key("United Arab Emirates")],"ft_world_v4"))
    for tab,i,source in table_columns:
        x=tab[103][i]
        if not isinstance(x,(float,int)):
            continue
        col=get_column_letter(i+1)
        link=links[col]
        used.add(col)
        name=tab[1][i].strip()
        uid="ft_"+slug(name)
        region=tab[0][i].title().strip()
        candidates=[politics[n] for n in link["ww_gwcodes"].split()]
        common=dict(unit_id=uid,name=name,parent_id="ft_region_"+region.lower(),kind="territory",
                    definition="Estimated midyear de facto residents where possible. Historical-border study series; source labels may postdate 1900.",
                    source_id=source,mapping_status="historical_identity_link" if len(candidates)==1 and not link["scope_note"] else "scope_review",
                    candidate_polity_ids=candidates,scope_note=link["scope_note"] or None,region=region,
                    method_reference=PAPER,method_locator="Appendix I, printed pp. "+link["paper_pages"],
                    boundary_note=tab[2][i],population_lower=None,population_upper=None)
        endpoints=[]
        for idx in (102,103):
            year=tab[idx][0]
            if year not in (1899,1900) or not isinstance(tab[idx][i],(float,int)):
                raise ValueError((name,year))
            v=people(tab[idx][i]); locator=f"Country series!{col}{idx+1}"
            qidx=mapq.get(key(name)); pidx=map25.get(key(name))
            grade=None
            if pidx is not None and qidx is not None and tab[idx][i]==prior[idx][pidx]:
                grade=quality[idx][qidx]
            if grade not in SENSITIVITY: grade=None
            rate=SENSITIVITY.get(grade)
            row=dict(common,date=str(year)+"-07-01",date_precision="nominal midyear",
                     population_value=v,quality=grade or "not_assessed_for_this_revision",locator=locator,
                     method="published historical reconstruction; thousand persons converted to persons",
                     reported_thousands=tab[idx][i],quality_locator=None if not grade else f"ft_quality_2025:Quality Assessment!{get_column_letter(qidx+1)}{idx+1}",
                     uncertainty_kind="author-assumed sensitivity, not sampling limits" if rate else "unquantified")
            if rate:
                row.update(population_lower=math.floor(v*(1-rate)),population_upper=math.ceil(v*(1+rate)))
            endpoints.append(row)
            observations.append(row)
        a,b=endpoints
        w=OPENING_WEIGHT
        val=opening_value(a["reported_thousands"], b["reported_thousands"])
        row=dict(common,date="1900-01-01",population_value=val,method="linear between nominal July 1 midyear values in thousands, multiply by 1000 then round once",
                 locator=a["locator"]+" and "+b["locator"],source_dates=[a["date"],b["date"]],fraction="184/365",
                 quality=max(a["quality"],b["quality"]),uncertainty_kind="linear interpolation of endpoint sensitivity envelopes; between-date deviation is unquantified")
        if a["population_lower"] is not None and b["population_lower"] is not None:
            row.update(population_lower=math.floor(a["population_lower"]*(1-w)+b["population_lower"]*w),
                       population_upper=math.ceil(a["population_upper"]*(1-w)+b["population_upper"]*w))
        observations.append(row)
    if set(links)!=used: raise ValueError("crosswalk column not in source")
    # Compare the raw table partition, retaining single-person roundoff.
    for year in (1899,1900):
        total=Counter()
        for row in observations:
            if row["date"]==f"{year}-07-01": total[row["region"]]+=row["population_value"]
        idx=next(i for i,r in enumerate(summary) if r[0]==year)
        for j,region in enumerate(REGIONS,8):
            pub=people(summary[idx][j]); parts=sum(total.values()) if region=="World" else total[region]
            v5only=sum(r["population_value"] for r in observations if r["date"]==f"{year}-07-01" and r["source_id"]==SERIES and r["kind"]=="territory" and (region=="World" or r["region"]==region))
            comparisons.append(dict(region=region,year=year,published=pub,v5_components=v5only,v5_difference=v5only-pub,
                                    components_including_v4_trucial_coast=parts,difference=parts-pub))
            observations.append(dict(unit_id="ft_region_"+region.lower(),name=region,parent_id=None if region=="World" else "ft_region_world",
                kind="benchmark",population_value=pub,population_lower=None,population_upper=None,date=f"{year}-07-01",source_id=SERIES,
                locator=f"Summary data!{get_column_letter(j+1)}{idx+1}",definition="Published summary, thousand persons at midyear.",
                method="research estimate",mapping_status="statistical_control",quality="published_aggregate",region=region))
    for j,region in enumerate(REGIONS,8):
        controls=[r for r in observations if r["kind"]=="benchmark" and r["region"]==region]
        a,b=controls
        ix=[next(i for i,t in enumerate(summary) if t[0]==yr) for yr in (1899,1900)]
        value=opening_value(summary[ix[0]][j], summary[ix[1]][j])
        parts=sum(r["population_value"] for r in observations if r["kind"]=="territory" and r["date"]=="1900-01-01" and (region=="World" or r["region"]==region))
        observations.append(dict(a,date="1900-01-01",population_value=value,locator=a["locator"]+" and "+b["locator"],
                                 definition="Interpolation of published midyear aggregate in thousands.",source_dates=[a["date"],b["date"]],
                                 fraction="184/365",method="linear between nominal midyear controls",quality="derived_aggregate"))
        comparisons.append(dict(region=region,date="1900-01-01",interpolated_control=value,components_including_v4_trucial_coast=parts,difference=parts-value))
    # This independent publication reports the range across different historical reconstructions.
    observations.append(dict(unit_id="world_comparison_1900",name="World",parent_id=None,kind="benchmark",population_value=1650000000,
        population_lower=1550000000,population_upper=1762000000,date="1900",source_id="census_world_comparison",locator="1900 AD, UN 1999 and summary lower/upper",
        definition="World, persons. Year only.",method="UN 1999 Table 1 p.5; bounds are summary spread across published estimates, not a confidence interval.",
        mapping_status="statistical_control",quality="independent_comparison",region="World"))
    write_json("sources.json",SOURCE)
    comparisons.extend(version_comparisons(series, prior, summary, rows("world_2025.xlsx", "Summary data")))
    write_json("reconciliation.json",comparisons)
    with (HERE/"observations.jsonl").open("w",encoding="utf-8",newline="\n") as out:
        for r in observations: out.write(json.dumps(r,ensure_ascii=False)+"\n")

if __name__=="__main__":
    build()
