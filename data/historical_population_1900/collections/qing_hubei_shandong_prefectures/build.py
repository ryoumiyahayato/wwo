"""Build the disjoint Hubei and Shandong observations from Cao's appendix."""
import csv
import json
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = "cao_qing_hubei_shandong_prefecture_reconstruction"
SHANDONG_BALANCE = "qing_hist_shandong_unlocated"

scopes_by_unit = defaultdict(list)
for province in ("hubei", "shandong"):
    with (HERE / f"cao_{province}_appendix_7.csv").open(encoding="utf-8", newline="") as stream:
        for row in csv.DictReader(stream):
            scopes_by_unit[row["opening_group_id"]].append(row)

observations = []
for unit_id, scopes in scopes_by_unit.items():
    row = scopes[0]
    unlocated = unit_id == SHANDONG_BALANCE
    name = "山东省内未定位" if unlocated else row["admin_1900_name"]
    source_labels = ", ".join(scope["source_name"] for scope in scopes)
    definition = (
        "Shandong balance for the Dengzhou and Laizhou statistical rows. The source cannot separate the "
        "leased territories or reassign Jiaozhou and its counties across the later boundary change."
        if unlocated else
        f"Author's comparable historical population reconstruction assigned to the 1900 scope {name}."
    )
    if not unlocated and row["scope_note"]:
        definition += " " + row["scope_note"]
    table = row["locator"].rsplit(", ", 1)[0]
    for year in ("1880", "1910"):
        observations.append(dict(
            unit_id=unit_id, name=name, parent_id=row["parent_unit_id"],
            date=year, kind="admin", administrative_level=2,
            population_value=sum(int(scope[f"population_{year}"]) for scope in scopes), source_id=SOURCE,
            locator=f"{table}, {year} column, {source_labels}",
            definition=definition, method="published_historical_demographic_reconstruction",
            quality="rounded_reconstruction", mapping_status="unlocated" if unlocated else "historical_statistical_area",
            geographically_unlocated=unlocated, region="Asia",
        ))

(HERE / "observations.jsonl").write_text(
    "".join(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n" for row in observations),
    encoding="utf-8",
)
