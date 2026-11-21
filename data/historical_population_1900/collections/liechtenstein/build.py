import csv
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = "li_statistisches_tabellenwerk_1960"
with (HERE/"communes.csv").open(encoding="utf8") as f:
    raw = list(csv.DictReader(f))
observations = []
for year in ["1891", "1901"]:
    if sum(int(r[year]) for r in raw[1:]) != int(raw[0][year]):
        raise ValueError("municipalities differ from national enumeration")
    for r in raw:
        root = r["name"] == "Liechtenstein"
        observations.append(dict(unit_id="li_"+r["name"].lower(), name=r["name"], parent_id=None if root else "li_liechtenstein",
             kind="country" if root else "admin", population_value=int(r[year]), date=year, source_id=SOURCE,
             locator=f"Wohnbevölkerung nach Gemeinden 1812–1958 (contents no. 8), {r['name']}, {year}",
             definition="Official historic municipality series; before 1930 the demographic balance used persons present. Enumeration day not given here.",
             method="official census retrospective", mapping_status="no_formal_polity_id", quality="official_retrospective", region="Europe"))
observations.append(dict(unit_id="li_liechtenstein", name="Liechtenstein", parent_id=None, kind="benchmark", population_value=7520,
     date="1900", source_id=SOURCE, locator="Ehe, Geburt, Tod: Jahreswerte, 1900, geschätzte mittlere Bevölkerung",
     definition="Estimated annual mean. Based on persons present in this period.", method="official estimated annual mean",
     mapping_status="no_formal_polity_id", quality="official_retrospective", region="Europe"))
(HERE/"observations.jsonl").write_text("".join(json.dumps(r,ensure_ascii=False)+"\n" for r in observations),encoding="utf8")
(HERE/"sources.json").write_text(json.dumps([dict(id=SOURCE,title="Statistisches Tabellenwerk Liechtenstein, Heft 1 (1960)",
     publisher="Amt für Statistik des Fürstentums Liechtenstein, Vaduz",locator="Wohnbevölkerung nach Gemeinden, 1812–1958; Ehe, Geburt, Tod, Jahreswerte",
     url="https://www.statistikportal.li/statistikportal/publications/101-statistisches-jahrbuch/1960/01/1/101.1960.01_01_statistisches-tabellenwerk-heft1-1960.pdf",
     rights="Numerical facts only; reference to digitized official statistical tables.")],indent=2,ensure_ascii=False)+"\n",encoding="utf8")
