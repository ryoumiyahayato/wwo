import csv
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent
def save(name,content):
    (HERE/name).write_text(content+"\n",encoding="utf8")
with (HERE/"jersey.csv").open(encoding="utf8") as f:
    facts=list(csv.DictReader(f))
rows=[]
for y,dt in [("1891","1891-04-05"),("1901","1901-03-31")]:
    if sum(int(r[y]) for r in facts[1:]) != int(facts[0][y]):
        raise ValueError("Jersey parishes")
    for r in facts:
        name=r["parish"]
        row=dict(unit_id="je_"+name.lower().replace(".","").replace(" ","_"),name=name,parent_id=None if name=="Jersey" else "je_jersey",
            kind="territory" if name=="Jersey" else "admin",date=dt,population_value=int(r[y]),region="Europe",
            source_id="jersey_census_1901",locator=f"Printed p. 20, tables 1–2, {name}, Persons, {y}",quality="primary_census",
            definition="Persons enumerated. Includes vessels in local waters and military in forts and barracks with their families.",
            method="census",mapping_status="historical_statistical_identity_only")
        if y=="1901":row["families_or_separate_occupiers"]=int(r["1901_families_or_separate_occupiers"])
        rows.append(row)
for key,name,facts in [("man","Isle of Man",[("1891-04-05",55608),("1901-03-31",54752)]),
                       ("guernsey","Guernsey, Alderney, Sark, Herm and Jethou",[("1901-03-31",43042)])]:
    for dt,value in facts:
        rows.append(dict(unit_id="crown_"+key,name=name,parent_id=None,kind="territory",date=dt,population_value=value,
              region="Europe",source_id="uk_preliminary_report_1911",locator=f"Report, Islands in the British Seas, {name.split(',')[0]}, {dt[:4]}",
              quality="official_retrospective",definition="Crown dependency, outside the three United Kingdom census divisions.",
              method="published census comparison",mapping_status="historical_statistical_identity_only"))
save("observations.jsonl","\n".join(json.dumps(x,ensure_ascii=False) for x in rows))
save("sources.json",json.dumps([
    dict(id="jersey_census_1901",title="Census, 1901 – Islands in the British Seas: Jersey",publisher="Census Office, HMSO",
         url="https://boleat.com/materials/1901.pdf",locator="Printed p. 20, Jersey tables 1 and 2 and accompanying notes",
         rights="Numeric facts transcribed from the original census page."),
    dict(id="uk_preliminary_report_1911",title="1911 Census of England and Wales, Preliminary Report",publisher="Census Office, HMSO; transcription by University of Portsmouth",
         url="https://www.visionofbritain.org.uk/census/EW1911PRE/2",locator="Report section on Islands in the British Seas",
         rights="Historical numeric facts from the report.")],ensure_ascii=False,indent=2))
