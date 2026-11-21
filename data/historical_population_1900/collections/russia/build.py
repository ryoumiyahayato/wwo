"""Normalize the census's own geographic units and retain its nested, non-additive breakdowns."""
import csv
import json
import re
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
MAP = HERE.parents[3]/"data/world_map/historical/russian_empire_1897_identity.json"
SOURCE = "russia_first_census"
COUNTRY = "ru_census_1897_ex_finland"
DATE = "1897-02-09"
def norm(value):
    return " ".join(value.lower().replace("ё","е").replace("c","с").split())

def build():
    geography=json.loads(MAP.read_text(encoding="utf-8"))["units"]
    provinces={norm(x["historical_name"]):x["id"] for x in geography if x["id"].startswith("administrative_region:ristat_province_")}
    districts=defaultdict(list)
    for x in geography:
        if x["id"].startswith("administrative_region:ristat_district_"):
            districts[x["parent_region_id"],norm(x["historical_name"])].append(x["id"])
    with (HERE/"census_facts.csv").open(encoding="utf-8") as src:
        facts=list(csv.DictReader(src))
    out=[]
    differences=[]
    country_total=0
    for n in sorted({int(r["table"]) for r in facts}):
        block=[r for r in facts if r["table"]==str(n)]
        region="Europe" if n<=60 else "Asia"
        province=block[0]["province"]
        pid=f"ru1897_{n}"
        pname=norm(province)
        pname={"бесарабская губерния":"бессарабская губерния","каменец-подольская губерния":"подольская губерния"}.get(pname,pname)
        province_map=provinces.get(pname)
        district_id=None
        district_label=None
        district_total=0
        for raw in block:
            index=int(raw["row"]); label=raw["label"]
            if not raw["both"].isdigit(): continue # printed dash; retained in source extract
            people=int(raw["both"]); male=int(raw["male"]); female=int(raw["female"])
            if male+female!=people:raise ValueError((n,index))
            wwo=None
            if index==3:
                kind="admin"; parent=COUNTRY; unit=pid; name=province; wwo=province_map
            elif index in (4,5):
                continue # provincial components kept on province record below
            elif (n,index) in {(12,9),(27,26)}:
                # These repeat the preceding district label but equal its residual
                # after its towns. Keep verbatim in the extract, not as a second district.
                continue
            elif (n,index)==(67,19) or re.search(r"[-–]\s*(?:весь|вся|все|всё)\s*$",label,re.I):
                kind="admin"; parent=pid; unit=f"{pid}_r{index}"; district_id=unit
                name=re.split(r"\s*[-–]\s*(?:весь|вся|все|всё)\s*$",label,flags=re.I)[0]
                district_label=name
                district_total+=people
                stem=re.sub(r"\s+(уезд|округ|отдел|округа)$","",norm(name))
                matches=districts.get((province_map,stem),[])
                if len(matches)==1:wwo=matches[0]
            else:
                city=re.search(r"\s[-–]\s*г\.\s*(.+)$",label)
                if not city or "без города" in label or "итого" in label.lower():continue
                name=city.group(1)
                # Require the district label from the city line to match the current district.
                prefix=label[:city.start()].strip()
                parent=district_id if district_label and norm(prefix)==norm(district_label) else pid
                unit=f"{pid}_city_r{index}";kind="city"
                wwo={("37","Санкт-Петербург"):"place:st_petersburg"}.get((str(n),name))
            row=dict(unit_id=unit,name=name,parent_id=parent,kind=kind,population_value=people,population_lower=None,population_upper=None,
                     date=DATE,source_id=SOURCE,locator=f"rus_gub_97.php?reg={n}, row {index}: {label}",definition="De facto persons of both sexes. Original date 28 January 1897 Julian.",
                     method="published census count via numerical transcription",mapping_status="dated_identity_1897" if wwo else "statistical_identity_only",
                     quality="census_transcription",region=region,wwo_id=wwo,sex={"male":male,"female":female},
                     accounting="contained in parent; city observations never add to parent")
            if index==3:
                country_total+=people
                parts=[(r["label"],int(r["both"])) for r in block if r["row"] in ("4","5") and r["both"].isdigit()]
                row["published_components"]=parts
                row["component_definition"]="Ambiguous duplicated labels; no urban/rural attribution" if n==26 else "See exact source labels (Sakhalin includes posts and village)."
                differences.append(dict(unit_id=pid,published=people,component_difference=sum(x[1] for x in parts)-people))
            out.append(row)
        differences[-1]["identified_districts_minus_province"]=district_total-int(block[0]["both"]) if district_total else None
    total=125640021
    out.append(dict(unit_id=COUNTRY,name="Russian Empire census area excluding Finland",parent_id=None,kind="country",
               population_value=total,population_lower=None,population_upper=None,date=DATE,source_id="ru_presidential_library",
               locator="Presidential Library: anniversary of the 1897 census, paragraph reporting total of both sexes",
               definition="Census territory; Grand Duchy of Finland excluded.",method="published national census total",
               mapping_status="partial_polity_scope",quality="census_control",region="Europe and Asia"))
    differences.append(dict(unit_id=COUNTRY,published=total,province_difference=country_total-total))
    sources=[dict(id=SOURCE,title="First General Census of the Russian Empire 1897, provincial returns, volumes I–LXXXIX",
                  publisher="Central Statistical Committee, Ministry of the Interior, St Petersburg 1903–1905; Demoscope Weekly numerical transcription",
                  url="https://www.demoscope.ru/weekly/ssp/rus_gub_97.php",locator="Наличное население в губерниях, уездах, городах Российской Империи (без Финляндии); table parameter reg=1…89, row numbers include two header rows",
                  rights="Historical numerical facts only. No republication licence for Demoscope page layout or editorial text asserted.",
                  geometry="Kessler/Markevich, RISTAT https://doi.org/10.34894/NQOASN; exact parent/name match only. No assumption of unchanged 1900 boundaries."),
             dict(id="ru_presidential_library",title="Проведена Первая всеобщая перепись населения Российской империи",publisher="Presidential Library of the Russian Federation",
                  url="https://www.prlib.ru/history/619019",locator="28 January (9 February) 1897, empire population of both sexes",rights="Factual extract and citation only.")]
    for table, label in [("rus_rel_97","Table XII: religious denomination"),("rus_sos_97","Table VIII: legal estates"),
                         ("rus_lan_97","Table XIII: mother tongue"),("rus_age_97","Age, sex and literacy")]:
        sources.append(dict(id=table,title="First General Census of the Russian Empire, 1897, "+label,
                            publisher="Central Statistical Committee; Demoscope Weekly numeric transcription",
                            url=f"https://www.demoscope.ru/weekly/ssp/{table}.php",
                            locator="structure.csv retains table parameter reg, published scope, and original table row counting headers",
                            rights="Numeric facts from historical census; original web layout and editorial text not redistributed."))
    for name,data in [("sources.json",sources),("reconciliation.json",differences)]:
        (HERE/name).write_text(json.dumps(data,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
    with (HERE/"observations.jsonl").open("w",encoding="utf-8",newline="\n") as f:
        for row in out:f.write(json.dumps(row,ensure_ascii=False)+"\n")

if __name__=="__main__":
    build()
